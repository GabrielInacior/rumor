class_name ClueView
extends RefCounted
## Monta a pista do jeito que ela existiria no mundo do caso: conversa num app de mensagem,
## post de rede social, depoimento no caderno, registro impresso, bilhete em post-it, foto de objeto.
## Os apps são fictícios ("Papo" e "Flash"). Aceita o formato rico (chat/post) e o antigo (texto).

const Avatar := preload("res://scripts/ui/avatar.gd")


static func person_name(who: String) -> String:
	var c := Net.card_by_id(who)
	return UI.strip_emoji(str(c.get("name", who)))


## Ícone 3D (assets/items) que representa a pista no quadro e na mochila.
static func icon_kind(clue: Dictionary) -> String:
	var vis: Dictionary = clue.get("visual", {}) if clue.get("visual") is Dictionary else {}
	if vis.has("model"):
		return str(vis["model"])
	match str(vis.get("art", "")):
		"ransom": return "recorte"
		"cctv": return "camera_seg"
		"pix": return "celular"
	return {"mensagem": "mensagem", "post": "celular", "depoimento": "microfone", "registro": "prancheta",
		"bilhete": "papel", "objeto": "caixa"}.get(str(clue.get("kind", "")), "papel")


## Imagem da pista (objeto 3D, bilhete recortado, câmera de segurança, Pix) no topo da ficha.
static func visual_block(clue: Dictionary, h := 300.0) -> Control:
	var vis: Dictionary = clue.get("visual", {}) if clue.get("visual") is Dictionary else {}
	if vis.is_empty():
		return null
	var art := str(vis.get("art", ""))
	if art == "ransom":
		var rn := RansomNote.new()
		rn.text = UI.strip_emoji(str(vis.get("text", clue.get("text", ""))))
		rn.custom_minimum_size = Vector2(0, h)
		return rn
	if art == "cctv":
		var cf := CctvFrame.new()
		cf.stamp = str(vis.get("stamp", clue.get("time", "")))
		cf.label = UI.strip_emoji(str(vis.get("caption", clue.get("title", ""))))
		cf.custom_minimum_size = Vector2(0, h)
		return cf
	if art == "pix":
		var px := PixReceipt.new()
		px.valor = str(vis.get("valor", ""))
		px.de = str(vis.get("de", ""))
		px.para = str(vis.get("para", ""))
		px.hora = str(vis.get("hora", clue.get("time", "")))
		px.custom_minimum_size = Vector2(0, h + 40)
		return px
	if vis.has("model"):
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", UI.box(Color("#fbfaf6"), Color.TRANSPARENT, 0, 4, 10))
		var tr := TextureRect.new()
		tr.texture = Snap.get_tex("item:" + str(vis["model"]))
		tr.custom_minimum_size = Vector2(0, h)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.add_child(tr)
		return frame
	return null


static func build(clue: Dictionary) -> Control:
	var base := _build_base(clue)
	var vb := visual_block(clue)
	if vb == null or str(clue.get("kind", "")) == "objeto" or clue.has("post"):
		return base
	# imagem em cima, o documento embaixo (a pista se entende de longe, sem ler tudo)
	var v := UI.vbox(14)
	var c := CenterContainer.new()
	vb.custom_minimum_size.x = 520
	c.add_child(vb)
	v.add_child(c)
	v.add_child(base)
	return v


static func _build_base(clue: Dictionary) -> Control:
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
	gv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(UI.label(user, 24, Color("#111"), "bold"))
	hv.add_child(UI.label("Flash  ·  " + str(clue.get("time", "")), 18, Color("#8a8fa3")))
	hh.add_child(hv)
	head.add_child(hh)
	v.add_child(head)
	var photo := Photo.new()
	photo.caption = UI.strip_emoji(str(p.get("image", clue.get("title", ""))))
	photo.custom_minimum_size = Vector2(0, 330)
	photo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var vb := visual_block(clue)
	if vb:
		v.add_child(vb)
	else:
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


## Bilhete de letras recortadas de revista: cada letra num pedaço de papel de cor/tamanho diferente.
class RansomNote extends Control:
	var text := ""

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color("#f4efe2"))
		draw_rect(r, Color(0, 0, 0, 0.15), false, 2.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(text)
		var fonts := [UI.font("title"), UI.font("type"), UI.font("marker"), UI.font("bold")]
		var bgs := [Color("#ffffff"), Color("#ffe27a"), Color("#e2384f"), Color("#4e9bff"), Color("#1b2140"), Color("#efe8d6"), Color("#5fd38a")]
		var words := text.to_upper().split(" ", false)
		var x := 16.0
		var y := 18.0
		var line_h := 0.0
		for w in words:
			var ww := 0.0
			var cells := []
			for ch in w:
				var fs := rng.randi_range(26, 40)
				var f: Font = fonts[rng.randi() % fonts.size()]
				var cw := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10
				cells.append([ch, fs, f, cw])
				ww += cw + 2
			if x + ww > r.size.x - 12:
				x = 16.0
				y += line_h + 10
				line_h = 0.0
			if y > r.size.y - 30:
				break
			for cell in cells:
				var bg: Color = bgs[rng.randi() % bgs.size()]
				var fg := UI.INK if bg.get_luminance() > 0.5 else Color.WHITE
				var cr := Rect2(x, y + rng.randf_range(-4, 4), cell[3], cell[1] + 10)
				draw_set_transform(cr.get_center(), rng.randf_range(-0.12, 0.12))
				draw_rect(Rect2(-cr.size / 2 + Vector2(2, 3), cr.size), Color(0, 0, 0, 0.18))
				draw_rect(Rect2(-cr.size / 2, cr.size), bg)
				draw_string(cell[2], Vector2(-cr.size.x / 2 + 5, cr.size.y / 2 - 7), cell[0], HORIZONTAL_ALIGNMENT_LEFT, -1, cell[1], fg)
				draw_set_transform(Vector2.ZERO, 0.0)
				x += cell[3] + 2
				line_h = maxf(line_h, cell[1] + 10)
			x += 14


## Quadro de câmera de segurança: granulado, REC, data e hora, uma silhueta no corredor.
class CctvFrame extends Control:
	var stamp := ""
	var label := ""

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color("#1a2a22"))
		# corredor em perspectiva
		var c := Vector2(r.size.x * 0.5, r.size.y * 0.42)
		draw_colored_polygon(PackedVector2Array([Vector2(0, r.size.y), Vector2(r.size.x, r.size.y), c + Vector2(60, 40), c + Vector2(-60, 40)]), Color("#2c4236"))
		draw_line(Vector2(0, 0), c + Vector2(-60, -50), Color("#3f5a4a"), 3.0)
		draw_line(Vector2(r.size.x, 0), c + Vector2(60, -50), Color("#3f5a4a"), 3.0)
		draw_rect(Rect2(c + Vector2(-60, -50), Vector2(120, 90)), Color("#22362c"))
		# silhueta
		var s := Vector2(r.size.x * 0.58, r.size.y * 0.62)
		draw_circle(s + Vector2(0, -70), 16, Color("#0b1410"))
		draw_colored_polygon(PackedVector2Array([s + Vector2(-26, -50), s + Vector2(26, -50), s + Vector2(30, 40), s + Vector2(-30, 40)]), Color("#0b1410"))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(stamp + label)
		for i in 900:
			draw_rect(Rect2(rng.randf() * r.size.x, rng.randf() * r.size.y, 2, 2), Color(1, 1, 1, rng.randf() * 0.12))
		for yy in range(0, int(r.size.y), 4):
			draw_line(Vector2(0, yy), Vector2(r.size.x, yy), Color(0, 0, 0, 0.18), 1.0)
		var f := UI.font("type")
		draw_circle(Vector2(26, 26), 8, Color("#e2384f"))
		draw_string(f, Vector2(42, 34), "REC", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#e2384f"))
		draw_string(f, Vector2(r.size.x - 220, 34), "CAM 02  " + stamp, HORIZONTAL_ALIGNMENT_LEFT, 210, 20, Color("#cfe8d6"))
		draw_string(f, Vector2(16, r.size.y - 16), label, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 32, 20, Color("#cfe8d6"))


## Comprovante de Pix (tela do banco): valor grande, de, para, horário.
class PixReceipt extends Control:
	var valor := ""
	var de := ""
	var para := ""
	var hora := ""

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color("#f7f8fb"))
		draw_rect(Rect2(0, 0, r.size.x, 70), Color("#2fb38a"))
		var ft := UI.font("title")
		var fb := UI.font("bold")
		draw_string(ft, Vector2(20, 48), "PIX ENVIADO", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
		draw_circle(Vector2(r.size.x - 44, 35), 20, Color.WHITE)
		draw_polyline(PackedVector2Array([Vector2(r.size.x - 54, 35), Vector2(r.size.x - 46, 43), Vector2(r.size.x - 33, 27)]), Color("#2fb38a"), 4.0)
		draw_string(fb, Vector2(20, 112), "Valor", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#7a8094"))
		draw_string(ft, Vector2(20, 162), valor, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color("#16182a"))
		var y := 200.0
		for row in [["De", de], ["Para", para], ["Horário", hora]]:
			draw_line(Vector2(20, y), Vector2(r.size.x - 20, y), Color(0, 0, 0, 0.1), 1.0)
			draw_string(fb, Vector2(20, y + 30), str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#7a8094"))
			draw_string(fb, Vector2(140, y + 30), str(row[1]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 160, 22, Color("#16182a"))
			y += 44


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
