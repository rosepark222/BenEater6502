/*
write a processing code drawing FFT 
1, use the below teensy code which is sending FFT result  
2, use 44.1khz sampling rate  , so draw 0 to 22.05khz 
3, also freq resolution should be 44.1khz / 1024, because sample size is 1024
4, make the drawing as simple as possible, no color coding. just add 5 labels on X axis (0 hz, fs/4, fs/2, 3*fs/4, fs). 
5, mark the fft values on Y axis


*/


import processing.serial.*;

Serial myPort;
String buffer = "";
float[] fftData = new float[512];
boolean newData = false;

// FFT parameters
final int FFT_SIZE = 1024;
final int NUM_BINS = 512; // Teensy sends only half (Nyquist)
final float SAMPLE_RATE = 44100.0;
final float FREQ_RESOLUTION = SAMPLE_RATE / FFT_SIZE; // 43.07 Hz per bin
final float NYQUIST = SAMPLE_RATE / 2.0; // 22050 Hz

void setup() {
  size(1200, 600);
  
  // List all available serial ports
  printArray(Serial.list());
  
  // Change the index [0] to match your Teensy port
  String portName = Serial.list()[0];
  myPort = new Serial(this, portName, 115200);
  myPort.bufferUntil('\n');
}

void draw() {
  background(255);
  
  if (newData) {
    drawFFT();
    // Don't set newData to false here - keep drawing the same data
  } else {
    // Show waiting message
    fill(0);
    textAlign(CENTER, CENTER);
    textSize(20);
    text("Waiting for FFT data...", width/2, height/2);
  }
}

void drawFFT() {
  // Draw FFT spectrum (512 bins = 0 to Nyquist frequency)
  
  // Find max value for scaling
  float maxVal = 0;
  for (int i = 0; i < NUM_BINS; i++) {
    if (fftData[i] > maxVal) {
      maxVal = fftData[i];
    }
  }
  
  // Draw axes
  stroke(0);
  strokeWeight(2);
  line(50, height - 50, width - 50, height - 50); // X-axis
  line(50, 50, 50, height - 50); // Y-axis
  
  // X-axis labels (frequency)
  fill(0);
  textAlign(CENTER, TOP);
  textSize(14);
  int plotWidth = width - 100;
  
  text("0 Hz", 50, height - 35);
  text(nf(NYQUIST/4, 0, 0) + " Hz", 50 + plotWidth/4, height - 35);
  text(nf(NYQUIST/2, 0, 0) + " Hz", 50 + plotWidth/2, height - 35);
  text(nf(3*NYQUIST/4, 0, 0) + " Hz", 50 + 3*plotWidth/4, height - 35);
  text(nf(NYQUIST, 0, 0) + " Hz", width - 50, height - 35);
  
  // Y-axis labels (magnitude)
  textAlign(RIGHT, CENTER);
  for (int i = 0; i <= 5; i++) {
    float yPos = height - 50 - i * (height - 100) / 5.0;
    float val = maxVal * i / 5.0;
    
    // Format based on magnitude size
    if (maxVal < 0.01) {
      text(nf(val, 0, 6), 45, yPos);
    } else if (maxVal < 1.0) {
      text(nf(val, 0, 4), 45, yPos);
    } else {
      text(nf(val, 0, 2), 45, yPos);
    }
    
    // Grid lines
    stroke(200);
    strokeWeight(1);
    line(50, yPos, width - 50, yPos);
  }
  
  // Draw FFT data
  stroke(0, 0, 255);
  strokeWeight(1);
  noFill();
  beginShape();
  
  for (int i = 0; i < NUM_BINS; i++) {
    float x = map(i, 0, NUM_BINS - 1, 50, width - 50);
    float y = map(fftData[i], 0, maxVal, height - 50, 50);
    vertex(x, y);
  }
  
  endShape();
  
  // Display info
  fill(0);
  textAlign(LEFT, TOP);
  textSize(12);
  text("FFT Size: " + FFT_SIZE, 60, 60);
  text("Freq Resolution: " + nf(FREQ_RESOLUTION, 0, 2) + " Hz/bin", 60, 80);
  text("Max Magnitude: " + nf(maxVal, 0, 4), 60, 100);
}

void serialEvent(Serial myPort) {
  String inString = myPort.readStringUntil('\n');
  
  if (inString != null) {
    inString = trim(inString);
    
    if (inString.equals("FFT_START")) {
      buffer = "";
    } else if (inString.equals("FFT_END")) {
      parseFFTData(buffer);
      newData = true;
    } else {
      buffer += inString;
    }
  }
}

void parseFFTData(String data) {
  String[] values = split(data, ',');
  
  if (values.length == NUM_BINS) {
    for (int i = 0; i < NUM_BINS; i++) {
      fftData[i] = abs(float(values[i])); // Use absolute value
    }
    println("Received " + NUM_BINS + " values. Max: " + max(fftData));
  } else {
    println("Warning: Expected " + NUM_BINS + " values, got " + values.length);
  }
}
