---
name: factory-test
description: Structural patterns from Heltec's official factory-test firmware (per board family) for writing or adapting an all-in-one hardware bring-up self-test sketch — display, LoRa radio, WiFi, sensors, GPS, buttons, battery ADC — on a Heltec ESP32 board. Use for hardware bring-up self-test, factory test firmware, or board validation tasks.
version: 1.0.0
---

# Heltec Factory-Test Firmware Patterns

Grounded in Heltec's official `Factory_Test` examples (~28 board variants: WiFi_LoRa_32 V2-V4, Vision_Master T190/E290/E213, Wireless_Paper, Wireless_Tracker, Wireless_Stick/Shell, RadioCore C6/S3R8, RC32/RCC6, Lora32_R8_V4.3_Exp_Board_HF). Use this skill when asked to write/adapt a single sketch that exercises multiple peripherals on one board and reports pass/fail — not for a single-peripheral driver (see the peripheral-specific skills listed at the bottom).

## 1. Board family → what gets tested

| Board family | Display | Radio | Extra peripherals tested |
|---|---|---|---|
| WiFi_LoRa_32 V2/V3/V4/V4_R8 | SSD1306 128x64 OLED (I2C, `HT_SSD1306Wole`/`HT_SSD1306Wire`) | LoRa (LoRaWan_APP) | WiFi connect+scan, LED, deep sleep; V4 adds GPS (TinyGPS++ on Serial1) |
| WIFI_Kit_32 / V3 | SSD1306 OLED | **none** (no LoRaWan_APP include) | WiFi connect+scan, LED only |
| Wireless_Stick_Lite(/V3), Wireless_Stick_V3, Wireless_Shell(/V3), WIRELESS_MINI_SHELL | SSD1306 OLED | LoRa | WiFi, LED |
| Vision_Master_T190(/V1.4.1) | ST7789 color TFT 1.9" (`Adafruit_ST7789`/`Adafruit_GFX`) | LoRa | WiFi, battery ADC (`analogRead`+coefficient), I2C bus scan |
| Vision_Master_E290(/V0.4.1) | E-ink 2.9" (`HT_DEPG0290BxS800FxX_BW`) | LoRa | WiFi, battery ADC, I2C scan, boot-button long-press → rescan |
| Vsion_Master_E213 / E0213A367 | E-ink 2.13" (`HT_QYEG0213RWS800_BWR` / `HT_E0213A367`) | LoRa | WiFi, battery ADC |
| Wireless_Paper V1.0/V1.1, E0213A367 | E-ink (`HT_ICMEN2R13EFC1` / `HT_DEPG0290..` / `HT_E0213A367`) | LoRa | WiFi scan, boot-button long-press (>1s) → rescan+redisplay logo, deep sleep |
| Wireless_Tracker V1.0/V1.1/V2 | ST7735/ST7736 TFT (`HT_st7735`/`HT_st7736`) | LoRa | WiFi, GPS (TinyGPS++ over Serial1, `VGNSS_CTRL`/Vext power gate), deep sleep |
| RadioCore_C6, RadioCore_S3R8 | **none** — Serial-only | LoRa | WiFi connect+scan, deep sleep. Pure radio-module bring-up, no display code at all |
| RC32, RCC6 | **none** — Serial-only | LoRa | GPIO sequential sweep (every pin HIGH then LOW, 500ms step), WiFi, battery ADC (`analogReadMilliVolts`), structured `FT_ITEM`/`FT_RESULT` pass/fail protocol over Serial (newest/cleanest style — model new sketches on this one) |
| Lora32_R8_V4.3_Exp_Board_HF | SSD1306 OLED | LoRa + TX continuous-wave power sweep | WiFi, GPS, I2C scan, BME280 (temp/humidity/pressure/altitude), GXHTC (temp/humidity), DA217 (accelerometer), buzzer (LEDC), SD card (SdFat: init/list/write/read/verify), two independent button tasks, deep sleep — the most feature-complete reference sketch |

## 2. Common structural pattern

Every sketch follows the same skeleton, built on `LoRaWan_APP.h` (provides `Radio`, `Mcu`, `RadioEvents_t`, and board pin macros: `Vext`, `LED`, `RADIO_DIO_1`, `RADIO_NSS`, `RADIO_RESET`, `RADIO_BUSY`, `LORA_CLK/MISO/MOSI`).

```cpp
void setup() {
  rtc_gpio_hold_dis(GPIO_NUM_7);       // undo any hold left from a previous deep sleep FIRST
  Serial.begin(115200);
  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);  // MUST run before Radio.Init or display.init()
  VextON();                             // power the peripheral rail (OLED/sensors/GPS)
  factory_display.init();
  logo();                               // draw XBM splash from images.h
  attachInterrupt(0, interrupt_GPIO0, FALLING);  // GPIO0 = BOOT button, doubles as test control
  chipid = ESP.getEfuseMac();           // chip ID = MAC, used as LoRa echo payload / report field
  test_status = WIFI_CONNECT_TEST_INIT;
}

void loop() {
  interrupt_handle();
  switch (test_status) {               // sequential state machine, each case falls through once
    case WIFI_CONNECT_TEST_INIT: wifi_connect_init(); test_status = WIFI_CONNECT_TEST;
    case WIFI_CONNECT_TEST:      if (wifi_connect_try(2)) test_status = WIFI_SCAN_TEST; break;
    case WIFI_SCAN_TEST:         wifi_scan(1); test_status = LORA_TEST_INIT; break;
    case LORA_TEST_INIT:         lora_init(); test_status = LORA_COMMUNICATION_TEST; break;
    case LORA_COMMUNICATION_TEST: lora_status_handle(); break;   // stays here, driven by radio IRQs
    case DEEPSLEEP_TEST:         enter_deepsleep(); break;       // triggered by long button press
    case GPS_TEST:                gps_test(); break;             // blocking while(1), terminal state
  }
}
```

The newer boards (RC32, RCC6, Lora32_R8) instead run each test **once, sequentially, inside `setup()`** (IO sweep → WiFi connect → WiFi scan → battery ADC), leave only the LoRa echo running in `loop()`, and emit a machine-parsable pass/fail report at the end — prefer this style for a new bring-up sketch, it's easier to reason about and to hook into CI/bench tooling than the old-style `switch` state machine.

### Button handling — two idioms
1. **ISR + flag**, consumed by a `custom_delay()` helper that breaks out of any wait loop early on GPIO0 falling edge (debounced with `delay(200)` + re-check):
   ```cpp
   void interrupt_GPIO0(void) { interrupt_flag = true; }
   void custom_delay(uint32_t ms) {
     for (uint32_t n = ms/10; n > 0; n--) {
       delay(10);
       if (interrupt_flag) { delay(200); if (digitalRead(0)==0) break; }
     }
   }
   ```
2. **Dedicated FreeRTOS task** polling a button pin, distinguishing short vs. long press by hold duration, used to branch into an alternate sub-test (I2C sensor dump, GPS, SD card) without touching the main loop:
   ```cpp
   void checkUserkey(void *pv) {
     pinMode(USERKEY, INPUT);
     while (1) {
       if (digitalRead(USERKEY) == 0) {
         uint32_t t0 = millis(); delay(10);
         while (digitalRead(USERKEY) == 0) if (millis()-t0 > 2000) break;
         if (millis()-t0 > 2000) { /* long press -> e.g. gps_test() */ }
         else                    { /* short press -> e.g. I2C sensor dump */ }
       }
     }
   }
   xTaskCreateUniversal(checkUserkey, "keyTask", 2048, NULL, 1, &handle, CONFIG_ARDUINO_RUNNING_CORE);
   ```

### Pass/fail reporting — two idioms
- **Display-only** (all display-equipped boards): draw a `String` status line per subsystem with `factory_display.drawString(x, y, s)` then flush (see §4).
- **Serial protocol** (RC32/RCC6, and worth adopting for any new sketch since it's easy to parse from a test jig):
  ```cpp
  Serial.print("FT_START,BOARD=Heltec RC32,FW="); Serial.print(FW_VERSION);
  Serial.print(",ROLE=DUT,CHIPID="); Serial.println(chipIdText);
  // per-test:
  Serial.print("FT_ITEM,"); Serial.print(id); Serial.print(",");
  Serial.print(pass ? "PASS" : "FAIL");
  if (detail.length()) { Serial.print(","); Serial.print(detail); }  // key=val,key=val
  Serial.println();
  // final:
  Serial.print("FT_RESULT,"); Serial.print(allPass ? "PASS" : "FAIL"); /* ...summary fields... */
  ```

## 3. LoRa radio self-test

Ping-pong echo (works standalone, or DUT-vs-tester across two boards on frequencies ~2MHz apart to avoid cross-talk with neighboring benches):

```cpp
RadioEvents_t RadioEvents;
RadioEvents.TxDone = OnTxDone; RadioEvents.TxTimeout = OnTxTimeout; RadioEvents.RxDone = OnRxDone;
Radio.Init(&RadioEvents);
Radio.SetChannel(RF_FREQUENCY);
Radio.SetTxConfig(MODEM_LORA, TX_OUTPUT_POWER, 0, LORA_BANDWIDTH, LORA_SPREADING_FACTOR,
                   LORA_CODINGRATE, LORA_PREAMBLE_LENGTH, LORA_FIX_LENGTH_PAYLOAD_ON,
                   true, 0, 0, LORA_IQ_INVERSION_ON, 3000);
Radio.SetRxConfig(MODEM_LORA, LORA_BANDWIDTH, LORA_SPREADING_FACTOR, LORA_CODINGRATE, 0,
                   LORA_PREAMBLE_LENGTH, LORA_SYMBOL_TIMEOUT, LORA_FIX_LENGTH_PAYLOAD_ON,
                   0, true, 0, 0, LORA_IQ_INVERSION_ON, true);
state = STATE_TX;
// loop(): switch(state) { STATE_TX: Radio.Send(...); state=LOWPOWER; break;
//                          STATE_RX: Radio.Rx(0); state=LOWPOWER; break;
//                          LOWPOWER: Radio.IrqProcess(); break; }
```
Callbacks: `OnTxDone` → `state=STATE_RX`; `OnRxDone(payload,size,rssi,snr)` → copy payload, set `state=STATE_TX` (or compare an embedded chip-ID/echo RSSI against the DUT's own TX RSSI, failing if the delta exceeds ~15-20 dB — that's the actual pass criterion RC32/Lora32_R8 use, not just "a packet arrived").

TX-chain-only test (no RX needed — verifies PA/antenna path by sweeping output power and watching current draw or a spectrum analyzer on the bench):
```cpp
RadioEvents.TxTimeout = OnRadioTxTimeout;  // re-arms the CW below
Radio.Init(&RadioEvents);
for (int power = 28; power <= 32; power += 2) {
  Radio.IrqProcess();
  Radio.SetTxContinuousWave(RF_FREQUENCY, power, TX_TIMEOUT);
  delay(250);
  Radio.Sleep();
  delay(250);
}
```

## 4. Display self-test

- OLED (SSD1306, I2C): `factory_display.clear(); factory_display.drawString(x,y,str); factory_display.display();` — `display()` is required to flush.
- E-ink (`HT_ICMEN2R13EFC1` family): needs an extra buffer-update step before flush: `factory_display.clear(); factory_display.drawXbm(...); factory_display.update(BLACK_BUFFER); factory_display.display();` — forgetting `update(BLACK_BUFFER)` silently no-ops the draw. See the `eink` skill for full-vs-partial refresh detail.
- TFT (ST7735/ST7789): draws immediately, no separate flush call, e.g. `st7735.st7735_fill_screen(ST7735_BLACK); st7735.st7735_write_str(0,0,str);`.
- Logo/splash pattern used everywhere: an XBM bitmap in `images.h` (`logo_width`, `logo_height`, `logo_bits[]`) drawn via `drawXbm(x,y,w,h,bits)`.

## 5. Other peripheral snippets actually used

**Battery ADC** — two idioms seen across boards, pick the second for new work (it's more accurate and self-documenting):
```cpp
// older (Vision_Master/E-ink boards): raw analogRead + fixed coefficient
analogReadResolution(12);
battery_levl = analogRead(7) * 0.000244140625 /*Resolution*/ * 3.3 /*battary_in*/ * 4.01 /*coefficient*/;

// newer (RC32/RCC6): calibrated millivolt read + control-pin gate + averaging + pass-range check
analogReadResolution(12);
pinMode(ADC_BATTERY_CTRL_PIN, OUTPUT); digitalWrite(ADC_BATTERY_CTRL_PIN, HIGH); delay(10);
uint32_t sum = 0;
for (int i = 0; i < ADC_SAMPLE_COUNT; i++) { sum += analogReadMilliVolts(ADC_BATTERY_PIN); delay(2); }
digitalWrite(ADC_BATTERY_CTRL_PIN, LOW); pinMode(ADC_BATTERY_PIN, ANALOG);
uint16_t adcMv = sum / ADC_SAMPLE_COUNT;
uint16_t batMv = adcMv * BATTERY_MULTIPLIER;   // e.g. 4.9f — divider ratio
bool pass = batMv >= ADC_PASS_MIN_MV && batMv <= ADC_PASS_MAX_MV;
```

**I2C bus scan** (used both to find sensors and as a standalone connectivity test):
```cpp
Wire.begin(sda, scl);
for (byte addr = 0x01; addr < 0x7f; addr++) {
  Wire.beginTransmission(addr);
  byte err = Wire.endTransmission();
  if (err == 0) { /* device found at addr */ }
}
```

**Buzzer** (LEDC PWM, used as an audible "boot OK" beep):
```cpp
pinMode(beep_pin, OUTPUT);
ledcAttach(beep_pin, 2000 /*Hz*/, 8 /*resolution bits*/);
for (int i = 0; i < 4; i++) { ledcWrite(beep_pin, 128); delay(250); ledcWrite(beep_pin, 0); delay(250); }
ledcDetach(beep_pin);
```

**GPS** (TinyGPS++ over Serial1; module needs its own power gate driven before UART begins):
```cpp
pinMode(VGNSS_CTRL, OUTPUT); digitalWrite(VGNSS_CTRL, HIGH);  // or LOW — polarity is board-specific
Serial1.begin(9600, SERIAL_8N1, rxPin, txPin);
// in loop(): while (Serial1.available()) gps.encode(Serial1.read());
// then read gps.time.*, gps.location.lat()/lng() once gps.time.second() != 0
```
See the `gps` skill for the full UC6580/NMEA power-sequencing detail on Wireless_Tracker boards.

**GPIO sequential sweep** (RC32/RCC6 — walks every exposed pin HIGH then LOW with a bench operator/probe watching, useful as a cheap continuity test with no extra hardware):
```cpp
for (auto &p : testIoPins) { pinMode(p.pin, OUTPUT); digitalWrite(p.pin, HIGH); Serial.println(p.name); delay(500); }
for (auto &p : testIoPins) { digitalWrite(p.pin, LOW); delay(500); }
```

**Deep sleep exit** (shared teardown across every board — the LoRa SPI pins must be isolated or current leaks during sleep):
```cpp
VextOFF();
Radio.Sleep();
WiFi.disconnect(true); WiFi.mode(WIFI_OFF);
SPI.end();
pinMode(RADIO_NSS_or_PA_PIN, OUTPUT); digitalWrite(RADIO_NSS_or_PA_PIN, LOW);
rtc_gpio_hold_en((gpio_num_t)RADIO_NSS_or_PA_PIN);
rtc_gpio_isolate((gpio_num_t)RADIO_NSS_or_PA_PIN);
pinMode(RADIO_DIO_1, ANALOG); pinMode(RADIO_NSS, ANALOG); pinMode(RADIO_RESET, ANALOG);
pinMode(RADIO_BUSY, ANALOG); pinMode(LORA_CLK, ANALOG); pinMode(LORA_MISO, ANALOG); pinMode(LORA_MOSI, ANALOG);
esp_sleep_enable_timer_wakeup(600 * 1000 * (uint64_t)1000);  // 10 min, µs units
esp_deep_sleep_start();
```

## 6. Gotchas (from real comments and observed behavior)

- `Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE)` must run **before** `Radio.Init()` and before `factory_display.init()` — it resolves the board-specific pin macros (`Vext`, `LED`, `RADIO_*`, `LORA_CLK/MISO/MOSI`) from the Heltec board support package. Skipping/reordering this breaks radio and display init silently on some boards.
- `rtc_gpio_hold_dis(GPIO_NUM_x)` must be called at the very top of `setup()`, before any `pinMode`, for any pin that was `rtc_gpio_hold_en`'d before a previous deep sleep — otherwise `pinMode()`/`digitalWrite()` on that pin is a silent no-op after wake.
- Vext (or its board-specific equivalent — pin 45 on Wireless_Paper, pins 18+46 together on Vision_Master_E290) gates power to the OLED/sensors/GPS, but **polarity is not universal**: some boards' `VextON()` drives the pin LOW, others HIGH — check the board's own example rather than assuming.
- GPIO0 is simultaneously the flashing boot-select pin and the factory-test's control button; its interrupt fires on every bounce, so every consumer debounces with a `delay(200)` + re-check of `digitalRead(0)==0` rather than trusting the first edge.
- The two-channel TX/RX frequency trick (`RF_FREQUENCY_1`/`RF_FREQUENCY_2`, ~1-2 MHz apart) exists so a DUT and its ping-pong partner (or two boards on the same bench) don't talk over themselves.
- Boards without a display (RadioCore_C6, RadioCore_S3R8, RC32, RCC6) do **everything** over Serial — don't assume `factory_display` exists; guard display calls behind a compile-time or runtime capability check if writing one sketch meant to be portable across variants.
- The `BME280` test in `Lora32_R8_V4.3_Exp_Board_HF` has `if (!bme.begin(0x76)) { while(1); }` — an infinite hang on missing/failed hardware. A bring-up sketch that must never brick on absent hardware should replace any `while(1)` failure path with a pass/fail flag and continue to the next test.
- WiFi credentials are hardcoded placeholders (`"Your WiFi SSID"`/`"Your Password"`) in every example; the WiFi test is designed to soft-fail (log FAIL, continue) rather than block the rest of the sequence if no AP is reachable — a full bring-up test should do the same for every subsystem, not stop at the first failure.
- `LORA_FIX_LENGTH_PAYLOAD_ON` / IQ inversion / bandwidth / SF / coding-rate constants are copy-pasted verbatim across nearly all boards (`SF7`, `BW125`, `CR 4/5`, preamble 8) — treat these as the de-facto factory defaults for any new LoRa self-test rather than inventing new ones.

## When to use this skill

Reach for this skill when writing or adapting a **single sketch that exercises multiple peripherals on one Heltec ESP32 board and reports pass/fail** — display, LoRa, WiFi, sensors, GPS, buttons, battery — i.e. hardware bring-up self-test / factory test firmware / board validation. For depth on one specific peripheral, use the narrower project skills instead: `oled`, `eink`, `tft` (display drivers), `gps` (GNSS/NMEA), `sensors` (I2C sensors), `sd-card`, `lora-basic`/`lorawan` (radio), `rf-24g` (WiFi/BLE), `esp32-utilities` (battery/Vext/deep-sleep/I2C-scan/chip-ID helpers), and the per-board skills (`vme213`, `vme290`, `vmt190`, `wireless-paper`) for exact pinouts.
