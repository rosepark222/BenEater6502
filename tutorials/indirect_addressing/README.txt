  .org $8000

reset:

;write a 6502 assembly code doing the below
;use zero page of 0x20 to store the address 0xbb00
;use the above zero page, store 0xff to 0xbb00
;store 0xf0 to 0xbb01
;store 0x03 to 0xff away from 0xbb00, which is 0xbbff
;load from 0xbb00 to A register
;store 0x04 to 0xf away from 0xbb00, which is 0xbb0f









  .org $fffc
  .word reset
  .word $0000
