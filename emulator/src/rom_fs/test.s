    .org $8000         ; Start of program

; === Set inode and block bitmaps ===
SetBitmaps:
    LDA #%01111111      ; Blocks 0-4 + 6 used
    STA $BB10           ; Block bitmap
    LDA #%00111111      ; Inodes 0-5 used
    STA $BB00           ; Inode bitmap

; === Inode 0: root directory ===
    LDA #%00010001
    STA $BC00           ; i_mode
    LDA #$00
    STA $BC01           ; uid
    LDA #$30
    STA $BC02           ; size = 3 entries * 16
    LDA #$00
    STA $BC03
    STA $BC04
    STA $BC05
    LDA #$00
    STA $BC06           ; block 0
    STA $BC07
    STA $BC08

; === Inode 1: README.txt ===
    LDA #%00000001
    STA $BC10
    STA $BC11
    LDA #$00
    STA $BC12
    LDA #$04
    STA $BC13           ; size = 1024 bytes
    STA $BC14
    STA $BC15
    LDA #$01
    STA $BC16           ; i_block[0] = block 1
    LDA #$02
    STA $BC17           ; i_block[1] = block 2
    LDA #$06
    STA $BC18           ; i_block[2] = block 6 (indirect)

; === Inode 2: /ram ===
    LDA #%00010001
    STA $BC20
    STA $BC21
    STA $BC22
    STA $BC23
    STA $BC24
    STA $BC25
    LDA #$05
    STA $BC26           ; block 5
    STA $BC27
    STA $BC28

; === Inode 3: /rom ===
    LDA #%00010001
    STA $BC30
    STA $BC31
    LDA #$20
    STA $BC32           ; 2 entries
    STA $BC33
    STA $BC34
    STA $BC35
    LDA #$03
    STA $BC36           ; block 3
    STA $BC37
    STA $BC38

; === Inode 4: romFS.txt ===
    LDA #%00000001
    STA $BC40
    STA $BC41
    STA $BC42
    STA $BC43
    STA $BC44
    STA $BC45
    LDA #$04
    STA $BC46
    STA $BC47
    STA $BC48

; === Inode 5: /rom/bin ===
    LDA #%00010001
    STA $BC50
    STA $BC51
    STA $BC52
    STA $BC53
    STA $BC54
    STA $BC55
    LDA #$04
    STA $BC56           ; reused block 4 (for testing, update if needed)
    STA $BC57
    STA $BC58

; === Root dir @ block 0 = $C000 ===
    ; Entry 1: README.txt
    LDA #$01
    STA $C000
    LDA #$00
    STA $C001
    LDX #$00
Loop_README:
    LDA README_name,X
    STA $C002,X
    INX
    CPX #14
    BNE Loop_README

    ; Entry 2: ram
    LDA #$02
    STA $C010
    LDA #$01
    STA $C011
    LDX #$00
Loop_RAM:
    LDA RAM_name,X
    STA $C012,X
    INX
    CPX #14
    BNE Loop_RAM

    ; Entry 3: rom
    LDA #$03
    STA $C020
    LDA #$01
    STA $C021
    LDX #$00
Loop_ROM:
    LDA ROM_name,X
    STA $C022,X
    INX
    CPX #14
    BNE Loop_ROM

; === /rom dir @ block 3 = $C300 ===
    ; Entry 1: romFS.txt
    LDA #$04
    STA $C300
    LDA #$00
    STA $C301
    LDX #$00
Loop_romFS:
    LDA ROMFS_name,X
    STA $C302,X
    INX
    CPX #14
    BNE Loop_romFS

    ; Entry 2: bin
    LDA #$05
    STA $C310
    LDA #$01
    STA $C311
    LDX #$00
Loop_bin:
    LDA BIN_name,X
    STA $C312,X
    INX
    CPX #14
    BNE Loop_bin

; === README.txt indirect block (block 6 = $C700) ===
    LDA #$03
    STA $C700
    LDA #$04
    STA $C701

; === Fill README.txt file data blocks (1, 2, 3, 4) with 0xEA ===

FillBlock1:
    LDX #$00
LoopB1:
    LDA #$EA
    STA $C100,X
    INX
    BNE LoopB1

FillBlock2:
    LDX #$00
LoopB2:
    LDA #$EA
    STA $C200,X
    INX
    BNE LoopB2

FillBlock3:
    LDX #$00
LoopB3:
    LDA #$EA
    STA $C300,X
    INX
    BNE LoopB3

FillBlock4:
    LDX #$00
LoopB4:
    LDA #$EA
    STA $C400,X
    INX
    BNE LoopB4

BRK

    .org $CF60
; === File/Dir Names (14B) ===
README_name: .byte "README.txt", 0, 0, 0
RAM_name:    .byte "ram", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
ROM_name:    .byte "rom", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
ROMFS_name:  .byte "romFS.txt", 0, 0, 0, 0
BIN_name:    .byte "bin", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
