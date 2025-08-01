    .org $8000         ; Start of program

; === Base Address Configuration ===

BITMAP_BASE   = $BB00      ; Base address for bitmaps
INODE_BASE    = $BC00      ; Base address for inodes
BLOCK_BASE    = $C000      ; Base address for data blocks

;BITMAP_BASE   = $1B00      ; Base address for bitmaps
;INODE_BASE    = $1C00      ; Base address for inodes
;BLOCK_BASE    = $2000      ; Base address for data blocks

; Derived addresses
BLOCK_BITMAP  = BITMAP_BASE + $10   ; Block bitmap at $BB10
INODE_BITMAP  = BITMAP_BASE + $00   ; Inode bitmap at $BB00

; Zero page addresses for ls_util compatibility
INODE_BASE_HI = $12        ; High byte of inode base
BLOCK_BASE_HI = $13        ; High byte of block base

INVALID_DATABLOCK = $FF
INVALID_INODE = $00

A_SCRATCH  = $20
X_SCRATCH  = $21
Y_SCRATCH  = $22

; === Initialize base addresses for ls_util ===
InitBaseAddresses:
    LDA #>INODE_BASE       ; High byte of inode base ($BC)
    STA INODE_BASE_HI      ; Store in $12
    LDA #>BLOCK_BASE       ; High byte of block base ($C0)
    STA BLOCK_BASE_HI      ; Store in $13

; === Set inode and block bitmaps ===
SetBitmaps:
    LDA #%01111111         ; Blocks 0-4 + 6 used
    STA BLOCK_BITMAP       ; Block bitmap
    LDA #%00111111         ; Inodes 0-5 used
    STA INODE_BITMAP       ; Inode bitmap

; === Inode 0: root directory ===
    LDA #%00010001
    STA INODE_BASE+$00     ; i_mode
    LDA #$00
    STA INODE_BASE+$01     ; uid
    LDA #$30
    STA INODE_BASE+$02     ; size = 3 entries * 16
    LDA #$00
    STA INODE_BASE+$03
    STA INODE_BASE+$04
    STA INODE_BASE+$05
    LDA #$00
    STA INODE_BASE+$06     ; block 0
    LDA #INVALID_DATABLOCK
    STA INODE_BASE+$07
    STA INODE_BASE+$08

; === Inode 1: README.txt ===
    LDA #%00000001
    STA INODE_BASE+$10
    STA INODE_BASE+$11
    LDA #$00
    STA INODE_BASE+$12
    LDA #$04
    STA INODE_BASE+$13     ; size = 1024 bytes
    STA INODE_BASE+$14
    STA INODE_BASE+$15
    LDA #$01
    STA INODE_BASE+$16     ; i_block[0] = block 1
    LDA #$02
    STA INODE_BASE+$17     ; i_block[1] = block 2
    LDA #$07
    STA INODE_BASE+$18     ; i_block[2] = block 6 (indirect)

; === Inode 2: /ram ===
    LDA #%00010001
    STA INODE_BASE+$20
    STA INODE_BASE+$21
    STA INODE_BASE+$22
    STA INODE_BASE+$23
    STA INODE_BASE+$24
    STA INODE_BASE+$25
    LDA #$05
    STA INODE_BASE+$26     ; block 5
    LDA #INVALID_DATABLOCK
    STA INODE_BASE+$27
    STA INODE_BASE+$28

; === Inode 3: /rom ===
    LDA #%00010001
    STA INODE_BASE+$30
    STA INODE_BASE+$31
    LDA #$20
    STA INODE_BASE+$32     ; 2 entries
    STA INODE_BASE+$33
    STA INODE_BASE+$34
    STA INODE_BASE+$35
    LDA #$06
    STA INODE_BASE+$36     ; block 6
    LDA #INVALID_DATABLOCK
    STA INODE_BASE+$37
    STA INODE_BASE+$38

; === Inode 4: romFS.txt ===
    LDA #%00000001
    STA INODE_BASE+$40
    STA INODE_BASE+$41
    STA INODE_BASE+$42
    STA INODE_BASE+$43
    STA INODE_BASE+$44
    STA INODE_BASE+$45
    LDA #$08
    STA INODE_BASE+$46
    LDA #INVALID_DATABLOCK
    STA INODE_BASE+$47
    STA INODE_BASE+$48

; === Inode 5: /rom/bin ===
    LDA #%00010001
    STA INODE_BASE+$50
    STA INODE_BASE+$51
    STA INODE_BASE+$52
    STA INODE_BASE+$53
    STA INODE_BASE+$54
    STA INODE_BASE+$55
    LDA #$09
    STA INODE_BASE+$56     ; reused block 4 (for testing, update if needed)
    LDA #INVALID_DATABLOCK
    STA INODE_BASE+$57
    STA INODE_BASE+$58

; === Root dir @ block 0 ===
    ; Entry 1: README.txt
    LDA #$01
    STA BLOCK_BASE+$000
    LDA #$00
    STA BLOCK_BASE+$001
    LDX #$00
Loop_README:
    LDA README_name,X
    STA BLOCK_BASE+$002,X
    INX
    CPX #14
    BNE Loop_README

    ; Entry 2: ram
    LDA #$02
    STA BLOCK_BASE+$010
    LDA #$01
    STA BLOCK_BASE+$011
    LDX #$00
Loop_RAM:
    LDA RAM_name,X
    STA BLOCK_BASE+$012,X
    INX
    CPX #14
    BNE Loop_RAM

    ; Entry 3: rom
    LDA #$03
    STA BLOCK_BASE+$020
    LDA #$01
    STA BLOCK_BASE+$021
    LDX #$00
Loop_ROM:
    LDA ROM_name,X
    STA BLOCK_BASE+$022,X
    INX
    CPX #14
    BNE Loop_ROM

; === /rom dir @ block 6 ===
    ; Entry 1: romFS.txt
    LDA #$04
    STA BLOCK_BASE+$600
    LDA #$00
    STA BLOCK_BASE+$601
    LDX #$00
Loop_romFS:
    LDA ROMFS_name,X
    STA BLOCK_BASE+$602,X
    INX
    CPX #14
    BNE Loop_romFS

    ; Entry 2: bin
    LDA #$05
    STA BLOCK_BASE+$610
    LDA #$01
    STA BLOCK_BASE+$611
    LDX #$00
Loop_bin:
    LDA BIN_name,X
    STA BLOCK_BASE+$612,X
    INX
    CPX #14
    BNE Loop_bin

; === README.txt indirect block (block 7) ===
    LDA #$03
    STA BLOCK_BASE+$700
    LDA #$04
    STA BLOCK_BASE+$701

; === Fill README.txt file data blocks (1, 2, 3, 4) with 0xEA ===

; FillBlock1:
;     LDX #$00
; LoopB1:
;     LDA #$EA
;     STA BLOCK_BASE+$100,X
;     INX
;     BNE LoopB1

; FillBlock2:
;     LDX #$00
; LoopB2:
;     LDA #$EA
;     STA BLOCK_BASE+$200,X
;     INX
;     BNE LoopB2

; FillBlock3:
;     LDX #$00
; LoopB3:
;     LDA #$EA
;     STA BLOCK_BASE+$300,X
;     INX
;     BNE LoopB3

; FillBlock4:
;     LDX #$00
; LoopB4:
;     LDA #$EA
;     STA BLOCK_BASE+$400,X
;     INX
;     BNE LoopB4

;BRK
;    .align 2 ; 2 byte alignment
;token1:       .byte "wwwwwwwwwwwwwwww"
    .include "../shell/test.s"
    .include "../ls_util/test.s"

    .org $CF60
; === File/Dir Names (14B) ===
token2:       .byte "wwwwwwwwwwwwwwww"
; README_name: .byte "1", 0, 0, 0
; RAM_name:    .byte "2", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
; ROM_name:    .byte "3", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
; ROMFS_name:  .byte "4", 0, 0, 0, 0
; BIN_name:    .byte "5", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
README_name: .byte "Readme.txt", 0, 0, 0
RAM_name:    .byte "ram", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
ROM_name:    .byte "rom", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
ROMFS_name:  .byte "romfs.txt", 0, 0, 0, 0
BIN_name:    .byte "bin", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0