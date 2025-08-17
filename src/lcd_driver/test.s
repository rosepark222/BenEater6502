; HD44780 LCD  


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
; LCD_DISPLAY  = $0C          ; Display on, cursor off
LCD_DISPLAY  = $0F          ; Display on, cursor on, Blinking on
LCD_FUNCTION = $38          ; Function set: 8-bit, 2-line, 5x8 dots
LCD_CGRAM    = $40          ; Set CGRAM address
LCD_DDRAM    = $80          ; Set DDRAM address

; LCD Position Constants
LCD_ROW0_COL0_ADDR      = $80          ; DDRAM address for line 1, column 0
LCD_ROW1_COL0_ADDR      = $C0          ; DDRAM address for line 2, column 0
LCD_COLS                = 16           ; Number of columns
LCD_ROWS                = 2            ; Number of rows

LCD_CURRENT_ROW  = $0230         ; current row
LCD_CURRENT_COL  = $0231         ; current col

; Buffer for line content (32 bytes: 16 for each line) 
LCD_LINE1_BUFFER = $0240         ; First line buffer 
LCD_LINE2_BUFFER = $0250         ; Second line buffer 

WORKING_DIR_INODE = $0213       ; Current working directory inode number (ADDED) ; pwd support

; ---------------------------------------------
; Initialize working directory (call this at system startup)
;     RTS



;summer_break:
start_lcd:

;    JSR init_working_dir
    ; *** CLEAR KEY BUFFER HERE! ***
    LDA #0
    STA KEY_INPUT
    JSR lcd_init
    JSR lcd_home_cursor
    JSR print_prompt

init_working_dir:
     LDA #0                      ; Start at root directory
     STA WORKING_DIR_INODE

    ; LDA #'1'
    ; JSR print_char
    ; JSR print_char
    ; JSR print_char
    ; JSR print_char
    ; JSR print_char

    ; LDA #LCD_HOME
    ; JSR lcd_command

    ; LDA #'H'
    ; JSR print_char        
    ; JSR print_char

    ; LDA #LCD_ROW1_COL0_ADDR
    ; JSR lcd_command
    ; LDA #1
    ; STA LCD_CURRENT_ROW
    ; LDA #0
    ; STA LCD_CURRENT_COL


keyinput_loop:
    JSR poll_keyboard
    BCC keyinput_loop          ; No key yet, poll again

    ; uncomment this to process shell command
     CMP #$0D                ; Enter key (CR)
     BEQ handle_enter
    ; CMP #$0A                ; Line feed?
    ; BEQ process_shell_cmd

    CMP #$08                ; Backspace?
    BEQ handle_backspace

    ; Ignore extra input if buffer full
    LDX CMD_INDEX
    CPX #CMD_MAX            ; len(cmd) >= CMD_MAX, do not fall through
    BCS keyinput_loop

    ; Normal character input
    JSR print_char
    JSR store_char
    JMP keyinput_loop

handle_backspace:
    LDX CMD_INDEX
    BEQ keyinput_loop          ; No chars to delete

    DEX
    STX CMD_INDEX

    ; Handle LCD backspace
    JSR lcd_backspace
    ; *** CLEAR KEY BUFFER HERE! ***
    LDA #0
    STA KEY_INPUT
    JMP keyinput_loop

handle_enter:
    JSR process_shell_cmd

; summer_break:
reset_shell:
    ;LDX #-1
    LDX #0
    STX CMD_INDEX
    ;JSR clear_newline_and_move ; do_wrap_and_print
    JSR do_carriage
    JSR print_prompt

    JMP keyinput_loop
; lcd driver including line discipline and scroll



lcd_init:
    ; Initialize LCD in 8-bit mode, 2-line display
    LDA #LCD_FUNCTION
    JSR lcd_command
    LDA #LCD_DISPLAY 
    JSR lcd_command
    LDA #LCD_ENTRY
    JSR lcd_command
    JSR lcd_clear
    JSR lcd_clear_buffers      
    RTS

lcd_clear:
    LDA #LCD_CLEAR
    JSR lcd_command
    ; Reset cursor position


    LDA #0
    STA LCD_CURRENT_COL
    STA LCD_CURRENT_ROW
    RTS

lcd_clear_buffers:             
    ; Clear both line buffers   
    LDX #0                     
    LDA #' '                   
clear_buffers_loop:            
    STA LCD_LINE1_BUFFER,X     
    STA LCD_LINE2_BUFFER,X     
    INX                        
    CPX #LCD_COLS              
    BNE clear_buffers_loop     
    RTS                        

lcd_home_cursor:
    LDA #0
    STA LCD_CURRENT_COL
    STA LCD_CURRENT_ROW
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

print_char:
 
    STX X_SCRATCH      ; 
    STY Y_SCRATCH      ; bug_report at 4426a08, Y is the pointer used in print_name in ls_util, but also used in print_char and should be preserved
    ;CMP #$0A
    ;BEQ do_newline           ; emulator sends \r for enter key so this routine is not used
; 
; bug_report : \r should not be printed
    ; CMP #$0D
    ; BEQ do_carriage

    LDX LCD_CURRENT_COL
    CPX #LCD_COLS            ; end of column, wrap
    BCS do_wrap_and_print

do_normal: ; fallthrough normal write
    STA LCD_DATA
    JSR lcd_delay
    JSR lcd_store_char_in_buffer   
    INC LCD_CURRENT_COL
 
    LDY Y_SCRATCH      ; bug_report at 4426a08
    LDX X_SCRATCH      ; 
    RTS

;do_newline:   ; emulator sends \r for enter key so this routine is not used
;    JSR clear_newline_and_move
;    RTS

do_carriage:
;summer_break:
    LDA LCD_CURRENT_ROW        
    BEQ carriage_line1         
    ; On line 2, need to scroll 
    JSR lcd_scroll_up          
    RTS                        
carriage_line1:                
    JSR clear_newline_and_move ; lcd_carriage_return
    RTS

do_wrap_and_print:
    PHA
    LDA LCD_CURRENT_ROW        
    BEQ wrap_to_line2          
    ; On line 2, need to scroll before printing 
    JSR lcd_scroll_up          
    PLA                        
    JMP do_normal              
wrap_to_line2:                 
    JSR clear_newline_and_move  ; clear new line, put curtor at the head 
    PLA
    JMP do_normal   ; print the char

lcd_scroll_up:                 
    ; Copy line 2 to line 1     
    LDX #0                     
scroll_copy_loop:              
    LDA LCD_LINE2_BUFFER,X     
    STA LCD_LINE1_BUFFER,X     
    INX                        
    CPX #LCD_COLS              
    BNE scroll_copy_loop       
                               
    ; Clear line 2 buffer       
    LDX #0                     
    LDA #' '                   
scroll_clear_loop:             
    STA LCD_LINE2_BUFFER,X     
    INX                        
    CPX #LCD_COLS              
    BNE scroll_clear_loop      
                               
    ; Refresh LCD display       
    JSR lcd_refresh_display    
                               
    ; Position cursor at start of line 2 
    LDA #1                     
    STA LCD_CURRENT_ROW        
    LDA #0                     
    STA LCD_CURRENT_COL        
    LDA #LCD_ROW1_COL0_ADDR    
    JSR lcd_command            
    RTS                        

lcd_refresh_display:           
    ; Display line 1            
    LDA #LCD_ROW0_COL0_ADDR    
    JSR lcd_command            
    LDX #0                     
refresh_line1_loop:            
    LDA LCD_LINE1_BUFFER,X     
    STA LCD_DATA               
    JSR lcd_delay              
    INX                        
    CPX #LCD_COLS              
    BNE refresh_line1_loop     
                               
    ; Display line 2            
    LDA #LCD_ROW1_COL0_ADDR    
    JSR lcd_command            
    LDX #0                     
refresh_line2_loop:            
    LDA LCD_LINE2_BUFFER,X     
    STA LCD_DATA               
    JSR lcd_delay              
    INX                        
    CPX #LCD_COLS              
    BNE refresh_line2_loop     
    RTS                        

lcd_store_char_in_buffer:      
    ; Store character in appropriate line buffer 
    LDX LCD_CURRENT_COL        
    LDY LCD_CURRENT_ROW        
    BEQ store_in_line1         
    ; Store in line 2           
    STA LCD_LINE2_BUFFER,X     
    RTS                        
store_in_line1:                
    STA LCD_LINE1_BUFFER,X     
    RTS                        

clear_newline_and_move: ; Move to start of next line
    ;PHA     
    LDA LCD_CURRENT_ROW
    CMP #0
    BEQ move_to_line2
    
    ; Currently on line 2, clear and go to line 1
    JSR lcd_clear_line
    JSR lcd_clear_line_buffer  
    LDA #0
    STA LCD_CURRENT_ROW
    STA LCD_CURRENT_COL
    LDA #LCD_ROW0_COL0_ADDR
    JSR lcd_command
    ;PLA 
    RTS

move_to_line2:
    ; Currently on line 1, clear line 2 and move there
    JSR lcd_clear_line
    JSR lcd_clear_line_buffer  
    LDA #1
    STA LCD_CURRENT_ROW
    LDA #0
    STA LCD_CURRENT_COL
    LDA #LCD_ROW1_COL0_ADDR
    JSR lcd_command
    RTS

lcd_clear_line_buffer:         
    ; Clear the buffer for current line 
    LDA LCD_CURRENT_ROW        
    BEQ clear_line1_buffer     
    ; Clear line 2 buffer       
    LDX #0                     
    LDA #' '                   
clear_line2_buf_loop:          
    STA LCD_LINE2_BUFFER,X     
    INX                        
    CPX #LCD_COLS              
    BNE clear_line2_buf_loop   
    RTS                        
clear_line1_buffer:            
    LDX #0                     
    LDA #' '                   
clear_line1_buf_loop:          
    STA LCD_LINE1_BUFFER,X     
    INX                        
    CPX #LCD_COLS              
    BNE clear_line1_buf_loop   
    RTS                        

lcd_carriage_return:
    ; Move to start of current line
    LDA #0
    STA LCD_CURRENT_COL
    LDA LCD_CURRENT_ROW
    BEQ set_line1_pos
    LDA #LCD_ROW1_COL0_ADDR
    JSR lcd_command
    RTS
set_line1_pos:
    LDA #LCD_ROW0_COL0_ADDR
    JSR lcd_command
    RTS

lcd_backspace:
    ; Move cursor back one position
    LDA LCD_CURRENT_COL
    BEQ backspace_prev_line
    
    ; Same line backspace
    DEC LCD_CURRENT_COL
    JSR lcd_update_cursor
    
    ; Clear character at current position
    LDA #' '
    STA LCD_DATA
    JSR lcd_delay
    JSR lcd_store_char_in_buffer   
    
    ; Move cursor back again
    JSR lcd_update_cursor
    RTS

backspace_prev_line:
    ; At start of line, can't backspace further
    ; (Could implement wrap to previous line if desired)
    RTS

lcd_update_cursor:
    ; Set cursor position based on LCD_CURRENT_ROW and LCD_CURRENT_COL
    LDA LCD_CURRENT_ROW
    BEQ update_line1
    
    ; Line 2
    LDA #LCD_ROW1_COL0_ADDR
    CLC
    ADC LCD_CURRENT_COL
    JSR lcd_command
    RTS

update_line1:
    ; Line 1  
    LDA #LCD_ROW0_COL0_ADDR
    CLC
    ADC LCD_CURRENT_COL
    JSR lcd_command
    RTS

; ====================================================================
; Combined LCD Clear Line Routine (Input in A)
; Input: A = 0 to clear line 2
;        A = 1 to clear line 1
; ====================================================================
lcd_clear_line:
    TAX                     ; Save the input value of A into X for comparison
    LDA #$C0                ; Start with the base command for line 2
    CPX #1                  ; Check if the input is 1
    BNE set_cursor          ; If X is not 1, skip the EOR
    ; If X is 1, change the command to line 1
    EOR #$40                ; Flip bit 6 to change 0xC0 to 0x80

set_cursor:
    JSR lcd_command         ; Send the command
    LDY #0                  ; Use Y as a counter
    LDA #' '                ; The space character to write
    
clear_loop:
    STA LCD_DATA            ; Write the space
    JSR lcd_delay
    INY
    CPY #LCD_COLS           ; Assumes LCD_COLS is the width of the display
    BNE clear_loop
    
    RTS

lcd_delay:
    ; Simple delay for LCD timing
    ; Adjust based on your system clock
    PHA
    ;LDA #$FF  ; long delay
    LDA #$03
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
    JSR print_char
    INY
    JMP print_prompt_loop
done_prompt:
    RTS

print_unknown:
    LDY #0
print_unk_loop:
    LDA unk_msg,Y
    BEQ done_unk
    JSR print_char
    INY
    JMP print_unk_loop
done_unk:
    RTS


; === Data ===

CMD_INDEX:      .byte 0
prompt_msg:     .byte "> ", 0
unk_msg:        .byte "Unknown command", 0
; LCD State Variables
;LCD_CURRENT_COL:     .byte 0        ; Current column (0-15)
;LCD_CURRENT_ROW:     .byte 0        ; Current row (0-1)