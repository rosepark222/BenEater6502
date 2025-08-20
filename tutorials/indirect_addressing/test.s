  .org $8000

reset:

;write a 6502 assembly code doing the below
;use zero page of 0x20 to store the address 0xbb00
;use the above zero page, store 0xff to 0xbb00
;store 0xf0 to 0xbb01
;store 0x03 to 0xff away from 0xbb00, which is 0xbbff
;load from 0xbb00 to A register
;store 0x04 to 0xf away from 0xbb00, which is 0xbb0f

  LDA  #$81
  ASL  A
  ADC  #$80
  ROL  A
  ASL  A
  ADC  #$80
  ROL  A

  ; Step 1: Store address $BB00 in zero page $20/$21
  LDA #$00        ; Low byte of $BB00
  STA $20
  LDA #$BB        ; High byte of $BB00
  STA $21

  ; Initialize Y to 0 once, as it's often needed for the first indirect access
  LDY #$00        ; Clear Y for the initial indirect access

  ; Step 2: Store $FF to $BB00 using indirect addressing
  LDA #$FF
  STA ($20),Y     ; Store to $BB00 (since Y is 0)

  ; Step 3: Store $F0 to $BB01 using indirect addressing
  INY             ; Increment Y to 0x01
  LDA #$F0
  STA ($20),Y     ; Store to $BB01 (since Y is 1)

  ; Step 4: Store $03 to $BBFF ($FF offset from $BB00)
  LDA #$03
  LDY #$FF        ; Set Y to 0xFF for the offset
  STA ($20),Y     ; Store to $BBFF

  ; Step 5: Load from $BB00 to A register
  LDY #$00        ; Reset Y to 0 to load from $BB00
  LDA ($20),Y     ; A = contents of $BB00 (should be $FF)

  ; Step 6: Store $04 to $BB0F ($0F offset from $BB00)
  LDA #$04
  LDY #$0F        ; Set Y to 0x0F for the offset
  STA ($20),Y     ; Store to $BB0F

  STA $BB00

  ; Optional: Infinite loop to halt execution (for simulators/emulators)
;  JMP *

  .org $fffc
  .word reset
  .word $0000
