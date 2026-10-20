extends Node

## Renderiza o mundo de alguns pontos de vista (conferência visual).
## godot --path . res://tools/testes/ver_mundo.tscn -- pasta_saida

var cam: Camera3D
var quadros := 0
var vistas := []
var idx := 0
var saida := "/tmp"
var mundo

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		saida = a[0]
	mundo = load("res://scripts/mundo.gd").new()
	add_child(mundo)
	cam = Camera3D.new()
	add_child(cam)
	vistas = [
		[Vector3(0, 1.7, 6.0), Vector3(0, 0.3, -8), 60.0],
		[Vector3(0.9, 0.5, -11.6), Vector3(-0.1, 0.25, -14.6), 50.0],
		[Vector3(5, 3.5, 4), Vector3(0, 0.0, -6), 55.0],
	]

func _process(_d: float) -> void:
	quadros += 1
	if quadros == 2:
		mundo.construir()
		mundo.acender_pista(true)
		mundo.bola_z = 6.0
	if quadros > 3 and idx < vistas.size():
		var v = vistas[idx]
		cam.fov = v[2]
		cam.look_at_from_position(v[0], v[1])
		cam.current = true
		if quadros % 6 == 0:
			get_viewport().get_texture().get_image().save_png("%s/mundo_%d.png" % [saida, idx])
			idx += 1
	if idx >= vistas.size():
		get_tree().quit()
