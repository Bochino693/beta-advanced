class_name Classificacao
extends RefCounted

## CLASSIFICAÇÃO DO DIA: os melhores de hoje, cada um com a SUA FOTO (a da
## câmera da máquina; sem câmera, o mascote com que jogou). Aparece no fim
## da partida ("você ficou em 2º lugar hoje!") e na tela de atração.
## Vira a cada dia; o operador zera junto com os recordes.
##
## Fica em user://classificacao.json; as fotos em user://fotos/rank_*.png.

const ARQUIVO := "user://classificacao.json"
const MAXIMO := 10

static var _cache := {}


static func hoje() -> String:
	return Time.get_date_string_from_system()


static func _ler() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var d := {}
	if FileAccess.file_exists(ARQUIVO):
		var j = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))
		if j is Dictionary:
			d = j
	if str(d.get("dia", "")) != hoje():
		_apagar_fotos(d.get("lista", []))
		d = {"dia": hoje(), "lista": []}
	_cache = d
	return d


## Grava numa linha de trabalho separada (no fim da partida, gravar na
## hora dava um tranco na TV Box), sempre na ordem certa.
static var _versao := 0
static var _gravada := 0
static var _trava := Mutex.new()


static func _gravar(d: Dictionary) -> void:
	_cache = d
	_versao += 1
	var v := _versao
	var texto := JSON.stringify(d, " ")
	Tarefas.rodar(func():
		_trava.lock()
		if v > _gravada:
			var f := FileAccess.open(ARQUIVO, FileAccess.WRITE)
			if f:
				f.store_string(texto)
				f.close()
				_gravada = v
		_trava.unlock())


static func _apagar_fotos(lista: Array) -> void:
	for e in lista:
		var c := str((e as Dictionary).get("foto", ""))
		if c != "" and FileAccess.file_exists(c):
			DirAccess.remove_absolute(c)


## Os de hoje, do melhor para o pior: [{pontos, personagem, foto, hora}].
static func lista() -> Array:
	return (_ler()["lista"] as Array).duplicate(true)


## Registra os jogadores da partida. entradas: [{pontos, personagem,
## chave_foto}]. Volta a posição de cada um no dia (1 = primeiro).
static func registrar(entradas: Array) -> Array[int]:
	var d := _ler()
	var todos: Array = d["lista"]
	var hora := Time.get_time_string_from_system().substr(0, 5)
	var novos := []
	for i in entradas.size():
		var e: Dictionary = entradas[i]
		var id := "%d_%d" % [int(Time.get_unix_time_from_system()), i]
		var r := {"pontos": int(e["pontos"]), "personagem": str(e["personagem"]), "foto": "", "hora": hora, "id": id,
			"chave_foto": str(e.get("chave_foto", ""))}
		novos.append(r)
		todos.append(r)
	# maior pontuação primeiro; empate: quem fez antes fica na frente
	var ordem := todos.duplicate()
	ordem.sort_custom(func(a, b):
		if int(a["pontos"]) != int(b["pontos"]):
			return int(a["pontos"]) > int(b["pontos"])
		return todos.find(a) < todos.find(b))
	var posicoes: Array[int] = []
	for r in novos:
		posicoes.append(ordem.find(r) + 1)
	var fica := ordem.slice(0, MAXIMO)
	_apagar_fotos(ordem.slice(MAXIMO))
	for r in novos:
		if fica.has(r) and str(r["chave_foto"]) != "":
			r["foto"] = Fotos.gravar(str(r["chave_foto"]), "rank_%s.png" % r["id"])
		r.erase("chave_foto")
	d["lista"] = fica
	_gravar(d)
	return posicoes


static func zerar() -> void:
	var d := _ler()
	_apagar_fotos(d["lista"])
	_gravar({"dia": hoje(), "lista": []})
