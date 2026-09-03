---
name: vme290
description: Concrete firmware patterns for the Heltec Vision Master E290 board (ESP32-S3 + LoRa + 2.9" 296x128 E-ink DEPG0290BxS800FxX_BW panel + GXHTC I2C temp/humidity sensor) - display init/draw/refresh API, GXHTC sensor readout, battery-voltage ADC read, deep sleep with pin hold, and a LoRaWAN weather-station uplink cycle. Use when writing/reviewing firmware for the Vision Master E290, VME290, or an E-ink + LoRa + deep-sleep weather-station-style Heltec board.
version: 1.0.0
---

# Heltec Vision Master E290 (VME290) Firmware

Knowledge extracted from the official Heltec examples in
`Heltec_ESP32/examples/VME290/{deepsleep, DEPG0290BxS800FxX_BW,
GHXTC_Sensor_Display, lorawaneink_GHXTC, weather_station}` and the board's
driver headers `src/HT_DEPG0290BxS800FxX_BW.h` and `src/GXHTC.h`/`.cpp`.

## When to use this skill

Any task targeting the Vision Master E290 (VME290): the 2.9" E-ink panel
(part number `DEPG0290BxS800FxX_BW`, 296x128px), the onboard GXHTC
temperature/humidity sensor, battery-voltage sensing, or a wake/measure/
display/(LoRaWAN uplink)/sleep cycle on this board. **Do not confuse this
with the `eink` skill** — that one covers the Vision Master E213 / Wireless
Paper boards, which use a completely different display library
(`heltec-eink-modules`, `EInkDisplay_*` classes, `fastmodeOn/Off`,
`DRAW(){}` macro). The E290 examples here use the older Heltec core's
`HT_Display`/`ScreenDisplay` (ssd1306-style) API instead — **these two
driver APIs are not interchangeable.**

## What each example demonstrates

| Directory | Demonstrates |
|---|---|
| `deepsleep/deepsleep.ino` | Powering down radio/SPI/Vext and holding pin state before `esp_deep_sleep_start()` with a timer wakeup. No sensor/display use. |
| `DEPG0290BxS800FxX_BW/` | Bare E-ink driver demo: font faces, text alignment, shapes, XBM image — one call per `loop()` iteration, full refresh each time. |
| `GHXTC_Sensor_Display/sensor_th.ino` | Wi-Fi connect, NTP time, and reading the GXHTC sensor every 30s, drawing temp/humidity + icons + time on the E-ink. |
| `lorawaneink_GHXTC/lorawaneink_GHXTC.ino` | Full stack: GXHTC read + E-ink render + pack temp/humidity into a LoRaWAN uplink payload via the standard Heltec `LoRaWAN` state machine (OTAA/ABP, Class C). |
| `weather_station/weather_station.ino` | Wi-Fi + HTTP JSON weather API + NTP time + battery-voltage read + multi-icon E-ink dashboard layout. Its own `readme.md` claims it "only supports Vison Master Eink213", but the code uses the 296x128 `DEPG0290BxS800FxX_BW` display and pin layout identical to the other E290 examples — treat that readme line as a doc error, not evidence this is an E213 sketch. |

## E-ink driver: `DEPG0290BxS800FxX_BW` (`HT_DEPG0290BxS800FxX_BW.h`)

This class extends `ScreenDisplay` (same base as Heltec's OLED/ssd1306
wrapper), so the drawing API is the familiar ssd1306-style immediate-mode
API, not Adafruit-GFX. It is **not** part of the `heltec-eink-modules`
library used elsewhere.

### Construction and init

Every VME290 example wires up the panel identically:

```cpp
#include "HT_DEPG0290BxS800FxX_BW.h"
// rst, dc, cs, busy, sck, mosi, miso, freq
DEPG0290BxS800FxX_BW display(5, 4, 3, 6, 2, 1, -1, 6000000);

void VextON(void) { pinMode(18, OUTPUT); digitalWrite(18, HIGH); }

void setup() {
  VextON();          // must power the Vext rail before touching the display
  delay(100);
  display.init();    // pulses reset, opens FSPI bus, soft-resets panel (0x12)
  display.screenRotate(DIRECTION);   // ANGLE_0/90/180/270_DEGREE
  display.setFont(ArialMT_Plain_10); // fonts: ArialMT_Plain_10 / _16 / _24
}
```

`connect()` internally does `fSPI.begin(sck, miso, mosi)` and toggles reset
(`HIGH -> delay(100) -> LOW -> delay(100) -> HIGH`). Geometry is fixed to
`GEOMETRY_296_128` (framebuffer is `uint8_t _bbf[4736]` = 296*128/8), so this
class is specific to the 2.9" panel — don't reuse it for other panel sizes.

### Drawing API actually used in the examples

```cpp
display.clear();                                   // clear framebuffer (not the panel yet)
display.setFont(ArialMT_Plain_10);                  // _10 / _16 / _24 sizes available
display.setTextAlignment(TEXT_ALIGN_LEFT);           // or _CENTER / _RIGHT
display.drawString(x, y, "text");
display.drawStringMaxWidth(x, y, maxWidth, "text");  // word-wrapped text block
display.setPixel(x, y);
display.drawRect(x, y, w, h);      display.fillRect(x, y, w, h);
display.drawHorizontalLine(x, y, len);
display.drawVerticalLine(x, y, len);
display.setColor(WHITE); display.drawCircle(x, y, r);
display.setColor(BLACK); display.fillCircle(x, y, r);
display.drawLine(x0, y0, x1, y1);
display.drawXbm(x, y, w, h, bitmapArray);            // 1-bit XBM icon
display.width(); display.height();                    // 296 x 128
display.display();                                    // push framebuffer to panel (see below)
```

### `display.display()` — always a full refresh, SPI protocol

```cpp
void display(void) {
  sendCommand(0x24);              // 0x24 = write RAM
  digitalWrite(_cs, LOW);
  // ... for x in width, y in height/8: fSPI.transfer(~buffer[...]);  (bits inverted)
  fSPI.endTransaction();
  digitalWrite(_cs, HIGH);
  sendCommand(0x20);              // 0x20 = display update/refresh trigger
  WaitUntilIdle();                // polls _busy pin: LOW=idle, HIGH=busy, +100ms settle
}
```

**Gotcha: no partial/fast-refresh method is exposed by this driver.** Every
`display.display()` call resends the *entire* 4736-byte framebuffer and
triggers a full-panel update — there is no `fastmodeOn()`/`setWindow()`
equivalent here (contrast with the `eink` skill's `heltec-eink-modules`
library, which does have that). The `weather_station.ino` header comment
claims "Time updates use part refresh, while others information update use
global refresh", but nothing in the code or driver implements a partial
update — that comment describes an aspiration/limitation, not working
behavior. If you need real partial refresh on this panel, you'd have to
extend the driver yourself (e.g. issue `0x24`/`0x20` over a sub-window and
skip `WaitUntilIdle`'s full-frame cost) — don't assume it exists.

Also note four different rotation code paths inside `display()` (0°/180° vs
90°/270° use different byte-reordering and even swap SPI bit order
LSBFIRST/MSBFIRST) — if you see corrupted/mirrored output after changing
`DIRECTION`, that's the known asymmetry in this driver, not necessarily a
wiring bug.

## GXHTC temperature/humidity sensor

I2C sensor, driver in `src/GXHTC.h`/`GXHTC.cpp` (class name is `GXHTC`,
even though the example folder is misspelled `GHXTC_Sensor_Display`).

```cpp
#include "Wire.h"
#include "GXHTC.h"
GXHTC gxhtc;

void setup() {
  gxhtc.begin(39, 38);   // sda, scl — VME290 uses GPIO39/38, NOT the header's
                          // own defaults (GXHTC_SDA=1, GXHTC_SCL=2) — always
                          // pass the board's actual I2C pins explicitly.
}

void read_th() {
  gxhtc.read_data();                 // triggers a measurement over I2C, ~synchronous
  float t = gxhtc.g_temperature;     // °C, already converted
  float h = gxhtc.g_humidity;        // %RH, already converted
  uint16_t id = gxhtc.read_id();     // should read GXHTC_CHIP_ID == 0x0887
}
```

Internally `read_data()` writes two command-word pairs (`0x3517` then
`0x7CA2`) over I2C, reads back 6 bytes, and converts:
`T = -45 + 175 * raw_t/65535`, `RH = 100 * raw_h/65535` (standard SHT-family
conversion — treat it as a SHT3x-compatible I2C sensor at address `0x70`).
Default I2C address is `GXHTC_ADDRESS = 0x70`.

## Combining sensor + display + LoRaWAN uplink (`lorawaneink_GHXTC`)

Pattern: read sensor -> render on E-ink -> pack floats into the LoRaWAN
`appData` buffer -> let the standard Heltec LoRaWAN state machine send it.

```cpp
static void prepareTxFrame(uint8_t port) {
  display.clear();
  GetNetTime();
  gxhtc.begin(39, 38);
  gxhtc.read_data();
  // ... draw temp/humidity + icons on the display, display.display() ...

  appDataSize = 0;
  appData[appDataSize++] = 0x04; appData[appDataSize++] = 0x00;
  appData[appDataSize++] = 0x0A; appData[appDataSize++] = 0x02;   // custom header tag
  unsigned char *puc = (unsigned char *)(&gxhtc.g_temperature);
  appData[appDataSize++] = puc[0]; appData[appDataSize++] = puc[1];
  appData[appDataSize++] = puc[2]; appData[appDataSize++] = puc[3];  // raw float bytes
  appData[appDataSize++] = 0x12;                                     // tag for next field
  puc = (unsigned char *)(&gxhtc.g_humidity);
  appData[appDataSize++] = puc[0]; appData[appDataSize++] = puc[1];
  appData[appDataSize++] = puc[2]; appData[appDataSize++] = puc[3];
  Wire.end();   // gotcha: free the I2C bus before the radio TX/RX window
}
```

This is a **custom byte framing** (raw little-endian `float` memcpy behind
ad-hoc tag bytes `0x04 0x00 0x0A 0x02` / `0x12`), not Cayenne LPP or any
standard codec — the LoRaWAN server-side decoder must match this exact
layout. The surrounding `loop()` follows Heltec's standard LoRaWAN device
state machine unchanged: `DEVICE_STATE_INIT -> JOIN -> SEND -> CYCLE ->
SLEEP`, `LoRaWAN.init(loraWanClass, loraWanRegion)`,
`LoRaWAN.setDefaultDR(3)`, `LoRaWAN.join()`, `prepareTxFrame()` +
`LoRaWAN.send()`, `LoRaWAN.cycle(txDutyCycleTime)`,
`LoRaWAN.sleep(loraWanClass)`. `Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE)` is
called once at the end of `setup()`, after Wi-Fi/NTP/display bring-up.

## Deep sleep cycle (`deepsleep/deepsleep.ino`)

```cpp
#define wakeuptime  10 * 1000 * (uint64_t)1000   // µs — cast to uint64_t or it overflows

void intodeepsleep() {
  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);
  pinMode(18, OUTPUT); digitalWrite(18, LOW);     // Vext OFF: cut power to E-ink/sensor rail
  Radio.Sleep();
  SPI.end();
  pinMode(14, ANALOG);                            // float unused pins to reduce leakage
  pinMode(8, OUTPUT); digitalWrite(8, HIGH);
  rtc_gpio_hold_en(gpio_num_t(8));                // hold pin 8's level through deep sleep
  pinMode(12, ANALOG); pinMode(13, ANALOG);
  pinMode(9, ANALOG);  pinMode(11, ANALOG); pinMode(10, ANALOG);
}

void setup() {
  intodeepsleep();
  esp_sleep_enable_timer_wakeup(wakeuptime);
  delay(4000);                                    // grace window before sleeping
  esp_deep_sleep_start();
}
void loop() {}
```

Key points/gotchas:
- **Radio and SPI must be explicitly put to sleep/ended** (`Radio.Sleep()`,
  `SPI.end()`) before deep sleep, not just relying on `esp_deep_sleep_start()`.
- **Vext (pin 18) is driven LOW to cut power** to the E-ink/sensor rail
  before sleeping — this is the *opposite* of every other example, which
  calls `VextON()` (pin 18 HIGH) in `setup()` before using the display.
  Always pair "power rail on for active work" with "power rail off before
  sleep" in a real wake/measure/display/sleep application.
- `rtc_gpio_hold_en(gpio_num_t(8))` is used to latch pin 8's output level
  during deep sleep (likely a display/power enable line) — without this,
  RTC-domain GPIOs can drift/float during sleep and glitch external
  circuitry on wake.
- Several otherwise-unused pins (9, 10, 11, 12, 13, 14) are set to
  `ANALOG` mode purely to minimize leakage current while asleep — copy this
  pattern for any pins not actively driven during sleep.
- **Reflash gotcha (from the source comment):** once a board is running
  this deep-sleep sketch, to upload new firmware you must "press and hold
  the Boot key, press RST once, and then release the Boot key" to interrupt
  the sleep cycle and re-enter the bootloader.
- No example combines this exact `intodeepsleep()` helper with the
  sensor/display/LoRaWAN examples — if building a real battery-powered
  weather node, you must compose it yourself: `VextON()` -> read GXHTC ->
  draw+`display.display()` -> (optional LoRaWAN send) -> `VextOFF()` +
  radio/SPI teardown -> `esp_sleep_enable_timer_wakeup()` ->
  `esp_deep_sleep_start()`.

## Battery voltage read (`weather_station.ino`)

```cpp
#define VBAT_PIN 7
#define Resolution 0.000244140625     // 1 / 4096 (12-bit ADC LSB fraction)
#define battery_in 3.3
#define coefficient 1.03              // empirical divider-correction factor

pinMode(46, OUTPUT);                  // ADC_Ctrl: must enable the battery-sense circuit
digitalWrite(46, HIGH);

void battery() {
  analogReadResolution(12);
  float battery_data = analogRead(VBAT_PIN) * Resolution * battery_in * coefficient * 4.9;
  // then bucket battery_data against thresholds (<=3.3, 3.4, 3.5, 3.6, 3.8, 3.9, >4.1 V)
  // to pick one of battery0..battery6/batteryfull XBM icons to draw.
}
```

Gotcha: GPIO46 (`ADC_CTrl`) must be driven HIGH to enable the battery-sense
divider before `analogRead(VBAT_PIN)` returns a meaningful value — reading
without enabling it first will give a bogus/floating value.

## Practical checklist for a new VME290 sketch

1. `#include "HT_DEPG0290BxS800FxX_BW.h"`; instantiate
   `DEPG0290BxS800FxX_BW display(5, 4, 3, 6, 2, 1, -1, 6000000);` — reuse
   these exact pin numbers unless your board revision differs.
2. Call `VextON()` (pin 18 HIGH) before `display.init()`; call `VextOFF()`
   (pin 18 LOW, plus `rtc_gpio_hold_en` on any held pins) before deep sleep.
3. `display.init(); display.screenRotate(DIRECTION); display.setFont(...);`
   then draw with the ssd1306-style API and finish each frame with
   `display.display()` — remember this is always a full refresh (no partial
   update path exists in this driver).
4. For the sensor: `GXHTC gxhtc; gxhtc.begin(39, 38);` then
   `gxhtc.read_data()` and read `g_temperature`/`g_humidity`.
5. For LoRaWAN uplink, follow the standard Heltec `DEVICE_STATE_*` state
   machine and call `Wire.end()` after the sensor read, before radio TX.
6. For battery-powered operation, enable GPIO46 before reading `VBAT_PIN=7`
   with the documented scale factor, and read battery + sensor + draw
   *before* cutting Vext and entering deep sleep — none of the stock
   examples do the full cycle end-to-end, so this composition is on you.
