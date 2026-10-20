package com.lazersport.strikecamera;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.ImageFormat;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.hardware.usb.UsbConstants;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.media.Image;
import android.media.ImageReader;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemClock;
import android.util.Log;
import android.util.Size;
import android.view.Surface;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * STRIKE CAMERA — a câmera da máquina (webcam USB, ex.: Sigma) na TV Box.
 *
 * O MESMO MÉTODO DO JOGO DE SOCO (Super Boxing), três caminhos, nesta ordem:
 *   1. CÂMERA DO SISTEMA pela API clássica (android.hardware.Camera): é por
 *      ela que as TV Box publicam a webcam USB (driver uvcvideo do kernel +
 *      HAL antigo, nível LEGACY). A webcam costuma ser a ÚLTIMA da lista.
 *   2. CAMERA2 (preferindo a câmera EXTERNA): TV Box com HAL novo.
 *   3. UVC DIRETA: a webcam aberta direto pelo USB com a libuvc (biblioteca
 *      AndroidUSBCamera, chamada por reflexão: se ela não estiver no APK,
 *      este caminho só avisa e o resto funciona igual). Para TV Box que não
 *      publicam a webcam no Android. Precisa da permissão USB (pedir_usb):
 *      no primeiro encaixe o Android oferece "Usar por padrão" e a
 *      permissão fica guardada (StrikeUsbAtivo).
 * VIGIA: se um caminho "abre" mas não manda imagem em poucos segundos, ele
 * é fechado e o próximo é tentado (webcam de TV Box que abre e fica muda).
 *
 * Cada quadro chega ao jogo como dois planos (Y e UV intercalado, 4:2:0)
 * que viram cor na placa de vídeo (shaders/camera.gdshader, tipo 3).
 *
 * GDScript:  var c = Engine.get_singleton("StrikeCamera")
 *            c.listar(); c.abrir("auto", 640, 480); c.quadros(); c.plano_y();
 *            c.plano_uv(); c.largura(); c.altura(); c.fechar(); c.estado();
 *            c.fonte(); c.pedir_usb(); c.usb_pendente(); c.relatorio();
 *            c.ver(false)  (ligada, mas só contando os quadros: fora da foto)
 * Tudo também vai para o logcat com a etiqueta "StrikeCamera".
 */
public class StrikeCamera extends GodotPlugin {

	private static final String TAG = "StrikeCamera";
	private static final long VIGIA_MS = 4500;          // sem quadro neste tempo: próximo caminho
	private static final long VIGIA_UVC_MS = 8000;      // a UVC direta demora mais para começar
	private static final String ACAO_USB = "com.lazersport.strikecamera.PERMISSAO_USB";
	private static final int FLAG_MUTABLE = 0x02000000; // PendingIntent.FLAG_MUTABLE (Android 12+)

	private final Object trava = new Object();
	private HandlerThread linha;
	private Handler alca;
	private CameraManager gerente;
	private UsbManager usb;
	// caminho 2: Camera2
	private CameraDevice dispositivo;
	private CameraCaptureSession sessao;
	private ImageReader leitor;
	// caminho 1: câmera do sistema (API clássica)
	@SuppressWarnings("deprecation")
	private android.hardware.Camera camera1;
	private SurfaceTexture textura1;
	// caminho 3: UVC direta (libuvc por reflexão)
	private Object uvc;
	private Object uvcMonitor;
	private SurfaceTexture uvcTextura;
	private Surface uvcSuperficie;
	private byte[] uvcBruto;

	private byte[] y = new byte[0];
	private byte[] uv = new byte[0];
	private int w = 0;
	private int h = 0;
	private int contador = 0;
	private volatile int quadrosEtapa = 0;
	/** Alguém está vendo a imagem? Sem ninguém vendo, a câmera continua
	 * ligada mas só conta os quadros (sem copiar nada: não pesa na TV Box). */
	private volatile boolean vendo = true;
	private volatile String estado = "parada";
	private volatile String fonte = "";
	private int pedidoW = 640;
	private int pedidoH = 480;
	private int etapa = -1;
	private volatile int geracao = 0;
	private long pedidoUsbEm = 0;
	private final StringBuilder diario = new StringBuilder();

	public StrikeCamera(Godot godot) {
		super(godot);
	}

	@Override
	public String getPluginName() {
		return "StrikeCamera";
	}

	private void anotar(String s) {
		estado = s;
		try {
			Log.i(TAG, s);
		} catch (Throwable ignored) {
		}
		synchronized (diario) {
			if (diario.length() > 4000) {
				diario.delete(0, diario.length() - 2000);
			}
			diario.append(SystemClock.elapsedRealtime() / 1000).append("s ").append(s).append('\n');
		}
	}

	// ------------------------------------------------------------ consulta
	@UsedByGodot
	public String estado() {
		return estado;
	}

	/** De onde vem a imagem agora: "sistema", "camera2", "uvc" ou "". */
	@UsedByGodot
	public String fonte() {
		return fonte;
	}

	@UsedByGodot
	public boolean tem_permissao() {
		Context c = getActivity();
		if (c == null) {
			return false;
		}
		if (Build.VERSION.SDK_INT < 23) {
			return true;
		}
		return c.checkSelfPermission(android.Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED;
	}

	/**
	 * Uma linha por câmera: "id|lado|api|permissao". api: 1 (sistema),
	 * 2 (Camera2) ou uvc (webcam no USB; permissao 1/0 = USB liberada).
	 */
	@UsedByGodot
	@SuppressWarnings("deprecation")
	public String listar() {
		StringBuilder sb = new StringBuilder();
		try {
			int n = android.hardware.Camera.getNumberOfCameras();
			for (int i = 0; i < n; i++) {
				android.hardware.Camera.CameraInfo info = new android.hardware.Camera.CameraInfo();
				android.hardware.Camera.getCameraInfo(i, info);
				String lado = info.facing == android.hardware.Camera.CameraInfo.CAMERA_FACING_FRONT ? "frente" : "tras";
				// a última costuma ser a webcam USB
				if (n > 1 && i == n - 1) {
					lado = "externa";
				}
				sb.append("c1:").append(i).append('|').append(lado).append("|1|1\n");
			}
		} catch (Throwable e) {
			sb.append("#erro camera1: ").append(e.getMessage()).append('\n');
		}
		CameraManager m = gerente();
		if (m != null) {
			try {
				for (String id : m.getCameraIdList()) {
					sb.append(id).append('|').append(lado2(m, id)).append("|2|1\n");
				}
			} catch (Throwable e) {
				sb.append("#erro camera2: ").append(e.getMessage()).append('\n');
			}
		}
		try {
			// a webcam vista direto no USB só serve com a libuvc no APK: sem
			// ela, nada de pedir permissão USB à toa (vira só um aviso)
			boolean libuvc = temLibuvc();
			for (UsbDevice d : webcamsUsb()) {
				sb.append(libuvc ? "uvc:" : "#sem libuvc: uvc:").append(d.getDeviceId()).append("|externa|uvc|")
						.append(usb().hasPermission(d) ? "1" : "0").append('\n');
			}
		} catch (Throwable e) {
			sb.append("#erro usb: ").append(e.getMessage()).append('\n');
		}
		return sb.toString();
	}

	/**
	 * Liga/desliga a cópia dos quadros. A câmera fica LIGADA o tempo todo
	 * (como no jogo de soco: abrir e fechar a webcam mexe no driver USB);
	 * com ver(false) ela só conta os quadros. ver(true) na hora da prévia e
	 * da foto: o próximo quadro já chega inteiro.
	 */
	@UsedByGodot
	public void ver(boolean sim) {
		vendo = sim;
		if (!sim) {
			synchronized (trava) {
				// nada de quadro velho esperando a próxima foto
				y = new byte[0];
				uv = new byte[0];
			}
		}
	}

	@UsedByGodot
	public int quadros() {
		synchronized (trava) {
			return contador;
		}
	}

	@UsedByGodot
	public int largura() {
		synchronized (trava) {
			return w;
		}
	}

	@UsedByGodot
	public int altura() {
		synchronized (trava) {
			return h;
		}
	}

	@UsedByGodot
	public byte[] plano_y() {
		synchronized (trava) {
			return y;
		}
	}

	@UsedByGodot
	public byte[] plano_uv() {
		synchronized (trava) {
			return uv;
		}
	}

	// ------------------------------------------------------------ USB
	private UsbManager usb() {
		if (usb == null) {
			Activity a = getActivity();
			if (a != null) {
				usb = (UsbManager) a.getSystemService(Context.USB_SERVICE);
			}
		}
		return usb;
	}

	private static boolean ehWebcam(UsbDevice d) {
		if (d.getDeviceClass() == UsbConstants.USB_CLASS_VIDEO) {
			return true;
		}
		for (int i = 0; i < d.getInterfaceCount(); i++) {
			if (d.getInterface(i).getInterfaceClass() == UsbConstants.USB_CLASS_VIDEO) {
				return true;
			}
		}
		return false;
	}

	private List<UsbDevice> webcamsUsb() {
		List<UsbDevice> lista = new ArrayList<UsbDevice>();
		UsbManager u = usb();
		if (u == null) {
			return lista;
		}
		for (UsbDevice d : u.getDeviceList().values()) {
			if (ehWebcam(d)) {
				lista.add(d);
			}
		}
		return lista;
	}

	/** A webcam USB (a que já tem permissão primeiro). */
	private UsbDevice webcamUsb() {
		UsbDevice primeira = null;
		for (UsbDevice d : webcamsUsb()) {
			if (usb().hasPermission(d)) {
				return d;
			}
			if (primeira == null) {
				primeira = d;
			}
		}
		return primeira;
	}

	/** Há webcam no USB ainda sem permissão? (o jogo pede na hora certa) */
	@UsedByGodot
	public boolean usb_pendente() {
		try {
			if (!temLibuvc()) {
				return false;
			}
			UsbDevice d = webcamUsb();
			return d != null && !usb().hasPermission(d);
		} catch (Throwable e) {
			return false;
		}
	}

	/**
	 * Pede ao Android a permissão da webcam USB (janela "Permitir que o
	 * Strike Kids acesse..." — marque "Usar por padrão"). Só para a UVC
	 * direta; a câmera do sistema não precisa disto.
	 */
	@UsedByGodot
	public String pedir_usb() {
		final Activity a = getActivity();
		if (a == null) {
			return "tela ainda nao disponivel";
		}
		try {
			if (!temLibuvc()) {
				return "sem libuvc neste apk: a permissao usb nao serviria";
			}
			UsbDevice d = webcamUsb();
			if (d == null) {
				return "nenhuma webcam no usb";
			}
			if (usb().hasPermission(d)) {
				return "ok";
			}
			long agora = SystemClock.elapsedRealtime();
			if (agora - pedidoUsbEm < 15000) {
				return "aguardando permissao usb";
			}
			pedidoUsbEm = agora;
			Intent it = new Intent(ACAO_USB);
			it.setPackage(a.getPackageName());
			int flags = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 31 ? FLAG_MUTABLE : 0);
			PendingIntent pi = PendingIntent.getBroadcast(a, 7300 + d.getDeviceId(), it, flags);
			usb().requestPermission(d, pi);
			anotar("pedindo permissao da webcam usb");
			return "pedido";
		} catch (Throwable e) {
			return "erro: " + e.getMessage();
		}
	}

	// ------------------------------------------------------------ ligar
	/**
	 * Abre a câmera. id: "auto" (sistema > Camera2 > UVC direta, com vigia),
	 * "c1:N" (sistema), um id da Camera2 ou "uvc". Volta logo; o resultado
	 * aparece em estado()/fonte() e quadros() começa a subir.
	 */
	@UsedByGodot
	public boolean abrir(final String id, int largura, int altura) {
		fechar();
		if (!tem_permissao()) {
			anotar("sem permissao da camera");
			return false;
		}
		pedidoW = largura > 0 ? largura : 640;
		pedidoH = altura > 0 ? altura : 480;
		// nada da sessão anterior: a foto nunca sai com um quadro velho
		synchronized (trava) {
			y = new byte[0];
			uv = new byte[0];
			w = 0;
			h = 0;
			contador = 0;
		}
		linha = new HandlerThread("StrikeCamera");
		linha.start();
		alca = new Handler(linha.getLooper());
		final int g = geracao;
		anotar("ligando (" + id + ")");
		alca.post(new Runnable() {
			@Override
			public void run() {
				if (g != geracao) {
					return;
				}
				if ("auto".equals(id)) {
					etapa = -1;
					proxima(g);
				} else if (id.startsWith("c1:")) {
					abrirSistema(Integer.parseInt(id.substring(3)), g);
				} else if (id.startsWith("uvc")) {
					UsbDevice d = webcamUsb();
					if (d != null) {
						abrirUvc(d, g);
					}
				} else {
					abrirCamera2(id, g);
				}
			}
		});
		return true;
	}

	/** Próximo caminho da sequência automática. */
	@SuppressWarnings("deprecation")
	private void proxima(int g) {
		if (g != geracao) {
			return;
		}
		fecharDispositivos();
		etapa++;
		quadrosEtapa = 0;
		if (etapa == 0) {
			int n = 0;
			try {
				n = android.hardware.Camera.getNumberOfCameras();
			} catch (Throwable ignored) {
			}
			if (n > 0 && abrirSistema(-1, g)) {
				vigiar(g, VIGIA_MS);
				return;
			}
			proxima(g);
		} else if (etapa == 1) {
			String id2 = escolher2();
			if (id2 != null) {
				abrirCamera2(id2, g);
				vigiar(g, VIGIA_MS);
				return;
			}
			proxima(g);
		} else if (etapa == 2) {
			UsbDevice d = webcamUsb();
			if (d == null) {
				anotar("sem imagem: nenhuma camera respondeu e nao ha webcam no usb");
				return;
			}
			if (!usb().hasPermission(d)) {
				anotar("webcam usb sem permissao (pedir_usb)");
				return;
			}
			if (abrirUvc(d, g)) {
				vigiar(g, VIGIA_UVC_MS);
			}
		} else {
			anotar("sem imagem: nenhum caminho mandou quadros");
		}
	}

	/** Se este caminho não mandar quadros a tempo, tenta o próximo. */
	private void vigiar(final int g, long ms) {
		if (alca == null) {
			return;
		}
		alca.postDelayed(new Runnable() {
			@Override
			public void run() {
				if (g != geracao || quadrosEtapa > 0) {
					return;
				}
				anotar("caminho " + fonte + " abriu mas nao mandou imagem: tentando o proximo");
				proxima(g);
			}
		}, ms);
	}

	@UsedByGodot
	public void fechar() {
		geracao++;
		fecharDispositivos();
		if (linha != null) {
			linha.quitSafely();
			linha = null;
			alca = null;
		}
		fonte = "";
		estado = "parada";
	}

	@SuppressWarnings("deprecation")
	private void fecharDispositivos() {
		try {
			if (sessao != null) {
				sessao.close();
			}
		} catch (Throwable ignored) {
		}
		sessao = null;
		try {
			if (dispositivo != null) {
				dispositivo.close();
			}
		} catch (Throwable ignored) {
		}
		dispositivo = null;
		try {
			if (leitor != null) {
				leitor.close();
			}
		} catch (Throwable ignored) {
		}
		leitor = null;
		try {
			if (camera1 != null) {
				camera1.setPreviewCallbackWithBuffer(null);
				camera1.stopPreview();
				camera1.release();
			}
		} catch (Throwable ignored) {
		}
		camera1 = null;
		try {
			if (textura1 != null) {
				textura1.release();
			}
		} catch (Throwable ignored) {
		}
		textura1 = null;
		fecharUvc();
	}

	@Override
	public void onMainPause() {
		// a TV Box saiu do jogo: solta a câmera para outros apps
		fechar();
	}

	@Override
	public void onMainDestroy() {
		fechar();
	}

	// ------------------------------------------------- 1. câmera do sistema
	/** indice -1: da última para a primeira (a webcam USB costuma ser a última). */
	@SuppressWarnings("deprecation")
	private boolean abrirSistema(int indice, int g) {
		if (g != geracao) {
			return false;
		}
		android.hardware.Camera cam = null;
		String erro = "";
		try {
			int n = android.hardware.Camera.getNumberOfCameras();
			if (indice >= 0) {
				cam = android.hardware.Camera.open(indice);
			} else {
				for (int i = n - 1; i >= 0 && cam == null; i--) {
					try {
						cam = android.hardware.Camera.open(i);
					} catch (Throwable t) {
						erro = t.getMessage();
					}
				}
			}
		} catch (Throwable t) {
			erro = t.getMessage();
		}
		if (cam == null) {
			anotar("camera do sistema nao abriu: " + erro);
			return false;
		}
		try {
			android.hardware.Camera.Parameters prm = cam.getParameters();
			android.hardware.Camera.Size melhor = null;
			long nota = Long.MAX_VALUE;
			List<android.hardware.Camera.Size> tams = prm.getSupportedPreviewSizes();
			if (tams != null) {
				for (android.hardware.Camera.Size s : tams) {
					long nn = Math.abs((long) s.width * s.height - (long) pedidoW * pedidoH);
					if (nn < nota) {
						nota = nn;
						melhor = s;
					}
				}
			}
			if (melhor != null) {
				prm.setPreviewSize(melhor.width, melhor.height);
			}
			prm.setPreviewFormat(ImageFormat.NV21);
			try {
				cam.setParameters(prm);
			} catch (Throwable ignored) {
				// alguns drivers recusam: segue com o que a câmera já usa
			}
			final android.hardware.Camera.Size usado = cam.getParameters().getPreviewSize();
			final int W = usado.width;
			final int H = usado.height;
			textura1 = new SurfaceTexture(10);
			cam.setPreviewTexture(textura1);
			int bytes = W * H * 3 / 2;
			cam.addCallbackBuffer(new byte[bytes]);
			cam.addCallbackBuffer(new byte[bytes]);
			cam.setPreviewCallbackWithBuffer(new android.hardware.Camera.PreviewCallback() {
				@Override
				public void onPreviewFrame(byte[] dados, android.hardware.Camera c) {
					guardarNv21(dados, W, H);
					try {
						c.addCallbackBuffer(dados);
					} catch (Throwable ignored) {
					}
				}
			});
			cam.setErrorCallback(new android.hardware.Camera.ErrorCallback() {
				@Override
				public void onError(int erro, android.hardware.Camera c) {
					anotar("camera do sistema caiu (erro " + erro + ")");
				}
			});
			cam.startPreview();
			camera1 = cam;
			fonte = "sistema";
			anotar("camera do sistema aberta " + W + "x" + H);
			return true;
		} catch (Throwable t) {
			anotar("camera do sistema falhou: " + t.getMessage());
			try {
				cam.release();
			} catch (Throwable ignored) {
			}
			return false;
		}
	}

	// ------------------------------------------------------------ 2. Camera2
	private CameraManager gerente() {
		if (gerente == null) {
			Activity a = getActivity();
			if (a != null) {
				gerente = (CameraManager) a.getSystemService(Context.CAMERA_SERVICE);
			}
		}
		return gerente;
	}

	private static String lado2(CameraManager m, String id) {
		try {
			Integer f = m.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING);
			if (f == null) {
				return "externa";
			}
			if (f == CameraCharacteristics.LENS_FACING_FRONT) {
				return "frente";
			}
			if (f == CameraCharacteristics.LENS_FACING_BACK) {
				return "tras";
			}
			return "externa";
		} catch (Throwable e) {
			return "externa";
		}
	}

	/** A webcam USB (externa) primeiro; senão a primeira que houver. */
	private String escolher2() {
		CameraManager m = gerente();
		if (m == null) {
			return null;
		}
		try {
			String[] ids = m.getCameraIdList();
			for (String id : ids) {
				if ("externa".equals(lado2(m, id))) {
					return id;
				}
			}
			return ids.length > 0 ? ids[ids.length - 1] : null;
		} catch (Throwable e) {
			return null;
		}
	}

	private Size tamanho2(String id) {
		try {
			StreamConfigurationMap mapa = gerente().getCameraCharacteristics(id)
					.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
			Size[] tams = mapa != null ? mapa.getOutputSizes(ImageFormat.YUV_420_888) : null;
			if (tams == null || tams.length == 0) {
				return new Size(pedidoW, pedidoH);
			}
			Size melhor = tams[0];
			long nota = Long.MAX_VALUE;
			for (Size s : tams) {
				long n = Math.abs((long) s.getWidth() * s.getHeight() - (long) pedidoW * pedidoH);
				if (n < nota) {
					nota = n;
					melhor = s;
				}
			}
			return melhor;
		} catch (Throwable e) {
			return new Size(pedidoW, pedidoH);
		}
	}

	@SuppressWarnings("MissingPermission")
	private void abrirCamera2(final String id, final int g) {
		CameraManager m = gerente();
		if (m == null) {
			proxima(g);
			return;
		}
		final Size tam = tamanho2(id);
		fonte = "camera2";
		try {
			m.openCamera(id, new CameraDevice.StateCallback() {
				@Override
				public void onOpened(CameraDevice d) {
					if (g != geracao) {
						d.close();
						return;
					}
					dispositivo = d;
					iniciarSessao(d, tam, g);
				}

				@Override
				public void onDisconnected(CameraDevice d) {
					d.close();
					if (dispositivo == d) {
						dispositivo = null;
					}
					anotar("camera2 desconectada");
				}

				@Override
				public void onError(CameraDevice d, int erro) {
					d.close();
					if (dispositivo == d) {
						dispositivo = null;
					}
					anotar("erro camera2 " + erro);
					proxima(g);
				}
			}, alca);
		} catch (Throwable e) {
			anotar("erro camera2: " + e.getMessage());
			proxima(g);
		}
	}

	private void iniciarSessao(final CameraDevice d, Size tam, final int g) {
		try {
			leitor = ImageReader.newInstance(tam.getWidth(), tam.getHeight(), ImageFormat.YUV_420_888, 3);
			leitor.setOnImageAvailableListener(new ImageReader.OnImageAvailableListener() {
				@Override
				public void onImageAvailable(ImageReader r) {
					Image img = null;
					try {
						img = r.acquireLatestImage();
						if (img != null) {
							guardarYuv(img);
						}
					} catch (Throwable ignored) {
					} finally {
						if (img != null) {
							img.close();
						}
					}
				}
			}, alca);
			List<Surface> alvos = new ArrayList<Surface>(Arrays.asList(leitor.getSurface()));
			d.createCaptureSession(alvos, new CameraCaptureSession.StateCallback() {
				@Override
				public void onConfigured(CameraCaptureSession s) {
					if (g != geracao) {
						s.close();
						return;
					}
					sessao = s;
					try {
						CaptureRequest.Builder b = d.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
						b.addTarget(leitor.getSurface());
						s.setRepeatingRequest(b.build(), null, alca);
						anotar("camera2 aberta");
					} catch (CameraAccessException e) {
						anotar("erro pedido camera2: " + e.getMessage());
						proxima(g);
					} catch (Throwable e) {
						anotar("erro pedido camera2: " + e.getMessage());
						proxima(g);
					}
				}

				@Override
				public void onConfigureFailed(CameraCaptureSession s) {
					anotar("erro sessao camera2");
					proxima(g);
				}
			}, alca);
		} catch (Throwable e) {
			anotar("erro sessao camera2: " + e.getMessage());
			proxima(g);
		}
	}

	/** Copia Y e monta o UV intercalado (U, V) respeitando o passo de cada plano. */
	private void guardarYuv(Image img) {
		int W = img.getWidth();
		int H = img.getHeight();
		if (!vendo) {
			contar(W, H);
			return;
		}
		Image.Plane[] p = img.getPlanes();
		ByteBuffer by = p[0].getBuffer();
		int rsY = p[0].getRowStride();
		byte[] nY = new byte[W * H];
		for (int r = 0; r < H; r++) {
			by.position(r * rsY);
			by.get(nY, r * W, Math.min(W, by.remaining()));
		}
		ByteBuffer bu = p[1].getBuffer();
		ByteBuffer bv = p[2].getBuffer();
		int rsU = p[1].getRowStride();
		int psU = p[1].getPixelStride();
		int rsV = p[2].getRowStride();
		int psV = p[2].getPixelStride();
		int W2 = W / 2;
		int H2 = H / 2;
		byte[] nUV = new byte[W2 * H2 * 2];
		int limU = bu.limit();
		int limV = bv.limit();
		for (int r = 0; r < H2; r++) {
			int bU = r * rsU;
			int bV = r * rsV;
			int o = r * W2 * 2;
			for (int c = 0; c < W2; c++) {
				int iu = bU + c * psU;
				int iv = bV + c * psV;
				nUV[o + c * 2] = iu < limU ? bu.get(iu) : (byte) 128;
				nUV[o + c * 2 + 1] = iv < limV ? bv.get(iv) : (byte) 128;
			}
		}
		entregar(nY, nUV, W, H);
	}

	// --------------------------------------------------- 3. UVC direta
	/** A libuvc (AndroidUSBCamera) está dentro deste APK? */
	private static boolean temLibuvc() {
		try {
			Class.forName("com.serenegiant.usb.UVCCamera");
			return true;
		} catch (Throwable e) {
			return false;
		}
	}

	/**
	 * Abre a webcam direto pelo USB com a libuvc, SEM registrar o USBMonitor
	 * (o registro dele quebra no Android 12+): a permissão USB é deste
	 * plugin, e a libuvc é chamada por reflexão.
	 */
	private boolean abrirUvc(UsbDevice device, final int g) {
		if (g != geracao) {
			return false;
		}
		if (!temLibuvc()) {
			anotar("uvc direta indisponivel neste apk (libuvc ausente)");
			return false;
		}
		Activity host = getActivity();
		if (host == null) {
			return false;
		}
		fonte = "uvc";
		try {
			Class<?> cUvc = Class.forName("com.serenegiant.usb.UVCCamera");
			Class<?> cMonitor = Class.forName("com.serenegiant.usb.USBMonitor");
			Class<?> cOuvinte = Class.forName("com.serenegiant.usb.USBMonitor$OnDeviceConnectListener");
			Class<?> cBloco = Class.forName("com.serenegiant.usb.USBMonitor$UsbControlBlock");
			Object ouvinte = Proxy.newProxyInstance(cOuvinte.getClassLoader(), new Class<?>[] { cOuvinte },
					new InvocationHandler() {
						@Override
						public Object invoke(Object proxy, Method metodo, Object[] args) {
							return null;
						}
					});
			Object monitor = cMonitor.getConstructor(Context.class, cOuvinte).newInstance(host.getApplicationContext(), ouvinte);
			uvcMonitor = monitor;
			Constructor<?> ctorBloco = cBloco.getDeclaredConstructor(cMonitor, UsbDevice.class);
			ctorBloco.setAccessible(true);
			Object bloco = ctorBloco.newInstance(monitor, device);
			Object camera = cUvc.getDeclaredConstructor().newInstance();
			cUvc.getMethod("open", cBloco).invoke(camera, bloco);
			uvc = camera;
			Method setSize = cUvc.getMethod("setPreviewSize", int.class, int.class, int.class);
			int mjpeg = campo(cUvc, "FRAME_FORMAT_MJPEG", 1);
			int yuyv = campo(cUvc, "FRAME_FORMAT_YUYV", 0);
			int[][] tentativas = { { 640, 480, mjpeg }, { 640, 480, yuyv }, { 1280, 720, mjpeg }, { 320, 240, yuyv } };
			int largura = 0;
			int altura = 0;
			String ultimo = "";
			for (int[] t : tentativas) {
				try {
					setSize.invoke(camera, t[0], t[1], t[2]);
					largura = t[0];
					altura = t[1];
					break;
				} catch (Throwable e) {
					Throwable c = e instanceof InvocationTargetException ? ((InvocationTargetException) e).getTargetException() : e;
					ultimo = String.valueOf(c.getMessage());
				}
			}
			if (largura == 0) {
				throw new IllegalStateException("a webcam recusou os tamanhos: " + ultimo);
			}
			// superfície "de mentira" para o pipeline nativo andar
			uvcTextura = new SurfaceTexture(43);
			uvcTextura.setDefaultBufferSize(largura, altura);
			uvcSuperficie = new Surface(uvcTextura);
			try {
				cUvc.getMethod("setPreviewDisplay", Surface.class).invoke(camera, uvcSuperficie);
			} catch (NoSuchMethodException e) {
				cUvc.getMethod("setPreviewTexture", SurfaceTexture.class).invoke(camera, uvcTextura);
			}
			Class<?> cQuadro = Class.forName("com.serenegiant.usb.IFrameCallback");
			int nv21 = campo(cUvc, "PIXEL_FORMAT_NV21", 5);
			final int W = largura;
			final int H = altura;
			Object retorno = Proxy.newProxyInstance(cQuadro.getClassLoader(), new Class<?>[] { cQuadro },
					new InvocationHandler() {
						@Override
						public Object invoke(Object proxy, Method metodo, Object[] args) {
							if ("onFrame".equals(metodo.getName()) && args != null && args.length > 0 && args[0] instanceof ByteBuffer) {
								ByteBuffer buf = (ByteBuffer) args[0];
								int precisa = W * H * 3 / 2;
								if (!vendo) {
									contar(W, H);
								} else if (buf.remaining() >= precisa) {
									if (uvcBruto == null || uvcBruto.length != precisa) {
										uvcBruto = new byte[precisa];
									}
									buf.get(uvcBruto, 0, precisa);
									guardarNv21(uvcBruto, W, H);
								}
							}
							return null;
						}
					});
			cUvc.getMethod("setFrameCallback", cQuadro, int.class).invoke(camera, retorno, nv21);
			cUvc.getMethod("startPreview").invoke(camera);
			anotar("webcam usb aberta direto (uvc " + W + "x" + H + ")");
			return true;
		} catch (Throwable t) {
			Throwable c = t instanceof InvocationTargetException ? ((InvocationTargetException) t).getTargetException() : t;
			anotar("uvc direta falhou: " + c.getClass().getSimpleName() + " " + c.getMessage());
			fecharUvc();
			return false;
		}
	}

	private static int campo(Class<?> c, String nome, int padrao) {
		try {
			return c.getField(nome).getInt(null);
		} catch (Throwable e) {
			return padrao;
		}
	}

	private void fecharUvc() {
		Object camera = uvc;
		uvc = null;
		if (camera != null) {
			try {
				camera.getClass().getMethod("stopPreview").invoke(camera);
			} catch (Throwable ignored) {
			}
			try {
				camera.getClass().getMethod("destroy").invoke(camera);
			} catch (Throwable ignored) {
			}
		}
		uvcMonitor = null;
		try {
			if (uvcSuperficie != null) {
				uvcSuperficie.release();
			}
		} catch (Throwable ignored) {
		}
		try {
			if (uvcTextura != null) {
				uvcTextura.release();
			}
		} catch (Throwable ignored) {
		}
		uvcSuperficie = null;
		uvcTextura = null;
	}

	// ------------------------------------------------------------ quadros
	/** NV21: Y inteiro e depois V,U intercalados — vira Y + (U,V). */
	private void guardarNv21(byte[] d, int W, int H) {
		if (d == null || d.length < W * H * 3 / 2) {
			return;
		}
		if (!vendo) {
			contar(W, H);
			return;
		}
		byte[] nY = new byte[W * H];
		System.arraycopy(d, 0, nY, 0, W * H);
		int n = (W / 2) * (H / 2);
		byte[] nUV = new byte[n * 2];
		int base = W * H;
		for (int i = 0; i < n; i++) {
			nUV[i * 2] = d[base + i * 2 + 1];
			nUV[i * 2 + 1] = d[base + i * 2];
		}
		entregar(nY, nUV, W, H);
	}

	private void entregar(byte[] nY, byte[] nUV, int W, int H) {
		synchronized (trava) {
			y = nY;
			uv = nUV;
			w = W;
			h = H;
			contador++;
		}
		chegou(W, H);
	}

	/** Ninguém vendo: só conta o quadro (a câmera segue viva). */
	private void contar(int W, int H) {
		synchronized (trava) {
			w = W;
			h = H;
			contador++;
		}
		chegou(W, H);
	}

	private void chegou(int W, int H) {
		if (quadrosEtapa == 0) {
			quadrosEtapa = 1;
			anotar("imagem chegando (" + fonte + " " + W + "x" + H + ")");
		}
	}

	// ------------------------------------------------------------ relatório
	/**
	 * O que o Android enxerga, uma linha por fato: câmeras do sistema, da
	 * Camera2 (com o nível), aparelhos USB (classe e permissão), se a libuvc
	 * está no APK e o que esta ponte tentou. Aparece no menu do operador.
	 */
	@UsedByGodot
	@SuppressWarnings("deprecation")
	public String relatorio() {
		StringBuilder sb = new StringBuilder();
		sb.append("Android ").append(Build.VERSION.RELEASE).append(" (API ").append(Build.VERSION.SDK_INT).append(") ")
				.append(Build.MANUFACTURER).append(' ').append(Build.MODEL).append('\n');
		sb.append("permissao da camera: ").append(tem_permissao() ? "SIM" : "NAO").append('\n');
		try {
			sb.append("cameras do sistema (API classica): ").append(android.hardware.Camera.getNumberOfCameras()).append('\n');
		} catch (Throwable e) {
			sb.append("cameras do sistema: erro ").append(e.getMessage()).append('\n');
		}
		CameraManager m = gerente();
		if (m != null) {
			try {
				String[] ids = m.getCameraIdList();
				sb.append("camera2: ").append(ids.length).append('\n');
				for (String id : ids) {
					Integer nivel = m.getCameraCharacteristics(id).get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL);
					sb.append("  ").append(id).append(" ").append(lado2(m, id)).append(" nivel ").append(nivel).append('\n');
				}
			} catch (Throwable e) {
				sb.append("camera2: erro ").append(e.getMessage()).append('\n');
			}
		}
		try {
			UsbManager u = usb();
			if (u != null) {
				sb.append("usb: ").append(u.getDeviceList().size()).append(" aparelho(s)\n");
				for (UsbDevice d : u.getDeviceList().values()) {
					sb.append("  ").append(String.format("%04x:%04x", d.getVendorId(), d.getProductId()))
							.append(" classe ").append(d.getDeviceClass())
							.append(ehWebcam(d) ? " WEBCAM" : "")
							.append(u.hasPermission(d) ? " permitido" : " sem-permissao").append('\n');
				}
			}
		} catch (Throwable e) {
			sb.append("usb: erro ").append(e.getMessage()).append('\n');
		}
		sb.append("libuvc no apk: ").append(temLibuvc() ? "SIM" : "NAO").append('\n');
		sb.append("agora: ").append(estado).append(" | fonte: ").append(fonte.isEmpty() ? "-" : fonte)
				.append(" | quadros: ").append(quadros()).append('\n');
		synchronized (diario) {
			sb.append(diario);
		}
		return sb.toString();
	}
}
