extends Control

## Amostra da TELA FINAL com a CLASSIFICAÇÃO DE HOJE (dados de mentira):
##   godot --path . res://tools/testes/tela_fim.tscn -- --janela=540x960 saida.png [--um]
## --um: um jogador só. Usa a classificação gravada (user://) se houver.

func _ready() -> void:
	var a := Array(OS.get_cmdline_user_args()).filter(func(x): return not str(x).begins_with("--"))
	var um := OS.get_cmdline_user_args().has("--um")
	var hud := Hud.new()
	add_child(hud)
	hud.montar(null)
	hud.layout()
	var lista := [
		{"pontos": 210, "personagem": "mia", "foto": "", "hora": "10:12"},
		{"pontos": 180, "personagem": "bob", "foto": "", "hora": "10:40"},
		{"pontos": 150, "personagem": "bob", "foto": "", "hora": "11:05"},
		{"pontos": 120, "personagem": "mia", "foto": "", "hora": "11:30"},
		{"pontos": 90, "personagem": "bob", "foto": "", "hora": "11:52"},
	]
	var foto := ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path("res://tools/testes/foto_teste.png")))
	var js := [{"personagem": "bob", "pontos": 150, "estrelas": 2, "strikes": 1, "spares": 1, "foto": foto, "posicao": 3}]
	if not um:
		js.append({"personagem": "mia", "pontos": 60, "estrelas": 1, "strikes": 0, "spares": 1, "foto": null, "posicao": 8})
	hud.tela_fim(true, {"jogadores": js, "vencedor": 0, "classificacao": lista})
	await get_tree().create_timer(4.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(a[0] if a.size() > 0 else "user://tela_fim.png")
	get_tree().quit()
