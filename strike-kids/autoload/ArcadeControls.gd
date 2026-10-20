extends Node

## OS COMANDOS DO JOGO VÊM DA PLACA ZERO DELAY E/OU DO ARDUINO.
## (Os sensores, o botão de configuração e o START/ficha ligados no Arduino
## chegam como as mesmas ações — ver ArduinoBridge.)
##
## Sem mapeamento gravado, vale o Input Map do projeto: as teclas da Zero
## Delay no modo teclado (1/Espaço = STR, A = quadrado, S = X, D = bolinha,
## F = triângulo, G = R1, 5 = SELECT, 9 = configuração) e os botões de
## joystick como o Godot 4 os numera no ANDROID (TV Box), conferidos com o
## Dragon Bowling na mesma máquina:
##   X = 0, bolinha = 1, quadrado = 2, triângulo = 3, SELECT = 4, START = 6,
##   L3 = 7, R1 = 10, R2 = 16.
## (O Dragon Bowling, em Godot 3, numera diferente: R1 5, R2 7, SELECT 10,
## START 11 — por isso aqui os números mudam, mas os BOTÕES são os mesmos.)
## As ações "ui_*" do Godot (ENTER, setas, botão 0) são desligadas.
##
## MAPEAMENTO GRAVADO NA TV BOX. O Android numera os botões da placa de
## outro jeito que o Windows. Na tela de CONFIGURAÇÃO (L3, ou segurar
## qualquer botão da placa por 5 segundos no menu) o jogo pede um botão
## de cada vez, na sequência, e grava em user://controles_zero_delay.cfg.
## A placa vale do jeito que ela se apresentar ao Android: como joystick
## (botão) ou, no modo teclado, como tecla. Só teclas ligadas a uma ação
## do jogo contam; nenhuma outra tecla faz nada.

const ARQUIVO := "user://controles_zero_delay.cfg"

## A sequência do assistente: ação, nome na tela.
const SEQUENCIA: Array = [
	["input_start", "STR  ·  START"],
	["input_z", "QUADRADO  ·  JOGADA ESQUERDA"],
	["input_x", "X  ·  MEIO ESQUERDO"],
	["input_c", "BOLINHA  ·  CENTRO"],
	["input_v", "TRIÂNGULO  ·  MEIO DIREITO"],
	["input_b", "R1  ·  JOGADA DIREITA"],
	["input_credit", "SELECT  ·  CRÉDITO"],
	["input_teste", "R2  ·  CONFIGURAÇÃO"],
]
## Os primeiros são obrigatórios; SELECT e L3 podem ser pulados (a
## máquina pode não ter esses botões ligados).
const OBRIGATORIOS := 6

const JOGADAS := {
	"input_z": "Z",
	"input_x": "X",
	"input_c": "C",
	"input_v": "V",
	"input_b": "B",
}

## Segurar qualquer botão da placa por este tempo no menu abre a
## configuração — a saída de emergência se o mapeamento estiver errado.
## Longo de propósito: segurar um botão não pode disparar nada por acaso.
const SEGURAR_PARA_CONFIGURAR_MS := 10000
const CENA_CONFIGURACAO := "res://cenas/configuracao_botoes.tscn"
const CENA_MENU := "res://cenas/principal.tscn"
## R2 da Zero Delay (Godot 4 no Android). Abre o menu do operador em
## qualquer tela, mesmo com um mapeamento antigo gravado (de quando a
## configuração era o L3), a não ser que o R2 tenha virado outra ação.
const BOTAO_R2 := 16

var mapeamento_gravado := false
var _segurado_desde := {}

## Proteção de clique (ver eh_da_placa).
const INTERVALO_MINIMO_MS := 120
var _abaixados := {}
var _ultimo_clique := {}
var _evento_visto: InputEvent = null
var _veredito_visto := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_desligar_acoes_de_interface()
	_carregar()


## As ações "ui_*" vêm de fábrica ligadas a ENTER, espaço, setas e ao
## botão 0 de qualquer joystick. Sem elas, nenhum botão aciona a
## interface por baixo do jogo.
func _desligar_acoes_de_interface() -> void:
	for acao: StringName in InputMap.get_actions():
		if String(acao).begins_with("ui_"):
			InputMap.action_erase_events(acao)


## Um código por ação: >= 0 é botão de joystick; "tecla:<código>" é tecla.
func _carregar() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(ARQUIVO) != OK:
		return
	var botoes := {}
	for item: Array in SEQUENCIA:
		var acao: String = item[0]
		if cfg.has_section_key("botoes", acao):
			botoes[acao] = cfg.get_value("botoes", acao)
	if not botoes.is_empty():
		_aplicar(botoes)
		mapeamento_gravado = true
	_garantir_r2(botoes)


func gravar(botoes: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for acao: String in botoes:
		cfg.set_value("botoes", acao, botoes[acao])
	cfg.save(ARQUIVO)
	_aplicar(botoes)
	mapeamento_gravado = true
	_garantir_r2(botoes)


func _garantir_r2(botoes: Dictionary) -> void:
	var codigo_r2 := "botao:%d" % BOTAO_R2
	for acao: String in botoes:
		if acao != "input_teste" and str(botoes[acao]) == codigo_r2:
			return
	for ev in InputMap.action_get_events("input_teste"):
		if ev is InputEventJoypadButton and ev.button_index == BOTAO_R2:
			return
	var r2 := InputEventJoypadButton.new()
	r2.device = -1
	r2.button_index = BOTAO_R2 as JoyButton
	InputMap.action_add_event("input_teste", r2)


func _aplicar(botoes: Dictionary) -> void:
	for acao: String in botoes:
		var codigo = botoes[acao]
		if not InputMap.has_action(acao):
			InputMap.add_action(acao, 0.2)
		InputMap.action_erase_events(acao)
		var texto := str(codigo)
		if texto.begins_with("tecla:"):
			var tecla := int(texto.substr(6))
			var ev := InputEventKey.new()
			ev.physical_keycode = tecla as Key
			InputMap.action_add_event(acao, ev)
		else:
			var ev := InputEventJoypadButton.new()
			ev.device = -1
			ev.button_index = int(texto.trim_prefix("botao:")) as JoyButton
			InputMap.action_add_event(acao, ev)


## Código gravável de um evento: "botao:N" (joystick) ou "tecla:N";
## vazio se o evento não é botão nem tecla.
static func codigo_do_evento(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		return "botao:%d" % int(event.button_index)
	if event is InputEventKey:
		var k := event as InputEventKey
		var fisica := int(k.physical_keycode) if k.physical_keycode != KEY_NONE else int(k.keycode)
		if fisica != KEY_NONE:
			return "tecla:%d" % fisica
	return ""


static func texto_do_codigo(codigo: String) -> String:
	if codigo.begins_with("tecla:"):
		return "TECLA %s" % OS.get_keycode_string(int(codigo.substr(6)))
	return "BOTÃO %d" % int(codigo.trim_prefix("botao:"))


func texto_de(acao: String) -> String:
	var partes: PackedStringArray = []
	for ev in InputMap.action_get_events(acao):
		if ev is InputEventJoypadButton:
			partes.append("BOTÃO %d" % int(ev.button_index))
		elif ev is InputEventKey:
			partes.append("TECLA %s" % OS.get_keycode_string(ev.physical_keycode))
	return " / ".join(partes) if not partes.is_empty() else "-"


## É um botão da placa? A Zero Delay chega como joystick OU, no modo
## teclado, como teclas (1 = STR, A S D F G = jogadas, 5, 9...). Tecla só
## vale se estiver ligada a uma ação do jogo: as do controle remoto (setas,
## OK, voltar) não estão, então não fazem nada.
##
## CADA APERTO É UM CLIQUE. Um botão só vale de novo depois de ser SOLTO:
## segurar o START (ou qualquer botão/sensor) não repete o comando — nem a
## repetição automática do teclado, nem uma placa que reenvia o "apertado"
## sem soltar. Um repique do contato (apertar de novo em menos de
## INTERVALO_MINIMO_MS) também não conta.
func eh_da_placa(event: InputEvent) -> bool:
	# sensores e botões que vêm do ARDUINO (ArduinoBridge): ele já filtra o
	# repique e manda um aperto por bola/botão
	if event is InputEventAction and event.has_meta("arduino"):
		return true
	if event.is_echo():
		return false
	if not (event is InputEventJoypadButton or event is InputEventKey):
		return false
	# O mesmo evento passa por vários nós (menu, jogo, este): decide uma vez.
	if event == _evento_visto:
		return _veredito_visto
	var codigo := codigo_do_evento(event)
	var valido := true
	if event.is_pressed():
		var agora := Time.get_ticks_msec()
		if _abaixados.has(codigo):
			valido = false   # ainda segurado: não é um clique novo
		elif agora - int(_ultimo_clique.get(codigo, -100000)) < INTERVALO_MINIMO_MS:
			valido = false   # repique do contato
		_abaixados[codigo] = true
		if valido:
			_ultimo_clique[codigo] = agora
	else:
		_abaixados.erase(codigo)
	_evento_visto = event
	_veredito_visto = valido
	return valido


## A tecla/botão apertado não faz nada no jogo (serve para avisar o
## operador de que a configuração precisa ser feita).
func sem_funcao(event: InputEvent) -> bool:
	if not eh_da_placa(event) or not event.is_pressed():
		return false
	for item: Array in SEQUENCIA:
		if event.is_action(item[0]):
			return false
	return true


func eh_start(event: InputEvent) -> bool:
	return eh_da_placa(event) and event.is_action_pressed("input_start")


func eh_config(event: InputEvent) -> bool:
	return eh_da_placa(event) and event.is_action_pressed("input_teste")


func eh_credito(event: InputEvent) -> bool:
	return eh_da_placa(event) and event.is_action_pressed("input_credit")


func tecla_jogada(event: InputEvent) -> String:
	if not eh_da_placa(event):
		return ""
	for acao: String in JOGADAS:
		if event.is_action_pressed(acao):
			return JOGADAS[acao]
	return ""


## Qualquer botão da placa conta como "alguém está jogando".
func eh_atividade(event: InputEvent) -> bool:
	return eh_da_placa(event) and event.is_pressed()


# ----------------------------------------------------- saída de emergência
## Segurar um botão da placa (ou, se a placa estiver no modo teclado, uma
## tecla dela) por 10 s no menu abre a configuração.
func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton or event is InputEventKey):
		return
	if event.is_echo():
		return
	# Registra aperto/soltura de todo botão, mesmo quando a cena atual não
	# pergunta nada (abertura, transição): senão um botão solto nessa hora
	# ficaria "segurado" e o próximo clique dele seria ignorado.
	eh_da_placa(event)
	var chave := codigo_do_evento(event)
	if chave == "":
		return
	if event.is_pressed():
		if not _segurado_desde.has(chave):
			_segurado_desde[chave] = Time.get_ticks_msec()
	else:
		_segurado_desde.erase(chave)


func _process(_delta: float) -> void:
	if _segurado_desde.is_empty():
		return
	var cena := get_tree().current_scene
	if cena == null or cena.scene_file_path != CENA_MENU or (cena.has_method("pode_configurar") and not cena.pode_configurar()):
		# Fora do menu não conta: um aperto esquecido não pode abrir a
		# configuração assim que o menu voltar.
		_segurado_desde.clear()
		return
	var agora := Time.get_ticks_msec()
	for chave: String in _segurado_desde:
		if agora - int(_segurado_desde[chave]) >= SEGURAR_PARA_CONFIGURAR_MS:
			_segurado_desde.clear()
			if cena.has_method("abrir_menu"):
				# por cima do jogo pausado (nada é desmontado)
				cena.abrir_menu.call_deferred(load(CENA_CONFIGURACAO))
			else:
				get_tree().change_scene_to_file.call_deferred(CENA_CONFIGURACAO)
			return
