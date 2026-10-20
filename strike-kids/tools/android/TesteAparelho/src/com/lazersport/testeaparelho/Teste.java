package com.lazersport.testeaparelho;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Context;
import android.content.pm.ConfigurationInfo;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.opengl.GLES20;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.StatFs;
import android.util.DisplayMetrics;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.OutputStreamWriter;
import java.lang.reflect.Method;
import java.util.Locale;

import javax.microedition.khronos.egl.EGL10;
import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.egl.EGLContext;
import javax.microedition.khronos.egl.EGLDisplay;
import javax.microedition.khronos.egl.EGLSurface;

/**
 * STRIKE KIDS - TESTE DO APARELHO
 *
 * Mostra (e grava em aparelho.txt) o que importa para o jogo rodar numa TV
 * Box: chip, placa de vídeo, versão do OpenGL ES (o jogo normal precisa do
 * 3.0), Android, 32/64 bits, memória de verdade, USB e câmeras. Não precisa
 * de internet nem de permissão; abre em qualquer Android 4.1 ou mais novo.
 */
public class Teste extends Activity {

    private final StringBuilder rel = new StringBuilder();
    private ScrollView rolar;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        String[] gl2 = lerGl(2);
        String[] gl3 = lerGl(3);
        int req = 0;
        try {
            ActivityManager am = (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
            ConfigurationInfo ci = am.getDeviceConfigurationInfo();
            req = ci.reqGlEsVersion;
        } catch (Throwable t) { /* sem */ }
        boolean temGl3 = gl3 != null || req >= 0x30000;
        String placa = gl3 != null ? gl3[1] : (gl2 != null ? gl2[1] : "?");
        String versaoGl = gl3 != null ? gl3[2] : (gl2 != null ? gl2[2] : "?");
        long ram = ramTotal();
        int sdk = Build.VERSION.SDK_INT;
        String abis = abis();
        boolean bits64 = abis.contains("arm64") || abis.contains("x86_64");

        // ------------------------------------------------ veredito
        String veredito;
        int corVeredito;
        if (!temGl3) {
            veredito = "NAO RODA o Strike Kids normal (LEVE / ALTA)\n"
                    + "Esta placa de video (" + placa + ") so tem OpenGL ES 2.0.\n"
                    + "O jogo precisa de OpenGL ES 3.0. Use outra TV Box\n"
                    + "(chip H313/H616/H618, S905W2/X2/X3/X4, RK3566...)\n"
                    + "ou a EDICAO TX9 (OpenGL ES 2.0).";
            corVeredito = Color.rgb(200, 40, 50);
        } else if (sdk < 24) {
            veredito = "NAO RODA: o Android desta TV Box e antigo demais\n"
                    + "(Android " + Build.VERSION.RELEASE + "). O jogo precisa do Android 7.0 ou mais novo.\n"
                    + "A placa de video tem OpenGL ES 3 (" + placa + ").";
            corVeredito = Color.rgb(200, 90, 30);
        } else {
            boolean forte = forte(placa);
            veredito = "RODA o Strike Kids!  (" + placa + ", OpenGL ES 3)\n"
                    + (forte ? "Placa forte: a versao ALTA roda com folga."
                             : "Use a versao LEVE (a ALTA tambem abre; o jogo ajusta a nitidez sozinho).")
                    + (ram > 0 && ram < 1500L * 1024 * 1024 ? "\nAtencao: pouca memoria (" + mb(ram) + ")." : "");
            corVeredito = Color.rgb(30, 150, 70);
        }

        // ------------------------------------------------ relatório
        add("STRIKE KIDS - TESTE DO APARELHO");
        add("");
        add("VEREDITO:");
        add(veredito);
        add("");
        add("PLACA DE VIDEO:  " + placa);
        add("  fabricante:    " + (gl2 != null ? gl2[0] : (gl3 != null ? gl3[0] : "?")));
        add("  OpenGL ES:     " + versaoGl);
        add("  pedido pelo Android: " + glReq(req) + (gl3 != null ? "   (contexto ES 3 criado: SIM)" : "   (contexto ES 3: NAO)"));
        add("  GLSL:          " + (gl3 != null ? gl3[3] : (gl2 != null ? gl2[3] : "?")));
        add("  Vulkan:        " + (temRecurso("android.hardware.vulkan.version") ? "sim" : "nao"));
        add("");
        add("CHIP:            " + chip());
        add("  plataforma:    " + prop("ro.board.platform") + "   hardware: " + Build.HARDWARE + "   placa: " + Build.BOARD);
        add("  nucleos:       " + Runtime.getRuntime().availableProcessors() + "   " + cpuInfo());
        add("  32/64 bits:    " + abis + (bits64 ? "   (Android 64 bits)" : "   (Android 32 bits)"));
        add("");
        add("ANDROID:         " + Build.VERSION.RELEASE + "  (API " + sdk + ")");
        add("APARELHO:        " + Build.MANUFACTURER + " / " + Build.BRAND + " / " + Build.MODEL + "  (" + Build.DEVICE + ", " + Build.PRODUCT + ")");
        add("MEMORIA (de verdade): " + mb(ram) + "   armazenamento: " + armazenamento());
        add("TELA:            " + tela());
        add("USB (Arduino/camera): " + (temRecurso("android.hardware.usb.host") ? "sim" : "nao") + "   cameras do Android: " + cameras());
        add("");
        add("EXTENSOES GL (" + (gl3 != null ? "ES 3" : "ES 2") + "):");
        add(gl3 != null ? gl3[4] : (gl2 != null ? gl2[4] : "?"));
        add("");
        String arquivo = gravar();
        add("Relatorio gravado em: " + arquivo);
        add("Tire uma FOTO desta tela (de cima ate a linha CHIP) e mande.");
        add("Setas do controle: rolar.  VOLTAR: sair.");

        // ------------------------------------------------ tela
        LinearLayout raiz = new LinearLayout(this);
        raiz.setOrientation(LinearLayout.VERTICAL);
        raiz.setBackgroundColor(Color.rgb(11, 22, 52));
        int pad = dp(18);
        raiz.setPadding(pad, pad, pad, pad);

        TextView titulo = texto("STRIKE KIDS  -  TESTE DO APARELHO", 26, Color.rgb(255, 214, 64), true);
        raiz.addView(titulo);

        TextView vered = texto(veredito, 22, Color.WHITE, true);
        vered.setBackgroundColor(corVeredito);
        vered.setPadding(pad, pad / 2, pad, pad / 2);
        LinearLayout.LayoutParams lv = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lv.setMargins(0, pad / 2, 0, pad / 2);
        raiz.addView(vered, lv);

        TextView det = texto(rel.toString(), 15, Color.rgb(225, 235, 255), false);
        det.setTypeface(Typeface.MONOSPACE);
        rolar = new ScrollView(this);
        rolar.setFocusable(true);
        rolar.addView(det);
        raiz.addView(rolar, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        setContentView(raiz);
        rolar.requestFocus();
    }

    @Override
    public boolean onKeyDown(int code, KeyEvent ev) {
        if (rolar != null) {
            if (code == KeyEvent.KEYCODE_DPAD_DOWN) { rolar.smoothScrollBy(0, dp(120)); return true; }
            if (code == KeyEvent.KEYCODE_DPAD_UP) { rolar.smoothScrollBy(0, -dp(120)); return true; }
        }
        return super.onKeyDown(code, ev);
    }

    // ================================================================ OpenGL
    /** Cria um contexto OpenGL ES (2 ou 3) fora da tela e lê fabricante,
     * placa, versão, GLSL e extensões. null = esta versão não existe aqui. */
    private String[] lerGl(int versao) {
        EGL10 egl = (EGL10) EGLContext.getEGL();
        EGLDisplay dpy = egl.eglGetDisplay(EGL10.EGL_DEFAULT_DISPLAY);
        if (dpy == EGL10.EGL_NO_DISPLAY) return null;
        egl.eglInitialize(dpy, new int[2]);
        EGLContext ctx = EGL10.EGL_NO_CONTEXT;
        EGLSurface sup = EGL10.EGL_NO_SURFACE;
        try {
            int bit = versao >= 3 ? 0x40 /* EGL_OPENGL_ES3_BIT_KHR */ : 4 /* EGL_OPENGL_ES2_BIT */;
            int[] atrib = {EGL10.EGL_RENDERABLE_TYPE, bit, EGL10.EGL_SURFACE_TYPE, EGL10.EGL_PBUFFER_BIT,
                    EGL10.EGL_RED_SIZE, 8, EGL10.EGL_GREEN_SIZE, 8, EGL10.EGL_BLUE_SIZE, 8, EGL10.EGL_NONE};
            EGLConfig[] cfg = new EGLConfig[1];
            int[] n = new int[1];
            if (!egl.eglChooseConfig(dpy, atrib, cfg, 1, n) || n[0] == 0) {
                // sem o bit do ES 3 na configuração: tenta só pelo contexto
                atrib[1] = 4;
                if (!egl.eglChooseConfig(dpy, atrib, cfg, 1, n) || n[0] == 0) return null;
            }
            int[] cAtrib = {0x3098 /* EGL_CONTEXT_CLIENT_VERSION */, versao, EGL10.EGL_NONE};
            ctx = egl.eglCreateContext(dpy, cfg[0], EGL10.EGL_NO_CONTEXT, cAtrib);
            if (ctx == null || ctx == EGL10.EGL_NO_CONTEXT) return null;
            sup = egl.eglCreatePbufferSurface(dpy, cfg[0], new int[]{EGL10.EGL_WIDTH, 1, EGL10.EGL_HEIGHT, 1, EGL10.EGL_NONE});
            if (sup == null || sup == EGL10.EGL_NO_SURFACE) return null;
            if (!egl.eglMakeCurrent(dpy, sup, sup, ctx)) return null;
            String ver = GLES20.glGetString(GLES20.GL_VERSION);
            if (ver == null) return null;
            if (versao >= 3 && !ver.contains("ES 3")) return null;   // o driver deu um ES 2
            String ext = GLES20.glGetString(GLES20.GL_EXTENSIONS);
            return new String[]{GLES20.glGetString(GLES20.GL_VENDOR), GLES20.glGetString(GLES20.GL_RENDERER), ver,
                    GLES20.glGetString(GLES20.GL_SHADING_LANGUAGE_VERSION), ext == null ? "" : ext.trim().replace(' ', '\n')};
        } catch (Throwable t) {
            return null;
        } finally {
            try {
                egl.eglMakeCurrent(dpy, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_CONTEXT);
                if (sup != null && sup != EGL10.EGL_NO_SURFACE) egl.eglDestroySurface(dpy, sup);
                if (ctx != null && ctx != EGL10.EGL_NO_CONTEXT) egl.eglDestroyContext(dpy, ctx);
            } catch (Throwable t) { /* nada */ }
        }
    }

    private static String glReq(int req) {
        if (req == 0) return "?";
        return "OpenGL ES " + (req >> 16) + "." + (req & 0xffff);
    }

    /** Placas que dão conta da versão ALTA com folga. */
    private static boolean forte(String placa) {
        String p = placa.toLowerCase(Locale.ROOT);
        return p.contains("g52") || p.contains("g57") || p.contains("g68") || p.contains("g610") || p.contains("g710")
                || p.contains("adreno (tm) 6") || p.contains("adreno (tm) 7") || p.contains("ge8320") || p.contains("bxm");
    }

    // ================================================================ aparelho
    private String chip() {
        String soc = "";
        try {
            if (Build.VERSION.SDK_INT >= 31) {
                String fab = (String) Build.class.getField("SOC_MANUFACTURER").get(null);
                String mod = (String) Build.class.getField("SOC_MODEL").get(null);
                soc = (fab + " " + mod).trim();
            }
        } catch (Throwable t) { /* antes do Android 12 */ }
        String[] chaves = {"ro.soc.model", "ro.chipname", "ro.board.platform", "ro.hardware.chipname", "ro.product.board"};
        for (String k : chaves) {
            String v = prop(k);
            if (!v.isEmpty() && !soc.contains(v)) soc += (soc.isEmpty() ? "" : " / ") + v;
        }
        String hw = cpuCampo("Hardware");
        if (!hw.isEmpty() && !soc.contains(hw)) soc += (soc.isEmpty() ? "" : " / ") + hw;
        return soc.isEmpty() ? "?" : soc;
    }

    private static String prop(String chave) {
        try {
            Class<?> c = Class.forName("android.os.SystemProperties");
            Method m = c.getMethod("get", String.class);
            Object v = m.invoke(null, chave);
            return v == null ? "" : v.toString().trim();
        } catch (Throwable t) {
            return "";
        }
    }

    private static String cpuCampo(String campo) {
        try {
            BufferedReader r = new BufferedReader(new FileReader("/proc/cpuinfo"));
            String l;
            while ((l = r.readLine()) != null) {
                int i = l.indexOf(':');
                if (i > 0 && l.substring(0, i).trim().equalsIgnoreCase(campo)) {
                    r.close();
                    return l.substring(i + 1).trim();
                }
            }
            r.close();
        } catch (Throwable t) { /* sem */ }
        return "";
    }

    private static String cpuInfo() {
        String parte = cpuCampo("CPU part");
        String nucleo;
        switch (parte.toLowerCase(Locale.ROOT)) {
            case "0xc07": nucleo = "Cortex-A7 (32 bits)"; break;
            case "0xc09": nucleo = "Cortex-A9 (32 bits)"; break;
            case "0xd03": nucleo = "Cortex-A53 (64 bits)"; break;
            case "0xd04": nucleo = "Cortex-A35 (64 bits)"; break;
            case "0xd05": nucleo = "Cortex-A55 (64 bits)"; break;
            case "0xd08": nucleo = "Cortex-A72"; break;
            case "0xd09": nucleo = "Cortex-A73"; break;
            default: nucleo = parte.isEmpty() ? "" : "parte " + parte;
        }
        String mhz = "";
        try {
            BufferedReader r = new BufferedReader(new FileReader("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"));
            mhz = (Long.parseLong(r.readLine().trim()) / 1000) + " MHz";
            r.close();
        } catch (Throwable t) { /* sem */ }
        return (nucleo + "  " + mhz).trim();
    }

    @SuppressWarnings("deprecation")
    private static String abis() {
        try {
            String[] l = (String[]) Build.class.getField("SUPPORTED_ABIS").get(null);
            StringBuilder s = new StringBuilder();
            for (String a : l) s.append(s.length() > 0 ? ", " : "").append(a);
            return s.toString();
        } catch (Throwable t) {
            return Build.CPU_ABI + (Build.CPU_ABI2 == null || Build.CPU_ABI2.isEmpty() ? "" : ", " + Build.CPU_ABI2);
        }
    }

    private long ramTotal() {
        try {
            ActivityManager am = (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
            ActivityManager.MemoryInfo mi = new ActivityManager.MemoryInfo();
            am.getMemoryInfo(mi);
            return mi.totalMem;
        } catch (Throwable t) {
            return 0;
        }
    }

    private static String mb(long bytes) {
        if (bytes <= 0) return "?";
        return String.format(Locale.ROOT, "%.1f GB (%d MB)", bytes / 1073741824.0, bytes / 1048576);
    }

    @SuppressWarnings("deprecation")
    private String armazenamento() {
        try {
            StatFs s = new StatFs(Environment.getDataDirectory().getPath());
            long total = (long) s.getBlockCount() * (long) s.getBlockSize();
            long livre = (long) s.getAvailableBlocks() * (long) s.getBlockSize();
            return String.format(Locale.ROOT, "%.1f GB (livre %.1f GB)", total / 1073741824.0, livre / 1073741824.0);
        } catch (Throwable t) {
            return "?";
        }
    }

    @SuppressWarnings("deprecation")
    private String tela() {
        DisplayMetrics dm = new DisplayMetrics();
        try {
            getWindowManager().getDefaultDisplay().getClass().getMethod("getRealMetrics", DisplayMetrics.class)
                    .invoke(getWindowManager().getDefaultDisplay(), dm);
        } catch (Throwable t) {
            getWindowManager().getDefaultDisplay().getMetrics(dm);
        }
        return dm.widthPixels + " x " + dm.heightPixels + "  (" + dm.densityDpi + " dpi)";
    }

    private boolean temRecurso(String nome) {
        try {
            return getPackageManager().hasSystemFeature(nome);
        } catch (Throwable t) {
            return false;
        }
    }

    @SuppressWarnings("deprecation")
    private static String cameras() {
        try {
            return String.valueOf(android.hardware.Camera.getNumberOfCameras());
        } catch (Throwable t) {
            return "?";
        }
    }

    // ================================================================ arquivo e tela
    private String gravar() {
        File[] lugares = {getExternalFilesDir(null), getFilesDir()};
        for (File d : lugares) {
            if (d == null) continue;
            try {
                d.mkdirs();
                File f = new File(d, "aparelho.txt");
                OutputStreamWriter w = new OutputStreamWriter(new FileOutputStream(f), "UTF-8");
                w.write(rel.toString());
                w.close();
                return f.getAbsolutePath();
            } catch (Throwable t) { /* tenta o próximo */ }
        }
        return "(nao deu para gravar)";
    }

    private void add(String linha) {
        rel.append(linha).append('\n');
    }

    private TextView texto(String s, int sp, int cor, boolean negrito) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextColor(cor);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setGravity(Gravity.START);
        if (negrito) t.setTypeface(Typeface.DEFAULT_BOLD);
        return t;
    }

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }
}
