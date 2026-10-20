class_name Tarefas

## TRABALHO EM SEGUNDO PLANO (gravar no disco, ler as fotos, listar o USB):
## roda numa linha de trabalho separada, sem parar o jogo. Ao fechar, o jogo
## espera o que ainda estiver rodando — senão o trabalho continuaria mexendo
## em coisas que o motor já apagou e o jogo cairia ao sair.

static var _ids: Array[int] = []


static func rodar(f: Callable) -> void:
	_recolher()
	_ids.append(WorkerThreadPool.add_task(f))


## Libera as que já terminaram (o motor pede que cada uma seja esperada uma
## vez; esperar uma que já terminou não para nada).
static func _recolher() -> void:
	var i := 0
	while i < _ids.size():
		if WorkerThreadPool.is_task_completed(_ids[i]):
			WorkerThreadPool.wait_for_task_completion(_ids[i])
			_ids.remove_at(i)
		else:
			i += 1


## Fechando o jogo: espera tudo terminar.
static func esperar_todas() -> void:
	for id in _ids:
		WorkerThreadPool.wait_for_task_completion(id)
	_ids.clear()
