// test_sdl.c
#include <SDL.h>

int main() {
    SDL_Init(SDL_INIT_VIDEO);
    SDL_Window *win = SDL_CreateWindow("SDL2 Test", 100, 100, 640, 480, SDL_WINDOW_SHOWN);
    SDL_Delay(2000); // show window for 2 seconds
    SDL_Quit();
    return 0;
}