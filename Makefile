# ESP32 / Heltec arduino-cli build harness for the Heltec WiFi LoRa 32 (V4) devkit.
# Override any variable on the command line, e.g.:
#   make compile SKETCH=sketches/oled
#   make upload PORT=/dev/cu.usbmodem21201

# --- Configuration -----------------------------------------------------

SKETCH    ?= sketches/heltec_quickstart
BOARD     ?= heltec_wifi_lora_32_V4
CORE      ?= Heltec-esp32:esp32
FQBN      ?= $(CORE):$(BOARD)
BAUD      ?= 115200
BUILD_DIR ?= build/$(BOARD)

# Auto-detect the first USB serial port arduino-cli sees; override with
# `make upload PORT=/dev/tty.XXXX` if multiple boards are connected.
PORT ?= $(shell arduino-cli board list 2>/dev/null | awk '/usbmodem|usbserial|ttyUSB|ttyACM/{print $$1; exit}')

# Libraries the sketches in this repo depend on (arduino-cli lib install
# names, quoted because they contain spaces). Edit this list if a new
# sketch pulls in something else.
LIBS := \
	"Heltec ESP32 Dev-Boards" \
	"U8g2"

BOARD_MANAGER_URL := https://resource.heltec.cn/download/package_heltec_esp32_index.json

# --- Help ---------------------------------------------------------------

.PHONY: help
help:
	@echo "Targets:"
	@echo "  boards        List all known Heltec/ESP32 board FQBNs"
	@echo "  list-ports    List connected boards and their ports"
	@echo "  install-core  Install/update the $(CORE) core"
	@echo "  install-libs  Install libraries required by the sketches"
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
