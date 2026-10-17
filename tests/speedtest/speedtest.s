; Port 2 speed test on mapper 773: the usbadapter's bench times a known pattern going down through
; two decoders and up through the link. Each test's rate big, with OK when every byte arrived right.

.include "desk.inc"
.include "keyboard/adapter.inc"
.include "testlib.inc"

.export put_key

JOYPAD2    = $4017
CTRL_QUIET = %00001000 ; NMI off while a transfer runs
STROBE     = %101 ; as adapter.s
LOW        = %100
PASS       = 256 ; bytes a down pass (usbadapter/src/bench.h BENCH_PASS)
PASSES     = 16 ; down passes a decoder a round
UP_PAGES   = 16 ; 4 KB up a round
UP_CHUNK   = 32 ; bytes unrolled in up_burst
SETTLE     = 3 ; frames for the adapter to act on a command
REC_LEN    = 16 ; a test's report: KB/s, cycles a byte, errors, in ASCII (usbadapter/src/link.h)
REPLY_WAIT = 120 ; frames before a missing report counts as none

wbaBuf = $0200 ; a down pass lands here, below MENU_STUB

.segment "ZEROPAGE"

zbFrame:  .res 1
zbRound:  .res 1
zbMode:   .res 1 ; 0 fast, 1 table
zbPass:   .res 1
zbPages:  .res 1
zbGot:    .res 1
zbWait:   .res 1
zbTest:   .res 1
zbBase:   .res 1 ; the test's record in wbaRec
zbBigY:   .res 1
zbSmallY: .res 1
zbLen:    .res 1

.segment "BSS"

wbErrLo: .res 2 ; wrong bytes this round, fast and table
wbErrHi: .res 2
wbaCmd:  .res 5
wbaRec:  .res REC_LEN * 3
wbaStr:  .res 8

.segment "TABLES"

; bench.h bench_byte
rbaPattern:
.repeat 256, k
    .byte <((k * 167 + 29) ^ (k >> 3))
.endrepeat

; indexed by a raw $4017 read, $40 | D4 << 4 | D3 << 3 | D0: table n at rbaDecode + $20 * n
rbaDecode:
    .res $40
.repeat 32, i ; fast: D0 -> bit 1, D3 -> bit 7
    .byte (i & 1) << 1 | (i >> 3 & 1) << 7
.endrepeat
.repeat 32, i ; table, first read: bits 0-2
    .byte (i & 1) | (i >> 3 & 1) << 1 | (i >> 4 & 1) << 2
.endrepeat
.repeat 32, i ; second: bits 3-5
    .byte (i & 1) << 3 | (i >> 3 & 1) << 4 | (i >> 4 & 1) << 5
.endrepeat
.repeat 32, i ; third: bits 6-7
    .byte (i & 1) << 6 | (i >> 3 & 1) << 7
.endrepeat

.segment "RODATA"

rbaPalette:
.repeat 4
.byte $0f, $10, $30, $2a
.endrepeat

rsTitle:  .asciiz "PORT 2 SPEED"
rsLabel0: .asciiz "ADAPTER TO NES, FAST DECODE"
rsLabel1: .asciiz "ADAPTER TO NES, TABLE DECODE"
rsLabel2: .asciiz "NES TO ADAPTER"
rsKbs:    .asciiz " KB/S"
rsCycles: .asciiz " CYCLES/BYTE"
rsErrors: .asciiz " ERRORS"
rsRound:  .asciiz "ROUND $"
rsOk:     .asciiz "  OK"
rsBad:    .asciiz " BAD"
rsNone:   .asciiz "NONE"

rbaNoReply: .byte "  ---  ---      "
.assert * - rbaNoReply = REC_LEN, error, "a record is REC_LEN bytes"

rbaRowY:    .byte 44, 104, 164
rbaLabelLo: .byte <rsLabel0, <rsLabel1, <rsLabel2
rbaLabelHi: .byte >rsLabel0, >rsLabel1, >rsLabel2
rbaVerdictLo: .byte <rsOk, <rsBad, <rsNone
rbaVerdictHi: .byte >rsOk, >rsBad, >rsNone
rbaVerdictFg: .byte C_ACCENT, C_WHITE, C_GREY

.segment "LOW"

; one down pass into wbaBuf, 24 cycles a byte: bench.h BENCH_FAST's layout
.proc down_fast
.repeat ::PASS, k
    ldx JOYPAD2
    lda JOYPAD2
    asl
    asl
    eor JOYPAD2
    ora rbaDecode, x
    sta wbaBuf + k
.endrepeat
    rts
.endproc

; one down pass into wbaBuf, 28 cycles a byte, whatever the expansion port's D1, D2 read: BENCH_TABLE's layout
.proc down_table
.repeat ::PASS, k
    ldx JOYPAD2
    lda rbaDecode + $20, x
    ldx JOYPAD2
    ora rbaDecode + $40, x
    ldx JOYPAD2
    ora rbaDecode + $60, x
    sta wbaBuf + k
.endrepeat
    rts
.endproc

; UP_PAGES of rbaPattern up the link, 90 cycles a byte: a read with OUT0 high, then OUT0 = each bit for a read
.proc up_burst
    ldy #1
    lda #UP_PAGES
    sta zbPages
page:
    ldx #0
chunk:
.repeat ::UP_CHUNK, k
    lda rbaPattern + k, x
    sty JOYPAD1
    bit JOYPAD2
.repeat 7
    sta JOYPAD1
    bit JOYPAD2
    lsr
.endrepeat
    sta JOYPAD1
    bit JOYPAD2
.endrepeat
    txa
    clc
    adc #UP_CHUNK
    tax
    beq :+
    jmp chunk
:   dec zbPages
    beq :+
    jmp page
:   lda #LOW
    sta JOYPAD1
    rts
.endproc

.segment "CODE"

.proc start
    lda #1
    sta zbBig
    lda #C_WHITE
    sta zbFg
    ldx #<rsTitle
    ldy #>rsTitle
    lda #32
    sta zbT
    lda #12
    jsr print
    lda #0
    sta zbBig
    lda #C_GREY
    sta zbFg
    lda #8
    sta zbT
    ldx #0
:   stx zbTest
    lda rbaLabelLo, x
    pha
    ldy rbaLabelHi, x
    lda rbaRowY, x
    tax
    pla
    sta zpS
    txa
    ldx zpS
    jsr print
    ldx zbTest
    inx
    cpx #3
    bne :-
    jsr screen_on
    ; [fall_through]
.endproc

.proc main
round:
    lda #0
    ldx #3
:   sta wbErrLo, x
    dex
    bpl :-
    sta zbMode
mode:
    lda #0
    sta zbPass
pass:
    bit MENU
    bpl :+
    jmp to_menu
:   jsr down_pass
    inc zbPass
    lda zbPass
    cmp #PASSES
    bne pass
    inc zbMode
    lda zbMode
    cmp #2
    bne mode
    jsr up_test
    jsr report
    jsr show
    inc zbRound
    jmp round
.endproc

; CMD_BENCH with the zbLen bytes of wbaCmd, sent now
.proc command
    lda #Adapter::CMD_BENCH
    jsr Adapter::send
    lda zbLen
    jsr Adapter::send
    ldy #0
:   lda wbaCmd, y
    jsr Adapter::send
    iny
    cpy zbLen
    bne :-
    jmp Adapter::adapter
.endproc

; pass zbPass of decoder zbMode; its wrong bytes add to wbErrLo/Hi
.proc down_pass
    lda #Adapter::BENCH_DOWN
    sta wbaCmd
    lda zbMode
    sta wbaCmd + 1
    lda zbPass
    sta wbaCmd + 2
    lda #3
    sta zbLen
    jsr command
    lda #SETTLE
    jsr wait_frames
    lda #CTRL_QUIET
    sta PPU_CTRL
    lda #STROBE
    sta JOYPAD1
    lda #LOW
    sta JOYPAD1
    lda zbMode
    bne :+
    jsr down_fast
    jmp :++
:   jsr down_table
:   lda #CTRL_VALUE
    sta PPU_CTRL
    lda #1
    jsr wait_frames

    ldy zbMode
    ldx #0
check:
    lda wbaBuf, x
    eor zbPass
    cmp rbaPattern, x
    beq :+
    lda wbErrLo, y
    clc
    adc #1
    sta wbErrLo, y
    bcc :+
    lda wbErrHi, y
    adc #0
    sta wbErrHi, y
:   inx
    bne check
    rts
.endproc

.proc up_test
    lda #Adapter::BENCH_UP
    sta wbaCmd
    lda #<(UP_PAGES * 256)
    sta wbaCmd + 1
    lda #>(UP_PAGES * 256)
    sta wbaCmd + 2
    lda #3
    sta zbLen
    jsr command
    lda #SETTLE
    jsr wait_frames
    lda #CTRL_QUIET
    sta PPU_CTRL
    jsr up_burst
    lda #CTRL_VALUE
    sta PPU_CTRL
    lda #1
    jmp wait_frames
.endproc

; the round's results into wbaRec, or rbaNoReply's when none come back
.proc report
    lda #Adapter::BENCH_REPORT
    sta wbaCmd
    lda wbErrLo
    sta wbaCmd + 1
    lda wbErrHi
    sta wbaCmd + 2
    lda wbErrLo + 1
    sta wbaCmd + 3
    lda wbErrHi + 1
    sta wbaCmd + 4
    lda #5
    sta zbLen
    jsr command
    lda #0
    sta zbGot
    lda #REPLY_WAIT
    sta zbWait
frame:
    lda #1
    jsr wait_frames
    jsr Adapter::adapter
take:
    jsr Adapter::recv
    bcs none
    ldx zbGot
    sta wbaRec, x
    inx
    stx zbGot
    cpx #REC_LEN * 3
    bne take
    rts
none:
    dec zbWait
    bne frame
    ldx #REC_LEN * 3 - 1
:   txa
    and #REC_LEN - 1
    tay
    lda rbaNoReply, y
    sta wbaRec, x
    dex
    bpl :-
    rts
.endproc

; each test's rate, verdict, cycles a byte and errors
.proc show
    lda #0
    sta zbTest
test:
    ldx zbTest
    lda rbaRowY, x
    clc
    adc #12
    sta zbBigY
    adc #20
    sta zbSmallY
    txa
    asl
    asl
    asl
    asl
    sta zbBase

    lda #1
    sta zbBig
    lda #C_WHITE
    sta zbFg
    lda #8
    sta zbT
    lda zbBase
    ldx #5
    jsr field
    lda zbBigY
    jsr print
    lda #88
    sta zbT
    ldx #<rsKbs
    ldy #>rsKbs
    lda zbBigY
    jsr print
    jsr verdict
    lda rbaVerdictFg, x
    sta zbFg
    lda #184
    sta zbT
    lda rbaVerdictLo, x
    pha
    ldy rbaVerdictHi, x
    pla
    tax
    lda zbBigY
    jsr print

    lda #0
    sta zbBig
    lda #C_GREY
    sta zbFg
    lda #8
    sta zbT
    lda zbBase
    clc
    adc #5
    ldx #5
    jsr field
    lda zbSmallY
    jsr print
    lda #48
    sta zbT
    ldx #<rsCycles
    ldy #>rsCycles
    lda zbSmallY
    jsr print
    lda #144
    sta zbT
    lda zbBase
    clc
    adc #10
    ldx #6
    jsr field
    lda zbSmallY
    jsr print
    lda #192
    sta zbT
    ldx #<rsErrors
    ldy #>rsErrors
    lda zbSmallY
    jsr print

    inc zbTest
    lda zbTest
    cmp #3
    beq :+
    jmp test
:   lda #8
    sta zbT
    ldx #<rsRound
    ldy #>rsRound
    lda #224
    jsr print
    lda zbRound
    jmp puthex
.endproc

; X = 0 OK, 1 BAD (errors), 2 NONE (no rate) for the record at zbBase
.proc verdict
    ldx #2
    lda zbBase
    clc
    adc #4
    tay
    lda wbaRec, y
    cmp #'-'
    beq done
    ldx #0
    tya
    clc
    adc #6 ; errors at zbBase + 10
    tay
    lda #6
    sta zbLen
:   lda wbaRec, y
    cmp #' '
    beq :+
    cmp #'0'
    beq :+
    ldx #1
:   iny
    dec zbLen
    bne :--
done:
    rts
.endproc

; wbaStr = the X characters of wbaRec from A; YX = wbaStr for "print"
.proc field
    stx zbLen
    tay
    ldx #0
:   lda wbaRec, y
    sta wbaStr, x
    iny
    inx
    cpx zbLen
    bne :-
    lda #0
    sta wbaStr, x
    ldx #<wbaStr
    ldy #>wbaStr
    rts
.endproc

; A frames, by NMI
.proc wait_frames
    clc
    adc zbFrame
:   cmp zbFrame
    bne :-
    rts
.endproc

; Adapter::adapter puts keys here; this test takes none
.proc put_key
    rts
.endproc

; frames only: the port is the main loop's
.proc nmi
    pha
    inc zbFrame
    lda #0
    sta PPU_SCROLL
    sta PPU_SCROLL
    lda #CTRL_VALUE
    sta PPU_CTRL
    pla
    rti
.endproc
