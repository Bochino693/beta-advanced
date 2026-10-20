extends Node

## BANCO DE PLANOS DE CÂMERA (conferir enquadramentos e acabamento).
##   godot --path . res://tools/testes/planos.tscn -- --janela=1080x1920 --saida=pasta [--tema=parque]
##      [--plano=nome:px,py,pz:ax,ay,az:fov_v:fov_h] (pode repetir)
## Monta o mundo (pista, pinos, cenário, Bob com a bola, Mia torcendo) e
## tira uma foto por plano, com a mesma abertura responsiva do jogo.
## Sem --plano: uma lista padrão (espera da jogada, canaletas, caçapa,
## fundo atrás dos jogadores).

const PADRAO := [
	"espera:0,1.25,2.45:0,0.15,-9:46:42",
	"canaleta:1.05,0.32,-1.2:0.85,-0.05,-5:40:40",
	"cacapa:0,0.55,-11.6:0,0.4,-16.5:38:44",
	"fundo_cacapa:0.9,0.9,-12.8:0,0.2,-16.6:44:44",
	"atras_jogadores:0,1.0,-1.0:0,0.9,6:50:50",
	"reacao:0.2,0.85,1.6:-0.28,0.65,3.15:34:34",
]

var saida := "user://planos"
var tema := "parque"
var planos: Array = []
var cam: CameraCine
var mundo: Mundo
var _i := 0
var _espera := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--saida="):
			saida = a.substr(8)
		elif a.begins_with("--tema="):
			tema = a.substr(7)
		elif a.begins_with("--plano="):
			planos.append(a.substr(8))
	if planos.is_empty():
		planos = PADRAO.duplicate()
	DirAccess.make_dir_recursive_absolute(saida)
	mundo = Mundo.new()
	add_child(mundo)
	mundo.construir()
	mundo.aplicar_qualidade("alta")
	mundo.aplicar_tema(tema)
	var pinos := Pinos.new()
	add_child(pinos)
	pinos.montar()
	var maquina := Maquina.new()
	add_child(maquina)
	maquina.montar(pinos)
	maquina.instantaneo()
	var bob := Personagem.new()
	add_child(bob)
	bob.montar("bob")
	bob.posicionar(Vector3(-0.28, 0, 3.15), 180)
	bob.segurar_bola(true)
	bob.tocar("pronto", 0.01, true)
	var mia := Personagem.new()
	add_child(mia)
	mia.montar("mia")
	mia.posicionar(Vector3(-1.85, 0, 1.0), 218)
	mia.tocar("torcida", 0.01, true)
	cam = CameraCine.new()
	add_child(cam)
	cam.current = true


func _process(_d: float) -> void:
	if _i >= planos.size():
		get_tree().quit()
		return
	if _espera == 0:
		var p: PackedStringArray = (planos[_i] as String).split(":")
		var v := func(t: String) -> Vector3:
			var c := t.split(",")
			return Vector3(float(c[0]), float(c[1]), float(c[2]))
		cam.corte(v.call(p[1]), v.call(p[2]), float(p[3]), float(p[4]))
	_espera += 1
	if _espera < 20:
		return
	await RenderingServer.frame_post_draw
	if _espera < 20:
		return
	var img := get_viewport().get_texture().get_image()
	var nome := (planos[_i] as String).split(":")[0]
	img.save_png("%s/%s.png" % [saida, nome])
	print("plano ", nome)
	_espera = 0
	_i += 1
