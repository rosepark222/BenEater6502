; HD44780 LCD  
; the latest flow chart 
; https://claude.ai/public/artifacts/f1068269-3e7d-45ec-bc43-ecac6d8b7160

; which shows the below summary of function

; Three sources for display
;1, user input       -- stdin, echoing to termimal
;2, command results  -- stdout, priting to terminal from program output
;3, scroll buffer    -- terminal buffer ( history of stdout )

; 
;that is a great way to conceptualize the three primary sources for what you see displayed in a terminal. Your breakdown is accurate.
;
;1. User Input (Echoing)
;When you type characters on the keyboard, the terminal driver in the kernel immediately sends them back to the screen as part of an "echoing" process. This is not a direct path from stdin to stdout; the terminal driver handles it separately. It's an immediate visual confirmation of your input.
;
;2. Command Results (stdout)
;This is the most common source of terminal output. When you run a command like ls or echo "Hello, World!", the program writes its results to the stdout stream. The terminal emulator receives this stream and prints it to the screen in real-time. This is the primary channel for a program to communicate its results to you.
;
;3. Scrollback Buffer (History)
;The terminal emulator maintains a scrollback buffer to store a history of everything that has been printed to the screen. This includes both stdout and stderr from all programs. When you scroll up with your mouse or keyboard, you are viewing the contents of this buffer, which holds content that has already scrolled off the top of the active display area. This allows you to review past output without rerunning the commands.



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



; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; further simplications:

; case 1:
; replace
;     ; Display line 1 from buffer
;     JSR display_line_from_buffer
; with 
;     LDA #LCD_ROW0_COL0_ADDR    
;     JSR lcd_command
;     JSR display_chars_from_offset

; which removes display_line_from_buffer subroutine completely, because 
; it is strange to see display_line_from_buffer is used for the line 1 and 
; use display_chars_from_offset for the line 2
; AI coding style is strange!!!

; also 
; case 2:
; lcd_redraw_line_buffer 
; does not use zero page LCD_SRC_LO/HI for source data
; but rather directly drawing data from LCD_LINE1(2)_BUFFER
; this is literally what lcd_redraw_line_buffer should do

; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; bug_report : 1779d652cca1af1dd36c76d7e0dc2172146e41bf
;
; the attached code is based on the below idea: two buffers, line buffer and scroll buffer. 
; line buffer is two entries showing what is currently displayed in LCD and scroll buffer holds what scrolled up.
; I found scrolling logic is more complex because it needs to keep track of which buffer it needs to display -- from line buffer or scroll buffer.
; I think it is better to unify buffer which holds what are currently displayed and what scrolled out of LCD. In this way, scroll up and down is trivial -- choosing two lines from the unified buffer.
; Thus, I want you to  rewrite the code so that it combine line buffer and scroll buffer into a unified_lcd_buffer.

; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; bug_report : de0b41462768a587546e378849e1e979cd83bc40
;
; I realized that the code uses "wrap" in two meanings -- 
;   1) at the end of column, move to the next line, 
;   2) at the end of scroll buffer, move to the index 0 of the buffer.
; this is confusing. 

; AI suggested:
; do_wrap_and_print → do_lineWrap_and_print
; no_wrap_check → no_buffer_wrap_check
; no_line_wrap → no_line_buffer_wrap
; no_oldest_wrap → no_oldest_buffer_wrap

; But this still not clear because each "no_*_wrap" label is a jump destination that skips the wraparound handling code when it's not needed. 
; They function as jump destination and extra words just confuse the reader. 

; Finally, this is chosen names:
; no_buffer_wrap_check  → no_bufferWrap_0  : Skip bufferWrap in scroll down check
; no_line_buffer_wrap   → no_bufferWrap_1  : Skip bufferWrap when advancing current line
; no_oldest_buffer_wrap → no_bufferWrap_2  : Skip bufferWrap when advancing oldest line
; Now, the code is now much cleaner with the simplified jump labels:

; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; bug_report : 55cdfecdeede0bc267b54025374c26e93cc7ceea  

; I added DEC UNIFIED_CURRENT_COL to fix a cursor misalignment when backspacing.

; Previously, the cursor was always one column too far to the right before trying to erase a character. This meant that backspace often replaced the wrong position with a space (overwriting nothing), so nothing appeared to happen. This happened because the LCD has a default behaivior that automatically moves the cursor one spot
; to the right after writing a character (This behaivior is implemented so that when writing strings, the computers cursor is constantly behind the text for writing.). 
; This can be solved by adding DEC UNIFIED_CURRENT_COL to counteract the default behaivior and move the cursor back. 

; Example:
; If the screen showed "< ls", it means the cursor is at column 4 (after 's'). To remove 's', do the following:
; 1, move cursor to column 3 ( at s)
; 2, write space --> this moves the cursor right of s
; 3, move cursor to column 3 

; see lcd_backspace:

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;commit 278353e824d5040f82e7740db04c2ac4c2ec76bc
;added LDA #0
;STA KEY_INPUT
 
;The code would previously continuously print "unknown command" nonstop before, 
;when it was supposed to only print it once.
;This bug would happen because the code would see KEY_INPUT 
;and print unknown command depending on if there were any pending strings inside of
;KEY_INPUT. But inside of the reset shell (part of the code where the shell
;prepares for the next command), there was no form of
;reseting KEY_INPUT after it was printed onto the LCD, resulting
;in the computer thinking it has still not been printed onto the LCD.
;The computer would then attempt to print KEY_INPUT onto the LCD over and over.
;
;The fix added, puts a value of 0 into the KEY_INPUT, reseting the pending strings inside KEY_INPUT.
;
;commit 433554cde7c1da66c501cb3800e75ea1f86ffb24
;Added 
;LDA CMD_INDEX
;BEQ reset_shell
;
;
;The code would previously still print Unknown cmd even if
;there was no cmd inserted into the lcd.
;
;This bug could be fixed by adding LDA CMD_INDEX and BEQ reset_shell
;into handle_enter so that the code could branch to reset_shell as long as CMD_INDEX had
;the value of "0" (Since CMD_INDEX keeps track of how many characters was typed, if CMD_INDEX
;has a value of 0, basically nothing or enter was typed into the LCD) (BEQ also branches if the
;last operation loaded was a 0. (Only LDA works like this as STA does not work as the registor values do not change))
;
;Now the LCD prints the prompt again "<" when nothing/enter was typed into the LCD. 
;
;
;HOW TO CREATE THE PR
; git checkout -b 'empty_cmd_fix'
; git commit -am 'fixed the code so that when an empty cmd was inserted, Unknown cmd was not printed'
; git push --set-upstream origin empty_cmd_fix
; 
;
;
;
;
;

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

keyinput_loop:
    JSR poll_keyboard
    BCC keyinput_loop          ; No key yet, poll again

    ;; Check for arrow keys first
    CMP #KEY_UP
    BEQ handle_key_up
    CMP #KEY_DOWN
    BEQ handle_key_down
    
    ;; Any other key exits scroll mode
    PHA                    ; Save the key value
    LDA SCROLL_MODE
    BEQ normal_key_processing_restore
    JSR exit_scroll_mode

normal_key_processing_restore:
    PLA                    ; Restore the key value
    CMP #$0D                ; Enter key (CR)
    BEQ handle_enter

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

;; Handle up arrow key
handle_key_up:
    JSR scroll_up
    LDA #0
    STA KEY_INPUT
    JMP keyinput_loop

;; Handle down arrow key  
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
    LDA CMD_INDEX
    BEQ reset_shell
    JSR process_shell_cmd

reset_shell:
    LDX #0
    STX CMD_INDEX
    ;Reset KEY_INPUT
    LDA #0
    STA KEY_INPUT

    ; Move to next line in unified buffer
    JSR lcd_new_line
    JSR print_prompt
    JMP keyinput_loop

;(つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ
;(つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ
;(つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ
;(つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ
;(つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ
;(つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ (つ◉益◉)つ

;; Unified buffer scroll routines
scroll_up:
    LDA SCROLL_MODE
    BNE scroll_up_continue
    
    ; Entering scroll mode - set view to show previous lines
    LDA #1
    STA SCROLL_MODE
    
    ; Set view to show the line before current bottom line
    LDA UNIFIED_CURRENT_LINE
    SEC
    SBC #1                     ; View top = current line - 1
    BPL store_view_top
    CLC
    ADC #UNIFIED_BUFFER_LINES  ; bufferWrap around
store_view_top:
    STA UNIFIED_VIEW_TOP
    
scroll_up_continue:
    ; Check if we can scroll up more
    LDA UNIFIED_VIEW_TOP
    CMP UNIFIED_OLDEST_LINE
    BEQ scroll_up_done         ; Can't scroll up anymore
    
    ; Move view up one line
    DEC UNIFIED_VIEW_TOP
    LDA UNIFIED_VIEW_TOP
    BPL scroll_up_refresh
    LDA #UNIFIED_BUFFER_LINES-1 ; bufferWrap around
    STA UNIFIED_VIEW_TOP
    
scroll_up_refresh:
    JSR lcd_redraw_from_unified_buffer
    
scroll_up_done:
    RTS

scroll_down:
    LDA SCROLL_MODE
    BEQ scroll_down_done       ; Not in scroll mode
    
    ; Check if we're at the current line
    LDA UNIFIED_VIEW_TOP
    CLC
    ADC #1                     ; Bottom of view = top + 1
    CMP #UNIFIED_BUFFER_LINES
    BNE no_bufferWrap_0
    LDA #0                     ; bufferWrap around
no_bufferWrap_0:
    CMP UNIFIED_CURRENT_LINE
    BEQ scroll_down_done       ; Already showing current line
    
    ; Move view down one line
    INC UNIFIED_VIEW_TOP
    LDA UNIFIED_VIEW_TOP
    CMP #UNIFIED_BUFFER_LINES
    BNE scroll_down_refresh
    LDA #0                     ; bufferWrap around
    STA UNIFIED_VIEW_TOP
    
scroll_down_refresh:
    JSR lcd_redraw_from_unified_buffer
    
scroll_down_done:
    RTS

exit_scroll_mode:
    LDA #0
    STA SCROLL_MODE
    
    ; Set view to show current line at bottom
    LDA UNIFIED_CURRENT_LINE
    SEC
    SBC #1                     ; Top line = current - 1
    BPL store_normal_view
    CLC
    ADC #UNIFIED_BUFFER_LINES  ; bufferWrap around
store_normal_view:
    STA UNIFIED_VIEW_TOP
    
    ; Refresh display and restore cursor
    JSR lcd_redraw_from_unified_buffer
    JSR lcd_update_cursor
    RTS




;¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯
;¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯
;¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯
;¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯
;¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯
;¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯¯\_(ツ)_/¯


print_char:
    STA A_SCRATCH
    STX X_SCRATCH
    STY Y_SCRATCH
    
    ; Check if we need lineWrap to next line
    LDX UNIFIED_CURRENT_COL
    CPX #LCD_COLS
    BCS do_lineWrap_and_print

do_normal:
    ; Store character in unified buffer
    JSR store_char_in_unified_buffer
    
    ; Display character if we're viewing current line
    LDA SCROLL_MODE
    BNE skip_direct_output     ; In scroll mode, don't output directly
    
;summer_break:
    LDA A_SCRATCH
    STA LCD_DATA
    ; INC UNIFIED_CURRENT_COL ; bug_report : 1779d652cca1af1dd36c76d7e0dc2172146e41bf
    
skip_direct_output:
    LDY Y_SCRATCH
    LDX X_SCRATCH
    RTS

do_lineWrap_and_print:
    PHA
    JSR lcd_new_line
    PLA
    JMP do_normal

lcd_new_line:
    ; Move to next line in unified buffer
    INC UNIFIED_CURRENT_LINE
    LDA UNIFIED_CURRENT_LINE
    CMP #UNIFIED_BUFFER_LINES
    BNE no_bufferWrap_1
    LDA #0                     ; bufferWrap around
    STA UNIFIED_CURRENT_LINE
no_bufferWrap_1:
    
    ; Update oldest line if buffer is full
    LDA UNIFIED_CURRENT_LINE
    CMP UNIFIED_OLDEST_LINE
    BNE no_oldest_update
    INC UNIFIED_OLDEST_LINE    ; Buffer is full, advance oldest
    LDA UNIFIED_OLDEST_LINE
    CMP #UNIFIED_BUFFER_LINES
    BNE no_bufferWrap_2
    LDA #0
    STA UNIFIED_OLDEST_LINE
no_bufferWrap_2:
no_oldest_update:
    
    ; Clear the new line
    JSR clear_current_line_in_buffer
    
    ; Reset column position
    LDA #0
    STA UNIFIED_CURRENT_COL
    
    ; If not in scroll mode, update display
    LDA SCROLL_MODE
    BNE new_line_done
    
    ; Update view and redraw
    LDA UNIFIED_CURRENT_LINE
    SEC
    SBC #1
    BPL update_view_top
    CLC
    ADC #UNIFIED_BUFFER_LINES
update_view_top:
    STA UNIFIED_VIEW_TOP
    
    JSR lcd_redraw_from_unified_buffer
    JSR lcd_home_cursor
    
new_line_done:
    RTS

store_char_in_unified_buffer:
    ; Calculate address in unified buffer
    ; Address = UNIFIED_LCD_BUFFER + (current_line * LCD_COLS) + current_col
    PHA
    LDA UNIFIED_CURRENT_LINE
    ; Multiply by LCD_COLS (16)
    ASL A                      ; x2
    ASL A                      ; x4  
    ASL A                      ; x8
    ASL A                      ; x16
    CLC
    ADC UNIFIED_CURRENT_COL
    TAX
    
    ; Store the character (it's still in A from print_char)
    PLA
    STA UNIFIED_LCD_BUFFER,X
    
    ; Advance column if not in scroll mode
    LDA SCROLL_MODE
    BNE store_char_done
    INC UNIFIED_CURRENT_COL
    
store_char_done:
    RTS

clear_current_line_in_buffer:
    ; Clear the current line in unified buffer
    LDA UNIFIED_CURRENT_LINE
    ASL A                      ; Multiply by LCD_COLS (16)
    ASL A
    ASL A
    ASL A
    TAX                        ; X = start of line
    
    LDY #0
    LDA #' '
clear_line_loop:
    STA UNIFIED_LCD_BUFFER,X
    INX
    INY
    CPY #LCD_COLS
    BNE clear_line_loop
    RTS


; ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿
; ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿
; ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿
; ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿
; ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿
; ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿ ̿̿'̿'\̵͇̿̿\=(•̪●)=/̵͇̿̿/'̿̿ ̿ ̿ ̿




lcd_redraw_from_unified_buffer:
    ; Display two lines starting from UNIFIED_VIEW_TOP
    
    ; Calculate top line address
    LDA UNIFIED_VIEW_TOP
    ASL A                      ; Multiply by LCD_COLS (16)
    ASL A
    ASL A
    ASL A
    TAX
    
    ; Display top line (LCD row 0)
    LDA #LCD_ROW0_COL0_ADDR
    JSR lcd_command ; Andy -- move cursor to the position specified by A register
    LDY #0
redraw_top_line:
    LDA UNIFIED_LCD_BUFFER,X
    STA LCD_DATA ; Andy --     write register A to LCD on the current cursor and move cursor to the right
    INX
    INY
    CPY #LCD_COLS
    BNE redraw_top_line
    
    ; Calculate bottom line (next line in circular buffer)
    LDA UNIFIED_VIEW_TOP
    CLC
    ADC #1
    CMP #UNIFIED_BUFFER_LINES
    BNE calc_bottom_line
    LDA #0                     ; bufferWrap around
calc_bottom_line:
    ASL A                      ; Multiply by LCD_COLS (16)
    ASL A
    ASL A
    ASL A
    TAX
    
    ; Display bottom line (LCD row 1)
    LDA #LCD_ROW1_COL0_ADDR
    JSR lcd_command
    LDY #0
redraw_bottom_line:
    LDA UNIFIED_LCD_BUFFER,X
    STA LCD_DATA
    INX
    INY
    CPY #LCD_COLS
    BNE redraw_bottom_line
    
    RTS

lcd_backspace:
; summer_break:   
    ; Move cursor back one position
    LDA UNIFIED_CURRENT_COL
    BEQ backspace_done         ; At start of line, can't backspace
    ; Move back one column
    DEC UNIFIED_CURRENT_COL
    
    ; Clear character in buffer
    LDA #' '
    JSR store_char_in_unified_buffer
    
    ; Update display if not in scroll mode
    LDA SCROLL_MODE
    BNE backspace_done
    
    ; Move cursor back because store_char_in_unified_buffer advanced it 
    DEC UNIFIED_CURRENT_COL
    JSR lcd_update_cursor
    LDA #' '
    STA LCD_DATA
    JSR lcd_update_cursor      ; Move cursor back again
    
backspace_done:
    RTS

lcd_update_cursor:
    ; Calculate cursor position based on current view
    ; If we're viewing the current line, position cursor normally
    ; Otherwise, cursor positioning doesn't matter (we're in scroll mode)
    
    LDA SCROLL_MODE
    BNE cursor_update_done     ; In scroll mode, don't update cursor
    
    ; Position cursor at bottom row, current column
    LDA #LCD_ROW1_COL0_ADDR
    CLC
    ADC UNIFIED_CURRENT_COL
    JSR lcd_command
    
cursor_update_done:
    RTS

;; LCD driver with unified buffer

lcd_init:
    ; Initialize LCD in 8-bit mode, 2-line display
    LDA #LCD_FUNCTION
    JSR lcd_command
    LDA #LCD_DISPLAY 
    JSR lcd_command
    LDA #LCD_ENTRY
    JSR lcd_command
    JSR lcd_clear
    JSR init_unified_buffer
    RTS

init_unified_buffer:
    ; Clear the entire unified buffer
    LDX #0
    LDA #' '
clear_unified_loop:
    STA UNIFIED_LCD_BUFFER,X
    INX
    BNE clear_unified_loop     ; Clear all 256 bytes
    
    ; Initialize buffer management variables
    LDA #0
    STA UNIFIED_CURRENT_LINE   ; Start at line 0
    STA UNIFIED_OLDEST_LINE    ; Oldest line is also 0
    STA UNIFIED_CURRENT_COL    ; Start at column 0
    STA UNIFIED_VIEW_TOP       ; View starts at line 0
    STA SCROLL_MODE
    
    ; Set view to show line 0 as top line (line 1 will be bottom, empty)
    LDA #0
    STA UNIFIED_VIEW_TOP
    
    RTS

lcd_clear:
    LDA #LCD_CLEAR
    JSR lcd_command
    RTS

lcd_home_cursor:
    ; Position cursor at bottom line (row 1), column 0
    LDA #0
    STA UNIFIED_CURRENT_COL
    LDA #LCD_ROW1_COL0_ADDR
    JSR lcd_command
    RTS

lcd_command:
    STA LCD_CMD
    RTS

; === Original Shell Routines (Unchanged) ===

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

;summer_break:
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

prompt_msg:     .byte "> ", 0
unk_msg:        .byte " UK_CMD", 0
