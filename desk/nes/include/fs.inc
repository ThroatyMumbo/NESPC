; Desk's files on the SD card: sdfile.s's held file and scratch blocks, and the status codes past FatFs's.

.ifndef _FS_
    _FS_ = 1

BLOCK_SIZE = 1024
PATH_MAX   = 254 ; letters of a browser path, wbaPath

; listing row types (browser.s R_TYPE)
S_IFDIR = $40
S_IFREG = $80

; volumes of the browser's root (browser.s wbVol), 0 for the root itself
VOL_SD    = 1
VOL_COUNT = 1 ; the fake directories at the root: sd

HOLD_NONE = 0 ; sdfile.s zbHeld: whose file is open
HOLD_VIEW = 1
HOLD_DX   = 2

; status codes above the MCU's FatFs range
FS_E_FIRST  = $ef
FS_E_LINK   = $ef ; a .lnk without a target Desk can follow
FS_END      = $f0 ; no entry after the last
FS_E_EXIST  = $f1 ; a paste's name and its " - Copy" are both taken, or a rename's
FS_E_INSIDE = $f2 ; a folder pasted into itself
FS_E_NOTDIR = $f3
FS_E_NOTEMPTY = $f4
FS_E_GONE   = $f5 ; the entry no longer exists
FS_E_NAME   = $f6 ; a rename to a name FAT can't hold
FS_E_BIN    = $f7 ; recycling the bin, its origins' folder or a folder holding either
FS_E_BIG    = $f8 ; program larger than its bank
FS_E_EXEC   = $f9 ; program built for another format or API version
FS_E_RDONLY = $fa ; the root's volumes
FS_E_NOTROM = $fb ; no iNES header, or one Desk can't size
FS_E_NOCORE = $fc ; no sibling .rbf and no EDN8/MAPS core for the mapper
FS_E_NOAPP  = $fd ; a program in nespc/system (clock.dx, display.dx) isn't installed
FS_E_LONG   = $fe ; a path longer than Desk can pass on

; the clipboard (fileops.s clip_set)
CLIP_CUT = $01
CLIP_ALL = $02 ; every entry of the folder
CLIP_ON  = $80

; what a long operation is doing, for browser.s op_note
FOP_COPY = 0
FOP_MOVE = 1
FOP_DEL  = 2
FOP_RECYCLE = 3
FOP_RESTORE = 4

; rec_file's descriptor: .addr path, .byte its length, .addr buffer, .byte its length
.macro REC_FILE path, path_len, buf, buf_len
    .addr path
    .byte path_len
    .addr buf
    .byte buf_len
.endmacro
REC_PATH = 0
REC_BUF  = 3

.global sd_release, sd_hold, sd_read, rec_file, ed_fio, is_lnk, is_dx, wbaBlkData
.global dir_scan, scan_dx_lnk, wpScanHook, wbScanMax, wbScanSlot, wbScanCap
.globalzp zpScanTo
.global wbaPath, wbaName, wbaEdit, op_note
.global clip_set, clip_any, paste_go, del_go, ren_go, bin_go, restore_go, bin_del, bin_make
.globalzp zbHeld, zbHoldId, zwBlk, zwBlkLen
ROM_PATH = wbaBlkData + BLOCK_SIZE ; a ROM's MCU path held for launch_prep, clear of the data block

.endif
