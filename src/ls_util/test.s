 


 ; ---------------------------------------------
; 6502 RAM File System LS Utility
; Author: ChatGPT (based on your FS design)
; ---------------------------------------------
; Memory Layout Assumptions:
; - Path string starts at fixed address $0400
; - RAM scratch:
;     $0200-$020F: path token buffer
;     $0210: current inode number
;     $0010/$0011: zero-page pointer to path string (used by tokenizer)
; - No block/inode copying: data is accessed directly in place
; ---------------------------------------------
; assume inode base = 0xBC00
; assume blocks start at base $C000 (block 0)
; ---------------------------------------------
simulate_ls:
    ;LDA #<input_cmd
    ;PHA
    ;LDA #>input_cmd
    ;PHA
    JSR prepare_path
    LDA #$FF
    PHA
    PHA
    PHA
    BRK                  ; if prepare_path is done, code exit the simulation 
    RTS

; --- Prepare Path String ---
prepare_path:
    LDX #$00
copyLoop:
    LDA rom_bin,X        ; Load byte from ROM string
    STA $0400,X          ; Store to RAM path buffer
    BEQ start_ls         ; If null terminator, jump to ls
    INX
    JMP copyLoop

; --- Entry Point ---
start_ls:
    LDA #<$0400
    STA $10              ; zero-page low byte of path pointer
    LDA #>$0400
    STA $11              ; zero-page high byte of path pointer

    LDA #0
    STA $0210            ; Start from root inode 0

next_token:
    JSR next_path_token  ; Extract next path component into $0200
    BEQ done_resolving   ; If empty, done traversing

    LDA $0210
    JSR get_inode_ptr    ; Set pointer to inode address in $00/$01

    JSR find_in_dir      ; Look for token in this directory
    BCS not_found

    STA $0210            ; Found! Update inode number
    JMP next_token

done_resolving:
    LDA $0210
    JSR get_inode_ptr

    LDY #0
    LDA ($00),Y
    AND #%11110000
    CMP #%00010000       ; Directory?
    BEQ do_ls_dir

    CMP #%00000000       ; Regular file?
    BEQ do_ls_file

    JMP unknown_type

do_ls_dir:
    JSR print_dir
    RTS

do_ls_file:
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
; Output: $00/$01 = address of inode
get_inode_ptr:
    CMP #64
    BCS bad_inode        ; Bounds check
    STA $02
    LDA $02
    ASL A
    ASL A
    ASL A
    ASL A                 ; inode * 16
    STA $00
    LDA #$BC              ; base address $BC00
    ADC #0                ; add carry if any
    STA $01
    RTS
bad_inode:
    JMP not_found

; ---------------------------------------------
; Find directory entry
; Input:
;   $00/$01 = pointer to inode
;   $0200 = search name (null-terminated)
; Output:
;   A = inode number
;   Carry = 0 if found, 1 if not
find_in_dir:
    LDY #6
    LDA ($00),Y          ; i_block[0]
    JSR scan_block
    BCC found_entry

    INY
    LDA ($00),Y          ; i_block[1]
    JSR scan_block
    BCC found_entry

    INY
    LDA ($00),Y          ; i_block[2] = indirect block
    BEQ not_found
    STA $02              ; Save indirect block number
    CMP #64
    BCS not_found

    LDA $02
    ASL A
    ROL $03
    ASL A
    ROL $03
    STA $04
    LDA $03
    ORA #$C0
    STA $03

    LDY #0
next_indirect:
    LDA ($03),Y
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
;   $0200 = null-terminated string to match
;
; Output:
;   A    = inode number of matching entry (if found)
;   Carry = Clear if found, Set if not found
;
; Scratch:
;   $06/$07 = address of current directory block
;   $05 = inode number of candidate
;
scan_block:
    CMP #64
    BCS not_found_scan        ; Block number out of range

    TAX                       ; Save block number in X
    LDA #$00
    STA $06                   ; Low byte = 0
    TXA
    CLC
    ADC #$C0                  ; High byte = $C0 + block number
    STA $07                   ; $07:$06 = address of block

    LDY #0                    ; Offset into block

scan_loop:
    LDA ($06),Y              ; Load first byte of entry (inode)
    CMP #$00
    BEQ skip_entry           ; If 0, skip invalid entry

    STA $05                  ; Save inode number to $05

    ; Move Y to name field (offset 2)
    TYA
    CLC
    ADC #2
    TAY
    ; init X to 0
    LDX #0
    ; Compare entry name (null-terminated string)
cmp_loop:
    LDA ($06),Y
    CMP $0200,X              ; Compare with input string
    BNE skip_entry

    BEQ check_null
check_null:
    CMP #$00
    BEQ found_match          ; Null terminator and matched

    INX
    INY
    JMP cmp_loop

skip_entry:
    ; Round Y down to start of current entry
    TYA
    AND #$F0                ; Mask out low bits to get base of 16-byte entry
    CLC
    ADC #$10               ; Move to next entry
    TAY
    BNE scan_loop          ; Repeat until wrap (end of block)

not_found_scan:
    SEC
    RTS

found_match:
    LDA $05                 ; Load inode number
    CLC
    RTS

; ---------------------------------------------
; Print directory contents
print_dir:
    LDY #6
    LDA ($00),Y
    JSR print_block         ; direct block 1
    INY
    LDA ($00),Y
    JSR print_block         ; direct block 2
    RTS

print_block:
    CMP #64
    BCS skip_block
    TAX                       ; Save block number in X
    LDA #$00
    STA $02 
    TXA
    CLC
    ADC #$C0                  ; High byte = $C0 + block number
    STA $03                   ; $02:$03 = address of block

    LDY #0
print_loop:
    LDA ($02),Y           ; inode number
    CMP #$0
    BEQ print_next

    ; Move Y to name field (offset 2)
    TYA
    CLC
    ADC #2
    TAY
;    LDX #0
print_name:
    LDA ($02),Y
    BEQ print_next     ; null -> next entry
    JSR print_char
    INY
    BNE print_name

print_next:
    JSR newline
    ; Round Y down to start of current entry
    TYA
    AND #$F0                ; Mask out low bits to get base of 16-byte entry
    CLC
    ADC #$10               ; Move to next entry
    TAY
    CPY #$00               ; check all 16 entries are printed
    BNE print_loop
skip_block:
    RTS

; ---------------------------------------------
; Print file info
print_file_info:
    ; For now, just print "file"
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
    JSR newline
    RTS

; ---------------------------------------------
; Tokenize next path component
; Input: ($10) = pointer to current path position
; Output: $0200 = next token (null-terminated)
;         returns with Z = 1 if no more tokens
next_path_token:
    LDY #0
skip_slash:
    LDA ($10),Y
    CMP #'/'
    BNE parse_token
    INY
    JMP skip_slash

parse_token:
    LDX #0
next_char:
    LDA ($10),Y
    CMP #'/'
    BEQ end_token
    CMP #$00
    BEQ end_token
    STA $0200,X
    INY
    INX
    JMP next_char

end_token:
    LDA #0
    STA $0200,X
    TYA
    CLC
    ADC $10
    STA $10              ; update pointer low byte
    LDA $11
    ADC #0               ; propagate carry
    STA $11              ; update pointer high byte

    LDA $0200            ; check if token is empty
    CMP #0
    RTS

; --- Stub routines ---
print_char:
    ; your character output
    STA $6000
    RTS
newline:
    LDA #$0A
    JSR print_char
    RTS

compare_names:
    ; compare null-terminated $0200 and Y offset in memory
    ; (not used in final version)
    RTS

; --- ROM String ---
rom_bin:
    .byte "/rom", 0
;    .byte "/rom/bin", 0
;    .byte "/", 0 ; 
;    ls / works -- because next_path_token returns null, and jumps to done_resolving and  $0210 still holds 0, which is root inode

