; The taskbar's button: the window's while it isn't closed, an icon in sprites, raised, or pressed and checkered while
; the window shows.

.include "desk.inc"

ICON_DX = 5 ; the icon on a raised button; pressed, one right and one down
ICON_DY = 2

.segment "SHELL_BSS"

wbTaskN:   .res 1 ; buttons
wbTaskWin: .res 1 ; 1 when the first is the window's
wbTaskI:   .res 1
wbTaskO:   .res 1 ; the next icon's OAM offset
wbTaskD:   .res 1 ; 1 on a pressed button

.segment "RODATA"

rbaTaskX: ; each button's left edge
.repeat TASK_MAX, i
    .byte TASK_X + 1 + i * TASK_STEP
.endrepeat

.segment "SHELL"

; wbTaskN and wbTaskWin for the state now
.proc task_list
    ldx #1
    lda zbIcon
    beq :+
    lda zbClosed
    beq :+
    dex
:   stx wbTaskWin
    stx wbTaskN
    rts
.endproc

; > C set when button wbTaskI is the window's, pressed while it shows
.proc task_down
    lda wbTaskI
    bne no
    lda wbTaskWin
    beq no
    lda zbIcon
    bne no
    sec
    rts
no:
    clc
    rts
.endproc


; the buttons' bevels, on the bar draw_taskbar has just filled
.proc task_paint
    jsr task_list
    lda #0
    sta wbTaskI
next:
    lda wbTaskI
    cmp wbTaskN
    beq done
    tax
    lda rbaTaskX, x
    sta zbGx
    lda #TASK_BTN_Y
    sta zbGy
    lda #TASK_BTN_W
    sta zbGw
    lda #TASK_BTN_H
    sta zbGh
    jsr task_down
    bcs down
    lda #BEVEL_RAISED
    jsr gfx_bevel
    jmp step
down:
    lda #BEVEL_SUNKEN
    jsr gfx_bevel
    inc zbGx
    inc zbGx
    lda #TASK_BTN_Y + 2
    sta zbGy
    lda #TASK_BTN_W - 3
    sta zbGw
    lda #TASK_BTN_H - 3
    sta zbGh
    jsr gfx_checker
step:
    inc wbTaskI
    bne next
done:
    rts
.endproc


; every frame after the boot: each button's icon in sprites from TASK_OAM, the rest of them off the screen
.proc task_sync
    jsr task_list
    lda #0
    sta wbTaskI
    lda #TASK_OAM - OAM
    sta wbTaskO
next:
    lda wbTaskI
    cmp wbTaskN
    beq hide
    jsr win_icon_pick
    jsr task_down
    lda #0
    rol
    sta wbTaskD
    ldy wbTaskI
    lda rbaTaskX, y
    clc
    adc #ICON_DX
    adc wbTaskD
    sta wbSprX
    lda #2
    sta wbSprW
    lda #TASK_BTN_Y + ICON_DY - OAM_Y_BIAS
    clc
    adc wbTaskD
    ldx wbTaskO
    jsr icon_sprites_at
    stx wbTaskO
    inc wbTaskI
    bne next
hide:
    lda #TASK_MAX
    sec
    sbc wbTaskN
    asl
    asl
    beq done
    tay
    ldx wbTaskO
    jmp sprites_hide
done:
    rts
.endproc


; after pointer_px: > C set when the pointer is on the window's button, A = $ff
.proc task_hit
    jsr task_list
    lda zbPy
    cmp #TASK_Y
    bcc no
    ldy #0
find:
    cpy wbTaskN
    beq no
    lda zbPx
    sec
    sbc rbaTaskX, y
    bcc no
    cmp #TASK_BTN_W
    bcc hit
    iny
    bne find
hit:
    tya
    sec
    sbc wbTaskWin
    sec
    rts
no:
    clc
    rts
.endproc
