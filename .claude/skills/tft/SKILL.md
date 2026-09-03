---
name: tft
description: Patterns for driving color TFT displays on Heltec ESP32 boards — ST7735 1.8"/1.44"/mini SPI panels via the HT_st7735 library, and the ST7789 SPI touchscreen TFT on the Wireless Tracker V4 board via HT_ST7789 (Adafruit_SPITFT subclass) plus CHSC6X capacitive touch. Use when writing or reviewing firmware for a TFT display, ST7735, ST7789, SPI display, or touchscreen on a Heltec ESP32 board.
version: 1.0.0
---

# Heltec TFT / SPI Display Firmware

Knowledge extracted from the official Heltec ESP32 TFT examples
(`Heltec_ESP32/examples/TFT/ST7735_SPI` and `.../V4_Touch_TFT`), and the
underlying `HT_st7735` / `HT_st7789spi` / `chsc6x` library sources they use.

## When to use this skill

Use this whenever a task involves rendering to a color TFT panel on a Heltec
board — a small ST7735-driven SPI TFT (1.8", 1.44", or 160x80 "mini" panel),
or the ST7789-driven touchscreen TFT on the Wireless Tracker V4 board —
including pixel/shape/text drawing, screen fill, color handling, or reading
capacitive touch input. Not applicable to Heltec's OLED or e-ink displays
(different libraries/APIs — see the `eink` skill for e-ink).

There are two distinct display stacks in this source material — pick the one
matching the hardware:

| Directory | Panel / driver | Touch | Board target |
|---|---|---|---|
| `ST7735_SPI` | `HT_st7735` (custom, non-Adafruit-GFX) | none | small SPI ST7735 breakout panels (1.8"/1.44"/160x80) |
| `V4_Touch_TFT` | `HT_ST7789` (`HT_st7789spi`, subclasses `Adafruit_SPITFT`) | `chsc6x` (CHSC6X I2C capacitive touch) | Wireless Tracker V4 (`WIFI_LORA_32_V4`) |

## 1. ST7735_SPI example — non-touch SPI TFT

### What it demonstrates

`ST7735_SPI.ino` is a one-object demo cycling through, in `loop()`:
1. A red 1px border traced pixel-by-pixel around the full screen
   (`st7735_draw_pixel`) as a bring-up/alignment check.
2. Three font sizes (`Font_7x10`, `Font_11x18`, `Font_16x26`) rendered with
   `st7735_write_str`.
3. A full-screen fill through every named color (`st7735_fill_screen`) with a
   contrasting color-name label on top of each.

### Include / object pattern

```cpp
#include "HT_st7735.h"
#include "Arduino.h"
HT_st7735 st7735;   // default constructor uses the pins baked into HT_st7735.h
```

`HT_st7735`'s constructor accepts pin overrides
(`cs_pin, rest_pin, dc_pin, sclk_pin, mosi_pin, led_k_pin, vtft_ctrl_pin`),
each defaulting to the board macros defined at the top of `HT_st7735.h`
(`ST7735_CS_Pin`, `ST7735_REST_Pin`, `ST7735_DC_Pin`, `ST7735_SCLK_Pin`,
`ST7735_MOSI_Pin`, `ST7735_LED_K_Pin`, `ST7735_VTFT_CTRL_Pin` — default
38/39/40/41/42/21/3). The example doesn't override any of them; only do so if
targeting a board variant that wires the panel differently.

### Init and core drawing API actually used

```cpp
void setup() {
    Serial.begin(115200);
    st7735.st7735_init();     // must be called before any drawing call
}

void loop() {
    st7735.st7735_fill_screen(ST7735_BLACK);
    st7735.st7735_draw_pixel(x, y, ST7735_RED);
    st7735.st7735_write_str(0, 0,
        "Font_7x10, red on black, lorem ipsum dolor sit amet",
        Font_7x10, ST7735_RED, ST7735_BLACK);   // x, y, text, font, fg, bg
}
```

Other methods declared on `HT_st7735` (used in the wider library, not all
exercised by this specific example, but part of the API surface):
`st7735_write_char(x, y, ch, font, color, bgcolor)`,
`st7735_fill_rectangle(x, y, w, h, color)`,
`st7735_draw_image(x, y, w, h, const uint16_t* data)`,
`st7735_invert_colors(bool)`, `st7735_set_gamma(GammaDef)`.

### Colors and fonts

Colors are RGB565 constants: `ST7735_BLACK/BLUE/RED/GREEN/CYAN/MAGENTA/
YELLOW/WHITE`, or build one with `ST7735_COLOR565(r, g, b)`. Fonts come from
`HT_st7735_fonts.h`: `Font_7x10`, `Font_11x18`, `Font_16x26` — bigger glyphs
cost more screen real estate, so line-spacing in the example is computed
manually from the font's pixel height (e.g. `3*10` px gap after a `Font_7x10`
line, `3*18` after `Font_11x18`).

### Panel geometry / rotation gotcha

`HT_st7735.h` contains a large block of **mutually exclusive, commented-out**
`#define` groups for different physical panels — 160x128 in four rotations,
128x128 ("1.44\"") in four rotations, and 160x80 "mini" panels. Each group
sets `ST7735_WIDTH`, `ST7735_HEIGHT`, `ST7735_XSTART`/`ST7735_YSTART` (RAM
offset — many cheap panels have visible RAM larger than the physical glass,
so drawing must be offset), and `ST7735_ROTATION` (a MADCTL bitmask, e.g.
`ST7735_MADCTL_MX | ST7735_MADCTL_MY`). **Only one group should be active at
a time**, and it must match the physical panel or the image will be mirrored,
rotated, or shifted off-screen. The currently-active block in this codebase
is gated on `WIFI_LORA_32_V4` (mini 160x80 panel, two rotation variants) —
when bringing up a different physical panel, uncomment/add the matching
block instead of guessing new XSTART/YSTART/ROTATION values.

The `ST7735_LED_K_Pin` (backlight cathode) and `ST7735_VTFT_CTRL_Pin` (panel
power/Vext-style control) pins exist in the constructor/header but this
example's `setup()` never explicitly drives them — `st7735_init()` is the
only call made before drawing, implying the library's init handles
power/backlight sequencing internally for the boards it targets. If a board
needs explicit Vext or backlight gating, confirm against `HT_st7735.cpp`
before assuming it's unnecessary (contrast with `V4_Touch_TFT`, where the
sketch itself explicitly powers Vext and drives the backlight — see below).

## 2. V4_Touch_TFT example — ST7789 touchscreen TFT (Wireless Tracker V4)

### What it demonstrates

`V4_Touch_TFT.ino` is a small paint/drawing app on a 240x320 touchscreen: a
button palette down the right edge (clear button, pen-size button, 7 color
swatches) and a drawing canvas on the left, driven entirely from touch
events read every `loop()` iteration (`delay(50)` between polls).

### Includes / pin setup / object construction

```cpp
#include "Arduino.h"
#include "HT_st7789spi.h"
#include "chsc6x.h"

#define TFT_CS          15
#define TFT_RST         18   // Or set to -1 and connect to Arduino RESET pin
#define TFT_DC          16
#define TFT_MOSI        33   // Data out
#define TFT_SCLK        17   // Clock out
#define TFT_BLK         21   // backlight control

#define TOUCH_SDA_PIN      47
#define TOUCH_SCL_PIN      48
#define TOUCH_INT_PIN      45
#define TOUCH_RST_PIN      44

#define Vext_Ctrl       36

chsc6x touch(&Wire1, TOUCH_SDA_PIN, TOUCH_SCL_PIN, TOUCH_INT_PIN, TOUCH_RST_PIN);
HT_ST7789 tft(240, 320, TFT_CS, TFT_DC, TFT_MOSI, TFT_SCLK, TFT_RST);
```

`HT_ST7789` is declared as `class HT_ST7789 : public Adafruit_SPITFT`, so it
exposes the full Adafruit_GFX/Adafruit_SPITFT drawing API (`drawPixel`,
`drawRect`, `fillRect`, `fillCircle`, `drawBitmap`, `fillScreen`,
`invertDisplay`, `setRotation`, ...) on top of ST7789-specific extras
(`init`, `enableDisplay`, `enableSleep`, `LCD_Set_Scroll_Area`, ...).

### Init sequence (order matters)

```cpp
void setup() {
  Serial.begin(115200);
  VextON();                 // 1. power the display rail before touching SPI/I2C to it
  delay(100);
  tft.init(240, 320);       // 2. init the panel
  touch.chsc6x_init();      // 3. init the touch controller
  tft.invertDisplay(1);     // 4. this panel needs color inversion
  tft.fillScreen(ST7789_WHITE);
  blk_ctrl(1);              // 5. turn the backlight on last, after content is drawn
  draw_button_palette();
}

void VextON(void) {
  pinMode(Vext_Ctrl, OUTPUT);
  digitalWrite(Vext_Ctrl, LOW);   // LOW = Vext rail enabled on this board
}

void blk_ctrl(bool state) {
  pinMode(TFT_BLK, OUTPUT);
  digitalWrite(TFT_BLK, state ? HIGH : LOW);
}
```

`VextOFF()` (drives `Vext_Ctrl` HIGH) is also defined for symmetry, though
unused in the demo — call it to cut display rail power, e.g. before deep
sleep.

### Color-order gotcha (board-dependent RGB/BGR)

`HT_st7789spi.h` defines the ST7789 named colors **differently depending on
`WIFI_LORA_32_V4`**:

```cpp
#ifdef  WIFI_LORA_32_V4
#define ST7789_RED 0x001F     // swapped vs. the "normal" definition
#define ST7789_BLUE 0xF800
#define ST7789_CYAN 0xFFE0
#define ST7789_YELLOW 0x07FF
#else
#define ST7789_RED 0xF800
#define ST7789_BLUE 0x001F
#define ST7789_CYAN 0x07FF
#define ST7789_YELLOW 0xFFE0
#endif
```

This means the V4 tracker's ST7789 panel is wired/addressed with a different
color channel order than a "generic" ST7789 — **always build against the
correct board macro (`WIFI_LORA_32_V4`) rather than assuming the standard
RGB565 constants**, or reds and blues (and cyan/yellow) will swap.

### Drawing API actually used

```cpp
tft.drawRect(x, y, w, h, color);
tft.fillRect(x, y, w, h, color);
tft.fillCircle(x, y, r, color);
tft.drawPixel(x, y, color);
tft.drawBitmap(x, y, epd_bitmap_Bitmap, w, h, color);  // 1-bit PROGMEM bitmap, Adafruit_GFX style
tft.fillScreen(color);
```

A manual Bresenham line (`draw_line`) is implemented in the sketch itself by
stepping `draw_point()` (which picks `drawPixel` for a 1px pen or
`fillCircle` for a thicker pen) between two touch points — `HT_ST7789` /
`Adafruit_SPITFT` has no dedicated `drawLine` call used here, so
smooth-stroke drawing is the app's own responsibility, not the driver's.

### Touch input handling

```cpp
uint16_t touchX, touchY;
if (touch.chsc6x_read_touch_info(&touchX, &touchY) == 0) {
    // a touch is currently active; touchX/touchY updated in place
    // == 0 means a touch WAS read; non-zero means no touch this poll
} else {
    isDrawing = false;   // treat "no touch" as pen-up
}
```

Patterns from the example:
- Poll once per `loop()` iteration (`delay(50)` between polls — not
  interrupt-driven in this sketch, despite `TOUCH_INT_PIN` existing).
- Hit-test screen regions by comparing `touchX`/`touchY` against fixed pixel
  rectangles (palette buttons occupy `x in [210,240)`, then y-banded regions
  for clear/pen-size/each color swatch; the remaining `x in [0,210), y in
  [0,320)` region is the drawing canvas).
- Track `lastX/lastY` + a `isDrawing` bool across polls so consecutive touch
  samples can be connected with `draw_line()` into a continuous stroke,
  rather than just plotting disconnected points.
- `chsc6x` is constructed on `&Wire1` (the second I2C bus), not the default
  `Wire` — matches the V4 board's touch controller wiring being separate
  from any user-facing I2C bus.

## Quick checklist for new TFT sketches on Heltec boards

1. Identify the exact panel/board: small ST7735 breakout -> `HT_st7735`;
   Wireless Tracker V4 touchscreen -> `HT_ST7789` + `chsc6x`.
2. For `HT_st7735`: confirm the active `ST7735_WIDTH/HEIGHT/XSTART/YSTART/
   ROTATION` block in `HT_st7735.h` actually matches the physical panel
   before writing sketch code — wrong geometry mirrors/shifts everything.
3. For `HT_ST7789` boards (V4 tracker): power the display rail with
   `VextON()` and `delay(100)` *before* calling `tft.init(...)`; turn the
   backlight on (`blk_ctrl`/`TFT_BLK` HIGH) only after the first frame is
   drawn to avoid flashing garbage.
4. Always call the driver's `*_init()` before any drawing call.
5. Use the driver's own named color constants (`ST7735_*` / `ST7789_*`), not
   hardcoded hex — the V4 board's `ST7789_*` set intentionally differs from
   the generic ST7789 RGB order via `#ifdef WIFI_LORA_32_V4`.
6. For touch boards, poll `chsc6x_read_touch_info(&x, &y)` once per loop,
   check its return value (`0` = touch read), and drive an `isDrawing`/
   `lastX,lastY` state machine if you need continuous strokes rather than
   isolated points — the driver gives you points, not gestures or lines.
7. Neither example uses interrupts or deep sleep around the display; add
   power-down (`VextOFF()`, backlight off, `tft.enableSleep(true)`) yourself
   if building a battery-powered use case.
