extends Control
## O quadro de cortiça da equipe. Desenhado inteiro em _draw (barato no celular) e com
## interação de toque: arrastar carta, arrastar o fundo para mover, pinça para zoom,
## tocar carta para selecionar, tocar o nó do fio para abrir a ligação.
## Não fala com o servidor sozinho: emite sinais e a tela decide o que pedir.

signal card_tapped(ref: String)
signal link_tapped(id: String)
signal empty_tapped
signal card_moved(ref: String, pos: Vector2)   # pos normalizada 0..1

const BOARD := Vector2(1500, 1500)
const SIZES := {
	"pessoa": Vector2(176, 228), "lugar": Vector2(210, 116), "fato": Vector2(236, 132), "pista": Vector2(216, 146),
}
const DRAG_START := 14.0

var cards: Array = []        # [{ref,x,y}]
var links: Array = []        # [{id,a,b,type,evidence}]
var readonly := false
var selected_ref := ""
var selected_link := ""
var link_from := ""          # carta de origem enquanto escolhe o destino
var highlight_refs: Array = []
var zoom := 0.55
var offset := Vector2(40, 40)

var _press := false
var _press_pos := Vector2.ZERO
var _press_card := ""
var _dragging := false
var _panning := false
var _drag_card_off := Vector2.ZERO
var _touches := {}
var _pinch_d := 0.0
var _pinch_zoom := 1.0
var _tex_cache := {}
var _t := 0.0
var _fitted := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(func() -> void:
		if not _fitted and size.x > 10:
			fit()
			_fitted = true)


func _process(dt: float) -> void:
	_t += dt
	if link_from != "" or not highlight_refs.is_empty():
		queue_redraw()


func set_data(new_cards: Array, new_links: Array) -> void:
	# não sobrescreve a carta que este dedo está arrastando agora
	if _dragging and _press_card != "":
		var mine: Dictionary = {}
		for c in cards:
			if c["ref"] == _press_card:
				mine = c
		cards = new_cards.duplicate(true)
		for c in cards:
			if c["ref"] == _press_card and not mine.is_empty():
				c["x"] = mine["x"]; c["y"] = mine["y"]
	else:
		cards = new_cards.duplicate(true)
	links = new_links.duplicate(true)
	if selected_ref != "" and not _has_card(selected_ref):
		selected_ref = ""
	if selected_link != "" and _link(selected_link).is_empty():
		selected_link = ""
	queue_redraw()


func fit() -> void:
	# enquadra as cartas fixadas (ou o quadro todo se vazio)
	var r := Rect2()
	var first := true
	for c in cards:
		var cr := _card_rect(c)
		r = cr if first else r.merge(cr)
		first = false
	if first:
		r = Rect2(Vector2(200, 200), BOARD - Vector2(400, 400))
	r = r.grow(80)
	zoom = clampf(minf(size.x / r.size.x, size.y / r.size.y), 0.3, 1.4)
	offset = size / 2.0 - r.get_center() * zoom
	queue_redraw()


func free_spot() -> Vector2:
	# onde fixar a próxima carta: centro da vista atual, com leve espalhamento
	var center := (size / 2.0 - offset) / zoom
	center += Vector2(randf_range(-90, 90), randf_range(-90, 90))
	return Vector2(clampf(center.x / BOARD.x, 0.06, 0.94), clampf(center.y / BOARD.y, 0.06, 0.94))


# ------------------------------------------------------------------ geometria
func _kind(ref: String) -> String:
	if ref.begins_with("c:"):
		return "pista"
	var c := Net.card_by_id(ref.substr(2))
	return str(c.get("kind", "fato"))


func _card_rect(c: Dictionary) -> Rect2:
	var s: Vector2 = SIZES.get(_kind(c["ref"]), SIZES["fato"])
	var p := Vector2(float(c["x"]), float(c["y"])) * BOARD
	return Rect2(p - s / 2.0, s)


func _has_card(ref: String) -> bool:
	for c in cards:
		if c["ref"] == ref:
			return true
	return false


func _card(ref: String) -> Dictionary:
	for c in cards:
		if c["ref"] == ref:
			return c
	return {}


func _link(id: String) -> Dictionary:
	for l in links:
		if l["id"] == id:
			return l
	return {}


func _center(ref: String) -> Vector2:
	var c := _card(ref)
	if c.is_empty():
		return Vector2.ZERO
	return Vector2(float(c["x"]), float(c["y"])) * BOARD


func _link_points(l: Dictionary) -> PackedVector2Array:
	var a := _center("p:" + str(l["a"]))
	var b := _center("p:" + str(l["b"]))
	# fio frouxo: curva que cai um pouco, como barbante de verdade
	var mid := (a + b) / 2.0 + Vector2(0, clampf(a.distance_to(b) * 0.08, 10, 60))
	var pts := PackedVector2Array()
	for i in 17:
		var t := i / 16.0
		pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	return pts


func _knot(l: Dictionary) -> Vector2:
	var pts := _link_points(l)
	return pts[8]


func to_board(screen: Vector2) -> Vector2:
	return (screen - offset) / zoom


func _hit_card(bp: Vector2) -> String:
	for i in range(cards.size() - 1, -1, -1):
		if _card_rect(cards[i]).grow(6).has_point(bp):
			return cards[i]["ref"]
	return ""


func _hit_link(bp: Vector2) -> String:
	var best := ""
	var bd := 46.0 / maxf(zoom, 0.4)
	for l in links:
		var d := _knot(l).distance_to(bp)
		if d < bd:
			bd = d
			best = l["id"]
	return best


# ------------------------------------------------------------------ entrada
func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		if _touches.size() == 2:
			var ps: Array = _touches.values()
			_pinch_d = (ps[0] as Vector2).distance_to(ps[1])
			_pinch_zoom = zoom
			_cancel_press()
		accept_event()
		return
	if e is InputEventScreenDrag:
		var sd := e as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() == 2 and _pinch_d > 0.0:
			var ps: Array = _touches.values()
			var d := (ps[0] as Vector2).distance_to(ps[1])
			var center := ((ps[0] as Vector2) + (ps[1] as Vector2)) / 2.0
			_zoom_at(center, _pinch_zoom * d / _pinch_d)
		accept_event()
		return
	if _touches.size() >= 2:
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, zoom * 1.1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, zoom / 1.1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = true
				_dragging = false
				_panning = false
				_press_pos = mb.position
				var bp := to_board(mb.position)
				_press_card = _hit_card(bp)
				if _press_card != "":
					_drag_card_off = _center(_press_card) - bp
			else:
				_release(mb.position)
		accept_event()
	elif e is InputEventMouseMotion and _press:
		var mm := e as InputEventMouseMotion
		if not _dragging and not _panning and mm.position.distance_to(_press_pos) > DRAG_START:
			if _press_card != "" and not readonly and link_from == "":
				_dragging = true
				Sfx.play("card_pick", -6.0)
			else:
				_panning = true
		if _dragging:
			var bp := to_board(mm.position) + _drag_card_off
			var c := _card(_press_card)
			c["x"] = clampf(bp.x / BOARD.x, 0.04, 0.96)
			c["y"] = clampf(bp.y / BOARD.y, 0.04, 0.96)
			# a carta arrastada vai para cima das outras
			cards.erase(c)
			cards.append(c)
			queue_redraw()
		elif _panning:
			offset += mm.relative
			queue_redraw()
		accept_event()


func _cancel_press() -> void:
	_press = false
	_dragging = false
	_panning = false


func _release(pos: Vector2) -> void:
	if not _press:
		return
	_press = false
	if _dragging:
		_dragging = false
		var c := _card(_press_card)
		Sfx.play("card_drop", -4.0)
		card_moved.emit(_press_card, Vector2(c["x"], c["y"]))
		return
	if _panning:
		_panning = false
		return
	var bp := to_board(pos)
	var lk := _hit_link(bp)
	var cr := _hit_card(bp)
	if cr != "":
		card_tapped.emit(cr)
	elif lk != "":
		link_tapped.emit(lk)
	else:
		empty_tapped.emit()


func _zoom_at(screen_pt: Vector2, z: float) -> void:
	z = clampf(z, 0.25, 2.0)
	var bp := to_board(screen_pt)
	zoom = z
	offset = screen_pt - bp * zoom
	queue_redraw()


# ------------------------------------------------------------------ desenho
func _draw() -> void:
	draw_set_transform(offset, 0.0, Vector2(zoom, zoom))
	# cortiça: base marrom com manchas em faixas (pintura, não foto) e moldura de madeira
	draw_rect(Rect2(Vector2(-30, -30), BOARD + Vector2(60, 60)), Color("#3b2416"))
	draw_rect(Rect2(Vector2.ZERO, BOARD), Color("#7a5236"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 220:
		var p := Vector2(rng.randf() * BOARD.x, rng.randf() * BOARD.y)
		var r := rng.randf_range(8, 46)
		draw_circle(p, r, Color("#8c613f") if i % 3 else Color("#6a4529", 0.8))
	for i in 900:
		var p := Vector2(rng.randf() * BOARD.x, rng.randf() * BOARD.y)
		draw_rect(Rect2(p, Vector2(3, 3)), Color("#4e3220", 0.55))
	# luz de abajur amarela num canto, sombra azul no outro (a mesma luz das cenas)
	draw_circle(BOARD * Vector2(0.78, 0.18), 520, Color(UI.YELLOW, 0.06))
	draw_circle(BOARD * Vector2(0.78, 0.18), 300, Color(UI.YELLOW, 0.05))
	draw_circle(BOARD * Vector2(0.1, 0.95), 600, Color(UI.NIGHT, 0.22))

	if cards.is_empty():
		var f := UI.font("marker")
		draw_string(f, Vector2(260, 700), "Quadro vazio. Fixe pessoas e pistas!", HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(UI.PAPER, 0.5))

	# fios
	for l in links:
		var pts := _link_points(l)
		var sel: bool = l["id"] == selected_link
		draw_polyline(pts, Color(0, 0, 0, 0.35), 9.0, true)
		draw_polyline(pts, UI.YELLOW if sel else UI.RED, 6.0 if sel else 5.0, true)
		draw_polyline(pts, Color(1, 1, 1, 0.25), 1.5, true)
		_draw_link_tag(l, pts, sel)

	# carta de origem piscando enquanto escolhe destino
	for c in cards:
		_draw_card(c)

	if link_from != "":
		var a := _center(link_from)
		var pulse := 0.5 + 0.5 * sin(_t * 6.0)
		draw_circle(a, 30 + pulse * 10, Color(UI.YELLOW, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_link_tag(l: Dictionary, pts: PackedVector2Array, sel: bool) -> void:
	var k := pts[8]
	var dir := (pts[10] - pts[6]).normalized()
	# seta de direção
	var tip := k + dir * 30
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * 24 + side * 13, tip - dir * 24 - side * 13]), UI.YELLOW if sel else UI.RED)
	# etiqueta de papel com o tipo de ligação
	var f := UI.font("marker")
	var txt := Net.link_label(str(l["type"]))
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 22
	var r := Rect2(k - Vector2(w / 2.0, 46), Vector2(w, 34))
	draw_rect(Rect2(r.position + Vector2(3, 3), r.size), Color(0, 0, 0, 0.3))
	draw_rect(r, UI.PAPER if not sel else UI.YELLOW)
	draw_string(f, r.position + Vector2(11, 25), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UI.INK)
	# prova presa no fio: bilhetinho amarelo com clipe
	if l.get("evidence") != null:
		var e := Rect2(k + Vector2(-26, 2), Vector2(52, 40))
		draw_rect(Rect2(e.position + Vector2(3, 3), e.size), Color(0, 0, 0, 0.3))
		draw_rect(e, UI.YELLOW)
		draw_string(UI.font("title"), e.position + Vector2(6, 30), "PROVA", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.INK)
		draw_rect(Rect2(e.position + Vector2(20, -8), Vector2(8, 18)), Color("#c8ccd8"))
	else:
		draw_circle(k + Vector2(0, 14), 9, Color(UI.PAPER, 0.85))
		draw_circle(k + Vector2(0, 14), 5, UI.RED)


func _portrait(id: String) -> Texture2D:
	if not _tex_cache.has(id):
		_tex_cache[id] = UI.portrait(id)
	return _tex_cache[id]


func _draw_card(c: Dictionary) -> void:
	var ref: String = c["ref"]
	var r := _card_rect(c)
	var kind := _kind(ref)
	var sel := ref == selected_ref or ref == link_from
	var hl := highlight_refs.has(ref)
	# leve rotação "à mão" estável por carta
	var tilt := (float(hash(ref) % 9) - 4.0) * 0.012
	draw_set_transform(offset + r.get_center() * zoom, tilt, Vector2(zoom, zoom))
	var lr := Rect2(-r.size / 2.0, r.size)
	draw_rect(Rect2(lr.position + Vector2(6, 8), lr.size), Color(0, 0, 0, 0.35))
	if sel or hl:
		draw_rect(lr.grow(7), UI.YELLOW if sel else Color(UI.YELLOW, 0.4 + 0.3 * sin(_t * 5.0)))
	var f_m := UI.font("marker")
	var f_t := UI.font("type")
	match kind:
		"pessoa":
			var card := Net.card_by_id(ref.substr(2))
			draw_rect(lr, Color("#f3ecdc"))
			var ph := Rect2(lr.position + Vector2(10, 10), Vector2(lr.size.x - 20, lr.size.y - 62))
			draw_rect(ph, Color("#1b2650"))
			var tex := _portrait(ref.substr(2))
			if tex:
				draw_texture_rect(tex, ph, false)
			else:
				_draw_silhouette(ph, card)
			var nm := str(card.get("name", "?"))
			draw_string(f_m, Vector2(lr.position.x + 8, lr.end.y - 18), nm, HORIZONTAL_ALIGNMENT_CENTER, lr.size.x - 16, _fit_size(f_m, nm, lr.size.x - 16, 30), UI.INK)
		"lugar":
			var card := Net.card_by_id(ref.substr(2))
			draw_rect(lr, Color("#cfe0f5"))
			draw_rect(Rect2(lr.position, Vector2(lr.size.x, 28)), UI.SKY)
			draw_string(UI.font("title"), lr.position + Vector2(10, 23), "LUGAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UI.PAPER)
			draw_multiline_string(f_m, lr.position + Vector2(10, 58), str(card.get("name", "?")), HORIZONTAL_ALIGNMENT_LEFT, lr.size.x - 20, 24, 2, UI.INK)
		"fato":
			var card := Net.card_by_id(ref.substr(2))
			draw_rect(lr, Color("#fff4c4"))
			for i in 4:
				draw_line(lr.position + Vector2(8, 44 + i * 22), lr.position + Vector2(lr.size.x - 8, 44 + i * 22), Color(UI.SKY, 0.35), 1.5)
			draw_line(lr.position + Vector2(30, 0), lr.position + Vector2(30, lr.size.y), Color(UI.RED, 0.4), 1.5)
			draw_string(UI.font("title"), lr.position + Vector2(36, 26), "FATO", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UI.RED)
			draw_multiline_string(f_m, lr.position + Vector2(36, 54), UI.strip_emoji(str(card.get("name", "?"))), HORIZONTAL_ALIGNMENT_LEFT, lr.size.x - 46, 21, 3, UI.INK)
		"pista":
			var clue := Net.clue_by_id(ref.substr(2))
			var col := UI.clue_color(str(clue.get("kind", "")))
			draw_rect(lr, UI.PAPER)
			draw_rect(Rect2(lr.position, Vector2(lr.size.x, 30)), col)
			draw_string(UI.font("title"), lr.position + Vector2(10, 24), UI.clue_tag(str(clue.get("kind", ""))) + ("  " + str(clue.get("time", "")) if clue.get("time", "") != "" else ""), HORIZONTAL_ALIGNMENT_LEFT, lr.size.x - 16, 23, UI.INK)
			draw_multiline_string(f_t, lr.position + Vector2(10, 56), UI.strip_emoji(str(clue.get("title", "Pista"))), HORIZONTAL_ALIGNMENT_LEFT, lr.size.x - 20, 20, 3, UI.INK)
	# tachinha
	var pin := Vector2(0, lr.position.y + 6)
	draw_circle(pin + Vector2(2, 3), 11, Color(0, 0, 0, 0.35))
	draw_circle(pin, 11, UI.RED if kind != "pista" else UI.YELLOW.darkened(0.1))
	draw_circle(pin + Vector2(-3, -3), 4, Color(1, 1, 1, 0.6))
	draw_set_transform(offset, 0.0, Vector2(zoom, zoom))


func _fit_size(f: Font, txt: String, w: float, base: int) -> int:
	var s := base
	while s > 14 and f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > w:
		s -= 2
	return s


func _draw_silhouette(ph: Rect2, card: Dictionary) -> void:
	# retrato provisório pintado à mão em código: busto em contraluz com a cor da roupa
	var look: Dictionary = card.get("look", {})
	var top := Color(str(look.get("top", "#4e6fc0")))
	var skin := Color(str(look.get("skin", "#c98d6b")))
	var hair := Color(str(look.get("hair_color", "#1c1830")))
	var c := ph.get_center()
	draw_rect(ph, Color("#26407a"))
	draw_circle(ph.position + Vector2(ph.size.x * 0.8, ph.size.y * 0.2), ph.size.x * 0.35, Color(UI.YELLOW, 0.18))
	draw_colored_polygon(PackedVector2Array([
		Vector2(ph.position.x + 8, ph.end.y), Vector2(c.x - 40, c.y + 24), Vector2(c.x + 40, c.y + 24), Vector2(ph.end.x - 8, ph.end.y)]), top)
	draw_circle(Vector2(c.x, c.y - 6), 30, skin.darkened(0.35))
	draw_circle(Vector2(c.x - 6, c.y - 10), 26, skin)
	draw_circle(Vector2(c.x, c.y - 26), 28, hair)
	draw_rect(Rect2(c.x - 30, c.y - 30, 60, 10), hair)
