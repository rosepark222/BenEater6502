#include <Arduino.h>
#include <Audio.h>
#include <Wire.h>
#include <U8g2lib.h>
#include <arm_math.h>
#include <math.h>

#define MODE_FFT 0
#define MODE_CORR_01 1
#define MODE_EYE 2
#define MODE_GAME 3
#define MODE_CORR_23 4

// ------------------ Pins ------------------
const int MIC1_LED = 13;
const int MIC2_LED = 14;
const int MIC3_LED = 15;

// MODE SWITCHING: Current mode and pending mode change
int debug_mode = MODE_EYE;
int pending_mode = -1; // -1 means no pending mode change

// MODE SWITCHING: Buffer management for receiving commands from host
String commandBuffer = "";
bool newCommand = false;

// DEBUG: Heartbeat to show Teensy is alive
unsigned long lastHeartbeat = 0;
const unsigned long HEARTBEAT_INTERVAL = 200000; // 200 seconds

// ------------------ Audio objects ------------------
AudioInputI2SQuad      i2s_quad;  

//AudioInputI2S           i2sMic;
AudioFilterBiquad       dcBlocker0;
AudioFilterBiquad       dcBlocker1; 
AudioFilterBiquad       dcBlocker2;
AudioFilterBiquad       dcBlocker3;

AudioAnalyzePeak        peak0, peak1, peak2, peak3;
//AudioAnalyzeFFT1024     fft;  // Keep for display
AudioRecordQueue        queueMic0;  // Left channel (mic1)
AudioRecordQueue        queueMic1;  // mic2 added - Right channel (mic2)
AudioRecordQueue        queueMic2;  // Left channel (mic1)
AudioRecordQueue        queueMic3;  // mic2 added - Right channel (mic2)

//AudioConnection         patchCord1(i2sMic, 0, dcBlocker, 0);
AudioConnection          patchCord1_0(i2s_quad, 0, dcBlocker0, 0); 
AudioConnection          patchCord1_1(i2s_quad, 1, dcBlocker1, 0); 
AudioConnection          patchCord1_2(i2s_quad, 2, dcBlocker2, 0); 
AudioConnection          patchCord1_3(i2s_quad, 3, dcBlocker3, 0); 

AudioConnection         patchCord21(dcBlocker0, 0, peak0, 0);
AudioConnection         patchCord22(dcBlocker1, 0, peak1, 0);
AudioConnection         patchCord23(dcBlocker2, 0, peak2, 0);
AudioConnection         patchCord24(dcBlocker3, 0, peak3, 0);

//AudioConnection         patchCord3(dcBlocker, 0, fft, 0);
AudioConnection         patchCord4(dcBlocker0, 0, queueMic0, 0);  // Left channel to queue
AudioConnection         patchCord5(dcBlocker1, 0, queueMic1, 0);  // mic2 added - Right channel to queue
AudioConnection         patchCord6(dcBlocker2, 0, queueMic2, 0);  // mic2 added - Right channel to queue
AudioConnection         patchCord7(dcBlocker3, 0, queueMic3, 0);  // mic2 added - Right channel to queue

// AudioConnection         patchCord5(i2sMic, 1, dcBlocker2, 0);  // mic2 added - Right channel
//AudioConnection          patchCord3(i2s_quad, 2, dcBlocker2, 0); 

//AudioConnection         patchCord6(dcBlocker2, 0, queueMic2, 0);  // mic2 added - Right channel to queue

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
// #define DELAY_SAMPLES 13  // mic2 added - No longer needed with dual I2S channels

// ARM CMSIS FFT instance
arm_rfft_fast_instance_f32 fft_inst;

// Hann window coefficients
float hann_window[FFT_SIZE];

float mic0_time[FFT_SIZE];
float mic0_fft[FFT_SIZE * 2]; // 1024 complex 
float mic0_magnitude[FFT_BINS];
float mic0_phase[FFT_BINS];

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

// Mic2 buffers (delayed version)
float mic3_time[FFT_SIZE];
float mic3_fft[FFT_SIZE * 2]; // 1024 complex 
float mic3_magnitude[FFT_BINS];
float mic3_phase[FFT_BINS];

// Mic2 buffers (delayed version)

float cross_spectrum01[FFT_SIZE]; // X(f)X2*(f) / |X(f)X2*(f)|
float correlation_result01[FFT_SIZE]; // Final time domain result (size FFT_SIZE)

float cross_spectrum02[FFT_SIZE]; // X(f)X2*(f) / |X(f)X2*(f)|
float correlation_result02[FFT_SIZE]; // Final time domain result (size FFT_SIZE)

float cross_spectrum03[FFT_SIZE]; // X(f)X2*(f) / |X(f)X2*(f)|
float correlation_result03[FFT_SIZE]; // Final time domain result (size FFT_SIZE)

float cross_spectrum23[FFT_SIZE]; // X(f)X2*(f) / |X(f)X2*(f)|
float correlation_result23[FFT_SIZE]; // Final time domain result (size FFT_SIZE)

// mic2 added - Delay buffer no longer needed
// int16_t delayBuffer[DELAY_SAMPLES];
// int delayIndex = 0;

int sample_count = 0;
bool fft_ready = false;

float tukeyTable[FFT_SIZE];
float alpha = 0.5; // Tapering parameter

void generateTukey() {
    float taperSamples = alpha * (FFT_SIZE - 1) / 2.0;
    for (int n = 0; n < FFT_SIZE; n++) {
        if (n < taperSamples) {
            // Left cosine taper
            tukeyTable[n] = 0.5 * (1 + cos(M_PI * ( (2.0 * n / (alpha * (FFT_SIZE - 1))) - 1)));
        } else if (n > (FFT_SIZE - 1 - taperSamples)) {
            // Right cosine taper
            tukeyTable[n] = 0.5 * (1 + cos(M_PI * ( (2.0 * n / (alpha * (FFT_SIZE - 1))) - (2.0 / alpha) + 1)));
        } else {
            // Middle flat section
            tukeyTable[n] = 1.0;
        }
    }
}

void generateHann() {
    for (int i = 0; i < FFT_SIZE; i++) {
    hann_window[i] = 0.5 * (1.0 - cosf(2.0 * PI * i / (FFT_SIZE - 1)));
    }
  
}

void computeFFTAndPhase(float* input, float* fft_output, float* magnitude, float* phase) {
  // Apply Hann window before FFT
  float windowed_input[FFT_SIZE];
  for (int i = 0; i < FFT_SIZE; i++) {
    // windowed_input[i] = input[i] * hann_window[i];
    windowed_input[i] = input[i] * tukeyTable[i];   
  }
  
  // Perform FFT
  arm_rfft_fast_f32(&fft_inst, windowed_input, fft_output, 0);
  
  // Calculate magnitude and phase for each bin
  for (int i = 0; i < FFT_BINS; i++) {
    float real = fft_output[i * 2];
    float imag = fft_output[i * 2 + 1];
    
    magnitude[i] = sqrtf(real * real + imag * imag) / FFT_SIZE;
    phase[i] = atan2f(imag, real);
  }
}
 
void run_gcc_phat(float* fft1, float* fft2, float *cross_spectrum, float *correlation_result) {
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

/*
| PSR value | Interpretation          |
| --------- | ----------------------- |
| < 4       | noise / heavy multipath |
| 4–6       | weak / ambiguous        |
| 6–8       | usable                  |
| > 8       | strong direct path      |
| > 15      | very clean impulse      |

*/
float psr(float *correlation_result, int max_idx, int fft_size)
{
    const int EXCLUDE = 4;     // exclude ±4 bins around main peak
    float sum = 0.0f;
    float sumsq = 0.0f;
    int count = 0;

    for (int i = 0; i < fft_size; i++) {
        if (abs(i - max_idx) <= EXCLUDE)
            continue;

        float v = correlation_result[i];
        sum += v;
        sumsq += v * v;
        count++;
    }

    if (count < 2)
        return 0.0f;

    float mean = sum / count;
    float var  = (sumsq / count) - (mean * mean);
    if (var < 1e-12f)
        var = 1e-12f;

    float std = sqrtf(var);

    return (correlation_result[max_idx] - mean) / std;
}

// MODE SWITCHING: Check for incoming serial commands (non-blocking)
// This reads characters from serial and buffers them until newline is received
void checkSerialCommand() {
  while (Serial.available() > 0) {
    char inChar = (char)Serial.read();
    
    // DEBUG: Blink LED when receiving serial data
    digitalWrite(LED_BUILTIN, HIGH);
    
    // Check for command terminator (newline or carriage return)
    if (inChar == '\n' || inChar == '\r') {
      if (commandBuffer.length() > 0) {
        newCommand = true; // Flag that we have a complete command
        // DEBUG: Double blink when command complete
        digitalWrite(LED_BUILTIN, LOW);
        delay(50);
        digitalWrite(LED_BUILTIN, HIGH);
        delay(50);
        digitalWrite(LED_BUILTIN, LOW);
      }
    } else {
      commandBuffer += inChar; // Accumulate characters into command buffer
    }
  }
  digitalWrite(LED_BUILTIN, LOW);
}

// MODE SWITCHING: Process received command and send acknowledgment
// BUFFER CORRUPTION PREVENTION: Only sets pending_mode, actual switch happens after current frame completes
void processCommand() {
  if (!newCommand) return; // No new command to process
  
  // DEBUG: Show what command we received
  Serial.print("DEBUG:Received command: '");
  Serial.print(commandBuffer);
  Serial.println("'");
  
  commandBuffer.trim(); // Remove any whitespace
  commandBuffer.toUpperCase(); // Convert to uppercase for consistency
  
  // DEBUG: Show after trimming
  Serial.print("DEBUG:After trim: '");
  Serial.print(commandBuffer);
  Serial.println("'");
  
  // HANDSHAKE: Parse command and set pending mode change
  if (commandBuffer == "MODE_FFT") {
    pending_mode = MODE_FFT; // Don't switch immediately - wait for frame to complete
    Serial.println("ACK:MODE_FFT"); // Send acknowledgment to host
    Serial.println("DEBUG:Set pending_mode to MODE_FFT");
  } 
  else if (commandBuffer == "MODE_CORR_01") {
    pending_mode = MODE_CORR_01;
    Serial.println("ACK:MODE_CORR_01");
    Serial.println("DEBUG:Set pending_mode to MODE_CORR_01");
  }
  else if (commandBuffer == "MODE_EYE") {
    pending_mode = MODE_EYE;
    Serial.println("ACK:MODE_EYE");
    Serial.println("DEBUG:Set pending_mode to MODE_EYE");
  }
  else if (commandBuffer == "MODE_GAME") {
    pending_mode = MODE_GAME;
    Serial.println("ACK:MODE_GAME");
    Serial.println("DEBUG:Set pending_mode to MODE_GAME");
  }
  else if (commandBuffer == "MODE_CORR_23") {
    pending_mode = MODE_CORR_23;
    Serial.println("ACK:MODE_CORR_23");
    Serial.println("DEBUG:Set pending_mode to MODE_CORR_23");
  }
  else if (commandBuffer == "STATUS") {
    // Report current mode without changing anything
    Serial.print("CURRENT_MODE:");
    Serial.println(debug_mode);
  }
  else {
    // Unknown command
    Serial.println("ERROR:UNKNOWN_COMMAND");
    Serial.print("DEBUG:Unknown command length: ");
    Serial.println(commandBuffer.length());
    Serial.println("VALID_COMMANDS: MODE_FFT, MODE_CORR_??, MODE_EYE, MODE_GAME, STATUS");
  }
  
  // BUFFER CORRUPTION PREVENTION: Clear command buffer and flag immediately after processing
  commandBuffer = "";
  newCommand = false;
}

void setup() {
  Serial.begin(115200);
  
  // Wait a moment for serial to initialize
  delay(100);
  
  pinMode(MIC1_LED, OUTPUT);
  pinMode(MIC2_LED, OUTPUT);
  pinMode(MIC3_LED, OUTPUT);
  pinMode(LED_BUILTIN, OUTPUT); // DEBUG: Use built-in LED for debugging
  /*
  Each audio block is a fixed size: 128 samples of 16-bit data (2 bytes per sample). 
  The total buffer size allocated by that call is: 
   Total Samples: 20 blocks x 128 samples/block = 2560 samples
   Total Memory: 20 blocks x 256 bytes/block = 5120 bytes (5kb)

   Let's add it up conservatively:

Component	Blocks
FFT accumulation (1024 × 4)	32
FFT working buffers	48
I2SQuad buffering	12
System overhead	12
Total	104 blocks

  */
  AudioMemory(128);  // mic2 added - Increased from 20 to 30 for dual channel recording
  
  // Initialize ARM FFT
  arm_rfft_fast_init_f32(&fft_inst, FFT_SIZE);
  
  // Initialize Hann window coefficients
  generateTukey();
  generateHann();

  // Configure DC blocking filter
  dcBlocker0.setHighpass(0, 20, 0.707);
  dcBlocker1.setHighpass(0, 20, 0.707);  
  dcBlocker2.setHighpass(0, 20, 0.707);
  dcBlocker3.setHighpass(0, 20, 0.707);  

  // mic2 added - Delay buffer initialization no longer needed
  // for (int i = 0; i < DELAY_SAMPLES; i++) {
  //   delayBuffer[i] = 0;
  // }
  
  // Start recording queue
  queueMic0.begin(); 
  queueMic1.begin();
  queueMic2.begin();  // mic2 added - Start right channel queue
  queueMic3.begin();

  oled.begin();
  oled.clearBuffer();
  oled.setFont(u8g2_font_ncenB08_tr);
  oled.drawStr(0, 10, "Setup done");
  oled.sendBuffer();
  
  Serial.println("Setup complete - ARM FFT initialized with Hann window");
  Serial.println("READY"); // Tell host we're ready for commands
  Serial.println("Send commands: MODE_FFT, MODE_CORR, MODE_EYE, MODE_GAME, STATUS");
}

void loop() {
  // MODE SWITCHING: Check for incoming mode change commands every loop iteration
  checkSerialCommand();
  processCommand();
  
  // DEBUG: Send heartbeat to show Teensy is running
  unsigned long now = millis();
  if (now - lastHeartbeat > HEARTBEAT_INTERVAL) {
    Serial.print("HEARTBEAT:mode=");
    Serial.print(debug_mode);
    Serial.print(",pending=");
    Serial.print(pending_mode);
    Serial.print(",fft_ready=");
    Serial.print(fft_ready);
    Serial.print(",sample_count=");
    Serial.println(sample_count);
    lastHeartbeat = now;
  }
  
  // Run main audio processing
  loop_gcc_phat(); 
}

void loop_gcc_phat() {
  while (queueMic0.available() && queueMic1.available()  && queueMic2.available() && queueMic3.available()) {
    int16_t *buffer0 = queueMic0.readBuffer();
    int16_t *buffer1 = queueMic1.readBuffer();
    int16_t *buffer2 = queueMic2.readBuffer();
    int16_t *buffer3 = queueMic3.readBuffer();

    for (int i = 0; i < 128; i++) {
      if (sample_count < FFT_SIZE) {
        // The data is divided by 32768.0f to normalize the raw audio samples 
	// from a 16-bit signed integer range into a floating-point range of -1.0 to 1.0.
        mic0_time[sample_count] = buffer0[i] / 32768.0f;
        mic1_time[sample_count] = buffer1[i] / 32768.0f;
        mic2_time[sample_count] = buffer2[i] / 32768.0f;
        mic3_time[sample_count] = buffer3[i] / 32768.0f;
        sample_count++;
      }
    }
    queueMic0.freeBuffer();
    queueMic1.freeBuffer();  // mic2 added - Free right channel buffer
    queueMic2.freeBuffer();
    queueMic3.freeBuffer(); 
    // When buffer is full, mark ready for FFT processing
    if (sample_count >= FFT_SIZE && !fft_ready) {
      fft_ready = true;
      sample_count = 0;  // Reset immediately to start collecting next frame
    }
  }
  
  // Original display code - runs when both FFTs are available
  if (fft_ready) {
      computeFFTAndPhase(mic0_time, mic0_fft, mic0_magnitude, mic0_phase);
      computeFFTAndPhase(mic1_time, mic1_fft, mic1_magnitude, mic1_phase);
      computeFFTAndPhase(mic2_time, mic2_fft, mic2_magnitude, mic2_phase);
      computeFFTAndPhase(mic3_time, mic3_fft, mic3_magnitude, mic3_phase);
      run_gcc_phat(mic0_fft, mic1_fft, cross_spectrum01, correlation_result01);
      run_gcc_phat(mic0_fft, mic2_fft, cross_spectrum02, correlation_result02);
      run_gcc_phat(mic0_fft, mic3_fft, cross_spectrum03, correlation_result03);
      run_gcc_phat(mic2_fft, mic3_fft, cross_spectrum23, correlation_result23);

      // BUFFER CORRUPTION PREVENTION: Apply pending mode change ONLY after frame is complete
      // This ensures we don't switch modes mid-frame, which would cause corrupt/mixed data
      if (pending_mode != -1) {
        debug_mode = pending_mode; // Apply the mode change now that frame is done
        Serial.print("MODE_CHANGED:"); // Notify host that mode switch is complete
        Serial.println(debug_mode);
        pending_mode = -1; // Clear pending flag
      }

      /*
      *  MODE: MODE_FFT - Send 512 FFT magnitude bins
      *
      */
      if(debug_mode == MODE_FFT) {      
        Serial.println("FFT_START"); // Start marker for FFT data packet
        for(int i = 0; i < FFT_BINS; i++) {
          Serial.print(mic0_magnitude[i], 6); // Send magnitude with 6 decimal places
          //Serial.print(mic1_magnitude[i], 6);
          //Serial.print(mic2_magnitude[i], 6);
          //Serial.print(mic3_magnitude[i], 6);
          if(i < FFT_BINS - 1) {Serial.print(",");} // Comma-separated values
        }
        Serial.println(); // End of data line
        Serial.println("FFT_END"); // End marker for FFT data packet
      
      /*
      *  MODE: MODE_CORR_01 - Send only 21 values around peak (optimization)
      *
      */
      } else if(debug_mode == MODE_CORR_01 || debug_mode == MODE_CORR_23) {
        float *p = NULL;
        if(debug_mode == MODE_CORR_01) {
          p = correlation_result01;
        } else if (debug_mode == MODE_CORR_23) {
          p = correlation_result23;
        }

        // Find peak in correlation result first
        float corr_max_value = -1;
        int corr_max_idx = -1;
        for(int i = 0; i < FFT_SIZE; i++) {
          if(p[i] > corr_max_value) {
            corr_max_value = p[i];
            corr_max_idx = i;
          }
        }
        
        Serial.println("CORR_START"); // Start marker for correlation data packet
        
        // Send peak index and value first
        Serial.print(corr_max_idx);
        Serial.print(",");
        Serial.print(corr_max_value, 6);
        
        // Send 10 values to the left of peak (or less if near boundary)
        int left_start = max(0, corr_max_idx - 10);
        int left_count = corr_max_idx - left_start;
        Serial.print(",");
        Serial.print(left_count); // How many left values
        for(int i = left_start; i < corr_max_idx; i++) {
          Serial.print(",");
          Serial.print(p[i], 6);
        }
        
        // Send 10 values to the right of peak (or less if near boundary)
        int right_end = min(FFT_SIZE - 1, corr_max_idx + 10);
        int right_count = right_end - corr_max_idx;
        Serial.print(",");
        Serial.print(right_count); // How many right values
        for(int i = corr_max_idx + 1; i <= right_end; i++) {
          Serial.print(",");
          Serial.print(p[i], 6);
        }
        
        Serial.println(); // End of data line
        Serial.println("CORR_END"); // End marker for correlation data packet
      
      /*
      *  MODE: MODE_EYE and MODE_GAME - Send PHAT peak detection data
      *
      */
      }  else if(debug_mode == MODE_EYE || debug_mode == MODE_GAME ) {
        float mic01_max_value    = -1; int mic01_max_idx    = -1; 
        float mic01_second_value = -1; int mic01_second_idx = -1;
        float mic23_max_value    = -1; int mic23_max_idx    = -1; 
        float mic23_second_value = -1; int mic23_second_idx = -1;
 
        // Find peak and second peak in correlation results
        for(int i = 0; i < FFT_SIZE; i++) {
          if(correlation_result01[i] > mic01_max_value) {
            mic01_second_value = mic01_max_value;
            mic01_second_idx = mic01_max_idx;
            mic01_max_value =  correlation_result01[i];
            mic01_max_idx = i;
          } else if(correlation_result01[i] > mic01_second_value && correlation_result01[i] != mic01_max_value) {
            mic01_second_value = correlation_result01[i];
            mic01_second_idx = i;
          }

          if(correlation_result23[i] > mic23_max_value) {
            mic23_second_value = mic23_max_value;
            mic23_second_idx = mic23_max_idx;
            mic23_max_value =  correlation_result23[i];
            mic23_max_idx = i;
          } else if(correlation_result23[i] > mic23_second_value && correlation_result23[i] != mic23_max_value) {
            mic23_second_value = correlation_result23[i];
            mic23_second_idx = i;
          }
        }

        // Calculate Peak-to-Sidelobe Ratio for signal quality
        float psr01 = psr(correlation_result01, mic01_max_idx, FFT_SIZE); 
        float psr23 = psr(correlation_result23, mic23_max_idx, FFT_SIZE); 
        
        //float threshold = 0.15;
        //if (mic01_max_value > threshold && mic23_max_value > threshold) {
        
        // Shift indices to represent negative delays (indices > 512 represent negative delays)
        int mic01_max_shifted_idx = mic01_max_idx > 512 ? mic01_max_idx -1024 : mic01_max_idx;
        int mic01_second_shifted_idx = mic01_second_idx > 512 ? mic01_second_idx -1024 : mic01_second_idx;
        int mic23_max_shifted_idx = mic23_max_idx > 512 ? mic23_max_idx -1024 : mic23_max_idx;
        int mic23_second_shifted_idx = mic23_second_idx > 512 ? mic23_second_idx -1024 : mic23_second_idx;
 
        Serial.println("PHAT_START"); // Start marker for PHAT data packet
        // Send: peak_value, peak_idx, second_value, second_idx, psr for both mic pairs
        Serial.printf("%.6f, %5d, %.6f, %5d, %.6f, %.6f, %5d, %.6f, %5d, %.6f\n", 
          mic01_max_value, mic01_max_shifted_idx, mic01_second_value, mic01_second_shifted_idx, psr01, 
          mic23_max_value, mic23_max_shifted_idx, mic23_second_value, mic23_second_shifted_idx, psr23);
        Serial.println("PHAT_END"); // End marker for PHAT data packet

        //}
      } 

      fft_ready = false;  // Reset flag
  } // if (fft_ready)
} // void loop_gcc_phat()
