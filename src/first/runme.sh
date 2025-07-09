# step 1
rm a.out
rm a.out.hex
rm interrupt.gemini

# ~/vasm/vasm6502_oldstyle -Fbin -dotdir ./first.s
$BEN_HOME/tools/vasm/vasm6502_oldstyle -Fbin -dotdir ./first.s
ls -al a.out
echo ""
hexdump -C a.out
# hexdump -v -e '"%07.7_ax: " 8/2 "%04x " "\n"' a.out > a.out.hex
hexdump -v -e '"%07.7_ax: " 8/1 "%02x " "\n"' a.out > a.out.hex

# step 2
cc -std=c99 -Os $BEN_HOME/tools/fake6502_simulator/simulator.c -DMAX_IRQ_INTERVAL -o sim -I$BEN_HOME/tools/fake6502/MyLittle6502 && ./sim ./a.out.hex
