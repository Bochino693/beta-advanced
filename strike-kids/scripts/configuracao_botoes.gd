extends Control

## CONFIGURAÇÃO DOS BOTÕES DA ZERO DELAY — um botão de cada vez, na
## sequência da máquina. O que for apertado aqui é gravado na TV Box e
## passa a valer no jogo inteiro (ArcadeControls).
##
## A placa é aceita do jeito que o Android entregar: botão de joystick ou,
## em placas genéricas no modo teclado, tecla. A linha "SINAL RECEBIDO"
## mostra na hora o que chegou — é o diagnóstico da placa.
## Se ninguém apertar nada por 20 segundos, volta ao jogo sem mudar nada.
## Abre por cima do jogo pausado (Principal.abrir_menu), como o menu do
## operador.
## (Mesma lógica do Dragon Bowling Pro Ultra.)

const JOGO := "res://cenas/principal.tscn"
const ESPERA_MAXIMA_MS := 20000
const PULAR_OPCIONAL_MS := 4000

var _passo := 0
var _botoes := {}
var _segurando := ""
var _ultimo_toque_ms := 0
var _terminado := false

var _pedido: Label
var _dica: Label
var _sinal: Label
var _linhas: Array[Label] = []
var _rodape: Label
var _fonte: Font


func _ready() -> void:
	Tela.cobrir(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fonte = Materiais.fonte("fredoka_700")
	var T := Tela.tamanho()
	var u: float = min(T.x, T.y) / 1080.0
	var fundo := ColorRect.new()
	fundo.color = Color(0.03, 0.09, 0.22)
	fundo.size = T
	add_child(fundo)
	var y := T.y * 0.06
	_rotulo("CONFIGURAR BOTÕES DA PLACA", y, 54 * u, Color("#7FE7FF"))
	_pedido = _rotulo("", y + 120 * u, 76 * u, Color("#FFD43B"))
	_dica = _rotulo("APERTE O BOTÃO DA MÁQUINA", y + 230 * u, 36 * u, Color(1, 1, 1, 0.8))
	_sinal = _rotulo("SINAL RECEBIDO: nenhum ainda", y + 300 * u, 30 * u, Color("#7FE7FF"))
	y += 420 * u
	for item: Array in ArcadeControls.SEQUENCIA:
		_linhas.append(_rotulo("", y, 36 * u, Color(1, 1, 1, 0.55)))
		y += 82 * u
	_rodape = _rotulo("", T.y - 120 * u, 28 * u, Color(1, 1, 1, 0.6))
	_ultimo_toque_ms = Time.get_ticks_msec()
	_atualizar()


func _rotulo(texto: String, y: float, tam: float, cor: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.position = Vector2(0, y)
	l.size = Vector2(Tela.tamanho().x, tam * 1.6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font = _fonte
	ls.font_size = int(tam)
	ls.font_color = cor
	ls.outline_size = int(tam * 0.2)
	ls.outline_color = Color("#0B1F45")
	l.label_settings = ls
	add_child(l)
	return l


func _atualizar() -> void:
	var total := ArcadeControls.SEQUENCIA.size()
	if _passo < total:
		_pedido.text = str(ArcadeControls.SEQUENCIA[_passo][1]).get_slice("  ·  ", 0)
		if _passo >= ArcadeControls.OBRIGATORIOS:
			var falta: int = max(0, int(ceil((PULAR_OPCIONAL_MS - (Time.get_ticks_msec() - _ultimo_toque_ms)) / 1000.0)))
			_dica.text = "APERTE, OU AGUARDE %d s PARA PULAR" % falta
	for i in total:
		var acao: String = ArcadeControls.SEQUENCIA[i][0]
		var nome: String = ArcadeControls.SEQUENCIA[i][1]
		var linha := _linhas[i]
		if _botoes.has(acao):
			linha.text = "OK  %s   →   %s" % [nome, ArcadeControls.texto_do_codigo(_botoes[acao])]
			linha.label_settings.font_color = Color("#8DFF6A")
		elif i == _passo:
			linha.text = "▶  %s" % nome
			linha.label_settings.font_color = Color("#FFD43B")
		else:
			linha.text = "%s   (atual: %s)" % [nome, ArcadeControls.texto_de(acao)]
			linha.label_settings.font_color = Color(1, 1, 1, 0.45)
	var restante: int = max(0, int(ceil((ESPERA_MAXIMA_MS - (Time.get_ticks_msec() - _ultimo_toque_ms)) / 1000.0)))
	_rodape.text = "SEM TOQUE, VOLTA AO JOGO SEM ALTERAR EM %d s" % restante


func _process(_delta: float) -> void:
	if _terminado:
		return
	if _passo >= ArcadeControls.OBRIGATORIOS and _segurando == "" \
			and Time.get_ticks_msec() - _ultimo_toque_ms > PULAR_OPCIONAL_MS:
		_concluir()
		return
	if Time.get_ticks_msec() - _ultimo_toque_ms > ESPERA_MAXIMA_MS:
		_terminado = true
		_voltar()
		return
	_atualizar()


func _input(event: InputEvent) -> void:
	ArcadeControls.eh_da_placa(event)
	get_viewport().set_input_as_handled()
	if _terminado or event.is_echo():
		return
	if event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode in [KEY_BACK, KEY_ESCAPE]:
		cancelar()   # VOLTAR do controle remoto (ou Esc): sai sem mudar nada
		return
	var codigo := ArcadeControls.codigo_do_evento(event)
	if codigo == "":
		return
	if not event.is_pressed():
		if codigo == _segurando:
			_segurando = ""
		return
	_ultimo_toque_ms = Time.get_ticks_msec()
	var aparelho := Input.get_joy_name(event.device) if event is InputEventJoypadButton else "placa no modo teclado"
	_sinal.text = "SINAL RECEBIDO: %s  ·  %s" % [ArcadeControls.texto_do_codigo(codigo), aparelho]
	if _segurando != "":
		return
	if codigo in _botoes.values():
		_dica.text = "ESTE BOTÃO JÁ FOI USADO — APERTE OUTRO"
		return
	_segurando = codigo
	_botoes[ArcadeControls.SEQUENCIA[_passo][0]] = codigo
	_passo += 1
	_dica.text = "APERTE O BOTÃO DA MÁQUINA"
	_atualizar()
	if _passo >= ArcadeControls.SEQUENCIA.size():
		_concluir()


func _concluir() -> void:
	_terminado = true
	ArcadeControls.gravar(_botoes)
	_pedido.text = "PRONTO!"
	_dica.text = "GRAVADO. PARA REFAZER: BOTÃO DE CONFIGURAÇÃO, OU SEGURE UM BOTÃO 10 s NA TELA INICIAL"
	await get_tree().create_timer(1.6).timeout
	_voltar()


## Sai sem gravar nada (VOLTAR do controle remoto da TV Box ou Esc).
func cancelar() -> void:
	if _terminado:
		return
	_terminado = true
	_voltar()


## Volta ao jogo (aberto por cima dele: o jogo ficou pausado por baixo).
func _voltar() -> void:
	var jogo := get_tree().current_scene
	if jogo != null and jogo != self and jogo.has_method("fechar_menu"):
		jogo.fechar_menu()
	else:
		get_tree().change_scene_to_file.call_deferred(JOGO)
