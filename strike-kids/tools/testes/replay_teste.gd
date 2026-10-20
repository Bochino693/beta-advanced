extends Node

## TESTE DO REPLAY (só no PC): mede, quadro a quadro, quanto a bola anda
## durante o replay — tem que andar liso (sem quadros parados nem pulos).
##   godot --path . --fixed-fps 60 -- --janela=540x960 --replay-teste[=pasta_quadros]
## Sozinho, ele mesmo faz uma jogada de demonstração com STRIKE (rápido);
## junto com --roteiro=..., mede o replay da partida roteirada.
## Com =pasta_quadros, também grava cada quadro do replay (jpg).
## Também mede a bola ROLANDO na jogada (posição que aparece na tela, já
## interpolada): rode com --fixed-fps 50 (2,4 passos de física por quadro)
## para ver se ela anda por igual mesmo quando a tela não bate com a física.

var principal: Node
var pasta := ""
var _dados: Array = []
var _n := 0
var _feito := false
var _sozinho := true


func _ready() -> void:
	principal = get_parent()
	process_priority = 1000   # depois da câmera e do jogo: mede o quadro pronto
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--replay-teste="):
			pasta = a.substr(15)
			DirAccess.make_dir_recursive_absolute(pasta)
		elif a.begins_with("--roteiro"):
			_sozinho = false
	if _sozinho:
		_demo_com_strike()


func _demo_com_strike() -> void:
	while principal.estado != principal.E.ATRACAO:
		await get_tree().process_frame
	for i in 30:
		await get_tree().process_frame
	Jogada.forcar = [10]
	principal._jogada_demo()


var _ultimo_estado := -1
var _rolando: Array = []
var _rolando_ok := false


func _process(_d: float) -> void:
	if principal.estado != _ultimo_estado:
		_ultimo_estado = principal.estado
		print("REPLAY-TESTE estado=", principal.E.keys()[principal.estado], " quadro=", Engine.get_process_frames())
	if principal.estado == principal.E.ROLANDO:
		var bb: Node3D = principal.bola
		_rolando.append([Mundo.na_tela(bb).origin, bb.global_position])
		# começo da jogada: câmera e bola quadro a quadro (e fotos, com pasta)
		if _rolando.size() <= 40:
			var cm: Camera3D = principal.cam
			print("JOGADA q%02d cam=%s bola_tela=%s bola_fisica=%s visivel=%s" % [_rolando.size(), str(cm.global_position.snapped(Vector3.ONE * 0.01)),
				str(_rolando[-1][0].snapped(Vector3.ONE * 0.01)), str(bb.global_position.snapped(Vector3.ONE * 0.01)), bb.visible])
			if pasta != "":
				var nome := "%s/j%02d.jpg" % [pasta, _rolando.size()]
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_jpg(nome, 0.85)
	elif not _rolando.is_empty() and not _rolando_ok:
		_rolando_ok = true
		_relatorio_rolando()
	if _feito:
		return
	if principal.estado != principal.E.REPLAY:
		if _dados.size() > 10:
			_relatorio()
		return
	var b: Node3D = principal.bola
	var cam: Camera3D = principal.cam
	var p := b.global_position
	_dados.append([float(principal.get("_replay_t")), p, cam.unproject_position(p), b.visible, b.global_basis.get_rotation_quaternion()])
	if pasta != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg("%s/r%04d.jpg" % [pasta, _n], 0.9)
	_n += 1


## Passo por quadro na jogada: o que aparece (interpolado) e o passo cru da física.
func _relatorio_rolando() -> void:
	for k in 2:
		var passos: Array[float] = []
		for i in range(1, _rolando.size()):
			var a: Vector3 = _rolando[i - 1][k]
			var c: Vector3 = _rolando[i][k]
			if c.z > Mundo.Z_PINO1 + 1.5 and c.z < 0.2:
				passos.append(a.distance_to(c))
		var trancos := 0
		var pior := 0.0
		var txt := ""
		for i in range(1, passos.size() - 1):
			var viz := (passos[i - 1] + passos[i + 1]) / 2.0
			if viz > 0.002:
				var r := absf(passos[i] - viz) / viz
				pior = maxf(pior, r)
				if r > 0.1:
					trancos += 1
		for x in passos:
			txt += "%.4f " % x
		print("ROLANDO %s: trancos(>10%%)=%d pior_variacao=%.0f%%  passos: %s" % [
			"NA TELA (interpolado)" if k == 0 else "FISICA (passo cru)", trancos, pior * 100.0, txt])


func _relatorio() -> void:
	_feito = true
	# passo da bola no MUNDO a cada quadro (enquanto visível)
	var passos: Array[float] = []
	var giros: Array[float] = []
	var parados := 0
	for i in range(1, _dados.size()):
		var a: Array = _dados[i - 1]
		var c: Array = _dados[i]
		if not (a[3] and c[3]):
			continue
		var d := (c[1] as Vector3).distance_to(a[1])
		passos.append(d)
		giros.append((a[4] as Quaternion).angle_to(c[4]))
		if d < 1e-5:
			parados += 1
	# "tranco": quanto o passo de um quadro difere da média dos vizinhos
	var trancos := 0
	var pior := 0.0
	for i in range(1, passos.size() - 1):
		var viz := (passos[i - 1] + passos[i + 1]) / 2.0
		if viz < 0.002:
			continue
		var r := absf(passos[i] - viz) / viz
		pior = maxf(pior, r)
		if r > 0.35:
			trancos += 1
	var linhas := "REPLAY quadros=%d passos=%d parados=%d trancos(>35%%)=%d pior_variacao=%.0f%%" % [
		_dados.size(), passos.size(), parados, trancos, pior * 100.0]
	print(linhas)
	var amostra := ""
	for i in range(0, mini(passos.size(), 60)):
		amostra += "%.4f " % passos[i]
	print("REPLAY passos(m): ", amostra)
	var ga := ""
	for i in range(0, mini(giros.size(), 30)):
		ga += "%.3f " % giros[i]
	print("REPLAY giros(rad): ", ga)
	var ts := ""
	for i in range(0, mini(_dados.size(), 30)):
		ts += "%.4f " % float(_dados[i][0])
	print("REPLAY tempo_jogada: ", ts)
	if _sozinho:
		get_tree().quit()
