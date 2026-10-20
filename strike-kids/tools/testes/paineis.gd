extends Control

## Amostra dos painéis com volume (tools/testes): salva uma imagem.
##   godot --path . res://tools/testes/paineis.tscn -- --janela=1080x1920 saida.png

func _ready() -> void:
	var fundo := ColorRect.new()
	fundo.color = Color("#7EC8F0")
	fundo.size = Vector2(1080, 1920)
	add_child(fundo)
	var cores := [Color("#1A4FA8"), Color("#169BD5"), Color("#FF7A21"), Color("#FFC21A"), Color("#FFFFFF"), Color("#2DBE4E")]
	for i in cores.size():
		var p := Painel3D.new(cores[i], 34, 12, 6)
		p.position = Vector2(80 + (i % 2) * 480, 120 + (i / 2) * 300)
		p.size = Vector2(420, 220)
		add_child(p)
		if i == 3:
			p.realcar(1.0)
	var b := Painel3D.new(Color("#FFC21A"), 60, 16, 7)
	b.position = Vector2(140, 1100)
	b.size = Vector2(800, 150)
	add_child(b)
	var f := Painel3D.new(Color("#1A4FA8"), 20, 6, 4)
	f.position = Vector2(140, 1400)
	f.size = Vector2(800, 50)
	add_child(f)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var a := Array(OS.get_cmdline_user_args()).filter(func(x): return not str(x).begins_with("--janela="))
	img.save_png(a[0] if a.size() > 0 else "user://paineis.png")
	get_tree().quit()
