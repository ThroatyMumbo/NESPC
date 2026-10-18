; The Files window's clipboard, and paste, delete, rename and the recycle bin on SD card entries, whole folder trees at
; a time. Paths here are the MCU's: "/" before each name, empty for a volume's root.

.include "desk.inc"
.include "fs.inc"
.include "edio.inc"
.include "paths.inc"

SRC = 0 ; path X of path_arg, push_name and pop_name
DST = 1
DEPTH_MAX = 32 ; folders a copied tree may nest

.segment "RODATA"

rsRoot: .byte "/"
rsCopy: .byte " - Copy"
COPY_LEN = * - rsCopy
rsBin:  .byte "/", NESPC_TRASH
BIN_LEN = * - rsBin
rsInfo: .byte "/", NESPC_TRASH_INFO ; a file per bin entry by its name: the length, then the MCU path it came from
INFO_LEN = * - rsInfo

.segment "SHELL3_BSS"

wbaPaths:  .res 512 ; SRC, then DST at wbaPaths + 256
wbaLen:    .res 2
wbSrcVol:  .res 1 ; VOL_SD
wbNameLen: .res 1 ; wbaName's
wbIsDir:   .res 1 ; list_entry's or find_entry's entry is a folder
wbTopDir:  .res 1 ; the pasted, deleted or renamed entry is
wwIdx:     .res 2 ; list_entry's entry
wwTopIdx:  .res 2 ; paste_go's and del_go's entry of a whole folder
wbDepth:   .res 1
wbaIdxL:   .res DEPTH_MAX ; wwIdx of each folder copy_tree is in
wbaIdxH:   .res DEPTH_MAX
wbBase:    .res 1 ; del_entry's top
wbAll:     .res 1 ; del_go's every entry
wbOldLen:  .res 1 ; ren_go's entry
wbWhich:   .res 1
wbLen:     .res 1
wbAt:      .res 1
wbOp:      .res 1 ; FOP_* for op_note
wbDstTop:  .res 1 ; paste_go's folder, in wbaPath
wbClip:    .res 1 ; 0 for empty, else CLIP_ON | CLIP_*
wbClipVol: .res 1
wbClipLen: .res 1
wbClipDir: .res 1 ; its folder's length
wbaClip:   .res 256 ; the browser's path of the entry, or of the folder for CLIP_ALL
wbaInfo:   .res 256 ; ed_finfo's name
wbaSide:   .res 256 ; side_path's
wbSideLen: .res 1 ; 0 for a name too long to have one
wbaSuffix: .res COPY_LEN ; name_suffix's
wbSufLen:  .res 1
wbDigit:   .res 1 ; bin_entry's "(n)"
wbDirEnd:  .res 1 ; dst_dirs'

.segment "SHELL3"

; the clipboard: the entry in the first Y bytes of wbaPath on volume X, or with CLIP_ALL in A the folder's entries;
; CLIP_CUT moves them on the paste
.proc clip_set
    ora #CLIP_ON
    sta wbClip
    stx wbClipVol
    sty wbClipLen
    sty wbClipDir
    tya
    beq done
:   dey
    lda wbaPath, y
    sta wbaClip, y
    tya
    bne :-
    lda wbClip
    and #CLIP_ALL
    bne done
    ldy wbClipLen ; one entry: its folder ends at the last "/"
:   dey
    lda wbaClip, y
    cmp #'/'
    bne :-
    sty wbClipDir
done:
    rts
.endproc


; > A = the clipboard's CLIP_*, 0 when empty, Z set then
.proc clip_any
    lda wbClip
    rts
.endproc


; the clipboard's entries into the SD card folder in the first Y bytes of wbaPath, a taken name as "name - Copy";
; a cut moves them and empties the clipboard
; > A = status, Z set on success
.proc paste_go
    sty wbDstTop
    lda wbClip
    beq same
    lda wbClipVol
    cmp #VOL_SD
    bne paths
    jsr inside
    bcc home
    lda #FS_E_INSIDE
    rts
home:
    lda wbClip ; one entry cut into its own folder stays as it is
    and #CLIP_ALL | CLIP_CUT
    cmp #CLIP_CUT
    bne paths
    lda wbDstTop
    cmp wbClipDir
    bne paths
    tay
:   dey
    cpy #$ff
    beq same
    lda wbaPath, y
    cmp wbaClip, y
    beq :-
    bne paths
same:
    lda #0
    rts
paths:
    lda wbClipVol
    sta wbSrcVol
    lda #<wbaClip
    ldx #>wbaClip
    ldy wbClipDir
    jsr src_of
    lda #<wbaPath
    ldx #>wbaPath
    ldy wbDstTop
    jsr dst_of
    lda wbClip
    and #CLIP_CUT
    sta wbOp ; FOP_MOVE for a cut
    lda wbClip
    and #CLIP_ALL
    bne all
    ; the entry's name, after its folder in the clipboard
    ldx wbClipDir
    ldy #0
:   inx
    cpx wbClipLen
    beq :+
    lda wbaClip, x
    sta wbaName, y
    iny
    bne :-
:   sty wbNameLen
    lda #0
    sta wbaName, y
    jsr find_entry
    beq :+
    cmp #FR_NO_FILE
    beq gone
    cmp #FR_NO_PATH
    bne done
gone:
    lda #FS_E_GONE
    rts
:   jsr paste_entry
    bne done
    beq used
all:
    lda #0
    sta wwTopIdx
    sta wwTopIdx + 1
next:
    lda wwTopIdx
    sta wwIdx
    lda wwTopIdx + 1
    sta wwIdx + 1
    jsr list_entry
    beq :+
    cmp #FS_END
    bne done
    beq used
:   jsr paste_entry
    bne done
    lda wbClip
    and #CLIP_CUT
    bne next ; the moved entry is gone, the next one in its place
    inc wwTopIdx
    bne next
    inc wwTopIdx + 1
    bne next
used:
    lda wbClip
    and #CLIP_CUT
    beq ok
    lda #0
    sta wbClip
ok:
    lda #0
done:
    rts
.endproc


; > C set when paste_go's folder is the clipboard's entry, or its folder for CLIP_ALL, or under it
.proc inside
    lda wbDstTop
    cmp wbClipLen
    bcc no
    ldy #0
:   cpy wbClipLen
    beq end
    lda wbaPath, y
    cmp wbaClip, y
    bne no
    iny
    bne :-
end:
    cpy wbDstTop
    beq yes
    lda wbaPath, y
    cmp #'/'
    beq yes
no:
    clc
    rts
yes:
    sec
    rts
.endproc


; the entry wbaName in folder SRC copied, or moved for FOP_MOVE, into folder DST, under "name - Copy" when its own
; name is taken there; both paths back as they were on success
; > A = status, Z set on success
.proc paste_entry
    jsr entry_begin
    ldx #SRC
    jsr push_name
    bne done
    ldx #DST
    jsr push_name
    bne done
    jsr dst_claim
    bne done
    jsr copy_entry
    bne done
    lda wbOp
    cmp #FOP_MOVE
    bne back
    jsr del_top
    bne done
back:
    ldx #SRC
    jsr pop_name
    ldx #DST
    jsr pop_name
    lda #0
done:
    rts
.endproc


; a top-level entry's operation starting: wbIsDir kept for del_top, wbOp on the status line
.proc entry_begin
    lda wbIsDir
    sta wbTopDir
    lda wbOp
    far op_note
    rts
.endproc


; the top-level entry entry_begin started on deleted, a folder with everything in it
; > A = status, Z set on success
.proc del_top
    lda wbTopDir
    sta wbIsDir
    jmp del_entry
.endproc


; DST, which ends in its name, made a free name: that, else "name - Copy"
; > A = status, Z set on success, FS_E_EXIST when both are taken
.proc dst_claim
    jsr dst_free
    beq done
    ldx #DST
    jsr path_name
    ldx #DST
    jsr pop_name
    jsr copy_name
    bne done
    ldx #DST
    jsr push_name
    bne done
    jsr dst_free
    beq done
    lda #FS_E_EXIST
done:
    rts
.endproc


; > A = 0, Z set, when nothing is at DST yet; else not 0
.proc dst_free
    lda #<wbaInfo
    sta zpEdBuf
    lda #>wbaInfo
    sta zpEdBuf + 1
    ldx #DST
    jsr path_arg
    jsr ed_finfo
    beq taken
    lda #0
    rts
taken:
    lda #1
    rts
.endproc


; wbaName, wbNameLen long, as "name - Copy", before a file's extension
; > A = status, Z set on success
.proc copy_name
    ldx #COPY_LEN
    stx wbSufLen
:   lda rsCopy - 1, x
    sta wbaSuffix - 1, x
    dex
    bne :-
    jmp name_suffix
.endproc

; as copy_name, "name (A)" for digit A
.proc num_name
    sta wbaSuffix + 2
    lda #' '
    sta wbaSuffix
    lda #'('
    sta wbaSuffix + 1
    lda #')'
    sta wbaSuffix + 3
    lda #4
    sta wbSufLen
    ; [fall_through]
.endproc

; wbaName, wbNameLen long, with wbaSuffix's wbSufLen letters before a file's extension
; > A = status, Z set on success
.proc name_suffix
    lda wbNameLen
    clc
    adc wbSufLen
    bcs long
    sta wbLen
    ldy wbNameLen
    lda wbTopDir
    bne at
:   dey
    beq whole ; ".name" has no extension
    lda wbaName, y
    cmp #'.'
    bne :-
    beq at
whole:
    ldy wbNameLen
at:
    sty wbAt
    ldx wbNameLen ; from its NUL down, wbSufLen up
    ldy wbLen
move:
    lda wbaName, x
    sta wbaName, y
    cpx wbAt
    beq put
    dex
    dey
    jmp move
put:
    ldx #0
    ldy wbAt
:   lda wbaSuffix, x
    sta wbaName, y
    iny
    inx
    cpx wbSufLen
    bne :-
    lda wbLen
    sta wbNameLen
    lda #0
    rts
long:
    lda #FS_E_LONG
    rts
.endproc


; the entry at SRC copied to DST, a folder with everything in it
; > A = status, Z set on success
.proc copy_entry
    lda wbIsDir
    bne dir
    jmp copy_file
dir:
    ldx #DST
    jsr path_arg
    jsr ed_dir_make
    bne done
    jmp copy_tree
done:
    rts
.endproc


; what folder SRC holds copied into folder DST; both paths back as they were on success
; > A = status, Z set on success
.proc copy_tree
    lda #0
    sta wbDepth
    sta wwIdx
    sta wwIdx + 1
next:
    jsr list_entry
    beq got
    cmp #FS_END
    bne done
    ldx wbDepth ; this folder is done
    beq ok
    dex
    stx wbDepth
    lda wbaIdxL, x
    sta wwIdx
    lda wbaIdxH, x
    sta wwIdx + 1
    jsr pop_both
    jmp step
got:
    ldx #SRC
    jsr push_name
    bne done
    ldx #DST
    jsr push_name
    bne done
    lda wbIsDir
    beq file
    ldx #DST
    jsr path_arg
    jsr ed_dir_make
    bne done
    ldx wbDepth
    cpx #DEPTH_MAX
    bcs long
    lda wwIdx
    sta wbaIdxL, x
    lda wwIdx + 1
    sta wbaIdxH, x
    inc wbDepth
    lda #0
    sta wwIdx
    sta wwIdx + 1
    jmp next
file:
    jsr copy_file
    bne done
    jsr pop_both
step:
    inc wwIdx
    bne next
    inc wwIdx + 1
    jmp next
ok:
    lda #0
done:
    rts
long:
    lda #FS_E_LONG
    rts
.endproc


; the file at SRC copied to a new file DST by the MCU
; > A = status, Z set on success
.proc copy_file
    jsr sd_release
    lda #ED_F_FCP
    jsr ed_cmd
    lda #FA_WRITE | FA_CREATE_NEW
    sta FIFO_DATA
    ldx #SRC
    jsr send_path
    ldx #DST
    jsr send_path
    lda #ED_STATUS ; its reply waits for the whole copy
    jsr ed_cmd
    lda #ED_WAIT_COPY
    sta zbEdWait
    jsr ed_reply
    beq done
    cmp #FR_EXIST
    bne done
    lda #FS_E_EXIST
done:
    rts
.endproc


; path X after an MCU command
.proc send_path
    jsr path_arg
    sta zpEdSrc
    stx zpEdSrc + 1
    sty zbEdLen
    jmp send_str
.endproc


; delete the SD card entry in the first A bytes of wbaPath, or with Y not 0 every entry of that folder, folders
; with everything in them
; > A = status, Z set on success
.proc del_go
    sty wbAll
    tay
    lda #VOL_SD
    sta wbSrcVol
    lda #FOP_DEL
    sta wbOp
    lda #<wbaPath
    ldx #>wbaPath
    jsr src_of
    lda wbAll
    bne del_all
    jsr src_name
    jsr src_info
    bne done
    lda wbOp
    far op_note
    jmp del_entry
done:
    rts
.endproc

; every entry of folder SRC deleted, as del_go
; > A = status, Z set on success
.proc del_all
    lda #0
    sta wwIdx
    sta wwIdx + 1
    jsr list_entry
    beq :+
    cmp #FS_END
    bne done
    lda #0
    rts
:   lda wbOp
    far op_note
    ldx #SRC
    jsr push_name
    bne done
    jsr del_entry
    bne done
    ldx #SRC
    jsr pop_name
    jmp del_all
done:
    rts
.endproc


; as del_go in the recycle bin, each entry's origin file deleted with it
; > A = status, Z set on success
.proc bin_del
    sty wbAll
    pha
    lda wbAll
    bne all
    pla
    pha
    tay
    lda #<wbaPath
    ldx #>wbaPath
    jsr src_of
    jsr src_name
    jsr side_path
    pla
    ldy #0
    jsr del_go
    bne done
    jmp side_del
all:
    pla
    ldy #1
    jsr del_go
    bne done
    ldx #INFO_LEN
    stx wbaLen + SRC
:   lda rsInfo - 1, x
    sta wbaPaths - 1, x
    dex
    bne :-
    jsr del_all
    cmp #FR_NO_PATH ; no origins' folder yet
    bne done
    lda #0
done:
    rts
.endproc


; the SD card entry in the first A bytes of wbaPath into the recycle bin, or with Y not 0 every entry of that folder,
; each under its name there or "name (2)" on, its origin kept in nespc/system/trash
; > A = status, Z set on success
.proc bin_go
    ldx #FOP_RECYCLE
    jsr bin_args
    jsr holds_bin
    bcc :+
    lda #FS_E_BIN
    rts
:   jsr bin_make
    bne done
    jmp bin_each
done:
    rts
.endproc


; the recycle bin's entry in the first A bytes of wbaPath, or with Y not 0 every entry of the bin, back where it came
; from, its folders made again, under "name - Copy" when its name is taken there
; > A = status, Z set on success
.proc restore_go
    ldx #FOP_RESTORE
    jsr bin_args
    ; [fall_through]
.endproc

; bin_go's or restore_go's entry, or every entry, of SRC
.proc bin_each
    lda wbAll
    bne all
    jsr src_info
    bne done
    jsr src_name
    ldx #SRC
    jsr pop_name
    jmp entry
all:
    lda #0
    sta wwIdx
    sta wwIdx + 1
    jsr list_entry
    beq :+
    cmp #FS_END
    bne done
    lda #0
    rts
:   jsr entry
    beq all
done:
    rts
entry:
    lda wbOp
    cmp #FOP_RESTORE
    beq :+
    jmp bin_entry
:   jmp restore_entry
.endproc


; SRC = the browser's path in the first A bytes of wbaPath, wbAll = Y, wbOp = X
.proc bin_args
    sty wbAll
    stx wbOp
    tay
    lda #VOL_SD
    sta wbSrcVol
    lda #<wbaPath
    ldx #>wbaPath
    jmp src_of
.endproc


; nespc/trash and nespc/system/trash, made when they aren't there
; > A = status, Z set on success
.proc bin_make
    lda #<rsBin
    ldx #>rsBin
    ldy #BIN_LEN
    jsr ed_dir_make
    bne done
    lda #<rsInfo
    ldx #>rsInfo
    ldy #INFO_LEN
    jmp ed_dir_make
done:
    rts
.endproc


; > C set when SRC is the bin or its origins' folder, or a folder above either
.proc holds_bin
    lda #<rsBin
    ldx #>rsBin
    ldy #BIN_LEN
    jsr above
    bcc :+
    rts
:   lda #<rsInfo
    ldx #>rsInfo
    ldy #INFO_LEN
    ; [fall_through]
.endproc

; > C set when SRC is MCU path A/X (low/high), Y long, or a folder above it
.proc above
    sta zpEdSrc
    stx zpEdSrc + 1
    sty wbLen
    lda wbaLen + SRC
    cmp wbLen
    beq :+
    bcs no
:   ldy #0
:   cpy wbaLen + SRC
    beq at
    lda wbaPaths, y
    cmp (zpEdSrc), y
    bne no
    iny
    bne :-
at:
    cpy wbLen
    beq yes
    lda (zpEdSrc), y
    cmp #'/'
    beq yes
no:
    clc
    rts
yes:
    sec
    rts
.endproc


; entry wbaName of folder SRC moved into the bin under a free name, its origin file written; SRC back as it was
; > A = status, Z set on success
.proc bin_entry
    jsr entry_begin
    ldx #SRC
    jsr push_name
    bne done
    ldx #BIN_LEN
    stx wbaLen + DST
:   lda rsBin - 1, x
    sta wbaPaths + 256 - 1, x
    dex
    bne :-
    ldx #DST
    jsr push_name
    bne done
    jsr dst_free
    beq free
    lda #'2'
    sta wbDigit
next:
    ldx #DST
    jsr pop_name
    jsr src_name
    lda wbDigit
    jsr num_name
    bne done
    ldx #DST
    jsr push_name
    bne done
    jsr dst_free
    beq free
    inc wbDigit
    lda wbDigit
    cmp #'9' + 1
    bne next
    lda #FS_E_EXIST
    rts
free:
    ldx #DST
    jsr path_name
    jsr side_path
    bne done
    jsr copy_entry
    bne done
    jsr side_write
    bne done
    jsr del_top
    bne done
    ldx #SRC
    jsr pop_name
    lda #0
done:
    rts
.endproc


; bin entry wbaName of folder SRC copied back to the path in its origin file, then deleted with that; SRC back as
; it was
; > A = status, Z set on success
.proc restore_entry
    jsr entry_begin
    jsr side_path
    bne done
    ldx #SRC
    jsr push_name
    bne done
    jsr side_read
    bne done
    jsr dst_dirs
    bne done
    jsr dst_claim
    bne done
    jsr copy_entry
    bne done
    jsr del_top
    bne done
    jsr side_del
    bne done
    ldx #SRC
    jsr pop_name
    lda #0
done:
    rts
.endproc


; wbaSide = nespc/system/trash's file for bin entry wbaName
; > A = status, Z set on success
.proc side_path
    ldx #0
    lda wbNameLen
    cmp #256 - INFO_LEN - 1
    bcs long
:   lda rsInfo, x
    sta wbaSide, x
    inx
    cpx #INFO_LEN
    bne :-
    lda #'/'
    sta wbaSide, x
    inx
    ldy #0
:   cpy wbNameLen
    beq :+
    lda wbaName, y
    sta wbaSide, x
    iny
    inx
    bne :-
:   stx wbSideLen
    lda #0
    rts
long:
    stx wbSideLen
    lda #FS_E_LONG
    rts
.endproc


; wbaSide's file: SRC's length, then SRC
; > A = status, Z set on success
.proc side_write
    jsr sd_release
    lda #FA_WRITE | FA_CREATE_ALWAYS
    jsr side_open
    bne done
    lda #<(wbaLen + SRC)
    sta zpEdBuf
    lda #>(wbaLen + SRC)
    sta zpEdBuf + 1
    lda #1
    sta zwEdArg
    jsr ed_fwrite
    bne fail
    lda #<wbaPaths
    sta zpEdBuf
    lda #>wbaPaths
    sta zpEdBuf + 1
    lda wbaLen + SRC
    sta zwEdArg
    jsr ed_fwrite
    bne fail
    jmp ed_fclose
fail:
    pha
    jsr ed_fclose
    pla
done:
    rts
.endproc


; DST = the path in wbaSide's file
; > A = status, Z set on success, FS_E_GONE when there is none
.proc side_read
    jsr sd_release
    lda #FA_READ
    jsr side_open
    beq :+
    cmp #FR_NO_FILE
    beq gone
    cmp #FR_NO_PATH
    bne done
gone:
    lda #FS_E_GONE
done:
    rts
:   lda #<(wbaLen + DST)
    sta zpEdBuf
    lda #>(wbaLen + DST)
    sta zpEdBuf + 1
    lda #1
    sta zwEdArg
    jsr ed_fread
    bne fail
    lda wbaLen + DST
    beq bad
    cmp #PATH_MAX + 1
    bcs bad
    sta zwEdArg
    lda #<(wbaPaths + 256)
    sta zpEdBuf
    lda #>(wbaPaths + 256)
    sta zpEdBuf + 1
    jsr ed_fread
    bne fail
    lda wbaPaths + 256
    cmp #'/'
    bne bad
    jmp ed_fclose
bad:
    lda #FS_E_GONE
fail:
    pha
    jsr ed_fclose
    pla
    rts
.endproc


; open wbaSide's file in mode A, zwEdArg's high byte 0 for side_write and side_read
; > A = status, Z set on success
.proc side_open
    sta zbEdMode
    lda #0
    sta zwEdArg + 1
    lda #<wbaSide
    ldx #>wbaSide
    ldy wbSideLen
    jmp ed_fopen
.endproc


; delete wbaSide's file, there or not
; > A = status, Z set on success
.proc side_del
    ldy wbSideLen
    beq ok
    jsr sd_release
    lda #<wbaSide
    ldx #>wbaSide
    ldy wbSideLen
    jsr ed_fdel
    beq done
    cmp #FR_NO_FILE
    bne done
ok:
    lda #0
done:
    rts
.endproc


; each folder above DST's last name made where it isn't there
; > A = status, Z set on success
.proc dst_dirs
    lda wbaLen + DST
    sta wbDirEnd
    ldy #1
next:
    cpy wbDirEnd
    beq end
    lda wbaPaths + 256, y
    cmp #'/'
    bne step
    sty wbaLen + DST
    sty wbAt
    ldx #DST
    jsr path_arg
    jsr ed_dir_make
    bne fail
    ldy wbAt
step:
    iny
    bne next
end:
    lda #0
fail:
    ldx wbDirEnd
    stx wbaLen + DST
    cmp #0
    rts
.endproc


; rename the SD card entry in the first A bytes of wbaPath, in the folder of its first Y, to wbaEdit, X long
; > A = status, Z set on success
.proc ren_go
    sta wbOldLen
    stx wbNameLen
    lda #VOL_SD
    sta wbSrcVol
    lda #FOP_MOVE
    sta wbOp
    lda #<wbaPath
    ldx #>wbaPath
    jsr dst_of
    lda #<wbaPath
    ldx #>wbaPath
    ldy wbOldLen
    jsr src_of
    ldy #0
:   cpy wbNameLen
    beq :+
    lda wbaEdit, y
    sta wbaName, y
    iny
    bne :-
:   lda #0
    sta wbaName, y
    ldx #DST
    jsr push_name
    bne done
    jsr dst_free
    beq free
    lda #FS_E_EXIST
    rts
free:
    jsr src_info
    bne done
    lda wbIsDir
    sta wbTopDir
    jsr copy_entry
    bne done
    jmp del_top
done:
    rts
.endproc


; the entry at SRC deleted, a folder with everything in it; SRC back as it was on success
; > A = status, Z set on success
.proc del_entry
    lda wbIsDir
    bne dir
    jmp del_src
dir:
    lda wbaLen + SRC
    sta wbBase
loop:
    lda #0
    sta wwIdx
    sta wwIdx + 1
    jsr list_entry
    beq got
    cmp #FS_END
    bne done
    jsr del_src ; emptied: the folder itself
    bne done
    lda wbaLen + SRC
    cmp wbBase
    beq ok
    ldx #SRC
    jsr pop_name
    jmp loop
got:
    ldx #SRC
    jsr push_name
    bne done
    lda wbIsDir
    bne loop
    jsr del_src
    bne done
    ldx #SRC
    jsr pop_name
    jmp loop
ok:
    lda #0
done:
    rts
.endproc


; delete the file or empty folder at SRC
; > A = status, Z set on success
.proc del_src
    jsr sd_release ; the viewer's file may still be open
    ldx #SRC
    jsr path_arg
    jsr ed_fdel
    beq done
    cmp #FR_DENIED
    bne done
    lda #FS_E_RDONLY
done:
    rts
.endproc


; entry wwIdx of folder SRC: its name to wbaName, wbNameLen long, and wbIsDir
; > A = status, Z set on success, FS_END past the last
.proc list_entry
    lda #<wbaName
    sta zpEdBuf
    lda #>wbaName
    sta zpEdBuf + 1
    ldx #SRC
    jsr path_arg
    jsr ed_dir_load
    bne done
    lda wwIdx
    cmp zwEdArg
    lda wwIdx + 1
    sbc zwEdArg + 1
    bcs end
    lda wwIdx
    sta zwEdArg
    lda wwIdx + 1
    sta zwEdArg + 1
    lda #1
    ldx #$ff
    jsr ed_dir_get
    jsr ed_dir_rec
    bne done
    sty wbNameLen
    lda wbaEdInfo + FI_ATTR
    and #AT_DIR
    sta wbIsDir
    lda #0
done:
    rts
end:
    lda #FS_END
    rts
.endproc


; entry wbaName of folder SRC: wbIsDir
; > A = status, Z set on success
.proc find_entry
    ldx #SRC
    jsr push_name
    bne done
    jsr src_info
    php
    pha
    ldx #SRC
    jsr pop_name
    pla
    plp
done:
    rts
.endproc


; wbIsDir for the SD card entry at SRC
; > A = status, Z set on success
.proc src_info
    lda #<wbaInfo
    sta zpEdBuf
    lda #>wbaInfo
    sta zpEdBuf + 1
    ldx #SRC
    jsr path_arg
    jsr ed_finfo
    bne done
    lda wbaEdInfo + FI_ATTR
    and #AT_DIR
    sta wbIsDir
    lda #0
done:
    rts
.endproc


; wbaName, wbNameLen long = the last name in SRC
.proc src_name
    ldx #SRC
    ; [fall_through]
.endproc

; wbaName, wbNameLen long = the last name in path X
.proc path_name
    jsr path_ptr
    sty wbLen
:   dey
    lda (zpEdBuf), y
    cmp #'/'
    bne :-
    ldx #0
:   iny
    cpy wbLen
    beq :+
    lda (zpEdBuf), y
    sta wbaName, x
    inx
    bne :-
:   lda #0
    sta wbaName, x
    stx wbNameLen
    rts
.endproc


.proc src_of
    pha
    lda #SRC
    sta wbWhich
    pla
    jmp mcu_path
.endproc

.proc dst_of
    pha
    lda #DST
    sta wbWhich
    pla
    ; [fall_through]
.endproc

; path wbWhich = the MCU's path of the browser's path A/X (low/high), Y long: "sd/a" is "/a", "sd" empty
.proc mcu_path
    sta zpEdSrc
    stx zpEdSrc + 1
    sty wbLen
    ldy #0
skip:
    cpy wbLen
    beq empty
    lda (zpEdSrc), y
    cmp #'/'
    beq found
    iny
    bne skip
empty:
    lda #0
    ldx wbWhich
    sta wbaLen, x
    rts
found:
    sty wbAt
    clc
    tya
    adc zpEdSrc
    sta zpEdSrc
    bcc :+
    inc zpEdSrc + 1
:   ldx wbWhich
    jsr path_ptr
    lda wbLen
    sec
    sbc wbAt
    sta wbaLen, x
    tay
:   dey
    lda (zpEdSrc), y
    sta (zpEdBuf), y
    tya
    bne :-
    rts
.endproc


; zpEdBuf = path X's bytes, Y = its length
; keeps: X
.proc path_ptr
    lda #<wbaPaths
    sta zpEdBuf
    txa
    clc
    adc #>wbaPaths
    sta zpEdBuf + 1
    ldy wbaLen, x
    rts
.endproc


; > A/X = path X for an MCU command (low/high), Y = its length; "/" for the root
.proc path_arg
    ldy wbaLen, x
    beq root
    txa
    clc
    adc #>wbaPaths
    tax
    lda #<wbaPaths
    rts
root:
    lda #<rsRoot
    ldx #>rsRoot
    ldy #1
    rts
.endproc


; "/" and wbaName, wbNameLen long, after path X
; > A = status, Z set on success
.proc push_name
    stx wbWhich
    lda wbaLen, x
    sec
    adc wbNameLen
    bcs long
    cmp #PATH_MAX + 1
    bcs long
    jsr path_ptr
    lda #'/'
    sta (zpEdBuf), y
    iny
    ldx #0
:   cpx wbNameLen
    beq end
    lda wbaName, x
    sta (zpEdBuf), y
    iny
    inx
    bne :-
end:
    tya
    ldx wbWhich
    sta wbaLen, x
    lda #0
    rts
long:
    lda #FS_E_LONG
    rts
.endproc


; path X without its last name
; keeps: X
.proc pop_name
    jsr path_ptr
:   dey
    lda (zpEdBuf), y
    cmp #'/'
    bne :-
    tya
    sta wbaLen, x
    rts
.endproc


.proc pop_both
    ldx #SRC
    jsr pop_name
    ldx #DST
    jmp pop_name
.endproc
