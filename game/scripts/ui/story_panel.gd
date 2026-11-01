class_name StoryPanel
extends RefCounted
## A história que o quadro conta, em quadrinhos noir: cada fio vira uma CENA com narração,
## duas polaroides presas por barbante vermelho (com a ação na etiqueta), a fala da prova num
## balão e um carimbo de borracha (PROVADO / PALPITE). O aluno lê e julga se faz sentido.

const BACKDROP := preload("res://shaders/backdrop.gdshader")


static func _name(id: String) -> String:
	return UI.strip_emoji(str(Net.card_by_id(id).get("name", id)))


static func _tex_for(id: String, on_ready: Callable) -> Texture2D:
	var card := Net.card_by_id(id)
	var kind := str(card.get("kind", "pessoa"))
	if kind == "pessoa":
		return UI.portrait(id)
	var key := ("scene:" + str(card.get("scene", id))) if kind == "lugar" else ("item:" + ItemModels.kind_for(card))
	var t := Snap.get_tex(key)
	if t == null:
		Snap.photo_ready.connect(func(k: String) -> void:
			if k == key:
				on_ready.call(), CONNECT_ONE_SHOT)
	return t


static func _quote(clue: Dictionary, speaker: String) -> String:
	if clue.has("chat"):
		for l in clue["chat"].get("lines", []):
			if str(l.get("who", "")) == speaker:
				return UI.strip_emoji(str(l.get("text", "")))
		var ls: Array = clue["chat"].get("lines", [])
		if not ls.is_empty():
			return UI.strip_emoji(str(ls[0].get("text", "")))
	if clue.has("dialogue") and not (clue["dialogue"] as Array).is_empty():
		return UI.strip_emoji(str(clue["dialogue"][0].get("text", "")))
	var t := UI.strip_emoji(str(clue.get("text", ""))).replace("\n", " ")
	return t.substr(0, 130) + ("..." if t.length() > 130 else "")


## Uma CENA (um fio).
static func panel(l: Dictionary, index := 0) -> Control:
	var a := str(l["a"])
	var b := str(l["b"])
	var ev: Variant = l.get("evidence")
	var clue: Dictionary = Net.clue_by_id(str(ev)) if ev != null else {}
	var outer := PanelContainer.new()
	outer.add_theme_stylebox_override("panel", UI.box(UI.INK, UI.PAPER, 4, 4, 0))
	# fundo da cena: noite com chuva e retícula; se um dos lados é um lugar, a foto da sala
	var bg := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = BACKDROP
	mat.set_shader_parameter("rain_amount", 0.7)
	mat.set_shader_parameter("px_size", Vector2(640, 420))
	bg.material = mat
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(bg)
	var place := a if str(Net.card_by_id(a).get("kind", "")) == "lugar" else (b if str(Net.card_by_id(b).get("kind", "")) == "lugar" else "")
	if place != "":
		var ph := TextureRect.new()
		ph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		ph.modulate = Color(1, 1, 1, 0.45)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ph.texture = _tex_for(place, func() -> void:
			if is_instance_valid(ph):
				ph.texture = _tex_for(place, func() -> void: pass))
		outer.add_child(ph)
	var m := UI.margin(14, 12, 14)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(m)
	var v := UI.vbox(8)
	m.add_child(v)
	# claquete + narração
	var top := UI.hbox(8)
	if index > 0:
		var slate := PanelContainer.new()
		slate.add_theme_stylebox_override("panel", UI.box(UI.PAPER, UI.INK, 3, 3, 8))
		var sl := UI.title("CENA %d" % index, 24, UI.INK)
		sl.autowrap_mode = TextServer.AUTOWRAP_OFF
		slate.add_child(sl)
		slate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		top.add_child(slate)
	var cap := PanelContainer.new()
	cap.add_theme_stylebox_override("panel", UI.box(UI.YELLOW, UI.INK, 3, 2, 10))
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var time := str(clue.get("time", ""))
	var narr := ("%s.  " % time if time != "" else "") + "%s %s %s." % [_name(a), Net.link_label(str(l["type"])), _name(b)]
	cap.add_child(UI.label(narr, 22, UI.INK, "type"))
	top.add_child(cap)
	v.add_child(top)
	# polaroides com barbante vermelho
	var duo := Duo.new()
	duo.a = a
	duo.b = b
	duo.verb = Net.link_label(str(l["type"])).to_upper()
	duo.color = BoardColors.of(str(l.get("color", "vermelho")))
	duo.custom_minimum_size = Vector2(0, 270)
	v.add_child(duo)
	if not clue.is_empty():
		# balão saindo de quem fez a ação
		var bub := Bubble.new()
		bub.text = "\"" + _quote(clue, a) + "\""
		v.add_child(bub)
	var st := Stamp.new()
	st.proved = not clue.is_empty()
	st.sub = UI.strip_emoji(str(clue.get("title", ""))).to_upper() if not clue.is_empty() else "AINDA SEM PROVA"
	st.custom_minimum_size = Vector2(0, 70)
	v.add_child(st)
	return outer


## A história inteira, em ordem de hora (quando há), terminando no culpado.
static func story(links: Array, culprit := "") -> Control:
	var v := UI.vbox(18)
	var head := Paper.make("card", true)
	var hv := UI.vbox(2)
	hv.add_child(UI.label("ARQUIVO DO CASO", 18, Color(UI.INK, 0.6), "type"))
	hv.add_child(UI.title("A HISTÓRIA QUE O QUADRO CONTA", 40, UI.RED))
	hv.add_child(UI.label("Esta é a VERSÃO DE VOCÊS, montada no quadro. Pode estar certa ou errada. Leiam como uma história: faz sentido do começo ao fim? A prova de cada cena mostra mesmo aquilo?", 20, UI.INK))
	head.add_child(hv)
	v.add_child(head)
	# elenco: o que a equipe marcou em cada pessoa (inocente, suspeito, mentiu, tem álibi)
	var groups := {"suspeito": [], "mentiu": [], "alibi": [], "inocente": []}
	for c in Net.state.get("board", {}).get("cards", []):
		var tg = c.get("tag")
		if tg != null and groups.has(str(tg)):
			groups[str(tg)].append(UI.strip_emoji(str(Net.card_by_id(str(c["ref"]).substr(2)).get("name", ""))))
	var any := false
	for k in groups:
		if not (groups[k] as Array).is_empty():
			any = true
	if any:
		var cast := Paper.make("notebook")
		var cv := UI.vbox(4)
		cv.add_child(UI.label("O ELENCO SEGUNDO VOCÊS", 18, Color(UI.INK, 0.6), "type"))
		for k in [["suspeito", "Suspeitos", "#a87a10"], ["mentiu", "Mentiram", "#c42c3f"], ["alibi", "Têm álibi", "#2f6fb0"], ["inocente", "Inocentes", "#2f8f55"]]:
			var names: Array = groups[k[0]]
			if not names.is_empty():
				cv.add_child(UI.label("%s: %s" % [k[1], ", ".join(names)], 22, Color(str(k[2])), "bold"))
		cast.add_child(cv)
		v.add_child(cast)
	if links.is_empty():
		v.add_child(UI.label("O quadro ainda não tem fios. Ligue as cartas e a história aparece aqui.", 24, UI.PAPER, "type"))
		return v
	var ordered := links.duplicate()
	ordered.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var tx := str(Net.clue_by_id(str(x.get("evidence", ""))).get("time", "99h99")) if x.get("evidence") != null else "99h99"
		var ty := str(Net.clue_by_id(str(y.get("evidence", ""))).get("time", "99h99")) if y.get("evidence") != null else "99h99"
		return tx < ty)
	var n := 0
	for l in ordered:
		n += 1
		v.add_child(panel(l, n))
	var end := PanelContainer.new()
	end.add_theme_stylebox_override("panel", UI.box(UI.NIGHT, UI.PINK, 4, 4, 18))
	var ev := UI.vbox(8)
	ev.add_child(UI.title("CENA FINAL:  E O CULPADO FOI..." + ("" if culprit != "" else "?"), 32, UI.PINK))
	if culprit != "":
		var duo := Duo.new()
		duo.a = culprit
		duo.solo = true
		duo.custom_minimum_size = Vector2(0, 230)
		ev.add_child(duo)
	else:
		ev.add_child(UI.label("Vocês apontam o culpado na hora de apresentar a teoria.", 21, UI.MIST))
	end.add_child(ev)
	v.add_child(end)
	return v


class BoardColors:
	static func of(name: String) -> Color:
		return {"vermelho": Color("#e2384f"), "amarelo": Color("#ffc83d"), "azul": Color("#4e9bff"), "verde": Color("#5fd38a"), "rosa": Color("#ff6fae")}.get(name, Color("#e2384f"))


## duas polaroides tortas com fita, barbante entre elas com tachinhas e etiqueta da ação
class Duo extends Control:
	var a := ""
	var b := ""
	var verb := ""
	var color := Color("#e2384f")
	var solo := false
	var _ta: Texture2D
	var _tb: Texture2D

	func _ready() -> void:
		_ta = StoryPanel._tex_for(a, func() -> void:
			_ta = StoryPanel._tex_for(a, func() -> void: pass)
			queue_redraw())
		if not solo:
			_tb = StoryPanel._tex_for(b, func() -> void:
				_tb = StoryPanel._tex_for(b, func() -> void: pass)
				queue_redraw())
		resized.connect(queue_redraw)

	func _polaroid(c: Vector2, tex: Texture2D, nm: String, tilt: float) -> void:
		var w := minf(size.x * 0.34, 190.0)
		var h := w * 1.18
		draw_set_transform(c, tilt, Vector2.ONE)
		var r := Rect2(-w / 2.0, -h / 2.0, w, h)
		draw_rect(Rect2(r.position + Vector2(6, 8), r.size), Color(0, 0, 0, 0.45))
		draw_rect(r, Color("#fbfaf6"))
		var ph := Rect2(r.position + Vector2(9, 9), Vector2(w - 18, h - 52))
		draw_rect(ph, Color("#26407a"))
		if tex:
			draw_texture_rect(tex, ph, false)
		draw_string(UI.font("marker"), Vector2(r.position.x + 6, r.end.y - 14), nm, HORIZONTAL_ALIGNMENT_CENTER, w - 12, 20, UI.INK)
		# fita adesiva no topo
		draw_rect(Rect2(-28, r.position.y - 10, 56, 20), Color(1, 1, 0.9, 0.6))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw() -> void:
		var cy := size.y * 0.56
		var w := minf(size.x * 0.34, 190.0)
		var h := w * 1.18
		if solo:
			_polaroid(Vector2(size.x / 2.0, cy), _ta, StoryPanel._name(a), -0.03)
			return
		var pa := Vector2(size.x * 0.2, cy)
		var pb := Vector2(size.x * 0.8, cy)
		# barbante com leve barriga, de tachinha a tachinha
		# tachinhas no alto das fotos: o barbante passa por cima, sem cobrir os rostos
		var p1 := pa + Vector2(w * 0.28, -h / 2.0 + 14)
		var p2 := pb + Vector2(-w * 0.28, -h / 2.0 + 14)
		var mid := (p1 + p2) / 2.0 + Vector2(0, 22)
		var pts := PackedVector2Array()
		for i in 17:
			var t := i / 16.0
			pts.append(p1.lerp(mid, t).lerp(mid.lerp(p2, t), t))
		_polaroid(pa, _ta, StoryPanel._name(a), -0.05)
		_polaroid(pb, _tb, StoryPanel._name(b), 0.04)
		draw_polyline(pts, Color(0, 0, 0, 0.45), 8.0, true)
		draw_polyline(pts, color, 5.0, true)
		for p in [p1, p2]:
			draw_circle(p + Vector2(2, 3), 9, Color(0, 0, 0, 0.4))
			draw_circle(p, 9, color.darkened(0.15))
			draw_circle(p + Vector2(-3, -3), 3, Color(1, 1, 1, 0.6))
		# seta pequena no meio indicando o sentido
		var k := pts[8]
		var dir := (pts[10] - pts[6]).normalized()
		var side := Vector2(-dir.y, dir.x)
		var tip := k + dir * 26
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * 20 + side * 11, tip - dir * 20 - side * 11]), color)
		# etiqueta da ação
		var f := UI.font("title")
		var tw := f.get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x + 22
		var tr := Rect2(k + Vector2(-tw / 2.0, 14), Vector2(tw, 36))
		draw_rect(Rect2(tr.position + Vector2(3, 4), tr.size), Color(0, 0, 0, 0.4))
		draw_rect(tr, Color("#efe8d6"))
		draw_string(f, tr.position + Vector2(11, 28), verb, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UI.INK)


## balão de fala branco com rabicho apontando para a polaroide da esquerda (quem agiu)
class Bubble extends Control:
	var text := ""
	var _lab: Label

	func _ready() -> void:
		_lab = UI.label(text, 21, UI.INK, "bold")
		_lab.position = Vector2(22, 22)
		add_child(_lab)
		resized.connect(_relayout)
		_relayout.call_deferred()

	func _relayout() -> void:
		_lab.size = Vector2(size.x - 44, 0)
		_lab.custom_minimum_size.x = size.x - 44
		custom_minimum_size.y = _lab.get_combined_minimum_size().y + 40
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(6, 14), size - Vector2(12, 18))
		var tail := PackedVector2Array([Vector2(size.x * 0.16, 16), Vector2(size.x * 0.2, -6), Vector2(size.x * 0.27, 16)])
		draw_rect(Rect2(r.position + Vector2(4, 5), r.size), Color(0, 0, 0, 0.35))
		draw_colored_polygon(tail, UI.INK)
		draw_rect(r.grow(3), UI.INK)
		draw_rect(r, Color.WHITE)
		var inner := PackedVector2Array([Vector2(size.x * 0.17, 18), Vector2(size.x * 0.2, -1), Vector2(size.x * 0.26, 18)])
		draw_colored_polygon(inner, Color.WHITE)


## carimbo de borracha inclinado: PROVADO (verde) ou PALPITE (vermelho)
class Stamp extends Control:
	var proved := false
	var sub := ""

	func _draw() -> void:
		var col := Color("#3fcf7a") if proved else Color("#ff4f6a")
		# "COM PROVA" diz só que há uma pista presa: não diz se a ligação está certa
		var word := "COM PROVA" if proved else "PALPITE"
		var f := UI.font("title")
		var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		var sw := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var bw := maxf(w, sw) + 30
		var c := Vector2(size.x - bw / 2.0 - 10, size.y / 2.0)
		draw_set_transform(c, -0.08, Vector2.ONE)
		var r := Rect2(-bw / 2.0, -30, bw, 62)
		draw_rect(r, Color(col, 0.12))
		draw_rect(r, col, false, 4.0)
		draw_rect(r.grow(-6), col, false, 1.5)
		draw_string(f, Vector2(-w / 2.0, 6), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, col)
		draw_string(f, Vector2(-sw / 2.0, 25), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
