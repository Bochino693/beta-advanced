class_name Mundo
extends Node3D

## O MUNDO 3D: céu, sol, terreno com morros, a pista (madeira, canaletas,
## para-choques), o fundo dos pinos (veludo com estrelas, letreiro com
## lâmpadas) e os 4 CENÁRIOS (temas.gd): Parque de Diversões, Espaço,
## Fundo do Mar e Selva dos Dinos — um por rodada.
##
## Medidas: linha de falta em z = 0; os pinos em z = -10,5 (pista infantil,
## mais curta que a de adulto: a bola chega rápido); a pista vai para -Z.
##
## Marca Lazer & Sport (no 3D): sutil, uma em cada cenário (balãozinho no
## Parque, planetinha no Espaço, bolha no Mar, pterossauro nos Dinos).
## Pódios (escolha do personagem e foto) nas cores de Bob e Mia.

const MEIA_LARGURA := 0.675
const CANALETA := 0.25
const Z_PINO1 := -10.5
const ESPACO_PINOS := 0.38
const FILEIRA := 0.329
const Z_FIM_DECK := -11.95
const Z_FUNDO := -13.7
## para-choques: 10 pedaços de 0,96 m a partir da linha de falta — acabam
## em z = -9,8, antes da barra varredora (z = -10) e do fosso
const N_BUMPERS := 10

const CAMADA_MUNDO := 1
const CAMADA_PINOS := 2
const CAMADA_BOLA := 4
const CAMADA_PISO_BOLA := 8
const CAMADA_PISO_PINOS := 16
const CAMADA_SO_PINOS := 32      # parede que segura os pinos mas deixa a bola passar (caçapa)
## topo da boca da caçapa das bolas (no fundo do fosso)
const Y_BOCA := 0.28
const LARGURA_BOCA := 1.5
## retorno de bolas (perto de quem joga)
const RETORNO := Vector3(2.35, 0, 5.2)
const ALTURA_PODIO := 0.152
const BALAO_POS := Vector3(-1.75, 2.2, Z_PINO1 + 3.0)

var ambiente: Environment
var sol: DirectionalLight3D
var mat_pista: ShaderMaterial
var mat_piso: ShaderMaterial
var mat_lampadas: ShaderMaterial
var mat_fundo: ShaderMaterial
var mat_ceu: ShaderMaterial
var mat_placa: ShaderMaterial
var mat_divisoria: ShaderMaterial
var mat_faixa: ShaderMaterial
var mats_canaleta: Array[ShaderMaterial] = []
var mat_terreno: ShaderMaterial
var mat_gabinete: ShaderMaterial
var mat_parede: ShaderMaterial
var mat_coluna: ShaderMaterial
var mat_friso: ShaderMaterial
var mat_portal: ShaderMaterial
var temas: Temas
var tema := ""
var _bumpers: Array[Node3D] = []
var balao: Node3D                # o símbolo do cenário de agora (Parque: o balão)
var mat_balao: ShaderMaterial
var _marcas := {}                # cenário -> o seu símbolo Lazer & Sport
var _bolhinhas: Array[Node3D] = []
var _podios: Array[Node3D] = []
var _mats_podio: Array[ShaderMaterial] = []
var _podio_destaque := -1
var _t := 0.0
var _luz := 0.0
var _luz_alvo := 0.0
var bola_z := 100.0
var bola: Node3D                 # a bola do jogo (as tiras da caçapa abrem quando ela passa)
var _tiras: MultiMeshInstance3D
var _abertura_tiras: PackedFloat32Array = PackedFloat32Array()
var _bola_volta: MeshInstance3D
var mat_boca_luz: ShaderMaterial
## CENÁRIO LEVE (o padrão; menu do operador > "Cenário (fundo)"): o fundo
## mais barato para a TV Box rodar lisa — chão e decoração com a luz feita
## por vértice, metade da decoração, céu simples e sem neblina. A pista,
## os pinos, a máquina e os bichinhos são os mesmos do COMPLETO.
var leve := false


## Onde um objeto movido pela física APARECE neste quadro (interpolado
## entre dois passos). No quadro de um teletransporte (bola saindo da mão,
## pino recolocado) o Godot ainda devolve o lugar antigo: aí vale o atual.
static func na_tela(n: Node3D) -> Transform3D:
	if not n.is_physics_interpolated_and_enabled():
		return n.global_transform
	var t := n.get_global_transform_interpolated()
	var g := n.global_transform
	if t.origin.distance_squared_to(g.origin) > 1.0:
		return g
	return t


func construir() -> void:
	leve = Ajustes.cenario_leve()
	_ambiente()
	_sol()
	_astro_no_ceu()
	_terreno()
	_pista()
	_fundo_dos_pinos()
	_colunas()
	_marcas_dos_cenarios()
	_area_dos_jogadores()
	_montar_podios()
	temas = Temas.new()
	add_child(temas)
	temas.construir(self)
	# peças paradas com o mesmo material viram uma malha só (menos desenhos)
	var fora: Array = [temas]
	fora.append_array(_marcas.values())
	fora.append_array(_podios)
	fora.append_array(_bumpers)
	Lote.juntar(self, fora, 0.0)
	aplicar_tema(Temas.ORDEM[0])
	definir_protecao(Ajustes.protecao_canaleta())


## Troca o cenário: céu, luz, neblina, terreno, cores da pista e decoração.
func aplicar_tema(nome: String) -> void:
	if not Temas.CONFIG.has(nome):
		nome = "parque"
	tema = nome
	var c: Dictionary = Temas.CONFIG[nome]
	var ceu: Array = c["ceu"]
	mat_ceu.set_shader_parameter("cor_topo", ceu[0])
	mat_ceu.set_shader_parameter("cor_meio", ceu[1])
	mat_ceu.set_shader_parameter("cor_horizonte", ceu[2])
	mat_ceu.set_shader_parameter("cor_chao", ceu[3])
	mat_ceu.set_shader_parameter("cor_sol", c.get("cor_sol", Color(1.0, 0.95, 0.75)))
	mat_ceu.set_shader_parameter("forca_sol", c.get("forca_sol", 1.0))
	mat_ceu.set_shader_parameter("estrelas", c.get("estrelas", 0.0))
	mat_ceu.set_shader_parameter("cor_nebulosa", c.get("nebulosa", Color(0.9, 0.4, 1.0)))
	mat_ceu.set_shader_parameter("raios", c.get("raios", 0.0))
	ambiente.ambient_light_color = c["ambiente"]
	ambiente.ambient_light_energy = c.get("ambiente_forca", 0.62)
	ambiente.fog_light_color = c["neblina"]
	ambiente.fog_density = c.get("neblina_densidade", 0.0045)
	sol.light_color = c["sol"]
	sol.light_energy = c.get("sol_forca", 1.05)
	# a pista e o piso não usam o cálculo de luz do motor (são leves): a luz
	# da cena (ambiente + sol batendo no chão) vai pronta para o shader
	var para_sol := sol.global_transform.basis.z.normalized() if sol.is_inside_tree() else Vector3(0.35, 0.79, 0.5)
	var amb: Color = (c["ambiente"] as Color).srgb_to_linear() * float(c.get("ambiente_forca", 0.62))
	var luz_sol: Color = (c["sol"] as Color).srgb_to_linear() * float(c.get("sol_forca", 1.05)) * maxf(para_sol.y, 0.0)
	var luz_cena := Vector3(amb.r + luz_sol.r, amb.g + luz_sol.g, amb.b + luz_sol.b)
	# chão e decoração: a luz da cena vai pronta para o shader (por
	# vértice no leve, por pixel na decoração do completo)
	var sol_lin: Color = (c["sol"] as Color).srgb_to_linear() * float(c.get("sol_forca", 1.05))
	var sol_cor := Vector3(sol_lin.r, sol_lin.g, sol_lin.b)
	var amb_v := Vector3(amb.r, amb.g, amb.b)
	var nb: Color = (c["neblina"] as Color).srgb_to_linear()
	var neblina := Vector3(nb.r, nb.g, nb.b)
	var densidade := float(c.get("neblina_densidade", 0.0045))
	for m in [mat_terreno]:
		m.set_shader_parameter("sol_dir", para_sol)
		m.set_shader_parameter("sol_cor", sol_cor)
		m.set_shader_parameter("ambiente", amb_v)
		m.set_shader_parameter("neblina_cor", neblina)
		m.set_shader_parameter("neblina_densidade", densidade)
	temas.luz(para_sol, sol_cor, amb_v, neblina, densidade)
	for m in [mat_pista, mat_piso]:
		m.set_shader_parameter("luz_cena", luz_cena)
		m.set_shader_parameter("cor_ceu", ceu[2])
	mat_pista.set_shader_parameter("dir_sol", para_sol)
	var f: Array = c["fundo"]
	mat_fundo.set_shader_parameter("cor_a", f[0])
	mat_fundo.set_shader_parameter("cor_b", f[1])
	mat_fundo.set_shader_parameter("cor_halo", c["halo"])
	mat_boca_luz.set_shader_parameter("emissao", (c["halo"] as Color) * 0.9)
	mat_placa.set_shader_parameter("tinta", c["placa"])
	var portal: Array = c["portal"]
	# a pista: neon das bordas e o reflexo do portal no verniz
	mat_pista.set_shader_parameter("cor_luz", c.get("neon", portal[0]))
	mat_pista.set_shader_parameter("cor_reflexo_a", portal[0])
	mat_pista.set_shader_parameter("cor_reflexo_b", portal[1])
	mat_portal.set_shader_parameter("cor_a", portal[0])
	mat_portal.set_shader_parameter("cor_b", portal[1])
	mat_gabinete.set_shader_parameter("tinta", c["gabinete"])
	mat_coluna.set_shader_parameter("tinta", c["coluna"])
	mat_parede.set_shader_parameter("tinta", c["parede"])
	mat_divisoria.set_shader_parameter("tinta", c["divisoria"])
	mat_faixa.set_shader_parameter("tinta", c["faixa"])
	for m in mats_canaleta:
		m.set_shader_parameter("tinta", c["canaleta"])
	var chao: Array = c["chao"]
	mat_terreno.set_shader_parameter("modo", int(c["chao_modo"]))
	# cores do chão: lineares no leve; no completo, no espaço da conta do
	# motor (o terreno antigo passava a cor linear e o motor convertia de
	# novo: convertida duas vezes, fica igual a ele)
	for i in 4:
		var l: Color = _cor_do_chao(chao[i])
		mat_terreno.set_shader_parameter(["lin_a", "lin_b", "lin_c", "lin_d"][i], Vector3(l.r, l.g, l.b))
	if not leve:
		# a terra da selva: o detalhe 2 x (0.72, 0.6, 0.45) na cor sRGB
		var d: Color = chao[3]
		var terra := _cor_do_chao(Color(d.r * 0.72, d.g * 0.6, d.b * 0.45))
		var dl := _cor_do_chao(d)
		mat_terreno.set_shader_parameter("terra", Vector3(terra.r / maxf(dl.r, 1e-5), terra.g / maxf(dl.g, 1e-5), terra.b / maxf(dl.b, 1e-5)))
	_mostrar_marca(nome)
	_mostrar_astro(nome)
	temas.mostrar(nome)


func _cor_do_chao(c: Color) -> Color:
	var l := c.srgb_to_linear()
	return l if leve else l.srgb_to_linear()


# ================================================================ sol e lua
## SOL E LUA COM ROSTINHO no céu: sol no Parque, nos Dinos e no Mar (visto
## de dentro d'água, mais azulado) e a lua no Espaço. Um quadradinho sempre
## de frente para a câmera, desenhado NA DIREÇÃO do sol do céu e sempre à
## mesma distância da câmera (astro.gdshader) — como o céu, ele fica "no
## infinito": por mais que a câmera passeie (pinos, caçapa, trilhos), o
## rostinho fica exatamente onde o céu desenha o brilho do sol, e atrás de
## todo o cenário. Os raios giram e o rosto pisca no próprio shader.
## As 3 imagens (pequenas) ficam carregadas desde o começo: trocar de
## cenário não lê nada do disco.
## [imagem, onde fica visto da área de jogo, tamanho (m) a ~67 m, tinta]
const ASTROS := {
	"parque": ["sol", Vector3(9.8, 25.2, -59.4), 8.5, Color(1, 1, 1, 1)],
	"dinos": ["sol", Vector3(9.8, 25.2, -59.4), 8.5, Color(1, 1, 1, 1)],
	"mar": ["sol", Vector3(9.8, 25.2, -59.4), 8.0, Color(0.86, 1.0, 1.0, 0.82)],
	"espaco": ["lua", Vector3(-1.1, 26.3, -59.7), 7.2, Color(1, 1, 1, 1)],
}
## de onde as posições acima foram escolhidas (a área de jogo)
const ASTRO_REFERENCIA := Vector3(0.0, 1.2, 2.4)
## distância do rostinho até a câmera: atrás de tudo do cenário e antes do
## fim da visão da câmera (160 m)
const ASTRO_DISTANCIA := 140.0
var _astro: MeshInstance3D
var _mat_astro: ShaderMaterial
var _img_astro := {}


func _astro_no_ceu() -> void:
	for n in ["sol", "lua", "sol_raios"]:
		_img_astro[n] = load("res://ui/ceu/%s.png" % n)
	_mat_astro = ShaderMaterial.new()
	_mat_astro.shader = load("res://shaders/astro.gdshader")
	_mat_astro.set_shader_parameter("distancia", ASTRO_DISTANCIA)
	# o primeiro dos transparentes: o que estiver na frente (bolhas,
	# partículas) é desenhado por cima dele
	_mat_astro.render_priority = Material.RENDER_PRIORITY_MIN
	_astro = MeshInstance3D.new()
	_astro.name = "astro"
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_astro.mesh = q
	_astro.material_override = _mat_astro
	_astro.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# o shader coloca o quadrado longe, na frente da câmera: a caixa de
	# visibilidade cobre toda a visão (nunca some por engano)
	_astro.custom_aabb = AABB(Vector3(-400, -400, -400), Vector3(800, 800, 800))
	add_child(_astro)


func _mostrar_astro(nome: String) -> void:
	var a: Array = ASTROS.get(nome, ASTROS["parque"])
	var sol: bool = a[0] == "sol"
	var rel: Vector3 = (a[1] as Vector3) - ASTRO_REFERENCIA
	var dir := rel.normalized()
	_mat_astro.set_shader_parameter("rosto", _img_astro[a[0]])
	_mat_astro.set_shader_parameter("raios", _img_astro["sol_raios"] if sol else null)
	_mat_astro.set_shader_parameter("usa_raios", 1.0 if sol else 0.0)
	_mat_astro.set_shader_parameter("tinta", a[3])
	_mat_astro.set_shader_parameter("direcao", dir)
	# o mesmo tamanho na tela que teria a ~67 m, agora a ASTRO_DISTANCIA
	_mat_astro.set_shader_parameter("tamanho", float(a[2]) * ASTRO_DISTANCIA / rel.length())
	# o brilho do sol do céu fica bem atrás dele, de qualquer ponto de vista
	mat_ceu.set_shader_parameter("dir_sol", dir)


# ================================================================ ambiente
func _ambiente() -> void:
	var we := WorldEnvironment.new()
	ambiente = Environment.new()
	var ceu := Sky.new()
	var mc := ShaderMaterial.new()
	mc.shader = load("res://shaders/ceu_leve.gdshader" if leve else "res://shaders/ceu.gdshader")
	mat_ceu = mc
	ceu.sky_material = mc
	ceu.radiance_size = Sky.RADIANCE_SIZE_32
	ambiente.background_mode = Environment.BG_SKY
	ambiente.sky = ceu
	ambiente.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ambiente.ambient_light_color = Color(0.62, 0.7, 0.86)
	ambiente.ambient_light_energy = 0.62
	# sem reflexo do céu nos materiais (o toon não usa; a pista e o piso
	# desenham o próprio verniz): economiza uma busca de textura por pixel
	ambiente.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	ambiente.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	ambiente.tonemap_exposure = 1.0
	ambiente.tonemap_white = 1.6
	ambiente.glow_enabled = true
	ambiente.glow_intensity = 0.55
	ambiente.glow_strength = 0.9
	ambiente.glow_bloom = 0.0
	ambiente.glow_hdr_threshold = 1.0
	ambiente.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	ambiente.fog_enabled = true
	ambiente.fog_light_color = Color(0.86, 0.9, 1.0)
	ambiente.fog_density = 0.0045
	ambiente.fog_sky_affect = 0.0
	# saturação e contraste: feitos na hora de colocar o 3D na tela (hud),
	# sem a passada extra de pós-processamento do motor
	ambiente.adjustment_enabled = false
	we.environment = ambiente
	add_child(we)


func _sol() -> void:
	sol = DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-52, 28, 0)
	sol.light_color = Color(1.0, 0.95, 0.86)
	sol.light_energy = 1.05
	sol.shadow_enabled = false
	add_child(sol)


## Qualidade (o sol NÃO faz sombra de verdade em nenhuma: no Godot
## "Compatibilidade" isso desenha a cena inteira duas vezes. Pinos, bola e
## bichinhos têm sombrinha pintada no chão, que acompanha cada um):
##   alta  (PC): brilho (glow), neblina e ajuste de cor;
##   media (TV Box): neblina e ajuste de cor;
##   baixa (TV Box fraca): o mínimo.
## O chão e a decoração fazem a própria neblina, por vértice (mesma cor e
## densidade): a do motor (por pixel) só pinta o resto — pista, portal,
## bichinhos — e só no cenário completo (no leve ela fica desligada).
func aplicar_qualidade(q: String) -> void:
	sol.shadow_enabled = false
	ambiente.glow_enabled = q == "alta"
	ambiente.fog_enabled = q != "baixa" and not leve


# ================================================================ terreno
func _terreno() -> void:
	# um relevo só; o desenho do chão de cada cenário sai do shader (nítido)
	# o desenho do chão é o mesmo nas duas versões, feito do jeito barato
	# (terreno_desenho.gdshaderinc: 1 sorteio por pixel); no leve a luz é
	# por vértice e mais simples, no completo é a mesma conta do motor
	mat_terreno = ShaderMaterial.new()
	mat_terreno.shader = load("res://shaders/terreno_leve.gdshader" if leve else "res://shaders/terreno.gdshader")
	var t := MeshInstance3D.new()
	t.mesh = load("res://modelos/terreno.res")
	t.material_override = mat_terreno
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(t)
	# chão de segurança (nada cai para sempre)
	var chao := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	chao.add_child(cs)
	chao.position.y = -0.6
	chao.collision_layer = CAMADA_MUNDO
	add_child(chao)


# ================================================================ pista
func _caixa(tam: Vector3, pos: Vector3, mat: Material, colisao := true, sombra := false, atrito := 0.4, quique := 0.2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	if not sombra:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if colisao:
		_corpo_caixa(tam, pos, atrito, quique)
	return mi


## Corpo parado com uma forma pronta (a do próprio desenho da peça).
func _corpo_forma(forma: Shape3D, pos: Vector3, atrito := 0.4, quique := 0.2) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = forma
	sb.add_child(cs)
	sb.position = pos
	sb.collision_layer = CAMADA_MUNDO
	sb.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = atrito
	pm.bounce = quique
	sb.physics_material_override = pm
	add_child(sb)
	return sb


func _corpo_caixa(tam: Vector3, pos: Vector3, atrito := 0.4, quique := 0.2) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = tam
	cs.shape = bs
	sb.add_child(cs)
	sb.position = pos
	sb.collision_layer = CAMADA_MUNDO
	sb.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = atrito
	pm.bounce = quique
	sb.physics_material_override = pm
	add_child(sb)
	return sb


func _pista() -> void:
	# --- tábuas da pista (com marcações e luzes)
	mat_pista = ShaderMaterial.new()
	mat_pista.shader = load("res://shaders/pista.gdshader")
	mat_pista.set_shader_parameter("madeira", Materiais.textura("madeira"))
	mat_pista.set_shader_parameter("z_pino1", Z_PINO1)
	mat_pista.set_shader_parameter("meia_largura", MEIA_LARGURA)
	var comp := 0.1 - Z_FIM_DECK
	var deck := _caixa(Vector3(MEIA_LARGURA * 2, 0.2, comp), Vector3(0, -0.1, 0.1 - comp / 2), mat_pista, false, false)
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# física: duas peças INTEIRAS (sem emendas, que fariam a bola pular):
	# a da bola é lisa (óleo); a dos pinos tem atrito de madeira seca, para
	# eles não escorregarem como no gelo. Cada uma só "existe" para quem pisa.
	var cb := 1.2 - Z_FIM_DECK
	var piso_bola := _corpo_caixa(Vector3(MEIA_LARGURA * 2, 0.2, cb), Vector3(0, -0.1, 1.2 - cb / 2), 0.05, 0.05)
	piso_bola.collision_layer = CAMADA_PISO_BOLA
	var piso_pinos := _corpo_caixa(Vector3(MEIA_LARGURA * 2, 0.2, cb), Vector3(0, -0.1, 1.2 - cb / 2), 0.42, 0.1)
	piso_pinos.collision_layer = CAMADA_PISO_PINOS

	# --- área de aproximação (onde o personagem corre): madeira leve
	mat_piso = ShaderMaterial.new()
	mat_piso.shader = load("res://shaders/piso.gdshader")
	mat_piso.set_shader_parameter("madeira", Materiais.textura("madeira"))
	var aprox := _caixa(Vector3(6.6, 0.2, 6.2), Vector3(0, -0.101, 3.2), mat_piso, true, false, 0.8, 0.0)
	aprox.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# faixa colorida nas bordas da aproximação
	mat_faixa = Materiais.cor_toon(Color("#FF9F2E"))
	for s in [-1, 1]:
		_caixa(Vector3(0.12, 0.04, 6.2), Vector3(s * 3.3, 0.0, 3.2), mat_faixa, false, false)

	# --- canaletas: meia-cana de verdade (perfil liso, 56 segmentos na
	# curva), lábios no nível da pista; começam na linha de falta
	var perfil_c := Perfis.canaleta(CANALETA / 2.0)
	# mais escura no fundo da calha, clara nos lábios: lê-se a curva de longe
	var malha_c := Perfis.extrudar(perfil_c, Z_FIM_DECK, 0.1, true, true, 50.0, Vector4(-0.15, -0.005, 0.5, 1.05))
	# a colisão é a MESMA meia-cana do desenho: bola e pinos rolam e param
	# dentro da calha, encostados na parede curva — nada atravessa nada
	var forma_c := malha_c.create_trimesh_shape()
	for s in [-1, 1]:
		var x: float = s * (MEIA_LARGURA + CANALETA / 2)
		var mcan := Materiais.toon(false, 0.0, {"tinta": Color("#8FC4EE"), "borda": 0.18, "faixa": 0.22,
			"luz_minima": 0.45, "especular": 0.6, "tamanho_especular": 0.95})
		mats_canaleta.append(mcan)
		var can := MeshInstance3D.new()
		can.mesh = malha_c
		can.material_override = mcan
		can.position = Vector3(x, 0.0, 0.0)
		can.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		can.name = "canaleta_%d" % s
		add_child(can)
		_corpo_forma(forma_c, Vector3(x, 0.0, 0.0), 0.2, 0.1)
		# divisória (capping) arredondada entre a canaleta e o gramado: vai
		# dos pinos até a linha de falta (não invade a área do jogador)
		if mat_divisoria == null:
			mat_divisoria = Materiais.cor_toon(Color("#FFB627"), 0.0, {"borda": 0.25, "especular": 0.4})
		var largura_cap := 0.32
		var xc: float = s * (MEIA_LARGURA + CANALETA + 0.036 + largura_cap / 2)
		var cap := MeshInstance3D.new()
		cap.mesh = Perfis.extrudar(Perfis.retangulo(largura_cap, 0.34, 0.06, Vector2(0, -0.07)), Z_PINO1 + 0.2, 0.1)
		cap.material_override = mat_divisoria
		cap.position = Vector3(xc, 0.0, 0.0)
		cap.name = "divisoria_%d" % s
		add_child(cap)
		# colisão = o próprio desenho (quinas arredondadas, mesmo lugar)
		_corpo_forma(cap.mesh.create_convex_shape(), cap.position, 0.3, 0.3)
		# faixinha de luz em cima da divisória
		var luzes := _caixa(Vector3(0.05, 0.012, -Z_PINO1 - 0.3), Vector3(xc, 0.104, (Z_PINO1 + 0.2) / 2.0 + 0.05),
			Materiais.cor_toon(Color("#FFFFFF"), 0.0, {"emissao": Color(0.35, 0.85, 1.0), "borda": 0.0}), false, false)
		luzes.name = "luz_divisoria_%d" % s

	# --- para-choques (bumpers) listrados de doce
	# cápsula simples + listras pelo shader (nítidas em 4K e levinhas)
	var mb := CapsuleMesh.new()
	mb.radius = 0.07
	mb.height = 1.14
	mb.radial_segments = 14
	mb.rings = 3
	var mat_b := ShaderMaterial.new()
	mat_b.shader = load("res://shaders/doce_listrado.gdshader")
	if Materiais.contornos_ligados:
		var contorno_b := ShaderMaterial.new()
		contorno_b.shader = Materiais.shader(Materiais.CONTORNO)
		contorno_b.set_shader_parameter("espessura", 0.003)
		contorno_b.set_shader_parameter("usa_cor_vertice", 0.0)
		mat_b.next_pass = contorno_b
	for s in [-1, 1]:
		var grupo := Node3D.new()
		grupo.name = "bumpers_%d" % s
		add_child(grupo)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mb
		# terminam ANTES da máquina de pinos (como num boliche de verdade): a
		# barra varredora desce e varre ali sem encostar neles
		var n := N_BUMPERS
		mm.instance_count = n
		for i in n:
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(s * 0.735, 0.1, -0.6 - i * 0.96)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat_b
		grupo.add_child(mmi)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cap := CylinderShape3D.new()
		cap.radius = 0.075
		cap.height = n * 0.96 + 0.2
		cs.shape = cap
		cs.rotation_degrees.x = 90
		cs.position = Vector3(s * 0.735, 0.1, -0.6 - (n - 1) * 0.96 / 2)
		sb.add_child(cs)
		sb.collision_layer = CAMADA_MUNDO
		sb.collision_mask = 0
		var pm := PhysicsMaterial.new()
		pm.bounce = 0.55
		pm.friction = 0.1
		sb.physics_material_override = pm
		sb.name = "fisica"
		grupo.add_child(sb)
		_bumpers.append(grupo)


func definir_protecao(ligada: bool) -> void:
	for g in _bumpers:
		g.visible = ligada
		var sb := g.get_node("fisica") as StaticBody3D
		sb.collision_layer = CAMADA_MUNDO if ligada else 0


# ================================================================ fundo dos pinos
## Peça lisa feita por perfil (scripts/perfis.gd).
func _peca(perfil: PackedVector2Array, z0: float, z1: float, mat: Material, nome := "", sombra := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Perfis.extrudar(perfil, z0, z1)
	mi.material_override = mat
	if not sombra:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if nome != "":
		mi.name = nome
	add_child(mi)
	return mi


## A CAÇAPA e o PORTAL no fim da pista: paredes laterais acolchoadas (os
## pinos batem e voltam), cortina pregueada nas cores do cenário com um
## halo de luz atrás dos pinos, e por fora um gabinete alto (esconde a
## máquina de pinos) com o letreiro STRIKE KIDS e, em cima, um ARCO de
## raios coloridos com lâmpadas — o fundo da pista é um portal de parque,
## nas cores de cada cenário. De qualquer ângulo é uma máquina inteira.
func _fundo_dos_pinos() -> void:
	var fosso := Materiais.cor_toon(Color("#16336E"), 0.0, {"borda": 0.3})
	mat_parede = Materiais.cor_toon(Color("#2A63C4"), 0.0, {"borda": 0.3, "especular": 0.25})
	mat_friso = Materiais.cor_toon(Color("#FFB627"), 0.0, {"borda": 0.25, "especular": 0.5})
	mat_gabinete = Materiais.cor_toon(Color("#E8384F"), 0.004, {"borda": 0.35, "especular": 0.12, "luz_minima": 0.3})
	var z_frente := Z_PINO1 + 0.9
	# paredes laterais (kickbacks): visual arredondado + a mesma colisão de antes
	for s in [-1, 1]:
		var x: float = s * (MEIA_LARGURA + CANALETA + 0.06)
		var parede := _peca(Perfis.retangulo(0.12, 1.0, 0.05, Vector2(x, 0.35)), Z_FUNDO, z_frente, mat_parede, "parede_%d" % s)
		var friso := _peca(Perfis.retangulo(0.17, 0.07, 0.034, Vector2(x, 0.875)), Z_FUNDO, z_frente + 0.02, mat_friso)
		# colisão = o próprio desenho (o friso de cima também segura os pinos)
		_corpo_forma(parede.mesh.create_convex_shape(), Vector3.ZERO, 0.3, 0.35)
		_corpo_forma(friso.mesh.create_convex_shape(), Vector3.ZERO, 0.3, 0.35)
	# fosso
	_caixa(Vector3(2.0, 0.2, -Z_FUNDO + Z_FIM_DECK), Vector3(0, -0.24, (Z_FIM_DECK + Z_FUNDO) / 2), fosso, true, false, 0.9, 0.05)
	_cacapa_das_bolas()
	# cortina pregueada (estrelinhas + halo atrás dos pinos) em cima da boca
	mat_fundo = ShaderMaterial.new()
	mat_fundo.shader = load("res://shaders/fundo_estrelas.gdshader")
	var fundo := MeshInstance3D.new()
	fundo.mesh = Perfis.cortina(2.2, 1.95, 11, 0.07)
	fundo.material_override = mat_fundo
	fundo.position = Vector3(0, Y_BOCA + 0.08 + 0.975, Z_FUNDO + 0.04)
	fundo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fundo.name = "cortina"
	add_child(fundo)
	# parede de trás: em cima vale para tudo; embaixo (a boca) só para os
	# pinos — a bola passa e cai na caçapa
	# (a frente de cada parede fica na frente do que se vê: as pregas da
	# cortina chegam a 7,5 cm e as tiras da boca a 3,6 cm da parede — o
	# pino para encostando nelas, sem entrar)
	_corpo_caixa(Vector3(2.4, 1.6, 0.2), Vector3(0, Y_BOCA + 0.8, Z_FUNDO + 0.075 - 0.1), 0.9, 0.0)
	var so_pinos := _corpo_caixa(Vector3(2.4, 0.9, 0.2), Vector3(0, Y_BOCA - 0.45, Z_FUNDO + 0.04 - 0.1), 0.9, 0.0)
	so_pinos.collision_layer = CAMADA_SO_PINOS
	# teto escuro do fosso (esconde a parte de cima, vista de dentro)
	_caixa(Vector3(2.3, 0.1, -Z_FUNDO + Z_PINO1 + 0.7), Vector3(0, 2.12, (Z_PINO1 + 0.7 + Z_FUNDO) / 2),
		Materiais.cor_toon(Color("#0B1B3A"), 0.0, {"borda": 0.0}), false, false)
	# gabinete por fora: laterais, teto e fundo — alto, esconde a máquina
	var z_tras := Z_FUNDO - 0.95
	var z_masc := Z_PINO1 + 0.68
	for s in [-1, 1]:
		var lado := _peca(Perfis.retangulo(0.34, 3.7, 0.12, Vector2(s * 1.23, 1.55)), z_tras + 0.3, z_masc, mat_gabinete, "gabinete_lado_%d" % s)
		# um pino que voa por cima da parede bate no gabinete (não atravessa)
		_corpo_forma(lado.mesh.create_convex_shape(), Vector3.ZERO, 0.4, 0.3)
	_peca(Perfis.retangulo(2.8, 0.32, 0.1, Vector2(0, 3.24)), z_tras + 0.3, z_masc, mat_gabinete, "gabinete_teto")
	_peca(Perfis.retangulo(2.9, 3.75, 0.22, Vector2(0, 1.53)), z_tras, Z_FUNDO - 0.02, mat_gabinete, "gabinete_fundo")
	_peca(Perfis.retangulo(2.96, 0.09, 0.04, Vector2(0, 3.42)), z_tras - 0.03, z_masc, mat_friso)
	# letreiro (masking) acima dos pinos, com o logo e lâmpadas
	mat_placa = Materiais.cor_toon(Color("#1E3FA0"), 0.004, {"borda": 0.4})
	_peca(Perfis.retangulo(2.7, 0.95, 0.07, Vector2(0, 1.85)), Z_PINO1 + 0.68, Z_PINO1 + 0.82, mat_placa, "placa")
	_peca(Perfis.retangulo(2.8, 1.05, 0.09, Vector2(0, 1.85)), Z_PINO1 + 0.66, Z_PINO1 + 0.78, mat_friso)
	var logo_tex := Materiais.textura("logo")
	if logo_tex != null:
		var logo := MeshInstance3D.new()
		var lq := QuadMesh.new()
		var asp := float(logo_tex.get_width()) / float(logo_tex.get_height())
		lq.size = Vector2(min(2.5, 0.86 * asp), min(2.5, 0.86 * asp) / asp)
		logo.mesh = lq
		var ml := StandardMaterial3D.new()
		ml.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ml.albedo_texture = logo_tex
		ml.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		ml.alpha_scissor_threshold = 0.4
		ml.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		logo.material_override = ml
		logo.position = Vector3(0, 1.86, Z_PINO1 + 0.83)
		logo.name = "logo"
		add_child(logo)
	# ARCO em cima do letreiro: leque de raios nas cores do cenário (a frente)
	# sobre uma chapa escura, e a moldura amarela atrás
	mat_portal = ShaderMaterial.new()
	mat_portal.shader = load("res://shaders/raios.gdshader")
	var chapa := Materiais.cor_toon(Color("#2A1E3A"), 0.0, {"borda": 0.2})
	_peca(_perfil_arco(1.42, 2.22, 2.45, 0.86), Z_PINO1 + 0.69, Z_PINO1 + 0.79, chapa)
	var arco := MeshInstance3D.new()
	arco.mesh = _leque_raios(1.42, 2.22, 2.45, 0.86, 22, Z_PINO1 + 0.792)
	arco.material_override = mat_portal
	arco.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arco.name = "arco"
	add_child(arco)
	_peca(_perfil_arco(1.52, 2.2, 2.45, 0.96), Z_PINO1 + 0.66, Z_PINO1 + 0.76, mat_friso)
	# lâmpadas: contorno do letreiro e do arco
	var pontos: Array[Vector3] = []
	var zc := Z_PINO1 + 0.83
	for i in 26:
		pontos.append(Vector3(-1.3 + i * 0.104, 1.41, zc))
	for i in 9:
		pontos.append(Vector3(-1.33, 1.41 + i * 0.11, zc))
		pontos.append(Vector3(1.33, 1.41 + i * 0.11, zc))
	for i in 31:
		var a := PI * float(i) / 30.0
		pontos.append(Vector3(cos(a) * 1.47, 2.45 + sin(a) * 0.91, zc - 0.02))
	mat_lampadas = ShaderMaterial.new()
	mat_lampadas.shader = load("res://shaders/lampadas.gdshader")
	add_child(lampadas_em(pontos))


## CAÇAPA DAS BOLAS: no fundo do fosso, embaixo da cortina, uma boca
## escura com moldura e cortina de tiras de borracha. A bola rola até lá,
## empurra as tiras e some no túnel (depois volta no retorno de bolas, perto
## de quem joga). Os pinos batem na boca e ficam no fosso.
const N_TIRAS := 7
const Y_CHAO_FOSSO := -0.14


func _cacapa_das_bolas() -> void:
	var escuro := StandardMaterial3D.new()
	escuro.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	escuro.albedo_color = Color("#05070D")
	var borracha := Materiais.cor_toon(Color("#20263A"), 0.0, {"borda": 0.3, "luz_minima": 0.35})
	var meia := LARGURA_BOCA / 2.0
	var alto := Y_BOCA - Y_CHAO_FOSSO
	var fundo := 1.0
	# túnel: chão (a bola rola para dentro), paredes, teto e fundo — escuros
	_caixa(Vector3(LARGURA_BOCA + 0.2, 0.2, fundo), Vector3(0, Y_CHAO_FOSSO - 0.1, Z_FUNDO - fundo / 2), escuro, true, false, 0.3, 0.0)
	for s in [-1, 1]:
		_caixa(Vector3(0.1, alto + 0.1, fundo), Vector3(s * (meia + 0.05), Y_CHAO_FOSSO + alto / 2, Z_FUNDO - fundo / 2), escuro, true, false)
	_caixa(Vector3(LARGURA_BOCA + 0.2, 0.1, fundo), Vector3(0, Y_BOCA + 0.05, Z_FUNDO - fundo / 2), escuro, false, false)
	_caixa(Vector3(LARGURA_BOCA + 0.2, alto + 0.2, 0.1), Vector3(0, Y_CHAO_FOSSO + alto / 2, Z_FUNDO - fundo - 0.05), escuro, true, false)
	# dos lados da boca, a parede de borracha (até as paredes da caçapa)
	for s in [-1, 1]:
		var x0 := meia + 0.06
		var x1 := MEIA_LARGURA + CANALETA + 0.06
		_caixa(Vector3(x1 - x0, alto + 0.14, 0.12), Vector3(s * (x0 + x1) / 2.0, Y_CHAO_FOSSO + (alto + 0.14) / 2.0 - 0.07, Z_FUNDO - 0.02),
			borracha, false, false)
	# moldura amarela em volta da boca + filete de luz em cima (colidem
	# como são: os pinos param nelas; a bola passa no vão do meio)
	var moldura := _peca(Perfis.retangulo(LARGURA_BOCA + 0.26, 0.12, 0.05, Vector2(0, Y_BOCA + 0.06)), Z_FUNDO - 0.04, Z_FUNDO + 0.1, mat_friso)
	_corpo_forma(moldura.mesh.create_convex_shape(), Vector3.ZERO, 0.5, 0.2)
	for s in [-1, 1]:
		var poste := _peca(Perfis.retangulo(0.13, alto + 0.12, 0.05, Vector2(s * (meia + 0.065), Y_CHAO_FOSSO + (alto + 0.12) / 2.0 - 0.02)),
			Z_FUNDO - 0.04, Z_FUNDO + 0.1, mat_friso)
		_corpo_forma(poste.mesh.create_convex_shape(), Vector3.ZERO, 0.5, 0.2)
	mat_boca_luz = Materiais.cor_toon(Color("#FFFFFF"), 0.0, {"emissao": Color(0.6, 0.9, 1.0), "borda": 0.0})
	_caixa(Vector3(LARGURA_BOCA, 0.025, 0.02), Vector3(0, Y_BOCA + 0.005, Z_FUNDO + 0.105), mat_boca_luz, false, false)
	# cortina de tiras de borracha (uma MultiMesh: um desenho só)
	var tira := BoxMesh.new()
	var larg_tira := LARGURA_BOCA / N_TIRAS - 0.012
	tira.size = Vector3(larg_tira, alto - 0.03, 0.012)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tira
	mm.instance_count = N_TIRAS
	_tiras = MultiMeshInstance3D.new()
	_tiras.multimesh = mm
	_tiras.material_override = Materiais.cor_toon(Color("#151A28"), 0.0, {"borda": 0.25, "luz_minima": 0.3})
	_tiras.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tiras)
	_abertura_tiras.resize(N_TIRAS)
	_mexer_tiras(0.0)


## As tiras abrem (giram para trás, presas em cima) quando a bola passa.
func _mexer_tiras(delta: float) -> void:
	var mm := _tiras.multimesh
	var alto := Y_BOCA - Y_CHAO_FOSSO - 0.03
	var meia := LARGURA_BOCA / 2.0
	var pb := bola.global_position if bola != null and bola.visible else Vector3(100, 100, 100)
	var mexeu := delta <= 0.0
	for i in N_TIRAS:
		var x := -meia + LARGURA_BOCA * (float(i) + 0.5) / N_TIRAS
		var alvo := 0.0
		# abrem ANTES de a bola chegar (e depressa): ela nunca encosta nelas
		if absf(pb.z - Z_FUNDO) < 0.8 and absf(pb.x - x) < 0.3 and pb.y < Y_BOCA:
			alvo = 1.25
		var a := _abertura_tiras[i]
		var novo := move_toward(a, alvo, delta * (14.0 if alvo > a else 2.2))
		if novo != a or mexeu:
			_abertura_tiras[i] = novo
			# balancinho depois que a bola passa
			var t := Transform3D(Basis(Vector3.RIGHT, -novo), Vector3(x, Y_BOCA - 0.015, Z_FUNDO + 0.03))
			mm.set_instance_transform(i, t * Transform3D(Basis(), Vector3(0, -alto / 2.0, 0)))


## A bola que caiu na caçapa sai rolando de baixo da capota do retorno de
## bolas e encosta nas outras.
func retorno_bola(mat: Material) -> void:
	if _bola_volta == null:
		_bola_volta = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = Bola.RAIO
		sm.height = Bola.RAIO * 2.0
		sm.radial_segments = 24
		sm.rings = 12
		_bola_volta.mesh = sm
		_bola_volta.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_bola_volta)
	_bola_volta.material_override = mat
	_bola_volta.visible = true
	_bola_volta.position = RETORNO + Vector3(0, 0.69, 0.62)
	_bola_volta.rotation = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(_bola_volta, "position:z", RETORNO.z + 0.26, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_bola_volta, "rotation:x", -4.0, 0.55).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bola_volta, "position:z", RETORNO.z + 0.29, 0.08)
	tw.tween_property(_bola_volta, "position:z", RETORNO.z + 0.26, 0.1)


## Esconde a bola do retorno (ela vai para a mão do bichinho).
func guardar_retorno() -> void:
	if _bola_volta:
		_bola_volta.visible = false


## Leque de raios do arco: do meio da base (0, y0) até o contorno do arco
## (laterais retas até yc + meia-elipse), `setores` raios alternando cor.
## COLOR.r = qual das 2 cores; COLOR.g = 0 no centro, 1 na borda.
static func _leque_raios(r: float, y0: float, yc: float, alto: float, setores: int, z: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var borda := func(ang: float) -> Vector2:
		var d := Vector2(cos(ang), sin(ang))
		# laterais retas (x = ±r, até yc)
		if absf(d.x) > 1e-4:
			var t_lado := r / absf(d.x)
			var y_lado := y0 + t_lado * d.y
			if y_lado <= yc:
				return Vector2(t_lado * d.x, y_lado)
		# meia-elipse: (x/r)² + ((y - yc)/alto)² = 1, com x = t·dx, y = y0 + t·dy
		var a := (d.x * d.x) / (r * r) + (d.y * d.y) / (alto * alto)
		var b := 2.0 * (y0 - yc) * d.y / (alto * alto)
		var c := (y0 - yc) * (y0 - yc) / (alto * alto) - 1.0
		var t := (-b + sqrt(maxf(b * b - 4.0 * a * c, 0.0))) / (2.0 * a)
		return Vector2(t * d.x, y0 + t * d.y)
	var sub := 4
	var centro := Vector3(0, y0, z)
	for k in setores:
		var cor := Color(float(k % 2), 1.0, 0.0)
		var cor_c := Color(float(k % 2), 0.0, 0.0)
		for j in sub:
			var a0 := PI * (float(k) + float(j) / sub) / setores
			var a1 := PI * (float(k) + float(j + 1) / sub) / setores
			var p0: Vector2 = borda.call(a0)
			var p1: Vector2 = borda.call(a1)
			# frente virada para +Z (horário visto de +Z: centro, p1, p0)
			for v in [[centro, cor_c], [Vector3(p1.x, p1.y, z), cor], [Vector3(p0.x, p0.y, z), cor]]:
				st.set_color(v[1])
				st.set_normal(Vector3(0, 0, 1))
				st.add_vertex(v[0])
	return st.commit()


## Contorno do arco: base reta em y0, laterais até yc e meia-elipse
## (raio r na largura, `alto` na altura) por cima. Anti-horário.
static func _perfil_arco(r: float, y0: float, yc: float, alto: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	p.append(Vector2(r, y0))
	for i in 49:
		var a := PI * float(i) / 48.0
		p.append(Vector2(cos(a) * r, yc + sin(a) * alto))
	p.append(Vector2(-r, y0))
	return p


## Colunas dos dois lados do letreiro, com faixas de lâmpadas: fecham a
## frente do gabinete da máquina (cor do cenário).
func _colunas() -> void:
	var zc := Z_PINO1 + 0.75
	var pontos: Array[Vector3] = []
	mat_coluna = Materiais.cor_toon(Color("#1E62C8"), 0.004, {"borda": 0.35, "especular": 0.3})
	for s in [-1, 1]:
		var x: float = s * 1.93
		_peca(Perfis.retangulo(1.16, 3.0, 0.14, Vector2(x, 1.15)), zc - 0.07, zc + 0.07, mat_coluna, "coluna_%d" % s)
		_peca(Perfis.retangulo(1.26, 0.12, 0.05, Vector2(x, 2.7)), zc - 0.09, zc + 0.09, mat_friso)
		for i in 23:
			pontos.append(Vector3(x - s * 0.5, 0.2 + i * 0.1, zc + 0.08))
			pontos.append(Vector3(x + s * 0.5, 0.2 + i * 0.1, zc + 0.08))
	add_child(lampadas_em(pontos, 50))


## O SÍMBOLO DA LAZER & SPORT EM TODO CENÁRIO, sutil, flutuando ao lado
## da pista (sempre no mesmo lugar, boiando de leve), cada um do jeito do
## cenário: o balãozinho (Parque), o planetinha com anel (Espaço), a bolha
## (Fundo do Mar) e o pterossauro segurando a plaquinha (Selva dos Dinos).
func _marcas_dos_cenarios() -> void:
	_marcas["parque"] = _balao_marca()
	_marcas["espaco"] = _planeta_marca()
	_marcas["mar"] = _bolha_marca()
	_marcas["dinos"] = _ptero_marca()
	for k in _marcas:
		(_marcas[k] as Node3D).visible = false
	balao = _marcas["parque"]


func _novo_simbolo(nome: String, escala: float) -> Node3D:
	var n := Node3D.new()
	n.name = nome
	n.position = BALAO_POS
	n.scale = Vector3.ONE * escala
	add_child(n)
	return n


## Material com a logo (sem fundo) estampada na frente da peça (+Z).
## largura: da logo, nas medidas da própria malha; esticar_y: a escala Y
## da peça (para a logo não sair esticada).
func _mat_logo(tinta: Color, largura: float, centro := Vector2.ZERO, esticar_y := 1.0, extra := {}) -> ShaderMaterial:
	var p := {"usa_rosto": true, "rosto": load("res://ui/marca/lazer_sport.png"), "rosto_grade": Vector2(1, 1),
		"rosto_celula": Vector2.ZERO, "rosto_centro": centro,
		"rosto_tamanho": Vector2(largura, largura * 1698.0 / 2560.0 / esticar_y), "borda": 0.4, "faixa": 0.12, "luz_minima": 0.38,
		"especular": 0.3, "tamanho_especular": 0.985, "tinta": tinta}
	p.merge(extra, true)
	return Materiais.toon(true, 0.004, p)


func _esfera(raio := 1.0, gomos := 32) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = raio
	sm.height = raio * 2.0
	sm.radial_segments = gomos
	sm.rings = gomos / 2
	return sm


func _peca_simbolo(pai: Node3D, malha: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = malha
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pai.add_child(mi)
	return mi


## Parque: o balãozinho com a logo (~60 cm).
func _balao_marca() -> Node3D:
	var b := _novo_simbolo("balao_marca", 0.3)
	mat_balao = _mat_logo(Color("#E8384F"), 1.32, Vector2(0.0, 0.06), 1.12)
	var corpo := _peca_simbolo(b, _esfera(), mat_balao)
	corpo.scale = Vector3(1.0, 1.12, 1.0)
	# nó e cordão
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.09
	cm.height = 0.14
	cm.radial_segments = 12
	_peca_simbolo(b, cm, mat_balao, Vector3(0, -1.17, 0))
	var cc := CylinderMesh.new()
	cc.top_radius = 0.012
	cc.bottom_radius = 0.012
	cc.height = 4.2
	cc.radial_segments = 6
	_peca_simbolo(b, cc, Materiais.cor_toon(Color("#FFFFFF"), 0.0, {"borda": 0.0, "luz_minima": 0.6}), Vector3(0, -1.24 - 2.1, 0))
	return b


## Espaço: um planetinha roxo com anel amarelo e a logo na frente.
func _planeta_marca() -> Node3D:
	var b := _novo_simbolo("planeta_marca", 0.27)
	_peca_simbolo(b, _esfera(), _mat_logo(Color("#7B61FF"), 1.3, Vector2.ZERO, 1.0,
		{"borda": 0.7, "cor_borda": Color("#9FE8FF")}))
	# o anel passa por baixo da logo (inclinado para a frente)
	var anel := TorusMesh.new()
	anel.inner_radius = 1.32
	anel.outer_radius = 1.62
	anel.rings = 48
	anel.ring_segments = 8
	var a := _peca_simbolo(b, anel, Materiais.cor_toon(Color("#FFD43B"), 0.003, {"borda": 0.5, "luz_minima": 0.5}))
	a.rotation_degrees = Vector3(32, 0, -12)
	a.scale = Vector3(1.0, 0.35, 1.0)
	return b


## Fundo do Mar: uma bolha com a logo dentro e bolhinhas subindo.
func _bolha_marca() -> Node3D:
	var b := _novo_simbolo("bolha_marca", 0.3)
	_peca_simbolo(b, _esfera(), _mat_logo(Color("#C9F4FF"), 1.25, Vector2.ZERO, 1.0,
		{"borda": 1.3, "cor_borda": Color(1, 1, 1), "luz_minima": 0.75, "especular": 0.45, "tamanho_especular": 0.985}))
	var mb := Materiais.cor_toon(Color("#DDF8FF"), 0.0, {"borda": 1.4, "cor_borda": Color(1, 1, 1), "luz_minima": 0.8})
	for i in 4:
		var bi := _peca_simbolo(b, _esfera(1.0, 12), mb)
		bi.scale = Vector3.ONE * (0.12 + 0.05 * (i % 2))
		_bolhinhas.append(bi)
	return b


## Selva dos Dinos: um pterossauro batendo asas, segurando a plaquinha de
## madeira com a logo.
func _ptero_marca() -> Node3D:
	var b := _novo_simbolo("ptero_marca", 1.0)
	var moldura := BoxMesh.new()
	moldura.size = Vector3(0.74, 0.52, 0.05)
	_peca_simbolo(b, moldura, Materiais.cor_toon(Color("#7A4A22"), 0.003, {"borda": 0.25}), Vector3(0, 0, -0.012))
	var placa := BoxMesh.new()
	placa.size = Vector3(0.68, 0.46, 0.05)
	_peca_simbolo(b, placa, _mat_logo(Color("#FFE9C2"), 0.62, Vector2.ZERO, 1.0, {"borda": 0.2, "especular": 0.0}))
	# cordinhas até os pés do pterossauro
	var mc := Materiais.cor_toon(Color("#5A3A1A"), 0.0, {"borda": 0.0, "luz_minima": 0.5})
	for lado in [-1.0, 1.0]:
		var c := CylinderMesh.new()
		c.top_radius = 0.006
		c.bottom_radius = 0.006
		c.height = 0.36
		c.radial_segments = 5
		var mi := _peca_simbolo(b, c, mc, Vector3(lado * 0.17, 0.4, 0.0))
		mi.rotation.z = lado * 0.45
	var pt := _peca_simbolo(b, load("res://modelos/cenario/ptero.res"), _mat_ptero(), Vector3(0, 0.66, 0.02))
	pt.scale = Vector3.ONE * 0.62
	pt.name = "ptero"
	return b


func _mat_ptero() -> Material:
	# o mesmo toon dos pterossauros do cenário (contorno fino)
	return Materiais.toon(false, 0.003, {"borda": 0.3})


func _mostrar_marca(nome: String) -> void:
	for k in _marcas:
		(_marcas[k] as Node3D).visible = k == nome
	balao = _marcas.get(nome, _marcas["parque"])


# ================================================================ área dos jogadores
## Atrás de quem joga: tapete, uma mureta nas cores do cenário (por cima
## dela aparece o cenário — o parque, o fundo do mar...), o letreiro STRIKE
## KIDS em dois postes, sofás e o retorno de bolas. Quando a câmera vira
## para o mascote, o fundo é o próprio cenário, sem chão infinito.
func _area_dos_jogadores() -> void:
	var z_parede := 7.7
	var marinho := Materiais.cor_toon(Color("#123A7A"), 0.004, {"borda": 0.3, "especular": 0.2})
	var azul := Materiais.cor_toon(Color("#1E62C8"), 0.0, {"borda": 0.3})
	var vermelho := Materiais.cor_toon(Color("#E8384F"), 0.004, {"borda": 0.3, "especular": 0.3})
	var tapete := Materiais.cor_toon(Color("#1B3E86"), 0.0, {"borda": 0.15})
	# tapete entre a área de aproximação e a mureta (+ friso amarelo)
	_caixa(Vector3(9.6, 0.06, z_parede - 6.3), Vector3(0, -0.03, (6.3 + z_parede) / 2), tapete, false, false)
	_caixa(Vector3(6.6, 0.065, 0.07), Vector3(0, -0.03, 6.33), mat_friso, false, false)
	# mureta (cor do cenário) com friso amarelo em cima
	_peca(Perfis.retangulo(9.6, 1.1, 0.12, Vector2(0, 0.55)), z_parede, z_parede + 0.3, mat_gabinete, "mureta")
	_peca(Perfis.retangulo(9.7, 0.1, 0.05, Vector2(0, 1.12)), z_parede - 0.03, z_parede + 0.33, mat_friso)
	# letreiro STRIKE KIDS em dois postes, virado para a pista, com lâmpadas
	for s in [-1, 1]:
		_peca(Perfis.retangulo(0.16, 3.0, 0.07, Vector2(s * 1.9, 1.5)), z_parede - 0.2, z_parede - 0.04, mat_coluna)
	_peca(Perfis.retangulo(4.0, 1.75, 0.16, Vector2(0, 2.55)), z_parede - 0.18, z_parede - 0.06, mat_placa, "placa_fundo")
	var logo_tex := Materiais.textura("logo")
	var pontos: Array[Vector3] = []
	if logo_tex != null:
		var lq := QuadMesh.new()
		var lw := 3.0
		lq.size = Vector2(lw, lw * float(logo_tex.get_height()) / float(logo_tex.get_width()))
		var ml := StandardMaterial3D.new()
		ml.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ml.albedo_texture = logo_tex
		ml.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		ml.alpha_scissor_threshold = 0.4
		ml.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var logo := MeshInstance3D.new()
		logo.mesh = lq
		logo.material_override = ml
		logo.rotation_degrees.y = 180
		logo.position = Vector3(0, 2.55, z_parede - 0.2)
		logo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(logo)
		for i in 30:
			var x := -1.85 + i * (3.7 / 29.0)
			pontos.append(Vector3(x, 3.35, z_parede - 0.21))
			pontos.append(Vector3(x, 1.75, z_parede - 0.21))
	add_child(lampadas_em(pontos, 200))
	# sofás vermelhos encostados na mureta
	for s in [-1, 1]:
		var sofa := Node3D.new()
		sofa.position = Vector3(s * 3.4, 0, z_parede - 0.42)
		sofa.rotation_degrees.y = 90
		add_child(sofa)
		for parte in [[Perfis.retangulo(0.66, 0.42, 0.12, Vector2(0.0, 0.21)), 0.0],
				[Perfis.retangulo(0.2, 0.86, 0.09, Vector2(-0.27, 0.43)), 0.0],
				[Perfis.retangulo(0.66, 0.6, 0.1, Vector2(0.0, 0.3)), 1.0]]:
			var mi := MeshInstance3D.new()
			if parte[1] == 0.0:
				mi.mesh = Perfis.extrudar(parte[0], -1.1, 1.1)
			else:
				mi.mesh = Perfis.extrudar(parte[0], -0.12, 0.12)
			mi.material_override = vermelho if parte[1] == 0.0 else marinho
			sofa.add_child(mi)
			if parte[1] == 1.0:
				var outro := mi.duplicate() as MeshInstance3D
				mi.position.z = -1.2
				outro.position.z = 1.2
				sofa.add_child(outro)
	# retorno de bolas (como num boliche de verdade), do lado direito
	var ret := Node3D.new()
	ret.position = RETORNO
	add_child(ret)
	var corpo := MeshInstance3D.new()
	corpo.mesh = Perfis.extrudar(Perfis.retangulo(0.56, 0.5, 0.1, Vector2(0, 0.25)), -0.8, 0.8)
	corpo.material_override = marinho
	ret.add_child(corpo)
	var capo := MeshInstance3D.new()
	capo.mesh = Perfis.extrudar(Perfis.retangulo(0.6, 0.5, 0.24, Vector2(0, 0.62)), 0.25, 0.8)
	capo.material_override = azul
	ret.add_child(capo)
	var trilho := MeshInstance3D.new()
	trilho.mesh = Perfis.extrudar(Perfis.retangulo(0.5, 0.06, 0.03, Vector2(0, 0.53)), -0.78, 0.3)
	trilho.material_override = mat_friso
	ret.add_child(trilho)
	var cores := [Color("#169BD5"), Color("#FF7A21"), Color("#2DBE4E")]
	for i in 3:
		var b := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.13
		sm.height = 0.26
		sm.radial_segments = 24
		sm.rings = 12
		b.mesh = sm
		b.material_override = Materiais.cor_toon(cores[i], 0.003, {"borda": 0.4, "especular": 0.8})
		b.position = Vector3(0, 0.69, -0.62 + i * 0.29)
		ret.add_child(b)


# ================================================================ pódios
func _montar_podios() -> void:
	for i in 2:
		var g := Node3D.new()
		g.visible = false
		g.name = "podio_%d" % i
		add_child(g)
		var cor := Color("#169BD5") if i == 0 else Color("#FF7A21")
		var base := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.4
		cm.bottom_radius = 0.45
		cm.height = 0.14
		cm.radial_segments = 48
		cm.rings = 1
		base.mesh = cm
		base.position.y = 0.07
		base.material_override = Materiais.cor_toon(cor, 0.004, {"borda": 0.35})
		g.add_child(base)
		var tampa := MeshInstance3D.new()
		var ct := CylinderMesh.new()
		ct.top_radius = 0.37
		ct.bottom_radius = 0.37
		ct.height = 0.012
		ct.radial_segments = 48
		ct.rings = 1
		tampa.mesh = ct
		tampa.position.y = 0.146
		tampa.material_override = Materiais.cor_toon(Color("#F4F8FF"), 0.0, {"borda": 0.2})
		g.add_child(tampa)
		# anel de luz em volta da tampa (acende no escolhido)
		var aro := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.37
		tm.outer_radius = 0.405
		tm.rings = 64
		tm.ring_segments = 10
		aro.mesh = tm
		aro.position.y = 0.142
		var ma := Materiais.cor_toon(Color("#FFD43B"), 0.0, {"borda": 0.0, "emissao": Color(0, 0, 0)})
		aro.material_override = ma
		aro.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(aro)
		_podios.append(g)
		_mats_podio.append(ma)


## Liga/desliga os pódios (posições no chão) e acende o do escolhido.
func podios(ligar: bool, posicoes: Array = [], destaque := -1) -> void:
	for i in _podios.size():
		var g := _podios[i]
		var ia := not g.visible
		g.visible = ligar and i < posicoes.size()
		if g.visible:
			g.position = posicoes[i]
			if ia:
				g.scale = Vector3(1, 0.2, 1)
				create_tween().tween_property(g, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_podio_destaque = destaque


## Lâmpada: bolinha de 64 triângulos (são centenas delas na tela).
static var _lampada: SphereMesh


static func _malha_lampada() -> SphereMesh:
	if _lampada == null:
		_lampada = SphereMesh.new()
		_lampada.radius = 0.07
		_lampada.height = 0.14
		_lampada.radial_segments = 8
		_lampada.rings = 4
	return _lampada


## Fileira de lâmpadas (MultiMesh) que piscam com o material comum.
func lampadas_em(pontos: Array[Vector3], fase0 := 0) -> MultiMeshInstance3D:
	var cores := [Color("#FFE14D"), Color("#FF9F2E"), Color("#4FD8FF"), Color("#8DFF6A")]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _malha_lampada()
	mm.instance_count = pontos.size()
	for i in pontos.size():
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.75), pontos[i]))
		mm.set_instance_color(i, cores[i % cores.size()])
		mm.set_instance_custom_data(i, Color(float(i + fase0), 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat_lampadas
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


# ================================================================ decoração
func _objeto(nome: String, pos: Vector3, rot_y := 0.0, escala := 1.0, contorno := 0.0, pai: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var caminho := "res://modelos/cenario/%s.res" % nome
	if not ResourceLoader.exists(caminho):
		push_warning("modelo que falta: " + caminho)
		return mi
	mi.mesh = load(caminho)
	mi.material_override = Materiais.toon(false, contorno, {"borda": 0.3})
	mi.position = pos
	mi.rotation.y = rot_y
	mi.scale = Vector3.ONE * escala
	# só os objetos perto da pista fazem sombra (economiza a placa de vídeo)
	if absf(pos.x) > 4.5 or pos.z < -18.0:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(pai if pai != null else self).add_child(mi)
	return mi


## Mesma fórmula do tools/modelos/modelos.py (gerar_terreno), para apoiar
## os objetos no chão.
func _altura_terreno(x: float, z: float) -> float:
	var morros := [[-9, -20, 6, 2.2], [10, -26, 7, 2.6], [-14, -42, 9, 3.4], [15, -48, 10, 3.8], [0, -64, 16, 5.0],
		[-20, -10, 6, 1.8], [21, -8, 7, 2.2], [-26, -30, 9, 4.0], [27, -34, 10, 4.5], [-6, -52, 6, 2.0], [6, -58, 7, 2.4]]
	var h := 0.0
	for m in morros:
		h += m[3] * exp(-((x - m[0]) * (x - m[0]) + (z - m[1]) * (z - m[1])) / (2.0 * m[2] * m[2]))
	var p: float = clamp((abs(x) - 3.2) / 4.0, 0.0, 1.0)
	p = p * p * (3.0 - 2.0 * p)
	return h * p + 0.06 * sin(x * 0.7) * sin(z * 0.55) * p - 0.02 - 0.22 * (1.0 - p)


# ================================================================ animação
func acender_pista(ligar: bool) -> void:
	_luz_alvo = 1.0 if ligar else 0.0


func _process(delta: float) -> void:
	if mat_pista == null:
		return
	_t = fposmod(_t + delta, 3600.0)
	_luz = move_toward(_luz, _luz_alvo, delta * 2.5)
	mat_pista.set_shader_parameter("luz", _luz)
	mat_pista.set_shader_parameter("fase", fposmod(_t * 2.2, 1.0))
	mat_pista.set_shader_parameter("fase_lenta", fposmod(_t * 0.75, 1.0))
	mat_pista.set_shader_parameter("pulso", 0.5 + 0.5 * sin(_t * 3.1))
	if mat_piso:
		mat_piso.set_shader_parameter("pulso", 0.5 + 0.5 * sin(_t * 3.1))
	mat_pista.set_shader_parameter("bola_z", bola_z)
	mat_lampadas.set_shader_parameter("fase", fposmod(_t * 0.9, 100.0))
	# o símbolo do cenário flutua — sobe e desce, vai e volta e balança
	if balao.visible:
		_mexer_marca()
	mat_fundo.set_shader_parameter("fase", fposmod(_t * 0.4, 100.0))
	mat_portal.set_shader_parameter("pulso", sin(_t * 2.2))
	_mexer_tiras(delta)
	for i in _mats_podio.size():
		var on := 0.0
		if i == _podio_destaque:
			on = 0.75 + 0.25 * sin(_t * 6.0)
		_mats_podio[i].set_shader_parameter("emissao", Color(1.0, 0.75, 0.15) * on * 1.6)


func _mexer_marca() -> void:
	balao.position = BALAO_POS + Vector3(sin(_t * 0.31) * 0.18, sin(_t * 0.8) * 0.14, sin(_t * 0.23) * 0.1)
	match tema:
		"espaco":
			balao.rotation = Vector3(sin(_t * 0.4) * 0.06, sin(_t * 0.3) * 0.35, sin(_t * 0.5) * 0.05)
		"mar":
			var pulso := sin(_t * 2.0)
			balao.rotation = Vector3(0, sin(_t * 0.35) * 0.25, sin(_t * 0.6) * 0.06)
			balao.scale = Vector3(1.0 + pulso * 0.03, 1.0 - pulso * 0.03, 1.0 + pulso * 0.03) * 0.3
			for i in _bolhinhas.size():
				# sobem em volta da bolha e recomeçam embaixo
				var f := fposmod(_t * 0.22 + i * 0.25, 1.0)
				var a := i * 1.9 + _t * 0.4
				_bolhinhas[i].position = Vector3(cos(a) * 1.25, -1.0 + f * 3.4, sin(a) * 0.5 + 0.3)
				_bolhinhas[i].visible = f < 0.92
		"dinos":
			balao.rotation = Vector3(sin(_t * 0.7) * 0.05, sin(_t * 0.4) * 0.22, sin(_t * 0.9) * 0.06)
			var pt := balao.get_node("ptero") as Node3D
			# bate asas: o corpo sobe e desce um tiquinho, inclinando
			pt.position.y = 0.66 + sin(_t * 5.0) * 0.025
			pt.rotation.x = sin(_t * 5.0) * 0.08
		_:
			balao.rotation = Vector3(sin(_t * 0.5) * 0.05, sin(_t * 0.45) * 0.3, sin(_t * 0.6) * 0.08)


## Modo das lâmpadas: 0 corrida, 1 piscando todas (strike!), 2 alternado.
func lampadas(modo: int) -> void:
	mat_lampadas.set_shader_parameter("modo", modo)
