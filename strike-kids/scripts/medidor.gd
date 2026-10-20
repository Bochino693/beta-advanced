class_name Medidor
extends Control

## MEDIDOR DE DESEMPENHO — para saber, NA PRÓPRIA MÁQUINA (TV Box ou PC),
## se o jogo está rodando liso.
##
## 1) PAINEL NA TELA (tecla F3 no PC, ou menu do operador > "Mostrar
##    desempenho na tela"): quadros por segundo (QPS), tempo de cada quadro,
##    quanto a placa de vídeo leva para desenhar o 3D e a tela, número de
##    desenhos e triângulos, memória e a resolução do 3D. Verde = liso.
## 2) TESTE DE DESEMPENHO (menu do operador): 20 segundos passando pelas
##    vistas mais pesadas do jogo; no fim mostra a média, o pior momento e
##    a QUALIDADE RECOMENDADA — e, na qualidade automática, já passa a usar
##    ela. O resultado fica gravado em user://desempenho.txt.
##
## Como ler: 60 QPS = perfeito; 50+ = liso; 30-50 = joga, mas dá para ver
## travadinhas; menos de 30 = travado (baixe a qualidade).

signal teste_terminou(resultado: Dictionary)

const ATUALIZA := 0.5

var principal: Node
var _painel: PanelContainer
var _texto: Label
var _t := 0.0
var _quadros := 0
var _t0 := 0
var _pior := 0.0
var _ultimo := 0
var _medindo_gpu := false


func _init(p: Node) -> void:
	principal = p


## Fica por cima de tudo, dentro da interface (gira junto com a tela).
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Tela.cobrir(self)
	Tela.mudou.connect(func(_t): Tela.cobrir(self))
	_painel = PanelContainer.new()
	var caixa := StyleBoxFlat.new()
	caixa.bg_color = Color(0.0, 0.03, 0.1, 0.78)
	caixa.set_corner_radius_all(10)
	caixa.content_margin_left = 14
	caixa.content_margin_right = 14
	caixa.content_margin_top = 8
	caixa.content_margin_bottom = 8
	_painel.add_theme_stylebox_override("panel", caixa)
	_painel.position = Vector2(12, 12)
	_painel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_painel)
	_texto = Label.new()
	var ls := LabelSettings.new()
	ls.font = Materiais.fonte("fredoka_600")
	ls.font_size = 28
	ls.font_color = Color.WHITE
	ls.outline_size = 4
	ls.outline_color = Color(0.0, 0.03, 0.1)
	_texto.label_settings = ls
	_painel.add_child(_texto)
	mostrar(bool(Ajustes.valor("video", "medidor")))


func mostrar(sim: bool) -> void:
	_painel.visible = sim
	_medir_gpu(sim)
	set_process(sim)
	_t0 = Time.get_ticks_usec()
	_ultimo = _t0
	_quadros = 0
	_pior = 0.0


func alternar() -> void:
	mostrar(not _painel.visible)


func _medir_gpu(sim: bool) -> void:
	if sim == _medindo_gpu:
		return
	_medindo_gpu = sim
	var vp: SubViewport = principal.get("vp")
	if vp:
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), sim)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), sim)


func _process(_d: float) -> void:
	var agora := Time.get_ticks_usec()
	_pior = maxf(_pior, float(agora - _ultimo) / 1000.0)
	_ultimo = agora
	_quadros += 1
	if agora - _t0 < int(ATUALIZA * 1000000.0):
		return
	var ms := float(agora - _t0) / 1000.0 / maxf(_quadros, 1)
	var qps := 1000.0 / maxf(ms, 0.001)
	var vp: SubViewport = principal.get("vp")
	var gpu3d := RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()) if vp else 0.0
	var gputela := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	var cor := Color("#7CFF7C") if qps >= 50.0 else (Color("#FFE14D") if qps >= 30.0 else Color("#FF6B6B"))
	_texto.label_settings.font_color = cor
	# o tempo da placa de vídeo só é medido no PC (OpenGL); no Android
	# (TV Box) o Godot não recebe essa medida — vale o QPS e os ms
	var placa := "placa: 3D %.1f ms, tela %.1f ms" % [gpu3d, gputela] if gpu3d + gputela > 0.01 else "placa: (o Android não informa)"
	_texto.text = "%d QPS   (%.1f ms, pior %.0f ms)\nCPU %.1f ms · %s\n%d desenhos · %d mil triângulos\n3D %dx%d (%d%%) · %s · memória %d MB · vídeo %d MB" % [
		int(round(qps)), ms, _pior,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, placa,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
		vp.size.x if vp else 0, vp.size.y if vp else 0, int(round(float(principal.get("_fator")) * 100.0)),
		_nome(str(principal.get("_qualidade"))),
		int(OS.get_static_memory_usage() / 1048576), int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576)]
	_t0 = agora
	_quadros = 0
	_pior = 0.0


# ================================================================ teste
## Os planos mais pesados do jogo (os mesmos da bancada de testes).
const PLANOS := [
	["a pista de frente", Vector3(0.0, 1.05, 2.2), Vector3(0.0, 0.18, -9.9), 34.0, 40.0],
	["os pinos e o portal", Vector3(0.0, 0.9, -6.5), Vector3(0.0, 0.7, -12.5), 44.0, 40.0],
	["os bichinhos", Vector3(0.0, 1.35, 6.6), Vector3(0.0, 1.0, 2.3), 40.0, 44.0],
	["o cenário de cima", Vector3(-2.6, 4.6, -9.5), Vector3(0.0, 2.2, -16.7), 50.0, 40.0],
]
const SEG_POR_PLANO := 4.5


## Roda o teste (o jogo precisa estar na atração). Mostra o resultado na
## tela, grava em user://desempenho.txt e devolve o resumo.
func testar() -> Dictionary:
	var antes := _painel.visible
	mostrar(true)
	var aviso := _cartaz("TESTE DE DESEMPENHO\nmedindo... não mexa na máquina")
	var tempos: Array[float] = []
	var por_plano := {}
	var temas: Array = Temas.ORDEM
	for i in PLANOS.size():
		var p: Array = PLANOS[i]
		principal.mundo.aplicar_tema(temas[i % temas.size()])
		principal.cam.corte(p[1], p[2], p[3], p[4])
		principal._demo_t = -1000.0
		for k in 20:
			await get_tree().process_frame
		if principal.estado != principal.E.TESTE:
			return _interrompido(aviso, antes)
		var ini := Time.get_ticks_usec()
		var ult := ini
		var meus: Array[float] = []
		while Time.get_ticks_usec() - ini < int(SEG_POR_PLANO * 1000000.0):
			await get_tree().process_frame
			if principal.estado != principal.E.TESTE:
				return _interrompido(aviso, antes)
			principal._demo_t = -1000.0
			var agora := Time.get_ticks_usec()
			meus.append(float(agora - ult) / 1000.0)
			ult = agora
		tempos.append_array(meus)
		por_plano[p[0]] = 1000.0 / _media(meus)
		aviso.text = "TESTE DE DESEMPENHO\nmedindo... %d%%" % int(100.0 * (i + 1) / PLANOS.size())
	tempos.sort()
	var media_qps := 1000.0 / _media(tempos)
	var p99 := tempos[int(tempos.size() * 0.99)] if not tempos.is_empty() else 0.0
	var pior_plano := ""
	var pior_qps := 1e9
	for k in por_plano:
		if por_plano[k] < pior_qps:
			pior_qps = por_plano[k]
			pior_plano = k
	var qual: String = str(principal.get("_qualidade"))
	var recomendada := qual
	var veredito := ""
	if media_qps >= 55.0 and pior_qps >= 45.0:
		veredito = "ÓTIMO: roda liso"
		if qual == "baixa":
			recomendada = "media"
		elif qual == "media" and media_qps >= 58.0:
			recomendada = "alta"
	elif media_qps >= 45.0:
		veredito = "BOM: roda liso quase sempre"
	elif media_qps >= 30.0:
		veredito = "MÉDIO: dá para jogar, mas com travadinhas"
		recomendada = "baixa" if qual == "media" else ("media" if qual == "alta" else "baixa")
	else:
		veredito = "FRACO: travado nesta qualidade"
		recomendada = "baixa"
	var d := Time.get_datetime_dict_from_system()
	var data := "%02d/%02d/%04d %02d:%02d" % [d["day"], d["month"], d["year"], d["hour"], d["minute"]]
	var vs: Vector2i = principal.vp.size
	var r := {"media_qps": media_qps, "pior_quadro_ms": p99, "pior_plano": pior_plano, "pior_plano_qps": pior_qps,
		"qualidade": qual, "recomendada": recomendada, "veredito": veredito, "por_plano": por_plano,
		"resolucao_3d": "%dx%d" % [vs.x, vs.y], "tela": "%dx%d" % [get_window().size.x, get_window().size.y], "data": data}
	var linhas := "TESTE DE DESEMPENHO\n%s\n\n%s\n\nMédia: %d quadros por segundo (QPS)\nPior momento: %.0f ms (%s: %d QPS)\nQualidade usada: %s (imagem 3D %s)\nRECOMENDADA: %s\n\n" % [
		data, veredito, int(round(media_qps)), p99, pior_plano, int(round(pior_qps)), _nome(qual), r["resolucao_3d"],
		_nome(recomendada)]
	for k in por_plano:
		linhas += "  %s: %d QPS\n" % [k, int(round(por_plano[k]))]
	var f := FileAccess.open("user://desempenho.txt", FileAccess.WRITE)
	if f:
		f.store_string(linhas)
	print(linhas)
	# na qualidade automática, já fica valendo a recomendada
	if str(Ajustes.valor("video", "qualidade")) == "auto":
		Ajustes.definir("video", "qualidade_auto", recomendada)
	aviso.text = linhas + "\nAPERTE START"
	mostrar(antes)
	r["cartaz"] = aviso
	teste_terminou.emit(r)
	return r


## O menu do operador abriu no meio do teste: some com o cartaz, sem resultado.
func _interrompido(aviso: Label, antes: bool) -> Dictionary:
	(aviso.get_meta("fundo") as Node).queue_free()
	mostrar(antes)
	return {}


func _nome(q: String) -> String:
	return {"alta": "ALTA", "media": "MÉDIA", "baixa": "BAIXA"}.get(q, q.to_upper())


func _media(v: Array[float]) -> float:
	if v.is_empty():
		return 1.0
	var s := 0.0
	for x in v:
		s += x
	return s / v.size()


func _cartaz(texto: String) -> Label:
	var fundo := ColorRect.new()
	fundo.color = Color(0.0, 0.04, 0.12, 0.82)
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fundo)
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = Materiais.fonte("fredoka_700")
	ls.font_size = 34
	ls.font_color = Color.WHITE
	ls.outline_size = 6
	ls.outline_color = Color("#0B1F45")
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = texto
	fundo.add_child(l)
	var t := Tela.tamanho()
	fundo.size = t
	l.size = t * Vector2(0.9, 0.9)
	l.position = t * 0.05
	l.set_meta("fundo", fundo)
	return l
