class_name CaseFile
extends Control
## Pasta de arquivo de um caso (tela do solo): pasta parda com aba numerada, folhas aparecendo,
## foto presa por clipe, título datilografado, nível de perigo e carimbo (CONFIDENCIAL / RESOLVIDO).

signal open_pressed

const MANILA := Color("#d9b977")
const MANILA_DARK := Color("#b8944f")
const MANILA_BACK := Color("#c7a25e")
const INK := Color("#1b2140")
const STAMP_RED := Color("#c42c3f")
const STAMP_GREEN := Color("#2f8f55")

var data: Dictionary
var number := 1
var solved := false
var _seed := 0.0
var _photo: Texture2D
var _open_t := 0.0     # 0..1 animação de abrir


func setup(c: Dictionary, n: int, is_solved: bool) -> void:
	data = c
	number = n
	solved = is_solved
	_seed = float(hash(str(c.get("id", ""))) % 100) / 100.0
	custom_minimum_size = Vector2(0, 520)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var cover := str(c.get("cover", ""))
	if cover != "":
		_photo = UI.portrait(cover)
	_build()


func _build() -> void:
	# textos sobre a capa (posições relativas à capa, que começa em y=64)
	var tab := UI.label("ARQUIVO Nº %02d" % number, 22, INK, "type")
	tab.autowrap_mode = TextServer.AUTOWRAP_OFF
	tab.position = Vector2(18 + _seed * 40.0 + 26, 20)
	add_child(tab)
	var t := UI.title(str(data.get("title", "")).to_upper(), 50, INK)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.position = Vector2(34, 92)
	t.size = Vector2(0, 0)
	t.set_meta("wrap", true)
	add_child(t)
	var tg := UI.label(UI.strip_emoji(str(data.get("tagline", ""))), 22, Color(INK, 0.85), "type")
	tg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tg.set_meta("wrap", true)
	add_child(tg)
	var info := UI.label("%s  ·  %d ENVOLVIDOS  ·  %d MIN" % [str(data.get("place", "Escola")).to_upper(), int(data.get("people", 0)),
		int(data.get("duration_sec", 600)) / 60], 19, Color(INK, 0.7), "type")
	info.autowrap_mode = TextServer.AUTOWRAP_OFF
	info.clip_text = true
	info.set_meta("info", true)
	add_child(info)
	var lvl := UI.label("PERIGO", 18, Color(INK, 0.7), "type")
	lvl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lvl.set_meta("lvl", true)
	add_child(lvl)
	var go := UI.button("ABRIR O ARQUIVO" if not solved else "INVESTIGAR DE NOVO", "primary", 84)
	go.set_meta("go", true)
	go.pressed.connect(_on_open)
	add_child(go)
	var cap := UI.label(str(data.get("cover_name", "")), 20, INK, "marker")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	cap.clip_text = true
	cap.set_meta("cap", true)
	add_child(cap)
	resized.connect(_layout)
	_layout.call_deferred()


func _photo_rect() -> Rect2:
	var w := clampf(size.x * 0.3, 150.0, 210.0)
	return Rect2(size.x - w - 34, 96, w, w * 1.18)


func _layout() -> void:
	var pr := _photo_rect()
	var text_w := pr.position.x - 34 - 26
	for ch in get_children():
		var c := ch as Control
		if c == null:
			continue
		if c.has_meta("wrap") and c is Label and (c as Label).get_theme_font_size("font_size") >= 40:
			c.position = Vector2(34, 92)
			c.size = Vector2(text_w, 0)
			c.custom_minimum_size.x = text_w
		elif c.has_meta("wrap"):
			var title_l: Label = get_child(1)
			c.position = Vector2(34, 92 + title_l.get_combined_minimum_size().y + 6)
			c.custom_minimum_size.x = text_w
			c.size = Vector2(text_w, 0)
		elif c.has_meta("info"):
			c.position = Vector2(34, size.y - 160)
			c.size = Vector2(maxf(text_w, 200.0), 26)
		elif c.has_meta("lvl"):
			c.position = Vector2(34, size.y - 196)
		elif c.has_meta("go"):
			c.position = Vector2(34, size.y - 116)
			c.size = Vector2(size.x - 68, 84)
		elif c.has_meta("cap"):
			c.position = Vector2(pr.position.x, pr.end.y - 44)
			c.size = Vector2(pr.size.x, 36)
	queue_redraw()


func _on_open() -> void:
	Sfx.play("ui_tap")
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_open_t = v
		queue_redraw(), 0.0, 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: open_pressed.emit())


func _draw() -> void:
	var w := size.x
	var h := size.y
	var top := 64.0
	# sombra
	draw_rect(Rect2(10, top + 12, w - 6, h - top - 4), Color(0, 0, 0, 0.45))
	# fundo da pasta e aba
	var tab_x := 18.0 + _seed * 40.0
	var tab := PackedVector2Array([Vector2(tab_x, top + 2), Vector2(tab_x + 14, 2), Vector2(tab_x + 250, 2), Vector2(tab_x + 268, top + 2)])
	draw_colored_polygon(tab, MANILA_BACK)
	draw_polyline(tab, MANILA_DARK, 2.0)
	draw_rect(Rect2(0, top, w, h - top - 8), MANILA_BACK)
	# folhas aparecendo por cima (levantam quando abre)
	var lift := _open_t * 26.0
	for i in 2:
		var sx := tab_x + 282.0 + i * 12
		var off := Vector2(sx, top - 12 - i * 6 - lift * (1 - i * 0.4))
		var pts := _rot_rect(Rect2(off, Vector2(maxf(w - sx - 16 - i * 10, 60.0), 90)), (-0.012 + i * 0.02) * (1.0 + _seed))
		draw_colored_polygon(pts, Color("#f4efe2") if i == 0 else Color("#e8e1cd"))
		if i == 0:
			for k in 3:
				var y := off.y + 22 + k * 18
				draw_line(Vector2(off.x + 16, y), Vector2(minf(off.x + 200, w - 40), y), Color(INK, 0.25), 2.0)
	# capa (inclina um pouco ao abrir)
	var cover := Rect2(0, top + 18 + lift * 0.4, w, h - top - 26)
	draw_rect(cover, MANILA)
	draw_rect(Rect2(cover.position, Vector2(w, 6)), MANILA_DARK)
	# vincos e manchas de café
	draw_line(Vector2(0, cover.position.y + 40), Vector2(w, cover.position.y + 40), Color(MANILA_DARK, 0.35), 1.5)
	draw_arc(Vector2(w * (0.35 + _seed * 0.3), cover.end.y - 70), 46, 0.3, 5.2, 40, Color("#8a6a35", 0.18), 6.0)
	# linhas de preenchimento do formulário
	draw_line(Vector2(34, h - 128), Vector2(w - 34, h - 128), Color(INK, 0.25), 1.5)
	# nível de perigo: lupas
	var d := clampi(int(data.get("difficulty", 1)), 1, 3)
	for i in 3:
		var c := Vector2(120 + i * 34, h - 182)
		var col := INK if i < d else Color(INK, 0.22)
		draw_arc(c, 10, 0, TAU, 20, col, 3.5)
		draw_line(c + Vector2(7, 7), c + Vector2(16, 16), col, 4.5)
	# foto com clipe
	var pr := _photo_rect()
	var ang := -0.05 + _seed * 0.1
	draw_set_transform(pr.get_center() + Vector2(4, 6), ang)
	draw_rect(Rect2(-pr.size / 2, pr.size), Color(0, 0, 0, 0.35))
	draw_set_transform(pr.get_center(), ang)
	var local := Rect2(-pr.size / 2, pr.size)
	draw_rect(local, Color("#f7f3ea"))
	var img := Rect2(local.position + Vector2(10, 10), Vector2(local.size.x - 20, local.size.x - 20))
	draw_rect(img, Color("#16244d"))
	if _photo:
		draw_texture_rect(_photo, img, false)
	else:
		draw_string(UI.font("title"), img.get_center() + Vector2(-14, 20), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(UI.MIST, 0.6))
	# clipe de papel
	var cp := Vector2(local.position.x + local.size.x * 0.28, local.position.y - 14)
	var clip_col := Color("#9aa3b8")
	draw_line(cp, cp + Vector2(0, 58), clip_col, 4.0)
	draw_line(cp + Vector2(16, 0), cp + Vector2(16, 70), clip_col, 4.0)
	draw_arc(cp + Vector2(8, 0), 8, PI, TAU, 10, clip_col, 4.0)
	draw_arc(cp + Vector2(8, 58), 8, 0, PI, 10, clip_col, 4.0)
	draw_set_transform(Vector2.ZERO, 0.0)
	# carimbo
	var stamp_txt := "CASO RESOLVIDO" if solved else "CONFIDENCIAL"
	var sc := STAMP_GREEN if solved else STAMP_RED
	var sf := UI.font("title")
	var fs := 40
	var tw := sf.get_string_size(stamp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var spos := Vector2(w - tw - 46, pr.end.y + 34)
	spos.x = clampf(spos.x, 30, w - tw - 40)
	draw_set_transform(spos + Vector2(tw / 2, 0), -0.13)
	draw_rect(Rect2(-tw / 2 - 12, -fs * 0.82, tw + 24, fs + 8), Color(sc, 0.85), false, 4.0)
	draw_string(sf, Vector2(-tw / 2, 0), stamp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(sc, 0.85))
	draw_set_transform(Vector2.ZERO, 0.0)


func _rot_rect(r: Rect2, a: float) -> PackedVector2Array:
	var c := r.get_center()
	var out := PackedVector2Array()
	for p in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		out.append(c + (p - c).rotated(a))
	return out
