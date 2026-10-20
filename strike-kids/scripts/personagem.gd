class_name Personagem
extends Node3D

## UM PERSONAGEM (Bob, o cachorrinho, ou Mia, a gatinha): modelo articulado
## + animação por poses + rosto com expressões + piscar + olhar para a bola
## + rabinho que abana + brilhos de festa + bola na mão (solta no momento
## certo do arremesso).
##
## Movimento suave e natural (nada treme, nada encolhe/estica):
##   * Entre as poses-chave: curva monotônica (PCHIP) no tempo de verdade de
##     cada chave - passa por todas as poses sem passar do ponto e sem trocar
##     de velocidade de repente em cada pose.
##   * Troca de animação por INÉRCIA: o movimento que estava acontecendo
##     continua e se acomoda na animação nova (polinômio de 5º grau: posição,
##     velocidade e aceleração contínuas) - sem "congelar" no meio do gesto.
##   * IK de duas juntas nas pernas (quadril > joelho > tornozelo): o pé que
##     apoia fica TRAVADO no chão (não escorrega nem flutua) e o joelho dobra
##     sozinho quando o corpo abaixa; prender/soltar o pé é sempre gradual;
##     se o corpo anda/gira, o pé dá um passinho para acompanhar; o quadril
##     desce (suave) se o pé não alcançaria.
##   * Pé sempre de sola chata no chão; sombra de contato embaixo de cada pé.
##   * Pulos com arco de gravidade; o corpo NUNCA muda de tamanho (escala 1).
##   * Olhar e rabinho com mola amortecida (sem trancos).

signal soltou_bola(posicao: Vector3)
signal som(nome: String)
signal animacao_terminou(nome: String)

const EXPRESSOES := ["feliz", "piscando", "empolgado", "triste", "concentrado", "surpreso", "risada", "piscadinha"]
const JUNTAS := ["corpo", "cabeca", "braco_e", "antebraco_e", "braco_d", "antebraco_d",
	"coxa_e", "canela_e", "pe_e", "coxa_d", "canela_d", "pe_d"]
const PASSO_DUR := 0.22          # duração de um passinho automático (s)
const PASSO_ALTURA := 0.045      # quanto o pé sobe no passinho (m)
const DIST_PASSO := 0.13         # pé travado longe assim do lugar certo = dá um passo
const TROCA_PE := 0.14           # prender/soltar o pé leva este tempo (s)
const ESCALARES := ["altura", "frente", "giro", "voo"]

var nome_modelo := "bob"
var modelo: Node3D
var juntas := {}
var _pos_repouso := {}
var _mat_cabeca: ShaderMaterial
var _mats: Array[ShaderMaterial] = []
var bola_mao: MeshInstance3D
var _sombra: MeshInstance3D
var _festa: CPUParticles3D
var _rabo: Node3D
var _alegria := 0.5           # abana mais rápido quando está feliz
# pernas (IK) e pés
var _torn_y := 0.078          # altura do tornozelo com o pé apoiado
var chao := 0.0               # altura do chão onde ele pisa (pódio da escolha)
var _l1 := {}                 # coxa (quadril -> joelho)
var _l2 := {}                 # canela (joelho -> tornozelo)
var _pes := {}                # lado -> {preso, pos, passo (0..1 ou -1), de, para}
var _sombras_pe := {}
var _modo_ik := "trava"       # "trava" (pé preso), "chao" (só não afunda), "livre"
var _descer := 0.0             # quanto o quadril desce para o pé alcançar (suave)

var _clip := {}
var _nome_clip := ""
var _t := 0.0
var _eventos_feitos := {}
var _ultima_pose := {}         # pose mostrada agora
var _pose_ant := {}            # pose do quadro anterior (para a velocidade)
var _dt_ant := 1.0 / 60.0
var _inercia := {}             # canal -> coeficientes da transição por inércia
var _inercia_t := 0.0
var _inercia_dur := 0.0
var base := Transform3D()      # onde a animação "começou" (a corrida parte daqui)
var giro_base := 0.0

var _expressao := "feliz"
var _piscar_em := 2.0
var _piscando := 0.0
var olhar_alvo = null          # Vector3 (mundo) ou null
var _olhar := Vector2.ZERO     # yaw, pitch atuais
var _olhar_v := Vector2.ZERO
var _fase_resp := 0.0
var _fase_rabo := 0.0
var _alegria_suave := 0.5
var brilho := 1.4

## ROUPINHA DA FASE ("pirata", "dino", "astronauta", "parque"; "" = a de
## sempre): ver trocar_roupa.
const PECAS := ["corpo", "cabeca", "rabo", "braco_e", "antebraco_e", "braco_d", "antebraco_d",
	"coxa_e", "canela_e", "pe_e", "coxa_d", "canela_d", "pe_d"]
var roupa := ""
var _pecas := {}                     # junta -> MeshInstance3D dela
var _malhas_padrao := {}             # junta -> malha da roupa de sempre
var _estampa_padrao := {}
var _helice: MeshInstance3D          # hélice do boné (fase do parque): gira sozinha
var _pedidos: Array[String] = []     # roupas carregando em segundo plano
var _descartar: Array[String] = []   # carregadas e não usadas: soltar quando acabarem


func montar(nome: String) -> void:
	# as curvas de todas as animações são calculadas já aqui (na abertura):
	# calcular na primeira vez que um clipe toca dava um tranco na TV Box
	# (a primeira comemoração de strike, a primeira dança...)
	for clipe in Animacoes.todos():
		_preparar(Animacoes.pegar(clipe))
	nome_modelo = nome
	modelo = load("res://modelos/%s.scn" % nome).instantiate()
	add_child(modelo)
	var meta: Dictionary = modelo.get_meta("rosto", {})
	var rosto := Materiais.textura("rosto_" + nome)
	for j in JUNTAS:
		var no := modelo.find_child(j, true, false) as Node3D
		if no == null:
			continue
		juntas[j] = no
		_pos_repouso[j] = no.position
		var mi := no.get_node("malha") as MeshInstance3D
		var parametros := {"borda": 0.22, "cor_borda": Color(1.0, 0.92, 1.0), "brilho_luz": brilho, "faixa": 0.15, "luz_minima": 0.32}
		if j == "cabeca":
			parametros["usa_rosto"] = true
			parametros["rosto"] = rosto
			if meta.has("centro"):
				parametros["rosto_centro"] = Vector2(meta["centro"][0], meta["centro"][1])
				parametros["rosto_tamanho"] = Vector2(meta["tamanho"][0], meta["tamanho"][1])
		if j == "corpo":
			parametros.merge(_parametros_estampa(modelo.get_meta("estampa", {})), true)
		var m := Materiais.toon(true, 0.0032, parametros)
		mi.material_override = m
		# a malha já é leve; de longe ainda simplifica, mas sem sumir orelha
		mi.lod_bias = 1.5
		_mats.append(m)
		if j == "cabeca":
			_mat_cabeca = m
	# bola na mão direita
	bola_mao = MeshInstance3D.new()
	var esfera := SphereMesh.new()
	esfera.radius = Bola.RAIO
	esfera.height = Bola.RAIO * 2
	esfera.radial_segments = 32
	esfera.rings = 16
	bola_mao.mesh = esfera
	bola_mao.material_override = Bola.material(nome)
	var ante := juntas["antebraco_d"] as Node3D
	ante.add_child(bola_mao)
	var mao: Array = modelo.get_meta("mao_d", [-0.034, -0.15, 0.025])
	bola_mao.position = Vector3(mao[0], mao[1], mao[2]) + Vector3(0.0, -0.118, 0.028)
	bola_mao.visible = false
	# pernas: comprimentos e altura do tornozelo
	_torn_y = float(modelo.get_meta("tornozelo_y", 0.078))
	for lado in ["e", "d"]:
		if juntas.has("pe_" + lado):
			_l1[lado] = (_pos_repouso["canela_" + lado] as Vector3).length()
			_l2[lado] = (_pos_repouso["pe_" + lado] as Vector3).length()
		_pes[lado] = {"preso": false, "pos": Vector3.ZERO, "passo": -1.0, "de": Vector3.ZERO, "para": Vector3.ZERO}
		var sp := MeshInstance3D.new()
		var qp := QuadMesh.new()
		qp.size = Vector2(0.17, 0.24)
		qp.orientation = PlaneMesh.FACE_Y
		sp.mesh = qp
		sp.material_override = Materiais.sombra_blob(0.62)
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sp.top_level = true
		add_child(sp)
		_sombras_pe[lado] = sp
	# sombra redonda
	_sombra = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.75, 0.75)
	q.orientation = PlaneMesh.FACE_Y
	_sombra.mesh = q
	_sombra.material_override = Materiais.sombra_blob(0.38)
	_sombra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sombra)
	# rabinho (abana sozinho)
	_rabo = modelo.find_child("rabo", true, false) as Node3D
	if _rabo:
		var mr := _rabo.get_node("malha") as MeshInstance3D
		var m2 := Materiais.toon(true, 0.0032, {"borda": 0.22, "faixa": 0.15, "luz_minima": 0.32})
		mr.material_override = m2
		_mats.append(m2)
	# a roupa de sempre (para voltar depois das roupinhas das fases)
	for j in PECAS:
		var no := modelo.find_child(j, true, false)
		if no:
			_pecas[j] = no.get_node("malha") as MeshInstance3D
			_malhas_padrao[j] = (_pecas[j] as MeshInstance3D).mesh
	_estampa_padrao = _parametros_estampa(modelo.get_meta("estampa", {}))
	# brilhos de festa (estrelinhas e faíscas subindo em volta) para as comemorações
	_festa = CPUParticles3D.new()
	_festa.amount = 36
	_festa.lifetime = 0.9
	_festa.local_coords = false
	_festa.emitting = false
	_festa.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_festa.emission_ring_axis = Vector3.UP
	_festa.emission_ring_radius = 0.42
	_festa.emission_ring_inner_radius = 0.25
	_festa.emission_ring_height = 0.1
	_festa.direction = Vector3.UP
	_festa.spread = 25.0
	_festa.initial_velocity_min = 1.0
	_festa.initial_velocity_max = 2.2
	_festa.gravity = Vector3(0, -1.5, 0)
	_festa.angular_velocity_min = -300
	_festa.angular_velocity_max = 300
	_festa.scale_amount_min = 0.6
	_festa.scale_amount_max = 1.2
	var curva := Curve.new()
	curva.add_point(Vector2(0, 1.0))
	curva.add_point(Vector2(1, 0.0))
	_festa.scale_amount_curve = curva
	_festa.color_initial_ramp = Bola._arco_iris()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.09)
	qm.material = Materiais.particula("estrela", false)
	_festa.mesh = qm
	_festa.position = Vector3(0, 0.25, 0)
	add_child(_festa)
	tocar("parado")
	_piscar_em = randf_range(1.0, 3.0)


# ---------------------------------------------------------------- animação
## Troca a animação. `mistura`: segundos de transição suave.
func tocar(nome: String, mistura := 0.22, reiniciar := false) -> void:
	if nome == _nome_clip and not reiniciar:
		return
	# o que está na tela agora e para onde estava indo (velocidade)
	var antes := _ultima_pose.duplicate()
	var vel := {}
	if not _pose_ant.is_empty():
		for k in antes:
			if _pose_ant.has(k):
				vel[k] = (antes[k] - _pose_ant[k]) / maxf(_dt_ant, 0.001)
	_clip = _preparar(Animacoes.pegar(nome))
	_nome_clip = nome
	_modo_ik = str(_clip.get("ik", "trava"))
	_t = 0.0
	_eventos_feitos.clear()
	# o quanto ele andou/girou na animação anterior vira o novo ponto de partida
	if modelo != null:
		base = Transform3D(Basis(Vector3.UP, rotation.y), Vector3(position.x, base.origin.y, position.z))
	# (a velocidade continua: depois de soltar a bola ele desliza e para aos poucos)
	antes["frente"] = 0.0
	antes["giro"] = 0.0
	# inércia: a diferença entre a pose de agora e o começo da nova some aos
	# poucos, levando junto a velocidade que o gesto tinha
	_inercia.clear()
	_inercia_t = 0.0
	_inercia_dur = maxf(mistura, 0.001)
	if _ultima_pose.is_empty():
		return
	var novo0 := _amostra_clip(_clip, 0.0)
	var novo1 := _amostra_clip(_clip, 1.0 / 60.0)
	var canais := {}
	for k in antes:
		canais[k] = true
	for k in novo0:
		canais[k] = true
	for k in canais:
		var zero = 0.0 if k in ESCALARES else Vector3.ZERO
		var x0 = antes.get(k, zero) - novo0.get(k, zero)
		var v0 = vel.get(k, zero) - (novo1.get(k, zero) - novo0.get(k, zero)) * 60.0
		if k == "giro":
			_inercia[k] = [_inercia_coef(float(x0), float(v0), _inercia_dur, 420.0, 10.0)]
		elif k in ESCALARES:
			_inercia[k] = [_inercia_coef(float(x0), float(v0), _inercia_dur, 0.8, 0.015)]
		else:
			var a: Vector3 = x0
			var b: Vector3 = v0
			var vmax := 0.8 if k == "quadril" else 420.0
			var lim := 0.015 if k == "quadril" else 12.0
			_inercia[k] = [_inercia_coef(a.x, b.x, _inercia_dur, vmax, lim), _inercia_coef(a.y, b.y, _inercia_dur, vmax, lim),
				_inercia_coef(a.z, b.z, _inercia_dur, vmax, lim)]
	for k in _inercia:
		for c in _inercia[k]:
			if not (c as PackedFloat32Array).is_empty():
				_inercia_dur = maxf(_inercia_dur, c[5])


## Transição por inércia de solavanco mínimo: o deslocamento x0 entre a pose
## de agora e a nova, com a velocidade v0 que o gesto tinha, vai a zero por
## um polinômio de 5º grau que começa SEM arranque (aceleração 0) e chega
## parado (posição, velocidade e aceleração contínuas). O tempo cresce com o
## tamanho do movimento (no máximo `vmax` por segundo: nada de chicotada) e
## a velocidade herdada é limitada para nunca passar do ponto (indo para a
## pose nova) nem seguir longe demais (indo para o outro lado: `lim`).
## Devolve [A, B, C, v0, x0, t1, sinal].
static func _inercia_coef(x0: float, v0: float, t1: float, vmax: float, lim: float) -> PackedFloat32Array:
	if absf(x0) < 0.00001 and absf(v0) < 0.0001:
		return PackedFloat32Array()
	var s := 1.0 if x0 >= 0.0 else -1.0
	var x := x0 * s
	var v := v0 * s
	var t := clampf(maxf(t1, 1.875 * x / vmax), t1, 0.7)
	if v < 0.0 and -v * t > 2.5 * x:
		t = maxf(2.5 * x / -v, minf(t1, 0.12))
		v = maxf(v, -2.5 * x / t)
	elif v > 0.0:
		v = minf(v, maxf(2.0 * x, lim / 0.185) / t)
	var cc := -(6.0 * v * t + 10.0 * x) / pow(t, 3.0)
	var bb := (8.0 * v * t + 15.0 * x) / pow(t, 4.0)
	var aa := -(3.0 * v * t + 6.0 * x) / pow(t, 5.0)
	return PackedFloat32Array([aa, bb, cc, v, x, t, s])


static func _inercia_valor(c: PackedFloat32Array, t: float) -> float:
	if c.is_empty() or t >= c[5]:
		return 0.0
	return c[6] * ((((c[0] * t + c[1]) * t + c[2]) * t * t * t) + c[3] * t + c[4])


## Modo "à vontade" (atração, escolha): fica parado respirando e, de vez
## em quando, faz uma coisinha — acena, olha em volta, dança um pouquinho —
## e volta. Cada bichinho no seu tempo (nada de os dois quicando juntos).
var _ocioso := false
var _ocioso_t := 0.0
const OCIOSO_CLIPES := ["acenar_uma", "olhar_volta", "danca_curta", "acenar_uma", "danca_curta"]


func ocioso(ligar: bool) -> void:
	_ocioso = ligar
	_ocioso_t = randf_range(1.5, 4.0)
	if ligar:
		tocar("parado", 0.3)


func _ocioso_passo(delta: float) -> void:
	if not _ocioso or _nome_clip != "parado":
		return
	_ocioso_t -= delta
	if _ocioso_t <= 0.0:
		_ocioso_t = randf_range(4.0, 8.5)
		tocar(OCIOSO_CLIPES[randi() % OCIOSO_CLIPES.size()], 0.35, true)


func animacao() -> String:
	return _nome_clip


## Prepara o clipe uma vez: tempos, valores de cada canal em cada chave e as
## tangentes da curva (PCHIP, no tempo de verdade de cada chave).
static func _preparar(clip: Dictionary) -> Dictionary:
	if clip.has("_tempos"):
		return clip
	var chaves: Array = clip["chaves"]
	var tempos := PackedFloat32Array()
	var canais := {}
	for c in chaves:
		tempos.append(float(c[0]))
		for k in (c[1] as Dictionary):
			canais[k] = true
	var valores := {}
	var tangentes := {}
	var loop: bool = clip.get("loop", false)
	var dur := float(clip.get("dur", 1.0))
	for k in canais:
		var escalar: bool = k in ESCALARES
		var lista := []
		for c in chaves:
			var v = (c[1] as Dictionary).get(k, 0.0 if escalar else Vector3.ZERO)
			lista.append(float(v) if escalar else v)
		valores[k] = lista
		tangentes[k] = _tangentes(lista, tempos, loop, dur, escalar)
	clip["_tempos"] = tempos
	clip["_valores"] = valores
	clip["_tangentes"] = tangentes
	return clip


static func _tangentes(vals: Array, tempos: PackedFloat32Array, loop: bool, dur: float, escalar: bool) -> Array:
	var n := vals.size()
	var res := []
	for i in n:
		var ant = null
		var prox = null
		var h0 := 0.0
		var h1 := 0.0
		if i > 0:
			ant = vals[i - 1]
			h0 = tempos[i] - tempos[i - 1]
		elif loop and n > 2:
			ant = vals[n - 2]
			h0 = tempos[i] - (tempos[n - 2] - dur)
		if i < n - 1:
			prox = vals[i + 1]
			h1 = tempos[i + 1] - tempos[i]
		elif loop and n > 2:
			prox = vals[1]
			h1 = (tempos[1] + dur) - tempos[i]
		if ant == null or prox == null:
			# começo/fim do clipe: chega e sai devagar
			res.append(0.0 if escalar else Vector3.ZERO)
		elif escalar:
			res.append(_pchip(float(ant), float(vals[i]), float(prox), h0, h1))
		else:
			var a: Vector3 = ant
			var b: Vector3 = vals[i]
			var c: Vector3 = prox
			res.append(Vector3(_pchip(a.x, b.x, c.x, h0, h1), _pchip(a.y, b.y, c.y, h0, h1), _pchip(a.z, b.z, c.z, h0, h1)))
	return res


## Tangente monotônica (Fritsch-Carlson): zero nos picos e vales (não passa
## do ponto) e média ponderada pelo tempo nas subidas/descidas.
static func _pchip(a: float, b: float, c: float, h0: float, h1: float) -> float:
	h0 = maxf(h0, 0.0001)
	h1 = maxf(h1, 0.0001)
	var d0 := (b - a) / h0
	var d1 := (c - b) / h1
	if d0 * d1 <= 0.0:
		return 0.0
	var w1 := 2.0 * h1 + h0
	var w2 := h1 + 2.0 * h0
	return (w1 + w2) / (w1 / d0 + w2 / d1)


## A pose do clipe no instante t (Hermite cúbica com as tangentes PCHIP).
## Os pulos (arco de gravidade) entram no "voo".
func _amostra_clip(clip: Dictionary, t: float) -> Dictionary:
	var tempos: PackedFloat32Array = clip["_tempos"]
	var valores: Dictionary = clip["_valores"]
	var tangentes: Dictionary = clip["_tangentes"]
	var n := tempos.size()
	var res := {}
	if n == 1:
		for k in valores:
			res[k] = valores[k][0]
	else:
		var i := 0
		while i < n - 2 and t >= tempos[i + 1]:
			i += 1
		var h := maxf(tempos[i + 1] - tempos[i], 0.0001)
		var u := clampf((t - tempos[i]) / h, 0.0, 1.0)
		var u2 := u * u
		var u3 := u2 * u
		var h00 := 2.0 * u3 - 3.0 * u2 + 1.0
		var h10 := (u3 - 2.0 * u2 + u) * h
		var h01 := -2.0 * u3 + 3.0 * u2
		var h11 := (u3 - u2) * h
		for k in valores:
			var v: Array = valores[k]
			var m: Array = tangentes[k]
			res[k] = v[i] * h00 + m[i] * h10 + v[i + 1] * h01 + m[i + 1] * h11
	var pulo := _pulo(clip, t)
	if pulo > 0.0:
		res["voo"] = float(res.get("voo", 0.0)) + pulo
	return res


func _process(delta: float) -> void:
	if modelo == null:
		return
	var dur: float = _clip.get("dur", 1.0)
	var t_antes := _t
	_t += delta
	var loop: bool = _clip.get("loop", false)
	if loop:
		_t = fposmod(_t, dur)
	elif _t >= dur:
		_t = dur
		if t_antes < dur:
			animacao_terminou.emit.call_deferred(_nome_clip)
			# clipe que emenda em outro (ex.: vitória -> festa, aceno -> parado)
			if _clip.has("depois"):
				tocar.call_deferred(str(_clip["depois"]), 0.35)
	_ocioso_passo(delta)
	_eventos(t_antes, _t, loop and _t < t_antes)
	var pose := _amostra_clip(_clip, _t)
	if not _inercia.is_empty():
		_inercia_t += delta
		if _inercia_t >= _inercia_dur:
			_inercia.clear()
		else:
			for k in _inercia:
				var c: Array = _inercia[k]
				if k in ESCALARES:
					pose[k] = float(pose.get(k, 0.0)) + _inercia_valor(c[0], _inercia_t)
				else:
					pose[k] = pose.get(k, Vector3.ZERO) + Vector3(_inercia_valor(c[0], _inercia_t),
						_inercia_valor(c[1], _inercia_t), _inercia_valor(c[2], _inercia_t))
	_pose_ant = _ultima_pose
	_dt_ant = delta
	_ultima_pose = pose
	_aplicar(pose, delta)
	_rosto(delta)
	if _helice and _helice.visible:
		_helice.rotate_y(delta * (7.0 + 9.0 * _alegria_suave))
	if not _descartar.is_empty():
		_soltar_carregadas()


func _eventos(de: float, ate: float, deu_volta: bool) -> void:
	var evs: Array = _clip.get("eventos", [])
	for i in evs.size():
		var ev: Array = evs[i]
		var t: float = ev[0]
		var passou := (t > de and t <= ate) or (de == 0.0 and t == 0.0 and not _eventos_feitos.has(i)) or (deu_volta and (t > de or t <= ate))
		if passou and not _eventos_feitos.has(i):
			_eventos_feitos[i] = true
			match ev[1]:
				"soltar":
					if bola_mao.visible:
						var p := bola_mao.global_position
						bola_mao.visible = false
						soltou_bola.emit(p)
				"jatos":
					jatos(bool(ev[2]))
				"expressao":
					expressao(str(ev[2]))
				"som":
					som.emit(str(ev[2]))
	if deu_volta:
		_eventos_feitos.clear()


func _aplicar(pose: Dictionary, delta: float) -> void:
	var corpo_rot: Vector3 = pose.get("corpo", Vector3.ZERO)
	# respiração (bem de leve)
	_fase_resp = fposmod(_fase_resp + delta * 2.4, TAU)
	var resp := sin(_fase_resp) * 0.004
	var altura: float = pose.get("altura", 0.0) + resp
	var quadril: Vector3 = pose.get("quadril", Vector3.ZERO)
	var voo: float = maxf(pose.get("voo", 0.0), 0.0)
	var frente: float = pose.get("frente", 0.0)
	var giro: float = pose.get("giro", 0.0)
	for j in juntas:
		var no: Node3D = juntas[j]
		var r: Vector3 = pose.get(j, Vector3.ZERO)
		if j.begins_with("coxa"):
			r.x -= corpo_rot.x   # pernas em relação ao chão
		if j == "cabeca":
			r += Vector3(_olhar.y, _olhar.x, 0)
		# base nova a cada quadro (rotação pura, escala 1: nada acumula)
		no.basis = Basis.from_euler(r * (PI / 180.0))
	(juntas["corpo"] as Node3D).position = _pos_repouso["corpo"] + Vector3(quadril.x, altura, quadril.z)
	# deslocamento da corrida (para a frente do personagem) e voo
	var frente_mundo := base.basis.z.normalized() * frente
	position = base.origin + frente_mundo + Vector3(0, voo, 0)
	rotation.y = base.basis.get_euler().y + deg_to_rad(giro)
	if juntas.has("pe_e") and juntas.has("pe_d"):
		_ik_pernas(delta, voo)
	_sombras(voo)
	_olhar_passo(delta)
	# rabinho abanando (mais rápido quando está feliz; a fase anda sozinha,
	# então mudar a velocidade não dá tranco)
	if _rabo:
		_alegria_suave = lerpf(_alegria_suave, _alegria, 1.0 - exp(-delta * 3.0))
		_fase_rabo = fposmod(_fase_rabo + delta * (7.0 + _alegria_suave * 9.0), TAU * 2.0)
		_rabo.rotation = Vector3(sin(_fase_rabo * 0.5) * 0.12, sin(_fase_rabo) * (0.35 + _alegria_suave * 0.35), 0)


## Olha para a bola com uma mola amortecida (sem trancos). Só olha para o
## que está na frente: atrás, o pescoço ficava virando de um lado para o outro.
func _olhar_passo(delta: float) -> void:
	var alvo := Vector2.ZERO
	if olhar_alvo != null:
		var local := (juntas["corpo"] as Node3D).global_transform.affine_inverse() * (olhar_alvo as Vector3)
		var horiz := Vector2(local.x, local.z).length()
		var frente := clampf((local.z - 0.05) / 0.3, 0.0, 1.0) * clampf(horiz / 0.35, 0.0, 1.0)
		if frente > 0.0:
			var yaw := rad_to_deg(atan2(local.x, local.z))
			var pitch := -rad_to_deg(atan2(local.y - 0.55, horiz))
			alvo = Vector2(clampf(yaw, -55.0, 55.0), clampf(pitch, -25.0, 30.0)) * frente
	var w := 9.0
	var resto := delta
	while resto > 0.0:
		var h := minf(resto, 1.0 / 60.0)
		_olhar_v += ((alvo - _olhar) * w * w - _olhar_v * 2.0 * w) * h
		_olhar += _olhar_v * h
		resto -= h


## Altura extra dos pulos do clipe: arco de gravidade h = 4H·u·(1-u).
static func _pulo(clip: Dictionary, t: float) -> float:
	var h := 0.0
	for p in clip.get("pulos", []):
		var t0: float = p[0]
		var t1: float = p[1]
		if t > t0 and t < t1:
			var u := (t - t0) / (t1 - t0)
			h += 4.0 * float(p[2]) * u * (1.0 - u)
	return h


## IK das pernas com pé travado no chão. Cada pé tem um "peso" de apoio
## que vai de 0 (segue a animação) a 1 (preso no chão) aos poucos: prender,
## soltar (pulo, perna que levanta) e os passinhos nunca dão tranco.
func _ik_pernas(delta: float, voo: float) -> void:
	var alvos := {}
	var passando := false
	for lado in ["e", "d"]:
		var st: Dictionary = _pes[lado]
		if st["passo"] >= 0.0:
			passando = true
	var corpo := juntas["corpo"] as Node3D
	var ty := chao + _torn_y
	for lado in ["e", "d"]:
		var pe := juntas["pe_" + lado] as Node3D
		var st: Dictionary = _pes[lado]
		var fk := pe.global_position
		var altura_pe := fk.y - ty
		var livre := Vector3(fk.x, maxf(fk.y, ty), fk.z)
		if _modo_ik != "trava" or voo > 0.01:
			st["preso"] = false
			st["passo"] = -1.0
		elif st["passo"] >= 0.0:
			# passinho em andamento: vai do lugar antigo ao novo, subindo um pouco
			st["passo"] = minf(1.0, float(st["passo"]) + delta / PASSO_DUR)
			var u: float = st["passo"]
			var para := Vector3(fk.x, ty, fk.z)
			var e := u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
			st["ancora"] = (st["de"] as Vector3).lerp(para, e) + Vector3(0, PASSO_ALTURA * sin(PI * u), 0)
			if u >= 1.0:
				st["passo"] = -1.0
				st["preso"] = true
				st["pos"] = para
				st["ancora"] = para
		elif st["preso"]:
			var pos: Vector3 = st["pos"]
			var longe := Vector2(fk.x - pos.x, fk.z - pos.z).length()
			if altura_pe > 0.05:
				st["preso"] = false             # a perna levantou de propósito
			elif longe > DIST_PASSO and not passando:
				st["preso"] = false             # ficou para trás: um passinho
				st["passo"] = 0.0
				st["de"] = pos
				passando = true
			st["ancora"] = pos
		elif altura_pe < 0.02:
			st["preso"] = true
			st["pos"] = Vector3(fk.x, ty, fk.z)
			st["ancora"] = st["pos"]
		# peso do apoio: sobe/desce em TROCA_PE segundos (com curva suave)
		var quer := 1.0 if (st["preso"] or st["passo"] >= 0.0) else 0.0
		var lin: float = st.get("peso_lin", 0.0)
		lin = move_toward(lin, quer, delta / TROCA_PE)
		st["peso_lin"] = lin
		var w := lin * lin * (3.0 - 2.0 * lin)
		alvos[lado] = livre.lerp(st.get("ancora", livre), w) if w > 0.0 else livre
	# o quadril desce (suave) se um pé apoiado não alcançaria o chão
	var descer := 0.0
	for lado in ["e", "d"]:
		var coxa := juntas["coxa_" + lado] as Node3D
		var q := coxa.global_position
		var alvo: Vector3 = alvos[lado]
		var lmax: float = (_l1[lado] + _l2[lado]) * 0.985
		var dv := q.y - alvo.y
		var dh := Vector2(q.x - alvo.x, q.z - alvo.z).length()
		if dh < lmax:
			descer = maxf(descer, dv - sqrt(lmax * lmax - dh * dh))
	descer = clampf(descer, 0.0, 0.12)
	var rapidez := 40.0 if descer > _descer else 12.0
	_descer = lerpf(_descer, descer, 1.0 - exp(-delta * rapidez))
	if _descer > 0.0005:
		corpo.position.y -= _descer
	for lado in ["e", "d"]:
		_resolver_perna(lado, alvos[lado], float(_pes[lado].get("peso_lin", 0.0)) > 0.5)


func _resolver_perna(lado: String, alvo: Vector3, apoiado: bool) -> void:
	var coxa := juntas["coxa_" + lado] as Node3D
	var canela := juntas["canela_" + lado] as Node3D
	var pe := juntas["pe_" + lado] as Node3D
	var l1: float = _l1[lado]
	var l2: float = _l2[lado]
	var q := coxa.global_position
	var j_fk := canela.global_position
	var v := alvo - q
	var d := clampf(v.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.0008)
	var dir := v.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	# o joelho dobra para onde a pose mandou (e sempre para a frente)
	var frente := global_transform.basis.z.normalized()
	var polo := (j_fk - q) - dir * (j_fk - q).dot(dir) + frente * 0.02
	polo = polo - dir * polo.dot(dir)
	if polo.length() < 0.0001:
		polo = frente
	polo = polo.normalized()
	var j := q + dir * a + polo * h
	var de1 := (j_fk - q).normalized()
	var para1 := (j - q).normalized()
	if de1.dot(para1) < 0.99999:
		_girar_global(coxa, Quaternion(de1, para1))
	var a_agora := pe.global_position
	var de2 := (a_agora - j).normalized()
	var para2 := (q + dir * d - j).normalized()
	if de2.dot(para2) < 0.99999:
		_girar_global(canela, Quaternion(de2, para2))
	# pé de sola chata quando está no chão (ou perto dele)
	var peso := 1.0 if apoiado else clampf(1.0 - (alvo.y - chao - _torn_y) / 0.08, 0.0, 1.0)
	if peso > 0.0:
		var pai := canela.global_transform.basis.orthonormalized()
		var plano := pai.inverse() * Basis(Vector3.UP, global_rotation.y)
		var q_fk := pe.basis.orthonormalized().get_rotation_quaternion()
		var q_plano := plano.orthonormalized().get_rotation_quaternion()
		pe.basis = Basis(q_fk.slerp(q_plano, peso))


## Gira uma junta por uma rotação dada no espaço do mundo, mexendo só na
## rotação local dela (a escala continua 1, sem distorcer).
func _girar_global(no: Node3D, q: Quaternion) -> void:
	var pai := (no.get_parent() as Node3D).global_transform.basis.orthonormalized()
	var local := pai.inverse() * Basis(q) * pai
	no.basis = Basis(local.orthonormalized().get_rotation_quaternion()) * no.basis


func _sombras(voo: float) -> void:
	# sombra do corpo: fica no chão, menor quando voa
	_sombra.global_position = Vector3(global_position.x, chao + 0.006, global_position.z)
	_sombra.global_rotation = Vector3.ZERO
	var esc: float = clamp(1.0 - voo * 0.9, 0.35, 1.0)
	_sombra.scale = Vector3(esc, 1, esc)
	# sombra de contato de cada pé (some quando o pé sobe)
	for lado in _sombras_pe:
		var sp: MeshInstance3D = _sombras_pe[lado]
		if not juntas.has("pe_" + lado):
			sp.visible = false
			continue
		var pe := juntas["pe_" + lado] as Node3D
		var p := pe.global_position + pe.global_transform.basis.z.normalized() * 0.025
		var alto := maxf(0.0, p.y - chao - _torn_y)
		var e := clampf(1.0 - alto / 0.25, 0.25, 1.0)
		sp.global_position = Vector3(p.x, chao + 0.008, p.z)
		sp.global_rotation = Vector3(0, global_rotation.y, 0)
		sp.scale = Vector3(e, 1, e)


# ---------------------------------------------------------------- rosto
func expressao(nome: String) -> void:
	_expressao = nome
	_definir_celula(nome)
	_alegria = {"empolgado": 1.0, "risada": 1.0, "feliz": 0.7, "piscadinha": 0.8, "triste": 0.0, "concentrado": 0.25,
		"surpreso": 0.5}.get(nome, 0.5)


func _definir_celula(nome: String) -> void:
	var i := EXPRESSOES.find(nome)
	if i < 0:
		i = 0
	_mat_cabeca.set_shader_parameter("rosto_celula", Vector2(i % 4, i / 4))


func _rosto(delta: float) -> void:
	if _piscando > 0.0:
		_piscando -= delta
		if _piscando <= 0.0:
			_definir_celula(_expressao)
		return
	_piscar_em -= delta
	if _piscar_em <= 0.0:
		_piscar_em = randf_range(2.0, 4.5)
		if _expressao in ["feliz", "concentrado", "surpreso", "empolgado"]:
			_piscando = 0.13
			_definir_celula("piscando")


# ---------------------------------------------------------------- festa
## Estrelinhas subindo em volta (comemorações). O nome antigo "jatos" ficou
## nas animações e chamadas por compatibilidade.
func jatos(ligar: bool) -> void:
	_festa.emitting = ligar


## Estampa da roupa (estrela do Bob, bolinhas da Mia), desenhada no shader
## com os dados que o modelador gravou (tools/modelos/personagens.py).
func _parametros_estampa(e: Dictionary) -> Dictionary:
	if e.is_empty():
		return {}
	var p := {"estampa_base": Color(str(e["base"])), "estampa_cor": Color(str(e["cor"])), "estampa_raio": float(e["raio"])}
	if e["tipo"] == "estrela":
		p["estampa"] = 1
		p["estampa_centro"] = Vector2(e["centro"][0], e["centro"][1])
		p["estampa_dentro"] = float(e["dentro"])
	elif e["tipo"] == "listras":
		# listras de marinheiro (pirata): faixas de 2 x raio a cada "periodo"
		p["estampa"] = 3
		p["bolinhas_y0"] = float(e["y0"])
		p["bolinhas_dy"] = float(e["periodo"])
		p["bolinhas_y_max"] = float(e["y_max"])
	else:
		p["estampa"] = 2
		p["bolinhas_y0"] = float(e["y0"])
		p["bolinhas_dy"] = float(e["dy"])
		p["bolinhas_fileiras"] = int(e["fileiras"])
		p["bolinhas_n0"] = int(e["n0"])
		p["bolinhas_y_max"] = float(e["y_max"])
	return p


func _aplicar_estampa(p: Dictionary) -> void:
	var m := (_pecas["corpo"] as MeshInstance3D).material_override as ShaderMaterial
	m.set_shader_parameter("estampa", int(p.get("estampa", 0)))
	for k in p:
		m.set_shader_parameter(k, p[k])


# ---------------------------------------------------------------- roupinhas das fases
## A roupinha (modelos/roupas/<nome>_<roupa>.scn, feita pelo
## tools/modelos/roupas.py) tem as MESMAS juntas do bichinho: só a malha de
## cada junta troca — animações, IK das pernas, rosto e piscadas valem
## igual, e nenhum shader novo é preciso (nada de engasgo na troca).
## A roupa é carregada em segundo plano ANTES (pedir_roupa) e sai da memória
## sozinha quando ele volta para a roupa de sempre (ninguém mais segura as
## malhas dela).
func _caminho_roupa(r: String) -> String:
	return "res://modelos/roupas/%s_%s.scn" % [nome_modelo, r]


## Começa a carregar uma roupinha em segundo plano (o jogo não para).
func pedir_roupa(r: String) -> void:
	if r == "" or r == roupa:
		return
	var c := _caminho_roupa(r)
	if c in _pedidos:
		return
	if c in _descartar:
		_descartar.erase(c)
	elif ResourceLoader.exists(c):
		ResourceLoader.load_threaded_request(c)
	else:
		return
	_pedidos.append(c)


## Veste a roupinha `r` ("" = a de sempre). Se ela não foi pedida antes,
## carrega agora mesmo.
func trocar_roupa(r: String) -> void:
	if r == roupa:
		return
	var malhas := _malhas_padrao
	var estampa := _estampa_padrao
	var helice: Mesh = null
	var helice_pos := Vector3.ZERO
	var cena := _pegar_roupa(r) if r != "" else null
	if cena != null:
		var inst := cena.instantiate()
		malhas = {}
		for j in PECAS:
			var no := inst.find_child(j, true, false)
			if no:
				malhas[j] = (no.get_node("malha") as MeshInstance3D).mesh
		var h := inst.find_child("helice", true, false) as Node3D
		if h:
			helice = (h.get_node("malha") as MeshInstance3D).mesh
			helice_pos = h.position
		estampa = _parametros_estampa(inst.get_meta("estampa", {}))
		inst.free()
	else:
		r = ""   # sem o pacote da roupa: a de sempre
	if r == roupa:
		return
	roupa = r
	for j in malhas:
		if _pecas.has(j):
			(_pecas[j] as MeshInstance3D).mesh = malhas[j]
	_aplicar_estampa(estampa)
	if helice != null and _helice == null:
		_helice = MeshInstance3D.new()
		_helice.name = "helice"
		var m := Materiais.toon(true, 0.0032, {"borda": 0.22, "faixa": 0.15, "luz_minima": 0.32})
		_helice.material_override = m
		_mats.append(m)
		(juntas["cabeca"] as Node3D).add_child(_helice)
	if _helice:
		_helice.mesh = helice
		_helice.position = helice_pos
		_helice.visible = helice != null


func _pegar_roupa(r: String) -> PackedScene:
	var c := _caminho_roupa(r)
	if c in _pedidos or c in _descartar:
		_pedidos.erase(c)
		_descartar.erase(c)
		# já carregou em segundo plano (se ainda não acabou, espera o resto)
		return ResourceLoader.load_threaded_get(c) as PackedScene
	if not ResourceLoader.exists(c):
		return null
	return load(c) as PackedScene


## Roupinhas pedidas que não vão mais ser usadas (a partida acabou antes):
## soltas da memória assim que terminam de carregar.
func soltar_pedidos() -> void:
	for c in _pedidos:
		if not c in _descartar:
			_descartar.append(c)
	_pedidos.clear()


func _soltar_carregadas() -> void:
	for c in _descartar.duplicate():
		if ResourceLoader.load_threaded_get_status(c) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			ResourceLoader.load_threaded_get(c)
			_descartar.erase(c)


func segurar_bola(sim: bool) -> void:
	bola_mao.visible = sim


## Coloca o personagem num lugar, olhando para `direcao_y` (graus).
func posicionar(pos: Vector3, direcao_y: float) -> void:
	position = pos
	chao = pos.y
	rotation = Vector3(0, deg_to_rad(direcao_y), 0)
	base = transform
	for lado in _pes:
		_pes[lado]["preso"] = false
		_pes[lado]["passo"] = -1.0
		_pes[lado]["peso_lin"] = 0.0
	_descer = 0.0


## Brilho de destaque (personagem da vez fica "aceso").
func destaque(valor: float) -> void:
	for m in _mats:
		m.set_shader_parameter("flash", valor)


## Onde a mão direita fica no meio do arremesso (para a câmera mirar).
func posicao_mao() -> Vector3:
	return bola_mao.global_position
