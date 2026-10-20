extends Node

## A TELA DO JOGO — RESPONSIVA.
##
## O jogo se adapta a qualquer tela, em pé ou deitada, sem esticar:
##   * monitor em pé ligado no HDMI deitado (a máquina de boliche): a imagem
##     inteira é girada 90° (giro 1 ou -1);
##   * TV deitada, PC, celular: sem giro (giro 0), o layout se reorganiza.
##
## O lado menor da tela vale sempre 1080 unidades. Em pé, 1080 x (1920 ou
## o que a proporção der); deitada, (1920...) x 1080.
##
## Sentido do giro (Ajustes do operador ou `strike/tela/giro` no
## project.godot; variável de ambiente STRIKE_GIRO no PC):
##   1  = topo do jogo na ESQUERDA do HDMI
##  -1  = topo do jogo na DIREITA do HDMI
##   0  = sem giro
##
## Os scripts sempre usam `Tela.tamanho()` (o tamanho lógico, já em pé se
## girado) e `Tela.cobrir(no)`, nunca o tamanho da janela.

signal mudou(tamanho: Vector2)

const LADO_MENOR := 1080.0

var giro := 0
var _tamanho := Vector2(1080, 1920)
var _fisico := Vector2i(1080, 1920)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# INTERPOLAÇÃO DA FÍSICA: a física anda 120 passos por segundo; a tela,
	# 60, 75, 144... Só o que é movido PELA FÍSICA (bola, pinos, máquina de
	# pinos) liga a interpolação e aparece sempre no lugar certo do instante
	# do quadro — liso em qualquer monitor. Todo o resto (câmera, bichinhos,
	# telas), que anda a cada quadro, fica desligado.
	get_tree().root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_janela_de_teste()
	giro = _giro_configurado()
	get_tree().root.size_changed.connect(_aplicar)
	_aplicar()


## O jogo abre em TELA CHEIA (project.godot). Para testar no PC numa
## janela: godot --path . -- --janela=540x960
func _janela_de_teste() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--janela="):
			var p := a.substr(9).split("x")
			var w := get_window()
			w.mode = Window.MODE_WINDOWED
			if p.size() == 2:
				w.size = Vector2i(int(p[0]), int(p[1]))
			return


func _giro_configurado() -> int:
	if OS.has_environment("STRIKE_GIRO"):
		return clampi(int(OS.get_environment("STRIKE_GIRO")), -1, 1)
	var ajuste := _ler_ajuste_giro()
	if ajuste != 99:
		return ajuste
	if OS.get_name() != "Android":
		return 0
	return int(ProjectSettings.get_setting("strike/tela/giro", 1))


## O operador pode trocar o giro na tela de ajustes (sem gerar outro APK).
func _ler_ajuste_giro() -> int:
	var cfg := ConfigFile.new()
	if cfg.load("user://ajustes.cfg") != OK:
		return 99
	return int(cfg.get_value("tela", "giro", 99))


func definir_giro(novo: int) -> void:
	giro = clampi(novo, -1, 1)
	_aplicar()


func tamanho() -> Vector2:
	return _tamanho


func em_pe() -> bool:
	return _tamanho.y >= _tamanho.x


## Tamanho em pixels reais da imagem do jogo (já em pé, se girada).
func tamanho_fisico() -> Vector2i:
	return _fisico


func retangulo() -> Rect2:
	return Rect2(Vector2.ZERO, _tamanho)


## Faz um Control cobrir a tela do jogo inteira.
func cobrir(no: Control) -> void:
	no.set_anchors_preset(Control.PRESET_TOP_LEFT)
	no.position = Vector2.ZERO
	no.size = _tamanho


## Converte um ponto da janela (ex.: toque do mouse) para coordenadas do jogo.
func janela_para_jogo(p: Vector2) -> Vector2:
	return get_tree().root.global_canvas_transform.affine_inverse() * p


func _aplicar() -> void:
	var janela := get_tree().root
	var real := Vector2(janela.size)
	if real.x <= 0 or real.y <= 0:
		return
	var w := real.x
	var h := real.y
	if giro != 0:
		var t := w
		w = h
		h = t
	_fisico = Vector2i(int(w), int(h))
	if w <= h:
		_tamanho = Vector2(LADO_MENOR, roundf(LADO_MENOR * h / w))
	else:
		_tamanho = Vector2(roundf(LADO_MENOR * w / h), LADO_MENOR)
	janela.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	janela.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	if giro == 0:
		janela.content_scale_size = Vector2i(_tamanho)
		janela.global_canvas_transform = Transform2D.IDENTITY
	else:
		janela.content_scale_size = Vector2i(int(_tamanho.y), int(_tamanho.x))
		if giro > 0:
			# (x, y) do jogo -> (y, largura_jogo - x) na tela
			janela.global_canvas_transform = Transform2D(Vector2(0, -1), Vector2(1, 0), Vector2(0, _tamanho.x))
		else:
			# (x, y) do jogo -> (altura_jogo - y, x) na tela
			janela.global_canvas_transform = Transform2D(Vector2(0, 1), Vector2(-1, 0), Vector2(_tamanho.y, 0))
	mudou.emit(_tamanho)
