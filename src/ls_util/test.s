; ---------------------------------------------
; 6502 RAM File System LS Utility
; Author: ChatGPT (based on your FS design)
; ---------------------------------------------



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

    ; CHANGE 1: Check if path is empty (ls with no arguments) ; pwd support
    LDY #0
    LDA (PATH_PTR_LO),Y
    CMP #0
    BEQ ls_current_dir          ; Empty path = list current directory ; pwd support

    ; CHANGE 2: Check if path starts with '/' (absolute vs relative) ; pwd support
    CMP #'/'
    BEQ absolute_path
    
    ; Relative path - start from current working directory ; pwd support
    LDA WORKING_DIR_INODE
    STA CURRENT_INODE
    JMP resolve_path

absolute_path:
    ; Absolute path - start from root ; pwd support
    LDA #0
    STA CURRENT_INODE           ; Start from root inode 0
    JMP resolve_path

ls_current_dir:
    ; CHANGE 3: List current working directory ; pwd support
    LDA WORKING_DIR_INODE
    STA CURRENT_INODE
    JMP done_resolving

resolve_path: ; pwd support
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
    BNE ls_not_found

    JSR find_in_dir_block             ; Look for token in this directory
    BCS ls_not_found

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

ls_not_found:
    ; print "not found"
    RTS

unknown_type:
    ; print "unknown type"
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

; --- ROM String ---
rom_bin:
    .byte "/rom", 0
;    .byte "/rom/bin", 0
;    .byte "/", 0 ; 
;    ls / works -- because next_path_token returns null, and jumps to done_resolving and CURRENT_INODE still holds 0, which is root inode