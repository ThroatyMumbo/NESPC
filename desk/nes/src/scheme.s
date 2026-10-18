; The window colors: face, shadow and title, in place of BG_PALETTE's gray, dark gray and navy (colors.inc). The
; Display program changes them through K_COLORS_SET; fullscreen apps read the file.

.include "desk.inc"
.include "colors.inc"
.include "edio.inc"
.include "fs.inc"
.include "paths.inc"

MAGIC_LEN = SC_MAGIC_LEN

.segment "WRAM"

wbaScFile:  .res MAGIC_LEN ; nespc/system/colors: the magic, then the colors shown
wbaScheme:  .res SC_LEN
wbaScSaved: .res SC_LEN ; the colors as the card has them

.segment "RODATA"

rsScFile:  .byte NESPC_COLORS
SC_FILE_LEN = * - rsScFile
rsScMagic: .byte SC_MAGIC
rbaScDefault: .byte SC_DEFAULT
rbaScRec:  REC_FILE rsScFile, SC_FILE_LEN, wbaScFile, MAGIC_LEN + SC_LEN

.segment "CODE"

; the colors from the card, else BG_PALETTE's; before backdrop_init, whose palettes take them
.proc scheme_init
    lda #FA_READ
    ldx #<rbaScRec
    ldy #>rbaScRec
    jsr rec_file
    bne default
    ldx #MAGIC_LEN - 1
:   lda wbaScFile, x
    cmp rsScMagic, x
    bne default
    dex
    bpl :-
    ldx #SC_LEN - 1
:   lda wbaScheme, x
    jsr color_legal
    sta wbaScheme, x
    dex
    bpl :-
    bmi saved
default:
    ldx #SC_LEN - 1
:   lda rbaScDefault, x
    sta wbaScheme, x
    dex
    bpl :-
saved:
    ; [fall_through]
.endproc

.proc sc_saved
    ldx #SC_LEN - 1
:   lda wbaScheme, x
    sta wbaScSaved, x
    dex
    bpl :-
    rts
.endproc


; the colors the card has, into the palettes by the caller's bd_pal
.proc scheme_revert
    ldx #SC_LEN - 1
:   lda wbaScSaved, x
    sta wbaScheme, x
    dex
    bpl :-
    rts
.endproc


; K_COLORS: the colors shown into the SC_LEN bytes at A/X
.proc scheme_get
    sta zpGs
    stx zpGs + 1
    ldy #SC_LEN - 1
:   lda wbaScheme, y
    sta (zpGs), y
    dey
    bpl :-
    rts
.endproc


; K_COLORS_SET: the colors at A/X shown in the program's palettes; kept on the card with C set
.proc scheme_set
    php
    jsr scheme_put
    jsr scheme_pal
    sec
    jsr pal_show
    jsr vq_flush
    plp
    bcc done
    jsr sc_saved
    ldx #MAGIC_LEN - 1
:   lda rsScMagic, x
    sta wbaScFile, x
    dex
    bpl :-
    lda #FA_WRITE | FA_CREATE_ALWAYS
    ldx #<rbaScRec
    ldy #>rbaScRec
    jmp rec_file
done:
    rts
.endproc


; the colors at A/X, made legal, as the ones shown; bd_pal or scheme_pal puts them in the palettes
.proc scheme_put
    sta zpGs
    stx zpGs + 1
    ldy #SC_LEN - 1
:   lda (zpGs), y
    jsr color_legal
    sta wbaScheme, y
    dey
    bpl :-
    rts
.endproc


; the colors into wbaDeskPal and the program's palettes; the body and title share their face, as the captions need
.proc scheme_pal
    lda wbaScheme + SC_FACE
    sta wbaDeskPal + PAL_BODY * 4 + C_GRAY
    sta wbaDeskPal + PAL_TITLE * 4 + C_GRAY
    sta wbaAppPal + PAL_BODY * 4 + C_GRAY
    sta wbaAppPal + PAL_TITLE * 4 + C_GRAY
    lda wbaScheme + SC_SHADOW
    sta wbaDeskPal + PAL_BODY * 4 + C_ACCENT
    sta wbaAppPal + PAL_BODY * 4 + C_ACCENT
    lda wbaScheme + SC_TITLE
    sta wbaDeskPal + PAL_TITLE * 4 + C_ACCENT
    sta wbaAppPal + PAL_TITLE * 4 + C_ACCENT
    rts
.endproc
