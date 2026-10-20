extends SceneTree

## Prévia rápida dos modelos (renderiza e salva uma imagem).
## godot --path . --script res://tools/testes/previa.gd -- saida.png

var quadros := 0
var saida := "user://previa.png"
var celula := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		saida = args[0]
	if args.size() > 1:
		celula = int(args[1])
	var raiz := Node3D.new()
	get_root().add_child.call_deferred(raiz)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.78, 1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.58, 0.9)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	raiz.add_child(env)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-50, 35, 0)
	sol.light_energy = 0.95
	sol.light_color = Color(1.0, 0.96, 0.9)
	sol.shadow_enabled = true
	raiz.add_child(sol)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.8, 3.0)
	cam.fov = 40
	raiz.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 0.62, 0))
	var toon := load("res://shaders/toon_personagem.gdshader")
	var cont := load("res://shaders/contorno.gdshader")
	var chao := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	chao.mesh = pm
	var mc := StandardMaterial3D.new()
	mc.albedo_color = Color(0.45, 0.8, 0.4)
	chao.material_override = mc
	raiz.add_child(chao)
	var x := -0.65
	for nome in ["bob", "mia"]:
		if not ResourceLoader.exists("res://modelos/%s.scn" % nome):
			continue
		var p: Node3D = load("res://modelos/%s.scn" % nome).instantiate()
		p.position = Vector3(x, 0, 0)
		p.rotation_degrees.y = -12 if x < 0 else 12
		raiz.add_child(p)
		var rosto_tex = load("res://texturas/rosto_%s.png" % nome)
		for mi in p.find_children("*", "MeshInstance3D", true, false):
			var m := ShaderMaterial.new()
			m.shader = toon
			if mi.get_parent().name == "cabeca":
				m.set_shader_parameter("usa_rosto", true)
				m.set_shader_parameter("rosto", rosto_tex)
				var meta: Dictionary = p.get_meta("rosto", {})
				if meta.has("centro"):
					m.set_shader_parameter("rosto_centro", Vector2(meta["centro"][0], meta["centro"][1]))
					m.set_shader_parameter("rosto_tamanho", Vector2(meta["tamanho"][0], meta["tamanho"][1]))
				m.set_shader_parameter("rosto_celula", Vector2(celula % 4, celula / 4))
			var c := ShaderMaterial.new()
			c.shader = cont
			m.next_pass = c
			mi.material_override = m
		x += 1.3
	if ResourceLoader.exists("res://modelos/pino.res"):
		for i in 3:
			var pino := MeshInstance3D.new()
			pino.mesh = load("res://modelos/pino.res")
			pino.position = Vector3(-0.3 + i * 0.3, 0, -0.6)
			var m := ShaderMaterial.new()
			m.shader = toon
			m.set_shader_parameter("usa_rosto", true)
			m.set_shader_parameter("rosto", load("res://texturas/rosto_pino.png"))
			m.set_shader_parameter("rosto_centro", Vector2(0, 0.215))
			m.set_shader_parameter("rosto_tamanho", Vector2(0.15, 0.13))
			m.set_shader_parameter("rosto_celula", Vector2(i, 0))
			var c := ShaderMaterial.new()
			c.shader = cont
			m.next_pass = c
			pino.material_override = m
			raiz.add_child(pino)

func _process(_d: float) -> bool:
	quadros += 1
	if quadros == 8:
		var img := get_root().get_texture().get_image()
		img.save_png(saida)
		print("salvo ", saida)
		return true
	return false
