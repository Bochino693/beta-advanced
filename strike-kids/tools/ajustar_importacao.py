# -*- coding: utf-8 -*-
"""
AJUSTA A IMPORTAÇÃO DAS IMAGENS (nitidez em 4K sem gastar memória à toa):
  * texturas 3D grandes (rostos, bola, madeira) e letreiros/logo: compressão
    de placa de vídeo de ALTA qualidade (BPTC no PC, ASTC na TV Box) + mipmaps;
  * imagens pequenas (partículas, retratos, estrelas, ícone): sem perda + mipmaps.
Mipmaps evitam o "pixel quebrado" (cintilar/serrilhar) quando a imagem
aparece menor do que é. Rode depois de gerar artes novas:
    python3 tools/ajustar_importacao.py
"""
import glob
import os
import re

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LETREIROS = {"strike", "spare", "ops", "boa", "uau", "quase", "super", "replay", "pegando_fogo", "fim_de_jogo",
             "novo_recorde", "empate", "parabens", "venceu", "logo"}


def regra(rel):
    nome = os.path.splitext(os.path.basename(rel))[0]
    if rel.startswith("texturas/"):
        if nome.startswith(("rosto_", "bola_")) or nome == "madeira":
            return 2, True
        return 0, False
    if rel.startswith("ui/marca/"):
        return (0, False) if nome == "fundo" else (2, True)
    if rel.startswith("ui/ceu/"):   # sol e lua: pequenos no céu, sem perda + mipmaps
        return 0, False
    if rel.startswith("ui/"):
        if nome in LETREIROS or nome.startswith("cen_"):
            return 2, True
        return 0, False
    return None


def ajustar(caminho, modo, hq):
    s = open(caminho, encoding="utf-8").read()
    novo = re.sub(r"compress/mode=\d+", "compress/mode=%d" % modo, s)
    novo = re.sub(r"compress/high_quality=\w+", "compress/high_quality=%s" % ("true" if hq else "false"), novo)
    novo = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=true", novo)
    novo = re.sub(r"detect_3d/compress_to=\d+", "detect_3d/compress_to=0", novo)
    if novo != s:
        open(caminho, "w", encoding="utf-8").write(novo)
        return True
    return False


def main():
    mudou = 0
    for imp in glob.glob(os.path.join(RAIZ, "texturas", "*.png.import")) + glob.glob(os.path.join(RAIZ, "ui", "*.png.import")) + \
            glob.glob(os.path.join(RAIZ, "ui", "marca", "*.png.import")) + glob.glob(os.path.join(RAIZ, "ui", "ceu", "*.png.import")):
        rel = os.path.relpath(imp, RAIZ).replace(os.sep, "/")[:-len(".import")]
        r = regra(rel)
        if r and ajustar(imp, *r):
            mudou += 1
            # força reimportar
            for f in glob.glob(os.path.join(RAIZ, ".godot", "imported", os.path.basename(rel) + "-*")):
                os.remove(f)
    print("importações ajustadas:", mudou)


if __name__ == "__main__":
    main()
