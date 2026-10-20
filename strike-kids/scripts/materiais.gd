class_name Materiais
extends RefCounted

## FÁBRICA DE MATERIAIS (com cache dos shaders).

const TOON := "res://shaders/toon.gdshader"
const TOON_PERSONAGEM := "res://shaders/toon_personagem.gdshader"
const CONTORNO := "res://shaders/contorno.gdshader"
const SOMBRA := "res://shaders/sombra.gdshader"
const ADITIVO := "res://shaders/aditivo.gdshader"

static var _shaders := {}
static var _texturas := {}
static var contornos_ligados := true


## Fonte com as letras JÁ DESENHADAS em cada tamanho que o jogo usa
## (fontes/*_pronta.res, feitas jogando o jogo inteiro sozinho:
## tools/testes/glifos.gd). Desenhar uma letra com contorno na hora, na
## primeira vez que um texto aparece, dava travadinhas na TV Box.
static func fonte(nome: String) -> Font:
	var pronta := "res://fontes/%s_pronta.res" % nome
	if ResourceLoader.exists(pronta) and not OS.get_cmdline_user_args().has("--glifos"):
		return load(pronta)
	return load("res://fontes/%s.ttf" % nome)


static func shader(caminho: String) -> Shader:
	if not _shaders.has(caminho):
		_shaders[caminho] = load(caminho)
	return _shaders[caminho]


static func textura(nome: String) -> Texture2D:
	if not _texturas.has(nome):
		var c := "res://texturas/%s.png" % nome
		if not ResourceLoader.exists(c):
			c = "res://ui/%s.png" % nome
		_texturas[nome] = load(c) if ResourceLoader.exists(c) else null
	return _texturas[nome]


## Toon com cor do vértice. `personagem`: não recebe sombra (rosto limpo).
static func toon(personagem := false, contorno := 0.0035, parametros := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(TOON_PERSONAGEM if personagem else TOON)
	for k in parametros:
		m.set_shader_parameter(k, parametros[k])
	if contorno > 0.0 and contornos_ligados:
		var c := ShaderMaterial.new()
		c.shader = shader(CONTORNO)
		c.set_shader_parameter("espessura", contorno)
		m.next_pass = c
	return m


static func sombra_blob(forca := 0.55) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(SOMBRA)
	m.set_shader_parameter("textura", textura("sombra"))
	m.set_shader_parameter("forca", forca)
	m.render_priority = -1
	return m


static func aditivo(nome_textura: String, cor := Color.WHITE, forca := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(ADITIVO)
	m.set_shader_parameter("textura", textura(nome_textura))
	m.set_shader_parameter("cor", cor)
	m.set_shader_parameter("forca", forca)
	return m


## Material de partícula (billboard, cor da partícula, soma ou mistura).
static func particula(nome_textura: String, somar := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if somar else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = textura(nome_textura)
	m.disable_receive_shadows = true
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


## Material simples (cor sólida, toon), para peças montadas no código.
static func cor_toon(c: Color, contorno := 0.0, parametros := {}) -> ShaderMaterial:
	var p := parametros.duplicate()
	p["tinta"] = c
	return toon(false, contorno, p)


## Malha com cor de vértice branca (BoxMesh etc.): o toon usa COLOR, então
## para malhas sem cor de vértice o shader recebe branco + tinta.
