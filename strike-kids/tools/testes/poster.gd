extends Node

## CENA DO PÔSTER (sem HUD): Bob voando com os jatos, Mia pulando e os
## pinos explodindo atrás. Renderiza a imagem "crua" que o
## tools/testes/montar_posteres.py transforma em pôster/banner.
##   godot --path . --fixed-fps 30 res://tools/testes/poster.tscn -- --janela=1080x1920 --saida=arquivo.png --formato=vertical
## --tema=parque|espaco|mar|dinos escolhe o cenário. --formato=cenario faz
## um plano aberto do cenário (para a folha dos 4 cenários).

var saida := "/tmp/poster.png"
var formato := "vertical"
var tema := "parque"
var quadro := 0
var cam: Camera3D
var mundo: Mundo
var pinos: Pinos
var efeitos: Efeitos
var bola: Bola
var bob: Personagem
var mia: Personagem


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--saida="):
			saida = a.substr(8)
		elif a.begins_with("--formato="):
			formato = a.substr(10)
		elif a.begins_with("--tema="):
			tema = a.substr(7)
	mundo = Mundo.new()
	add_child(mundo)
	mundo.construir()
	mundo.aplicar_qualidade("alta")
	mundo.aplicar_tema(tema)
	mundo.lampadas(1)
	pinos = Pinos.new()
	add_child(pinos)
	pinos.montar()
	efeitos = Efeitos.new()
	add_child(efeitos)
	bola = Bola.new()
	add_child(bola)
	bola.vestir("bob")
	bola.guardar()
	bob = Personagem.new()
	add_child(bob)
	bob.montar("bob")
	mia = Personagem.new()
	add_child(mia)
	mia.montar("mia")
	var v := formato == "vertical"
	bob.posicionar(Vector3(-0.6 if v else -1.15, 0, Mundo.Z_PINO1 + 4.7), 16)
	mia.posicionar(Vector3(0.62 if v else 1.15, 0, Mundo.Z_PINO1 + 5.0), -14)
	mundo.ambiente.tonemap_exposure = 0.9
	bob.tocar("vitoria", 0.01, true)
	bob.jatos(true)
	bob.expressao("empolgado")
	mia.tocar("parado", 0.01, true)
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	if formato == "cenario":
		bob.posicionar(Vector3(-0.75, 0, 1.4), 12)
		mia.posicionar(Vector3(0.75, 0, 1.4), -12)
		bob.jatos(false)
		bob.tocar("danca", 0.01, true)
		mia.tocar("danca", 0.01, true)
		cam.fov = 52
		cam.look_at_from_position(Vector3(0.0, 2.3, 5.2), Vector3(0, 1.6, Mundo.Z_PINO1 + 2.0))
	elif v:
		cam.fov = 50
		cam.look_at_from_position(Vector3(0.0, 1.5, Mundo.Z_PINO1 + 9.3), Vector3(0, 0.95, Mundo.Z_PINO1 + 1.6))
	else:
		cam.fov = 34
		cam.look_at_from_position(Vector3(0.0, 1.0, Mundo.Z_PINO1 + 8.4), Vector3(0, 0.85, Mundo.Z_PINO1 + 1.6))


func _process(_d: float) -> void:
	quadro += 1
	if quadro == 12:
		mia.tocar("feliz", 0.01, true)
	if quadro == 16 and formato != "cenario":
		pinos.soltar_todos()
		for p in pinos.pinos:
			p.sleeping = false
			p.apply_impulse(Vector3(randf_range(-0.6, 0.6), randf_range(0.5, 1.6), randf_range(-0.6, 0.2)), Vector3(0, 0.35, 0))
		bola.lancar(Vector3(0.04, Bola.RAIO, Mundo.Z_PINO1 + 0.8), Vector3(0, 0, -3.0))
		bola.acender(0.6)
		efeitos.estrelas(Vector3(0, 0.7, Mundo.Z_PINO1 - 0.2), 40, 1.2)
		efeitos.confete(Vector3(0, 1.8, Mundo.Z_PINO1 + 3.5), 2.2, 120)
	if quadro == 27:
		mia.expressao("risada")
	if quadro == 28:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(saida)
		print("salvo ", saida)
		get_tree().quit()
