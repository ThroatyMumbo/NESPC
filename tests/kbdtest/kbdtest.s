; Keyboard test on mapper 773: the Family BASIC matrix, its raw $4017 bytes and changes (SELECT holds $4016 at 0-7),
; the port 2 USB adapter's last word, and what it and a port 1 PS/2 keyboard typed.

.include "desk.inc"
.include "keyboard/adapter.inc"
.include "keyboard/ps2.inc"
.include "testlib.inc"

.export put_key

KBD        = $4017
KBD_R      = %001 ; OUT0: back to row 0
KBD_C      = %010 ; OUT1: the column; high to low steps the row
KBD_K      = %100 ; OUT2: matrix on
KBD_DATA   = %00011110 ; D1-D4, 0 = pressed
ROWS       = 10 ; the 9 with keys and the keyless 10th the driver probes
KEY_BYTES  = 18
RING_N     = 8 ; changes waiting for the log, 32 bytes each: frame, then the key bytes
RISE_MAX   = 4 ; x 256 reads of 15 cycles, about 8.6 ms

TYPED_N    = 26
ADAPTER_SIG = $4B ; usbadapter/src/kbdword.h
ADAPTER_TAG = $A0

GRID_Y   = 4
PORT2_Y  = 13
HEX_Y    = 14
TYPED_Y  = 18
STATIC_Y = 19
EVENTS_Y = 22
LOG_Y    = 23
LOG_N    = 6

.segment "ZEROPAGE"

; NMI's
zbFrame:   .res 2
zbJoy:     .res 1
zbaScan:   .res ROWS * 2
zbaLast:   .res KEY_BYTES
zbaCur:    .res ROWS * 2
zbaStatic: .res 8
zbWr:      .res 1
zwEvents:  .res 2
zbLost:    .res 1
zbPad:     .res 1
zbPadOld:  .res 1
zbHold:    .res 1
zwRise:    .res 2
zbTyped:   .res 1
; the main loop's
zbSeen:    .res 1
zbRd:      .res 1
zbValid:   .res 1
zbaShown:  .res ROWS * 2
zbaShownStatic: .res 8
zwShownEvents:  .res 2
zbShownLost:    .res 1
zbShownHold:    .res 1
zwShownRise:    .res 2
zbaShownWord:   .res 3
zbShownTyped:   .res 1
zbaPrev:   .res KEY_BYTES
zbBg:      .res 1
zbPx:      .res 1
zbR:       .res 1
zbC:       .res 1
zbE:       .res 1
zbJ:       .res 1
zbK:       .res 1
zbN:       .res 1
zbNew:     .res 1
zbDiff:    .res 1
zbOver:    .res 1

.segment "BSS"

baRing: .res RING_N * 32
baLine: .res 32
baTyped: .res TYPED_N

.segment "RODATA"

rbaPalette:
.repeat 4
.byte $0f, $10, $30, $28
.endrepeat

rbaBit: .byte $02, $04, $08, $10

; three characters a key: by matrix row, $4017 D1-D4 with column 0, then with column 1 (nesdev "Family BASIC Keyboard")
rbaLabels:
.byte "F8 RET[  ]  KNARSHYENSTP"
.byte "F7 @  :  ;  _  /  -  ^  "
.byte "F6 O  L  K  .  ,  P  0  "
.byte "F5 I  U  J  M  N  9  8  "
.byte "F4 Y  G  H  B  V  7  6  "
.byte "F3 T  R  D  F  C  5  4  "
.byte "F2 W  S  A  X  Z  E  3  "
.byte "F1 ESCQ  CTRLSHGRP1  2  "
.byte "CLRUP RGTLFTDWNSPCDELINS"

; column, row, color, text
rbaText:
.byte 1, 1, C_WHITE, "FAMILY BASIC KEYBOARD", 0
.byte 23, 1, C_GRAY, "RISE", 0
.byte 0, 2, C_WHITE, "C0 $4016=$04", 0
.byte 16, 2, C_WHITE, "C1 $4016=$06", 0
.byte 0, 3, C_GRAY, "D1  D2  D3  D4  D1  D2  D3  D4", 0
.byte 0, STATIC_Y, C_WHITE, "$4016 =  0  1  2  3  4  5  6  7", 0
.byte 0, STATIC_Y + 1, C_WHITE, "$4017 =", 0
.byte 0, EVENTS_Y, C_WHITE, "EVENTS", 0
.byte 13, EVENTS_Y, C_WHITE, "LOST", 0
.byte 0, PORT2_Y, C_WHITE, "PORT 2", 0
.byte 24, PORT2_Y, C_GRAY, "SEQ", 0
.byte 0, TYPED_Y, C_WHITE, "TYPED", 0
.byte $ff
.assert * - rbaText <= 256, error, "text indexes off X"

rbaHexCol: .byte 0, 10, 20, 0, 10, 20, 0, 10, 20, 0
rbaHexRow: .byte HEX_Y, HEX_Y, HEX_Y, HEX_Y + 1, HEX_Y + 1, HEX_Y + 1, HEX_Y + 2, HEX_Y + 2, HEX_Y + 2, HEX_Y + 3

; 5 resets before 4 and 7 before 6, so no C fall steps the row while each value is held
rbaStaticOrder: .byte 0, 1, 2, 3, 5, 4, 7, 6

rsHoldOn:  .asciiz "HOLD ON "
rsHoldOff: .asciiz "HOLD OFF"
rsOk:      .asciiz "OK  "
rsNone:    .asciiz "NONE"

.segment "CODE"

.proc start
    lda #KBD_DATA
    ldx #KEY_BYTES - 1
:   sta zbaLast, x
    sta zbaPrev, x
    dex
    bpl :-
    lda #' '
    ldx #TYPED_N - 1
:   sta baTyped, x
    dex
    bpl :-

    jsr text
    jsr screen_on
    ; [fall_through]
.endproc

.proc main
    bit MENU
    bpl :+
    jmp to_menu
:   lda zbFrame
    cmp zbSeen
    beq main
    sta zbSeen

    lda #0
    sta zbR
row:
    lda zbR
    asl
    tax
    lda zbValid
    beq redraw
    lda zbaCur, x
    cmp zbaShown, x
    bne redraw
    lda zbaCur + 1, x
    cmp zbaShown + 1, x
    beq next_row
redraw:
    lda zbaCur, x
    sta zbaShown, x
    lda zbaCur + 1, x
    sta zbaShown + 1, x
    jsr draw_hex
    lda zbR
    cmp #ROWS - 1
    beq next_row
    jsr draw_row
next_row:
    inc zbR
    lda zbR
    cmp #ROWS
    bne row

    ldx #7
static:
    lda zbValid
    beq :+
    lda zbaStatic, x
    cmp zbaShownStatic, x
    beq :++
:   lda zbaStatic, x
    sta zbaShownStatic, x
    jsr draw_static
:   dex
    bpl static

    lda zbValid
    beq :+
    lda zwEvents
    cmp zwShownEvents
    bne :+
    lda zwEvents + 1
    cmp zwShownEvents + 1
    bne :+
    lda zbLost
    cmp zbShownLost
    bne :+
    lda zbHold
    cmp zbShownHold
    bne :+
    lda zwRise
    cmp zwShownRise
    bne :+
    lda zwRise + 1
    cmp zwShownRise + 1
    beq adapter
:   lda zwEvents
    sta zwShownEvents
    lda zwEvents + 1
    sta zwShownEvents + 1
    lda zbLost
    sta zbShownLost
    lda zbHold
    sta zbShownHold
    lda zwRise
    sta zwShownRise
    lda zwRise + 1
    sta zwShownRise + 1
    jsr draw_counts

adapter:
    ldx #2
:   lda zbValid
    beq port2
    lda Adapter::zbaWord, x
    cmp zbaShownWord, x
    bne port2
    dex
    bpl :-
    bmi typed
port2:
    ldx #2
:   lda Adapter::zbaWord, x
    sta zbaShownWord, x
    dex
    bpl :-
    jsr draw_port2

typed:
    lda zbValid
    beq :+
    lda zbTyped
    cmp zbShownTyped
    beq log
:   lda zbTyped
    sta zbShownTyped
    jsr draw_typed

log:
    lda zbRd
    cmp zbWr
    beq done
    asl
    asl
    asl
    asl
    asl
    tax
    jsr log_event
    lda zbRd
    clc
    adc #1
    and #RING_N - 1
    sta zbRd
    jmp log
done:
    lda #1
    sta zbValid
    jmp main
.endproc

; matrix row zbR: its 8 keys, a pressed one black on yellow
.proc draw_row
    lda #0
    sta zbC
cell:
    lda zbR
    asl
    sta zbT
    lda zbC
    lsr
    lsr
    ora zbT
    tax
    lda zbaShown, x
    sta zbT
    lda zbC
    and #3
    tax
    lda rbaBit, x
    and zbT
    beq pressed
    ldx #C_BLACK
    lda #C_GRAY
    bne :+
pressed:
    lda #C_BLACK
    ldx #C_ACCENT
:   sta zbFg
    stx zbBg
    lda zbR
    clc
    adc #GRID_Y
    tay
    lda zbC
    asl
    asl
    jsr at
    lda zbR
    asl
    asl
    asl
    ora zbC
    sta zbT
    asl
    adc zbT
    tax
    lda rbaLabels, x
    jsr putc
    lda rbaLabels + 1, x
    jsr putc
    lda rbaLabels + 2, x
    jsr putc
    inc zbC
    lda zbC
    cmp #8
    bne cell
    rts
.endproc


; "Rn c0 c1" for row zbR
.proc draw_hex
    jsr white
    ldx zbR
    ldy rbaHexRow, x
    lda rbaHexCol, x
    jsr at
    lda #'R'
    jsr putc
    lda zbR
    ora #'0'
    jsr putc
    lda #' '
    jsr putc
    lda zbR
    asl
    tax
    lda zbaShown, x
    jsr puthex
    lda #' '
    jsr putc
    lda zbaShown + 1, x
    jmp puthex
.endproc


; $4017 with $4016 held at X
; keeps: X
.proc draw_static
    jsr white
    stx zbT
    txa
    asl
    adc zbT
    adc #8
    ldy #STATIC_Y + 1
    jsr at
    lda zbaShownStatic, x
    jmp puthex
.endproc


.proc draw_counts
    jsr white
    lda #7
    ldy #EVENTS_Y
    jsr at
    lda zwShownEvents + 1
    jsr puthex
    lda zwShownEvents
    jsr puthex
    lda #18
    ldy #EVENTS_Y
    jsr at
    lda zbShownLost
    jsr puthex
    lda #28
    ldy #1
    jsr at
    lda zwShownRise + 1
    jsr puthex
    lda zwShownRise
    jsr puthex
    lda #22
    ldy #EVENTS_Y
    jsr at
    ldx #0
    lda zbShownHold
    beq off
:   lda rsHoldOn, x
    beq done
    jsr putc
    inx
    bne :-
off:
    lda rsHoldOff, x
    beq done
    jsr putc
    inx
    bne off
done:
    rts
.endproc


; the ring entry at X as a log line, "frame +pressed -released ...", '>' when they don't fit
.proc log_event
    stx zbE
    lda #0
    sta zbN
    sta zbOver
    lda baRing + 1, x
    jsr addhex
    ldx zbE
    lda baRing, x
    jsr addhex
    lda #0
    sta zbJ
byte:
    lda zbJ
    clc
    adc zbE
    tax
    lda baRing + 2, x
    sta zbNew
    ldx zbJ
    eor zbaPrev, x
    and #KBD_DATA
    beq next_byte
    sta zbDiff
    lda zbNew
    sta zbaPrev, x
    lda zbJ
    asl
    asl
    sta zbK
    ldy #0
key:
    lda rbaBit, y
    and zbDiff
    beq next_key
    lda #' '
    jsr addc
    lda rbaBit, y
    and zbNew
    beq :+
    lda #'-'
    bne :++
:   lda #'+'
:   jsr addc
    tya
    clc
    adc zbK
    sta zbT
    asl
    adc zbT
    tax
    lda rbaLabels, x
    jsr addkey
    lda rbaLabels + 1, x
    jsr addkey
    lda rbaLabels + 2, x
    jsr addkey
next_key:
    iny
    cpy #4
    bne key
next_byte:
    inc zbJ
    lda zbJ
    cmp #KEY_BYTES
    bne byte

    lda zbOver
    beq :+
    lda #'>'
    sta baLine + 31
:   jsr scroll
    jsr white
    lda #0
    ldy #LOG_Y + LOG_N - 1
    jsr at
    ldx #0
:   cpx zbN
    beq :+
    lda baLine, x
    jsr putc
    inx
    bne :-
:   rts
.endproc


; the log up a line, its bottom line blank
.proc scroll
:   bit GFX_OP
    bmi :-
    lda #0
    sta GFX_DX
    sta GFX_SX
    sta GFX_W
    sta GFX_FLAGS
    lda #LOG_Y * 8
    sta GFX_DY
    lda #(LOG_Y + 1) * 8
    sta GFX_SY
    lda #(LOG_N - 1) * 8
    sta GFX_H
    lda #OP_COPY
    sta GFX_OP
:   bit GFX_OP
    bmi :-
    lda #(LOG_Y + LOG_N - 1) * 8
    sta GFX_DY
    lda #8
    sta GFX_H
    lda #C_BLACK
    sta GFX_FG
    lda #OP_FILL
    sta GFX_OP
    rts
.endproc


; A onto baLine; zbOver once it is full
; keeps: X, Y
.proc addc
    stx zbPx
    ldx zbN
    cpx #32
    bcs :+
    sta baLine, x
    inc zbN
    ldx zbPx
    rts
:   lda #1
    sta zbOver
    ldx zbPx
    rts
.endproc


; a label character; its padding left out
; keeps: X, Y
.proc addkey
    cmp #' '
    beq :+
    jmp addc
:   rts
.endproc


; keeps: X, Y
.proc addhex
    pha
    lsr
    lsr
    lsr
    lsr
    jsr hexdigit
    jsr addc
    pla
    and #$0f
    jsr hexdigit
    jmp addc
.endproc


.proc hexdigit
    cmp #10
    bcc :+
    adc #6
:   adc #'0'
    rts
.endproc


; the adapter's last word, whether it is one, and its seq
.proc draw_port2
    jsr white
    lda #7
    ldy #PORT2_Y
    jsr at
    lda zbaShownWord
    jsr puthex
    lda #' '
    jsr putc
    lda zbaShownWord + 1
    jsr puthex
    lda #' '
    jsr putc
    lda zbaShownWord + 2
    jsr puthex
    lda #17
    ldy #PORT2_Y
    jsr at
    ldx #0
    lda zbaShownWord
    cmp #ADAPTER_SIG
    bne none
    lda zbaShownWord + 1
    and #$f0
    cmp #ADAPTER_TAG
    bne none
:   lda rsOk, x
    beq seq
    jsr putc
    inx
    bne :-
none:
    lda rsNone, x
    beq seq
    jsr putc
    inx
    bne none
seq:
    lda #28
    ldy #PORT2_Y
    jsr at
    lda zbaShownWord + 1
    and #$0f
    jsr hexdigit
    jmp putc
.endproc


.proc draw_typed
    jsr white
    lda #6
    ldy #TYPED_Y
    jsr at
    ldx #0
:   lda baTyped, x
    jsr putc
    inx
    cpx #TYPED_N
    bne :-
    rts
.endproc


; the adapter driver's key, from NMI: onto the end of the TYPED line, '.' for a control byte
; keeps: Y
.proc put_key
    pha
    ldx #0
:   lda baTyped + 1, x
    sta baTyped, x
    inx
    cpx #TYPED_N - 1
    bne :-
    pla
    cmp #' '
    bcc :+
    cmp #$7f
    bcc :++
:   lda #'.'
:   sta baTyped + TYPED_N - 1
    inc zbTyped
    rts
.endproc


.proc white
    lda #C_WHITE
    sta zbFg
    lda #C_BLACK
    sta zbBg
    rts
.endproc


; the pen to cell A, Y in zbFg on zbBg
; keeps: X
.proc at
    asl
    asl
    asl
    pha
    tya
    asl
    asl
    asl
    tay
:   bit GFX_OP
    bmi :-
    pla
    sta GFX_DX
    sty GFX_DY
    lda #8
    sta GFX_W
    sta GFX_H
    lda zbFg
    sta GFX_FG
    lda zbBg
    sta GFX_BG
    lda #0
    sta GFX_FLAGS
    rts
.endproc


.proc text
    ldx #0
entry:
    lda rbaText, x
    bmi done
    pha
    inx
    lda rbaText, x
    tay
    inx
    lda rbaText, x
    sta zbFg
    inx
    lda #C_BLACK
    sta zbBg
    pla
    jsr at
char:
    lda rbaText, x
    inx
    cmp #0
    beq entry
    jsr putc
    jmp char
done:
    rts
.endproc


.proc nmi
    pha
    txa
    pha
    tya
    pha
    inc zbFrame
    bne :+
    inc zbFrame + 1
:   lda zbFrame
    sta DESK_BANK ; host tap 0x11 reads it back; $8000 is unused here
    lda #0
    sta PPU_SCROLL
    sta PPU_SCROLL
    lda #CTRL_VALUE
    sta PPU_CTRL
    jsr scan
    jsr pad
    jsr track
    jsr Adapter::adapter
    jsr Ps2::ps2
    lda zbHold
    beq :+
    jsr hold
    jsr rise
:   pla
    tay
    pla
    tax
    pla
    rti
.endproc


; $4017 with $4016 held at each of 0-7
.proc hold
    ldy #0
:   ldx rbaStaticOrder, y
    stx JOYPAD1
    jsr delay
    lda KBD
    sta zbaStatic, x
    iny
    cpy #8
    bne :-
    rts
.endproc


; the driver's scan: reset, then C toggled before each read
.proc scan
    lda #KBD_K | KBD_R
    sta JOYPAD1
    lda #KBD_K | KBD_C
    sta zbJoy
    jsr delay
    ldx #0
:   lda zbJoy
    eor #KBD_C
    sta zbJoy
    sta JOYPAD1
    jsr delay
    lda KBD
    sta zbaScan, x
    inx
    cpx #ROWS * 2
    bne :-
    rts
.endproc


; pad 1, latched by the scan's $05 so K stays high, ORed with the host's; SELECT toggles HOLD
.proc pad
    lda #1
    sta zbPad
:   lda JOYPAD1
    lsr
    rol zbPad
    bcc :-
    lda zbPad
    ora HOST_PAD
    tax
    eor zbPadOld
    stx zbPadOld
    and zbPadOld
    and #JOYPAD_SELECT
    beq :+
    lda zbHold
    eor #1
    sta zbHold
:   rts
.endproc


; K high, then the count of $4017 reads until D1-D4 are all 1: 1 at once, RISE_MAX x 256 + 1 never, 0 unmeasured
.proc rise
    lda #KBD_K
    sta JOYPAD1
    ldx #0
    ldy #0
:   lda KBD
    and #KBD_DATA
    cmp #KBD_DATA
    beq done
    inx
    bne :-
    iny
    cpy #RISE_MAX
    bne :-
done:
    inx
    bne :+
    iny
:   stx zwRise
    sty zwRise + 1
    rts
.endproc


; the driver's settling time
.proc delay
    sec
    lda #0
:   ror
    bne :-
    rts
.endproc


; a key change goes into the ring; zbaCur gets this scan
.proc track
    ldx #KEY_BYTES - 1
:   lda zbaScan, x
    eor zbaLast, x
    and #KBD_DATA
    bne changed
    dex
    bpl :-
    bmi publish
changed:
    inc zwEvents
    bne :+
    inc zwEvents + 1
:   lda zbWr
    clc
    adc #1
    and #RING_N - 1
    cmp zbRd
    bne room
    lda zbLost
    cmp #$ff
    beq remember
    inc zbLost
    bne remember
room:
    pha
    lda zbWr
    asl
    asl
    asl
    asl
    asl
    tax
    lda zbFrame
    sta baRing, x
    lda zbFrame + 1
    sta baRing + 1, x
    ldy #0
:   lda zbaScan, y
    and #KBD_DATA
    sta baRing + 2, x
    inx
    iny
    cpy #KEY_BYTES
    bne :-
    pla
    sta zbWr
remember:
    ldx #KEY_BYTES - 1
:   lda zbaScan, x
    sta zbaLast, x
    dex
    bpl :-
publish:
    ldx #ROWS * 2 - 1
:   lda zbaScan, x
    sta zbaCur, x
    dex
    bpl :-
    rts
.endproc
