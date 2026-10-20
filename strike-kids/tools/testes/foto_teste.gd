extends Node

## TESTE DA FOTO NO CAMINHO DA TV BOX, com o plugin Android SIMULADO (no PC):
##   godot --path . res://tools/testes/foto_teste.tscn -- --saida=pasta
## Confere, como na máquina (e como no jogo de soco):
##   1. webcam só no USB, sem permissão: a janela USB (uma vez na vida; de
##      novo só pelo operador) não aparece logo de
##      cara (só depois de 20 s na tela de espera) e aparece uma vez;
##   2. com a webcam como câmera do sistema, a janela USB NUNCA aparece
##      (mesmo se o Android contar zero câmeras por um instante);
##   3. a câmera ACORDA e fica ligada sem ninguém vendo (só contando);
##   4. START não reabre a câmera; a foto sai na hora (câmera quente);
##   5. dois jogadores -> duas fotos diferentes; um jogador -> uma foto;
##   6. depois da foto a câmera continua ligada (não fica abrindo/fechando);
##   7. o app pausado (janela do Android) solta a câmera: ela volta sozinha;
##   8. câmera muda: reabre no máximo 3 vezes, o jogo pula o "SORRIA!" e a
##      foto desiste em ~4 s (o jogo segue com o mascote).

var saida := "user://foto_teste"
var falhas := 0


class PluginFalso extends RefCounted:
	var permitido := false
	var sistema := false          # a webcam aparece como câmera do sistema
	var pedidos_usb := 0
	var aberta_em := -1
	var abertas := 0
	var fechadas := 0
	var vendo := true
	var mudo := false
	var _n := 0
	var _w := 640
	var _h := 480
	var _y := PackedByteArray()
	var _uv := PackedByteArray()
	var _escuro_y := PackedByteArray()
	var _escuro_uv := PackedByteArray()
	var atraso_ms := 1500        # a câmera demora para mandar o 1º quadro
	var escuro_ms := 800         # e começa escura (exposição se ajustando)

	func usar_foto(caminho: String) -> void:
		var img := Image.load_from_file(ProjectSettings.globalize_path(caminho))
		img.resize(_w, _h)
		img.convert(Image.FORMAT_RGB8)
		_y.resize(_w * _h)
		_uv.resize((_w / 2) * (_h / 2) * 2)
		var d := img.get_data()
		for j in _h:
			for i in _w:
				var o := (j * _w + i) * 3
				_y[j * _w + i] = clampi(int(0.299 * d[o] + 0.587 * d[o + 1] + 0.114 * d[o + 2]), 0, 255)
		for j in _h / 2:
			for i in _w / 2:
				var o := ((j * 2) * _w + i * 2) * 3
				var r := float(d[o])
				var g := float(d[o + 1])
				var b := float(d[o + 2])
				var k := (j * (_w / 2) + i) * 2
				_uv[k] = clampi(int(-0.168736 * r - 0.331264 * g + 0.5 * b + 128.0), 0, 255)
				_uv[k + 1] = clampi(int(0.5 * r - 0.418688 * g - 0.081312 * b + 128.0), 0, 255)
		_escuro_y = PackedByteArray()
		_escuro_y.resize(_w * _h)
		_escuro_y.fill(4)
		_escuro_uv = PackedByteArray()
		_escuro_uv.resize((_w / 2) * (_h / 2) * 2)
		_escuro_uv.fill(128)

	func listar() -> String:
		var t := ""
		if sistema:
			t += "c1:0|externa|1|1\n"
		return t + "uvc:5|externa|uvc|%s\n" % ("1" if permitido else "0")

	func usb_pendente() -> bool:
		return not permitido

	func pedir_usb() -> String:
		pedidos_usb += 1
		return "pedido"

	func ver(sim: bool) -> void:
		vendo = sim

	func abrir(_id: String, _largura: int, _altura: int) -> bool:
		aberta_em = Time.get_ticks_msec()
		abertas += 1
		_n = 0
		return true

	func fechar() -> void:
		if aberta_em >= 0:
			fechadas += 1
		aberta_em = -1

	func estado() -> String:
		return "parada" if aberta_em < 0 else "ok"

	func fonte() -> String:
		return "uvc"

	func _idade() -> int:
		return -1 if aberta_em < 0 else Time.get_ticks_msec() - aberta_em

	func quadros() -> int:
		var t := _idade()
		if t < atraso_ms or mudo:
			return _n
		_n += 1
		return _n

	func largura() -> int:
		return _w

	func altura() -> int:
		return _h

	# sem ninguém vendo, o plugin só conta: nada de imagem
	func plano_y() -> PackedByteArray:
		if not vendo:
			return PackedByteArray()
		return _escuro_y if _idade() < atraso_ms + escuro_ms else _y

	func plano_uv() -> PackedByteArray:
		if not vendo:
			return PackedByteArray()
		return _escuro_uv if _idade() < atraso_ms + escuro_ms else _uv

	func relatorio() -> String:
		return "plugin falso"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--saida="):
			saida = a.substr(8)
	DirAccess.make_dir_recursive_absolute(saida)
	_rodar()


func checar(ok: bool, texto: String) -> void:
	print(("OK    " if ok else "FALHA ") + texto)
	if not ok:
		falhas += 1


func esperar(seg: float) -> void:
	await get_tree().create_timer(seg).timeout


func diferenca(a: Image, b: Image) -> float:
	var dif := 0.0
	for i in 64:
		var x := (i * 37) % a.get_width()
		var yy := (i * 53) % a.get_height()
		var ca := a.get_pixel(x, yy)
		var cb := b.get_pixel(x, yy)
		dif += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return dif / 64.0


func _rodar() -> void:
	# o Fotos procura a câmera 1 s depois de abrir: espera e troca pelo falso
	await esperar(1.6)
	var p := PluginFalso.new()
	p.usar_foto("res://tools/testes/foto_teste.png")
	Fotos._plugin = p
	Fotos.fonte = "android"
	Fotos.status = "procurando"
	Fotos._lembrancas = ConfigFile.new()   # como numa TV Box nova (nada pedido ainda)
	Fotos._sistema_visto = false
	Fotos._busca_desde_ms = -1
	Ajustes.definir("jogo", "foto", true)

	# 1. webcam só no USB, sem permissão
	Fotos._procurar_android()
	checar(Fotos.status == "sem_permissao_usb", "webcam so no USB, sem permissao -> status %s" % Fotos.status)
	Fotos.na_espera()
	checar(p.pedidos_usb == 0, "logo de cara a janela USB NAO aparece (o Android ainda pode contar zero cameras)")
	Fotos.espera_usb_ms = 0
	Fotos.na_espera()
	checar(p.pedidos_usb == 1, "na espera, depois do tempo, o jogo pediu a permissao USB (%d pedido)" % p.pedidos_usb)
	# só na primeira vez: a janela não volta sozinha, nem com o jogo reaberto
	Fotos.na_espera()
	Fotos.na_espera()
	checar(p.pedidos_usb == 1, "a janela USB nao volta sozinha (%d pedido)" % p.pedidos_usb)
	Fotos._lembrancas = null   # o jogo abriu de novo: lê o que guardou
	Fotos.na_espera()
	checar(p.pedidos_usb == 1, "nem depois de abrir o jogo de novo (lembra no camera.cfg)")
	Fotos._pedir_agora = true  # o operador pede no TESTE DA CÂMERA
	Fotos.na_espera()
	checar(p.pedidos_usb == 2, "o operador pede de novo no menu (%d pedidos)" % p.pedidos_usb)
	p.permitido = true
	Fotos.na_espera()
	checar(Fotos.pronta(), "permissao dada -> camera pronta (%s, %s)" % [Fotos.status, Fotos.nome_camera])
	checar(p.abertas == 0, "antes de acordar a camera nao abre (abrir %d vez)" % p.abertas)

	# 2. webcam como câmera do sistema: janela USB nunca
	p.sistema = true
	p.permitido = false
	Fotos.status = "procurando"
	Fotos._procurar_android()
	checar(Fotos.pronta() and Fotos.nome_camera == "câmera USB", "webcam como camera do sistema -> pronta (%s)" % Fotos.nome_camera)
	p.sistema = false          # o Android conta zero por um instante
	Fotos.status = "procurando"
	Fotos._procurar_android()
	var pedidos_antes := p.pedidos_usb
	Fotos._pedir_agora = true  # nem se o operador pedir: a câmera do sistema basta
	Fotos.na_espera()
	checar(p.pedidos_usb == pedidos_antes, "camera do sistema ja vista: sem janela USB a toa (%d pedido a mais)" % (p.pedidos_usb - pedidos_antes))
	Fotos._pedir_agora = false
	p.sistema = true
	Fotos.status = "procurando"
	Fotos._procurar_android()

	# 3. acorda: liga sem ninguém vendo
	Fotos._acordar()
	checar(p.abertas == 1 and not p.vendo, "acordou: camera ligada (%d) e so contando (vendo=%s)" % [p.abertas, p.vendo])
	await esperar(3.2)
	checar(Fotos._vivo_ms > 0, "o vigia ve a camera viva (quadros chegando)")
	checar(Fotos._quadro_visto == -1, "sem ninguem vendo, nenhum quadro vira imagem (nao pesa)")

	# 4. START: não reabre; a foto sai na hora
	Fotos.limpar_partida()
	Fotos.preparar()
	checar(p.abertas == 1, "START nao reabre a camera (abrir %d vez)" % p.abertas)
	checar(Fotos.pode_fotografar(), "camera viva -> tem SORRIA!")
	checar(Fotos.ligar() and p.vendo, "SORRIA!: a camera passa a mandar imagem")
	var t0 := Time.get_ticks_msec()
	var f1: ImageTexture = await Fotos.tirar("j0")
	var dt := Time.get_ticks_msec() - t0
	checar(f1 != null and dt < 1000, "1a foto na hora (camera quente: %d ms)" % dt)
	if f1 != null:
		var img := f1.get_image()
		checar(not Fotos._escura(img) and Fotos._contraste(img) >= 0.04, "1a foto nao e escura (contraste %.2f)" % Fotos._contraste(img))
		img.save_png(saida.path_join("foto_j0.png"))

	# 5. segundo jogador: outra criança na frente da câmera
	p.usar_foto("res://tools/testes/foto_teste_2.png")
	await esperar(0.6)
	var f2: ImageTexture = await Fotos.tirar("j1")
	checar(f2 != null, "2a foto (segundo jogador) tirada")
	if f1 != null and f2 != null:
		var d := diferenca(f1.get_image(), f2.get_image())
		checar(d > 0.05, "as 2 fotos sao de criancas diferentes (diferenca %.2f)" % d)
		f2.get_image().save_png(saida.path_join("foto_j1.png"))
	checar(Fotos.foto("j0") != null and Fotos.foto("j1") != null, "2 jogadores -> 2 fotos (j0 e j1)")

	# 6. fim da sessão de fotos: continua ligada, só contando
	Fotos.desligar(0.1)
	await esperar(0.4)
	checar(not p.vendo and p.aberta_em >= 0 and p.fechadas == 0, "depois da foto a camera segue ligada (fechada %d vez, vendo=%s)" % [p.fechadas, p.vendo])

	# partida seguinte, um jogador: uma foto
	Fotos.limpar_partida()
	Fotos.preparar()
	p.usar_foto("res://tools/testes/foto_teste.png")
	checar(Fotos.pode_fotografar() and Fotos.ligar(), "partida 2: SORRIA! de novo")
	var f3: ImageTexture = await Fotos.tirar("j0")
	checar(f3 != null and Fotos.foto("j1") == null, "1 jogador -> 1 foto")
	if f2 != null and f3 != null:
		checar(diferenca(f2.get_image(), f3.get_image()) > 0.05, "a foto e da crianca de agora (nao a da partida anterior)")
	Fotos.desligar(0.1)
	await esperar(0.4)
	checar(p.abertas == 1 and p.fechadas == 0, "2 partidas, a camera abriu 1 vez so (abrir %d, fechar %d)" % [p.abertas, p.fechadas])

	# 7. o app pausou (janela do Android): o plugin solta a câmera; ela volta
	p.fechar()
	await esperar(1.3)
	checar(p.abertas == 2 and p.aberta_em >= 0 and not p.vendo, "depois da pausa a camera voltou sozinha (abrir %d)" % p.abertas)

	# 8. câmera muda: reabre do zero no máximo 3 vezes
	p.mudo = true
	Fotos.reabrir_ms = 300
	Fotos._vivo_ms = Time.get_ticks_msec() - 1000
	var antes := p.abertas
	for i in 8:
		await esperar(0.35)
		Fotos.na_espera()
	checar(p.abertas - antes == 3, "camera muda: reabriu %d vezes (maximo 3)" % (p.abertas - antes))
	Fotos._aberta_ms -= 30000
	Fotos._vivo_ms -= 30000
	checar(not Fotos.pode_fotografar(), "camera muda ha muito tempo: o jogo pula o SORRIA! (mascote)")
	Fotos.ligar()
	t0 = Time.get_ticks_msec()
	var f4: ImageTexture = await Fotos.tirar("j2")
	dt = Time.get_ticks_msec() - t0
	checar(f4 == null and dt < 5000, "camera muda: a foto desiste em %d ms e o jogo segue" % dt)
	print("FOTO_TESTE %s (%d falha(s))" % ["OK" if falhas == 0 else "FALHOU", falhas])
	get_tree().quit(0 if falhas == 0 else 1)
