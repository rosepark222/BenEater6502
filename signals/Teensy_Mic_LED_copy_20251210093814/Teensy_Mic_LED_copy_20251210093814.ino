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
const float MIN_AMPLITUDE      = 0.01;   // Minimum detection
const float QUIET_THRESH       = 0.06;   // Quiet
const float TALKING_THRESH     = 0.07;   // Talking (raised threshold)
const float CLAPPING_THRESH    = 0.10;   // Clapping
const float BANGING_THRESH     = 0.40;   // Loud banging
// Above 0.75 is very loud

void setup() {
  Serial.begin(115200);
  pinMode(VOLUME_LED, OUTPUT);
  pinMode(LOW_LED, OUTPUT);
  pinMode(HIGH_LED, OUTPUT);
  
  AudioMemory(12);
  
  // Initialize OLED
  oled.begin();
  oled.clearBuffer();
  oled.setFont(u8g2_font_ncenB08_tr);
  oled.sendBuffer();
}

void loop() {
  if (peak.available() && fft.available()) {
    float amplitude = peak.read();
    
    // ----- Volume LED -----
    int brightness = 0;
    int volumeLevel = 0;  // 0=Silent, 1=Quiet, 2=Talking, 3=Clapping, 4=Banging, 5=Very Loud
    
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
    
    // ----- Determine Pitch -----
    float dominantFreq = 0;
    if (amplitude > MIN_AMPLITUDE) {
      int dominantBin = 0;
      float maxVal = 0;
      for (int i = 2; i < 512; i++) {
        float val = fft.read(i); //Andy we need to send this to processing and draw, not dominantFreq 
        if (val > maxVal) { maxVal = val; dominantBin = i; }
      }
      dominantFreq = (dominantBin * 44100.0) / 1024.0;
    }
    
    // ----- OLED Display -----
    oled.clearBuffer();
    
    // Volume Label
    oled.drawStr(0, 10, "Volume:");
    
    // Volume Bar - 5 segments
    int volSegmentWidth = 22;
    int volSegmentSpacing = 2;
    int volStartX = 0;
    int barY = 15;
    int barHeight = 12;
    
    // Draw 5 segments
    for(int i = 0; i < 5; i++) {
      int x = volStartX + i * (volSegmentWidth + volSegmentSpacing);
      oled.drawFrame(x, barY, volSegmentWidth, barHeight);
      if(i < volumeLevel) {
        oled.drawBox(x + 2, barY + 2, volSegmentWidth - 4, barHeight - 4);
      }
    }
    
    // Volume Level Text
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
    
    // Pitch Label and Bar (centered, expands outward from middle)
    oled.drawStr(0, 52, "Low");
    oled.drawStr(48, 52, "Pitch");
    oled.drawStr(92, 52, "High");
    
    int pitchBarY = 56;
    int pitchBarHeight = 8;
    int pitchSegmentWidth = 38;
    int pitchSegmentSpacing = 2;
    int pitchStartX = 0;
    
    // Draw 3 segments for pitch
    for(int i = 0; i < 3; i++) {
      int x = pitchStartX + i * (pitchSegmentWidth + pitchSegmentSpacing);
      oled.drawFrame(x, pitchBarY, pitchSegmentWidth, pitchBarHeight);
    }
    
    // Pitch ranges: Low (<400Hz), Medium (400-2000Hz), High (>2000Hz)
    // Only show pitch if volume is above Quiet level
    if (volumeLevel > 1 && dominantFreq > 0) {
      if(dominantFreq < 400) {
        // Low pitch (bass) - fill LEFT segment
        oled.drawBox(pitchStartX + 2, pitchBarY + 2, pitchSegmentWidth - 4, pitchBarHeight - 4);
      } 
      else if(dominantFreq >= 2000) {
        // High pitch (fire alarm) - fill RIGHT segment
        int x = pitchStartX + 2 * (pitchSegmentWidth + pitchSegmentSpacing);
        oled.drawBox(x + 2, pitchBarY + 2, pitchSegmentWidth - 4, pitchBarHeight - 4);
      }
      else {
        // Medium range (400-2000 Hz) - fill MIDDLE segment
        int x = pitchStartX + 1 * (pitchSegmentWidth + pitchSegmentSpacing);
        oled.drawBox(x + 2, pitchBarY + 2, pitchSegmentWidth - 4, pitchBarHeight - 4);
      }
    }
    
    oled.sendBuffer();
    
    // ----- Pitch LEDs -----
    // Only activate pitch LEDs if volume is above Quiet level
    if (volumeLevel <= 1) {
      // Turn off all LEDs when Silent or Quiet
      digitalWrite(LOW_LED, LOW);
      digitalWrite(HIGH_LED, LOW);
    } 
    else {
      if (dominantFreq < 400) {           // low pitch (bass)
        digitalWrite(LOW_LED, HIGH);
        digitalWrite(HIGH_LED, LOW);
      } 
      else if (dominantFreq >= 2000) {    // high pitch (fire alarm)
        digitalWrite(LOW_LED, LOW);
        digitalWrite(HIGH_LED, HIGH);
      } 
      else {                              // mid-range (400-2000 Hz)
        digitalWrite(LOW_LED, LOW);
        digitalWrite(HIGH_LED, LOW);
      }
    }
    
    // ----- Debug -----
    Serial.print(amplitude); 
    Serial.print(","); 
    Serial.print(volumeLevel); 
    Serial.print(","); 
    Serial.println(dominantFreq);
  }
}