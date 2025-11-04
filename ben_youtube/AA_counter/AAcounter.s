;I have 6502 project having 2, 6522. One for the keyboard is address mapped to 4000, 
;and one for an LCD is mapped to 6000. I want to use port A pin 0 and 1 for raw clock and data for the initial handshaking
; and port B for byte level scan code read for ps/2 keyboard protocol. Initial handshake reads AA from port B when the filtered clock
; signal goes high and reply back FF on port A using raw clock and data following ps/2 protocol. Make the code be able to just read AA
; from the keyboard and print how many times it read AA with a counter on the LCD.

;I have a keyboard interrupt coming to CA1 pin of keyboard 6522. It is positive edge signal. 6522 sends this interrupt to 6502. 
;therefore i need irq handler to read the scancode from the keyboard 6522. Of course, the 6522 has to be programmed so it recognizes 
;the interrupt. the code that you gave to me does not have irq handler, can you change that.

; 6502 PS/2 Keyboard Interface with dual 6522 VIAs
; Keyboard VIA at $4000, LCD VIA at $6000
; Uses CA1 interrupt on positive edge for keyboard scan codes

; VIA Register offsets
PORTB = $00
PORTA = $01
DDRB  = $02
DDRA  = $03
PCR   = $0C     ; Peripheral Control Register
IFR   = $0D     ; Interrupt Flag Register
IER   = $0E     ; Interrupt Enable Register

; Keyboard VIA ($4000)
KB_PORTB = $4000    ; Port B - Scan code input (8-bit)
KB_PORTA = $4001    ; Port A - bit 0: CLK, bit 1: DATA
KB_DDRB  = $4002
KB_DDRA  = $4003
KB_PCR   = $400C    ; Peripheral Control Register
KB_IFR   = $400D    ; Interrupt Flag Register
KB_IER   = $400E    ; Interrupt Enable Register

; LCD VIA ($6000)
LCD_PORTB = $6000   ; Port B - LCD data
LCD_PORTA = $6001   ; Port A - LCD control (RS, RW, E)
LCD_DDRB  = $6002
LCD_DDRA  = $6003

; LCD Control bits (Port A)
LCD_E  = %10000000  ; Enable bit
LCD_RW = %01000000  ; Read/Write bit
LCD_RS = %00100000  ; Register Select bit

; PS/2 protocol bits
PS2_CLK  = %00000001  ; Port A bit 0
PS2_DATA = %00000010  ; Port A bit 1

; Variables
AA_COUNT = $0200    ; 16-bit counter (low byte)
AA_COUNT_H = $0201  ; high byte
DISPLAY_UPDATE = $0202  ; Flag to indicate display needs update

    .org $8000

START:
    ; Disable interrupts during initialization
    SEI
    
    ; Initialize system
    JSR INIT_VIA
    JSR LCD_INIT
    
    ; Clear AA counter
    LDA #$00
    STA AA_COUNT
    STA AA_COUNT_H
    STA DISPLAY_UPDATE
    
    ; Display initial message
    JSR LCD_CLEAR
    LDA #$00
    JSR LCD_SET_CURSOR
    JSR DISPLAY_COUNT
    
    ; Enable interrupts
    CLI

MAIN_LOOP:
    ; Check if display needs updating
    LDA DISPLAY_UPDATE
    BEQ MAIN_LOOP       ; If no update needed, keep waiting
    
    ; Clear update flag
    LDA #$00
    STA DISPLAY_UPDATE
    
    ; Update LCD with new count
    JSR DISPLAY_COUNT
    
    ; Continue monitoring
    JMP MAIN_LOOP

;------------------------------------
; IRQ Handler
;------------------------------------
IRQ_HANDLER:
    ; Save registers
    PHA
    TXA
    PHA
    TYA
    PHA
    
    ; Check if interrupt is from keyboard VIA
    LDA KB_IFR
    AND #%10000000      ; Check if any interrupt flag is set
    BEQ IRQ_EXIT        ; Not from this VIA
    
    ; Check if CA1 interrupt (bit 1)
    LDA KB_IFR
    AND #%00000010
    BEQ IRQ_EXIT        ; Not CA1 interrupt
    
    ; Read scan code from Port B
    LDA KB_PORTB
    
    ; Check if it's AA
    CMP #$AA
    BNE CLEAR_IRQ       ; Not AA, just clear interrupt
    
    ; Increment counter
    INC AA_COUNT
    BNE SET_UPDATE
    INC AA_COUNT_H
    
SET_UPDATE:
    ; Set flag to update display in main loop
    LDA #$01
    STA DISPLAY_UPDATE
    
CLEAR_IRQ:
    ; Clear CA1 interrupt flag by reading Port A
    LDA KB_PORTA        ; Reading Port A clears CA1 flag
    
IRQ_EXIT:
    ; Restore registers
    PLA
    TAY
    PLA
    TAX
    PLA
    
    RTI

;------------------------------------
; Initialize VIA chips
;------------------------------------
INIT_VIA:
    ; Setup Keyboard VIA
    ; Port A: bits 0-1 as inputs for clock and data monitoring
    LDA #%00000000
    STA KB_DDRA
    
    ; Port B: all inputs for scan code
    LDA #%00000000
    STA KB_DDRB
    
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
    
    ; Setup LCD VIA
    ; Port B: all outputs for LCD data
    LDA #%11111111
    STA LCD_DDRB
    
    ; Port A: bits 5-7 as outputs for LCD control
    LDA #%11100000
    STA LCD_DDRA
    
    RTS

;------------------------------------
; LCD Initialization

;------------------------------------
LCD_INIT:
    LDA #$FF
    STA LCD_DDRB    ; Port B output
    
    ; Wait for LCD power up
    JSR DELAY_15MS
    
    ; Initialize 8-bit mode
    LDA #$38        ; 8-bit, 2 line, 5x8 font
    JSR LCD_COMMAND
    JSR DELAY_5MS
    
    ; Display on, cursor off
    LDA #$0C
    JSR LCD_COMMAND
    
    ; Clear display
    JSR LCD_CLEAR
    
    ; Entry mode: increment, no shift
    LDA #$06
    JSR LCD_COMMAND
    
    RTS

LCD_CLEAR:
    LDA #$01
    JSR LCD_COMMAND
    JSR DELAY_5MS
    RTS

LCD_SET_CURSOR:
    ; Set cursor to position in A (0-15 for line 1, 64+ for line 2)
    ORA #$80
    JSR LCD_COMMAND
    RTS

LCD_COMMAND:
    PHA
    JSR LCD_WAIT
    PLA
    STA LCD_PORTB
    LDA #$00        ; RS=0, RW=0
    STA LCD_PORTA
    LDA #LCD_E      ; E=1
    STA LCD_PORTA
    LDA #$00        ; E=0
    STA LCD_PORTA
    RTS

LCD_WRITE_CHAR:
    PHA
    JSR LCD_WAIT
    PLA
    STA LCD_PORTB
    LDA #LCD_RS     ; RS=1, RW=0
    STA LCD_PORTA
    ORA #LCD_E      ; E=1
    STA LCD_PORTA
    LDA #LCD_RS     ; E=0
    STA LCD_PORTA
    RTS

LCD_WAIT:
    ; Simple delay instead of busy flag check
    JSR DELAY_1MS
    RTS

;------------------------------------
; Display count on LCD
;------------------------------------
DISPLAY_COUNT:
    ; Set cursor to start
    LDA #$00
    JSR LCD_SET_CURSOR
    
    ; Display "AA Count: "
    LDX #$00
DISPLAY_MSG:
    LDA MESSAGE,X
    BEQ DISPLAY_NUMBER
    JSR LCD_WRITE_CHAR
    INX
    JMP DISPLAY_MSG
    
DISPLAY_NUMBER:
    ; Convert 16-bit count to decimal and display
    ; For simplicity, display hex value
    LDA AA_COUNT_H
    JSR DISPLAY_HEX_BYTE
    LDA AA_COUNT
    JSR DISPLAY_HEX_BYTE
    RTS

DISPLAY_HEX_BYTE:
    PHA
    ; High nibble
    LSR
    LSR
    LSR
    LSR
    JSR DISPLAY_HEX_DIGIT
    ; Low nibble
    PLA
    AND #$0F
    JSR DISPLAY_HEX_DIGIT
    RTS

DISPLAY_HEX_DIGIT:
    CMP #$0A
    BCC IS_DIGIT
    ; A-F
    ADC #$36        ; 'A' - 10 - 1 (carry is set)
    JMP WRITE_HEX
IS_DIGIT:
    ADC #$30        ; '0'
WRITE_HEX:
    JSR LCD_WRITE_CHAR
    RTS

MESSAGE:
    .byte "AA Count: ", $00

;------------------------------------
; Delay routines
;------------------------------------
DELAY_15MS:
    LDX #$03
DL15:
    JSR DELAY_5MS
    DEX
    BNE DL15
    RTS

DELAY_5MS:
    LDX #$05
DL5:
    JSR DELAY_1MS
    DEX
    BNE DL5
    RTS

DELAY_1MS:
    LDY #$FA
DL1:
    DEY
    BNE DL1
    RTS

;------------------------------------
; Reset/IRQ vectors
;------------------------------------
    .org $FFFA
    .word $0000         ; NMI vector (not used)
    .word START         ; Reset vector
    .word IRQ_HANDLER   ; IRQ vector
