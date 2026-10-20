extends Node

## DIRETOR DO VÍDEO DE DIVULGAÇÃO (só no PC).
##   godot --path . --fixed-fps 30 -- --janela=1080x1920 --video=pasta [--cena=promo|curto]
## Joga uma partida roteirada e grava CADA quadro (jpg) + os sons com o
## número do quadro (sons.json). Depois: python3 tools/testes/montar_video.py pasta

var pasta := "user://video"
var cena := "promo"
var principal: Node
var quadro := 0
var gravando := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--video="):
			pasta = a.substr(8)
		elif a.begins_with("--cena="):
			cena = a.substr(7)
	DirAccess.make_dir_recursive_absolute(pasta)
	principal = get_parent()
	Sons.registrar = true
	Sons.registro.clear()
	Ajustes.set("creditos", 99)
	gravando = true
	_rodar()


func _process(_d: float) -> void:
	if not gravando:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_jpg("%s/q%05d.jpg" % [pasta, quadro], 0.93)
	if quadro == 0:
		Sons.registro.append([Engine.get_process_frames(), "inicio", 1.0, 1.0])
	quadro += 1


func esperar(seg: float) -> void:
	await get_tree().create_timer(seg, true, false, true).timeout


func esperar_estado(nome: String, limite := 40.0) -> bool:
	var t := 0.0
	while principal.E.keys()[principal.estado] != nome:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > limite:
			return false
	return true


func apertar(acao: String) -> void:
	var teclas := {"input_start": KEY_1, "input_z": KEY_A, "input_x": KEY_S, "input_c": KEY_D, "input_v": KEY_F, "input_b": KEY_G}
	var k := InputEventKey.new()
	k.physical_keycode = teclas.get(acao, KEY_1)
	k.keycode = k.physical_keycode
	k.pressed = true
	Input.parse_input_event(k)
	await get_tree().create_timer(0.1).timeout
	var k2 := k.duplicate()
	k2.pressed = false
	Input.parse_input_event(k2)


func jogar(sensor: String) -> void:
	if await esperar_estado("PRONTO", 40.0):
		await esperar(0.9)
		await apertar(sensor)


func _rodar() -> void:
	# Atração passando pelos cenários -> START -> Bob -> SORRIA! (foto) ->
	# 3 rodadas com STRIKE: replay no 1º, "PEGANDO FOGO!" no 2º e bola de
	# fogo no 3º, cada rodada num cenário -> fim de jogo com a foto e recorde.
	var replay_antes = Ajustes.valor("jogo", "replay_strike")
	var rodadas_antes = Ajustes.valor("jogo", "rodadas")
	Ajustes.definir("jogo", "rodadas", 3 if cena != "curto" else 1)
	Ajustes.definir("jogo", "replay_strike", true)
	Jogada.forcar = [10, 10, 10] if cena != "curto" else [10]
	await esperar_estado("ATRACAO", 10.0)
	principal.mundo.aplicar_tema("dinos")
	await esperar(2.2)
	principal.hud.flash(Color.WHITE, 0.8, 0.5)
	principal.mundo.aplicar_tema("mar")
	await esperar(2.0)
	await apertar("input_start")
	await esperar_estado("PERSONAGEM", 10.0)
	await esperar(1.0)
	await apertar("input_start")
	await jogar("input_c")
	# depois do primeiro replay, sem replay (o vídeo fica curto)
	await esperar_estado("REPLAY", 30.0)
	await esperar_estado("RESULTADO", 30.0)
	Ajustes.definir("jogo", "replay_strike", false)
	if cena != "curto":
		await jogar("input_v")
		await jogar("input_c")
	await esperar_estado("FIM", 60.0)
	await esperar(8.0)
	gravando = false
	Ajustes.definir("jogo", "replay_strike", replay_antes)
	Ajustes.definir("jogo", "rodadas", rodadas_antes)
	var f := FileAccess.open(pasta + "/sons.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"registro": Sons.registro, "quadros": quadro}))
	f.close()
	print("VIDEO OK: ", quadro, " quadros")
	get_tree().quit()
