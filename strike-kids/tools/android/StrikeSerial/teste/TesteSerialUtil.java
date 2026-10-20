import com.lazersport.strikeserial.SerialUtil;

/**
 * Confere as contas dos chips e a montagem das linhas (roda no PC):
 *   sh tools/android/StrikeSerial/teste/rodar.sh
 * Valores esperados conferidos com o driver ch341.c do Linux e com a
 * libftdi (9600 = 0x4138 no FTDI).
 */
public class TesteSerialUtil {
	static int falhas = 0;

	static void checar(boolean ok, String texto) {
		System.out.println((ok ? "OK    " : "FALHA ") + texto);
		if (!ok) {
			falhas++;
		}
	}

	public static void main(String[] a) {
		checar(SerialUtil.ch34xDivisor(9600) == 0xB282, String.format("CH340 9600 = 0x%04X (0xB282)", SerialUtil.ch34xDivisor(9600)));
		checar(SerialUtil.ch34xDivisor(57600) == 0x9883, String.format("CH340 57600 = 0x%04X (0x9883)", SerialUtil.ch34xDivisor(57600)));
		checar(SerialUtil.ch34xDivisor(115200) == 0xCC83, String.format("CH340 115200 = 0x%04X (0xCC83)", SerialUtil.ch34xDivisor(115200)));
		int[] f = SerialUtil.ftdiDivisor(9600);
		checar(f[0] == 0x4138 && f[1] == 0, String.format("FTDI 9600 = 0x%04X/%d (0x4138/0)", f[0], f[1]));
		f = SerialUtil.ftdiDivisor(57600);
		checar(f[0] == 0xC034 && f[1] == 0, String.format("FTDI 57600 = 0x%04X/%d (0xC034/0)", f[0], f[1]));
		f = SerialUtil.ftdiDivisor(115200);
		checar(f[0] == 0x001A && f[1] == 0, String.format("FTDI 115200 = 0x%04X/%d (0x001A/0)", f[0], f[1]));
		byte[] l = SerialUtil.cdcLinha(9600);
		checar(l.length == 7 && (l[0] & 0xFF) == 0x80 && (l[1] & 0xFF) == 0x25 && l[6] == 8, "CDC 9600 8N1 = 80 25 00 00 00 00 08");
		SerialUtil.Linhas li = new SerialUtil.Linhas(200);
		byte[] b = "\u0000ÿOLA:STRIKE_KIDS:1\r\nS:".getBytes(java.nio.charset.StandardCharsets.ISO_8859_1);
		li.receber(b, 0, b.length);
		String um = li.tirar();
		checar(um.equals("OLA:STRIKE_KIDS:1"), "linha com lixo do boot e \\r: '" + um + "'");
		b = "3\nCFG\n\nSENS:00100\n".getBytes(java.nio.charset.StandardCharsets.US_ASCII);
		li.receber(b, 0, b.length);
		String dois = li.tirar();
		checar(dois.equals("S:3\nCFG\nSENS:00100"), "linha partida em dois pedacos: '" + dois.replace("\n", "|") + "'");
		checar(li.tirar().equals(""), "fila vazia depois de tirar");
		SerialUtil.Linhas cheia = new SerialUtil.Linhas(3);
		b = "A\nB\nC\nD\nE\n".getBytes(java.nio.charset.StandardCharsets.US_ASCII);
		cheia.receber(b, 0, b.length);
		checar(cheia.tirar().equals("C\nD\nE"), "fila cheia guarda as ultimas");
		byte[] ft = new byte[130];
		for (int i = 0; i < 130; i++) ft[i] = (byte) ('a' + (i % 26));
		ft[0] = 1; ft[1] = 0x60; ft[64] = 1; ft[65] = 0x60; ft[128] = 1; ft[129] = 0x60;
		int n = SerialUtil.ftdiTirarEstado(ft, 130, 64);
		checar(n == 124 && ft[0] == (byte) ('a' + 2) && ft[62] == (byte) ('a' + (66 % 26)), "FTDI tira 2 bytes de estado por pacote (" + n + " de 130)");
		System.out.println("TESTE_SERIAL " + (falhas == 0 ? "OK" : "FALHOU") + " (" + falhas + " falha(s))");
		System.exit(falhas == 0 ? 0 : 1);
	}
}
