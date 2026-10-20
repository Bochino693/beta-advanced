class_name Perfis
extends RefCounted

## PEÇAS POR PERFIL (extrusão): um contorno 2D (x, y) puxado ao longo de Z
## vira uma peça lisa, com quinas arredondadas e normais suaves — canaleta
## em "U", divisória, paredes da caçapa, gabinete da máquina. Muitos
## segmentos nas curvas: nada de "facetas" mesmo de perto em 4K.
##
## O contorno é FECHADO e no sentido anti-horário (visto de +Z).


## Retângulo de cantos arredondados centrado em `centro`.
static func retangulo(largura: float, altura: float, raio: float, centro := Vector2.ZERO, segs := 10) -> PackedVector2Array:
	var r := minf(raio, minf(largura, altura) * 0.5)
	var hw := largura * 0.5 - r
	var hh := altura * 0.5 - r
	var p := PackedVector2Array()
	var cantos := [Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh), Vector2(-hw, -hh)]
	for k in 4:
		var a0 := -PI * 0.5 + k * PI * 0.5
		for i in segs + 1:
			var a := a0 + PI * 0.5 * float(i) / float(segs)
			p.append(centro + cantos[k] + Vector2(cos(a), sin(a)) * r)
	return p


## Canaleta em meia-cana: calha de raio `r` cujos lábios arredondados ficam
## no nível da pista (y = 0); paredes retas por fora e fundo reto embaixo.
static func canaleta(r: float, borda := 0.018, fundo := 0.05, segs := 56) -> PackedVector2Array:
	var p := PackedVector2Array()
	var yc := -borda                 # centro da calha e dos lábios
	var xe := r + 2.0 * borda
	p.append(Vector2(xe, yc - r - fundo))
	# lábio direito: de fora (ângulo 0) por cima até dentro (ângulo PI)
	for i in 17:
		var a := PI * float(i) / 16.0
		p.append(Vector2(r + borda + cos(a) * borda, yc + sin(a) * borda))
	# a calha, descendo pela direita, passando pelo fundo e subindo
	for i in range(1, segs):
		var a := -PI * float(i) / float(segs)
		p.append(Vector2(cos(a) * r, yc + sin(a) * r))
	# lábio esquerdo: de dentro (ângulo 0) por cima até fora (ângulo PI)
	for i in 17:
		var a := PI * float(i) / 16.0
		p.append(Vector2(-r - borda + cos(a) * borda, yc + sin(a) * borda))
	p.append(Vector2(-xe, yc - r - fundo))
	return p


## Puxa o contorno de z0 até z1 (z0 < z1). Normais suaves nas curvas; quina
## viva onde o ângulo passa de `quina` graus. Tampas nas pontas.
## sombreado (opcional): Vector4(y_baixo, y_alto, brilho_baixo, brilho_alto)
## vira cor do vértice — a calha fica mais escura no fundo (dá profundidade).
static func extrudar(perfil: PackedVector2Array, z0: float, z1: float, tampa0 := true, tampa1 := true, quina := 50.0,
		sombreado := Vector4.ZERO) -> ArrayMesh:
	var n := perfil.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var usa_cor := sombreado != Vector4.ZERO
	var cor := func(y: float) -> Color:
		var t := clampf((y - sombreado.x) / maxf(sombreado.y - sombreado.x, 1e-4), 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		var v := lerpf(sombreado.z, sombreado.w, t)
		return Color(v, v, v, 0.0)
	# normal de cada aresta (para fora, contorno anti-horário)
	var na := PackedVector2Array()
	for i in n:
		var d := perfil[(i + 1) % n] - perfil[i]
		na.append(Vector2(d.y, -d.x).normalized())
	var limite := cos(deg_to_rad(quina))
	for i in n:
		var j := (i + 1) % n
		var a := perfil[i]
		var b := perfil[j]
		# normal em a: média com a aresta anterior se a curva for suave
		var ant := na[(i - 1 + n) % n]
		var prox := na[(j) % n]
		var n_a := na[i] if na[i].dot(ant) < limite else (na[i] + ant).normalized()
		var n_b := na[i] if na[i].dot(prox) < limite else (na[i] + prox).normalized()
		var A := Vector3(a.x, a.y, z0)
		var B := Vector3(b.x, b.y, z0)
		var C := Vector3(b.x, b.y, z1)
		var D := Vector3(a.x, a.y, z1)
		var nA := Vector3(n_a.x, n_a.y, 0)
		var nB := Vector3(n_b.x, n_b.y, 0)
		var comp := z1 - z0
		# frente no sentido horário (o Godot): A, C, B e A, D, C
		for v in [[A, nA, Vector2(0, 0)], [C, nB, Vector2(1, comp)], [B, nB, Vector2(1, 0)],
				[A, nA, Vector2(0, 0)], [D, nA, Vector2(0, comp)], [C, nB, Vector2(1, comp)]]:
			st.set_normal(v[1])
			st.set_uv(v[2])
			if usa_cor:
				st.set_color(cor.call((v[0] as Vector3).y))
			st.add_vertex(v[0])
	if tampa0 or tampa1:
		var tri := Geometry2D.triangulate_polygon(perfil)
		for t in range(0, tri.size(), 3):
			var p0 := perfil[tri[t]]
			var p1 := perfil[tri[t + 1]]
			var p2 := perfil[tri[t + 2]]
			var anti := (p1 - p0).cross(p2 - p0) > 0.0
			if tampa1:
				# vista de +Z: precisa ficar horária
				var ordem := [p0, p2, p1] if anti else [p0, p1, p2]
				for q in ordem:
					st.set_normal(Vector3(0, 0, 1))
					st.set_uv(Vector2(q.x, q.y))
					if usa_cor:
						st.set_color(cor.call(q.y))
					st.add_vertex(Vector3(q.x, q.y, z1))
			if tampa0:
				var ordem0 := [p0, p1, p2] if anti else [p0, p2, p1]
				for q in ordem0:
					st.set_normal(Vector3(0, 0, -1))
					st.set_uv(Vector2(q.x, q.y))
					if usa_cor:
						st.set_color(cor.call(q.y))
					st.add_vertex(Vector3(q.x, q.y, z0))
	return st.commit()


## Cortina pregueada (plano XY com dobras em Z), com UV 0..1 para o
## shader de estrelas. Normais calculadas das dobras: a luz desenha as pregas.
static func cortina(largura: float, altura: float, dobras: int, fundura: float, colunas := 160) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := TAU * float(dobras) / largura
	var linhas := 2
	for i in colunas:
		for jj in linhas - 1:
			var quad := []
			for c in [[i, jj], [i + 1, jj], [i + 1, jj + 1], [i, jj + 1]]:
				var u := float(c[0]) / float(colunas)
				var v := float(c[1]) / float(linhas - 1)
				var x := (u - 0.5) * largura
				var z := sin(x * k) * fundura * 0.5
				var dz := cos(x * k) * fundura * 0.5 * k
				var nrm := Vector3(-dz, 0, 1).normalized()
				quad.append([Vector3(x, (v - 0.5) * altura, z), nrm, Vector2(u, 1.0 - v)])
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_normal(quad[idx][1])
				st.set_uv(quad[idx][2])
				st.add_vertex(quad[idx][0])
	return st.commit()
