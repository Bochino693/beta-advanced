extends Control

## MENU DO OPERADOR: o botão de CONFIGURAÇÃO da máquina (no Arduino, ou o
## R2 da Zero Delay / tecla 9) entra aqui, e apertado de novo volta ao jogo.
## Aqui se testa tudo: os sensores (ao vivo), a porta (trava), a câmera.
##
## Navegação com os próprios sensores/botões da máquina:
##   X (meio-esquerda) = sobe        V (meio-direita) = desce
##   Z (esquerda)      = diminui     B (direita)      = aumenta
##   C (centro) ou START = escolher  Configuração     = voltar ao jogo
## Pelo CONTROLE REMOTO da TV Box: setas (cima/baixo andam, esquerda/direita
## mudam o valor), OK escolhe, VOLTAR (ou MENU) sai. No PC: setas, Enter e Esc.
##
## O menu abre POR CIMA do jogo pausado (Principal.abrir_menu): nada do
## jogo é desmontado, e sair dele é na hora.

const JOGO := "res://cenas/principal.tscn"
const BOTOES := "res://cenas/configuracao_botoes.tscn"

## [rótulo, seção, chave, tipo, opções]
const ITENS := [
	["Rodadas por jogador", "jogo", "rodadas", "int", [1, 10]],
	["Bolas por rodada", "jogo", "tentativas", "int", [1, 3]],
	["Dificuldade", "jogo", "dificuldade", "lista", ["facil", "normal", "dificil"]],
	["Para-choques nas canaletas", "jogo", "protecao_canaleta", "bool", []],
	["Replay do strike", "jogo", "replay_strike", "bool", []],
	["Demonstração na tela inicial", "jogo", "demo", "bool", []],
	["Modo livre (sem ficha)", "jogo", "modo_livre", "bool", []],
	["Foto das crianças (câmera)", "jogo", "foto", "bool", []],
	["Giro da câmera", "jogo", "camera_giro", "lista", [0, 90, 180, 270]],
	["Espelhar a câmera", "jogo", "camera_espelho", "bool", []],
	["Fichas por partida", "jogo", "creditos_por_partida", "int", [1, 5]],
	["Tempo sem jogar até o aviso (s)", "jogo", "tempo_inatividade", "int", [20, 180]],
	["Volume da música", "som", "musica", "vol", []],
	["Volume dos efeitos", "som", "efeitos", "vol", []],
	["Som na demonstração", "som", "som_na_demo", "bool", []],
	["Qualidade gráfica", "video", "qualidade", "lista", ["auto", "alta", "media", "baixa"]],
	["Cenário (fundo)", "video", "cenario", "lista", ["leve", "completo"]],
	["Nitidez do 3D (resolução)", "video", "nitidez", "lista", ["auto", "100%", "90%", "80%", "70%"]],
	["Mostrar desempenho na tela (QPS)", "video", "medidor", "bool", []],
	["> TESTE DE DESEMPENHO (20 s)", "", "desempenho", "acao", []],
	["Giro da tela", "tela", "giro", "lista", [1, -1, 0]],
	["> TESTE DOS SENSORES", "", "teste", "acao", []],
	["> CALIBRAR SENSORES (pista vazia)", "", "calibrar", "acao", []],
	["Sensores invertidos (direita/esquerda)", "arduino", "sensores_invertidos", "bool", []],
	["> TESTE DA PORTA (trava das bolas)", "", "porta", "acao", []],
	["Porta invertida", "arduino", "porta_invertida", "bool", []],
	["> TESTE DA CÂMERA", "", "camera", "acao", []],
	["> CONFIGURAR BOTÕES DA PLACA", "", "botoes", "acao", []],
	["> ZERAR RECORDES", "", "recordes", "acao", []],
	["> RESTAURAR PADRÃO DE FÁBRICA", "", "padrao", "acao", []],
	["> VOLTAR AO JOGO", "", "voltar", "acao", []],
]
const NOMES := {"facil": "FÁCIL", "normal": "NORMAL", "dificil": "DIFÍCIL", "auto": "AUTOMÁTICA", "alta": "ALTA",
	"media": "MÉDIA", "baixa": "BAIXA", "leve": "LEVE (TV Box)", "completo": "COMPLETO", 1: "1 (topo à esquerda)", -1: "-1 (topo à direita)", 0: "0 (sem giro)",
	90: "90°", 180: "180°", 270: "270°"}

var _sel := 0
var _linhas: Array[Label] = []
var _fonte: Font
var _info: Label
var _teste := false
var _teste_contagem := [0, 0, 0, 0, 0]
var _teste_rotulo: Label
var _camera := false
var _camera_tela: TextureRect
var _camera_ms := 0
var _camera_t := 0.0
var _porta := false            # teste da porta
var _calibrando := false       # calibração dos sensores
var _topo := 0                 # rolagem da lista (tela deitada)
var _visiveis := 0
var _esp := 0.0
var u := 1.0


func _ready() -> void:
	_fonte = Materiais.fonte("fredoka_700")
	_montar()
	Fotos.mudou.connect(_atualizar)
	ArduinoBridge.mudou.connect(_arduino_mudou)
	# no menu a porta das bolas fica fechada; aqui pode aparecer a janela
	# de permissão USB do Arduino
	ArduinoBridge.porta(false)
	ArduinoBridge.na_espera(true)
	_atualizar()


func _montar() -> void:
	Tela.cobrir(self)
	var T := Tela.tamanho()
	u = min(T.x, T.y) / 1080.0
	var fundo := ColorRect.new()
	fundo.color = Color(0.03, 0.09, 0.22)
	fundo.size = T
	add_child(fundo)
	var titulo := _rotulo("STRIKE KIDS · OPERADOR", Vector2(0, 40 * u), 58 * u, Color("#FFD43B"))
	titulo.size.x = T.x
	# a lista inteira se couber; senão, uma janela que rola com a seleção
	var area: float = T.y - 420 * u
	_esp = clampf(area / ITENS.size(), 44.0 * u, 68.0 * u)
	_visiveis = mini(ITENS.size(), int(area / _esp))
	for i in ITENS.size():
		var l := _rotulo("", Vector2(60 * u, 150 * u), min(34 * u, _esp * 0.55), Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.size.x = T.x - 120 * u
		_linhas.append(l)
	_info = _rotulo("", Vector2(0, T.y - 250 * u), 26 * u, Color(1, 1, 1, 0.75))
	_info.size = Vector2(T.x, 220 * u)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_teste_rotulo = _rotulo("", Vector2(0, T.y * 0.35), 54 * u, Color.WHITE)
	_teste_rotulo.size = Vector2(T.x, 500 * u)
	_teste_rotulo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_teste_rotulo.visible = false
	_camera_tela = TextureRect.new()
	_camera_tela.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_camera_tela.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_camera_tela.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var lado: float = minf(T.x * 0.8, T.y * 0.5)
	_camera_tela.size = Vector2(lado, lado)
	_camera_tela.position = Vector2((T.x - lado) / 2, T.y * 0.3)
	_camera_tela.visible = false
	add_child(_camera_tela)


## A tela girou (giro da tela mudou): monta o menu de novo no tamanho novo.
func _remontar() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_linhas.clear()
	_topo = 0
	_montar()
	_atualizar()


## Volta ao jogo (que ficou pausado por baixo do menu).
func _sair() -> void:
	var jogo := get_tree().current_scene
	if jogo != null and jogo != self and jogo.has_method("fechar_menu"):
		jogo.fechar_menu()
	else:
		get_tree().change_scene_to_file.call_deferred(JOGO)


func _rotulo(texto: String, pos: Vector2, tam: float, cor: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.position = pos
	l.size = Vector2(Tela.tamanho().x, tam * 1.5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font = _fonte
	ls.font_size = int(tam)
	ls.font_color = cor
	ls.outline_size = int(tam * 0.18)
	ls.outline_color = Color("#0B1F45")
	l.label_settings = ls
	add_child(l)
	return l


func _valor_texto(item: Array) -> String:
	if item[3] == "acao":
		return ""
	var v = Ajustes.valor(item[1], item[2]) if item[1] != "tela" else Tela.giro
	if item[2] == "cenario":
		v = Ajustes.cenario()
	match item[3]:
		"bool":
			return "SIM" if bool(v) else "NÃO"
		"vol":
			return "%d" % int(round(float(v) * 10.0))
		"lista":
			return str(NOMES.get(v, str(v)))
	return str(v)


func _atualizar() -> void:
	if _sel < _topo:
		_topo = _sel
	elif _sel >= _topo + _visiveis:
		_topo = _sel - _visiveis + 1
	var em_teste := _teste or _camera or _porta or _calibrando
	for i in ITENS.size():
		var item: Array = ITENS[i]
		var l := _linhas[i]
		var v := _valor_texto(item)
		var j := i - _topo
		l.visible = not em_teste and j >= 0 and j < _visiveis
		l.position.y = 150 * u + j * _esp
		l.text = ("▶ " if i == _sel else "   ") + str(item[0]) + ("" if v == "" else ":   " + v)
		l.label_settings.font_color = Color("#FFD43B") if i == _sel else Color(1, 1, 1, 0.85)
	var rolar := ""
	if _visiveis < ITENS.size():
		rolar = "   (%d de %d)" % [_sel + 1, ITENS.size()]
	_info.text = "X sobe · V desce · Z diminui · B aumenta · C/START escolhe · CONFIGURAÇÃO volta%s\n" % rolar + \
		"Controle da TV Box: setas andam e mudam · OK escolhe · VOLTAR sai\n" + \
		"Partidas: %d   ·   Strikes: %d   ·   Moedas: %d\n%s\nCâmera: %s\n%s" % [Ajustes.contador("partidas"),
		Ajustes.contador("strikes"), Ajustes.contador("moedas"), ArduinoBridge.status, Fotos.texto_status(),
		texto_aparelho()]


## Qual é o aparelho (para saber qual TV Box é — a TX9, por exemplo, sai
## com chips diferentes): modelo, sistema, placa de vídeo, núcleos e memória.
static func texto_aparelho() -> String:
	var gb := float(OS.get_memory_info().get("physical", 0)) / 1073741824.0
	return "Aparelho: %s · %s %s · %s · %d núcleos%s" % [OS.get_model_name(), OS.get_name(), OS.get_version(),
		RenderingServer.get_video_adapter_name(), OS.get_processor_count(), " · %.1f GB" % gb if gb > 0.0 else ""]


func _arduino_mudou() -> void:
	if _teste:
		_mostrar_teste("")
	elif _porta:
		_mostrar_porta()
	elif _calibrando:
		_mostrar_calibracao()
	else:
		_atualizar()


func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		ArcadeControls.eh_da_placa(event)
		return
	get_viewport().set_input_as_handled()
	var cmd := ""
	if ArcadeControls.eh_config(event):
		cmd = "sair"
	elif ArcadeControls.eh_start(event):
		cmd = "ok"
	else:
		var z := ArcadeControls.tecla_jogada(event)
		cmd = {"X": "sobe", "V": "desce", "Z": "menos", "B": "mais", "C": "ok"}.get(z, "")
		if _teste and z != "":
			var i := ["Z", "X", "C", "V", "B"].find(z)
			_teste_contagem[i] += 1
			_mostrar_teste(z)
			return
	if cmd == "" and event is InputEventKey:
		# teclado do PC e CONTROLE REMOTO da TV Box (no Android: setas = D-pad,
		# OK = Enter, VOLTAR = Back, e a tecla MENU)
		cmd = {KEY_UP: "sobe", KEY_DOWN: "desce", KEY_LEFT: "menos", KEY_RIGHT: "mais",
			KEY_ENTER: "ok", KEY_KP_ENTER: "ok", KEY_ESCAPE: "sair", KEY_BACK: "sair",
			KEY_MENU: "sair"}.get((event as InputEventKey).keycode, "")
	if cmd != "":
		comando(cmd)


## Um comando do menu (dos botões da máquina, do teclado ou do controle
## remoto da TV Box — o VOLTAR do Android chega pelo Principal).
func comando(cmd: String) -> void:
	if _camera and (cmd == "menos" or cmd == "mais"):
		# no teste da câmera, Z / B giram a imagem (câmera montada de lado)
		var g := (int(Ajustes.valor("jogo", "camera_giro")) + (90 if cmd == "mais" else 270)) % 360
		Ajustes.definir("jogo", "camera_giro", g)
		Sons.tocar("selecao")
		return
	if _porta and cmd == "ok":
		# teste da porta: C ou START abre/fecha; CONFIGURAÇÃO sai
		ArduinoBridge.porta(not ArduinoBridge.porta_quer)
		Sons.tocar("selecao")
		_mostrar_porta()
		return
	if _teste or _camera or _porta or _calibrando:
		if cmd == "sair" or cmd == "ok":
			_sair_do_teste()
		return
	match cmd:
		"sobe":
			_sel = (_sel - 1 + ITENS.size()) % ITENS.size()
		"desce":
			_sel = (_sel + 1) % ITENS.size()
		"menos":
			_mudar(-1)
		"mais":
			_mudar(1)
		"ok":
			_acao()
		"sair":
			_sair()
			return
	_atualizar()


func _mudar(d: int) -> void:
	var item: Array = ITENS[_sel]
	var v = Ajustes.valor(item[1], item[2]) if item[1] != "tela" else Tela.giro
	if item[2] == "cenario":
		v = Ajustes.cenario()
	match item[3]:
		"int":
			v = clampi(int(v) + d, item[4][0], item[4][1])
		"bool":
			v = not bool(v)
		"vol":
			v = clampf(snappedf(float(v) + d * 0.1, 0.1), 0.0, 1.0)
		"lista":
			var op: Array = item[4]
			v = op[(op.find(v) + d + op.size()) % op.size()]
		_:
			return
	if item[1] == "tela":
		Ajustes.definir("tela", "giro", v)
		Tela.definir_giro(int(v))
		Sons.tocar("selecao")
		_remontar()
		return
	Ajustes.definir(item[1], item[2], v)
	if item[2] == "foto":
		Fotos.iniciar()
		if bool(v):
			Fotos.pedir_permissao_agora()
	if item[2] == "porta_invertida":
		ArduinoBridge.reenviar_porta()
	Sons.atualizar_volume()
	Sons.tocar("selecao")


func _acao() -> void:
	var item: Array = ITENS[_sel]
	if item[3] != "acao":
		_mudar(1)
		return
	match item[2]:
		"teste":
			ArduinoBridge.pedir_permissao_agora()
			_teste = true
			_teste_contagem = [0, 0, 0, 0, 0]
			_entrar_no_teste()
			ArduinoBridge.modo_teste(true)
			_mostrar_teste("")
		"calibrar":
			ArduinoBridge.pedir_permissao_agora()
			_calibrando = true
			_entrar_no_teste()
			ArduinoBridge.calibrar()
			_mostrar_calibracao()
		"porta":
			ArduinoBridge.pedir_permissao_agora()
			_porta = true
			_entrar_no_teste()
			ArduinoBridge.porta(false)
			_mostrar_porta()
		"camera":
			_camera = true
			_entrar_no_teste()
			# confere a câmera e pede de novo a permissão que faltar (o jogo
			# sozinho só pede uma vez na vida)
			Fotos.pedir_permissao_agora()
			Fotos.na_espera()
			_camera_ms = Time.get_ticks_msec()
			if Fotos.ligar():
				_camera_ao_vivo()
			else:
				_camera_relatorio("")
		"botoes":
			var jogo := get_tree().current_scene
			if jogo != null and jogo != self and jogo.has_method("abrir_menu"):
				jogo.abrir_menu(load(BOTOES))
			else:
				get_tree().change_scene_to_file.call_deferred(BOTOES)
		"desempenho":
			# volta ao jogo e roda o teste
			Ajustes.definir("video", "testar", true)
			_sair()
		"recordes":
			Ajustes.zerar_recordes()
			Sons.tocar("pop")
		"padrao":
			Ajustes.restaurar_padrao()
			Sons.tocar("pop")
		"voltar":
			_sair()


func _entrar_no_teste() -> void:
	for l in _linhas:
		l.visible = false
	_teste_rotulo.visible = true
	_teste_rotulo.text = ""
	_teste_rotulo.label_settings.font_size = int(42 * u)
	_teste_rotulo.position = Vector2(40 * u, 120 * u)
	_teste_rotulo.size = Vector2(Tela.tamanho().x - 80 * u, Tela.tamanho().y - 400 * u)


func _sair_do_teste() -> void:
	if _teste:
		ArduinoBridge.modo_teste(false)
	if _porta:
		ArduinoBridge.porta(false)
	_teste = false
	_camera = false
	_porta = false
	_calibrando = false
	_teste_rotulo.visible = false
	_teste_rotulo.text = ""
	_teste_rotulo.position = Vector2(0, Tela.tamanho().y * 0.35)
	_teste_rotulo.size = Vector2(Tela.tamanho().x, 500 * u)
	_teste_rotulo.label_settings.font_size = int(54 * u)
	_camera_tela.visible = false
	Fotos.desligar(2.0)
	_atualizar()


## As últimas linhas do relatório do Arduino (USB, chip, firmware), para
## quando ele não está conectado.
func _relatorio_arduino() -> String:
	var linhas := ArduinoBridge.relatorio().split("\n")
	return "\n".join(linhas.slice(0, mini(linhas.size(), 12)))


## Teste da porta: o que o jogo pediu e o que o Arduino confirmou.
func _mostrar_porta() -> void:
	var t := "TESTE DA PORTA (trava das bolas)\n\n"
	if ArduinoBridge.completo():
		var pedida := "ABERTA" if ArduinoBridge.porta_quer else "FECHADA"
		var confirmada := "ABERTA" if ArduinoBridge.porta_aberta else "FECHADA"
		t += "Porta: %s\n" % pedida
		t += ("(o Arduino confirmou)" if confirmada == pedida else "(esperando o Arduino...)") + "\n\n"
		t += "C ou START: abre / fecha\nCONFIGURAÇÃO: sai (a porta fecha)\n\n"
		t += "Abriu quando devia fechar? Ligue \"Porta invertida\" no menu."
	else:
		_teste_rotulo.label_settings.font_size = int(30 * u)
		t += "SEM O ARDUINO\n%s\n\n%s\n\nCONFIGURAÇÃO ou START sai" % [ArduinoBridge.status, _relatorio_arduino()]
	_teste_rotulo.text = t


## Calibração: com a pista vazia, o nível de cada sensor vira o "sem bola".
func _mostrar_calibracao() -> void:
	var t := "CALIBRAR SENSORES\n\n"
	if not ArduinoBridge.completo():
		_teste_rotulo.label_settings.font_size = int(30 * u)
		t += "SEM O ARDUINO\n%s\n\n%s\n\nCONFIGURAÇÃO ou START sai" % [ArduinoBridge.status, _relatorio_arduino()]
	elif ArduinoBridge.calibracao.begins_with("CAL:OK:"):
		var niveis := ArduinoBridge.calibracao.substr(7)
		t += "PRONTO! Sem bola cada sensor fica em:\n"
		for i in mini(5, niveis.length()):
			t += "S%d: %s\n" % [i + 1, "ALTO (aciona em baixo)" if niveis[i] == "H" else "BAIXO (aciona em alto)"]
		t += "\nRole a bola no TESTE DOS SENSORES para conferir.\nCONFIGURAÇÃO ou START sai"
	else:
		t += "Calibrando... deixe a pista VAZIA\n(nenhuma bola na frente dos sensores)"
	_teste_rotulo.text = t


## Teste da câmera: a imagem ao vivo (Z / B giram).
func _camera_ao_vivo() -> void:
	_camera_tela.texture = Fotos.ao_vivo()
	_camera_tela.visible = true
	_teste_rotulo.label_settings.font_size = int(54 * u)
	_teste_rotulo.position.y = 40 * u
	_teste_rotulo.size.y = Tela.tamanho().y * 0.25
	_teste_rotulo.text = "TESTE DA CÂMERA\n%s\nZ / B giram a imagem · START sai" % Fotos.nome_camera


## Teste da câmera sem imagem: o que o Android enxerga e o que o jogo tentou.
func _camera_relatorio(aviso: String) -> void:
	_camera_tela.visible = false
	var linhas := Fotos.relatorio().split("\n")
	var rel := "\n".join(linhas.slice(0, mini(linhas.size(), 18)))
	_teste_rotulo.label_settings.font_size = int(30 * u)
	_teste_rotulo.position.y = 30 * u
	_teste_rotulo.size.y = Tela.tamanho().y - 60 * u
	_teste_rotulo.text = "TESTE DA CÂMERA%s\n\nCâmera: %s\n\n%s\n\nSTART ou CONFIGURAÇÃO para sair" % [aviso, Fotos.texto_status(), rel]


func _process(delta: float) -> void:
	if not _camera:
		return
	_camera_t += delta
	if _camera_t < 1.0:
		return
	_camera_t = 0.0
	if Fotos.tem_imagem():
		if not _camera_tela.visible:
			_camera_ao_vivo()
	elif Time.get_ticks_msec() - _camera_ms > 6000 and Fotos.pronta():
		# 6 s ligada e nenhuma imagem: mostra o porquê (atualiza a cada 1 s)
		_camera_relatorio(" - SEM IMAGEM AINDA")


func _mostrar_teste(ultimo: String) -> void:
	var nomes := ["S1 ESQUERDA (Z)", "S2 MEIO-ESQ. (X)", "S3 CENTRO (C)", "S4 MEIO-DIR. (V)", "S5 DIREITA (B)"]
	var ao_vivo := ArduinoBridge.sensores
	var txt := "TESTE DOS SENSORES\nrole a bola (ou passe a mão) em cada um\n\n"
	for i in 5:
		var agora := ""
		if ao_vivo.length() == 5:
			agora = "   ● BOLA" if ao_vivo[i] == "1" else "   ○ livre"
		txt += "%s%s:  %d%s\n" % ["▶ " if ["Z", "X", "C", "V", "B"][i] == ultimo else "", nomes[i], _teste_contagem[i], agora]
	if ArduinoBridge.completo():
		txt += "\nArduino conectado: ● aparece enquanto a bola tapa o sensor."
	else:
		txt += "\nSem o Arduino (contando os botões da placa).\n%s" % ArduinoBridge.status
	txt += "\nSTART ou CONFIGURAÇÃO para sair"
	_teste_rotulo.text = txt
	if ultimo != "":
		Sons.tocar("selecao")
