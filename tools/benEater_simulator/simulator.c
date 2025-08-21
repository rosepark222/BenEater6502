#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>    // For clock() and CLOCKS_PER_SEC (though less critical now)
#include <unistd.h>  // For usleep() on Linux/WSL for real-time pacing
#include <ctype.h>   // For isxdigit(), isspace()
#include <limits.h>  // Make sure to include this header for UINT_MAX
#include <stdbool.h>
#include <SDL2/SDL.h>
#include "lcdsim.h"

// Include the fake6502 emulator core
#include "fake6502.h"
#include <signal.h>


#include <string.h>   // For strcmp if needed, or just for clarity
#include <unistd.h>   // Required for getopt on many systems
#include <getopt.h>   // Required for getopt_long

volatile sig_atomic_t quit_flag = 0;
#define SIM_TIME_SECONDS 40

#define magic_opcde 0xFF
#define KEY_INPUT 0x0300
#define PRINT_CHAR_ADDR 0x6000

// Stack for subroutine calls (simplified - assumes standard 6502 stack)
#define STACK_BASE 0xfd

#define JSR 0x20
#define RTS 0x60


// --- Emulated 6502 Memory (64KB) ---
// This array represents the 6502's 64KB address space.
uint8_t RAM[65536];

LCDSim *lcd = NULL;
SDL_Window *window = NULL;
SDL_Surface *screen = NULL;


// Global variables to store parsed arguments
char *hex_file_path = NULL;
char *list_file_path = NULL;
char *break_symbol_name = NULL;
//unsigned int break_address = 0;

// --- Data Structure for the symbol_list (Linked List) ---
typedef struct SymbolEntry {
    char *symbol_name;
    unsigned int address;
    struct SymbolEntry *next;
} SymbolEntry;


// --- External CPU state variables (from fake6502.h) ---
// These are declared in fake6502.h and updated by the emulator core.
extern unsigned char   a, x, y, sp, status;
extern unsigned short  pc;
extern unsigned int    clockticks6502; // Total emulated CPU cycles (from fake6502 core)

SymbolEntry *symbol_list = NULL;

// Breakpoints storage
#define MAX_BREAKPOINTS 50
typedef struct {
    unsigned int address;
    char *label;
} Breakpoint;

#define MAX_CALL_STACK 50
typedef struct {
    unsigned int address;
    char *label;
} Subroutine;

static Subroutine call_stack[MAX_CALL_STACK];
static int call_stack_depth = 0;

static Breakpoint breakpoints[MAX_BREAKPOINTS];
static int breakpoint_count = 0;

// --- LCD Cursor Tracking (New Global/Static Variables) ---
static int lcd_current_row = 0; // LCD has 2 rows (0 and 1)
static int lcd_current_col = 0; // LCD has 16 columns (0-15)
#define MAX_LCD_COLUMNS 16
#define MAX_LCD_ROWS 2



// Global file pointer for logging
FILE *log_file = NULL;
 


#define MAX_MONITOR_ADDRESSES 50

typedef struct {
    unsigned int address;
    int size;
} MonitorAddr;

static MonitorAddr monitor_addresses[MAX_MONITOR_ADDRESSES];
static int monitor_count = 0;



    /*   opcode = RAM[pc];
        op1 = RAM[(pc + 1) % 65536];
        op2 = RAM[(pc + 2) % 65536];
        if (opcode == 0x8D && op1 == 0x00 && op2 == 0x60) {
            col++;
            LCD_SetCursor(lcd, row, col);
            LCD_PutChar(lcd, a);
            LCDSim_Draw(lcd);
            SDL_UpdateWindowSurface(window);
        }

==============================================================================================================
In linux, let's say a terminal is busy printing out command result. If I type something, why it does not show up in the terminal mixed with the output of the command ?
==============================================================================================================

Terminal Line Discipline and Input Buffering
Canonical (Cooked) Mode: By default, terminals operate in canonical mode. In this mode, the terminal driver (part of the kernel's TTY subsystem) buffers your input line by line. It waits until you press Enter before making the entire line available to the application (like the shell or a running command).

Echoing: While you type, the terminal driver does echo your characters back to the screen so you can see what you're typing. However, it often echoes them on a new line or after the current output, depending on the terminal emulator's specific behavior and the application's output method.

Buffering: The key is that your typed characters aren't sent to the application until you press Enter. This allows you to use backspace, delete, and other line-editing keys to correct your input before it's processed.

Output Stream: When a command is printing results, it's writing to its standard output. This output stream is distinct from your keyboard input stream. The terminal driver typically prioritizes printing the application's output.

Mixing Prevention: If you type while output is being printed, the terminal driver will usually buffer your input and echo it in a way that tries to avoid directly overwriting or interspersing it with the ongoing output. Once the command finishes its printing, or you press Enter, your buffered input line will then be presented, often on a new line, for the shell to interpret.

==============================================================================================================
when shell give control over 'ls' command, the terminal buffers the input and wait till the ls output is finished, then prints the buffered input ?
==============================================================================================================

Yes, generally, when you type into a Linux terminal while a command like ls is producing output, the terminal (specifically the TTY subsystem in the kernel) buffers your input. It won't directly mix your typed characters with the ongoing output of the ls command.

Here's a breakdown of why this happens:

Canonical (Cooked) Mode: By default, terminals operate in what's called canonical mode. In this mode, the TTY driver acts as a middleman between your keyboard and the running program. It buffers characters you type until you press the Enter key. This buffering allows for basic line editing functionalities like backspace and delete before the input is sent to the application.

Echoing: As you type, the TTY driver echoes the characters back to the screen so you can see what you're entering. However, when another program (like ls) is actively writing to the terminal's output, the TTY driver will try to display your echoed input in a way that minimizes interference. This often means your input appears on a new line or is temporarily obscured by the command's output, but it's still being buffered internally.

Separation of Concerns: The terminal effectively manages two separate streams:

Input Stream (from keyboard): Your typed characters go into a buffer controlled by the TTY driver.

Output Stream (from ls): The ls command writes its output to its standard output, which the TTY driver then prints to the screen.

When Input is Sent: Only when you press Enter (or a specific control character) does the TTY driver process the entire buffered line of your input and make it available to the program that's currently "listening" for input. If ls is still running and not expecting input, your typed line will eventually be passed to the shell once ls completes or if ls itself then attempts to read from standard input.

So, you won't see your input characters interleaved within the ls output line by line. Instead, your input is collected, and then presented as a complete line (usually on its own line) once the output flow subsides and the shell (or another program) is ready to receive input.

This design ensures that:

Your input remains coherent and editable.

The command's output is displayed as intended, without being corrupted by your typing.
    */  


// --- Memory Access Functions for fake6502 ---
// These are the functions fake6502 calls to read from and write to memory.
// We implement them to access our global RAM array.
uint8_t read6502(uint16_t address) {
    return RAM[address];
}

void write6502(uint16_t address, uint8_t value) {

    // In a true hardware system, memory-mapped devices (LCD, sound, etc.) “see” all writes to specific addresses, regardless of what instruction triggers those writes (STA, STX, etc). They don’t care about “what’s in RAM[pc] right now.”
    // By only checking for STA $6000 (opcode==0x8D, op1==0x00, op2==0x60), you miss all other ways the code could write to 0x6000, such as STX, STY, indirect addressing, and even self-modifying code or DMA.
 
    /*
    BenEater computer uses 0x6000 as PORTB and 0x6001 as PORTA
    PORTB for data and PORTA for control - RS, RW and E bits 
    the sequence to send data is 

        PORTB = $6000
        PORTA = $6001
        DDRB  = $6002
        DDRA  = $6003

        E  = %10000000
        RW = %01000000
        RS = %00100000

        LDA #"H"        ; writes data to PORTB
        STA PORTB
        LDA #RS         ; RS = 1 for sending value to data register
        STA PORTA
        LDA #(RS | E)   ; set E high
        STA PORTA
        LDA #RS         ; set E low ( which accomplishes toggling E bit ) 
        STA PORTA
    
    In the LCD emulator, it does not do the above. Using LCDSim_Instruction is enough 
    */

    if (address == 0x6000) {
        // Data register: write a character or data
        LCDSim_Instruction(lcd, 0x0100 | value);       // simulate RS=1 (data register), RW=0 (write)
        LCDSim_Draw(lcd);
        SDL_UpdateWindowSurface(window);
    }
    else if (address == 0x6001) {
        // Instruction register: send a command
        LCDSim_Instruction(lcd, value);       // simulate RS=0 (control register), RW=0 (write)
        LCDSim_Draw(lcd);
        SDL_UpdateWindowSurface(window);
    }
    RAM[address] = value;
}

// Function to print all monitored addresses
void print_monitor_addresses() {
    if (monitor_count == 0) {
        printf("No addresses being monitored\n");
        return;
    }
    
    printf("Monitored addresses:\n");
    for (int i = 0; i < monitor_count; i++) {
        printf("  %04X (%d bytes)\n", monitor_addresses[i].address, monitor_addresses[i].size);
    }
}

// Updated print_cpu_state_to_stream function
void print_cpu_state_to_stream(FILE *stream) {
    // Print CPU registers
    fprintf(stream, "CPU State: PC:%04X A:%02X X:%02X Y:%02X SP:%02X Status:%02X (NV-B DIZC)\n", 
            pc, a, x, y, sp, status);
    
    // Print monitored memory addresses
    for (int i = 0; i < monitor_count; i++) {
        unsigned int start_addr = monitor_addresses[i].address;
        int size = monitor_addresses[i].size;
        
        // Print memory in 16-byte rows
        int bytes_printed = 0;
        while (bytes_printed < size) {
            unsigned int current_addr = start_addr + bytes_printed;
            int bytes_in_row = (size - bytes_printed > 16) ? 16 : (size - bytes_printed);
            
            fprintf(stream, "RAM State $%04X: ", current_addr);
            
            for (int j = 0; j < bytes_in_row; j++) {
                fprintf(stream, "%02X ", RAM[(current_addr + j) & 0xFFFF]);
            }
            
            // Add padding if less than 16 bytes in this row
            for (int j = bytes_in_row; j < 16; j++) {
                fprintf(stream, "   ");
            }
            
            // Print ASCII representation
            fprintf(stream, " |");
            for (int j = 0; j < bytes_in_row; j++) {
                unsigned char byte = RAM[(current_addr + j) & 0xFFFF];
                if (byte >= 32 && byte <= 126) {
                    fprintf(stream, "%c", byte);
                } else {
                    fprintf(stream, ".");
                }
            }
            fprintf(stream, "|\n");
            
            bytes_printed += bytes_in_row;
        }
    }
    
    // If no monitors set, show default memory locations for backward compatibility
    if (monitor_count == 0) {
        fprintf(stream, "RAM State: $0000:%02X $0001:%02X $0002:%02X $0003:%02X\n", 
                RAM[0x0000], RAM[0x0001], RAM[0x0002], RAM[0x0003]);
        fprintf(stream, "RAM State: $6000:%02X $6001:%02X scroll mode $0264:%02X row $0230:%02X col $0231:%02X   \n", 
                RAM[0x6000], RAM[0x6001], RAM[0x0264], RAM[0x0230], RAM[0x0231] );
        fprintf(stream, "RAM State: $0300:%02X $0301:%02X $0302:%02X $0303:%02X\n", 
                RAM[0x0300], RAM[0x0301], RAM[0x0302], RAM[0x0303]);
    }

    fflush(stream);
}

/**
 * @brief Converts a single hexadecimal character to its integer value.
 * @param c The hexadecimal character ('0'-'9', 'a'-'f', 'A'-'F').
 * @return The integer value (0-15), or -1 if invalid.
 */
int hex_char_to_int(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1; // Invalid hex character
}

/**
 * @brief Reads a hex file and loads its content into the emulated RAM.
 * The hex file is expected to contain lines like "0000000: ffa9 028d ...",
 * where the leading address and colon are ignored. It parses pairs of hex characters.
 *
 * @param filename The path to the hex file.
 * @param start_address The memory address in RAM to start loading the data.
 * @param max_bytes The maximum number of bytes to load (to prevent buffer overflow).
 * @return The number of bytes successfully loaded, or -1 on error.
 */
long load_hex_file(const char *filename, uint16_t start_address, size_t max_bytes) {
    FILE *f = fopen(filename, "r");
    if (!f) {
        perror("Error opening hex file");
        return -1;
    }

    long bytes_loaded = 0;
    char line_buffer[1024]; // Buffer to read lines from the file

    while (fgets(line_buffer, sizeof(line_buffer), f) != NULL) {
        char *ptr = line_buffer;

        // Skip leading whitespace characters on the line
        while (*ptr != '\0' && isspace(*ptr)) {
            ptr++;
        }

        // Check if the line starts with an address prefix (e.g., "0000000:")
        // If it does, advance pointer past it.
        int i;
        int is_address_prefix = 1;
        for (i = 0; i < 7; ++i) { // Check for 7 hex digits
            if (!isxdigit(ptr[i])) {
                is_address_prefix = 0;
                break;
            }
        }
        if (is_address_prefix && ptr[7] == ':') {
            ptr += 8; // Move pointer past "XXXXXXX:"
            // Skip any spaces after the colon
            while (*ptr != '\0' && isspace(*ptr)) {
                ptr++;
            }
        }

        // Now, parse the actual hex bytes from the rest of the line
        while (*ptr != '\0') {
            // Skip any whitespace separating hex byte pairs
            while (*ptr != '\0' && isspace(*ptr)) {
                ptr++;
            }
            if (*ptr == '\0') break; // Reached end of line after skipping spaces

            // Read the first hex digit of the byte
            if (!isxdigit(*ptr)) {
                fprintf(stderr, "Warning: Non-hex character '%c' (0x%02X) encountered in data at byte %ld. Skipping rest of line.\n", *ptr, (unsigned int)*ptr, bytes_loaded);
                break; // Stop parsing this line if invalid char found
            }
            int val1 = hex_char_to_int(*ptr++);

            // Skip any whitespace between the two hex digits of a byte (uncommon but robust)
            while (*ptr != '\0' && isspace(*ptr)) {
                ptr++;
            }

            // Read the second hex digit of the byte
            if (!isxdigit(*ptr)) {
                fprintf(stderr, "Warning: Expected second hex digit for byte at %ld, found '%c' (0x%02X). Skipping last single digit.\n", bytes_loaded, *ptr, (unsigned int)*ptr);
                break; // Stop if not a hex digit
            }
            int val2 = hex_char_to_int(*ptr++);

            // Combine the two hex digits into one byte
            uint8_t byte = (uint8_t)((val1 << 4) | val2);

            // Store the byte in RAM, checking for bounds
            if (start_address + bytes_loaded < 65536 && bytes_loaded < max_bytes) {
                RAM[start_address + bytes_loaded] = byte;
                bytes_loaded++;
            } else {
                fprintf(stderr, "Warning: Reached max_bytes or end of RAM while loading hex file. Stopping.\n");
                // Stop loading entirely if bounds are hit
                goto end_loading;
            }
        }
    }

end_loading:; // Label for goto

    fclose(f);
    return bytes_loaded;
}

  
/**
 * @brief Disassembles and prints the 6502 instruction at the given PC to a stream.
 * @param stream The file stream to print to (e.g., stdout or log_file).
 * @param current_pc The current Program Counter of the 6502.
 * @param ram Pointer to the emulated RAM.
 */
uint8_t disassemble_current_instruction(FILE *stream, uint16_t current_pc, const uint8_t *ram, bool kill_on_FF) {
    uint8_t opcode = ram[current_pc];
    uint8_t op1 = ram[(current_pc + 1) % 65536]; // % 65536 to handle wrap-around for peek
    uint8_t op2 = ram[(current_pc + 2) % 65536]; // % 65536 to handle wrap-around for peek

    // Print PC and opcode byte(s)
    fprintf(stream, "%04X: %02X ", current_pc, opcode);

    // This is a simplified disassembler for common opcodes.
    // A complete one would be much larger.
    switch (opcode) {
        case 0x00: fprintf(stream, "         BRK"); break; // Implied
        case 0x01: fprintf(stream, "%02X       ORA ($%02X,X)", op1, op1); break; // Indexed Indirect, X
        case 0x05: fprintf(stream, "%02X       ORA $%02X", op1, op1); break;     // Zero Page
        case 0x06: fprintf(stream, "%02X       ASL $%02X", op1, op1); break;     // Zero Page
        case 0x08: fprintf(stream, "         PHP"); break; // Implied
        case 0x09: fprintf(stream, "%02X       ORA #$%02X", op1, op1); break;   // Immediate
        case 0x0A: fprintf(stream, "         ASL A"); break; // Accumulator
        case 0x0D: fprintf(stream, "%02X %02X    ORA $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0x0E: fprintf(stream, "%02X %02X    ASL $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0x10: fprintf(stream, "%02X       BPL $%04X", op1, (current_pc + 2 + (int8_t)op1) & 0xFFFF); break; // Relative
        case 0x11: fprintf(stream, "%02X       ORA ($%02X),Y", op1, op1); break; // Indirect Indexed, Y
        case 0x15: fprintf(stream, "%02X       ORA $%02X,X", op1, op1); break;   // Zero Page,X
        case 0x16: fprintf(stream, "%02X       ASL $%02X,X", op1, op1); break;   // Zero Page,X
        case 0x18: fprintf(stream, "         CLC"); break; // Implied
        case 0x19: fprintf(stream, "%02X %02X    ORA $%04X,Y", op1, op2, (op2 << 8) | op1); break; // Absolute,Y
        case 0x1D: fprintf(stream, "%02X %02X    ORA $%04X,X", op1, op2, (op2 << 8) | op1); break; // Absolute,X
        case 0x1E: fprintf(stream, "%02X %02X    ASL $%04X,X", op1, op2, (op2 << 8) | op1); break; // Absolute,X

        case 0x20: fprintf(stream, "%02X %02X    JSR $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0x21: fprintf(stream, "%02X       AND ($%02X,X)", op1, op1); break; // Indexed Indirect, X
        case 0x24: fprintf(stream, "%02X       BIT $%02X", op1, op1); break;     // Zero Page
        case 0x25: fprintf(stream, "%02X       AND $%02X", op1, op1); break;     // Zero Page
        case 0x26: fprintf(stream, "%02X       ROL $%02X", op1, op1); break;     // Zero Page
        case 0x28: fprintf(stream, "         PLP"); break; // Implied
        case 0x29: fprintf(stream, "%02X       AND #$%02X", op1, op1); break;   // Immediate
        case 0x2A: fprintf(stream, "         ROL A"); break; // Accumulator
        case 0x2C: fprintf(stream, "%02X %02X    BIT $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0x2D: fprintf(stream, "%02X %02X    AND $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0x2E: fprintf(stream, "%02X %02X    ROL $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0x30: fprintf(stream, "%02X       BMI $%04X", op1, (current_pc + 2 + (int8_t)op1) & 0xFFFF); break; // Relative
        case 0x31: fprintf(stream, "%02X       AND ($%02X),Y", op1, op1); break; // Indirect Indexed, Y
        case 0x35: fprintf(stream, "%02X       AND $%02X,X", op1, op1); break;   // Zero Page,X
        case 0x36: fprintf(stream, "%02X       ROL $%02X,X", op1, op1); break;   // Zero Page,X
        case 0x38: fprintf(stream, "         SEC"); break; // Implied
        case 0x39: fprintf(stream, "%02X %02X    AND $%04X,Y", op1, op2, (op2 << 8) | op1); break; // Absolute,Y
        case 0x3D: fprintf(stream, "%02X %02X    AND $%04X,X", op1, op2, (op2 << 8) | op1); break; // Absolute,X
        case 0x3E: fprintf(stream, "%02X %02X    ROL $%04X,X", op1, op2, (op2 << 8) | op1); break; // Absolute,X

        case 0x40: fprintf(stream, "         RTI"); break; // Implied
        case 0x41: fprintf(stream, "%02X       EOR ($%02X,X)", op1, op1); break; // Indexed Indirect, X
        case 0x45: fprintf(stream, "%02X       EOR $%02X", op1, op1); break;     // Zero Page
        case 0x46: fprintf(stream, "%02X       LSR $%02X", op1, op1); break;     // Zero Page
        case 0x48: fprintf(stream, "         PHA"); break; // Implied
        case 0x49: fprintf(stream, "%02X       EOR #$%02X", op1, op1); break;   // Immediate
        case 0x4A: fprintf(stream, "         LSR A"); break; // Accumulator
        case 0x4C: fprintf(stream, "%02X %02X    JMP $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0x4D: fprintf(stream, "%02X %02X    EOR $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0x4E: fprintf(stream, "%02X %02X    LSR $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0x50: fprintf(stream, "%02X       BVC $%04X", op1, (current_pc + 2 + (int8_t)op1) & 0xFFFF); break; // Relative
        case 0x51: fprintf(stream, "%02X       EOR ($%02X),Y", op1, op1); break; // Indirect Indexed, Y
        case 0x55: fprintf(stream, "%02X       EOR $%02X,X", op1, op1); break;   // Zero Page,X
        case 0x56: fprintf(stream, "%02X       LSR $%02X,X", op1, op1); break;   // Zero Page,X
        case 0x58: fprintf(stream, "         CLI"); break; // Implied
        case 0x59: fprintf(stream, "%02X %02X    EOR $%04X,Y", op1, op2, (op2 << 8) | op1); break; // Absolute,Y
        case 0x5D: fprintf(stream, "%02X %02X    EOR $%04X,X", op1, op2, (op2 << 8) | op1); break; // Absolute,X
        case 0x5E: fprintf(stream, "%02X %02X    LSR $%04X,X", op1, op2, (op2 << 8) | op1); break; // Absolute,X

        case 0x60: fprintf(stream, "         RTS"); break; // Implied
        case 0x61: fprintf(stream, "%02X       ADC ($%02X,X)", op1, op1); break; // Indexed Indirect, X
        case 0x65: fprintf(stream, "%02X       ADC $%02X", op1, op1); break;     // Zero Page
        case 0x66: fprintf(stream, "%02X       ROR $%02X", op1, op1); break;     // Zero Page
        case 0x68: fprintf(stream, "         PLA"); break; // Implied
        case 0x69: fprintf(stream, "%02X       ADC #$%02X", op1, op1); break;   // Immediate
        case 0x6A: fprintf(stream, "         ROR A"); break; // Accumulator
        case 0x6C: fprintf(stream, "%02X %02X    JMP ($%04X)", op1, op2, (op2 << 8) | op1); break; // Indirect Absolute
        case 0x6D: fprintf(stream, "%02X %02X    ADC $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0x6E: fprintf(stream, "%02X %02X    ROR $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0x70: fprintf(stream, "%02X       BVS $%04X", op1, (current_pc + 2 + (int8_t)op1) & 0xFFFF); break; // Relative
        case 0x71: fprintf(stream, "%02X       ADC ($%02X),Y", op1, op1); break; // Indirect Indexed, Y
        case 0x75: fprintf(stream, "%02X       ADC $%02X,X", op1, op1); break;   // Zero Page,X
        case 0x76: fprintf(stream, "%02X       ROR $%02X,X", op1, op1); break;   // Zero Page,X
        case 0x78: fprintf(stream, "         SEI"); break; // Implied
        case 0x79: fprintf(stream, "%02X %02X    ADC $%04X,Y", op1, op2, (op2 << 8) | op1); break; // Absolute,Y
        case 0x7D: fprintf(stream, "%02X %02X    ADC $%04X,X", op1, op2, (op2 << 8) | op1); break; // Absolute,X
        case 0x7E: fprintf(stream, "%02X %02X    ROR $%04X,X", op1, op2, (op2 << 8) | op1); break; // Absolute,X

        case 0x81: fprintf(stream, "%02X       STA ($%02X,X)", op1, op1); break; // Indexed Indirect, X
        case 0x84: fprintf(stream, "%02X       STY $%02X", op1, op1); break;     // Zero Page
        case 0x85: fprintf(stream, "%02X       STA $%02X", op1, op1); break;     // Zero Page
        case 0x86: fprintf(stream, "%02X       STX $%02X", op1, op1); break;     // Zero Page
        case 0x88: fprintf(stream, "         DEY"); break; // Implied
        case 0x8A: fprintf(stream, "         TXA"); break; // Implied
        case 0x8C: fprintf(stream, "%02X %02X    STY $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0x8D: fprintf(stream, "%02X %02X    STA $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0x8E: fprintf(stream, "%02X %02X    STX $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0x90: fprintf(stream, "%02X       BCC $%04X", op1, (current_pc + 2 + (int8_t)op1) & 0xFFFF); break; // Relative
        case 0x91: fprintf(stream, "%02X       STA ($%02X),Y", op1, op1); break; // Indirect Indexed, Y
        case 0x94: fprintf(stream, "%02X       STY $%02X,X", op1, op1); break;   // Zero Page,X
        case 0x95: fprintf(stream, "%02X       STA $%02X,X", op1, op1); break;   // Zero Page,X
        case 0x96: fprintf(stream, "%02X       STX $%02X,Y", op1, op1); break;   // Zero Page,Y
        case 0x98: fprintf(stream, "         TYA"); break; // Implied
        case 0x99: fprintf(stream, "%02X %02X    STA $%04X,Y", op1, op2, (op2 << 8) | op1); break; // Absolute,Y
        case 0x9A: fprintf(stream, "         TXS"); break; // Implied
        case 0x9D: fprintf(stream, "%02X %02X    STA $%04X,X", op1, op2, (op2 << 8) | op1); break; // Absolute,X

        case 0xA0: fprintf(stream, "%02X       LDY #$%02X", op1, op1); break;   // Immediate
        case 0xA1: fprintf(stream, "%02X       LDA ($%02X,X)", op1, op1); break; // Indexed Indirect, X
        case 0xA2: fprintf(stream, "%02X       LDX #$%02X", op1, op1); break;   // Immediate
        case 0xA4: fprintf(stream, "%02X       LDY $%02X", op1, op1); break;     // Zero Page
        case 0xA5: fprintf(stream, "%02X       LDA $%02X", op1, op1); break;     // Zero Page
        case 0xA6: fprintf(stream, "%02X       LDX $%02X", op1, op1); break;     // Zero Page
        case 0xA8: fprintf(stream, "         TAY"); break; // Implied
        case 0xA9: fprintf(stream, "%02X       LDA #$%02X", op1, op1); break;   // Immediate
        case 0xAA: fprintf(stream, "         TAX"); break; // Implied
        case 0xAC: fprintf(stream, "%02X %02X    LDY $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0xAD: fprintf(stream, "%02X %02X    LDA $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0xAE: fprintf(stream, "%02X %02X    LDX $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0xB0: fprintf(stream, "%02X       BCS $%04X", op1, (current_pc + 2 + (int8_t)op1) & 0xFFFF); break; // Relative
        case 0xB1: fprintf(stream, "%02X       LDA ($%02X),Y", op1, op1); break; // Indirect Indexed, Y
        case 0xB4: fprintf(stream, "%02X       LDY $%02X,X", op1, op1); break;   // Zero Page,X
        case 0xB5: fprintf(stream, "%02X       LDA $%02X,X", op1, op1); break;   // Zero Page,X
        case 0xB6: fprintf(stream, "%02X       LDX $%02X,Y", op1, op1); break;   // Zero Page,Y
        case 0xB8: fprintf(stream, "         CLV"); break; // Implied
        case 0xB9: fprintf(stream, "%02X %02X    LDA $%04X,Y", op1, op2, (op2 << 8) | op1); break; // Absolute,Y
        case 0xBA: fprintf(stream, "         TSX"); break; // Implied
        case 0xBC: fprintf(stream, "%02X %02X    LDY $%04X,X", op1, op2, (op2 << 8) | op1); break; // Absolute,X
        case 0xBD: fprintf(stream, "%02X %02X    LDA $%04X,X", op1, op2, (op2 << 8) | op1); break; // Absolute,X
        case 0xBE: fprintf(stream, "%02X %02X    LDX $%04X,Y", op1, op2, (op2 << 8) | op1); break; // Absolute,Y

        case 0xC0: fprintf(stream, "%02X       CPY #$%02X", op1, op1); break;   // Immediate
        case 0xC1: fprintf(stream, "%02X       CMP ($%02X,X)", op1, op1); break; // Indexed Indirect, X
        case 0xC4: fprintf(stream, "%02X       CPY $%02X", op1, op1); break;     // Zero Page
        case 0xC5: fprintf(stream, "%02X       CMP $%02X", op1, op1); break;     // Zero Page
        case 0xC6: fprintf(stream, "%02X       DEC $%02X", op1, op1); break;     // Zero Page
        case 0xC8: fprintf(stream, "         INY"); break; // Implied
        case 0xC9: fprintf(stream, "%02X       CMP #$%02X", op1, op1); break;   // Immediate
        case 0xCA: fprintf(stream, "         DEX"); break; // Implied
        case 0xCC: fprintf(stream, "%02X %02X    CPY $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0xCD: fprintf(stream, "%02X %02X    CMP $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0xCE: fprintf(stream, "%02X %02X    DEC $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0xD0: fprintf(stream, "%02X       BNE $%04X", op1, (current_pc + 2 + (int8_t)op1) & 0xFFFF); break; // Relative
        case 0xD1: fprintf(stream, "%02X       CMP ($%02X),Y", op1, op1); break; // Indirect Indexed, Y
        case 0xD5: fprintf(stream, "%02X       CMP $%02X,X", op1, op1); break;   // Zero Page,X
        case 0xD6: fprintf(stream, "%02X       DEC $%02X,X", op1, op1); break;   // Zero Page,X
        case 0xD8: fprintf(stream, "         CLD"); break; // Implied
        case 0xD9: fprintf(stream, "%02X %02X    CMP $%04X,Y", op1, op2, (op2 << 8) | op1); break; // Absolute,Y
        case 0xDD: fprintf(stream, "%02X %02X    CMP $%04X,X", op1, op2, (op2 << 8) | op1); break; // Absolute,X
        case 0xDE: fprintf(stream, "%02X %02X    DEC $%04X,X", op1, op2, (op2 << 8) | op1); break; // Absolute,X

        case 0xE0: fprintf(stream, "%02X       CPX #$%02X", op1, op1); break;   // Immediate
        case 0xE1: fprintf(stream, "%02X       SBC ($%02X,X)", op1, op1); break; // Indexed Indirect, X
        case 0xE4: fprintf(stream, "%02X       CPX $%02X", op1, op1); break;     // Zero Page
        case 0xE5: fprintf(stream, "%02X       SBC $%02X", op1, op1); break;     // Zero Page
        case 0xE6: fprintf(stream, "%02X       INC $%02X", op1, op1); break;     // Zero Page
        case 0xE8: fprintf(stream, "         INX"); break; // Implied
        case 0xE9: fprintf(stream, "%02X       SBC #$%02X", op1, op1); break;   // Immediate
        case 0xEA: fprintf(stream, "         NOP"); break; // Implied
        case 0xEC: fprintf(stream, "%02X %02X    CPX $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0xED: fprintf(stream, "%02X %02X    SBC $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0xEE: fprintf(stream, "%02X %02X    INC $%04X", op1, op2, (op2 << 8) | op1); break; // Absolute
        case 0xF0: fprintf(stream, "%02X       BEQ $%04X", op1, (current_pc + 2 + (int8_t)op1) & 0xFFFF); break; // Relative
        case 0xF1: fprintf(stream, "%02X       SBC ($%02X),Y", op1, op1); break; // Indirect Indexed, Y
        case 0xF5: fprintf(stream, "%02X       SBC $%02X,X", op1, op1); break;   // Zero Page,X
        case 0xF6: fprintf(stream, "%02X       INC $%02X,X", op1, op1); break;   // Zero Page,X
        case 0xF8: fprintf(stream, "         SED"); break; // Implied
        case 0xF9: fprintf(stream, "%02X %02X    SBC $%04X,Y", op1, op2, (op2 << 8) | op1); break; // Absolute,Y
        case 0xFD: fprintf(stream, "%02X %02X    SBC $%04X,X", op1, op2, (op2 << 8) | op1); break; // Absolute,X
        case 0xFE: fprintf(stream, "%02X %02X    INC $%04X,X", op1, op2, (op2 << 8) | op1); break; // Absolute,X

        default:
            fprintf(stream, "         ??? (0x%02X)", opcode); // Unknown opcode
            break;
    }
    fprintf(stream, "\n");
    fflush(stream);

    return opcode;

    // if(opcode == magic_opcde && kill_on_FF) {
    //     fprintf(stream, "INFO: magic opcode 0xFF detected, terminate the simulation\n");
    //     fprintf(stream, "INFO: this means the code jumps to pc where opcode is 0x00 BRK and executes \n");

    //     return 1;
    // }
    // return 0;
}

void dump_memory_range(FILE *stream, uint16_t start_addr, uint16_t end_addr) {
    printf("\nMemory dump from 0x%04X to 0x%04X:\n", start_addr, end_addr);
    for (uint16_t addr = start_addr; addr <= end_addr; ++addr) {
        if ((addr - start_addr) % 8 == 0) { // Print address every 8 bytes
            fprintf(stream, "\n%07X:", addr);
        }
        // Access the memory. Use 'ram[addr]' if direct access is possible,
        // otherwise use 'read6502(addr)'.
        #ifdef USE_READ6502_FUNCTION
            fprintf(stream, " %02X", read6502(addr));
        #else
            // Assuming 'ram' is your global memory array
            fprintf(stream, " %02X", RAM[addr]);
        #endif
    }
    fprintf(stream, "\n"); // Newline at the end
}
 

bool initialize_sdl_and_lcd(SDL_Window **window, SDL_Surface **screen, LCDSim **lcd) {
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        SDL_Log("SDL_Init failed: %s", SDL_GetError());
        return false;
    }

    *window = SDL_CreateWindow("LCD 16x2", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 331, 149, SDL_WINDOW_SHOWN);
    if (!*window) {
        SDL_Log("SDL_CreateWindow failed: %s", SDL_GetError());
        SDL_Quit(); return false;
    }

    *screen = SDL_GetWindowSurface(*window);
    if (!*screen) {
        SDL_Log("SDL_GetWindowSurface failed: %s", SDL_GetError());
        SDL_DestroyWindow(*window); SDL_Quit(); return false;
    }

    *lcd = LCDSim_Create(*screen, 0, 0, "../../tools/LCDSim/");
    // LCD_State(*lcd, 1, 1, 1);
    // LCD_SetCursor(*lcd, 1, 0);
    // LCD_PutS(*lcd, "gg");
    LCDSim_Draw(*lcd);
    SDL_UpdateWindowSurface(*window);
    // LCD_SetCursor(*lcd, 0, 0);
    return true;
}

bool load_program_and_irq(const char *filename, uint16_t start_addr, uint16_t irq_addr) {
    memset(RAM, 0, sizeof(RAM));

    log_file = fopen("trace.log", "w");
    if (!log_file) {
        perror("Error opening trace.log");
        return false;
    }

    long loaded = load_hex_file(filename, start_addr, sizeof(RAM) - start_addr);
    if (loaded == -1) {
        fprintf(stderr, "Failed to load hex file.\n");
        fclose(log_file);
        return false;
    }

    uint8_t irq_handler_bytes[] = {0x48, 0xE6, 0x02, 0x68, magic_opcde, 0x40};
    memcpy(&RAM[irq_addr], irq_handler_bytes, sizeof(irq_handler_bytes));

    fprintf(log_file, "Loaded main program (%ld bytes) and IRQ handler at 0x%04X\n", loaded, irq_addr);
    return true;
}

void set_vectors(uint16_t reset, uint16_t irq) {
    RAM[0xFFFC] = reset & 0xFF;
    RAM[0xFFFD] = (reset >> 8) & 0xFF;
    RAM[0xFFFE] = irq & 0xFF;
    RAM[0xFFFF] = (irq >> 8) & 0xFF;
    fprintf(log_file, "Vectors set: RESET = 0x%04X, IRQ = 0x%04X\n", reset, irq);
}



// Function to find symbol by address (closest match)
SymbolEntry* find_closest_symbol(unsigned int address) {
    SymbolEntry *current = symbol_list;
    SymbolEntry *closest = NULL;
    unsigned int min_distance = UINT_MAX;
    
    while (current != NULL) {
        if (current->address <= address) {
            unsigned int distance = address - current->address;
            if (distance < min_distance) {
                min_distance = distance;
                closest = current;
            }
        }
        current = current->next;
    }
    return closest;
}

// Function to find symbol by name
SymbolEntry* find_symbol_by_name(const char *name) {
    SymbolEntry *current = symbol_list;
    while (current != NULL) {
        if (strcmp(current->symbol_name, name) == 0) {
            return current;
        }
        current = current->next;
    }
    return NULL;
}

// Function to add breakpoint
void add_breakpoint(unsigned int address, const char *label) {
    if (breakpoint_count >= MAX_BREAKPOINTS) {
        printf("Maximum breakpoints reached!\n");
        return;
    }
    
    for (int i = 0; i < breakpoint_count; i++) {
        if (breakpoints[i].address == address) {
            printf("Breakpoint at %04X already exists. Removing it.\n", address);
            
            // Shift all subsequent elements down by one
            for (int j = i; j < breakpoint_count - 1; j++) {
                breakpoints[j] = breakpoints[j + 1];
            }
            
            // Decrement the count of valid breakpoints
            breakpoint_count--;
            return;
        }
    }
    breakpoints[breakpoint_count].address = address;
    if (label) {
        breakpoints[breakpoint_count].label = malloc(strlen(label) + 1);
        strcpy(breakpoints[breakpoint_count].label, label);
    } else {
        breakpoints[breakpoint_count].label = NULL;
    }
    breakpoint_count++;
    
    // Find closest symbol for display
    SymbolEntry *closest = find_closest_symbol(address);
    if (closest) {
        printf("Breakpoint set at %04X under %s\n", address, closest->symbol_name);
    } else {
        printf("Breakpoint set at %04X\n", address);
    }
}

// Function to check if address is a breakpoint
int is_breakpoint(unsigned int address) {
    for (int i = 0; i < breakpoint_count; i++) {
        if (breakpoints[i].address == address) {
            return 1;
        }
    }
    return 0;
}

// Function to handle read command
void handle_read_command(const char *input) {
    unsigned int start_addr;
    int count = 16; // default
    
    // Parse input: "r 8000 16" or "r 8000"
    if (sscanf(input, "r %x %d", &start_addr, &count) < 1) {
        printf("Usage: r <hex_address> [count]\n");
        return;
    }
    
    printf("Memory dump from %04X:\n", start_addr);
    for (int i = 0; i < count; i++) {
        if (i % 16 == 0) {
            printf("%04X: ", start_addr + i);
        }
        printf("%02X ", RAM[(start_addr + i) & 0xFFFF]);
        if (i % 16 == 15) {
            printf("\n");
        }
    }
    if (count % 16 != 0) {
        printf("\n");
    }
}

// Function to handle write command
void handle_write_command(const char *input) {
    unsigned int address;
    unsigned int value;
    
    // Parse input: "w 8000 FF"
    if (sscanf(input, "w %x %x", &address, &value) != 2) {
        printf("Usage: w <hex_address> <hex_value>\n");
        return;
    }
    
    if (value > 0xFF) {
        printf("Value must be 0x00-0xFF\n");
        return;
    }
    
    RAM[address & 0xFFFF] = (unsigned char)value;
    printf("Wrote %02X to address %04X\n", value, address);
}

// Function to print all breakpoints
void print_breakpoints() {
    if (breakpoint_count == 0) {
        printf("No breakpoints set\n");
        return;
    }
    
    printf("Breakpoints:\n");
    for (int i = 0; i < breakpoint_count; i++) {
        if (breakpoints[i].label) {
            printf("  %04X (%s)\n", breakpoints[i].address, breakpoints[i].label);
        } else {
            printf("  %04X\n", breakpoints[i].address);
        }
    }
    printf("\n");
}

// Function to handle breakpoint command
void handle_breakpoint_command(const char *input) {
    char label_or_addr[256];
    unsigned int address;
    
    // Skip 'b' and whitespace
    const char *ptr = input + 1;
    while (*ptr == ' ' || *ptr == '\t') ptr++;
    
    if (*ptr == '\0') {
        // printf("No breakpoint address specified. Currently active breakpoints:\n");
        print_breakpoints();
        return;
    }

    // Check if it's a hex address (starts with 0x or all hex digits)
    if (sscanf(ptr, "%x", &address) == 1 || sscanf(ptr, "0x%x", &address) == 1) {
        add_breakpoint(address, NULL);
    } else {
        // It's a label
        SymbolEntry *symbol = find_symbol_by_name(ptr);
        if (symbol) {
            add_breakpoint(symbol->address, ptr);
        } else {
            printf("Warning: Label '%s' not found\n", ptr);
        }
    }
}



void print_gdb_help() {
    printf("Debug Command Examples\n");
    printf("h           :  print help\n");
    printf("<enter>     :  run next instruction\n");
    printf("c           :  continue to the next breakpoint\n");
    printf("r           :  read memory.  r addr 32 for printing 32 byte from addr\n");
    printf("w addr val  :  write memory byte -- w addr value \n");
    printf("t           :  print call stack\n");
    printf("u           :  add a breakpoint at subroutine calls the current subroutine\n");
    printf("b           :  print all breakpoints\n");
    printf("b addr      :  add breakpoint at addr; it also remove it if the breakpoint exists in the database already\n");
    printf("b label     :  add breakpoint at address correspoinding to the label\n");
    
    printf("s *lcd*     :  print all labels matching the pattern\n");
    printf("m           :  print current monitoring address\n");
    printf("m addr      :  monitor address (4 byte default); it also remove it from monitor if exits \n");
    printf("m addr n    :  monitor address n byte\n");
}

// Function to push subroutine call onto debug stack
void push_subroutine_call(unsigned int jsr_address) {
    if (call_stack_depth >= MAX_CALL_STACK) {
        printf("Warning: Call stack overflow!\n");
        return;
    }
    
    // Find the symbol for this JSR target address
    SymbolEntry *symbol = find_closest_symbol(jsr_address);
    
    call_stack[call_stack_depth].address = jsr_address;
    if (symbol && symbol->address == jsr_address) {
        // Exact match - use the symbol name
        call_stack[call_stack_depth].label = malloc(strlen(symbol->symbol_name) + 1);
        strcpy(call_stack[call_stack_depth].label, symbol->symbol_name);
    } else if (symbol) {
        // Close match - show symbol + offset
        char temp_label[256];
        snprintf(temp_label, sizeof(temp_label), "%s+%d", 
                symbol->symbol_name, jsr_address - symbol->address);
        call_stack[call_stack_depth].label = malloc(strlen(temp_label) + 1);
        strcpy(call_stack[call_stack_depth].label, temp_label);
    } else {
        call_stack[call_stack_depth].label = NULL;
    }
    
    call_stack_depth++;
}

// Function to pop subroutine call from debug stack
void pop_subroutine_call() {
    if (call_stack_depth <= 0) {
        printf("Warning: RTS without matching JSR!\n");
        return;
    }
    
    call_stack_depth--;
    if (call_stack[call_stack_depth].label) {
        free(call_stack[call_stack_depth].label);
        call_stack[call_stack_depth].label = NULL;
    }
}

// Function to print call stack trace
void print_call_stack() {
    printf("Call stack trace (%d levels):\n", call_stack_depth);
    
    if (call_stack_depth == 0) {
        printf("  No subroutine calls active\n");
        return;
    }
    
    // Print from bottom to top (oldest to newest calls)
    for (int i = 0; i < call_stack_depth; i++) {
        if (call_stack[i].label) {
            printf("  #%d: %04X (%s)\n", i, call_stack[i].address, call_stack[i].label);
        } else {
            printf("  #%d: %04X\n", i, call_stack[i].address);
        }
    }
    printf("\n");
    printf("CPU status:\n");
    SymbolEntry *closest = find_closest_symbol(pc);
    if (closest) {
        printf("pc at %04X under %s\n", pc, closest->symbol_name);
    }  

    disassemble_current_instruction(stdout, pc, RAM, false);
    print_cpu_state_to_stream(stdout);
    //print_monitor_addresses();
}
 

// Function to handle "up" command - set breakpoint at return address
void handle_up_command() {
    if (sp >= 0xFF) {
        printf("No return address on stack\n");
        return;
    }
    
    // Get return address from stack
    unsigned int return_addr = call_stack[call_stack_depth-1].address + 3;
    // RAM[STACK_BASE + sp + 1] | 
    // (RAM[STACK_BASE + sp + 2] << 8);
    //return_addr++; // Adjust for JSR behavior
    
    // Set temporary breakpoint at return address
    add_breakpoint(return_addr, "up command breakpoint");
    printf("Will break at return address %04X\n", return_addr);
}

// Cleanup function to free breakpoint memory
void cleanup_breakpoints() {
    for (int i = 0; i < breakpoint_count; i++) {
        if (breakpoints[i].label) {
            free(breakpoints[i].label);
        }
    }
    breakpoint_count = 0;
}

// Simple wildcard pattern matching function
// Supports * (match any sequence) and ? (match single character)

/* 

I asked perplexity as:
Explain using s*ts pattern and ststs text.

--------------------------------------------------------------------------------
Here's how the pattern s*ts matches the text ststs using the wildcard matching logic from your code:

Text:    ststs
Pattern: s*ts

's': matches literal 's'
'*': matches zero or more characters
't': matches literal 't'
's': matches literal 's'

--------------------------------------------------------------------------------
my understanding on the backtracking after reading the answer from preplexity:

    s match (t=p=0)
    * found, remember t to return if needed (start_pattern = 2)
    t match (t=1, p=2)
    s match (t=2, p=3)
    pattern done but text remains
    return to t (backtracking) (p=2) in pattern because there may be *ts
    t match (t=3, p=2)
    s match  (t=4, p=3)
    text end and pattern end --> match found

--------------------------------------------------------------------------------
the below is how perplexity explains:

Step-by-step matching process:

1, Match the first 's'
Pattern 's' matches Text 's' (first character)
Advance pointers: Pattern now at '*', Text at 't'

2, Encounter '*' in pattern
Record star_pattern pointing to 't' (after '*')
Record star_text at current text 't'
Advance pattern beyond '*': Pattern at 't'
Do not advance text yet (still at 't')

3, Try to match 't' in pattern with 't' in text
Match! Advance both: Pattern at 's', Text at 's' (third character)

4, Try to match 's' in pattern with 's' in text
Match! Advance both: Pattern at end ('\0'), Text at 't' (fourth character)

5, Pattern finished? No, text remains ('t' and 's')
Since pattern pointer is at end, but text is not, backtrack to last '*' and try to expand it to consume more text.

6, Backtrack and consume one more character with '*'
Pattern reset to 't' (after '*')
Text advances to 's' (fourth character)

7, Try to match 't' to 's'
No match, backtrack again: text advances to next char 't' (fifth character)

8, Try to match 't' to 't'
Match! Advance both: Pattern at 's', Text at 's' (last character)

9, Try to match 's' to 's'
Match! Advance both: Pattern and text both at end

10, Pattern and Text fully matched → successful match!

What did '*' match?
'*' matched the substring "ts" (characters 2 and 3 in the text "ststs").


Matching split looks like:
's' matched the first 's'
'*' matched "ts"
't' matched the second 't' (fifth character)
's' matched the last 's'

Why backtracking?
Initially, the '*' tried to match zero characters (empty), but that led to a mismatch later (text was longer than pattern).
Backtracking let '*' expand its match to "t" and then "ts" until the entire pattern matched the text. 
*/

int match_pattern(const char *pattern, const char *text) {
    const char *p = pattern;
    const char *t = text;
    const char *star_pattern = NULL;
    const char *star_text = NULL;
    
    while (*t) {
        if (*p == '*') {
            // Found wildcard, save positions
            star_pattern = ++p;
            star_text = t;
        } else if (*p == '?' || *p == *t) {
            // Character match or single wildcard
            p++;
            t++;
        } else if (star_pattern) {
            // No match, but we have a previous *, backtrack
            p = star_pattern;
            t = ++star_text;
        } else {
            // No match and no previous *
            return 0;
        }
    }
    
    // Skip any trailing * in pattern
    while (*p == '*') {
        p++;
    }
    
    // Pattern matches if we've consumed all of it
    return *p == '\0';
}

// Function to search symbols by pattern
void search_symbols(const char *pattern) {
    if (!pattern || strlen(pattern) == 0) {
        printf("Usage: s <pattern>\n");
        printf("Examples: s print*, s *lcd*, s init_?\n");
        return;
    }
    
    SymbolEntry *current = symbol_list;
    int match_count = 0;
    
    printf("Symbols matching pattern '%s':\n", pattern);
    
    while (current != NULL) {
        if (match_pattern(pattern, current->symbol_name)) {
            printf("  %04X  %s\n", current->address, current->symbol_name);
            match_count++;
        }
        current = current->next;
    }
    
    if (match_count == 0) {
        printf("  No symbols found matching pattern '%s'\n", pattern);
    } else {
        printf("Found %d matching symbol(s)\n", match_count);
    }
}

// Function to handle symbol search command
void handle_symbol_search_command(const char *input) {
    // Skip 's' and whitespace
    const char *ptr = input + 1;
    while (*ptr == ' ' || *ptr == '\t') ptr++;
    
    if (strlen(ptr) == 0) {
        printf("Usage: s <pattern>\n");
        printf("Wildcards: * (any sequence), ? (single char)\n");
        printf("Examples:\n");
        printf("  s print*     - symbols starting with 'print'\n");
        printf("  s *lcd*      - symbols containing 'lcd'\n");
        printf("  s init_?     - symbols like 'init_a', 'init_1', etc.\n");
        printf("  s main       - exact match for 'main'\n");
        return;
    }
    
    search_symbols(ptr);
}

void handle_keyboard_event(SDL_Event *event, LCDSim *lcd, SDL_Window *window, long int loop_cnt) {
    char input = 0;
    SDL_Keycode key = event->key.keysym.sym;

    if (key >= SDLK_SPACE && key <= SDLK_z) input = key;
    else if (key == SDLK_RETURN) input = '\r';
    else if (key == SDLK_BACKSPACE) input = '\b';
    //
    // TODO: attemp to pass arrow up/down to 6502
    //       for now, use [ and ] for scroll up and down
    // else if (key == SDLK_UP) input = key;
    // else if (key == SDLK_DOWN) input = key;

    if (!input) return;

    printf("key pressed: %04X  at loop_cnt %04ld\n", input, loop_cnt);

    write6502(KEY_INPUT, input); // put it to keyboard buffer

    LCDSim_Draw(lcd);
    SDL_UpdateWindowSurface(window);
}


void handle_sigint(int sig) {
    (void)sig; // unused
    quit_flag = 1;
}


// Manual implementation of strdup()
char* my_strdup(const char* s) {
    if (s == NULL) return NULL;
    size_t len = strlen(s) + 1; // +1 for the null terminator
    char* new_str = malloc(len);
    if (new_str == NULL) {
        return NULL;
    }
    return memcpy(new_str, s, len);
}

// --- Function to Create and Populate the symbol_list ---
SymbolEntry* create_symbol_dictionary(const char* filepath) {
    FILE *file = fopen(filepath, "r");
    if (!file) {
        perror("Failed to open list file");
        return NULL;
    }

    SymbolEntry *head = NULL;
    char line[256];
    char name_buffer[100];
    char type_char;
    unsigned int address;

    // Skip header lines
    // The format seems to start after "Symbols by name:"
    while (fgets(line, sizeof(line), file)) {
        if (strstr(line, "Symbols by name:")) {
            break;
        }
    }

    printf("create_symbol_dictionary: started"  );


    // Read and parse symbol entries
    while (fgets(line, sizeof(line), file)) {

        // Use sscanf to parse the symbol name, type, and address
        // The format specifier handles spaces between the symbol name and the type.
        // It also handles a colon and a hex value.
        int result = sscanf(line, "%s %c:%x", name_buffer, &type_char, &address);

        if (result == 3) {
            // Found a valid symbol entry
            SymbolEntry *new_entry = malloc(sizeof(SymbolEntry));
            if (!new_entry) {
                perror("Memory allocation failed");
                fclose(file);
                return head; // Return what we have so far
            }

            // Copy the symbol name
            //new_entry->symbol_name = strdup(name_buffer);
            new_entry->symbol_name = my_strdup(name_buffer);
            if (!new_entry->symbol_name) {
                perror("Memory allocation failed for symbol name");
                free(new_entry);
                fclose(file);
                return head;
            }

            new_entry->address = address;
            
            //printf("create_symbol_dictionary: %s  %x", new_entry->symbol_name, new_entry->address);

            // Add the new entry to the front of the list
            new_entry->next = head;
            head = new_entry;
        }
    }

    fclose(file);
    return head;
}

// --- Function to Free the symbol_list ---
void free_dictionary(SymbolEntry* head) {
    SymbolEntry *current = head;
    while (current) {
        SymbolEntry *temp = current;
        free(current->symbol_name); // Free the string
        current = current->next;
        free(temp); // Free the struct
    }
}



// Function to find monitor address index (-1 if not found)
int find_monitor_address(unsigned int address) {
    for (int i = 0; i < monitor_count; i++) {
        if (monitor_addresses[i].address == address) {
            return i;
        }
    }
    return -1;
}

// Function to add monitor address
void add_monitor_address(unsigned int address, int size) {
    if (monitor_count >= MAX_MONITOR_ADDRESSES) {
        printf("Maximum monitor addresses reached (%d)!\n", MAX_MONITOR_ADDRESSES);
        return;
    }
    
    monitor_addresses[monitor_count].address = address;
    monitor_addresses[monitor_count].size = size;
    monitor_count++;
    
    printf("Added monitor: %04X (%d bytes)\n", address, size);
}

// Function to remove monitor address
void remove_monitor_address(unsigned int address) {
    int index = find_monitor_address(address);
    if (index == -1) {
        printf("Address %04X not found in monitor list\n", address);
        return;
    }
    
    // Shift remaining addresses down
    for (int i = index; i < monitor_count - 1; i++) {
        monitor_addresses[i] = monitor_addresses[i + 1];
    }
    monitor_count--;
    
    printf("Removed monitor: %04X\n", address);
}



// Function to handle memory monitor command
void handle_memory_monitor_command(const char *input) {
    unsigned int address;
    int size = 4; // default size
    
    // Skip 'm' and whitespace
    const char *ptr = input + 1;
    while (*ptr == ' ' || *ptr == '\t') ptr++;
    
    if (strlen(ptr) == 0) {
        // Just 'm' - print all monitored addresses
        print_monitor_addresses();
        return;
    }
    
    // Parse input: "m 0200" or "m 0200 16"
    int parsed = sscanf(ptr, "%x %d", &address, &size);
    if (parsed < 1) {
        printf("Usage: m [address] [size]\n");
        printf("Examples:\n");
        printf("  m           - show all monitored addresses\n");
        printf("  m 0200      - toggle monitoring of address 0200 (4 bytes default)\n");
        printf("  m 0200 16   - toggle monitoring of address 0200 (16 bytes)\n");
        return;
    }
    
    // If only address specified, use default size
    if (parsed == 1) {
        size = 4;
    }
    
    // Check if address is already being monitored
    int existing_index = find_monitor_address(address);
    if (existing_index != -1) {
        // Address exists, remove it
        remove_monitor_address(address);
    } else {
        // Address doesn't exist, add it
        add_monitor_address(address, size);
    }
}

int run_emulator_loop(LCDSim *lcd, SDL_Window *window, uint16_t irq_interval, int duration_seconds) {
    uint8_t opcode, op1, op2;
    long int loop_cnt = 0;
    unsigned int last_irq = 0, total_cycles = 0;
    int irq_count = 0;
    int row = 1, col = 0;
    int break_loop = 0;
    SDL_Event event;

    time_t start_time = time(NULL);

    int step_enabled = 0;
    char input_buffer[60];
    uint8_t opcode_decoded;

    while (!break_loop && !quit_flag) {
    // while (time(NULL) - start_time < duration_seconds && !break_loop && !quit_flag) {
        
        // Check for breakpoints (including original and new ones)
        //if (pc == break_address || is_breakpoint(pc)) {
        if (is_breakpoint(pc)) {
            step_enabled = 1;
        }
        
        if (step_enabled) {
            duration_seconds = INT_MAX;
            //printf("DEBUG [%04X]: ", pc);
            
            // Display current instruction
            disassemble_current_instruction(stdout, pc, RAM, false);
            
            printf("\nDEBUG> ");
            
            if (fgets(input_buffer, sizeof(input_buffer), stdin) == NULL) {
                break;
            }
            
            // Remove newline
            input_buffer[strcspn(input_buffer, "\n")] = 0;
            
            // https://claude.ai/public/artifacts/6c8eb142-6502-40ab-b77a-705c9245dd59
            if (strlen(input_buffer) == 0) {
                // Enter pressed - step one instruction
                // Continue to execute one instruction
            } else if (input_buffer[0] == 'h') {
                print_gdb_help();
                continue;
            } else if (input_buffer[0] == 'c') {
                step_enabled = 0;
                printf("Continuing execution...\n");
            } else if (input_buffer[0] == 'r') {
                handle_read_command(input_buffer);
                continue; // Don't execute instruction, stay in debug mode
            } else if (input_buffer[0] == 'w') {
                handle_write_command(input_buffer);
                continue; // Don't execute instruction, stay in debug mode
            } else if (input_buffer[0] == 'u') {
                handle_up_command();
                step_enabled = 0; // Continue until return
            } else if (input_buffer[0] == 't') {
                print_call_stack();
                continue; // Don't execute instruction, stay in debug mode
            } else if (input_buffer[0] == 'b') {
                handle_breakpoint_command(input_buffer);
                continue; // Don't execute instruction, stay in debug mode
            } else if (input_buffer[0] == 's') {
                handle_symbol_search_command(input_buffer);
                continue; // Don't execute instruction, stay in debug mode
            } else if (input_buffer[0] == 'm') {
                handle_memory_monitor_command(input_buffer);
                continue; // Don't execute instruction, stay in debug mode
            } else {
                printf("Unknown command. Available: enter, c, r, w, u, t, b, s\n");
                continue; // Don't execute instruction, stay in debug mode
            }
        }
        
        // SDL_PollEvent removes one event: Each call to SDL_PollEvent(&event) does two things:
        // It checks if there's an event at the front of the queue.
        // If there is, it copies that event's data into the event structure you provide AND removes that event from the queue.
        // It returns 1 if an event was processed and 0 if the queue was empty.

        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) { break_loop = 1; break; }
            else if (event.type == SDL_KEYDOWN) {
                handle_keyboard_event(&event, lcd, window, loop_cnt);
            }
        }

        if (step_enabled) disassemble_current_instruction(stdout, pc, RAM, false);
        opcode_decoded = disassemble_current_instruction(log_file, pc, RAM, false);
        if(opcode_decoded == magic_opcde) {
            fprintf(log_file, "INFO: magic opcode 0xFF detected, terminate the simulation\n");
            fprintf(log_file, "INFO: this means the code jumps to pc where opcode is 0x00 BRK and executes \n");

            break; // break the while loop
        } else if(opcode_decoded == JSR) {
            unsigned int target_address = pc; // RAM[(pc + 1) & 0xFFFF] | (RAM[(pc + 2) & 0xFFFF] << 8);
            push_subroutine_call(target_address);
        } else if(opcode_decoded == RTS) {
            pop_subroutine_call();
        }


        exec6502(1);
        total_cycles += clockticks6502;

        if (step_enabled) print_cpu_state_to_stream(stdout);
        print_cpu_state_to_stream(log_file);

        if (total_cycles - last_irq >= irq_interval) {
            fprintf(stdout, "Triggering IRQ at %u cycles\n", total_cycles);
            irq6502();
            last_irq = total_cycles;
            irq_count++;
        }

        usleep(10);
        loop_cnt++;
    }

    fprintf(log_file, "--- Simulation Finished ---\n");
    dump_memory_range(log_file, 0xBB00, 0xCFFF);
    print_cpu_state_to_stream(stdout);
    fprintf(log_file, "Total Cycles: %u | IRQs: %d | $02 = %02X\n", total_cycles, irq_count, RAM[0x02]);
    fclose(log_file);

    return 0;

}


// --- Function to handle symbol list creation and breakpoint lookup ---
int handle_symbol_lookup(const char* list_file_path, const char* break_symbol_name) {
    if (list_file_path == NULL) {
        // No list file was specified, so no symbols can be loaded.
        // This is not an error if a breakpoint wasn't requested.
        return 0; 
    }

    // Create the symbol_list from the list file
    symbol_list = create_symbol_dictionary(list_file_path);

    if (!symbol_list) {
        fprintf(stderr, "Error: Could not create symbol dictionary from file: %s\n", list_file_path);
        return -1; // Indicate failure
    }

    // --- Example of searching for a symbol ---
    SymbolEntry *current = symbol_list;
    //while (current) {
    //    printf("Symbol: %-25s Address: 0x%04X\n", current->symbol_name, current->address);
    //    current = current->next;
    // }

    if (break_symbol_name) {
        current = symbol_list;
        int found = 0;
        while (current) {
            if (strcmp(current->symbol_name, break_symbol_name) == 0) {
                printf("Found breakpoint symbol '%s' at address 0x%04X\n", break_symbol_name, current->address);
                found = 1;
                add_breakpoint(current->address, break_symbol_name);
                break;
            }
            current = current->next;
        }

        if (!found) {
            printf("Symbol '%s' not found.\n", break_symbol_name);
        } else {
            printf("Symbol '%s' found and breakpoint added.\n", break_symbol_name);
        }
    }

    return 0; // Indicate success
}


// --- Main Function ---
int main(int argc, char *argv[]) {
    int opt; // To store the return value of getopt_long

    // Define the long options
    static struct option long_options[] = {
        {"hex",           required_argument, 0, 'h'}, // 'h' is the short option equivalent value
        {"list",          required_argument, 0, 'l'}, // 'l' is the short option equivalent value
        {"break_symbol",  required_argument, 0, 'b'}, // 'b' is the short option equivalent value
        {0, 0, 0, 0} // Sentinel to mark the end of the array
    };

    int long_index = 0; // To store the index of the long option found

    // Loop through command-line arguments using getopt_long
    // ":" after a short option means it requires an argument.
    // We're using 'h', 'l', 'b' as the return values for the long options.
    while ((opt = getopt_long(argc, argv, "h:l:b:", long_options, &long_index)) != -1) {
        switch (opt) {
            case 'h': // Corresponds to --hex
                hex_file_path = optarg;
                printf("Hex file specified: %s\n", hex_file_path);
                break;
            case 'l': // Corresponds to --list
                list_file_path = optarg;
                printf("List file specified: %s\n", list_file_path);
                break;
            case 'b': // Corresponds to --break_symbol
                break_symbol_name = optarg;
                printf("Break symbol specified: %s\n", break_symbol_name);
                //add_breakpoint(return_addr, "up command breakpoint");
                break;
            case '?': // getopt_long returns '?' for an unknown option
                fprintf(stderr, "Unknown option or missing argument.\n");
                // getopt_long already prints an error message.
                return EXIT_FAILURE;
            default:
                // This case should ideally not be reached
                fprintf(stderr, "Error parsing arguments.\n");
                return EXIT_FAILURE;
        }
    }

    // --- Validate parsed arguments ---
    if (hex_file_path == NULL) {
        fprintf(stderr, "Error: --hex <hex_file_path> is required.\n");
        fprintf(stderr, "Usage: %s --hex <hex_file> [--list <list_file>] [--break_symbol <symbol>]\n", argv[0]);
        return EXIT_FAILURE;
    }

    // Call the new function to handle symbol-related logic
    if (handle_symbol_lookup(list_file_path, break_symbol_name) != 0) {
        return EXIT_FAILURE;
    }

    // const char *hex_file_path = argv[1];
    uint16_t program_start_address = 0x8000;
    uint16_t irq_handler_address = 0x0700;

#ifdef MAX_IRQ_INTERVAL
    unsigned int irq_cycle_interval = UINT_MAX;
#else
    unsigned int irq_cycle_interval = 1000;
#endif



    if (!initialize_sdl_and_lcd(&window, &screen, &lcd)) return EXIT_FAILURE;

    if (!load_program_and_irq(hex_file_path, program_start_address, irq_handler_address)) return EXIT_FAILURE;
        
    
    //usleep(100000);


    set_vectors(program_start_address, irq_handler_address);
    reset6502();
    signal(SIGINT, handle_sigint); // capture ctrl-c

    run_emulator_loop(lcd, window, irq_cycle_interval, SIM_TIME_SECONDS);

    SDL_DestroyWindow(window);
    SDL_Quit();
    return EXIT_SUCCESS;
}

