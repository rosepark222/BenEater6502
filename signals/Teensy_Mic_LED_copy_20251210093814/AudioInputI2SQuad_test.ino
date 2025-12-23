#include <Audio.h>
#include <Wire.h>
#include <SPI.h>
#include <SD.h>
#include <SerialFlash.h>

// 1. Setup Audio Objects
AudioInputI2SQuad      i2s_quad;       // Captures 4 channels from pins 8 and 6
//AudioAnalyzeRMS        rms1, rms2, rms3, rms4; 

AudioAnalyzePeak peak1; // Mic 1 (I2S1 Left)
AudioAnalyzePeak peak2; // Mic 2 (I2S1 Right)
AudioAnalyzePeak peak3; // Mic 3 (I2S2 Left)
AudioAnalyzePeak peak4; // Mic 4 (I2S2 Right)

AudioAmplifier amp1, amp2, amp3, amp4;
// 2. Connect microphones to analysis objects
// SPH0645 often needs a gain boost; you can add AudioAmplifier objects if needed.
AudioConnection          patchCord1(i2s_quad, 0, amp1, 0); // Pin 8, SEL=GND
AudioConnection          patchCord1b(amp1, 0, peak1, 0);

AudioConnection          patchCord2(i2s_quad, 1, amp2, 0); // Pin 8, SEL=3.3V
AudioConnection          patchCord2b(amp2, 0, peak2, 0);

AudioConnection          patchCord3(i2s_quad, 2, amp3, 0); // Pin 6, SEL=GND
AudioConnection          patchCord3b(amp3, 0, peak3, 0);

AudioConnection          patchCord4(i2s_quad, 3, amp4, 0); // Pin 6, SEL=3.3V
AudioConnection          patchCord4b(amp4, 0, peak4, 0);

void setup() {
  Serial.begin(115200);
  
  // Allocate memory for the audio library
  AudioMemory(20); 
  
  Serial.println("4-Mic I2S Quad Test Starting...");
}

void loop() {
 
 
  //Serial.println("Read and print levels every 100ms");
  if (peak1.available() &&
	  peak2.available() &&
	  peak3.available() &&
	  peak4.available()) {
      Serial.print("Mic1: "); Serial.print(peak1.read(), 4);
      Serial.print(" | Mic2: "); Serial.print(peak2.read(), 4);
      Serial.print(" | Mic3: "); Serial.print(peak3.read(), 4);
      Serial.print(" | Mic4: "); Serial.println(peak4.read(), 4);
  }
  //delay(100);
}
