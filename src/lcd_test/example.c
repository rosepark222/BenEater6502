// example.c, updated to use SDL_Surface
#include <SDL2/SDL.h>
#include <stdlib.h>
#include "lcdsim.h"
#include <math.h>

#define SAMPLE_RATE 44100
#define FREQUENCY 1840.0
#define AMPLITUDE 10000
#define M_PI 3.14159265358979323846

// Callback function to generate audio samples
void audio_callback(void* userdata, Uint8* stream, int len) {
    static double phase = 0.0;
    Sint16* buffer = (Sint16*)stream;
    int samples_to_generate = len / sizeof(Sint16);

    for (int i = 0; i < samples_to_generate; ++i) {
        // Generate a sine wave sample
        double sample = AMPLITUDE * sin(phase);
        buffer[i] = (Sint16)sample;

        // Update the phase for the next sample
        phase += 2.0 * M_PI * FREQUENCY / SAMPLE_RATE;
        if (phase >= 2.0 * M_PI) {
            phase -= 2.0 * M_PI;
        }
    }
}

int main(int argc, char* argv[]) {
    SDL_Init(SDL_INIT_AUDIO);

    SDL_AudioSpec desired;
    desired.freq = SAMPLE_RATE;
    desired.format = AUDIO_S16SYS;
    desired.channels = 1;
    desired.samples = 4096;
    desired.callback = audio_callback;
    desired.userdata = NULL;

    SDL_AudioDeviceID device = SDL_OpenAudioDevice(NULL, 0, &desired, NULL, 0);
    if (device == 0) {
        fprintf(stderr, "Failed to open audio device: %s\n", SDL_GetError());
        return 1;
    }

    // Unpause the audio device to start playback
    SDL_PauseAudioDevice(device, 0);

    printf("Playing 440 Hz sine wave for 5 seconds...\n");
    SDL_Delay(5000); // Wait for 5 seconds

    // Clean up
    SDL_CloseAudioDevice(device);
    SDL_Quit();

    printf("Done.\n");
    return 0;
}

/*typedef struct LCDSim LCDSim;

LCDSim* LCDSim_Create(SDL_Surface* screen, int x, int y);
void LCDSim_Draw(LCDSim* lcd);
void LCD_State(LCDSim* lcd, int displayOn, int cursorOn, int blinkOn);
void LCD_SetCursor(LCDSim* lcd, int row, int col);
void LCD_PutS(LCDSim* lcd, const char* str);
LCDSim* LCDSim_Destroy(LCDSim* lcd);
*/

/*
window (SDL_Window)*: This represents the top-level display area on your operating system's desktop. It's the visible frame that contains all the graphics. In this code, SDL_CreateWindow creates a new window titled "LCD 16x2" with specific dimensions (331x149 pixels) and positions it in the center of your screen. It's the canvas upon which the LCD emulation will be drawn.

screen (SDL_Surface)*: This refers to the drawing surface associated directly with the window. It's the actual pixel buffer where you can draw graphics. SDL_GetWindowSurface(window) retrieves this surface. Whatever you draw onto this screen surface will be rendered inside your window. It acts as the intermediary between your drawing operations and what gets displayed in the window.

lcd (LCDSim)*: This is a custom data structure (likely defined in lcdsim.h and implemented in lcdsim.c) that simulates the internal state and behavior of a physical LCD module. It encapsulates the LCD's characters, cursor position, display settings (like on/off, cursor on/off, blink on/off), and its logic for processing commands (like LCD_PutS for displaying text). It doesn't directly handle pixels but interprets commands and translates them into what should be displayed.
*/

int __main(int argc, char** argv) {
    SDL_Event event;
    SDL_Window* window = NULL;
    SDL_Surface* screen = NULL;
    LCDSim* lcd = NULL;
    int hold = 1;

    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        SDL_Log("SDL_Init failed: %s", SDL_GetError());
        return EXIT_FAILURE;
    }

    window = SDL_CreateWindow("LCD 16x2",
                              SDL_WINDOWPOS_CENTERED,
                              SDL_WINDOWPOS_CENTERED,
                              331, 149,
                              SDL_WINDOW_SHOWN);
    if (!window) {
        SDL_Log("SDL_CreateWindow failed: %s", SDL_GetError());
        SDL_Quit();
        return EXIT_FAILURE;
    }

    // Get the window's surface
    screen = SDL_GetWindowSurface(window);
    if (!screen) {
        SDL_Log("SDL_GetWindowSurface failed: %s", SDL_GetError());
        SDL_DestroyWindow(window);
        SDL_Quit();
        return EXIT_FAILURE;
    }

    lcd = LCDSim_Create(screen, 0, 0, "../../tools/LCDSim/");
    LCD_State(lcd, 1, 1, 1);
    LCD_SetCursor(lcd, 0, 3);
    LCD_PutS(lcd, "Hello,");
    LCD_SetCursor(lcd, 1, 1);
    LCD_PutS(lcd, "Andy and Louis!");

    // 1, LCD instruciton executed

    LCD_SetCursor(lcd, 1, 1);
    LCD_PutChar(lcd, 'H');
    LCDSim_Draw(lcd);
    SDL_UpdateWindowSurface(window);
    SDL_Delay(500); // Wait 500 milliseconds (0.5 seconds)

    // 2, non-LCD instruciton executed
    // do nothing 

    // 3, LCD instruciton executed


    LCD_SetCursor(lcd, 1, 2);
    LCD_PutChar(lcd, 'O');
    LCDSim_Draw(lcd);
    SDL_UpdateWindowSurface(window);
    SDL_Delay(500);

        // 4, LCD instruciton executed

    LCD_SetCursor(lcd, 1, 4);
    LCD_PutChar(lcd, 'M');
    LCDSim_Draw(lcd);
    SDL_UpdateWindowSurface(window);
    SDL_Delay(500);

    // 5, all instructions were  executed, wait for Ctrl-C to exit


    while (hold) {
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) {
                hold = 0;
            }
        }
/* 
        // Fill the screen with black
        SDL_FillRect(screen, NULL, SDL_MapRGB(screen->format, 0, 0, 0));

        // Draw LCD content
        LCDSim_Draw(lcd);

        // Update the window with the surface content
        SDL_UpdateWindowSurface(window);

        SDL_Delay(1000*5);

        // LCD_SetCursor(lcd, 1, 1);
        // LCD_PutS(lcd, "Test");

        // LCD_Sh_Display_L(lcd);

        // LCDSim_Draw(lcd);
        // Update the window with the surface content
        // SDL_UpdateWindowSurface(window);
        LCD_SetCursor(lcd, 1, 1);

        LCD_Sh_Cursor_R(lcd);
        SDL_UpdateWindowSurface(window);
       LCDSim_Draw(lcd);
        SDL_Delay(1000*1);
        
        LCD_Sh_Cursor_R(lcd);
        SDL_UpdateWindowSurface(window);
       LCDSim_Draw(lcd);
        SDL_Delay(1000*1); */

        SDL_Delay(1000*1); 
    }

    lcd = LCDSim_Destroy(lcd);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return EXIT_SUCCESS;
}
