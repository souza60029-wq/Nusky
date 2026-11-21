extends RefCounted

# Regras de um lutador: estados, física, golpes e combo.
# Não desenha nada e não lê arquivos.
# Pulo: decolagem no chão (4 frames no normal, 2 na sombra). A direção é escolhida
# na decolagem e fica travada até cair. Sem controle aéreo.
# Escala: corpo e hitbox crescem; velocidade e altura do pulo ficam em px.

const Barra = preload("res://engine/nucleo/Barra.gd")
const Formato = preload("res://engine/formato/Formato.gd")

enum Estado { PARADO, ANDANDO, PULANDO, DEFENDENDO, ATACANDO, GOLPEADO, CAIDO, LEVANTANDO, ESQUIVANDO, KO, DECOLANDO, PARRY, GUARDA_QUEBRADA }

const NOMES_ESTADO := ["PARADO", "ANDANDO", "PULANDO", "DEFENDENDO", "ATACANDO", "GOLPEADO", "CAIDO", "LEVANTANDO", "ESQUIVANDO", "KO", "DECOLANDO", "PARRY", "GUARDA_QUEBRADA"]
const DT: float = 1.0 / 60.0
const GRAVIDADE: float = 2700.0

# Velocidade inicial do pulo (px/s; negativo sobe).
# Normal: alto -560 (25% abaixo de -750), baixo -400.
# Sombra: 25% acima do normal correspondente: alto -700, baixo -500.
const VEL_NORMAL_ALTO: float = -840.0
const VEL_NORMAL_BAIXO: float = -600.0
const VEL_SOMBRA_ALTO: float = -1050.0
const VEL_SOMBRA_BAIXO: float = -750.0
# Frames de decolagem no chão antes de sair do chão.
const DECOLAGEM_NORMAL: int = 4
const DECOLAGEM_SOMBRA: int = 2

const VEL_ANDAR: float = 340.0
const CHAO_Y: float = 480.0
const LIMITE_ESQ: float = 70.0
const LIMITE_DIR: float = 890.0
const VIDA_MAX: float = 1000.0
const HITSTUN: int = 18
const HITSTUN_BLOWBACK: int = 20
const BLOQUEIO: int = 10
const CAIDO_FRAMES: int = 36
const CAIDO_BLOWOFF: int = 90
const LEVANTAR_FRAMES: int = 18
# Esquiva: distância fixa para todos (22 frames x 330 px/s = 121 px), sem custo.
# Para frente atravessa o oponente; com o direcional para trás, rola para trás.
const ESQUIVA_FRAMES: int = 22
const ESQUIVA_VEL: float = 460.0
const ESQUIVA_RECARGA: int = 20
const CUSTO_LEVANTAR: float = 25.0

# Just defense (parry): apertar para trás logo antes do golpe encostar.
# Segurar para trás desde antes é defesa normal. Janela de 5 frames (~83 ms).
const JANELA_PARRY: int = 5
const PARRY_RECARGA: int = 24
const PARRY_FRAMES: int = 14
const PARRY_AVISO: int = 40

# Barra de defesa: cada golpe defendido gasta uma parte. Chegou a zero, a guarda quebra.
const GUARDA_MAX: float = 100.0
const GUARDA_CUSTO := {1: 14.0, 2: 20.0, 3: 28.0}
const GUARDA_QUEBRADA_FRAMES: int = 75
const GUARDA_REGEN_ESPERA: int = 60
const GUARDA_REGEN_POR_FRAME: float = 0.4

# Golpes fortes (força 2 ou 3) causam 30% menos dano.
const FORCA_FORTE: int = 2

# REV (overhead): os dois socos ou os dois chutes executam o golpe forte na hora, sem a parte lenta
# (startup). Cada uso enche a barra PULSE. Ela esvazia sozinha (99 -> 0 em 5 s), mas só depois de
# 2 s sem usar REV. Cheia (100), entra em FLATLINE: o personagem pisca vermelho, perde a defesa
# 15% mais rápido, anda mais devagar e não pode usar REV até o Pulse zerar.
const PULSE_POR_USO: float = 30.0
const PULSE_ESPERA: int = 120
const PULSE_DECAI_FRAME: float = 99.0 / 300.0
const FLATLINE_VEL: float = 0.7
const FLATLINE_GUARDA: float = 1.15
const REV_JANELA_COMBO: int = 4
const REDUCAO_DANO_FORTE: float = 0.30
const CUSTO_GUARD_CANCEL: float = 50.0
const CORPO_LARGURA: float = 50.0
const CORPO_ALTURA: float = 120.0
const ESCALA_MIN: float = 0.5
const ESCALA_MAX: float = 6.0
# Tamanho geral dos personagens (multiplica altura_px). 2.0 deixa o corpo padrão com 240 px de
# 540, perto da proporção do KOF. Pulo e velocidades acima já foram aumentados junto.
const TAMANHO_GERAL: float = 2.0
const JANELA_PULO_SOMBRA: int = 6
const JANELA_COMBO: int = 50
const DIRECAO_SALTO_MIN: float = 0.3

var golpes: Array = []
var barra = Barra.new()
var escala: float = 1.0
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var no_chao: bool = false
var direita: bool = true
var vida: float = VIDA_MAX
var estado: Estado = Estado.PARADO
var tempo: int = 0
var duracao: int = 0
var total_ataque: int = 0
var golpe_atual: Dictionary = {}
var golpe_acertou: bool = false
var combo: int = 0
var janela_combo: int = 0
var dano_combo: float = 0.0
var oponente = null
var bloqueando: bool = false
var bloqueado: bool = false
var caido_recuperavel: bool = true
var carga_tras_t: float = 0.0
var carga_baixo_t: float = 0.0
var frames_desde_baixo: int = 999
var pulo_sombra: bool = false
var pulo_direcao_x: float = 0.0
var guarda: float = GUARDA_MAX
var frames_sem_guarda: int = 0
var parry_janela: int = 0
var parry_trava: int = 0
var parry_aviso: int = 0
var guarda_aviso: int = 0
var esquiva_dir: float = 1.0
var esquiva_trava: int = 0
var reacao: String = "alto"
var relogio: int = 0
var _tras_antes: bool = false
var pulse: float = 0.0
var pulse_ocioso: int = 0
var flatline: bool = false
# Blocos de golpe: movimento programado, sons por sprite e encadeamento.
var _mov_frames: int = 0
var _mov_vx: float = 0.0
var _cadeia: int = 0
var _ultimo_idx_som: int = -2
# Fila de eventos para a Luta tocar sons: {"tipo": String, "golpe": Dictionary}
var eventos: Array = []


# Dano de um golpe depois da redução dos golpes fortes.
static func dano_do_golpe(g: Dictionary) -> float:
	var d: float = float(g["dano"])
	if int(g["forca"]) >= FORCA_FORTE:
		d *= 1.0 - REDUCAO_DANO_FORTE
	return d

# ---------- Ciclo de vida ----------

func definir_golpes(lista: Array) -> void:
	golpes = []
	for g in lista:
		if typeof(g) == TYPE_DICTIONARY:
			golpes.append(Formato.normalizar_golpe(g))


func definir_escala(e: float) -> void:
	escala = clampf(e, ESCALA_MIN, ESCALA_MAX)


func largura_corpo() -> float:
	return CORPO_LARGURA * escala


func altura_corpo() -> float:
	return CORPO_ALTURA * escala


func resetar(x: float, olhando_direita: bool) -> void:
	pos = Vector2(x, CHAO_Y)
	vel = Vector2.ZERO
	no_chao = false
	direita = olhando_direita
	vida = VIDA_MAX
	barra.valor = 0.0
	combo = 0
	janela_combo = 0
	dano_combo = 0.0
	estado = Estado.PARADO
	tempo = 0
	duracao = 0
	total_ataque = 0
	golpe_atual = {}
	golpe_acertou = false
	bloqueando = false
	bloqueado = false
	caido_recuperavel = true
	carga_tras_t = 0.0
	carga_baixo_t = 0.0
	frames_desde_baixo = 999
	pulo_sombra = false
	pulo_direcao_x = 0.0
	guarda = GUARDA_MAX
	frames_sem_guarda = 0
	parry_janela = 0
	parry_trava = 0
	parry_aviso = 0
	guarda_aviso = 0
	esquiva_dir = 1.0
	esquiva_trava = 0
	reacao = "alto"
	relogio = 0
	_tras_antes = false
	_mov_frames = 0
	_cadeia = 0
	_ultimo_idx_som = -2
	pulse = 0.0
	pulse_ocioso = 0
	flatline = false

# ---------- Entrada e estados ----------

func atualizar(dir: Vector2, apertados: Dictionary) -> void:
	relogio += 1
	pulse_ocioso += 1
	if pulse > 0.0 and pulse_ocioso > PULSE_ESPERA:
		pulse = maxf(0.0, pulse - PULSE_DECAI_FRAME)
		if flatline and pulse <= 0.0:
			flatline = false
	if parry_aviso > 0:
		parry_aviso -= 1
	if guarda_aviso > 0:
		guarda_aviso -= 1
	if esquiva_trava > 0:
		esquiva_trava -= 1
	if estado != Estado.GUARDA_QUEBRADA and estado != Estado.KO:
		frames_sem_guarda = mini(frames_sem_guarda + 1, 9999)
		if frames_sem_guarda > GUARDA_REGEN_ESPERA and guarda < GUARDA_MAX:
			guarda = minf(GUARDA_MAX, guarda + GUARDA_REGEN_POR_FRAME)
	if estado == Estado.KO:
		_aplicar_fisica()
		return
	# Vira para o oponente só no chão, em estado livre. No ar a direção fica travada.
	if oponente != null and not no_chao and estado in [Estado.PARADO, Estado.ANDANDO, Estado.DEFENDENDO]:
		direita = oponente.pos.x >= pos.x
	var frente: float = 1.0 if direita else -1.0
	var atras: bool = dir.x * frente < -0.5
	var cima: bool = dir.y < -0.5
	var baixo: bool = dir.y > 0.5
	carga_tras_t = carga_tras_t + DT if atras else 0.0
	carga_baixo_t = carga_baixo_t + DT if baixo else 0.0
	frames_desde_baixo = 0 if baixo else mini(frames_desde_baixo + 1, 999)
	_atualizar_parry(atras and not _tras_antes, atras)
	bloqueando = atras and estado in [Estado.PARADO, Estado.ANDANDO, Estado.PULANDO, Estado.DEFENDENDO, Estado.GOLPEADO]
	match estado:
		Estado.PARADO, Estado.ANDANDO, Estado.PULANDO, Estado.DEFENDENDO:
			_estado_livre(dir, apertados, atras, cima)
		Estado.DECOLANDO:
			_processar_decolagem(dir)
		Estado.ATACANDO:
			_processar_ataque(apertados)
		Estado.GOLPEADO:
			if bloqueado and apertados.get("BO", false) and barra.valor >= CUSTO_GUARD_CANCEL and oponente != null:
				_guard_cancel()
			else:
				_processar_golpeado()
		Estado.CAIDO:
			_processar_caido(apertados)
		Estado.LEVANTANDO, Estado.ESQUIVANDO, Estado.PARRY, Estado.GUARDA_QUEBRADA:
			_processar_temporizado()
	_aplicar_fisica()


func _estado_livre(dir: Vector2, apertados: Dictionary, atras: bool, cima: bool) -> void:
	if apertados.get("ESQ", false) and not no_chao and esquiva_trava == 0:
		_iniciar_esquiva(dir)
		return
	var rev: String = _rev_pedido(apertados)
	if rev != "" and _tentar_rev(rev):
		return
	var g: Dictionary = _escolher_golpe(apertados)
	if not g.is_empty():
		_executar(g)
		return
	if no_chao:
		# No ar: a direção foi escolhida na decolagem. Sem controle aéreo.
		estado = Estado.PULANDO
		return
	if cima:
		_iniciar_decolagem(dir)
		return
	if atras:
		estado = Estado.DEFENDENDO
		vel.x = dir.x * VEL_ANDAR * 0.5 * _mult_vel()
	elif absf(dir.x) > 0.3:
		estado = Estado.ANDANDO
		vel.x = dir.x * VEL_ANDAR * _mult_vel()
	else:
		estado = Estado.PARADO
		vel.x = 0.0


func _escolher_golpe(apertados: Dictionary) -> Dictionary:
	for g in golpes:
		var d: Dictionary = g
		if not apertados.get(d["botao"], false):
			continue
		if not _bloco_do_tipo(d, "comecar_de").is_empty():
			continue
		if d["carga"] == "tras" and carga_tras_t < float(d["carga_seg"]):
			continue
		if d["carga"] == "baixo" and carga_baixo_t < float(d["carga_seg"]):
			continue
		if d["so_ar"] and not no_chao:
			continue
		if float(d["custo"]) > barra.valor:
			continue
		return d
	return {}


func _executar(g: Dictionary, encadeado: bool = false) -> void:
	if not encadeado:
		_cadeia = 0
	_mov_frames = 0
	_ultimo_idx_som = -2
	if str(g["carga"]) != "":
		carga_tras_t = 0.0
		carga_baixo_t = 0.0
	var custo: float = float(g["custo"])
	if custo > 0.0:
		barra.gastar(custo)
	golpe_atual = g.duplicate(true)
	eventos.append({"tipo": "golpe", "golpe": golpe_atual})
	golpe_acertou = false
	estado = Estado.ATACANDO
	tempo = 0
	total_ataque = int(g["startup"]) + int(g["active"]) + int(g["recovery"])
	if not no_chao:
		vel.x = 0.0
	_blocos_do_quadro()
	_sons_do_quadro()


func _processar_ataque(apertados: Dictionary) -> void:
	tempo += 1
	if tempo > total_ataque:
		_fim_do_golpe()
		return
	# REV logo depois de começar um golpe (soco fraco e depois o forte) vira o golpe forte na hora.
	if tempo <= REV_JANELA_COMBO:
		var rev: String = _rev_pedido(apertados)
		if rev != "" and _tentar_rev(rev):
			return
	_blocos_do_quadro()
	_sons_do_quadro()
	if _mov_frames > 0:
		vel.x = _mov_vx
		_mov_frames -= 1
	elif not no_chao:
		vel.x = 0.0
	_tentar_encadear(apertados)


func _mult_vel() -> float:
	return FLATLINE_VEL if flatline else 1.0


func _rev_pedido(apertados: Dictionary) -> String:
	if bool(apertados.get("REVP", false)):
		return "P"
	if bool(apertados.get("REVK", false)):
		return "K"
	return ""


# Executa o golpe forte (HP ou HK) direto na parte ativa. Devolve false se não deu.
func _tentar_rev(tipo: String) -> bool:
	if flatline:
		return false
	var botao: String = "HP" if tipo == "P" else "HK"
	var g: Dictionary = {}
	for x in golpes:
		var d: Dictionary = x
		if bool(d["base"]) and str(d["botao"]) == botao:
			g = d
			break
	if g.is_empty() or (bool(g["so_ar"]) and not no_chao):
		return false
	_executar(g)
	var inicio: int = int(g["startup"])
	for t in range(1, inicio + 1):
		tempo = t
		_blocos_do_quadro()
	tempo = inicio
	_sons_do_quadro()
	pulse_ocioso = 0
	pulse = minf(100.0, pulse + PULSE_POR_USO)
	if pulse >= 100.0:
		flatline = true
	eventos.append({"tipo": "rev", "golpe": {}})
	return true


func _bloco_do_tipo(g: Dictionary, tipo: String) -> Dictionary:
	for b in g.get("blocos", []):
		if str((b as Dictionary)["tipo"]) == tipo:
			return b
	return {}


func _golpe_por_nome(nome: String) -> Dictionary:
	for g in golpes:
		if str((g as Dictionary)["nome"]) == nome:
			return g
	return {}


# Blocos que acontecem num frame do golpe: mover, pular, parar e lançar magia.
func _blocos_do_quadro() -> void:
	for b in golpe_atual.get("blocos", []):
		var d: Dictionary = b
		var tipo: String = str(d["tipo"])
		if not d.has("quadro") or int(d["quadro"]) != tempo:
			continue
		match tipo:
			"mover":
				_mov_vx = float(d["vx"]) * (1.0 if direita else -1.0)
				_mov_frames = int(d["frames"])
			"pular":
				vel.y = -absf(float(d["vy"]))
				no_chao = true
			"parar":
				_mov_frames = 0
				vel.x = 0.0
			"projetil":
				eventos.append({"tipo": "projetil", "golpe": golpe_atual, "bloco": d})


# Sons marcados em sprites do golpe: tocam quando o sprite aparece.
func _sons_do_quadro() -> void:
	var sons: Array = golpe_atual.get("sons_quadros", [])
	if sons.is_empty():
		return
	var idx: int = Formato.indice_no_tempo(golpe_atual, tempo)
	if idx == _ultimo_idx_som:
		return
	_ultimo_idx_som = idx
	for s in sons:
		if int((s as Dictionary)["quadro"]) == maxi(idx, 0):
			eventos.append({"tipo": "som_quadro", "golpe": {}, "arquivo": str((s as Dictionary)["arquivo"])})


# Golpe que "começa de outro": a partir do fim do startup, se o botão dele for apertado.
func _tentar_encadear(apertados: Dictionary) -> void:
	if _cadeia >= 6 or tempo < int(golpe_atual["startup"]):
		return
	for g in golpes:
		var d: Dictionary = g
		var b: Dictionary = _bloco_do_tipo(d, "comecar_de")
		if b.is_empty() or str(b["golpe"]) != str(golpe_atual["nome"]):
			continue
		if str(b["quando"]) == "acertar" and not golpe_acertou:
			continue
		if not apertados.get(d["botao"], false):
			continue
		if bool(d["so_ar"]) and not no_chao:
			continue
		if float(d["custo"]) > barra.valor:
			continue
		_cadeia += 1
		_executar(d, true)
		return


# Fim do golpe: bloco "Quando o golpe terminar" (subir ou ir para outro golpe).
func _fim_do_golpe() -> void:
	var g: Dictionary = golpe_atual
	golpe_atual = {}
	tempo = 0
	_mov_frames = 0
	estado = Estado.PULANDO if no_chao else Estado.PARADO
	var b: Dictionary = _bloco_do_tipo(g, "ao_fim")
	if b.is_empty():
		return
	if str(b["acao"]) == "subir":
		vel.y = -absf(float(b["vy"]))
		no_chao = true
		estado = Estado.PULANDO
		eventos.append({"tipo": "pulo", "golpe": {}})
	elif _cadeia < 6:
		var alvo: Dictionary = _golpe_por_nome(str(b["golpe"]))
		if not alvo.is_empty():
			_cadeia += 1
			_executar(alvo, true)


# Decolagem: começa no chão, sem movimento. Ao fim, decide alto ou baixo pelo cima
# (ainda segurado = alto; já solto = baixo) e sai com a direção escolhida no início.
func _iniciar_decolagem(dir: Vector2) -> void:
	pulo_sombra = frames_desde_baixo <= JANELA_PULO_SOMBRA
	pulo_direcao_x = dir.x if absf(dir.x) > DIRECAO_SALTO_MIN else 0.0
	estado = Estado.DECOLANDO
	tempo = 0
	duracao = DECOLAGEM_SOMBRA if pulo_sombra else DECOLAGEM_NORMAL
	vel = Vector2.ZERO


func _processar_decolagem(dir: Vector2) -> void:
	tempo += 1
	vel.x = 0.0
	if tempo < duracao:
		return
	var alto: bool = dir.y < -0.5
	if pulo_sombra:
		vel.y = VEL_SOMBRA_ALTO if alto else VEL_SOMBRA_BAIXO
	else:
		vel.y = VEL_NORMAL_ALTO if alto else VEL_NORMAL_BAIXO
	vel.x = pulo_direcao_x * VEL_ANDAR * _mult_vel()
	no_chao = true
	eventos.append({"tipo": "pulo", "golpe": {}})
	estado = Estado.PULANDO
	tempo = 0
	duracao = 0


func _iniciar_esquiva(dir: Vector2) -> void:
	var frente: float = 1.0 if direita else -1.0
	esquiva_dir = -frente if dir.x * frente < -0.5 else frente
	esquiva_trava = ESQUIVA_FRAMES + ESQUIVA_RECARGA
	eventos.append({"tipo": "esquiva", "golpe": {}})
	estado = Estado.ESQUIVANDO
	tempo = 0
	duracao = ESQUIVA_FRAMES
	golpe_atual = {}
	bloqueado = false
	vel.x = esquiva_dir * ESQUIVA_VEL


func _processar_temporizado() -> void:
	tempo += 1
	if estado == Estado.ESQUIVANDO:
		vel.x = esquiva_dir * ESQUIVA_VEL
	elif estado == Estado.GUARDA_QUEBRADA:
		vel.x *= 0.85
		guarda = GUARDA_MAX * float(tempo) / float(maxi(1, duracao))
	else:
		vel.x = 0.0
	if tempo >= duracao:
		_voltar_neutro()


func _processar_caido(apertados: Dictionary) -> void:
	tempo += 1
	vel.x *= 0.85
	if caido_recuperavel and apertados.get("ESQ", false) and barra.valor >= CUSTO_LEVANTAR:
		barra.gastar(CUSTO_LEVANTAR)
		estado = Estado.LEVANTANDO
		tempo = 0
		duracao = ESQUIVA_FRAMES
		vel.x = 0.0
		return
	if tempo >= duracao:
		estado = Estado.LEVANTANDO
		tempo = 0
		duracao = LEVANTAR_FRAMES
		vel.x = 0.0


func _processar_golpeado() -> void:
	tempo += 1
	vel.x *= 0.85
	if tempo >= duracao:
		_voltar_neutro()


func _voltar_neutro() -> void:
	estado = Estado.PULANDO if no_chao else Estado.PARADO
	tempo = 0
	duracao = 0
	bloqueado = false
	golpe_atual = {}


# Janela de just defense: abre quando o "trás" é apertado de novo (soltou e apertou).
func _atualizar_parry(tras_novo: bool, atras: bool) -> void:
	_tras_antes = atras
	if parry_trava > 0:
		parry_trava -= 1
	if parry_janela > 0:
		parry_janela -= 1
		if parry_janela == 0:
			parry_trava = PARRY_RECARGA
	elif tras_novo and parry_trava == 0 and estado in [Estado.PARADO, Estado.ANDANDO, Estado.PULANDO, Estado.DEFENDENDO]:
		parry_janela = JANELA_PARRY


func _guard_cancel() -> void:
	barra.gastar(CUSTO_GUARD_CANCEL)
	var sentido: float = 1.0 if oponente.pos.x > pos.x else -1.0
	oponente.receber_blowback(sentido * 300.0)
	_voltar_neutro()

# ---------- Hitbox e colisão (quem decide o acerto é a Luta) ----------

func corpo_rect() -> Rect2:
	var w: float = largura_corpo()
	var h: float = altura_corpo()
	return Rect2(pos.x - w * 0.5, pos.y - h, w, h)


func hitbox_ativa() -> bool:
	if estado != Estado.ATACANDO or golpe_atual.is_empty():
		return false
	var inicio: int = int(golpe_atual["startup"])
	var fim: int = inicio + int(golpe_atual["active"])
	return tempo > inicio and tempo <= fim


# Hitbox na escala do personagem. Virado para a esquerda, espelha em relação ao corpo.
func hitbox_rect() -> Rect2:
	if not hitbox_ativa():
		return Rect2()
	var hb: Dictionary = golpe_atual["hitbox"]
	var x_rel: float = float(hb["x"]) * escala
	var w: float = float(hb["w"]) * escala
	var x: float = pos.x + x_rel if direita else pos.x - x_rel - w
	return Rect2(x, pos.y + float(hb["y"]) * escala, w, float(hb["h"]) * escala)


func resultado_para(g: Dictionary) -> String:
	if estado == Estado.ESQUIVANDO or estado == Estado.LEVANTANDO or estado == Estado.KO or estado == Estado.PARRY:
		return "nada"
	var antichao: bool = g["antichao"]
	if estado == Estado.CAIDO:
		return "acerto" if antichao else "nada"
	if antichao:
		return "nada"
	if bloqueando and parry_janela > 0:
		return "parry"
	if bloqueando:
		return "bloqueio"
	return "acerto"


# Just defense: sem dano, sem gastar a barra de defesa.
func receber_parry(_g: Dictionary) -> void:
	estado = Estado.PARRY
	tempo = 0
	duracao = PARRY_FRAMES
	bloqueado = false
	golpe_atual = {}
	vel.x = 0.0
	parry_janela = 0
	parry_trava = 0
	parry_aviso = PARRY_AVISO
	eventos.append({"tipo": "parry", "golpe": {}})


func _quebrar_guarda() -> void:
	estado = Estado.GUARDA_QUEBRADA
	tempo = 0
	duracao = GUARDA_QUEBRADA_FRAMES
	guarda = 0.0
	bloqueado = false
	golpe_atual = {}
	vel.x = _empurrao_base() * 60.0
	guarda_aviso = PARRY_AVISO
	eventos.append({"tipo": "guarda_quebrada", "golpe": {}})


func receber_bloqueio(g: Dictionary) -> void:
	frames_sem_guarda = 0
	var custo_guarda: float = float(GUARDA_CUSTO.get(int(g["forca"]), 14.0))
	if flatline:
		custo_guarda *= FLATLINE_GUARDA
	guarda -= custo_guarda
	if guarda <= 0.0:
		_quebrar_guarda()
		return
	eventos.append({"tipo": "bloqueio", "golpe": g})
	estado = Estado.GOLPEADO
	tempo = 0
	duracao = BLOQUEIO
	bloqueado = true
	golpe_atual = {}
	vel.x = _empurrao_base() * 60.0


func receber_acerto(g: Dictionary, dano: float) -> void:
	var era_caido: bool = estado == Estado.CAIDO
	vida = maxf(0.0, vida - dano)
	golpe_atual = {}
	bloqueado = false
	tempo = 0
	if vida <= 0.0:
		estado = Estado.KO
		vel.x = 0.0
		return
	var blowoff: bool = g["blowoff"]
	var knock: bool = era_caido or bool(g["antichao"]) or blowoff or int(g["forca"]) >= 3
	reacao = _classificar_reacao(g, knock)
	eventos.append({"tipo": "acerto", "golpe": g})
	if knock:
		estado = Estado.CAIDO
		duracao = CAIDO_BLOWOFF if blowoff else CAIDO_FRAMES
		caido_recuperavel = not blowoff
		vel.x = 0.0 if era_caido else _empurrao_base() * 120.0
	else:
		estado = Estado.GOLPEADO
		duracao = HITSTUN
		vel.x = _empurrao_base() * 60.0


# Onde o golpe pegou, pela altura do centro da hitbox: baixo, medio ou alto.
# Golpe baixo que derruba vira "rasteira".
func _classificar_reacao(g: Dictionary, derrubou: bool) -> String:
	var hb: Dictionary = g["hitbox"]
	var centro: float = -(float(hb["y"]) + float(hb["h"]) * 0.5)
	var rel: float = centro / CORPO_ALTURA
	if rel < 0.35:
		return "rasteira" if derrubou else "baixo"
	if rel < 0.7:
		return "medio"
	return "alto"


# Nome da animação (SLOTS do Formato) para o estado atual. "" = animação do golpe.
func slot_animacao() -> String:
	match estado:
		Estado.PARADO:
			return "parado"
		Estado.ANDANDO:
			return "andando"
		Estado.PULANDO, Estado.DECOLANDO:
			return "pulando"
		Estado.DEFENDENDO:
			return "defendendo"
		Estado.GOLPEADO:
			return "bloqueio" if bloqueado else "golpeado_" + reacao
		Estado.CAIDO:
			return "rasteira" if reacao == "rasteira" else "caido"
		Estado.LEVANTANDO:
			return "levantando"
		Estado.ESQUIVANDO:
			return "esquiva"
		Estado.KO:
			return "ko"
		Estado.PARRY:
			return "parry"
		Estado.GUARDA_QUEBRADA:
			return "guarda_quebrada"
	return ""


func receber_blowback(vx: float) -> void:
	reacao = "medio"
	estado = Estado.GOLPEADO
	tempo = 0
	duracao = HITSTUN_BLOWBACK
	bloqueado = false
	golpe_atual = {}
	vel.x = vx


func _empurrao_base() -> float:
	# Empurra para trás, já que o personagem está virado para o oponente
	return -1.0 if direita else 1.0

# ---------- Física e utilidades ----------

func _aplicar_fisica() -> void:
	if no_chao:
		vel.y += GRAVIDADE * DT
	pos += vel * DT
	if pos.y >= CHAO_Y:
		pos.y = CHAO_Y
		if no_chao:
			no_chao = false
			vel.y = 0.0
			# Pouso: deslize horizontal do pulo ou do ataque aéreo para no chão.
			if estado == Estado.PULANDO or estado == Estado.ATACANDO:
				vel.x = 0.0
			if estado == Estado.PULANDO:
				estado = Estado.PARADO
	pos.x = clampf(pos.x, LIMITE_ESQ, LIMITE_DIR)


func nome_estado() -> String:
	return NOMES_ESTADO[estado]