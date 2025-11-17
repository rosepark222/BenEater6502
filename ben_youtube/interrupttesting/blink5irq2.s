; 6502 LED Control with Direct IRQ Button
; Button with pull-up connected directly to 6502 IRQ pin
; Blinks LED 5 times at startup, then 2 times on each IRQ
; Keyboard VIA at $4000

; VIA Register offsets
PORTB = $00
PORTA = $01
DDRB  = $02
DDRA  = $03

; Keyboard VIA ($4000)
KB_PORTA = $4001
KB_DDRA  = $4003

; PA2 bit mask
PA2 = %00000100

    .org $8000

START:
    ; Disable interrupts during initialization
    SEI
    
    ; Set PA2 as output (bit 2 = 1)
    LDA #%00000100
    STA KB_DDRA
    
    ; Blink LED 5 times before enabling IRQ
    LDX #5              ; 5 blinks
STARTUP_BLINK_LOOP:
    ; Turn LED ON
    LDA #PA2
    STA KB_PORTA
    
    ; Wait 1 second
    JSR DELAY_1S
    
    ; Turn LED OFF
    LDA #$00
    STA KB_PORTA
    
    ; Wait 1 second
    JSR DELAY_1S
    
    ; Decrement counter and loop
    DEX
    BNE STARTUP_BLINK_LOOP
    
    ; Enable interrupts
    CLI

MAIN_LOOP:
    ; Just wait for interrupts
    JMP MAIN_LOOP

;------------------------------------
; IRQ Handler - Blink LED 2 times
;------------------------------------
IRQ_HANDLER:
    ; Save registers
    PHA
    TXA
    PHA
    TYA
    PHA
    
    ; Blink LED 2 times
    LDX #2              ; 2 blinks
IRQ_BLINK_LOOP:
    ; Turn LED ON
    LDA #PA2
    STA KB_PORTA
    
    ; Wait 1 second
    JSR DELAY_1S
    
    ; Turn LED OFF
    LDA #$00
    STA KB_PORTA
    
    ; Wait 1 second
    JSR DELAY_1S
    
    ; Decrement counter and loop
    DEX
    BNE IRQ_BLINK_LOOP
    
    ; Restore registers
    PLA
    TAY
    PLA
    TAX
    PLA
    
    RTI

;------------------------------------
; Delay 1 second (approximately for 1MHz 6502)
;------------------------------------
DELAY_1S:
    LDY #4              ; Outer loop count
DELAY_1S_OUTER:
    LDX #$00            ; Inner loop count (256 iterations)
DELAY_1S_MIDDLE:
    ; Inner-most delay loop
    PHA                 ; 3 cycles
    PLA                 ; 4 cycles
    PHA                 ; 3 cycles
    PLA                 ; 4 cycles
    NOP                 ; 2 cycles
    NOP                 ; 2 cycles
    ; Total ~18 cycles per inner loop
    
    DEX                 ; 2 cycles
    BNE DELAY_1S_MIDDLE ; 3 cycles (2 if not taken)
    
    DEY
    BNE DELAY_1S_OUTER
    
    RTS

;------------------------------------
; Reset/IRQ vectors
;------------------------------------
    .org $FFFA
    .word $0000         ; NMI vector (not used)
    .word START         ; Reset vector
    .word IRQ_HANDLER   ; IRQ vector