; ---------------------------------------------
; 6502 RAM File System LS Utility
; Author: ChatGPT (based on your FS design)
; ---------------------------------------------

; === Memory Layout Symbols ===
; Zero Page Usage
PATH_PTR_LO     = $10           ; Low byte of path string pointer
PATH_PTR_HI     = $11           ; High byte of path string pointer
; Note: INODE_BASE_HI = $12 and BLOCK_BASE_HI = $13 defined in rom_fs.s

; Scratch Memory
TOKEN_BUFFER    = $0200         ; $0200-$020F: path token buffer (16 bytes)
CURRENT_INODE   = $0210         ; Current inode number during traversal
TEMP_BLOCK_NUM  = $0211         ; Temporary block number storage
TEMP_INODE_NUM  = $0212         ; Temporary inode number storage

; Working Pointers (used by various routines)
WORK_PTR_LO     = $00           ; General purpose pointer low byte
WORK_PTR_HI     = $01           ; General purpose pointer high byte
BLOCK_PTR_LO    = $02           ; Block pointer low byte
BLOCK_PTR_HI    = $03           ; Block pointer high byte
DIR_PTR_LO      = $04           ; Directory scanning pointer low
DIR_PTR_HI      = $05           ; Directory scanning pointer high
SCAN_PTR_LO     = $06           ; Scan block pointer low byte
SCAN_PTR_HI     = $07           ; Scan block pointer high byte

; Input/Output
PATH_INPUT      = $0400         ; Input path string buffer
PRINT_CHAR_ADDR = $6000         ; Character output address

; File System Constants
MAX_INODES      = 64            ; Maximum number of inodes
MAX_DATABLOCK   = 64            ; Maximum number of inodes
INODE_SIZE      = 16            ; Size of each inode in bytes
DIR_ENTRY_SIZE  = 16            ; Size of directory entry
BLOCK_SIZE      = 256           ; Size of data block

; Inode Structure Offsets
I_MODE          = 0             ; File type and permissions
I_UID           = 1             ; User ID
I_SIZE_LO       = 2             ; File size low byte
I_SIZE_HI       = 3             ; File size high byte
I_BLOCK0        = 6             ; Direct block 0
I_BLOCK1        = 7             ; Direct block 1  
I_BLOCK2        = 8             ; Indirect block

; Directory Entry Structure Offsets
DE_INODE        = 0             ; Inode number
DE_TYPE         = 1             ; Type
DE_NAME         = 2             ; Start of filename

; File Type Masks
FT_FILE         = %00000000     ; Regular file
FT_DIR          = %00010000     ; Directory

; ---------------------------------------------
simulate_ls:
    JSR prepare_path
    LDA #$FF
    PHA
    PHA
    PHA
    BRK                         ; Exit simulation
    RTS

; --- Prepare Path String ---
prepare_path:
    LDX #$00
copyLoop:
    LDA rom_bin,X               ; Load byte from ROM string
    STA PATH_INPUT,X            ; Store to RAM path buffer
    BEQ start_ls                ; If null terminator, jump to ls
    INX
    JMP copyLoop

; --- Entry Point ---
start_ls:
    LDA #<PATH_INPUT
    STA PATH_PTR_LO             ; zero-page low byte of path pointer
    LDA #>PATH_INPUT
    STA PATH_PTR_HI             ; zero-page high byte of path pointer

    LDA #0
    STA CURRENT_INODE           ; Start from root inode 0

next_token:
    JSR next_path_token         ; Extract next path component into TOKEN_BUFFER
    BEQ done_resolving          ; If empty, done traversing

    LDA CURRENT_INODE
    JSR get_inode_ptr           ; Set pointer to inode address in WORK_PTR

    ; --- if current inode is file, do not search in its data block
    LDY #I_MODE
    LDA (WORK_PTR_LO),Y
    AND #%11110000
    CMP #FT_DIR
    BNE not_found

    JSR find_in_dir_block             ; Look for token in this directory
    BCS not_found

    STA CURRENT_INODE           ; Found! Update inode number
    JMP next_token

done_resolving:
    LDA CURRENT_INODE
    JSR get_inode_ptr

    LDY #I_MODE
    LDA (WORK_PTR_LO),Y
    AND #%11110000
    CMP #FT_DIR                 ; Directory?
    BEQ do_ls_dir

    CMP #FT_FILE                ; Regular file?
    BEQ do_ls_file

    JMP unknown_type

do_ls_dir:
    ;JSR clear_newline_and_move
    JSR print_dir
    RTS

do_ls_file:
    ;JSR clear_newline_and_move
    JSR print_file_info
    RTS

not_found:
    ; print "not found"
    RTS

unknown_type:
    ; print "unknown type"
    RTS

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
    BEQ not_found
    STA TEMP_BLOCK_NUM          ; Save indirect block number
    CMP #MAX_INODES
    BCS not_found

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
; Print directory contents
print_dir:
    LDY #I_BLOCK0
    LDA (WORK_PTR_LO),Y
    JSR print_block             ; direct block 1
    LDY #I_BLOCK1
    LDA (WORK_PTR_LO),Y
    JSR print_block             ; direct block 2
    RTS


print_block:
    CMP #MAX_DATABLOCK
    BCS skip_block
    TAX                         ; Save block number in X
    LDA #$00
    STA DIR_PTR_LO 
    TXA
    CLC
    ADC BLOCK_BASE_HI           ; Read base from zero page
    STA DIR_PTR_HI              ; DIR_PTR = address of block

    LDY #0
print_loop:
    LDA (DIR_PTR_LO),Y          ; inode number
    CMP #INVALID_INODE
    BEQ print_next              ; invalid or empty inode, skip to next entry

    JSR separator                 ; space between names
    ; Move Y to name field (offset 2)
    TYA
    CLC
    ADC #DE_NAME
    TAY
    
 summer_break:

print_name:
    LDA (DIR_PTR_LO),Y          ; name string , null ending
    BEQ print_next              ; null -> next entry
    JSR print_char
    INY
    BNE print_name

print_next:
    ; JSR separator
    ; Round Y down to start of current entry
    TYA
    AND #$F0                    ; Mask out low bits to get base of 16-byte entry
    CLC
    ADC #DIR_ENTRY_SIZE         ; Move to next entry
    TAY
    CPY #$00                    ; check all 16 entries are printed
    BNE print_loop
skip_block:
    RTS

; ---------------------------------------------
; Print file info
print_file_info:
    ; For now, just print "FILE"
    LDX #0
    LDY #$00
    LDA #'F'
    JSR print_char
    LDA #'I'
    JSR print_char
    LDA #'L'
    JSR print_char
    LDA #'E'
    JSR print_char
    JSR separator
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

; --- Stub routines ---
; remove this because it is defined in shell
; print_char:
;    ; your character output
;    STA PRINT_CHAR_ADDR
;    RTS

separator:
    LDA #$20 ; #$5F underscore #$20 is space , #$0A = Line Feed
    JSR print_char
    RTS

compare_names:
    ; compare null-terminated TOKEN_BUFFER and Y offset in memory
    ; (not used in final version)
    RTS

; --- ROM String ---
rom_bin:
    .byte "/rom", 0
;    .byte "/rom/bin", 0
;    .byte "/", 0 ; 
;    ls / works -- because next_path_token returns null, and jumps to done_resolving and CURRENT_INODE still holds 0, which is root inode