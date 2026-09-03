---
name: esp32-utilities
description: Concrete Heltec ESP32 (WiFi LoRa 32 / Wireless Stick) code patterns extracted from official Heltec examples — battery voltage reading via ADC divider, Vext external power rail control, dual-core FreeRTOS tasks with xTaskCreatePinnedToCore, deep sleep with external wakeup (ext0/ext1) and ULP GPIO hold, I2C scanner, chip ID/eFuse MAC, PSRAM test, RTC counter, and Serial1/Serial2 UARTs.
version: 1.0.0
---

# Heltec ESP32 Utilities Cookbook

Concrete, copy-adaptable patterns from HelTec Automation's official Arduino examples
(`Heltec_ESP32_Dev-Boards/examples/ESP32/*`) for the peripherals/utilities every
Heltec WiFi LoRa 32 / Wireless Stick firmware ends up needing. This is deliberately
narrow and Heltec-specific — for general ESP32 chip theory, GPIO safety, or ESP-IDF/
PlatformIO tooling, use the sibling `esp32` skill instead.

## When to use this skill

Reach for this skill when writing or debugging code that touches: reading battery
voltage on GPIO13/GPIO37, turning the Vext power rail on/off (OLED, sensors, RF
switch), pinning FreeRTOS tasks to core 0 vs core 1, putting the board into deep
sleep and waking it with a button/external signal, holding a GPIO level through deep
sleep with the ULP/RTC domain, scanning I2C0 for device addresses, reading the chip's
eFuse MAC / chip ID, verifying external PSRAM, reading the internal RTC counter, or
using Serial1/Serial2 alongside the USB Serial console.

## Board family note

Heltec board hardware differs by revision — read comments in examples before reuse:
- V1 boards ("WIFI Kit series V1") have **no Vext control**.
- V2/V3 boards: Vext MOSFET is **active LOW** (`VextON()` pulls GPIO21 LOW).
- V4 boards: Vext MOSFET is **active HIGH** (per `VextControl.ino` comment).
- Battery-sense pin moved across hardware revisions: GPIO13 (older/simple examples),
  GPIO37 combined with GPIO36 "Vin" sense (`Battery_power.ino`, hw ≥ V2.3), or
  GPIO1 with a GPIO37 enable pin (`WiFiLoRa32_battery_read.ino`, V3.2). **Always
  confirm the exact pin/polarity for the specific board revision in use** rather than
  assuming one example's pins apply everywhere.

## 1. Battery / ADC voltage reading

Three real variants exist in the examples — pick based on board revision and
precision needs.

**Simple raw read (`ADC_Read_Voltage/ADC_Read_Simple`)** — GPIO13, no calibration:
```cpp
adcAttachPin(13);
analogSetClockDiv(255); // 1338mS
// loop: Serial.print(analogRead(13));
```

**Accurate polynomial-corrected read (`ADC_Read_Accurate`)** — improves default ADC
accuracy to ~1% using a polynomial fit against measured reference points:
```cpp
double ReadVoltage(byte pin) {
  double reading = analogRead(pin); // 3.3V ref -> range 0..4095
  if (reading < 1 || reading >= 4095)
    // return 0;
  return -0.000000000000016 * pow(reading,4) + 0.000000000118171 * pow(reading,3)
       - 0.000000301211691 * pow(reading,2) + 0.001109019271794 * reading
       + 0.034143524634089;
}
```
The polynomial was fit from measured raw-ADC-vs-voltage pairs (464->0.5V,
1088->1.0V, 1707->1.5V, 2331->2.0V, 2951->2.5V, 3775->3.0V) — don't reuse the
coefficients on a different board/attenuation without re-deriving them.

**Heltec.begin() based battery read (`Battery_power.ino`)** — for hw ≥ V2.3 boards
using GPIO37 (battery) and GPIO36 ("Vin"):
```cpp
#define Fbattery 3700 // full-charge battery default, mV
float XS = 0.0025;    // scale factor: raw ADC -> volts, multiplied by MUL for mV
uint16_t MUL = 1000;

analogSetClockDiv(1);
analogSetAttenuation(ADC_11db);         // ADC_11db: IN/OUT = 1/3.6, 3V input -> ~0.833V at ADC
analogSetPinAttenuation(36, ADC_11db);
analogSetPinAttenuation(37, ADC_11db);
adcAttachPin(36);
adcAttachPin(37);

// loop:
uint16_t vbat_mV = analogRead(37) * XS * MUL;      // battery voltage
uint16_t vin_mV  = analogRead(36) * 0.769 + 150;    // external Vin voltage (empirical fit)
```
Attenuation cheat sheet used across examples (`ADC_0db`/`ADC_2_5db`/`ADC_6db`/`ADC_11db`):
0db = no attenuation (IN=OUT); 2.5db = 1/1.34; 6db = 1/2; 11db = 1/3.6 (widest range,
default). Comment in `ADC_Read_Simple.ino` documents `analogReadResolution`/
`analogSetWidth` (9-12 bit, default 12-bit = 0-4095) and low-level `adcAttachPin`/
`adcStart`/`adcBusy`/`adcEnd` API if you need non-blocking conversions.

**Newer boards, `analogReadMilliVolts` (`WiFiLoRa32_battery_read.ino`, V3.2)** — uses
a GPIO37 enable pin plus a built-in mV conversion, then a board-specific scale factor:
```cpp
analogReadResolution(12);
pinMode(37, OUTPUT);
digitalWrite(37, HIGH); // enable ADC/battery-sense circuit before reading

int analogValue = analogRead(1);
int analogVolts = analogReadMilliVolts(1);
Serial.printf("ADC millivolts value = %d\n", analogVolts * 490 / 100); // board-specific divider scale (4.90x)
```
Gotcha: on this variant, GPIO37 must be driven HIGH first to enable the sense
circuit before `analogRead(1)`/`analogReadMilliVolts(1)` return anything meaningful.

## 2. Vext (external power rail) control

Many Heltec boards gate power to the OLED and RF switch (PE4259) through a MOSFET
on GPIO21, exposed as `Heltec.VextON()` / `Heltec.VextOFF()` once `heltec.h` is used
and `Heltec.begin()` has run. From `VextControl.ino`:
```cpp
#include "heltec.h"

void setup() {
  Heltec.begin(true /*Display*/, false /*LoRa*/, true /*Serial*/);
  // Vext must be ON before OLED init — OLED is powered through Vext.
  Heltec.display->init();
  ...
}

void loop() {
  Heltec.display->sleep();
  Heltec.VextOFF();
  Serial.println("Turn OFF Vext");
  delay(5000);

  Heltec.VextON();
  Serial.println("Turn ON Vext");
  Heltec.display->wakeup();
  delay(5000);
}
```
Gotchas:
- Polarity flips by hardware revision: MOSFET is **active LOW** on V2/V3 boards,
  **active HIGH** on V4 — `Heltec.VextON()`/`VextOFF()` abstract this away, so prefer
  those over manually driving GPIO21 unless you know the exact revision.
- V1 boards have no Vext control at all — check board revision before calling these.
- Turning Vext off cuts power to the OLED and the LoRa RF switch — call
  `display->sleep()` before `VextOFF()` and `display->wakeup()` after `VextON()`, and
  expect a LoRa radio (PE4259-switched) to also need Vext on to transmit/receive.
- This is the standard technique for battery-life optimization: cut Vext during deep
  sleep / idle periods since the OLED+RF switch draw current even when unused.

## 3. Dual-core FreeRTOS tasks

ESP32 exposes `xPortGetCoreID()` to identify the running core, and
`xTaskCreatePinnedToCore` to pin a task to core 0 or core 1 (Arduino `loop()` runs on
core 1 by default).

**Just print current core (`Showcore.ino`):**
```cpp
void loop() {
  Serial.println(xPortGetCoreID());
  ...
}
```

**Pin a task to a specific core (`Movecore.ino`):**
```cpp
TaskHandle_t Task1;

void codeForTask1(void *parameter) {
  for (;;) {
    Serial.print("This Task run on Core: ");
    Serial.println(xPortGetCoreID());
    digitalWrite(LED1, HIGH); delay(1000);
    digitalWrite(LED1, LOW);  delay(1000);
  }
}

void setup() {
  xTaskCreatePinnedToCore(
    codeForTask1, "Task_1", 1000 /*stack*/, NULL /*param*/,
    1 /*priority*/, &Task1, 0 /*core*/);
}
```
Gotcha: a pinned task's function must contain its own infinite `for(;;)` loop — it
never returns like `loop()` does; returning from the task function is undefined
behavior in FreeRTOS unless you call `vTaskDelete(NULL)`.

**Two independent tasks + main loop, comparing throughput (`SpeedTest.ino`)** shows
running the same CPU-bound `artificialLoad()` simultaneously on core 0 (`Task1`),
core 1 (`Task2`, offset-started with a `delay(500)` between the two
`xTaskCreatePinnedToCore` calls to desync them), and `loop()` itself (also core 1),
timing each with `millis()`. It declares `SemaphoreHandle_t baton =
xSemaphoreCreateMutex();` for task synchronization (mutex is created but the shown
example doesn't exercise take/give — set up as scaffolding for readers to extend).
Confirms: `loop()` competes with any task pinned to core 1, so CPU-heavy work
belongs on core 0 if `loop()` needs to stay responsive.

## 4. Deep sleep + external wakeup

**Wake on button press via ext0 (`ExternalWakeUp.ino`)** — RTC-only GPIOs (0, 2, 4,
12-15, 25-27, 32-39) can be used as wakeup sources:
```cpp
#include "driver/rtc_io.h"
RTC_DATA_ATTR int bootCount = 0; // survives deep sleep / reboot

void setup() {
  rtc_gpio_deinit(GPIO_NUM_0);
  ++bootCount;
  print_wakeup_reason(); // esp_sleep_get_wakeup_cause() switch on ESP_SLEEP_WAKEUP_EXT0/EXT1/TIMER/TOUCHPAD/ULP

  rtc_gpio_pulldown_en(GPIO_NUM_0);
  esp_sleep_enable_ext0_wakeup(GPIO_NUM_0, 0); // wake on LOW->trigger, 1=High 0=Low
  // ext1 alternative (bitmask of RTC pins, no RTC peripheral power needed):
  // esp_sleep_enable_ext1_wakeup(BUTTON_PIN_BITMASK, ESP_EXT1_WAKEUP_ANY_HIGH);

  esp_deep_sleep_start();
  // code after this line never runs
}
```
Gotchas from comments: ext0 uses RTC_IO and needs RTC peripherals powered (so
internal pullups/pulldowns work); ext1 uses the RTC controller and doesn't need
peripherals on. `BUTTON_PIN_BITMASK` is `1ULL << gpio_num` (`0x200000000` = 2^33 for
GPIO33 in the ext1 comment form). Only RTC-capable pins qualify as wakeup sources.

**Hold a GPIO level across deep sleep with ULP/RTC hold (`ULP/HoldPinStatus.ino`)**
— keeps an LED lit/off through deep sleep using `rtc_gpio_hold_en`, not the ULP
coprocessor program itself:
```cpp
#include "driver/rtc_io.h"
#define TIME_TO_SLEEP 5

void setup() {
  rtc_gpio_hold_dis(GPIO_NUM_35);
  pinMode(35, OUTPUT);
  digitalWrite(35, LOW); // LED off while awake

  esp_sleep_enable_timer_wakeup(TIME_TO_SLEEP * 1000000ULL /* uS_TO_S_FACTOR */);

  rtc_gpio_init(GPIO_NUM_35);
  pinMode(35, OUTPUT);
  digitalWrite(35, HIGH);      // LED on during sleep
  rtc_gpio_hold_en(GPIO_NUM_35); // latch the pin level through deep sleep
  esp_deep_sleep_start();
}
```
Gotcha: you must call `rtc_gpio_hold_dis()` at the start of the next boot before
reconfiguring the pin, otherwise the hold from the previous sleep cycle keeps the
pin latched and writes are ignored.

## 5. Chip ID / eFuse MAC (`GetChipID.ino`)
```cpp
uint64_t chipId = ESP.getEfuseMac(); // true ESP32 chip ID == its MAC address
Serial.printf("ESP32 Chip model = %s Rev %d\n", ESP.getChipModel(), ESP.getChipRevision());
Serial.printf("This chip has %d cores\n", ESP.getChipCores());
Serial.printf("ESP32ChipID=%04X", (uint16_t)(chipId >> 32)); // high 2 bytes
Serial.printf("%08X\r\n", (uint32_t)chipId);                 // low 4 bytes
```
Useful for per-device identifiers (e.g. deriving a LoRa node address) without
storing a separate ID in flash.

## 6. I2C scanner (`I2C_Scanner.ino`)

ESP32 has two I2C buses (`Wire` = I2C0, `Wire1` = I2C1). On Heltec boards the OLED
is on I2C0 and answers at `0x3C`.
```cpp
#include "heltec.h"
#if defined(WIRELESS_STICK_LITE)
  static const uint8_t SCL_OLED = 15;
  static const uint8_t SDA_OLED = 4;
#endif

void setup() {
  Heltec.begin(true, false, true);
  Wire.begin(SDA_OLED, SCL_OLED); // scan OLED's bus (I2C0)
  // Wire1.begin(SDA, SCL);       // use for a second device on I2C1 instead
}

void loop() {
  byte error, address; int nDevices = 0;
  for (address = 1; address < 127; address++) {
    Wire.beginTransmission(address);
    error = Wire.endTransmission();
    if (error == 0) {
      Serial.printf("I2C device found at address 0x%02X !\n", address);
      nDevices++;
    } else if (error == 4) {
      Serial.printf("Unknown error at address 0x%02X\n", address);
    }
  }
  if (nDevices == 0) Serial.println("No I2C devices found\n");
  delay(5000);
}
```
To probe a second I2C bus, comment out all `Wire.*` calls and uncomment the
`Wire1.*` equivalents rather than mixing both simultaneously.

## 7. PSRAM test (`PSRAM_Test.ino`)
```cpp
Serial.printf("Total heap: %d\r\n", ESP.getHeapSize());
Serial.printf("Free heap: %d\r\n", ESP.getFreeHeap());
Serial.printf("Total PSRAM: %d\r\n", ESP.getPsramSize());
byte* psdRamBuffer = (byte*)ps_malloc(4000000); // allocate from PSRAM specifically
Serial.printf("Free PSRAM: %d\r\n", ESP.getFreePsram());
```
Requires a board with external PSRAM actually wired up; `ESP.getPsramSize()` /
`ESP.getFreePsram()` return 0 if PSRAM isn't present or isn't enabled in the build
config. `ps_malloc` is the way to explicitly request PSRAM instead of internal heap
for large buffers.

## 8. RTC counter (`RTC_counter.ino`)
```cpp
#include "soc/rtc.h"
uint64_t rtc_counter1 = rtc_time_get();
delay(1000);
uint64_t rtc_counter2 = rtc_time_get();
Serial.println((uint32_t)(rtc_counter2 - rtc_counter1));
```
Comment notes the board uses an internal 150KHz RTC clock, and it is **not
accurate** — don't use `rtc_time_get()` deltas as a precise timebase; use it only
for coarse/relative timing across sleep cycles, not real-time-clock precision.

## 9. Serial1 / Serial2 (`Serial2.ino`)

ESP32 has 3 hardware UARTs, and pins are freely remappable via the IO MUX:
```cpp
Serial1.begin(115200, SERIAL_8N1, 2, 17);  // rxPin=2, txPin=17
Serial2.begin(115200, SERIAL_8N1, 22, 23); // rxPin=22, txPin=23

void loop() {
  if (Serial.available())  Serial1.write(Serial.read());   // USB -> UART1
  if (Serial2.available()) Serial2.write(Serial2.read());  // UART2 loopback echo
  if (Serial2.available()) Serial.write(Serial2.read());   // UART2 -> USB
}
```
`Serial1.begin`/`Serial2.begin` take `(baud, config, rxPin, txPin, invert)` — the
Rx/Tx pins can be set to essentially any output-capable GPIO thanks to the ESP32 IO
MUX, unlike some other MCUs with fixed UART pins.
