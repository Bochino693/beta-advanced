# -*- coding: utf-8 -*-
"""
OBJETOS DOS CENÁRIOS TEMÁTICOS DO STRIKE KIDS
=============================================

Quatro mundos (um por rodada), no mesmo estilo "brinquedo de vinil /
massinha" do resto do jogo: formas gordinhas, bordas redondas e cores
alegres (turquesa, azul, amarelo, laranja, verde-limão, vermelho, coral).

  * ESPAÇO ............. planeta_anel, foguete, ovni, planeta, cristal,
                          pedra_lua, estrela_3d
  * FUNDO DO MAR ....... coral, coral_roxo, alga, concha, estrela_mar, peixe,
                          agua_viva, bau, tartaruga, navio
  * SELVA DOS DINOS .... palmeira, samambaia, vulcao, ovo_dino, dino, ptero,
                          pedra, flor_gigante
  * PARQUE ............. roda_base, roda, cabine, tenda, carrossel

Uso (na pasta do projeto):

    python3 tools/modelos/temas.py               # gera todos
    python3 tools/modelos/temas.py dino ovni     # refaz só esses (os outros
                                                 # vêm do temas.bin atual)
    godot --headless --path . --script res://tools/modelos/assar_modelos.gd -- temas

O assador grava cada um em res://modelos/cenario/<nome>.res (com LODs).

CONVENÇÕES
  * metros; frente para +Z;
  * origem no centro da BASE, no chão (y = 0) — exceto os marcados CENTRO:
    planeta_anel, ovni, planeta, estrela_3d, peixe, agua_viva (centro do
    sino), ptero e roda (eixo). A cabine tem a origem no PIVÔ (em cima) e
    fica pendurada para baixo;
  * TINTA (planeta, peixe, agua_viva, cabine): quase brancos, para o jogo
    colorir cada cópia com o parâmetro `tinta` do toon (os olhos continuam
    escuros);
  * bases largas (vulcao, tenda, carrossel, roda_base) ficam ABERTAS por
    baixo, enterradas uns centímetros no chão: economiza triângulos que
    nunca aparecem;
  * alfa da cor do vértice = 0 em tudo (o alfa é máscara só dos personagens).
"""
import json
import math
import multiprocessing as mp
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sdf import (Capsula, CaixaRedonda, CilindroRedondo, ConeRedondo, Deslocada,  # noqa: E402
                 Elipsoide, Esfera, Forma, Intersecao, Malha, Pacote, Pintura,
                 Primitiva, SemiEspaco, Toro, Torno, comprimento, estrela_2d,
                 gerar_malha, gradiente, hex_cor, juntar, rot_x, rot_y, rot_z,
                 smax, smin, unir)
from modelos import SAIDA, Paleta  # noqa: E402

PI = math.pi
CIMA = np.array([0.0, 1.0, 0.0])

# cores da casa (sRGB)
OLHO = "#2B1F3F"
BRILHO = "#FFFFFF"
BOCHECHA = "#FF9BB0"


# =================================================================== utilidades

def norm(v):
    v = np.asarray(v, dtype=np.float64)
    return v / np.linalg.norm(v)


def eixos(z, cima=(0.0, 1.0, 0.0)):
    """Rotação (colunas = eixos x, y, z locais no mundo) com o z local = `z`."""
    z = norm(z)
    x = np.cross(cima, z)
    if np.linalg.norm(x) < 1e-6:
        x = np.cross((1.0, 0.0, 0.0), z)
    x = norm(x)
    return np.stack([x, np.cross(z, x), z], axis=1)


def eixos_y(y, giro=0.0):
    """Rotação com o y local = `y` (para cristais e postes inclinados)."""
    y = norm(y)
    ref = np.array([0.0, 0.0, 1.0]) if abs(y[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    x = norm(np.cross(y, ref))
    z = np.cross(x, y)
    m = np.stack([x, y, z], axis=1)
    return m @ rot_y(giro)


def girar_pontos(pts, rot, desloc=(0.0, 0.0, 0.0)):
    """Aplica rot (local -> mundo) em pontos (linhas) e translada."""
    return np.asarray(pts, dtype=np.float64) @ np.asarray(rot).T + np.asarray(desloc, dtype=np.float64)


def superficie(forma, dentro, direcao, t_max=2.0):
    """Ponto (e normal) onde o raio que sai de `dentro` fura a superfície."""
    p0 = np.asarray(dentro, dtype=np.float64)
    d = norm(direcao)
    ts = np.linspace(0.0, t_max, 801)
    D = forma.d(p0[None] + ts[:, None] * d[None])
    if D[0] >= 0 or not (D > 0).any():
        raise ValueError("superficie(): o raio não atravessa a forma")
    j = int(np.argmax(D > 0))
    a, b = ts[j - 1], ts[j]
    for _ in range(48):
        m = 0.5 * (a + b)
        if forma.d((p0 + d * m)[None])[0] < 0:
            a = m
        else:
            b = m
    p = p0 + d * a
    return p, gradiente(forma, p[None])[0]


def arestas_abertas(m, abaixo_de=None):
    """Quantas arestas têm um triângulo só (0 = malha fechada). Com
    abaixo_de, ignora a borda de baixo das bases enterradas."""
    # solda vértices no mesmo lugar: o gerador joga fora triângulos de área
    # zero, o que deixa arestas "soltas" sem buraco de verdade
    _, ids = np.unique(np.round(m.v.astype(np.float64) / 1e-5).astype(np.int64), axis=0, return_inverse=True)
    T = ids.reshape(-1)[m.i.astype(np.int64)]
    T = T[(T[:, 0] != T[:, 1]) & (T[:, 1] != T[:, 2]) & (T[:, 2] != T[:, 0])]
    E = np.sort(np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]]), axis=1)
    u, c = np.unique(E, axis=0, return_counts=True)
    soltas = u[c == 1]
    if abaixo_de is not None and len(soltas):
        y = np.zeros(ids.max() + 1)
        y[ids.reshape(-1)] = m.v[:, 1]
        soltas = soltas[np.max(y[soltas], axis=1) > abaixo_de]
    return len(soltas)


def caixa_auto(forma, rmin, rmax, pg):
    """Caixa justa (com folga) em volta da forma, achada numa grade grossa."""
    rmin, rmax = np.asarray(rmin, dtype=np.float64), np.asarray(rmax, dtype=np.float64)
    n = np.ceil((rmax - rmin) / pg).astype(int) + 1
    xs = [rmin[i] + np.arange(n[i]) * pg for i in range(3)]
    X, Y, Z = np.meshgrid(*xs, indexing='ij')
    P = np.stack([X, Y, Z], -1).reshape(-1, 3)
    D = forma.d(P)
    Q = P[D < pg]
    if len(Q) == 0:
        raise ValueError("forma vazia na região de busca")
    toca_min = Q.min(0) <= rmin + 0.5 * pg
    toca_max = Q.max(0) >= rmax - 0.5 * pg
    return Q.min(0) - 2.0 * pg, Q.max(0) + 2.0 * pg, toca_min, toca_max


def malha(nome, forma, passo, pal, pint=(), regiao=((-6, -1, -6), (6, 8, 6)), chao=None):
    """gerar_malha com a caixa calculada sozinha (nunca corta um pedaço).
    chao: se dado, a malha fica aberta embaixo nessa altura (base enterrada)."""
    rmin, rmax = np.asarray(regiao[0], dtype=np.float64), np.asarray(regiao[1], dtype=np.float64)
    pg = max(passo * 2.0, float((rmax - rmin).max()) / 90.0)
    lo, hi, tmin, tmax = caixa_auto(forma, rmin, rmax, pg)
    if chao is not None:
        lo[1] = chao
        tmin[1] = False
    if tmin.any() or tmax.any():
        print("  AVISO: %s encosta na borda da região de busca (%s %s)" % (nome, tmin, tmax))
    m = gerar_malha(forma, lo, hi, passo, pal.cores, pint)
    abertas = arestas_abertas(m, abaixo_de=(chao + 2 * passo) if chao is not None else None)
    if abertas:
        print("  AVISO: %s tem %d arestas abertas (buraco na malha?)" % (nome, abertas))
    if "/" in nome or os.environ.get("TEMAS_DETALHE"):
        print("      · %-24s %6d triângulos" % (nome, len(m.i)))
    return m


def suavizar_normais(m, vezes=2):
    """Média das normais com as vizinhas: some com vinquinhos de poucos graus
    que o toon (luz em duas faixas) transformaria em risquinhos."""
    N = m.n.astype(np.float64)
    T = m.i
    for _ in range(vezes):
        S = N.copy()
        for a, b in ((0, 1), (1, 2), (2, 0)):
            np.add.at(S, T[:, a], N[T[:, b]])
            np.add.at(S, T[:, b], N[T[:, a]])
        tam = np.linalg.norm(S, axis=1, keepdims=True)
        N = np.where(tam > 1e-6, S / np.maximum(tam, 1e-12), N)
    return Malha(m.v, N.astype(np.float32), m.c, m.i)


def sorte(n, semente):
    """Direções 'aleatórias' bem espalhadas (espiral de Fibonacci embaralhada)."""
    i = np.arange(n) + 0.5
    phi = np.arccos(1 - 2 * i / n)
    th = PI * (1 + 5 ** 0.5) * i
    d = np.stack([np.cos(th) * np.sin(phi), np.cos(phi), np.sin(th) * np.sin(phi)], -1)
    rng = np.random.default_rng(semente)
    return d[rng.permutation(n)]


def dentro_esferas(P, centros, raios):
    m = np.zeros(len(P), dtype=bool)
    for c, r in zip(centros, raios):
        m |= comprimento(P - np.asarray(c)) < r
    return m


def na_cor(forma, cor_id, regiao):
    """Pintura só onde a cor de base (da forma) é `cor_id`."""
    def f(P):
        return regiao(P) & (forma.dc(P)[1] == cor_id)
    return f


# =================================================================== malhas diretas
# Tubos e bolinhas feitos direto (sem SDF): para estruturas finas — aros e
# raios da roda-gigante, pernas, postes, mastros — saem redondinhos com bem
# menos triângulos que a grade do SDF precisaria.

def malha_crua(V, N, T, pal, cor_id, pint=()):
    V = np.asarray(V, dtype=np.float64)
    N = np.asarray(N, dtype=np.float64)
    T = np.asarray(T, dtype=np.int64)
    e1 = V[T[:, 1]] - V[T[:, 0]]
    e2 = V[T[:, 2]] - V[T[:, 0]]
    errado = np.sum(np.cross(e1, e2) * (N[T[:, 0]] + N[T[:, 1]] + N[T[:, 2]]), axis=1) < 0
    T[errado] = T[errado][:, ::-1]
    cids = np.broadcast_to(np.asarray(cor_id), (len(V),)).copy()
    for p in pint:
        cids = np.where(p.regiao(V), p.cor_id, cids)
    C = np.array(pal.cores, dtype=np.float64)[cids]
    return Malha(V.astype(np.float32), N.astype(np.float32), C.astype(np.float32), T.astype(np.int32))


def tubo(pontos, raio, pal, cor_id, lados=12, fechado=False, tampa=True, normal_fixa=None,
         tangentes=None, aneis=4, pint=()):
    """Tubo ao longo de uma polilinha (raio por ponto ou fixo), com tampas
    redondas nas pontas (se aberto)."""
    P = np.asarray(pontos, dtype=np.float64)
    M = len(P)
    r = np.broadcast_to(np.asarray(raio, dtype=np.float64), (M,))
    if tangentes is not None:
        Tg = np.asarray(tangentes, dtype=np.float64)
    elif fechado:
        Tg = np.roll(P, -1, 0) - np.roll(P, 1, 0)
    else:
        Tg = np.gradient(P, axis=0)
    Tg = Tg / np.linalg.norm(Tg, axis=1, keepdims=True)
    if normal_fixa is not None:
        nf = np.asarray(normal_fixa, dtype=np.float64)
        N = nf[None] - (Tg @ nf)[:, None] * Tg
        N /= np.linalg.norm(N, axis=1, keepdims=True)
    else:
        N = np.zeros_like(P)
        ref = np.array([1.0, 0.0, 0.0]) if abs(Tg[0, 0]) < 0.9 else np.array([0.0, 1.0, 0.0])
        N[0] = norm(np.cross(Tg[0], ref))
        for i in range(1, M):
            n = N[i - 1] - (N[i - 1] @ Tg[i]) * Tg[i]
            N[i] = n / np.linalg.norm(n)
    B = np.cross(Tg, N)
    phi = np.linspace(0, 2 * PI, lados, endpoint=False)
    rad = np.cos(phi)[None, :, None] * N[:, None, :] + np.sin(phi)[None, :, None] * B[:, None, :]
    verts = [(P[:, None, :] + r[:, None, None] * rad).reshape(-1, 3)]
    norms = [rad.reshape(-1, 3)]
    idx = np.arange(M * lados).reshape(M, lados)
    tris = []
    for i in range(M if fechado else M - 1):
        a, b = idx[i], idx[(i + 1) % M]
        tris += [np.stack([a, b, np.roll(b, -1)], 1), np.stack([a, np.roll(b, -1), np.roll(a, -1)], 1)]
    base = M * lados
    if not fechado and tampa:
        for k, sinal in ((0, -1.0), (M - 1, 1.0)):
            ant = idx[k]
            t = Tg[k] * sinal
            for j in range(1, aneis):
                al = 0.5 * PI * j / aneis
                verts.append(P[k] + t * r[k] * math.sin(al) + r[k] * math.cos(al) * rad[k])
                norms.append(math.cos(al) * rad[k] + math.sin(al) * t)
                cur = base + np.arange(lados)
                base += lados
                tris += [np.stack([ant, cur, np.roll(cur, -1)], 1), np.stack([ant, np.roll(cur, -1), np.roll(ant, -1)], 1)]
                ant = cur
            verts.append((P[k] + t * r[k])[None])
            norms.append(t[None])
            tris.append(np.stack([ant, np.full(lados, base), np.roll(ant, -1)], 1))
            base += 1
    return malha_crua(np.concatenate(verts), np.concatenate(norms), np.concatenate(tris), pal, cor_id, pint)


def bolinha(c, r, pal, cor_id, lados=14, pint=()):
    c = np.asarray(c, dtype=np.float64)
    return tubo([c - (0, 1e-5, 0), c + (0, 1e-5, 0)], r, pal, cor_id, lados=lados, aneis=lados // 3, pint=pint)


def arco(R, a0, a1, r, pal, cor_id, segs=12, lados=12, centro=(0.0, 0.0, 0.0)):
    """Pedaço de aro no plano XY (eixo Z), sem tampas: vários arcos de cores
    diferentes encaixam sem fresta e com a troca de cor bem nítida."""
    a = np.linspace(a0, a1, segs + 1)
    pts = np.stack([R * np.cos(a), R * np.sin(a), np.zeros_like(a)], 1) + np.asarray(centro)
    tg = np.stack([-np.sin(a), np.cos(a), np.zeros_like(a)], 1)
    return tubo(pts, r, pal, cor_id, lados=lados, tampa=False, normal_fixa=(0, 0, 1), tangentes=tg)


def torno_gomos(perfil, cores, pal, segs=6, fase=0.0):
    """Sólido de revolução (eixo Y) feito direto, em gomos de cores
    alternadas com a divisa nítida (lona de tenda, telhado de carrossel).
    perfil: (y, raio) de baixo para cima; cores: cor_id de cada gomo."""
    P = np.asarray(perfil, dtype=np.float64)
    M = len(P)
    d = np.diff(P, axis=0)
    ns = np.stack([d[:, 0], -d[:, 1]], 1)            # normal do trecho no plano (r, y)
    ns /= np.linalg.norm(ns, axis=1, keepdims=True)
    nv = np.zeros((M, 2))
    nv[:-1] += ns
    nv[1:] += ns
    nv /= np.linalg.norm(nv, axis=1, keepdims=True)
    G = len(cores)
    V, N, C, T = [], [], [], []
    base = 0
    for g in range(G):
        a = fase + 2 * PI * (g + np.linspace(0, 1, segs + 1)) / G
        ca, sa = np.cos(a)[None, :], np.sin(a)[None, :]
        r, y = P[:, 1:2], P[:, 0:1]
        V.append(np.stack([r * ca, y + 0 * ca, r * sa], -1).reshape(-1, 3))
        N.append(np.stack([nv[:, 0:1] * ca, nv[:, 1:2] + 0 * ca, nv[:, 0:1] * sa], -1).reshape(-1, 3))
        C.append(np.full(M * (segs + 1), cores[g]))
        ix = base + np.arange(M * (segs + 1)).reshape(M, segs + 1)
        a0, a1, b0, b1 = ix[:-1, :-1], ix[:-1, 1:], ix[1:, :-1], ix[1:, 1:]
        T.append(np.stack([a0, b0, b1], -1).reshape(-1, 3))
        T.append(np.stack([a0, b1, a1], -1).reshape(-1, 3))
        base += M * (segs + 1)
    N = np.concatenate(N)
    N[np.linalg.norm(N, axis=1) < 1e-9] = (0, 1, 0)
    T = np.concatenate(T)
    V = np.concatenate(V)
    area = np.linalg.norm(np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]]), axis=1)
    return malha_crua(V, N, T[area > 1e-12], pal, np.concatenate(C))


def adesivo_porta(R, larg, alt, borda, pal, cor_porta, cor_moldura, afasta=0.012):
    """Porta em arco 'colada' na parede cilíndrica (raio R) de frente para
    +Z, com moldura: contorno redondinho e nítido, poucos triângulos."""
    pecas = []

    def folha(F, cor, nu, nv):
        s_, t_ = np.meshgrid(np.linspace(0, 1, nu + 1), np.linspace(0, 1, nv + 1), indexing='ij')
        u, v = F(s_.reshape(-1), t_.reshape(-1))
        ang = u / R
        Rr = R + afasta
        V = np.stack([Rr * np.sin(ang), v, Rr * np.cos(ang)], 1)
        N = np.stack([np.sin(ang), 0 * v, np.cos(ang)], 1)
        ix = np.arange((nu + 1) * (nv + 1)).reshape(nu + 1, nv + 1)
        a0, a1, b0, b1 = ix[:-1, :-1], ix[:-1, 1:], ix[1:, :-1], ix[1:, 1:]
        T = np.concatenate([np.stack([a0, b0, b1], -1).reshape(-1, 3), np.stack([a0, b1, a1], -1).reshape(-1, 3)])
        area = np.linalg.norm(np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]]), axis=1)
        pecas.append(malha_crua(V, N, T[area > 1e-12], pal, cor))
    w, h, b = larg, alt, borda
    folha(lambda s_, t_: (-w + 2 * w * s_, h * t_), cor_porta, 6, 6)
    folha(lambda s_, t_: (w * s_ * np.cos(PI * t_), h + w * s_ * np.sin(PI * t_)), cor_porta, 4, 16)
    folha(lambda s_, t_: (w + b * s_, h * t_), cor_moldura, 1, 6)
    folha(lambda s_, t_: (-w - b * s_, h * t_), cor_moldura, 1, 6)
    folha(lambda s_, t_: ((w + b * s_) * np.cos(PI * t_), h + (w + b * s_) * np.sin(PI * t_)), cor_moldura, 1, 16)
    return juntar(pecas)


# =================================================================== formas extras

class Arredondada(Forma):
    """Infla a forma (arredonda as quinas vivas)."""

    def __init__(self, base, r):
        self.base, self.r = base, r

    def d(self, P):
        return self.base.d(P) - self.r

    def dc(self, P):
        d, c = self.base.dc(P)
        return d - self.r, c


def catmull_rom(pts, sub):
    """Densifica uma polilinha passando uma curva suave pelos pontos."""
    P = np.asarray(pts, dtype=np.float64)
    if sub <= 1 or len(P) < 3:
        return P
    ext = np.vstack([2 * P[0] - P[1], P, 2 * P[-1] - P[-2]])
    t = np.linspace(0, 1, sub, endpoint=False)[:, None]
    out = []
    for i in range(len(P) - 1):
        p0, p1, p2, p3 = ext[i], ext[i + 1], ext[i + 2], ext[i + 3]
        out.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t ** 2
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-1:])
    return np.concatenate(out)


class Fita(Primitiva):
    """Lâmina (folha, alga, asa, bandeirinha) varrida ao longo de uma
    polilinha (alisada por Catmull-Rom). Seção: 'estádio' de meia largura
    larg(t) e meia espessura esp(t); a largura fica na direção `lado`
    (projetada para ficar perpendicular à linha). desloc(t) desloca a
    lâmina para um lado. Nas juntas a seção gira em volta do eixo da dobra
    ("cotovelo"), senão sobraria uma fresta em V do lado de fora da curva."""

    def __init__(self, pontos, larg, esp, lado, cor_id, desloc=None, folga=0.3, suave=3):
        super().__init__(cor_id)
        pts = catmull_rom(pontos, suave)
        self.a, self.b = pts[:-1], pts[1:]
        seg = self.b - self.a
        L = np.linalg.norm(seg, axis=1)
        acum = np.concatenate([[0.0], np.cumsum(L)])
        self.t0, self.t1 = acum[:-1] / acum[-1], acum[1:] / acum[-1]
        self.L = L
        self.tan = seg / L[:, None]
        lado = np.broadcast_to(np.asarray(lado, dtype=np.float64), (len(seg), 3))
        lat = lado - np.sum(lado * self.tan, axis=1, keepdims=True) * self.tan
        self.lat = lat / np.linalg.norm(lat, axis=1, keepdims=True)
        self.nrm = np.cross(self.tan, self.lat)
        self.larg, self.esp, self.desloc = larg, esp, desloc
        ts = np.linspace(0, 1, 401)
        extra = np.max(larg(ts) + esp(ts) + (np.abs(desloc(ts)) if desloc else 0.0))
        self.centro = pts.mean(0)
        self.raio = float(np.max(np.linalg.norm(pts - self.centro, axis=1)) + extra)
        self.folga = folga
        # esferas envolventes de cada trecho e de cada junta (só avalia perto)
        self.meio = 0.5 * (self.a + self.b)
        self.raio_seg = 0.5 * L + extra + folga
        self.raio_junta = extra + folga

    def _avaliar(self, Q):
        melhor = np.full(len(Q), np.inf)
        t_m = np.zeros(len(Q))
        l_m = np.zeros(len(Q))

        def guarda(ix, d, t, l):
            m = d < melhor[ix]
            ix = ix[m]
            melhor[ix] = d[m]
            t_m[ix] = t[m]
            l_m[ix] = l[m]

        for i in range(len(self.a)):
            ix = np.nonzero(comprimento(Q - self.meio[i]) < self.raio_seg[i])[0]
            if len(ix) == 0:
                continue
            pa = Q[ix] - self.a[i]
            al = pa @ self.tan[i]
            h = np.clip(al / self.L[i], 0.0, 1.0)
            w = pa - (h * self.L[i])[:, None] * self.tan[i]
            t = self.t0[i] + h * (self.t1[i] - self.t0[i])
            W, E = self.larg(t), self.esp(t)
            l = w @ self.lat[i]
            if self.desloc is not None:
                l = l - self.desloc(t)
            n = w @ self.nrm[i]
            dl = np.maximum(np.abs(l) - np.maximum(W - E, 0.0), 0.0)
            dcr = np.sqrt(dl * dl + n * n) - E
            # só vale onde o ponto cai "dentro" do trecho; tampa reta só nas
            # duas pontas da fita (o resto das juntas fica com os cotovelos)
            fora = np.zeros(len(ix))
            if i == 0:
                fora = np.maximum(fora, -al)
            if i == len(self.a) - 1:
                fora = np.maximum(fora, al - self.L[i])
            d = np.sqrt(np.maximum(dcr, 0.0) ** 2 + fora * fora) + np.where(fora > 0, 0.0, np.minimum(dcr, 0.0))
            vale = ((al >= 0.0) | (i == 0)) & ((al <= self.L[i]) | (i == len(self.a) - 1))
            guarda(ix[vale], d[vale], t[vale], l[vale])
        for j in range(1, len(self.a)):
            t0, t1 = self.tan[j - 1], self.tan[j]
            c = np.cross(t0, t1)
            s = float(np.linalg.norm(c))
            if s < 1e-6:
                continue
            ix = np.nonzero(comprimento(Q - self.a[j]) < self.raio_junta)[0]
            if len(ix) == 0:
                continue
            ax = c / s
            th = math.atan2(s, float(t0 @ t1))
            b0 = np.cross(ax, t0)
            w = Q[ix] - self.a[j]
            phi = np.arctan2(w @ t0, -(w @ b0))
            vale = (phi > 0.0) & (phi < th)
            ix, w, phi = ix[vale], w[vale], phi[vale]
            if len(ix) == 0:
                continue
            cs, sn = np.cos(phi)[:, None], np.sin(phi)[:, None]

            def girar(v):
                return cs * v + sn * np.cross(ax, v) + (1 - cs) * ax * (ax @ v)
            tj = np.full(len(ix), self.t0[j])
            W, E = self.larg(tj), self.esp(tj)
            l = np.sum(w * girar(self.lat[j - 1]), axis=1)
            if self.desloc is not None:
                l = l - self.desloc(tj)
            n = np.sum(w * girar(self.nrm[j - 1]), axis=1)
            dl = np.maximum(np.abs(l) - np.maximum(W - E, 0.0), 0.0)
            guarda(ix, np.sqrt(dl * dl + n * n) - E, tj, l)
        # longe de tudo: a folga é um limite por baixo da distância de verdade
        melhor[np.isinf(melhor)] = self.folga
        return melhor, t_m, l_m

    def d(self, P):
        dc = comprimento(P - self.centro) - self.raio
        out = dc.copy()
        perto = dc < self.folga
        if perto.any():
            out[perto] = self._avaliar(P[perto])[0]
        return out

    def param(self, P):
        """(distância, t ao longo da fita, coordenada lateral) — para pinturas."""
        return self._avaliar(P)


def param_fitas(fitas, P):
    """t e lateral da fita mais próxima de cada ponto (várias fitas)."""
    melhor = np.full(len(P), np.inf)
    t = np.zeros(len(P))
    l = np.zeros(len(P))
    k = np.zeros(len(P), dtype=np.int32)
    for i, f in enumerate(fitas):
        d, ti, li = f.param(P)
        m = d < melhor
        melhor = np.where(m, d, melhor)
        t = np.where(m, ti, t)
        l = np.where(m, li, l)
        k = np.where(m, i, k)
    return melhor, t, l, k


class PrismaHex(Primitiva):
    """Prisma hexagonal com ponta de pirâmide (cristal), bordas suavizadas."""

    def __init__(self, base, apotema, altura, ponta, cor_id, rot=None, k=0.025):
        super().__init__(cor_id)
        self.base, self.apo, self.h, self.ponta = np.asarray(base, dtype=np.float64), apotema, altura, ponta
        self.rot, self.k = rot, k

    def d(self, P):
        q = P - self.base
        if self.rot is not None:
            q = q @ self.rot
        d = -q[:, 1]
        nf = math.hypot(self.ponta, self.apo)
        for i in range(6):
            a = i * PI / 3
            s = q[:, 0] * math.cos(a) + q[:, 2] * math.sin(a)
            d = smax(d, s - self.apo, self.k)
            d = smax(d, (self.ponta * s + self.apo * (q[:, 1] - self.h) - self.apo * self.ponta) / nf, self.k)
        return d


def capsula_desigual_2d(px, py, r1, r2, h):
    """Cápsula 2D de (0,0) raio r1 até (0,h) raio r2 (Inigo Quilez)."""
    px = np.abs(px)
    b = (r1 - r2) / h
    a = math.sqrt(1.0 - b * b)
    k = -b * px + a * py
    return np.where(k < 0.0, np.sqrt(px * px + py * py) - r1,
                    np.where(k > a * h, np.sqrt(px * px + (py - h) ** 2) - r2, a * px + b * py - r1))


def estrela_bracos_2d(px, py, r_centro, r_ponta, comp, k, pontas=5):
    """Estrela feita de braços (cápsulas afinando) soldados: pontas redondas e
    os 'vales' entre os braços arredondados também (nada de quina viva)."""
    d = None
    for i in range(pontas):
        a = 2 * PI * i / pontas
        c, s = math.cos(a), math.sin(a)
        x, y = c * px + s * py, -s * px + c * py
        di = capsula_desigual_2d(x, y, r_centro, r_ponta, comp)
        d = di if d is None else smin(d, di, k)
    return d


class EstrelaFofa(Primitiva):
    """Estrela 'almofada' no plano XY local (frente +Z local): borda
    redonda e mais gordinha no meio. d2(x, y) dá a silhueta 2D."""

    def __init__(self, c, d2, borda, inchar, cor_id, rot=None, lim=0.15):
        super().__init__(cor_id)
        self.c, self.d2 = np.asarray(c, dtype=np.float64), d2
        self.borda, self.inchar, self.rot, self.lim = borda, inchar, rot, lim

    def d(self, P):
        q = P - self.c
        if self.rot is not None:
            q = q @ self.rot
        d2 = self.d2(q[:, 0], q[:, 1])
        meia = self.borda + self.inchar * np.clip(-d2, 0.0, self.lim)
        wx = d2 + self.borda
        wy = np.abs(q[:, 2]) - meia + self.borda
        return (np.sqrt(np.maximum(wx, 0) ** 2 + np.maximum(wy, 0) ** 2)
                + np.minimum(np.maximum(wx, wy), 0.0) - self.borda)


class Babado(Primitiva):
    """Saia de babados (anel em volta do eixo Y com a borda de baixo em
    ondinhas): sanefa de tenda e de carrossel."""

    def __init__(self, c, r_in, r_out, y_top, y_bot, n, prof, cor_id, arred=0.03, fase=0.0):
        super().__init__(cor_id)
        self.c = np.asarray(c, dtype=np.float64)
        self.r_in, self.r_out, self.y_top, self.y_bot = r_in, r_out, y_top, y_bot
        self.n, self.prof, self.arred, self.fase = n, prof, arred, fase

    def d(self, P):
        q = P - self.c
        rr = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2)
        th = np.arctan2(q[:, 2], q[:, 0]) + self.fase
        u = np.mod(th * self.n / (2 * PI), 1.0)
        fundo = self.y_bot + self.prof * (1.0 - np.sin(PI * u))
        a = self.arred
        dr = np.maximum(self.r_in + a - rr, rr - (self.r_out - a))
        dy = np.maximum(q[:, 1] - (self.y_top - a), (fundo + a) - q[:, 1])
        return (np.sqrt(np.maximum(dr, 0) ** 2 + np.maximum(dy, 0) ** 2)
                + np.minimum(np.maximum(dr, dy), 0.0) - a)


class Leque(Primitiva):
    """Concha de vieira: leque no plano XY local (dobradiça na origem, abre
    para +Y), bojuda para +Z local, com costelas."""

    def __init__(self, c, R, abertura, costelas, cor_id, rot=None):
        super().__init__(cor_id)
        self.c, self.R, self.ab, self.n = np.asarray(c, dtype=np.float64), R, abertura, costelas
        self.rot = rot

    def local(self, P):
        q = P - self.c
        if self.rot is not None:
            q = q @ self.rot
        return q

    def onda(self, th):
        return np.cos(2 * PI * self.n * th / (2 * self.ab))

    def d(self, P):
        q = self.local(P)
        x, y, z = q[:, 0], q[:, 1], q[:, 2]
        r = np.sqrt(x * x + y * y)
        th = np.arctan2(x, y)
        ond = self.onda(th)
        Rt = self.R * (1 - 0.1 * (th / self.ab) ** 2) + 0.022 * ond
        d2 = smax(r - Rt, (np.abs(th) - self.ab) * np.maximum(r, 0.05), 0.05)
        bojo = np.sqrt(np.clip(1 - (r / self.R) ** 2, 0, 1))
        frente = 0.05 + 0.13 * bojo + 0.022 * ond * np.clip(r / (0.35 * self.R), 0, 1)
        tras = -(0.045 + 0.06 * bojo)
        dz = np.maximum(z - frente, tras - z)
        return smax(d2, dz, 0.035)


def borda_hex(u, v, s):
    """Distância até a borda da célula da grade hexagonal (lado s) mais próxima."""
    a1 = np.array([math.sqrt(3) * s, 0.0])
    a2 = np.array([math.sqrt(3) / 2 * s, 1.5 * s])
    M = np.stack([a1, a2], 1)
    f = np.stack([u, v], -1) @ np.linalg.inv(M).T
    base = np.floor(f)
    p = np.stack([u, v], -1)
    cs, ds = [], []
    for di in (-1, 0, 1, 2):
        for dj in (-1, 0, 1, 2):
            c = (base + np.array([di, dj])) @ M.T
            cs.append(c)
            ds.append(np.sum((p - c) ** 2, axis=1))
    C = np.stack(cs, 1)
    D = np.stack(ds, 1)
    o = np.argsort(D, axis=1)
    i = np.arange(len(p))
    d1, d2 = D[i, o[:, 0]], D[i, o[:, 1]]
    c1, c2 = C[i, o[:, 0]], C[i, o[:, 1]]
    return (d2 - d1) / (2 * np.linalg.norm(c2 - c1, axis=1))


# =================================================================== rostinhos
# Olhos, sorrisos e bochechas são malhas diretas (esferas e tubinhos) meio
# enterradas na cabeça: o olho é uma esfera com o polo virado para o brilho,
# então o brilho sai redondinho e nítido com poucos triângulos.

class Rosto:
    def __init__(self, cabeca):
        self.cabeca = cabeca
        self.pal = Paleta(olho=hex_cor(OLHO), brilho=hex_cor(BRILHO), bochecha=hex_cor(BOCHECHA))
        self.malhas = []

    def olho(self, dentro, direcao, r, afundar=0.5, brilho=(0.3, 0.6, 0.15)):
        p, n = superficie(self.cabeca, dentro, direcao)
        c = p - n * r * afundar
        hb = norm(n + np.asarray(brilho))

        def claro(V, c=c, hb=hb, r=r):
            return ((V - c) @ hb) / r > 0.93
        self.malhas.append(tubo([c - hb * 1e-5, c + hb * 1e-5], r, self.pal, self.pal.olho, lados=18, aneis=7,
                                pint=[Pintura(claro, self.pal.brilho)]))
        hp = norm(n - 0.6 * np.asarray(brilho) + np.array([0.0, -0.15, 0.0]))
        self.malhas.append(bolinha(c + hp * r * 0.93, r * 0.17, self.pal, self.pal.brilho, lados=8))

    def traco(self, pontos_dentro, direcao, r, afundar=0.35):
        """Sorriso: tubinho escuro seguindo a pele."""
        cs = []
        for q in pontos_dentro:
            p, n = superficie(self.cabeca, q, direcao)
            cs.append(p - n * r * afundar)
        self.malhas.append(tubo(cs, r, self.pal, self.pal.olho, lados=8, aneis=3))

    def bochecha(self, dentro, direcao, raios):
        p, n = superficie(self.cabeca, dentro, direcao)
        R = eixos(n)
        u = bolinha((0, 0, 0), 1.0, self.pal, self.pal.bochecha, lados=14)
        raios = np.asarray(raios, dtype=np.float64)
        V = (u.v * raios) @ R.T + (p - n * raios[2] * 0.3)
        N = (u.n / raios) @ R.T
        N /= np.linalg.norm(N, axis=1, keepdims=True)
        self.malhas.append(Malha(V.astype(np.float32), N.astype(np.float32), u.c, u.i))

    def gerar(self):
        return juntar(self.malhas)


def sorriso_pontos(cx, cy, z, larg, curva, n=7):
    """Pontos de um 'U' sorridente no plano XY (pontas mais altas)."""
    xs = np.linspace(-1, 1, n)
    return [(cx + larg * x, cy + curva * x * x, z) for x in xs]


# =================================================================== ESPAÇO

def planeta_anel():
    pal = Paleta(lilas=hex_cor("#4FA8FF"), claro=hex_cor("#A8D8FF"), escuro=hex_cor("#2E7BE0"),
                 anel=hex_cor("#FFB347"), anel_claro=hex_cor("#FFE066"), anel_escuro=hex_cor("#FF8A3D"))
    incl = rot_z(0.36) @ rot_x(0.30)
    planeta = Esfera((0, 0, 0), 1.6, pal.lilas)
    anel = CilindroRedondo((0, 0, 0), 2.7, 0.14, 0.13, pal.anel, rot=incl).menos(
        CilindroRedondo((0, 0, 0), 2.05, 0.8, 0.0, pal.anel, rot=incl), k=0.06)

    def local(P):
        return P @ incl

    def faixas(P, lim):
        q = local(P)
        th = np.arctan2(q[:, 2], q[:, 0])
        s = np.sin(q[:, 1] * 4.3 + 0.18 * np.sin(th * 3.0))
        return (comprimento(P) < 1.75) & (s > lim)

    def faixa_escura(P):
        q = local(P)
        th = np.arctan2(q[:, 2], q[:, 0])
        s = np.sin(q[:, 1] * 4.3 + 0.18 * np.sin(th * 3.0))
        return (comprimento(P) < 1.75) & (s < -0.72)

    def anel_raio(a, b):
        def f(P):
            q = local(P)
            rr = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2)
            return (comprimento(P) > 1.75) & (rr >= a) & (rr < b)
        return f
    pint = [Pintura(lambda P: faixas(P, 0.6), pal.claro), Pintura(faixa_escura, pal.escuro),
            Pintura(anel_raio(0.0, 2.24), pal.anel_claro), Pintura(anel_raio(2.24, 2.36), pal.anel_escuro),
            Pintura(anel_raio(2.52, 2.6), pal.anel_claro), Pintura(anel_raio(2.6, 9), pal.anel_escuro)]
    return malha("planeta_anel", planeta | anel, 0.112, pal, pint, ((-3.2, -3.2, -3.2), (3.2, 3.2, 3.2)))


def foguete():
    pal = Paleta(branco=hex_cor("#FBF8FF"), coral=hex_cor("#FF6F61"), janela=hex_cor("#7FD8FF"),
                 moldura=hex_cor("#5B4BA8"), listra=hex_cor("#2EC4B6"), bocal=hex_cor("#A59FC6"),
                 brilho=hex_cor("#FFFFFF"), estrela=hex_cor("#FFD43B"))
    perfil = [(0.30, 0.0), (0.31, 0.30), (0.42, 0.47), (0.75, 0.58), (1.3, 0.62), (1.9, 0.6), (2.3, 0.52),
              (2.65, 0.38), (2.92, 0.22), (3.08, 0.09), (3.14, 0.0)]
    corpo = Arredondada(Torno((0, 0, 0), perfil, pal.branco), 0.02)
    bocal = Arredondada(Torno((0, 0, 0), [(0.1, 0.0), (0.1, 0.27), (0.2, 0.25), (0.34, 0.2), (0.36, 0.0)], pal.bocal), 0.02)
    aletas = []
    for az in (PI, PI / 3, -PI / 3):
        dr = np.array([math.sin(az), 0.0, math.cos(az)])
        tg = np.cross(CIMA, dr)
        ev = norm(CIMA - 0.4 * dr)
        er = np.cross(ev, tg)
        aletas.append(Elipsoide(dr * 0.6 + np.array([0, 0.62, 0]), (0.36, 0.64, 0.095), pal.coral,
                                rot=np.stack([er, ev, tg], 1)))
    aletas = Intersecao(unir(*aletas), SemiEspaco((0, 0, 0), (0, -1, 0)), 0.03)
    jy = 1.82
    janela = Esfera((0, jy, 0.3), 0.37, pal.janela)
    moldura = Toro((0, jy, 0.575), 0.265, 0.07, pal.moldura, rot=rot_x(PI / 2))
    forma = unir(corpo.solda(aletas, 0.06), bocal, janela, moldura)
    ys_p, rs_p = np.array([p[0] for p in perfil]), np.array([p[1] for p in perfil])

    def aleta(P):
        return (P[:, 1] < 1.6) & (comprimento(P[:, [0, 2]]) > np.interp(P[:, 1], ys_p, rs_p) + 0.045)
    pint = [
        Pintura(aleta, pal.coral),
        Pintura(na_cor(forma, pal.branco, lambda P: P[:, 1] > 2.42), pal.coral),
        Pintura(na_cor(forma, pal.branco, lambda P: (P[:, 1] > 0.8) & (P[:, 1] < 1.0) & ~aleta(P)), pal.listra),
        Pintura(na_cor(forma, pal.branco, lambda P: (P[:, 1] > 2.3) & (P[:, 1] < 2.42)), pal.listra),
        Pintura(na_cor(forma, pal.janela, lambda P: comprimento(P - np.array([-0.08, jy + 0.09, 0.66])) < 0.065), pal.brilho),
        Pintura(na_cor(forma, pal.janela, lambda P: comprimento(P - np.array([0.07, jy - 0.08, 0.66])) < 0.03), pal.brilho),
        Pintura(na_cor(forma, pal.branco, lambda P: (P[:, 2] > 0.3) & estrela_2d(P[:, 0], P[:, 1], 0.0, 1.3, 0.18, 0.08)), pal.estrela),
    ]
    return malha("foguete", forma, 0.058, pal, pint, ((-1.5, -0.3, -1.5), (1.5, 3.6, 1.5)))


def ovni():
    pal = Paleta(casco=hex_cor("#B8C4D6"), claro=hex_cor("#E3E9F2"), barriga=hex_cor("#7E8CA6"),
                 vidro=hex_cor("#86F0FF"), brilho=hex_cor("#FFFFFF"), antena=hex_cor("#FF6F61"),
                 l0=hex_cor("#FFD43B"), l1=hex_cor("#FF6F91"), l2=hex_cor("#9BE15D"), l3=hex_cor("#4FC3F7"))
    disco = Elipsoide((0, 0, 0), (0.9, 0.2, 0.9), pal.casco)
    topo = Elipsoide((0, 0.07, 0), (0.64, 0.17, 0.64), pal.claro)
    barriga = Elipsoide((0, -0.11, 0), (0.46, 0.17, 0.46), pal.barriga)
    cupula = Intersecao(Esfera((0, 0.13, 0), 0.4, pal.vidro), SemiEspaco((0, 0.12, 0), (0, -1, 0)))
    antena = Capsula((0, 0.5, 0), (0, 0.66, 0), 0.03, pal.casco) | Esfera((0, 0.7, 0), 0.065, pal.antena)
    luzes = []
    for i in range(10):
        a = 2 * PI * i / 10 + PI / 10
        luzes.append(Esfera((0.87 * math.sin(a), 0.0, 0.87 * math.cos(a)), 0.075, pal.l0 + i % 4))
    forma = unir(unir(disco, topo, barriga, k=0.05), cupula, antena, unir(*luzes))
    pint = [Pintura(na_cor(forma, pal.vidro, lambda P: comprimento(P - np.array([-0.15, 0.44, 0.22])) < 0.09), pal.brilho)]
    return malha("ovni", forma, 0.04, pal, pint, ((-1.2, -0.6, -1.2), (1.2, 1.0, 1.2)))


def planeta():
    # TINTA: quase branco; crateras num cinza bem clarinho
    pal = Paleta(branco=hex_cor("#F7F7FB"), cratera=hex_cor("#D6D6E4"), borda=hex_cor("#FFFFFF"))
    dirs = sorte(11, 5)
    rng = np.random.default_rng(5)
    raios = rng.uniform(0.06, 0.13, len(dirs))
    furos = [Esfera(d * (0.5 + r * 0.62), r, pal.cratera) for d, r in zip(dirs, raios)]
    forma = Esfera((0, 0, 0), 0.5, pal.branco).menos(unir(*furos), k=0.03)

    def cratera(P):
        u = P / comprimento(P)[:, None]
        m = np.zeros(len(P), dtype=bool)
        for d, r in zip(dirs, raios):
            m |= (u @ d) > math.cos(r / 0.5 * 0.8)
        return m
    return malha("planeta", forma, 0.031, pal, [Pintura(cratera, pal.cratera)], ((-0.7, -0.7, -0.7), (0.7, 0.7, 0.7)))


def cristal():
    pal = Paleta(ciano=hex_cor("#5CE1F0"), roxo=hex_cor("#FFC23A"), pedra=hex_cor("#8F9AB0"),
                 ciano_claro=hex_cor("#B5F6FF"), roxo_claro=hex_cor("#FFE7A3"))
    lista = [  # base xz, inclinação, direção da inclinação, apótema, altura, ponta, cor
        ((0.0, 0.0), 0.0, 0.0, 0.15, 0.86, 0.27, pal.ciano),
        ((0.15, 0.05), 0.45, 0.2, 0.105, 0.42, 0.17, pal.roxo),
        ((-0.15, 0.06), 0.5, PI - 0.25, 0.11, 0.48, 0.18, pal.roxo),
        ((0.04, -0.14), 0.42, -PI / 2, 0.11, 0.52, 0.19, pal.ciano),
        ((-0.05, 0.16), 0.55, PI / 2 + 0.3, 0.08, 0.3, 0.13, pal.ciano),
        ((0.17, -0.13), 0.62, -0.6, 0.075, 0.28, 0.12, pal.roxo),
    ]
    prismas = []
    for (x, z), incl, az, apo, alt, ponta, cor in lista:
        eixo = np.array([math.sin(incl) * math.cos(az), math.cos(incl), math.sin(incl) * math.sin(az)])
        prismas.append(PrismaHex((x, -0.08, z), apo, alt, ponta, cor, rot=eixos_y(eixo, giro=x * 7 + z * 3)))
    pedra = Intersecao(Deslocada(Elipsoide((0, 0.0, 0), (0.36, 0.15, 0.32), pal.pedra), 0.02, 9.0),
                       SemiEspaco((0, 0, 0), (0, -1, 0)), 0.02)
    forma = unir(*prismas).solda(pedra, 0.04)

    # brilho: a face voltada para a luz (+x, +z) de cada prisma fica mais clara
    def claro(cor_base):
        def f(P):
            _, cids = forma.dc(P)
            g = gradiente(forma, P)
            return (cids == cor_base) & ((g @ norm((0.7, 0.35, 0.6))) > 0.75)
        return f
    pint = [Pintura(claro(pal.ciano), pal.ciano_claro), Pintura(claro(pal.roxo), pal.roxo_claro)]
    return malha("cristal", forma, 0.025, pal, pint, ((-0.9, -0.3, -0.9), (0.9, 1.4, 0.9)))


def pedra_lua():
    pal = Paleta(pedra=hex_cor("#ABA4CB"), cratera=hex_cor("#8C84B3"))
    base = Deslocada(Elipsoide((0, 0.1, 0), (0.47, 0.32, 0.4), pal.pedra), 0.022, 7.0)
    furos = []
    centros = [((0.12, 0.42, 0.08), 0.13), ((-0.2, 0.36, -0.05), 0.1), ((0.0, 0.3, 0.33), 0.08),
               ((0.32, 0.25, -0.12), 0.08), ((-0.3, 0.2, 0.22), 0.07)]
    for c, r in centros:
        furos.append(Esfera(c, r, pal.cratera))
    forma = Intersecao(base.menos(unir(*furos), k=0.03), SemiEspaco((0, 0, 0), (0, -1, 0)), 0.03)
    pint = [Pintura(lambda P: dentro_esferas(P, [c for c, _ in centros], [r * 1.12 for _, r in centros]), pal.cratera)]
    return malha("pedra_lua", forma, 0.025, pal, pint, ((-0.7, -0.2, -0.7), (0.7, 0.7, 0.7)))


def estrela_3d():
    pal = Paleta(amarelo=hex_cor("#FFD43B"))
    forma = EstrelaFofa((0, 0, 0), lambda x, y: estrela_bracos_2d(x, y, 0.19, 0.06, 0.355, 0.05),
                        0.06, 0.6, pal.amarelo, lim=0.12)
    return malha("estrela_3d", forma, 0.019, pal, (), ((-0.6, -0.6, -0.4), (0.6, 0.6, 0.4)))


# =================================================================== FUNDO DO MAR

def coral():
    pal = Paleta(coral=hex_cor("#FF7F66"), ponta=hex_cor("#FFB59E"), pedra=hex_cor("#B9B2DA"))
    rng = np.random.default_rng(23)
    partes, pontas = [], []
    comps = {3: 0.34, 2: 0.42, 1: 0.36, 0: 0.28}
    abre = {2: (0.8, 1.0), 1: (0.4, 0.6), 0: (0.35, 0.55)}

    def galho(a, dr, nivel, r, az0):
        b = a + dr * comps[nivel] * rng.uniform(0.85, 1.1)
        partes.append(Capsula(a, b, r, pal.coral, rb=r * 0.88))
        if nivel == 0:
            pontas.append(Esfera(b, r * 0.88 * 1.28, pal.ponta))
            return
        n = 3 if nivel == 3 else 2
        x = norm(np.cross(dr, (0.3, 0.1, 1.0)))
        y = np.cross(dr, x)
        for i in range(n):
            ang = az0 + 2 * PI * i / n + rng.uniform(-0.3, 0.3)
            incl = rng.uniform(*abre[nivel - 1])
            nova = norm(dr * math.cos(incl) + (x * math.cos(ang) + y * math.sin(ang)) * math.sin(incl))
            nova = norm(nova + np.array([0, 0.3, 0]))
            galho(b, nova, nivel - 1, r * 0.84, ang + 0.9)
    galho(np.array([0.0, -0.02, 0.0]), np.array([0.0, 1.0, 0.0]), 3, 0.13, 0.4)
    corpo = unir(*partes, k=0.05)
    pedra = Intersecao(Deslocada(Elipsoide((0, 0, 0), (0.3, 0.14, 0.28), pal.pedra), 0.02, 9.0),
                       SemiEspaco((0, 0, 0), (0, -1, 0)), 0.02)
    forma = Intersecao(unir(corpo, *pontas, k=0.04).solda(pedra, 0.06), SemiEspaco((0, 0, 0), (0, -1, 0)), 0.02)
    return malha("coral", forma, 0.031, pal, (), ((-1.4, -0.2, -1.4), (1.4, 2.0, 1.4)))


def coral_roxo():
    pal = Paleta(roxo=hex_cor("#FFC93C"), borda=hex_cor("#FFF0A8"), dentro=hex_cor("#C98A1A"), pedra=hex_cor("#C9C2B0"))
    tubos = [  # x, z, altura, raio, inclinação
        (0.0, 0.0, 1.2, 0.14, 0.0), (0.22, 0.07, 0.95, 0.125, 0.22), (-0.2, 0.1, 0.85, 0.12, 0.24),
        (0.07, -0.22, 1.0, 0.13, 0.2), (-0.14, -0.16, 0.72, 0.11, 0.28), (0.29, -0.16, 0.6, 0.1, 0.35),
        (-0.03, 0.25, 0.55, 0.1, 0.3)]
    cheios, labios, covas = [], [], []
    for x, z, h, r, incl in tubos:
        sai = norm((x, 0.0, z)) if (x or z) else np.array([0.0, 0.0, 0.0])
        eixo = norm(CIMA + sai * math.tan(incl))
        a = np.array([x, -0.05, z])
        b = a + eixo * h
        cheios.append(ConeRedondo(a, b, r * 0.78, r, pal.roxo))
        labios.append(Toro(b - eixo * 0.015, r * 0.9, 0.04, pal.borda, rot=eixos_y(eixo)))
        covas.append(Esfera(b + eixo * r * 0.62, r * 0.78, pal.dentro))
    corpo = unir(*cheios, k=0.06).solda(unir(*labios), 0.03).menos(unir(*covas), k=0.02, cor_do_corte=True)
    pedra = Intersecao(Deslocada(Elipsoide((0, 0, 0), (0.42, 0.14, 0.4), pal.pedra), 0.02, 8.0),
                       SemiEspaco((0, 0, 0), (0, -1, 0)), 0.02)
    forma = Intersecao(corpo.solda(pedra, 0.07), SemiEspaco((0, 0, 0), (0, -1, 0)), 0.02)
    return malha("coral_roxo", forma, 0.033, pal, (), ((-1.0, -0.2, -1.0), (1.0, 1.7, 1.0)))


def fita_alga(base, yaw, H, A, f, fase, larg_max, esp, cor):
    ys = np.linspace(0.0, H, 22)
    xs = A * np.sin(f * ys + fase) * (0.25 + 0.75 * ys / H) - A * math.sin(fase) * 0.25
    zs = 0.05 * np.sin(1.7 * ys + fase)
    pts = girar_pontos(np.stack([xs, ys, zs], 1), rot_y(yaw), base)
    lado = rot_y(yaw) @ np.array([1.0, 0.0, 0.0])
    return Fita(pts, lambda t: esp + larg_max * np.sin(PI * np.clip(t, 0, 1) ** 0.75) ** 0.7,
                lambda t: np.full_like(t, esp), lado, cor)


def alga():
    pal = Paleta(verde=hex_cor("#5ED16A"), limao=hex_cor("#9BE15D"), mar=hex_cor("#3FB97A"),
                 nervura=hex_cor("#C9F27A"), base=hex_cor("#2E9E6A"))
    fitas = [fita_alga((0.0, -0.05, 0.0), 0.0, 2.25, 0.16, 2.6, 0.3, 0.13, 0.045, pal.verde),
             fita_alga((0.17, -0.05, 0.1), 0.55, 1.8, 0.14, 3.0, 2.0, 0.115, 0.045, pal.limao),
             fita_alga((-0.16, -0.05, -0.04), -0.6, 1.5, 0.13, 3.3, 4.0, 0.11, 0.045, pal.mar)]
    pe = Intersecao(Elipsoide((0, 0, 0), (0.3, 0.12, 0.24), pal.base), SemiEspaco((0, 0, 0), (0, -1, 0)), 0.02)
    forma = unir(*fitas, k=0.04).solda(pe, 0.08)

    def nervura(P):
        d, t, l, _ = param_fitas(fitas, P)
        return (d < 0.03) & (np.abs(l) < 0.022) & (t > 0.05) & (t < 0.93)
    return suavizar_normais(malha("alga", forma, 0.028, pal, [Pintura(nervura, pal.nervura)], ((-1.0, -0.2, -1.0), (1.0, 2.7, 1.0))))


def concha():
    pal = Paleta(pessego=hex_cor("#FFB89A"), creme=hex_cor("#FFEBDD"), escuro=hex_cor("#FFA987"))
    incl = rot_x(-0.18)
    leque = Leque((0, 0.13, 0), 0.68, 1.24, 9, pal.pessego, rot=incl)
    orelha = CaixaRedonda((0, 0.1, 0.0), (0.19, 0.1, 0.08), 0.06, pal.pessego)
    forma = leque.solda(orelha, 0.05)

    def costela(P):
        q = leque.local(P)
        th = np.arctan2(q[:, 0], q[:, 1])
        r = np.sqrt(q[:, 0] ** 2 + q[:, 1] ** 2)
        return (leque.onda(th) > 0.25) & (r > 0.12) & (q[:, 2] > -0.01)

    pint = [Pintura(costela, pal.creme), Pintura(lambda P: P[:, 1] < 0.21, pal.escuro)]
    return malha("concha", forma, 0.021, pal, pint, ((-0.9, -0.2, -0.5), (0.9, 1.0, 0.5)))


def estrela_mar():
    pal = Paleta(laranja=hex_cor("#FF9F2E"), bolinha=hex_cor("#FFD9A0"))
    # estrela no plano XZ (uma ponta para +Z), espessura em Y
    troca = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, 1.0, 0.0]])
    est = EstrelaFofa((0, 0.03, 0), lambda x, y: estrela_bracos_2d(x, y, 0.1, 0.042, 0.255, 0.05),
                      0.03, 0.55, pal.laranja, rot=troca, lim=0.09)
    forma = Intersecao(est, SemiEspaco((0, 0, 0), (0, -1, 0)), 0.015)
    centros, raios = [(0.0, 0.0)], [0.032]
    for k in range(5):
        a = 2 * PI * k / 5
        for s, rr in ((0.1, 0.024), (0.165, 0.02), (0.22, 0.016)):
            centros.append((-s * math.sin(a), s * math.cos(a)))
            raios.append(rr)

    def bolinhas(P):
        m = np.zeros(len(P), dtype=bool)
        for (cx, cz), r in zip(centros, raios):
            m |= ((P[:, 0] - cx) ** 2 + (P[:, 2] - cz) ** 2) < r * r
        return m & (P[:, 1] > 0.045)
    return malha("estrela_mar", forma, 0.0125, pal, [Pintura(bolinhas, pal.bolinha)], ((-0.45, -0.1, -0.45), (0.45, 0.3, 0.45)))


def peixe():
    # TINTA: corpo branco, nadadeiras cinza bem clarinho; nada para +Z
    pal = Paleta(corpo=hex_cor("#FFFFFF"), nadadeira=hex_cor("#D9D9E6"), boca=hex_cor("#3A2A40"))
    corpo = Elipsoide((0, 0, 0.04), (0.13, 0.17, 0.21), pal.corpo)
    rabo = unir(Elipsoide((0, 0.075, -0.235), (0.026, 0.105, 0.07), pal.nadadeira, rot=rot_x(0.68)),
                Elipsoide((0, -0.075, -0.235), (0.026, 0.105, 0.07), pal.nadadeira, rot=rot_x(-0.68)),
                Elipsoide((0, 0.0, -0.17), (0.05, 0.07, 0.07), pal.nadadeira), k=0.035)
    dorsal = Elipsoide((0, 0.15, -0.02), (0.022, 0.07, 0.1), pal.nadadeira, rot=rot_x(-0.35))
    laterais = [Elipsoide((s * 0.12, -0.05, 0.02), (0.02, 0.045, 0.075), pal.nadadeira,
                          rot=rot_y(s * 0.6) @ rot_x(0.5)) for s in (-1, 1)]
    forma = unir(corpo, rabo, dorsal, *laterais, k=0.035)
    m = malha("peixe", forma, 0.012, pal, (), ((-0.3, -0.3, -0.4), (0.3, 0.3, 0.35)))
    rosto = Rosto(forma)
    for s in (-1, 1):
        rosto.olho((s * 0.05, 0.035, 0.1), (s * 1.0, 0.18, 0.35), 0.052, afundar=0.55, brilho=(0.0, 0.6, 0.35))
    rosto.traco(sorriso_pontos(0.0, -0.035, 0.1, 0.03, 0.014, 7), (0, 0, 1), 0.0085)
    return juntar([m, rosto.gerar()])


def agua_viva():
    # TINTA: sino branco com pintinhas cinza-claro; origem no centro do sino
    pal = Paleta(sino=hex_cor("#FFFFFF"), pinta=hex_cor("#E4E6F0"), dentro=hex_cor("#E9E9F2"), tentaculo=hex_cor("#F1F1F7"))
    sino = Intersecao(Elipsoide((0, 0, 0), (0.3, 0.27, 0.3), pal.sino), SemiEspaco((0, -0.05, 0), (0, -1, 0)), 0.04)
    babados = [Esfera((0.27 * math.cos(a), -0.055, 0.27 * math.sin(a)), 0.058, pal.sino)
               for a in np.linspace(0, 2 * PI, 12, endpoint=False)]
    corpo = sino.solda(unir(*babados), 0.04).menos(Elipsoide((0, -0.13, 0), (0.22, 0.12, 0.22), pal.dentro), k=0.03, cor_do_corte=True)
    tent = []
    for i in range(6):
        a = 2 * PI * i / 6 + 0.3
        r0 = 0.15 if i % 2 else 0.1
        pts = []
        for j, y in enumerate(np.linspace(-0.06, -0.5 - 0.06 * (i % 2), 9)):
            w = 0.035 * math.sin(j * 1.3 + i)
            pts.append(((r0 + 0.02 * j) * math.cos(a) - w * math.sin(a), y, (r0 + 0.02 * j) * math.sin(a) + w * math.cos(a)))
        for j in range(len(pts) - 1):
            ra = 0.032 - 0.0025 * j
            tent.append(Capsula(pts[j], pts[j + 1], ra, pal.tentaculo, rb=ra - 0.0025))
    forma = corpo.solda(unir(*tent, k=0.015), 0.03)
    dirs = [d for d in sorte(14, 3) if d[1] > 0.45]

    def pintas(P):
        u = P / comprimento(P)[:, None]
        m = np.zeros(len(P), dtype=bool)
        for d in dirs:
            m |= (u @ d) > 0.985
        return m & (P[:, 1] > 0.05)
    m = malha("agua_viva", forma, 0.02, pal, [Pintura(pintas, pal.pinta)], ((-0.5, -0.8, -0.5), (0.5, 0.4, 0.5)))
    rosto = Rosto(forma)
    for s in (-1, 1):
        rosto.olho((s * 0.085, 0.05, 0.0), (0, 0, 1), 0.035, afundar=0.5)
    rosto.traco(sorriso_pontos(0.0, -0.005, 0.0, 0.03, 0.014, 5), (0, 0, 1), 0.009)
    rosto.bochecha((0.15, 0.015, 0.0), (0.6, 0, 1), (0.03, 0.02, 0.008))
    rosto.bochecha((-0.15, 0.015, 0.0), (-0.6, 0, 1), (0.03, 0.02, 0.008))
    return juntar([m, rosto.gerar()])


def bau():
    pal = Paleta(madeira=hex_cor("#B8743F"), tabua=hex_cor("#A3632F"), ouro=hex_cor("#FFC93B"),
                 ouro_claro=hex_cor("#FFE27A"), buraco=hex_cor("#3A2433"))
    corpo = CaixaRedonda((0, 0.26, 0), (0.43, 0.26, 0.28), 0.05, pal.madeira)
    tampa = Intersecao(CilindroRedondo((0, 0.5, 0), 0.28, 0.43, 0.05, pal.madeira, rot=rot_z(PI / 2)),
                       SemiEspaco((0, 0.5, 0), (0, -1, 0)))
    bandas = []
    for x in (-0.27, 0.27):
        bandas.append(CaixaRedonda((x, 0.26, 0), (0.045, 0.265, 0.297), 0.025, pal.ouro))
        bandas.append(Intersecao(CilindroRedondo((x, 0.5, 0), 0.297, 0.045, 0.025, pal.ouro, rot=rot_z(PI / 2)),
                                 SemiEspaco((0, 0.5, 0), (0, -1, 0))))
    aro = CaixaRedonda((0, 0.5, 0), (0.447, 0.032, 0.297), 0.025, pal.ouro)
    forma = unir(corpo, tampa, *bandas, aro)

    def tabuas(P):
        corpo_ = (P[:, 1] < 0.47) & (np.floor(P[:, 1] / 0.155) % 2 == 1)
        ang = np.arctan2(P[:, 2], P[:, 1] - 0.5)
        tampa_ = (P[:, 1] > 0.53) & (np.floor((ang + 0.2) / 0.5) % 2 == 1)
        return corpo_ | tampa_
    m = malha("bau", forma, 0.029, pal, [Pintura(tabuas, pal.tabua)], ((-0.7, -0.2, -0.5), (0.7, 1.0, 0.5)))
    # fechadura: malha fina à parte (o buraco da chave sai nítido)
    pf = Paleta(ouro=hex_cor("#FFD54F"), buraco=hex_cor("#3A2433"))
    fech = CaixaRedonda((0, 0.46, 0.3), (0.075, 0.095, 0.03), 0.025, pf.ouro)

    def buraco(P):
        return (P[:, 2] > 0.315) & ((((P[:, 0]) ** 2 + (P[:, 1] - 0.48) ** 2) < 0.022 ** 2) |
                                     ((np.abs(P[:, 0]) < 0.009) & (P[:, 1] > 0.425) & (P[:, 1] < 0.48)))
    mf = malha("bau/fechadura", fech, 0.011, pf, [Pintura(buraco, pf.buraco)], ((-0.2, 0.25, 0.15), (0.2, 0.65, 0.45)))
    return juntar([m, mf])


def navio():
    """Navio pirata naufragado, INTEIRO (fica no fundo do mar atrás dos pinos,
    com os mastros e as velas aparecendo por cima do arco): casco gordinho
    de tábuas com faixa dourada e escotilhas, castelos de proa e de popa,
    três mastros com cesto da gávea, velas estufadas listradas e a
    bandeira de caveira. Proa para +Z, base em y = 0."""
    pal = Paleta(madeira=hex_cor("#B8743F"), tabua=hex_cor("#9A5B2C"), conves=hex_cor("#E2B279"),
                 ouro=hex_cor("#FFC93B"), vidro=hex_cor("#2B3A6B"), mastro=hex_cor("#7A4A2A"))
    # casco: a metade de baixo de um ovo comprido (o convés é o corte)
    casco = Intersecao(Elipsoide((0, 1.0, 0), (1.0, 1.15, 3.0), pal.madeira), SemiEspaco((0, 1.55, 0), (0, 1, 0)), 0.06)
    popa = CaixaRedonda((0, 1.7, -2.05), (0.82, 0.5, 0.78), 0.16, pal.madeira)
    proa = CaixaRedonda((0, 1.62, 2.05), (0.62, 0.34, 0.55), 0.14, pal.madeira)
    gurupes = Capsula((0, 1.85, 2.4), (0, 2.45, 4.05), 0.07, pal.mastro)
    corpo = unir(casco.solda(popa, 0.12).solda(proa, 0.1), gurupes)
    # base enterrada uns centímetros (está pousado na areia)
    corpo = Intersecao(corpo, SemiEspaco((0, -0.02, 0), (0, -1, 0)), 0.04)
    mastros = []
    for z, y0, y1, r in ((0.3, 1.5, 6.05, 0.095), (1.85, 1.5, 4.95, 0.08), (-1.95, 2.15, 4.75, 0.075)):
        mastros.append(Capsula((0, y0, z), (0, y1, z), r, pal.mastro))
        # vergas (as varas das velas)
        for yv, meia in ((y1 - 0.55, 0.95 if z == 0.3 else 0.78), (y0 + (y1 - y0) * 0.38, 1.05 if z == 0.3 else 0.86)):
            mastros.append(Capsula((-meia, yv, z + 0.1), (meia, yv, z + 0.1), 0.05, pal.mastro))
    cesto = CilindroRedondo((0, 5.62, 0.3), 0.3, 0.12, 0.04, pal.mastro).menos(
        CilindroRedondo((0, 5.72, 0.3), 0.2, 0.2, 0.0, pal.mastro))
    forma = unir(corpo, *mastros, cesto)

    def casco_lado(P):
        return (P[:, 1] < 1.5) & (np.abs(P[:, 0]) > 0.15)

    def tabuas(P):
        return casco_lado(P) & (np.floor(P[:, 1] / 0.21) % 2 == 1) & (P[:, 1] < 1.12)

    def faixa(P):
        return (np.abs(P[:, 1] - 1.24) < 0.065) & (np.abs(P[:, 0]) > 0.3)

    def conves(P):
        # o piso do convés (por dentro da borda do casco)
        dentro = np.abs(P[:, 0]) < 0.9 * np.sqrt(np.clip(1 - (P[:, 2] / 3.0) ** 2, 0, 1)) - 0.08
        return (P[:, 1] > 1.52) & (P[:, 1] < 1.62) & dentro & (np.abs(P[:, 2]) < 1.35)

    def escotilha(P, borda):
        r = np.full(len(P), 9.0)
        for z in (-0.95, 0.0, 0.95):
            r = np.minimum(r, np.hypot(P[:, 1] - 0.92, P[:, 2] - z))
        lado = np.abs(P[:, 0]) > 0.55
        return lado & ((r < 0.14) if not borda else ((r >= 0.14) & (r < 0.19)))

    pint = [Pintura(tabuas, pal.tabua), Pintura(faixa, pal.ouro), Pintura(conves, pal.conves),
            Pintura(lambda P: escotilha(P, True), pal.ouro), Pintura(lambda P: escotilha(P, False), pal.vidro)]
    m = malha("navio", forma, 0.036, pal, pint, ((-1.6, -0.3, -3.6), (1.6, 6.4, 4.4)), chao=-0.02)
    # VELAS estufadas (malha fina à parte: o pano é fino) e a bandeira
    pv = Paleta(pano=hex_cor("#FFF4DD"), listra=hex_cor("#E53935"), preto=hex_cor("#262230"), osso=hex_cor("#FFFFFF"))
    velas = []
    for z, y0, y1, meia in ((0.3, 3.32, 5.42, 0.93), (1.85, 2.92, 4.32, 0.76), (-1.95, 3.18, 4.13, 0.74)):
        R = 2.6
        zc = z + 0.17 - R
        pano = CilindroRedondo((0, (y0 + y1) / 2, zc), R + 0.04, (y1 - y0) / 2 + 0.2, 0.0, pv.pano).menos(
            CilindroRedondo((0, (y0 + y1) / 2, zc), R - 0.04, (y1 - y0) / 2 + 0.4, 0.0, pv.pano))
        limite = CaixaRedonda((0, (y0 + y1) / 2, z + 0.2), (meia, (y1 - y0) / 2, 0.6), 0.03, pv.pano)
        velas.append(Intersecao(pano, limite, 0.01))
    bandeira = CaixaRedonda((0, 6.08, 0.3 - 0.36), (0.032, 0.24, 0.34), 0.016, pv.preto)
    forma_v = unir(*velas, bandeira)

    def listras(P):
        return (P[:, 1] < 5.6) & (np.floor((P[:, 1] - 3.32) / 0.3) % 2 == 1)

    def caveira(P):
        y, z = P[:, 1] - 6.12, P[:, 2] - (0.3 - 0.36)
        cabeca = np.hypot(y * 1.1, z) < 0.085
        olhos = (np.hypot(y - 0.01, z - 0.035) < 0.022) | (np.hypot(y - 0.01, z + 0.035) < 0.022)
        ossos = ((np.abs((y + 0.1) - 0.55 * z) < 0.016) | (np.abs((y + 0.1) + 0.55 * z) < 0.016)) & (np.abs(z) < 0.15)
        return (P[:, 1] > 5.8) & ((cabeca & ~olhos) | ossos)

    pint_v = [Pintura(listras, pv.listra), Pintura(caveira, pv.osso)]
    mv = malha("navio/velas", forma_v, 0.026, pv, pint_v, ((-1.2, 2.6, -2.6), (1.2, 6.5, 2.4)))
    return juntar([m, mv])


def tartaruga():
    pal = Paleta(casco=hex_cor("#3FB97A"), linha=hex_cor("#2A8A5A"), pele=hex_cor("#9BE15D"),
                 barriga=hex_cor("#FFF1B8"), centro=hex_cor("#5ED16A"))
    casco = Intersecao(Elipsoide((0, 0.2, -0.04), (0.36, 0.26, 0.42), pal.casco), SemiEspaco((0, 0.16, 0), (0, -1, 0)), 0.03)
    barriga = Elipsoide((0, 0.17, -0.03), (0.35, 0.09, 0.41), pal.barriga)
    cabeca = Esfera((0, 0.3, 0.5), 0.15, pal.pele)
    pescoco = Capsula((0, 0.2, 0.25), (0, 0.27, 0.45), 0.1, pal.pele)
    nad = []
    for s in (-1, 1):
        nad.append(Elipsoide((s * 0.38, 0.11, 0.2), (0.22, 0.045, 0.1), pal.pele, rot=rot_y(s * 0.55)))
        nad.append(Elipsoide((s * 0.27, 0.09, -0.37), (0.13, 0.04, 0.08), pal.pele, rot=rot_y(-s * 0.6)))
    rabo = Capsula((0, 0.14, -0.44), (0, 0.11, -0.54), 0.045, pal.pele, rb=0.02)
    forma = unir(casco.solda(barriga, 0.03), unir(pescoco, cabeca, k=0.06), unir(*nad), rabo, k=0.04)

    def no_casco(P):
        q = (P - np.array([0, 0.2, -0.04])) / np.array([0.36, 0.26, 0.42])
        return (comprimento(q) > 0.93) & (P[:, 1] > 0.235) & (comprimento(q) < 1.12)

    def linhas(P):
        return no_casco(P) & (borda_hex(P[:, 0], P[:, 2] + 0.04, 0.14) < 0.02)

    def centro(P):
        return no_casco(P) & (borda_hex(P[:, 0], P[:, 2] + 0.04, 0.14) > 0.06)
    m = malha("tartaruga", forma, 0.026, pal, [Pintura(centro, pal.centro), Pintura(linhas, pal.linha)],
              ((-0.8, -0.2, -0.8), (0.8, 0.7, 0.9)))
    rosto = Rosto(forma)
    for s in (-1, 1):
        rosto.olho((s * 0.065, 0.335, 0.5), (s * 0.45, 0.2, 1.0), 0.042, afundar=0.45)
    rosto.traco(sorriso_pontos(0.0, 0.255, 0.5, 0.05, 0.022, 7), (0, 0, 1), 0.011)
    rosto.bochecha((0.1, 0.27, 0.5), (0.7, 0, 1), (0.03, 0.02, 0.008))
    rosto.bochecha((-0.1, 0.27, 0.5), (-0.7, 0, 1), (0.03, 0.02, 0.008))
    # barriga e nadadeiras encostando no chão
    return juntar([m, rosto.gerar()]).transladar((0.0, -0.048, 0.0))


# =================================================================== SELVA DOS DINOS

def fronde(topo, az, L, subida, queda, larg_max, esp, lobos, cor, n=14, prof=0.28):
    """Folha arqueada saindo de `topo` na direção azimutal az."""
    dr = np.array([math.cos(az), 0.0, math.sin(az)])
    s = np.linspace(0.0, 1.0, n)
    pts = topo + np.outer(s * L, dr) + np.outer(L * (subida * s - queda * s * s), CIMA)
    lado = np.array([-math.sin(az), 0.0, math.cos(az)])

    def larg(t):
        t = np.clip(t, 0, 1)
        base = esp + larg_max * np.sin(PI * t ** 0.8) ** 0.8
        return base * (1.0 - prof + prof * np.abs(np.cos(lobos * PI * t))) if lobos else base
    return Fita(pts, larg, lambda t: np.full_like(t, esp), lado, cor)


def palmeira():
    pal = Paleta(tronco=hex_cor("#C99560"), anel=hex_cor("#A8743F"), folha=hex_cor("#4CC46A"),
                 folha2=hex_cor("#36AE5E"), nervura=hex_cor("#B6EB6E"), coco=hex_cor("#8B5A2B"), copa=hex_cor("#3E9E4E"))
    H = 3.55
    ys = np.linspace(-0.1, H, 10)
    xs = 0.45 * (np.clip(ys, 0, H) / H) ** 2
    pts = np.stack([xs, ys, np.zeros_like(ys)], 1)
    tronco = []
    for i in range(len(pts) - 1):
        r0 = 0.23 - 0.085 * max(ys[i], 0) / H
        r1 = 0.23 - 0.085 * ys[i + 1] / H
        tronco.append(Capsula(pts[i], pts[i + 1], r0, pal.tronco, rb=r1))
    pe = Elipsoide((0, 0.0, 0), (0.36, 0.24, 0.36), pal.tronco)
    topo = np.array([0.45, H, 0.0])
    copa = Elipsoide(topo + np.array([0, 0.06, 0]), (0.25, 0.2, 0.25), pal.copa)
    folhas = []
    for i in range(7):
        az = 2 * PI * i / 7 + 0.35 + 0.15 * math.sin(i * 2.3)
        L = 1.85 + 0.15 * math.sin(i * 1.7)
        folhas.append(fronde(topo + np.array([0, 0.08, 0]), az, L, 0.7, 1.25 + 0.1 * math.cos(i), 0.25, 0.07, 7, pal.folha))
    cocos = [Esfera(topo + np.array([0.2 * math.cos(a), -0.24, 0.2 * math.sin(a)]), 0.14, pal.coco)
             for a in (0.9, 0.9 + 2.1, 0.9 + 4.2)]
    forma = unir(unir(*tronco, k=0.05).solda(pe, 0.15), copa, k=0.08)
    forma = unir(forma, unir(*folhas, k=0.03), k=0.06) | unir(*cocos)
    forma = Intersecao(forma, SemiEspaco((0, 0, 0), (0, -1, 0)), 0.03)

    def aneis(P):
        return (np.sin(P[:, 1] * 2 * PI / 0.3) > 0.35) & (P[:, 1] < H - 0.1)

    def folha_cor(nervura):
        def f(P):
            d, t, l, _ = param_fitas(folhas, P)
            perto = d < 0.04
            if nervura:
                return perto & (np.abs(l) < 0.035) & (t > 0.06)
            return perto & (np.floor(t * 7 + 0.5 + (l > 0) * 0.5) % 2 == 0)
        return f
    pint = [Pintura(na_cor(forma, pal.tronco, aneis), pal.anel), Pintura(folha_cor(False), pal.folha2),
            Pintura(folha_cor(True), pal.nervura)]
    return suavizar_normais(malha("palmeira", forma, 0.064, pal, pint, ((-2.6, -0.3, -2.6), (3.0, 4.8, 2.6))))


def samambaia():
    pal = Paleta(verde=hex_cor("#5ED16A"), claro=hex_cor("#A6E85F"), escuro=hex_cor("#2F9E5A"))
    folhas = []
    for i in range(8):
        az = 2 * PI * i / 8 + 0.25 + 0.2 * math.sin(i * 3.1)
        externa = i % 2 == 0
        L = 0.8 if externa else 1.0
        sub, que = (1.25, 1.05) if externa else (1.75, 1.0)
        folhas.append(fronde(np.array([0.0, 0.04, 0.0]), az, L, sub, que, 0.15, 0.04, 8, pal.verde, n=12, prof=0.5))
    centro = Intersecao(Elipsoide((0, 0.0, 0), (0.16, 0.13, 0.16), pal.escuro), SemiEspaco((0, 0, 0), (0, -1, 0)), 0.02)
    forma = unir(*folhas, k=0.02).solda(centro, 0.05)

    def pontas(P):
        d, t, l, _ = param_fitas(folhas, P)
        return (d < 0.03) & (t > 0.72)

    def nervura(P):
        d, t, l, _ = param_fitas(folhas, P)
        return (d < 0.03) & (np.abs(l) < 0.018) & (t < 0.9)
    return suavizar_normais(malha("samambaia", forma, 0.031, pal, [Pintura(pontas, pal.claro), Pintura(nervura, pal.escuro)],
                 ((-1.3, -0.2, -1.3), (1.3, 1.4, 1.3))))


def vulcao():
    pal = Paleta(terra=hex_cor("#B97650"), escura=hex_cor("#9C6043"), clara=hex_cor("#CC8C62"),
                 lava=hex_cor("#FF7A1A"), lava_clara=hex_cor("#FFC93B"), pedra=hex_cor("#8A6352"))
    perfil = [(-0.4, 0.0), (-0.4, 4.62), (0.0, 4.4), (0.4, 3.82), (1.0, 3.16), (1.8, 2.52), (2.7, 1.98),
              (3.6, 1.58), (4.35, 1.34), (4.78, 1.22), (4.88, 1.08), (4.8, 0.9), (4.55, 0.76), (4.4, 0.0)]
    corpo = Arredondada(Torno((0, 0, 0), perfil, pal.terra), 0.1)
    rng = np.random.default_rng(9)
    pedras = []
    for i in range(7):
        a = 2 * PI * i / 7 + 0.5
        rr = rng.uniform(3.7, 4.4)
        pedras.append(Elipsoide((rr * math.sin(a), 0.15, rr * math.cos(a)), (0.4, 0.3, 0.35), pal.pedra, rot=rot_y(a)))
    forma = Deslocada(corpo.solda(unir(*pedras), 0.25), 0.05, 1.6)
    TOPO = 4.98
    escorridos = [(0.12, 2.5, 0.42), (0.95, 1.7, 0.36), (-0.75, 2.1, 0.38), (1.9, 2.3, 0.4), (-1.75, 1.5, 0.34),
                  (2.75, 1.8, 0.38), (-2.6, 2.4, 0.4), (3.6, 1.6, 0.36)]

    def escorrido(P, folga):
        rr = np.sqrt(P[:, 0] ** 2 + P[:, 2] ** 2)
        th = np.arctan2(P[:, 0], P[:, 2])
        m = np.zeros(len(P), dtype=bool)
        for a, L, w in escorridos:
            s_ = np.angle(np.exp(1j * (th - a))) * np.maximum(rr, 0.5)
            fim = TOPO - L
            larg = (w - folga) * (1 + 0.25 * np.clip((fim + 0.6 - P[:, 1]) / 0.6, 0, 1))  # gota na ponta
            corpo = (np.abs(s_) < larg) & (P[:, 1] > fim)
            gota = (s_ / w) ** 2 + ((P[:, 1] - fim) / (w * 0.9)) ** 2 < (1 - folga / w) ** 2
            m |= corpo | gota
        return m & (rr > 0.9)

    def cratera(P, r):
        rr = np.sqrt(P[:, 0] ** 2 + P[:, 2] ** 2)
        return (rr < r) & (P[:, 1] > 4.3)

    def borda_lava(P):
        th = np.arctan2(P[:, 0], P[:, 2])
        return P[:, 1] > 4.7 + 0.06 * np.sin(th * 7.0)
    pint = [Pintura(lambda P: P[:, 1] < 0.55 + 0.12 * np.sin(np.arctan2(P[:, 0], P[:, 2]) * 5), pal.escura),
            Pintura(lambda P: (P[:, 1] > 1.6 + 0.15 * np.sin(np.arctan2(P[:, 0], P[:, 2]) * 4)) &
                    (P[:, 1] < 1.9 + 0.15 * np.sin(np.arctan2(P[:, 0], P[:, 2]) * 4)), pal.escura),
            Pintura(lambda P: (P[:, 1] > 3.3) & (P[:, 1] < 4.7), pal.clara),
            Pintura(lambda P: borda_lava(P) | escorrido(P, 0.0) | cratera(P, 1.1), pal.lava),
            Pintura(lambda P: escorrido(P, 0.17) | cratera(P, 0.8), pal.lava_clara)]
    return malha("vulcao", forma, 0.15, pal, pint, ((-5.5, -0.6, -5.5), (5.5, 5.6, 5.5)), chao=-0.12)


def ovo_dino():
    pal = Paleta(ovo=hex_cor("#FFF3DC"), pinta=hex_cor("#2EC4B6"), palha=hex_cor("#E8C170"), palha2=hex_cor("#C99A4B"))
    ovo = Elipsoide((0, 0.39, 0), (0.205, 0.285, 0.205), pal.ovo).solda(Esfera((0, 0.3, 0), 0.198, pal.ovo), 0.12)
    ninho = Deslocada(unir(Toro((0, 0.12, 0), 0.25, 0.1, pal.palha),
                           Elipsoide((0, 0.05, 0), (0.3, 0.07, 0.3), pal.palha), k=0.05), 0.014, 32.0)
    forma = Intersecao(ninho, SemiEspaco((0, 0, 0), (0, -1, 0)), 0.01) | ovo
    dirs = sorte(16, 11)
    rng = np.random.default_rng(4)
    tam = rng.uniform(0.94, 0.975, len(dirs))

    def pintas(P):
        q = P - np.array([0, 0.37, 0])
        u = q / comprimento(q)[:, None]
        m = np.zeros(len(P), dtype=bool)
        for d, c in zip(dirs, tam):
            m |= (u @ d) > c
        return m & (P[:, 1] > 0.2) & (comprimento(P[:, [0, 2]]) < 0.23)

    def palha(P):
        th = np.arctan2(P[:, 2], P[:, 0])
        return (P[:, 1] < 0.24) & (np.sin(th * 26 + P[:, 1] * 45 + np.sin(th * 5) * 2) > 0.45)
    return malha("ovo_dino", forma, 0.021, pal, [Pintura(palha, pal.palha2), Pintura(pintas, pal.pinta)],
                 ((-0.5, -0.2, -0.5), (0.5, 0.9, 0.5)))


def dino():
    pal = Paleta(verde=hex_cor("#8FD14F"), barriga=hex_cor("#E4F5A6"), pinta=hex_cor("#5FB33C"), unha=hex_cor("#FFF3DC"))
    corpo = Elipsoide((0, 1.35, -0.35), (0.78, 0.72, 1.05), pal.verde)
    pernas = []
    for x in (-0.44, 0.44):
        for z in (0.26, -0.98):
            pernas.append(CilindroRedondo((x, 0.5, z), 0.27, 0.5, 0.09, pal.verde))
            pernas.append(Elipsoide((x, 0.1, z + 0.05), (0.3, 0.14, 0.33), pal.verde))
    pescoco = unir(Capsula((0, 1.55, 0.3), (0, 2.25, 0.78), 0.4, pal.verde, rb=0.3),
                   Capsula((0, 2.25, 0.78), (0, 2.72, 1.05), 0.3, pal.verde, rb=0.27), k=0.1)
    cabeca = Elipsoide((0, 2.87, 1.17), (0.4, 0.35, 0.42), pal.verde).solda(
        Elipsoide((0, 2.74, 1.42), (0.31, 0.23, 0.26), pal.verde), 0.1)
    rabo = unir(Capsula((0, 1.3, -1.2), (0, 0.92, -1.78), 0.34, pal.verde, rb=0.2),
                Capsula((0, 0.92, -1.78), (0.2, 0.55, -2.12), 0.2, pal.verde, rb=0.085), k=0.08)
    forma = unir(corpo, pescoco, rabo, k=0.2).solda(cabeca, 0.12).solda(unir(*pernas, k=0.1), 0.12)
    forma = Intersecao(forma, SemiEspaco((0, 0, 0), (0, -1, 0)), 0.03)

    def barriga(P):
        baixo = (((P[:, 0] / 0.62) ** 2 + ((P[:, 1] - 0.9) / 0.5) ** 2 + ((P[:, 2] + 0.3) / 0.95) ** 2) < 1) & (np.abs(P[:, 0]) < 0.4)
        # frente do pescoço: perto da linha do peito até o queixo, do lado da frente
        a, b = np.array([0, 1.25, 0.62]), np.array([0, 2.5, 1.32])
        ab = b - a
        h = np.clip((P - a) @ ab / (ab @ ab), 0, 1)
        peito = comprimento(P - (a + h[:, None] * ab)) < 0.2
        return (baixo | peito) & (P[:, 1] > 0.55)

    centros, raios = [], []
    for d, r in ((norm((0.5, 0.75, 0.1)), 0.17), (norm((-0.55, 0.7, -0.25)), 0.19), (norm((0.25, 0.9, -0.55)), 0.15),
                 (norm((-0.2, 0.95, 0.3)), 0.13), (norm((0.65, 0.5, -0.6)), 0.14), (norm((-0.7, 0.45, 0.35)), 0.12),
                 (norm((-0.4, 0.8, -0.7)), 0.13)):
        centros.append(np.array([0, 1.35, -0.35]) + d * np.array([0.78, 0.72, 1.05]))
        raios.append(r)
    centros += [np.array([0.0, 1.17, -1.45]), np.array([0.06, 3.2, 1.05])]
    raios += [0.12, 0.1]

    def unhas(P):
        m = np.zeros(len(P), dtype=bool)
        for x in (-0.44, 0.44):
            for z in (0.26, -0.98):
                for o in (-0.13, 0.0, 0.13):
                    m |= (comprimento(P - np.array([x + o, 0.07, z + 0.35])) < 0.075)
        return m
    pint = [Pintura(barriga, pal.barriga), Pintura(lambda P: dentro_esferas(P, centros, raios), pal.pinta),
            Pintura(unhas, pal.unha)]
    m = malha("dino", forma, 0.07, pal, pint, ((-1.4, -0.3, -2.8), (1.4, 3.8, 2.2)))
    rosto = Rosto(forma)
    for s in (-1, 1):
        rosto.olho((s * 0.17, 2.96, 1.17), (s * 0.35, 0.12, 1.0), 0.105, afundar=0.5)
    rosto.traco(sorriso_pontos(0.0, 2.67, 1.3, 0.12, 0.045, 9), (0, 0, 1), 0.026)
    rosto.bochecha((0.27, 2.77, 1.25), (0.65, 0.0, 1.0), (0.08, 0.055, 0.02))
    rosto.bochecha((-0.27, 2.77, 1.25), (-0.65, 0.0, 1.0), (0.08, 0.055, 0.02))
    return juntar([m, rosto.gerar()])


def ptero():
    pal = Paleta(laranja=hex_cor("#FF9F2E"), asa=hex_cor("#FF8657"), barriga=hex_cor("#FFD9A0"),
                 bico=hex_cor("#FFD43B"), crista=hex_cor("#2EC4B6"), osso=hex_cor("#F07438"), asa_clara=hex_cor("#FFB08A"))
    corpo = Elipsoide((0, 0, 0), (0.13, 0.13, 0.21), pal.laranja)
    cabeca = Esfera((0, 0.11, 0.23), 0.125, pal.laranja)
    bico = ConeRedondo((0, 0.065, 0.32), (0, 0.035, 0.5), 0.06, 0.022, pal.bico)
    crista = Elipsoide((0, 0.24, 0.13), (0.025, 0.055, 0.13), pal.crista, rot=rot_x(0.55))
    rabo = Capsula((0, 0.0, -0.18), (0, -0.04, -0.33), 0.05, pal.laranja, rb=0.02)
    asas, ossos, pes = [], [], []
    for s in (-1, 1):
        pts = np.array([(s * 0.06, 0.04, 0.03), (s * 0.23, 0.08, 0.03), (s * 0.4, 0.13, 0.0),
                        (s * 0.55, 0.17, -0.06), (s * 0.63, 0.19, -0.11)])

        def frente(t):
            return np.full_like(t, 0.035)

        def tras(t):
            t = np.clip(t, 0, 1)
            return -(0.02 + 0.36 * (1 - t) ** 0.95) * (0.8 + 0.2 * np.abs(np.cos(2.5 * PI * t)))
        asas.append(Fita(pts, lambda t, f=frente, b=tras: 0.5 * (f(t) - b(t)), lambda t: np.full_like(t, 0.024),
                         (0, 0, 1), pal.asa, desloc=lambda t, f=frente, b=tras: 0.5 * (f(t) + b(t))))
        for a, b in zip(pts[:-1], pts[1:]):
            ossos.append(Capsula(a, b, 0.036, pal.osso, rb=0.03))
        pes.append(Capsula((s * 0.05, -0.08, -0.1), (s * 0.06, -0.13, -0.2), 0.03, pal.laranja))
        pes.append(Esfera((s * 0.06, -0.135, -0.215), 0.036, pal.bico))
    forma = unir(unir(corpo, cabeca, rabo, k=0.06), crista, bico, k=0.03)
    forma = unir(forma, unir(*asas, *ossos, k=0.02), *pes, k=0.04)

    def barriga(P):
        return (P[:, 1] < -0.03) & (np.abs(P[:, 0]) < 0.11) & (np.abs(P[:, 2]) < 0.2)

    def membrana(P):
        d, t, l, _ = param_fitas(asas, P)
        return (d < 0.02) & (np.abs(P[:, 0]) > 0.14) & (np.cos(2.5 * PI * t * 2) > 0.6) & (l < -0.04)
    m = suavizar_normais(malha("ptero", forma, 0.018, pal, [Pintura(barriga, pal.barriga), Pintura(membrana, pal.asa_clara)],
              ((-0.9, -0.5, -0.7), (0.9, 0.6, 0.8))))
    rosto = Rosto(forma)
    for s in (-1, 1):
        rosto.olho((s * 0.05, 0.145, 0.23), (s * 0.55, 0.22, 0.8), 0.042, afundar=0.45)
    rosto.bochecha((0.09, 0.07, 0.23), (0.7, -0.2, 0.7), (0.03, 0.02, 0.008))
    rosto.bochecha((-0.09, 0.07, 0.23), (-0.7, -0.2, 0.7), (0.03, 0.02, 0.008))
    return juntar([m, rosto.gerar()])


def pedra():
    pal = Paleta(pedra=hex_cor("#A9A6BC"), musgo=hex_cor("#7ED957"), musgo2=hex_cor("#5ABF4E"), escura=hex_cor("#8E8AA6"))
    base = Deslocada(unir(Elipsoide((0, 0.3, 0), (0.52, 0.42, 0.46), pal.pedra),
                          Elipsoide((0.3, 0.18, 0.12), (0.3, 0.24, 0.28), pal.pedra), k=0.15), 0.035, 5.5)
    forma = Intersecao(base, SemiEspaco((0, 0, 0), (0, -1, 0)), 0.04)

    def musgo(P):
        th = np.arctan2(P[:, 2], P[:, 0])
        return P[:, 1] > 0.47 + 0.07 * np.sin(th * 5) + 0.04 * np.sin(th * 11 + 1)

    def manchas(P):
        th = np.arctan2(P[:, 2], P[:, 0])
        return musgo(P) & (np.sin(P[:, 0] * 23) * np.sin(P[:, 2] * 19 + th) > 0.45)
    pint = [Pintura(lambda P: P[:, 1] < 0.12, pal.escura), Pintura(musgo, pal.musgo), Pintura(manchas, pal.musgo2)]
    return malha("pedra", forma, 0.03, pal, pint, ((-0.9, -0.2, -0.9), (0.9, 0.9, 0.9)))


def flor_gigante():
    pal = Paleta(caule=hex_cor("#4CB85A"), folha=hex_cor("#6FD25E"), petala=hex_cor("#FF8A2A"),
                 petala_clara=hex_cor("#FFD43B"), miolo=hex_cor("#7A4A2E"), ponto=hex_cor("#B07A50"))
    caule_pts = [(0.0, 0.0, 0.0), (0.04, 0.32, 0.0), (0.02, 0.62, 0.02), (0.0, 0.88, 0.06)]
    caule = unir(*[Capsula(a, b, 0.05, pal.caule, rb=0.045) for a, b in zip(caule_pts[:-1], caule_pts[1:])], k=0.03)
    folhas = []
    for y, az, L in ((0.26, 0.15, 0.48), (0.46, PI - 0.25, 0.42)):
        folhas.append(fronde(np.array([0.03, y, 0.0]), az, L, 0.75, 0.65, 0.11, 0.032, 0, pal.folha, n=10))
    centro = np.array([0.0, 0.93, 0.08])
    f = norm((0.0, 0.42, 1.0))
    u = norm(np.cross(CIMA, f))
    v = np.cross(f, u)
    petalas = []
    for i in range(5):
        a = PI / 2 + 2 * PI * i / 5
        rad = u * math.cos(a) + v * math.sin(a)
        tg = np.cross(f, rad)
        radl = norm(rad + 0.25 * f)
        nl = np.cross(radl, tg)
        petalas.append(Elipsoide(centro + rad * 0.2 + f * 0.01, (0.19, 0.125, 0.04), pal.petala,
                                 rot=np.stack([radl, tg, nl], 1)))
    miolo = Elipsoide(centro + f * 0.045, (0.11, 0.11, 0.07), pal.miolo, rot=np.stack([u, v, f], 1))
    forma = unir(caule, *folhas, k=0.03) | unir(*petalas, k=0.025).solda(miolo, 0.03)

    def clara(P):
        return (comprimento(P - centro) < 0.17) & (comprimento(P - centro) > 0.1)

    def pontos(P):
        q = P - centro
        x, y = q @ u, q @ v
        return ((q @ f) > 0.07) & (np.sin(x * 70) * np.sin(y * 70) > 0.55) & (x * x + y * y < 0.085 ** 2)
    pint = [Pintura(na_cor(forma, pal.petala, clara), pal.petala_clara), Pintura(pontos, pal.ponto)]
    return suavizar_normais(malha("flor_gigante", forma, 0.019, pal, pint, ((-0.8, -0.2, -0.8), (0.8, 1.6, 0.8))))


# =================================================================== PARQUE DE DIVERSÕES

EIXO_RODA = 4.6     # altura do eixo da roda-gigante
RAIO_RODA = 3.8     # aro de fora: as cabines penduram no meio das barras brancas
Z_ARO = 0.5         # a roda tem dois aros (z = ±0.5); a cabine passa entre eles
Z_CAVALETE = 0.85   # os cavaletes (pernas em A) ficam em z = ±0.85


def roda_base():
    pal = Paleta(branco=hex_cor("#FFFFFF"), turquesa=hex_cor("#2EC4B6"), amarelo=hex_cor("#FFD43B"))
    pe_x = 2.35
    pecas = []
    for z in (-Z_CAVALETE, Z_CAVALETE):
        for s in (-1, 1):
            pecas.append(tubo([(0, EIXO_RODA, z), (s * pe_x, 0.12, z)], 0.13, pal, pal.branco, lados=16))
        y = 1.7
        xb = pe_x * (1 - (y - 0.12) / (EIXO_RODA - 0.12))
        pecas.append(tubo([(-xb, y, z), (xb, y, z)], 0.09, pal, pal.turquesa))
        pecas.append(bolinha((0, EIXO_RODA, z), 0.26, pal, pal.turquesa, lados=18))
    pecas.append(tubo([(0, EIXO_RODA, -Z_CAVALETE - 0.16), (0, EIXO_RODA, Z_CAVALETE + 0.16)], 0.12, pal, pal.amarelo, lados=14))
    blocos = []
    for s in (-1, 1):
        pecas.append(tubo([(s * pe_x, 0.3, -Z_CAVALETE), (s * pe_x, 0.3, Z_CAVALETE)], 0.1, pal, pal.turquesa))
        blocos.append(CaixaRedonda((s * pe_x, 0.08, 0), (0.42, 0.2, Z_CAVALETE + 0.32), 0.07, pal.turquesa))
    plataforma = CaixaRedonda((0, -0.02, 0), (pe_x + 0.5, 0.1, Z_CAVALETE + 0.32), 0.04, pal.branco)
    forma = unir(*blocos) | plataforma
    pint = [Pintura(lambda P: P[:, 1] < 0.045, pal.turquesa)]
    m = malha("roda_base", forma, 0.1, pal, pint, ((-3.4, -0.5, -1.8), (3.4, 1.0, 1.8)), chao=-0.1)
    return juntar([m] + pecas)


def roda():
    """Roda-gigante (origem no eixo, gira em Z). Dois aros paralelos
    (z = ±Z_ARO) ligados por 8 barras brancas: o pivô de cada cabine é o meio
    da barra, em RAIO_RODA * (cos a, sin a, 0) com a = 90° + k * 45°."""
    pal = Paleta(turquesa=hex_cor("#2EC4B6"), amarelo=hex_cor("#FFD43B"), roxo=hex_cor("#E8384F"),
                 laranja=hex_cor("#FF9F2E"), branco=hex_cor("#FFFFFF"), lampada=hex_cor("#FFF6C8"))
    cores = [pal.turquesa, pal.amarelo, pal.roxo, pal.laranja]
    pecas = []
    for i in range(8):
        a = 2 * PI * i / 8 + PI / 2          # raio i (o 0 aponta para cima)
        cor = cores[i % 4]
        d = np.array([math.cos(a), math.sin(a), 0.0])
        d2 = np.array([math.cos(a + PI / 8), math.sin(a + PI / 8), 0.0])
        for z in (-Z_ARO, Z_ARO):
            zz = np.array([0.0, 0.0, z])
            pecas.append(arco(RAIO_RODA, a - PI / 8, a + PI / 8, 0.12, pal, cor, segs=10, lados=12, centro=zz))
            pecas.append(arco(3.3, a - PI / 8, a + PI / 8, 0.09, pal, cor, segs=8, lados=10, centro=zz))
            pecas.append(tubo([d * 0.38 + zz * 0.45, d * RAIO_RODA + zz], 0.08, pal, cor, lados=10))
            pecas.append(tubo([d2 * 3.3 + zz, d2 * RAIO_RODA + zz], 0.065, pal, pal.branco, lados=8))
        # barra do pivô da cabine (as tampas redondas fazem de 'botões')
        pecas.append(tubo([d * RAIO_RODA - (0, 0, Z_ARO + 0.1), d * RAIO_RODA + (0, 0, Z_ARO + 0.1)], 0.07, pal, pal.branco,
                          lados=10))
        for da in (-PI / 16, PI / 16):
            pecas.append(bolinha((RAIO_RODA * math.cos(a + da), RAIO_RODA * math.sin(a + da), Z_ARO + 0.11), 0.055,
                                 pal, pal.lampada, lados=8))
    cubo = CilindroRedondo((0, 0, 0), 0.45, 0.3, 0.08, pal.amarelo, rot=rot_x(PI / 2))

    def estrela(P):
        return (np.abs(P[:, 2]) > 0.25) & estrela_2d(P[:, 0], P[:, 1], 0.0, 0.0, 0.31, 0.14)
    pecas.append(malha("roda/cubo", cubo, 0.045, pal, [Pintura(estrela, pal.roxo)], ((-0.7, -0.7, -0.6), (0.7, 0.7, 0.6))))
    return juntar(pecas)


def cabine():
    # TINTA; origem no pivô (em cima)
    pal = Paleta(branco=hex_cor("#FFFFFF"), cinza=hex_cor("#DCDCE8"), dentro=hex_cor("#E7E7F0"), faixa=hex_cor("#EEEEF5"))
    pivo = Esfera((0, 0, 0), 0.05, pal.cinza) | Capsula((0, 0, 0), (0, -0.12, 0), 0.032, pal.cinza)
    teto = Elipsoide((0, -0.15, 0), (0.37, 0.075, 0.3), pal.branco).solda(Esfera((0, -0.1, 0), 0.06, pal.branco), 0.04)
    postes = unir(*[Capsula((s * 0.3, -0.16, 0), (s * 0.3, -0.46, 0), 0.032, pal.cinza) for s in (-1, 1)])
    cuba = Intersecao(Elipsoide((0, -0.5, 0), (0.36, 0.16, 0.28), pal.branco), SemiEspaco((0, -0.43, 0), (0, 1, 0)), 0.02)
    cuba = cuba.menos(Elipsoide((0, -0.44, 0), (0.26, 0.13, 0.18), pal.dentro), k=0.015, cor_do_corte=True)
    banco = CaixaRedonda((0, -0.5, -0.07), (0.22, 0.05, 0.07), 0.03, pal.dentro)
    forma = unir(pivo, teto, postes, k=0.03) | cuba.solda(banco, 0.02).solda(postes, 0.03)

    def faixas(P):
        th = np.arctan2(P[:, 2], P[:, 0])
        return (P[:, 1] > -0.2) & (P[:, 1] < -0.08) & (np.floor(th / (PI / 6)) % 2 == 0)
    return malha("cabine", forma, 0.021, pal, [Pintura(faixas, pal.faixa)], ((-0.6, -0.9, -0.5), (0.6, 0.2, 0.5)))


def bandeirinha(nome, topo, haste, comp, larg, fase=0.0):
    """Mastro + bandeira triangular ondulando (para +X) + bolinha no alto."""
    pal = Paleta(mastro=hex_cor("#FFFFFF"), bandeira=hex_cor("#FF6F61"), bola=hex_cor("#FFD43B"))
    topo = np.asarray(topo, dtype=np.float64)
    mastro = tubo([topo, topo + np.array([0, haste, 0])], 0.03, pal, pal.mastro, lados=10)
    bola = bolinha(topo + np.array([0, haste + 0.05, 0]), 0.065, pal, pal.bola, lados=12)
    s = np.linspace(0, 1, 9)
    pts = np.stack([0.03 + s * comp, np.full_like(s, haste - larg - 0.03) - 0.04 * s,
                    0.04 * np.sin(s * 2 * PI + fase) * s], 1) + topo
    band = Fita(pts, lambda t: larg * (1 - 0.8 * np.clip(t, 0, 1)) + 0.024, lambda t: np.full_like(t, 0.024),
                (0, 1, 0), pal.bandeira)
    mb = suavizar_normais(malha(nome + "/bandeira", band, 0.02, pal, (), (topo - (0.3, 0.1, 0.3), topo + (comp + 0.3, haste + 0.3, 0.3))))
    return juntar([mastro, bola, mb])


def tenda():
    pal = Paleta(turquesa=hex_cor("#2EC4B6"), amarelo=hex_cor("#FFD43B"), roxo=hex_cor("#E8384F"),
                 porta=hex_cor("#4A2C7A"), creme=hex_cor("#FFF3DC"))
    N = 16
    # lona (parede + telhado côncavo) em gomos turquesa/amarelo
    perfil = [(-0.12, 1.37), (0.6, 1.375), (1.3, 1.38), (1.5, 1.52), (1.62, 1.3), (1.8, 1.02), (2.0, 0.78),
              (2.2, 0.58), (2.4, 0.41), (2.56, 0.27), (2.68, 0.15), (2.76, 0.07), (2.8, 0.0)]
    lona = torno_gomos(perfil, [pal.turquesa if g % 2 == 0 else pal.amarelo for g in range(N)], pal,
                       segs=5, fase=-PI / N)
    # sanefa de babados: amarelo embaixo do gomo turquesa, roxo embaixo do amarelo
    saia = Babado((0, 0, 0), 1.3, 1.6, 1.5, 1.1, N, 0.14, pal.roxo, arred=0.04, fase=PI / N)

    def babado_amarelo(P):
        th = np.arctan2(P[:, 2], P[:, 0]) + PI / N
        k = np.floor(np.mod(th, 2 * PI) / (2 * PI / N)).astype(int)
        return k % 2 == 0
    m = malha("tenda", saia, 0.07, pal, [Pintura(babado_amarelo, pal.amarelo)], ((-2.0, 0.6, -2.0), (2.0, 2.0, 2.0)))
    porta = adesivo_porta(1.375, 0.33, 0.58, 0.07, pal, pal.porta, pal.creme)
    return juntar([lona, m, porta, bandeirinha("tenda", (0.0, 2.74, 0.0), 0.62, 0.5, 0.15)])


def ponei(c, frente, cor_crina, pal):
    """Cavalinho simples de carrossel, olhando para `frente` (horizontal)."""
    f = norm(frente)
    lado = np.cross(CIMA, f)
    R = np.stack([lado, CIMA, f], 1)

    def P(x, y, z):
        return c + lado * x + CIMA * y + f * z
    corpo = Elipsoide(c, (0.11, 0.12, 0.23), pal.branco, rot=R)
    pescoco = Capsula(P(0, 0.05, 0.14), P(0, 0.22, 0.24), 0.07, pal.branco)
    cabeca = Elipsoide(P(0, 0.27, 0.3), (0.07, 0.075, 0.12), pal.branco, rot=R @ rot_x(0.5))
    orelhas = [Capsula(P(s * 0.035, 0.33, 0.25), P(s * 0.04, 0.4, 0.23), 0.032, pal.branco) for s in (-1, 1)]
    crina = Capsula(P(0, 0.33, 0.22), P(0, 0.12, 0.07), 0.045, cor_crina)
    rabo = Capsula(P(0, 0.06, -0.2), P(0, -0.12, -0.32), 0.05, cor_crina, rb=0.035)
    pernas = []
    for s in (-1, 1):
        pernas.append(Capsula(P(s * 0.06, -0.06, 0.13), P(s * 0.06, -0.12, 0.27), 0.042, pal.branco))
        pernas.append(Capsula(P(s * 0.06, -0.06, -0.14), P(s * 0.06, -0.21, -0.22), 0.042, pal.branco))
    corpo = unir(corpo, pescoco, cabeca, *orelhas, *pernas, k=0.04)
    return unir(corpo, crina, rabo, k=0.02), (c, f, lado)


def carrossel():
    pal = Paleta(turquesa=hex_cor("#2EC4B6"), piso=hex_cor("#FFF1B8"), roxo=hex_cor("#E8384F"), amarelo=hex_cor("#FFD43B"),
                 coluna=hex_cor("#F1EAFF"), lampada=hex_cor("#FFF6C8"))
    N = 12
    base = CilindroRedondo((0, 0.06, 0), 1.25, 0.2, 0.06, pal.turquesa)
    coluna = CilindroRedondo((0, 1.1, 0), 0.17, 0.9, 0.05, pal.coluna)
    perfil = [(1.8, 0.15), (1.8, 0.7), (1.8, 1.24), (1.85, 1.33), (1.93, 1.36), (2.0, 1.28), (2.15, 1.0),
              (2.33, 0.62), (2.48, 0.32), (2.58, 0.12), (2.62, 0.0)]
    teto = torno_gomos(perfil, [pal.roxo if g % 2 else pal.amarelo for g in range(N)], pal, segs=6)
    saia = Babado((0, 0, 0), 1.08, 1.34, 1.86, 1.62, N, 0.11, pal.amarelo, arred=0.035)
    forma = unir(base, coluna, k=0.05) | saia

    def babado_roxo(P):
        th = np.arctan2(P[:, 2], P[:, 0])
        k = np.floor(np.mod(th, 2 * PI) / (2 * PI / N)).astype(int)
        return (P[:, 1] < 1.9) & (P[:, 1] > 1.5) & (comprimento(P[:, [0, 2]]) > 1.06) & (k % 2 == 0)

    def piso(P):
        return (P[:, 1] > 0.2) & (P[:, 1] < 0.3) & (comprimento(P[:, [0, 2]]) < 1.17)

    def lampadas(P):
        th = np.arctan2(P[:, 2], P[:, 0])
        u = np.mod(th / (2 * PI) * 28, 1.0)
        return (P[:, 1] > 0.0) & (P[:, 1] < 0.15) & (comprimento(P[:, [0, 2]]) > 1.2) & (np.abs(u - 0.5) < 0.2)
    pint = [Pintura(babado_roxo, pal.roxo), Pintura(piso, pal.piso), Pintura(lampadas, pal.lampada)]
    m = malha("carrossel", forma, 0.09, pal, pint, ((-1.8, -0.6, -1.8), (1.8, 3.0, 1.8)), chao=-0.1)
    # cavalinhos (malha fina à parte) + postes dourados + bandeirinha
    pp = Paleta(branco=hex_cor("#FFFFFF"), dourado=hex_cor("#FFD43B"), c0=hex_cor("#FF6F61"), c1=hex_cor("#2EC4B6"),
                c2=hex_cor("#9BE15D"), c3=hex_cor("#4FC3F7"), sela=hex_cor("#E8384F"))
    poneis, selas, pecas = [], [], [m, teto]
    for i in range(4):
        a = PI / 4 + i * PI / 2
        pos = np.array([0.85 * math.sin(a), 0.0, 0.85 * math.cos(a)])
        tang = np.array([math.cos(a), 0.0, -math.sin(a)])
        y = 0.92 if i % 2 == 0 else 0.8
        corpo, sela = ponei(pos + np.array([0, y, 0]), tang, pp.c0 + i, pp)
        poneis.append(corpo)
        selas.append(sela)
        pecas.append(tubo([pos + np.array([0, 0.2, 0]), pos + np.array([0, 1.75, 0])], 0.035, pp, pp.dourado, lados=10))

    def selas_f(P):
        m_ = np.zeros(len(P), dtype=bool)
        for c, f, lado in selas:
            q = P - c
            m_ |= (np.abs(q @ f) < 0.075) & ((q @ CIMA) > 0.02) & (comprimento(q) < 0.2)
        return m_
    pecas.append(malha("carrossel/cavalinhos", unir(*poneis), 0.036, pp, [Pintura(selas_f, pp.sela)],
                       ((-1.4, 0.3, -1.4), (1.4, 1.6, 1.4))))
    pecas.append(bandeirinha("carrossel", (0.0, 2.62, 0.0), 0.5, 0.4, 0.12))
    return juntar(pecas)


# =================================================================== lista e gravação

OBJETOS = {
    # espaço
    "planeta_anel": planeta_anel, "foguete": foguete, "ovni": ovni, "planeta": planeta,
    "cristal": cristal, "pedra_lua": pedra_lua, "estrela_3d": estrela_3d,
    # fundo do mar
    "coral": coral, "coral_roxo": coral_roxo, "alga": alga, "concha": concha, "estrela_mar": estrela_mar,
    "peixe": peixe, "agua_viva": agua_viva, "bau": bau, "tartaruga": tartaruga, "navio": navio,
    # selva dos dinos
    "palmeira": palmeira, "samambaia": samambaia, "vulcao": vulcao, "ovo_dino": ovo_dino,
    "dino": dino, "ptero": ptero, "pedra": pedra, "flor_gigante": flor_gigante,
    # parque de diversões
    "roda_base": roda_base, "roda": roda, "cabine": cabine, "tenda": tenda, "carrossel": carrossel,
}


def _gerar_um(nome):
    t = time.time()
    m = OBJETOS[nome]()
    return nome, m, time.time() - t


def ler_pacote(caminho_sem_ext):
    """Lê de volta as malhas de um pacote já gravado (para refazer só alguns)."""
    if not os.path.exists(caminho_sem_ext + ".json"):
        return {}
    with open(caminho_sem_ext + ".json", encoding="utf-8") as f:
        info = json.load(f)
    with open(caminho_sem_ext + ".bin", "rb") as f:
        blob = f.read()
    out = {}
    for p in info["partes"]:
        def arr(chave, tipo, cols):
            ini, tam = p[chave]
            return np.frombuffer(blob[ini:ini + tam], dtype=tipo).reshape(-1, cols)
        out[p["nome"]] = Malha(arr("v", np.float32, 3), arr("n", np.float32, 3), arr("c", np.float32, 4), arr("i", np.int32, 3))
    return out


def gerar_temas(so=None):
    caminho = os.path.join(SAIDA, "temas")
    antigas = ler_pacote(caminho) if so else {}
    alvo = [n for n in OBJETOS if (not so or n in so or n not in antigas)]
    malhas = dict(antigas)
    with mp.get_context("fork").Pool(min(4, os.cpu_count() or 1)) as pool:
        for nome, m, dt in pool.imap_unordered(_gerar_um, alvo):
            malhas[nome] = m
            print("  %-14s %6d triângulos  (%.1f s)" % (nome, len(m.i), dt))
    pac = Pacote()
    for nome in OBJETOS:
        pac.adicionar(nome, malhas[nome])
    pac.gravar(caminho)


if __name__ == "__main__":
    so = sys.argv[1:]
    for n in so:
        if n not in OBJETOS:
            sys.exit("objeto desconhecido: %s" % n)
    gerar_temas(so)
