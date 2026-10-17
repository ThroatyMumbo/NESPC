; the USB adapter on controller port 2 (usbadapter/src/kbdword.h): each strobe, a word of $4B, tag | seq and two
; payload bytes in 11 reads of D0, D3, D4, counted once per seq. Bytes go back over OUT0.

.include "const.inc"
.include "keyboard.inc"
.include "keyboard/adapter.inc"

.export adapter
.export send, recv, note, sys, raw
.exportzp zbaWord
.export wbMouseDx, wbMouseDy, wbMouseBtn, wbMouseWheel

SIG       = $4B
TAG_WHEEL = $80 ; notches, signed, positive down the page; 0
TAG_RAW   = $90 ; HID usage, 1 down / 0 up: a key while raw mode is on (CMD_RAWKEYS)
TAG_KEY   = $A0 ; key, 0
TAG_MOUSE = $B0 ; left << 7 | dx, right << 7 | dy; dx, dy 7-bit signed
TAG_REPLY = $C0 ; byte, 0: from the adapter's link
TAG_MIDI  = $D0 ; on << 7 | note, velocity: a MIDI keyboard
TAG_SYS   = $E0 ; Adapter::SYS_*, 0: a request to the running program
TAG_MASK  = $F0
WORDS_MAX = 6 ; a frame's worth, so an escape sequence arrives together: Shift+Del's ESC [3;2~ is the longest
TX_N      = 32 ; ring sizes, powers of 2
RX_N      = 32
NOTE_N    = 16
RAW_N     = 16
TX_MAX    = 8 ; bytes sent a call, ~200 cycles each

STROBE    = %101 ; OUT0 high; OUT2 stays high for a Family BASIC keyboard's K
LOW       = %100

.segment "ZEROPAGE"

zbaWord: .res 4
zbSeq:   .res 1 ; byte 1 of the last good word

.segment "BSS"

wbMouseDx:  .res 1 ; this call's motion, signed
wbMouseDy:  .res 1
wbMouseBtn: .res 1 ; bit 7 left, bit 6 right, held until a mouse word changes them
wbMouseWheel: .res 1 ; this call's wheel notches, signed, positive down the page

wbaTx:  .res TX_N
wbTxRd: .res 1
wbTxWr: .res 1
wbTx:   .res 1 ; the byte going out
wbaRx:  .res RX_N
wbRxRd: .res 1
wbRxWr: .res 1
wbaNote:  .res NOTE_N
wbaVel:   .res NOTE_N
wbNoteRd: .res 1
wbNoteWr: .res 1
wbSys:    .res 1 ; the last SYS_* not yet taken, 0 for none
wbaRaw:   .res RAW_N
wbaRawDn: .res RAW_N
wbRawRd:  .res 1
wbRawWr:  .res 1

.segment "CODE"

; from NMI: buffer the adapter's words, then send what "send" queued; changes A, X, Y
.proc adapter
    jsr receive
    jmp flush
.endproc

; queue A for the adapter, outside NMI; C = 1 when the queue was full and it was dropped; changes A, X
.proc send
    ldx wbTxWr
    sta wbaTx, x ; the free slot, even when full
    inx
    txa
    and #TX_N - 1
    cmp wbTxRd
    beq full ; C = 1
    sta wbTxWr
    clc
full:
    rts
.endproc

; a byte the adapter sent back in A, C = 0; A = 0, C = 1 when none is waiting; changes A, X
.proc recv
    ldx wbRxRd
    cpx wbRxWr
    beq none ; C = 1
    inx
    txa
    and #RX_N - 1
    sta wbRxRd
    lda wbaRx - 1, x ; X was the slot plus 1, before the wrap
    clc
    rts
none:
    lda #0
    rts
.endproc

; a MIDI note: A = on << 7 | note, X = velocity, C = 0; A = 0, C = 1 when none is waiting; changes A, X, Y
.proc note
    ldy wbNoteRd
    cpy wbNoteWr
    beq none ; C = 1
    iny
    tya
    and #NOTE_N - 1
    sta wbNoteRd
    ldx wbaVel - 1, y ; Y was the slot plus 1, before the wrap
    lda wbaNote - 1, y
    clc
    rts
none:
    lda #0
    rts
.endproc

; a CMD_RAWKEYS key: A = HID usage, X = 1 down / 0 up, C = 0; A = 0, C = 1 when none is waiting; changes A, X, Y
.proc raw
    ldy wbRawRd
    cpy wbRawWr
    beq none ; C = 1
    iny
    tya
    and #RAW_N - 1
    sta wbRawRd
    ldx wbaRawDn - 1, y ; Y was the slot plus 1, before the wrap
    lda wbaRaw - 1, y
    clc
    rts
none:
    lda #0
    rts
.endproc

; a system request: A = SYS_*, C = 0; A = 0, C = 1 when none is waiting; changes A
.proc sys
    lda wbSys
    beq none
    pha
    lda #0
    sta wbSys
    pla
    clc
    rts
none:
    sec
    rts
.endproc

.proc receive
    lda #0
    sta wbMouseDx
    sta wbMouseDy
    sta wbMouseWheel
    ldy #WORDS_MAX
word:
    lda #STROBE
    sta Const::JOYPAD1
    lda #LOW
    sta Const::JOYPAD1
    ldx #8
low: ; reads 0-7: D0, D3, D4 a bit each of bytes 0, 1, 2
    lda Const::JOYPAD2
    lsr
    ror zbaWord
    lsr
    lsr
    lsr
    ror zbaWord + 1
    lsr
    ror zbaWord + 2
    dex
    bne low
    .repeat 2 ; reads 8, 9: D0, D3, D4 into byte 3
    lda Const::JOYPAD2
    lsr
    ror zbaWord + 3
    lsr
    lsr
    lsr
    ror zbaWord + 3
    lsr
    ror zbaWord + 3
    .endrepeat
    lda Const::JOYPAD2 ; read 10: D3, D4 end byte 3
    lsr
    lsr
    lsr
    lsr
    ror zbaWord + 3
    lsr
    ror zbaWord + 3

    lda zbaWord
    cmp #SIG
    bne done
    lda zbaWord + 1
    cmp zbSeq
    beq done ; nothing since the last word
    and #TAG_MASK
    cmp #TAG_MOUSE
    bne :+
    jmp mouse
:   cmp #TAG_REPLY
    beq reply
    cmp #TAG_MIDI
    beq midi
    cmp #TAG_SYS
    beq request
    cmp #TAG_RAW
    beq rawkey
    cmp #TAG_WHEEL
    beq wheel
    cmp #TAG_KEY
    bne done
    lda zbaWord + 1
    sta zbSeq
    lda zbaWord + 2
    beq done ; no key; its seq is the one the next key won't have
    jsr Keyboard::put_key
taken:
    dey
    bne word
done:
    rts

reply:
    lda zbaWord + 1
    sta zbSeq
    ldx wbRxWr
    lda zbaWord + 2
    sta wbaRx, x
    inx
    txa
    and #RX_N - 1
    cmp wbRxRd
    beq taken ; full: dropped
    sta wbRxWr
    jmp taken

request:
    lda zbaWord + 1
    sta zbSeq
    lda zbaWord + 2
    sta wbSys
    jmp taken

wheel:
    lda zbaWord + 1
    sta zbSeq
    lda zbaWord + 2
    clc
    adc wbMouseWheel
    sta wbMouseWheel
    jmp taken

rawkey:
    lda zbaWord + 1
    sta zbSeq
    ldx wbRawWr
    lda zbaWord + 2
    sta wbaRaw, x
    lda zbaWord + 3
    sta wbaRawDn, x
    inx
    txa
    and #RAW_N - 1
    cmp wbRawRd
    beq taken ; full: dropped
    sta wbRawWr
    jmp taken

midi:
    lda zbaWord + 1
    sta zbSeq
    ldx wbNoteWr
    lda zbaWord + 2
    sta wbaNote, x
    lda zbaWord + 3
    sta wbaVel, x
    inx
    txa
    and #NOTE_N - 1
    cmp wbNoteRd
    beq taken ; full: dropped
    sta wbNoteWr
    jmp taken

mouse:
    lda zbaWord + 1
    sta zbSeq
    lda zbaWord + 3
    and #$80
    lsr
    sta wbMouseBtn
    lda zbaWord + 2
    and #$80
    ora wbMouseBtn
    sta wbMouseBtn
    ; sign-extend from 7 bits
    lda zbaWord + 2
    asl
    cmp #$80
    ror
    sta wbMouseDx
    lda zbaWord + 3
    asl
    cmp #$80
    ror
    sta wbMouseDy
    rts
.endproc

; each byte: a port 2 read with OUT0 high, then OUT0 = bit for 8 more reads, LSB first
.proc flush
    ldy #TX_MAX
next:
    ldx wbTxRd
    cpx wbTxWr
    beq done
    lda wbaTx, x
    sta wbTx
    inx
    txa
    and #TX_N - 1
    sta wbTxRd
    lda #STROBE
    sta Const::JOYPAD1
    lda Const::JOYPAD2
    ldx #8
next_bit:
    lda #LOW >> 1
    lsr wbTx
    rol a ; LOW | the bit
    sta Const::JOYPAD1
    lda Const::JOYPAD2
    dex
    bne next_bit
    dey
    bne next
done:
    lda #LOW
    sta Const::JOYPAD1
    rts
.endproc
