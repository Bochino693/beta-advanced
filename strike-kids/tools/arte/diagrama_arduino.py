#!/usr/bin/env python3
"""DIAGRAMA DE LIGAÇÃO DO ARDUINO (Strike Kids).

Gera docs/ligacao_arduino.svg (e .png / .pdf, se o rsvg-convert existir):
o Arduino Nano visto de cima, com os pinos na ordem real, e onde vai cada
fio — os 5 sensores, os botões START / CONFIGURAÇÃO / FICHA, a trava da
porta (servo ou relé), a fita de LED e o USB da TV Box — mais o passo a
passo para dar o primeiro START.

Os pinos são os do firmware (arduino/strike_kids/strike_kids.ino): se
mudar lá, mude aqui e rode de novo:
    python3 tools/arte/diagrama_arduino.py
"""
import os
import shutil
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.normpath(os.path.join(AQUI, "..", ".."))
SAIDA = os.path.join(RAIZ, "docs", "ligacao_arduino")

W, H = 3400, 2470
TXT = "DejaVu Sans"
TIT = "Fredoka Light"

# cores dos fios
COR = {
    "S1": "#7d3c98", "S2": "#1f6fb2", "S3": "#1e8449", "S4": "#b9770e", "S5": "#c2185b",
    "LED": "#0097a7", "RELE": "#566573", "SERVO": "#e67e22",
    "START": "#1fa84f", "CFG": "#d35400", "FICHA": "#7f8c8d",
    "GND": "#1c1c1c", "5V": "#d0021b", "12V": "#a93226", "USB": "#7b7d7d",
}

partes = []


def esc(t):
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def ret(x, y, w, h, fill, stroke="none", sw=0, r=0, extra=""):
    partes.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>')


def circ(x, y, r, fill, stroke="none", sw=0):
    partes.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>')


def txt(x, y, t, size=28, cor="#1b2631", peso="normal", ancora="start", fam=TXT, extra=""):
    partes.append(f'<text x="{x}" y="{y}" font-family="{fam}" font-size="{size}" font-weight="{peso}" fill="{cor}" text-anchor="{ancora}" {extra}>{esc(t)}</text>')


def linhas_txt(x, y, linhas, size=26, cor="#1b2631", alt=1.35, peso="normal", ancora="start"):
    for i, l in enumerate(linhas):
        p = peso
        t = l
        if l.startswith("**"):
            p = "bold"
            t = l[2:]
        txt(x, y + i * size * alt, t, size, cor, p, ancora)


def fio(pontos, cor, largura=8, hops=()):
    """Fio em linhas retas; hops = [(x, y)] onde ele pula outro fio."""
    d = f"M {pontos[0][0]} {pontos[0][1]}"
    for (x0, y0), (x1, y1) in zip(pontos, pontos[1:]):
        pulos = [(hx, hy) for (hx, hy) in hops if y0 == y1 == hy and min(x0, x1) < hx < max(x0, x1)]
        pulos.sort(key=lambda p: p[0] if x1 > x0 else -p[0])
        for hx, hy in pulos:
            s = 1 if x1 > x0 else -1
            d += f" L {hx - 16 * s} {hy} A 16 16 0 0 {1 if s > 0 else 0} {hx + 16 * s} {hy}"
        d += f" L {x1} {y1}"
    partes.append(f'<path d="{d}" fill="none" stroke="#ffffff" stroke-width="{largura + 6}" stroke-linecap="round" stroke-linejoin="round"/>')
    partes.append(f'<path d="{d}" fill="none" stroke="{cor}" stroke-width="{largura}" stroke-linecap="round" stroke-linejoin="round"/>')


def bandeira(x, y, texto, cor, txtcor="#ffffff", size=24):
    """Etiqueta no fim de um fio (GND, 5V...)."""
    w = int(len(texto) * size * 0.72) + 28
    ret(x - w / 2, y, w, size + 16, cor, r=8)
    txt(x, y + size + 4, texto, size, txtcor, "bold", "middle")


def ponta(x, y, cor):
    circ(x, y, 9, cor, "#ffffff", 3)


# ====================================================================== fundo e título
partes.append(f'<rect width="{W}" height="{H}" fill="#f7f9fc"/>')
ret(0, 0, W, 170, "#0b1f45")
txt(60, 100, "STRIKE KIDS · LIGAÇÃO DO ARDUINO", 76, "#ffd43b", "bold", fam=TIT)
txt(60, 148, "Arduino Nano visto de cima (no Uno e no Mega os pinos têm os mesmos nomes; no Mega o servo vai no D11) · firmware arduino/strike_kids", 30, "#dfe9ff")

# ====================================================================== Arduino Nano
BX0, BX1, BY0, BY1 = 1000, 2150, 1050, 1350
PASSO = 70
PX = [1060 + PASSO * i for i in range(15)]
TOPO = ["TX1", "RX0", "RST", "GND", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9", "D10", "D11", "D12"]
BAIXO = ["VIN", "GND", "RST", "5V", "A7", "A6", "A5", "A4", "A3", "A2", "A1", "A0", "AREF", "3V3", "D13"]
YT, YB = 1085, 1315
pino_topo = {n: PX[i] for i, n in enumerate(TOPO)}
pino_baixo = {n: PX[i] for i, n in enumerate(BAIXO)}
USADOS_T = {"D2", "D3", "D4", "D5", "D6", "D7", "D8", "D9"}
USADOS_B = {"A0", "A1", "A2", "5V", "GND"}

partes.append(f'<rect x="{BX0 + 8}" y="{BY0 + 10}" width="{BX1 - BX0}" height="{BY1 - BY0}" rx="22" fill="#00000022"/>')
ret(BX0, BY0, BX1 - BX0, BY1 - BY0, "#1d5fa8", "#123f73", 4, 22)
ret(2150, 1145, 95, 110, "#aab7b8", "#7b7d7d", 3, 8)            # USB
ret(2160, 1172, 70, 56, "#7b7d7d", r=6)
ret(1430, 1150, 210, 100, "#17202a", r=8)                        # chip
txt(1535, 1195, "ATmega328P", 22, "#bfc9ca", "bold", "middle")
txt(1535, 1228, "ARDUINO NANO", 22, "#ffd43b", "bold", "middle")
circ(1960, 1200, 11, "#f5b041", "#ffffff", 2)                    # LED L (D13)
txt(1960, 1240, "L = D13", 18, "#ffffff", "bold", "middle")
txt(1960, 1172, "pisca", 16, "#d6eaf8", "normal", "middle")
for i, n in enumerate(TOPO):
    usado = n in USADOS_T
    circ(PX[i], YT, 17, "#f7dc6f" if usado else "#d4ac0d", "#7d6608", 3)
    circ(PX[i], YT, 6, "#5d4037")
    txt(PX[i], YT + 50, n, 21, "#ffffff" if usado else "#aed6f1", "bold" if usado else "normal", "middle")
for i, n in enumerate(BAIXO):
    usado = n in USADOS_B and not (n == "GND" and i != 1)
    circ(PX[i], YB, 17, "#f7dc6f" if usado else "#d4ac0d", "#7d6608", 3)
    circ(PX[i], YB, 6, "#5d4037")
    txt(PX[i], YB - 32, n, 21, "#ffffff" if usado else "#aed6f1", "bold" if usado else "normal", "middle")

# ====================================================================== sensores (em cima, da esquerda para a direita)
SENS = [("S1", "ESQUERDA", "D2"), ("S2", "MEIO-ESQ.", "D3"), ("S3", "CENTRO", "D4"), ("S4", "MEIO-DIR.", "D5"), ("S5", "DIREITA", "D7")]
CX = [175, 495, 815, 1135, 1455]
CW, CY0, CY1 = 290, 250, 520
NIVEIS = [1012, 972, 932, 892, 852]
txt(40, 228, "OS 5 SENSORES DA PISTA — da ESQUERDA para a DIREITA, olhando da criança para a tela", 30, "#0b1f45", "bold")
for k, (nome, lado, pino) in enumerate(SENS):
    cx = CX[k]
    cor = COR[nome]
    ret(cx - CW / 2, CY0, CW, CY1 - CY0, "#ffffff", cor, 5, 18)
    ret(cx - CW / 2, CY0, CW, 58, cor, r=18)
    ret(cx - CW / 2, CY0 + 30, CW, 28, cor)
    txt(cx, CY0 + 42, f"{nome} · {lado}", 27, "#ffffff", "bold", "middle")
    # desenho do sensor (emissor/receptor)
    ret(cx - 70, CY0 + 80, 140, 60, "#eaecee", "#566573", 3, 10)
    circ(cx - 32, CY0 + 110, 16, "#f1948a", "#922b21", 3)
    circ(cx + 32, CY0 + 110, 16, "#85c1e9", "#1a5276", 3)
    txt(cx, CY0 + 175, f"sinal → {pino}", 26, cor, "bold", "middle")
    # 3 terminais: + (marrom), − (azul), sinal (preto) — cores comuns de sensor NPN
    txt(cx - 95, CY1 - 22, "+", 26, "#6e2c00", "bold", "middle")
    txt(cx, CY1 - 22, "sinal", 20, "#1b2631", "bold", "middle")
    txt(cx + 95, CY1 - 22, "−", 30, "#1a5276", "bold", "middle")
    # + e − em etiquetas logo abaixo do sensor
    fio([(cx - 95, CY1), (cx - 95, CY1 + 40)], "#6e2c00", 6)
    bandeira(cx - 95, CY1 + 40, "+5/12V", "#6e2c00", size=19)
    fio([(cx + 95, CY1), (cx + 95, CY1 + 40)], "#1a5276", 6)
    bandeira(cx + 95, CY1 + 40, "GND", COR["GND"], size=19)

# os fios de sinal: escada sem cruzar (o S5 pula o fio da fita de LED)
LED_X = pino_topo["D6"]
for k, (nome, lado, pino) in enumerate(SENS):
    px, cx, nv = pino_topo[pino], CX[k], NIVEIS[k]
    pts = [(px, YT - 17), (px, nv), (cx, nv), (cx, CY1)]
    hops = [(LED_X, nv)] if nome == "S5" else []
    fio(pts, COR[nome], 8, hops)
    ponta(px, YT - 17, COR[nome])

# ====================================================================== fita de LED (D6)
FX0, FY = 1900, 300
ret(FX0, FY - 40, 1440, 80, "#212f3d", r=14)
for i in range(24):
    x = FX0 + 40 + i * 58
    ret(x, FY - 22, 40, 44, "#fdfefe", "#aab7b8", 2, 6)
    circ(x + 20, FY, 12, ["#ff4d4d", "#ffd43b", "#4dd2ff", "#7dff6a", "#ff7af2"][i % 5])
txt(FX0, FY - 58, "FITA DE LED WS2812 (opcional) — DIN no D6 (resistor de 330 Ω no caminho)", 26, "#0b1f45", "bold")
txt(FX0 + 1440, FY + 78, "+5V e GND da fita: FONTE 5 V própria (60 LEDs ≈ 3,6 A) + capacitor 1000 µF", 22, "#566573", ancora="end")
DIN_X = 1960
fio([(LED_X, YT - 17), (LED_X, 772), (DIN_X, 772), (DIN_X, FY + 40)], COR["LED"], 8)
ponta(LED_X, YT - 17, COR["LED"])
txt(DIN_X + 14, FY + 74, "DIN", 22, COR["LED"], "bold")

# ====================================================================== trava: relé (D8)
RX0, RY0, RW, RH = 2160, 470, 360, 230
ret(RX0, RY0, RW, RH, "#1a5276", "#0b2d4a", 4, 14)
ret(RX0 + 150, RY0 + 50, 130, 100, "#2e86c1", "#d6eaf8", 3, 8)
txt(RX0 + 215, RY0 + 108, "relé", 24, "#ffffff", "bold", "middle")
txt(2160, 432, "TRAVA DA PORTA DAS BOLAS: use o SERVO (D9) ou o RELÉ (D8)", 28, "#0b1f45", "bold")
txt(RX0 + 18, RY0 + 34, "RELÉ · D8", 24, "#ffffff", "bold")
for j, (n, c) in enumerate([("IN", COR["RELE"]), ("VCC", COR["5V"]), ("GND", COR["GND"])]):
    x = RX0 + 50 + j * 90
    circ(x, RY0 + RH, 12, "#f7dc6f", "#7d6608", 3)
    txt(x, RY0 + RH - 22, n, 19, "#ffffff", "bold", "middle")
REL_IN = RX0 + 50
fio([(pino_topo["D8"], YT - 17), (pino_topo["D8"], 812), (REL_IN, 812), (REL_IN, RY0 + RH)], COR["RELE"], 8)
ponta(pino_topo["D8"], YT - 17, COR["RELE"])
fio([(RX0 + 140, RY0 + RH), (RX0 + 140, RY0 + RH + 40)], COR["5V"], 6)
bandeira(RX0 + 140, RY0 + RH + 40, "5V", COR["5V"], size=19)
fio([(RX0 + 230, RY0 + RH), (RX0 + 230, RY0 + RH + 40)], COR["GND"], 6)
bandeira(RX0 + 230, RY0 + RH + 40, "GND", COR["GND"], size=19)
# contatos -> trava e fonte de 12 V
for j, n in enumerate(["NO", "COM", "NC"]):
    y = RY0 + 50 + j * 60
    circ(RX0 + RW, y, 12, "#aab7b8", "#566573", 3)
    txt(RX0 + RW - 22, y + 8, n, 19, "#ffffff", "bold", "end")
SX = 2690
ret(SX, 470, 270, 110, "#7b7d7d", "#4d5656", 4, 14)
txt(SX + 135, 516, "TRAVA", 24, "#ffffff", "bold", "middle")
txt(SX + 135, 548, "solenoide/motor", 20, "#ffffff", "normal", "middle")
txt(SX + 135, 606, "(diodo 1N4007 na trava)", 18, "#566573", ancora="middle")
ret(3040, 600, 300, 110, "#a93226", "#78281f", 4, 14)
txt(3190, 645, "FONTE 12 V", 26, "#ffffff", "bold", "middle")
txt(3070, 690, "+", 30, "#ffffff", "bold", "middle")
txt(3300, 690, "−", 34, "#ffffff", "bold", "middle")
fio([(RX0 + RW, RY0 + 50), (SX, RY0 + 50)], COR["12V"], 6)                          # NO -> trava
fio([(SX + 270, 525), (3300, 525), (3300, 600)], "#1c1c1c", 6)                      # trava -> fonte −
fio([(RX0 + RW, RY0 + 110), (2600, RY0 + 110), (2600, 665), (3040, 665)], COR["12V"], 6)  # COM -> fonte +

# ====================================================================== trava: servo (D9)
SVX, SVY = 2660, 790
ret(SVX, SVY, 300, 160, "#2c3e50", "#17202a", 4, 16)
circ(SVX + 230, SVY + 80, 46, "#f8f9f9", "#aab7b8", 4)
ret(SVX + 180, SVY + 70, 140, 20, "#f8f9f9", "#aab7b8", 3, 10)
txt(SVX + 95, SVY + 96, "0° = fechada", 20, "#d5d8dc", "normal", "middle")
txt(SVX + 95, SVY + 126, "90° = aberta", 20, "#d5d8dc", "normal", "middle")
txt(SVX + 18, SVY + 36, "SERVO · D9", 24, "#ffffff", "bold")
fio([(pino_topo["D9"], YT - 17), (pino_topo["D9"], 852), (SVX, 852)], COR["SERVO"], 8)
ponta(pino_topo["D9"], YT - 17, COR["SERVO"])
txt(2250, 892, "fio laranja/amarelo do servo", 20, COR["SERVO"], "bold")
ret(3040, 790, 300, 160, "#1e8449", "#145a32", 4, 14)
txt(3190, 836, "FONTE 5–6 V", 26, "#ffffff", "bold", "middle")
txt(3190, 868, "do servo", 22, "#ffffff", "normal", "middle")
txt(3070, 902, "+", 28, "#ffffff", "bold", "middle")
txt(3070, 940, "−", 32, "#ffffff", "bold", "middle")
fio([(SVX + 300, 892), (3040, 892)], COR["5V"], 6)       # vermelho
fio([(SVX + 300, 932), (3040, 932)], "#6e2c00", 6)       # marrom
txt(3340, 1000, "o − dessa fonte também no GND do Arduino", 20, "#566573", ancora="end")

# ====================================================================== USB -> TV Box
fio([(2245, 1200), (2700, 1200)], COR["USB"], 22)
ret(2700, 1080, 600, 250, "#17202a", "#000000", 4, 22)
ret(2730, 1110, 540, 150, "#2e4053", r=12)
txt(3000, 1180, "TV BOX (Android)", 34, "#ffd43b", "bold", "middle", fam=TIT)
txt(3000, 1222, "o jogo Strike Kids", 24, "#d6eaf8", "normal", "middle")
txt(3000, 1300, "USB: dados + alimenta o Arduino", 22, "#ffffff", "bold", "middle")
txt(2470, 1176, "cabo USB", 24, "#4d5656", "bold", "middle")
txt(2470, 1250, "1ª vez: marque", 20, "#4d5656", ancora="middle")
txt(2470, 1276, "“Usar por padrão”", 20, "#4d5656", "bold", "middle")

# ====================================================================== botões (embaixo)
BOT = [("FICHA", "A2", 1420, "MOEDEIRO / FICHA", "opcional"), ("START", "A1", 1760, "BOTÃO START", "começa a partida"),
       ("CFG", "A0", 2245, "BOTÃO CONFIGURAÇÃO", "entra e sai do menu")]
BY_TOPO = 1500
for nome, pino, cx, titulo, sub in BOT:
    cor = COR[nome]
    px = pino_baixo[pino]
    nv = 1395
    if px == cx:
        pts = [(px, YB + 17), (cx, BY_TOPO)]
    else:
        pts = [(px, YB + 17), (px, nv), (cx, nv), (cx, BY_TOPO)]
    fio(pts, cor, 8)
    ponta(px, YB + 17, cor)
    destaque = nome == "START"
    w = {"START": 360, "CFG": 400, "FICHA": 280}[nome]
    ret(cx - w / 2, BY_TOPO, w, 230 if destaque else 210, "#ffffff", cor, 8 if destaque else 5, 18)
    circ(cx, BY_TOPO + 85, 50 if destaque else 42, cor, "#ffffff", 6)
    circ(cx, BY_TOPO + 85, 30 if destaque else 24, "#ffffff55")
    txt(cx, BY_TOPO + 165, titulo, 25 if destaque else 23, cor, "bold", "middle")
    txt(cx, BY_TOPO + 195, f"{pino} e GND · {sub}", 19, "#566573", "normal", "middle")
    # o GND de cada botão (o da FICHA sai pela esquerda: à direita está o START)
    lado = -1 if nome == "FICHA" else 1
    fio([(cx + lado * w / 2, BY_TOPO + 85), (cx + lado * (w / 2 + 34), BY_TOPO + 85)], COR["GND"], 6)
    bandeira(cx + lado * (w / 2 + 68), BY_TOPO + 66, "GND", COR["GND"], size=18)
txt(1760, BY_TOPO + 268, "(o START da Zero Delay também vale)", 20, "#1e8449", "bold", "middle")

# 5V e GND do Arduino
fio([(pino_baixo["GND"], YB + 17), (pino_baixo["GND"], 1440)], COR["GND"], 8)
ponta(pino_baixo["GND"], YB + 17, COR["GND"])
bandeira(pino_baixo["GND"], 1440, "GND COMUM", COR["GND"], size=22)
fio([(pino_baixo["5V"], YB + 17), (pino_baixo["5V"], 1440)], COR["5V"], 8)
ponta(pino_baixo["5V"], YB + 17, COR["5V"])
bandeira(pino_baixo["5V"], 1440, "5V", COR["5V"], size=22)
txt(pino_baixo["GND"], 1515, "o − de tudo aqui", 19, "#566573", ancora="middle")

# ====================================================================== se for Arduino UNO
UX0, UY0, UW, UH = 40, 1370, 940, 420
txt(UX0, UY0 - 14, "SE FOR ARDUINO UNO: os mesmos nomes, nos conectores da placa", 24, "#0b1f45", "bold")
ret(UX0, UY0, UW, UH, "#1d5fa8", "#123f73", 4, 20)
ret(UX0 - 18, UY0 + 70, 70, 90, "#aab7b8", "#7b7d7d", 3, 8)       # USB
ret(UX0 - 18, UY0 + 250, 60, 80, "#17202a", r=8)                 # P4 (fonte)
txt(UX0 + 470, UY0 + 212, "ARDUINO UNO", 28, "#ffd43b", "bold", "middle")
txt(UX0 + 470, UY0 + 240, "(USB para a TV Box)", 18, "#d6eaf8", "normal", "middle")
USO = {"2": ("S1", COR["S1"]), "3": ("S2", COR["S2"]), "4": ("S3", COR["S3"]), "5": ("S4", COR["S4"]),
       "6": ("LED", COR["LED"]), "7": ("S5", COR["S5"]), "8": ("RELÉ", COR["RELE"]), "9": ("SERVO", COR["SERVO"]),
       "A0": ("CFG", COR["CFG"]), "A1": ("START", COR["START"]), "A2": ("FICHA", COR["FICHA"]),
       "5V": ("5V", COR["5V"]), "GND": ("GND", COR["GND"])}
DIG = ["SCL", "SDA", "AREF", "GND", "13", "12", "11", "10", "9", "8", "", "7", "6", "5", "4", "3", "2", "1", "0"]
POT = ["", "IOREF", "RST", "3V3", "5V", "GND", "GND", "VIN", "", "A0", "A1", "A2", "A3", "A4", "A5"]
def conector(nomes, x0, y, passo, rotulo_em_cima):
    for i, n in enumerate(nomes):
        if not n:
            continue
        x = x0 + i * passo
        uso = USO.get(n) if not (n == "GND" and rotulo_em_cima) else None
        if n == "GND" and not rotulo_em_cima and i != 5:
            uso = None
        ret(x - 16, y - 16, 32, 32, "#17202a", "#000000", 2, 4)
        circ(x, y, 8, uso[1] if uso else "#d4ac0d")
        ty = y - 26 if rotulo_em_cima else y + 40
        txt(x, ty, n, 15, "#ffffff" if uso else "#aed6f1", "bold" if uso else "normal", "middle")
        if uso:
            # nomes em duas alturas (vizinhos não se encostam)
            alto = (i % 2 == 0)
            ly = (y - 50 - (24 if alto else 0)) if rotulo_em_cima else (y + 64 + (24 if alto else 0))
            ret(x - len(uso[0]) * 6.6 - 8, ly - 17, len(uso[0]) * 13.2 + 16, 23, uso[1], r=6)
            txt(x, ly, uso[0], 16, "#ffffff", "bold", "middle")
conector(DIG, UX0 + 60, UY0 + 125, 47, True)
conector(POT, UX0 + 240, UY0 + 295, 47, False)
txt(UX0 + 44, UY0 + 172, "DIGITAL", 16, "#d6eaf8")
txt(UX0 + 240, UY0 + 255, "POWER", 16, "#d6eaf8")
txt(UX0 + 663, UY0 + 255, "ANALOG IN", 16, "#d6eaf8")

# ====================================================================== quadros de baixo
def quadro(x, y, w, h, titulo, cor, linhas, size=27):
    ret(x, y, w, h, "#ffffff", cor, 5, 20)
    ret(x, y, w, 64, cor, r=20)
    ret(x, y + 34, w, 30, cor)
    txt(x + 30, y + 46, titulo, 32, "#ffffff", "bold", fam=TIT)
    linhas_txt(x + 34, y + 110, linhas, size)


quadro(40, 1820, 1080, 620, "COMO DAR START", COR["START"], [
    "**1. Ligue o botão START entre o A1 e o GND",
    "   (ou use o START da placa Zero Delay).",
    "**2. Na tela de espera aperte START:",
    "   a PORTA DAS BOLAS ABRE (servo vai a 90°",
    "   ou o relé liga) e aparece “QUANTOS VÃO JOGAR?”.",
    "   START de novo em 4 s = 2 jogadores.",
    "**3. Escolha o amigo rolando a bola:",
    "   esquerda = Bob, direita = Mia, meio = confirma.",
    "**4. Jogue: a bola que passa num sensor vira a jogada.",
    "**5. Fim da partida: a porta FECHA sozinha.",
    "   Modo fichas: precisa de ficha (A2) antes do START.",
])
quadro(1160, 1820, 1080, 620, "PRIMEIRA VEZ (passo a passo)", "#1f6fb2", [
    "**1. Grave o strike_kids.ino pela IDE do Arduino",
    "   (Nano clone: Processador “ATmega328P (Old Bootloader)”).",
    "**2. Monitor Serial a 9600: aparece OLA:STRIKE_KIDS:1.",
    "   Passe a mão nos sensores: S:1 ... S:5.",
    "   Botões: CFG, START, FICHA.",
    "**3. Ligue o USB do Arduino na TV Box e abra o jogo:",
    "   na janela do USB marque “Usar por padrão” e OK.",
    "**4. Botão CONFIGURAÇÃO → menu do operador:",
    "   TESTE DOS SENSORES (ao vivo) → CALIBRAR SENSORES",
    "   (pista vazia) → TESTE DA PORTA → TESTE DA CÂMERA.",
    "**5. CONFIGURAÇÃO de novo → volta ao jogo. Pronto!",
])
quadro(2280, 1820, 1080, 620, "CUIDADOS", "#c0392b", [
    "**Todos os GND juntos no GND do Arduino",
    "   (sensores, botões, relé e o − de todas as fontes).",
    "**Sensor com saída NPN — nunca PNP:",
    "   o PNP manda 12 V no pino e queima o Arduino.",
    "   Fios comuns: marrom +, azul −, preto = sinal.",
    "   Antes de ligar, meça o preto: nunca pode dar 12 V.",
    "**Servo e fita de LED com fonte própria: o 5V do",
    "   Arduino é só para o relé e sensores de 5 V.",
    "**Trava solenoide comum esquenta: no .ino use",
    "   RELE_TEMPO_MAX_S = 5 (liga 5 s e solta).",
    "**Porta ao contrário? Menu: “Porta invertida”.",
    "**Esquerda e direita trocadas? “Sensores invertidos”.",
    "**Sem fita de LED: no .ino USAR_LEDS = 0.",
    "**Sensor de 2 fios (chave): um no pino, outro no GND.",
])

svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">\n' + "\n".join(partes) + "\n</svg>\n"
os.makedirs(os.path.dirname(SAIDA), exist_ok=True)
with open(SAIDA + ".svg", "w", encoding="utf-8") as f:
    f.write(svg)
print("ok:", SAIDA + ".svg")
if shutil.which("rsvg-convert"):
    subprocess.run(["rsvg-convert", "-o", SAIDA + ".png", SAIDA + ".svg"], check=True)
    subprocess.run(["rsvg-convert", "-f", "pdf", "-o", SAIDA + ".pdf", SAIDA + ".svg"], check=True)
    print("ok:", SAIDA + ".png", SAIDA + ".pdf")
else:
    print("(sem o rsvg-convert: só o .svg)", file=sys.stderr)
