~/vasm/vasm6502_oldstyle -Fbin -dotdir first.s
echo ""
hexdump -C a.out
# hexdump -v -e '"%07.7_ax: " 8/2 "%04x " "\n"' a.out > a.out.hex
hexdump -v -e '"%07.7_ax: " 8/1 "%02x " "\n"' a.out > a.out.hex
