;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; file system base address
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; addresses

; placing FS to ROM ( works for emulator but not for real HW )
; BITMAP_BASE   = $BB00      ; Base address for bitmaps
; INODE_BASE    = $BC00      ; Base address for inodes
; BLOCK_BASE    = $C000      ; Base address for data blocks

; placing FS to RAM
BITMAP_BASE   = $1B00      ; Base address for bitmaps
INODE_BASE    = $1C00      ; Base address for inodes
BLOCK_BASE    = $2000      ; Base address for data blocks

BLOCK_BITMAP  = BITMAP_BASE + $10   ; Block bitmap at $BB10
INODE_BITMAP  = BITMAP_BASE + $00   ; Inode bitmap at $BB00

;;; Zero page addresses for ls_util compatibility
INODE_BASE_HI = $12        ; High byte of inode base
BLOCK_BASE_HI = $13        ; High byte of block base

A_SCRATCH  = $20
X_SCRATCH  = $21
Y_SCRATCH  = $22

;;; constants
INVALID_DATABLOCK = $FF
INVALID_INODE = $00

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; file system utils
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; === Memory Layout Symbols ===

; Scratch Memory
TOKEN_BUFFER    = $0200         ; $0200-$020F: path token buffer (16 bytes)
CURRENT_INODE   = $0210         ; Current inode number during traversal
TEMP_BLOCK_NUM  = $0211         ; Temporary block number storage
TEMP_INODE_NUM  = $0212         ; Temporary inode number storage


; Zero Page Usage
PATH_PTR_LO     = $10           ; Low byte of path string pointer
PATH_PTR_HI     = $11           ; High byte of path string pointer
; Working Pointers (used by various routines)
WORK_PTR_LO     = $00           ; General purpose pointer low byte
WORK_PTR_HI     = $01           ; General purpose pointer high byte
BLOCK_PTR_LO    = $02           ; Block pointer low byte
BLOCK_PTR_HI    = $03           ; Block pointer high byte
DIR_PTR_LO      = $04           ; Directory scanning pointer low
DIR_PTR_HI      = $05           ; Directory scanning pointer high
SCAN_PTR_LO     = $06           ; Scan block pointer low byte
SCAN_PTR_HI     = $07           ; Scan block pointer high byte


; File System Constants
MAX_INODES      = 64            ; Maximum number of inodes
MAX_DATABLOCK   = 64            ; Maximum number of inodes
INODE_SIZE      = 16            ; Size of each inode in bytes
DIR_ENTRY_SIZE  = 16            ; Size of directory entry
BLOCK_SIZE      = 256           ; Size of data block

; Inode Structure Offsets
I_MODE          = 0             ; File type and permissions
I_UID           = 1             ; User ID
I_SIZE_LO       = 2             ; File size low byte
I_SIZE_HI       = 3             ; File size high byte
I_BLOCK0        = 6             ; Direct block 0
I_BLOCK1        = 7             ; Direct block 1  
I_BLOCK2        = 8             ; Indirect block

; Directory Entry Structure Offsets
DE_INODE        = 0             ; Inode number
DE_TYPE         = 1             ; Type
DE_NAME         = 2             ; Start of filename

; File Type Masks
FT_FILE         = %00000000     ; Regular file
FT_DIR          = %00010000     ; Directory

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; === LCD Configuration ===
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

KEY_INPUT    = $0300        ; Key byte buffer
LCD_DATA     = $6000        ; LCD data register
LCD_CMD      = $6001        ; LCD command register (if available)


LCD_CURRENT_ROW  = $0230         ; current row
LCD_CURRENT_COL  = $0231         ; current col
; Buffer for line content (32 bytes: 16 for each line) 
LCD_LINE1_BUFFER = $0240         ; First line buffer 
LCD_LINE2_BUFFER = $0250         ; Second line buffer 

SCROLL_BUFFER      = $0500       ; Start of 16-line buffer (16*16 = 256 bytes)
SCROLL_HEAD        = $0260       ; Index of newest line (0-15)
SCROLL_TAIL        = $0261       ; Index of oldest line (0-15)  
SCROLL_VIEW_TOP    = $0262       ; Index of top line currently displayed (0-15)
SCROLL_COUNT       = $0263       ; Number of lines in buffer (0-16)
SCROLL_MODE        = $0264       ; 0=normal mode, 1=scroll mode


CMD_INDEX          = $0265

; Zero page variables for display helpers
LCD_SRC_LO      = $23       ; Low byte of source buffer address
LCD_SRC_HI      = $24       ; High byte of source buffer address  
LCD_TMP_ADDR_LO = $25       ; Temporary address calculation
LCD_TMP_ADDR_HI = $26       ; Temporary address calculation


; HD44780 LCD Commands 
LCD_CLEAR    = $01          ; Clear display
LCD_HOME     = $02          ; Return home
LCD_ENTRY    = $06          ; Entry mode set
; LCD_DISPLAY  = $0C          ; Display on, cursor off
LCD_DISPLAY  = $0F          ; Display on, cursor on, Blinking on
LCD_FUNCTION = $38          ; Function set: 8-bit, 2-line, 5x8 dots
LCD_CGRAM    = $40          ; Set CGRAM address
LCD_DDRAM    = $80          ; Set DDRAM address

CMD_MAX      = 64           ; Max command length
; LCD Position Constants
LCD_ROW0_COL0_ADDR      = $80          ; DDRAM address for line 1, column 0
LCD_ROW1_COL0_ADDR      = $C0          ; DDRAM address for line 2, column 0
LCD_COLS                = 16           ; Number of columns
LCD_ROWS                = 2            ; Number of rows

;; scroll up down - Scrollable buffer variables
SCROLL_BUFFER_SIZE = 16          ; 16 lines in circular buffer
SCROLL_LINE_SIZE   = 16          ; 16 characters per line

;; scroll up down - Key codes for arrow keys
KEY_UP             = $5B ;  '['  Up scroll key
KEY_DOWN           = $5D ;  ']'  Down scroll key

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; shell  utils
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

CMD_BUFFER      = $0400        ; full command string buffer
PATH_INPUT      = $0400        ; path string buffer, copied over to CMD_BUFFER

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; PWD
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

WORKING_DIR_INODE  = $0213       ; Current working directory inode number (ADDED) ; pwd support
; Additional variables for PWD (reusing existing ls_util variables where possible)
PWD_STACK_PTR = $0214          ; Stack pointer for path reconstruction (after WORKING_DIR_INODE)
PWD_TEMP_INODE = $0215         ; Temporary inode storage
PWD_PARENT_INODE = $0216       ; Parent inode storage

; Path reconstruction buffer and stack
PWD_BUFFER = $0300             ; 256 bytes for path buffer (before TOKEN_BUFFER)
PWD_STACK = $0500              ; 256 bytes for inode stack
