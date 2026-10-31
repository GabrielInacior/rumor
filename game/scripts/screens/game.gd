extends Control
## Tela do aluno durante a investigação. Três abas na base (alcance do polegar):
## CENA (explorar em 3D), PISTAS (o que só você e a equipe sabem) e QUADRO (o centro do jogo).
## Ações aparecem em painéis que sobem de baixo, um de cada vez, para não lotar a tela.

const BoardView := preload("res://scripts/board/board_view.gd")
const CaseScene := preload("res://scripts/scene3d/case_scene.gd")
const TalkView := preload("res://scripts/scene3d/talk_view.gd")

var timer_l: Label
var team_l: Label
var tabs_box: HBoxContainer
var tab_btns := {}
var pages := {}
var tab := "cena"
var board: Control
var scene3d: SubViewportContainer
var narr_panel: PanelContainer
var narr_l: Label
var clue_list: VBoxContainer
var clue_count_l: Label
var submit_btn: Button
var action_bar: HBoxContainer
var link_banner: PanelContainer
var guide: PanelContainer
var guide_l: Label
var sheet_layer: Control
var seen_clues := {}
var new_badge := 0
var last_result_at := 0.0
var _urgent_played := false
var _last_sec := -1
var locations: Array = []
var loc := ""
var loc_strip: HBoxContainer
var person_locks := {}
var chosen_culprit := ""
const LOC_NAMES := {
	"corredor": "Corredor", "biblioteca": "Biblioteca", "teatro": "Teatro", "sala_aula": "Sala de aula",
	"cantina": "Cantina", "patio": "Pátio", "sala_professores": "Sala dos profs", "quadra": "Quadra",
	"sala_diretor": "Diretoria", "deposito": "Depósito", "laboratorio": "Laboratório", "sala_musica": "Sala de música",
}


func _ready() -> void:
	var root := UI.vbox(0)
	add_child(UI.full(root))

	# ---- barra de cima: tempo, equipe, objetivo
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UI.box(Color(UI.NIGHT, 0.92), Color.TRANSPARENT, 0, 0, 18))
	var th := UI.hbox(14)
	top.add_child(th)
	timer_l = UI.title("0:00", 64, UI.YELLOW)
	th.add_child(timer_l)
	var tv := UI.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_l = UI.title("", 32, UI.PAPER)
	tv.add_child(team_l)
	var goal := UI.label(str(Net.case_data.get("goal", "")), 20, UI.MIST)
	goal.max_lines_visible = 2
	tv.add_child(goal)
	th.add_child(tv)
	root.add_child(top)

	# ---- páginas
	var pages_holder := Control.new()
	pages_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(pages_holder)
	pages["cena"] = _build_scene_page()
	pages["pistas"] = _build_clues_page()
	pages["quadro"] = _build_board_page()
	for k in pages:
		pages_holder.add_child(UI.full(pages[k]))

	# ---- abas
	var tb := PanelContainer.new()
	tb.add_theme_stylebox_override("panel", UI.box(Color(UI.NIGHT, 0.97), Color.TRANSPARENT, 0, 0, 10))
	tabs_box = UI.hbox(10)
	tb.add_child(tabs_box)
	for k in [["cena", "CENA"], ["pistas", "PISTAS"], ["quadro", "QUADRO"]]:
		var b := UI.button(k[1], "ghost", 104)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", UI.font("title"))
		b.add_theme_font_size_override("font_size", 40)
		b.pressed.connect(_set_tab.bind(k[0]))
		tabs_box.add_child(b)
		tab_btns[k[0]] = b
	root.add_child(tb)

	sheet_layer = Control.new()
	sheet_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UI.full(sheet_layer))

	_set_tab("cena")
	Sfx.set_ambience("ambience_rain_loop")
	Sfx.start_music()


# ================================================================== CENA
func _build_scene_page() -> Control:
	var page := Control.new()
	scene3d = CaseScene.new()
	page.add_child(UI.full(scene3d))
	var found := {}
	locations = Net.case_data.get("locations", [])
	if locations.is_empty():
		locations = [str(Net.case_data.get("scene", "corredor"))]
	scene3d.person_tapped.connect(_talk_to)
	# faixa de lugares: trocar de cena é tocar no nome do lugar
	var strip_sc := ScrollContainer.new()
	strip_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip_sc.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip_sc.offset_left = 12; strip_sc.offset_right = -12; strip_sc.offset_top = 12; strip_sc.offset_bottom = 92
	loc_strip = UI.hbox(10)
	strip_sc.add_child(loc_strip)
	page.add_child(strip_sc)
	_load_location(str(locations[0]))
	scene3d.hotspot_tapped.connect(_on_hotspot)
	scene3d.flavor_tapped.connect(func(t: String) -> void: _narrate(t, false))
	var hint := UI.label("Arraste para olhar em volta. Toque no que brilha.", 22, UI.PAPER, "bold")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 104
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_color_override("font_outline_color", UI.NIGHT)
	hint.add_theme_constant_override("outline_size", 8)
	page.add_child(hint)
	# caixa de narração amarela, estilo quadrinho
	narr_panel = PanelContainer.new()
	narr_panel.add_theme_stylebox_override("panel", UI.box(UI.YELLOW, UI.INK, 4, 4, 22))
	narr_l = UI.label("", 28, UI.INK, "type")
	narr_panel.add_child(narr_l)
	narr_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	narr_panel.offset_left = 22; narr_panel.offset_right = -22; narr_panel.offset_bottom = -22
	narr_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	narr_panel.visible = false
	narr_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(narr_panel)
	return page


func _load_location(l: String) -> void:
	loc = l
	var hs := []
	for h in Net.case_data.get("hotspots", []):
		if str(h.get("scene", locations[0])) == l:
			hs.append(h)
	var ppl := []
	for e in Net.case_data.get("scene_people", []):
		var pid := ""
		var where := str(locations[0])
		if e is Dictionary:
			pid = str(e.get("id", ""))
			where = str(e.get("scene", where))
		else:
			pid = str(e)
		if where == l:
			var pc := Net.card_by_id(pid)
			if not pc.is_empty():
				ppl.append(pc)
	var found := {}
	for hid in Net.state.get("hotspots", []):
		found[str(hid)] = true
	scene3d.setup(l, hs, found, ppl)
	_refresh_loc_strip()
	Sfx.play("paper_flip", -8.0)


## Cada lugar mostra quantas coisas brilhantes ainda faltam ali: guia quem joga pouco sem dar a resposta.
func _refresh_loc_strip() -> void:
	if loc_strip == null:
		return
	UI.clear(loc_strip)
	var found: Array = Net.state.get("hotspots", [])
	for l in locations:
		var left := 0
		for h in Net.case_data.get("hotspots", []):
			if str(h.get("scene", locations[0])) == str(l) and not found.has(h["id"]):
				left += 1
		var on: bool = str(l) == loc
		var b := UI.button(str(LOC_NAMES.get(str(l), str(l))).to_upper() + ("  •%d" % left if left > 0 else ""), "ghost", 72)
		b.add_theme_font_override("font", UI.font("title"))
		b.add_theme_font_size_override("font_size", 30)
		b.custom_minimum_size.x = 200
		b.add_theme_stylebox_override("normal", UI.box(UI.YELLOW if on else Color(UI.NIGHT, 0.85), UI.YELLOW.darkened(0.3), 0 if on else 2, 16, 18))
		b.add_theme_color_override("font_color", UI.INK if on else UI.PAPER)
		b.pressed.connect(func() -> void:
			if str(l) != loc:
				_load_location(str(l)))
		loc_strip.add_child(b)


func _narrate(text: String, important: bool) -> void:
	narr_l.text = text
	narr_panel.visible = true
	narr_panel.modulate.a = 1.0
	Sfx.play("paper_flip", -6.0)
	var tw := narr_panel.create_tween()
	tw.tween_interval(4.5 if important else 3.2)
	tw.tween_property(narr_panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: narr_panel.visible = false)


## Conversa com quem está na cena: o depoimento só sai se a equipe já tem essa pista
## (alguém precisa ter achado ou recebido); antes disso, a pessoa desconversa.
func _talk_to(pid: String) -> void:
	var card := Net.card_by_id(pid)
	var lock_left := (float(person_locks.get(pid, 0)) - Time.get_ticks_msec()) / 1000.0
	if lock_left > 0:
		get_meta("main").toast("%s não quer falar agora. Tente de novo em %ds." % [_name_of(pid), int(ceil(lock_left))], UI.PINK)
		return
	var tree: Dictionary = card.get("talk", {}).get("tree", {})
	if not tree.is_empty():
		var ids := []
		for c in Net.state.get("clues", []):
			ids.append(c["id"])
		var tv := TalkView.new()
		tv.open_tree(card, tree, ids)
		add_child(UI.full(tv))
		scene3d.set_process(false)
		tv.locked.connect(func(person: String, secs: float) -> void:
			person_locks[person] = Time.get_ticks_msec() + secs * 1000.0)
		tv.finished.connect(func() -> void: scene3d.set_process(tab == "cena"))
		return
	for c in Net.state.get("clues", []):
		if str(c.get("kind", "")) == "depoimento" and str(c.get("who", c.get("from", ""))) == pid:
			_open_talk(card, _dialogue_of(c), "DEPOIMENTO")
			return
	var greet: Array = card.get("talk", {}).get("greet", [])
	if greet.is_empty():
		greet = [{"text": "Agora não, detetive.", "expr": "desconfiado", "anim": "negando"}]
	_open_talk(card, greet, "CONVERSA")


func _dialogue_of(c: Dictionary) -> Array:
	var d: Array = c.get("dialogue", [])
	if not d.is_empty():
		return d
	var out := []
	for sentence in UI.strip_emoji(str(c.get("text", ""))).split(". "):
		if sentence.strip_edges() != "":
			out.append({"text": sentence.strip_edges(), "expr": "neutro", "anim": "falando"})
	return out


func _open_talk(card: Dictionary, lines: Array, subtitle: String) -> void:
	var tv := TalkView.new()
	tv.open(card, lines, subtitle)
	add_child(UI.full(tv))
	scene3d.set_process(false)
	tv.finished.connect(func() -> void: scene3d.set_process(tab == "cena"))


func _on_hotspot(id: String, label: String) -> void:
	var hs := {}
	for h in Net.case_data.get("hotspots", []):
		if h["id"] == id:
			hs = h
	Net.send({"t": "hotspot", "id": id})
	scene3d.mark_found(id)
	_narrate("%s. Guardado com a equipe: veja em PISTAS." % label, true)


# ================================================================== PISTAS
func _build_clues_page() -> Control:
	var m := UI.margin(22, 18, 18)
	var v := UI.vbox(12)
	m.add_child(v)
	clue_count_l = UI.label("", 24, UI.MIST, "bold")
	v.add_child(clue_count_l)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	clue_list = UI.vbox(14)
	clue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(clue_list)
	v.add_child(scroll)
	return m


func _refresh_clues() -> void:
	UI.clear(clue_list)
	var clues: Array = Net.state.get("clues", [])
	var mine: Array = Net.state.get("mine", [])
	var on_board := _pinned_refs()
	clue_count_l.text = "%d pistas com a equipe. As marcadas SÓ VOCÊ, conte para eles!" % clues.size()
	# as que só eu tenho primeiro: são as que geram conversa
	var sorted := clues.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var am := mine.has(a["id"]) and not on_board.has("c:" + str(a["id"]))
		var bm := mine.has(b["id"]) and not on_board.has("c:" + str(b["id"]))
		if am != bm:
			return am
		return str(a.get("time", "")) < str(b.get("time", "")))
	# mochila: objetos de troca que a equipe carrega (pegos nas cenas ou ganhos em conversa)
	var items: Array = Net.state.get("items", [])
	if not items.is_empty():
		clue_list.add_child(UI.title("MOCHILA DA EQUIPE", 34, UI.YELLOW))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 12)
		flow.add_theme_constant_override("v_separation", 12)
		for iid in items:
			var it := {}
			for x in Net.case_data.get("items", []):
				if x["id"] == iid:
					it = x
			var tag := Paper.make("sticky")
			tag.custom_minimum_size = Vector2(300, 0)
			var tv := UI.vbox(2)
			tv.add_child(UI.label(UI.strip_emoji(str(it.get("name", iid))), 28, UI.INK, "marker"))
			tv.add_child(UI.label(UI.strip_emoji(str(it.get("desc", ""))), 19, Color(UI.INK, 0.75)))
			tag.add_child(tv)
			flow.add_child(tag)
		clue_list.add_child(flow)
		clue_list.add_child(UI.label("Ofereça numa conversa: alguém pode querer trocar por informação.", 20, UI.MIST))
		clue_list.add_child(UI.title("PISTAS", 34, UI.YELLOW))
	for c in sorted:
		clue_list.add_child(_clue_row(c, mine.has(c["id"]), on_board.has("c:" + str(c["id"]))))
	if clues.is_empty():
		clue_list.add_child(UI.label("Nenhuma pista ainda. Explore a CENA!", 28, UI.MIST, "type"))


func _clue_row(c: Dictionary, mine: bool, pinned: bool) -> Control:
	var col := UI.clue_color(str(c.get("kind", "")))
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 132)
	var edge := UI.PINK if (mine and not pinned) else Color(0, 0, 0, 0)
	b.add_theme_stylebox_override("normal", UI.box(Color("#f4eedf"), edge, 4 if edge.a > 0 else 0, 18))
	b.add_theme_stylebox_override("hover", UI.box(Color("#fffaf0"), UI.YELLOW, 4, 18))
	b.add_theme_stylebox_override("pressed", UI.box(Color("#e9e0c8"), UI.YELLOW, 4, 18))
	var h := UI.hbox(16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 18; h.offset_right = -16; h.offset_top = 12; h.offset_bottom = -12
	var who := str(c.get("who", c.get("from", c.get("post", {}).get("who", ""))))
	var av := ClueView.Avatar.new()
	av.setup(who, 40, UI.clue_tag(str(c.get("kind", ""))))
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	var v := UI.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UI.hbox(8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_chip(UI.clue_tag(str(c.get("kind", ""))), col.darkened(0.15)))
	if str(c.get("time", "")) != "":
		var tm := UI.label(str(c.get("time", "")), 22, Color("#5a6080"), "bold")
		tm.autowrap_mode = TextServer.AUTOWRAP_OFF
		tm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(tm)
	v.add_child(top)
	var t := UI.label(UI.strip_emoji(str(c.get("title", ""))), 30, UI.INK, "bold")
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.clip_text = true
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.max_lines_visible = 1
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(t)
	var prev := UI.label(UI.strip_emoji(str(c.get("text", ""))).replace("
", "  "), 21, Color("#4a4f66"))
	prev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prev.max_lines_visible = 1
	prev.autowrap_mode = TextServer.AUTOWRAP_OFF
	prev.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	prev.clip_text = true
	v.add_child(prev)
	h.add_child(v)
	if mine and not pinned:
		h.add_child(_badge("SÓ VOCÊ", UI.PINK))
	elif pinned:
		h.add_child(_badge("NO QUADRO", UI.SKY))
	b.add_child(h)
	b.pressed.connect(func() -> void: _open_clue(c))
	return b


func _chip(text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UI.box(col, Color.TRANSPARENT, 0, 8, 10))
	var l := UI.title(text, 22, UI.INK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


func _badge(text: String, col: Color) -> Control:
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(col, UI.INK, 0, 8, 10))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.title(text, 24, UI.INK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	c.add_child(p)
	return c


func _open_clue(c: Dictionary) -> void:
	Sfx.play("paper_flip")
	var v := UI.vbox(18)
	var col := UI.clue_color(str(c.get("kind", "")))
	var hd := UI.hbox(12)
	hd.add_child(_chip(UI.clue_tag(str(c.get("kind", ""))), col))
	if str(c.get("time", "")) != "":
		hd.add_child(_chip(str(c.get("time", "")), UI.MIST))
	v.add_child(hd)
	v.add_child(UI.title(UI.strip_emoji(str(c.get("title", ""))).to_upper(), 46, UI.PAPER))
	v.add_child(_clue_body(c))
	if str(c.get("kind", "")) == "depoimento" and str(c.get("who", c.get("from", ""))) != "":
		var hear := UI.button("OUVIR O DEPOIMENTO", "ghost")
		var who_id := str(c.get("who", c.get("from", "")))
		hear.pressed.connect(func() -> void:
			_close_sheet()
			_open_talk(Net.card_by_id(who_id), _dialogue_of(c), "DEPOIMENTO"))
		v.add_child(hear)
	var pinned := _pinned_refs().has("c:" + str(c["id"]))
	if Net.state.get("mine", []).has(c["id"]) and not pinned:
		v.add_child(UI.label("Só você está vendo esta pista. Leia em voz alta ou fixe no quadro.", 22, UI.PINK, "bold"))
	var pin := UI.button("JÁ ESTÁ NO QUADRO" if pinned else "FIXAR NO QUADRO", "ghost" if pinned else "primary")
	pin.disabled = pinned
	pin.pressed.connect(func() -> void:
		var p: Vector2 = board.free_spot()
		Net.board_op({"k": "pin", "ref": "c:" + str(c["id"]), "x": p.x, "y": p.y})
		Sfx.play("card_pin")
		_close_sheet()
		_set_tab("quadro"))
	v.add_child(pin)
	_open_sheet(v)


func _clue_body(c: Dictionary) -> Control:
	return ClueView.build(c)


# ================================================================== QUADRO
func _build_board_page() -> Control:
	var page := Control.new()
	board = BoardView.new()
	page.add_child(UI.full(board))
	board.card_tapped.connect(_on_card_tapped)
	board.link_tapped.connect(_on_link_tapped)
	board.empty_tapped.connect(func() -> void:
		board.selected_ref = ""
		board.selected_link = ""
		board.queue_redraw()
		_update_action_bar())
	board.card_moved.connect(func(ref: String, p: Vector2) -> void: Net.board_op({"k": "move", "ref": ref, "x": p.x, "y": p.y}))

	var topbar := UI.hbox(12)
	topbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	topbar.offset_left = 16; topbar.offset_right = -16; topbar.offset_top = 14
	var add := UI.button("+ FIXAR", "primary", 84)
	add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.pressed.connect(_open_palette)
	topbar.add_child(add)
	var fit := UI.button("ENQUADRAR", "ghost", 84)
	fit.custom_minimum_size.x = 200
	fit.add_theme_font_override("font", UI.font("title"))
	fit.add_theme_font_size_override("font_size", 32)
	fit.pressed.connect(func() -> void: board.fit())
	topbar.add_child(fit)
	page.add_child(topbar)

	guide = PanelContainer.new()
	guide.add_theme_stylebox_override("panel", UI.box(Color(UI.NIGHT, 0.88), Color(UI.YELLOW, 0.7), 2, 16, 16))
	guide_l = UI.label("", 24, UI.PAPER, "bold")
	guide.add_child(guide_l)
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	guide.offset_left = 16; guide.offset_right = -16; guide.offset_top = 112
	page.add_child(guide)

	link_banner = PanelContainer.new()
	link_banner.add_theme_stylebox_override("panel", UI.box(UI.YELLOW, UI.INK, 0, 14, 16))
	var lb := UI.hbox(10)
	var lbl := UI.label("Agora toque na carta de DESTINO do fio.", 26, UI.INK, "bold")
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb.add_child(lbl)
	var cancel := UI.button("Cancelar", "ghost", 70)
	cancel.pressed.connect(func() -> void:
		board.link_from = ""
		link_banner.visible = false
		_update_guide()
		board.queue_redraw())
	lb.add_child(cancel)
	link_banner.add_child(lb)
	link_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	link_banner.offset_left = 16; link_banner.offset_right = -16; link_banner.offset_top = 112
	link_banner.visible = false
	page.add_child(link_banner)

	var bottom := UI.vbox(10)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16; bottom.offset_right = -16; bottom.offset_bottom = -14
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	action_bar = UI.hbox(10)
	action_bar.visible = false
	bottom.add_child(action_bar)
	submit_btn = UI.button("APRESENTAR TEORIA", "primary", 96)
	submit_btn.add_theme_stylebox_override("normal", UI.box(UI.PINK, UI.INK, 0, 20))
	submit_btn.add_theme_stylebox_override("hover", UI.box(UI.PINK.lightened(0.15), UI.INK, 0, 20))
	submit_btn.pressed.connect(_open_submit)
	bottom.add_child(submit_btn)
	page.add_child(bottom)
	return page


func _pinned_refs() -> Array:
	var out := []
	for c in Net.state.get("board", {}).get("cards", []):
		out.append(c["ref"])
	return out


func _on_card_tapped(ref: String) -> void:
	if board.link_from != "":
		if ref == board.link_from:
			return
		if ref.begins_with("c:"):
			Sfx.play("wrong", -10.0)
			get_meta("main").toast("Fios ligam pessoas, lugares e fatos. Pistas vão presas NO fio, como prova.", UI.YELLOW)
			return
		var from: String = board.link_from
		board.link_from = ""
		link_banner.visible = false
		_open_relation_picker(from.substr(2), ref.substr(2))
		return
	Sfx.play("ui_tap", -6.0)
	board.selected_ref = ref
	board.selected_link = ""
	board.queue_redraw()
	_update_action_bar()


func _update_action_bar() -> void:
	UI.clear(action_bar)
	var ref: String = board.selected_ref
	action_bar.visible = ref != ""
	if ref == "":
		return
	if not ref.begins_with("c:"):
		var link := UI.button("LIGAR COM FIO", "primary", 88)
		link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		link.add_theme_stylebox_override("normal", UI.box(UI.RED, UI.INK, 0, 20))
		link.add_theme_color_override("font_color", UI.PAPER)
		link.pressed.connect(func() -> void:
			board.link_from = ref
			board.selected_ref = ""
			link_banner.visible = true
			guide.visible = false
			Sfx.play("string_stretch")
			_update_action_bar())
		action_bar.add_child(link)
	else:
		var see := UI.button("LER", "ghost", 88)
		see.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		see.pressed.connect(func() -> void: _open_clue(Net.clue_by_id(ref.substr(2))))
		action_bar.add_child(see)
	var rm := UI.button("TIRAR", "danger", 88)
	rm.custom_minimum_size.x = 170
	rm.pressed.connect(func() -> void:
		Net.board_op({"k": "unpin", "ref": ref})
		Sfx.play("string_cut")
		board.selected_ref = ""
		_update_action_bar())
	action_bar.add_child(rm)


func _name_of(id: String) -> String:
	return UI.strip_emoji(str(Net.card_by_id(id).get("name", id)))


func _open_relation_picker(a: String, b: String) -> void:
	var v := UI.vbox(14)
	v.add_child(UI.title("QUE LIGAÇÃO É ESSA?", 46, UI.YELLOW))
	v.add_child(UI.label("O fio sai de %s e vai até %s." % [_name_of(a), _name_of(b)], 24, UI.MIST))
	for lt in Net.case_data.get("link_types", []):
		var btn := UI.button("%s  %s  %s" % [_name_of(a), str(lt["label"]).to_upper(), _name_of(b)], "ghost", 96)
		btn.add_theme_font_override("font", UI.font("bold"))
		btn.add_theme_font_size_override("font_size", 26)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(func() -> void:
			Net.board_op({"k": "link", "a": a, "b": b, "type": lt["id"]})
			Sfx.play("string_connect")
			_close_sheet())
		v.add_child(btn)
	var swap := UI.button("Inverter: começar por %s" % _name_of(b), "ghost", 76)
	swap.pressed.connect(func() -> void:
		_close_sheet()
		_open_relation_picker(b, a))
	v.add_child(swap)
	_open_sheet(v)


func _on_link_tapped(id: String) -> void:
	if board.link_from != "":
		return
	board.selected_link = id
	board.selected_ref = ""
	board.queue_redraw()
	_update_action_bar()
	var l := {}
	for x in Net.state.get("board", {}).get("links", []):
		if x["id"] == id:
			l = x
	if l.is_empty():
		return
	Sfx.play("ui_tap")
	var v := UI.vbox(14)
	v.add_child(UI.title("FIO", 40, UI.RED))
	v.add_child(UI.label("%s  %s  %s" % [_name_of(l["a"]), Net.link_label(l["type"]).to_upper(), _name_of(l["b"])], 32, UI.PAPER, "bold"))
	if l.get("evidence") != null:
		var ev := Net.clue_by_id(str(l["evidence"]))
		v.add_child(UI.label("Prova presa: " + UI.strip_emoji(str(ev.get("title", "?"))), 26, UI.YELLOW, "bold"))
	else:
		v.add_child(UI.label("Sem prova. Um fio sem prova é só um palpite.", 24, UI.MIST))
	var prove := UI.button("PRENDER UMA PROVA" if l.get("evidence") == null else "TROCAR A PROVA", "primary")
	prove.pressed.connect(func() -> void: _open_evidence_picker(id))
	v.add_child(prove)
	var row := UI.hbox(10)
	var retype := UI.button("Mudar tipo", "ghost")
	retype.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retype.pressed.connect(func() -> void:
		_close_sheet()
		_open_retype(l))
	row.add_child(retype)
	var flip := UI.button("Inverter", "ghost")
	flip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flip.pressed.connect(func() -> void:
		Net.board_op({"k": "flip", "id": id})
		Sfx.play("string_stretch")
		_close_sheet())
	row.add_child(flip)
	v.add_child(row)
	var cut := UI.button("CORTAR FIO", "danger")
	cut.pressed.connect(func() -> void:
		Net.board_op({"k": "unlink", "id": id})
		Sfx.play("string_cut")
		board.selected_link = ""
		_close_sheet())
	v.add_child(cut)
	_open_sheet(v)


func _open_retype(l: Dictionary) -> void:
	var v := UI.vbox(14)
	v.add_child(UI.title("MUDAR O TIPO", 44, UI.YELLOW))
	for lt in Net.case_data.get("link_types", []):
		var btn := UI.button("%s  %s  %s" % [_name_of(l["a"]), str(lt["label"]).to_upper(), _name_of(l["b"])], "ghost", 92)
		btn.add_theme_font_size_override("font_size", 26)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(func() -> void:
			Net.board_op({"k": "retype", "id": l["id"], "type": lt["id"]})
			Sfx.play("string_connect")
			_close_sheet())
		v.add_child(btn)
	_open_sheet(v)


func _open_evidence_picker(link_id: String) -> void:
	_close_sheet()
	var v := UI.vbox(12)
	v.add_child(UI.title("QUAL PISTA PROVA ESTE FIO?", 42, UI.YELLOW))
	var clues: Array = Net.state.get("clues", [])
	if clues.is_empty():
		v.add_child(UI.label("Vocês ainda não têm pistas.", 26, UI.MIST))
	for c in clues:
		var btn := UI.button("%s  %s" % [UI.clue_tag(str(c.get("kind", ""))), UI.strip_emoji(str(c.get("title", "")))], "ghost", 88)
		btn.add_theme_font_size_override("font_size", 24)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func() -> void:
			Net.board_op({"k": "attach", "id": link_id, "clue": c["id"]})
			Sfx.play("card_pin")
			_close_sheet())
		v.add_child(btn)
	_open_sheet(v)


func _open_palette() -> void:
	var v := UI.vbox(12)
	v.add_child(UI.title("FIXAR NO QUADRO", 46, UI.YELLOW))
	var pinned := _pinned_refs()
	var groups := [["pessoa", "PESSOAS"], ["lugar", "LUGARES"], ["fato", "FATOS"]]
	for g in groups:
		var items := []
		for c in Net.case_data.get("cards", []):
			if c["kind"] == g[0]:
				items.append(c)
		if items.is_empty():
			continue
		v.add_child(UI.title(g[1], 30, UI.MIST))
		var grid := GridContainer.new()
		grid.columns = 3 if g[0] == "pessoa" else 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		for c in items:
			grid.add_child(_palette_item(c, pinned.has("p:" + str(c["id"]))))
		v.add_child(grid)
	var clues: Array = Net.state.get("clues", [])
	var unpinned := clues.filter(func(c: Dictionary) -> bool: return not pinned.has("c:" + str(c["id"])))
	if not unpinned.is_empty():
		v.add_child(UI.title("PISTAS", 30, UI.MIST))
		for c in unpinned:
			var b := UI.button("%s  %s" % [UI.clue_tag(str(c.get("kind", ""))), UI.strip_emoji(str(c.get("title", "")))], "ghost", 80)
			b.add_theme_font_size_override("font_size", 24)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.pressed.connect(func() -> void: _pin("c:" + str(c["id"])))
			v.add_child(b)
	_open_sheet(v)


func _palette_item(c: Dictionary, pinned: bool) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = pinned
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var is_person: bool = c["kind"] == "pessoa"
	b.custom_minimum_size = Vector2(0, 230 if is_person else 100)
	b.add_theme_stylebox_override("normal", UI.box(UI.PAPER, UI.INK, 0, 8, 8))
	b.add_theme_stylebox_override("hover", UI.box(UI.YELLOW, UI.INK, 0, 8, 8))
	b.add_theme_stylebox_override("pressed", UI.box(UI.YELLOW, UI.INK, 0, 8, 8))
	b.add_theme_stylebox_override("disabled", UI.box(Color(UI.PAPER, 0.25), UI.INK, 0, 8, 8))
	var v := UI.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8; v.offset_right = -8; v.offset_top = 8; v.offset_bottom = -6
	if is_person:
		var tr := TextureRect.new()
		tr.texture = UI.portrait(str(c["id"]))
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if tr.texture == null:
			var cr := ColorRect.new()
			cr.color = Color(str(c.get("look", {}).get("top", "#26407a")))
			cr.size_flags_vertical = Control.SIZE_EXPAND_FILL
			cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(cr)
		else:
			v.add_child(tr)
	var n := UI.label(UI.strip_emoji(str(c["name"])), 22, UI.INK, "marker")
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	if is_person and str(c.get("role", "")) != "":
		var r := UI.label(str(c["role"]), 17, Color(UI.INK, 0.7))
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.max_lines_visible = 2
		v.add_child(r)
	b.add_child(v)
	b.pressed.connect(func() -> void: _pin("p:" + str(c["id"])))
	return b


func _pin(ref: String) -> void:
	var p: Vector2 = board.free_spot()
	Net.board_op({"k": "pin", "ref": ref, "x": p.x, "y": p.y})
	Sfx.play("card_pin")
	_close_sheet()


func _open_submit() -> void:
	var v := UI.vbox(14)
	v.add_child(UI.title("APRESENTAR A TEORIA?", 50, UI.PINK))
	v.add_child(UI.label("O quadro inteiro é a teoria da equipe. O caso pede:", 26, UI.PAPER))
	for cat in Net.case_data.get("categories", []):
		v.add_child(UI.label("·  " + str(cat["label"]), 28, UI.YELLOW, "bold"))
	v.add_child(UI.label("Cada fio importante precisa de uma PROVA presa nele. Se errar, a equipe espera %d segundos para tentar de novo." % int(Net.state.get("settings", {}).get("penaltySec", 45)), 24, UI.MIST))
	var go := UI.button("APRESENTAR AGORA", "primary", 110)
	if Net.case_data.get("has_culprit", false):
		# o momento alto: a equipe aponta o culpado, carta por carta
		v.add_child(UI.title(str(Net.case_data.get("culprit_question", "Quem é o responsável?")).to_upper(), 44, UI.PINK))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		var btns := []
		for c in Net.case_data.get("cards", []):
			if c["kind"] != "pessoa":
				continue
			var b := _palette_item(c, false)
			b.toggle_mode = true
			b.add_theme_stylebox_override("pressed", UI.box(UI.PINK, UI.INK, 0, 8, 8))
			btns.append(b)
			var cid := str(c["id"])
			b.pressed.connect(func() -> void:
				chosen_culprit = cid
				for o in btns:
					(o as Button).button_pressed = o == b
				Sfx.play("card_pin")
				go.disabled = false
				go.text = "ACUSAR %s E APRESENTAR" % _name_of(cid).to_upper())
			if b.pressed.get_connections().size() > 0:
				pass
			grid.add_child(b)
		v.add_child(grid)
		go.disabled = chosen_culprit == ""
		if chosen_culprit != "":
			go.text = "ACUSAR %s E APRESENTAR" % _name_of(chosen_culprit).to_upper()
	go.pressed.connect(func() -> void:
		Net.send({"t": "submit", "culprit": chosen_culprit})
		Sfx.play("submit_stamp")
		_close_sheet())
	v.add_child(go)
	_open_sheet(v)


func _show_result(r: Dictionary) -> void:
	var v := UI.vbox(14)
	if r.get("correct", false):
		v.add_child(UI.title("CASO RESOLVIDO!", 72, UI.GREEN))
		v.add_child(UI.label("A teoria de vocês fecha. Esperem a revelação no telão.", 28, UI.PAPER, "bold"))
	else:
		v.add_child(UI.title("AINDA NÃO FECHA", 64, UI.PINK))
		v.add_child(UI.label("Teoria apresentada por %s. Olhem o que falta:" % str(r.get("by", "alguém")), 24, UI.MIST))
	for cat in r.get("categories", []):
		var st := str(cat["status"])
		var info: Array = {
			"ok": ["CERTO", UI.GREEN], "incompleto": ["FALTA LIGAÇÃO", UI.YELLOW],
			"falta_prova": ["FALTA PROVA", Color("#ff9a4d")], "errado": ["TEM UM ERRO AQUI", UI.RED],
		}.get(st, ["?", UI.MIST])
		var row := UI.hbox(12)
		var l := UI.label(str(cat["label"]), 26, UI.PAPER, "bold")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var stamp := PanelContainer.new()
		stamp.add_theme_stylebox_override("panel", UI.box(Color(info[1], 0.15), info[1], 4, 6, 12))
		stamp.add_child(UI.title(info[0], 30, info[1]))
		row.add_child(stamp)
		v.add_child(row)
	var ok := UI.button("VOLTAR AO QUADRO", "ghost")
	ok.pressed.connect(_close_sheet)
	v.add_child(ok)
	_open_sheet(v)


# ================================================================== painéis
func _open_sheet(content: Control) -> void:
	_close_sheet()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_close_sheet())
	sheet_layer.add_child(UI.full(dim))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(Color(UI.NAVY, 0.98), UI.YELLOW, 3, 28, 26))
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	# na tela larga o painel vira uma folha central, não uma faixa de ponta a ponta
	var side := maxf(10.0, (size.x - 860.0) / 2.0)
	panel.offset_left = side; panel.offset_right = -side; panel.offset_bottom = -10
	panel.offset_top = -minf(size.y * 0.82, 1080)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	panel.add_child(scroll)
	sheet_layer.add_child(panel)
	# encolhe para o tamanho do conteúdo quando ele é pequeno
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	var want := content.get_combined_minimum_size().y + 60
	panel.offset_top = -minf(want, size.y * 0.82)
	panel.position.y += 60
	panel.create_tween().tween_property(panel, "position:y", panel.position.y - 60, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close_sheet() -> void:
	UI.clear(sheet_layer)


func _set_tab(k: String) -> void:
	tab = k
	for key in pages:
		(pages[key] as Control).visible = key == k
	for key in tab_btns:
		var b: Button = tab_btns[key]
		var active: bool = key == k
		b.add_theme_stylebox_override("normal", UI.box(UI.YELLOW if active else Color(0, 0, 0, 0.2), UI.YELLOW.darkened(0.4), 0 if active else 2, 18))
		b.add_theme_color_override("font_color", UI.INK if active else UI.PAPER)
	if k == "pistas":
		new_badge = 0
		for c in Net.state.get("clues", []):
			seen_clues[c["id"]] = true
		_refresh_clues()
	_update_tab_labels()
	scene3d.set_process(k == "cena")
	(scene3d as SubViewportContainer).get_child(0).render_target_update_mode = SubViewport.UPDATE_ALWAYS if k == "cena" else SubViewport.UPDATE_DISABLED


func _update_tab_labels() -> void:
	(tab_btns["pistas"] as Button).text = "PISTAS" if new_badge == 0 else "PISTAS (%d)" % new_badge


# ================================================================== estado
func refresh() -> void:
	var team := Net.my_team()
	if not team.is_empty():
		team_l.text = "EQUIPE %s" % str(team["name"]).to_upper()
		team_l.add_theme_color_override("font_color", Color(str(team["color"])))
	var bd: Dictionary = Net.state.get("board", {})
	board.set_data(bd.get("cards", []), bd.get("links", []))
	var unseen := 0
	for c in Net.state.get("clues", []):
		if not seen_clues.has(c["id"]):
			unseen += 1
	if tab == "pistas":
		for c in Net.state.get("clues", []):
			seen_clues[c["id"]] = true
		_refresh_clues()
		unseen = 0
	new_badge = unseen
	_update_tab_labels()
	# hotspots já achados pela equipe ficam apagados na cena
	for hid in Net.state.get("hotspots", []):
		scene3d.mark_found(str(hid))
	_refresh_loc_strip()
	var lr: Variant = Net.state.get("lastResult")
	if lr is Dictionary and float(lr.get("at", 0)) > last_result_at:
		var first := last_result_at == 0.0 and Time.get_ticks_msec() < 3000
		last_result_at = float(lr["at"])
		if not first:
			_show_result(lr)
	_update_submit()
	_update_guide()


func on_event(evt: Dictionary) -> void:
	if str(evt.get("k", "")) == "hotspot":
		scene3d.mark_found(str(evt.get("id", "")))


## Passo a passo para quem joga pouco: mostra só o PRÓXIMO passo, até a equipe pegar o jeito.
func _update_guide() -> void:
	var bd: Dictionary = Net.state.get("board", {})
	var people := 0
	for c in bd.get("cards", []):
		if str(c["ref"]).begins_with("p:"):
			people += 1
	var links: Array = bd.get("links", [])
	var proved := links.filter(func(l: Dictionary) -> bool: return l.get("evidence") != null).size()
	var txt := ""
	if people < 2:
		txt = "PASSO 1 de 3   Toque em + FIXAR e coloque no quadro as pessoas do caso."
	elif links.is_empty():
		txt = "PASSO 2 de 3   Toque numa pessoa e depois em LIGAR COM FIO."
	elif proved == 0:
		txt = "PASSO 3 de 3   Toque no nó vermelho do fio e prenda uma PROVA."
	elif Net.state.get("lastResult") == null:
		txt = "Isso! Liguem o resto da história e toquem em APRESENTAR TEORIA."
	guide_l.text = txt
	guide.visible = txt != "" and not link_banner.visible


func _update_submit() -> void:
	var lock := float(Net.state.get("lockUntil", 0))
	var left := int(ceil((lock - Net.server_now_ms()) / 1000.0))
	if Net.state.get("solved", false):
		submit_btn.text = "CASO RESOLVIDO"
		submit_btn.disabled = true
	elif left > 0:
		submit_btn.text = "NOVA TEORIA EM %ds" % left
		submit_btn.disabled = true
	else:
		submit_btn.text = "APRESENTAR TEORIA"
		submit_btn.disabled = false


func _process(_dt: float) -> void:
	var s := Net.seconds_left()
	timer_l.text = UI.fmt_time(s)
	if s != _last_sec:
		_last_sec = s
		if s <= 60 and s > 0:
			timer_l.add_theme_color_override("font_color", UI.RED if s % 2 == 0 else UI.YELLOW)
			Sfx.play("timer_urgent" if s <= 10 else "timer_tick", -10.0)
		_update_submit()
