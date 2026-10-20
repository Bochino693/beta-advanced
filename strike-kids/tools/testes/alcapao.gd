extends Node

## ALÇAPÃO DO FOSSO (conferir de olho): derruba os pinos, roda a máquina
## (rack novo) e fotografa da câmera da máquina a varrida, o alçapão
## abrindo, os pinos caindo no poço e as portinhas fechando.
##   godot --path . --fixed-fps 30 res://tools/testes/alcapao.tscn -- --janela=540x960 --saida=pasta [--tema=espaco]

var saida := "user://alcapao"
var tema := "parque"
var mundo: Mundo
var pinos: Pinos
var maquina: Maquina
var cam: CameraCine
var _t := 0.0
var _fotos := 0
var _fase := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--saida="):
			saida = a.substr(8)
		elif a.begins_with("--tema="):
			tema = a.substr(7)
	DirAccess.make_dir_recursive_absolute(saida)
	mundo = Mundo.new()
	add_child(mundo)
	mundo.construir()
	mundo.aplicar_qualidade("alta")
	mundo.aplicar_tema(tema)
	pinos = Pinos.new()
	add_child(pinos)
	pinos.montar()
	maquina = Maquina.new()
	add_child(maquina)
	maquina.montar(pinos)
	maquina.instantaneo()
	# como no jogo (principal.gd, _alcapao_maquina): corta para o fosso
	maquina.alcapao.connect(func(abrindo: bool):
		if Array(OS.get_cmdline_user_args()).any(func(x): return str(x).begins_with("--cam=")):
			return
		if abrindo:
			cam.corte(Vector3(0.98, 1.08, Mundo.ALCAPAO_Z0 - 0.15), Vector3(-0.12, -0.45, Mundo.ALCAPAO_Z1 + 0.75), 56, 56)
			cam.ir(Vector3(0.9, 1.0, Mundo.ALCAPAO_Z0 - 0.25), Vector3(-0.1, -0.55, Mundo.ALCAPAO_Z1 + 0.8), 56, 56, 1.0)
		else:
			cam.corte(Vector3(-0.35, 0.72, Mundo.Z_PINO1 + 2.2), Vector3(0, 0.5, Mundo.Z_PINO1 - 0.45), 40, 40))
	cam = CameraCine.new()
	add_child(cam)
	cam.current = true
	# a câmera da máquina do jogo (principal.gd, _plano_maquina) ou --cam=px,py,pz:ax,ay,az:fov
	cam.corte(Vector3(-0.35, 0.72, Mundo.Z_PINO1 + 2.2), Vector3(0, 0.5, Mundo.Z_PINO1 - 0.45), 40, 40)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):
			var c := a.substr(6).split(":")
			var v := func(t: String) -> Vector3:
				var k := t.split(",")
				return Vector3(float(k[0]), float(k[1]), float(k[2]))
			cam.corte(v.call(c[0]), v.call(c[1]), float(c[2]), float(c[2]))
	# derruba todos: cada pino ganha um empurrão para trás e para o lado
	pinos.soltar_todos()
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 7
	for p in pinos.pinos:
		(p as RigidBody3D).apply_central_impulse(Vector3(rnd.randf_range(-0.25, 0.25), 0.15, rnd.randf_range(-0.55, -0.2)) * (p as RigidBody3D).mass)


func _physics_process(delta: float) -> void:
	_t += delta
	if _fase == 1 and OS.get_cmdline_user_args().has("--depurar") and int(_t * 30) % 3 == 0:
		var pd: AnimatableBody3D = maquina.portas[1]
		print("  t=%.2f rot=%.3f grot=%.3f pos=%s barra_z=%.2f" % [_t, pd.rotation.z, pd.global_rotation.z, pd.position, maquina.barra.position.z])
	if _fase == 0 and _t > 2.0:
		_fase = 1
		_t = 0.0
		print("pinos caidos: ", 10 - pinos.em_pe().size(), "  no fosso: ", pinos.pinos.filter(func(p): return p.global_position.z < Mundo.Z_FIM_DECK).size())
		maquina.rack_novo()


func _process(_d: float) -> void:
	if _fase != 1:
		return
	# uma foto a cada ~0,2 s de máquina
	if _t >= _fotos * 0.12 and _fotos < 36:
		_fotos += 1
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%02d.png" % [saida, _fotos])
		var abertas := maquina.portas.map(func(p): return snappedf(p.rotation.z, 0.01))
		print("foto %d  t=%.2f  portas=%s  pinos visiveis=%d" % [_fotos, _t, abertas, pinos.pinos.filter(func(p): return p.visible).size()])
	if not maquina.trabalhando and _t > 1.0:
		print("ALCAPAO OK  portas fechadas=", maquina.portas.all(func(p): return absf(p.rotation.z) < 0.001))
		get_tree().quit()
