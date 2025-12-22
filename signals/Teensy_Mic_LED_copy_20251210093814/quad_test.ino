#include <Audio.h>

// Quad I2S input uses Pins 8 (ch 1-2) and 6 (ch 3-4)
AudioInputI2SQuad        i2s_quad;       
AudioAnalyzePeak         peak1, peak2, peak3, peak4;

// Route the 4 quad channels to analyzers
AudioConnection          patch1(i2s_quad, 0, peak1, 0);
AudioConnection          patch2(i2s_quad, 1, peak2, 0);
AudioConnection          patch3(i2s_quad, 2, peak3, 0);
AudioConnection          patch4(i2s_quad, 3, peak4, 0);

void setup() {
  Serial.begin(9600);
  AudioMemory(12);
}

void loop() {
  if (peak1.available() && peak2.available() && peak3.available() && peak4.available()) {
    Serial.print("CH1: "); Serial.print(peak1.read(), 2);
    Serial.print(" | CH2: "); Serial.print(peak2.read(), 2);
    Serial.print(" | CH3: "); Serial.print(peak3.read(), 2);
    Serial.print(" | CH4: "); Serial.println(peak4.read(), 2);
  }
  delay(100);
}
