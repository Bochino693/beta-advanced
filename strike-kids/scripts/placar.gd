class_name Placar
extends RefCounted

## PONTUAÇÃO.
## Cada pino = 10 pontos. STRIKE (10 na 1ª bola) = +50. SPARE (completou os
## 10 depois) = +20. Números grandes: criança adora ver o placar subir!

const PONTOS_PINO := 10
const BONUS_STRIKE := 50
const BONUS_SPARE := 20

var jogadores := []   # [{nome, personagem, rodadas: [[bolas...]...], pontos, strikes, spares}]
var rodadas := 3
var tentativas := 3
var jogador_atual := 0
var rodada_atual := 0       # 0..rodadas-1
var bola_atual := 0         # 0..tentativas-1
var pinos_na_rodada := 0


func comecar(personagens: Array, n_rodadas: int, n_tentativas: int) -> void:
	jogadores.clear()
	for p in personagens:
		jogadores.append({"personagem": p, "rodadas": [], "pontos": 0, "strikes": 0, "spares": 0, "pinos": 0, "seguidos": 0})
	rodadas = n_rodadas
	tentativas = n_tentativas
	jogador_atual = 0
	rodada_atual = 0
	bola_atual = 0
	pinos_na_rodada = 0
	for j in jogadores:
		for r in rodadas:
			j["rodadas"].append([])


func atual() -> Dictionary:
	return jogadores[jogador_atual]


## Registra uma bola. Retorna {tipo: "strike"|"spare"|"normal"|"zero", pontos, fim_rodada}.
func registrar(derrubados: int) -> Dictionary:
	var j: Dictionary = atual()
	var bolas: Array = j["rodadas"][rodada_atual]
	bolas.append(derrubados)
	pinos_na_rodada += derrubados
	var tipo := "normal"
	var pontos := derrubados * PONTOS_PINO
	if derrubados == 0:
		tipo = "zero"
	if pinos_na_rodada >= 10:
		if bola_atual == 0:
			tipo = "strike"
			pontos += BONUS_STRIKE
			j["strikes"] += 1
		else:
			tipo = "spare"
			pontos += BONUS_SPARE
			j["spares"] += 1
	j["pontos"] += pontos
	j["pinos"] += derrubados
	var fim := pinos_na_rodada >= 10 or bola_atual + 1 >= tentativas
	# strikes seguidos (rodada sem strike zera a sequência)
	if tipo == "strike":
		j["seguidos"] += 1
	elif fim:
		j["seguidos"] = 0
	return {"tipo": tipo, "pontos": pontos, "fim_rodada": fim}


## Passa para a próxima bola / rodada / jogador. Retorna "bola", "rodada" ou "fim".
func avancar(fim_rodada: bool) -> String:
	if not fim_rodada:
		bola_atual += 1
		return "bola"
	bola_atual = 0
	pinos_na_rodada = 0
	jogador_atual += 1
	if jogador_atual >= jogadores.size():
		jogador_atual = 0
		rodada_atual += 1
	if rodada_atual >= rodadas:
		rodada_atual = rodadas - 1
		return "fim"
	return "rodada"


func total(i: int) -> int:
	return int(jogadores[i]["pontos"])


func vencedor() -> int:
	if jogadores.size() < 2:
		return 0
	if total(0) == total(1):
		return -1
	return 0 if total(0) > total(1) else 1


## Pontuação máxima possível (para as estrelas do fim).
func maximo() -> int:
	return rodadas * (10 * PONTOS_PINO + BONUS_STRIKE)


func estrelas(i: int) -> int:
	var f := float(total(i)) / float(max(maximo(), 1))
	if f >= 0.62:
		return 3
	if f >= 0.38:
		return 2
	return 1
