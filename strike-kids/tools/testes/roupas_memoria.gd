extends Node

## ROUPINHAS SEM PESAR: confere que cada roupinha carrega em segundo plano,
## troca rápido, e que a memória volta ao que era quando o bichinho volta
## para a roupa de sempre (e quando um pedido é solto sem uso).
##   godot --headless --path . res://tools/testes/roupas_memoria.tscn

func _ready() -> void:
	_rodar.call_deferred()


func _contar() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))


func _rodar() -> void:
	var p := Personagem.new()
	add_child(p)
	p.montar("bob")
	for i in 5:
		await get_tree().process_frame
	var base := _contar()
	print("base: ", base, " recursos")
	for r in ["pirata", "dino", "astronauta", "parque"]:
		var t0 := Time.get_ticks_usec()
		p.pedir_roupa(r)
		var pedido_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var n := 0
		while ResourceLoader.load_threaded_get_status("res://modelos/roupas/bob_%s.scn" % r) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
			n += 1
		t0 = Time.get_ticks_usec()
		p.trocar_roupa(r)
		var troca_ms := (Time.get_ticks_usec() - t0) / 1000.0
		await get_tree().process_frame
		print("%s: pedido %.2f ms, carregou em %d quadros, troca %.2f ms, recursos %d, helice %s, estampa %s" % [r, pedido_ms,
			n, troca_ms, _contar(), str(p._helice != null and p._helice.visible),
			str((p._pecas["corpo"] as MeshInstance3D).material_override.get_shader_parameter("estampa"))])
	p.trocar_roupa("")
	for i in 3:
		await get_tree().process_frame
	print("de volta à roupa de sempre: recursos %d (base %d), helice %s, estampa %s" % [_contar(), base,
		str(p._helice.visible), str((p._pecas["corpo"] as MeshInstance3D).material_override.get_shader_parameter("estampa"))])
	# pedido que não vai ser usado: sai da memória quando termina de carregar
	p.pedir_roupa("dino")
	p.soltar_pedidos()
	for i in 120:
		await get_tree().process_frame
	print("pedido solto: recursos %d (base %d), pendentes %d" % [_contar(), base, p._descartar.size()])
	# carga sem pedido antes (síncrona)
	var t1 := Time.get_ticks_usec()
	p.trocar_roupa("astronauta")
	print("troca sem pedir antes: %.1f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
	p.trocar_roupa("")
	await get_tree().process_frame
	await get_tree().process_frame
	var fim := _contar()
	print("fim: recursos %d (base %d)" % [fim, base])
	print("ROUPAS_TESTE %s" % ("OK" if fim == base else "FALHOU"))
	get_tree().quit(0 if fim == base else 1)
