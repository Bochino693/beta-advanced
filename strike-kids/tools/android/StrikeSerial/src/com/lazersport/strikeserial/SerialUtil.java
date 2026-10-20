package com.lazersport.strikeserial;

import java.util.ArrayDeque;

/**
 * As contas dos chips USB-serial e a montagem das linhas — sem nada do
 * Android, para poder testar no PC (tools/android/StrikeSerial/teste).
 */
public final class SerialUtil {

	private SerialUtil() {
	}

	/**
	 * CH340/CH341 (Arduino Nano/Uno "clone"): o valor do registrador do
	 * divisor (0x1312), como o driver do Linux (ch341.c) calcula. O bit 7
	 * manda o chip entregar cada byte na hora (sem esperar 32).
	 */
	public static int ch34xDivisor(int baud) {
		final long clk = 48000000L;
		long[] minimo = new long[4];
		for (int ps = 0; ps < 4; ps++) {
			minimo[ps] = clk / (divClk(ps, 1) * 512L);
		}
		int ps = 3;
		while (ps >= 0 && baud <= minimo[ps]) {
			ps--;
		}
		if (ps < 0) {
			throw new IllegalArgumentException("baud muito baixo: " + baud);
		}
		int fact = 1;
		long clkDiv = divClk(ps, fact);
		long div = clk / (clkDiv * baud);
		if (div < 9 || div > 255) {
			div /= 2;
			clkDiv *= 2;
			fact = 0;
		}
		if (div < 2) {
			throw new IllegalArgumentException("baud muito alto: " + baud);
		}
		// o divisor seguinte, se der um baud mais perto do pedido
		if (16 * clk / (clkDiv * div) - 16L * baud >= 16L * baud - 16 * clk / (clkDiv * (div + 1))) {
			div++;
		}
		// base de relógio menor quando o divisor é par (mais tolerante)
		if (fact == 1 && div % 2 == 0) {
			div /= 2;
			fact = 0;
		}
		return (int) (((0x100 - div) << 8) | (fact << 2) | ps) | 0x80;
	}

	private static long divClk(int ps, int fact) {
		return 1L << (12 - 3 * ps - fact);
	}

	private static final int[] FTDI_FRACAO = { 0, 3, 2, 4, 1, 5, 6, 7 };

	/**
	 * FTDI FT232R/FT231X (Arduino Nano original antigo): {valor, índice} do
	 * pedido SET_BAUDRATE. Relógio de 3 MHz, divisor em oitavos.
	 */
	public static int[] ftdiDivisor(int baud) {
		int oitavos = (int) ((24000000L + baud / 2) / baud);
		int inteiro = oitavos >> 3;
		int fracao = FTDI_FRACAO[oitavos & 7];
		int codificado = inteiro | (fracao << 14);
		return new int[] { codificado & 0xFFFF, (codificado >> 16) & 0xFFFF };
	}

	/** CDC (Arduino Uno/Mega/Leonardo originais): SET_LINE_CODING, 8N1. */
	public static byte[] cdcLinha(int baud) {
		return new byte[] { (byte) baud, (byte) (baud >> 8), (byte) (baud >> 16), (byte) (baud >> 24), 0, 0, 8 };
	}

	/**
	 * Junta os bytes que chegam em linhas (terminadas em \n; o \r some).
	 * Linha comprida demais é cortada; a fila guarda as últimas `maximo`.
	 */
	public static final class Linhas {
		private final StringBuilder parcial = new StringBuilder();
		private final ArrayDeque<String> fila = new ArrayDeque<String>();
		private final int maximo;

		public Linhas(int maximo) {
			this.maximo = maximo;
		}

		public synchronized void receber(byte[] dados, int inicio, int n) {
			for (int i = inicio; i < inicio + n; i++) {
				int c = dados[i] & 0xFF;
				if (c == '\n') {
					String l = parcial.toString().trim();
					parcial.setLength(0);
					if (l.length() > 0) {
						if (fila.size() >= maximo) {
							fila.removeFirst();
						}
						fila.addLast(l);
					}
				} else if (c != '\r' && c >= 32 && c < 127) {
					if (parcial.length() < 120) {
						parcial.append((char) c);
					}
				}
			}
		}

		/** Todas as linhas completas, separadas por \n (e esvazia a fila). */
		public synchronized String tirar() {
			if (fila.isEmpty()) {
				return "";
			}
			StringBuilder sb = new StringBuilder();
			while (!fila.isEmpty()) {
				if (sb.length() > 0) {
					sb.append('\n');
				}
				sb.append(fila.removeFirst());
			}
			return sb.toString();
		}

		public synchronized void limpar() {
			fila.clear();
			parcial.setLength(0);
		}
	}

	/**
	 * FTDI: cada pacote USB começa com 2 bytes de estado do chip. Devolve
	 * quantos bytes de dados ficaram (copiados para o começo de `buf`).
	 */
	public static int ftdiTirarEstado(byte[] buf, int n, int pacote) {
		int saida = 0;
		for (int ini = 0; ini < n; ini += pacote) {
			int fim = Math.min(n, ini + pacote);
			for (int i = ini + 2; i < fim; i++) {
				buf[saida++] = buf[i];
			}
		}
		return saida;
	}
}
