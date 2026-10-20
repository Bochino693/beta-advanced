class_name Bola
extends RigidBody3D

## A BOLA: corpo físico (Jolt), textura do personagem (patinhas do Bob,
## estrelas da Mia), rastro de arco-íris no chão e brilhinhos. Com 2 ou
## mais strikes seguidos ela vira BOLA DE FOGO (rastro e chamas).

signal bateu(corpo: Node, velocidade: float)
## entrou na caçapa das bolas (no fundo do fosso)
signal recolhida

const RAIO := 0.14
const MASSA := 6.5
const FOGO := [Color("#FFF3B0"), Color("#FFD43B"), Color("#FF9F2E"), Color("#FF5A1E"), Color("#E0301E")]

var malha: MeshInstance3D
var _sombra: MeshInstance3D
var _rastro: MeshInstance3D
var _im: ImmediateMesh
var _pontos: Array[Vector3] = []
var _brilhos: CPUParticles3D
var _chamas: CPUParticles3D
var _fogo := false
var _grad_arco: Gradient
var _grad_fogo: Gradient
var curva := 0.0              # força lateral (efeito "gancho")
var rolando := false
## no replay a bola só é "posta" nos lugares gravados (sem física)
var em_replay := false
var _mat: ShaderMaterial


static func material(nome: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Materiais.shader("res://shaders/bola.gdshader")
	m.set_shader_parameter("textura", Materiais.textura("bola_" + nome))
	var c := ShaderMaterial.new()
	c.shader = Materiais.shader(Materiais.CONTORNO)
	c.set_shader_parameter("espessura", 0.0025)
	c.set_shader_parameter("usa_cor_vertice", 0.0)
	m.next_pass = c
	return m


func _init() -> void:
	mass = MASSA
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	can_sleep = false
	collision_layer = Mundo.CAMADA_BOLA
	collision_mask = Mundo.CAMADA_MUNDO | Mundo.CAMADA_PINOS | Mundo.CAMADA_PISO_BOLA
	var pm := PhysicsMaterial.new()
	pm.friction = 0.12
	pm.bounce = 0.12
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = RAIO
	cs.shape = sh
	add_child(cs)
	malha = MeshInstance3D.new()
	var esfera := SphereMesh.new()
	esfera.radius = RAIO
	esfera.height = RAIO * 2
	esfera.radial_segments = 32
	esfera.rings = 16
	malha.mesh = esfera
	add_child(malha)
	_sombra = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.42, 0.42)
	q.orientation = PlaneMesh.FACE_Y
	_sombra.mesh = q
	_sombra.material_override = Materiais.sombra_blob(0.6)
	_sombra.top_level = true
	add_child(_sombra)
	_im = ImmediateMesh.new()
	_rastro = MeshInstance3D.new()
	_rastro.mesh = _im
	_rastro.top_level = true
	var mr := StandardMaterial3D.new()
	mr.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mr.vertex_color_use_as_albedo = true
	mr.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mr.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mr.cull_mode = BaseMaterial3D.CULL_DISABLED
	mr.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_rastro.material_override = mr
	_rastro.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rastro)
	_brilhos = CPUParticles3D.new()
	_brilhos.amount = 40
	_brilhos.lifetime = 0.7
	_brilhos.emitting = false
	_brilhos.local_coords = false
	_brilhos.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_brilhos.emission_sphere_radius = RAIO
	_brilhos.direction = Vector3(0, 1, 0)
	_brilhos.spread = 70.0
	_brilhos.initial_velocity_min = 0.3
	_brilhos.initial_velocity_max = 0.9
	_brilhos.gravity = Vector3(0, -0.6, 0)
	_brilhos.scale_amount_min = 0.5
	_brilhos.scale_amount_max = 1.0
	var curva_esc := Curve.new()
	curva_esc.add_point(Vector2(0, 1))
	curva_esc.add_point(Vector2(1, 0))
	_brilhos.scale_amount_curve = curva_esc
	_brilhos.color_initial_ramp = _arco_iris()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.09)
	qm.material = Materiais.particula("faisca")
	_brilhos.mesh = qm
	_brilhos.top_level = false
	add_child(_brilhos)
	_chamas = CPUParticles3D.new()
	_chamas.amount = 46
	_chamas.lifetime = 0.45
	_chamas.emitting = false
	_chamas.local_coords = false
	_chamas.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_chamas.emission_sphere_radius = RAIO * 0.8
	_chamas.direction = Vector3(0, 1, 0)
	_chamas.spread = 25.0
	_chamas.initial_velocity_min = 0.6
	_chamas.initial_velocity_max = 1.4
	_chamas.gravity = Vector3(0, 1.5, 0)
	_chamas.scale_amount_min = 0.7
	_chamas.scale_amount_max = 1.3
	var ce := Curve.new()
	ce.add_point(Vector2(0, 0.6))
	ce.add_point(Vector2(0.3, 1.0))
	ce.add_point(Vector2(1, 0.0))
	_chamas.scale_amount_curve = ce
	var gc := Gradient.new()
	gc.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gc.colors = PackedColorArray([Color(1.0, 0.95, 0.6, 1.0), Color(1.0, 0.55, 0.12, 0.9), Color(0.9, 0.15, 0.05, 0.0)])
	_chamas.color_ramp = gc
	var qc := QuadMesh.new()
	qc.size = Vector2(0.2, 0.2)
	qc.material = Materiais.particula("fumaca", true)
	_chamas.mesh = qc
	add_child(_chamas)
	_grad_arco = _arco_iris()
	_grad_fogo = Gradient.new()
	_grad_fogo.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	_grad_fogo.colors = PackedColorArray(FOGO)
	body_entered.connect(_ao_bater)
	# a bola anda pela física: aparece interpolada entre os passos (lisa em
	# qualquer monitor); sombra, rastro e brilhos são postos a cada quadro
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	for n in [_sombra, _rastro, _brilhos, _chamas]:
		(n as Node).physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _ready() -> void:
	get_global_transform_interpolated()


static func _arco_iris() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color("#FF4B5C"))
	g.set_color(1, Color("#2E7BFF"))
	g.add_point(0.2, Color("#FF9F2E"))
	g.add_point(0.4, Color("#FFE14D"))
	g.add_point(0.6, Color("#5ED16A"))
	g.add_point(0.8, Color("#4FC3F7"))
	return g


func vestir(nome: String) -> void:
	_mat = material(nome)
	malha.material_override = _mat


func lancar(origem: Vector3, velocidade: Vector3, efeito := 0.0) -> void:
	freeze = false
	visible = true
	global_position = origem
	rotation = Vector3.ZERO
	linear_velocity = velocidade
	angular_velocity = Vector3.UP.cross(velocidade) / RAIO
	curva = efeito
	rolando = true
	em_replay = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	reset_physics_interpolation()
	_pontos.clear()
	replay_ritmo(1.0)
	_brilhos.emitting = true
	_chamas.emitting = _fogo


func guardar() -> void:
	rolando = false
	em_replay = false
	freeze = true
	visible = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_position = Vector3(0, -5, 20)
	reset_physics_interpolation()
	_pontos.clear()
	_im.clear_surfaces()
	_brilhos.emitting = false
	_chamas.emitting = false


## Bola de fogo (sequência de strikes): rastro de fogo e chamas.
func fogo(ligar: bool) -> void:
	_fogo = ligar
	_brilhos.color_initial_ramp = _grad_fogo if ligar else _grad_arco
	if not ligar:
		_chamas.emitting = false


func _physics_process(_delta: float) -> void:
	if not rolando:
		return
	var p := global_position
	if curva != 0.0 and p.z > Mundo.Z_PINO1 + 1.4 and p.y > -0.02:
		apply_central_force(Vector3(curva * mass, 0, 0))
	# no fosso: o chão "puxa" a bola para a caçapa (como a esteira de verdade)
	if p.z < Mundo.Z_FIM_DECK and p.y < 0.0 and linear_velocity.z > -1.6:
		apply_central_force(Vector3(-p.x * 3.0, 0, -4.0) * mass)
	# entrou no túnel da caçapa: some (e volta no retorno de bolas)
	if p.z < Mundo.Z_FUNDO - 0.35:
		rolando = false
		_brilhos.emitting = false
		_chamas.emitting = false
		visible = false
		set_deferred("freeze", true)
		recolhida.emit()


func _process(_delta: float) -> void:
	if not visible:
		return
	# onde a bola APARECE neste quadro (entre dois passos da física)
	var g := Mundo.na_tela(self).origin
	_sombra.global_position = Vector3(g.x, max(g.y - RAIO, -0.3) + 0.008, g.z)
	_sombra.global_rotation = Vector3.ZERO
	var alt: float = clamp(1.0 - (g.y - RAIO) * 1.5, 0.3, 1.0)
	# a sombra é um adesivo reto: só no chão reto (pista, área de quem joga,
	# fundo do fosso). Indo para a canaleta ela some — dentro da calha
	# curva ela atravessaria a parede.
	if g.z > Mundo.Z_FIM_DECK and g.z < 0.12:
		alt *= clampf((Mundo.MEIA_LARGURA - absf(g.x)) / 0.2, 0.0, 1.0)
	_sombra.scale = Vector3(maxf(alt, 0.001), 1, maxf(alt, 0.001))
	if rolando:
		marcar_rastro(g)
	if (rolando or em_replay) and g.z < Mundo.Z_PINO1 + 0.4:
		_brilhos.emitting = false
		_chamas.emitting = false
	_desenhar_rastro()


## Mais um ponto do rastro de arco-íris (o replay chama nos mesmos
## instantes da jogada de verdade).
func marcar_rastro(p: Vector3) -> void:
	# o rastro é desenhado NA PISTA: saindo dela (canaleta, fosso) ele só
	# vai sumindo — nunca atravessa a calha nem as paredes
	if absf(p.x) > Mundo.MEIA_LARGURA - 0.03 or p.y - RAIO < -0.03 or p.z < Mundo.Z_FIM_DECK:
		if not _pontos.is_empty():
			_pontos.pop_back()
		return
	_pontos.push_front(Vector3(p.x, maxf(p.y - RAIO, 0.0) + 0.012, p.z))
	if _pontos.size() > 28:
		_pontos.pop_back()


## REPLAY: rastro recomeça e os brilhinhos voltam (em câmera lenta).
func replay(ligar: bool) -> void:
	em_replay = ligar
	# no replay quem move a bola é o jogo, quadro a quadro (sem interpolar)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF if ligar else Node.PHYSICS_INTERPOLATION_MODE_ON
	if not ligar:
		reset_physics_interpolation()
	_pontos.clear()
	_im.clear_surfaces()
	_brilhos.emitting = ligar
	_chamas.emitting = ligar and _fogo
	replay_ritmo(1.0)


## Os brilhinhos andam no ritmo do replay (0,45 = 45% da velocidade).
func replay_ritmo(vel: float) -> void:
	_brilhos.speed_scale = vel
	_chamas.speed_scale = vel


func _desenhar_rastro() -> void:
	_im.clear_surfaces()
	if _pontos.size() < 2:
		return
	var g := _grad_fogo if _fogo else _grad_arco
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _pontos.size()
	for i in n:
		var p := _pontos[i]
		var d: Vector3
		if i < n - 1:
			d = (p - _pontos[i + 1])
		else:
			d = (_pontos[i - 1] - p)
		d.y = 0.0
		if d.length() < 0.0001:
			d = Vector3(0, 0, -1)
		var lado := d.normalized().cross(Vector3.UP)
		var f := 1.0 - float(i) / float(n - 1)
		var w := RAIO * (1.2 if _fogo else 0.95) * (0.35 + 0.65 * f)
		# nunca passa da borda da pista
		w = clampf(minf(w, Mundo.MEIA_LARGURA - absf(p.x)), 0.0, w)
		var c := g.sample(float(i) / float(n - 1) if _fogo else fposmod(float(i) / 10.0, 1.0))
		c.a = f * 0.75
		_im.surface_set_color(c)
		_im.surface_add_vertex(p + lado * w)
		_im.surface_set_color(c)
		_im.surface_add_vertex(p - lado * w)
	_im.surface_end()


func velocidade() -> float:
	return linear_velocity.length() if rolando else 0.0


func _ao_bater(corpo: Node) -> void:
	bateu.emit(corpo, linear_velocity.length())


## O brilho na bola (aceso no strike / replay).
func acender(v: float) -> void:
	if _mat:
		_mat.set_shader_parameter("aceso", v)
