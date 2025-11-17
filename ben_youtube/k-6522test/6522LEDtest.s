
; 6522 VIA Test Code
; VIA #1 at $6000 - LCD on Port B, control on Port A
; VIA #2 at $4000 - Blinking LEDs on Port A and Port B

; VIA #1 Register Offsets (base address $6000) - LCD
VIA1_PORTB   = $6000    ; Port B data register (LCD data)
VIA1_PORTA   = $6001    ; Port A data register (LCD control)
VIA1_DDRB    = $6002    ; Port B data direction register
VIA1_DDRA    = $6003    ; Port A data direction register

; VIA #2 Register Offsets (base address $4000) - LEDs
VIA2_PORTB   = $4000    ; Port B data register
VIA2_PORTA   = $4001    ; Port A data register
VIA2_DDRB    = $4002    ; Port B data direction register
VIA2_DDRA    = $4003    ; Port A data direction register

; LCD control bits on VIA #1 Port A
E  = %10000000
RW = %01000000
RS = %00100000

        .ORG $8000

START:
        LDX #$FF
        TXS
        
        ; Initialize VIA #1 for LCD
        LDA #%11111111  ; Set all pins on port B to output (LCD data)
        STA VIA1_DDRB
        LDA #%11100000  ; Set top 3 pins on port A to output (LCD control)
        STA VIA1_DDRA
        
        ; Initialize VIA #2 for LEDs - Set both ports as outputs
        LDA #$FF
        STA VIA2_DDRA
        STA VIA2_DDRB
        
        ; Initialize LCD
        LDA #%00111000  ; Set 8-bit mode; 2-line display; 5x8 font
        JSR lcd_instruction
        LDA #%00001110  ; Display on; cursor on; blink off
        JSR lcd_instruction
        LDA #%00000110  ; Increment and shift cursor; don't shift display
        JSR lcd_instruction
        LDA #%00000001  ; Clear display
        JSR lcd_instruction
        
        ; Print "HELLO" to LCD
        LDX #0
print:
        LDA message,X
        BEQ MAIN_LOOP   ; When done, start LED blinking
        JSR print_char
        INX
        JMP print

MAIN_LOOP:
        ; Turn ON all LEDs on VIA #2 (set outputs high)
        LDA #$FF
        STA VIA2_PORTA
        STA VIA2_PORTB
        
        ; Delay for 5 seconds
        JSR DELAY_5S
        
        ; Turn OFF all LEDs on VIA #2 (set outputs low)
        LDA #$00
        STA VIA2_PORTA
        STA VIA2_PORTB
        
        ; Delay for 5 seconds
        JSR DELAY_5S
        
        ; Repeat forever
        JMP MAIN_LOOP

message: .asciiz "HELLO"

lcd_wait:
        PHA
        LDA #%00000000  ; Port B is input
        STA VIA1_DDRB
lcdbusy:
        LDA #RW
        STA VIA1_PORTA
        LDA #(RW | E)
        STA VIA1_PORTA
        LDA VIA1_PORTB
        AND #%10000000
        BNE lcdbusy

        LDA #RW
        STA VIA1_PORTA
        LDA #%11111111  ; Port B is output
        STA VIA1_DDRB
        PLA
        RTS

lcd_instruction:
        JSR lcd_wait
        STA VIA1_PORTB
        LDA #0         ; Clear RS/RW/E bits
        STA VIA1_PORTA
        LDA #E         ; Set E bit to send instruction
        STA VIA1_PORTA
        LDA #0         ; Clear RS/RW/E bits
        STA VIA1_PORTA
        RTS

print_char:
        JSR lcd_wait
        STA VIA1_PORTB
        LDA #RS         ; Set RS; Clear RW/E bits
        STA VIA1_PORTA
        LDA #(RS | E)   ; Set E bit to send instruction
        STA VIA1_PORTA
        LDA #RS         ; Clear E bits
        STA VIA1_PORTA
        RTS

; 5 second delay routine (assumes 1MHz clock)
DELAY_5S:
        LDX #$05        ; Outer loop: 5 iterations (5 seconds)
DELAY_1S:
        LDY #$00        ; Middle loop counter
DELAY_LOOP:
        NOP
        NOP
        NOP
        NOP
        NOP
        DEY
        BNE DELAY_LOOP
        DEX
        BNE DELAY_1S
        RTS

        .ORG $FFFC
        .WORD START
        .WORD $0000

        .END
