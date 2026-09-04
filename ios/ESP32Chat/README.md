# ESP32Chat (iOS)

SwiftUI + CoreBluetooth companion app for `sketches/ble`. It scans for a BLE
peripheral advertising a specific name, connects to it, and lets you send
text messages that show up on the ESP32's OLED screen along with your
device's name.

## Requirements

- Xcode 16+ (deployment target iOS 16).
- A physical iPhone. **BLE does not work in the iOS Simulator** — you can
  build/run the UI there, but scanning will report "Bluetooth is not
  supported on this device".
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
  if you need to regenerate the `.xcodeproj` after editing `project.yml`.
  The generated project is committed, so this is optional for a normal
  build.

## Build & run

All targets below are driven from the root `Makefile` (run from the repo
root, not from this directory) — run `make help` there for the full list
alongside the firmware targets.

```sh
make ios-open           # open the project in Xcode
make ios-build          # compile for the simulator (IOS_SIMULATOR=iPhone 17)
make ios-run            # build, install and launch on the simulator (UI only — no BLE)
```

BLE requires a physical iPhone (see the requirement above), which needs
your Apple Developer Team ID and the device's UDID. Both are kept out of
the repo in a gitignored `Makefile.local` at the repo root:

```sh
cp Makefile.local.example Makefile.local   # then fill in DEVELOPMENT_TEAM
make ios-list-devices                      # find your iPhone's UDID, add it too
make ios-deploy-device                     # build for device + install over USB
```

Other targets: `ios-test`, `ios-archive` / `ios-export-appstore` (signed
`.xcarchive` / App Store Connect `.ipa`, also require `DEVELOPMENT_TEAM`),
`ios-clean`.

To regenerate the project after changing `project.yml`:

```sh
make ios-regen
```

## Matching the firmware's BLE name

The app scans for a peripheral whose advertised name equals the "ESP32 BLE
name" set in the app's Settings sheet (gear icon), default `Heltec-BLE` —
this must match whatever the firmware was built with
(`make upload SKETCH=sketches/ble BLE_NAME=YourName`, see the root
`Makefile`). Change it in Settings if you flashed the board with a custom
`BLE_NAME`.

## Protocol

Messages are written to the RX characteristic as UTF-8 text in the form
`"<sender name>|<message text>"`. The firmware parses this and shows both
the sender name and message on the OLED. See `sketches/ble/ble.ino` for the
GATT service/characteristic UUIDs (Nordic UART Service).
