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
    LDA #$50               ; size = 5 entries * 16 (added . and ..) ; dot, dot_dot entries
    STA INODE_BASE+$02     ; 
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
    LDA #$20               ; size = 2 entries * 16 (. and ..) ; dot, dot_dot entries
    STA INODE_BASE+$22     ; dot, dot_dot entries
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
    LDA #$40               ; size = 4 entries * 16 (., .., romfs.txt, bin) ; dot, dot_dot entries
    STA INODE_BASE+$32     ; dot, dot_dot entries
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
    LDA #$20               ; size = 2 entries * 16 (. and ..) ; dot, dot_dot entries
    STA INODE_BASE+$52     ; dot, dot_dot entries
    STA INODE_BASE+$53
    STA INODE_BASE+$54
    STA INODE_BASE+$55
    LDA #$09
    STA INODE_BASE+$56     ; reused block 4 (for testing, update if needed)
    LDA #INVALID_DATABLOCK
    STA INODE_BASE+$57
    STA INODE_BASE+$58

; === Root dir @ block 0 ===
    ; Entry 1: . (current directory - points to inode 0) ; dot, dot_dot entries
    LDA #$00               ; dot, dot_dot entries
    STA BLOCK_BASE+$000    ; dot, dot_dot entries
    LDA #$01               ; dot, dot_dot entries
    STA BLOCK_BASE+$001    ; dot, dot_dot entries
    LDX #$00               ; dot, dot_dot entries
Loop_DOT:                  ; dot, dot_dot entries
    LDA DOT_name,X         ; dot, dot_dot entries
    STA BLOCK_BASE+$002,X  ; dot, dot_dot entries
    INX                    ; dot, dot_dot entries
    CPX #14                ; dot, dot_dot entries
    BNE Loop_DOT           ; dot, dot_dot entries

    ; Entry 2: .. (parent directory - root has no parent, points to itself) ; dot, dot_dot entries
    LDA #$00               ; dot, dot_dot entries
    STA BLOCK_BASE+$010    ; dot, dot_dot entries
    LDA #$01               ; dot, dot_dot entries
    STA BLOCK_BASE+$011    ; dot, dot_dot entries
    LDX #$00               ; dot, dot_dot entries
Loop_DOTDOT:               ; dot, dot_dot entries
    LDA DOTDOT_name,X      ; dot, dot_dot entries
    STA BLOCK_BASE+$012,X  ; dot, dot_dot entries
    INX                    ; dot, dot_dot entries
    CPX #14                ; dot, dot_dot entries
    BNE Loop_DOTDOT        ; dot, dot_dot entries

    ; Entry 3: README.txt ; dot, dot_dot entries
    LDA #$01
    STA BLOCK_BASE+$020    ; dot, dot_dot entries
    LDA #$00
    STA BLOCK_BASE+$021    ; dot, dot_dot entries
    LDX #$00
Loop_README:
    LDA README_name,X
    STA BLOCK_BASE+$022,X  ; dot, dot_dot entries
    INX
    CPX #14
    BNE Loop_README

    ; Entry 4: ram ; dot, dot_dot entries
    LDA #$02
    STA BLOCK_BASE+$030    ; dot, dot_dot entries
    LDA #$01
    STA BLOCK_BASE+$031    ; dot, dot_dot entries
    LDX #$00
Loop_RAM:
    LDA RAM_name,X
    STA BLOCK_BASE+$032,X  ; dot, dot_dot entries
    INX
    CPX #14
    BNE Loop_RAM

    ; Entry 5: rom ; dot, dot_dot entries
    LDA #$03
    STA BLOCK_BASE+$040    ; dot, dot_dot entries
    LDA #$01
    STA BLOCK_BASE+$041    ; dot, dot_dot entries
    LDX #$00
Loop_ROM:
    LDA ROM_name,X
    STA BLOCK_BASE+$042,X  ; dot, dot_dot entries
    INX
    CPX #14
    BNE Loop_ROM

; === /ram dir @ block 5 === ; dot, dot_dot entries
    ; Entry 1: . (current directory - points to inode 2) ; dot, dot_dot entries
    LDA #$02               ; dot, dot_dot entries
    STA BLOCK_BASE+$500    ; dot, dot_dot entries
    LDA #$01               ; dot, dot_dot entries
    STA BLOCK_BASE+$501    ; dot, dot_dot entries
    LDX #$00               ; dot, dot_dot entries
Loop_RAM_DOT:              ; dot, dot_dot entries
    LDA DOT_name,X         ; dot, dot_dot entries
    STA BLOCK_BASE+$502,X  ; dot, dot_dot entries
    INX                    ; dot, dot_dot entries
    CPX #14                ; dot, dot_dot entries
    BNE Loop_RAM_DOT       ; dot, dot_dot entries

    ; Entry 2: .. (parent directory - points to root inode 0) ; dot, dot_dot entries
    LDA #$00               ; dot, dot_dot entries
    STA BLOCK_BASE+$510    ; dot, dot_dot entries
    LDA #$01               ; dot, dot_dot entries
    STA BLOCK_BASE+$511    ; dot, dot_dot entries
    LDX #$00               ; dot, dot_dot entries
Loop_RAM_DOTDOT:           ; dot, dot_dot entries
    LDA DOTDOT_name,X      ; dot, dot_dot entries
    STA BLOCK_BASE+$512,X  ; dot, dot_dot entries
    INX                    ; dot, dot_dot entries
    CPX #14                ; dot, dot_dot entries
    BNE Loop_RAM_DOTDOT    ; dot, dot_dot entries

; === /rom dir @ block 6 ===
    ; Entry 1: . (current directory - points to inode 3) ; dot, dot_dot entries
    LDA #$03               ; dot, dot_dot entries
    STA BLOCK_BASE+$600    ; dot, dot_dot entries
    LDA #$01               ; dot, dot_dot entries
    STA BLOCK_BASE+$601    ; dot, dot_dot entries
    LDX #$00               ; dot, dot_dot entries
Loop_ROM_DOT:              ; dot, dot_dot entries
    LDA DOT_name,X         ; dot, dot_dot entries
    STA BLOCK_BASE+$602,X  ; dot, dot_dot entries
    INX                    ; dot, dot_dot entries
    CPX #14                ; dot, dot_dot entries
    BNE Loop_ROM_DOT       ; dot, dot_dot entries

    ; Entry 2: .. (parent directory - points to root inode 0) ; dot, dot_dot entries
    LDA #$00               ; dot, dot_dot entries
    STA BLOCK_BASE+$610    ; dot, dot_dot entries
    LDA #$01               ; dot, dot_dot entries
    STA BLOCK_BASE+$611    ; dot, dot_dot entries
    LDX #$00               ; dot, dot_dot entries
Loop_ROM_DOTDOT:           ; dot, dot_dot entries
    LDA DOTDOT_name,X      ; dot, dot_dot entries
    STA BLOCK_BASE+$612,X  ; dot, dot_dot entries
    INX                    ; dot, dot_dot entries
    CPX #14                ; dot, dot_dot entries
    BNE Loop_ROM_DOTDOT    ; dot, dot_dot entries

    ; Entry 3: romFS.txt ; dot, dot_dot entries
    LDA #$04
    STA BLOCK_BASE+$620    ; dot, dot_dot entries
    LDA #$00
    STA BLOCK_BASE+$621    ; dot, dot_dot entries
    LDX #$00
Loop_romFS:
    LDA ROMFS_name,X
    STA BLOCK_BASE+$622,X  ; dot, dot_dot entries
    INX
    CPX #14
    BNE Loop_romFS

    ; Entry 4: bin ; dot, dot_dot entries
    LDA #$05
    STA BLOCK_BASE+$630    ; dot, dot_dot entries
    LDA #$01
    STA BLOCK_BASE+$631    ; dot, dot_dot entries
    LDX #$00
Loop_bin:
    LDA BIN_name,X
    STA BLOCK_BASE+$632,X  ; dot, dot_dot entries
    INX
    CPX #14
    BNE Loop_bin

; === /rom/bin dir @ block 9 === ; dot, dot_dot entries
    ; Entry 1: . (current directory - points to inode 5) ; dot, dot_dot entries
    LDA #$05               ; dot, dot_dot entries
    STA BLOCK_BASE+$900    ; dot, dot_dot entries
    LDA #$01               ; dot, dot_dot entries
    STA BLOCK_BASE+$901    ; dot, dot_dot entries
    LDX #$00               ; dot, dot_dot entries
Loop_BIN_DOT:              ; dot, dot_dot entries
    LDA DOT_name,X         ; dot, dot_dot entries
    STA BLOCK_BASE+$902,X  ; dot, dot_dot entries
    INX                    ; dot, dot_dot entries
    CPX #14                ; dot, dot_dot entries
    BNE Loop_BIN_DOT       ; dot, dot_dot entries

    ; Entry 2: .. (parent directory - points to /rom inode 3) ; dot, dot_dot entries
    LDA #$03               ; dot, dot_dot entries
    STA BLOCK_BASE+$910    ; dot, dot_dot entries
    LDA #$01               ; dot, dot_dot entries
    STA BLOCK_BASE+$911    ; dot, dot_dot entries
    LDX #$00               ; dot, dot_dot entries
Loop_BIN_DOTDOT:           ; dot, dot_dot entries
    LDA DOTDOT_name,X      ; dot, dot_dot entries
    STA BLOCK_BASE+$912,X  ; dot, dot_dot entries
    INX                    ; dot, dot_dot entries
    CPX #14                ; dot, dot_dot entries
    BNE Loop_BIN_DOTDOT    ; dot, dot_dot entries

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
    .include "../lcd_driver/test.s"
    .include "../shell/test.s"
    .include "../ls_util/test.s"
    .include "../cd_util/test.s"
    .include "../pwd_util/test.s"

    .org $CF60
; === File/Dir Names (14B) ===
token2:       .byte "wwwwwwwwwwwwwwww"
; Special directory entries ; dot, dot_dot entries
DOT_name:     .byte ".", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ; dot, dot_dot entries
DOTDOT_name:  .byte "..", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ; dot, dot_dot entries
; Regular entries
README_name:  .byte "Readme.txt", 0, 0, 0
RAM_name:     .byte "ram", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
ROM_name:     .byte "rom", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
ROMFS_name:   .byte "romfs.txt", 0, 0, 0, 0
BIN_name:     .byte "bin", 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

; Updated directory structure:
; .
; ├── . (inode 0)
; ├── .. (inode 0)
; ├── Readme.txt (inode 1)
; ├── /ram (inode 2)
; │   ├── . (inode 2)
; │   └── .. (inode 0)
; └── /rom (inode 3)
;     ├── . (inode 3)
;     ├── .. (inode 0)
;     ├── romFS.txt (inode 4)
;     └── /bin (inode 5)
;         ├── . (inode 5)
;         └── .. (inode 3)