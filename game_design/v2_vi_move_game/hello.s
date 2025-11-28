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
BOX_X        = $0200
BOX_Y        = $0201
BOX_X_COL    = $0204
BOX_Y_COL    = $0205
SCAN_CODE_BUFFER = $0203

; Enemy system (max 5 enemies on screen)
ENEMY_POS    = $0210      ; Enemy positions array (16 bytes, one per column)
ENEMY_TIMER  = $0220      ; Timer for enemy movement (30 frames = 1 second)
SPAWN_TIMER  = $0221      ; Timer for spawning new enemies
SKIP_COUNT   = $0222      ; Number of times player used skip (w)
KILL_COUNT   = $0223      ; Number of enemies killed (x)
GAME_OVER    = $0224      ; Game over flag (0=playing, 1=dead)

; Keyboard variables
HANDSHAKE_DONE = $0230
PS2_BYTE_TEMP  = $0231
F0_DETECTED = $0232

; Circular buffer for key input
KEY_BUFFER     = $0240
KEY_BUF_HEAD   = $0250
KEY_BUF_TAIL   = $0251
KEY_BUF_SIZE   = 16

; Shift key tracking
SHIFT_PRESSED  = $0260
LAST_KEY_CHAR  = $0261

; PS/2 Scan codes
SCANCODE_H     = $33  ; h - left
SCANCODE_J     = $3B  ; j - down
SCANCODE_K     = $42  ; k - up
SCANCODE_L     = $4B  ; l - right
SCANCODE_W     = $1D  ; w - teleport/skip
SCANCODE_X     = $22  ; x - kill enemy

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
  STA F0_DETECTED
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

  lda #%00111000
  sta LCD_PORTB
  lda #0
  sta LCD_PORTA
  lda #E
  sta LCD_PORTA
  lda #0
  sta LCD_PORTA
  jsr lcd_delay

  lda #%00001100
  sta LCD_PORTB
  lda #0
  sta LCD_PORTA
  lda #E
  sta LCD_PORTA
  lda #0
  sta LCD_PORTA
  jsr lcd_delay

  lda #%00000110
  sta LCD_PORTB
  lda #0
  sta LCD_PORTA
  lda #E
  sta LCD_PORTA
  lda #0
  sta LCD_PORTA
  jsr lcd_delay

  lda #%00000001
  jsr lcd_instruction
  jsr lcd_long_delay

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
  ; Initialize box position
  LDA #39
  STA BOX_X
  LDA #0
  STA BOX_Y
  
  ; Clear enemy array
  LDX #15
clear_enemies:
  LDA #0
  STA ENEMY_POS,X
  DEX
  BPL clear_enemies
  
  ; Initialize game state
  LDA #0
  STA ENEMY_TIMER
  STA SPAWN_TIMER
  STA SKIP_COUNT
  STA KILL_COUNT
  STA GAME_OVER
  
  ; Spawn first enemy at right edge
  LDA #'a'
  STA ENEMY_POS+15

game_loop:
  ; Check if game over
  LDA GAME_OVER
  BNE game_over_loop
  
  ; Process input from key buffer
  JSR process_key_input
  
  ; Update enemies
  JSR update_enemies
  
  ; Check collision
  JSR check_collision
  
  ; Render the frame
  JSR render_frame
  
  ; Wait for next frame (30 FPS)
  JSR delay_frame
  
  JMP game_loop

game_over_loop:
  ; Display game over message
  JSR render_game_over
  JSR delay_frame
  JMP game_over_loop

; Update enemy positions (move left every second)
update_enemies:
  ; Increment timer
  INC ENEMY_TIMER
  LDA ENEMY_TIMER
  CMP #30         ; 30 frames = 1 second at 30 FPS
  BCC update_spawning
  
  ; Reset timer
  LDA #0
  STA ENEMY_TIMER
  
  ; Move all enemies left
  LDX #0
move_enemies_loop:
  CPX #15
  BEQ move_enemies_loop_end
  
  LDA ENEMY_POS+1,X
  STA ENEMY_POS,X
  INX
  JMP move_enemies_loop
  
move_enemies_loop_end:
  ; Clear rightmost position
  LDA #0
  STA ENEMY_POS+15

update_spawning:
  ; Increment spawn timer
  INC SPAWN_TIMER
  LDA SPAWN_TIMER
  CMP #60         ; Spawn every 2 seconds
  BCC spawn_done
  
  ; Reset spawn timer
  LDA #0
  STA SPAWN_TIMER
  
  ; Check if rightmost position is empty and previous position is not enemy
  LDA ENEMY_POS+15
  BNE spawn_done
  LDA ENEMY_POS+14
  BNE spawn_done
  
  ; Spawn new enemy
  LDA #'a'
  STA ENEMY_POS+15
  
spawn_done:
  RTS

; Check collision between box and enemies
check_collision:
  ; Calculate box column
  LDA BOX_X
  JSR get_char_col
  
  ; Check if enemy at box position
  LDX BOX_X_COL
  LDA ENEMY_POS,X
  BEQ no_collision
  
  ; Check if box is on first row
  LDA BOX_Y_COL
  BNE no_collision
  
  ; Collision! Game over
  LDA #1
  STA GAME_OVER
  
no_collision:
  RTS

; Process key input
process_key_input:
  LDA KEY_BUF_HEAD
  CMP KEY_BUF_TAIL
  BEQ no_key_available
  
  LDX KEY_BUF_TAIL
  LDA KEY_BUFFER,X
  STA SCAN_CODE_BUFFER
  
  INX
  TXA
  AND #(KEY_BUF_SIZE - 1)
  STA KEY_BUF_TAIL
  
  LDA SCAN_CODE_BUFFER
  JSR lookup_keymap_char
  STA LAST_KEY_CHAR
  
  LDA SCAN_CODE_BUFFER
  
  CMP #SCANCODE_K
  BEQ move_up
  CMP #SCANCODE_J
  BEQ move_down
  CMP #SCANCODE_H
  BEQ move_left
  CMP #SCANCODE_L
  BEQ move_right
  CMP #SCANCODE_W
  BEQ teleport_skip
  CMP #SCANCODE_X
  BEQ kill_enemy
  
no_key_available:
  RTS

lookup_keymap_char:
  TAY
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
  CMP #15
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
  CMP #74
  BCC store_x_right
  LDA #73
store_x_right:
  STA BOX_X
  RTS

; Teleport: skip over enemy to the right
teleport_skip:
  ; Get current box column
  LDA BOX_X
  JSR get_char_col
  
  ; Only teleport if on first row
  LDA BOX_Y_COL
  BNE skip_done
  
  ; Find next enemy to the right
  LDX BOX_X_COL
find_enemy_right:
  INX
  CPX #16
  BEQ skip_done
  
  LDA ENEMY_POS,X
  BEQ find_enemy_right
  
  ; Found enemy, teleport past it
  INX
  CPX #16
  BEQ skip_done
  
  ; Move box to that column
  TXA
  STA BOX_X_COL
  
  ; Convert column to pixels (multiply by 5)
  LDA #0
  STA BOX_X
  LDY BOX_X_COL
  BEQ teleport_done
multiply_by_5:
  LDA BOX_X
  CLC
  ADC #5
  STA BOX_X
  DEY
  BNE multiply_by_5
  
teleport_done:
  ; Increment skip count
  INC SKIP_COUNT
  
skip_done:
  RTS

; Kill: remove enemy to the right
kill_enemy:
  ; Get current box column
  LDA BOX_X
  JSR get_char_col
  
  ; Only kill if on first row
  LDA BOX_Y_COL
  BNE kill_done
  
  ; Find next enemy to the right
  LDX BOX_X_COL
find_enemy_kill:
  INX
  CPX #16
  BEQ kill_done
  
  LDA ENEMY_POS,X
  BEQ find_enemy_kill
  
  ; Found enemy, remove it
  LDA #0
  STA ENEMY_POS,X
  
  ; Increment kill count
  INC KILL_COUNT
  
kill_done:
  RTS

; Render frame
render_frame:
  ; Create custom character
  JSR create_custom_character
  
  ; Clear display
  LDA #%00000001
  JSR lcd_instruction
  jsr lcd_long_delay
  
  ; Draw enemies on first row
  LDX #0
draw_enemies:
  LDA ENEMY_POS,X
  BEQ skip_enemy_draw
  
  ; Set cursor to first row, column X
  TXA
  ORA #%10000000
  JSR lcd_instruction
  
  ; Draw enemy
  LDA ENEMY_POS,X
  JSR print_char
  
skip_enemy_draw:
  INX
  CPX #16
  BNE draw_enemies
  
  ; Draw box
  LDA BOX_Y
  LSR A
  LSR A
  LSR A
  STA BOX_Y_COL
  BEQ draw_box_row1
  
draw_box_row2:
  LDA BOX_X
  JSR get_char_col
  LDA BOX_X_COL
  ORA #%11000000
  JSR lcd_instruction
  JMP display_box
  
draw_box_row1:
  LDA BOX_X
  JSR get_char_col
  LDA BOX_X_COL
  ORA #%10000000
  JSR lcd_instruction
  
display_box:
  LDA #$00
  JSR print_char
  
  ; Draw score on second row
  LDA #%11000000
  JSR lcd_instruction
  
  ; Display skip count
  LDA SKIP_COUNT
  JSR convert_to_ascii
  JSR print_char
  
  ; Display space
  LDA #' '
  JSR print_char
  
  ; Display kill count
  LDA KILL_COUNT
  JSR convert_to_ascii
  JSR print_char
  
  RTS

render_game_over:
  ; Clear display
  LDA #%00000001
  JSR lcd_instruction
  jsr lcd_long_delay
  
  ; Display "GAME OVER"
  LDA #%10000011
  JSR lcd_instruction
  
  LDA #'D'
  JSR print_char
  LDA #'E'
  JSR print_char
  LDA #'A'
  JSR print_char
  LDA #'D'
  JSR print_char
  LDA #'!'
  JSR print_char
  
  ; Display final score on second row
  LDA #%11000000
  JSR lcd_instruction
  
  LDA #'S'
  JSR print_char
  LDA #':'
  JSR print_char
  LDA SKIP_COUNT
  JSR convert_to_ascii
  JSR print_char
  
  LDA #' '
  JSR print_char
  
  LDA #'K'
  JSR print_char
  LDA #':'
  JSR print_char
  LDA KILL_COUNT
  JSR convert_to_ascii
  JSR print_char
  
  RTS

get_char_col:
  PHA
  LDA BOX_X
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
  RTS

create_custom_character:
  LDA #%01000000
  JSR lcd_instruction
  
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
  STA $0251
  
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
  STA $0252
  
  LDX #0
gen_char_loop:
  TXA
  CMP $0252
  BCC gen_empty_row
  SEC
  SBC $0252
  CMP #2
  BCS gen_empty_row
  
  LDA $0251
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

create_box_row:
  CMP #0
  BEQ box_at_0
  CMP #1
  BEQ box_at_1
  CMP #2
  BEQ box_at_2
  CMP #3
  BEQ box_at_3
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
  BNE CHECK_F0_DETECTED
  
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

CHECK_F0_DETECTED:
  LDX F0_DETECTED
  BNE HANDLE_SKIP_STATE
  
  CMP #$F0
  BNE STORE_SCANCODE
  
  LDA #1
  STA F0_DETECTED
  JMP CLEAR_IRQ

HANDLE_SKIP_STATE:
  LDA #0
  STA F0_DETECTED
  JMP CLEAR_IRQ

STORE_SCANCODE:
  PHA
  LDX KEY_BUF_HEAD
  PLA
  STA KEY_BUFFER,X
  
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

delay_frame:
  pha
  txa
  pha
  tya
  pha
  
  ldx #$17
delay_outer:
  ldy #$00
delay_middle:
  lda #$05
delay_inner:
  sbc #$01
  bne delay_inner
  dey
  bne delay_middle
  dex
  bne delay_outer
  
  ldy #$35
delay_fine:
  dey
  bne delay_fine
  
  pla
  tay
  pla
  tax
  pla
  rts

convert_to_ascii:
  CMP #10
  BCC single_digit
  SEC
  SBC #10
  CLC
  ADC #'A'
  RTS
single_digit:
  CLC
  ADC #'0'
  RTS

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
  .byte "????????????? `?"
  .byte "?????q1???zsaw2?"
  .byte "?cxde43?? vftr5?"
  .byte "?nbhgy6???mju78?"
  .byte "?,kio09??./l;p-?"
  .byte "??'?[=????",$0a,"]?\??"
  .byte "?????????1?47???"
  .byte "0.2568",$1b,"??+3-*9??"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
keymap_shifted:
  .byte "????????????? ~?"
  .byte "?????Q!???ZSAW@?"
  .byte "?CXDE#$?? VFTR%?"
  .byte "?NBHGY^???MJU&*?"
  .byte "?<KIO)(??>?L:P_?"
  .byte '??"?{+?????}?|??'
  .byte "?????????1?47???"
  .byte "0.2568???+3-*9??"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"

  .org $FFFA
  .word $0000
  .word reset
  .word IRQ_HANDLER

