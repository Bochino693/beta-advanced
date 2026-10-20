extends Node

## MEDIDOR DE DESEMPENHO (só no PC): a cada segundo imprime FPS, tempo de
## CPU, chamadas de desenho, triângulos, objetos e memória de vídeo, com o
## estado do jogo. Liga com:  godot --path . -- --desempenho [--roteiro=...]
## --engasgos: cada quadro acima de 30 ms sai dividido em física / jogo
## (processo) / desenho — numa janela pequena (--janela=72x128) o desenho
## fica barato e qualquer tranco aparece (busca de câmera, imagem carregada
## na hora, shader preparado na hora...). --engasgos=12 muda o limite (ms).

var t := 0.0
var principal: Node
var limite_ms := 30.0


func _ready() -> void:
	principal = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		# sem a pausa do modo econômico: o tempo do quadro vira o custo real
		OS.low_processor_usage_mode = false
		OS.low_processor_usage_mode_sleep_usec = 0
	var engasgos := false
	for a in OS.get_cmdline_user_args():
		if a == "--engasgos" or a.begins_with("--engasgos="):
			engasgos = true
			if "=" in a:
				limite_ms = float(a.get_slice("=", 1))
	if engasgos:
		get_tree().physics_frame.connect(func():
			if _e_fis < 0:
				_e_fis = Time.get_ticks_usec()
			_e_passos += 1)
		get_tree().process_frame.connect(func(): _e_proc = Time.get_ticks_usec())
		RenderingServer.frame_pre_draw.connect(func(): _e_pre = Time.get_ticks_usec())
		RenderingServer.frame_post_draw.connect(_fim_do_quadro)
		_e_ini = Time.get_ticks_usec()


# --engasgos: as marcas de tempo de cada parte do quadro
var _e_ini := 0
var _e_fis := -1
var _e_proc := 0
var _e_pre := 0
var _e_passos := 0


func _fim_do_quadro() -> void:
	var fim := Time.get_ticks_usec()
	var total := (fim - _e_ini) / 1000.0
	if total > limite_ms and Engine.get_process_frames() > 30 and principal and "estado" in principal:
		print("ENGASGO %6.1f ms  fisica=%5.1f (%d passos) jogo=%6.1f desenho=%6.1f  estado=%s quadro=%d" % [total,
			(_e_proc - _e_fis) / 1000.0 if _e_fis >= 0 else 0.0, _e_passos, (_e_pre - _e_proc) / 1000.0,
			(fim - _e_pre) / 1000.0, principal.E.keys()[principal.estado], Engine.get_process_frames()])
	_e_ini = fim
	_e_fis = -1
	_e_passos = 0


var _ult_pico := 0


func _process(delta: float) -> void:
	var agora_p := Time.get_ticks_usec()
	if _ult_pico > 0 and agora_p - _ult_pico > 40000 and principal and "estado" in principal:
		print("PICO %.1f ms estado=%s quadro=%d" % [(agora_p - _ult_pico) / 1000.0, principal.E.keys()[principal.estado], Engine.get_process_frames()])
	_ult_pico = agora_p
	if OS.get_cmdline_user_args().has("--contar-objetos") and not _contou and Engine.get_process_frames() > 400:
		_contou = true
		_contar()
	t += delta
	if t < 1.0:
		return
	t = 0.0
	var est := "?"
	if principal and "estado" in principal:
		est = principal.E.keys()[principal.estado]
	print("DESEMPENHO estado=%s fps=%d cpu=%.1fms fisica=%.1fms desenhos=%d triangulos=%d objetos=%d vram=%dMB nos=%d" % [
		est, Performance.get_monitor(Performance.TIME_FPS),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	var vp: SubViewport = principal.get("vp")
	if vp:
		var rid := vp.get_viewport_rid()
		var info := func(tipo, qual) -> int:
			return RenderingServer.viewport_get_render_info(rid, tipo, qual)
		print("  3D visivel: desenhos=%d triangulos=%d objetos=%d | sombra: desenhos=%d triangulos=%d | %dx%d" % [
			info.call(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			info.call(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
			info.call(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
			info.call(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			info.call(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
			vp.size.x, vp.size.y])
		var raiz := get_viewport().get_viewport_rid()
		print("  2D tela: desenhos=%d" % RenderingServer.viewport_get_render_info(raiz, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))


## --medir-fisica: alterna a física ligada/desligada a cada 4 s (na atração)
## e mostra quanto cada passo de física custa em média.
var _janela := 0.0
var _quadros := 0
var _fisica_ligada := true
var _medidas := {true: [], false: []}
var _t_ini := 0


func _physics_process(_d: float) -> void:
	if not OS.get_cmdline_user_args().has("--medir-fisica"):
		return
	if principal == null or not ("estado" in principal) or principal.estado != principal.E.ATRACAO:
		return
	if _t_ini == 0:
		_t_ini = Time.get_ticks_usec()
		_quadros = Engine.get_process_frames()
		return
	var agora := Time.get_ticks_usec()
	if agora - _t_ini < 4000000:
		return
	var q := Engine.get_process_frames() - _quadros
	var ms := float(agora - _t_ini) / 1000.0 / maxf(q, 1)
	_medidas[_fisica_ligada].append(ms)
	print("FISICA %s: %.2f ms por quadro" % ["ligada" if _fisica_ligada else "desligada", ms])
	if _medidas[false].size() >= 3:
		var a: float = (_medidas[true] as Array).reduce(func(x, y): return x + y, 0.0) / _medidas[true].size()
		var b: float = (_medidas[false] as Array).reduce(func(x, y): return x + y, 0.0) / _medidas[false].size()
		print("FISICA custo médio: %.2f ms por quadro" % (a - b))
		get_tree().quit()
		return
	_fisica_ligada = not _fisica_ligada
	PhysicsServer3D.set_active(_fisica_ligada)
	_t_ini = Time.get_ticks_usec()
	_quadros = Engine.get_process_frames()


## --contar-objetos: lista o que é desenhado (agrupado), 6 s depois de abrir.
var _contou := false


func _contar() -> void:
	var grupos := {}
	var vp: Node = principal.get("vp")
	for no in vp.find_children("*", "GeometryInstance3D", true, false):
		var g := no as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var nome := g.get_class()
		if g is MeshInstance3D and (g as MeshInstance3D).mesh:
			var m: Mesh = (g as MeshInstance3D).mesh
			nome += ":" + (m.resource_path.get_file() if m.resource_path != "" else m.get_class())
		var pai := g.get_parent().name
		var tris := 0
		var m: Mesh = null
		var vezes := 1
		if g is MeshInstance3D:
			m = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			m = (g as MultiMeshInstance3D).multimesh.mesh
			vezes = (g as MultiMeshInstance3D).multimesh.instance_count
		if m:
			for si in m.get_surface_count():
				var arr := m.surface_get_arrays(si)
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null and idx.size() > 0 else arr[Mesh.ARRAY_VERTEX].size()) / 3
		var contorno := g.material_override != null and g.material_override.next_pass != null
		tris *= vezes * (2 if contorno else 1)
		var chave := "%s @%s sombra=%d contorno=%s" % [nome, pai, g.cast_shadow, str(contorno)]
		if not grupos.has(chave):
			grupos[chave] = [0, 0]
		grupos[chave][0] += tris
		grupos[chave][1] += 1
	var lista := []
	var total := 0
	for k in grupos:
		lista.append([grupos[k][0], "%3d x %s" % [grupos[k][1], k]])
		total += grupos[k][0]
	print("OBJ TOTAL triangulos (sem sombra) = ", total)
	var por_pai := {}
	for k in grupos:
		var pai: String = k.split("@")[1].split(" ")[0]
		por_pai[pai] = int(por_pai.get(pai, 0)) + int(grupos[k][1])
	var lp := []
	for k in por_pai:
		lp.append([por_pai[k], k])
	lp.sort()
	lp.reverse()
	var n := 0
	for l in lp:
		n += l[0]
	print("OBJ TOTAL objetos visiveis = ", n, "   por pai: ", lp.slice(0, 25))
	lista.sort()
	lista.reverse()
	for l in lista.slice(0, 60):
		print("OBJ %7d  %s" % [l[0], l[1]])
	get_tree().quit()
