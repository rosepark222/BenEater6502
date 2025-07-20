.PHONY: all clean

all: example

example: example.c
	gcc example.c $(BEN_HOME)/tools/LCDSim/lcdsim.c -I$(BEN_HOME)/tools/LCDSim -o example `sdl2-config --cflags --libs`

clean:
	rm -rf example

