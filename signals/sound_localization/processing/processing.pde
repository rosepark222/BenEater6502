import processing.serial.*; //<>//
import processing.sound.*;


final int MODE_FFT = 0;
final int MODE_CORR_01 = 1;
final int MODE_EYE = 2;
final int MODE_GAME = 3;
final int MODE_CORR_23 = 4;
final int MODE_CORR_02 = 5;
final int MODE_CORR_03 = 6;
final int MODE_3D_LOCATION = 7;

final int FFT_SIZE = 1024;
final int FFT_BINS = 512;

final int FRAME_WINDOW = 43; // 43 is one second

PVector[] mics = new PVector[4];
PVector soundPos = new PVector(0, 0, 0);

  // X-axis: RED (255, 80, 80)   // Y-axis: GREEN (80, 255, 80)   // Z-axis: BLUE (80, 80, 255)

float rotX = -0.349;     // No tilt
float rotY = 0.349;  // Rotate 20° to the right (makes Y point left)
float zoom = 300;
float sceneScale = 10.0; // Scale factor for 3D objects (adjust this value)
// Mouse interaction variables
float prevMouseX = 0;
float prevMouseY = 0;
boolean isDragging = false;

SoundFile hitSound;
SoundFile dingSound;

Serial myPort;
boolean newFrameAvailable = false; 
PrintWriter output;
boolean recording = false;

// MODE SWITCHING: Current mode and mode transition state
int currentMode = 2; // 0=FFT, 1=CORR, 2=EYE, 3=GAME
int requestedMode = -1; // -1 means no mode change requested
boolean waitingForAck = false; // Waiting for acknowledgment from Teensy
boolean modeChanging = false; // In the process of changing modes
String modeChangeStatus = ""; // Status message to display
ArrayList<String> debugMessages = new ArrayList<String>(); // Store debug messages
int maxDebugMessages = 1; // 10; // Keep last 10 messages

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
  float baseSize; // Base size before scaling
  boolean alive;
  float wingAngle;
  float wingSpeed;
  float hoverOffsetX, hoverOffsetY;
  float hoverAngle;
  
  int leftright_margin;
  int topbottom_margin;
  
  Mosquito() {
    // move the marge before respawn so that it will be applied
    leftright_margin = 150;
    topbottom_margin = 250; // prevent duck from respawning too high or too low
    baseSize = 30; // Default base size
    respawn();
    wingAngle = 0;
    wingSpeed = 0.3;
    hoverAngle = random(TWO_PI);

  }
  
  void respawn() {
    // Spawn in random location (with margins)
    x = random(leftright_margin, width - leftright_margin);
    //y = random(150, height - 150);
    y = random(topbottom_margin, height - topbottom_margin); // make y direction smaller for m to show up
    size = baseSize * mosquitoScale; // Apply scaling factor
    alive = true;
  }
  
  void update() {
    if (!alive) return;
    
    // Animate wings
    wingAngle += wingSpeed;
    
    // Hovering motion
    hoverAngle += 0.05;
    hoverOffsetX = cos(hoverAngle) * 10 * mosquitoScale; // Scale hover motion
    hoverOffsetY = sin(hoverAngle * 1.3) * 8 * mosquitoScale;
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
  // The killDistance check now considers the mosquito's actual scaled size
  boolean checkHit(float clapX, float clapY, float threshold) {
    if (!alive) return false;
    
    float distance = dist(x, y, clapX, clapY);
    // Subtract half the mosquito size from the threshold to account for mosquito body
    // This makes the hitbox match the visual size of the mosquito
    float effectiveThreshold = threshold + (size * 0.5);
    return distance < effectiveThreshold;
  }
  
  void kill() {
    alive = false;
  }
}

// GAME MODE: Game state variables
Mosquito mosquito;
int gameScore = 0;
int killDistance = 100; // Kill distance stays constant (not scaled)
float mosquitoScale = 4.0; // MOSQUITO SIZE SCALE: Change this to make mosquito larger/smaller (e.g., 5.0 = 5x larger)
ArrayList<String> gameMessages = new ArrayList<String>();
int lastClapX = -1, lastClapY = -1;
long lastClapTime = 0;
long killAnimationTime = 0; // Track when mosquito was killed for animation
boolean showKillAnimation = false;
// Timer variables
long gameStartTime = 0;
int gameDuration = 60000; // 60 seconds in milliseconds
boolean gameActive = false;
boolean showRestartDialog = false;

// FFT data storage
float[] fft_data = new float[FFT_BINS]; // MODE: FFT - 512 magnitude bins
float[] correlation_data = new float[FFT_SIZE]; // MODE: CORR - 1024 correlation samples
float[] corr_roated = new float[FFT_SIZE];
//float[] mic1_phase = new float[FFT_BINS];
//float[] mic2_magnitude = new float[FFT_BINS];
//float[] mic2_phase = new float[FFT_BINS];

// ANTI-FLICKER: PGraphics buffers for smooth rendering
PGraphics fftBuffer;
PGraphics corrBuffer;
PGraphics waterfallBuffer; // Waterfall for FFT mode
PGraphics corrWaterfallBuffer; // Waterfall for CORR mode
boolean fftBufferReady = false;
boolean corrBufferReady = false;

// Waterfall parameters for FFT mode
final int FFT_GRAPH_HEIGHT = 300;
final int WATERFALL_HEIGHT = 300;
int waterfallRows;

// Waterfall parameters for CORR mode
final int CORR_GRAPH_HEIGHT = 300;
final int CORR_WATERFALL_HEIGHT = 300;
int corrWaterfallRows;

//int displayBins = 20;  // Only display first 24 bins (0-1000 Hz)
int displayBins = FFT_SIZE;  // Only display first 24 bins (0-1000 Hz)

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
int signalDetectedByTDOAmic01 = 0;
int prevSureFrameCount = 0;

// Receiving state
boolean receivingData = false;
String currentMic = "";

float max_value = 0;
int  max_idx = 0;
float draw_vertical_line_threshold = 0.2;

float mic01_phat_peak_value = -1;
float mic01_phat_peak_idx = -10;
float mic01_phat_second_value = -1;
float mic01_phat_second_idx = -10;
float mic01_psr = 0;

float mic02_phat_peak_value = -1;
float mic02_phat_peak_idx = -10;
float mic02_phat_second_value = -1;
float mic02_phat_second_idx = -10;
float mic02_psr = 0;

float mic03_phat_peak_value = -1;
float mic03_phat_peak_idx = -10;
float mic03_phat_second_value = -1;
float mic03_phat_second_idx = -10;
float mic03_psr = 0;


float mic23_phat_peak_value = -1;
float mic23_phat_peak_idx = -10;
float mic23_phat_second_value = -1;
float mic23_phat_second_idx = -10;
float mic23_psr = 0;

float last_max_value = 0;
int  last_max_idx = 0;

void drawAxes(float len) {
  strokeWeight(2);

  stroke(255, 80, 80);
  line(0, 0, 0, len, 0, 0);

  stroke(80, 255, 80);
  line(0, 0, 0, 0, len, 0);

  stroke(80, 80, 255);
  line(0, 0, 0, 0, 0, len);
}

void drawMics(PVector[] mics) {
  noStroke();
  fill(80, 160, 255);
  for (PVector m : mics) {
    pushMatrix();
    translate(m.x, m.y, m.z);
    sphere(2.5);
    popMatrix();
  }
}

void drawSound(PVector p) {
  if (p == null) return;
  noStroke();
  fill(255, 80, 80);
  pushMatrix();
  translate(p.x, p.y, p.z);
  sphere(3.5);
  popMatrix();
}

void drawConnections(PVector[] mics, PVector p) {
  if (p == null) return;
  stroke(150, 150, 150, 120);
  strokeWeight(1);
  for (PVector m : mics) {
    line(m.x, m.y, m.z, p.x, p.y, p.z);
  }
}
 
void drawMicAndSoundScene(
  PVector[] mics,
  PVector soundPos,
  float rotX, float rotY, float zoom
) {
  
  float xyz_scale = 1000;
  scene3DBuffer.beginDraw();
  //scene3DBuffer.background(20); The key change is replacing scene3DBuffer.background(20) with scene3DBuffer.clear(). This makes the buffer transparent, so when you draw it on top of the main screen (which already has the text), the text will show through.
  scene3DBuffer.clear(); // The key change is replacing scene3DBuffer.background(20) with scene3DBuffer.clear(). This makes the buffer transparent, so when you draw it on top of the main screen (which already has the text), the text will show through.
  scene3DBuffer.pushMatrix();
  scene3DBuffer.translate(width/2, height/2);
  


scene3DBuffer.rotateX(HALF_PI); // Make Z vertical
scene3DBuffer.rotateX(rotX);    // Tilt (none in this case)
scene3DBuffer.rotateZ(rotY);    // Rotate around vertical Z-axis

  scene3DBuffer.lights();

 
  // X-axis: RED (255, 80, 80)   // Y-axis: GREEN (80, 255, 80)   // Z-axis: BLUE (80, 80, 255)
  scene3DBuffer.stroke(255, 80, 80);
  scene3DBuffer.line(0, 0, 0, 50 * sceneScale, 0, 0);
  scene3DBuffer.stroke(80, 255, 80);
  scene3DBuffer.line(0, 0, 0, 0, 50 * sceneScale, 0);
  scene3DBuffer.stroke(80, 80, 255);
  scene3DBuffer.line(0, 0, 0, 0, 0, 50 * sceneScale);
  
  // Draw mics - scaled
  scene3DBuffer.noStroke();
  
  color[] micColors = {
    color(255, 0, 255),   // Mic 0: Red
    color(80, 255, 80),   // Mic 1: Green
    color(80, 80, 255),   // Mic 2: Blue
    color(255, 255, 80)   // Mic 3: Yellow
  };
  for (int i = 0; i < mics.length; i++) {
    scene3DBuffer.fill(micColors[i]);
    scene3DBuffer.pushMatrix();
    scene3DBuffer.translate(xyz_scale*mics[i].x, xyz_scale*mics[i].y, xyz_scale*mics[i].z);
    scene3DBuffer.sphere(2.5 * sceneScale/2);
    scene3DBuffer.popMatrix();
  }
  
  // Draw sound position - scaled
  if (soundPos != null) {
    scene3DBuffer.noStroke();
    scene3DBuffer.fill(255, 80, 80);
    scene3DBuffer.pushMatrix();
    scene3DBuffer.translate(xyz_scale*soundPos.x, xyz_scale*soundPos.y, xyz_scale*soundPos.z);
    scene3DBuffer.sphere(3.5 * sceneScale/2);
    scene3DBuffer.popMatrix();
    
    // Draw connections - scaled
    scene3DBuffer.stroke(150, 150, 150, 120);
    scene3DBuffer.strokeWeight(1);
    for (PVector m : mics) {
      scene3DBuffer.line(xyz_scale*m.x, xyz_scale*m.y, xyz_scale*m.z, xyz_scale*soundPos.x, xyz_scale*soundPos.y, xyz_scale*soundPos.z);
    }
  }

  scene3DBuffer.popMatrix();
  scene3DBuffer.endDraw();
  
  scene3DBufferReady = true;
}

boolean locateSound3DFromGCC(
  PVector mic0, PVector mic1,
  PVector mic2, PVector mic3,
  int peak01, int peak02, int peak03,
  PVector outPos
) {
  final float fs = 44100.0f;
  final float c  = 343.0f;
  final int   N  = 1024;

  /*--------------------------------------------------
    Peak index → signed sample delay
  --------------------------------------------------*/
  //float dn01 = (peak01 <= 512) ? peak01 : peak01 - N;
  //float dn02 = (peak02 <= 512) ? peak02 : peak02 - N;
  //float dn03 = (peak03 <= 512) ? peak03 : peak03 - N;

  float d1 = c * (peak01 / fs);
  float d2 = c * (peak02 / fs);
  float d3 = c * (peak03 / fs);

  /*--------------------------------------------------
    Geometry deltas (relative to mic0)
  --------------------------------------------------*/
  float dx10 = mic1.x - mic0.x;

  float dx20 = mic2.x - mic0.x;
  float dy20 = mic2.y - mic0.y;
  float dz20 = mic2.z - mic0.z;

  float dx30 = mic3.x - mic0.x;
  float dy30 = mic3.y - mic0.y;
  float dz30 = mic3.z - mic0.z;

  /*--------------------------------------------------
    x = ax*r0 + bx   (from mic1)
  --------------------------------------------------*/
  if (abs(dx10) < 1e-6f) return false;

  float ax = -(2.0f * d1) / (2.0f * dx10);
  float bx = -((d1*d1) + (mic1.x*mic1.x - mic0.x*mic0.x))
             / (2.0f * dx10);

  /*--------------------------------------------------
    Linear equations for y and z
  --------------------------------------------------*/
  float A1 = 2.0f * dy20;
  float B1 = 2.0f * dz20;
  float C1r = 2.0f * d2 + 2.0f * dx20 * ax;
  float C1c = d2*d2
            + (mic2.x*mic2.x + mic2.y*mic2.y + mic2.z*mic2.z)
            - (mic0.x*mic0.x + mic0.y*mic0.y + mic0.z*mic0.z)
            + 2.0f * dx20 * bx;

  float A2 = 2.0f * dy30;
  float B2 = 2.0f * dz30;
  float C2r = 2.0f * d3 + 2.0f * dx30 * ax;
  float C2c = d3*d3
            + (mic3.x*mic3.x + mic3.y*mic3.y + mic3.z*mic3.z)
            - (mic0.x*mic0.x + mic0.y*mic0.y + mic0.z*mic0.z)
            + 2.0f * dx30 * bx;

  /*--------------------------------------------------
    Solve 2×2 → y = ay*r0 + by , z = az*r0 + bz
  --------------------------------------------------*/
  float det = A1*B2 - A2*B1;
  if (abs(det) < 1e-6f) return false;

  float ay = ( C1r*B2 - C2r*B1 ) / det;
  float by = ( C1c*B2 - C2c*B1 ) / det;

  float az = ( A1*C2r - A2*C1r ) / det;
  float bz = ( A1*C2c - A2*C1c ) / det;

  /*--------------------------------------------------
    Quadratic constraint
  --------------------------------------------------*/
  float Ax = ax;
  float Bx = bx - mic0.x;

  float Ay = ay;
  float By = by - mic0.y;

  float Az = az;
  float Bz = bz - mic0.z;

  float qa = Ax*Ax + Ay*Ay + Az*Az - 1.0f;
  float qb = 2.0f*(Ax*Bx + Ay*By + Az*Bz);
  float qc = Bx*Bx + By*By + Bz*Bz;

  float disc = qb*qb - 4.0f*qa*qc;
  if (disc < 0.0f) return false;

  float r0 = (-qb + sqrt(disc)) / (2.0f * qa);
  if (r0 <= 0.0f)
    r0 = (-qb - sqrt(disc)) / (2.0f * qa);
  if (r0 <= 0.0f) return false;

  /*--------------------------------------------------
    Recover position
  --------------------------------------------------*/
  outPos.set(
    ax*r0 + bx,
    ay*r0 + by,
    az*r0 + bz
  );

  return true;
}
PGraphics scene3DBuffer; // 3D scene rendering
boolean scene3DBufferReady = false;


class HighScore {
  String name;
  int score;
  
  HighScore(String name, int score) {
    this.name = name;
    this.score = score;
  }
}

ArrayList<HighScore> highScores = new ArrayList<HighScore>();
String playerName = "";
boolean isEnteringName = false;
boolean isNewHighScore = false;
String highScoreFilename = "highscores.txt";

void loadHighScores() {
  highScores.clear();
  try {
    String[] lines = loadStrings(highScoreFilename);
    if (lines != null) {
      for (String line : lines) {
        String[] parts = split(line, ',');
        if (parts.length == 2) {
          String name = parts[0];
          int score = int(parts[1]);
          highScores.add(new HighScore(name, score));
        }
      }
    }
  } catch (Exception e) {
    println("No high scores file found, starting fresh.");
  }
  
  // Sort by score (highest first)
  sortHighScores();
  
  println("Loaded " + highScores.size() + " high scores");
}

void saveHighScores() {
  String[] lines = new String[highScores.size()];
  for (int i = 0; i < highScores.size(); i++) {
    lines[i] = highScores.get(i).name + "," + highScores.get(i).score;
  }
  saveStrings(highScoreFilename, lines);
  println("High scores saved!");
}

void sortHighScores() {
  // Simple bubble sort (good enough for 10 items)
  for (int i = 0; i < highScores.size() - 1; i++) {
    for (int j = 0; j < highScores.size() - i - 1; j++) {
      if (highScores.get(j).score < highScores.get(j + 1).score) {
        HighScore temp = highScores.get(j);
        highScores.set(j, highScores.get(j + 1));
        highScores.set(j + 1, temp);
      }
    }
  }
}

boolean isTopTenScore(int score) {
  if (highScores.size() < 10) return true;
  return score > highScores.get(9).score;
}

void addHighScore(String name, int score) {
  highScores.add(new HighScore(name, score));
  sortHighScores();
  
  // Keep only top 10
  while (highScores.size() > 10) {
    highScores.remove(highScores.size() - 1);
  }
  
  saveHighScores();
}

void setup() {
  // size(1400, 1000); //RuntimeException: createGraphics() with P3D or OPENGL requires size() to use P2D or P3D
  size(1400, 1000, P3D);
  surface.setLocation(500, 5);
  smooth();

  loadHighScores();

    // mic2 at green
    //mics[0] = new PVector(-0.15, 0, 0);
    //mics[1] = new PVector( 0.15, 0, 0);
    //// mics[2] = new PVector(  0,-0.10, 0.09);
    //mics[2] = new PVector(  0,-0.17, 0.0);
    //mics[3] = new PVector(  0, 0.065,-0.10);
    
    // mic2 at tetrohedron
    mics[0] = new PVector(0.15, 0, 0);
    mics[1] = new PVector(-0.15, 0, 0);
    mics[2] = new PVector(  0,-0.17, 0.0);
    mics[3] = new PVector(  0, 0.065,-0.10);
    
    // mic2 above gree
    //mics[0] = new PVector(0.15, 0, 0);
    //mics[1] = new PVector(-0.15, 0, 0);
    //mics[2] = new PVector(  0,-0.12, 0.17);
    //mics[3] = new PVector(  0, 0.065,-0.10);
    
    
  scene3DBuffer = createGraphics(width, height, P3D); // P3D for 3D rendering
  hitSound = new SoundFile(this, "242664__reitanna__quack.wav");
  dingSound = new SoundFile(this, "573381__ammaro__ding.wav");
   
  e1 = new Eye(820, 430, 220);
  e2 = new Eye(420, 430, 220);
  
  // GAME MODE: Initialize mosquito
  mosquito = new Mosquito();
  
  // ANTI-FLICKER: Initialize PGraphics buffers
  fftBuffer = createGraphics(width, height);
  corrBuffer = createGraphics(width, height);
  
  // Initialize waterfall buffer for FFT mode
  waterfallRows = WATERFALL_HEIGHT;
  waterfallBuffer = createGraphics(FFT_BINS, waterfallRows);
  waterfallBuffer.beginDraw();
  waterfallBuffer.background(0);
  waterfallBuffer.endDraw();
  
  // Initialize waterfall buffer for CORR mode
  corrWaterfallRows = CORR_WATERFALL_HEIGHT;
  corrWaterfallBuffer = createGraphics(FFT_SIZE, corrWaterfallRows);
  corrWaterfallBuffer.beginDraw();
  corrWaterfallBuffer.background(0);
  corrWaterfallBuffer.endDraw();

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
  if (newMode == MODE_FFT) {
    command = "MODE_FFT\n";
    modeChangeStatus = "Requesting FFT mode...";
  } else if (newMode == MODE_CORR_01) {
    command = "MODE_CORR_01\n";
    modeChangeStatus = "Requesting CORR mode...";
  } else if (newMode == MODE_EYE) {
    command = "MODE_EYE\n";
    modeChangeStatus = "Requesting EYE mode...";
  } else if (newMode == MODE_GAME) {
    command = "MODE_GAME\n";
    modeChangeStatus = "Requesting GAME mode...";
  } else if (newMode == MODE_CORR_23) {
    command = "MODE_CORR_23\n";
    modeChangeStatus = "Requesting MODE_CORR_23 mode...";
  } else if (newMode == MODE_CORR_02) {
    command = "MODE_CORR_02\n";
    modeChangeStatus = "Requesting MODE_CORR_02 mode...";
  } else if (newMode == MODE_CORR_03) {
    command = "MODE_CORR_03\n";
    modeChangeStatus = "Requesting MODE_CORR_03 mode...";
  } else if (newMode == MODE_3D_LOCATION) {
    command = "MODE_3D_LOCATION\n";
    modeChangeStatus = "Requesting MODE_3D_LOCATION mode...";
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
      
      frameCount = 0; // reset frameCount on mode change
      signalDetectedByTDOAmic01 = 0;
      
      return;
    }
 
    // Route to appropriate serial event handler based on current mode
    // BUFFER CORRUPTION PREVENTION: Only process data if not changing modes
    if (!modeChanging) {
      if (currentMode == MODE_FFT) {
        serialEvent_fft(data); // FFT mode
      } else if (currentMode == MODE_CORR_01 || currentMode == MODE_CORR_23 || currentMode == MODE_CORR_02 || currentMode == MODE_CORR_03) {
        serialEvent_corr(data); // CORR mode
      } else if (currentMode == MODE_EYE || currentMode == MODE_GAME) {
        serialEvent_Eyes(data); // EYE or GAME mode
      }else if (currentMode == MODE_3D_LOCATION) {
        serialEvent_3D(data);
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

    if (values.length == FFT_BINS) {
      for (int i = 0; i < FFT_BINS; i++) {
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
        for (int i = 0; i < FFT_SIZE; i++) {
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
    frameCount = (++frameCount) % FRAME_WINDOW;
    if(frameCount == 0) {
      prevSureFrameCount = signalDetectedByTDOAmic01;
      signalDetectedByTDOAmic01 = 0;
    }
    
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
      println(String.format("INFO: mic01 p0:%10.6f []:%5d, p1:%10.6f []:%5d (p0/p1:%10.6f <> 1.5, psr:%10.6f <> 6.0); mic23 %10.6f %5d, %10.6f %5d (%10.6f) %10.6f;  %s",
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
    if(sure_signal.equals("1") || sure_signal.equals("12") ){
      signalDetectedByTDOAmic01 = (++signalDetectedByTDOAmic01) % FRAME_WINDOW; 
    }
  }
}




// MODE: 3D
void serialEvent_3D(String data) {
  if (data.equals("3D_START")) {
    receivingData = true; // Start receiving PHAT data packet
    
    // Record timing: new frame arrived
    long currentTime = millis();
    if (lastFrameTime > 0) {
      timeBetweenFrames = (currentTime - lastFrameTime);
    }
    frameArrivalTime = currentTime;
    lastFrameTime = currentTime;
    frameCount++;
    
    
    modeChangeStatus = "Receiving 3D data..."; // Update status message
    
    return;
  }

  if (data.equals("3D_END")) {
    receivingData = false; // End of PHAT data packet
    
    // Record timing: frame fully received
    long receiveEndTime = millis();
    float receiveTime = receiveEndTime - frameArrivalTime;
    
    modeChangeStatus = "3D data received correctly"; // Update status message
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
    
    mic02_phat_peak_value = float(values[5]);
    mic02_phat_peak_idx =float(values[6]);
    mic02_phat_second_value = float(values[7]);
    mic02_phat_second_idx =float(values[8]);
    mic02_psr = float(values[9]);
    
    mic03_phat_peak_value = float(values[10]);
    mic03_phat_peak_idx =float(values[11]);
    mic03_phat_second_value = float(values[12]);
    mic03_phat_second_idx =float(values[13]);
    mic03_psr = float(values[14]);
    
    sure_signal = "";
    //if(mic01_phat_peak_value/mic01_phat_second_value > 1.5 && mic01_phat_peak_value > 0.2) sure_signal = "1";
    //if(mic23_phat_peak_value/mic23_phat_second_value > 1.5 && mic23_phat_peak_value > 0.2) sure_signal += "2";
    if(mic01_phat_peak_value/mic01_phat_second_value > 1.5 && mic01_phat_peak_value > 0.2 && mic01_psr > 6.0f) sure_signal = "1";
    if(mic02_phat_peak_value/mic02_phat_second_value > 1.5 && mic02_phat_peak_value > 0.2 && mic02_psr > 6.0f) sure_signal += "2";    
    if(mic03_phat_peak_value/mic03_phat_second_value > 1.5 && mic03_phat_peak_value > 0.2 && mic03_psr > 6.0f) sure_signal += "3";   
    
    if(! sure_signal.equals("")) {
      float dd01 = mic01_phat_peak_idx * 1/44100 * 343 * 100;
      float dd02 = mic02_phat_peak_idx * 1/44100 * 343 * 100; 
      float dd03 = mic03_phat_peak_idx * 1/44100 * 343 * 100; // cm
      println(String.format("INFO: mic01 p0:%4.2f []:%5d, p1:%4.2f []:%5d (p0/p1:%4.2f <> 1.5, psr:%5.2f <> 6.0) || mic02 %4.2f %3d, %4.2f %5d (%5.2f) %5.2f || mic03 %4.2f %3d, %4.2f %5d (%5.2f) %5.2f || (%5.1f, %5.1f, %5.1f) || %s",
          mic01_phat_peak_value, (int)mic01_phat_peak_idx, 
          mic01_phat_second_value, (int)mic01_phat_second_idx,
          mic01_phat_peak_value/mic01_phat_second_value,
          mic01_psr,
          mic02_phat_peak_value, (int)mic02_phat_peak_idx,
          mic02_phat_second_value, (int)mic02_phat_second_idx,
          mic02_phat_peak_value/mic02_phat_second_value,
          mic02_psr,
          mic03_phat_peak_value, (int)mic03_phat_peak_idx,
          mic03_phat_second_value, (int)mic03_phat_second_idx,
          mic03_phat_peak_value/mic03_phat_second_value,
          mic03_psr,
          dd01, dd02, dd03,
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
  text("Mode: " + getModeNameForDisplay(currentMode) + " | Receiving: " + receivingData + " | Frame: " + nf(frameCount, 2) + 
    " | sureFrame: " + signalDetectedByTDOAmic01 + " | prevSureFrame: " + nf(prevSureFrameCount, 2) , 20, 20);
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
  if (currentMode == MODE_FFT) {
    drawFFTMode(); // MODE: FFT
  } else if (currentMode == MODE_CORR_01 || currentMode == MODE_CORR_23 || currentMode == MODE_CORR_02 || currentMode == MODE_CORR_03) {
    drawCorrMode(currentMode); // MODE: CORR
  } else if (currentMode == MODE_EYE) {
    drawEyesMode(); // MODE: EYE
  } else if (currentMode == MODE_GAME) {
    drawGameMode(); // MODE: GAME (same as EYE for now)
  } else if (currentMode == MODE_3D_LOCATION) {
    draw3DMode();
  }
  
  // Draw mode selection instructions
  fill(255, 255, 0);
  textSize(18);
  textAlign(CENTER);
  text("Press '1' for FFT | '2' for EYE | '9 or 0' for CORR | '4' for GAME", width/2, height - 20);
  
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
  for (int i = 0; i < FFT_BINS; i++) {
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
  
  for (int i = 0; i < FFT_BINS; i++) {
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
  for (int i = 0; i < FFT_BINS; i++) {
    if (fft_data[i] > maxVal) {
      maxVal = fft_data[i];
    }
  }
  if (maxVal == 0) maxVal = 1; // Prevent division by zero
  
  // Scroll waterfall down by copying pixels
  waterfallBuffer.beginDraw();
  waterfallBuffer.copy(0, 0, FFT_BINS, waterfallRows - 1, 0, 1, FFT_BINS, waterfallRows - 1);
  
  // Add new row at top
  for (int i = 0; i < FFT_BINS; i++) {
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
  int corrTop = 350; // Start correlation graph lower to make room for waterfall
  int graphBottom = corrTop + CORR_GRAPH_HEIGHT;
  int graphWidth = width - 100;
  
  // Y-axis scale is fixed from 0 to 1 (correlation values are normalized)
  float minScale = 0.0;
  float maxScale = 1.0;
  
  if (max_value > draw_vertical_line_threshold) {
    // Draw line graph
    corrBuffer.stroke(255, 150, 100);
    corrBuffer.strokeWeight(2);
    corrBuffer.noFill();
    corrBuffer.beginShape();
    for (int i = 0; i < FFT_SIZE; i++) {
      float x = map(i, 0, FFT_SIZE-1, 50, width - 50);
      // Map correlation data from 0 to 1 scale
      float y = map(correlation_data[i], minScale, maxScale, graphBottom, corrTop);
      y = constrain(y, corrTop, graphBottom); // Clamp to graph bounds
      corrBuffer.vertex(x, y);
    }
    corrBuffer.endShape();
  }
  
  // Draw vertical line at peak
  if (max_value > draw_vertical_line_threshold) {
    float peakX = map(max_idx, 0, FFT_SIZE-1, 50, width - 50);
    float peakY = map(max_value, minScale, maxScale, graphBottom, corrTop);
    
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
    int display_idx = max_idx < FFT_BINS ? max_idx : max_idx - FFT_SIZE;
    corrBuffer.text("Index: " + display_idx, peakX, peakY - 35);
  }
  
  // Draw axes
  corrBuffer.stroke(255);
  corrBuffer.strokeWeight(1);
  corrBuffer.line(50, graphBottom, width - 50, graphBottom); // X-axis
  corrBuffer.line(50, corrTop, 50, graphBottom); // Y-axis
  
  // Draw Y-axis grid lines and labels
  corrBuffer.stroke(80, 80, 100);
  corrBuffer.strokeWeight(1);
  corrBuffer.fill(180);
  corrBuffer.textSize(12);
  corrBuffer.textAlign(RIGHT);
  for (int i = 0; i <= 5; i++) {
    float yValue = i * 0.2; // 0.0, 0.2, 0.4, 0.6, 0.8, 1.0
    float yPos = map(yValue, minScale, maxScale, graphBottom, corrTop);
    
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
  corrBuffer.text("256", 50 + graphWidth * 0.25, graphBottom + 20);
  corrBuffer.text("512", 50 + graphWidth * 0.5, graphBottom + 20);
  corrBuffer.text("768", 50 + graphWidth * 0.75, graphBottom + 20);
  corrBuffer.textAlign(RIGHT);
  corrBuffer.text("1023", width - 50, graphBottom + 20);
  corrBuffer.textAlign(CENTER);
  
  // Overall peak info
  corrBuffer.fill(255);
  corrBuffer.textSize(14);
  corrBuffer.text("Peak: " + nf(max_value, 0, 6) + " at index " + max_idx, width/2, graphBottom + 40);
  
  // Display info
  corrBuffer.fill(255);
  corrBuffer.textAlign(LEFT, TOP);
  corrBuffer.textSize(12);
  corrBuffer.text("Correlation Result (sparse: 21 values)", 60, corrTop + 10);
  
  corrBuffer.endDraw();
  
  // Update waterfall
  updateWaterfallCorr();
}

// Update waterfall spectrogram for CORR mode
void updateWaterfallCorr() {
  // Scroll waterfall down by copying pixels
  corrWaterfallBuffer.beginDraw();
  corrWaterfallBuffer.copy(0, 0, FFT_SIZE, corrWaterfallRows - 1, 0, 1, FFT_SIZE, corrWaterfallRows - 1);
  
  // Add new row at top (correlation data)
  // Color based on correlation strength (0 to 1)
  for (int i = 0; i < FFT_SIZE; i++) {
    float value = correlation_data[i];
    
    // Convert to color
    int colorValue = getColorForCorrValue(value);
    
    corrWaterfallBuffer.set(i, 0, colorValue);
  }
  
  corrWaterfallBuffer.endDraw();
}

// Color mapping for CORR waterfall (similar to FFT but different scheme)
int getColorForCorrValue(float value) {
  // Correlation values are 0 to 1
  value = constrain(value, 0, 1);
  
  int r, g, b;
  
  if (value < 0.2) {
    // Black to blue
    float t = value / 0.2;
    r = 0;
    g = 0;
    b = int(t * 255);
  } else if (value < 0.4) {
    // Blue to cyan
    float t = (value - 0.2) / 0.2;
    r = 0;
    g = int(t * 255);
    b = 255;
  } else if (value < 0.6) {
    // Cyan to green
    float t = (value - 0.4) / 0.2;
    r = 0;
    g = 255;
    b = int((1 - t) * 255);
  } else if (value < 0.8) {
    // Green to yellow
    float t = (value - 0.6) / 0.2;
    r = int(t * 255);
    g = 255;
    b = 0;
  } else {
    // Yellow to red
    float t = (value - 0.8) / 0.2;
    r = 255;
    g = int((1 - t) * 255);
    b = 0;
  }
  
  return color(r, g, b);
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
void drawCorrMode(int mode) {
  fill(255);
  textSize(24);
  textAlign(CENTER);
  if(mode == MODE_CORR_01) {
      text("CORR MODE - Correlation mic0, mic1", width/2, 140);
  } else if(mode == MODE_CORR_23) {
      text("CORR MODE - Correlation mic2, mic3", width/2, 140);
  } else if(mode == MODE_CORR_02) {
      text("CORR MODE - Correlation mic0, mic2", width/2, 140);
  } else if(mode == MODE_CORR_03) {
      text("CORR MODE - Correlation mic0, mic3", width/2, 140);
  }

  
  // ANTI-FLICKER: Draw from buffer if available
  if (corrBufferReady) {
    image(corrBuffer, 0, 0);
    
    // Draw waterfall spectrogram for correlation
    int waterfallTop = 680;
    image(corrWaterfallBuffer, 50, waterfallTop, width - 100, CORR_WATERFALL_HEIGHT);
    
    // Draw frame around waterfall
    noFill();
    stroke(255);
    strokeWeight(2);
    rect(50, waterfallTop, width - 100, CORR_WATERFALL_HEIGHT);
    
    // X-axis labels for waterfall (0 to 1023)
    fill(255);
    textAlign(CENTER, TOP);
    textSize(14);
    int plotWidth = width - 100;
    int labelY = waterfallTop + CORR_WATERFALL_HEIGHT + 5;
    
    text("0", 50, labelY);
    text("256", 50 + plotWidth * 0.25, labelY);
    text("512", 50 + plotWidth * 0.5, labelY);
    text("768", 50 + plotWidth * 0.75, labelY);
    text("1023", width - 50, labelY);
    
    // Waterfall title
    textAlign(LEFT, TOP);
    textSize(14);
    fill(255);
    text("Correlation Waterfall", 60, waterfallTop - 25);
    
    // Time axis label
    textAlign(CENTER, CENTER);
    pushMatrix();
    translate(20, waterfallTop + CORR_WATERFALL_HEIGHT/2);
    rotate(-HALF_PI);
    text("Time (newest at top)", 0, 0);
    popMatrix();
    
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
    
    // Save data to file if recording
    if (recording && output != null) {
      output.println(millis() + "," + sure_signal + "," + mic01_phat_peak_idx + "," + mic23_phat_peak_idx);
    }
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



// MODE: EYE - Eyes tracking display
void draw3DMode() {
  //fill(255);
  textSize(24);
  textAlign(CENTER);
  text("3D MODE - Location Tracking", width/2, 100);
  
  noStroke();  // Eyes should have no stroke
  
  int leftX = 92;
  int rightX = 1113;
  int upY = 130;
  int downY = 830;
  
  if(sure_signal.equals("1") || sure_signal.equals("2") || sure_signal.equals("12") || sure_signal.equals("123")) {
    
    //mics[0] = new PVector(-0.15, 0, 0);
    //mics[1] = new PVector( 0.15, 0, 0);
    //mics[2] = new PVector(  0,-0.10, 0.09);
    //mics[3] = new PVector(  0, 0.065,-0.10);
    // Display eye position info
    fill(100, 255, 100);
    textSize(14);
    textAlign(LEFT);
    text("dt01: " + nf(1/44100*mic01_phat_peak_idx, 0, 6), 20, 120);
    text("dt02: " + nf(1/44100*mic02_phat_peak_idx, 0, 6), 20, 140);
    text("dt03: " + nf(1/44100*mic03_phat_peak_idx, 0, 6), 20, 160);
    
    locateSound3DFromGCC(
      mics[0], mics[1], mics[2], mics[3],
      (int)mic01_phat_peak_idx, (int)mic02_phat_peak_idx, (int)mic03_phat_peak_idx,
      soundPos
    );

    drawMicAndSoundScene(
      mics,
      soundPos,
      rotX, rotY, zoom
    );
    
 
    // Save data to file if recording
    if (recording && output != null) {
      output.println(millis() + "," + sure_signal + "," + mic01_phat_peak_idx + "," + mic23_phat_peak_idx);
    }
  }
 
  // ANTI-FLICKER: Draw from buffer if available (MOVED OUTSIDE if statement otherwise, it will erate if sure_signale condition is not met)
  if (scene3DBufferReady) {
    image(scene3DBuffer, 0, 0);
  }
  

}

// MODE: GAME - Game display (same as EYE for now)
// MODE: GAME - Game display (same as EYE for now)
void drawGameMode() {
  fill(255);
  textSize(32);
  textAlign(CENTER);
  text("MOSQUITO HUNTER - Clap to Kill!", width/2, 60);
  
  // Calculate remaining time
  long elapsedTime = millis() - gameStartTime;
  long remainingTime = gameDuration - elapsedTime;
  
  // Check if time expired
  //if (remainingTime <= 0 && gameActive) {
  //  gameActive = false;
  //  showRestartDialog = true;
  //  remainingTime = 0;
  //}
  if (remainingTime <= 0 && gameActive) {
    gameActive = false;
    showRestartDialog = true;
    isNewHighScore = isTopTenScore(gameScore);
    if (isNewHighScore) {
      isEnteringName = true;
      playerName = "";
    }
    remainingTime = 0;
  }
  // Display score and timer
  fill(255, 255, 0);
  textSize(48);
  text("Score: " + gameScore, width/2 - 200, 120);
  
  // Display countdown timer
  int seconds = (int)(remainingTime / 1000);
  fill(remainingTime < 10000 ? color(255, 0, 0) : color(0, 255, 0)); // Red when < 10s
  textSize(48);
  text("Time: " + seconds + "s", width/2 + 200, 120);
  
  // Display instructions
  fill(200);
  textSize(16);
  text("Clap near the mosquito to kill it! (within " + killDistance + " pixels)", width/2, 160);
  text("Mosquito scale: " + nf(mosquitoScale, 0, 1) + "x", width/2, 180);
  
  // Show restart dialog if game ended
  if (showRestartDialog) {
    // Semi-transparent overlay
    fill(0, 0, 0, 200);
    rect(0, 0, width, height);
    
    // Dialog box
    fill(40, 50, 60);
    stroke(255);
    strokeWeight(3);
    rectMode(CENTER);
    //rect(width/2, height/2, 500, 300, 10);
    rect(width/2, height/2, 700, 600, 10);
    rectMode(CORNER);
    
    // Game over text
    fill(255, 255, 0);
    textSize(48);
    textAlign(CENTER);
    //text("TIME'S UP!", width/2, height/2 - 60);
    text("TIME'S UP!", width/2, height/2 - 260);
    // Final score
    //fill(255);
    //textSize(36);
    //text("Final Score: " + gameScore, width/2, height/2);
    fill(255);
    textSize(36);
    text("Your Score: " + gameScore, width/2, height/2 - 210);
    
    // Check if it's a new record
    if (isNewHighScore && highScores.size() > 0 && gameScore > highScores.get(0).score) {
      fill(255, 215, 0); // Gold color
      textSize(32);
      text("🎉 NEW HIGH SCORE! 🎉", width/2, height/2 - 170);
      fill(255, 100, 100);
      textSize(24);
      text("CONGRATULATIONS! You broke the record!", width/2, height/2 - 140);
    } else if (isNewHighScore) {
      fill(0, 255, 0);
      textSize(28);
      text("Top 10 Score!", width/2, height/2 - 170);
    }
    
    // Restart button
    // Name entry if new high score
    if (isEnteringName) {
      fill(255);
      textSize(20);
      text("Enter your name:", width/2, height/2 - 100);
      
      // Name input box
      fill(60, 70, 80);
      stroke(255);
      strokeWeight(2);
      rect(width/2 - 150, height/2 - 75, 300, 40, 5);
      
      // Display entered name
      fill(255, 255, 0);
      textSize(24);
      text(playerName + "_", width/2, height/2 - 45);
      
      fill(200);
      textSize(14);
      text("Type your name and press ENTER", width/2, height/2 - 20);
    } else {
      // High scores table
      fill(255);
      textSize(28);
      text("HIGH SCORES", width/2, height/2 - 80);
      
      textAlign(LEFT);
      textSize(18);
      int startY = height/2 - 40;
      
      for (int i = 0; i < min(10, highScores.size()); i++) {
        HighScore hs = highScores.get(i);
        
        // Highlight current player's score
        if (hs.score == gameScore && hs.name.equals(playerName)) {
          fill(255, 255, 0);
        } else {
          fill(200);
        }
        
        String rank = (i + 1) + ".";
        text(rank, width/2 - 280, startY + i * 30);
        text(hs.name, width/2 - 240, startY + i * 30);
        text(hs.score + " pts", width/2 + 100, startY + i * 30);
      }
      
      // Restart button
      textAlign(CENTER);
      fill(0, 200, 0);
      stroke(255);
      strokeWeight(2);
      rect(width/2 - 100, height/2 + 220, 200, 60, 5);
      
      fill(255);
      textSize(28);
      text("RESTART", width/2, height/2 + 258);
      
      // Instructions
      fill(200);
      textSize(16);
      text("Click the button to play again!", width/2, height/2 + 290);
    }
    
    return; // Don't draw game elements when dialog is shown
  }
  
  // Only update and display game if active
  if (gameActive) {
    // GAME MODE: Update and display mosquito
    mosquito.update();
    mosquito.display();
    
    // Check if kill animation should end and respawn mosquito
    if (showKillAnimation && (millis() - killAnimationTime) > 500) {
      showKillAnimation = false;
      mosquito.respawn();
    }
    
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
      
      // Check if mosquito was hit (hitbox considers mosquito's scaled size)
      if (mosquito.checkHit(clapX, clapY, killDistance) && !showKillAnimation) {
        mosquito.kill();
        gameScore += 10; // Award points
        
        //
        if(gameScore % 100 == 0) {
          if(dingSound != null) { dingSound.play(); }
        } else {
          if(hitSound != null) { hitSound.play(); }
        }
        
        // Start kill animation (non-blocking)
        showKillAnimation = true;
        killAnimationTime = millis();
        
        // Add success message
        String msg = millis() + ": HIT! +10 points";
        gameMessages.add(msg);
        if (gameMessages.size() > 5) gameMessages.remove(0);
        
        println("MOSQUITO KILLED! Score: " + gameScore);
        
        // NO MORE delay() - animation happens in draw loop!
      } else if (!showKillAnimation) {
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
      
      // Circle showing kill radius (fixed at 100px regardless of mosquito scale)
      stroke(255, 255, 0, alpha * 0.5);
      strokeWeight(2);
      ellipse(lastClapX, lastClapY, killDistance * 2, killDistance * 2);
    }
    
    // GAME MODE: Draw kill animation effect
    if (showKillAnimation) {
      float animProgress = (millis() - killAnimationTime) / 500.0; // 0 to 1
      float alpha = map(animProgress, 0, 1, 255, 0);
      
      // Explosion effect
      stroke(255, 255, 0, alpha);
      strokeWeight(3);
      noFill();
      float explosionSize = map(animProgress, 0, 1, mosquito.size, mosquito.size * 3);
      ellipse(mosquito.x, mosquito.y, explosionSize, explosionSize);
      
      // Draw "SPLAT!" text
      fill(255, 0, 0, alpha);
      textSize(32);
      textAlign(CENTER);
      text("SPLAT!", mosquito.x, mosquito.y - 50);
    }
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
  
  // Draw mosquito position and size info
  if (mosquito.alive && gameActive) {
    fill(255, 100, 100);
    text("Mosquito at: (" + nf(mosquito.x, 0, 2) + ", " + nf(mosquito.y, 0, 2) + ")", 20, 440);
    text("Mosquito size: " + nf(mosquito.size, 0, 1) + " (scale: " + nf(mosquitoScale, 0, 1) + "x)", 20, 460);
    text("Kill distance: " + killDistance + "px (fixed) + mosquito radius", 20, 480);
    text("Game: width " + width + " height " + height, 20, 500);
    
    // Draw mosquito hitbox visualization (for debugging)
    noFill();
    stroke(255, 100, 100, 100);
    strokeWeight(1);
    float effectiveHitbox = killDistance + (mosquito.size * 0.5);
    ellipse(mosquito.x, mosquito.y, effectiveHitbox * 2, effectiveHitbox * 2);
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
  
  // Handle name entry in game mode
  if (currentMode == MODE_GAME && isEnteringName) {
    if (key == ENTER || key == RETURN) {
      if (playerName.length() > 0) {
        addHighScore(playerName, gameScore);
        isEnteringName = false;
        println("High score added: " + playerName + " - " + gameScore);
      }
    } else if (key == BACKSPACE) {
      if (playerName.length() > 0) {
        playerName = playerName.substring(0, playerName.length() - 1);
      }
    } else if (key >= 32 && key <= 126 && playerName.length() < 15) {
      // Allow printable characters, max 15 chars
      playerName += key;
    }
    return; // Don't process other keys while entering name
  }
  
  if (key == 's' || key == 'S') {
    saveFrame("fft_snapshot_####.png");
    println("Screenshot saved!");
  }

  // MODE SWITCHING: Handle key presses for mode changes
  if (key == '1') {
    println("KEY PRESSED: Requesting FFT mode");
    requestModeChange(MODE_FFT); // Request FFT mode
  }
  else if (key == '2') {
    println("KEY PRESSED: Requesting EYE mode");
    requestModeChange(MODE_EYE); // Request EYE mode
  }

 
  else if (key == '3') {
    println("KEY PRESSED: Requesting GAME mode");
    requestModeChange(MODE_GAME);
    startGame(); // Auto-start game when entering mode
  }
 

  else if (key == '7') {
    println("KEY PRESSED: Requesting CORR mode");
    requestModeChange(MODE_CORR_01); // Request CORR mode
  }
  else if (key == '8') {
    println("KEY PRESSED: Requesting CORR mode");
    requestModeChange(MODE_CORR_02); // Request CORR mode
  }
  else if (key == '9') {
    println("KEY PRESSED: Requesting CORR mode");
    requestModeChange(MODE_CORR_03); // Request CORR mode
  }
  else if (key == '0') {
    println("KEY PRESSED: Requesting SANITY mode");
    requestModeChange(MODE_CORR_23); // Request CORR mode
  }
  else if (key == '4') {
    println("KEY PRESSED: Requesting 3D mode");
    requestModeChange(MODE_3D_LOCATION); // Request MODE_3D_LOCATION mode
  }
    // DATA RECORDING: Press 'R' to start/stop recording
  else if (key == 'r' || key == 'R') {
    if (!recording) {
      // Start recording
      String filename = "eye_data_" + year() + nf(month(), 2) + nf(day(), 2) + "_" + 
                        nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2) + ".csv";
      output = createWriter(filename);
      output.println("timestamp,sure_signal,mic01_phat_peak_idx,mic23_phat_peak_idx"); // CSV header
      recording = true;
      println("Started recording to: " + filename);
    } else {
      // Stop recording
      output.flush(); // Write remaining data
      output.close(); // Close file
      recording = false;
      println("Recording stopped and file saved!");
    }
  }
}

void startGame() {
  //gameScore = 0;
  //gameStartTime = millis();
  //gameActive = true;
  //showRestartDialog = false;
  //mosquito.respawn();
  //gameMessages.clear();
  //println("Game started!");
  
  gameScore = 0;
  gameStartTime = millis();
  gameActive = true;
  showRestartDialog = false;
  isEnteringName = false;
  isNewHighScore = false;
  playerName = "";
  mosquito.respawn();
  gameMessages.clear();
  println("Game started!");
}

void __mousePressed() {
  // Only enable rotation in 3D mode
  if (currentMode == MODE_3D_LOCATION) {
    isDragging = true;
    prevMouseX = mouseX;
    prevMouseY = mouseY;
  }
  
  // Handle restart button click in GAME mode
  if (currentMode == MODE_GAME && showRestartDialog) {
    // Check if click is on restart button (centered at width/2, height/2 + 70)
    if (mouseX > width/2 - 100 && mouseX < width/2 + 100 &&
        mouseY > height/2 + 40 && mouseY < height/2 + 100) {
      startGame();
    }
  }
}
void mousePressed() {
  if (currentMode == MODE_3D_LOCATION) {
    isDragging = true;
    prevMouseX = mouseX;
    prevMouseY = mouseY;
  }
  
  // Handle restart button click (only when not entering name)
  if (currentMode == MODE_GAME && showRestartDialog && !isEnteringName) {
    if (mouseX > width/2 - 100 && mouseX < width/2 + 100 &&
        mouseY > height/2 + 220 && mouseY < height/2 + 280) {
      startGame();
    }
  }
}
void mouseReleased() {
  isDragging = false;
}

void mouseDragged() {
  // Only rotate in 3D mode when dragging
  if (currentMode == MODE_3D_LOCATION && isDragging) {
    float dx = mouseX - prevMouseX;
    float dy = mouseY - prevMouseY;
    
    // Update rotation based on mouse movement
    rotY += dx * 0.01; // Horizontal mouse movement rotates around Y-axis
    rotX += dy * 0.01; // Vertical mouse movement rotates around X-axis
    
    // Store current mouse position for next frame
    prevMouseX = mouseX;
    prevMouseY = mouseY;
  }
}

void mouseWheel(MouseEvent event) {
  // Only zoom in 3D mode
  if (currentMode == MODE_3D_LOCATION) {
    float e = event.getCount();
    zoom += e * 10; // Adjust zoom speed as needed
    zoom = constrain(zoom, 50, 1000); // Limit zoom range
  }
}
