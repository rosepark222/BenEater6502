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
    // fill(153, 204, 0); yellowish green
    fill(0);  // black
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
float mic23_phat_peak_value = -1;
float mic23_phat_peak_idx = -10;
float mic23_phat_second_value = -1;
float mic23_phat_second_idx = -10;

float last_max_value = 0;
int  last_max_idx = 0;
  
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
  
  // serialEvent_phat(myPort);
  serialEvent_Eyes(myPort);
  
}

void serialEvent_Eyes(Serial myPort) {
  
  if (myPort == null) return;

  String data = myPort.readStringUntil('\n');
  if (data != null) {
    data = trim(data);

    if (data.equals("PHAT_START")) {
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

    if (data.equals("PHAT_END")) {
      receivingData = false;
            // Record timing: frame fully received
      long receiveEndTime = millis();
      float receiveTime = receiveEndTime - frameArrivalTime;
      
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
      
      mic23_phat_peak_value = float(values[4]);
      mic23_phat_peak_idx =float(values[5]);
      mic23_phat_second_value = float(values[6]);
      mic23_phat_second_idx =float(values[7]);
      
      sure_signal = "";
      if(mic01_phat_peak_value/mic01_phat_second_value > 1.5 && mic01_phat_peak_value > 0.2) sure_signal = "1";
      if(mic23_phat_peak_value/mic23_phat_second_value > 1.5 && mic23_phat_peak_value > 0.2) sure_signal += "2";
      
      println(String.format("INFO: mic01 %10.6f %5d, %10.6f %5d (%10.6f); mic23 %10.6f %5d, %10.6f %5d (%10.6f);  %s",
          mic01_phat_peak_value, (int)mic01_phat_peak_idx, 
          mic01_phat_second_value, (int)mic01_phat_second_idx,
          mic01_phat_peak_value/mic01_phat_second_value,
          mic23_phat_peak_value, (int)mic23_phat_peak_idx,
          mic23_phat_second_value, (int)mic23_phat_second_idx,
          mic23_phat_peak_value/mic23_phat_second_value,
          sure_signal));

    }
 
  }
  
  newFrameAvailable = true; 

}













void serialEvent_phat(Serial myPort) {
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
    
    // println("mouseX: " + mouseX + " mouseY: " + mouseY + " max_idx: " + max_idx + " max_value: " + max_value);
  
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

  if(max_value > 0.25) {
    last_max_value = max_value;
    last_max_idx = max_idx;
  }
  
  fill(100, 255, 100);
  text("max idx: " + nf(last_max_idx, 0, 1), 20, 80);
  
  fill(100, 255, 100);
  text("max value: " + nf(last_max_value, 0, 1), 20, 100);

  




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
  
  int leftX = 92;
  int rightX = 1113;
  int upY = 130;
  int downY = 830;
  
//INFO: mic01 0.289768 38.0, 0.282878 37.0; mic23 0.186098 -3.0, 0.182395 37.0   mic01 peak/second         1.0243568  mic23 peak/second          1.020302 
//INFO: mic01 0.114807 22.0, 0.108704 486.0; mic23 0.111058 -124.0, 0.105166 150.0   mic01 peak/second         1.0561433  mic23 peak/second          1.0560256 
//INFO: mic01 0.113225 -52.0, 0.10392 36.0; mic23 0.098039 -28.0, 0.093445 370.0   mic01 peak/second         1.08954  mic23 peak/second          1.0491626 
//INFO: mic01 0.124512 -9.0, 0.099909 26.0; mic23 0.106888 235.0, 0.103654 9.0   mic01 peak/second         1.2462541  mic23 peak/second          1.0312 
//INFO: mic01 0.100658 -270.0, 0.087885 22.0; mic23 0.120031 -34.0, 0.097734 140.0   mic01 peak/second         1.1453377  mic23 peak/second          1.2281396 
//INFO: mic01 0.199516 5.0, 0.115253 -4.0; mic23 0.110936 24.0, 0.106729 -11.0   mic01 peak/second         1.7311132  mic23 peak/second          1.0394176 1
//sure_signal 1
//sure_signal 1
//INFO: mic01 0.107744 -32.0, 0.091673 218.0; mic23 0.109209 -137.0, 0.107717 -189.0   mic01 peak/second         1.1753079  mic23 peak/second          1.0138512 
//INFO: mic01 0.092765 31.0, 0.092462 -49.0; mic23 0.093404 -40.0, 0.090495 -130.0   mic01 peak/second         1.0032771  mic23 peak/second          1.0321455 
//INFO: mic01 0.106199 -89.0, 0.099672 -233.0; mic23 0.098694 109.0, 0.096115 63.0   mic01 peak/second         1.0654848  mic23 peak/second          1.0268323 
//INFO: mic01 0.114302 65.0, 0.101658 15.0; mic23 0.10024 -103.0, 0.092965 330.0   mic01 peak/second         1.1243778  mic23 peak/second          1.0782553 
//INFO: mic01 0.100437 -20.0, 0.099048 343.0; mic23 0.097852 188.0, 0.087988 459.0   mic01 peak/second         1.0140234  mic23 peak/second          1.1121062 
//INFO: mic01 0.088287 64.0, 0.082093 30.0; mic23 0.11991 12.0, 0.093093 -243.0   mic01 peak/second         1.075451  mic23 peak/second          1.2880667 
//INFO: mic01 0.099985 27.0, 0.096472 25.0; mic23 0.112528 6.0, 0.102204 -172.0   mic01 peak/second         1.0364147  mic23 peak/second          1.1010135 
//INFO: mic01 0.126729 30.0, 0.122697 -381.0; mic23 0.133395 7.0, 0.128345 8.0   mic01 peak/second         1.0328614  mic23 peak/second          1.039347 
//INFO: mic01 0.138063 58.0, 0.111843 34.0; mic23 0.104382 12.0, 0.096786 -299.0   mic01 peak/second         1.2344358  mic23 peak/second          1.0784824 
//INFO: mic01 0.12668 22.0, 0.086161 26.0; mic23 0.094789 -14.0, 0.092553 152.0   mic01 peak/second         1.4702708  mic23 peak/second          1.0241592 
//INFO: mic01 0.117732 -50.0, 0.106614 -37.0; mic23 0.103826 -21.0, 0.102412 -22.0   mic01 peak/second         1.1042827  mic23 peak/second          1.0138069 
//INFO: mic01 0.099507 -53.0, 0.095157 33.0; mic23 0.097043 -40.0, 0.094192 -406.0   mic01 peak/second         1.0457139  mic23 peak/second          1.030268 
//INFO: mic01 0.103044 28.0, 0.09224 3.0; mic23 0.103376 43.0, 0.099734 146.0   mic01 peak/second         1.1171293  mic23 peak/second          1.0365171 
//INFO: mic01 0.099389 10.0, 0.098649 455.0; mic23 0.132888 27.0, 0.098126 4.0   mic01 peak/second         1.0075014  mic23 peak/second          1.3542588 
//INFO: mic01 0.099365 -79.0, 0.097605 27.0; mic23 0.098986 65.0, 0.097586 464.0   mic01 peak/second         1.018032  mic23 peak/second          1.0143464 
//INFO: mic01 0.107805 33.0, 0.105151 -23.0; mic23 0.098396 131.0, 0.086819 159.0   mic01 peak/second         1.02524  mic23 peak/second          1.1333464 
//INFO: mic01 0.105436 30.0, 0.102349 -71.0; mic23 0.127693 175.0, 0.1011 14.0   mic01 peak/second         1.0301615  mic23 peak/second          1.2630366 
//INFO: mic01 0.104685 484.0, 0.086263 45.0; mic23 0.153382 8.0, 0.090384 128.0   mic01 peak/second         1.2135562  mic23 peak/second          1.697004 2
//INFO: mic01 0.091128 -2.0, 0.083634 -397.0; mic23 0.102533 42.0, 0.092249 76.0   mic01 peak/second         1.0896047  mic23 peak/second          1.1114808 

  if(sure_signal.equals("1") || sure_signal.equals("2") || sure_signal.equals("12")) {
    println("sure_signal " + sure_signal);
    if(mic01_phat_peak_idx < 0 && mic23_phat_peak_idx < 0) {
      e1.update(leftX, upY);
      e2.update(leftX, upY);
    } else if(mic01_phat_peak_idx > 0 && mic23_phat_peak_idx < 0) {
      e1.update(rightX, upY);
      e2.update(rightX, upY);
    } else if(mic01_phat_peak_idx < 0 && mic23_phat_peak_idx > 0) {
      e1.update(leftX, downY);
      e2.update(leftX, downY);
    } else if(mic01_phat_peak_idx > 0 && mic23_phat_peak_idx > 0) {
      e1.update(rightX, downY);
      e2.update(rightX, downY);
    }
  }
 
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
