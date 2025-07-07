#!/bin/sh

INPUT="$1"

if [ -z "$INPUT" ]; then
  echo "Usage: $0 <a.out.hex>"
  exit 1
fi

awk '{
  # Match lines like: 0000300: xx xx ...
  if (match($0, /^([0-9a-fA-F]+):/, m)) {
    orig = "0x" m[1]
    new_addr = strtonum(orig) + 0x8000
    printf "%07x: ", new_addr
    sub(/^[0-9a-fA-F]+: /, "", $0)  # Remove old address
    print $0
  } else {
    print $0
  }
}' "$INPUT"

