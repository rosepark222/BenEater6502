
; 6502 LED Control with Direct IRQ Button
; Button with pull-up connected directly to 6502 IRQ pin
; Turns LED (on PA2) off when button is pressed
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
    
    ; Turn LED ON initially
    LDA #PA2
    STA KB_PORTA

    
    ; Enable interrupts
    CLI

MAIN_LOOP:
    ; Just wait for interrupts
    JMP MAIN_LOOP

;------------------------------------
; IRQ Handler - Turn LED off when button pressed
;------------------------------------
IRQ_HANDLER:
    ; Save registers
    PHA
    TXA
    PHA
    TYA
    PHA
    
    ;Turn LED off
    LDA #0
    STA KB_PORTA

    ; Restore registers
    PLA
    TAY
    PLA
    TAX
    PLA
    
    RTI

;------------------------------------
; Reset/IRQ vectors
;------------------------------------
    .org $FFFA
    .word $0000         ; NMI vector (not used)
    .word START         ; Reset vector
    .word IRQ_HANDLER   ; IRQ vector
