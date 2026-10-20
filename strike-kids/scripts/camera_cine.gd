class_name CameraCine
extends Camera3D

## CÂMERA DE CINEMA: planos com transição suave, seguir a bola, tremida,
## "soco" de zoom e enquadramento RESPONSIVO — cada plano diz quanto quer
## ver na vertical e na horizontal, e a câmera escolhe a abertura (FOV)
## que garante as duas coisas em qualquer proporção de tela (em pé ou
## deitada).

var _pos := Vector3(0, 2, 6)
var _alvo := Vector3(0, 0, -8)
var _fov_v := 50.0
var _fov_h := 40.0
var _pos_dest := Vector3(0, 2, 6)
var _alvo_dest := Vector3(0, 0, -8)
var _fov_v_dest := 50.0
var _fov_h_dest := 40.0
var _rapidez := 3.0
var _seguir: Node3D = null
var _desl_pos := Vector3.ZERO
var _desl_alvo := Vector3.ZERO
var _tremor := 0.0
var _tremor_dur := 0.0
var _soco := 0.0
var _orbita := false
var _orbita_centro := Vector3.ZERO
var _orbita_raio := 6.0
var _orbita_altura := 2.0
var _orbita_ang := 0.0
var _orbita_vel := 0.15
var _balanco := 0.0           # > 0: em vez de dar a volta, balança de um lado ao outro
var _balanco_base := 0.0
var _orbita_t := 0.0
var _trilho := []          # [[pos, alvo, tempo]...] (movimento de câmera em trilho)
var _trilho_t := 0.0


func _ready() -> void:
	near = 0.05
	far = 160.0
	keep_aspect = Camera3D.KEEP_HEIGHT


## Corte seco para um plano.
func corte(pos: Vector3, alvo: Vector3, fov_v := 50.0, fov_h := 34.0) -> void:
	_parar_modos()
	_pos = pos
	_alvo = alvo
	_pos_dest = pos
	_alvo_dest = alvo
	_fov_v = fov_v
	_fov_h = fov_h
	_fov_v_dest = fov_v
	_fov_h_dest = fov_h
	_aplicar(0.0)


## Vai suavemente até o plano. rapidez: maior = chega mais rápido.
func ir(pos: Vector3, alvo: Vector3, fov_v := 50.0, fov_h := 34.0, rapidez := 3.0) -> void:
	_parar_modos()
	_pos_dest = pos
	_alvo_dest = alvo
	_fov_v_dest = fov_v
	_fov_h_dest = fov_h
	_rapidez = rapidez


## Segue um objeto (bola, personagem) mantendo o deslocamento.
func seguir(no: Node3D, desl_pos: Vector3, desl_alvo: Vector3, fov_v := 50.0, fov_h := 34.0, rapidez := 5.0) -> void:
	_orbita = false
	_trilho.clear()
	_seguir = no
	_desl_pos = desl_pos
	_desl_alvo = desl_alvo
	_fov_v_dest = fov_v
	_fov_h_dest = fov_h
	_rapidez = rapidez


func orbitar(centro: Vector3, raio: float, altura: float, vel := 0.15, fov_v := 45.0, fov_h := 40.0, balanco := 0.0) -> void:
	_parar_modos()
	_orbita = true
	_balanco = balanco
	_orbita_t = 0.0
	_balanco_base = 0.0
	_orbita_centro = centro
	_orbita_raio = raio
	_orbita_altura = altura
	_orbita_vel = vel
	_orbita_ang = atan2(_pos.x - centro.x, _pos.z - centro.z)
	_fov_v_dest = fov_v
	_fov_h_dest = fov_h
	_rapidez = 1.5


## Movimento em trilho: lista de [pos, alvo, segundos] (replay, abertura).
func trilho(pontos: Array, fov_v := 45.0, fov_h := 34.0) -> void:
	_parar_modos()
	_trilho = pontos
	_trilho_t = 0.0
	_fov_v_dest = fov_v
	_fov_h_dest = fov_h
	_fov_v = fov_v
	_fov_h = fov_h


func tremer(forca: float, dur := 0.35) -> void:
	_tremor = max(_tremor, forca)
	_tremor_dur = max(_tremor_dur, dur)


## "Soco" de zoom (fecha a abertura de repente e volta).
func soco(graus: float) -> void:
	_soco = graus


func _parar_modos() -> void:
	_seguir = null
	_orbita = false
	_trilho.clear()


func _process(delta: float) -> void:
	_aplicar(delta)


func _aplicar(delta: float) -> void:
	if not _trilho.is_empty():
		_trilho_t += delta
		var acc := 0.0
		var i := 0
		while i < _trilho.size() - 1 and _trilho_t > acc + float(_trilho[i + 1][2]):
			acc += float(_trilho[i + 1][2])
			i += 1
		if i >= _trilho.size() - 1:
			_pos = _trilho[-1][0]
			_alvo = _trilho[-1][1]
		else:
			var u: float = clamp((_trilho_t - acc) / max(float(_trilho[i + 1][2]), 0.001), 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			_pos = (_trilho[i][0] as Vector3).lerp(_trilho[i + 1][0], u)
			_alvo = (_trilho[i][1] as Vector3).lerp(_trilho[i + 1][1], u)
		_pos_dest = _pos
		_alvo_dest = _alvo
	elif _orbita:
		if _balanco > 0.0:
			_orbita_t += delta
			_orbita_ang = _balanco_base + sin(_orbita_t * _orbita_vel) * _balanco
		else:
			_orbita_ang += _orbita_vel * delta
		_pos_dest = _orbita_centro + Vector3(sin(_orbita_ang) * _orbita_raio, _orbita_altura, cos(_orbita_ang) * _orbita_raio)
		_alvo_dest = _orbita_centro
	elif _seguir != null and is_instance_valid(_seguir):
		# a bola aparece interpolada entre os passos da física: a câmera
		# segue onde ela APARECE (senão a bola tremeria na tela)
		var g := Mundo.na_tela(_seguir).origin
		_pos_dest = g + _desl_pos
		_alvo_dest = g + _desl_alvo
	if delta > 0.0 and _trilho.is_empty():
		var k := 1.0 - exp(-_rapidez * delta)
		_pos = _pos.lerp(_pos_dest, k)
		_alvo = _alvo.lerp(_alvo_dest, k)
	var kf := 1.0 - exp(-3.0 * delta) if delta > 0.0 else 1.0
	_fov_v = lerp(_fov_v, _fov_v_dest, kf)
	_fov_h = lerp(_fov_h, _fov_h_dest, kf)
	_soco = move_toward(_soco, 0.0, delta * 30.0)
	var tremor := Vector3.ZERO
	if _tremor_dur > 0.0:
		_tremor_dur -= delta
		tremor = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _tremor * clamp(_tremor_dur * 3.0, 0.0, 1.0)
		if _tremor_dur <= 0.0:
			_tremor = 0.0
	var p := _pos + tremor
	if p.distance_to(_alvo) > 0.001:
		look_at_from_position(p, _alvo + tremor * 0.5, Vector3.UP)
	fov = _fov_responsivo() - _soco


## A abertura vertical que mostra pelo menos _fov_v na vertical E _fov_h
## na horizontal, seja qual for a proporção da tela.
func _fov_responsivo() -> float:
	var vp := get_viewport()
	var tam := Vector2(vp.size) if vp else Vector2(1080, 1920)
	var aspecto: float = tam.x / maxf(tam.y, 1.0)
	var v_pela_h := rad_to_deg(2.0 * atan(tan(deg_to_rad(_fov_h) * 0.5) / maxf(aspecto, 0.01)))
	return clamp(max(_fov_v, v_pela_h), 10.0, 110.0)


func alvo_atual() -> Vector3:
	return _alvo
