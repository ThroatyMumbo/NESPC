; The system's sprite icons' palettes, as tools/mkchr.py built them with their tiles.

.include "desk.inc"

.segment "BSS"

wbaSysPal:  .res T_ROM16 + 4 - T_EXE16 ; tile palettes of the system's sprite icons, as rbaSysPal
wbaExePal  = wbaSysPal
wbaFolderPal = wbaSysPal + T_FOLDER16 - T_EXE16
wbaRomPal  = wbaSysPal + T_ROM16 - T_EXE16

.segment "RODATA"

rbaSysPal: ; tools/mkchr.py's, in tile order from T_EXE16
.incbin "exe_16.pal"
.res T_FOLDER16 - T_EXE16 - 4 ; tiles $84-$97 aren't system icons
.incbin "folder_16.pal"
.incbin "rom_16.pal"
rbaSysPalEnd:
.assert rbaSysPalEnd - rbaSysPal = T_ROM16 + 4 - T_EXE16, error, "rbaSysPal is not T_EXE16 on"

.segment "SHELL"

; the built-in sprite icons' palettes, as their tiles are at reset
.proc icons_reset
    ldx #rbaSysPalEnd - rbaSysPal - 1
:   lda rbaSysPal, x
    sta wbaSysPal, x
    dex
    bpl :-
    rts
.endproc
