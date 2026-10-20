extends Node

## TESTE DO ARDUINO NO CAMINHO DA TV BOX, com o plugin USB SIMULADO (no PC):
##   godot --path . res://tools/testes/arduino_teste.tscn -- --saida=pasta
## O "Arduino" falso fala o mesmo protocolo do firmware (arduino/strike_kids,
## que tem o seu próprio teste num ATmega simulado: tools/testes/arduino).
## Confere:
##   1. Arduino no USB sem permissão -> o jogo pede a permissão UMA vez na
##      vida (na tela de espera, com o aviso "marque Sempre abrir"); depois
##      só o operador pede de novo, pelo menu;
##   2. permitido -> abre, espera o OLA (o Uno reinicia) e conecta; manda a
##      porta fechada, o modo de teste e a fita de LED;
##   3. sensores S1..S5 viram as jogadas Z X C V B; CFG, START e FICHA viram
##      os botões; sensores invertidos trocam esquerda e direita;
##   4. porta: abre/fecha com a confirmação do Arduino; porta invertida;
##   5. teste dos sensores ao vivo e calibração;
##   6. Arduino que para de responder -> reconecta e manda a porta de novo;
##   7. firmware antigo (só LEDs) conecta, mas avisa;
##   8. PARTIDA INTEIRA só com o Arduino: START abre a porta, a bola no
##      sensor joga, o fim da partida fecha a porta; CFG abre o menu do
##      operador por cima do jogo pausado e CFG de novo volta na hora.

var saida := "user://arduino_teste"
var falhas := 0
var f: ArduinoFalso
var visto: Array[String] = []


class ArduinoFalso extends RefCounted:
	var permitido := false
	var pedidos := 0
	var pendente_ate := 0
	var firmware := "STRIKE_KIDS:1"
	var mudo := false
	var estado_porta := ""
	var aberta := false
	var _estado := "fechada"
	var _aberta_em := 0
	var _fila: Array = []      # [ms, linha]
	var recebidos: Array[String] = []
	var teste := false
	var abertas := 0

	func listar() -> String:
		return "/dev/bus/usb/001/004|1A86:7523|ch34x|%s|USB Serial\n" % ("1" if permitido else "0")

	func permissao_pendente() -> bool:
		return Time.get_ticks_msec() < pendente_ate

	func pedir_permissao(_nome: String) -> String:
		pedidos += 1
		pendente_ate = Time.get_ticks_msec() + 30000
		return "pedido"

	func abrir(_nome: String, _baud: int) -> void:
		abertas += 1
		_estado = "abrindo"
		_aberta_em = Time.get_ticks_msec()
		_fila.clear()
		# o Uno/Nano reinicia quando a porta abre (DTR) e diz OLA ~1,5 s depois
		if firmware.begins_with("STRIKE_KIDS"):
			chegar("OLA:" + firmware, 1500)
		else:
			chegar("READY:" + firmware, 1500)

	func estado() -> String:
		if _estado == "abrindo" and Time.get_ticks_msec() - _aberta_em > 100:
			_estado = "aberta"
		return _estado

	func erro() -> String:
		return ""

	func chegar(linha: String, depois_ms := 0) -> void:
		_fila.append([Time.get_ticks_msec() + depois_ms, linha])

	func ler() -> String:
		if _estado != "aberta":
			return ""
		var agora := Time.get_ticks_msec()
		var prontas: Array[String] = []
		var resto: Array = []
		for item in _fila:
			if int(item[0]) <= agora:
				prontas.append(str(item[1]))
			else:
				resto.append(item)
		_fila = resto
		return "\n".join(prontas)

	func escrever(linha: String) -> bool:
		recebidos.append(linha)
		if mudo:
			return true
		if not firmware.begins_with("STRIKE_KIDS"):
			if linha == "PING":
				chegar("PONG:" + firmware)
			return true
		match linha:
			"PING":
				chegar("PONG:" + firmware)
			"PORTA:ABRE":
				aberta = true
				chegar("PORTA:ABERTA", 20)
			"PORTA:FECHA":
				aberta = false
				chegar("PORTA:FECHADA", 20)
			"TESTE:1":
				teste = true
				chegar("SENS:00000")
			"TESTE:0":
				teste = false
			"CALIBRA":
				chegar("CAL:OK:HHHHL", 150)
			"INFO?":
				chegar("INFO:STRIKE_KIDS:1:LEDS=1:SERVO=9:RELE=8:REPOUSO=HHHHH")
		return true

	func fechar() -> void:
		_estado = "fechada"
		_fila.clear()

	func relatorio() -> String:
		return "Arduino falso"

	func ultimo(prefixo: String) -> String:
		for i in range(recebidos.size() - 1, -1, -1):
			if recebidos[i].begins_with(prefixo):
				return recebidos[i]
		return ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--saida="):
			saida = a.substr(8)
	DirAccess.make_dir_recursive_absolute(saida)
	RenderingServer.frame_pre_draw.connect(_sem_3d)
	_rodar()


## Escuta o que chega no jogo (como o principal e o menu do operador).
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if ArcadeControls.eh_config(event):
		visto.append("CFG")
	elif ArcadeControls.eh_start(event):
		visto.append("START")
	elif ArcadeControls.eh_credito(event):
		visto.append("FICHA")
	else:
		var z := ArcadeControls.tecla_jogada(event)
		if z != "":
			visto.append(z)


func checar(ok: bool, texto: String) -> void:
	print(("OK    " if ok else "FALHA ") + texto)
	if not ok:
		falhas += 1


## Começa a medir o tempo de cada quadro; a função devolvida para de medir
## e devolve os tempos (ms).
func _medir_quadros() -> Callable:
	var dados := {"ult": Time.get_ticks_usec(), "tempos": []}
	var medir := func():
		var agora := Time.get_ticks_usec()
		dados["tempos"].append(float(agora - dados["ult"]) / 1000.0)
		dados["ult"] = agora
	get_tree().process_frame.connect(medir)
	return func() -> Array:
		get_tree().process_frame.disconnect(medir)
		return dados["tempos"]


## A máquina de teste não tem placa de vídeo: desenha o 3D por software
## (~1 s por quadro), o que esconde qualquer tranco. Enquanto mede o menu, a
## imagem 3D não é desenhada (o jogo continua rodando): logo antes de cada
## quadro ser desenhado ela é desligada (fechar o menu a liga de novo).
var _jogo_sem_3d: Node = null


func _sem_3d() -> void:
	if _jogo_sem_3d != null and _jogo_sem_3d.vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		_jogo_sem_3d.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func esperar(seg: float) -> void:
	await get_tree().create_timer(seg, true, false, true).timeout


func esperar_que(cond: Callable, limite: float) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > limite:
			return false
	return true


func _rodar() -> void:
	await esperar(0.5)
	Ajustes.definir("arduino", "porta_invertida", false)
	Ajustes.definir("arduino", "sensores_invertidos", false)
	f = ArduinoFalso.new()
	ArduinoBridge._plugin = f
	ArduinoBridge._fase = "procurando"
	ArduinoBridge._ultima_procura = -100000
	ArduinoBridge._pedidos_salvos = ConfigFile.new()   # como numa TV Box nova: nada pedido ainda
	ArduinoBridge._janela_ate = 0
	ArduinoBridge.porta(false)
	var avisos: Array[String] = []
	ArduinoBridge.janela_android.connect(func(t: String): avisos.append(t))

	# 1. sem permissão: a janela do Android UMA vez na vida, na tela de espera
	ArduinoBridge.na_espera(false)
	await esperar(2.0)
	checar(f.pedidos == 0, "fora da tela de espera (no meio do jogo) a janela nao aparece")
	ArduinoBridge.na_espera(true)
	checar(await esperar_que(func(): return f.pedidos == 1, 4.0), "Arduino no USB sem permissao -> na espera o jogo pede (%d pedido)" % f.pedidos)
	checar(avisos.size() >= 1 and "SEMPRE ABRIR" in avisos[0], "antes da janela, o aviso na tela manda marcar SEMPRE ABRIR")
	checar("Sempre abrir" in ArduinoBridge.status, "status manda aceitar a janela: %s" % ArduinoBridge.status)
	await esperar(2.0)
	checar(f.pedidos == 1, "nao fica pedindo de novo com a janela aberta")
	# a janela fechou sem a permissão: o jogo nunca mais pede sozinho
	f.pendente_ate = 0
	ArduinoBridge._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	checar(not avisos.is_empty() and avisos[-1] == "", "a janela fechou: o aviso some da tela")
	await esperar(4.0)
	checar(f.pedidos == 1, "janela fechada sem permissao: o jogo NAO pede de novo sozinho (%d pedido)" % f.pedidos)
	ArduinoBridge._pedidos_salvos = null   # o jogo abriu de novo: lê o que guardou
	await esperar(4.0)
	checar(f.pedidos == 1, "nem depois de abrir o jogo de novo (lembra no permissoes.cfg)")
	checar("TESTE DOS SENSORES" in ArduinoBridge.status, "status diz como pedir de novo: %s" % ArduinoBridge.status)
	ArduinoBridge.pedir_permissao_agora()   # o operador, nos testes do Arduino no menu
	checar(await esperar_que(func(): return f.pedidos == 2, 4.0), "o operador pede de novo pelo menu (%d pedidos)" % f.pedidos)

	# 2. permitido -> conecta
	f.permitido = true
	checar(await esperar_que(func(): return ArduinoBridge.connected, 6.0), "permitido -> abre e conecta depois do OLA (%s)" % ArduinoBridge.status)
	checar(ArduinoBridge.completo(), "firmware novo reconhecido (%s)" % ArduinoBridge.firmware)
	await esperar(0.3)
	checar("PORTA:FECHA" in f.recebidos and "TESTE:0" in f.recebidos and "MENU" in f.recebidos and "INFO?" in f.recebidos,
		"ao conectar manda porta fechada, modo normal, LED e INFO? (%s)" % ", ".join(f.recebidos))

	# 3. sensores e botões
	visto.clear()
	for i in 5:
		f.chegar("S:%d" % (i + 1))
		await esperar(0.15)
	checar(visto == ["Z", "X", "C", "V", "B"], "S1..S5 -> jogadas Z X C V B (%s)" % ", ".join(visto))
	visto.clear()
	f.chegar("CFG")
	await esperar(0.15)
	f.chegar("START")
	await esperar(0.15)
	f.chegar("FICHA")
	await esperar(0.15)
	checar(visto == ["CFG", "START", "FICHA"], "CFG, START e FICHA viram os botoes (%s)" % ", ".join(visto))
	Ajustes.definir("arduino", "sensores_invertidos", true)
	visto.clear()
	f.chegar("S:1")
	await esperar(0.15)
	checar(visto == ["B"], "sensores invertidos: S1 vira a jogada da direita (%s)" % ", ".join(visto))
	Ajustes.definir("arduino", "sensores_invertidos", false)

	# 4. porta
	ArduinoBridge.porta(true)
	checar(await esperar_que(func(): return ArduinoBridge.porta_aberta, 1.0) and f.aberta, "porta(true) -> PORTA:ABRE e o Arduino confirma")
	ArduinoBridge.porta(false)
	checar(await esperar_que(func(): return not ArduinoBridge.porta_aberta, 1.0) and not f.aberta, "porta(false) -> PORTA:FECHA e o Arduino confirma")
	Ajustes.definir("arduino", "porta_invertida", true)
	ArduinoBridge.reenviar_porta()
	await esperar(0.2)
	checar(f.aberta and not ArduinoBridge.porta_aberta, "porta invertida: fechada para o jogo = ABRE no Arduino")
	ArduinoBridge.porta(true)
	await esperar(0.2)
	checar(not f.aberta and ArduinoBridge.porta_aberta, "porta invertida: aberta para o jogo = FECHA no Arduino")
	Ajustes.definir("arduino", "porta_invertida", false)
	ArduinoBridge.porta(false)
	await esperar(0.2)

	# 5. teste dos sensores e calibração
	ArduinoBridge.modo_teste(true)
	await esperar(0.2)
	f.chegar("SENS:00100")
	await esperar(0.15)
	checar(ArduinoBridge.sensores == "00100", "teste dos sensores: estado ao vivo (%s)" % ArduinoBridge.sensores)
	ArduinoBridge.modo_teste(false)
	checar(ArduinoBridge.calibrar(), "calibrar manda CALIBRA")
	checar(await esperar_que(func(): return ArduinoBridge.calibracao == "CAL:OK:HHHHL", 1.0), "calibracao volta do Arduino (%s)" % ArduinoBridge.calibracao)

	# 6. Arduino mudo -> reconecta e manda a porta de novo
	ArduinoBridge.porta(true)
	await esperar(0.2)
	var abertas_antes := f.abertas
	f.mudo = true
	checar(await esperar_que(func(): return not ArduinoBridge.connected, 9.0), "Arduino mudo -> desconecta (%s)" % ArduinoBridge.status)
	f.mudo = false
	f.recebidos.clear()
	f.aberta = false
	checar(await esperar_que(func(): return ArduinoBridge.connected, 9.0) and f.abertas > abertas_antes, "volta a conectar sozinho")
	await esperar(0.3)
	checar(f.aberta and "PORTA:ABRE" in f.recebidos, "ao reconectar manda a porta como o jogo quer (aberta)")
	ArduinoBridge.porta(false)
	await esperar(0.2)

	# 7. firmware antigo (só LEDs)
	f.firmware = "DRAGON_BOWLING:1"
	f.fechar()
	checar(await esperar_que(func(): return ArduinoBridge.connected and ArduinoBridge.firmware == "DRAGON_BOWLING:1", 12.0),
		"firmware antigo (so LEDs) conecta (%s)" % ArduinoBridge.status)
	checar(not ArduinoBridge.completo() and "ANTIGO" in ArduinoBridge.status, "e avisa para gravar o firmware novo")
	f.firmware = "STRIKE_KIDS:1"
	f.fechar()
	checar(await esperar_que(func(): return ArduinoBridge.completo(), 12.0), "firmware novo de volta")

	# 8. a partida inteira só com o Arduino
	await _partida()
	print("ARDUINO_TESTE %s (%d falha(s))" % ["OK" if falhas == 0 else "FALHOU", falhas])
	get_tree().quit(0 if falhas == 0 else 1)


func _partida() -> void:
	var rodadas_antes = Ajustes.valor("jogo", "rodadas")
	var bolas_antes = Ajustes.valor("jogo", "tentativas")
	var demo_antes = Ajustes.valor("jogo", "demo")
	Ajustes.definir("jogo", "rodadas", 1)
	Ajustes.definir("jogo", "tentativas", 1)
	Ajustes.definir("jogo", "demo", false)
	# este teste continua vivo quando a cena do jogo entra no lugar dele
	if get_tree().current_scene == self:
		reparent(get_tree().root)
		get_tree().current_scene = null
	get_tree().change_scene_to_file("res://cenas/principal.tscn")
	await esperar(0.5)
	var p := get_tree().current_scene
	checar(await esperar_que(func(): return p.E.keys()[p.estado] == "ATRACAO", 40.0), "o jogo abre e chega na tela de espera")
	await esperar(0.5)
	checar(not f.aberta, "na espera a porta esta FECHADA")
	f.chegar("START")
	checar(await esperar_que(func(): return p.E.keys()[p.estado] in ["JOGADORES", "PERSONAGEM"], 3.0), "START do Arduino comeca a partida")
	checar(await esperar_que(func(): return f.aberta, 1.0), "depois do START a porta ABRE")
	checar(await esperar_que(func(): return p.E.keys()[p.estado] == "PERSONAGEM", 8.0), "escolha do amigo")
	f.chegar("S:5")   # bola pela direita = Mia
	await esperar(0.5)
	f.chegar("START")
	checar(await esperar_que(func(): return p.E.keys()[p.estado] == "PRONTO", 30.0), "vez de jogar (pista esperando a bola)")
	f.chegar("S:3")   # a bola passou no sensor do centro
	checar(await esperar_que(func(): return p.E.keys()[p.estado] == "ARREMESSO" or p.E.keys()[p.estado] == "ROLANDO", 3.0), "a bola no sensor do centro faz a jogada")
	checar(await esperar_que(func(): return p.E.keys()[p.estado] == "FIM", 60.0), "a partida termina")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(saida.path_join("fim.png"))
	checar(await esperar_que(func(): return not f.aberta, 1.0), "no fim da partida a porta FECHA")
	# botão de configuração: o menu do operador abre POR CIMA do jogo
	# pausado e fecha na hora (nada é montado de novo: sem quadro lento)
	# quadros normais antes, sem desenhar o 3D (o que conta é o EXTRA da
	# troca de tela)
	_jogo_sem_3d = p
	await esperar(0.5)
	var normais := _medir_quadros()
	await esperar(1.0)
	var antes: Array = normais.call()
	antes.sort()
	var normal: float = antes[antes.size() / 2] if not antes.is_empty() else 0.0
	var quadros := _medir_quadros()
	f.chegar("CFG")
	checar(await esperar_que(func(): return p.menu_aberto() and get_tree().paused, 3.0),
		"CFG do Arduino abre o menu do operador (por cima do jogo pausado)")
	await esperar(0.5)
	var ao_abrir: Array = quadros.call()
	# a foto da tela (do teste) fica fora da medida
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(saida.path_join("operador.png"))
	for k in 3:
		await get_tree().process_frame
	quadros = _medir_quadros()
	f.chegar("CFG")
	checar(await esperar_que(func(): return not p.menu_aberto() and not get_tree().paused, 3.0),
		"CFG de novo volta ao jogo")
	checar(get_tree().current_scene == p, "o jogo nao foi montado de novo (mesma cena)")
	checar(await esperar_que(func(): return p.E.keys()[p.estado] == "ATRACAO", 1.0), "volta direto para a tela de espera")
	await esperar(1.0)
	var ao_fechar: Array = quadros.call()
	# o quadro normal da tela de espera (para onde o menu voltou: cada tela
	# tem o seu custo; o menu abriu na tela de fim de jogo)
	var depois := _medir_quadros()
	await esperar(1.0)
	var espera: Array = depois.call()
	espera.sort()
	var normal_espera: float = espera[espera.size() / 2] if not espera.is_empty() else 0.0
	_jogo_sem_3d = null
	p.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var pior_abrir: float = ao_abrir.max() if not ao_abrir.is_empty() else 0.0
	var pior_fechar: float = ao_fechar.max() if not ao_fechar.is_empty() else 0.0
	print("quadros sem desenhar o 3D: fim de jogo %.1f ms -> abrindo o menu, pior %.1f ms; tela de espera %.1f ms -> fechando o menu, pior %.1f ms" % [
		normal, pior_abrir, normal_espera, pior_fechar])
	# (aqui só pega travada grande, como a de antes, que montava o jogo de
	# novo: este teste roda numa tela pequena, onde as letras do menu têm
	# tamanhos que não estão nas fontes prontas. A medida fina é o
	# tools/testes/menu_teste.tscn na resolução da TV Box.)
	checar(pior_abrir - normal < 150.0 and pior_fechar - normal_espera < 150.0,
		"entrar e sair do menu sem travar (extra %.0f / %.0f ms)" % [pior_abrir - normal, pior_fechar - normal_espera])
	Ajustes.definir("jogo", "rodadas", rodadas_antes)
	Ajustes.definir("jogo", "tentativas", bolas_antes)
	Ajustes.definir("jogo", "demo", demo_antes)
