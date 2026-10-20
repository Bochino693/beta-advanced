extends Node

## BANCO DE TESTE DAS ANIMAÇÕES (pés no chão, joelhos, pulos).
##   godot --path . --fixed-fps 30 res://tools/testes/anim_teste.tscn -- --janela=1600x900 saida.png danca 0.2,0.6,1.0 [lado|frente]
## Bob e Mia tocam o clipe; tira fotos nos instantes pedidos e monta uma
## folha (uma coluna por instante).

var saida := "user://anim.png"
var clipe := "danca"
var tempos: Array = [0.2, 0.6, 1.0]
var vista := "lado"
var bob: Personagem
var mia: Personagem
var t := 0.0
var n := 0
var fotos: Array[Image] = []


func _ready() -> void:
	var a := Array(OS.get_cmdline_user_args()).filter(func(x): return not str(x).begins_with("--janela="))
	if a.size() > 0:
		saida = a[0]
	if a.size() > 1:
		clipe = a[1]
	if a.size() > 2:
		tempos = Array(a[2].split(",")).map(func(x): return float(x))
	if a.size() > 3:
		vista = a[3]
	var raiz := Node3D.new()
	add_child(raiz)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.8, 1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.66, 0.62, 0.92)
	e.ambient_light_energy = 0.62
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 1.6
	we.environment = e
	raiz.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-52, 28, 0)
	sol.light_energy = 1.05
	sol.light_color = Color(1.0, 0.95, 0.86)
	sol.shadow_enabled = true
	raiz.add_child(sol)
	var chao := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	chao.mesh = pm
	var mc := StandardMaterial3D.new()
	mc.albedo_color = Color(0.93, 0.84, 0.72)
	chao.material_override = mc
	raiz.add_child(chao)
	# grade no chão (para ver se o pé escorrega)
	for i in range(-6, 7):
		for eixo in 2:
			var l := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.006, 0.002, 3.0) if eixo == 0 else Vector3(3.0, 0.002, 0.006)
			l.mesh = b
			l.position = Vector3(i * 0.1, 0.001, 0) if eixo == 0 else Vector3(0, 0.001, i * 0.1)
			var ml := StandardMaterial3D.new()
			ml.albedo_color = Color(0.6, 0.5, 0.45)
			l.material_override = ml
			raiz.add_child(l)
	bob = Personagem.new()
	raiz.add_child(bob)
	bob.montar("bob")
	mia = Personagem.new()
	raiz.add_child(mia)
	mia.montar("mia")
	if vista == "frente":
		bob.posicionar(Vector3(-0.45, 0, 0), 0)
		mia.posicionar(Vector3(0.45, 0, 0), 0)
	else:
		bob.posicionar(Vector3(0, 0, 0.55), 0)
		mia.posicionar(Vector3(0, 0, -0.55), 0)
	bob.tocar(clipe, 0.01, true)
	mia.tocar(clipe, 0.01, true)
	var cam := Camera3D.new()
	cam.fov = 30
	raiz.add_child(cam)
	if vista == "frente":
		cam.look_at_from_position(Vector3(0, 0.75, 3.6), Vector3(0, 0.5, 0))
	else:
		cam.fov = 34
		cam.look_at_from_position(Vector3(4.6, 0.8, 0.0), Vector3(0, 0.62, 0))
	cam.current = true


func _process(delta: float) -> void:
	t += delta
	if n < tempos.size() and t >= float(tempos[n]):
		n += 1
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		fotos.append(img)
		if n >= tempos.size():
			var w := fotos[0].get_width()
			var h := fotos[0].get_height()
			var folha := Image.create(w * fotos.size(), h, false, Image.FORMAT_RGBA8)
			for i in fotos.size():
				folha.blit_rect(fotos[i], Rect2i(0, 0, w, h), Vector2i(i * w, 0))
			folha.save_png(saida)
			print("salvo ", saida)
			get_tree().quit()
