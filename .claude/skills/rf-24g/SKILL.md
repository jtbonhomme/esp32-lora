---
name: rf-24g
description: Concrete patterns for WiFi and BLE (2.4GHz radio) on Heltec ESP32 boards - STA connection, RSSI reading, NTP time sync over UDP, and a combined BLE UART bridge to a WiFi WebServer. Use when writing/reviewing firmware that touches WiFi.h, BLEDevice/BLEServer, WiFiUdp, WebServer, or ESPmDNS on ESP32.
version: 1.0.0
---

# Heltec ESP32 2.4GHz RF (WiFi / BLE)

Reusable patterns extracted from the HelTec `2.4G_RF` example set (`WiFi_Test`, `TimeNTP_ESP32WiFi`, `BLE_WiFi`). These are Arduino-framework `.ino` examples for Heltec WiFi Kit 32 / Wireless Bridge boards. Use this skill whenever the task involves connecting to WiFi, reading signal strength, syncing time via NTP, running a local WebServer, or bridging BLE <-> WiFi on a Heltec ESP32.

## When to use this skill

- Writing or reviewing code that includes `WiFi.h`, `WiFiUdp.h`, `WebServer.h`, `ESPmDNS.h`, or the `BLEDevice`/`BLEServer`/`BLEUtils`/`BLE2902` headers.
- Connecting an ESP32 to a WiFi access point in station mode.
- Reading/displaying WiFi RSSI (signal strength).
- Syncing the device clock to NTP over UDP.
- Building a BLE peripheral (UART-style service) that relays data to/from WiFi clients.
- Any task combining WiFi + BLE simultaneously on a Heltec board (only certain boards, e.g. Wireless Bridge, support running both radios' example concurrently — see gotchas below).

## 1. WiFi_Test — basic STA connect + RSSI

Demonstrates: connecting to an AP in station mode, blocking-wait for connection, then polling RSSI in the loop with a simple signal-quality classification. Works on WiFi Kit 32 V2 and V3.

```cpp
#include <WiFi.h>

const char* ssid     = "your_SSID";
const char* password = "your_PASSWORD";

void setup() {
  Serial.begin(115200);
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(1000);
    Serial.print(".");
  }
  Serial.print("IP address: ");
  Serial.println(WiFi.localIP());
}

void loop() {
  long rssi = WiFi.RSSI();
  Serial.print("Signal Strength (RSSI): ");
  Serial.print(rssi);
  Serial.println(" dBm");

  if (rssi > -50)      Serial.println("   -> Excellent signal");
  else if (rssi > -60) Serial.println("   -> Good signal");
  else if (rssi > -70) Serial.println("   -> Fair signal");
  else                 Serial.println("   -> Weak signal");

  delay(2000);
}
```

Notes:
- `WiFi.status() != WL_CONNECTED` is the standard blocking-connect poll idiom used across all three examples.
- `WiFi.RSSI()` returns a `long` in dBm; no explicit mode call is needed for a simple STA-only sketch (defaults to STA on first `WiFi.begin`).

## 2. TimeNTP_ESP32WiFi — NTP time sync over raw UDP

Demonstrates: explicit `WIFI_MODE_STA`, `WiFiUDP` for a raw NTP request/response (not a high-level NTP client library), and the `Time` library (`TimeLib.h`, `setSyncProvider`/`setSyncInterval`) to keep a running clock synced periodically.

Setup pattern:
```cpp
#include <TimeLib.h>
#include <WiFi.h>
#include <WiFiUdp.h>

static const char ntpServerName[] = "pool.ntp.org";
const int timeZone = 0; // UTC
WiFiUDP Udp;
unsigned int localPort = 8888;

void setup() {
  Serial.begin(115200);
  WiFi.disconnect();
  WiFi.mode(WIFI_MODE_STA);
  WiFi.begin(ssid, pass);
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }

  Udp.begin(localPort);
  setSyncProvider(getNtpTime);
  setSyncInterval(300); // re-sync every 300s
}
```

Loop only needs to react to `timeStatus() != timeNotSet` and call `now()` — the `Time` library's sync provider handles re-sync in the background:
```cpp
void loop() {
  if (timeStatus() != timeNotSet) {
    if (now() != prevDisplay) {
      prevDisplay = now();
      digitalClockDisplay(); // hour(), minute(), second(), day(), month(), year()
    }
  }
}
```

The raw NTP packet exchange (useful if you don't want the `Time` library dependency, or need the epoch value directly):
```cpp
const int NTP_PACKET_SIZE = 48;
byte packetBuffer[NTP_PACKET_SIZE];

time_t getNtpTime() {
  IPAddress ntpServerIP;
  while (Udp.parsePacket() > 0) ; // flush stale packets first
  WiFi.hostByName(ntpServerName, ntpServerIP);
  sendNTPpacket(ntpServerIP);
  uint32_t beginWait = millis();
  while (millis() - beginWait < 1500) { // 1.5s timeout
    int size = Udp.parsePacket();
    if (size >= NTP_PACKET_SIZE) {
      Udp.read(packetBuffer, NTP_PACKET_SIZE);
      unsigned long secsSince1900 =
          (unsigned long)packetBuffer[40] << 24 |
          (unsigned long)packetBuffer[41] << 16 |
          (unsigned long)packetBuffer[42] << 8  |
          (unsigned long)packetBuffer[43];
      return secsSince1900 - 2208988800UL + timeZone * SECS_PER_HOUR;
    }
  }
  return 0; // 0 = failed, caller must handle
}

void sendNTPpacket(IPAddress &address) {
  memset(packetBuffer, 0, NTP_PACKET_SIZE);
  packetBuffer[0] = 0b11100011; // LI, Version, Mode
  packetBuffer[1] = 0;          // Stratum
  packetBuffer[2] = 6;          // Polling Interval
  packetBuffer[3] = 0xEC;       // Peer Clock Precision
  packetBuffer[12] = 49; packetBuffer[13] = 0x4E;
  packetBuffer[14] = 49; packetBuffer[15] = 52;
  Udp.beginPacket(address, 123); // NTP = port 123
  Udp.write(packetBuffer, NTP_PACKET_SIZE);
  Udp.endPacket();
}
```

Key gotchas:
- Always `while (Udp.parsePacket() > 0);` to discard stale/buffered UDP packets before sending a new NTP request, or you'll read a stale response.
- Use a fixed timeout loop (`millis() - beginWait < 1500`) around `Udp.parsePacket()` — it's non-blocking and returns 0 when nothing is available yet.
- Unix epoch offset from NTP epoch is the constant `2208988800UL` (seconds between 1900 and 1970).

## 3. BLE_WiFi — combined BLE UART bridge + WiFi WebServer

Demonstrates: running BLE server and WiFi WebServer **simultaneously**, bridging data between a BLE UART-style service and an HTTP page. The header explicitly states this dual-radio-at-once pattern is validated only on the **Heltec Wireless Bridge** board — don't assume it works unmodified on every Heltec variant.

Includes used together: `BLEDevice.h`, `BLEServer.h`, `BLEUtils.h`, `BLE2902.h`, `WiFi.h`, `WiFiClient.h`, `WebServer.h`, `ESPmDNS.h`, `Update.h`.

BLE UART service pattern (Nordic UART Service UUIDs — a de facto standard for BLE serial bridges):
```cpp
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer)    { deviceConnected = true; }
    void onDisconnect(BLEServer* pServer) { deviceConnected = false; }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String rxValue = pCharacteristic->getValue();
      // ... handle incoming bytes
    }
};

void setup() {
  BLEDevice::init("UART Service");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);
  pTxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
  pTxCharacteristic->addDescriptor(new BLE2902()); // required for notify to work

  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID_RX, BLECharacteristic::PROPERTY_WRITE);
  pRxCharacteristic->setCallbacks(new MyCallbacks());

  pService->start();
  pServer->getAdvertising()->start();
}
```

Sending a notification to the connected BLE central:
```cpp
pTxCharacteristic->setValue((uint8_t *)data.c_str(), strlen(data.c_str()));
pTxCharacteristic->notify();
```

Re-advertising after disconnect (must be done manually — BLE doesn't auto-resume advertising):
```cpp
if (!deviceConnected && oldDeviceConnected) {
  delay(500); // give the BLE stack time to settle before restarting
  pServer->startAdvertising();
  oldDeviceConnected = deviceConnected;
}
if (deviceConnected && !oldDeviceConnected) {
  oldDeviceConnected = deviceConnected; // connect edge, do first-notify work here
}
```

WiFi side runs a `WebServer` alongside BLE in the same `setup()`/`loop()`:
```cpp
WebServer server(80);

void setup() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);
  if (WiFi.waitForConnectResult() == WL_CONNECTED) {
    server.on("/", ROOT_HTML);
    server.on("/w", ROOT_HTMLW); // separate route to accept POSTed data -> forwarded to BLE TX
    server.begin();
    MDNS.addService("http", "tcp", 80); // advertise via mDNS after server.begin()
  }
}

void loop() {
  server.handleClient(); // must be polled every loop iteration, non-blocking
  // ... BLE connect/disconnect state machine above
}
```

`WiFi.waitForConnectResult()` is a blocking alternative to polling `WiFi.status()` in a `while` loop — returns `WL_CONNECTED` or a failure status directly.

Data POSTed to the WiFi page (`server.hasArg("server")` / `server.arg("server")`) is forwarded straight into the BLE TX characteristic as a WiFi-to-BLE bridge; incoming BLE writes (`onWrite`) are captured into a `String` that the WiFi `/` page later renders — this is the reusable "bridge" shape: **each radio's data handler assigns into a shared variable; the other radio's send path reads that variable next cycle.**

## Board-specific gotchas seen in these examples

- **LED activity indicators**: `BLE_WiFi.ino` drives board LED pins (`WIFI_LED`, `BLE_LED` — Heltec board-variant macros, not raw GPIO numbers) HIGH briefly at boot as a self-test blink, then uses them as live traffic indicators (lit while `BLEDownLink`/`WiFiDownLink` flag is set, auto-off after >1000ms of inactivity via `millis()` comparison). Reuse this "flag + millis() timeout auto-off" pattern for any activity LED instead of using `delay()` in the loop.
- **Dual radio caveat**: the BLE_WiFi example's header comment states this simultaneous WiFi+BLE example is validated specifically for the **Heltec Wireless Bridge** hardware — running both radios concurrently is more resource/timing-sensitive than either alone; don't assume every Heltec board variant handles it the same.
- **`BLE2902` descriptor is required** on any `NOTIFY` characteristic (`pTxCharacteristic->addDescriptor(new BLE2902())`) — without it, `notify()` calls silently do nothing on many BLE clients since the Client Characteristic Configuration Descriptor is what enables notifications.
- **Advertising must be restarted manually** after a BLE disconnect (`pServer->startAdvertising()`); a small `delay(500)` is used in the example to let the BLE stack settle first.
- **`server.handleClient()` must run every loop iteration** with no blocking `delay()` around it, or the WebServer becomes unresponsive — none of the examples put long `delay()` calls in `loop()` once WiFi/BLE/WebServer are active (the RSSI example's `delay(2000)` is fine there because nothing else needs servicing in that loop).
- **NTP UDP requires flushing stale packets** before each request (see `Udp.parsePacket() > 0` discard loop above) — otherwise a leftover buffered response from a previous request can be misread as the current one.
- Credentials (`ssid`/`password`) are hardcoded plaintext `const char*` at the top of every example — fine for demos, but flag this for anything beyond a quick test (should move to NVS/secrets in real firmware).
