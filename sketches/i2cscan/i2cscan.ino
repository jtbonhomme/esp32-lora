#include <Wire.h>

#define SDA_PIN 17
#define SCL_PIN 18
#define RST_PIN 21
#define VEXT_PIN 40

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("i2c scan, Vext ON, RST held HIGH (no pulse)");

  pinMode(VEXT_PIN, OUTPUT);
  digitalWrite(VEXT_PIN, LOW);
  delay(150);

  pinMode(RST_PIN, OUTPUT);
  digitalWrite(RST_PIN, HIGH);
  delay(50);

  Wire.begin(SDA_PIN, SCL_PIN);
  Wire.setClock(100000);
}

void loop() {
  Serial.println("--- scanning ---");
  int found = 0;
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    uint8_t err = Wire.endTransmission();
    if (err == 0) {
      Serial.print("Found device at 0x");
      Serial.println(addr, HEX);
      found++;
    }
    delay(5);
  }
  Serial.print("total found: ");
  Serial.println(found);
  delay(1500);
}
