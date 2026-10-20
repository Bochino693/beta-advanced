class_name Pinos
extends Node3D

## OS 10 PINOS: montagem no triângulo, contagem dos caídos, carinhas e
## gravação para o replay. Quem varre e recoloca é a Maquina (maquina.gd).
## A queda é 100% física (Jolt): um pino derruba o outro, batem nas
## paredes e voltam, caem no fosso.
##
## Numeração oficial (vista de quem joga):
##          7   8   9   10
##            4   5   6
##              2   3
##                1

signal batida(posicao: Vector3, forca: float)
signal som_pousar

var pinos: Array[Pino] = []
## sombrinhas pintadas no chão embaixo de cada pino (deitam junto com ele).
## Uma MultiMesh só para os 10 pinos = um desenho.
var _sombras: MultiMeshInstance3D


static func posicao_do_pino(n: int) -> Vector3:
	var fileira := 0
	var primeiro := 1
	while n >= primeiro + fileira + 1:
		primeiro += fileira + 1
		fileira += 1
	var k := n - primeiro
	var x := (float(k) - float(fileira) * 0.5) * Mundo.ESPACO_PINOS
	return Vector3(x, 0.0, Mundo.Z_PINO1 - fileira * Mundo.FILEIRA)


func montar() -> void:
	var malha: Mesh = load("res://modelos/pino.res")
	var forma: Shape3D = load("res://modelos/pino_colisao.res")
	var rosto := Materiais.textura("rosto_pino")
	var meta: Dictionary = malha.get_meta("rosto", {})
	for n in range(1, 11):
		var p := Pino.new()
		add_child(p)
		p.montar(n, posicao_do_pino(n), malha, forma, rosto, meta)
		p.bateu.connect(func(pino: Pino, f: float): batida.emit(pino.global_position, f))
		pinos.append(p)
	var q := QuadMesh.new()
	q.size = Vector2(0.28, 0.28)
	q.orientation = PlaneMesh.FACE_Y
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = pinos.size()
	_sombras = MultiMeshInstance3D.new()
	_sombras.multimesh = mm
	_sombras.material_override = Materiais.sombra_blob(0.5)
	_sombras.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sombras)


func _process(_d: float) -> void:
	var mm := _sombras.multimesh
	for i in pinos.size():
		var p := pinos[i]
		# onde o pino APARECE neste quadro (interpolado entre passos da física)
		var tp := Mundo.na_tela(p)
		var g := tp.origin
		# pino levantado pela máquina ou longe do chão: a sombra some
		var f := 0.0 if p.removido or not p.visible or g.y < -0.1 else clampf(1.0 - g.y * 2.2, 0.0, 1.0)
		# deitado: a sombra fica comprida no sentido do pino
		var eixo := tp.basis.y.normalized()
		var deitado := 1.0 - absf(eixo.y)
		var b := Basis().scaled(Vector3(f * (1.0 + deitado * 0.2), 1.0, f * (1.0 + deitado * 1.6)))
		var giro := atan2(eixo.x, eixo.z)
		b = Basis(Vector3.UP, giro) * b
		var chao := 0.004 if absf(g.x) < Mundo.MEIA_LARGURA and g.z > Mundo.Z_FIM_DECK else -0.2
		if chao < 0.0:
			# fora da pista não tem sombra (nem aparece no alçapão aberto)
			b = Basis().scaled(Vector3.ZERO)
		# perto da borda a sombra encolhe: o adesivo reto não sai da pista
		# (nem fica boiando por cima da canaleta)
		if chao > 0.0:
			f *= clampf((Mundo.MEIA_LARGURA - absf(g.x)) / 0.16, 0.0, 1.0)
			b = Basis(Vector3.UP, giro) * Basis().scaled(Vector3(maxf(f * (1.0 + deitado * 0.2), 0.001), 1.0, maxf(f * (1.0 + deitado * 1.6), 0.001)))
		var centro := g + Vector3(eixo.x, 0, eixo.z) * 0.19 * deitado
		mm.set_instance_transform(i, Transform3D(b, Vector3(centro.x, chao, centro.z)))


func em_pe() -> Array[int]:
	var r: Array[int] = []
	for p in pinos:
		if not p.removido and not p.esta_caido():
			r.append(p.numero)
	return r


func caidos_desde(antes: Array[int]) -> Array[int]:
	var r: Array[int] = []
	var agora := em_pe()
	for n in antes:
		if not agora.has(n):
			r.append(n)
	return r


func pino(n: int) -> Pino:
	return pinos[n - 1]


## Antes da bola chegar: libera a física dos pinos em pé.
func soltar_todos() -> void:
	for p in pinos:
		if not p.removido:
			p.soltar()


## Carinha de medo quando a bola se aproxima.
func susto(bola_pos: Vector3) -> void:
	for p in pinos:
		if p.removido or p.esta_caido():
			continue
		var d := p.global_position.distance_to(bola_pos)
		if d < 3.2 and p._expr == "normal":
			p.expressao("medo")


## Replay: os pinos voltam a ter cara normal (sem estrelinhas) para
## "reviver" a jogada.
func reviver() -> void:
	for p in pinos:
		if not p.removido:
			p.expressao("normal")
			p._estrelas.visible = false


func todos_parados() -> bool:
	for p in pinos:
		if p.removido or p.freeze:
			continue
		if p.linear_velocity.length() > 0.06 or p.angular_velocity.length() > 0.25:
			return false
	return true


## Depois da jogada: os caídos ficam tontos (estrelinhas) ou bravinhos; os
## que ficaram de pé comemoram — quanto mais sobraram, mais festa, e alguns
## dão pulinhos. Devolve quantos vão pular (para a câmera esperar a festa).
func reagir() -> int:
	var de_pe: Array[Pino] = []
	for p in pinos:
		if p.removido:
			continue
		if p.esta_caido():
			if randf() < 0.55:
				p.ficar_tonto()
			else:
				p.ficar_bravo()
		else:
			de_pe.append(p)
	var chance := clampf(0.3 + de_pe.size() * 0.06, 0.35, 0.85)
	de_pe.shuffle()
	var pulando := 0
	for i in de_pe.size():
		var pulos := 0
		if randf() < chance:
			pulos = 1 + int(randf() < 0.45)
			pulando += 1
		de_pe[i].comemorar(0.1 + i * 0.07, pulos)
	return pulando


func prender_todos() -> void:
	for p in pinos:
		p.parar_pulo()
		p.prender()


## Interpolação da física dos pinos (o replay desliga: ele mesmo os move).
func interpolar(sim: bool) -> void:
	for p in pinos:
		p.interpolar(sim)


## Rack completo no lugar, sem animação.
func repor_todos(_animar := false) -> void:
	for p in pinos:
		p.recolocar()


# ---------------------------------------------------------------- replay
func foto() -> Array:
	var r := []
	for p in pinos:
		r.append(p.global_transform)
	return r


func aplicar_foto(f: Array) -> void:
	for i in pinos.size():
		if not pinos[i].removido:
			pinos[i].global_transform = f[i]
