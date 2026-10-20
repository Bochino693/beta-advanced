extends Node

## SONS E MÚSICAS.
##
## Efeitos: res://sons/<nome>.wav (vários tocam juntos, pelo "pool").
## Músicas: res://sons/<nome>.ogg, em loop, com troca suave.
## Vozes opcionais: se existir res://sons/voz/<nome>.wav (ex.: strike.wav,
## spare.wav, vez_bob.wav), ela toca junto do efeito — basta gravar e
## colocar o arquivo na pasta, sem mexer no código.

const PASTA := "res://sons/"
const VARIACOES := {"pino_batida": 3}
const TAMANHO_POOL := 14

var _cache := {}
var _pool: Array[AudioStreamPlayer] = []
var _musica_a: AudioStreamPlayer
var _musica_b: AudioStreamPlayer
var _musica_atual := ""
var _rolando: AudioStreamPlayer
var _tween_musica: Tween
## Na demo o som pode ficar desligado (ajuste do operador).
var mudo_demo := false
## Gravação do vídeo de divulgação: anota cada som com o número do quadro.
var registrar := false
var registro: Array = []
var _rolando_reg := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in TAMANHO_POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_musica_a = AudioStreamPlayer.new()
	_musica_b = AudioStreamPlayer.new()
	add_child(_musica_a)
	add_child(_musica_b)
	_rolando = AudioStreamPlayer.new()
	add_child(_rolando)
	_pre_carregar()


## Todos os sons começam a carregar já na abertura, em segundo plano: o
## primeiro "STRIKE!" não espera o disco (nada de engasgo).
var _pendentes := {}


func _pre_carregar() -> void:
	for f in ResourceLoader.list_directory(PASTA):
		if f.get_extension() in ["wav", "ogg"]:
			var caminho: String = PASTA + f
			_pendentes[f.get_basename()] = caminho
			ResourceLoader.load_threaded_request(caminho)


func _carregar(nome: String) -> AudioStream:
	if _cache.has(nome):
		return _cache[nome]
	if _pendentes.has(nome):
		var a := ResourceLoader.load_threaded_get(_pendentes[nome]) as AudioStream
		_pendentes.erase(nome)
		if a != null:
			_cache[nome] = a
			return a
	var s: AudioStream = null
	for ext in [".wav", ".ogg"]:
		var caminho: String = PASTA + nome + ext
		if ResourceLoader.exists(caminho):
			s = load(caminho)
			break
	_cache[nome] = s
	return s


func _vol_efeitos() -> float:
	var v := float(Ajustes.valor("som", "efeitos"))
	if mudo_demo:
		v = 0.0
	return v


func _db(fator: float) -> float:
	return linear_to_db(max(fator, 0.0001))


## Toca um efeito. volume: 0..1 (multiplica o volume do operador).
func tocar(nome: String, volume := 1.0, tom := 1.0) -> void:
	var base := nome
	if VARIACOES.has(nome):
		nome = "%s_%d" % [nome, randi_range(1, VARIACOES[nome])]
	if registrar:
		registro.append([Engine.get_process_frames(), nome, volume, tom])
	var s := _carregar(nome)
	if s == null:
		return
	var vol := _vol_efeitos() * volume
	if vol <= 0.001:
		return
	var p := _livre()
	p.stream = s
	p.volume_db = _db(vol)
	p.pitch_scale = tom
	p.play()
	var voz := _carregar("voz/" + base)
	if voz != null:
		var pv := _livre()
		pv.stream = voz
		pv.volume_db = _db(vol)
		pv.pitch_scale = 1.0
		pv.play()


func _livre() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	# todos ocupados: reaproveita o que está tocando há mais tempo
	var mais_velho := _pool[0]
	for p in _pool:
		if p.get_playback_position() > mais_velho.get_playback_position():
			mais_velho = p
	return mais_velho


# ---------------------------------------------------------------- música
func musica(nome: String, troca := 0.8) -> void:
	if nome == _musica_atual:
		return
	_musica_atual = nome
	if registrar:
		registro.append([Engine.get_process_frames(), "musica:" + nome, 1.0, 1.0])
	var s := _carregar(nome)
	var vol_alvo := _db(float(Ajustes.valor("som", "musica")) * (0.0 if mudo_demo else 1.0) * 0.75)
	if _tween_musica:
		_tween_musica.kill()
	_tween_musica = create_tween().set_parallel(true)
	_tween_musica.tween_interval(0.01)
	var sai := _musica_a if _musica_a.playing else null
	var entra := _musica_b if sai == _musica_a else _musica_a
	if sai == null and _musica_b.playing:
		sai = _musica_b
		entra = _musica_a
	if sai != null:
		_tween_musica.tween_property(sai, "volume_db", -60.0, troca)
		_tween_musica.chain().tween_callback(sai.stop)
	if s != null:
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		entra.stream = s
		entra.volume_db = -60.0
		entra.play()
		_tween_musica.tween_property(entra, "volume_db", vol_alvo, troca)


func parar_musica(troca := 0.6) -> void:
	musica("", troca)


## Reaplica o volume (depois de mudar ajustes ou entrar/sair da demo).
func atualizar_volume() -> void:
	var vol := _db(float(Ajustes.valor("som", "musica")) * (0.0 if mudo_demo else 1.0) * 0.75)
	for p in [_musica_a, _musica_b]:
		if p.playing:
			p.volume_db = vol


# ---------------------------------------------------------------- bola rolando
func rolando(ligar: bool, velocidade := 0.0) -> void:
	if ligar:
		if _rolando.stream == null:
			var s := _carregar("bola_rolando")
			if s is AudioStreamWAV:
				(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
				(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).get_length() * (s as AudioStreamWAV).mix_rate)
			_rolando.stream = s
		var f: float = clamp(velocidade / 7.0, 0.0, 1.2)
		_rolando.volume_db = _db(_vol_efeitos() * f * 0.9)
		_rolando.pitch_scale = 0.75 + 0.35 * f
		if registrar and not _rolando_reg:
			_rolando_reg = true
			registro.append([Engine.get_process_frames(), "rolando:on", 0.8, 1.0])
		if not _rolando.playing and _rolando.stream != null:
			_rolando.play()
	else:
		if registrar and _rolando_reg:
			_rolando_reg = false
			registro.append([Engine.get_process_frames(), "rolando:off", 0.0, 1.0])
		if _rolando.playing:
			_rolando.stop()
