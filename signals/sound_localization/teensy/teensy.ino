#include <Arduino.h>
#include <Audio.h>
#include <Wire.h>
#include <U8g2lib.h>
#include <arm_math.h>

// ------------------ Pins ------------------
const int VOLUME_LED = 13;
const int LOW_LED    = 14;
const int HIGH_LED   = 15;

// ------------------ Audio objects ------------------
AudioInputI2S           i2sMic;
AudioFilterBiquad       dcBlocker;
AudioAnalyzePeak        peak;
AudioAnalyzeFFT1024     fft;  // Keep for display
AudioRecordQueue        queueMic1;  // NEW: For raw samples
AudioConnection         patchCord1(i2sMic, 0, dcBlocker, 0);
AudioConnection         patchCord2(dcBlocker, 0, peak, 0);
AudioConnection         patchCord3(dcBlocker, 0, fft, 0);
AudioConnection         patchCord4(dcBlocker, 0, queueMic1, 0);  // NEW: Capture samples

// ------------------ OLED ------------------
U8G2_SH1106_128X64_NONAME_F_HW_I2C oled(U8G2_R0, /* reset=*/ U8X8_PIN_NONE);

// ------------------ Thresholds ------------------
const float MIN_AMPLITUDE      = 0.01;
const float QUIET_THRESH       = 0.06;
const float TALKING_THRESH     = 0.07;
const float CLAPPING_THRESH    = 0.10;
const float BANGING_THRESH     = 0.40;

// ------------------ FFT Settings ------------------
#define FFT_SIZE 1024
#define FFT_BINS 512
#define NUM_FFT_BINS 512
#define DELAY_SAMPLES 13  // 0.3ms at 44.1kHz

// ARM CMSIS FFT instance
arm_rfft_fast_instance_f32 fft_inst;

// Mic1 buffers
float mic1_time[FFT_SIZE];
float mic1_fft[FFT_SIZE * 2];  // Complex: [real0, imag0, real1, imag1, ...]
float mic1_magnitude[FFT_BINS];
float mic1_phase[FFT_BINS];

// Mic2 buffers (delayed version)
float mic2_time[FFT_SIZE];
float mic2_fft[FFT_SIZE * 2];
float mic2_magnitude[FFT_BINS];
float mic2_phase[FFT_BINS];

// Delay buffer for mic2 emulation
int16_t delayBuffer[DELAY_SAMPLES];
int delayIndex = 0;

int sample_count = 0;
bool fft_ready = false;

void computeFFTAndPhase(float* input, float* fft_output, float* magnitude, float* phase) {
  // Perform FFT
  arm_rfft_fast_f32(&fft_inst, input, fft_output, 0);
  
  // Calculate magnitude and phase for each bin
  for (int i = 0; i < FFT_BINS; i++) {
    float real = fft_output[i * 2];
    float imag = fft_output[i * 2 + 1];
    
    magnitude[i] = sqrtf(real * real + imag * imag) / FFT_SIZE;
    phase[i] = atan2f(imag, real);
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(VOLUME_LED, OUTPUT);
  pinMode(LOW_LED, OUTPUT);
  pinMode(HIGH_LED, OUTPUT);
  
  AudioMemory(20);
  
  // Initialize ARM FFT
  arm_rfft_fast_init_f32(&fft_inst, FFT_SIZE);
  
  // Configure DC blocking filter
  dcBlocker.setHighpass(0, 20, 0.707);
  
  // Initialize delay buffer
  for (int i = 0; i < DELAY_SAMPLES; i++) {
    delayBuffer[i] = 0;
  }
  
  // Start recording queue
  queueMic1.begin();
  
  oled.begin();
  oled.clearBuffer();
  oled.setFont(u8g2_font_ncenB08_tr);
  oled.drawStr(0, 10, "Setup done");
  oled.sendBuffer();
  
  Serial.println("Setup complete - ARM FFT initialized");
}

void loop() {
  // Collect samples for ARM FFT
  if (queueMic1.available()) {
    int16_t *buffer = queueMic1.readBuffer();
    
    for (int i = 0; i < 128; i++) {
      if (sample_count < FFT_SIZE) {
        // Mic1: current sample
        mic1_time[sample_count] = buffer[i] / 32768.0f;
        
        // Mic2: delayed version (emulated)
        mic2_time[sample_count] = delayBuffer[delayIndex] / 32768.0f;
        
        // Update delay buffer
        delayBuffer[delayIndex] = buffer[i];
        delayIndex = (delayIndex + 1) % DELAY_SAMPLES;
        
        sample_count++;
      }
    }
    
    queueMic1.freeBuffer();
    
    // When buffer is full, compute FFT
    if (sample_count >= FFT_SIZE) {
      computeFFTAndPhase(mic1_time, mic1_fft, mic1_magnitude, mic1_phase);
      computeFFTAndPhase(mic2_time, mic2_fft, mic2_magnitude, mic2_phase);
      fft_ready = true;
      sample_count = 0;
    }
  }
  
  // Original display code - runs when both FFTs are available
  if (peak.available() && fft.available() && fft_ready) {
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
    
    // OLED Display
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
    
    // Send data to serial - now using ARM FFT results
    // Format: MIC1_MAG,MIC1_PHASE,MIC2_MAG,MIC2_PHASE (alternating)
    Serial.println("FFT_DATA_START");
    
    // Send Mic1 FFT (magnitude and phase interleaved)
    Serial.print("MIC1:");
    for(int i = 0; i < NUM_FFT_BINS; i++) {
      Serial.print(mic1_magnitude[i], 6);
      Serial.print(",");
      Serial.print(mic1_phase[i], 6);
      if(i < NUM_FFT_BINS - 1) {
        Serial.print(",");
      }
    }
    Serial.println();
    
    // Send Mic2 FFT (magnitude and phase interleaved)
    Serial.print("MIC2:");
    for(int i = 0; i < NUM_FFT_BINS; i++) {
      Serial.print(mic2_magnitude[i], 6);
      Serial.print(",");
      Serial.print(mic2_phase[i], 6);
      if(i < NUM_FFT_BINS - 1) {
        Serial.print(",");
      }
    }
    Serial.println();
    
    Serial.println("FFT_DATA_END");
    
    fft_ready = false;  // Reset flag
  }
}

