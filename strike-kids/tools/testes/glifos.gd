extends Node

## LETRAS PRONTAS (sem tranco na primeira vez que um texto aparece).
## A placa da TV Box desenha cada letra (com contorno e sombra) na primeira
## vez em que ela aparece num tamanho novo — e isso dava travadinhas nas
## cenas. Aqui o jogo inteiro é jogado sozinho (roteiro), mais as telas que
## o roteiro não passa (menus, avisos), e no fim fica anotado, para cada
## fonte e tamanho (com contorno), que letras apareceram: dados/glifos.json.
## Depois tools/testes/fontes_prontas.gd monta fontes/*_pronta.res com
## essas letras já desenhadas (o jogo carrega essas).
##   godot --path . --resolution 1080x1920 -- --janela=1080x1920 --roteiro=pasta --sem-sair --glifos [--jogadores=2]
## (rode em 1080x1920: a imagem da TV Box, 1 pixel do jogo = 1 pixel da tela;
## rode com 1 e com 2 jogadores: as anotações se somam)
## Com --glifos-conferir (em vez de --glifos) o jogo usa as fontes prontas e,
## no fim, mostra as letras que ainda tiveram de ser desenhadas na hora.

const FONTES := ["fredoka_700", "fredoka_600", "titan_one"]
const ARQUIVO := "res://dados/glifos.json"
## letras do jogo: ASCII, acentos do português e os símbolos dos menus
const FAIXAS := [[32, 126], [160, 255], [0x2014, 0x2014], [0x2192, 0x2192], [0x25B6, 0x25B6], [0x25CB, 0x25CB], [0x25CF, 0x25CF]]

var p: Node


func _ready() -> void:
	p = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rodar.call_deferred()


func esperar(seg: float) -> void:
	await get_tree().create_timer(seg, true, false, true).timeout


func quadros(n := 3) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _rodar() -> void:
	# a imagem 3D não interessa aqui (só as letras): sem ela, a máquina de
	# teste roda o jogo na velocidade certa
	await get_tree().process_frame
	p.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var conferir := OS.get_cmdline_user_args().has("--glifos-conferir")
	var antes := {}
	for nome in FONTES:
		var fo := Materiais.fonte(nome) as FontFile
		var d := {}
		for tam in fo.get_size_cache_list(0):
			d[tam] = fo.get_glyph_list(0, tam)
		antes[nome] = d
	# 1. o jogo inteiro (roteiro; sem --roteiro, só as telas abaixo)
	var roteiro: Node = null
	for i in 30:
		await get_tree().process_frame
		for c in p.get_children():
			if c.get_script() != null and str(c.get_script().resource_path).ends_with("roteiro.gd"):
				roteiro = c
		if roteiro != null:
			break
	if roteiro != null:
		while not roteiro.terminou:
			await esperar(0.5)
		print("GLIFOS: roteiro terminou")
	else:
		await esperar(6.0)
	var hud: Hud = p.hud
	# 2. telas que o roteiro não mostra
	hud.texto_grande("INSIRA FICHA", Color("#FFF6A8"), 1.0, 0.55)
	await quadros()
	for n in [10, 9, 3]:
		hud.inatividade(true, n)
		await quadros(2)
	hud.inatividade(false)
	hud.aviso_android(ArduinoBridge.DICA_USB)
	await quadros()
	hud.aviso_android(Fotos.DICA_CAMERA)
	await quadros()
	hud.aviso_android("")
	for nome in ["strike", "spare", "boa", "super", "quase", "pegando_fogo"]:
		for n in [1, 4, 7, 9]:
			hud.letreiro(nome, "%d %s!" % [n, "PINO" if n == 1 else "PINOS"], 0.5)
			await quadros(2)
	hud.letreiro("pegando_fogo", "3 STRIKES SEGUIDOS!", 0.5)
	await quadros()
	hud.letreiro("novo_recorde", "190 PONTOS", 0.5, 0.42)
	await quadros()
	# fim de jogo com 6 e 7 linhas na classificação do dia (o tamanho das
	# letras dela depende do número de linhas: até 5 do dia + quem jogou)
	var lista := []
	for k in 5:
		lista.append({"pontos": 190 - k * 23, "personagem": "bob" if k % 2 == 0 else "mia", "hora": "1%d:4%d" % [k, k], "foto": ""})
	for n_js in [1, 2]:
		var js := []
		for i in n_js:
			js.append({"personagem": "bob" if i == 0 else "mia", "pontos": 47 + i * 12, "estrelas": 2, "strikes": 1,
				"spares": 1, "foto": null, "posicao": 6 + i})
		hud.tela_fim(true, {"jogadores": js, "vencedor": 1 if n_js == 2 else 0, "recorde": false, "classificacao": lista})
		await esperar(2.5)
	hud.tela_fim(false)
	for tema in Temas.ORDEM:
		hud.anunciar_cenario(tema, 0.5)
		await quadros(2)
	for quem in ["bob", "mia"]:
		for r in [1, 2, 10]:
			hud.faixa(quem, "VEZ %s %s!" % ["DO" if quem == "bob" else "DA", quem.to_upper()], "RODADA %d" % r, null)
			await quadros(2)
	for n in [1, 2]:
		hud.jogadores(true, n, 0.5, 3)
		await quadros(2)
	hud.jogadores(false)
	p.medidor.mostrar(true)
	await esperar(1.2)
	p.medidor.mostrar(false)
	# o aviso de "aplicando os ajustes" (menu do operador)
	p._aviso_remontar()
	await quadros()
	for c in p._camada_menu.get_children():
		c.queue_free()
	# 3. menu do operador: todas as linhas e os testes
	p.abrir_menu(p.CENA_OPERADOR)
	await quadros()
	var m: Node = p._menu
	for i in m.ITENS.size():
		m._sel = i
		m._atualizar()
		await quadros(1)
	for acao in ["teste", "calibrar", "porta", "camera"]:
		m._sel = _indice(m, acao)
		m._acao()
		await quadros(3)
		m._sair_do_teste()
		await quadros(1)
	p.abrir_menu(p.CENA_BOTOES)
	await esperar(1.2)
	p.fechar_menu()
	await esperar(1.0)
	# 4. anota as letras que apareceram em cada tamanho de cada fonte
	# (somando com as anotadas antes, de outras partidas):
	# dados/glifos.json. As fontes prontas saem dele (fontes_prontas.gd).
	if conferir:
		_conferir(antes)
		get_tree().quit()
		return
	var dados := {}
	if FileAccess.file_exists(ARQUIVO):
		dados = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))
	for nome in FONTES:
		var f := Materiais.fonte(nome) as FontFile
		var por_letra := {}
		for faixa in FAIXAS:
			for c in range(faixa[0], faixa[1] + 1):
				var g := f.get_glyph_index(16, c, 0)
				if g != 0:
					por_letra[g] = String.chr(c)
		var d: Dictionary = dados.get(nome, {})
		for tam in f.get_size_cache_list(0):
			var chave := "%d,%d" % [tam.x, tam.y]
			var letras: String = d.get(chave, "")
			for g in f.get_glyph_list(0, tam):
				var ch: String = por_letra.get(g, "")
				if ch != "" and not letras.contains(ch):
					letras += ch
			d[chave] = letras
		dados[nome] = d
		print("GLIFOS %s: %d tamanhos" % [nome, d.size()])
	var arq := FileAccess.open(ARQUIVO, FileAccess.WRITE)
	arq.store_string(JSON.stringify(dados, "\t", true))
	arq.close()
	print("GLIFOS OK")
	get_tree().quit()


## Fontes prontas: o que foi desenhado na hora (devia ser nada, ou quase).
func _conferir(antes: Dictionary) -> void:
	var faltas := 0
	for nome in FONTES:
		var f := Materiais.fonte(nome) as FontFile
		var por_letra := {}
		for faixa in FAIXAS:
			for c in range(faixa[0], faixa[1] + 1):
				var g := f.get_glyph_index(16, c, 0)
				if g != 0:
					por_letra[g] = String.chr(c)
		var d: Dictionary = antes[nome]
		for tam in f.get_size_cache_list(0):
			var velhas: PackedInt32Array = d.get(tam, PackedInt32Array())
			var novas := ""
			var n := 0
			for g in f.get_glyph_list(0, tam):
				if not velhas.has(g):
					n += 1
					novas += por_letra.get(g, "?")
			if n > 0:
				faltas += n
				print("GLIFOS %s %s: %s %d letra(s) desenhada(s) na hora: \"%s\"" % [nome, tam, "TAMANHO NOVO," if not d.has(tam) else "", n, novas])
	print("GLIFOS CONFERIDOS: %d letra(s) desenhada(s) na hora" % faltas)


func _indice(m: Node, acao: String) -> int:
	for i in m.ITENS.size():
		if m.ITENS[i][2] == acao:
			return i
	return 0
