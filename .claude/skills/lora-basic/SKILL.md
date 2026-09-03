---
name: lora-basic
description: Concrete patterns for raw point-to-point LoRa radio firmware (NOT LoRaWAN) on Heltec ESP32 boards, using the Radio/RadioEvents_t hardware API directly - Radio.Init/SetTxConfig/SetRxConfig/Send/Rx, OnTxDone/OnRxDone callbacks, Radio.IrqProcess() in loop(), TX/RX send-receive, ping-pong turnaround, TX power tuning/continuous wave, and LoRa-DIO1-triggered deep sleep wakeup. Use when writing/reviewing firmware that talks to the SX126x radio directly instead of through the LoRaWAN stack.
version: 1.0.0
---

# LoRa Basic (raw point-to-point radio)

Patterns extracted from Heltec's `LoRaBasic` example folder (`LoRaSender`, `LoRaReceiver`, `LoRaSenderShow`, `LoRaReceiverShow`, `pingpong`, `TxPowerTest`, `LoRaPowerTest`, `DeepSleepWakeUpByLora`). Per Heltec's own README for that folder: **"All examples in this path just directly call the SX1262 hardware layer to transmit LoRa signals, and do not include any operations with protocol layer."** This is the raw radio driver API (`Radio.*` from `LoRaWan_APP.h`), not the LoRaWAN MAC/join/session stack.

## When to use this skill

Use this when the task is point-to-point LoRa radio communication between two or more Heltec ESP32 boards with no gateway/network server involved: simple sender/receiver links, ping-pong latency/link tests, TX power calibration, or a node that sleeps and wakes only when a LoRa packet arrives. Do NOT use this for LoRaWAN (OTAA/ABP join, `LoRaWAN_APP.h` join/session functions, TTN/ChirpStack) - that is a different API surface and belongs in a separate LoRaWAN skill.

## Core radio API pattern

Every example follows the same shape:

1. `#include "LoRaWan_APP.h"` and `#include "Arduino.h"`.
2. Define a block of LoRa PHY parameters as `#define`s.
3. Declare a `static RadioEvents_t RadioEvents;` and assign only the callbacks you need (`TxDone`, `TxTimeout`, `RxDone`, `RxTimeout`, `RxError`...).
4. In `setup()`: `Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);` then `Radio.Init(&RadioEvents)`, `Radio.SetChannel(RF_FREQUENCY)`, and `Radio.SetTxConfig(...)` and/or `Radio.SetRxConfig(...)`.
5. In `loop()`: drive the state machine (kick off `Radio.Send()` or `Radio.Rx()` when idle) and **always call `Radio.IrqProcess();` on every loop iteration** - this is what actually dispatches the `RadioEvents` callbacks; without it TxDone/RxDone never fire.

### Standard LoRa parameter block (from LoRaSender.ino)

```cpp
#define RF_FREQUENCY                                915000000 // Hz

#define TX_OUTPUT_POWER                             5         // dBm

#define LORA_BANDWIDTH                              0         // [0: 125 kHz,
                                                              //  1: 250 kHz,
                                                              //  2: 500 kHz,
                                                              //  3: Reserved]
#define LORA_SPREADING_FACTOR                       7         // [SF7..SF12]
#define LORA_CODINGRATE                             1         // [1: 4/5,
                                                              //  2: 4/6,
                                                              //  3: 4/7,
                                                              //  4: 4/8]
#define LORA_PREAMBLE_LENGTH                        8         // Same for Tx and Rx
#define LORA_SYMBOL_TIMEOUT                         0         // Symbols
#define LORA_FIX_LENGTH_PAYLOAD_ON                  false
#define LORA_IQ_INVERSION_ON                        false

#define RX_TIMEOUT_VALUE                            1000
#define BUFFER_SIZE                                 30 // Define the payload size here
```

`RF_FREQUENCY` varies by example/region: `915000000` (US/most examples), `868000000` (`TxPowerTest`, EU-ish), `865000000` (`pingpong`, IN865-ish). **Both ends of a link must use the exact same frequency and PHY params (bandwidth, SF, coding rate).**

### Sender setup + send (LoRaSender.ino)

```cpp
char txpacket[BUFFER_SIZE];
double txNumber;
bool lora_idle = true;
static RadioEvents_t RadioEvents;

void setup() {
    Serial.begin(115200);
    Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);
    txNumber = 0;

    RadioEvents.TxDone = OnTxDone;
    RadioEvents.TxTimeout = OnTxTimeout;

    Radio.Init(&RadioEvents);
    Radio.SetChannel(RF_FREQUENCY);
    Radio.SetTxConfig(MODEM_LORA, TX_OUTPUT_POWER, 0, LORA_BANDWIDTH,
                       LORA_SPREADING_FACTOR, LORA_CODINGRATE,
                       LORA_PREAMBLE_LENGTH, LORA_FIX_LENGTH_PAYLOAD_ON,
                       true, 0, 0, LORA_IQ_INVERSION_ON, 3000);
}

void loop() {
    if (lora_idle == true) {
        delay(1000);
        txNumber += 0.01;
        sprintf(txpacket, "Hello world number %0.2f", txNumber);
        Serial.printf("\r\nsending packet \"%s\" , length %d\r\n", txpacket, strlen(txpacket));
        Radio.Send((uint8_t *)txpacket, strlen(txpacket));
        lora_idle = false;
    }
    Radio.IrqProcess();
}

void OnTxDone(void) {
    Serial.println("TX done......");
    lora_idle = true;
}

void OnTxTimeout(void) {
    Radio.Sleep();
    Serial.println("TX Timeout......");
    lora_idle = true;
}
```

### Receiver setup + receive (LoRaReceiver.ino)

```cpp
char rxpacket[BUFFER_SIZE];
int16_t rssi, rxSize;
bool lora_idle = true;
static RadioEvents_t RadioEvents;

void setup() {
    Serial.begin(115200);
    Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);

    RadioEvents.RxDone = OnRxDone;
    Radio.Init(&RadioEvents);
    Radio.SetChannel(RF_FREQUENCY);
    Radio.SetRxConfig(MODEM_LORA, LORA_BANDWIDTH, LORA_SPREADING_FACTOR,
                       LORA_CODINGRATE, 0, LORA_PREAMBLE_LENGTH,
                       LORA_SYMBOL_TIMEOUT, LORA_FIX_LENGTH_PAYLOAD_ON,
                       0, true, 0, 0, LORA_IQ_INVERSION_ON, true);
}

void loop() {
    if (lora_idle) {
        lora_idle = false;
        Serial.println("into RX mode");
        Radio.Rx(0); // 0 = no RX timeout, listen continuously
    }
    Radio.IrqProcess();
}

void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr) {
    rxSize = size;
    memcpy(rxpacket, payload, size);
    rxpacket[size] = '\0';
    Radio.Sleep(); // put radio back to sleep before re-arming RX
    Serial.printf("\r\nreceived packet \"%s\" with rssi %d , length %d\r\n", rxpacket, rssi, rxSize);
    lora_idle = true; // loop() will call Radio.Rx(0) again
}
```

Note: always `memcpy` the payload out and NUL-terminate into your own buffer inside `OnRxDone` - the `payload` pointer is only valid for the duration of the callback (it's the radio driver's internal RX buffer).

## Sender/Receiver "Show" variants (OLED/TFT display)

`LoRaSenderShow.ino` / `LoRaReceiverShow.ino` are the same TX/RX pattern above, plus board-specific display output gated by preprocessor board defines:

```cpp
#if defined(WIRELESS_TRACKER_V2)
  HT_st7735 st7735;
#endif
#if defined(WIFI_LORA_32_V3) || defined(WIFI_LORA_32_V2)
  SSD1306Wire factory_display(0x3c, 500000, SDA_OLED, SCL_OLED, GEOMETRY_128_64, RST_OLED);
#endif
```

For the SSD1306 OLED boards, the display's I2C power rail (`Vext`) must be explicitly enabled before `factory_display.init()`:

```cpp
pinMode(Vext, OUTPUT);
digitalWrite(Vext, LOW);   // LOW = Vext ON on these boards
delay(100);
factory_display.init();
```

`LoRaSenderShow` stops after 100 sent packets (`if (num >= 100) { ... while(1) delay(1000); }`) - a simple bounded burn-in/test pattern. `LoRaReceiverShow` accumulates running RSSI/SNR averages and prints/display them every 10 received packets:

```cpp
int32_t rec_num_all = 0, rec_rssi_all = 0, rec_snr_all = 0;
// in OnRxDone:
rec_rssi_all += rssi; rec_snr_all += snr; rec_num_all++;
// in loop(), before re-arming RX:
if (rec_num_all > 0 && ((rec_num_all % 10 == 0) || (rec_num_all > 90))) {
    snprintf(show_buf, 60, "num:%03d,rssi:%04d,snr:%03d",
             rec_num_all, rec_rssi_all / rec_num_all, rec_snr_all / rec_num_all);
    // draw show_buf to display
}
```

## Ping-pong: send/receive turnaround as a state machine

`pingpong.ino` is the reference pattern for bidirectional (half-duplex) exchange - the same sketch flashed to both boards, alternating TX and RX:

```cpp
typedef enum { LOWPOWER, STATE_RX, STATE_TX } States_t;
States_t state;

void setup() {
    ...
    RadioEvents.TxDone = OnTxDone;
    RadioEvents.TxTimeout = OnTxTimeout;
    RadioEvents.RxDone = OnRxDone;

    Radio.Init(&RadioEvents);
    Radio.SetChannel(RF_FREQUENCY);
    Radio.SetTxConfig(MODEM_LORA, TX_OUTPUT_POWER, 0, LORA_BANDWIDTH,
                       LORA_SPREADING_FACTOR, LORA_CODINGRATE,
                       LORA_PREAMBLE_LENGTH, LORA_FIX_LENGTH_PAYLOAD_ON,
                       true, 0, 0, LORA_IQ_INVERSION_ON, 3000);
    Radio.SetRxConfig(MODEM_LORA, LORA_BANDWIDTH, LORA_SPREADING_FACTOR,
                       LORA_CODINGRATE, 0, LORA_PREAMBLE_LENGTH,
                       LORA_SYMBOL_TIMEOUT, LORA_FIX_LENGTH_PAYLOAD_ON,
                       0, true, 0, 0, LORA_IQ_INVERSION_ON, true);
    state = STATE_TX; // one side must start as TX so the link kicks off
}

void loop() {
    switch (state) {
        case STATE_TX:
            delay(1000);
            txNumber++;
            sprintf(txpacket, "hello %d, Rssi : %d", txNumber, Rssi);
            Radio.Send((uint8_t *)txpacket, strlen(txpacket));
            state = LOWPOWER; // wait for TxDone/TxTimeout callback to move state on
            break;
        case STATE_RX:
            Radio.Rx(0);
            state = LOWPOWER; // wait for RxDone callback to move state on
            break;
        case LOWPOWER:
            Radio.IrqProcess(); // only this dispatches callbacks that advance state
            break;
    }
}

void OnTxDone(void) { state = STATE_RX; }        // after sending, go listen for the reply
void OnTxTimeout(void) { Radio.Sleep(); state = STATE_TX; } // retry TX on timeout
void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr) {
    Rssi = rssi;
    memcpy(rxpacket, payload, size); rxpacket[size] = '\0';
    Radio.Sleep();
    state = STATE_TX; // after receiving, send the next ping/pong back
}
```

Key mechanics: `state` transitions to `LOWPOWER` immediately after issuing `Radio.Send`/`Radio.Rx`, and only the interrupt-driven callbacks (fired via `Radio.IrqProcess()`) move it out of `LOWPOWER` again. This avoids busy-driving the radio and lets one `Radio.IrqProcess()` call in the `LOWPOWER` case do all the waiting. Because both boards run identical code and one naturally transmits first (`state = STATE_TX` in `setup()`), the two nodes settle into an alternating TX/RX rhythm automatically - this is the turnaround mechanism to imitate for any request/response LoRa protocol.

## TX power tuning

Two distinct examples cover power characterization vs. runtime adjustment.

**`TxPowerTest.ino`** - unmodulated continuous-wave carrier for measuring actual transmit power with a spectrum analyzer / power meter (no packets sent, nothing decodable):

```cpp
#define RF_FREQUENCY     868000000 // Hz
#define TX_OUTPUT_POWER  10        // dBm  (comment in the file says "20 dBm" - the comment is stale, the value used is 10)
#define TX_TIMEOUT       10        // seconds (MAX value)

void OnRadioTxTimeout(void) {
    // Restarts continuous wave transmission when timeout expires
    Radio.SetTxContinuousWave(RF_FREQUENCY, TX_OUTPUT_POWER, TX_TIMEOUT);
}

void setup() {
    Serial.begin(115200);
    Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);
    RadioEvents.TxTimeout = OnRadioTxTimeout;
    Radio.Init(&RadioEvents);
    Radio.SetTxContinuousWave(RF_FREQUENCY, TX_OUTPUT_POWER, TX_TIMEOUT);
}

void loop() {
    Radio.IrqProcess();
}
```

Gotcha: `TX_TIMEOUT` of "seconds (MAX value)" is called out in the comment - continuous wave transmission is capped and self-restarts via `OnRadioTxTimeout`, it isn't a truly infinite carrier.

**`LoRaPowerTest.ino`** - interactive TX power adjustment at runtime via the board's PRG/GPIO0 button, re-applying `Radio.SetTxConfig` with an incremented power each press, and reflecting the current value on the OLED/TFT:

```cpp
int8_t power = TX_OUTPUT_POWER;
volatile bool interrupt_flag = false;

void interrupt_GPIO0(void) { interrupt_flag = true; }

void interrupt_handle(void) {
    if (interrupt_flag) {
        interrupt_flag = false;
        if (digitalRead(0) == 0) {
            delay(500); // debounce
            if (digitalRead(0) == 0) {
                power += 1;
                Radio.SetTxConfig(MODEM_LORA, power, 0, LORA_BANDWIDTH,
                                   LORA_SPREADING_FACTOR, LORA_CODINGRATE,
                                   LORA_PREAMBLE_LENGTH, LORA_FIX_LENGTH_PAYLOAD_ON,
                                   true, 0, 0, LORA_IQ_INVERSION_ON, 3000);
                // ... update display with new power value
            }
        }
    }
}

void setup() {
    ...
    attachInterrupt(0, interrupt_GPIO0, FALLING); // GPIO0 = PRG button
    ...
}

void loop() {
    interrupt_handle(); // called from inside the lora_idle branch, not the ISR itself
    ...
}
```

Gotcha: the ISR (`interrupt_GPIO0`) only sets a flag - the actual button debounce, `digitalRead`, and `Radio.SetTxConfig` call happen later in `loop()` via `interrupt_handle()`. Never call `Radio.*` or do heavy work directly inside the GPIO ISR.

Power value ranges are not asserted in code - respect your board/module's PA limits and local regulatory max EIRP (these examples use 0-22 dBm depending on the sketch; SX126x boards commonly top out around 22 dBm).

## LoRa-triggered deep sleep wakeup

`DeepSleepWakeUpByLora.ino` is a receiver that goes to deep sleep and is woken by the SX126x's DIO1 pin toggling on packet reception (RX interrupt), rather than by a timer.

```cpp
#include "driver/rtc_io.h"

uint32_t enter_deepsleep_number = 0;

void setup() {
#if defined(WIFI_LORA_32_V4) && defined(USE_GC1109_PA)
    rtc_gpio_hold_dis((gpio_num_t)LORA_PA_EN);   // release any RTC GPIO hold left from a previous deep sleep
#elif defined(WIRELESS_TRACKER_V2) || (defined(WIFI_LORA_32_V4) && defined(USE_KCT8103L_PA))
    rtc_gpio_hold_dis((gpio_num_t)LORA_PA_CSD);
#endif
    Serial.begin(115200);
    Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);
    print_wakeup_reason(); // esp_sleep_get_wakeup_cause() -> EXT0/EXT1/TIMER/TOUCHPAD/ULP

    RadioEvents.RxDone = OnRxDone;
    Radio.Init(&RadioEvents);
    Radio.SetChannel(RF_FREQUENCY);
    Radio.SetRxConfig(MODEM_LORA, LORA_BANDWIDTH, LORA_SPREADING_FACTOR,
                       LORA_CODINGRATE, 0, LORA_PREAMBLE_LENGTH,
                       LORA_SYMBOL_TIMEOUT, LORA_FIX_LENGTH_PAYLOAD_ON,
                       0, true, 0, 0, LORA_IQ_INVERSION_ON, true);
}

void loop() {
    if (lora_idle) {
        lora_idle = false;
        Radio.Rx(0);
    }
    Radio.IrqProcess();

    if (enter_deepsleep_number >= 5) { // after 5 packets received, go to sleep
        Radio.Rx(0); // re-arm RX so DIO1 will fire again on the next packet
        // hold the PA-enable pin state across sleep so the radio front-end stays in RX-capable state
#if defined(WIFI_LORA_32_V4) && defined(USE_GC1109_PA)
        pinMode(LORA_PA_EN, OUTPUT);
        digitalWrite(LORA_PA_EN, HIGH);
        rtc_gpio_hold_en((gpio_num_t)LORA_PA_EN);
#elif defined(WIRELESS_TRACKER_V2) || (defined(WIFI_LORA_32_V4) && defined(USE_KCT8103L_PA))
        pinMode(LORA_PA_CSD, OUTPUT);
        digitalWrite(LORA_PA_CSD, HIGH);
        rtc_gpio_hold_en((gpio_num_t)LORA_PA_CSD);
#endif
        esp_sleep_enable_ext0_wakeup((gpio_num_t)RADIO_DIO_1, 1); // wake on DIO1 going HIGH
        rtc_gpio_pullup_dis((gpio_num_t)RADIO_DIO_1);
        rtc_gpio_pulldown_en((gpio_num_t)RADIO_DIO_1);
        Serial.println("Going to sleep now");
        delay(1000);
        esp_deep_sleep_start(); // execution never returns past this line; chip resets and re-runs setup() on wake
    }
}

void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr) {
    memcpy(rxpacket, payload, size);
    rxpacket[size] = '\0';
    Radio.Sleep();
    lora_idle = true;
    enter_deepsleep_number++;
}
```

Deep sleep + LoRa wakeup gotchas:
- The wake source is `esp_sleep_enable_ext0_wakeup((gpio_num_t)RADIO_DIO_1, 1)` - EXT0 wakeup on the radio's DIO1 pin going HIGH (level 1). `RADIO_DIO_1` is the board-defined GPIO wired to the SX126x's DIO1 line.
- Configure the DIO1 RTC pin explicitly with `rtc_gpio_pullup_dis()` + `rtc_gpio_pulldown_en()` before sleeping, so it has a defined idle level and doesn't false-trigger.
- On boards with an external PA that has an enable/CSD pin controlled by a normal GPIO (`LORA_PA_EN` / `LORA_PA_CSD`, board- and PA-chip-specific via `USE_GC1109_PA`/`USE_KCT8103L_PA` defines), that pin's state must be held across deep sleep with `rtc_gpio_hold_en()` before `esp_deep_sleep_start()`, and the hold must be released with `rtc_gpio_hold_dis()` at the very top of `setup()` on the next boot - otherwise the PA state from before sleep is stuck/undefined after wake.
- After `esp_deep_sleep_start()`, execution does not resume in `loop()` - the chip fully resets and `setup()` runs again from scratch; use `esp_sleep_get_wakeup_cause()` in `setup()` (see `print_wakeup_reason()`) to distinguish "woke from LoRa RX" from a fresh power-on.
- Deep sleep here is entered only after the radio has already been armed to `Radio.Rx(0)` again immediately beforehand, so the DIO1 IRQ line is in the correct state to trigger EXT0 wakeup on the next incoming packet.

## Board init and general gotchas

- Every example calls `Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE)` (note the library's typo `TPYE`, not `TYPE`) right after `Serial.begin(...)` and before touching `Radio.*` - this initializes the Heltec board abstraction (clocks, power rails) that the SX126x driver depends on.
- `Radio.IrqProcess()` must be called every single `loop()` iteration unconditionally (not just when "idle") - it is what services the radio's interrupt and dispatches `RadioEvents` callbacks (`OnTxDone`, `OnRxDone`, `OnTxTimeout`, etc.). Forgetting it means callbacks silently never fire and the state machine hangs.
- Both TX and RX sides must agree on `RF_FREQUENCY`, `LORA_BANDWIDTH`, `LORA_SPREADING_FACTOR`, `LORA_CODINGRATE`, and `LORA_PREAMBLE_LENGTH`, or packets will not be decoded even though nothing errors visibly.
- `Radio.Rx(0)` with timeout `0` means listen indefinitely (no RX timeout); a non-zero value in milliseconds arms `RxTimeout` after that window.
- `Radio.Sleep()` is called at the end of every `OnRxDone`/`OnTxTimeout` before the main loop re-arms TX/RX again - always park the radio in a known sleep state between operations rather than chaining `Radio.Send`/`Radio.Rx` calls directly from inside a callback.
- `payload`/`size` in `OnRxDone` point into the driver's internal buffer - copy out immediately (`memcpy` into your own `rxpacket`) and NUL-terminate if you're going to treat it as a C string.
- `RF_FREQUENCY` must be set for your regulatory region (these examples use 915 MHz, 868 MHz, and 865 MHz across different files/regions) and `TX_OUTPUT_POWER` must respect your region's/board's legal and hardware max EIRP.
