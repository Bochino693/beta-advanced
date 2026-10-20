# -*- coding: utf-8 -*-
"""
MONTA AS PEÇAS DE DIVULGAÇÃO a partir das imagens renderizadas pelo Godot
(tools/testes/poster.tscn) e dos retratos:

    python3 tools/testes/montar_posteres.py <render_vertical.png> <render_horizontal.png>

Gera em marketing/:
  poster_vertical_1080x1920.png  (stories, WhatsApp, cartaz)
  banner_horizontal_1920x1080.png (YouTube, Facebook, site)
  post_quadrado_1080x1080.png     (feed do Instagram)
  personagens.png                 (apresentação do Bob e da Mia)
  cenarios.png                    (os 4 cenários; renders em <pasta>/cenario_<tema>.png)
A marca Lazer & Sport aparece como no jogo (balão do Parque nas imagens);
nada de logo sobreposta.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
UI = os.path.join(RAIZ, "ui")
SAIDA = os.path.join(RAIZ, "marketing")
os.makedirs(SAIDA, exist_ok=True)
ROXO = (11, 31, 69)      # azul-marinho dos contornos (nome antigo mantido)


def fonte(nome, tam):
    return ImageFont.truetype(os.path.join(RAIZ, "fontes", nome), int(tam))


def texto_central(img, txt, y, tam, cor=(255, 255, 255), contorno=None, fonte_nome="fredoka_700.ttf"):
    d = ImageDraw.Draw(img)
    f = fonte(fonte_nome, tam)
    w = d.textlength(txt, font=f)
    c = contorno if contorno is not None else max(3, int(tam * 0.14))
    d.text(((img.width - w) / 2, y), txt, font=f, fill=cor, stroke_width=c, stroke_fill=ROXO)


def faixa(img, y, h, alpha=170):
    camada = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(camada)
    d.rectangle([0, y, img.width, y + h], fill=(6, 20, 48, alpha))
    camada = camada.filter(ImageFilter.GaussianBlur(18))
    img.alpha_composite(camada)


def logo(larg):
    lg = Image.open(os.path.join(UI, "logo.png")).convert("RGBA")
    return lg.resize((int(larg), int(larg * lg.height / lg.width)), Image.LANCZOS)


def vertical(caminho):
    img = Image.open(caminho).convert("RGBA").resize((1080, 1920), Image.LANCZOS)
    faixa(img, -60, 520, 120)
    faixa(img, 1520, 460, 190)
    lg = logo(980)
    img.alpha_composite(lg, ((1080 - lg.width) // 2, 50))
    texto_central(img, "BOLICHE INFANTIL 3D", 1560, 78)
    texto_central(img, "com BOB e MIA", 1660, 62, (255, 246, 168))
    texto_central(img, "5 sensores  ·  4 cenários  ·  1 ou 2 jogadores", 1760, 38)
    img.convert("RGB").save(os.path.join(SAIDA, "poster_vertical_1080x1920.png"))


def horizontal(caminho):
    img = Image.open(caminho).convert("RGBA").resize((1920, 1080), Image.LANCZOS)
    faixa(img, 860, 240, 190)
    # o letreiro do jogo (STRIKE KIDS em cima dos pinos) já é o logo da cena
    texto_central(img, "BOLICHE INFANTIL 3D  ·  BOB & MIA", 890, 70)
    texto_central(img, "5 sensores  ·  4 cenários  ·  física de verdade  ·  replay do strike  ·  foto da criança", 990, 36, (255, 246, 168))
    img.convert("RGB").save(os.path.join(SAIDA, "banner_horizontal_1920x1080.png"))


def quadrado(caminho_vertical):
    """Feed do Instagram: recorte do render vertical (os dois personagens e
    os pinos explodindo) + faixa de texto."""
    v = Image.open(caminho_vertical).convert("RGBA").resize((1080, 1920), Image.LANCZOS)
    q = v.crop((0, 470, 1080, 1550))
    faixa(q, 880, 240, 190)
    texto_central(q, "BOLICHE INFANTIL 3D", 905, 66)
    texto_central(q, "com Bob & Mia", 995, 40, (255, 246, 168))
    q.convert("RGB").save(os.path.join(SAIDA, "post_quadrado_1080x1080.png"))


def personagens():
    W, H = 1920, 1080
    img = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        c = (int(18 + (22 - 18) * t), int(58 + (155 - 58) * t), int(122 + (213 - 122) * t), 255)
        d.line([(0, y), (W, y)], fill=c)
    lg = logo(560)
    img.alpha_composite(lg, ((W - lg.width) // 2, 20))
    dados = [
        ("bob", "BOB", "o cachorrinho", ["Orelhas caídas e rabinho que abana", "Camiseta azul com estrela", "Pula girando quando faz STRIKE!"], (22, 155, 213)),
        ("mia", "MIA", "a gatinha", ["Rajadinha, de laço azul", "Roupa laranja de bolinhas", "Pulinhos, palmas e muita festa!"], (255, 122, 33)),
    ]
    for i, (nome, titulo, sub, linhas, cor) in enumerate(dados):
        x0 = 150 + i * 870
        card = Image.new("RGBA", (750, 800), (0, 0, 0, 0))
        dc = ImageDraw.Draw(card)
        dc.rounded_rectangle([0, 110, 749, 799], radius=60, fill=cor + (255,), outline=(255, 255, 255, 255), width=10)
        r = Image.open(os.path.join(UI, "retrato_%s_empolgado.png" % nome)).convert("RGBA").resize((500, 500), Image.LANCZOS)
        card.alpha_composite(r, (125, 0))
        f1 = fonte("titan_one.ttf", 78)
        f2 = fonte("fredoka_700.ttf", 40)
        f3 = fonte("fredoka_600.ttf", 32)
        w = dc.textlength(titulo, font=f1)
        dc.text(((750 - w) / 2, 470), titulo, font=f1, fill=(255, 246, 168), stroke_width=10, stroke_fill=ROXO)
        w = dc.textlength(sub, font=f2)
        dc.text(((750 - w) / 2, 565), sub, font=f2, fill=(255, 255, 255), stroke_width=6, stroke_fill=ROXO)
        for k, l in enumerate(linhas):
            w = dc.textlength(l, font=f3)
            dc.text(((750 - w) / 2, 640 + k * 46), l, font=f3, fill=(255, 255, 255), stroke_width=5, stroke_fill=ROXO)
        img.alpha_composite(card, (x0, 200))
    texto_central(img, "Mascotes originais  ·  modelados em 3D  ·  8 expressões  ·  jogam boliche de verdade", 1020, 34)
    img.convert("RGB").save(os.path.join(SAIDA, "personagens.png"))


def cenarios(pasta):
    """Os 4 cenários lado a lado, com o letreiro de cada um."""
    W, H = 1920, 1080
    img = Image.new("RGBA", (W, H), (6, 20, 48, 255))
    temas = ["parque", "espaco", "mar", "dinos"]
    cw, ch = 940, 500
    for i, t in enumerate(temas):
        c = os.path.join(pasta, "cenario_%s.png" % t)
        if not os.path.exists(c):
            continue
        r = Image.open(c).convert("RGBA")
        esc = max(cw / r.width, ch / r.height)
        r = r.resize((int(r.width * esc), int(r.height * esc)), Image.LANCZOS)
        r = r.crop(((r.width - cw) // 2, (r.height - ch) // 2, (r.width - cw) // 2 + cw, (r.height - ch) // 2 + ch))
        m = Image.new("L", (cw, ch), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, cw - 1, ch - 1], radius=36, fill=255)
        x, y = 13 + (i % 2) * (cw + 14), 13 + (i // 2) * (ch + 40) + 20
        img.paste(r, (x, y), m)
        lt = Image.open(os.path.join(UI, "cen_%s.png" % t)).convert("RGBA")
        lw = 380
        lt = lt.resize((lw, int(lw * lt.height / lt.width)), Image.LANCZOS)
        img.alpha_composite(lt, (x + 14, y + 8))
    img.convert("RGB").save(os.path.join(SAIDA, "cenarios.png"))


if __name__ == "__main__":
    vertical(sys.argv[1])
    horizontal(sys.argv[2])
    quadrado(sys.argv[1])
    personagens()
    if len(sys.argv) > 3:
        cenarios(sys.argv[3])
    print("peças em", SAIDA)
