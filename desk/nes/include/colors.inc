; NESPC_COLORS: SC_MAGIC, then the window colors, which scheme.s keeps.

.ifndef _COLORS_
    _COLORS_ = 1

.define SC_MAGIC "DSC1"
SC_MAGIC_LEN = 4
SC_FACE   = 0 ; BG_PALETTE's gray: window faces, panels, menus, the taskbar
SC_SHADOW = 1 ; its dark gray: bevels' shadows
SC_TITLE  = 2 ; its navy: title bars, menu highlights, selections
SC_LEN    = 3
.define SC_DEFAULT $10, $00, $02

.endif
