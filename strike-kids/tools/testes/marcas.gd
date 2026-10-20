extends Node

## O SÍMBOLO DA LAZER & SPORT EM CADA CENÁRIO: cada cenário visto da
## espera (a pista de frente), da máquina de pinos e de pertinho do símbolo.
##   godot --path . res://tools/testes/marcas.tscn -- --janela=540x960 saida.png

const VISTAS := [
	[Vector3(0.0, 1.05, 2.2), Vector3(0.0, 0.18, -9.9), 34.0],      # a pista de frente (espera)
	[Vector3(-0.35, 0.72, -8.3), Vector3(0, 0.5, -10.95), 40.0],    # máquina de pinos
	[Vector3(-0.9, 2.6, -3.9), Vector3(-1.75, 2.45, -7.5), 40.0],   # de pertinho
]

var mundo: Mundo
var cam: Camera3D
var saida := "user://marcas.png"
var fotos: Array[Image] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if not str(a).begins_with("--"):
			saida = a
	var vp := SubViewport.new()
	vp.size = Vector2i(540, 960)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	mundo = Mundo.new()
	vp.add_child(mundo)
	mundo.construir()
	mundo.aplicar_qualidade("media")
	cam = Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	_rodar(vp)


func _rodar(vp: SubViewport) -> void:
	for tema in Temas.ORDEM:
		mundo.aplicar_tema(tema)
		for v in VISTAS:
			cam.fov = v[2]
			cam.look_at_from_position(v[0], v[1])
			for i in 8:
				await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			fotos.append(img)
	var w := 540
	var h := 960
	var folha := Image.create(w * VISTAS.size() * 2, h * 2, false, Image.FORMAT_RGBA8)
	for k in fotos.size():
		var col := k % (VISTAS.size() * 2)
		var lin := k / (VISTAS.size() * 2)
		folha.blit_rect(fotos[k], Rect2i(0, 0, w, h), Vector2i(col * w, lin * h))
	folha.save_png(saida)
	print("salvo ", saida)
	get_tree().quit()
