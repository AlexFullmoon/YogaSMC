//  SPDX-License-Identifier: GPL-2.0-only
//
//  YogaISH.hpp
//  YogaSMC
//
//  Minimal host for Intel Integrated Sensor Hub. On convertibles like
//  ThinkPad X1 Yoga Gen 5 the ISH firmware calculates the hinge posture and
//  reports it to EC (CMMD / GMMS) only while a host driver is present.
//  Brings up IPC and ISHTP bus (HBM) without any HID client, polling instead
//  of interrupts.
//

#ifndef YogaISH_hpp
#define YogaISH_hpp

#include <IOKit/IOTimerEventSource.h>
#include <IOKit/pci/IOPCIDevice.h>
#include "YogaBaseService.hpp"

// from linux/drivers/hid/intel-ish-hid/ipc/hw-ish-regs.h, BXT and later layout

#define IPC_REG_PIMR            0x08
#define IPC_REG_PISR            0x0C
#define IPC_REG_ISH_HOST_FWSTS  0x34
#define IPC_REG_HOST_COMM       0x38
#define IPC_REG_HOST2ISH_DRBL   0x48
#define IPC_REG_ISH2HOST_DRBL   0x54
#define IPC_REG_ISH2HOST_MSG    0x60
#define IPC_REG_HOST2ISH_MSG    0xE0
#define IPC_REG_ISH_RMP2        0x368
#define IPC_REG_MAX             0x400

#define IPC_DRBL_BUSY_BIT               BIT(31)
#define IPC_HOSTCOMM_READY_BIT          BIT(7)
#define IPC_PIMR_INT_EN_BIT             BIT(0)
#define IPC_HOST2ISH_BUSYCLEAR_MASK_BIT BIT(8)
#define IPC_ILUP_BIT                    BIT(0)
#define IPC_ISHTP_READY_BIT             BIT(1)
#define IPC_ISH_IN_DMA                  (0xFU << 16)
#define IPC_RMP2_DMA_ENABLED            0x1

#define IPC_HEADER_GET_LENGTH(d)        ((d) & 0x3FF)
#define IPC_HEADER_GET_PROTOCOL(d)      (((d) >> 10) & 0xF)
#define IPC_HEADER_GET_MNG_CMD(d)       (((d) >> 16) & 0xF)
#define IPC_BUILD_HEADER(len, proto)    (IPC_DRBL_BUSY_BIT | ((proto) << 10) | (len))
#define IPC_BUILD_MNG_MSG(cmd, len)     (IPC_DRBL_BUSY_BIT | (IPC_PROTOCOL_MNG << 10) | ((cmd) << 16) | (len))

#define IPC_PROTOCOL_ISHTP      1
#define IPC_PROTOCOL_MNG        3
#define IPC_PAYLOAD_SIZE        128

#define MNG_RX_CMPL_INDICATION  2
#define MNG_RESET_NOTIFY        3
#define MNG_RESET_NOTIFY_ACK    4
#define MNG_SYNC_FW_CLOCK       5

// from linux/drivers/hid/intel-ish-hid/ishtp/hbm.h

#define HOST_START_REQ_CMD              0x01
#define HOST_START_RES_CMD              0x81
#define HOST_ENUM_REQ_CMD               0x04
#define HOST_ENUM_RES_CMD               0x84
#define HOST_CLIENT_PROPERTIES_REQ_CMD  0x05
#define HOST_CLIENT_PROPERTIES_RES_CMD  0x85
#define HBM_MAJOR_VERSION               1
#define HBM_MINOR_VERSION               0

#define ISHTP_SYSTEM_STATE_CLIENT_ADDR  13
#define SYSTEM_STATE_SUBSCRIBE          0x1
#define SYSTEM_STATE_STATUS             0x2
#define SYSTEM_STATE_QUERY_SUBSCRIBERS  0x3
#define CONNECTED_STANDBY_STATE_BIT     BIT(0)
#define SUSPEND_STATE_BIT               BIT(1)

class YogaISH : public YogaBaseService
{
    typedef YogaBaseService super;
    OSDeclareDefaultStructors(YogaISH)

    enum ISHState : UInt32 {
        kStateWaitDevice = 0,   // waiting for MMIO to become accessible, then start
        kStateWaitReset,        // waiting for FW-initiated MNG_RESET_NOTIFY
        kStateWaitFwReady,      // ACK sent, waiting for ILUP & ISHTP_READY
        kStateHbmStart,         // HOST_START_REQ sent
        kStateHbmEnum,          // HOST_ENUM_REQ sent
        kStateHbmProps,         // walking client properties
        kStateRunning,          // HBM done, system state client handled
        kStateSuspended,        // system sleep, DMA disabled
        kStateFailed
    };

    IOPCIDevice *pci {nullptr};
    IOMemoryMap *mmio {nullptr};
    volatile UInt8 *base {nullptr};
    IOTimerEventSource *timer {nullptr};

    ISHState state {kStateWaitDevice};
    UInt32 waitedMs {0};
    UInt32 clockMs {0};
    UInt8 clientsMap[32] {};
    int clientIndex {-1};
    UInt32 clientCount {0};
    UInt32 resetCount {0};
    UInt32 wakeCount {0};
    bool loggedUnknownFixed {false};

    inline UInt32 readReg(UInt32 off) { return *reinterpret_cast<volatile UInt32 *>(base + off); }
    inline void writeReg(UInt32 off, UInt32 val) { *reinterpret_cast<volatile UInt32 *>(base + off) = val; }

    void setState(ISHState s);
    void publishStatus();

    /**
     *  Put the function into D0 and enable memory decoding and bus mastering
     */
    void prepareDevice();

    /**
     *  Set host ready and wake FW, which then starts its reset flow (ish_hw_start)
     */
    void hwStart();

    /**
     *  Stop ISH DMA, needed before D3 (ish_disable_dma)
     */
    void disableDMA();

    bool waitInputReady(UInt32 timeoutMs);
    bool sendIPC(UInt32 doorbell, const void *payload, UInt32 length);
    bool sendMng(UInt32 cmd, const void *payload, UInt32 length);
    bool sendISHTP(UInt8 fwAddr, const void *msg, UInt32 length);
    void syncClock();

    void hostStart();
    void requestNextProps();
    void handleMng(UInt32 doorbell);
    void handleISHTP();
    void handleHbm(const UInt8 *msg, UInt32 length);
    void handleFixedClient(UInt8 fwAddr, const UInt8 *msg, UInt32 length);

    void poll(IOTimerEventSource *sender);
    void powerGated(bool *on);
    void cleanup();

public:
    virtual bool start(IOService *provider) APPLE_KEXT_OVERRIDE;
    virtual void stop(IOService *provider) APPLE_KEXT_OVERRIDE;
    virtual IOReturn setPowerState(unsigned long powerStateOrdinal, IOService * whatDevice) APPLE_KEXT_OVERRIDE;
};

#endif /* YogaISH_hpp */
