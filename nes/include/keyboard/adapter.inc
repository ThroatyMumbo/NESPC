.ifndef _KEYBOARD_ADAPTER_
    _KEYBOARD_ADAPTER_ = 1

    .scope Adapter

        .import adapter
        .import send, recv, note, sys, raw
        .importzp zbaWord
        .import wbMouseDx, wbMouseDy, wbMouseBtn, wbMouseWheel

        ; link commands, "send" as cmd, len, len bytes (usbadapter/src/link.h)
        CMD_ECHO    = $01 ; the bytes come back through "recv"
        CMD_RAWKEYS = $02 ; 1 byte, 1 on: keys come as HID usages going down and up, through "raw"
        CMD_BENCH   = $03 ; the speed test: op, then its bytes

        BENCH_DOWN   = 0 ; mode (0 fast, 1 table), pass: the next strobe starts a down pass
        BENCH_UP     = 1 ; n lo, n hi: the next n bytes sent are the pattern
        BENCH_REPORT = 2 ; NES errors fast lo, hi, table lo, hi: 16 ASCII bytes a test come back

        ; "sys" requests (usbadapter/src/kbdword.h)
        SYS_CLOSE = 1 ; Alt+F4
        SYS_START = 2 ; a Windows key tapped alone
        SYS_F12   = 3 ; F12 alone: Desk's teaser

    .endscope

.endif
