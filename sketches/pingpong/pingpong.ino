/* Ping Pong communication test, WiFi LoRa 32 V4 (ESP32-S3 + SX1262)
 *
 * Function:
 * 1. Ping Pong communication between two boards.
 *
 * Description:
 * 1. Only hardware layer communication, no LoRaWAN protocol support;
 * 2. Download the same code into two boards, then they will ping-pong each other;
 * 3. Uses RadioLib to drive the SX1262 directly instead of Heltec's
 *    LoRaWan_APP.h / Mcu.begin() stack: on this exact board/library
 *    combination, Mcu.begin() hangs indefinitely and never returns,
 *    even with nothing else in setup() and every LoRa FEM/board-variant
 *    option tried. Meshtastic (which doesn't go through Mcu.begin())
 *    runs fine on the same hardware, confirming the radio itself works
 *    and the problem is specific to that precompiled library call.
 */

#include "Arduino.h"
#include <SPI.h>
#include <RadioLib.h>
#include "HT_SSD1306Wire.h" // Écran OLED SSD1306 128x64 en I2C matériel (broches fournies par le board package Heltec)
#include <stdarg.h>

// Broches du SX1262 sur WiFi LoRa 32 V4 / V4_R8 (cf. driver/board-config.h du
// package Heltec-esp32 : RADIO_NSS=8, LORA_CLK=9, LORA_MOSI=10, LORA_MISO=11,
// RADIO_RESET=12, RADIO_BUSY=13, RADIO_DIO_1=14 - identiques sur les deux variantes)
#define LORA_NSS    8
#define LORA_SCK    9
#define LORA_MOSI   10
#define LORA_MISO   11
#define LORA_RST    12
#define LORA_BUSY   13
#define LORA_DIO1   14
// Broche d'activation du front-end RF (GC1109 ou KCT8103L selon la révision
// V4.2/V4.3) : LORA_PA_EN / LORA_PA_CSD = GPIO2 dans les deux cas, à maintenir
// HIGH en permanence (cf. retour d'expérience RadioLib sur Heltec V4).
#define LORA_FEM_EN 2

SX1262 radio = new Module(LORA_NSS, LORA_DIO1, LORA_RST, LORA_BUSY);

// Écran OLED utilisé comme équivalent visuel des logs série
static SSD1306Wire display(0x3c, 500000, SDA_OLED, SCL_OLED, GEOMETRY_128_64, RST_OLED);

void VextON(void) {
  pinMode(Vext, OUTPUT);
  digitalWrite(Vext, LOW); // LOW = alimentation Vext activée
}

// Journalise un message à la fois sur le port série et sur l'écran OLED
// (défilement automatique via le log buffer, comme un mini terminal série)
void logLine(const char *fmt, ...) {
  char buf[64];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);

  Serial.println(buf);

  display.clear();
  display.println(buf); // ajoute la ligne au log buffer (gère le \n)
  display.drawLogBuffer(0, 0);
  display.display();
}

#define RF_FREQUENCY_MHZ                            865.0     // MHz
#define LORA_BANDWIDTH_KHZ                          125.0     // kHz
#define LORA_SPREADING_FACTOR                       11        // [SF7..SF12]
#define LORA_CODINGRATE                              5        // 4/5
#define LORA_SYNC_WORD                               RADIOLIB_SX126X_SYNC_WORD_PRIVATE
#define TX_OUTPUT_POWER                             22        // dBm
#define LORA_PREAMBLE_LENGTH                         8         // symbols

#define RX_WINDOW_MS                                 2000      // délai d'attente d'une réponse avant de retransmettre
#define BUFFER_SIZE                                 30        // Define the payload size here

char txpacket[BUFFER_SIZE];

int16_t txNumber;
int16_t Rssi;

typedef enum
{
    STATE_TX,
    STATE_WAIT_TX,
    STATE_START_RX,
    STATE_WAIT_RX
}States_t;

States_t state;
uint32_t rxStartMs;

volatile bool radioActionDone = false;
void radioISR(void) {
  radioActionDone = true;
}

void setup() {
    Serial.begin(115200);
    delay(1000); // laisser le temps à l'hôte USB CDC de se connecter avant les premiers logs

    VextON();
    delay(100);
    display.init();
    display.setContrast(255);
    display.setFont(ArialMT_Plain_10);
    display.setTextAlignment(TEXT_ALIGN_LEFT);
    display.setLogBuffer(6, 28);

    txNumber = 0;
    Rssi = 0;

    pinMode(LORA_FEM_EN, OUTPUT);
    digitalWrite(LORA_FEM_EN, HIGH); // active le front-end RF en permanence

    SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_NSS);

    int st = radio.begin(RF_FREQUENCY_MHZ, LORA_BANDWIDTH_KHZ, LORA_SPREADING_FACTOR,
                          LORA_CODINGRATE, LORA_SYNC_WORD, TX_OUTPUT_POWER, LORA_PREAMBLE_LENGTH);
    if (st != RADIOLIB_ERR_NONE) {
        logLine("Radio begin FAIL %d", st);
        while (true) { delay(1000); }
    }
    radio.setDio2AsRfSwitch(true);
    radio.setCRC(true);
    radio.explicitHeader();

    radio.setPacketSentAction(radioISR);
    radio.setPacketReceivedAction(radioISR);

    state = STATE_TX;

    logLine("PingPong ready");
}

void loop()
{
  switch(state)
  {
    case STATE_TX: {
      delay(1000);
      txNumber++;
      sprintf(txpacket,"hello %d, Rssi : %d",txNumber,Rssi);
      logLine("TX: %s (%d)", txpacket, (int)strlen(txpacket));
      radioActionDone = false;
      int st = radio.startTransmit((uint8_t *)txpacket, strlen(txpacket));
      if (st != RADIOLIB_ERR_NONE) {
        logLine("TX start fail %d", st);
        break; // reessaie au prochain tour de loop()
      }
      state = STATE_WAIT_TX;
      break;
    }
    case STATE_WAIT_TX:
      if (radioActionDone) {
        radioActionDone = false;
        radio.finishTransmit();
        logLine("TX done");
        state = STATE_START_RX;
      }
      break;
    case STATE_START_RX:
      logLine("into RX mode");
      radioActionDone = false;
      radio.startReceive();
      rxStartMs = millis();
      state = STATE_WAIT_RX;
      break;
    case STATE_WAIT_RX:
      if (radioActionDone) {
        radioActionDone = false;
        char rxpacket[BUFFER_SIZE];
        size_t len = radio.getPacketLength();
        if (len >= BUFFER_SIZE) len = BUFFER_SIZE - 1;
        int st = radio.readData((uint8_t *)rxpacket, len);
        rxpacket[len] = '\0';
        if (st == RADIOLIB_ERR_NONE) {
          Rssi = (int16_t)radio.getRSSI();
          logLine("RX: %s (%d,%ddB)", rxpacket, (int)len, Rssi);
          logLine("wait next TX");
        } else {
          logLine("RX fail %d", st);
        }
        state = STATE_TX;
      } else if (millis() - rxStartMs > RX_WINDOW_MS) {
        radio.standby();
        logLine("RX timeout");
        state = STATE_TX;
      }
      break;
  }
}
