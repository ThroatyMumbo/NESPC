; Desk programs: loads them into APP_BANK, and the kernel calls they make through JUMPS.

.include "desk.inc"
.include "fs.inc"
.include "edio.inc"

.segment "ZEROPAGE"

zbBank:    .res 1 ; at $8000 but while gfx reads bank 0: a shell bank, APP_BANK while the program's code runs
zpFar:     .res 2 ; far_call's inline target
zbAppExit: .res 1 ; the program called K_EXIT
zbAppFit:  .res 1 ; the program asked for another window size (K_SIZE)
zbCurX:    .res 1 ; body cursor
zbCurY:    .res 1
zbEnd:     .res 1
zbN:       .res 1
zpSrc:     .res 2
zpDst:     .res 2
zpDxDir:   .res 2 ; dx_join's folder
zbTextPal: .res 1 ; palette of the text K_PUTS writes (K_ATTR)
zbPutX:    .res 1 ; screen pixel of a K_PUTS
zbPutY:    .res 1

RSRC_HEADER = 5 ; "DSKR", entry count
RSRC_ENTRY  = 6 ; type, size, offset, length
RSRC_MAX    = (BLOCK_SIZE - RSRC_HEADER) / RSRC_ENTRY
ICON16_LEN  = 4 * ICON_REC

.segment "BSS"

wbSizing: .res 1 ; the program's first draw, run only for its K_SIZE: nothing reaches the screen
wbaDxFile:  .res APP_TITLE_LEN ; the program's file name less ".dx" (dx_path), its title when the header has none
wbaDxTitle: .res APP_TITLE_LEN ; dx_open's
wbDxRsrc:   .res 1 ; block of its resource section, $ff for none
wbDxTile:   .res 1
wbDxN:      .res 1
wbRsType:   .res 1 ; rsrc_find's
wbRsSize:   .res 1
wwRsLen:    .res 2
wbaIconPal: .res 4 ; dx_icon16's tile palettes
wbSprX:     .res 1 ; icon_sprites_at's top left pixel, tiles a side, first tile and their palettes
wbSprY:     .res 1
wbSprW:     .res 1
wbSprTile:  .res 1
wbaSprPal:  .res 16
wbSprN:     .res 1
wbSprC:     .res 1
wbSprR:     .res 1
wbaAppChr:  .res APP_TILES * 16 ; K_CHR's tiles as IMAGE rows
wbPutI:     .res 1 ; k_puts's cell, and the first of the text run before it
wbRun:      .res 1
wbAppX:     .res 1 ; app_in's
wbAppY:     .res 1
wbAppSx:    .res 1 ; k_copy's source
wbAppSy:    .res 1
wpFarTo:    .res 2 ; far_call's
wbFarA:     .res 1
wbFarY:     .res 1
wbFarP:     .res 1

.segment "WRAM"

wbaAppPal:  .res 16 ; the background palettes while the program's window shows (K_PAL)
wbaTilePal: .res APP_TILES ; palette of each program tile (K_CHR)
wbaDxPath:  .res 256 ; the program's MCU path (dx_path)
wbDxPathLen: .res 1
wdDxSize:   .res 4
wwDxImage:  .res 2 ; bytes exec_load reads into the bank

.segment "RODATA"

rsMagic: .byte "DSKX"
rsRsrcMagic: .byte "DSKR"

rbaAppColor: ; 1 for the palette entries a program may set
.repeat 16, i
    .byte (APP_COLORS >> i) & 1
.endrepeat

.import __SHELL_BSS_RUN__, __SHELL_BSS_SIZE__, __SHELL3_BSS_RUN__, __SHELL3_BSS_SIZE__
rbaRamBank:   .byte SHELL_BANK, SHELL3_BANK ; each shell bank's RAM (conf/ld.cfg)
rbaRamLo:     .byte <__SHELL_BSS_RUN__, <__SHELL3_BSS_RUN__
rbaRamHi:     .byte >__SHELL_BSS_RUN__, >__SHELL3_BSS_RUN__
rbaRamSizeLo: .byte <__SHELL_BSS_SIZE__, <__SHELL3_BSS_SIZE__
rbaRamSizeHi: .byte >__SHELL_BSS_SIZE__, >__SHELL3_BSS_SIZE__
RAM_BANKS = * - rbaRamSizeHi

; K_PUTS text in each palette, as the tile Desk had: white on teal, black on gray, white on navy, black on gray
rbaTextFg: .byte C_WHITE, C_BLACK, C_WHITE, C_BLACK
rbaTextBg: .byte C_DESK, C_GRAY, C_ACCENT, C_GRAY

; addresses frozen: apps/include/desk.inc
.segment "JUMPS"

    jmp k_clear  ; $FF00
    jmp k_goto   ; $FF03
    jmp k_puts   ; $FF06
    jmp k_flush  ; $FF09
    jmp k_exit   ; $FF0C
    jmp k_pointer ; $FF0F
    jmp k_body   ; $FF12
    jmp k_chr    ; $FF15
    jmp k_size   ; $FF18
    jmp k_attr   ; $FF1B
    jmp k_pal    ; $FF1E
    jmp k_rtc    ; $FF21
    jmp k_rtc_set ; $FF24
    jmp k_fill   ; $FF27, API 4: pixels from the body's top left, in K_X-K_H
    jmp k_bevel  ; $FF2A
    jmp k_text   ; $FF2D
    jmp k_image  ; $FF30
    jmp k_span_pal ; $FF33
    jmp k_copy   ; $FF36
    jmp k_point  ; $FF39
    jmp clock_ampm ; $FF3C, API 5
    jmp clock_ampm_set ; $FF3F
    jmp backdrop_get ; $FF42, API 6
    jmp backdrop_set ; $FF45
    jmp scheme_get ; $FF48, API 7
    jmp scheme_set ; $FF4B
    jmp saver_get ; $FF4E, API 8
    jmp saver_set ; $FF51
    jmp saver_list ; $FF54
    jmp saver_set ; $FF57, K_SAVER_RUN
    jmp saver_resume ; $FF5A
    jmp saver_none ; $FF5D, K_SAVER_PIC
    jmp rom_list ; $FF60, API 9
    jmp rom_pic  ; $FF63
    jmp rom_run  ; $FF66
    jmp saver_none ; $FF69, API 10: K_SAVER_OPTS
    jmp saver_none ; $FF6C, K_SAVER_CFG
    jmp saver_none ; $FF6F, K_SAVER_CFG_SET
    jmp k_key    ; $FF72

.segment "CODE"

; program wbaDxPath into APP_BANK, straight from the card; dx_open's title and resources with it
; > A = status, Z set on success
.proc exec_load
    lda zbBank
    pha
    jsr load
    tax
    pla
    jsr set_bank
    txa
    rts
load:
    jsr dx_open
    bne done
    jsr app_bank
    lda #0
    sta zwBlk
    sta zwBlk + 1
    sta zpEdBuf
    lda #>DX_MAGIC
    sta zpEdBuf + 1
    lda wwDxImage
    sta zwBlkLen
    lda wwDxImage + 1
    sta zwBlkLen + 1
    jsr sd_read
    bne done
    ; the rest of its last block zeroed, which programs expect
    clc
    lda wwDxImage
    sta zpDst
    lda wwDxImage + 1
    adc #>DX_MAGIC
    sta zpDst + 1
    ldy #0
pad:
    lda zpDst
    bne zero
    lda zpDst + 1
    and #>(BLOCK_SIZE - 1)
    beq loaded
zero:
    tya
    sta (zpDst), y
    inc zpDst
    bne pad
    inc zpDst + 1
    bne pad
loaded:
    lda #0
done:
    rts
.endproc


; ------------------------------------ banks: the program's at $8000 only while its code runs

; every shell bank's RAM zeroed at reset, as the console's is; leaves the last of them mapped
.proc shell_ram_clear
    ldx #0
bank:
    lda rbaRamBank, x
    sta DESK_BANK
    lda rbaRamLo, x
    sta zpDst
    lda rbaRamHi, x
    sta zpDst + 1
    lda rbaRamSizeLo, x
    sta zpSrc ; a count here
    lda rbaRamSizeHi, x
    sta zpSrc + 1
    ldy #0
loop:
    lda zpSrc
    ora zpSrc + 1
    beq next
    tya
    sta (zpDst), y
    inc zpDst
    bne :+
    inc zpDst + 1
:   lda zpSrc
    bne :+
    dec zpSrc + 1
:   dec zpSrc
    jmp loop
next:
    inx
    cpx #RAM_BANKS
    bne bank
    rts
.endproc


; A at $8000, as code there expects it
; keeps: X, Y and C
.proc set_bank
    sta zbBank
    sta DESK_BANK
    rts
.endproc

; keeps: A
.proc app_bank
    pha
    lda #APP_BANK
    sta zbBank
    sta DESK_BANK
    pla
    rts
.endproc


; keeps: A, X, Y and the flags
.proc shell_bank
    php
    pha
    lda #SHELL_BANK
    sta zbBank
    sta DESK_BANK
    pla
    plp
    rts
.endproc


; `far` (desk.inc): the proc after the jsr in the bank after it, then the caller's bank again
; keeps: A, X, Y and the flags, both ways
.proc far_call
    php
    sta wbFarA
    pla
    sta wbFarP
    sty wbFarY
    pla
    sta zpFar
    pla
    sta zpFar + 1
    clc ; back past the inline address and bank
    lda zpFar
    adc #3
    tay
    lda zpFar + 1
    adc #0
    pha
    tya
    pha
    lda zbBank
    pha
    ldy #1
    lda (zpFar), y
    sta wpFarTo
    iny
    lda (zpFar), y
    sta wpFarTo + 1
    iny
    lda (zpFar), y
    jsr set_bank
    lda wbFarP
    pha
    lda wbFarA
    ldy wbFarY
    plp
    jsr go
    php
    sta wbFarA
    pla
    sta wbFarP
    pla
    jsr set_bank
    lda wbFarP
    pha
    lda wbFarA
    plp
    rts
go:
    jmp (wpFarTo)
.endproc


.proc app_draw
    lda zbBank
    pha
    jsr app_bank
    jsr draw
    pla
    jmp set_bank
draw:
    jmp (DX_DRAW)
.endproc


; A = the pad's new buttons
; > C as the program's handler returns it
.proc app_event
    tax
    lda zbBank
    pha
    txa
    jsr app_bank
    jsr event
    pla
    jmp set_bank
event:
    jmp (DX_EVENT)
.endproc


; > Z set when the program has no event handler
.proc app_listens
    lda zbBank
    pha
    jsr app_bank
    ldx DX_EVENT + 1
    pla
    jsr set_bank
    cpx #0
    rts
.endproc


; A/X (low/high) = a program's MCU path, Y its length: the file dx_open and exec_load take, its name the fallback title
.proc dx_path
    sta zpSrc
    stx zpSrc + 1
    sty wbDxPathLen
    ldy #0
:   cpy wbDxPathLen
    beq copied
    lda (zpSrc), y
    sta wbaDxPath, y
    iny
    bne :-
copied:
    ; its name: after the last "/", up to any ".dx", cut to DX_NAME_LEN
    lda #<wbaDxPath
    ldx #>wbaDxPath
    ldy wbDxPathLen
    jsr is_dx
    lda wbDxPathLen
    bcc :+
    sbc #3
:   sta zbEnd
    ldy wbDxPathLen
start:
    tya
    beq name
    lda wbaDxPath - 1, y
    cmp #'/'
    beq name
    dey
    jmp start
name:
    ldx #0
:   cpy zbEnd
    bcs end
    cpx #DX_NAME_LEN
    beq end
    lda wbaDxPath, y
    sta wbaDxFile, x
    inx
    iny
    bne :-
end:
    lda #0
    sta wbaDxFile, x
    rts
.endproc


; as dx_path, for the Y letters at zpDxDir (a folder and its "/") and then the NUL-ended name at A/X
.proc dx_join
    sta zpSrc
    stx zpSrc + 1
    tya
    tax
    dey
:   lda (zpDxDir), y
    sta wbaDxPath, y
    dey
    bpl :-
    ldy #0
:   lda (zpSrc), y
    beq :+
    sta wbaDxPath, x
    inx
    iny
    bne :-
:   txa
    tay
    lda #<wbaDxPath
    ldx #>wbaDxPath
    jmp dx_path
.endproc


; wbaDxTitle = the NUL-ended file name at A/X less its ".lnk", cut to APP_TITLE_LEN - 1 letters
.proc lnk_title
    sta zpSrc
    stx zpSrc + 1
    ldy #0
:   lda (zpSrc), y
    beq :+
    iny
    bne :-
:   tya
    sec
    sbc #4 ; ".lnk"
    sta zbN
    ldy #0
:   cpy zbN
    beq :+
    cpy #APP_TITLE_LEN - 1
    beq :+
    lda (zpSrc), y
    sta wbaDxTitle, y
    iny
    bne :-
:   lda #0
    sta wbaDxTitle, y
    rts
.endproc


; wbaDxPath held open, its size in wdDxSize
; > A = status, Z set on success
.proc dx_hold
    lda #<wbaBlkData
    sta zpEdBuf
    lda #>wbaBlkData
    sta zpEdBuf + 1
    lda #<wbaDxPath
    ldx #>wbaDxPath
    ldy wbDxPathLen
    jsr ed_finfo
    bne done
    ldx #3
:   lda wbaEdInfo + FI_SIZE, x
    sta wdDxSize, x
    dex
    bpl :-
    lda #HOLD_DX
    sta zbHoldId
    lda #<wbaDxPath
    ldx #>wbaDxPath
    ldy wbDxPathLen
    jmp sd_hold
done:
    rts
.endproc


; program wbaDxPath's header checked, the file left held; wbaDxTitle (its name, else wbaDxFile), wwDxImage and
; wbDxRsrc ($ff: none)
; > A = status, Z set when this Desk runs it
.proc dx_open
    lda #$ff
    sta wbDxRsrc
    jsr dx_hold
    bne fail
    lda wdDxSize + 3
    ora wdDxSize + 2
    ora wdDxSize + 1
    bne read
    lda wdDxSize
    cmp #DX_HEADER_SIZE
    bcs read
    lda #FS_E_EXEC
    bne fail
read:
    lda #0
    sta zwBlk
    sta zwBlk + 1
    sta zwBlkLen + 1
    lda #DX_HEADER_SIZE
    sta zwBlkLen
    lda #<wbaBlkData
    sta zpEdBuf
    lda #>wbaBlkData
    sta zpEdBuf + 1
    jsr sd_read
    bne fail
    jsr dx_header
    bne fail
    ldy #0
:   lda wbaBlkData + DX_NAME - DX_MAGIC, y
    sta wbaDxTitle, y
    beq named
    iny
    cpy #DX_NAME_LEN
    bne :-
    lda #0
    sta wbaDxTitle, y
named:
    lda wbaDxTitle
    bne ok
    jsr file_title
ok:
    lda #0
    rts
fail:
    pha
    jsr file_title
    pla
    rts
.endproc


; the header in the data block against wdDxSize: wwDxImage and wbDxRsrc from it
; > A = status, Z set when this Desk runs it
.proc dx_header
    ldx #3
:   lda wbaBlkData, x
    cmp rsMagic, x
    bne exec
    dex
    bpl :-
    lda wbaBlkData + DX_FORMAT - DX_MAGIC
    cmp #DX_FORMAT_CUR
    bne exec
    lda wbaBlkData + DX_API - DX_MAGIC
    cmp #DX_API_OLD ; its calls are all still here
    bcc exec
    cmp #DX_API_CUR + 1
    bcs exec
    lda wbaBlkData + DX_IMAGE - DX_MAGIC + 1
    cmp #>DX_MAX
    bcc bank
    bne big
    lda wbaBlkData + DX_IMAGE - DX_MAGIC
    bne big
bank:
    lda wbaBlkData + DX_IMAGE - DX_MAGIC + 1
    bne header
    lda wbaBlkData + DX_IMAGE - DX_MAGIC
    cmp #DX_HEADER_SIZE
    bcc exec
header:
    lda wdDxSize + 3
    ora wdDxSize + 2
    bne fits
    lda wdDxSize
    cmp wbaBlkData + DX_IMAGE - DX_MAGIC
    lda wdDxSize + 1
    sbc wbaBlkData + DX_IMAGE - DX_MAGIC + 1
    bcc exec ; the image runs past the file
fits:
    lda wbaBlkData + DX_IMAGE - DX_MAGIC
    sta wwDxImage
    lda wbaBlkData + DX_IMAGE - DX_MAGIC + 1
    sta wwDxImage + 1
    lda wbaBlkData + DX_RSRC - DX_MAGIC
    bne done ; off a block boundary: no resources
    lda wbaBlkData + DX_RSRC - DX_MAGIC + 1
    beq done
    tax
    and #>(BLOCK_SIZE - 1)
    bne done
    txa
    lsr
    lsr
    sta wbDxRsrc
done:
    lda #0
    rts
big:
    lda #FS_E_BIG
    rts
exec:
    lda #FS_E_EXEC
    rts
.endproc


.proc file_title
    ldx #APP_TITLE_LEN - 1
:   lda wbaDxFile, x
    sta wbaDxTitle, x
    dex
    bpl :-
    rts
.endproc


; program wbaDxPath's 16 px icon, after dx_open: into the sprite table from tile A, its tile palettes into wbaIconPal
; > Z set when it has one
.proc dx_icon16
    ldx wbDxRsrc
    bmi none
    pha
    jsr rsrc_read
    tax
    pla
    cpx #0
    bne none
    jmp rsrc_icon16
none:
    lda #1
    rts
.endproc


; program wbaDxPath's desktop picture, after dx_open
; > C clear when it has one, A (low), X (high) at it in the data block
.proc dx_picture
    ldx wbDxRsrc
    bmi none
    jsr rsrc_read
    beq rsrc_picture
none:
    sec
    rts
.endproc


; as dx_picture, from the resource section at the start of wbaBlkData
.proc rsrc_picture
    lda #<PICTURE_LEN
    sta wwRsLen
    lda #>PICTURE_LEN
    sta wwRsLen + 1
    lda #RSRC_PICTURE
    ldx #ICON_SIZE
    ; [fall_through]
.endproc

; the resource of type A, size X and length wwRsLen in the section at the start of wbaBlkData
; > C clear when there is one, A (low), X (high) at it
.proc rsrc_at
    jsr rsrc_find
    sec
    bne done
    lda zpSrc
    ldx zpSrc + 1
    clc
done:
    rts
.endproc


; what the file has of block wbDxRsrc, up to a block, into the data block; held again if another took the handle
; > A = status, Z set on success
.proc rsrc_read
    lda zbHeld
    cmp #HOLD_DX
    beq held
    jsr dx_hold
    bne done
held:
    lda wbDxRsrc
    sta zwBlk
    asl
    asl
    sta zbN ; its offset's second byte
    lda #0
    sta zwBlk + 1
    sec
    lda wdDxSize + 1
    sbc zbN
    tax
    lda wdDxSize + 2
    sbc #0
    sta zbN
    lda wdDxSize + 3
    sbc #0
    bcc short
    ora zbN
    bne whole
    cpx #>BLOCK_SIZE
    bcs whole
    stx zwBlkLen + 1
    lda wdDxSize
    sta zwBlkLen
    ora zwBlkLen + 1
    bne read
short:
    lda #FS_E_EXEC
    rts
whole:
    lda #<BLOCK_SIZE
    sta zwBlkLen
    lda #>BLOCK_SIZE
    sta zwBlkLen + 1
read:
    lda #<wbaBlkData
    sta zpEdBuf
    lda #>wbaBlkData
    sta zpEdBuf + 1
    jmp sd_read
done:
    rts
.endproc


; as dx_icon16, from the resource section at the start of wbaBlkData
.proc rsrc_icon16
    sta wbDxTile
    lda #<ICON16_LEN
    sta wwRsLen
    lda #>ICON16_LEN
    sta wwRsLen + 1
    lda #RSRC_ICON
    ldx #16
    jsr rsrc_find
    bne done
    ldx zpSrc
    ldy zpSrc + 1
    lda wbDxTile
    jsr icon_upload
    lda #0
done:
    rts
.endproc


; a 16x16 icon's 4 sprite records at X/Y (low/high) onto tiles A on, their palettes into wbaIconPal
.proc icon_upload
    sta wbDxTile
    stx zpSrc
    sty zpSrc + 1
    lda #0
    sta wbDxN
tile:
    ldy #15
:   lda (zpSrc), y
    sta wbaRow, y
    dey
    bpl :-
    ldy #16
    lda (zpSrc), y
    and #3
    ldx wbDxN
    sta wbaIconPal, x
    txa
    clc
    adc wbDxTile
    jsr vq_spr
    ldy #16
    jsr vq_row
    lda zpSrc
    clc
    adc #ICON_REC
    sta zpSrc
    bcc :+
    inc zpSrc + 1
:   inc wbDxN
    lda wbDxN
    cmp #4
    bne tile
    rts
.endproc


; the resource of type A, size X and length wwRsLen in the section at the start of wbaBlkData
; > zpSrc at its data, A = 0 and Z set when there is one
.proc rsrc_find
    sta wbRsType
    stx wbRsSize
    ldx #3
:   lda wbaBlkData, x
    cmp rsRsrcMagic, x
    bne none
    dex
    bpl :-
    lda wbaBlkData + 4
    cmp #RSRC_MAX + 1
    bcs none
    sta wbDxN
    lda #<(wbaBlkData + RSRC_HEADER)
    sta zpSrc
    lda #>(wbaBlkData + RSRC_HEADER)
    sta zpSrc + 1
entry:
    lda wbDxN
    beq none
    ldy #0
    lda (zpSrc), y
    cmp wbRsType
    bne next
    iny
    lda (zpSrc), y
    cmp wbRsSize
    bne next
    ldy #4
    lda (zpSrc), y
    cmp wwRsLen
    bne next
    iny
    lda (zpSrc), y
    cmp wwRsLen + 1
    bne next
    ldy #2 ; its data must end inside the block
    lda (zpSrc), y
    clc
    adc wwRsLen
    tax
    iny
    lda (zpSrc), y
    adc wwRsLen + 1
    bcs next
    cmp #>BLOCK_SIZE
    bcc found
    bne next
    txa
    beq found
next:
    lda zpSrc
    clc
    adc #RSRC_ENTRY
    sta zpSrc
    bcc :+
    inc zpSrc + 1
:   dec wbDxN
    jmp entry
none:
    lda #1
    rts
found:
    ldy #2
    lda (zpSrc), y
    clc
    adc #<wbaBlkData
    tax
    iny
    lda (zpSrc), y
    adc #>wbaBlkData
    stx zpSrc
    sta zpSrc + 1
    lda #0
    rts
.endproc


; wbSprTile = A, and the 4 tile palettes at X/Y (low/high) into wbaSprPal
; keeps: A
.proc spr_icon
    sta wbSprTile
    stx zpSrc
    sty zpSrc + 1
    ldy #3
:   lda (zpSrc), y
    sta wbaSprPal, y
    dey
    bpl :-
    lda wbSprTile
    rts
.endproc


; an icon wbSprW tiles square as sprites from OAM + X: tiles from wbSprTile and palettes wbaSprPal in reading
; order, top left at wbSprX and OAM Y A
.proc icon_sprites_at
    sta wbSprY
    lda #0
    sta wbSprN
    sta wbSprR
row:
    lda #0
    sta wbSprC
sprite:
    lda wbSprY
    sta OAM, x
    ldy wbSprN
    tya
    clc
    adc wbSprTile
    sta OAM + 1, x
    lda wbaSprPal, y
    sta OAM + 2, x
    lda wbSprC
    asl
    asl
    asl
    adc wbSprX
    sta OAM + 3, x
    inx
    inx
    inx
    inx
    inc wbSprN
    inc wbSprC
    lda wbSprC
    cmp wbSprW
    bne sprite
    lda wbSprY
    clc
    adc #8
    sta wbSprY
    inc wbSprR
    lda wbSprR
    cmp wbSprW
    bne row
    rts
.endproc


; Y sprites from OAM + X off the screen
.proc sprites_hide
    lda #$ff
:   sta OAM, x
    inx
    inx
    inx
    inx
    dey
    bne :-
    rts
.endproc

; ------------------------------------ kernel calls

; blank the body in gray on its own palette, the cursor to its top left; in the file window's frame, its listing's
; white round the body too
.proc k_clear
    lda #0
    sta zbCurX
    sta zbCurY
    lda wbSizing
    bne done
    jsr body_px
    lda #PAL_BODY
    jsr gfx_pal
    lda zbFitW
    bne fill
    jsr win_x0
    clc
    adc #FRAME + 1
    sta zbGx
    lda zbWinW
    asl
    asl
    asl
    sec
    sbc #FRAME * 2 + 1 + SB_W
    sta zbGw
    dec zbGy
    inc zbGh
    inc zbGh
fill:
    lda #C_GRAY
    jmp gfx_rect
done:
    rts
.endproc


.proc k_flush
    jsr gfx_wait
    jmp vq_flush
.endproc


; X = body column, Y = body row
.proc k_goto
    stx zbCurX
    sty zbCurY
    rts
.endproc


; the zero-terminated string at A (low), X (high) at the cursor, cut at the body's right edge;
; program tiles in their K_CHR palettes, the rest in the K_ATTR one
.proc k_puts
    sta zpSrc
    stx zpSrc + 1
    lda wbSizing
    bne done
    lda zbCurY
    cmp zbBodyH
    bcs done
    lda zbBodyW
    sec
    sbc zbCurX
    beq done
    bcc done
    sta zbN
    ldy #0
copy:
    lda (zpSrc), y
    beq put
    sta wbaRow, y
    iny
    cpy zbN
    bne copy
put:
    tya
    beq done
    sta zbN
    lda zbCurY
    asl
    asl
    asl
    clc
    adc zbBodyY
    sta zbPutY
    lda zbCurX
    clc
    adc zbBodyX
    asl
    asl
    asl
    sta zbPutX
    lda #0
    sta wbPutI
    sta wbRun
cell:
    ldx wbPutI
    lda wbaRow, x
    cmp #T_APP
    bcc :+
    jsr text_run
    jsr tile_cell
    ldx wbPutI
    inx
    stx wbRun
    stx wbPutI
    bne more
:   inc wbPutI
more:
    lda wbPutI
    cmp zbN
    bne cell
    jsr text_run
    lda zbCurX
    clc
    adc zbN
    sta zbCurX
done:
    rts
.endproc


; k_puts's cell zbGx from wbPutI: zbPutX, plus 8 a cell; zbGy, zbGh its row
.proc cell_at
    asl
    asl
    asl
    clc
    adc zbPutX
    sta zbGx
    lda zbPutY
    sta zbGy
    lda #FONT_H
    sta zbGh
    rts
.endproc


; k_puts's characters from wbRun up to wbPutI in zbTextPal's colors
.proc text_run
    lda wbPutI
    sec
    sbc wbRun
    beq done
    sta zbGn
    asl
    asl
    asl
    sta zbGw
    lda wbRun
    jsr cell_at
    lda zbTextPal
    jsr gfx_pal
    ldx zbTextPal
    lda rbaTextFg, x
    sta zbGc
    lda rbaTextBg, x
    sta zbGb
    lda wbRun
    clc
    adc #<wbaRow
    sta zpGs
    lda #>wbaRow
    adc #0
    sta zpGs + 1
    jmp gfx_text
done:
    rts
.endproc


; program tile wbaRow[wbPutI] in its cell
.proc tile_cell
    lda wbPutI
    jsr cell_at
    lda #8
    sta zbGw
    ldx wbPutI
    lda wbaRow, x
    sec
    sbc #T_APP
    tax
    lda wbaTilePal, x
    jsr gfx_pal
    lda #0
    sta zpGs + 1
    txa
    asl
    asl
    asl
    asl
    rol zpGs + 1 ; tiles from 16 on
    clc
    adc #<wbaAppChr
    sta zpGs
    lda zpGs + 1
    adc #>wbaAppChr
    sta zpGs + 1
    lda #$ff
    sta zbGb
    jmp gfx_image
.endproc
.assert APP_TILES <= 32, error, "tile_cell's offset is 9 bits"


; ends the program once its call returns
.proc k_exit
    lda #1
    sta zbAppExit
    rts
.endproc


; > X = body column, Y = body row under the pointer; C set when it is outside the body
.proc k_pointer
    jsr k_point
    bcs out
    txa
    lsr
    lsr
    lsr
    tax
    tya
    lsr
    lsr
    lsr
    tay
    clc ; the last lsr left bit 2 of Y in C
out:
    rts
.endproc


; > A = the key typed this frame as key_poll gives it, 0 for none
.proc k_key
    far key_get
    rts
.endproc


; > X, Y = the body pixel under the pointer; C set when it is outside the body
.proc k_point
    jsr pointer_px
    jsr body_origin
    lda zbPx
    sec
    sbc zbN
    tax
    bcc out
    lda zbBodyW
    asl
    asl
    asl
    sta zbN
    cpx zbN
    bcs out
    lda zbPy
    sec
    sbc zbBodyY
    tay
    bcc out
    lda zbBodyH
    asl
    asl
    asl
    sta zbN
    cpy zbN
    bcs out
    clc
    rts
out:
    sec
    rts
.endproc


; > X = body width, Y = body height
.proc k_body
    ldx zbBodyW
    ldy zbBodyH
    rts
.endproc


; X = body width, Y = body height for the window once this call into the program returns
; > C set when the window is redrawn for it, and draw called again
.proc k_size
    cpx zbFitW
    bne new
    cpy zbFitH
    beq same
new:
    stx zbFitW
    sty zbFitH
    lda zbZoom
    bne same
    lda #1
    sta zbAppFit
    sec
    rts
same:
    clc
    rts
.endproc


; the tile at A (low), X (high), 16 pattern bytes and its palette, into program tile Y
.proc k_chr
    sta zpSrc
    stx zpSrc + 1
    cpy #APP_TILES
    bcs done
    tya
    tax
    ldy #16
    lda (zpSrc), y
    and #3
    sta wbaTilePal, x
    lda #0
    sta zpDst + 1
    txa
    asl
    asl
    asl
    asl
    rol zpDst + 1 ; tiles from 16 on
    clc
    adc #<wbaAppChr
    sta zpDst
    lda zpDst + 1
    adc #>wbaAppChr
    sta zpDst + 1
    ldy #0
:   lda (zpSrc), y ; plane 0's row, then plane 1's beside it
    pha
    tya
    ora #8
    tay
    lda (zpSrc), y
    sta zbN
    tya
    and #7
    asl
    tay
    pla
    sta (zpDst), y
    iny
    lda zbN
    sta (zpDst), y
    tya
    lsr
    tay
    iny
    cpy #8
    bne :-
done:
    rts
.endproc


; A = palette (PAL_*) for the text of the K_PUTS calls after this
.proc k_attr
    and #3
    sta zbTextPal
    rts
.endproc


; X = background palette entry, A = NES color; entries outside APP_COLORS are left alone
.proc k_pal
    cpx #16
    bcs done
    ldy rbaAppColor, x
    beq done
    sta wbaAppPal, x
    ldy wbSizing
    bne done
    sta wbaRow
    txa
    jsr vq_pal
    ldy #1
    jmp vq_row
done:
    rts
.endproc


; > A/X = the cart's clock, RTC_SIZE BCD bytes
.proc k_rtc
    jsr ed_rtc_get
    lda #<wbaEdRtc
    ldx #>wbaEdRtc
    rts
.endproc


; set the cart's clock from the RTC_SIZE BCD bytes at A/X, and the taskbar's with it
.proc k_rtc_set
    sta zpSrc
    stx zpSrc + 1
    ldy #RTC_SIZE - 1
:   lda (zpSrc), y
    sta wbaEdRtc, y
    dey
    bpl :-
    jsr ed_rtc_set
    jmp clock_refresh
.endproc


; a program starting: the Desk's palettes, and text in the body's
.proc app_init
    ldx #15
:   lda wbaDeskPal, x
    sta wbaAppPal, x
    dex
    bpl :-
    lda #PAL_BODY
    sta zbTextPal
    rts
.endproc


; ------------------------------------ API 4: K_X-K_H from the body's top left, drawing kept to the body

; > C set while the program is only sizing; else K_X, K_Y on the screen and the clip on the body
.proc app_in
    sec
    lda wbSizing
    bne done
    lda zbGx
    sta wbAppX
    lda zbGy
    sta wbAppY
    lda zbGw
    pha
    lda zbGh
    pha
    jsr body_px
    jsr gfx_clip
    lda zbGx
    clc
    adc wbAppX
    sta wbAppX
    lda zbGy
    clc
    adc wbAppY
    sta zbGy
    lda wbAppX
    sta zbGx
    pla
    sta zbGh
    pla
    sta zbGw
    clc
done:
    rts
.endproc


; K_X, K_Y from the body again, the clip off
.proc app_out
    jsr gfx_noclip
    jsr body_origin
    lda zbGx
    sec
    sbc zbN
    sta zbGx
    lda zbGy
    sec
    sbc zbBodyY
    sta zbGy
    rts
.endproc


; a kernel call that runs gfx proc with A, its rect from the body's top left, unless the program is only sizing
.macro APP_DRAW proc
    pha
    jsr app_in
    pla
    bcs :+
    jsr proc
    jmp app_out
:   rts
.endmacro

; A = color over K_X, K_Y, K_W, K_H
.proc k_fill
    APP_DRAW gfx_rect
.endproc

; A = BEVEL_* round the rect, its face first when it has one
.proc k_bevel
    APP_DRAW gfx_bevel
.endproc

; A = palette for the 8x1 spans the rect touches
.proc k_span_pal
    APP_DRAW gfx_pal
.endproc


; the rect from A (x), X (y) in the body
.proc k_copy
    sta wbAppSx
    stx wbAppSy
    jsr app_in
    bcs done
    jsr body_origin
    lda wbAppSx
    clc
    adc zbN
    pha
    lda wbAppSy
    clc
    adc zbBodyY
    tax
    pla
    jsr gfx_copy
    jmp app_out
done:
    rts
.endproc


; the zero-terminated string at A (low), X (high), up to 32 letters, at K_X, K_Y in K_FG on K_BG ($ff for none);
; K_X moves past it
.proc k_text
    sta zpSrc
    stx zpSrc + 1
    ldy #0
:   lda (zpSrc), y
    beq :+
    sta wbaRow, y
    iny
    cpy #32
    bne :-
:   sty zbGn
    jsr app_in
    bcs done
    jsr gfx_text_row
    jmp app_out
done:
    rts
.endproc


; the K_W x K_H picture at A (low), X (high), IMAGE rows, at K_X, K_Y; color K_BG left out
; unless $ff
.proc k_image
    sta zpGs
    stx zpGs + 1
    jsr app_in
    bcs done
    jsr gfx_image
    jmp app_out
done:
    rts
.endproc


; > zbN = the body's left edge in pixels
.proc body_origin
    lda zbBodyX
    asl
    asl
    asl
    sta zbN
    rts
.endproc


; the program's background palettes (C set) or the Desk's (C clear) onto the screen
.proc pal_show
    ldx #15
    bcc desk
app:
    lda wbaAppPal, x
    sta wbaRow, x
    dex
    bpl app
    bmi put
desk:
    lda wbaDeskPal, x
    sta wbaRow, x
    dex
    bpl desk
put:
    lda #0
    jsr vq_pal
    ldy #16
    jmp vq_row
.endproc
