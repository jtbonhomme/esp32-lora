---
name: sensors
description: Concrete patterns for wiring and reading I2C/digital sensors (BH1750 light, BME280/BMP180/BMP280 pressure-temp-humidity, DA217 accelerometer, DHT11 temp/humidity, GXHTC temp/humidity) on Heltec ESP32 boards, including LoRa transmission of sensor data and displaying readings on the built-in OLED. Use when integrating a sensor library, reading I2C sensors on Heltec, or wiring sensor readings to LoRa/OLED.
version: 1.0.0
---

# Sensor Integration on Heltec ESP32

Patterns extracted from Heltec's official `Sensor` examples. All snippets are taken
almost verbatim from working `.ino` files — reuse them as a starting point rather
than inventing new library APIs.

## When to use this skill

Use this skill whenever the task involves reading a physical sensor on a Heltec
ESP32 board — especially BH1750, BME280, BMP180, BMP280, DA217, DHT11, or GXHTC —
and either printing values to Serial, showing them on the OLED, or sending them
over LoRa.

## Common gotchas (apply to all sensors below)

- **Vext / external power rail:** on Heltec V3-class boards the I2C sensor rail is
  often gated behind the `Vext` control pin. `BME280basic` explicitly drives it:
  ```cpp
  #define VEXT_PIN 36
  pinMode(VEXT_PIN, OUTPUT);
  digitalWrite(VEXT_PIN, HIGH);
  delay(100);  // Wait for power stabilization
  ```
  If a sensor "isn't found" on an otherwise correctly-wired board, check whether
  Vext needs to be enabled first.
- **The onboard OLED already owns I2C bus 0** (`SDA_OLED`/`SCL_OLED`). When adding
  an external I2C sensor alongside the OLED, create a **second `TwoWire` instance**
  instead of sharing/reinitializing the default bus:
  ```cpp
  TwoWire Wire2(1);
  Wire2.begin(41, 42);   // or Wire2.begin(42, 41) — SDA, SCL order varies by wiring
  ```
- **BME280 I2C address conflict:** the sensor ships configured for either `0x76`
  or `0x77` depending on the SDO pin strap. Always try both:
  ```cpp
  if (!bme.begin(0x76, &Wire2)) {
    if (!bme.begin(0x77, &Wire2)) {
      Serial.println("BME280 sensor not found! Check connections.");
      while (1);
    }
  }
  ```
- **DHT11 sampling interval:** the sensor needs at least ~1s between reads; the
  example uses a 2s delay and always checks `dht.getStatus()` before trusting the
  reading.
- **Halt-on-failure pattern:** most examples `while (1);` (or `while (1) {}`) if
  the sensor doesn't initialize, rather than continuing with garbage readings.
  Follow this pattern for hard sensor dependencies.
- **NaN check:** `BME280basic` validates readings with `isnan()` before using them,
  since a flaky I2C read can return `NaN` instead of throwing.

## BH1750 — ambient light (lux), I2C

Library: `BH1750.h` (uses the default global `Wire` bus, address is internal to
the library — not overridden in this example).

```cpp
#include <Wire.h>
#include <BH1750.h>

BH1750 lightMeter;

void setup(){
  Serial.begin(115200);
  lightMeter.begin();
}

void loop() {
  float lux = lightMeter.readLightLevel();
  Serial.print("Light: ");
  Serial.print(lux);
  Serial.println(" lx");
  delay(1000);
}
```

## BME280 — temperature / pressure / humidity, I2C

Library: `Adafruit_BME280.h`. Init takes an explicit I2C address plus an optional
`TwoWire*` when using a secondary bus. Configure oversampling with `setSampling`.

```cpp
#include <Wire.h>
#include <Adafruit_BME280.h>

#define BME_SDA 41
#define BME_SCL 42
TwoWire bmeWire(1);
Adafruit_BME280 bme;

void setup() {
  bmeWire.begin(BME_SDA, BME_SCL);

  if (bme.begin(0x76, &bmeWire)) {
    Serial.println("BME280 found at address 0x76");
  } else if (bme.begin(0x77, &bmeWire)) {
    Serial.println("BME280 found at address 0x77");
  } else {
    Serial.println("Could not find BME280 sensor!");
    while (1);
  }

  bme.setSampling(
    Adafruit_BME280::MODE_NORMAL,
    Adafruit_BME280::SAMPLING_X2,     // Temperature
    Adafruit_BME280::SAMPLING_X16,    // Pressure
    Adafruit_BME280::SAMPLING_X1,     // Humidity
    Adafruit_BME280::FILTER_OFF,      // or FILTER_X16
    Adafruit_BME280::STANDBY_MS_1000  // or STANDBY_MS_500
  );
}

void loop() {
  float temperature = bme.readTemperature();          // Celsius
  float pressure = bme.readPressure() / 100.0F;        // Pa -> hPa
  float humidity = bme.readHumidity();                 // %
  if (isnan(temperature) || isnan(pressure) || isnan(humidity)) {
    Serial.println("Error: Failed to read from sensor!");
    return;
  }
  float altitude = bme.readAltitude(1013.25);           // sea-level ref hPa
}
```

## BMP180 — pressure / temperature / altitude, I2C (uses `Heltec.begin`/OLED)

Library: `BMP180.h`, class `BMP085`. This example also drives the OLED through the
`heltec.h` helper (`Heltec.begin(...)` / `Heltec.display`) instead of a raw
`SSD1306Wire` instance — an alternate, higher-level API for the same display.

```cpp
#include "heltec.h"
#include <Wire.h>
#include <BMP180.h>

BMP085 bmp;

void loop() {
  if (!bmp.begin()) {
    Serial.println("Could not find a valid BMP085 sensor, check wiring!");
    while (1) {}
  }
  double T = bmp.readTemperature();          // *C
  double P = bmp.readPressure();             // Pa
  double A = bmp.readAltitude();             // meters, standard sea-level 101325 Pa
  double R = bmp.readAltitude(101500);       // meters, given local sea-level pressure

  Heltec.begin(true /*Display*/, false /*LoRa*/, true /*Serial*/);
  Heltec.display->clear();
  Heltec.display->setTextAlignment(TEXT_ALIGN_LEFT);
  Heltec.display->setFont(ArialMT_Plain_10);
  Heltec.display->drawString(0, 0, "Temperature =");
  Heltec.display->drawString(76, 0, (String)T);
  Heltec.display->display();
}
```
Note: this example calls `bmp.begin()` and `Heltec.begin()` from inside `loop()`,
which is unusual (normally these belong in `setup()`) — worth cleaning up if reused.

## BMP280 — pressure / temperature, I2C (single-bus and dual-bus variants)

Library: `BMP280.h`. Two styles seen: default `Wire` bus, or an explicit
`TwoWire` passed into the constructor.

Single-bus (`bmp280.ino`):
```cpp
#include <Wire.h>
#include <BMP280.h>

BMP280 bmp;

void setup() {
  Wire.begin(42, 41);   // SDA, SCL
  bmp.begin();
  bmp.setSampling(BMP280::MODE_NORMAL,
                  BMP280::SAMPLING_X2,     // Temp oversampling
                  BMP280::SAMPLING_X16,    // Pressure oversampling
                  BMP280::FILTER_X16,
                  BMP280::STANDBY_MS_500);
}

void loop() {
  float temp = bmp.readTemperature();
  float Pressure = (float)bmp.readPressure() / 100.0;
}
```

Dual-bus + OLED variant (`Sensor_OLED.ino`) — pass the secondary `TwoWire` straight
into the sensor constructor:
```cpp
TwoWire Wire2(1);
BMP280 bmp(&Wire2);
static SSD1306Wire display(0x3c, 500000, SDA_OLED, SCL_OLED, GEOMETRY_128_64, RST_OLED);

void setup() {
  Wire2.begin(42, 41);
  if (!bmp.begin()) {
    Serial.println("Sensor not found!");
    while (1);
  }
  bmp.setSampling(BMP280::MODE_NORMAL, BMP280::SAMPLING_X2,
                  BMP280::SAMPLING_X16, BMP280::FILTER_X16,
                  BMP280::STANDBY_MS_500);

  display.init();
  display.clear();
  display.display();
  display.setContrast(255);
  display.setFont(ArialMT_Plain_10);
  display.setTextAlignment(TEXT_ALIGN_LEFT);
}
```

## DA217 — 3-axis accelerometer, I2C

Library: `da217.h`, class `DA217`. Simple polling API, no address/bus configuration
shown (uses the library's internal default).

```cpp
#include "da217.h"

DA217 da217;
float x_data, y_data, z_data, sum_gravity;

void setup() {
  Serial.begin(115200);
  da217.da217_gravity_init();
}

void loop() {
  da217.da217_get_xyz_gravity(&x_data, &y_data, &z_data);
  da217.da217_get_vector_sum_gravity(&sum_gravity);
  Serial.printf("x_data=%f  y_data=%f z_data=%f  %f\r\n", x_data, y_data, z_data, sum_gravity);
  delay(3000);
}
```

## GXHTC — temperature / humidity, I2C

Library: `GXHTC.h`, class `GXHTC`. Note `begin()` takes two pin-like args
(SDA, SCL order per the example) and exposes readings as public fields rather than
getter methods.

```cpp
#include "Wire.h"
#include "GXHTC.h"

GXHTC gxhtc;

void setup() {
  Serial.begin(115200);
  gxhtc.begin(1, 2);
}

void loop() {
  gxhtc.read_data();
  Serial.print("Temperature:"); Serial.print(gxhtc.g_temperature);
  Serial.print("  Humidity:");  Serial.println(gxhtc.g_humidity);
  Serial.printf("id = %X\r\n", gxhtc.read_id());
  delay(3000);
}
```

## DHT11 — temperature / humidity, single-wire digital, combined with LoRa TX

Library: `DHTesp.h`. This example (`DHT11_LoRa_sender.ino`) is the reference
pattern for **reading a sensor and transmitting it over LoRa** using the
`LoRaWan_APP.h` radio stack (`Mcu.begin` + `Radio.*`), the same primitives as this
repo's `lora-basic` skill.

```cpp
#include <DHTesp.h>
#include "LoRaWan_APP.h"

#define DHT_PIN 1   // avoid GPIO0/1 conflicts with boot/UART pins on your board
DHTesp dht;

#define RF_FREQUENCY 915000000
#define TX_OUTPUT_POWER 14
#define LORA_BANDWIDTH 0
#define LORA_SPREADING_FACTOR 7
#define LORA_CODINGRATE 1
#define LORA_PREAMBLE_LENGTH 8
#define BUFFER_SIZE 50
char txpacket[BUFFER_SIZE];
bool lora_idle = true;
static RadioEvents_t RadioEvents;

void setup() {
  dht.setup(DHT_PIN, DHTesp::DHT11);

  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);
  RadioEvents.TxDone = OnTxDone;
  RadioEvents.TxTimeout = OnTxTimeout;
  Radio.Init(&RadioEvents);
  Radio.SetChannel(RF_FREQUENCY);
  Radio.SetTxConfig(MODEM_LORA, TX_OUTPUT_POWER, 0, LORA_BANDWIDTH,
                     LORA_SPREADING_FACTOR, LORA_CODINGRATE,
                     LORA_PREAMBLE_LENGTH, false, true, 0, 0, false, 3000);
}

void loop() {
  if (lora_idle) {
    delay(2000); // DHT11 requires at least 1-second sampling interval

    TempAndHumidity data = dht.getTempAndHumidity();
    if (dht.getStatus() != DHTesp::ERROR_NONE) {
      Serial.println("DHT11 read failed: " + String(dht.getStatusString()));
      return;
    }

    // Encode as a compact JSON string before sending over the air
    snprintf(txpacket, BUFFER_SIZE, "{\"t\":%.1f,\"h\":%.1f}",
             data.temperature, data.humidity);

    Radio.Send((uint8_t *)txpacket, strlen(txpacket));
    lora_idle = false;
  }
  Radio.IrqProcess();
}

void OnTxDone(void) {
  Serial.println("LoRa transmission successful");
  lora_idle = true;
}

void OnTxTimeout(void) {
  Radio.Sleep();
  Serial.println("LoRa transmission timeout");
  lora_idle = true;
}
```
Key pattern: gate the read+send cycle on a `lora_idle` flag set by the `TxDone`/
`TxTimeout` callbacks, so a new reading is only taken/sent once the radio has
finished the previous transmission. Call `Radio.IrqProcess()` every loop iteration
regardless.

## Showing readings on the OLED (`Sensor_OLED`, `BME280_OLED`)

Both patterns use `HT_SSD1306Wire.h`'s `SSD1306Wire` class directly (not the
`Heltec.display` helper used by BMP180), constructed with the board's OLED I2C
address/pins:

```cpp
#include "HT_SSD1306Wire.h"

static SSD1306Wire display(0x3c, 500000, SDA_OLED, SCL_OLED, GEOMETRY_128_64, RST_OLED);

void setup() {
  display.init();
  display.clear();
  display.display();
  display.setContrast(255);
  display.setFont(ArialMT_Plain_10);
  display.setTextAlignment(TEXT_ALIGN_LEFT);
  display.drawString(0, 0, "BME280 Sensor Test");
  display.display();
}

void loop() {
  float temp = bme.readTemperature();
  float pressure = bme.readPressure() / 100.0;
  float humidity = bme.readHumidity();

  display.clear();
  display.drawString(0, 0,  "BME280 Sensor");
  display.drawString(0, 15, "Temp: "  + String(temp, 1)     + " C");
  display.drawString(0, 30, "Press: " + String(pressure, 1) + " hPa");
  display.drawString(0, 45, "Humid: " + String(humidity, 1) + " %");
  display.display();

  delay(3000); // refresh every 3s — no need to redraw faster than this
}
```
Formatting notes: values are rounded to 1 decimal place with `String(value, 1)`
before concatenation, one measurement per line at ~15px vertical spacing
(0, 15, 30, 45 for `ArialMT_Plain_10`), and `display.clear()` is always called
before redrawing to avoid overlapping text from the previous frame. Always call
`display.display()` after drawing — nothing appears on the panel until then.

## Cross-cutting integration recipe

To combine a new sensor with both OLED display and LoRa transmission:
1. `Wire2.begin(sda, scl)` for the sensor bus if the onboard OLED already uses bus 0.
2. Enable `Vext` first if the board gates sensor power.
3. Initialize the sensor with address-fallback + `while(1)` halt on failure.
4. Initialize the OLED via `SSD1306Wire` (or `Heltec.begin(true, false, true)` for
   the simpler helper) if a screen is needed.
5. Initialize the radio via `Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE)` + `Radio.Init`
   + `Radio.SetTxConfig` if LoRa TX is needed (see this repo's `lora-basic` skill
   for the full radio config).
6. In `loop()`: read sensor -> validate (NaN / status check) -> update OLED text ->
   format packet -> `Radio.Send()` gated on `lora_idle` -> always call
   `Radio.IrqProcess()`.
