#../vasm/vasm6502_oldstyle -Fbin -dotdir first.s
#
#
#echo ""
#hexdump -c a.out
#hexdump -v -e '"%07.7_ax: " 8/2 "%04x " "\n"' a.out > a.out.hex
#hexdump -v -e '"%07.7_ax: " 8/1 "%02x " "\n"' a.out > a.out.hex

# ../../tools/vasm/vasm6502_oldstyle -L ./listFile -Fbin -dotdir ./LEDtoggle.s
# ../../tools/vasm/vasm6502_oldstyle -L ./listFile -Fbin -dotdir ./simplest.s
 ../../tools/vasm/vasm6502_oldstyle -L ./listFile -Fbin -dotdir ./blink5irq2.s

 ls -al a.out
 hexdump -C a.out
