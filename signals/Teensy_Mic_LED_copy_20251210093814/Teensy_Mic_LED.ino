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

// LEFT mic chain
AudioAnalyzePeak        peakLeft;
AudioAnalyzeFFT1024     fftLeft;

// RIGHT mic chain
AudioAnalyzePeak        peakRight;
AudioAnalyzeFFT1024     fftRight;

// ------------------ Connections ------------------
AudioConnection patchCord1(i2sMic, 0, peakLeft, 0);   // Left channel
AudioConnection patchCord2(i2sMic, 0, fftLeft, 0);
AudioConnection patchCord3(i2sMic, 1, peakRight, 0);  // Right channel
AudioConnection patchCord4(i2sMic, 1, fftRight, 0);

// ------------------ OLED ------------------
U8G2_SH1106_128X64_NONAME_F_HW_I2C oled(U8G2_R0, /* reset=*/ U8X8_PIN_NONE);

// ------------------ Thresholds ------------------
const float MIN_AMPLITUDE      = 0.01;
const float QUIET_THRESH       = 0.06;
const float TALKING_THRESH     = 0.07;
const float CLAPPING_THRESH    = 0.10;
const float BANGING_THRESH     = 0.40;

// ------------------ GCC-PHAT Distance Estimation ------------------
const float MIC_SPACING_CM = 10.0;  // Distance between your two mics in cm
const float SPEED_OF_SOUND = 34300.0; // cm/s at room temperature
const float SAMPLE_RATE = 44100.0;
const int FFT_SIZE = 1024;

// Maximum time delay based on mic spacing
const float MAX_DELAY_SECONDS = MIC_SPACING_CM / SPEED_OF_SOUND;
const int MAX_DELAY_SAMPLES = (int)(MAX_DELAY_SECONDS * SAMPLE_RATE);

// ------------------ FFT Settings ------------------
#define NUM_FFT_BINS 512

// ------------------ Display update control ------------------
unsigned long lastDisplayUpdate = 0;
const unsigned long DISPLAY_INTERVAL = 50; // Update display every 50ms (20 FPS)

// Previous values for change detection
int prevVolLeft = -1;
int prevVolRight = -1;
int prevPitchLeft = -1;
int prevPitchRight = -1;
float prevFreqLeft = -1;
float prevFreqRight = -1;
float prevAmpLeft = -1;
float prevAmpRight = -1;
float prevDistance = -1;
int prevDirection = 0;

// GCC-PHAT buffers for smoothing
float gccPhatHistory[5] = {0};
int historyIndex = 0;

// Helper function to get volume level
int getVolumeLevel(float amplitude) {
  if (amplitude < MIN_AMPLITUDE) return 0;
  else if (amplitude <= QUIET_THRESH) return 1;
  else if (amplitude <= TALKING_THRESH) return 2;
  else if (amplitude <= CLAPPING_THRESH) return 3;
  else if (amplitude <= BANGING_THRESH) return 4;
  else return 5;
}

// Helper function to get brightness
int getBrightness(int volumeLevel) {
  const int brightLevels[] = {0, 80, 140, 200, 240, 255};
  return brightLevels[volumeLevel];
}

// Helper function to get dominant frequency
float getDominantFreq(AudioAnalyzeFFT1024 &fft, float amplitude) {
  if (amplitude <= MIN_AMPLITUDE) return 0;
  
  int dominantBin = 0;
  float maxVal = 0;
  for (int i = 2; i < 512; i++) {
    float val = fft.read(i);
    if (val > maxVal) { 
      maxVal = val; 
      dominantBin = i; 
    }
  }
  return (dominantBin * 44100.0) / 1024.0;
}

// Helper function to determine pitch category (0=low, 1=mid, 2=high, -1=none)
int getPitchCategory(float freq, int volumeLevel) {
  if (volumeLevel <= 1 || freq <= 0) return -1;
  if (freq < 400) return 0;
  if (freq >= 2000) return 2;
  return 1;
}

// GCC-PHAT: Generalized Cross-Correlation with Phase Transform
// This method is robust to noise and reverberation
float calculateGCCPHAT() {
  // We need to compute cross-power spectrum between the two microphones
  // GCC-PHAT formula: R(τ) = IFFT[ X1(f) * conj(X2(f)) / |X1(f) * conj(X2(f))| ]
  // Where τ is the time delay
  
  float maxCorrelation = 0;
  int maxLag = 0;
  
  // Search range: ±MAX_DELAY_SAMPLES
  int searchRange = min(MAX_DELAY_SAMPLES, 50); // Limit search for performance
  
  // Compute cross-correlation in frequency domain with phase transform
  for (int lag = -searchRange; lag <= searchRange; lag++) {
    float correlation = 0;
    float normalization = 0;
    
    // Sum over frequency bins (skip DC and very low frequencies)
    for (int i = 5; i < NUM_FFT_BINS - 10; i++) {
      float left_mag = fftLeft.read(i);
      float right_mag = fftRight.read(i);
      
      // Phase Transform: normalize by magnitude to emphasize phase
      // This makes the method robust to amplitude variations
      float denom = left_mag * right_mag;
      
      if (denom > 0.0001) { // Avoid division by zero
        // Simplified cross-correlation with phase emphasis
        // In true GCC-PHAT we'd work with complex numbers, but we approximate with magnitudes
        float weight = 1.0 / sqrt(denom); // PHAT weighting
        
        // Approximate phase correlation using magnitude product
        // This is a simplification since we don't have access to phase directly
        correlation += left_mag * right_mag * weight * cos(2 * PI * i * lag / FFT_SIZE);
        normalization += weight;
      }
    }
    
    if (normalization > 0) {
      correlation /= normalization;
    }
    
    // Find maximum correlation
    if (abs(correlation) > abs(maxCorrelation)) {
      maxCorrelation = correlation;
      maxLag = lag;
    }
  }
  
  // Convert lag to time delay (in samples)
  return maxLag;
}

// Enhanced GCC-PHAT with temporal smoothing and confidence
float calculateDistanceGCCPHAT(float ampLeft, float ampRight, float &confidence) {
  // Need minimum amplitude to calculate
  if (ampLeft < MIN_AMPLITUDE && ampRight < MIN_AMPLITUDE) {
    confidence = 0;
    return 0;
  }
  
  // Calculate time delay using GCC-PHAT
  float delaySamples = calculateGCCPHAT();
  
  // Add to history for smoothing
  gccPhatHistory[historyIndex] = delaySamples;
  historyIndex = (historyIndex + 1) % 5;
  
  // Moving average filter for stability
  float avgDelay = 0;
  for (int i = 0; i < 5; i++) {
    avgDelay += gccPhatHistory[i];
  }
  avgDelay /= 5.0;
  
  // Convert delay in samples to time
  float delayTime = avgDelay / SAMPLE_RATE;
  
  // Calculate distance difference: d = v * t
  float distanceDiff = delayTime * SPEED_OF_SOUND;
  
  // Calculate confidence based on signal strength
  float totalAmp = ampLeft + ampRight;
  confidence = min(totalAmp / 0.2, 1.0); // Normalize to 0-1
  
  // If delay is positive: sound reached left mic first (source is on left)
  // If delay is negative: sound reached right mic first (source is on right)
  
  return constrain(distanceDiff, -MIC_SPACING_CM * 2, MIC_SPACING_CM * 2);
}

// Get direction indicator: -1 (left), 0 (center), 1 (right)
int getDirection(float distance, float confidence) {
  if (confidence < 0.3) return 0; // Low confidence = center
  if (abs(distance) < 1.5) return 0; // Center threshold
  return (distance < 0) ? -1 : 1; // Negative = left, Positive = right
}

void setup() {
  Serial.begin(115200);
  pinMode(VOLUME_LED, OUTPUT);
  pinMode(LOW_LED, OUTPUT);
  pinMode(HIGH_LED, OUTPUT);
  
  AudioMemory(24); // Increased for dual FFT
  
  // Initialize GCC-PHAT history
  for (int i = 0; i < 5; i++) {
    gccPhatHistory[i] = 0;
  }
  
  oled.begin();
  oled.clearBuffer();
  oled.setFont(u8g2_font_ncenB08_tr);
  oled.drawStr(10, 28, "Dual Mic Ready");
  oled.drawStr(8, 38, "GCC-PHAT Method");
  oled.sendBuffer();
  delay(1500);
}

void loop() {
  if (peakLeft.available() && peakRight.available() && 
      fftLeft.available() && fftRight.available()) {
    
    // Read both microphones
    float ampLeft = peakLeft.read();
    float ampRight = peakRight.read();
    
    // Get volume levels
    int volLeft = getVolumeLevel(ampLeft);
    int volRight = getVolumeLevel(ampRight);
    
    // Get dominant frequencies
    float freqLeft = getDominantFreq(fftLeft, ampLeft);
    float freqRight = getDominantFreq(fftRight, ampRight);
    
    // Get pitch categories
    int pitchLeft = getPitchCategory(freqLeft, volLeft);
    int pitchRight = getPitchCategory(freqRight, volRight);
    
    // Calculate distance and direction using GCC-PHAT
    float confidence = 0;
    float distance = calculateDistanceGCCPHAT(ampLeft, ampRight, confidence);
    int direction = getDirection(distance, confidence);
    
    // Use the louder mic for LED control
    int dominantVol = max(volLeft, volRight);
    float dominantFreq = (ampLeft > ampRight) ? freqLeft : freqRight;
    
    analogWrite(VOLUME_LED, getBrightness(dominantVol));
    
    // ========== OLED DISPLAY (rate-limited and change-detected) ==========
    unsigned long currentTime = millis();
    bool shouldUpdate = (currentTime - lastDisplayUpdate >= DISPLAY_INTERVAL);
    
    // Check if any significant values changed
    bool valuesChanged = (volLeft != prevVolLeft || volRight != prevVolRight ||
                          pitchLeft != prevPitchLeft || pitchRight != prevPitchRight ||
                          abs(freqLeft - prevFreqLeft) > 50 || abs(freqRight - prevFreqRight) > 50 ||
                          abs(ampLeft - prevAmpLeft) > 0.01 || abs(ampRight - prevAmpRight) > 0.01 ||
                          abs(distance - prevDistance) > 0.5 || direction != prevDirection);
    
    if (shouldUpdate && valuesChanged) {
      lastDisplayUpdate = currentTime;
      
      // Update previous values
      prevVolLeft = volLeft;
      prevVolRight = volRight;
      prevPitchLeft = pitchLeft;
      prevPitchRight = pitchRight;
      prevFreqLeft = freqLeft;
      prevFreqRight = freqRight;
      prevAmpLeft = ampLeft;
      prevAmpRight = ampRight;
      prevDistance = distance;
      prevDirection = direction;
      
      oled.clearBuffer();
      oled.setFont(u8g2_font_6x10_tr); // Smaller font for more space
      
      // --- MIC 1 (LEFT) Section ---
      oled.drawStr(0, 8, "M1");
      
      // Volume bar for Mic 1 (5 segments, smaller)
      int barWidth = 8;
      int barHeight = 6;
      int barSpacing = 1;
      int mic1BarY = 10;
      for(int i = 0; i < 5; i++) {
        int x = 18 + i * (barWidth + barSpacing);
        oled.drawFrame(x, mic1BarY, barWidth, barHeight);
        if(i < volLeft) {
          oled.drawBox(x + 1, mic1BarY + 1, barWidth - 2, barHeight - 2);
        }
      }
      
      // --- MIC 2 (RIGHT) Section ---
      oled.drawStr(70, 8, "M2");
      
      // Volume bar for Mic 2
      for(int i = 0; i < 5; i++) {
        int x = 88 + i * (barWidth + barSpacing);
        oled.drawFrame(x, mic1BarY, barWidth, barHeight);
        if(i < volRight) {
          oled.drawBox(x + 1, mic1BarY + 1, barWidth - 2, barHeight - 2);
        }
      }
      
      // --- DIRECTION INDICATOR (Visual) ---
      oled.drawLine(0, 20, 128, 20); // Divider line
      oled.drawStr(35, 28, "DIRECTION");
      
      // Draw direction bar: [L]----o----[R]
      int dirBarY = 32;
      int dirBarWidth = 100;
      int dirBarX = 14;
      
      // Draw left and right markers
      oled.drawStr(0, dirBarY + 6, "L");
      oled.drawStr(120, dirBarY + 6, "R");
      
      // Draw center line
      oled.drawLine(dirBarX, dirBarY, dirBarX + dirBarWidth, dirBarY);
      oled.drawLine(dirBarX + dirBarWidth/2, dirBarY - 2, dirBarX + dirBarWidth/2, dirBarY + 2); // Center mark
      
      // Draw sound position indicator
      if (dominantVol > 1 && confidence > 0.2) {
        // Map distance to position on bar
        // Negative distance = LEFT (sound reached left mic first)
        // Positive distance = RIGHT (sound reached right mic first)
        int indicatorX = dirBarX + dirBarWidth/2 - (int)(distance * dirBarWidth / (MIC_SPACING_CM * 4));
        indicatorX = constrain(indicatorX, dirBarX, dirBarX + dirBarWidth);
        
        // Draw circle indicator (size based on confidence)
        int radius = 2 + (int)(confidence * 2);
        oled.drawDisc(indicatorX, dirBarY, radius);
      }
      
      // --- Bottom Section: Numeric Info ---
      oled.drawLine(0, 45, 128, 45); // Divider line
      
      // Show distance estimate and confidence
      char distText[32];
      if (dominantVol > 1 && confidence > 0.2) {
        if (direction < 0) {
          sprintf(distText, "LEFT %.1fcm C:%.0f%%", abs(distance), confidence * 100);
        } else if (direction > 0) {
          sprintf(distText, "RIGHT %.1fcm C:%.0f%%", abs(distance), confidence * 100);
        } else {
          sprintf(distText, "CENTER C:%.0f%%", confidence * 100);
        }
      } else {
        sprintf(distText, "No signal / Low C");
      }
      oled.drawStr(2, 54, distText);
      
      // Show amplitudes
      char ampText[32];
      sprintf(ampText, "L:%.2f R:%.2f", ampLeft, ampRight);
      oled.drawStr(15, 63, ampText);
      
      oled.sendBuffer();
    } // End of display update
    
    // ========== LED CONTROL ==========
    // Use direction to control LEDs (only if confident)
    if (dominantVol <= 1 || confidence < 0.3) {
      digitalWrite(LOW_LED, LOW);
      digitalWrite(HIGH_LED, LOW);
    } else {
      if (direction < 0) {
        digitalWrite(LOW_LED, HIGH);  // Sound from LEFT
        digitalWrite(HIGH_LED, LOW);
      } else if (direction > 0) {
        digitalWrite(LOW_LED, LOW);
        digitalWrite(HIGH_LED, HIGH); // Sound from RIGHT
      } else {
        digitalWrite(LOW_LED, LOW);
        digitalWrite(HIGH_LED, LOW);  // Sound from CENTER
      }
    }
    
    // ========== SERIAL OUTPUT ==========
    // Format: ampLeft,volLeft,freqLeft,ampRight,volRight,freqRight,distance,direction,confidence,FFT_LEFT[512],FFT_RIGHT[512]
    Serial.print(ampLeft); Serial.print(",");
    Serial.print(volLeft); Serial.print(",");
    Serial.print(freqLeft); Serial.print(",");
    Serial.print(ampRight); Serial.print(",");
    Serial.print(volRight); Serial.print(",");
    Serial.print(freqRight); Serial.print(",");
    Serial.print(distance); Serial.print(",");
    Serial.print(direction); Serial.print(",");
    Serial.print(confidence); Serial.print(",");
    
    // FFT data for LEFT mic
    for(int i = 0; i < NUM_FFT_BINS; i++) {
      float binValue = fftLeft.read(i);
      int scaledValue = constrain((int)(binValue * 1000), 0, 100);
      Serial.print(scaledValue);
      Serial.print(",");
    }
    
    // FFT data for RIGHT mic
    for(int i = 0; i < NUM_FFT_BINS; i++) {
      float binValue = fftRight.read(i);
      int scaledValue = constrain((int)(binValue * 1000), 0, 100);
      Serial.print(scaledValue);
      if(i < NUM_FFT_BINS - 1) Serial.print(",");
    }
    Serial.println();
  }
}