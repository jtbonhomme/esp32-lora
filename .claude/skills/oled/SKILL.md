---
name: oled
description: Concrete patterns for driving the onboard SSD1306-family I2C OLED display on Heltec ESP32 boards - init, clearing/drawing/text, screen rotation, a scrolling log buffer, a multi-frame DisplayUi menu system, and showing ArduinoOTA progress on screen. Use when writing/reviewing firmware that touches HT_SSD1306Wire.h, HT_DisplayUi.h, SSD1306Wire, DisplayUi, or draws to the Heltec board's OLED display.
version: 1.0.0
---

# Heltec ESP32 OLED Display (SSD1306)

Reusable patterns extracted from the HelTec `OLED` example set (`DrawingDemo`, `OLED_rotate`, `OTA_OLED`, `SimpleDemo`, `UiDemo`). These are Arduino-framework `.ino` examples for Heltec WiFi Kit 32 / Wireless Stick boards with an onboard SSD1306 128x64 (or 64x32 on some Wireless Stick variants) I2C OLED. Use this skill whenever the task involves initializing the display, drawing shapes/text/bitmaps, rotating the screen, building a multi-screen UI, or rendering progress (e.g. OTA) on screen.

## When to use this skill

- Writing or reviewing code that includes `HT_SSD1306Wire.h` or `HT_DisplayUi.h`, or instantiates `SSD1306Wire` / `DisplayUi`.
- Drawing text, shapes, or bitmaps to the onboard OLED.
- Rotating the screen orientation.
- Building a multi-frame/menu UI on the small OLED.
- Displaying progress (OTA upload, download, etc.) as a bar/percentage on screen.
- Debugging a blank/unresponsive OLED (Vext power gotcha below is the #1 cause).

## Critical gotcha: Vext power rail

On Heltec boards the OLED (and some other peripherals) sit behind a controllable power rail called `Vext`. **If you don't drive `Vext` LOW, the display will not power up and stays blank**, even though `display.init()` succeeds. Every example does this first thing in `setup()`:

```cpp
void VextON(void)
{
  pinMode(Vext, OUTPUT);
  digitalWrite(Vext, LOW);   // LOW = power ON
}

void VextOFF(void) // Vext default OFF
{
  pinMode(Vext, OUTPUT);
  digitalWrite(Vext, HIGH);  // HIGH = power OFF (default state)
}

void setup() {
  VextON();
  delay(100);   // let the rail stabilize before display.init()
  display.init();
  ...
}
```

`Vext`, `SDA_OLED`, `SCL_OLED`, and `RST_OLED` are board-variant pin macros supplied by the Heltec board package (`variant.h`) — do not hardcode GPIO numbers, use these symbols.

## Init pattern and object construction

The display object is a `static SSD1306Wire`, constructed at file scope (not inside `setup()`), with I2C address, clock speed, SDA/SCL pins, geometry, and reset pin:

```cpp
#include <Wire.h>
#include "HT_SSD1306Wire.h"

#ifdef WIRELESS_STICK_V3
static SSD1306Wire display(0x3c, 500000, SDA_OLED, SCL_OLED, GEOMETRY_64_32, RST_OLED); // addr, freq, i2c group, resolution, rst
#else
static SSD1306Wire display(0x3c, 500000, SDA_OLED, SCL_OLED, GEOMETRY_128_64, RST_OLED);
#endif
```

`GEOMETRY_64_32` is used for `WIRELESS_STICK_V3` boards with the smaller display; `GEOMETRY_128_64` is the standard Heltec WiFi Kit 32 size. Guard geometry selection with `#ifdef WIRELESS_STICK_V3` when writing board-portable code.

`setup()` boilerplate seen in every example:

```cpp
VextON();
delay(100);

display.init();
display.clear();
display.display();     // flush cleared buffer to the panel

display.setContrast(255);
```

**Every drawing call only touches an in-memory framebuffer — nothing appears on the physical panel until you call `display.display()`.** This flush call must follow any sequence of `clear()`/`draw*()` calls before the change becomes visible. Several examples call `display.display()` inside animation loops (once per frame) to show incremental drawing.

## Drawing API (from DrawingDemo, SimpleDemo)

Shapes:
```cpp
display.drawLine(x0, y0, x1, y1);
display.drawRect(x, y, w, h);              // outline
display.fillRect(x, y, w, h);              // filled
display.drawCircle(cx, cy, radius);
display.fillCircle(cx, cy, radius);
display.drawCircleQuads(cx, cy, radius, quadrantBitmask); // e.g. 0b00000001 = quadrant 1 only
display.setPixel(x, y);
display.drawHorizontalLine(x, y, length);
display.drawVerticalLine(x, y, length);
```

Color (monochrome — WHITE draws "on", BLACK draws "off", useful for erasing/overlap):
```cpp
display.setColor(WHITE);   // default
display.setColor(BLACK);   // e.g. alternate fill colors, or erase over existing content
```

Text:
```cpp
display.setFont(ArialMT_Plain_10);   // also: ArialMT_Plain_16, ArialMT_Plain_24
display.setTextAlignment(TEXT_ALIGN_LEFT);    // also: TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT
display.drawString(x, y, "Hello world");
display.drawStringMaxWidth(x, y, maxWidth, "long text..."); // word-wraps on spaces and "-"
```
Alignment changes what `x` means: LEFT -> x is the left edge, CENTER -> x is the horizontal center, RIGHT -> x is the right edge.

Bitmaps (XBM format, generated at http://blog.squix.org XBM tool referenced in comments):
```cpp
#include "images.h"   // defines e.g. WiFi_Logo_width/height and a PROGMEM uint8_t[] bitmap
display.drawXbm(x, y, WiFi_Logo_width, WiFi_Logo_height, WiFi_Logo_bits);
```

Progress bar:
```cpp
display.drawProgressBar(x, y, width, height, percent0to100);
```

Scrolling text log buffer (DrawingDemo `printBuffer`):
```cpp
display.setLogBuffer(linesToKeep, charsPerLine);  // allocate buffer, e.g. setLogBuffer(2, 30)
display.clear();
display.println("some line");     // appended to the log buffer
display.drawLogBuffer(0, 0);      // renders buffer contents into the framebuffer at (x,y)
display.display();
```

Query helpers used for layout math: `display.getWidth()`, `display.getHeight()` (also `display.width()`/`display.height()` seen in SimpleDemo — same values).

## OLED_rotate — screen rotation

Rotation only applies to `GEOMETRY_128_64` panels (comment in the example: "rotate only for GEOMETRY_128_64"). Call `screenRotate()` after `clear()`/`display()`, then set font and draw:

```cpp
display.clear();
display.display();
display.screenRotate(ANGLE_0_DEGREE);      // also ANGLE_90_DEGREE, ANGLE_180_DEGREE, ANGLE_270_DEGREE
display.setFont(ArialMT_Plain_16);
display.drawString(64, 32 - 16/2, "ROTATE_0");
display.display();
```

Note width/height effectively swap conceptually between 0/180 vs 90/270 in the example's hardcoded coordinates (64,32 center for 0/180 text vs 32,64 for 90/270), even though `getWidth()`/`getHeight()` are not re-queried after rotating in this example — compute your centering from `display.getWidth()/2`, `display.getHeight()/2` if you need it to stay correct after rotation (as DrawingDemo does).

## OTA_OLED — showing ArduinoOTA progress on screen

Standard `ArduinoOTA` callbacks (`onStart`, `onProgress`, `onEnd`, `onError`) each redraw the display directly:

```cpp
ArduinoOTA.onStart([]() {
  display.clear();
  display.setFont(ArialMT_Plain_10);
  display.setTextAlignment(TEXT_ALIGN_LEFT);
  display.drawString(0, 0, "Start Updating....");
  // NOTE: this example does NOT call display.display() here in onStart — call it yourself if adapting.
});

ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
  String pro = String(progress / (total / 100)) + "%";
  int progressbar = (progress / (total / 100));

  display.clear();
#if defined(WIRELESS_STICK)
  display.drawProgressBar(0, 11, 64, 8, progressbar);
  display.setTextAlignment(TEXT_ALIGN_CENTER);
  display.drawString(10, 20, pro);
#else
  display.drawProgressBar(0, 32, 120, 10, progressbar);
  display.setTextAlignment(TEXT_ALIGN_CENTER);
  display.drawString(64, 15, pro);
#endif
  display.display();
});

ArduinoOTA.onEnd([]() {
  display.clear();
  display.drawString(0, 0, "Update Complete!");
  ESP.restart();
});

ArduinoOTA.onError([](ota_error_t error) {
  display.clear();
  display.drawString(0, 0, info);  // info built from a switch on `error`
  ESP.restart();
});
```

Gotcha: `progress/(total/100)` divides by zero if `total < 100` at the moment a callback fires — guard this in adapted code even though the stock example doesn't. Also note `#if defined(WIRELESS_STICK)` is used to pick different progress-bar geometry for the smaller-screen board variant — mirror this pattern for board portability.

Wifi connection status is also shown on screen before OTA starts (`setupWIFI()`): draws "Connecting...", the SSID, then "Connected" or "Connect False" depending on `WiFi.status()`.

## UiDemo — DisplayUi multi-frame menu framework

`HT_DisplayUi.h` provides a `DisplayUi` class that manages a set of animated, swipeable "frames" (screens) plus optional "overlays" (drawn on every frame, e.g. a clock).

```cpp
#include "HT_DisplayUi.h"
DisplayUi ui(&display);

void drawFrame1(ScreenDisplay *display, DisplayUiState* state, int16_t x, int16_t y) {
  // Draw relative to x,y — the UI framework offsets frames during slide transitions
  display->drawXbm(x + 34, y + 14, WiFi_Logo_width, WiFi_Logo_height, WiFi_Logo_bits);
}

void msOverlay(ScreenDisplay *display, DisplayUiState* state) {
  display->setTextAlignment(TEXT_ALIGN_RIGHT);
  display->setFont(ArialMT_Plain_10);
  display->drawString(128, 0, String(millis()));
}

FrameCallback frames[] = { drawFrame1, drawFrame2, drawFrame3, drawFrame4, drawFrame5 };
int frameCount = 5;
OverlayCallback overlays[] = { msOverlay };
int overlaysCount = 1;

void setup() {
  VextON();
  delay(100);

  ui.setTargetFPS(60);                          // 30fps recommended if doing other work in loop()
  ui.setActiveSymbol(activeSymbol);              // PROGMEM bitmaps from images.h
  ui.setInactiveSymbol(inactiveSymbol);
  ui.setIndicatorPosition(BOTTOM);               // TOP, LEFT, BOTTOM, RIGHT
  ui.setIndicatorDirection(LEFT_RIGHT);
  ui.setFrameAnimation(SLIDE_LEFT);              // SLIDE_LEFT/RIGHT/UP/DOWN
  ui.setFrames(frames, frameCount);
  ui.setOverlays(overlays, overlaysCount);

  ui.init();   // also initializes the underlying display — don't call display.init() separately
}

void loop() {
  int remainingTimeBudget = ui.update();
  if (remainingTimeBudget > 0) {
    delay(remainingTimeBudget);   // idle only if under the frame time budget
  }
}
```

`ui.update()` handles clearing, drawing the current/transitioning frame(s), overlays, the page indicator dots, and flushing to the display — no manual `display.display()` call is needed when driving the display through `DisplayUi`.

## I2C bus notes

- Fixed I2C address `0x3c`, clock `500000` Hz (500kHz), using board-specific `SDA_OLED`/`SCL_OLED` pins — all examples pass these identically to the `SSD1306Wire` constructor.
- `#include <Wire.h>` is included even though `SSD1306Wire` manages the bus internally — keep it for compatibility with the Heltec board package.

## Summary of example purposes

| Example | Demonstrates |
|---|---|
| `DrawingDemo` | Full primitive sweep: animated lines, growing/shrinking rects, alternating-color fills, circles + circle quadrants, the scrolling log buffer, and all 4 screen rotations with centered text. |
| `OLED_rotate` | Minimal focused demo of `screenRotate()` at all 4 angles with `ArialMT_Plain_16`/`_10` fonts. |
| `OTA_OLED` | Full WiFi STA connect + `ArduinoOTA` factory-test sketch that renders connection status and OTA progress bar/percentage/errors on the OLED. |
| `SimpleDemo` | Cycles through 7 self-contained demo functions (fonts, text flow/wrap, alignment, rects/lines, circles, progress bar, XBM image) every 3 seconds via a function-pointer array. |
| `UiDemo` | `DisplayUi` framework: 5 sliding frames + a millis() overlay, active/inactive page-indicator symbols, configurable indicator position/direction and slide animation, FPS-budgeted `loop()`. |
