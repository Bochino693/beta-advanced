class_name Pino
extends RigidBody3D

## UM PINO com carinha. Corpo físico (Jolt) com o centro de massa no lugar
## de um pino de verdade (ele tomba fácil), sons de batida e expressões:
## normal / piscando / medo (bola chegando) / tonto ou bravinho (caiu) /
## feliz (ficou de pé — às vezes até dá pulinhos de comemoração).
## Os pulinhos são animação (o pino fica preso, sem física) e terminam
## exatamente onde ele estava: na hora da jogada está tudo no lugar.

signal bateu(pino: Pino, forca: float)

const EXPR := ["normal", "piscando", "medo", "tonto", "feliz", "surpreso", "triste", "bravo"]
const MASSA := 1.5

var numero := 1
var lugar := Vector3.ZERO
var malha: MeshInstance3D
var mat: ShaderMaterial
var removido := false
var _expr := "normal"
var _piscar := randf_range(1.0, 4.0)
var _piscando := 0.0
var _estrelas: Node3D
var _ultimo_som := 0
var _pulo: Tween
var _base_pulo := Transform3D()
var _pulando := false
var _raiva: Tween


func montar(n: int, pos: Vector3, malha_pino: Mesh, forma: Shape3D, rosto: Texture2D, meta: Dictionary) -> void:
	numero = n
	lugar = pos
	name = "Pino%d" % n
	mass = MASSA
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.17, 0)
	can_sleep = true
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = Mundo.CAMADA_PINOS
	collision_mask = Mundo.CAMADA_MUNDO | Mundo.CAMADA_PINOS | Mundo.CAMADA_BOLA | Mundo.CAMADA_PISO_PINOS | Mundo.CAMADA_SO_PINOS
	var pm := PhysicsMaterial.new()
	pm.friction = 0.38
	pm.bounce = 0.38
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	cs.shape = forma
	add_child(cs)
	malha = MeshInstance3D.new()
	malha.mesh = malha_pino
	mat = Materiais.toon(true, 0.0026, {
		"usa_rosto": true, "rosto": rosto, "rosto_grade": Vector2(4, 2),
		"rosto_centro": Vector2(meta.get("centro", [0, 0.215])[0], meta.get("centro", [0, 0.215])[1]),
		"rosto_tamanho": Vector2(meta.get("tamanho", [0.15, 0.13])[0], meta.get("tamanho", [0.15, 0.13])[1]),
		"borda": 0.4, "cor_borda": Color(0.92, 0.96, 1.0),
	})
	malha.material_override = mat
	malha.lod_bias = 3.0
	add_child(malha)
	_estrelas = Node3D.new()
	_estrelas.top_level = true
	_estrelas.visible = false
	var me := StandardMaterial3D.new()
	me.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	me.albedo_texture = Materiais.textura("estrela")
	me.albedo_color = Color("#FFE14D")
	me.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	me.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	for i in 3:
		var e := MeshInstance3D.new()
		var qe := QuadMesh.new()
		qe.size = Vector2(0.07, 0.07)
		e.mesh = qe
		e.material_override = me
		var a := TAU * i / 3.0
		e.position = Vector3(cos(a) * 0.1, 0, sin(a) * 0.1)
		_estrelas.add_child(e)
	add_child(_estrelas)
	body_entered.connect(_ao_bater)
	# o pino anda pela física e pela máquina (passos da física): interpolado.
	# As estrelinhas da tontura são postas a cada quadro.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	_estrelas.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	recolocar()


func recolocar() -> void:
	parar_pulo()
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	removido = false
	visible = true
	global_transform = Transform3D(Basis(), lugar)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = Mundo.CAMADA_PINOS
	collision_mask = Mundo.CAMADA_MUNDO | Mundo.CAMADA_PINOS | Mundo.CAMADA_BOLA | Mundo.CAMADA_PISO_PINOS | Mundo.CAMADA_SO_PINOS
	malha.scale = Vector3.ONE
	_estrelas.visible = false
	expressao("normal")
	if is_inside_tree():
		reset_physics_interpolation()


## Libera a física (antes da bola chegar).
func soltar() -> void:
	if removido:
		return
	parar_pulo()
	if physics_interpolation_mode != Node.PHYSICS_INTERPOLATION_MODE_ON:
		interpolar(true)
	freeze = false
	sleeping = false


func prender() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true


func esta_caido() -> bool:
	if removido:
		return true
	var up := global_transform.basis.y.normalized()
	if up.y < 0.74:
		return true
	if global_position.y < -0.12:
		return true
	if Vector2(global_position.x - lugar.x, global_position.z - lugar.z).length() > 0.75:
		return true
	return false


func tirar() -> void:
	removido = true
	prender()
	visible = false
	collision_layer = 0
	collision_mask = 0
	global_position = lugar + Vector3(0, -3, 0)
	_estrelas.visible = false


func expressao(nome: String) -> void:
	_expr = nome
	_celula(nome)


func _celula(nome: String) -> void:
	var i := EXPR.find(nome)
	mat.set_shader_parameter("rosto_celula", Vector2(i % 4, i / 4))


func _process(delta: float) -> void:
	if not visible:
		return
	# tontura: estrelinhas girando em volta da cabeça
	if _estrelas.visible:
		var topo := global_transform * Vector3(0, 0.42, 0)
		_estrelas.global_position = topo + Vector3(0, 0.1, 0)
		_estrelas.rotation.y += delta * 5.0
	# piscar
	if _piscando > 0.0:
		_piscando -= delta
		if _piscando <= 0.0:
			_celula(_expr)
	elif _expr == "normal" or _expr == "feliz":
		_piscar -= delta
		if _piscar <= 0.0:
			_piscar = randf_range(1.5, 4.5)
			_piscando = 0.12
			_celula("piscando")


func ficar_tonto() -> void:
	if not removido:
		expressao("tonto")
		_estrelas.visible = true


## Caiu e ficou bravinho: cara brava e uma tremidinha de raiva.
func ficar_bravo() -> void:
	if removido:
		return
	expressao("bravo")
	_estrelas.visible = false
	if _raiva != null and _raiva.is_valid():
		_raiva.kill()
	_raiva = create_tween()
	_raiva.tween_interval(randf_range(0.1, 0.5))
	for i in 3:
		_raiva.tween_property(malha, "rotation:x", 0.09, 0.05)
		_raiva.tween_property(malha, "rotation:x", -0.09, 0.07)
	_raiva.tween_property(malha, "rotation:x", 0.0, 0.06)


## Ficou de pé: feliz. pulos > 0: pulinhos de comemoração (agacha, pula,
## amortece), começando depois de `atraso`; no fim volta exatamente ao
## lugar de onde saiu.
func comemorar(atraso: float, pulos: int) -> void:
	if removido:
		return
	expressao("feliz")
	if pulos <= 0:
		return
	parar_pulo()
	prender()
	_base_pulo = global_transform
	_pulando = true
	# os pulinhos são animados a cada quadro: sem interpolar
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_pulo = create_tween()
	_pulo.tween_interval(atraso)
	for i in pulos:
		var h := 0.16 if i == 0 else 0.1
		_pulo.tween_property(malha, "scale", Vector3(1.08, 0.86, 1.08), 0.08)
		_pulo.tween_property(malha, "scale", Vector3(0.94, 1.1, 0.94), 0.07)
		_pulo.parallel().tween_method(_altura_pulo, 0.0, h, 0.17).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_pulo.tween_method(_altura_pulo, h, 0.0, 0.17).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_pulo.parallel().tween_property(malha, "scale", Vector3.ONE, 0.17)
		_pulo.tween_property(malha, "scale", Vector3(1.07, 0.9, 1.07), 0.06)
		_pulo.tween_property(malha, "scale", Vector3.ONE, 0.1)
	_pulo.tween_callback(parar_pulo)


func _altura_pulo(h: float) -> void:
	global_transform = Transform3D(_base_pulo.basis, _base_pulo.origin + Vector3(0, h, 0))


## Interrompe a comemoração e põe o pino de volta onde estava.
func parar_pulo() -> void:
	if _pulo != null and _pulo.is_valid():
		_pulo.kill()
	_pulo = null
	if _raiva != null and _raiva.is_valid():
		_raiva.kill()
	_raiva = null
	if malha:
		malha.rotation = Vector3.ZERO
		malha.scale = Vector3.ONE
	if _pulando:
		global_transform = _base_pulo
		_pulando = false
		interpolar(true)


## Liga/desliga a interpolação da física (desligada no replay e nos pulinhos).
func interpolar(sim: bool) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON if sim else Node.PHYSICS_INTERPOLATION_MODE_OFF
	if sim and is_inside_tree():
		reset_physics_interpolation()


func _ao_bater(corpo: Node) -> void:
	var agora := Time.get_ticks_msec()
	if agora - _ultimo_som < 90:
		return
	_ultimo_som = agora
	var v := linear_velocity.length()
	if corpo is RigidBody3D:
		v = max(v, (corpo as RigidBody3D).linear_velocity.length())
	if v > 0.35:
		bateu.emit(self, v)
