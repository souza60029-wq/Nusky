extends Node

# Acha os personagens nas duas pastas e guarda a lista pronta para o menu e o editor.
# res://personagens/ é o conteúdo do jogo. user://personagens/ é o que foi criado ou editado no app.
# Se o mesmo id existir nas duas, vale o do app: é a versão que o jogador editou.

const Formato = preload("res://engine/formato/Formato.gd")

const PASTAS := [
	{"caminho": "res://personagens/", "origem": "jogo"},
	{"caminho": "user://personagens/", "origem": "usuario"},
]

# Os dois bonecos de treino nunca podem ser apagados.
const PROTEGIDOS := ["boneco_treino_1", "boneco_treino_2"]
# Personagens que vêm dentro do jogo (res://) não podem ser removidos do arquivo; "apagar" esconde.
const ARQ_OCULTOS := "user://personagens_ocultos.json"

signal mudou

var _lista: Array = []
var _por_id: Dictionary = {}
var _ocultos: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://personagens")
	recarregar()


func recarregar() -> void:
	_lista.clear()
	_por_id.clear()
	for info in PASTAS:
		_varrer(info["caminho"], info["origem"])
	_carregar_ocultos()
	for id in _ocultos.duplicate():
		if _por_id.has(id) and str(_por_id[id]["origem"]) == "jogo" and not eh_protegido(str(id)):
			_remover(str(id))
	_lista.sort_custom(func(a, b): return a["nome"] < b["nome"])
	mudou.emit()


func eh_protegido(id: String) -> bool:
	return PROTEGIDOS.has(id)


func _carregar_ocultos() -> void:
	_ocultos = []
	if FileAccess.file_exists(ARQ_OCULTOS):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(ARQ_OCULTOS))
		if typeof(d) == TYPE_ARRAY:
			for x in d:
				_ocultos.append(str(x))


func _salvar_ocultos() -> void:
	var f := FileAccess.open(ARQ_OCULTOS, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_ocultos))
		f.close()


# Apaga um personagem (menos os de treino). Se for do app (user://), apaga a pasta; se vier junto
# do jogo (res://), ele é escondido da lista. Devolve true se apagou.
func apagar(id: String) -> bool:
	if eh_protegido(id) or not _por_id.has(id):
		return false
	var item: Dictionary = _por_id[id]
	if str(item["origem"]) == "usuario":
		_apagar_pasta(str(item["pasta"]))
	elif not _ocultos.has(id):
		_ocultos.append(id)
		_salvar_ocultos()
	recarregar()
	# se por baixo havia uma versão do jogo com o mesmo id, esconde também
	if _por_id.has(id):
		if not _ocultos.has(id):
			_ocultos.append(id)
			_salvar_ocultos()
		recarregar()
	return not _por_id.has(id)


func _apagar_pasta(pasta: String) -> void:
	var dir := DirAccess.open(pasta)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	for d in dir.get_directories():
		_apagar_pasta(pasta.path_join(d) + "/")
	DirAccess.remove_absolute(pasta)


func lista() -> Array:
	return _lista.duplicate(true)


func existe(id: String) -> bool:
	return _por_id.has(id)


func obter(id: String) -> Dictionary:
	return _por_id.get(id, {}).duplicate(true)


func pasta(id: String) -> String:
	return str(_por_id.get(id, {}).get("pasta", ""))


func total() -> int:
	return _lista.size()


func _varrer(raiz: String, origem: String) -> void:
	var dir := DirAccess.open(raiz)
	if dir == null:
		return
	dir.list_dir_begin()
	var nome := dir.get_next()
	while nome != "":
		if dir.current_is_dir() and not nome.begins_with("."):
			_carregar_pasta(raiz + nome + "/", origem)
		nome = dir.get_next()
	dir.list_dir_end()


func _carregar_pasta(pasta_personagem: String, origem: String) -> void:
	var arquivo := pasta_personagem + "personagem.json"
	if not FileAccess.file_exists(arquivo):
		return
	var r := Formato.ler(arquivo)
	if not r["ok"]:
		push_warning("Personagem ignorado (%s): %s" % [pasta_personagem, r["erro"]])
		return
	var p: Dictionary = r["personagem"]
	var id: String = p["id"]
	if _por_id.has(id):
		var antigo: Dictionary = _por_id[id]
		# O do app (user://) substitui o do jogo (res://) com o mesmo id.
		if origem == "usuario" and antigo["origem"] == "jogo":
			_remover(id)
		else:
			push_warning("ID repetido, ignorado (%s): %s" % [origem, id])
			return
	var item := {
		"id": id,
		"nome": p["nome"],
		"origem": origem,
		"pasta": pasta_personagem,
		"personagem": p,
		"moveset": Formato.moveset(p)
	}
	_lista.append(item)
	_por_id[id] = item


func _remover(id: String) -> void:
	for i in range(_lista.size()):
		if _lista[i]["id"] == id:
			_lista.remove_at(i)
			break
	_por_id.erase(id)