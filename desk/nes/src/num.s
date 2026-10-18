; Division and decimal text for the status line.

.include "desk.inc"

DEC_LEN = 10 ; digits of 2^32 - 1

.segment "ZEROPAGE"

zdNum:    .res 4
zbDiv:    .res 1
zpStr:    .res 2

.segment "SHELL_BSS"

wbDecCol: .res 1
wbDecI:   .res 1
wbaDec:.res DEC_LEN

.segment "SHELL"

; zdNum /= A (1-255)
; > A = remainder
; changes: A, X
.proc udiv32_8
    sta zbDiv
    lda #0
    ldx #32
loop:
    asl zdNum
    rol zdNum + 1
    rol zdNum + 2
    rol zdNum + 3
    rol
    bcs sub ; 9-bit remainder, so at least the divisor
    cmp zbDiv
    bcc next
sub:
    sbc zbDiv
    inc zdNum
next:
    dex
    bne loop
    rts
.endproc


; zdNum in decimal into wbaRow from column Y on; zdNum ends up 0
; > Y = column after the last digit
.proc put_dec
    sty wbDecCol
    lda #DEC_LEN
    sta wbDecI
digit:
    lda #10
    jsr udiv32_8
    dec wbDecI
    ldx wbDecI
    ora #'0'
    sta wbaDec, x
    lda zdNum
    ora zdNum + 1
    ora zdNum + 2
    ora zdNum + 3
    bne digit
    ldy wbDecCol
copy:
    lda wbaDec, x
    sta wbaRow, y
    iny
    inx
    cpx #DEC_LEN
    bne copy
    rts
.endproc


; the zero-terminated string at A (low), X (high) into wbaRow from column Y on
; > Y = column after it
.proc put_str
    sta zpStr
    stx zpStr + 1
    ldx #0
loop:
    sty wbDecCol
    txa
    tay
    lda (zpStr), y
    beq done
    ldy wbDecCol
    sta wbaRow, y
    iny
    inx
    bne loop
done:
    ldy wbDecCol
    rts
.endproc
