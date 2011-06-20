#include <TimedAction.h>
#include <OneWire.h>
#include <EtherShield.h>
#include <stdio.h>

static uint8_t mymac[6] = {
  0x54,0x55,0x58,0x10,0x00,0x25};
static uint8_t myip[4] = {
  172,31,24,55};
// Default gateway. The ip address of your DSL router. It can be set to the same as
// websrvip the case where there is no default GW to access the
// web server (=web server is on the same lan as this host)
static uint8_t gwip[4] = {
  172,31,24,1};

//============================================================================================================
// Pachube declarations
//============================================================================================================
#define PORT 80                   // HTTP

// the etherShield library does not really support sending additional info in a get request
// here we fudge it in the host field to add the API key
// Http header is
// Host: <HOSTNAME>
// X-PachubeApiKey: xxxxxxxx
// User-Agent: Arduino/1.0
// Accept: text/html
#define HOSTNAME "babbage"      // API key
static uint8_t websrvip[4] = {
  172,31,24,101};	// Get pachube ip by DNS call
#define WEBSERVER_VHOST "babbage"
#define HTTPPATH "/?"      // Set your own feed ID here

static uint8_t resend=0;
static int8_t dns_state=0;

EtherShield es=EtherShield();

#define BUFFER_SIZE 550
static uint8_t buf[BUFFER_SIZE+1];

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

// DS18S20 Temperature chip i/o
OneWire ds1(5);  // on pin 10
OneWire ds2(4);  // on pin 10

TimedAction checkWaterTemprature = TimedAction(5000,serviceWaterTemprature);
TimedAction checkRoomTemprature = TimedAction(20000,serviceRoomTemprature);
TimedAction heartBeat = TimedAction(300000,beat);
TimedAction checkLazorStatus = TimedAction(1000,checkLazor);

void beat(){
  sendGetRequest("beat");
}

void checkLazor(){
  int lazor = digitalRead(2);
  //Serial.println(lazor);
  if(lazor!=laserStatus){
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
      sprintf(buffer1, "lazor=off&timeOn=%d", lazordTime);
      sendGetRequest(buffer1);
    }
    laserStatus = !laserStatus;
  }
}

void serviceWaterTemprature(){
  int reading = readWater();
  //Serial.print("Water:");
  //Serial.println(reading);
  if(reading>2200){
    digitalWrite(3,HIGH);
    if(relay==0){
      relay = 1;
      // **************** SEND COOLING ON **************
      sendGetRequest("cooling=true");
    }
  }
  else if(reading<2000){
    digitalWrite(3,LOW);
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
  int reading = readWater();
  //Serial.print("Room:");
  //Serial.println(reading);
  if(reading!=oldRoomReading){
    // ****************** SEND NEW TEMPRATURE ***************
    oldRoomReading = reading;
    sprintf(buffer3, "room=%d", reading);
    sendGetRequest(buffer3);
  }

}

void browserresult_callback(uint8_t statuscode,uint16_t datapos){
  waitingForPing = 0;
  es.ES_packetloop_icmp_tcp(buf,es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf));
  es.ES_packetloop_icmp_tcp(buf,es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf));
  es.ES_packetloop_icmp_tcp(buf,es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf));
  es.ES_packetloop_icmp_tcp(buf,es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf));
  es.ES_packetloop_icmp_tcp(buf,es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf));
  es.ES_packetloop_icmp_tcp(buf,es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf));
  es.ES_packetloop_icmp_tcp(buf,es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf));
  es.ES_packetloop_icmp_tcp(buf,es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf));
  es.ES_packetloop_icmp_tcp(buf,es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf));
  es.ES_packetloop_icmp_tcp(buf,es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf));
}

void sendGetRequest(char* message){
  Serial.println(message);
  es.ES_client_browse_url(PSTR(HTTPPATH), message, PSTR(HOSTNAME), &browserresult_callback); 
  waitingForPing = 1;
  timeOut = 0;
  while((waitingForPing) && (timeOut<99999)){
    es.ES_packetloop_icmp_tcp(buf,es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf));
    ++timeOut;
  }
  //Serial.println(timeOut);
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

  delay(750);     // maybe 750ms is enough, maybe not
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

  //Whole = Tc_100 / 100;  // separate off the whole and fractional portions
  //Fract = Tc_100 % 100;

  /*
  Serial.print("Water:");
   if (SignBit) // If its negative
   {
   Serial.print("-");
   }
   Serial.print(Whole);
   Serial.print(".");
   if (Fract < 10)
   {
   Serial.print("0");
   }
   Serial.print(Fract);
   
   Serial.print("\n");*/
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
  /*
  Whole = Tc_100 / 100;  // separate off the whole and fractional portions
   Fract = Tc_100 % 100;
   
   
   Serial.print("Room:");
   if (SignBit) // If its negative
   {
   Serial.print("-");
   }
   Serial.print(Whole);
   Serial.print(".");
   if (Fract < 10)
   {
   Serial.print("0");
   }
   Serial.print(Fract);
   
   Serial.print("\n");*/
}

void setup(void) {
  // initialize inputs/outputs
  // start serial port
  Serial.begin(9600);
  pinMode(3, OUTPUT);
  pinMode(2, INPUT);
  digitalWrite(2,HIGH);
  digitalWrite(3,LOW);
  // Initialise SPI interface
  es.ES_enc28j60SpiInit();

  // initialize ENC28J60
  es.ES_enc28j60Init(mymac,8);

  //init the ethernet/ip layer:
  es.ES_init_ip_arp_udp_tcp(mymac, myip, PORT);

  // init the web client:
  es.ES_client_set_gwip(gwip);  // e.g internal IP of dsl router
  es.ES_client_set_wwwip(websrvip);
  delay(1000);
  sendGetRequest("coolBotStartingUp");
}

void loop(void) {
  // handle ping and wait for a tcp packet - calling this routine powers the sending and receiving of data
  es.ES_packetloop_icmp_tcp(buf,es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf));

  checkWaterTemprature.check();
  checkLazorStatus.check();
  checkRoomTemprature.check();
  heartBeat.check();
}


