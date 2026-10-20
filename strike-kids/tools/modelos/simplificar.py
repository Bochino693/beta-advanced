"""SIMPLIFICADOR DE MALHAS — deixa o jogo leve na TV Box sem perder o desenho.

As malhas saem do modelador (Surface Nets) com triângulos do mesmo tamanho
no corpo inteiro: muito mais do que a tela precisa (o Bob tinha 120 mil).
Aqui cada peça é simplificada pelo meshoptimizer levando em conta a
POSIÇÃO, a NORMAL e a COR de cada vértice: as partes lisas viram poucos
triângulos grandes e as bordas de cor (roupas, listras, pintas, a máscara
do rosto) continuam nítidas. Bordas abertas (objetos cortados no chão)
ficam presas no lugar.

Lê   tools/modelos/saida/<pacote>.json/.bin  (o que o modelos.py gravou)
Grava tools/modelos/saida/leve/<pacote>.json/.bin (o assar_modelos.gd usa
estes quando existem).

Uso: python3 tools/modelos/simplificar.py   (precisa: pip install meshoptimizer)
"""
import ctypes
import json
import os

import numpy as np
import meshoptimizer as mo
from meshoptimizer._loader import lib as _lib

# a ligação Python não declara os tipos desta função: declarados aqui
_P = ctypes.c_void_p
_lib.meshopt_simplifyWithAttributes.argtypes = [
    _P, _P, ctypes.c_size_t, _P, ctypes.c_size_t, ctypes.c_size_t, _P, ctypes.c_size_t,
    _P, ctypes.c_size_t, _P, ctypes.c_size_t, ctypes.c_float, ctypes.c_uint, _P]
_lib.meshopt_simplifyWithAttributes.restype = ctypes.c_size_t

PASTA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "saida")
LEVE = os.path.join(PASTA, "leve")

# orçamento de triângulos de cada pacote: fração do original, mínimo e máximo
# por peça, e o erro aceito (fração do tamanho da peça)
ORCAMENTO = {
    "bob": (0.22, 700, 12000, 0.006),
    "mia": (0.22, 700, 12000, 0.006),
    "pino": (0.16, 2400, 2400, 0.004),
    "cenario": (0.10, 500, 4000, 0.02),
    "temas": (0.10, 500, 4000, 0.02),
}
# as roupinhas das fases (roupas.py): o mesmo orçamento do personagem
for _quem in ("bob", "mia"):
    for _roupa in ("pirata", "dino", "astronauta", "parque"):
        ORCAMENTO["%s_%s" % (_quem, _roupa)] = ORCAMENTO[_quem]

# peças repetidas centenas de vezes (lâmpadas): orçamento próprio
POR_PECA = {"lampada": 48, "balao": 400, "nuvem": 500, "cabine": 1200, "navio": 9000}

PESO_NORMAL = 0.35
PESO_COR = 1.2


def ler(nome):
    with open(os.path.join(PASTA, nome + ".json"), encoding="utf-8") as f:
        info = json.load(f)
    with open(os.path.join(PASTA, nome + ".bin"), "rb") as f:
        blob = f.read()
    return info, blob


def pegar(blob, faixa, tipo, colunas):
    ini, tam = faixa
    return np.frombuffer(blob, dtype=tipo, count=tam // np.dtype(tipo).itemsize, offset=ini).reshape(-1, colunas).copy()


def simplificar(v, n, c, i, alvo, erro):
    indices = i.reshape(-1).astype(np.uint32)
    if len(indices) // 3 <= alvo:
        return v, n, c, i
    attrs = np.ascontiguousarray(np.hstack([n, c]).astype(np.float32))
    pesos = np.array([PESO_NORMAL] * 3 + [PESO_COR] * 4, dtype=np.float32)
    destino = np.zeros_like(indices)
    pos = np.ascontiguousarray(v, dtype=np.float32)
    qtd = _lib.meshopt_simplifyWithAttributes(
        destino.ctypes.data, indices.ctypes.data, len(indices), pos.ctypes.data, len(pos), 12,
        attrs.ctypes.data, attrs.shape[1] * 4, pesos.ctypes.data, len(pesos), None,
        alvo * 3, erro, mo.SIMPLIFY_LOCK_BORDER, None)
    novos = destino[:qtd]
    # cache de vértices da placa de vídeo
    otim = np.zeros_like(novos)
    mo.optimize_vertex_cache(otim, novos, vertex_count=len(v))
    # só os vértices usados, na ordem em que aparecem (leitura em sequência)
    _, primeiro = np.unique(otim, return_index=True)
    seq = otim[np.sort(primeiro)].astype(np.int64)
    ordem = np.full(len(v), -1, dtype=np.int64)
    ordem[seq] = np.arange(len(seq))
    return v[seq], n[seq], c[seq], ordem[otim].reshape(-1, 3).astype(np.int32)


def pacote(nome):
    info, blob = ler(nome)
    frac, minimo, maximo, erro = ORCAMENTO[nome]
    saida = bytearray()
    antes = depois = 0
    for parte in info["partes"]:
        v = pegar(blob, parte["v"], np.float32, 3)
        n = pegar(blob, parte["n"], np.float32, 3)
        c = pegar(blob, parte["c"], np.float32, 4)
        i = pegar(blob, parte["i"], np.int32, 3)
        alvo = int(np.clip(len(i) * frac, minimo, maximo))
        if parte["nome"] in POR_PECA:
            alvo = POR_PECA[parte["nome"]]
        v2, n2, c2, i2 = simplificar(v, n, c, i, alvo, erro)
        antes += len(i)
        depois += len(i2)
        parte["vertices"] = int(len(v2))
        parte["triangulos"] = int(len(i2))
        for chave, arr in (("v", v2), ("n", n2), ("c", c2), ("i", i2)):
            arr = np.ascontiguousarray(arr)
            parte[chave] = [len(saida), int(arr.nbytes)]
            saida += arr.tobytes()
            while len(saida) % 4:
                saida += b"\0"
    os.makedirs(LEVE, exist_ok=True)
    with open(os.path.join(LEVE, nome + ".bin"), "wb") as f:
        f.write(bytes(saida))
    with open(os.path.join(LEVE, nome + ".json"), "w", encoding="utf-8") as f:
        json.dump(info, f, ensure_ascii=False, indent=1)
    print("  %-10s %8d -> %7d triângulos (%.0f%%)" % (nome, antes, depois, 100.0 * depois / max(antes, 1)))


def main():
    for nome in ORCAMENTO:
        if os.path.exists(os.path.join(PASTA, nome + ".json")):
            pacote(nome)


if __name__ == "__main__":
    main()
