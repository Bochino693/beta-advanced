#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# =============================================================================
# STRIKE KIDS - gerador de efeitos sonoros e musicas (sintese 100% original)
# -----------------------------------------------------------------------------
# Este script cria do zero, so com numpy (sem scipy), todos os sons do jogo:
#   * efeitos  -> sons/*.wav  (WAV PCM 16 bits, mono, 44100 Hz, pico ~ -1 dBFS)
#   * musicas  -> sons/musica_menu.ogg, musica_jogo.ogg, musica_fim.ogg
#                 (OGG Vorbis estereo 44100 Hz, loop perfeito em compassos
#                 inteiros, codificadas com ffmpeg -c:a libvorbis -q:a 4)
# Tudo e feito com osciladores, ruido filtrado (FFT) e envelopes; nenhum
# sample externo. A semente aleatoria e fixa, entao o resultado e sempre igual.
#
# Requisitos: python3, numpy e ffmpeg (com libvorbis) no PATH.
# Para gerar de novo, a partir da pasta strike-kids:
#     python3 tools/sons/gerar_sons.py
# Opcoes: --so-efeitos  (so os .wav)   |   --so-musicas  (so os .ogg)
# =============================================================================

import argparse
import os
import subprocess
import sys
import time
import wave
import zlib

import numpy as np

SR = 44100
SEED = 20261014
AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.abspath(os.path.join(AQUI, "..", ".."))
SAIDA = os.path.join(RAIZ, "sons")
TWO_PI = 2.0 * np.pi


# -----------------------------------------------------------------------------
# Utilitarios basicos
# -----------------------------------------------------------------------------
def rng(name):
    """Gerador aleatorio deterministico por som (independe da ordem)."""
    return np.random.default_rng([SEED, zlib.crc32(name.encode())])


def n_of(sec):
    return int(round(sec * SR))


def tt(n):
    return np.arange(n) / SR


def mtof(m):
    return 440.0 * 2.0 ** ((np.asarray(m, dtype=float) - 69.0) / 12.0)


_PC = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5,
       "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10,
       "Bb": 10, "B": 11}


def nm(s):
    """'C#5' -> numero MIDI."""
    return 12 * (int(s[-1]) + 1) + _PC[s[:-1]]


def hz(s):
    return float(mtof(nm(s)))


def rms(x):
    return float(np.sqrt(np.mean(np.square(x)) + 1e-20))


def env_pts(n, pts):
    ts = np.array([p[0] for p in pts], dtype=float)
    vs = np.array([p[1] for p in pts], dtype=float)
    return np.interp(tt(n), ts, vs)


def fade(x, fin=0.002, fout=0.02):
    x = x.copy()
    a = min(len(x), max(1, n_of(fin)))
    b = min(len(x), max(1, n_of(fout)))
    x[:a] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a))
    x[len(x) - b:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, b))
    return x


def add(buf, sig, pos, g=1.0, pan=0.0):
    """Mistura sig em buf a partir da amostra pos (mono ou estereo)."""
    pos = int(pos)
    if pos >= len(buf):
        return
    if pos < 0:
        sig = sig[-pos:]
        pos = 0
    n = min(len(sig), len(buf) - pos)
    if n <= 0:
        return
    if buf.ndim == 1:
        s = sig[:n] if sig.ndim == 1 else sig[:n].mean(axis=1)
        buf[pos:pos + n] += g * s
    elif sig.ndim == 1:
        th = (pan + 1.0) * np.pi / 4.0
        buf[pos:pos + n, 0] += g * np.cos(th) * np.sqrt(2) * sig[:n]
        buf[pos:pos + n, 1] += g * np.sin(th) * np.sqrt(2) * sig[:n]
    else:
        buf[pos:pos + n, 0] += g * min(1.0, 1.0 - pan) * sig[:n, 0]
        buf[pos:pos + n, 1] += g * min(1.0, 1.0 + pan) * sig[:n, 1]


# ---- filtros no dominio da frequencia (fase zero, vetorizados) ---------------
def bp(f, fc, octaves):
    """Passa-banda gaussiano em escala log (largura em oitavas)."""
    return np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / fc) / octaves) ** 2)


def lp(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def hp(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-3)) ** (2 * order))


def fft_filter(x, mask, circular=False, pad_s=0.1):
    """Filtra x com o ganho mask(freq). circular=True para loops."""
    n = len(x)
    m = n if circular else n + n_of(pad_s)
    X = np.fft.rfft(x, m, axis=0)
    g = mask(np.fft.rfftfreq(m, 1.0 / SR))
    if X.ndim == 2:
        g = g[:, None]
    return np.fft.irfft(X * g, m, axis=0)[:n]


def tv_filter(x, mask_fn, nfft=1024, hop=256):
    """Filtro variante no tempo via STFT: mask_fn(freqs[1,B], tempos[F,1])."""
    n = len(x)
    pad = nfft
    xp = np.concatenate([np.zeros(pad), x, np.zeros(pad + nfft)])
    nfr = 1 + (len(xp) - nfft) // hop
    win = 0.5 - 0.5 * np.cos(TWO_PI * np.arange(nfft) / nfft)
    idx = np.arange(nfft)[None, :] + hop * np.arange(nfr)[:, None]
    X = np.fft.rfft(xp[idx] * win, axis=1)
    f = np.fft.rfftfreq(nfft, 1.0 / SR)[None, :]
    tc = ((np.arange(nfr) * hop + nfft / 2 - pad) / SR)[:, None]
    yf = np.fft.irfft(X * mask_fn(f, tc), nfft, axis=1) * win
    y = np.zeros(len(xp))
    ws = np.zeros(len(xp))
    for i in range(nfr):
        s = i * hop
        y[s:s + nfft] += yf[i]
        ws[s:s + nfft] += win * win
    y /= np.maximum(ws, 1e-3)
    return y[pad:pad + n]


def smooth_random(r, n, rate_hz, lo=0.0, hi=1.0):
    """Curva aleatoria suave (para modulacoes)."""
    k = max(2, int(n / SR * rate_hz) + 2)
    pts = r.random(k)
    y = np.interp(np.linspace(0, k - 1, n), np.arange(k), pts)
    y = fft_filter(y - y.mean(), lambda f: lp(f, rate_hz, 2)) + y.mean()
    y = (y - y.min()) / (y.max() - y.min() + 1e-12)
    return lo + (hi - lo) * y


# -----------------------------------------------------------------------------
# Instrumentos
# -----------------------------------------------------------------------------
def _modal(f, parts, tau, n, attack=0.0012):
    t = tt(n)
    y = np.zeros(n)
    tot = 0.0
    for ratio, a, ts in parts:
        fr = f * ratio
        if fr > 0.42 * SR:
            continue
        y += a * np.sin(TWO_PI * fr * t) * np.exp(-t / (tau * ts))
        tot += a
    y /= max(tot, 1e-9)
    return y * np.minimum(1.0, t / attack)


def _click(r, n, fc, tau=0.0012, oct_=1.0):
    c = r.standard_normal(n) * np.exp(-tt(n) / tau)
    c = fft_filter(c, lambda f: bp(f, fc, oct_))
    return c / (np.max(np.abs(c)) + 1e-9)


def mallet(f, vel=1.0, kind="marimba", r=None, tau_scale=1.0):
    """Marimba / xilofone: parciais modais com decaimento rapido."""
    if kind == "xylo":
        parts = [(1.0, 1.0, 1.0), (3.0, 0.40, 0.30), (6.1, 0.14, 0.12), (10.2, 0.05, 0.05)]
        base = 0.30
    else:
        parts = [(1.0, 1.0, 1.0), (3.93, 0.30, 0.20), (9.2, 0.09, 0.06)]
        base = 0.55
    tau = base * tau_scale * (440.0 / f) ** 0.4
    n = n_of(min(5.0 * tau, 2.5) + 0.01)
    y = _modal(f, parts, tau, n)
    if r is not None:
        nc = n_of(0.006)
        y[:nc] += 0.12 * _click(r, nc, min(4.0 * f, 6000.0))
    return vel * y


def glock(f, vel=1.0, r=None, tau_scale=1.0):
    """Glockenspiel (parciais inarmonicos de barra metalica)."""
    parts = [(1.0, 1.0, 1.0), (2.76, 0.28, 0.35), (5.40, 0.10, 0.15), (8.93, 0.04, 0.08)]
    tau = 0.9 * tau_scale * (1046.0 / f) ** 0.3
    n = n_of(min(5.0 * tau, 2.5) + 0.01)
    y = _modal(f, parts, tau, n, attack=0.0006)
    if r is not None:
        nc = n_of(0.004)
        y[:nc] += 0.08 * _click(r, nc, 7000.0, 0.0008)
    return vel * y


def chime(f, vel=1.0, tau=0.45):
    """Sino/carrilhao suave para dings."""
    parts = [(1.0, 1.0, 1.0), (2.0, 0.45, 0.55), (3.0, 0.20, 0.35), (4.16, 0.12, 0.22), (5.43, 0.07, 0.15)]
    n = n_of(min(5.0 * tau, 2.5))
    return vel * _modal(f, parts, tau, n, attack=0.001)


def brass(f, dur, vel=1.0, att=0.025, rel=0.18, vib=0.0, r=None,
          voices=(-6.0, 6.0), bright=1.0, scoop=30.0):
    """Metal sintetico (serra aditiva cujo brilho acompanha o volume)."""
    n = n_of(dur + rel)
    t = tt(n)
    sus = max(dur, att + 0.09)
    amp = env_pts(n, [(0, 0), (att, 1.0), (att + 0.08, 0.82), (sus, 0.72), (sus + rel, 0.0)])
    vibr = vib * np.sin(TWO_PI * 5.5 * t) * np.clip((t - 0.12) / 0.25, 0, 1)
    b = 1.2 + 10.0 * bright * amp
    y = np.zeros(n)
    K = int(min(40, 0.42 * SR / (f * 1.02)))
    for i, dc in enumerate(voices):
        cents = dc - scoop * np.exp(-t / 0.03) + vibr
        ph = TWO_PI * np.cumsum(f * 2.0 ** (cents / 1200.0)) / SR
        ph += (r.random() * TWO_PI) if r is not None else 1.3 * i
        for k in range(1, K + 1):
            y += (1.0 / k) * np.exp(-(k - 1) / b) * np.sin(k * ph)
    y *= amp
    return vel * y / (np.max(np.abs(y)) + 1e-9)


def square_tone(f_inst, n, soft=1.15, bright=None):
    """Onda quadrada de banda limitada (harmonicos impares)."""
    f_inst = np.broadcast_to(np.asarray(f_inst, dtype=float), (n,))
    ph = TWO_PI * np.cumsum(f_inst) / SR
    fmax = float(np.max(f_inst))
    y = np.zeros(n)
    k = 1
    while k * fmax < 0.42 * SR and k < 60:
        w = 1.0 / k ** soft
        if bright is not None:
            w = w * np.exp(-(k - 1) / bright)
        y += w * np.sin(k * ph)
        k += 2
    return y / (np.max(np.abs(y)) + 1e-9)


def square_lead(f, dur, vel=1.0, vib=12.0, rel=0.2):
    n = n_of(dur + rel)
    t = tt(n)
    cents = vib * np.sin(TWO_PI * 5.8 * t) * np.clip((t - 0.15) / 0.3, 0, 1)
    y = square_tone(f * 2.0 ** (cents / 1200.0), n, soft=1.3)
    env = env_pts(n, [(0, 0), (0.01, 1.0), (0.12, 0.75), (dur, 0.65), (dur + rel, 0)])
    return vel * y * env


def sq_pluck(f, vel=1.0, tau=0.14):
    n = n_of(min(6 * tau, 1.2))
    t = tt(n)
    y = square_tone(f, n, soft=1.2, bright=1.0 + 8.0 * np.exp(-t / 0.05))
    return vel * y * np.exp(-t / tau) * np.minimum(1.0, t / 0.002)


def pad_note(f, dur, att=0.3, rel=0.6, r=None):
    """Pad estereo macio (serras desafinadas, poucas harmonicas)."""
    n = n_of(dur + rel)
    t = tt(n)
    out = np.zeros((n, 2))
    for ch, dets in enumerate([(-9.0, 4.0), (-4.0, 9.0)]):
        for dc in dets:
            fd = f * 2.0 ** (dc / 1200.0)
            ph0 = r.random() * TWO_PI if r is not None else 0.7
            K = int(min(10, 0.4 * SR / fd))
            for k in range(1, K + 1):
                out[:, ch] += k ** -1.7 * np.sin(TWO_PI * k * fd * t + k * ph0)
    env = env_pts(n, [(0, 0), (att, 1.0), (dur, 0.85), (dur + rel, 0.0)])
    out *= env[:, None]
    return out / (np.max(np.abs(out)) + 1e-9)


def bass_pluck(f, dur, vel=1.0):
    """Baixo 'plucky': fundamental + harmonicos que somem rapido."""
    n = n_of(dur + 0.06)
    t = tt(n)
    ph = TWO_PI * f * t
    y = np.sin(ph)
    for k in range(2, 9):
        if k * f > 0.4 * SR:
            break
        y += (0.7 / k) * np.exp(-t * (k - 1) * 9.0) * np.sin(k * ph)
    gate = np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.02))
    y *= np.exp(-t / 0.55) * gate * np.minimum(1.0, t / 0.004)
    return vel * y / (np.max(np.abs(y)) + 1e-9)


# ---- bateria ------------------------------------------------------------------
def kick(r, vel=1.0, tau=0.16, f_hi=95.0, f_lo=46.0):
    n = n_of(0.45)
    t = tt(n)
    f = f_lo + f_hi * np.exp(-t / 0.035)
    y = np.sin(TWO_PI * np.cumsum(f) / SR) * np.exp(-t / tau)
    nc = n_of(0.006)
    y[:nc] += 0.25 * _click(r, nc, 2500.0, 0.0015, 1.5)
    y *= np.minimum(1.0, t / 0.001)
    return vel * y / (np.max(np.abs(y)) + 1e-9)


def snare(r, vel=1.0, tau=0.065):
    n = n_of(0.3)
    t = tt(n)
    nz = fft_filter(r.standard_normal(n), lambda f: bp(f, 3200.0, 1.3) + 0.3 * hp(f, 7000.0, 2))
    nz /= np.max(np.abs(nz)) + 1e-9
    y = 0.8 * nz * np.exp(-t / tau)
    y += 0.5 * np.sin(TWO_PI * 195.0 * t) * np.exp(-t / 0.04)
    y += 0.22 * np.sin(TWO_PI * 330.0 * t) * np.exp(-t / 0.025)
    y *= np.minimum(1.0, t / 0.0008)
    return vel * y / (np.max(np.abs(y)) + 1e-9)


def clap(r, vel=1.0):
    n = n_of(0.3)
    t = tt(n)
    nz = fft_filter(r.standard_normal(n), lambda f: bp(f, 1400.0, 0.8))
    e = np.zeros(n)
    for d in (0.0, 0.009, 0.019):
        e += np.where(t >= d, np.exp(-(t - d) / 0.006), 0.0)
    e += 0.5 * np.where(t >= 0.028, np.exp(-(t - 0.028) / 0.07), 0.0)
    y = nz * e
    return vel * y / (np.max(np.abs(y)) + 1e-9)


def hat(r, vel=1.0, tau=0.022, dur=0.1):
    n = n_of(dur)
    t = tt(n)
    nz = fft_filter(r.standard_normal(n), lambda f: hp(f, 7000.0, 3) * (0.6 + 0.4 * bp(f, 10000.0, 0.6)))
    y = nz * np.exp(-t / tau) * np.minimum(1.0, t / 0.0005)
    return vel * y / (np.max(np.abs(y)) + 1e-9)


def shaker(r, vel=1.0):
    n = n_of(0.09)
    t = tt(n)
    nz = fft_filter(r.standard_normal(n), lambda f: bp(f, 6500.0, 0.7))
    y = nz * np.minimum(1.0, t / 0.008) * np.exp(-t / 0.025)
    return vel * y / (np.max(np.abs(y)) + 1e-9)


def crash(r, dur=1.8, vel=1.0, tau=0.55):
    n = n_of(dur)
    t = tt(n)
    nz = fft_filter(r.standard_normal(n), lambda f: hp(f, 3200.0, 2) * (0.5 + bp(f, 6500.0, 0.8)))
    y = nz * np.exp(-t / tau) * np.minimum(1.0, t / 0.001)
    return vel * fade(y / (np.max(np.abs(y)) + 1e-9), 0.0005, 0.2)


def woodblock(r, f=900.0, vel=1.0, dur=0.1):
    n = n_of(dur)
    y = _modal(f, [(1.0, 1.0, 1.0), (2.45, 0.45, 0.5), (4.1, 0.2, 0.25)], 0.02, n, attack=0.0004)
    nc = n_of(0.003)
    y[:nc] += 0.25 * _click(r, nc, 3000.0, 0.0006)
    return vel * y / (np.max(np.abs(y)) + 1e-9)


def pin_clack(r, fscale=1.0, dur=0.35, vel=1.0):
    """Batida de pino de madeira: ruido 1.5-3 kHz + modos ressonantes rapidos."""
    n = n_of(dur)
    t = tt(n)
    burst = r.standard_normal(n) * np.exp(-t / 0.004)
    burst = fft_filter(burst, lambda f: bp(f, 2200.0 * fscale, 0.55))
    y = 0.9 * burst / (np.max(np.abs(burst)) + 1e-9)
    modes = [(720.0, 0.55, 0.045), (1180.0, 0.38, 0.030), (1930.0, 0.28, 0.018), (2750.0, 0.18, 0.011)]
    for f0, a, tau in modes:
        fr = f0 * fscale * (1.0 + r.uniform(-0.04, 0.04))
        y += a * np.sin(TWO_PI * fr * t + r.random() * TWO_PI) * np.exp(-t / tau)
    y += 0.35 * np.sin(TWO_PI * 210.0 * fscale * t) * np.exp(-t / 0.025)  # corpo oco "toc"
    y *= np.minimum(1.0, t / 0.0004)
    return vel * y / (np.max(np.abs(y)) + 1e-9)


# -----------------------------------------------------------------------------
# Efeitos sonoros
# -----------------------------------------------------------------------------
def sfx_bola_rolando(r):
    N = n_of(2.0)
    X = n_of(0.3)
    n = N + X
    rum = fft_filter(r.standard_normal(n), lambda f: lp(f, 160.0, 3) * hp(f, 30.0, 2))
    rum /= rms(rum)
    wood = fft_filter(r.standard_normal(n), lambda f: bp(f, 420.0, 0.6) + 0.5 * bp(f, 900.0, 0.5))
    wood /= rms(wood)
    grit = fft_filter(r.standard_normal(n), lambda f: bp(f, 2400.0, 0.8))
    grit = grit / rms(grit) * smooth_random(r, n, 8.0, 0.3, 1.0)
    noise = rum + 0.20 * wood + 0.025 * grit
    # costura do loop: crossfade de potencia igual do final para o inicio
    w = np.linspace(0.0, 1.0, X)
    y = noise[:N].copy()
    y[:X] = noise[N:N + X] * np.sqrt(1.0 - w) + noise[:X] * np.sqrt(w)
    # componentes periodicas (numero inteiro de ciclos em 2 s => sem emenda)
    t = tt(N)
    am = 1.0 + 0.16 * np.sin(TWO_PI * 5.5 * t) + 0.07 * np.sin(TWO_PI * 2.5 * t + 1.0)
    hum = (np.sin(TWO_PI * 52.0 * t) + 0.5 * np.sin(TWO_PI * 78.5 * t + 0.4)) * (1 + 0.3 * np.sin(TWO_PI * 2.5 * t))
    return y * am + 0.30 * hum


def sfx_pino(r, var):
    fs = [0.94, 1.0, 1.09][var]
    return pin_clack(r, fs)


def sfx_pinos_queda(r):
    n = n_of(1.4)
    t = tt(n)
    y = np.zeros(n)
    # baque grave inicial (bola entrando nos pinos)
    f = 55.0 + 85.0 * np.exp(-t / 0.05)
    thump = np.sin(TWO_PI * np.cumsum(f) / SR) * np.exp(-t / 0.12) * np.minimum(1, t / 0.002)
    thn = fft_filter(r.standard_normal(n), lambda f: lp(f, 400.0, 2)) * np.exp(-t / 0.05)
    y += 0.9 * thump + 0.5 * thn / (np.max(np.abs(thn)) + 1e-9)
    # 15-25 batidas aleatorias concentradas no inicio
    k = int(r.integers(18, 24))
    times = np.sort(0.9 * r.random(k) ** 1.7)
    times[0] = 0.004
    for tm in times:
        g = np.exp(-tm / 0.55) * r.uniform(0.45, 1.0)
        add(y, pin_clack(r, r.uniform(0.82, 1.22), 0.35), n_of(tm), 0.75 * g)
    # pinos caindo no chao (tuns graves curtos)
    for tm in r.uniform(0.15, 0.95, 5):
        nn = n_of(0.15)
        tl = tt(nn)
        th = np.sin(TWO_PI * r.uniform(120, 190) * tl) * np.exp(-tl / 0.03) * np.minimum(1, tl / 0.001)
        add(y, th, n_of(tm), 0.25 * r.uniform(0.5, 1))
    # chiado de pinos rolando
    cl = fft_filter(r.standard_normal(n), lambda f: bp(f, 1800.0, 0.9))
    cl = cl / rms(cl) * smooth_random(r, n, 25.0, 0.0, 1.0) ** 2
    y += 0.06 * cl * env_pts(n, [(0, 0), (0.05, 1), (0.9, 0.5), (1.4, 0)])
    return y


def sfx_strike(r):
    n = n_of(2.2)
    y = np.zeros(n)
    for i, nt in enumerate(["C5", "E5", "G5", "C6", "E6", "G6"]):
        add(y, mallet(hz(nt), 0.7 + 0.06 * i, "xylo", r), n_of(0.052 * i))
    T = 0.34
    for nt, g in [("C3", 0.35), ("C4", 0.5), ("G4", 0.42), ("C5", 0.5), ("E5", 0.42), ("G5", 0.32)]:
        add(y, brass(hz(nt), 1.25, r=r, vib=10.0), n_of(T), g)
    add(y, square_lead(hz("C6"), 1.2, vib=14.0), n_of(T), 0.22)
    add(y, square_lead(hz("E6"), 1.2, vib=14.0), n_of(T), 0.12)
    for nt in ["C6", "E6", "G6"]:
        add(y, mallet(hz(nt), 0.5, "marimba", r), n_of(T))
    add(y, kick(r, tau=0.22), n_of(T), 0.7)
    add(y, crash(r, 1.85), n_of(T), 0.28)
    notes = ["C7", "E7", "G7", "C7", "G6", "E7", "C8", "G7"]
    for i in range(10):
        tm = T + 0.06 + i * 0.12 + r.uniform(0, 0.04)
        add(y, glock(hz(notes[int(r.integers(len(notes)))]), r=r), n_of(tm), 0.33 * (1 - i / 13))
    return y


def sfx_spare(r):
    n = n_of(1.4)
    y = np.zeros(n)
    for i, nt in enumerate(["G5", "C6", "E6"]):
        add(y, mallet(hz(nt), 0.8, "xylo", r), n_of(0.065 * i))
    T = 0.2
    for nt in ["C6", "E6", "G6"]:
        add(y, mallet(hz(nt), 0.7, "marimba", r), n_of(T))
    for nt, g in [("C4", 0.3), ("E4", 0.28), ("G4", 0.28), ("C5", 0.3)]:
        add(y, brass(hz(nt), 0.42, r=r, vib=8.0, rel=0.25), n_of(T), g)
    add(y, glock(hz("C7"), r=r), n_of(T + 0.02), 0.35)
    add(y, glock(hz("E7"), r=r), n_of(T + 0.14), 0.3)
    add(y, glock(hz("G7"), r=r), n_of(T + 0.26), 0.22)
    return y


def sfx_boa(r):
    n = n_of(0.8)
    y = np.zeros(n)
    add(y, chime(hz("G6"), tau=0.3), 0, 0.8)
    add(y, chime(hz("C7"), tau=0.35), n_of(0.11), 1.0)
    add(y, glock(hz("G7"), r=r, tau_scale=0.5), n_of(0.11), 0.15)
    return y


def sfx_ops(r):
    """Trombone de surdina 'wah-wah-waah' com vibrato (engracado)."""
    n = n_of(1.3)
    t = tt(n)
    notes = [(0.0, 0.24, "G4"), (0.27, 0.24, "F#4"), (0.54, 0.70, "F4")]
    midi = np.full(n, float(nm("G4")))
    amp = np.zeros(n)
    bright = np.zeros(n)
    for i, (s, d, nt) in enumerate(notes):
        i0, i1 = n_of(s), min(n, n_of(s + d))
        tl = t[i0:i1] - s
        m = float(nm(nt)) + np.zeros(len(tl))
        a = np.minimum(1.0, tl / 0.03) * np.clip((d - tl) / 0.05, 0, 1)
        if i == len(notes) - 1:
            m -= 1.0 * np.clip((tl - 0.25) / 0.45, 0, 1)
            m += 0.35 * np.sin(TWO_PI * 6.5 * tl) * np.clip((tl - 0.08) / 0.2, 0, 1)
            b = np.clip(tl / 0.15, 0, 1) * (1 - 0.6 * np.clip((tl - 0.3) / 0.4, 0, 1))
            a *= 1.0 - 0.25 * np.clip((tl - 0.3) / 0.4, 0, 1)
        else:
            b = np.sin(np.pi * np.clip(tl / d, 0, 1)) ** 0.8
        midi[i0:i1] = m
        amp[i0:i1] = a
        bright[i0:i1] = b
        if i1 < n:
            midi[i1:] = m[-1]
    f = mtof(midi)
    ph = TWO_PI * np.cumsum(f) / SR
    y = np.zeros(n)
    for k in range(1, 31):
        if k * 400.0 > 0.42 * SR:
            break
        w = k ** -0.9 * np.exp(-(k - 1) / (0.7 + 6.0 * bright)) * (1.0 + 1.5 * bp(k * f, 1100.0, 0.6))
        y += w * np.sin(k * ph)
    return y * amp


def sfx_boing(r):
    n = n_of(0.5)
    t = tt(n)
    f0 = 140.0 + 200.0 * (1 - np.exp(-t / 0.10))
    f = f0 * (1.0 + 0.32 * np.exp(-t / 0.16) * np.sin(TWO_PI * 17.0 * t))
    ph = TWO_PI * np.cumsum(f) / SR
    y = np.sin(ph) + 0.35 * np.sin(2 * ph) * np.exp(-t / 0.1) + 0.15 * np.sin(3 * ph) * np.exp(-t / 0.06)
    y *= np.minimum(1.0, t / 0.003) * np.exp(-t / 0.17)
    th = np.sin(TWO_PI * 90.0 * t) * np.exp(-t / 0.03) * np.minimum(1, t / 0.002)
    return y + 0.4 * th


def sfx_moeda(r):
    n = n_of(0.5)
    y = np.zeros(n)
    n1 = n_of(0.075)
    s1 = square_tone(hz("B5"), n1) * env_pts(n1, [(0, 0), (0.001, 1), (0.072, 1), (0.075, 0)])
    n2 = n - n1
    t2 = tt(n2)
    s2 = square_tone(hz("E6"), n2) * np.minimum(1, t2 / 0.001) * np.where(t2 < 0.06, 1.0, np.exp(-(t2 - 0.06) / 0.11))
    y[:n1] += 0.8 * s1
    y[n1:] += 0.8 * s2
    return y


def sfx_start(r):
    n = n_of(0.9)
    t = tt(n)
    y = np.zeros(n)
    # arpejo quadrado subindo (C maior)
    seq = ["C5", "E5", "G5", "C6", "E6", "G6", "C7", "E7", "G7"]
    step = 0.068
    fi = np.full(n, hz(seq[-1]))
    pulse = np.zeros(n)
    for i, nt in enumerate(seq):
        a, b = n_of(i * step), n_of((i + 1) * step)
        fi[a:b] = hz(nt)
        tl = t[a:b] - i * step
        pulse[a:b] = np.exp(-tl / 0.05)
    end = n_of(len(seq) * step)
    pulse[end:] = pulse[end - 1] * np.exp(-(t[end:] - t[end]) / 0.06)
    arp = square_tone(fi, n, soft=1.3) * pulse * np.minimum(1, t / 0.002)
    y += 0.35 * arp
    # varredura senoidal com tremolo
    fs = 200.0 * 2.0 ** (np.minimum(t, 0.75) / 0.75 * 3.5)
    sw = np.sin(TWO_PI * np.cumsum(fs) / SR) * (0.75 + 0.25 * np.sin(TWO_PI * 28.0 * t))
    y += 0.3 * sw * env_pts(n, [(0, 0), (0.05, 0.6), (0.6, 1.0), (0.85, 0.0), (0.9, 0)])
    # jato de ruido (botas a jato acendendo)
    jet = tv_filter(r.standard_normal(n), lambda f, tc: bp(f, 300.0 * 10.0 ** (np.clip(tc, 0, 0.8) / 0.8), 1.0))
    jet /= np.max(np.abs(jet)) + 1e-9
    y += 0.45 * jet * env_pts(n, [(0, 0), (0.1, 0.8), (0.55, 1.0), (0.9, 0.0)])
    # brilho final
    for tm, nt in [(0.55, "C7"), (0.63, "G7"), (0.71, "E7"), (0.78, "C8")]:
        add(y, glock(hz(nt), r=r, tau_scale=0.4), n_of(tm), 0.25)
    return y


def sfx_selecao(r):
    n = n_of(0.15)
    t = tt(n)
    f = 1200.0 * (1 + 0.25 * (1 - np.exp(-t / 0.01)))
    ph = TWO_PI * np.cumsum(f) / SR
    y = (np.sin(ph) + 0.2 * np.sin(3 * ph)) * np.minimum(1, t / 0.001) * np.exp(-t / 0.035)
    return y


def sfx_escolha(r):
    n = n_of(0.7)
    y = np.zeros(n)
    add(y, mallet(hz("G5"), 0.8, "marimba", r), 0)
    add(y, mallet(hz("C6"), 0.85, "marimba", r), n_of(0.1))
    add(y, mallet(hz("E6"), 1.0, "marimba", r), n_of(0.2))
    add(y, mallet(hz("C5"), 0.6, "marimba", r), n_of(0.2))
    add(y, glock(hz("E7"), r=r, tau_scale=0.5), n_of(0.2), 0.2)
    return y


def sfx_pop(r):
    n = n_of(0.2)
    t = tt(n)
    f = 300.0 + 1500.0 * (1 - np.exp(-t / 0.012))
    y = np.sin(TWO_PI * np.cumsum(f) / SR) * np.minimum(1, t / 0.001) * np.exp(-t / 0.025)
    nc = n_of(0.004)
    y[:nc] += 0.3 * _click(r, nc, 3000.0, 0.0006)
    return y


def sfx_brilho(r):
    n = n_of(0.7)
    t = tt(n)
    y = np.zeros(n)
    pool = ["C7", "D7", "E7", "G7", "A7", "C8"]
    for i in range(11):
        tm = i * 0.042 + r.uniform(0, 0.02)
        add(y, glock(hz(pool[int(r.integers(len(pool)))]), r=r, tau_scale=0.35), n_of(tm), 0.9 * (1 - i / 14))
    sh = np.sin(TWO_PI * 4186.0 * t) * (0.5 + 0.5 * np.sin(TWO_PI * 22 * t)) * env_pts(n, [(0, 0), (0.1, 1), (0.7, 0)])
    return y + 0.05 * sh


def sfx_vez(r):
    n = n_of(0.7)
    y = np.zeros(n)
    add(y, chime(hz("C6"), tau=0.35), 0, 0.85)
    add(y, chime(hz("G6"), tau=0.4), n_of(0.16), 1.0)
    return y


def sfx_tique(r):
    return woodblock(r, 900.0, 1.0, 0.1)


def sfx_recorde(r):
    n = n_of(2.8)
    y = np.zeros(n)
    # rufar de caixa crescendo
    for i in range(16):
        add(y, snare(r, tau=0.04), n_of(i * 0.026), 0.10 + 0.25 * i / 15)
    arp = ["C5", "E5", "G5", "C6", "E6", "G6", "C7", "E7"]
    for i, nt in enumerate(arp):
        add(y, mallet(hz(nt), 0.6 + 0.05 * i, "xylo", r), n_of(0.05 * i))
    # 'ta-ta-taaa' bVI - bVII - I
    hits = [(0.45, 0.14, ["Ab3", "C4", "Eb4", "Ab4"], "Ab5"),
            (0.62, 0.14, ["Bb3", "D4", "F4", "Bb4"], "Bb5"),
            (0.79, 1.25, ["C3", "C4", "E4", "G4", "C5", "E5"], "C6")]
    for tm, d, chord, top in hits:
        for nt in chord:
            add(y, brass(hz(nt), d, r=r, vib=10.0 if d > 1 else 0.0, rel=0.12 if d < 1 else 0.5), n_of(tm), 0.4)
        add(y, square_lead(hz(top), d, vib=14.0 if d > 1 else 0.0, rel=0.1 if d < 1 else 0.45), n_of(tm), 0.25)
        add(y, kick(r, tau=0.2), n_of(tm), 0.6 if d > 1 else 0.4)
    add(y, crash(r, 2.0), n_of(0.79), 0.32)
    # rolo de marimba no acorde final
    for i in range(12):
        nt = ["C6", "E6", "G6", "C7"][i % 4]
        add(y, mallet(hz(nt), 0.5 * (1 - i / 14), "marimba", r), n_of(0.79 + i * 0.065))
    pool = ["C7", "E7", "G7", "C8", "G7", "E7"]
    for i in range(14):
        tm = 0.85 + i * 0.1 + r.uniform(0, 0.04)
        add(y, glock(hz(pool[int(r.integers(len(pool)))]), r=r), n_of(tm), 0.3 * (1 - i / 17))
    return y


def sfx_fim(r):
    n = n_of(2.6)
    y = np.zeros(n)
    chords = [(0.0, 0.38, ["F3", "A3", "C4", "F4"], "F2"),
              (0.4, 0.38, ["G3", "B3", "D4", "G4"], "G2"),
              (0.8, 1.1, ["C3", "E4", "G4", "C5"], "C2")]
    for tm, d, ch, bass in chords:
        for nt in ch:
            add(y, brass(hz(nt), d, r=r, vib=8.0 if d > 1 else 0.0, rel=0.15 if d < 1 else 0.6, bright=0.8), n_of(tm), 0.3)
        add(y, bass_pluck(hz(bass), d + 0.2), n_of(tm), 0.55)
        add(y, kick(r), n_of(tm), 0.45 if d > 1 else 0.3)
    for tm, nt in [(0.0, "A5"), (0.2, "C6"), (0.4, "B5"), (0.6, "D6"), (0.8, "C6"), (0.86, "E6"), (0.92, "G6"), (0.98, "C7")]:
        add(y, mallet(hz(nt), 0.85, "xylo", r), n_of(tm))
    add(y, crash(r, 1.8), n_of(0.8), 0.2)
    for i, nt in enumerate(["C7", "E7", "G7", "C8", "G7", "E7", "C7"]):
        add(y, glock(hz(nt), r=r), n_of(1.0 + i * 0.09), 0.28 * (1 - i / 9))
    return y


def sfx_confete(r):
    n = n_of(0.8)
    t = tt(n)
    y = np.zeros(n)
    # estouro
    nb = n_of(0.03)
    b = fft_filter(r.standard_normal(nb), lambda f: lp(f, 6000.0, 2) * hp(f, 300.0, 1)) * np.exp(-tt(nb) / 0.005)
    add(y, b / (np.max(np.abs(b)) + 1e-9), 0, 1.0)
    add(y, np.sin(TWO_PI * 120.0 * t) * np.exp(-t / 0.03) * np.minimum(1, t / 0.001), 0, 0.6)
    add(y, np.sin(TWO_PI * 900.0 * t) * np.exp(-t / 0.012) * np.minimum(1, t / 0.0005), 0, 0.3)
    # chuva de papel: graos de ruido aleatorios
    grains = np.zeros(n)
    gl = n_of(0.003)
    for i in range(320):
        tm = 0.02 + 0.72 * r.random() ** 1.6
        g = r.standard_normal(gl) * np.hanning(gl)
        add(grains, g, n_of(tm), r.uniform(0.2, 1.0) * np.exp(-tm / 0.35))
    grains = fft_filter(grains, lambda f: hp(f, 3000.0, 2) * (0.6 + bp(f, 7000.0, 0.8)))
    grains /= np.max(np.abs(grains)) + 1e-9
    rus = fft_filter(r.standard_normal(n), lambda f: hp(f, 4000.0, 2))
    rus = rus / rms(rus) * smooth_random(r, n, 30.0, 0.2, 1.0)
    shower_env = env_pts(n, [(0, 0), (0.04, 1.0), (0.3, 0.6), (0.8, 0.0)])
    y += (0.5 * grains + 0.06 * rus) * shower_env
    return y


def sfx_torcida(r):
    n = n_of(2.2)
    t = tt(n)
    y = np.zeros(n)
    # vozes infantis 'eeeee!/aaaa!' (zumbido + formantes)
    voices = np.zeros(n)
    for i in range(14):
        f0 = r.uniform(290, 480)
        on = r.uniform(0.0, 0.45)
        d = r.uniform(1.0, 1.7)
        nn = n_of(min(d + 0.35, 2.2 - on))
        tl = tt(nn)
        cents = 250.0 * (1 - np.exp(-tl / 0.12)) - 250.0 + 30.0 * np.sin(TWO_PI * r.uniform(5, 7) * tl + r.random() * 6)
        cents += 40.0 * (smooth_random(r, nn, 6.0) - 0.5)
        ph = TWO_PI * np.cumsum(f0 * 2.0 ** (cents / 1200.0)) / SR + r.random() * TWO_PI
        v = np.zeros(nn)
        for k in range(1, 15):
            if k * f0 > 6000:
                break
            v += k ** -1.1 * np.sin(k * ph)
        v *= env_pts(nn, [(0, 0), (r.uniform(0.06, 0.15), 1.0), (d, 0.8), (d + 0.35, 0.0)])
        v *= smooth_random(r, nn, 7.0, 0.55, 1.0)
        add(voices, v, n_of(on), r.uniform(0.5, 1.0))
    voices = fft_filter(voices, lambda f: hp(f, 250, 2) * (0.08 + bp(f, 950.0, 0.35) + 0.8 * bp(f, 1750.0, 0.3) + 0.4 * bp(f, 3100.0, 0.3)))
    voices /= rms(voices)
    # 'murmurio' de ruido em bandas com modulacao aleatoria
    crowd = np.zeros(n)
    for fc, g in [(700.0, 1.0), (1400.0, 0.8), (3000.0, 0.45)]:
        b = fft_filter(r.standard_normal(n), lambda f, fc=fc: bp(f, fc, 0.45))
        crowd += g * b / rms(b) * smooth_random(r, n, 9.0, 0.3, 1.0)
    crowd /= rms(crowd)
    swell = env_pts(n, [(0, 0), (0.35, 1.0), (1.4, 0.9), (2.2, 0.0)])
    y += (0.5 * voices + 0.35 * crowd) * swell
    # apitos de embolo subindo
    for st, f_a, f_b in [(0.25, 700.0, 1700.0), (0.95, 800.0, 2000.0)]:
        nn = n_of(0.6)
        tl = tt(nn)
        u = np.clip(tl / 0.45, 0, 1)
        u = u * u * (3 - 2 * u)
        fw = f_a * (f_b / f_a) ** u * 2.0 ** (20.0 * np.sin(TWO_PI * 7.0 * tl) / 1200.0)
        ph = TWO_PI * np.cumsum(fw) / SR
        w = (np.sin(ph) + 0.06 * np.sin(2 * ph)) * env_pts(nn, [(0, 0), (0.03, 1), (0.48, 0.9), (0.6, 0)])
        add(y, w, n_of(st), 0.3)
    return y


def sfx_whoosh(r):
    n = n_of(0.45)
    t = tt(n)
    T = 0.45
    x = r.standard_normal(n)
    y = tv_filter(x, lambda f, tc: bp(f, 350.0 * 9.0 ** np.sin(np.pi * np.clip(tc / T, 0, 1)), 0.8)
                  + 0.25 * bp(f, 250.0, 1.0))
    y /= np.max(np.abs(y)) + 1e-9
    return y * np.sin(np.pi * np.clip(t / T, 0, 1)) ** 1.3


EFEITOS = [
    # (arquivo, funcao, duracao_s, fade_out_s, loop)
    ("bola_rolando.wav", sfx_bola_rolando, 2.0, 0.0, True),
    ("pino_batida_1.wav", lambda r: sfx_pino(r, 0), 0.35, 0.03, False),
    ("pino_batida_2.wav", lambda r: sfx_pino(r, 1), 0.35, 0.03, False),
    ("pino_batida_3.wav", lambda r: sfx_pino(r, 2), 0.35, 0.03, False),
    ("pinos_queda.wav", sfx_pinos_queda, 1.4, 0.15, False),
    ("strike.wav", sfx_strike, 2.2, 0.35, False),
    ("spare.wav", sfx_spare, 1.4, 0.3, False),
    ("boa.wav", sfx_boa, 0.8, 0.15, False),
    ("ops.wav", sfx_ops, 1.3, 0.08, False),
    ("boing.wav", sfx_boing, 0.5, 0.08, False),
    ("moeda.wav", sfx_moeda, 0.5, 0.05, False),
    ("start.wav", sfx_start, 0.9, 0.08, False),
    ("selecao.wav", sfx_selecao, 0.15, 0.03, False),
    ("escolha.wav", sfx_escolha, 0.7, 0.15, False),
    ("pop.wav", sfx_pop, 0.2, 0.04, False),
    ("brilho.wav", sfx_brilho, 0.7, 0.15, False),
    ("vez.wav", sfx_vez, 0.7, 0.15, False),
    ("tique.wav", sfx_tique, 0.1, 0.02, False),
    ("recorde.wav", sfx_recorde, 2.8, 0.4, False),
    ("fim.wav", sfx_fim, 2.6, 0.4, False),
    ("confete.wav", sfx_confete, 0.8, 0.1, False),
    ("torcida.wav", sfx_torcida, 2.2, 0.1, False),
    ("whoosh.wav", sfx_whoosh, 0.45, 0.03, False),
]


def normalize(x, peak_db=-1.0):
    return x * (10.0 ** (peak_db / 20.0) / (np.max(np.abs(x)) + 1e-12))


def finalizar_efeito(x, n, fout, loop):
    x = np.asarray(x, dtype=float)
    x = np.pad(x, (0, max(0, n - len(x))))[:n]
    hp20 = lambda f: hp(f, 20.0, 2)
    if loop:
        x = fft_filter(x, hp20, circular=True)  # filtro circular: emenda intacta
        x -= x.mean()
    else:
        x = fft_filter(x, hp20)
        x -= x.mean()
        x = fade(x, 0.0015, max(fout, 0.005))
    return normalize(x, -1.0)


def write_wav_mono(path, x):
    d = np.round(np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(d.tobytes())


def gerar_efeitos():
    for nome, fn, dur, fout, loop in EFEITOS:
        n = n_of(dur)
        x = finalizar_efeito(fn(rng(nome)), n, fout, loop)
        write_wav_mono(os.path.join(SAIDA, nome), x)
        print(f"  {nome:20s} {dur:5.2f} s")


# -----------------------------------------------------------------------------
# Musica: sequenciador simples com loop perfeito
# -----------------------------------------------------------------------------
class Song:
    def __init__(self, bpm, bars, tail=3.0):
        self.spb = 60.0 / bpm
        self.L = int(round(bars * 4 * self.spb * SR))
        self.T = n_of(tail)
        self.bus = {}

    def at(self, beat):
        return int(round(beat * self.spb * SR))

    def put(self, name, sig, beat, g=1.0, pan=0.0, r=None, jit_ms=0.0):
        if name not in self.bus:
            self.bus[name] = np.zeros((self.L + self.T, 2))
        pos = self.at(beat)
        if r is not None and jit_ms > 0 and beat > 0:
            pos += int(r.normal(0.0, jit_ms) * SR / 1000.0)
        add(self.bus[name], sig, max(0, pos), g, pan)

    def fold(self):
        """Dobra a cauda (decaimentos apos o fim) sobre o inicio do loop."""
        out = {}
        for k, v in self.bus.items():
            w = v[:self.L].copy()
            w[:self.T] += v[self.L:self.L + self.T]
            out[k] = w
        return out


def parse_bar(s):
    out = []
    for tok in s.split():
        b, nt, d = tok.split(":")
        out.append((float(b), nt, float(d)))
    return out


def chord_pcs(name):
    minor = name.endswith("m")
    root = _PC[name[:-1] if minor else name]
    return root, [root, (root + (3 if minor else 4)) % 12, (root + 7) % 12]


def pad_voicing(name, lo=55):
    _, pcs = chord_pcs(name)
    return sorted(lo + ((p - lo) % 12) for p in pcs)


def make_ir(r, secs=1.6, tau_lo=0.28, tau_hi=0.11, predelay=0.014):
    n = n_of(secs)
    t = tt(n)
    ir = np.zeros((n, 2))
    pd = n_of(predelay)
    for c in range(2):
        nz = r.standard_normal(n)
        lo = fft_filter(nz, lambda f: lp(f, 2500.0, 2))
        tail = lo * np.exp(-t / tau_lo) + (nz - lo) * np.exp(-t / tau_hi)
        tail *= np.minimum(1.0, t / 0.02)
        ch = np.zeros(n)
        ch[pd:] = tail[:n - pd]
        for _ in range(6):  # primeiras reflexoes
            d = n_of(r.uniform(0.005, 0.045))
            ch[d] += r.choice([-1.0, 1.0]) * r.uniform(0.3, 0.7) * np.sqrt(np.sum(tail[:n_of(0.05)] ** 2) / n_of(0.05))
        ir[:, c] = ch / np.sqrt(np.sum(ch ** 2))
    return ir


def circ_conv(x, h, L):
    H = np.fft.rfft(h, L)
    return np.fft.irfft(np.fft.rfft(x, L) * H, L)


def soft_limit(x, ceil=0.84, knee=0.62):
    a = np.abs(x)
    span = ceil - knee
    y = x.copy()
    m = a > knee
    y[m] = np.sign(x[m]) * (knee + span * np.tanh((a[m] - knee) / span))
    return y


def mixdown(song, r, gains, sends, wet=0.3, delay_bus=None, delay_beats=0.75, delay_fb=0.22,
            target_rms_db=-16.0, label=""):
    buses = song.fold()
    L = song.L
    dry = np.zeros((L, 2))
    send = np.zeros(L)
    info = []
    for k, v in buses.items():
        v = v * gains.get(k, 1.0)
        buses[k] = v
        dry += v
        send += v.mean(axis=1) * sends.get(k, 0.0)
        info.append((k, 20 * np.log10(rms(v) + 1e-12)))
    ir = make_ir(r)
    rev = np.stack([circ_conv(send, ir[:, c], L) for c in range(2)], axis=1)
    mix = dry + wet * rev
    if delay_bus in buses:
        d = song.at(delay_beats)
        m = buses[delay_bus].mean(axis=1)
        dl = np.zeros((L, 2))
        for i in range(1, 4):  # eco ping-pong: taps alternando L/R
            tap = np.roll(m, i * d) * delay_fb * 0.5 ** (i - 1)
            dl[:, i % 2] += 0.85 * tap
            dl[:, (i + 1) % 2] += 0.15 * tap
        mix += fft_filter(dl, lambda f: lp(f, 3500.0, 2) * hp(f, 300.0, 1), circular=True)
    mix = fft_filter(mix, lambda f: hp(f, 25.0, 2), circular=True)
    mix -= mix.mean(axis=0)
    mix *= 10.0 ** (target_rms_db / 20.0) / rms(mix)
    over = float(np.mean(np.abs(mix) > 0.62)) * 100
    mix = soft_limit(mix)
    print(f"  [{label}] barramentos (dB RMS): " + ", ".join(f"{k} {v:.1f}" for k, v in sorted(info, key=lambda z: -z[1])))
    print(f"  [{label}] RMS final {20 * np.log10(rms(mix)):.1f} dBFS, pico {20 * np.log10(np.max(np.abs(mix))):.2f} dBFS, "
          f"amostras no limitador {over:.3f}%")
    return mix


def encode_ogg(path, x):
    d = np.round(np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "2",
           "-i", "pipe:0", "-c:a", "libvorbis", "-q:a", "4", path]
    subprocess.run(cmd, input=d.tobytes(), check=True)


def _drum_bank(r, k=4):
    return {
        "kick": [kick(r) for _ in range(k)],
        "snare": [snare(r) for _ in range(k)],
        "clap": [clap(r) for _ in range(k)],
        "hat": [hat(r) for _ in range(k)],
        "ohat": [hat(r, tau=0.13, dur=0.45) for _ in range(k)],
        "shaker": [shaker(r) for _ in range(k)],
        "crash": [crash(r, 2.5, tau=0.7)],
    }


def _pick(r, lst):
    return lst[int(r.integers(len(lst)))]


def _pad_cached(cache, r, m, dur):
    key = (m, round(dur, 4))
    if key not in cache:
        cache[key] = pad_note(float(mtof(m)), dur, att=0.3, rel=0.6, r=r)
    return cache[key]


# ---- 1) Menu: 120 BPM, 16 compassos, C maior -------------------------------
def musica_menu():
    r = rng("musica_menu")
    s = Song(120, 16)
    db = _drum_bank(r)
    pc = {}
    chords = ["C", "G", "Am", "F", "C", "G", "Am", "F", "F", "G", "Em", "Am", "F", "G", "C", "G"]
    A1 = "0:E5:.5 .5:G5:.5 1:C6:.75 2:B5:.5 2.5:C6:.5 3:G5:1"
    A2 = "0:B5:.5 .5:A5:.5 1:G5:.5 1.5:D5:.5 2:G5:1.5 3.5:G5:.5"
    A3 = "0:A5:.5 .5:C6:.5 1:E6:.75 2:D6:.5 2.5:C6:.5 3:A5:1"
    mel = [A1, A2, A3,
           "0:F5:.5 .5:A5:.5 1:C6:.5 1.5:A5:.5 2:A5:1 3:G5:1",
           A1, A2, A3,
           "0:A5:.5 .5:G5:.5 1:F5:.5 1.5:E5:.5 2:F5:.5 2.5:A5:.5 3:C6:1",
           "0:A5:.5 .5:C6:.5 1:F6:1 2:E6:.5 2.5:D6:.5 3:C6:1",
           "0:B5:.5 .5:D6:.5 1:G6:1 2:F6:.5 2.5:E6:.5 3:D6:1",
           "0:G5:.5 .5:B5:.5 1:E6:.5 1.5:D6:.5 2:B5:.5 2.5:G5:.5 3:B5:1",
           "0:C6:.5 .5:B5:.5 1:A5:1 2:E5:.5 2.5:A5:.5 3:C6:1",
           "0:A5:.5 .5:C6:.5 1:F6:.75 2:E6:.5 2.5:C6:.5 3:A5:1",
           "0:B5:.5 .5:D6:.5 1:G6:.75 2:F6:.5 2.5:D6:.5 3:B5:1",
           "0:C6:.5 .5:E6:.5 1:G6:.5 1.5:E6:.5 2:C6:1 3:G5:.5 3.5:C6:.5",
           "0:D6:.5 .5:B5:.5 1:G5:.5 1.5:B5:.5 2:D6:1 3:G5:.5 3.5:D5:.5"]
    bass_pat = [(0, 0, .45), (1, 12, .3), (1.5, 0, .45), (2, 7, .45), (3, 12, .3), (3.5, 7, .4)]
    for bar in range(16):
        b0 = bar * 4
        root, pcs = chord_pcs(chords[bar])
        B = bar >= 8
        for beat, nt, d in parse_bar(mel[bar]):
            v = (1.0 if beat == int(beat) else 0.85) + r.uniform(-0.05, 0.05)
            s.put("lead", mallet(hz(nt), v, "marimba", r), b0 + beat, pan=-0.1, r=r, jit_ms=3)
            if B:
                s.put("lead2", mallet(hz(nt) * 2, 0.5 * v, "xylo", r), b0 + beat, pan=0.25, r=r, jit_ms=3)
        R = 36 + root
        for off, iv, d in bass_pat:
            s.put("bass", bass_pluck(float(mtof(R + iv)), d * s.spb, 1.0 if off == 0 else 0.8), b0 + off, r=r, jit_ms=2)
        for m in pad_voicing(chords[bar]):
            s.put("pad", _pad_cached(pc, r, m, 4 * s.spb), b0)
        # bateria
        kicks = [0, 2] + ([2.5] if bar % 2 == 1 else [])
        for k in kicks:
            s.put("kick", _pick(r, db["kick"]), b0 + k, 1.0 if k == 0 else 0.85)
        sn = [1, 3] if bar != 15 else [1, 2.5, 3, 3.25, 3.5, 3.75]
        for k in sn:
            v = 1.0 if k in (1, 3) else 0.5 + 0.15 * (k - 2.5) / 0.25
            s.put("snare", _pick(r, db["snare"]), b0 + k, min(1.0, v), r=r, jit_ms=2)
            if B and k in (1, 3):
                s.put("clap", _pick(r, db["clap"]), b0 + k, 1.0, pan=0.15, r=r, jit_ms=3)
        ohat = bar % 4 == 3
        for e in range(8):
            if ohat and e == 7:
                s.put("ohat", _pick(r, db["ohat"]), b0 + 3.5, 1.0, pan=0.3)
                continue
            s.put("hats", _pick(r, db["hat"]), b0 + e * 0.5, (1.0 if e % 2 else 0.6) * r.uniform(0.85, 1.0), pan=0.3, r=r, jit_ms=2)
        if bar in (0, 8):
            s.put("crash", db["crash"][0], b0, 1.0, pan=-0.3)
        # brilhos de glockenspiel
        nsp = (2 if B else 1)
        for _ in range(nsp):
            pos = _pick(r, [0.5, 1.5, 2.5, 3.5, 3.0, 1.0]) if B else 3.5
            m = 84 + _pick(r, pcs) + (12 if r.random() < 0.3 else 0)
            s.put("glock", glock(float(mtof(m)), r.uniform(0.6, 1.0), r), b0 + pos, pan=r.uniform(-0.6, 0.6))
        # arpejo de apoio na parte B
        if B:
            tones = [72 + p if 72 + p < 81 else 60 + p for p in pcs]
            tones = sorted(tones)
            seq = tones + [tones[0] + 12] + tones[::-1][:3] + [tones[1]]
            for e in range(8):
                s.put("arp", sq_pluck(float(mtof(seq[e % len(seq)])), 1.0 if e % 2 == 0 else 0.75), b0 + e * 0.5, pan=0.4)
    gains = {"lead": 0.46, "lead2": 0.24, "bass": 0.7, "pad": 0.145, "kick": 0.84, "snare": 0.45, "clap": 0.27,
             "hats": 0.2, "ohat": 0.18, "crash": 0.22, "glock": 0.13, "arp": 0.095}
    sends = {"lead": 0.35, "lead2": 0.5, "pad": 0.5, "glock": 0.7, "snare": 0.25, "clap": 0.3, "arp": 0.4,
             "hats": 0.05, "crash": 0.2}
    return mixdown(s, r, gains, sends, wet=0.3, delay_bus="lead", delay_beats=0.75, target_rms_db=-16.0, label="menu")


# ---- 2) Jogo: 112 BPM, 16 compassos, F maior, mais leve --------------------
def musica_jogo():
    r = rng("musica_jogo")
    s = Song(112, 16)
    db = _drum_bank(r)
    pc = {}
    chords = ["F", "C", "Dm", "Bb", "F", "C", "Dm", "Bb", "Bb", "C", "Am", "Dm", "Gm", "C", "F", "C"]
    A1 = "0:A5:1 1:C6:.5 1.5:A5:.5 2:F5:1.5"
    A2 = "0:G5:1 1:E5:.5 1.5:G5:.5 2:C6:1.5"
    A3 = "0:D6:1 1:C6:.5 1.5:A5:.5 2:F5:1 3:A5:1"
    mel = [A1, A2, A3, "0:F5:1 1:D5:.5 1.5:F5:.5 2:G5:2",
           A1, A2, A3, "0:F5:.5 .5:G5:.5 1:Bb5:1 2:D6:1 3:C6:1",
           "0:D6:1.5 1.5:C6:.5 2:Bb5:1 3:F5:1",
           "0:E6:1.5 1.5:D6:.5 2:C6:1 3:G5:1",
           "0:C6:1 1:E6:1 2:A5:2",
           "0:D6:1 1:F6:1 2:A5:1 3:C6:1",
           "0:Bb5:1 1:D6:.5 1.5:Bb5:.5 2:G5:2",
           "0:C6:1 1:E6:.5 1.5:C6:.5 2:G5:2",
           "0:A5:1 1:C6:1 2:F6:1.5",
           "0:E6:.5 .5:D6:.5 1:C6:1 2:E5:1 3:G5:1"]
    bass_pat = [(0, 0, .8), (1.5, 0, .4), (2, 7, .8), (3, 12, .4)]
    for bar in range(16):
        b0 = bar * 4
        root, pcs = chord_pcs(chords[bar])
        for beat, nt, d in parse_bar(mel[bar]):
            v = (1.0 if beat == int(beat) else 0.85) + r.uniform(-0.05, 0.05)
            s.put("lead", mallet(hz(nt), v, "marimba", r, tau_scale=1.2), b0 + beat, pan=-0.1, r=r, jit_ms=3)
        R = 36 + root
        for off, iv, d in bass_pat:
            s.put("bass", bass_pluck(float(mtof(R + iv)), d * s.spb, 1.0 if off == 0 else 0.75), b0 + off, r=r, jit_ms=2)
        for m in pad_voicing(chords[bar], lo=57):
            s.put("pad", _pad_cached(pc, r, m, 4 * s.spb), b0)
        s.put("kick", _pick(r, db["kick"]), b0, 1.0)
        s.put("kick", _pick(r, db["kick"]), b0 + 2, 0.8)
        s.put("clap", _pick(r, db["clap"]), b0 + 3, 1.0, pan=0.1, r=r, jit_ms=3)
        if bar % 2 == 1:
            s.put("snare", _pick(r, db["snare"]), b0 + 1, 0.6, r=r, jit_ms=3)
        for e in range(8):
            s.put("shaker", _pick(r, db["shaker"]), b0 + e * 0.5, (1.0 if e % 2 else 0.55) * r.uniform(0.85, 1.0), pan=0.35, r=r, jit_ms=3)
        if bar % 2 == 1:
            m = 84 + _pick(r, pcs)
            s.put("glock", glock(float(mtof(m)), r.uniform(0.7, 1.0), r), b0 + _pick(r, [2.5, 3.5]), pan=r.uniform(-0.5, 0.5))
        if bar == 0:
            s.put("crash", db["crash"][0], b0, 0.7, pan=-0.3)
    gains = {"lead": 0.42, "bass": 0.84, "pad": 0.15, "kick": 0.8, "snare": 0.2, "clap": 0.24,
             "shaker": 0.135, "glock": 0.15, "crash": 0.14}
    sends = {"lead": 0.4, "pad": 0.5, "glock": 0.7, "clap": 0.35, "snare": 0.3, "shaker": 0.05, "crash": 0.2}
    return mixdown(s, r, gains, sends, wet=0.3, delay_bus="lead", delay_beats=1.0, delay_fb=0.18,
                   target_rms_db=-19.2, label="jogo")


# ---- 3) Fim/resultados: 126 BPM, 8 compassos, G maior, festivo -------------
def musica_fim():
    r = rng("musica_fim")
    s = Song(126, 8)
    db = _drum_bank(r)
    pc = {}
    chords = ["G", "C", "D", "G", "Em", "C", "Am", "D"]
    mel = ["0:G5:.5 .5:B5:.5 1:D6:.5 1.5:B5:.5 2:G6:1 3:D6:.5 3.5:B5:.5",
           "0:C6:.5 .5:E6:.5 1:G6:.75 2:E6:.5 2.5:C6:.5 3:E6:1",
           "0:D6:.5 .5:F#6:.5 1:A6:.75 2:F#6:.5 2.5:D6:.5 3:A5:1",
           "0:B5:.5 .5:D6:.5 1:G6:1 2:D6:.5 2.5:B5:.5 3:G5:1",
           "0:B5:.5 .5:E6:.5 1:G6:.75 2:F#6:.5 2.5:E6:.5 3:B5:1",
           "0:C6:.5 .5:E6:.5 1:G6:.75 2:A6:.5 2.5:G6:.5 3:E6:1",
           "0:C6:.5 .5:E6:.5 1:A6:.5 1.5:G6:.5 2:E6:.5 2.5:C6:.5 3:A5:1",
           "0:F#6:.5 .5:E6:.5 1:D6:.5 1.5:C6:.5 2:A5:.5 2.5:F#5:.5 3:A5:.5 3.5:F#5:.5"]
    bass_pat = [(0, 0), (0.5, 12), (1, 0), (1.5, 12), (2, 0), (2.5, 12), (3, 7), (3.5, 12)]
    for bar in range(8):
        b0 = bar * 4
        root, pcs = chord_pcs(chords[bar])
        for beat, nt, d in parse_bar(mel[bar]):
            v = (1.0 if beat == int(beat) else 0.85) + r.uniform(-0.05, 0.05)
            s.put("lead", mallet(hz(nt), v, "xylo", r), b0 + beat, pan=-0.05, r=r, jit_ms=2)
            s.put("lead_low", mallet(hz(nt) / 2, v, "marimba", r), b0 + beat, pan=-0.2, r=r, jit_ms=2)
        R = 36 + root if root < 7 else 24 + root
        for off, iv in bass_pat:
            s.put("bass", bass_pluck(float(mtof(R + iv)), 0.38 * s.spb, 1.0 if off == 0 else 0.8), b0 + off, r=r, jit_ms=2)
        voic = pad_voicing(chords[bar], lo=60)
        stabs = [1.5, 3.5] + ([3.0] if bar in (3, 7) else [])
        for st in stabs:
            for m in voic:
                s.put("brass", brass(float(mtof(m)), 0.28 * s.spb + 0.05, r=r, rel=0.08, scoop=20), b0 + st, pan=0.2)
        for m in pad_voicing(chords[bar], lo=55):
            s.put("pad", _pad_cached(pc, r, m, 4 * s.spb), b0)
        for k in range(4):
            s.put("kick", _pick(r, db["kick"]), b0 + k, 1.0 if k in (0, 2) else 0.85)
        sn = [1, 3] if bar != 7 else [1, 3, 3.25, 3.5, 3.75]
        for k in sn:
            s.put("snare", _pick(r, db["snare"]), b0 + k, 1.0 if k in (1, 3) else 0.6, r=r, jit_ms=2)
            if k in (1, 3):
                s.put("clap", _pick(r, db["clap"]), b0 + k, 1.0, pan=0.15, r=r, jit_ms=3)
        for e in range(8):
            if e == 7 and bar % 2 == 1:
                s.put("ohat", _pick(r, db["ohat"]), b0 + 3.5, 1.0, pan=0.3)
                continue
            s.put("hats", _pick(r, db["hat"]), b0 + e * 0.5, (1.0 if e % 2 else 0.6) * r.uniform(0.85, 1.0), pan=0.3, r=r, jit_ms=2)
        if bar in (0, 4):
            s.put("crash", db["crash"][0], b0, 1.0, pan=-0.3)
        for _ in range(2):
            m = 84 + _pick(r, pcs) + (12 if r.random() < 0.35 else 0)
            s.put("glock", glock(float(mtof(m)), r.uniform(0.6, 1.0), r), b0 + _pick(r, [0.5, 1.5, 2.5, 3.5, 1.0, 3.0]), pan=r.uniform(-0.6, 0.6))
    gains = {"lead": 0.42, "lead_low": 0.3, "bass": 0.6, "brass": 0.11, "pad": 0.1, "kick": 0.7, "snare": 0.37,
             "clap": 0.2, "hats": 0.22, "ohat": 0.18, "crash": 0.16, "glock": 0.12}
    sends = {"lead": 0.35, "lead_low": 0.2, "brass": 0.3, "pad": 0.5, "glock": 0.7, "snare": 0.25, "clap": 0.3,
             "hats": 0.05, "crash": 0.2}
    return mixdown(s, r, gains, sends, wet=0.28, delay_bus="lead", delay_beats=0.75, delay_fb=0.18,
                   target_rms_db=-16.0, label="fim")


MUSICAS = [
    ("musica_menu.ogg", musica_menu),
    ("musica_jogo.ogg", musica_jogo),
    ("musica_fim.ogg", musica_fim),
]


def gerar_musicas():
    for nome, fn in MUSICAS:
        t0 = time.time()
        x = fn()
        encode_ogg(os.path.join(SAIDA, nome), x)
        print(f"  {nome:20s} {len(x) / SR:6.2f} s  ({time.time() - t0:.1f} s para gerar)")


def main():
    ap = argparse.ArgumentParser(description="Gera os sons do STRIKE KIDS")
    ap.add_argument("--so-efeitos", action="store_true")
    ap.add_argument("--so-musicas", action="store_true")
    a = ap.parse_args()
    os.makedirs(SAIDA, exist_ok=True)
    print(f"Saida: {SAIDA}")
    if not a.so_musicas:
        print("Efeitos:")
        gerar_efeitos()
    if not a.so_efeitos:
        print("Musicas:")
        gerar_musicas()
    print("Pronto.")


if __name__ == "__main__":
    sys.exit(main())
