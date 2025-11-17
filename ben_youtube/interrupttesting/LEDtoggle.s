
; 6502 LED Toggle with IRQ Counter
; Button with pull-up connected directly to 6502 IRQ pin
; Counts IRQs and toggles LED every 10000 interrupts
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

; Variables
IRQ_COUNT_L = $0200     ; Counter low byte
IRQ_COUNT_H = $0201     ; Counter high byte
LED_STATE = $0202       ; LED state (0=OFF, 1=ON)

; Constant: 10000 decimal = $2710 hex
THRESHOLD_L = $10
THRESHOLD_H = $27

    .org $8000

START:
    ; Disable interrupts during initialization
    SEI
    
    ; Initialize counter to 0
    LDA #$00
    STA IRQ_COUNT_L
    STA IRQ_COUNT_H
    
    ; Initialize LED state to OFF
    STA LED_STATE
    
    ; Set PA2 as output (bit 2 = 1)
    LDA #%00000100
    STA KB_DDRA
    
    ; Turn LED OFF initially
    LDA #$00
    STA KB_PORTA
    
    ; Enable interrupts
    CLI

MAIN_LOOP:
    ; Just wait for interrupts
    JMP MAIN_LOOP

;------------------------------------
; IRQ Handler - Count and toggle LED at 10000
;------------------------------------
IRQ_HANDLER:
    ; Save registers
    PHA
    TXA
    PHA
    TYA
    PHA
    
    ; Increment counter
    INC IRQ_COUNT_L
    BNE CHECK_THRESHOLD
    INC IRQ_COUNT_H
    
CHECK_THRESHOLD:
    ; Check if counter >= 10000 ($2710)
    ; First compare high byte
    LDA IRQ_COUNT_H
    CMP #THRESHOLD_H
    BCC IRQ_EXIT        ; If high byte < $27, exit
    BNE TOGGLE_AND_RESET ; If high byte > $27, toggle
    
    ; High bytes equal, check low byte
    LDA IRQ_COUNT_L
    CMP #THRESHOLD_L
    BCC IRQ_EXIT        ; If low byte < $10, exit
    
TOGGLE_AND_RESET:
    ; Reset counter to 0
    LDA #$00
    STA IRQ_COUNT_L
    STA IRQ_COUNT_H
    
    ; Toggle LED state
    LDA LED_STATE
    EOR #$01            ; Flip bit 0
    STA LED_STATE
    
    ; Update LED based on state
    BEQ SET_LED_OFF
    
SET_LED_ON:
    LDA #PA2            ; Turn LED ON
    STA KB_PORTA
    JMP IRQ_EXIT
    
SET_LED_OFF:
    LDA #$00            ; Turn LED OFF
    STA KB_PORTA
    
IRQ_EXIT:
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

