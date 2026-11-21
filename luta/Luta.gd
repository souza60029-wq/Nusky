extends Node2D

# Tela de luta: liga o núcleo (Personagem) à tela, ao toque e ao controle.
# Não guarda dados de personagem: lê o JSON pelo Formato.
# Nesta versão, o botão EDITOR saiu da luta. O editor volta na próxima entrega.

const Caixa = preload("res://engine/nucleo/Caixa.gd")
const Personagem = preload("res://engine/nucleo/Personagem.gd")
const Formato = preload("res://engine/formato/Formato.gd")
const Sprites = preload("res://engine/nucleo/Sprites.gd")

const PERSONAGEM_INICIAL := "res://personagens/boneco_treino_1/personagem.json"
const VIEW_W := 960.0
const VIEW_H := 540.0
const FRAMES_KO := 150
const TECLAS := ["LP", "LK", "HP", "HK", "BO", "ESQ", "REVP", "REVK"]

const DPAD_C := Vector2(120.0, 430.0)
const DPAD_R := 80.0
const BOTAO_R := 36.0
const BOTOES := {
	"HP": Vector2(720.0, 330.0),
	"BO": Vector2(840.0, 330.0),
	"LP": Vector2(660.0, 410.0),
	"HK": Vector2(780.0, 410.0),
	"LK": Vector2(720.0, 490.0),
	"ESQ": Vector2(860.0, 470.0),
	"REVP": Vector2(600.0, 490.0),
	"REVK": Vector2(900.0, 400.0),
}
const RASTRO_SEG := 0.25

const RECT_RESET := Rect2(260.0, 8.0, 120.0, 34.0)

const COR_P1 := Color(0.9, 0.15, 0.15)
const COR_P1_FUNDO := Color(0.3, 0.05, 0.05)
const COR_P2 := Color(0.2, 0.5, 1.0)
const COR_P2_FUNDO := Color(0.05, 0.12, 0.3)
const COR_DANO := Color(1.0, 0.9, 0.2)

# Altura da faixa de dano em relação à barra de vida (0.35 = 35%).
const FRACAO_FAIXA_DANO := 0.35

var p1 = Personagem.new()
var p2 = Personagem.new()
var nome_p1: String = "Sem personagem"
var nome_p2: String = "Sem personagem"
var projeteis: Array = []
var rastros: Array = []
var _pre: Array = [{}, {}]
var dados1: Dictionary = {}
var dados2: Dictionary = {}
var pasta1: String = ""
var pasta2: String = ""
var id1: String = ""
var id2: String = ""
var aviso: String = ""
var toques := {}
var mask1 := {}
var mask2 := {}
var ko_t := 0

# ---------- Ciclo de vida ----------

func _init() -> void:
	p1.oponente = p2
	p2.oponente = p1

func _ready() -> void:
	_carregar_lutadores()
	_tocar_tema()
	_reiniciar_luta()

func _process(_delta: float) -> void:
	queue_redraw()

func _physics_process(_delta: float) -> void:
	_pre = [_foto(p1, dados1, pasta1), _foto(p2, dados2, pasta2)]
	_passo_jogador(p1, (_dir_pad(0) + _vec_dpad()).limit_length(1.0), _entrada_p1(), mask1)
	_passo_jogador(p2, _dir_pad(1), _entrada_pad(1, 2), mask2)
	_resolver_combate(p1, p2)
	_resolver_combate(p2, p1)
	_separar_corpos()
	_tocar_eventos(p1, id1)
	_tocar_eventos(p2, id2)
	_passo_projeteis()
	_passo_rastros()
	_expirar_combos()
	if p1.estado == Personagem.Estado.KO or p2.estado == Personagem.Estado.KO:
		ko_t += 1
		if ko_t > FRAMES_KO:
			_reiniciar_luta()
	else:
		ko_t = 0

# ---------- Carregamento ----------

# Lê os personagens escolhidos na seleção (Navegacao.selecao). Sem escolha, usa o primeiro
# do catálogo e, se não houver nenhum, o personagem inicial do jogo.
func _carregar_lutadores() -> void:
	var sel: Dictionary = {"p1": "", "p2": ""}
	if has_node("/root/Navegacao"):
		sel = get_node("/root/Navegacao").selecao
	var a: Dictionary = _obter(str(sel.get("p1", "")))
	var b: Dictionary = _obter(str(sel.get("p2", "")))
	if b.is_empty():
		b = a
	_aplicar(p1, a, 1)
	_aplicar(p2, b, 2)

# Música da luta: tema do jogador 1 (personagens/<id>/musica); sem tema, o do jogador 2;
# sem nenhum, sorteia entre todas as músicas de musica/ (inclui musica/menu/).
func _tocar_tema() -> void:
	if not has_node("/root/Audio"):
		return
	var audio: Node = get_node("/root/Audio")
	if not (audio.tocar_musica_personagem(id1) or audio.tocar_musica_personagem(id2)):
		audio.tocar_luta()

func _obter(id: String) -> Dictionary:
	if has_node("/root/Catalogo"):
		var cat: Node = get_node("/root/Catalogo")
		if id != "":
			var item: Dictionary = cat.obter(id)
			if not item.is_empty():
				return item
		var lista: Array = cat.lista()
		if not lista.is_empty():
			return lista[0]
	var r: Dictionary = Formato.ler(PERSONAGEM_INICIAL)
	if r["ok"]:
		var per: Dictionary = r["personagem"]
		return {"id": str(per["id"]), "nome": str(per["nome"]), "pasta": PERSONAGEM_INICIAL.get_base_dir() + "/", "personagem": per}
	return {}

func _aplicar(p, item: Dictionary, lado: int) -> void:
	var per: Dictionary = {}
	var pasta: String = ""
	var nome: String = "Sem personagem"
	var id: String = ""
	if item.is_empty():
		p.definir_golpes([Formato.padrao_golpe()])
		aviso = "Personagem não carregado."
	else:
		per = item["personagem"]
		pasta = str(item["pasta"])
		nome = str(per["nome"])
		id = str(item["id"])
		p.definir_golpes(per["golpes"])
		p.definir_escala(float(per.get("altura_px", Formato.ALTURA_PADRAO)) / Personagem.CORPO_ALTURA * Personagem.TAMANHO_GERAL)
	if lado == 1:
		dados1 = per
		pasta1 = pasta
		nome_p1 = nome
		id1 = id
	else:
		dados2 = per
		pasta2 = pasta
		nome_p2 = nome
		id2 = id

# Sons da luta: usa os arquivos do personagem (sons/<evento>) e o som do golpe, se houver.
func _tocar_eventos(p, id: String) -> void:
	var fila: Array = p.eventos
	p.eventos = []
	var audio: Node = get_node("/root/Audio") if has_node("/root/Audio") else null
	for e in fila:
		var ev: Dictionary = e
		var g: Dictionary = ev["golpe"]
		var tipo: String = str(ev["tipo"])
		if tipo == "projetil":
			_criar_projetil(p, ev["bloco"], g)
			continue
		if tipo == "rev":
			rastros.append({"foto": _pre[0 if p == p1 else 1], "t": RASTRO_SEG})
		if audio == null or not _sons_ligados():
			continue
		match tipo:
			"golpe":
				audio.tocar("ataque_forte" if int(g["forca"]) >= 2 else "ataque_leve", id)
			"som_quadro":
				audio.tocar("", id, str(ev["arquivo"]))
			"acerto":
				audio.tocar("impacto_forte" if int(g["forca"]) >= 2 else "impacto_leve", id)
			"bloqueio":
				audio.tocar("bloqueio", id)
			"parry", "guarda_quebrada", "esquiva", "pulo", "rev":
				audio.tocar(tipo, id)

# Rastro do REV: o último sprite antes do REV fica em vermelho e some em 0,25 s.
func _foto(p, dados: Dictionary, pasta: String) -> Dictionary:
	return {"tex": _textura_atual(p, dados, pasta), "pos": p.pos, "direita": p.direita != (str(dados.get("olhando", "direita")) == "esquerda"), "rect": p.corpo_rect()}

func _passo_rastros() -> void:
	var vivos: Array = []
	for r in rastros:
		var d: Dictionary = r
		d["t"] = float(d["t"]) - DT
		if float(d["t"]) > 0.0:
			vivos.append(d)
	rastros = vivos

func _desenhar_rastros() -> void:
	for r in rastros:
		var d: Dictionary = r
		var f: Dictionary = d["foto"]
		var a: float = clampf(float(d["t"]) / RASTRO_SEG, 0.0, 1.0) * 0.7
		var tex: Texture2D = f["tex"]
		if tex != null:
			Sprites.desenhar(self, tex, f["pos"], bool(f["direita"]), Color(1.0, 0.2, 0.2, a), Personagem.TAMANHO_GERAL)
		else:
			draw_rect(f["rect"], Color(1.0, 0.2, 0.2, a * 0.7))

func _sons_ligados() -> bool:
	return not has_node("/root/Config") or bool(get_node("/root/Config").sons_luta_ligados)

# ---------- Magias (projéteis lançados por blocos) ----------

const DT := 1.0 / 60.0
const MAX_PROJETEIS := 8

func _criar_projetil(p, b: Dictionary, _g: Dictionary) -> void:
	if projeteis.size() >= MAX_PROJETEIS:
		return
	var frente: float = 1.0 if p.direita else -1.0
	var esc: float = float(p.escala)
	var g: Dictionary = Formato.padrao_golpe()
	g["nome"] = "Magia"
	g["dano"] = int(b["dano"])
	g["forca"] = int(b["forca"])
	projeteis.append({
		"dono": p,
		"pos": p.pos + Vector2(float(b["ox"]) * frente * esc, float(b["oy"]) * esc),
		"vel": Vector2(float(b["vx"]) * frente, 0.0),
		"tam": Vector2(float(b["w"]), float(b["h"])) * esc,
		"vida": int(b["vida"]),
		"golpe": g,
	})

func _passo_projeteis() -> void:
	var restantes: Array = []
	for it in projeteis:
		var pj: Dictionary = it
		pj["pos"] = (pj["pos"] as Vector2) + (pj["vel"] as Vector2) * DT
		pj["vida"] = int(pj["vida"]) - 1
		var dono = pj["dono"]
		var alvo = dono.oponente
		var r := Rect2((pj["pos"] as Vector2) - (pj["tam"] as Vector2) * 0.5, pj["tam"])
		var fora: bool = r.end.x < -80.0 or r.position.x > 1040.0
		var g: Dictionary = pj["golpe"]
		if int(pj["vida"]) > 0 and not fora:
			if Caixa.colidem(r, alvo.corpo_rect()):
				var res: String = alvo.resultado_para(g)
				if res != "nada":
					_aplicar_acerto(dono, alvo, g, res)
					continue
			restantes.append(pj)
	projeteis = restantes

func _desenhar_projeteis() -> void:
	for it in projeteis:
		var pj: Dictionary = it
		var t: Vector2 = pj["tam"]
		var r: float = maxf(t.x, t.y) * 0.5
		draw_circle(pj["pos"], r, Color(1.0, 0.55, 0.15, 0.55))
		draw_circle(pj["pos"], r * 0.6, Color(1.0, 0.9, 0.5, 0.95))
		if _debug():
			draw_rect(Rect2((pj["pos"] as Vector2) - t * 0.5, t), Color(1.0, 0.3, 0.3), false, 2.0)

# ---------- Entrada ----------

func _unhandled_input(ev: InputEvent) -> void:
	var st := ev as InputEventScreenTouch
	var sd := ev as InputEventScreenDrag
	if st != null:
		if st.pressed:
			var alvo := _alvo_toque(st.position)
			toques[st.index] = {"alvo": alvo, "pos": st.position}
			if alvo == "RESET":
				_reiniciar_luta()
		else:
			toques.erase(st.index)
	elif sd != null:
		if toques.has(sd.index):
			toques[sd.index]["pos"] = sd.position

# Com controle conectado os botões de luta na tela somem (e deixam de receber toque).
func _modo_controle() -> bool:
	return has_node("/root/Config") and str(get_node("/root/Config").modo_efetivo()) == "controle"

func _alvo_toque(p: Vector2) -> String:
	if RECT_RESET.has_point(p):
		return "RESET"
	if _modo_controle():
		return ""
	if p.distance_to(DPAD_C) <= DPAD_R * 1.2:
		return "DPAD"
	var melhor := ""
	var menor: float = BOTAO_R * 1.25
	for k in BOTOES:
		var d: float = p.distance_to(BOTOES[k])
		if d < menor:
			menor = d
			melhor = str(k)
	return melhor

func _vec_dpad() -> Vector2:
	for idx in toques:
		if str(toques[idx]["alvo"]) == "DPAD":
			var pos_t: Vector2 = toques[idx]["pos"]
			var v: Vector2 = (pos_t - DPAD_C) / DPAD_R
			if v.length() < 0.25:
				return Vector2.ZERO
			return v.limit_length(1.0)
	return Vector2.ZERO

func _botoes_tocados() -> Dictionary:
	var r := {}
	for idx in toques:
		var alvo: String = str(toques[idx]["alvo"])
		if BOTOES.has(alvo):
			r[alvo] = true
	return r

func _dir_pad(dev: int) -> Vector2:
	var v := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
	if v.length() < 0.3:
		v = Vector2.ZERO
	if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_LEFT):
		v.x -= 1.0
	if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_RIGHT):
		v.x += 1.0
	if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_UP):
		v.y -= 1.0
	if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_DOWN):
		v.y += 1.0
	return v.limit_length(1.0)

# Botões do controle, pelo mapa do jogador (Configurações > Controles).
func _entrada_pad(dev: int, jogador: int) -> Dictionary:
	if has_node("/root/Config"):
		return get_node("/root/Config").entrada_luta(dev, jogador)
	return {"LP": false, "LK": false, "HP": false, "HK": false, "BO": false, "ESQ": false, "REVP": false, "REVK": false}

func _entrada_p1() -> Dictionary:
	var pad := _entrada_pad(0, 1)
	var tocado := _botoes_tocados()
	var r := {}
	for k in TECLAS:
		r[k] = bool(pad.get(k, false)) or tocado.has(k)
	return r

# Combos de toque: LP+LK = ESQ (esquiva), HP+HK = BO (blow off).
# Também: LP+HP = REV de soco e LK+HK = REV de chute (os botões REV na tela fazem o mesmo).
func _logico(raw: Dictionary) -> Dictionary:
	var lp: bool = bool(raw["LP"])
	var lk: bool = bool(raw["LK"])
	var hp: bool = bool(raw["HP"])
	var hk: bool = bool(raw["HK"])
	var bo: bool = bool(raw["BO"])
	var esq: bool = bool(raw["ESQ"])
	var revp: bool = bool(raw["REVP"])
	var revk: bool = bool(raw["REVK"])
	if hp and hk:
		bo = true
		hp = false
		hk = false
	if lp and lk:
		esq = true
		lp = false
		lk = false
	if lp and hp:
		revp = true
		lp = false
		hp = false
	if lk and hk:
		revk = true
		lk = false
		hk = false
	return {"LP": lp, "LK": lk, "HP": hp, "HK": hk, "BO": bo, "ESQ": esq, "REVP": revp, "REVK": revk}

# Botão segurado não repete golpe. Ao iniciar um golpe, ou ao sair de um
# estado livre e voltar a um livre, os botões ainda segurados ficam mascarados
# até serem soltos.
func _passo_jogador(p, dir: Vector2, raw: Dictionary, mask: Dictionary) -> void:
	var logico: Dictionary = _logico(raw)
	var ap := {}
	for k in TECLAS:
		ap[k] = bool(logico[k]) and not bool(mask[k])
	var era_livre: bool = _livre(p.estado)
	p.atualizar(dir, ap)
	if era_livre != _livre(p.estado):
		for k in TECLAS:
			if bool(raw[k]) or bool(logico[k]):
				mask[k] = true
	for k in TECLAS:
		if not (bool(raw[k]) or bool(logico[k])):
			mask[k] = false

func _livre(est: int) -> bool:
	return est == Personagem.Estado.PARADO or est == Personagem.Estado.ANDANDO or est == Personagem.Estado.PULANDO or est == Personagem.Estado.DEFENDENDO

func _mascara_vazia() -> Dictionary:
	var d := {}
	for k in TECLAS:
		d[k] = false
	return d

# ---------- Combate ----------

func _reiniciar_luta() -> void:
	p1.resetar(200.0, true)
	p2.resetar(720.0, false)
	p1.oponente = p2
	p2.oponente = p1
	mask1 = _mascara_vazia()
	mask2 = _mascara_vazia()
	ko_t = 0
	projeteis.clear()
	rastros.clear()

func _resolver_combate(atk, dfn) -> void:
	if not atk.hitbox_ativa() or atk.golpe_acertou:
		return
	var g: Dictionary = atk.golpe_atual
	if not Caixa.colidem(atk.hitbox_rect(), dfn.corpo_rect()):
		return
	var res: String = dfn.resultado_para(g)
	if res == "nada":
		return
	atk.golpe_acertou = true
	_aplicar_acerto(atk, dfn, g, res)

# Resultado de um golpe (ou magia) que encostou no defensor: parry, bloqueio ou dano.
func _aplicar_acerto(atk, dfn, g: Dictionary, res: String) -> void:
	if res == "parry":
		dfn.receber_parry(g)
		return
	if res == "bloqueio":
		dfn.receber_bloqueio(g)
		return
	var escala: float = maxf(0.5, 1.0 - 0.1 * float(atk.combo))
	var dano: float = Personagem.dano_do_golpe(g) * escala
	var vida_antes: float = dfn.vida
	# Primeiro acerto de um combo zera a barra de dano do defensor.
	if atk.combo == 0:
		dfn.dano_combo = 0.0
	dfn.receber_acerto(g, dano)
	dfn.dano_combo += vida_antes - dfn.vida
	atk.combo += 1
	atk.janela_combo = Personagem.JANELA_COMBO
	if str(g["carga"]) != "" and float(g["energia_ganha"]) > 0.0:
		atk.barra.ganhar(float(g["energia_ganha"]))

# Combo para de contar quando a janela do último acerto acaba.
func _expirar_combos() -> void:
	_expirar_combo(p1, p2)
	_expirar_combo(p2, p1)

func _expirar_combo(atk, dfn) -> void:
	if atk.janela_combo <= 0:
		return
	atk.janela_combo -= 1
	if atk.janela_combo == 0:
		atk.combo = 0
		dfn.dano_combo = 0.0

func _separar_corpos() -> void:
	if p1.no_chao or p2.no_chao:
		return
	# Durante a esquiva o corpo atravessa o oponente.
	if p1.estado == Personagem.Estado.ESQUIVANDO or p2.estado == Personagem.Estado.ESQUIVANDO:
		return
	var d: float = p2.pos.x - p1.pos.x
	var falta: float = (p1.largura_corpo() + p2.largura_corpo()) * 0.5 - absf(d)
	if falta <= 0.0:
		return
	var s: float = 1.0 if d >= 0.0 else -1.0
	var metade: float = falta * 0.5
	p1.pos = Vector2(clampf(p1.pos.x - s * metade, Personagem.LIMITE_ESQ, Personagem.LIMITE_DIR), p1.pos.y)
	p2.pos = Vector2(clampf(p2.pos.x + s * metade, Personagem.LIMITE_ESQ, Personagem.LIMITE_DIR), p2.pos.y)

# ---------- Desenho ----------

func _draw() -> void:
	_desenhar_luta()
	_desenhar_hud()
	_desenhar_controles()

func _texto(s: String, pos: Vector2, tam: int = 14, cor: Color = Color.WHITE) -> void:
	draw_string(ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, tam, cor)

func _texto_dir(s: String, pos: Vector2, largura: float, tam: int = 14, cor: Color = Color.WHITE) -> void:
	draw_string(ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_RIGHT, largura, tam, cor)

func _texto_c(r: Rect2, s: String, tam: int = 14, cor: Color = Color.WHITE) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + tam * 0.35), s, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, tam, cor)

func _botao(r: Rect2, s: String, ativo: bool = false) -> void:
	draw_rect(r, Color(0.25, 0.35, 0.55) if ativo else Color(0.16, 0.16, 0.22))
	draw_rect(r, Color(0.6, 0.6, 0.7), false, 1.0)
	_texto_c(r, s, 13)

func _desenhar_luta() -> void:
	draw_rect(Rect2(0.0, 0.0, VIEW_W, VIEW_H), Color(0.09, 0.09, 0.12))
	draw_rect(Rect2(0.0, Personagem.CHAO_Y, VIEW_W, VIEW_H - Personagem.CHAO_Y), Color(0.18, 0.16, 0.2))
	draw_line(Vector2(0.0, Personagem.CHAO_Y), Vector2(VIEW_W, Personagem.CHAO_Y), Color(0.5, 0.5, 0.6), 2.0)
	_desenhar_rastros()
	_desenhar_personagem(p1, Color(0.3, 0.6, 1.0), dados1, pasta1)
	_desenhar_personagem(p2, Color(1.0, 0.45, 0.2), dados2, pasta2)
	_desenhar_projeteis()
	if _debug():
		_desenhar_debug(p1)
		_desenhar_debug(p2)
	if aviso != "":
		_texto(aviso, Vector2(20.0, 520.0), 12, Color(1.0, 0.8, 0.5))

func _debug() -> bool:
	return has_node("/root/Config") and bool(get_node("/root/Config").debug_hitboxes)

# Sprite do momento: do golpe (cronograma de frames) ou da animação do estado.
func _textura_atual(p, dados: Dictionary, pasta: String) -> Texture2D:
	if dados.is_empty():
		return null
	var lista: Array = []
	var i: int = -1
	if p.estado == Personagem.Estado.ATACANDO and not p.golpe_atual.is_empty():
		lista = p.golpe_atual["frames"]
		i = Formato.indice_no_tempo(p.golpe_atual, p.tempo)
	else:
		var slot: String = p.slot_animacao()
		var sprites: Dictionary = dados["sprites"]
		lista = sprites.get(slot, [])
		if lista.is_empty():
			lista = sprites.get("parado", [])
			i = Formato.indice_ciclo(lista.size(), p.relogio)
		elif Formato.SLOTS_EM_CICLO.has(slot):
			i = Formato.indice_ciclo(lista.size(), p.relogio)
		else:
			i = Formato.indice_proporcional(lista.size(), p.tempo, p.duracao)
	if lista.is_empty() and p.estado == Personagem.Estado.ATACANDO:
		var sprites2: Dictionary = dados["sprites"]
		lista = sprites2.get("parado", [])
		i = Formato.indice_ciclo(lista.size(), p.relogio)
	return Sprites.textura(Sprites.caminho_quadro(pasta, lista, i))

func _desenhar_personagem(p, base: Color, dados: Dictionary, pasta: String) -> void:
	var tex: Texture2D = _textura_atual(p, dados, pasta)
	var alfa: float = 0.55 if (p.estado == Personagem.Estado.ESQUIVANDO or p.estado == Personagem.Estado.LEVANTANDO) else 1.0
	# Flatline: o personagem inteiro pisca vermelho.
	var pisca: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 70.0) if p.flatline else 0.0
	if tex != null:
		Sprites.desenhar(self, tex, p.pos, p.direita != (str(dados.get("olhando", "direita")) == "esquerda"), Color(1.0, 1.0 - 0.75 * pisca, 1.0 - 0.75 * pisca, alfa), Personagem.TAMANHO_GERAL)
		return
	# Sem sprite: caixa de cor no lugar do personagem.
	var est: int = p.estado
	var cor: Color = base
	if est == Personagem.Estado.GOLPEADO:
		cor = base.lerp(Color.WHITE, 0.5)
	elif est == Personagem.Estado.CAIDO:
		cor = base.darkened(0.4)
	elif est == Personagem.Estado.ATACANDO:
		cor = base.lightened(0.3)
	elif est == Personagem.Estado.KO:
		cor = Color(0.3, 0.3, 0.3)
	elif est == Personagem.Estado.PARRY:
		cor = Color(0.4, 1.0, 0.6)
	elif est == Personagem.Estado.GUARDA_QUEBRADA:
		cor = Color(0.9, 0.4, 0.9)
	elif alfa < 1.0:
		cor = Color(base.r, base.g, base.b, alfa)
	if pisca > 0.0:
		cor = cor.lerp(Color(1.0, 0.1, 0.1), pisca)
	var c: Rect2 = p.corpo_rect()
	draw_rect(c, cor)
	draw_rect(c, Color(1.0, 1.0, 1.0, 0.8), false, 2.0)
	var frente: float = 1.0 if p.direita else -1.0
	draw_circle(Vector2(p.pos.x + frente * 14.0 * p.escala, p.pos.y - 96.0 * p.escala), 5.0, Color.WHITE)

# Modo debug: corpo (azul), hitbox do golpe (vermelho), janela de parry (verde) e dados.
func _desenhar_debug(p) -> void:
	var c: Rect2 = p.corpo_rect()
	draw_rect(c, Color(0.2, 0.5, 1.0, 0.25))
	draw_rect(c, Color(0.3, 0.6, 1.0, 0.9), false, 2.0)
	var hb: Rect2 = p.hitbox_rect()
	if hb.size.x > 0.0:
		draw_rect(hb, Color(1.0, 0.2, 0.2, 0.45))
		draw_rect(hb, Color(1.0, 0.3, 0.3, 1.0), false, 2.0)
	if p.parry_janela > 0:
		draw_rect(c.grow(6.0), Color(0.3, 1.0, 0.5, 0.9), false, 3.0)
	draw_circle(p.pos, 3.0, Color.YELLOW)
	var info: String = "%s  g:%d  pj:%d" % [p.nome_estado(), int(p.guarda), p.parry_janela]
	_texto(info, Vector2(p.pos.x - 50.0, c.position.y - 8.0), 11, Color(1.0, 1.0, 0.6))

func _desenhar_hud() -> void:
	var r1 := Rect2(20.0, 60.0, 410.0, 16.0)
	var r2 := Rect2(530.0, 60.0, 410.0, 16.0)
	_barra_vida(r1, p1, false, COR_P1, COR_P1_FUNDO)
	_barra_vida(r2, p2, true, COR_P2, COR_P2_FUNDO)
	_barra_energia(Rect2(20.0, 82.0, 300.0, 8.0), p1, false)
	_barra_energia(Rect2(640.0, 82.0, 300.0, 8.0), p2, true)
	_barra_guarda(Rect2(20.0, 94.0, 300.0, 6.0), p1, false)
	_barra_guarda(Rect2(640.0, 94.0, 300.0, 6.0), p2, true)
	_barra_pulse(Rect2(20.0, 104.0, 300.0, 6.0), p1, false)
	_barra_pulse(Rect2(640.0, 104.0, 300.0, 6.0), p2, true)
	_avisos(p1, 20.0, false)
	_avisos(p2, 530.0, true)
	_texto(nome_p1, Vector2(20.0, 54.0), 14)
	_texto_dir(nome_p2, Vector2(530.0, 54.0), 410.0, 14)
	_texto(p1.nome_estado(), Vector2(20.0, 110.0), 12, Color(0.8, 0.8, 0.8))
	_texto_dir(p2.nome_estado(), Vector2(530.0, 110.0), 410.0, 12, Color(0.8, 0.8, 0.8))
	if p1.combo > 1:
		_texto("%d hits" % p1.combo, Vector2(20.0, 130.0), 16, Color(1.0, 0.9, 0.3))
	if p2.combo > 1:
		_texto_dir("%d hits" % p2.combo, Vector2(530.0, 130.0), 410.0, 16, Color(1.0, 0.9, 0.3))
	_botao(RECT_RESET, "RESET")
	if p1.estado == Personagem.Estado.KO or p2.estado == Personagem.Estado.KO:
		draw_string(ThemeDB.fallback_font, Vector2(0.0, 220.0), "K.O.", HORIZONTAL_ALIGNMENT_CENTER, VIEW_W, 56, Color(1.0, 0.3, 0.3))

# Barra de vida com a barra de dano ATRÁS dela.
# Ordem: fundo, faixa amarela fina (dano do combo), vida por cima.
# A faixa aparece só entre a vida atual e a vida que o defensor tinha antes do combo.
# Some quando o combo para de contar (_expirar_combo zera dano_combo).
func _barra_vida(r: Rect2, p, da_direita: bool, cor: Color, fundo: Color) -> void:
	draw_rect(r, fundo)
	var atual: float = clampf(float(p.vida) / Personagem.VIDA_MAX, 0.0, 1.0)
	var antes: float = clampf((float(p.vida) + float(p.dano_combo)) / Personagem.VIDA_MAX, 0.0, 1.0)
	if float(p.dano_combo) > 0.0 and antes > atual:
		draw_rect(_faixa_dano(r, atual, antes, da_direita), COR_DANO)
	var w: float = r.size.x * atual
	var x: float = r.position.x + (r.size.x - w if da_direita else 0.0)
	draw_rect(Rect2(x, r.position.y, w, r.size.y), cor)
	draw_rect(r, Color(1.0, 1.0, 1.0, 0.8), false, 1.0)

# Faixa fina, centralizada na altura da barra, entre a proporção atual (de)
# e a proporção de antes do combo (ate).
func _faixa_dano(r: Rect2, de: float, ate: float, da_direita: bool) -> Rect2:
	var x0: float
	var x1: float
	if da_direita:
		x0 = r.position.x + r.size.x * (1.0 - ate)
		x1 = r.position.x + r.size.x * (1.0 - de)
	else:
		x0 = r.position.x + r.size.x * de
		x1 = r.position.x + r.size.x * ate
	var h: float = r.size.y * FRACAO_FAIXA_DANO
	var y: float = r.position.y + (r.size.y - h) * 0.5
	return Rect2(x0, y, x1 - x0, h)

func _barra_energia(r: Rect2, p, da_direita: bool) -> void:
	draw_rect(r, Color(0.15, 0.15, 0.2))
	var maximo: float = maxf(1.0, float(p.barra.maximo))
	var prop: float = clampf(float(p.barra.valor) / maximo, 0.0, 1.0)
	var w: float = r.size.x * prop
	var x: float = r.position.x + (r.size.x - w if da_direita else 0.0)
	draw_rect(Rect2(x, r.position.y, w, r.size.y), Color(1.0, 0.7, 0.2))
	draw_rect(r, Color(1.0, 1.0, 1.0, 0.6), false, 1.0)

# Barra de defesa: azul-claro; vermelha enquanto a guarda está quebrada.
func _barra_guarda(r: Rect2, p, da_direita: bool) -> void:
	draw_rect(r, Color(0.12, 0.15, 0.2))
	var prop: float = clampf(float(p.guarda) / Personagem.GUARDA_MAX, 0.0, 1.0)
	var w: float = r.size.x * prop
	var x: float = r.position.x + (r.size.x - w if da_direita else 0.0)
	var quebrada: bool = p.estado == Personagem.Estado.GUARDA_QUEBRADA
	draw_rect(Rect2(x, r.position.y, w, r.size.y), Color(1.0, 0.3, 0.3) if quebrada else Color(0.4, 0.8, 1.0))
	draw_rect(r, Color(1.0, 1.0, 1.0, 0.5), false, 1.0)

# Barra PULSE (REV). Cheia vira FLATLINE.
func _barra_pulse(r: Rect2, p, da_direita: bool) -> void:
	draw_rect(r, Color(0.12, 0.12, 0.15))
	var prop: float = clampf(float(p.pulse) / 100.0, 0.0, 1.0)
	var w: float = r.size.x * prop
	var x: float = r.position.x + (r.size.x - w if da_direita else 0.0)
	var cor: Color = Color(0.2, 0.9, 0.8).lerp(Color(1.0, 0.2, 0.2), prop)
	draw_rect(Rect2(x, r.position.y, w, r.size.y), cor)
	draw_rect(r, Color(1.0, 1.0, 1.0, 0.5), false, 1.0)
	var rotulo: String = "FLATLINE" if p.flatline else "PULSE"
	var cor_t: Color = Color(1.0, 0.3, 0.3) if p.flatline else Color(0.7, 0.9, 0.9)
	if da_direita:
		_texto_dir(rotulo, Vector2(r.position.x, r.end.y + 12.0), r.size.x, 11, cor_t)
	else:
		_texto(rotulo, Vector2(r.position.x, r.end.y + 12.0), 11, cor_t)

func _avisos(p, x: float, da_direita: bool) -> void:
	var texto: String = ""
	var cor: Color = Color.WHITE
	if p.parry_aviso > 0:
		texto = "JUST DEFENSE!"
		cor = Color(0.4, 1.0, 0.6)
	elif p.estado == Personagem.Estado.GUARDA_QUEBRADA:
		texto = "GUARD BREAK"
		cor = Color(1.0, 0.4, 0.4)
	if texto == "":
		return
	if da_direita:
		_texto_dir(texto, Vector2(x, 150.0), 410.0, 16, cor)
	else:
		_texto(texto, Vector2(x, 150.0), 16, cor)

func _desenhar_controles() -> void:
	if _modo_controle():
		return
	var tocado := _botoes_tocados()
	draw_circle(DPAD_C, DPAD_R, Color(1.0, 1.0, 1.0, 0.1))
	var dv: Vector2 = _vec_dpad()
	draw_circle(DPAD_C + dv * DPAD_R * 0.6, 26.0, Color(1.0, 1.0, 1.0, 0.4 if dv != Vector2.ZERO else 0.15))
	for k in BOTOES:
		var c: Vector2 = BOTOES[k]
		draw_circle(c, BOTAO_R, Color(1.0, 1.0, 1.0, 0.35 if tocado.has(k) else 0.12))
		draw_string(ThemeDB.fallback_font, c + Vector2(-BOTAO_R, 5.0), str(k), HORIZONTAL_ALIGNMENT_CENTER, BOTAO_R * 2.0, 14, Color(1.0, 1.0, 1.0, 0.8))