extends SceneTree

## PRÉVIA DOS OBJETOS TEMÁTICOS (tools/modelos/temas.py)
##
## Renderiza cada objeto de res://modelos/cenario/ sozinho, com o toon e o
## contorno do jogo, enquadrado pela própria caixa, e monta uma folha em
## grade (nome, triângulos e tamanho em cada quadro).
##
## godot --path . --script res://tools/testes/previa_temas.gd -- --janela=480x480 \
##     saida.png [vista] [nome,nome,...] [colunas]
## vista: frente (padrão), lado, tras, cima, baixo
## 5º argumento opcional "sem_contorno": desliga o contorno (para depurar)
## Os objetos TINTA aparecem já coloridos (como no jogo).

const TODOS := [
	"planeta_anel", "foguete", "ovni", "planeta", "cristal", "pedra_lua", "estrela_3d",
	"coral", "coral_roxo", "alga", "concha", "estrela_mar", "peixe", "agua_viva", "bau", "tartaruga",
	"palmeira", "samambaia", "vulcao", "ovo_dino", "dino", "ptero", "pedra", "flor_gigante",
	"roda_base", "roda", "cabine", "tenda", "carrossel",
]
const TINTA := {
	"planeta": Color("#7FD8FF"), "peixe": Color("#FFB347"), "agua_viva": Color("#FF9BD2"), "cabine": Color("#FF7A6B"),
}
const DIRECOES := {
	"frente": Vector3(0.42, 0.32, 1.0), "lado": Vector3(1.0, 0.2, 0.0), "tras": Vector3(-0.42, 0.32, -1.0),
	"cima": Vector3(0.0, 1.0, 0.25), "baixo": Vector3(0.3, -0.6, 1.0),
}
## origem no centro (sem chão na prévia)
const CENTRO := ["planeta_anel", "ovni", "planeta", "estrela_3d", "peixe", "agua_viva", "ptero", "roda", "cabine"]
const CELULA := 400

var saida := "user://previa_temas.png"
var vista := "frente"
var nomes: Array = []
var colunas := 6
var com_contorno := true
var cam: Camera3D
var chao: MeshInstance3D
var rotulo: Label
var folha: Image
var atual: MeshInstance3D
var idx := -1
var quadros := 0
var toon: Shader
var contorno: Shader


func _init() -> void:
	var args := Array(OS.get_cmdline_user_args()).filter(func(x): return not str(x).begins_with("--janela="))
	if args.size() > 0:
		saida = args[0]
	if args.size() > 1:
		vista = args[1]
	nomes = TODOS.duplicate() if args.size() < 3 or args[2] == "" or args[2] == "todos" else Array(args[2].split(","))
	if args.size() > 3:
		colunas = int(args[3])
	if args.size() > 4 and args[4] == "sem_contorno":
		com_contorno = false
	colunas = mini(colunas, nomes.size())
	var linhas := int(ceil(float(nomes.size()) / colunas))
	folha = Image.create(CELULA * colunas, CELULA * linhas, false, Image.FORMAT_RGBA8)
	folha.fill(Color(0.86, 0.87, 0.9))
	toon = load("res://shaders/toon.gdshader")
	contorno = load("res://shaders/contorno.gdshader")

	var raiz := Node3D.new()
	get_root().add_child.call_deferred(raiz)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.87, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.66, 0.62, 0.92)
	e.ambient_light_energy = 0.62
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 1.6
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.12
	e.adjustment_contrast = 1.04
	we.environment = e
	raiz.add_child(we)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-52, 28, 0)
	sol.light_color = Color(1.0, 0.95, 0.86)
	sol.light_energy = 1.05
	sol.shadow_enabled = true
	sol.shadow_bias = 0.04
	sol.shadow_normal_bias = 1.2
	sol.directional_shadow_max_distance = 60.0
	raiz.add_child(sol)
	cam = Camera3D.new()
	cam.fov = 32
	cam.far = 200
	raiz.add_child(cam)
	chao = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	chao.mesh = pm
	var mc := StandardMaterial3D.new()
	mc.albedo_color = Color(0.78, 0.8, 0.76)
	chao.material_override = mc
	raiz.add_child(chao)
	atual = MeshInstance3D.new()
	raiz.add_child(atual)
	var cl := CanvasLayer.new()
	raiz.add_child(cl)
	rotulo = Label.new()
	rotulo.position = Vector2(8, 6)
	rotulo.add_theme_font_size_override("font_size", 17)
	rotulo.add_theme_color_override("font_color", Color(0.15, 0.1, 0.25))
	cl.add_child(rotulo)


func _material(nome: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = toon
	m.set_shader_parameter("borda", 0.3)
	if TINTA.has(nome):
		m.set_shader_parameter("tinta", TINTA[nome])
	if com_contorno:
		var c := ShaderMaterial.new()
		c.shader = contorno
		c.set_shader_parameter("espessura", 0.004)
		m.next_pass = c
	return m


func _mostrar(nome: String) -> void:
	var caminho := "res://modelos/cenario/%s.res" % nome
	if not ResourceLoader.exists(caminho):
		push_error("não achei " + caminho)
		atual.mesh = null
		rotulo.text = nome + " (FALTA)"
		return
	var m: Mesh = load(caminho)
	atual.mesh = m
	atual.material_override = _material(nome)
	var caixa := m.get_aabb()
	var centro := caixa.get_center()
	var raio := caixa.size.length() * 0.5
	var dir: Vector3 = DIRECOES.get(vista, DIRECOES["frente"]).normalized()
	var dist := raio / sin(deg_to_rad(cam.fov * 0.5)) * 0.9
	cam.look_at_from_position(centro + dir * dist, centro, Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD)
	cam.near = maxf(0.01, dist - raio * 2.0)
	chao.visible = not CENTRO.has(nome) and vista != "baixo"
	var tris := 0
	for s in m.get_surface_count():
		tris += m.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	rotulo.text = "%s  %d tri\n%.2f x %.2f x %.2f m" % [nome, tris, caixa.size.x, caixa.size.y, caixa.size.z]


func _process(_d: float) -> bool:
	if idx < 0:
		idx = 0
		_mostrar(nomes[0])
		quadros = 0
		return false
	quadros += 1
	if quadros < 5:
		return false
	var img := get_root().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != CELULA or img.get_height() != CELULA:
		img.resize(CELULA, CELULA, Image.INTERPOLATE_LANCZOS)
	folha.blit_rect(img, Rect2i(0, 0, CELULA, CELULA), Vector2i((idx % colunas) * CELULA, (idx / colunas) * CELULA))
	idx += 1
	if idx >= nomes.size():
		folha.save_png(saida)
		print("salvo ", saida)
		return true
	_mostrar(nomes[idx])
	quadros = 0
	return false
