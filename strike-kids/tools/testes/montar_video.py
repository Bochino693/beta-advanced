# -*- coding: utf-8 -*-
"""
MONTA O VÍDEO DE DIVULGAÇÃO
===========================

Depois de gravar os quadros com o diretor (tools/testes/video.gd):

    python3 tools/testes/montar_video.py <pasta_dos_quadros> <saida.mp4> [fps] [primeiro_quadro]

Mistura a trilha (músicas + efeitos nos quadros exatos em que tocaram no
jogo), acrescenta um cartão final com o logo do jogo e gera o MP4
(H.264 + AAC). A marca Lazer & Sport vem da própria abertura do jogo.
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFont

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SONS = os.path.join(RAIZ, "sons")
TAXA = 44100


def ler_audio(caminho):
    """Lê wav/ogg (via ffmpeg) como float32 estéreo 44.1 kHz."""
    bruto = subprocess.run(["ffmpeg", "-v", "quiet", "-i", caminho, "-f", "f32le", "-ac", "2", "-ar", str(TAXA), "-"],
                           capture_output=True).stdout
    a = np.frombuffer(bruto, dtype=np.float32).reshape(-1, 2)
    return a.copy()


_cache = {}


def som(nome):
    if nome not in _cache:
        for ext in (".wav", ".ogg"):
            c = os.path.join(SONS, nome + ext)
            if os.path.exists(c):
                _cache[nome] = ler_audio(c)
                break
        else:
            _cache[nome] = None
    return _cache[nome]


def mudar_tom(a, tom):
    if abs(tom - 1.0) < 0.01:
        return a
    n = int(len(a) / tom)
    x = np.linspace(0, len(a) - 1, n)
    return np.stack([np.interp(x, np.arange(len(a)), a[:, k]) for k in range(2)], -1).astype(np.float32)


def cartao_final(pasta, inicio, n, largura, altura):
    logo = Image.open(os.path.join(RAIZ, "ui", "logo.png")).convert("RGBA")
    fonte = ImageFont.truetype(os.path.join(RAIZ, "fontes", "fredoka_700.ttf"), int(min(largura, altura) * 0.05))
    fonte2 = ImageFont.truetype(os.path.join(RAIZ, "fontes", "fredoka_600.ttf"), int(min(largura, altura) * 0.037))
    retratos = []
    for p in ("bob", "mia"):
        c = os.path.join(RAIZ, "ui", "retrato_%s_empolgado.png" % p)
        if os.path.exists(c):
            retratos.append(Image.open(c).convert("RGBA"))
    for i in range(n):
        t = i / max(n - 1, 1)
        img = Image.new("RGBA", (largura, altura))
        px = np.zeros((altura, largura, 4), dtype=np.uint8)
        g = np.linspace(0, 1, altura)[:, None]
        c1 = np.array([18, 58, 122, 255])
        c2 = np.array([22, 155, 213, 255])
        px[:] = (c1 * (1 - g) + c2 * g)[:, None, :].astype(np.uint8).reshape(altura, 1, 4)
        img = Image.fromarray(px, "RGBA")
        esc = 0.9 + 0.1 * min(1.0, t * 4)
        lw = int(largura * 0.86 * esc)
        lg = logo.resize((lw, int(lw * logo.height / logo.width)), Image.LANCZOS)
        img.alpha_composite(lg, ((largura - lw) // 2, int(altura * 0.12)))
        rs = int(min(largura, altura) * 0.5)
        for k, r in enumerate(retratos):
            rr = r.resize((rs, rs), Image.LANCZOS)
            x = int(largura * (0.27 if k == 0 else 0.73) - rs / 2)
            img.alpha_composite(rr, (x, int(altura * 0.42)))
        d = ImageDraw.Draw(img)
        for (txt, f, y) in (("Boliche infantil 3D com Bob e Mia", fonte, 0.76),
                            ("5 sensores  ·  4 cenários  ·  foto da criança  ·  replay", fonte2, 0.82)):
            w = d.textlength(txt, font=f)
            d.text(((largura - w) / 2, altura * y), txt, font=f, fill=(255, 255, 255), stroke_width=6, stroke_fill=(11, 31, 69))
        img.convert("RGB").save(os.path.join(pasta, "q%05d.jpg" % (inicio + i)), quality=93)


def main():
    pasta = sys.argv[1]
    saida = sys.argv[2]
    fps = float(sys.argv[3]) if len(sys.argv) > 3 else 30.0
    pula = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    dados = json.load(open(os.path.join(pasta, "sons.json")))
    quadros = int(dados["quadros"])
    reg = dados["registro"]
    base = 0
    for r in reg:
        if r[1] == "inicio":
            base = int(r[0])
    base += pula
    # a música que já tocava antes do corte começa no quadro 0
    antes = [r for r in reg if str(r[1]).startswith("musica:") and int(r[0]) < base]
    reg = [r for r in reg if int(r[0]) >= base or str(r[1]).startswith("rolando")]
    if antes:
        reg.insert(0, [base, antes[-1][1], 1.0, 1.0])
    primeiro = Image.open(os.path.join(pasta, "q%05d.jpg" % pula))
    W, H = primeiro.size
    extra = int(fps * 3.0)
    cartao_final(pasta, quadros, extra, W, H)
    total = quadros + extra - pula
    dur = total / fps
    trilha = np.zeros((int(dur * TAXA) + TAXA, 2), dtype=np.float32)

    def colocar(a, t, vol):
        i = int(t * TAXA)
        if i >= len(trilha) or a is None:
            return
        n = min(len(a), len(trilha) - i)
        trilha[i:i + n] += a[:n] * vol

    # música: trechos entre as trocas
    musicas = [(max(0, (int(r[0]) - base)) / fps, r[1][7:]) for r in reg if str(r[1]).startswith("musica:")]
    musicas.append((dur, ""))
    for k in range(len(musicas) - 1):
        t0, nome = musicas[k]
        t1 = musicas[k + 1][0]
        if not nome:
            continue
        m = som(nome)
        if m is None:
            continue
        n = int((t1 - t0 + 0.8) * TAXA)
        rep = np.tile(m, (n // len(m) + 1, 1))[:n].copy()
        fade = int(0.8 * TAXA)
        rep[:fade] *= np.linspace(0, 1, fade)[:, None]
        rep[-fade:] *= np.linspace(1, 0, fade)[:, None]
        colocar(rep, t0, 0.55)
    # bola rolando
    lig = None
    rol = som("bola_rolando")
    for r in reg:
        t = (int(r[0]) - base) / fps
        if r[1] == "rolando:on":
            lig = t
        elif r[1] == "rolando:off" and lig is not None and rol is not None:
            n = int((t - lig) * TAXA)
            rep = np.tile(rol, (n // len(rol) + 1, 1))[:n].copy()
            colocar(rep, max(lig, 0), 0.6)
            lig = None
    # efeitos
    for r in reg:
        nome = str(r[1])
        if nome == "inicio" or ":" in nome:
            continue
        t = (int(r[0]) - base) / fps
        if t < 0:
            continue
        a = som(nome)
        if a is None:
            continue
        colocar(mudar_tom(a, float(r[3])), t, float(r[2]) * 0.85)
    # final: jingle
    fim = som("fim")
    pico = np.max(np.abs(trilha)) or 1.0
    trilha = trilha / max(pico, 1.0) * 0.95 if pico > 0.95 else trilha
    trilha = np.clip(trilha[: int(dur * TAXA)], -1, 1)
    wav = os.path.join(pasta, "trilha.wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(TAXA)
        w.writeframes((trilha * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-framerate", str(fps), "-start_number", str(pula), "-i", os.path.join(pasta, "q%05d.jpg"), "-i", wav,
                    # qualidade alta com teto de taxa: arquivo leve para WhatsApp/Instagram (~25 MB)
                    "-c:v", "libx264", "-preset", "slow", "-crf", "21", "-maxrate", "2300k", "-bufsize", "4600k",
                    "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                    "-c:a", "aac", "-b:a", "192k", "-shortest", saida], check=True)
    print("vídeo:", saida, "%.1f s" % dur)


if __name__ == "__main__":
    main()
