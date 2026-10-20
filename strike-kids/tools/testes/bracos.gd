extends Node

## BRAÇOS DE PERTO: um bichinho grande, de frente e de três-quartos, em
## vários instantes de cada clipe (para achar braço quebrado, cotovelo
## aberto, mão entrando no corpo...).
##   godot --path . --fixed-fps 30 res://tools/testes/bracos.tscn -- --janela=1200x900 saida.png bob pronto,acenar 0.3,0.8,1.3
## Com roupinha de fase: bob:pirata, mia:dino, bob:astronauta, mia:parque...
## --perto: a cabeça de perto (rosto, chapéu, capuz). --costas: de costas
## (como na hora do arremesso).

const LARG := 340
const ALT := 430
var saida := "user://bracos.png"
var quem := "bob"
var roupa := ""
var clipes: Array = ["pronto"]
var tempos: Array = [0.3, 0.8, 1.3]
var bicho: Personagem
var cf: Camera3D
var cl: Camera3D
var vp_frente: SubViewport
var vp_lado: SubViewport
var fotos: Array[Image] = []
var _i := 0          # clipe atual
var _n := 0          # instante atual
var _t := 0.0


func _ready() -> void:
	var a := Array(OS.get_cmdline_user_args()).filter(func(x): return not str(x).begins_with("--"))
	if a.size() > 0:
		saida = a[0]
	if a.size() > 1:
		quem = a[1]
		if ":" in quem:
			roupa = quem.get_slice(":", 1)
			quem = quem.get_slice(":", 0)
	if a.size() > 2:
		clipes = Array(a[2].split(","))
	if a.size() > 3:
		tempos = Array(a[3].split(",")).map(func(x): return float(x))
	var mundo := World3D.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.8, 1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.66, 0.62, 0.92)
	e.ambient_light_energy = 0.62
	mundo.environment = e
	var raiz := Node3D.new()
	vp_frente = _vp(mundo)
	vp_lado = _vp(mundo)
	vp_frente.add_child(raiz)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-52, 28, 0)
	sol.light_energy = 1.05
	raiz.add_child(sol)
	bicho = Personagem.new()
	raiz.add_child(bicho)
	bicho.montar(quem)
	bicho.trocar_roupa(roupa)
	bicho.posicionar(Vector3.ZERO, 0)
	cf = Camera3D.new()
	cf.fov = 30
	vp_frente.add_child(cf)
	cl = Camera3D.new()
	cl.fov = 30
	vp_lado.add_child(cl)
	cf.current = true
	cl.current = true
	_seguir()
	_comecar()


func _vp(mundo: World3D) -> SubViewport:
	var v := SubViewport.new()
	v.size = Vector2i(LARG, ALT)
	v.world_3d = mundo
	v.msaa_3d = Viewport.MSAA_4X
	v.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(v)
	return v


func _comecar() -> void:
	_t = 0.0
	_n = 0
	bicho.tocar(str(clipes[_i]), 0.01, true)


## As câmeras acompanham o bichinho (corrida do arremesso, pulos).
func _seguir() -> void:
	var c := bicho.global_position
	if OS.get_cmdline_user_args().has("--perto"):
		cf.look_at_from_position(c + Vector3(0, 1.0, 1.25), c + Vector3(0, 0.9, 0))
		cl.look_at_from_position(c + Vector3(0.95, 1.05, 0.8), c + Vector3(0, 0.9, 0))
		return
	var z := -1.0 if OS.get_cmdline_user_args().has("--costas") else 1.0
	cf.look_at_from_position(c + Vector3(0, 0.95, 2.6 * z), c + Vector3(0, 0.62, 0))
	cl.look_at_from_position(c + Vector3(2.0, 1.0, 1.7 * z), c + Vector3(0, 0.62, 0))


func _process(delta: float) -> void:
	if _i >= clipes.size():
		return
	_seguir()
	_t += delta
	if _n < tempos.size() and _t >= float(tempos[_n]):
		_n += 1
		await RenderingServer.frame_post_draw
		var f := vp_frente.get_texture().get_image()
		var l := vp_lado.get_texture().get_image()
		f.convert(Image.FORMAT_RGBA8)
		l.convert(Image.FORMAT_RGBA8)
		var par := Image.create(LARG * 2, ALT, false, Image.FORMAT_RGBA8)
		par.blit_rect(f, Rect2i(0, 0, LARG, ALT), Vector2i(0, 0))
		par.blit_rect(l, Rect2i(0, 0, LARG, ALT), Vector2i(LARG, 0))
		fotos.append(par)
		if _n >= tempos.size():
			_i += 1
			if _i < clipes.size():
				_comecar()
			else:
				_salvar()


func _salvar() -> void:
	var colunas := tempos.size()
	var linhas := clipes.size()
	var folha := Image.create(LARG * 2 * colunas, ALT * linhas, false, Image.FORMAT_RGBA8)
	for k in fotos.size():
		folha.blit_rect(fotos[k], Rect2i(0, 0, LARG * 2, ALT), Vector2i((k % colunas) * LARG * 2, (k / colunas) * ALT))
	folha.save_png(saida)
	print("salvo ", saida)
	get_tree().quit()
