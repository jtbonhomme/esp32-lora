---
name: wireless-paper
description: Concrete patterns for the Heltec Wireless Paper board family (ESP32 + LoRa + E-ink) - driving the E0213A367/ICMEN2R13EFC1/QYEG0213RWS800_BWR E-paper panels, reading the panel's chip ID to auto-detect firmware/driver at runtime, and the manual-flasher/XBM image procedure used to verify and re-flash boards by hand. Use when writing/reviewing firmware for a Wireless Paper board, when the user mentions Wireless Paper, E0213A367, ICMEN2R13EFC1, E-ink firmware query, or manual flashing of an e-paper board.
version: 1.0.0
---

# Heltec Wireless Paper (ESP32 + LoRa + E-ink)

Patterns extracted from Heltec's official `Wireless_paper` examples: `E-ink_Firmware_Query`, `HT_E0213A367_test`, `Wireless_paper_1.1_manual_flasher`, `Wireless_paper_1.2_manual_flasher`, `Wireless_Paper_V1.0`, `Wireless_Paper_V1.1`.

## Board revisions use different E-ink driver chips

The Wireless Paper family shipped with **three different panel controllers** across hardware revisions, so firmware must pick the matching driver class:

| Hardware | Header | Driver class |
|---|---|---|
| Wireless Paper V1.0 | `HT_QYEG0213RWS800_BWR.h` | `QYEG0213RWS800_BWR` |
| Wireless Paper V1.1 / "1.1 manual flasher" | `HT_lCMEN2R13EFC1.h` | `HT_ICMEN2R13EFC1` |
| Wireless Paper V1.2 / "1.2 manual flasher" | `HT_E0213A367.h` | `HT_E0213A367` |

All three expose the same constructor signature and drawing API (`init/clear/update/display/drawXbm/...`), so code is largely portable across revisions once the right class is selected — this is exactly what `E-ink_Firmware_Query` automates at boot.

## Common setup: Vext power before display init

Every example enables the external power rail (`Vext`, GPIO 45) and waits before touching the display — the panel is powered through this rail and will not respond otherwise:

```cpp
void VextON(void) {
  pinMode(45, OUTPUT);
  digitalWrite(45, LOW);   // active LOW
}
void VextOFF(void) { // Vext default OFF
  pinMode(45, OUTPUT);
  digitalWrite(45, HIGH);
}

void setup() {
  VextON();
  delay(100);              // let power rail stabilize before display.init()
  display.init();
}
```

Comment in the code notes a variant for other boards: "For HT-VME213, choose `18, OUTPUT` / `18, HIGH/LOW`" instead of GPIO 45 — the Vext pin is board-specific.

## E0213A367 driver API (HT_E0213A367_test)

Construction takes `rst, dc, cs, busy, sck, mosi, miso, frequency`:

```cpp
#include "HT_E0213A367.h"
#include "images.h"

HT_E0213A367 display(6, 5, 4, 7, 3, 2, -1, 6000000); // rst,dc,cs,busy,sck,mosi,miso,frequency

#define DIRECTION ANGLE_0_DEGREE // ANGLE_0/90/180/270_DEGREE

void setup() {
  Serial.begin(115200);
  VextON();
  delay(100);
  display.init();
  display.screenRotate(DIRECTION);
  display.setFont(ArialMT_Plain_10);
}
```

Drawing/refresh pattern (two logical planes — black and "color" — each pushed with its own `update()` call before the final physical `display()`):

```cpp
display.clear();
display.setTextAlignment(TEXT_ALIGN_LEFT);
display.setFont(ArialMT_Plain_24);
display.drawString(0, 26, "Hello world");
display.update(BLACK_BUFFER);   // commit black-plane draws

display.setColor(WHITE);        // or BLACK, for shapes
display.drawCircle(x, y, r);
display.fillCircle(x, y, r);
display.drawRect(x, y, w, h);
display.fillRect(x, y, w, h);
display.drawHorizontalLine(x, y, len);
display.drawVerticalLine(x, y, len);
display.setPixel(x, y);
display.update(COLOR_BUFFER);   // commit color-plane draws

display.display();              // physical refresh of the panel
```

Text helpers used in the demo: `drawStringMaxWidth(x, y, maxWidth, text)` (word-wrap), `setTextAlignment(TEXT_ALIGN_LEFT|RIGHT|CENTER)`, `width()`/`_width`/`_height` for layout math, `drawXbm(x, y, w, h, bits)` for bitmaps.

`width`/`height` must be swapped for 90/270-degree rotation:

```cpp
if (DIRECTION == ANGLE_0_DEGREE || DIRECTION == ANGLE_180_DEGREE) {
  width = display._width; height = display._height;
} else {
  width = display._height; height = display._width;
}
```

## Firmware/chip identification pattern (E-ink_Firmware_Query)

To auto-detect *which* panel controller is soldered on a given board (so the correct driver class is instantiated), this example bit-bangs a raw SPI read of the panel's chip-ID register (**before** any high-level driver is constructed) using command byte `0x2F`:

```cpp
#define PIN_EINK_SCLK 3
#define PIN_EINK_DC   5
#define PIN_EINK_CS   4
#define PIN_EINK_RES  6
#define PIN_EINK_MOSI 2
#define PIN_VEXT      45

uint8_t displayChipId;

// power + reset
VextON(); delay(100);
pinMode(PIN_EINK_SCLK, OUTPUT); pinMode(PIN_EINK_DC, OUTPUT);
pinMode(PIN_EINK_CS, OUTPUT);   pinMode(PIN_EINK_RES, OUTPUT);
digitalWrite(PIN_EINK_RES, LOW);  delay(20);
digitalWrite(PIN_EINK_RES, HIGH); delay(20);

// send 0x2F "read chip ID" command, MSB first
digitalWrite(PIN_EINK_DC, LOW);   // command mode
digitalWrite(PIN_EINK_CS, LOW);
uint8_t cmd = 0x2F;
pinMode(PIN_EINK_MOSI, OUTPUT);
digitalWrite(PIN_EINK_SCLK, LOW);
for (int i = 0; i < 8; i++) {
  digitalWrite(PIN_EINK_MOSI, (cmd & 0x80) ? HIGH : LOW);
  cmd <<= 1;
  digitalWrite(PIN_EINK_SCLK, HIGH); delayMicroseconds(1);
  digitalWrite(PIN_EINK_SCLK, LOW);  delayMicroseconds(1);
}
delay(10);

// read back 8-bit chip ID, MSB first
digitalWrite(PIN_EINK_DC, HIGH);  // data mode
pinMode(PIN_EINK_MOSI, INPUT_PULLUP);
displayChipId = 0;
for (int8_t b = 7; b >= 0; b--) {
  digitalWrite(PIN_EINK_SCLK, LOW);  delayMicroseconds(1);
  digitalWrite(PIN_EINK_SCLK, HIGH); delayMicroseconds(1);
  if (digitalRead(PIN_EINK_MOSI)) displayChipId |= (1 << b);
}
digitalWrite(PIN_EINK_CS, HIGH);  // deselect

// decode: bits [1:0] == 0b01 identifies E0213A367, anything else -> ICMEN2R13EFC1
ScreenDisplay *factory_display;
if ((displayChipId & 0x03) != 0x01) {
  factory_display = new HT_ICMEN2R13EFC1(6, 5, 4, 7, 3, 2, -1, 6000000);
} else {
  factory_display = new HT_E0213A367(6, 5, 4, 7, 3, 2, -1, 6000000);
}
factory_display->init();
```

Both driver classes are subclasses of a common `ScreenDisplay` base, so `factory_display` can be a single `ScreenDisplay*` regardless of which chip was detected — use `factory_display->update(BLACK_BUFFER); factory_display->display();` polymorphically afterward. This is the pattern to reuse whenever firmware must run unmodified across V1.1 and V1.2 hardware without a compile-time `#define`.

## Manual flasher examples (board bring-up / visual verification tool)

`Wireless_paper_1.1_manual_flasher` and `Wireless_paper_1.2_manual_flasher` are minimal single-purpose sketches: init the correct driver for that hardware revision, then loop drawing a fixed logo bitmap every 15s as a burn-in/visual-verification test image:

```cpp
#include "HT_E0213A367.h"   // or HT_lCMEN2R13EFC1.h for the 1.1 flasher
#include "images.h"

HT_E0213A367 display(6, 5, 4, 7, 3, 2, -1, 6000000);

void setup() {
  VextON(); delay(100);
  display.init();
  display.screenRotate(DIRECTION);
}

void drawImageDemo() {
  display.clear();
  display.update(BLACK_BUFFER);
  display.clear();
  int x = width/2 - WiFi_Logo_width/2;
  int y = height/2 - WiFi_Logo_height/2;
  display.drawXbm(x, y, WiFi_Logo_width, WiFi_Logo_height, WiFi_Logo_bits);
  display.update(COLOR_BUFFER);
  display.display();
}

void loop() {
  drawImageDemo();
  delay(15000); // keep the logo displayed for 15 seconds
}
```

**Manual flashing / image-swap procedure** (from `Wireless_paper_1.2_manual_flasher/readme.md`):
1. Set the source image resolution to **250x122** (must match the panel resolution configured in `images.h`) and convert it to XBM format (e.g. via GIMP export, or any BMP→XBM tool).
2. Open the generated `.xbm` file in VSCode/Notepad and copy the C byte-array code it contains.
3. Paste that array into `images.h`, replacing the existing `WiFi_Logo_bits[]` (and matching `WiFi_Logo_width`/`WiFi_Logo_height` `#define`s).
4. Re-flash the sketch — the board will now display the new static image every boot, which is used to visually confirm the panel/driver combination is correct before deploying real firmware.

Note the flasher `images.h` files use a larger `WiFi_Logo` (212x104) for full-panel test patterns, versus 60x36 in the `HT_E0213A367_test` demo — image dimensions are whatever fits the intended draw region, not a fixed constant.

## Wi-Fi web-upload variant (Wireless_Paper_V1.0 / V1.1)

A second way to push a new image to the panel without recompiling: these sketches bring up a `WebServer` on port 80 serving a page (`html.h`) with a file picker. The browser-side JS validates the image is exactly the panel resolution, converts the BMP to an XBM-style bit array client-side, and POSTs it to `/set?value=<comma-separated-bytes>`; the firmware parses that CSV directly into the live `WiFi_Logo_bits[]` array and redraws:

```cpp
WebServer server(80);
const char *ssid = "your_ssid";
const char *password = "your_password";

void Config_Callback() {
  String Payload = server.arg("value");
  char *token = strtok((char *)Payload.c_str(), ",");
  int i = 0;
  while (token != NULL) {
    WiFi_Logo_bits[i++] = atoi(token);
    token = strtok(NULL, ",");
  }
  drawImageDemo();
}

void setup() {
  VextON(); delay(100);
  display.init();
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) { delay(500); }
  server.on("/", []() { server.send(200, "text/html", index_html); });
  server.on("/set", HTTP_GET, Config_Callback);
  server.begin();
}

void loop() { server.handleClient(); }
```

Client-side flow described in the served page (`html.h`) and the V1.1 `readme.md`: modify SSID/password in the sketch and flash it; open the Serial Monitor to read the DHCP-assigned IP; browse to that IP; pick a black-and-white BMP sized to the panel (250x122); click "Get image data" to convert it in-browser to the byte array shown on a `<canvas>`; click "refresh" to POST it to `/set` and redraw the panel over Wi-Fi. Note the browser-side dimension check in `html.h` actually compares against `255`/`122` (off-by-a-few from the documented 250 — treat 250x122 as the real target and don't copy the `255` literal into new code).

## Gotchas noted in the source

- Vext must be turned on (`VextON()`) and given a `delay(100)` **before** `display.init()` — the panel has no power otherwise.
- The chip-ID bit-bang read in `E-ink_Firmware_Query` must run against raw pins, before any `HT_E0213A367`/`HT_ICMEN2R13EFC1` object talks to the bus — it is a manual protocol probe, not a library call.
- `screenRotate()` swaps effective width/height for 90/270-degree rotations; layout math using `width`/`height` locals must account for this explicitly (the examples do it in `setup()`, not inside the driver).
- Two logical draw planes exist per frame — `BLACK_BUFFER` and `COLOR_BUFFER` — each committed with a separate `display.update(...)` call; `display.display()` performs the actual (slow) physical E-ink refresh and should be called once after both planes are updated, not per-plane.
- `Vext` pin is board-specific: GPIO 45 on Wireless Paper, but a code comment flags GPIO 18 (opposite polarity: `HIGH` to enable) for the "HT-VME213" board — don't hardcode 45 when porting to other Heltec boards.
- The V1.0/V1.1 web-upload HTML validates image size against `255`/`122` in one branch while the documentation and panel spec say `250x122` — a latent bug in the reference firmware, worth fixing rather than copying if reusing this flow.

## When to use this skill

Load this skill when writing or reviewing firmware for a Heltec **Wireless Paper** board (ESP32 + LoRa + E-ink), including: initializing/drawing to the E0213A367, ICMEN2R13EFC1, or QYEG0213RWS800_BWR E-ink panel drivers; auto-detecting the panel chip ID/firmware variant at runtime; building a manual/burn-in flasher that draws a fixed XBM test image; or implementing a Wi-Fi based image-upload-and-refresh workflow for the panel.
