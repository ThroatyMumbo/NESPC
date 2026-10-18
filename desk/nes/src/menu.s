; The Start menu: a box over the Start button listing nespc/menu's shortcuts (.lnk) and programs (.dx) by title and
; icon, with Start pressed while it shows.

.include "desk.inc"
.include "fs.inc"
.include "edio.inc"
.include "paths.inc"

MENU_FILE = 128 ; a listed file's name and its NUL; longer names aren't listed

.segment "ZEROPAGE"

zpMenu: .res 2

.segment "WRAM"

wbaMenuFile: .res MENU_APPS * MENU_FILE

.segment "SHELL_BSS"

wbMenuN:    .res 1 ; programs listed
wbMenuTop:  .res 1 ; pixel row of the box's top edge
wbMenuHot:   .res 1 ; entry under the pointer, $ff for none
wbMenuI:     .res 1
wbMenuE:     .res 1
wbMenuT:     .res 1
wbRowX:      .res 1 ; menu_row's box
wbRowY:      .res 1
wbRowW:      .res 1
wbRowT:      .res 1
wbRowC:      .res 1
wbStartDown: .res 1 ; 1: start_paint paints Start pressed
wbMenuEnd:   .res 1 ; programs menu_scan found
wbaMenuName: .res MENU_APPS * MENU_NAME ; titles
wbaMenuTile: .res MENU_APPS ; first sprite tile of each icon
wbaMenuPal:  .res MENU_APPS * 4

.segment "RODATA"

rsStart:    .byte "Menu"
rsStartEnd:
rsMenuDir:  .byte NESPC_MENU
MENU_DIR_LEN = * - rsMenuDir

; the box: its edges and an entry per program
.assert MENU_EDGE * 2 + MENU_APPS * MENU_ENTRY_H <= SCREEN_H - ICON_Y, error, "a full Start menu is taller than the desk"

.segment "SHELL"

.proc menu_open
    jsr pointer_busy
    clc ; a program may own the panels' colors; app_frame gives them back
    jsr pal_show
    jsr menu_scan
    lda #$ff
    sta wbMenuHot
    lda wbMenuN
    asl
    asl
    asl
    asl
    adc #MENU_EDGE * 2 ; C clear: at most MENU_APPS * 16
    eor #$ff
    sec
    adc #SCREEN_H
    sta wbMenuTop
    jsr gfx_noclip
    lda #0
    sta zbGx
    lda wbMenuTop
    sta zbGy
    lda #MENU_W
    sta zbGw
    lda #SCREEN_H
    sec
    sbc wbMenuTop
    sta zbGh
    lda #PAL_PANEL
    jsr gfx_pal
    lda #BEVEL_WINDOW
    jsr gfx_bevel
    lda #0
    sta wbMenuI
entry:
    lda wbMenuI
    cmp wbMenuN
    beq :+
    jsr menu_entry
    inc wbMenuI
    bne entry
:   sec
    jsr start_paint
    jsr menu_icons
    jmp pointer_idle
.endproc


; Start raised again and the icons gone; the caller redraws what the box covered
.proc menu_close
    jsr icons_hide
    clc
    jmp start_paint
.endproc


; > A = MENU_NONE while the menu stays open, else what closed it; MENU_APP with its file given to dx_path
.proc menu_update
    jsr menu_hot
    cmp wbMenuHot
    beq pad
    ldx wbMenuHot
    sta wbMenuHot
    txa
    bmi :+
    jsr menu_entry
:   lda wbMenuHot
    bmi :+
    jsr menu_entry
:   jsr vq_flush
pad:
    lda zbPadNew
    bmi pick
    and #JOYPAD_B
    bne shut
    lda #MENU_NONE
    rts
pick:
    lda wbMenuHot
    bmi shut
    jsr menu_path
    lda #MENU_APP
    rts
shut:
    lda #MENU_SHUT
    rts
.endproc


; > A = entry under the pointer, $ff for none
.proc menu_hot
    jsr pointer_px
    lda zbPx
    cmp #MENU_W
    bcs none
    ldx wbMenuN
    dex
    bmi none
entry:
    txa
    pha
    jsr entry_row
    stx wbMenuT
    pla
    tax
    lda zbPy
    sec
    sbc wbMenuT
    cmp #MENU_ENTRY_H
    bcc found
    dex
    bpl entry
none:
    lda #$ff
    rts
found:
    txa
    rts
.endproc


; the first MENU_APPS shortcuts and programs in nespc/menu, in the card's order: their titles cut to MENU_NAME - 1
; letters, and their icons
.proc menu_scan
    lda #<wbaMenuFile
    sta zpScanTo
    lda #>wbaMenuFile
    sta zpScanTo + 1
    lda #<scan_dx_lnk
    sta wpScanHook
    lda #>scan_dx_lnk
    sta wpScanHook + 1
    lda #MENU_FILE
    sta wbScanMax
    sta wbScanSlot
    lda #MENU_APPS
    sta wbScanCap
    lda #<rsMenuDir
    ldx #>rsMenuDir
    ldy #MENU_DIR_LEN - 1
    jsr dir_scan
    sta wbMenuEnd
    lda #0
    sta wbMenuN
info:
    lda wbMenuN
    cmp wbMenuEnd
    beq done
    jsr scan_entry
    inc wbMenuN
    bne info
done:
    jmp vq_flush ; the last icon's tiles are still queued
.endproc


; menu entry wbMenuN's title and icon: a program's from its header, a shortcut titled by its name less ".lnk"
.proc scan_entry
    lda wbMenuN
    jsr menu_path
    lda #<wbaDxPath
    ldx #>wbaDxPath
    ldy wbDxPathLen
    jsr is_lnk
    bcs link
    jsr dx_open
    bne exe
    jsr own_tile
    jsr dx_icon16
    bne exe
own:
    jsr own_tile
    ldx #<wbaIconPal
    ldy #>wbaIconPal
    jmp pals
link:
    lda #<wbaDxPath
    ldx #>wbaDxPath
    ldy wbDxPathLen
    jsr link_read
    bne named
    jsr link_mcu
    jsr is_dx
    bcc rom
    jsr link_mcu ; a program: its own icon
    jsr dx_path
    jsr dx_open
    bne named
    jsr own_tile
    jsr dx_icon16
    bne named
    jsr link_title
    jmp own
rom:
    jsr link_rom
    bcc named
    jsr own_tile
    jsr link_icon16
    bne cart
    jsr link_title
    jmp own
named:
    jsr link_title
    jmp exe
cart:
    jsr link_title
    lda #T_ROM16
    ldx #<wbaRomPal
    ldy #>wbaRomPal
    jmp pals
exe:
    lda #T_EXE16
    ldx #<wbaExePal
    ldy #>wbaExePal
pals:
    jsr spr_icon
    ldx wbMenuN
    sta wbaMenuTile, x
    txa
    asl
    asl
    tax
    ldy #0
:   lda wbaSprPal, y
    sta wbaMenuPal, x
    inx
    iny
    cpy #4
    bne :-
    lda wbMenuN
    jsr name_off
    tax
    ldy #0
title:
    lda wbaDxTitle, y
    sta wbaMenuName, x
    beq done
    inx
    iny
    cpy #MENU_NAME - 1
    bne title
    lda #0
    sta wbaMenuName, x
done:
    rts
.endproc


; wbaDxTitle = entry wbMenuN's file name less ".lnk"
.proc link_title
    lda wbMenuN
    jsr file_ptr
    lda zpMenu
    ldx zpMenu + 1
    jmp lnk_title
.endproc


; > A = first sprite tile of entry wbMenuN's own icon
.proc own_tile
    lda wbMenuN
    asl
    asl
    clc
    adc #T_MENU_ICON
    rts
.endproc


; each program's icon beside its title
.proc menu_icons
    jsr icons_hide
    lda #0
    sta wbMenuI
icon:
    lda wbMenuI
    cmp wbMenuN
    beq done
    tax
    lda wbaMenuTile, x
    sta wbSprTile
    txa
    asl
    asl
    tax
    ldy #0
:   lda wbaMenuPal, x
    sta wbaSprPal, y
    inx
    iny
    cpy #4
    bne :-
    jsr entry_icon
    inc wbMenuI
    bne icon
done:
    rts
.endproc

; entry wbMenuI's icon from wbSprTile and wbaSprPal, in its own 4 sprites
.proc entry_icon
    lda #MENU_ICON_X
    sta wbSprX
    lda #2
    sta wbSprW
    lda wbMenuI
    jsr entry_row
    dex ; OAM_Y_BIAS
    txa
    pha
    lda wbMenuI
    asl
    asl
    asl
    asl
    adc #MENU_OAM - OAM
    tax
    pla
    jmp icon_sprites_at
.endproc


.proc icons_hide
    ldx #MENU_OAM - OAM
    ldy #MENU_APPS * 4
    jmp sprites_hide
.endproc


; entry A: its name, in white on navy when it is under the pointer
.proc menu_entry
    sta wbMenuE
    jsr entry_name
    sta zpGs
    stx zpGs + 1
    lda wbMenuE
    jsr entry_row
    stx zbGy
    lda #0
    sta zbGx
    lda #MENU_W
    sta zbGw
    ldx #0
    lda wbMenuE
    cmp wbMenuHot
    bne :+
    inx
:   lda #MENU_TEXT_X
    jmp menu_row
.endproc


; a row of a menu box at zbGx, zbGy, zbGw wide: string zpGs A pixels in, white on navy when X is not 0; the navy
; stops a span short of the right, whose dark gray edge would turn navy
.proc menu_row
    sta wbRowT
    lda zbGx
    sta wbRowX
    lda zbGy
    sta wbRowY
    lda zbGw
    sta wbRowW
    sec
    sbc #8
    sta zbGw
    lda #MENU_ENTRY_H
    sta zbGh
    lda #C_GRAY
    sta wbRowC
    lda #PAL_PANEL
    cpx #0
    beq :+
    lda #C_ACCENT
    sta wbRowC
    lda #PAL_TITLE
:   jsr gfx_pal
    lda wbRowX
    clc
    adc #MENU_EDGE - 1
    sta zbGx
    lda wbRowW
    sec
    sbc #8 + MENU_EDGE - 1
    sta zbGw
    lda wbRowC
    jsr gfx_rect
    ldx #C_BLACK
    lda wbRowC
    cmp #C_ACCENT
    bne :+
    ldx #C_WHITE
:   stx zbGc
    lda #$ff
    sta zbGb
    lda wbRowX
    clc
    adc wbRowT
    sta zbGx
    lda wbRowY
    clc
    adc #(MENU_ENTRY_H - FONT_H) / 2 + 1
    sta zbGy
    jmp gfx_puts
.endproc


; > X = pixel row of entry A
.proc entry_row
    pha
    lda #MENU_EDGE
    clc
    adc wbMenuTop
    sta wbMenuT
    pla
    asl
    asl
    asl
    asl
    adc wbMenuT ; C clear: at most MENU_APPS * 16
    tax
    rts
.endproc


; > A (low), X (high) = entry A's title
.proc entry_name
    jsr name_off
    clc
    adc #<wbaMenuName
    pha
    lda #>wbaMenuName
    adc #0
    tax
    pla
    rts
.endproc


; zpMenu at entry A's file name
.proc file_ptr
    .assert MENU_FILE = 128, error, "file_ptr multiplies by 128"
    lsr
    tax
    lda #0
    ror
    clc
    adc #<wbaMenuFile
    sta zpMenu
    txa
    adc #>wbaMenuFile
    sta zpMenu + 1
    rts
.endproc


; wbaDxPath = nespc/menu/ and entry A's file name, through dx_path
.proc menu_path
    jsr file_ptr
    lda #<rsMenuDir
    sta zpDxDir
    lda #>rsMenuDir
    sta zpDxDir + 1
    lda zpMenu
    ldx zpMenu + 1
    ldy #MENU_DIR_LEN
    jmp dx_join
.endproc


.assert MENU_NAME = 12, error, "name_off multiplies by 12"
; > A = A * MENU_NAME
.proc name_off
    asl
    asl
    sta wbMenuT
    asl
    adc wbMenuT
    rts
.endproc


; the Start button, pressed when C is set
.proc start_paint
    lda #0
    rol
    sta wbStartDown
    lda #START_X + 1
    sta zbGx
    lda #TASK_BTN_Y
    sta zbGy
    lda #START_W - 2
    sta zbGw
    lda #TASK_BTN_H
    sta zbGh
    lda wbStartDown
    ora #BEVEL_RAISED ; BEVEL_SUNKEN when pressed
    jsr gfx_bevel
    lda #START_X + 4
    clc
    adc wbStartDown
    sta zbGx
    lda #TASK_TEXT_Y
    clc
    adc wbStartDown
    sta zbGy
    lda #<rsStart
    sta zpGs
    lda #>rsStart
    sta zpGs + 1
    lda #rsStartEnd - rsStart
    sta zbGn
    lda #C_BLACK
    sta zbGc
    lda #$ff
    sta zbGb
    jmp gfx_text
.endproc
.assert BEVEL_RAISED = 0 && BEVEL_SUNKEN = 1, error, "start_paint picks the bevel by adding"
