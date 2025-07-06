; ---------------------------------------------
; 6502 RAM File System LS Utility
; Author: ChatGPT (based on your FS design)
; ---------------------------------------------
; Memory Layout Assumptions:
; - Path string starts at fixed address $0400
; - RAM scratch:
;     $0200-$020F: path token buffer
;     $0210: current inode number
;     $0220-$022F: inode buffer (16 bytes)
;     $0300-$03FF: data block buffer (256B)
;     $0010/$0011: zero-page pointer to path string (used by tokenizer)
; ---------------------------------------------

;/.segment "CODE"

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
    JSR get_inode        ; Load inode into $0220

    JSR find_in_dir      ; Look for token in this directory
    BCS not_found

    STA $0210            ; Found! Update inode number
    JMP next_token

done_resolving:
    LDA $0210
    JSR get_inode
    
    LDA $0220            ; i_mode
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
; Get inode
; Input: A = inode number
; Output: $0220-$022F filled
get_inode:
    STA $00
    LDA #$00
    STA $01
    LDA $00
    ASL A
    ASL A
    ASL A
    ASL A                 ; inode * 16
    CLC
    ADC #$00
    STA $02
    LDA #$BC              ; inode base = 0xBC00
    ADC #$00              ; carry from low byte add
    STA $03

    LDY #0
get_inode_loop:
    LDA ($02),Y
    STA $0220,Y
    INY
    CPY #16
    BNE get_inode_loop
    RTS

; ---------------------------------------------
; Find directory entry
; Input:
;   $0220 = inode
;   $0200 = search name (null-terminated)
; Output:
;   A = inode number
;   Carry = 0 if found, 1 if not
find_in_dir:
    LDA $0226              ; i_block[0]
    JSR load_block
    LDY #0
find_loop:
    LDA $0301,Y           ; file type
    CMP #$FF              ; unused?
    BEQ find_next

    ; Compare name
    LDA #14
    STA $04
    LDX #0
cmp_loop:
    LDA $0302,Y
    CMP $0200,X
    BNE find_next
    INX
    INY
    DEC $04
    BNE cmp_loop

    ; Match!
    SEC
    LDA $0300,Y
    CLC
    RTS

find_next:
    TYA
    CLC
    ADC #16
    TAY
    CPY #$00
    BNE find_loop
    SEC
    RTS

; ---------------------------------------------
; Load data block
; Input: A = block number
; Output: data in $0300-$03FF
load_block:
    STA $05
    ; Assume blocks start at $C000 (block 0)
    ASL A
    ROL $06
    ASL A
    ROL $06
    STA $07
    LDA $06
    ORA #$C0
    STA $06
    LDY #0
load_loop:
    LDA ($06),Y
    STA $0300,Y
    INY
    BNE load_loop
    RTS

; ---------------------------------------------
; Print directory contents
print_dir:
    LDA $0226
    JSR load_block
    LDY #0
print_loop:
    LDA $0300,Y           ; inode number
    CMP #$FF
    BEQ print_next

    ; Print name at $0302,Y
    ; Assume you have a print_string subroutine
    LDX #0
print_name:
    LDA $0302,Y
    JSR print_char        ; your print_char routine
    INX
    INY
    CPX #14
    BNE print_name
    JSR newline

print_next:
    TYA
    CLC
    ADC #16
    TAY
    CPY #$00
    BNE print_loop
    RTS

; ---------------------------------------------
; Print file info
print_file_info:
    ; file size = $0222:$0223
    ; ctime     = $0224:$0225
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
    RTS
newline:
    LDA #$0A
    JSR print_char
    RTS

compare_names:
    ; compare null-terminated $0200 and Y offset in memory
    ; (not used in final version)
    RTS
