---
name: lorawan
description: Concrete patterns for network-server-joined LoRaWAN firmware on Heltec ESP32 boards - OTAA/ABP join (DevEui/AppEui/AppKey), the DEVICE_STATE_INIT/JOIN/SEND/CYCLE/SLEEP state machine, uplink payload framing, downlink callbacks, multicast, and Class A/C behavior against a network server (TTN etc). Distinct from raw point-to-point LoRa (LoRa.h) - use this skill when the code targets a LoRaWAN network server, not direct radio-to-radio LoRa.
version: 1.0.0
---

# Heltec ESP32 LoRaWAN (network-server-joined)

Reusable patterns extracted from the HelTec `Heltec_ESP32` `examples/LoRaWAN` set (14 `.ino` sketches) plus the shared library they all depend on: `src/LoRaWan_APP.h` / `LoRaWan_APP.cpp` (the `LoRaWanClass` / global `LoRaWAN` object and the LoRaMAC stack glue) and `src/loramac/Commissioning.h`. These are Arduino-framework sketches for Heltec WiFi LoRa 32 boards joining a real LoRaWAN network server (e.g. The Things Network). This is **not** the raw point-to-point `LoRa.h` API — if the code isn't joining a network server (no DevEui/AppKey, no `LoRaWAN.join()`), this skill doesn't apply.

## When to use this skill

- Writing or reviewing code that includes `LoRaWan_APP.h`, references `deviceState`, `LoRaWAN.init/join/send/cycle/sleep`, or the `DEVICE_STATE_*` enum.
- Configuring OTAA (DevEui/AppEui/AppKey) or ABP (DevAddr/NwkSKey/AppSKey) join credentials for a Heltec board.
- Building an uplink payload (`appData`/`appDataSize`) to send to a LoRaWAN network server (TTN, ChirpStack, etc).
- Handling downlink data or ACKs sent from the network server back to the device.
- Setting up multicast, Class A vs Class C behavior, ADR, confirmed/unconfirmed uplinks, or a LoRaWAN duty cycle.
- Anything mentioning TTN, DevEUI, AppEUI/JoinEUI, AppKey, NwkSKey/AppSKey, or a LoRaWAN region (EU868/US915/AS923/...).

## 1. The shared app skeleton (state machine)

Every example follows the exact same `switch(deviceState)` shape, driven by the `eDeviceState_LoraWan` enum declared in `LoRaWan_APP.h`:

```cpp
enum eDeviceState_LoraWan
{
    DEVICE_STATE_INIT,
    DEVICE_STATE_JOIN,
    DEVICE_STATE_SEND,
    DEVICE_STATE_CYCLE,
    DEVICE_STATE_SLEEP
};
```

Minimal real skeleton (from `LoRaWan.ino`, the plain reference example):

```cpp
#include "LoRaWan_APP.h"

/* OTAA para*/
uint8_t devEui[] = { 0x70, 0xB3, 0xD5, 0x7E, 0xD0, 0x06, 0x53, 0xC8 };
uint8_t appEui[] = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
uint8_t appKey[] = { 0x74, 0xD6, 0x6E, 0x63, 0x45, 0x82, 0x48, 0x27, 0xFE, 0xC5, 0xB7, 0x70, 0xBA, 0x2B, 0x50, 0x45 };

/* ABP para*/
uint8_t nwkSKey[] = { /* 16 bytes */ };
uint8_t appSKey[] = { /* 16 bytes */ };
uint32_t devAddr =  ( uint32_t )0x007e6ae1;

uint16_t userChannelsMask[6]={ 0x00FF,0x0000,0x0000,0x0000,0x0000,0x0000 };
LoRaMacRegion_t loraWanRegion = ACTIVE_REGION;      // set via Arduino IDE Tools menu
DeviceClass_t  loraWanClass = CLASS_A;              // CLASS_A or CLASS_C
uint32_t appTxDutyCycle = 15000;                    // ms between uplinks
bool overTheAirActivation = true;                   // true = OTAA, false = ABP
bool loraWanAdr = true;
bool isTxConfirmed = true;
uint8_t appPort = 2;
uint8_t confirmedNbTrials = 4;

static void prepareTxFrame( uint8_t port )
{
    appDataSize = 4;             // <= LORAWAN_APP_DATA_MAX_SIZE (255, see Commissioning.h)
    appData[0] = 0x00;
    appData[1] = 0x01;
    appData[2] = 0x02;
    appData[3] = 0x03;
}

void setup() {
  Serial.begin(115200);
  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);
}

void loop()
{
  switch( deviceState )
  {
    case DEVICE_STATE_INIT:
    {
#if(LORAWAN_DEVEUI_AUTO)
      LoRaWAN.generateDeveuiByChipID();   // derive DevEui from chip ID instead of the hardcoded array
#endif
      LoRaWAN.init(loraWanClass, loraWanRegion);
      LoRaWAN.setDefaultDR(3);            // sets both the join DR and the DR used when ADR is off
      break;
    }
    case DEVICE_STATE_JOIN:
    {
      LoRaWAN.join();
      break;
    }
    case DEVICE_STATE_SEND:
    {
      prepareTxFrame( appPort );
      LoRaWAN.send();
      deviceState = DEVICE_STATE_CYCLE;
      break;
    }
    case DEVICE_STATE_CYCLE:
    {
      txDutyCycleTime = appTxDutyCycle + randr( -APP_TX_DUTYCYCLE_RND, APP_TX_DUTYCYCLE_RND );
      LoRaWAN.cycle(txDutyCycleTime);
      deviceState = DEVICE_STATE_SLEEP;
      break;
    }
    case DEVICE_STATE_SLEEP:
    {
      LoRaWAN.sleep(loraWanClass);
      break;
    }
    default:
    {
      deviceState = DEVICE_STATE_INIT;
      break;
    }
  }
}
```

`LoRaWAN` is a global `LoRaWanClass` instance (declared `extern LoRaWanClass LoRaWAN;` in `LoRaWan_APP.h`). Its methods (`init`, `join`, `send`, `cycle`, `sleep`, `setDefaultDR`, `generateDeveuiByChipID`, and on OLED-equipped boards `displayJoining/displayJoined/displaySending/displayAck/displayMcuInit`) are the entire public API used by every sketch — none of the examples call the underlying LoRaMAC layer directly except for special cases (multicast setup, `MLME_DEVICE_TIME` request — see below).

`init()` internally sets `deviceState = DEVICE_STATE_JOIN` once the LoRaMAC stack is initialized, so `setup()` never sets `deviceState` itself in most examples — the state machine bootstraps from `DEVICE_STATE_INIT` (its default value) automatically. `appData`/`appDataSize` are declared `RTC_DATA_ATTR` in the library (survive deep sleep / some reset types), sized `appData[LORAWAN_APP_DATA_MAX_SIZE]`.

`join()`'s internal branch (worth knowing, not something you normally re-implement):
- **OTAA** (`overTheAirActivation == true`): builds an `MlmeReq_t{ Type = MLME_JOIN, Req.Join.{DevEui,AppEui,AppKey}, NbTrials = 1 }` and calls `LoRaMacMlmeRequest()`; on success `deviceState` goes to `DEVICE_STATE_SLEEP` (waits for the join to complete asynchronously), on failure to `DEVICE_STATE_CYCLE` (retry later).
- **ABP** (`overTheAirActivation == false`): sets `MIB_NET_ID`, `MIB_DEV_ADDR`, `MIB_NWK_SKEY`, `MIB_APP_SKEY`, `MIB_NETWORK_JOINED = true` directly via `LoRaMacMibSetRequestConfirm()` and jumps straight to `DEVICE_STATE_SEND` — no join handshake needed since ABP has pre-shared session keys.

## 2. OTAA/ABP credential configuration

Credentials are **not** stored in `Commissioning.h`. That header (`src/loramac/Commissioning.h`) only defines network-wide constants that rarely change:

```cpp
#define LORAWAN_APP_DATA_MAX_SIZE   255
#define LORAWAN_PUBLIC_NETWORK      true
#define LORAWAN_NETWORK_ID          ( uint32_t )0
```

The actual per-device secrets are plain global arrays declared at the top of **every** `.ino` sketch (matching the `extern` declarations in `LoRaWan_APP.h`), hardcoded in plaintext:

```cpp
/* OTAA para*/
uint8_t devEui[] = { 0x22, 0x32, 0x33, 0x00, 0x00, 0x88, 0x88, 0x02 };  // 8 bytes
uint8_t appEui[] = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };  // 8 bytes, "AppEUI"/"JoinEUI"
uint8_t appKey[] = { 0x88, 0x88, ... };                                  // 16 bytes

/* ABP para*/
uint8_t nwkSKey[] = { ... };   // 16 bytes
uint8_t appSKey[] = { ... };   // 16 bytes
uint32_t devAddr = (uint32_t)0x007e6ae1;
```

`overTheAirActivation` (bool) picks which credential set `join()` actually uses; both sets are always declared regardless (unused set is simply ignored). To auto-derive the DevEui from the chip's unique ID instead of hardcoding it, guard with `#if(LORAWAN_DEVEUI_AUTO)` and call `LoRaWAN.generateDeveuiByChipID()` in `DEVICE_STATE_INIT` before `LoRaWAN.init()` — every example does this even when it also hardcodes a `devEui[]` fallback array.

`loraWanRegion = ACTIVE_REGION` — the region/frequency plan is picked in the **Arduino IDE Tools menu** (or the equivalent PlatformIO build flag), not in the sketch; `ACTIVE_REGION` is a macro that resolves to one of `LORAMAC_REGION_EU868`, `_US915`, `_AS923`, `_AU915`, `_CN470`, `_KR920`, `_IN865`, `_RU864`, etc. Get this wrong and the device will never join (wrong channel plan for your gateway/network server).

## 3. What each example demonstrates

| Example | Demonstrates |
|---|---|
| `LoRaWan` | Minimal reference skeleton — the canonical state machine, no sensor. |
| `LoRaWAN_GHTV3_Battery` | GXHTC temp/humidity sensor uplink + ADC battery-voltage reading (`analogRead`/`analogReadMilliVolts`), ad hoc TLV payload framing. |
| `LoRaWAN_GHTV3_Uplink` | Same GXHTC temp/humidity sensor uplink, simpler payload, no ADC. |
| `LoRaWAN_Hallsensor_Door_Detection` | Interrupt-driven Hall sensor (door open/close pulse counting) with debounce; payload only rebuilt once per measurement window inside `prepareTxFrame()`. |
| `LoRaWan_Monitor_heartrate` | MAX30102 pulse oximeter (heart rate + SpO2) uplink via the `PulseOximeter` library. |
| `LoRaWanDownlinkDatahandle` | Overrides `downLinkDataHandle()` to print received downlink bytes and drive the board RGB LED from downlink payload. |
| `LoRaWanGPSLocation` | TinyGPS++ over UART, blocking wait-for-fix, uploads raw lat/lon floats; ships a TTN payload-decoder (`TTNDecoder.js`). |
| `LoRaWanGPSTime` | Same GPS pattern but uploads GPS time-of-day fields instead of location; also ships a `TTNDecoder.js`. |
| `LoRaWanGPSTime_lora_v4` | GPS time+location combined, with boot-count-aware fix timeout (longer timeout on cold boot) and `RTC_DATA_ATTR` state across deep sleep. |
| `LoRaWanInterrupt` | Class A **and** Class C low-power interrupt wake-up: a GPIO interrupt can force an immediate `DEVICE_STATE_SEND`, plus `esp_sleep_enable_ext0_wakeup`/`esp_deep_sleep_enable_gpio_wakeup` deep-sleep wake configuration. |
| `LoRaWanMulticast` | Joins a LoRaWAN multicast group via `LoRaMacMulticastChannelLink()` in `setup()`, in addition to the normal unicast join/send flow. |
| `LoRaWanOLED` | Drives the board's OLED via `LoRaWAN.displayMcuInit/displayJoining/displaySending/displayAck` status calls inline in the state machine (OLED-equipped boards only). |
| `LoRaWanTimeReq` | Issues an explicit `MLME_DEVICE_TIME` MAC request piggybacked on the next uplink to pull network time; implements the `dev_time_updated()` callback. |
| `LoRaWanWiFi` | Class C node bridging LoRaWAN uplink/downlink to a local WiFi `WebServer` page (view + inject data from a browser). |

## 4. Downlink handling (callback pattern)

Downlink is delivered through two **weak** C functions declared in `LoRaWan_APP.h` and defined (weakly, as no-ops/log-only) in `LoRaWan_APP.cpp`. A sketch overrides them simply by defining a function with the matching signature — no registration call needed:

```cpp
extern "C" void downLinkAckHandle();
extern "C" void downLinkDataHandle(McpsIndication_t *mcpsIndication);
```

Both are invoked from the library's internal `McpsIndication()` callback: `downLinkAckHandle()` when `mcpsIndication->AckReceived` is true (i.e. the network ACKed a confirmed uplink), `downLinkDataHandle()` when `mcpsIndication->RxData` is true (the server sent an actual downlink payload). Example override (`LoRaWanDownlinkDatahandle.ino`):

```cpp
void downLinkDataHandle(McpsIndication_t *mcpsIndication)
{
  Serial.printf("+REV DATA:%s,RXSIZE %d,PORT %d\r\n",
      mcpsIndication->RxSlot ? "RXWIN2" : "RXWIN1",
      mcpsIndication->BufferSize, mcpsIndication->Port);
  for (uint8_t i = 0; i < mcpsIndication->BufferSize; i++)
    Serial.printf("%02X", mcpsIndication->Buffer[i]);
  Serial.println();

  uint32_t color = mcpsIndication->Buffer[0]<<16 | mcpsIndication->Buffer[1]<<8 | mcpsIndication->Buffer[2];
#if(LoraWan_RGB==1)
  turnOnRGB(color, 5000);
  turnOffRGB();
#endif
}
```

`mcpsIndication->Buffer`/`BufferSize`/`Port`/`RxSlot` (RX1 vs RX2 window) are the fields you read. `LoRaWanWiFi.ino` uses the same callback to forward downlink bytes into a `String` rendered on a WebServer page — the reusable shape is "downlink handler writes into a shared variable; something else (display, webpage, LED) reads it next iteration/tick", the same pattern as the `rf-24g` skill's BLE-WiFi bridge.

There's also a `dev_time_updated()` weak callback fired once a `MLME_DEVICE_TIME` request resolves (see `LoRaWanTimeReq.ino`):

```cpp
RTC_DATA_ATTR bool timeReq = true;

void dev_time_updated() { printf("Once device time updated, this function run\r\n"); }

// inside DEVICE_STATE_SEND, before prepareTxFrame():
if (timeReq) {
  timeReq = false;
  MlmeReq_t mlmeReq;
  mlmeReq.Type = MLME_DEVICE_TIME;
  LoRaMacMlmeRequest(&mlmeReq);   // piggybacks a time request on the next uplink
}
```

## 5. Multicast

`LoRaWanMulticast.ino` links a multicast channel once in `setup()`, before the normal state machine starts sending — this is additive to (not a replacement for) the regular unicast OTAA/ABP join:

```cpp
MulticastParams_t mult1;
uint8_t mulNwkSKey[]={...};   // 16 bytes, multicast group session key
uint8_t mulAppSKey[]={...};   // 16 bytes
uint32_t multicastAddress = 0x00638f9e;

mult1.Address = multicastAddress;
for (int i = 0; i < 16; i++) {
  mult1.NwkSKey[i] = mulNwkSKey[i];
  mult1.AppSKey[i] = mulAppSKey[i];
}
LoRaMacMulticastChannelLink(&mult1);
```

## 6. Class A vs Class C / interrupt-driven send

`loraWanClass` selects `CLASS_A` (default, RX windows only after a TX — lowest power) or `CLASS_C` (continuously listening — higher power, lower downlink latency; used by `LoRaWanOLED`/`LoRaWanWiFi` for responsive UIs). `LoRaWanInterrupt.ino` shows Class-C-specific interrupt wiring:

```cpp
void keyDown()
{
  delay(10);
  if (digitalRead(INT_PIN) == 0 && IsLoRaMacNetworkJoined)
    deviceState = DEVICE_STATE_SEND;   // force an immediate send, bypassing the duty-cycle timer
}

void setup() {
  ...
  if (loraWanClass == CLASS_C) {
    pinMode(INT_PIN, INPUT);
    attachInterrupt(INT_PIN, keyDown, FALLING);
  }
  deviceState = DEVICE_STATE_INIT;
}
```

and Class-A-specific deep-sleep GPIO wakeup, set right before `LoRaWAN.sleep()`:

```cpp
case DEVICE_STATE_SLEEP:
{
  if (loraWanClass == CLASS_A) {
#ifdef WIRELESS_MINI_SHELL
    esp_deep_sleep_enable_gpio_wakeup(1<<INT_PIN, ESP_GPIO_WAKEUP_GPIO_LOW);
#else
    esp_sleep_enable_ext0_wakeup((gpio_num_t)INT_PIN, 0);
#endif
  }
  LoRaWAN.sleep(loraWanClass);
  break;
}
```

`IsLoRaMacNetworkJoined` is a library global you can check before forcing a send — don't send before the device has actually joined.

## 7. Payload framing conventions

The examples don't use a standard codec (no CayenneLPP library call visible) — payloads are hand-packed raw bytes, and each sketch defines its own layout:

- **Simple placeholder**: `appDataSize = 4; appData[0..3] = 0x00,0x01,0x02,0x03;` (most skeleton examples).
- **Raw little-endian float**: `puc = (unsigned char*)(&floatVar); appData[n++] = puc[0..3];` — used for GPS lat/lon, heart rate, SpO2, temperature, humidity. The paired TTN payload decoders (`TTNDecoder.js` in the GPS examples) confirm the on-the-wire format is little-endian IEEE-754 float, decoded with a manual bit-twiddling `bytesToFloat()` (no `Float32Array`/DataView used, presumably for old TTN v2 decoder sandbox compatibility):
  ```js
  function bytesToFloat(by) {
      var bits = by[3]<<24 | by[2]<<16 | by[1]<<8 | by[0];
      var sign = (bits>>>31 === 0) ? 1.0 : -1.0;
      var e = bits>>>23 & 0xff;
      var m = (e === 0) ? (bits & 0x7fffff)<<1 : (bits & 0x7fffff) | 0x800000;
      return sign * m * Math.pow(2, e - 150);
  }
  function Decoder(bytes, port) {
    var decoded = {}, i = 0;
    decoded.latitude  = bytesToFloat(bytes.slice(i, i+=4));
    decoded.longitude = bytesToFloat(bytes.slice(i, i+=4));
    return decoded;
  }
  ```
- **Ad hoc TLV-ish scheme** (`LoRaWAN_GHTV3_*`): a leading `parentID`/sensor-length byte pair, then a byte whose upper nibble is a "subID" and lower nibble a decimal-place count, followed by the raw 4-byte float — this is a vendor-specific convention for their sensor dashboard, not a LoRaWAN or TTN standard; don't assume a network server understands it without the matching decoder.

When writing a new payload, keep it simple (raw fixed-width fields, documented byte offsets) and write/update the matching TTN/ChirpStack payload decoder alongside the firmware change.

## Gotchas seen in these examples

- **Confirmed vs unconfirmed uplinks**: `isTxConfirmed` (bool) + `confirmedNbTrials` control retry behavior. Every example carries this exact comment block about the retry/datarate-backoff table (LoRaWAN spec v1.0.2 §18.4) — worth remembering when confirmed uplinks seem to "lose" data rate over failed retries:
  ```
  Transmission nb | Data Rate
  1 (first)       | DR
  2               | DR
  3               | max(DR-1,0)
  4               | max(DR-1,0)
  5               | max(DR-2,0)
  6               | max(DR-2,0)
  7               | max(DR-3,0)
  8               | max(DR-3,0)
  ```
  If `confirmedNbTrials` is 1 or 2, the MAC will *not* decrease the datarate on failed ACK.
- **Region/frequency plan is a build-time choice**, not a sketch variable — `loraWanRegion = ACTIVE_REGION` just reads whatever the Arduino IDE Tools menu (or build flag) selected. A device that never joins is very often a region mismatch against the gateway/network server, not a key problem.
- **`LoRaWAN.setDefaultDR(3)` sets both the join datarate and the fallback DR used when ADR is disabled** — nearly every example calls this immediately after `LoRaWAN.init()` with the comment "both set join DR and DR when ADR off"; omit it and you get the stack's built-in default, which may not match your gateway's expected join DR.
- **`appDataSize` is capped at `LORAWAN_APP_DATA_MAX_SIZE` (255, from `Commissioning.h`)**, but the comment in every `prepareTxFrame()` warns: if AT-command mode is enabled, don't change that constant (can hang/fail the system); if AT is disabled, the real ceiling is the region+datarate max payload (e.g. see `MaxPayloadOfDatarateCN470` for CN470) — a payload that's fine at DR3 can silently fail to send at a lower DR.
- **Duty cycle jitter is intentional**: `txDutyCycleTime = appTxDutyCycle + randr(-APP_TX_DUTYCYCLE_RND, APP_TX_DUTYCYCLE_RND)` (jitter window ±1000ms via `APP_TX_DUTYCYCLE_RND`) — don't remove the `randr()` call, it avoids synchronized uplink collisions across many devices with the same duty cycle.
- **`appData`/`appDataSize` are `RTC_DATA_ATTR`** — they (and other RTC_DATA_ATTR globals like `RTC_DATA_ATTR bool firstrun` in `LoRaWanOLED.ino` or `RTC_DATA_ATTR int bootCount` in `LoRaWanGPSTime_lora_v4.ino`) survive deep sleep and most resets, which is how examples avoid redoing one-time init (e.g. OLED splash) or use "cold boot vs warm wake" logic (longer GPS fix timeout only on `bootCount==0`).
- **GPS examples busy-wait for a fix inside `prepareTxFrame()`** with a hardcoded timeout (10-120s depending on example) rather than doing it asynchronously — this blocks the whole state machine (and the duty cycle) until fix-or-timeout; fine for a demo, but means `appTxDutyCycle` is not the real uplink interval when GPS is slow to fix.
- **Vext / VGNSS_CTRL power-gating pins**: GPS and some sensor examples explicitly power the peripheral up (`digitalWrite(Vext, HIGH)` or `VGNSS_CTRL`) before reading and back down after, to save power between duty cycle wakeups — Serial1 pins/baud for the GPS UART differ per board variant across these examples (e.g. `33/34 @115200` vs `39/38 @9600`), so don't copy pin numbers across board variants without checking.
- **`LoRaWAN.displayJoining/displaySending/displayAck/displayMcuInit`** only exist on boards with a built-in OLED (guarded by `#if defined(WIFI_LORA_32_V3)||...` in `LoRaWan_APP.h`) — calling them unconditionally will fail to compile for boards without a display.
- **The heartrate example (`LoRaWan_Monitor_heartrate.ino`) has an inconsistent state machine**: its `DEVICE_STATE_INIT` case calls `LoRaWAN.join()` instead of `LoRaWAN.init()` (and `LoRaWAN.init()`/`setDefaultDR()` are instead called once in `setup()`) — this deviates from every other example's skeleton; treat it as a one-off, not the pattern to copy.
- **Credentials are hardcoded plaintext arrays** in every example (fine for demos/dev boards) — for real firmware, keep them out of source control (NVS/provisioning) rather than copying the literal byte arrays shown here.
