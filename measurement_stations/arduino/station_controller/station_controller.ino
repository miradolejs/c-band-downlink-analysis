#include <TinyGPS++.h>
#include <SoftwareSerial.h>


static const int RXPin = 4, TXPin = 3;
static const uint32_t GPSBaud = 9600;

//RS485/čidlo

#include <ModbusMaster.h>
#include <SoftwareSerial.h>

SoftwareSerial rs485(10, 13); // RX, TX

#define RS485_DIR 11

ModbusMaster node;

void preTransmission() {
  digitalWrite(RS485_DIR, HIGH);
}

void postTransmission() {
  digitalWrite(RS485_DIR, LOW);
}

//relé
#define RELE 2

// The TinyGPS++ object
TinyGPSPlus gps;

// The serial connection to the GPS device
SoftwareSerial ss(RXPin, TXPin);

enum GpsDateTimePart {
GPS_YEAR,
GPS_MONTH,
GPS_DAY,
GPS_HOUR,
GPS_MINUTE,
GPS_SECOND
};

static int getGpsDateTimePart(GpsDateTimePart part);
static bool isCzechSummerTime(int year, int month, int day, int hourUtc);
static int lastSundayOfMonth(int year, int month);
static int dayOfWeek(int year, int month, int day);
static void addHoursToDateTime(int &year, int &month, int &day, int &hour, int hoursToAdd);
static int daysInMonth(int year, int month);
static bool isLeapYear(int year);

// Časové značky

unsigned long lastTimeRele = 0;
const unsigned long intervalRele = 5500; // 5,5 sekundy
bool endRele = false;

unsigned long lastTimeTemHum = 0;
const unsigned long intervalTemHum = 2000; // 2 sekundy


//void setup()
void setup(){

  //GPS
  Serial.begin(115200);
  ss.begin(GPSBaud);
  ss.listen();
  //Serial.println(F("GPS cesky cas"));
  //Serial.print(F("TinyGPS++ v. "));
  //Serial.println(TinyGPSPlus::libraryVersion());

  //RELÉ
  pinMode(RELE, OUTPUT);
  digitalWrite(RELE, LOW);

  //RS485 převodník/teplotní čislo
  rs485.begin(9600);

  pinMode(RS485_DIR, OUTPUT);
  digitalWrite(RS485_DIR, LOW);

  node.begin(1, rs485);

  node.preTransmission(preTransmission);
  node.postTransmission(postTransmission);
}

//RS485 převodník/čidlo

bool getTempHumidity(float &t, float &h) {
  uint16_t data[4];
    
  rs485.listen();

  delay(10);

  uint8_t result = node.readHoldingRegisters(0, 4);

  ss.listen();

  if (result == node.ku8MBSuccess) {
    data[0] = node.getResponseBuffer(0);
    data[1] = node.getResponseBuffer(1);
    data[2] = node.getResponseBuffer(2);
    data[3] = node.getResponseBuffer(3);

    union {                                      // složení zpět na float,protože jak teplota tak i vlhkost jsou hodnoty uložené ve float proměnné
      float f;
      uint16_t reg[2];
    } tem;

    union {
      float f;
      uint16_t reg[2];
    } hum;

    tem.reg[0] = data[0];
    tem.reg[1] = data[1];

    hum.reg[0] = data[2];
    hum.reg[1] = data[3];

    t = tem.f;
    h = hum.f;

    return true;
  }

  return false;
}


void loop(){

  processGPS();  

  //rs485/čidlo
  float t, h;

  unsigned long currentTime = millis();

  if (endRele == true){
    if (currentTime - lastTimeRele >= intervalRele){
      digitalWrite(RELE, LOW);
      endRele = false;
      //Serial.println("Relé vypnuto");
    }
  }

  if(currentTime - lastTimeTemHum >= intervalTemHum){

    lastTimeTemHum = currentTime;

    if (getTempHumidity(t, h)) {
      Serial.print("ENV:T:");
      Serial.print(t);

      Serial.print(",H:");
      Serial.println(h);
    } else {
      Serial.println("Modbus chyba");
    }

  }

  processGPS();

  //čas
  static int lastPrintedSecond = -1;
  static unsigned long lastMissingTimePrint = 0;

  smartDelay(5);

  int second = getGpsDateTimePart(GPS_SECOND);

  if (second == -1) {

    if (millis() - lastMissingTimePrint >= 1000) {
      lastMissingTimePrint = millis();
      Serial.println(F("Cesky cas jeste neni dostupny"));
    }

    if (millis() > 5000 && gps.charsProcessed() < 10) Serial.println(F("No GPS data received: check wiring"));

    return;
  }

  if (second == lastPrintedSecond) return;

  lastPrintedSecond = second;

  //Serial.println(second);


  if (second == 59){
    digitalWrite(RELE, HIGH);
    endRele = true;
    lastTimeRele = millis();
    //Serial.println("Relé zapnuto");
  }

  
}

void processGPS() {

    ss.listen();

    while (ss.available()) {
        gps.encode(ss.read());
    }
}

// This custom version of delay() ensures that the gps object
// is being "fed".
static void smartDelay(unsigned long ms) {
  unsigned long start = millis();
  do {
  while (ss.available())
  gps.encode(ss.read());
  } while (millis() - start < ms);
}

static int getGpsDateTimePart(GpsDateTimePart part) {
  if (!gps.date.isValid() || !gps.time.isValid())
    return -1;

  int year = gps.date.year();
  int month = gps.date.month();
  int day = gps.date.day();
  int hour = gps.time.hour();
  int minute = gps.time.minute();
  int second = gps.time.second();
  int offsetHours = isCzechSummerTime(year, month, day, hour) ? 2 : 1;

  addHoursToDateTime(year, month, day, hour, offsetHours);

  switch (part) {
    case GPS_YEAR:
    return year;
  case GPS_MONTH:
    return month;
  case GPS_DAY:
    return day;
  case GPS_HOUR:
    return hour;
  case GPS_MINUTE:
    return minute;
  case GPS_SECOND:
    return second;
  default:
    return -1;
  }
}

static bool isCzechSummerTime(int year, int month, int day, int hourUtc) {
  if (month < 3 || month > 10)
    return false;
  if (month > 3 && month < 10)
    return true;

  int lastSunday = lastSundayOfMonth(year, month);

  if (month == 3) {
    if (day > lastSunday)
      return true;
    if (day < lastSunday)
      return false;
  return hourUtc >= 1;
  }

  if (day < lastSunday)
    return true;
  if (day > lastSunday)
    return false;
  return hourUtc < 1;
}

static int lastSundayOfMonth(int year, int month) {
  int lastDay = daysInMonth(year, month);
  int weekday = dayOfWeek(year, month, lastDay);
  return lastDay - weekday;
}

static int dayOfWeek(int year, int month, int day) {
  if (month < 3) {
    month += 12;
    year--;
  }

  int k = year % 100;
  int j = year / 100;
  int h = (day + (13 * (month + 1)) / 5 + k + k / 4 + j / 4 + 5 * j) % 7;
  return (h + 6) % 7;
}

static void addHoursToDateTime(int &year, int &month, int &day, int &hour, int hoursToAdd) {
  hour += hoursToAdd;

  while (hour >= 24) {
    hour -= 24;
    day++;

    if (day > daysInMonth(year, month)) {
      day = 1;
      month++;

      if (month > 12) {
        month = 1;
        year++;
      }
    }
  }
}

static int daysInMonth(int year, int month) {
  switch (month) {
    case 2:
      return isLeapYear(year) ? 29 : 28;
    case 4:
    case 6:
    case 9:
    case 11:
      return 30;
    default:
      return 31;
  }
}

static bool isLeapYear(int year) {
  return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
}
