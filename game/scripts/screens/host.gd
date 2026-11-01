extends Control
## Tela do professor, feita para o projetor mas que funciona no celular também.
## Lobby: código gigante, escolha do caso e das equipes. Rodada: cronômetro, progresso de cada
## equipe (sem revelar a resposta), quadro de qualquer equipe ao vivo e os controles da aula.

const BoardView := preload("res://scripts/board/board_view.gd")

var body: Control
var phase_built := ""
var timer_l: Label
var teams_box: Container
var viewer_layer: Control
var viewer_board: Control
var viewer_team := ""
var lobby_cases: Container
var lobby_teams: Container
var lobby_count: Label
var _last_sec := -1


func _ready() -> void:
	body = Control.new()
	add_child(UI.full(body))
	viewer_layer = Control.new()
	viewer_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UI.full(viewer_layer))
	Sfx.set_ambience("ambience_room_tone_loop")
	Net.guide_loaded.connect(func() -> void:
		_guide_dirty = true
		if phase_built == "game" and game_tab == "guia":
			_refresh_game())


## No PC, texto longo numa coluna central de leitura; no celular, a largura toda.
func _reading_column(c: Control) -> Control:
	if not _wide():
		return c
	var h := UI.hbox(0)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Control.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	c.custom_minimum_size.x = 1300
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	h.add_child(c)
	var r := Control.new()
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(r)
	return h


func _wide() -> bool:
	return size.x > size.y * 1.1


func refresh() -> void:
	var phase := str(Net.state.get("phase", ""))
	if phase == "":
		_build_waiting()
		return
	var want := "lobby" if phase == "lobby" else "game"
	if want != phase_built:
		phase_built = want
		if want == "lobby":
			_build_lobby()
		else:
			_build_game()
	if want == "lobby":
		_refresh_lobby()
	else:
		_refresh_game()


func _build_waiting() -> void:
	UI.clear(body)
	var c := CenterContainer.new()
	body.add_child(UI.full(c))
	var v := UI.vbox(24)
	v.add_child(UI.title("CRIANDO A SALA...", 70))
	# se o servidor não responder, o professor não fica preso aqui
	var back := UI.button("Voltar", "ghost", 80)
	back.pressed.connect(func() -> void: get_meta("main").go_home())
	v.add_child(back)
	c.add_child(v)


# ================================================================== LOBBY
func _host_url() -> String:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("location.host", true))
	return "o endereço do servidor"


const MANILA := Color("#d9b977")
const MANILA_EDGE := Color("#b8944f")
const DOC_INK := Color("#1b2140")


func _build_lobby() -> void:
	UI.clear(body)
	var wide := _wide()
	var m := UI.margin(36 if wide else 20, 24 if wide else 20, 18)
	body.add_child(UI.full(m))
	var page := UI.vbox(12)
	m.add_child(page)
	# topo: crachá da diretoria + código da sala (o que os alunos precisam ver) + contador
	var badge := UI.label("DIRETORIA DE INVESTIGAÇÃO  ·  PROF. AILSON", 20, UI.PINK, "type")
	badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	badge.clip_text = true
	page.add_child(badge)
	var head := UI.hbox(16)
	var hv := UI.vbox(0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var url := UI.label("Entrem em " + _host_url() + " e digitem o código", 22, UI.MIST, "bold")
	url.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(url)
	hv.add_child(UI.title("SALA " + Net.code, 120 if wide else 92, UI.YELLOW))
	head.add_child(hv)
	var cnt_box := PanelContainer.new()
	cnt_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cnt_box.add_theme_stylebox_override("panel", UI.box(Color(UI.YELLOW, 0.12), UI.YELLOW, 2, 18, 14))
	var cv := UI.vbox(0)
	lobby_count = UI.title("0", 64, UI.YELLOW)
	lobby_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(lobby_count)
	var cl := UI.label("na sala", 20, UI.PAPER, "bold")
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.autowrap_mode = TextServer.AUTOWRAP_OFF
	cv.add_child(cl)
	cnt_box.add_child(cv)
	head.add_child(cnt_box)
	page.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var inner := UI.vbox(12)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	# caso escolhido (pasta parda numa linha) + TROCAR / GUIA
	lobby_cases = UI.vbox(0)
	lobby_cases.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(lobby_cases)
	# ajustes numa faixa só: equipes e tempo
	var row: BoxContainer = UI.hbox(14) if wide else UI.vbox(10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(row)
	row.add_child(_stepper("EQUIPES", "TeamCount",
		func() -> void: Net.send({"t": "host_settings", "teamCount": int(Net.state["settings"]["teamCount"]) - 1}),
		func() -> void: Net.send({"t": "host_settings", "teamCount": int(Net.state["settings"]["teamCount"]) + 1}),
		"Sortear", func() -> void: Net.send({"t": "host_shuffle"})))

	lobby_teams = GridContainer.new()
	(lobby_teams as GridContainer).columns = 3 if wide else 2
	lobby_teams.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_teams.add_theme_constant_override("h_separation", 10)
	lobby_teams.add_theme_constant_override("v_separation", 10)
	inner.add_child(lobby_teams)
	# rodapé fixo: fechar (pequeno) + começar (grande)
	var foot := UI.hbox(12)
	var leave := UI.button("Fechar", "ghost", 96)
	leave.custom_minimum_size.x = 150
	leave.pressed.connect(func() -> void: get_meta("main").go_home())
	foot.add_child(leave)
	var start := UI.button("COMEÇAR O CASO", "primary", 96)
	start.add_theme_font_size_override("font_size", 44)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.name = "Start"
	start.pressed.connect(func() -> void: Net.send({"t": "host_start"}))
	foot.add_child(start)
	page.add_child(foot)


## Faixa compacta "RÓTULO  [-] valor [+]  (ação)".
func _stepper(label: String, value_name: String, minus_cb: Callable, plus_cb: Callable, extra := "", extra_cb := Callable()) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", UI.box(Color(UI.NAVY, 0.9), Color(UI.SKY, 0.4), 2, 16, 10))
	var h := UI.hbox(8)
	var l := UI.label(label, 22, UI.MIST, "type")
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.custom_minimum_size.x = 110
	h.add_child(l)
	var mi := UI.button("-", "ghost", 68)
	mi.custom_minimum_size.x = 68
	mi.pressed.connect(minus_cb)
	h.add_child(mi)
	var v := UI.title("", 44, UI.YELLOW)
	v.name = value_name
	v.custom_minimum_size.x = 96
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(v)
	var pl := UI.button("+", "ghost", 68)
	pl.custom_minimum_size.x = 68
	pl.pressed.connect(plus_cb)
	h.add_child(pl)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	if extra != "":
		var ex := UI.button(extra, "ghost", 68)
		ex.custom_minimum_size.x = 130
		ex.pressed.connect(extra_cb)
		h.add_child(ex)
	p.add_child(h)
	return p


func _diff_name(d: int) -> String:
	return ["FÁCIL", "MÉDIO", "DIFÍCIL"][clampi(d, 1, 3) - 1]


func _case_thumb(c: Dictionary, side: float) -> Control:
	var ph := PanelContainer.new()
	ph.add_theme_stylebox_override("panel", UI.box(Color("#f7f3ea"), Color.TRANSPARENT, 0, 3, 6))
	ph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(side, side)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.texture = UI.case_icon(str(c.get("id", "")))
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ph.add_child(tr)
	return ph


## Janela para escolher o caso da aula (lista compacta, um toque escolhe e fecha).
func _open_case_picker() -> void:
	UI.clear(viewer_layer)
	var bg := ColorRect.new()
	bg.color = Color(UI.NIGHT, 0.94)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	viewer_layer.add_child(UI.full(bg))
	var m := UI.margin(20, 24, 20)
	viewer_layer.add_child(UI.full(m))
	var v := UI.vbox(10)
	m.add_child(v)
	var h := UI.hbox(10)
	var tl := UI.title("ESCOLHA O CASO", 52, UI.YELLOW)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(tl)
	var close := UI.button("Fechar", "ghost", 72)
	close.custom_minimum_size.x = 150
	close.pressed.connect(func() -> void: UI.clear(viewer_layer))
	h.add_child(close)
	v.add_child(h)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var lst := UI.vbox(10)
	lst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(lst)
	TouchScroll.attach(sc)
	var sel := str(Net.state.get("settings", {}).get("caseId", ""))
	var cases: Array = (Net.state.get("cases", []) as Array).duplicate()
	cases.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("difficulty", 1)) < int(b.get("difficulty", 1)))
	var n := 0
	for c in cases:
		n += 1
		var on: bool = c["id"] == sel
		var d := int(c.get("difficulty", 1))
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 156)
		b.add_theme_stylebox_override("normal", UI.box(MANILA if on else Color("#efe6cf"), Color("#c42c3f") if on else MANILA_EDGE, 4 if on else 2, 8))
		b.add_theme_stylebox_override("hover", UI.box(MANILA, MANILA_EDGE, 3, 8))
		b.add_theme_stylebox_override("pressed", UI.box(MANILA_EDGE, MANILA_EDGE, 3, 8))
		var row := UI.hbox(16)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 16; row.offset_right = -16; row.offset_top = 12; row.offset_bottom = -12
		row.add_child(_case_thumb(c, 108))
		var tv := UI.vbox(2)
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var no := UI.label("ARQUIVO Nº %02d%s" % [n, "   ·   ESCOLHIDO" if on else ""], 18, Color("#c42c3f") if on else Color(DOC_INK, 0.6), "type")
		no.autowrap_mode = TextServer.AUTOWRAP_OFF
		no.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(no)
		var t := UI.title(str(c["title"]).to_upper(), 38, DOC_INK)
		t.autowrap_mode = TextServer.AUTOWRAP_OFF
		t.clip_text = true
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(t)
		var tg := UI.label(UI.strip_emoji(str(c.get("tagline", ""))), 20, Color(DOC_INK, 0.85), "type")
		tg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tg.max_lines_visible = 2
		tv.add_child(tg)
		var meta := UI.label("%s  ·  ~%d min  ·  %d envolvidos  ·  %d lugares" % [_diff_name(d), int(c.get("duration_sec", 900)) / 60,
			int(c.get("people", 0)), int(c.get("places", 0))], 19, [Color("#2f6b3a"), Color("#8a6a1a"), Color("#c42c3f")][clampi(d, 1, 3) - 1], "bold")
		meta.autowrap_mode = TextServer.AUTOWRAP_OFF
		meta.clip_text = true
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(meta)
		row.add_child(tv)
		b.add_child(row)
		var cid := str(c["id"])
		b.pressed.connect(func() -> void:
			Sfx.play("ui_tap")
			Net.send({"t": "host_settings", "caseId": cid})
			UI.clear(viewer_layer))
		lst.add_child(b)
	UI.scroll_friendly(lst)


func _refresh_lobby() -> void:
	var st := Net.state
	var total := 0
	for t in st.get("teams", []):
		total += (t["players"] as Array).size()
	lobby_count.text = str(total)
	var cnt := find_child("TeamCount", true, false) as Label
	if cnt:
		cnt.text = str(int(st.get("settings", {}).get("teamCount", 3)))
	var start := find_child("Start", true, false) as Button
	if start:
		start.disabled = total == 0
		start.text = "COMEÇAR O CASO" if total > 0 else "ESPERANDO ALUNOS..."
	var sel := str(st.get("settings", {}).get("caseId", ""))
	var cur := {}
	for c in st.get("cases", []):
		if c["id"] == sel:
			cur = c
	var tlab := find_child("TimeLabel", true, false) as Label
	if tlab:
		tlab.text = "%d min" % (int(cur.get("duration_sec", 0)) / 60)
	# caso escolhido: pasta parda
	UI.clear(lobby_cases)
	var cp := PanelContainer.new()
	cp.add_theme_stylebox_override("panel", UI.box(MANILA, MANILA_EDGE, 2, 8, 14))
	var ch := UI.hbox(14)
	if not cur.is_empty():
		ch.add_child(_case_thumb(cur, 100))
	var cv := UI.vbox(2)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var k := UI.label("CASO DA AULA  ·  CONFIDENCIAL", 18, Color("#c42c3f"), "type")
	k.autowrap_mode = TextServer.AUTOWRAP_OFF
	k.clip_text = true
	cv.add_child(k)
	var tt := UI.title(str(cur.get("title", "Escolha um caso")).to_upper(), 40, DOC_INK)
	tt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(tt)
	if not cur.is_empty():
		var mt := UI.label("%s  ·  %d envolvidos  ·  %d lugares" % [_diff_name(int(cur.get("difficulty", 1))), int(cur.get("people", 0)), int(cur.get("places", 0))], 19, Color(DOC_INK, 0.75), "type")
		mt.autowrap_mode = TextServer.AUTOWRAP_OFF
		mt.clip_text = true
		cv.add_child(mt)
	ch.add_child(cv)
	var bv := UI.vbox(8)
	bv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var change := UI.button("TROCAR", "primary", 64)
	change.custom_minimum_size.x = 140
	change.pressed.connect(_open_case_picker)
	bv.add_child(change)
	var guide := UI.button("GUIA", "ghost", 64)
	guide.custom_minimum_size.x = 140
	guide.add_theme_color_override("font_color", DOC_INK)
	guide.add_theme_stylebox_override("normal", UI.box(Color("#f4efe2"), DOC_INK, 2, 12))
	guide.pressed.connect(_open_guide_overlay)
	bv.add_child(guide)
	ch.add_child(bv)
	cp.add_child(ch)
	lobby_cases.add_child(cp)
	# equipes (compactas)
	UI.clear(lobby_teams)
	for t in st.get("teams", []):
		var col := Color(str(t["color"]))
		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.add_theme_stylebox_override("panel", UI.box(Color(col, 0.1), col, 2, 14, 12))
		var v := UI.vbox(6)
		var th := UI.hbox(6)
		var tn := UI.title(str(t["name"]).to_upper(), 32, col)
		tn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tn.autowrap_mode = TextServer.AUTOWRAP_OFF
		tn.clip_text = true
		th.add_child(tn)
		th.add_child(UI.title(str((t["players"] as Array).size()), 32, Color(col, 0.7)))
		v.add_child(th)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		for pl in t["players"]:
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", UI.box(Color(UI.NIGHT, 0.8), Color(col, 0.5), 1, 20, 8))
			var clb := UI.label(UI.short_name(str(pl["name"])), 20, UI.PAPER if pl["online"] else UI.MIST, "bold")
			clb.autowrap_mode = TextServer.AUTOWRAP_OFF
			chip.add_child(clb)
			flow.add_child(chip)
		if (t["players"] as Array).is_empty():
			flow.add_child(UI.label("ninguém ainda", 20, UI.MIST, "type"))
		v.add_child(flow)
		p.add_child(v)
		lobby_teams.add_child(p)
	UI.scroll_friendly(lobby_cases)
	UI.scroll_friendly(lobby_teams)


# ================================================================== RODADA
## Três abas para o professor não ficar alheio: EQUIPES (progresso real e quem está parado),
## AO VIVO (tudo que os alunos fazem, em tempo real) e QUADROS (miniaturas dos quadros).
var game_tab := "equipes"
var tab_btns := {}
var feed_filter := ""
var page_box: VBoxContainer
var _feed_len := -1


func _build_game() -> void:
	UI.clear(body)
	var wide := _wide()
	var m := UI.margin(28 if wide else 18, 22, 18)
	body.add_child(UI.full(m))
	var outer := UI.vbox(10)
	m.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.name = "PageScroll"
	page_scroll = scroll
	outer.add_child(scroll)
	var v := UI.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var top := UI.hbox(16)
	timer_l = UI.title("0:00", 96 if wide else 68, UI.YELLOW)
	top.add_child(timer_l)
	var tv := UI.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UI.label("SALA %s  ·  PROF. AILSON" % Net.code, 22, UI.MIST, "bold"))
	var tt := UI.title(str(Net.case_data.get("title", "")).to_upper(), 44 if wide else 32, UI.PAPER)
	tt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(tt)
	top.add_child(tv)
	v.add_child(top)
	var tabs := UI.hbox(8)
	for k in [["equipes", "EQUIPES"], ["aovivo", "AO VIVO"], ["quadros", "QUADROS"], ["guia", "GUIA"]]:
		var b := UI.button(k[1], "ghost", 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", UI.font("title"))
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(func() -> void:
			game_tab = k[0]
			_scroll_top = true
			_feed_len = -1
			_guide_dirty = true
			if k[0] == "guia" and Net.guide_data.is_empty():
				Net.send({"t": "host_guide"})
			_refresh_game())
		tabs.add_child(b)
		tab_btns[k[0]] = b
	v.add_child(tabs)
	# enquanto o dedo rola, a tela não se refaz (senão a rolagem trava ou pula)
	scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _touch_scroll())
	scroll.gui_input.connect(func(_e: InputEvent) -> void: _touch_scroll())
	page_box = UI.vbox(12)
	page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(page_box)
	_touch = TouchScroll.attach(scroll)
	# controles numa fileira só (rótulos curtos): sobra mais tela para a lista
	var ctrl := UI.hbox(8)
	for spec in [["DICA", "ghost", "hint"], ["PISTA", "ghost", "rel"], ["ENCERRAR", "danger", "end"]]:
		var b := UI.button(spec[0], spec[1], 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", UI.font("title"))
		b.add_theme_font_size_override("font_size", 26)
		match spec[2]:
			"hint": b.pressed.connect(func() -> void: _open_hint(""))
			"rel": b.pressed.connect(func() -> void: Net.send({"t": "host_release"}))
			"more": b.pressed.connect(func() -> void: Net.send({"t": "host_add_time"}))
			"end": b.pressed.connect(func() -> void: Net.send({"t": "host_end"}))
		ctrl.add_child(b)
	outer.add_child(ctrl)


var page_scroll: ScrollContainer
var _touch: TouchScroll
var _guide_dirty := true
var _busy_until := 0
var _pending := false


func _touch_scroll() -> void:
	_busy_until = maxi(_busy_until, Time.get_ticks_msec() + 1400)


## Qualquer toque, arrasto ou roda do mouse na tela segura a reconstrução por um tempo: a lista
## não se refaz embaixo do dedo do professor (era isso que travava e fazia a rolagem pular).
func _input(e: InputEvent) -> void:
	if phase_built != "game":
		return
	if e is InputEventScreenTouch or e is InputEventScreenDrag or e is InputEventMouseButton 			or (e is InputEventMouseMotion and (e as InputEventMouseMotion).button_mask != 0):
		_busy_until = maxi(_busy_until, Time.get_ticks_msec() + 2500)


var _last_sig := ""
var _last_build_ms := -100000
var _scroll_top := false


## Assinatura do que a aba mostra: se nada mudou, a tela não é refeita.
func _page_sig() -> String:
	var st := Net.state
	if str(st.get("phase", "")) == "briefing":
		return "b" + JSON.stringify([st.get("readyList", []), st.get("countdown", false)])
	var bucket := int(Net.seconds_elapsed() / 30)
	match game_tab:
		"equipes":
			# o tempo parado de cada aluno muda a cada mensagem; na ficha só importa a faixa (ativo,
			# pensando, parado N min), então a assinatura usa a faixa
			var ins: Dictionary = (st.get("insight", {}) as Dictionary).duplicate(true)
			for tid in ins:
				for mbr in (ins[tid] as Dictionary).get("members", []):
					var idle := int(mbr.get("idleSec", 0))
					mbr["idleSec"] = 0 if idle < 60 else (1 if idle < 180 else 2 + idle / 60)
					mbr.erase("actions")
			return "e%d|%s" % [bucket, JSON.stringify([st.get("teams", []), ins])]
		"aovivo":
			return "a%d|%d|%s" % [bucket, (st.get("feed", []) as Array).size(), feed_filter]
		"quadros":
			# arrastar carta manda o quadro de novo várias vezes por segundo: a miniatura só
			# refaz quando muda o que tem nele (cartas, fios, provas), não a posição
			var parts := []
			var bds: Dictionary = st.get("boards", {})
			for tid in bds:
				var b: Dictionary = bds[tid]
				var refs := []
				for c in b.get("cards", []):
					refs.append(str(c.get("ref", "")) + str(c.get("tag", "")))
				parts.append([tid, refs, b.get("links", [])])
			return "q" + JSON.stringify([parts, st.get("teams", [])])
		"guia":
			return "g%d" % Net.guide_data.size()
	return game_tab


func _refresh_game() -> void:
	# mudança pedida pelo professor (aba, filtro) passa na hora; atualização dos alunos espera
	# quadro de equipe aberto em tela cheia: atualiza sempre (é barato e mostra o arrasto ao vivo)
	if viewer_team != "" and viewer_board and is_instance_valid(viewer_board):
		var vb: Dictionary = Net.state.get("boards", {}).get(viewer_team, {})
		viewer_board.set_data(vb.get("cards", []), vb.get("links", []))
	var forced := _feed_len == -1 or (_guide_dirty and game_tab == "guia")
	if not forced:
		if _touch and _touch.busy():
			_busy_until = maxi(_busy_until, Time.get_ticks_msec() + 900)
		if page_scroll and Time.get_ticks_msec() < _busy_until:
			_pending = true
			return
	# no máximo uma reconstrução a cada 1,5 s vinda dos alunos (turma inteira mexendo ao mesmo
	# tempo não pode travar o celular do professor)
	if not forced and Time.get_ticks_msec() - _last_build_ms < 1500:
		_pending = true
		return
	_pending = false
	var sig := _page_sig()
	if not forced and sig == _last_sig and page_box and page_box.get_child_count() > 0:
		_do_tabs_only()
		return
	_last_sig = sig
	_last_build_ms = Time.get_ticks_msec()
	if _feed_len == -1:
		_feed_len = 0
	var keep := 0 if _scroll_top else (page_scroll.scroll_vertical if page_scroll else 0)
	_scroll_top = false
	# segura a altura da página durante a troca: a lista nunca fica vazia por um instante
	# (a rolagem não é puxada para o topo)
	if page_box:
		page_box.custom_minimum_size.y = page_box.size.y
	_do_refresh_game()
	_restore_scroll(keep)


func _restore_scroll(keep: int) -> void:
	if page_scroll:
		page_scroll.scroll_vertical = keep
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(page_box) or not is_instance_valid(page_scroll):
		return
	page_box.custom_minimum_size.y = 0
	if not (_touch and _touch.busy()):
		page_scroll.scroll_vertical = keep


func _do_tabs_only() -> void:
	for k in tab_btns:
		var on: bool = k == game_tab
		(tab_btns[k] as Button).add_theme_stylebox_override("normal", UI.box(UI.YELLOW if on else Color(UI.NIGHT, 0.8), UI.YELLOW.darkened(0.4), 0 if on else 2, 16))
		(tab_btns[k] as Button).add_theme_color_override("font_color", UI.INK if on else UI.PAPER)


func _do_refresh_game() -> void:
	var st := Net.state
	for k in tab_btns:
		var on: bool = k == game_tab
		(tab_btns[k] as Button).add_theme_stylebox_override("normal", UI.box(UI.YELLOW if on else Color(UI.NIGHT, 0.8), UI.YELLOW.darkened(0.4), 0 if on else 2, 16))
		(tab_btns[k] as Button).add_theme_color_override("font_color", UI.INK if on else UI.PAPER)
	if str(st.get("phase", "")) == "briefing":
		timer_l.text = ("%ds" % Net.seconds_left()) if st.get("countdown", false) else "PRONTOS?"
		UI.clear(page_box)
		page_box.add_child(_ready_panel())
		return
	if game_tab == "guia" and page_box.get_child_count() > 0 and not _guide_dirty:
		return
	_guide_dirty = false
	UI.clear(page_box)
	match game_tab:
		"equipes":
			# fichas lado a lado no PC; uma por linha no celular em pé
			var tg := GridContainer.new()
			var nt := (st.get("teams", []) as Array).size()
			tg.columns = 1 if not _wide() else clampi(nt, 1, 3 if size.x >= 1500 else 2)
			tg.add_theme_constant_override("h_separation", 14)
			tg.add_theme_constant_override("v_separation", 14)
			tg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for t in st.get("teams", []):
				tg.add_child(_team_card(t))
			page_box.add_child(tg)
		"aovivo":
			_build_feed()
		"guia":
			page_box.add_child(_reading_column(GuideView.build(Net.guide_data)))
		"quadros":
			var grid := GridContainer.new()
			grid.columns = 3 if _wide() else 1
			grid.add_theme_constant_override("h_separation", 12)
			grid.add_theme_constant_override("v_separation", 12)
			grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for t in st.get("teams", []):
				grid.add_child(_board_thumb(t))
			page_box.add_child(grid)
	UI.scroll_friendly(page_box)
	if viewer_team != "" and viewer_board:
		var b: Dictionary = st.get("boards", {}).get(viewer_team, {})
		viewer_board.set_data(b.get("cards", []), b.get("links", []))


func _bar(label: String, val: int, total: int, col: Color) -> Control:
	var v := UI.vbox(4)
	var h := UI.hbox(8)
	var l := UI.label(label, 21, UI.MIST, "bold")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(l)
	var n := UI.label("%d/%d" % [val, total], 21, col, "bold")
	n.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(n)
	v.add_child(h)
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.max_value = maxi(1, total)
	pb.value = val
	pb.custom_minimum_size.y = 14
	pb.add_theme_stylebox_override("background", UI.box(Color(0, 0, 0, 0.4), Color.TRANSPARENT, 0, 7, 0))
	pb.add_theme_stylebox_override("fill", UI.box(col, Color.TRANSPARENT, 0, 7, 0))
	v.add_child(pb)
	return v


## Abertura: quem já deu PRONTO e quem falta; o professor pode começar mesmo assim.
func _ready_panel() -> Control:
	var st := Net.state
	var lst: Array = st.get("readyList", []) if st.get("readyList") is Array else []
	var v := UI.vbox(12)
	var on := lst.filter(func(r: Dictionary) -> bool: return r["online"])
	var ok := on.filter(func(r: Dictionary) -> bool: return r["ready"])
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UI.box(Color("#d9b977"), Color("#b8944f"), 2, 8, 14))
	var hv := UI.vbox(2)
	var k := UI.label("ABERTURA DO CASO  ·  CHAMADA", 18, Color("#c42c3f"), "type")
	k.autowrap_mode = TextServer.AUTOWRAP_OFF
	hv.add_child(k)
	var big := UI.title("%d DE %d PRONTOS" % [ok.size(), on.size()] if not st.get("countdown", false) else "TODOS PRONTOS!", 54, Color("#1b2140"))
	big.autowrap_mode = TextServer.AUTOWRAP_OFF
	hv.add_child(big)
	hv.add_child(UI.label("O relógio só começa quando todos tocarem em PRONTO. Quem caiu não segura a turma.", 20, Color("#1b2140", 0.75)))
	head.add_child(hv)
	v.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 1 if not _wide() else 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for t in st.get("teams", []):
		var col := Color(str(t["color"]))
		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.add_theme_stylebox_override("panel", UI.box(Color(col, 0.08), col, 2, 12, 12))
		var tv := UI.vbox(6)
		tv.add_child(UI.title("EQUIPE " + str(t["name"]).to_upper(), 30, col))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		for r in lst:
			if r["team"] != t["id"]:
				continue
			var rc: Color = UI.GREEN if r["ready"] else (UI.MIST.darkened(0.3) if not r["online"] else UI.YELLOW)
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", UI.box(Color(rc, 0.15), rc, 2, 20, 8))
			var txt := ("OK  " if r["ready"] else "") + UI.short_name(str(r["name"])) + ("" if r["online"] else "  fora") + ("" if r["ready"] or not r["online"] else "  lendo...")
			var l := UI.label(txt, 20, rc, "bold")
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			chip.add_child(l)
			flow.add_child(chip)
		tv.add_child(flow)
		p.add_child(tv)
		grid.add_child(p)
	v.add_child(grid)
	if not st.get("countdown", false):
		var force := UI.button("COMEÇAR MESMO ASSIM", "ghost", 80)
		force.pressed.connect(func() -> void: Net.send({"t": "host_force_start"}))
		v.add_child(force)
	return v


func _team_card(t: Dictionary) -> Control:
	var col := Color(str(t["color"]))
	var ins: Dictionary = Net.state.get("insight", {}).get(t["id"], {})
	var wrap := UI.vbox(0)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# aba da ficha: nome da equipe + carimbo de situação
	var tabrow := UI.hbox(0)
	var tab := PanelContainer.new()
	var tsb := UI.box(Color("#d9b977"), Color("#b8944f"), 2, 10, 10)
	tsb.corner_radius_bottom_left = 0
	tsb.corner_radius_bottom_right = 0
	tsb.border_width_bottom = 0
	tab.add_theme_stylebox_override("panel", tsb)
	var th := UI.hbox(8)
	var sw := ColorRect.new()
	sw.color = col
	sw.custom_minimum_size = Vector2(14, 14)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(sw)
	var name := UI.title("EQUIPE " + str(t["name"]).to_upper(), 30, Color("#1b2140"))
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	th.add_child(name)
	tab.add_child(th)
	tabrow.add_child(tab)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabrow.add_child(sp)
	var st_txt := "INVESTIGANDO"
	var st_col := UI.MIST
	if ins.get("finished", false):
		st_txt = "ENTREGUE" + (" · CULPADO CERTO" if ins.get("culpritOk", false) else " · CULPADO ERRADO")
		st_col = UI.GREEN if ins.get("culpritOk", false) else UI.PINK
	elif ins.get("voting", false):
		st_txt = "VOTANDO A ENTREGA"
		st_col = UI.YELLOW
	var stamp := PanelContainer.new()
	stamp.add_theme_stylebox_override("panel", UI.box(Color(st_col, 0.14), st_col, 2, 6, 8))
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sl := UI.title(st_txt, 22, st_col)
	sl.autowrap_mode = TextServer.AUTOWRAP_OFF
	stamp.add_child(sl)
	stamp.rotation = -0.03
	tabrow.add_child(stamp)
	wrap.add_child(tabrow)

	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var psb := UI.box(Color(UI.NAVY, 0.95), Color("#b8944f"), 2, 12, 14)
	psb.corner_radius_top_left = 0
	psb.border_color = Color(col, 0.8)
	p.add_theme_stylebox_override("panel", psb)
	var v := UI.vbox(10)
	# três números que importam
	var stats := UI.hbox(8)
	stats.add_child(_stat("PISTAS", "%d/%d" % [int(ins.get("cluesFound", 0)), int(ins.get("cluesTotal", 0))], UI.SKY))
	stats.add_child(_stat("PROVAS", "%d/%d" % [int(ins.get("edgesOk", 0)), int(ins.get("edgesTotal", 0))], UI.GREEN))
	stats.add_child(_stat("OBJETOS", str(int(ins.get("items", 0))), UI.YELLOW))
	v.add_child(stats)
	# objetivos: cada parte da história (verde = provada no quadro agora)
	var of := HFlowContainer.new()
	of.add_theme_constant_override("h_separation", 6)
	of.add_theme_constant_override("v_separation", 6)
	for cat in ins.get("cats", []):
		var ok: bool = cat["status"] == "ok"
		var c2 := UI.GREEN if ok else (UI.RED if cat["status"] == "errado" else Color(UI.MIST, 0.7))
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UI.box(Color(c2, 0.14), c2, 1, 8, 6))
		var chl := UI.label(("OK  " if ok else "") + str(cat["label"]), 17, c2, "bold")
		chl.autowrap_mode = TextServer.AUTOWRAP_OFF
		chip.add_child(chl)
		of.add_child(chip)
	if of.get_child_count() > 0:
		v.add_child(of)
	# alunos: ativo (verde), pensando (amarelo), parado ou fora
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for mbr in ins.get("members", []):
		var idle := int(mbr.get("idleSec", 0))
		var dot := UI.GREEN if idle < 60 else (UI.YELLOW if idle < 180 else UI.RED)
		if not mbr.get("online", true):
			dot = UI.MIST.darkened(0.4)
		var mc := PanelContainer.new()
		mc.add_theme_stylebox_override("panel", UI.box(Color(UI.NIGHT, 0.85), dot, 2, 20, 8))
		var txt := UI.short_name(str(mbr["name"]))
		if not mbr.get("online", true):
			txt += "  fora"
		elif idle >= 180:
			txt += "  parado %dmin" % (idle / 60)
		var cl := UI.label(txt, 18, UI.PAPER, "bold")
		cl.autowrap_mode = TextServer.AUTOWRAP_OFF
		mc.add_child(cl)
		flow.add_child(mc)
	v.add_child(flow)
	var row := UI.hbox(8)
	for spec in [["Quadro", func() -> void: _open_viewer(t)], ["Dica", func() -> void: _open_hint(str(t["id"]))],
			["Ações", func() -> void:
				feed_filter = str(t["id"])
				game_tab = "aovivo"
				_feed_len = -1
				_refresh_game()]]:
		var b := UI.button(spec[0], "ghost", 60)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(spec[1])
		row.add_child(b)
	v.add_child(row)
	p.add_child(v)
	wrap.add_child(p)
	return wrap


func _stat(label: String, value: String, col: Color) -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", UI.box(Color(col, 0.1), Color(col, 0.5), 1, 10, 8))
	var v := UI.vbox(0)
	var vl := UI.title(value, 36, col)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vl.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.add_child(vl)
	var ll := UI.label(label, 15, UI.MIST, "type")
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ll.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.add_child(ll)
	pc.add_child(v)
	return pc


const FEED_COLORS := {"cena": Color("#ffc83d"), "conversa": Color("#6fd3ff"), "quadro": Color("#b9a3ff"), "teoria": Color("#ff9a4d"),
	"acerto": Color("#8ef0b5"), "alerta": Color("#ff6fae"), "dica": Color("#ffffff"), "sistema": Color("#a9bdf0"), "sala": Color("#a9bdf0")}


## Ícone desenhado de cada tipo de ação (lupa, balão, alfinete, urna, carimbo, alerta, lâmpada...).
class FeedIcon extends Control:
	var kind := ""
	var col := Color.WHITE
	var ring := true

	func _init(k: String, c: Color, sz := 44.0, with_ring := true) -> void:
		kind = k
		col = c
		ring = with_ring
		custom_minimum_size = Vector2(sz, sz)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2
		var r := minf(size.x, size.y) / 2 - 1
		if ring:
			draw_circle(c, r, Color(col, 0.18))
			draw_arc(c, r, 0, TAU, 32, col, 2.0)
		var s := r * 0.55
		var w := maxf(2.0, r * 0.12)
		match kind:
			"cena":  # lupa
				draw_arc(c + Vector2(-s * 0.2, -s * 0.2), s * 0.6, 0, TAU, 20, col, w)
				draw_line(c + Vector2(s * 0.25, s * 0.25), c + Vector2(s * 0.85, s * 0.85), col, w * 1.4)
			"conversa":  # balão
				draw_rect(Rect2(c + Vector2(-s, -s * 0.7), Vector2(s * 2, s * 1.2)), col, false, w)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.4, s * 0.5), c + Vector2(-s * 0.7, s * 1.0), c + Vector2(0, s * 0.5)]), col)
				for i in 3:
					draw_circle(c + Vector2(-s * 0.5 + i * s * 0.5, -s * 0.1), w * 0.7, col)
			"quadro":  # alfinete com fio
				draw_line(c + Vector2(-s, s * 0.7), c + Vector2(s, -s * 0.2), Color(UI.RED, 0.9), w)
				draw_circle(c + Vector2(-s, s * 0.7), w * 1.3, col)
				draw_circle(c + Vector2(s, -s * 0.2), w * 1.6, col)
				draw_line(c + Vector2(s, -s * 0.2), c + Vector2(s * 0.6, -s * 0.9), col, w)
			"teoria":  # urna com cédula
				draw_rect(Rect2(c + Vector2(-s, -s * 0.2), Vector2(s * 2, s * 1.1)), col, false, w)
				draw_line(c + Vector2(-s * 0.5, -s * 0.2), c + Vector2(s * 0.5, -s * 0.2), Color(0, 0, 0, 0.6), w)
				draw_rect(Rect2(c + Vector2(-s * 0.35, -s), Vector2(s * 0.7, s * 0.9)), col)
			"acerto":  # visto de carimbo
				draw_polyline(PackedVector2Array([c + Vector2(-s * 0.8, 0), c + Vector2(-s * 0.2, s * 0.6), c + Vector2(s * 0.9, -s * 0.6)]), col, w * 1.6)
			"alerta":  # exclamação
				draw_line(c + Vector2(0, -s * 0.9), c + Vector2(0, s * 0.25), col, w * 1.6)
				draw_circle(c + Vector2(0, s * 0.75), w, col)
			"dica":  # lâmpada
				draw_arc(c + Vector2(0, -s * 0.2), s * 0.6, PI * 0.8, PI * 2.2, 20, col, w)
				draw_line(c + Vector2(-s * 0.3, s * 0.45), c + Vector2(s * 0.3, s * 0.45), col, w)
				draw_line(c + Vector2(-s * 0.2, s * 0.8), c + Vector2(s * 0.2, s * 0.8), col, w)
			"sala":  # porta
				draw_rect(Rect2(c + Vector2(-s * 0.55, -s * 0.9), Vector2(s * 1.1, s * 1.8)), col, false, w)
				draw_circle(c + Vector2(s * 0.25, 0), w * 0.8, col)
			_:  # sistema: relógio
				draw_arc(c, s * 0.85, 0, TAU, 24, col, w)
				draw_line(c, c + Vector2(0, -s * 0.55), col, w)
				draw_line(c, c + Vector2(s * 0.4, 0), col, w)


const FEED_TITLES := {"cena": "PISTA NA CENA", "conversa": "INTERROGATÓRIO", "quadro": "QUADRO", "teoria": "ENTREGA", "acerto": "ACERTO",
	"alerta": "ALERTA", "dica": "DICA", "sistema": "AVISO", "sala": "SALA"}


func _ago(at: float) -> String:
	var ago := int((Net.server_now_ms() - at) / 1000.0)
	return ("agora" if ago < 10 else "há %ds" % ago) if ago < 60 else "há %dmin" % (ago / 60)


func _build_feed() -> void:
	var st := Net.state
	var team_by := {}
	for t in st.get("teams", []):
		team_by[t["id"]] = t
	var feed: Array = st.get("feed", [])
	# no PC: radar numa coluna à esquerda, ocorrências à direita
	var left: VBoxContainer = page_box
	var right: VBoxContainer = page_box
	if _wide():
		var cols := UI.hbox(16)
		cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left = UI.vbox(10)
		left.custom_minimum_size.x = 470
		right = UI.vbox(10)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(left)
		cols.add_child(right)
		page_box.add_child(cols)

	# ---- radar: uma faixa por equipe com as últimas ações em ícones (quem está ativo, fazendo o quê)
	var radar := PanelContainer.new()
	radar.add_theme_stylebox_override("panel", UI.box(Color(UI.NIGHT, 0.85), Color(UI.YELLOW, 0.35), 2, 14, 12))
	var rv := UI.vbox(8)
	var rt := UI.label("RADAR DAS EQUIPES  ·  últimas ações", 18, UI.YELLOW, "type")
	rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	rv.add_child(rt)
	for t in st.get("teams", []):
		var tcol := Color(str(t["color"]))
		var on := feed_filter == str(t["id"])
		var lane := Button.new()
		lane.focus_mode = Control.FOCUS_NONE
		lane.custom_minimum_size = Vector2(0, 58)
		lane.add_theme_stylebox_override("normal", UI.box(Color(tcol, 0.16 if on else 0.06), tcol if on else Color(tcol, 0.35), 2, 10))
		lane.add_theme_stylebox_override("hover", UI.box(Color(tcol, 0.2), tcol, 2, 10))
		lane.add_theme_stylebox_override("pressed", UI.box(Color(tcol, 0.3), tcol, 2, 10))
		var lh := UI.hbox(8)
		lh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lh.offset_left = 10; lh.offset_right = -10
		var nm := UI.title(str(t["name"]).to_upper(), 28, tcol)
		nm.custom_minimum_size.x = 120
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		nm.clip_text = true
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lh.add_child(nm)
		var icons := UI.hbox(4)
		icons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var recent := []
		for i in range(feed.size() - 1, -1, -1):
			if feed[i].get("team") == t["id"]:
				recent.append(feed[i])
				if recent.size() >= 9:
					break
		var last_at := 0.0
		for k in recent.size():
			var e: Dictionary = recent[k]
			if k == 0:
				last_at = float(e.get("at", 0))
			var kd := str(e.get("kind", ""))
			var ic := FeedIcon.new(kd, FEED_COLORS.get(kd, UI.MIST), 34.0)
			ic.modulate.a = 1.0 - k * 0.08
			icons.add_child(ic)
		if recent.is_empty():
			var none := UI.label("sem ações ainda", 18, UI.MIST, "type")
			none.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icons.add_child(none)
		lh.add_child(icons)
		var ag := UI.label(_ago(last_at) if last_at > 0 else "", 17, UI.MIST, "bold")
		ag.autowrap_mode = TextServer.AUTOWRAP_OFF
		ag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lh.add_child(ag)
		lane.add_child(lh)
		var tid := str(t["id"])
		lane.pressed.connect(func() -> void:
			feed_filter = "" if feed_filter == tid else tid
			_feed_len = -1
			_refresh_game())
		rv.add_child(lane)
	var hint := UI.label("Toque numa equipe para ver só as ocorrências dela" if feed_filter == "" else "Mostrando só %s · toque de novo para ver todas" % str(team_by.get(feed_filter, {}).get("name", "")).to_upper(), 16, UI.MIST)
	rv.add_child(hint)
	radar.add_child(rv)
	left.add_child(radar)

	# ---- linha do tempo: fio vermelho com alfinetes, um cartão por ocorrência (repetidas agrupadas)
	var title := UI.label("OCORRÊNCIAS", 20, UI.YELLOW, "type")
	right.add_child(title)
	var groups := []
	for i in range(feed.size() - 1, -1, -1):
		var e: Dictionary = feed[i]
		if feed_filter != "" and e.get("team") != feed_filter and e.get("team") != null:
			continue
		var last: Dictionary = groups[-1] if not groups.is_empty() else {}
		if not last.is_empty() and last["kind"] == e.get("kind") and last["team"] == e.get("team") and str(e.get("kind")) in ["quadro", "cena"] \
				and float(last["first_at"]) - float(e.get("at", 0)) < 120000.0:
			last["count"] += 1
			last["first_at"] = float(e.get("at", 0))
			continue
		groups.append({"kind": e.get("kind"), "team": e.get("team"), "who": e.get("who"), "text": str(e.get("text", "")),
			"at": float(e.get("at", 0)), "first_at": float(e.get("at", 0)), "count": 1})
		if groups.size() >= 60:
			break
	if groups.is_empty():
		right.add_child(UI.label("Nada ainda. As ações dos alunos aparecem aqui em tempo real.", 24, UI.MIST, "type"))
		return
	for g in groups:
		right.add_child(_feed_card(g, team_by.get(g["team"], {})))


func _feed_card(g: Dictionary, t: Dictionary) -> Control:
	var kd := str(g["kind"])
	var kcol: Color = FEED_COLORS.get(kd, UI.MIST)
	var tcol := Color(str(t.get("color", "#a9bdf0")))
	var big := kd in ["acerto", "alerta"] or (kd == "teoria" and str(g["text"]).find("entregou") >= 0)
	var row := UI.hbox(10)
	# coluna do fio: linha vermelha contínua com o alfinete no ícone
	var rail := Control.new()
	rail.custom_minimum_size = Vector2(52, 0)
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.draw.connect(func() -> void:
		rail.draw_line(Vector2(26, 0), Vector2(26, rail.size.y + 10), Color(UI.RED, 0.55), 3.0))
	var ic := FeedIcon.new(kd, kcol, 46.0)
	ic.position = Vector2(3, 10)
	rail.add_child(ic)
	row.add_child(rail)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := UI.box(Color(kcol, 0.12) if big else Color(UI.NIGHT, 0.82), kcol if big else Color(tcol, 0.35), 3 if big else 1, 10, 10)
	sb.border_width_left = 6
	sb.border_color = kcol if big else tcol
	card.add_theme_stylebox_override("panel", sb)
	var v := UI.vbox(2)
	var head := UI.hbox(8)
	var kl := UI.label(FEED_TITLES.get(kd, "AVISO"), 16, kcol, "type")
	kl.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(kl)
	if not t.is_empty():
		var tg := PanelContainer.new()
		tg.add_theme_stylebox_override("panel", UI.box(Color(tcol, 0.2), tcol, 1, 6, 4))
		var tl := UI.label(str(t["name"]).to_upper(), 14, tcol, "bold")
		tl.autowrap_mode = TextServer.AUTOWRAP_OFF
		tg.add_child(tl)
		head.add_child(tg)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var al := UI.label(_ago(float(g["at"])), 15, UI.MIST, "bold")
	al.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(al)
	v.add_child(head)
	# título curto (antes dos dois pontos) e detalhe em letra menor
	var txt := UI.strip_emoji(str(g["text"]))
	var cut := txt.find(": ")
	var main := txt.substr(0, cut) if cut > 0 else txt
	var detail := txt.substr(cut + 2) if cut > 0 else ""
	if int(g["count"]) > 1:
		main = "%s mexeu no quadro %dx" % [str(g.get("who", "A equipe")), int(g["count"])] if kd == "quadro" else "%s achou %d pistas" % [str(g.get("who", "A equipe")), int(g["count"])]
		detail = "última: " + (detail if detail != "" else txt)
	var ml := UI.label(main, 26 if big else 22, UI.PAPER, "bold")
	v.add_child(ml)
	if detail != "":
		var dl := UI.label(detail, 18, UI.MIST)
		dl.max_lines_visible = 2
		v.add_child(dl)
	card.add_child(v)
	row.add_child(card)
	return row


func _board_thumb(t: Dictionary) -> Control:
	var col := Color(str(t["color"]))
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", UI.box(Color(col, 0.08), col, 3, 18, 12))
	var v := UI.vbox(8)
	var h := UI.hbox(8)
	var n := UI.title(str(t["name"]).to_upper(), 36, col)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	var open := UI.button("Abrir", "ghost", 60)
	open.custom_minimum_size.x = 140
	open.pressed.connect(func() -> void: _open_viewer(t))
	h.add_child(open)
	v.add_child(h)
	var bv := BoardView.new()
	bv.readonly = true
	bv.custom_minimum_size = Vector2(0, 360)
	var b: Dictionary = Net.state.get("boards", {}).get(t["id"], {})
	bv.set_data(b.get("cards", []), b.get("links", []))
	v.add_child(bv)
	bv.call_deferred("fit")
	p.add_child(v)
	return p


## Mensagem do professor: primeiro ele DIGITA (o campo já vem focado); se quiser, abre as sugestões
## escritas para este caso, da mais sutil para a mais forte.
func _open_hint(team_id: String, show_suggestions := false) -> void:
	UI.clear(viewer_layer)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			UI.clear(viewer_layer))
	viewer_layer.add_child(UI.full(bg))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(Color(UI.NAVY, 0.99), UI.YELLOW, 3, 26, 22))
	# fica no TOPO: no celular o teclado virtual cobre a metade de baixo da tela
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var side := maxf(12.0, (size.x - 860.0) / 2.0)
	panel.offset_left = side; panel.offset_right = -side; panel.offset_top = 16
	var v := UI.vbox(12)
	var tname := "TODAS AS EQUIPES"
	for t in Net.state.get("teams", []):
		if t["id"] == team_id:
			tname = "EQUIPE " + str(t["name"]).to_upper()
	var hh := UI.hbox(10)
	var title := UI.title("MENSAGEM PARA " + tname, 36, UI.YELLOW)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hh.add_child(title)
	var close := UI.button("FECHAR", "ghost", 64)
	close.custom_minimum_size.x = 150
	close.pressed.connect(func() -> void: UI.clear(viewer_layer))
	hh.add_child(close)
	v.add_child(hh)
	var le := LineEdit.new()
	le.placeholder_text = "Escreva sua mensagem ou dica..."
	le.custom_minimum_size.y = 84
	le.max_length = 160
	le.virtual_keyboard_enabled = true
	le.add_theme_font_override("font", UI.font("bold"))
	le.add_theme_font_size_override("font_size", 28)
	le.add_theme_color_override("font_color", UI.PAPER)
	le.add_theme_color_override("font_placeholder_color", Color(UI.MIST, 0.6))
	le.add_theme_color_override("caret_color", UI.YELLOW)
	le.add_theme_stylebox_override("normal", UI.box(Color(UI.NIGHT, 0.95), UI.SKY, 2, 14, 18))
	le.add_theme_stylebox_override("focus", UI.box(Color(UI.NIGHT, 0.95), UI.YELLOW, 3, 14, 18))
	v.add_child(le)
	var send_fn := func() -> void:
		var txt := le.text.strip_edges()
		if txt == "":
			return
		Net.send({"t": "host_hint", "team": team_id, "text": txt})
		Sfx.play("phone_buzz")
		get_meta("main").toast("Mensagem enviada para " + tname.to_lower(), UI.GREEN)
		UI.clear(viewer_layer)
	le.text_submitted.connect(func(_t: String) -> void: send_fn.call())
	var row := UI.hbox(10)
	var sug := UI.button("Sugestões de dica", "ghost", 84)
	sug.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sug.pressed.connect(func() -> void: _open_hint(team_id, not show_suggestions))
	row.add_child(sug)
	var send := UI.button("ENVIAR", "primary", 84)
	send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send.pressed.connect(send_fn)
	row.add_child(send)
	v.add_child(row)
	if show_suggestions:
		v.add_child(UI.label("Toque numa sugestão para colocar no campo. Da mais sutil para a mais forte.", 21, UI.MIST))
		var hints: Array = Net.case_data.get("hints", [])
		if hints.is_empty():
			hints = ["Já olharam todos os lugares da escola? Troquem de cena no topo.", "Mostrem uma pista para quem vocês interrogaram.",
				"Prendam uma prova em cada fio importante.", "Conversem: cada um tem pistas que só ele vê."]
		var sc := ScrollContainer.new()
		sc.custom_minimum_size.y = minf(520.0, size.y * 0.45)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var lv := UI.vbox(8)
		lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var n := 0
		for h in hints:
			n += 1
			var b := UI.button("%d.  %s" % [n, UI.strip_emoji(str(h))], "ghost", 76)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 22)
			b.pressed.connect(func() -> void:
				le.text = UI.strip_emoji(str(h))
				le.caret_column = le.text.length()
				le.grab_focus())
			lv.add_child(b)
		sc.add_child(lv)
		UI.scroll_friendly(lv)
		v.add_child(sc)
	panel.add_child(v)
	viewer_layer.add_child(panel)
	le.grab_focus.call_deferred()


func _open_guide_overlay() -> void:
	UI.clear(viewer_layer)
	var bg := ColorRect.new()
	bg.color = Color(UI.NIGHT, 0.97)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	viewer_layer.add_child(UI.full(bg))
	var m := UI.margin(20, 24, 20)
	viewer_layer.add_child(UI.full(m))
	var v := UI.vbox(10)
	m.add_child(v)
	var close := UI.button("FECHAR O GUIA", "ghost", 70)
	close.pressed.connect(func() -> void: UI.clear(viewer_layer))
	v.add_child(close)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	TouchScroll.attach(sc)
	var fill := func() -> void:
		if not is_instance_valid(sc):
			return
		UI.clear(sc)
		var g := GuideView.build(Net.guide_data)
		sc.add_child(_reading_column(g))
		UI.scroll_friendly(g)
	fill.call()
	Net.guide_loaded.connect(fill, CONNECT_ONE_SHOT)
	Net.send({"t": "host_guide"})


func _open_viewer(t: Dictionary) -> void:
	UI.clear(viewer_layer)
	viewer_team = str(t["id"])
	var bg := ColorRect.new()
	bg.color = Color(UI.NIGHT, 0.97)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	viewer_layer.add_child(UI.full(bg))
	var m := UI.margin(24)
	viewer_layer.add_child(UI.full(m))
	var v := UI.vbox(12)
	m.add_child(v)
	var h := UI.hbox()
	var ttl := UI.title("QUADRO DA EQUIPE " + str(t["name"]).to_upper(), 56, Color(str(t["color"])))
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ttl)
	var close := UI.button("Fechar", "ghost", 76)
	close.custom_minimum_size.x = 200
	close.pressed.connect(func() -> void:
		viewer_team = ""
		viewer_board = null
		UI.clear(viewer_layer))
	h.add_child(close)
	v.add_child(h)
	viewer_board = BoardView.new()
	viewer_board.readonly = true
	viewer_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(viewer_board)
	var b: Dictionary = Net.state.get("boards", {}).get(viewer_team, {})
	viewer_board.set_data(b.get("cards", []), b.get("links", []))
	viewer_board.call_deferred("fit")


func _process(_dt: float) -> void:
	if _pending and Time.get_ticks_msec() >= _busy_until and phase_built == "game":
		_refresh_game()
	if phase_built == "game" and timer_l and str(Net.state.get("phase", "")) == "playing":
		var s := Net.seconds_elapsed()
		timer_l.text = UI.fmt_time(s)
		if s != _last_sec:
			_last_sec = s
			if s % 5 == 0 and game_tab != "quadros":
				_refresh_game()
	elif phase_built == "game" and timer_l:
		timer_l.text = ("%ds" % Net.seconds_left()) if Net.state.get("countdown", false) else "PRONTOS?"
