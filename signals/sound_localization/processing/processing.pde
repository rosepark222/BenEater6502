import processing.serial.*; //<>//

Serial myPort;
boolean newFrameAvailable = false; 

// MODE SWITCHING: Current mode and mode transition state
int currentMode = 2; // 0=FFT, 1=CORR, 2=EYE, 3=GAME
int requestedMode = -1; // -1 means no mode change requested
boolean waitingForAck = false; // Waiting for acknowledgment from Teensy
boolean modeChanging = false; // In the process of changing modes
String modeChangeStatus = ""; // Status message to display
ArrayList<String> debugMessages = new ArrayList<String>(); // Store debug messages
int maxDebugMessages = 10; // Keep last 10 messages

// Eye class for demo mode - DEFINED FIRST
class Eye {
  int x, y;
  int size;
  float angle = 0.0;
  int eyex, eyey;

  Eye(int tx, int ty, int ts) {
    x = tx;
    y = ty;
    size = ts;
  }

  void update(int mx, int my) {
    // angle = atan2(my - y, mx - x);
    eyex = mx;
    eyey = my;
  }

  void display() {
    pushMatrix();
    translate(x, y);
    fill(255);
    ellipse(0, 0, size, 2*size);
    //rotate(angle);
    // fill(153, 204, 0); yellowish green
    fill(0);  // black
    ellipse(eyex, eyey, size/2, size/2);
    popMatrix();
  }
  
  void display2() {
    pushMatrix();
    translate(x, y);
    fill(255);
    ellipse(0, 0, size, 2*size);
    rotate(angle);
    // fill(153, 204, 0); yellowish green
    fill(0);  // black
    ellipse(size/4, 0, size/2, size/2);
    popMatrix();
  }
}

// GAME MODE: Mosquito class for mosquito hunting game
class Mosquito {
  float x, y;
  float size;
  boolean alive;
  float wingAngle;
  float wingSpeed;
  float hoverOffsetX, hoverOffsetY;
  float hoverAngle;
  
  Mosquito() {
    respawn();
    wingAngle = 0;
    wingSpeed = 0.3;
    hoverAngle = random(TWO_PI);
  }
  
  void respawn() {
    // Spawn in random location (with margins)
    x = random(150, width - 150);
    y = random(150, height - 150);
    size = 30;
    alive = true;
  }
  
  void update() {
    if (!alive) return;
    
    // Animate wings
    wingAngle += wingSpeed;
    
    // Hovering motion
    hoverAngle += 0.05;
    hoverOffsetX = cos(hoverAngle) * 10;
    hoverOffsetY = sin(hoverAngle * 1.3) * 8;
  }
  
  void display() {
    if (!alive) return;
    
    pushMatrix();
    translate(x + hoverOffsetX, y + hoverOffsetY);
    
    // Body (dark gray/black)
    fill(50);
    stroke(30);
    strokeWeight(1);
    ellipse(0, 0, size * 0.4, size * 0.8); // Elongated body
    
    // Head
    fill(60);
    ellipse(0, -size * 0.4, size * 0.35, size * 0.35);
    
    // Eyes (red for evil look)
    fill(255, 0, 0);
    noStroke();
    ellipse(-size * 0.08, -size * 0.42, size * 0.1, size * 0.1);
    ellipse(size * 0.08, -size * 0.42, size * 0.1, size * 0.1);
    
    // Wings (animated)
    stroke(150, 150, 200, 100);
    strokeWeight(1);
    fill(200, 200, 255, 80);
    
    // Left wing
    pushMatrix();
    rotate(sin(wingAngle) * 0.3);
    ellipse(-size * 0.25, 0, size * 0.6, size * 0.3);
    popMatrix();
    
    // Right wing
    pushMatrix();
    rotate(-sin(wingAngle) * 0.3);
    ellipse(size * 0.25, 0, size * 0.6, size * 0.3);
    popMatrix();
    
    // Legs (thin lines)
    stroke(50);
    strokeWeight(1);
    line(0, size * 0.3, -size * 0.15, size * 0.5);
    line(0, size * 0.3, size * 0.15, size * 0.5);
    
    popMatrix();
  }
  
  // Check if clap position is near mosquito
  boolean checkHit(float clapX, float clapY, float threshold) {
    if (!alive) return false;
    
    float distance = dist(x, y, clapX, clapY);
    return distance < threshold;
  }
  
  void kill() {
    alive = false;
  }
}

// GAME MODE: Game state variables
Mosquito mosquito;
int gameScore = 0;
int killDistance = 100; // How close the clap needs to be
ArrayList<String> gameMessages = new ArrayList<String>();
int lastClapX = -1, lastClapY = -1;
long lastClapTime = 0;

// FFT data storage
float[] fft_data = new float[512]; // MODE: FFT - 512 magnitude bins
float[] correlation_data = new float[1024]; // MODE: CORR - 1024 correlation samples
float[] corr_roated = new float[1024];
//float[] mic1_phase = new float[512];
//float[] mic2_magnitude = new float[512];
//float[] mic2_phase = new float[512];

// ANTI-FLICKER: PGraphics buffers for smooth rendering
PGraphics fftBuffer;
PGraphics corrBuffer;
PGraphics waterfallBuffer; // Waterfall for FFT mode
boolean fftBufferReady = false;
boolean corrBufferReady = false;

// Waterfall parameters for FFT mode
final int FFT_GRAPH_HEIGHT = 300;
final int WATERFALL_HEIGHT = 300;
int waterfallRows;

//int displayBins = 20;  // Only display first 24 bins (0-1000 Hz)
int displayBins = 1024;  // Only display first 24 bins (0-1000 Hz)

boolean showEyes = false;  // Toggle between FFT display and eyes demo
String sure_signal = "";

Eye e1, e2 ;

// Timing diagnostics
long lastFrameTime = 0;
long frameArrivalTime = 0;
long frameDrawEndTime = 0;
float timeBetweenFrames = 0;
float timeToDrawFrame = 0;
int frameCount = 0;

// Receiving state
boolean receivingData = false;
String currentMic = "";

float max_value = 0;
int  max_idx = 0;

float mic01_phat_peak_value = -1;
float mic01_phat_peak_idx = -10;
float mic01_phat_second_value = -1;
float mic01_phat_second_idx = -10;
float mic01_psr = 0;

float mic23_phat_peak_value = -1;
float mic23_phat_peak_idx = -10;
float mic23_phat_second_value = -1;
float mic23_phat_second_idx = -10;
float mic23_psr = 0;

float last_max_value = 0;
int  last_max_idx = 0;
  
void setup() {
  size(1400, 1000);
  smooth();

  e1 = new Eye(820, 430, 220);
  e2 = new Eye(420, 430, 220);
  
  // GAME MODE: Initialize mosquito
  mosquito = new Mosquito();
  
  // ANTI-FLICKER: Initialize PGraphics buffers
  fftBuffer = createGraphics(width, height);
  corrBuffer = createGraphics(width, height);
  
  // Initialize waterfall buffer for FFT mode
  waterfallRows = WATERFALL_HEIGHT;
  waterfallBuffer = createGraphics(512, waterfallRows);
  waterfallBuffer.beginDraw();
  waterfallBuffer.background(0);
  waterfallBuffer.endDraw();

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

/*
Data Size: 512 floats * 4 bytes/float = 2048 bytes (2 KB) of data.
Teensy 4.1 Capability: The Teensy 4.1 can achieve speeds of over 20 MB/second
(megabytes per second) when optimized, and in some benchmarks even higher.
The theoretical maximum for USB 2.0 high-speed is around 60 MB/sec.


    myPort.bufferUntil(char): This is the most common use case. The serialEvent()
    is called every time the specified termination character (e.g., a newline \n or
    carriage return \r) is received. This is useful for processing complete "packets"
    or lines of data sent from a device like an Arduino.

https://forum.pjrc.com/index.php?threads/fft-number-of-samples.53146/#:~:text=1024%20is%20the%20number%20of,section%20of%20the%20video%20walkthrough.
1024 is the number of audio samples it analyzes. At 44.1 kHz, each FFT result
represents the spectrum based on 23.2 ms of time. By default a Hanning window scaling
is applied, so you're getting results that mostly represent the middle ~13 ms of that time.
This is covered in detail in the tutorial. Check out pages 27-29 in the tutorial PDF, or
watch that section of the video walkthrough.

512 mag send < 22.3msec
512 mag, 512 phase  -->   about 40msec
512 mag, 512 phase for both mic1 and 2 --> about 60 msec
*/

// MODE SWITCHING: Send mode change request to Teensy
// HANDSHAKE: Sends command and sets flag to wait for acknowledgment
void requestModeChange(int newMode) {
  if (waitingForAck || modeChanging) {
    println("WARNING: Already changing mode, ignoring request");
    return; // Don't send if already waiting for response
  }
  
  requestedMode = newMode;
  waitingForAck = true;
  modeChanging = true;
  
  // Send mode command to Teensy
  String command = "";
  if (newMode == 0) {
    command = "MODE_FFT\n";
    modeChangeStatus = "Requesting FFT mode...";
  } else if (newMode == 1) {
    command = "MODE_CORR\n";
    modeChangeStatus = "Requesting CORR mode...";
  } else if (newMode == 2) {
    command = "MODE_EYE\n";
    modeChangeStatus = "Requesting EYE mode...";
  } else if (newMode == 3) {
    command = "MODE_GAME\n";
    modeChangeStatus = "Requesting GAME mode...";
  }
  
  myPort.write(command); // Send command to Teensy
  println("SENT: " + command.trim());
}

void serialEvent(Serial myPort) {
  if (myPort == null) return;

  String data = myPort.readStringUntil('\n');
  if (data != null) {
    data = trim(data);
    
    // DEBUG: Capture debug messages from Teensy
    if (data.startsWith("DEBUG:")) {
      addDebugMessage(data);
      println(data);
      return;
    }
    
    // DEBUG: Capture heartbeat messages from Teensy
    if (data.startsWith("HEARTBEAT:")) {
      addDebugMessage("Teensy alive: " + data.substring(10));
      println(data);
      return;
    }
    
    // HANDSHAKE: Check for acknowledgment from Teensy
    if (data.startsWith("ACK:MODE_")) {
      if (waitingForAck) {
        modeChangeStatus = "Received acknowledgment: " + data;
        addDebugMessage("ACK received: " + data);
        println("RECEIVED: " + data);
        waitingForAck = false; // Got the acknowledgment
        
        // BUFFER CORRUPTION PREVENTION: Clear serial buffer to discard any old data
        myPort.clear();
        
        // BUFFER CORRUPTION PREVENTION: Reset receiving state to ignore partial packets
        receivingData = false;
        currentMic = "";
      }
      return;
    }
    
    // HANDSHAKE: Check for mode change confirmation from Teensy
    if (data.startsWith("MODE_CHANGED:")) {
      int newMode = int(data.substring(13));
      currentMode = newMode; // Update our current mode
      modeChanging = false; // Mode change complete
      requestedMode = -1;
      modeChangeStatus = "Mode changed successfully to: " + getModeNameForDisplay(currentMode);
      addDebugMessage("Mode change complete: " + getModeNameForDisplay(currentMode));
      println("RECEIVED: " + data + " - Mode change complete!");
      
      // BUFFER CORRUPTION PREVENTION: Clear any old data after mode change
      myPort.clear();
      receivingData = false;
      
      return;
    }
    
    // Route to appropriate serial event handler based on current mode
    // BUFFER CORRUPTION PREVENTION: Only process data if not changing modes
    if (!modeChanging) {
      if (currentMode == 0) {
        serialEvent_fft(data); // FFT mode
      } else if (currentMode == 1) {
        serialEvent_corr(data); // CORR mode
      } else if (currentMode == 2 || currentMode == 3) {
        serialEvent_Eyes(data); // EYE or GAME mode
      }
    } else {
      // BUFFER CORRUPTION PREVENTION: Ignore data during mode transition
      if (data.equals("FFT_START") || data.equals("CORR_START") || data.equals("PHAT_START")) {
        addDebugMessage("IGNORED: Data packet during mode transition");
        println("IGNORED: Data packet during mode transition");
      }
    }
  }
}

// Add debug message to list (keep only last N messages)
void addDebugMessage(String msg) {
  debugMessages.add(millis() + ": " + msg);
  while (debugMessages.size() > maxDebugMessages) {
    debugMessages.remove(0); // Remove oldest
  }
}

// MODE: FFT - Receive 512 FFT magnitude bins
void serialEvent_fft(String data) {
  // Check for data markers
  if (data.equals("FFT_START")) {
    receivingData = true; // Start receiving FFT data packet

    // Record timing: new frame arrived
    long currentTime = millis();
    if (lastFrameTime > 0) {
      timeBetweenFrames = (currentTime - lastFrameTime);
    }
    frameArrivalTime = currentTime;
    lastFrameTime = currentTime;
    frameCount++;
    
    modeChangeStatus = "Receiving FFT data..."; // Update status message

    return;
  }

  if (data.equals("FFT_END")) {
    receivingData = false; // End of FFT data packet

    // Record timing: frame fully received
    long receiveEndTime = millis();
    float receiveTime = receiveEndTime - frameArrivalTime;
    
    modeChangeStatus = "FFT data received correctly"; // Update status message
    
    // ANTI-FLICKER: Render FFT to buffer immediately when data arrives
    renderFFTToBuffer();
    fftBufferReady = true;
    
    newFrameAvailable = true; // Flag that we have new data to draw

    return;
  }

  if (receivingData) {
    // Parse FFT magnitude data (comma-separated values)
    String[] values = split(data, ',');

    if (values.length == 512) {
      for (int i = 0; i < 512; i++) {
        try {
          fft_data[i] = float(values[i]); // Parse magnitude values
        } catch (Exception e) {
          // Skip invalid values
        }
      }
    } else {
      println("WARNING: Expected 512 FFT values, got " + values.length);
    }
  }
}

// MODE: CORR - Receive 1024 correlation samples
void serialEvent_corr(String data) {
  // Check for data markers
  if (data.equals("CORR_START")) {
    receivingData = true; // Start receiving correlation data packet

    // Record timing: new frame arrived
    long currentTime = millis();
    if (lastFrameTime > 0) {
      timeBetweenFrames = (currentTime - lastFrameTime);
    }
    frameArrivalTime = currentTime;
    lastFrameTime = currentTime;
    frameCount++;
    
    modeChangeStatus = "Receiving CORR data..."; // Update status message

    return;
  }

  if (data.equals("CORR_END")) {
    receivingData = false; // End of correlation data packet

    // Record timing: frame fully received
    long receiveEndTime = millis();
    float receiveTime = receiveEndTime - frameArrivalTime;
    
    modeChangeStatus = "CORR data received correctly (sparse)"; // Update status message
    
    // ANTI-FLICKER: Render correlation to buffer immediately when data arrives
    renderCorrToBuffer();
    corrBufferReady = true;
    
    newFrameAvailable = true; // Flag that we have new data to draw

    return;
  }

  if (receivingData) {
    // OPTIMIZATION: Parse sparse correlation data (only 21 values around peak)
    // Format: peak_idx, peak_value, left_count, [left_values...], right_count, [right_values...]
    String[] values = split(data, ',');

    if (values.length >= 5) { // At minimum: peak_idx, peak_value, left_count, right_count, and at least one value
      try {
        // Clear correlation array (all zeros by default)
        for (int i = 0; i < 1024; i++) {
          correlation_data[i] = 0.0;
        }
        
        int idx = 0;
        
        // Parse peak index and value
        max_idx = int(values[idx++]);
        max_value = float(values[idx++]);
        correlation_data[max_idx] = max_value; // Set peak value
        
        // Parse left values
        int left_count = int(values[idx++]);
        int left_start_idx = max_idx - left_count;
        for (int i = 0; i < left_count; i++) {
          correlation_data[left_start_idx + i] = float(values[idx++]);
        }
        
        // Parse right values
        int right_count = int(values[idx++]);
        for (int i = 0; i < right_count; i++) {
          correlation_data[max_idx + 1 + i] = float(values[idx++]);
        }
        
        println("Received sparse CORR: peak at " + max_idx + " = " + nf(max_value, 0, 6) + 
                " with " + left_count + " left, " + right_count + " right values");
        
      } catch (Exception e) {
        println("ERROR parsing sparse CORR data: " + e.getMessage());
      }
    } else {
      println("WARNING: Expected sparse CORR format, got " + values.length + " values");
    }
  }
}

// MODE: EYE and GAME - Receive PHAT peak detection data
void serialEvent_Eyes(String data) {
  if (data.equals("PHAT_START")) {
    receivingData = true; // Start receiving PHAT data packet
    
    // Record timing: new frame arrived
    long currentTime = millis();
    if (lastFrameTime > 0) {
      timeBetweenFrames = (currentTime - lastFrameTime);
    }
    frameArrivalTime = currentTime;
    lastFrameTime = currentTime;
    frameCount++;
    
    modeChangeStatus = "Receiving PHAT data..."; // Update status message
    
    return;
  }

  if (data.equals("PHAT_END")) {
    receivingData = false; // End of PHAT data packet
    
    // Record timing: frame fully received
    long receiveEndTime = millis();
    float receiveTime = receiveEndTime - frameArrivalTime;
    
    modeChangeStatus = "PHAT data received correctly"; // Update status message
    newFrameAvailable = true; // Flag that we have new data to draw
    
    return;
  }

  if (receivingData) {
    // Parse magnitude and phase data (interleaved: mag0,phase0,mag1,phase1,...)
    String[] values = split(data, ',');
    // println( values[0] + "; " + values[1] + "; " + values[2] + "; " + values[3] );
    mic01_phat_peak_value = float(values[0]);
    mic01_phat_peak_idx = float(values[1]);
    mic01_phat_second_value = float(values[2]);
    mic01_phat_second_idx = float(values[3]); 
    mic01_psr = float(values[4]);
    
    mic23_phat_peak_value = float(values[5]);
    mic23_phat_peak_idx =float(values[6]);
    mic23_phat_second_value = float(values[7]);
    mic23_phat_second_idx =float(values[8]);
    mic23_psr = float(values[9]);
    
    sure_signal = "";
    //if(mic01_phat_peak_value/mic01_phat_second_value > 1.5 && mic01_phat_peak_value > 0.2) sure_signal = "1";
    //if(mic23_phat_peak_value/mic23_phat_second_value > 1.5 && mic23_phat_peak_value > 0.2) sure_signal += "2";
    if(mic01_phat_peak_value/mic01_phat_second_value > 1.5 && mic01_phat_peak_value > 0.2 && mic01_psr > 6.0f) sure_signal = "1";
    if(mic23_phat_peak_value/mic23_phat_second_value > 1.5 && mic23_phat_peak_value > 0.2 && mic23_psr > 6.0f) sure_signal += "2";    
    
    if(! sure_signal.equals("")) {
      println(String.format("INFO: mic01 %10.6f %5d, %10.6f %5d (%10.6f) %10.6f; mic23 %10.6f %5d, %10.6f %5d (%10.6f) %10.6f;  %s",
          mic01_phat_peak_value, (int)mic01_phat_peak_idx, 
          mic01_phat_second_value, (int)mic01_phat_second_idx,
          mic01_phat_peak_value/mic01_phat_second_value,
          mic01_psr,
          mic23_phat_peak_value, (int)mic23_phat_peak_idx,
          mic23_phat_second_value, (int)mic23_phat_second_idx,
          mic23_phat_peak_value/mic23_phat_second_value,
          mic23_psr,
          sure_signal)); 
    }
  }
}

// Helper function to get mode name for display
String getModeNameForDisplay(int mode) {
  if (mode == 0) return "FFT";
  if (mode == 1) return "CORR";
  if (mode == 2) return "EYE";
  if (mode == 3) return "GAME";
  return "UNKNOWN";
}
  
void draw() {
  long drawStartTime = millis();
  
  background(20, 25, 35);
  
  // Debug info - TIMING DIAGNOSTICS
  fill(255, 255, 0);
  textSize(14);
  textAlign(LEFT);
  text("Mode: " + getModeNameForDisplay(currentMode) + " | Receiving: " + receivingData + " | Frame: " + frameCount, 20, 20);

  fill(255, 100, 100);
  text("Time between frames: " + nf(timeBetweenFrames, 0, 1) + " ms", 20, 40);

  fill(100, 255, 100);
  text("Time to draw frame: " + nf(timeToDrawFrame, 0, 1) + " ms", 20, 60);
  
  // MODE SWITCHING: Display mode change status
  if (modeChanging || modeChangeStatus.length() > 0) {
    if (modeChanging) {
      fill(255, 200, 0); // Yellow for in-progress
    } else {
      fill(100, 255, 100); // Green for complete
    }
    textSize(16);
    text("Status: " + modeChangeStatus, 20, 90);
  }
  
  // DEBUG: Display debug messages from Teensy
  fill(150, 150, 255);
  textSize(12);
  textAlign(LEFT);
  text("Debug Messages (last " + maxDebugMessages + "):", 20, 120);
  for (int i = 0; i < debugMessages.size(); i++) {
    text(debugMessages.get(i), 20, 140 + i * 15);
  }

  // Draw appropriate visualization based on current mode
  if (currentMode == 0) {
    drawFFTMode(); // MODE: FFT
  } else if (currentMode == 1) {
    drawCorrMode(); // MODE: CORR
  } else if (currentMode == 2) {
    drawEyesMode(); // MODE: EYE
  } else if (currentMode == 3) {
    drawGameMode(); // MODE: GAME (same as EYE for now)
  }
  
  // Draw mode selection instructions
  fill(255, 255, 0);
  textSize(18);
  textAlign(CENTER);
  text("Press '1' for FFT | '2' for EYE | '3' for CORR | '4' for GAME", width/2, height - 20);
  
  // Calculate and store draw time
  long drawEndTime = millis();
  timeToDrawFrame = drawEndTime - drawStartTime;
}

// ANTI-FLICKER: Render FFT to off-screen buffer
void renderFFTToBuffer() {
  fftBuffer.beginDraw();
  fftBuffer.clear();
  
  int fftTop = 350; // Start FFT graph lower to make room for waterfall
  int fftBottom = fftTop + FFT_GRAPH_HEIGHT;
  int graphWidth = width - 100;
  
  // Find max for scaling
  float maxMag = 0;
  for (int i = 0; i < 512; i++) {
    if (fft_data[i] > maxMag) maxMag = fft_data[i];
  }
  
  // Draw axes
  fftBuffer.stroke(255);
  fftBuffer.strokeWeight(2);
  fftBuffer.line(50, fftBottom, width - 50, fftBottom); // X-axis
  fftBuffer.line(50, fftTop, 50, fftBottom); // Y-axis
  
  // X-axis labels (frequency) - 0 to 22050 Hz
  fftBuffer.fill(255);
  fftBuffer.textAlign(CENTER, TOP);
  fftBuffer.textSize(14);
  
  fftBuffer.text("0 Hz", 50, fftBottom + 5);
  fftBuffer.text("5512 Hz", 50 + graphWidth/4, fftBottom + 5);
  fftBuffer.text("11025 Hz", 50 + graphWidth/2, fftBottom + 5);
  fftBuffer.text("16537 Hz", 50 + 3*graphWidth/4, fftBottom + 5);
  fftBuffer.text("22050 Hz", width - 50, fftBottom + 5);
  
  // Y-axis labels (magnitude)
  fftBuffer.textAlign(RIGHT, CENTER);
  fftBuffer.textSize(12);
  for (int i = 0; i <= 5; i++) {
    float yPos = fftBottom - i * FFT_GRAPH_HEIGHT / 5.0;
    float val = maxMag * i / 5.0;
    
    if (maxMag < 0.01) {
      fftBuffer.text(nf(val, 0, 6), 45, yPos);
    } else if (maxMag < 1.0) {
      fftBuffer.text(nf(val, 0, 4), 45, yPos);
    } else {
      fftBuffer.text(nf(val, 0, 2), 45, yPos);
    }
    
    // Grid lines
    fftBuffer.stroke(80, 80, 100);
    fftBuffer.strokeWeight(1);
    fftBuffer.line(50, yPos, width - 50, yPos);
  }
  
  // Draw FFT line graph
  fftBuffer.stroke(100, 200, 255);
  fftBuffer.strokeWeight(2);
  fftBuffer.noFill();
  fftBuffer.beginShape();
  
  for (int i = 0; i < 512; i++) {
    float x = map(i, 0, 511, 50, width - 50);
    float y = map(fft_data[i], 0, maxMag, fftBottom, fftTop);
    fftBuffer.vertex(x, y);
  }
  
  fftBuffer.endShape();
  
  // Display info
  fftBuffer.fill(255);
  fftBuffer.textAlign(LEFT, TOP);
  fftBuffer.textSize(12);
  fftBuffer.text("FFT Size: 1024", 60, fftTop + 10);
  fftBuffer.text("Freq Resolution: 43.07 Hz/bin", 60, fftTop + 30);
  fftBuffer.text("Max Magnitude: " + nf(maxMag, 0, 4), 60, fftTop + 50);
  
  fftBuffer.endDraw();
  
  // Update waterfall
  updateWaterfallFFT();
}

// Update waterfall spectrogram for FFT mode
void updateWaterfallFFT() {
  // Find max value for color scaling
  float maxVal = 0;
  for (int i = 0; i < 512; i++) {
    if (fft_data[i] > maxVal) {
      maxVal = fft_data[i];
    }
  }
  if (maxVal == 0) maxVal = 1; // Prevent division by zero
  
  // Scroll waterfall down by copying pixels
  waterfallBuffer.beginDraw();
  waterfallBuffer.copy(0, 0, 512, waterfallRows - 1, 0, 1, 512, waterfallRows - 1);
  
  // Add new row at top
  for (int i = 0; i < 512; i++) {
    // Normalize to 0-1 range
    float normalized = fft_data[i] / maxVal;
    
    // Apply sqrt scaling for better visualization
    normalized = sqrt(normalized);
    
    // Convert to color
    int colorValue = getColorForFFTValue(normalized);
    
    waterfallBuffer.set(i, 0, colorValue);
  }
  
  waterfallBuffer.endDraw();
}

// Color mapping for FFT waterfall
int getColorForFFTValue(float normalized) {
  normalized = constrain(normalized, 0, 1);
  
  int r, g, b;
  
  if (normalized < 0.2) {
    // Black to blue
    float t = normalized / 0.2;
    r = 0;
    g = 0;
    b = int(t * 255);
  } else if (normalized < 0.4) {
    // Blue to cyan
    float t = (normalized - 0.2) / 0.2;
    r = 0;
    g = int(t * 255);
    b = 255;
  } else if (normalized < 0.6) {
    // Cyan to green
    float t = (normalized - 0.4) / 0.2;
    r = 0;
    g = 255;
    b = int((1 - t) * 255);
  } else if (normalized < 0.8) {
    // Green to yellow
    float t = (normalized - 0.6) / 0.2;
    r = int(t * 255);
    g = 255;
    b = 0;
  } else {
    // Yellow to red
    float t = (normalized - 0.8) / 0.2;
    r = 255;
    g = int((1 - t) * 255);
    b = 0;
  }
  
  return color(r, g, b);
}

// ANTI-FLICKER: Render correlation to off-screen buffer
void renderCorrToBuffer() {
  corrBuffer.beginDraw();
  corrBuffer.clear();
  
  // Draw correlation as line graph
  int graphBottom = height - 200;
  int graphHeight = 400;
  
  // Y-axis scale is fixed from 0 to 1 (correlation values are normalized)
  float minScale = 0.0;
  float maxScale = 1.0;
  
  // Draw line graph
  corrBuffer.stroke(255, 150, 100);
  corrBuffer.strokeWeight(2);
  corrBuffer.noFill();
  corrBuffer.beginShape();
  for (int i = 0; i < 1024; i++) {
    float x = map(i, 0, 1023, 50, width - 50);
    // Map correlation data from 0 to 1 scale
    float y = map(correlation_data[i], minScale, maxScale, graphBottom, graphBottom - graphHeight);
    y = constrain(y, graphBottom - graphHeight, graphBottom); // Clamp to graph bounds
    corrBuffer.vertex(x, y);
  }
  corrBuffer.endShape();
  
  // Draw vertical line at peak
  if (max_value > 0) {
    float peakX = map(max_idx, 0, 1023, 50, width - 50);
    float peakY = map(max_value, minScale, maxScale, graphBottom, graphBottom - graphHeight);
    
    // Vertical line from bottom to peak
    corrBuffer.stroke(255, 255, 0); // Yellow for peak marker
    corrBuffer.strokeWeight(2);
    corrBuffer.line(peakX, graphBottom, peakX, peakY);
    
    // Circle at peak
    corrBuffer.fill(255, 255, 0);
    corrBuffer.noStroke();
    corrBuffer.ellipse(peakX, peakY, 10, 10);
    
    // Peak label above the peak
    corrBuffer.fill(255, 255, 0);
    corrBuffer.textSize(16);
    corrBuffer.textAlign(CENTER);
    corrBuffer.text("Peak: " + nf(max_value, 0, 4), peakX, peakY - 15);
    corrBuffer.text("Index: " + max_idx, peakX, peakY - 35);
  }
  
  // Draw axes
  corrBuffer.stroke(255);
  corrBuffer.strokeWeight(1);
  corrBuffer.line(50, graphBottom, width - 50, graphBottom); // X-axis
  corrBuffer.line(50, graphBottom - graphHeight, 50, graphBottom); // Y-axis
  
  // Draw Y-axis grid lines and labels
  corrBuffer.stroke(80, 80, 100);
  corrBuffer.strokeWeight(1);
  corrBuffer.fill(180);
  corrBuffer.textSize(12);
  corrBuffer.textAlign(RIGHT);
  for (int i = 0; i <= 5; i++) {
    float yValue = i * 0.2; // 0.0, 0.2, 0.4, 0.6, 0.8, 1.0
    float yPos = map(yValue, minScale, maxScale, graphBottom, graphBottom - graphHeight);
    
    // Grid line
    corrBuffer.line(50, yPos, width - 50, yPos);
    
    // Y-axis label
    corrBuffer.text(nf(yValue, 0, 1), 45, yPos + 5);
  }
  
  // X-axis labels (0 to 1023)
  corrBuffer.fill(180);
  corrBuffer.textSize(14);
  corrBuffer.textAlign(LEFT);
  corrBuffer.text("0", 50, graphBottom + 20);
  corrBuffer.textAlign(CENTER);
  corrBuffer.text("256", 50 + (width - 100) * 0.25, graphBottom + 20);
  corrBuffer.text("512", 50 + (width - 100) * 0.5, graphBottom + 20);
  corrBuffer.text("768", 50 + (width - 100) * 0.75, graphBottom + 20);
  corrBuffer.textAlign(RIGHT);
  corrBuffer.text("1023", width - 50, graphBottom + 20);
  corrBuffer.textAlign(CENTER);
  
  // Overall peak info
  corrBuffer.fill(255);
  corrBuffer.textSize(14);
  corrBuffer.text("Peak: " + nf(max_value, 0, 6) + " at index " + max_idx, width/2, graphBottom + 40);
  
  corrBuffer.endDraw();
}

// MODE: FFT - Simple FFT magnitude display
void drawFFTMode() {
  fill(255);
  textSize(24);
  textAlign(CENTER);
  text("FFT MODE - Frequency Spectrum", width/2, 140);
  
  // ANTI-FLICKER: Draw from buffer if available
  if (fftBufferReady) {
    image(fftBuffer, 0, 0);
    
    // Draw waterfall spectrogram
    int waterfallTop = 680;
    image(waterfallBuffer, 50, waterfallTop, width - 100, WATERFALL_HEIGHT);
    
    // Draw frame around waterfall
    noFill();
    stroke(255);
    strokeWeight(2);
    rect(50, waterfallTop, width - 100, WATERFALL_HEIGHT);
    
    // X-axis labels for waterfall (same as FFT)
    fill(255);
    textAlign(CENTER, TOP);
    textSize(14);
    int plotWidth = width - 100;
    int labelY = waterfallTop + WATERFALL_HEIGHT + 5;
    
    text("0 Hz", 50, labelY);
    text("5512 Hz", 50 + plotWidth/4, labelY);
    text("11025 Hz", 50 + plotWidth/2, labelY);
    text("16537 Hz", 50 + 3*plotWidth/4, labelY);
    text("22050 Hz", width - 50, labelY);
    
    // Waterfall title
    textAlign(LEFT, TOP);
    textSize(14);
    fill(255);
    text("Waterfall Spectrogram", 60, waterfallTop - 25);
    
    // Time axis label
    textAlign(CENTER, CENTER);
    pushMatrix();
    translate(20, waterfallTop + WATERFALL_HEIGHT/2);
    rotate(-HALF_PI);
    text("Time (newest at top)", 0, 0);
    popMatrix();
  }
}

// MODE: CORR - Simple correlation display
void drawCorrMode() {
  fill(255);
  textSize(24);
  textAlign(CENTER);
  text("CORR MODE - Correlation Result", width/2, 140);
  
  // ANTI-FLICKER: Draw from buffer if available
  if (corrBufferReady) {
    image(corrBuffer, 0, 0);
    
    // Update stored max values (draw over the buffer)
    if(max_value > 0.25) {
      last_max_value = max_value;
      last_max_idx = max_idx;
    }
    
    // Display last significant peak (draw over the buffer)
    fill(100, 255, 100);
    textAlign(LEFT);
    textSize(14);
    text("Last peak idx: " + nf(last_max_idx, 0, 1), 20, 300);
    text("Last peak value: " + nf(last_max_value, 0, 4), 20, 320);
  }
}

// MODE: EYE - Eyes tracking display
void drawEyesMode() {
  fill(255);
  textSize(24);
  textAlign(CENTER);
  text("EYE MODE - Eye Tracking", width/2, 100);
  
  noStroke();  // Eyes should have no stroke
  
  int leftX = 92;
  int rightX = 1113;
  int upY = 130;
  int downY = 830;
  
  if(sure_signal.equals("1") || sure_signal.equals("2") || sure_signal.equals("12")) {
    e1.update(3*(int)mic01_phat_peak_idx, 3*(int)mic23_phat_peak_idx);
    e2.update(3*(int)mic01_phat_peak_idx, 3*(int)mic23_phat_peak_idx);
  }
 
  e1.display();
  e2.display();
  
  // Display eye position info
  fill(100, 255, 100);
  textSize(14);
  textAlign(LEFT);
  text("eyeX: " + nf(e1.eyex, 0, 1), 20, 120);
  text("eyeY: " + nf(e1.eyey, 0, 1), 20, 140);
}

// MODE: GAME - Game display (same as EYE for now)
void drawGameMode() {
  fill(255);
  textSize(32);
  textAlign(CENTER);
  text("MOSQUITO HUNTER - Clap to Kill!", width/2, 60);
  
  // Display score
  fill(255, 255, 0);
  textSize(48);
  text("Score: " + gameScore, width/2, 120);
  
  // Display instructions
  fill(200);
  textSize(16);
  text("Clap near the mosquito to kill it! (within " + killDistance + " pixels)", width/2, 160);
  
  // GAME MODE: Update and display mosquito
  mosquito.update();
  mosquito.display();
  
  // GAME MODE: Check for clap and handle hit detection
  if(sure_signal.equals("1") || sure_signal.equals("2") || sure_signal.equals("12")) {
    // Calculate clap position from microphone data
    // mic01_phat_peak_idx and mic23_phat_peak_idx range from approximately -30 to +30
    // Scale to cover the playable area where mosquitoes spawn (150 to width-150, 150 to height-150)
    float clapX = map(mic01_phat_peak_idx, -30, 30, 150, width - 150);
    float clapY = map(mic23_phat_peak_idx, -30, 30, 150, height - 150);
    
    // Constrain to screen bounds
    clapX = constrain(clapX, 0, width);
    clapY = constrain(clapY, 0, height);
    
    // Store clap position and time for visualization
    lastClapX = int(clapX);
    lastClapY = int(clapY);
    lastClapTime = millis();
    
    // Check if mosquito was hit
    if (mosquito.checkHit(clapX, clapY, killDistance)) {
      mosquito.kill();
      gameScore += 10; // Award points
      
      // Add success message
      String msg = millis() + ": HIT! +10 points";
      gameMessages.add(msg);
      if (gameMessages.size() > 5) gameMessages.remove(0);
      
      println("MOSQUITO KILLED! Score: " + gameScore);
      
      // Respawn mosquito after a short delay
      delay(500); // Brief pause to show kill
      mosquito.respawn();
    } else {
      // Add miss message
      float distance = dist(mosquito.x, mosquito.y, clapX, clapY);
      String msg = millis() + ": Miss by " + nf(distance, 0, 0) + " pixels";
      gameMessages.add(msg);
      if (gameMessages.size() > 5) gameMessages.remove(0);
    }
  }
  
  // GAME MODE: Draw clap position indicator (fades over time)
  if (lastClapTime > 0 && (millis() - lastClapTime) < 1000) {
    float alpha = map(millis() - lastClapTime, 0, 1000, 255, 0);
    
    // Draw crosshair at clap position
    stroke(255, 0, 0, alpha);
    strokeWeight(3);
    noFill();
    
    // Crosshair
    line(lastClapX - 20, lastClapY, lastClapX + 20, lastClapY);
    line(lastClapX, lastClapY - 20, lastClapX, lastClapY + 20);
    
    // Circle showing kill radius
    stroke(255, 255, 0, alpha * 0.5);
    strokeWeight(2);
    ellipse(lastClapX, lastClapY, killDistance * 2, killDistance * 2);
  }
  
  // GAME MODE: Draw game messages
  fill(100, 255, 100);
  textSize(14);
  textAlign(LEFT);
  text("Game Log:", 20, 200);
  for (int i = 0; i < gameMessages.size(); i++) {
    text(gameMessages.get(i), 20, 220 + i * 20);
  }
  
  // Display current clap detection info
  fill(150, 150, 255);
  textSize(12);
  text("Clap Detection (range: -30 to +30):", 20, 350);
  text("mic01_idx: " + nf(mic01_phat_peak_idx, 0, 1) + " → X: " + nf(lastClapX, 0, 0) + ", PSR: " + nf(mic01_psr, 0, 2), 20, 370);
  text("mic23_idx: " + nf(mic23_phat_peak_idx, 0, 1) + " → Y: " + nf(lastClapY, 0, 0) + ", PSR: " + nf(mic23_psr, 0, 2), 20, 390);
  text("Sure signal: " + sure_signal, 20, 410);
  
  // Draw mosquito position for debugging
  if (mosquito.alive) {
    fill(255, 100, 100);
    text("Mosquito at: (" + nf(mosquito.x, 0, 0) + ", " + nf(mosquito.y, 0, 0) + ")", 20, 440);
  }
  
  // Draw playable area boundary for reference
  noFill();
  stroke(100, 100, 100, 100);
  strokeWeight(1);
  rect(150, 150, width - 300, height - 300);
}

void shiftIntoNewBuffer(float[] src, float[] dst, int MAX_LAG) {
  int N = src.length;
  int k = 0;

  // -------------------------------
  // 1) Negative lags (tail)
  //    src[-MAX_LAG+1:]
  // -------------------------------
  //for (int i = N - MAX_LAG + 1; i < N; i++) {
  //  dst[k++] = src[i];
  //}

  //// -------------------------------
  //// 2) Zero + positive lags
  ////    src[:MAX_LAG+1]
  //// -------------------------------
  //for (int i = 0; i <= MAX_LAG; i++) {
  //  dst[k++] = src[i];
  //}
  
  for (int i = 0; i < N; i++) {
    dst[i] = src[i];
  }
}

void keyPressed() {
  if (key == 's' || key == 'S') {
    saveFrame("fft_snapshot_####.png");
    println("Screenshot saved!");
  }

  // MODE SWITCHING: Handle key presses for mode changes
  if (key == '1') {
    println("KEY PRESSED: Requesting FFT mode");
    requestModeChange(0); // Request FFT mode
  }
  else if (key == '2') {
    println("KEY PRESSED: Requesting EYE mode");
    requestModeChange(2); // Request EYE mode
  }
  else if (key == '3') {
    println("KEY PRESSED: Requesting CORR mode");
    requestModeChange(1); // Request CORR mode
  }
  else if (key == '4') {
    println("KEY PRESSED: Requesting GAME mode");
    requestModeChange(3); // Request GAME mode
  }
}
