; The shell: the mode loop, the desktop's and taskbar's input, the Files window's listings of /sd, its text viewer,
; programs, launches and the state file.

.include "desk.inc"
.include "fs.inc"
.include "edio.inc"
.include "launch.inc"
.include "paths.inc"
.include "saver.inc"
.include "colors.inc"
.include "keyboard/adapter.inc"

HIT_NONE  = 0 ; hit_test results, indexes into the click tables
HIT_CLOSE = 1
HIT_MIN   = 2
HIT_ZOOM  = 3
HIT_BACK  = 4 ; BACK, FWD, UP, ROOT in toolbar order
HIT_PREV  = 8
HIT_NEXT  = 9
HIT_TASK  = 10 ; the window's taskbar button
HIT_CLOCK = 11 ; the taskbar's clock
HIT_START = 12

REC_SIZE   = 32 ; wbaRec, one per listed row
R_TYPE     = 0  ; S_IFDIR or S_IFREG
R_SIZE     = 1  ; u32
R_SLOT     = 3  ; a volume's row at the root: its VOL_*
R_NAME     = 5  ; the name cut to SD_NAME_MAX, and a NUL
SD_NAME_MAX = REC_SIZE - R_NAME - 1
SD_LEN     = 2  ; "sd", the SD card's directory in the root, which links point into
LNK_MAX   = 512 ; bytes of a .lnk read for its first line
HIST_MAX   = 16
HIST_POOL  = 1024 ; paths of the history entries, oldest first
; the state file: "DST4", these fields, then the window's path and the program's
ST_ZOOM    = 4    ; zbZoom
ST_TOP     = 5    ; zwTop
ST_DISC    = 7    ; 0, kept for the record's layout
ST_LEN     = 8    ; the window's path length, 0 for the desktop
ST_DX      = 9    ; the program's path length, 0 for none
ST_ARG     = 10   ; its K_RESUME byte
ST_SAVER   = 11   ; the screensaver, background and window colors shown
ST_DESK    = ST_SAVER + SS_LEN
ST_COLORS  = ST_DESK + BD_LEN
ST_SIZE    = ST_COLORS + SC_LEN
SEL_NONE   = 0 ; wbSel
SEL_ONE    = 1 ; entry wwSel
SEL_ALL    = 2 ; every entry of the folder
DBL_FRAMES = 30 ; a second press on an entry this soon opens it
NAME_MAX   = 255 ; a rename's letters
ESC        = $1b
KEY_UP     = $80 ; key_poll's VT keys, rbaCsiEnd's order
KEY_DOWN   = $81
KEY_DEL    = $82
KEY_PGUP   = $83
KEY_PGDN   = $84
KEY_F2     = $85
KEY_SDEL   = $86 ; Shift+Del
ACT_OPEN   = 0 ; the listing's right-click menu, keys and buttons
ACT_CUT    = 1
ACT_COPY   = 2
ACT_RENAME = 3
ACT_DELETE = 4
ACT_PASTE  = 5
ACT_RESTORE = 6
ACT_EMPTY  = 7
ASK_BIN    = 0 ; wbAskOp: into the recycle bin
ASK_DEL    = 1 ; deleted for good
ASK_BINDEL = 2 ; deleted for good from the bin, origins too
ASK_EMPTY  = 3 ; the bin emptied
ASK_RESTORE = 4 ; no prompt, sel_op's

.segment "ZEROPAGE"

zbMode:    .res 1
zbPathLen: .res 1
zbOldLen:  .res 1 ; zbPathLen before sd_push_name
zbFileLen: .res 1 ; path length with the viewed file's name, kept in wbaPath past zbPathLen
zwCount:   .res 2
zwTop:     .res 2
zwWalk:    .res 2
zbShown:   .res 1
zbI:       .res 1
zbT:       .res 1
zbAsk:     .res 1 ; row the prompt is for
zbTextCol: .res 1
zbErr:     .res 1 ; read error to show once the page is drawn
zpRec:     .res 2
zpSrc:     .res 2
zpDst:     .res 2
zwNext:    .res 2 ; the viewed file's next block
zdLeft:    .res 4 ; bytes of it not yet in wbaBlkData
zdSize:    .res 4
zwPos:     .res 2
zwLen:     .res 2
zbViewPage: .res 1 ; pages of the file laid out so far
zbWant:    .res 1
zbDry:     .res 1 ; show_text lays out without drawing
zbRelY:    .res 1 ; hit_test: the pointer from the window's top left
zbRelX:    .res 1
zbThumb:   .res 1 ; body row of the scroll thumb, $ff for none
zbUpTile:  .res 1 ; T_SB_* pictures of the scroll bar's ends
zbDownTile: .res 1
zbPages:   .res 1
zbPageIdx: .res 1
zbClosed:  .res 1 ; the icon reopens at the Files folder
zbHidMode: .res 1 ; zbMode to bring back with a minimized window
zbLen:     .res 1
zbaTool:   .res 4 ; toolbar picture of each button, lit or grayed
zpTitle:   .res 2 ; title_text's string
zbTitleLen: .res 1
zbSlash:   .res 1 ; title_text puts "/" before a string that fits

.segment "WRAM" ; fileops.s, in another bank, reads and writes these

wbaPath: .res 256
wbaRec:  .res BODY_H_MAX * REC_SIZE
wbaName: .res 256 ; whole name of an SD card entry
wbaEdit: .res NAME_MAX ; a rename's new name, which fileops.s takes

.segment "SHELL_BSS"

wbaHistTopL: .res HIST_MAX
wbaHistTopH: .res HIST_MAX
wbaHistLen:  .res HIST_MAX ; length of each entry's path in wbaHistPool, 0 for the root
wbaHistPool: .res HIST_POOL
wbHistPos: .res 1
wbHistLen: .res 1
wbVol: .res 1 ; VOL_* listed, wbaPath starting with its name; 0 at the root
wbRow: .res 1 ; page row list_open opened
wbRetMode: .res 1 ; MODE_LIST, MODE_VIEW or MODE_ICON for the window once its program ends
wbMenuRet: .res 1 ; zbMode under the Start menu
wbPopRet: .res 1 ; zbMode under a right-click menu
wwPopGo:   .res 2 ; where its pick goes, less one, with the item in A
wbaAppTitle: .res APP_TITLE_LEN ; the running program's
wbaAppPath: .res 256 ; ...and its path, which the Start menu and desktop scans don't reuse as they do wbaDxPath's
wbAppPathLen: .res 1
wbWinTile: .res 1 ; first sprite tile of its icon
wbaWinPal: .res 4
wbaState:  .res ST_SIZE ; the state file's record, its path in wbaPath
wbaPtr:    .res PTR_SIZE ; the pointer file's
wbPtrMenu: .res 1 ; PTR_MENU: the app came back by its Menu button
wbLinkLen: .res 1 ; the link target's in wbaName
wbKey:    .res 1 ; key_poll's this frame, 0 for none
wbCsiP:    .res 1 ; a VT sequence's first parameter byte
wbCsiLast: .res 1 ; its last, a modifier after ";"
wbCsiEnd:  .res 1 ; and its final byte
wbAskOp:   .res 1 ; ASK_*
wbSel:     .res 1 ; SEL_*
wwSel:     .res 2
wwHit:     .res 2 ; the entry sel_set and sel_go select
wbOldRow:  .res 1
wbDrawRow: .res 1
wwClick:   .res 2 ; the entry the last press selected, for a double click
wbClickAt: .res 1 ; zbFrame then
wbClickOk: .res 1 ; 1 while a second press may open it
wbaPopAct: .res POP_MAX ; ACT_* of each right-click item
wbClipFlags: .res 1
wbEditLen: .res 1
wbEditRow: .res 1
wbCol:     .res 1

.segment "RODATA"

rsState:  .byte NESPC_SYSTEM, "state"
STATE_NAME_LEN = * - rsState
rsStateMagic: .byte "DST4"
STATE_MAGIC_LEN = * - rsStateMagic
rbaZero:  .res STATE_MAGIC_LEN, 0
rsPointer: .byte NESPC_POINTER
POINTER_NAME_LEN = * - rsPointer
rbaPtrRec: REC_FILE rsPointer, POINTER_NAME_LEN, wbaPtr, PTR_SIZE
rsVols: ; the root's directory for each volume
rsSd:     .asciiz "sd"
rbaVolOff: .byte rsSd - rsVols ; by VOL_* - 1
rbaVolLen: .byte rbaVolOff - rsSd - 1
.assert VOL_SD = 1 && VOL_COUNT = 1, error, "rbaVolOff's order"
rsHome:   .byte "sd/", NESPC_DIR ; where the Files icon opens
HOME_LEN = * - rsHome
rsBinPath: .byte "sd/", NESPC_TRASH
BIN_PATH_LEN = * - rsBinPath
rsPopOpen: .asciiz "Open"
rsPopCut: .asciiz "Cut"
rsPopCopy: .asciiz "Copy"
rsPopRename: .asciiz "Rename"
rsPopDelete: .asciiz "Delete"
rsPopPaste: .asciiz "Paste"
rsPopRestore: .asciiz "Restore"
rsPopEmpty: .asciiz "Empty Trash"
rbaActL: .byte <rsPopOpen, <rsPopCut, <rsPopCopy, <rsPopRename, <rsPopDelete, <rsPopPaste, <rsPopRestore, <rsPopEmpty
rbaActH: .byte >rsPopOpen, >rsPopCut, >rsPopCopy, >rsPopRename, >rsPopDelete, >rsPopPaste, >rsPopRestore, >rsPopEmpty
.assert ACT_RESTORE = 6 && ACT_EMPTY = 7, error, "rbaActL's order"
rsCopying: .asciiz "copying "
rsMoving:  .asciiz "moving "
rsDeleting: .asciiz "deleting "
rsRecycling: .asciiz "trashing "
rsRestoring: .asciiz "restoring "
rbaOpL: .byte <rsCopying, <rsMoving, <rsDeleting, <rsRecycling, <rsRestoring ; by FOP_*
rbaOpH: .byte >rsCopying, >rsMoving, >rsDeleting, >rsRecycling, >rsRestoring
.assert FOP_COPY = 0 && FOP_MOVE = 1 && FOP_DEL = 2 && FOP_RECYCLE = 3 && FOP_RESTORE = 4, error, "rbaOpL's order"
rsEditHint: .asciiz "Enter saves, Esc cancels"
rbaBadName: .byte "/\:*?", $22, "<>|" ; letters FAT names can't hold
BAD_NAME_N = * - rbaBadName
rbaCsiEnd: .byte "AB~~~Q~" ; a VT sequence's final byte, first parameter and last, KEY_UP on
rbaCsiArg: .byte 0, 0, "356", 0, "3"
rbaCsiLast: .byte 0, 0, "356", 0, "2" ; xterm's ";2" for Shift
CSI_N = * - rbaCsiLast
.assert KEY_SDEL - KEY_UP + 1 = CSI_N, error, "rbaCsiEnd's keys"
rbaListKey: .byte $01, $03, $18, $16, KEY_DEL, KEY_F2, $0d, $08, ESC, KEY_UP, KEY_DOWN, KEY_PGUP, KEY_PGDN, KEY_SDEL
LIST_KEY_N = * - rbaListKey
rsSlash: .byte "/"
rsError:  .asciiz "error $"
rsDelete: .asciiz "delete "
rsRecycle: .asciiz "trash "
rsEmptyBin: .asciiz "empty the Trash"
rbaAskL:  .byte <rsRecycle, <rsDelete, <rsDelete, <rsEmptyBin ; by ASK_*
rbaAskH:  .byte >rsRecycle, >rsDelete, >rsDelete, >rsEmptyBin
.assert ASK_BIN = 0 && ASK_DEL = 1 && ASK_BINDEL = 2 && ASK_EMPTY = 3, error, "rbaAskL's order"
rsAsk:    .asciiz "? A/B"
ASK_LEN = * - rsAsk - 1
rsItems:  .asciiz " items"
rsBytes:  .asciiz " bytes"
rsPage:   .asciiz "page "
rsClock:  .byte NESPC_SYSTEM, "clock.dx"
CLOCK_LEN = * - rsClock
rsDisplay: .byte NESPC_SYSTEM, "display.dx"
DISPLAY_LEN = * - rsDisplay
rsPopProps: .asciiz "Properties"
rsPopClose: .asciiz "Close"

rsErrLink:    .asciiz "bad shortcut"
rsErrBin:      .asciiz "can't trash the Trash"
rsErrNotDir:   .asciiz "not a directory"
rsErrNotEmpty: .asciiz "folder not empty"
rsErrGone:     .asciiz "entry is gone"
rsErrBig:      .asciiz "program over 16 KB"
rsErrExec:     .asciiz "not a program for this Desk"
rsErrRdonly:   .asciiz "read-only"
rsErrNotRom:   .asciiz "not a ROM Desk can load"
rsErrNoCore:   .asciiz "no core for its mapper"
rsErrNoApp:    .asciiz "system program missing"
rsErrLong:     .asciiz "path too long"
rsErrExist:    .asciiz "already exists"
rsErrInside:   .asciiz "can't paste into itself"
rsErrName:     .asciiz "not a valid name"

rwaErrors: ; FS_E_FIRST on, FS_END as a name that's gone
.word rsErrLink, rsErrGone
.word rsErrExist, rsErrInside, rsErrNotDir, rsErrNotEmpty, rsErrGone, rsErrName, rsErrBin
.word rsErrBig, rsErrExec, rsErrRdonly, rsErrNotRom, rsErrNoCore, rsErrNoApp, rsErrLong
.assert (* - rwaErrors) / 2 = FS_E_LONG - FS_E_FIRST + 1, error, "an error code without its text"
.assert FS_E_LINK = FS_E_FIRST && FS_END = FS_E_LINK + 1 && FS_E_EXIST = FS_END + 1 && FS_E_NOTDIR = FS_END + 3, error, "rwaErrors' order"
.assert FS_E_NAME = FS_END + 6 && FS_E_BIN = FS_END + 7, error, "rwaErrors' order"

rwaMode: ; by MODE_*, for rts
.word boot - 1, list_update - 1, view_update - 1, ask_update - 1, icon_update - 1, edit_update - 1, app_update - 1
.word menu_mode - 1, popup_mode - 1
.assert MODE_START = 0 && MODE_LIST = 1 && MODE_VIEW = 2 && MODE_ASK = 3 && MODE_ICON = 4, error, "rwaMode's order"
.assert MODE_EDIT = 5 && MODE_APP = 6 && MODE_MENU = 7 && MODE_POPUP = 8, error, "rwaMode's order"

rwaListKey: ; by rbaListKey, for rts
.word sel_all - 1, act_copy - 1, act_cut - 1, act_paste - 1, list_ask - 1, edit_start - 1, act_open - 1
.word list_up - 1, sel_clear - 1, sel_up - 1, sel_down - 1, list_prev - 1, list_down - 1, list_kill - 1
.assert (* - rwaListKey) / 2 = LIST_KEY_N, error, "a key without its action"

rwaAct: ; by ACT_*, for rts
.word act_open - 1, act_cut - 1, act_copy - 1, edit_start - 1, list_ask - 1, act_paste - 1, act_restore - 1
.word act_empty - 1

rwaListClick: ; by HIT_*, for rts
.word list_press - 1, win_close - 1, win_min - 1, win_zoom - 1
.word hist_back - 1, hist_fwd - 1, list_up - 1, go_root - 1, list_prev - 1, list_down - 1, win_min - 1
.word clock_open - 1, start_open - 1

rwaViewClick:
.word no_op - 1, win_close - 1, win_min - 1, win_zoom - 1
.word load_dir - 1, no_op - 1, load_dir - 1, go_root - 1, view_prev - 1, show_text - 1, win_min - 1
.word clock_open - 1, start_open - 1

rwaAppClick:
.word no_op - 1, win_close - 1, win_min - 1, win_zoom - 1
.word app_quit - 1, no_op - 1, no_op - 1, no_op - 1, no_op - 1, no_op - 1, win_min - 1
.word clock_open - 1, start_open - 1

.segment "SHELL"
.assert .bank(browser_update) = SHELL_BANK, lderror, "desk.inc's SHELL_BANK is not conf/ld.cfg's"

.proc browser_update
    jsr win_icon_sync
    lda zbMode
    cmp #MODE_START ; the taskbar's icons come with the boot
    beq :+
    jsr task_sync
:   jsr key_poll ; taken in every mode, so a stale key can't act on the next screen
    sta wbKey
    jsr Adapter::sys ; taken in every mode, so a stale Alt+F4 can't close the next program
    bcs mode_update
    cmp #Adapter::SYS_START
    bne :+
    jmp start_key
:   cmp #Adapter::SYS_CLOSE
    bne mode_update
    lda zbMode
    cmp #MODE_APP
    bne mode_update
    jmp app_quit
.endproc

; the frame's pad and pointer to the screen zbMode shows
.proc mode_update
    jsr task_press
    bcc :+
    rts
:   lda zbMode
    rts_jump rwaMode
.endproc


; B on a taskbar button over the screens that show the bar live: its right-click menu, Close
; > C set when it opened
.proc task_press
    lda zbPadNew
    and #JOYPAD_B
    beq no
    lda zbMode
    cmp #MODE_LIST
    beq bar
    cmp #MODE_VIEW
    beq bar
    cmp #MODE_ICON
    beq bar
    cmp #MODE_APP
    bne no
bar:
    jsr pointer_px
    jsr task_hit
    bcc no
    lda #<rsPopClose
    sta wbaPopL
    lda #>rsPopClose
    sta wbaPopH
    lda #1
    sta wbPopN
    lda #<(task_close - 1)
    ldx #>(task_close - 1)
    jsr popup_start
    sec
    rts
no:
    clc
    rts
.endproc


; Close on the window's taskbar button
.proc task_close
    lda zbMode
    cmp #MODE_ICON
    bne :+
    lda zbHidMode ; minimized: closed as from the screen it hides
    sta zbMode
:   jmp win_close
.endproc


; reset: the desktop with the window closed, or the folder and program a launch left in the state file
.proc boot
    jsr pointer_busy
    jsr ptr_load
    jsr home_reset
    far desk_scan
    jsr jingle_boot
    jsr state_load
    bcc desktop
    jsr state_live
    lda wbaState + ST_LEN
    beq desktop
    jsr state_restore
    jmp program
desktop:
    lda #MODE_ICON
    sta zbMode
    lda #MODE_LIST
    sta zbHidMode
    jsr redraw_screen
    jsr pointer_idle
program:
    jsr state_program
    lda wbPtrMenu
    beq done
    jmp start_key
done:
    rts
.endproc

; the program the state file kept, open again
.proc state_program
    lda wbaState + ST_DX
    beq done
    lda wbaState + ST_ARG
    sta wbResume
    jsr pointer_busy
    lda #<wbaDxPath
    ldx #>wbaDxPath
    ldy wbaState + ST_DX
    jsr dx_path
    jsr dx_open
    bne fail
    jmp app_run
fail:
    jsr backdrop_revert
    clc
    jsr pal_show
    jsr redraw_screen
    jmp pointer_idle
done:
    rts
.endproc

; the choices the state file's program showed and didn't keep, shown again before anything is drawn
.proc state_live
    lda wbaState + ST_DX
    beq done
    lda #<(wbaState + ST_COLORS)
    ldx #>(wbaState + ST_COLORS)
    jsr scheme_put
    lda #<(wbaState + ST_DESK)
    ldx #>(wbaState + ST_DESK)
    jsr backdrop_put
    clc
    jmp pal_show
done:
    rts
.endproc


; the window at sd/nespc, the Files icon's folder, with no history before it
.proc home_reset
    ldx #HOME_LEN
    stx zbPathLen
:   lda rsHome - 1, x
    sta wbaPath - 1, x
    dex
    bne :-
    lda #VOL_SD
    sta wbVol
    jmp hist_reset
.endproc


.proc list_update
    lda Adapter::wbMouseWheel ; a page a frame it turns, as the scroll bar's arrows step
    beq pad
    bmi :+
    jmp list_down
:   jmp list_prev
pad:
    lda zbPadNew
    asl
    bcs click
    asl
    bcs menu
    asl
    bcs ask
    asl
    bcs next
    lda wbKey
    bne key
    rts
click:
    jsr hit_test
    rts_jump rwaListClick
menu:
    jmp list_menu
ask:
    jmp list_ask
next:
    jmp list_next
key:
    ldx #LIST_KEY_N - 1
:   cmp rbaListKey, x
    beq hit
    dex
    bpl :-
    rts
hit:
    txa
    rts_jump rwaListKey
.endproc


; > A = the next key from the adapter, ESC alone, KEY_* for the VT keys it sends as ESC sequences; 0 for none or
; one Desk doesn't take (Alt+key); a sequence comes whole within a frame (Adapter::adapter)
.proc key_poll
    jsr key_next
    bcs none
    cmp #ESC
    bne done
    jsr key_next
    bcs esc
    cmp #'['
    beq csi
    cmp #'O'
    bne none
csi:
    lda #0
    sta wbCsiP
    sta wbCsiLast
param:
    jsr key_next
    bcs none
    cmp #$40 ; parameters until a final byte
    bcs final
    sta wbCsiLast
    ldx wbCsiP
    bne param
    sta wbCsiP
    jmp param
final:
    sta wbCsiEnd
    ldx #CSI_N - 1
find:
    lda rbaCsiEnd, x
    cmp wbCsiEnd
    bne :+
    lda rbaCsiArg, x
    cmp wbCsiP
    bne :+
    lda rbaCsiLast, x
    cmp wbCsiLast
    beq hit
:   dex
    bpl find
none:
    lda #0
    rts
hit:
    txa
    ora #KEY_UP
    rts
esc:
    lda #ESC
done:
    rts
.endproc


; K_KEY's: > A = key_poll's key this frame, 0 for none
.proc key_get
    lda wbKey
    rts
.endproc


.proc view_update
    lda Adapter::wbMouseWheel
    beq pad
    bmi :+
    jmp show_text
:   jmp view_prev
pad:
    lda zbPadNew
    bmi click
    and #JOYPAD_B
    bne back
    lda zbPadNew
    and #JOYPAD_START
    bne more
    rts
click:
    jsr hit_test
    rts_jump rwaViewClick
more:
    jmp show_text
back:
    jmp load_dir
.endproc


.proc no_op
    rts
.endproc


; A on the prompt's row, Enter or Y does wbAskOp to the selection; B, Esc, N, or A anywhere else, keeps it
.proc ask_update
    lda zbPadNew
    and #JOYPAD_A
    bne click
    lda zbPadNew
    and #JOYPAD_B
    bne no
    lda wbKey
    beq done
    cmp #$0d
    beq yes
    cmp #ESC
    beq no
    ora #$20 ; y or Y
    cmp #'y'
    beq yes
    cmp #'n'
    beq no
done:
    rts
click:
    jsr pointer_line
    bcs no
    clc
    adc #1
    cmp zbBodyH
    beq yes
no:
    lda #MODE_LIST
    sta zbMode
    jmp show_page
yes:
    jmp sel_op
.endproc


; wbAskOp on the selection: entry zbAsk's row, or every entry
.proc sel_op
    lda #MODE_LIST
    sta zbMode
    jsr pointer_busy
    lda wbSel
    cmp #SEL_ALL
    beq all
    lda zbAsk
    sta wbRow
    jsr sd_push_name
    bne fail
    lda zbPathLen
    ldy #0
    jsr ask_go
    jsr name_pop
    jmp op_done
all:
    lda zbPathLen
    ldy #1
    jsr ask_go
    jmp op_done
fail:
    pha
    jsr show_page
    jsr pointer_idle
    pla
    jmp status_error
.endproc


; fileops.s's work for wbAskOp on the first A bytes of wbaPath, Y not 0 for every entry of that folder
; > A = status
.proc ask_go
    ldx wbAskOp
    beq bin
    cpx #ASK_DEL
    beq del
    cpx #ASK_RESTORE
    beq restore
    far bin_del
    rts
del:
    far del_go
    rts
bin:
    far bin_go
    rts
restore:
    far restore_go
    rts
.endproc


; the listing again after fileops.s changed the folder, nothing selected; A = its status, shown when not 0
.proc op_done
    pha
    jsr sel_none
    jsr load_dir
    pla
    beq done
    jmp status_error
done:
    rts
.endproc


; fileops.s at work on wbaName: FOP_* in A, on the status line
.proc op_note
    pha
    jsr blank_row
    pla
    tax
    lda rbaOpL, x
    pha
    lda rbaOpH, x
    tax
    pla
    ldy #0
    jsr put_str
    ldx #0
name:
    cpy zbBodyW
    beq put
    lda wbaName, x
    beq put
    cmp #' '
    bcc odd
    cmp #$7f
    bcc :+
odd:
    lda #'?' ; the font has nothing to show past '~'
:   sta wbaRow, y
    iny
    inx
    bne name
put:
    jsr put_status
    jmp vq_flush
.endproc


; the desktop's input: A on an icon or a taskbar button (Start, the clock, the window's) opens what it stands for; B
; on the bin or the empty desk opens its right-click menu
.proc icon_update
    lda zbPadNew
    and #JOYPAD_B
    bne menu
    lda zbPadNew
    and #JOYPAD_A
    beq done
    jsr pointer_px
    jsr on_start
    bcc :+
    jmp start_open
:   jsr on_tray
    bcc :+
    jmp clock_open
:   jsr task_hit
    bcs restore
    far desk_hit
    cmp #$ff
    beq done
    cmp #DESK_BIN
    beq bin
    tax
    bne desk
restore:
    lda #0
    sta zbIcon
    lda zbClosed
    beq open
    jsr pointer_busy
    jsr redraw_screen
    jsr home_reset
    jmp enter_dir
open:
    lda zbHidMode
    sta zbMode
    jmp win_show
desk:
    far desk_path
    jmp app_run
bin:
    jmp bin_open
menu:
    far desk_hit
    cmp #DESK_BIN
    beq bin_menu
    cmp #$ff
    bne done
    lda zbPy
    cmp #SCREEN_H
    bcs done
    jmp desk_popup
bin_menu:
    jmp bin_popup
done:
    rts
.endproc


; the Trash icon's right-click menu: Open, and Empty Trash with something in it
.proc bin_popup
    ldy #0
    lda #<rsPopOpen
    ldx #>rsPopOpen
    jsr pop_add
    lda wbBinFull
    beq :+
    lda #<rsPopEmpty
    ldx #>rsPopEmpty
    jsr pop_add
:   sty wbPopN
    lda #<(bin_pick - 1)
    ldx #>(bin_pick - 1)
    jmp popup_start
.endproc


; the empty desktop's right-click menu: Properties, the Display program
.proc desk_popup
    ldy #0
    lda #<rsPopProps
    ldx #>rsPopProps
    jsr pop_add
    sty wbPopN
    lda #<(display_open - 1)
    ldx #>(display_open - 1)
    jmp popup_start
.endproc


; item A of the bin icon's menu: the bin in the window, then for the second the question to empty it
.proc bin_pick
    pha
    jsr bin_open
    pla
    beq done
    jmp act_empty
done:
    rts
.endproc


; after pointer_px: > C set when the pointer is on the Start button
.proc on_start
    lda zbPy
    cmp #TASK_Y
    bcc done
    lda zbPx
    cmp #START_X + START_W
    bcs out
    sec
    rts
out:
    clc
done:
    rts
.endproc


; after pointer_px: > C set when the pointer is on the taskbar's clock, which runs to the right edge
.proc on_tray
    lda zbPy
    cmp #TASK_Y
    bcc done
    lda zbPx
    cmp #TRAY_X
done:
    rts
.endproc


; nespc/system/clock.dx in the window
.proc clock_open
    lda #<rsClock
    ldx #>rsClock
    ldy #CLOCK_LEN
    jmp sys_open
.endproc


; nespc/system/display.dx in the window
.proc display_open
    lda #<rsDisplay
    ldx #>rsDisplay
    ldy #DISPLAY_LEN
    ; [fall_through]
.endproc

; the system program at A (low), X (high), Y letters, in the window
.proc sys_open
    pha
    jsr pointer_busy
    pla
    jsr dx_path
    jsr dx_open
    beq app_run
    cmp #FR_NO_FILE
    beq none
    cmp #FR_NO_PATH
    bne fail
none:
    lda #FS_E_NOAPP
fail:
    jmp app_fail
.endproc


; the program or shortcut wbaDxPath in the window, which goes back to its listing, file or icon when it ends; on
; failure the listing says why. A shortcut opens what it points at.
.proc app_run
    jsr pointer_busy
    lda #<wbaDxPath
    ldx #>wbaDxPath
    ldy wbDxPathLen
    jsr is_lnk
    bcs link
    lda zbMode
    cmp #MODE_APP
    beq launch ; it replaces the program, and ends as that would have
    ldx #MODE_LIST
    cmp #MODE_VIEW
    beq :+
    cmp #MODE_ICON
    bne ret
    ldy zbHidMode
    cpy #MODE_APP
    bne :+
    ldy #MODE_LIST
    sty zbHidMode
:   tax
ret:
    stx wbRetMode
launch:
    jsr exec_ino
    bne fail
    rts
link:
    lda #<wbaDxPath
    ldx #>wbaDxPath
    ldy wbDxPathLen
    jsr link_read
    bne fail
    jsr link_open
    bne fail
    rts
fail:
    jmp app_fail
.endproc


; A = status from starting a program: the listing, saying why
.proc app_fail
    pha
    lda #MODE_LIST
    sta wbRetMode
    lda #0
    sta zbIcon
    jsr app_quit
    pla
    jsr show_error
    jmp pointer_idle
.endproc


.proc start_open
    lda zbMode
    sta wbMenuRet
    lda #MODE_MENU
    sta zbMode
    jmp menu_open
.endproc


; the Windows key: the Start menu over the screens that have a Start button live, or shut again if open
.proc start_key
    lda zbMode
    cmp #MODE_MENU
    beq shut
    cmp #MODE_LIST
    beq open
    cmp #MODE_VIEW
    beq open
    cmp #MODE_ICON
    beq open
    cmp #MODE_APP
    beq open
    rts
open:
    jmp start_open
shut:
    jsr menu_close
    lda wbMenuRet
    sta zbMode
    jmp screen_back
.endproc


; what the Start menu closed with: a program, or the screen it covered drawn again
.proc menu_mode
    jsr menu_update
    cmp #MENU_NONE
    beq done
    pha
    jsr menu_close
    lda wbMenuRet
    sta zbMode
    pla
    cmp #MENU_APP
    bne back
    jmp app_run
back:
    jsr screen_back
    jsr bar_press
    bcc done
    jmp mode_update ; the same press goes on to the taskbar under the menu
done:
    rts
.endproc

; > C set when this frame's A press is on the taskbar, off Start
.proc bar_press
    lda zbPadNew
    bpl no
    jsr pointer_px
    lda zbPy
    cmp #TASK_Y
    bcc no
    jsr on_start
    bcs no
    sec
    rts
no:
    clc
    rts
.endproc


; a right-click menu of wbPopN items over the screen, its pick going to A (low), X (high) plus one with the item in A
.proc popup_start
    sta wwPopGo
    stx wwPopGo + 1
    lda zbMode
    sta wbPopRet
    lda #MODE_POPUP
    sta zbMode
    jmp popup_open
.endproc


; the screen under a right-click menu drawn again once it closes, then its pick acted on
.proc popup_mode
    jsr popup_update
    cmp #POP_NONE
    beq done
    pha
    lda wbPopRet
    sta zbMode
    jsr screen_back
    pla
    cmp #POP_SHUT
    beq done
    tax
    lda wwPopGo + 1
    pha
    lda wwPopGo
    pha
    txa
done:
    rts
.endproc


; the screen zbMode shows drawn again, the desktop or the window, after something over it closed
.proc screen_back
    lda zbMode
    cmp #MODE_ICON
    beq icon
    jmp win_show
icon:
    jsr pointer_busy
    jsr redraw_screen
    jmp pointer_idle
.endproc


; volume A's listing in the window, ending any program in it
.proc vol_go
    jsr vol_name
    jmp vol_folder
.endproc


; wbVol = A, and wbaPath its directory in the root
.proc vol_name
    sta wbVol
    tax
    lda rbaVolLen - 1, x
    sta zbPathLen
    ldy rbaVolOff - 1, x
    ldx #0
:   lda rsVols, y
    sta wbaPath, x
    inx
    iny
    cpx zbPathLen
    bne :-
    rts
.endproc

; the wbVol folder in wbaPath and zbPathLen in the window from its first entry, ending any program in it
.proc vol_folder
    jsr vol_window
    lda #0
    tax
    ; [fall_through]
.endproc

; list the wbVol folder in wbaPath and zbPathLen from entry A/X (low/high), as a new history entry
.proc vol_list
    pha
    txa
    pha
    jsr sel_none
    lda #0
    sta zbIcon
    sta zbClosed
    jsr hist_push
    pla
    sta zwTop + 1
    pla
    sta zwTop
    lda #MODE_LIST
    sta zbMode
    jmp win_show
.endproc


; the viewer on SD card file wbaPath, zbFileLen long, zdSize bytes, in folder zbPathLen, ending any program in the window
.proc sd_view
    jsr vol_window
    lda #VOL_SD
    sta wbVol
    jsr hist_push
    lda #0
    sta zwTop
    sta zwTop + 1
    jsr rewind
    lda #MODE_VIEW
    sta zbMode
    jmp win_show
.endproc


; the window shown, any program in it ended
.proc vol_window
    jsr pointer_busy
    lda zbMode
    cmp #MODE_ICON
    bne :+
    lda zbHidMode
:   cmp #MODE_APP
    bne open
    jsr app_drop
open:
    lda #0
    sta zbIcon
    sta zbClosed
    rts
.endproc


; ------------------------------------ the window across a launch (nespc/system/state on the SD card)

; the SD card listing showing, or under the program or a menu, else the desktop, written so the Desk a launched ROM
; returns to opens it again
.proc state_window
    jsr app_live
    lda wbRetMode
    bcs :+
    jsr mode_under
:   ldx #0
    cmp #MODE_LIST
    bne save
    lda wbVol
    beq save
    ldx zbPathLen
save:
    txa
    jmp state_save
.endproc

; > A = zbMode under any Start menu or right-click menu
.proc mode_under
    lda zbMode
    cmp #MODE_MENU
    bne :+
    lda wbMenuRet
:   cmp #MODE_POPUP
    bne :+
    lda wbPopRet
:   rts
.endproc

; > C set when a program is in the window, under a menu or minimized with it
.proc app_live
    jsr mode_under
    cmp #MODE_ICON
    bne :+
    lda zbClosed
    lsr
    bcs no
    lda zbHidMode
:   cmp #MODE_APP
    beq yes
no:
    clc
yes:
    rts
.endproc

; write the record for the listed folder wbaPath, A its length (0 for the desktop); best effort, a failure leaves the
; desktop
.proc state_save
    sta wbaState + ST_LEN
    ldx #STATE_MAGIC_LEN - 1
:   lda rsStateMagic, x
    sta wbaState, x
    dex
    bpl :-
    lda zbZoom
    sta wbaState + ST_ZOOM
    lda zwTop
    sta wbaState + ST_TOP
    lda zwTop + 1
    sta wbaState + ST_TOP + 1
    lda #0
    sta wbaState + ST_DISC
    ldx wbRunReq ; the program goes on after a K_ROM_RUN, with the record it showed
    beq :+
    jsr app_live
    lda #0
    bcc :+
    lda wbAppPathLen
:   sta wbaState + ST_DX
    lda wbRunArg
    sta wbaState + ST_ARG
    lda #<(wbaState + ST_SAVER)
    ldx #>(wbaState + ST_SAVER)
    jsr saver_get
    lda #<(wbaState + ST_DESK)
    ldx #>(wbaState + ST_DESK)
    jsr backdrop_get
    lda #<(wbaState + ST_COLORS)
    ldx #>(wbaState + ST_COLORS)
    jsr scheme_get
    jsr sd_release
    jsr ptr_save
    lda #FA_WRITE | FA_OPEN_ALWAYS
    sta zbEdMode
    lda #<rsState
    ldx #>rsState
    ldy #STATE_NAME_LEN
    jsr ed_fopen
    bne done
    lda #<wbaState
    ldx #>wbaState
    ldy #ST_SIZE
    jsr ed_fio
    bne close
    ldy wbaState + ST_LEN
    beq program
    lda #<wbaPath
    ldx #>wbaPath
    jsr ed_fio
    bne close
program:
    ldy wbaState + ST_DX
    beq close
    lda #<wbaAppPath
    ldx #>wbaAppPath
    jsr ed_fio
close:
    jmp ed_fclose
done:
    rts
.endproc

; launch_prep, from a shell bank
.proc rom_prep
    jmp launch_prep
.endproc

; as rom_prep, then the ROM launched with the window kept as state_window keeps it; back only on failure
; > A = status
.proc rom_launch
    jsr rom_prep
    bne done
    jsr state_window
    jmp launch_go
done:
    rts
.endproc

; read the record into wbaState and wbaPath, then void it, so it opens the window once
; > C set when there was one; ST_LEN 0 for the desktop
.proc state_load
    jsr sd_release
    lda #FA_READ
    sta zbEdMode
    lda #<rsState
    ldx #>rsState
    ldy #STATE_NAME_LEN
    jsr ed_fopen
    bne none
    lda #<wbaState
    ldx #>wbaState
    ldy #ST_SIZE
    jsr ed_fio
    bne close
    ldx #STATE_MAGIC_LEN - 1
:   lda wbaState, x
    cmp rsStateMagic, x
    bne close
    dex
    bpl :-
    lda wbaState + ST_LEN
    beq program
    cmp #SD_LEN
    bcc close
    cmp #PATH_MAX + 1
    bcs close
    tay
    lda #<wbaPath
    ldx #>wbaPath
    jsr ed_fio
    bne close
    ldy wbaState + ST_LEN
    jsr path_vol
    beq close
program:
    ldy wbaState + ST_DX
    beq void
    lda #<wbaDxPath
    ldx #>wbaDxPath
    jsr ed_fio
    bne close
void:
    jsr ed_fclose
    lda #FA_WRITE
    sta zbEdMode
    lda #<rsState
    ldx #>rsState
    ldy #STATE_NAME_LEN
    jsr ed_fopen
    bne voided ; still read; it opens the window again next boot
    lda #<rbaZero
    ldx #>rbaZero
    ldy #STATE_MAGIC_LEN
    jsr ed_fio
    jsr ed_fclose
voided:
    sec
    rts
close:
    jsr ed_fclose
none:
    lda #0
    sta wbaState + ST_DX
    clc
    rts
.endproc

; the pointer where the last ROM with one left it, its Start menu request into wbPtrMenu and voided in the file
.proc ptr_load
    lda #FA_READ
    jsr ptr_io
    bne done
    lda wbaPtr + PTR_X
    ldx wbaPtr + PTR_Y
    jsr pointer_put
    lda wbaPtr + PTR_FLAGS
    and #PTR_MENU
    sta wbPtrMenu
    beq done
    lda #0
    sta wbaPtr + PTR_FLAGS
    lda #FA_WRITE
    jmp ptr_io
done:
    rts
.endproc

; the pointer's tip into the file, for the ROM a launch starts; best effort
.proc ptr_save
    jsr pointer_px
    lda zbPx
    sta wbaPtr + PTR_X
    lda zbPy
    sta wbaPtr + PTR_Y
    lda #0
    sta wbaPtr + PTR_FLAGS
    lda #FA_WRITE | FA_CREATE_ALWAYS
    ; [fall_through]
.endproc

; the pointer file's record through mode A; > A = status, Z set on success
.proc ptr_io
    ldx #<rbaPtrRec
    ldy #>rbaPtrRec
    jmp rec_file
.endproc

; the window as state_load found it
.proc state_restore
    lda wbaState + ST_ZOOM
    and #1
    sta zbZoom
    jsr set_geometry
    lda wbaState + ST_LEN
    sta zbPathLen
    tay
    jsr path_vol
    sta wbVol
    lda wbaState + ST_TOP
    ldx wbaState + ST_TOP + 1
    jmp vol_list
.endproc


; > A = the volume the first Y characters of wbaPath are in, Z set for none
.proc path_vol
    sty zbLen
    ldx #VOL_COUNT
vol:
    clc
    lda #<rsVols
    adc rbaVolOff - 1, x
    sta zpSrc
    lda #>rsVols
    adc #0
    sta zpSrc + 1
    ldy #0
same:
    lda (zpSrc), y
    beq end
    cpy zbLen
    bcs next
    cmp wbaPath, y
    bne next
    iny
    bne same
end:
    cpy zbLen
    beq found
    lda wbaPath, y
    cmp #'/'
    beq found
next:
    dex
    bne vol
found:
    txa
    rts
.endproc


; ------------------------------------ window controls

; > A = HIT_* for the control under the pointer
.proc hit_test
    jsr pointer_px
    jsr on_start
    bcc :+
    lda #HIT_START
    rts
:   jsr on_tray
    bcc :+
    lda #HIT_CLOCK
    rts
:   jsr task_hit
    bcc :+
    lda #HIT_TASK
    rts
:   jsr win_x0
    sta zbT
    lda zbPx
    sec
    sbc zbT
    bcc none
    sta zbRelX
    lda zbWinW
    asl
    asl
    asl
    sta zbT ; the width, 0 for the screen's
    beq :+
    lda zbRelX
    cmp zbT
    bcs none
:   lda zbPy
    sec
    sbc zbWinY
    bcc none
    cmp zbWinH
    bcs none
    sta zbRelY
    cmp #TITLE_H
    bcc cap_hit
    ldy zbFitW ; a program's plain frame has no toolbar or scroll bar
    bne none
    cmp #TITLE_H + TOOL_H
    bcc tool_hit
    jmp sb_hit
none:
    lda #HIT_NONE
    rts
.endproc

; hit_test's title bar, A = zbRelY: its caption buttons
.proc cap_hit
    sec
    sbc #CAP_Y
    cmp #14
    bcs none
    lda zbT
    sec
    sbc zbRelX ; pixels from the right edge
    sec
    sbc #CAP_CLOSE - 15
    cmp #16
    bcc close
    sbc #CAP_ZOOM - CAP_CLOSE
    cmp #16
    bcc zoom
    sbc #CAP_MIN - CAP_ZOOM
    cmp #16
    bcs none
    lda #HIT_MIN
    rts
close:
    lda #HIT_CLOSE
    rts
zoom:
    lda #HIT_ZOOM
    rts
none:
    lda #HIT_NONE
    rts
.endproc

; hit_test's toolbar, A = zbRelY: Back, Forward, Up or Root
.proc tool_hit
    sec
    sbc #TOOL_Y
    cmp #16
    bcs none
    lda zbRelX
    sec
    sbc #TOOL_X
    bcc none
    ldy #HIT_BACK
step:
    cmp #TOOL_STEP
    bcc rem
    sbc #TOOL_STEP
    iny
    bne step
rem:
    cmp #16 ; the gap after a button
    bcs none
    cpy #HIT_BACK + 4
    bcs none
    tya
    rts
none:
    lda #HIT_NONE
    rts
.endproc

; hit_test's scroll bar, inside the right edge beside the rows
.proc sb_hit
    lda zbT
    sec
    sbc #FRAME + SB_W
    sta zbI
    lda zbRelX
    sec
    sbc zbI
    cmp #SB_W
    bcs none
    lda zbRelY
    sec
    sbc #BODY_TOP - 1
    bcc none
    cmp #SB_W
    bcc prev
    sta zbI
    lda zbBodyH
    asl
    asl
    asl
    sec
    sbc #SB_W - 2 ; the down button's top
    cmp zbI
    beq next
    bcc down
    lda zbThumb
    cmp #$ff
    beq none
    asl
    asl
    asl
    cmp zbI
    beq none
    bcs prev
    adc #SB_W - 2 ; C set: its last row
    cmp zbI
    bcs none
next:
    lda #HIT_NEXT
    rts
down:
    adc #SB_W - 1 ; C clear
    cmp zbI
    bcs next
none:
    lda #HIT_NONE
    rts
prev:
    lda #HIT_PREV
    rts
.endproc


.proc win_close
    jsr backdrop_revert ; a program's choice it didn't keep
    lda #1
    jmp win_hide
.endproc

.proc win_min
    lda #0
    ; [fall_through]
.endproc

; swap the window for its icon; A = 1 when the icon should reopen at the Files folder
.proc win_hide
    sta zbClosed
    clc
    jsr pal_show
    lda zbClosed
    lsr
    bcc :+
    lda #0 ; a closed window's program is gone
    sta wbAppIcon
    jsr fit_reset
:   lda zbMode
    sta zbHidMode
    lda #MODE_ICON
    sta zbMode
    lda #1
    sta zbIcon
    jsr pointer_busy
    far desk_scan ; what the window put in nespc/desktop
    jsr redraw_screen
    jsr vq_flush ; pal_show's colors, which nothing on the desktop flushes
    jmp pointer_idle
.endproc


.proc win_zoom
    lda zbZoom
    eor #1
    sta zbZoom
    jsr set_geometry
    ; [fall_through]
.endproc

; redraw the screen with the window's contents for zbMode
.proc win_show
    jsr pointer_busy
    jsr redraw_screen
    lda zbMode
    cmp #MODE_VIEW
    beq view
    cmp #MODE_APP
    beq app
    jsr round_top
    jmp load_dir
app:
    jmp app_frame
view:
    jsr view_title
    jsr show_toolbar
    lda zbViewPage
    jmp view_goto
.endproc


; zwTop down to a page boundary of the current body height
.proc round_top
    lda zwTop
    ldx zwTop + 1
    jsr set_num16
    lda zbBodyH
    jsr udiv32_8
    sta zbT
    sec
    lda zwTop
    sbc zbT
    sta zwTop
    lda zwTop + 1
    sbc #0
    sta zwTop + 1
    rts
.endproc


; zdNum = A (low), X (high)
.proc set_num16
    sta zdNum
    stx zdNum + 1
    lda #0
    sta zdNum + 2
    sta zdNum + 3
    rts
.endproc


; > A = zdNum, 255 when it is larger; Z set when 0
.proc num_byte
    lda zdNum + 1
    ora zdNum + 2
    ora zdNum + 3
    beq low
    lda #$ff
    rts
low:
    lda zdNum
    rts
.endproc


; ------------------------------------ history

; the history wbaPath alone
.proc hist_reset
    lda #0
    sta wbHistPos
    lda zbPathLen
    sta wbaHistLen
    ldy #0
:   cpy zbPathLen
    beq done
    lda wbaPath, y
    sta wbaHistPool, y
    iny
    bne :-
done:
    lda #1
    sta wbHistLen
    rts
.endproc


.proc hist_save
    ldx wbHistPos
    lda zwTop
    sta wbaHistTopL, x
    lda zwTop + 1
    sta wbaHistTopH, x
    rts
.endproc


; keep zwTop for the current entry, then add wbaPath after it, dropping any forward entries
.proc hist_push
    jsr hist_save
    inx
    cpx #HIST_MAX
    bne room
    jsr hist_drop
    dex
room:
    lda zbPathLen
    sta wbaHistLen, x
fit:
    stx wbHistPos
    jsr hist_off
    clc
    lda zpSrc
    adc wbaHistLen, x
    sta zpDst
    lda zpSrc + 1
    adc #0
    sta zpDst + 1
    lda #<(wbaHistPool + HIST_POOL)
    cmp zpDst
    lda #>(wbaHistPool + HIST_POOL)
    sbc zpDst + 1
    bcs copy
    jsr hist_drop
    dex
    jmp fit
copy:
    lda wbaHistLen, x
    sta zbT
    ldy #0
:   cpy zbT
    beq set
    lda wbaPath, y
    sta (zpSrc), y
    iny
    bne :-
set:
    inx
    stx wbHistLen
    rts
.endproc


; forget the oldest history entry, moving the others down one
; keeps: X
.proc hist_drop
    txa
    pha
    lda #<wbaHistPool
    sta zpDst
    clc
    adc wbaHistLen
    sta zpSrc
    lda #>wbaHistPool
    sta zpDst + 1
    adc #0
    sta zpSrc + 1
    ldx #>HIST_POOL
    ldy #0
move:
    lda (zpSrc), y
    sta (zpDst), y
    iny
    bne move
    inc zpSrc + 1
    inc zpDst + 1
    dex
    bne move
shift:
    lda wbaHistTopL + 1, y
    sta wbaHistTopL, y
    lda wbaHistTopH + 1, y
    sta wbaHistTopH, y
    lda wbaHistLen + 1, y
    sta wbaHistLen, y
    iny
    cpy #HIST_MAX - 1
    bne shift
    pla
    tax
    rts
.endproc


; zpSrc = where history entry X's path starts in wbaHistPool
; changes: A, Y, zbT; keeps: X
.proc hist_off
    lda #<wbaHistPool
    sta zpSrc
    lda #>wbaHistPool
    sta zpSrc + 1
    stx zbT
    ldy #0
loop:
    cpy zbT
    beq done
    clc
    lda zpSrc
    adc wbaHistLen, y
    sta zpSrc
    bcc :+
    inc zpSrc + 1
:   iny
    bne loop
done:
    rts
.endproc


.proc hist_back
    lda wbHistPos
    beq done
    jsr hist_save
    dec wbHistPos
    jmp hist_go
done:
    rts
.endproc


.proc hist_fwd
    ldx wbHistPos
    inx
    cpx wbHistLen
    bcs done
    jsr hist_save
    inc wbHistPos
    jmp hist_go
done:
    rts
.endproc


; list history entry wbHistPos
.proc hist_go
    ldx wbHistPos
    lda wbaHistTopL, x
    sta zwTop
    lda wbaHistTopH, x
    sta zwTop + 1
    jsr pointer_busy
    ldx wbHistPos
    jsr hist_off
    lda wbaHistLen, x
    sta zbPathLen
    ldy #0
:   cpy zbPathLen
    beq named
    lda (zpSrc), y
    sta wbaPath, y
    iny
    bne :-
named:
    jsr path_vol
    sta wbVol
    jsr sel_none
    jsr round_top
    jmp load_dir
.endproc


; ------------------------------------ directory list

; list wbaPath from its first entry
.proc enter_dir
    jsr sel_none
    lda #0
    sta zwTop
    sta zwTop + 1
    ; [fall_through]
.endproc

; list wbaPath from entry zwTop, or its first page when there are fewer entries
.proc load_dir
    lda #MODE_LIST
    sta zbMode
    jsr pointer_busy
    jsr show_title
    jsr show_toolbar
    jsr count_entries
    bne fail
    lda zwTop
    cmp zwCount
    lda zwTop + 1
    sbc zwCount + 1
    bcc page
    lda #0
    sta zwTop
    sta zwTop + 1
page:
    jsr sel_fit
    jsr show_page
    jmp pointer_idle
fail:
    ldx #0
    stx zwCount
    stx zwCount + 1
    stx zwTop
    stx zwTop + 1
    pha
    jsr list_chrome
    pla
    jsr show_error
    jmp pointer_idle
.endproc


; > A = status, Z set on success; zwCount = entries listed in wbaPath: at the root, its volumes
.proc count_entries
    lda #0
    sta zwCount
    sta zwCount + 1
    lda wbVol
    bne sd
    lda #VOL_COUNT
    sta zwCount
    lda #0
done:
    rts
sd:
    ldy zbPathLen
    jsr vol_path
    jsr ed_dir_load
    bne done
    lda zwEdArg
    sta zwCount
    lda zwEdArg + 1
    sta zwCount + 1
    lda #0
    rts
.endproc


.proc count_one
    inc zwCount
    bne done
    inc zwCount + 1
done:
    rts
.endproc


; wbVol's own path for the first Y characters of wbaPath: what follows its name, or "/" for its root
; > A/X = path (low/high), Y = its length
.proc vol_path
    ldx wbVol
    tya
    sec
    sbc rbaVolLen - 1, x
    beq root
    bcc root
    tay
    clc
    lda #<wbaPath
    adc rbaVolLen - 1, x
    pha
    lda #>wbaPath
    adc #0
    tax
    pla
    rts
root:
    lda #<rsSlash
    ldx #>rsSlash
    ldy #1
    rts
.endproc


; the next page, back to the first after the last
.proc list_next
    clc
    lda zwTop
    adc zbBodyH
    tax
    lda zwTop + 1
    adc #0
    cmp zwCount + 1
    bcc ok
    bne wrap
    cpx zwCount
    bcc ok
wrap:
    ldx #0
    txa
ok:
    stx zwTop
    sta zwTop + 1
    jmp show_page
.endproc


; the next page, if there is one
.proc list_down
    clc
    lda zwTop
    adc zbBodyH
    tax
    lda zwTop + 1
    adc #0
    cmp zwCount + 1
    bcc ok
    bne done
    cpx zwCount
    bcs done
ok:
    stx zwTop
    sta zwTop + 1
    jmp show_page
done:
    rts
.endproc


.proc list_prev
    lda zwTop
    ora zwTop + 1
    beq done
    sec
    lda zwTop
    sbc zbBodyH
    sta zwTop
    lda zwTop + 1
    sbc #0
    sta zwTop + 1
    bcs page
    lda #0
    sta zwTop
    sta zwTop + 1
page:
    jmp show_page
done:
    rts
.endproc


.proc list_up
    ldx wbVol
    beq done
    lda rbaVolLen - 1, x
    ldy zbPathLen
    cmp zbPathLen
    bcc back
    lda #0 ; a volume's own directory: up to the root
    sta wbVol
    sta zbPathLen
    beq enter
back:
    dey
    beq cut
    lda wbaPath, y
    cmp #'/'
    bne back
cut:
    sty zbPathLen
enter:
    jsr hist_push
    jmp enter_dir
done:
    rts
.endproc


.proc go_root
    lda wbVol
    beq done
    lda #0
    sta zbPathLen
    sta wbVol
    jsr hist_push
    jmp enter_dir
done:
    rts
.endproc


; open the entry of page row wbRow
.proc list_open
    lda wbRow
    jsr rec_at
    ldy #R_TYPE
    lda (zpRec), y
    cmp #S_IFDIR
    beq dir
    jmp sd_open_file
dir:
    lda wbVol
    bne vol_dir
    ldy #R_SLOT ; a volume at the root
    lda (zpRec), y
    jsr vol_name
enter:
    jsr hist_push
    jmp enter_dir
vol_dir:
    jsr sd_push_name
    beq enter
    jmp show_error
.endproc


; Shift+Del: ask before deleting the selection for good
.proc list_kill
    jsr in_bin
    tax
    lda #ASK_DEL
    cpx #1
    bne :+
    lda #ASK_BINDEL
:   jmp ask_op
.endproc

; ask before recycling the selection, in the bin before deleting it
.proc list_ask
    jsr in_bin
    tax
    lda #ASK_BIN
    cpx #0
    beq ask_op
    lda #ASK_BINDEL
    cpx #1
    beq ask_op
    lda #ASK_DEL
    ; [fall_through]
.endproc

; ask before wbAskOp = A on the selection: "trash NAME? A/B", or its count for every entry
.proc ask_op
    sta wbAskOp
    lda wbSel
    bne :+
    rts
:   lda wbVol
    cmp #VOL_SD
    beq :+
    lda #FS_E_RDONLY
    jmp status_error
:   jsr blank_row
    lda wbSel
    cmp #SEL_ALL
    beq all
    jsr sel_show
    bcs done
    sta zbAsk
    jsr rec_at
    ldy #0
    jsr ask_verb
    tya
    tax
    lda zbBodyW
    sec
    sbc #ASK_LEN
    sta wbCol ; the name stops where the question still fits
    ldy #R_NAME
:   cpx wbCol
    bcs ask
    lda (zpRec), y
    beq ask
    sta wbaRow, x
    inx
    iny
    bne :-
all:
    ldy #0
    lda wbAskOp
    cmp #ASK_EMPTY
    bne count
    jsr ask_verb
    tya
    tax
    jmp ask
count:
    lda zwCount
    ldx zwCount + 1
    jsr set_num16
    ldy #0
    jsr ask_verb
    jsr put_dec
    lda #<rsItems
    ldx #>rsItems
    jsr put_str
    tya
    tax
ask:
    txa
    tay
    lda #<rsAsk
    ldx #>rsAsk
    jsr put_str
    lda #MODE_ASK
    sta zbMode
    lda zbBodyH
    sec
    sbc #1
    jsr put_row
    jmp vq_flush
done:
    rts
.endproc

; the prompt's first words for wbAskOp at column Y
.proc ask_verb
    ldx wbAskOp
    lda rbaAskL, x
    pha
    lda rbaAskH, x
    tax
    pla
    jmp put_str
.endproc


; > A = 1 when the listing is the recycle bin, 2 a folder in it, else 0
; keeps: Y
.proc in_bin
    lda wbVol
    cmp #VOL_SD
    bne no
    lda zbPathLen
    cmp #BIN_PATH_LEN
    bcc no
    ldx #BIN_PATH_LEN - 1
:   lda wbaPath, x
    cmp rsBinPath, x
    bne no
    dex
    bpl :-
    lda zbPathLen
    cmp #BIN_PATH_LEN
    beq bin
    lda wbaPath + BIN_PATH_LEN
    cmp #'/'
    bne no
    lda #2
    rts
bin:
    lda #1
    rts
no:
    lda #0
    rts
.endproc


; the recycle bin in the window, made when it isn't there yet
.proc bin_open
    jsr pointer_busy
    far bin_make
    ldx #BIN_PATH_LEN
    stx zbPathLen
:   lda rsBinPath - 1, x
    sta wbaPath - 1, x
    dex
    bne :-
    lda #VOL_SD
    sta wbVol
    jmp vol_folder
.endproc


; zpRec = record of row A
.proc rec_at
    ldx #0
    stx zpRec + 1
    .repeat 5
        asl
        rol zpRec + 1
    .endrepeat
    clc
    adc #<wbaRec
    sta zpRec
    lda zpRec + 1
    adc #>wbaRec
    sta zpRec + 1
    rts
.endproc


; > A = body row under the pointer, C set when it is left, right or above the body
.proc pointer_line
    jsr pointer_px
    lda zbPx
    lsr
    lsr
    lsr
    sec
    sbc zbBodyX
    bcc out
    cmp zbBodyW
    bcs out
    lda zbPy
    sec
    sbc zbBodyY
    bcc out
    lsr
    lsr
    lsr
    clc
    rts
out:
    sec
    rts
.endproc


; volume A's directory at the root into the record at zpRec, the volume in R_SLOT
.proc card_rec
    ldy #R_SLOT
    sta (zpRec), y
    tax
    ldy #R_TYPE
    lda #S_IFDIR
    sta (zpRec), y
    lda rbaVolOff - 1, x
    tax
    ldy #R_NAME
copy:
    lda rsVols, x
    sta (zpRec), y
    inx
    iny
    cmp #0
    bne copy
    rts
.endproc


; zbShown SD card entries from zwTop on into the records from zpRec
; > A = status, Z set on success
.proc sd_fetch
    lda zbShown
    beq done
    lda zwTop
    sta zwEdArg
    lda zwTop + 1
    sta zwEdArg + 1
    lda zbShown
    ldx #SD_NAME_MAX
    jsr ed_dir_get
loop:
    clc
    lda zpRec
    adc #R_NAME
    sta zpEdBuf
    lda zpRec + 1
    adc #0
    sta zpEdBuf + 1
    jsr ed_dir_rec
    bne done
    ; '?' for what the font can't show
clean:
    dey
    bmi type
    lda (zpEdBuf), y
    cmp #' '
    bcc odd
    cmp #$7f
    bcc clean
odd:
    lda #'?'
    sta (zpEdBuf), y
    bne clean
type:
    ldy #R_TYPE
    lda wbaEdInfo + FI_ATTR
    and #AT_DIR
    beq file
    lda #S_IFDIR
    bne :+
file:
    lda #S_IFREG
:   sta (zpRec), y
    ldy #R_SIZE
    ldx #0
size:
    lda wbaEdInfo + FI_SIZE, x
    sta (zpRec), y
    iny
    inx
    cpx #4
    bne size
    jsr next_rec
    inc zbI
    lda zbI
    cmp zbShown
    bne loop
    lda #0
done:
    rts
.endproc


; append "/" and the whole name of SD card entry zwTop + wbRow to wbaPath, keeping the old length in zbOldLen
; > A = status, Z set on success, the path as it was on failure; wbaEdInfo the entry's
.proc sd_push_name
    lda zbPathLen
    sta zbOldLen
    clc
    lda zwTop
    adc wbRow
    sta zwEdArg
    lda zwTop + 1
    adc #0
    sta zwEdArg + 1
    lda #<wbaName
    sta zpEdBuf
    lda #>wbaName
    sta zpEdBuf + 1
    lda #1
    ldx #$ff
    jsr ed_dir_get
    jsr ed_dir_rec
    beq name_append
    rts
.endproc

; append "/" and wbaName, Y long, to wbaPath
; > A = status, Z set on success, the path as it was on failure
.proc name_append
    tya
    sec ; and the "/"
    adc zbPathLen
    bcs full
    cmp #PATH_MAX + 1
    bcs full
    ldx zbPathLen
    lda #'/'
    sta wbaPath, x
    inx
    ldy #0
copy:
    lda wbaName, y
    beq end
    sta wbaPath, x
    inx
    iny
    bne copy
end:
    stx zbPathLen
    lda #0
    rts
full:
    lda #FS_E_LONG
    rts
.endproc

; wbaPath back to its length before sd_push_name
; keeps: A, Y and C
.proc name_pop
    ldx zbOldLen
    stx zbPathLen
    rts
.endproc


; ------------------------------------ the listing

; fetch and draw the entries from zwTop on
.proc show_page
    sec
    lda zwCount
    sbc zwTop
    tax
    lda zwCount + 1
    sbc zwTop + 1
    bne full
    cpx zbBodyH
    bcc some
full:
    ldx zbBodyH
some:
    stx zbShown
    lda #<wbaRec
    sta zpRec
    lda #>wbaRec
    sta zpRec + 1
    lda #0
    sta zbI
    lda wbVol
    beq root
    jsr sd_fetch
    beq :+
    jmp show_error
:   jmp draw

root:
    ; the volumes
    lda zbI
    cmp zbShown
    beq draw
    clc
    adc zwTop
    adc #1
    jsr card_rec
    jsr next_rec
    inc zbI
    jmp root

draw:
    jsr rows_draw
    jsr list_chrome
    jmp vq_flush
.endproc


; every body row of the listing from wbaRec
.proc rows_draw
    lda #0
    sta zbI
:   lda zbI
    jsr row_draw
    inc zbI
    lda zbI
    cmp zbBodyH
    bne :-
    rts
.endproc


; body row A of the listing from its record, white on navy when it is selected
.proc row_draw
    sta wbDrawRow
    jsr blank_row
    lda wbDrawRow
    cmp zbShown
    bcs put
    jsr rec_at
    ldy #R_NAME
    ldx #0
name:
    lda (zpRec), y
    beq slash
    sta wbaRow, x
    inx
    iny
    bne name
slash:
    ldy #R_TYPE
    lda (zpRec), y
    cmp #S_IFDIR
    bne put
    lda #'/'
    sta wbaRow, x
put:
    lda wbDrawRow
    jsr row_on
    lda wbDrawRow
    bcs lit
    jmp put_row
lit:
    jmp put_row_lit
.endproc


; ------------------------------------ selection

; > C set when listing row A is selected
.proc row_on
    cmp zbShown
    bcs no
    ldx wbSel
    beq no
    cpx #SEL_ALL
    beq yes
    clc
    adc zwTop
    tax
    lda zwTop + 1
    adc #0
    cmp wwSel + 1
    bne no
    cpx wwSel
    bne no
yes:
    sec
    rts
no:
    clc
    rts
.endproc


; > A = page row of entry wwSel, C set when it isn't on the page
.proc sel_row
    sec
    lda wwSel
    sbc zwTop
    tax
    lda wwSel + 1
    sbc zwTop + 1
    bne out
    txa
    cmp zbShown
    rts
out:
    sec
    rts
.endproc


; nothing selected, nothing drawn
.proc sel_none
    lda #SEL_NONE
    sta wbSel
    sta wbClickOk
    rts
.endproc


; a selection past the folder's last entry dropped, as after a delete
.proc sel_fit
    lda wbSel
    beq done
    lda zwCount
    ora zwCount + 1
    beq none
    lda wbSel
    cmp #SEL_ALL
    beq done
    lda wwSel
    cmp zwCount
    lda wwSel + 1
    sbc zwCount + 1
    bcc done
none:
    jmp sel_none
done:
    rts
.endproc


; selection A (SEL_*), entry wwHit for SEL_ONE, and the rows it changes drawn again
.proc sel_set
    tax
    lda wbSel
    stx wbSel
    cpx #SEL_ALL
    beq all
    cmp #SEL_ALL
    beq all
    ldy #$ff
    cmp #SEL_ONE
    bne :+
    jsr sel_row
    bcs :+
    tay
:   sty wbOldRow
    jsr take
    lda wbOldRow
    bmi :+
    jsr row_draw
:   lda wbSel
    beq done
    jsr sel_row
    bcs done
    jsr row_draw
done:
    jmp vq_flush
all:
    jsr take
    jsr rows_draw
    jmp vq_flush
take:
    lda wwHit
    sta wwSel
    lda wwHit + 1
    sta wwSel + 1
    rts
.endproc


; entry wwHit selected, its page shown when it is on another
.proc sel_go
    sec
    lda wwHit
    sbc zwTop
    tax
    lda wwHit + 1
    sbc zwTop + 1
    bne turn
    cpx zbShown
    bcs turn
    lda #SEL_ONE
    jmp sel_set
turn:
    lda #SEL_ONE
    sta wbSel
    lda wwHit
    sta wwSel
    lda wwHit + 1
    sta wwSel + 1
    ; [fall_through]
.endproc

; the selected entry's page shown
; > A = its row, C set when it can't be
.proc sel_show
    jsr sel_row
    bcc done
    lda wwSel
    sta zwTop
    lda wwSel + 1
    sta zwTop + 1
    jsr round_top
    jsr show_page
    jsr sel_row
done:
    rts
.endproc


.proc sel_all
    lda zwCount
    ora zwCount + 1
    beq done
    lda #SEL_ALL
    jmp sel_set
done:
    rts
.endproc


.proc sel_clear
    lda #SEL_NONE
    sta wbClickOk
    jmp sel_set
.endproc


; the entry after the selected one, or the page's first
.proc sel_down
    lda wbSel
    cmp #SEL_ONE
    beq one
    lda zbShown
    beq done
    lda zwTop
    sta wwHit
    lda zwTop + 1
    sta wwHit + 1
    jmp sel_go
one:
    clc
    lda wwSel
    adc #1
    sta wwHit
    lda wwSel + 1
    adc #0
    sta wwHit + 1
    lda wwHit
    cmp zwCount
    lda wwHit + 1
    sbc zwCount + 1
    bcs done
    jmp sel_go
done:
    rts
.endproc


; the entry before the selected one, or the page's last
.proc sel_up
    lda wbSel
    cmp #SEL_ONE
    beq one
    lda zbShown
    beq done
    clc
    lda zwTop
    adc zbShown
    sta wwHit
    lda zwTop + 1
    adc #0
    sta wwHit + 1
    jmp back
one:
    lda wwSel
    ora wwSel + 1
    beq done
    lda wwSel
    sta wwHit
    lda wwSel + 1
    sta wwHit + 1
back:
    lda wwHit
    bne :+
    dec wwHit + 1
:   dec wwHit
    jmp sel_go
done:
    rts
.endproc


; ------------------------------------ actions on the listing

; A on the listing: the entry under the pointer selected, opened by a second press soon after; off the entries,
; nothing selected
.proc list_press
    jsr pointer_line
    bcs done
    cmp zbShown
    bcs clear
    sta wbRow
    clc
    adc zwTop
    sta wwHit
    lda zwTop + 1
    adc #0
    sta wwHit + 1
    lda wbClickOk
    beq first
    lda wwHit
    cmp wwClick
    bne first
    lda wwHit + 1
    cmp wwClick + 1
    bne first
    lda zbFrame
    sec
    sbc wbClickAt
    cmp #DBL_FRAMES
    bcs first
    lda #0
    sta wbClickOk
    jmp list_open
first:
    lda wwHit
    sta wwClick
    lda wwHit + 1
    sta wwClick + 1
    lda zbFrame
    sta wbClickAt
    lda #1
    sta wbClickOk
    lda #SEL_ONE
    jmp sel_set
clear:
    jmp sel_clear
done:
    rts
.endproc


; B on the listing: the entry under the pointer selected unless it already is, and the menu of what can be done to
; the selection; off the entries, Paste, and in the bin Empty Trash
.proc list_menu
    jsr pointer_line
    bcc :+
    rts
:   cmp zbShown
    bcs empty
    sta wbRow
    jsr row_on
    bcs keep
    lda wbRow
    clc
    adc zwTop
    sta wwHit
    lda zwTop + 1
    adc #0
    sta wwHit + 1
    lda #SEL_ONE
    jsr sel_set
keep:
    ldy #0
    lda wbSel
    cmp #SEL_ALL
    beq :+
    lda #ACT_OPEN
    jsr add
:   lda wbVol
    beq show ; the root's volumes
    jsr in_bin
    cmp #1
    beq bin
    lda #ACT_CUT
    jsr add
    lda #ACT_COPY
    jsr add
    lda wbSel
    cmp #SEL_ONE
    bne :+
    lda #ACT_RENAME
    jsr add
:   lda #ACT_DELETE
    jsr add
    jmp show
bin: ; no Cut or Rename, which would part an entry from its origin file
    lda #ACT_RESTORE
    jsr add
    lda #ACT_COPY
    jsr add
    lda #ACT_DELETE
    jsr add
show:
    sty wbPopN
    cpy #0
    beq done
    lda #<(pop_pick - 1)
    ldx #>(pop_pick - 1)
    jmp popup_start
empty:
    jsr sel_clear
    lda wbVol
    cmp #VOL_SD
    bne done
    far clip_any
    php
    ldy #0
    plp
    beq :+
    lda #ACT_PASTE
    jsr add
:   jsr in_bin
    cmp #1
    bne show
    lda zwCount
    ora zwCount + 1
    beq show
    lda #ACT_EMPTY
    jsr add
    jmp show
done:
    rts
add:
    sta wbaPopAct, y
    tax
    lda rbaActL, x
    sta wbaPopL, y
    lda rbaActH, x
    sta wbaPopH, y
    iny
    rts
.endproc


; item A of the listing's right-click menu
.proc pop_pick
    tax
    lda wbaPopAct, x
    rts_jump rwaAct
.endproc


.proc act_open
    lda wbSel
    cmp #SEL_ONE
    bne done
    jsr sel_show
    bcs done
    sta wbRow
    jmp list_open
done:
    rts
.endproc


.proc act_cut
    lda #CLIP_CUT
    jmp clip
.endproc

.proc act_copy
    lda #0
    ; [fall_through]
.endproc

; the selection to the clipboard, moved by the paste with CLIP_CUT in A
.proc clip
    sta wbClipFlags
    ldx wbVol
    beq ro ; the root's volumes
    lda wbSel
    beq done
    cmp #SEL_ALL
    beq all
    jsr sel_show
    bcs done
    sta wbRow
    jsr sd_push_name
    bne fail
    lda wbClipFlags
    ldx wbVol
    ldy zbPathLen
    far clip_set
    jmp name_pop
all:
    lda wbClipFlags
    ora #CLIP_ALL
    ldx wbVol
    ldy zbPathLen
    far clip_set
done:
    rts
ro:
    lda #FS_E_RDONLY
fail:
    jmp status_error
.endproc


; the selection in the bin back where it came from
.proc act_restore
    lda #ASK_RESTORE
    sta wbAskOp
    lda wbSel
    beq done
    cmp #SEL_ALL
    beq go
    jsr sel_show
    bcs done
    sta zbAsk
go:
    jmp sel_op
done:
    rts
.endproc


; every entry of the bin deleted for good, after asking
.proc act_empty
    jsr sel_all
    lda #ASK_EMPTY
    jmp ask_op
.endproc


; the clipboard's entries into the SD card folder listed
.proc act_paste
    lda wbVol
    cmp #VOL_SD
    beq sd
    lda #FS_E_RDONLY
    jmp status_error
sd:
    far clip_any
    beq done
    jsr pointer_busy
    ldy zbPathLen
    far paste_go
    jmp op_done
done:
    rts
.endproc


; ------------------------------------ rename

; F2 or Rename: the selected entry's name to type over on its row
.proc edit_start
    lda wbVol
    cmp #VOL_SD
    beq :+
    lda #FS_E_RDONLY
    jmp status_error
:   lda wbSel
    cmp #SEL_ONE
    bne done
    jsr sel_show
    bcs done
    sta wbRow
    sta wbEditRow
    jsr sd_push_name
    bne fail
    jsr name_pop
    ldy #0
:   lda wbaName, y
    beq :+
    sta wbaEdit, y
    iny
    cpy #NAME_MAX
    bne :-
:   sty wbEditLen
    lda #MODE_EDIT
    sta zbMode
    jsr blank_row
    ldy #0
    lda #<rsEditHint
    ldx #>rsEditHint
    jsr put_str
    jsr put_status
    jmp edit_draw
fail:
    jmp status_error
done:
    rts
.endproc


; typing the new name: Enter renames, Esc or a press anywhere leaves the name as it was
.proc edit_update
    lda zbPadNew
    and #JOYPAD_A | JOYPAD_B
    bne cancel
    lda wbKey
    beq done
    cmp #$0d
    beq save
    cmp #ESC
    beq cancel
    cmp #$08
    beq back
    cmp #' '
    bcc done
    cmp #$7f
    bcs done
    ldx wbEditLen
    cpx #NAME_MAX
    bcs done
    sta wbaEdit, x
    inc wbEditLen
    jmp edit_draw
back:
    lda wbEditLen
    beq done
    dec wbEditLen
    jmp edit_draw
save:
    jmp edit_save
cancel:
    jmp edit_end
done:
    rts
.endproc


; the listing as it was before the rename
.proc edit_end
    lda #MODE_LIST
    sta zbMode
    lda wbEditRow
    jsr row_draw
    jsr list_chrome
    jmp vq_flush
.endproc


; the name typed so far on its row, its tail when it is too long, and a cursor
.proc edit_draw
    jsr blank_row
    lda wbEditLen ; from len - (zbBodyW - 1), a column left for the cursor
    sec
    sbc zbBodyW
    bcs :+
    lda #$ff
:   tay
    iny
    ldx #0
:   cpy wbEditLen
    beq cursor
    lda wbaEdit, y
    sta wbaRow, x
    inx
    iny
    bne :-
cursor:
    lda #'_'
    sta wbaRow, x
    lda wbEditRow
    jsr put_row
    jmp vq_flush
.endproc


; rename the entry to the name typed, unless FAT can't hold it
.proc edit_save
    ldy wbEditLen
    beq bad
:   dey
    lda wbaEdit, y
    ldx #BAD_NAME_N - 1
:   cmp rbaBadName, x
    beq bad
    dex
    bpl :-
    tya
    bne :--
    lda wbaEdit ; "." and ".."
    cmp #'.'
    bne name
    ldy wbEditLen
    dey
    beq bad
    dey
    bne name
    lda wbaEdit + 1
    cmp #'.'
    beq bad
name:
    lda #MODE_LIST
    sta zbMode
    lda wbEditRow
    sta wbRow
    jsr sd_push_name
    bne fail
    ldy #0 ; the name it has: nothing to do
:   cpy wbEditLen
    beq end
    lda wbaEdit, y
    cmp wbaName, y
    bne go
    iny
    bne :-
end:
    lda wbaName, y
    bne go
    jsr name_pop
    jmp edit_end
go:
    jsr pointer_busy
    lda zbPathLen
    ldy zbOldLen
    ldx wbEditLen
    far ren_go
    jsr name_pop
    jmp op_done
bad:
    lda #FS_E_NAME
    jmp status_error
fail:
    pha
    jsr edit_end
    pla
    jmp status_error
.endproc


.proc next_rec
    clc
    lda zpRec
    adc #REC_SIZE
    sta zpRec
    bcc done
    inc zpRec + 1
done:
    rts
.endproc


; ------------------------------------ shortcuts: .lnk files whose first line is an SD card path

; the target of .lnk A/X (low/high), Y its length, into wbaName as "/sd" or "/sd/" and its path, wbLinkLen long; the
; file may give the path with or without a "/sd/" before it
; > A = status, Z set on success
.proc link_read
    sta zpSrc
    stx zpSrc + 1
    sty zbLen
    jsr sd_release
    lda #<wbaBlkData
    sta zpEdBuf
    lda #>wbaBlkData
    sta zpEdBuf + 1
    lda zpSrc
    ldx zpSrc + 1
    ldy zbLen
    jsr ed_finfo
    bne done
    lda #<LNK_MAX
    sta zwWalk
    lda #>LNK_MAX
    sta zwWalk + 1
    lda wbaEdInfo + FI_SIZE + 3
    ora wbaEdInfo + FI_SIZE + 2
    bne open
    lda wbaEdInfo + FI_SIZE + 1
    cmp #>LNK_MAX
    bcs open
    sta zwWalk + 1
    lda wbaEdInfo + FI_SIZE
    sta zwWalk
open:
    lda #FA_READ
    sta zbEdMode
    lda zpSrc
    ldx zpSrc + 1
    ldy zbLen
    jsr ed_fopen
    bne done
    lda zwWalk
    sta zwEdArg
    lda zwWalk + 1
    sta zwEdArg + 1
    lda #<wbaBlkData
    sta zpEdBuf
    lda #>wbaBlkData
    sta zpEdBuf + 1
    jsr ed_fread
    pha
    jsr ed_fclose
    pla
    beq link_parse
done:
    rts
.endproc

; link_read's target from the first line of the zwWalk bytes at wbaBlkData, less spaces or a "/" after it
; > A = status, Z set on success
.proc link_parse
    lda zwWalk + 1
    beq :+
    lda #$ff
    bne :++
:   lda zwWalk
:   sta zbT
    ldy #0
line:
    cpy zbT
    beq end
    lda wbaBlkData, y
    beq end
    cmp #$0d
    beq end
    cmp #$0a
    beq end
    iny
    bne line
end:
    tya
    beq bad
trim:
    lda wbaBlkData - 1, y
    cmp #' '
    beq :+
    cmp #'/'
    bne trimmed
:   dey
    bne trim
trimmed:
    sty zbT
    ; past a "/", or a "/sd" and the "/" after it
    ldx #0
    lda wbaBlkData
    cmp #'/'
    bne rest
    inx
    cpy #SD_LEN + 1
    bcc rest
    lda wbaBlkData + 1
    cmp rsSd
    bne rest
    lda wbaBlkData + 2
    cmp rsSd + 1
    bne rest
    ldx #SD_LEN + 1
    cpy #SD_LEN + 1
    beq rest
    lda wbaBlkData + SD_LEN + 1
    cmp #'/'
    beq :+
    ldx #1 ; a folder whose name starts "sd"
    bne rest
:   ldx #SD_LEN + 2
rest:
    stx zbLen
    lda #'/'
    sta wbaName
    lda rsSd
    sta wbaName + 1
    lda rsSd + 1
    sta wbaName + 2
    ldy #SD_LEN + 1
    cpx zbT
    bcs ok
    lda #'/'
    sta wbaName, y
    iny
copy:
    lda wbaBlkData, x
    sta wbaName, y
    iny
    beq bad
    inx
    cpx zbT
    bne copy
ok:
    sty wbLinkLen
    lda #0
    rts
bad:
    lda #FS_E_LINK
    rts
.endproc


; > A/X = the MCU's path for the link's target (low/high), Y = its length; empty for the card's root
.proc link_mcu
    lda wbLinkLen
    sec
    sbc #SD_LEN + 1
    tay
    lda #<(wbaName + SD_LEN + 1)
    ldx #>(wbaName + SD_LEN + 1)
    rts
.endproc


; after link_read: > C set when the target is a ROM
.proc link_rom
    jsr link_mcu
    jmp is_nes
.endproc


; after link_rom found a ROM: the 16 px icon in its resource section, as dx_icon16
; > Z set when it has one
.proc link_icon16
    pha
    jsr sd_release
    jsr link_mcu
    jsr rom_rsrc
    tax
    pla
    cpx #0
    bne done
    jmp rsrc_icon16
done:
    rts
.endproc


; the target link_read found: a ROM starts, a folder lists, a program runs, any other file shows in the viewer
; > A = status, Z set once the window shows it; the window as it was when it can't
.proc link_open
    lda wbLinkLen
    cmp #SD_LEN + 2
    bcs path
    lda #VOL_SD
    jsr vol_go
    lda #0
    rts
path:
    jsr pointer_busy
    jsr sd_release
    jsr link_mcu
    jsr is_dx
    bcc :+
    jsr link_mcu
    jsr dx_path
    jsr app_run
    lda #0
    rts
:   jsr link_mcu
    jsr is_nes
    bcc other
    jsr link_mcu
    jsr rom_launch
    jmp fail
other:
    lda #<wbaBlkData
    sta zpEdBuf
    lda #>wbaBlkData
    sta zpEdBuf + 1
    jsr link_mcu
    jsr ed_finfo
    bne fail
    ; wbaPath = "sd" and the rest of the target
    ldx wbLinkLen
    dex
    stx zbFileLen
:   lda wbaName, x
    sta wbaPath - 1, x
    dex
    bne :-
    lda wbaEdInfo + FI_ATTR
    and #AT_DIR
    beq file
    lda zbFileLen
    sta zbPathLen
    lda #VOL_SD
    sta wbVol
    jsr vol_folder
    lda #0
    rts
file:
    ldx #3
:   lda wbaEdInfo + FI_SIZE, x
    sta zdSize, x
    dex
    bpl :-
    ldy zbFileLen
:   dey
    lda wbaPath, y
    cmp #'/'
    bne :-
    sty zbPathLen
    jsr sd_view
    lda #0
    rts
fail:
    cmp #FR_NO_FILE
    beq gone
    cmp #FR_NO_PATH
    bne :+
gone:
    lda #FS_E_GONE
:   jmp pointer_idle
.endproc


; ------------------------------------ opening SD card files

; launch, run, follow or show the SD card file of page row wbRow: a ROM, a program, a shortcut, anything else
.proc sd_open_file
    jsr sd_push_name
    bne fail
    ldy zbPathLen
    jsr vol_path
    jsr is_lnk
    bcs link
    ldy zbPathLen
    jsr vol_path
    jsr is_nes
    bcc file
    jsr pointer_busy
    jsr sd_release
    ldy zbPathLen
    jsr vol_path
    jsr rom_prep
    bne refused
    lda zbOldLen ; the folder, without the ROM's name
    jsr state_save
    jsr launch_go
refused:
    jsr name_pop
    jsr pointer_idle
    jmp status_error
link:
    jsr pointer_busy
    ldy zbPathLen
    jsr vol_path
    jsr link_read
    bne refused
    jsr name_pop
    jsr link_open
    bne refused
    rts
file:
    lda zbPathLen
    sta zbFileLen
    jsr name_pop
    ldx #3
:   lda wbaEdInfo + FI_SIZE, x
    sta zdSize, x
    dex
    bpl :-
    ldy zbFileLen
    jsr vol_path
    jsr is_dx
    bcs prog
    lda #0
    jmp view_open
prog:
    ldy zbFileLen
    jsr vol_path
    jsr dx_path
    jmp exec_file
fail:
    jmp show_error
.endproc


; the viewer on the file zbFileLen and zdSize describe, from its start; A = status, shown instead when not 0
.proc view_open
    pha
    lda #MODE_VIEW
    sta zbMode
    jsr view_title
    jsr show_toolbar
    jsr rewind
    pla
    bne fail
    jmp show_text
fail:
    jmp show_error
.endproc


; ------------------------------------ programs

; load and start the program dx_path named, back to the listing when it ends; on failure the viewer shows why
.proc exec_file
    jsr pointer_busy
    lda #MODE_LIST
    sta wbRetMode
    jsr exec_ino
    bne fail
    rts
fail:
    pha
    lda #MODE_VIEW
    sta zbMode
    jsr view_title
    jsr show_toolbar
    jsr rewind
    pla
    jsr show_error
    jmp pointer_idle
.endproc


; load and start the program in wbaDxPath in the window, sized before anything of it shows
; > A = status, Z set once it started
.proc exec_ino
    jsr exec_load
    beq start
    rts
start:
    lda #MODE_APP
    sta zbMode
    lda #0
    sta zbAppExit
    sta zbAppFit
    sta zbIcon
    jsr app_init
    ldx #APP_TITLE_LEN - 1
:   lda wbaDxTitle, x
    sta wbaAppTitle, x
    dex
    bpl :-
    ldy #0
:   lda wbaDxPath, y
    sta wbaAppPath, y
    iny
    bne :-
    lda wbDxPathLen
    sta wbAppPathLen
    jsr app_icon
    lda #1
    sta wbSizing
    jsr app_draw
    lda #0
    sta wbSizing
    jsr app_refit
    lda #0
    rts
.endproc


; title, toolbar and chrome for the program, and its body drawn from blank
.proc app_frame
    jsr app_title
    lda zbFitW
    bne plain
    jsr show_toolbar
    lda #T_SB_UP_OFF
    sta zbUpTile
    lda #T_SB_DOWN_OFF
    sta zbDownTile
    lda #$ff
    sta zbThumb
    jsr show_scroll
    jsr blank_row
    jsr put_status
plain:
    jsr k_clear
    sec
    jsr pal_show
    jsr app_draw
    jsr vq_flush
    jsr pointer_idle
    lda zbAppExit
    bne quit
    lda zbAppFit
    bne refit
    rts
refit:
    jmp app_refit
quit:
    jmp app_quit
.endproc


; the window at the size the program asked for, drawn again
.proc app_refit
    lda #0
    sta zbAppFit
    jsr set_geometry
    jmp win_show
.endproc


; the window as it was before the program, in the file window's own size
.proc app_quit
    jsr backdrop_revert
    jsr app_drop
    lda wbRetMode
    cmp #MODE_VIEW
    beq view
    cmp #MODE_ICON
    beq icon
    jsr redraw_screen
    jmp load_dir
view:
    sta zbMode
    jmp win_show
icon:
    sta zbMode
    lda #1
    sta zbIcon
    jsr redraw_screen
    jsr vq_flush
    jmp pointer_idle
.endproc


; the file window's size again
; > Z clear when it changed
.proc fit_reset
    lda zbFitW
    beq done
    lda #0
    sta zbFitW
    sta zbFitH
    jsr set_geometry
    lda #1
done:
    rts
.endproc

; the program gone from the window: its icon, its palettes and its size
.proc app_drop
    lda #0
    sta wbAppIcon
    clc
    jsr pal_show
    jmp fit_reset
.endproc


; the program's icon, after exec_load: its own into T_WIN_APP, else exe_16; it stands for the folder in the title bar
.proc app_icon
    lda #T_WIN_APP
    jsr dx_icon16
    bne exe
    ldx #3
:   lda wbaIconPal, x
    sta wbaWinPal, x
    dex
    bpl :-
    lda #T_WIN_APP
    bne put
exe:
    ldx #3
:   lda wbaExePal, x
    sta wbaWinPal, x
    dex
    bpl :-
    lda #T_EXE16
put:
    sta wbWinTile
    lda #1
    sta wbAppIcon
    rts
.endproc


; the window's icon, the program's or else the folder's, into wbSprTile and wbaSprPal
.proc win_icon_pick
    lda wbAppIcon
    bne app
    lda #T_FOLDER16
    ldx #<wbaFolderPal
    ldy #>wbaFolderPal
    jmp spr_icon
app:
    lda wbWinTile
    ldx #<wbaWinPal
    ldy #>wbaWinPal
    jmp spr_icon
.endproc

; the title bar's icon sprites, the program's or else the folder's, while the window shows; the desktop's own them
; while it shows
.proc win_icon_sync
    lda zbIcon
    bne done
    lda zbMode
    cmp #MODE_START
    beq done
    lda wbNoIcon
    bne hide
    jsr win_icon_pick
    lda #2
    sta wbSprW
    jsr win_x0
    clc
    adc #TITLE_ICON_X
    sta wbSprX
    lda zbWinY
    clc
    adc #TITLE_ICON_Y - OAM_Y_BIAS
    ldx #WIN_OAM - OAM
    jmp icon_sprites_at
hide:
    ldx #WIN_OAM - OAM
    ldy #4
    jmp sprites_hide
done:
    rts
.endproc


; the program's title in the title bar, cut to fit, and its icon
.proc app_title
    lda #<wbaAppTitle
    sta zpTitle
    lda #>wbaAppTitle
    sta zpTitle + 1
    ldy #0
:   lda wbaAppTitle, y
    beq len
    iny
    cpy #DX_NAME_LEN
    bne :-
len:
    sty zbTitleLen
    lda zbWinW
    sec
    sbc #8 ; the room with the icon gone
    cmp zbTitleLen
    bcs :+
    sta zbTitleLen
:
    lda #0
    sta zbSlash
    jsr title_text
    jmp win_icon_sync
.endproc


; the program sees every frame's new buttons first, then unless it returns C set, A works the window controls
.proc app_update
    jsr app_listens
    beq pad
    lda zbPadNew
    jsr app_event
    lda wbRunReq
    bne run
    lda zbAppExit
    bne quit
    lda zbAppFit
    bne refit
    bcc pad
    rts
refit:
    jmp app_refit
pad:
    lda zbPadNew
    bmi click
    rts
click:
    jsr hit_test
    rts_jump rwaAppClick
run:
    jmp run_request
quit:
    jmp app_quit
.endproc


; ------------------------------------ text viewer

; the title bar with the open file's path
.proc view_title
    lda zbPathLen
    pha
    lda zbFileLen
    sta zbPathLen
    jsr show_title
    pla
    sta zbPathLen
    rts
.endproc


; back to the start of the open file, which is opened afresh
.proc rewind
    jsr sd_release
    lda #0
    sta zwNext
    sta zwNext + 1
    sta zwPos
    sta zwPos + 1
    sta zwLen
    sta zwLen + 1
    sta zbErr
    sta zbViewPage
    ldx #3
:   lda zdSize, x
    sta zdLeft, x
    dex
    bpl :-
    rts
.endproc


.proc view_prev
    lda zbViewPage
    cmp #2
    bcc done
    sbc #1
    jmp view_goto
done:
    rts
.endproc


; lay the file out again from its start and draw page A (1 on), or its last page when it has fewer
.proc view_goto
    sta zbWant
    jsr pointer_busy
restart:
    jsr rewind
    lda #1
    sta zbDry
skip:
    lda zbViewPage
    beq next ; the first page always exists
    jsr at_end
    bcs last
next:
    lda zbViewPage
    clc
    adc #1
    cmp zbWant
    bcs draw
    jsr show_text
    jmp skip
last:
    lda zbViewPage
    sta zbWant
    jmp restart
draw:
    lda #0
    sta zbDry
    jsr show_text
    jmp pointer_idle
.endproc


; draw the next page of the open file as text; nothing past its end
.proc show_text
    lda zbViewPage
    beq first
    jsr at_end
    bcs done
first:
    inc zbViewPage
    bne :+
    dec zbViewPage
:   lda #0
    sta zbI
row:
    jsr blank_row
    lda #0
    sta zbTextCol
char:
    jsr next_byte
    bcs put
    cmp #$0a
    beq put
    cmp #$0d
    beq char
    cmp #$09
    bne :+
    lda #' '
:   cmp #$20
    bcc dot
    cmp #$7f
    bcc keep
dot:
    lda #'.'
keep:
    ldx zbTextCol
    sta wbaRow, x
    inx
    stx zbTextCol
    cpx zbBodyW
    bne char
put:
    lda zbDry
    bne next
    lda zbI
    jsr put_row
next:
    inc zbI
    lda zbI
    cmp zbBodyH
    bne row
    lda zbDry
    bne done
    jsr view_chrome
    jsr vq_flush
    lda zbErr
    beq done
    ldx #0
    stx zbErr
    jmp show_error
done:
    rts
.endproc


; > C set when every byte of the file has been shown
; changes: A
.proc at_end
    lda zwPos
    cmp zwLen
    bne more
    lda zwPos + 1
    cmp zwLen + 1
    bne more
    lda zdLeft
    ora zdLeft + 1
    ora zdLeft + 2
    ora zdLeft + 3
    bne more
    sec
    rts
more:
    clc
    rts
.endproc


; > A = next byte of the file, C set at its end
; changes: A, Y
.proc next_byte
    lda zwPos
    cmp zwLen
    bne have
    lda zwPos + 1
    cmp zwLen + 1
    bne have
    jsr refill
    bcs done
have:
    clc
    lda #<wbaBlkData
    adc zwPos
    sta zpSrc
    lda #>wbaBlkData
    adc zwPos + 1
    sta zpSrc + 1
    ldy #0
    lda (zpSrc), y
    inc zwPos
    bne :+
    inc zwPos + 1
:   clc
done:
    rts
.endproc


; the next block of the file into wbaBlkData, or what is left of it
; > C set at its end, or on a read error (left in zbErr)
.proc refill
    lda zdLeft
    ora zdLeft + 1
    ora zdLeft + 2
    ora zdLeft + 3
    bne :+
    sec
    rts
:   lda zdLeft + 3
    ora zdLeft + 2
    bne full
    lda zdLeft + 1
    cmp #>BLOCK_SIZE
    bcs full
    lda zdLeft
    sta zwLen
    lda zdLeft + 1
    sta zwLen + 1
    jmp read
full:
    lda #<BLOCK_SIZE
    sta zwLen
    lda #>BLOCK_SIZE
    sta zwLen + 1
read:
    jsr sd_bread
    bne fail
    inc zwNext
    bne :+
    inc zwNext + 1
:   sec
    lda zdLeft
    sbc zwLen
    sta zdLeft
    lda zdLeft + 1
    sbc zwLen + 1
    sta zdLeft + 1
    lda zdLeft + 2
    sbc #0
    sta zdLeft + 2
    lda zdLeft + 3
    sbc #0
    sta zdLeft + 3
    lda #0
    sta zwPos
    sta zwPos + 1
    clc
    rts
fail:
    sta zbErr
    lda #0
    sta zwPos
    sta zwPos + 1
    sta zwLen
    sta zwLen + 1
    ldx #3
:   sta zdLeft, x
    dex
    bpl :-
    sec
    rts
.endproc


; zwLen bytes of the viewed SD card file, from block zwNext on, into wbaBlkData; the file stays open for the next
; > A = status, Z set on success
.proc sd_bread
    lda zbHeld
    cmp #HOLD_VIEW
    beq held
    lda #HOLD_VIEW
    sta zbHoldId
    ldy zbFileLen
    jsr vol_path
    jsr sd_hold
    bne done
held:
    lda zwNext
    sta zwBlk
    lda zwNext + 1
    sta zwBlk + 1
    lda zwLen
    sta zwBlkLen
    lda zwLen + 1
    sta zwBlkLen + 1
    lda #<wbaBlkData
    sta zpEdBuf
    lda #>wbaBlkData
    sta zpEdBuf + 1
    jmp sd_read
done:
    rts
.endproc


; ------------------------------------ drawing

; the path on the lower row of the title bar, under a white strip on the upper row
.proc show_title
    lda #<wbaPath
    sta zpTitle
    lda #>wbaPath
    sta zpTitle + 1
    lda zbPathLen
    sta zbTitleLen
    lda #1
    sta zbSlash
    ; [fall_through]
.endproc

; zbTitleLen characters at zpTitle in the title bar, over the icon when they don't fit beside it, and their tail
; when they don't fit at all
.proc title_text
    lda zbWinW
    sec
    sbc #(TITLE_TEXT_X + CAP_MIN + 2 + 7) / 8
    sta zbT ; characters that fit between the icon and the buttons
    lda zbTitleLen
    clc
    adc zbSlash
    ldx #0
    cmp zbT
    beq :+
    bcc :+
    lda zbT
    clc
    adc #(TITLE_TEXT_X + CAP_MIN + 2 + 7) / 8 - (TITLE_ICON_X + CAP_MIN + 2 + 7) / 8
    sta zbT
    inx
:   stx wbNoIcon
    ldx #0
    lda zbTitleLen
    cmp zbT
    bcs tail
    ldy #0
    lda zbSlash
    beq copy
    lda #'/'
    sta wbaRow, x
    inx
    bne copy
tail:
    sbc zbT
    tay
copy:
    cpy zbTitleLen
    beq end
    lda (zpTitle), y
    sta wbaRow, x
    inx
    iny
    bne copy
end:
    stx zbGn
    ; the band from the icon to the buttons, then the text
    jsr win_x0
    clc
    adc #FRAME
    sta zbGx
    lda zbWinY
    clc
    adc #FRAME
    sta zbGy
    jsr win_x1
    sec
    sbc #CAP_MIN + FRAME
    sec
    sbc zbGx
    sta zbGw
    lda #BAND_H
    sta zbGh
    lda #C_ACCENT
    jsr gfx_rect
    jsr win_x0
    clc
    adc #TITLE_TEXT_X
    ldx wbNoIcon
    beq :+
    sec
    sbc #TITLE_TEXT_X - TITLE_ICON_X
:   sta zbGx
    lda zbWinY
    clc
    adc #TITLE_TEXT_Y
    sta zbGy
    lda #C_WHITE
    sta zbGc
    lda #C_ACCENT
    sta zbGb
    jmp gfx_text_row
.endproc
.assert (TITLE_ICON_X + CAP_MIN + 2 + 7) / 8 = 8, error, "app_title cuts a title to the window's width - 8"


; Back, Forward, Up and Root, grayed where they would do nothing
.proc show_toolbar
    lda zbMode
    cmp #MODE_VIEW
    beq view
    cmp #MODE_APP
    beq app
    ldx #T_BACK + T_OFF
    lda wbHistPos
    beq :+
    ldx #T_BACK
:   stx zbaTool
    ldx #T_FWD + T_OFF
    lda wbHistPos
    clc
    adc #1
    cmp wbHistLen
    bcs :+
    ldx #T_FWD
:   stx zbaTool + 1
    ldx #T_UP + T_OFF
    ldy #T_ROOT + T_OFF
    lda wbVol
    beq put
    ldx #T_UP
    ldy #T_ROOT
    bne put
view:
    lda #T_BACK
    sta zbaTool
    lda #T_FWD + T_OFF
    sta zbaTool + 1
    ldx #T_UP
    ldy #T_ROOT
    bne put
app:
    lda #T_BACK
    sta zbaTool
    lda #T_FWD + T_OFF
    sta zbaTool + 1
    ldx #T_UP + T_OFF
    ldy #T_ROOT + T_OFF
put:
    stx zbaTool + 2
    sty zbaTool + 3
    lda #0
    sta zbI
button:
    jsr win_x0
    clc
    adc #TOOL_X
    ldx zbI
    beq :++
:   clc
    adc #TOOL_STEP
    dex
    bne :-
:   sta zbGx
    lda zbWinY
    clc
    adc #TOOL_Y
    sta zbGy
    ldx zbI
    lda zbaTool, x
    jsr gfx_tool
    inc zbI
    lda zbI
    cmp #4
    bne button
    rts
.endproc


; scroll bar and status line for the listing
.proc list_chrome
    lda zbBodyH
    sec
    sbc #1
    clc
    adc zwCount
    tax
    lda zwCount + 1
    adc #0
    sta zbT
    txa
    ldx zbT
    jsr set_num16
    lda zbBodyH
    jsr udiv32_8
    jsr num_byte
    bne :+
    lda #1
:   sta zbPages
    lda zwTop
    ldx zwTop + 1
    jsr set_num16
    lda zbBodyH
    jsr udiv32_8
    jsr num_byte
    sta zbPageIdx

    ldx #T_SB_UP_OFF
    lda zwTop
    ora zwTop + 1
    beq :+
    ldx #T_SB_UP
:   stx zbUpTile
    ldx #T_SB_DOWN_OFF
    clc
    lda zwTop
    adc zbBodyH
    sta zbT
    lda zwTop + 1
    adc #0
    cmp zwCount + 1
    bcc down
    bne :+
    lda zbT
    cmp zwCount
    bcs :+
down:
    ldx #T_SB_DOWN
:   stx zbDownTile

    ; thumb row = 1 + page * (track rows - 1) / (pages - 1)
    lda #$ff
    sta zbThumb
    lda zbPages
    cmp #2
    bcc scroll
    lda #0
    tax
    jsr set_num16
    lda zbBodyH
    sec
    sbc #3
    tax
mul:
    clc
    lda zdNum
    adc zbPageIdx
    sta zdNum
    lda zdNum + 1
    adc #0
    sta zdNum + 1
    dex
    bne mul
    lda zbPages
    sec
    sbc #1
    jsr udiv32_8
    ldx zdNum
    inx
    stx zbThumb
scroll:
    jsr show_scroll

    jsr blank_row
    lda zbPageIdx
    ldx #0
    jsr set_num16
    inc zdNum
    bne :+
    inc zdNum + 1
:   ldy #0
    jsr put_dec
    lda #'/'
    sta wbaRow, y
    iny
    lda zbPages
    ldx #0
    jsr set_num16
    jsr put_dec
    jsr align_right
    lda zwCount
    ldx zwCount + 1
    jsr set_num16
    ldy #1
    jsr put_dec
    lda #<rsItems
    ldx #>rsItems
    jsr put_str
    jmp put_status
.endproc


; scroll bar and status line for the viewer
.proc view_chrome
    lda #$ff
    sta zbThumb
    ldx #T_SB_UP_OFF
    lda zbViewPage
    cmp #2
    bcc :+
    ldx #T_SB_UP
:   stx zbUpTile
    ldx #T_SB_DOWN
    jsr at_end
    bcc :+
    ldx #T_SB_DOWN_OFF
:   stx zbDownTile
    jsr show_scroll

    jsr blank_row
    ldy #0
    lda #<rsPage
    ldx #>rsPage
    jsr put_str
    lda zbViewPage
    ldx #0
    jsr set_num16
    jsr put_dec
    jsr align_right
    ldx #3
:   lda zdSize, x
    sta zdNum, x
    dex
    bpl :-
    ldy #1
    jsr put_dec
    lda #<rsBytes
    ldx #>rsBytes
    jsr put_str
    jmp put_status
.endproc


; the scroll bar beside the rows: zbUpTile, the track with the thumb zbThumb rows down it, zbDownTile
.proc show_scroll
    jsr win_x1
    sec
    sbc #FRAME + SB_W
    sta zbGx
    lda zbBodyY
    sec
    sbc #1
    sta zbGy
    lda #SB_W
    sta zbGw
    lda zbBodyH
    asl
    asl
    asl
    clc
    adc #2
    sta zbGh
    jsr gfx_checker
    lda zbGy
    clc
    adc zbGh
    sec
    sbc #SB_W
    pha
    lda zbUpTile
    jsr gfx_sb
    pla
    sta zbGy
    lda zbDownTile
    jsr gfx_sb
    lda zbThumb
    cmp #$ff
    beq done
    asl
    asl
    asl
    clc
    adc zbBodyY
    sec
    sbc #1
    sta zbGy
    lda #T_SB_THUMB
    jmp gfx_sb
done:
    rts
.endproc


; move the Y characters at the start of wbaRow to its right end, one column in, blanking where they were
.proc align_right
    cpy #0
    beq done
    ldx zbBodyW
    dex
loop:
    dey
    dex
    lda wbaRow, y
    sta wbaRow, x
    lda #' '
    sta wbaRow, y
    cpy #0
    bne loop
done:
    rts
.endproc


; wbaRow as the status line
.proc put_status
    lda zbWinY
    clc
    adc zbWinH
    sec
    sbc #STATUS_BOT
    sta zbGy
    lda #C_GRAY
    jmp text_row
.endproc


; A = status, shown on the status line
.proc status_error
    jsr error_text
    jsr put_status
    jmp vq_flush
.endproc


; A = status, shown on the first body row; the rest of the body is cleared
.proc show_error
    pha
    lda #0
    sta zbShown
    pla
    jsr error_text
    lda #0
    jsr put_row
    lda #1
    sta zbI
rest:
    jsr blank_row
    lda zbI
    jsr put_row
    inc zbI
    lda zbI
    cmp zbBodyH
    bne rest
    jmp vq_flush
.endproc


; A = status as text in wbaRow
.proc error_text
    pha
    jsr blank_row
    pla
    cmp #FS_E_FIRST
    bcc code
    cmp #FS_E_LONG + 1
    bcs code
    sec
    sbc #FS_E_FIRST
    asl
    tax
    lda rwaErrors, x
    sta zpSrc
    lda rwaErrors + 1, x
    sta zpSrc + 1
    ldy #0
msg:
    lda (zpSrc), y
    beq done
    sta wbaRow, y
    iny
    bne msg
code:
    pha
    ldx #0
text:
    lda rsError, x
    beq hex
    sta wbaRow, x
    inx
    bne text
hex:
    pla
    pha
    lsr
    lsr
    lsr
    lsr
    jsr hex_digit
    sta wbaRow, x
    pla
    and #$0f
    jsr hex_digit
    sta wbaRow + 1, x
done:
    rts
.endproc


; A = 0-15 as an ASCII hex digit
.proc hex_digit
    cmp #10
    bcc digit
    adc #'A' - '0' - 10 - 1
digit:
    adc #'0'
    rts
.endproc


; changes: A, X
.proc blank_row
    lda #' '
    ldx zbBodyW
    dex
loop:
    sta wbaRow, x
    dex
    bpl loop
    rts
.endproc


; wbaRow as body row A, white on navy, the row's spans in PAL_TITLE for it
; changes: A, X, Y
.proc put_row_lit
    jsr row_y
    lda zbBodyX
    asl
    asl
    asl
    sta zbGx
    lda zbBodyW
    asl
    asl
    asl
    sta zbGw
    lda #FONT_H
    sta zbGh
    lda #PAL_TITLE
    jsr gfx_pal
    lda #C_ACCENT
    ldx #C_WHITE
    jmp text_row_fg
.endproc


; zbGy = body row A's
.proc row_y
    asl
    asl
    asl
    clc
    adc zbBodyY
    sta zbGy
    rts
.endproc


; wbaRow as body row A, black on white, which PAL_PANEL and PAL_TITLE show alike
; changes: A, X, Y
.proc put_row
    jsr row_y
    lda #C_WHITE
    ; [fall_through]
.endproc

; wbaRow's zbBodyW characters at the body's left, row zbGy, black on color A
.proc text_row
    ldx #C_BLACK
    ; [fall_through]
.endproc

; the same in color X on color A
.proc text_row_fg
    stx zbGc
    sta zbGb
    lda zbBodyX
    asl
    asl
    asl
    sta zbGx
    lda zbBodyW
    sta zbGn
    jmp gfx_text_row
.endproc
