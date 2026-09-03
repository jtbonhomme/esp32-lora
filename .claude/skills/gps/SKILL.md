---
name: gps
description: Read and parse location data from a UC6580/u-blox-style GNSS module over UART on Heltec ESP32 boards (Wireless Tracker / tracker_v1), using TinyGPS++ NMEA parsing, GNSS power control, and UFirebird reset commands. Use when the user mentions GPS, GNSS, NMEA, UC6580, TinyGPS, or reading location/lat-lon on a Heltec ESP32 board.
version: 1.0.0
---

# Heltec ESP32 GNSS/GPS (UC6580) Integration

When to use this skill: the user wants to read a GNSS/GPS module (UC6580 or similar) wired to a Heltec ESP32 board (e.g. Wireless Tracker V1/V2) over UART, parse NMEA sentences into lat/lon/time, print it to Serial, show it on a TFT, or send reset/clear commands to the receiver.

These patterns are extracted from three real examples in `Heltec_ESP32/examples/GPS`: `GPSToUart` (serial-only GPS logger), `GPSDisplayOnTFT` (GPS + ST7735 TFT display), and `UC6580_Clear_All` (raw UART command/ACK protocol to cold-reset the receiver). All three target `tracker_v1`/`Wireless_Tracker_V2_FactoryTest` boards — **pin numbers must be adjusted for other boards.**

## Hardware wiring (tracker_v1 / Wireless Tracker V2)

- GNSS power enable pin: **GPIO 3**, driven `HIGH` to power on the module.
- GNSS UART: **Serial1**, RX = GPIO 33, TX = GPIO 34, **115200 baud, SERIAL_8N1**.
- The GNSS chip needs its power pin explicitly enabled before UART traffic will appear — always `pinMode(OUTPUT)` + `digitalWrite(HIGH)` before `Serial1.begin(...)`.

```cpp
#define VGNSS_CTRL 3
pinMode(VGNSS_CTRL, OUTPUT);
digitalWrite(VGNSS_CTRL, HIGH);
Serial1.begin(115200, SERIAL_8N1, 33, 34);
```

## Example 1 — `GPSToUart`: minimal NMEA parse + Serial log

Demonstrates the bare-minimum pattern: power the GNSS, feed raw UART bytes into TinyGPS++ char-by-char, and print decoded time/lat/lon over USB Serial whenever a full NMEA line (`\n`) has been consumed.

Key include and object:
```cpp
#include "Arduino.h"
#include "HT_TinyGPS++.h"

TinyGPSPlus GPS;
```

Parsing loop pattern — feed bytes to `GPS.encode()` one at a time, and only read out fields once a newline is seen (end of an NMEA sentence):
```cpp
while (1) {
  if (Serial1.available() > 0) {
    if (Serial1.peek() != '\n') {
      GPS.encode(Serial1.read());
    } else {
      Serial1.read();                     // consume the '\n'
      if (GPS.time.second() == 0) {
        continue;                         // no valid fix parsed yet, skip
      }
      Serial.printf(" %02d:%02d:%02d.%02d",
        GPS.time.hour(), GPS.time.minute(), GPS.time.second(), GPS.time.centisecond());
      Serial.print("LAT: "); Serial.print(GPS.location.lat(), 6);
      Serial.print(", LON: "); Serial.print(GPS.location.lng(), 6);
      Serial.println();

      delay(5000);
      while (Serial1.read() > 0);         // drain any buffered bytes before resuming
    }
  }
}
```
Note: this example runs its whole GPS loop inside `GPS_test()`, called once from `setup()` — `loop()` is left basically empty (`delay(100)`). It is a blocking, single-purpose demo, not designed to run concurrently with other logic.

## Example 2 — `GPSDisplayOnTFT`: same parsing, rendered to ST7735 TFT

Identical NMEA parsing pattern to `GPSToUart`, but renders to a Heltec ST7735 TFT instead of Serial. Adds `HT_st7735.h` and an `HT_st7735` object; screen must be initialized once in `setup()` before entering the GPS loop.

```cpp
#include "HT_st7735.h"
HT_st7735 st7735;
...
st7735.st7735_init();
st7735.st7735_fill_screen(ST7735_BLACK);
st7735.st7735_write_str(0, 0, (String)"GPS_test");
```

Each time a fix line completes, it clears and redraws the screen with time/lat/lon at fixed y-offsets (0, 20, 40, 60):
```cpp
st7735.st7735_fill_screen(ST7735_BLACK);
st7735.st7735_write_str(0, 0, (String)"GPS_test");
String time_str = (String)GPS.time.hour() + ":" + (String)GPS.time.minute() + ":" +
                   (String)GPS.time.second() + ":" + (String)GPS.time.centisecond();
st7735.st7735_write_str(0, 20, time_str);
st7735.st7735_write_str(0, 40, "LAT: " + (String)GPS.location.lat());
st7735.st7735_write_str(0, 60, "LON: " + (String)GPS.location.lng());
```

## Example 3 — `UC6580_Clear_All`: raw UFirebird command/ACK protocol (cold reset)

Demonstrates talking to the UC6580 receiver's own proprietary text protocol (not NMEA) to force a cold start / clear stored ephemeris, position, time and almanac — useful when a fix is stuck/stale or for a "factory reset GPS" utility. This example does **not** use TinyGPS++; it hand-builds and hand-parses lines.

**Command framing** — `$` + body + `*` + 2 hex checksum digits + `\r\n`, checksum = XOR of all uppercased body bytes:
```cpp
static uint8_t uc6580Checksum(const char *body) {
  uint8_t checksum = 0;
  while (*body != '\0') { checksum ^= uint8_t(toupper((unsigned char)*body)); ++body; }
  return checksum;
}
// frames as: '$' + body + '*' + hex(checksum) + "\r\n"
```

**Cold-start clear command**: `$RESET,0,H85*<checksum>\r\n`
```cpp
sendUc6580Command("RESET,0,H85");
```
Comment in source: *"H85 is the cold-start reset mask listed in the protocol. Do not use HFF because the protocol marks the other bits as reserved."*

**ACK handling** — read lines from the GNSS UART, watch for `$OK` or `$FAIL` substrings, with a timeout:
```cpp
while (millis() - start < timeoutMs) {
  while (GNSS_UART.available() > 0) {
    const char c = char(GNSS_UART.read());
    if (c == '\r') continue;
    if (c == '\n') {
      line[lineLen] = '\0';
      if (strstr(line, "$OK") != NULL)   return UC6580_ACK_OK;
      if (strstr(line, "$FAIL") != NULL) return UC6580_ACK_FAIL;
      lineLen = 0; continue;
    }
    if (lineLen < sizeof(line) - 1) line[lineLen++] = c;
  }
  delay(1);
}
return UC6580_ACK_TIMEOUT;
```

**Boot/reset timing constants** (gotchas — the receiver needs settle time before/after commands):
```cpp
#define UC6580_BOOT_WAIT_MS   1000UL   // wait after power-on before sending anything
#define UC6580_RESET_WAIT_MS  3000UL   // wait after sending reset, listening for output
#define UC6580_ACK_TIMEOUT_MS 3000UL   // max time to wait for $OK/$FAIL
```
Sequence used: enable power -> `Serial1.begin()` -> wait `UC6580_BOOT_WAIT_MS` -> drain/discard any boot chatter -> send `RESET,0,H85` -> wait for ACK (or timeout) -> drain output for `UC6580_RESET_WAIT_MS`.

After the one-time clear, `loop()` becomes a transparent USB<->GNSS UART bridge (bytes each way), handy for watching raw NMEA/UFirebird output live in a serial monitor:
```cpp
void loop() {
  while (GNSS_UART.available() > 0) Serial.write(GNSS_UART.read());
  while (Serial.available() > 0)    GNSS_UART.write(Serial.read());
  delay(1);
}
```

## Gotchas / lessons from the examples

- **Power pin must be enabled first.** GNSS chip stays silent on UART until `GNSS_PWR_PIN` (GPIO 3) is driven `HIGH`. Forgetting this looks like "GPS never responds."
- **Fixed baud: 115200, SERIAL_8N1, RX=33/TX=34** on tracker_v1 hardware — re-verify pins for other Heltec boards, but the framing/baud is consistent across all three examples.
- **`GPS.time.second() == 0` is used as a crude "no fix yet" guard** in both TinyGPS++ examples — skip printing/rendering until the parser has real time data.
- **NMEA parsing loop is peek-based**: read byte by byte into `GPS.encode()`, but `Serial1.peek()` is checked first so the trailing `\n` of a sentence is consumed separately (`Serial1.read()`) rather than passed to `encode()`. This is how the example detects "a full sentence just completed" without TinyGPS++'s own sentence-complete callback.
- **Cold start takes time.** After a `$RESET,0,H85` cold-start clear, expect the receiver to need real time to reacquire a fix (ephemeris/almanac/time/position all cleared) — this is why the example waits `UC6580_RESET_WAIT_MS` (3s) just to drain the immediate response, not to get a fix.
- **Use `H85`, not `HFF`**, for the reset mask — other bits are reserved per the UFirebird protocol comment in source.
- **UC6580 protocol is a separate text protocol from NMEA** (`$RESET,...*XX\r\n` framing with XOR checksum and `$OK`/`$FAIL` ACKs) — don't try to parse these lines with TinyGPS++; they're receiver-management commands, not location sentences.
- All three examples are written as blocking demos (`while(1)` loops inside a helper function called once from `setup()`); production firmware should adapt this into a non-blocking pattern (poll `Serial1.available()` inside `loop()`) if other tasks (e.g. LoRa TX) need to run concurrently.
