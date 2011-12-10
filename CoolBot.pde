#include <SPI.h>
#include <Ethernet.h>
#include <TimedAction.h>
#include <OneWire.h>
#include <stdio.h>


byte mac[] = { 
  0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED};
// assign an IP address for the controller:
byte ip[] = { 
  172,31,24,55 };
byte gateway[] = {
  172,31,24,1};	
byte subnet[] = { 
  255, 255, 255, 0 };

//  The address of the server you want to connect to (pachube.com):
byte server[] = { 
  172,31,24,101 }; 

// initialize the library instance:
Client client(server, 8022);


int relay = 0;
int oldWaterReading;
int oldRoomReading;
int waitingForPing = 0;
int laserStatus = 1;
long lazorTimer;
char buffer1[50];
char buffer2[50];
char buffer3[50];
long timeOut = 0;
int lazorPin = 2;
int relayPin = 3;

// DS18S20 Temperature chip i/o
OneWire ds1(5);  // on pin 10
OneWire ds2(6);  // on pin 10

TimedAction checkWaterTemprature = TimedAction(5000,serviceWaterTemprature);
TimedAction checkRoomTemprature = TimedAction(20000,serviceRoomTemprature);
TimedAction heartBeat = TimedAction(300000,beat);
TimedAction checkLazorStatus = TimedAction(1000,checkLazor);

void beat(){
  sendGetRequest("beat=true");
}

void checkLazor(){
  int lazor = digitalRead(lazorPin);
  //Serial.println(lazor);
  if(lazor!=laserStatus){
    delay(1000);
    if(lazor==digitalRead(lazorPin)){
      //Serial.println("lazor not match");
      //Serial.println(laserStatus);
      if(lazor==0){
        // ************* SEND LAZOR ON AND START COUNTER **************
        sendGetRequest("lazor=on");
        lazorTimer = millis();
      }
      else{
        // ************* SEND LAZOR OFF AND HOW LONG ON FOR ************
        long lazordTime = (millis() - lazorTimer) / 1000;
        if(lazordTime<4){
          lazordTime = 0;
        }
        sprintf(buffer1, "lazor=off&timeOn=%d", lazordTime);
        sendGetRequest(buffer1);
      }
    laserStatus = !laserStatus;
    }
  }
}

void serviceWaterTemprature(){
  int reading = readWater();
  //Serial.print("Water:");
  //Serial.println(reading);
  if(reading>2200){
    digitalWrite(relayPin,HIGH);
    if(relay==0){
      relay = 1;
      // **************** SEND COOLING ON **************
      sendGetRequest("cooling=true");
    }
  }
  else if(reading<1900){
    digitalWrite(relayPin,LOW);
    if(relay==1){
      relay = 0;
      // **************** SEND COOLING OFF **************
      sendGetRequest("cooling=false");
    }
  }

  if(reading!=oldWaterReading){
    // ****************** SEND NEW TEMPRATURE ***************
    oldWaterReading = reading;
    sprintf(buffer2, "water=%d", reading);
    sendGetRequest(buffer2);
  }


}

void serviceRoomTemprature(){
  int reading = readRoom();
  //Serial.print("Room:");
  //Serial.println(reading);
  if(reading!=oldRoomReading){
    // ****************** SEND NEW TEMPRATURE ***************
    oldRoomReading = reading;
    sprintf(buffer3, "room=%d", reading);
    sendGetRequest(buffer3);
  }

}

void sendGetRequest(char* message){
  Serial.println(message);
  if(!client.connected()){
    client.connect();
  }
  
  if(client.connected()){
    
    client.print("GET /?");
    client.print(message);
    client.println(" HTTP/1.0");
    client.println();
    
    Serial.println("sent data");
    
  }
  else{
    
    Serial.print("ERROR CONNECTING");
    
  }
  
}

int readWater(){
  int HighByte, LowByte, TReading, SignBit, Tc_100, Whole, Fract;
  byte i;
  byte present = 0;
  byte data[12];
  byte addr[8];

  while ( !ds1.search(addr)) {
    //Serial.print("No more addresses.\n");
    ds1.reset_search();
    //return;
  }

  ds1.reset();
  ds1.select(addr);
  ds1.write(0x44,1);         // start conversion, with parasite power on at the end

  long readDelayMillis = millis();
  
  delay(750);
      
  //delay(750);     // maybe 750ms is enough, maybe not
  // we might do a ds.depower() here, but the reset will take care of it.

  present = ds1.reset();
  ds1.select(addr);    
  ds1.write(0xBE);         // Read Scratchpad

  for ( i = 0; i < 9; i++) {           // we need 9 bytes
    data[i] = ds1.read();
  }

  LowByte = data[0];
  HighByte = data[1];
  TReading = (HighByte << 8) + LowByte;
  SignBit = TReading & 0x8000;  // test most sig bit
  if (SignBit) // negative
  {
    TReading = (TReading ^ 0xffff) + 1; // 2's comp
  }
  Tc_100 = (6 * TReading) + TReading / 4;    // multiply by (100 * 0.0625) or 6.25

  return Tc_100;
}

int readRoom(){
  int HighByte, LowByte, TReading, SignBit, Tc_100, Whole, Fract;
  byte i;
  byte present = 0;
  byte data[12];
  byte addr[8];

  while ( !ds2.search(addr)) {
    //Serial.print("No more addresses.\n");
    ds2.reset_search();
    //return;
  }

  ds2.reset();
  ds2.select(addr);
  ds2.write(0x44,1);         // start conversion, with parasite power on at the end

  
  delay(750);     // maybe 750ms is enough, maybe not
  // we might do a ds.depower() here, but the reset will take care of it.

  present = ds2.reset();
  ds2.select(addr);    
  ds2.write(0xBE);         // Read Scratchpad

  for ( i = 0; i < 9; i++) {           // we need 9 bytes
    data[i] = ds2.read();
  }

  LowByte = data[0];
  HighByte = data[1];
  TReading = (HighByte << 8) + LowByte;
  SignBit = TReading & 0x8000;  // test most sig bit
  if (SignBit) // negative
  {
    TReading = (TReading ^ 0xffff) + 1; // 2's comp
  }
  Tc_100 = (6 * TReading) + TReading / 4;    // multiply by (100 * 0.0625) or 6.25

  return Tc_100;
}

void setup(void) {
  // initialize inputs/outputs
  // start serial port
  Serial.begin(9600);
  pinMode(3, OUTPUT);
  pinMode(2, INPUT);
  digitalWrite(2,HIGH);
  digitalWrite(3,LOW);
  
  Ethernet.begin(mac, ip);
  
  delay(1000);
  sendGetRequest("coolBotStartingUp=true");
}

void loop(void) {
  
  while(client.available()) {
    char c = client.read();
    Serial.print(c);
  }
  
  checkWaterTemprature.check();
  checkLazorStatus.check();
  checkRoomTemprature.check();
  heartBeat.check();
}
