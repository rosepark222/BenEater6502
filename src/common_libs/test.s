
; ---------------------------------------------
; Set pointer to inode
; Input: A = inode number
; Output: WORK_PTR_LO/HI = address of inode
get_inode_ptr:
    CMP #MAX_INODES
    BCS bad_inode               ; Bounds check
    STA TEMP_INODE_NUM
    LDA TEMP_INODE_NUM
    ASL A
    ASL A
    ASL A
    ASL A                       ; inode * 16
    STA WORK_PTR_LO
    LDA INODE_BASE_HI           ; Read base from zero page
    ADC #0                      ; add carry if any
    STA WORK_PTR_HI
    RTS
bad_inode:
    JMP not_found

; ---------------------------------------------
; Find directory entry in inode and dir data block
; Input:
;   WORK_PTR_LO/HI = pointer to inode
;   TOKEN_BUFFER = search name (null-terminated)
; Output:
;   A = inode number
;   Carry = 0 if found, 1 if not
find_in_dir_block:
    LDY #I_BLOCK0
    LDA (WORK_PTR_LO),Y         ; i_block[0]
    JSR scan_block
    BCC found_entry

    INY
    LDA (WORK_PTR_LO),Y         ; i_block[1]
    JSR scan_block
    BCC found_entry

    INY
    LDA (WORK_PTR_LO),Y         ; i_block[2] = indirect block
    BNE found_indirect_block
    JMP not_found
found_indirect_block:
    STA TEMP_BLOCK_NUM          ; Save indirect block number
    CMP #MAX_INODES
    BCC inode_less_than_max
    JMP not_found
inode_less_than_max:

    LDA TEMP_BLOCK_NUM
    ASL A
    ROL BLOCK_PTR_HI
    ASL A
    ROL BLOCK_PTR_HI
    STA BLOCK_PTR_LO
    LDA BLOCK_PTR_HI
    ORA BLOCK_BASE_HI           ; Read base from zero page
    STA BLOCK_PTR_HI

    LDY #0
next_indirect:
    LDA (BLOCK_PTR_LO),Y
    BEQ skip_indirect
    JSR scan_block
    BCC found_entry
skip_indirect:
    INY
    CPY #$00
    BNE next_indirect

    JMP not_found

found_entry:
    CLC
    RTS

; ------------------------------------------------
; scan_block
; Scan a single directory data block for name match
;
; Input:
;   A    = block number (0..63)
;   TOKEN_BUFFER = null-terminated string to match
;
; Output:
;   A    = inode number of matching entry (if found)
;   Carry = Clear if found, Set if not found
;
; Scratch:
;   SCAN_PTR_LO/HI = address of current directory block
;   TEMP_INODE_NUM = inode number of candidate
;
scan_block:
    CMP #MAX_INODES
    BCS not_found_scan          ; Block number out of range

    TAX                         ; Save block number in X
    LDA #$00
    STA SCAN_PTR_LO             ; Low byte = 0
    TXA
    CLC
    ADC BLOCK_BASE_HI           ; Read base from zero page
    STA SCAN_PTR_HI             ; SCAN_PTR = address of block

    LDY #0                      ; Offset into block

scan_loop:
    LDA (SCAN_PTR_LO),Y         ; Load first byte of entry (inode)
    CMP #$00
    BEQ skip_entry              ; If 0, skip invalid entry

    STA TEMP_INODE_NUM          ; Save inode number

    ; Move Y to name field (offset 2)
    TYA
    CLC
    ADC #DE_NAME
    TAY
    ; init X to 0
    LDX #0
    ; Compare entry name (null-terminated string)
cmp_loop:
    LDA (SCAN_PTR_LO),Y
    CMP TOKEN_BUFFER,X          ; Compare with input string
    BNE skip_entry

    BEQ check_null
check_null:
    CMP #$00
    BEQ found_match             ; Null terminator and matched

    INX
    INY
    JMP cmp_loop

skip_entry:
    ; Round Y down to start of current entry
    TYA
    AND #$F0                    ; Mask out low bits to get base of 16-byte entry
    CLC
    ADC #DIR_ENTRY_SIZE         ; Move to next entry
    TAY
    BNE scan_loop               ; Repeat until wrap (end of block)

not_found_scan:
    SEC
    RTS

found_match:
    LDA TEMP_INODE_NUM          ; Load inode number
    CLC
    RTS


; ---------------------------------------------
; Tokenize next path component
; Input: PATH_PTR_LO/HI = pointer to current path position
; Output: TOKEN_BUFFER = next token (null-terminated)
;         returns with Z = 1 if no more tokens
next_path_token:
    LDY #0
skip_slash:
    LDA (PATH_PTR_LO),Y
    CMP #'/'
    BNE parse_token
    INY
    JMP skip_slash

parse_token:
    LDX #0
next_char:
    LDA (PATH_PTR_LO),Y
    CMP #'/'
    BEQ end_token
    CMP #$00
    BEQ end_token
    STA TOKEN_BUFFER,X
    INY
    INX
    JMP next_char

end_token:
    LDA #0
    STA TOKEN_BUFFER,X
    TYA
    CLC
    ADC PATH_PTR_LO
    STA PATH_PTR_LO             ; update pointer low byte
    LDA PATH_PTR_HI
    ADC #0                      ; propagate carry
    STA PATH_PTR_HI             ; update pointer high byte

    LDA TOKEN_BUFFER            ; check if token is empty
    CMP #0
    RTS

separator:
    LDA #$20 ; #$5F underscore #$20 is space , #$0A = Line Feed
    JSR print_char
    RTS

compare_names:
    ; compare null-terminated TOKEN_BUFFER and Y offset in memory
    ; (not used in final version)
    RTS

not_found:
    ; print "not found"
    RTS