/*
write a processing code drawing FFT 
1, use the below teensy code which is sending FFT result  
2, use 44.1khz sampling rate  , so draw 0 to 22.05khz 
3, also freq resolution should be 44.1khz / 1024, because sample size is 1024
4, make the drawing as simple as possible, no color coding. just add 5 labels on X axis (0 hz, fs/4, fs/2, 3*fs/4, fs). 
5, mark the fft values on Y axis

6, add waterfall spectrogram 

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

// Waterfall parameters
final int WATERFALL_HEIGHT = 300;
PGraphics waterfall;
int waterfallRows;

void setup() {
  size(1200, 950);
  
  // List all available serial ports
  printArray(Serial.list());
  
  // Change the index [0] to match your Teensy port
  String portName = Serial.list()[0];
  myPort = new Serial(this, portName, 115200);
  myPort.bufferUntil('\n');
  
  // Initialize waterfall display
  waterfallRows = WATERFALL_HEIGHT;
  waterfall = createGraphics(NUM_BINS, waterfallRows);
  waterfall.beginDraw();
  waterfall.background(0);
  waterfall.endDraw();
}

void draw() {
  background(255);
  
  if (newData) {
    drawFFT();
    drawWaterfall();
    newData = false; // Reset after drawing
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
  
  int fftHeight = 300;
  int fftTop = 50;
  int fftBottom = fftTop + fftHeight;
  
  // Draw axes
  stroke(0);
  strokeWeight(2);
  line(50, fftBottom, width - 50, fftBottom); // X-axis
  line(50, fftTop, 50, fftBottom); // Y-axis
  
  // X-axis labels (frequency)
  fill(0);
  textAlign(CENTER, TOP);
  textSize(14);
  int plotWidth = width - 100;
  
  text("0 Hz", 50, fftBottom + 5);
  text(nf(NYQUIST/4, 0, 0) + " Hz", 50 + plotWidth/4, fftBottom + 5);
  text(nf(NYQUIST/2, 0, 0) + " Hz", 50 + plotWidth/2, fftBottom + 5);
  text(nf(3*NYQUIST/4, 0, 0) + " Hz", 50 + 3*plotWidth/4, fftBottom + 5);
  text(nf(NYQUIST, 0, 0) + " Hz", width - 50, fftBottom + 5);
  
  // Y-axis labels (magnitude)
  textAlign(RIGHT, CENTER);
  for (int i = 0; i <= 5; i++) {
    float yPos = fftBottom - i * fftHeight / 5.0;
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
    float y = map(fftData[i], 0, maxVal, fftBottom, fftTop);
    vertex(x, y);
  }
  
  endShape();
  
  // Display info
  fill(0);
  textAlign(LEFT, TOP);
  textSize(12);
  text("FFT Size: " + FFT_SIZE, 60, fftTop + 10);
  text("Freq Resolution: " + nf(FREQ_RESOLUTION, 0, 2) + " Hz/bin", 60, fftTop + 30);
  text("Max Magnitude: " + nf(maxVal, 0, 4), 60, fftTop + 50);
}

void drawWaterfall() {
  // Update waterfall with new FFT data
  updateWaterfall();
  
  // Draw waterfall spectrogram
  int waterfallTop = 400;
  int waterfallBottom = waterfallTop + WATERFALL_HEIGHT;
  
  // Draw the waterfall image
  image(waterfall, 50, waterfallTop, width - 100, WATERFALL_HEIGHT);
  
  // Draw frame around waterfall
  noFill();
  stroke(0);
  strokeWeight(2);
  rect(50, waterfallTop, width - 100, WATERFALL_HEIGHT);
  
  // X-axis labels (frequency) - same as FFT
  fill(0);
  textAlign(CENTER, TOP);
  textSize(14);
  int plotWidth = width - 100;
  
  text("0 Hz", 50, waterfallBottom + 5);
  text(nf(NYQUIST/4, 0, 0) + " Hz", 50 + plotWidth/4, waterfallBottom + 5);
  text(nf(NYQUIST/2, 0, 0) + " Hz", 50 + plotWidth/2, waterfallBottom + 5);
  text(nf(3*NYQUIST/4, 0, 0) + " Hz", 50 + 3*plotWidth/4, waterfallBottom + 5);
  text(nf(NYQUIST, 0, 0) + " Hz", width - 50, waterfallBottom + 5);
  
  // Y-axis label
  fill(0);
  textAlign(CENTER, CENTER);
  pushMatrix();
  translate(20, waterfallTop + WATERFALL_HEIGHT/2);
  rotate(-HALF_PI);
  text("Time (newest at top)", 0, 0);
  popMatrix();
  
  // Title
  textAlign(LEFT, TOP);
  textSize(14);
  fill(0);
  text("Waterfall Spectrogram", 60, waterfallTop - 25);
}

void updateWaterfall() {
  // Scroll waterfall down by copying pixels
  waterfall.beginDraw();
  waterfall.copy(0, 0, NUM_BINS, waterfallRows - 1, 0, 1, NUM_BINS, waterfallRows - 1);
  
  // Find max value for color scaling
  float maxVal = 0;
  for (int i = 0; i < NUM_BINS; i++) {
    if (fftData[i] > maxVal) {
      maxVal = fftData[i];
    }
  }
  
  // Add new row at top
  for (int i = 0; i < NUM_BINS; i++) {
    // Normalize to 0-1 range
    float normalized = maxVal > 0 ? fftData[i] / maxVal : 0;
    
    // Apply log scaling for better visualization
    normalized = sqrt(normalized); // sqrt gives good visual range
    
    // Convert to color (blue=low, red=high)
    int colorValue = getColorForValue(normalized);
    
    waterfall.set(i, 0, colorValue);
  }
  
  waterfall.endDraw();
}

int getColorForValue(float normalized) {
  // Create color map: black -> blue -> cyan -> green -> yellow -> red
  normalized = constrain(normalized, 0, 1);
  
  if (normalized < 0.2) {
    // Black to blue
    float t = normalized / 0.2;
    return color(0, 0, t * 255);
  } else if (normalized < 0.4) {
    // Blue to cyan
    float t = (normalized - 0.2) / 0.2;
    return color(0, t * 255, 255);
  } else if (normalized < 0.6) {
    // Cyan to green
    float t = (normalized - 0.4) / 0.2;
    return color(0, 255, (1 - t) * 255);
  } else if (normalized < 0.8) {
    // Green to yellow
    float t = (normalized - 0.6) / 0.2;
    return color(t * 255, 255, 0);
  } else {
    // Yellow to red
    float t = (normalized - 0.8) / 0.2;
    return color(255, (1 - t) * 255, 0);
  }
}

void serialEvent(Serial myPort) {
  String inString = myPort.readStringUntil('\n');
  
  if (inString != null) {
    inString = trim(inString);
    
    if (inString.equals("FFT_DATA_START")) {
      buffer = "";
    } else if (inString.equals("FFT_DATA_END")) {
      parseFFTData(buffer);
      newData = true;
    } else if (inString.startsWith("CORR:")) {
      // Extract data after "CORR:"
      buffer = inString.substring(5);
    }
  }
}

void parseFFTData(String data) {
  String[] values = split(data, ',');
  
  if (values.length == NUM_BINS || values.length == FFT_SIZE) {
    int numToParse = min(NUM_BINS, values.length);
    for (int i = 0; i < numToParse; i++) {
      fftData[i] = abs(float(values[i])); // Use absolute value
    }
    println("Received " + numToParse + " values. Max: " + max(fftData));
  } else {
    println("Warning: Expected " + NUM_BINS + " values, got " + values.length);
  }
}
