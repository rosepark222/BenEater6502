; ---------------------------------------------
; 6502 RAM File System CD Utility (Minimal Version)
; Author: Based on ls_util design
; Assumes ls_util is included before this code
; All common functions and variables are defined in ls_util
; ---------------------------------------------


; bug_report -- cd .. and cd . has not been fully debugged
; at rom/bin cd .. bring pwd to rom
; at rom cd .. say not found but bring pwd to rom/bin  -- very funny


; --- CD Entry Point ---
start_cd:
;summer_break:
    LDA #<PATH_INPUT
    STA PATH_PTR_LO             ; zero-page low byte of path pointer
    LDA #>PATH_INPUT
    STA PATH_PTR_HI             ; zero-page high byte of path pointer

    ; Check if path starts with '/' (absolute path)
    LDY #0
    LDA (PATH_PTR_LO),Y
    CMP #'/'
    BEQ absolute_path_cd
    
    ; Relative path - start from current working directory
    LDA WORKING_DIR_INODE
    STA CURRENT_INODE
    JMP resolve_path_cd

absolute_path_cd:
    ; Absolute path - start from root
    LDA #1
    STA CURRENT_INODE           ; Start from root inode 0

resolve_path_cd:
next_token_cd:
    JSR next_path_token         ; Extract next path component into TOKEN_BUFFER
    BEQ done_resolving_cd          ; If empty, done traversing

    ; ; Check for special directories
    ; JSR check_dot_dirs
    ; BCC handle_special          ; Carry clear means special directory handled
    
    LDA CURRENT_INODE
    JSR get_inode_ptr           ; Set pointer to inode address in WORK_PTR

    ; --- if current inode is file, cannot cd into it
    LDY #I_MODE
    LDA (WORK_PTR_LO),Y
    AND #%11110000
    CMP #FT_DIR
    BNE path_not_found

    JSR find_in_dir_block       ; Look for token in this directory
    BCS path_not_found

    STA CURRENT_INODE           ; Found! Update inode number
    JMP next_token_cd

handle_special:
    ; CURRENT_INODE already updated by check_dot_dirs
    JMP next_token_cd

done_resolving_cd:
    ; Verify final target is a directory
    LDA CURRENT_INODE
    JSR get_inode_ptr

    LDY #I_MODE
    LDA (WORK_PTR_LO),Y
    AND #%11110000
    CMP #FT_DIR                 ; Directory?
    BNE path_not_found

    ; Success! Update working directory
    JSR cd_ok_print
    LDA CURRENT_INODE
    STA WORKING_DIR_INODE
    RTS

cd_ok_print:
    LDX #0
cd_ok_loop:
    LDA cd_ok_msg, X
    BEQ cd_ok_done
    JSR print_char
    INX
    JMP cd_ok_loop
cd_ok_done:
    RTS

path_not_found:
    LDX #0
path_not_found_loop:
    LDA path_not_found_msg,X
    BEQ path_not_found_done
    JSR print_char
    INX
    JMP path_not_found_loop
path_not_found_done:
    RTS



; ---------------------------------------------
; Get current working directory inode
; Output: A = current working directory inode number
get_working_dir:
    LDA WORKING_DIR_INODE
    RTS

; --- Messages ---
cd_ok_msg:
    .byte " ok", 0
path_not_found_msg:
    .byte " cd_fail", 0

; --- ROM String for testing ---
; rom_bin_cd:
;     .byte "/rom/bin", 0         ; Test path
;    .byte "..", 0              ; Test parent directory
;    .byte "bin", 0             ; Test relative path