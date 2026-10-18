; Sprite pattern and palette writes queued by the main loop and copied by the NMI, so they land with rendering on.

.include "desk.inc"

VQ_MAX = 96 ; bytes the NMI copies after OAM DMA within vblank: 5 sprite tiles

.segment "ZEROPAGE"

zbVqLen:   .res 1
zbVqReady: .res 1 ; set by vq_flush, cleared by the NMI once the queue is on screen
zbVqN:     .res 1
zpVqAddr:  .res 2 ; high, low

.segment "WRAM"

wbaVq:  .res VQ_MAX
wbaRow: .res 32

.segment "CODE"

; A = tile of the sprite pattern table, whose 16 bytes the next vq_row replaces
.proc vq_spr
    jsr vq_chr
    lda zpVqAddr
    ora #$10
    sta zpVqAddr
    rts
.endproc


; A = tile of the background pattern table ($0xxx); vq_spr is the sprite half
.proc vq_chr
    pha
    lsr
    lsr
    lsr
    lsr
    sta zpVqAddr
    pla
    asl
    asl
    asl
    asl
    sta zpVqAddr + 1
    rts
.endproc


; A = first palette entry the next vq_row replaces
.proc vq_pal
    sta zpVqAddr + 1
    lda #$3f
    sta zpVqAddr
    rts
.endproc


; queue Y (1-32) bytes from wbaRow at the vq_spr or vq_pal address
; changes: A, X, Y
.proc vq_row
    sty zbVqN
    tya
    clc
    adc #3
    adc zbVqLen
    cmp #VQ_MAX + 1
    bcc room
    jsr vq_flush
room:
    ldx zbVqLen
    lda zpVqAddr
    sta wbaVq, x
    lda zpVqAddr + 1
    sta wbaVq + 1, x
    lda zbVqN
    sta wbaVq + 2, x
    inx
    inx
    inx
    ldy #0
copy:
    lda wbaRow, y
    sta wbaVq, x
    inx
    iny
    cpy zbVqN
    bne copy
    stx zbVqLen
    rts
.endproc


; hand the queue to the NMI and wait until it is done
.proc vq_flush
    lda zbVqLen
    beq done
    lda #1
    sta zbVqReady
wait:
    lda zbVqReady
    bne wait
done:
    rts
.endproc


; called from the NMI in vblank
; changes: A, X, Y
.proc vq_nmi
    lda zbVqReady
    beq done
    ldx zbVqLen
    beq empty
    bit PPU_STATUS
    ldx #0
entry:
    lda wbaVq, x
    sta PPU_ADDR
    lda wbaVq + 1, x
    sta PPU_ADDR
    ldy wbaVq + 2, x
    inx
    inx
    inx
copy:
    lda wbaVq, x
    sta PPU_DATA
    inx
    dey
    bne copy
    cpx zbVqLen
    bne entry
empty:
    lda #0
    sta zbVqLen
    sta zbVqReady
done:
    rts
.endproc
