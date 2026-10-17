.ifndef _TESTLIB_
    _TESTLIB_ = 1

CTRL_VALUE = %10001000 ; NMI on
MASK_BG    = %00001010 ; the bitmap BG, including the left 8 pixels

.global reset, irq, screen_on, to_menu, clear, print, puthex, putc
.globalzp zbFg, zbBig, zbT, zpS
.global start, nmi, rbaPalette ; each test ROM's own: reset ends in start

.endif
