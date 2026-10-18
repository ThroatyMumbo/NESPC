; SD card file access through the Everdrive MCU.

.include "edio.inc"

.segment "ZEROPAGE"

zwEdArg:  .res 2 ; byte count for ed_fread (<= 512) and ed_fwrite (<= 1024)
zpEdBuf:  .res 2 ; where ed_fread puts the data and ed_fwrite takes it; advanced past it
zbEdMode: .res 1 ; ed_fopen mode
zdEdOff:  .res 4 ; ed_fseek offset
zpEdSrc:  .res 2
zbEdLen:  .res 1
zbEdWait: .res 1 ; the command's wait for replies left, in ED_WAIT's units; ed_cmd sets it
zbEdLost: .res 1 ; a reply never came: ed_cmd drops it, should it come late
zbEdQuiet: .res 1 ; the MCU went quiet: one unit a command until it answers
zbEdSync: .res 1 ; 1 once ed_sync has run since reset
zwEdSpin: .res 2

.segment "BSS"

wbaEdInfo: .res ED_INFO_SIZE ; entry ed_dir_rec read
wbaEdRtc:  .res RTC_SIZE ; as ed_rtc_get left it

.segment "CODE"

.proc ed_flush
    lda #0
    sta FIFO_DATA
    nop
    sta FIFO_DATA
loop:
    bit FIFO_STAT
    bmi done
    lda FIFO_DATA
    jmp loop
done:
    rts
.endproc


; the FIFO drained until ~0.3 s pass silent, so what a launch, hop or host transfer left isn't read as replies
; changes: A
.proc ed_sync
    txa
    pha
    tya
    pha
    jsr ed_flush
restart:
    ldx #0
    ldy #0
wait:
    bit FIFO_STAT
    bmi empty
    lda FIFO_DATA
    jmp restart
empty:
    dex
    bne wait
    dey
    bne wait
    lda #1
    sta zbEdSync
    pla
    tay
    pla
    tax
    rts
.endproc


; < A = command; the first since reset waits for ed_sync
.proc ed_cmd
    pha
    lda zbEdSync
    bne :+
    jsr ed_sync
:   lda zbEdLost
    beq :+
    jsr ed_flush
    lda #0
    sta zbEdLost
:   lda zbEdQuiet
    beq loud
    lda #1
    bne wait
loud:
    lda #ED_WAIT
wait:
    sta zbEdWait
    lda #'+'
    sta FIFO_DATA
    lda #'+' ^ $ff
    sta FIFO_DATA
    pla
    sta FIFO_DATA
    eor #$ff
    sta FIFO_DATA
    rts
.endproc


; > A = byte received, Z/N from it; ED_BAD_REPLY when the MCU never sent one
.proc ed_read
    jsr ed_wait
    bcs lost
    lda FIFO_DATA
    rts
lost:
    lda #ED_BAD_REPLY
    rts
.endproc


; until the FIFO has a byte, for what is left of zbEdWait; X and Y kept
; > C set when it never came, and at once for the rest of the command
.proc ed_wait
    bit FIFO_STAT
    bpl ready
    lda zbEdLost
    bne lost
    lda #0
    sta zwEdSpin
    sta zwEdSpin + 1
spin: ; 14 cycles, 65536 of them an ED_WAIT unit
    bit FIFO_STAT
    bpl ready
    inc zwEdSpin
    bne spin
    inc zwEdSpin + 1
    bne spin
    dec zbEdWait
    bne spin
    lda #1
    sta zbEdLost
    sta zbEdQuiet
lost:
    sec
    rts
ready:
    lda #0
    sta zbEdQuiet
    clc
    rts
.endproc


; > A = status of the last command (0 ok), Z set on success
; changes: A, Y
.proc ed_status
    lda #ED_STATUS
    jsr ed_cmd
    ; [fall_through]
.endproc

; ED_STATUS's reply, after its ed_cmd
.proc ed_reply
    jsr ed_read
    tay
    jsr ed_read
    cmp #ED_STATUS_MARKER
    bne bad
    tya
    rts
bad:
    lda #ED_BAD_REPLY
    rts
.endproc


; the cart's clock into wbaEdRtc
; changes: A, X
.proc ed_rtc_get
    lda #ED_RTC_GET
    jsr ed_cmd
    ldx #0
loop:
    jsr ed_read
    sta wbaEdRtc, x
    inx
    cpx #RTC_SIZE
    bne loop
    rts
.endproc


; set the cart's clock from wbaEdRtc
; changes: A, X
.proc ed_rtc_set
    lda #ED_RTC_SET
    jsr ed_cmd
    ldx #0
loop:
    lda wbaEdRtc, x
    sta FIFO_DATA
    inx
    cpx #RTC_SIZE
    bne loop
    rts
.endproc


; the zbEdLen bytes at zpEdSrc as an MCU string: u16 length, then the bytes
.proc send_str
    lda zbEdLen
    sta FIFO_DATA
    lda #0
    sta FIFO_DATA
    ldy #0
loop:
    cpy zbEdLen
    beq done
    lda (zpEdSrc), y
    sta FIFO_DATA
    iny
    bne loop
done:
    rts
.endproc


; open in mode zbEdMode. < A/X = path (low/high), Y = its length
; > A = status, Z set on success
.proc ed_fopen
    sta zpEdSrc
    stx zpEdSrc + 1
    sty zbEdLen
    lda #ED_F_FOPN
    jsr ed_cmd
    lda zbEdMode
    sta FIFO_DATA
    jsr send_str
    jmp ed_status
.endproc


; move the open file's pointer to zdEdOff
; > A = status, Z set on success
.proc ed_fseek
    lda #ED_F_FPTR
    jsr ed_cmd
    ldx #0
loop:
    lda zdEdOff, x
    sta FIFO_DATA
    inx
    cpx #4
    bne loop
    jmp ed_status
.endproc


; send zwEdArg as the u32 length of a read or write
.proc send_len
    lda zwEdArg
    sta FIFO_DATA
    lda zwEdArg + 1
    sta FIFO_DATA
    lda #0
    sta FIFO_DATA
    sta FIFO_DATA
    rts
.endproc


; one byte of zwEdArg counted down
; > Z set once it reaches 0 (before the decrement)
.proc count_down
    lda zwEdArg
    ora zwEdArg + 1
    beq done
    lda zwEdArg
    bne :+
    dec zwEdArg + 1
:   dec zwEdArg
    lda #1
done:
    rts
.endproc


; read zwEdArg (<= 512) bytes of the open file to zpEdBuf
; > A = status, Z set on success; zwEdArg 0, zpEdBuf past each whole page
.proc ed_fread
    lda #ED_F_FRD
    jsr ed_cmd
    jsr send_len
    jsr ed_read
    bne done

    ldy #0
    lda zwEdArg + 1
    beq tail
page: ; 21 cycles a byte
    bit FIFO_STAT
    bmi page_wait
    lda FIFO_DATA
    sta (zpEdBuf), y
    iny
    bne page
    inc zpEdBuf + 1
    dec zwEdArg + 1
    bne page
tail:
    cpy zwEdArg
    beq ok
rest:
    bit FIFO_STAT
    bmi rest_wait
    lda FIFO_DATA
    sta (zpEdBuf), y
    iny
    cpy zwEdArg
    bne rest
ok:
    lda #0
    sta zwEdArg
done:
    rts
page_wait:
    jsr ed_wait
    bcc page
    lda #ED_BAD_REPLY
    rts
rest_wait:
    jsr ed_wait
    bcc rest
    lda #ED_BAD_REPLY
    rts
.endproc


; write zwEdArg (1-1024, one ack block) bytes from zpEdBuf to the open file
; > A = status, Z set on success
.proc ed_fwrite
    lda #ED_F_FWR
    jsr ed_cmd
    jsr send_len
    jsr ed_read
    bne done

    ldy #0
loop:
    jsr count_down
    beq status
    lda (zpEdBuf), y
    sta FIFO_DATA
    iny
    bne loop
    inc zpEdBuf + 1
    jmp loop
status:
    jmp ed_status
done:
    rts
.endproc


; send zwEdArg (< 256) bytes from zpEdBuf to the host over USB
.proc ed_usb_wr
    lda #ED_USB_WR
    jsr ed_cmd
    lda zwEdArg
    sta FIFO_DATA
    lda #0
    sta FIFO_DATA
    tay
loop:
    cpy zwEdArg
    beq done
    lda (zpEdBuf), y
    sta FIFO_DATA
    iny
    bne loop
done:
    rts
.endproc


; command A on config-space address zdEdOff, zwEdArg bytes long, no DMA
.proc cfg_cmd
    jsr ed_cmd
    ldx #0
:   lda zdEdOff, x
    sta FIFO_DATA
    inx
    cpx #4
    bne :-
    jsr send_len
    lda #0
    sta FIFO_DATA
    tay
    rts
.endproc


; read zwEdArg (< 256) bytes of config space from zdEdOff to zpEdBuf
.proc ed_cfg_rd
    lda #ED_MEM_RD
    jsr cfg_cmd
loop:
    cpy zwEdArg
    beq done
    jsr ed_read
    sta (zpEdBuf), y
    iny
    bne loop
done:
    rts
.endproc


; write zwEdArg (< 256) bytes from zpEdBuf to config space at zdEdOff
.proc ed_cfg_wr
    lda #ED_MEM_WR
    jsr cfg_cmd
loop:
    cpy zwEdArg
    beq done
    lda (zpEdBuf), y
    sta FIFO_DATA
    iny
    bne loop
done:
    rts
.endproc


; > A = status, Z set on success
.proc ed_fclose
    lda #ED_F_FCLOSE
    jsr ed_cmd
    jmp ed_status
.endproc


; load directory A/X (low/high), Y its length, sorted, for ed_dir_get
; > A = status, Z set on success; zwEdArg = its entry count
.proc ed_dir_load
    sta zpEdSrc
    stx zpEdSrc + 1
    sty zbEdLen
    lda #ED_F_DIR_LD
    jsr ed_cmd
    lda #DIR_OPT_SORTED ; HIDESYS would hide EDN8
    sta FIFO_DATA
    jsr send_str
    jsr ed_status
    bne done
    lda #ED_F_DIR_SIZE
    jsr ed_cmd
    jsr ed_read
    sta zwEdArg
    jsr ed_read
    sta zwEdArg + 1
    lda #0
done:
    rts
.endproc


; info of file A/X (low/high), Y its length, as ed_dir_rec leaves it: the name comes back too, to zpEdBuf
.proc ed_finfo
    sta zpEdSrc
    stx zpEdSrc + 1
    sty zbEdLen
    lda #ED_F_FINFO
    jsr ed_cmd
    jsr send_str
    jmp ed_dir_rec
.endproc


; delete file (or empty folder) A/X (low/high), Y its length
; > A = status, Z set on success
.proc ed_fdel
    sta zpEdSrc
    stx zpEdSrc + 1
    sty zbEdLen
    lda #ED_F_DEL
    jsr ed_cmd
    jsr send_str
    jmp ed_status
.endproc


; make directory A/X (low/high), Y its length
; > A = status, Z set on success or when it is there already
.proc ed_dir_make
    sta zpEdSrc
    stx zpEdSrc + 1
    sty zbEdLen
    lda #ED_F_DIR_MK
    jsr ed_cmd
    jsr send_str
    jsr ed_status
    beq done
    cmp #FR_EXIST
    bne done
    lda #0
done:
    rts
.endproc


; ask for A entries of the loaded directory from entry zwEdArg on, names cut to X bytes; ed_dir_rec takes each
.proc ed_dir_get
    pha
    lda #ED_F_DIR_GET
    jsr ed_cmd
    lda zwEdArg
    sta FIFO_DATA
    lda zwEdArg + 1
    sta FIFO_DATA
    pla
    sta FIFO_DATA
    lda #0
    sta FIFO_DATA
    stx FIFO_DATA
    sta FIFO_DATA
    rts
.endproc


; the next entry ed_dir_get asked for: its info to wbaEdInfo, its name to zpEdBuf with a NUL after it
; > A = status, Z set on success; Y = name length
.proc ed_dir_rec
    jsr ed_read
    bne done
    ldy #0
info:
    jsr ed_read
    sta wbaEdInfo, y
    iny
    cpy #ED_INFO_SIZE
    bne info
    jsr ed_read
    sta zbEdLen
    jsr ed_read
    bne bad
    tay
name:
    cpy zbEdLen
    beq end
    jsr ed_read
    sta (zpEdBuf), y
    iny
    bne name
end:
    lda #0
    sta (zpEdBuf), y
    rts
bad:
    lda #ED_BAD_REPLY
done:
    rts
.endproc
