#include "Arduino.h"
#include "HT_SSD1306Wire.h" // Broches de l'écran OLED pour WiFi LoRa 32 V4 (SDA_OLED/SCL_OLED/RST_OLED/Vext fournis par le board package Heltec)

// Écran OLED SSD1306 128x64 en I2C matériel (mêmes broches/lib que SimpleDemo, testé fonctionnel)
static SSD1306Wire display(0x3c, 500000, SDA_OLED, SCL_OLED, GEOMETRY_128_64, RST_OLED);

void VextON(void) {
  pinMode(Vext, OUTPUT);
  digitalWrite(Vext, LOW); // LOW = alimentation Vext activée
}

void setup() {
  // Initialiser le port série pour le débogage
  Serial.begin(115200);
  delay(1000);
  Serial.println("HELTEC WiFi LoRa 32 V4 Starting...");

  // Activer l'alimentation Vext (nécessaire pour l'écran OLED)
  VextON();
  delay(100);

  // Initialiser l'écran OLED (gère aussi le reset via RST_OLED)
  display.init();
  display.setContrast(255);
  // display.screenRotate(ANGLE_180_DEGREE); // Retourner l'écran à 180 degrés

  // Effacer l'écran et définir la police
  display.clear();
  display.setFont(ArialMT_Plain_10);
  display.setTextAlignment(TEXT_ALIGN_LEFT);

  // Afficher le message de bienvenue
  display.drawString(0, 0, "HELTEC V4");
  display.drawString(0, 12, "WiFi LoRa 32");
  display.drawString(0, 24, "ESP32-S3 + SX1262");
  display.drawString(0, 36, "Ready!");
  display.display();

  Serial.println("Setup complete!");
}

#define RGB_LED 45 // LED RVB intégrée (WiFi LoRa 32 V4 R8 = GPIO45, pas GPIO38)

void loop() {
  // Faire clignoter la LED RVB intégrée
  static uint8_t color = 0;

  // Cycle de couleurs simple
  switch(color) {
    case 0:
      neopixelWrite(RGB_LED, 255, 0, 0);
      break; // Rouge
    case 1:
      neopixelWrite(RGB_LED, 0, 255, 0);
      break; // Vert
    case 2:
      neopixelWrite(RGB_LED, 0, 0, 255);
      break; // Bleu
  }

  color = (color + 1) % 3;
  Serial.println("loop tick");
  delay(1000);
}
