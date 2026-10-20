extends Node

## FOTOS EM INSTANTES FIXOS do jogo rodando (diagnóstico de qualidade).
##   godot --path . --fixed-fps 30 -- --janela=1080x1920 --instantes=pasta --em=1.0,2.5,6.0
## Tira uma foto da tela em cada instante (segundos desde o começo) e sai.

var pasta := "user://instantes"
var tempos: Array = [1.0, 3.0, 6.0]
var t := 0.0
var n := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--instantes="):
			pasta = a.substr(12)
		elif a.begins_with("--em="):
			tempos = Array(a.substr(5).split(",")).map(func(x): return float(x))
	DirAccess.make_dir_recursive_absolute(pasta)


func _process(delta: float) -> void:
	t += delta
	if n < tempos.size() and t >= float(tempos[n]):
		var nome := "%s/t%05.1f.png" % [pasta, float(tempos[n])]
		n += 1
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(nome)
		print("FOTO ", nome)
		if n >= tempos.size():
			get_tree().quit()
