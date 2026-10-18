; Desk: reset, NMI, and the main loop, which takes host commands and hands the cart back to the menu when asked.

.include "desk.inc"
.include "edio.inc"
.include "fs.inc"

CTRL_VALUE = %10001000 ; NMI on, BG from $0000, sprites from $1000

.segment "ZEROPAGE"

zbFrame: .res 1

.segment "BSS"

wbBeat: .res 1

.segment "RODATA"

rbaPalette:
.byte BG_PALETTE
.byte SPR_PALETTE
rbaPaletteEnd:
.assert rbaPaletteEnd - rbaPalette = 32, error, "backdrop.s's wbaDeskPal"

; copied to MENU_STUB: the store hands the cart to the menu mapper, the jump takes its reset vector
rbaMenuStub:
.byte $8d, <MENU, >MENU, $6c, $fc, $ff
rbaMenuStubEnd:

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
    bit PPU_STATUS
vblank1:
    bit PPU_STATUS
    bpl vblank1

    txa
clear_ram:
    sta $000, x
    sta $100, x
    sta $200, x
    sta $300, x
    sta $400, x
    sta $500, x
    sta $600, x
    sta $700, x
    inx
    bne clear_ram

vblank2:
    bit PPU_STATUS
    bpl vblank2

    ldx #(rbaMenuStubEnd - rbaMenuStub - 1)
stub:
    lda rbaMenuStub, x
    sta MENU_STUB, x
    dex
    bpl stub

    jsr upload_sprites ; from bank 0, mapped at reset
    jsr shell_ram_clear
    jsr shell_bank

    jsr pointer_init
    jsr ed_flush
    jsr clock_init
    jsr scheme_init
    jsr backdrop_init ; the desktop's and window colors into wbaDeskPal

    lda #$3f
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR
    ldx #0
palette:
    lda wbaDeskPal, x
    sta PPU_DATA
    inx
    cpx #(rbaPaletteEnd - rbaPalette)
    bne palette
    jsr set_geometry
    jsr icons_reset
    lda #1 ; the desktop, the window closed until Files opens it
    sta zbIcon
    sta zbClosed

vblank3:
    bit PPU_STATUS
    bpl vblank3
    lda #CTRL_VALUE
    sta PPU_CTRL
    jsr redraw_screen ; still with rendering off
    lda zbFrame
vblank4:
    cmp zbFrame
    beq vblank4
    lda #MASK_VALUE
    sta PPU_MASK
    ; [fall_through]
.endproc

.proc main
    lda zbFrame
wait:
    bit MENU
    bmi menu_exit
    bit FIFO_STAT
    bpl host
    cmp zbFrame
    beq wait

    jsr pointer_update
    jsr browser_update ; the boot, the first time
    jsr clock_update
    inc wbBeat
    lda wbBeat
    sta DESK_BEAT
    jmp main
host:
    jsr host_poll
    jmp main
.endproc


; hand the cart to the menu mapper and its reset vector: the OS, which boots Desk again
.proc menu_exit
    jsr sd_release ; nothing left open for the menu
    sei
    lda #0
    sta PPU_CTRL
    sta PPU_MASK
    sta APU_STATUS
    jmp MENU_STUB
.endproc


.proc nmi
    pha
    txa
    pha
    tya
    pha

    lda #0
    sta OAM_ADDR
    lda #>OAM
    sta OAM_DMA
    jsr vq_nmi

    bit PPU_STATUS
    lda #0
    sta PPU_SCROLL
    sta PPU_SCROLL
    lda #CTRL_VALUE
    sta PPU_CTRL

    inc zbFrame
    jsr jingle_tick
    pla
    tay
    pla
    tax
    pla
    rti
.endproc


.proc irq
    rti
.endproc


.segment "VECTORS"
.word nmi, reset, irq
