; Taskbar clock: the cart's RTC as HH:MM, or H:MM with a small AM/PM, in the tray (draw.s), re-read every POLL frames.

.include "desk.inc"
.include "edio.inc"
.include "fs.inc"
.include "paths.inc"

POLL     = 30
TEXT_LEN = 5 ; "HH:MM"
FIELD_X  = TRAY_X + 2 ; inside the field's bevel
FIELD_W  = 256 - TRAY_X - 4
CLOCK_24_X = FIELD_X + (FIELD_W - TEXT_LEN * FONT_W) / 2
AMPM_W   = 10

.segment "BSS"

wbClockWait: .res 1
wbaClock:    .res TEXT_LEN
wbAmPm:      .res 1 ; 1 for 12 hours with AM/PM, kept in nespc/system/clock

.segment "RODATA"

rsClockFile: .byte NESPC_SYSTEM, "clock"
CLOCK_FILE_LEN = * - rsClockFile
rbaClockRec: REC_FILE rsClockFile, CLOCK_FILE_LEN, wbAmPm, 1

; a row of AM/PM's IMAGE, 16 pixels from bit 15: black ink on the panel's gray
.macro ampm_row r
    .byte <(~(>(r))), 0, <(~(<(r))), 0
.endmacro
.assert C_BLACK = 0 && C_GRAY = 1, error, "ampm_row's colors"
rbaAm:
    ampm_row 0
    ampm_row 0
    ampm_row %0110010001000000
    ampm_row %1001011011000000
    ampm_row %1111010101000000
    ampm_row %1001010001000000
    ampm_row %1001010001000000
    ampm_row 0
rbaPm:
    ampm_row 0
    ampm_row 0
    ampm_row %1110010001000000
    ampm_row %1001011011000000
    ampm_row %1110010101000000
    ampm_row %1000010001000000
    ampm_row %1000010001000000
    ampm_row 0

; the RTC's BCD hour as the 12-hour clock's, by that BCD hour
rbaHour12:
    .byte $12, $01, $02, $03, $04, $05, $06, $07, $08, $09, 0, 0, 0, 0, 0, 0
    .byte $10, $11, $12, $01, $02, $03, $04, $05, $06, $07, 0, 0, 0, 0, 0, 0
    .byte $08, $09, $10, $11

.segment "CODE"

.proc clock_init
    lda #':'
    sta wbaClock + 2
    lda #1
    sta wbClockWait
    lda #FA_READ
    ldx #<rbaClockRec
    ldy #>rbaClockRec
    jsr rec_file
    beq read
    lda #0
    sta wbAmPm
read:
    lda wbAmPm
    and #1
    sta wbAmPm
    rts
.endproc


; > A = 1 when the clock shows AM/PM, 0 for 24 hours
.proc clock_ampm
    lda wbAmPm
    rts
.endproc


; A = 1 for AM/PM, 0 for 24 hours; saved in nespc/system/clock, best effort
.proc clock_ampm_set
    and #1
    cmp wbAmPm
    beq done
    sta wbAmPm
    lda #FA_WRITE | FA_OPEN_ALWAYS
    ldx #<rbaClockRec
    ldy #>rbaClockRec
    jsr rec_file
    lda #FIELD_X ; the other mode's text gone
    sta zbGx
    lda #TASK_TEXT_Y
    sta zbGy
    lda #FIELD_W
    sta zbGw
    lda #FONT_H
    sta zbGh
    lda #C_GRAY
    jsr gfx_rect
    jmp clock_refresh
done:
    rts
.endproc


.proc clock_update
    dec wbClockWait
    beq clock_refresh
    rts
.endproc


.proc clock_refresh
    lda #POLL
    sta wbClockWait
    jsr ed_rtc_get
    lda wbaEdRtc + RTC_MIN
    ldx #3
    jsr put_bcd
    lda wbAmPm
    bne ampm
    lda wbaEdRtc + RTC_HOUR
    ldx #0
    jsr put_bcd
    lda #CLOCK_24_X
    bne show
ampm:
    ldx wbaEdRtc + RTC_HOUR
    lda rbaHour12, x
    ldx #0
    jsr put_bcd
    lda wbaClock
    cmp #'0'
    bne :+
    lda #' '
    sta wbaClock
:   lda #<rbaAm
    sta zpGs
    lda #>rbaAm
    sta zpGs + 1
    lda wbaEdRtc + RTC_HOUR
    cmp #$12
    bcc :+
    lda #<rbaPm
    sta zpGs
    lda #>rbaPm
    sta zpGs + 1
:   lda #AMPM_X
    sta zbGx
    lda #TASK_TEXT_Y
    sta zbGy
    lda #AMPM_W
    sta zbGw
    lda #FONT_H
    sta zbGh
    lda #$ff
    sta zbGb
    jsr gfx_image
    lda #CLOCK_X
show:
    sta zbGx
    lda #TEXT_LEN
    sta zbGn
    lda #TASK_TEXT_Y
    sta zbGy
    lda #<wbaClock
    sta zpGs
    lda #>wbaClock
    sta zpGs + 1
    lda #C_BLACK
    sta zbGc
    lda #C_GRAY
    sta zbGb
    jmp gfx_text
.endproc


; A = BCD byte as two digits at wbaClock + X
.proc put_bcd
    pha
    lsr
    lsr
    lsr
    lsr
    ora #'0'
    sta wbaClock, x
    pla
    and #$0f
    ora #'0'
    sta wbaClock + 1, x
    rts
.endproc
