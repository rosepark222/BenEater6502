#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>    // For clock() and CLOCKS_PER_SEC (though less critical now)
#include <unistd.h>  // For usleep() on Linux/WSL for real-time pacing
#include <ctype.h>   // For isxdigit(), isspace()
#include <limits.h>  // Make sure to include this header for UINT_MAX
#include <stdbool.h>

// Include the fake6502 emulator core
#include "fake6502.h"

#define magic_opcde 0xFF
// --- Emulated 6502 Memory (64KB) ---
// This array represents the 6502's 64KB address space.
uint8_t RAM[65536];

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
    RAM[address] = value;
}

// --- Helper to print CPU state to a specified stream ---
void print_cpu_state_to_stream(FILE *stream) {
    // Note: status register bits are: N V - B D I Z C
    fprintf(stream, "CPU State: PC:%04X A:%02X X:%02X Y:%02X SP:%02X Status:%02X (NV-B DIZC)\n",
           pc, a, x, y, sp, status);
    fprintf(stream, "RAM State: $0006:%02X $0007:%02X $0008:%02X\n", RAM[0x0006], RAM[0x0007], RAM[0x0008]);
    fprintf(stream, "RAM State: $0200:%02X $0201:%02X $0202:%02X\n", RAM[0x0200], RAM[0x0201], RAM[0x0202]);
    fprintf(stream, "RAM State: $C000:%02X $C001:%02X $C002:%02X\n", RAM[0xC000], RAM[0xC001], RAM[0xC002]);
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

int main(int argc, char *argv[]) { // Modified main function signature
    // --- Program Parameters ---
    // Start address for our main 6502 program
    uint16_t program_start_address = 0x8000;
    // Name of the hex file to load - now taken from command line
    const char *hex_filename; // Declare it, but don't hardcode
    int break_loop = 0;

    // Check if enough arguments are provided
    if (argc < 2) { // argc[0] is the program name, argc[1] would be the first argument
        fprintf(stderr, "Usage: %s <hex_file_path>\n", argv[0]);
        return 1; // Indicate an error
    }

    // Assign the first command-line argument to hex_filename
    hex_filename = argv[1];

    printf("Loading %s into 6502 memory at 0x%04X...\n", hex_filename, program_start_address);

    // Start address for our 6502 IRQ handler
    uint16_t irq_handler_address = 0x0700;
    // Number of emulated cycles to run per C loop iteration
    // Remains at 1 to print CPU state for every instruction step.
    int cycles_per_loop_iteration = 1; 
    // Total real-time duration to run the simulation (e.g., 10 seconds)
    int simulation_duration_seconds = 10; 

 
#ifdef MAX_IRQ_INTERVAL
    unsigned int IRQ_6502_CYCLE_INTERVAL = UINT_MAX;
#else
    unsigned int IRQ_6502_CYCLE_INTERVAL = 1000; // 3 second run gives 6 IRQs 
#endif
    // --- 6502 IRQ Handler Bytes ---
    // This is the machine code for our IRQ handler.
    // IRQ_Handler:
    //   PHA        ; 0x48 - Push A to stack
    //   INC $02    ; 0xE6 02 - Increment Zero Page address $02 (our IRQ counter)
    //   PLA        ; 0x68 - Pull A from stack
    //   RTI        ; 0x40 - Return from Interrupt
    uint8_t irq_handler_bytes[] = {
        0x48,             // PHA
        0xE6, 0x02,       // INC $02
        0x68,             // PLA
        magic_opcde,             // Unknown magic opcode
        0x40              // RTI
    };

    // --- Open Log File ---
    log_file = fopen("trace.log", "w");
    if (!log_file) {
        perror("Error opening trace.log");
        return EXIT_FAILURE;
    }
    printf("Logging output to trace.log and console.\n");
    fprintf(log_file, "--- 6502 Emulation Trace Log ---\n\n");


    // --- 1. Initialize Emulated RAM ---
    memset(RAM, 0, sizeof(RAM));
    printf("Initialized 64KB RAM to zeros.\n");
    fprintf(log_file, "Initialized 64KB RAM to zeros.\n");

    // --- 2. Load Programs into RAM ---
    // Load main program from hex file
    long loaded_bytes = load_hex_file(hex_filename, program_start_address, sizeof(RAM) - program_start_address);
    if (loaded_bytes == -1) {
        fprintf(stderr, "Failed to load hex file. Exiting.\n");
        fprintf(log_file, "Failed to load hex file. Exiting.\n");
        fclose(log_file);
        return EXIT_FAILURE;
    }
    printf("Loaded main program (%ld bytes) from '%s' to 0x%04X.\n", loaded_bytes, hex_filename, program_start_address);
    fprintf(log_file, "Loaded main program (%ld bytes) from '%s' to 0x%04X.\n", loaded_bytes, hex_filename, program_start_address);


    // Load IRQ handler
    memcpy(&RAM[irq_handler_address], irq_handler_bytes, sizeof(irq_handler_bytes));
    printf("Loaded IRQ handler (%zu bytes) to 0x%04X.\n", sizeof(irq_handler_bytes), irq_handler_address);
    fprintf(log_file, "Loaded IRQ handler (%zu bytes) to 0x%04X.\n", sizeof(irq_handler_bytes), irq_handler_address);

    // --- 3. Set 6502 Vectors ---
    // Set the Reset Vector (0xFFFC/0xFFFD) to point to our main program start
    RAM[0xFFFC] = (uint8_t)(program_start_address & 0xFF);         // Low byte
    RAM[0xFFFD] = (uint8_t)((program_start_address >> 8) & 0xFF); // High byte
    printf("Set Reset Vector (0xFFFC/D) to 0x%04X.\n", program_start_address);
    fprintf(log_file, "Set Reset Vector (0xFFFC/D) to 0x%04X.\n", program_start_address);

    // Set the IRQ/BRK Vector (0xFFFE/0xFFFF) to point to our IRQ handler
    RAM[0xFFFE] = (uint8_t)(irq_handler_address & 0xFF);           // Low byte
    RAM[0xFFFF] = (uint8_t)((irq_handler_address >> 8) & 0xFF);   // High byte
    printf("Set IRQ/BRK Vector (0xFFFE/F) to 0x%04X.\n", irq_handler_address);
    fprintf(log_file, "Set IRQ/BRK Vector (0xFFFE/F) to 0x%04X.\n", irq_handler_address);

    // --- 4. Reset the 6502 CPU ---
    reset6502();
    printf("\nCPU Reset. Program Counter (PC) is now at 0x%04X (from Reset Vector).\n", pc);
    fprintf(log_file, "\nCPU Reset. Program Counter (PC) is now at 0x%04X (from Reset Vector).\n", pc);

    // --- 5. Main Simulation Loop ---
    unsigned int last_irq_trigger_cycle = 0; // Track IRQ trigger by emulated cycles
    unsigned int current_total_cycles = 0;   // Explicitly accumulated cycles
    int current_irq_count = 0; // Track IRQ count from our C program perspective

    printf("\n--- Starting 6502 Emulation with Cycle-Based IRQs ---\n");
    fprintf(log_file, "\n--- Starting 6502 Emulation with Cycle-Based IRQs ---\n");

    time_t start_real_time = time(NULL); // Still use real time to limit total simulation duration

    while (time(NULL) - start_real_time < simulation_duration_seconds) {
        // Print disassembly before execution
        disassemble_current_instruction(stdout, pc, RAM, false);
        break_loop = disassemble_current_instruction(log_file, pc, RAM, true);

        // Execute one 6502 instruction
        exec6502(cycles_per_loop_iteration); // This is now 1 cycle per call
        current_total_cycles += clockticks6502; // Update explicit accumulator

        // Print CPU state after every step
        print_cpu_state_to_stream(stdout);
        print_cpu_state_to_stream(log_file);
        
        // Timing variables for debugging IRQ firing (now cycle-based)
        fprintf(stdout, "Timing: Current Emulated Cycle: %u, Last IRQ Trigger Cycle: %u, Cycles Since Last IRQ: %u\n",
                current_total_cycles, last_irq_trigger_cycle, current_total_cycles - last_irq_trigger_cycle);
        fprintf(log_file, "Timing: Current Emulated Cycle: %u, Last IRQ Trigger Cycle: %u, Cycles Since Last IRQ: %u\n",
                current_total_cycles, last_irq_trigger_cycle, current_total_cycles - last_irq_trigger_cycle);

        printf("Emulated Cycles: %u\n\n", current_total_cycles);
        fprintf(log_file, "Emulated Cycles: %u\n\n", current_total_cycles);


        // Check emulated time for IRQ trigger
        if (current_total_cycles - last_irq_trigger_cycle >= IRQ_6502_CYCLE_INTERVAL) {
            printf("\n--- %u Emulated Cycles elapsed: Triggering IRQ! ---\n", IRQ_6502_CYCLE_INTERVAL);
            fprintf(log_file, "\n--- %u Emulated Cycles elapsed: Triggering IRQ! ---\n", IRQ_6502_CYCLE_INTERVAL);
            irq6502(); // Trigger the 6502 IRQ
            last_irq_trigger_cycle = current_total_cycles;
            current_irq_count++;
        }

        // Add a small sleep to prevent the loop from consuming 100% CPU on your host.
        // This makes the step-by-step output more readable.
        usleep(1000); // Sleep for 1 millisecond (1,000 microseconds)

        if (break_loop == 1) {
            printf("brek loop is: %u\n\n", break_loop);
            break;
        }
    }

    printf("\n--- Simulation Finished ---\n");
    dump_memory_range(log_file, 0xBB00, 0xCFFF);
    fprintf(log_file, "\n--- Simulation Finished ---\n");
    print_cpu_state_to_stream(stdout);
    print_cpu_state_to_stream(log_file);
    printf("Total Emulated Cycles: %u\n", current_total_cycles);
    fprintf(log_file, "Total Emulated Cycles: %u\n", current_total_cycles);
    printf("Total IRQs triggered (simulated cycles): %d\n", current_irq_count);
    fprintf(log_file, "Total IRQs triggered (simulated cycles): %d\n", current_irq_count);
    printf("Final Zero Page IRQ Counter ($02): %02X\n", RAM[0x02]);
    fprintf(log_file, "Final Zero Page IRQ Counter ($02): %02X\n", RAM[0x02]);

    // Close the log file
    fclose(log_file);

    return EXIT_SUCCESS;
}
