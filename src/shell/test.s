KEY_INPUT    = $0300        ; key byte buffer
LCD         = $6000
;PATH_INPUT  = $0400
CMD_BUFFER  = $0400         ; command string buffer
CMD_MAX     = 64            ; Max command length

 

start_shell:
    JSR print_prompt

shell_loop:
    JSR poll_keyboard
    BCC shell_loop          ; No key yet, poll again
    CMP #$0D                ; Enter key?
    BEQ process_command
    CMP #$08                ; Backspace?
    BEQ handle_backspace

    ; Ignore extra input if buffer full
    LDX CMD_INDEX
    CPX #CMD_MAX
    BCS shell_loop

    ; Normal character input
    JSR echo_to_lcd
    JSR store_char
    JMP shell_loop

handle_backspace:
    LDX CMD_INDEX
    BEQ shell_loop          ; No chars to delete

    DEX
    STX CMD_INDEX

    ; Send backspace to LCD (depends on your LCD handling)
    LDA #$08                ; ASCII Backspace
    STA LCD
    LDA #' '                ; Overwrite with space
    STA LCD
    LDA #$08                ; Move cursor back again
    STA LCD

    JMP shell_loop

process_command:
    LDX CMD_INDEX
    LDA #$00
    STA CMD_BUFFER,X        ; Null-terminate

    ; Reset CMD_INDEX for next command
    LDX #0
    STX CMD_INDEX

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
    JMP reset_shell

unknown_cmd:
    JSR print_unknown
    JMP reset_shell

reset_shell:
    LDX #0
    STX CMD_INDEX
    JMP start_shell

; --- Subroutines ---

poll_keyboard:
    LDA KEY_INPUT
    CMP #$00
    BEQ no_key
    SEC
    RTS
no_key:
    CLC
    RTS

echo_to_lcd:
    ; Input: A = character
    STA LCD
    RTS

store_char:
    ; Input: A = character
    LDX CMD_INDEX
    STA CMD_BUFFER,X
    INX
    STX CMD_INDEX
    LDA #$00        ; clear key buffer, otherwise same key is used again
    STA KEY_INPUT
    RTS

print_prompt:
    LDY #0
print_prompt_loop:
    LDA prompt_msg,Y
    BEQ done_prompt
    STA LCD
    INY
    JMP print_prompt_loop
done_prompt:
    LDX #0
    STX CMD_INDEX
    RTS

print_unknown:
    LDY #0
print_unk_loop:
    LDA unk_msg,Y
    BEQ done_unk
    STA LCD
    INY
    JMP print_unk_loop
done_unk:
    RTS

; --- Data ---

CMD_INDEX:      .byte 0
ls_cmd:         .byte "ls",0
; 0A	00001010	LF	&#10;	 	Line Feed
prompt_msg:     .byte "> ", $0A, 0
unk_msg:        .byte "Unknown command",13,0

; --- External entry point ---
;start_ls:    JMP $9000     ; Or wherever the ls utility begins

;            .org $FFFC
;            .word start_shell
;            .word start_shell
