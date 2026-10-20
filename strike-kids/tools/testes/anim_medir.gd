extends Node

## MEDIDOR DE SUAVIDADE DOS BICHINHOS (sem tela).
##   godot --headless --path . --fixed-fps 60 res://tools/testes/anim_medir.tscn [-- --fps=30] [--detalhe=7.0,7.6]
## (--detalhe imprime quadro a quadro o Bob entre esses instantes)
## O Bob e a Mia fazem a sequência de uma partida (pronto -> arremesso ->
## assistindo, olhando a bola -> comemoração/feliz/triste/quase -> parado,
## torcida, dança, aceno, escolha, vitória, festa) e, a cada quadro, mede:
##   escala   quanto o corpo encolhe/estica (deveria ser 0)
##   tremor   o "chacoalho": o que sobra do movimento depois de tirar a
##            parte lisa (parábola em 0,15 s) - corpo, cabeça, mãos e pés (mm)
##   pulo_pe  o maior salto de um pé de um quadro para o outro, além do
##            movimento liso dele (mm)
##   cabeca   a maior virada da cabeça de um quadro para o outro (graus)

const SEQUENCIA := [
	# [tempo, clipe, mistura, reiniciar, olhar a bola?]
	[0.0, "parado", 0.3, true, false],
	[2.0, "pronto", 0.15, true, false],
	[3.5, "arremesso", 0.12, true, false],
	[4.5, "assistindo", 0.25, false, true],
	[7.0, "comemora_strike", 0.2, true, false],
	[10.4, "parado", 0.35, false, false],
	[12.0, "feliz", 0.2, true, false],
	[14.5, "triste", 0.2, true, false],
	[17.0, "quase", 0.2, true, false],
	[19.0, "torcida", 0.2, true, true],
	[22.0, "danca_curta", 0.35, true, false],
	[28.0, "acenar_uma", 0.35, true, false],
	[31.0, "olhar_volta", 0.35, true, false],
	[34.5, "escolhido", 0.15, true, false],
	[36.5, "vitoria", 0.2, true, false],
	[40.0, "parado", 0.3, true, false],
]
const FIM := 42.0

var bichos: Array[Personagem] = []
var t := 0.0
var passo := 0
var dt := 1.0 / 60.0
var dados := {}          # nome -> {canal -> Array[Vector3]}, + "escala", "clipe"
var bola := Vector3.ZERO
var bola_t := -1.0
var detalhe := Vector2(-1, -1)   # --detalhe=7.0,7.6: imprime quadro a quadro


func _ready() -> void:
	process_priority = 100   # mede depois que os bichinhos se mexeram
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fps="):
			dt = 1.0 / float(a.substr(6))
		if a.begins_with("--detalhe="):
			var x := a.substr(10).split(",")
			detalhe = Vector2(float(x[0]), float(x[1]))
	Engine.max_fps = 0
	var raiz := Node3D.new()
	add_child(raiz)
	var i := 0
	for nome in ["bob", "mia"]:
		var p := Personagem.new()
		raiz.add_child(p)
		p.montar(nome)
		p.set_process(false)    # quem avança o tempo é este medidor (passo fixo)
		p.posicionar(Vector3(-0.6 + i * 1.2, 0, 1.6), 180)
		bichos.append(p)
		dados[nome] = {"corpo": [], "cabeca": [], "mao_e": [], "mao_d": [], "pe_e": [], "pe_d": [], "olhar": [], "escala": [], "clipe": []}
		i += 1


func _process(_d: float) -> void:
	# passo fixo (o mesmo em qualquer máquina)
	while passo < SEQUENCIA.size() and t >= float(SEQUENCIA[passo][0]):
		var s: Array = SEQUENCIA[passo]
		for p in bichos:
			p.tocar(str(s[1]), float(s[2]), bool(s[3]))
			p.olhar_alvo = null
		if bool(s[4]):
			bola_t = 0.0
		else:
			bola_t = -1.0
		passo += 1
	if bola_t >= 0.0:
		# a bola sai da mão e rola pela pista (6 m/s), de um lado para o outro
		bola_t += dt
		for p in bichos:
			var ini := p.global_position + Vector3(0.1, 0.2, -0.4)
			bola = ini + Vector3(sin(bola_t * 1.3) * 0.4, -0.1, -6.0 * bola_t)
			p.olhar_alvo = bola
	for p in bichos:
		p._process(dt)
		var d: Dictionary = dados[p.nome_modelo]
		d["corpo"].append((p.juntas["corpo"] as Node3D).global_position)
		d["cabeca"].append((p.juntas["cabeca"] as Node3D).global_transform * Vector3(0, 0.25, 0.1))
		d["mao_e"].append((p.juntas["antebraco_e"] as Node3D).global_transform * Vector3(0, -0.16, 0))
		d["mao_d"].append((p.juntas["antebraco_d"] as Node3D).global_transform * Vector3(0, -0.16, 0))
		d["pe_e"].append((p.juntas["pe_e"] as Node3D).global_position)
		d["pe_d"].append((p.juntas["pe_d"] as Node3D).global_position)
		d["olhar"].append(-(p.juntas["cabeca"] as Node3D).global_transform.basis.z.normalized())
		d["escala"].append(p.modelo.scale)
		d["clipe"].append(p.animacao())
		if t >= detalhe.x and t <= detalhe.y and p.nome_modelo == "bob":
			var po: Dictionary = p._ultima_pose
			var n: int = d["olhar"].size()
			var ang := 0.0 if n < 2 else rad_to_deg((d["olhar"][n - 1] as Vector3).angle_to(d["olhar"][n - 2]))
			print("%6.3f %-16s alt=%6.3f voo=%5.3f giro=%6.1f corpo=%s cab=%s ang=%5.1f maoE=%s peE=%s w=%.2f/%.2f desc=%.3f braE=%s" % [t, p.animacao(),
				float(po.get("altura", 0.0)), float(po.get("voo", 0.0)), float(po.get("giro", 0.0)),
				str((p.juntas["corpo"] as Node3D).global_position.snapped(Vector3.ONE * 0.001)),
				str(po.get("cabeca", Vector3.ZERO).snapped(Vector3.ONE * 0.1)), ang,
				str((d["mao_e"][n - 1] as Vector3).snapped(Vector3.ONE * 0.001)),
				str((d["pe_e"][n - 1] as Vector3).snapped(Vector3.ONE * 0.001)),
				float(p._pes["e"].get("peso_lin", 0.0)), float(p._pes["d"].get("peso_lin", 0.0)), p._descer,
				str(po.get("braco_e", Vector3.ZERO).snapped(Vector3.ONE * 0.1))])
	t += dt
	if t >= FIM:
		_relatorio()
		get_tree().quit()


## Ajuste local de parábola (Savitzky-Golay, janela 2m+1): o movimento
## liso (mesmo rápido) fica igual; o que sobra é tremor/salto.
func _liso(v: Array, i: int, m: int) -> Vector3:
	var s := Vector3.ZERO
	var den := float((2 * m - 1) * (2 * m + 1) * (2 * m + 3))
	for k in range(-m, m + 1):
		s += (v[i + k] as Vector3) * (float(3 * (3 * m * m + 3 * m - 1) - 15 * k * k) / den)
	return s


func _suave(v: Array, i: int, r: int) -> Vector3:
	return _liso(v, i, r)


func _relatorio() -> void:
	var r := int(round(0.075 / dt))   # janela de 0,15 s
	print("MEDICAO  dt=%.4f  (%.0f quadros/s)" % [dt, 1.0 / dt])
	var total := {}
	for nome in dados:
		var d: Dictionary = dados[nome]
		var por_clipe := {}
		var n: int = d["corpo"].size()
		for i in range(r, n - r):
			var c: String = d["clipe"][i]
			if not por_clipe.has(c):
				por_clipe[c] = {"escala": 0.0, "tremor": 0.0, "tremor_onde": "", "tremor_t": 0.0, "pulo_pe": 0.0, "pulo_t": 0.0, "cabeca": 0.0, "cabeca_t": 0.0}
			var m: Dictionary = por_clipe[c]
			var e: Vector3 = d["escala"][i]
			m["escala"] = maxf(m["escala"], maxf(absf(e.y - 1.0), absf(e.x - 1.0)) * 100.0)
			for canal in ["corpo", "cabeca", "mao_e", "mao_d", "pe_e", "pe_d"]:
				var v: Array = d[canal]
				var tr: float = (v[i] - _suave(v, i, r)).length() * 1000.0
				if tr > m["tremor"]:
					m["tremor"] = tr
					m["tremor_onde"] = canal
					m["tremor_t"] = i * dt
			for canal in ["pe_e", "pe_d"]:
				var v: Array = d[canal]
				var dp: float = (v[i] - v[i - 1]).length() * 1000.0
				# o que conta é o salto além do movimento normal do pé
				var esperado: float = (_suave(v, i, r) - _suave(v, i - 1, r)).length() * 1000.0
				if dp - esperado > m["pulo_pe"]:
					m["pulo_pe"] = dp - esperado
					m["pulo_t"] = i * dt
			var o: Array = d["olhar"]
			var ang := rad_to_deg((o[i] as Vector3).angle_to(o[i - 1]))
			if ang > m["cabeca"]:
				m["cabeca"] = ang
				m["cabeca_t"] = i * dt
		print("--- %s" % nome)
		print("  %-16s %8s %10s %-8s %6s %8s %6s %8s %6s" % ["clipe", "escala%", "tremor_mm", "onde", "em_s", "pulo_pe", "em_s", "cabeca", "em_s"])
		for c in por_clipe:
			var m: Dictionary = por_clipe[c]
			print("  %-16s %8.2f %10.1f %-8s %6.2f %8.1f %6.2f %8.2f %6.2f" % [c, m["escala"], m["tremor"], m["tremor_onde"], m["tremor_t"], m["pulo_pe"], m["pulo_t"], m["cabeca"], m["cabeca_t"]])
			for k in ["escala", "tremor", "pulo_pe", "cabeca"]:
				total[k] = maxf(float(total.get(k, 0.0)), float(m[k]))
	print("PIOR  escala=%.2f%%  tremor=%.1f mm  pulo_pe=%.1f mm  cabeca=%.2f graus/quadro" % [total["escala"], total["tremor"], total["pulo_pe"], total["cabeca"]])
