extends Node

## MENU DO OPERADOR SEM TRAVAR: abre e fecha o menu por cima do jogo e mede
## cada quadro (e quanto cada passo levou).
##   godot --path . --resolution 1080x1920 res://tools/testes/menu_teste.tscn -- --janela=1080x1920
## (na resolução da TV Box: é para ela que as letras já vêm desenhadas)
## A máquina de teste não tem placa de vídeo: desenha o 3D por software
## (~1 s por quadro, variando ±100 ms) e isso esconde qualquer tranco. Aqui
## o 3D não é desenhado (o jogo continua rodando por baixo, só a imagem 3D
## fica parada): os quadros ficam rápidos e o EXTRA da troca de tela
## (montar o menu, a tela de espera, os textos) aparece.

var falhas := 0
var _ult := 0
var _quadros: Array = []
var _medindo := false
var _jogo: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().process_frame.connect(_quadro)
	RenderingServer.frame_pre_draw.connect(_sem_3d)
	_rodar.call_deferred()


## Logo antes de desenhar cada quadro: a imagem 3D não é desenhada (fechar o
## menu a liga de novo no meio do quadro; aqui ela é desligada antes).
func _sem_3d() -> void:
	if _jogo != null and _jogo.vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		_jogo.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _quadro() -> void:
	var agora := Time.get_ticks_usec()
	if _medindo:
		_quadros.append(float(agora - _ult) / 1000.0)
	_ult = agora


func _mediana(v: Array) -> float:
	if v.is_empty():
		return 0.0
	var c := v.duplicate()
	c.sort()
	return c[c.size() / 2]


func checar(ok: bool, texto: String) -> void:
	print(("OK    " if ok else "FALHA ") + texto)
	if not ok:
		falhas += 1


func esperar(seg: float) -> void:
	await get_tree().create_timer(seg, true, false, true).timeout


func _medir(nome: String, f: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	f.call()
	print("  %s: %.1f ms" % [nome, float(Time.get_ticks_usec() - t0) / 1000.0])


func _rodar() -> void:
	reparent(get_tree().root)
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://cenas/principal.tscn")
	await esperar(0.5)
	var p := get_tree().current_scene
	while p.E.keys()[p.estado] != "ATRACAO":
		await get_tree().process_frame
	await esperar(2.0)
	_jogo = p
	await esperar(1.5)
	for vez in 3:
		print("== vez %d" % (vez + 1))
		# quadros normais do jogo (a máquina de teste não tem placa de vídeo:
		# o 3D já é lento aqui; o que conta é o EXTRA da troca de tela)
		_quadros.clear()
		_medindo = true
		await esperar(1.0)
		var normal := _mediana(_quadros)
		_quadros.clear()
		_medir("abrir_menu", func(): p.abrir_menu(p.CENA_OPERADOR))
		await esperar(1.0)
		var menu := _mediana(_quadros)
		var extra_abrir: float = _quadros.slice(0, 3).max() - maxf(menu, normal)
		print("  quadros: jogo %.1f ms, menu %.1f ms; ao abrir %s" % [normal, menu, str(_quadros.slice(0, 4))])
		_quadros.clear()
		_medir("fechar_menu", func(): p.fechar_menu())
		await esperar(1.5)
		var extra_fechar: float = _quadros.slice(0, 3).max() - normal
		print("  ao fechar %s" % str(_quadros.slice(0, 4)))
		_medindo = false
		checar(extra_abrir < 25.0 and extra_fechar < 25.0, "vez %d: abre e fecha sem travar (extra %.0f / %.0f ms)" % [vez + 1, extra_abrir, extra_fechar])
		await esperar(2.0)
	await _controle_remoto(p)
	print("MENU_TESTE %s" % ("OK" if falhas == 0 else "FALHOU"))
	get_tree().quit(0 if falhas == 0 else 1)


## O CONTROLE REMOTO DA TV BOX no menu: MENU abre, setas andam e mudam o
## valor, OK entra num teste, VOLTAR sai do teste e depois do menu (no
## Android o VOLTAR chega como NOTIFICATION_WM_GO_BACK_REQUEST).
func _tecla(k: Key) -> void:
	for apertada in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = apertada
		Input.parse_input_event(ev)
		await get_tree().process_frame
	await esperar(0.15)


func _controle_remoto(p: Node) -> void:
	print("== controle remoto da TV Box")
	await _tecla(KEY_MENU)
	await esperar(0.6)
	checar(p.menu_aberto(), "MENU do controle abre o menu")
	if not p.menu_aberto():
		return
	var menu: Node = p._menu
	await _tecla(KEY_DOWN)
	checar(menu._sel == 1, "seta para baixo anda na lista")
	await _tecla(KEY_UP)
	checar(menu._sel == 0, "seta para cima volta")
	var antes := int(Ajustes.valor("jogo", "rodadas"))
	await _tecla(KEY_RIGHT if antes < 10 else KEY_LEFT)
	var depois := int(Ajustes.valor("jogo", "rodadas"))
	checar(depois != antes, "seta para o lado muda o valor (rodadas %d -> %d)" % [antes, depois])
	await _tecla(KEY_LEFT if antes < 10 else KEY_RIGHT)
	checar(int(Ajustes.valor("jogo", "rodadas")) == antes, "e a outra seta volta o valor")
	# OK entra no teste dos sensores; VOLTAR sai do teste (o menu continua)
	for i in menu.ITENS.size():
		if menu.ITENS[i][2] == "teste":
			menu._sel = i
	await _tecla(KEY_ENTER)
	checar(menu._teste, "OK entra no teste dos sensores")
	p.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await esperar(0.3)
	checar(not menu._teste and p.menu_aberto(), "VOLTAR sai do teste e fica no menu")
	p.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await esperar(0.8)
	checar(not p.menu_aberto(), "VOLTAR de novo volta ao jogo")
	checar(p.E.keys()[p.estado] == "ATRACAO", "o jogo continua (tela de espera), sem fechar")
