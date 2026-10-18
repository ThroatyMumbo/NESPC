; Everdrive N8 Pro MCU file commands over the cart FIFO (krikzz/EDN8-PRO edio/everdrive.c).

.ifndef _EDIO_
    _EDIO_ = 1

FIFO_DATA = $40f0
FIFO_STAT = $40f1 ; bit7 set while the MCU->6502 FIFO is empty

ED_STATUS   = $10 ; > status, ED_STATUS_MARKER
ED_F_DIR_LD   = $c5 ; < options, path > status via ED_STATUS
ED_F_DIR_SIZE = $c6 ; > u16 entries of the loaded directory
ED_F_DIR_GET  = $c8 ; < u16 first, u16 count, u16 longest name > per entry: status, info, u16 length, name
DIR_GET_MAX   = 32 ; entries one ED_F_DIR_GET gives; 33 answers $82 at once
ED_F_FOPN   = $c9 ; < mode, path > status via ED_STATUS
ED_F_FRD    = $ca ; < u32 len (<= 512) > status, len bytes
ED_F_FWR    = $cc ; < u32 len, then per 1 KiB: > ack, < bytes; status via ED_STATUS
ED_F_FCLOSE = $ce
ED_F_FPTR   = $cf ; < u32 offset > status via ED_STATUS
ED_F_FINFO  = $d0 ; < path > status, info, u16 length, name
ED_F_DIR_MK = $d2 ; < path > status via ED_STATUS, FR_EXIST when it is there already
ED_F_DEL    = $d3 ; < path > status via ED_STATUS; $d7, move, answers 0 and does nothing
ED_F_FCP    = $d6 ; < mode, source path, new path > status via ED_STATUS; files only, ~3.4 MB/s
ED_F_FRD_MEM = $cb ; < u32 address, u32 length; DMA from the open file, then ED_STATUS
ED_F_FWR_MEM = $cd ; < u32 address, u32 length; DMA to the open file, then ED_STATUS
ED_MEM_RD   = $19 ; < u32 address, u32 length, ack (0 for config space) > data
ED_MEM_WR   = $1a ; < u32 address, u32 length, ack ($aa: DMA once halted), data
ED_USB_WR   = $22 ; < u16 length, data for the host
ED_MEM_SET  = $1b ; < u32 address, u32 length, value; DMA
ED_FPG_SDC  = $1f ; < u32 length of the open .rbf; reconfigures the FPGA once halted
ED_RTC_GET  = $14 ; > RTC_SIZE BCD bytes: year (from 2000), month, day, hour, minute, second
ED_RTC_SET  = $15 ; < the same, no reply

ED_SYS_INF  = $26 ; > SYS_INF_LEN bytes
SYS_INF_LEN = 64
SYS_BOOT_CTR = 28 ; its u32 power-on count

RTC_HOUR = 3
RTC_MIN  = 4
RTC_SIZE = 6

MSTAT = $40ff ; while halted: $Ax, the pending bits below clear once the MCU is done, ST_STROBE toggling
ST_UNLOCK = $01
ST_CMD_OK = $02
ST_FPG_OK = $04
ST_STROBE = $08

ED_STATUS_MARKER = $a5
ED_BAD_REPLY     = $ff ; ours: ED_STATUS answered without its marker, or the MCU never answered
ED_WAIT          = 16 ; a command's wait for its replies, in 0.5 s units, before ED_BAD_REPLY
ED_WAIT_COPY     = 255 ; ED_F_FCP's ED_STATUS reply: ~2 min, ~440 MB at its 3.4 MB/s

FA_READ  = $01
FA_WRITE = $02 ; a handle opened write-only can't read (status 9)
FA_CREATE_NEW = $04 ; FR_EXIST when it is there
FA_CREATE_ALWAYS = $08
FA_OPEN_ALWAYS = $10
FR_NO_FILE = 4
FR_NO_PATH = 5
FR_DENIED = 7 ; also a folder that isn't empty
FR_EXIST = 8

DIR_OPT_SORTED  = $01
AT_DIR = $10

; wbaEdInfo, as ed_dir_rec leaves it
FI_SIZE = 0 ; u32
FI_DATE = 4
FI_TIME = 6
FI_ATTR = 8
ED_INFO_SIZE = 9

ADDR_SCFG = $1800020 ; sys_cfg's 16 bytes: 0-9 the mapper configuration, the rest free (edn8.py)

.global ed_flush, ed_sync, ed_read, ed_fopen, ed_fseek, ed_fread, ed_fwrite, ed_fclose, ed_usb_wr, ed_cfg_rd, ed_cfg_wr
.global ed_dir_load, ed_dir_get, ed_dir_rec, ed_finfo, ed_dir_make, wbaEdInfo, ed_rtc_get, ed_rtc_set, wbaEdRtc
.global ed_cmd, ed_reply, send_str, ed_fdel
.globalzp zwEdArg, zpEdBuf, zbEdMode, zdEdOff, zpEdSrc, zbEdLen, zbEdWait

.endif
