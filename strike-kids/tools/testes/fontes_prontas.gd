extends SceneTree

## FONTES PRONTAS: monta fontes/*_pronta.res com as letras já desenhadas em
## cada tamanho (e contorno) que o jogo usa — anotados em dados/glifos.json
## por tools/testes/glifos.gd. Assim nenhuma letra é desenhada na hora em
## que um texto aparece (na TV Box isso dava travadinhas nas cenas).
##   godot --headless --path . -s res://tools/testes/fontes_prontas.gd
## Em cada tamanho: as letras que apareceram, mais os números (pontos,
## rodadas...). Nos tamanhos de texto (até 90) também as maiúsculas e a
## pontuação; e minúsculas/acentos onde já apareceram. Título grande só
## com o que apareceu: letra grande ocupa muita memória.

const ARQUIVO := "res://dados/glifos.json"
const NUMEROS := "0123456789"
const PONTUACAO := " !?.,:%()-+/"
const MAIUSCULAS := "ABCDEFGHIJKLMNOPQRSTUVWXYZÁÂÃÉÊÍÓÔÕÚÇ"
const MINUSCULAS := "abcdefghijklmnopqrstuvwxyzáâãéêíóôõúç"
## fontes de texto corrido (nomes, menus, números): ganham o alfabeto todo
const TEXTO := ["fredoka_700", "fredoka_600"]


func _init() -> void:
	var dados: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))
	var total := 0
	for nome in dados:
		var f := load("res://fontes/%s.ttf" % nome) as FontFile
		var tamanhos: Dictionary = dados[nome]
		var n_letras := 0
		var t0 := Time.get_ticks_msec()
		for chave in tamanhos:
			var p: PackedStringArray = str(chave).split(",")
			var tam := Vector2i(int(p[0]), int(p[1]))
			var vistas: String = tamanhos[chave]
			var letras := vistas + NUMEROS
			var tem_min := false
			for ch in MINUSCULAS:
				if vistas.contains(ch):
					tem_min = true
			if nome in TEXTO and tam.x <= 90:
				letras += PONTUACAO + MAIUSCULAS
				if tem_min:
					letras += MINUSCULAS
			var feitas := {}
			for ch in letras:
				var g := f.get_glyph_index(tam.x, ch.unicode_at(0), 0)
				if g != 0 and not feitas.has(g):
					feitas[g] = true
					f.render_glyph(0, tam, g)
			n_letras += feitas.size()
			_juntar(f, tam)
		var bytes := 0
		var texturas := 0
		for tam in f.get_size_cache_list(0):
			for k in f.get_texture_count(0, tam):
				bytes += f.get_texture_image(0, tam, k).get_data().size()
				texturas += 1
		var caminho := "res://fontes/%s_pronta.res" % nome
		var e := ResourceSaver.save(f, caminho, ResourceSaver.FLAG_COMPRESS)
		var arq := FileAccess.get_file_as_bytes(caminho).size()
		total += arq
		print("FONTE %s: %d tamanhos, %d letras desenhadas em %d ms, %d texturas (%.1f MB na memória), arquivo %.1f MB (%s)" % [
			nome, tamanhos.size(), n_letras, Time.get_ticks_msec() - t0, texturas, bytes / 1048576.0, arq / 1048576.0, error_string(e)])
	print("FONTES_PRONTAS OK (%.1f MB)" % (total / 1048576.0))
	quit()


## O motor guarda as letras de cada tamanho em páginas de até 1024x1024
## (2 MB cada, na memória e na placa de vídeo), quase vazias aqui: poucas
## letras por tamanho. Junta as letras de cada tamanho numa textura só, do
## tamanho certo (com 1 pixel de folga em volta de cada letra, como o motor
## faz). A textura fica marcada como cheia: uma letra que não foi preparada
## ganha uma página nova, como antes.
func _juntar(f: FontFile, tam: Vector2i) -> void:
	var pecas := []
	var area := 0
	var maior_largura := 0
	for g in f.get_glyph_list(0, tam):
		var t := f.get_glyph_texture_idx(0, tam, g)
		var uv := f.get_glyph_uv_rect(0, tam, g)
		if t < 0 or uv.size.x < 1.0 or uv.size.y < 1.0:
			continue
		var origem := Rect2i(Vector2i(uv.position) - Vector2i.ONE, Vector2i(uv.size) + Vector2i(2, 2))
		pecas.append([g, t, origem, uv.size])
		area += origem.size.x * origem.size.y
		maior_largura = max(maior_largura, origem.size.x)
	if pecas.is_empty():
		return
	pecas.sort_custom(func(a, b): return a[2].size.y > b[2].size.y)
	var formato := f.get_texture_image(0, tam, 0).get_format()
	# a largura que der a menor textura (a altura não precisa ser potência de 2)
	var melhor := {}
	for largura in [64, 128, 256, 512, 1024, 2048]:
		if largura < maior_largura:
			continue
		var pos := {}
		var x := 0
		var y := 0
		var altura_linha := 0
		for p in pecas:
			var s: Vector2i = p[2].size
			if x + s.x > largura:
				y += altura_linha
				x = 0
				altura_linha = 0
			pos[p[0]] = Vector2i(x, y)
			x += s.x
			altura_linha = max(altura_linha, s.y)
		var altura := y + altura_linha
		altura = (altura + 3) / 4 * 4
		if altura > 2048:
			continue
		if melhor.is_empty() or largura * altura < melhor.largura * melhor.altura:
			melhor = {"largura": largura, "altura": altura, "pos": pos}
	if melhor.is_empty():
		return
	var antes := 0
	var origens := []
	for k in f.get_texture_count(0, tam):
		var im := f.get_texture_image(0, tam, k)
		origens.append(im)
		antes += im.get_width() * im.get_height()
	if melhor.largura * melhor.altura >= antes:
		return
	var img := Image.create_empty(melhor.largura, melhor.altura, false, formato)
	for p in pecas:
		img.blit_rect(origens[p[1]], p[2], melhor.pos[p[0]])
	f.clear_textures(0, tam)
	f.set_texture_image(0, tam, 0, img)
	f.set_texture_offsets(0, tam, 0, PackedInt32Array([melhor.largura, 0, 0, melhor.altura]))
	for p in pecas:
		f.set_glyph_texture_idx(0, tam, p[0], 0)
		f.set_glyph_uv_rect(0, tam, p[0], Rect2(Vector2(melhor.pos[p[0]] + Vector2i.ONE), p[3]))
