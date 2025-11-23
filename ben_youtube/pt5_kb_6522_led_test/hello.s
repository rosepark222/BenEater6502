PORTB = $6000
PORTA = $6001
DDRB = $6002
DDRA = $6003

KPORTB = $4000
KPORTA = $4001
KDDRB = $4002
KDDRA = $4003

E  = %10000000
RW = %01000000
RS = %00100000

  .org $8000

reset:
;;;; pt4 test code begin
 
  lda #%11111111 ; Set all pins on port B to output
  sta DDRB

  lda #%11100000 ; Set top 3 pins on port A to output
  sta DDRA

  lda #%00111000 ; Set 8-bit mode; 2-line display; 5x8 font
  sta PORTB
  lda #0         ; Clear RS/RW/E bits
  sta PORTA
  lda #E         ; Set E bit to send instruction
  sta PORTA
  lda #0         ; Clear RS/RW/E bits
  sta PORTA

  lda #%00001110 ; Display on; cursor on; blink off
  sta PORTB
  lda #0         ; Clear RS/RW/E bits
  sta PORTA
  lda #E         ; Set E bit to send instruction
  sta PORTA
  lda #0         ; Clear RS/RW/E bits
  sta PORTA

  lda #%00000110 ; Increment and shift cursor; don't shift display
  sta PORTB
  lda #0         ; Clear RS/RW/E bits
  sta PORTA
  lda #E         ; Set E bit to send instruction
  sta PORTA
  lda #0         ; Clear RS/RW/E bits
  sta PORTA

  lda #"P"
  sta PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta PORTA
  lda #RS         ; Clear E bits
  sta PORTA

  lda #"A"
  sta PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta PORTA
  lda #RS         ; Clear E bits
  sta PORTA

        LDA #$42        ; Load immediate value $42 into accumulator
        STA $10         ; Store accumulator to zero page address $10
        
        LDA $10         ; Load value from zero page address $10
        CMP #$42        ; Compare accumulator with $42
        BEQ PASS        ; Branch if equal - jump to PASS
        JMP FAIL        ; If not equal, jump to FAIL

        
PASS:
  lda #"N"
  sta PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta PORTA
  lda #RS         ; Clear E bits
  sta PORTA

  lda #"C"
  sta PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta PORTA
  lda #RS         ; Clear E bits
  sta PORTA

  lda #"A"
  sta PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta PORTA
  lda #RS         ; Clear E bits
  sta PORTA

  lda #"C"
  sta PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta PORTA
  lda #RS         ; Clear E bits
  sta PORTA

  lda #"K"
  sta PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta PORTA
  lda #RS         ; Clear E bits
  sta PORTA

FAIL:
  lda #"E"
  sta PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta PORTA
  lda #RS         ; Clear E bits
  sta PORTA

  ;;;;; pt4 test code end 

; Start LED blinking loop
  lda #%11111111 ; Set all pins on port A to output
  sta DDRA

led_loop:


  lda #"1"        ; before 5s
  sta PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta PORTA
  lda #RS         ; Clear E bits
  sta PORTA

  ; Turn ON LED (set PA0 high, keep LCD control bits as they are)
  lda PORTA
  ora #%00000001  ; Set bit 0 high
  sta PORTA
  
  ; Delay for 5 seconds
  jsr delay_5s

  lda #"2"        ; after 5s
  sta PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta PORTA
  lda #RS         ; Clear E bits
  sta PORTA

  ; Turn OFF LED (clear PA0, keep LCD control bits as they are)
  lda PORTA
  and #%11111110  ; Clear bit 0
  sta PORTA
  
  ; Delay for 5 seconds
  jsr delay_5s

  lda #"3"        ; after 5s
  sta PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta PORTA
  lda #RS         ; Clear E bits
  sta PORTA
 

keyboard_led:
  lda #%11111111 ; Set all pins on port A to output
  sta KDDRA


  lda #%00000001  ; Set bit 0 high
  sta KPORTA

  lda #"4"        ; after 5s
  sta PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta PORTA
  lda #RS         ; Clear E bits
  sta PORTA

  jsr delay_5s

  lda #%00000000  ; Set bit 0 low
  sta KPORTA

  lda #"5"        ; after 5s
  sta PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta PORTA
  lda #RS         ; Clear E bits
  sta PORTA

  jsr delay_5s

; 5 second delay routine (assumes 1MHz clock)
delay_5s:
  ldx #$05        ; Outer loop: 5 iterations (5 seconds)
delay_1s:
  ldy #$20        ; Middle loop counter
delay_loop:
  nop
  nop
  nop
  nop
  nop
  dey
  bne delay_loop
  dex
  bne delay_1s
  rts

  .org $fffc
  .word reset
  .word $0000
