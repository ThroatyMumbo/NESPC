; What Desk and its programs (apps/include/desk.inc) agree on: program tiles, palettes and colors, bevel styles, pad
; bits, picture and name sizes, and the .dx format and API this Desk runs.

.ifndef _ABI_
    _ABI_ = 1

T_APP      = $EE ; K_PUTS bytes from here are the program's K_CHR tiles
APP_TILES  = 18
ICON_REC   = 17 ; 2bpp tile, color 0 transparent, then its sprite palette

PAL_DESK   = 0 ; background palettes, entry 0 the black behind them all: the desk's teal, white and yellow
PAL_BODY   = 1 ; then black, gray, white and dark gray; a program's body, K_PUTS text black on gray
PAL_TITLE  = 2 ; navy
PAL_PANEL  = PAL_BODY ; dark gray, for shadows
PAL_ICON   = 3 ; the desk's with navy at 3, as desktop pictures have it
C_BLACK    = 0
C_GRAY     = 1
C_WHITE    = 2
C_ACCENT   = 3
APP_COLORS = $00EC ; entries a program may set (K_PAL), bit n for entry n: the desk's 2 and 3, and its body's

BEVEL_RAISED = 0 ; gfx_bevel's styles: a button
BEVEL_SUNKEN = 1 ; a pressed one
BEVEL_FIELD  = 2 ; an edit field's edge, no face
BEVEL_WINDOW = 3

JOYPAD_A      = %10000000
JOYPAD_B      = %01000000
JOYPAD_SELECT = %00100000
JOYPAD_START  = %00010000
JOYPAD_UP     = %00001000
JOYPAD_DOWN   = %00000100
JOYPAD_LEFT   = %00000010
JOYPAD_RIGHT  = %00000001

PICTURE_LEN = 32 * 32 / 4 + 32 ; a 32x32 desktop picture: IMAGE rows, then a byte a row of its spans' palettes
RN_LEN      = 64 ; K_ROMS: a ROM's name with its extension, zero-padded

DX_FORMAT_CUR = 2 ; the .dx format and kernel API programs are built for
DX_API_CUR    = 10

.endif
