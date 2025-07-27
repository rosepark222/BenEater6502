

; using the code in the previous commit,
; asked claude the below

; the below is a small 6502 code handling keyboard input and jumps to ls util if the command is ls.
; It access   HD44780 LCD by writing a character to 0x6000. 
; However, I need a full line discipline doing
; 1, at the start, place cursor to 0 col and 0 row.
; 2, when writing characters, if column goes beyond 15 (max can be displayed), it should clear the other row and start to write on it.   
; can you modify the code so that it can function like tty on  16x2 LCD ?


; === LCD and Shell Configuration ===
KEY_INPUT    = $0300        ; Key byte buffer
LCD_DATA     = $6000        ; LCD data register
LCD_CMD      = $6001        ; LCD command register (if available)
CMD_BUFFER   = $0400        ; Command string buffer
CMD_MAX      = 64           ; Max command length

; HD44780 LCD Commands 
LCD_CLEAR    = $01          ; Clear display
LCD_HOME     = $02          ; Return home
LCD_ENTRY    = $06          ; Entry mode set
LCD_DISPLAY  = $0C          ; Display on, cursor off
LCD_FUNCTION = $38          ; Function set: 8-bit, 2-line, 5x8 dots
LCD_CGRAM    = $40          ; Set CGRAM address
LCD_DDRAM    = $80          ; Set DDRAM address

; LCD Position Constants
LCD_LINE1    = $80          ; DDRAM address for line 1, column 0
LCD_LINE2    = $C0          ; DDRAM address for line 2, column 0
LCD_COLS     = 16           ; Number of columns
LCD_ROWS     = 2            ; Number of rows

LCD_ROW  = $0230         ; current row
LCD_COL  = $0231         ; current col


start_shell:
    ; *** CLEAR KEY BUFFER HERE! ***
    LDA #0
    STA KEY_INPUT
    JSR lcd_init
    JSR lcd_home_cursor
    JSR print_prompt


    LDA #'1'
    JSR lcd_putchar
    JSR lcd_putchar
    JSR lcd_putchar
    JSR lcd_putchar
    JSR lcd_putchar

    ; LDA #LCD_HOME
    ; JSR lcd_command

    ; LDA #'H'
    ; JSR lcd_putchar        
    ; JSR lcd_putchar

    ; LDA #LCD_LINE2
    ; JSR lcd_command
    ; LDA #1
    ; STA LCD_ROW
    ; LDA #0
    ; STA LCD_COL

    LDA #'2'
    JSR lcd_putchar
    LDA #'2'
    JSR lcd_putchar
    LDA #'2'
    JSR lcd_putchar
    LDA #'2'
    JSR lcd_putchar
    LDA #'2'
    JSR lcd_putchar 
    LDA #'2'
    JSR lcd_putchar
    LDA #'2'
    JSR lcd_putchar
    LDA #'2'
    JSR lcd_putchar
    LDA #'2'
    JSR lcd_putchar

    LDA #'3'
    JSR lcd_putchar
    LDA #'3'
    JSR lcd_putchar
    LDA #'3'
    JSR lcd_putchar




shell_loop:
    JSR poll_keyboard
    BCC shell_loop          ; No key yet, poll again
    CMP #$0D                ; Enter key (CR)?
    BEQ process_command
    CMP #$0A                ; Line feed?
    BEQ process_command
    CMP #$08                ; Backspace?
    BEQ handle_backspace

    ; Ignore extra input if buffer full
    LDX CMD_INDEX
    CPX #CMD_MAX
    BCS shell_loop

    ; Normal character input
    JSR lcd_putchar
    JSR store_char
    JMP shell_loop

handle_backspace:
    LDX CMD_INDEX
    BEQ shell_loop          ; No chars to delete

    DEX
    STX CMD_INDEX

    ; Handle LCD backspace
    JSR lcd_backspace
    ; *** CLEAR KEY BUFFER HERE! ***
    LDA #0
    STA KEY_INPUT
    JMP shell_loop

process_command:
    LDX CMD_INDEX
    LDA #$00
    STA CMD_BUFFER,X        ; Null-terminate

    ; Reset CMD_INDEX for next command
    LDX #0
    STX CMD_INDEX

    ; Move to next line
    ;JSR lcd_newline

    ; Parse command - currently supports "ls"
    LDX #0
    LDY #0
check_ls:
    LDA CMD_BUFFER,X
    CMP ls_cmd,Y
    BNE unknown_cmd
    BEQ match_check
match_check:
    INX
    INY
    LDA ls_cmd,Y
    CMP #0
    BNE check_ls

    ; Matched "ls", skip spaces
skip_space:
    LDA CMD_BUFFER,X
    CMP #' '
    BNE got_path
    INX
    JMP skip_space

got_path:
    LDY #0
copy_path:
    LDA CMD_BUFFER,X
    STA PATH_INPUT,Y
    BEQ call_ls
    INX
    INY
    CPY #CMD_MAX
    BNE copy_path

call_ls:
    JSR start_ls     ; jump to ls util
    ; *** CLEAR KEY BUFFER HERE! ***

    JSR newline
    LDA #0
    STA KEY_INPUT
    JMP start_shell

unknown_cmd:
    JSR print_unknown
    JMP start_shell

reset_shell:
    LDX #0
    STX CMD_INDEX
    JSR print_prompt

    JMP shell_loop

; === LCD Line Discipline Routines ===

lcd_init:
    ; Initialize LCD in 8-bit mode, 2-line display
    LDA #LCD_FUNCTION
    JSR lcd_command
    LDA #LCD_DISPLAY 
    JSR lcd_command
    LDA #LCD_ENTRY
    JSR lcd_command
    JSR lcd_clear
    RTS

lcd_clear:
    LDA #LCD_CLEAR
    JSR lcd_command
    ; Reset cursor position
    LDA #0
    STA LCD_COL
    STA LCD_ROW
    RTS

lcd_home_cursor:
    LDA #0
    STA LCD_COL
    STA LCD_ROW
    LDA #LCD_HOME
    JSR lcd_command
    RTS

lcd_command:
    ; Send command to LCD
    ; For basic setup, we'll assume LCD_CMD register exists
    ; If not available, this would need timing loops
    STA LCD_CMD
    JSR lcd_delay
    RTS

lcd_putchar:
    ; Input: A = character to display
    ; Handle special characters
    CMP #$0A                ; Line feed?
    BEQ lcd_newline
    CMP #$0D                ; Carriage return?
    BEQ lcd_carriage_return
    
    ; Normal character - check if we need to wrap
    LDX LCD_COL
    CPX #LCD_COLS
    BCS lcd_wrap_line
    
    ; Display character and advance cursor
    STA LCD_DATA
    JSR lcd_delay
    INC LCD_COL
    RTS

lcd_wrap_line:
    PHA     ; save A , a char to print
    ; Current line is full, move to next line
    JSR lcd_newline
    PLA     ; restore A, a char to print
    ; Now display the character
    STA LCD_DATA
    JSR lcd_delay
    INC LCD_COL
    RTS

lcd_newline:
    ;PHA 
    ; Move to start of next line
    LDA LCD_ROW
    CMP #0
    BEQ move_to_line2
    
    ; Currently on line 2, clear and go to line 1
    JSR lcd_clear_line2
    LDA #0
    STA LCD_ROW
    STA LCD_COL
    LDA #LCD_LINE1
    JSR lcd_command
    ;PLA 
    RTS

move_to_line2:
    ; Currently on line 1, clear line 2 and move there
    JSR lcd_clear_line2
    LDA #1
    STA LCD_ROW
    LDA #0
    STA LCD_COL
    LDA #LCD_LINE2
    JSR lcd_command
    RTS

lcd_carriage_return:
    ; Move to start of current line
    LDA #0
    STA LCD_COL
    LDA LCD_ROW
    BEQ set_line1_pos
    LDA #LCD_LINE2
    JSR lcd_command
    RTS
set_line1_pos:
    LDA #LCD_LINE1
    JSR lcd_command
    RTS

lcd_backspace:
    ; Move cursor back one position
    LDA LCD_COL
    BEQ backspace_prev_line
    
    ; Same line backspace
    DEC LCD_COL
    JSR lcd_update_cursor
    
    ; Clear character at current position
    LDA #' '
    STA LCD_DATA
    JSR lcd_delay
    
    ; Move cursor back again
    JSR lcd_update_cursor
    RTS

backspace_prev_line:
    ; At start of line, can't backspace further
    ; (Could implement wrap to previous line if desired)
    RTS

lcd_update_cursor:
    ; Set cursor position based on LCD_ROW and LCD_COL
    LDA LCD_ROW
    BEQ update_line1
    
    ; Line 2
    LDA #LCD_LINE2
    CLC
    ADC LCD_COL
    JSR lcd_command
    RTS

update_line1:
    ; Line 1  
    LDA #LCD_LINE1
    CLC
    ADC LCD_COL
    JSR lcd_command
    RTS

lcd_clear_line2:
    ; Clear line 2 by writing spaces
    LDA #LCD_LINE2
    JSR lcd_command
    
    LDY #0
clear_line2_loop:
    LDA #' '
    STA LCD_DATA
    JSR lcd_delay
    INY
    CPY #LCD_COLS
    BNE clear_line2_loop
    RTS

lcd_delay:
    ; Simple delay for LCD timing
    ; Adjust based on your system clock
    PHA
    LDA #$FF
delay_loop:
    NOP
    NOP
    SBC #1
    BNE delay_loop
    PLA
    RTS

; === Original Shell Routines (Modified) ===

poll_keyboard:
    LDA KEY_INPUT
    CMP #$00
    BEQ no_key
    SEC
    RTS
no_key:
    CLC
    RTS

store_char:
    ; Input: A = character
    LDX CMD_INDEX
    STA CMD_BUFFER,X
    INX
    STX CMD_INDEX
    LDA #$00        ; clear key buffer
    STA KEY_INPUT
    RTS

print_prompt:
    LDY #0
print_prompt_loop:
    LDA prompt_msg,Y
    BEQ done_prompt
    JSR lcd_putchar
    INY
    JMP print_prompt_loop
done_prompt:
    RTS

print_unknown:
    LDY #0
print_unk_loop:
    LDA unk_msg,Y
    BEQ done_unk
    JSR lcd_putchar
    INY
    JMP print_unk_loop
done_unk:
    RTS

; Override the print_char routine used by ls_util
print_char:
    JSR lcd_putchar
    RTS

; === Data ===

CMD_INDEX:      .byte 0
ls_cmd:         .byte "ls",0
prompt_msg:     .byte "> ",0
unk_msg:        .byte "Unknown command",10,0
; LCD State Variables
;LCD_COL:     .byte 0        ; Current column (0-15)
;LCD_ROW:     .byte 0        ; Current row (0-1)

; === External entry point ===
; start_ls should be defined in your ls_util.s