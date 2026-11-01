class_name UI
extends RefCounted
## Kit visual do RUMOR: paleta noir azul + amarelo, fontes e fábricas de controles.
## Tudo pensado para o polegar no celular: alvo mínimo de 88 px no viewport de 720 de largura.

const NIGHT := Color("#060c1f")
const NAVY := Color("#0f1a3a")
const DEEP := Color("#16244d")
const BLUE := Color("#26407a")
const SKY := Color("#4e6fc0")
const MIST := Color("#a9bdf0")
const PAPER := Color("#efe8d6")
const YELLOW := Color("#ffc83d")
const PINK := Color("#ff4fa3")
const RED := Color("#e2384f")
const GREEN := Color("#8ef0b5")
const INK := Color("#05091a")

const TAP := 88

static var _fonts := {}


static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var path: String = {
		"title": "res://assets/fonts/BebasNeue-Regular.ttf",
		"type": "res://assets/fonts/SpecialElite-Regular.ttf",
		"marker": "res://assets/fonts/PermanentMarker-Regular.ttf",
		"body": "res://assets/fonts/Nunito-Var.ttf",
	}.get(kind, "res://assets/fonts/Nunito-Var.ttf")
	var f: Font = load(path)
	if kind == "body" or kind == "bold":
		var fv := FontVariation.new()
		fv.base_font = f
		fv.variation_opentype = {"wght": 800 if kind == "bold" else 600}
		f = fv
	_fonts[kind] = f
	return f


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = 28
	t.set_color("font_color", "Label", PAPER)
	t.set_stylebox("normal", "Button", box(DEEP, YELLOW.darkened(0.5), 3, 18))
	t.set_stylebox("hover", "Button", box(BLUE, YELLOW, 3, 18))
	t.set_stylebox("pressed", "Button", box(YELLOW.darkened(0.2), YELLOW, 3, 18))
	t.set_stylebox("disabled", "Button", box(NAVY, BLUE, 2, 18))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", PAPER)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", MIST.darkened(0.4))
	t.set_font("font", "Button", font("bold"))
	t.set_font_size("font_size", "Button", 30)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.18)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb)
	var sc := StyleBoxEmpty.new()
	sc.content_margin_left = 6
	t.set_stylebox("scroll", "VScrollBar", sc)
	return t


static func box(bg: Color, border: Color = Color.TRANSPARENT, bw := 0, radius := 16, pad := 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.anti_aliasing = true
	return s


static func label(text: String, size := 28, color := PAPER, kind := "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func title(text: String, size := 64, color := YELLOW) -> Label:
	var l := label(text, size, color, "title")
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


## kind: "primary" (amarelo, ação principal), "ghost" (contorno), "danger"
static func button(text: String, kind := "primary", min_h := TAP) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.focus_mode = Control.FOCUS_NONE
	if kind == "primary":
		b.add_theme_stylebox_override("normal", box(YELLOW, INK, 0, 20))
		b.add_theme_stylebox_override("hover", box(YELLOW.lightened(0.15), INK, 0, 20))
		b.add_theme_stylebox_override("pressed", box(YELLOW.darkened(0.25), INK, 0, 20))
		b.add_theme_color_override("font_color", INK)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_pressed_color", INK)
		b.add_theme_font_override("font", font("title"))
		b.add_theme_font_size_override("font_size", 40)
	elif kind == "danger":
		b.add_theme_stylebox_override("normal", box(Color(RED, 0.18), RED, 3, 20))
		b.add_theme_stylebox_override("hover", box(Color(RED, 0.3), RED, 3, 20))
		b.add_theme_stylebox_override("pressed", box(RED, RED, 3, 20))
	elif kind == "ghost":
		b.add_theme_stylebox_override("normal", box(Color(0, 0, 0, 0.25), MIST.darkened(0.3), 2, 20))
		b.add_theme_stylebox_override("hover", box(Color(SKY, 0.25), MIST, 2, 20))
		b.add_theme_stylebox_override("pressed", box(SKY, MIST, 2, 20))
	b.pressed.connect(func() -> void: Sfx.play("ui_tap"))
	return b


static func panel(bg := Color(NAVY, 0.92), border := Color(SKY, 0.5), radius := 22) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, border, 2, radius, 24))
	return p


static func vbox(sep := 16) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 16) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func margin(m := 28, top := -1, bottom := -1) -> MarginContainer:
	var c := MarginContainer.new()
	c.add_theme_constant_override("margin_left", m)
	c.add_theme_constant_override("margin_right", m)
	c.add_theme_constant_override("margin_top", m if top < 0 else top)
	c.add_theme_constant_override("margin_bottom", m if bottom < 0 else bottom)
	return c


static func spacer(h := 0.0, expand := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func full(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


static func fmt_time(sec: int) -> String:
	return "%d:%02d" % [sec / 60, sec % 60]


## Nome curto para fichas e etiquetas: "Maria Eduarda Santos" -> "Maria E. S." (nunca estoura a UI).
static func short_name(n: String, max_len := 13) -> String:
	n = n.strip_edges()
	if n.length() <= max_len:
		return n
	var parts := n.split(" ", false)
	var first := parts[0]
	if first.length() > max_len - 1:
		return first.substr(0, max_len - 1) + "."
	var out := first
	for k in range(1, parts.size()):
		var ini := " " + parts[k].substr(0, 1).to_upper() + "."
		if (out + ini).length() > max_len:
			break
		out += ini
	return out


## Quantos pixels reais cabem em cada ponto da interface (celular com tela fina: ~1,5 a 3).
## As cenas 3D renderizam nessa escala para não ficarem embaçadas; no celular tem um teto.
static func render_scale(tree: SceneTree) -> float:
	var win := tree.root
	var cs := Vector2(win.content_scale_size)
	if cs.x <= 0.0 or cs.y <= 0.0:
		return 1.0
	var f := minf(win.size.x / cs.x, win.size.y / cs.y)
	var mobile := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	return clampf(f, 1.0, 1.5 if mobile else 2.0)


## Janela de confirmação por cima de tudo (sair do caso, fechar a sala...). Toque fora cancela.
static func confirm(host: Node, title_text: String, body: String, yes_text: String, on_yes: Callable, no_text := "CONTINUAR AQUI") -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	host.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(full(dim))
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			layer.queue_free())
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(full(cc))
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(NAVY, 0.98), YELLOW, 3, 22, 26))
	var vs := host.get_viewport().get_visible_rect().size if host is CanvasItem else Vector2(720, 1280)
	p.custom_minimum_size.x = minf(vs.x - 40, 620)
	var v := vbox(16)
	var t := title(title_text, 46, YELLOW)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	v.add_child(label(body, 24, PAPER))
	var yes := button(yes_text, "primary", 90)
	yes.pressed.connect(func() -> void:
		layer.queue_free()
		on_yes.call())
	v.add_child(yes)
	var no := button(no_text, "ghost", 80)
	no.pressed.connect(func() -> void: layer.queue_free())
	v.add_child(no)
	p.add_child(v)
	cc.add_child(p)


## Foto de evidência do caso (objeto 3D gerado por tools_dev/case_icon_bake): nunca uma pessoa.
static func case_icon(case_id: String) -> Texture2D:
	var p := "res://assets/case_icons/%s.png" % case_id
	if ResourceLoader.exists(p):
		return load(p)
	return null


static func portrait(id: String) -> Texture2D:
	var p := "res://assets/portraits/%s.png" % id
	if ResourceLoader.exists(p):
		return load(p)
	return null


## Etiqueta por tipo de pista. Texto e não emoji: a fonte do jogo no navegador não tem emoji.
static func clue_tag(kind: String) -> String:
	return {
		"mensagem": "MENSAGEM", "depoimento": "DEPOIMENTO", "registro": "REGISTRO", "objeto": "OBJETO",
		"post": "POST", "bilhete": "BILHETE",
	}.get(kind, "PISTA")


static func clue_color(kind: String) -> Color:
	return {
		"mensagem": Color("#6fd3ff"), "depoimento": Color("#ff9a4d"), "registro": Color("#b9a3ff"),
		"objeto": YELLOW, "post": PINK, "bilhete": GREEN,
	}.get(kind, MIST)


## Emoji vindo do texto do caso some na fonte do navegador; troca por nada para não virar quadrado.
static func strip_emoji(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if (c >= 0x1F000 and c <= 0x1FAFF) or (c >= 0x2600 and c <= 0x27BF) or c == 0xFE0F or c == 0x200D:
			continue
		out += char(c)
	return out.strip_edges() if out.length() < s.length() else out


## Toque curto de "tween" de entrada usado em todas as telas.
static func pop_in(c: Control, delay := 0.0) -> void:
	c.modulate.a = 0.0
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, 0.25)


## Dentro de uma rolagem, painéis e botões não podem "segurar" o dedo, senão a lista não rola
## no celular. PASS deixa o toque chegar ao ScrollContainer e os botões continuam funcionando.
static func scroll_friendly(n: Node) -> void:
	for c in n.get_children():
		if c is Control:
			var ctl := c as Control
			if ctl is LineEdit or ctl is TextEdit or ctl is ScrollContainer or ctl is SubViewportContainer or ctl.get_class() == "Control" and ctl.has_method("fit"):
				pass
			elif ctl.mouse_filter == Control.MOUSE_FILTER_STOP:
				ctl.mouse_filter = Control.MOUSE_FILTER_PASS
		scroll_friendly(c)
