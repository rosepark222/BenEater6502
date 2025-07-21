// example.c, updated to use SDL_Surface
#include <SDL2/SDL.h>
#include <stdlib.h>
#include "lcdsim.h"

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
int main(int argc, char** argv) {
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
