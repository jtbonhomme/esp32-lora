---
name: esp32-makefile
description: Generates a practical arduino-cli-based Makefile for managing an ESP32/Heltec devkit board — targets to list boards and ports, install the core and required libraries, compile, upload, monitor the serial console, and erase flash. Use when the user asks for a Makefile, build automation, or CLI workflow to compile/upload/monitor an ESP32 or Heltec Arduino sketch.
version: 1.0.0
---

# ESP32 arduino-cli Makefile

Generates a `Makefile` that wraps `arduino-cli` with practical, memorable targets for the day-to-day loop of working on an ESP32/Heltec Arduino sketch: find the board, install what's missing, compile, flash, and watch the serial output.

## When to use this skill

The user asks for a Makefile (or "build script", "CLI workflow") to compile/upload/monitor an ESP32 sketch, to list connected boards/ports, or to install the board core and libraries a sketch depends on — for an Arduino-CLI-based ESP32 project (this is not a PlatformIO or ESP-IDF `idf.py` skill; those have different tooling entirely).

## Prerequisite

`arduino-cli` must be installed (`brew install arduino-cli` on macOS). If it's missing, tell the user to install it before the Makefile is useful — do not silently assume it exists.

## How to generate the Makefile

1. **Check what's already installed** before writing anything, so the Makefile's defaults match reality instead of guessing:
   ```bash
   arduino-cli config dump                # board_manager.additional_urls (Heltec needs one, see below)
   arduino-cli core list                  # installed cores, e.g. esp32:esp32, Heltec-esp32:esp32
   arduino-cli lib list                   # installed libraries
   arduino-cli board list                 # connected boards + their auto-detected port and FQBN
   ```
2. **Pick the FQBN and core** for the target board (see table below). If a board is connected, `arduino-cli board list` already tells you its FQBN directly — prefer that over guessing.
3. **Find the sketch(es)** in the repo. arduino-cli requires a sketch to be a directory whose name matches its `.ino` file (`foo/foo.ino`). If the repo has multiple sketches (e.g. a `test/` or `examples/` directory with several such folders), make the sketch path a variable (`SKETCH ?=`) rather than hardcoding one, and default it to the most relevant one for the current task.
4. Write the Makefile below to the repo root (or wherever the user asks), substituting the variables' defaults for the project's actual board/sketch. Then run `make help` and `make list-ports` to sanity check it actually works in this environment before declaring it done.

## Heltec board FQBN reference

Two overlapping cores can provide the same board names — pick based on which library the sketch uses (`heltec.h` / `Heltec.begin()` legacy API works with either; `LoRaWan_APP.h` / `Mcu.begin()` newer API expects the Heltec-authored core):

| Core | Package | Notes |
|---|---|---|
| `Heltec-esp32:esp32` | Heltec's own core | Needed for `Mcu.begin()`, `LoRaWan_APP.h`, `VextON()/VextOFF()` newer API. Requires the board manager URL below. |
| `esp32:esp32` | Espressif's official core | Also ships the same Heltec board definitions; use for generic ESP32 code with no Heltec-specific library dependency. |

Board manager URL needed for the Heltec core (add once via `arduino-cli config init` then edit, or `arduino-cli config add board_manager.additional_urls <url>`):
```
https://resource.heltec.cn/download/package_heltec_esp32_index.json
```

Common FQBNs (`arduino-cli board listall | grep -i heltec` for the full/current list — board names change across core versions, so verify rather than trusting this table blindly):

| Board | FQBN (Heltec-esp32 core) |
|---|---|
| WiFi LoRa 32 (V2) | `Heltec-esp32:esp32:heltec_wifi_lora_32_V2` |
| WiFi LoRa 32 (V3) | `Heltec-esp32:esp32:heltec_wifi_lora_32_V3` |
| WiFi LoRa 32 (V4) | `Heltec-esp32:esp32:heltec_wifi_lora_32_V4` |
| WiFi Kit 32 (V3) | `Heltec-esp32:esp32:heltec_wifi_kit_32_V3` |
| Wireless Stick (V3) | `Heltec-esp32:esp32:heltec_wireless_stick_V3` |
| Wireless Tracker | `Heltec-esp32:esp32:heltec_wireless_tracker` |
| Wireless Paper | `Heltec-esp32:esp32:heltec_wireless_paper` |
| Vision Master E213 | `Heltec-esp32:esp32:heltec_vision_master_e_213` |
| Vision Master E290 | `Heltec-esp32:esp32:heltec_vision_master_e290` |
| Vision Master T190 | `Heltec-esp32:esp32:heltec_vision_master_t190` |

For a plain (non-Heltec) ESP32 devkit, use the `esp32:esp32` core with a generic FQBN such as `esp32:esp32:esp32` (classic devkit) or `esp32:esp32:esp32s3` (S3 devkit) — again, confirm the exact board id with `arduino-cli board listall`.

## The Makefile template

```makefile
# ESP32 / Heltec arduino-cli build harness.
# Override any variable on the command line, e.g.:
#   make compile SKETCH=test/oled BOARD=heltec_wifi_lora_32_V3
#   make upload PORT=/dev/cu.usbmodem21201

# --- Configuration -----------------------------------------------------

SKETCH    ?= test/heltec_quickstart
BOARD     ?= heltec_wifi_lora_32_V3
CORE      ?= Heltec-esp32:esp32
FQBN      ?= $(CORE):$(BOARD)
BAUD      ?= 115200
BUILD_DIR ?= build/$(BOARD)

# Auto-detect the first USB serial port arduino-cli sees; override with
# `make upload PORT=/dev/tty.XXXX` if multiple boards are connected.
PORT ?= $(shell arduino-cli board list 2>/dev/null | awk '/usbmodem|usbserial|ttyUSB|ttyACM/{print $$1; exit}')

# Libraries the project depends on (arduino-cli lib install names, quoted
# because most contain spaces). Edit this list to match the sketch.
LIBS := \
	"Heltec ESP32 Dev-Boards" \
	"heltec-eink-modules" \
	"Adafruit BME280 Library" \
	"Adafruit GFX Library" \
	"Adafruit BusIO" \
	"Adafruit Unified Sensor" \
	"U8g2" \
	"ArduinoJson"

BOARD_MANAGER_URL := https://resource.heltec.cn/download/package_heltec_esp32_index.json

# --- Help ---------------------------------------------------------------

.PHONY: help
help:
	@echo "Targets:"
	@echo "  boards        List all known Heltec/ESP32 board FQBNs"
	@echo "  list-ports    List connected boards and their ports"
	@echo "  install-core  Install/update the $(CORE) core"
	@echo "  install-libs  Install libraries required by the sketch"
	@echo "  libs          List currently installed libraries"
	@echo "  compile       Compile SKETCH=$(SKETCH) for BOARD=$(BOARD)"
	@echo "  upload        Compile then flash to PORT=$(PORT)"
	@echo "  monitor       Open a serial monitor at BAUD=$(BAUD)"
	@echo "  run           upload, then monitor"
	@echo "  size          Show flash/RAM usage after compiling"
	@echo "  erase         Full chip erase via esptool (destructive)"
	@echo "  clean         Remove local build artifacts"

# --- Discovery ------------------------------------------------------------

.PHONY: boards
boards:
	arduino-cli board listall | grep -i heltec

.PHONY: list-ports
list-ports:
	arduino-cli board list

# --- Setup ----------------------------------------------------------------

.PHONY: install-core
install-core:
	arduino-cli config add board_manager.additional_urls $(BOARD_MANAGER_URL)
	arduino-cli core update-index
	arduino-cli core install $(CORE)

.PHONY: install-libs
install-libs:
	arduino-cli lib install $(LIBS)

.PHONY: libs
libs:
	arduino-cli lib list

# --- Build / flash / monitor ----------------------------------------------

.PHONY: compile
compile:
	arduino-cli compile --fqbn $(FQBN) --build-path $(BUILD_DIR) $(SKETCH)

.PHONY: upload
upload: compile
	@if [ -z "$(PORT)" ]; then \
		echo "No serial port detected/set. Plug in the board or pass PORT=/dev/tty.XXXX"; \
		exit 1; \
	fi
	arduino-cli upload -p $(PORT) --fqbn $(FQBN) --input-dir $(BUILD_DIR) $(SKETCH)

.PHONY: flash
flash: upload

.PHONY: monitor
monitor:
	@if [ -z "$(PORT)" ]; then \
		echo "No serial port detected/set. Plug in the board or pass PORT=/dev/tty.XXXX"; \
		exit 1; \
	fi
	arduino-cli monitor -p $(PORT) -c baudrate=$(BAUD)

.PHONY: run
run: upload monitor

.PHONY: size
size:
	arduino-cli compile --fqbn $(FQBN) --build-path $(BUILD_DIR) --verbose $(SKETCH) | grep -E "Sketch uses|Global variables"

# --- Maintenance ------------------------------------------------------------

.PHONY: erase
erase:
	@if [ -z "$(PORT)" ]; then \
		echo "No serial port detected/set. Plug in the board or pass PORT=/dev/tty.XXXX"; \
		exit 1; \
	fi
	python3 -m esptool --port $(PORT) erase_flash

.PHONY: clean
clean:
	rm -rf build
```

## Gotchas to carry into the generated Makefile / to tell the user about

- **Sketch folder naming**: arduino-cli refuses to compile a directory whose name doesn't match its `.ino` file (`oled/oled.ino` works, `oled/sketch.ino` does not). If `SKETCH` points at a mismatched folder, `compile` fails with a clear but easy-to-miss error — mention this if compile fails immediately.
- **Port auto-detection can pick the wrong device**: on macOS, `arduino-cli board list` may also list Bluetooth/debug-console serial ports; the `PORT` shell snippet filters for common USB-serial patterns but still confirm with `make list-ports` when more than one real device is plugged in. On macOS prefer the `/dev/cu.*` device over `/dev/tty.*` (the `cu` device doesn't wait for DCD and is what arduino-cli itself reports).
- **Two cores can shadow each other**: if both `esp32:esp32` and `Heltec-esp32:esp32` are installed, the same board name resolves to two different FQBNs with different underlying `esp32` Arduino core versions — a sketch written against one may not compile against the other (e.g. `Mcu.begin()` only exists via the Heltec core's bundled library expectations). Keep `CORE` explicit rather than relying on a bare board name.
- **Linux serial permissions**: on Linux, upload/monitor will fail with a permissions error unless the user is in the `dialout` (or `uucp`) group — `sudo usermod -aG dialout $USER` then re-login, not something the Makefile itself can fix.
- **BOOT button on some boards**: a handful of ESP32 devkits (not most Heltec boards, which auto-reset) need the BOOT button held during the upload's flashing phase — if `upload` times out waiting to sync, this is the first thing to check.
- **`erase` is destructive** and wipes the whole flash including any NVS-stored calibration/config — don't wire it into `run` or any default target.
- **Multiple sketches in one repo**: don't hardcode one `SKETCH` if the repo has several (e.g. this repo's `test/*/`) — keep it a `?=` default overridable on the command line, and mention in `help` how to override it.
