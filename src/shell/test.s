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

WORKING_DIR_INODE = $0212       ; Current working directory inode number (ADDED) ; pwd support

; ---------------------------------------------
; Initialize working directory (call this at system startup)
;     RTS

start_shell:

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

    ; LDA #'t'
    ; JSR print_char
    ; LDA #'h'
    ; JSR print_char
    ; LDA #'i'
    ; JSR print_char
    ; LDA #'s'
    ; JSR print_char
    ; LDA #' '
    ; JSR print_char 
    ; LDA #'i'
    ; JSR print_char
    ; LDA #'s'
    ; JSR print_char
    ; LDA #' '
    ; JSR print_char
    ; LDA #'s'
    ; JSR print_char
    ; LDA #'p'
    ; JSR print_char
    ; LDA #'a'
    ; JSR print_char
    ; LDA #'r'
    ; JSR print_char
    ; LDA #'t'
    ; JSR print_char
    ; LDA #'a'
    ; JSR print_char
    ; LDA #'n'
    ; JSR print_char


shell_loop:
    JSR poll_keyboard
    BCC shell_loop          ; No key yet, poll again

    ; uncomment this to process shell command
     CMP #$0D                ; Enter key (CR)
     BEQ process_shell_cmd
    ; CMP #$0A                ; Line feed?
    ; BEQ process_shell_cmd

    CMP #$08                ; Backspace?
    BEQ handle_backspace

    ; Ignore extra input if buffer full
    LDX CMD_INDEX
    CPX #CMD_MAX            ; len(cmd) >= CMD_MAX, do not fall through
    BCS shell_loop

    ; Normal character input
    JSR print_char
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

process_shell_cmd:
    LDX CMD_INDEX
    LDA #$00
    STA CMD_BUFFER,X        ; Null-terminate

    ; Reset CMD_INDEX for next command
    LDX #0
    STX CMD_INDEX

    ; Move to next line
    ;JSR clear_newline_and_move

    ; Parse command - currently supports "ls"
    LDX #0
    LDY #0

;summer_break:
; bug_report  bc59655 for the command parsing logic
;
; bug1 
; if command is cd2, it matches command cd and take 2 as a path
; if command is cd2 3, cd is recognized as cmd and '2 3' as a path
;
; bug2: 
; logic checks if cmd matches to cd\0
; if there is a command cwd, then c is matched to the c of cd
; then w does not match to the d, so it jumps to the next cmd , check_ls
; however, X and Y should be reset to zero so that it compares from the first character
; 
; otherwise an interesting case is this:
;  1, assume there are cmds cd, cwd, and pwd
;  2, cmd check cd, pwd, then cwd in that order
;  3, user type cwd
;  4, code check if cmd is cd first -- compares c in cd and c in cwd, ok
;  5, next, d and w does not match , so code check if cmd is pwd
;  6, X, Y are at w not at p
;  7, w in cwd and w in pwd matches 
;  8, d in cwd and d in pwd matches 
;  9, finally, code recognize it as pwd and runs pwd, not user typed cwd
; 
check_cd:                               ; cd util
    LDA CMD_BUFFER,X                    ; cd util
    CMP cd_cmd,Y                        ; cd util
    BNE check_pwd                        ; cd util - Not cd, try pwd
    BEQ cd_match_check                  ; cd util
cd_match_check:                         ; cd util
    INX                                 ; cd util
    INY                                 ; cd util
    LDA cd_cmd,Y                        ; cd util
    CMP #0                              ; cd util
    BNE check_cd                        ; cd util

    ; Matched "cd", skip spaces         ; cd util
cd_skip_space:                          ; cd util
    LDA CMD_BUFFER,X                    ; cd util
    CMP #' '                            ; cd util
    BNE cd_got_path                     ; cd util
    INX                                 ; cd util
    JMP cd_skip_space                   ; cd util

cd_got_path:                            ; cd util
    LDY #0                              ; cd util
cd_copy_path:                           ; cd util
    LDA CMD_BUFFER,X                    ; cd util
    STA PATH_INPUT,Y                    ; cd util
    BEQ call_cd                         ; cd util
    INX                                 ; cd util
    INY                                 ; cd util
    CPY #CMD_MAX                        ; cd util
    BNE cd_copy_path                    ; cd util

call_cd:                                ; cd util
    JSR start_cd                        ; cd util - jump to cd util
    LDA #0                              ; cd util
    STA KEY_INPUT                       ; cd util
    JMP reset_shell                     ; cd util
    
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

check_pwd:                              ; pwd util
    LDA CMD_BUFFER,X                    ; pwd util
    CMP pwd_cmd,Y                       ; pwd util
    BNE check_ls                        ; pwd util - Not pwd, try ls
    BEQ pwd_match_check                 ; pwd util
pwd_match_check:                        ; pwd util
    INX                                 ; pwd util
    INY                                 ; pwd util
    LDA pwd_cmd,Y                       ; pwd util
    CMP #0                              ; pwd util
    BNE check_pwd                       ; pwd util

    ; Matched "pwd",                    ; pwd util
call_pwd:                               ; pwd util
    JSR start_pwd                       ; pwd util - jump to pwd util
    LDA #0                              ; pwd util
    STA KEY_INPUT                       ; pwd util
    JMP reset_shell                     ; pwd util

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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

    ; JSR newline
    LDA #0
    STA KEY_INPUT
    JMP reset_shell

unknown_cmd:
    JSR print_unknown
    JMP reset_shell

reset_shell:
    LDX #0
    STX CMD_INDEX
    JSR clear_newline_and_move ; do_wrap_and_print
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
    STA LCD_CURRENT_COL
    STA LCD_CURRENT_ROW
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
 
    ; STY Y_SCRATCH      ; bug_report at 4426a08, Y is the pointer used in print_name in ls_util, but also used in print_char and should be preserved
    ;CMP #$0A
    ;BEQ do_newline           ; emulator sends \r for enter key so this routine is not used
    CMP #$0D
    BEQ do_carriage

    LDX LCD_CURRENT_COL
    CPX #LCD_COLS            ; end of column, wrap
    BCS do_wrap_and_print

do_normal: ; fallthrough normal write
    STA LCD_DATA
    JSR lcd_delay
    INC LCD_CURRENT_COL
 
    ; LDY Y_SCRATCH       ; bug_report at 4426a08
    RTS

;do_newline:   ; emulator sends \r for enter key so this routine is not used
;    JSR clear_newline_and_move
;    RTS

do_carriage:
    JSR clear_newline_and_move ; lcd_carriage_return
    RTS

do_wrap_and_print:
    PHA
    JSR clear_newline_and_move  ; clear new line, put curtor at the head 
    PLA
    JMP do_normal   ; print the char

clear_newline_and_move: ; Move to start of next line
    ;PHA     
    LDA LCD_CURRENT_ROW
    CMP #0
    BEQ move_to_line2
    
    ; Currently on line 2, clear and go to line 1
    JSR lcd_clear_line
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
    LDA #1
    STA LCD_CURRENT_ROW
    LDA #0
    STA LCD_CURRENT_COL
    LDA #LCD_ROW1_COL0_ADDR
    JSR lcd_command
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

; ; Override the print_char routine used by ls_util
; print_char:
;     JSR print_char
;     RTS

; === Data ===

CMD_INDEX:      .byte 0
ls_cmd:         .byte "ls", 0
cd_cmd:         .byte "cd", 0           ; cd util
pwd_cmd:        .byte "pwd", 0           ; pwd util
prompt_msg:     .byte "> ", 0
unk_msg:        .byte "Unknown command", 0
; LCD State Variables
;LCD_CURRENT_COL:     .byte 0        ; Current column (0-15)
;LCD_CURRENT_ROW:     .byte 0        ; Current row (0-1)

; === External entry point ===
; start_ls should be defined in your ls_util.s