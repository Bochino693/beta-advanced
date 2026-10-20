extends Control

## Amostra dos TEXTOS do jogo (as duas fontes, vários tamanhos, contorno e
## sombra) e quanto custa desenhar cada um pela primeira vez:
##   godot --path . res://tools/testes/textos.tscn -- --janela=1080x1920 saida.png

const AMOSTRAS := [
	["VEZ DO BOB!", 76, 16, true],
	["RODADA 2", 44, 10, false],
	["7 PINOS!", 64, 14, true],
	["CRÉDITOS: 3   ·   MODO LIVRE", 34, 8, false],
	["RECORDE: 210 PONTOS (MIA)", 40, 9, false],
	["ROLE A BOLA PARA ESCOLHER SEU AMIGO", 34, 9, false],
	["QUANTOS VÃO JOGAR?", 70, 14, true],
	["AINDA ESTÁ AÍ? Role a bola para continuar!", 52, 12, false],
	["▶ Rodadas por jogador:   3", 34, 6, false],
	["SORRIA!", 110, 24, true],
	["SELVA DOS DINOS", 90, 18, true],
	["Classificação de hoje — 1º 2º 3º", 38, 8, false],
	["ÁÉÍÓÚ ÂÊÔ ÃÕ Ç àéíóú ãõ ç 0123456789", 46, 10, false],
]


func _ready() -> void:
	var saida := ""
	for a in OS.get_cmdline_user_args():
		if not str(a).begins_with("--"):
			saida = a
	var fundo := ColorRect.new()
	fundo.color = Color("#2E86DE")
	fundo.size = Vector2(1080, 1920)
	add_child(fundo)
	var hud := Hud.new()
	hud.fonte = load("res://fontes/fredoka_700.ttf")
	hud.fonte_titulo = load("res://fontes/titan_one.ttf")
	var y := 40.0
	for am in AMOSTRAS:
		var l: Label = hud.rotulo(am[0], am[1], Color.WHITE if not am[3] else Color("#FFF6A8"), am[2], Hud.MARINHO, hud.fonte_titulo if am[3] else null)
		l.position = Vector2(20, y)
		l.size = Vector2(1040, am[1] * 1.5)
		add_child(l)
		y += am[1] * 1.45
	await RenderingServer.frame_post_draw
	var t0 := Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	print("segundo quadro: %.1f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0))
	if saida != "":
		get_viewport().get_texture().get_image().save_png(saida)
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW:
		pass
