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

```sh
open ESP32Chat.xcodeproj
```

Select your iPhone as the run destination, set your Apple Development Team
under the target's Signing & Capabilities tab, and run.

To regenerate the project after changing `project.yml`:

```sh
xcodegen generate
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
