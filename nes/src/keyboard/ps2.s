; a PS/2 keyboard wired straight to controller port 1, no MCU: DATA on D3, CLK on D4, and CLK pulled low through a
; Schottky diode by OUT0, so the keyboard is inhibited (and buffers keys) whenever OUT0 is low.

.include "const.inc"
.include "keyboard.inc"
.include "keyboard/ps2.inc"

.export ps2

PORT    = Const::JOYPAD1
DATA    = %00001000 ; D3; the port's inputs read inverted: 1 = line low
CLK     = %00010000 ; D4
RELEASE = %101      ; OUT0 high frees CLK; OUT2 kept high as adapter.s keeps it
INHIBIT = %100

; wait loops are 13 cycles a pass at 1.79 MHz
START_PASSES = 138 ; ~1 ms for a buffered key's start bit after the release
GAP_PASSES   = 138 ; ~1 ms for the next byte of a sequence
BIT_PASSES   = 40  ; ~300 us for one clock edge; a PS/2 half period is 30-50 us
BYTES_MAX    = 8

BREAK = $80 ; wbPre: $F0 seen
EXT   = $40 ; $E0 seen

MOD_LSHIFT = $01 ; wbMods
MOD_RSHIFT = $02
MOD_LCTRL  = $04
MOD_RCTRL  = $08
MOD_LALT   = $10
MOD_RALT   = $20
MOD_CAPS_HELD = $40 ; typematic repeats Caps Lock's make code; toggle once a press
MOD_CAPS   = $80
MOD_SHIFT = MOD_LSHIFT | MOD_RSHIFT
MOD_CTRL  = MOD_LCTRL | MOD_RCTRL
MOD_ALT   = MOD_LALT | MOD_RALT

CAPS_CODE = $58

.segment "BSS"

wbaRaw:  .res BYTES_MAX ; this window's bytes, decoded once the keyboard is inhibited again
wbCount: .res 1
wbByte:  .res 1 ; the frame coming in, inverted
wbOnes:  .res 1 ; 1 bits of data + parity, odd when the parity is good
wbPre:   .res 1
wbFlags: .res 1 ; wbPre of the code being decoded
wbMods:  .res 1
wbShift: .res 1

.segment "RODATA"

; scancode set 2, US: make code to ASCII, 0 for none; the keypad as digits (num lock is the keyboard's, unseen)
rbaPlain:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $09, '`', $00 ; $00
    .byte $00, $00, $00, $00, $00, 'q', '1', $00, $00, $00, 'z', 's', 'a', 'w', '2', $00 ; $10
    .byte $00, 'c', 'x', 'd', 'e', '4', '3', $00, $00, $20, 'v', 'f', 't', 'r', '5', $00 ; $20
    .byte $00, 'n', 'b', 'h', 'g', 'y', '6', $00, $00, $00, 'm', 'j', 'u', '7', '8', $00 ; $30
    .byte $00, ',', 'k', 'i', 'o', '0', '9', $00, $00, '.', '/', 'l', ';', 'p', '-', $00 ; $40
    .byte $00, $00, $27, $00, '[', '=', $00, $00, $00, $00, $0D, ']', $00, $5C, $00, $00 ; $50
    .byte $00, $00, $00, $00, $00, $00, $08, $00, $00, '1', $00, '4', '7', $00, $00, $00 ; $60
    .byte '0', '.', '2', '5', '6', '8', $1B, $00, $00, '+', '3', '-', '*', '9', $00, $00 ; $70
rbaShift:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $09, '~', $00 ; $00
    .byte $00, $00, $00, $00, $00, 'Q', '!', $00, $00, $00, 'Z', 'S', 'A', 'W', '@', $00 ; $10
    .byte $00, 'C', 'X', 'D', 'E', '$', '#', $00, $00, $20, 'V', 'F', 'T', 'R', '%', $00 ; $20
    .byte $00, 'N', 'B', 'H', 'G', 'Y', '^', $00, $00, $00, 'M', 'J', 'U', '&', '*', $00 ; $30
    .byte $00, '<', 'K', 'I', 'O', ')', '(', $00, $00, '>', '?', 'L', ':', 'P', '_', $00 ; $40
    .byte $00, $00, '"', $00, '{', '+', $00, $00, $00, $00, $0D, '}', $00, '|', $00, $00 ; $50
    .byte $00, $00, $00, $00, $00, $00, $08, $00, $00, '1', $00, '4', '7', $00, $00, $00 ; $60
    .byte '0', '.', '2', '5', '6', '8', $1B, $00, $00, '+', '3', '-', '*', '9', $00, $00 ; $70

rbaModCode: .byte $12, $59, $14, $11, CAPS_CODE
rbaModMask: .byte MOD_LSHIFT, MOD_RSHIFT, MOD_LCTRL, MOD_LALT, MOD_CAPS
MODS = * - rbaModMask
rbaExtModCode: .byte $14, $11
rbaExtModMask: .byte MOD_RCTRL, MOD_RALT
EXT_MODS = * - rbaExtModMask

; after $E0: up, down, right, left, home, end, page up, page down, insert, delete as ESC [ x (then ~ from VT_TILDE on),
; then the keypad's / and Enter; $E0 $12 / $E0 $59, the fake shifts round some of these, are left out
rbaExtCode: .byte $75, $72, $74, $6B, $6C, $69, $7D, $7A, $70, $71, $4A, $5A
rbaExtOut:  .byte 'A', 'B', 'C', 'D', 'H', 'F', '5', '6', '2', '3', '/', $0D
EXTS = * - rbaExtOut
VT_TILDE = 6
VT_N     = 10

.segment "CODE"

; free the keyboard for a short window, take what it sends, inhibit it again, then decode
; changes: A, X, Y
.proc ps2
    lda #RELEASE
    sta PORT
    lda #0
    sta wbCount
    ldx #START_PASSES
next:
    jsr wait_low
    bcs done
    jsr read_byte
    bcs done
    ldx wbCount
    sta wbaRaw, x
    inx
    stx wbCount
    cpx #BYTES_MAX
    beq done
    ldx #GAP_PASSES
    bne next
done:
    ; mid-frame this makes the keyboard abort the byte and send it again later
    lda #INHIBIT
    sta PORT

    ldy #0
decode_next:
    cpy wbCount
    beq decoded
    lda wbaRaw, y
    jsr decode
    iny
    bne decode_next
decoded:
    rts
.endproc


; up to X passes for CLK low: C = 0 once it is, 1 on timeout; changes A, X
.proc wait_low
:   lda PORT
    and #CLK
    bne low
    dex
    bne :-
    sec
    rts
low:
    clc
    rts
.endproc


; up to X passes for CLK high: C = 0 once it is, 1 on timeout; changes A, X
.proc wait_high
:   lda PORT
    and #CLK
    beq high
    dex
    bne :-
    sec
    rts
high:
    clc
    rts
.endproc


; one 11-bit frame, its start bit's falling edge just seen: start 0, 8 data bits LSB first, odd parity, stop 1;
; A = the byte, C = 1 on a framing, parity or timing error; changes A, X, Y
.proc read_byte
    lda PORT
    and #DATA
    beq bad ; the start bit is a low DATA
    lda #0
    sta wbOnes
    ldy #9 ; 8 data bits, then parity, counted but not kept
next_bit:
    ldx #BIT_PASSES
    jsr wait_high
    bcs bad
    ldx #BIT_PASSES
    jsr wait_low
    bcs bad
    lda PORT
    and #DATA
    cmp #1 ; C = 1 for a low DATA, so wbByte fills inverted
    bcs :+
    inc wbOnes
:   dey ; keeps C for the ror
    beq stop
    ror wbByte
    jmp next_bit

stop:
    ldx #BIT_PASSES
    jsr wait_high
    bcs bad
    ldx #BIT_PASSES
    jsr wait_low
    bcs bad
    lda PORT
    and #DATA
    bne bad ; the stop bit is a high DATA
    ldx #BIT_PASSES
    jsr wait_high ; the keyboard lets CLK go after the stop bit
    bcs bad
    lda wbOnes
    lsr
    bcc bad
    lda wbByte
    eor #$ff
    clc
    rts
bad:
    sec
    rts
.endproc


; scancode byte A into the modifiers or the key buffer; keeps Y
.proc decode
    cmp #$F0
    bne :+
    lda #BREAK
    bne prefix
:   cmp #$E0
    bne :+
    lda #EXT
prefix:
    ora wbPre
    sta wbPre
    rts
:   tax
    lda wbPre
    sta wbFlags
    lda #0
    sta wbPre
    cpx #$80
    bcs done ; $AA after self-test, $E1 of Pause, $FA, error codes

    jsr modifier
    cmp #0
    bne set_mod
    bit wbFlags
    bmi done ; a released key
    bvs extended
    jmp plain
done:
    rts

set_mod:
    cmp #MOD_CAPS
    beq caps
    bit wbFlags
    bmi release
    ora wbMods
    sta wbMods
    rts
release:
    eor #$ff
    and wbMods
    sta wbMods
    rts
caps:
    bit wbFlags
    bmi caps_up
    lda wbMods
    and #MOD_CAPS_HELD
    bne done
    lda wbMods
    eor #MOD_CAPS
    ora #MOD_CAPS_HELD
    sta wbMods
    rts
caps_up:
    lda wbMods
    and #<~MOD_CAPS_HELD
    sta wbMods
    rts

extended:
    txa
    ldx #EXTS - 1
:   cmp rbaExtCode, x
    beq ext_found
    dex
    bpl :-
    rts
ext_found:
    cpx #VT_N
    bcc vt
    lda rbaExtOut, x
    jmp emit
vt:
    lda #$1b
    jsr put
    lda #'['
    jsr put
    lda rbaExtOut, x
    jsr put
    cpx #VT_TILDE
    bcc :+
    lda #'~'
    jsr put
:   rts
.endproc


; A = make code X's modifier mask under wbFlags' EXT, 0 for a key that isn't one; keeps X, Y
.proc modifier
    txa
    bit wbFlags
    bvs ext
    stx wbShift
    ldx #MODS - 1
:   cmp rbaModCode, x
    beq found
    dex
    bpl :-
    bmi none
found:
    lda rbaModMask, x
    ldx wbShift
    rts
ext:
    stx wbShift
    ldx #EXT_MODS - 1
:   cmp rbaExtModCode, x
    beq ext_found
    dex
    bpl :-
none:
    ldx wbShift
    lda #0
    rts
ext_found:
    lda rbaExtModMask, x
    ldx wbShift
    rts
.endproc


; plain make code X through shift and caps lock to ASCII; keeps Y
.proc plain
    lda #0
    sta wbShift
    lda wbMods
    and #MOD_SHIFT
    beq :+
    inc wbShift
:   lda rbaPlain, x
    beq done
    cmp #'a'
    bcc pick
    cmp #'z' + 1
    bcs pick
    bit wbMods
    bpl pick
    lda wbShift
    eor #1
    sta wbShift
pick:
    lda wbShift
    beq :+
    lda rbaShift, x
    jmp emit
:   lda rbaPlain, x
    jmp emit
done:
    rts
.endproc


; character A through ctrl (letters and @-_ to 1-31, as usbadapter's keymap) and alt (an ESC first); keeps X, Y
.proc emit
    pha
    lda wbMods
    and #MOD_CTRL
    beq no_ctrl
    pla
    cmp #'A'
    bcc no_ctrl_pha
    cmp #'_' + 1
    bcc ctrl
    cmp #'a'
    bcc no_ctrl_pha
    cmp #'z' + 1
    bcs no_ctrl_pha
ctrl:
    and #$1f
no_ctrl_pha:
    pha
no_ctrl:
    lda wbMods
    and #MOD_ALT
    beq :+
    lda #$1b
    jsr put
:   pla
    ; [fall_through]
.endproc

; A into the key buffer; keeps X, Y
.proc put
    sta wbShift
    txa
    pha
    lda wbShift
    jsr Keyboard::put_key
    pla
    tax
    rts
.endproc
