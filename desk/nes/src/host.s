; The stock menu's USB commands (edn8.py menu_test/menu_install/menu_start/menu_reset), so the host tools treat Desk as the menu.

.include "desk.inc"
.include "fs.inc"
.include "edio.inc"
.include "launch.inc"

PATH = ROM_PATH ; the '*n' and '*o' path

.segment "SHELL_BSS"

wbaReply:  .res 3
wbPathLen:  .res 1

.segment "SHELL"

; one host command from the FIFO, which the host has just written to; only '*t', '*n' and '*r' reply, '*s' and '*r'
; don't return
.proc host_poll
    jsr ed_read
    cmp #'*'
    bne done
    jsr ed_read
    cmp #'t'
    beq test
    cmp #'n'
    beq install
    cmp #'s'
    beq start
    cmp #'r'
    beq reset
    cmp #'w'
    beq windows
    cmp #'o'
    beq open
done:
    rts

windows: ; desk.py start: as the keyboard's Windows key
    jmp start_key

open: ; desk.py open: a program or shortcut, as the Start menu opens one
    jsr host_path
    bcs done
    lda #<PATH
    ldx #>PATH
    ldy wbPathLen
    jsr dx_path
    jmp app_run

test:
    lda #'k'
    ldy #1
    jmp reply
start:
    jsr state_window
    jmp launch_go
reset:
    lda #0
    ldy #1
    jsr reply
    jmp menu_exit

install:
    jsr host_path
    bcs long
    lda #<PATH
    ldx #>PATH
    ldy wbPathLen
    jsr rom_prep
    bne fail
    sta wbaReply
    lda wwMap
    sta wbaReply + 1
    lda wwMap + 1
    sta wbaReply + 2
    ldy #3
    jmp send
long:
    lda #FS_E_NOTROM
fail:
    ldy #1
    ; [fall_through]
.endproc

; A as the reply's first byte, Y bytes of wbaReply in all
.proc reply
    sta wbaReply
    ; [fall_through]
.endproc

.proc send
    sty zwEdArg
    lda #0
    sta zwEdArg + 1
    lda #<wbaReply
    sta zpEdBuf
    lda #>wbaReply
    sta zpEdBuf + 1
    jmp ed_usb_wr
.endproc

; the command's path into PATH, wbPathLen long, all of it out of the FIFO before sd_release talks to the MCU
; > C set when it is longer than 255
.proc host_path
    jsr ed_read
    sta wbPathLen
    jsr ed_read
    bne long
    ldy #0
:   cpy wbPathLen
    beq :+
    jsr ed_read
    sta PATH, y
    iny
    bne :-
:   jsr sd_release
    clc
    rts
long:
    sec
    rts
.endproc
