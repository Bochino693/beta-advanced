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
	mat.set_shader_parameter("raio", raio)
	mat.set_shader_parameter("espessura", espessura)
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
