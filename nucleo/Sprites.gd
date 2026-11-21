extends RefCounted

# Carrega imagens de res:// ou user:// e desenha o sprite pelo centro dos pés.
# Os sprites devem estar virados para a direita; o motor espelha quando preciso.

static var _cache: Dictionary = {}


static func textura(caminho: String) -> Texture2D:
	if caminho == "":
		return null
	if _cache.has(caminho):
		return _cache[caminho]
	var t: Texture2D = null
	if caminho.begins_with("res://") and ResourceLoader.exists(caminho):
		t = load(caminho) as Texture2D
	if t == null and FileAccess.file_exists(caminho):
		var img: Image = Image.load_from_file(caminho)
		if img != null and not img.is_empty():
			t = ImageTexture.create_from_image(img)
	_cache[caminho] = t
	return t


static func limpar() -> void:
	_cache.clear()


# Escolhe o arquivo do quadro atual. "lista" são caminhos relativos à pasta do personagem.
static func caminho_quadro(pasta: String, lista: Array, indice: int) -> String:
	if indice < 0 or indice >= lista.size():
		return ""
	return pasta + str(lista[indice])


# Desenha com a base do sprite em "pos" (pés), centralizado, espelhado se virado para a esquerda.
static func desenhar(canvas: CanvasItem, tex: Texture2D, pos: Vector2, direita: bool, cor: Color = Color.WHITE, esc: float = 1.0) -> void:
	if tex == null:
		return
	var tam: Vector2 = tex.get_size()
	canvas.draw_set_transform(pos, 0.0, Vector2((1.0 if direita else -1.0) * esc, esc))
	canvas.draw_texture(tex, Vector2(-tam.x * 0.5, -tam.y), cor)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
