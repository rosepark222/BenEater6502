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


;summer_break:
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

check_wordgame:                         ; wordgame command
    LDA CMD_BUFFER,X                    ; wordgame command
    CMP wordgame_cmd,Y                  ; wordgame command
    BNE check_cd                        ; wordgame command - Not wordgame, try cd
    BEQ wordgame_match_check            ; wordgame command
wordgame_match_check:                   ; wordgame command
    INX                                 ; wordgame command
    INY                                 ; wordgame command
    LDA wordgame_cmd,Y                  ; wordgame command
    CMP #0                              ; wordgame command
    BNE check_wordgame                  ; wordgame command

    ; Matched "wordgame"                ; wordgame command
call_wordgame:                          ; wordgame command
    JSR start_wordgame                  ; wordgame command - jump to wordgame
    LDA #0                              ; wordgame command
    STA KEY_INPUT                       ; wordgame command
    RTS                                 ; wordgame command

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

check_cd:                               ; cd util
    LDX #0                              ; Reset X and Y for fresh comparison
    LDY #0                              ; Reset X and Y for fresh comparison
    LDA CMD_BUFFER,X                    ; cd util
    CMP cd_cmd,Y                        ; cd util
    BNE check_pwd                       ; cd util - Not cd, try pwd
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
    RTS                                 ; cd util
    
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

check_pwd:                              ; pwd util
    LDX #0                              ; Reset X and Y for fresh comparison
    LDY #0                              ; Reset X and Y for fresh comparison
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
    RTS                                 ; pwd util

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

check_ls:
    LDX #0                              ; Reset X and Y for fresh comparison
    LDY #0                              ; Reset X and Y for fresh comparison
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
    RTS

unknown_cmd:
    JSR print_unknown
    RTS


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; WORDGAME HANDLER - Word puzzle with auto-advance
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

start_wordgame:
    ; Initialize game
    JSR wg_init
    
wg_next_word:
    JSR wg_select_word         ; Pick next word
    JSR wg_create_puzzle       ; Create the blanked version
    
wg_game_loop:
    ; Display puzzle
    JSR wg_show_puzzle
    
    ; Clear input buffer
    LDA #0
    STA WG_INPUT_INDEX
    
    ; Get user input
wg_input_loop:
    JSR poll_keyboard
    BCC wg_input_loop          ; No key yet
    
    ;; Check for arrow keys FIRST
    CMP #KEY_UP
    BEQ wg_handle_scroll_up
    CMP #KEY_DOWN
    BEQ wg_handle_scroll_down
    
    CMP #$0D                   ; Enter key?
    BEQ wg_check_answer
    
    CMP #$08                   ; Backspace?
    BEQ wg_handle_backspace
    
    ; Store character
    LDX WG_INPUT_INDEX
    CPX #15                    ; Max 15 chars
    BCS wg_input_loop
    
    STA WG_INPUT_BUFFER,X
    JSR print_char
    INX
    STX WG_INPUT_INDEX
    LDA #0
    STA KEY_INPUT
    JMP wg_input_loop

;; Handle scrolling during wordgame
wg_handle_scroll_up:
    JSR scroll_up
    LDA #0
    STA KEY_INPUT
    JMP wg_input_loop

wg_handle_scroll_down:
    JSR scroll_down
    LDA #0
    STA KEY_INPUT
    JMP wg_input_loop

wg_handle_backspace:
    LDX WG_INPUT_INDEX
    BEQ wg_input_loop_clear
    DEX
    STX WG_INPUT_INDEX
    JSR lcd_backspace
wg_input_loop_clear:
    LDA #0
    STA KEY_INPUT
    JMP wg_input_loop

wg_check_answer:
    ; Check if anything was typed
    LDX WG_INPUT_INDEX
    BEQ wg_input_loop_restart  ; Nothing typed, just restart input
    
    ; Null-terminate input
    LDA #0
    STA WG_INPUT_BUFFER,X
    STA KEY_INPUT
    
    ; Compare with secret word
    LDX #0
wg_compare_loop:
    LDA WG_INPUT_BUFFER,X
    CMP WG_CURRENT_WORD,X
    BNE wg_wrong_answer
    CMP #0                     ; End of both strings?
    BEQ wg_correct_answer
    INX
    JMP wg_compare_loop

wg_input_loop_restart:
    LDA #0
    STA KEY_INPUT
    JMP wg_input_loop          ; Go back to input without showing error

wg_correct_answer:
    JSR lcd_new_line
    LDY #0
wg_print_win:
    LDA wg_win_msg,Y
    BEQ wg_next_word_prompt
    JSR print_char
    INY
    JMP wg_print_win

wg_next_word_prompt:
    JSR lcd_new_line
    
    ; Check if we've completed all words
    LDA WG_WORD_INDEX
    CMP #WG_NUM_WORDS
    BCC wg_continue             ; More words available
    
    ; All words completed!
    LDY #0
wg_print_complete:
    LDA wg_complete_msg,Y
    BEQ wg_exit
    JSR print_char
    INY
    JMP wg_print_complete

wg_continue:
    ; Show "Next word..." message
    LDY #0
wg_print_next:
    LDA wg_next_msg,Y
    BEQ wg_wait_continue
    JSR print_char
    INY
    JMP wg_print_next

wg_wait_continue:
    JSR lcd_new_line
    ; Wait for any key press to continue
wg_wait_key:
    JSR poll_keyboard
    BCC wg_wait_key
    LDA #0
    STA KEY_INPUT
    JSR lcd_new_line
    JMP wg_next_word           ; Move to next word

wg_wrong_answer:
    JSR lcd_new_line
    LDY #0
wg_print_wrong:
    LDA wg_wrong_msg,Y
    BEQ wg_try_again           ; Try again after wrong answer
    JSR print_char
    INY
    JMP wg_print_wrong

wg_try_again:
    JSR lcd_new_line
    JMP wg_game_loop           ; Go back to prompt for new attempt

wg_exit:
    RTS

wg_init:
    ; Reset word index to start from beginning
    LDA #0
    STA WG_WORD_INDEX
    
    ; Print intro message
    LDY #0
wg_print_intro:
    LDA wg_intro_msg,Y
    BEQ wg_init_done
    JSR print_char
    INY
    JMP wg_print_intro
wg_init_done:
    JSR lcd_new_line
    RTS

wg_select_word:
    ; Get current word index
    LDA WG_WORD_INDEX
    
    ; Calculate word address: word_list + (index * 16)
    ; Each word takes 16 bytes (max word length)
    ASL A                      ; x2
    ASL A                      ; x4
    ASL A                      ; x8
    ASL A                      ; x16
    TAX
    
    ; Copy selected word to WG_CURRENT_WORD
    LDY #0
wg_copy_word:
    LDA wg_word_list,X
    STA WG_CURRENT_WORD,Y
    BEQ wg_copy_done
    INX
    INY
    CPY #15
    BNE wg_copy_word
wg_copy_done:
    
    ; Increment word index for next game
    INC WG_WORD_INDEX
    RTS

wg_create_puzzle:
    ; Count word length
    LDY #0
wg_count_len:
    LDA WG_CURRENT_WORD,Y
    BEQ wg_len_done
    INY
    JMP wg_count_len
wg_len_done:
    STY WG_WORD_LEN
    
    ; Decide how many letters to blank (2 or 4)
    ; If word length <= 5, blank 2 letters
    ; If word length > 5, blank 4 letters
    CPY #6
    BCC wg_blank_2
    LDA #4
    JMP wg_store_blank_count
wg_blank_2:
    LDA #2
wg_store_blank_count:
    STA WG_BLANK_COUNT
    
    ; Copy word to puzzle buffer
    LDX #0
wg_copy_to_puzzle:
    LDA WG_CURRENT_WORD,X
    STA WG_PUZZLE,X
    BEQ wg_puzzle_copied
    INX
    JMP wg_copy_to_puzzle
wg_puzzle_copied:
    
    ; Blank out letters
    ; Simple algorithm: blank every other letter starting from position 1
    LDA WG_BLANK_COUNT
    STA WG_BLANKS_LEFT
    LDA #1                     ; Start at position 1
    STA WG_BLANK_POS
    
wg_blank_loop:
    LDA WG_BLANKS_LEFT
    BEQ wg_blanking_done
    
    LDX WG_BLANK_POS
    CPX WG_WORD_LEN
    BCS wg_blanking_done       ; Past end of word
    
    ; Blank this position
    LDA #'_'
    STA WG_PUZZLE,X
    
    ; Move to next position (skip 1)
    LDA WG_BLANK_POS
    CLC
    ADC #2
    STA WG_BLANK_POS
    
    DEC WG_BLANKS_LEFT
    JMP wg_blank_loop
    
wg_blanking_done:
    RTS

wg_show_puzzle:
    ; Show the puzzle with blanks
    LDY #0
wg_print_puzzle_msg:
    LDA wg_puzzle_msg,Y
    BEQ wg_print_puzzle_word
    JSR print_char
    INY
    JMP wg_print_puzzle_msg
    
wg_print_puzzle_word:
    LDY #0
wg_print_puzzle_loop:
    LDA WG_PUZZLE,Y
    BEQ wg_puzzle_shown
    JSR print_char
    INY
    JMP wg_print_puzzle_loop
    
wg_puzzle_shown:
    JSR lcd_new_line
    
    ; Print prompt
    LDY #0
wg_print_prompt:
    LDA wg_prompt_msg,Y
    BEQ wg_prompt_done
    JSR print_char
    INY
    JMP wg_print_prompt
wg_prompt_done:
    RTS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; WORDGAME DATA
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

wg_intro_msg:     .byte "start", 0
wg_puzzle_msg:    .byte "Word: ", 0
wg_prompt_msg:    .byte "Guess: ", 0
wg_win_msg:       .byte "CORRECT!", 0
wg_wrong_msg:     .byte "WRONG! TRY", 0
wg_next_msg:      .byte "Next word...", 0
wg_complete_msg:  .byte "ALL DONE!", 0

; Word list - each word padded to 16 bytes
; Add your words here (max 15 chars each)
wg_word_list:
    .byte "planet", 0,0,0,0,0,0,0,0,0,0
    .byte "forest", 0,0,0,0,0,0,0,0,0,0
    .byte "hornet", 0,0,0,0,0,0,0,0,0,0
    .byte "rocket", 0,0,0,0,0,0,0,0,0,0
    .byte "garden", 0,0,0,0,0,0,0,0,0,0
    .byte "knight", 0,0,0,0,0,0,0,0,0,0
    .byte "library", 0,0,0,0,0,0,0,0,0
    .byte "machine", 0,0,0,0,0,0,0,0,0
    .byte "battery", 0,0,0,0,0,0,0,0,0
    .byte "triangle", 0,0,0,0,0,0,0,0
    .byte "magnet", 0,0,0,0,0,0,0,0,0,0
    .byte "computer", 0,0,0,0,0,0,0,0
    .byte "keyboard", 0,0,0,0,0,0,0,0
    .byte "terminal", 0,0,0,0,0,0,0,0
    .byte "sandpiper", 0,0,0,0,0,0,0
    .byte "telescope", 0,0,0,0,0,0,0
    .byte "microscope", 0,0,0,0,0,0
    .byte "satellite", 0,0,0,0,0,0,0
    .byte "algorithm", 0,0,0,0,0,0
    .byte "processor", 0,0,0,0,0,0
    .byte "television", 0,0,0,0,0,0
    .byte "electricity", 0,0,0,0,0
    .byte "simulation", 0,0,0,0,0,0
    .byte "transmitter", 0,0,0,0,0
    .byte "automation", 0,0,0,0,0,0
    .byte "philosophy", 0,0,0,0,0,0
    .byte "mechanical", 0,0,0,0,0,0
    .byte "laboratory", 0,0,0,0,0,0
    .byte "technology", 0,0,0,0,0,0
    .byte "architecture", 0,0,0,0,0
    .byte "transmission", 0,0,0,0,0
    .byte "microbiology", 0,0,0,0
    .byte "intelligence", 0,0,0,0,0
    .byte "electromagnet", 0,0,0,0
    .byte "photosystem", 0,0,0,0,0
    .byte "cybernetics", 0,0,0,0,0
    .byte "neuroscience", 0,0,0,0
    .byte "thermodynamic", 0,0,0
    .byte "electromagnetic", 0,0
    .byte "intercommunication", 0


WG_NUM_WORDS = 40               ; Number of words in list

; Game variables
WG_WORD_INDEX:    .byte 0      ; Current word index
WG_INPUT_INDEX:   .byte 0
WG_WORD_LEN:      .byte 0
WG_BLANK_COUNT:   .byte 0
WG_BLANKS_LEFT:   .byte 0
WG_BLANK_POS:     .byte 0
WG_INPUT_BUFFER:  .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
WG_CURRENT_WORD:  .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
WG_PUZZLE:        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; DATA SECTION (existing)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

ls_cmd:         .byte "ls", 0
cd_cmd:         .byte "cd", 0           ; cd util
pwd_cmd:        .byte "pwd", 0          ; pwd util
wordgame_cmd:   .byte "wordgame", 0     ; wordgame command