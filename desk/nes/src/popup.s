; Right-click menus: a box at the pointer listing up to POP_MAX items, the one under the pointer in white on navy.

.include "desk.inc"

.segment "SHELL_BSS"

wbPopN:   .res 1 ; items, their names in wbaPopL/H; the caller fills all three
wbaPopL:  .res POP_MAX
wbaPopH:  .res POP_MAX
wbPopX:   .res 1 ; the box's top-left
wbPopY:   .res 1
wbPopHot: .res 1 ; item under the pointer, $ff for none
wbPopI:   .res 1

.assert POP_W .mod 8 = 0, error, "a right-click menu's palettes go by span"

.segment "SHELL"

; the string A/X (low/high) as item Y of the next box; > Y = the item after it
.proc pop_add
    sta wbaPopL, y
    txa
    sta wbaPopH, y
    iny
    rts
.endproc


; the box with its top-left at the pointer, kept on the desk
.proc popup_open
    jsr pointer_busy
    jsr pointer_px
    lda zbPx
    and #$f8
    cmp #256 - POP_W + 1
    bcc :+
    lda #256 - POP_W
:   sta wbPopX
    lda wbPopN
    asl
    asl
    asl
    asl
    adc #MENU_EDGE * 2 ; C clear: at most POP_MAX * 16
    sta wbPopI
    lda #SCREEN_H
    sec
    sbc wbPopI
    cmp zbPy
    bcc :+
    lda zbPy
:   sta wbPopY
    lda #$ff
    sta wbPopHot
    jsr gfx_noclip
    lda wbPopX
    sta zbGx
    lda wbPopY
    sta zbGy
    lda #POP_W
    sta zbGw
    lda wbPopI
    sta zbGh
    lda #PAL_PANEL
    jsr gfx_pal
    lda #BEVEL_WINDOW
    jsr gfx_bevel
    lda #0
    sta wbPopI
item:
    lda wbPopI
    jsr pop_item
    inc wbPopI
    lda wbPopI
    cmp wbPopN
    bcc item
    jmp pointer_idle
.endproc


; > A = POP_NONE while the box stays open, the item picked with A, or POP_SHUT for B or A off the items
.proc popup_update
    jsr pop_hot
    cmp wbPopHot
    beq pad
    ldx wbPopHot
    sta wbPopHot
    txa
    bmi :+
    jsr pop_item
:   lda wbPopHot
    bmi :+
    jsr pop_item
:   jsr vq_flush
pad:
    lda zbPadNew
    bmi pick
    and #JOYPAD_B
    bne shut
    lda #POP_NONE
    rts
pick:
    lda wbPopHot
    bpl done
shut:
    lda #POP_SHUT
done:
    rts
.endproc


; > A = item under the pointer, $ff for none
.proc pop_hot
    jsr pointer_px
    lda zbPx
    sec
    sbc wbPopX
    bcc none
    cmp #POP_W
    bcs none
    lda zbPy
    sec
    sbc wbPopY
    bcc none
    sbc #MENU_EDGE
    bcc none
    lsr
    lsr
    lsr
    lsr
    cmp wbPopN
    bcc done
none:
    lda #$ff
done:
    rts
.endproc


; item A's row
.proc pop_item
    tax
    lda wbaPopL, x
    sta zpGs
    lda wbaPopH, x
    sta zpGs + 1
    txa
    asl
    asl
    asl
    asl
    adc wbPopY ; C clear: at most (POP_MAX - 1) * 16, and the box ends above the taskbar
    adc #MENU_EDGE
    sta zbGy
    lda wbPopX
    sta zbGx
    lda #POP_W
    sta zbGw
    ldy #0
    cpx wbPopHot
    bne :+
    iny
:   tya
    tax
    lda #POP_TEXT_X
    jmp menu_row
.endproc
