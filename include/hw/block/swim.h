/*
 * QEMU Macintosh floppy disk controller emulator (SWIM)
 *
 * Copyright (c) 2014-2018 Laurent Vivier <laurent@vivier.eu>
 *
 * This work is licensed under the terms of the GNU GPL, version 2.  See
 * the COPYING file in the top-level directory.
 *
 */

#ifndef SWIM_H
#define SWIM_H

#include "qemu/osdep.h"
#include "hw/sysbus.h"

#define MAX_FD                  2

typedef struct SWIMCtrl SWIMCtrl;

typedef struct FDrive {
    SWIMCtrl *swimctrl;
    BlockBackend *blk;
} FDrive;

#define TYPE_SWIM "swim"
#define SWIM(obj) OBJECT_CHECK(SWIMCtrl, (obj), TYPE_SWIM)

typedef struct SWIMCtrl {
    SysBusDevice parent_obj;

    MemoryRegion iomem;
    FDrive drives[MAX_FD];
    int mode;
    /* IWM mode */
    int iwm_switch;
    int regs[8];
#define IWM_PH0   0
#define IWM_PH1   1
#define IWM_PH2   2
#define IWM_PH3   3
#define IWM_MTR   4
#define IWM_DRIVE 5
#define IWM_Q6    6
#define IWM_Q7    7
    uint8_t iwm_data;
    uint8_t iwm_mode;
    /* SWIM mode */
    uint8_t swim_phase;
    uint8_t swim_mode;
} SWIMCtrl;

#endif
