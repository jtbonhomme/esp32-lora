---
name: eink
description: Patterns for driving E-ink / E-paper (EPD) displays on Heltec ESP32 boards with the heltec-eink-modules Arduino library — display init, full vs fast/partial refresh (fastmodeOn/fastmodeOff), the DRAW() macro, windowed updates, and XBitmap icons. Use when writing or reviewing firmware that renders to an e-ink/e-paper panel on a Heltec board (Vision Master E213, Wireless Paper, etc.).
version: 1.0.0
---

# Heltec E-ink / E-paper Display Firmware

Knowledge extracted from the official Heltec ESP32 e-ink examples
(`Heltec_ESP32/examples/eink/e213_E0213A367_fase_mode` and
`.../wireless_paper_E0213A367_fase_mode`), both built on the
`heltec-eink-modules` Arduino library.

## When to use this skill

Use this whenever a task involves rendering to an e-ink/e-paper (EPD) panel
on a Heltec board — e.g. Vision Master E213, Wireless Paper, or similar
Heltec e-ink dev boards — including partial/fast refresh, ghosting concerns,
or low-power update strategies. Not applicable to Heltec's OLED displays
(those use a different library/API).

## What the examples demonstrate

Both examples in the source tree are functionally identical demos of the
**same feature** ("fast mode" / partial refresh), differing only in which
board-specific display class is instantiated:

| Directory | Board class used |
|---|---|
| `e213_E0213A367_fase_mode` | `EInkDisplay_VisionMasterE213V1_1` |
| `wireless_paper_E0213A367_fase_mode` | `EInkDisplay_WirelessPaperV1_2` |

Each demo:
1. Clears the screen to a known blank state.
2. Draws a static "Fastmode: On" label at the bottom of the screen (full refresh).
3. Enables fast mode (`fastmodeOn()`), then loops 6 times drawing an
   animated "loading icon" (cycling XBitmap hourglass images) plus a
   counter digit in the corner — each frame drawn inside a `DRAW(display){...}`
   block, using a `setWindow()` region that deliberately excludes the label
   area so the label survives.
4. Turns fast mode back off (`fastmodeOff()`), which forces a full refresh,
   and rewrites the label text ("Fastmode: Off") in a *different*, tightly
   scoped window (only the bottom 35px).

There is no `loop()` behavior in either sketch — everything happens once in
`setup()`.

## Library / include pattern

```cpp
#include <heltec-eink-modules.h>

// One global display object, using the class matching the exact board:
EInkDisplay_VisionMasterE213V1_1 display;   // Vision Master E213
// or
EInkDisplay_WirelessPaperV1_2 display;      // Wireless Paper
```

The board-specific class (`class-aliases.h` in the library) encapsulates the
panel driver and SPI/GPIO wiring for that exact board — **neither example
does any manual SPI.begin() or pin configuration**. Pick the display class
that matches the physical board/panel and the library handles the bus setup
internally. Don't hand-roll pin setup unless you're bringing up a panel the
library doesn't already have a class for.

## Core API surface actually used in the examples

- `display.clear()` — blank the screen before drawing.
- `display.setTextSize(n)` / `display.setTextColor(BLACK|WHITE)` — text styling (Adafruit-GFX-style API).
- `display.setCursor(x, y)`, `display.println(...)`, `display.print(...)` — text drawing.
- `display.drawXBitmap(x, y, bitmapArray, w, h, color)` — draw a 1-bit XBitmap (see icon pattern below).
- `display.fillRect(x, y, w, h, color)` — filled rectangle (used here to blank a counter box each frame).
- `display.left()`, `display.top()`, `display.right()`, `display.bottom()`, `display.width()`, `display.height()`, `display.centerX()`, `display.centerY()` — layout helpers; prefer these over hardcoded panel dimensions so sketches port across panel sizes.
- `display.setWindow(x, y, w, h)` — restrict the next refresh/draw region. Used to protect an area (e.g. a label) from being overwritten/blanked by the next update.
- `display.fastmodeOn()` / `display.fastmodeOff()` — toggle partial vs full refresh (see below).
- `DRAW (display) { ... }` — a macro wrapping a block of drawing calls; used around every logical "frame" (each icon/counter update, each label write). Treat each `DRAW(){}` block as one atomic screen update/refresh cycle.

## Full refresh vs fast mode (partial refresh) — the key gotcha

This is the central lesson of both examples, and it's called out directly in
comments in the source:

```cpp
// DEMO: Fast Mode
// ------------------
// Some panels have the ability to perform a "fast update",
// The technical term for this feature is "partial refresh".
// If your panel supports this, you can select it with fastmodeOn()
```

Practical implications observed in the code:

- **`fastmodeOn()`** enables partial refresh: subsequent `DRAW()` updates are
  fast (used here for a 6-frame loading animation) but only work correctly
  within the region defined by `setWindow()`.
- **`fastmodeOff()`** forces a full refresh on the next update — the
  example uses this after the fast-mode animation loop finishes, to cleanly
  repaint text ("Back to normal mode (full refresh)").
- **`setWindow()` is used to fence off regions from being touched by a
  refresh**, so a fast-mode animation in one part of the screen doesn't
  erase/redraw a label elsewhere:
  ```cpp
  // Don't overwrite the bottom 35px (label area) while animating above it
  display.setWindow(display.left(), display.top(), display.width(), display.height() - 35);
  ...
  // Later, restrict the window to ONLY the bottom 35px to update the label
  display.setWindow(display.left(), display.bottom() - 35, display.width(), 35);
  ```
- Not every panel supports fast/partial mode — the comment explicitly says
  "If your panel supports this, you can select it with fastmodeOn()",
  implying this should be treated as a capability to check for, not assumed
  universal across all e-ink panels.
- Neither example puts anything in `loop()` or does deep sleep between
  updates — both are one-shot `setup()`-only demos. No power-sequencing or
  deep-sleep-between-refresh pattern is shown in this source material; if a
  battery-powered e-ink use case is being built, that must be designed
  separately (e.g. `esp_deep_sleep_start()` after the final `DRAW()` call),
  not copied from these examples.

## XBitmap icon pattern

Icons are stored as separate headers, generated per the library's own
XBitmap tutorial, and included directly:

```cpp
#include "hourglass_1.h"
#include "hourglass_2.h"
#include "hourglass_3.h"
const unsigned char* hourglasses[] = {hourglass_1_bits, hourglass_2_bits, hourglass_3_bits};
```

Header format (`hourglass_1.h`), `PROGMEM`-resident 1-bit bitmap data:

```cpp
// XBitmap Image used in example: "fast_mode.ino"
// See https://github.com/todd-herbert/heltec-eink-modules/blob/main/docs/XBitmapTutorial/README.md

#define hourglass_1_width 70
#define hourglass_1_height 100
PROGMEM const static unsigned char hourglass_1_bits[] = {
   0x00, 0xfe, 0xff, ...
};
```

Position icons using the layout helpers rather than magic numbers, e.g.:

```cpp
int ICON_L = display.centerX() - (hourglass_1_width / 2);
int ICON_T = display.centerY() - (hourglass_1_height / 2) - 15; // nudge toward top
```

Cycle through frames with modulo indexing: `hourglasses[demo % 3]`.

If a new panel/board is needed and the library doesn't already have an
`EInkDisplay_*` alias for it, generate new XBitmap headers following the
library's own tutorial (linked in the header comments above) rather than
hand-writing bitmap arrays.

## Quick checklist for new e-ink sketches on Heltec boards

1. `#include <heltec-eink-modules.h>` and instantiate the correct
   `EInkDisplay_<Board><Version>` object for the exact panel — don't
   configure SPI/pins manually.
2. `display.clear()` before drawing anything.
3. Wrap each logical screen update in `DRAW (display) { ... }`.
4. Decide full vs fast refresh: default (no `fastmodeOn()`) is full refresh;
   call `fastmodeOn()` before rapid/animated updates, `fastmodeOff()` before
   the next update that needs a clean, ghost-free full repaint.
5. Use `setWindow()` to scope updates so fast-mode redraws don't clobber
   parts of the screen you want preserved (e.g. static labels).
6. Use `display.left()/top()/right()/bottom()/width()/height()/centerX()/centerY()`
   instead of hardcoded pixel coordinates so layout survives across panels.
7. For anything beyond a one-shot demo (battery operation, periodic
   refresh), add your own power/sleep strategy — it is not shown in these
   examples.
