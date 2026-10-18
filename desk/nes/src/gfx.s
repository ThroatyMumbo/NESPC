; Drawing on the bitmap through the blitter (rtl/blit.sv), in screen pixels; the pictures are in bank 0.
; Arguments in zbGx-zbGn, which programs see as K_X and on (apps/include/desk.inc).

.include "desk.inc"

FONT_FIRST = ' '
FONT_LAST  = $7F

.segment "GFXZP": zeropage

zbGx: .res 1 ; rect: left, top, width, height (0 = 256)
zbGy: .res 1
zbGw: .res 1
zbGh: .res 1
zbGc: .res 1 ; color, palette or style; text's color
zbGb: .res 1 ; text's background, or the color a picture leaves out; $ff for none
zpGs: .res 2 ; text or picture
zbGn: .res 1 ; characters of text
zbGi: .res 1
zpGf: .res 2
zbGt: .res 1

.segment "BSS"

wbaBevel: .res 4 ; gfx_bevel's rect
wbaPatRect: .res 4 ; gfx_pattern's
wbaWinRect: .res 4 ; gfx_window's
wbBandH:    .res 1
wbPatDone: .res 1

.segment "LOWDATA"

rbaTool:    .incbin "tool.bin"
rbaFolder:  .incbin "desk.bin" ; Files on the desktop, a program, the bin empty and full, in the desk's palette
rbaExe32 = rbaFolder + ICON_SIZE * ICON_SIZE / 4
rbaBin32 = rbaExe32 + ICON_SIZE * ICON_SIZE / 4
rbaBinFull32 = rbaBin32 + ICON_SIZE * ICON_SIZE / 4
.assert * = rbaBinFull32 + ICON_SIZE * ICON_SIZE / 4, error, "desk.bin's pictures"
rbaCaption: .incbin "caption.bin"
rbaSb:      .incbin "sb.bin"

.segment "RODATA"

rbaFont:    .incbin "font.bin" ; tools/mkchr.py; fixed, so text can come from any bank

; per style: the face color ($ff none), then lines as sides (1 top, 2 left, 4 bottom, 8 right), inset, color; $ff
rbaBevels:
.word bevel_raised, bevel_sunken, bevel_field, bevel_window
bevel_raised: .byte C_GRAY, 3, 0, C_WHITE, 12, 0, C_BLACK, 12, 1, C_ACCENT, $ff
bevel_sunken: .byte C_GRAY, 3, 0, C_BLACK, 3, 1, C_ACCENT, 12, 0, C_WHITE, $ff
bevel_field:  .byte $ff, 3, 0, C_ACCENT, 12, 0, C_WHITE, $ff
bevel_window: .byte C_GRAY, 3, 1, C_WHITE, 12, 0, C_BLACK, 12, 1, C_ACCENT, $ff

.segment "CODE"

.proc gfx_wait
:   bit GFX_OP
    bmi :-
    rts
.endproc


.proc set_rect
    lda zbGx
    sta GFX_DX
    lda zbGy
    sta GFX_DY
    lda zbGw
    sta GFX_W
    lda zbGh
    sta GFX_H
    rts
.endproc


; GFX_FLAGS = A
; keeps: X, Y
.proc set_flags
    sta GFX_FLAGS
    rts
.endproc


; the rect in color A
.proc gfx_rect
    sta GFX_FG
    jsr set_rect
    lda #0
    jsr set_flags
    lda #OP_FILL
    ; [fall_through]
.endproc

.proc start
    jsr gfx_wait
    sta GFX_OP
    rts
.endproc


; palette A for the rect's 8x1 spans
.proc gfx_pal
    sta GFX_FG
    jsr set_rect
    lda #0
    jsr set_flags
    lda #OP_PAL
    jmp start
.endproc


; the rect from A (x), X (y)
.proc gfx_copy
    sta GFX_SX
    stx GFX_SY
    jsr set_rect
    lda #0
    jsr set_flags
    lda #OP_COPY
    jmp start
.endproc


; drawing kept to the rect
.proc gfx_clip
    lda zbGx
    sta GFX_CX0
    clc
    adc zbGw
    sta GFX_CX1
    lda zbGy
    sta GFX_CY0
    clc
    adc zbGh
    sta GFX_CY1
    rts
.endproc


.proc gfx_noclip
    lda #0
    sta GFX_CX0
    sta GFX_CY0
    sta GFX_CX1
    lda #240
    sta GFX_CY1
    rts
.endproc


; the rect's edge in style A (BEVEL_*), its face filled first when the style has one; keeps the rect
.proc gfx_bevel
    asl
    tax
    lda rbaBevels, x
    sta zpGf
    lda rbaBevels + 1, x
    sta zpGf + 1
    ldx #3
:   lda zbGx, x
    sta wbaBevel, x
    dex
    bpl :-
    ldy #0
    lda (zpGf), y
    bmi line
    jsr gfx_rect
line:
    iny
    lda (zpGf), y
    bmi done
    sta zbGt
    iny
    lda (zpGf), y
    sta zbGi ; inset
    iny
    lda (zpGf), y
    sta zbGc
    sty zbGn
    lda #1
    bit zbGt
    beq :+
    jsr side_top
:   lda #2
    bit zbGt
    beq :+
    jsr side_left
:   lda #4
    bit zbGt
    beq :+
    jsr side_bottom
:   lda #8
    bit zbGt
    beq :+
    jsr side_right
:   ldy zbGn
    jmp line
done:
    ldx #3
:   lda wbaBevel, x
    sta zbGx, x
    dex
    bpl :-
    rts
.endproc


; the rect inset zbGi on every side, as zbGx-zbGh
.proc inset
    lda wbaBevel
    clc
    adc zbGi
    sta zbGx
    lda wbaBevel + 1
    clc
    adc zbGi
    sta zbGy
    lda zbGi
    asl
    sta zbGw
    lda wbaBevel + 2
    sec
    sbc zbGw
    sta zbGw
    lda zbGi
    asl
    sta zbGh
    lda wbaBevel + 3
    sec
    sbc zbGh
    sta zbGh
    rts
.endproc

.proc side_top
    jsr inset
    lda #1
    sta zbGh
    lda zbGc
    jmp gfx_rect
.endproc

.proc side_left
    jsr inset
    lda #1
    sta zbGw
    lda zbGc
    jmp gfx_rect
.endproc

.proc side_bottom
    jsr inset
    lda zbGy
    clc
    adc zbGh
    sec
    sbc #1
    sta zbGy
    lda #1
    sta zbGh
    lda zbGc
    jmp gfx_rect
.endproc

.proc side_right
    jsr inset
    lda zbGx
    clc
    adc zbGw
    sec
    sbc #1
    sta zbGx
    lda #1
    sta zbGw
    lda zbGc
    jmp gfx_rect
.endproc


; a window over the rect: its panel in BEVEL_WINDOW's edge, a navy band A rows tall inside the top edge, and those
; rows in PAL_TITLE; keeps the rect
.proc gfx_window
    sta wbBandH
    ldx #3
:   lda zbGx, x
    sta wbaWinRect, x
    dex
    bpl :-
    lda #PAL_PANEL
    jsr gfx_pal
    lda wbBandH
    clc
    adc #FRAME
    sta zbGh
    lda #PAL_TITLE
    jsr gfx_pal
    lda wbaWinRect + 3
    sta zbGh
    lda #BEVEL_WINDOW
    jsr gfx_bevel
    ; the edge's dark gray would be navy beside the title
    lda zbGx
    clc
    adc zbGw
    sec
    sbc #2
    sta zbGx
    inc zbGy
    lda #1
    sta zbGw
    lda wbBandH
    clc
    adc #FRAME - 1
    sta zbGh
    lda #C_GRAY
    jsr gfx_rect
    lda wbaWinRect
    clc
    adc #FRAME
    sta zbGx
    lda wbaWinRect + 1
    clc
    adc #FRAME
    sta zbGy
    lda wbaWinRect + 2
    sec
    sbc #FRAME * 2
    sta zbGw
    lda wbBandH
    sta zbGh
    lda #C_ACCENT
    jsr gfx_rect
    ldx #3
:   lda wbaWinRect, x
    sta zbGx, x
    dex
    bpl :-
    rts
.endproc


; > A = letters of the string at zpGs before its NUL
.proc strlen
    ldy #0
:   lda (zpGs), y
    beq :+
    iny
    bne :-
:   tya
    rts
.endproc


; the NUL-ended string at zpGs as gfx_text
.proc gfx_puts
    jsr strlen
    sta zbGn
    jmp gfx_text
.endproc


; wbaRow's first zbGn characters as text
.proc gfx_text_row
    lda #<wbaRow
    sta zpGs
    lda #>wbaRow
    sta zpGs + 1
    ; [fall_through]
.endproc

; zbGn characters at zpGs from zbGx, zbGy in color zbGc on zbGb; zbGx moves past them
.proc gfx_text
    lda zbGn
    bne :+
    rts
:   lda zbGx
    sta GFX_DX
    lda zbGy
    sta GFX_DY
    lda #FONT_W
    sta GFX_W
    lda #FONT_H
    sta GFX_H
    lda zbGc
    sta GFX_FG
    ldx #0
    lda zbGb
    bpl :+
    ldx #GF_BG_CLEAR
:   sta GFX_BG
    txa
    jsr set_flags
    lda #0
    sta zbGi
char:
    ldy zbGi
    lda (zpGs), y
    sec
    sbc #FONT_FIRST
    cmp #FONT_LAST - FONT_FIRST + 1
    bcc :+
    lda #'?' - FONT_FIRST
:   ldx #0
    stx zpGf + 1
    asl
    rol zpGf + 1
    asl
    rol zpGf + 1
    asl
    rol zpGf + 1
    adc #<rbaFont ; C clear from the last rol
    sta zpGf
    lda zpGf + 1
    adc #>rbaFont
    sta zpGf + 1
    jsr gfx_wait
    lda #OP_EXPAND
    sta GFX_OP
    ldy #0
    .repeat ::FONT_H
        lda (zpGf), y
        sta GFX_DATA
        iny
    .endrepeat
    inc zbGi
    lda zbGi
    cmp zbGn
    bne char
    lda zbGn
    asl
    asl
    asl
    clc
    adc zbGx
    sta zbGx
    rts
.endproc


; the picture at zpGs in the bank mapped now: zbGw x zbGh at zbGx, zbGy, color zbGb left out unless $ff
.proc gfx_image
    jsr set_rect
    ldx #0
    lda zbGb
    bmi :+
    sta GFX_KEY
    ldx #GF_KEY
:   txa
    jsr set_flags
    lda #OP_IMAGE
    jsr start
    lda zbGw
    clc
    adc #7
    lsr
    lsr
    lsr
    asl
    sta zbGt ; bytes a row
    ldx zbGh
row:
    ldy #0
:   lda (zpGs), y
    sta GFX_DATA
    iny
    cpy zbGt
    bne :-
    tya
    clc
    adc zpGs
    sta zpGs
    bcc :+
    inc zpGs + 1
:   dex
    bne row
    rts
.endproc


; as gfx_image, the picture in bank 0
.proc gfx_image_ui
    lda #0
    sta DESK_BANK
    jsr gfx_image
    lda zbBank
    sta DESK_BANK
    rts
.endproc


; toolbar picture A (T_BACK and on) at zbGx, zbGy
.proc gfx_tool
    ldx #0
    stx zpGs + 1
    .repeat 6 ; TOOL_IMG
        asl
        rol zpGs + 1
    .endrepeat
    adc #<rbaTool
    sta zpGs
    lda zpGs + 1
    adc #>rbaTool
    sta zpGs + 1
    lda #16
    sta zbGw
    sta zbGh
    ; [fall_through]
.endproc

.proc ui_image
    lda #$ff
    sta zbGb
    jmp gfx_image_ui
.endproc
.assert TOOL_IMG = 64, error, "gfx_tool multiplies by 64"


; the desktop's Files folder, ICON_SIZE square, at zbGx, zbGy
.proc gfx_folder
    lda #<rbaFolder
    ldx #>rbaFolder
    ; [fall_through]
.endproc

; desktop picture A (low), X (high) in bank 0, ICON_SIZE square, at zbGx, zbGy; its see-through desk color left out
.proc desk_image
    sta zpGs
    stx zpGs + 1
    lda #ICON_SIZE
    sta zbGw
    sta zbGh
    lda #C_DESK
    sta zbGb
    jmp gfx_image_ui
.endproc


; a desktop shortcut to a program without a picture of its own, as gfx_folder
.proc gfx_exe
    lda #<rbaExe32
    ldx #>rbaExe32
    jmp desk_image
.endproc


; the recycle bin, full with A not 0, as gfx_folder
.proc gfx_bin
    tax
    bne full
    lda #<rbaBin32
    ldx #>rbaBin32
    jmp desk_image
full:
    lda #<rbaBinFull32
    ldx #>rbaBinFull32
    jmp desk_image
.endproc


; scroll bar picture A (T_SB_*) at zbGx, zbGy
.proc gfx_sb
    asl
    asl
    asl
    asl
    clc
    adc #<rbaSb
    sta zpGs
    lda #>rbaSb
    adc #0
    sta zpGs + 1
    lda #8
    sta zbGw
    sta zbGh
    jmp ui_image
.endproc
.assert SB_IMG = 16, error, "gfx_sb multiplies by 16"


; caption button A (CAPTION_*) at zbGx, zbGy
.proc gfx_caption
    tax
    lda #<rbaCaption
    sta zpGs
    lda #>rbaCaption
    sta zpGs + 1
    cpx #0
    beq put
:   lda zpGs
    clc
    adc #CAP_IMG
    sta zpGs
    bcc :+
    inc zpGs + 1
:   dex
    bne :--
put:
    lda #16
    sta zbGw
    lda #14
    sta zbGh
    jmp ui_image
.endproc


; the rect in white and gray alternating, Windows' pressed look
.proc gfx_checker
    jsr set_rect
    lda #C_WHITE
    sta GFX_FG
    lda #C_GRAY
    sta GFX_BG
    lda #0
    jsr set_flags
    lda #OP_EXPAND
    jsr start
    lda zbGw
    clc
    adc #7
    lsr
    lsr
    lsr
    sta zbGt
    lda zbGy
    sta zbGi
    ldx zbGh
row:
    lda zbGi
    eor zbGx
    lsr
    lda #$aa
    bcc :+
    lda #$55
:   ldy zbGt
:   sta GFX_DATA
    dey
    bne :-
    inc zbGi
    dex
    bne row
    rts
.endproc


; the rect, 1 to 240 rows, tiled with the 8 rows at zpGs anchored to the screen: 1 bits zbGc, 0 bits zbGb; its first
; 8 rows streamed, the rest copied down from them. Keeps the rect; the clip is off after
.proc gfx_pattern
    ldx #3
:   lda zbGx, x
    sta wbaPatRect, x
    dex
    bpl :-
    jsr gfx_clip
    lda zbGx
    and #7
    clc
    adc zbGw
    sec
    sbc #1
    lsr
    lsr
    lsr
    tax
    inx
    stx zbGt ; spans a row, from the one the rect starts in
    txa
    asl
    asl
    asl
    sta GFX_W
    lda zbGx
    and #$f8
    sta GFX_DX
    lda zbGy
    sta GFX_DY
    sta zbGi
    lda zbGh
    cmp #8
    bcc :+
    lda #8
:   sta GFX_H
    sta wbPatDone
    lda zbGc
    sta GFX_FG
    lda zbGb
    sta GFX_BG
    lda #0
    jsr set_flags
    lda #OP_EXPAND
    jsr start
    ldx wbPatDone
row:
    lda zbGi
    and #7
    tay
    lda (zpGs), y
    ldy zbGt
:   sta GFX_DATA
    dey
    bne :-
    inc zbGi
    dex
    bne row
copy:
    lda wbPatDone
    cmp wbaPatRect + 3
    bcs done
    lda wbaPatRect + 3
    sec
    sbc wbPatDone
    cmp wbPatDone
    bcc :+
    lda wbPatDone
:   sta zbGh
    lda wbaPatRect + 1
    clc
    adc wbPatDone
    sta zbGy
    lda wbaPatRect
    ldx wbaPatRect + 1
    jsr gfx_copy
    asl wbPatDone
    bcc copy
done:
    lda wbaPatRect + 1
    sta zbGy
    lda wbaPatRect + 3
    sta zbGh
    jmp gfx_noclip
.endproc
