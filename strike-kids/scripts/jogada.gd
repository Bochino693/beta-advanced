class_name Jogada
extends RefCounted

## O PLANEJADOR DA JOGADA — ele só escolhe a LINHA da bola. Quem derruba os
## pinos é a física de verdade (Jolt): a bola bate, os pinos voam, batem uns
## nos outros, nas paredes, e caem. Nenhum pino é empurrado "de mentira".
##
## A mira é sempre o STRIKE (o "bolso" entre os pinos 1 e 3, ou 1 e 2). O
## sensor diz POR ONDE a bola passou (5 posições): no centro é mais fácil
## acertar o bolso; nas pontas a bola chega torta. A dificuldade escolhida
## pelo operador define o quanto a bola "erra" o bolso.
##
## Para o resultado ser justo e ajustável, as linhas vêm de uma tabela de
## jogadas simuladas com a mesma física (tools/testes/calibrar.gd ->
## dados/tabela_jogadas.json): o jogo sorteia quão boa foi a jogada e pega
## uma linha que, na simulação, rendeu aquilo. Na hora, a física pode dar um
## pino a mais ou a menos — como no boliche de verdade.
##
##   Z = esquerda   X = meio-esquerda   C = CENTRO   V = meio-direita   B = direita

const LINHA := {"Z": -0.43, "X": -0.21, "C": 0.0, "V": 0.21, "B": 0.43}
const ARQUIVO := "res://dados/tabela_jogadas.json"

## Chance (%) de cada resultado na 1ª bola, por posição e dificuldade.
## Chave = pinos derrubados.
const TABELA := {
	"facil": {
		"C": {10: 60, 9: 14, 8: 10, 7: 8, 6: 5, 5: 3},
		"X": {10: 34, 9: 17, 8: 15, 7: 13, 6: 10, 5: 7, 4: 4},
		"Z": {10: 14, 9: 12, 8: 14, 7: 15, 6: 14, 5: 12, 4: 10, 3: 6, 2: 3},
	},
	"normal": {
		"C": {10: 42, 9: 18, 8: 14, 7: 11, 6: 8, 5: 5, 4: 2},
		"X": {10: 22, 9: 16, 8: 16, 7: 15, 6: 12, 5: 10, 4: 6, 3: 3},
		"Z": {10: 7, 9: 9, 8: 12, 7: 14, 6: 15, 5: 14, 4: 12, 3: 9, 2: 6, 1: 2},
	},
	"dificil": {
		"C": {10: 28, 9: 18, 8: 16, 7: 14, 6: 10, 5: 8, 4: 6},
		"X": {10: 12, 9: 13, 8: 15, 7: 16, 6: 15, 5: 12, 4: 9, 3: 8},
		"Z": {10: 4, 9: 6, 8: 9, 7: 12, 6: 14, 5: 15, 4: 14, 3: 12, 2: 9, 1: 5},
	},
}

## Chance (%) da bola acertar em cheio o que sobrou (spare), conforme a
## linha do sensor passa perto do grupo de pinos.
const SPARE := {"facil": [72, 45, 20], "normal": [58, 32, 12], "dificil": [42, 22, 7]}

## Sem para-choques: chance (%) de canaleta na 1ª bola, por posição.
const CANALETA := {"C": 0, "X": 4, "Z": 12}

var zona := "C"
var origem_x := 0.0         # por onde a bola passa na linha de falta (z = 0,35)
var alvo_x := 0.0           # para onde ela vai (na altura do pino 1)
var velocidade := 7.9
var efeito := 0.0           # gancho (força lateral)
var esperado := -1          # quantos pinos a simulação derrubou com essa linha
var canaleta := false

## Só para testes e para gravar o vídeo de divulgação: resultados desejados
## em sequência (quantos pinos caem). Vazio = sorteio normal.
static var forcar: Array = []

static var _grupos := {}    # zona -> [{xt, v, e, resultados: [n...], entrada}]


var strike_provavel: bool:
	get:
		return esperado == 10


static func planejar(z: String, em_pe: Array, primeira_bola: bool, dificuldade: String, protecao: bool) -> Jogada:
	var j := Jogada.new()
	j.zona = z
	var linha: float = LINHA.get(z, 0.0)
	var grupo := "C" if z == "C" else ("X" if z in ["X", "V"] else "Z")
	var dif: String = dificuldade if TABELA.has(dificuldade) else "facil"
	var desejado := -1
	if not forcar.is_empty():
		desejado = clampi(int(forcar.pop_front()), 0, em_pe.size())
	if primeira_bola and em_pe.size() == 10:
		if desejado < 0:
			desejado = _sortear(TABELA[dif][grupo])
			if not protecao and randi() % 100 < int(CANALETA[grupo]):
				desejado = 0
		if desejado == 0 and not protecao:
			_canaleta(j, linha)
			return j
		if _da_tabela(j, z, desejado, protecao):
			return j
	_resto(j, linha, em_pe, dif, desejado, protecao)
	return j


static func _sortear(tabela: Dictionary) -> int:
	var total := 0
	for k in tabela:
		total += int(tabela[k])
	var r: int = randi() % maxi(total, 1)
	for k in tabela:
		r -= int(tabela[k])
		if r < 0:
			return int(k)
	return 0


static func _canaleta(j: Jogada, linha: float) -> void:
	var lado: float = signf(linha) if linha != 0.0 else (1.0 if randf() < 0.5 else -1.0)
	j.canaleta = true
	j.esperado = 0
	j.origem_x = clampf(linha + lado * 0.08, -0.5, 0.5)
	j.alvo_x = lado * 0.95
	j.velocidade = randf_range(6.8, 7.4)


# ---------------------------------------------------------------- 1ª bola
static func _carregar() -> void:
	if not _grupos.is_empty():
		return
	if not FileAccess.file_exists(ARQUIVO):
		push_warning("Jogada: sem tabela de calibração (%s)" % ARQUIVO)
		return
	var dados = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))
	if typeof(dados) != TYPE_DICTIONARY:
		return
	var idx := {}
	for r in dados.get("jogadas", []):
		# [zona, x0, xt, v, efeito, n, caidos, x_entrada]
		var chave := _chave(str(r[0]), float(r[2]), float(r[3]), float(r[4]))
		if not idx.has(chave):
			idx[chave] = {"zona": str(r[0]), "xt": float(r[2]), "v": float(r[3]), "e": float(r[4]),
				"resultados": [], "entrada": float(r[7]) if r.size() > 7 else float(r[2])}
			if not _grupos.has(str(r[0])):
				_grupos[str(r[0])] = []
			_grupos[str(r[0])].append(idx[chave])
		idx[chave]["resultados"].append(int(r[5]))
	# a física é caótica: um tiquinho de diferença muda o resultado. Por isso
	# cada linha olha também as vizinhas (2 cm para cada lado): só conta como
	# "linha de strike" a que derruba tudo mesmo errando um pouquinho.
	for chave in idx:
		var g: Dictionary = idx[chave]
		var amostra: Array = g["resultados"].duplicate()
		for dx in [-0.02, 0.02]:
			var viz := _chave(g["zona"], float(g["xt"]) + dx, g["v"], g["e"])
			if idx.has(viz):
				amostra.append_array(idx[viz]["resultados"])
		g["amostra"] = amostra


static func _chave(z: String, xt: float, v: float, e: float) -> String:
	return "%s|%.2f|%.1f|%.2f" % [z, snappedf(xt, 0.01), v, e]


## Pega na tabela uma linha da zona que costuma render `n` pinos (a mais
## "garantida", contando as vizinhas).
static func _da_tabela(j: Jogada, z: String, n: int, protecao: bool) -> bool:
	_carregar()
	var lista: Array = _grupos.get(z, [])
	if lista.is_empty():
		return false
	var melhor := -1.0
	var opcoes := []
	for g in lista:
		if not protecao and (absf(float(g["entrada"])) > 0.5 or absf(float(g["xt"])) > 0.5):
			continue  # essa linha encostava no para-choque
		var amostra: Array = g["amostra"]
		var nota := 0.0
		for r in amostra:
			var dif := absi(int(r) - n)
			nota += 1.0 if dif == 0 else (0.35 if dif == 1 else 0.0)
		nota /= float(amostra.size())
		if nota > melhor + 0.001:
			melhor = nota
			opcoes = [g]
		elif absf(nota - melhor) <= 0.001:
			opcoes.append(g)
	if opcoes.is_empty():
		return false
	var g: Dictionary = opcoes[randi() % opcoes.size()]
	j.origem_x = LINHA[z]
	j.alvo_x = g["xt"]
	j.velocidade = g["v"]
	j.efeito = g["e"]
	j.esperado = n
	return true


static func _media(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return s / maxf(a.size(), 1.0)


# ---------------------------------------------------------------- bolas seguintes
## Mira no que sobrou: o pino da frente do grupo, batendo do lado que joga
## ele em cima dos outros. Errou a mira? A bola passa raspando ou de lado.
static func _resto(j: Jogada, linha: float, em_pe: Array, dif: String, desejado: int, protecao: bool) -> void:
	j.origem_x = clampf(linha, -0.45, 0.45)
	j.velocidade = randf_range(8.0, 8.8)
	j.efeito = 0.0
	if em_pe.is_empty():
		j.alvo_x = 0.0
		return
	# centro do grupo e o pino "chave" (o mais da frente; empate: o mais central)
	var cx := 0.0
	var chave: int = em_pe[0]
	var xmin := 9.0
	var xmax := -9.0
	for n in em_pe:
		var p := Pinos.posicao_do_pino(n)
		cx += p.x
		xmin = minf(xmin, p.x)
		xmax = maxf(xmax, p.x)
		var pc := Pinos.posicao_do_pino(chave)
		if p.z > pc.z + 0.01 or (absf(p.z - pc.z) < 0.01 and absf(p.x) < absf(pc.x)):
			chave = n
	cx /= float(em_pe.size())
	var pk := Pinos.posicao_do_pino(chave)
	var lado := signf(cx - pk.x)
	var mira := pk.x - lado * 0.07 if absf(cx - pk.x) > 0.03 else pk.x + randf_range(-0.03, 0.03)
	var dist := 0.0
	if linha < xmin:
		dist = xmin - linha
	elif linha > xmax:
		dist = linha - xmax
	var chances: Array = SPARE[dif]
	var chance: int = chances[0] if dist < 0.12 else (chances[1] if dist < 0.32 else chances[2])
	var acertou := randi() % 100 < chance
	if desejado >= 0:
		acertou = desejado >= em_pe.size()
	if acertou:
		j.alvo_x = mira + randf_range(-0.015, 0.015)
		j.esperado = em_pe.size()
	else:
		# erra para o lado de fora do grupo (raspando ou passando direto)
		var fora := signf(mira) if mira != 0.0 else (1.0 if randf() < 0.5 else -1.0)
		var erro := randf_range(0.1, 0.32)
		if desejado == 0:
			erro = 0.45
		j.alvo_x = mira + fora * erro
		j.esperado = -1
	j.alvo_x = clampf(j.alvo_x, -0.58 if protecao else -0.62, 0.58 if protecao else 0.62)
