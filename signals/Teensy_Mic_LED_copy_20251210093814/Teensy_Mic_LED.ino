#include <Arduino.h>
#include <Audio.h>
#include <Wire.h>
#include <U8g2lib.h>

// ------------------ Pins ------------------
const int VOLUME_LED = 13;
const int LOW_LED    = 14;
const int HIGH_LED   = 15;

// ------------------ Audio objects ------------------
AudioInputI2S           i2sMic;
AudioAnalyzePeak         peak;
AudioAnalyzeFFT1024      fft;
AudioConnection          patchCord1(i2sMic, peak);
AudioConnection          patchCord2(i2sMic, fft);

// ------------------ OLED ------------------
U8G2_SH1106_128X64_NONAME_F_HW_I2C oled(U8G2_R0, /* reset=*/ U8X8_PIN_NONE);

// ------------------ Thresholds ------------------
const float MIN_AMPLITUDE      = 0.01;
const float QUIET_THRESH       = 0.06;
const float TALKING_THRESH     = 0.07;
const float CLAPPING_THRESH    = 0.10;
const float BANGING_THRESH     = 0.40;

// ------------------ FFT Settings ------------------
#define NUM_FFT_BINS 512  // Changed from 32 to 512 (1024/2)

void setup() {
  Serial.begin(115200);
  pinMode(VOLUME_LED, OUTPUT);
  pinMode(LOW_LED, OUTPUT);
  pinMode(HIGH_LED, OUTPUT);
  
  AudioMemory(12);
  
  oled.begin();
  oled.clearBuffer();
  oled.setFont(u8g2_font_ncenB08_tr);
  oled.sendBuffer();
}

void loop() {
  if (peak.available() && fft.available()) {
    float amplitude = peak.read();
    
    int brightness = 0;
    int volumeLevel = 0;
    
    if (amplitude < MIN_AMPLITUDE) {
      volumeLevel = 0; brightness = 0;
    } 
    else if (amplitude <= QUIET_THRESH) {
      volumeLevel = 1; brightness = 80;
    }
    else if (amplitude <= TALKING_THRESH) {
      volumeLevel = 2; brightness = 140;
    }
    else if (amplitude <= CLAPPING_THRESH) {
      volumeLevel = 3; brightness = 200;
    }
    else if (amplitude <= BANGING_THRESH) {
      volumeLevel = 4; brightness = 240;
    }
    else {
      volumeLevel = 5; brightness = 255;
    }
    analogWrite(VOLUME_LED, brightness);
    
    float dominantFreq = 0;
    if (amplitude > MIN_AMPLITUDE) {
      int dominantBin = 0;
      float maxVal = 0;
      for (int i = 2; i < 512; i++) {
        float val = fft.read(i);
        if (val > maxVal) { maxVal = val; dominantBin = i; }
      }
      dominantFreq = (dominantBin * 44100.0) / 1024.0;
    }
    
    // OLED Display code here (keeping it as is)
    oled.clearBuffer();
    oled.drawStr(0, 10, "Volume:");
    
    int volSegmentWidth = 22;
    int volSegmentSpacing = 2;
    int volStartX = 0;
    int barY = 15;
    int barHeight = 12;
    
    for(int i = 0; i < 5; i++) {
      int x = volStartX + i * (volSegmentWidth + volSegmentSpacing);
      oled.drawFrame(x, barY, volSegmentWidth, barHeight);
      if(i < volumeLevel) {
        oled.drawBox(x + 2, barY + 2, volSegmentWidth - 4, barHeight - 4);
      }
    }
    
    String volText;
    switch(volumeLevel){
      case 0: volText = "Silent"; break;
      case 1: volText = "Quiet"; break;
      case 2: volText = "Talking"; break;
      case 3: volText = "Clapping"; break;
      case 4: volText = "Banging"; break;
      case 5: volText = "VERY LOUD!"; break;
    }
    oled.drawStr(0, 40, volText.c_str());
    
    oled.drawStr(0, 52, "Low");
    oled.drawStr(48, 52, "Pitch");
    oled.drawStr(92, 52, "High");
    
    int pitchBarY = 56;
    int pitchBarHeight = 8;
    int pitchSegmentWidth = 38;
    int pitchSegmentSpacing = 2;
    int pitchStartX = 0;
    
    for(int i = 0; i < 3; i++) {
      int x = pitchStartX + i * (pitchSegmentWidth + pitchSegmentSpacing);
      oled.drawFrame(x, pitchBarY, pitchSegmentWidth, pitchBarHeight);
    }
    
    if (volumeLevel > 1 && dominantFreq > 0) {
      if(dominantFreq < 400) {
        oled.drawBox(pitchStartX + 2, pitchBarY + 2, pitchSegmentWidth - 4, pitchBarHeight - 4);
      } 
      else if(dominantFreq >= 2000) {
        int x = pitchStartX + 2 * (pitchSegmentWidth + pitchSegmentSpacing);
        oled.drawBox(x + 2, pitchBarY + 2, pitchSegmentWidth - 4, pitchBarHeight - 4);
      }
      else {
        int x = pitchStartX + 1 * (pitchSegmentWidth + pitchSegmentSpacing);
        oled.drawBox(x + 2, pitchBarY + 2, pitchSegmentWidth - 4, pitchBarHeight - 4);
      }
    }
    
    oled.sendBuffer();
    
    if (volumeLevel <= 1) {
      digitalWrite(LOW_LED, LOW);
      digitalWrite(HIGH_LED, LOW);
    } 
    else {
      if (dominantFreq < 400) {
        digitalWrite(LOW_LED, HIGH);
        digitalWrite(HIGH_LED, LOW);
      } 
      else if (dominantFreq >= 2000) {
        digitalWrite(LOW_LED, LOW);
        digitalWrite(HIGH_LED, HIGH);
      } 
      else {
        digitalWrite(LOW_LED, LOW);
        digitalWrite(HIGH_LED, LOW);
      }
    }
    
    // Send data with FFT - Now sending all 512 bins
    Serial.print(amplitude); 
    Serial.print(","); 
    Serial.print(volumeLevel); 
    Serial.print(","); 
    Serial.print(dominantFreq);
    Serial.print(",");
    
    for(int i = 0; i < NUM_FFT_BINS; i++) {
      float binValue = fft.read(i);
      int scaledValue = (int)(binValue * 1000);
      scaledValue = constrain(scaledValue, 0, 100);
      Serial.print(scaledValue);
      if(i < NUM_FFT_BINS - 1) {
        Serial.print(",");
      }
    }
    Serial.println();
  }
}
