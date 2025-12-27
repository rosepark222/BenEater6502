#include <Arduino.h>
#include <Audio.h>
#include <Wire.h>
#include <U8g2lib.h>
#include <arm_math.h>

// ------------------ Pins ------------------
const int MIC1_LED = 13;
const int MIC2_LED = 14;
const int MIC3_LED = 15;


int debug_mode = 1; // 1: send to processing, 2: print max_value and index, 
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

void setup() {
  Serial.begin(115200);
  pinMode(MIC1_LED, OUTPUT);
  pinMode(MIC2_LED, OUTPUT);
  pinMode(MIC3_LED, OUTPUT);
  /*
  Each audio block is a fixed size: 128 samples of 16-bit data (2 bytes per sample). 
  The total buffer size allocated by that call is: 
   Total Samples: 20 blocks x 128 samples/block = 2560 samples
   Total Memory: 20 blocks x 256 bytes/block = 5120 bytes (5kb)

   Let’s add it up conservatively:

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
}

void loop() {
   //loop_digital_life_check_test();  // test 1
   //loop_DC_offset_stuck_bit_test(); // test 2
   //loop_1khz_tone_injection_test(); // test 3
   //loop_check_clock_sanity_by_fft_sum_test(); // test 4

   loop_sanity_fft_draw();
}



/*
2️⃣ Test #1 — “Digital life check” (no audio processing)

Goal: Verify I2S data toggles correctly.

Code:
void loop() {
  Serial.println(micPeak.read(), 6);
  delay(50);
}

Expected:

Silence: stable low value (~0.002–0.01)

Tap mic: value jumps immediately

Failure modes
Observation	        Likely cause
Always zero	DATA    line dead
Random spikes	      Clock integrity
Freezes	             I2S clock loss


 

breadboard result 
 
 
peak: 0.000610, 0.000885, 0.000763, 0.000946  max : 0.000580, 0.000885, 0.000854, 0.000793
peak: 0.000610, 0.000977, 0.000824, 0.000855  max : 0.000641, 0.001099, 0.000824, 0.000977
peak: 0.000671, 0.001007, 0.000793, 0.000977  max : 0.000641, 0.000885, 0.000885, 0.000977
peak: 0.000580, 0.000916, 0.000671, 0.000916  max : 0.000610, 0.001068, 0.000793, 0.000977
peak: 0.001038, 0.001251, 0.000977, 0.001129  max : 0.000610, 0.000793, 0.000702, 0.000793
peak: 0.000641, 0.001007, 0.000824, 0.000946  max : 0.000610, 0.001007, 0.000793, 0.000916
peak: 0.000610, 0.001007, 0.000916, 0.001007  max : 0.000641, 0.001007, 0.000793, 0.000977
peak: 0.000549, 0.000946, 0.000732, 0.000885  max : 0.000549, 0.000916, 0.000702, 0.000793
peak: 0.000732, 0.000977, 0.000977, 0.000946  max : 0.000702, 0.000946, 0.000763, 0.000916
peak: 0.000519, 0.000977, 0.000885, 0.000885  max : 0.000641, 0.000916, 0.000793, 0.001007
peak: 0.000488, 0.000793, 0.000793, 0.000793  max : 0.000610, 0.000854, 0.000793, 0.000946
peak: 0.000549, 0.001038, 0.000702, 0.000916  max : 0.000732, 0.001007, 0.000793, 0.001038
peak: 0.000488, 0.000763, 0.000793, 0.000824  max : 0.000671, 0.001038, 0.000885, 0.001007
peak: 0.000122, 0.001007, 0.000763, 0.000763  max : 0.001038, 0.001221, 0.001312, 0.001068
peak: 0.764153, 0.002045, 0.002075, 0.000671  max : 0.000610, 0.000916, 0.000824, 0.000916  **** _peak_ on tapping erp029
peak: 0.176244, 0.000824, 0.000336, 0.000336  max : 0.000641, 0.000916, 0.000824, 0.000916
peak: 0.167089, 0.000366, 0.000214, 0.000855  max : 0.000580, 0.000793, 0.000732, 0.000793
peak: 0.327860, 0.000275, 0.000183, 0.000946  max : 0.000641, 0.000793, 0.000824, 0.000977
peak: 0.260628, 0.006348, 0.009278, 0.007172  max : 0.000519, 0.000763, 0.000732, 0.000885
peak: 0.498795, 0.002655, 0.000671, 0.001617  max : 0.000641, 0.000885, 0.000824, 0.000916
peak: 0.312235, 0.002380, 0.000244, 0.001007  max : 0.000610, 0.000732, 0.000763, 0.000946
peak: 0.116459, 0.002655, 0.000122, 0.000641  max : 0.000702, 0.001007, 0.000916, 0.001129
peak: 0.088260, 0.003693, 0.001221, 0.003479  max : 0.000580, 0.000702, 0.000763, 0.000580
peak: 0.092898, 0.002838, 0.000702, 0.000366  max : 0.000641, 0.000854, 0.000793, 0.000977
peak: 0.113651, 0.001801, 0.000336, 0.000305  max : 0.000610, 0.000732, 0.000793, 0.000824
peak: 0.117557, 0.000977, 0.000153, 0.000793  max : 0.000641, 0.000916, 0.000763, 0.000977
peak: 0.104984, 0.001099, 0.000183, 0.000702  max : 0.000671, 0.001007, 0.000763, 0.001007
peak: 0.083560, 0.000671, 0.000244, 0.000702  max : 0.000824, 0.001251, 0.000854, 0.001068
peak: 0.059877, 0.000336, 0.000183, 0.000641  max : 0.000641, 0.001251, 0.000824, 0.000885
peak: 0.039064, 0.000092, 0.000092, 0.000763  max : 0.000793, 0.000824, 0.000916, 0.000977
peak: 0.021088, 0.000244, 0.000183, 0.000763  max : 0.000641, 0.000763, 0.000763, 0.000946
peak: 0.008301, 0.000458, 0.000305, 0.000580  max : 0.000610, 0.000885, 0.000763, 0.000946
peak: 0.007721, 0.000580, 0.000183, 0.000549  max : 0.000610, 0.000977, 0.000824, 0.000854
peak: 0.010254, 0.000610, 0.000092, 0.000793  max : 0.000671, 0.001007, 0.000793, 0.000977
peak: 0.011292, 0.000549, 0.000214, 0.000732  max : 0.000580, 0.000916, 0.000671, 0.000916
peak: 0.010041, 0.000763, 0.000183, 0.000671  max : 0.001038, 0.001251, 0.000977, 0.001129
peak: 0.009156, 0.000763, 0.000122, 0.000671  max : 0.000641, 0.001007, 0.000824, 0.000946
peak: 0.007569, 0.000824, 0.000153, 0.000641  max : 0.000610, 0.001007, 0.000916, 0.001007
peak: 0.006561, 0.000671, 0.000183, 0.000580  max : 0.000549, 0.000946, 0.000732, 0.000885
peak: 0.005890, 0.000855, 0.000275, 0.000702  max : 0.000732, 0.000977, 0.000977, 0.000946
peak: 0.005036, 0.000702, 0.000214, 0.000488  max : 0.000519, 0.000977, 0.000885, 0.000885
peak: 0.004151, 0.000793, 0.000183, 0.000671  max : 0.000488, 0.000793, 0.000793, 0.000793
peak: 0.003510, 0.000824, 0.000244, 0.000641  max : 0.000549, 0.001038, 0.000702, 0.000916
peak: 0.002716, 0.001007, 0.000153, 0.000763  max : 0.000488, 0.000763, 0.000793, 0.000824
peak: 0.002136, 0.000946, 0.000305, 0.000641  max : 0.000122, 0.001007, 0.000763, 0.000763
peak: 0.001526, 0.000946, 0.000458, 0.000732  max : 0.764130, 0.002045, 0.002075, 0.000671   **** _peak_ erp029
peak: 0.000702, 0.000885, 0.000458, 0.000671  max : 0.176239, 0.000824, 0.000336, 0.000336
peak: 0.000488, 0.001007, 0.000519, 0.000763  max : 0.167084, 0.000366, 0.000214, 0.000854
peak: 0.000153, 0.000885, 0.000610, 0.000610  max : 0.327850, 0.000275, 0.000183, 0.000946
peak: 0.000549, 0.000885, 0.000641, 0.000793  max : 0.260620, 0.006348, 0.009277, 0.007172
peak: 0.000916, 0.000793, 0.000671, 0.000732  max : 0.498779, 0.002655, 0.000671, 0.001617
peak: 0.001160, 0.000916, 0.000671, 0.000671  max : 0.312225, 0.002380, 0.000244, 0.001007
peak: 0.001404, 0.000793, 0.000763, 0.000641  max : 0.116455, 0.002655, 0.000122, 0.000641
peak: 0.001373, 0.000977, 0.000916, 0.000855  max : 0.088257, 0.003693, 0.001221, 0.003479
peak: 0.000824, 0.000793, 0.000763, 0.000641  max : 0.092896, 0.002838, 0.000702, 0.000366
peak: 0.000702, 0.000732, 0.000824, 0.000641  max : 0.113647, 0.001801, 0.000336, 0.000305
peak: 0.000244, 0.000885, 0.000916, 0.000671  max : 0.117554, 0.000977, 0.000153, 0.000793
peak: 0.000153, 0.000977, 0.001007, 0.000793  max : 0.104980, 0.001099, 0.000183, 0.000702
peak: 0.000183, 0.000793, 0.000824, 0.000732  max : 0.083557, 0.000671, 0.000244, 0.000702
peak: 0.000305, 0.000793, 0.000855, 0.000610  max : 0.059875, 0.000336, 0.000183, 0.000641
peak: 0.000336, 0.001007, 0.000855, 0.000610  max : 0.039062, 0.000092, 0.000092, 0.000763
peak: 0.000397, 0.000793, 0.000916, 0.000641  max : 0.021088, 0.000244, 0.000183, 0.000763
peak: 0.000580, 0.000855, 0.000824, 0.000549  max : 0.008301, 0.000458, 0.000305, 0.000580
peak: 0.000549, 0.001007, 0.000916, 0.000580  max : 0.007721, 0.000580, 0.000183, 0.000549
peak: 0.000519, 0.001007, 0.000885, 0.000580  max : 0.010254, 0.000610, 0.000092, 0.000793
peak: 0.000488, 0.000824, 0.000824, 0.000610  max : 0.011292, 0.000549, 0.000214, 0.000732
peak: 0.000427, 0.000855, 0.000732, 0.000702  max : 0.010040, 0.000763, 0.000183, 0.000671
peak: 0.000519, 0.001068, 0.000916, 0.000580  max : 0.009155, 0.000763, 0.000122, 0.000671
peak: 0.000488, 0.001038, 0.000946, 0.000671  max : 0.007568, 0.000824, 0.000153, 0.000641
peak: 0.000549, 0.001007, 0.000824, 0.000580  max : 0.006561, 0.000671, 0.000183, 0.000580
peak: 0.000458, 0.001007, 0.000732, 0.000671  max : 0.005890, 0.000854, 0.000275, 0.000702
peak: 0.000732, 0.001038, 0.000855, 0.000702  max : 0.005035, 0.000702, 0.000214, 0.000488
peak: 0.000519, 0.000946, 0.000824, 0.000641  max : 0.004150, 0.000793, 0.000183, 0.000671
peak: 0.000458, 0.000824, 0.000702, 0.000610  max : 0.003510, 0.000824, 0.000244, 0.000641
peak: 0.000580, 0.001038, 0.000946, 0.000732  max : 0.002716, 0.001007, 0.000153, 0.000763
peak: 0.000580, 0.000946, 0.000946, 0.000671  max : 0.002136, 0.000946, 0.000305, 0.000641
peak: 0.000519, 0.001007, 0.000977, 0.000610  max : 0.001526, 0.000946, 0.000458, 0.000732
peak: 0.000549, 0.000855, 0.001007, 0.000671  max : 0.000702, 0.000885, 0.000458, 0.000671
peak: 0.000519, 0.000824, 0.000946, 0.000702  max : 0.000488, 0.001007, 0.000519, 0.000763
peak: 0.000885, 0.001038, 0.001068, 0.000763  max : 0.000153, 0.000885, 0.000610, 0.000610
peak: 0.000519, 0.001068, 0.000977, 0.000671  max : 0.000549, 0.000885, 0.000641, 0.000793
peak: 0.000488, 0.001007, 0.000855, 0.000702  max : 0.000916, 0.000793, 0.000671, 0.000732
peak: 0.000519, 0.000977, 0.000885, 0.000732  max : 0.001160, 0.000916, 0.000671, 0.000671
peak: 0.000549, 0.000793, 0.000946, 0.000671  max : 0.001404, 0.000793, 0.000763, 0.000641
peak: 0.000488, 0.000824, 0.001007, 0.000702  max : 0.001373, 0.000977, 0.000916, 0.000854
peak: 0.000671, 0.000793, 0.000977, 0.000763  max : 0.000824, 0.000793, 0.000763, 0.000641
peak: 0.000519, 0.000793, 0.000885, 0.000610  max : 0.000702, 0.000732, 0.000824, 0.000641
peak: 0.000763, 0.001007, 0.001068, 0.000732  max : 0.000244, 0.000885, 0.000916, 0.000671
peak: 0.000488, 0.000855, 0.000946, 0.000702  max : 0.000153, 0.000977, 0.001007, 0.000793
peak: 0.000732, 0.000793, 0.000916, 0.000702  max : 0.000183, 0.000793, 0.000824, 0.000732
peak: 0.000488, 0.000885, 0.000977, 0.000732  max : 0.000305, 0.000793, 0.000854, 0.000610

 

tetrahedron, 
tap on mic0 
peak: 0.000397, 0.000244, 0.000366, 0.000427  max : 0.000854, 0.001068, 0.000702, 0.000427
peak: 0.000916, 0.000275, 0.000763, 0.001312  max : 0.000854, 0.000580, 0.000549, 0.000275
peak: 0.000641, 0.000519, 0.000946, 0.001343  max : 0.000702, 0.000946, 0.000580, 0.000305
peak: 0.001099, 0.000732, 0.001007, 0.001495  max : 0.000916, 0.000885, 0.000610, 0.000275
peak: 0.000916, 0.000824, 0.001404, 0.001709  max : 0.000763, 0.000824, 0.000610, 0.000244
peak: 0.001068, 0.000732, 0.001007, 0.001617  max : 0.000854, 0.000793, 0.000519, 0.000214
peak: 0.001465, 0.000641, 0.000977, 0.001465  max : 0.000916, 0.001068, 0.000610, 0.000275
peak: 0.000855, 0.000763, 0.000977, 0.001465  max : 0.000763, 0.000946, 0.000641, 0.000183
peak: 0.221046, 0.003143, 0.002228, 0.003662  max : 0.000977, 0.000793, 0.000610, 0.000122
peak: 0.018311, 0.001038, 0.000793, 0.000885  max : 0.000977, 0.000977, 0.000641, 0.000305
peak: 0.088504, 0.000610, 0.001038, 0.002014  max : 0.001282, 0.001038, 0.000916, 0.000366
peak: 0.100223, 0.000397, 0.001129, 0.002197  max : 0.000732, 0.000946, 0.000641, 0.000366
peak: 0.077395, 0.000458, 0.001038, 0.002136  max : 0.001007, 0.000885, 0.000610, 0.000275
peak: 0.048128, 0.000275, 0.001038, 0.002045  max : 0.000427, 0.000763, 0.000610, 0.000366
peak: 0.023560, 0.000397, 0.001038, 0.002075  max : 0.001129, 0.000885, 0.000610, 0.000366
peak: 0.005676, 0.001587, 0.002503, 0.003906  max : 0.000275, 0.000824, 0.000580, 0.000397
peak: 0.012848, 0.002625, 0.003632, 0.004578  max : 0.000824, 0.000885, 0.000580, 0.000458

tap on mic1  

eak: 0.001190, 0.001221, 0.001648, 0.061312  max : 0.000885, 0.001099, 0.001373, 0.003418
peak: 0.000549, 0.000885, 0.000824, 0.006897  max : 0.001404, 0.001221, 0.001343, 0.003876
peak: 0.000610, 0.000916, 0.000885, 0.013825  max : 0.001251, 0.001160, 0.001312, 0.004028
peak: 0.001007, 0.001282, 0.001556, 0.008332  max : 0.000641, 0.000946, 0.000732, 0.003204
peak: 0.001587, 0.001587, 0.001953, 0.001282  max : 0.000671, 0.000885, 0.001251, 0.003418
peak: 0.000702, 0.000977, 0.001129, 0.003784  max : 0.001709, 0.001678, 0.001770, 0.004486
peak: 0.000427, 0.000641, 0.000916, 0.015748  max : 0.001160, 0.001099, 0.001343, 0.003723
peak: 0.000977, 0.001221, 0.001404, 0.021821  max : 0.000519, 0.000793, 0.000732, 0.003265
peak: 0.001434, 0.001343, 0.002106, 0.002014  max : 0.000458, 0.000885, 0.000885, 0.003174
peak: 0.001007, 0.000580, 0.001251, 0.002777  max : 0.001129, 0.001160, 0.001434, 0.003143
peak: 0.000671, 0.000641, 0.000855, 0.007050  max : 0.001007, 0.000946, 0.001038, 0.002045
peak: 0.000580, 0.001282, 0.001007, 0.083071  max : 0.000488, 0.000732, 0.000763, 0.001648
peak: 0.001312, 0.001251, 0.001892, 0.015473  max : 0.000275, 0.001251, 0.000824, 0.093201
peak: 0.001343, 0.001068, 0.001740, 0.025361  max : 0.000519, 0.001007, 0.001068, 0.063721
peak: 0.000641, 0.000763, 0.001099, 0.022034  max : 0.001160, 0.001068, 0.001465, 0.044312

mic1 and 3 are not consistent -- the below is tap on mic1 , which shows signal, but not consistent
peak: 0.000427, 0.000732, 0.000214, 0.000732  max : 0.001404, 0.032074, 0.000397, 0.001099
peak: 0.000122, 0.000305, 0.000244, 0.000458  max : 0.001007, 0.027557, 0.000214, 0.001007
peak: 0.000824, 0.000885, 0.000275, 0.001007  max : 0.001160, 0.018799, 0.000153, 0.000732
peak: 0.000763, 0.000885, 0.000244, 0.001099  max : 0.001099, 0.011261, 0.000275, 0.000946
peak: 0.000671, 0.001068, 0.000366, 0.001007  max : 0.001099, 0.004456, 0.000183, 0.000946
peak: 0.000275, 0.001160, 0.000275, 0.000824  max : 0.001373, 0.003418, 0.000183, 0.000977
peak: 0.000305, 0.000336, 0.000366, 0.000641  max : 0.001129, 0.003937, 0.000244, 0.001007
peak: 0.000763, 0.000580, 0.000610, 0.001099  max : 0.001129, 0.003845, 0.000153, 0.000885
peak: 0.000488, 0.000214, 0.000153, 0.000824  max : 0.001556, 0.004456, 0.000275, 0.001129
peak: 0.001495, 0.237251, 0.001373, 0.001038  max : 0.001495, 0.004395, 0.000305, 0.001099
peak: 0.000610, 0.032533, 0.000885, 0.001068  max : 0.001282, 0.004120, 0.000153, 0.000824
peak: 0.000366, 0.087985, 0.000610, 0.000855  max : 0.000977, 0.004333, 0.000244, 0.000793
peak: 0.000397, 0.085055, 0.000610, 0.000916  max : 0.000732, 0.004364, 0.000244, 0.000793
peak: 0.000427, 0.060579, 0.000671, 0.000793  max : 0.001495, 0.004456, 0.000366, 0.001099
peak: 0.000488, 0.036012, 0.000763, 0.000793  max : 0.001099, 0.003448, 0.000275, 0.000946
peak: 0.000366, 0.016358, 0.000732, 0.000763  max : 0.001038, 0.003174, 0.000214, 0.000977

tap on mic3 -- see 0.719077*
peak: 0.000855, 0.000977, 0.002106, 0.002625  max : 0.001160, 0.000610, 0.001617, 0.001129
peak: 0.000519, 0.000275, 0.000763, 0.001038  max : 0.000702, 0.000458, 0.002014, 0.001587
peak: 0.000519, 0.000305, 0.000671, 0.000732  max : 0.001099, 0.000549, 0.001709, 0.001556
peak: 0.000763, 0.000824, 0.001770, 0.001648  max : 0.001495, 0.000793, 0.001282, 0.001190
peak: 0.000305, 0.000153, 0.001007, 0.000610  max : 0.001434, 0.001526, 0.001801, 0.004028
peak: 0.002899, 0.002960, 0.003235, 0.003723  max : 0.001556, 0.001831, 0.001617, 0.002289
peak: 0.004730, 0.004059, 0.004883, 0.004608  max : 0.001404, 0.000946, 0.001465, 0.002258
peak: 0.005554, 0.004730, 0.003906, 0.719077* max : 0.004974, 0.003937, 0.005463, 0.005432
peak: 0.002258, 0.002472, 0.003998, 0.162175  max : 0.001526, 0.001862, 0.003204, 0.003204
peak: 0.002503, 0.002289, 0.003418, 0.150243  max : 0.003632, 0.003082, 0.004852, 0.005554
peak: 0.002106, 0.002106, 0.002014, 0.237922  max : 0.006409, 0.006500, 0.005615, 0.007843
peak: 0.001923, 0.001373, 0.001770, 0.205115  max : 0.005310, 0.005341, 0.004364, 0.007874
peak: 0.000305, 0.000275, 0.000519, 0.135624  max : 0.001007, 0.001404, 0.001373, 0.001495
peak: 0.001190, 0.000946, 0.000855, 0.072726  max : 0.001160, 0.001190, 0.000702, 0.000977
peak: 0.000916, 0.000885, 0.000458, 0.021577  max : 0.002411, 0.002289, 0.000946, 0.000763
peak: 0.001190, 0.001007, 0.000916, 0.028657  max : 0.001648, 0.001953, 0.000610, 0.001007
peak: 0.001251, 0.000946, 0.000732, 0.036744  max : 0.001984, 0.002075, 0.000763, 0.001251
peak: 0.001251, 0.000977, 0.001923, 0.042482  max : 0.001862, 0.001984, 0.000610, 0
*/
void loop_digital_life_check_test() {

  float mic0_max=-1;
  float mic1_max=-1;
  float mic2_max=-1;
  float mic3_max=-1;

/*

The Teensy Audio Library processes audio in fixed blocks:

Block size: 128 samples
Sample rate: 44,100 Hz
Block duration:
128 / 44100 ≈ 2.9 ms

queueMicX.available() > 0 --- true if there is at least one block  

This while loop is for FFT matching:
 wait until all 4 queues have at least one block
If one mic lags → everything waits
This increases effective latency jitter

That’s fine for FFT batching, but not for timing comparison with peak.
*/
  while (queueMic0.available() && queueMic1.available()  && queueMic2.available() && queueMic3.available()) {  // mic2 added - Check both queues
    int16_t *buffer0 = queueMic0.readBuffer();  // mic2 added - Left channel buffer
    int16_t *buffer1 = queueMic1.readBuffer();  // mic2 added - Right channel buffer
    int16_t *buffer2 = queueMic2.readBuffer();  // mic2 added - Left channel buffer
    int16_t *buffer3 = queueMic3.readBuffer();  // mic2 added - Right channel buffer


    for (int i = 0; i < 128; i++) {
      //if (sample_count < FFT_SIZE) {

        // The data is divided by 32768.0f to normalize the raw audio samples from a 16-bit signed integer range 
        // into a floating-point range of -1.0 to 1.0.

        mic0_time[sample_count] = buffer0[i] / 32768.0f;  // range of -1.0 to 1.0.
        mic1_time[sample_count] = buffer1[i] / 32768.0f;  // range of -1.0 to 1.0.
        mic2_time[sample_count] = buffer2[i] / 32768.0f;  // range of -1.0 to 1.0.
        mic3_time[sample_count] = buffer3[i] / 32768.0f;  // range of -1.0 to 1.0.
        // Serial.printf("%d, %.6f, %.6f, %.6f, %.6f \n", sample_count, mic0_time[sample_count], mic1_time[sample_count], mic2_time[sample_count],  mic3_time[sample_count]);
        if(fabs(mic0_time[sample_count]) > mic0_max ) mic0_max = fabs(mic0_time[sample_count]);
        if(fabs(mic1_time[sample_count]) > mic1_max ) mic1_max = fabs(mic1_time[sample_count]);
        if(fabs(mic2_time[sample_count]) > mic2_max ) mic2_max = fabs(mic2_time[sample_count]);
        if(fabs(mic3_time[sample_count]) > mic3_max ) mic3_max = fabs(mic3_time[sample_count]);

        // mic2 added - Delay buffer update no longer needed
        // delayBuffer[delayIndex] = buffer[i];
        // delayIndex = (delayIndex + 1) % DELAY_SAMPLES;
        
        sample_count++;
      //}
    }



    float p0 = peak0.read();
    float p1 = peak1.read();
    float p2 = peak2.read();
    float p3 = peak3.read();
    Serial.printf("peak: %.6f, %.6f, %.6f, %.6f  ", p0, p1, p2, p3);
    Serial.printf("max : %.6f, %.6f, %.6f, %.6f \r\n", mic0_max, mic1_max, mic2_max, mic3_max);

    queueMic0.freeBuffer();
    queueMic1.freeBuffer();  // mic2 added - Free right channel buffer
    queueMic2.freeBuffer();
    queueMic3.freeBuffer(); 

    mic0_max=-1;
    mic1_max=-1;
    mic2_max=-1;
    mic3_max=-1;

    if (sample_count >= 128) {
      sample_count = 0;  // Reset immediately to start collecting next frame

    }

    delay(50);
  }
}

/*
3️⃣ Test #2 — DC offset / stuck-bit test (VERY IMPORTANT)
Long cables often cause stuck MSB/LSB.

Code:
int16_t *buf;
if (queueMic.available()) {
  buf = queueMic.readBuffer();
  int32_t sum = 0;
  for (int i = 0; i < 128; i++) sum += buf[i];
  queueMic.freeBuffer();
  Serial.println(sum / 128);
}

Expected:
≈ 0 (±200)

Red flags:
Result	Meaning
Large constant offset	DATA corruption
Offset varies with cable movement	Ground reference problem

 breadboard result 
peak: 0.000458, 0.000824, 0.001038, 0.000916  sum : -41.765625, -26.984375, -32.929688, -23.632812
peak: 0.000519, 0.000793, 0.001068, 0.000885  sum : -49.851562, -25.687500, -31.875000, -21.656250
peak: 0.000671, 0.000763, 0.000946, 0.000916  sum : -47.687500, -25.367188, -26.445312, -24.531250
peak: 0.000885, 0.000977, 0.001221, 0.001068  sum : -54.804688, -25.554688, -30.546875, -21.109375
peak: 0.000336, 0.000702, 0.000916, 0.000946  sum : -40.804688, -21.062500, -24.726562, -21.820312
peak: 0.000610, 0.000855, 0.001007, 0.000916  sum : -55.015625, -25.406250, -32.390625, -25.515625
peak: 0.000458, 0.000610, 0.000793, 0.000916  sum : -53.500000, -20.195312, -25.835938, -24.906250
peak: 0.000488, 0.000916, 0.000977, 0.000885  sum : -53.789062, -24.640625, -27.617188, -26.351562
peak: 0.000336, 0.000885, 0.000916, 0.000946  sum : -45.273438, -26.195312, -27.953125, -26.882812
peak: 0.000458, 0.000793, 0.000824, 0.000824  sum : -55.828125, -28.859375, -25.984375, -27.445312
peak: 0.000610, 0.000855, 0.000732, 0.000946  sum : -49.445312, -25.437500, -26.359375, -28.343750
peak: 0.000641, 0.000855, 0.000855, 0.000885  sum : -48.976562, -18.578125, -24.968750, -24.242188
peak: 0.000671, 0.000855, 0.000855, 0.000916  sum : -33.257812, -24.804688, -26.617188, -24.671875
peak: 0.000549, 0.000855, 0.000855, 0.000885  sum : -36.687500, -25.976562, -29.460938, -27.976562
peak: 0.000458, 0.000671, 0.000671, 0.000946  sum : -19.554688, -24.781250, -27.304688, -23.828125
peak: 0.000610, 0.000824, 0.000916, 0.000855  sum : -26.101562, -21.000000, -28.343750, -25.148438
peak: 0.000275, 0.000793, 0.000702, 0.000855  sum : -18.390625, -25.523438, -26.734375, -27.367188
peak: 0.001526, 0.000824, 0.000885, 0.000885  sum : -29.101562, -26.914062, -33.460938, -29.328125
peak: 0.468459, 0.000916, 0.001007, 0.001801  sum : -24.257812, -23.429688, -26.218750, -26.507812
peak: 0.055605, 0.001099, 0.000580, 0.000916  sum : -25.132812, -26.109375, -32.476562, -27.687500
peak: 0.170415, 0.000916, 0.000458, 0.000977  sum : -20.140625, -24.421875, -28.101562, -26.687500
peak: 0.204047, 0.000824, 0.000702, 0.000916  sum : -22.140625, -26.601562, -33.406250, -29.398438      *** tap tap show up in peak
peak: 0.164373, 0.000885, 0.000702, 0.000885  sum : -14.984375, -17.750000, -25.968750, -25.132812
peak: 0.105441, 0.000824, 0.000641, 0.000824  sum : -11.429688, -24.492188, -27.406250, -23.125000
peak: 0.699515, 0.001251, 0.000580, 0.001007  sum : -12.765625, -26.007812, -33.843750, -27.109375
peak: 0.194861, 0.000916, 0.000580, 0.000977  sum : -6.445312, -24.296875, -25.164062, -25.531250
peak: 0.165288, 0.000824, 0.000336, 0.000916  sum : -13.273438, -25.273438, -29.328125, -25.835938
peak: 0.306833, 0.000916, 0.000458, 0.000885  sum : -12.617188, -25.546875, -29.421875, -26.703125
peak: 0.322611, 0.000885, 0.000549, 0.000977  sum : -17.429688, -24.359375, -32.687500, -27.289062
peak: 0.258248, 0.000885, 0.000580, 0.000977  sum : -13.570312, -19.312500, -24.976562, -25.343750
peak: 0.168157, 0.000855, 0.000519, 0.000916  sum : -14.312500, -25.632812, -33.937500, -25.890625
peak: 0.087771, 0.000885, 0.000610, 0.000946  sum : -12.453125, -25.203125, -32.375000, -27.382812
peak: 0.026093, 0.000855, 0.000671, 0.000977  sum : -13.945312, -23.359375, -29.742188, -26.117188
peak: 0.038179, 0.000824, 0.000458, 0.000885  sum : -19.179688, -21.812500, -28.046875, -27.585938
peak: 0.048616, 0.000732, 0.000488, 0.000855  sum : -18.218750, -24.687500, -31.078125, -27.890625
peak: 0.050020, 0.000885, 0.000549, 0.000885  sum : -8.304688, -19.132812, -26.164062, -28.164062
peak: 0.050081, 0.000855, 0.000671, 0.000885  sum : -17.835938, -25.523438, -30.281250, -26.937500
peak: 0.045808, 0.000824, 0.000549, 0.000885  sum : -11.304688, -18.406250, -23.421875, -27.429688
peak: 0.038179, 0.000610, 0.000488, 0.000855  sum : -13.789062, -26.531250, -28.046875, -25.679688
peak: 0.030305, 0.000885, 0.000488, 0.000855  sum : -8.507812, -25.820312, -27.281250, -27.375000
peak: 0.022706, 0.000855, 0.000702, 0.000946  sum : -12.015625, -23.718750, -23.789062, -23.984375
peak: 0.014771, 0.000916, 0.000488, 0.000916  sum : -16.835938, -25.195312, -22.179688, -28.367188
peak: 0.010834, 0.000855, 0.000702, 0.000946  sum : -18.695312, -24.773438, -25.640625, -24.421875
peak: 0.007050, 0.000885, 0.000671, 0.000946  sum : -16.351562, -23.773438, -23.453125, -26.351562
peak: 0.003113, 0.000763, 0.000610, 0.000824  sum : -15.085938, -25.625000, -25.320312, -25.570312
peak: 0.000397, 0.000824, 0.000458, 0.000855  sum : -12.406250, -19.445312, -18.960938, -26.851562
peak: 0.000793, 0.000610, 0.000610, 0.000824  sum : -17.539062, -24.882812, -26.671875, -24.921875
peak: 0.000458, 0.000916, 0.000732, 0.000946  sum : -4.835938, -22.046875, -20.156250, -25.218750
peak: 0.000244, 0.000763, 0.000671, 0.000885  sum : 30.265625, -24.898438, -24.820312, -26.218750
peak: 0.000458, 0.000824, 0.000580, 0.000916  sum : 11636.992188, -12.000000, -25.289062, -40.648438    *** tap tap show up in sum
peak: 0.000519, 0.000702, 0.000702, 0.000916  sum : 617.578125, -31.929688, -16.320312, -25.234375
peak: 0.000580, 0.000885, 0.000702, 0.000916  sum : -5017.429688, -26.742188, -12.093750, -27.453125
peak: 0.000244, 0.000702, 0.000671, 0.000885  sum : -5544.851562, -24.578125, -18.914062, -25.367188
peak: 0.000488, 0.000641, 0.000610, 0.000946  sum : -4219.875000, -23.046875, -17.031250, -24.726562
peak: 0.000580, 0.000732, 0.000671, 0.000885  sum : -2491.382812, -25.148438, -16.656250, -24.914062
peak: 0.000641, 0.000885, 0.000671, 0.001038  sum : -17115.156250, -20.140625, -0.296875, 11.390625
peak: 0.000397, 0.000702, 0.000610, 0.000885  sum : -3507.125000, -23.242188, -9.539062, -27.921875
peak: 0.000641, 0.001282, 0.000732, 0.001495  sum : 5116.531250, -24.250000, -8.390625, -27.218750
peak: 0.000610, 0.000916, 0.000793, 0.000946  sum : 8943.781250, -26.921875, -12.429688, -26.546875
peak: 0.000610, 0.000824, 0.000519, 0.000885  sum : 8791.773438, -26.679688, -15.164062, -28.890625
peak: 0.000702, 0.000885, 0.000702, 0.000885  sum : 6659.039062, -26.296875, -13.742188, -28.140625
peak: 0.000977, 0.000885, 0.000671, 0.000885  sum : 4017.320312, -24.398438, -15.078125, -26.664062
peak: 0.000153, 0.000641, 0.000610, 0.000763  sum : 1771.226562, -25.734375, -16.218750, -26.984375
peak: 0.000549, 0.000824, 0.000641, 0.000855  sum : 122.062500, -25.359375, -19.328125, -27.929688
peak: 0.000610, 0.000855, 0.000732, 0.000885  sum : -911.484375, -24.851562, -12.242188, -26.414062



tetrahedron: mic1 and 3 are dead

peak: 0.001251, 0.001892, 0.001862, 0.476516  sum : -34.187500, -22.554688, -21.226562, -37.281250
peak: 0.001190, 0.002045, 0.001617, 0.214789  sum : -29.976562, -16.429688, -18.781250, -28.328125
peak: 0.000458, 0.000732, 0.000641, 0.158879  sum : -24.593750, -12.804688, -16.546875, -15.984375
peak: 0.000549, 0.001343, 0.000488, 0.084201  sum : -34.578125, -18.351562, -21.726562, -26.109375
peak: 0.000641, 0.001465, 0.001038, 0.038484  sum : -60.054688, -59.773438, -87.328125, -99.820312
peak: 0.001038, 0.001404, 0.001526, 0.098453  sum : -17.226562, -12.539062, -33.507812, -61.375000
peak: 0.001465, 0.002564, 0.002106, 0.324412  sum : 15.023438, 31.898438, 12.179688, -17.156250
peak: 0.000519, 0.001617, 0.000732, 0.054079  sum : 32.539062, 42.648438, 24.750000, 16.484375
peak: 0.000336, 0.001495, 0.001190, 0.166997  sum : 29.554688, 40.953125, 15.023438, 161.023438
peak: 0.000855, 0.001495, 0.000610, 0.115574  sum : 25.437500, 31.273438, 24.906250, 1956.453125
peak: 0.000763, 0.001465, 0.001068, 0.018799  sum : 3.421875, 16.304688, -11.656250, -749.414062


*/
void loop_DC_offset_stuck_bit_test () {


  float mic0_sum=0;
  float mic1_sum=0;
  float mic2_sum=0;
  float mic3_sum=0;
 
  while (queueMic0.available() && queueMic1.available()  && queueMic2.available() && queueMic3.available()) {  // mic2 added - Check both queues
    int16_t *buffer0 = queueMic0.readBuffer();  // mic2 added - Left channel buffer
    int16_t *buffer1 = queueMic1.readBuffer();  // mic2 added - Right channel buffer
    int16_t *buffer2 = queueMic2.readBuffer();  // mic2 added - Left channel buffer
    int16_t *buffer3 = queueMic3.readBuffer();  // mic2 added - Right channel buffer


    for (int i = 0; i < 128; i++) {
        mic0_sum += buffer0[i];  
        mic1_sum += buffer1[i];
        mic2_sum += buffer2[i];
        mic3_sum += buffer3[i];      
        sample_count++;
      //}
    }

    float p0 = peak0.read();
    float p1 = peak1.read();
    float p2 = peak2.read();
    float p3 = peak3.read();
    Serial.printf("peak: %.6f, %.6f, %.6f, %.6f  ", p0, p1, p2, p3);
    Serial.printf("sum : %.6f, %.6f, %.6f, %.6f \r\n", mic0_sum/128, mic1_sum/128, mic2_sum/128, mic3_sum/128);

    queueMic0.freeBuffer();
    queueMic1.freeBuffer();  // mic2 added - Free right channel buffer
    queueMic2.freeBuffer();
    queueMic3.freeBuffer(); 

    mic0_sum=0;
    mic1_sum=0;
    mic2_sum=0;
    mic3_sum=0;

    if (sample_count >= 128) {
      sample_count = 0;  // Reset immediately to start collecting next frame
    }

    delay(50);
  }

}

/*
4️⃣ Test #3 — Known-tone injection test (BEST sanity test)

This is the most reliable test you can do.

Method
Play a 1 kHz sine from phone / speaker
Hold at fixed distance
No claps, no speech

Observe FFT bin
int bin = 1024 * 1000 / 44100;  // ≈ 23
Serial.println(fft.read(bin), 4);

Expected

Stable magnitude
Same order of magnitude every run
Minor noise variation only

Failure indicators
Bin jumps wildly
Energy smeared across bins
One mic differs drastically

This test catches:
✔ Bit errors
✔ Clock jitter
✔ Data skew




*/


void loop_1khz_tone_injection_test() {

  while (queueMic0.available() && queueMic1.available()  && queueMic2.available() && queueMic3.available()) {

    int16_t *buffer0 = queueMic0.readBuffer();
    int16_t *buffer1 = queueMic1.readBuffer();
    int16_t *buffer2 = queueMic2.readBuffer();
    int16_t *buffer3 = queueMic3.readBuffer();
    for (int i = 0; i < 128; i++) {
      if (sample_count < FFT_SIZE) {
        mic0_time[sample_count] = buffer0[i] / 32768.0f;
        mic1_time[sample_count] = buffer1[i] / 32768.0f;
        mic2_time[sample_count] = buffer2[i] / 32768.0f;
        mic3_time[sample_count] = buffer3[i] / 32768.0f;
        sample_count++;
      }
    }
    queueMic0.freeBuffer();
    queueMic1.freeBuffer();
    queueMic2.freeBuffer();
    queueMic3.freeBuffer(); 

    // When buffer is full, mark ready for FFT processing
    if (sample_count >= FFT_SIZE && !fft_ready) {
      computeFFTAndPhase(mic0_time, mic0_fft, mic0_magnitude, mic0_phase);
      computeFFTAndPhase(mic1_time, mic1_fft, mic1_magnitude, mic1_phase);
      computeFFTAndPhase(mic2_time, mic2_fft, mic2_magnitude, mic2_phase);
      computeFFTAndPhase(mic3_time, mic3_fft, mic3_magnitude, mic3_phase);
      fft_ready = true;
      sample_count = 0;  // Reset immediately to start collecting next frame
    }
  }

  /*
  what is the benefit of separating out send_fft_result_to_serial_port outside of while loop? 

  Note that 
   1) it takes 23.2ms to collect 1024 sample ( 128 samples takes 2.9ms)
   2) let's assume send_fft_result_to_serial_port takes 10ms 
  Then Loop Iteration Duration
    Current approach:
    Each loop() call: ~23.2ms (process 8 frames) + 10ms (send) = ~33ms total

    Inside while approach ( call send_fft_result_to_serial_port right after FFT in while )
    Each loop() call: ~23.2ms (process 8 frames) + 10ms (send) + ~8.7ms (process 3 more frames) = ~42ms total

    this is because during 10ms, 3 more frames are queued and while loop is still true

  Thus, 
  3. Latency for Other Tasks
      If your main loop() does other things after loop_1khz_tone_injection_test():
      void loop() {
          loop_1khz_tone_injection_test();
          // Other tasks here
      }
      Current approach: Other tasks run every ~33ms
      Inside while approach: Other tasks run every ~42ms (blocked longer)

Which Is Better?
  Current approach is better because:

  More predictable timing: Each iteration processes exactly 8 frames + sends
  Better for multitasking: Doesn't monopolize the while loop
  Cleaner separation: Audio processing vs. I/O

  Inside while would be better only if:

  You want to guarantee the queue is completely drained each iteration
  You have no other tasks in loop()

  Given your application (tone injection test), the current approach is ideal

*/  

 
/*  


fft : [22] 0.001662, [23] 0.018486, [24] 0.009817, others: [0] 0.000413,  [511] 0.000000
fft : [22] 0.001646, [23] 0.018380, [24] 0.009768, others: [0] 0.000342,  [511] 0.000000
fft : [22] 0.001632, [23] 0.018256, [24] 0.009716, others: [0] 0.000398,  [511] 0.000000
fft : [22] 0.001639, [23] 0.018326, [24] 0.009754, others: [0] 0.000450,  [511] 0.000000
fft : [22] 0.001615, [23] 0.018297, [24] 0.009736, others: [0] 0.000451,  [511] 0.000000
fft : [22] 0.001586, [23] 0.018267, [24] 0.009754, others: [0] 0.000426,  [511] 0.000000
fft : [22] 0.001631, [23] 0.018278, [24] 0.009709, others: [0] 0.000450,  [511] 0.000000
fft : [22] 0.001614, [23] 0.018293, [24] 0.009763, others: [0] 0.000378,  [511] 0.000000
fft : [22] 0.001687, [23] 0.018428, [24] 0.009787, others: [0] 0.000455,  [511] 0.000000
fft : [22] 0.001802, [23] 0.018458, [24] 0.009807, others: [0] 0.000367,  [511] 0.000000
fft : [22] 0.001617, [23] 0.018440, [24] 0.009816, others: [0] 0.000462,  [511] 0.000000
fft : [22] 0.001558, [23] 0.018469, [24] 0.009830, others: [0] 0.000506,  [511] 0.000000

Understanding result: 

Great — thanks for pasting the exact FFT code. That makes this much more concrete.
What you’re observing (≈ 0.017–0.02 at the 1 kHz bin) is reasonable and consistent given your scaling and window choice.
Nothing looks “wrong” here.
Now let me explain why that number makes sense, what range you should expect, and how to sanity-check it.
1️⃣ What your FFT magnitude actually represents
You are doing:
magnitude[i] = sqrt(real^2 + imag^2) / FFT_SIZE;

Important implications:
CMSIS FFT is unnormalized
You divide by FFT_SIZE (1024)
You are using a window (Tukey)
You are looking at a single-sided bin
Your mic input is far from full-scale

So your FFT bin magnitude is:

bin magnitude ≈ 𝐴signal × window coherent gain × 1/2
(That 1/2 is because a real sine splits energy between ±f bins.)

2️⃣ Expected magnitude for a 1 kHz sine (order of magnitude)

Let’s build intuition with realistic numbers.
Typical SPH0645LM4H input level
From your earlier measurements:
Normal loud sound → peak.read() ≈ 0.1–0.2
That corresponds to roughly:

𝐴peak≈0.1 ⇒ 𝐴RMS≈0.07
 
But your phone speaker + air + distance means the mic likely sees much less than that.
A realistic normalized sine amplitude at the mic is often:

A ≈ 0.03 – 0.06

3️⃣ Window effect (very important)

You’re using a Tukey window.
Typical coherent gain:
Hann: ≈ 0.5
Tukey (α ≈ 0.25–0.5): ≈ 0.6–0.8

Let’s assume:
window gain ≈ 0.7

4️⃣ Expected FFT bin value (math)

For a single-tone sine exactly on-bin:
bin magnitude≈𝐴 × window gain /2
 


Plug in reasonable numbers:

A ≈ 0.05
window ≈ 0.7

≈ 0.05 × 0.7 / 2 = 0.0175
 

🎯 That lands exactly in your observed range:

0.017652 – 0.02

So your FFT scaling is behaving correctly.

5️⃣ Why this is smaller than Teensy FFT values

Earlier, with AudioAnalyzeFFT1024, I mentioned speech bins like:

0.08 – 0.25


That’s because the Teensy FFT:
Internally compensates window loss
Uses different normalization
Presents a user-friendly amplitude, not raw math
Your CMSIS FFT is physically correct, not “boosted”.

6️⃣ One subtle improvement (important)

Right now you divide by FFT_SIZE.
If you want amplitude-consistent single-sided FFT, the usual normalization is:
magnitude[i] *= 2.0f / FFT_SIZE;

(Except bin 0 and Nyquist.)
Why?
Real FFT splits energy between +f and −f
You are only looking at +f
I
f you apply that change Your observed values would become:

≈ 0.035 – 0.04


Which may match intuition better.

7️⃣ Practical sanity checks you can do
✅ Check 1 — Double normalization test

Temporarily change:

magnitude[i] = sqrtf(real*real + imag*imag) * (2.0f / FFT_SIZE);

Expected result:
Your 1 kHz bin roughly doubles

✅ Check 2 — Energy concentration

For a clean sine:
Bin 22–24 should dominate
Adjacent bins should be much smaller
If energy spreads widely:
Window mismatch

Frequency not exactly 1 kHz

Clock mismatch (phone ≠ 44.1 kHz)

✅ Check 3 — Volume scaling

If you halve phone volume:
Bin magnitude should drop ≈ linearly
FFT magnitude ∝ signal amplitude.

8️⃣ Summary (answering your question directly)
Observed range:
≈ 0.017 – 0.02

Is this reasonable?
✔ Yes — exactly what we expect with:
CMSIS FFT

/ FFT_SIZE normalization
Tukey window
Phone speaker stimulus
Nothing is wrong.



tetrahedron:

1khz on mic1 --> I see it capcutres signal and FFT is showing up.


fft mic0: [22] 0.000026, [23] 0.000301, [24] 0.000162, [0] 0.000437, [511] 0.000000 ; mic1: 0.012101 ; mic2: 0.003375; mic3: 0.001449
fft mic0: [22] 0.000023, [23] 0.000302, [24] 0.000165, [0] 0.000463, [511] 0.000000 ; mic1: 0.012065 ; mic2: 0.003369; mic3: 0.001437
fft mic0: [22] 0.000025, [23] 0.000309, [24] 0.000168, [0] 0.000498, [511] 0.000000 ; mic1: 0.012034 ; mic2: 0.003375; mic3: 0.001438
fft mic0: [22] 0.000034, [23] 0.000310, [24] 0.000160, [0] 0.000399, [511] 0.000000 ; mic1: 0.012036 ; mic2: 0.003387; mic3: 0.001451
fft mic0: [22] 0.000028, [23] 0.000306, [24] 0.000163, [0] 0.000426, [511] 0.000000 ; mic1: 0.012024 ; mic2: 0.003390; mic3: 0.001458
fft mic0: [22] 0.000025, [23] 0.000298, [24] 0.000160, [0] 0.000382, [511] 0.000000 ; mic1: 0.011938 ; mic2: 0.003392; mic3: 0.001446
fft mic0: [22] 0.000026, [23] 0.000296, [24] 0.000157, [0] 0.000410, [511] 0.000000 ; mic1: 0.011859 ; mic2: 0.003398; mic3: 0.001444
fft mic0: [22] 0.000027, [23] 0.000292, [24] 0.000156, [0] 0.000382, [511] 0.000000 ; mic1: 0.011808 ; mic2: 0.003416; mic3: 0.001439
fft mic0: [22] 0.000025, [23] 0.000288, [24] 0.000155, [0] 0.000447, [511] 0.000000 ; mic1: 0.011770 ; mic2: 0.003424; mic3: 0.001440
fft mic0: [22] 0.000026, [23] 0.000285, [24] 0.000153, [0] 0.000356, [511] 0.000000 ; mic1: 0.011738 ; mic2: 0.003431; mic3: 0.001441
fft mic0: [22] 0.000021, [23] 0.000277, [24] 0.000150, [0] 0.000436, [511] 0.000000 ; mic1: 0.011688 ; mic2: 0.003431; mic3: 0.001429



*/
  if (fft_ready) {
    int bin = 1024 * 1000 / 44100;  // ≈ 23 , around 1khz
    Serial.printf("fft mic0: [%d] %.6f, [%d] %.6f, [%d] %.6f, [0] %.6f, [511] %.6f ; \
mic1: %.6f ; mic2: %.6f; mic3: %.6f\r\n", 
      bin-1, mic0_magnitude[bin-1], bin, mic0_magnitude[bin], bin+1, mic0_magnitude[bin+1], mic0_magnitude[0], mic0_magnitude[511],   
      mic1_magnitude[bin], mic2_magnitude[bin], mic3_magnitude[bin]);
    fft_ready = false; 
  }

}

/*6️⃣ Test #5 — Clock sanity test (advanced, very revealing)

Temporarily mute audio input (quiet room).

Measure:
float sum = 0;
for (int i = 0; i < 512; i++) sum += fft.read(i);
Serial.println(sum);

Expected
Low, stable baseline
If clock is marginal:
Baseline jumps
High-frequency bins light up randomly
*/
void loop_check_clock_sanity_by_fft_sum_test() {
  //Serial.printf("loop_check_clock_sanity_by_fft_sum_test\r\n" );
  float mic0_fft_sum=0; 
  float mic1_fft_sum=0; 
  float mic2_fft_sum=0; 
  float mic3_fft_sum=0; 
  while (queueMic0.available() && queueMic1.available()  && queueMic2.available() && queueMic3.available()) {

    int16_t *buffer0 = queueMic0.readBuffer();
    int16_t *buffer1 = queueMic1.readBuffer();
    int16_t *buffer2 = queueMic2.readBuffer();
    int16_t *buffer3 = queueMic3.readBuffer();
    for (int i = 0; i < 128; i++) {
      if (sample_count < FFT_SIZE) {
        mic0_time[sample_count] = buffer0[i] / 32768.0f;
        mic1_time[sample_count] = buffer1[i] / 32768.0f;
        mic2_time[sample_count] = buffer2[i] / 32768.0f;
        mic3_time[sample_count] = buffer3[i] / 32768.0f;
        sample_count++;
      }
    }
    queueMic0.freeBuffer();
    queueMic1.freeBuffer();
    queueMic2.freeBuffer();
    queueMic3.freeBuffer(); 

    //Serial.printf("fft sum:  %d, %d,  \r\n", sample_count, fft_ready );
    // When buffer is full, mark ready for FFT processing
    if (sample_count >= FFT_SIZE && !fft_ready) {
      computeFFTAndPhase(mic0_time, mic0_fft, mic0_magnitude, mic0_phase);
      computeFFTAndPhase(mic1_time, mic1_fft, mic1_magnitude, mic1_phase);
      computeFFTAndPhase(mic2_time, mic2_fft, mic2_magnitude, mic2_phase);
      computeFFTAndPhase(mic3_time, mic3_fft, mic3_magnitude, mic3_phase);
      fft_ready = true;
      sample_count = 0;  // Reset immediately to start collecting next frame
    }
  }

/*

breadboard result:
fft sum:  0.001316, 0.001377, 0.001316, 0.001787
fft sum:  0.001274, 0.001239, 0.001132, 0.001544
fft sum:  0.001721, 0.001345, 0.001308, 0.001691
fft sum:  0.001538, 0.001225, 0.001196, 0.001535
fft sum:  0.001620, 0.001390, 0.001387, 0.001531
fft sum:  0.001803, 0.001854, 0.001594, 0.001617
fft sum:  0.001449, 0.001297, 0.001218, 0.001044
fft sum:  0.001520, 0.001275, 0.001471, 0.001077
fft sum:  0.001735, 0.001678, 0.001926, 0.001218
fft sum:  0.001477, 0.001199, 0.001667, 0.001025
fft sum:  0.001611, 0.001361, 0.001762, 0.001047
fft sum:  0.001679, 0.001455, 0.001722, 0.001264
fft sum:  0.001488, 0.001092, 0.001310, 0.001037




tetrahedron
fft sum:  0.000899, 0.001306, 0.001136, 0.001262
fft sum:  0.001146, 0.001346, 0.001180, 0.001471
fft sum:  0.000911, 0.001163, 0.001046, 0.001310
fft sum:  0.001007, 0.001167, 0.000985, 0.001337
fft sum:  0.000772, 0.001303, 0.001053, 0.001345
fft sum:  0.001052, 0.001354, 0.001628, 0.001527
fft sum:  0.000916, 0.001409, 0.001722, 0.001647
fft sum:  0.000778, 0.001288, 0.001578, 0.001499



*/

  if (fft_ready) {
    for(int i=0 ; i < FFT_BINS; i++) {
      mic0_fft_sum += mic0_magnitude[i];
      mic1_fft_sum += mic1_magnitude[i];
      mic2_fft_sum += mic2_magnitude[i];
      mic3_fft_sum += mic3_magnitude[i];
    }
    Serial.printf("fft sum:  %.6f, %.6f, %.6f, %.6f \r\n", mic0_fft_sum, mic1_fft_sum, mic2_fft_sum, mic3_fft_sum);
 
    fft_ready = false; // allow while loop collect 1024 samples
  }  
}

/*
7️⃣ Test #6 — Cross-mic coherence test (excellent for arrays)

Same sound source, fixed position.

Compute:

corr = correlation(mic0, mic1);

Expected

Stable peak position

Similar magnitude every run

If wiring is bad:

Peak shifts randomly

Multiple competing peaks
*/
void loop_cross_correlation() {

}


void loop_sanity_fft_draw() {
 //Serial.printf("loop_check_clock_sanity_by_fft_sum_test\r\n" );
  float mic0_fft_sum=0; 
  float mic1_fft_sum=0; 
  float mic2_fft_sum=0; 
  float mic3_fft_sum=0; 
  while (queueMic0.available() && queueMic1.available()  && queueMic2.available() && queueMic3.available()) {

    int16_t *buffer0 = queueMic0.readBuffer();
    int16_t *buffer1 = queueMic1.readBuffer();
    int16_t *buffer2 = queueMic2.readBuffer();
    int16_t *buffer3 = queueMic3.readBuffer();
    for (int i = 0; i < 128; i++) {
      if (sample_count < FFT_SIZE) {
        mic0_time[sample_count] = buffer0[i] / 32768.0f;
        mic1_time[sample_count] = buffer1[i] / 32768.0f;
        mic2_time[sample_count] = buffer2[i] / 32768.0f;
        mic3_time[sample_count] = buffer3[i] / 32768.0f;
        sample_count++;
      }
    }
    queueMic0.freeBuffer();
    queueMic1.freeBuffer();
    queueMic2.freeBuffer();
    queueMic3.freeBuffer(); 

    //Serial.printf("fft sum:  %d, %d,  \r\n", sample_count, fft_ready );
    // When buffer is full, mark ready for FFT processing
    if (sample_count >= FFT_SIZE && !fft_ready) {
      computeFFTAndPhase(mic0_time, mic0_fft, mic0_magnitude, mic0_phase);
      computeFFTAndPhase(mic1_time, mic1_fft, mic1_magnitude, mic1_phase);
      computeFFTAndPhase(mic2_time, mic2_fft, mic2_magnitude, mic2_phase);
      computeFFTAndPhase(mic3_time, mic3_fft, mic3_magnitude, mic3_phase);
      fft_ready = true;
      sample_count = 0;  // Reset immediately to start collecting next frame
    }
  }

 
  if (fft_ready) {
 
      Serial.println("FFT_START");
 
      for(int i = 0; i < FFT_BINS; i++) {
        //Serial.print(mic0_magnitude[i], 6);
        //Serial.print(mic1_magnitude[i], 6);
        //Serial.print(mic2_magnitude[i], 6);
        Serial.print(mic3_magnitude[i], 6);
        if(i < FFT_BINS - 1) {Serial.print(",");}
      }

      
      Serial.println();
 
      Serial.println("FFT_END");

 
    fft_ready = false; // allow while loop collect 1024 samples
  }  
}

 


void loop_gcc_phat() {
  // Continuous draining mic1 queue - prevents audio buffer overflow
  // We must always read available buffers even while processing FFT
  // mic2 added - Now processing both left and right channels simultaneously
  while (queueMic0.available() && queueMic1.available()  && queueMic2.available() && queueMic3.available()) {  // mic2 added - Check both queues
    int16_t *buffer0 = queueMic0.readBuffer();  // mic2 added - Left channel buffer
    int16_t *buffer1 = queueMic1.readBuffer();  // mic2 added - Right channel buffer
    int16_t *buffer2 = queueMic2.readBuffer();  // mic2 added - Left channel buffer
    int16_t *buffer3 = queueMic3.readBuffer();  // mic2 added - Right channel buffer


    for (int i = 0; i < 128; i++) {
      if (sample_count < FFT_SIZE) {

        // The data is divided by 32768.0f to normalize the raw audio samples from a 16-bit signed integer range into a floating-point range of -1.0 to 1.0.

        mic0_time[sample_count] = buffer0[i] / 32768.0f;  // mic2 added - Direct left channel data
        mic1_time[sample_count] = buffer1[i] / 32768.0f;  // mic2 added - Direct right channel data (no delay needed)
        mic2_time[sample_count] = buffer2[i] / 32768.0f;  // mic2 added - Direct left channel data
        mic3_time[sample_count] = buffer3[i] / 32768.0f;  // mic2 added - Direct right channel data (no delay needed)
        
        // mic2 added - Delay buffer update no longer needed
        // delayBuffer[delayIndex] = buffer[i];
        // delayIndex = (delayIndex + 1) % DELAY_SAMPLES;
        
        sample_count++;
      }
    }
    
    queueMic0.freeBuffer();
    queueMic1.freeBuffer();  // mic2 added - Free right channel buffer
    queueMic2.freeBuffer();
    queueMic3.freeBuffer(); 

    // When buffer is full, mark ready for FFT processing
    if (sample_count >= FFT_SIZE && !fft_ready) {
      digitalWrite(MIC1_LED, LOW); 
      digitalWrite(MIC2_LED, LOW); 
      digitalWrite(MIC3_LED, LOW); 

      computeFFTAndPhase(mic0_time, mic0_fft, mic0_magnitude, mic0_phase);
      computeFFTAndPhase(mic1_time, mic1_fft, mic1_magnitude, mic1_phase);
      computeFFTAndPhase(mic2_time, mic2_fft, mic2_magnitude, mic2_phase);
      computeFFTAndPhase(mic3_time, mic3_fft, mic3_magnitude, mic3_phase);

      run_gcc_phat(mic0_fft, mic1_fft, cross_spectrum01, correlation_result01);
      run_gcc_phat(mic0_fft, mic2_fft, cross_spectrum02, correlation_result02);
      run_gcc_phat(mic0_fft, mic3_fft, cross_spectrum03, correlation_result03);

      fft_ready = true;
      sample_count = 0;  // Reset immediately to start collecting next frame
    }
  }
  
  // Original display code - runs when both FFTs are available
  //if (peak.available() && fft.available() && fft_ready) {
  if (fft_ready) {

    
    // if (amplitude < MIN_AMPLITUDE) {
    //   volumeLevel = 0; brightness = 0;
    // } 
    // else if (amplitude <= QUIET_THRESH) {
    //   volumeLevel = 1; brightness = 80;
    // }
    // else if (amplitude <= TALKING_THRESH) {
    //   volumeLevel = 2; brightness = 140;
    // }
    // else if (amplitude <= CLAPPING_THRESH) {
    //   volumeLevel = 3; brightness = 200;
    // }
    // else if (amplitude <= BANGING_THRESH) {
    //   volumeLevel = 4; brightness = 240;
    // }
    // else {
    //   volumeLevel = 5; brightness = 255;
    // }
    // analogWrite(MIC1_LED, brightness);
    
    //float dominantFreq = 0;

 
      /*
      *
      *
      *
      */
    if(debug_mode == 1) {
      // Send data to serial - now using ARM FFT results
      // Format: MIC1_MAG,MIC1_PHASE,MIC2_MAG,MIC2_PHASE (alternating)
      Serial.println("FFT_DATA_START");
      
      // Send Mic1 FFT (magnitude and phase interleaved)
      Serial.print("CORR:");
      // float mic_mag[FFT_SIZE];

      // for(int i = 0; i < NUM_FFT_BINS ; i++) {
      //   Serial.print(mic1_magnitude[i], 6);
      //   Serial.print(",");
      // }
      // for(int i = 0; i < NUM_FFT_BINS ; i++) {
      //   Serial.print(mic1_magnitude[i], 6);
      //   // Serial.print(mic2_magnitude[i], 6);
      //   //if(i < NUM_FFT_BINS  - 1) {
      //     Serial.print(",");
      //   //}
      // }
      for(int i = 0; i < FFT_SIZE; i++) {
        Serial.print(correlation_result01[i], 6);
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

      /*
      *
      *
      *
      */
    } else if(debug_mode == 2) {
      float max01_value = -1; int max01_idx = -1;
      float max02_value = -1; int max02_idx = -1;
      float max03_value = -1; int max03_idx = -1;

      for(int i = 0; i < FFT_SIZE; i++) {
        if(correlation_result01[i] > max01_value) {
          max01_value =  correlation_result01[i];
          max01_idx = i;
        } 
        if(correlation_result02[i] > max02_value) {
          max02_value =  correlation_result02[i];
          max02_idx = i;
        } 
        if(correlation_result03[i] > max03_value) {
          max03_value =  correlation_result03[i];
          max03_idx = i;
        } 
      }

        //  Serial.printf("max01_value: %.2f at %5d, max02_value: %.2f at %5d, max03_value: %.2f at %5d \n", 
        //                max01_value, max01_idx, 
        //                max02_value, max02_idx, 
        //                max03_value, max03_idx);
    // after wiring of quadpus legs 
    //max01_value: 0.28 at   -20, max02_value: 0.32 at   -38, max03_value: 0.55 at   -51 
    // 20 sample distance is 0.4535 msec --- 15.56 cm ( 343 m/s * 0.4535 msec = 155.55 mm = 15.5 cm)

      if (max01_value > 0.25 && max02_value > 0.25 && max03_value > 0.25) {
        int max01_shifted_idx = max01_idx > 512 ? max01_idx -1024 : max01_idx;
        int max02_shifted_idx = max02_idx > 512 ? max02_idx -1024 : max02_idx;
        int max03_shifted_idx = max03_idx > 512 ? max03_idx -1024 : max03_idx;
        int max12_shifted_idx = max02_shifted_idx - max01_shifted_idx;
        int max13_shifted_idx = max03_shifted_idx - max01_shifted_idx;
        int max23_shifted_idx = max03_shifted_idx - max02_shifted_idx;

        Serial.printf("%lu: max01_value: %.2f at %5d, max02_value: %.2f at %5d, max03_value: %.2f at %5d \n", 
                      millis()/1000, 
                      max01_value, max01_shifted_idx, 
                      max02_value, max02_shifted_idx, 
                      max03_value, max03_shifted_idx);


        if(max01_shifted_idx < 0 && max02_shifted_idx < 0 && max03_shifted_idx < 0) {
          digitalWrite(MIC1_LED, HIGH); 
        } else if(max01_shifted_idx > 0 &&  max12_shifted_idx < 0 && max13_shifted_idx < 0 ) {
          digitalWrite(MIC2_LED, HIGH); 
        } else if(max02_shifted_idx > 0 &&  max12_shifted_idx > 0 && max23_shifted_idx < 0 ) {
          digitalWrite(MIC3_LED, HIGH); 
        }
      
      
      }

      /*
      *
      *
      *
      */
    } else if( debug_mode == 3) {
      //float amplitude = peak0.read();
        float _peak0 = peak0.read();
        float _peak1 = peak1.read();
        float _peak2 = peak2.read();
        float _peak3 = peak3.read();
        if( _peak0 > 0.1 || _peak1 > 0.1 || _peak2 > 0.1 || _peak3 > 0.1) {
          Serial.printf("%lu: peak0: %.2f, peak1: %.2f, peak2: %.2f, peak3: %.2f \n", 
                        millis()/1000, _peak0, _peak1, _peak2, _peak3);
 
        }

    }
    fft_ready = false;  // Reset flag
  }
}
