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

  .org $8000

reset:
;;;; pt4 test code begin
 
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

 
  ; memory access test

  LDA #$42        ; Load immediate value $42 into accumulator
  STA $10         ; Store accumulator to zero page address $10
        
  LDA $10         ; Load value from zero page address $10
  CMP #$42        ; Compare accumulator with $42
  BEQ PASS        ; Branch if equal - jump to PASS
;   JMP FAIL        ; If not equal, jump to FAIL

FAIL:
  lda #"F"
  sta LCD_PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta LCD_PORTA
  lda #RS         ; Clear E bits
  sta LCD_PORTA
  jsr lcd_delay   ; fast_clock

  lda #"A"
  sta LCD_PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta LCD_PORTA
  lda #RS         ; Clear E bits
  sta LCD_PORTA
  jsr lcd_delay   ; fast_clock

  lda #"I"
  sta LCD_PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta LCD_PORTA
  lda #RS         ; Clear E bits
  sta LCD_PORTA
  jsr lcd_delay   ; fast_clock

  lda #"L"
  sta LCD_PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta LCD_PORTA
  lda #RS         ; Clear E bits
  sta LCD_PORTA
  jsr lcd_delay   ; fast_clock

PASS:
  lda #"1"
  sta LCD_PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta LCD_PORTA
  lda #RS         ; Clear E bits
  sta LCD_PORTA
  jsr lcd_delay   ; fast_clock

  lda #"M"
  sta LCD_PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta LCD_PORTA
  lda #RS         ; Clear E bits
  sta LCD_PORTA
  jsr lcd_delay   ; fast_clock

  lda #"h"
  sta LCD_PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta LCD_PORTA
  lda #RS         ; Clear E bits
  sta LCD_PORTA
  jsr lcd_delay   ; fast_clock

  lda #"z"
  sta LCD_PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta LCD_PORTA
  lda #RS         ; Clear E bits
  sta LCD_PORTA
  jsr lcd_delay   ; fast_clock

  ;;;;; pt4 test code end 

; Start LED blinking loop
  lda #%11111111 ; Set all pins on port A to output
  sta LCD_DDRA

led_loop:


  lda #"1"        ; before 5s
  sta LCD_PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta LCD_PORTA
  lda #RS         ; Clear E bits
  sta LCD_PORTA
  jsr lcd_delay   ; fast_clock

  ; Turn ON LED (set PA0 high, keep LCD control bits as they are)
  lda LCD_PORTA
  ora #%00000001  ; Set bit 0 high
  sta LCD_PORTA
  
  ; Delay for 5 seconds
  jsr delay_5s

  lda #"2"        ; after 5s
  sta LCD_PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta LCD_PORTA
  lda #RS         ; Clear E bits
  sta LCD_PORTA
  jsr lcd_delay   ; fast_clock

  ; Turn OFF LED (clear PA0, keep LCD control bits as they are)
  lda LCD_PORTA
  and #%11111110  ; Clear bit 0
  sta LCD_PORTA
  
  ; Delay for 5 seconds
  jsr delay_5s

 
 

keyboard_init:
  lda #%00000001 ; bit 0 output, bit 1-2 inputs
  sta KB_DDRA
    
  
  LDA #%00000000 ; Port B: all inputs for scan code
  STA KB_DDRB

  lda #%00000001  ; Set bit 0 high
  sta KB_PORTA

  lda #"4"        ; after 5s
  sta LCD_PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta LCD_PORTA
  lda #RS         ; Clear E bits
  sta LCD_PORTA
  jsr lcd_delay   ; fast_clock

  jsr delay_5s

  lda #%00000000  ; Set bit 0 low
  sta KB_PORTA


irq_setup:


    ; Configure CA1 for positive edge interrupt
    LDA KB_PCR
    AND #%11111110      ; Clear CA1 control bit 0
    ORA #%00000001      ; Set for positive edge (bit 0 = 1)
    STA KB_PCR
    
    ; Enable CA1 interrupt
    LDA #%10000010      ; Set bit 7 (master enable) and bit 1 (CA1)
    STA KB_IER
    
    ; Clear any pending interrupts
    LDA KB_PORTA        ; Reading Port A clears CA1 flag
    
    ; Enable interrupts
    CLI

lcd_loop:

  lda #"5"        ; after 5s
  sta LCD_PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta LCD_PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta LCD_PORTA
  lda #RS         ; Clear E bits
  sta LCD_PORTA
  jsr lcd_delay   ; fast_clock

wait_loop:
  jmp wait_loop   ; Infinite loop waiting for interrupts


IRQ_HANDLER:
    ; Save registers
  PHA
  TXA
  PHA
  TYA
  PHA

  ; Read the scancode from keyboard Port B
  LDA KB_PORTB
  
  ; Save the scancode for later comparison
  PHA
  
  ; Convert high nibble to ASCII and print
  PHA
  LSR A
  LSR A
  LSR A
  LSR A
  CMP #$0A
  BCC HIGH_DIGIT
  ADC #$06        ; Add 7 (6 + carry) to get A-F
HIGH_DIGIT:
  ADC #$30        ; Convert to ASCII
  STA LCD_PORTB
  LDA #RS         ; Set RS; Clear RW/E bits
  STA LCD_PORTA
  LDA #(RS | E)   ; Set E bit to send instruction
  STA LCD_PORTA
  LDA #RS         ; Clear E bits
  STA LCD_PORTA
  jsr lcd_delay   ; fast_clock
  
  ; Convert low nibble to ASCII and print
  PLA
  AND #$0F
  CMP #$0A
  BCC LOW_DIGIT
  ADC #$06        ; Add 7 (6 + carry) to get A-F
LOW_DIGIT:
  ADC #$30        ; Convert to ASCII
  STA LCD_PORTB
  LDA #RS         ; Set RS; Clear RW/E bits
  STA LCD_PORTA
  LDA #(RS | E)   ; Set E bit to send instruction
  STA LCD_PORTA
  LDA #RS         ; Clear E bits
  STA LCD_PORTA
  jsr lcd_delay   ; fast_clock
  
 

IRQ_BLINK_LOOP:
  ; Turn LED ON
  lda #%00000001  ; Set bit 0 high
  sta KB_PORTA
  JSR delay_5s
  ; Turn LED OFF
  LDA #$00
  STA KB_PORTA
  JSR delay_5s

CLEAR_IRQ:
    ; Clear CA1 interrupt flag by reading Port A
    LDA KB_PORTA        ; Reading Port A clears CA1 flag
    
  PLA
  TAY
  PLA
  TAX
  PLA
    
  RTI

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

