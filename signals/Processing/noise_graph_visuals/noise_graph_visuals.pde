import processing.serial.*;

Serial myPort;
float amplitude = 0;
int volumeLevel = 0;
float dominantFreq = 0;

// Waveform data
ArrayList<Float> waveformData = new ArrayList<Float>();
int maxWaveformPoints = 50;

// Smoothing variables
float smoothAmplitude = 0;
float smoothVolumeLevel = 0;
float smoothFreq = 0;

// Beat/Rhythm detection variables
float lastBeatTime = 0;
float beatThreshold = 0.08;  // Very low threshold - detects small sounds
boolean beatDetected = false;
float bpm = 0;
float waveHeight = 50;  // Start with visible wave height

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
      
      // Parse waveform data if present
      if (values.length > 3) {
        waveformData.clear();
        for (int i = 3; i < values.length && i < 3 + maxWaveformPoints; i++) {
          try {
            waveformData.add(float(values[i]));
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
  float smoothingFadeOut = 0.15; // Slow fade out
  float smoothingFadeIn = 0.6;   // Fast response
  
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
  
  // Beat detection - detect sharp increases in amplitude
  if (amplitude > beatThreshold && !beatDetected) {
    float currentTime = millis() / 1000.0; // Current time in seconds
    float timeSinceLast = currentTime - lastBeatTime;
    
    // Calculate BPM from time between beats
    if (lastBeatTime > 0 && timeSinceLast > 0.15 && timeSinceLast < 2.0) {
      bpm = 60.0 / timeSinceLast; // Calculate BPM
      waveHeight = map(constrain(bpm, 40, 200), 40, 200, 80, 250); // Map BPM to wave height
    } else if (lastBeatTime == 0) {
      // First beat - show immediate feedback
      bpm = 60; // Start with 60 BPM placeholder
      waveHeight = 100;
    }
    
    lastBeatTime = currentTime;
    beatDetected = true;
  }
  
  // Reset beat detection when amplitude drops (faster reset)
  if (amplitude < beatThreshold * 0.6) {
    beatDetected = false;
  }
  
  // Reset BPM after 3 seconds of no beats
  float currentTime = millis() / 1000.0;
  if (currentTime - lastBeatTime > 3.0 && lastBeatTime > 0) {
    bpm = 0;
    waveHeight = 50; // Reset to default wave height
  }
  
  // Slowly decay wave height but keep minimum visible
  waveHeight = lerp(waveHeight, 50, 0.02);
  
  // Use smoothed volume level for display
  int displayVolumeLevel = round(smoothVolumeLevel);
  
  // Sleek gradient background - dark blue to purple
  setGradient(0, 0, width, height, color(15, 20, 40), color(40, 25, 50));
  
  // Background decorative elements
  drawBackgroundPattern();
  
  // Draw tempo wave in FRONT of background
  drawTempoWave();
  
  // ===== VOLUME SECTION =====
  pushMatrix();
  translate(50, 40);
  
  // Title - clean and crisp
  fill(255);
  textSize(28);
  textAlign(LEFT);
  text("♫ VOLUME", 0, 28);
  
  // Draw 5 volume segments with modern style
  int segmentWidth = 150;
  int segmentHeight = 50;
  int spacing = 12;
  
  String[] volumeLabels = {"- Silent", "• Quiet", "♪ Talking", "♫ Loud", "⚡ Very Loud"};
  color[] volumeColors = {
    color(80, 80, 100),      // Silent - Dark Gray
    color(100, 220, 120),    // Quiet - Green
    color(80, 180, 255),     // Talking - Cyan
    color(255, 220, 60),     // Clapping - Yellow
    color(255, 90, 90)       // Banging - Red
  };
  
  for (int i = 0; i < 5; i++) {
    int x = i * (segmentWidth + spacing);
    
    // Filled segment with rounded corners and glow
    if (i < displayVolumeLevel) {
      // Glow effect
      noStroke();
      fill(volumeColors[i], 40);
      for (int g = 8; g > 0; g--) {
        rect(x - g, 40 - g, segmentWidth + g*2, segmentHeight + g*2, 15);
      }
      
      // Main filled bar
      fill(volumeColors[i]);
      noStroke();
      rect(x, 40, segmentWidth, segmentHeight, 12);
      
      // Thick outline for filled bars
      noFill();
      stroke(255);
      strokeWeight(3);
      rect(x, 40, segmentWidth, segmentHeight, 12);
    } else {
      // Empty segment - thick outline
      noFill();
      stroke(255);
      strokeWeight(3);
      rect(x, 40, segmentWidth, segmentHeight, 12);
    }
    
    // Label - crisp white text
    fill(255);
    textSize(14);
    textAlign(CENTER);
    noStroke();
    text(volumeLabels[i], x + segmentWidth/2, 40 + segmentHeight + 25);
  }
  
  // Volume level indicator text
  fill(255, 255, 255);
  textSize(20);
  textAlign(LEFT);
  String volText = "Level " + displayVolumeLevel;
  if (displayVolumeLevel == 5) volText += " - VERY LOUD!";
  text(volText, 0, 140);
  
  popMatrix();
  
  // ===== PITCH SECTION =====
  pushMatrix();
  translate(50, 250);
  
  // Title - clean and crisp
  fill(255);
  textSize(28);
  textAlign(LEFT);
  text("♪ PITCH", 0, 28);
  
  // Draw 3 pitch segments
  int pitchSegmentWidth = 270;
  
  String[] pitchLabels = {"▼ Low (<400Hz)", "■ Medium (400-2000Hz)", "▲ High (>2000Hz)"};
  color[] pitchColors = {
    color(80, 255, 120),    // Low - Bright Green
    color(255, 240, 80),    // Medium - Bright Yellow
    color(255, 80, 80)      // High - Bright Red
  };
  
  for (int i = 0; i < 3; i++) {
    int x = i * (pitchSegmentWidth + spacing);
    
    // Determine which segment to fill
    boolean fillSegment = false;
    if (displayVolumeLevel > 1) {
      if (i == 0 && smoothFreq < 400) fillSegment = true;
      if (i == 1 && smoothFreq >= 400 && smoothFreq < 2000) fillSegment = true;
      if (i == 2 && smoothFreq >= 2000) fillSegment = true;
    }
    
    // Filled segment with glow
    if (fillSegment) {
      // Glow effect
      noStroke();
      fill(pitchColors[i], 40);
      for (int g = 8; g > 0; g--) {
        rect(x - g, 40 - g, pitchSegmentWidth + g*2, segmentHeight + g*2, 15);
      }
      
      // Main filled bar
      fill(pitchColors[i]);
      noStroke();
      rect(x, 40, pitchSegmentWidth, segmentHeight, 12);
      
      // Thick outline for filled bars
      noFill();
      stroke(255);
      strokeWeight(3);
      rect(x, 40, pitchSegmentWidth, segmentHeight, 12);
    } else {
      // Empty segment - thick outline
      noFill();
      stroke(255);
      strokeWeight(3);
      rect(x, 40, pitchSegmentWidth, segmentHeight, 12);
    }
    
    // Label - crisp white text
    fill(255);
    textSize(14);
    textAlign(CENTER);
    noStroke();
    text(pitchLabels[i], x + pitchSegmentWidth/2, 40 + segmentHeight + 25);
  }
  
  // Frequency text and musical note
  fill(255, 255, 255);
  textSize(20);
  textAlign(LEFT);
  if (displayVolumeLevel > 1) {
    text("Frequency: " + nf(smoothFreq, 0, 1) + " Hz", 0, 140);
  } else {
    fill(150, 150, 170);
    text("Frequency: -- (volume too low)", 0, 140);
  }
  
  // Display musical note on separate line
  if (displayVolumeLevel > 1 && !currentNote.equals("--")) {
    fill(100, 255, 200);
    textSize(28);
    text("♪ Note: " + currentNote + currentOctave, 0, 175);
  }
  
  popMatrix();
  
  // ===== LIVE AMPLITUDE WAVEFORM =====
  pushMatrix();
  translate(50, 460);
  
  // Title - clean and crisp
  fill(255);
  textSize(28);
  textAlign(LEFT);
  text("~ LIVE AMPLITUDE", 0, 28);
  
  int ampBarWidth = 800;
  int ampBarHeight = 80;
  
  // Background bar
  noStroke();
  fill(30, 30, 45);
  rect(0, 40, ampBarWidth, ampBarHeight, 12);
  
  // Filled amplitude with gradient
  float ampWidth = map(constrain(smoothAmplitude, 0, 1.0), 0, 1.0, 0, ampBarWidth - 8);
  
  // Color based on volume level with gradient - reduced brightness
  color barColor;
  if (displayVolumeLevel == 0) barColor = color(50, 50, 65);
  else if (displayVolumeLevel == 1) barColor = color(70, 150, 85);
  else if (displayVolumeLevel == 2) barColor = color(60, 130, 180);
  else if (displayVolumeLevel == 3) barColor = color(180, 150, 45);
  else if (displayVolumeLevel == 4) barColor = color(180, 100, 45);
  else barColor = color(180, 60, 60);
  
  // Glow effect
  noStroke();
  fill(barColor, 60);
  for (int g = 6; g > 0; g--) {
    rect(4 - g/2, 44 - g/2, ampWidth + g, ampBarHeight - 8 + g, 10);
  }
  
  // Main bar (no outline)
  noStroke();
  fill(barColor);
  rect(4, 44, ampWidth, ampBarHeight - 8, 10);
  
  // Outline for container only
  noFill();
  stroke(255);
  strokeWeight(3);
  rect(0, 40, ampBarWidth, ampBarHeight, 12);
  
  // Amplitude value
  fill(255);
  textSize(18);
  textAlign(LEFT);
  text("Value: " + nf(smoothAmplitude, 0, 3), 0, ampBarHeight + 60);
  
  popMatrix();
  
  // Draw tempo wave at the very bottom (won't overlap with amplitude bar)
  drawTempoWave();
  
  // Connection indicator (pulsing)
  float pulse = sin(frameCount * 0.1) * 0.3 + 0.7;
  fill(100, 255, 150, 255 * pulse);
  noStroke();
  ellipse(width - 40, 40, 24, 24);
  fill(100, 255, 150);
  ellipse(width - 40, 40, 16, 16);
}

// Helper function for gradient background
void setGradient(int x, int y, float w, float h, color c1, color c2) {
  noFill();
  for (int i = y; i <= y+h; i++) {
    float inter = map(i, y, y+h, 0, 1);
    color c = lerpColor(c1, c2, inter);
    stroke(c);
    line(x, i, x+w, i);
  }
}

// Background decorative pattern
void drawBackgroundPattern() {
  noFill();
  
  // Tech grid lines with fade effect
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
  
  // Rotating 3D arcs in background - more of them
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
  
  // Second set of arcs
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
  
  // Third arc cluster - center
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
  
  // Static hexagonal tech pattern
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
  
  // Slow scanning line effect
  float scanY = (frameCount * 1.5) % height;
  stroke(0, 255, 255, 30);
  strokeWeight(2);
  line(0, scanY, width, scanY);
  stroke(0, 255, 255, 15);
  strokeWeight(1);
  line(0, scanY - 10, width, scanY - 10);
  line(0, scanY + 10, width, scanY + 10);
  
  // Pulsing concentric circles
  for (int i = 0; i < 6; i++) {
    float offset = frameCount * 1.5 + i * 150;
    float x = (offset % (width + 300)) - 150;
    float y = height * 0.4 + sin(frameCount * 0.02 + i) * 120;
    
    float pulse = sin(frameCount * 0.1 + i) * 0.5 + 0.5;
    stroke(255, 255, 255, 10 + pulse * 8);
    strokeWeight(2);
    ellipse(x, y, 100 + i * 20 + pulse * 20, 100 + i * 20 + pulse * 20);
  }
  
  // Corner HUD elements
  pushMatrix();
  translate(60, 60);
  rotate(frameCount * 0.01);
  stroke(150, 100, 255, 35);
  strokeWeight(2);
  noFill();
  for (int i = 0; i < 8; i++) {
    float size = 15 + i * 6;
    rect(-size/2, -size/2, size, size);
  }
  popMatrix();
  
  pushMatrix();
  translate(width - 60, height - 60);
  rotate(-frameCount * 0.01);
  stroke(255, 150, 100, 35);
  strokeWeight(2);
  noFill();
  for (int i = 0; i < 8; i++) {
    float size = 15 + i * 6;
    ellipse(0, 0, size, size);
  }
  popMatrix();
  
  // Tech corner brackets (static)
  stroke(0, 255, 200, 60);
  strokeWeight(3);
  // Top left
  line(20, 20, 80, 20);
  line(20, 20, 20, 80);
  // Top right
  line(width - 20, 20, width - 80, 20);
  line(width - 20, 20, width - 20, 80);
  // Bottom left
  line(20, height - 20, 80, height - 20);
  line(20, height - 20, 20, height - 80);
  // Bottom right
  line(width - 20, height - 20, width - 80, height - 20);
  line(width - 20, height - 20, width - 20, height - 80);
  
  // Radar sweep effect in corner
  pushMatrix();
  translate(width - 100, 100);
  rotate(frameCount * 0.02);
  stroke(0, 255, 150, 30);
  strokeWeight(2);
  for (int i = 0; i < 360; i += 30) {
    float angle = radians(i);
    line(0, 0, cos(angle) * 60, sin(angle) * 60);
  }
  // Sweep line
  stroke(0, 255, 150, 80);
  strokeWeight(3);
  line(0, 0, 60, 0);
  popMatrix();
  
  // Floating waveform lines
  for (int i = 0; i < 4; i++) {
    stroke(100 + i * 30, 200, 255 - i * 30, 20);
    strokeWeight(2);
    noFill();
    beginShape();
    for (float x = 0; x < width; x += 8) {
      float y = height * (0.25 + i * 0.2) + sin(x * 0.015 + frameCount * 0.05 + i * 2) * 25;
      vertex(x, y);
    }
    endShape();
  }
}

// Helper to draw hexagon
void drawHexagon(float x, float y, float size) {
  beginShape();
  for (int i = 0; i < 6; i++) {
    float angle = radians(i * 60);
    vertex(x + cos(angle) * size, y + sin(angle) * size);
  }
  endShape(CLOSE);
}

// Draw tempo wave that rises with BPM
void drawTempoWave() {
  // Fixed position at very bottom of screen
  float waveBaseY = height - 60;
  
  // Always show the wave at fixed position
  noFill();
  
  // Draw multiple wave layers - amplitude of wave increases with tempo
  for (int layer = 0; layer < 3; layer++) {
    stroke(255, 100, 200, 100 - layer * 25);  // Pink/magenta color
    strokeWeight(4 - layer);
    
    beginShape();
    for (float x = 0; x < width; x += 8) {
      // Only the wave amplitude changes, not the base position
      float waveAmplitude = 10 + waveHeight * 0.4;  // Wave gets taller with faster tempo
      float y = waveBaseY + sin(x * 0.03 + frameCount * 0.08 + layer * 0.5) * waveAmplitude;
      vertex(x, y);
    }
    endShape();
  }
  
  // BPM text - stationary on the left side
  fill(255, 150, 220, 255);
  textSize(18);
  textAlign(LEFT);
  if (bpm > 0) {
    text("♪ Tempo: " + nf(bpm, 0, 0) + " BPM", 20, height - 25);
  } else {
    fill(150, 150, 170);
    text("♪ Tempo: -- (clap twice!)", 20, height - 25);
  }
  
  // Debug info on right side
  fill(255, 255, 0);
  textSize(14);
  textAlign(RIGHT);
  text("Amp: " + nf(amplitude, 0, 3) + " | Freq: " + nf(smoothFreq, 0, 1) + "Hz | Note: " + currentNote + currentOctave, width - 20, height - 45);
}

// Helper to draw arc shapes
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

// Helper function for glowing text
void drawGlowText(String txt, float x, float y, int size, color c) {
  textAlign(LEFT);
  // Glow layers
  for (int i = 8; i > 0; i--) {
    fill(c, 30);
    textSize(size + i);
    text(txt, x, y + size);
  }
  // Main text
  fill(255);
  textSize(size);
  text(txt, x, y + size);
}
