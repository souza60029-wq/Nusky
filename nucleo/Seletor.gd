extends Node

# Abre a galeria ou o explorador de arquivos do sistema. No iPhone usa o código nativo
# ios/EmberSeletor.m, que conversa com o app por arquivos (pedido.json / resultado.json).

signal escolhidos(caminhos: PackedStringArray)
signal falhou(msg: String)

const PASTA := "user://seletor/"

var _id: int = 0
var _timer: Timer = null
var _espera: float = 0.0


func disponivel() -> bool:
	return OS.get_name() == "iOS"


# origem: "galeria" ou "arquivos". tipo: "imagem", "audio" ou "qualquer".
func pedir(origem: String, varios: bool, tipo: String = "imagem") -> void:
	if not disponivel():
		falhou.emit("Importar da galeria/arquivos ainda nao esta pronto neste sistema (so no iPhone por enquanto).")
		return
	DirAccess.make_dir_recursive_absolute(PASTA + "recebidos")
	var dir := DirAccess.open(PASTA + "recebidos")
	if dir != null:
		for nome in dir.get_files():
			dir.remove(nome)
	for velho in ["resultado.json", "pedido.json", "pedido.tmp"]:
		if FileAccess.file_exists(PASTA + velho):
			DirAccess.remove_absolute(PASTA + velho)
	_id = Time.get_ticks_msec()
	var f := FileAccess.open(PASTA + "pedido.tmp", FileAccess.WRITE)
	if f == null:
		falhou.emit("Nao consegui preparar o seletor.")
		return
	f.store_string(JSON.stringify({"id": _id, "origem": origem, "varios": varios, "tipo": tipo}))
	f.close()
	DirAccess.rename_absolute(PASTA + "pedido.tmp", PASTA + "pedido.json")
	_espera = 0.0
	if _timer == null:
		_timer = Timer.new()
		_timer.wait_time = 0.3
		_timer.timeout.connect(_poll)
		add_child(_timer)
	_timer.start()


func _poll() -> void:
	_espera += 0.3
	if FileAccess.file_exists(PASTA + "resultado.json"):
		var txt: String = FileAccess.get_file_as_string(PASTA + "resultado.json")
		DirAccess.remove_absolute(PASTA + "resultado.json")
		_timer.stop()
		var d: Variant = JSON.parse_string(txt)
		if typeof(d) == TYPE_DICTIONARY and int((d as Dictionary).get("id", -1)) == _id:
			if bool(d.get("ok", false)):
				var lista := PackedStringArray()
				for c in d.get("arquivos", []):
					lista.append(str(c))
				if not lista.is_empty():
					escolhidos.emit(lista)
					return
			if d.has("erro"):
				falhou.emit(str(d["erro"]))
		return
	# o nativo apaga o pedido ao recebê-lo; se continua lá, o código nativo não está neste build
	if _espera >= 3.0 and FileAccess.file_exists(PASTA + "pedido.json"):
		_timer.stop()
		DirAccess.remove_absolute(PASTA + "pedido.json")
		falhou.emit("O seletor do iPhone nao esta neste build (veja o passo do seletor no GitHub Actions).")
