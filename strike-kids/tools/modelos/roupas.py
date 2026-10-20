# -*- coding: utf-8 -*-
"""
ROUPINHAS DAS FASES — Bob e Mia trocam de roupa em cada cenário
===============================================================

  * FUNDO DO MAR  -> piratas: Bob de chapéu de pirata (com caveirinha) e
    camiseta listrada; Mia de bandana de bolinhas e blusinha listrada.
  * SELVA DOS DINOS -> fantasia de dinossaurinho: capuz com dentinhos e
    olhinhos, espinhos nas costas e rabo de dino (Bob verde, Mia lilás).
  * ESPAÇO        -> astronautas: macacão branco, capacete aberto com
    antena que brilha, painel no peito e mochila (Bob azul, Mia rosa).
  * PARQUE        -> boné de hélice (a hélice gira) e roupa de passeio
    de bolinhas (Bob vermelho, Mia verde-água).

O ROSTO nunca é coberto: capuz e capacete só emolduram a cara (o desenho
do rosto continua o mesmo). Mesmas juntas e mesmas medidas do personagem
de sempre (personagens.py): as animações e a IK das pernas valem igual — o
jogo só troca a malha de cada junta (scripts/personagem.gd).

Gera tools/modelos/saida/<bob|mia>_<roupa>.json/.bin:
    python3 tools/modelos/modelos.py roupas
"""
import os

import numpy as np

from sdf import (CaixaRedonda, Capsula, CilindroRedondo, ConeRedondo, Elipsoide, Esfera, Intersecao, Pacote,
                 Pintura, SemiEspaco, Toro, gerar_malha, hex_cor, rot_x, rot_y, rot_z, unir)
from personagens import (CABECA_C, COTOVELO, JOELHO, MAO, OMBRO, PASSO, PESCOCO_Y, PULSO, QUADRIL, QUADRIL_Y, RABO,
                         ROSTO, ROSTO_CENTRO, ROSTO_TAMANHO, TORNOZELO, Paleta, alfa_por_cor, cabeca_base, espelho)

ROUPAS = ("pirata", "dino", "astronauta", "parque")


def _v(x):
    return np.asarray(x, dtype=np.float64)


# ------------------------------------------------------------- membros (cores livres)
# Peças com VOLUME de verdade (não só pintura): punho da luva, barra da
# calça, cano da bota dobrado e garrinhas de dino.

def _alinhar_y(d):
    """Base (colunas) com o eixo Y local na direção d (para os anéis)."""
    d = _v(d) / np.linalg.norm(d)
    a = np.array([1.0, 0.0, 0.0]) if abs(d[0]) < 0.9 else np.array([0.0, 0.0, 1.0])
    e1 = np.cross(a, d)
    e1 /= np.linalg.norm(e1)
    e3 = np.cross(e1, d)
    return np.stack([e1, d, e3], axis=1)


def braco(s, cores, punho=None):
    om, co, pu, mao = espelho(OMBRO, s), espelho(COTOVELO, s), espelho(PULSO, s), espelho(MAO, s)
    manga = Elipsoide(om + np.array([s * 0.012, -0.018, 0.0]), (0.07, 0.072, 0.066), cores["manga"])
    sup = Capsula(om, co, 0.044, cores["braco"], rb=0.041)
    superior = manga.solda(sup, 0.022).solda(Esfera(co, 0.041, cores["braco"]), 0.015)
    inf = Capsula(co, pu, 0.04, cores["antebraco"], rb=0.038)
    pata = Elipsoide(mao, (0.054, 0.058, 0.052), cores["mao"])
    inferior = inf.solda(pata, 0.03)
    if punho is not None:   # punho da luva: um anel gordinho no pulso
        d = pu - co
        inferior = inferior | Toro(co + d * 0.8, 0.038, 0.015, punho, rot=_alinhar_y(d))
    return superior, inferior


def perna(s, cores, barra=None, cano=None, garras=None):
    """(coxa, canela, pé, pinturas do pé, pinturas da canela).
    barra = cor da barra da calça (anel acima do joelho); cano = (cor da
    bota, cor da dobra): a bota sobe pela canela e termina numa dobra;
    garras = cor das garrinhas (dino)."""
    q, j, t = espelho(QUADRIL, s), espelho(JOELHO, s), espelho(TORNOZELO, s)
    coxa = Capsula(q + np.array([0, 0.02, 0]), j, 0.057, cores["coxa"], rb=0.05)
    superior = coxa.solda(Esfera(j, 0.049, cores["joelho"]), 0.015)
    if barra is not None:
        superior = superior | Toro(j + np.array([0.0, 0.035, 0.0]), 0.05, 0.013, barra)
    inferior = Capsula(j, t + np.array([0, 0.01, 0]), 0.048, cores["canela"], rb=0.045)
    pint_canela = []
    if cano is not None:
        bota, dobra = cano
        inferior = inferior | Toro(np.array([t[0], 0.14, t[2] + 0.002]), 0.046, 0.017, dobra)

        def cano_bota(P):
            return P[:, 1] < 0.14
        pint_canela = [Pintura(cano_bota, bota)]
    pe = Elipsoide((t[0], 0.05, 0.03), (0.064, 0.056, 0.09), cores["pe"])
    pe = pe.solda(Esfera((t[0], 0.075, 0.0), 0.045, cores["pe"]), 0.03)
    pe = Intersecao(pe, SemiEspaco((0, 0.003, 0), (0, -1, 0)), 0.012)
    if garras is not None:
        for dx in (-0.026, 0.0, 0.026):
            pe = pe | ConeRedondo((t[0] + dx, 0.03, 0.098), (t[0] + dx, 0.024, 0.138), 0.014, 0.004, garras)
    x = t[0]

    def dedos(P, x=x):
        return (P[:, 2] > 0.085) & (P[:, 1] < 0.065) & (np.abs(np.abs(P[:, 0] - x) - 0.021) < 0.0045)
    return superior, inferior, pe, [Pintura(dedos, cores["dedo"])], pint_canela


# ------------------------------------------------------------- cabeça: orelhas

def orelhas_bob(cab, c, cor):
    for s in (1, -1):
        orelha = Elipsoide(c + np.array([s * 0.262, -0.035, -0.035]), (0.068, 0.165, 0.105), cor,
                           rot=rot_z(s * 0.28) @ rot_x(0.12))
        cab = cab.solda(orelha, 0.03)
    return cab


def orelhas_mia(cab, c, cor):
    for s in (1, -1):
        base = c + np.array([s * 0.155, 0.17, -0.03])
        ponta = c + np.array([s * 0.215, 0.33, -0.045])
        cab = cab.solda(ConeRedondo(base, ponta, 0.088, 0.024, cor), 0.045)
    return cab


def fora_de(forma, regiao):
    """A pintura `regiao` só no que NÃO é a peça (ex.: orelha, não o boné)."""
    def r(P):
        return regiao(P) & (forma.d(P) > 0.003)
    return r


def sobre(forma, regiao):
    """A pintura `regiao` só na superfície da peça (ex.: bolinhas da bandana)."""
    def r(P):
        return regiao(P) & (np.abs(forma.d(P)) < 0.006)
    return r


def dentro_orelha_mia(c):
    def r(P):
        m = np.zeros(len(P), dtype=bool)
        for s in (1, -1):
            b = c + np.array([s * 0.158, 0.19, 0.0])
            d = P - b
            h = d[:, 1]
            meia = 0.052 - h * 0.3
            m |= (P[:, 2] > c[2] - 0.02) & (h > 0.0) & (h < 0.125) & (np.abs(d[:, 0] - s * h * 0.36) < meia)
        return m
    return r


def listras_mia(c, capuz=False):
    def r(P):
        q = P - c
        frente = q[:, 2] > 0.1
        if capuz:   # no capuz/capacete: só no pelo, nunca no aro
            frente = frente & (_plano(c, P) > 0.004)
        m = np.zeros(len(P), dtype=bool)
        for x0, comp in ((-0.058, 0.07), (0.0, 0.095), (0.058, 0.07)):
            topo = 0.235
            dx = q[:, 0] - x0 * (1.0 + (topo - q[:, 1]) * 1.2)
            dentro = (q[:, 1] < topo) & (q[:, 1] > topo - comp)
            largura = 0.015 * np.clip((q[:, 1] - (topo - comp)) / comp, 0.0, 1.0) ** 0.6 + 0.002
            m |= frente & dentro & (np.abs(dx) < largura)
        return m
    return r


# ------------------------------------------------------------- capuz (dino) e capacete (astronauta)
# Uma casca em volta da cabeça, aberta na frente por um plano QUASE em pé
# (como capuz de pijama de bichinho): a borda passa pela testa, desce pelos
# lados do rosto e por baixo do queixo — o rosto inteiro fica de fora,
# emoldurado, e de frente o capuz aparece em volta dele. A face do corte
# (o "aro") ganha a cor do forro.
PLANO_P = np.array([0.0, 0.0, 0.135])          # em relação ao centro da cabeça
PLANO_N = np.array([0.0, -0.32, 0.947]) / np.linalg.norm([0.0, -0.32, 0.947])
PLANO_K = 0.32 / 0.947                          # z do plano sobe assim com y


def _casca(c, largura, folga):
    centro = c + np.array([0.0, 0.012, -0.014])
    raios = np.array([0.272 * largura + folga, 0.246 + folga, 0.244 + folga])
    return centro, raios


def _plano(c, P):
    """> 0 na frente do corte (onde fica o rosto)."""
    return (P - (c + PLANO_P)) @ PLANO_N


def capuz(c, largura, folga, cor):
    centro, raios = _casca(c, largura, folga)
    casca = Elipsoide(centro, raios, cor)
    return Intersecao(casca, SemiEspaco(c + PLANO_P, PLANO_N), 0.008)


def na_casca(c, largura, folga):
    """Pontos na superfície de fora do capuz (para pinturas)."""
    centro, raios = _casca(c, largura, folga)

    def r(P):
        q = (P - centro) / raios
        e = np.sqrt(np.sum(q * q, axis=1))
        return (e > 0.93) & (_plano(c, P) < -0.004)
    return r


def forro(c, largura, folga, cor):
    """O aro do capuz (a face do corte em volta do rosto), na cor do forro."""
    centro, raios = _casca(c, largura, folga)

    def r(P):
        q = (P - centro) / raios
        e = np.sqrt(np.sum(q * q, axis=1))
        return (np.abs(_plano(c, P)) < 0.0035) & (e < 1.0)
    return Pintura(r, cor)


def borda_do_capuz(c, largura, folga, xs):
    """Pontos da borda de cima (na testa), para os dentinhos do dino."""
    centro, raios = _casca(c, largura, folga)
    pts = []
    for x in xs:
        ys = np.linspace(c[1], c[1] + 0.35, 4000)
        zs = (c[2] + PLANO_P[2]) + PLANO_K * (ys - c[1])
        f = (x / raios[0]) ** 2 + ((ys - centro[1]) / raios[1]) ** 2 + ((zs - centro[2]) / raios[2]) ** 2 - 1.0
        i = int(np.argmax(f > 0.0))
        pts.append(np.array([x, ys[i], zs[i]]))
    return pts


def ponto_no_topo(c, largura, folga, ang, x=0.0):
    """Ponto (e normal) no capuz, na linha do meio: ang 0 = topo, + para trás."""
    centro, raios = _casca(c, largura, folga)
    a = np.radians(ang)
    y = centro[1] + raios[1] * np.cos(a)
    z = centro[2] - raios[2] * np.sin(a)
    p = np.array([x, y, z])
    n = np.array([2 * x / raios[0] ** 2, 2 * (y - centro[1]) / raios[1] ** 2, 2 * (z - centro[2]) / raios[2] ** 2])
    return p, n / np.linalg.norm(n)


def enfeites_dino(c, largura, folga, pal):
    """Dentinhos na borda, olhinhos e espinhos no capuz."""
    partes = []
    # dentinhos pendurados na borda (na testa), de pontinha redonda
    for p in borda_do_capuz(c, largura, folga, (-0.15, -0.075, 0.0, 0.075, 0.15)):
        partes.append(ConeRedondo(p + np.array([0.0, 0.006, -0.012]), p + np.array([0.0, -0.034, 0.002]),
                                  0.019, 0.005, pal.dente))
    # olhinhos de dino em cima do capuz, olhando para a frente
    for s in (1, -1):
        p, n = ponto_no_topo(c, largura, folga, -22.0, s * 0.092)
        partes.append(Esfera(p + n * 0.014, 0.038, pal.olho_dino))
        partes.append(Esfera(p + n * 0.03 + np.array([0.0, 0.0, 0.024]), 0.017, pal.pupila))
    for ang, h, r in ((-6.0, 0.075, 0.038), (24.0, 0.085, 0.042), (54.0, 0.075, 0.038), (84.0, 0.058, 0.032)):
        p, n = ponto_no_topo(c, largura, folga, ang)
        partes.append(ConeRedondo(p - n * 0.012, p + n * h, r, 0.008, pal.espinho))
    return unir(*partes)


def espinhos_costas(pal):
    partes = []
    for y in (0.6, 0.53, 0.465, 0.405):
        partes.append(ConeRedondo((0.0, y, -0.1), (0.0, y + 0.012, -0.19), 0.034, 0.007, pal.espinho))
    return unir(*partes)


def rabo_dino(cor, espinho):
    r0 = RABO
    p1 = r0 + np.array([0.0, -0.05, -0.13])
    p2 = r0 + np.array([0.0, -0.1, -0.25])
    p3 = r0 + np.array([0.0, -0.12, -0.34])
    cauda = unir(Capsula(r0 + np.array([0.0, 0.01, 0.03]), p1, 0.075, cor, rb=0.06),
                 Capsula(p1, p2, 0.06, cor, rb=0.04), Capsula(p2, p3, 0.04, cor, rb=0.014), k=0.03)
    for base in (r0 + np.array([0.0, 0.055, -0.06]), p1 + np.array([0.0, 0.05, 0.0]), p2 + np.array([0.0, 0.035, 0.0])):
        cauda = cauda | ConeRedondo(base, base + np.array([0.0, 0.055, -0.02]), 0.026, 0.006, espinho)
    return cauda


def barriga(cor, z=0.1):
    """A barriga clarinha do dino: uma placa em relevo na frente do corpo."""
    return Elipsoide((0.0, 0.455, z), (0.104, 0.128, 0.056), cor)


# ------------------------------------------------------------- pirata

def chapeu_pirata(c, pal):
    copa = Intersecao(Elipsoide(c + np.array([0.0, 0.17, -0.01]), (0.215, 0.11, 0.2), pal.chapeu),
                      SemiEspaco(c + np.array([0.0, 0.12, 0.0]), (0, -1, 0)), 0.01)
    aba = Intersecao(Elipsoide(c + np.array([0.0, 0.215, -0.02]), (0.37, 0.17, 0.075), pal.chapeu, rot=rot_x(-0.18)),
                     SemiEspaco(c + np.array([0.0, 0.165, 0.0]), (0, -1, 0)), 0.012)
    return unir(copa, aba, k=0.02)


def _seg2(px, py, ax, ay, bx, by):
    abx, aby = bx - ax, by - ay
    t = np.clip(((px - ax) * abx + (py - ay) * aby) / (abx * abx + aby * aby), 0.0, 1.0)
    return np.hypot(px - (ax + t * abx), py - (ay + t * aby))


def pinturas_chapeu(c, pal):
    yc = c[1] + 0.215

    def frente(P):
        return (P[:, 2] > c[2] + 0.02) & (P[:, 1] > c[1] + 0.17)

    def friso(P):
        e = (P[:, 0] / 0.37) ** 2 + ((P[:, 1] - yc) / 0.17) ** 2
        return (P[:, 1] > c[1] + 0.175) & (e > 0.8) & (np.abs(P[:, 2] - (c[2] - 0.02)) < 0.12)

    y0 = c[1] + 0.25

    def ossos(P):
        x, y = P[:, 0], P[:, 1]
        d = np.minimum(_seg2(x, y, -0.055, y0 - 0.06, 0.055, y0 + 0.0),
                       _seg2(x, y, 0.055, y0 - 0.06, -0.055, y0 + 0.0))
        return frente(P) & (d < 0.011)

    def caveira(P):
        x, y = P[:, 0], P[:, 1]
        return frente(P) & ((x ** 2 + ((y - y0) / 1.05) ** 2 < 0.034 ** 2) | ((np.abs(x) < 0.02) & (y < y0) & (y > y0 - 0.045)))

    def olhos_caveira(P):
        x, y = P[:, 0], P[:, 1]
        return frente(P) & (((x - 0.013) ** 2 + (y - y0 - 0.004) ** 2 < 0.0095 ** 2) | ((x + 0.013) ** 2 + (y - y0 - 0.004) ** 2 < 0.0095 ** 2))
    return [Pintura(friso, pal.ouro), Pintura(ossos, pal.caveira), Pintura(caveira, pal.caveira), Pintura(olhos_caveira, pal.chapeu)]


def bandana(c, largura, pal):
    band = Intersecao(Elipsoide(c + np.array([0.0, 0.015, -0.008]),
                                (0.272 * largura + 0.02, 0.246 + 0.02, 0.244 + 0.02), pal.bandana),
                      SemiEspaco(c + np.array([0.0, 0.175, 0.2]), (0.0, -0.8, 0.6)), 0.008)
    no = c + np.array([0.13, 0.03, -0.235])
    laco = unir(Esfera(no, 0.032, pal.bandana),
                Elipsoide(no + np.array([0.05, -0.035, -0.03]), (0.055, 0.03, 0.022), pal.bandana, rot=rot_z(-0.6)),
                Elipsoide(no + np.array([0.0, -0.08, -0.02]), (0.03, 0.055, 0.02), pal.bandana, rot=rot_z(0.3)), k=0.012)
    return unir(band, laco, k=0.01)


def bolinhas_bandana(c, pal, band):
    def r(P):
        q = P - c
        u = np.arctan2(q[:, 0], q[:, 2]) * 0.26
        v = q[:, 1]
        cu = np.round(u / 0.055) * 0.055
        desl = (np.round(u / 0.055).astype(int) % 2) * 0.0275
        cv = np.round((v - desl) / 0.055) * 0.055 + desl
        # longe da barra (a face do corte em volta do rosto fica lisa)
        plano = -0.8 * (P[:, 1] - (c[1] + 0.175)) + 0.6 * (P[:, 2] - (c[2] + 0.2))
        return (np.hypot(u - cu, v - cv) < 0.012) & (plano < -0.012)
    return Pintura(sobre(band, r), pal.bolinha_bandana)


def cinto(y, R, pal):
    return unir(Toro((0.0, y, 0.0), R, 0.02, pal.cinto),
                CaixaRedonda((0.0, y, R + 0.006), (0.032, 0.024, 0.012), 0.006, pal.ouro), k=0.004)


# ------------------------------------------------------------- astronauta

def enfeites_capacete(c, largura, folga, pal):
    lado = 0.272 * largura + folga
    partes = []
    for s in (1, -1):
        partes.append(CilindroRedondo(c + np.array([s * (lado + 0.004), -0.01, -0.012]), 0.07, 0.026, 0.012,
                                      pal.detalhe, rot=rot_z(np.pi / 2)))
    topo, n = ponto_no_topo(c, largura, folga, 30.0, 0.0)
    ponta = topo + n * 0.12 + np.array([0.035, 0.03, 0.0])
    partes.append(Capsula(topo - n * 0.01, ponta, 0.009, pal.cinza))
    partes.append(Esfera(ponta + np.array([0.0, 0.018, 0.0]), 0.03, pal.luz))
    return unir(*partes)


def faixa_capacete(c, largura, folga, pal):
    casca = na_casca(c, largura, folga)

    def r(P):
        return casca(P) & (np.abs(P[:, 0]) < 0.034)
    return Pintura(r, pal.detalhe)


def mochila_e_painel(pal):
    mochila = CaixaRedonda((0.0, 0.5, -0.17), (0.12, 0.11, 0.055), 0.032, pal.traje)
    painel = CaixaRedonda((0.0, 0.5, 0.12), (0.078, 0.052, 0.024), 0.012, pal.cinza)
    gola = Toro((0.0, 0.615, 0.0), 0.083, 0.03, pal.detalhe)
    cintura = Toro((0.0, 0.405, 0.0), 0.158, 0.02, pal.detalhe)
    return unir(mochila, painel, gola, cintura)


def pinturas_traje(pal):
    def botao(cx, cy):
        def r(P):
            return (P[:, 2] > 0.135) & ((P[:, 0] - cx) ** 2 + (P[:, 1] - cy) ** 2 < 0.0135 ** 2)
        return r

    def tela(P):
        return (P[:, 2] > 0.135) & (np.abs(P[:, 0]) < 0.05) & (np.abs(P[:, 1] - 0.474) < 0.011)

    def faixa_mochila(P):
        return (P[:, 2] < -0.2) & (np.abs(P[:, 1] - 0.5) < 0.022)
    return [Pintura(botao(-0.036, 0.512), pal.vermelho), Pintura(botao(0.0, 0.512), pal.amarelo),
            Pintura(botao(0.036, 0.512), pal.verde), Pintura(tela, pal.tela), Pintura(faixa_mochila, pal.detalhe)]


# ------------------------------------------------------------- parque (boné de hélice)
BONE_Y = 0.15


def bone(c, pal):
    copa = Intersecao(Elipsoide(c + np.array([0.0, 0.14, 0.0]), (0.222, 0.15, 0.212), pal.bone_a),
                      SemiEspaco(c + np.array([0.0, BONE_Y, 0.0]), (0, -1, 0)), 0.008)
    aba = Intersecao(Elipsoide(c + np.array([0.0, BONE_Y + 0.006, 0.15]), (0.16, 0.022, 0.135), pal.aba),
                     SemiEspaco(c + np.array([0.0, 0.0, 0.12]), (0, 0, -1)), 0.006)
    botao = Esfera(c + np.array([0.0, 0.287, 0.0]), 0.024, pal.bone_c)
    return unir(copa, aba, botao)


def gomos_bone(c, pal):
    cores = (pal.bone_a, pal.bone_b, pal.bone_c)
    copa = Elipsoide(c + np.array([0.0, 0.14, 0.0]), (0.222, 0.15, 0.212), 0)
    pinturas = []
    for k in range(6):
        def r(P, k=k):
            q = P - c
            ang = (np.arctan2(q[:, 0], q[:, 2]) + np.pi + np.pi / 6) % (2 * np.pi)
            return ((q[:, 1] > BONE_Y + 0.002) & (q[:, 1] < 0.265) & (q[:, 2] < 0.13)
                    & (np.abs(copa.d(P)) < 0.006) & (np.floor(ang / (np.pi / 3)).astype(int) == k))
        pinturas.append(Pintura(r, cores[k % 3]))
    return pinturas


HELICE = CABECA_C + np.array([0.0, 0.3, 0.0])


def helice(pal):
    eixo = Capsula(HELICE + np.array([0.0, -0.02, 0.0]), HELICE + np.array([0.0, 0.018, 0.0]), 0.011, pal.bone_c)
    pas = unir(Elipsoide(HELICE + np.array([0.075, 0.014, 0.0]), (0.072, 0.008, 0.024), pal.helice_a, rot=rot_x(0.35)),
               Elipsoide(HELICE + np.array([-0.075, 0.014, 0.0]), (0.072, 0.008, 0.024), pal.helice_b, rot=rot_x(-0.35)), k=0.006)
    return unir(eixo, pas, k=0.008)


# ------------------------------------------------------------- as fantasias

def _paleta_bob(**extra):
    return Paleta(
        pelo=hex_cor("#E9A55B", ROSTO), focinho=hex_cor("#FFF1DE", ROSTO), nariz=hex_cor("#3A2422"),
        orelha=hex_cor("#A9652F"), pata=hex_cor("#FFF1DE"), dedo=hex_cor("#E2C3A0"), pelo_corpo=hex_cor("#E9A55B"),
        **extra)


def _paleta_mia(**extra):
    return Paleta(
        pelo=hex_cor("#C9CEDE", ROSTO), focinho=hex_cor("#FFFFFF", ROSTO), listra=hex_cor("#9AA2BA", ROSTO),
        nariz=hex_cor("#FF8FA6"), orelha=hex_cor("#C9CEDE"), orelha_dentro=hex_cor("#FFB8C8"), pata=hex_cor("#FFFFFF"),
        dedo=hex_cor("#FFC6D3"), pelo_corpo=hex_cor("#C9CEDE"), rabo_ponta=hex_cor("#9AA2BA"), **extra)


def _tronco_bob(roupa_cor):
    peito = Elipsoide((0, 0.515, 0.0), (0.158, 0.142, 0.13), roupa_cor)
    barriga_ = Elipsoide((0, 0.42, 0.006), (0.172, 0.118, 0.142), roupa_cor)
    ombros = Capsula((-0.118, 0.565, 0), (0.118, 0.565, 0), 0.058, roupa_cor)
    return peito.solda(barriga_, 0.06).solda(ombros, 0.05)


def _rabo_bob(pal, cor=None, ponta=None):
    """O rabinho enrolado; cor/ponta = o rabo "vestido" (astronauta)."""
    cor = pal.pelo_corpo if cor is None else cor
    ponta = pal.focinho if ponta is None else ponta
    r0 = RABO
    return unir(Capsula(r0, r0 + np.array([0, 0.07, -0.06]), 0.036, cor, rb=0.032),
                Capsula(r0 + np.array([0, 0.07, -0.06]), r0 + np.array([0, 0.13, -0.05]), 0.032, cor, rb=0.03),
                Esfera(r0 + np.array([0, 0.145, -0.035]), 0.036, ponta), k=0.025)


def _rabo_mia(pal, cor=None, ponta=None):
    cor = pal.pelo_corpo if cor is None else cor
    ponta = pal.rabo_ponta if ponta is None else ponta
    p0 = RABO
    p1 = RABO + np.array([0.0, 0.02, -0.13])
    p2 = RABO + np.array([0.025, 0.15, -0.2])
    p3 = RABO + np.array([0.055, 0.27, -0.15])
    return unir(Capsula(p0, p1, 0.031, cor), Capsula(p1, p2, 0.03, cor),
                Capsula(p2, p3, 0.03, ponta, rb=0.034), k=0.03)


def bob_fantasia(roupa):
    c = CABECA_C
    extra = {}
    if roupa == "pirata":
        pal = _paleta_bob(camisa=hex_cor("#F6F1E6"), lenco=hex_cor("#E53935"), calca=hex_cor("#2A3A6E"),
                          bota=hex_cor("#5A3420"), dobra=hex_cor("#8A5634"), chapeu=hex_cor("#262230"), ouro=hex_cor("#FFC93C"),
                          caveira=hex_cor("#FFFFFF"), cinto=hex_cor("#6B3E1E"))
        cab = orelhas_bob(cabeca_base(pal.pelo, pal.focinho, pal.nariz), c, pal.orelha) | chapeu_pirata(c, pal)
        pint_cab = pinturas_chapeu(c, pal)
        lenco = unir(Toro((0, 0.615, 0.0), 0.078, 0.026, pal.lenco),
                     ConeRedondo((0, 0.6, 0.085), (0, 0.53, 0.128), 0.044, 0.012, pal.lenco), k=0.012)
        tronco = _tronco_bob(pal.camisa).solda(Elipsoide((0, 0.355, 0.0), (0.15, 0.075, 0.125), pal.calca), 0.04)
        tronco = tronco.solda(Capsula((0, 0.58, 0), (0, 0.69, 0), 0.062, pal.pelo_corpo), 0.02).solda(lenco, 0.008)
        tronco = tronco | cinto(0.4, 0.162, pal)
        pint_tronco = []
        cores = dict(manga=pal.camisa, braco=pal.pelo_corpo, antebraco=pal.pelo_corpo, mao=pal.pata, coxa=pal.calca,
                     joelho=pal.calca, canela=pal.pelo_corpo, pe=pal.bota, dedo=pal.bota)
        estampa = {"tipo": "listras", "base": "#F6F1E6", "cor": "#E53935", "y0": 0.395 - QUADRIL_Y, "periodo": 0.046,
                   "raio": 0.012, "y_max": 0.63 - QUADRIL_Y}
        rabo = _rabo_bob(pal)
        extra["perna"] = dict(barra=pal.calca, cano=(pal.bota, pal.dobra))
    elif roupa == "dino":
        pal = _paleta_bob(fantasia=hex_cor("#58C255"), barriga=hex_cor("#FFF0A8"), espinho=hex_cor("#FF8A2B"),
                          dente=hex_cor("#FFFFFF"), olho_dino=hex_cor("#FFFFFF"), pupila=hex_cor("#1B1530"),
                          unha=hex_cor("#FFFFFF"))
        cab = cabeca_base(pal.pelo, pal.focinho, pal.nariz)
        cab = cab | capuz(c, 1.0, 0.042, pal.fantasia) | enfeites_dino(c, 1.0, 0.042, pal)
        pint_cab = [forro(c, 1.0, 0.042, pal.barriga)]
        tronco = _tronco_bob(pal.fantasia).solda(Elipsoide((0, 0.355, 0.0), (0.15, 0.075, 0.125), pal.fantasia), 0.04)
        tronco = tronco.solda(Capsula((0, 0.58, 0), (0, 0.69, 0), 0.062, pal.fantasia), 0.02) | espinhos_costas(pal)
        tronco = tronco.solda(barriga(pal.barriga, 0.098), 0.012)
        pint_tronco = []
        cores = dict(manga=pal.fantasia, braco=pal.fantasia, antebraco=pal.fantasia, mao=pal.pata, coxa=pal.fantasia,
                     joelho=pal.fantasia, canela=pal.fantasia, pe=pal.fantasia, dedo=pal.fantasia)
        extra["perna"] = dict(garras=pal.unha)
        estampa = {}
        rabo = rabo_dino(pal.fantasia, pal.espinho)
        extra["rabo_caixa"] = ((-0.16, 0.16, -0.52), (0.16, 0.58, -0.04))
    elif roupa == "astronauta":
        pal = _paleta_bob(traje=hex_cor("#F2F4F8"), detalhe=hex_cor("#2E7BEA"), cinza=hex_cor("#7D8799"),
                          luva=hex_cor("#C3CAD6"), luz=hex_cor("#FFD54F", 0.5), vermelho=hex_cor("#FF4D4D"),
                          amarelo=hex_cor("#FFD43B"), verde=hex_cor("#3DDC84"), tela=hex_cor("#1B2B4A"))
        cab = cabeca_base(pal.pelo, pal.focinho, pal.nariz)
        cab = cab | capuz(c, 1.0, 0.05, pal.traje) | enfeites_capacete(c, 1.0, 0.05, pal)
        pint_cab = [faixa_capacete(c, 1.0, 0.05, pal), forro(c, 1.0, 0.05, pal.detalhe)]
        tronco = _tronco_bob(pal.traje).solda(Elipsoide((0, 0.355, 0.0), (0.15, 0.075, 0.125), pal.traje), 0.04)
        tronco = tronco.solda(Capsula((0, 0.58, 0), (0, 0.69, 0), 0.062, pal.traje), 0.02) | mochila_e_painel(pal)
        pint_tronco = pinturas_traje(pal)
        cores = dict(manga=pal.traje, braco=pal.traje, antebraco=pal.traje, mao=pal.luva, coxa=pal.traje,
                     joelho=pal.traje, canela=pal.traje, pe=pal.luva, dedo=pal.luva)
        estampa = {}
        rabo = _rabo_bob(pal, pal.traje, pal.detalhe)
        extra["braco"] = dict(punho=pal.detalhe)
        extra["perna"] = dict(cano=(pal.luva, pal.detalhe))
    else:  # parque
        pal = _paleta_bob(camisa=hex_cor("#F2443A"), bermuda=hex_cor("#3D6FB6"), bone_a=hex_cor("#FF4D4D"),
                          bone_b=hex_cor("#FFD43B"), bone_c=hex_cor("#2E7BEA"), aba=hex_cor("#2E7BEA"),
                          helice_a=hex_cor("#FF4D4D"), helice_b=hex_cor("#FFD43B"), lenco=hex_cor("#FFD43B"))
        cab = orelhas_bob(cabeca_base(pal.pelo, pal.focinho, pal.nariz), c, pal.orelha).solda(bone(c, pal), 0.01)
        pint_cab = gomos_bone(c, pal)
        lenco = unir(Toro((0, 0.615, 0.0), 0.078, 0.026, pal.lenco),
                     ConeRedondo((0, 0.6, 0.085), (0, 0.53, 0.128), 0.044, 0.012, pal.lenco), k=0.012)
        tronco = _tronco_bob(pal.camisa).solda(Elipsoide((0, 0.355, 0.0), (0.15, 0.075, 0.125), pal.bermuda), 0.04)
        tronco = tronco.solda(Capsula((0, 0.58, 0), (0, 0.69, 0), 0.062, pal.pelo_corpo), 0.02).solda(lenco, 0.008)
        pint_tronco = []
        cores = dict(manga=pal.camisa, braco=pal.pelo_corpo, antebraco=pal.pelo_corpo, mao=pal.pata, coxa=pal.bermuda,
                     joelho=pal.pelo_corpo, canela=pal.pelo_corpo, pe=pal.pata, dedo=pal.dedo)
        estampa = {"tipo": "bolinhas", "base": "#F2443A", "cor": "#FFFFFF", "raio": 0.017, "y0": 0.44 - QUADRIL_Y,
                   "dy": 0.052, "fileiras": 3, "n0": 11, "y_max": 0.6 - QUADRIL_Y}
        rabo = _rabo_bob(pal)
        extra["helice"] = helice(pal)
        extra["perna"] = dict(barra=pal.bermuda)
    return pal, (cab, pint_cab), (tronco, pint_tronco), cores, rabo, estampa, extra


def mia_fantasia(roupa):
    c = CABECA_C
    larg = 1.02
    extra = {}
    if roupa == "pirata":
        pal = _paleta_mia(blusa=hex_cor("#F6F1E6"), saia=hex_cor("#E8344E"), bandana=hex_cor("#E53935"),
                          bolinha_bandana=hex_cor("#FFFFFF"), cinto=hex_cor("#6B3E1E"), ouro=hex_cor("#FFC93C"),
                          bota=hex_cor("#5A3420"), dobra=hex_cor("#8A5634"))
        extra["perna"] = dict(cano=(pal.bota, pal.dobra))
        band = bandana(c, larg, pal)
        cab = orelhas_mia(cabeca_base(pal.pelo, pal.focinho, pal.nariz, largura=larg), c, pal.orelha) | band
        pint_cab = [Pintura(fora_de(band, dentro_orelha_mia(c)), pal.orelha_dentro),
                    Pintura(fora_de(band, listras_mia(c)), pal.listra), bolinhas_bandana(c, pal, band)]
        roupa_cor, saia_cor, manga = pal.blusa, pal.saia, pal.blusa
        estampa = {"tipo": "listras", "base": "#F6F1E6", "cor": "#1E6FD9", "y0": 0.45 - QUADRIL_Y, "periodo": 0.042,
                   "raio": 0.011, "y_max": 0.63 - QUADRIL_Y}
        cores = dict(manga=manga, braco=pal.pelo_corpo, antebraco=pal.pelo_corpo, mao=pal.pata, coxa=pal.pelo_corpo,
                     joelho=pal.pelo_corpo, canela=pal.pelo_corpo, pe=pal.bota, dedo=pal.bota)
        gola = None
        rabo = _rabo_mia(pal)
        enfeite = cinto(0.455, 0.152, pal)
    elif roupa == "dino":
        pal = _paleta_mia(fantasia=hex_cor("#B07CF0"), barriga=hex_cor("#FFD6EC"), espinho=hex_cor("#FF5FA2"),
                          dente=hex_cor("#FFFFFF"), olho_dino=hex_cor("#FFFFFF"), pupila=hex_cor("#1B1530"),
                          unha=hex_cor("#FFFFFF"))
        cab = cabeca_base(pal.pelo, pal.focinho, pal.nariz, largura=larg)
        cab = cab | capuz(c, larg, 0.042, pal.fantasia) | enfeites_dino(c, larg, 0.042, pal)
        pint_cab = [Pintura(listras_mia(c, True), pal.listra), forro(c, larg, 0.042, pal.barriga)]
        roupa_cor, saia_cor, manga = pal.fantasia, pal.fantasia, pal.fantasia
        estampa = {}
        cores = dict(manga=manga, braco=pal.fantasia, antebraco=pal.fantasia, mao=pal.pata, coxa=pal.fantasia,
                     joelho=pal.fantasia, canela=pal.fantasia, pe=pal.fantasia, dedo=pal.fantasia)
        extra["perna"] = dict(garras=pal.unha)
        gola = None
        rabo = rabo_dino(pal.fantasia, pal.espinho)
        extra["rabo_caixa"] = ((-0.16, 0.16, -0.52), (0.16, 0.58, -0.04))
        enfeite = espinhos_costas(pal)
    elif roupa == "astronauta":
        pal = _paleta_mia(traje=hex_cor("#F2F4F8"), detalhe=hex_cor("#FF5FA2"), cinza=hex_cor("#7D8799"),
                          luva=hex_cor("#C3CAD6"), luz=hex_cor("#FFD54F", 0.5), vermelho=hex_cor("#FF4D4D"),
                          amarelo=hex_cor("#FFD43B"), verde=hex_cor("#3DDC84"), tela=hex_cor("#1B2B4A"))
        cab = cabeca_base(pal.pelo, pal.focinho, pal.nariz, largura=larg)
        cab = cab | capuz(c, larg, 0.05, pal.traje) | enfeites_capacete(c, larg, 0.05, pal)
        pint_cab = [Pintura(listras_mia(c, True), pal.listra), faixa_capacete(c, larg, 0.05, pal),
                    forro(c, larg, 0.05, pal.detalhe)]
        roupa_cor, saia_cor, manga = pal.traje, pal.traje, pal.traje
        estampa = {}
        cores = dict(manga=manga, braco=pal.traje, antebraco=pal.traje, mao=pal.luva, coxa=pal.traje,
                     joelho=pal.traje, canela=pal.traje, pe=pal.luva, dedo=pal.luva)
        extra["braco"] = dict(punho=pal.detalhe)
        extra["perna"] = dict(cano=(pal.luva, pal.detalhe))
        gola = None
        rabo = _rabo_mia(pal, pal.traje, pal.detalhe)
        enfeite = mochila_e_painel(pal)
    else:  # parque
        pal = _paleta_mia(vestido=hex_cor("#2BC4A0"), gola=hex_cor("#FFFFFF"), bone_a=hex_cor("#FF7AB8"),
                          bone_b=hex_cor("#B07CF0"), bone_c=hex_cor("#FFD43B"), aba=hex_cor("#FF7AB8"),
                          helice_a=hex_cor("#FF7AB8"), helice_b=hex_cor("#2BC4A0"))
        bo = bone(c, pal)
        cab = orelhas_mia(cabeca_base(pal.pelo, pal.focinho, pal.nariz, largura=larg), c, pal.orelha).solda(bo, 0.01)
        # o boné cobre a testa (sem listrinhas); o rosa só dentro das orelhas
        pint_cab = [Pintura(fora_de(bo, dentro_orelha_mia(c)), pal.orelha_dentro)] + gomos_bone(c, pal)
        roupa_cor, saia_cor, manga = pal.vestido, pal.vestido, pal.vestido
        estampa = {"tipo": "bolinhas", "base": "#2BC4A0", "cor": "#FFE14D", "raio": 0.019, "y0": 0.31 - QUADRIL_Y,
                   "dy": 0.05, "fileiras": 3, "n0": 12, "y_max": 0.44 - QUADRIL_Y}
        cores = dict(manga=manga, braco=pal.pelo_corpo, antebraco=pal.pelo_corpo, mao=pal.pata, coxa=pal.pelo_corpo,
                     joelho=pal.pelo_corpo, canela=pal.pelo_corpo, pe=pal.pata, dedo=pal.dedo)
        gola = unir(Elipsoide((0.04, 0.603, 0.06), (0.05, 0.022, 0.04), pal.gola, rot=rot_z(-0.25)),
                    Elipsoide((-0.04, 0.603, 0.06), (0.05, 0.022, 0.04), pal.gola, rot=rot_z(0.25)),
                    Toro((0, 0.612, 0.0), 0.072, 0.02, pal.gola), k=0.01)
        rabo = _rabo_mia(pal)
        enfeite = None
        extra["helice"] = helice(pal)
    blusa = Elipsoide((0, 0.515, 0), (0.152, 0.135, 0.125), roupa_cor)
    ombros = Capsula((-0.115, 0.565, 0), (0.115, 0.565, 0), 0.056, roupa_cor)
    saia = Intersecao(ConeRedondo((0, 0.46, 0), (0, 0.3, 0), 0.15, 0.215, saia_cor),
                      SemiEspaco((0, 0.27, 0), (0, -1, 0)), 0.03)
    pescoco_cor = pal.fantasia if roupa == "dino" else (pal.traje if roupa == "astronauta" else pal.pelo_corpo)
    pescoco = Capsula((0, 0.58, 0), (0, 0.69, 0), 0.058, pescoco_cor)
    tronco = blusa.solda(ombros, 0.05).solda(saia, 0.05).solda(pescoco, 0.02)
    if gola is not None:
        tronco = tronco.solda(gola, 0.006)
    if enfeite is not None:
        tronco = tronco | enfeite
    if roupa == "dino":
        tronco = tronco.solda(barriga(pal.barriga, 0.112), 0.012)
    pint_tronco = pinturas_traje(pal) if roupa == "astronauta" else []
    return pal, (cab, pint_cab), (tronco, pint_tronco), cores, rabo, estampa, extra


# ------------------------------------------------------------- montagem (como personagens.gerar_personagem)

def gerar_fantasia(nome, roupa, pasta):
    fabrica = bob_fantasia if nome == "bob" else mia_fantasia
    pal, (cabeca, pint_cab), (tronco, pint_tronco), cores, rabo, estampa, extra = fabrica(roupa)
    alfa = alfa_por_cor(pal)
    pac = Pacote()

    def malha(forma, pint, bmin, bmax):
        return gerar_malha(forma, bmin, bmax, PASSO, pal.cores, pint, mascara_rosto=alfa)

    def sem_rosto(forma, pint, bmin, bmax):
        return gerar_malha(forma, bmin, bmax, PASSO, pal.cores, pint, mascara_rosto=lambda P, c: np.zeros(len(P)))

    q = np.array([0, QUADRIL_Y, 0])
    pac.adicionar("corpo", sem_rosto(tronco, pint_tronco, (-0.3, 0.22, -0.3), (0.3, 0.79, 0.26)), "", q, q)
    pc = np.array([0, PESCOCO_Y, 0])
    pac.adicionar("cabeca", malha(cabeca, pint_cab, (-0.46, 0.55, -0.44), (0.46, 1.36, 0.38)), "corpo", pc - q, pc)
    caixa = extra.get("rabo_caixa", ((-0.14, 0.32, -0.42), (0.14, 0.74, -0.06)))
    pac.adicionar("rabo", sem_rosto(rabo, [], caixa[0], caixa[1]), "corpo", RABO - q, RABO)
    for lado, s in (("e", 1), ("d", -1)):
        sup, inf = braco(s, cores, **extra.get("braco", {}))
        om, co = espelho(OMBRO, s), espelho(COTOVELO, s)
        xs = sorted([s * 0.06, s * 0.3])
        pac.adicionar("braco_" + lado, sem_rosto(sup, [], (xs[0], 0.38, -0.12), (xs[1], 0.66, 0.12)), "corpo", om - q, om)
        xs = sorted([s * 0.12, s * 0.34])
        pac.adicionar("antebraco_" + lado, sem_rosto(inf, [], (xs[0], 0.26, -0.1), (xs[1], 0.53, 0.12)), "braco_" + lado, co - om, co)
    for lado, s in (("e", 1), ("d", -1)):
        sup, inf, pe, pint, pint_canela = perna(s, cores, **extra.get("perna", {}))
        qq, jj, tt = espelho(QUADRIL, s), espelho(JOELHO, s), espelho(TORNOZELO, s)
        x = qq[0]
        pac.adicionar("coxa_" + lado, sem_rosto(sup, [], (x - 0.09, 0.15, -0.09), (x + 0.09, 0.45, 0.09)), "corpo", qq - q, qq)
        pac.adicionar("canela_" + lado, sem_rosto(inf, pint_canela, (x - 0.08, 0.04, -0.08), (x + 0.08, 0.28, 0.09)),
                      "coxa_" + lado, jj - qq, jj)
        pac.adicionar("pe_" + lado, sem_rosto(pe, pint, (x - 0.09, -0.02, -0.08), (x + 0.09, 0.14, 0.15)), "canela_" + lado, tt - jj, tt)
    if "helice" in extra:
        h = HELICE
        pac.adicionar("helice", sem_rosto(extra["helice"], [], (h[0] - 0.17, h[1] - 0.05, -0.07), (h[0] + 0.17, h[1] + 0.06, 0.07)),
                      "cabeca", h - pc, h)
    meta = {
        "rosto": {"centro": list(ROSTO_CENTRO), "tamanho": list(ROSTO_TAMANHO)},
        "mao_d": [float(v) for v in (espelho(MAO, -1) - espelho(COTOVELO, -1))],
        "tornozelo_y": float(TORNOZELO[1]),
        "estampa": estampa,
        "roupa": roupa,
    }
    pac.gravar(os.path.join(pasta, "%s_%s" % (nome, roupa)), meta=meta)
