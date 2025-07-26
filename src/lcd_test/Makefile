.PHONY: all clean

all: example

example: example.c
	cc -std=c99 -Os example.c $(BEN_HOME)/tools/LCDSim/lcdsim.c -I$(BEN_HOME)/tools/LCDSim -o example `sdl2-config --cflags --libs` -lm
	# cc -std=c99 -Os example.c /home/rosep/BenEater6502/tools/LCDSim/lcdsim.c -I/home/rosep/BenEater6502/tools/LCDSim -o example `sdl2-config --cflags --libs` -lm
clean:
	rm -rf example

