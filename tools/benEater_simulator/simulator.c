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

volatile sig_atomic_t quit_flag = 0;
#define SIM_TIME_SECONDS 40

#define magic_opcde 0xFF
#define KEY_INPUT 0x0300
#define PRINT_CHAR_ADDR 0x6000
// --- Emulated 6502 Memory (64KB) ---
// This array represents the 6502's 64KB address space.
uint8_t RAM[65536];

LCDSim *lcd = NULL;
SDL_Window *window = NULL;
SDL_Surface *screen = NULL;

// --- External CPU state variables (from fake6502.h) ---
// These are declared in fake6502.h and updated by the emulator core.
extern unsigned char   a, x, y, sp, status;
extern unsigned short  pc;
extern unsigned int    clockticks6502; // Total emulated CPU cycles (from fake6502 core)

// --- Memory Access Functions for fake6502 ---
// These are the functions fake6502 calls to read from and write to memory.
// We implement them to access our global RAM array.
uint8_t read6502(uint16_t address) {
    return RAM[address];
}

void write6502(uint16_t address, uint8_t value) {

    // In a true hardware system, memory-mapped devices (LCD, sound, etc.) “see” all writes to specific addresses, regardless of what instruction triggers those writes (STA, STX, etc). They don’t care about “what’s in RAM[pc] right now.”
    // By only checking for STA $6000 (opcode==0x8D, op1==0x00, op2==0x60), you miss all other ways the code could write to 0x6000, such as STX, STY, indirect addressing, and even self-modifying code or DMA.

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

// --- Helper to print CPU state to a specified stream ---
void print_cpu_state_to_stream(FILE *stream) {
    // Note: status register bits are: N V - B D I Z C
    fprintf(stream, "CPU State: PC:%04X A:%02X X:%02X Y:%02X SP:%02X Status:%02X (NV-B DIZC)\n",
           pc, a, x, y, sp, status);
    fprintf(stream, "RAM State: $0000:%02X $0001:%02X $0002:%02X $0003:%02X\n", RAM[0x0000], RAM[0x0001], RAM[0x0002], RAM[0x0003]);
    fprintf(stream, "RAM State: $6000:%02X $6001:%02X $0230:%02X $0231:%02X\n", RAM[0x6000], RAM[0x6001], RAM[0x0230], RAM[0x0231]);
    // fprintf(stream, "RAM State: $0006:%02X $0007:%02X $0008:%02X $0009:%02X\n", RAM[0x0006], RAM[0x0007], RAM[0x0008], RAM[0x0009]);
    // fprintf(stream, "RAM State: $0200:%02X $0201:%02X $0202:%02X $0203:%02X\n", RAM[0x0200], RAM[0x0201], RAM[0x0202], RAM[0x0203]);
    fprintf(stream, "RAM State: $0300:%02X $0301:%02X $0302:%02X $0303:%02X\n", RAM[0x0300], RAM[0x0301], RAM[0x0302], RAM[0x0303]);
    // fprintf(stream, "RAM State: $C000:%02X $C001:%02X $C002:%02X $C003:%02X\n", RAM[0xC000], RAM[0xC001], RAM[0xC002], RAM[0xC003]);
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

// Global file pointer for logging
FILE *log_file = NULL;

 
/**
 * @brief Disassembles and prints the 6502 instruction at the given PC to a stream.
 * @param stream The file stream to print to (e.g., stdout or log_file).
 * @param current_pc The current Program Counter of the 6502.
 * @param ram Pointer to the emulated RAM.
 */
int disassemble_current_instruction(FILE *stream, uint16_t current_pc, const uint8_t *ram, bool kill_on_FF) {
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

    if(opcode == magic_opcde && kill_on_FF) {
        fprintf(stream, "INFO: magic opcode 0xFF detected, terminate the simulation\n");
        fprintf(stream, "INFO: this means the code jumps to pc where opcode is 0x00 BRK and executes \n");

        return 1;
    }
    return 0;
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
// --- LCD Cursor Tracking (New Global/Static Variables) ---
static int lcd_current_row = 0; // LCD has 2 rows (0 and 1)
static int lcd_current_col = 0; // LCD has 16 columns (0-15)
#define MAX_LCD_COLUMNS 16
#define MAX_LCD_ROWS 2

 



// === Helper Functions ===

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

void run_emulator_loop(LCDSim *lcd, SDL_Window *window, uint16_t irq_interval, int duration_seconds) {
    uint8_t opcode, op1, op2;
    unsigned int last_irq = 0, total_cycles = 0;
    int irq_count = 0;
    int row = 1, col = 0;
    int break_loop = 0;
    SDL_Event event;

    time_t start_time = time(NULL);

    while (time(NULL) - start_time < duration_seconds && !break_loop && !quit_flag) {
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) { break_loop = 1; break; }
            else if (event.type == SDL_KEYDOWN) {
                handle_keyboard_event(&event, lcd, window);
            }
        }

        //disassemble_current_instruction(stdout, pc, RAM, false);
        break_loop = disassemble_current_instruction(log_file, pc, RAM, false);




        exec6502(1);
        total_cycles += clockticks6502;

        // print_cpu_state_to_stream(stdout);
        print_cpu_state_to_stream(log_file);

        if (total_cycles - last_irq >= irq_interval) {
            fprintf(stdout, "Triggering IRQ at %u cycles\n", total_cycles);
            irq6502();
            last_irq = total_cycles;
            irq_count++;
        }

        usleep(10);
    }

    fprintf(log_file, "--- Simulation Finished ---\n");
    dump_memory_range(log_file, 0xBB00, 0xCFFF);
    print_cpu_state_to_stream(stdout);
    fprintf(log_file, "Total Cycles: %u | IRQs: %d | $02 = %02X\n", total_cycles, irq_count, RAM[0x02]);
    fclose(log_file);


}

void handle_keyboard_event(SDL_Event *event, LCDSim *lcd, SDL_Window *window) {
    char input = 0;
    SDL_Keycode key = event->key.keysym.sym;

    if (key >= SDLK_SPACE && key <= SDLK_z) input = key;
    else if (key == SDLK_RETURN) input = '\r';
    else if (key == SDLK_BACKSPACE) input = '\b';

    if (!input) return;

    printf("key pressed: %04X\n", input);

    write6502(KEY_INPUT, input); // put it to keyboard buffer

    // if (input == '\b') {
    //     if (lcd_current_col > 0) {
    //         lcd_current_col--;
    //         LCD_SetCursor(lcd, lcd_current_row, lcd_current_col);
    //         LCD_PutChar(lcd, ' ');

    //     }
    // } else if (input == '\r') {
    //     lcd_current_col = 0;
    //     lcd_current_row = (lcd_current_row + 1) % MAX_LCD_ROWS;
    //     LCD_SetCursor(lcd, lcd_current_row, lcd_current_col);
    //     LCD_ClearLine(lcd, lcd_current_row);
    // } else {
    //     LCD_SetCursor(lcd, lcd_current_row, lcd_current_col);
    //     LCD_PutChar(lcd, input);
    //     lcd_current_col++;
    //     if (lcd_current_col >= MAX_LCD_COLUMNS) {
    //         lcd_current_col = 0;
    //         lcd_current_row = (lcd_current_row + 1) % MAX_LCD_ROWS;
    //         LCD_SetCursor(lcd, lcd_current_row, lcd_current_col);
    //         LCD_ClearLine(lcd, lcd_current_row);
    //     }
    // }

    LCDSim_Draw(lcd);
    SDL_UpdateWindowSurface(window);
}

void handle_sigint(int sig) {
    (void)sig; // unused
    quit_flag = 1;
}



// === Main Function ===
int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <hex_file_path>\n", argv[0]);
        return EXIT_FAILURE;
    }

    const char *hex_filename = argv[1];
    uint16_t program_start_address = 0x8000;
    uint16_t irq_handler_address = 0x0700;

#ifdef MAX_IRQ_INTERVAL
    unsigned int irq_cycle_interval = UINT_MAX;
#else
    unsigned int irq_cycle_interval = 1000;
#endif



    if (!initialize_sdl_and_lcd(&window, &screen, &lcd)) return EXIT_FAILURE;

    if (!load_program_and_irq(hex_filename, program_start_address, irq_handler_address)) return EXIT_FAILURE;
        
    
    //usleep(100000);


    set_vectors(program_start_address, irq_handler_address);
    reset6502();
    signal(SIGINT, handle_sigint); // capture ctrl-c

    run_emulator_loop(lcd, window, irq_cycle_interval, SIM_TIME_SECONDS);

    SDL_DestroyWindow(window);
    SDL_Quit();
    return EXIT_SUCCESS;
}