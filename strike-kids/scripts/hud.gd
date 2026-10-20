class_name Hud
extends Control

## TUDO O QUE É 2D POR CIMA DO 3D: placar, mapa dos pinos, o convite
## "ROLE A BOLA!", letreiros (STRIKE!...), faixa "VEZ DE...", nome do
## cenário, modo replay e as telas de atração, escolha, fim e inatividade.
## Não há setinhas nem alvos na tela: a mira é sempre o STRIKE.
##
## Responsivo: tudo é reposicionado em `layout()` conforme a tela (em pé ou
## deitada). Unidade "u" = lado menor / 1080.
##
## Visual: placas com volume (Painel3D: degradê, verniz, lateral e sombra,
## como os objetos 3D) e contorno azul-marinho. A marca Lazer & Sport só
## aparece na abertura (e, no 3D, sutil em cada cenário: ver Mundo).

const COR_BOB := Color("#169BD5")
const COR_MIA := Color("#FF7A21")
const DESTAQUE := Color("#FFC21A")
const ESCALA_ARTE := 1.6       # letreiros gerados em 1,6x (nítidos em 4K)
const MARINHO := Color("#0B1F45")   # contornos e textos escuros
const AZUL := Color("#1A4FA8")      # placas azuis
const CREME := Color("#FFF6A8")
const ZONAS := ["Z", "X", "C", "V", "B"]
const MARCA := "res://ui/marca/"
## posição das peças dentro da logo inteira (tools/arte/gerar_marca.py)
const CENTRO_ALVO := Vector2(0.4752, 0.2780)
const CENTRO_PLACA := Vector2(0.5, 0.7792)
const PROPORCAO_LOGO := 1698.0 / 2560.0

var fonte: FontFile
var fonte_titulo: FontFile
var u := 1.0
var retrato := true

var tela3d: TextureRect
var _flash: ColorRect
var _tarja_cima: ColorRect
var _tarja_baixo: ColorRect
var _replay: TextureRect
var _replay_ponto: Panel

var _cartoes: Array = []          # [{painel, avatar, nome, pontos, rodadas(HBox), cor, valor_mostrado}]
var _info: Label
var _bolas_box: HBoxContainer
var _mapa: Painel3D
var _mapa_pontos := {}
var _toque: Control
var _aviso: Label
var _aviso_sub: Label
var _cenario: TextureRect
var _sequencia: Label
var _centro: Control
var _faixa: Painel3D
var _faixa_texto: Label
var _faixa_avatar: TextureRect
var _atracao: Control
var _logo: TextureRect
var _aperte: Label
var _aperte_botao: Painel3D
var _recorde: Label
var _recorde_placa: Painel3D
var _creditos: Label
# quantos vão jogar
var _jog: Control
var _jog_painel: Painel3D
var _jog_titulo: Label
var _jog_cartoes: Array[Painel3D] = []
var _jog_dica: Label
var _jog_trilho: Painel3D
var _jog_barra: Painel3D
var _jog_n := 1
# escolha do personagem
var _selecao: Control
var _sel_titulo: Painel3D
var _sel_placas: Array[Painel3D] = []
var _sel_nomes: Array[Label] = []
var _sel_dica: Painel3D
var _sel_texto: Label
var _sel_destaque := 0
var _sel_sensores: Control
var _fim: Control
var _fim_vez := 0          # cada fim de jogo mostrado (os letreiros atrasados conferem)
var _inativo: Painel3D
var _inativo_texto: Label
var _aviso_android: Painel3D
var _aviso_android_texto: Label
var _tempo := 0.0
var _convite := false
var _retratos := {}
# fotos das crianças (câmera da máquina)
var _foto_tela: Control
var _foto_fundo: ColorRect
var _foto_titulo: Label
var _foto_sub: Label
var _foto_circulo: TextureRect
var _foto_selo: TextureRect
var _foto_numero: Label
var _foto_destaque: TextureRect
var _rec_foto: TextureRect
var _shader_foto: Shader
# marca Lazer & Sport
var _marca_tela: Control
var _marca_fundo: TextureRect
var _marca_games: TextureRect
var _marca_veu: TextureRect
var _marca_alvo: TextureRect
var _marca_placa: TextureRect
var _marca_texto: Label


func montar(textura_3d: Texture2D) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fonte = Materiais.fonte("fredoka_700")
	fonte_titulo = Materiais.fonte("titan_one")
	for p in ["bob", "mia"]:
		_retratos[p] = Materiais.textura("retrato_" + p)
	tela3d = TextureRect.new()
	tela3d.texture = textura_3d
	tela3d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tela3d.stretch_mode = TextureRect.STRETCH_SCALE
	tela3d.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # imagem 3D (sem mipmaps)
	var m3d := ShaderMaterial.new()
	m3d.shader = load("res://shaders/tela3d.gdshader")
	tela3d.material = m3d
	tela3d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tela3d)
	_montar_placar()
	_montar_mapa()
	_montar_toque()
	_centro = Control.new()
	_centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_centro)
	_montar_faixa()
	_montar_replay()
	_montar_atracao()
	_montar_jogadores()
	_montar_selecao()
	_fim = Control.new()
	_fim.visible = false
	_fim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fim)
	_montar_inatividade()
	_montar_aviso_android()
	_montar_fotos()
	_montar_etapas()
	_montar_marca()
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# escondido quando transparente: um retângulo da tela inteira desenhado
	# à toa a cada quadro custa caro na TV Box
	_flash.visible = false
	add_child(_flash)
	layout()


# ================================================================ peças
func rotulo(texto: String, tam: float, cor := Color.WHITE, contorno := 0.0, cor_contorno := MARINHO, f: Font = null) -> Label:
	var l := Label.new()
	l.text = texto
	var ls := LabelSettings.new()
	ls.font = f if f != null else fonte
	ls.font_size = int(tam)
	ls.font_color = cor
	if contorno > 0.0:
		ls.outline_size = int(contorno)
		ls.outline_color = cor_contorno
	ls.shadow_size = int(max(1.0, tam * 0.06))
	ls.shadow_color = Color(0.0, 0.05, 0.15, 0.45)
	ls.shadow_offset = Vector2(0, tam * 0.06)
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func caixa(cor: Color, raio := 28.0, borda := 0.0, cor_borda := Color.WHITE, sombra := 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = cor
	s.set_corner_radius_all(int(raio))
	if borda > 0.0:
		s.set_border_width_all(int(borda))
		s.border_color = cor_borda
	s.shadow_size = int(sombra)
	s.shadow_color = Color(0.0, 0.05, 0.15, 0.35)
	s.shadow_offset = Vector2(0, sombra * 0.4)
	s.anti_aliasing = true
	return s


func painel(cor: Color, raio := 28.0, borda := 0.0, cor_borda := Color.WHITE) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", caixa(cor, raio, borda, cor_borda))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _tamanho_rotulo(l: Label, tam: float) -> void:
	l.label_settings.font_size = int(tam)
	l.label_settings.shadow_size = int(max(1.0, tam * 0.06))
	l.label_settings.shadow_offset = Vector2(0, tam * 0.06)


## Diminui a letra até o texto caber na largura (nunca estoura a placa).
func _caber(l: Label, tam: float, largura: float) -> void:
	var ls := l.label_settings
	var t := tam
	while t > 12.0 and ls.font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(t)).x + ls.outline_size > largura:
		t *= 0.94
	ls.font_size = int(t)


# ================================================================ placar
func _montar_placar() -> void:
	for i in 2:
		var cor := COR_BOB if i == 0 else COR_MIA
		var p := Painel3D.new(cor, 34, 12, 6)
		add_child(p)
		var av := TextureRect.new()
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(av)
		var selo := TextureRect.new()
		selo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		selo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		selo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		selo.visible = false
		p.add_child(selo)
		var nome := rotulo("", 34, Color.WHITE, 8)
		nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		p.add_child(nome)
		var pts := rotulo("0", 64, Color("#FFF6A8"), 12, MARINHO, fonte_titulo)
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		p.add_child(pts)
		var rod := HBoxContainer.new()
		rod.alignment = BoxContainer.ALIGNMENT_BEGIN
		rod.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(rod)
		_cartoes.append({"painel": p, "avatar": av, "selo": selo, "nome": nome, "pontos": pts, "rodadas": rod, "cor": cor, "valor": 0.0, "alvo": 0})
	_info = rotulo("", 34, Color.WHITE, 9)
	add_child(_info)
	_bolas_box = HBoxContainer.new()
	_bolas_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_bolas_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bolas_box)
	mostrar_placar(false)


func mostrar_placar(sim: bool) -> void:
	for c in _cartoes:
		c["painel"].visible = sim and c.get("usado", false)
	_info.visible = sim
	_bolas_box.visible = sim
	if _mapa:
		_mapa.visible = sim


## jogadores: [{personagem}], placar: Placar
func configurar_placar(personagens: Array) -> void:
	for i in 2:
		var c: Dictionary = _cartoes[i]
		c["usado"] = i < personagens.size()
		if i < personagens.size():
			var p: String = personagens[i]
			c["nome"].text = p.to_upper()
			var cor := COR_BOB if p == "bob" else COR_MIA
			var ft: Texture2D = Fotos.foto("j%d" % i)
			c["foto"] = ft != null
			c["avatar"].texture = ft if ft != null else _retratos.get(p)
			c["avatar"].material = material_foto(Color.WHITE) if ft != null else null
			c["selo"].texture = _retratos.get(p)
			c["selo"].visible = ft != null
			c["cor"] = cor
			(c["painel"] as Painel3D).pintar(cor)
			c["valor"] = 0.0
			c["alvo"] = 0
			c["pontos"].text = "0"
	layout()


func atualizar_placar(placar: Placar) -> void:
	for i in placar.jogadores.size():
		var c: Dictionary = _cartoes[i]
		c["alvo"] = placar.total(i)
		var rod: HBoxContainer = c["rodadas"]
		for f in rod.get_children():
			f.queue_free()
		var j: Dictionary = placar.jogadores[i]
		for r in placar.rodadas:
			var bolas: Array = j["rodadas"][r]
			var soma := 0
			for b in bolas:
				soma += int(b)
			var cel := Panel.new()
			cel.custom_minimum_size = Vector2(46, 46) * u
			cel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var cor_cel := Color(1, 1, 1, 0.22)
			var txt := ""
			if bolas.size() > 0:
				cor_cel = Color(1, 1, 1, 0.95)
				txt = str(soma)
				if soma >= 10 and bolas.size() == 1:
					cor_cel = Color("#FFD43B")
					txt = ""
				elif soma >= 10:
					cor_cel = Color("#7FE7FF")
			var atual := (i == placar.jogador_atual and r == placar.rodada_atual)
			cel.add_theme_stylebox_override("panel", caixa(cor_cel, 23 * u, 4 * u if atual else 0.0, DESTAQUE, 0))
			if txt != "":
				var l := rotulo(txt, 26 * u, MARINHO)
				l.label_settings.shadow_size = 0
				l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				cel.add_child(l)
			elif cor_cel == Color("#FFD43B"):
				var e := TextureRect.new()
				e.texture = Materiais.textura("estrela_placar")
				e.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				e.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				e.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				e.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cel.add_child(e)
			rod.add_child(cel)
		var ativo := i == placar.jogador_atual
		var painel_c: Control = c["painel"]
		painel_c.modulate = Color(1, 1, 1, 1) if ativo or placar.jogadores.size() == 1 else Color(0.78, 0.78, 0.85, 0.9)
		painel_c.scale = Vector2.ONE * (1.0 if ativo else 0.94)
	_info.text = "RODADA %d de %d" % [placar.rodada_atual + 1, placar.rodadas]
	for b in _bolas_box.get_children():
		b.queue_free()
	for k in placar.tentativas:
		var bola := Panel.new()
		bola.custom_minimum_size = Vector2(34, 34) * u
		var usada := k < placar.bola_atual
		bola.add_theme_stylebox_override("panel", caixa(Color(1, 1, 1, 0.25) if usada else _cor_atual(placar), 17 * u, 3 * u, Color.WHITE, 4))
		bola.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bolas_box.add_child(bola)


func _cor_atual(placar: Placar) -> Color:
	return COR_BOB if placar.atual()["personagem"] == "bob" else COR_MIA


# ================================================================ mapa dos pinos
func _montar_mapa() -> void:
	_mapa = Painel3D.new(AZUL, 26, 8, 4)
	add_child(_mapa)
	for n in range(1, 11):
		var d := Panel.new()
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mapa.add_child(d)
		_mapa_pontos[n] = d
	mostrar_mapa([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	_mapa.visible = false


func mostrar_mapa(em_pe: Array) -> void:
	for n in _mapa_pontos:
		var d: Panel = _mapa_pontos[n]
		var de_pe := em_pe.has(n)
		d.add_theme_stylebox_override("panel", caixa(Color.WHITE if de_pe else Color(1, 1, 1, 0.12), 99, 3 if de_pe else 0, DESTAQUE, 0))


# ================================================================ convite e toque
## Sem luzes nem setas na tela. No PC/tablet dá para tocar na tela: a
## posição do toque (5 faixas, da esquerda para a direita) vale como o sensor.
func _montar_toque() -> void:
	_toque = Control.new()
	_toque.mouse_filter = Control.MOUSE_FILTER_STOP
	_toque.gui_input.connect(_ao_tocar)
	_toque.visible = false
	add_child(_toque)
	_aviso = rotulo("ROLE A BOLA!", 64, Color("#FFF6A8"), 16, MARINHO, fonte_titulo)
	add_child(_aviso)
	_aviso.visible = false
	_aviso_sub = rotulo("mire no STRIKE!", 40, Color.WHITE, 10, MARINHO)
	add_child(_aviso_sub)
	_aviso_sub.visible = false
	_cenario = TextureRect.new()
	_cenario.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cenario.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cenario.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cenario.visible = false
	add_child(_cenario)
	_sequencia = rotulo("", 40, Color("#FFF6A8"), 10, Color("#7A1E00"), fonte_titulo)
	_sequencia.visible = false
	add_child(_sequencia)


signal toque_sensor(zona: String)


func _ao_tocar(ev: InputEvent) -> void:
	var pos := Vector2(-1, -1)
	if ev is InputEventMouseButton and ev.pressed:
		pos = ev.position
	elif ev is InputEventScreenTouch and ev.pressed:
		pos = ev.position
	if pos.x < 0.0:
		return
	var i := clampi(int(pos.x / maxf(size.x, 1.0) * 5.0), 0, 4)
	toque_sensor.emit(ZONAS[i])


func convite(ligado: bool, texto := "ROLE A BOLA!") -> void:
	_convite = ligado
	_aviso.text = texto
	_aviso.visible = ligado
	_aviso_sub.visible = ligado
	_toque.visible = true


func mostrar_sensores(sim: bool) -> void:
	_toque.visible = sim
	if not sim:
		_aviso.visible = false
		_aviso_sub.visible = false


func sensor_acendeu(_zona: String) -> void:
	_convite = false
	_aviso.visible = false
	_aviso_sub.visible = false


## Nome do cenário (letreiro grande que entra girando e sai).
func anunciar_cenario(tema: String, dur := 2.2) -> void:
	var tex := Materiais.textura("cen_" + tema)
	if tex == null:
		return
	_cenario.texture = tex
	var T := size
	var w: float = minf(T.x * 0.86, 900.0 * u)
	var h: float = w * float(tex.get_height()) / float(tex.get_width())
	_cenario.size = Vector2(w, h)
	_cenario.position = Vector2((T.x - w) / 2, T.y * (0.3 if retrato else 0.24) - h / 2)
	_cenario.pivot_offset = _cenario.size / 2
	_cenario.visible = true
	_cenario.scale = Vector2.ZERO
	_cenario.rotation = -0.5
	_cenario.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_cenario, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_cenario, "rotation", 0.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(dur)
	tw.tween_property(_cenario, "scale", Vector2.ONE * 1.25, 0.3)
	tw.parallel().tween_property(_cenario, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): _cenario.visible = false)


## Sequência de strikes (aparece embaixo do placar do jogador).
func sequencia(n: int) -> void:
	_sequencia.visible = n >= 2
	if n >= 2:
		_sequencia.text = "%d STRIKES SEGUIDOS!" % n
		_pular(_sequencia)


# ================================================================ letreiros
## Letreiro grande no centro (STRIKE!, SPARE!...). sub: texto embaixo.
func letreiro(nome: String, sub := "", dur := 1.7, altura := 0.38) -> void:
	var tex := Materiais.textura(nome)
	if tex == null:
		return
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var T := size
	var larg: float = min(T.x * 0.9, tex.get_width() / ESCALA_ARTE * u * 0.95)
	var alt := larg * tex.get_height() / tex.get_width()
	tr.size = Vector2(larg, alt)
	tr.position = Vector2((T.x - larg) / 2, T.y * altura - alt / 2)
	tr.pivot_offset = tr.size / 2
	tr.scale = Vector2.ZERO
	tr.rotation = deg_to_rad(-12)
	_centro.add_child(tr)
	var tw := create_tween()
	tw.tween_property(tr, "scale", Vector2.ONE * 1.18, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(tr, "rotation", deg_to_rad(3), 0.22)
	tw.tween_property(tr, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(tr, "rotation", 0.0, 0.18)
	tw.tween_property(tr, "scale", Vector2.ONE * 1.05, dur * 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(tr, "position:y", tr.position.y - 120 * u, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(tr, "modulate:a", 0.0, 0.3)
	tw.tween_callback(tr.queue_free)
	_estrelas_2d(tr.position + tr.size / 2, 26)
	if sub != "":
		var l := rotulo(sub, 58 * u, Color.WHITE, 14 * u, MARINHO, fonte_titulo)
		l.size = Vector2(T.x, 90 * u)
		l.position = Vector2(0, tr.position.y + alt + 10 * u)
		l.pivot_offset = l.size / 2
		l.scale = Vector2.ZERO
		_centro.add_child(l)
		var t2 := create_tween()
		t2.tween_interval(0.18)
		t2.tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t2.tween_interval(dur * 0.55)
		t2.tween_property(l, "modulate:a", 0.0, 0.3)
		t2.tween_callback(l.queue_free)


## Texto grande simples (ex.: "7 PINOS!").
func texto_grande(texto: String, cor := Color("#FFF6A8"), dur := 1.4, altura := 0.38) -> void:
	var T := size
	var l := rotulo(texto, 110 * u, cor, 22 * u, MARINHO, fonte_titulo)
	l.size = Vector2(T.x, 160 * u)
	l.position = Vector2(0, T.y * altura - 80 * u)
	l.pivot_offset = l.size / 2
	l.scale = Vector2.ZERO
	_centro.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE * 1.12, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.15)
	tw.tween_interval(dur)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)


## "+120" voando até o placar do jogador.
func pontos_voando(pontos: int, jogador: int) -> void:
	if jogador >= _cartoes.size():
		return
	var c: Dictionary = _cartoes[jogador]
	var p: Control = c["painel"]
	var l := rotulo("+%d" % pontos, 84 * u, Color("#FFF6A8"), 18 * u, MARINHO, fonte_titulo)
	l.size = Vector2(400, 120) * u
	l.position = Vector2(size.x / 2 - 200 * u, size.y * 0.5)
	l.pivot_offset = l.size / 2
	_centro.add_child(l)
	var destino := p.position + p.size / 2 - l.size / 2
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE * 1.2, 0.15)
	tw.tween_interval(0.35)
	tw.tween_property(l, "position", destino, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(l, "scale", Vector2.ONE * 0.5, 0.55)
	tw.tween_callback(func():
		l.queue_free()
		_pular(p))


func _pular(no: Control) -> void:
	no.pivot_offset = no.size / 2
	var tw := create_tween()
	tw.tween_property(no, "scale", Vector2.ONE * 1.08, 0.08)
	tw.tween_property(no, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _estrelas_2d(centro: Vector2, n: int) -> void:
	var p := CPUParticles2D.new()
	p.texture = Materiais.textura("estrela")
	p.amount = n
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 1.0
	p.position = centro
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 60 * u
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 450 * u
	p.initial_velocity_max = 900 * u
	p.gravity = Vector2(0, 900 * u)
	p.angular_velocity_min = -360
	p.angular_velocity_max = 360
	p.scale_amount_min = 0.12 * u
	p.scale_amount_max = 0.3 * u
	if _estrelas_cor == null:
		_estrelas_cor = Gradient.new()
		_estrelas_cor.set_color(0, Color("#FFE14D"))
		_estrelas_cor.set_color(1, Color("#FF9F2E"))
		_estrelas_cor.add_point(0.5, Color("#7FE7FF"))
	p.color_initial_ramp = _estrelas_cor
	_centro.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


var _estrelas_cor: Gradient


func flash(cor := Color.WHITE, forca := 0.7, dur := 0.35) -> void:
	_flash.color = Color(cor.r, cor.g, cor.b, forca)
	_flash.visible = true
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, dur)
	tw.tween_callback(func(): _flash.visible = false)


# ================================================================ faixa "VEZ DE"
func _montar_faixa() -> void:
	_faixa = Painel3D.new(COR_BOB, 40, 14, 7)
	_faixa.visible = false
	add_child(_faixa)
	_faixa_avatar = TextureRect.new()
	_faixa_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_faixa_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_faixa_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_faixa.add_child(_faixa_avatar)
	_faixa_texto = rotulo("", 76, Color.WHITE, 16, MARINHO, fonte_titulo)
	_faixa.add_child(_faixa_texto)


func faixa(personagem: String, texto: String, sub := "", foto: Texture2D = null) -> void:
	var cor := COR_BOB if personagem == "bob" else COR_MIA
	_faixa.pintar(cor)
	_faixa_avatar.texture = foto if foto != null else _retratos.get(personagem)
	_faixa_avatar.material = material_foto(Color.WHITE) if foto != null else null
	_faixa_texto.text = texto + ("\n" + sub if sub != "" else "")
	var T := size
	var h := 210 * u
	var w: float = min(T.x * 0.92, 980 * u)
	_faixa.size = Vector2(w, h)
	if foto != null:
		_faixa_avatar.size = Vector2(h * 1.05, h * 1.05)
		_faixa_avatar.position = Vector2(-h * 0.05, -h * 0.12)
	else:
		_faixa_avatar.size = Vector2(h * 1.25, h * 1.25)
		_faixa_avatar.position = Vector2(-h * 0.15, -h * 0.35)
	_faixa_texto.size = Vector2(w - h * 1.1, h)
	_faixa_texto.position = Vector2(h * 1.05, 0)
	_tamanho_rotulo(_faixa_texto, (70 if sub == "" else 58) * u)
	_faixa_texto.label_settings.outline_size = int(16 * u)
	var y := T.y * (0.3 if retrato else 0.36)
	_faixa.position = Vector2(-w - 50 * u, y)
	_faixa.visible = true
	var tw := create_tween()
	tw.tween_property(_faixa, "position:x", (T.x - w) / 2, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.25)
	tw.tween_property(_faixa, "position:x", T.x + 50 * u, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _faixa.visible = false)


# ================================================================ replay
func _montar_replay() -> void:
	_tarja_cima = ColorRect.new()
	_tarja_baixo = ColorRect.new()
	for t in [_tarja_cima, _tarja_baixo]:
		t.color = Color(0.01, 0.03, 0.09, 1)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(t)
	_replay = TextureRect.new()
	_replay.texture = Materiais.textura("replay")
	_replay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_replay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_replay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_replay.visible = false
	add_child(_replay)
	_replay_ponto = painel(Color("#FF2E4D"), 99)
	_replay_ponto.visible = false
	add_child(_replay_ponto)


## Faixas pretas de cinema (abertura), sem o selo de replay.
func tarjas(ligado: bool) -> void:
	var T := size
	var h := T.y * (0.09 if retrato else 0.1) if ligado else 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_tarja_cima, "size:y", h, 0.4).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_tarja_baixo, "size:y", h, 0.4).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_tarja_baixo, "position:y", T.y - h, 0.4).set_trans(Tween.TRANS_QUAD)


func modo_replay(ligado: bool) -> void:
	var T := size
	var h := T.y * (0.1 if retrato else 0.12) if ligado else 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_tarja_cima, "size:y", h, 0.35).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_tarja_baixo, "size:y", h, 0.35).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_tarja_baixo, "position:y", T.y - h, 0.35).set_trans(Tween.TRANS_QUAD)
	_replay.visible = ligado
	_replay_ponto.visible = ligado
	# na demonstração (tela inicial) o logo grande sai da frente do selo REPLAY
	create_tween().tween_property(_logo, "modulate:a", 0.0 if ligado else 1.0, 0.3)
	var w := 420 * u
	_replay.size = Vector2(w, w * 0.236)
	_replay.position = Vector2(T.x - w - 40 * u, T.y * (0.1 if retrato else 0.12) * 0.5 - w * 0.118)
	_replay_ponto.size = Vector2(34, 34) * u
	_replay_ponto.position = _replay.position + Vector2(-50 * u, w * 0.118 - 17 * u)
	if ligado:
		mostrar_placar(false)
		mostrar_sensores(false)


# ================================================================ atração
func _montar_atracao() -> void:
	_atracao = Control.new()
	_atracao.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_atracao)
	_logo = TextureRect.new()
	_logo.texture = Materiais.textura("logo")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atracao.add_child(_logo)
	# botão amarelo com volume
	_aperte_botao = Painel3D.new(DESTAQUE, 70, 18, 8)
	_atracao.add_child(_aperte_botao)
	_aperte = rotulo("APERTE START", 88, MARINHO, 0, MARINHO, fonte_titulo)
	_aperte.label_settings.shadow_color = Color(1, 1, 1, 0.55)
	_aperte_botao.add_child(_aperte)
	# placa do recorde
	_recorde_placa = Painel3D.new(AZUL, 40, 10, 5)
	_atracao.add_child(_recorde_placa)
	_recorde = rotulo("", 40, CREME, 8)
	_recorde.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_recorde_placa.add_child(_recorde)
	_rec_foto = TextureRect.new()
	_rec_foto.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rec_foto.stretch_mode = TextureRect.STRETCH_SCALE
	_rec_foto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rec_foto.material = material_foto(DESTAQUE)
	_rec_foto.visible = false
	_recorde_placa.add_child(_rec_foto)
	_creditos = rotulo("", 30, Color.WHITE, 8)
	_atracao.add_child(_creditos)
	_atracao.visible = false


func atracao(ligado: bool, recorde := "", creditos := "", foto_recorde: Texture2D = null, melhores := []) -> void:
	_atracao.visible = ligado
	_melhores_hoje = melhores
	# o quadro dos melhores só é montado de novo quando muda (montar a cada
	# volta da demonstração dava um tranco na TV Box)
	var chave := "%s|%s|%s|%s" % [str(melhores), recorde, str(size), str(retrato)]
	if chave != _chave_melhores or (_melhores == null and not melhores.is_empty()):
		_chave_melhores = chave
		_montar_melhores(melhores, recorde)
	if not melhores.is_empty():
		recorde = ""
	_recorde.text = recorde
	_creditos.text = creditos
	_rec_foto.texture = foto_recorde
	_rec_foto.visible = foto_recorde != null and recorde != ""
	_recorde_placa.visible = recorde != ""
	if recorde != "":
		var ls := _recorde.label_settings
		var larg := ls.font.get_string_size(recorde, HORIZONTAL_ALIGNMENT_LEFT, -1, ls.font_size).x
		var h := 100 * u
		var d := 124 * u
		var foto_l := d * 0.82 if _rec_foto.visible else 0.0
		var w := minf(larg + foto_l + 80 * u, size.x * 0.94)
		_recorde_placa.size = Vector2(w, h)
		var cx := _aperte_botao.position.x + _aperte_botao.size.x / 2
		_recorde_placa.position = Vector2(clampf(cx - w / 2, 16 * u, size.x - w - 16 * u), _aperte_botao.position.y + _aperte_botao.size.y + 34 * u)
		_recorde.size = Vector2(w - foto_l - 50 * u, h - 10 * u)
		_recorde.position = Vector2(foto_l + 30 * u, 0)
		_rec_foto.size = Vector2(d, d)
		_rec_foto.position = Vector2(-d * 0.3, (h - d) / 2 - 6 * u)
	if ligado:
		mostrar_placar(false)
		mostrar_sensores(false)


## "MELHORES DE HOJE" na atração: os 3 primeiros do dia, com a foto de
## cada um (chama a criançada: "olha eu ali!").
var _melhores: Control
var _melhores_hoje := []
var _chave_melhores := ""


func _montar_melhores(lista: Array, recorde: String) -> void:
	if _melhores != null:
		_melhores.queue_free()
		_melhores = null
	if lista.is_empty():
		return
	var T := size
	var d := 150 * u
	var gap := 34 * u
	var w := lista.size() * d + (lista.size() - 1) * gap + 80 * u
	var cab_h := 70 * u
	var h := cab_h + d + 96 * u
	w = maxf(w, 560 * u)
	var p := Painel3D.new(Color("#0E2A5C"), 40, 14, 7)
	p.size = Vector2(w, h)
	if retrato:
		var y := _aperte_botao.position.y + _aperte_botao.size.y + 34 * u
		p.position = Vector2((T.x - w) / 2, minf(y, T.y - h - 110 * u))
	else:
		p.position = Vector2(T.x - w - 40 * u, T.y * 0.06)
	_atracao.add_child(p)
	_melhores = p
	var cab_txt := "MELHORES DE HOJE"
	var cab := rotulo(cab_txt, 42 * u, CREME, 10 * u, MARINHO, fonte_titulo)
	cab.size = Vector2(w, cab_h)
	p.add_child(cab)
	_caber(cab, 42 * u, w - 40 * u)
	var x0 := (w - (lista.size() * d + (lista.size() - 1) * gap)) / 2
	for k in lista.size():
		var e: Dictionary = lista[k]
		var fr := TextureRect.new()
		var ft := Fotos.carregar(str(e.get("foto", "")))
		fr.texture = ft if ft != null else _retratos.get(str(e.get("personagem", "bob")))
		fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fr.stretch_mode = TextureRect.STRETCH_SCALE
		fr.material = material_foto(_cor_medalha(k + 1))
		fr.size = Vector2(d, d)
		fr.position = Vector2(x0 + k * (d + gap), cab_h)
		p.add_child(fr)
		var md := 54 * u
		var med := Painel3D.new(_cor_medalha(k + 1), md / 2.0 / u, 5, 4)
		med.size = Vector2(md, md)
		med.position = fr.position + Vector2(-md * 0.2, -md * 0.15)
		p.add_child(med)
		var ln := rotulo(str(k + 1), md * 0.56, MARINHO, 0, MARINHO, fonte_titulo)
		ln.size = Vector2(md, md - 4 * u)
		med.add_child(ln)
		var lp := rotulo("%d" % int(e.get("pontos", 0)), 46 * u, Color.WHITE, 10 * u, MARINHO, fonte_titulo)
		lp.size = Vector2(d + gap, 60 * u)
		lp.position = Vector2(fr.position.x - gap / 2, cab_h + d + 8 * u)
		p.add_child(lp)


# ================================================================ etapas
## Faixa "1 JOGADORES › 2 AMIGO › 3 FOTO › 4 JOGAR" no alto das telas de
## preparação: a criança (e o pai) sabem em que passo estão.
const ETAPAS := ["JOGADORES", "AMIGO", "FOTO", "JOGAR"]
var _etapas: Control
var _etapas_pilulas: Array[Painel3D] = []


func _montar_etapas() -> void:
	_etapas = Control.new()
	_etapas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_etapas.visible = false
	add_child(_etapas)
	for i in ETAPAS.size():
		var p := Painel3D.new(AZUL, 30, 7, 4)
		_etapas.add_child(p)
		var l := rotulo("%d  %s" % [i + 1, ETAPAS[i]], 30, Color.WHITE, 7, MARINHO)
		l.name = "texto"
		p.add_child(l)
		_etapas_pilulas.append(p)


## n = passo atual (1..4); 0 esconde. pulos: passos que não acontecem nesta
## partida (ex.: AMIGO com 2 jogadores) aparecem como feitos.
func etapa(n: int) -> void:
	_etapas.visible = n > 0
	for i in _etapas_pilulas.size():
		var p := _etapas_pilulas[i]
		var passo := i + 1
		if passo == n:
			p.pintar(DESTAQUE)
			p.modulate = Color.WHITE
			(p.get_node("texto") as Label).label_settings.font_color = MARINHO
			(p.get_node("texto") as Label).label_settings.outline_size = 0
		elif passo < n:
			p.pintar(Color("#2DBE4E"))
			p.modulate = Color(1, 1, 1, 0.9)
			(p.get_node("texto") as Label).label_settings.font_color = Color.WHITE
			(p.get_node("texto") as Label).label_settings.outline_size = int(7 * u)
		else:
			p.pintar(AZUL)
			p.modulate = Color(1, 1, 1, 0.75)
			(p.get_node("texto") as Label).label_settings.font_color = Color.WHITE
			(p.get_node("texto") as Label).label_settings.outline_size = int(7 * u)


func _layout_etapas(T: Vector2) -> void:
	var gap := 12 * u
	var w: float = minf((T.x - 40 * u - gap * 3) / 4.0, 250 * u)
	var h := 66 * u
	var x0 := (T.x - (w * 4 + gap * 3)) / 2
	for i in _etapas_pilulas.size():
		var p := _etapas_pilulas[i]
		p.size = Vector2(w, h)
		p.position = Vector2(x0 + i * (w + gap), 24 * u)
		var l := p.get_node("texto") as Label
		l.size = Vector2(w, h - 8 * u)
		l.position = Vector2.ZERO
		_caber(l, 30 * u, w - 20 * u)


## Os 5 sensores da máquina em miniatura (da esquerda para a direita),
## cada um com a cor do que ele faz nesta tela.
func _sensores(cores: Array, legendas: Array) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 5:
		var b := Panel.new()
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_theme_stylebox_override("panel", caixa(cores[i], 99, 4, Color.WHITE, 4))
		b.name = "s%d" % i
		c.add_child(b)
	for i in legendas.size():
		var l := rotulo(str(legendas[i][0]), 28, Color.WHITE, 7, MARINHO)
		l.name = "l%d" % i
		l.set_meta("de", legendas[i][1])
		l.set_meta("ate", legendas[i][2])
		c.add_child(l)
	return c


func _layout_sensores(c: Control, largura: float) -> void:
	var d := 40 * u
	var passo := minf(largura / 5.0, 76 * u)
	var x0 := (largura - passo * 4 - d) / 2
	for i in 5:
		var b := c.get_node("s%d" % i) as Panel
		b.size = Vector2(d, d)
		b.position = Vector2(x0 + i * passo, 0)
	for l in c.get_children():
		if l is Label:
			var de: int = l.get_meta("de")
			var ate: int = l.get_meta("ate")
			var xa := x0 + de * passo
			var xb := x0 + ate * passo + d
			_tamanho_rotulo(l, 26 * u)
			l.label_settings.outline_size = int(7 * u)
			l.size = Vector2(maxf(xb - xa, 120 * u), 36 * u)
			l.position = Vector2((xa + xb) / 2 - l.size.x / 2, d + 4 * u)
	c.size = Vector2(largura, d + 44 * u)


# ================================================================ quantos vão jogar
## Igual ao Dragon Bowling (mesma máquina): START 1 vez = 1 jogador;
## START de novo (dentro do tempo) = 2 jogadores. A tela mostra isso com o
## botão START desenhado em cada cartão e a contagem para começar.
func _montar_jogadores() -> void:
	_jog = Control.new()
	_jog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_jog.visible = false
	add_child(_jog)
	_jog_painel = Painel3D.new(AZUL, 50, 18, 8)
	_jog.add_child(_jog_painel)
	_jog_titulo = rotulo("QUANTOS VÃO JOGAR?", 70, CREME, 16, MARINHO, fonte_titulo)
	_jog_painel.add_child(_jog_titulo)
	for i in 2:
		var c := Painel3D.new(Color("#F2F7FF"), 40, 16, 6)
		_jog_painel.add_child(c)
		var num := rotulo(str(i + 1), 170, COR_BOB if i == 0 else COR_MIA, 22, MARINHO, fonte_titulo)
		num.name = "num"
		c.add_child(num)
		var leg := rotulo("JOGADOR" if i == 0 else "JOGADORES", 46, MARINHO, 0, MARINHO, fonte_titulo)
		leg.label_settings.shadow_size = 0
		leg.name = "leg"
		c.add_child(leg)
		for k in 2:
			var r := TextureRect.new()
			r.texture = _retratos["bob" if k == 0 else "mia"]
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.name = "retrato_%d" % k
			c.add_child(r)
		var mei := rotulo("ou" if i == 0 else "x", 40, MARINHO, 0, MARINHO, fonte_titulo)
		mei.label_settings.shadow_size = 0
		mei.name = "meio"
		c.add_child(mei)
		# como escolher: o botão START desenhado + quantas vezes
		var bt := Painel3D.new(Color("#E8384F"), 26, 7, 4)
		bt.name = "botao"
		c.add_child(bt)
		var bl := rotulo("START", 34, Color.WHITE, 8, MARINHO, fonte_titulo)
		bl.name = "texto"
		bt.add_child(bl)
		var vezes := rotulo("1 VEZ" if i == 0 else "2 VEZES", 40, MARINHO, 0, MARINHO, fonte_titulo)
		vezes.label_settings.shadow_size = 0
		vezes.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		vezes.name = "vezes"
		c.add_child(vezes)
		_jog_cartoes.append(c)
	_jog_dica = rotulo("", 36, Color.WHITE, 9)
	_jog_painel.add_child(_jog_dica)
	_jog_trilho = Painel3D.new(MARINHO.lightened(0.08), 17, 3, 3)
	_jog_trilho.sombra(0.0)
	_jog_painel.add_child(_jog_trilho)
	_jog_barra = Painel3D.new(DESTAQUE, 17, 5, 3)
	_jog_barra.sombra(0.0)
	_jog_trilho.add_child(_jog_barra)


## Tela "QUANTOS VÃO JOGAR?": dois cartões (1 ou 2), o escolhido brilha.
## fracao: tempo que falta (1 → 0); segundos: para a contagem escrita.
func jogadores(ligado: bool, n := 1, fracao := 0.0, segundos := 0) -> void:
	if ligado and not _jog.visible:
		_jog_painel.pivot_offset = _jog_painel.size / 2
		_jog_painel.scale = Vector2.ONE * 0.75
		create_tween().tween_property(_jog_painel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_jog.visible = ligado
	if not ligado:
		return
	if n != _jog_n:
		_pular(_jog_cartoes[n - 1])
	_jog_n = n
	if n == 1:
		_jog_dica.text = "Vão jogar em 2? Aperte START de novo agora!\nSe não, começa com 1 jogador em %d..." % maxi(segundos, 1)
	else:
		_jog_dica.text = "2 JOGADORES: BOB x MIA!\nPreparem-se..."
	_jog_barra.size.x = maxf(_jog_trilho.size.x * clampf(fracao, 0.0, 1.0), _jog_trilho.size.y)
	_jog_barra.visible = fracao > 0.0
	for i in 2:
		var c := _jog_cartoes[i]
		c.modulate = Color.WHITE if i == n - 1 else Color(0.78, 0.82, 0.9, 0.9)
		if i != n - 1:
			c.realcar(0.0)


func _layout_jogadores(T: Vector2) -> void:
	var mw: float = minf(T.x * 0.92, 980 * u)
	var mh := 830 * u
	_jog_painel.size = Vector2(mw, mh)
	_jog_painel.position = (T - _jog_painel.size) / 2 + Vector2(0, (50 if retrato else 30) * u)
	_jog_painel.pivot_offset = _jog_painel.size / 2
	_tamanho_rotulo(_jog_titulo, 70 * u)
	_jog_titulo.label_settings.outline_size = int(16 * u)
	_jog_titulo.size = Vector2(mw, 120 * u)
	_jog_titulo.position = Vector2(0, 22 * u)
	_caber(_jog_titulo, 70 * u, mw - 60 * u)
	var gap := 36 * u
	var cw := (mw - gap * 3) / 2
	var ch := 470 * u
	for i in 2:
		var c := _jog_cartoes[i]
		c.size = Vector2(cw, ch)
		c.position = Vector2(gap + i * (cw + gap), 150 * u)
		c.pivot_offset = c.size / 2
		var num := c.get_node("num") as Label
		_tamanho_rotulo(num, 170 * u)
		num.label_settings.outline_size = int(22 * u)
		num.size = Vector2(cw, 180 * u)
		num.position = Vector2(0, 0)
		var leg := c.get_node("leg") as Label
		_tamanho_rotulo(leg, 44 * u)
		leg.label_settings.shadow_size = 0
		leg.size = Vector2(cw, 56 * u)
		leg.position = Vector2(0, 172 * u)
		_caber(leg, 44 * u, cw - 30 * u)
		var rs := 112 * u
		for k in 2:
			var r := c.get_node("retrato_%d" % k) as TextureRect
			r.size = Vector2(rs, rs)
			r.position = Vector2(cw / 2 + (-rs - 20 * u if k == 0 else 20 * u), 232 * u)
		var mei := c.get_node("meio") as Label
		_tamanho_rotulo(mei, 38 * u)
		mei.label_settings.shadow_size = 0
		mei.size = Vector2(cw, rs)
		mei.position = Vector2(0, 232 * u)
		# botão START + "1 VEZ"/"2 VEZES", centralizados
		var bt := c.get_node("botao") as Painel3D
		var vezes := c.get_node("vezes") as Label
		var bw := 150 * u
		var bh := 60 * u
		_tamanho_rotulo(vezes, 38 * u)
		vezes.label_settings.shadow_size = 0
		var vw := vezes.label_settings.font.get_string_size(vezes.text, HORIZONTAL_ALIGNMENT_LEFT, -1, vezes.label_settings.font_size).x
		var total := bw + 14 * u + vw
		var x0 := (cw - total) / 2
		bt.size = Vector2(bw, bh)
		bt.position = Vector2(x0, 372 * u)
		var bl := bt.get_node("texto") as Label
		_tamanho_rotulo(bl, 32 * u)
		bl.label_settings.outline_size = int(7 * u)
		bl.size = Vector2(bw, bh - 7 * u)
		bl.position = Vector2.ZERO
		vezes.size = Vector2(vw + 10 * u, bh)
		vezes.position = Vector2(x0 + bw + 14 * u, 372 * u - 4 * u)
	_tamanho_rotulo(_jog_dica, 34 * u)
	_jog_dica.label_settings.outline_size = int(9 * u)
	_jog_dica.size = Vector2(mw - 40 * u, 100 * u)
	_jog_dica.position = Vector2(20 * u, 636 * u)
	_jog_dica.autowrap_mode = TextServer.AUTOWRAP_OFF
	_jog_trilho.size = Vector2(mw - 140 * u, 34 * u)
	_jog_trilho.position = Vector2(70 * u, 752 * u)
	_jog_barra.size = Vector2(_jog_barra.size.x, 34 * u)
	_jog_barra.position = Vector2.ZERO


# ================================================================ escolha do personagem
func _montar_selecao() -> void:
	_selecao = Control.new()
	_selecao.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selecao.visible = false
	add_child(_selecao)
	_sel_titulo = Painel3D.new(AZUL, 44, 14, 7)
	_selecao.add_child(_sel_titulo)
	var t := rotulo("ESCOLHA SEU AMIGO!", 76, CREME, 16, MARINHO, fonte_titulo)
	t.name = "titulo"
	_sel_titulo.add_child(t)
	for i in 2:
		var placa := Painel3D.new(COR_BOB if i == 0 else COR_MIA, 36, 14, 7)
		_selecao.add_child(placa)
		var l := rotulo("BOB" if i == 0 else "MIA", 70, Color.WHITE, 16, MARINHO, fonte_titulo)
		placa.add_child(l)
		_sel_placas.append(placa)
		_sel_nomes.append(l)
	_sel_dica = Painel3D.new(MARINHO.lightened(0.12), 30, 8, 5)
	_sel_dica.modulate.a = 0.94
	_selecao.add_child(_sel_dica)
	_sel_texto = rotulo("", 36, Color.WHITE, 9)
	_sel_dica.add_child(_sel_texto)
	# os 5 sensores: esquerda = Bob, meio = confirma, direita = Mia
	_sel_sensores = _sensores([COR_BOB, COR_BOB, DESTAQUE, COR_MIA, COR_MIA],
		[["BOB", 0, 1], ["OK", 2, 2], ["MIA", 3, 4]])
	_sel_dica.add_child(_sel_sensores)


## pes: onde ficam os pés de Bob e Mia na tela (a placa fica logo abaixo).
func selecao(ligado: bool, destaque := 0, texto := "", pes: Array = []) -> void:
	var entrou := ligado and not _selecao.visible
	_selecao.visible = ligado
	_sel_texto.text = texto
	if not ligado:
		return
	if entrou:
		_pular(_sel_titulo)
	if destaque != _sel_destaque:
		_pular(_sel_placas[destaque])
	_sel_destaque = destaque
	for i in 2:
		var p := _sel_placas[i]
		if pes.size() == 2:
			var pe: Vector2 = pes[i]
			p.position = Vector2(clampf(pe.x - p.size.x / 2, 12 * u, size.x - p.size.x - 12 * u), pe.y + 30 * u)
		p.pivot_offset = p.size / 2
		var alvo := 1.12 if i == destaque else 0.9
		p.scale = p.scale.lerp(Vector2.ONE * alvo, 0.25)
		p.modulate = Color.WHITE if i == destaque else Color(0.8, 0.84, 0.92, 0.85)
		if i != destaque:
			p.realcar(0.0)


# ================================================================ fim de jogo
## dados: {jogadores: [{personagem, pontos, estrelas, strikes, spares}], vencedor, recorde: bool, recorde_valor}
## FIM DE JOGO + CLASSIFICAÇÃO: o cartão de cada jogador com a FOTO grande
## dele (ou o mascote), pontos, estrelas e a posição no dia; embaixo (em
## pé) ou ao lado (deitada) o quadro "CLASSIFICAÇÃO DE HOJE" com a foto de
## cada um — quem acabou de jogar aparece brilhando, com "VOCÊ!".
func tela_fim(ligado: bool, dados := {}) -> void:
	for f in _fim.get_children():
		f.queue_free()
	_fim.visible = ligado
	_fim_vez += 1
	if not ligado:
		return
	var vez := _fim_vez
	mostrar_placar(false)
	mostrar_sensores(false)
	var T := size
	var bh := 116 * u
	var y_botao := T.y - bh - (110 if retrato else 34) * u
	var titulo := TextureRect.new()
	titulo.texture = Materiais.textura("fim_de_jogo")
	titulo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	titulo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tw_l: float = minf(T.x * 0.42, 440 * u) if retrato else 340 * u
	titulo.size = Vector2(tw_l, tw_l * 0.61)
	titulo.position = Vector2((T.x - tw_l) / 2, (40 if retrato else 14) * u)
	titulo.pivot_offset = titulo.size / 2
	titulo.scale = Vector2.ZERO
	_fim.add_child(titulo)
	create_tween().tween_property(titulo, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var y0 := titulo.position.y + titulo.size.y + 6 * u
	var area_c: Rect2
	var area_q: Rect2
	if retrato:
		area_c = Rect2(36 * u, y0, T.x - 72 * u, 590 * u)
		area_q = Rect2(36 * u, y0 + 620 * u, T.x - 72 * u, y_botao - (y0 + 620 * u) - 26 * u)
	else:
		var meio := T.x * 0.5
		area_c = Rect2(30 * u, y0, meio - 50 * u, y_botao - y0 - 20 * u)
		area_q = Rect2(meio + 20 * u, y0, meio - 50 * u, y_botao - y0 - 20 * u)
	var js: Array = dados.get("jogadores", [])
	for i in js.size():
		_cartao_fim(js[i], i, js.size(), area_c, dados.get("vencedor", -9) == i and js.size() > 1)
	_quadro_classificacao(dados.get("classificacao", []), js, area_q)
	# (só se ainda for este fim de jogo: com START logo, a partida nova já começou)
	if dados.get("vencedor", -9) == -1 and js.size() > 1:
		_atrasado(3.0, func():
			if vez == _fim_vez:
				letreiro("empate", "", 2.5, 0.55))
	if dados.get("recorde", false):
		_atrasado(3.4, func():
			if vez == _fim_vez:
				letreiro("novo_recorde", "%d PONTOS" % dados.get("recorde_valor", 0), 3.0, 0.42 if retrato else 0.3))
	# botão "jogar de novo"
	var bw: float = minf(T.x * 0.92, 940 * u)
	var botao := Painel3D.new(DESTAQUE, 58, 14, 7)
	botao.size = Vector2(bw, bh)
	botao.position = Vector2((T.x - bw) / 2, y_botao)
	botao.name = "botao"
	_fim.add_child(botao)
	var ap := rotulo("APERTE START PARA JOGAR DE NOVO", 44 * u, MARINHO, 0, MARINHO, fonte_titulo)
	ap.label_settings.shadow_color = Color(1, 1, 1, 0.55)
	ap.size = Vector2(bw, bh - 14 * u)
	ap.name = "aperte"
	botao.add_child(ap)
	_caber(ap, 44 * u, bw - 70 * u)


## Cartão de um jogador: foto grande em cima, nome, pontos, estrelas e o
## lugar na classificação do dia.
func _cartao_fim(j: Dictionary, i: int, n: int, area: Rect2, venceu: bool) -> void:
	var cor := COR_BOB if j["personagem"] == "bob" else COR_MIA
	var gap := 26 * u
	var w: float = minf((area.size.x - gap * (n - 1)) / n, 620 * u)
	var d: float = minf(w * (0.5 if n == 1 else 0.56), 250 * u)
	var h: float = minf(area.size.y - d * 0.42, 472 * u)
	var x := area.position.x + (area.size.x - (w * n + gap * (n - 1))) / 2 + i * (w + gap)
	var y := area.position.y + d * 0.42
	var c := Painel3D.new(cor, 44, 18, 8)
	c.size = Vector2(w, h)
	c.position = Vector2(x, y + 900 * u)
	_fim.add_child(c)
	var tw := create_tween()
	tw.tween_interval(0.3 + i * 0.2)
	tw.tween_property(c, "position:y", y, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# foto (da câmera; sem câmera, o mascote)
	var ft: Texture2D = j.get("foto")
	var fr := TextureRect.new()
	fr.texture = ft if ft != null else _retratos.get(j["personagem"])
	fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fr.stretch_mode = TextureRect.STRETCH_SCALE
	fr.material = material_foto(DESTAQUE if venceu else Color.WHITE)
	fr.size = Vector2(d, d)
	fr.position = Vector2((w - d) / 2, -d * 0.42)
	fr.pivot_offset = fr.size / 2
	c.add_child(fr)
	if ft != null:
		# o mascote com quem jogou, no cantinho da foto
		var selo := TextureRect.new()
		selo.texture = _retratos.get(j["personagem"])
		selo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		selo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		selo.size = Vector2(d, d) * 0.4
		selo.position = fr.position + Vector2(d * 0.7, d * 0.62)
		c.add_child(selo)
	var yy := d * 0.6
	var nome := rotulo(str(j["personagem"]).to_upper(), 46 * u, Color.WHITE, 10 * u, MARINHO, fonte_titulo)
	nome.size = Vector2(w, 58 * u)
	nome.position = Vector2(0, yy)
	c.add_child(nome)
	var pts := rotulo("0", 96 * u, CREME, 20 * u, MARINHO, fonte_titulo)
	pts.size = Vector2(w, 100 * u)
	pts.position = Vector2(0, yy + 44 * u)
	c.add_child(pts)
	var alvo := int(j["pontos"])
	# (a contagem é do próprio texto: some junto com ele)
	var tw2 := pts.create_tween()
	tw2.tween_interval(0.8 + i * 0.2)
	tw2.tween_method(func(v: float): pts.text = str(int(v)), 0.0, float(alvo), 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var leg := rotulo("PONTOS", 30 * u, Color.WHITE, 7 * u)
	leg.size = Vector2(w, 34 * u)
	leg.position = Vector2(0, yy + 136 * u)
	c.add_child(leg)
	var ne := int(j.get("estrelas", 1))
	for k in 3:
		var e := TextureRect.new()
		e.texture = Materiais.textura("estrela_placar" if k < ne else "estrela_vazia")
		e.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		e.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var es := 64 * u if k == 1 else 54 * u
		e.size = Vector2(es, es)
		e.position = Vector2(w / 2 - es / 2 + (k - 1) * 72 * u, yy + 176 * u - (6 * u if k == 1 else 0.0))
		e.pivot_offset = e.size / 2
		e.scale = Vector2.ZERO
		c.add_child(e)
		var tw3 := create_tween()
		tw3.tween_interval(2.2 + k * 0.25 + i * 0.1)
		tw3.tween_property(e, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# lugar no dia (e quem venceu a partida de 2)
	var pos := int(j.get("posicao", 0))
	if pos > 0 or venceu:
		var fita_h := 58 * u
		var fita := Painel3D.new(DESTAQUE if venceu else _cor_medalha(pos), 28, 8, 5)
		fita.size = Vector2(w * 0.88, fita_h)
		fita.position = Vector2(w * 0.06, h - fita_h - 16 * u)
		c.add_child(fita)
		var txt := "%dº LUGAR HOJE!" % pos if pos <= 3 else "%dº LUGAR HOJE" % pos
		if venceu:
			txt = "VENCEU!  %dº HOJE" % pos if pos > 0 else "VENCEU!"
			pos = mini(pos, 3) if pos > 0 else 1
		var lf := rotulo(txt, 34 * u, MARINHO if pos <= 3 else Color.WHITE, 0 if pos <= 3 else 7 * u, MARINHO, fonte_titulo)
		lf.size = Vector2(w * 0.86, fita_h - 6 * u)
		fita.add_child(lf)
		_caber(lf, 34 * u, w * 0.8)
		fita.pivot_offset = fita.size / 2
		fita.scale = Vector2.ZERO
		var tw5 := create_tween()
		tw5.tween_interval(2.8 + i * 0.15)
		tw5.tween_property(fita, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if venceu:
		c.realcar(0.55)


func _cor_medalha(pos: int) -> Color:
	match pos:
		1:
			return Color("#FFC21A")
		2:
			return Color("#DCE6F2")
		3:
			return Color("#F0A25A")
	return AZUL


## Quadro "CLASSIFICAÇÃO DE HOJE": os 5 primeiros do dia, cada um com a sua
## foto; quem jogou agora e ficou mais para trás aparece numa linha a mais.
func _quadro_classificacao(lista: Array, js: Array, area: Rect2) -> void:
	if area.size.y < 200 * u:
		return
	var linhas := []
	for k in mini(5, lista.size()):
		linhas.append({"pos": k + 1, "e": lista[k]})
	for j in js:
		var pos := int(j.get("posicao", 0))
		if pos > 5:
			linhas.append({"pos": pos, "e": {"pontos": j["pontos"], "personagem": j["personagem"], "hora": ""}, "foto": j.get("foto")})
	var atuais := {}
	for j in js:
		atuais[int(j.get("posicao", 0))] = true
	var cab_h := 86 * u
	var gap := 12 * u
	var n := maxi(linhas.size(), 1)
	var lh: float = clampf((area.size.y - cab_h - gap * (n + 1)) / n, 70 * u, 112 * u)
	var altura := cab_h + gap + n * (lh + gap)
	var quadro := Painel3D.new(Color("#0E2A5C"), 40, 14, 7)
	quadro.size = Vector2(area.size.x, altura)
	quadro.position = area.position
	quadro.modulate.a = 0.0
	_fim.add_child(quadro)
	create_tween().tween_property(quadro, "modulate:a", 1.0, 0.4).set_delay(1.0)
	var cab := rotulo("CLASSIFICAÇÃO DE HOJE", 50 * u, CREME, 12 * u, MARINHO, fonte_titulo)
	cab.size = Vector2(area.size.x, cab_h)
	quadro.add_child(cab)
	_caber(cab, 50 * u, area.size.x - 60 * u)
	if lista.is_empty() and linhas.is_empty():
		return
	var lw := area.size.x - 36 * u
	for k in linhas.size():
		var l: Dictionary = linhas[k]
		var e: Dictionary = l["e"]
		var pos: int = l["pos"]
		var minha: bool = atuais.has(pos)
		var cor := Color("#2A63C4") if not minha else Color("#FFB627")
		var lin := Painel3D.new(cor, 26, 8, 4)
		lin.size = Vector2(lw, lh)
		lin.position = Vector2(18 * u, cab_h + gap + k * (lh + gap))
		quadro.add_child(lin)
		lin.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(1.2 + k * 0.12)
		tw.tween_property(lin, "modulate:a", 1.0, 0.25)
		# número (medalha para os 3 primeiros)
		var md := lh * 0.74
		var med := Painel3D.new(_cor_medalha(pos), md / 2.0 / u, 6, 4)
		med.size = Vector2(md, md)
		med.position = Vector2(12 * u, (lh - md) / 2 - 3 * u)
		lin.add_child(med)
		var ln := rotulo(str(pos), md * 0.55, MARINHO if pos <= 3 else Color.WHITE, 0 if pos <= 3 else 6 * u, MARINHO, fonte_titulo)
		ln.size = Vector2(md, md - 4 * u)
		med.add_child(ln)
		# foto da criança (ou o mascote)
		var fd := lh * 0.92
		var ft: Texture2D = l.get("foto")
		if ft == null:
			ft = Fotos.carregar(str(e.get("foto", "")))
		var fr := TextureRect.new()
		fr.texture = ft if ft != null else _retratos.get(str(e.get("personagem", "bob")))
		fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fr.stretch_mode = TextureRect.STRETCH_SCALE
		fr.material = material_foto(Color.WHITE)
		fr.size = Vector2(fd, fd)
		fr.position = Vector2(24 * u + md, (lh - fd) / 2 - 3 * u)
		lin.add_child(fr)
		var px := 24 * u + md + fd + 14 * u
		var quem := "com %s" % str(e.get("personagem", "")).to_upper()
		if str(e.get("hora", "")) != "":
			quem += "  ·  %s" % e["hora"]
		var lq := rotulo(quem, 30 * u, Color.WHITE, 7 * u, MARINHO)
		lq.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lq.size = Vector2(lw * 0.5, lh - 6 * u)
		lq.position = Vector2(px, 0)
		lin.add_child(lq)
		if minha:
			var voce := rotulo("VOCÊ!", 34 * u, MARINHO, 0, MARINHO, fonte_titulo)
			voce.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			voce.size = Vector2(lw * 0.3, lh * 0.5)
			voce.position = Vector2(px, -2 * u)
			lq.position.y = lh * 0.36
			lq.size.y = lh * 0.6
			lq.label_settings.font_color = MARINHO
			lq.label_settings.outline_size = 0
			lin.add_child(voce)
		var lp := rotulo(str(int(e.get("pontos", 0))), lh * 0.6, CREME if not minha else MARINHO, 0 if minha else 10 * u, MARINHO, fonte_titulo)
		lp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lp.size = Vector2(lw * 0.3, lh - 6 * u)
		lp.position = Vector2(lw * 0.7 - 24 * u, 0)
		lin.add_child(lp)


func fim_contagem(segundos: int) -> void:
	var ap := _fim.find_child("aperte", true, false) as Label
	if ap:
		ap.text = "APERTE START PARA JOGAR DE NOVO  (%d)" % segundos
		_caber(ap, 44 * u, ap.size.x - 70 * u)
	var b := _fim.get_node_or_null("botao") as Control
	if b:
		b.pivot_offset = b.size / 2
		b.scale = Vector2.ONE * (1.0 + sin(_tempo * 4.0) * 0.025)


func _atrasado(t: float, f: Callable) -> void:
	get_tree().create_timer(t).timeout.connect(f)


# ================================================================ inatividade
func _montar_inatividade() -> void:
	_inativo = Painel3D.new(AZUL, 48, 18, 8)
	_inativo.visible = false
	add_child(_inativo)
	_inativo_texto = rotulo("", 52, Color.WHITE, 12)
	_inativo_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inativo.add_child(_inativo_texto)


## Aviso no alto da tela ANTES de uma janela de permissão do Android (ela
## congela a imagem do jogo; o aviso fica visível em volta dela): o que
## tocar para ela nunca mais aparecer. "" = some.
func _montar_aviso_android() -> void:
	_aviso_android = Painel3D.new(Color("#E8384F"), 36, 12, 7)
	_aviso_android.visible = false
	add_child(_aviso_android)
	_aviso_android_texto = rotulo("", 40, Color.WHITE, 10)
	_aviso_android_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aviso_android.add_child(_aviso_android_texto)


func aviso_android(texto: String) -> void:
	_aviso_android.visible = texto != ""
	_aviso_android_texto.text = texto


func inatividade(ligado: bool, segundos := 10) -> void:
	_inativo.visible = ligado
	_inativo_texto.text = "AINDA ESTÁ AÍ?\n\nRole a bola para continuar!\n\n%d" % segundos


# ================================================================ fotos (câmera da máquina)
func material_foto(cor_aro: Color) -> ShaderMaterial:
	if _shader_foto == null:
		_shader_foto = load("res://shaders/foto_redonda.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader_foto
	m.set_shader_parameter("cor_aro", cor_aro)
	return m


func _montar_fotos() -> void:
	_foto_tela = Control.new()
	_foto_tela.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foto_tela.visible = false
	add_child(_foto_tela)
	_foto_fundo = ColorRect.new()
	_foto_fundo.color = Color(0.01, 0.05, 0.14, 0.55)
	_foto_fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foto_tela.add_child(_foto_fundo)
	_foto_titulo = rotulo("SORRIA!", 110, Color("#FFF6A8"), 24, MARINHO, fonte_titulo)
	_foto_tela.add_child(_foto_titulo)
	_foto_circulo = TextureRect.new()
	_foto_circulo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_foto_circulo.stretch_mode = TextureRect.STRETCH_SCALE
	_foto_circulo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_foto_circulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foto_tela.add_child(_foto_circulo)
	_foto_selo = TextureRect.new()
	_foto_selo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_foto_selo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_foto_selo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foto_tela.add_child(_foto_selo)
	_foto_numero = rotulo("", 280, Color.WHITE, 44, MARINHO, fonte_titulo)
	_foto_tela.add_child(_foto_numero)
	_foto_sub = rotulo("", 46, Color.WHITE, 12, MARINHO)
	_foto_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_foto_tela.add_child(_foto_sub)
	_foto_destaque = TextureRect.new()
	_foto_destaque.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_foto_destaque.stretch_mode = TextureRect.STRETCH_SCALE
	_foto_destaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foto_destaque.visible = false
	add_child(_foto_destaque)


func _layout_fotos() -> void:
	var T := size
	_foto_fundo.size = T
	var d: float = minf(T.x * 0.7, T.y * 0.44)
	var cy := T.y * (0.47 if retrato else 0.52)
	_foto_circulo.size = Vector2(d, d)
	_foto_circulo.position = Vector2((T.x - d) / 2, cy - d / 2)
	_foto_circulo.pivot_offset = _foto_circulo.size / 2
	var sd := d * 0.42
	_foto_selo.size = Vector2(sd, sd)
	_foto_selo.position = _foto_circulo.position + Vector2(d * 0.74, d * 0.66)
	_tamanho_rotulo(_foto_titulo, 110 * u)
	_foto_titulo.label_settings.outline_size = int(24 * u)
	_foto_titulo.size = Vector2(T.x, 150 * u)
	_foto_titulo.position = Vector2(0, cy - d / 2 - 190 * u)
	_foto_titulo.pivot_offset = _foto_titulo.size / 2
	_tamanho_rotulo(_foto_numero, 280 * u)
	_foto_numero.label_settings.outline_size = int(44 * u)
	_foto_numero.size = Vector2(T.x, 360 * u)
	_foto_numero.position = Vector2(0, cy - 180 * u)
	_foto_numero.pivot_offset = _foto_numero.size / 2
	_tamanho_rotulo(_foto_sub, 46 * u)
	_foto_sub.label_settings.outline_size = int(12 * u)
	_foto_sub.size = Vector2(T.x * 0.9, 140 * u)
	_foto_sub.position = Vector2(T.x * 0.05, cy + d / 2 + 30 * u)


## Tela "SORRIA!": a câmera ao vivo num círculo, com o mascote do lado.
func foto_tela(ligado: bool, textura: Texture2D = null, personagem := "", titulo := "SORRIA!", sub := "") -> void:
	_foto_tela.visible = ligado
	if not ligado:
		return
	_layout_fotos()
	var cor := COR_BOB if personagem == "bob" else COR_MIA
	_foto_circulo.texture = textura
	_foto_circulo.material = material_foto(cor.lightened(0.35))
	_foto_selo.texture = _retratos.get(personagem)
	_foto_titulo.text = titulo
	_foto_sub.text = sub
	_foto_numero.text = ""
	_foto_circulo.scale = Vector2.ZERO
	var tw := create_tween()
	tw.tween_property(_foto_circulo, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pular(_foto_titulo)


func foto_contagem(n: int) -> void:
	_foto_numero.text = str(n) if n > 0 else ""
	if n > 0:
		_foto_numero.scale = Vector2.ONE * 1.6
		_foto_numero.modulate.a = 1.0
		var tw := create_tween()
		tw.tween_property(_foto_numero, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_foto_numero, "modulate:a", 0.75, 0.6)


## A foto tirada (ou o mascote, se a câmera não mandou imagem).
func foto_pronta(foto: Texture2D, personagem: String) -> void:
	_foto_numero.text = ""
	if foto != null:
		_foto_circulo.texture = foto
		_foto_titulo.text = "QUE FOTO LINDA!"
		_foto_sub.text = ""
	else:
		_foto_circulo.texture = _retratos.get(personagem)
		_foto_titulo.text = "VAMOS JOGAR!"
		_foto_sub.text = "(a câmera não mandou imagem)"
	_pular(_foto_titulo)
	_foto_circulo.scale = Vector2.ONE * 1.12
	create_tween().tween_property(_foto_circulo, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_estrelas_2d(_foto_circulo.position + _foto_circulo.size / 2, 26)


## Foto da criança pulando na tela (no strike).
func foto_destaque(foto: Texture2D, cor: Color, dur := 1.6) -> void:
	if foto == null:
		return
	var T := size
	var d: float = minf(T.x * 0.36, 360.0 * u)
	_foto_destaque.texture = foto
	_foto_destaque.material = material_foto(cor.lightened(0.3))
	_foto_destaque.size = Vector2(d, d)
	_foto_destaque.position = Vector2((T.x - d) / 2, T.y * (0.56 if retrato else 0.58) - d / 2)
	_foto_destaque.pivot_offset = _foto_destaque.size / 2
	_foto_destaque.visible = true
	_foto_destaque.scale = Vector2.ZERO
	_foto_destaque.rotation = -0.6
	_foto_destaque.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_foto_destaque, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_foto_destaque, "rotation", 0.08, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_foto_destaque, "rotation", -0.08, 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_foto_destaque, "rotation", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(maxf(dur - 1.2, 0.1))
	tw.tween_property(_foto_destaque, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _foto_destaque.visible = false)
	_estrelas_2d(_foto_destaque.position + _foto_destaque.size / 2, 22)


# ================================================================ marca Lazer & Sport
func _montar_marca() -> void:
	_marca_tela = Control.new()
	_marca_tela.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marca_tela.visible = false
	add_child(_marca_tela)
	_marca_fundo = TextureRect.new()
	_marca_fundo.texture = load(MARCA + "fundo.png")
	_marca_fundo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_marca_fundo.stretch_mode = TextureRect.STRETCH_SCALE
	_marca_fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marca_tela.add_child(_marca_fundo)
	var sh := load("res://shaders/brilho_marca.gdshader") as Shader
	for nome in ["placa", "alvo"]:
		var t := TextureRect.new()
		t.texture = load(MARCA + nome + ".png")
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("pos", -1.0)
		t.material = m
		if nome == "alvo":
			_marca_alvo = t
		else:
			_marca_placa = t
	# véu escuro redondo atrás da logo (quando ela aparece sobre o 3D)
	_marca_veu = TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.03, 0.12, 0.72))
	g.set_color(1, Color(0.0, 0.03, 0.12, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	_marca_veu.texture = gt
	_marca_veu.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_marca_veu.stretch_mode = TextureRect.STRETCH_SCALE
	_marca_veu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marca_tela.add_child(_marca_veu)
	# o alvo fica atrás da placa (como na logo)
	_marca_tela.add_child(_marca_alvo)
	_marca_tela.add_child(_marca_placa)
	# selo GAMES embaixo da placa: LAZER & SPORT GAMES
	_marca_games = TextureRect.new()
	_marca_games.texture = load(MARCA + "games.png")
	_marca_games.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_marca_games.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_marca_games.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marca_tela.add_child(_marca_games)
	_marca_texto = rotulo("apresenta", 52, Color(1, 1, 1, 0.92), 0, MARINHO)
	_marca_tela.add_child(_marca_texto)


func _layout_marca(T: Vector2) -> void:
	_marca_fundo.size = T
	var lw: float = minf(T.x * 0.82, T.y * 0.62 / PROPORCAO_LOGO)
	var lh := lw * PROPORCAO_LOGO
	var centro_y := 0.4 if _marca_veu.visible else 0.46
	var origem := Vector2((T.x - lw) / 2, T.y * centro_y - lh / 2)
	var ref := float(_marca_placa.texture.get_width())     # a placa tem a largura da logo inteira
	for par in [[_marca_alvo, CENTRO_ALVO], [_marca_placa, CENTRO_PLACA]]:
		var t: TextureRect = par[0]
		var tam := Vector2(t.texture.get_size()) * (lw / ref)
		t.size = tam
		t.position = origem + Vector2(lw, lh) * (par[1] as Vector2) - tam / 2
		t.pivot_offset = tam / 2
	var gw := lw * 0.46
	var gh := gw * 188.0 / 616.0
	_marca_games.size = Vector2(gw, gh)
	_marca_games.position = Vector2((T.x - gw) / 2, origem.y + lh + 10 * u)
	_marca_games.pivot_offset = _marca_games.size / 2
	var vw := maxf(T.x, T.y) * 1.25
	_marca_veu.size = Vector2(vw, vw)
	_marca_veu.position = origem + Vector2(lw, lh) * 0.5 - _marca_veu.size / 2
	_tamanho_rotulo(_marca_texto, 52 * u)
	_marca_texto.label_settings.shadow_size = int(4 * u)
	_marca_texto.size = Vector2(T.x, 80 * u)
	_marca_texto.position = Vector2(0, origem.y + lh + gh + 26 * u)


## Abertura: a logo aparece (sobre o fundo azul da inicialização ou, com
## `sobre_3d`, por cima do strike da abertura), o dardo "acerta" o alvo
## (tremidinha + estrelas), sobe o selo GAMES, passa um brilho e entra
## "apresenta".
func marca(ligado: bool, na_hora := false, sobre_3d := false) -> void:
	if not ligado:
		if not _marca_tela.visible:
			return
		if na_hora:
			_marca_tela.visible = false
			return
		var tw := create_tween()
		tw.tween_property(_marca_tela, "modulate:a", 0.0, 0.4)
		tw.tween_callback(func(): _marca_tela.visible = false)
		return
	_marca_fundo.visible = not sobre_3d
	_marca_veu.visible = sobre_3d
	_layout_marca(size)
	_marca_tela.visible = true
	_marca_tela.modulate.a = 1.0
	_marca_texto.modulate.a = 0.0
	_marca_alvo.scale = Vector2.ONE
	_marca_games.visible = true
	_marca_games.scale = Vector2.ZERO
	var tg := create_tween()
	tg.tween_interval(0.55)
	tg.tween_property(_marca_games, "scale", Vector2(1.12, 1.12), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tg.tween_property(_marca_games, "scale", Vector2.ONE, 0.18)
	if sobre_3d:
		# logo "estoura" na tela
		for t in [_marca_alvo, _marca_placa]:
			(t as Control).scale = Vector2.ZERO
			var tp := create_tween()
			tp.tween_interval(0.0 if t == _marca_placa else 0.08)
			tp.tween_property(t, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_marca_veu.modulate.a = 0.0
		create_tween().tween_property(_marca_veu, "modulate:a", 1.0, 0.3)
		_atrasado(0.12, func(): _estrelas_2d(_marca_placa.position + _marca_placa.size * 0.5, 36))
	var tw := create_tween()
	tw.tween_interval(0.3)
	tw.tween_property(_marca_alvo, "scale", Vector2(1.07, 0.94), 0.07)
	tw.tween_property(_marca_alvo, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_atrasado(0.32, func(): _estrelas_2d(_marca_alvo.position + _marca_alvo.size * Vector2(0.43, 0.5), 30))
	for t in [_marca_placa, _marca_alvo]:
		var m := (t as TextureRect).material as ShaderMaterial
		m.set_shader_parameter("pos", -1.0)
		var tb := create_tween()
		tb.tween_interval(0.7 if t == _marca_placa else 0.6)
		tb.tween_method(func(v: float): m.set_shader_parameter("pos", v), -0.4, 1.6, 0.9).set_trans(Tween.TRANS_SINE)
	var tt := create_tween()
	tt.tween_interval(1.0)
	tt.tween_property(_marca_texto, "modulate:a", 1.0, 0.4)


# ================================================================ layout responsivo
func layout() -> void:
	var T := Tela.tamanho()
	size = T
	position = Vector2.ZERO
	retrato = T.y >= T.x
	u = min(T.x, T.y) / 1080.0
	tela3d.position = Vector2.ZERO
	tela3d.size = T
	_flash.size = T
	_centro.size = T
	_tarja_cima.position = Vector2.ZERO
	_tarja_cima.size = Vector2(T.x, _tarja_cima.size.y)
	_tarja_baixo.size = Vector2(T.x, _tarja_baixo.size.y)
	_tarja_baixo.position = Vector2(0, T.y - _tarja_baixo.size.y)
	# placar
	var usados := 0
	for c in _cartoes:
		if c.get("usado", false):
			usados += 1
	var margem := 26 * u
	var larg: float
	var alt := 200 * u
	if retrato:
		larg = (T.x - margem * 3) / 2 if usados == 2 else T.x * 0.62
	else:
		larg = 560 * u
	for i in 2:
		var c: Dictionary = _cartoes[i]
		var p: Control = c["painel"]
		p.size = Vector2(larg, alt)
		var x: float
		if usados == 1:
			x = (T.x - larg) / 2 if retrato else margem
		else:
			x = margem if i == 0 else T.x - larg - margem
		p.position = Vector2(x, margem + 40 * u)
		p.pivot_offset = p.size / 2
		var av: TextureRect = c["avatar"]
		if c.get("foto", false):
			# foto da criança dentro do cartão + o mascote de "selo"
			av.size = Vector2(alt * 0.86, alt * 0.86)
			av.position = Vector2(alt * 0.07, alt * 0.07)
			var selo: TextureRect = c["selo"]
			selo.size = Vector2(alt * 0.5, alt * 0.5)
			selo.position = Vector2(alt * 0.55, alt * 0.52)
		else:
			av.size = Vector2(alt * 1.15, alt * 1.15)
			av.position = Vector2(-alt * 0.12, -alt * 0.32)
		var nome: Label = c["nome"]
		_tamanho_rotulo(nome, 42 * u)
		nome.label_settings.outline_size = int(10 * u)
		nome.size = Vector2(larg - alt * 1.0, 54 * u)
		nome.position = Vector2(alt * 0.98, 10 * u)
		var pts: Label = c["pontos"]
		_tamanho_rotulo(pts, 78 * u)
		pts.label_settings.outline_size = int(14 * u)
		pts.size = Vector2(larg - alt * 1.0 - 20 * u, 88 * u)
		pts.position = Vector2(alt * 0.98, 52 * u)
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var rod: HBoxContainer = c["rodadas"]
		rod.position = Vector2(alt * 0.98, alt - 64 * u)
		rod.size = Vector2(larg - alt, 50 * u)
		rod.add_theme_constant_override("separation", int(8 * u))
	var base_y := margem + 40 * u + alt + 16 * u
	_tamanho_rotulo(_info, 34 * u)
	_info.label_settings.outline_size = int(9 * u)
	if retrato:
		_info.size = Vector2(T.x, 48 * u)
		_info.position = Vector2(0, base_y)
		_bolas_box.size = Vector2(T.x, 40 * u)
		_bolas_box.position = Vector2(0, base_y + 52 * u)
	else:
		_info.size = Vector2(larg, 48 * u)
		_info.position = Vector2(margem, base_y)
		_bolas_box.size = Vector2(larg, 40 * u)
		_bolas_box.position = Vector2(margem, base_y + 52 * u)
	_bolas_box.add_theme_constant_override("separation", int(14 * u))
	# mapa dos pinos (canto)
	var ms := 190 * u
	_mapa.size = Vector2(ms, ms * 0.86)
	_mapa.position = Vector2(T.x - ms - margem, base_y + 8 * u) if retrato else Vector2(T.x - ms - margem, margem + 300 * u)
	for n in _mapa_pontos:
		var pos := Pinos.posicao_do_pino(n)
		var d: Panel = _mapa_pontos[n]
		var r := 24 * u
		d.size = Vector2(r, r)
		var fx := pos.x / (Mundo.ESPACO_PINOS * 1.5)  # -1..1
		var fy := (Mundo.Z_PINO1 - pos.z) / (Mundo.FILEIRA * 3.0)  # 0..1 (fundo em cima)
		d.position = Vector2(ms / 2 + fx * ms * 0.36 - r / 2, ms * 0.86 * (0.78 - fy * 0.56) - r / 2)
	# toque e convite
	_toque.position = Vector2.ZERO
	_toque.size = T
	var y_aviso := T.y - (330 if retrato else 210) * u
	_tamanho_rotulo(_aviso, 84 * u)
	_aviso.label_settings.outline_size = int(20 * u)
	_aviso.size = Vector2(T.x, 120 * u)
	_aviso.position = Vector2(0, y_aviso)
	_aviso.pivot_offset = _aviso.size / 2
	_tamanho_rotulo(_aviso_sub, 44 * u)
	_aviso_sub.label_settings.outline_size = int(11 * u)
	_aviso_sub.size = Vector2(T.x, 64 * u)
	_aviso_sub.position = Vector2(0, y_aviso + 112 * u)
	_aviso_sub.pivot_offset = _aviso_sub.size / 2
	_tamanho_rotulo(_sequencia, 40 * u)
	_sequencia.label_settings.outline_size = int(10 * u)
	_sequencia.size = Vector2(T.x if retrato else larg, 56 * u)
	_sequencia.position = Vector2(0 if retrato else margem, base_y + 100 * u)
	_sequencia.pivot_offset = _sequencia.size / 2
	# atração
	var lw: float = min(T.x * 0.9, 980 * u) if retrato else T.x * 0.36
	var lt := _logo.texture
	var lh: float = lw * (float(lt.get_height()) / float(lt.get_width()) if lt else 0.4)
	_logo.size = Vector2(lw, lh)
	if retrato:
		_logo.position = Vector2((T.x - lw) / 2, T.y * 0.05)
	else:
		_logo.position = Vector2(T.x * 0.03, T.y * 0.05)
	_logo.pivot_offset = _logo.size / 2
	var bw: float = minf(T.x * 0.78, 780 * u) if retrato else T.x * 0.34
	var bh := 150 * u
	_aperte_botao.size = Vector2(bw, bh)
	if retrato:
		_aperte_botao.position = Vector2((T.x - bw) / 2, T.y * 0.69)
	else:
		_aperte_botao.position = Vector2(T.x * 0.03 + (lw - bw) / 2, T.y * 0.6)
	_aperte_botao.pivot_offset = _aperte_botao.size / 2
	_tamanho_rotulo(_aperte, 84 * u)
	_aperte.label_settings.shadow_size = int(3 * u)
	_aperte.label_settings.shadow_offset = Vector2(0, 3 * u)
	_aperte.size = Vector2(bw, bh - 18 * u)
	_aperte.position = Vector2.ZERO
	_caber(_aperte, 84 * u, bw - 90 * u)
	_tamanho_rotulo(_recorde, 40 * u)
	_recorde.label_settings.outline_size = int(8 * u)
	_tamanho_rotulo(_creditos, 30 * u)
	_creditos.label_settings.outline_size = int(8 * u)
	_creditos.size = Vector2(T.x, 46 * u)
	_creditos.position = Vector2(0, T.y - (90 if retrato else 64) * u)
	# quantos vão jogar
	_layout_jogadores(T)
	_layout_etapas(T)
	# seleção
	var sw: float = minf(T.x * 0.9, 900 * u)
	_sel_titulo.size = Vector2(sw, 130 * u)
	_sel_titulo.position = Vector2((T.x - sw) / 2, 112 * u)
	_sel_titulo.pivot_offset = _sel_titulo.size / 2
	var t := _sel_titulo.get_node("titulo") as Label
	_tamanho_rotulo(t, 74 * u)
	t.label_settings.outline_size = int(16 * u)
	t.size = Vector2(sw, 116 * u)
	t.position = Vector2.ZERO
	for i in 2:
		var p := _sel_placas[i]
		p.size = Vector2(330, 116) * u
		if p.position == Vector2.ZERO:
			p.position = Vector2(T.x * (0.27 if i == 0 else 0.73) - p.size.x / 2, T.y * 0.64)
		var l := _sel_nomes[i]
		_tamanho_rotulo(l, 70 * u)
		l.label_settings.outline_size = int(16 * u)
		l.size = Vector2(p.size.x, p.size.y - 14 * u)
		l.position = Vector2.ZERO
	var dw: float = minf(T.x * 0.9, 860 * u)
	var dh := 230 * u
	_sel_dica.size = Vector2(dw, dh)
	_sel_dica.position = Vector2((T.x - dw) / 2, T.y - dh - (60 if retrato else 24) * u)
	_tamanho_rotulo(_sel_texto, 34 * u)
	_sel_texto.label_settings.outline_size = int(9 * u)
	_sel_texto.size = Vector2(dw, 100 * u)
	_sel_texto.position = Vector2(0, 8 * u)
	_layout_sensores(_sel_sensores, minf(dw - 80 * u, 420 * u))
	_sel_sensores.position = Vector2((dw - _sel_sensores.size.x) / 2, 112 * u)
	var mw: float = min(T.x * 0.86, 860 * u)
	# inatividade
	_inativo.size = Vector2(mw, 600 * u)
	_inativo.position = (T - _inativo.size) / 2
	_aviso_android.size = Vector2(minf(T.x - 60 * u, 1500 * u), 230 * u)
	_aviso_android.position = Vector2((T.x - _aviso_android.size.x) / 2, 30 * u)
	_tamanho_rotulo(_aviso_android_texto, 40 * u)
	_aviso_android_texto.label_settings.outline_size = int(10 * u)
	_aviso_android_texto.size = _aviso_android.size - Vector2(60 * u, 20 * u)
	_aviso_android_texto.position = Vector2(30 * u, 10 * u)
	_tamanho_rotulo(_inativo_texto, 54 * u)
	_inativo_texto.label_settings.outline_size = int(12 * u)
	_inativo_texto.size = _inativo.size
	_inativo_texto.position = Vector2.ZERO
	if _foto_tela.visible:
		_layout_fotos()
	if _marca_tela.visible:
		_layout_marca(T)
	if _atracao.visible:
		atracao(true, _recorde.text, _creditos.text, _rec_foto.texture, _melhores_hoje)


func _process(delta: float) -> void:
	_tempo += delta
	# placar: pontos contando
	for c in _cartoes:
		if c.get("usado", false) and c["valor"] < float(c["alvo"]):
			c["valor"] = min(float(c["alvo"]), c["valor"] + delta * max(60.0, (float(c["alvo"]) - c["valor"]) * 3.0))
			(c["pontos"] as Label).text = str(int(c["valor"]))
	if _aviso.visible:
		_aviso.scale = Vector2.ONE * (1.0 + sin(_tempo * 5.0) * 0.05)
		_aviso_sub.modulate.a = 0.6 + 0.4 * absf(sin(_tempo * 2.6))
	if _atracao.visible:
		_logo.scale = Vector2.ONE * (1.0 + sin(_tempo * 2.2) * 0.025)
		_logo.rotation = sin(_tempo * 1.3) * 0.02
		_aperte_botao.scale = Vector2.ONE * (1.0 + sin(_tempo * 3.0) * 0.035)
		_aperte_botao.realcar(0.35 + 0.35 * absf(sin(_tempo * 3.0)))
	if _jog.visible:
		_jog_cartoes[_jog_n - 1].realcar(0.7 + 0.3 * sin(_tempo * 6.0))
		_jog_cartoes[_jog_n - 1].scale = Vector2.ONE * (1.05 + sin(_tempo * 6.0) * 0.015)
		_jog_cartoes[2 - _jog_n].scale = Vector2.ONE * 0.94
	if _selecao.visible:
		_sel_placas[_sel_destaque].realcar(0.7 + 0.3 * sin(_tempo * 6.0))
	if _replay_ponto.visible:
		_replay_ponto.modulate.a = 1.0 if fposmod(_tempo, 1.0) < 0.6 else 0.15
