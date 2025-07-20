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

    lcd = LCDSim_Create(screen, 0, 0);
    LCD_State(lcd, 1, 1, 1);
    LCD_SetCursor(lcd, 0, 3);
    LCD_PutS(lcd, "Hello,");
    LCD_SetCursor(lcd, 1, 1);
    LCD_PutS(lcd, "Andy and Luois!");


    LCD_SetCursor(lcd, 1, 1);
LCD_PutChar(lcd, 'H');
LCDSim_Draw(lcd);
SDL_UpdateWindowSurface(window);
SDL_Delay(500); // Wait 500 milliseconds (0.5 seconds)

LCD_SetCursor(lcd, 1, 2);
LCD_PutChar(lcd, 'O');
LCDSim_Draw(lcd);
SDL_UpdateWindowSurface(window);
SDL_Delay(500);

LCD_SetCursor(lcd, 1, 4);
LCD_PutChar(lcd, 'M');
LCDSim_Draw(lcd);
SDL_UpdateWindowSurface(window);
SDL_Delay(500);



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
