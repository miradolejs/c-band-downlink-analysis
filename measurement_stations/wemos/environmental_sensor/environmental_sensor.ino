#include <Wire.h>
#include <ModbusRTU.h>
#include <Adafruit_AHTX0.h>

#define DERE_PIN D6

Adafruit_AHTX0 aht;
ModbusRTU mb;

unsigned long lastTime = 0;
const unsigned long interval = 1000;    //vlhkost a teplota se aktualizují jednou za sekundu

union {
  float f;
  uint16_t reg[2];
} tem;

union {
  float f;
  uint16_t reg[2];
} hum;

void setup() {
  Serial.begin(9600, SERIAL_8N1);   // HW UART pro RS485
  delay(1000);

  
  Wire.begin(D2, D1);               // nastavení I2C pinů (D2 = SDA, D1 = SCL)
  aht.begin();

  mb.begin(&Serial, DERE_PIN);      // řízení DE/RE knihovnou
  mb.slave(1);                      // adresa slave

  mb.addHreg(0);
  mb.addHreg(1);
  mb.addHreg(2);
  mb.addHreg(3);

  sensorDataToRegister();
}

void loop() {

  unsigned long currentTime = millis();

  if(currentTime - lastTime >= interval){
    lastTime = currentTime;

    sensorDataToRegister();
    
  }

  mb.task();
  yield();
}

void sensorDataToRegister(){
  sensors_event_t humidity, temp;

    aht.getEvent(&humidity, &temp);

    tem.f = temp.temperature;
    hum.f = humidity.relative_humidity;


    // uložení do registrů
    mb.Hreg(0, tem.reg[0]);
    mb.Hreg(1, tem.reg[1]);
    mb.Hreg(2, hum.reg[0]);
    mb.Hreg(3, hum.reg[1]);
}