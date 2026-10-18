; The taskbar: its layout, and the sprite palettes its icons are drawn in.

.ifndef _TASKBAR_
    _TASKBAR_ = 1

; sprite palettes: the pointer's, then the ones icons pick from per tile (tools/mkapptiles.py sprite_records)
.define SPR_PALETTE $0f, $0f, $30, $10, $0f, $0f, $16, $30, $0f, $0f, $02, $30, $0f, $0f, $00, $30

TASK_Y     = 216 ; the taskbar, 24 rows
TASK_BTN_Y = TASK_Y + 2 ; its buttons and the clock's field
TASK_BTN_H = 20
TASK_TEXT_Y = TASK_Y + 8
START_X    = 0
START_W    = 40
TASK_X     = 40 ; the window's button, TASK_STEP apart from any after it
TASK_BTN_W = 26
TASK_STEP  = 28
TASK_MAX   = 3 ; with the pointer, 7 sprites on a taskbar line
TRAY_X     = 196
CLOCK_X    = 200 ; "12:34", then "AM" at AMPM_X
AMPM_X     = 241

; the pointer file: its tip as the last ROM with a pointer left it, and PTR_MENU for Desk to open its Start menu
PTR_X     = 0
PTR_Y     = 1
PTR_FLAGS = 2
PTR_SIZE  = 3
PTR_MENU  = 1

.endif
