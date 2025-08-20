#!/usr/bin/env python3

import sys

if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} <a.out.hex>", file=sys.stderr)
    sys.exit(1)

input_file_path = sys.argv[1]

try:
    with open(input_file_path, 'r') as f:
        for line in f:
            line = line.strip()
            # Check if the line starts with a hexadecimal address
            if ':' in line and line.split(':')[0].isalnum():
                parts = line.split(':', 1)
                try:
                    # Convert the hex address to an integer
                    orig_addr = int(parts[0], 16)
                    # Add 0x8000 to the address
                    new_addr = orig_addr + 0x8000
                    # Print the new address in 7-digit hex format
                    print(f"{new_addr:07x}: {parts[1].strip()}")
                except ValueError:
                    # If conversion fails, print the original line
                    print(line)
            else:
                # If the line doesn't match the pattern, print it as is
                print(line)
except FileNotFoundError:
    print(f"Error: File not found at {input_file_path}", file=sys.stderr)
    sys.exit(1)

