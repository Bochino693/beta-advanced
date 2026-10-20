class_name Aquecer
extends SubViewport

## AQUECER OS SHADERS (evita os "engasgos").
##
## A placa de vídeo só prepara (compila) o desenho de um material na
## primeira vez em que ele aparece na tela — e isso trava o jogo por um
## instante: na troca de cenário, na primeira bola de fogo, no confete...
## Na TV Box são travadas bem visíveis.
##
## Aqui, durante a abertura (a marca cobre a tela), uma telinha escondida
## de 96x96 que enxerga o MESMO mundo 3D desenha uma amostra de cada
## material do jogo — inclusive os dos cenários que ainda não apareceram,
## partículas e lâmpadas (MultiMesh), com sombra e neblina — e também os
## materiais 2D da interface. Depois de alguns quadros ela some.

const ALTURA := 400.0      # lá no alto, longe de tudo que a câmera do jogo vê
const QUADROS := 8
## Imagens que só aparecem mais tarde (letreiros do resultado, cartões dos
## cenários, fim de jogo, a bola de cada bichinho): carregadas já aqui —
## ler e mandar para a placa de vídeo na primeira vez que aparecessem dava
## um tranco (na TV Box, bem visível).
const TEXTURAS := ["strike", "spare", "ops", "boa", "super", "uau", "quase", "pegando_fogo", "empate",
	"novo_recorde", "parabens", "venceu", "fim_de_jogo", "replay", "cen_dinos", "cen_parque", "cen_espaco",
	"cen_mar", "estrela", "estrela_placar", "estrela_vazia", "bola_bob", "bola_mia", "retrato_bob",
	"retrato_mia", "retrato_bob_empolgado", "retrato_mia_empolgado"]
## Shaders 2D que só aparecem mais tarde (a foto redonda das crianças).
const SHADERS_2D := ["res://shaders/foto_redonda.gdshader"]

var _quadros := 0


func preparar(vp: SubViewport, interface: Node, extras: Array = []) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	size = Vector2i(96, 96)
	world_3d = vp.find_world_3d()
	msaa_3d = vp.msaa_3d
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera3D.new()
	cam.position = Vector3(0, ALTURA, 6.0)
	cam.fov = 75.0
	cam.far = 40.0
	add_child(cam)
	cam.current = true
	var amostras := _amostras_3d(vp)
	# materiais que ainda não estão na cena (as partículas dos efeitos:
	# estrelas, confete, faíscas, fumaça) — desenhadas em MultiMesh
	for m in extras:
		if m is Material:
			amostras.append(_multi(_quad(), m, true, true))
	var lado := int(ceil(sqrt(float(amostras.size()))))
	for i in amostras.size():
		var no: GeometryInstance3D = amostras[i]
		var x := float(i % lado) - lado * 0.5
		var y := float(i / lado) - lado * 0.5
		no.position = Vector3(x * 0.6, ALTURA + y * 0.6, 0.0)
		add_child(no)
	cam.position.z = maxf(6.0, lado * 0.6)
	# materiais 2D (painéis, fotos redondas, brilho da marca...)
	var vistos := {}
	for c in interface.find_children("*", "CanvasItem", true, false):
		var m: Material = (c as CanvasItem).material
		if m != null and not vistos.has(m):
			vistos[m] = true
			var r := ColorRect.new()
			r.size = Vector2(8, 8)
			r.position = Vector2(vistos.size() % 12 * 8, vistos.size() / 12 * 8)
			r.material = m
			add_child(r)
	for caminho in SHADERS_2D:
		var sm := ShaderMaterial.new()
		sm.shader = load(caminho)
		var r := ColorRect.new()
		r.size = Vector2(8, 8)
		r.position = Vector2(88, 88)
		r.material = sm
		add_child(r)
	var n_tex := 0
	for nome in TEXTURAS:
		var t := Materiais.textura(nome)
		if t != null:
			n_tex += 1
			var tr := TextureRect.new()
			tr.texture = t
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.size = Vector2(4, 4)
			tr.position = Vector2(n_tex % 24 * 4, 92)
			add_child(tr)
	print("Aquecer: %d materiais 3D, %d 2D, %d imagens" % [amostras.size(), vistos.size(), n_tex])


func _process(_d: float) -> void:
	_quadros += 1
	if _quadros > QUADROS:
		queue_free()


## Uma amostra para cada combinação de material + tipo de desenho.
func _amostras_3d(vp: SubViewport) -> Array:
	var r := []
	var vistos := {}
	for no in vp.find_children("*", "GeometryInstance3D", true, false):
		if no is MeshInstance3D:
			var mi := no as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var m: Material = mi.get_active_material(s)
				if m == null or vistos.has([m, 0]):
					continue
				vistos[[m, 0]] = true
				var a := MeshInstance3D.new()
				a.mesh = mi.mesh if mi.mesh.get_surface_count() == 1 else _quad()
				a.material_override = m
				a.scale = Vector3.ONE * _escala(mi.mesh)
				r.append(a)
		elif no is MultiMeshInstance3D:
			var mmi := no as MultiMeshInstance3D
			var m: Material = mmi.material_override
			if mmi.multimesh == null or mmi.multimesh.mesh == null:
				continue
			if m == null:
				m = mmi.multimesh.mesh.surface_get_material(0)
			if m == null or vistos.has([m, 1]):
				continue
			vistos[[m, 1]] = true
			r.append(_multi(mmi.multimesh.mesh, m, mmi.multimesh.use_colors, mmi.multimesh.use_custom_data))
		elif no is CPUParticles3D:
			var p := no as CPUParticles3D
			if p.mesh == null:
				continue
			var m: Material = p.material_override if p.material_override else p.mesh.surface_get_material(0)
			if m == null or vistos.has([m, 2]):
				continue
			vistos[[m, 2]] = true
			r.append(_multi(p.mesh, m, true, true))
	return r


func _escala(m: Mesh) -> float:
	var t := m.get_aabb().get_longest_axis_size()
	return 0.5 / maxf(t, 0.01)


func _quad() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	return q


## As partículas (CPUParticles3D) e as lâmpadas são desenhadas em MultiMesh:
## é outro "jeito" de desenhar, que também precisa ser preparado.
func _multi(malha: Mesh, m: Material, cores: bool, extra: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = cores
	mm.use_custom_data = extra
	mm.mesh = malha
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis().scaled(Vector3.ONE * _escala(malha)), Vector3.ZERO))
	if cores:
		mm.set_instance_color(0, Color.WHITE)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	return mmi
