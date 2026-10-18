; ROM launching (src/launch.s).

.ifndef _LAUNCH_
    _LAUNCH_ = 1

; script ops, run by the stub after a record's FIFO bytes
OP_NONE   = 0
OP_STATUS = 1 ; ED_STATUS must answer 0
OP_HALT   = 2 ; wait in RAM for the MCU, arg = MSTAT bits
OP_BOOT   = 3 ; halt, then the game's reset vector
OP_JUMP   = 4 ; the reset vector of whatever is now at $FFFC

; a battery game's RAM for deskboot to write back: a record in its WRAM bank, which a reset keeps and power-on clears
WRAM_BANK  = 4 ; deskboot's $6000: OS image 0x8000, clear of OS RAM ($5000 = bank 0)
SAVE_REC   = $7F00 ; where deskboot sees it
SAVE_PSRAM = $7E0000 + WRAM_BANK * $2000 + SAVE_REC - $6000 ; where the launch script writes it
SV_MAGIC    = 0 ; rsSaveMagic while armed
SV_LEN      = 4 ; u32 bytes of SRM
SV_PATH_LEN = 8
SV_PATH     = 9 ; the .srm file's MCU path
SAVE_MAGIC_LEN = 4

.global launch_prep, launch_go, launch_script, is_nes, rom_rsrc, wwMap
.global launch_guest, wwGuest, wbGuestLen, wbGuestBatt, wbGuestSrm
.global script_begin, put_open_as, put_fwr, put_close
.global wdLen, wbOpenMode, rsSaveMagic, rdSrm

.endif
