class_name ClueView
extends RefCounted
## Monta a pista do jeito que ela existiria no mundo do caso: conversa num app de mensagem,
## post de rede social, depoimento no caderno, registro impresso, bilhete em post-it, foto de objeto.
## Os apps são fictícios ("Papo" e "Flash"). Aceita o formato rico (chat/post) e o antigo (texto).

const Avatar := preload("res://scripts/ui/avatar.gd")


static func person_name(who: String) -> String:
	var c := Net.card_by_id(who)
	return UI.strip_emoji(str(c.get("name", who)))


static func build(clue: Dictionary) -> Control:
	var kind := str(clue.get("kind", ""))
	if clue.has("chat") or kind == "mensagem":
		return _chat(clue)
	if clue.has("post") or kind == "post":
		return _post(clue)
	match kind:
		"depoimento": return _testimony(clue)
		"registro": return _receipt(clue)
		"bilhete": return _sticky(clue)
		"objeto": return _polaroid(clue)
	return _testimony(clue)


# ------------------------------------------------------------------ app de conversa "Papo"
static func _chat_lines(clue: Dictionary) -> Array:
	if clue.has("chat"):
		return clue["chat"].get("lines", [])
	var out := []
	for line in UI.strip_emoji(str(clue.get("text", ""))).split("\n"):
		line = line.strip_edges()
		if line == "":
			continue
		var i := line.find(":")
		if i > 0 and i < 26:
			out.append({"who": line.substr(0, i).strip_edges(), "text": line.substr(i + 1).strip_edges()})
		else:
			out.append({"who": "", "text": line})
	return out


static func _chat(clue: Dictionary) -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UI.box(Color("#0b0f1c"), Color("#2a3352"), 3, 34, 10))
	var v := UI.vbox(0)
	frame.add_child(v)
	# barra do app
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _sb(Color("#1d2b55"), [26, 26, 0, 0], 14))
	var bh := UI.hbox(12)
	var lines := _chat_lines(clue)
	var group := str(clue.get("chat", {}).get("group", ""))
	if group == "":
		group = str(clue.get("title", "Conversa"))
	var ic := Avatar.new()
	ic.setup(str(clue.get("from", "")), 30, group)
	bh.add_child(ic)
	var gv := UI.vbox(0)
	gv.add_child(UI.label(UI.strip_emoji(group), 26, Color.WHITE, "bold"))
	gv.add_child(UI.label("Papo  ·  " + str(clue.get("time", "")), 18, Color("#9fb3e6")))
	bh.add_child(gv)
	bar.add_child(bh)
	v.add_child(bar)
	# conversa
	var body := PanelContainer.new()
	body.add_theme_stylebox_override("panel", _sb(Color("#dde4f0"), [0, 0, 26, 26], 16))
	var msgs := UI.vbox(12)
	body.add_child(msgs)
	var speakers := []
	for l in lines:
		var w := str(l.get("who", ""))
		if w != "" and not speakers.has(w):
			speakers.append(w)
	var two := speakers.size() == 2
	for l in lines:
		var who := str(l.get("who", ""))
		var right: bool = two and who == str(speakers[1])
		var row := UI.hbox(10)
		var av := Avatar.new()
		av.setup(who, 28, person_name(who))
		var bub := PanelContainer.new()
		bub.add_theme_stylebox_override("panel", _sb(Color("#fff3c4") if right else Color.WHITE, [20, 20, 20 if right else 20, 20], 14, Color(0, 0, 0, 0.12)))
		bub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bv := UI.vbox(2)
		if who != "" and not right:
			bv.add_child(UI.label(person_name(who), 19, Color("#2f5bb7"), "bold"))
		bv.add_child(UI.label(UI.strip_emoji(str(l.get("text", ""))), 25, Color("#16182a")))
		var tm := str(l.get("time", ""))
		if tm != "":
			var tl := UI.label(tm, 16, Color("#6b7390"))
			tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			bv.add_child(tl)
		bub.add_child(bv)
		if right:
			row.add_child(UI.spacer(0))
			row.get_child(0).custom_minimum_size.x = 60
			row.add_child(bub)
			row.add_child(av)
		else:
			row.add_child(av)
			row.add_child(bub)
			var sp := UI.spacer(0)
			sp.custom_minimum_size.x = 40
			row.add_child(sp)
		msgs.add_child(row)
	v.add_child(body)
	return frame


# ------------------------------------------------------------------ rede social "Flash"
static func _post(clue: Dictionary) -> Control:
	var p: Dictionary = clue.get("post", {})
	var who := str(p.get("who", clue.get("from", "")))
	var user := str(p.get("user", "@" + person_name(who).to_lower().replace(" ", "")))
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UI.box(Color.WHITE, Color("#d9dce6"), 2, 26, 0))
	var v := UI.vbox(10)
	frame.add_child(v)
	var head := UI.margin(18, 16, 0)
	var hh := UI.hbox(12)
	var av := Avatar.new()
	av.setup(who, 30, user)
	av.ring = UI.PINK
	hh.add_child(av)
	var hv := UI.vbox(0)
	hv.add_child(UI.label(user, 24, Color("#111"), "bold"))
	hv.add_child(UI.label("Flash  ·  " + str(clue.get("time", "")), 18, Color("#8a8fa3")))
	hh.add_child(hv)
	head.add_child(hh)
	v.add_child(head)
	var photo := Photo.new()
	photo.caption = UI.strip_emoji(str(p.get("image", clue.get("title", ""))))
	photo.custom_minimum_size = Vector2(0, 330)
	v.add_child(photo)
	var foot := UI.margin(18, 0, 18)
	var fv := UI.vbox(8)
	var icons := IconRow.new()
	icons.likes = int(p.get("likes", 0))
	icons.custom_minimum_size = Vector2(0, 40)
	fv.add_child(icons)
	var cap := RichTextLabel.new()
	cap.bbcode_enabled = true
	cap.fit_content = true
	cap.scroll_active = false
	cap.add_theme_font_override("normal_font", UI.font("body"))
	cap.add_theme_font_override("bold_font", UI.font("bold"))
	cap.add_theme_font_size_override("normal_font_size", 24)
	cap.add_theme_font_size_override("bold_font_size", 24)
	cap.add_theme_color_override("default_color", Color("#16182a"))
	var caption := UI.strip_emoji(str(p.get("caption", clue.get("text", ""))))
	cap.text = "[b]%s[/b]  %s" % [user, caption.replace("[", "(").replace("]", ")")]
	fv.add_child(cap)
	for cm in p.get("comments", []):
		var cl := RichTextLabel.new()
		cl.bbcode_enabled = true
		cl.fit_content = true
		cl.scroll_active = false
		cl.add_theme_font_override("normal_font", UI.font("body"))
		cl.add_theme_font_override("bold_font", UI.font("bold"))
		cl.add_theme_font_size_override("normal_font_size", 21)
		cl.add_theme_font_size_override("bold_font_size", 21)
		cl.add_theme_color_override("default_color", Color("#4a4f66"))
		cl.text = "[b]%s[/b]  %s" % [str(cm.get("user", "")), UI.strip_emoji(str(cm.get("text", ""))).replace("[", "(")]
		fv.add_child(cl)
	foot.add_child(fv)
	v.add_child(foot)
	return frame


# ------------------------------------------------------------------ papéis
static func _testimony(clue: Dictionary) -> Control:
	var page := Paper.make("notebook", true)
	var v := UI.vbox(12)
	page.add_child(v)
	var who := str(clue.get("who", clue.get("from", "")))
	var h := UI.hbox(14)
	if who != "":
		var av := Avatar.new()
		av.setup(who, 44, person_name(who))
		h.add_child(av)
	var hv := UI.vbox(0)
	hv.add_child(UI.title("DEPOIMENTO", 34, UI.RED))
	if who != "":
		hv.add_child(UI.label(person_name(who), 30, UI.INK, "marker"))
	h.add_child(hv)
	v.add_child(h)
	var t := UI.label("\"" + UI.strip_emoji(str(clue.get("text", ""))) + "\"", 28, Color("#1b2140"), "type")
	t.add_theme_constant_override("line_spacing", 10)
	v.add_child(t)
	return page


static func _receipt(clue: Dictionary) -> Control:
	var page := Paper.make("receipt")
	var v := UI.vbox(8)
	page.add_child(v)
	var head := UI.title(UI.strip_emoji(str(clue.get("title", "REGISTRO"))).to_upper(), 34, UI.INK)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	v.add_child(UI.label("- - - - - - - - - - - - - - - - - - - -", 20, Color(0, 0, 0, 0.4), "type"))
	for line in UI.strip_emoji(str(clue.get("text", ""))).split("\n"):
		v.add_child(UI.label(line, 25, Color("#202436"), "type"))
	v.add_child(UI.label("- - - - - - - - - - - - - - - - - - - -", 20, Color(0, 0, 0, 0.4), "type"))
	if str(clue.get("time", "")) != "":
		var tl := UI.label("impresso " + str(clue.get("time", "")), 18, Color(0, 0, 0, 0.5), "type")
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tl)
	return page


static func _sticky(clue: Dictionary) -> Control:
	var c := CenterContainer.new()
	var page := Paper.make("sticky", true)
	page.custom_minimum_size = Vector2(520, 0)
	page.rotation = -0.025
	var l := UI.label(UI.strip_emoji(str(clue.get("text", ""))), 32, Color("#1b2140"), "marker")
	l.custom_minimum_size.x = 460
	page.add_child(l)
	c.add_child(page)
	return c


static func _polaroid(clue: Dictionary) -> Control:
	var c := CenterContainer.new()
	var page := Paper.make("polaroid", true)
	page.custom_minimum_size = Vector2(540, 0)
	var v := UI.vbox(14)
	var photo := Photo.new()
	photo.caption = UI.strip_emoji(str(clue.get("title", "")))
	photo.evidence = true
	photo.custom_minimum_size = Vector2(0, 300)
	v.add_child(photo)
	var l := UI.label(UI.strip_emoji(str(clue.get("text", ""))), 26, Color("#1b2140"), "type")
	v.add_child(l)
	page.add_child(v)
	c.add_child(page)
	return c


static func _sb(bg: Color, radius: Array, pad := 16, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius[0]
	s.corner_radius_top_right = radius[1]
	s.corner_radius_bottom_right = radius[2]
	s.corner_radius_bottom_left = radius[3]
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.8
	s.content_margin_bottom = pad * 0.8
	if border.a > 0:
		s.border_color = border
		s.border_width_bottom = 2
	s.anti_aliasing = true
	return s


# ------------------------------------------------------------------ "foto" pintada em código
## Não temos fotos: a imagem do post vira um quadro noir em duotom com a descrição escrita à mão,
## como se o jogador estivesse vendo a cena pelo olhar do detetive.
class Photo extends Control:
	var caption := ""
	var evidence := false

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var top := Color("#26407a") if not evidence else Color("#3b3550")
		var bot := Color("#0a1430")
		var steps := 6
		for i in steps:
			var t := float(i) / steps
			draw_rect(Rect2(0, r.size.y * t, r.size.x, r.size.y / steps + 1), top.lerp(bot, t))
		draw_circle(Vector2(r.size.x * 0.78, r.size.y * 0.25), r.size.y * 0.32, Color(UI.YELLOW, 0.16))
		draw_circle(Vector2(r.size.x * 0.78, r.size.y * 0.25), r.size.y * 0.18, Color(UI.YELLOW, 0.14))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(caption)
		for i in 160:
			var p := Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y)
			draw_circle(p, 1.6, Color(0, 0, 0, 0.25))
		var f := UI.font("marker")
		var fs := 34
		draw_multiline_string(f, Vector2(30, r.size.y * 0.5 - 20), caption, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 60, fs, 4, Color(UI.PAPER, 0.92))
		if evidence:
			var tag := Rect2(r.size.x - 190, r.size.y - 60, 170, 44)
			draw_rect(tag, UI.YELLOW)
			draw_string(UI.font("title"), tag.position + Vector2(12, 34), "EVIDÊNCIA", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, UI.INK)


class IconRow extends Control:
	var likes := 0

	func _draw() -> void:
		var y := size.y / 2.0
		# coração
		var c := Vector2(18, y)
		draw_circle(c + Vector2(-7, -4), 8, UI.RED)
		draw_circle(c + Vector2(7, -4), 8, UI.RED)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-15, -1), c + Vector2(15, -1), c + Vector2(0, 15)]), UI.RED)
		# balão de comentário
		draw_arc(Vector2(66, y - 2), 13, 0, TAU, 20, Color("#16182a"), 3.0)
		draw_colored_polygon(PackedVector2Array([Vector2(56, y + 8), Vector2(52, y + 17), Vector2(63, y + 10)]), Color("#16182a"))
		draw_string(UI.font("bold"), Vector2(100, y + 9), "%d curtidas" % likes, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("#16182a"))
