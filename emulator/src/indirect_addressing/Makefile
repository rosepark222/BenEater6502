.PHONY: all clean

all: sim a.out.hex
	./sim ./a.out.hex

sim: ../../fake6502_simulator/simulator.c
	cc -std=c99 -Os ../../fake6502_simulator/simulator.c -DMAX_IRQ_INTERVAL -I../../../fake6502/MyLittle6502 -o sim

a.out.hex: a.out
	hexdump -v -e '"%07.7_ax: " 8/1 "%02x " "\n"' a.out > a.out.hex

a.out: test.s
	../../../vasm/vasm6502_oldstyle -Fbin -dotdir ./test.s
	ls -al a.out
	hexdump -C a.out

clean:
	rm -f a.out a.out.hex sim trace.log
