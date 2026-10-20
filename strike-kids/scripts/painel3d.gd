class_name Painel3D
extends Control

## PLACA COM VOLUME das telas (placar, botões, cartões, faixas): frente em
## degradê com verniz, lateral mais escura, contorno azul-marinho e sombra.
## Desenhada por shader (shaders/painel3d.gdshader): nítida em qualquer
## resolução. Os filhos (textos, fotos) ficam por cima, como num Panel.

const SHADER := preload("res://shaders/painel3d.gdshader")
const MARINHO := Color("#0B1F45")

var mat: ShaderMaterial
var _fundo: ColorRect
var _margem := 30.0
var _raio := 30.0
var _espessura := 10.0
var _borda := 5.0


func _init(cor := Color("#1A4FA8"), raio := 30.0, espessura := 10.0, borda := 5.0) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	_fundo = ColorRect.new()
	_fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fundo.material = mat
	add_child(_fundo, false, Node.INTERNAL_MODE_FRONT)
	pintar(cor)
	formato(raio, espessura, borda)


## Cor principal (o degradê, a lateral e o filete saem dela).
func pintar(cor: Color, borda := MARINHO, brilho := 0.24) -> Painel3D:
	mat.set_shader_parameter("cor_topo", cor.lightened(0.2))
	mat.set_shader_parameter("cor_base", cor.darkened(0.14))
	mat.set_shader_parameter("cor_lado", cor.darkened(0.52))
	mat.set_shader_parameter("cor_borda", borda)
	mat.set_shader_parameter("brilho", brilho)
	return self


func formato(raio: float, espessura: float, borda: float) -> Painel3D:
	_raio = raio
	_espessura = espessura
	_borda = borda
	mat.set_shader_parameter("borda", borda)
	_margem = maxf(12.0, raio * 0.9 + espessura)
	_ajustar()
	return self


## 0..1: halo amarelo de "escolhido".
func realcar(valor: float) -> void:
	mat.set_shader_parameter("realce", valor)


func sombra(forca: float) -> void:
	mat.set_shader_parameter("sombra", forca)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_ENTER_TREE:
		_ajustar()


func _ajustar() -> void:
	_fundo.position = -Vector2(_margem, _margem)
	_fundo.size = size + Vector2(_margem, _margem) * 2.0
	mat.set_shader_parameter("tamanho", size)
	mat.set_shader_parameter("margem", _margem)
	_medidas()


## As medidas da placa que valem para todos os pixels: calculadas aqui uma
## vez (e não pelo shader em cada pixel — bem mais leve na TV Box).
func _medidas() -> void:
	var meio := size * 0.5
	var r := minf(_raio, minf(size.x, size.y) * 0.5)
	var base_f := maxf(size.y - _borda - _espessura, _borda + 2.0 * r)
	var meio_f := Vector2(meio.x - _borda, (base_f - _borda) * 0.5)
	var alt_f := base_f - _borda
	mat.set_shader_parameter("meio", meio)
	mat.set_shader_parameter("r", r)
	mat.set_shader_parameter("base_f", base_f)
	mat.set_shader_parameter("centro_f", Vector2(meio.x, (_borda + base_f) * 0.5))
	mat.set_shader_parameter("meio_f", meio_f)
	mat.set_shader_parameter("r_f", maxf(r - _borda, 1.0))
	mat.set_shader_parameter("div_lado", maxf(_espessura + _borda, 1.0))
	mat.set_shader_parameter("div_frente", maxf(base_f - _borda, 1.0))
	mat.set_shader_parameter("centro_v", Vector2(meio.x, _borda + alt_f * 0.26))
	mat.set_shader_parameter("verniz_m", Vector4(meio_f.x - r * 0.3 - _borda, alt_f * 0.19, maxf(r * 0.75, 2.0),
		clampf(alt_f * 0.04, 1.5, 8.0)))
	mat.set_shader_parameter("sombra_g", Vector4(meio.x, meio.y + _margem * 0.35, -_margem * 0.2, _margem * 0.85))
	mat.set_shader_parameter("sombra_m", meio - Vector2(_margem, _margem) * 0.1)
	mat.set_shader_parameter("filete_g", Vector2(_borda * 0.35 + 1.0, maxf(_borda * 0.5, 1.5)))
