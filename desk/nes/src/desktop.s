; The desktop's icons while the window is hidden, down two columns: Files, nespc/desktop's shortcuts (.lnk) and
; programs (.dx) with their pictures; the Trash alone at the top right.

.include "desk.inc"
.include "fs.inc"
.include "edio.inc"
.include "launch.inc"
.include "paths.inc"

DESK_FILE = 64 ; a listed file's name and its NUL; longer names aren't listed
DESK_LABEL = DESK_LABEL_MAX + 1
KIND_OWN = 0 ; its own picture, in wbaDeskPic
KIND_FOLDER = 1
KIND_EXE = 2
BIN_SLOT = DESK_ROWS * 2 ; slot_xy's for the bin, past the columns
.assert DESK_ROWS = 4 && ICON_PITCH = 48, error, "slot_xy places slots by shifting"
.assert DESK_APPS + 1 <= DESK_ROWS * 2, error, "Files and nespc/desktop's fill more than two columns"
.assert ICON_Y + (DESK_ROWS - 1) * ICON_PITCH + ICON_SIZE + LABEL_GAP + FONT_H <= SCREEN_H, error, "a column runs past the desk"

.segment "ZEROPAGE"

zpDesk: .res 2
zpPic:  .res 2
zpPal:  .res 2

.segment "BSS"

wbBinFull:   .res 1 ; something is in nespc/trash; browser.s reads it too

.segment "SHELL3_BSS"

wbHitSlot:   .res 1 ; desk_hit's
wbDeskN:    .res 1 ; nespc/desktop's entries shown, slots 1 on; the CD's slot after them
wbDeskSlots: .res 1
wbDeskI:     .res 1
wbDeskT:     .res 1
wbDeskX:     .res 1 ; slot_xy's
wbDeskY:     .res 1
wbLabelX:    .res 1 ; desk_label's
wbLabelEnd:  .res 1
wbPicRow:    .res 1 ; draw_picture's
wbPicSel:    .res 1
wbPicBits:   .res 1
wbPicRun:    .res 1
wbPicPal:    .res 1
wbaDeskFile:  .res DESK_APPS * DESK_FILE
wbaDeskLabel: .res DESK_APPS * DESK_LABEL
wbaDeskKind:  .res DESK_APPS
wbaDeskPic:   .res DESK_APPS * PICTURE_LEN

.segment "SHELL3"

rsDeskDir: .byte NESPC_DESKTOP
DESK_DIR_LEN = * - rsDeskDir
rsFiles:   .byte "Files"
rsFilesEnd:
rsBinLabel: .byte "Trash"
BIN_LABEL_LEN = * - rsBinLabel
BIN_LABEL_X = BIN_X + ICON_SIZE / 2 - BIN_LABEL_LEN * FONT_W / 2
.assert BIN_LABEL_X >= ICON_X2 + ICON_SIZE / 2 + DESK_LABEL_MAX * FONT_W / 2, error, "the bin's label meets column 2's"
.assert BIN_LABEL_X + BIN_LABEL_LEN * FONT_W <= 256, error, "the bin's label runs off the screen"
rsBinDir:  .byte NESPC_TRASH
BIN_DIR_LEN = * - rsBinDir
rbaPicLo:
.repeat DESK_APPS, i
    .byte <(wbaDeskPic + i * PICTURE_LEN)
.endrepeat
rbaPicHi:
.repeat DESK_APPS, i
    .byte >(wbaDeskPic + i * PICTURE_LEN)
.endrepeat


; wbBinFull, then the first DESK_APPS shortcuts and programs in nespc/desktop, in the card's order: their labels and
; pictures
.proc desk_scan
    lda #<rsBinDir
    ldx #>rsBinDir
    ldy #BIN_DIR_LEN
    jsr ed_dir_load
    ldx #0
    tay
    bne :+ ; no bin yet
    lda zwEdArg
    ora zwEdArg + 1
    tax
:   stx wbBinFull
    lda #<wbaDeskFile
    sta zpScanTo
    lda #>wbaDeskFile
    sta zpScanTo + 1
    lda #<scan_dx_lnk
    sta wpScanHook
    lda #>scan_dx_lnk
    sta wpScanHook + 1
    lda #DESK_FILE
    sta wbScanMax
    sta wbScanSlot
    lda #DESK_APPS
    sta wbScanCap
    lda #<rsDeskDir
    ldx #>rsDeskDir
    ldy #DESK_DIR_LEN - 1
    jsr dir_scan
    sta wbDeskN
    lda #0
    sta wbDeskI
info:
    lda wbDeskI
    cmp wbDeskN
    beq done
    jsr desk_entry
    inc wbDeskI
    bne info
done:
    rts
.endproc


; entry wbDeskI's label and picture: a program's title and its own, a shortcut's name less ".lnk" and its target's,
; a folder's or a plain program's when it has none
.proc desk_entry
    ldx wbDeskI
    lda #KIND_EXE
    sta wbaDeskKind, x
    lda wbDeskI
    jsr entry_path
    lda #<wbaDxPath
    ldx #>wbaDxPath
    ldy wbDxPathLen
    jsr is_lnk
    bcs link
    jsr dx_open
    php
    jsr title_dx
    plp
    bne done
    jsr dx_picture
    bcc copy
done:
    rts
link:
    jsr title_link
    lda #<wbaDxPath
    ldx #>wbaDxPath
    ldy wbDxPathLen
    far link_read
    bne done
    far link_mcu
    jsr is_dx
    bcc rom
    far link_mcu
    jsr dx_path
    jsr dx_open
    bne done
    jsr dx_picture
    bcc copy
    rts
rom:
    far link_rom
    bcc other
    jsr sd_release
    far link_mcu
    far rom_rsrc
    bne done
    jsr rsrc_picture
    bcc copy
    rts
other:
    lda #<wbaBlkData
    sta zpEdBuf
    lda #>wbaBlkData
    sta zpEdBuf + 1
    far link_mcu
    jsr ed_finfo
    bne done
    lda wbaEdInfo + FI_ATTR
    and #AT_DIR
    beq done
    ldx wbDeskI
    lda #KIND_FOLDER
    sta wbaDeskKind, x
    rts
copy:
    sta zpPal
    stx zpPal + 1
    ldx wbDeskI
    lda rbaPicLo, x
    sta zpPic
    lda rbaPicHi, x
    sta zpPic + 1
    ldy #0
:   lda (zpPal), y
    sta (zpPic), y
    iny
    bne :-
    inc zpPal + 1
    inc zpPic + 1
:   lda (zpPal), y
    sta (zpPic), y
    iny
    cpy #<PICTURE_LEN
    bne :-
    .assert >PICTURE_LEN = 1, error, "desk_entry copies a picture as a page and the rest"
    lda #KIND_OWN
    sta wbaDeskKind, x
    rts
.endproc


; entry wbDeskI's label: the program's title
.proc title_dx
    lda wbDeskI
    jsr label_ptr
    ldy #0
:   lda wbaDxTitle, y
    beq end
    sta (zpDesk), y
    iny
    cpy #DESK_LABEL_MAX
    bne :-
end:
    lda #0
    sta (zpDesk), y
    rts
.endproc


; entry wbDeskI's label: its file name less ".lnk"
.proc title_link
    lda wbDeskI
    jsr desk_file
    lda zpDesk
    ldx zpDesk + 1
    jsr lnk_title
    jmp title_dx
.endproc


; zpDesk at entry A's label
.proc label_ptr
    .assert DESK_LABEL = 12, error, "label_ptr multiplies by 12"
    asl
    asl
    sta zpDesk
    asl
    adc zpDesk ; C clear: at most DESK_APPS * 12
    adc #<wbaDeskLabel
    sta zpDesk
    lda #>wbaDeskLabel
    adc #0
    sta zpDesk + 1
    rts
.endproc


; zpDesk at entry A's file name
.proc desk_file
    .assert DESK_FILE = 64, error, "desk_file multiplies by 64"
    sta wbDeskT
    lda #0
    lsr wbDeskT
    ror
    lsr wbDeskT
    ror
    clc
    adc #<wbaDeskFile
    sta zpDesk
    lda wbDeskT
    adc #>wbaDeskFile
    sta zpDesk + 1
    rts
.endproc


; wbaDxPath = nespc/desktop/ and the file name of desk_hit's slot A, through dx_path
.proc desk_path
    sec
    sbc #1
    ; [fall_through]
.endproc

; as desk_path, for entry A
.proc entry_path
    jsr desk_file
    lda #<rsDeskDir
    sta zpDxDir
    lda #>rsDeskDir
    sta zpDxDir + 1
    lda zpDesk
    ldx zpDesk + 1
    ldy #DESK_DIR_LEN
    jmp dx_join
.endproc


; wbDeskSlots = Files and the entries
.proc slot_count
    ldx wbDeskN
    inx
    txa
    sta wbDeskSlots
    rts
.endproc


; wbDeskX, wbDeskY = slot A's top left, BIN_SLOT the bin's
.proc slot_xy
    cmp #BIN_SLOT
    bne :+
    lda #BIN_X
    sta wbDeskX
    lda #BIN_Y
    sta wbDeskY
    rts
:   tax
    and #DESK_ROWS - 1
    asl
    asl
    asl
    asl
    sta wbDeskY
    asl
    adc wbDeskY ; C clear: at most 96
    adc #ICON_Y
    sta wbDeskY
    lda #ICON_X
    cpx #DESK_ROWS
    bcc :+
    lda #ICON_X2
:   sta wbDeskX
    rts
.endproc


; every icon and its label, white on the desk, centered under it, the bin's last
.proc desk_draw
    jsr slot_count
    lda #0
    sta wbDeskI
slot:
    lda wbDeskI
    jsr slot_xy
    lda wbDeskX
    sta zbGx
    lda wbDeskY
    sta zbGy
    lda wbDeskI
    beq folder
    cmp #BIN_SLOT
    beq bin
    sec
    sbc #1
    tax
    lda wbaDeskKind, x
    beq own
    cmp #KIND_FOLDER
    beq folder
    jsr gfx_exe
    jmp label
own:
    txa
    jsr draw_picture
    jmp label
folder:
    jsr gfx_folder
    jmp label
bin:
    lda wbBinFull
    jsr gfx_bin
label:
    lda wbDeskI
    jsr desk_label
    lda wbLabelX
    sta zbGx
    lda #C_WHITE
    sta zbGc
    lda #C_DESK
    sta zbGb
    jsr gfx_text
    lda wbDeskI
    cmp #BIN_SLOT
    beq done
    inc wbDeskI
    lda wbDeskI
    cmp wbDeskSlots
    bne slot
    lda #BIN_SLOT
    sta wbDeskI
    bne slot
done:
    rts
.endproc


; entry A's own picture at zbGx, zbGy, then its spans' palettes: a rect for each run of rows alike, and in it for
; each run of spans alike that isn't the desk's
.proc draw_picture
    tax
    lda rbaPicLo, x
    sta zpGs
    sta zpPal
    lda rbaPicHi, x
    sta zpGs + 1
    sta zpPal + 1
    inc zpPal + 1
    .assert PICTURE_LEN - ICON_SIZE = 256, error, "draw_picture finds the palettes a page on"
    lda #ICON_SIZE
    sta zbGw
    sta zbGh
    lda #C_DESK
    sta zbGb
    jsr gfx_image
    lda #0
    sta wbPicRow
rows:
    ldy wbPicRow
    lda (zpPal), y
    sta wbPicSel
:   iny
    cpy #ICON_SIZE
    beq :+
    lda (zpPal), y
    cmp wbPicSel
    beq :-
:   tya
    sec
    sbc wbPicRow
    sta zbGh
    lda wbDeskY
    clc
    adc wbPicRow
    sta zbGy
    sty wbPicRow
    lda wbPicSel
    sta wbPicBits
    ldx #0
span:
    stx wbPicRun
    lda wbPicBits
    and #3
    sta wbPicPal
more:
    inx
    lsr wbPicBits
    lsr wbPicBits
    cpx #4
    beq put
    lda wbPicBits
    and #3
    cmp wbPicPal
    beq more
put:
    lda wbPicPal
    .assert PAL_DESK = 0, error, "draw_picture leaves the desk's spans as they are"
    beq skip
    stx wbDeskT
    txa
    sec
    sbc wbPicRun
    asl
    asl
    asl
    sta zbGw
    lda wbPicRun
    asl
    asl
    asl
    adc wbDeskX ; C clear: at most 24
    sta zbGx
    lda wbPicPal
    jsr gfx_pal
    lda wbPicPal
    cmp #PAL_ICON ; the desk's color at 1, as PAL_DESK has it
    beq :+
    jsr opaque
:   ldx wbDeskT
skip:
    cpx #4
    bne span
    lda wbPicRow
    cmp #ICON_SIZE
    beq :+
    jmp rows
:   rts
.endproc


; the picture again inside the rect zbGx-zbGh, opaque: color 1 there is gray, not see-through; keeps zbGy, zbGh
.proc opaque
    jsr gfx_clip
    lda zbGy
    pha
    lda zbGh
    pha
    lda wbDeskX
    sta zbGx
    lda wbDeskY
    sta zbGy
    lda #ICON_SIZE
    sta zbGw
    sta zbGh
    lda #$ff
    sta zbGb
    lda zpPal
    sta zpGs
    ldx zpPal + 1
    dex
    stx zpGs + 1
    jsr gfx_image
    jsr gfx_noclip
    pla
    sta zbGh
    pla
    sta zbGy
    rts
.endproc


; slot A's label: zpGs and zbGn its text, zbGy its row, wbLabelX to wbLabelEnd its pixels; past the column's left
; edge when too long to center
.proc desk_label
    pha
    jsr slot_xy
    pla
    beq files
    cmp #BIN_SLOT
    beq bin
    sec
    sbc #1
    jsr label_ptr
    lda zpDesk
    sta zpGs
    lda zpDesk + 1
    sta zpGs + 1
    jsr strlen
    jmp len
files:
    lda #<rsFiles
    sta zpGs
    lda #>rsFiles
    sta zpGs + 1
    lda #rsFilesEnd - rsFiles
    bne len
bin:
    lda #<rsBinLabel
    sta zpGs
    lda #>rsBinLabel
    sta zpGs + 1
    lda #BIN_LABEL_LEN
len:
    sta zbGn
    asl
    asl
    sta wbDeskT ; half its width
    lda wbDeskX
    clc
    adc #ICON_SIZE / 2
    sec
    sbc wbDeskT
    bcs :+
    lda wbDeskX
    sbc #ICON_X - 1 ; C clear
:   sta wbLabelX
    lda zbGn
    asl
    asl
    asl
    clc
    adc wbLabelX
    sta wbLabelEnd
    lda wbDeskY
    clc
    adc #ICON_SIZE + LABEL_GAP
    sta zbGy
    rts
.endproc


; > A = what is under the pointer: 0 Files, slot 1 on nespc/desktop's (desk_path), DESK_BIN, $ff for nothing
.proc desk_hit
    jsr pointer_px
    jsr slot_count
    lda #BIN_SLOT
    jsr slot_hit
    bcc :+
    lda #DESK_BIN
    rts
:   ldx wbDeskSlots
    dex
slot:
    stx wbHitSlot
    txa
    jsr slot_hit
    bcs found
    ldx wbHitSlot
    dex
    bpl slot
    lda #$ff
    rts
found:
    lda wbHitSlot
    rts
.endproc


; > C set when the pointer is on slot A's picture or its label
.proc slot_hit
    pha
    jsr slot_xy
    lda zbPy
    sec
    sbc wbDeskY
    bcc no
    cmp #ICON_SIZE
    bcc picture
    sbc #ICON_SIZE + LABEL_GAP
    cmp #FONT_H
    bcs no
    pla
    jsr desk_label
    lda zbPx
    cmp wbLabelX
    bcc out
    cmp wbLabelEnd
    bcs out
    sec
    rts
picture:
    pla
    lda zbPx
    sec
    sbc wbDeskX
    cmp #ICON_SIZE
    bcs out
    sec
    rts
no:
    pla
out:
    clc
    rts
.endproc
