; Launch an iNES ROM from the SD card: checked and scripted from here, played by a RAM stub (as krikzz edio's ed_start_app).

.include "desk.inc"
.include "fs.inc"
.include "edio.inc"
.include "launch.inc"

.import __STUB_LOAD__, __STUB_RUN__, __STUB_SIZE__
.assert __STUB_SIZE__ <= 256, error, "the stub copy loop counts in X"

SCRIPT = $0400 ; to $07FF, over the BSS: records of [count] [count bytes for the FIFO] [op] [arg]
SCRIPT_END = $0800 ; launch_prep's dry run refuses a script past here
REC_MAX = 253 ; the stub's Y reaches count + 2
DRY_COUNT = $80 ; put and rec_end count bytes without storing them
DRY_LONG = $40 ; a record over REC_MAX
SAVE_BUF = wbaBlkData ; the .srm path, built in launch_prep's scratch
ROM_SAVE_MAX = 230 ; longest battery ROM path: its .srm path fits one stub record (boottest.py)

CFG_SIZE = 42 ; 32 cheat bytes, then the mapper configuration (the EDN8 base's sys_cfg.sv)
SRM_MSK  = 6  ; 128 << 6 = 8 KiB of PRG RAM unless a NES 2.0 header says otherwise
VOLUME   = $2c ; what the stock menu writes for this cart (mem_rd 0x1800023)

; mapper configuration, at rdCfg + 32 = ADDR_SCFG
C_IDX  = 0 ; mapper bits 7-0
C_PRG  = 1 ; PRG mask, SRM mask << 4
C_CHR  = 2 ; CHR mask, mapper bits 11-8 << 4
C_VOL  = 3
C_MAP  = 4 ; mirroring, CHR RAM, submapper << 4
C_CTRL = 7
CFG_LEN = 10
MAP_CTRL_UNLOCK = $80

.segment "WRAM"

wbaHdr:     .res 16
wbaCore:    .res 256 ; MCU path of the .rbf
wbCoreLen:  .res 1
wdCoreSize: .res 4
wdPrg:      .res 4
wdChr:      .res 4
wdOff:      .res 4 ; PRG's offset in the file
wdLen:      .res 4
wdSrmLen:   .res 4 ; 128 << SRM mask
wbSrm:      .res 1 ; SRM mask
wbaCfg:     .res CFG_LEN
wwRom:      .res 2
wbRomLen:   .res 1
wwMap:      .res 2
wwV:        .res 2
wpRec:      .res 2
wbN:        .res 1
wbArg:      .res 1
wbPack:     .res 1
wbOpenMode: .res 1 ; put_open_as's
wbBattery:  .res 1 ; header byte 6 bit 1: the game keeps its SRM
wdSaveLoad: .res 4 ; bytes of its .srm to load, 0 for none yet
wbSaveDir:  .res 1 ; SAVE_BUF up to the game's folder
wbSaveLen:  .res 1 ; all of it
wbDry:      .res 1 ; DRY_*: script_fits' dry run
wwGuest:    .res 2 ; launch_guest's file, CHR and save name in place of the ROM's
wbGuestLen: .res 1 ; 0 for none
wbGuestBatt: .res 1 ; the guest's battery flag over the header's
wbGuestSrm: .res 1 ; its SRM mask, when it has a battery
wbNameLen:  .res 1 ; save_name's

.segment "RODATA"

rsGamedata: .byte "EDN8/gamedata" ; the stock menu's: gamedata/<ROM name>/bram.srm
GAMEDATA_LEN = * - rsGamedata
rsBram:    .byte "/bram.srm"
BRAM_LEN = * - rsBram
rsSaveMagic: .byte "DSRM"
.assert * - rsSaveMagic = SAVE_MAGIC_LEN, error, "launch.inc's SAVE_MAGIC_LEN"
rdSaveRec: .dword SAVE_PSRAM
rsMagic:   .byte "NES", $1a
rsMaprout: .byte "EDN8/syscore/maprout.bin"
MAPROUT_LEN = * - rsMaprout
rsMaps:    .byte "EDN8/MAPS/000.RBF" ; core number in decimal at MAPS_NUM
MAPS_LEN = * - rsMaps
MAPS_NUM = 10
rdZero:    .dword 0
rdChr:     .dword $800000
rdSrm:     .dword $1000000
rdCfg:     .dword $1800000
rdCfgLen:  .dword CFG_SIZE

.segment "SHELL"

; check ROM A/X (low/high), Y its length, an MCU path, and find its core; launch_go then starts it.
; The path stays in place until launch_go; wbaBlkData is scratch (Desk: sd_release first).
; > A = status, Z set on success; wwMap = the mapper
.proc launch_prep
    pha
    lda #0
    sta wbGuestLen
    pla
    ; [fall_through]
.endproc

; as launch_prep, with the guest in wwGuest, wbGuestLen, wbGuestBatt and wbGuestSrm, kept in place as well
.proc launch_guest
    sta wwRom
    stx wwRom + 1
    sty wbRomLen
    jsr read_header
    bne done
    jsr parse_header
    bne done
    jsr guest_chr
    bne done
    jsr find_core
    bne done
    jsr save_prep
    bne done
    jmp script_fits
done:
    rts
.endproc


; dry-run launch_script's records from SCRIPT
; > A = status, Z set when they end by SCRIPT_END, each within REC_MAX
.proc script_fits
    lda #DRY_COUNT
    sta wbDry
    lda #<SCRIPT
    sta zpEdBuf
    lda #>SCRIPT
    sta zpEdBuf + 1
    jsr script_records
    lda wbDry
    ldx #0
    stx wbDry
    and #DRY_LONG
    bne long
    lda #<SCRIPT_END
    cmp zpEdBuf
    lda #>SCRIPT_END
    sbc zpEdBuf + 1
    bcc long
    lda #0
    rts
long:
    lda #FS_E_LONG
    rts
.endproc


; > C set when A/X (low/high), Y its length, ends in ".nes", any case
.proc is_nes
    sta zpEdSrc
    stx zpEdSrc + 1
    cpy #4
    bcc no
    dey
    lda (zpEdSrc), y
    ora #$20
    cmp #'s'
    bne no
    dey
    lda (zpEdSrc), y
    ora #$20
    cmp #'e'
    bne no
    dey
    lda (zpEdSrc), y
    ora #$20
    cmp #'n'
    bne no
    dey
    lda (zpEdSrc), y
    cmp #'.'
    bne no
    sec
    rts
no:
    clc
    rts
.endproc


; > A = status, Z set on success
.proc read_header
    lda #FA_READ
    sta zbEdMode
    lda wwRom
    ldx wwRom + 1
    ldy wbRomLen
    jsr ed_fopen
    bne done
    lda #<wbaHdr
    sta zpEdBuf
    lda #>wbaHdr
    sta zpEdBuf + 1
    lda #16
    sta zwEdArg
    lda #0
    sta zwEdArg + 1
    jsr ed_fread
    pha
    jsr ed_fclose
    pla
done:
    rts
.endproc


; wbaHdr into sizes, the PRG offset and wbaCfg
; > A = status, Z set on success
.proc parse_header
    ldx #3
:   lda wbaHdr, x
    cmp rsMagic, x
    beq :+
    jmp bad
:   dex
    bpl :--
    lda #SRM_MSK
    sta wbSrm
    lda wbaHdr + 7
    and #$0c
    cmp #$08 ; NES 2.0
    bne ines
    ; PRG RAM and NVRAM are 64 << shift; the larger, as 128 << (shift - 1)
    lda wbaHdr + 10
    and #$0f
    sta wbN
    lda wbaHdr + 10
    lsr
    lsr
    lsr
    lsr
    cmp wbN
    bcs :+
    lda wbN
:   tax
    beq sizes
    dex
    cpx #12 ; past the 256 KiB SRM
    bcs bad
    stx wbSrm
    jmp sizes
ines:
    ; iNES: a tag in bytes 12-15 (DiskDude!) overwrote byte 7
    lda wbaHdr + 12
    ora wbaHdr + 13
    ora wbaHdr + 14
    ora wbaHdr + 15
    beq :+
    lda #0
    sta wbaHdr + 7
:   lda #0
    sta wbaHdr + 8
    sta wbaHdr + 9
sizes:
    ; PRG = 16 KiB units << 14, byte 9's low nibble above byte 4 ($F is the exponent form)
    lda wbaHdr + 9
    and #$0f
    cmp #$0f
    beq bad
    sta wdPrg + 3
    lda wbaHdr + 4
    sta wdPrg + 2
    ora wdPrg + 3
    beq bad
    lda wbaHdr + 9
    lsr
    lsr
    lsr
    lsr
    cmp #$0f
    beq bad
    sta wdChr + 3
    lda wbaHdr + 5
    sta wdChr + 2
    lda #0
    sta wdPrg + 1
    sta wdPrg
    sta wdChr + 1
    sta wdChr
    ldx #3
:   lsr wdChr + 3
    ror wdChr + 2
    ror wdChr + 1
    cpx #1
    beq :+
    lsr wdPrg + 3
    ror wdPrg + 2
    ror wdPrg + 1
:   dex
    bne :--
    jmp config
bad:
    lda #FS_E_NOTROM
    rts

config:
    lda wbaHdr + 6
    and #$02
    sta wbBattery
    lda wbaHdr + 6
    lsr
    lsr
    lsr
    lsr
    sta wwMap
    lda wbaHdr + 7
    and #$f0
    ora wwMap
    sta wwMap
    sta wbaCfg + C_IDX
    lda wbaHdr + 8
    and #$0f
    sta wwMap + 1

    ; PRG mask over 8 KiB units: twice the 16 KiB count
    lda wbaHdr + 4
    asl
    tay
    lda wbaHdr + 9
    and #$0f
    rol
    tax
    tya
    jsr mask_of
    sta wbaCfg + C_PRG
    lda wbSrm
    jsr srm_set
    lda wbaHdr + 9
    lsr
    lsr
    lsr
    lsr
    tax
    lda wbaHdr + 5
    jsr mask_of
    sta wbaCfg + C_CHR
    lda wwMap + 1
    asl
    asl
    asl
    asl
    ora wbaCfg + C_CHR
    sta wbaCfg + C_CHR

    ; map_cfg: mirroring, CHR RAM when there is no CHR, submapper
    lda wbaHdr + 6
    and #$08
    beq :+
    lda #2 ; four-screen
    bne mirror
:   lda wbaHdr + 6
    and #$01 ; vertical
mirror:
    sta wbaCfg + C_MAP
    lda wbaHdr + 5
    ora wdChr + 3
    bne :+
    lda wbaCfg + C_MAP
    ora #$04
    sta wbaCfg + C_MAP
:   lda wbaHdr + 8
    and #$f0
    ora wbaCfg + C_MAP
    sta wbaCfg + C_MAP

    lda #VOLUME
    sta wbaCfg + C_VOL
    lda #MAP_CTRL_UNLOCK
    sta wbaCfg + C_CTRL
    lda #0
    sta wbaCfg + 5
    sta wbaCfg + 6
    sta wbaCfg + 8
    sta wbaCfg + 9

    ; PRG follows the header, and the trainer when there is one
    lda #16
    sta wdOff
    lda #0
    sta wdOff + 2
    sta wdOff + 3
    lda wbaHdr + 6
    and #$04
    lsr
    sta wdOff + 1
    lda #0
    rts
.endproc


; SRM mask A into wbSrm, wdSrmLen and C_PRG's high nibble
.proc srm_set
    sta wbSrm
    asl
    asl
    asl
    asl
    sta wbN
    lda wbaCfg + C_PRG
    and #$0f
    ora wbN
    sta wbaCfg + C_PRG
    lda #128
    sta wdSrmLen
    lda #0
    sta wdSrmLen + 1
    sta wdSrmLen + 2
    sta wdSrmLen + 3
    ldx wbSrm
    beq done
:   asl wdSrmLen
    rol wdSrmLen + 1
    rol wdSrmLen + 2
    dex
    bne :-
done:
    rts
.endproc


; with a guest: its size for the CHR, its battery and SRM over the header's
; > A = status, Z set on success
.proc guest_chr
    lda wbGuestLen
    beq done
    lda #<wbaBlkData
    sta zpEdBuf
    lda #>wbaBlkData
    sta zpEdBuf + 1
    lda wwGuest
    ldx wwGuest + 1
    ldy wbGuestLen
    jsr ed_finfo
    bne done
    ldx #3
:   lda wbaEdInfo + FI_SIZE, x
    sta wdChr, x
    dex
    bpl :-
    ; 8 KiB units, rounded up: (size + $1FFF) >> 13
    clc
    lda wdChr
    adc #$ff
    lda wdChr + 1
    adc #$1f
    sta wwV
    lda wdChr + 2
    adc #0
    sta wwV + 1
    lda wdChr + 3
    adc #0
    sta wbN
    ldx #5
:   lsr wbN
    ror wwV + 1
    ror wwV
    dex
    bne :-
    lda wwV
    ldx wwV + 1
    jsr mask_of
    sta wbN
    lda wbaCfg + C_CHR
    and #$f0
    ora wbN
    sta wbaCfg + C_CHR
    lda wbaCfg + C_MAP
    and #$fb ; CHR ROM now, not RAM
    sta wbaCfg + C_MAP
    lda wbGuestBatt
    sta wbBattery
    beq ok
    lda wbGuestSrm
    jsr srm_set
ok:
    lda #0
done:
    rts
.endproc


; > A = n for the smallest 8 KiB << n holding A/X (low/high) 8 KiB units; 0 for none
.proc mask_of
    sta wwV
    stx wwV + 1
    ora wwV + 1
    beq zero
    lda wwV
    bne :+
    dec wwV + 1
:   dec wwV
    ldy #0
loop:
    lda wwV
    ora wwV + 1
    beq done
    lsr wwV + 1
    ror wwV
    iny
    bne loop
done:
    tya
    and #$0f
    rts
zero:
    lda #0
    rts
.endproc


; wbaCore and wdCoreSize: a sibling name.rbf (what edn8.py --rbf leaves), else the stock core for the mapper
; > A = status, Z set on success
.proc find_core
    lda wwRom
    ldx wwRom + 1
    ldy wbRomLen
    jsr is_nes
    bcc maps
    ldy #0
:   lda (zpEdSrc), y
    sta wbaCore, y
    iny
    cpy wbRomLen
    bne :-
    sty wbCoreLen
    lda #'r'
    sta wbaCore - 3, y
    lda #'b'
    sta wbaCore - 2, y
    lda #'f'
    sta wbaCore - 1, y
    jsr core_info
    beq done

maps:
    lda #FA_READ
    sta zbEdMode
    lda #<rsMaprout
    ldx #>rsMaprout
    ldy #MAPROUT_LEN
    jsr ed_fopen
    bne none
    lda wwMap
    sta zdEdOff
    lda wwMap + 1
    sta zdEdOff + 1
    lda #0
    sta zdEdOff + 2
    sta zdEdOff + 3
    jsr ed_fseek
    bne close
    lda #<wbPack
    sta zpEdBuf
    lda #>wbPack
    sta zpEdBuf + 1
    lda #1
    sta zwEdArg
    lda #0
    sta zwEdArg + 1
    jsr ed_fread
close:
    pha
    jsr ed_fclose
    pla
    bne none
    lda wbPack
    cmp #$ff
    beq none

    ldy #MAPS_LEN - 1
:   lda rsMaps, y
    sta wbaCore, y
    dey
    bpl :-
    lda #MAPS_LEN
    sta wbCoreLen
    lda wbPack
    ldx #'0' - 1
    sec
:   inx
    sbc #100
    bcs :-
    adc #100
    stx wbaCore + MAPS_NUM
    ldx #'0' - 1
    sec
:   inx
    sbc #10
    bcs :-
    adc #10 + '0'
    stx wbaCore + MAPS_NUM + 1
    sta wbaCore + MAPS_NUM + 2
    jsr core_info
    bne none
done:
    rts
none:
    lda #FS_E_NOCORE
    rts
.endproc


; wdCoreSize for wbaCore
; > A = status, Z set on success
.proc core_info
    lda #<wbaBlkData ; the data block is ours
    sta zpEdBuf
    lda #>wbaBlkData
    sta zpEdBuf + 1
    lda #<wbaCore
    ldx #>wbaCore
    ldy wbCoreLen
    jsr ed_finfo
    bne done
    ldx #3
:   lda wbaEdInfo + FI_SIZE, x
    sta wdCoreSize, x
    dex
    bpl :-
    lda #0
done:
    rts
.endproc


; a battery game's folder made and its .srm sized, for launch_go to load and deskboot to write back
; > A = status, Z set on success
.proc save_prep
    lda #0
    ldx #3
:   sta wdSaveLoad, x
    dex
    bpl :-
    lda wbBattery
    beq done
    jsr save_name
    lda wbNameLen
    cmp #ROM_SAVE_MAX + 1
    bcs long
    jsr save_path
    lda #<SAVE_BUF
    ldx #>SAVE_BUF
    ldy #GAMEDATA_LEN
    jsr ed_dir_make
    bne done
    lda #<SAVE_BUF
    ldx #>SAVE_BUF
    ldy wbSaveDir
    jsr ed_dir_make
    bne done
    lda #<SAVE_BUF ; the name comes back over the path, which has gone by then
    sta zpEdBuf
    lda #>SAVE_BUF
    sta zpEdBuf + 1
    lda #<SAVE_BUF
    ldx #>SAVE_BUF
    ldy wbSaveLen
    jsr ed_finfo
    bne missing
    ldx #3
:   lda wbaEdInfo + FI_SIZE, x
    sta wdSaveLoad, x
    dex
    bpl :-
    ; no more than the SRM holds
    lda wdSrmLen
    cmp wdSaveLoad
    lda wdSrmLen + 1
    sbc wdSaveLoad + 1
    lda wdSrmLen + 2
    sbc wdSaveLoad + 2
    lda wdSrmLen + 3
    sbc wdSaveLoad + 3
    bcs ok
    ldx #3
:   lda wdSrmLen, x
    sta wdSaveLoad, x
    dex
    bpl :-
ok:
    lda #0
done:
    rts
missing:
    cmp #FR_NO_FILE ; the first run: nothing to load
    beq ok
    rts
long:
    lda #FS_E_LONG
    rts
.endproc


; zpEdSrc and wbNameLen: the path a save is named after, the guest's when there is one
.proc save_name
    lda wbGuestLen
    beq rom
    sta wbNameLen
    lda wwGuest
    sta zpEdSrc
    lda wwGuest + 1
    sta zpEdSrc + 1
    rts
rom:
    lda wbRomLen
    sta wbNameLen
    lda wwRom
    sta zpEdSrc
    lda wwRom + 1
    sta zpEdSrc + 1
    rts
.endproc


; SAVE_BUF = "EDN8/gamedata/<save_name's file name>/bram.srm", wbSaveDir and wbSaveLen its lengths
.proc save_path
    ldy #GAMEDATA_LEN - 1
:   lda rsGamedata, y
    sta SAVE_BUF, y
    dey
    bpl :-
    jsr save_name
    ldy wbNameLen
find:
    dey
    cpy #$ff
    beq name
    lda (zpEdSrc), y
    cmp #'/'
    bne find
name:
    iny ; past the last '/', or the whole path
    lda #'/'
    sta SAVE_BUF + GAMEDATA_LEN
    ldx #GAMEDATA_LEN + 1
:   cpy wbNameLen
    beq bram
    lda (zpEdSrc), y
    sta SAVE_BUF, x
    inx
    iny
    bne :-
bram:
    stx wbSaveDir
    ldy #0
:   lda rsBram, y
    sta SAVE_BUF, x
    inx
    iny
    cpy #BRAM_LEN
    bne :-
    stx wbSaveLen
    rts
.endproc


; the block after the PRG and CHR of ROM A/X (low/high), Y its length, into wbaBlkData: its resource section, if
; tools/mknes.py put one there (Desk: sd_release first)
; > A = status, Z set when the file holds a whole block there
.proc rom_rsrc
    sta wwRom
    stx wwRom + 1
    sty wbRomLen
    jsr read_header
    bne :+
    jsr parse_header
    beq sized
:   rts
sized:
    ; wdLen = the header, any trainer, PRG and CHR
    ldx #0
    ldy #4
    clc
:   lda wdOff, x
    adc wdPrg, x
    sta wdLen, x
    inx
    dey
    bne :-
    ldx #0
    ldy #4
    clc
:   lda wdLen, x
    adc wdChr, x
    sta wdLen, x
    inx
    dey
    bne :-
    lda #<wbaBlkData
    sta zpEdBuf
    lda #>wbaBlkData
    sta zpEdBuf + 1
    lda wwRom
    ldx wwRom + 1
    ldy wbRomLen
    jsr ed_finfo
    bne done
    ; a block or more past wdLen
    sec
    lda wbaEdInfo + FI_SIZE
    sbc wdLen
    lda wbaEdInfo + FI_SIZE + 1
    sbc wdLen + 1
    sta wbN
    lda wbaEdInfo + FI_SIZE + 2
    sbc wdLen + 2
    sta wbArg
    lda wbaEdInfo + FI_SIZE + 3
    sbc wdLen + 3
    bcc none
    ora wbArg
    bne read
    lda wbN
    cmp #>BLOCK_SIZE
    bcc none
read:
    lda #FA_READ
    sta zbEdMode
    lda wwRom
    ldx wwRom + 1
    ldy wbRomLen
    jsr ed_fopen
    bne done
    ldx #3
:   lda wdLen, x
    sta zdEdOff, x
    dex
    bpl :-
    jsr ed_fseek
    bne close
    lda #<wbaBlkData
    sta zpEdBuf
    lda #>wbaBlkData
    sta zpEdBuf + 1
    jsr half
    bne close
    jsr half
close:
    pha
    jsr ed_fclose
    pla
done:
    rts
none:
    lda #FS_END
    rts
half: ; the next 512 bytes, which the MCU reads at most at once
    lda #<(BLOCK_SIZE / 2)
    sta zwEdArg
    lda #>(BLOCK_SIZE / 2)
    sta zwEdArg + 1
    jmp ed_fread
.endproc


; ------------------------------------ the point of no return

; script the launch launch_prep checked into SCRIPT and hand the console to the stub
.proc launch_go
    jsr script_begin
    ; [fall_through]
.endproc

; as launch_go, after the records the script has already
.proc launch_script
    jsr script_records
    jmp script_run
.endproc


; the launch's records from zpEdBuf on
.proc script_records
    lda #<wbaCore
    ldx #>wbaCore
    ldy wbCoreLen
    jsr put_open
    jsr rec_begin
    lda #ED_FPG_SDC
    jsr put_cmd
    lda #<wdCoreSize
    ldx #>wdCoreSize
    jsr put_u32
    lda #OP_HALT
    ldx #ST_FPG_OK
    jsr rec_end
    jsr rec_begin
    lda #ED_F_FCLOSE
    jsr put_cmd
    lda #OP_NONE
    jsr rec_end

    lda wwRom
    ldx wwRom + 1
    ldy wbRomLen
    jsr put_open
    lda #<wdOff
    ldx #>wdOff
    jsr put_seek
    ldx #3
:   lda wdPrg, x
    sta wdLen, x
    dex
    bpl :-
    lda #<rdZero
    ldx #>rdZero
    jsr put_frd
    lda wdChr + 1
    ora wdChr + 2
    ora wdChr + 3
    beq close
    lda wbGuestLen
    beq chr
    jsr put_close
    lda wwGuest
    ldx wwGuest + 1
    ldy wbGuestLen
    jsr put_open
chr:
    ldx #3
:   lda wdChr, x
    sta wdLen, x
    dex
    bpl :-
    lda #<rdChr
    ldx #>rdChr
    jsr put_frd
close:
    jsr put_close

    ; the game's PRG RAM cleared of Desk's WRAM
    jsr rec_begin
    lda #ED_MEM_SET
    jsr put_cmd
    lda #<rdSrm
    ldx #>rdSrm
    jsr put_u32
    lda #<wdSrmLen
    ldx #>wdSrmLen
    jsr put_u32
    lda #0
    jsr put
    lda #OP_HALT
    ldx #ST_CMD_OK
    jsr rec_end
    lda wbBattery
    beq :+
    jsr put_save

:   jsr rec_begin
    lda #ED_MEM_WR
    jsr put_cmd
    lda #<rdCfg
    ldx #>rdCfg
    jsr put_u32
    lda #<rdCfgLen
    ldx #>rdCfgLen
    jsr put_u32
    lda #$aa
    jsr put
    ldy #32 ; no cheats
:   lda #0
    jsr put
    dey
    bne :-
    lda #<wbaCfg
    ldx #>wbaCfg
    ldy #CFG_LEN
    jsr put_bytes
    lda #OP_BOOT
    ldx #ST_CMD_OK
    jmp rec_end
.endproc


; records loading a battery game's .srm, then arming deskboot to write the SRM back to it after the reset
.proc put_save
    jsr save_path ; SAVE_BUF is the dying Desk's to spend
    lda wdSaveLoad
    ora wdSaveLoad + 1
    ora wdSaveLoad + 2
    ora wdSaveLoad + 3
    beq arm
    ldx #3
:   lda wdSaveLoad, x
    sta wdLen, x
    dex
    bpl :-
    lda #<SAVE_BUF
    ldx #>SAVE_BUF
    ldy wbSaveLen
    jsr put_open
    lda #<rdSrm
    ldx #>rdSrm
    jsr put_frd
    jsr put_close

arm:
    jsr rec_begin
    lda #ED_MEM_WR
    jsr put_cmd
    lda #<rdSaveRec
    ldx #>rdSaveRec
    jsr put_u32
    lda wbSaveLen
    clc
    adc #SV_PATH
    sta wdLen
    lda #0
    sta wdLen + 2
    sta wdLen + 3
    adc #0
    sta wdLen + 1
    lda #<wdLen
    ldx #>wdLen
    jsr put_u32
    lda #$aa
    jsr put
    lda #<rsSaveMagic
    ldx #>rsSaveMagic
    ldy #SAVE_MAGIC_LEN
    jsr put_bytes
    lda #<wdSrmLen
    ldx #>wdSrmLen
    jsr put_u32
    lda wbSaveLen
    jsr put
    lda #OP_NONE
    jsr rec_end
    jsr rec_begin
    lda #<SAVE_BUF
    ldx #>SAVE_BUF
    ldy wbSaveLen
    jsr put_bytes
    lda #OP_HALT
    ldx #ST_CMD_OK
    jmp rec_end
.endproc
.assert SV_LEN = SV_MAGIC + SAVE_MAGIC_LEN && SV_PATH_LEN = SV_LEN + 4 && SV_PATH = SV_PATH_LEN + 1, error, "put_save's order"


; no more interrupts or rendering; records go to SCRIPT from here on
.proc script_begin
    sei
    lda #0
    sta PPU_CTRL
    sta PPU_MASK
    sta APU_STATUS
    sta wbDry
    lda #<SCRIPT
    sta zpEdBuf
    lda #>SCRIPT
    sta zpEdBuf + 1
    rts
.endproc


; the stub to its RAM, then the records from SCRIPT on; the last one boots or jumps away
.proc script_run
    ldx #0
:   lda __STUB_LOAD__, x
    sta __STUB_RUN__, x
    inx
    cpx #<__STUB_SIZE__
    bne :-
    lda #<SCRIPT
    sta S_PTR
    lda #>SCRIPT
    sta S_PTR + 1
    jmp stub_run
.endproc


; records moving the open file's pointer to the u32 at A/X
.proc put_seek
    pha
    txa
    pha
    jsr rec_begin
    lda #ED_F_FPTR
    jsr put_cmd
    pla
    tax
    pla
    jsr put_u32
    lda #OP_STATUS
    jmp rec_end
.endproc


; records closing the open file
.proc put_close
    jsr rec_begin
    lda #ED_F_FCLOSE
    jsr put_cmd
    lda #OP_STATUS
    jmp rec_end
.endproc


; records opening file A/X (low/high), Y its length, for reading
.proc put_open
    pha
    lda #FA_READ
    sta wbOpenMode
    pla
    ; [fall_through]
.endproc

; as put_open, in mode wbOpenMode
.proc put_open_as
    sta zpEdSrc
    stx zpEdSrc + 1
    sty wbN
    jsr rec_begin
    lda #ED_F_FOPN
    jsr put_cmd
    lda wbOpenMode
    jsr put
    lda wbN
    jsr put
    lda #0
    jsr put
    lda #OP_NONE
    jsr rec_end
    jsr rec_begin
    lda zpEdSrc
    ldx zpEdSrc + 1
    ldy wbN
    jsr put_bytes
    lda #OP_STATUS
    jmp rec_end
.endproc


; records DMAing wdLen bytes of the open file to the u32 at A/X
.proc put_frd
    ldy #ED_F_FRD_MEM
    bne put_dma
.endproc

; records DMAing wdLen bytes from the u32 at A/X to the open file
.proc put_fwr
    ldy #ED_F_FWR_MEM
    ; [fall_through]
.endproc

; DMA command Y between memory at the u32 at A/X and the open file
.proc put_dma
    pha
    txa
    pha
    tya
    pha
    jsr rec_begin
    pla
    jsr put_cmd
    pla
    tax
    pla
    jsr put_u32
    lda #<wdLen
    ldx #>wdLen
    jsr put_u32
    lda #OP_HALT
    ldx #ST_CMD_OK
    jsr rec_end
    jsr rec_begin
    lda #OP_STATUS
    jmp rec_end
.endproc


; a record's count byte, filled in by rec_end
.proc rec_begin
    lda zpEdBuf
    sta wpRec
    lda zpEdBuf + 1
    sta wpRec + 1
    lda #0
    jmp put
.endproc


; end the record with op A, its arg X
.proc rec_end
    stx wbArg
    pha
    clc ; count = bytes after the count byte
    lda zpEdBuf
    sbc wpRec
    tay
    lda zpEdBuf + 1
    sbc wpRec + 1
    bne long
    cpy #REC_MAX + 1
    bcc :+
long:
    lda wbDry
    ora #DRY_LONG
    sta wbDry
:   lda zpEdBuf
    pha
    lda zpEdBuf + 1
    pha
    lda wpRec
    sta zpEdBuf
    lda wpRec + 1
    sta zpEdBuf + 1
    tya
    ldx #0
    bit wbDry
    bmi :+
    sta (zpEdBuf, x)
:   pla
    sta zpEdBuf + 1
    pla
    sta zpEdBuf
    pla
    jsr put
    lda wbArg
    jmp put
.endproc


; the MCU's framing of command A
.proc put_cmd
    pha
    lda #'+'
    jsr put
    lda #'+' ^ $ff
    jsr put
    pla
    pha
    jsr put
    pla
    eor #$ff
    jmp put
.endproc


.proc put_u32
    ldy #4
    ; [fall_through]
.endproc

; Y bytes from A/X (low/high)
; keeps: nothing but zpEdBuf's progress
.proc put_bytes
    sta zpEdSrc
    stx zpEdSrc + 1
    sty wbN
    ldy #0
loop:
    cpy wbN
    beq done
    lda (zpEdSrc), y
    jsr put
    iny
    bne loop
done:
    rts
.endproc


; A at zpEdBuf, advancing it
; changes: X; keeps: Y
.proc put
    ldx #0
    bit wbDry
    bmi :+
    sta (zpEdBuf, x)
:   inc zpEdBuf
    bne :+
    inc zpEdBuf + 1
:   rts
.endproc


; ------------------------------------ the stub, run at $0300 with all else given up

S_PTR = $00 ; next record
S_N   = $02
S_ARG = $03
S_T   = $04

.segment "STUB"

.proc stub_run
next:
    ldy #0
    lda (S_PTR), y
    sta S_N
send:
    cpy S_N
    beq op
    iny
    lda (S_PTR), y
    sta FIFO_DATA
    jmp send
op:
    iny
    lda (S_PTR), y
    tax
    iny
    lda (S_PTR), y
    sta S_ARG
    tya
    sec
    adc S_PTR
    sta S_PTR
    bcc :+
    inc S_PTR + 1
:   cpx #OP_STATUS
    beq status
    cpx #OP_HALT
    beq halt_next
    cpx #OP_BOOT
    beq boot
    cpx #OP_JUMP
    beq jump
    jmp next
halt_next:
    jsr halt
    jmp next

status:
    lda #'+'
    sta FIFO_DATA
    lda #'+' ^ $ff
    sta FIFO_DATA
    lda #ED_STATUS
    sta FIFO_DATA
    lda #ED_STATUS ^ $ff
    sta FIFO_DATA
    jsr read
    sta S_T
    jsr read
    cmp #ED_STATUS_MARKER
    bne fail
    lda S_T
    beq next
fail:
    ; Desk again before the FPGA is touched, the OS (map 255, deskboot) after
jump:
    jmp ($fffc)

boot:
    jsr halt
    ldx #0
    txa
:   sta $00, x
    inx
    bne :-
    lda #$ff
    sta $11 ; as krikzz's ed_reboot_exec leaves it, which a game relies on
    bit PPU_STATUS
:   bit PPU_STATUS
    bpl :-
    ldx #$fd
    txs
    lda #$34
    pha
    lda #0
    tax
    tay
    plp
    jmp ($fffc)

read:
    bit FIFO_STAT
    bmi read
    lda FIFO_DATA
    rts

; MSTAT = S_ARG, run the MCU, then wait until those pending bits clear (everdrive_asm.s wait_status)
halt:
    lda S_ARG
    sta MSTAT
    lda #0
    sta FIFO_DATA
wait:
    lda MSTAT
    sta S_T
    lda MSTAT
    eor #ST_STROBE
    cmp S_T
    bne wait
    eor #ST_CMD_OK | ST_FPG_OK
    and S_ARG
    cmp S_ARG
    bne wait
    lda S_T
    and #$f0
    cmp #$a0
    bne wait
    rts
.endproc
