# -*- coding: utf-8 -*-
"""
ARTES 2D DO STRIKE KIDS
=======================

Gera, com Pillow, todas as imagens do jogo:
  * rostos (atlas de expressões) do Léo, da Lia e dos pinos;
  * texturas: madeira da pista, bolas, sombra redonda, brilhos, confete;
  * letreiros ("STRIKE!", "SPARE!"...), painéis, ícones, logo, splash.

Uso (na pasta do projeto):
    python3 tools/arte/gerar_arte.py            # tudo
    python3 tools/arte/gerar_arte.py rostos     # só uma parte

Tudo é desenhado em tamanho 4x e reduzido (bordas lisas).
"""
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEX = os.path.join(RAIZ, "texturas")
UI = os.path.join(RAIZ, "ui")
FONTES = os.path.join(RAIZ, "fontes")
os.makedirs(TEX, exist_ok=True)
os.makedirs(UI, exist_ok=True)

SS = 4  # super-amostragem
ESCALA_UI = 1.6   # letreiros e logo em 1,6x (nítidos em telas 4K); o HUD divide por isso


def cor(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def reduzir(img, tamanho):
    return img.resize(tamanho, Image.LANCZOS)


def elipse(d, cx, cy, rx, ry, **kw):
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], **kw)


def fonte(nome, tam):
    return ImageFont.truetype(os.path.join(FONTES, nome), tam)


# =====================================================================
# ROSTOS
# =====================================================================
# Cada célula do atlas cobre o retângulo do rosto (ver modelos.py: rosto
# centro/tamanho). Coordenadas em fração da célula (0..1).

EXPR_PERSONAGEM = ["feliz", "piscando", "empolgado", "triste", "concentrado", "surpreso", "risada", "piscadinha"]
EXPR_PINO = ["normal", "piscando", "medo", "tonto", "feliz", "surpreso", "triste", "bravo"]


class Rosto:
    def __init__(self, celula, iris, sobrancelha, boca_borda="#3A1420", cilios=False, bochecha="#FF7A9A",
                 olho_x=0.215, olho_y=0.455, olho_rx=0.094, olho_ry=0.132, boca_y=0.71, boca_l=0.2,
                 bochecha_x=0.36, bochecha_y=0.64, sobr_y=0.25, bicho=False, gato=False, nariz_y=0.62):
        self.bicho = bicho
        self.gato = gato
        self.nariz_y = nariz_y
        self.c = celula
        self.iris = iris
        self.sobr = sobrancelha
        self.boca_borda = boca_borda
        self.cilios = cilios
        self.bochecha = bochecha
        self.ox, self.oy, self.orx, self.ory = olho_x, olho_y, olho_rx, olho_ry
        self.by, self.bl = boca_y, boca_l
        self.bx, self.byc = bochecha_x, bochecha_y
        self.sy = sobr_y

    def P(self, u, v):
        return u * self.c, v * self.c

    def L(self, f):
        return f * self.c


def desenhar_olho(d, R, cx, cy, tipo="aberto", lado=1, escala=1.0, olhar=(0.0, 0.0)):
    c = R.c
    rx, ry = R.L(R.orx) * escala, R.L(R.ory) * escala
    contorno = cor("#22101C")
    if tipo == "fechado":  # arco feliz "^"
        w = max(2, int(R.L(0.022)))
        d.arc([cx - rx, cy - ry * 0.55, cx + rx, cy + ry * 0.75], 200, 340, fill=contorno, width=w)
        return
    if tipo == "fechado_baixo":  # piscando (arco para baixo)
        w = max(2, int(R.L(0.02)))
        d.arc([cx - rx, cy - ry * 0.9, cx + rx, cy + ry * 0.35], 20, 160, fill=contorno, width=w)
        if R.cilios:
            for k in range(3):
                a = math.radians(30 + k * 20) if lado > 0 else math.radians(150 - k * 20)
                x0 = cx + math.cos(a) * rx * (1 if lado > 0 else 1)
                y0 = cy - ry * 0.25 + math.sin(a) * ry * 0.6
                d.line([x0, y0, x0 + lado * R.L(0.02), y0 + R.L(0.02)], fill=contorno, width=w)
        return
    if tipo == "x":  # tonto
        w = max(2, int(R.L(0.03)))
        k = rx * 0.75
        d.line([cx - k, cy - k, cx + k, cy + k], fill=contorno, width=w)
        d.line([cx - k, cy + k, cx + k, cy - k], fill=contorno, width=w)
        return
    if tipo == "espiral":
        w = max(2, int(R.L(0.018)))
        pts = []
        for i in range(60):
            t = i / 59 * 4 * math.pi
            r = rx * 0.9 * (i / 59)
            pts.append((cx + math.cos(t) * r, cy + math.sin(t) * r))
        d.line(pts, fill=contorno, width=w, joint="curve")
        return
    if R.bicho:
        # olho de bichinho: grande, escuro e brilhante (sem "branco do olho")
        elipse(d, cx, cy, rx, ry, fill=contorno)
        ix, iy = cx + olhar[0] * rx * 0.15, cy + olhar[1] * ry * 0.12
        elipse(d, ix, iy, rx * 0.86, ry * 0.9, fill=cor(R.iris))
        clara = tuple(min(255, int(v * 1.45 + 25)) for v in cor(R.iris)[:3]) + (255,)
        elipse(d, ix, iy + ry * 0.38, rx * 0.6, ry * 0.42, fill=clara)
        if R.gato:
            elipse(d, ix, iy + ry * 0.05, rx * 0.3, ry * 0.68, fill=cor("#140C10"))
        else:
            elipse(d, ix, iy + ry * 0.05, rx * 0.62, ry * 0.66, fill=cor("#140C10"))
        if tipo == "brilho":
            estrela(d, ix, iy + ry * 0.05, rx * 0.62, rx * 0.27, cor("#FFE14D"))
        elipse(d, ix - rx * 0.3, iy - ry * 0.36, rx * 0.36, ry * 0.3, fill=cor("#FFFFFF"))
        elipse(d, ix + rx * 0.32, iy + ry * 0.36, rx * 0.16, ry * 0.13, fill=cor("#FFFFFF"))
        elipse(d, ix + rx * 0.1, iy - ry * 0.55, rx * 0.09, ry * 0.07, fill=cor("#FFFFFF"))
        if R.cilios:
            w = max(2, int(R.L(0.014)))
            for k in range(2):
                a = -55 - k * 25 if lado > 0 else -125 + k * 25
                ar = math.radians(a)
                x0 = cx + math.cos(ar) * rx * 0.95
                y0 = cy + math.sin(ar) * ry * 0.95
                d.line([x0, y0, cx + math.cos(ar) * rx * 1.3, cy + math.sin(ar) * ry * 1.22], fill=contorno, width=w)
        return
    # olho aberto: contorno, branco pequeno, íris grande, brilhos
    elipse(d, cx, cy, rx, ry, fill=contorno)
    elipse(d, cx, cy, rx * 0.86, ry * 0.9, fill=cor("#FFFFFF"))
    ix, iy = cx + olhar[0] * rx * 0.25, cy + olhar[1] * ry * 0.2 + ry * 0.08
    elipse(d, ix, iy, rx * 0.74, ry * 0.76, fill=cor(R.iris))
    # degradê da íris (mais clara embaixo)
    clara = tuple(min(255, int(v * 1.35 + 30)) for v in cor(R.iris)[:3]) + (255,)
    elipse(d, ix, iy + ry * 0.3, rx * 0.5, ry * 0.36, fill=clara)
    elipse(d, ix, iy, rx * 0.38, ry * 0.42, fill=cor("#180A12"))
    elipse(d, ix - rx * 0.28, iy - ry * 0.32, rx * 0.26, ry * 0.24, fill=cor("#FFFFFF"))
    elipse(d, ix + rx * 0.25, iy + ry * 0.3, rx * 0.12, ry * 0.11, fill=cor("#FFFFFF"))
    if tipo == "brilho":  # olhinhos de estrela
        estrela(d, ix + rx * 0.05, iy - ry * 0.05, rx * 0.55, rx * 0.24, cor("#FFE14D"))
        elipse(d, ix - rx * 0.28, iy - ry * 0.32, rx * 0.16, ry * 0.15, fill=cor("#FFFFFF"))
    if R.cilios:
        w = max(2, int(R.L(0.016)))
        for k in range(3):
            a = -60 - k * 22 if lado > 0 else -120 + k * 22
            ar = math.radians(a)
            x0 = cx + math.cos(ar) * rx * 0.95
            y0 = cy + math.sin(ar) * ry * 0.95
            x1 = cx + math.cos(ar) * rx * 1.35
            y1 = cy + math.sin(ar) * ry * 1.25
            d.line([x0, y0, x1, y1], fill=contorno, width=w)


def estrela(d, cx, cy, r_ext, r_int, fill, pontas=5, giro=0.0):
    pts = []
    for i in range(pontas * 2):
        r = r_ext if i % 2 == 0 else r_int
        a = -math.pi / 2 + giro + i * math.pi / pontas
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    d.polygon(pts, fill=fill)


def sobrancelha(d, R, cx, cy, inclinacao, lado, curva=0.0):
    w = int(R.L(0.032))
    L = R.L(0.09)
    pts = []
    for i in range(9):
        t = (i / 8 - 0.5)
        x = cx + t * L
        y = cy + lado * t * inclinacao * L - curva * L * (0.25 - t * t)
        pts.append((x, y))
    d.line(pts, fill=cor(R.sobr), width=w, joint="curve")
    elipse(d, pts[0][0], pts[0][1], w / 2, w / 2, fill=cor(R.sobr))
    elipse(d, pts[-1][0], pts[-1][1], w / 2, w / 2, fill=cor(R.sobr))


def boca(d, R, tipo):
    cx, cy = R.P(0.5, R.by)
    L = R.L(R.bl)
    borda = cor(R.boca_borda)
    w = max(2, int(R.L(0.022)))
    interior = cor("#7A1E33")
    lingua = cor("#FF7A8C")
    if tipo == "sorriso_aberto":
        bb = [cx - L * 0.55, cy - L * 0.32, cx + L * 0.55, cy + L * 0.55]
        d.chord(bb, 0, 180, fill=borda)
        bb2 = [bb[0] + w, bb[1] + w * 0.6, bb[2] - w, bb[3] - w]
        d.chord(bb2, 0, 180, fill=interior)
        elipse(d, cx, cy + L * 0.33, L * 0.26, L * 0.13, fill=lingua)
        d.rectangle([cx - L * 0.4, cy - L * 0.02, cx + L * 0.4, cy + L * 0.06], fill=cor("#FFFFFF"))
        d.line([bb[0] + w * 0.5, cy + w * 0.3, bb[2] - w * 0.5, cy + w * 0.3], fill=borda, width=w)
    elif tipo == "sorriso":
        d.arc([cx - L * 0.45, cy - L * 0.45, cx + L * 0.45, cy + L * 0.3], 20, 160, fill=borda, width=w)
    elif tipo == "grande":  # empolgado / risada
        bb = [cx - L * 0.62, cy - L * 0.38, cx + L * 0.62, cy + L * 0.78]
        d.chord(bb, 0, 180, fill=borda)
        bb2 = [bb[0] + w, bb[1] + w * 0.6, bb[2] - w, bb[3] - w]
        d.chord(bb2, 0, 180, fill=interior)
        elipse(d, cx, cy + L * 0.52, L * 0.32, L * 0.17, fill=lingua)
        d.rectangle([cx - L * 0.5, cy - L * 0.02, cx + L * 0.5, cy + L * 0.08], fill=cor("#FFFFFF"))
        d.line([bb[0] + w * 0.5, cy + w * 0.3, bb[2] - w * 0.5, cy + w * 0.3], fill=borda, width=w)
    elif tipo == "o":
        elipse(d, cx, cy + L * 0.08, L * 0.2, L * 0.26, fill=borda)
        elipse(d, cx, cy + L * 0.08, L * 0.2 - w, L * 0.26 - w, fill=interior)
        elipse(d, cx, cy + L * 0.22, L * 0.1, L * 0.06, fill=lingua)
    elif tipo == "triste":
        pts = []
        for i in range(17):
            t = i / 16 - 0.5
            pts.append((cx + t * L * 0.85, cy + L * 0.12 + math.sin(t * math.pi * 3) * L * 0.05 + t * t * L * 0.25 * -1 + L * 0.03))
        d.line(pts, fill=borda, width=w, joint="curve")
    elif tipo == "ondulada":  # medo
        pts = []
        for i in range(21):
            t = i / 20 - 0.5
            pts.append((cx + t * L * 0.9, cy + L * 0.1 + math.sin(t * math.pi * 5) * L * 0.07))
        d.line(pts, fill=borda, width=w, joint="curve")
    elif tipo == "lingua":  # piscadinha
        d.arc([cx - L * 0.45, cy - L * 0.45, cx + L * 0.45, cy + L * 0.3], 15, 165, fill=borda, width=w)
        elipse(d, cx + L * 0.12, cy + L * 0.33, L * 0.13, L * 0.15, fill=borda)
        elipse(d, cx + L * 0.12, cy + L * 0.33, L * 0.13 - w * 0.8, L * 0.15 - w * 0.8, fill=lingua)
        d.line([cx + L * 0.12, cy + L * 0.25, cx + L * 0.12, cy + L * 0.42], fill=cor("#E0566E"), width=max(1, w // 2))
    elif tipo == "reta":
        d.line([cx - L * 0.25, cy + L * 0.1, cx + L * 0.25, cy + L * 0.06], fill=borda, width=w)
    elif tipo == "bravo":
        d.arc([cx - L * 0.35, cy + L * 0.05, cx + L * 0.35, cy + L * 0.55], 200, 340, fill=borda, width=w)


def boca_bicho(d, R, tipo):
    """Boquinha de bichinho: risquinho do nariz + "ω", aberta quando feliz."""
    cx = R.c * 0.5
    cy = R.P(0.5, R.by)[1]
    L = R.L(R.bl)
    borda = cor(R.boca_borda)
    w = max(2, int(R.L(0.017)))
    interior = cor("#7A1E33")
    lingua = cor("#FF7A8C")
    ny = R.P(0.5, R.nariz_y)[1]

    def omega(y, abre=1.0):
        d.line([cx, ny, cx, y], fill=borda, width=w)
        for s in (-1, 1):
            d.arc([cx + (s - 1) * L * 0.27 if s > 0 else cx - L * 0.54, y - L * 0.22 * abre,
                   cx + L * 0.54 if s > 0 else cx, y + L * 0.22 * abre], 0, 180, fill=borda, width=w)

    if tipo in ("sorriso", "reta"):
        omega(cy - L * 0.12)
    elif tipo == "sorriso_aberto":
        omega(cy - L * 0.18)
        bb = [cx - L * 0.25, cy - L * 0.05, cx + L * 0.25, cy + L * 0.38]
        d.chord(bb, 0, 180, fill=borda)
        d.chord([bb[0] + w, bb[1] + w * 0.5, bb[2] - w, bb[3] - w], 0, 180, fill=interior)
        elipse(d, cx, cy + L * 0.24, L * 0.13, L * 0.08, fill=lingua)
    elif tipo == "grande":
        omega(cy - L * 0.2)
        bb = [cx - L * 0.36, cy - L * 0.1, cx + L * 0.36, cy + L * 0.6]
        d.chord(bb, 0, 180, fill=borda)
        d.chord([bb[0] + w, bb[1] + w * 0.5, bb[2] - w, bb[3] - w], 0, 180, fill=interior)
        elipse(d, cx, cy + L * 0.4, L * 0.18, L * 0.1, fill=lingua)
    elif tipo == "o":
        d.line([cx, ny, cx, cy - L * 0.12], fill=borda, width=w)
        elipse(d, cx, cy + L * 0.08, L * 0.12, L * 0.15, fill=borda)
        elipse(d, cx, cy + L * 0.08, L * 0.12 - w, L * 0.15 - w, fill=interior)
    elif tipo == "triste":
        d.line([cx, ny, cx, cy - L * 0.05], fill=borda, width=w)
        d.arc([cx - L * 0.3, cy - L * 0.02, cx + L * 0.3, cy + L * 0.3], 200, 340, fill=borda, width=w)
    elif tipo == "lingua":
        omega(cy - L * 0.12)
        elipse(d, cx + L * 0.12, cy + L * 0.12, L * 0.1, L * 0.12, fill=borda)
        elipse(d, cx + L * 0.12, cy + L * 0.12, L * 0.1 - w * 0.8, L * 0.12 - w * 0.8, fill=lingua)
    elif tipo == "ondulada":
        pts = []
        for i in range(17):
            t = i / 16 - 0.5
            pts.append((cx + t * L * 0.7, cy + math.sin(t * math.pi * 4) * L * 0.06))
        d.line(pts, fill=borda, width=w, joint="curve")
    else:
        omega(cy - L * 0.12)


def bigodes(d, R):
    w = max(2, int(R.L(0.009)))
    for s in (-1, 1):
        for k in range(3):
            x0 = R.c * (0.5 + s * 0.17)
            y0 = R.c * (R.by - 0.03 + k * 0.035)
            x1 = R.c * (0.5 + s * 0.42)
            y1 = y0 + R.c * (-0.04 + k * 0.04)
            d.line([x0, y0, (x0 + x1) / 2, (y0 + y1) / 2 - R.c * 0.008, x1, y1], fill=cor("#6E7488", 200), width=w, joint="curve")


def bochechas(d, R, forte=1.0):
    for s in (-1, 1):
        cx, cy = R.P(0.5 + s * R.bx, R.byc)
        rx, ry = R.L(0.075), R.L(0.045)
        camada = Image.new("RGBA", (R.c, R.c), (0, 0, 0, 0))
        dc = ImageDraw.Draw(camada)
        c = cor(R.bochecha, int(150 * forte))
        elipse(dc, cx, cy, rx, ry, fill=c)
        camada = camada.filter(ImageFilter.GaussianBlur(R.L(0.012)))
        d._image.alpha_composite(camada)


def desenhar_rosto(R, expr):
    img = Image.new("RGBA", (R.c, R.c), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d._image = img
    oxe, oxd = 0.5 + R.ox, 0.5 - R.ox  # e = esquerda do personagem (direita da imagem)
    oy = R.oy
    sy = R.sy
    olhos = {"feliz": ("aberto", "aberto"), "piscando": ("fechado_baixo", "fechado_baixo"),
             "empolgado": ("brilho", "brilho"), "triste": ("aberto", "aberto"), "concentrado": ("aberto", "aberto"),
             "surpreso": ("aberto", "aberto"), "risada": ("fechado", "fechado"), "piscadinha": ("aberto", "fechado"),
             "normal": ("aberto", "aberto"), "medo": ("aberto", "aberto"), "tonto": ("espiral", "x"), "bravo": ("aberto", "aberto")}[expr]
    escala = {"surpreso": 1.12, "medo": 1.15, "empolgado": 1.08, "concentrado": 0.95, "triste": 1.0}.get(expr, 1.0)
    olhar = {"triste": (0.0, 0.6), "medo": (0.0, -0.3), "concentrado": (0.0, -0.4)}.get(expr, (0.0, 0.0))
    bochechas(d, R, 1.3 if expr in ("empolgado", "risada", "feliz") else 0.9)
    if R.sobr:
        incl = {"triste": -0.35, "medo": -0.45, "concentrado": 0.35, "bravo": 0.55, "surpreso": 0.0}.get(expr, 0.0)
        curva = {"surpreso": 0.6, "empolgado": 0.5, "feliz": 0.35, "risada": 0.4, "piscadinha": 0.3}.get(expr, 0.15)
        dy = {"surpreso": -0.045, "empolgado": -0.03, "medo": -0.03}.get(expr, 0.0)
        for s, ux in ((1, oxe), (-1, oxd)):
            cx, cy = R.P(ux, sy + dy)
            sobrancelha(d, R, cx, cy, incl, s, curva)
    for (lado, ux), tipo in zip(((1, oxe), (-1, oxd)), olhos):
        cx, cy = R.P(ux, oy)
        desenhar_olho(d, R, cx, cy, tipo, lado, escala, olhar)
    tipo_boca = {"feliz": "sorriso_aberto", "piscando": "sorriso", "empolgado": "grande", "triste": "triste",
                 "concentrado": "reta", "surpreso": "o", "risada": "grande", "piscadinha": "lingua",
                 "normal": "sorriso", "medo": "ondulada", "tonto": "ondulada", "bravo": "bravo"}[expr]
    if R.bicho:
        if R.gato:
            bigodes(d, R)
        boca_bicho(d, R, tipo_boca)
    else:
        boca(d, R, tipo_boca)
    if expr == "triste":  # lagriminha
        cx, cy = R.P(oxd, oy + 0.1)
        d.polygon([(cx, cy - R.L(0.03)), (cx - R.L(0.022), cy + R.L(0.02)), (cx + R.L(0.022), cy + R.L(0.02))], fill=cor("#7FD3FF"))
        elipse(d, cx, cy + R.L(0.022), R.L(0.023), R.L(0.023), fill=cor("#7FD3FF"))
    if expr == "medo":  # gota de suor
        cx, cy = R.P(0.5 + 0.38, 0.22)
        d.polygon([(cx, cy - R.L(0.04)), (cx - R.L(0.03), cy + R.L(0.02)), (cx + R.L(0.03), cy + R.L(0.02))], fill=cor("#9FE2FF"))
        elipse(d, cx, cy + R.L(0.025), R.L(0.03), R.L(0.03), fill=cor("#9FE2FF"))
    return img


# ---------------------------------------------------------------- rostos dos mascotes (v2)
# Desenho alinhado ao modelo 3D (tools/modelos/personagens.py): o rosto é
# projetado de frente na cabeça; a coordenada da imagem vem da altura no
# mundo (y) e da distância ao centro (x), em metros.
CABECA_PESCOCO_Y = 0.635
ROSTO_CENTRO_Y = 0.205
ROSTO_TAM = (0.46, 0.40)


def uv_rosto(x, y_mundo):
    """(x em metros, y no mundo) -> (u, v) 0..1 na célula do rosto."""
    u = 0.5 + x / ROSTO_TAM[0]
    v = 0.5 - (y_mundo - CABECA_PESCOCO_Y - ROSTO_CENTRO_Y) / ROSTO_TAM[1]
    return u, v


MASCOTES = {
    "bob": dict(olho_x=0.09, olho_y=0.878, olho_rx=0.038, olho_ry=0.049, olho="#2A1814", iris="#6A3E22",
                sobr="#A2602C", pelo="#E9A55B", nariz_baixo=0.789, boca_y=0.768, boca_l=0.068, bochecha=(0.13, 0.818),
                cilios=False, bigode=False),
    "mia": dict(olho_x=0.092, olho_y=0.88, olho_rx=0.039, olho_ry=0.05, olho="#1A1420", iris="#2FB27E",
                sobr="#8A92AA", pelo="#C9CEDE", nariz_baixo=0.789, boca_y=0.768, boca_l=0.064, bochecha=(0.132, 0.818),
                cilios=True, bigode=True),
}


def desenhar_rosto_mascote(cfg, expr, C):
    """Rosto de pelúcia: olhos grandes e brilhantes (sem branco), sobrancelha
    curtinha, bochecha rosada, boquinha em "w" logo abaixo do nariz 3D."""
    img = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def P(x, y):
        u, v = uv_rosto(x, y)
        return u * C, v * C

    def M(m):   # metros -> pixels
        return m / ROSTO_TAM[0] * C

    escuro = cor(cfg["olho"])
    rx, ry = M(cfg["olho_rx"]), M(cfg["olho_ry"])
    escala = {"surpreso": 1.12, "empolgado": 1.1, "concentrado": 0.96}.get(expr, 1.0)
    rx, ry = rx * escala, ry * escala
    olhar_y = {"triste": 0.18, "concentrado": -0.05}.get(expr, 0.0)

    # bochechas (rosadas e macias)
    camada = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    dc = ImageDraw.Draw(camada)
    forca = 1.25 if expr in ("empolgado", "risada", "feliz", "piscadinha") else 0.9
    for s in (-1, 1):
        cx, cy = P(s * cfg["bochecha"][0], cfg["bochecha"][1])
        elipse(dc, cx, cy, M(0.034), M(0.021), fill=cor("#FF8FA6", int(140 * forca)))
    camada = camada.filter(ImageFilter.GaussianBlur(M(0.008)))
    img.alpha_composite(camada)
    d = ImageDraw.Draw(img)

    def olho_aberto(cx, cy, lado, brilho=False, palpebra=0.0, olhar=0.0):
        cy2 = cy + ry * olhar
        elipse(d, cx, cy, rx, ry, fill=escuro)
        # íris (só a parte de baixo, clarinha) e pupila
        camada = Image.new("RGBA", (C, C), (0, 0, 0, 0))
        dl = ImageDraw.Draw(camada)
        elipse(dl, cx, cy2 + ry * 0.2, rx * 0.8, ry * 0.72, fill=cor(cfg["iris"]))
        clara = tuple(min(255, int(v * 1.5 + 30)) for v in cor(cfg["iris"])[:3]) + (255,)
        elipse(dl, cx, cy2 + ry * 0.5, rx * 0.55, ry * 0.3, fill=clara)
        elipse(dl, cx, cy2 + ry * 0.08, rx * 0.5, ry * 0.56, fill=escuro)
        camada = camada.filter(ImageFilter.GaussianBlur(M(0.0012)))
        mascara = Image.new("L", (C, C), 0)
        elipse(ImageDraw.Draw(mascara), cx, cy, rx * 0.97, ry * 0.97, fill=255)
        img.paste(camada, (0, 0), Image.composite(camada.getchannel("A"), Image.new("L", (C, C), 0), mascara))
        dd = ImageDraw.Draw(img)
        # brilhos
        elipse(dd, cx - rx * 0.32, cy2 - ry * 0.36, rx * 0.36, ry * 0.3, fill=cor("#FFFFFF"))
        elipse(dd, cx + rx * 0.36, cy2 + ry * 0.36, rx * 0.15, ry * 0.12, fill=cor("#FFFFFF", 235))
        if brilho:
            estrela(dd, cx + rx * 0.28, cy2 - ry * 0.48, rx * 0.26, rx * 0.08, cor("#FFFFFF"), pontas=4)
            estrela(dd, cx - rx * 0.42, cy2 + ry * 0.42, rx * 0.16, rx * 0.05, cor("#FFFFFF"), pontas=4)
        if palpebra > 0.0:
            # pálpebra da cor do pelo (cansado, triste, concentrado)
            dd.chord([cx - rx * 1.25, cy - ry * 1.6, cx + rx * 1.25, cy - ry * 1.6 + ry * 2.0 * palpebra * 1.3], 0, 180,
                     fill=cor(cfg["pelo"]))
            dd.rectangle([cx - rx * 1.25, cy - ry * 1.7, cx + rx * 1.25, cy - ry * 1.6 + ry * 0.65 * palpebra],
                         fill=cor(cfg["pelo"]))
            dd.arc([cx - rx * 1.02, cy - ry * 1.6 + ry * 2.0 * palpebra * 1.3 - ry * 0.95, cx + rx * 1.02,
                    cy - ry * 1.6 + ry * 2.0 * palpebra * 1.3 + ry * 0.12], 15, 165, fill=escuro, width=max(2, int(M(0.0045))))
        if cfg["cilios"]:
            w = max(2, int(M(0.0042)))
            for k in range(2):
                a = math.radians(-35 - k * 26) if lado > 0 else math.radians(-145 + k * 26)
                x0, y0 = cx + math.cos(a) * rx * 0.96, cy + math.sin(a) * ry * 0.96
                x1, y1 = cx + math.cos(a) * rx * 1.32, cy + math.sin(a) * ry * 1.24
                dd.line([x0, y0, x1, y1], fill=escuro, width=w)
                elipse(dd, x1, y1, w * 0.5, w * 0.5, fill=escuro)

    def olho_fechado(cx, cy, feliz=True):
        w = max(3, int(M(0.0062)))
        if feliz:   # "^" (sorrindo de olho fechado)
            d.arc([cx - rx * 1.05, cy - ry * 0.55, cx + rx * 1.05, cy + ry * 1.0], 200, 340, fill=escuro, width=w)
        else:       # piscando: "u" suave
            d.arc([cx - rx, cy - ry * 0.9, cx + rx, cy + ry * 0.45], 20, 160, fill=escuro, width=w)
            if cfg["cilios"]:
                for k in (-1, 1):
                    x0 = cx + k * rx * 0.85
                    d.line([x0, cy - ry * 0.12, x0 + k * M(0.008), cy + ry * 0.02], fill=escuro, width=max(2, w // 2))

    def sobrancelha(cx, cy, lado, incl, curva):
        w = M(0.0075)
        L = M(0.034)
        pts = []
        for i in range(11):
            t = i / 10 - 0.5
            pts.append((cx + t * L, cy + lado * t * incl * L - curva * L * (0.25 - t * t)))
        d.line(pts, fill=cor(cfg["sobr"]), width=int(w), joint="curve")
        for q in (pts[0], pts[-1]):
            elipse(d, q[0], q[1], w / 2, w / 2, fill=cor(cfg["sobr"]))

    # olhos
    tipos = {"feliz": ("aberto", "aberto"), "piscando": ("u", "u"), "empolgado": ("brilho", "brilho"),
             "triste": ("triste", "triste"), "concentrado": ("conc", "conc"), "surpreso": ("aberto", "aberto"),
             "risada": ("^", "^"), "piscadinha": ("aberto", "^")}[expr]
    for (lado, x), tipo in zip(((1, cfg["olho_x"]), (-1, -cfg["olho_x"])), tipos):
        cx, cy = P(x, cfg["olho_y"])
        if tipo == "aberto":
            olho_aberto(cx, cy, lado)
        elif tipo == "brilho":
            olho_aberto(cx, cy, lado, brilho=True)
        elif tipo == "triste":
            olho_aberto(cx, cy, lado, palpebra=0.22, olhar=olhar_y)
        elif tipo == "conc":
            olho_aberto(cx, cy, lado, palpebra=0.28, olhar=olhar_y)
        elif tipo == "^":
            olho_fechado(cx, cy, True)
        else:
            olho_fechado(cx, cy, False)
    d = ImageDraw.Draw(img)
    # sobrancelhas
    incl = {"triste": -0.45, "concentrado": 0.3, "surpreso": 0.0}.get(expr, 0.05)
    curva = {"surpreso": 0.55, "empolgado": 0.45, "feliz": 0.3, "risada": 0.35, "piscadinha": 0.3}.get(expr, 0.15)
    dy = {"surpreso": 0.012, "empolgado": 0.008, "triste": 0.004}.get(expr, 0.0)
    for s in (1, -1):
        cx, cy = P(s * (cfg["olho_x"] + 0.004), cfg["olho_y"] + cfg["olho_ry"] + 0.024 + dy)
        sobrancelha(cx, cy, s, incl, curva)
    # boca: risquinho do nariz + "w"; aberta quando feliz
    borda = cor("#4A1E22")
    interior = cor("#8E2A3C")
    lingua = cor("#FF7C90")
    w = max(3, int(M(0.0062)))
    nx, ny = P(0.0, cfg["nariz_baixo"])
    bx, by = P(0.0, cfg["boca_y"])
    L = M(cfg["boca_l"])

    def w_boca(abre=1.0):
        d.line([nx, ny - M(0.004), bx, by], fill=borda, width=w)
        for s in (-1, 1):
            caixa = [bx + (0 if s > 0 else -L * 0.5), by - L * 0.22 * abre, bx + (L * 0.5 if s > 0 else 0), by + L * 0.26 * abre]
            d.arc(caixa, 0, 180, fill=borda, width=w)

    tipo_boca = {"feliz": "aberta", "piscando": "w", "empolgado": "grande", "triste": "triste", "concentrado": "w",
                 "surpreso": "o", "risada": "grande", "piscadinha": "lingua"}[expr]
    if tipo_boca == "w":
        w_boca()
    elif tipo_boca in ("aberta", "grande"):
        g = 1.0 if tipo_boca == "aberta" else 1.4
        w_boca(0.9)
        caixa = [bx - L * 0.3 * g, by - L * 0.02, bx + L * 0.3 * g, by + L * 0.62 * g]
        d.chord(caixa, 0, 180, fill=borda)
        d.chord([caixa[0] + w, caixa[1] + w * 0.4, caixa[2] - w, caixa[3] - w], 0, 180, fill=interior)
        elipse(d, bx, by + L * 0.42 * g, L * 0.17 * g, L * 0.1 * g, fill=lingua)
    elif tipo_boca == "o":
        d.line([nx, ny - M(0.004), bx, by - L * 0.08], fill=borda, width=w)
        elipse(d, bx, by + L * 0.18, L * 0.15, L * 0.19, fill=borda)
        elipse(d, bx, by + L * 0.18, L * 0.15 - w, L * 0.19 - w, fill=interior)
    elif tipo_boca == "triste":
        d.line([nx, ny - M(0.004), bx, by], fill=borda, width=w)
        d.arc([bx - L * 0.32, by + L * 0.05, bx + L * 0.32, by + L * 0.5], 200, 340, fill=borda, width=w)
    elif tipo_boca == "lingua":
        w_boca()
        elipse(d, bx + L * 0.16, by + L * 0.3, L * 0.13, L * 0.15, fill=borda)
        elipse(d, bx + L * 0.16, by + L * 0.3, L * 0.13 - w * 0.8, L * 0.15 - w * 0.8, fill=lingua)
    if cfg["bigode"]:
        wb = max(2, int(M(0.0028)))
        for s in (-1, 1):
            for k in range(3):
                x0, y0 = P(s * 0.06, cfg["boca_y"] + 0.024 - k * 0.011)
                x1, y1 = P(s * 0.15, cfg["boca_y"] + 0.032 - k * 0.022)
                d.line([x0, y0, (x0 + x1) / 2, (y0 + y1) / 2 - M(0.003), x1, y1], fill=cor("#6E7488", 190), width=wb, joint="curve")
    if expr == "triste":   # lagriminha
        cx, cy = P(-cfg["olho_x"] - 0.01, cfg["olho_y"] - cfg["olho_ry"] - 0.012)
        r = M(0.009)
        d.polygon([(cx, cy - r * 1.8), (cx - r, cy), (cx + r, cy)], fill=cor("#7FD3FF"))
        elipse(d, cx, cy, r, r, fill=cor("#7FD3FF"))
    return img


def gerar_atlas_mascote(nome, colunas=4, celula_final=1024):
    cfg = MASCOTES[nome]
    C = celula_final * 2
    linhas = (len(EXPR_PERSONAGEM) + colunas - 1) // colunas
    atlas = Image.new("RGBA", (colunas * celula_final, linhas * celula_final), (0, 0, 0, 0))
    for i, e in enumerate(EXPR_PERSONAGEM):
        img = desenhar_rosto_mascote(cfg, e, C)
        img = img.resize((celula_final, celula_final), Image.LANCZOS)
        atlas.paste(img, ((i % colunas) * celula_final, (i // colunas) * celula_final))
    atlas.save(os.path.join(TEX, "rosto_%s.png" % nome))
    print("  textura rosto", nome, atlas.size)


def gerar_atlas(nome, R, exprs, colunas=4, celula_final=512):
    linhas = (len(exprs) + colunas - 1) // colunas
    atlas = Image.new("RGBA", (colunas * celula_final, linhas * celula_final), (0, 0, 0, 0))
    for i, e in enumerate(exprs):
        img = desenhar_rosto(R, e)
        img = reduzir(img, (celula_final, celula_final))
        atlas.paste(img, ((i % colunas) * celula_final, (i // colunas) * celula_final))
    atlas.save(os.path.join(TEX, nome + ".png"))
    print("  textura", nome, atlas.size)


def rostos():
    c = 512 * SS
    bob = Rosto(c, iris="#4A2A18", sobrancelha="#8A4E22", bicho=True, olho_x=0.205, olho_y=0.395,
                olho_rx=0.1, olho_ry=0.128, boca_y=0.725, boca_l=0.2, bochecha_x=0.335, bochecha_y=0.6,
                sobr_y=0.2, nariz_y=0.655, bochecha="#FF8FA8")
    mia = Rosto(c, iris="#3DBE7A", sobrancelha="#7D8599", bicho=True, gato=True, cilios=True, olho_x=0.205,
                olho_y=0.395, olho_rx=0.102, olho_ry=0.132, boca_y=0.725, boca_l=0.19, bochecha_x=0.33,
                bochecha_y=0.58, sobr_y=0.2, nariz_y=0.655, bochecha="#FF8FA8")
    gerar_atlas_mascote("bob")
    gerar_atlas_mascote("mia")
    # pino: rosto menor e mais simples (olhos grandes, sem sobrancelha grossa)
    pino = Rosto(512 * SS, iris="#2A2A55", sobrancelha="#2A1A30", olho_x=0.2, olho_y=0.42, olho_rx=0.105,
                 olho_ry=0.15, boca_y=0.74, boca_l=0.22, bochecha_x=0.34, bochecha_y=0.66, sobr_y=0.2)
    gerar_atlas("rosto_pino", pino, EXPR_PINO, celula_final=512)


# =====================================================================
# TEXTURAS DO MUNDO
# =====================================================================

def madeira():
    """Tábuas da pista (repete no comprimento). 39 tábuas como na pista real,
    tons de bordo claro com veios; envernizada (o brilho vem do shader).
    1024 x 2048 (nítida de perto em 4K)."""
    import numpy as np
    W, H = 1024, 2048
    rnd = random.Random(5)
    tabuas = 39
    larg = W / tabuas
    base = np.array([[236 + 10 * t, 196 + 12 * t, 140 + 14 * t] for t in (rnd.uniform(-1, 1) for _ in range(tabuas))])
    emendas = np.array([[rnd.uniform(0, H) for _ in range(2)] for _ in range(tabuas)])
    x = np.arange(W)[None, :].repeat(H, 0).astype(float)
    y = np.arange(H)[:, None].repeat(W, 1).astype(float)
    i = np.minimum((x / larg).astype(int), tabuas - 1)
    fx = (x - i * larg) / larg
    ys = y / 2.0   # mesma densidade de veio da versão 512 x 1024
    veio = np.sin(ys * 0.045 + np.sin(ys * 0.011 + i * 1.7) * 3.0 + fx * 2.0 + i)
    veio2 = np.sin(ys * 0.19 + i * 3.1 + fx * 9.0) * 0.5
    k = 1.0 + 0.045 * veio + 0.02 * veio2
    borda = 1.0 - 0.10 * np.maximum(0.0, 1.0 - np.minimum(fx, 1 - fx) * 14)
    emenda = np.ones_like(x)
    for e in range(2):
        ee = emendas[i, e]
        perto = np.abs(((y - ee + H / 2) % H) - H / 2) < 2.0
        emenda = np.where(perto, 0.86, emenda)
    f = (k * borda * emenda)[..., None]
    img = np.clip(base[i] * f, 0, 255).astype(np.uint8)
    Image.fromarray(img, "RGB").save(os.path.join(TEX, "madeira.png"))
    print("  textura madeira", (W, H))


def bola_textura(nome, fundo, fundo2, desenho, cor_desenho, faixa):
    """Textura equiretangular (2:1) para a bola. desenho: 'estrela' | 'coracao' | 'pata'."""
    W, H = 2048, 1024
    img = Image.new("RGBA", (W * 2, H * 2), cor(fundo))
    d = ImageDraw.Draw(img)
    w, h = img.size
    # degradê suave (redemoinho)
    for y in range(0, h, 4):
        t = y / h
        for x in range(0, w, 8):
            v = 0.5 + 0.5 * math.sin(x / w * 2 * math.pi * 2 + t * 6.0)
            if v > 0.62:
                d.rectangle([x, y, x + 8, y + 4], fill=cor(fundo2))
    img = img.filter(ImageFilter.GaussianBlur(10))
    d = ImageDraw.Draw(img)
    # faixa no "equador"
    d.rectangle([0, h * 0.47, w, h * 0.53], fill=cor(faixa))
    rnd = random.Random(nome)
    for i in range(26):
        u = rnd.uniform(0, 1)
        v = rnd.uniform(0.18, 0.82)
        if abs(v - 0.5) < 0.07:
            continue
        r = rnd.uniform(0.035, 0.06) * h
        cx, cy = u * w, v * h
        rx = r / max(0.35, math.sin(v * math.pi))  # compensa o achatamento nos polos
        for dx in (-w, 0, w):
            if desenho == "estrela":
                pts = []
                for k in range(10):
                    rr = r if k % 2 == 0 else r * 0.45
                    a = -math.pi / 2 + k * math.pi / 5 + i
                    pts.append((cx + dx + math.cos(a) * rr * (rx / r), cy + math.sin(a) * rr))
                d.polygon(pts, fill=cor(cor_desenho))
            elif desenho == "pata":
                # patinha: almofada grande + 4 dedinhos
                camada = Image.new("L", (int(rx * 2.8), int(r * 2.8)), 0)
                dc = ImageDraw.Draw(camada)
                cw, ch = camada.size
                elipse(dc, cw * 0.5, ch * 0.64, cw * 0.25, ch * 0.21, fill=255)
                for fx, fy in ((0.22, 0.38), (0.4, 0.22), (0.6, 0.22), (0.78, 0.38)):
                    elipse(dc, cw * fx, ch * fy, cw * 0.1, ch * 0.12, fill=255)
                camada = camada.rotate(rnd.uniform(-35, 35), resample=Image.BICUBIC)
                img.paste(Image.new("RGBA", camada.size, cor(cor_desenho)), (int(cx + dx - cw / 2), int(cy - ch / 2)), camada)
            else:
                camada = Image.new("L", (int(rx * 2.6), int(r * 2.6)), 0)
                dc = ImageDraw.Draw(camada)
                cw, ch = camada.size
                elipse(dc, cw * 0.32, ch * 0.38, cw * 0.2, ch * 0.2, fill=255)
                elipse(dc, cw * 0.68, ch * 0.38, cw * 0.2, ch * 0.2, fill=255)
                dc.polygon([(cw * 0.13, ch * 0.45), (cw * 0.87, ch * 0.45), (cw * 0.5, ch * 0.88)], fill=255)
                img.paste(Image.new("RGBA", camada.size, cor(cor_desenho)), (int(cx + dx - cw / 2), int(cy - ch / 2)), camada)
    # três furos dos dedos (perto do polo de cima, vistos de lado)
    for (u, v, r) in ((0.25, 0.2, 0.04), (0.29, 0.13, 0.034), (0.21, 0.13, 0.034)):
        elipse(d, u * w, v * h, r * h * 1.6, r * h, fill=cor("#0E1A33"))
    img = img.resize((W, H), Image.LANCZOS)
    img.convert("RGB").save(os.path.join(TEX, "bola_%s.png" % nome))
    print("  textura bola", nome)


def radial(nome, tam, cor_c, potencia=1.6, borda=1.0):
    img = Image.new("RGBA", (tam, tam), (0, 0, 0, 0))
    px = img.load()
    c = (tam - 1) / 2
    for y in range(tam):
        for x in range(tam):
            r = math.hypot(x - c, y - c) / c
            a = max(0.0, 1.0 - r / borda)
            a = a ** potencia
            px[x, y] = (cor_c[0], cor_c[1], cor_c[2], int(255 * a))
    img.save(os.path.join(TEX, nome + ".png"))


def particulas():
    radial("sombra", 128, (30, 14, 60), 1.4)
    radial("brilho", 128, (255, 255, 255), 2.2)
    # estrela com brilho
    t = 256 * SS
    img = Image.new("RGBA", (t, t), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    estrela(d, t / 2, t / 2 + t * 0.03, t * 0.46, t * 0.2, cor("#FFFFFF"))
    img = reduzir(img, (256, 256))
    img.save(os.path.join(TEX, "estrela.png"))
    # brilhinho de 4 pontas
    img = Image.new("RGBA", (t, t), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    estrela(d, t / 2, t / 2, t * 0.48, t * 0.08, cor("#FFFFFF"), pontas=4)
    img = reduzir(img, (128, 128)).filter(ImageFilter.GaussianBlur(1))
    img.save(os.path.join(TEX, "faisca.png"))
    # confete (retângulo arredondado branco: a cor vem da partícula)
    img = Image.new("RGBA", (64 * SS, 64 * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([8 * SS, 18 * SS, 56 * SS, 46 * SS], radius=6 * SS, fill=(255, 255, 255, 255))
    reduzir(img, (64, 64)).save(os.path.join(TEX, "confete.png"))
    # fumacinha fofa (poeira do impacto)
    img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    rnd = random.Random(2)
    camada = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(camada)
    for _ in range(9):
        x, y, r = rnd.uniform(40, 88), rnd.uniform(40, 88), rnd.uniform(18, 30)
        elipse(d, x, y, r, r, fill=(255, 255, 255, 200))
    camada = camada.filter(ImageFilter.GaussianBlur(6))
    camada.save(os.path.join(TEX, "fumaca.png"))
    # bolha de sabão / do fundo do mar (anel claro + brilhinho)
    t = 128 * SS
    img = Image.new("RGBA", (t, t), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    elipse(d, t / 2, t / 2, t * 0.44, t * 0.44, fill=(255, 255, 255, 60), outline=(255, 255, 255, 235), width=int(t * 0.06))
    elipse(d, t * 0.36, t * 0.34, t * 0.1, t * 0.07, fill=(255, 255, 255, 240))
    reduzir(img, (128, 128)).save(os.path.join(TEX, "bolha.png"))
    # chama do jato (gota vertical, branco no centro -> laranja)
    W, H = 64, 128
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    for y in range(H):
        for x in range(W):
            v = y / H  # 0 em cima (bocal) -> 1 na ponta
            larg = 0.5 * (1 - v) ** 0.7 * (0.6 + 0.4 * math.sin(v * math.pi) + 0.25)
            dx = abs(x - W / 2) / (W / 2)
            if dx < larg:
                k = 1 - dx / max(larg, 1e-3)
                quente = (1 - v) * k
                r = 255
                g = int(120 + 135 * min(1, quente * 1.4))
                b = int(40 + 215 * max(0, quente - 0.55) * 2)
                a = int(255 * min(1, k * 1.6) * (1 - v) ** 0.5)
                px[x, y] = (r, g, min(255, b), a)
    img.save(os.path.join(TEX, "chama.png"))
    print("  partículas ok")


def texturas():
    madeira()
    bola_textura("bob", "#0E9DB8", "#3FD3E0", "pata", "#FFD43B", "#FFFFFF")
    bola_textura("mia", "#F2601E", "#FF9A3D", "estrela", "#FFF2A8", "#FFD43B")
    particulas()


# =====================================================================
# INTERFACE: letreiros, logo, ícones
# =====================================================================

def gradiente_vertical(tam, cores):
    """cores: lista de (posição 0..1, '#hex')."""
    import numpy as np
    w, h = tam
    t = np.linspace(0, 1, h)
    ps = [p for p, _ in cores]
    canais = []
    for k in range(4):
        canais.append(np.interp(t, ps, [cor(c)[k] for _, c in cores]))
    col = np.stack(canais, -1).astype(np.uint8)  # (h, 4)
    arr = np.repeat(col[:, None, :], w, axis=1)
    return Image.fromarray(arr, "RGBA")


def letreiro(texto, nome, cores, contorno="#0B1F45", tam_fonte=260, fonte_nome="titan_one.ttf", inclinar=-4,
             brilho=True, estrelas=True, linhas=None, escala=None):
    """Texto de desenho animado: degradê, contorno grosso, sombra, brilho."""
    f = fonte(fonte_nome, tam_fonte * 2)
    textos = linhas or [texto]
    # mede
    tmp = Image.new("L", (10, 10))
    dt = ImageDraw.Draw(tmp)
    caixas = [dt.textbbox((0, 0), t, font=f) for t in textos]
    larg = max(b[2] - b[0] for b in caixas)
    alt_linha = max(b[3] - b[1] for b in caixas)
    esp = int(alt_linha * 0.12)
    alt = alt_linha * len(textos) + esp * (len(textos) - 1)
    m = int(tam_fonte * 0.55)
    W, H = larg + m * 2, alt + m * 2
    mascara = Image.new("L", (W, H), 0)
    dm = ImageDraw.Draw(mascara)
    y = m
    for t, b in zip(textos, caixas):
        x = m + (larg - (b[2] - b[0])) // 2 - b[0]
        dm.text((x, y - b[1]), t, font=f, fill=255)
        y += alt_linha + esp
    borda = int(tam_fonte * 0.16)
    contorno_m = mascara.filter(ImageFilter.MaxFilter(borda * 2 + 1)) if borda < 40 else mascara
    if borda >= 40:
        contorno_m = mascara
        for _ in range(borda // 12):
            contorno_m = contorno_m.filter(ImageFilter.MaxFilter(25))
    contorno_m = contorno_m.filter(ImageFilter.GaussianBlur(1.5))
    final = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # sombra
    sombra = Image.new("RGBA", (W, H), (0, 12, 36, 0))
    sombra.putalpha(contorno_m.point(lambda v: int(v * 0.55)))
    final.alpha_composite(sombra, (0, int(tam_fonte * 0.09)))
    # contorno escuro
    c_img = Image.new("RGBA", (W, H), cor(contorno))
    c_img.putalpha(contorno_m)
    final.alpha_composite(c_img)
    # anel branco fino entre contorno e preenchimento
    anel = mascara.filter(ImageFilter.MaxFilter(max(3, (borda // 3) * 2 + 1)))
    a_img = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    a_img.putalpha(anel)
    final.alpha_composite(a_img)
    # preenchimento em degradê
    g = gradiente_vertical((W, H), [(0.0, cores[0]), (0.55, cores[1]), (1.0, cores[2])])
    g.putalpha(mascara)
    final.alpha_composite(g)
    if brilho:
        # faixa de brilho na metade de cima das letras
        br = Image.new("L", (W, H), 0)
        db = ImageDraw.Draw(br)
        y = m
        for _ in textos:
            db.rectangle([0, y + alt_linha * 0.06, W, y + alt_linha * 0.36], fill=110)
            y += alt_linha + esp
        br = ImageChops.multiply(br, mascara.filter(ImageFilter.MinFilter(max(3, (borda // 4) * 2 + 1))))
        b_img = Image.new("RGBA", (W, H), (255, 255, 255, 255))
        b_img.putalpha(br.filter(ImageFilter.GaussianBlur(2)))
        final.alpha_composite(b_img)
    if estrelas:
        d = ImageDraw.Draw(final)
        rnd = random.Random(nome)
        for i in range(5):
            cx = rnd.choice([rnd.uniform(0.02, 0.18), rnd.uniform(0.82, 0.98)]) * W
            cy = rnd.uniform(0.08, 0.92) * H
            r = rnd.uniform(0.05, 0.09) * H
            estrela(d, cx, cy, r, r * 0.42, cor("#0B1F45"), giro=rnd.uniform(-0.3, 0.3))
            estrela(d, cx, cy, r * 0.78, r * 0.32, cor(rnd.choice(["#FFE14D", "#FFFFFF", "#7FE7FF", "#FF9F2E"])), giro=rnd.uniform(-0.3, 0.3))
    if inclinar:
        final = final.rotate(inclinar, resample=Image.BICUBIC, expand=True)
    bbox = final.getbbox()
    final = final.crop(bbox)
    e = (ESCALA_UI if escala is None else escala) / 2.0
    final = final.resize((int(final.width * e), int(final.height * e)), Image.LANCZOS)
    final.save(os.path.join(UI, nome + ".png"))
    print("  letreiro", nome, final.size)


def logo():
    """STRIKE / KIDS com pino e bola."""
    k = SS // 2
    letreiro("", "logo_texto", ["#FFF6A8", "#FFD43B", "#FF8A1E"], tam_fonte=300, inclinar=0, estrelas=False,
             linhas=["STRIKE", "KIDS"], escala=float(k))
    txt2 = Image.open(os.path.join(UI, "logo_texto.png"))
    txt = txt2.resize((txt2.width // k, txt2.height // k), Image.LANCZOS)
    W, H = txt.width + 360, txt.height + 140
    img = Image.new("RGBA", (W * SS // 2, H * SS // 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # pino estilizado à esquerda
    px0, py0 = 150 * k, (H * k) * 0.52
    def pino(cx, cy, esc, giro):
        camada = Image.new("RGBA", (int(220 * esc * k), int(480 * esc * k)), (0, 0, 0, 0))
        dc = ImageDraw.Draw(camada)
        w, h = camada.size
        for (contorno, cc) in ((True, "#0B1F45"), (False, "#FFFFFF")):
            e = 10 * k * esc if contorno else 0
            elipse(dc, w / 2, h * 0.62, w * 0.42 + e, h * 0.3 + e, fill=cor(cc))
            elipse(dc, w / 2, h * 0.17, w * 0.24 + e, h * 0.13 + e, fill=cor(cc))
            dc.rectangle([w / 2 - w * 0.15 - e, h * 0.2, w / 2 + w * 0.15 + e, h * 0.45], fill=cor(cc))
        dc.rectangle([w / 2 - w * 0.17, h * 0.3, w / 2 + w * 0.17, h * 0.34], fill=cor("#FF3B4E"))
        dc.rectangle([w / 2 - w * 0.18, h * 0.37, w / 2 + w * 0.18, h * 0.41], fill=cor("#FF3B4E"))
        # olhinhos
        for s in (-1, 1):
            elipse(dc, w / 2 + s * w * 0.13, h * 0.58, w * 0.06, h * 0.045, fill=cor("#22101C"))
            elipse(dc, w / 2 + s * w * 0.13 - w * 0.02, h * 0.57, w * 0.022, h * 0.016, fill=cor("#FFFFFF"))
        dc.arc([w / 2 - w * 0.1, h * 0.6, w / 2 + w * 0.1, h * 0.7], 20, 160, fill=cor("#22101C"), width=int(5 * k * esc))
        camada = camada.rotate(giro, resample=Image.BICUBIC, expand=True)
        img.alpha_composite(camada, (int(cx - camada.width / 2), int(cy - camada.height / 2)))
    pino(px0 + 30 * k, py0, 0.9, 14)
    pino(W * k - 140 * k, py0 + 30 * k, 0.75, -18)
    t2 = txt2
    img.alpha_composite(t2, (int((W * k - t2.width) / 2), int(70 * k)))
    # bola com brilho
    bx, by, br = W * k - 210 * k, H * k - 150 * k, 95 * k
    elipse(d, bx, by, br + 10 * k, br + 10 * k, fill=cor("#0B1F45"))
    elipse(d, bx, by, br, br, fill=cor("#2E7BFF"))
    elipse(d, bx - br * 0.15, by - br * 0.1, br * 0.82, br * 0.8, fill=cor("#4FA8FF"))
    for (u, v, r) in ((-0.25, -0.35, 0.13), (0.1, -0.45, 0.11), (0.0, -0.15, 0.11)):
        elipse(d, bx + u * br, by + v * br, r * br, r * br, fill=cor("#0B1F45"))
    estrela(d, bx + br * 0.35, by + br * 0.3, br * 0.32, br * 0.14, cor("#FFE14D"))
    elipse(d, bx - br * 0.45, by - br * 0.55, br * 0.18, br * 0.12, fill=cor("#FFFFFF"))
    img = img.crop(img.getbbox())
    img = img.resize((int(img.width * ESCALA_UI / k), int(img.height * ESCALA_UI / k)), Image.LANCZOS)
    img.save(os.path.join(UI, "logo.png"))
    os.remove(os.path.join(UI, "logo_texto.png"))
    print("  logo", img.size)


def icones():
    # bolinha de "tentativa" e estrela do placar
    t = 128 * SS
    img = Image.new("RGBA", (t, t), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    estrela(d, t / 2, t / 2 + t * 0.04, t * 0.48, t * 0.21, cor("#0B1F45"))
    estrela(d, t / 2, t / 2 + t * 0.04, t * 0.38, t * 0.165, cor("#FFD43B"))
    estrela(d, t / 2 - t * 0.04, t / 2, t * 0.2, t * 0.09, cor("#FFF6A8"))
    reduzir(img, (128, 128)).save(os.path.join(UI, "estrela_placar.png"))
    img = Image.new("RGBA", (t, t), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    estrela(d, t / 2, t / 2 + t * 0.04, t * 0.48, t * 0.21, cor("#0B1F45", 160))
    estrela(d, t / 2, t / 2 + t * 0.04, t * 0.38, t * 0.165, cor("#9FB4D8", 200))
    reduzir(img, (128, 128)).save(os.path.join(UI, "estrela_vazia.png"))
    print("  ícones ok")


def ui():
    roxo = "#0B1F45"   # contorno azul-marinho (cor da marca)
    letreiro("STRIKE!", "strike", ["#FFF6A8", "#FFD43B", "#FF6A1E"], roxo, 300)
    letreiro("SPARE!", "spare", ["#C9F7FF", "#4FD8FF", "#2E6BFF"], roxo, 280)
    letreiro("OPS!", "ops", ["#FFF1DA", "#FFB36B", "#F0602A"], roxo, 260)
    letreiro("BOA!", "boa", ["#E6FFD6", "#8DFF6A", "#2DBE4E"], roxo, 260)
    letreiro("UAU!", "uau", ["#E6FFFB", "#5EE6E0", "#13A3BC"], roxo, 260)
    letreiro("QUASE!", "quase", ["#FFF1DA", "#FFB347", "#FF6A1E"], roxo, 250)
    letreiro("SUPER!", "super", ["#FFF6A8", "#FF9F2E", "#FF3B4E"], roxo, 260)
    letreiro("REPLAY", "replay", ["#FFFFFF", "#BFF3FF", "#20B4CC"], roxo, 200, inclinar=0, estrelas=False)
    letreiro("", "pegando_fogo", ["#FFF6A8", "#FF9F2E", "#FF3B1E"], roxo, 210, linhas=["PEGANDO", "FOGO!"])
    # cenários (um por rodada)
    letreiro("", "cen_espaco", ["#F0F4FF", "#8FD3FF", "#2E6BFF"], roxo, 200, linhas=["VIAGEM AO", "ESPAÇO!"])
    letreiro("", "cen_mar", ["#E6FFFB", "#5EE6E0", "#1B8FD6"], roxo, 200, linhas=["FUNDO", "DO MAR!"])
    letreiro("", "cen_dinos", ["#F4FFD6", "#A6EC52", "#2FA84F"], roxo, 200, linhas=["SELVA DOS", "DINOS!"])
    letreiro("", "cen_parque", ["#FFF6A8", "#FFB627", "#FF6A1E"], roxo, 200, linhas=["PARQUE DE", "DIVERSÕES!"])
    letreiro("", "fim_de_jogo", ["#FFFFFF", "#D6E6FF", "#7F9CFF"], roxo, 210, linhas=["FIM DE", "JOGO!"])
    letreiro("", "novo_recorde", ["#FFF6A8", "#FFD43B", "#FF6A1E"], roxo, 200, linhas=["NOVO", "RECORDE!"])
    letreiro("EMPATE!", "empate", ["#FFFFFF", "#8FD3FF", "#2E6BFF"], roxo, 240)
    letreiro("PARABÉNS!", "parabens", ["#FFF6A8", "#FFD43B", "#FF6A1E"], roxo, 220)
    letreiro("VENCEU!", "venceu", ["#FFF6A8", "#FFD43B", "#FF6A1E"], roxo, 240)
    logo()
    icones()


def icone():
    """Ícone do app (432 px): fundo em degradê + Bob e Mia + logo.
    Usa os retratos renderizados pelo Godot (tools/testes/retratos.tscn)."""
    import numpy as np
    T = 432
    fundo = gradiente_vertical((T, T), [(0, "#123A7A"), (0.55, "#169BD5"), (1, "#FFD43B")])
    d = ImageDraw.Draw(fundo)
    rnd = random.Random(4)
    for _ in range(14):
        x, y, r = rnd.uniform(0, T), rnd.uniform(0, T), rnd.uniform(6, 16)
        estrela(d, x, y, r, r * 0.42, cor("#FFFFFF", 120))
    fundo.save(os.path.join(UI, "icone_fundo.png"))
    frente = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    for nome, dx in (("mia", 0.2), ("bob", -0.2)):
        c = os.path.join(UI, "retrato_%s_empolgado.png" % nome)
        if not os.path.exists(c):
            continue
        r = Image.open(c)
        r = r.crop((int(r.width * 0.12), 0, int(r.width * 0.88), int(r.height * 0.7)))
        r = r.resize((int(T * 0.78), int(T * 0.78 * r.height / r.width)), Image.LANCZOS)
        frente.alpha_composite(r, (int(T * 0.11 + dx * T), int(T * 0.02)))
    comp = fundo.copy()
    comp.alpha_composite(frente)
    lg = os.path.join(UI, "logo.png")
    if os.path.exists(lg):
        lo = Image.open(lg)
        lw = int(T * 0.96)
        lo = lo.resize((lw, int(lw * lo.height / lo.width)), Image.LANCZOS)
        comp.alpha_composite(lo, ((T - lw) // 2, T - lo.height - int(T * 0.02)))
    # cantos arredondados para o ícone "main"
    m = Image.new("L", (T, T), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, T - 1, T - 1], radius=int(T * 0.22), fill=255)
    comp.putalpha(m)
    comp.save(os.path.join(UI, "icone.png"))
    comp.resize((256, 256), Image.LANCZOS).save(os.path.join(UI, "icone_256.png"))
    print("  ícone ok")


# =====================================================================
# SOL E LUA COM ROSTINHO (no céu dos cenários: Mundo._astro)
# =====================================================================
# Pequenos de propósito (no céu eles ocupam poucos pixels): rosto em 2
# quadros lado a lado (olhos abertos | piscando) e os raios do sol num
# desenho à parte (o shader astro.gdshader gira os raios e faz piscar).
CEU = os.path.join(UI, "ceu")


def _disco(d, img, c, raio, centro_cor, borda_cor, contorno, larg):
    """Disco com degradê radial (centro -> borda) e contorno."""
    elipse(d, c, c, raio + larg, raio + larg, fill=cor(contorno))
    camada = Image.new("RGBA", img.size, (0, 0, 0, 0))
    px = camada.load()
    a, b = cor(centro_cor), cor(borda_cor)
    r2 = raio * raio
    for y in range(int(c - raio), int(c + raio) + 1):
        for x in range(int(c - raio), int(c + raio) + 1):
            dd = (x - c) ** 2 + (y - c) ** 2
            if dd <= r2:
                t = (dd / r2) ** 0.8
                px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)
    img.alpha_composite(camada)


def _boca_aberta(d, R):
    """Sorriso aberto LISO: só a boquinha (meia-lua) com a linguinha — sem
    dentes e sem a linha em cima (de longe aquilo parecia um bigode)."""
    cx, cy = R.P(0.5, R.by)
    L = R.L(R.bl)
    w = max(2, int(R.L(0.022)))
    bb = [cx - L * 0.5, cy - L * 0.42, cx + L * 0.5, cy + L * 0.5]
    d.chord(bb, 0, 180, fill=cor(R.boca_borda))
    bb2 = [bb[0] + w, bb[1] + w, bb[2] - w, bb[3] - w]
    d.chord(bb2, 0, 180, fill=cor("#7A1E33"))
    # linguinha: elipse no fundo da boca, recortada pelo lado de dentro
    img = d._image
    dentro = Image.new("L", img.size, 0)
    ImageDraw.Draw(dentro).chord(bb2, 0, 180, fill=255)
    lingua = Image.new("RGBA", img.size, (0, 0, 0, 0))
    elipse(ImageDraw.Draw(lingua), cx, bb2[3] - L * 0.02, L * 0.25, L * 0.17, fill=cor("#FF7A8C"))
    lingua.putalpha(ImageChops.multiply(lingua.getchannel("A"), dentro))
    img.alpha_composite(lingua)


def _rosto_astro(T, cx, cy, escala, iris, piscando, bochecha="#FF8FA6", boca_tipo="aberta"):
    """Olhos, bochechas e boca (os mesmos dos personagens) numa camada."""
    cel = int(T * escala)
    R = Rosto(cel, iris, None, boca_borda="#7A2E12", bochecha=bochecha, olho_x=0.2, olho_y=0.43,
              olho_rx=0.115, olho_ry=0.155, boca_y=0.68, boca_l=0.28, bochecha_x=0.35, bochecha_y=0.62)
    camada = Image.new("RGBA", (cel, cel), (0, 0, 0, 0))
    d = ImageDraw.Draw(camada)
    d._image = camada
    bochechas(d, R, 1.2)
    for lado, ux in ((1, 0.5 + R.ox), (-1, 0.5 - R.ox)):
        x, y = R.P(ux, R.oy)
        desenhar_olho(d, R, x, y, "fechado_baixo" if piscando else "aberto", lado)
    if boca_tipo == "aberta":
        _boca_aberta(d, R)
    else:
        boca(d, R, boca_tipo)
    saida = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    saida.alpha_composite(camada, (int(cx - cel / 2), int(cy - cel / 2)))
    return saida


def _quadros(desenhar, T):
    """Os dois quadros (olhos abertos | piscando) lado a lado."""
    atlas = Image.new("RGBA", (T * 2, T), (0, 0, 0, 0))
    for k in range(2):
        atlas.alpha_composite(desenhar(k == 1), (k * T, 0))
    return atlas


def astros():
    os.makedirs(CEU, exist_ok=True)
    T = 256 * SS
    c = T / 2
    # ---- sol: disco amarelo com contorno laranja; raios num desenho à parte
    r_sol = T * 0.30

    def sol(piscando):
        img = Image.new("RGBA", (T, T), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        _disco(d, img, c, r_sol, "#FFF27A", "#FFB52E", "#C2570C", T * 0.014)
        img.alpha_composite(_rosto_astro(T, c, c + r_sol * 0.06, 0.6, "#6B3A12", piscando))
        return img

    _quadros(sol, T).resize((512, 256), Image.LANCZOS).save(os.path.join(CEU, "sol.png"))
    raios = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(raios)
    n = 12
    for k in range(n):
        a = k / n * math.tau
        longo = k % 2 == 0
        r1 = r_sol * 0.92
        r2 = T * (0.49 if longo else 0.43)
        meia = math.tau / n * (0.34 if longo else 0.3)
        pts = [(c + math.cos(a - meia) * r1, c + math.sin(a - meia) * r1),
               (c + math.cos(a) * r2, c + math.sin(a) * r2),
               (c + math.cos(a + meia) * r1, c + math.sin(a + meia) * r1)]
        d.polygon(pts, fill=cor("#C2570C"))
        # o miolo do raio (deixa o contorno em volta)
        enc = 0.86
        pts2 = [(c + (x - c) * enc + math.cos(a) * T * 0.012, c + (y - c) * enc + math.sin(a) * T * 0.012) for x, y in pts]
        d.polygon(pts2, fill=cor("#FFC93C" if longo else "#FF9A1F"))
    raios.resize((256, 256), Image.LANCZOS).save(os.path.join(CEU, "sol_raios.png"))
    # ---- lua cheia com crateras e rostinho
    r_lua = T * 0.44

    def lua(piscando):
        img = Image.new("RGBA", (T, T), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        _disco(d, img, c, r_lua, "#FFF9DC", "#F2D98A", "#A07A2C", T * 0.014)
        # crateras (longe do rosto)
        for fx, fy, fr in ((0.42, -0.5, 0.17), (-0.6, -0.28, 0.11), (0.62, 0.2, 0.09), (-0.45, 0.55, 0.13), (0.15, -0.72, 0.07)):
            x, y, rr = c + fx * r_lua, c + fy * r_lua, fr * r_lua
            elipse(d, x, y, rr, rr, fill=cor("#E8CB72"))
            elipse(d, x + rr * 0.12, y + rr * 0.14, rr * 0.82, rr * 0.82, fill=cor("#F3DC93"))
        img.alpha_composite(_rosto_astro(T, c, c + r_lua * 0.08, 0.72, "#2B3F8C", piscando, "#FF9AB0", "sorriso"))
        return img

    _quadros(lua, T).resize((512, 256), Image.LANCZOS).save(os.path.join(CEU, "lua.png"))
    print("  sol e lua ok")


if __name__ == "__main__":
    partes = sys.argv[1:] or ["rostos", "texturas", "ui"]
    if "rostos" in partes:
        rostos()
    if "texturas" in partes:
        texturas()
    if "ui" in partes and "ui" in globals():
        globals()["ui"]()
    if "icone" in partes or "ui" in partes:
        icone()
    if "astros" in partes:
        astros()
