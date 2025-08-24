; HD44780 LCD  


; using the code in the previous commit,
; asked claude the below

; the below is a small 6502 code handling keyboard input and jumps to ls util if the command is ls.
; It access   HD44780 LCD by writing a character to 0x6000. 
; However, I need a full line discipline doing
; 1, at the start, place cursor to 0 col and 0 row.
; 2, when writing characters, if column goes beyond 15 (max can be displayed), it should clear the other row and start to write on it.   
; can you modify the code so that it can function like tty on  16x2 LCD ?


; bug_report : 
; if HEAD = 8, it means the latest line stored to the scroll buffer is line 8. 
; When user presses UP, the screen should show line 7 and 8 at 
; the top and bottom of LCD, respectively. 
; For this, SCROLL_VIEW_TOP should be 7 not 8. What do you think ?


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; commit: 06c86acdac30cf842b71b15243d1bda51720e0ba
; Date:   Sun Aug 24 08:59:43 2025 -0700

; proposal 1: major change in LCD
; This is the behavior of the desired LCD driver.
; assume row 1 is top and row 2 is bottom of LCD VIEW ( VIEW is what is currently shown in LCD).
; 1, 
; while print characters in row 2, if it reaches the end of the column, the row 2 should be copied over to row 1 (scroll up), while row 1 copied over to the scroll buffer (16 entries circular buffer).  
; 2,
; command can also print characters as the result of execution. It should be keeping the rule 1. At the end of printing, the LCD VIEW should scroll up and row 2 should be empty line with prompt ready to taking in future command
; 3, 
;  when the up button is pressed and scroll buffer got something to show, the first row is copied to the second row and the most recent entry of scroll buffer will be copied over to the first row to do the scrolling up . Up button should not do anything if row 1 displays the oldest entry in the scroll buffer
; 4, 
; when down button is pressed, the behavior is opposite to the behavior from the pressing up button 
; 5, 
; when normal key is pressed, LCD will show the VIEW users see before the scroll mode is activated.
;
; I have the attached lcd display driver implemented the above rules but want to simplify it by placing the cursor at the row 2 at the beginning. In this way, cursors are always in the row 2 and there is no need for checking if the current cursor is at row 1 or row 2. 
; For easy comparison, any changed line should be marked with comment "; row 2 start "

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; flow chart can be compared before and after the logic simplication ( row 2 start )

; before: row 1 start -- cursor at row 1 but always stay at row 2 once it reaches it
; https://claude.ai/public/artifacts/f90189b5-9f6e-4f42-82e3-7e156b5e4806

; after : row 2 start  -- cursor only stays at the row 2 , greatly simplifies the logic
; https://claude.ai/public/artifacts/1a53db00-d52e-41ed-8619-df7306d1c4f2

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; propoal 2: a minor suggestion
; The clear_newline_and_move logic seems unreachable, can you remove it and clean up the code?
; Also,
; 1,
; do_carriage does not have to be a subroutine, because there is only one place calling it. remove subroutine by directly calling add_line_to_scroll_buffer and lcd_scroll_up.
; 2, 
; add_line_to_scroll_buffer should be called add_row1_to_scroll_buffer because it stores the row 1 to the scroll buffer, right? If you agree, change the code.





start_lcd:

    ; *** CLEAR KEY BUFFER HERE! ***
    LDA #0
    STA KEY_INPUT
    JSR lcd_init
    JSR lcd_home_cursor
    JSR print_prompt

init_working_dir:
     LDA #0                      ; Start at root directory
     STA WORKING_DIR_INODE

    ; LDA #'1' ; JSR print_char ; JSR print_char ; JSR print_char ; JSR print_char ; JSR print_char ; LDA #LCD_HOME ; JSR lcd_command ; LDA #'H' ; JSR print_char        ; JSR print_char ; LDA #LCD_ROW1_COL0_ADDR ; JSR lcd_command ; LDA #1 ; STA LCD_CURRENT_ROW ; LDA #0 ; STA LCD_CURRENT_COL

keyinput_loop:
    JSR poll_keyboard
    BCC keyinput_loop          ; No key yet, poll again

    ;; scroll up down - Check for arrow keys first
    CMP #KEY_UP
    BEQ handle_key_up
    CMP #KEY_DOWN
    BEQ handle_key_down
    
    ;; scroll up down - Any other key exits scroll mode
    PHA                    ; Save the key value
    LDA SCROLL_MODE
    BEQ normal_key_processing_restore
    JSR exit_scroll_mode

normal_key_processing_restore:
    PLA                    ; Restore the key value
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

;; scroll up down - Handle up arrow key
handle_key_up:
    JSR scroll_up
    LDA #0
    STA KEY_INPUT
    JMP keyinput_loop

;; scroll up down - Handle down arrow key  
handle_key_down:
    JSR scroll_down
    LDA #0
    STA KEY_INPUT
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

reset_shell:
    ;LDX #-1
    LDX #0
    STX CMD_INDEX
    ; row 2 start - Inline do_carriage logic (add to scroll buffer and scroll up)
    JSR add_row1_to_scroll_buffer
    JSR lcd_scroll_up
    JSR print_prompt

    JMP keyinput_loop

;; scroll up down - Scroll buffer management routines
;summer_break:
scroll_up:
    LDA SCROLL_MODE
    BNE scroll_up_continue
    ; Entering scroll mode for first time
    LDA #1
    STA SCROLL_MODE
    LDA SCROLL_HEAD
    ; bug_report_123 : if HEAD = 8, it means the latest line stored to the scroll buffer is line 8.
    ; When user presses UP, the screen should show line 7 and 8 at the top and bottom of LCD, 
    ; respectively. For this, SCROLL_VIEW_TOP should be 7 not 8. What do you think ?

    SEC                    ; scroll up fix - Set carry for subtraction
    SBC #1                 ; scroll up fix - SCROLL_VIEW_TOP = HEAD - 1
    BPL store_view_top     ; scroll up fix - If positive, store it
    LDA #SCROLL_BUFFER_SIZE-1  ; scroll up fix - If negative, wrap to 15
store_view_top:            ; scroll up fix
    STA SCROLL_VIEW_TOP    ; scroll up fix
    
scroll_up_continue:
    ; Check if we can scroll up (view_top != tail)
    LDA SCROLL_VIEW_TOP
    CMP SCROLL_TAIL
    BEQ scroll_up_done      ; Can't scroll up anymore
    
    ; Move view up one line

    ; bug_report_202f8f4812c7b102582525428c0769f1cdab866d
    ; Here no need to decrement the SCROLL_VIEW_TOP because 
    ; it has been already decremented in scroll_up:  SEC; SBC #1
    ; Thus, the meaning of SCROLL_VIEW_TOP is the index of buffer will show up as the result 
    ; of the scrolling up
    ; 
    ; DEC SCROLL_VIEW_TOP
    LDA SCROLL_VIEW_TOP
    BPL scroll_up_refresh
    LDA #SCROLL_BUFFER_SIZE-1  ; Wrap around
    STA SCROLL_VIEW_TOP
    
scroll_up_refresh:
    JSR refresh_scroll_display
    
scroll_up_done:
    RTS

scroll_down:
    LDA SCROLL_MODE
    BEQ scroll_down_done    ; Not in scroll mode
    
    ; Check if we can scroll down
    LDA SCROLL_VIEW_TOP
    CMP SCROLL_HEAD
    BEQ scroll_down_done    ; Already at newest
    
    ; Move view down one line
    INC SCROLL_VIEW_TOP
    LDA SCROLL_VIEW_TOP
    CMP #SCROLL_BUFFER_SIZE
    BNE scroll_down_refresh
    LDA #0                  ; Wrap around
    STA SCROLL_VIEW_TOP
    
scroll_down_refresh:
    JSR refresh_scroll_display
    
scroll_down_done:
    RTS

; exit_scroll_mode:
;     LDA #0
;     STA SCROLL_MODE
;     ; Refresh display to show current lines
;     JSR lcd_refresh_display
;     RTS

; The key addition is JSR lcd_update_cursor at the end of exit_scroll_mode. This ensures that after refreshing the display with the current line buffers, the LCD cursor is positioned correctly based on LCD_CURRENT_ROW and LCD_CURRENT_COL so that normal character input can continue from the right position.

exit_scroll_mode:
    LDA #0
    STA SCROLL_MODE
    ; Refresh display to show current lines
    JSR lcd_refresh_display
    ;; scroll up down - Restore cursor position after exiting scroll mode
    JSR lcd_update_cursor
    RTS

refresh_scroll_display:
    ; Display two lines starting from SCROLL_VIEW_TOP
    
    ; Calculate first line address
    LDA SCROLL_VIEW_TOP
    ASL A                   ; Multiply by 16 (line size)
    ASL A
    ASL A  
    ASL A
    TAX                     ; X = line offset in buffer
    
    ; Display first line
    LDA #LCD_ROW0_COL0_ADDR
    JSR lcd_command
    LDY #0
refresh_line1:
    LDA SCROLL_BUFFER,X
    STA LCD_DATA
    ;JSR lcd_delay
    INX
    INY
    CPY #LCD_COLS
    BNE refresh_line1
    
    ; Calculate second line (next line in circular buffer)
    LDA SCROLL_VIEW_TOP
    CLC 
    ADC #$01
    CMP #SCROLL_BUFFER_SIZE
    BNE calc_second_line
    LDA #0                  ; Wrap around
calc_second_line:
    ASL A                   ; Multiply by 16
    ASL A
    ASL A
    ASL A
    TAX
    
    ; Display second line
    LDA #LCD_ROW1_COL0_ADDR
    JSR lcd_command
    LDY #0
refresh_line2:
    LDA SCROLL_BUFFER,X
    STA LCD_DATA
    ;JSR lcd_delay
    INX
    INY
    CPY #LCD_COLS
    BNE refresh_line2
    
    RTS

add_row1_to_scroll_buffer:
    ; Add current LCD_LINE1_BUFFER and LCD_LINE2_BUFFER to scroll buffer
    
    ; First, add line 1 to buffer
    LDA SCROLL_HEAD
    CLC 
    ADC #$01
    CMP #SCROLL_BUFFER_SIZE
    BNE store_head1
    LDA #0                  ; Wrap around
store_head1:
    STA SCROLL_HEAD
    
    ; Calculate buffer offset
    ASL A                   ; Multiply by 16
    ASL A
    ASL A
    ASL A
    TAX
    
    ; Copy LCD_LINE1_BUFFER to scroll buffer
    LDY #0
copy_line1:
    LDA LCD_LINE1_BUFFER,Y
    STA SCROLL_BUFFER,X
    INX
    INY
    CPY #LCD_COLS
    BNE copy_line1
    
    ; Update count and tail if buffer is full
    LDA SCROLL_COUNT
    CMP #SCROLL_BUFFER_SIZE
    BEQ update_tail1
    INC SCROLL_COUNT
    JMP add_line2
update_tail1:
    INC SCROLL_TAIL
    LDA SCROLL_TAIL
    CMP #SCROLL_BUFFER_SIZE
    BNE add_line2
    LDA #0
    STA SCROLL_TAIL
    
add_line2:
    ; Add line 2 to buffer
    LDA SCROLL_HEAD
    CLC 
    ADC #$01
    CMP #SCROLL_BUFFER_SIZE
    BNE store_head2
    LDA #0
store_head2:
    STA SCROLL_HEAD
    
    ASL A
    ASL A
    ASL A
    ASL A
    TAX
    
    LDY #0
copy_line2:
    LDA LCD_LINE2_BUFFER,Y
    STA SCROLL_BUFFER,X
    INX
    INY
    CPY #LCD_COLS
    BNE copy_line2
    
    LDA SCROLL_COUNT
    CMP #SCROLL_BUFFER_SIZE
    BEQ update_tail2
    INC SCROLL_COUNT
    RTS
update_tail2:
    INC SCROLL_TAIL
    LDA SCROLL_TAIL
    CMP #SCROLL_BUFFER_SIZE
    BNE done_add_line
    LDA #0
    STA SCROLL_TAIL
done_add_line:
    RTS

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
    ;; scroll up down - Initialize scroll buffer
    JSR init_scroll_buffer
    RTS

;; scroll up down - Initialize scroll buffer variables
init_scroll_buffer:
    LDA #0
    STA SCROLL_HEAD
    STA SCROLL_TAIL
    STA SCROLL_VIEW_TOP
    STA SCROLL_COUNT
    STA SCROLL_MODE
    RTS

lcd_clear:
    LDA #LCD_CLEAR
    JSR lcd_command
    ; Reset cursor position

    ; row 2 start - Always start cursor at row 2 (bottom row)
    LDA #0
    STA LCD_CURRENT_COL
    LDA #1                      ; row 2 start - Set to row 2 (1) instead of row 1 (0)
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
    ; row 2 start - Always position cursor at row 2 (bottom row)
    LDA #0
    STA LCD_CURRENT_COL
    LDA #1                      ; row 2 start - Set to row 2 instead of row 1
    STA LCD_CURRENT_ROW
    LDA #LCD_ROW1_COL0_ADDR     ; row 2 start - Position at row 2 address
    JSR lcd_command
    RTS

lcd_command:
    ; Send command to LCD
    ; For basic setup, we'll assume LCD_CMD register exists
    ; If not available, this would need timing loops
    STA LCD_CMD
;    JSR lcd_delay
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
    ;JSR lcd_delay
    JSR lcd_store_char_in_buffer   
    INC LCD_CURRENT_COL
 
    LDY Y_SCRATCH      ; bug_report at 4426a08
    LDX X_SCRATCH      ; 
    RTS

do_wrap_and_print:
    PHA
    ; row 2 start - Since cursor is always on row 2, always scroll up when wrapping
    JSR lcd_scroll_up          
    PLA                        
    JMP do_normal              

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
                               
    ; row 2 start - Cursor always stays at start of line 2
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
    ;JSR lcd_delay              
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
    ;JSR lcd_delay              
    INX                        
    CPX #LCD_COLS              
    BNE refresh_line2_loop     
    RTS                        

lcd_store_char_in_buffer:      
    ; row 2 start - Since cursor is always on row 2, always store in line 2 buffer
    LDX LCD_CURRENT_COL        
    STA LCD_LINE2_BUFFER,X     
    RTS                        

lcd_clear_line_buffer:         
    ; row 2 start - Since cursor is always on row 2, only clear line 2 buffer
    LDX #0                     
    LDA #' '                   
clear_line2_buf_loop_2:        
    STA LCD_LINE2_BUFFER,X     
    INX                        
    CPX #LCD_COLS              
    BNE clear_line2_buf_loop_2   
    RTS                        

lcd_carriage_return:
    ; row 2 start - Since cursor is always on row 2, always position at start of row 2
    LDA #0
    STA LCD_CURRENT_COL
    LDA #LCD_ROW1_COL0_ADDR    ; row 2 start - Always use row 2 address
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
    ;JSR lcd_delay
    JSR lcd_store_char_in_buffer   
    
    ; Move cursor back again
    JSR lcd_update_cursor
    RTS

backspace_prev_line:
    ; At start of line, can't backspace further
    ; (Could implement wrap to previous line if desired)
    RTS

lcd_update_cursor:
    ; row 2 start - Since cursor is always on row 2, simplified cursor positioning
    LDA #LCD_ROW1_COL0_ADDR    ; row 2 start - Always use row 2 base address
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
    ;JSR lcd_delay
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


; # Scroll Buffer Visual Explanation

; ## Buffer Structure
; The scroll buffer is a **circular buffer** that holds 16 lines, each 16 characters wide:

; ```
; SCROLL_BUFFER (256 bytes total):
; ┌─────────────────┐
; │ Line 0 (16 ch)  │  ← Index 0  (bytes 0-15)
; │ Line 1 (16 ch)  │  ← Index 1  (bytes 16-31)
; │ Line 2 (16 ch)  │  ← Index 2  (bytes 32-47)
; │      ...        │
; │ Line 15 (16 ch) │  ← Index 15 (bytes 240-255)
; └─────────────────┘
; ```

; ## Key Variables
; - **SCROLL_HEAD**: Points to the newest line (last written)
; - **SCROLL_TAIL**: Points to the oldest line (first to be overwritten)
; - **SCROLL_COUNT**: Number of lines currently stored (0-16)
; - **SCROLL_VIEW_TOP**: Which line is shown at top of LCD when scrolling

; ## How Lines Are Added

; ### Initial State (Empty Buffer)
; ```
; HEAD=0, TAIL=0, COUNT=0
; ┌─────────────────┐
; │ Line 0 [empty]  │  ← HEAD, TAIL
; │ Line 1 [empty]  │
; │ Line 2 [empty]  │
; │      ...        │
; │ Line 15 [empty] │
; └─────────────────┘
; ```

; ### Step 1: First Carriage Return (adds 2 lines)
; When user presses Enter, `do_carriage` → `add_line_to_scroll_buffer`:

; 1. **Add LINE1_BUFFER**:
;    ```
;    HEAD moves: 0 → 1, COUNT: 0 → 1
;    ┌─────────────────┐
;    │ Line 0 [empty]  │  ← TAIL
;    │ Line 1 [LINE1]  │  ← HEAD (just written)
;    │ Line 2 [empty]  │
;    │      ...        │
;    └─────────────────┘
;    ```

; 2. **Add LINE2_BUFFER**:
;    ```
;    HEAD moves: 1 → 2, COUNT: 1 → 2
;    ┌─────────────────┐
;    │ Line 0 [empty]  │  ← TAIL
;    │ Line 1 [LINE1]  │
;    │ Line 2 [LINE2]  │  ← HEAD (just written)
;    │ Line 3 [empty]  │
;    │      ...        │
;    └─────────────────┘
;    ```

; ### Step 2: After Several Carriage Returns
; ```
; HEAD=8, TAIL=0, COUNT=8
; ┌─────────────────┐
; │ Line 0 [empty]  │  ← TAIL
; │ Line 1 [LINE1]  │  ← oldest data
; │ Line 2 [LINE2]  │
; │ Line 3 [LINE3]  │
; │ Line 4 [LINE4]  │
; │ Line 5 [LINE5]  │
; │ Line 6 [LINE6]  │
; │ Line 7 [LINE7]  │
; │ Line 8 [LINE8]  │  ← HEAD (newest)
; │ Line 9 [empty]  │
; │      ...        │
; └─────────────────┘
; ```

; ### Step 3: Buffer Full (16 lines)
; ```
; HEAD=0, TAIL=1, COUNT=16 (wraps around)
; ┌─────────────────┐
; │ Line 0 [LINE16] │  ← HEAD (newest, wrapped)
; │ Line 1 [LINE1]  │  ← TAIL (oldest)
; │ Line 2 [LINE2]  │
; │      ...        │
; │ Line 15[LINE15] │
; └─────────────────┘
; ```

; ### Step 4: Overwriting Old Data
; When buffer is full and we add new lines:
; ```
; Before: HEAD=0, TAIL=1
; After adding 2 new lines: HEAD=2, TAIL=3

; ┌─────────────────┐
; │ Line 0 [LINE16] │  (old)
; │ Line 1 [NEW1]   │  ← HEAD moved here
; │ Line 2 [NEW2]   │  ← HEAD moved here  
; │ Line 3 [LINE2]  │  ← TAIL moved here (LINE1 overwritten)
; │      ...        │
; └─────────────────┘
; ```

; ## Scrolling View

; ### Normal Display
; LCD shows the current LINE1_BUFFER and LINE2_BUFFER:
; ```
; LCD Display:
; ┌─────────────────┐
; │ Current Line 1  │  ← What user is typing
; │ Current Line 2  │  ← Current cursor position
; └─────────────────┘
; ```

; ### Scroll Mode Activated
; When user presses UP arrow:
; - SCROLL_VIEW_TOP = SCROLL_HEAD (start at newest)
; - Display shows 2 consecutive lines from scroll buffer

; ```
; Example: HEAD=8, user presses UP
; SCROLL_VIEW_TOP = 8

; LCD Display:
; ┌─────────────────┐
; │ Line 8 content  │  ← SCROLL_VIEW_TOP
; │ Line 9 content  │  ← SCROLL_VIEW_TOP + 1
; └─────────────────┘
; ```
; 
; bug_report : 
; if HEAD = 8, it means the latest line stored to the scroll buffer is line 8. 
; When user presses UP, the screen should show line 7 and 8 at 
; the top and bottom of LCD, respectively. 
; For this, SCROLL_VIEW_TOP should be 7 not 8. What do you think ?

; AI suggested before (b) and after (a) for the fix:
; scroll_up:
;     LDA SCROLL_MODE
;     BNE scroll_up_continue
;     ; Entering scroll mode for first time
;     LDA #1
;     STA SCROLL_MODE
;     LDA SCROLL_HEAD
; b   STA SCROLL_VIEW_TOP
; a   SEC                    ; scroll up fix - Set carry for subtraction
; a   SBC #1                 ; scroll up fix - SCROLL_VIEW_TOP = HEAD - 1
; a   BPL store_view_top     ; scroll up fix - If positive, store it
; a   LDA #SCROLL_BUFFER_SIZE-1  ; scroll up fix - If negative, wrap to 15
; astore_view_top:            ; scroll up fix
; a   STA SCROLL_VIEW_TOP    ; scroll up fix
    
; scroll_up_continue:
;     ; Check if we can scroll up (view_top != tail)
;     LDA SCROLL_VIEW_TOP
;     CMP SCROLL_TAIL
;     BEQ scroll_up_done      ; Can't scroll up anymore
    
;     ; Move view up one line
;     DEC SCROLL_VIEW_TOP
;     LDA SCROLL_VIEW_TOP
;     BPL scroll_up_refresh
;     LDA #SCROLL_BUFFER_SIZE-1  ; Wrap around
;     STA SCROLL_VIEW_TOP


; ### Scrolling Up Further
; User presses UP again:
; ```
; SCROLL_VIEW_TOP moves: 8 → 7

; LCD Display:
; ┌─────────────────┐
; │ Line 7 content  │  ← SCROLL_VIEW_TOP
; │ Line 8 content  │  ← SCROLL_VIEW_TOP + 1
; └─────────────────┘
; ```

; ### Scroll Limits
; - **Can't scroll up past TAIL**: `SCROLL_VIEW_TOP == SCROLL_TAIL` stops upward scrolling
; - **Can't scroll down past HEAD**: `SCROLL_VIEW_TOP == SCROLL_HEAD` stops downward scrolling

; ## Key Algorithm: Circular Buffer Math

; **Buffer Address Calculation**:
; ```assembly
; ; To get byte offset for line N:
; LDA line_index    ; 0-15
; ASL A             ; × 2
; ASL A             ; × 4  
; ASL A             ; × 8
; ASL A             ; × 16 = line_index * 16
; TAX               ; X = offset into SCROLL_BUFFER
; ```

; **Wraparound Logic**:
; ```assembly
; ; Increment with wraparound
; INC HEAD
; LDA HEAD
; CMP #SCROLL_BUFFER_SIZE  ; 16
; BNE no_wrap
; LDA #0                   ; Wrap to 0
; STA HEAD
; ```

; This design efficiently manages a rolling window of the last 16 lines displayed, 
; allowing users to scroll back through recent history without losing current typing position.