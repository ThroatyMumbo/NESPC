; Port 2 adapter link test on mapper 773: sends ECHO packets of a running count through Adapter::send and checks
; that Adapter::recv hands the same bytes back in order. One verdict in big letters, the counts under it.

.include "desk.inc"
.include "keyboard/adapter.inc"
.include "testlib.inc"

.export put_key

ECHO_N     = 8 ; payload bytes a packet
RESEND     = 120 ; frames before a packet counts as lost and the next goes out
SILENT     = 60 ; frames with no reply before the verdict is NO REPLY

ST_WAIT  = 0
ST_OK    = 1
ST_QUIET = 2
ST_BAD   = 3

.segment "ZEROPAGE"

zbFrame:   .res 1
zbSeen:    .res 1
zbNext:    .res 1 ; the next payload byte to send
zbExpect:  .res 1 ; the next byte due back
zbOut:     .res 1 ; payload bytes not back yet
zbWait:    .res 1 ; frames the packet has been out
zbSilent:  .res 1 ; frames since a reply, stops at 255
zbLost:    .res 1 ; packets resent after RESEND
zwSent:    .res 2
zwBack:    .res 2
zwBad:     .res 2
zbState:   .res 1
zbShown:   .res 1 ; zbState drawn, $ff none yet

.segment "RODATA"

rbaPalette:
.repeat 4
.byte $0f, $10, $30, $2a
.endrepeat

rsTitle: .asciiz "ADAPTER LINK"
rsWait:  .asciiz "WAITING "
rsOk:    .asciiz "ECHO OK "
rsQuiet: .asciiz "NO REPLY"
rsBad:   .asciiz "BAD DATA"
rsSent:  .asciiz "SENT     $"
rsBack:  .asciiz "BACK     $"
rsBadN:  .asciiz "WRONG    $"
rsLost:  .asciiz "RESENT   $"

rbaStateLo: .byte <rsWait, <rsOk, <rsQuiet, <rsBad
rbaStateHi: .byte >rsWait, >rsOk, >rsQuiet, >rsBad
rbaStateFg: .byte C_GREY, C_ACCENT, C_WHITE, C_WHITE

.segment "CODE"

.proc start
    lda #$ff
    sta zbShown
    lda #1
    sta zbBig
    lda #C_WHITE
    sta zbFg
    ldx #<rsTitle
    ldy #>rsTitle
    lda #32
    sta zbT
    lda #24
    jsr print
    lda #0
    sta zbBig
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

    lda zbSilent
    cmp #255
    beq replies
    inc zbSilent
replies:
    jsr Adapter::recv
    bcs check
    cmp zbExpect
    beq :+
    inc zwBad
    bne :+
    inc zwBad + 1
:   clc
    adc #1
    sta zbExpect
    inc zwBack
    bne :+
    inc zwBack + 1
:   lda #0
    sta zbSilent
    sta zbWait
    lda zbOut
    beq replies
    dec zbOut
    jmp replies

check:
    lda zbOut
    beq packet
    inc zbWait
    lda zbWait
    cmp #RESEND
    bcc verdict
    inc zbLost
    lda zbNext
    sta zbExpect
packet:
    lda #Adapter::CMD_ECHO
    jsr Adapter::send
    lda #ECHO_N
    jsr Adapter::send
    ldy #ECHO_N
:   lda zbNext
    jsr Adapter::send
    inc zbNext
    dey
    bne :-
    lda #ECHO_N
    sta zbOut
    lda #0
    sta zbWait
    lda zwSent
    clc
    adc #ECHO_N
    sta zwSent
    bcc verdict
    inc zwSent + 1

verdict:
    ldx #ST_BAD
    lda zwBad
    ora zwBad + 1
    bne :+
    ldx #ST_QUIET
    lda zbSilent
    cmp #SILENT
    bcs :+
    ldx #ST_OK
    lda zwBack
    ora zwBack + 1
    bne :+
    ldx #ST_WAIT
:   stx zbState
    cpx zbShown
    beq counts
    stx zbShown
    lda rbaStateFg, x
    sta zbFg
    lda #1
    sta zbBig
    lda #64
    sta zbT
    lda rbaStateLo, x
    pha
    ldy rbaStateHi, x
    pla
    tax
    lda #88
    jsr print
    lda #0
    sta zbBig

counts:
    lda zbFrame
    and #7
    bne done
    lda #C_GREY
    sta zbFg
    lda #48
    sta zbT
    ldx #<rsSent
    ldy #>rsSent
    lda #144
    jsr print
    lda zwSent + 1
    jsr puthex
    lda zwSent
    jsr puthex
    ldx #<rsBack
    ldy #>rsBack
    lda #160
    jsr print
    lda zwBack + 1
    jsr puthex
    lda zwBack
    jsr puthex
    ldx #<rsBadN
    ldy #>rsBadN
    lda #176
    jsr print
    lda zwBad + 1
    jsr puthex
    lda zwBad
    jsr puthex
    ldx #<rsLost
    ldy #>rsLost
    lda #192
    jsr print
    lda zbLost
    jsr puthex
done:
    jmp main
.endproc

; Adapter::adapter puts keys here; this test takes none
.proc put_key
    rts
.endproc

.proc nmi
    pha
    txa
    pha
    tya
    pha
    inc zbFrame
    lda zbFrame
    sta DESK_BANK ; host tap 0x11 reads it back; $8000 is unused here
    lda #0
    sta PPU_SCROLL
    sta PPU_SCROLL
    lda #CTRL_VALUE
    sta PPU_CTRL
    jsr Adapter::adapter
    pla
    tay
    pla
    tax
    pla
    rti
.endproc
