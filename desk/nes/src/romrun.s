; The K_ROM* calls, a program asking Desk to run a ROM and open it again after; the K_SAVER* calls answer that there
; are no screensavers.

.include "desk.inc"
.include "edio.inc"
.include "fs.inc"
.include "saver.inc"
.include "launch.inc"

RUN_ROM = 1 ; wbRunReq's

.segment "BSS"

wbRunReq:  .res 1 ; RUN_ROM, asked by the program, until the launch
wbRunArg:  .res 1 ; its byte, for the program when it opens again
wbResume:  .res 1 ; K_RESUME's
wbRomLen:  .res 1
wpRomPic:  .res 2 ; rom_pic's

.segment "CODE"

; K_ROM_RUN: the ROM at the zero-terminated path A/X readied, run once this call returns; Y kept for K_RESUME
; > C set when Desk refuses it, A the error
.proc rom_run
    sty wbRunArg
    jsr rom_path_in
    sty wbRomLen
    jsr pointer_busy
    lda #<ROM_PATH
    ldx #>ROM_PATH
    ldy wbRomLen
    far rom_prep
    bne refused
    lda #RUN_ROM
    sta wbRunReq
    clc
    rts
refused:
    jsr pointer_idle
    sec
    rts
.endproc


; K_RESUME: > A = the byte K_ROM_RUN kept when Desk opened the program again after it, else 0
.proc saver_resume
    lda wbResume
    rts
.endproc


; K_ROMS: the ROMs' file names in the zero-terminated folder A/X into the buffer at K_X/K_Y, RN_LEN bytes each,
; zero-padded, up to Y of them in the card's order; a name RN_LEN long or longer left off
; > A = how many
.proc rom_list
    sty wbScanCap
    jsr rom_path_in
    pha
    lda zbGx
    sta zpScanTo
    lda zbGy
    sta zpScanTo + 1
    lda #<rom_keep
    sta wpScanHook
    lda #>rom_keep
    sta wpScanHook + 1
    lda #RN_LEN
    sta wbScanSlot
    sta wbScanMax
    pla
    jsr sd_release
    jmp dir_scan
.endproc

; dir_scan's hook for K_ROMS: > C set when the name in wbaBlkData, Y letters, is a ROM Desk launches; Y kept
.proc rom_keep
    sty wbRomLen
    lda #<wbaBlkData
    ldx #>wbaBlkData
    far is_nes
    ldy wbRomLen
    rts
.endproc


; K_ROM_PIC: the PICTURE_LEN bytes at A/X, a ROM's zero-terminated path at their start, replaced with its 32x32
; picture as the desktop keeps one (RSRC_PICTURE); C set when it has none
.proc rom_pic
    sta wpRomPic
    stx wpRomPic + 1
    jsr rom_path_in
    far rom_rsrc
    bne none
    jsr rsrc_picture
    bcs none
    sta zpEdSrc
    stx zpEdSrc + 1
    lda wpRomPic
    sta zpGs
    lda wpRomPic + 1
    sta zpGs + 1
    ldy #0
:   lda (zpEdSrc), y
    sta (zpGs), y
    iny
    bne :-
    inc zpEdSrc + 1
    inc zpGs + 1
:   lda (zpEdSrc), y
    sta (zpGs), y
    iny
    cpy #<PICTURE_LEN
    bne :-
    .assert >PICTURE_LEN = 1, error, "rom_pic copies a picture as a page and the rest"
    clc
    rts
none:
    sec
    rts
.endproc


; the zero-terminated path at A/X, up to 255 letters, into ROM_PATH, the MCU's handle released first
; > A/X = ROM_PATH, Y its length
.proc rom_path_in
    pha
    txa
    pha
    jsr sd_release
    pla
    sta zpGs + 1
    pla
    sta zpGs
    ldy #0
:   lda (zpGs), y
    sta ROM_PATH, y
    beq done
    iny
    cpy #$ff
    bne :-
done:
    lda #<ROM_PATH
    ldx #>ROM_PATH
    rts
.endproc


; K_SAVER: an empty record, no screensaver, into the SS_LEN bytes at A/X
.proc saver_get
    sta zpGs
    stx zpGs + 1
    lda #0
    ldy #SS_LEN - 1
:   sta (zpGs), y
    dey
    bpl :-
    rts
.endproc

; K_SAVERS: > A = 0, none
.proc saver_list
    lda #0
    rts
.endproc

; K_SAVER_SET and K_SAVER_RUN: nothing to show or run
.proc saver_set
    rts
.endproc

; K_SAVER_PIC, K_SAVER_OPTS, K_SAVER_CFG and K_SAVER_CFG_SET: > C set, none
.proc saver_none
    sec
    rts
.endproc


.segment "SHELL"

; K_ROM_RUN's ROM, the program kept in the state file to open again after it; back to it on failure
.proc run_request
    lda #0 ; the desktop under the program
    jsr state_save
    jsr launch_go
    jsr pointer_idle
    lda #0
    sta wbRunReq
    sta wbRunArg
    rts
.endproc
