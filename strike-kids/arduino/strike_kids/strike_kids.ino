// STRIKE KIDS - ARDUINO DA MAQUINA
// ================================
// Le os 5 SENSORES da pista, o botao de CONFIGURACAO (e, se ligados, o
// START e o moedeiro), comanda a TRAVA da porta (servo e/ou rele) e a fita
// de LED. Conversa com a TV Box pelo cabo USB (9600, linhas de texto).
//
// Placas: Arduino Uno, Nano (original ou clone CH340), Pro Mini 5 V,
// Mega 2560 e Leonardo/Micro.
//
// LIGACOES (padrao - mude abaixo se precisar)
//   Sensores, da ESQUERDA para a DIREITA (olhando da crianca para os pinos):
//     S1 = D2   S2 = D3   S3 = D4 (centro)   S4 = D5   S5 = D7
//     Sensor optico/infravermelho com saida NPN, chave ou micro-switch:
//     o sinal no pino e o GND no GND do Arduino (o pino ja tem pull-up).
//     Sensor que precisa de 12 V: alimentacao pela fonte de 12 V, GND
//     comum com o Arduino, e SO o fio de sinal no pino (saida NPN).
//   Botao de CONFIGURACAO (entra e sai do menu do operador): A0 e GND
//   Botao START (opcional; o START da Zero Delay tambem vale): A1 e GND
//   Moedeiro / FICHA (opcional): A2 e GND
//   TRAVA (porta das bolas):
//     SERVO: sinal no D9 (Mega: D11). Alimente o servo por uma fonte
//            de 5-6 V propria (servo grande puxa muita corrente) e ligue o
//            GND dessa fonte no GND do Arduino.
//     RELE:  D8 -> entrada (IN) de um modulo rele (para trava solenoide,
//            motor ou eletroima). Veja RELE_LIGA_EM_LOW e RELE_TEMPO_MAX_S.
//   Fita de LED WS2812 (NeoPixel), opcional: D6
//   LED da placa (D13): pisca a cada sensor/botao acionado.
//
// A PORTA comeca FECHADA. O jogo manda ABRIR depois do START e FECHAR no
// fim da partida. Se o jogo sumir (cabo solto, TV Box desligada) com a
// porta aberta, ela fecha sozinha em 15 s.
//
// Sem fita de LED (ou sem a biblioteca "Adafruit NeoPixel" instalada):
// troque USAR_LEDS para 0.

#include <EEPROM.h>

// ------------------------------------------------------------ AJUSTES
#define USAR_LEDS 1          // 1 = tem fita de LED no D6 (biblioteca Adafruit NeoPixel)
#define LED_PINO 6
#define NUM_LEDS 60
#define BRILHO 180

const uint8_t SENSOR_PINOS[5] = {2, 3, 4, 5, 7};
#define CONFIG_PINO A0
#define START_PINO A1
#define FICHA_PINO A2
#define RELE_PINO 8
#define LED_PLACA 13

// Servo da trava: angulo com a porta FECHADA e ABERTA (0 a 180).
#define SERVO_FECHADA 0
#define SERVO_ABERTA 90
#define SERVO_GRAUS_POR_S 240     // velocidade do movimento
#define SERVO_SOLTA_PARADO 0      // 1 = para de segurar 1 s depois de chegar

// Rele da trava.
#define RELE_LIGA_EM_LOW 1        // modulo rele comum liga com LOW; o seu liga com HIGH? troque para 0
#define RELE_LIGADO_ABERTA 1      // 1 = rele ligado com a porta aberta; 0 = ligado com ela fechada
#define RELE_TEMPO_MAX_S 0        // 0 = sem limite. Trava SOLENOIDE comum nao pode ficar
                                  // ligada muito tempo: ponha 5 (liga 5 s e desliga)

#define FILTRO_SENSOR_MS 2        // o sinal precisa ficar assim este tempo
#define REARME_SENSOR_MS 120      // a mesma bola balancando no sensor nao conta 2 vezes
#define FILTRO_BOTAO_MS 25
#define FILTRO_FICHA_MS 5         // moedeiro manda pulsos curtos (20 ms ou mais)
#define SEM_JOGO_FECHA_MS 15000UL // sem noticia do jogo: fecha a porta
#define VERSAO "1"

#if USAR_LEDS
#include <Adafruit_NeoPixel.h>
Adafruit_NeoPixel fita(NUM_LEDS, LED_PINO, NEO_GRB + NEO_KHZ800);
#endif

#if defined(__AVR_ATmega2560__) || defined(__AVR_ATmega1280__)
#define SERVO_PINO 11             // OC1A no Mega
#else
#define SERVO_PINO 9              // OC1A no Uno/Nano/Pro Mini/Leonardo
#endif
#define PASSOS_POR_US (F_CPU / 8000000UL)  // Timer1 com prescaler 8

// ------------------------------------------------------------ tipos
// TODOS os tipos ficam aqui no comeco, antes da primeira funcao: a IDE do
// Arduino escreve sozinha a "declaracao" de cada funcao logo antes da
// primeira funcao do arquivo; um tipo declarado mais abaixo ainda nao
// existiria ali (era o erro "'Efeito' was not declared in this scope").
enum Efeito { MENU, IDLE, STRIKE, MISS, SPARE, NORMAL, BLUE, RED, OFF };

// ------------------------------------------------------------ entradas
struct Entrada {
  uint8_t pino;
  uint8_t repouso;      // nivel lido sem nada acionando (HIGH com pull-up)
  bool leitura;         // acionado agora (sem filtro)
  bool estavel;         // acionado (filtrado)
  unsigned long mudouEm;
  unsigned long ultimoEvento;
  uint8_t filtro;
  uint16_t rearme;
  const char *evento;
};

Entrada sensores[5];
Entrada botoes[3];
const char *const NOMES_SENSOR[5] = {"S:1", "S:2", "S:3", "S:4", "S:5"};

bool streamSensores = false;   // TESTE:1 -> manda SENS: a cada mudanca
unsigned long ultimoComando = 0;
unsigned long piscarAte = 0;

// ------------------------------------------------------------ porta
bool portaAberta = false;
int16_t servoAtual10 = SERVO_FECHADA * 10;  // decimos de grau
int16_t servoAlvo10 = SERVO_FECHADA * 10;
unsigned long servoPasso = 0;
unsigned long servoChegou = 0;
bool servoSegurando = true;
unsigned long releLigouEm = 0;
bool releLigado = false;

// ------------------------------------------------------------ serial
char buf[24];
uint8_t bufLen = 0;

void enviarSensores();

// ============================================================ EEPROM
// endereco 0: 0x5B (marca)  1: niveis de repouso dos sensores (bit 1 = HIGH)
#define EE_MARCA 0
#define EE_REPOUSO 1

void carregarRepouso() {
  uint8_t mascara = 0x1F;  // padrao: todos em HIGH (pull-up, aciona em LOW)
  if (EEPROM.read(EE_MARCA) == 0x5B) mascara = EEPROM.read(EE_REPOUSO);
  for (uint8_t i = 0; i < 5; i++) sensores[i].repouso = (mascara >> i) & 1 ? HIGH : LOW;
}

void calibrar() {
  // le cada sensor varias vezes: o nivel de agora (pista vazia) e o repouso
  uint8_t mascara = 0;
  for (uint8_t i = 0; i < 5; i++) {
    uint8_t altos = 0;
    for (uint8_t k = 0; k < 15; k++) {
      if (digitalRead(sensores[i].pino) == HIGH) altos++;
      delay(2);
    }
    if (altos >= 8) mascara |= (1 << i);
  }
  EEPROM.update(EE_MARCA, 0x5B);
  EEPROM.update(EE_REPOUSO, mascara);
  carregarRepouso();
  for (uint8_t i = 0; i < 5; i++) {
    sensores[i].leitura = false;
    sensores[i].estavel = false;
  }
  Serial.print(F("CAL:OK:"));
  for (uint8_t i = 0; i < 5; i++) Serial.print(sensores[i].repouso == HIGH ? 'H' : 'L');
  Serial.println();
  enviarSensores();
}

// ============================================================ porta
uint16_t pulsoUs(int16_t graus10) {
  // como a biblioteca Servo: 544 us = 0 grau, 2400 us = 180 graus
  return 544 + (int32_t)graus10 * (2400 - 544) / 1800;
}

void servoIniciar() {
  digitalWrite(SERVO_PINO, LOW);
  pinMode(SERVO_PINO, OUTPUT);
  // Timer1 no modo 14 (PWM rapido, topo = ICR1), prescaler 8: o pulso sai
  // do proprio Timer1, firme mesmo quando a fita de LED segura o processador.
  TCCR1A = _BV(COM1A1) | _BV(WGM11);
  TCCR1B = _BV(WGM13) | _BV(WGM12) | _BV(CS11);
  ICR1 = 20000UL * PASSOS_POR_US - 1;  // 20 ms
  OCR1A = pulsoUs(servoAtual10) * PASSOS_POR_US;
  servoSegurando = true;
}

void servoSegurar(bool sim) {
  if (sim == servoSegurando) return;
  servoSegurando = sim;
  if (sim) {
    TCCR1A |= _BV(COM1A1);
  } else {
    TCCR1A &= ~_BV(COM1A1);
    digitalWrite(SERVO_PINO, LOW);
  }
}

void tickServo(unsigned long agora) {
  if (servoAtual10 != servoAlvo10) {
    if (agora - servoPasso >= 10) {
      int16_t passo = (int16_t)((uint32_t)SERVO_GRAUS_POR_S * 10UL * (agora - servoPasso) / 1000UL);
      if (passo < 1) passo = 1;
      servoPasso = agora;
      if (servoAtual10 < servoAlvo10) {
        servoAtual10 = min((int16_t)(servoAtual10 + passo), servoAlvo10);
      } else {
        servoAtual10 = max((int16_t)(servoAtual10 - passo), servoAlvo10);
      }
      servoSegurar(true);
      OCR1A = pulsoUs(servoAtual10) * PASSOS_POR_US;
      if (servoAtual10 == servoAlvo10) servoChegou = agora;
    }
  } else if (SERVO_SOLTA_PARADO && servoSegurando && agora - servoChegou > 1000) {
    servoSegurar(false);
  }
}

void releEscrever(bool ligado) {
  releLigado = ligado;
  bool nivel = ligado ? !RELE_LIGA_EM_LOW : RELE_LIGA_EM_LOW;
  digitalWrite(RELE_PINO, nivel ? HIGH : LOW);
}

void porta(bool abrir) {
  portaAberta = abrir;
  servoAlvo10 = (abrir ? SERVO_ABERTA : SERVO_FECHADA) * 10;
  servoPasso = millis();
  bool ligar = RELE_LIGADO_ABERTA ? abrir : !abrir;
  if (ligar && !releLigado) releLigouEm = millis();
  releEscrever(ligar);
  Serial.println(abrir ? F("PORTA:ABERTA") : F("PORTA:FECHADA"));
}

void tickRele(unsigned long agora) {
  if (RELE_TEMPO_MAX_S > 0 && releLigado && agora - releLigouEm > (unsigned long)RELE_TEMPO_MAX_S * 1000UL) {
    releEscrever(false);  // protege a solenoide; a porta continua "aberta" para o jogo
  }
}

// ============================================================ entradas
void iniciarEntrada(Entrada &e, uint8_t pino, uint8_t filtro, uint16_t rearme, const char *evento) {
  e.pino = pino;
  e.repouso = HIGH;
  e.leitura = false;
  e.estavel = false;
  e.mudouEm = 0;
  e.ultimoEvento = 0;
  e.filtro = filtro;
  e.rearme = rearme;
  e.evento = evento;
  pinMode(pino, INPUT_PULLUP);
}

// devolve true quando o estado filtrado mudou
bool tickEntrada(Entrada &e, unsigned long agora, bool &disparou) {
  disparou = false;
  bool ativo = digitalRead(e.pino) != e.repouso;
  if (ativo != e.leitura) {
    e.leitura = ativo;
    e.mudouEm = agora;
  }
  if (e.leitura != e.estavel && agora - e.mudouEm >= e.filtro) {
    e.estavel = e.leitura;
    if (e.estavel && (e.ultimoEvento == 0 || agora - e.ultimoEvento >= e.rearme)) {
      e.ultimoEvento = agora;
      disparou = true;
    }
    return true;
  }
  return false;
}

void enviarSensores() {
  Serial.print(F("SENS:"));
  for (uint8_t i = 0; i < 5; i++) Serial.print(sensores[i].estavel ? '1' : '0');
  Serial.println();
}

void piscar(unsigned long agora) {
  digitalWrite(LED_PLACA, HIGH);
  piscarAte = agora + 60;
}

// ============================================================ LEDs
#if USAR_LEDS
Efeito efeito = MENU;
unsigned long ledUltimo = 0;
uint16_t menuOffset = 0;
int ondaPos = 0, ondaDir = 1, ondaVolta = 0, ondaMax = 0, ondaMs = 38, ondaRastro = 8;
uint8_t cR = 0, cG = 60, cB = 220, rR = 0, rG = 0, rB = 140;
unsigned long strikeSegura = 0;

void setTodos(uint32_t cor) {
  for (int i = 0; i < NUM_LEDS; i++) fita.setPixelColor(i, cor);
  fita.show();
}

void setOnda(Efeito e, int maxV, int ms, int rastro, uint8_t cr, uint8_t cg, uint8_t cb, uint8_t rr, uint8_t rg, uint8_t rb) {
  efeito = e;
  strikeSegura = 0;
  ondaPos = 0; ondaDir = 1; ondaVolta = 0;
  ondaMax = maxV; ondaMs = ms; ondaRastro = rastro;
  cR = cr; cG = cg; cB = cb; rR = rr; rG = rg; rB = rb;
  ledUltimo = 0;
}

void ledComando(const char *c) {
  if (!strcmp(c, "MENU")) { efeito = MENU; menuOffset = 0; ledUltimo = 0; }
  else if (!strcmp(c, "BLUE")) { efeito = BLUE; setTodos(fita.Color(0, 40, 255)); }
  else if (!strcmp(c, "RED")) { efeito = RED; setTodos(fita.Color(255, 0, 0)); }
  else if (!strcmp(c, "IDLE")) setOnda(IDLE, 0, 42, 8, 0, 45, 180, 0, 0, 100);
  else if (!strcmp(c, "MISS")) setOnda(MISS, 5, 15, 14, 255, 0, 0, 170, 0, 0);
  else if (!strcmp(c, "SPARE")) setOnda(SPARE, 5, 24, 11, 255, 170, 0, 180, 95, 0);
  else if (!strcmp(c, "NORMAL")) setOnda(NORMAL, 3, 22, 10, 0, 180, 255, 0, 90, 190);
  else if (!strcmp(c, "STRIKE")) setOnda(STRIKE, 8, 6, 22, 0, 80, 255, 0, 0, 255);
  else if (!strcmp(c, "OFF")) { efeito = OFF; setTodos(0); }
}

void tickLeds(unsigned long agora) {
  if (strikeSegura && (long)(agora - strikeSegura) >= 0) {
    strikeSegura = 0;
    ledComando("IDLE");
  }
  if (efeito == MENU) {
    if (agora - ledUltimo < 20) return;
    ledUltimo = agora;
    // arco-iris andando (contas inteiras: rapido, nao atrasa os sensores)
    for (int i = 0; i < NUM_LEDS; i++) {
      uint16_t h = menuOffset + (uint16_t)((uint32_t)i * 65536UL / NUM_LEDS);
      fita.setPixelColor(i, fita.gamma32(fita.ColorHSV(h, 255, 255)));
    }
    fita.show();
    menuOffset += 420;
    return;
  }
  if (efeito == OFF || efeito == BLUE || efeito == RED) return;
  if (agora - ledUltimo < (unsigned long)ondaMs) return;
  ledUltimo = agora;
  fita.clear();
  for (int r = 0; r < ondaRastro; r++) {
    int pos = ondaPos - r * ondaDir;
    if (pos < 0 || pos >= NUM_LEDS) continue;
    if (r == 0) {
      fita.setPixelColor(pos, fita.Color(cR, cG, cB));
    } else {
      uint16_t t = 256 - (uint16_t)r * 256 / ondaRastro;
      fita.setPixelColor(pos, fita.Color((uint16_t)rR * t >> 8, (uint16_t)rG * t >> 8, (uint16_t)rB * t >> 8));
    }
  }
  fita.show();
  if (efeito == STRIKE) {
    ondaPos += ondaDir;
    if (ondaPos >= NUM_LEDS - 1) { ondaPos = NUM_LEDS - 1; ondaDir = -1; ondaVolta++; }
    else if (ondaPos <= 0) { ondaPos = 0; ondaDir = 1; ondaVolta++; }
  } else {
    ondaPos++;
    if (ondaPos >= NUM_LEDS + ondaRastro) { ondaPos = 0; ondaVolta++; }
  }
  if (ondaMax > 0 && ondaVolta >= ondaMax) {
    if (efeito == STRIKE) {
      setTodos(fita.Color(0, 50, 255));
      efeito = BLUE;
      strikeSegura = agora + 750;
      return;
    }
    ledComando("IDLE");
  }
}
#endif

// ============================================================ comandos
void executar(const char *c) {
  ultimoComando = millis();
  if (!strcmp(c, "PING")) {
    Serial.println(F("PONG:STRIKE_KIDS:" VERSAO));
  } else if (!strcmp(c, "PORTA:ABRE")) {
    porta(true);
  } else if (!strcmp(c, "PORTA:FECHA")) {
    porta(false);
  } else if (!strcmp(c, "PORTA?")) {
    Serial.println(portaAberta ? F("PORTA:ABERTA") : F("PORTA:FECHADA"));
  } else if (!strcmp(c, "SENS?")) {
    enviarSensores();
  } else if (!strcmp(c, "TESTE:1")) {
    streamSensores = true;
    enviarSensores();
  } else if (!strcmp(c, "TESTE:0")) {
    streamSensores = false;
  } else if (!strcmp(c, "CALIBRA")) {
    calibrar();
  } else if (!strcmp(c, "INFO?")) {
    Serial.print(F("INFO:STRIKE_KIDS:" VERSAO ":LEDS="));
    Serial.print(USAR_LEDS);
    Serial.print(F(":SERVO="));
    Serial.print(SERVO_PINO);
    Serial.print(F(":RELE="));
    Serial.print(RELE_PINO);
    Serial.print(F(":REPOUSO="));
    for (uint8_t i = 0; i < 5; i++) Serial.print(sensores[i].repouso == HIGH ? 'H' : 'L');
    Serial.println();
  } else {
#if USAR_LEDS
    ledComando(c);
#endif
  }
}

void lerSerial() {
  uint8_t n = 0;
  while (Serial.available() && n++ < 32) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (bufLen) {
        buf[bufLen] = '\0';
        executar(buf);
        bufLen = 0;
      }
      continue;
    }
    if (c >= 'a' && c <= 'z') c -= 32;
    if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == ':' || c == '?' || c == '_') {
      if (bufLen < sizeof(buf) - 1) buf[bufLen++] = c;
      else bufLen = 0;  // linha comprida demais: descarta
    }
  }
}

// ============================================================ setup / loop
void setup() {
  // a porta nasce fechada: rele desligado ja antes de virar saida
  releLigado = true;
  releEscrever(false);
  pinMode(RELE_PINO, OUTPUT);
  servoIniciar();
  pinMode(LED_PLACA, OUTPUT);
  for (uint8_t i = 0; i < 5; i++) iniciarEntrada(sensores[i], SENSOR_PINOS[i], FILTRO_SENSOR_MS, REARME_SENSOR_MS, NOMES_SENSOR[i]);
  iniciarEntrada(botoes[0], CONFIG_PINO, FILTRO_BOTAO_MS, 250, "CFG");
  iniciarEntrada(botoes[1], START_PINO, FILTRO_BOTAO_MS, 250, "START");
  iniciarEntrada(botoes[2], FICHA_PINO, FILTRO_FICHA_MS, 40, "FICHA");
  carregarRepouso();
  Serial.begin(9600);
#if USAR_LEDS
  fita.begin();
  fita.setBrightness(BRILHO);
  fita.show();
#endif
  delay(50);
  Serial.println(F("OLA:STRIKE_KIDS:" VERSAO));
}

void loop() {
  unsigned long agora = millis();
  lerSerial();
  bool mudouSensor = false;
  bool disparou;
  for (uint8_t i = 0; i < 5; i++) {
    if (tickEntrada(sensores[i], agora, disparou)) mudouSensor = true;
    if (disparou) {
      Serial.println(sensores[i].evento);
      piscar(agora);
    }
  }
  if (mudouSensor && streamSensores) enviarSensores();
  for (uint8_t i = 0; i < 3; i++) {
    tickEntrada(botoes[i], agora, disparou);
    if (disparou) {
      Serial.println(botoes[i].evento);
      piscar(agora);
    }
  }
  tickServo(agora);
  tickRele(agora);
  if (portaAberta && agora - ultimoComando > SEM_JOGO_FECHA_MS) {
    porta(false);
    Serial.println(F("AVISO:SEM_JOGO"));
  }
  if (piscarAte && (long)(agora - piscarAte) >= 0) {
    piscarAte = 0;
    digitalWrite(LED_PLACA, LOW);
  }
#if USAR_LEDS
  tickLeds(agora);
#endif
}
