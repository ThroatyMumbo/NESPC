.ifndef _DESK_
    _DESK_ = 1

.include "abi.inc"
.include "taskbar.inc"

PPU_CTRL   = $2000
PPU_MASK   = $2001
PPU_STATUS = $2002
OAM_ADDR   = $2003
PPU_SCROLL = $2005
PPU_ADDR   = $2006
PPU_DATA   = $2007
APU_DMC    = $4010
OAM_DMA    = $4014
APU_STATUS = $4015
JOYPAD1    = $4016
APU_FRAME  = $4017
MASK_VALUE = %00011110 ; BG and sprites on, including the left 8 pixels

MENU       = $5007 ; bit7 host wants the menu (rtl/menu_ret.sv)
HOST_PAD   = $5008 ; buttons pressed from the host (tap 0x10, tools/desk.py pad)
DESK_BEAT  = $5009 ; write: the main loop's heartbeat, once the boot's card reads are done (tap 0x14, desk.py status)
MENU_STUB  = $0300 ; kept clear of BSS (conf/ld.cfg)
DESK_BANK  = $5010 ; PSRAM bank at $8000 (rtl/map_desk.sv), 0 = the image's first 16 KB: the pictures
SHELL_BANK = 2 ; the image's third 16 KB: segment SHELL, the home shell bank, at $8000 from reset (conf/ld.cfg)
SHELL3_BANK = 3 ; segment SHELL3: the desktop and file operations
APP_BANK   = $40

; the bitmap's blitter (rtl/blit.sv): registers latched when GFX_OP is written
GFX_DX    = $5020
GFX_DY    = $5021
GFX_W     = $5022 ; 0 = 256
GFX_H     = $5023
GFX_SX    = $5024
GFX_SY    = $5025
GFX_FG    = $5026
GFX_BG    = $5027
GFX_KEY   = $5028
GFX_FLAGS = $5029
GFX_CX0   = $502A ; clip, x1 and y1 exclusive, 0 = 256
GFX_CY0   = $502B
GFX_CX1   = $502C
GFX_CY1   = $502D
GFX_OP    = $502E ; read: bit 7 busy
GFX_DATA  = $502F ; EXPAND and IMAGE rows
GFX_WIN   = $5030 ; page of GFX_WINDOW: spans' bytes from 0, their palettes from 8
GFX_WINDOW = $5800
OP_FILL   = 1
OP_COPY   = 2
OP_EXPAND = 3
OP_IMAGE  = 4
OP_PAL    = 5
GF_BG_CLEAR = 1 ; GFX_FLAGS
GF_KEY    = 2
GF_XOR    = 4
GF_OVER   = 8 ; draws inside the mask
GFX_MX0   = $5031 ; the mask, which only GF_OVER draws into: x1 and y1 exclusive, 0 = 256; off while x0 = x1
GFX_MY0   = $5032
GFX_MX1   = $5033
GFX_MY1   = $5034
BD_LEN    = 9 ; the desktop's background (backdrop.s): the color, then the pattern's rows, MSB leftmost
MODE_START = 0 ; reset state: the first update loads the saved state, then the desktop (browser.s boot)
MODE_LIST  = 1
MODE_VIEW  = 2
MODE_ASK   = 3 ; trash, delete or empty prompt on the last body row
MODE_ICON  = 4 ; window minimized or closed to its desk icon
MODE_EDIT  = 5 ; the selected entry's new name typed on its row
MODE_APP   = 6 ; a program (exec.s) owns the body
MODE_MENU  = 7 ; the Start menu (menu.s) is open over wbMenuRet's screen
MODE_POPUP = 8 ; a right-click menu (popup.s) over wbPopRet's screen

; background palettes: the desk's black, teal, white and yellow; then black, gray and white with dark gray and navy;
; then the desk's with navy, for desktop pictures (tools/mkicons.py desk_picture)
.define BG_PALETTE $0f, $1c, $30, $28, $0f, $10, $30, $00, $0f, $10, $30, $02, $0f, $1c, $30, $02
C_DESK     = 1 ; teal, in PAL_DESK

; executable header at $8000 in APP_BANK, as apps/include/desk.inc and tools/mkdx.py build it
DX_MAGIC   = $8000 ; "DSKX"
DX_FORMAT  = $8004
DX_API     = $8005
DX_DRAW    = $8006
DX_EVENT   = $8008 ; 0 for none
DX_NAME    = $800A ; the title; empty for the file's name without ".dx"
DX_NAME_LEN = 16
DX_IMAGE   = $801A ; bytes of the file loaded into the bank
DX_RSRC    = $801C ; file offset of the resource section, on a block boundary; 0 for none
DX_HEADER_SIZE = 30
DX_MAX     = $4000
DX_API_OLD    = 3 ; the oldest this Desk runs
RSRC_ICON  = 1 ; resource type: sprite records of a square icon, its size in pixels beside it
RSRC_PICTURE = 2 ; a 32 px desktop picture: IMAGE data, then a byte a row of its spans' palettes (tools/mkicons.py)
OAM        = $0200
OAM_Y_BIAS = 1 ; OAM Y is one line above the sprite
MENU_OAM   = OAM + 1 * 4 ; MENU_APPS icons of 4 sprites
WIN_OAM    = MENU_OAM + MENU_APPS * 4 * 4 ; the title bar's icon, 4 sprites
TASK_OAM   = WIN_OAM + 4 * 4 ; TASK_MAX icons of 4 sprites

; sprite table (tools/mkchr.py): assets/cursors.png in reading order, then the sprite icons, 2x2 unless noted
T_POINTER  = $00
T_HOURGLASS = $52
T_EXE16    = $80 ; the system's first (their palettes in wbaSysPal): a program's without its own
T_FOLDER16 = $98 ; the file window's, in the title bar
T_ROM16    = $9C ; a shortcut to a ROM
T_MENU_ICON = $A4 ; MENU_APPS of them, the Start menu's
T_WIN_APP  = $BC ; the running program's, in the title bar
; IMAGE pictures in bank 0 (tools/mkchr.py): toolbar buttons, each followed by its grayed copy, then scroll bar parts
T_BACK     = 0
T_FWD      = 2
T_UP       = 4
T_ROOT     = 6
T_OFF      = 1
T_SB_UP    = 0
T_SB_DOWN  = 1
T_SB_UP_OFF = 2
T_SB_DOWN_OFF = 3
T_SB_THUMB = 4
TOOL_IMG   = 16 * 16 / 4 ; bytes a 16x16 picture
SB_IMG     = 8 * 8 / 4
CAP_IMG    = 16 * 14 / 4

; screen layout in pixels; window columns and widths are in 8-pixel spans, as the palettes are
SCREEN_H   = TASK_Y ; above the taskbar (taskbar.inc)
FONT_W     = 8
FONT_H     = 8
ICON_X     = 16 ; desktop icons while the window is hidden, down columns: Files, then nespc/desktop's
ICON_Y     = 8
ICON_X2    = 120 ; the second column
ICON_PITCH = 48
DESK_ROWS  = 4
DESK_APPS  = 6 ; shortcuts and programs from nespc/desktop it shows
DESK_BIN   = $81 ; desk_hit's answer for the recycle bin, at the top right
ICON_SIZE  = 32
BIN_X      = 256 - ICON_X - ICON_SIZE
BIN_Y      = ICON_Y
.assert PICTURE_LEN = ICON_SIZE * ICON_SIZE / 4 + ICON_SIZE, error, "a desktop picture is an icon's size"
LABEL_GAP  = 1 ; label rows under an icon
DESK_LABEL_MAX = 11 ; letters of a desktop icon's label


FRAME      = 3 ; window edge
TITLE_H    = 21 ; the edge's top 3, then the navy band
BAND_H     = 18
TITLE_ICON_X = FRAME + 2
TITLE_ICON_Y = FRAME + 1 ; a navy row above and below it
TITLE_TEXT_X = TITLE_ICON_X + 16 + 3
TITLE_TEXT_Y = FRAME + 5
CAP_Y      = FRAME + 2 ; 16x14 caption buttons
CAP_CLOSE  = FRAME + 2 + 16 ; from the window's right edge: close, a gap, zoom, then minimize against it
CAP_ZOOM   = CAP_CLOSE + 2 + 16
CAP_MIN    = CAP_ZOOM + 16
CAPTION_MIN   = 0 ; gfx_caption's buttons
CAPTION_ZOOM  = 1
CAPTION_CLOSE = 2
TOOL_Y     = TITLE_H + 1 ; toolbar pictures, 16x16, every 24 pixels from TOOL_X
TOOL_X     = 8
TOOL_STEP  = 24
TOOL_H     = 18
BODY_EDGE_Y = TITLE_H + TOOL_H ; the listing's sunken edge, then a pad above its rows
BODY_TOP   = BODY_EDGE_Y + 2
FRAMED_H   = 60 ; a framed window's height without its rows
STATUS_BOT = 14 ; status text this far above the window's bottom
SB_W       = 8 ; scroll bar, inside the right edge
PLAIN_TOP  = TITLE_H + 3 ; a program's body below its title bar
PLAIN_H    = 29 ; a program's window's height without its body rows
MENU_W     = 128 ; Start menu, from the left edge, standing on the taskbar
MENU_ENTRY_H = 16
MENU_EDGE  = 3
MENU_ICON_X = 8
MENU_TEXT_X = 32
MENU_APPS  = 6 ; shortcuts and programs from nespc/menu it lists
MENU_NAME  = 12 ; letters of a program's title it shows, and the NUL
APP_TITLE_LEN = DX_NAME_LEN + 1
MENU_NONE  = 0 ; menu_update: still open
MENU_SHUT  = 1 ; closed with nothing picked
MENU_APP   = 2 ; the program or shortcut in wbaDxPath
POP_MAX    = 6 ; a right-click menu's items
POP_W      = 104 ; its width: 11 letters, a span's margin either side
POP_TEXT_X = 8
POP_NONE   = $ff ; popup_update: still open
POP_SHUT   = $fe ; closed with nothing picked; else the item's index

BODY_H_MAX = 20
FIT_MIN_W  = 11 ; narrowest program window: the title bar's icon, caption buttons and a letter

.global upload_sprites, set_geometry, redraw_screen, draw_taskbar, pointer_init, pointer_update, pointer_busy, pointer_idle, browser_update
.global pointer_put
.global start_key
.global state_window, state_save, rom_prep, rom_launch, link_read, link_mcu, link_rom, link_icon16, app_run
.global vq_row, vq_flush, vq_nmi, wbaRow
.global vq_pal, rbaPalette, pal_show, app_init, wbNoIcon
.global blank_row, put_row, exec_load, k_clear, pointer_px, host_poll, menu_exit
.global shell_bank, shell_ram_clear, set_bank, far_call, app_draw, app_event, app_listens
.globalzp zbBank, zpDxDir

; to entry A of table, a .word list of addresses less one, through rts; changes: A, X
.macro rts_jump table
    asl
    tax
    lda table + 1, x
    pha
    lda table, x
    pha
    rts
.endmacro

; a call into another shell bank's code (conf/ld.cfg), which tools/bankcheck.py requires there
.macro far proc
    jsr far_call
    .addr proc
    .byte <.bank(proc)
.endmacro
.global clock_init, clock_update, clock_refresh, clock_ampm, clock_ampm_set
.global jingle_boot, jingle_tick
.global task_paint, task_sync, task_hit, win_icon_pick, wbSizing
.global menu_open, menu_update, menu_close, start_paint, menu_row
.global popup_open, popup_update, pop_add, wbPopN, wbaPopL, wbaPopH
.global vq_spr, dx_open, dx_path, dx_join, lnk_title, wbaDxPath, wbDxPathLen, dx_icon16, rsrc_icon16, icon_upload, wbaDxTitle, wbaIconPal, wbaExePal, wbaRomPal
.global spr_icon, icon_sprites_at, sprites_hide, wbSprX, wbSprW, wbSprTile, wbaSprPal, wbAppIcon, wbaFolderPal
.global desk_scan, desk_draw, desk_hit, desk_path, icons_reset, dx_picture, rsrc_picture
.global gfx_wait, gfx_rect, gfx_pal, gfx_bevel, gfx_window, strlen, gfx_puts, gfx_text, gfx_text_row, gfx_image, gfx_copy
.global gfx_clip, gfx_noclip, gfx_tool, gfx_sb, gfx_caption, gfx_checker, gfx_pattern, gfx_folder, gfx_exe
.global gfx_bin
.global backdrop_init, backdrop_fill, backdrop_get, backdrop_set, backdrop_revert, wbaDeskPal, wbaAppPal
.global color_legal, scheme_init, scheme_get, scheme_set, scheme_revert, scheme_pal, scheme_put, backdrop_put
.global saver_get, saver_set, saver_resume, saver_list, saver_none
.global run_request, wbRunReq, wbRunArg, wbResume, wbKey, rom_list, rom_pic, rom_run, key_get
.global wbBinFull
.global win_x0, win_x1, body_px
.globalzp zbPx, zbPy
.globalzp zbAppExit, zbAppFit, zbFitW, zbFitH
.global udiv32_8, put_dec, put_str
.globalzp zbPad, zbPadNew, zbX, zbY, zdNum, zbMode, zbFrame
.global key_next
.globalzp zbWinX, zbWinY, zbWinW, zbWinH, zbBodyX, zbBodyY, zbBodyW, zbBodyH, zbZoom, zbIcon, zbClosed
.globalzp zbGx, zbGy, zbGw, zbGh, zbGc, zbGb, zpGs, zbGn

.endif
