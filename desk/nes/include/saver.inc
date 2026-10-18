; The screensaver record K_SAVER answers with (romrun.s: always none) and the state file keeps a copy of.

.ifndef _SAVER_REC_
    _SAVER_REC_ = 1

SS_WAIT     = 0 ; idle minutes before it runs, 0 never
SS_NAME     = 1 ; its program less ".nes", zero-padded; all 0 for none
SS_NAME_LEN = 12
SS_LEN      = SS_NAME + SS_NAME_LEN

.endif
