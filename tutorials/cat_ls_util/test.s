;--------------------------------------------------
; 6502 Assembly: Combined cat + ls utility (Fixed Branch Range Errors)
;--------------------------------------------------

zp_string_ptr = $00
zp_path_ptr   = $02
zp_inode_ptr  = $04
zp_device_id  = $06
zp_block_ptr  = $07
zp_temp_ptr   = $08

;--------------------------------------------------
; Shared Entry Point: Parses command and dispatches to cat or ls
;--------------------------------------------------
main:
    LDX #0
    LDA $0300,X
    CMP #'c'
    BNE check_ls
    INX
    LDA $0300,X
    CMP #'a'
    BNE check_ls
    INX
    LDA $0300,X
    CMP #'t'
    BNE check_ls
    JMP cat

check_ls:
    LDX #0
    LDA $0300,X
    CMP #'l'
    BNE invalid
    INX
    LDA $0300,X
    CMP #'s'
    BNE invalid
    JMP ls

invalid:
    RTS

;--------------------------------------------------
ls:
    LDA zp_path_ptr
    STA $10
    LDA zp_path_ptr+1
    STA $11
    LDA #0
    STA $0210

ls_next_token:
    JSR next_path_token
    BEQ ls_done_resolving
    LDA $0210
    JSR get_inode_ptr
    JSR find_in_dir
    BCS ls_not_found_branch
    STA $0210
    JMP ls_next_token
ls_not_found_branch:
    JMP not_found

ls_done_resolving:
    LDA $0210
    JSR get_inode_ptr
    LDY #0
    LDA ($00),Y
    AND #%11110000
    CMP #%00010000
    BEQ do_ls_dir
    CMP #%00000000
    BEQ do_ls_file
    JMP not_found

do_ls_dir:
    JSR print_dir
    RTS

do_ls_file:
    JSR print_file_info
    RTS

;--------------------------------------------------
cat:
    LDA zp_path_ptr
    STA $10
    LDA zp_path_ptr+1
    STA $11
    LDA #0
    STA $0210

next_token:
    JSR next_path_token
    BEQ done_resolving
    LDA $0210
    JSR get_inode_ptr
    JSR find_in_dir
    BCS cat_not_found_branch
    STA $0210
    JMP next_token
cat_not_found_branch:
    JMP not_found

done_resolving:
    LDA $0210
    JSR get_inode_ptr
    LDA $00
    STA zp_inode_ptr
    LDA $01
    STA zp_inode_ptr+1

    LDY #0
    LDA ($00),Y
    AND #%11110000
    CMP #%00100000
    BEQ cat_to_device
    CMP #%00000000
    BEQ cat_to_file
    JMP cat_error

cat_to_device:
    LDY #7
    LDA (zp_inode_ptr),Y
    STA zp_device_id
    JSR device_write_dispatch
    RTS

cat_to_file:
    LDY #5
    LDA (zp_inode_ptr),Y
    STA zp_block_ptr
    LDA zp_block_ptr
    ASL
    TAY
    LDA file_block_table,Y
    STA zp_temp_ptr
    LDA file_block_table+1,Y
    STA zp_temp_ptr+1
    JSR copy_string_to_block
    RTS

cat_error:
    RTS

copy_string_to_block:
    LDY #0
.copy_loop:
    LDA (zp_string_ptr),Y
    BEQ .done
    STA (zp_temp_ptr),Y
    INY
    BNE .copy_loop
.done:
    RTS

;--------------------------------------------------
print_dir:
    LDY #6
    LDA ($00),Y
    JSR print_block
    INY
    LDA ($00),Y
    JSR print_block
    RTS

print_block:
    CMP #64
    BCS skip_block
    ASL A
    ROL $02
    ASL A
    ROL $02
    STA $03
    LDA $02
    ORA #$C0
    STA $02
    LDY #0
print_loop:
    LDA ($02),Y
    CMP #$FF
    BEQ print_next
    LDX #0
print_name:
    LDA ($02),Y
    JSR print_char
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
skip_block:
    RTS

print_file_info:
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

;--------------------------------------------------
; Common FS logic and LCD handler (unchanged, below this point)
;--------------------------------------------------
; [get_inode_ptr, find_in_dir, scan_block, next_path_token, device_write_dispatch, lcd_write_handler, etc. remain unchanged as in prior version. If you want these shown inline again, just ask.]

get_inode_ptr:
    CMP #64
    BCS bad_inode
    STA $02
    LDA $02
    ASL
    ASL
    ASL
    ASL
    STA $00
    LDA #$BC
    ADC #0
    STA $01
    RTS
bad_inode:
    JMP not_found

find_in_dir:
    LDY #6
    LDA ($00),Y
    JSR scan_block
    BCC found_entry
    INY
    LDA ($00),Y
    JSR scan_block
    BCC found_entry
    INY
    LDA ($00),Y
    BEQ not_found_dir
    STA $02
    CMP #64
    BCS not_found_dir
    LDA $02
    ASL
    ROL $03
    ASL
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
not_found_dir:
    JMP not_found

scan_block:
    CMP #64
    BCS not_found_scan
    ASL
    ROL $06
    ASL
    ROL $06
    STA $07
    LDA $06
    ORA #$C0
    STA $06
    LDY #0
scan_loop:
    LDA ($06),Y
    CMP #$FF
    BEQ scan_next
    LDA #14
    STA $04
    LDX #0
cmp_loop:
    LDA ($06),Y
    CMP $0200,X
    BNE scan_next
    INX
    INY
    DEC $04
    BNE cmp_loop
    LDA ($06),Y
    SEC
    CLC
    RTS
scan_next:
    TYA
    CLC
    ADC #16
    TAY
    CPY #$00
    BNE scan_loop
not_found_scan:
    SEC
    RTS

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
    STA $10
    LDA $11
    ADC #0
    STA $11
    LDA $0200
    CMP #0
    RTS

;--------------------------------------------------
; LCD device driver handler
;--------------------------------------------------
device_write_dispatch:
    LDA zp_device_id
    ASL
    TAY
    LDA device_write_table,Y
    STA zp_temp_ptr
    LDA device_write_table+1,Y
    STA zp_temp_ptr+1
    JMP (zp_temp_ptr)

device_write_table:
    .word lcd_write_handler

lcd_write_handler:
    LDY #0
.loop:
    LDA (zp_string_ptr),Y
    BEQ .done
    CMP #'\'
    BNE .normal
    INY
    LDA (zp_string_ptr),Y
    CMP #'n'
    BEQ .newline
    CMP #'r'
    BEQ .carriage
    CMP #'c'
    BEQ .clear
    JMP .next
.normal:
    STA $D100
    JMP .next
.newline:
    LDA #$C0
    STA $D101
    JMP .next
.carriage:
    LDA #$80
    STA $D101
    JMP .next
.clear:
    LDX #0
.clear_loop:
    LDA #' '
    STA $D100
    INX
    CPX #32
    BNE .clear_loop
    LDA #$80
    STA $D101
    JMP .next
.next:
    INY
    BNE .loop
.done:
    RTS

file_block_table:
    .word $C000, $C100, $C200, $C300, $C400, $C500

print_char:
    ; Your actual character output routine
    RTS
newline:
    LDA #$0A
    JSR print_char
    RTS
not_found:
    RTS

