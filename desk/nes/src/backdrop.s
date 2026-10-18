; The desktop's background: a color, with an 8x8 pattern in black over it unless the pattern's rows are all 0. Kept in
; nespc/system/desktop; the Display program (apps/display) changes it through K_DESKTOP_SET.

.include "desk.inc"
.include "edio.inc"
.include "fs.inc"
.include "paths.inc"

BD_TEAL   = $1c
MAGIC_LEN = 4

.segment "WRAM"

wbaBdFile:   .res MAGIC_LEN ; nespc/system/desktop: the magic, then the record shown
wbaBackdrop: .res BD_LEN
wbaBdSaved:  .res BD_LEN ; the record as the card has it
wbaDeskPal:  .res 32 ; rbaPalette with the desktop's color where the teal was
wbBdNew:     .res 1 ; backdrop_set's: a pattern row changed

.segment "RODATA"

rsBdFile:  .byte NESPC_SYSTEM, "desktop"
BD_FILE_LEN = * - rsBdFile
rsBdMagic: .byte "DBG1"
rbaBdRec:  REC_FILE rsBdFile, BD_FILE_LEN, wbaBdFile, MAGIC_LEN + BD_LEN

.segment "CODE"

; the record from the card, else teal with no pattern; wbaDeskPal with its color
.proc backdrop_init
    lda #FA_READ
    ldx #<rbaBdRec
    ldy #>rbaBdRec
    jsr rec_file
    bne teal
    ldx #MAGIC_LEN - 1
:   lda wbaBdFile, x
    cmp rsBdMagic, x
    bne teal
    dex
    bpl :-
    bmi keep
teal:
    lda #BD_TEAL
    sta wbaBackdrop
    ldx #BD_LEN - 1
    lda #0
:   sta wbaBackdrop, x
    dex
    bne :-
keep:
    jsr bd_pal
    ; [fall_through]
.endproc

.proc bd_saved
    ldx #BD_LEN - 1
:   lda wbaBackdrop, x
    sta wbaBdSaved, x
    dex
    bpl :-
    rts
.endproc


; the record and window colors the card has, shown again once the caller redraws; for a program that ends without
; keeping its choice
.proc backdrop_revert
    jsr scheme_revert
    lda #0
    sta wbResume
    ldx #BD_LEN - 1
:   lda wbaBdSaved, x
    sta wbaBackdrop, x
    dex
    bpl :-
    jmp bd_pal
.endproc


; the record at A/X in wbaDeskPal and the program's palettes, before anything is drawn with it
.proc backdrop_put
    sta zpGs
    stx zpGs + 1
    ldy #BD_LEN - 1
:   lda (zpGs), y
    sta wbaBackdrop, y
    dey
    bpl :-
    jmp bd_pal
.endproc


; K_DESKTOP: the record shown into the BD_LEN bytes at A/X
.proc backdrop_get
    sta zpGs
    stx zpGs + 1
    ldy #BD_LEN - 1
:   lda wbaBackdrop, y
    sta (zpGs), y
    dey
    bpl :-
    rts
.endproc


; K_DESKTOP_SET: the record at A/X shown, a changed pattern painted round the window; kept on the card with C set
.proc backdrop_set
    php
    sta zpGs
    stx zpGs + 1
    lda #0
    sta wbBdNew
    ldy #BD_LEN - 1
rows:
    lda (zpGs), y
    cmp wbaBackdrop, y
    beq :+
    sta wbaBackdrop, y
    sty wbBdNew
:   dey
    bne rows
    lda (zpGs), y
    sta wbaBackdrop
    jsr bd_pal
    lda wbaBackdrop
    sta wbaRow
    lda #PAL_DESK * 4 + C_DESK
    jsr vq_pal
    ldy #1
    jsr vq_row
    lda #PAL_ICON * 4 + C_DESK
    jsr vq_pal
    ldy #1
    jsr vq_row
    jsr vq_flush
    lda wbBdNew
    beq keep
    jsr bd_around
keep:
    plp
    bcc done
    jsr bd_saved
    ldx #MAGIC_LEN - 1
:   lda rsBdMagic, x
    sta wbaBdFile, x
    dex
    bpl :-
    lda #FA_WRITE | FA_CREATE_ALWAYS
    ldx #<rbaBdRec
    ldy #>rbaBdRec
    jmp rec_file
done:
    rts
.endproc


; the background over the rect zbGx-zbGh, which it keeps
.proc backdrop_fill
    lda #PAL_DESK
    jsr gfx_pal
    ldx #BD_LEN - 1
:   lda wbaBackdrop, x
    bne pattern
    dex
    bne :-
    lda #C_DESK
    jmp gfx_rect
pattern:
    lda #<(wbaBackdrop + 1)
    sta zpGs
    lda #>(wbaBackdrop + 1)
    sta zpGs + 1
    lda #C_BLACK
    sta zbGc
    lda #C_DESK
    sta zbGb
    jmp gfx_pattern
.endproc


; the background round the window: above it, below it, then either side
.proc bd_around
    lda #0
    sta zbGx
    sta zbGy
    sta zbGw
    lda zbWinY
    beq below
    sta zbGh
    jsr backdrop_fill
below:
    lda zbWinY
    clc
    adc zbWinH
    cmp #SCREEN_H
    bcs sides
    sta zbGy
    eor #$ff
    sec
    adc #SCREEN_H
    sta zbGh
    jsr backdrop_fill
sides:
    lda zbWinY
    sta zbGy
    lda zbWinH
    sta zbGh
    lda zbWinX
    beq right
    jsr win_x0
    sta zbGw
    lda #0
    sta zbGx
    jsr backdrop_fill
right:
    jsr win_x1
    beq done
    sta zbGx
    eor #$ff
    clc
    adc #1
    sta zbGw
    jmp backdrop_fill
done:
    rts
.endproc


; wbaDeskPal and a program's palettes with the record's color, made a legal one
.proc bd_pal
    lda wbaBackdrop
    jsr color_legal
    sta wbaBackdrop
    ldx #31
:   lda rbaPalette, x
    sta wbaDeskPal, x
    dex
    bpl :-
    lda wbaBackdrop
    sta wbaDeskPal + PAL_DESK * 4 + C_DESK
    sta wbaDeskPal + PAL_ICON * 4 + C_DESK ; the teal of see-through spans beside navy
    sta wbaAppPal + PAL_DESK * 4 + C_DESK
    sta wbaAppPal + PAL_ICON * 4 + C_DESK
    jmp scheme_pal
.endproc


; A made a color the PPU shows as it should, X and Y kept
.proc color_legal
    and #$3f
    cmp #$0d ; blacker than black
    beq black
    pha
    and #$0f
    cmp #$0e
    pla
    bcc done
black:
    lda #$0f
done:
    rts
.endproc
