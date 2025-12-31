/*
write a processing code drawing FFT 
1, use the below teensy code which is sending FFT result  
2, use 44.1khz sampling rate  , so draw 0 to 22.05khz 
3, also freq resolution should be 44.1khz / 1024, because sample size is 1024
4, make the drawing as simple as possible, no color coding. just add 5 labels on X axis (0 hz, fs/4, fs/2, 3*fs/4, fs). 
5, mark the fft values on Y axis

6, add waterfall spectrogram 
7, remove flickering using PGraphics 

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

// Layout parameters
final int FFT_HEIGHT_PERCENT = 40; // Change this: 50 = 50/50 split, 40 = 40/60 split, etc.
final int WINDOW_HEIGHT = 840;
final int MARGIN = 50;
final int LABEL_HEIGHT = 20;

// Calculated heights
final int FFT_HEIGHT = int(WINDOW_HEIGHT * FFT_HEIGHT_PERCENT / 100.0) - LABEL_HEIGHT;
final int WATERFALL_HEIGHT = WINDOW_HEIGHT - FFT_HEIGHT - LABEL_HEIGHT * 2 - MARGIN;
final int FFT_BOTTOM = FFT_HEIGHT + MARGIN;
final int WATERFALL_TOP = FFT_BOTTOM + LABEL_HEIGHT;

// Waterfall buffer
PGraphics waterfall;
PGraphics fftBuffer;

void setup() {
  size(1200, 840);
  
  // Create waterfall buffer
  waterfall = createGraphics(width - 100, WATERFALL_HEIGHT);
  waterfall.beginDraw();
  waterfall.background(0);
  waterfall.endDraw();
  
  // Create FFT buffer
  fftBuffer = createGraphics(width, FFT_BOTTOM + LABEL_HEIGHT);
  fftBuffer.beginDraw();
  fftBuffer.background(255);
  fftBuffer.endDraw();
  
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
    updateWaterfall();
    newData = false;
  }
  
  // Always draw the buffers (no flickering)
  if (fftBuffer != null) {
    image(fftBuffer, 0, 0);
  } else {
    // Show waiting message
    fill(0);
    textAlign(CENTER, CENTER);
    textSize(20);
    text("Waiting for FFT data...", width/2, height/2);
  }
  
  // Draw waterfall
  image(waterfall, MARGIN, WATERFALL_TOP);
  
  // Waterfall labels
  fill(0);
  textAlign(CENTER, TOP);
  textSize(14);
  int plotWidth = width - 100;
  int labelY = WATERFALL_TOP + WATERFALL_HEIGHT + 5;
  text("0 Hz", MARGIN, labelY);
  text(nf(NYQUIST/4, 0, 0) + " Hz", MARGIN + plotWidth/4, labelY);
  text(nf(NYQUIST/2, 0, 0) + " Hz", MARGIN + plotWidth/2, labelY);
  text(nf(3*NYQUIST/4, 0, 0) + " Hz", MARGIN + 3*plotWidth/4, labelY);
  text(nf(NYQUIST, 0, 0) + " Hz", width - MARGIN, labelY);
  
  // Waterfall title
  textAlign(LEFT, TOP);
  textSize(12);
  fill(0);
  text("Waterfall Spectrogram", MARGIN + 10, WATERFALL_TOP - 20);
}

void drawFFT() {
  // Draw FFT spectrum (512 bins = 0 to Nyquist frequency)
  
  fftBuffer.beginDraw();
  fftBuffer.background(255);
  
  // Find max value for scaling
  float maxVal = 0;
  for (int i = 0; i < NUM_BINS; i++) {
    if (fftData[i] > maxVal) {
      maxVal = fftData[i];
    }
  }
  
  // Draw axes
  fftBuffer.stroke(0);
  fftBuffer.strokeWeight(2);
  fftBuffer.line(MARGIN, FFT_BOTTOM, width - MARGIN, FFT_BOTTOM); // X-axis
  fftBuffer.line(MARGIN, MARGIN, MARGIN, FFT_BOTTOM); // Y-axis
  
  // X-axis labels (frequency)
  fftBuffer.fill(0);
  fftBuffer.textAlign(CENTER, TOP);
  fftBuffer.textSize(14);
  int plotWidth = width - 100;
  
  fftBuffer.text("0 Hz", MARGIN, FFT_BOTTOM + 5);
  fftBuffer.text(nf(NYQUIST/4, 0, 0) + " Hz", MARGIN + plotWidth/4, FFT_BOTTOM + 5);
  fftBuffer.text(nf(NYQUIST/2, 0, 0) + " Hz", MARGIN + plotWidth/2, FFT_BOTTOM + 5);
  fftBuffer.text(nf(3*NYQUIST/4, 0, 0) + " Hz", MARGIN + 3*plotWidth/4, FFT_BOTTOM + 5);
  fftBuffer.text(nf(NYQUIST, 0, 0) + " Hz", width - MARGIN, FFT_BOTTOM + 5);
  
  // Y-axis labels (magnitude)
  fftBuffer.textAlign(RIGHT, CENTER);
  for (int i = 0; i <= 5; i++) {
    float yPos = FFT_BOTTOM - i * FFT_HEIGHT / 5.0;
    float val = maxVal * i / 5.0;
    
    // Format based on magnitude size
    if (maxVal < 0.01) {
      fftBuffer.text(nf(val, 0, 6), 45, yPos);
    } else if (maxVal < 1.0) {
      fftBuffer.text(nf(val, 0, 4), 45, yPos);
    } else {
      fftBuffer.text(nf(val, 0, 2), 45, yPos);
    }
    
    // Grid lines
    fftBuffer.stroke(200);
    fftBuffer.strokeWeight(1);
    fftBuffer.line(MARGIN, yPos, width - MARGIN, yPos);
  }
  
  // Draw FFT data
  fftBuffer.stroke(0, 0, 255);
  fftBuffer.strokeWeight(1);
  fftBuffer.noFill();
  fftBuffer.beginShape();
  
  for (int i = 0; i < NUM_BINS; i++) {
    float x = map(i, 0, NUM_BINS - 1, MARGIN, width - MARGIN);
    float y = map(fftData[i], 0, maxVal, FFT_BOTTOM, MARGIN);
    fftBuffer.vertex(x, y);
  }
  
  fftBuffer.endShape();
  
  // Display info
  fftBuffer.fill(0);
  fftBuffer.textAlign(LEFT, TOP);
  fftBuffer.textSize(12);
  fftBuffer.text("FFT Size: " + FFT_SIZE, MARGIN + 10, MARGIN + 10);
  fftBuffer.text("Freq Resolution: " + nf(FREQ_RESOLUTION, 0, 2) + " Hz/bin", MARGIN + 10, MARGIN + 30);
  fftBuffer.text("Max Magnitude: " + nf(maxVal, 0, 4), MARGIN + 10, MARGIN + 50);
  
  fftBuffer.endDraw();
}

void updateWaterfall() {
  // Find max value for color scaling
  float maxVal = 0;
  for (int i = 0; i < NUM_BINS; i++) {
    if (fftData[i] > maxVal) {
      maxVal = fftData[i];
    }
  }
  if (maxVal == 0) maxVal = 1; // Prevent division by zero
  
  // Scroll existing waterfall up by copying pixels
  waterfall.beginDraw();
  waterfall.copy(0, 1, waterfall.width, waterfall.height - 1, 0, 0, waterfall.width, waterfall.height - 1);
  
  // Draw new line at bottom
  waterfall.loadPixels();
  for (int i = 0; i < NUM_BINS; i++) {
    float intensity = map(fftData[i], 0, maxVal, 0, 1);
    intensity = constrain(intensity, 0, 1);
    
    int x = int(map(i, 0, NUM_BINS - 1, 0, waterfall.width - 1));
    int pixelIndex = x + (waterfall.height - 1) * waterfall.width;
    
    // Color mapping: black -> blue -> green -> yellow -> red -> white
    waterfall.pixels[pixelIndex] = intensityToColor(intensity);
  }
  waterfall.updatePixels();
  waterfall.endDraw();
}

color intensityToColor(float val) {
  // Map 0-1 to color gradient: black -> blue -> cyan -> green -> yellow -> red -> white
  val = constrain(val, 0, 1);
  
  int r, g, b;
  
  if (val < 0.2) {
    // Black to blue
    float t = val / 0.2;
    r = 0;
    g = 0;
    b = int(t * 255);
  } else if (val < 0.4) {
    // Blue to cyan
    float t = (val - 0.2) / 0.2;
    r = 0;
    g = int(t * 255);
    b = 255;
  } else if (val < 0.6) {
    // Cyan to green
    float t = (val - 0.4) / 0.2;
    r = 0;
    g = 255;
    b = int((1 - t) * 255);
  } else if (val < 0.8) {
    // Green to yellow
    float t = (val - 0.6) / 0.2;
    r = int(t * 255);
    g = 255;
    b = 0;
  } else if (val < 0.95) {
    // Yellow to red
    float t = (val - 0.8) / 0.15;
    r = 255;
    g = int((1 - t) * 255);
    b = 0;
  } else {
    // Red to white
    float t = (val - 0.95) / 0.05;
    r = 255;
    g = int(t * 255);
    b = int(t * 255);
  }
  
  return color(r, g, b);
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
