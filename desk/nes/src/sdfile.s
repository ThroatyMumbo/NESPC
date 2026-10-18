; The MCU's one file handle kept open between reads (the viewer's file, or a program's), and the scratch they read into.

.include "edio.inc"
.include "fs.inc"

.segment "ZEROPAGE"

zbHeld:    .res 1 ; HOLD_* of the open file
zbHoldId:  .res 1 ; whose sd_hold opens
zwBlk:     .res 2 ; sd_read's first block
zwBlkLen:  .res 2 ; and its byte count
zwHeldBlk: .res 2 ; block the file's pointer is at, $ffff off a block boundary
zpRecDesc: .res 2 ; rec_file's descriptor
zpScanTo:  .res 2 ; dir_scan's next slot

.segment "BLOCKS"

wbaBlkData: .res BLOCK_SIZE * 2 ; the data block, then ROM_PATH

.segment "WRAM"

wbExt: .res 1 ; has_ext's
wpScanHook:  .res 2 ; dir_scan's: whether to keep an entry
wbScanMax:   .res 1 ; names this long or longer left off
wbScanSlot:  .res 1 ; bytes of a kept name's slot
wbScanCap:   .res 1 ; slots
wbScanN:     .res 1 ; slots filled
wbScanLeft:  .res 1 ; entries still to read
wbScanChunk: .res 1 ; and of the current ED_F_DIR_GET
wbScanLen:   .res 1

.segment "RODATA"

rsExts:
rsExtLnk: .asciiz ".lnk"
rsExtDx:  .asciiz ".dx"

.segment "CODE"

; the held file closed, freeing the MCU's one handle for another
; keeps: X, Y
.proc sd_release
    lda zbHeld
    beq done
    lda #HOLD_NONE
    sta zbHeld
    tya
    pha
    jsr ed_fclose
    pla
    tay
done:
    rts
.endproc


; path A/X (low/high), Y its length, opened for reading as zbHoldId's, closing what was held
; > A = status, Z set on success
.proc sd_hold
    pha
    jsr sd_release
    lda #FA_READ
    sta zbEdMode
    pla
    jsr ed_fopen
    bne done
    lda zbHoldId
    sta zbHeld
    lda #0
    sta zwHeldBlk
    sta zwHeldBlk + 1
done:
    rts
.endproc


; zwBlkLen bytes of the held file from block zwBlk on, to zpEdBuf; seeks only off the file's pointer, closes on failure
; > A = status, Z set on success; changes: zwBlkLen
.proc sd_read
    lda zwBlk
    cmp zwHeldBlk
    bne seek
    lda zwBlk + 1
    cmp zwHeldBlk + 1
    beq read
seek:
    ; offset = zwBlk << 10
    lda #0
    sta zdEdOff
    sta zdEdOff + 3
    lda zwBlk + 1
    sta zdEdOff + 2
    lda zwBlk
    asl
    rol zdEdOff + 2
    rol zdEdOff + 3
    asl
    rol zdEdOff + 2
    rol zdEdOff + 3
    sta zdEdOff + 1
    jsr ed_fseek
    bne fail
read:
    lda zwBlkLen
    bne odd
    lda zwBlkLen + 1
    and #>(BLOCK_SIZE - 1)
    bne odd
    lda zwBlkLen + 1
    lsr
    lsr
    clc
    adc zwBlk
    sta zwHeldBlk
    lda zwBlk + 1
    adc #0
    sta zwHeldBlk + 1
    jmp chunk
odd:
    lda #$ff
    sta zwHeldBlk
    sta zwHeldBlk + 1
chunk:
    lda zwBlkLen
    ora zwBlkLen + 1
    beq done
    ; ed_fread takes 512 at most
    lda zwBlkLen + 1
    cmp #>512
    bcc part
    lda #<512
    ldx #>512
    bcs set
part:
    lda zwBlkLen
    ldx zwBlkLen + 1
set:
    sta zwEdArg
    stx zwEdArg + 1
    sec
    lda zwBlkLen
    sbc zwEdArg
    sta zwBlkLen
    lda zwBlkLen + 1
    sbc zwEdArg + 1
    sta zwBlkLen + 1
    jsr ed_fread
    beq chunk
fail:
    pha
    jsr sd_release
    pla
done:
    rts
.endproc


; a small record file read whole with A = FA_READ, else written in mode A; X/Y (low/high) at its REC_* descriptor
; > A = status, Z set on success
.proc rec_file
    stx zpRecDesc
    sty zpRecDesc + 1
    sta zbEdMode
    jsr sd_release
    ldy #REC_PATH
    jsr rec_axy
    jsr ed_fopen
    bne done
    ldy #REC_BUF
    jsr rec_axy
    jsr ed_fio
    pha
    jsr ed_fclose
    pla
done:
    rts
.endproc

; A/X/Y = the address and length at zpRecDesc + Y
.proc rec_axy
    lda (zpRecDesc), y
    pha
    iny
    lda (zpRecDesc), y
    tax
    iny
    lda (zpRecDesc), y
    tay
    pla
    rts
.endproc


; Y bytes at A/X (low/high) through the open file: read in FA_READ, else written
; > A = status, Z set on success
.proc ed_fio
    sta zpEdBuf
    stx zpEdBuf + 1
    sty zwEdArg
    lda #0
    sta zwEdArg + 1
    lda zbEdMode
    lsr
    bcc write
    jmp ed_fread
write:
    jmp ed_fwrite
.endproc


; folder A/X (low/high), Y its length: the names wpScanHook keeps into wbScanCap slots of wbScanSlot bytes from
; zpScanTo, zero-padded; every name is read before anything else talks to the MCU, up to 255 of them
; > A = how many were kept
.proc dir_scan
    pha
    lda #0
    sta wbScanN
    pla
    jsr ed_dir_load
    bne done
    lda zwEdArg + 1
    beq :+
    lda #$ff
    bne :++
:   lda zwEdArg
    beq done
:   sta wbScanLeft
    lda #0
    sta zwEdArg
    sta zwEdArg + 1
chunk:
    lda wbScanLeft
    cmp #DIR_GET_MAX
    bcc :+
    lda #DIR_GET_MAX
:   sta wbScanChunk
    ldx wbScanMax
    jsr ed_dir_get
entry:
    lda #<wbaBlkData
    sta zpEdBuf
    lda #>wbaBlkData
    sta zpEdBuf + 1
    jsr ed_dir_rec
    bne done
    jsr scan_keep
    dec wbScanLeft
    beq done
    dec wbScanChunk
    bne entry
    clc
    lda zwEdArg
    adc #DIR_GET_MAX
    sta zwEdArg
    bcc chunk
    inc zwEdArg + 1
    bcs chunk
done:
    lda wbScanN
    rts
.endproc

; the entry ed_dir_rec read, Y letters, into the next slot unless it is a folder, too long, past the last slot, or
; the hook (> C set to keep it, Y letters of it) passes it over
.proc scan_keep
    cpy wbScanMax
    bcs no
    lda wbaEdInfo + FI_ATTR
    and #AT_DIR
    bne no
    lda wbScanN
    cmp wbScanCap
    bcs no
    jsr hook
    bcc no
    sty wbScanLen
    ldy #0
pad:
    lda #0
    cpy wbScanLen
    bcs :+
    lda wbaBlkData, y
:   sta (zpScanTo), y
    iny
    cpy wbScanSlot
    bne pad
    lda zpScanTo
    clc
    adc wbScanSlot
    sta zpScanTo
    bcc :+
    inc zpScanTo + 1
:   inc wbScanN
no:
    rts
hook:
    jmp (wpScanHook)
.endproc

; dir_scan's hook for programs and shortcuts: > C set when the name in wbaBlkData, Y letters, ends in ".dx" or ".lnk"
.proc scan_dx_lnk
    sty wbScanLen
    lda #<wbaBlkData
    ldx #>wbaBlkData
    jsr is_dx
    bcs keep
    lda #<wbaBlkData
    ldx #>wbaBlkData
    ldy wbScanLen
    jsr is_lnk
keep:
    ldy wbScanLen
    rts
.endproc


; > C set when A/X (low/high), Y its length, ends in ".lnk", any case
.proc is_lnk
    pha
    lda #rsExtLnk - rsExts
    jmp has_ext
.endproc

; > C set when A/X (low/high), Y its length, ends in ".dx", any case
.proc is_dx
    pha
    lda #rsExtDx - rsExts
    ; [fall_through]
.endproc

; > C set when the path ends in the extension at rsExts + A; the path's low byte pushed, its high byte in X
.proc has_ext
    sta wbExt
    pla
    sta zpEdSrc
    stx zpEdSrc + 1
    ldx wbExt
:   lda rsExts, x
    beq back
    inx
    bne :-
back:
    cpx wbExt
    beq yes
    dex
    tya
    beq no
    dey
    lda (zpEdSrc), y
    ora #$20
    cmp rsExts, x
    beq back
no:
    clc
    rts
yes:
    sec
    rts
.endproc
