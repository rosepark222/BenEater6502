------------------------------------------------------------------------------------------
https://claude.ai/share/a51999b2-7b9f-426f-90d6-4e70cafc3867
------------------------------------------------------------------------------------------

my 6502 is able to take in ps/2 scan code from keyboard. Now I can do some game design. First, I'd like to do the following. After the keyboard initialization, display a character in the center of the 16x2 LCD screen. the character is a box of 2x2 pixels in LCD. When I press the arrow keys, it should move accordingly, but stays in LCD screen. 6502 should create 30 frames per second and each frame , it should create a custom character for the box, depending where it is, write to LCD ram, write to display ram to render in LCD, wait for the next key input. When it moves, it should move three pixels. In this way, it will hide the gap between the first and second row and space between 5x8 character spaces. Use the attached code as a starting point. if you need to add a circular buffer for the key input, do so. Also, currently it takes in 3 scan code ( code, 0xF0, code). Change the IRQ so that it skips 0xF0 and the one after that.


------------------------------------------------------------------------------------------
I am wondering using delay_33ms can produce 30 frames per second? Each frame requires time to process input, calculate position, produce character, create render screen, then extra wait time to fill the gap. For this you need to do some analysis measuring how logic function take per frame and make delay_Xms to make the function + delay be 33ms.


------------------------------------------------------------------------------------------
add these functions:
1, use vi like h(left) j( down) k (up) l (down) keys for movement
2, use the below table to print the key pressed at the right bottom of LCD every time a key is pressed


------------------------------------------------------------------------------------------
shouldn't  .org $fd00 come before .org $FFFA  or it does not matter ?

------------------------------------------------------------------------------------------
can you update CYCLE COUNT ANALYSIS because the logic for displaying character is added?
