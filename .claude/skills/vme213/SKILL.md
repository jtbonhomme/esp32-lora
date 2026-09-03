---
name: vme213
description: Concrete firmware patterns for the Heltec Vision Master E213 board (VME213) — ESP32-S3 + LoRa + 2.13" E-ink display, typically battery powered with deep sleep. Covers global vs partial e-ink refresh, GXHTC temp/humidity sensor, battery voltage ADC read, Vext power control, and ESP32 deep sleep pin-holding. Use when writing/reviewing firmware for the Vision Master E213 / Eink213 board, or any Heltec board using the HT_ICMEN2R13EFC1 / HT_E0213A367 display classes.
version: 1.0.0
---

# Heltec Vision Master E213 (VME213)

Knowledge extracted from the official Heltec examples in
`Heltec_ESP32_Dev-Boards/examples/VME213`: `Deepsleep`, `Global_Simple`,
`HT_lCMEN2R13EFC1`, `LorawanEink`, `Part_Simple`, `sensor_th`, `weather_station`.

**This is a different e-ink API than the repo's `eink` skill.** The `eink`
skill covers the `heltec-eink-modules` library (`EInkDisplay_*`,
`DRAW()`, `fastmodeOn/Off`). VME213 examples instead use board-support
classes `HT_ICMEN2R13EFC1` / `HT_E0213A367` (from `HT_lCMEN2R13EFC1.h`),
with a `clear()` / `update(BUFFER)` / `display()` / `dis_img_Partial_Refresh()`
API. Do not mix the two APIs.

## When to use this skill

Writing or reviewing firmware for the Vision Master E213 (ESP32-S3 + SX126x
LoRa + 250x122 2-color e-ink panel), or anything touching
`HT_lCMEN2R13EFC1.h`, `HT_ICMEN2R13EFC1`, `HT_E0213A367`, `GXHTC.h`, or a
battery-powered e-ink + LoRa + deep-sleep weather-station-style device.

## What each example demonstrates

| Directory | Demonstrates |
|---|---|
| `Deepsleep` | Pure ESP32 deep sleep prep: radio off, SPI off, unused pins set to ANALOG, one GPIO latched HIGH via `rtc_gpio_hold_en`, timer wakeup. No display/sensor code. |
| `Global_Simple` | Full-refresh ("global") e-ink drawing demo: text, shapes, XBM image. Also auto-detects panel revision (`HT_ICMEN2R13EFC1` vs `HT_E0213A367`) by bit-banging a chip-ID read over SPI before constructing the display object. |
| `HT_lCMEN2R13EFC1` | Same full-refresh demo as `Global_Simple` but with the display object constructed directly (no auto-detect), and a different/inconsistent pin order — see gotcha below. |
| `LorawanEink` | LoRaWAN (Class C) uplink of GXHTC temperature/humidity, with the reading also drawn to the e-ink screen. Time is fetched over **WiFi** NTP, not LoRaWAN device-time. Uses the LoRaWAN device-state machine (`DEVICE_STATE_INIT/JOIN/SEND/CYCLE/SLEEP`), not ESP32 deep sleep. |
| `Part_Simple` | Partial ("fast") refresh demo: repeatedly blits small digit bitmaps into a fixed screen region via `dis_img_Partial_Refresh()`, without going through `clear()`/`update()`/`display()`. |
| `sensor_th` | GXHTC temperature/humidity read over I2C + WiFi NTP time, drawn with a global-refresh loop every 30s. No LoRa, no deep sleep. |
| `weather_station` | The fullest app: WiFi + Open-Meteo HTTP/JSON weather API + NTP + battery-voltage gauge icon + weather icons + a nav bar (global refresh) with a clock that ticks via partial refresh. No deep sleep — designed to stay awake and poll every minute. |

None of the examples combines deep sleep + sensor read + e-ink update +
LoRa send in one sketch — each piece is demonstrated in isolation. See
"Composing a full wake/measure/display/sleep cycle" below for how to stitch
them together, and treat that composition as untested guidance, not a
copy-pasted example.

## Display driver: construction and pinout

```cpp
#include "HT_lCMEN2R13EFC1.h"
// rst, dc, cs, busy, sck, mosi, miso, frequency
HT_ICMEN2R13EFC1 display(3, 2, 5, 1, 4, 6, -1, 6000000);
```

This exact pinout (`rst=3, dc=2, cs=5, busy=1, sck=4, mosi=6, miso=-1`) is
used consistently in `Part_Simple`, `LorawanEink`, `weather_station`, and
`Global_Simple`'s auto-detect path — treat it as the canonical VME213
wiring. `miso=-1` because e-ink panels are write-only (no MISO line wired).

**Gotcha:** `HT_lCMEN2R13EFC1/HT_lCMEN2R13EFC1.ino` instantiates the same
class with a *different* pin order — `display(6, 5, 4, 7, 3, 2, -1,
6000000)`. This is inconsistent with every other example in the set. Prefer
the canonical pinout above unless you've confirmed the exact board
revision needs the other wiring.

`Global_Simple` shows how to auto-detect the panel chip revision instead of
hardcoding a class, by manually bit-banging an SPI command (`0x2F`) and
reading back a chip ID before picking the driver class:

```cpp
// after resetting the panel and clocking out cmd 0x2F...
if ((chipId & 0x03) != 0x01) {
  display = new HT_ICMEN2R13EFC1(3, 2, 5, 1, 4, 6, -1, 6000000);
} else {
  display = new HT_E0213A367(3, 2, 5, 1, 4, 6, -1, 6000000);
}
```

Screen size/orientation:
```cpp
#define DIRECTION ANGLE_0_DEGREE // or 90/180/270
display.init();
display.screenRotate(DIRECTION);
display.setFont(ArialMT_Plain_10);
// width/height swap depending on rotation:
width  = (DIRECTION == ANGLE_0_DEGREE || DIRECTION == ANGLE_180_DEGREE) ? display._width  : display._height;
height = (DIRECTION == ANGLE_0_DEGREE || DIRECTION == ANGLE_180_DEGREE) ? display._height : display._width;
```
Panel is 250x122 in the 0/180-degree orientation.

## Global (full) refresh vs partial refresh

**Global refresh** — used for anything that isn't a small fixed region
(text, shapes, full-screen redraws). Pattern seen in every non-`Part_Simple`
example:

```cpp
display.clear();
display.setFont(ArialMT_Plain_10);
display.setTextAlignment(TEXT_ALIGN_LEFT);
display.drawString(0, 0, "Hello world");
// ... more draw calls (drawRect, drawXbm, fillCircle, etc.) ...
display.update(BLACK_BUFFER);   // commit the black-layer draw calls made so far
// ... optionally more draw calls for the second color layer ...
display.update(COLOR_BUFFER);   // commit the color/red-layer draw calls
display.display();              // push the composed buffers to the physical panel
```

The two-color panel has separate `BLACK_BUFFER` and `COLOR_BUFFER` layers —
`update(BUFFER)` commits whatever was drawn since the last `clear()`/`update()`
into that layer, and `display()` is the final flush to the panel (a full,
ghosting-clearing refresh). This is a two-step commit, not a single call —
forgetting `display()` means nothing appears on the panel.

**Partial ("fast") refresh** — used only in `Part_Simple` and for the clock
digits in `weather_station`, to update a small fixed-size region (e.g. a
single digit glyph) without a full-panel flash:

```cpp
// dis_img_Partial_Refresh(x, y, img_width, img_length, bitmap)
display.dis_img_Partial_Refresh(100, 32, 14, 4, num0);
```
Comment in the source: *"The second parameter, the fourth parameter, takes
an integer multiple of 8"* — i.e. `y` and `img_length` should be multiples
of 8 (the `Part_Simple` example itself uses `y=32, length=4`, which doesn't
strictly follow that rule, so treat it as a soft constraint to verify
against the panel's actual line/byte alignment before relying on odd
values).

`weather_station` calls the same function with two extra trailing bool
args — `dis_img_Partial_Refresh(155, 20, 32, 14, num0, true, true)` — whose
exact meaning isn't documented in the source comments. Don't assume their
purpose; check the library header (`HT_lCMEN2R13EFC1.h`) before relying on
them.

`weather_station`'s actual pattern: full-refresh the whole layout (nav bar,
weather, forecast) once per data fetch, then partial-refresh just the four
clock digits on the intervening ticks:
```cpp
void loop() {
  uint8_t part_times = 10;
  while (part_times > 0) {
    fetchWeather();                 // draws full widget into buffer
    part_time();                    // partial-refreshes the 4 clock digit regions
    display.update(COLOR_BUFFER);   // full refresh commit
    display.display();
    delay(1000 * 60);
    part_times--;
  }
}
```

## XBM icons

Icons are plain `PROGMEM` byte arrays in a sibling header, drawn with
`drawXbm`:
```cpp
#include "images.h"
display.drawXbm(x, y, WiFi_Logo_width, WiFi_Logo_height, WiFi_Logo_bits);
```
`weather_station/images.h` is the richest example: per-digit glyphs
(`num0`..`num9`), a `colon3x18` separator, a battery icon set
(`battery0`..`battery6`, `batteryfull`, sized `battery_w=13`/`battery_h=13`),
and ~20 weather-condition icons (`icon_sunny_code_0`,
`icon_cloudy_code_3`, `icon_rain_code_61`, ...) each `48x48`, switched on
the Open-Meteo WMO weather code.

## Vext (peripheral power rail) control

Every example gates e-ink/sensor power through GPIO 18 before touching the
display or I2C bus:
```cpp
void VextON(void)  { pinMode(18, OUTPUT); digitalWrite(18, HIGH); }
void VextOFF(void) { pinMode(18, OUTPUT); digitalWrite(18, LOW); }  // Vext default OFF
```
Call `VextON(); delay(100);` before `display.init()`. `Deepsleep.ino`
explicitly drives it `LOW` (`digitalWrite(18, LOW)`) as the first step of
its sleep-prep routine, to cut peripheral power while asleep.

## Battery voltage read (weather_station only)

```cpp
#define VBAT_PIN 7
#define Resolution 0.000244140625
#define battery_in 3.3
#define coefficient 1.03   // tune this if the reading is off from actual voltage

pinMode(46, OUTPUT);        // "Enable ADC_CTrl" — must be driven HIGH first
digitalWrite(46, HIGH);     // or VBAT_PIN reads garbage/0

analogReadResolution(12);
float battery_data = analogRead(VBAT_PIN) * Resolution * battery_in * coefficient * 4.9;
```
**Gotcha:** GPIO 46 is a separate "ADC control" enable pin that gates the
battery-voltage divider circuit — it must be set `HIGH` before `analogRead(VBAT_PIN)`
returns a meaningful value; this is easy to miss since it's unrelated to
Vext (GPIO 18). The code then buckets the voltage into 7 icon levels
(`battery0` = <=3.3V, ..., `batteryfull` = >4.1V) and shows "N/A" text below 3.3V.

## GXHTC temperature/humidity sensor

```cpp
#include "GXHTC.h"
GXHTC gxhtc;
gxhtc.begin(39, 38);      // SDA, SCL
gxhtc.read_data();
gxhtc.g_temperature;      // float, °C
gxhtc.g_humidity;         // float, %
gxhtc.read_id();          // chip ID, e.g. Serial.printf("id = %X\r\n", gxhtc.read_id());
```
`LorawanEink.ino` calls `Wire.end()` right after reading the sensor, before
building/sending the LoRaWAN payload — releasing the I2C bus once the
reading is captured is the pattern to follow if you need to free I2C for
other use or reduce power between reads.

Packing a float sensor reading into a raw LoRaWAN payload (byte-for-byte,
no encoding library):
```cpp
appDataSize = 0;
appData[appDataSize++] = 0x04; appData[appDataSize++] = 0x00;
appData[appDataSize++] = 0x0A; appData[appDataSize++] = 0x02;
unsigned char *puc = (unsigned char *)(&gxhtc.g_temperature);
appData[appDataSize++] = puc[0]; appData[appDataSize++] = puc[1];
appData[appDataSize++] = puc[2]; appData[appDataSize++] = puc[3];
appData[appDataSize++] = 0x12;
puc = (unsigned char *)(&gxhtc.g_humidity);
appData[appDataSize++] = puc[0]; appData[appDataSize++] = puc[1];
appData[appDataSize++] = puc[2]; appData[appDataSize++] = puc[3];
```
(the leading `0x04 0x00 0x0A 0x02` / `0x12` bytes look like an
application-specific tag/length header, not a library API — treat them as
this example's own protocol, not something to copy verbatim.)

## ESP32 deep sleep prep (from `Deepsleep.ino`)

This is the only example that actually enters deep sleep. Full snippet:
```cpp
#include "LoRaWan_APP.h"
#include "driver/rtc_io.h"
#include <driver/gpio.h>

#define wakeuptime 10 * 1000 * (uint64_t)1000  // microseconds -> 10s here

void intodeepsleep() {
  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);
  pinMode(18, OUTPUT);
  digitalWrite(18, LOW);       // Vext off
  Radio.Sleep();                // put the LoRa radio to sleep explicitly
  SPI.end();                    // release the SPI bus
  pinMode(14, ANALOG);
  pinMode(8, OUTPUT);
  digitalWrite(8, HIGH);
  rtc_gpio_hold_en(gpio_num_t(8));  // latch GPIO8 HIGH across deep sleep
  pinMode(12, ANALOG);
  pinMode(13, ANALOG);
  pinMode(9, ANALOG);
  pinMode(11, ANALOG);
  pinMode(10, ANALOG);
}

void setup() {
  intodeepsleep();
  esp_sleep_enable_timer_wakeup(wakeuptime);
  delay(4000);
  esp_deep_sleep_start();
}
void loop() {}
```
Gotchas called out by the code (not comments, but implicit in what it
does):
- **Set every unused GPIO to `ANALOG` mode** (floating/high-Z) before
  sleeping — this is the standard ESP32 trick to eliminate leakage current
  through pins that would otherwise be left as digital in/out.
- **`rtc_gpio_hold_en(gpio_num_t(pin))`** latches a pin's output level so it
  survives deep sleep (RTC domain keeps driving it even though the main
  CPU/GPIO logic powers down) — used here to hold GPIO 8 HIGH. Use this for
  any pin whose state must not glitch/float during sleep (e.g. a power
  latch or enable line for external circuitry).
- **Explicitly sleep the radio (`Radio.Sleep()`) and end SPI (`SPI.end()`)**
  before sleeping — don't rely on deep sleep alone to power down peripherals
  that were left mid-transaction.
- **`esp_sleep_enable_timer_wakeup()` takes microseconds**, not
  milliseconds or seconds — the `wakeuptime` macro is `10 * 1000 * 1000`
  microseconds (10s), cast to `uint64_t`.
- **No `RTC_DATA_ATTR` / RTC memory usage appears anywhere in this example
  set.** None of the seven sketches persists state (a boot counter, last
  reading, wake reason, etc.) across deep sleep. If you need that, use
  `RTC_DATA_ATTR` variables and check `esp_sleep_get_wakeup_cause()` — this
  is a gap you'll need to add yourself, not a pattern copied from these
  examples.

## Composing a full wake/measure/display/sleep cycle

No single example wires all four steps together — this is a synthesis of
the real building blocks above, not a tested example. A VME213
battery-powered weather-node cycle would look like:

```cpp
void setup() {
  VextON(); delay(100);          // power up e-ink + sensors (from Global_Simple/Part_Simple/etc.)
  display.init();
  display.screenRotate(DIRECTION);

  gxhtc.begin(39, 38);           // from LorawanEink/sensor_th
  gxhtc.read_data();
  Wire.end();                    // release I2C once read (from LorawanEink)

  display.clear();               // draw + full refresh (from Global_Simple/weather_station)
  // ... draw temperature/humidity/battery ...
  display.update(COLOR_BUFFER);
  display.display();

  // optionally: LoRaWAN.send(...) with the packed payload, as in LorawanEink

  intodeepsleep();                // from Deepsleep.ino: Vext off, Radio.Sleep(), SPI.end(), unused pins ANALOG, rtc_gpio_hold_en on any latched pin
  esp_sleep_enable_timer_wakeup(wakeuptime);
  esp_deep_sleep_start();
}
void loop() {}
```
Note that `LorawanEink`'s LoRaWAN send is driven by its own state machine
(`DEVICE_STATE_SEND` -> `LoRaWAN.send()` -> `DEVICE_STATE_CYCLE` ->
`DEVICE_STATE_SLEEP` -> `LoRaWAN.sleep()`), which is a MAC-level idle, not
an ESP32 deep sleep — if you need actual power-off deep sleep after a
LoRaWAN send, you must call `intodeepsleep()`/`esp_deep_sleep_start()`
yourself after the send completes; the LoRaWAN example as written never
enters ESP32 deep sleep, it just loops forever redoing the duty cycle.
