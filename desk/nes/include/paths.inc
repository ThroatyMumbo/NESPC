; Where NESPC keeps its files on the SD card: programs in nespc/apps, the Start menu's in nespc/menu, the rest in
; nespc/system.

.ifndef _PATHS_
    _PATHS_ = 1

.define NESPC_DIR     "nespc" ; the Files icon's folder
.define NESPC_APPS    .concat(NESPC_DIR, "/apps/")
.define NESPC_MENU    .concat(NESPC_DIR, "/menu/")
.define NESPC_DESKTOP .concat(NESPC_DIR, "/desktop/") ; the desktop's shortcuts and programs, beside Files
.define NESPC_SYSTEM  .concat(NESPC_DIR, "/system/")
.define NESPC_TRASH   .concat(NESPC_DIR, "/trash") ; the Trash
.define NESPC_TRASH_INFO .concat(NESPC_SYSTEM, "trash") ; a file per trashed entry, by its name: where it came from
.define NESPC_COLORS  .concat(NESPC_SYSTEM, "colors") ; the window colors (colors.inc)
.define NESPC_POINTER .concat(NESPC_SYSTEM, "pointer") ; the pointer across a launch (taskbar.inc PTR_*)

.endif
