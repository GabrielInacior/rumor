extends Control
## Tela do aluno durante a investigação. Três abas na base (alcance do polegar):
## CENA (explorar em 3D), PISTAS (o que só você e a equipe sabem) e QUADRO (o centro do jogo).
## Ações aparecem em painéis que sobem de baixo, um de cada vez, para não lotar a tela.

const BoardView := preload("res://scripts/board/board_view.gd")
const CaseScene := preload("res://scripts/scene3d/case_scene.gd")
const TalkView := preload("res://scripts/scene3d/talk_view.gd")
const ItemView := preload("res://scripts/ui/item_view.gd")
const TutorialIcon := preload("res://scripts/ui/tutorial_icon.gd")
const SchoolMap := preload("res://scripts/ui/school_map.gd")

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
var _guide_done_at := 0
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
var hint_btn: Button
var hints_used := 0


func _show_solo_hint() -> void:
	var hints: Array = Net.case_data.get("hints", [])
	var v := UI.vbox(14)
	v.add_child(UI.title("DICAS DO CASO", 46, UI.YELLOW))
	if hints.is_empty():
		v.add_child(UI.label("Este caso não tem dicas. Explore todos os lugares e converse com todo mundo!", 26, UI.PAPER))
	else:
		hints_used = clampi(hints_used + 1, 1, hints.size())
		for i in hints_used:
			var p := Paper.make("sticky")
			p.add_child(UI.label("%d.  %s" % [i + 1, UI.strip_emoji(str(hints[i]))], 26, UI.INK, "marker"))
			v.add_child(p)
		if hints_used < hints.size():
			v.add_child(UI.label("Toque em DICA de novo para uma dica mais forte (%d de %d)." % [hints_used, hints.size()], 21, UI.MIST))
	_open_sheet(v)
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
	# modo solo: sem professor, o próprio aluno pede dicas do caso (da mais sutil à mais forte)
	hint_btn = UI.button("DICA", "ghost", 70)
	hint_btn.add_theme_font_override("font", UI.font("title"))
	hint_btn.add_theme_font_size_override("font_size", 28)
	hint_btn.custom_minimum_size.x = 120
	hint_btn.visible = false
	hint_btn.pressed.connect(_show_solo_hint)
	th.add_child(hint_btn)
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


## A aura e o balão de "novo" somem para quem ESTE jogador já interrogou (cada aluno vê os seus).
func _apply_talked() -> void:
	if not scene3d.has_method("set_talked"):
		return
	for f in (Net.state.get("flags", {}) as Dictionary).keys():
		var parts := str(f).split(":")
		if parts.size() >= 3 and parts[0] == "talk" and parts[2] == Net.my_name:
			scene3d.call("set_talked", parts[1], true)


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
	_apply_talked()
	_refresh_loc_strip()
	Sfx.play("paper_flip", -8.0)


func _remaining_by_room() -> Dictionary:
	var found: Array = Net.state.get("hotspots", [])
	var out := {}
	for h in Net.case_data.get("hotspots", []):
		var room := str(h.get("scene", locations[0]))
		if not found.has(h["id"]):
			out[room] = int(out.get(room, 0)) + 1
	return out


## No topo da cena fica só um botão: a sala atual + MAPA. O mapa da escola mostra o resto.
func _refresh_loc_strip() -> void:
	if loc_strip == null:
		return
	UI.clear(loc_strip)
	var rem := _remaining_by_room()
	var total := 0
	for k in rem:
		total += int(rem[k])
	var b := UI.button("MAPA  ·  " + str(LOC_NAMES.get(loc, loc)).to_upper() + ("   (%d pista%s pelo mapa)" % [total, "" if total == 1 else "s"] if total > 0 else ""), "primary", 72)
	b.add_theme_font_override("font", UI.font("title"))
	b.add_theme_font_size_override("font_size", 30)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_open_map)
	loc_strip.add_child(b)


func _open_map() -> void:
	_close_sheet()
	var dim := ColorRect.new()
	dim.color = Color(UI.NIGHT, 0.96)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet_layer.add_child(UI.full(dim))
	var m := UI.margin(14, 14, 14)
	sheet_layer.add_child(UI.full(m))
	var v := UI.vbox(10)
	m.add_child(v)
	var h := UI.hbox(10)
	var t := UI.title("MAPA DA ESCOLA", 46, UI.YELLOW)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var close := UI.button("VOLTAR", "ghost", 66)
	close.custom_minimum_size.x = 170
	close.pressed.connect(_close_sheet)
	h.add_child(close)
	v.add_child(h)
	v.add_child(UI.label("Toque numa sala do caso para ir até ela. As salas apagadas não fazem parte desta investigação.", 20, UI.MIST))
	var mp := SchoolMap.new()
	mp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mp.locations = locations
	mp.current = loc
	mp.remaining = _remaining_by_room()
	var ppl := {}
	for e in Net.case_data.get("scene_people", []):
		if e is Dictionary:
			var room := str(e.get("scene", ""))
			if not ppl.has(room):
				ppl[room] = []
			ppl[room].append(_name_of(str(e.get("id", ""))))
	mp.people = ppl
	mp.room_chosen.connect(func(id: String) -> void:
		_close_sheet()
		if id != loc:
			_load_location(id))
	v.add_child(mp)


func _narrate(text: String, important: bool) -> void:
	narr_l.text = text
	narr_panel.visible = true
	narr_panel.modulate.a = 1.0
	Sfx.play("paper_flip", -6.0)
	var tw := narr_panel.create_tween()
	tw.tween_interval(7.5 if important else 5.5)
	tw.tween_property(narr_panel, "modulate:a", 0.0, 1.0)
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
		tv.finished.connect(func() -> void:
			scene3d.set_process(tab == "cena")
			if scene3d.has_method("set_talked"):
				scene3d.call("set_talked", pid, true))
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
	tv.finished.connect(func() -> void:
		scene3d.set_process(tab == "cena")
		if scene3d.has_method("set_talked"):
			scene3d.call("set_talked", str(card.get("id", "")), true))


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
	clue_scroll = scroll
	scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _clue_busy_until = Time.get_ticks_msec() + 1400)
	scroll.gui_input.connect(func(_e: InputEvent) -> void: _clue_busy_until = Time.get_ticks_msec() + 1400)
	clue_list = UI.vbox(14)
	clue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(clue_list)
	v.add_child(scroll)
	return m


var clue_scroll: ScrollContainer
var _clue_busy_until := 0
var _clue_pending := false


func _refresh_clues() -> void:
	# não refaz a lista no meio de uma rolagem; guarda a posição quando refaz
	if Time.get_ticks_msec() < _clue_busy_until:
		_clue_pending = true
		return
	_clue_pending = false
	var keep := clue_scroll.scroll_vertical if clue_scroll else 0
	_build_clue_list()
	if clue_scroll:
		clue_scroll.set_deferred("scroll_vertical", keep)


func _build_clue_list() -> void:
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
	# mochila da equipe: a mochila gira em 3D e cada objeto aparece como modelo low-poly
	# mochila compacta: uma faixa só, com a mochila 3D pequena e os objetos em miniatura
	var bag := PanelContainer.new()
	bag.add_theme_stylebox_override("panel", UI.box(Color(UI.NIGHT, 0.75), Color(UI.YELLOW, 0.4), 2, 18, 10))
	var bh := UI.hbox(10)
	var iv := ItemView.new()
	iv.kind = "mochila"
	iv.custom_minimum_size = Vector2(80, 80)
	bh.add_child(iv)
	var bv := UI.vbox(4)
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bt := UI.title("MOCHILA" + ("" if items.is_empty() else "  (%d)" % items.size()), 30, UI.YELLOW)
	bv.add_child(bt)
	if items.is_empty():
		bv.add_child(UI.label("Vazia. Objetos achados nas cenas vêm para cá.", 19, UI.MIST))
	else:
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		for iid in items:
			var it := {}
			for x in Net.case_data.get("items", []):
				if x["id"] == iid:
					it = x
			flow.add_child(_item_card(it if not it.is_empty() else {"id": iid, "name": iid}))
		bv.add_child(flow)
	bh.add_child(bv)
	bag.add_child(bh)
	clue_list.add_child(bag)
	clue_list.add_child(UI.title("PISTAS", 34, UI.YELLOW))
	for c in sorted:
		clue_list.add_child(_clue_row(c, mine.has(c["id"]), on_board.has("c:" + str(c["id"]))))
	if clues.is_empty():
		clue_list.add_child(UI.label("Nenhuma pista ainda. Explore a CENA!", 28, UI.MIST, "type"))
	UI.scroll_friendly(clue_list)


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


func _item_card(it: Dictionary) -> Control:
	# miniatura: foto do objeto 3D com o nome embaixo (toque longo mostra a descrição)
	var p := Paper.make("card")
	p.custom_minimum_size = Vector2(128, 0)
	var v := UI.vbox(2)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(104, 70)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var key := "item:" + ItemModels.kind_for(it)
	tr.texture = Snap.get_tex(key)
	if tr.texture == null:
		Snap.photo_ready.connect(func(k: String) -> void:
			if k == key and is_instance_valid(tr):
				tr.texture = Snap.get_tex(key), CONNECT_ONE_SHOT)
	v.add_child(tr)
	var n := UI.label(UI.strip_emoji(str(it.get("name", ""))), 17, UI.INK, "marker")
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.custom_minimum_size.x = 104
	n.max_lines_visible = 2
	v.add_child(n)
	p.add_child(v)
	p.tooltip_text = str(it.get("desc", ""))
	return p


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
	# atalhos de arrastar: pessoa até pessoa = ligar; pista até fio = prender a prova
	board.link_dropped.connect(func(a: String, b: String) -> void:
		Sfx.play("string_stretch")
		_open_relation_picker(a, b))
	board.evidence_dropped.connect(func(link_id: String, clue_id: String) -> void:
		Net.board_op({"k": "attach", "id": link_id, "clue": clue_id})
		Sfx.play("card_pin")
		get_meta("main").toast("Prova presa no fio!", UI.GREEN))

	var topbar := UI.hbox(12)
	topbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	topbar.offset_left = 16; topbar.offset_right = -16; topbar.offset_top = 14
	var add := UI.button("+ FIXAR", "primary", 84)
	add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.pressed.connect(_open_palette)
	topbar.add_child(add)
	var org := UI.button("ORGANIZAR", "ghost", 84)
	org.custom_minimum_size.x = 170
	org.add_theme_font_override("font", UI.font("title"))
	org.add_theme_font_size_override("font_size", 30)
	org.pressed.connect(_organize_board)
	topbar.add_child(org)
	var fit := UI.button("ENQUADRAR", "ghost", 84)
	fit.custom_minimum_size.x = 170
	fit.add_theme_font_override("font", UI.font("title"))
	fit.add_theme_font_size_override("font_size", 30)
	fit.pressed.connect(func() -> void: board.fit())
	topbar.add_child(fit)
	page.add_child(topbar)

	guide = PanelContainer.new()
	guide.add_theme_stylebox_override("panel", UI.box(Color(UI.NIGHT, 0.88), Color(UI.YELLOW, 0.7), 2, 16, 16))
	guide_l = UI.label("", 24, UI.PAPER, "bold")
	guide.add_child(guide_l)
	guide.mouse_filter = Control.MOUSE_FILTER_STOP
	guide_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# tocar na faixa de dica abre o guia ilustrado de novo
	guide.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_board_tutorial())
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
	var story_btn := UI.button("LER A HISTÓRIA DO QUADRO", "ghost", 70)
	story_btn.add_theme_font_override("font", UI.font("title"))
	story_btn.add_theme_font_size_override("font_size", 30)
	story_btn.add_theme_stylebox_override("normal", UI.box(Color(UI.NIGHT, 0.85), UI.YELLOW, 2, 18))
	story_btn.pressed.connect(_open_story)
	bottom.add_child(story_btn)
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
		see.custom_minimum_size.x = 130
		see.pressed.connect(func() -> void: _open_clue(Net.clue_by_id(ref.substr(2))))
		action_bar.add_child(see)
		var att := UI.button("PRENDER NUM FIO", "primary", 88)
		att.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		att.add_theme_font_size_override("font_size", 32)
		att.pressed.connect(func() -> void: _open_link_picker_for_clue(ref.substr(2)))
		action_bar.add_child(att)
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


var link_color := "vermelho"


## fileira de cores de fio: cada equipe pode combinar um código (ex.: amarelo = mentira)
func _color_row(selected: String, on_pick: Callable) -> Control:
	var row := UI.hbox(12)
	for cname in ["vermelho", "amarelo", "azul", "verde", "rosa"]:
		var col: Color = BoardView.LINK_COLORS[cname]
		var sw := Button.new()
		sw.focus_mode = Control.FOCUS_NONE
		sw.custom_minimum_size = Vector2(88, 72)
		sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var on: bool = cname == selected
		sw.add_theme_stylebox_override("normal", UI.box(col, Color.WHITE if on else Color(0, 0, 0, 0.4), 5 if on else 2, 36))
		sw.add_theme_stylebox_override("hover", UI.box(col.lightened(0.15), Color.WHITE, 4, 36))
		sw.add_theme_stylebox_override("pressed", UI.box(col.darkened(0.2), Color.WHITE, 5, 36))
		sw.pressed.connect(func() -> void:
			Sfx.play("ui_tap")
			on_pick.call(cname))
		row.add_child(sw)
	return row


## Frases sempre fazem sentido: a ordem é escolhida pelo TIPO das cartas (pessoa antes de lugar
## ou fato) e só aparecem as ligações que existem para aquele par neste caso.
func _kind_of(id: String) -> String:
	return str(Net.card_by_id(id).get("kind", "fato"))


func _pairs_of(lt: Dictionary) -> Array:
	var p: Array = lt.get("pairs", [])
	if not p.is_empty():
		return p
	# caso sem regra no servidor: deduz pelo rótulo ("estava em" liga pessoa a lugar)
	var lbl := str(lt.get("label", "")).to_lower()
	if lbl.ends_with(" em") or lbl.ends_with(" no") or lbl.ends_with(" na"):
		return ["pessoa>lugar"]
	if lbl.ends_with(" para") or lbl.begins_with("viu"):
		return ["pessoa>pessoa"]
	return ["pessoa>fato", "pessoa>pessoa"]


func _open_relation_picker(a: String, b: String) -> void:
	var ka := _kind_of(a)
	var kb := _kind_of(b)
	var options := []   # [from, to, link_type]
	for lt in Net.case_data.get("link_types", []):
		var pairs := _pairs_of(lt)
		if pairs.has(ka + ">" + kb):
			options.append([a, b, lt])
		elif pairs.has(kb + ">" + ka):
			options.append([b, a, lt])
	var v := UI.vbox(14)
	v.add_child(UI.title("QUE LIGAÇÃO É ESSA?", 46, UI.YELLOW))
	if options.is_empty():
		v.add_child(UI.label("%s e %s não se ligam diretamente neste caso." % [_name_of(a), _name_of(b)], 26, UI.PAPER, "bold"))
		v.add_child(UI.label("Dica: ligue PESSOAS a outras pessoas, a LUGARES ou a FATOS.", 22, UI.MIST))
		var ok := UI.button("ENTENDI", "primary", 90)
		ok.pressed.connect(_close_sheet)
		v.add_child(ok)
		_open_sheet(v)
		return
	v.add_child(UI.label("Cor do fio", 22, UI.PAPER, "bold"))
	v.add_child(_color_row(link_color, func(cname: String) -> void:
		link_color = cname
		_close_sheet()
		_open_relation_picker(a, b)))
	for op in options:
		var lt: Dictionary = op[2]
		var f: String = op[0]
		var t: String = op[1]
		var btn := UI.button("%s  %s  %s" % [_name_of(f), str(lt["label"]).to_upper(), _name_of(t)], "ghost", 96)
		btn.add_theme_font_override("font", UI.font("bold"))
		btn.add_theme_font_size_override("font_size", 26)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(func() -> void:
			Net.board_op({"k": "link", "a": f, "b": t, "type": lt["id"], "color": link_color})
			Sfx.play("string_connect")
			_close_sheet())
		v.add_child(btn)
	# inverter só faz sentido entre cartas do mesmo tipo (ex.: quem contou para quem)
	if ka == kb:
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
	# o fio vira um quadrinho: quem fez, a ação, com quem/onde, a fala da prova e o carimbo
	v.add_child(UI.label("Assim o seu quadro conta esta parte da história (pode estar certa ou errada):", 20, UI.MIST))
	v.add_child(StoryPanel.panel(l))
	if l.get("evidence") != null:
		var rel := _relevance(Net.clue_by_id(str(l["evidence"])), l["a"], l["b"])
		if int(rel[0]) == 0:
			v.add_child(UI.label("Atenção: essa prova não cita ninguém deste fio. Ela prova mesmo isso?", 21, UI.PINK, "bold"))
	v.add_child(UI.label("Cor do fio", 22, UI.PAPER, "bold"))
	v.add_child(_color_row(str(l.get("color", "vermelho")), func(cname: String) -> void:
		Net.board_op({"k": "recolor", "id": id, "color": cname})
		_close_sheet()))
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
	flip.visible = _kind_of(str(l["a"])) == _kind_of(str(l["b"]))
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
		if not _pairs_of(lt).has(_kind_of(str(l["a"])) + ">" + _kind_of(str(l["b"]))):
			continue
		var btn := UI.button("%s  %s  %s" % [_name_of(l["a"]), str(lt["label"]).to_upper(), _name_of(l["b"])], "ghost", 92)
		btn.add_theme_font_size_override("font_size", 26)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(func() -> void:
			Net.board_op({"k": "retype", "id": l["id"], "type": lt["id"]})
			Sfx.play("string_connect")
			_close_sheet())
		v.add_child(btn)
	_open_sheet(v)


## Caminho sem arrastar: escolhe em qual fio prender esta pista
func _open_link_picker_for_clue(clue_id: String) -> void:
	var links: Array = Net.state.get("board", {}).get("links", [])
	var v := UI.vbox(12)
	v.add_child(UI.title("PRENDER EM QUAL FIO?", 44, UI.YELLOW))
	v.add_child(UI.label("A pista \"%s\" vai ficar presa no fio como prova." % UI.strip_emoji(str(Net.clue_by_id(clue_id).get("title", ""))), 22, UI.MIST))
	if links.is_empty():
		v.add_child(UI.label("Ainda não há fios. Primeiro ligue duas cartas (arraste uma até a outra).", 24, UI.PAPER))
	for l in links:
		var txt := "%s  %s  %s" % [_name_of(l["a"]), Net.link_label(l["type"]).to_upper(), _name_of(l["b"])]
		if l.get("evidence") != null:
			txt += "   (já tem prova: trocar)"
		var b := UI.button(txt, "ghost", 84)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 24)
		var lid: String = l["id"]
		b.pressed.connect(func() -> void:
			Net.board_op({"k": "attach", "id": lid, "clue": clue_id})
			Sfx.play("card_pin")
			board.selected_ref = ""
			_update_action_bar()
			_close_sheet()
			get_meta("main").toast("Prova presa no fio!", UI.GREEN))
		v.add_child(b)
	_open_sheet(v)


## Organiza o quadro: pessoas num círculo, lugares e fatos no meio, pistas soltas embaixo
func _organize_board() -> void:
	var cards: Array = Net.state.get("board", {}).get("cards", [])
	var people := []
	var mids := []
	var loose := []
	var ev := {}
	for l in Net.state.get("board", {}).get("links", []):
		if l.get("evidence") != null:
			ev[str(l["evidence"])] = true
	for c in cards:
		var ref: String = c["ref"]
		if ref.begins_with("c:"):
			if not ev.has(ref.substr(2)):
				loose.append(ref)
		elif str(Net.card_by_id(ref.substr(2)).get("kind", "")) == "pessoa":
			people.append(ref)
		else:
			mids.append(ref)
	var moves := []
	for i in people.size():
		var a := TAU * i / maxf(1, people.size()) - PI / 2.0
		moves.append([people[i], Vector2(0.5 + cos(a) * 0.36, 0.44 + sin(a) * 0.32)])
	for i in mids.size():
		var a2 := TAU * i / maxf(1, mids.size()) + PI / 4.0
		var r := 0.0 if mids.size() == 1 else 0.14
		moves.append([mids[i], Vector2(0.5 + cos(a2) * r, 0.44 + sin(a2) * r)])
	for i in loose.size():
		moves.append([loose[i], Vector2(0.12 + (i % 5) * 0.19, 0.86 + (i / 5) * 0.08)])
	for mv in moves:
		var p: Vector2 = mv[1]
		Net.board_op({"k": "move", "ref": mv[0], "x": clampf(p.x, 0.06, 0.94), "y": clampf(p.y, 0.06, 0.94)})
	# atualiza na hora localmente (o servidor confirma)
	for c in cards:
		for mv in moves:
			if mv[0] == c["ref"]:
				c["x"] = (mv[1] as Vector2).x
				c["y"] = (mv[1] as Vector2).y
	board.set_data(cards, Net.state.get("board", {}).get("links", []))
	board.call_deferred("fit")
	Sfx.play("card_drop")


func _mentions(clue: Dictionary, card_id: String) -> bool:
	var txt := (str(clue.get("title", "")) + " " + str(clue.get("text", ""))).to_lower()
	if clue.has("chat"):
		for l in clue["chat"].get("lines", []):
			txt += " " + str(l.get("who", "")) + " " + str(l.get("text", ""))
	if clue.has("post"):
		txt += " " + str(clue["post"].get("who", "")) + " " + str(clue["post"].get("caption", ""))
	txt += " " + str(clue.get("who", "")) + " " + str(clue.get("from", ""))
	txt = txt.to_lower()
	var nm := _name_of(card_id).to_lower()
	# nome completo ou a palavra principal (ex.: "Profa. Lúcia" -> "lúcia")
	if txt.find(card_id.to_lower()) >= 0 or txt.find(nm) >= 0:
		return true
	for part in nm.split(" "):
		if part.length() >= 4 and txt.find(part) >= 0:
			return true
	return false


func _relevance(clue: Dictionary, a: String, b: String) -> Array:
	var ma := _mentions(clue, a)
	var mb := _mentions(clue, b)
	if ma and mb:
		return [2, "fala de %s e %s" % [_name_of(a), _name_of(b)], UI.GREEN]
	if ma or mb:
		return [1, "fala de %s" % _name_of(a if ma else b), UI.YELLOW]
	return [0, "não cita ninguém deste fio", UI.MIST]


## Frase do fio em linguagem simples (é o que o fio "afirma" no quadro)
func _sentence(l: Dictionary) -> String:
	return "%s %s %s" % [_name_of(l["a"]).to_upper(), Net.link_label(l["type"]), _name_of(l["b"]).to_upper()]


func _first_sentence(t: String, max_len := 150) -> String:
	t = UI.strip_emoji(t).replace("\n", " ").strip_edges()
	if t.length() <= max_len:
		return t
	var cut := t.substr(0, max_len)
	var dot := cut.rfind(". ")
	return (cut.substr(0, dot + 1) if dot > 40 else cut + "...")


func _open_evidence_picker(link_id: String) -> void:
	_close_sheet()
	var v := UI.vbox(12)
	v.add_child(UI.title("QUAL PISTA PROVA ESTE FIO?", 42, UI.YELLOW))
	var clues: Array = Net.state.get("clues", [])
	if clues.is_empty():
		v.add_child(UI.label("Vocês ainda não têm pistas.", 26, UI.MIST))
	var lk := {}
	for x in Net.state.get("board", {}).get("links", []):
		if x["id"] == link_id:
			lk = x
	if not lk.is_empty():
		v.add_child(UI.label("O fio diz: " + _sentence(lk) + ". Qual pista mostra isso?", 22, UI.PAPER, "bold"))
	var ranked := clues.duplicate()
	if not lk.is_empty():
		ranked.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
			return int(_relevance(x, lk["a"], lk["b"])[0]) > int(_relevance(y, lk["a"], lk["b"])[0]))
	for c in ranked:
		var row := Button.new()
		row.focus_mode = Control.FOCUS_NONE
		row.custom_minimum_size = Vector2(0, 104)
		row.add_theme_stylebox_override("normal", UI.box(Color(UI.NIGHT, 0.85), Color(UI.SKY, 0.5), 2, 16))
		row.add_theme_stylebox_override("hover", UI.box(Color(UI.BLUE, 0.4), UI.YELLOW, 2, 16))
		row.add_theme_stylebox_override("pressed", UI.box(Color(UI.YELLOW, 0.3), UI.YELLOW, 2, 16))
		var rv := UI.vbox(2)
		rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rv.offset_left = 16; rv.offset_right = -12; rv.offset_top = 10
		var t1 := UI.label("%s  ·  %s" % [UI.clue_tag(str(c.get("kind", ""))), UI.strip_emoji(str(c.get("title", "")))], 24, UI.PAPER, "bold")
		t1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t1.autowrap_mode = TextServer.AUTOWRAP_OFF
		t1.clip_text = true
		rv.add_child(t1)
		if not lk.is_empty():
			var rel := _relevance(c, lk["a"], lk["b"])
			var rl := UI.label(str(rel[1]), 20, rel[2], "bold")
			rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rl.autowrap_mode = TextServer.AUTOWRAP_OFF
			rl.clip_text = true
			rv.add_child(rl)
		row.add_child(rv)
		row.pressed.connect(func() -> void:
			Net.board_op({"k": "attach", "id": link_id, "clue": c["id"]})
			Sfx.play("card_pin")
			_close_sheet())
		v.add_child(row)
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


func _open_story() -> void:
	Sfx.play("paper_flip")
	_open_sheet(StoryPanel.story(Net.state.get("board", {}).get("links", []), chosen_culprit))


func _open_submit() -> void:
	var v := UI.vbox(14)
	v.add_child(UI.title("APRESENTAR A TEORIA?", 50, UI.PINK))
	v.add_child(UI.label("O quadro inteiro é a teoria da equipe. O caso pede:", 26, UI.PAPER))
	var read := UI.button("Ler a história do quadro antes", "ghost", 70)
	read.pressed.connect(func() -> void:
		_close_sheet()
		_open_story())
	v.add_child(read)
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
	# botão VOLTAR fixo no topo (fora da rolagem): sempre visível, mesmo em pista longa no celular em pé
	var frame := UI.vbox(10)
	var back := UI.button("VOLTAR", "ghost", 72)
	back.add_theme_font_override("font", UI.font("title"))
	back.add_theme_font_size_override("font_size", 32)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.custom_minimum_size.x = 220
	back.pressed.connect(_close_sheet)
	frame.add_child(back)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	UI.scroll_friendly(content)
	frame.add_child(scroll)
	panel.add_child(frame)
	sheet_layer.add_child(panel)
	# encolhe para o tamanho do conteúdo quando ele é pequeno
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	var want := content.get_combined_minimum_size().y + 150
	panel.offset_top = -minf(want, size.y * 0.82)
	panel.position.y += 60
	panel.create_tween().tween_property(panel, "position:y", panel.position.y - 60, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close_sheet() -> void:
	UI.clear(sheet_layer)


var _board_tutorial_shown := false


## Guia de 3 passos desenhado, na primeira vez que o aluno abre o quadro.
func _board_tutorial() -> void:
	_board_tutorial_shown = true
	var v := UI.vbox(16)
	v.add_child(UI.title("COMO MONTAR O QUADRO", 50, UI.YELLOW))
	var steps := [
		["1", "FIXE", "Toque em + FIXAR e coloque pessoas, lugares e fatos no quadro.", "pessoa"],
		["2", "LIGUE", "Arraste uma carta até outra. Escolha o que uma fez com a outra.", "fio"],
		["3", "PROVE", "Arraste a pista até o fio. Ela fica presa nele como PROVA.", "prova"],
	]
	for st in steps:
		var row := Paper.make("card")
		var h := UI.hbox(16)
		var ill := TutorialIcon.new()
		ill.kind = st[3]
		ill.custom_minimum_size = Vector2(150, 110)
		h.add_child(ill)
		var sv := UI.vbox(2)
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t := UI.title(st[0] + "  " + st[1], 42, UI.RED)
		sv.add_child(t)
		sv.add_child(UI.label(st[2], 24, UI.INK, "bold"))
		h.add_child(sv)
		row.add_child(h)
		v.add_child(row)
	v.add_child(UI.label("Depois, aponte o culpado e toque em APRESENTAR TEORIA. O quadro inteiro é a teoria da equipe.", 23, UI.PAPER))
	var ok := UI.button("ENTENDI", "primary", 100)
	ok.pressed.connect(_close_sheet)
	v.add_child(ok)
	_open_sheet(v)


func _set_tab(k: String) -> void:
	if k == "quadro" and not _board_tutorial_shown and (Net.state.get("board", {}).get("links", []) as Array).is_empty():
		_board_tutorial.call_deferred()
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
	if Net.state.get("solo", false):
		team_l.text = "INVESTIGAÇÃO SOLO"
		team_l.add_theme_color_override("font_color", UI.YELLOW)
		if hint_btn and not hint_btn.visible:
			hint_btn.visible = true
	elif not team.is_empty():
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
	_apply_talked()
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
		txt = "PASSO 2 de 3   ARRASTE uma pessoa até outra para ligar com um fio."
	elif proved == 0:
		txt = "PASSO 3 de 3   ARRASTE uma pista até o fio para prender a PROVA."
	elif Net.state.get("lastResult") == null:
		txt = "Isso! Liguem o resto da história e toquem em APRESENTAR TEORIA."
		# a última dica fica só alguns segundos: depois o quadro ganha o espaço todo
		if _guide_done_at == 0:
			_guide_done_at = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - _guide_done_at > 9000:
			txt = ""
	if txt != "":
		txt += "   (toque para ver como)"
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
	if _clue_pending and tab == "pistas" and Time.get_ticks_msec() >= _clue_busy_until:
		_refresh_clues()
	var s := Net.seconds_left()
	timer_l.text = UI.fmt_time(s)
	if s != _last_sec:
		_last_sec = s
		if s <= 60 and s > 0:
			timer_l.add_theme_color_override("font_color", UI.RED if s % 2 == 0 else UI.YELLOW)
			Sfx.play("timer_urgent" if s <= 10 else "timer_tick", -10.0)
		_update_submit()
