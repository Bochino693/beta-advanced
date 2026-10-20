class_name Temas
extends Node3D

## OS 4 CENÁRIOS — um por rodada (e a atração vai passando por todos).
## Cada um tem céu, luz, neblina, terreno e cores da pista próprios (CONFIG,
## aplicado por Mundo.aplicar_tema) e um grupo de decoração que se mexe:
##   parque — Parque de Diversões: roda-gigante, carrossel, tendas de circo, balões
##   espaco — Viagem ao Espaço: planeta com anel, foguetes, disco voador
##   mar    — Fundo do Mar: concha gigante, corais, algas, peixinhos, bolhas
##   dinos  — Selva dos Dinos: vulcão, dino pescoçudo, palmeiras, pterossauros

## a Selva dos Dinos é sempre a PRIMEIRA fase (e o começo da atração);
## depois Parque, Espaço e Mar
const ORDEM := ["dinos", "parque", "espaco", "mar"]

const CONFIG := {
	"parque": {
		"ceu": [Color("#2F7FFF"), Color("#6CBBFF"), Color("#E4F4FF"), Color("#8CD18C")],
		"ambiente": Color(0.62, 0.7, 0.86), "ambiente_forca": 0.62,
		"neblina": Color(0.84, 0.92, 1.0), "neblina_densidade": 0.0045,
		"sol": Color(1.0, 0.95, 0.86), "sol_forca": 1.05,
		"fundo": [Color("#3A1C8C"), Color("#7A3FD6")], "halo": Color("#FFD6F4"),
		"portal": [Color("#FFC21A"), Color("#E8384F")], "gabinete": Color("#E8384F"), "coluna": Color("#1E62C8"), "neon": Color("#FF4FC8"),
		"parede": Color("#2A63C4"),
		"placa": Color("#1E3FA0"), "divisoria": Color("#FFB627"), "faixa": Color("#E8384F"),
		# canaleta de doce (listras rosa e creme, lábios amarelos) e para-choques de bala
		"canaleta_modo": 0, "canaleta": [Color("#FF6FAE"), Color("#FFF3E2"), Color("#FFD23F")],
		"bumper": [Color("#FFFFFF"), Color("#FF3B50")],
		"chao": [Color("#6BCB5D"), Color("#5BB54E"), Color("#FFFFFF"), Color("#FFE873")], "chao_modo": 0,
	},
	"espaco": {
		"ceu": [Color("#040A26"), Color("#0E2560"), Color("#2C6AB8"), Color("#14244E")],
		"estrelas": 1.0, "nebulosa": Color("#2FC8FF"), "cor_sol": Color("#CFE0FF"), "forca_sol": 0.35,
		"ambiente": Color(0.6, 0.7, 1.0), "ambiente_forca": 0.78,
		"neblina": Color(0.14, 0.24, 0.5), "neblina_densidade": 0.006,
		"sol": Color(0.9, 0.94, 1.0), "sol_forca": 1.05,
		"fundo": [Color("#0B1450"), Color("#2A3FB0")], "halo": Color("#9FE8FF"),
		"portal": [Color("#4FD8FF"), Color("#3B2FA8")], "gabinete": Color("#3B3FA8"), "coluna": Color("#6A3FD0"), "neon": Color("#4FE3FF"),
		"parede": Color("#3B4FC8"),
		"placa": Color("#141E66"), "divisoria": Color("#4FD8FF"), "faixa": Color("#FF9F2E"),
		# canaleta de nave (metal com luzes correndo) e para-choques azul e branco
		"canaleta_modo": 1, "canaleta": [Color("#26357A"), Color("#9FB4FF"), Color("#4FE3FF")],
		"bumper": [Color("#FFFFFF"), Color("#3B8BFF")],
		"chao": [Color("#9AA8C4"), Color("#8494B3"), Color("#C3CEE2"), Color("#E2F5FF")], "chao_modo": 1,
	},
	"mar": {
		"ceu": [Color("#0A4F86"), Color("#1A94C0"), Color("#86E6DE"), Color("#E8D29A")],
		"raios": 1.0, "cor_sol": Color("#E6FFF8"), "forca_sol": 0.5,
		"ambiente": Color(0.5, 0.82, 0.92), "ambiente_forca": 0.72,
		"neblina": Color(0.32, 0.72, 0.84), "neblina_densidade": 0.014,
		"sol": Color(0.88, 1.0, 0.96), "sol_forca": 1.0,
		"fundo": [Color("#064A70"), Color("#0FA0B8")], "halo": Color("#C8FFF4"),
		"portal": [Color("#2EE6C8"), Color("#FF7A5C")], "gabinete": Color("#0E8C9C"), "coluna": Color("#FF7A5C"), "neon": Color("#5CFFD8"),
		"parede": Color("#18A6B8"),
		"placa": Color("#0B5A80"), "divisoria": Color("#FF8A5C"), "faixa": Color("#2EC4B6"),
		# canaleta de água (reflexos e bolhinhas) e para-choques coral
		"canaleta_modo": 2, "canaleta": [Color("#0C86A6"), Color("#56E0EA"), Color("#E9FFFB")],
		"bumper": [Color("#FFFFFF"), Color("#FF7A5C")],
		"chao": [Color("#F9DCA2"), Color("#EDC98A"), Color("#FFB09E"), Color("#9EDDE6")], "chao_modo": 2,
	},
	"dinos": {
		"ceu": [Color("#3FA7E8"), Color("#9BD8F0"), Color("#FFE4AE"), Color("#6BBF59")],
		"cor_sol": Color("#FFE7B0"),
		"ambiente": Color(0.72, 0.72, 0.62), "ambiente_forca": 0.62,
		"neblina": Color(0.92, 0.9, 0.78), "neblina_densidade": 0.006,
		"sol": Color(1.0, 0.93, 0.8), "sol_forca": 1.1,
		"fundo": [Color("#14501E"), Color("#3E9A2E")], "halo": Color("#FFF2A8"),
		"portal": [Color("#9BE04A"), Color("#FF8A1E")], "gabinete": Color("#8A5228"), "coluna": Color("#2E9A3E"), "neon": Color("#B6FF3B"),
		"parede": Color("#3E9A3A"),
		"placa": Color("#1E5A28"), "divisoria": Color("#FF9F2E"), "faixa": Color("#8BD33F"),
		# canaleta de bambu e para-choques amarelo e verde
		"canaleta_modo": 3, "canaleta": [Color("#6DBB45"), Color("#D4F58A"), Color("#F2D27A")],
		"bumper": [Color("#FFE65A"), Color("#2E9A3E")],
		"chao": [Color("#46A44E"), Color("#57B948"), Color("#FF9F33"), Color("#FFE65A")], "chao_modo": 3,
	},
}

const CORES_BICHOS := [Color("#FF9F2E"), Color("#FFD43B"), Color("#4FD8FF"), Color("#FF4B5C"), Color("#8DFF6A"), Color("#2E7BFF")]

## Lugares de destaque perto da pista (vistos de perto nas jogadas): x, z, giro, escala
const DESTAQUES := [[-2.55, -1.2, 0.3], [2.7, -2.7, -0.4], [-3.9, 3.4, 0.4], [3.9, 2.6, 0.0],
	[2.3, -6.0, 2.0], [-2.3, -6.8, 1.0], [-2.4, -4.2, 0.0], [2.45, -8.7, 0.5]]

var mundo: Mundo
var atual := ""
var grupos := {}
var _anim := {}          # tema -> [{no, tipo, ...}]
var _mats := {}
var _t := 0.0
## cenário LEVE (Mundo.leve): metade da decoração, sem contorno, luz por
## vértice (toon_leve) e menos partículas
var leve := false
var _mats_leve: Array[ShaderMaterial] = []


func construir(m: Mundo) -> void:
	mundo = m
	leve = m.leve
	for nome in ORDEM:
		var g := Node3D.new()
		g.name = nome
		g.visible = false
		add_child(g)
		grupos[nome] = g
		_anim[nome] = []
	_parque()
	_espaco()
	_mar()
	_dinos()
	# atrás de quem joga (a câmera vira para o mascote): o próprio cenário
	_atras("parque", [["carrossel", 0.9], ["tenda", 1.0], ["arvore_verde", 1.4], ["pirulito", 1.3], ["arvore_laranja", 1.4], ["cupcake", 1.5]])
	_atras("espaco", [["foguete", 1.1], ["pedra_lua", 1.7], ["cristal", 1.5], ["cristal", 1.1], ["pedra_lua", 1.3], ["foguete", 0.9]])
	_atras("mar", [["coral_roxo", 1.5], ["concha", 1.3], ["alga", 1.6], ["coral", 1.5], ["alga", 1.3], ["bau", 1.2]])
	_atras("dinos", [["palmeira", 1.1], ["samambaia", 1.5], ["ovo_dino", 1.3], ["pedra", 1.4], ["palmeira", 0.95], ["flor_gigante", 1.4]])
	# o que fica parado em cada cenário vira poucas malhas (uma por material)
	for nome in ORDEM:
		var fora: Array = []
		for item in _anim[nome]:
			for k in ["no", "roda", "particulas"]:
				if item.has(k):
					fora.append(item[k])
			if item.has("cabines"):
				fora.append_array(item["cabines"])
		Lote.juntar(grupos[nome], fora)


func mostrar(nome: String) -> void:
	atual = nome
	for k in grupos:
		(grupos[k] as Node3D).visible = k == nome
		for item in _anim[k]:
			if item.has("particulas"):
				(item["particulas"] as CPUParticles3D).emitting = k == nome


static func proximo(nome: String) -> String:
	return ORDEM[(ORDEM.find(nome) + 1) % ORDEM.size()]


# ================================================================ peças
func _mat(contorno: float, tinta: Color, extra := {}) -> ShaderMaterial:
	if leve:
		contorno = 0.0
	var chave := "%s|%s|%s" % [contorno, tinta.to_html(), str(extra)]
	if not _mats.has(chave):
		var p := {"borda": 0.3, "tinta": tinta}
		p.merge(extra, true)
		_mats[chave] = _toon(contorno, p)
	return _mats[chave]


## Toon do cenário: o completo (luz por pixel, contorno) ou o leve (luz por
## vértice; o brilho especular não existe nele).
func _toon(contorno: float, p: Dictionary) -> ShaderMaterial:
	if not leve:
		return Materiais.toon(false, contorno, p)
	var m := ShaderMaterial.new()
	m.shader = Materiais.shader("res://shaders/toon_leve.gdshader")
	for k in p:
		if k != "especular" and k != "tamanho_especular":
			m.set_shader_parameter(k, p[k])
	_mats_leve.append(m)
	return m


## Quantas peças de um tipo: a metade (pelo menos uma) no cenário leve.
func _q(n: int) -> int:
	return maxi(1, int(round(n * 0.45))) if leve else n


## A luz da cena para a decoração leve (Mundo.aplicar_tema): para onde está o
## sol, cor x força do sol e do ambiente e a neblina (cores lineares).
func luz(sol_dir: Vector3, sol_cor: Vector3, ambiente: Vector3, neblina_cor: Vector3, neblina_densidade: float) -> void:
	for m in _mats_leve:
		m.set_shader_parameter("sol_dir", sol_dir)
		m.set_shader_parameter("sol_cor", sol_cor)
		m.set_shader_parameter("ambiente", ambiente)
		m.set_shader_parameter("neblina_cor", neblina_cor)
		m.set_shader_parameter("neblina_densidade", neblina_densidade)


## Um objeto do cenário (res://modelos/cenario/<nome>.res) no grupo do tema.
func _obj(tema: String, nome: String, pos: Vector3, rot_y := 0.0, esc := 1.0, contorno := 0.0,
		tinta := Color.WHITE, pai: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var caminho := "res://modelos/cenario/%s.res" % nome
	if ResourceLoader.exists(caminho):
		mi.mesh = load(caminho)
	mi.material_override = _mat(contorno, tinta)
	mi.position = pos
	mi.rotation.y = rot_y
	mi.scale = Vector3.ONE * esc
	# sombra só dos que ficam colados na pista (os de longe não precisam)
	if absf(pos.x) > 3.6 or pos.z < -15.0 or pos.z > 4.0 or pos.y > 1.5:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(pai if pai != null else grupos[tema] as Node3D).add_child(mi)
	return mi


func _chao(x: float, z: float) -> float:
	return mundo._altura_terreno(x, z)


func _animar(tema: String, item: Dictionary) -> void:
	_anim[tema].append(item)


## Espalha objetos pelo terreno, longe da pista (mesma regra do parque).
func _espalhar(tema: String, tipos: Array, qtd: int, semente: int, escala := {}, evitar: Array[Vector2] = []) -> void:
	var rnd := RandomNumberGenerator.new()
	rnd.seed = semente
	# evitar: lugares já ocupados por peças grandes (nada nasce dentro delas)
	var usados: Array[Vector2] = evitar.duplicate()
	var colocados := 0
	var tentativas := 0
	while colocados < qtd and tentativas < 2000:
		tentativas += 1
		var s := -1.0 if rnd.randf() < 0.5 else 1.0
		var x := s * rnd.randf_range(3.6, 15.0)
		var z := rnd.randf_range(-34.0, 7.0)
		if z > -2.0 and absf(x) < 5.0:
			continue
		var p := Vector2(x, z)
		var ok := true
		for u in usados:
			if u.distance_to(p) < 2.6:
				ok = false
				break
		if not ok:
			continue
		usados.append(p)
		var tipo: String = tipos[rnd.randi() % tipos.size()]
		var esc := rnd.randf_range(0.9, 1.35) * float(escala.get(tipo, 1.0))
		_obj(tema, tipo, Vector3(x, _chao(x, z) - 0.05, z), rnd.randf() * TAU, esc)
		colocados += 1


func _destaques(tema: String, itens: Array) -> void:
	# itens: [nome, escala, contorno] na ordem de DESTAQUES
	for i in mini(itens.size(), DESTAQUES.size()):
		var d: Array = DESTAQUES[i]
		var it: Array = itens[i]
		var x: float = d[0]
		var z: float = d[1]
		var y: float = 0.0 if (z > 0.0 and absf(x) < 3.3) else _chao(x, z)
		_obj(tema, it[0], Vector3(x, y - 0.02, z), d[2], it[1], it[2] if it.size() > 2 else 0.0)


## Lugares atrás da mureta dos jogadores (x, z, giro).
const ATRAS := [[-5.4, 10.6, 0.4], [5.3, 11.2, -0.5], [-2.5, 12.9, 0.2], [2.6, 13.6, -0.2], [-8.6, 13.2, 0.8], [8.4, 12.4, -0.9]]


func _atras(tema: String, itens: Array) -> void:
	for i in mini(itens.size(), ATRAS.size()):
		var a: Array = ATRAS[i]
		var x: float = a[0]
		var z: float = a[1]
		_obj(tema, itens[i][0], Vector3(x, _chao(x, z) - 0.05, z), PI + float(a[2]), float(itens[i][1]))


func _torres(tema: String, nome: String, esc := 1.0, contorno := 0.004) -> void:
	for s in [-1.0, 1.0]:
		_obj(tema, nome, Vector3(s * 2.75, -0.02, Mundo.Z_FUNDO + 0.4), -s * deg_to_rad(25.0), esc, contorno)


func _particulas(tema: String, pos: Vector3, textura: String, qtd: int, vida: float, tam: float, somar := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = qtd
	p.lifetime = vida
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(tam, tam)
	q.material = Materiais.particula(textura, somar)
	p.mesh = q
	p.position = pos
	p.emitting = false
	(grupos[tema] as Node3D).add_child(p)
	_animar(tema, {"tipo": "nada", "particulas": p})
	return p


# ================================================================ PARQUE
func _parque() -> void:
	var T := "parque"
	# arco-íris com lâmpadas e torres de circo
	_obj(T, "arco_iris", Vector3(0, -0.05, Mundo.Z_FUNDO - 0.5), 0.0, 0.95, 0.0, Color.WHITE)
	var R := 3.0 * 0.95 - 0.42 * 0.95 - 0.08
	var pontos: Array[Vector3] = []
	for i in 40:
		var a := PI * (i + 0.5) / 40.0
		pontos.append(Vector3(cos(a) * R, sin(a) * R - 0.05, Mundo.Z_FUNDO - 0.5 + 0.38))
	grupos[T].add_child(mundo.lampadas_em(pontos, 100))
	_torres(T, "torre")
	_espalhar(T, ["arvore_verde", "arvore_laranja", "arvore_escura", "pirulito", "cogumelo", "bengala",
		"presente", "donut", "cupcake", "arvore_verde", "arvore_escura", "arvore_laranja"], _q(40), 2026,
		{"arvore_verde": 1.25, "arvore_laranja": 1.25, "arvore_escura": 1.25})
	_destaques(T, [["pirulito", 0.75, 0.004], ["pirulito", 0.85, 0.004], ["presente", 0.8, 0.004], ["cupcake", 0.75, 0.004],
		["bengala", 0.9], ["bengala", 0.9], ["cogumelo", 0.9], ["donut", 0.85]])
	# roda-gigante (gira) com as cabines sempre de pé
	var rg := Node3D.new()
	rg.position = Vector3(-6.8, _chao(-6.8, -27.0) - 0.05, -27.0)
	rg.rotation.y = 0.35
	grupos[T].add_child(rg)
	_obj(T, "roda_base", Vector3.ZERO, 0.0, 1.0, 0.0, Color.WHITE, rg)
	var eixo := Node3D.new()
	eixo.position = Vector3(0, 4.6, 0)
	rg.add_child(eixo)
	var roda := _obj(T, "roda", Vector3.ZERO, 0.0, 1.0, 0.0, Color.WHITE, eixo)
	var cabines := []
	for i in 8:
		var c := _obj(T, "cabine", Vector3.ZERO, 0.0, 1.0, 0.0, CORES_BICHOS[i % CORES_BICHOS.size()], eixo)
		cabines.append(c)
	_animar(T, {"tipo": "roda", "roda": roda, "cabines": cabines, "raio": 3.8, "vel": 0.16})
	# carrossel (gira devagar) e tendas
	var car := _obj(T, "carrossel", Vector3(6.4, _chao(6.4, -21.0) - 0.05, -21.0), 0.0, 1.2)
	_animar(T, {"tipo": "girar", "no": car, "vel": 0.5})
	_obj(T, "tenda", Vector3(-9.5, _chao(-9.5, -13.0) - 0.05, -13.0), 0.6, 1.1)
	_obj(T, "tenda", Vector3(10.5, _chao(10.5, -33.0) - 0.05, -33.0), -0.4, 1.3)
	_obj(T, "carrossel", Vector3(-12.0, _chao(-12.0, -38.0) - 0.05, -38.0), 0.0, 1.0)
	_nuvens(T, 14, 77)
	_baloes(T)


func _nuvens(tema: String, qtd: int, semente: int) -> void:
	var rnd := RandomNumberGenerator.new()
	rnd.seed = semente
	var mat := _toon(0.0, {"borda": 0.6, "luz_minima": 0.5, "cor_borda": Color(0.9, 0.96, 1)})
	for i in _q(qtd):
		var n := _obj(tema, "nuvem", Vector3.ZERO)
		n.material_override = mat
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var lado := -1.0 if i % 2 == 0 else 1.0
		n.position = Vector3(lado * rnd.randf_range(4.0, 22.0), rnd.randf_range(6.0, 15.0), rnd.randf_range(-60.0, -8.0))
		n.scale = Vector3.ONE * rnd.randf_range(1.2, 2.6)
		n.rotation.y = rnd.randf() * TAU
		_animar(tema, {"tipo": "nuvem", "no": n, "vel": rnd.randf_range(0.15, 0.4)})


func _baloes(tema: String) -> void:
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 91
	var mb: Mesh = load("res://modelos/cenario/balao.res")
	var cores := [Color("#FF4B5C"), Color("#FFD43B"), Color("#4FC3F7"), Color("#5ED16A"), Color("#2E7BFF"), Color("#FF9F2E")]
	var linha_mat := _toon(0.0, {"tinta": Color("#FFFFFF"), "borda": 0.0})
	for i in (8 if leve else 16):
		var b := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = mb
		mi.material_override = _mat(0.0, cores[i % cores.size()], {"borda": 0.6, "especular": 0.8, "tamanho_especular": 0.95})
		b.add_child(mi)
		var fio := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.004
		cm.bottom_radius = 0.004
		cm.height = 0.9
		cm.radial_segments = 4
		fio.mesh = cm
		fio.position.y = -0.45
		fio.material_override = linha_mat
		b.add_child(fio)
		var lado := -1.0 if i % 2 == 0 else 1.0
		var base := Vector3(lado * rnd.randf_range(1.8, 5.5), rnd.randf_range(2.2, 4.8), rnd.randf_range(-19.0, -4.0))
		if i < 4:
			base = Vector3(lado * rnd.randf_range(2.0, 2.8), rnd.randf_range(2.6, 3.4), Mundo.Z_FUNDO + rnd.randf_range(0.0, 1.5))
		b.position = base
		b.scale = Vector3.ONE * rnd.randf_range(0.8, 1.15)
		grupos[tema].add_child(b)
		_animar(tema, {"tipo": "boiar", "no": b, "base": base, "fase": rnd.randf() * TAU, "vel": rnd.randf_range(0.6, 1.1),
			"amp": Vector3(0.12, 0.18, 0.0), "balanco": 0.12})


# ================================================================ ESPAÇO
func _espaco() -> void:
	var T := "espaco"
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 404
	# planeta com anel atrás dos pinos (aparece por cima do letreiro); gira
	# em volta do eixo do ANEL (o da malha, tools/modelos/temas.py): o anel
	# fica sempre com a mesma inclinação (girando em volta do eixo do mundo
	# ele ficava de lado, um "palito")
	var pa := _obj(T, "planeta_anel", Vector3(0.3, 3.7, Mundo.Z_FUNDO - 2.6), 0.0, 1.15)
	pa.rotation = Vector3(0.18, 0.0, 0.32)
	_animar(T, {"tipo": "girar_proprio", "no": pa, "vel": 0.12, "eixo": Vector3(-0.336, 0.894, 0.296).normalized()})
	# dois foguetes em pé no chão, ao lado do gabinete, inteiros à vista
	# (atrás das colunas só aparecia a pontinha das aletas)
	var foguetes: Array[Vector2] = []
	for s in [-1.0, 1.0]:
		var fx: float = s * 3.35
		var fz := -11.0
		_obj(T, "foguete", Vector3(fx, _chao(fx, fz) - 0.03, fz), -s * deg_to_rad(35.0), 0.95, 0.004)
		foguetes.append(Vector2(fx, fz))
	# disco voador passeando por cima do fim da pista: na FRENTE do planeta
	# e acima do letreiro (nunca atravessa o planeta nem some atrás do arco),
	# inclinando nas curvas como um aviãozinho
	var ovni := _obj(T, "ovni", Vector3(0, 5.0, -12.1), 0.0, 1.0, 0.004)
	_animar(T, {"tipo": "passeio", "no": ovni, "centro": Vector3(0, 5.0, -12.1), "raio": Vector3(3.1, 0.25, 0.65),
		"vel": 0.3, "girar": 1.6, "ang": 0.0})
	# planetinhas coloridos no céu
	for i in _q(8):
		var lado := -1.0 if i % 2 == 0 else 1.0
		var pos := Vector3(lado * rnd.randf_range(6.0, 22.0), rnd.randf_range(5.0, 15.0), rnd.randf_range(-58.0, -14.0))
		var pl := _obj(T, "planeta", pos, rnd.randf() * TAU, rnd.randf_range(1.6, 4.2), 0.0, CORES_BICHOS[i % CORES_BICHOS.size()])
		pl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_animar(T, {"tipo": "girar", "no": pl, "vel": rnd.randf_range(0.05, 0.2)})
	# estrelas fofas flutuando ao lado da pista
	for i in _q(6):
		var lado := -1.0 if i % 2 == 0 else 1.0
		var base := Vector3(lado * rnd.randf_range(2.1, 3.4), rnd.randf_range(2.2, 3.8), rnd.randf_range(-17.0, -3.0))
		var e := _obj(T, "estrela_3d", base, 0.0, rnd.randf_range(0.6, 0.9), 0.003)
		# balança de um lado para o outro (girando inteira ela ficava de
		# perfil, um palitinho amarelo)
		_animar(T, {"tipo": "boiar", "no": e, "base": base, "fase": rnd.randf() * TAU, "vel": rnd.randf_range(0.7, 1.1),
			"amp": Vector3(0.0, 0.2, 0.0), "olhar": -lado * 0.35, "vira": 0.45})
	_espalhar(T, ["cristal", "pedra_lua", "cristal", "pedra_lua", "pedra_lua", "foguete"], _q(38), 77,
		{"cristal": 1.3, "pedra_lua": 1.6, "foguete": 0.8}, foguetes)
	_destaques(T, [["cristal", 0.9, 0.004], ["cristal", 1.0, 0.004], ["pedra_lua", 1.0, 0.004], ["cristal", 0.8, 0.004],
		["pedra_lua", 1.1], ["cristal", 1.0], ["pedra_lua", 1.0], ["cristal", 1.1]])
	# estrelas cadentes de vez em quando (faíscas que atravessam o céu)
	var cad := _particulas(T, Vector3(0, 13.0, -30.0), "faisca", 3, 1.6, 0.6, true)
	cad.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	cad.emission_box_extents = Vector3(14, 3, 8)
	cad.direction = Vector3(1, -0.35, 0)
	cad.spread = 5.0
	cad.gravity = Vector3.ZERO
	cad.initial_velocity_min = 14.0
	cad.initial_velocity_max = 18.0
	cad.color = Color(1.0, 0.95, 0.8)


# ================================================================ FUNDO DO MAR
func _mar() -> void:
	var T := "mar"
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 505
	# concha gigante atrás dos pinos e corais no lugar das torres
	_obj(T, "concha", Vector3(0, -0.05, Mundo.Z_FUNDO - 0.45), 0.0, 2.9, 0.0)
	_obj(T, "coral", Vector3(-2.75, -0.02, Mundo.Z_FUNDO + 0.4), deg_to_rad(25.0), 2.1, 0.004)
	_obj(T, "coral_roxo", Vector3(2.75, -0.02, Mundo.Z_FUNDO + 0.4), deg_to_rad(-25.0), 2.3, 0.004)
	_espalhar(T, ["coral", "coral_roxo", "alga", "alga", "estrela_mar", "concha", "pedra", "coral"], _q(44), 31,
		{"coral": 1.5, "coral_roxo": 1.5, "alga": 1.3, "estrela_mar": 1.6, "concha": 0.7, "pedra": 1.2})
	_destaques(T, [["coral", 0.8, 0.004], ["alga", 0.8, 0.0], ["estrela_mar", 1.0, 0.004], ["bau", 0.9, 0.004],
		["coral_roxo", 0.9], ["alga", 0.9], ["concha", 0.5], ["estrela_mar", 1.0]])
	# algas balançando na correnteza (as dos destaques e mais algumas)
	for g in grupos[T].get_children():
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null and (g as MeshInstance3D).mesh.resource_path.ends_with("alga.res"):
			_animar(T, {"tipo": "alga", "no": g, "fase": rnd.randf() * TAU, "base": (g as Node3D).rotation})
	# cardumes de peixinhos
	for c in (3 if leve else 5):
		var centro := Vector3((-1.0 if c % 2 == 0 else 1.0) * rnd.randf_range(3.0, 7.0), rnd.randf_range(2.6, 5.5), rnd.randf_range(-20.0, -4.0))
		var cor: Color = CORES_BICHOS[c % CORES_BICHOS.size()]
		var vel := rnd.randf_range(0.25, 0.45) * (1.0 if c % 2 == 0 else -1.0)
		for k in (3 if leve else 5):
			var p := _obj(T, "peixe", centro, 0.0, rnd.randf_range(0.7, 1.0), 0.003, cor)
			_animar(T, {"tipo": "peixe", "no": p, "centro": centro + Vector3(rnd.randf_range(-0.4, 0.4), rnd.randf_range(-0.3, 0.3), 0),
				"raio": Vector2(rnd.randf_range(2.2, 3.0), rnd.randf_range(1.4, 2.0)), "vel": vel, "fase": k * 0.22, "nado": rnd.randf() * TAU})
	# águas-vivas subindo e descendo
	for i in _q(7):
		var lado := -1.0 if i % 2 == 0 else 1.0
		var base := Vector3(lado * rnd.randf_range(2.2, 5.0), rnd.randf_range(2.4, 5.2), rnd.randf_range(-19.0, -2.0))
		var cor: Color = [Color("#FFB36B"), Color("#9FF0C8"), Color("#8FE9FF")][i % 3]
		var av := _obj(T, "agua_viva", base, 0.0, rnd.randf_range(0.7, 1.0), 0.003, cor)
		_animar(T, {"tipo": "agua_viva", "no": av, "base": base, "fase": rnd.randf() * TAU, "vel": rnd.randf_range(0.8, 1.2)})
	# tartarugas atravessando o mar lá no alto
	for i in _q(2):
		var tt := _obj(T, "tartaruga", Vector3(0, 7.5 + i * 2.0, -24.0 - i * 10.0), PI / 2 * (1 if i == 0 else -1), 1.8 + i * 0.4)
		_animar(T, {"tipo": "atravessar", "no": tt, "vel": 1.1 * (1 if i == 0 else -1), "limite": 28.0})
	# bolhas subindo
	for i in (3 if leve else 8):
		var lado := -1.0 if i % 2 == 0 else 1.0
		var pos := Vector3(lado * rnd.randf_range(1.8, 6.0), 0.1, rnd.randf_range(-18.0, 1.0))
		var b := _particulas(T, pos, "bolha", 10, 4.0, 0.16)
		b.direction = Vector3.UP
		b.spread = 12.0
		b.gravity = Vector3(0, 0.25, 0)
		b.initial_velocity_min = 0.5
		b.initial_velocity_max = 0.9
		b.scale_amount_min = 0.4
		b.scale_amount_max = 1.4
		b.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		b.emission_sphere_radius = 0.25
		b.color = Color(0.85, 1.0, 1.0, 0.85)


# ================================================================ SELVA DOS DINOS
func _dinos() -> void:
	var T := "dinos"
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 606
	# vulcão fumegando lá no fundo
	_obj(T, "vulcao", Vector3(5.5, -0.4, -48.0), 0.3, 1.9)
	_obj(T, "vulcao", Vector3(-16.0, -0.4, -40.0), -0.5, 1.1)
	var fum := _particulas(T, Vector3(5.5, 9.3, -48.0), "fumaca", 8 if leve else 14, 5.0, 2.4)
	fum.direction = Vector3(0.25, 1, 0)
	fum.spread = 18.0
	fum.gravity = Vector3(0.15, 0.15, 0)
	fum.initial_velocity_min = 0.8
	fum.initial_velocity_max = 1.3
	fum.scale_amount_min = 0.8
	fum.scale_amount_max = 1.6
	var cf := Curve.new()
	cf.add_point(Vector2(0, 0.4))
	cf.add_point(Vector2(1, 1.6))
	fum.scale_amount_curve = cf
	var gf := Gradient.new()
	gf.set_color(0, Color(0.95, 0.9, 0.95, 0.85))
	gf.set_color(1, Color(0.85, 0.85, 0.95, 0.0))
	fum.color_ramp = gf
	# palmeiras no lugar das torres
	_torres(T, "palmeira", 0.85, 0.0)
	# dino pescoçudo espiando atrás dos pinos + outro lá longe
	var dino := _obj(T, "dino", Vector3(3.7, -0.02, Mundo.Z_FUNDO - 0.9), -0.55, 1.0, 0.004)
	_animar(T, {"tipo": "respirar", "no": dino, "fase": 0.0, "giro": dino.rotation.y})
	var dino2 := _obj(T, "dino", Vector3(-8.5, _chao(-8.5, -25.0) - 0.05, -25.0), 0.7, 1.5)
	_animar(T, {"tipo": "respirar", "no": dino2, "fase": 1.7, "giro": dino2.rotation.y})
	# pterossauros voando em círculos
	for i in _q(3):
		var p := _obj(T, "ptero", Vector3.ZERO, 0.0, rnd.randf_range(0.9, 1.3), 0.003)
		_animar(T, {"tipo": "voo", "no": p, "centro": Vector3(rnd.randf_range(-3.0, 3.0), rnd.randf_range(6.0, 8.5), rnd.randf_range(-22.0, -9.0)),
			"raio": rnd.randf_range(4.0, 7.0), "vel": rnd.randf_range(0.25, 0.4) * (1.0 if i % 2 == 0 else -1.0), "fase": rnd.randf() * TAU})
	_espalhar(T, ["palmeira", "samambaia", "pedra", "flor_gigante", "samambaia", "palmeira", "ovo_dino", "pedra"], _q(44), 2027,
		{"palmeira": 1.0, "samambaia": 1.4, "pedra": 1.3, "flor_gigante": 1.3, "ovo_dino": 1.2})
	_destaques(T, [["samambaia", 1.0, 0.004], ["flor_gigante", 1.0, 0.004], ["ovo_dino", 1.0, 0.004], ["flor_gigante", 0.9, 0.004],
		["samambaia", 1.2], ["pedra", 1.0], ["ovo_dino", 1.0], ["samambaia", 1.1]])
	_nuvens(T, 10, 88)


# ================================================================ animação
func _process(delta: float) -> void:
	if atual == "":
		return
	_t = fposmod(_t + delta, 3600.0)
	for item in _anim[atual]:
		match item["tipo"]:
			"girar":
				(item["no"] as Node3D).rotate_y(float(item["vel"]) * delta)
			"nuvem":
				var no: Node3D = item["no"]
				no.position.x += float(item["vel"]) * delta
				if no.position.x > 30.0:
					no.position.x = -30.0
			"boiar":
				var no: Node3D = item["no"]
				var f: float = item["fase"]
				var v: float = item["vel"]
				var amp: Vector3 = item["amp"]
				no.position = (item["base"] as Vector3) + Vector3(sin(_t * 0.5 * v + f) * amp.x, sin(_t * 0.9 * v + f * 2.0) * amp.y, 0)
				if item.has("balanco"):
					no.rotation.z = sin(_t * 0.7 * v + f) * float(item["balanco"])
				if item.has("girar"):
					no.rotation.y += float(item["girar"]) * delta
				if item.has("vira"):
					no.rotation.y = float(item["olhar"]) + sin(_t * 0.6 * v + f) * float(item["vira"])
			"girar_proprio":
				(item["no"] as Node3D).rotate_object_local(item["eixo"], float(item["vel"]) * delta)
			"passeio":
				# uma volta deitada e achatada (x larga, z curta) com um sobe e
				# desce em "8"; o disco gira no próprio eixo e inclina para o
				# lado da curva
				var no: Node3D = item["no"]
				var a: float = _t * float(item["vel"])
				var r: Vector3 = item["raio"]
				no.position = (item["centro"] as Vector3) + Vector3(sin(a) * r.x, sin(2.0 * a) * r.y, cos(a) * r.z)
				item["ang"] = fposmod(float(item["ang"]) + float(item["girar"]) * delta, TAU)
				no.basis = Basis(Vector3(0, 0, 1), -cos(a) * 0.2) * Basis(Vector3.UP, float(item["ang"]))
			"roda":
				var roda: Node3D = item["roda"]
				roda.rotation.z += float(item["vel"]) * delta
				var cab: Array = item["cabines"]
				for i in cab.size():
					var a: float = roda.rotation.z + TAU * i / cab.size()
					(cab[i] as Node3D).position = Vector3(cos(a), sin(a), 0) * float(item["raio"])
					(cab[i] as Node3D).rotation.z = sin(_t * 1.3 + i) * 0.06
			"orbita":
				var no: Node3D = item["no"]
				var a: float = _t * float(item["vel"]) + float(item["fase"])
				var r: Vector2 = item["raio"]
				no.position = (item["centro"] as Vector3) + Vector3(cos(a) * r.x, sin(_t * 1.1) * float(item["sobe"]), sin(a) * r.y)
				no.rotation.y += float(item["girar"]) * delta
				no.rotation.z = sin(_t * 0.9) * 0.08
			"alga":
				var no: Node3D = item["no"]
				var f: float = item["fase"]
				var b: Vector3 = item["base"]
				no.rotation = b + Vector3(sin(_t * 0.8 + f) * 0.07, 0, sin(_t * 1.1 + f * 1.7) * 0.09)
			"peixe":
				var no: Node3D = item["no"]
				var v: float = item["vel"]
				var a: float = _t * v - float(item["fase"]) * signf(v)
				var r: Vector2 = item["raio"]
				var c: Vector3 = item["centro"]
				no.position = c + Vector3(cos(a) * r.x, sin(_t * 1.7 + float(item["nado"])) * 0.12, sin(a) * r.y)
				# olha para onde está nadando (+Z do modelo) e rebola o rabinho
				var dir := Vector3(-sin(a) * r.x, 0, cos(a) * r.y) * signf(v)
				no.rotation.y = atan2(dir.x, dir.z) + sin(_t * 9.0 + float(item["nado"])) * 0.12
			"agua_viva":
				var no: Node3D = item["no"]
				var f: float = item["fase"]
				var v: float = item["vel"]
				var pulso := sin(_t * 2.2 * v + f)
				no.position = (item["base"] as Vector3) + Vector3(0, sin(_t * 0.6 * v + f) * 0.5, 0)
				no.scale = Vector3(1.0 + pulso * 0.06, 1.0 - pulso * 0.08, 1.0 + pulso * 0.06) * _escala_base(item)
			"atravessar":
				var no: Node3D = item["no"]
				no.position.x += float(item["vel"]) * delta
				var lim: float = item["limite"]
				if no.position.x > lim:
					no.position.x = -lim
				elif no.position.x < -lim:
					no.position.x = lim
				no.position.y += sin(_t * 0.8) * 0.003
			"respirar":
				var no: Node3D = item["no"]
				var f: float = item["fase"]
				no.rotation.y = float(item["giro"]) + sin(_t * 0.35 + f) * 0.12
				no.rotation.z = sin(_t * 0.9 + f) * 0.025
			"voo":
				var no: Node3D = item["no"]
				var v: float = item["vel"]
				var a: float = _t * v + float(item["fase"])
				var r: float = item["raio"]
				no.position = (item["centro"] as Vector3) + Vector3(cos(a) * r, sin(_t * 1.4 + float(item["fase"])) * 0.4, sin(a) * r)
				var dir := Vector3(-sin(a), 0, cos(a)) * signf(v)
				no.rotation = Vector3(0, atan2(dir.x, dir.z), -signf(v) * 0.35 + sin(_t * 3.0) * 0.05)


func _escala_base(item: Dictionary) -> float:
	if not item.has("escala"):
		item["escala"] = (item["no"] as Node3D).scale.x
	return float(item["escala"])
