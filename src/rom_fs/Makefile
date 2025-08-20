.PHONY: all clean

all: sim a.out.hex
	./sim -h ./a.out.hex -l ./listFile -b  summer_break

sim: $(BEN_HOME)/tools/benEater_simulator/simulator.c
	cc -std=c99 -g -Os $(BEN_HOME)/tools/benEater_simulator/simulator.c $(BEN_HOME)/tools/LCDSim/lcdsim.c -I$(BEN_HOME)/tools/LCDSim  -DMAX_IRQ_INTERVAL -I$(BEN_HOME)/tools/fake6502/MyLittle6502 -o sim `sdl2-config --cflags --libs`
	# cc -std=c99 -Os example.c $(BEN_HOME)/tools/LCDSim/lcdsim.c -I$(BEN_HOME)/tools/LCDSim -o example `sdl2-config --cflags --libs`
a.out.hex: a.out
	hexdump -v -e '"%07.7_ax: " 8/1 "%02x " "\n"' a.out > a.out.hex.raw
	python3 $(BEN_HOME)/bin/addr_shifter.py a.out.hex.raw > a.out.hex
	# $(BEN_HOME)/tools/dcc6502/dcc6502 -o 0x8000 -d -c -n a.out > a.out.dis

a.out: test.s
	$(BEN_HOME)/tools/vasm/vasm6502_oldstyle -L ./listFile -Fbin -dotdir ./test.s
	ls -al a.out
	hexdump -C a.out

clean:
	rm -f a.out* sim trace.log listFile
