/* BLE peripheral, WiFi LoRa 32 V4 (ESP32-S3)
 *
 * Function:
 * 1. Advertises a BLE peripheral under a configurable device name.
 * 2. Accepts a connection from a single BLE central (e.g. the companion
 *    iOS app), exposing a Nordic UART-style service (RX write / TX notify).
 * 3. When the central writes a message, it is shown on the OLED screen
 *    together with the name of the sender.
 *
 * Message format written to the RX characteristic (UTF-8 text):
 *   "<sender name>|<message text>"
 * If no "|" separator is present, the whole payload is treated as the
 * message body and the sender is shown as "Unknown".
 *
 * Device name:
 *   Defaults to BLE_DEVICE_NAME below. Override at compile time with
 *   -DBLE_DEVICE_NAME='"MyDeviceName"' (the root Makefile wires this up
 *   to a BLE_NAME make variable / environment variable).
 */

#include "Arduino.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "HT_SSD1306Wire.h" // Écran OLED SSD1306 128x64 en I2C matériel (broches fournies par le board package Heltec)

#ifndef BLE_DEVICE_NAME
#define BLE_DEVICE_NAME "Heltec-BLE"
#endif

// Nordic UART Service UUIDs (de facto standard for a BLE serial bridge)
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E" // central -> peripheral (write)
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E" // peripheral -> central (notify)

static SSD1306Wire display(0x3c, 500000, SDA_OLED, SCL_OLED, GEOMETRY_128_64, RST_OLED);

BLEServer *pServer = nullptr;
BLECharacteristic *pTxCharacteristic = nullptr;
bool deviceConnected = false;
bool oldDeviceConnected = false;

void VextON(void) {
  pinMode(Vext, OUTPUT);
  digitalWrite(Vext, LOW); // LOW = alimentation Vext activée
}

void showStatus(const String &line1, const String &line2) {
  display.clear();
  display.setFont(ArialMT_Plain_10);
  display.setTextAlignment(TEXT_ALIGN_LEFT);
  display.drawString(0, 0, "BLE: " BLE_DEVICE_NAME);
  display.drawString(0, 14, line1);
  display.drawStringMaxWidth(0, 28, 128, line2);
  display.display();
}

void showMessage(const String &sender, const String &message) {
  display.clear();
  display.setFont(ArialMT_Plain_10);
  display.setTextAlignment(TEXT_ALIGN_LEFT);
  display.drawString(0, 0, "From: " + sender);
  display.drawStringMaxWidth(0, 14, 128, message);
  display.display();
  Serial.printf("[BLE] %s: %s\n", sender.c_str(), message.c_str());
}

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    deviceConnected = true;
    Serial.println("[BLE] central connected");
  }
  void onDisconnect(BLEServer *server) override {
    deviceConnected = false;
    Serial.println("[BLE] central disconnected");
  }
};

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    String value = characteristic->getValue();
    if (value.length() == 0) return;

    String sender = "Unknown";
    String message = value;
    int sep = value.indexOf('|');
    if (sep >= 0) {
      sender = value.substring(0, sep);
      message = value.substring(sep + 1);
    }
    showMessage(sender, message);

    if (pTxCharacteristic) {
      String ack = "ACK:" + message;
      pTxCharacteristic->setValue((uint8_t *)ack.c_str(), ack.length());
      pTxCharacteristic->notify();
    }
  }
};

void setup() {
  Serial.begin(115200);
  delay(1000); // laisser le temps à l'hôte USB CDC de se connecter avant les premiers logs
  Serial.println("Heltec BLE starting...");

  VextON();
  delay(100);
  display.init();
  display.setContrast(255);
  showStatus("Advertising...", "");

  BLEDevice::init(BLE_DEVICE_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  pTxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
  pTxCharacteristic->addDescriptor(new BLE2902()); // requis pour que notify() fonctionne

  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_RX,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  pRxCharacteristic->setCallbacks(new RxCallbacks());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.printf("[BLE] advertising as \"%s\"\n", BLE_DEVICE_NAME);
}

void loop() {
  // Reprendre l'annonce après une déconnexion (non automatique côté BLE)
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
    showStatus("Connected", "waiting for message...");
  }
  if (!deviceConnected && oldDeviceConnected) {
    delay(500); // laisser la pile BLE se stabiliser avant de relancer l'annonce
    pServer->startAdvertising();
    oldDeviceConnected = deviceConnected;
    showStatus("Advertising...", "");
  }
  delay(50);
}
