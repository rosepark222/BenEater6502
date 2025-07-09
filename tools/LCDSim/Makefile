.PHONY: all

all: example

example: example.c lcdsim.c
	gcc example.c lcdsim.c -o example `sdl2-config --cflags --libs`

clean:
	rm -rf example
