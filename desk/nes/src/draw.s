; The desktop, the taskbar and the window's frame on the bitmap, and the window's geometry.

.include "desk.inc"

.segment "ZEROPAGE"

zbWinX:  .res 1 ; span column
zbWinY:  .res 1 ; pixel row
zbWinW:  .res 1 ; spans
zbWinH:  .res 1 ; pixels
zbBodyX: .res 1 ; span column of the body's first character
zbBodyY: .res 1 ; pixel row of its first
zbBodyW: .res 1 ; characters a row
zbBodyH: .res 1 ; rows
zbZoom:  .res 1 ; window fills the screen
zbFitW:  .res 1 ; body the program asked for (K_SIZE), 0 for the file window's
zbFitH:  .res 1
zbIcon:  .res 1 ; window hidden, its icon on the desk

.segment "WRAM"

wbNoIcon: .res 1 ; the title needs the icon's room (title_text)

.segment "BSS"

wbAppIcon: .res 1 ; a program's sprite icon stands in the title bar for the folder's

.segment "RODATA"

rbaGeom: ; x, y, w (spans), h (pixels): normal, zoomed; rows of 8 between a framed window's FRAMED_H
.byte 2, (SCREEN_H - FRAMED_H - 16 * 8) / 2, 28, FRAMED_H + 16 * 8
.byte 0, (SCREEN_H - FRAMED_H - 19 * 8) / 2, 32, FRAMED_H + 19 * 8

.segment "CODE"

; window and body bounds for zbZoom, else the program's zbFitW x zbFitH
.proc set_geometry
    ldx #4
    lda zbZoom
    bne table
    lda zbFitW
    bne fit
    tax
table:
    lda rbaGeom, x
    sta zbWinX
    lda rbaGeom + 1, x
    sta zbWinY
    lda rbaGeom + 2, x
    sta zbWinW
    lda rbaGeom + 3, x
    sta zbWinH
    jmp body
fit:
    clc
    adc #2
    cmp #FIT_MIN_W
    bcs :+
    lda #FIT_MIN_W
:   cmp #33
    bcc :+
    lda #32
:   sta zbWinW
    eor #$ff
    sec
    adc #32
    lsr
    sta zbWinX
    lda zbFitH
    cmp #(SCREEN_H - PLAIN_H) / 8 + 1
    bcc :+
    lda #(SCREEN_H - PLAIN_H) / 8
:   asl
    asl
    asl
    adc #PLAIN_H ; C clear
    sta zbWinH
    eor #$ff
    sec
    adc #SCREEN_H
    lsr
    sta zbWinY
body:
    lda zbWinX
    clc
    adc #1
    sta zbBodyX
    lda zbFitW
    beq framed
    lda zbWinW
    sec
    sbc #2
    sta zbBodyW
    lda zbWinY
    clc
    adc #PLAIN_TOP
    sta zbBodyY
    lda zbWinH
    sec
    sbc #PLAIN_H
    jmp rows
framed:
    lda zbWinW
    sec
    sbc #3 ; the scroll bar takes most of a span
    sta zbBodyW
    lda zbWinY
    clc
    adc #BODY_TOP
    sta zbBodyY
    lda zbWinH
    sec
    sbc #FRAMED_H
rows:
    lsr
    lsr
    lsr
    sta zbBodyH
    rts
.endproc


; > A = the window's left edge in pixels
.proc win_x0
    lda zbWinX
    asl
    asl
    asl
    rts
.endproc


; > A = the window's right edge (exclusive) in pixels, 0 for 256
.proc win_x1
    lda zbWinX
    clc
    adc zbWinW
    asl
    asl
    asl
    rts
.endproc


; zbGx, zbGy, zbGw, zbGh = the body, characters and rows as pixels
.proc body_px
    lda zbBodyX
    asl
    asl
    asl
    sta zbGx
    lda zbBodyY
    sta zbGy
    lda zbBodyW
    asl
    asl
    asl
    sta zbGw
    lda zbBodyH
    asl
    asl
    asl
    sta zbGh
    rts
.endproc


; the whole screen for zbIcon and the window, the window's contents blank
.proc redraw_screen
    jsr gfx_noclip
    lda #0
    sta zbGx
    sta zbGy
    sta zbGw
    lda #SCREEN_H
    sta zbGh
    jsr backdrop_fill
    lda zbIcon
    beq window
    far desk_draw
    jmp taskbar
window:
    jsr draw_window
taskbar:
    jsr draw_taskbar
    ldx #WIN_OAM - OAM ; the title bar's icon, which win_icon_sync puts back while the window shows
    ldy #4
    jmp sprites_hide
.endproc


.proc draw_window
    jsr win_x0
    sta zbGx
    lda zbWinY
    sta zbGy
    lda zbWinW
    asl
    asl
    asl
    sta zbGw
    lda zbWinH
    sta zbGh
    lda #BAND_H
    jsr gfx_window
    ; the band's buttons
    lda zbWinY
    clc
    adc #CAP_Y
    sta zbGy
    jsr win_x1
    sec
    sbc #CAP_MIN
    sta zbGx
    lda #CAPTION_MIN
    jsr gfx_caption
    jsr win_x1
    sec
    sbc #CAP_ZOOM
    sta zbGx
    lda #CAPTION_ZOOM
    jsr gfx_caption
    jsr win_x1
    sec
    sbc #CAP_CLOSE
    sta zbGx
    lda #CAPTION_CLOSE
    jsr gfx_caption
    lda zbFitW
    beq framed
    rts
framed:
    ; the listing's white, sunken at its top and left, the scroll bar inside its right
    jsr win_x0
    clc
    adc #FRAME
    sta zbGx
    lda zbWinY
    clc
    adc #BODY_EDGE_Y
    sta zbGy
    lda zbWinW
    asl
    asl
    asl
    sec
    sbc #FRAME * 2
    sta zbGw
    lda zbBodyH
    asl
    asl
    asl
    clc
    adc #3
    sta zbGh
    lda #C_WHITE
    jsr gfx_rect
    lda zbGh
    pha
    lda #1
    sta zbGh
    lda #C_ACCENT
    jsr gfx_rect
    pla
    sta zbGh
    lda #1
    sta zbGw
    lda #C_ACCENT
    jsr gfx_rect
    ; the status line's sunken field
    jsr win_x0
    clc
    adc #FRAME + 2
    sta zbGx
    lda zbWinY
    clc
    adc zbWinH
    sec
    sbc #STATUS_BOT + 2
    sta zbGy
    lda zbWinW
    asl
    asl
    asl
    sec
    sbc #(FRAME + 2) * 2
    sta zbGw
    lda #11
    sta zbGh
    lda #BEVEL_FIELD
    jmp gfx_bevel
.endproc


; the bar under the screen: Menu, the window's button, the clock's field
.proc draw_taskbar
    lda #0
    sta zbGx
    sta zbGw
    lda #TASK_Y
    sta zbGy
    lda #240 - TASK_Y
    sta zbGh
    lda #PAL_PANEL
    jsr gfx_pal
    lda #C_GRAY
    jsr gfx_rect
    inc zbGy
    lda #1
    sta zbGh
    lda #C_WHITE
    jsr gfx_rect
    clc
    jsr start_paint
    jsr task_paint
    lda #TRAY_X + 1
    sta zbGx
    lda #TASK_BTN_Y
    sta zbGy
    lda #256 - TRAY_X - 2
    sta zbGw
    lda #TASK_BTN_H
    sta zbGh
    lda #BEVEL_FIELD
    jsr gfx_bevel
    jmp clock_refresh
.endproc
