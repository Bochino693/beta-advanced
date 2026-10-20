extends Node

## BANCO DE TESTE DAS REAÇÕES DOS PINOS: derruba alguns (empurrão), espera
## assentar, chama Pinos.reagir() e monta uma folha com 4 instantes.
##   godot --path . --fixed-fps 30 res://tools/testes/pinos_reacao.tscn -- --janela=800x800 saida.png

var saida := "user://pinos_reacao.png"
var pinos: Pinos
var t := 0.0
var fase := 0
var fotos: Array[Image] = []
const INSTANTES := [0.25, 0.45, 0.7, 1.6]
var _t_reacao := 0.0
var _n := 0


func _ready() -> void:
	var a := Array(OS.get_cmdline_user_args()).filter(func(x): return not str(x).begins_with("--janela="))
	if a.size() > 0:
		saida = a[0]
	seed(7)
	var mundo := Mundo.new()
	add_child(mundo)
	mundo.construir()
	mundo.aplicar_qualidade("alta")
	pinos = Pinos.new()
	add_child(pinos)
	pinos.montar()
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40
	cam.look_at_from_position(Vector3(0.45, 0.7, Mundo.Z_PINO1 + 2.3), Vector3(0, 0.3, Mundo.Z_PINO1 - 0.5))
	cam.current = true
	pinos.soltar_todos()
	for n in [1, 2, 4, 7]:
		pinos.pino(n).apply_impulse(Vector3(randf_range(-0.6, 0.6), 0.2, -2.2), Vector3(0, 0.3, 0))


func _process(delta: float) -> void:
	t += delta
	if fase == 0 and t > 3.0:
		fase = 1
		pinos.reagir()
		_t_reacao = t
	if fase == 1 and _n < INSTANTES.size() and t - _t_reacao >= INSTANTES[_n]:
		_n += 1
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		fotos.append(img)
		if fotos.size() == INSTANTES.size():
			var w := fotos[0].get_width()
			var h := fotos[0].get_height()
			var folha := Image.create(w * 2, h * 2, false, Image.FORMAT_RGBA8)
			for i in fotos.size():
				folha.blit_rect(fotos[i], Rect2i(0, 0, w, h), Vector2i((i % 2) * w, (i / 2) * h))
			folha.save_png(saida)
			print("salvo ", saida)
			get_tree().quit()
