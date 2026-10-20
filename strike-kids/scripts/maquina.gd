class_name Maquina
extends Node3D

## A MÁQUINA DE PINOS (pinsetter), como num boliche de verdade:
##   * BARRA varredora: desce na frente dos pinos (proteção), varre os
##     caídos para o fosso (empurrando de verdade, com física) e sobe.
##   * MESA: desce sobre os pinos, levanta os que ficaram em pé, espera a
##     varrida e devolve cada um no seu lugar. Num rack novo, desce já com
##     os 10 pinos encaixados e os deixa na pista.

signal terminou
signal som(nome: String)

const Y_REPOUSO := 1.85
const Y_ENCAIXE := 0.575       # altura da mesa com os pinos apoiados na pista
const Y_LEVANTA := 0.95
const Y_BARRA_CIMA := 1.72
const Y_BARRA_BAIXO := 0.085

var pinos: Pinos
var mesa: Node3D
var barra: AnimatableBody3D
var _z_mesa := 0.0
var _z_barra := 0.0
var _carregando: Array = []     # pinos presos na mesa: [pino, de onde saiu, lugar certo]
var _centrar := 0.0             # 0 = onde o pino estava, 1 = no lugar certo
var _seq := 0
var _tweens: Array[Tween] = []
var trabalhando := false
var rapidez := 1.25             # >1 = máquina mais rápida


func montar(p: Pinos) -> void:
	pinos = p
	_z_mesa = Mundo.Z_PINO1 - Mundo.FILEIRA * 1.5
	_z_barra = Mundo.Z_PINO1 + 0.5
	var cor_maquina := Color("#E4EAF4")
	var cor_detalhe := Color("#FFD23F")
	# mesa
	mesa = Node3D.new()
	mesa.name = "mesa"
	add_child(mesa)
	mesa.position = Vector3(0, Y_REPOUSO, _z_mesa)
	var placa := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.28, 0.07, 1.32)
	placa.mesh = bm
	placa.material_override = Materiais.cor_toon(cor_maquina, 0.0, {"borda": 0.3, "especular": 0.6})
	mesa.add_child(placa)
	var mat_copo := Materiais.cor_toon(cor_detalhe, 0.0, {"borda": 0.3})
	for n in range(1, 11):
		var pos := Pinos.posicao_do_pino(n)
		var copo := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.075
		cm.bottom_radius = 0.06
		cm.height = 0.12
		cm.radial_segments = 16
		copo.mesh = cm
		copo.material_override = mat_copo
		copo.position = Vector3(pos.x, -0.035 - 0.06, pos.z - _z_mesa)
		mesa.add_child(copo)
	# colunas que sobem para o teto (o mecanismo)
	for s in [-1.0, 1.0]:
		var col := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.top_radius = 0.03
		cc.bottom_radius = 0.03
		cc.height = 1.4
		col.mesh = cc
		col.material_override = Materiais.cor_toon(cor_maquina.darkened(0.25), 0.0, {"borda": 0.2})
		col.position = Vector3(s * 0.55, 0.7, 0)
		mesa.add_child(col)
	# barra varredora (corpo físico que empurra os pinos)
	barra = AnimatableBody3D.new()
	barra.name = "barra"
	barra.sync_to_physics = true
	barra.collision_layer = Mundo.CAMADA_MUNDO
	barra.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(Mundo.MEIA_LARGURA * 2 + 0.3, 0.17, 0.07)
	cs.shape = bs
	barra.add_child(cs)
	var vis := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = bs.size
	vis.mesh = bb
	vis.material_override = Materiais.cor_toon(cor_detalhe, 0.003, {"borda": 0.3})
	barra.add_child(vis)
	for s in [-1.0, 1.0]:
		var haste := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(0.05, 1.3, 0.05)
		haste.mesh = hb
		haste.material_override = Materiais.cor_toon(cor_maquina.darkened(0.25), 0.0, {"borda": 0.2})
		haste.position = Vector3(s * (Mundo.MEIA_LARGURA + 0.12), 0.65, 0)
		barra.add_child(haste)
	add_child(barra)
	barra.position = Vector3(0, Y_BARRA_CIMA, _z_barra)
	# mesa e barra andam nos passos da física (tweens de física): interpoladas
	for n in [mesa, barra]:
		(n as Node).physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
		(n as Node).reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	for item in _carregando:
		var p: Pino = item[0]
		var off: Vector3 = (item[1] as Vector3).lerp(item[2], _centrar)
		p.global_transform = Transform3D(Basis(), mesa.global_position + off)


func _tw(alvo: Object, prop: String, valor, dur: float) -> Tween:
	var t := create_tween()
	t.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	t.tween_property(alvo, prop, valor, dur / rapidez).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tweens.append(t)
	return t


## Espera o tween; false se a máquina foi interrompida no meio.
func _ok(t: Tween, s: int) -> bool:
	await t.finished
	_tweens.erase(t)
	return s == _seq


## Depois de uma bola que não fechou a rodada: guarda os pinos em pé,
## varre os caídos e devolve os em pé no lugar.
func reposicionar() -> void:
	await _ciclo(true)


## Rack novo (rodada nova): varre tudo e desce os 10 pinos.
func rack_novo() -> void:
	await _ciclo(false)


func _ciclo(manter: bool) -> void:
	_seq += 1
	var s := _seq
	trabalhando = true
	pinos.prender_todos()
	# 1. barra desce na frente (proteção)
	som.emit("barra")
	if not await _ok(_tw(barra, "position:y", Y_BARRA_BAIXO, 0.55), s):
		return
	# 2. mesa desce e levanta os pinos em pé (centralizando no lugar certo)
	_carregando.clear()
	_centrar = 0.0
	if manter:
		var em_pe := pinos.em_pe()
		if not em_pe.is_empty():
			som.emit("mesa")
			if not await _ok(_tw(mesa, "position:y", Y_ENCAIXE + 0.02, 0.7), s):
				return
			for n in em_pe:
				var p := pinos.pino(n)
				var onde := Vector3(p.global_position.x, p.lugar.y, p.global_position.z)
				p.global_transform = Transform3D(Basis(), onde)
				p.collision_layer = 0
				_carregando.append([p, onde - mesa.global_position, p.lugar - mesa.global_position])
			var t := _tw(mesa, "position:y", Y_LEVANTA, 0.45)
			t.parallel().tween_property(self, "_centrar", 1.0, 0.45 / rapidez)
			if not await _ok(t, s):
				return
	# 3. varre os caídos para o fosso (a barra empurra de verdade)
	var levados := []
	for item in _carregando:
		levados.append(item[0])
	for p in pinos.pinos:
		if not levados.has(p) and not p.removido:
			p.soltar()
			p.sleeping = false
	som.emit("varrer")
	if not await _ok(_tw(barra, "position:z", Mundo.Z_FIM_DECK - 0.15, 0.7), s):
		return
	for p in pinos.pinos:
		if not levados.has(p):
			p.tirar()
	if not await _ok(_tw(barra, "position:z", _z_barra, 0.5), s):
		return
	# 4. mesa devolve (ou traz os 10 novos)
	if not manter:
		mesa.position.y = Y_REPOUSO
		_centrar = 1.0
		for p in pinos.pinos:
			p.recolocar()
			p.collision_layer = 0
			var off := p.lugar - Vector3(0, Y_ENCAIXE, _z_mesa)
			_carregando.append([p, off, off])
			# já na mesa (sem aparecer um quadro na pista)
			p.global_transform = Transform3D(Basis(), mesa.global_position + off)
			p.reset_physics_interpolation()
	if not _carregando.is_empty():
		som.emit("mesa")
		if not await _ok(_tw(mesa, "position:y", Y_ENCAIXE, 0.85 if not manter else 0.75), s):
			return
		for item in _carregando:
			var p: Pino = item[0]
			p.recolocar()
		_carregando.clear()
		som.emit("pousar")
		pinos.som_pousar.emit()
		if not await _ok(_tw(mesa, "position:y", Y_REPOUSO, 0.6), s):
			return
	# 5. barra sobe
	som.emit("barra")
	if not await _ok(_tw(barra, "position:y", Y_BARRA_CIMA, 0.5), s):
		return
	trabalhando = false
	terminou.emit()


## Sem animação (atração, começo).
func instantaneo() -> void:
	_seq += 1
	for t in _tweens:
		if t.is_valid():
			t.kill()
	_tweens.clear()
	_carregando.clear()
	_centrar = 0.0
	mesa.position = Vector3(0, Y_REPOUSO, _z_mesa)
	barra.position = Vector3(0, Y_BARRA_CIMA, _z_barra)
	mesa.reset_physics_interpolation()
	barra.reset_physics_interpolation()
	for p in pinos.pinos:
		p.recolocar()
	trabalhando = false
