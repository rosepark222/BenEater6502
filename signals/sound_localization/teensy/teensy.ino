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
//AudioConnection         patchCord3(dcBlocker, 0, fft, 0);
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
float mic1_fft[FFT_SIZE * 2];  // 1024 Complex: [real0, imag0, real1, imag1, ...]
float mic1_magnitude[FFT_BINS];
float mic1_phase[FFT_BINS];

// Mic2 buffers (delayed version)
float mic2_time[FFT_SIZE];
float mic2_fft[FFT_SIZE * 2]; // 1024 complex 
float mic2_magnitude[FFT_BINS];
float mic2_phase[FFT_BINS];

float cross_spectrum[FFT_SIZE]; // X(f)X2*(f) / |X(f)X2*(f)|
float correlation_result[FFT_SIZE]; // Final time domain result (size N)

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
 
void run_gcc_phat(float* fft1, float* fft2) {
    // 1. Perform Forward FFTs
    // Input is real samples, Output is complex interleaved in the same size buffer
    // arm_rfft_fast_f32(&fft_instance, samples1, fft1, 0); // 0 for forward FFT
    // arm_rfft_fast_f32(&fft_instance, samples2, fft2, 0); 
    
    // 2. Calculate the Normalized Cross-Spectrum (G_PHAT)
    for (unsigned int k = 0; k < FFT_BINS; k++) {
        unsigned int real_idx = k * 2;
        unsigned int imag_idx = k * 2 + 1;

        float a = fft1[real_idx]; // Real(F1)
        float b = fft1[imag_idx]; // Imag(F1)
        float c = fft2[real_idx]; // Real(F2)
        float d = fft2[imag_idx]; // Imag(F2)

        // G(f) = F1 * conj(F2) = (a + j b) * ( c - j d ) note d = -d for conjugate
        float cross_real = (a * c) + (b * d);
        float cross_imag = (b * c) - (a * d); 

        // // G(f) = conj(F1) *  F2 = (a - j b) * ( c + j d )
        // float cross_real = (a * c) + (b * d);
        // float cross_imag = -(b * c) + (a * d); 
        
        // Magnitude |G(f)| = |F1|*|F2|
        float magnitude = sqrtf(cross_real * cross_real + cross_imag * cross_imag);
        float weight_denominator = magnitude + 1e-10; // Epsilon for stability

        // G_PHAT(f) = G(f) / |G(f)| (Normalized Phase Transform)
        cross_spectrum[real_idx] = cross_real / weight_denominator;
        cross_spectrum[imag_idx] = cross_imag / weight_denominator;
    }

    // 3. Perform Inverse FFT (IFFT)
    // Input is the normalized complex cross_spectrum
    // Output (stored back into the same buffer for space efficiency) is 
    // the real time-domain correlation function
    arm_rfft_fast_f32(&fft_inst, cross_spectrum, correlation_result, 1); // 1 for inverse FFT

    // 4. Normalize the IFFT result (critical for true amplitude scaling)
    for (unsigned int i = 0; i < FFT_SIZE; i++) {
      // correlation_result[i] /= FFT_SIZE; 
      // correlation_result[i] *= 5; 

    }

    // correlation_result[] now holds the 1024-point time-domain GCC-PHAT function
    // You can now find the peak in correlation_result[] to determine the time delay (tau).
    /*
    You should look for the single highest absolute peak in the correlation_result array. 
    The location of this peak corresponds directly to the time delay: 
    Index 0 to 511: These indices represent positive time delays (signal 2 arrived after signal 1). 
    Index 0 represents zero delay (the signals are perfectly aligned).
    Index 1023 down to 512: These indices represent negative time delays (signal 1 arrived after signal 2). 
    The exact index of the maximum value (max_index) gives you the time lag in samples. 
    You can convert this to actual time (seconds) using your sampling frequency: 
     Time delay = max(index) / 44100
     */
}

void setup() {
  Serial.begin(115200);
  pinMode(VOLUME_LED, OUTPUT);
  pinMode(LOW_LED, OUTPUT);
  pinMode(HIGH_LED, OUTPUT);
  /*
  Each audio block is a fixed size: 128 samples of 16-bit data (2 bytes per sample). 
  The total buffer size allocated by that call is: 
   Total Samples: 20 blocks x 128 samples/block = 2560 samples
   Total Memory: 20 blocks x 256 bytes/block = 5120 bytes (5kb)
  */
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
  // Continuous draining mic1 queue - prevents audio buffer overflow
  // We must always read available buffers even while processing FFT
  while (queueMic1.available()) {
    int16_t *buffer = queueMic1.readBuffer();
    
    for (int i = 0; i < 128; i++) {
      if (sample_count < FFT_SIZE) {

        // The data is divided by 32768.0f to normalize the raw audio samples from a 16-bit signed integer range into a floating-point range of -1.0 to 1.0.

        mic1_time[sample_count] = buffer[i] / 32768.0f;                //        Mic1: current sample
        mic2_time[sample_count] = delayBuffer[delayIndex] / 32768.0f; //        Mic2: delayed version (emulated)
        
        // Update delay buffer
        delayBuffer[delayIndex] = buffer[i];
        delayIndex = (delayIndex + 1) % DELAY_SAMPLES;
        
        sample_count++;
      }
    }
    
    queueMic1.freeBuffer();
    
    // When buffer is full, mark ready for FFT processing
    if (sample_count >= FFT_SIZE && !fft_ready) {
      computeFFTAndPhase(mic1_time, mic1_fft, mic1_magnitude, mic1_phase);
      computeFFTAndPhase(mic2_time, mic2_fft, mic2_magnitude, mic2_phase);
      run_gcc_phat(mic1_fft, mic2_fft);
      fft_ready = true;
      sample_count = 0;  // Reset immediately to start collecting next frame
    }
  }
  
  // Original display code - runs when both FFTs are available
  //if (peak.available() && fft.available() && fft_ready) {
  if (fft_ready) {
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
  
    // Send data to serial - now using ARM FFT results
    // Format: MIC1_MAG,MIC1_PHASE,MIC2_MAG,MIC2_PHASE (alternating)
    Serial.println("FFT_DATA_START");
    
    // Send Mic1 FFT (magnitude and phase interleaved)
    Serial.print("CORR:");
    // for(int i = 0; i < NUM_FFT_BINS ; i++) {
    //   Serial.print(mic1_magnitude[i], 6);
    //   // Serial.print(mic2_magnitude[i], 6);
    //   if(i < NUM_FFT_BINS  - 1) {
    //     Serial.print(",");
    //   }
    // }
    for(int i = 0; i < FFT_SIZE; i++) {
      Serial.print(correlation_result[i], 6);
      // Serial.print(mic1_magnitude[i], 6);
      // Serial.print(mic2_magnitude[i], 6);
      //Serial.print(",");
      //Serial.print(mic1_phase[i], 6);
      if(i < FFT_SIZE - 1) {
        Serial.print(",");
      }
    }

    
    Serial.println();
    
    // // Send Mic2 FFT (magnitude and phase interleaved)
    // Serial.print("MIC2:");
    // for(int i = 0; i < NUM_FFT_BINS; i++) {
    //   Serial.print(correlation_result[i+512], 6);
    //   //Serial.print(mic2_magnitude[i], 6);
    //   //Serial.print(",");
    //   //Serial.print(mic2_phase[i], 6);
    //   if(i < NUM_FFT_BINS - 1) {
    //     Serial.print(",");
    //   }
    // }
    // Serial.println();
    
    Serial.println("FFT_DATA_END");
    
    fft_ready = false;  // Reset flag
  }
}
