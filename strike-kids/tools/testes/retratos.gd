extends Node

## Gera os retratos (busto) do Bob e da Mia com fundo transparente:
## ui/retrato_bob.png, ui/retrato_mia.png (+ _empolgado) para placar, faixas e divulgação.
## godot --path . res://tools/testes/retratos.tscn

const TAM := 768

var quadro := 0
var vps := []


func _ready() -> void:
	for nome in ["bob", "mia"]:
		for expr in ["feliz", "empolgado"]:
			vps.append(_montar(nome, expr))


func _montar(nome: String, expr: String) -> Array:
	var vp := SubViewport.new()
	vp.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	vp.size = Vector2i(TAM, TAM)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.66, 0.62, 0.92)
	e.ambient_light_energy = 0.62
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 1.6
	we.environment = e
	vp.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-35, -30, 0)
	sol.light_energy = 1.05
	sol.light_color = Color(1.0, 0.95, 0.86)
	vp.add_child(sol)
	var p := Personagem.new()
	vp.add_child(p)
	p.montar(nome)
	p.posicionar(Vector3.ZERO, 0)
	p.tocar("parado", 0.01, true)
	p.expressao(expr)
	p.set_process(false)
	p._aplicar({"braco_e": Vector3(0, 0, 12), "braco_d": Vector3(-20, 0, -14), "antebraco_d": Vector3(-60, 0, 0), "cabeca": Vector3(-4, 12 if nome == "bob" else -12, 4 if nome == "bob" else -4)}, 0.0)
	var cam := Camera3D.new()
	cam.fov = 30
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.33 if nome == "bob" else -0.33, 0.93, 2.15), Vector3(0, 0.8, 0))
	return [vp, nome, expr]


func _process(_d: float) -> void:
	quadro += 1
	if quadro == 6:
		for item in vps:
			var img: Image = item[0].get_texture().get_image()
			var arq: String = "res://ui/retrato_%s.png" % item[1] if item[2] == "feliz" else "res://ui/retrato_%s_%s.png" % [item[1], item[2]]
			img.save_png(ProjectSettings.globalize_path(arq))
			print("salvo ", arq)
		get_tree().quit()
