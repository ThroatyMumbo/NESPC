; Copies the 4 KiB sprite table (tools/mkchr.py) into CHR RAM at $1000. Rendering must be off, and bank 0 mapped.

.include "desk.inc"

.segment "ZEROPAGE"

zpSrc: .res 2

.segment "LOWDATA"

rbaChr:
.incbin "desk.chr"

.segment "CODE"

.proc upload_sprites
    lda #<rbaChr
    sta zpSrc
    lda #>rbaChr
    sta zpSrc + 1
    bit PPU_STATUS
    lda #$10
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR
    ldx #$10 ; pages
    ldy #0
copy:
    lda (zpSrc), y
    sta PPU_DATA
    iny
    bne copy
    inc zpSrc + 1
    dex
    bne copy
    rts
.endproc
