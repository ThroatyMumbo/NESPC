; The boot jingle on the APU, played from the NMI once per power-up: when SYS_INF's boot count isn't the one
; nespc/system/boot kept.

.include "desk.inc"
.include "edio.inc"
.include "fs.inc"
.include "paths.inc"

APU       = $4000 ; a voice's 4 registers at its SQ1-NOISE offset: volume, sweep, period low, period high
SQ1       = 0
SQ2       = 4
TRI       = 8
NOISE     = 12
VOICES    = 4
TRI_VOICE = TRI / 4

VOL_ON    = $B0 ; 50% duty, length halted, constant volume; ORed with the volume
SWEEP_OFF = $08 ; negate set, so the sweep never mutes a low note
TRI_ON    = $FF ; linear counter held at 127
TRI_OFF   = $80 ; linear counter reloads to 0 at the next quarter frame

APU_DAC   = $4011 ; raised, it quietens the triangle: 9 dB at DAC_TOP
DAC_TOP   = 126
DAC_UP    = 2 ; per frame, done before the triangle's first note
DAC_DOWN  = 1 ; per frame once the notes end; slow, or it clicks

EVENT     = 5 ; rbaScore's: voice, period low, high, envelope, frames to the next event (0 the same frame)
END       = $FF ; the last event's wait
OFF       = $FF ; wbaEnv of a voice that's done

.segment "BSS"

wbJingle: .res 1 ; nonzero while it plays
wbWait:   .res 1 ; frames to the next event, 0 after the last
wbPos:    .res 1 ; the next event in rbaScore
wbDac:    .res 1 ; APU_DAC's level
wbaEnv:   .res VOICES ; each voice's next run in rbaEnv, OFF when done
wbaLeft:  .res VOICES ; frames left of its run
wbaCount: .res 4 ; SYS_INF's boot count
wbaSeen:  .res 4 ; nespc/system/boot's

.segment "RODATA"

rsBootFile: .byte NESPC_SYSTEM, "boot"
BOOT_FILE_LEN = * - rsBootFile
rbaSeenRec:  REC_FILE rsBootFile, BOOT_FILE_LEN, wbaSeen, 4 ; nespc/system/boot read
rbaCountRec: REC_FILE rsBootFile, BOOT_FILE_LEN, wbaCount, 4 ; and written

; runs of frames, volume; 0 frames ends the note
rbaEnv:
ENV_MEL = * - rbaEnv ; 7 * 0.90^frame
.byte 1, 7, 2, 6, 2, 5, 2, 4, 3, 3, 5, 2, 11, 1, 0
ENV_PART = * - rbaEnv ; the bell's 4th harmonic, 2.5 * 0.86^frame
.byte 4, 2, 7, 1, 0
ENV_CHORD = * - rbaEnv ; 6.5 * 0.975^frame
.byte 7, 6, 8, 5, 10, 4, 13, 3, 20, 2, 44, 1, 0
ENV_HIT = * - rbaEnv
.byte 1, 3, 1, 2, 2, 1, 0
ENV_TRI = * - rbaEnv ; the triangle can't fade: on, then off
.byte 48, 1, 0

.macro event voice, period, env, wait
    .byte voice, <(period), >(period), env, wait
.endmacro

; NTSC pulse periods; onsets at 0.06, 0.46, 0.66, 1.06 and 1.48 s
rbaScore:
    event SQ1, $167, ENV_MEL, 0 ; Eb4
    event SQ2, $059, ENV_PART, 24 ; Eb6
    event SQ1, $13f, ENV_MEL, 0 ; F4
    event SQ2, $04f, ENV_PART, 12 ; F6
    event SQ1, $167, ENV_MEL, 0 ; Eb4
    event SQ2, $059, ENV_PART, 24 ; Eb6
    event SQ1, $1df, ENV_MEL, 0 ; Bb3
    event SQ2, $077, ENV_PART, 25 ; Bb5
    event SQ1, $13f, ENV_CHORD, 0 ; Db major: F4
    event SQ2, $21a, ENV_CHORD, 0 ; Ab3
    event TRI, $193, ENV_TRI, 0 ; Db3
    event NOISE, 3, ENV_HIT, END

.segment "CODE"

; at boot: the jingle when the cart has powered up since the last check
.proc jingle_boot
    lda #ED_SYS_INF
    jsr ed_cmd
    ldx #0
read:
    jsr ed_read
    cpx #SYS_BOOT_CTR
    bcc next
    cpx #SYS_BOOT_CTR + 4
    bcs next
    sta wbaCount - SYS_BOOT_CTR, x
next:
    inx
    cpx #SYS_INF_LEN
    bne read

    lda #FA_READ
    ldx #<rbaSeenRec
    ldy #>rbaSeenRec
    jsr rec_file
    bne play
    ldx #3
:   lda wbaCount, x
    cmp wbaSeen, x
    bne play
    dex
    bpl :-
    rts
play:
    lda #FA_WRITE | FA_CREATE_ALWAYS
    ldx #<rbaCountRec
    ldy #>rbaCountRec
    jsr rec_file ; a failed write plays it again next boot
    ; [fall_through]
.endproc

.proc jingle_start
    lda #0
    sta wbPos
    sta wbDac
    lda #1
    sta wbWait
    lda #OFF
    ldx #VOICES - 1
:   sta wbaEnv, x
    dex
    bpl :-
    lda #VOL_ON
    sta APU + SQ1
    sta APU + SQ2
    sta APU + NOISE
    lda #TRI_OFF
    sta APU + TRI
    lda #SWEEP_OFF
    sta APU + SQ1 + 1
    sta APU + SQ2 + 1
    lda #$0f
    sta APU_STATUS
    sta wbJingle
    rts
.endproc


; once a frame from the NMI: the score's events that are due, then each voice's envelope
; changes: A, X, Y
.proc jingle_tick
    lda wbJingle
    bne playing
    rts
playing:
    lda wbWait
    beq voices
    dec wbWait
    bne voices

    ldx wbPos
due:
    ldy rbaScore, x
    lda rbaScore + 1, x
    sta APU + 2, y
    lda rbaScore + 2, x
    sta APU + 3, y
    tya
    lsr
    lsr
    tay
    lda rbaScore + 3, x
    sta wbaEnv, y
    lda #0
    sta wbaLeft, y
    lda rbaScore + 4, x
    sta wbWait
    txa
    clc
    adc #EVENT
    tax
    lda wbWait
    beq due
    stx wbPos
    cmp #END
    bne voices
    lda #0
    sta wbWait

voices:
    ldx #VOICES - 1
voice:
    ldy wbaEnv, x
    cpy #OFF
    beq next
    lda wbaLeft, x
    bne hold
    lda rbaEnv, y
    beq stop
    sta wbaLeft, x
    lda rbaEnv + 1, y
    pha
    iny
    iny
    tya
    sta wbaEnv, x
    pla
    jsr set_volume
hold:
    dec wbaLeft, x
    jmp next
stop:
    lda #OFF
    sta wbaEnv, x
    lda #0
    jsr set_volume
next:
    dex
    bpl voice

    lda wbWait
    bne up
    ldx #VOICES - 1
:   lda wbaEnv, x
    cmp #OFF
    bne up
    dex
    bpl :-
    lda wbDac
    beq over
    sec
    sbc #DAC_DOWN
    sta wbDac
    sta APU_DAC
    rts
over:
    sta wbJingle
    sta APU_STATUS
    rts
up:
    lda wbDac
    cmp #DAC_TOP
    bcs done
    adc #DAC_UP
    sta wbDac
    sta APU_DAC
done:
    rts
.endproc


; voice X's volume A, 0-15; the triangle's on or off
; changes: A, Y
.proc set_volume
    pha
    txa
    asl
    asl
    tay
    pla
    cpx #TRI_VOICE
    beq tri
    ora #VOL_ON
    sta APU, y
    rts
tri:
    cmp #1
    lda #TRI_OFF
    bcc :+
    lda #TRI_ON
:   sta APU, y
    rts
.endproc
