extends Node

## BANCADA DE DESEMPENHO (PC, testes): mede quanto CADA PARTE do desenho
## custa, ligando e desligando uma de cada vez, em 4 planos de câmera.
##   godot --path . -- --janela=720x1280 --benchmark [--quadros=60]
## Imprime uma tabela: ms por quadro (relógio), ms de desenho do 3D e da
## tela (medidos pela placa de vídeo), desenhos e triângulos.
## Na máquina de teste (sem placa de vídeo, o "llvmpipe" desenha no
## processador) os números se parecem com os de uma TV Box fraca: o que
## pesa aqui, pesa lá — COM UMA EXCEÇÃO: imagens com compressão de alta
## qualidade (BPTC no PC / ASTC na TV Box: logo, madeira, rostos, bola)
## parecem caras aqui porque o llvmpipe as descomprime no processador;
## numa placa de vídeo de verdade (inclusive a Mali-G31) isso é de graça.
## Ex.: "sem_logo" tira ~60 ms aqui e quase nada na TV Box.
## Configs extras: sem_arco, sem_logo, sem_lampadas, sem_tiras;
## --planos=cacapa,espera mede só esses planos.

const PLANOS := {
	"espera": [Vector3(0.0, 1.05, 2.2), Vector3(0.0, 0.18, -9.9), 34.0, 40.0],
	"cacapa": [Vector3(0.0, 0.9, -6.5), Vector3(0.0, 0.7, -12.5), 44.0, 40.0],
	"bichos": [Vector3(0.0, 1.35, 6.6), Vector3(0.0, 1.0, 2.3), 40.0, 44.0],
	"jogador": [Vector3(0.6, 1.1, 0.4), Vector3(-0.3, 0.9, 6.0), 50.0, 50.0],
}

var principal: Node
var quadros := 60
var _contornos := {}


func _ready() -> void:
	principal = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quadros="):
			quadros = int(a.substr(10))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_rodar.call_deferred()


func _esperar_quadros(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _rodar() -> void:
	# espera a atração (a abertura já preparou tudo)
	while principal.estado != principal.E.ATRACAO:
		await get_tree().process_frame
	principal.set("_adaptar", false)
	var vp: SubViewport = principal.vp
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var mundo: Mundo = principal.mundo
	var cfgs := ["base", "sem_contorno", "sem_hud", "sem_temas", "sem_terreno", "sem_bichos",
		"sem_ceu", "toon_simples", "sem_pista_shader", "metade"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--configs="):
			cfgs = Array(a.substr(10).split(","))
	print("BENCH qualidade=%s 3D=%dx%d janela=%s" % [principal.get("_qualidade"), vp.size.x, vp.size.y, str(get_window().size)])
	print("BENCH %-16s %-8s %8s %8s %8s %6s %8s" % ["config", "plano", "quadro", "gpu3d", "gputela", "desen", "triang"])
	var planos: Array = PLANOS.keys()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--planos="):
			planos = Array(a.substr(9).split(","))
	for cfg in cfgs:
		_aplicar(cfg, true)
		for nome in planos:
			var p: Array = PLANOS[nome]
			principal._demo_t = -1000.0
			principal.cam.corte(p[0], p[1], p[2], p[3])
			await _esperar_quadros(12)
			var r := await _medir()
			print("BENCH %-16s %-8s %8.1f %8.1f %8.1f %6d %8d" % [cfg, nome, r[0], r[1], r[2], r[3], r[4]])
		_aplicar(cfg, false)
	print("BENCH FIM")
	get_tree().quit()


func _medir() -> Array:
	var vp: SubViewport = principal.vp
	var rid := vp.get_viewport_rid()
	var raiz := get_viewport().get_viewport_rid()
	var soma_q := 0.0
	var soma_g := 0.0
	var soma_t := 0.0
	var t0 := Time.get_ticks_usec()
	for i in quadros:
		await get_tree().process_frame
		var t1 := Time.get_ticks_usec()
		soma_q += float(t1 - t0) / 1000.0
		t0 = t1
		principal._demo_t = -1000.0
		soma_g += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		soma_t += RenderingServer.viewport_get_measured_render_time_gpu(raiz)
	var d := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var tr := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	return [soma_q / quadros, soma_g / quadros, soma_t / quadros, d, tr]


func _aplicar(cfg: String, ligar: bool) -> void:
	var mundo: Mundo = principal.mundo
	var vp: SubViewport = principal.vp
	match cfg:
		"sem_contorno":
			if ligar:
				_contornos.clear()
				for no in vp.find_children("*", "GeometryInstance3D", true, false):
					var m: Material = (no as GeometryInstance3D).material_override
					if m != null and m.next_pass != null:
						_contornos[m] = m.next_pass
						m.next_pass = null
			else:
				for m in _contornos:
					(m as Material).next_pass = _contornos[m]
		"sem_neblina":
			mundo.ambiente.fog_enabled = not ligar
		"sem_hud":
			principal.hud.get_node(".").set("modulate", Color(1, 1, 1, 1))
			for f in principal.hud.get_children():
				if f != principal.hud.tela3d and f is CanvasItem:
					if ligar:
						f.set_meta("bench_vis", (f as CanvasItem).visible)
						(f as CanvasItem).visible = false
					elif f.has_meta("bench_vis"):
						(f as CanvasItem).visible = f.get_meta("bench_vis")
		"sem_temas":
			mundo.temas.visible = not ligar
		"sem_terreno":
			for no in mundo.get_children():
				if no is MeshInstance3D and (no as MeshInstance3D).mesh != null and (no as MeshInstance3D).mesh.resource_path.ends_with("terreno.res"):
					(no as MeshInstance3D).visible = not ligar
		"sem_bichos":
			for k in principal.personagens:
				(principal.personagens[k] as Node3D).visible = not ligar
		"sem_ceu":
			mundo.ambiente.background_mode = Environment.BG_COLOR if ligar else Environment.BG_SKY
		"sem_pista_shader":
			var mp: ShaderMaterial = mundo.mat_pista
			if ligar:
				var s := StandardMaterial3D.new()
				s.albedo_color = Color(0.9, 0.75, 0.55)
				set_meta("pista_shader", mp.shader)
				mp.shader = Shader.new()
				mp.shader.code = "shader_type spatial;\nvoid fragment(){ ALBEDO = vec3(0.9, 0.75, 0.55); }"
			else:
				mp.shader = get_meta("pista_shader")
		"sem_cortina":
			for no in mundo.find_children("cortina", "MeshInstance3D", true, false):
				(no as Node3D).visible = not ligar
		"sem_portal":
			for nome in ["arco", "logo"]:
				for no in mundo.find_children(nome, "Node3D", true, false):
					(no as Node3D).visible = not ligar
			for no in mundo.find_children("*", "MultiMeshInstance3D", false, false):
				(no as Node3D).visible = not ligar
		"sem_arco", "sem_logo":
			for no in mundo.find_children(cfg.substr(4), "Node3D", true, false):
				(no as Node3D).visible = not ligar
		"sem_lampadas":
			for no in mundo.find_children("*", "MultiMeshInstance3D", true, false):
				if (no as GeometryInstance3D).material_override == mundo.mat_lampadas:
					(no as Node3D).visible = not ligar
		"sem_tiras":
			mundo._tiras.visible = not ligar
		"toon_simples":
			# troca o shader toon por um de cor chapada (quanto custa o toon?)
			if ligar:
				var simples := Shader.new()
				simples.code = "shader_type spatial;\nrender_mode unshaded;\nuniform vec4 tinta : source_color = vec4(1.0);\nvoid fragment(){ ALBEDO = COLOR.rgb * tinta.rgb; }"
				var trocas := {}
				for no in vp.find_children("*", "GeometryInstance3D", true, false):
					var m := (no as GeometryInstance3D).material_override as ShaderMaterial
					if m != null and m.shader != null and m.shader.resource_path.find("toon") >= 0:
						trocas[m] = m.shader
						m.shader = simples
				set_meta("toon", trocas)
			else:
				var trocas: Dictionary = get_meta("toon")
				for m in trocas:
					(m as ShaderMaterial).shader = trocas[m]
		"msaa_0":
			if ligar:
				set_meta("msaa", vp.msaa_3d)
				vp.msaa_3d = Viewport.MSAA_DISABLED
			else:
				vp.msaa_3d = get_meta("msaa")
		"metade":
			if ligar:
				set_meta("tam", vp.size)
				vp.size = vp.size / 2
			else:
				vp.size = get_meta("tam")
