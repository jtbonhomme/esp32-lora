---
name: sd-card
description: Concrete patterns for reading and writing an SD/Micro TF card over SPI on Heltec ESP32 boards using FS.h/SD.h, including SPIClass pin setup, SD.begin(), file open/read/write/append/rename/delete, directory listing with timestamps, and NTP-synced timestamped data logging.
version: 1.0.0
---

# SD Card (SPI) on Heltec ESP32

Reusable knowledge extracted from HelTec AutoMation's `SD_Time` example (Heltec_ESP32_Dev-Boards `examples/SD/SD_Time/SD_Time.ino`). This is the only example in that tree — it demonstrates Micro TF (microSD) card access over a **dedicated SPI bus** plus NTP time sync so file timestamps / logged records are meaningful.

## When to use this skill

Use this when writing or reviewing Heltec ESP32 firmware that needs to:
- Mount and read/write a Micro SD (TF) card over SPI (`FS.h`, `SD.h`, `SPI.h`).
- Log timestamped data to a file (sensor readings, LoRa packets, events).
- List, create, or remove directories/files on the card.
- Get the current time via NTP (`WiFi.h`, `configTime`, `getLocalTime`) to stamp log entries or check file `getLastWrite()` times.

## What the example demonstrates

`SD_Time.ino`: connects to WiFi, syncs time via NTP, then mounts a Micro TF card on a **second SPI bus** (`SPIClass spi1` — not the default `SPI`), prints card type/size, and exercises the full basic file API: list directory (recursive with write timestamps), create/remove directory, write, append, read, rename, delete.

## Wiring (from the header comment)

```
SD_CS   -- GPIO22
SD_MOSI -- GPIO23
SD_SCK  -- GPIO17
SD_MISO -- GPIO13
```

This is a custom SPI pin mapping (not the ESP32 default VSPI/HSPI pins), which is why the example explicitly instantiates a second `SPIClass` and calls `.begin()` with these four pins rather than relying on the default `SPI` object.

## Includes

```cpp
#include "FS.h"
#include "SD.h"
#include "SPI.h"
#include <time.h>
#include <WiFi.h>
```

## SPI bus + SD.begin() pattern

```cpp
SPIClass spi1;
...
SPIClass(1);                       // select SPI host 1
spi1.begin(17, 13, 23, 22);        // (SCK, MISO, MOSI, SS/CS)

if(!SD.begin(22, spi1)){           // SD.begin(csPin, spiInstance)
    Serial.println("Card Mount Failed");
    return;
}
uint8_t cardType = SD.cardType();

if(cardType == CARD_NONE){
    Serial.println("No SD card attached");
    return;
}

Serial.print("SD Card Type: ");
if(cardType == CARD_MMC){
    Serial.println("MMC");
} else if(cardType == CARD_SD){
    Serial.println("SDSC");
} else if(cardType == CARD_SDHC){
    Serial.println("SDHC");
} else {
    Serial.println("UNKNOWN");
}

uint64_t cardSize = SD.cardSize() / (1024 * 1024);
Serial.printf("SD Card Size: %lluMB\n", cardSize);
```

**Gotcha:** always check the return of `SD.begin()` and `cardType() == CARD_NONE` before touching the filesystem — a missing/unseated card or wrong CS pin fails silently otherwise. There is no separate card-detect pin used in this example; card presence is inferred purely from `SD.begin()` / `cardType()`.

## File API used (all take `fs::FS &fs` so they work against `SD` or other filesystems)

**List directory, recursive, with timestamps:**
```cpp
void listDir(fs::FS &fs, const char * dirname, uint8_t levels){
    File root = fs.open(dirname);
    if(!root || !root.isDirectory()){ return; }
    File file = root.openNextFile();
    while(file){
        if(file.isDirectory()){
            time_t t = file.getLastWrite();
            struct tm * tmstruct = localtime(&t);
            // recurse if levels > 0: listDir(fs, file.name(), levels - 1);
        } else {
            Serial.print(file.size());
            time_t t = file.getLastWrite();
            struct tm * tmstruct = localtime(&t);
            // tmstruct->tm_year + 1900, tm_mon + 1, tm_mday, tm_hour, tm_min, tm_sec
        }
        file = root.openNextFile();
    }
}
```

**Create / remove directory:**
```cpp
fs.mkdir(path);   // returns bool
fs.rmdir(path);   // returns bool
```

**Write (truncate/create) and append:**
```cpp
File file = fs.open(path, FILE_WRITE);   // truncates or creates
file.print(message);
file.close();

File file2 = fs.open(path, FILE_APPEND); // opens for append — use this for log files
file2.print(message);
file2.close();
```

**Read:**
```cpp
File file = fs.open(path);   // default mode = read
while(file.available()){
    Serial.write(file.read());
}
file.close();
```

**Rename / delete:**
```cpp
fs.rename(path1, path2);   // returns bool
fs.remove(path);           // returns bool
```

Every call checks the returned `File`/`bool` for truthiness before use — none of these Arduino SD APIs throw; they fail silently and must be checked (`if(!file){ ... return; }`).

## Timestamped logging pattern (combine NTP + SD)

The example gets real time via NTP before touching the SD card, which is the pattern to reuse for timestamped log entries:

```cpp
configTime(3600*timezone, daysavetime*3600, "time.nist.gov", "0.pool.ntp.org", "1.pool.ntp.org");
struct tm tmstruct;
tmstruct.tm_year = 0;
getLocalTime(&tmstruct, 5000);   // 5000ms timeout
Serial.printf("Now is : %d-%02d-%02d %02d:%02d:%02d\n",
    (tmstruct.tm_year)+1900, (tmstruct.tm_mon)+1, tmstruct.tm_mday,
    tmstruct.tm_hour, tmstruct.tm_min, tmstruct.tm_sec);
```

To log a timestamped record: format a line with the `tmstruct` fields above and pass it to `appendFile(SD, "/log.txt", line)` using `FILE_APPEND` (not `FILE_WRITE`, which truncates). Requires WiFi connectivity for the NTP sync step — if no WiFi is available, fall back to a monotonic counter or an RTC module for timestamps instead.

## Gotchas / notes observed in the example

- **Wrong SPI instance is a common bug source**: this board's SD wiring does not match the default SPI pins, so a plain `SD.begin()` (no args) would fail — must construct a second `SPIClass`, call `.begin(sck, miso, mosi, cs)`, and pass both the CS pin and the SPI instance to `SD.begin(cs, spi)`.
- **CS pin doubles as chip-select argument** to `SD.begin()` — GPIO22 here; must match the physical wiring.
- **All FS calls should be null/false-checked** — `fs.open()` returns a falsy `File` on failure, `mkdir`/`rmdir`/`rename`/`remove` return `bool`.
- **`FILE_WRITE` truncates**, `FILE_APPEND` preserves existing content — pick `FILE_APPEND` for logs, `FILE_WRITE` for fresh/overwritten files.
- **`getLastWrite()`** returns a `time_t` usable with `localtime()` for human-readable file timestamps — useful for verifying log file freshness without opening the file.
- No explicit handling of a card-detect (CD) pin or hot-swap in this example — assume the card is present at boot and re-check `SD.begin()`'s return value defensively in real firmware.
