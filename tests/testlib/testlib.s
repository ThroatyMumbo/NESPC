; The mapper 773 test ROMs' reset, menu return and blitter text.

.include "desk.inc"
.include "testlib.inc"

FONT_ROW = 8 ; a glyph's 1bpp rows: plane 1 of its background.chr tile

.segment "ZEROPAGE"

zbFg:  .res 1
zbBig: .res 1 ; 1: 16x16 glyphs
zbT:   .res 1
zpS:   .res 2
zpF:   .res 2
zbPy:  .res 1

.segment "FONT"
rbaFont: .incbin "background.chr"
.assert (rbaFont & $0fff) = 0, error, "putc needs the font on a 4 KB boundary"

.segment "RODATA"

rbaMenuStub:
.byte $8d, <MENU, >MENU, $6c, $fc, $ff
rbaMenuStubEnd:

; a nibble's 4 bits, each doubled
rbaDouble:
.byte $00, $03, $0c, $0f, $30, $33, $3c, $3f, $c0, $c3, $cc, $cf, $f0, $f3, $fc, $ff

.segment "CODE"

.proc reset
    sei
    cld
    ldx #$40
    stx APU_FRAME
    ldx #$ff
    txs
    inx
    stx PPU_CTRL
    stx PPU_MASK
    stx APU_DMC
    stx DESK_BANK ; this image's lower half at $8000: the LOW segment
    bit PPU_STATUS
:   bit PPU_STATUS
    bpl :-
    txa
:   sta $000, x
    sta $400, x
    sta $500, x
    sta $600, x
    sta $700, x
    inx
    bne :-
:   bit PPU_STATUS
    bpl :-

    ldx #rbaMenuStubEnd - rbaMenuStub - 1
:   lda rbaMenuStub, x
    sta MENU_STUB, x
    dex
    bpl :-

    lda #$3f
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR
    ldx #0
:   lda rbaPalette, x
    sta PPU_DATA
    inx
    cpx #16
    bne :-

    jsr clear
    jmp start
.endproc

; at the next vblank: the picture and NMI on
.proc screen_on
:   bit PPU_STATUS
    bpl :-
    lda #0
    sta PPU_SCROLL
    sta PPU_SCROLL
    lda #CTRL_VALUE
    sta PPU_CTRL
    lda #MASK_BG
    sta PPU_MASK
    rts
.endproc

.proc to_menu
    sei
    lda #0
    sta PPU_CTRL
    sta PPU_MASK
    jmp MENU_STUB
.endproc

; the string at YX, from pixel zbT, A; 8x8 glyphs, or 16x16 when zbBig
.proc print
    stx zpS
    sty zpS + 1
    tay
    lda zbT
    jsr at
    ldy #0
:   lda (zpS), y
    beq done
    jsr putc
    iny
    bne :-
done:
    rts
.endproc

; A as two hex digits at the blitter's position; keeps Y, and X for 8x8
.proc puthex
    pha
    lsr
    lsr
    lsr
    lsr
    jsr digit
    pla
    and #$0f
digit:
    cmp #10
    bcc :+
    adc #'A' - '0' - 10 - 1
:   adc #'0'
    jmp putc
.endproc

; place the next glyph at pixel A, Y, zbFg on black
.proc at
:   bit GFX_OP
    bmi :-
    sta GFX_DX
    sty GFX_DY
    lda #8
    ldx zbBig
    beq :+
    lda #16
:   sta GFX_W
    sta GFX_H
    lda zbFg
    sta GFX_FG
    lda #C_BLACK
    sta GFX_BG
    lda #0
    sta GFX_FLAGS
    rts
.endproc

; glyph A at the blitter's position, which then moves right by one glyph; keeps Y, and X for 8x8
.proc putc
    sty zbPy
    ldy #0
    sty zpF + 1
    asl
    rol zpF + 1
    asl
    rol zpF + 1
    asl
    rol zpF + 1
    asl
    rol zpF + 1
    ora #FONT_ROW
    sta zpF
    lda zpF + 1
    ora #>rbaFont
    sta zpF + 1
:   bit GFX_OP
    bmi :-
    lda #OP_EXPAND
    sta GFX_OP
    lda zbBig
    bne big
    .repeat 8
    lda (zpF), y
    sta GFX_DATA
    iny
    .endrepeat
    ldy zbPy
    rts
big:
    lda (zpF), y
    lsr
    lsr
    lsr
    lsr
    tax
    lda rbaDouble, x
    sta GFX_DATA
    lda (zpF), y
    and #$0f
    tax
    lda rbaDouble, x
    sta GFX_DATA
    lda (zpF), y
    lsr
    lsr
    lsr
    lsr
    tax
    lda rbaDouble, x
    sta GFX_DATA
    lda (zpF), y
    and #$0f
    tax
    lda rbaDouble, x
    sta GFX_DATA
    iny
    cpy #8
    bne big
    ldy zbPy
    rts
.endproc

.proc clear
:   bit GFX_OP
    bmi :-
    lda #0
    sta GFX_DX
    sta GFX_DY
    sta GFX_W
    sta GFX_FG
    sta GFX_FLAGS
    sta GFX_CX0
    sta GFX_CY0
    sta GFX_CX1
    lda #240
    sta GFX_H
    sta GFX_CY1
    lda #OP_FILL
    sta GFX_OP
:   bit GFX_OP
    bmi :-
    lda #OP_PAL
    sta GFX_OP
    rts
.endproc

.proc irq
    rti
.endproc

.segment "VECTORS"
.word nmi, reset, irq
