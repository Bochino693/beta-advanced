class_name Lote
extends RefCounted

## JUNTAR AS PEÇAS PARADAS: dezenas de malhas com o MESMO material viram uma
## malha só — uma chamada de desenho no lugar de dezenas (e o mesmo para o
## contorno e a sombra). É o que mais pesa numa TV Box: o número de
## "desenhos" por quadro, não os triângulos.
##
## Só junta MeshInstance3D paradas; o que se mexe, acende ou some (balões,
## rodas, pódios, para-choques...) vai em `fora` e fica como está.


## Junta as malhas paradas debaixo de `raiz` (menos as de `fora` e os filhos
## delas), por material e por REGIÃO (quadrados de `celula` metros): poucos
## desenhos e a câmera ainda deixa de desenhar o que está fora do quadro.
## Devolve quantas peças sumiram.
static func juntar(raiz: Node3D, fora: Array = [], celula := 10.0) -> int:
	var excluir := {}
	for n in fora:
		if n != null:
			excluir[n] = true
	var pecas: Array[MeshInstance3D] = []
	_coletar(raiz, excluir, pecas)
	var grupos := {}
	for mi in pecas:
		var c := mi.global_transform.origin
		var regiao := Vector2i(floori(c.x / celula), floori(c.z / celula)) if celula > 0.0 else Vector2i.ZERO
		var chave := "%d|%d|%d|%s" % [mi.material_override.get_instance_id(), mi.cast_shadow, int(_tem_cor(mi.mesh)), regiao]
		if not grupos.has(chave):
			grupos[chave] = []
		grupos[chave].append(mi)
	var inv := raiz.global_transform.affine_inverse()
	var sumiram := 0
	for chave in grupos:
		var lista: Array = grupos[chave]
		if lista.size() < 2:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var escalado := false
		for mi in lista:
			var xf: Transform3D = inv * (mi as MeshInstance3D).global_transform
			if not is_equal_approx(xf.basis.get_scale().x, 1.0):
				escalado = true
			st.append_from((mi as MeshInstance3D).mesh, 0, xf)
		var arrays := st.commit_to_arrays()
		if escalado:
			# a escala entra na normal: devolve o comprimento 1 (contorno certo)
			var nn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in nn.size():
				nn[i] = nn[i].normalized()
			arrays[Mesh.ARRAY_NORMAL] = nn
		var malha := ArrayMesh.new()
		malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var novo := MeshInstance3D.new()
		novo.name = "lote"
		novo.mesh = malha
		novo.material_override = (lista[0] as MeshInstance3D).material_override
		novo.cast_shadow = (lista[0] as MeshInstance3D).cast_shadow
		raiz.add_child(novo)
		for mi in lista:
			(mi as Node).get_parent().remove_child(mi)
			(mi as Node).free()
			sumiram += 1
		sumiram -= 1
	return sumiram


static func _coletar(no: Node, excluir: Dictionary, saida: Array[MeshInstance3D]) -> void:
	for f in no.get_children():
		if excluir.has(f):
			continue
		if f is MeshInstance3D:
			var mi := f as MeshInstance3D
			if mi.mesh != null and mi.material_override != null and mi.mesh.get_surface_count() == 1 \
					and _triangulos(mi.mesh) and mi.get_child_count() == 0 and mi.visible:
				saida.append(mi)
				continue
		if f is Node3D and (f as Node3D).visible:
			_coletar(f, excluir, saida)


static func _tem_cor(m: Mesh) -> bool:
	if m is ArrayMesh:
		return (m as ArrayMesh).surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR != 0
	return m.surface_get_arrays(0)[Mesh.ARRAY_COLOR] != null


static func _triangulos(m: Mesh) -> bool:
	if m is ArrayMesh:
		return (m as ArrayMesh).surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES
	return m is PrimitiveMesh
