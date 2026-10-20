class_name Animacoes
extends RefCounted

## ANIMAÇÕES DOS PERSONAGENS (poses-chave).
##
## Cada animação: duração, se repete, as poses-chave no tempo e eventos.
## Ângulos em graus, no espaço do personagem (ele olha para +Z):
##   braco_*.x  negativo = levanta para a FRENTE, positivo = para trás
##   braco_e.z  positivo = abre para fora (braço esquerdo fica em +X)
##   braco_d.z  negativo = abre para fora
##   antebraco  x negativo = dobra o cotovelo (mão vem para a frente)
##   coxa.x     negativo = perna para a frente (sempre em relação ao chão)
##   canela.x   positivo = dobra o joelho
##   corpo.x    positivo = inclina para a frente
##   cabeca.x   positivo = olha para baixo; cabeca.y positivo = vira p/ esquerda
## BRAÇOS E A CABEÇA GRANDE: os braços são curtinhos (~28 cm) e a cabeça
## é enorme. Mão levantada vai sempre pelo LADO da cabeça (braco.z bem
## aberto, uns 25-40 graus a partir do "para cima"), nunca por cima ou
## por trás dela — senão a mão some atrás da cabeça ou entra nela.
## (Com o braço acima do ombro, x negativo leva a mão para TRÁS.)
## Extras: "altura" (sobe/desce o quadril, metros — os joelhos dobram
## sozinhos pela IK), "quadril" (desloca o quadril: x para o lado, z para a
## frente — o peso passa de um pé para o outro), "frente" (anda para a
## frente, metros — corrida do arremesso), "giro" (gira o corpo inteiro em
## Y, graus), "voo" (sobe o personagem todo, metros).
## No clipe: "pulos" = [[início, fim, altura]...] — pulo com arco de
## gravidade (somado ao voo); "ik" = "trava" (pés presos no chão, padrão),
## "chao" (só não deixa o pé afundar: corrida) ou "livre".

const PARADO := {
	"braco_e": Vector3(0, 0, 8), "braco_d": Vector3(0, 0, -8),
	"antebraco_e": Vector3(-12, 0, 0), "antebraco_d": Vector3(-12, 0, 0),
}

const PRONTO := {
	"braco_d": Vector3(-48, 0, -4), "antebraco_d": Vector3(-78, 0, 6),
	"braco_e": Vector3(-42, 0, 14), "antebraco_e": Vector3(-72, 0, -18),
	"corpo": Vector3(6, 0, 0), "cabeca": Vector3(4, 0, 0),
	"coxa_e": Vector3(-5, 0, 0), "canela_e": Vector3(10, 0, 0),
	"coxa_d": Vector3(-5, 0, 0), "canela_d": Vector3(10, 0, 0), "altura": -0.012,
}


static func _p(base: Dictionary, mudancas: Dictionary) -> Dictionary:
	var d := base.duplicate()
	for k in mudancas:
		d[k] = mudancas[k]
	return d


static var _cache := {}


static func todos() -> Array:
	if _cache.is_empty():
		_montar()
	return _cache.keys()


static func pegar(nome: String) -> Dictionary:
	if _cache.is_empty():
		_montar()
	return _cache.get(nome, _cache["parado"])


static func _montar() -> void:
	# parado: o peso passa devagar de um pé para o outro, cabeça acompanha
	_cache["parado"] = {
		"dur": 4.0, "loop": true,
		"chaves": [
			[0.0, _p(PARADO, {"quadril": Vector3(0.012, 0, 0), "corpo": Vector3(1, 0, -2), "cabeca": Vector3(0, 0, 3), "altura": -0.006})],
			[2.0, _p(PARADO, {"quadril": Vector3(-0.012, 0, 0), "corpo": Vector3(2, 0, 2), "cabeca": Vector3(3, 0, -3),
				"braco_e": Vector3(4, 0, 11), "braco_d": Vector3(4, 0, -11), "altura": -0.012})],
			[4.0, _p(PARADO, {"quadril": Vector3(0.012, 0, 0), "corpo": Vector3(1, 0, -2), "cabeca": Vector3(0, 0, 3), "altura": -0.006})],
		],
	}
	_cache["pronto"] = {
		"dur": 3.2, "loop": true,
		"chaves": [
			[0.0, PRONTO],
			[1.6, _p(PRONTO, {"altura": -0.008, "corpo": Vector3(7, 0, 0)})],
			[3.2, PRONTO],
		],
	}
	# ---------------------------------------------------- o ARREMESSO
	# passada de 3 passos: empurra a bola, desce, vai lá atrás, desliza e solta.
	var p1 := {
		"braco_d": Vector3(-40, 0, -6), "antebraco_d": Vector3(-25, 0, 0),
		"braco_e": Vector3(-30, 0, 20), "antebraco_e": Vector3(-30, 0, 0),
		"coxa_d": Vector3(-28, 0, 0), "canela_d": Vector3(10, 0, 0),
		"coxa_e": Vector3(14, 0, 0), "canela_e": Vector3(28, 0, 0),
		"corpo": Vector3(8, 0, 0), "altura": -0.02, "frente": 0.45,
	}
	var p2 := {
		"braco_d": Vector3(12, 0, -4), "antebraco_d": Vector3(-5, 0, 0),
		"braco_e": Vector3(-15, 0, 40), "antebraco_e": Vector3(-20, 0, 0),
		"coxa_e": Vector3(-30, 0, 0), "canela_e": Vector3(12, 0, 0),
		"coxa_d": Vector3(16, 0, 0), "canela_d": Vector3(32, 0, 0),
		"corpo": Vector3(12, 0, 0), "altura": -0.03, "frente": 1.05,
	}
	var p3 := {
		"braco_d": Vector3(78, 0, -4), "antebraco_d": Vector3(0, 0, 0),
		"braco_e": Vector3(-25, 0, 60), "antebraco_e": Vector3(-15, 0, 0),
		"coxa_d": Vector3(-32, 0, 0), "canela_d": Vector3(18, 0, 0),
		"coxa_e": Vector3(22, 0, 0), "canela_e": Vector3(40, 0, 0),
		"corpo": Vector3(24, 0, -4), "cabeca": Vector3(-16, 0, 0), "altura": -0.06, "frente": 1.7,
	}
	var p4 := {
		"braco_d": Vector3(-18, 0, -4), "antebraco_d": Vector3(-8, 0, 0),
		"braco_e": Vector3(-10, 0, 80), "antebraco_e": Vector3(-10, 0, 0),
		"coxa_e": Vector3(-58, 0, 0), "canela_e": Vector3(72, 0, 0),
		"coxa_d": Vector3(42, 0, 0), "canela_d": Vector3(12, 0, 0),
		"corpo": Vector3(32, 0, -6), "cabeca": Vector3(-30, 0, 0), "altura": -0.19, "frente": 2.35,
	}
	var p5 := _p(p4, {"braco_d": Vector3(-128, 0, -8), "antebraco_d": Vector3(-25, 0, 0),
		"braco_e": Vector3(-5, 0, 82), "corpo": Vector3(26, 0, -4), "cabeca": Vector3(-24, 0, 0),
		"altura": -0.17, "frente": 2.5})
	var p6 := _p(p5, {"braco_d": Vector3(-112, 0, -10), "antebraco_d": Vector3(-35, 0, 0), "frente": 2.55,
		"cabeca": Vector3(-20, 0, 0)})
	_cache["arremesso"] = {
		"dur": 2.0, "loop": false, "ik": "chao",
		"chaves": [[0.0, PRONTO], [0.28, p1], [0.55, p2], [0.8, p3], [1.02, p4], [1.3, p5], [2.0, p6]],
		"eventos": [[0.28, "som", "passo"], [0.55, "som", "passo"], [0.8, "som", "passo"], [1.0, "soltar", null],
			[0.0, "expressao", "concentrado"], [1.0, "expressao", "surpreso"]],
	}
	# depois de soltar: fica olhando a bola, na pose final
	_cache["assistindo"] = {
		"dur": 1.6, "loop": true, "ik": "chao",
		"chaves": [[0.0, _p(p6, {"frente": 0.0})], [0.8, _p(p6, {"frente": 0.0, "altura": -0.15, "braco_d": Vector3(-100, 0, -12)})],
			[1.6, _p(p6, {"frente": 0.0})]],
	}
	# ---------------------------------------------------- STRIKE: pulão com pirueta e festa!
	# agacha (impulso) -> decola com os braços para cima -> pirueta no ar
	# (arco de gravidade) -> aterrissa dobrando os joelhos -> socos no ar -> pulinho final
	var agacha := _p(PARADO, {"altura": -0.1, "corpo": Vector3(16, 0, 0), "cabeca": Vector3(-6, 0, 0),
		"braco_e": Vector3(28, 0, 22), "braco_d": Vector3(28, 0, -22), "antebraco_e": Vector3(-20, 0, 0), "antebraco_d": Vector3(-20, 0, 0)})
	var voando := {"braco_e": Vector3(-162, 0, 26), "braco_d": Vector3(-162, 0, -26),
		"antebraco_e": Vector3(-10, 0, 0), "antebraco_d": Vector3(-10, 0, 0),
		"coxa_e": Vector3(-34, 0, 4), "canela_e": Vector3(70, 0, 0), "coxa_d": Vector3(-24, 0, -4), "canela_d": Vector3(78, 0, 0),
		"pe_e": Vector3(20, 0, 0), "pe_d": Vector3(24, 0, 0),
		"corpo": Vector3(-8, 0, 0), "cabeca": Vector3(-14, 0, 0)}
	var esticado := _p(voando, {"coxa_e": Vector3(-6, 0, 0), "canela_e": Vector3(8, 0, 0), "coxa_d": Vector3(-6, 0, 0),
		"canela_d": Vector3(8, 0, 0), "pe_e": Vector3(30, 0, 0), "pe_d": Vector3(30, 0, 0), "corpo": Vector3(-4, 0, 0)})
	var aterrissa := _p(agacha, {"altura": -0.085, "braco_e": Vector3(-120, 0, 52), "braco_d": Vector3(-120, 0, -52)})
	# soquinhos no ar: o punho sobe pelo LADO da cabeça (por cima dela sumia)
	var vibra1 := _p(PARADO, {"braco_d": Vector3(-125, 0, -35), "antebraco_d": Vector3(-15, 0, 0), "braco_e": Vector3(-20, 0, 30),
		"corpo": Vector3(-4, 0, -6), "altura": -0.03, "quadril": Vector3(0.015, 0, 0)})
	var vibra2 := _p(vibra1, {"braco_d": Vector3(-155, 0, -35), "antebraco_d": Vector3(-5, 0, 0), "altura": -0.005,
		"quadril": Vector3(-0.01, 0, 0)})
	# impulso: os braços vêm de trás para cima passando pela frente (sem chicotada)
	var impulso := _p(agacha, {"altura": -0.05, "corpo": Vector3(8, 0, 0), "braco_e": Vector3(-70, 0, 20), "braco_d": Vector3(-70, 0, -20),
		"antebraco_e": Vector3(-25, 0, 0), "antebraco_d": Vector3(-25, 0, 0)})
	_cache["comemora_strike"] = {
		"dur": 3.1, "loop": false,
		"pulos": [[0.3, 0.98, 0.52], [2.42, 2.74, 0.12]],
		"chaves": [
			[0.0, PARADO], [0.2, agacha], [0.3, impulso],
			[0.42, _p(esticado, {"giro": 25.0})],
			[0.56, _p(voando, {"giro": 125.0})],
			[0.72, _p(voando, {"giro": 245.0})],
			[0.92, _p(esticado, {"giro": 360.0})],
			[1.06, _p(aterrissa, {"giro": 360.0})],
			[1.3, _p(vibra1, {"giro": 360.0})], [1.5, _p(vibra2, {"giro": 360.0})], [1.7, _p(vibra1, {"giro": 360.0})],
			[1.9, _p(vibra2, {"giro": 360.0})], [2.1, _p(vibra1, {"giro": 360.0})],
			[2.36, _p(agacha, {"giro": 360.0, "altura": -0.06, "braco_e": Vector3(-110, 0, 30), "braco_d": Vector3(-110, 0, -30),
				"antebraco_e": Vector3(-20, 0, 0), "antebraco_d": Vector3(-20, 0, 0)})],
			[2.5, _p(esticado, {"giro": 360.0})],
			[2.78, _p(aterrissa, {"giro": 360.0, "altura": -0.05})],
			[3.1, _p(PARADO, {"giro": 360.0})],
		],
		"eventos": [[0.0, "expressao", "empolgado"], [0.3, "jatos", true], [0.3, "som", "jato"], [2.7, "jatos", false],
			[1.1, "expressao", "risada"], [1.0, "som", "passo"], [2.74, "som", "passo"]],
	}
	# ---------------------------------------------------- feliz (spare, boa jogada): pulinho + palmas
	var palma_junta := _p(PARADO, {"braco_e": Vector3(-72, 0, -12), "antebraco_e": Vector3(-48, -20, -25),
		"braco_d": Vector3(-72, 0, 12), "antebraco_d": Vector3(-48, 20, 25), "corpo": Vector3(4, 0, 0)})
	var palma_abre := _p(palma_junta, {"braco_e": Vector3(-70, 0, 14), "braco_d": Vector3(-70, 0, -14)})
	_cache["feliz"] = {
		"depois": "parado", "dur": 1.9, "loop": false,
		"pulos": [[0.22, 0.56, 0.2]],
		"chaves": [
			[0.0, PARADO],
			[0.18, _p(agacha, {"altura": -0.07})],
			[0.39, _p(PARADO, {"braco_e": Vector3(-130, 0, 45), "braco_d": Vector3(-130, 0, -45), "coxa_e": Vector3(-20, 0, 0),
				"canela_e": Vector3(45, 0, 0), "coxa_d": Vector3(-20, 0, 0), "canela_d": Vector3(45, 0, 0)})],
			[0.62, _p(PARADO, {"altura": -0.05})],
			[0.75, palma_junta], [0.9, palma_abre], [1.05, palma_junta], [1.2, palma_abre], [1.35, palma_junta],
			[1.9, PARADO],
		],
		"eventos": [[0.0, "expressao", "feliz"], [0.75, "som", "palma"], [1.05, "som", "palma"], [1.35, "som", "palma"]],
	}
	# ---------------------------------------------------- triste (errou): cabeça baixa, balança
	var baixa := _p(PARADO, {"cabeca": Vector3(26, 0, 0), "corpo": Vector3(10, 0, 0), "braco_e": Vector3(6, 0, 3), "braco_d": Vector3(6, 0, -3),
		"altura": -0.03})
	_cache["triste"] = {
		"depois": "parado", "dur": 2.0, "loop": false,
		"chaves": [[0.0, PARADO], [0.3, baixa], [0.6, _p(baixa, {"cabeca": Vector3(24, -22, 0)})], [0.9, _p(baixa, {"cabeca": Vector3(24, 22, 0)})],
			[1.2, _p(baixa, {"cabeca": Vector3(20, 0, 0)})], [1.5, baixa],
			[2.0, _p(PARADO, {"braco_e": Vector3(-20, 0, 40), "braco_d": Vector3(-20, 0, -40), "antebraco_e": Vector3(-80, 0, 0), "antebraco_d": Vector3(-80, 0, 0)})]],
		"eventos": [[0.0, "expressao", "triste"], [1.6, "expressao", "concentrado"]],
	}
	# ---------------------------------------------------- torcida (o outro jogando)
	var t1 := _p(PARADO, {"braco_e": Vector3(-155, 0, 28), "antebraco_e": Vector3(-30, 0, 0), "braco_d": Vector3(-110, 0, -40), "antebraco_d": Vector3(-70, 0, 0)})
	var t2 := _p(PARADO, {"braco_d": Vector3(-155, 0, -28), "antebraco_d": Vector3(-30, 0, 0), "braco_e": Vector3(-110, 0, 40), "antebraco_e": Vector3(-70, 0, 0)})
	_cache["torcida"] = {
		"dur": 2.4, "loop": true,
		"chaves": [[0.0, _p(t1, {"quadril": Vector3(0.01, 0, 0)})], [0.6, _p(t1, {"quadril": Vector3(0.012, 0, 0), "altura": -0.006})],
			[1.2, _p(t2, {"quadril": Vector3(-0.01, 0, 0)})], [1.8, _p(t2, {"quadril": Vector3(-0.012, 0, 0), "altura": -0.006})],
			[2.4, _p(t1, {"quadril": Vector3(0.01, 0, 0)})]],
	}
	# festa (fim de jogo): braços para cima balançando, sem pular
	var f1 := _p(PARADO, {"braco_e": Vector3(-150, 0, 38), "antebraco_e": Vector3(-15, 0, 0), "braco_d": Vector3(-150, 0, -38),
		"antebraco_d": Vector3(-15, 0, 0), "corpo": Vector3(-3, 0, -5), "cabeca": Vector3(-6, 0, 6), "quadril": Vector3(0.015, 0, 0)})
	var f2 := _p(f1, {"corpo": Vector3(-3, 0, 5), "cabeca": Vector3(-6, 0, -6), "quadril": Vector3(-0.015, 0, 0)})
	_cache["festa"] = {"dur": 2.0, "loop": true, "chaves": [[0.0, f1], [1.0, f2], [2.0, f1]]}
	# ---------------------------------------------------- dança (atração / fim): o quadril vai de um lado
	# para o outro no ritmo, joelhos dobram no tempo forte, um pezinho bate.
	var d1 := _p(PARADO, {"braco_e": Vector3(-110, 0, 30), "antebraco_e": Vector3(-35, 0, 0), "braco_d": Vector3(-8, 0, -30),
		"antebraco_d": Vector3(-90, 0, 0), "corpo": Vector3(2, 10, 7), "cabeca": Vector3(0, -10, -8), "quadril": Vector3(0.035, 0, 0)})
	var d2 := _p(PARADO, {"braco_d": Vector3(-110, 0, -30), "antebraco_d": Vector3(-35, 0, 0), "braco_e": Vector3(-8, 0, 30),
		"antebraco_e": Vector3(-90, 0, 0), "corpo": Vector3(2, -10, -7), "cabeca": Vector3(0, 10, 8), "quadril": Vector3(-0.035, 0, 0)})
	_cache["danca"] = {
		"dur": 2.8, "loop": true,
		"chaves": [[0.0, d1], [0.4, _p(d1, {"altura": -0.018, "quadril": Vector3(0.025, 0, 0)})], [0.7, d1],
			[0.95, _p(d1, {"coxa_d": Vector3(-22, 0, 0), "canela_d": Vector3(40, 0, 0), "pe_d": Vector3(12, 0, 0)})], [1.2, d1],
			[1.4, d2], [1.8, _p(d2, {"altura": -0.018, "quadril": Vector3(-0.025, 0, 0)})], [2.1, d2],
			[2.35, _p(d2, {"coxa_e": Vector3(-22, 0, 0), "canela_e": Vector3(40, 0, 0), "pe_e": Vector3(12, 0, 0)})], [2.6, d2],
			[2.8, d1]],
	}
	# um pedacinho de dança e volta a ficar parado (atração)
	var dc := []
	for c in _cache["danca"]["chaves"]:
		dc.append(c)
	for c in (_cache["danca"]["chaves"] as Array).slice(1):
		dc.append([float(c[0]) + 2.8, c[1]])
	_cache["danca_curta"] = {"dur": 5.6, "loop": false, "depois": "parado", "chaves": dc}
	# ---------------------------------------------------- acenar (oi!)
	# o braço sobe pelo LADO da cabeça e a mão balança — a cabeça é grande:
	# com o braço por cima dela (como antes) a mão sumia atrás
	var a1 := _p(PARADO, {"braco_d": Vector3(-150, 0, -38), "antebraco_d": Vector3(-10, 0, -30), "cabeca": Vector3(0, 0, 6),
		"quadril": Vector3(0.015, 0, 0), "corpo": Vector3(0, 0, -3)})
	var a2 := _p(a1, {"antebraco_d": Vector3(-10, 0, 28), "cabeca": Vector3(0, 0, -4), "quadril": Vector3(0.008, 0, 0)})
	_cache["acenar"] = {"dur": 1.2, "loop": true, "chaves": [[0.0, a1], [0.3, a2], [0.6, a1], [0.9, a2], [1.2, a1]]}
	# "oi!" uma vez e volta a ficar parado (atração)
	_cache["acenar_uma"] = {"dur": 2.6, "loop": false, "depois": "parado",
		"chaves": [[0.0, PARADO], [0.35, a1], [0.65, a2], [0.95, a1], [1.25, a2], [1.55, a1], [1.85, a2], [2.6, PARADO]],
		"eventos": [[0.0, "expressao", "feliz"]]}
	# olha para os lados, curioso (atração)
	_cache["olhar_volta"] = {"dur": 3.2, "loop": false, "depois": "parado",
		"chaves": [[0.0, PARADO], [0.6, _p(PARADO, {"cabeca": Vector3(4, 35, 4), "corpo": Vector3(0, 8, 0)})],
			[1.5, _p(PARADO, {"cabeca": Vector3(4, 35, 4), "corpo": Vector3(0, 8, 0)})],
			[2.1, _p(PARADO, {"cabeca": Vector3(2, -30, -4), "corpo": Vector3(0, -6, 0)})],
			[2.7, _p(PARADO, {"cabeca": Vector3(2, -30, -4), "corpo": Vector3(0, -6, 0)})], [3.2, PARADO]]}
	# ---------------------------------------------------- andar
	var w1 := _p(PARADO, {"coxa_e": Vector3(-26, 0, 0), "canela_e": Vector3(8, 0, 0), "coxa_d": Vector3(22, 0, 0), "canela_d": Vector3(30, 0, 0),
		"braco_e": Vector3(25, 0, 10), "braco_d": Vector3(-25, 0, -10), "altura": -0.015})
	var w2 := _p(PARADO, {"coxa_d": Vector3(-26, 0, 0), "canela_d": Vector3(8, 0, 0), "coxa_e": Vector3(22, 0, 0), "canela_e": Vector3(30, 0, 0),
		"braco_d": Vector3(25, 0, -10), "braco_e": Vector3(-25, 0, 10), "altura": -0.015})
	_cache["andar"] = {"dur": 0.7, "loop": true, "ik": "chao", "chaves": [[0.0, w1], [0.175, _p(PARADO, {"altura": 0.02})], [0.35, w2], [0.525, _p(PARADO, {"altura": 0.02})], [0.7, w1]]}
	# ---------------------------------------------------- vitória: pulinhos de alegria, braços para cima
	var v_baixo := _p(agacha, {"altura": -0.08, "braco_e": Vector3(-150, 0, 40), "braco_d": Vector3(-150, 0, -40)})
	var v_alto := _p(voando, {})
	_cache["vitoria"] = {
		"dur": 1.4, "loop": false, "depois": "festa",
		"pulos": [[0.12, 0.58, 0.3], [0.82, 1.24, 0.24]],
		"chaves": [[0.0, v_baixo], [0.12, _p(esticado, {})], [0.35, v_alto], [0.58, _p(esticado, {})], [0.7, v_baixo],
			[0.82, _p(esticado, {"corpo": Vector3(-6, 0, 8)})], [1.03, _p(v_alto, {"corpo": Vector3(-6, 0, 10)})],
			[1.24, _p(esticado, {})], [1.4, v_baixo]],
	}
	# ---------------------------------------------------- escolhido (seleção de personagem)
	_cache["escolhido"] = {
		"dur": 1.4, "loop": false,
		"pulos": [[0.2, 0.62, 0.26]],
		"chaves": [[0.0, PARADO], [0.17, _p(agacha, {"altura": -0.07})],
			[0.41, _p(PARADO, {"braco_d": Vector3(-165, 0, -25), "antebraco_d": Vector3(-10, 0, 0), "braco_e": Vector3(10, 0, 30),
				"coxa_e": Vector3(-30, 0, 0), "canela_e": Vector3(55, 0, 0), "coxa_d": Vector3(-10, 0, 0), "canela_d": Vector3(25, 0, 0)})],
			[0.75, _p(PARADO, {"altura": -0.03, "braco_d": Vector3(-160, 0, -28)})],
			[1.4, _p(PARADO, {"braco_d": Vector3(-150, 0, -30), "antebraco_d": Vector3(-40, 0, 0)})]],
		"eventos": [[0.0, "expressao", "empolgado"], [1.2, "expressao", "piscadinha"]],
	}
	# ---------------------------------------------------- quase (ficou 1 pino): mãos nas bochechas
	# (com os braços curtinhos, "mãos na cabeça" enfiava as mãos dentro dela)
	_cache["quase"] = {
		"depois": "parado", "dur": 1.7, "loop": false,
		"chaves": [[0.0, PARADO],
			[0.3, _p(PARADO, {"braco_e": Vector3(-110, 0, 20), "antebraco_e": Vector3(-30, 0, 0), "braco_d": Vector3(-110, 0, -20), "antebraco_d": Vector3(-30, 0, 0),
				"corpo": Vector3(-6, 0, 0), "cabeca": Vector3(-10, 0, 0)})],
			[1.2, _p(PARADO, {"braco_e": Vector3(-115, 0, 18), "antebraco_e": Vector3(-35, 0, 0), "braco_d": Vector3(-115, 0, -18), "antebraco_d": Vector3(-35, 0, 0),
				"corpo": Vector3(-4, 0, 0), "cabeca": Vector3(-6, 0, 4)})],
			[1.7, PARADO]],
		"eventos": [[0.0, "expressao", "surpreso"]],
	}
