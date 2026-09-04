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
	"U8g2" \
	"RadioLib"

BOARD_MANAGER_URL := https://resource.heltec.cn/download/package_heltec_esp32_index.json

# BLE advertised name for sketches/ble. Override on the command line or via
# environment, e.g.:
#   make compile SKETCH=sketches/ble BLE_NAME=MyDevice
#   BLE_NAME=MyDevice make upload SKETCH=sketches/ble
BLE_NAME ?= Heltec-BLE

# Extra compiler defines threaded into the build. Currently only used to
# override the BLE_DEVICE_NAME macro compiled into sketches/ble.
EXTRA_BUILD_PROPERTIES :=
ifeq ($(SKETCH),sketches/ble)
EXTRA_BUILD_PROPERTIES += --build-property 'compiler.cpp.extra_flags=-DBLE_DEVICE_NAME="$(BLE_NAME)"'
endif

# --- iOS app (ios/ESP32Chat) ---------------------------------------------

IOS_DIR             := ios/ESP32Chat
IOS_PROJECT         := $(IOS_DIR)/ESP32Chat.xcodeproj
IOS_SCHEME          := ESP32Chat
IOS_BUNDLE_ID       := com.jtbonhomme.ESP32Chat
IOS_SIMULATOR       ?= iPhone 17
IOS_BUILD_DIR       := $(IOS_DIR)/build
IOS_ARCHIVE_PATH    := $(IOS_BUILD_DIR)/$(IOS_SCHEME).xcarchive
IOS_EXPORT_OPTS_DIR := $(IOS_BUILD_DIR)/export-options

# DEVELOPMENT_TEAM (Apple Developer Team ID) and IOS_DEVICE_UDID (target
# iPhone, see `make ios-list-devices`) are personal/machine-specific, so
# they're kept out of the repo and loaded from Makefile.local (gitignored,
# see Makefile.local.example) instead of hardcoded here.
-include Makefile.local

IOS_GIT_DIRTY           := $(shell git status --porcelain 2>/dev/null)
IOS_GIT_SHORT           := $(shell git rev-parse --short=8 HEAD 2>/dev/null)
IOS_VERSION             := $(IOS_GIT_SHORT)$(if $(strip $(IOS_GIT_DIRTY)),-dirty)
IOS_BUILD_NUMBER        := $(shell git rev-list --count HEAD 2>/dev/null)
IOS_MARKETING_VERSION   := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
ifeq ($(strip $(IOS_MARKETING_VERSION)),)
IOS_MARKETING_VERSION := 1.0.0
endif

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
	@echo "                (SKETCH=sketches/ble also honors BLE_NAME=$(BLE_NAME))"
	@echo "  upload        Compile then flash to PORT=$(PORT)"
	@echo "  monitor       Open a serial monitor at BAUD=$(BAUD)"
	@echo "  run           upload, then monitor"
	@echo "  size          Show flash/RAM usage after compiling"
	@echo "  erase         Full chip erase via esptool (destructive)"
	@echo "  clean         Remove local build artifacts"
	@echo ""
	@echo "iOS app ($(IOS_DIR)):"
	@echo "  ios-build           Compile for the simulator (IOS_SIMULATOR=$(IOS_SIMULATOR))"
	@echo "  ios-test            Run unit tests on the simulator"
	@echo "  ios-run             build + install + launch on the simulator"
	@echo "  ios-build-device    Compile for a physical iPhone (DEVELOPMENT_TEAM required)"
	@echo "  ios-deploy-device   build-device + install on the iPhone (IOS_DEVICE_UDID required)"
	@echo "  ios-list-devices    List connected iPhones and their UDIDs"
	@echo "  ios-archive         Create a signed .xcarchive (Release, DEVELOPMENT_TEAM required)"
	@echo "  ios-export-appstore archive + export an App Store Connect .ipa"
	@echo "  ios-regen           Regenerate the Xcode project with XcodeGen"
	@echo "  ios-open            Open the project in Xcode"
	@echo "  ios-clean           Remove iOS build artifacts"
	@echo "  (DEVELOPMENT_TEAM / IOS_DEVICE_UDID come from Makefile.local, see Makefile.local.example)"

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
	arduino-cli compile --fqbn $(FQBN) --build-path $(BUILD_DIR) $(EXTRA_BUILD_PROPERTIES) $(SKETCH)

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
	arduino-cli compile --fqbn $(FQBN) --build-path $(BUILD_DIR) --verbose $(EXTRA_BUILD_PROPERTIES) $(SKETCH) | grep -E "Sketch uses|Global variables"

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

# --- iOS app (ios/ESP32Chat) -----------------------------------------------

.PHONY: ios-version ios-build ios-test ios-run ios-build-device \
        ios-deploy-device ios-list-devices ios-archive ios-export-appstore \
        ios-regen ios-open ios-clean

ios-version:
	@echo "$(IOS_VERSION)"

ios-build:
	xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) \
	  -destination 'platform=iOS Simulator,name=$(IOS_SIMULATOR)' \
	  build

ios-test:
	xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) \
	  -destination 'platform=iOS Simulator,name=$(IOS_SIMULATOR)' \
	  test

ios-run: ios-build
	xcrun simctl boot "$(IOS_SIMULATOR)" 2>/dev/null || true
	open -a Simulator
	xcrun simctl install booted "$(shell xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) \
	  -destination 'platform=iOS Simulator,name=$(IOS_SIMULATOR)' -showBuildSettings 2>/dev/null \
	  | awk -F' = ' '/ TARGET_BUILD_DIR /{d=$$2} / FULL_PRODUCT_NAME /{p=$$2} END{print d"/"p}')"
	xcrun simctl launch booted $(IOS_BUNDLE_ID)

# BLE doesn't work in the iOS Simulator (see ios/ESP32Chat/README.md), so
# these targets sign for and deploy to a real iPhone. Signing needs an
# Apple Developer team, supplied via Makefile.local (gitignored, see
# Makefile.local.example).
ios-build-device:
	@test -n "$(DEVELOPMENT_TEAM)" || { echo "DEVELOPMENT_TEAM required (see Makefile.local.example)"; exit 1; }
	xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) \
	  -destination 'generic/platform=iOS' \
	  -derivedDataPath $(IOS_BUILD_DIR) \
	  -allowProvisioningUpdates \
	  DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) \
	  CODE_SIGN_STYLE=Automatic \
	  build

ios-deploy-device: ios-build-device
	@if [ -z "$(IOS_DEVICE_UDID)" ]; then \
		echo "IOS_DEVICE_UDID required (make ios-deploy-device IOS_DEVICE_UDID=... or in Makefile.local, see make ios-list-devices)"; \
		exit 1; \
	fi
	ios-deploy -b $(IOS_BUILD_DIR)/Build/Products/Debug-iphoneos/$(IOS_SCHEME).app -i $(IOS_DEVICE_UDID)

ios-list-devices:
	xcrun xctrace list devices

# --- iOS archive & App Store export ----------------------------------------

ios-archive:
	@test -n "$(DEVELOPMENT_TEAM)" || { echo "DEVELOPMENT_TEAM required (see Makefile.local.example)"; exit 1; }
	mkdir -p $(IOS_BUILD_DIR)
	xcodebuild \
	  -project $(IOS_PROJECT) \
	  -scheme $(IOS_SCHEME) \
	  -configuration Release \
	  -archivePath $(IOS_ARCHIVE_PATH) \
	  -destination 'generic/platform=iOS' \
	  -allowProvisioningUpdates \
	  DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) \
	  CODE_SIGN_STYLE=Automatic \
	  MARKETING_VERSION=$(IOS_MARKETING_VERSION) \
	  CURRENT_PROJECT_VERSION=$(IOS_BUILD_NUMBER) \
	  clean archive

$(IOS_EXPORT_OPTS_DIR)/appstore.plist:
	@test -n "$(DEVELOPMENT_TEAM)" || { echo "DEVELOPMENT_TEAM required"; exit 1; }
	mkdir -p $(IOS_EXPORT_OPTS_DIR)
	sed 's/__TEAM_ID__/$(DEVELOPMENT_TEAM)/' $(IOS_DIR)/scripts/ExportOptions-appstore.plist.template > $@

ios-export-appstore: ios-archive $(IOS_EXPORT_OPTS_DIR)/appstore.plist
	xcodebuild -exportArchive \
	  -archivePath $(IOS_ARCHIVE_PATH) \
	  -exportPath $(IOS_BUILD_DIR)/export-appstore \
	  -allowProvisioningUpdates \
	  -exportOptionsPlist $(IOS_EXPORT_OPTS_DIR)/appstore.plist
	@echo "App Store IPA generated: $(IOS_BUILD_DIR)/export-appstore/$(IOS_SCHEME).ipa"

# --- iOS project maintenance -------------------------------------------------

ios-regen:
	cd $(IOS_DIR) && xcodegen generate

ios-open:
	open $(IOS_PROJECT)

ios-clean:
	xcodebuild -project $(IOS_PROJECT) -scheme $(IOS_SCHEME) clean
	rm -rf $(IOS_BUILD_DIR)
