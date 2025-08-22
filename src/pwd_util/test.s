; ---------------------------------------------
; 6502 RAM File System PWD Utility 
; Author: Based on cd_util and ls_util design
; Assumes ls_util is included before this code
; All common functions and variables are defined in ls_util
; ---------------------------------------------


; --- PWD Entry Point ---
; temporary implementation of returning inode 
; no need to print full path for now
start_pwd:
    LDA #' ' 
    JSR print_char
    LDA WORKING_DIR_INODE
    CLC                 ; Clear the Carry flag
    ADC #'0'            ; Add the ASCII value of '0' (e.g., $05 + $30 = $35, which is ASCII for '5')
    JSR print_char
; bug_report -- pwd print inode
; uncomment the below RTS and return the pwd after priting the inode
; , not trying to form the full path
    RTS
    
; bug_report --  the below pwd code has not been debugged
; it supposed to terverse .. to root and stack the directory name
; when it reaches the root, pop them to form the full path
; but it print /? where ? is a garbage

; bug_report -- pwd changes WORKING_DIR_INODE (it should not)
; repeated pwd will change the currently working directory --- funny but why?

    LDA WORKING_DIR_INODE
    BEQ print_root_path         ; If inode 0, just print "/"
    
    ; Initialize stack pointer and reconstruct path
    LDA #0
    STA PWD_STACK_PTR
    
    ; Start with current working directory
    LDA WORKING_DIR_INODE
    STA PWD_TEMP_INODE
    
    ; Traverse up the directory tree, pushing inodes onto stack
traverse_up:
    LDA PWD_TEMP_INODE
    BEQ reconstruct_path        ; If we reach root (inode 0), start reconstruction
    
    ; Push current inode onto stack
    LDY PWD_STACK_PTR
    STA PWD_STACK,Y
    INC PWD_STACK_PTR
    
    ; Get parent inode by looking up ".." entry
    JSR find_parent_inode
    STA PWD_TEMP_INODE
    JMP traverse_up

reconstruct_path:
    ; Start building path from root
    LDA #'/'
    STA PWD_BUFFER
    LDA #0
    STA PWD_BUFFER+1            ; Initialize with just "/" and null terminator
    
    ; Check if stack is empty (we're at root)
    LDA PWD_STACK_PTR
    BEQ print_pwd_result
    
    ; Pop inodes from stack and find their names
    LDX #1                      ; Start at position 1 in buffer (after initial "/")
    
build_path_loop:
    LDA PWD_STACK_PTR
    BEQ print_pwd_result        ; Stack empty, done
    
    DEC PWD_STACK_PTR
    LDY PWD_STACK_PTR
    LDA PWD_STACK,Y             ; Get inode from stack
    STA PWD_TEMP_INODE
    
    ; Find this inode's name in its parent directory
    JSR find_inode_name
    
    ; Copy name to buffer
    JSR copy_name_to_buffer
    
    ; Add trailing slash if not last component
    LDA PWD_STACK_PTR
    BEQ build_path_loop         ; Don't add slash after last component
    
    LDA #'/'
    STA PWD_BUFFER,X
    INX
    
    JMP build_path_loop

print_root_path:
    ; Just print "/" for root directory
    LDA #'/'
    JSR print_char
    LDA #$0A                    ; newline
    JSR print_char
    RTS

print_pwd_result:
    ; Print the reconstructed path
    LDX #0
print_pwd_loop:
    LDA PWD_BUFFER,X
    BEQ print_pwd_newline
    JSR print_char
    INX
    JMP print_pwd_loop
    
print_pwd_newline:
    LDA #$0A                    ; newline
    JSR print_char
    RTS

; --- Find Parent Inode ---
; Input: PWD_TEMP_INODE = current inode
; Output: A = parent inode number
; Uses ls_util's get_inode_ptr and reuses WORK_PTR variables
find_parent_inode:
    LDA PWD_TEMP_INODE
    JSR get_inode_ptr           ; Set pointer to inode in WORK_PTR (from ls_util)
    
    ; Get first data block of directory
    LDY #I_BLOCK0
    LDA (WORK_PTR_LO),Y
    STA TEMP_BLOCK_NUM          ; Reuse ls_util variable
    
    ; Convert block number to address (similar to scan_block in ls_util)
    LDA #$00
    STA SCAN_PTR_LO             ; Low byte = 0 (reuse ls_util variable)
    LDA TEMP_BLOCK_NUM
    CLC
    ADC BLOCK_BASE_HI           ; Read base from zero page (ls_util)
    STA SCAN_PTR_HI             ; SCAN_PTR = address of block
    
    ; Look for ".." entry (should be second entry at offset $10)
    LDY #$10                    ; Offset to second directory entry
    LDA (SCAN_PTR_LO),Y         ; Get inode number from ".." entry
    RTS

; --- Find Inode Name in Parent Directory ---
; Input: PWD_TEMP_INODE = inode to find name for
; Result: Name stored in TOKEN_BUFFER (reusing ls_util buffer)
; Uses ls_util functions and variables
find_inode_name:
    ; First get the parent inode
    LDA PWD_TEMP_INODE
    PHA                         ; Save target inode
    
    JSR find_parent_inode       ; Get parent inode in A
    JSR get_inode_ptr           ; Set pointer to parent inode (ls_util)
    
    ; Get first data block of parent directory  
    LDY #I_BLOCK0
    LDA (WORK_PTR_LO),Y
    STA TEMP_BLOCK_NUM          ; Reuse ls_util variable
    
    ; Convert block number to address (similar to scan_block)
    LDA #$00
    STA SCAN_PTR_LO             ; Low byte = 0
    LDA TEMP_BLOCK_NUM
    CLC
    ADC BLOCK_BASE_HI           ; Read base from zero page
    STA SCAN_PTR_HI             ; SCAN_PTR = address of block
    
    PLA                         ; Restore target inode
    STA PWD_TEMP_INODE
    
    ; Search directory entries for matching inode (similar to scan_block logic)
    LDY #0                      ; Start at first entry
    
search_dir_entries:
    LDA (SCAN_PTR_LO),Y         ; Get inode number from entry
    CMP PWD_TEMP_INODE
    BEQ found_entry_pwd             ; Found matching inode
    
    ; Skip to next entry (16 bytes each, like ls_util DIR_ENTRY_SIZE)
    TYA
    CLC
    ADC #DIR_ENTRY_SIZE         ; Use ls_util constant
    TAY
    BNE search_dir_entries      ; Continue if not wrapped around
    
    ; Entry not found - shouldn't happen in valid filesystem
    RTS

found_entry_pwd:
    ; Copy name from directory entry to TOKEN_BUFFER (reuse ls_util buffer)
    TYA
    CLC
    ADC #DE_NAME                ; Skip to name field (ls_util constant)
    TAY
    
    LDX #0
copy_name_loop:
    LDA (SCAN_PTR_LO),Y
    BEQ name_copied
    STA TOKEN_BUFFER,X          ; Reuse ls_util buffer
    INY
    INX
    CPX #14                     ; Max name length
    BNE copy_name_loop
    
name_copied:
    LDA #0
    STA TOKEN_BUFFER,X          ; Null terminate
    RTS

; --- Copy Name to PWD Buffer ---
; Input: X = current position in PWD_BUFFER
; Uses: TOKEN_BUFFER contains name to copy (ls_util buffer)
; Output: X = updated position in PWD_BUFFER
copy_name_to_buffer:
    LDY #0
copy_to_buffer_loop:
    LDA TOKEN_BUFFER,Y          ; Read from ls_util buffer
    BEQ copy_to_buffer_done
    STA PWD_BUFFER,X
    INY
    INX
    JMP copy_to_buffer_loop
    
copy_to_buffer_done:
    LDA #0
    STA PWD_BUFFER,X            ; Null terminate
    RTS