#define VEXT_PIN 40

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("BEFORE_VEXT");
  pinMode(VEXT_PIN, OUTPUT);
  digitalWrite(VEXT_PIN, LOW); // enable OLED power rail, no I2C touched
}

void loop() {
  Serial.println("ALIVE");
  delay(300);
}
