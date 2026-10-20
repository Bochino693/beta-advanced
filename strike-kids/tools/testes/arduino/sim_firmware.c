// TESTE DO FIRMWARE DO ARDUINO NUM ATMEGA328P SIMULADO (simavr).
//   tools/testes/arduino/rodar.sh
// Liga o firmware (Uno, 16 MHz, com a fita de LED), aperta os sensores e os
// botões nos pinos, manda comandos pela serial (como o jogo) e confere as
// respostas, o pino do relé (D8) e o pulso do servo no Timer1 (D9).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <simavr/sim_avr.h>
#include <simavr/sim_elf.h>
#include <simavr/avr_uart.h>
#include <simavr/avr_ioport.h>
#include <simavr/sim_irq.h>

static avr_t *avr;
static avr_irq_t *uart_in;
static char parcial[256];
static int nparcial = 0;
static char linhas[512][64];
static double linhas_ms[512];
static int nlinhas = 0, lidas = 0;
static int falhas = 0;

static double agora_ms(void) { return avr->cycle / 16000.0; }

static void uart_saida(struct avr_irq_t *irq, uint32_t valor, void *param) {
	char c = (char)valor;
	if (c == '\n') {
		parcial[nparcial] = 0;
		if (nparcial > 0 && nlinhas < 512) {
			if (getenv("SIM_LINHAS")) printf("      [%8.1f ms] %s\n", agora_ms(), parcial);
			strncpy(linhas[nlinhas], parcial, 63);
			linhas_ms[nlinhas] = agora_ms();
			nlinhas++;
		}
		nparcial = 0;
	} else if (c != '\r' && nparcial < 255) {
		parcial[nparcial++] = c;
	}
}

static void rodar_ms(double ms) {
	uint64_t alvo = avr->cycle + (uint64_t)(ms * 16000.0);
	while (avr->cycle < alvo) {
		int st = avr_run(avr);
		if (st == cpu_Done || st == cpu_Crashed) {
			printf("FALHA a CPU parou (%d)\n", st);
			exit(2);
		}
	}
}

static void checar(int ok, const char *texto) {
	printf("%s %s\n", ok ? "OK   " : "FALHA", texto);
	if (!ok) falhas++;
}

static void enviar(const char *cmd) {
	for (const char *p = cmd; *p; p++) {
		avr_raise_irq(uart_in, (uint8_t)*p);
		rodar_ms(1.1);  // 9600 baud: ~1 ms por byte
	}
	avr_raise_irq(uart_in, '\n');
}

// espera uma linha que começa com `prefixo` (descarta as outras); devolve o ms em que chegou ou -1
static double esperar(const char *prefixo, double limite_ms, char *copia) {
	double fim = agora_ms() + limite_ms;
	for (;;) {
		while (lidas < nlinhas) {
			int i = lidas++;
			if (strncmp(linhas[i], prefixo, strlen(prefixo)) == 0) {
				if (copia) strcpy(copia, linhas[i]);
				return linhas_ms[i];
			}
		}
		if (agora_ms() >= fim) return -1;
		rodar_ms(0.5);
	}
}

// nenhuma linha com `prefixo` nos próximos `ms`
static int nenhuma(const char *prefixo, double ms) {
	double fim = agora_ms() + ms;
	int ok = 1;
	while (agora_ms() < fim) {
		rodar_ms(0.5);
		while (lidas < nlinhas) {
			if (strncmp(linhas[lidas], prefixo, strlen(prefixo)) == 0) ok = 0;
			lidas++;
		}
	}
	return ok;
}

// O sensor/botão de verdade "segura" o nível do pino (vence o pull-up).
// No simavr isso é o "external": sem ele, cada escrita no PORTD (a fita de
// LED escreve o PORTD inteiro) voltaria os pinos de entrada para HIGH.
static uint8_t ext_mask[8], ext_valor[8];

static void pino(char porta, int bit, int nivel) {
	int k = porta - 'A';
	ext_mask[k] |= (uint8_t)(1 << bit);
	if (nivel) ext_valor[k] |= (uint8_t)(1 << bit);
	else ext_valor[k] &= (uint8_t)~(1 << bit);
	avr_ioport_external_t e;
	memset(&e, 0, sizeof(e));
	e.name = porta;
	e.mask = ext_mask[k];
	e.value = ext_valor[k];
	avr_ioctl(avr, AVR_IOCTL_IOPORT_SET_EXTERNAL(porta), &e);
	avr_raise_irq(avr_io_getirq(avr, AVR_IOCTL_IOPORT_GETIRQ(porta), bit), nivel);
}

// um sensor/botão "acionado" puxa o pino para o GND (LOW) por `ms`
static void acionar(char porta, int bit, double ms) {
	pino(porta, bit, 0);
	rodar_ms(ms);
	pino(porta, bit, 1);
}

static unsigned ocr1a(void) { return avr->data[0x88] | (avr->data[0x89] << 8); }
static unsigned icr1(void) { return avr->data[0x86] | (avr->data[0x87] << 8); }
static int rele_nivel(void) { return (avr->data[0x25] & 1) != 0; }    // PORTB0 = D8
static int rele_saida(void) { return (avr->data[0x24] & 1) != 0; }    // DDRB0
static unsigned pulso(int graus) { return (544 + graus * 10 * (2400 - 544) / 1800) * 2; }

int main(int argc, char **argv) {
	elf_firmware_t f;
	memset(&f, 0, sizeof(f));
	if (argc < 2 || elf_read_firmware(argv[1], &f) != 0) {
		printf("uso: sim_firmware firmware.elf\n");
		return 2;
	}
	avr = avr_make_mcu_by_name("atmega328p");
	avr_init(avr);
	avr->frequency = 16000000;
	avr_load_firmware(avr, &f);
	avr->log = 0;
	uint32_t flags = 0;
	avr_ioctl(avr, AVR_IOCTL_UART_GET_FLAGS('0'), &flags);
	flags &= ~AVR_UART_FLAG_STDIO;
	avr_ioctl(avr, AVR_IOCTL_UART_SET_FLAGS('0'), &flags);
	avr_irq_register_notify(avr_io_getirq(avr, AVR_IOCTL_UART_GETIRQ('0'), UART_IRQ_OUTPUT), uart_saida, NULL);
	uart_in = avr_io_getirq(avr, AVR_IOCTL_UART_GETIRQ('0'), UART_IRQ_INPUT);
	// sensores (D2 D3 D4 D5 D7 = PD2..PD5, PD7) e botões (A0 A1 A2 = PC0..PC2) em repouso: HIGH
	int sens_bits[5] = {2, 3, 4, 5, 7};
	for (int i = 0; i < 5; i++) pino('D', sens_bits[i], 1);
	for (int i = 0; i < 3; i++) pino('C', i, 1);

	char l[64];
	// 1. liga
	double t = esperar("OLA:STRIKE_KIDS:1", 1500, NULL);
	checar(t >= 0, "liga e diz OLA:STRIKE_KIDS:1");
	checar(rele_saida() && rele_nivel() == 1, "rele desligado ao ligar (D8 em HIGH: modulo comum liga com LOW)");
	checar(icr1() == 39999 && ocr1a() == pulso(0), "servo: 20 ms, porta FECHADA (544 us)");
	// 2. ping
	enviar("PING");
	checar(esperar("PONG:STRIKE_KIDS:1", 200, NULL) >= 0, "PING -> PONG:STRIKE_KIDS:1");
	// 3. sensor do centro (S3 = D4)
	double t0 = agora_ms();
	pino('D', 4, 0);
	t = esperar("S:3", 50, NULL);
	checar(t >= 0 && t - t0 < 10, "bola no sensor do centro (D4) -> S:3 em menos de 10 ms");
	rodar_ms(40);
	pino('D', 4, 1);
	rodar_ms(30);
	acionar('D', 4, 20);   // a mesma bola balançando
	checar(nenhuma("S:3", 60), "a mesma bola balancando no sensor nao conta 2 vezes");
	rodar_ms(300);
	acionar('D', 4, 30);
	checar(esperar("S:3", 50, NULL) >= 0, "a bola seguinte conta de novo");
	acionar('D', 2, 1);    // ruído de 1 ms no S1
	checar(nenhuma("S:1", 50), "ruido de 1 ms nao vira jogada");
	acionar('D', 7, 15);
	checar(esperar("S:5", 50, NULL) >= 0, "sensor da direita (D7) -> S:5");
	// 4. botões
	acionar('C', 0, 80);
	checar(esperar("CFG", 50, NULL) >= 0, "botao de configuracao (A0) -> CFG");
	acionar('C', 1, 80);
	checar(esperar("START", 50, NULL) >= 0, "botao START (A1) -> START");
	acionar('C', 2, 20);
	rodar_ms(60);
	acionar('C', 2, 20);
	int fichas = 0;
	double fim = agora_ms() + 100;
	while (agora_ms() < fim) {
		rodar_ms(1);
		while (lidas < nlinhas) if (strcmp(linhas[lidas++], "FICHA") == 0) fichas++;
	}
	checar(fichas == 2, "moedeiro: 2 pulsos de 20 ms -> 2 FICHA");
	// 5. porta
	enviar("PORTA:ABRE");
	checar(esperar("PORTA:ABERTA", 50, NULL) >= 0, "PORTA:ABRE -> PORTA:ABERTA");
	checar(rele_nivel() == 0, "rele ligado com a porta aberta (D8 em LOW)");
	rodar_ms(700);
	checar(ocr1a() == pulso(90), "servo foi devagar ate 90 graus (1472 us)");
	enviar("PORTA:FECHA");
	checar(esperar("PORTA:FECHADA", 50, NULL) >= 0, "PORTA:FECHA -> PORTA:FECHADA");
	checar(rele_nivel() == 1, "rele desligado com a porta fechada");
	rodar_ms(150);
	unsigned meio = ocr1a();
	checar(meio < pulso(90) && meio > pulso(0), "o servo fecha devagar (nao bate)");
	rodar_ms(600);
	checar(ocr1a() == pulso(0), "servo voltou a 0 grau");
	enviar("PORTA?");
	checar(esperar("PORTA:FECHADA", 50, NULL) >= 0, "PORTA? -> PORTA:FECHADA");
	// 6. teste dos sensores (estado ao vivo)
	enviar("TESTE:1");
	checar(esperar("SENS:00000", 50, NULL) >= 0, "TESTE:1 -> SENS:00000");
	pino('D', 2, 0);
	checar(esperar("SENS:10000", 30, NULL) >= 0, "S1 coberto -> SENS:10000 (ao vivo)");
	pino('D', 2, 1);
	checar(esperar("SENS:00000", 30, NULL) >= 0, "S1 livre -> SENS:00000");
	enviar("TESTE:0");
	rodar_ms(20);
	acionar('D', 3, 30);
	checar(nenhuma("SENS:", 80), "TESTE:0 -> sem estado ao vivo (so os eventos)");
	// 7. sensor com repouso em LOW (normalmente fechado): calibra
	pino('D', 7, 0);
	rodar_ms(300);
	enviar("CALIBRA");
	checar(esperar("CAL:OK:HHHHL", 400, NULL) >= 0, "CALIBRA com o S5 em LOW -> CAL:OK:HHHHL");
	rodar_ms(300);
	acionar('D', 7, 1);
	pino('D', 7, 1);
	checar(esperar("S:5", 50, NULL) >= 0, "depois de calibrar, o S5 aciona em HIGH");
	pino('D', 7, 0);
	rodar_ms(200);
	enviar("INFO?");
	checar(esperar("INFO:STRIKE_KIDS:1:LEDS=1", 100, l) >= 0 && strstr(l, "REPOUSO=HHHHL"), "INFO? mostra o repouso gravado");
	pino('D', 7, 1);
	rodar_ms(200);
	enviar("CALIBRA");
	checar(esperar("CAL:OK:HHHHH", 400, NULL) >= 0, "calibra de novo (todos em HIGH)");
	// 8. LEDs animando nao atrasam os sensores nem a serial
	enviar("STRIKE");
	rodar_ms(100);
	t0 = agora_ms();
	pino('D', 3, 0);
	t = esperar("S:2", 50, NULL);
	checar(t >= 0 && t - t0 < 10, "com a fita de LED animando, o sensor responde em menos de 10 ms");
	pino('D', 3, 1);
	enviar("PING");
	checar(esperar("PONG", 100, NULL) >= 0, "a serial continua respondendo com a fita animando");
	// 9. o jogo some com a porta aberta: fecha sozinha
	enviar("PORTA:ABRE");
	checar(esperar("PORTA:ABERTA", 50, NULL) >= 0, "abre de novo");
	t0 = agora_ms();
	t = esperar("PORTA:FECHADA", 17000, NULL);
	checar(t >= 0 && t - t0 > 14000 && t - t0 < 16000, "sem noticia do jogo por 15 s a porta fecha sozinha");
	checar(esperar("AVISO:SEM_JOGO", 50, NULL) >= 0, "e avisa AVISO:SEM_JOGO");
	checar(rele_nivel() == 1, "rele desligado");
	printf("FIRMWARE_TESTE %s (%d falha(s)) em %.1f s simulados\n", falhas ? "FALHOU" : "OK", falhas, agora_ms() / 1000.0);
	return falhas ? 1 : 0;
}
