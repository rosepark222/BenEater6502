LCD_PORTB = $6000
LCD_PORTA = $6001
LCD_DDRB = $6002
LCD_DDRA = $6003

KB_PORTB = $4000
KB_PORTA = $4001
KB_DDRB = $4002
KB_DDRA = $4003
KB_PCR   = $400C    ; Peripheral Control Register
KB_IFR   = $400D    ; Interrupt Flag Register
KB_IER   = $400E    ; Interrupt Enable Register

E  = %10000000
RW = %01000000
RS = %00100000

; keyboard init - PS/2 Protocol Constants
PS2_CLK_BIT  = %00000100    ; PA1 - Clock line
PS2_DATA_BIT = %00000010    ; PA2 - Data line
PS2_INIT_AA  = $AA          ; Expected initial byte from keyboard
PS2_REPLY_FF = $FF          ; Reply byte for handshake

; keyboard init - Variables
HANDSHAKE_DONE = $0222      ; Flag: 0=not done, $FF=done
PS2_BYTE_TEMP  = $0223      ; Temporary storage for PS/2 transmission

  .org $8000

reset:
;;;; pt4 test code begin
; Disable interrupts
SEI
keyboard_init:


  ; keyboard init - Configure Port A: PA1 and PA2 as outputs for PS/2 protocol
  lda #%00000001      ; PA1(clock) and PA2(data) as outputs, PA0 as output -- erp029
  sta KB_DDRA
    
  ; keyboard init - Configure Port B: all inputs for scan code
  LDA #%00000000
  STA KB_DDRB
  ; keyboard init - Initialize handshake flag
  LDA #$00
  STA HANDSHAKE_DONE

  ; ; keyboard init - Set PS/2 lines to idle state (both high)
  ; lda #(PS2_CLK_BIT | PS2_DATA_BIT)  ; Both clock and data high
  ; sta KB_PORTA

;   lda #"4"        ; after 5s
;   sta LCD_PORTB
;   lda #RS         ; Set RS; Clear RW/E bits
;   sta LCD_PORTA
;   lda #(RS | E)   ; Set E bit to send instruction
;   sta LCD_PORTA
;   lda #RS         ; Clear E bits
;   sta LCD_PORTA
;   jsr lcd_delay   ; fast_clock
; 
;   jsr delay_5s
; 
;   lda #%00000000  ; Set bit 0 low
;   sta KB_PORTA

lcd_init:
  lda #%11111111 ; Set all pins on port B to output
  sta LCD_DDRB

  lda #%11100000 ; Set top 3 pins on port A to output
  sta LCD_DDRA

  ; Wait for LCD power-up (15ms)
  jsr lcd_long_delay ; fast_clock
  jsr lcd_long_delay ; fast_clock
  jsr lcd_long_delay ; fast_clock

  lda #%00111000 ; Set 8-bit mode; 2-line display; 5x8 font
  sta LCD_PORTB
  lda #0         ; Clear RS/RW/E bits
  sta LCD_PORTA
  lda #E         ; Set E bit to send instruction
  sta LCD_PORTA
  lda #0         ; Clear RS/RW/E bits
  sta LCD_PORTA
  jsr lcd_delay  ; fast_clock

  lda #%00001110 ; Display on; cursor on; blink off
  sta LCD_PORTB
  lda #0         ; Clear RS/RW/E bits
  sta LCD_PORTA
  lda #E         ; Set E bit to send instruction
  sta LCD_PORTA
  lda #0         ; Clear RS/RW/E bits
  sta LCD_PORTA
  jsr lcd_delay  ; fast_clock

  lda #%00000110 ; Increment and shift cursor; don't shift display
  sta LCD_PORTB
  lda #0         ; Clear RS/RW/E bits
  sta LCD_PORTA
  lda #E         ; Set E bit to send instruction
  sta LCD_PORTA
  lda #0         ; Clear RS/RW/E bits
  sta LCD_PORTA
  jsr lcd_delay  ; fast_clock

 

;Start LED blinking loop
  lda #%11111111 ; Set all pins on port A to output
  sta LCD_DDRA

lcd_loop:


  lda #"1"        ; before 5s
  sta LCD_PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta LCD_PORTA
  lda #RS         ; Clear E bits
  sta LCD_PORTA
  jsr lcd_delay   ; fast_clock

  ; lda LCD_PORTA
  ; ora #%00000001  ; Set bit 0 high
  ; sta LCD_PORTA
  
  ; Delay for 5 seconds
  ;jsr delay_5s

  lda #"2"        ; after 5s
  sta LCD_PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta LCD_PORTA
  lda #RS         ; Clear E bits
  sta LCD_PORTA
  jsr lcd_delay   ; fast_clock

  ; ; Turn OFF LED (clear PA0, keep LCD control bits as they are)
  ; lda LCD_PORTA
  ; and #%11111110  ; Clear bit 0
  ; sta LCD_PORTA
  
  ; Delay for 5 seconds
  ;jsr delay_5s

 

irq_setup:
    ; keyboard init - Configure CA1 for positive edge interrupt (filtered clock)
    LDA KB_PCR
    AND #%11111110      ; Clear CA1 control bit 0
    ORA #%00000001      ; Set for positive edge (bit 0 = 1)
    STA KB_PCR
    
    ; keyboard init - Enable CA1 interrupt
    LDA #%10000010      ; Set bit 7 (master enable) and bit 1 (CA1)
    STA KB_IER
    
    ; keyboard init - Clear any pending interrupts
    LDA KB_PORTA        ; Reading Port A clears CA1 flag
    
    ; keyboard init - Enable interrupts
    CLI

; lcd_loop:
; 
;   lda #"5"        ; after 5s
;   sta LCD_PORTB
;   lda #RS         ; Set RS; Clear RW/E bits
;   sta LCD_PORTA
;   lda #(RS | E)   ; Set E bit to send instruction
;   sta LCD_PORTA
;   lda #RS         ; Clear E bits
;   sta LCD_PORTA
;   jsr lcd_delay   ; fast_clock

wait_loop:
  ; ; Turn LED ON
  ; lda #%00000001  ; Set bit 0 high
  ; sta KB_PORTA
  ; JSR delay_5s
  ; ; Turn LED OFF
  ; LDA #$00
  ; STA KB_PORTA
  ; JSR delay_5s
  jmp wait_loop   ; Infinite loop waiting for interrupts


IRQ_HANDLER:
    ; Save registers
  PHA
  TXA
  PHA
  TYA
  PHA

  ; keyboard init - Read the scancode from keyboard Port B
  LDA KB_PORTB
 

  ; keyboard init - Check if handshake is complete
  LDX HANDSHAKE_DONE
  BNE DISPLAY_SCANCODE    ; Handshake done, display to LCD


  ; keyboard init - *** Initial Handshake Logic ***
  CMP #PS2_INIT_AA        ; Is it $AA?
  BNE CLEAR_IRQ           ; Not $AA, ignore and wait

  ; ; if it is AA
  ; ; Turn LED ON
  ; lda #%00000001  ; Set bit 0 high
  ; sta KB_PORTA
  ; JSR delay_5s

  ; ; Turn LED OFF
  ; LDA #$00
  ; STA KB_PORTA
  ; JSR delay_5s
  ; keyboard init - Display handshake complete message
  ; lda #"a"        ; after 5s
  ; sta LCD_PORTB
  ; lda #RS         ; Set RS; Clear RW/E bits
  ; sta LCD_PORTA
  ; lda #(RS | E)   ; Set E bit to send instruction
  ; sta LCD_PORTA
  ; lda #RS         ; Clear E bits
  ; sta LCD_PORTA
  ; jsr lcd_delay   ; fast_clock

  
  lda #%00000111      ; PA1(clock) and PA2(data) as outputs, PA0 as output -- erp029
  sta KB_DDRA

  ; keyboard init - Received $AA, send $FF reply via Port A
  JSR send_ff_reply

  ; keyboard init - Mark handshake complete
  LDA #$FF
  STA HANDSHAKE_DONE

  ; keyboard init - Disable Port A PA1 and PA2 (set to input, tristated)
  LDA #%00000001          ; All Port A pins as inputs
  STA KB_DDRA

  ; keyboard init - Display handshake complete message
  lda #"c"        ; after 5s
  sta LCD_PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta LCD_PORTA
  lda #RS         ; Clear E bits
  sta LCD_PORTA
  jsr lcd_delay   ; fast_clock

  ;jsr delay_5s

  ; LDA #"O"
  ; JSR print_char_lcd
  ; LDA #"K"
  ; JSR print_char_lcd
  ; LDA #" "
  ; JSR print_char_lcd

  JMP CLEAR_IRQ

DISPLAY_SCANCODE:
  ; keyboard init - Save the scancode for display
  PHA
  
  ; keyboard init - Convert high nibble to ASCII and print
  PHA
  LSR A
  LSR A
  LSR A
  LSR A
  CMP #$0A
  BCC HIGH_DIGIT2
  ADC #$06        ; Add 7 (6 + carry) to get A-F
HIGH_DIGIT2:
  ADC #$30        ; Convert to ASCII
  JSR print_char_lcd
  
  ; keyboard init - Convert low nibble to ASCII and print
  PLA
  AND #$0F
  CMP #$0A
  BCC LOW_DIGIT2
  ADC #$06        ; Add 7 (6 + carry) to get A-F
LOW_DIGIT2:
  ADC #$30        ; Convert to ASCII
  JSR print_char_lcd

  ; keyboard init - Print space separator
  LDA #" "
  JSR print_char_lcd
  
  PLA             ; Remove saved scancode from stack



CLEAR_IRQ:
    ; keyboard init - Clear CA1 interrupt flag by reading Port A
    LDA KB_PORTA        ; Reading Port A clears CA1 flag
  
  ; ; Turn LED ON
  ; lda #%00000001  ; Set bit 0 high
  ; sta KB_PORTA
  ; JSR delay_5s

  ; ; Turn LED OFF
  ; LDA #$00
  ; STA KB_PORTA
  ; JSR delay_5s

  PLA
  TAY
  PLA
  TAX
  PLA
    
  RTI

; keyboard init - Print character in A to LCD
print_char_lcd:
  STA LCD_PORTB
  LDA #RS         ; Set RS; Clear RW/E bits
  STA LCD_PORTA
  LDA #(RS | E)   ; Set E bit to send instruction
  STA LCD_PORTA
  LDA #RS         ; Clear E bits
  STA LCD_PORTA
  JSR lcd_delay
  RTS

; keyboard init - SEND $FF REPLY - PS/2 Protocol Transmission
; Sends $FF byte using bit-banged PS/2 protocol on Port A (PA1=clock, PA2=data)
send_ff_reply:

  ; lda #"b"        ; after 5s
  ; sta LCD_PORTB
  ; lda #RS         ; Set RS; Clear RW/E bits
  ; sta LCD_PORTA
  ; lda #(RS | E)   ; Set E bit to send instruction
  ; sta LCD_PORTA
  ; lda #RS         ; Clear E bits
  ; sta LCD_PORTA
  ; jsr lcd_delay   ; fast_clock


    LDA #PS2_REPLY_FF
    STA PS2_BYTE_TEMP    ; Store byte to send
    
    LDX #$00             ; Bit counter
    LDY #$00             ; Parity accumulator
    
    ; FF reply fix - RULE 1: Pull Clock line low for at least 100µs to inhibit device
    LDA #$00             ; FF reply fix - Both Clock and Data low
    STA KB_PORTA         ; FF reply fix
    JSR ps2_long_delay   ; FF reply fix - Wait 100µs
    
     ; FF reply fix - RULE 2: Request-to-Send - Pull Data line low while Clock is still low
    LDA #$00             ; FF reply fix - Both Clock and Data low
    STA KB_PORTA         ; FF reply fix
    ; FF reply fix - RULE 3: Release Clock line (keep Data low, let Clock go high via pull-up)

    LDA KB_DDRA          ; FF reply fix - Read current DDR
    AND #%11111011       ; FF reply fix -   release clock, it is  pulled HIGH and host should wait for it goes low
    STA KB_DDRA          ; FF reply fix
    JSR ps2_delay        ; FF reply fix - Wait for Clock to stabilize high

 
    
send_bit_loop:
    ; FF reply fix - Wait for device to pull Clock LOW
    JSR wait_clock_low   ; FF reply fix
    
    ; Prepare data bit
    LDA PS2_BYTE_TEMP    ; Get byte to send
    AND #$01             ; Isolate LSB
    BEQ send_zero
    
send_one:
    LDA #PS2_DATA_BIT    ; FF reply fix - Data high (Clock released)
    STA KB_PORTA         ; FF reply fix
    INY                  ; Update parity
    JMP next_bit
    
send_zero:
    LDA #$00             ; FF reply fix - Data low (Clock released)
    STA KB_PORTA         ; FF reply fix
    
next_bit:
    ; JSR ps2_delay ; FF reply fix - REMOVED
    JSR wait_clock_high_sub  ; FF reply fix - Wait for device to pull Clock HIGH
    
    ; Shift to next bit
    LSR PS2_BYTE_TEMP
    INX
    CPX #$08             ; Sent all 8 bits?
    BNE send_bit_loop
    
    ; FF reply fix - Wait for device to pull Clock LOW
    JSR wait_clock_low   ; FF reply fix
    
    ; Send parity bit (odd parity)
    TYA
    AND #$01             ; Check if parity is odd
    BNE send_parity_zero
    
send_parity_one:

    LDA #PS2_DATA_BIT    ; FF reply fix - Data high (Clock released)
    STA KB_PORTA         ; FF reply fix
    JMP send_stop
    
send_parity_zero:

    LDA #$00             ; FF reply fix - Data low (Clock released)
    STA KB_PORTA         ; FF reply fix
    
send_stop:
    ; JSR ps2_delay ; FF reply fix - REMOVED
    JSR wait_clock_high_sub  ; FF reply fix - Wait for device to pull Clock HIGH
    
    ; FF reply fix - Wait for device to pull Clock LOW
    JSR wait_clock_low   ; FF reply fix
    
    ; Stop bit: data high
    LDA #PS2_DATA_BIT    ; FF reply fix - Release Data (high)
    STA KB_PORTA         ; FF reply fix
    ; JSR ps2_delay ; FF reply fix - REMOVED
    JSR wait_clock_high_sub  ; FF reply fix - Wait for device to pull Clock HIGH
    
    ; FF reply fix - Wait for ACK bit (device pulls Data low)
    JSR wait_clock_low   ; FF reply fix - Device should have Data low now
    JSR wait_clock_high_sub  ; FF reply fix
    
    ; Release lines (both high)
 
    LDA KB_DDRA          ;  
    AND #%11111001       ;  release clock and data
    STA KB_DDRA          ;
    JSR ps2_delay        ;

    RTS

; FF reply fix - Wait for Clock line to go LOW (device controls it)
wait_clock_low:          ; FF reply fix
  PHA                    ; FF reply fix
wait_clock_low_loop:     ; FF reply fix
  LDA KB_PORTA           ; FF reply fix
  AND #PS2_CLK_BIT       ; FF reply fix - Check PA1 (clock)
  BNE wait_clock_low_loop  ; FF reply fix - Loop while high
  PLA                    ; FF reply fix
  RTS                    ; FF reply fix

; FF reply fix - Wait for Clock line to go HIGH (device controls it)
wait_clock_high_sub:     ; FF reply fix
  PHA                    ; FF reply fix
wait_clock_high_loop:    ; FF reply fix
  LDA KB_PORTA           ; FF reply fix
  AND #PS2_CLK_BIT       ; FF reply fix - Check PA1 (clock)
  BEQ wait_clock_high_loop  ; FF reply fix - Loop while low
  PLA                    ; FF reply fix
  RTS                    ; FF reply fix

; keyboard init - PS/2 TIMING DELAY
; For 1MHz clock: ~40-50µs per half-clock period
; Each loop iteration: 5 cycles, so need ~40-50 iterations
ps2_delay:
    PHA
    LDA #$0A             ; Delay count for 1MHz (~50µs)
ps2_delay_loop:
    SBC #$01
    BNE ps2_delay_loop
    PLA
    RTS

; FF reply fix - PS/2 long delay for 100µs initial clock hold
ps2_long_delay:          ; FF reply fix
    PHA                  ; FF reply fix
    LDA #$32             ; FF reply fix - ~50 iterations * 2µs = 100µs at 1MHz
ps2_long_delay_loop:     ; FF reply fix
    SBC #$01             ; FF reply fix
    BNE ps2_long_delay_loop  ; FF reply fix
    PLA                  ; FF reply fix
    RTS                  ; FF reply fix

; fast_clock - LCD delay routine (~2ms for 1MHz clock)
lcd_delay:              ; fast_clock
  pha                   ; fast_clock
  lda #$82              ; fast_clock - Loop counter for ~2ms delay
lcd_delay_loop:         ; fast_clock
  sbc #$01              ; fast_clock
  bne lcd_delay_loop    ; fast_clock
  pla                   ; fast_clock
  rts                   ; fast_clock

; fast_clock - LCD long delay routine (~5ms for initialization)
lcd_long_delay:         ; fast_clock
  pha                   ; fast_clock
  lda #$FF              ; fast_clock - Longer delay for power-up
lcd_long_delay_loop:    ; fast_clock
  sbc #$01              ; fast_clock
  bne lcd_long_delay_loop ; fast_clock
  pla                   ; fast_clock
  rts                   ; fast_clock

  
; Simple 2 second delay routine for 1MHz clock
; Approximately 2,000,000 cycles needed
delay_5s:
  ldx #$04        ; Repeat 4 times (4 × 0.5s = 2s)
delay_repeat:
  ldy #$DD        ; ~221 iterations
delay_outer:
  lda #$00        ; Inner loop: 256 iterations
delay_inner:
  nop
  nop
  sbc #$01
  bne delay_inner
  dey
  bne delay_outer
  dex
  bne delay_repeat
  rts

;  .org $fffc
;  .word reset
;  .word $0000
  .org $FFFA
  .word $0000         ; NMI vector (not used)
  .word reset         ; Reset vector
  .word IRQ_HANDLER   ; IRQ