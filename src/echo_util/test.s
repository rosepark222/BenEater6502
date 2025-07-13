;--------------------------------------------------
; 6502 Assembly: echo utility (with LCD support)
;--------------------------------------------------

;--------------------------------------------------
; Zero Page Register Usage (ZP variables)
;--------------------------------------------------

zp_string_ptr = $00   ; Pointer to input character string (e.g., "hello") to write
zp_path_ptr   = $02   ; Pointer to resolved path string (for ls/cat resolution)
zp_inode_ptr  = $04   ; Pointer to current inode structure (used after resolution)
zp_device_id  = $06   ; Device ID (from inode) used for device dispatch (e.g., /dev/lcd)
zp_block_ptr  = $07   ; Temporary storage for block number (used when writing to file)
zp_temp_ptr   = $08   ; General-purpose temp pointer (e.g., to point to file block buffer)

;--------------------------------------------------
; Shared Entry Point: Parses command and dispatches to cat, ls, or echo
;--------------------------------------------------
main:
    JSR echo
    RTS

;--------------------------------------------------
echo:
    ; Setup hardcoded message string pointer
    LDA #<hello_string
    STA zp_string_ptr
    LDA #>hello_string
    STA zp_string_ptr+1

    ; Setup hardcoded path pointer
    LDA #<lcd_path
    STA $10           ; path string pointer low
    LDA #>lcd_path
    STA $11           ; path string pointer high

    ; Resolve the path to get inode pointer
    LDA #0
    STA $0210         ; start from root inode

.echo_next_token:
    JSR next_path_token
    BEQ .echo_done_resolving

    LDA $0210
    JSR get_inode_ptr
    JSR find_in_dir
    BCS .echo_error
    STA $0210
    JMP .echo_next_token

.echo_done_resolving:
    LDA $0210
    JSR get_inode_ptr
    LDA $00
    STA zp_inode_ptr
    LDA $01
    STA zp_inode_ptr+1

    ; Check if inode is LCD device (type = $10, id = $01)
    LDY #0
    LDA (zp_inode_ptr),Y
    AND #%11110000
    CMP #%00010000     ; device type?
    BNE .echo_error

    LDY #7             ; device ID stored at offset 7
    LDA (zp_inode_ptr),Y
    CMP #$01           ; LCD device ID
    BNE .echo_error

    ; Call LCD driver to print the string
    JSR echo_lcd_driver_indirect
    RTS

.echo_error:
    RTS

echo_lcd_driver_indirect:
    LDY #0
.echo_loop:
    LDA (zp_string_ptr),Y
    BEQ .done
    STA $6000         ; Write char to LCD register
    INY
    JMP .echo_loop
.done:
    RTS

hello_string:
    .byte "hello", 0

lcd_path:
    .byte "/dev/lcd", 0

echo_lcd_driver:
    LDY #0
.echo_loop:
    LDA (zp_string_ptr),Y
    BEQ .done
    STA $6000         ; Write char to LCD register
    INY
    JMP .echo_loop
.done:
    RTS




;--------------------------------------------------
; Common FS logic and LCD handler (full definitions)
;--------------------------------------------------

; Get pointer to inode given inode number in A
get_inode_ptr:
    CMP #64
    BCS bad_inode        ; Bounds check
    ASL A
    ASL A
    ASL A
    ASL A                ; Multiply by 16
    STA $00
    LDA #$BC             ; Base address $BC00
    ADC #0               ; Add carry
    STA $01
    RTS

bad_inode:
    JMP not_found

; Find directory entry with name in $0200
; Input: $00/$01 = directory inode pointer
; Output: A = inode number if found; Carry clear if found
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
    STA $02
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

not_found:
    SEC
    RTS

found_entry:
    CLC
    RTS

; Scan block for token name in $0200
; Output: A = inode number; Carry clear if found
scan_block:
    CMP #64
    BCS not_found_scan
    ASL A
    ROL $06
    ASL A
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

; Extract next token from path at ($10) and store in $0200
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



