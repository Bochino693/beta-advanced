# -*- coding: utf-8 -*-
"""
PERSONAGENS DO STRIKE KIDS: BOB (cachorrinho) E MIA (gatinha)
=============================================================

Mascotes de pelúcia: cabeça grande e redonda (proporção de bebê: olhos no
meio do rosto, testa grande), corpinho de pera, bracinhos e perninhas
curtos e gordinhos, pés de sola chata (pisam firme no chão), cores em
blocos limpos — nada de manchas tortas.

  * BOB — cachorrinho caramelo, focinho e patas creme, orelhas caídas
    marrons, camiseta azul com estrela amarela, lenço vermelho e
    rabinho enroladinho.
  * MIA — gatinha cinza-clarinha com três listrinhas na testa, focinho e
    peito brancos, orelhas pontudas rosadas por dentro, laço azul,
    roupinha laranja de bolinhas brancas e golinha, rabo comprido.

ESTAMPAS (estrela do Bob, bolinhas da Mia): NÃO são pintadas nos vértices
— são desenhadas no shader (shaders/toon_personagem.gdshader) a partir dos
dados em meta["estampa"]: bordas perfeitas em qualquer resolução (4K).

Rig (juntas): corpo (quadril) > cabeça, rabo, braço > antebraço,
coxa > canela > pé. O pé separado é o que deixa o jogo travar a sola no
chão (IK de pernas em scripts/personagem.gd).

Cor do vértice: RGB = cor (sRGB); ALFA = 1 onde o desenho do rosto pode
aparecer (pelo da cara e focinho), 0 = normal.
"""
import os

import numpy as np

from sdf import (Capsula, ConeRedondo, Elipsoide, Esfera, Intersecao, Pacote, Pintura, SemiEspaco, Toro,
                 gerar_malha, hex_cor, rot_x, rot_y, rot_z, unir)

# ------------------------------------------------------------- juntas (metros, ele olha para +Z)
QUADRIL_Y = 0.36
PESCOCO_Y = 0.635
OMBRO = np.array([0.150, 0.565, 0.0])
COTOVELO = np.array([0.198, 0.468, 0.006])
PULSO = np.array([0.226, 0.386, 0.014])
MAO = np.array([0.236, 0.352, 0.018])          # centro da patinha (onde a bola encaixa)
QUADRIL = np.array([0.086, 0.36, 0.0])
JOELHO = np.array([0.086, 0.215, 0.006])
TORNOZELO = np.array([0.086, 0.078, 0.0])
RABO = np.array([0.0, 0.40, -0.135])

CABECA_C = np.array([0.0, 0.865, 0.0])         # centro da cabeça
ROSTO_CENTRO = (0.0, 0.205)                    # em relação ao pescoço (onde o desenho do rosto é projetado)
ROSTO_TAMANHO = (0.46, 0.40)

ROSTO = 1.0
PASSO = 0.0082


class Paleta:
    def __init__(self, **cores):
        self.nomes = list(cores.keys())
        self.cores = [cores[n] for n in self.nomes]

    def __getattr__(self, nome):
        nomes = self.__dict__.get("nomes", [])
        if nome in nomes:
            return nomes.index(nome)
        raise AttributeError(nome)


def alfa_por_cor(pal):
    alfas = np.array([c[3] for c in pal.cores], dtype=np.float32)

    def f(P, cids):
        return alfas[cids]
    return f


def espelho(v, s):
    return np.array([v[0] * s, v[1], v[2]])


# ------------------------------------------------------------- cabeça

def cabeca_base(pelo, focinho, nariz, largura=1.0):
    """Cabeça redonda (um pouco mais larga que alta), bochechas fofas que
    descem até o focinho, focinho clarinho e narizinho 3D."""
    c = CABECA_C
    cranio = Elipsoide(c, (0.272 * largura, 0.246, 0.244), pelo)
    cab = cranio
    for s in (1, -1):   # bochechas fofinhas
        cab = cab.solda(Elipsoide(c + np.array([s * 0.118, -0.092, 0.078]), (0.13, 0.11, 0.12), pelo), 0.07)
    foc = Elipsoide(c + np.array([0.0, -0.082, 0.172]), (0.112, 0.07, 0.085), focinho)
    cab = cab.solda(foc, 0.05)
    nar = Elipsoide(c + np.array([0.0, -0.05, 0.248]), (0.04, 0.027, 0.025), nariz)
    return cab.solda(nar, 0.008)


# ------------------------------------------------------------- membros

def braco(s, cores):
    """(superior, inferior). s = +1 lado esquerdo do personagem (+x)."""
    om, co, pu, mao = espelho(OMBRO, s), espelho(COTOVELO, s), espelho(PULSO, s), espelho(MAO, s)
    manga = Elipsoide(om + np.array([s * 0.012, -0.018, 0.0]), (0.07, 0.072, 0.066), cores["manga"])
    sup = Capsula(om, co, 0.044, cores["pelo"], rb=0.041)
    superior = manga.solda(sup, 0.022).solda(Esfera(co, 0.041, cores["pelo"]), 0.015)
    inf = Capsula(co, pu, 0.04, cores["pelo"], rb=0.038)
    pata = Elipsoide(mao, (0.054, 0.058, 0.052), cores["pata"])
    inferior = inf.solda(pata, 0.03)
    return superior, inferior


def perna(s, cores):
    """(coxa, canela, pé, pinturas do pé)."""
    q, j, t = espelho(QUADRIL, s), espelho(JOELHO, s), espelho(TORNOZELO, s)
    coxa = Capsula(q + np.array([0, 0.02, 0]), j, 0.057, cores["coxa"], rb=0.05)
    superior = coxa.solda(Esfera(j, 0.049, cores["pelo"]), 0.015)
    inferior = Capsula(j, t + np.array([0, 0.01, 0]), 0.048, cores["pelo"], rb=0.045)
    # pé: almofada redonda com SOLA CHATA (pisa firme)
    pe = Elipsoide((t[0], 0.05, 0.03), (0.064, 0.056, 0.09), cores["pata"])
    pe = pe.solda(Esfera((t[0], 0.075, 0.0), 0.045, cores["pata"]), 0.03)
    pe = Intersecao(pe, SemiEspaco((0, 0.003, 0), (0, -1, 0)), 0.012)
    x = t[0]

    def dedos(P, x=x):
        return (P[:, 2] > 0.085) & (P[:, 1] < 0.065) & (np.abs(np.abs(P[:, 0] - x) - 0.021) < 0.0045)
    return superior, inferior, pe, [Pintura(dedos, cores["dedo"])]


# ------------------------------------------------------------- BOB (cachorrinho)

def bob():
    pal = Paleta(
        pelo=hex_cor("#E9A55B", ROSTO),
        focinho=hex_cor("#FFF1DE", ROSTO),
        nariz=hex_cor("#3A2422"),
        orelha=hex_cor("#A9652F"),
        camisa=hex_cor("#1FB2C8"),
        estampa=hex_cor("#FFD43B"),
        lenco=hex_cor("#FF5A4E"),
        pata=hex_cor("#FFF1DE"),
        dedo=hex_cor("#E2C3A0"),
        pelo_corpo=hex_cor("#E9A55B"),
    )
    c = CABECA_C
    cabeca = cabeca_base(pal.pelo, pal.focinho, pal.nariz)
    # topetinho (três fiozinhos enrolados)
    topete = unir(Esfera(c + np.array([0.012, 0.226, 0.085]), 0.026, pal.pelo),
                  Esfera(c + np.array([-0.022, 0.222, 0.092]), 0.02, pal.pelo), k=0.02)
    cabeca = cabeca.solda(topete, 0.04)
    for s in (1, -1):   # orelhas caídas, macias, presas no alto da cabeça
        orelha = Elipsoide(c + np.array([s * 0.262, -0.035, -0.035]), (0.068, 0.165, 0.105), pal.orelha,
                           rot=rot_z(s * 0.28) @ rot_x(0.12))
        cabeca = cabeca.solda(orelha, 0.03)
    pint_cab = []

    cores = dict(pelo=pal.pelo_corpo, manga=pal.camisa, pata=pal.pata, coxa=pal.pelo_corpo, dedo=pal.dedo)
    peito = Elipsoide((0, 0.515, 0.0), (0.158, 0.142, 0.13), pal.camisa)
    barriga = Elipsoide((0, 0.42, 0.006), (0.172, 0.118, 0.142), pal.camisa)
    ombros = Capsula((-0.118, 0.565, 0), (0.118, 0.565, 0), 0.058, pal.camisa)
    quadril = Elipsoide((0, 0.355, 0.0), (0.15, 0.075, 0.125), pal.pelo_corpo)
    pescoco = Capsula((0, 0.58, 0), (0, 0.69, 0), 0.062, pal.pelo_corpo)
    lenco = unir(Toro((0, 0.615, 0.0), 0.078, 0.026, pal.lenco),
                 ConeRedondo((0, 0.6, 0.085), (0, 0.53, 0.128), 0.044, 0.012, pal.lenco), k=0.012)
    tronco = peito.solda(barriga, 0.06).solda(ombros, 0.05).solda(quadril, 0.04).solda(pescoco, 0.02)
    # lenço "costurado" na camiseta (emenda lisa, sem vinco nem risco)
    tronco = tronco.solda(lenco, 0.008)
    pint_tronco = []
    # estrela amarela no peito (desenhada no shader)
    estampa = {"tipo": "estrela", "base": "#1FB2C8", "cor": "#FFD43B", "centro": [0.0, 0.452 - QUADRIL_Y],
               "raio": 0.064, "dentro": 0.5}
    # rabinho enroladinho para cima
    r0 = RABO
    rabo = unir(Capsula(r0, r0 + np.array([0, 0.07, -0.06]), 0.036, pal.pelo_corpo, rb=0.032),
                Capsula(r0 + np.array([0, 0.07, -0.06]), r0 + np.array([0, 0.13, -0.05]), 0.032, pal.pelo_corpo, rb=0.03),
                Esfera(r0 + np.array([0, 0.145, -0.035]), 0.036, pal.focinho), k=0.025)
    return pal, (cabeca, pint_cab), (tronco, pint_tronco), cores, rabo, estampa


# ------------------------------------------------------------- MIA (gatinha)

def mia():
    pal = Paleta(
        pelo=hex_cor("#C9CEDE", ROSTO),
        focinho=hex_cor("#FFFFFF", ROSTO),
        listra=hex_cor("#9AA2BA", ROSTO),
        nariz=hex_cor("#FF8FA6"),
        orelha=hex_cor("#C9CEDE"),
        orelha_dentro=hex_cor("#FFB8C8"),
        vestido=hex_cor("#FF8A2B"),
        gola=hex_cor("#FFFFFF"),
        laco=hex_cor("#1E9BE0"),
        pata=hex_cor("#FFFFFF"),
        dedo=hex_cor("#FFC6D3"),
        pelo_corpo=hex_cor("#C9CEDE"),
        bolinha=hex_cor("#FFFFFF"),
        rabo_ponta=hex_cor("#9AA2BA"),
    )
    c = CABECA_C
    cabeca = cabeca_base(pal.pelo, pal.focinho, pal.nariz, largura=1.02)
    for s in (1, -1):   # orelhas pontudas de pontinha redonda
        base = c + np.array([s * 0.155, 0.17, -0.03])
        ponta = c + np.array([s * 0.215, 0.33, -0.045])
        cabeca = cabeca.solda(ConeRedondo(base, ponta, 0.088, 0.024, pal.orelha), 0.045)
    no = c + np.array([0.19, 0.205, 0.07])   # laço amarelo na orelha
    laco = unir(Esfera(no, 0.028, pal.laco),
                Elipsoide(no + np.array([0.045, 0.018, 0.0]), (0.046, 0.032, 0.02), pal.laco, rot=rot_z(0.35) @ rot_y(0.3)),
                Elipsoide(no + np.array([-0.045, -0.018, 0.0]), (0.046, 0.032, 0.02), pal.laco, rot=rot_z(0.35) @ rot_y(0.3)), k=0.012)
    cabeca = cabeca | laco

    def dentro_orelha(P):
        r = np.zeros(len(P), dtype=bool)
        for s in (1, -1):
            # triângulo arredondado na frente da orelha
            b = c + np.array([s * 0.158, 0.19, 0.0])
            d = P - b
            h = d[:, 1]
            meia = 0.052 - h * 0.3
            r |= (P[:, 2] > c[2] - 0.02) & (h > 0.0) & (h < 0.125) & (np.abs(d[:, 0] - s * h * 0.36) < meia)
        # o laço fica por cima da orelha: não pinta o laço
        return r & (np.linalg.norm(P - no, axis=1) > 0.075)

    def listras(P):
        # três listrinhas curvas na testa (a do meio maior)
        q = P - c
        frente = q[:, 2] > 0.1
        r = np.zeros(len(P), dtype=bool)
        for x0, comp in ((-0.058, 0.07), (0.0, 0.095), (0.058, 0.07)):
            topo = 0.235
            dx = q[:, 0] - x0 * (1.0 + (topo - q[:, 1]) * 1.2)
            dentro = (q[:, 1] < topo) & (q[:, 1] > topo - comp)
            largura = 0.015 * np.clip((q[:, 1] - (topo - comp)) / comp, 0.0, 1.0) ** 0.6 + 0.002
            r |= frente & dentro & (np.abs(dx) < largura)
        return r
    pint_cab = [Pintura(dentro_orelha, pal.orelha_dentro), Pintura(listras, pal.listra)]

    cores = dict(pelo=pal.pelo_corpo, manga=pal.vestido, pata=pal.pata, coxa=pal.pelo_corpo, dedo=pal.dedo)
    blusa = Elipsoide((0, 0.515, 0), (0.152, 0.135, 0.125), pal.vestido)
    ombros = Capsula((-0.115, 0.565, 0), (0.115, 0.565, 0), 0.056, pal.vestido)
    # saia rodada com BARRA de verdade: cortada reta em y = 0,27 e com a
    # quina arredondada (antes a caixa da malha cortava a saia e a barra
    # ficava aberta e serrilhada)
    saia = Intersecao(ConeRedondo((0, 0.46, 0), (0, 0.3, 0), 0.15, 0.215, pal.vestido),
                      SemiEspaco((0, 0.27, 0), (0, -1, 0)), 0.03)
    gola = unir(Elipsoide((0.04, 0.603, 0.06), (0.05, 0.022, 0.04), pal.gola, rot=rot_z(-0.25)),
                Elipsoide((-0.04, 0.603, 0.06), (0.05, 0.022, 0.04), pal.gola, rot=rot_z(0.25)),
                Toro((0, 0.612, 0.0), 0.072, 0.02, pal.gola), k=0.01)
    pescoco = Capsula((0, 0.58, 0), (0, 0.69, 0), 0.058, pal.pelo_corpo)
    tronco = blusa.solda(ombros, 0.05).solda(saia, 0.05).solda(pescoco, 0.02).solda(gola, 0.006)
    pint_tronco = []
    # bolinhas brancas na saia, em fileiras desencontradas (desenhadas no shader)
    estampa = {"tipo": "bolinhas", "base": "#FF8A2B", "cor": "#FFFFFF", "raio": 0.019,
               "y0": 0.31 - QUADRIL_Y, "dy": 0.05, "fileiras": 3, "n0": 12, "y_max": 0.44 - QUADRIL_Y}
    # rabo comprido e curvado, pontinha mais escura
    p0 = RABO
    p1 = RABO + np.array([0.0, 0.02, -0.13])
    p2 = RABO + np.array([0.025, 0.15, -0.2])
    p3 = RABO + np.array([0.055, 0.27, -0.15])
    rabo = unir(Capsula(p0, p1, 0.031, pal.pelo_corpo), Capsula(p1, p2, 0.03, pal.pelo_corpo),
                Capsula(p2, p3, 0.03, pal.rabo_ponta, rb=0.034), k=0.03)
    return pal, (cabeca, pint_cab), (tronco, pint_tronco), cores, rabo, estampa


# ------------------------------------------------------------- montagem

def gerar_personagem(nome, fabrica, pasta):
    pal, (cabeca, pint_cab), (tronco, pint_tronco), cores, rabo, estampa = fabrica()
    alfa = alfa_por_cor(pal)
    pac = Pacote()

    def malha(forma, pint, bmin, bmax):
        return gerar_malha(forma, bmin, bmax, PASSO, pal.cores, pint, mascara_rosto=alfa)

    def sem_rosto(forma, pint, bmin, bmax):
        return gerar_malha(forma, bmin, bmax, PASSO, pal.cores, pint, mascara_rosto=lambda P, c: np.zeros(len(P)))

    q = np.array([0, QUADRIL_Y, 0])
    pac.adicionar("corpo", sem_rosto(tronco, pint_tronco, (-0.3, 0.22, -0.26), (0.3, 0.79, 0.26)), "", q, q)
    pc = np.array([0, PESCOCO_Y, 0])
    pac.adicionar("cabeca", malha(cabeca, pint_cab, (-0.42, 0.55, -0.4), (0.42, 1.26, 0.36)), "corpo", pc - q, pc)
    pac.adicionar("rabo", sem_rosto(rabo, [], (-0.14, 0.32, -0.42), (0.14, 0.74, -0.06)), "corpo", RABO - q, RABO)
    for lado, s in (("e", 1), ("d", -1)):
        sup, inf = braco(s, cores)
        om, co = espelho(OMBRO, s), espelho(COTOVELO, s)
        xs = sorted([s * 0.06, s * 0.3])
        pac.adicionar("braco_" + lado, sem_rosto(sup, [], (xs[0], 0.38, -0.12), (xs[1], 0.66, 0.12)), "corpo", om - q, om)
        xs = sorted([s * 0.12, s * 0.34])
        pac.adicionar("antebraco_" + lado, sem_rosto(inf, [], (xs[0], 0.26, -0.1), (xs[1], 0.53, 0.12)), "braco_" + lado, co - om, co)
    for lado, s in (("e", 1), ("d", -1)):
        sup, inf, pe, pint = perna(s, cores)
        qq, jj, tt = espelho(QUADRIL, s), espelho(JOELHO, s), espelho(TORNOZELO, s)
        x = qq[0]
        pac.adicionar("coxa_" + lado, sem_rosto(sup, [], (x - 0.09, 0.15, -0.09), (x + 0.09, 0.45, 0.09)), "corpo", qq - q, qq)
        pac.adicionar("canela_" + lado, sem_rosto(inf, [], (x - 0.08, 0.04, -0.08), (x + 0.08, 0.28, 0.09)), "coxa_" + lado, jj - qq, jj)
        pac.adicionar("pe_" + lado, sem_rosto(pe, pint, (x - 0.09, -0.02, -0.08), (x + 0.09, 0.14, 0.15)), "canela_" + lado, tt - jj, tt)
    pac.gravar(os.path.join(pasta, nome), meta={
        "rosto": {"centro": list(ROSTO_CENTRO), "tamanho": list(ROSTO_TAMANHO)},
        "mao_d": [float(v) for v in (espelho(MAO, -1) - espelho(COTOVELO, -1))],
        "tornozelo_y": float(TORNOZELO[1]),
        "estampa": estampa,
    })
