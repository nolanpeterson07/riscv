/*-----------------------------------------------------------------------*/
/* Low level disk I/O module SKELETON for FatFs     (C)ChaN, 2025        */
/*-----------------------------------------------------------------------*/
/* If a working storage control module is available, it should be        */
/* attached to the FatFs via a glue function rather than modifying it.   */
/* This is an example of glue functions to attach various exsisting      */
/* storage control modules to the FatFs module with a defined API.       */
/*-----------------------------------------------------------------------*/

#include "ff.h"
#include "diskio.h"
#include "sdspi.h"

static DSTATUS stat = STA_NOINIT;

DSTATUS disk_status(BYTE pdrv) {
    return pdrv ? STA_NOINIT : stat;
}

DSTATUS disk_initialize(BYTE pdrv) {
    if (pdrv == 0 && sdspi_init(SDSPI) == 0)
        stat = 0;
    return disk_status(pdrv);
}

DRESULT disk_read(BYTE pdrv, BYTE *buff, LBA_t sector, UINT count) {
    if (disk_status(pdrv))
        return RES_NOTRDY;
    for (; count; count--, sector++, buff += 512)
        if (sdspi_read_block(SDSPI, sector, buff) != 0)
            return RES_ERROR;
    return RES_OK;
}

DRESULT disk_write(BYTE pdrv, const BYTE *buff, LBA_t sector, UINT count) {
    if (disk_status(pdrv))
        return RES_NOTRDY;
    for (; count; count--, sector++, buff += 512)
        if (sdspi_write_block(SDSPI, sector, buff) != 0)
            return RES_ERROR;
    return RES_OK;
}

DRESULT disk_ioctl(BYTE pdrv, BYTE cmd, void *buff) {
    (void)buff;
    if (disk_status(pdrv))
        return RES_NOTRDY;
    if (cmd == CTRL_SYNC)
        return sdspi_sync(SDSPI) == 0 ? RES_OK : RES_ERROR;
    return RES_PARERR;
}
