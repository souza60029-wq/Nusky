extends Control

# Tela de personagens (substitui criar/editar personagem, que agora é feito no Ember Forja).
# modo "importar": traz um personagem do Forja (arquivo .ember) para o jogo.
#   - "Escolher arquivo..." abre o app Arquivos do iPhone;
#   - ou toque num .ember que você colocou em Arquivos > No meu iPhone > Ember > importar.
# modo "apagar": lista todos os personagens, menos os 2 bonecos de treino; a lixeira apaga (toque duas vezes).
# Autoloads são acessados por get_node, para o script compilar sem eles.

const Pacote = preload("res://engine/formato/Pacote.gd")
const Seletor = preload("res://engine/nucleo/Seletor.gd")

const PASTA_IMPORTAR := "user://importar/"
const VIEW_W := 960.0
const VIEW_H := 540.0
const TOPO := 96.0
const LINHA_W := 660.0
const LINHA_H := 58.0
const LINHA_GAP := 8.0
const LIXO_W := 64.0
const R_VOLTAR := Rect2(20.0, 16.0, 130.0, 44.0)

# Menu que abriu a tela (para voltar para a mesma aba) e o modo pedido.
static var modo: String = "importar"
static var voltar_aba: int = -1

var _itens: Array = []
var _rolagem: float = 0.0
var _msg: String = ""
var _msg_t: float = 0.0
var _confirmar: int = -1
var _baixo: bool = false
var _arrasto: bool = false
var _inicio: Vector2 = Vector2.ZERO
var _ultimo: Vector2 = Vector2.ZERO
var _toque: bool = false
var _seletor: Variant = null


func _textos() -> Variant:
	return get_node("/root/Textos")


func _catalogo() -> Variant:
	return get_node("/root/Catalogo")


func _navegacao() -> Variant:
	return get_node("/root/Navegacao")


func _t(chave: String) -> String:
	return str(_textos().t(chave))


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toque = DisplayServer.is_touchscreen_available()
	DirAccess.make_dir_recursive_absolute(PASTA_IMPORTAR)
	_seletor = Seletor.new()
	_seletor.escolhidos.connect(_ao_escolher_arquivo)
	_seletor.falhou.connect(_avisar)
	add_child(_seletor)
	_carregar()


func _avisar(texto: String) -> void:
	_msg = texto
	_msg_t = 5.0


func _carregar() -> void:
	_itens.clear()
	_confirmar = -1
	if modo == "importar":
		_itens.append({"tipo": "escolher", "titulo": _t("imp_escolher"), "sub": ""})
		var dir := DirAccess.open(PASTA_IMPORTAR)
		if dir != null:
			var nomes: Array = []
			for f in dir.get_files():
				if f.to_lower().ends_with("." + Pacote.EXTENSAO_ARQUIVO):
					nomes.append(f)
			nomes.sort()
			for f in nomes:
				var kb: int = int(FileAccess.get_file_as_bytes(PASTA_IMPORTAR + str(f)).size() / 1024)
				_itens.append({"tipo": "arquivo", "titulo": str(f), "sub": "%d KB" % kb, "dado": PASTA_IMPORTAR + str(f)})
	else:
		for it in _catalogo().lista():
			if _catalogo().eh_protegido(str(it["id"])):
				continue   # os bonecos de treino não podem ser apagados
			_itens.append({"tipo": "personagem", "titulo": str(it["nome"]), "sub": "", "dado": it})
	_rolagem = clampf(_rolagem, 0.0, _max_rolagem())


func _max_rolagem() -> float:
	var total: float = float(_itens.size()) * (LINHA_H + LINHA_GAP)
	return maxf(0.0, total - (VIEW_H - TOPO - 40.0))


func _rect_linha(i: int) -> Rect2:
	return Rect2((VIEW_W - LINHA_W) * 0.5, TOPO + float(i) * (LINHA_H + LINHA_GAP) - _rolagem, LINHA_W, LINHA_H)


func _rect_lixo(i: int) -> Rect2:
	var r: Rect2 = _rect_linha(i)
	return Rect2(r.end.x - LIXO_W, r.position.y, LIXO_W, r.size.y)


func _process(delta: float) -> void:
	if _msg_t > 0.0:
		_msg_t -= delta
	queue_redraw()


# ---------- toques ----------

func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel"):
		_voltar()
		return
	if _toque:
		var t := ev as InputEventScreenTouch
		if t != null:
			if t.pressed:
				_comecar(t.position)
			else:
				_terminar(t.position)
			return
		var d := ev as InputEventScreenDrag
		if d != null:
			_arrastar(d.position)
		return
	var mb := ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_comecar(mb.position)
		else:
			_terminar(mb.position)
		return
	var mm := ev as InputEventMouseMotion
	if mm != null and _baixo:
		_arrastar(mm.position)
		return
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_rolagem = clampf(_rolagem + 40.0, 0.0, _max_rolagem())
	elif mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_rolagem = clampf(_rolagem - 40.0, 0.0, _max_rolagem())


func _comecar(p: Vector2) -> void:
	_baixo = true
	_arrasto = false
	_inicio = p
	_ultimo = p


func _arrastar(p: Vector2) -> void:
	if not _baixo:
		return
	if p.distance_to(_inicio) > 12.0:
		_arrasto = true
	if _arrasto:
		_rolagem = clampf(_rolagem - (p.y - _ultimo.y), 0.0, _max_rolagem())
	_ultimo = p


func _terminar(p: Vector2) -> void:
	var tocou: bool = _baixo and not _arrasto
	_baixo = false
	if not tocou:
		return
	if R_VOLTAR.has_point(p):
		_voltar()
		return
	if p.y < TOPO - 8.0:
		return
	for i in range(_itens.size()):
		if not _rect_linha(i).has_point(p):
			continue
		var tipo: String = str(_itens[i]["tipo"])
		if tipo == "escolher":
			_seletor.pedir("arquivos", false, "qualquer")
		elif tipo == "arquivo":
			_importar(str(_itens[i]["dado"]), true)
		elif _rect_lixo(i).has_point(p):
			_apagar(i)
		else:
			_confirmar = -1
		return


# ---------- ações ----------

func _voltar() -> void:
	_navegacao().ir_para_menu()


func _ao_escolher_arquivo(caminhos: PackedStringArray) -> void:
	for c in caminhos:
		if str(c).to_lower().ends_with("." + Pacote.EXTENSAO_ARQUIVO):
			_importar(str(c), false)
		else:
			_avisar("Escolha um arquivo .ember (exportado pelo Ember Forja).")


func _importar(caminho: String, mover: bool) -> void:
	var r: Dictionary = Pacote.importar_arquivo(caminho)
	if bool(r["ok"]):
		_catalogo().recarregar()
		_avisar("Importado: " + str((r["personagem"] as Dictionary)["nome"]))
		if mover:
			# tira da lista para não importar duas vezes
			var destino: String = PASTA_IMPORTAR + "importados/"
			DirAccess.make_dir_recursive_absolute(destino)
			DirAccess.rename_absolute(caminho, destino + caminho.get_file())
		_carregar()
	else:
		_avisar(str(r["erro"]))


func _apagar(i: int) -> void:
	if _confirmar != i:
		_confirmar = i
		return
	var it: Dictionary = _itens[i]["dado"]
	var nome: String = str(it["nome"])
	if _catalogo().apagar(str(it["id"])):
		_avisar("Apagado: " + nome)
	else:
		_avisar("Nao foi possivel apagar " + nome)
	_carregar()


# ---------- desenho ----------

func _draw() -> void:
	var fonte: Font = ThemeDB.fallback_font
	draw_rect(Rect2(0.0, 0.0, VIEW_W, VIEW_H), Color(0.07, 0.06, 0.12), true)
	for i in range(_itens.size()):
		var r: Rect2 = _rect_linha(i)
		if r.end.y < TOPO - 10.0 or r.position.y > VIEW_H:
			continue
		var tipo: String = str(_itens[i]["tipo"])
		var pedindo: bool = tipo == "personagem" and i == _confirmar
		var destaque: bool = tipo == "escolher"
		var fundo: Color = Color(0.35, 0.1, 0.12, 0.95) if pedindo else (Color(0.3, 0.16, 0.06, 0.95) if destaque else Color(0.16, 0.14, 0.26, 0.95))
		var borda: Color = Color(1.0, 0.45, 0.4) if pedindo else (Color(1.0, 0.6, 0.2) if destaque else Color(0.45, 0.38, 0.75))
		draw_rect(r, fundo, true)
		draw_rect(r, borda, false, 2.0)
		draw_string(fonte, Vector2(r.position.x + 20.0, r.position.y + r.size.y * 0.5 + 8.0), str(_itens[i]["titulo"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 200.0, 24, Color.WHITE)
		if tipo == "personagem":
			var rl: Rect2 = _rect_lixo(i)
			var cor: Color = Color(1.0, 0.5, 0.45)
			var c: Vector2 = rl.get_center()
			draw_rect(Rect2(c.x - 11.0, c.y - 6.0, 22.0, 22.0), cor, false, 2.5)
			draw_line(Vector2(c.x - 15.0, c.y - 9.0), Vector2(c.x + 15.0, c.y - 9.0), cor, 2.5)
			draw_line(Vector2(c.x - 5.0, c.y - 14.0), Vector2(c.x + 5.0, c.y - 14.0), cor, 2.5)
			if pedindo:
				draw_string(fonte, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 6.0), _t("exp_confirmar"), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - LIXO_W - 14.0, 16, Color(1.0, 0.6, 0.55))
		elif str(_itens[i]["sub"]) != "":
			draw_string(fonte, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 6.0), str(_itens[i]["sub"]), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 18.0, 16, Color(0.7, 0.68, 0.85))
	if _itens.is_empty():
		draw_string(fonte, Vector2(0.0, 270.0), _t("exp_vazio"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_W, 24, Color(0.7, 0.68, 0.85))
	# cabeçalho por cima da lista
	draw_rect(Rect2(0.0, 0.0, VIEW_W, TOPO - 10.0), Color(0.07, 0.06, 0.12), true)
	draw_rect(R_VOLTAR, Color(0.16, 0.14, 0.26), true)
	draw_rect(R_VOLTAR, Color(0.45, 0.38, 0.75), false, 2.0)
	draw_string(fonte, Vector2(R_VOLTAR.position.x, R_VOLTAR.position.y + 30.0), "< " + _t("voltar"), HORIZONTAL_ALIGNMENT_CENTER, R_VOLTAR.size.x, 20, Color.WHITE)
	var titulo: String = _t("exp_titulo_importar") if modo == "importar" else _t("exp_titulo_apagar")
	draw_string(fonte, Vector2(0.0, 44.0), titulo, HORIZONTAL_ALIGNMENT_CENTER, VIEW_W, 32, Color(1.0, 0.6, 0.2))
	draw_string(fonte, Vector2(0.0, 72.0), _t("exp_dica_importar") if modo == "importar" else _t("exp_dica_apagar"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_W, 15, Color(0.7, 0.68, 0.85))
	if _msg_t > 0.0 and _msg != "":
		var rm := Rect2(60.0, VIEW_H - 54.0, VIEW_W - 120.0, 40.0)
		draw_rect(rm, Color(0.1, 0.08, 0.2, 0.95), true)
		draw_rect(rm, Color(1.0, 0.6, 0.2), false, 2.0)
		draw_string(fonte, Vector2(rm.position.x, rm.position.y + 27.0), _msg, HORIZONTAL_ALIGNMENT_CENTER, rm.size.x, 17, Color.WHITE)
