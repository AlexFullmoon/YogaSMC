//  SPDX-License-Identifier: GPL-2.0-only
//
//  YogaISH.cpp
//  YogaSMC
//
//  Based on linux/drivers/hid/intel-ish-hid/{ipc,ishtp}
//

#include "YogaISH.hpp"

OSDefineMetaClassAndStructors(YogaISH, YogaBaseService);

#define POLL_INTERVAL_MS        10
#define FW_READY_TIMEOUT_MS     2000
#define HOST_RESET_DELAY_MS     3000
#define HOST_RESET_TIMEOUT_MS   10000
#define DMA_DISABLE_TIMEOUT_MS  100
#define CLOCK_SYNC_INTERVAL_MS  20000

static const char *stateNames[] = {
    "WaitDevice", "WaitReset", "WaitFwReady", "HbmStart", "HbmEnum", "HbmProps", "Running", "Suspended", "Failed"
};

bool YogaISH::start(IOService *provider) {
    pci = OSDynamicCast(IOPCIDevice, provider);
    if (!pci)
        return false;
    pci->retain();

    prepareDevice();

    mmio = pci->mapDeviceMemoryWithIndex(0);
    if (!mmio || mmio->getLength() < IPC_REG_MAX) {
        AlwaysLog("failed to map BAR0");
        cleanup();
        return false;
    }
    base = reinterpret_cast<volatile UInt8 *>(mmio->getVirtualAddress());
    DebugLog("FWSTS=0x%08x HOST_COMM=0x%08x PIMR=0x%08x",
             readReg(IPC_REG_ISH_HOST_FWSTS), readReg(IPC_REG_HOST_COMM), readReg(IPC_REG_PIMR));

    isPMsupported = true;
    if (!super::start(provider)) {
        cleanup();
        return false;
    }

    timer = IOTimerEventSource::timerEventSource(this,
        OSMemberFunctionCast(IOTimerEventSource::Action, this, &YogaISH::poll));
    if (!timer || workLoop->addEventSource(timer) != kIOReturnSuccess) {
        AlwaysLog("failed to add timer");
        cleanup();
        super::stop(provider);
        return false;
    }

    // poll() starts the hardware once MMIO responds
    setState(kStateWaitDevice);
    timer->setTimeoutMS(POLL_INTERVAL_MS);

    registerService();
    return true;
}

void YogaISH::stop(IOService *provider) {
    cleanup();
    super::stop(provider);
}

void YogaISH::cleanup() {
    if (timer) {
        timer->cancelTimeout();
        if (workLoop)
            workLoop->removeEventSource(timer);
        OSSafeReleaseNULL(timer);
    }
    if (base) {
        // ish_device_disable()
        if (readReg(IPC_REG_ISH_HOST_FWSTS) != 0xFFFFFFFF) {
            disableDMA();
            writeReg(IPC_REG_HOST_COMM, readReg(IPC_REG_HOST_COMM) & ~IPC_HOSTCOMM_READY_BIT);
        }
        base = nullptr;
    }
    OSSafeReleaseNULL(mmio);
    OSSafeReleaseNULL(pci);
}

void YogaISH::setState(ISHState s) {
    state = s;
    waitedMs = 0;
    DebugLog("state -> %s", stateNames[s]);
    publishStatus();
}

void YogaISH::publishStatus() {
    setProperty("State", stateNames[state]);
#ifdef DEBUG
    setProperty("FWSTS", readReg(IPC_REG_ISH_HOST_FWSTS), 32);
    setProperty("Clients", clientCount, 32);
    setProperty("ResetCount", resetCount, 32);
    setProperty("WakeCount", wakeCount, 32);
#endif
}

void YogaISH::prepareDevice() {
    UInt8 pmOffset = 0;
    if (pci->findPCICapability(kIOPCIPowerManagementCapability, &pmOffset)) {
        UInt16 pmcsr = pci->configRead16((UInt8)(pmOffset + 4));
        if (pmcsr & 3) {
            DebugLog("PMCSR 0x%04x (D%u), switching to D0", pmcsr, pmcsr & 3);
            UInt32 bar0 = pci->configRead32((UInt8)kIOPCIConfigBaseAddress0);
            UInt32 bar1 = pci->configRead32((UInt8)kIOPCIConfigBaseAddress1);
            pci->configWrite16((UInt8)(pmOffset + 4), (UInt16)(pmcsr & ~3));
            IOSleep(10);
            if (pci->configRead32((UInt8)kIOPCIConfigBaseAddress0) != bar0) {
                AlwaysLog("restoring BAR0 after D0 transition");
                pci->configWrite32((UInt8)kIOPCIConfigBaseAddress0, bar0);
                pci->configWrite32((UInt8)kIOPCIConfigBaseAddress1, bar1);
            }
        }
    }

    pci->setMemoryEnable(true);
    pci->setBusMasterEnable(true);
    // No interrupt handler: keep legacy INTx off, we poll
    pci->configWrite16((UInt8)kIOPCIConfigCommand, (UInt16)(pci->configRead16((UInt8)kIOPCIConfigCommand) | 0x400));
}

void YogaISH::hwStart() {
    clientCount = 0;
    loggedUnknownFixed = false;
    writeReg(IPC_REG_HOST_COMM, readReg(IPC_REG_HOST_COMM) | IPC_HOSTCOMM_READY_BIT);
    // Unmask as Linux does, interrupt itself is not delivered with INTx and MSI off
    writeReg(IPC_REG_PIMR, (readReg(IPC_REG_PIMR) | IPC_PIMR_INT_EN_BIT) & ~IPC_HOST2ISH_BUSYCLEAR_MASK_BIT);
    writeReg(IPC_REG_ISH_RMP2, IPC_RMP2_DMA_ENABLED);
    // Empty message wakes FW up from waiting-for-host state
    writeReg(IPC_REG_HOST2ISH_DRBL, IPC_DRBL_BUSY_BIT);
    (void)readReg(IPC_REG_ISH_HOST_FWSTS);
    setState(kStateWaitReset);
}

void YogaISH::disableDMA() {
    writeReg(IPC_REG_ISH_RMP2, 0);
    for (UInt32 ms = 0; ms < DMA_DISABLE_TIMEOUT_MS; ms += 5) {
        UInt32 fwsts = readReg(IPC_REG_ISH_HOST_FWSTS);
        if (fwsts == 0xFFFFFFFF || !(fwsts & IPC_ISH_IN_DMA))
            return;
        IOSleep(5);
    }
    AlwaysLog("timed out waiting for DMA to stop");
}

bool YogaISH::waitInputReady(UInt32 timeoutMs) {
    for (UInt32 i = 0; i < timeoutMs; i++) {
        UInt32 drbl = readReg(IPC_REG_HOST2ISH_DRBL);
        if (drbl != 0xFFFFFFFF && !(drbl & IPC_DRBL_BUSY_BIT))
            return true;
        IOSleep(1);
    }
    return false;
}

bool YogaISH::sendIPC(UInt32 doorbell, const void *payload, UInt32 length) {
    if (length > IPC_PAYLOAD_SIZE)
        return false;
    if (!waitInputReady(100)) {
        AlwaysLog("send: input not ready (HOST2ISH_DRBL=0x%08x)", readReg(IPC_REG_HOST2ISH_DRBL));
        return false;
    }
    UInt32 words[IPC_PAYLOAD_SIZE / 4] = {};
    memcpy(words, payload, length);
    for (UInt32 i = 0; i < (length + 3) / 4; i++)
        writeReg(IPC_REG_HOST2ISH_MSG + i * 4, words[i]);
    writeReg(IPC_REG_HOST2ISH_DRBL, doorbell);
    (void)readReg(IPC_REG_ISH_HOST_FWSTS);
    return true;
}

bool YogaISH::sendMng(UInt32 cmd, const void *payload, UInt32 length) {
    return sendIPC(IPC_BUILD_MNG_MSG(cmd, length), payload, length);
}

bool YogaISH::sendISHTP(UInt8 fwAddr, const void *msg, UInt32 length) {
    UInt8 buf[IPC_PAYLOAD_SIZE] = {};
    if (length + 4 > sizeof(buf))
        return false;
    // ishtp_msg_hdr: fw_addr:8 host_addr:8 length:9 reserved:6 msg_complete:1
    UInt32 hdr = fwAddr | ((length & 0x1FF) << 16) | BIT(31);
    memcpy(buf, &hdr, 4);
    memcpy(buf + 4, msg, length);
    return sendIPC(IPC_BUILD_HEADER(length + 4, IPC_PROTOCOL_ISHTP), buf, length + 4);
}

void YogaISH::syncClock() {
    uint64_t ns;
    absolutetime_to_nanoseconds(mach_absolute_time(), &ns);
    UInt64 usec = ns / 1000;
    sendMng(MNG_SYNC_FW_CLOCK, &usec, sizeof(usec));
    clockMs = 0;
}

void YogaISH::hostStart() {
    UInt8 req[4] = {HOST_START_REQ_CMD, 0, HBM_MINOR_VERSION, HBM_MAJOR_VERSION};
    setState(kStateHbmStart);
    if (!sendISHTP(0, req, sizeof(req)))
        setState(kStateFailed);
}

void YogaISH::requestNextProps() {
    for (int i = clientIndex + 1; i < 256; i++) {
        if (clientsMap[i / 8] & (1 << (i % 8))) {
            clientIndex = i;
            UInt8 req[4] = {HOST_CLIENT_PROPERTIES_REQ_CMD, (UInt8)i, 0, 0};
            if (!sendISHTP(0, req, sizeof(req)))
                setState(kStateFailed);
            return;
        }
    }

    // All properties received, ask system state client to subscribe
    AlwaysLog("ISHTP bus up, %u FW clients", clientCount);
    setState(kStateRunning);
    UInt32 query[2] = {SYSTEM_STATE_QUERY_SUBSCRIBERS, 0};
    sendISHTP(ISHTP_SYSTEM_STATE_CLIENT_ADDR, query, sizeof(query));
}

void YogaISH::handleMng(UInt32 doorbell) {
    UInt32 cmd = IPC_HEADER_GET_MNG_CMD(doorbell);
    switch (cmd) {
        case MNG_RESET_NOTIFY: {
            UInt32 resetId = readReg(IPC_REG_ISH2HOST_MSG) & 0xFFFF;
            DebugLog("MNG_RESET_NOTIFY id=%u", resetId);
            resetCount++;
            // release the doorbell before answering, as Linux does in its BH
            writeReg(IPC_REG_ISH2HOST_DRBL, 0);
            (void)readReg(IPC_REG_ISH_HOST_FWSTS);
            if (!waitInputReady(2000)) {
                AlwaysLog("FW not taking input after reset");
                setState(kStateFailed);
                return;
            }
            writeReg(IPC_REG_HOST_COMM, readReg(IPC_REG_HOST_COMM) | IPC_HOSTCOMM_READY_BIT);
            sendMng(MNG_RESET_NOTIFY_ACK, &resetId, sizeof(resetId));
            setState(kStateWaitFwReady);
            break;
        }

        case MNG_RESET_NOTIFY_ACK:
            // answer to host-initiated reset
            DebugLog("MNG_RESET_NOTIFY_ACK");
            if (state == kStateWaitReset)
                setState(kStateWaitFwReady);
            break;

        case MNG_RX_CMPL_INDICATION:
            break;

        default:
            DebugLog("MNG cmd %u", cmd);
            break;
    }
}

void YogaISH::handleHbm(const UInt8 *msg, UInt32 length) {
    switch (msg[0]) {
        case HOST_START_RES_CMD:
            DebugLog("HOST_START_RES supported=%u fw_max=%u.%u", msg[1], msg[3], msg[2]);
            if (!msg[1]) {
                AlwaysLog("HBM version %u.%u not supported by FW", HBM_MAJOR_VERSION, HBM_MINOR_VERSION);
                setState(kStateFailed);
                return;
            }
            if (state == kStateHbmStart) {
                UInt8 req[4] = {HOST_ENUM_REQ_CMD, 0, 0, 0};
                setState(kStateHbmEnum);
                sendISHTP(0, req, sizeof(req));
            }
            break;

        case HOST_ENUM_RES_CMD:
            if (length < 4 + sizeof(clientsMap) || state != kStateHbmEnum)
                break;
            memcpy(clientsMap, msg + 4, sizeof(clientsMap));
            clientCount = 0;
            for (int i = 0; i < 256; i++)
                if (clientsMap[i / 8] & (1 << (i % 8)))
                    clientCount++;
            clientIndex = -1;
            setState(kStateHbmProps);
            requestNextProps();
            break;

        case HOST_CLIENT_PROPERTIES_RES_CMD:
            if (length < 4 + 16 || state != kStateHbmProps)
                break;
            // address, status, reserved, then client properties starting with protocol GUID
            DebugLog("client %u status %u guid %02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                     msg[1], msg[2],
                     msg[7], msg[6], msg[5], msg[4], msg[9], msg[8], msg[11], msg[10],
                     msg[12], msg[13], msg[14], msg[15], msg[16], msg[17], msg[18], msg[19]);
            if (msg[2]) {
                AlwaysLog("client %u properties status %u", msg[1], msg[2]);
                setState(kStateFailed);
                return;
            }
            requestNextProps();
            break;

        default:
            DebugLog("HBM cmd 0x%02x len %u", msg[0], length);
            break;
    }
}

void YogaISH::handleFixedClient(UInt8 fwAddr, const UInt8 *msg, UInt32 length) {
    if (fwAddr != ISHTP_SYSTEM_STATE_CLIENT_ADDR || length < 4) {
        // FW periodically talks to fixed client 14, Linux ignores it as well
        if (!loggedUnknownFixed)
            DebugLog("fixed client %u msg len %u (further ones not logged)", fwAddr, length);
        loggedUnknownFixed = true;
        return;
    }

    UInt32 cmd;
    memcpy(&cmd, msg, sizeof(cmd));
    if (cmd == SYSTEM_STATE_SUBSCRIBE) {
        // ishtp_send_resume(): report S0, nothing suspended
        UInt32 status[4] = {SYSTEM_STATE_STATUS, 0, SUSPEND_STATE_BIT | CONNECTED_STANDBY_STATE_BIT, 0};
        DebugLog("system state subscribed, sending resume");
        sendISHTP(ISHTP_SYSTEM_STATE_CLIENT_ADDR, status, sizeof(status));
    } else {
        DebugLog("system state cmd 0x%x", cmd);
    }
}

void YogaISH::handleISHTP() {
    UInt32 hdr = readReg(IPC_REG_ISH2HOST_MSG);
    if (!hdr)
        return;
    UInt8 fwAddr = hdr & 0xFF;
    UInt8 hostAddr = (hdr >> 8) & 0xFF;
    UInt32 length = (hdr >> 16) & 0x1FF;
    if (length > IPC_PAYLOAD_SIZE - 4) {
        AlwaysLog("bad ISHTP length %u (hdr 0x%08x)", length, hdr);
        return;
    }

    UInt32 words[IPC_PAYLOAD_SIZE / 4] = {};
    for (UInt32 i = 0; i < (length + 3) / 4; i++)
        words[i] = readReg(IPC_REG_ISH2HOST_MSG + 4 + i * 4);
    const UInt8 *msg = reinterpret_cast<const UInt8 *>(words);

    if (!hostAddr && !fwAddr)
        handleHbm(msg, length);
    else if (!hostAddr)
        handleFixedClient(fwAddr, msg, length);
    else
        DebugLog("client msg fw %u host %u len %u", fwAddr, hostAddr, length);
}

void YogaISH::poll(IOTimerEventSource *sender) {
    if (state == kStateSuspended)
        return;

    UInt32 fwsts = readReg(IPC_REG_ISH_HOST_FWSTS);
    if (fwsts == 0xFFFFFFFF) {
        // device is not accessible (e.g. still in D3 after wake), try later
        if (state != kStateWaitDevice)
            setState(kStateWaitDevice);
        timer->setTimeoutMS(100);
        return;
    }

    if (state == kStateWaitDevice) {
        hwStart();
        timer->setTimeoutMS(POLL_INTERVAL_MS);
        return;
    }

    UInt32 pisr = readReg(IPC_REG_PISR);
    if (pisr)
        writeReg(IPC_REG_PISR, pisr);

    UInt32 doorbell = readReg(IPC_REG_ISH2HOST_DRBL);
    if (doorbell & IPC_DRBL_BUSY_BIT) {
        if (IPC_HEADER_GET_LENGTH(doorbell) <= IPC_PAYLOAD_SIZE) {
            switch (IPC_HEADER_GET_PROTOCOL(doorbell)) {
                case IPC_PROTOCOL_MNG:
                    handleMng(doorbell);
                    break;

                case IPC_PROTOCOL_ISHTP:
                    handleISHTP();
                    break;

                default:
                    DebugLog("unknown protocol, doorbell 0x%08x", doorbell);
                    break;
            }
        } else {
            AlwaysLog("bad IPC length, doorbell 0x%08x", doorbell);
        }
        // MNG_RESET_NOTIFY handler may have already released it
        if (readReg(IPC_REG_ISH2HOST_DRBL) & IPC_DRBL_BUSY_BIT) {
            writeReg(IPC_REG_ISH2HOST_DRBL, 0);
            (void)readReg(IPC_REG_ISH_HOST_FWSTS);
        }
    }

    waitedMs += POLL_INTERVAL_MS;
    clockMs += POLL_INTERVAL_MS;

    switch (state) {
        case kStateWaitFwReady:
            fwsts = readReg(IPC_REG_ISH_HOST_FWSTS);
            if ((fwsts & IPC_ILUP_BIT) && (fwsts & IPC_ISHTP_READY_BIT)) {
                DebugLog("FW ready, FWSTS=0x%08x", fwsts);
                IOSleep(300);
                syncClock();
                hostStart();
            } else if (waitedMs >= FW_READY_TIMEOUT_MS) {
                AlwaysLog("FW not ready after reset, FWSTS=0x%08x", fwsts);
                setState(kStateFailed);
            }
            break;

        case kStateWaitReset:
            if (waitedMs == HOST_RESET_DELAY_MS) {
                // FW did not start the reset flow (e.g. kept alive over sleep), request it like _ish_ipc_reset()
                UInt32 resetPayload = 1; // reset_id = 1, reserved = 0
                DebugLog("no MNG_RESET_NOTIFY (FWSTS=0x%08x), sending host reset", fwsts);
                writeReg(IPC_REG_ISH2HOST_DRBL, 0);
                sendMng(MNG_RESET_NOTIFY, &resetPayload, sizeof(resetPayload));
            } else if (waitedMs == HOST_RESET_TIMEOUT_MS) {
                AlwaysLog("no reset response from FW, FWSTS=0x%08x", fwsts);
                setState(kStateFailed);
            }
            break;

        case kStateRunning:
            if (clockMs >= CLOCK_SYNC_INTERVAL_MS)
                syncClock();
            break;

        default:
            break;
    }

    timer->setTimeoutMS(POLL_INTERVAL_MS);
}

void YogaISH::powerGated(bool *on) {
    if (!*on) {
        if (state == kStateSuspended)
            return;
        timer->cancelTimeout();
        if (readReg(IPC_REG_ISH_HOST_FWSTS) != 0xFFFFFFFF) {
            if (state == kStateRunning) {
                // ishtp_send_suspend()
                UInt32 status[4] = {SYSTEM_STATE_STATUS, 0,
                                    SUSPEND_STATE_BIT | CONNECTED_STANDBY_STATE_BIT,
                                    SUSPEND_STATE_BIT | CONNECTED_STANDBY_STATE_BIT};
                sendISHTP(ISHTP_SYSTEM_STATE_CLIENT_ADDR, status, sizeof(status));
                waitInputReady(25);
            }
            // otherwise FW resets on its own when put into D3
            disableDMA();
        }
        setState(kStateSuspended);
    } else {
        if (state != kStateSuspended)
            return;
        // FW is rebooted after S3, so go through the whole init again;
        // if it was kept alive, the host reset in WaitReset handles it
        wakeCount++;
        prepareDevice();
        setState(kStateWaitDevice);
        timer->setTimeoutMS(POLL_INTERVAL_MS);
    }
}

IOReturn YogaISH::setPowerState(unsigned long powerStateOrdinal, IOService *whatDevice) {
    if (super::setPowerState(powerStateOrdinal, whatDevice) != kIOPMAckImplied)
        return kIOReturnInvalid;

    if (!timer)
        return kIOPMAckImplied;

    DebugLog("setPowerState %ld", powerStateOrdinal);
    bool on = (powerStateOrdinal != 0);
    commandGate->runAction(OSMemberFunctionCast(IOCommandGate::Action, this, &YogaISH::powerGated), &on);
    return kIOPMAckImplied;
}
