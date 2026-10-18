; Sprite 0 pointer, moved 2 px a frame with the D-pad on pad 1 (or the host pad) or by the port 2 USB mouse, whose
; left and right buttons are A and B; latches new button presses.

.include "desk.inc"
.include "keyboard/adapter.inc"

.export put_key

SPEED = 2
X_MAX = 255
Y_MAX = 231
KEYS_N = 16 ; put_key's ring, a power of 2

.segment "ZEROPAGE"

zbPad:    .res 1
zbPadNew: .res 1 ; buttons down this frame and not the last
zbPadOld: .res 1
zbX:   .res 1
zbY:   .res 1
zbPx:  .res 1 ; pointer_px: the pixel under the pointer's tip
zbPy:  .res 1

.segment "BSS"

wbaKey:  .res KEYS_N
wbKeyRd: .res 1
wbKeyWr: .res 1

.segment "CODE"

.proc pointer_init
    lda #$ff
    ldx #0
hide:
    sta OAM, x
    inx
    bne hide

    lda #T_POINTER
    sta OAM + 1
    lda #0
    sta OAM + 2
    lda #128
    sta zbX
    lda #120
    sta zbY
    jmp store
.endproc

.proc pointer_update
    lda #1
    sta JOYPAD1
    sta zbPad
    lsr
    sta JOYPAD1
read:
    lda JOYPAD1
    lsr
    rol zbPad
    bcc read
    jsr Adapter::adapter
    lda zbPad
    ora HOST_PAD
    ora Adapter::wbMouseBtn
    sta zbPad
    lda zbPadOld
    eor #$ff
    and zbPad
    sta zbPadNew
    lda zbPad
    sta zbPadOld

    lda Adapter::wbMouseDx
    beq no_dx
    bmi dx_neg
    clc
    adc zbX
    bcc :+
    lda #X_MAX
:   sta zbX
    jmp no_dx
dx_neg:
    clc
    adc zbX
    bcs :+
    lda #0
:   sta zbX
no_dx:

    lda Adapter::wbMouseDy
    beq no_dy
    bmi dy_neg
    clc
    adc zbY
    bcs dy_max
    cmp #Y_MAX + 1
    bcc :+
dy_max:
    lda #Y_MAX
:   sta zbY
    jmp no_dy
dy_neg:
    clc
    adc zbY
    bcs :+
    lda #0
:   sta zbY
no_dy:

    lda zbPad
    and #JOYPAD_RIGHT
    beq no_right
    lda zbX
    clc
    adc #SPEED
    bcc :+
    lda #X_MAX
:   sta zbX
no_right:

    lda zbPad
    and #JOYPAD_LEFT
    beq no_left
    lda zbX
    sec
    sbc #SPEED
    bcs :+
    lda #0
:   sta zbX
no_left:

    lda zbPad
    and #JOYPAD_DOWN
    beq no_down
    lda zbY
    clc
    adc #SPEED
    cmp #Y_MAX + 1
    bcc :+
    lda #Y_MAX
:   sta zbY
no_down:

    lda zbPad
    and #JOYPAD_UP
    beq no_up
    lda zbY
    sec
    sbc #SPEED
    bcs :+
    lda #0
:   sta zbY
no_up:
    ; [fall_through]
.endproc

.proc store
    lda zbY
    sta OAM + 0
    lda zbX
    sta OAM + 3
    rts
.endproc


; the adapter driver's key A into the ring, dropped when it is full
; keeps: Y
.proc put_key
    ldx wbKeyWr
    sta wbaKey, x
    inx
    txa
    and #KEYS_N - 1
    cmp wbKeyRd
    beq full
    sta wbKeyWr
full:
    rts
.endproc


; > A = the oldest key put_key kept, C set when there is none
.proc key_next
    ldx wbKeyRd
    cpx wbKeyWr
    beq none
    lda wbaKey, x
    pha
    inx
    txa
    and #KEYS_N - 1
    sta wbKeyRd
    pla
    clc
    rts
none:
    sec
    rts
.endproc


.proc pointer_px
    lda zbX
    sta zbPx
    ldx zbY
    inx ; OAM_Y_BIAS
    stx zbPy
    rts
.endproc


; the pointer's tip to column A, row X
.proc pointer_put
    sta zbX
    txa
    beq :+
    dex ; OAM_Y_BIAS
:   cpx #Y_MAX + 1
    bcc :+
    ldx #Y_MAX
:   stx zbY
    jmp store
.endproc


.proc pointer_busy
    lda #T_HOURGLASS
    sta OAM + 1
    rts
.endproc


; keeps: A and the flags
.proc pointer_idle
    php
    pha
    lda #T_POINTER
    sta OAM + 1
    pla
    plp
    rts
.endproc
