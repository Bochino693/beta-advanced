extends SceneTree

## ASSADOR DE MODELOS
##
## Lê o que o tools/modelos/modelos.py gravou em tools/modelos/saida
## (.bin + .json) — de preferência a versão leve que o simplificar.py
## grava em saida/leve — e salva recursos nativos do Godot em res://modelos/:
##   * bob.scn / mia.scn  — personagem montado (juntas + malhas)
##   * roupas/<bob|mia>_<roupa>.scn — as roupinhas das fases (mesmas juntas;
##     o jogo só troca a malha de cada junta: Personagem.trocar_roupa)
##   * pino.res + pino_colisao.res
##   * cenario/<objeto>.res, terreno.res
## Cada malha ganha níveis de detalhe (LOD) automáticos: de longe o Godot
## desenha a versão leve, de perto a completa.
##
## Uso (na pasta do projeto):
##   python3 tools/modelos/modelos.py        (formas -> malhas finas)
##   python3 tools/modelos/simplificar.py    (malhas leves, bordas de cor nítidas)
##   godot --headless --path . --script res://tools/modelos/assar_modelos.gd

const ENTRADA := "res://tools/modelos/saida/"
const ENTRADA_LEVE := "res://tools/modelos/saida/leve/"
const SAIDA := "res://modelos/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAIDA + "cenario"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAIDA + "roupas"))
	var so := OS.get_cmdline_user_args()   # ex.: -- temas  (só esse pacote)
	for nome in ["bob", "mia"]:
		if not so.is_empty() and not so.has(nome):
			continue
		if FileAccess.file_exists(ENTRADA + nome + ".json"):
			_assar_personagem(nome)
	for nome in ["bob", "mia"]:
		for roupa in ["pirata", "dino", "astronauta", "parque"]:
			var pacote: String = nome + "_" + roupa
			if not so.is_empty() and not so.has(pacote) and not so.has("roupas"):
				continue
			if FileAccess.file_exists(ENTRADA + pacote + ".json"):
				_assar_personagem(pacote, SAIDA + "roupas/")
	for pac in ["pino", "cenario", "temas", "terreno"]:
		if not so.is_empty() and not so.has(pac):
			continue
		if not FileAccess.file_exists(ENTRADA + pac + ".json"):
			continue
		match pac:
			"pino":
				_assar_pino()
			"cenario", "temas":
				_assar_soltos(pac, SAIDA + "cenario/")
			"terreno":
				_assar_soltos(pac, SAIDA)
	quit()


func _ler(nome: String) -> Array:
	var pasta := ENTRADA_LEVE if FileAccess.file_exists(ENTRADA_LEVE + nome + ".json") else ENTRADA
	print(nome, " <- ", pasta)
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pasta + nome + ".json"))
	var blob := FileAccess.get_file_as_bytes(pasta + nome + ".bin")
	return [info, blob]


func _malha(parte: Dictionary, blob: PackedByteArray, lod := true) -> ArrayMesh:
	var fv: PackedFloat32Array = blob.slice(parte["v"][0], parte["v"][0] + parte["v"][1]).to_float32_array()
	var fn: PackedFloat32Array = blob.slice(parte["n"][0], parte["n"][0] + parte["n"][1]).to_float32_array()
	var fc: PackedFloat32Array = blob.slice(parte["c"][0], parte["c"][0] + parte["c"][1]).to_float32_array()
	var ii: PackedInt32Array = blob.slice(parte["i"][0], parte["i"][0] + parte["i"][1]).to_int32_array()
	var n := fv.size() / 3
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var c := PackedColorArray()
	v.resize(n)
	nn.resize(n)
	c.resize(n)
	for k in n:
		v[k] = Vector3(fv[k * 3], fv[k * 3 + 1], fv[k * 3 + 2])
		nn[k] = Vector3(fn[k * 3], fn[k * 3 + 1], fn[k * 3 + 2])
		c[k] = Color(fc[k * 4], fc[k * 4 + 1], fc[k * 4 + 2], fc[k * 4 + 3])
	# O Godot desenha a face da frente no sentido HORÁRIO; o modelador grava
	# no anti-horário: inverte cada triângulo.
	var idx := PackedInt32Array()
	idx.resize(ii.size())
	for t in ii.size() / 3:
		idx[t * 3] = ii[t * 3]
		idx[t * 3 + 1] = ii[t * 3 + 2]
		idx[t * 3 + 2] = ii[t * 3 + 1]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nn
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = idx
	if not lod:
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return am
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


func _assar_personagem(nome: String, pasta := SAIDA) -> void:
	var dados := _ler(nome)
	var info: Dictionary = dados[0]
	var blob: PackedByteArray = dados[1]
	var raiz := Node3D.new()
	raiz.name = nome.capitalize()
	var nos := {}
	for parte in info["partes"]:
		var junta := Node3D.new()
		junta.name = parte["nome"]
		var p: Array = parte["pivo"]
		junta.position = Vector3(p[0], p[1], p[2])
		var pai: Node = raiz if parte["pai"] == "" else nos[parte["pai"]]
		pai.add_child(junta)
		junta.owner = raiz
		var mi := MeshInstance3D.new()
		mi.name = "malha"
		mi.mesh = _malha(parte, blob)
		junta.add_child(mi)
		mi.owner = raiz
		nos[parte["nome"]] = junta
	for k in info:
		if k != "partes":
			raiz.set_meta(k, info[k])
	var cena := PackedScene.new()
	cena.pack(raiz)
	var r := ResourceSaver.save(cena, pasta + nome + ".scn", ResourceSaver.FLAG_COMPRESS)
	print("personagem ", nome, " -> ", r)
	raiz.free()


func _assar_pino() -> void:
	var dados := _ler("pino")
	var info: Dictionary = dados[0]
	var blob: PackedByteArray = dados[1]
	var m := _malha(info["partes"][0], blob)
	m.set_meta("rosto", info["rosto"])
	print("pino -> ", ResourceSaver.save(m, SAIDA + "pino.res", ResourceSaver.FLAG_COMPRESS))
	var pontos := PackedVector3Array()
	for q in info["casco"]:
		pontos.append(Vector3(q[0], q[1], q[2]))
	var forma := ConvexPolygonShape3D.new()
	forma.points = pontos
	print("pino colisao -> ", ResourceSaver.save(forma, SAIDA + "pino_colisao.res"))


func _assar_soltos(arquivo: String, pasta: String) -> void:
	var dados := _ler(arquivo)
	var info: Dictionary = dados[0]
	var blob: PackedByteArray = dados[1]
	for parte in info["partes"]:
		var m := _malha(parte, blob, not str(parte["nome"]).begins_with("terreno"))
		var r := ResourceSaver.save(m, pasta + parte["nome"] + ".res", ResourceSaver.FLAG_COMPRESS)
		print(arquivo, "/", parte["nome"], " -> ", r)
