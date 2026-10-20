# -*- coding: utf-8 -*-
"""
MODELOS 3D DO STRIKE KIDS
=========================

Gera as malhas do jogo (personagens — ver personagens.py —, pinos, cenário) a partir das formas do
sdf.py e grava em tools/modelos/saida/*.bin + *.json.

Depois rode o "assador" do Godot, que transforma isso em recursos nativos
(.res / .scn) dentro de res://modelos/:

    python3 tools/modelos/modelos.py
    godot --headless --path . --script res://tools/modelos/assar_modelos.gd

Medidas em metros. O personagem olha para +Z, os pés no chão (y = 0).
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sdf import (Capsula, CaixaRedonda, CilindroRedondo, ConeRedondo, Deslocada,  # noqa: E402
                 Elipsoide, Esfera, Intersecao, Pacote, Pintura, SemiEspaco,
                 Toro, Torno, coracao_2d, estrela_2d, gerar_malha, hex_cor,
                 juntar, rot_x, rot_y, rot_z, unir)

SAIDA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "saida")
os.makedirs(SAIDA, exist_ok=True)

PASSO_PERSONAGEM = 0.0105


class Paleta:
    """Nomes de cor -> índice. O alfa de cada cor é a máscara do rosto."""

    def __init__(self, **cores):
        self.nomes = list(cores.keys())
        self.cores = [cores[n] for n in self.nomes]

    def __getattr__(self, nome):
        nomes = self.__dict__.get("nomes", [])
        if nome in nomes:
            return nomes.index(nome)
        raise AttributeError(nome)


def mascara_pele(paleta, nome="pele"):
    idx = paleta.nomes.index(nome)

    def f(P, cids):
        return (cids == idx).astype(np.float32)
    return f


# ===================================================================
# PINO
# ===================================================================
ALTURA_PINO = 0.48


def perfil_pino():
    ys = [0, 0.35, 1.5, 3.0, 4.5, 6.0, 7.5, 9.0, 10.0, 11.0, 12.0, 13.0, 13.8, 14.5, 14.85, 15.0]
    rs = [0.98, 1.18, 1.78, 2.26, 2.40, 2.31, 1.96, 1.38, 0.98, 0.92, 1.06, 1.26, 1.29, 1.08, 0.62, 0.0]
    k = ALTURA_PINO / 15.0
    # alisa o perfil com uma spline simples (Catmull-Rom)
    pts = []
    for i in range(len(ys) - 1):
        p0 = (ys[max(i - 1, 0)], rs[max(i - 1, 0)])
        p1 = (ys[i], rs[i])
        p2 = (ys[i + 1], rs[i + 1])
        p3 = (ys[min(i + 2, len(ys) - 1)], rs[min(i + 2, len(ys) - 1)])
        for t in np.linspace(0, 1, 6, endpoint=False):
            t2, t3 = t * t, t * t * t
            y = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            r = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            pts.append((y * k, max(r, 0.0) * k * 1.12))
    pts.append((ys[-1] * k, 0.0))
    return pts


def gerar_pino():
    pal = Paleta(branco=hex_cor("#FFFBF4", 1.0), vermelho=hex_cor("#FF3B4E"), base=hex_cor("#E9E2D8"))
    perfil = perfil_pino()
    f = Torno((0, 0, 0), perfil, pal.branco)
    k = ALTURA_PINO / 15.0
    pint = [
        Pintura(lambda P: (P[:, 1] > 10.25 * k) & (P[:, 1] < 10.85 * k), pal.vermelho),
        Pintura(lambda P: (P[:, 1] > 11.2 * k) & (P[:, 1] < 11.8 * k), pal.vermelho),
        Pintura(lambda P: P[:, 1] < 0.006, pal.base),
    ]
    m = gerar_malha(f, (-0.1, -0.01, -0.1), (0.1, 0.5, 0.1), 0.0074, pal.cores, pint,
                    mascara_rosto=mascara_pele(pal, "branco"))
    pac = Pacote()
    pac.adicionar("pino", m)
    # pontos do casco de colisão (perfil grosseiro girado)
    casco = []
    for y, r in perfil[::4] + [perfil[-2]]:
        for a in np.linspace(0, 2 * math.pi, 10, endpoint=False):
            casco.append([r * math.cos(a), y, r * math.sin(a)])
    pac.gravar(os.path.join(SAIDA, "pino"), meta={
        "rosto": {"centro": [0.0, 0.215], "tamanho": [0.15, 0.13]},
        "casco": casco, "altura": ALTURA_PINO,
    })


# ===================================================================
# CENÁRIO (objetos espalhados; o Godot posiciona as cópias)
# ===================================================================

def gerar_cenario():
    pac = Pacote()

    # --- pirulito gigante (espiral azul/amarela)
    pal = Paleta(cabo=hex_cor("#FFF6E8"), doce=hex_cor("#1E88F0"), listra=hex_cor("#FFD43B"))
    disco = CilindroRedondo((0, 2.0, 0), 0.62, 0.11, 0.1, pal.doce, rot=rot_x(math.pi / 2))
    cabo = Capsula((0, 0, 0), (0, 1.5, 0), 0.06, pal.cabo)

    def espiral(P):
        x, y = P[:, 0], P[:, 1] - 2.0
        r = np.sqrt(x * x + y * y)
        a = np.arctan2(y, x)
        return (np.abs(P[:, 2]) < 0.2) & (r > 0.03) & (np.sin(a * 1.0 + r * 15.0) > 0.25)
    m = gerar_malha(disco | cabo, (-0.7, -0.1, -0.2), (0.7, 2.7, 0.2), 0.034, pal.cores, [Pintura(espiral, pal.listra)])
    pac.adicionar("pirulito", m)

    # --- árvores fofas: verde, laranja (outono) e verde-escura
    for nome, cor_copa, cor_tronco in (("arvore_verde", "#5ED16A", "#A86B3C"), ("arvore_laranja", "#FFA23A", "#A86B3C"),
                                       ("arvore_escura", "#2FA35A", "#8E5A32")):
        pal = Paleta(tronco=hex_cor(cor_tronco), copa=hex_cor(cor_copa))
        tronco = ConeRedondo((0, 0, 0), (0, 1.3, 0), 0.16, 0.09, pal.tronco)
        rng = np.random.default_rng(len(nome))
        bolas = [Esfera((0, 1.75, 0), 0.62, pal.copa)]
        for _ in range(6):
            a = rng.uniform(0, 2 * math.pi)
            bolas.append(Esfera((0.42 * math.cos(a), 1.65 + rng.uniform(-0.1, 0.35), 0.42 * math.sin(a)), rng.uniform(0.33, 0.45), pal.copa))
        copa = unir(*bolas, k=0.18)
        m = gerar_malha(tronco.solda(copa, 0.05), (-1.15, -0.05, -1.15), (1.15, 2.75, 1.15), 0.055, pal.cores)
        pac.adicionar(nome, m)

    # --- cogumelo
    pal = Paleta(caule=hex_cor("#FFF3DC"), chapeu=hex_cor("#FF4B5C"), pinta=hex_cor("#FFFFFF"))
    caule = ConeRedondo((0, 0, 0), (0, 0.55, 0), 0.2, 0.15, pal.caule)
    chapeu = Intersecao(Elipsoide((0, 0.6, 0), (0.55, 0.42, 0.55), pal.chapeu), SemiEspaco((0, 0.62, 0), (0, -1, 0)), 0.04)

    def pintas(P):
        d = P - np.array([0, 0.6, 0])
        d = d / np.linalg.norm(d, axis=1, keepdims=True)
        out = np.zeros(len(P), dtype=bool)
        for c in ((0, 1, 0), (0.7, 0.5, 0.3), (-0.6, 0.55, 0.5), (0.2, 0.5, -0.8), (-0.5, 0.5, -0.6), (0.6, 0.45, -0.55), (-0.1, 0.55, 0.85), (0.85, 0.45, 0.4)):
            c = np.array(c) / np.linalg.norm(c)
            out |= (d @ c) > 0.965
        return out & (P[:, 1] > 0.66)
    m = gerar_malha(caule.solda(chapeu, 0.04), (-0.62, -0.05, -0.62), (0.62, 1.1, 0.62), 0.034, pal.cores, [Pintura(pintas, pal.pinta)])
    pac.adicionar("cogumelo", m)

    # --- bengala doce (listrada)
    pal = Paleta(branco=hex_cor("#FFFFFF"), vermelho=hex_cor("#FF3B4E"))
    haste = Capsula((0, 0, 0), (0, 1.6, 0), 0.085, pal.branco)
    curva = Intersecao(Toro((0.28, 1.6, 0), 0.28, 0.085, pal.branco, rot=rot_x(math.pi / 2)), SemiEspaco((0, 1.6, 0), (0, -1, 0)))

    def listras(P):
        a = np.arctan2(P[:, 2], P[:, 0])
        return np.sin(P[:, 1] * 22.0 + a * 1.0 + P[:, 0] * 22.0) > 0.2
    m = gerar_malha(haste | curva, (-0.15, -0.1, -0.15), (0.7, 2.0, 0.15), 0.024, pal.cores, [Pintura(listras, pal.vermelho)])
    pac.adicionar("bengala", m)

    # --- caixa de presente
    pal = Paleta(caixa=hex_cor("#4FC3F7"), fita=hex_cor("#FFD43B"))
    caixa = CaixaRedonda((0, 0.35, 0), (0.36, 0.35, 0.36), 0.05, pal.caixa)
    tampa = CaixaRedonda((0, 0.72, 0), (0.39, 0.06, 0.39), 0.04, pal.caixa)
    laco1 = Toro((-0.12, 0.83, 0), 0.1, 0.035, pal.fita, rot=rot_z(math.pi / 2 - 0.5) @ rot_y(0.0))
    laco2 = Toro((0.12, 0.83, 0), 0.1, 0.035, pal.fita, rot=rot_z(-math.pi / 2 + 0.5))
    fita_pint = Pintura(lambda P: (np.abs(P[:, 0]) < 0.07) | (np.abs(P[:, 2]) < 0.07), pal.fita)
    m = gerar_malha(caixa | tampa | laco1 | laco2, (-0.45, -0.05, -0.45), (0.45, 1.0, 0.45), 0.032, pal.cores, [fita_pint])
    pac.adicionar("presente", m)

    # --- rosquinha gigante (donut)
    pal = Paleta(massa=hex_cor("#E9A55B"), cobertura=hex_cor("#7B4A2E"), conf1=hex_cor("#FFFFFF"), conf2=hex_cor("#FFD43B"), conf3=hex_cor("#4FC3F7"))
    donut = Toro((0, 0.3, 0), 0.5, 0.28, pal.massa, rot=rot_x(math.pi / 2) @ rot_x(-math.pi / 2))
    rng = np.random.default_rng(7)
    conf = rng.normal(size=(140, 3))
    conf /= np.linalg.norm(conf, axis=1, keepdims=True)

    def cobertura(P):
        return P[:, 1] > 0.33 + 0.04 * np.sin(np.arctan2(P[:, 2], P[:, 0]) * 7)

    def confeitos(cor_alvo):
        def f(P):
            q = P - np.array([0, 0.3, 0])
            ang = np.arctan2(q[:, 2], q[:, 0])
            u = np.floor(ang / (2 * math.pi) * 40)
            v = np.floor(np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) * 18)
            h = np.sin(u * 12.9898 + v * 78.233) * 43758.5453
            h = h - np.floor(h)
            return cobertura(P) & (P[:, 1] > 0.45) & (h > 0.86) & (np.floor(h * 100) % 3 == cor_alvo)
        return f
    m = gerar_malha(donut, (-0.85, -0.05, -0.85), (0.85, 0.65, 0.85), 0.036, pal.cores,
                    [Pintura(cobertura, pal.cobertura), Pintura(confeitos(0), pal.conf1), Pintura(confeitos(1), pal.conf2), Pintura(confeitos(2), pal.conf3)])
    pac.adicionar("donut", m)

    # --- nuvem (fofinha, base achatada)
    pal = Paleta(nuvem=hex_cor("#FFFFFF"))
    rng = np.random.default_rng(3)
    bolas = [Elipsoide((0, 0.5, 0), (1.3, 0.6, 0.8), pal.nuvem)]
    for x, y, r in ((-0.9, 0.5, 0.55), (0.9, 0.45, 0.6), (-0.3, 0.95, 0.65), (0.45, 0.9, 0.58), (1.45, 0.35, 0.4), (-1.5, 0.35, 0.38)):
        bolas.append(Esfera((x, y, rng.uniform(-0.15, 0.15)), r, pal.nuvem))
    nuvem = Intersecao(unir(*bolas, k=0.3), SemiEspaco((0, 0.2, 0), (0, -1, 0)), 0.15)
    m = gerar_malha(nuvem, (-2.1, 0.0, -1.0), (2.1, 1.7, 1.0), 0.08, pal.cores)
    pac.adicionar("nuvem", m)

    # --- balão (branco: o Godot pinta com a cor de cada cópia)
    pal = Paleta(balao=hex_cor("#FFFFFF"))
    balao = Elipsoide((0, 0.42, 0), (0.3, 0.36, 0.3), pal.balao).solda(ConeRedondo((0, 0.1, 0), (0, 0.0, 0), 0.06, 0.035, pal.balao), 0.05)
    m = gerar_malha(balao, (-0.35, -0.05, -0.35), (0.35, 0.82, 0.35), 0.034, pal.cores)
    pac.adicionar("balao", m)

    # --- cupcake
    pal = Paleta(forma=hex_cor("#4FC3F7"), bolo=hex_cor("#C98A5A"), creme=hex_cor("#FFF7E6"), cereja=hex_cor("#FF3B4E"))
    forminha = ConeRedondo((0, 0, 0), (0, 0.42, 0), 0.32, 0.42, pal.forma)
    creme = unir(Esfera((0, 0.55, 0), 0.38, pal.creme), Esfera((0, 0.82, 0), 0.25, pal.creme), Esfera((0, 1.0, 0), 0.13, pal.creme), k=0.12)
    cereja = Esfera((0, 1.17, 0), 0.09, pal.cereja)

    def pregas(P):
        a = np.arctan2(P[:, 2], P[:, 0])
        return (P[:, 1] < 0.42) & (np.sin(a * 16) > 0.0)
    pal.cores[pal.forma]  # noqa
    m = gerar_malha(forminha.solda(creme, 0.04) | cereja, (-0.5, -0.05, -0.5), (0.5, 1.32, 0.5), 0.034, pal.cores,
                    [Pintura(pregas, pal.bolo)])
    pac.adicionar("cupcake", m)

    # --- arco-íris (portal no fim da pista): faixas pintadas pelo raio
    cores_ai = ["#FF4B5C", "#FF9F2E", "#FFD43B", "#5ED16A", "#4FC3F7", "#2E5BE6"]
    pal = Paleta(**{"c%d" % i: hex_cor(h) for i, h in enumerate(cores_ai)})
    R, r = 3.0, 0.42
    arco = Intersecao(Toro((0, 0, 0), R, r, 0, rot=rot_x(math.pi / 2)), SemiEspaco((0, -0.05, 0), (0, -1, 0)))
    arco = CaixaRedonda((0, 0, 0), (R + r, 0.01, 0.01), 0.005, 0).solda(arco, 0.0) if False else arco

    def faixa(i):
        def f(P):
            rr = np.sqrt(P[:, 0] ** 2 + P[:, 1] ** 2)
            lim0 = R + r - (i + 1) * (2 * r / 6)
            lim1 = R + r - i * (2 * r / 6)
            return (rr >= lim0) & (rr < lim1 + 0.01)
        return f
    m = gerar_malha(arco, (-R - r - 0.05, -0.1, -r - 0.05), (R + r + 0.05, R + r + 0.05, r + 0.05), 0.06, pal.cores,
                    [Pintura(faixa(i), i) for i in range(6)])
    pac.adicionar("arco_iris", m)

    # --- torre de circo (lateral do fim da pista): branca e vermelha, telhado azul
    pal = Paleta(parede=hex_cor("#FFFFFF"), listra=hex_cor("#E8384F"), telhado=hex_cor("#1E6FE0"), bandeira=hex_cor("#FFD43B"), janela=hex_cor("#0E2A5C"))
    corpo = CilindroRedondo((0, 1.25, 0), 0.55, 1.25, 0.08, pal.parede)
    ameia = CilindroRedondo((0, 2.6, 0), 0.66, 0.14, 0.06, pal.parede)
    telhado = ConeRedondo((0, 2.7, 0), (0, 3.9, 0), 0.62, 0.04, pal.telhado)
    pau = Capsula((0, 3.85, 0), (0, 4.35, 0), 0.02, pal.bandeira)
    bandeira = CaixaRedonda((0.14, 4.22, 0), (0.14, 0.09, 0.012), 0.01, pal.bandeira)

    def listras_torre(P):
        a = np.arctan2(P[:, 2], P[:, 0])
        return (P[:, 1] < 2.45) & (np.sin(a * 6 + P[:, 1] * 4.0) > 0.35)

    def janela(P):
        return (P[:, 2] > 0.3) & (np.abs(P[:, 0]) < 0.14) & (P[:, 1] > 1.55) & (P[:, 1] < 2.0) | \
               (P[:, 2] > 0.3) & (((P[:, 0]) ** 2 + (P[:, 1] - 2.0) ** 2) < 0.14 ** 2)
    m = gerar_malha(corpo | ameia | telhado | pau | bandeira, (-0.75, -0.05, -0.75), (0.75, 4.45, 0.75), 0.05, pal.cores,
                    [Pintura(listras_torre, pal.listra), Pintura(janela, pal.janela)])
    pac.adicionar("torre", m)

    # --- lâmpadas do letreiro (contas pequenas; o alfa guarda a fase do pisca)
    pal = Paleta(lamp=hex_cor("#FFFFFF"))
    m = gerar_malha(Esfera((0, 0, 0), 0.07, pal.lamp), (-0.09, -0.09, -0.09), (0.09, 0.09, 0.09), 0.022, pal.cores)
    pac.adicionar("lampada", m)

    # --- para-choque da canaleta (bumper listrado), 1 m de comprimento ao longo de Z
    pal = Paleta(branco=hex_cor("#FFFFFF"), vermelho=hex_cor("#FF3B4E"))
    bumper = Capsula((0, 0, -0.5), (0, 0, 0.5), 0.07, pal.branco)

    def listras_b(P):
        a = np.arctan2(P[:, 1], P[:, 0])
        return np.sin(P[:, 2] * 25.0 + a * 1.0) > 0.0
    m = gerar_malha(bumper, (-0.09, -0.09, -0.6), (0.09, 0.09, 0.6), 0.017, pal.cores, [Pintura(listras_b, pal.vermelho)])
    pac.adicionar("bumper", m)

    pac.gravar(os.path.join(SAIDA, "cenario"))


# ===================================================================
# TERRENO (malha de altura: gramado com morros nas laterais)
# ===================================================================

def gerar_terreno():
    nx, nz = 90, 110
    xs = np.linspace(-34, 34, nx)
    zs = np.linspace(-70, 18, nz)
    X, Z = np.meshgrid(xs, zs, indexing='ij')
    H = np.zeros_like(X)
    rng = np.random.default_rng(11)
    morros = [(-9, -20, 6, 2.2), (10, -26, 7, 2.6), (-14, -42, 9, 3.4), (15, -48, 10, 3.8), (0, -64, 16, 5.0),
              (-20, -10, 6, 1.8), (21, -8, 7, 2.2), (-26, -30, 9, 4.0), (27, -34, 10, 4.5), (-6, -52, 6, 2.0), (6, -58, 7, 2.4)]
    for cx, cz, r, h in morros:
        H += h * np.exp(-((X - cx) ** 2 + (Z - cz) ** 2) / (2 * r * r))
    # vale plano onde fica a pista
    plano = np.clip((np.abs(X) - 3.2) / 4.0, 0, 1)
    plano = plano * plano * (3 - 2 * plano)
    H *= plano
    H += 0.06 * np.sin(X * 0.7) * np.sin(Z * 0.55) * plano
    H -= 0.02 + 0.22 * (1.0 - plano)
    V = np.stack([X, H, Z], -1).reshape(-1, 3)
    # normais por diferença finita
    dx = np.gradient(H, xs, axis=0)
    dz = np.gradient(H, zs, axis=1)
    N = np.stack([-dx, np.ones_like(H), -dz], -1)
    N /= np.linalg.norm(N, axis=-1, keepdims=True)
    N = N.reshape(-1, 3)
    # a cor do chão vem do shader (shaders/terreno.gdshader): aqui só o relevo
    variantes = {"terreno": np.ones((nx * nz, 3))}
    idx = np.arange(nx * nz).reshape(nx, nz)
    a = idx[:-1, :-1].reshape(-1)
    b = idx[1:, :-1].reshape(-1)
    c = idx[1:, 1:].reshape(-1)
    d = idx[:-1, 1:].reshape(-1)
    T = np.concatenate([np.stack([a, b, c], -1), np.stack([a, c, d], -1)])
    # orientação: normal para cima
    e1 = V[T[:, 1]] - V[T[:, 0]]
    e2 = V[T[:, 2]] - V[T[:, 0]]
    ng = np.cross(e1, e2)
    errado = ng[:, 1] < 0
    T[errado] = T[errado][:, ::-1]
    from sdf import Malha
    pac = Pacote()
    for nome, C in variantes.items():
        C = np.concatenate([np.clip(C, 0, 1), np.zeros((len(C), 1))], -1)
        m = Malha(V.astype(np.float32), N.astype(np.float32), C.astype(np.float32), T.astype(np.int32))
        pac.adicionar(nome, m)
    pac.gravar(os.path.join(SAIDA, "terreno"))


if __name__ == "__main__":
    import personagens
    alvo = sys.argv[1:] or ["bob", "mia", "pino", "cenario", "terreno"]
    if "bob" in alvo:
        personagens.gerar_personagem("bob", personagens.bob, SAIDA)
    if "mia" in alvo:
        personagens.gerar_personagem("mia", personagens.mia, SAIDA)
    if "roupas" in alvo:   # as roupinhas de cada fase (roupas.py)
        import roupas
        for nome in ("bob", "mia"):
            for roupa in roupas.ROUPAS:
                roupas.gerar_fantasia(nome, roupa, SAIDA)
    if "pino" in alvo:
        gerar_pino()
    if "cenario" in alvo:
        gerar_cenario()
    if "terreno" in alvo:
        gerar_terreno()
