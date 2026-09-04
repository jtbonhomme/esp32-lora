# ESP32Chat (Android)

Kotlin + Jetpack Compose companion app for `sketches/ble` — the Android
counterpart to `ios/ESP32Chat`, same feature set and branding. It scans for
a BLE peripheral advertising a specific name, connects to it, and lets you
send text messages that show up on the ESP32's OLED screen along with your
device's name.

## Requirements

- JDK 17+ (this repo's Makefile prefers a dedicated JDK 21 install if
  present — see `ANDROID_JAVA_HOME` in the root `Makefile`).
- Android SDK with `platforms;android-35` and `build-tools;35.0.0` (e.g.
  `brew install --cask android-commandlinetools`, or Android Studio's SDK
  Manager). Point `ANDROID_HOME` at it if it's not at the conventional
  `~/Library/Android/sdk` or Homebrew cask location.
- A physical Android phone with USB debugging enabled. **BLE does not work
  in the emulator** — you can build/run the UI there, but scanning will
  never find anything.

The Gradle wrapper (`gradlew`) is committed, so no local Gradle install is
required — the SDK/JDK above are the only prerequisites.

## Build & run

All targets below are driven from the root `Makefile` (run from the repo
root, not from this directory) — run `make help` there for the full list
alongside the firmware and iOS targets.

```sh
make android-build   # assemble a debug APK
make android-test    # run JVM unit tests
```

With a phone connected over USB (USB debugging enabled, and the
"Allow USB debugging" prompt accepted on the device):

```sh
make android-list-devices   # confirm adb sees it
make android-run            # build + install + launch
```

Other targets: `android-install` (build + install without launching),
`android-bundle` (signed release `.aab` for Play Store upload — needs
`ANDROID_KEYSTORE*` in a gitignored `Makefile.local` at the repo root, see
`Makefile.local.example`), `android-clean`.

## Matching the firmware's BLE name

The app scans for a peripheral whose advertised name equals the "ESP32 BLE
name" set in the app's Settings sheet (gear icon), default `Heltec-BLE` —
this must match whatever the firmware was built with
(`make upload SKETCH=sketches/ble BLE_NAME=YourName`, see the root
`Makefile`). Change it in Settings if you flashed the board with a custom
`BLE_NAME`. Devices running the firmware under a different name still show
up in an "Other ESP32 Chat devices nearby" section (scanning itself is
filtered by the GATT service UUID, not the name) — tap one to connect
anyway.

## Protocol

Messages are written to the RX characteristic as UTF-8 text in the form
`"<sender name>|<message text>"`. The firmware parses this and shows both
the sender name and message on the OLED. See `sketches/ble/ble.ino` for the
GATT service/characteristic UUIDs (Nordic UART Service) — identical to the
iOS app.

## Notes

- Runtime Bluetooth permissions are handled per Android version:
  `BLUETOOTH_SCAN` (flagged `neverForLocation`) + `BLUETOOTH_CONNECT` on
  Android 12+, `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` below that
  (BLE scanning required location permission pre-Android 12).
- The debug log (bug icon, top bar) mirrors the iOS app's: every GATT
  callback is logged with Android's status code, and `BluetoothGatt`
  connect calls are wrapped in the same manual timeout the iOS app uses,
  since neither platform's BLE API times out a hung connection on its own.
- The launcher icon reuses the iOS app's full-bleed square artwork rather
  than a proper Android adaptive icon (safe-zone foreground + background
  layers) — flagged by `./gradlew lintDebug` as a cosmetic
  `IconLauncherShape` warning, not a functional issue.
