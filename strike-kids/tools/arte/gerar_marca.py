"""MARCA LAZER & SPORT — as imagens da logo usadas no jogo (ui/marca/).

A logo original (tools/arte/fonte/lazer_sport_original.png) tem 1280 px de
largura: numa TV 4K ela apareceria ampliada e borrada. Aqui ela é
redesenhada no DOBRO do tamanho sem perder a nitidez: amplia 4x (suave),
devolve cada pixel para a cor "oficial" mais próxima da logo (bordas
retas e lisas, como num desenho vetorial) e reduz 2x com filtro Lanczos
(bordas suaves, sem serrilhado). Saem:

  ui/marca/lazer_sport.png   logo inteira (alvo + placa), 2560 px
  ui/marca/alvo.png          só o alvo com o dardo (abertura animada)
  ui/marca/placa.png         só a placa "Lazer & Sport" (abertura animada)
  ui/marca/fundo.png         fundo azul da abertura (igual ao da inicialização)
  ui/marca/games.png         selo "GAMES" (LAZER & SPORT GAMES na abertura)
  texturas/bola_alvo.png     a bola da abertura com os anéis do alvo
  ui/splash.png              tela de inicialização (fundo azul + logo), em pé
  ui/splash_giro_1.png       a mesma, deitada (TV Box com monitor em pé, giro 1)
  ui/splash_giro_m1.png      idem, girada para o outro lado (giro -1)
  ui/splash_giro_0.png       TV deitada sem giro (giro 0)
  (o GERAR_APK.ps1 escolhe a certa conforme o -Giro)

Uso: python3 tools/arte/gerar_marca.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
ORIGINAL = os.path.join(RAIZ, "tools", "arte", "fonte", "lazer_sport_original.png")
PASTA = os.path.join(RAIZ, "ui", "marca")
AMPLIA = 4

# cores da logo (medidas na original)
CORES = np.array([
    (252, 252, 252),   # branco
    (42, 42, 42),      # contorno / letras
    (238, 66, 94),     # vermelho do alvo
    (180, 52, 68),     # lado escuro do alvo
    (52, 186, 234),    # azul do dardo
    (235, 52, 52),     # vermelho do texto de baixo
    (92, 92, 92),      # ponta do dardo
    (232, 232, 232),   # brilho do dardo
], dtype=np.float32)


def redesenhar(im):
    """Logo com o dobro de pixels e bordas nítidas."""
    W, H = im.size
    grande = im.convert("RGBa").resize((W * AMPLIA, H * AMPLIA), Image.BICUBIC).convert("RGBA")
    a = np.asarray(grande).astype(np.float32)
    rgb = a[..., :3]
    alfa = a[..., 3]
    # cor oficial mais próxima (por blocos, para não estourar a memória)
    plano = rgb.reshape(-1, 3)
    idx = np.empty(len(plano), dtype=np.int32)
    passo = 1 << 20
    for i in range(0, len(plano), passo):
        d = ((plano[i:i + passo, None, :] - CORES[None, :, :]) ** 2).sum(-1)
        idx[i:i + passo] = d.argmin(1)
    rgb = CORES[idx].reshape(rgb.shape)
    alfa = np.where(alfa > 127, 255.0, 0.0)
    nitida = Image.fromarray(np.dstack([rgb, alfa]).astype(np.uint8), "RGBA")
    final = nitida.convert("RGBa").resize((W * 2, H * 2), Image.LANCZOS).convert("RGBA")
    return final


def recortar(im):
    alfa = im.getchannel("A").point(lambda v: 255 if v > 24 else 0)
    return im.crop(alfa.getbbox())


def fundo(W, H, pontilhado=True):
    """Azul-marinho com um brilho atrás da logo (o mesmo na abertura)."""
    y = np.linspace(0, 1, H)[:, None]
    x = np.linspace(-1, 1, W)[None, :]
    topo = np.array([18, 58, 122], np.float32)
    base = np.array([6, 20, 48], np.float32)
    f = topo[None, None, :] * (1 - y[..., None]) + base[None, None, :] * y[..., None]
    halo = np.exp(-((x * 1.1) ** 2 + ((y - 0.46) * 2.2) ** 2) * 2.2)[..., None]
    f = f + halo * np.array([40, 110, 170], np.float32) * 0.8
    # pontilhado fininho: sem "degraus" no degradê (só no fundo da abertura,
    # que é pequeno; nas imagens de inicialização deixaria o arquivo pesado)
    if pontilhado:
        f = f + np.random.default_rng(1).uniform(-1.0, 1.0, f.shape[:2])[..., None]
    return Image.fromarray(np.clip(f, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def splash(logo):
    """Tela de inicialização: fundo azul-marinho com brilho e a logo.
    splash.png (em pé) e splash_giro_1.png (deitada, para a TV Box com o
    monitor em pé: topo do jogo à esquerda do HDMI, giro 1)."""
    W, H = 1080, 1920
    fundo(540, 960).convert("RGB").save(os.path.join(PASTA, "fundo.png"), optimize=True)
    img = fundo(W, H, False)
    lw = int(W * 0.82)
    lo = logo.resize((lw, int(lw * logo.height / logo.width)), Image.LANCZOS)
    # sombra suave embaixo da logo
    sombra = Image.new("RGBA", lo.size, (0, 8, 24, 0))
    sombra.putalpha(lo.getchannel("A").point(lambda v: int(v * 0.45)).filter(ImageFilter.GaussianBlur(14)))
    px, py = (W - lw) // 2, int(H * 0.46 - lo.height / 2)
    img.alpha_composite(sombra, (px, py + 22))
    img.alpha_composite(lo, (px, py))
    img = img.convert("RGB")
    img.save(os.path.join(RAIZ, "ui", "splash.png"), optimize=True)
    img.rotate(90, expand=True).save(os.path.join(RAIZ, "ui", "splash_giro_1.png"), optimize=True)
    img.rotate(-90, expand=True).save(os.path.join(RAIZ, "ui", "splash_giro_m1.png"), optimize=True)
    # TV deitada sem giro: a mesma arte, deitada
    deitada = fundo(1920, 1080, False)
    lw = int(1080 * 0.82)
    lo = logo.resize((lw, int(lw * logo.height / logo.width)), Image.LANCZOS)
    sombra = Image.new("RGBA", lo.size, (0, 8, 24, 0))
    sombra.putalpha(lo.getchannel("A").point(lambda v: int(v * 0.45)).filter(ImageFilter.GaussianBlur(14)))
    px, py = (1920 - lw) // 2, int(1080 * 0.48 - lo.height / 2)
    deitada.alpha_composite(sombra, (px, py + 22))
    deitada.alpha_composite(lo, (px, py))
    deitada.convert("RGB").save(os.path.join(RAIZ, "ui", "splash_giro_0.png"), optimize=True)


def games():
    """Selo "GAMES" (fita vermelha com contorno escuro, letras brancas) que
    entra embaixo da placa na abertura: LAZER & SPORT GAMES."""
    from PIL import ImageFont
    fonte = ImageFont.truetype(os.path.join(RAIZ, "fontes", "titan_one.ttf"), 250)
    texto = "GAMES"
    caixa = fonte.getbbox(texto, stroke_width=22)
    tw, th = caixa[2] - caixa[0], caixa[3] - caixa[1]
    W, H = tw + 300, th + 150
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = H // 2 - 6
    d.rounded_rectangle((6, 6, W - 7, H - 7), radius=r, fill=(42, 42, 42, 255))
    d.rounded_rectangle((26, 26, W - 27, H - 27), radius=r - 20, fill=(238, 66, 94, 255))
    # brilho em cima (verniz, como a placa do jogo)
    brilho = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    db = ImageDraw.Draw(brilho)
    db.rounded_rectangle((46, 40, W - 47, H // 2 - 4), radius=r - 40, fill=(255, 255, 255, 60))
    img.alpha_composite(brilho)
    x = (W - tw) // 2 - caixa[0]
    y = (H - th) // 2 - caixa[1] - 6
    d = ImageDraw.Draw(img)
    d.text((x, y + 10), texto, font=fonte, fill=(120, 20, 40, 255), stroke_width=22, stroke_fill=(42, 42, 42, 255))
    d.text((x, y), texto, font=fonte, fill=(255, 255, 255, 255), stroke_width=22, stroke_fill=(42, 42, 42, 255))
    img = img.resize((W // 2, H // 2), Image.LANCZOS)
    img.save(os.path.join(PASTA, "games.png"), optimize=True)
    print("games", img.size)


def bola_alvo():
    """Textura da bola da abertura: o alvo da marca (anéis vermelho e branco
    em volta do polo) — a bola de boliche com a cara da Lazer & Sport."""
    W, H = 512, 256
    y = np.arange(H)[:, None] / (H - 1)          # 0 = polo de cima
    ang = y * np.pi
    anel = np.floor(ang / (np.pi / 9.0)).astype(int) % 2
    verm = np.array([238, 66, 94], np.float32)
    bran = np.array([252, 252, 252], np.float32)
    escuro = np.array([180, 52, 68], np.float32)
    c = np.where(anel[..., None] == 0, verm, bran)
    c = np.where((y > 0.5)[..., None], escuro + (verm - escuro) * 0.4, c)
    c = np.broadcast_to(c, (H, W, 3)).copy()
    Image.fromarray(c.astype(np.uint8), "RGB").save(os.path.join(RAIZ, "texturas", "bola_alvo.png"), optimize=True)
    print("bola_alvo", (W, H))


def main():
    os.makedirs(PASTA, exist_ok=True)
    original = Image.open(ORIGINAL).convert("RGBA")
    logo = recortar(redesenhar(original))
    logo.save(os.path.join(PASTA, "lazer_sport.png"), optimize=True)
    print("logo", logo.size)
    # alvo e placa separados (a placa começa na primeira linha mais larga que o alvo)
    a = np.asarray(logo)[..., 3]
    ocupacao = (a > 20).sum(1)
    corte = int(np.argmax(ocupacao > logo.width * 0.65))
    alvo = logo.crop((0, 0, logo.width, corte - 4))   # sem a borda antisserrilhada da placa
    placa = logo.crop((0, corte, logo.width, logo.height))
    # o alvo continua "atrás" da placa: guarda a posição de cada peça na logo
    ca = alvo.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    cp = placa.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    alvo.crop(ca).save(os.path.join(PASTA, "alvo.png"), optimize=True)
    placa.crop(cp).save(os.path.join(PASTA, "placa.png"), optimize=True)
    # centros (em fração da logo inteira) para a abertura montar no lugar certo
    cx_a = (ca[0] + ca[2]) / 2 / logo.width
    cy_a = (ca[1] + ca[3]) / 2 / logo.height
    cx_p = (cp[0] + cp[2]) / 2 / logo.width
    cy_p = (corte + (cp[1] + cp[3]) / 2) / logo.height
    print("alvo", alvo.crop(ca).size, "centro %.4f %.4f" % (cx_a, cy_a))
    print("placa", placa.crop(cp).size, "centro %.4f %.4f" % (cx_p, cy_p))
    splash(logo)
    print("splash ok")
    games()
    bola_alvo()


if __name__ == "__main__":
    main()
