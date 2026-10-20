# -*- coding: utf-8 -*-
"""
MODELADOR SDF DO STRIKE KIDS
============================

Os modelos 3D do jogo (Léo, Lia, pinos, cenário) são descritos como formas
matemáticas (SDF = "signed distance field"): esferas, cápsulas, elipsoides...
unidas com "solda suave" (smooth union). O resultado é uma superfície lisa,
sem emendas, com cara de massinha / brinquedo de vinil.

Este arquivo tem:
  * as formas básicas e as operações (unir, soldar, cortar, pintar);
  * o gerador de malha (Surface Nets, vetorizado com numpy);
  * a gravação em um formato simples (.bin + .json) que o Godot converte em
    malhas nativas (tools/modelos/assar_modelos.gd).

Nada aqui roda no jogo: é ferramenta de produção.
"""
import json
import math
import struct

import numpy as np

# ----------------------------------------------------------------- cores

def hex_cor(h, a=0.0):
    """'#RRGGBB' -> (r, g, b, a) em 0..1 (sRGB). O alfa é a MÁSCARA DO ROSTO
    (1 = pele onde o rosto pintado pode aparecer)."""
    h = h.lstrip('#')
    return (int(h[0:2], 16) / 255.0, int(h[2:4], 16) / 255.0, int(h[4:6], 16) / 255.0, a)


# ----------------------------------------------------------------- vetores

def _v(x):
    return np.asarray(x, dtype=np.float64)


def comprimento(p):
    return np.sqrt(np.sum(p * p, axis=-1))


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=np.float64)


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float64)


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=np.float64)


# ----------------------------------------------------------------- formas
# Cada forma é um objeto com:
#   d(P)   -> distância com sinal (negativo = dentro), P: (N, 3)
#   cor(P) -> índice da cor em cada ponto (N,), usado só nos vértices finais

class Forma:
    cor_id = 0

    def d(self, P):
        raise NotImplementedError

    def dc(self, P):
        """distância e cor juntas"""
        return self.d(P), np.full(len(P), self.cor_id, dtype=np.int32)

    # açúcar sintático
    def __or__(self, outra):
        return Uniao(self, outra, 0.0)

    def solda(self, outra, k):
        return Uniao(self, outra, k)

    def menos(self, outra, k=0.0, cor_do_corte=False):
        return Subtracao(self, outra, k, cor_do_corte)

    def e(self, outra, k=0.0):
        return Intersecao(self, outra, k)


class Primitiva(Forma):
    def __init__(self, cor_id):
        self.cor_id = cor_id


class Esfera(Primitiva):
    def __init__(self, c, r, cor_id):
        super().__init__(cor_id)
        self.c, self.r = _v(c), r

    def d(self, P):
        return comprimento(P - self.c) - self.r


class Elipsoide(Primitiva):
    """Elipsoide (aproximação de Inigo Quilez), com rotação opcional."""

    def __init__(self, c, raios, cor_id, rot=None):
        super().__init__(cor_id)
        self.c, self.r = _v(c), _v(raios)
        self.rot = rot

    def d(self, P):
        q = P - self.c
        if self.rot is not None:
            q = q @ self.rot  # rotação inversa (matriz ortogonal)
        k0 = comprimento(q / self.r)
        k1 = comprimento(q / (self.r * self.r))
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


class Capsula(Primitiva):
    def __init__(self, a, b, r, cor_id, rb=None):
        super().__init__(cor_id)
        self.a, self.b, self.r = _v(a), _v(b), r
        self.rb = r if rb is None else rb

    def d(self, P):
        pa = P - self.a
        ba = self.b - self.a
        h = np.clip(np.sum(pa * ba, axis=-1) / np.dot(ba, ba), 0.0, 1.0)
        r = self.r + (self.rb - self.r) * h
        return comprimento(pa - h[:, None] * ba) - r


class CaixaRedonda(Primitiva):
    def __init__(self, c, meia, raio, cor_id, rot=None):
        super().__init__(cor_id)
        self.c, self.meia, self.raio = _v(c), _v(meia), raio
        self.rot = rot

    def d(self, P):
        q = P - self.c
        if self.rot is not None:
            q = q @ self.rot
        q = np.abs(q) - (self.meia - self.raio)
        fora = comprimento(np.maximum(q, 0.0))
        dentro = np.minimum(np.max(q, axis=-1), 0.0)
        return fora + dentro - self.raio


class CilindroRedondo(Primitiva):
    """Cilindro em pé (eixo Y local) com bordas arredondadas."""

    def __init__(self, c, raio, meia_altura, arred, cor_id, rot=None):
        super().__init__(cor_id)
        self.c, self.raio, self.h, self.arred = _v(c), raio, meia_altura, arred
        self.rot = rot

    def d(self, P):
        q = P - self.c
        if self.rot is not None:
            q = q @ self.rot
        dxz = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) - self.raio + self.arred
        dy = np.abs(q[:, 1]) - self.h + self.arred
        fora = np.sqrt(np.maximum(dxz, 0) ** 2 + np.maximum(dy, 0) ** 2)
        dentro = np.minimum(np.maximum(dxz, dy), 0.0)
        return fora + dentro - self.arred


class Toro(Primitiva):
    """Rosca deitada (no plano XZ local)."""

    def __init__(self, c, R, r, cor_id, rot=None):
        super().__init__(cor_id)
        self.c, self.R, self.r, self.rot = _v(c), R, r, rot

    def d(self, P):
        q = P - self.c
        if self.rot is not None:
            q = q @ self.rot
        qx = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) - self.R
        return np.sqrt(qx ** 2 + q[:, 1] ** 2) - self.r


class ConeRedondo(Primitiva):
    """Tronco de cone arredondado entre a (raio ra) e b (raio rb)."""

    def __init__(self, a, b, ra, rb, cor_id):
        super().__init__(cor_id)
        self.a, self.b, self.ra, self.rb = _v(a), _v(b), ra, rb

    def d(self, P):
        ba = self.b - self.a
        l2 = float(np.dot(ba, ba))
        rr = self.ra - self.rb
        a2 = l2 - rr * rr
        il2 = 1.0 / l2
        pa = P - self.a
        y = np.sum(pa * ba, axis=-1)
        z = y - l2
        xv = pa * l2 - y[:, None] * ba
        x2 = np.sum(xv * xv, axis=-1)
        y2 = y * y * l2
        z2 = z * z * l2
        k = np.sign(rr) * rr * rr * x2
        res = np.empty(len(P))
        m1 = np.sign(z) * a2 * z2 > k
        m2 = (~m1) & (np.sign(y) * a2 * y2 < k)
        m3 = ~(m1 | m2)
        res[m1] = np.sqrt(x2[m1] + z2[m1]) * il2 - self.rb
        res[m2] = np.sqrt(x2[m2] + y2[m2]) * il2 - self.ra
        res[m3] = (np.sqrt(x2[m3] * a2 * il2) + y[m3] * rr) * il2 - self.ra
        return res


class Torno(Primitiva):
    """Sólido de revolução em torno do eixo Y (perfil: lista de (y, raio))."""

    def __init__(self, c, perfil, cor_id):
        super().__init__(cor_id)
        self.c = _v(c)
        p = np.array(perfil, dtype=np.float64)
        self.ys, self.rs = p[:, 0], p[:, 1]

    def d(self, P):
        q = P - self.c
        rxz = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2)
        y = q[:, 1]
        # distância 2D ao polígono do perfil (segmentos entre pontos + eixo)
        pts = np.stack([self.rs, self.ys], -1)
        poly = np.concatenate([[[0.0, self.ys[0]]], pts, [[0.0, self.ys[-1]]]])
        P2 = np.stack([rxz, y], -1)
        dmin = np.full(len(P), 1e9)
        dentro = np.zeros(len(P), dtype=bool)
        for i in range(len(poly) - 1):
            a, b = poly[i], poly[i + 1]
            e = b - a
            w = P2 - a
            h = np.clip((w @ e) / max(float(e @ e), 1e-12), 0, 1)
            dd = comprimento(w - h[:, None] * e)
            dmin = np.minimum(dmin, dd)
            # teste par/ímpar (cruzamento de raio horizontal)
            c1 = (P2[:, 1] >= a[1]) != (P2[:, 1] >= b[1])
            xint = a[0] + (P2[:, 1] - a[1]) * e[0] / np.where(e[1] == 0, 1e-12, e[1])
            dentro ^= c1 & (P2[:, 0] < xint)
        # fecha pelo eixo
        a, b = poly[-1], poly[0]
        e = b - a
        w = P2 - a
        c1 = (P2[:, 1] >= a[1]) != (P2[:, 1] >= b[1])
        xint = a[0] + (P2[:, 1] - a[1]) * e[0] / np.where(e[1] == 0, 1e-12, e[1])
        dentro ^= c1 & (P2[:, 0] < xint)
        return np.where(dentro, -dmin, dmin)


class Deslocada(Forma):
    """Superfície com 'cachinhos': soma um ruído senoidal à distância."""

    def __init__(self, base, amp, freq, fase=(0.0, 0.0, 0.0)):
        self.base, self.amp, self.freq, self.fase = base, amp, freq, _v(fase)

    def d(self, P):
        f = self.freq
        q = P * f + self.fase
        n = np.sin(q[:, 0]) * np.sin(q[:, 1] * 1.13 + 0.7) * np.sin(q[:, 2] * 0.93 + 1.9)
        return self.base.d(P) - self.amp * n

    def dc(self, P):
        d, c = self.base.dc(P)
        return self.d(P), c


def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


class Uniao(Forma):
    def __init__(self, a, b, k):
        self.a, self.b, self.k = a, b, k

    def d(self, P):
        return smin(self.a.d(P), self.b.d(P), self.k)

    def dc(self, P):
        da, ca = self.a.dc(P)
        db, cb = self.b.dc(P)
        return smin(da, db, self.k), np.where(da <= db, ca, cb)


class Subtracao(Forma):
    def __init__(self, a, b, k, cor_do_corte):
        self.a, self.b, self.k, self.cc = a, b, k, cor_do_corte

    def d(self, P):
        return smax(self.a.d(P), -self.b.d(P), self.k)

    def dc(self, P):
        da, ca = self.a.dc(P)
        db, cb = self.b.dc(P)
        d = smax(da, -db, self.k)
        if self.cc:
            return d, np.where(-db > da, cb, ca)
        return d, ca


class Intersecao(Forma):
    def __init__(self, a, b, k=0.0):
        self.a, self.b, self.k = a, b, k

    def d(self, P):
        return smax(self.a.d(P), self.b.d(P), self.k)

    def dc(self, P):
        da, ca = self.a.dc(P)
        db, cb = self.b.dc(P)
        return smax(da, db, self.k), np.where(da >= db, ca, cb)


class SemiEspaco(Forma):
    """Plano: tudo 'abaixo' do plano (lado oposto à normal) está dentro."""

    def __init__(self, ponto, normal, cor_id=0):
        n = _v(normal)
        self.n = n / np.linalg.norm(n)
        self.p = _v(ponto)
        self.cor_id = cor_id

    def d(self, P):
        return (P - self.p) @ self.n


def unir(*formas, k=0.0):
    f = formas[0]
    for o in formas[1:]:
        f = Uniao(f, o, k)
    return f


# ----------------------------------------------------------------- pintura
# Pinturas mudam só a COR dos vértices (não a forma): listras, estrela no
# peito, sola do tênis...

class Pintura:
    def __init__(self, regiao, cor_id):
        """regiao(P) -> máscara booleana"""
        self.regiao, self.cor_id = regiao, cor_id


def estrela_2d(px, py, cx, cy, r_ext, r_int, pontas=5, giro=0.0):
    """Máscara de estrela no plano (px, py)."""
    ang = np.arctan2(py - cy, px - cx) - giro + math.pi / 2
    raio = np.sqrt((px - cx) ** 2 + (py - cy) ** 2)
    setor = 2 * math.pi / pontas
    a = np.mod(ang, setor) - setor / 2
    # interpola linearmente entre raio externo (ponta) e interno (vale)
    t = np.abs(a) / (setor / 2)
    lim = r_ext + (r_int - r_ext) * t
    return raio < lim


def coracao_2d(px, py, cx, cy, s):
    x = (px - cx) / s
    y = (py - cy) / s + 0.25
    return (x * x + y * y - 0.35) ** 3 - x * x * y * y * y < 0


# ----------------------------------------------------------------- malha

class Malha:
    def __init__(self, v, n, c, i):
        self.v, self.n, self.c, self.i = v, n, c, i

    def transladar(self, t):
        return Malha(self.v + _v(t), self.n, self.c, self.i)


def gradiente(forma, P, eps=1e-4):
    ex = np.array([eps, 0, 0])
    ey = np.array([0, eps, 0])
    ez = np.array([0, 0, eps])
    g = np.stack([
        forma.d(P + ex) - forma.d(P - ex),
        forma.d(P + ey) - forma.d(P - ey),
        forma.d(P + ez) - forma.d(P - ez),
    ], -1)
    n = np.linalg.norm(g, axis=-1, keepdims=True)
    return g / np.maximum(n, 1e-12)


def gerar_malha(forma, bmin, bmax, passo, paleta, pinturas=(), mascara_rosto=None, projetar=2, refinar=2):
    """Surface Nets: grade regular -> um vértice por célula que cruza a
    superfície -> um quadrado por aresta da grade que cruza a superfície.

    paleta: lista de cores (r, g, b, a) indexada pelo cor_id das formas.
    mascara_rosto: função(P, cor_ids) -> alfa (0..1); None = alfa da paleta.
    refinar: quantas vezes subdividir os triângulos onde a cor muda (bordas
    de cor lisas e nítidas, sem degraus).
    """
    bmin, bmax = _v(bmin), _v(bmax)
    nx, ny, nz = [int(math.ceil((bmax[i] - bmin[i]) / passo)) + 1 for i in range(3)]
    xs = bmin[0] + np.arange(nx) * passo
    ys = bmin[1] + np.arange(ny) * passo
    zs = bmin[2] + np.arange(nz) * passo
    X, Y, Z = np.meshgrid(xs, ys, zs, indexing='ij')
    P = np.stack([X, Y, Z], -1).reshape(-1, 3)
    D = forma.d(P).reshape(nx, ny, nz)
    dentro = D < 0

    cx, cy, cz = nx - 1, ny - 1, nz - 1
    soma = np.zeros((cx, cy, cz, 3))
    cont = np.zeros((cx, cy, cz))
    origem = np.stack(np.meshgrid(xs[:-1], ys[:-1], zs[:-1], indexing='ij'), -1)

    # 12 arestas de cada célula: (canto a, canto b)
    cantos = [(i, j, k) for i in (0, 1) for j in (0, 1) for k in (0, 1)]
    arestas = []
    for a in cantos:
        for b in cantos:
            if a < b and sum(abs(a[t] - b[t]) for t in range(3)) == 1:
                arestas.append((a, b))

    def fatia(c):
        return D[c[0]:c[0] + cx, c[1]:c[1] + cy, c[2]:c[2] + cz]

    for a, b in arestas:
        da, db = fatia(a), fatia(b)
        cruza = (da < 0) != (db < 0)
        t = np.where(cruza, da / np.where(cruza, da - db, 1.0), 0.0)
        pa = origem + _v(a) * passo
        pb = origem + _v(b) * passo
        pos = pa + t[..., None] * (pb - pa)
        soma += np.where(cruza[..., None], pos, 0.0)
        cont += cruza

    ativo = cont > 0
    indice = -np.ones((cx, cy, cz), dtype=np.int64)
    nverts = int(ativo.sum())
    indice[ativo] = np.arange(nverts)
    V = soma[ativo] / cont[ativo][:, None]

    # projeta os vértices na superfície (fica mais fiel e liso)
    for _ in range(projetar):
        g = gradiente(forma, V)
        V = V - forma.d(V)[:, None] * g

    quads = []
    # arestas da grade ao longo de x, y, z
    for eixo in range(3):
        u, w = [e for e in range(3) if e != eixo]
        sl_a = [slice(None)] * 3
        sl_b = [slice(None)] * 3
        sl_a[eixo] = slice(0, -1)
        sl_b[eixo] = slice(1, None)
        da = D[tuple(sl_a)]
        db = D[tuple(sl_b)]
        cruza = (da < 0) != (db < 0)
        # precisa de vizinhos nos dois eixos perpendiculares
        mask = np.zeros_like(cruza)
        sl = [slice(None)] * 3
        sl[u] = slice(1, -1)
        sl[w] = slice(1, -1)
        mask[tuple(sl)] = True
        cruza &= mask
        idx = np.argwhere(cruza)
        if len(idx) == 0:
            continue
        flip = (da[cruza] < 0)

        def cel(du, dw):
            q = idx.copy()
            q[:, u] -= du
            q[:, w] -= dw
            return indice[q[:, 0], q[:, 1], q[:, 2]]

        c00, c10, c11, c01 = cel(1, 1), cel(0, 1), cel(0, 0), cel(1, 0)
        q = np.stack([c00, c10, c11, c01], -1)
        q[flip] = q[flip][:, ::-1]
        quads.append(q)
    Q = np.concatenate(quads)
    Q = Q[(Q >= 0).all(axis=1)]

    # triângulos: divide pela diagonal mais curta
    d02 = np.linalg.norm(V[Q[:, 0]] - V[Q[:, 2]], axis=1)
    d13 = np.linalg.norm(V[Q[:, 1]] - V[Q[:, 3]], axis=1)
    t1 = np.where((d02 <= d13)[:, None], Q[:, [0, 1, 2]], Q[:, [0, 1, 3]])
    t2 = np.where((d02 <= d13)[:, None], Q[:, [0, 2, 3]], Q[:, [1, 2, 3]])
    T = np.concatenate([t1, t2])

    N = gradiente(forma, V)
    # orientação: a normal geométrica tem de concordar com o gradiente
    e1 = V[T[:, 1]] - V[T[:, 0]]
    e2 = V[T[:, 2]] - V[T[:, 0]]
    ng = np.cross(e1, e2)
    nm = N[T[:, 0]] + N[T[:, 1]] + N[T[:, 2]]
    errado = np.sum(ng * nm, axis=1) < 0
    T[errado] = T[errado][:, ::-1]
    # remove triângulos degenerados
    area = np.linalg.norm(np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]]), axis=1)
    T = T[area > 1e-12]

    # bordas de cor nítidas: a malha fica mais fina SÓ onde a cor muda
    V, T = refinar_bordas(forma, V, T, paleta, pinturas, mascara_rosto, refinar, projetar)
    N = gradiente(forma, V)
    C = cores_suaves(forma, V, N, paleta, pinturas, mascara_rosto, passo / (2 ** refinar))
    return Malha(V.astype(np.float32), N.astype(np.float32), C.astype(np.float32), T.astype(np.int32))


def _cores(forma, P, paleta, pinturas, mascara_rosto):
    """Cor (RGBA) e índice da cor em cada ponto: forma mais próxima + pinturas."""
    _, cids = forma.dc(P)
    for p in pinturas:
        cids = np.where(p.regiao(P), p.cor_id, cids)
    pal = np.array(paleta, dtype=np.float64)
    C = pal[cids].copy()
    if mascara_rosto is not None:
        C[:, 3] = mascara_rosto(P, cids)
    return C, cids


def refinar_bordas(forma, V, T, paleta, pinturas, mascara_rosto, niveis, projetar=2):
    """Divide (1 -> 4) os triângulos em que a cor muda, `niveis` vezes, com os
    vizinhos divididos em 2 ou 3 para não abrir frestas (refinamento
    "vermelho-verde"). Os vértices novos são puxados para a superfície.
    Assim listras, bolinhas e manchas ficam com a borda lisa, sem degraus,
    e as partes de cor única continuam leves."""
    for _ in range(niveis):
        _, cids = _cores(forma, V, paleta, pinturas, mascara_rosto)
        a, b, c = T[:, 0], T[:, 1], T[:, 2]
        borda = (cids[a] != cids[b]) | (cids[b] != cids[c]) | (cids[a] != cids[c])
        if not borda.any():
            break
        nv = len(V)
        E = np.stack([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]], 1)          # (nt, 3, 2)
        Es = np.sort(E, axis=2)
        chave = Es[..., 0].astype(np.int64) * nv + Es[..., 1]
        cortar = np.unique(chave[borda].ravel())
        ka, kb = cortar // nv, cortar % nv
        M = (V[ka] + V[kb]) * 0.5
        for _ in range(projetar):
            g = gradiente(forma, M)
            M = M - forma.d(M)[:, None] * g
        V = np.concatenate([V, M])
        pos = np.searchsorted(cortar, chave)
        pos_ok = np.clip(pos, 0, len(cortar) - 1)
        tem = cortar[pos_ok] == chave
        meio = np.where(tem, nv + pos_ok, -1)                             # (nt, 3): ab, bc, ca
        mab, mbc, mca = meio[:, 0], meio[:, 1], meio[:, 2]
        e0, e1, e2 = mab >= 0, mbc >= 0, mca >= 0
        n = e0.astype(int) + e1 + e2
        novos = [T[n == 0]]
        s = n == 3
        novos += [np.stack([a[s], mab[s], mca[s]], 1), np.stack([mab[s], b[s], mbc[s]], 1),
                  np.stack([mca[s], mbc[s], c[s]], 1), np.stack([mab[s], mbc[s], mca[s]], 1)]
        s = (n == 1) & e0
        novos += [np.stack([a[s], mab[s], c[s]], 1), np.stack([mab[s], b[s], c[s]], 1)]
        s = (n == 1) & e1
        novos += [np.stack([a[s], b[s], mbc[s]], 1), np.stack([a[s], mbc[s], c[s]], 1)]
        s = (n == 1) & e2
        novos += [np.stack([a[s], b[s], mca[s]], 1), np.stack([mca[s], b[s], c[s]], 1)]
        s = (n == 2) & e0 & e1
        novos += [np.stack([mab[s], b[s], mbc[s]], 1), np.stack([a[s], mab[s], mbc[s]], 1), np.stack([a[s], mbc[s], c[s]], 1)]
        s = (n == 2) & e1 & e2
        novos += [np.stack([mbc[s], c[s], mca[s]], 1), np.stack([a[s], b[s], mbc[s]], 1), np.stack([a[s], mbc[s], mca[s]], 1)]
        s = (n == 2) & e2 & e0
        novos += [np.stack([a[s], mab[s], mca[s]], 1), np.stack([mab[s], b[s], c[s]], 1), np.stack([mab[s], c[s], mca[s]], 1)]
        T = np.concatenate([x for x in novos if len(x)])
    return V, T


def cores_suaves(forma, V, N, paleta, pinturas, mascara_rosto, raio):
    """Cor de cada vértice = média de amostras em volta dele (no plano da
    superfície): a troca de cor vira uma transição de meio vértice, sem
    serrilhado, como um antisserrilhado da pintura."""
    C, _ = _cores(forma, V, paleta, pinturas, mascara_rosto)
    if raio <= 0:
        return C
    ref = np.where(np.abs(N[:, 1:2]) < 0.9, np.array([[0.0, 1.0, 0.0]]), np.array([[1.0, 0.0, 0.0]]))
    t1 = np.cross(N, ref)
    t1 /= np.maximum(np.linalg.norm(t1, axis=1, keepdims=True), 1e-12)
    t2 = np.cross(N, t1)
    soma = C * 2.0
    peso = 2.0
    for k in range(6):
        ang = k * math.pi / 3 + 0.3
        P = V + (t1 * math.cos(ang) + t2 * math.sin(ang)) * (raio * 0.55)
        Ck, _ = _cores(forma, P, paleta, pinturas, mascara_rosto)
        soma += Ck
        peso += 1.0
    return soma / peso


def juntar(malhas):
    v, n, c, i = [], [], [], []
    base = 0
    for m in malhas:
        v.append(m.v)
        n.append(m.n)
        c.append(m.c)
        i.append(m.i + base)
        base += len(m.v)
    return Malha(np.concatenate(v), np.concatenate(n), np.concatenate(c), np.concatenate(i))


# ----------------------------------------------------------------- gravação

class Pacote:
    """Um arquivo .bin com todas as malhas + um .json descrevendo as partes.

    Cada parte: nome, pai, pivô (posição do pivô no espaço do pai) e a malha
    já relativa ao pivô.
    """

    def __init__(self):
        self.partes = []
        self.blob = bytearray()

    def adicionar(self, nome, malha, pai="", pivo=(0, 0, 0), pivo_absoluto=None, extra=None):
        """malha em coordenadas ABSOLUTAS do modelo; pivo_absoluto é onde
        a junta fica. O vértice é gravado relativo à junta."""
        pa = _v(pivo_absoluto if pivo_absoluto is not None else (0, 0, 0))
        v = (malha.v - pa).astype(np.float32)
        info = {"nome": nome, "pai": pai, "pivo": [float(x) for x in pivo],
                "pivo_absoluto": [float(x) for x in pa],
                "vertices": int(len(v)), "triangulos": int(len(malha.i))}
        for chave, arr in (("v", v), ("n", malha.n), ("c", malha.c), ("i", malha.i)):
            arr = np.ascontiguousarray(arr)
            info[chave] = [len(self.blob), int(arr.nbytes)]
            self.blob += arr.tobytes()
            while len(self.blob) % 4:
                self.blob += b"\0"
        if extra:
            info.update(extra)
        self.partes.append(info)

    def gravar(self, caminho_sem_ext, meta=None):
        with open(caminho_sem_ext + ".bin", "wb") as f:
            f.write(bytes(self.blob))
        dados = {"partes": self.partes}
        if meta:
            dados.update(meta)
        with open(caminho_sem_ext + ".json", "w", encoding="utf-8") as f:
            json.dump(dados, f, ensure_ascii=False, indent=1)
        tot_v = sum(p["vertices"] for p in self.partes)
        tot_t = sum(p["triangulos"] for p in self.partes)
        print("  %-28s %3d partes  %7d vértices  %7d triângulos" % (caminho_sem_ext.split('/')[-1], len(self.partes), tot_v, tot_t))
