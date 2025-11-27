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

; Game variables
BOX_X        = $0200      ; Box X position (0-75 pixels, 16 chars * 5 pixels - 2 pixels box width)
BOX_Y        = $0201      ; Box Y position (0-14 pixels, 2 rows * 8 pixels - 2 pixels box height)
FRAME_COUNTER = $0202     ; Frame counter for 30 FPS timing
SCAN_CODE_BUFFER = $0203 
BOX_X_COL    = 0204       ; Box X / 5
BOX_Y_COL    = 0205       ; Box Y / 8

; Keyboard variables
HANDSHAKE_DONE = $0222
PS2_BYTE_TEMP  = $0223
SCANCODE_STATE = $0224    ; 0=normal, 1=received F0 (skip next)
;BREAK_CODE_FLAG = $0225   ; Flag to indicate F0 (break code) was received

; Circular buffer for key input
KEY_BUFFER     = $0230    ; Buffer starts here (16 bytes)
KEY_BUF_HEAD   = $0240    ; Write pointer
KEY_BUF_TAIL   = $0241    ; Read pointer
KEY_BUF_SIZE   = 16       ; Must be power of 2

SCAN_ROW_POS = $0250      ; Current position in second row for scancode display (0-13, reserve 14-15 for position)

; PS/2 Scan codes for arrow keys and vi keys (make codes)
SCANCODE_UP    = $75
SCANCODE_DOWN  = $72
SCANCODE_LEFT  = $6B
SCANCODE_RIGHT = $74
SCANCODE_H     = $33  ; h - left
SCANCODE_J     = $3B  ; j - down
SCANCODE_K     = $42  ; k - up
SCANCODE_L     = $4B  ; l - right

; Shift key tracking
SHIFT_PRESSED  = $0242  ; 0=not pressed, $FF=pressed
LAST_KEY_CHAR  = $0243  ; Last key character to display

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
  STA SCANCODE_STATE
  STA KEY_BUF_HEAD
  STA KEY_BUF_TAIL
  STA SHIFT_PRESSED
  LDA #'x'
  STA LAST_KEY_CHAR

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
  ; Initialize box position to center of screen
  ; Center X: (80 pixels / 2) - 1 = 39 pixels
  ; Center Y: (16 pixels / 2) - 1 = 7 pixels
  LDA #39
  STA BOX_X
  LDA #7
  STA BOX_Y
  LDA #0
  STA SCAN_ROW_POS

  lda #"1"        ; before 5s
  sta LCD_PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta LCD_PORTA
  lda #RS         ; Clear E bits
  sta LCD_PORTA
  jsr lcd_long_delay   ; fast_clock

game_loop:
  ; Process input from key buffer
  JSR process_key_input
  
  ; Update box position (already done in process_key_input)
  
  ; Render the frame
  JSR render_frame
  
  ; Wait for next frame (30 FPS = 33.33ms per frame)
  JSR delay_frame
  
  JMP game_loop

; Process one key from the circular buffer
process_key_input:
  ; Check if buffer has data
  LDA KEY_BUF_HEAD
  CMP KEY_BUF_TAIL
  BEQ no_key_available
  
  ; Read from buffer
  LDX KEY_BUF_TAIL
  LDA KEY_BUFFER,X

  STA SCAN_CODE_BUFFER


  ; Increment tail pointer (with wrap)
  INX
  TXA
  AND #(KEY_BUF_SIZE - 1)
  STA KEY_BUF_TAIL
  

  ; Save scancode for character lookup
  ; PHA
  LDA SCAN_CODE_BUFFER
  ; Look up character in keymap and store
  JSR lookup_keymap_char
  STA LAST_KEY_CHAR
  
  ; Restore scancode and process movement
  ; PLA
  LDA SCAN_CODE_BUFFER
  
  ; Check for arrow keys
  CMP #SCANCODE_UP
  BEQ move_up
  CMP #SCANCODE_DOWN
  BEQ move_down
  CMP #SCANCODE_LEFT
  BEQ move_left
  CMP #SCANCODE_RIGHT
  BEQ move_right
  
  ; Check for vi keys
  CMP #SCANCODE_K
  BEQ move_up
  CMP #SCANCODE_J
  BEQ move_down
  CMP #SCANCODE_H
  BEQ move_left
  CMP #SCANCODE_L
  BEQ move_right
  
no_key_available:
  RTS

; Look up character in keymap based on scancode in A
lookup_keymap_char:
  TAY  ; Save scancode in Y
  
  ; Check if shift is pressed
  LDA SHIFT_PRESSED
  BEQ use_normal_keymap
  
use_shifted_keymap:
  LDA keymap_shifted,Y
  RTS
  
use_normal_keymap:
  LDA keymap,Y
  RTS

move_up:
  LDA BOX_Y
  SEC
  SBC #3
  BPL store_y
  LDA #0
store_y:
  STA BOX_Y
  RTS

move_down:
  LDA BOX_Y
  CLC
  ADC #3
  CMP #15        ; Max Y is 14 (16 - 2 pixel height)
  BCC store_y_down
  LDA #14
store_y_down:
  STA BOX_Y
  RTS

move_left:
  LDA BOX_X
  SEC
  SBC #3
  BPL store_x_left
  LDA #0
store_x_left:
  STA BOX_X
  RTS

move_right:
  LDA BOX_X
  CLC
  ADC #3
  CMP #74        ; Max X is 73 (80 - 5 - 2 pixel width)
  BCC store_x_right
  LDA #73
store_x_right:
  STA BOX_X
  RTS

















; Render the current frame
render_frame:
  ; Create custom character based on BOX_X and BOX_Y position
  JSR create_custom_character
  
  ; Clear display
  ;LDA #%00000001
  ;JSR lcd_instruction
  ;jsr lcd_long_delay ; 1.2ms or 2 ms need to clear all memories in LCD

  ; Calculate which character position to place the box
  ; Character column = BOX_X / 5
  ; Character row = BOX_Y / 8
  
  LDA BOX_Y
  LSR A
  LSR A
  LSR A          ; Divide by 8
  STA BOX_Y_COL
  BEQ first_row
  
second_row:
  ; Set cursor to second row
  LDA BOX_X 
  ORA #%11000000  ; Set DDRAM address to second row
  JSR get_char_col
  JSR lcd_instruction
  JMP display_char
  
first_row:
  ; Set cursor to first row
  LDA BOX_X 
  ORA #%10000000  ; Set DDRAM address to first row
  JSR get_char_col
  JSR lcd_instruction
  
display_char:
  ; Display custom character 0
  LDA #$00
  JSR print_char 
  ; STA LCD_PORTB
  ; LDA #RS
  ; STA LCD_PORTA
  ; LDA #(RS | E)
  ; STA LCD_PORTA
  ; LDA #RS
  ; STA LCD_PORTA
  ; JSR lcd_delay
  
  ; Display last key pressed at bottom right (position 15 of row 2)
  LDA #%11001101  ; DDRAM address for second row, position 13
  JSR lcd_instruction
  
  LDA BOX_X_COL
  JSR print_char 

  LDA BOX_Y_COL
  JSR print_char 

  LDA LAST_KEY_CHAR
  JSR print_char 



  LDA SCAN_CODE_BUFFER
  JSR print_scancode_hex
  
  RTS

; Convert BOX_X to character column (divide by 5)
get_char_col:
  PHA
  LDA BOX_X
  ; Divide by 5 using repeated subtraction
  LDX #0
div5_loop:
  CMP #5
  BCC div5_done
  SEC
  SBC #5
  INX
  JMP div5_loop
div5_done:
  TXA
  STA BOX_X_COL
  PLA
  ORA BOX_X_COL
  RTS




















; Create custom character based on box position
create_custom_character:
  ; Set CGRAM address to character 0
  LDA #%01000000
  JSR lcd_instruction
  
  ; Calculate pixel offsets within the character
  LDA BOX_X
calc_x_offset:
  LDX #0
x_offset_loop:
  CMP #5
  BCC x_offset_done
  SEC
  SBC #5
  INX
  JMP x_offset_loop
x_offset_done:
  STA $0251      ; X offset (0-4)
  
  LDA BOX_Y
calc_y_offset:
  LDX #0
y_offset_loop:
  CMP #8
  BCC y_offset_done
  SEC
  SBC #8
  INX
  JMP y_offset_loop
y_offset_done:
  STA $0252      ; Y offset (0-7)
  
  ; Generate 8 rows of custom character data
  LDX #0
gen_char_loop:
  TXA
  CMP $0252      ; Compare with Y offset
  BCC gen_empty_row
  SEC
  SBC $0252
  CMP #2         ; Box is 2 pixels tall
  BCS gen_empty_row
  
  ; This row contains part of the box
  LDA $0251      ; Get X offset
  JSR create_box_row
  JMP write_char_row
  
gen_empty_row:
  LDA #%00000000
  
write_char_row:
  STA LCD_PORTB
  PHA
  LDA #RS
  STA LCD_PORTA
  LDA #(RS | E)
  STA LCD_PORTA
  LDA #RS
  STA LCD_PORTA
  JSR lcd_delay
  PLA
  
  INX
  CPX #8
  BNE gen_char_loop
  
  RTS


; Create a row pattern for the box given X offset in A
create_box_row:
  CMP #0
  BEQ box_at_0
  CMP #1
  BEQ box_at_1
  CMP #2
  BEQ box_at_2
  CMP #3
  BEQ box_at_3
  ; box_at_4
  LDA #%00000011
  RTS
box_at_0:
  LDA #%00011000
  RTS
box_at_1:
  LDA #%00001100
  RTS
box_at_2:
  LDA #%00000110
  RTS
box_at_3:
  LDA #%00000011
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

  LDA KB_PORTB
  
  LDX HANDSHAKE_DONE
  BNE CHECK_SCANCODE_STATE
  
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

CHECK_SCANCODE_STATE:
  LDX SCANCODE_STATE
  BNE HANDLE_SKIP_STATE
  
  ; Check for shift key press (left shift = 0x12, right shift = 0x59)
  CMP #$12
  BEQ SET_SHIFT
  CMP #$59
  BEQ SET_SHIFT
  
  ; Normal state - check if this is F0
  CMP #$F0
  BNE STORE_SCANCODE
  
  ; Received F0 - set state to skip next
  LDA #1
  STA SCANCODE_STATE
  JMP CLEAR_IRQ

SET_SHIFT:
  LDA #$FF
  STA SHIFT_PRESSED
  JMP CLEAR_IRQ

HANDLE_SKIP_STATE:
  ; Check if releasing shift key
  CMP #$12
  BEQ CLEAR_SHIFT
  CMP #$59
  BEQ CLEAR_SHIFT
  
  ; Skip this scancode and return to normal state
  LDA #0
  STA SCANCODE_STATE
  JMP CLEAR_IRQ

CLEAR_SHIFT:
  LDA #0
  STA SHIFT_PRESSED
  STA SCANCODE_STATE
  JMP CLEAR_IRQ

STORE_SCANCODE:
  ; Store scancode in circular buffer
  PHA
  LDX KEY_BUF_HEAD
  PLA
  STA KEY_BUFFER,X
  
  ; Increment head pointer (with wrap)
  INX
  TXA
  AND #(KEY_BUF_SIZE - 1)
  STA KEY_BUF_HEAD

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

; Frame timing analysis for 1MHz clock (30 FPS = 33,333 cycles per frame)
;
; CYCLE COUNT ANALYSIS:
; ---------------------
; process_key_input:
;   - No key: ~15 cycles (buffer check + return)
;   - With key: ~15 + ~50 (read buffer + process) = ~65 cycles
;   - lookup_keymap_char: ~20 cycles (keymap lookup)
;   - Move function: ~25 cycles
;   - Total worst case: ~110 cycles
;
; render_frame:
;   - create_custom_character: ~2,500 cycles
;     * Set CGRAM: lcd_instruction = ~150 cycles
;     * Calculate offsets: ~50 cycles
;     * Generate 8 rows: 8 × (comparison + create_box_row + write) = 8 × 200 = 1,600 cycles
;     * lcd_delay per write: 8 × 130 = 1,040 cycles
;   - Clear display: lcd_instruction = ~150 cycles
;   - Calculate position: ~100 cycles
;   - Set cursor for box: lcd_instruction = ~150 cycles
;   - Display box character: ~150 cycles
;   - Set cursor for key display (bottom right): lcd_instruction = ~150 cycles
;   - Display key character: ~150 cycles
;   - Total: ~3,400 cycles
;
; TOTAL FRAME LOGIC: ~3,510 cycles
; TARGET FRAME TIME: 33,333 cycles (30 FPS at 1MHz)
; REQUIRED DELAY: 33,333 - 3,510 = 29,823 cycles
;
; Delay loop calculation:
; Inner loop: 5 cycles (lda + sbc + bne) = 5 cycles per iteration
; Middle loop: 256 inner iterations = 256 × 5 = 1,280 cycles + 5 overhead = 1,285 cycles
; Outer loop: Need 29,823 / 1,285 = ~23.2 iterations, use 23 for outer loop
; 23 × 1,285 = 29,555 cycles
; Add fine-tune inner loop for remaining: 29,823 - 29,555 = 268 cycles
; 268 / 5 = ~53 iterations

delay_frame:
  pha
  txa
  pha
  tya
  pha
  
  ; Outer loop: 23 iterations of full 256-cycle inner loops
  ldx #$17        ; 23 in decimal
  ;ldx #$FF        ; almost 23*33 -- meaning 1 sec delay
delay_outer:
  ldy #$00        ; 256 iterations
delay_middle:
  lda #$05        ; Small inner delay
delay_inner:
  sbc #$01
  bne delay_inner
  dey
  bne delay_middle
  dex
  bne delay_outer
  
  ; Fine-tune delay: ~268 additional cycles
  ldy #$35        ; 53 iterations
delay_fine:
  dey
  bne delay_fine
  
  pla
  tay
  pla
  tax
  pla
  rts

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

  .org $fd00
keymap:
  .byte "????????????? `?" ; 00-0F
  .byte "?????q1???zsaw2?" ; 10-1F
  .byte "?cxde43?? vftr5?" ; 20-2F
  .byte "?nbhgy6???mju78?" ; 30-3F
  .byte "?,kio09??./l;p-?" ; 40-4F
  .byte "??'?[=????",$0a,"]?\??" ; 50-5F
  .byte "?????????1?47???" ; 60-6F
  .byte "0.2568",$1b,"??+3-*9??" ; 70-7F
  .byte "????????????????" ; 80-8F
  .byte "????????????????" ; 90-9F
  .byte "????????????????" ; A0-AF
  .byte "????????????????" ; B0-BF
  .byte "????????????????" ; C0-CF
  .byte "????????????????" ; D0-DF
  .byte "????????????????" ; E0-EF
  .byte "????????????????" ; F0-FF
keymap_shifted:
  .byte "????????????? ~?" ; 00-0F
  .byte "?????Q!???ZSAW@?" ; 10-1F
  .byte "?CXDE#$?? VFTR%?" ; 20-2F
  .byte "?NBHGY^???MJU&*?" ; 30-3F
  .byte "?<KIO)(??>?L:P_?" ; 40-4F
  .byte '??"?{+?????}?|??' ; 50-5F
  .byte "?????????1?47???" ; 60-6F
  .byte "0.2568???+3-*9??" ; 70-7F
  .byte "????????????????" ; 80-8F
  .byte "????????????????" ; 90-9F
  .byte "????????????????" ; A0-AF
  .byte "????????????????" ; B0-BF
  .byte "????????????????" ; C0-CF
  .byte "????????????????" ; D0-DF
  .byte "????????????????" ; E0-EF
  .byte "????????????????" ; F0-FF

  .org $FFFA
  .word $0000
  .word reset
  .word IRQ_HANDLER

