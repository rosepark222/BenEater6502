import processing.serial.*; //<>//

Serial myPort;
boolean newFrameAvailable = false; 
// Eye class for demo mode - DEFINED FIRST
class Eye {
  int x, y;
  int size;
  float angle = 0.0;

  Eye(int tx, int ty, int ts) {
    x = tx;
    y = ty;
    size = ts;
  }

  void update(int mx, int my) {
    angle = atan2(my - y, mx - x);
  }

  void display() {
    pushMatrix();
    translate(x, y);
    fill(255);
    ellipse(0, 0, size, 2*size);
    rotate(angle);
    fill(153, 204, 0);
    ellipse(size/4, 0, size/2, size/2);
    popMatrix();
  }
}

// FFT data storage
float[] correlation_data = new float[1024];
float[] corr_roated = new float[1024];
//float[] mic1_phase = new float[512];
//float[] mic2_magnitude = new float[512];
//float[] mic2_phase = new float[512];

//int displayBins = 20;  // Only display first 24 bins (0-1000 Hz)
 int displayBins = 1024;  // Only display first 24 bins (0-1000 Hz)

boolean showEyes = false;  // Toggle between FFT display and eyes demo

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
  
void setup() {
  size(1400, 1000);
  smooth();

  e1 = new Eye(820, 430, 220);
  e2 = new Eye(420, 430, 220);

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
void serialEvent(Serial myPort) {
  if (myPort == null) return;

  String data = myPort.readStringUntil('\n');
  if (data != null) {
    data = trim(data);

    // Check for data markers
    if (data.equals("FFT_DATA_START")) {
      receivingData = true;

      // Record timing: new frame arrived
      long currentTime = millis();
      if (lastFrameTime > 0) {
        timeBetweenFrames = (currentTime - lastFrameTime);
      }
      frameArrivalTime = currentTime;
      lastFrameTime = currentTime;
      frameCount++;

      return;
    }

    if (data.equals("FFT_DATA_END")) {
      receivingData = false;

      // Record timing: frame fully received
      long receiveEndTime = millis();
      float receiveTime = receiveEndTime - frameArrivalTime;

      //println("Frame " + frameCount +
      //        " | Between frames: " + nf(timeBetweenFrames, 0, 1) + " ms" +
      //        " | Receive time: " + nf(receiveTime, 0, 1) + " ms");

      return;
    }

    if (receivingData) {
      // Check which mic data this is
      if (data.startsWith("CORR:")) {
        currentMic = "CORR";
        data = data.substring(5); // Remove prefix
      } else if (data.startsWith("MIC2:")) {
        currentMic = "MIC2";
        data = data.substring(5); // Remove   prefix
      } else {
        return; // Skip if no prefix
      }

      // Parse magnitude and phase data (interleaved: mag0,phase0,mag1,phase1,...)
      String[] values = split(data, ',');

      if (currentMic.equals("CORR")) {
        for (int i = 0; i < 1024; i++) {
          try {
            // 512 floats * 4 bytes/float = 2048 bytes (2 KB) of data.
            correlation_data[i] = float(values[i]);
          } catch (Exception e) {
            // Skip invalid values
          }
        }
      } 
    }
    
    max_value = -1;
    max_idx = -1;
    for (int i = 0; i < 1024; i++) {
      if( correlation_data[i] > max_value) {
        max_value = correlation_data[i];
        max_idx = i;
      }
    }
    
    println("mouseX: " + mouseX + " mouseY: " + mouseY + " max_idx: " + max_idx + " max_value: " + max_value);
  
  }
  
  newFrameAvailable = true; 

}

void draw() {
  long drawStartTime = millis();
    // Check if we have valid data

  
  background(20, 25, 35);
  // Debug info - TIMING DIAGNOSTICS
  fill(255, 255, 0);
  textSize(14);
  textAlign(LEFT);
  text("Receiving: " + receivingData + " | Current: " + currentMic + " | Frame: " + frameCount, 20, 20);

  fill(255, 100, 100);
  text("Time between frames: " + nf(timeBetweenFrames, 0, 1) + " ms", 20, 40);

  fill(100, 255, 100);
  text("Time to draw frame: " + nf(timeToDrawFrame, 0, 1) + " ms", 20, 60);


  fill(100, 255, 100);
  text("max idx: " + nf(max_idx, 0, 1), 20, 80);
  



  // Check mode and draw accordingly
  if (showEyes) {
    drawEyesDemo();
  } else {
    drawFFTDisplay();
  }
  // Calculate and store draw time
  long drawEndTime = millis();
  timeToDrawFrame = drawEndTime - drawStartTime;
}

void drawEyesDemo() {
  

  noStroke();  // Eyes should have no stroke
  

  
  // int eye_move = 100;
  if(max_value > .05) {
    if(max_idx < 1024/2) {
      e1.update(1113, 430);
      e2.update(1113, 430);
    }else {
      e1.update(92, 430);
      e2.update(92, 430);
    }
  }
      
        //     " | Between frames: " + nf(timeBetweenFrames, 0, 1) + " ms" +
        //     " | Receive time: " + nf(receiveTime, 0, 1) + " ms");
  //e1.update(mouseX, mouseY);
  //e2.update(mouseX, mouseY);

  e1.display();
  e2.display();


  // Mode indicator
  fill(255, 255, 0);
  textSize(24);
  textAlign(CENTER);
  text("EYES DEMO MODE - Press '2' to return to FFT", width/2, height - 40);
}

void drawFFTDisplay() {



  // Debug info - TIMING DIAGNOSTICS
  fill(255, 255, 0);
  textSize(14);
  textAlign(LEFT);
  text("Receiving: " + receivingData + " | Current: " + currentMic + " | Frame: " + frameCount, 20, 20);

  fill(255, 100, 100);
  text("Time between frames: " + nf(timeBetweenFrames, 0, 1) + " ms", 20, 40);

  fill(100, 255, 100);
  text("Time to draw frame: " + nf(timeToDrawFrame, 0, 1) + " ms", 20, 60);
  
  //// Check if we have valid data
  //float max_value = 0;
  //float max_idx = 0;
  //for (int i = 0; i < 1024; i++) {
  //  if( correlation_data[i] > max_value) {
  //    max_value = correlation_data[i];
  //    max_idx = i;
  //  }
  //  //max_value += correlation_data[i];
  //  //max_idx += mic2_magnitude[i];
  //}
  //fill(150, 150, 255);
  //text("corr max: " + nf(max_value, 0, 4) + " | max index: " + nf(max_idx, 0, 4), 400, 20);

  // Title
  fill(100, 200, 255);
  textSize(28);
  textAlign(CENTER);
  text("MIC1 & MIC2 - FFT MAGNITUDE & PHASE", width/2, 100);

  // Subtitle
  fill(150, 180, 255);
  textSize(16);
  text("MIC2 is delayed by 0.3ms (13 samples) from MIC1 | Displaying 0-1000 Hz (24 bins)", width/2, 125);

  int margin = 80;
  int graphWidth = width - margin * 2;
  int graphHeight = 160;
  int spacing = 220;

  // Draw MIC1 Magnitude
  drawFFTGraph(correlation_data, null, margin, 150, graphWidth, graphHeight,
               "MIC1 - MAGNITUDE", color(100, 255, 200), false);

  //// Draw MIC1 Phase
  //drawFFTGraph(null, mic1_phase, margin, 150 + spacing, graphWidth, graphHeight,
  //             "MIC1 - PHASE", color(100, 255, 200), true);

  //// Draw MIC2 Magnitude
  //drawFFTGraph(mic2_magnitude, null, margin, 150 + spacing * 2, graphWidth, graphHeight,
  //             "MIC2 - MAGNITUDE (Delayed)", color(255, 150, 100), false);

  //// Draw MIC2 Phase
  //drawFFTGraph(null, mic2_phase, margin, 150 + spacing * 3, graphWidth, graphHeight,
  //             "MIC2 - PHASE (Delayed)", color(255, 150, 100), true);

  // Connection indicator
  float pulse = sin(frameCount * 0.1) * 0.3 + 0.7;
  fill(100, 255, 150, 255 * pulse);
  noStroke();
  ellipse(width - 40, 80, 24, 24);
  fill(100, 255, 150);
  ellipse(width - 40, 80, 16, 16);

}

//void rotateLeftInPlace(float[] magData, float[] magDataRotated, int MAX_LAG) {
//  //int N = magData.length;

//  for (int i = 0; i < MAX_LAG; i++) {
//    magDataRotated[i] = magData[i + MAX_LAG];
//    magDataRotated[i + MAX_LAG] = magData[i];
//  }
//  magDataRotated[MAX_LAG] = magData[MAX_LAG];
//}

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

void drawFFTGraph(float[] magData, float[] phaseData, int x, int y, int w, int h,
                  String label, color col, boolean isPhase) {
  pushMatrix();
  translate(x, y);

  // Title
  fill(255);
  textSize(18);
  textAlign(LEFT);
  text(label, 0, -10);

  // Draw axes
  stroke(100, 100, 120);
  strokeWeight(2);

  if (isPhase) {
    // Phase graph: zero line in middle
    line(0, h/2, w, h/2);
    line(0, 0, 0, h);
    line(0, h, w, h);

    // Grid lines
    stroke(60, 60, 80);
    strokeWeight(1);
    line(0, h/4, w, h/4);     // +π/2
    line(0, 3*h/4, w, 3*h/4); // -π/2

    // Y-axis labels (phase in radians)
    fill(180);
    textSize(12);
    textAlign(RIGHT);
    text("+π", -10, 5);
    text("+π/2", -10, h/4 + 5);
    text("0", -10, h/2 + 5);
    text("-π/2", -10, 3*h/4 + 5);
    text("-π", -10, h + 5);
  } else {
    // Magnitude graph
    line(0, h, w, h);
    line(0, 0, 0, h);

    // Grid lines
    stroke(60, 60, 80);
    strokeWeight(1);
    for (int i = 1; i <= 4; i++) {
      float yPos = h - (h / 4) * i;
      line(0, yPos, w, yPos);
    }

    // Y-axis labels (magnitude)
    fill(180);
    textSize(12);
    textAlign(RIGHT);
    text("1.0", -10, 5);
    text("0.75", -10, h/4 + 5);
    text("0.5", -10, h/2 + 5);
    text("0.25", -10, 3*h/4 + 5);
    text("0", -10, h + 5);
  }

  // X-axis labels (frequency in Hz for 0-1000 Hz)
  fill(180);
  textSize(11);
  textAlign(CENTER);
  for (int i = 0; i <= 10; i++) {
    float freq = (1000.0 / 10) * i;  // 0 to 1000 Hz
    float xPos = (w / 10.0) * i;
    text(nf(freq, 0, 0) + "Hz", xPos, h + 20);
  }

  // Draw the FFT data - ONLY FIRST 24 BINS
  noFill();
  stroke(col);
  strokeWeight(2);
  beginShape();
  float minDecibel = -60.0;
  if (magData != null) {
    
    // the inplace rotation is called twice if draw is called twice given a frame
    // thus, it should be guarded to do once per frame
    //if (newFrameAvailable) {
    //  rotateLeftInPlace(magData, displayBins / 2);
    //  newFrameAvailable = false;   // VERY IMPORTANT
    //}
    
    shiftIntoNewBuffer(magData, corr_roated, displayBins / 2);
    
    for (int i = 0; i < displayBins; i++) {
      float px = map(i, 0, displayBins - 1, 0, w);
      float py = map(corr_roated[i], 0, 1.0, h, 0);

      //// Map the dB value: from minDecibel to 0dB -> to screen height h to 0
      //// 0dB (loudest) maps to the top (0 y-coordinate)
      //// minDecibel (quietest visible) maps to the bottom (h y-coordinate)
      //float dB = (float) ( 20 * Math.log10(max(corr_roated[i], 0.00001))); // Use max() to avoid log(0)
      //float py = map(dB, minDecibel, 0, h, 0);


      py = constrain(py, 0, h);
      vertex(px, py);
      if(corr_roated[i] > 0.5) {
        println("i:"  + i  + " px:"  + px + " py:" + py + " w:" + w + " h:" + h + " corr_roated: " + corr_roated[i]);
      }
 

    }
    
  } 

  endShape();


  if (corr_roated != null) {
    int peakBin = 0;
    float peakVal = 0;
    for (int i = 0; i < displayBins; i++) {
      if (corr_roated[i] > peakVal) {
        peakVal = corr_roated[i];
        peakBin = i;
      }
    }

    if (peakVal > 0.25) {
      float peakX = map(peakBin, 0, displayBins - 1, 0, w);
      float peakY = map(peakVal, 0, 1.0, h, 0);

      // Vertical line at peak
      stroke(255, 200, 100, 150);
      strokeWeight(2);
      line(peakX, h, peakX, peakY);

      // Peak marker
      fill(255, 200, 100);
      noStroke();
      ellipse(peakX, peakY, 10, 10);

      // TDOA label
      float peakFreq = 30; // (peakBin * 44100.0) / 1024.0;
      if(peakBin < 512) {
        peakFreq = -1*  (( 512.0f - peakBin ) / 44100.0f * 1000.0f);
      } else {
        peakFreq =  ((peakBin - 512.0f ) / 44100.0f * 1000.0f);
      }

      fill(255, 200, 100);
      textSize(22);
      textAlign(CENTER);
      text(nf(peakFreq, 0, 3) + " ms", peakX, peakY - 15);
      
      println("peakBin:"  + peakBin  + " peakVal:"  + peakVal + " peakFreq:" + peakFreq);
    }
  }

  popMatrix();
}

void keyPressed() {
  if (key == 's' || key == 'S') {
    saveFrame("fft_snapshot_####.png");
    println("Screenshot saved!");
  }

  if (key == '2') {
    showEyes = !showEyes;  // Toggle between modes
    println("Mode switched to: " + (showEyes ? "Eyes Demo" : "FFT Display"));
  }
}
