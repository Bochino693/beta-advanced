class_name Maquina
extends Node3D

## A MÁQUINA DE PINOS (pinsetter), como num boliche de verdade:
##   * BARRA varredora: desce na frente dos pinos (proteção), varre os
##     caídos para o fosso (empurrando de verdade, com física) e sobe.
##   * ALÇAPÃO: depois da varrida as duas portinhas do chão do fosso abrem
##     para baixo e os pinos caem no poço escuro (só com a bola já
##     recolhida; na jogada o chão fica sempre fechado).
##   * MESA: desce sobre os pinos, levanta os que ficaram em pé, espera a
##     varrida e devolve cada um no seu lugar. Num rack novo, desce já com
##     os 10 pinos encaixados e os deixa na pista.

signal terminou
signal som(nome: String)
## o alçapão vai abrir (true: a câmera do jogo corta para o fosso) / já
## fechou (false: volta para a mesa)
signal alcapao(abrindo: bool)

const Y_REPOUSO := 1.85
const Y_ENCAIXE := 0.575       # altura da mesa com os pinos apoiados na pista
const Y_LEVANTA := 0.95
const Y_BARRA_CIMA := 1.72
const Y_BARRA_BAIXO := 0.085
const ABRE_ALCAPAO := 1.4      # quanto as portinhas giram para baixo (rad)

var pinos: Pinos
var mesa: Node3D
var barra: AnimatableBody3D
var portas: Array[AnimatableBody3D] = []
var _portas_lado: Array[float] = []     # -1 = dobradiça na esquerda, 1 = na direita
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
	_montar_alcapao()
	# mesa, barra e portinhas andam nos passos da física (tweens de física): interpoladas
	for n in [mesa, barra] + portas:
		(n as Node).physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
		(n as Node).reset_physics_interpolation()


## As duas portinhas do alçapão (o vão é o Mundo.ALCAPAO_*): cada uma gira
## na dobradiça da beirada de fora; fechadas, o chão fica liso como o resto
## do fosso (mesma altura, mesmo atrito).
func _montar_alcapao() -> void:
	var comp := Mundo.ALCAPAO_Z0 - Mundo.ALCAPAO_Z1
	var mat := Materiais.cor_toon(Color("#1D4290"), 0.0, {"borda": 0.3})
	var mat_faixa := Materiais.cor_toon(Color("#FFD23F"), 0.0, {"borda": 0.25})
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	for s in [-1.0, 1.0]:
		var porta := AnimatableBody3D.new()
		porta.name = "alcapao_%d" % int(s)
		porta.sync_to_physics = true
		porta.collision_layer = Mundo.CAMADA_MUNDO
		porta.collision_mask = 0
		porta.physics_material_override = pm
		var tam := Vector3(Mundo.ALCAPAO_X - 0.004, 0.04, comp - 0.008)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = tam
		cs.shape = bs
		cs.position = Vector3(-s * tam.x / 2.0, -tam.y / 2.0, 0)
		porta.add_child(cs)
		var vis := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = tam
		vis.mesh = bm
		vis.material_override = mat
		vis.position = cs.position
		vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		porta.add_child(vis)
		# faixa amarela na beirada do meio (onde o chão se abre)
		var faixa := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.045, 0.004, tam.z - 0.05)
		faixa.mesh = fm
		faixa.material_override = mat_faixa
		faixa.position = Vector3(-s * (tam.x - 0.035), 0.002, 0)
		faixa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		porta.add_child(faixa)
		add_child(porta)
		portas.append(porta)
		_portas_lado.append(s)
	_fechar_portas()


## Portinhas fechadas, na hora (o transform INTEIRO: num corpo sincronizado
## com a física, mexer só no giro antes de um passo da física levaria a
## posição de antes, a da origem).
func _fechar_portas() -> void:
	for i in portas.size():
		portas[i].transform = Transform3D(Basis(), Vector3(_portas_lado[i] * Mundo.ALCAPAO_X, Mundo.Y_CHAO_FOSSO,
			(Mundo.ALCAPAO_Z0 + Mundo.ALCAPAO_Z1) / 2.0))
		portas[i].reset_physics_interpolation()


## Abre (as portinhas giram para baixo, acelerando como quem cai) ou fecha.
func _alcapao(abrir: bool, dur: float) -> Tween:
	var t := create_tween()
	t.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	t.set_parallel(true)
	for i in portas.size():
		var alvo := _portas_lado[i] * ABRE_ALCAPAO if abrir else 0.0
		t.tween_property(portas[i], "rotation:z", alvo, dur / rapidez).set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_IN if abrir else Tween.EASE_IN_OUT)
	_tweens.append(t)
	return t


func _pausa(dur: float) -> Tween:
	var t := create_tween()
	t.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	t.tween_interval(dur / rapidez)
	_tweens.append(t)
	return t


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
## varre os caídos e devolve os em pé no lugar. derrubou: a bola derrubou
## algum pino (numa jogada errada o alçapão não abre).
func reposicionar(derrubou := true) -> void:
	await _ciclo(true, derrubou)


## Rack novo (rodada nova): varre tudo e desce os 10 pinos.
func rack_novo(derrubou := true) -> void:
	await _ciclo(false, derrubou)


## Pinos caídos lá no fosso (atrás da pista), que o alçapão faria cair.
func _pinos_no_fosso(levados: Array) -> int:
	var n := 0
	for p in pinos.pinos:
		if levados.has(p) or p.removido:
			continue
		var g := p.global_position
		if g.z < Mundo.Z_FIM_DECK and g.z > Mundo.ALCAPAO_Z1 - 0.1 and absf(g.x) < Mundo.ALCAPAO_X + 0.05 and g.y < 0.0:
			n += 1
	return n


func _ciclo(manter: bool, derrubou := true) -> void:
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
	# 3b. o ALÇAPÃO: as portinhas abrem para baixo e os pinos do fosso caem
	# (com a física) até o fundo do poço — só se a bola derrubou pinos e há
	# pino caído no fosso (bola na canaleta / jogada errada: fica fechado)
	if derrubou and _pinos_no_fosso(levados) > 0:
		alcapao.emit(true)
		if not await _ok(_pausa(0.25), s):
			return
		som.emit("alcapao")
		if not await _ok(_alcapao(true, 0.45), s):
			return
		if not await _ok(_pausa(0.85), s):
			return
		# a barra volta enquanto o alçapão fecha; os pinos lá embaixo saem do jogo
		var fecha := _alcapao(false, 0.55)
		if not await _ok(_tw(barra, "position:z", _z_barra, 0.55), s):
			return
		if fecha.is_valid() and fecha.is_running():
			if not await _ok(fecha, s):
				return
		_fechar_portas()   # no lugar exato (sem acumular sobra de conta)
		for p in pinos.pinos:
			if not levados.has(p):
				p.tirar()
		alcapao.emit(false)
	else:
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
	_fechar_portas()
	for p in pinos.pinos:
		p.recolocar()
	trabalhando = false
