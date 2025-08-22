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
    RTS                     ; cd util
    
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
    RTS                     ; pwd util

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
    RTS

unknown_cmd:
    JSR print_unknown
    RTS



ls_cmd:         .byte "ls", 0
cd_cmd:         .byte "cd", 0           ; cd util
pwd_cmd:        .byte "pwd", 0           ; pwd util
