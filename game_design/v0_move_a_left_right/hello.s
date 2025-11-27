LCD_PORTB = $6000
LCD_PORTA = $6001
LCD_DDRB = $6002
LCD_DDRA = $6003

KB_PORTB = $4000
KB_PORTA = $4001
KB_DDRB = $4002
KB_DDRA = $4003
KB_PCR   = $400C
KB_IFR   = $400D
KB_IER   = $400E

E  = %10000000
RW = %01000000
RS = %00100000

PS2_CLK_BIT  = %00000100
PS2_DATA_BIT = %00000010
PS2_INIT_AA  = $AA
PS2_REPLY_FF = $FF

; Simple game variables
CHAR_POS     = $0200      ; Position of 'a' character (0-15)
SCAN_ROW_POS = $0201      ; Current position in second row for scancode display (0-13, reserve 14-15 for position)
TIMER_COUNT  = $0202      ; Timer counter for 5 second clear (3 bytes for larger count)
TIMER_COUNT_MID = $0203
TIMER_COUNT_HI = $0204

; Keyboard variables
HANDSHAKE_DONE = $0222
PS2_BYTE_TEMP  = $0223
CURRENT_SCANCODE = $0224  ; Store the scancode received
BREAK_CODE_FLAG = $0225   ; Flag to indicate F0 (break code) was received

; PS/2 Scan codes for h and l
SCANCODE_H     = $33  ; h - left
SCANCODE_L     = $4B  ; l - right

  .org $8000

reset:
  SEI
  
keyboard_init:
  lda #%00000001
  sta KB_DDRA
  
  LDA #%00000000
  STA KB_DDRB
  
  LDA #$00
  STA HANDSHAKE_DONE
  STA CURRENT_SCANCODE
  STA BREAK_CODE_FLAG

lcd_init:
  lda #%11111111
  sta LCD_DDRB

  lda #%11100000
  sta LCD_DDRA

  jsr lcd_long_delay
  jsr lcd_long_delay
  jsr lcd_long_delay

  lda #%00111000  ; 8-bit mode; 2-line display; 5x8 font
  sta LCD_PORTB
  lda #0
  sta LCD_PORTA
  lda #E
  sta LCD_PORTA
  lda #0
  sta LCD_PORTA
  jsr lcd_delay

  lda #%00001100  ; Display on; cursor off; blink off
  sta LCD_PORTB
  lda #0
  sta LCD_PORTA
  lda #E
  sta LCD_PORTA
  lda #0
  sta LCD_PORTA
  jsr lcd_delay

  lda #%00000110  ; Increment and shift cursor
  sta LCD_PORTB
  lda #0
  sta LCD_PORTA
  lda #E
  sta LCD_PORTA
  lda #0
  sta LCD_PORTA
  jsr lcd_delay

  ; Clear display
  lda #%00000001
  jsr lcd_instruction

irq_setup:
  LDA KB_PCR
  AND #%11111110
  ORA #%00000001
  STA KB_PCR
  
  LDA #%10000010
  STA KB_IER
  
  LDA KB_PORTA
  CLI

game_init:
  ; Initialize character position to first column
  LDA #0
  STA CHAR_POS
  STA SCAN_ROW_POS
  
  ; Initialize timer for 5 second clear (5,000,000 cycles at 1MHz)
  ; Store as 24-bit value: $4C4B40
  LDA #$40
  STA TIMER_COUNT
  LDA #$4B
  STA TIMER_COUNT_MID
  LDA #$4C
  STA TIMER_COUNT_HI
  
  ; Display 'a' at first position
  JSR display_hero

main_loop:
  ; Decrement timer
  LDA TIMER_COUNT
  BNE dec_low
  LDA TIMER_COUNT_MID
  BNE dec_mid
  LDA TIMER_COUNT_HI
  BNE dec_high
  
  ; Timer reached zero - clear screen and reset
  JSR clear_screen_reset
  JMP main_loop

dec_low:
  DEC TIMER_COUNT
  JMP main_loop

dec_mid:
  DEC TIMER_COUNT_MID
  LDA #$FF
  STA TIMER_COUNT
  JMP main_loop

dec_high:
  DEC TIMER_COUNT_HI
  LDA #$FF
  STA TIMER_COUNT_MID
  STA TIMER_COUNT
  JMP main_loop

clear_screen_reset:
  ; Clear display
  LDA #%00000001
  JSR lcd_instruction
  
  ; Reset scancode position
  LDA #0
  STA SCAN_ROW_POS
  
  ; Reset timer
  LDA #$40
  STA TIMER_COUNT
  LDA #$4B
  STA TIMER_COUNT_MID
  LDA #$4C
  STA TIMER_COUNT_HI
  
  ; Redisplay 'a'
  JSR display_hero
  RTS

remove_hero:
  LDA CHAR_POS 
  ORA #%10000000  
  JSR lcd_instruction
  LDA #' '
  JSR print_char
  RTS
 
display_hero:
  ; Clear display
  ; for some reason, it clears the screen and below display did not work
  ; instead, remove previous 'a' and display the current 'a' worked
;  LDA #%00000001
;  JSR lcd_instruction
  
  ; Set cursor to first row, CHAR_POS position
  LDA CHAR_POS    ; Load position first
  ORA #%10000000  ; Then OR with first row base address
  JSR lcd_instruction
  
  ; Display 'a'
  LDA #'a'
  JSR print_char
  
  ; Display position at column 14-15 of second row
  ; JSR display_position
  
  RTS

; Display row and column position at second row columns 14-15
display_position:
  ; Set cursor to second row, column 14
  LDA #%11001110  ; Second row base + 14
  JSR lcd_instruction
  
  ; Display row (always 0 since we only have first row for 'a')
  LDA #'0'
  JSR print_char
  
  ; Set cursor to second row, column 15
  LDA #%11001111  ; Second row base + 15
  JSR lcd_instruction
  
  ; Display column position (convert CHAR_POS to ASCII digit)
  LDA CHAR_POS
  CMP #10
  BCC single_digit
  
  ; For positions 10-15, display A-F
  SEC
  SBC #10
  CLC
  ADC #'A'
  JSR print_char
  RTS
  
single_digit:
  CLC
  ADC #'0'
  JSR print_char
  RTS

; Print character in A to LCD
print_char:
  STA LCD_PORTB
  LDA #RS
  STA LCD_PORTA
  LDA #(RS | E)
  STA LCD_PORTA
  LDA #RS
  STA LCD_PORTA
  JSR lcd_delay
  RTS

; Print scancode as hex at current position in second row
print_scancode_hex:
  PHA  ; Save original scancode
  
  ; Set cursor to second row at SCAN_ROW_POS
  LDA SCAN_ROW_POS ; Load position first
  ORA #%11000000   ; Then OR with second row base address
  JSR lcd_instruction
  
  ; Print high nibble
  PLA
  PHA
  LSR A
  LSR A
  LSR A
  LSR A
  CMP #$0A
  BCC high_digit
  ADC #$06        ; Add 7 (6 + carry) to get A-F
high_digit:
  ADC #$30        ; Convert to ASCII
  JSR print_char
  
  ; Increment position
  INC SCAN_ROW_POS
  LDA SCAN_ROW_POS
  CMP #14         ; Stop at column 13 (reserve 14-15 for position display)
  BCC print_low_nibble
  LDA #0
  STA SCAN_ROW_POS
  
print_low_nibble:
  ; Set cursor again for low nibble
  LDA SCAN_ROW_POS ; Load position first
  ORA #%11000000   ; Then OR with second row base address
  JSR lcd_instruction
  
  ; Print low nibble
  PLA
  PHA
  AND #$0F
  CMP #$0A
  BCC low_digit
  ADC #$06        ; Add 7 (6 + carry) to get A-F
low_digit:
  ADC #$30        ; Convert to ASCII
  JSR print_char
  
  ; Increment position
  INC SCAN_ROW_POS
  LDA SCAN_ROW_POS
  CMP #14         ; Stop at column 13 (reserve 14-15 for position display)
  BCC done_print
  LDA #0
  STA SCAN_ROW_POS
  
done_print:
  PLA  ; Clean up stack
  RTS

; Send instruction to LCD
lcd_instruction:
  STA LCD_PORTB
  LDA #0
  STA LCD_PORTA
  LDA #E
  STA LCD_PORTA
  LDA #0
  STA LCD_PORTA
  JSR lcd_delay
  RTS

IRQ_HANDLER:
  PHA
  TXA
  PHA
  TYA
  PHA

  ; Read scancode from keyboard
  LDA KB_PORTB
  STA CURRENT_SCANCODE
  
  ; Check if handshake is complete
  LDX HANDSHAKE_DONE
  BNE PROCESS_SCANCODE
  
  ; Handshake logic
  CMP #PS2_INIT_AA
  BNE CLEAR_IRQ
  
  lda #%00000111
  sta KB_DDRA
  
  JSR send_ff_reply
  
  LDA #$FF
  STA HANDSHAKE_DONE
  
  LDA #%00000001
  STA KB_DDRA
  
  JMP CLEAR_IRQ

; PROCESS_SCANCODE:
;   ; Print all scancodes to second row
;   LDA CURRENT_SCANCODE
;   JSR print_scancode_hex
  
;   ; Check if it's 'h' (move left)
;   LDA CURRENT_SCANCODE
;   CMP #SCANCODE_H
;   BEQ move_left
  
;   ; Check if it's 'l' (move right)
;   CMP #SCANCODE_L
;   BEQ move_right
  
;   JMP CLEAR_IRQ


PROCESS_SCANCODE:

  LDA CURRENT_SCANCODE
  ; -------------------------------
  ; Check BREAK_CODE_FLAG
  ; -------------------------------
  LDX BREAK_CODE_FLAG
  BEQ NOT_IN_BREAK
; ===============================
; FLAG SET: this is the key released
; ===============================
IN_BREAK:
  LDA #0
  STA BREAK_CODE_FLAG        ; Clear flag
  ; Display released scancode
  LDA CURRENT_SCANCODE
  JSR print_scancode_hex
  ; Move left?
  CMP #SCANCODE_H
  BEQ move_left
  ; Move right?
  CMP #SCANCODE_L
  BEQ move_right

  JMP CLEAR_IRQ
; ===============================
; FLAG NOT SET: check for F0
; ===============================
NOT_IN_BREAK:
  CMP #$F0
  BNE CLEAR_IRQ              ; Not F0, ignore and return
  ; If F0 received, set break flag
  LDA #$01
  STA BREAK_CODE_FLAG
  JMP CLEAR_IRQ

move_left:
  LDA CHAR_POS
  BEQ CLEAR_IRQ  ; Already at leftmost position
  jsr remove_hero
  DEC CHAR_POS
  JSR display_hero
  jsr display_position
  JMP CLEAR_IRQ

move_right:
  LDA CHAR_POS
  CMP #15
  BEQ CLEAR_IRQ  ; Already at rightmost position
  jsr remove_hero
  INC CHAR_POS
  JSR display_hero
  jsr display_position
  JMP CLEAR_IRQ

CLEAR_IRQ:
  LDA KB_PORTA
  
  PLA
  TAY
  PLA
  TAX
  PLA
  
  RTI

send_ff_reply:
  LDA #PS2_REPLY_FF
  STA PS2_BYTE_TEMP
  
  LDX #$00
  LDY #$00
  
  LDA #$00
  STA KB_PORTA
  JSR ps2_long_delay
  
  LDA #$00
  STA KB_PORTA
  
  LDA KB_DDRA
  AND #%11111011
  STA KB_DDRA
  JSR ps2_delay
  
send_bit_loop:
  JSR wait_clock_low
  
  LDA PS2_BYTE_TEMP
  AND #$01
  BEQ send_zero
  
send_one:
  LDA #PS2_DATA_BIT
  STA KB_PORTA
  INY
  JMP next_bit
  
send_zero:
  LDA #$00
  STA KB_PORTA
  
next_bit:
  JSR wait_clock_high_sub
  
  LSR PS2_BYTE_TEMP
  INX
  CPX #$08
  BNE send_bit_loop
  
  JSR wait_clock_low
  
  TYA
  AND #$01
  BNE send_parity_zero
  
send_parity_one:
  LDA #PS2_DATA_BIT
  STA KB_PORTA
  JMP send_stop
  
send_parity_zero:
  LDA #$00
  STA KB_PORTA
  
send_stop:
  JSR wait_clock_high_sub
  JSR wait_clock_low
  
  LDA #PS2_DATA_BIT
  STA KB_PORTA
  JSR wait_clock_high_sub
  
  JSR wait_clock_low
  JSR wait_clock_high_sub
  
  LDA KB_DDRA
  AND #%11111001
  STA KB_DDRA
  JSR ps2_delay
  
  RTS

wait_clock_low:
  PHA
wait_clock_low_loop:
  LDA KB_PORTA
  AND #PS2_CLK_BIT
  BNE wait_clock_low_loop
  PLA
  RTS

wait_clock_high_sub:
  PHA
wait_clock_high_loop:
  LDA KB_PORTA
  AND #PS2_CLK_BIT
  BEQ wait_clock_high_loop
  PLA
  RTS

ps2_delay:
  PHA
  LDA #$0A
ps2_delay_loop:
  SBC #$01
  BNE ps2_delay_loop
  PLA
  RTS

ps2_long_delay:
  PHA
  LDA #$32
ps2_long_delay_loop:
  SBC #$01
  BNE ps2_long_delay_loop
  PLA
  RTS

lcd_delay:
  pha
  lda #$82
lcd_delay_loop:
  sbc #$01
  bne lcd_delay_loop
  pla
  rts

lcd_long_delay:
  pha
  lda #$FF
lcd_long_delay_loop:
  sbc #$01
  bne lcd_long_delay_loop
  pla
  rts

  .org $FFFA
  .word $0000
  .word reset
  .word IRQ_HANDLER