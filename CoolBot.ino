#include <SPI.h>
#include <Ethernet.h>
#include <TimedAction.h>
#include <OneWire.h>
#include <stdio.h>
#include <avr/wdt.h>
#include <NewSoftSerial.h>
#include <EEPROM.h>
#include "EEPROMAnything.h"

NewSoftSerial mySerial(10, 8);

byte mac[] = { 
  0x00, 0x30, 0xBD, 0xB2, 0xFD, 0x59};
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

int buzzer = 9;
int relay = 0;
int oldWaterReading;
int oldRoomReading;
int oldOutflowReading;
int waitingForPing = 0;
int laserStatus = 1;
long lazorTimer;
char buffer1[50];
char buffer2[50];
char buffer3[50];
char buffer4[50];
long timeOut = 0;
int lazorPin = 2;
int relayPin = 3;
long totalLazordTime;

// DS18S20 Temperature chip i/o
OneWire ds1(5);  // on pin 10
OneWire ds2(6);  // on pin 10
OneWire ds3(7);  // on pin 10

TimedAction checkWaterTemprature = TimedAction(5000,serviceWaterTemprature);
TimedAction checkRoomTemprature = TimedAction(10000,serviceRoomTemprature);
TimedAction checkOutflowTemprature = TimedAction(5000,serviceOutflowTemprature);
TimedAction heartBeat = TimedAction(300000,beat);
TimedAction checkLazorStatus = TimedAction(1000,checkLazor);
TimedAction updateDisplayTimed = TimedAction(1500,updateDisplay);


void setup(void) {
  // initialize inputs/outputs
  // start serial port
  mySerial.begin(9600);
  Serial.begin(9600);
  pinMode(3, OUTPUT);
  pinMode(2, INPUT);
  pinMode(buzzer, OUTPUT);
  digitalWrite(2,HIGH);
  digitalWrite(3,LOW);
  analogWrite(buzzer,0);
  
  // Reset screen
  delay(2000);
  mySerial.print(0x7C, BYTE);
  mySerial.print(4, BYTE);
  mySerial.print(0x7C, BYTE);
  mySerial.print(6, BYTE);
  
  //totalLazordTime = 0;
  
  //EEPROM_writeAnything(0, totalLazordTime);
  
  //delay(100);
  
  Serial.print(EEPROM_readAnything(0, totalLazordTime));
  
  delay(1000);
  mySerial.print(".");
  
  writeToScreen("--NOW  BOOTING----COOLBOT V1.0--");
  Ethernet.begin(mac, ip);
  
  //wdt_enable(WDTO_8S);
  
  delay(1000);
  sendGetRequest("coolBotStartingUp=true");
  checkWaterTemprature.enable();
  checkLazorStatus.enable();
  checkRoomTemprature.enable();
  checkOutflowTemprature.enable();
  heartBeat.enable();
  updateDisplayTimed.enable();
}

void loop(void) {
  
  checkWaterTemprature.check();
  checkLazorStatus.check();
  checkRoomTemprature.check();
  checkOutflowTemprature.check();
  heartBeat.check();
  updateDisplayTimed.check();
  //serviceWaterTemprature();
  //serviceRoomTemprature();
  
}

void updateDisplay(){
  
  char dipMes[50];
  
  
  //sprintf(dipMes, "WTR:%d RM:%d", waterFloat , roomFloat);
  //sprintf(dipMes,"%2d.%01d",oldWaterReading/100,oldWaterReading%100);
  sprintf(dipMes,"WTR:%2d.%01d RM:%2d.%01d",oldWaterReading/100,(oldWaterReading%100)/10, oldRoomReading/100,(oldRoomReading%100)/10);
  //sprintf(dipMes, "%2.2f", oldWaterReading/100);
  
  
  mySerial.print(0xFE,BYTE);
  mySerial.print(0x01,BYTE);
  delay(1);
  mySerial.print(dipMes);
  
  mySerial.print("COOL:");
  if(relay){
    mySerial.print("ON  ");
  }
  else{
    mySerial.print("OFF ");
  }
  
  mySerial.print("LZR:");
  if(!laserStatus){
    mySerial.print("ON");
  }
  else{
    mySerial.print("OFF");
  }
  
  //Serial.println(dipMes);
  
}

void writeToScreen(char* msg){

  mySerial.print(0xFE,BYTE);
  mySerial.print(0x01,BYTE);
  delay(2);
  mySerial.print(msg);

}

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
        totalLazordTime += lazordTime;
        EEPROM_writeAnything(0, totalLazordTime);
        sprintf(buffer1, "lazor=off&timeOn=%ld", totalLazordTime);
        sendGetRequest(buffer1);
      }
    laserStatus = !laserStatus;
    }
  }
}

void serviceWaterTemprature(){
  //Serial.print("Water:");
  int reading = readWater();
  //Serial.print("Water:");
  Serial.println(reading);
  if(reading>2200){
    digitalWrite(relayPin,HIGH);
    if(relay==0){
      relay = 1;
      // **************** SEND COOLING ON **************
      sendGetRequest("cooling=true");
    }
    if(reading>2500){
      analogWrite(buzzer,200);
    }
    else{
      analogWrite(buzzer,0);
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
  //Serial.print("Room:");
  int reading = readRoom();
  //Serial.println(reading);
  if(reading!=oldRoomReading){
    // ****************** SEND NEW TEMPRATURE ***************
    oldRoomReading = reading;
    sprintf(buffer3, "room=%d", reading);
    sendGetRequest(buffer3);
  }

}

void serviceOutflowTemprature(){
  //Serial.print("Room:");
  int reading = readOutflow();
  //Serial.println(reading);
  if(reading!=oldOutflowReading){
    // ****************** SEND NEW TEMPRATURE ***************
    oldOutflowReading = reading;
    sprintf(buffer4, "outflow=%d", reading);
    sendGetRequest(buffer4);
  }

}

void sendGetRequest(char* message){
  Serial.println(message);
  if(client.connect()){
    
    client.print("GET /?");
    client.print(message);
    client.println(" HTTP/1.0");
    client.println();
    client.flush();
    client.stop();
    
    Serial.println("sent data");
    
  }
  else{
    
    Serial.println("ERROR CONNECTING");
    
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

int readOutflow(){
  int HighByte, LowByte, TReading, SignBit, Tc_100, Whole, Fract;
  byte i;
  byte present = 0;
  byte data[12];
  byte addr[8];

  while ( !ds3.search(addr)) {
    //Serial.print("No more addresses.\n");
    ds3.reset_search();
    //return;
  }

  ds3.reset();
  ds3.select(addr);
  ds3.write(0x44,1);         // start conversion, with parasite power on at the end

  
  delay(750);     // maybe 750ms is enough, maybe not
  // we might do a ds.depower() here, but the reset will take care of it.

  present = ds3.reset();
  ds3.select(addr);    
  ds3.write(0xBE);         // Read Scratchpad

  for ( i = 0; i < 9; i++) {           // we need 9 bytes
    data[i] = ds3.read();
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
