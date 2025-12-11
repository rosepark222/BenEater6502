import processing.serial.*; //<>//

Serial myPort;
float amplitude = 0;
int volumeLevel = 0;
float dominantFreq = 0;

// FFT spectrum data
ArrayList<Float> fftSpectrum = new ArrayList<Float>();
int numFFTBins = 512;  // Changed from 32 to 512

// Smoothing variables
float smoothAmplitude = 0;
float smoothVolumeLevel = 0;
float smoothFreq = 0;

// Beat/Rhythm detection variables
float lastBeatTime = 0;
float beatThreshold = 0.08;
boolean beatDetected = false;
float bpm = 0;
float waveHeight = 50;

// Musical note detection
String[] noteNames = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"};
String currentNote = "--";
int currentOctave = 0;

void setup() {
  size(1200, 900);
  smooth();
  
  println("Available ports:");
  printArray(Serial.list());
  
  if (Serial.list().length > 0) {
    String portName = Serial.list()[0];
    println("Connecting to: " + portName);
    myPort = new Serial(this, portName, 115200);
    myPort.bufferUntil('\n');
    println("Connected successfully!");
  }
}

void serialEvent(Serial myPort) {
  String data = myPort.readStringUntil('\n');
  if (data != null) {
    data = trim(data);
    String[] values = split(data, ',');
    
    if (values.length >= 3) {
      amplitude = float(values[0]);
      volumeLevel = int(values[1]);
      dominantFreq = float(values[2]);
      
      // Parse FFT spectrum data if present (now expecting 512 bins)
      if (values.length > 3) {
        fftSpectrum.clear();
        for (int i = 3; i < values.length && fftSpectrum.size() < numFFTBins; i++) {
          try {
            fftSpectrum.add(float(values[i]));
          } catch (Exception e) {
            // Skip invalid values
          }
        }
      }
    }
  }
}

void draw() {
  // Smooth the values for less jarring transitions
  float smoothingFadeOut = 0.15;
  float smoothingFadeIn = 0.6;
  
  // Fast rise, slow fall for amplitude
  if (amplitude > smoothAmplitude) {
    smoothAmplitude = lerp(smoothAmplitude, amplitude, smoothingFadeIn);
  } else {
    smoothAmplitude = lerp(smoothAmplitude, amplitude, smoothingFadeOut);
  }
  
  // Fast rise, slow fall for volume level
  if (volumeLevel > smoothVolumeLevel) {
    smoothVolumeLevel = lerp(smoothVolumeLevel, volumeLevel, smoothingFadeIn);
  } else {
    smoothVolumeLevel = lerp(smoothVolumeLevel, volumeLevel, smoothingFadeOut);
  }
  
  // Fast rise, slow fall for frequency
  if (dominantFreq > smoothFreq) {
    smoothFreq = lerp(smoothFreq, dominantFreq, smoothingFadeIn);
  } else {
    smoothFreq = lerp(smoothFreq, dominantFreq, smoothingFadeOut);
  }
  
  // Beat detection
  if (amplitude > beatThreshold && !beatDetected) {
    float currentTime = millis() / 1000.0;
    float timeSinceLast = currentTime - lastBeatTime;
    
    if (lastBeatTime > 0 && timeSinceLast > 0.15 && timeSinceLast < 2.0) {
      bpm = 60.0 / timeSinceLast;
      waveHeight = map(constrain(bpm, 40, 200), 40, 200, 80, 250);
    } else if (lastBeatTime == 0) {
      bpm = 60;
      waveHeight = 100;
    }
    
    lastBeatTime = currentTime;
    beatDetected = true;
  }
  
  if (amplitude < beatThreshold * 0.6) {
    beatDetected = false;
  }
  
  // Reset BPM after 3 seconds
  float currentTime = millis() / 1000.0;
  if (currentTime - lastBeatTime > 3.0 && lastBeatTime > 0) {
    bpm = 0;
    waveHeight = 50;
  }
  
  // Detect musical note
  if (volumeLevel > 1 && smoothFreq > 50) {
    detectNote(smoothFreq);
  } else {
    currentNote = "--";
    currentOctave = 0;
  }
  
  int displayVolumeLevel = round(smoothVolumeLevel);
  
  // Background
  setGradient(0, 0, width, height, color(15, 20, 40), color(40, 25, 50));
  drawBackgroundPattern();
  
  // VOLUME SECTION
  pushMatrix();
  translate(50, 30);
  
  fill(255);
  textSize(24);
  textAlign(LEFT);
  text("♫ VOLUME", 0, 24);
  
  int segmentWidth = 130;
  int segmentHeight = 40;
  int spacing = 10;
  
  String[] volumeLabels = {"- Silent", "• Quiet", "♪ Talking", "♫ Loud", "⚡ Very Loud"};
  color[] volumeColors = {
    color(60, 60, 75),
    color(70, 150, 85),
    color(60, 130, 180),
    color(180, 150, 45),
    color(180, 65, 65)
  };
  
  for (int i = 0; i < 5; i++) {
    int x = i * (segmentWidth + spacing);
    
    if (i < displayVolumeLevel) {
      noStroke();
      fill(volumeColors[i], 40);
      for (int g = 8; g > 0; g--) {
        rect(x - g, 40 - g, segmentWidth + g*2, segmentHeight + g*2, 15);
      }
      
      fill(volumeColors[i]);
      noStroke();
      rect(x, 40, segmentWidth, segmentHeight, 12);
      
      noFill();
      stroke(255);
      strokeWeight(3);
      rect(x, 40, segmentWidth, segmentHeight, 12);
    } else {
      noFill();
      stroke(255);
      strokeWeight(3);
      rect(x, 40, segmentWidth, segmentHeight, 12);
    }
    
    fill(255);
    textSize(14);
    textAlign(CENTER);
    noStroke();
    text(volumeLabels[i], x + segmentWidth/2, 40 + segmentHeight + 25);
  }
  
  fill(255);
  textSize(20);
  textAlign(LEFT);
  String volText = "Level " + displayVolumeLevel;
  if (displayVolumeLevel == 5) volText += " - VERY LOUD!";
  text(volText, 0, 140);
  
  popMatrix();
  
  // PITCH SECTION
  pushMatrix();
  translate(50, 190);
  
  fill(255);
  textSize(24);
  textAlign(LEFT);
  text("♪ PITCH", 0, 24);
  
  int pitchSegmentWidth = 230;
  
  String[] pitchLabels = {"▼ Low (<400Hz)", "■ Medium (400-2000Hz)", "▲ High (>2000Hz)"};
  color[] pitchColors = {
    color(60, 180, 85),
    color(180, 170, 60),
    color(180, 60, 60)
  };
  
  for (int i = 0; i < 3; i++) {
    int x = i * (pitchSegmentWidth + spacing);
    
    boolean fillSegment = false;
    if (displayVolumeLevel > 1) {
      if (i == 0 && smoothFreq < 400) fillSegment = true;
      if (i == 1 && smoothFreq >= 400 && smoothFreq < 2000) fillSegment = true;
      if (i == 2 && smoothFreq >= 2000) fillSegment = true;
    }
    
    if (fillSegment) {
      noStroke();
      fill(pitchColors[i], 40);
      for (int g = 8; g > 0; g--) {
        rect(x - g, 40 - g, pitchSegmentWidth + g*2, segmentHeight + g*2, 15);
      }
      
      fill(pitchColors[i]);
      noStroke();
      rect(x, 40, pitchSegmentWidth, segmentHeight, 12);
      
      noFill();
      stroke(255);
      strokeWeight(3);
      rect(x, 40, pitchSegmentWidth, segmentHeight, 12);
    } else {
      noFill();
      stroke(255);
      strokeWeight(3);
      rect(x, 40, pitchSegmentWidth, segmentHeight, 12);
    }
    
    fill(255);
    textSize(14);
    textAlign(CENTER);
    noStroke();
    text(pitchLabels[i], x + pitchSegmentWidth/2, 40 + segmentHeight + 25);
  }
  
  fill(255);
  textSize(16);
  textAlign(LEFT);
  if (displayVolumeLevel > 1) {
    text("Frequency: " + nf(smoothFreq, 0, 1) + " Hz", 0, 120);
  } else {
    fill(150, 150, 170);
    text("Frequency: -- (volume too low)", 0, 120);
  }
  
  if (displayVolumeLevel > 1 && !currentNote.equals("--")) {
    fill(100, 255, 200);
    textSize(22);
    text("♪ Note: " + currentNote + currentOctave, 0, 145);
  }
  
  popMatrix();
  
  // LIVE AMPLITUDE
  pushMatrix();
  translate(50, 360);
  
  fill(255);
  textSize(24);
  textAlign(LEFT);
  text("~ LIVE AMPLITUDE", 0, 24);
  
  int ampBarWidth = 700;
  int ampBarHeight = 60;
  
  noStroke();
  fill(30, 30, 45);
  rect(0, 40, ampBarWidth, ampBarHeight, 12);
  
  float ampWidth = map(constrain(smoothAmplitude, 0, 1.0), 0, 1.0, 0, ampBarWidth - 8);
  
  color barColor;
  if (displayVolumeLevel == 0) barColor = color(50, 50, 65);
  else if (displayVolumeLevel == 1) barColor = color(70, 150, 85);
  else if (displayVolumeLevel == 2) barColor = color(60, 130, 180);
  else if (displayVolumeLevel == 3) barColor = color(180, 150, 45);
  else if (displayVolumeLevel == 4) barColor = color(180, 100, 45);
  else barColor = color(180, 60, 60);
  
  noStroke();
  fill(barColor, 60);
  for (int g = 6; g > 0; g--) {
    rect(4 - g/2, 44 - g/2, ampWidth + g, ampBarHeight - 8 + g, 10);
  }
  
  noStroke();
  fill(barColor);
  rect(4, 44, ampWidth, ampBarHeight - 8, 10);
  
  noFill();
  stroke(255);
  strokeWeight(3);
  rect(0, 40, ampBarWidth, ampBarHeight, 12);
  
  fill(255);
  textSize(16);
  textAlign(LEFT);
  text("Value: " + nf(smoothAmplitude, 0, 3), 0, ampBarHeight + 50);
  
  popMatrix();
  
  // TEMPO WAVE
  drawTempoWave();
  
  // Connection indicator
  float pulse = sin(frameCount * 0.1) * 0.3 + 0.7;
  fill(100, 255, 150, 255 * pulse);
  noStroke();
  ellipse(width - 40, 40, 24, 24);
  fill(100, 255, 150);
  ellipse(width - 40, 40, 16, 16);
}

void setGradient(int x, int y, float w, float h, color c1, color c2) {
  noFill();
  for (int i = y; i <= y+h; i++) {
    float inter = map(i, y, y+h, 0, 1);
    color c = lerpColor(c1, c2, inter);
    stroke(c);
    line(x, i, x+w, i);
  }
}

void drawBackgroundPattern() {
  noFill();
  
  stroke(255, 255, 255, 3);
  strokeWeight(1);
  for (int i = 0; i < width; i += 25) {
    float alpha = map(sin(i * 0.05 + frameCount * 0.02), -1, 1, 2, 8);
    stroke(255, 255, 255, alpha);
    line(i, 0, i, height);
  }
  for (int i = 0; i < height; i += 25) {
    float alpha = map(sin(i * 0.05 + frameCount * 0.02), -1, 1, 2, 8);
    stroke(255, 255, 255, alpha);
    line(0, i, width, i);
  }
  
  pushMatrix();
  translate(width * 0.85, height * 0.25, -200);
  rotateX(frameCount * 0.005);
  rotateY(frameCount * 0.008);
  for (int i = 0; i < 12; i++) {
    float radius = 60 + i * 12;
    stroke(100, 150, 255, 35 - i * 2);
    strokeWeight(2);
    drawArc(0, 0, 120 + sin(frameCount * 0.02 + i) * 30, radius, 6);
  }
  popMatrix();
  
  pushMatrix();
  translate(width * 0.15, height * 0.75, -150);
  rotateX(frameCount * 0.007);
  rotateY(-frameCount * 0.006);
  for (int i = 0; i < 10; i++) {
    float radius = 50 + i * 10;
    stroke(255, 150, 200, 30 - i * 2);
    strokeWeight(2);
    drawArc(0, 0, 90 + cos(frameCount * 0.03 + i) * 20, radius, 5);
  }
  popMatrix();
  
  pushMatrix();
  translate(width * 0.5, height * 0.5, -250);
  rotateX(frameCount * 0.003);
  rotateZ(frameCount * 0.004);
  for (int i = 0; i < 8; i++) {
    float radius = 80 + i * 15;
    stroke(150, 255, 150, 25 - i * 2);
    strokeWeight(1);
    drawArc(0, 0, 60 + sin(frameCount * 0.04 + i) * 15, radius, 4);
  }
  popMatrix();
  
  pushMatrix();
  translate(width * 0.2, height * 0.3);
  rotate(frameCount * 0.005);
  stroke(100, 200, 255, 15);
  strokeWeight(1);
  for (int i = 0; i < 4; i++) {
    drawHexagon(0, 0, 40 + i * 15);
  }
  popMatrix();
  
  pushMatrix();
  translate(width * 0.8, height * 0.7);
  rotate(-frameCount * 0.005);
  stroke(255, 150, 200, 15);
  strokeWeight(1);
  for (int i = 0; i < 4; i++) {
    drawHexagon(0, 0, 35 + i * 12);
  }
  popMatrix();
  
  float scanY = (frameCount * 1.5) % height;
  stroke(0, 255, 255, 30);
  strokeWeight(2);
  line(0, scanY, width, scanY);
  stroke(0, 255, 255, 15);
  strokeWeight(1);
  line(0, scanY - 10, width, scanY - 10);
  line(0, scanY + 10, width, scanY + 10);
  
  for (int i = 0; i < 6; i++) {
    float offset = frameCount * 1.5 + i * 150;
    float x = (offset % (width + 300)) - 150;
    float y = height * 0.4 + sin(frameCount * 0.02 + i) * 120;
    float pulse = sin(frameCount * 0.1 + i) * 0.5 + 0.5;
    stroke(255, 255, 255, 10 + pulse * 8);
    strokeWeight(2);
    ellipse(x, y, 100 + i * 20 + pulse * 20, 100 + i * 20 + pulse * 20);
  }
  
  stroke(0, 255, 200, 60);
  strokeWeight(3);
  line(20, 20, 80, 20);
  line(20, 20, 20, 80);
  line(width - 20, 20, width - 80, 20);
  line(width - 20, 20, width - 20, 80);
  line(20, height - 20, 80, height - 20);
  line(20, height - 20, 20, height - 80);
  line(width - 20, height - 20, width - 80, height - 20);
  line(width - 20, height - 20, width - 20, height - 80);
}

void drawHexagon(float x, float y, float size) {
  beginShape();
  for (int i = 0; i < 6; i++) {
    float angle = radians(i * 60);
    vertex(x + cos(angle) * size, y + sin(angle) * size);
  }
  endShape(CLOSE);
}

void drawTempoWave() {
  float waveBaseY = height - 240;  // Moved up to make more room for FFT
  
  // Draw FFT spectrum if we have data
  if (fftSpectrum.size() > 5) {
    drawFFTSpectrum();
  }
  
  // Draw tempo wave above FFT
  noFill();
  for (int layer = 0; layer < 3; layer++) {
    stroke(255, 100, 200, 100 - layer * 25);
    strokeWeight(4 - layer);
    beginShape();
    for (float x = 0; x < width; x += 8) {
      float waveAmplitude = 10 + waveHeight * 0.4;
      float y = waveBaseY + sin(x * 0.03 + frameCount * 0.08 + layer * 0.5) * waveAmplitude;
      vertex(x, y);
    }
    endShape();
  }
  
  fill(255, 150, 220, 255);
  textSize(18);
  textAlign(LEFT);
  if (bpm > 0) {
    text("♪ Tempo: " + nf(bpm, 0, 0) + " BPM", 20, waveBaseY + 50);
  } else {
    fill(150, 150, 170);
    text("♪ Tempo: -- (clap twice!)", 20, waveBaseY + 50);
  }
  
  fill(255, 255, 0);
  textSize(14);
  textAlign(RIGHT);
  text("Amp: " + nf(amplitude, 0, 3) + " | Freq: " + nf(smoothFreq, 0, 1) + "Hz | Note: " + currentNote + currentOctave, width - 20, waveBaseY + 50);
}

// Draw FULL SPECTRUM FFT analyzer at the bottom (512 bins)
void drawFFTSpectrum() {
  float spectrumBaseY = height - 80;
  float spectrumWidth = width - 100;
  
  // Calculate bar width - with 512 bins, bars will be very thin
  float barWidth = spectrumWidth / float(fftSpectrum.size());
  
  // For better performance and visibility with 512 bins, we can optionally downsample
  // by grouping adjacent bins. Here we'll draw every bin but they'll be very thin.
  
  // Label
  fill(100, 200, 255);
  textSize(20);
  textAlign(LEFT);
  text("⚡ FULL SPECTRUM FFT (512 bins, 0-22kHz)", 50, spectrumBaseY - 140);
  
  // Draw all 512 bins
  for (int i = 0; i < fftSpectrum.size(); i++) {
    float x = 50 + i * barWidth;
    float value = fftSpectrum.get(i);
    
    // Map FFT value to bar height
    float barHeight = map(value, 0, 100, 0, 120);
    
    // Color based on frequency range (low = blue, mid = green, high = red)
    float hue = map(i, 0, fftSpectrum.size(), 0.6, 0.0);
    colorMode(HSB, 1.0);
    
    // For thin bars, we'll use stroke instead of filled rectangles for better visibility
    if (barWidth < 2) {
      stroke(hue, 0.8, 0.9, 0.9);
      strokeWeight(1);
      line(x, spectrumBaseY, x, spectrumBaseY - barHeight);
      
      // Add glow for prominent frequencies
      if (barHeight > 30) {
        stroke(hue, 0.6, 1.0, 0.5);
        strokeWeight(2);
        line(x, spectrumBaseY, x, spectrumBaseY - barHeight);
      }
    } else {
      // If bars are wide enough, use filled rectangles
      fill(hue, 0.8, 0.9, 0.8);
      noStroke();
      rect(x, spectrumBaseY - barHeight, barWidth - 1, barHeight, 2);
      
      // Add glow effect for prominent bars
      if (barHeight > 20) {
        fill(hue, 0.6, 1.0, 0.3);
        rect(x - 1, spectrumBaseY - barHeight - 3, barWidth + 1, barHeight + 3, 3);
      }
    }
  }
  
  colorMode(RGB, 255);
  
  // Draw baseline
  stroke(255, 255, 255, 100);
  strokeWeight(2);
  line(50, spectrumBaseY, width - 50, spectrumBaseY);
  
  // Frequency labels with actual Hz values
  fill(150, 150, 170);
  textSize(12);
  textAlign(LEFT);
  text("0 Hz", 50, spectrumBaseY + 20);
  text("Bass", 50, spectrumBaseY + 35);
  
  textAlign(CENTER);
  text("~5.5 kHz", width/2, spectrumBaseY + 20);
  text("Mid", width/2, spectrumBaseY + 35);
  
  textAlign(RIGHT);
  text("~22 kHz", width - 50, spectrumBaseY + 20);
  text("Treble", width - 50, spectrumBaseY + 35);
  
  // Show bin count
  textAlign(LEFT);
  fill(100, 200, 255);
  textSize(12);
  text("Bins: " + fftSpectrum.size(), 50, spectrumBaseY - 155);
}

void drawArc(float x, float y, float degrees, float radius, float w) {
  beginShape();
  for (int i = 0; i < degrees; i += 2) {
    float angle = radians(i);
    vertex(x + cos(angle) * radius, y + sin(angle) * radius);
  }
  endShape();
  
  beginShape();
  for (int i = 0; i < degrees; i += 2) {
    float angle = radians(i);
    vertex(x + cos(angle) * (radius + w), y + sin(angle) * (radius + w));
  }
  endShape();
}

void detectNote(float freq) {
  float noteNum = 12 * (log(freq / 440.0) / log(2)) + 69;
  int midiNote = round(noteNum);
  currentOctave = (midiNote / 12) - 1;
  int noteIndex = midiNote % 12;
  float cents = (noteNum - midiNote) * 100;
  if (abs(cents) < 30) {
    currentNote = noteNames[noteIndex];
  } else {
    currentNote = noteNames[noteIndex] + "?";
  }
}
