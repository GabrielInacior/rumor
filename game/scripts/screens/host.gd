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
	c.add_child(UI.title("CRIANDO A SALA...", 70))


# ================================================================== LOBBY
func _host_url() -> String:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("location.host", true))
	return "o endereço do servidor"


func _build_lobby() -> void:
	UI.clear(body)
	var wide := _wide()
	var m := UI.margin(36 if wide else 24, 40 if wide else 30, 24)
	body.add_child(UI.full(m))
	var page := UI.vbox(14)
	m.add_child(page)
	# no celular em pé tudo vira uma página só que rola; o botão de começar fica fixo embaixo
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var outer: BoxContainer = UI.hbox(30) if wide else UI.vbox(18)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(outer)

	var left := UI.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(left)
	left.add_child(UI.label("PROF. AILSON  ·  sala de investigação", 24, UI.PINK, "bold"))
	left.add_child(UI.label("Entrem em  " + _host_url() + "  e digitem:", 26, UI.MIST, "bold"))
	left.add_child(UI.title("SALA " + Net.code, 150 if wide else 120, UI.YELLOW))
	lobby_count = UI.label("", 28, UI.PAPER, "bold")
	left.add_child(lobby_count)
	lobby_teams = GridContainer.new()
	(lobby_teams as GridContainer).columns = 3 if wide else 1
	lobby_teams.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_teams.add_theme_constant_override("h_separation", 14)
	lobby_teams.add_theme_constant_override("v_separation", 12)
	left.add_child(lobby_teams)

	var right := UI.vbox(12)
	right.custom_minimum_size.x = 560 if wide else 0
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not wide else Control.SIZE_FILL
	outer.add_child(right)
	right.add_child(UI.title("ESCOLHA O CASO", 40, UI.PAPER))
	lobby_cases = UI.vbox(12)
	lobby_cases.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(lobby_cases)
	var tc := UI.hbox(12)
	var tl := UI.label("Equipes", 30, UI.PAPER, "bold")
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tc.add_child(tl)
	var minus := UI.button("-", "ghost", 80)
	minus.custom_minimum_size.x = 90
	minus.pressed.connect(func() -> void: Net.send({"t": "host_settings", "teamCount": int(Net.state["settings"]["teamCount"]) - 1}))
	tc.add_child(minus)
	var cnt := UI.title("", 56, UI.YELLOW)
	cnt.name = "TeamCount"
	cnt.custom_minimum_size.x = 40
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tc.add_child(cnt)
	var plus := UI.button("+", "ghost", 80)
	plus.custom_minimum_size.x = 90
	plus.pressed.connect(func() -> void: Net.send({"t": "host_settings", "teamCount": int(Net.state["settings"]["teamCount"]) + 1}))
	tc.add_child(plus)
	var shuffle := UI.button("Sortear", "ghost", 80)
	shuffle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shuffle.pressed.connect(func() -> void: Net.send({"t": "host_shuffle"}))
	tc.add_child(shuffle)
	right.add_child(tc)
	var tm := UI.hbox(12)
	var tml := UI.label("Tempo", 30, UI.PAPER, "bold")
	tml.autowrap_mode = TextServer.AUTOWRAP_OFF
	tml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tm.add_child(tml)
	var tminus := UI.button("-5 min", "ghost", 80)
	tminus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tminus.pressed.connect(func() -> void: Net.send({"t": "host_settings", "extraMin": int(Net.state["settings"].get("extraMin", 0)) - 5}))
	tm.add_child(tminus)
	var tplus := UI.button("+5 min", "ghost", 80)
	tplus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tplus.pressed.connect(func() -> void: Net.send({"t": "host_settings", "extraMin": int(Net.state["settings"].get("extraMin", 0)) + 5}))
	tm.add_child(tplus)
	right.add_child(tm)

	var start := UI.button("COMEÇAR O CASO", "primary", 116)
	start.add_theme_font_size_override("font_size", 52)
	start.name = "Start"
	start.pressed.connect(func() -> void: Net.send({"t": "host_start"}))
	page.add_child(start)
	var leave := UI.button("Fechar a sala", "ghost", 64)
	leave.pressed.connect(func() -> void: get_meta("main").go_home())
	page.add_child(leave)


func _refresh_lobby() -> void:
	var st := Net.state
	var total := 0
	for t in st.get("teams", []):
		total += (t["players"] as Array).size()
	lobby_count.text = "%d detetive%s na sala" % [total, "" if total == 1 else "s"]
	var cnt := find_child("TeamCount", true, false) as Label
	if cnt:
		cnt.text = str(int(st.get("settings", {}).get("teamCount", 3)))
	var start := find_child("Start", true, false) as Button
	if start:
		start.disabled = total == 0
	UI.clear(lobby_teams)
	for t in st.get("teams", []):
		var col := Color(str(t["color"]))
		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.add_theme_stylebox_override("panel", UI.box(Color(col, 0.1), col, 3, 18, 18))
		var v := UI.vbox(8)
		var th := UI.hbox(8)
		var tn := UI.title(str(t["name"]).to_upper(), 42, col)
		tn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		th.add_child(tn)
		th.add_child(UI.title(str((t["players"] as Array).size()), 42, Color(col, 0.6)))
		v.add_child(th)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		for pl in t["players"]:
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", UI.box(Color(UI.NIGHT, 0.8), Color(col, 0.6), 2, 26, 12))
			var cl := UI.label(str(pl["name"]), 22, UI.PAPER if pl["online"] else UI.MIST, "bold")
			cl.autowrap_mode = TextServer.AUTOWRAP_OFF
			chip.add_child(cl)
			flow.add_child(chip)
		if (t["players"] as Array).is_empty():
			flow.add_child(UI.label("vazia", 22, UI.MIST, "type"))
		v.add_child(flow)
		p.add_child(v)
		lobby_teams.add_child(p)
	UI.clear(lobby_cases)
	var sel := str(st.get("settings", {}).get("caseId", ""))
	for c in st.get("cases", []):
		var on: bool = c["id"] == sel
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 150)
		b.add_theme_stylebox_override("normal", UI.box(Color(UI.YELLOW, 0.15) if on else Color(0, 0, 0, 0.3), UI.YELLOW if on else UI.BLUE, 4 if on else 2, 18))
		b.add_theme_stylebox_override("hover", UI.box(Color(UI.YELLOW, 0.2), UI.YELLOW, 3, 18))
		b.add_theme_stylebox_override("pressed", UI.box(Color(UI.YELLOW, 0.3), UI.YELLOW, 3, 18))
		var v := UI.vbox(2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 20; v.offset_top = 12; v.offset_right = -16
		var t := UI.title(str(c["title"]).to_upper(), 40, UI.YELLOW if on else UI.PAPER)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(t)
		var tg := UI.label(UI.strip_emoji(str(c.get("tagline", ""))), 22, UI.MIST)
		tg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tg)
		var meta := UI.label("%s  ·  %d min" % ["Fácil" if int(c.get("difficulty", 1)) == 1 else ("Médio" if int(c.get("difficulty", 1)) == 2 else "Difícil"), int(c.get("duration_sec", 900)) / 60], 22, UI.PINK, "bold")
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(meta)
		b.add_child(v)
		b.pressed.connect(func() -> void: Net.send({"t": "host_settings", "caseId": c["id"]}))
		lobby_cases.add_child(b)
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
	var v := UI.vbox(12)
	m.add_child(v)
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
	for k in [["equipes", "EQUIPES"], ["aovivo", "AO VIVO"], ["quadros", "QUADROS"]]:
		var b := UI.button(k[1], "ghost", 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", UI.font("title"))
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(func() -> void:
			game_tab = k[0]
			_feed_len = -1
			_refresh_game())
		tabs.add_child(b)
		tab_btns[k[0]] = b
	v.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.name = "PageScroll"
	page_scroll = scroll
	# enquanto o dedo rola, a tela não se refaz (senão a rolagem trava ou pula)
	scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _touch_scroll())
	scroll.gui_input.connect(func(_e: InputEvent) -> void: _touch_scroll())
	page_box = UI.vbox(12)
	page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page_box)
	v.add_child(scroll)
	# controles numa fileira só (rótulos curtos): sobra mais tela para a lista
	var ctrl := UI.hbox(8)
	for spec in [["DICA", "ghost", "hint"], ["PISTA", "ghost", "rel"], ["+1 MIN", "ghost", "more"], ["ENCERRAR", "danger", "end"]]:
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
	v.add_child(ctrl)


var page_scroll: ScrollContainer
var _busy_until := 0
var _pending := false


func _touch_scroll() -> void:
	_busy_until = Time.get_ticks_msec() + 1400


func _refresh_game() -> void:
	if page_scroll and Time.get_ticks_msec() < _busy_until:
		_pending = true
		return
	_pending = false
	var keep := page_scroll.scroll_vertical if page_scroll else 0
	_do_refresh_game()
	if page_scroll:
		page_scroll.set_deferred("scroll_vertical", keep)


func _do_refresh_game() -> void:
	var st := Net.state
	for k in tab_btns:
		var on: bool = k == game_tab
		(tab_btns[k] as Button).add_theme_stylebox_override("normal", UI.box(UI.YELLOW if on else Color(UI.NIGHT, 0.8), UI.YELLOW.darkened(0.4), 0 if on else 2, 16))
		(tab_btns[k] as Button).add_theme_color_override("font_color", UI.INK if on else UI.PAPER)
	if str(st.get("phase", "")) == "briefing":
		timer_l.text = "%ds" % Net.seconds_left()
	if game_tab == "aovivo":
		var feed: Array = st.get("feed", [])
		if feed.size() == _feed_len:
			return
		_feed_len = feed.size()
	UI.clear(page_box)
	match game_tab:
		"equipes":
			for t in st.get("teams", []):
				page_box.add_child(_team_card(t))
		"aovivo":
			_build_feed()
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


func _team_card(t: Dictionary) -> Control:
	var col := Color(str(t["color"]))
	var ins: Dictionary = Net.state.get("insight", {}).get(t["id"], {})
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", UI.box(Color(col, 0.08), col, 3, 20, 18))
	var v := UI.vbox(10)
	var h := UI.hbox(10)
	var name := UI.title(str(t["name"]).to_upper(), 46, col)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	h.add_child(name)
	if t.get("solved", false):
		var stamp := PanelContainer.new()
		stamp.add_theme_stylebox_override("panel", UI.box(Color(UI.GREEN, 0.15), UI.GREEN, 4, 6, 10))
		stamp.add_child(UI.title("RESOLVIDO %dº" % int(t.get("place", 1)), 30, UI.GREEN))
		h.add_child(stamp)
	elif int(ins.get("lockLeft", 0)) > 0:
		var lk := PanelContainer.new()
		lk.add_theme_stylebox_override("panel", UI.box(Color(UI.PINK, 0.15), UI.PINK, 2, 6, 10))
		var lkl := UI.label("errou · %ds" % int(ins["lockLeft"]), 20, UI.PINK, "bold")
		lkl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lk.add_child(lkl)
		h.add_child(lk)
	v.add_child(h)
	# progresso real (só o professor vê): pistas reunidas e ligações certas no quadro agora
	v.add_child(_bar("Pistas reunidas", int(ins.get("cluesFound", 0)), int(ins.get("cluesTotal", 1)), UI.SKY))
	v.add_child(_bar("Ligações certas no quadro (agora)", int(ins.get("edgesOk", 0)), int(ins.get("edgesTotal", 1)), UI.GREEN))
	v.add_child(UI.label("%d cartas · %d fios · %d teoria%s · %d objeto%s na mochila" % [int(t["cards"]), int(t["links"]), int(t["submissions"]), "" if int(t["submissions"]) == 1 else "s", int(ins.get("items", 0)), "" if int(ins.get("items", 0)) == 1 else "s"], 20, UI.PAPER))
	# alunos: ativo (verde), pensando (amarelo), parado ou fora (cinza/vermelho)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for mbr in ins.get("members", []):
		var idle := int(mbr.get("idleSec", 0))
		var dot := UI.GREEN if idle < 60 else (UI.YELLOW if idle < 180 else UI.RED)
		if not mbr.get("online", true):
			dot = UI.MIST.darkened(0.4)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UI.box(Color(UI.NIGHT, 0.85), dot, 2, 26, 12))
		var txt := str(mbr["name"])
		if not mbr.get("online", true):
			txt += "  fora"
		elif idle >= 180:
			txt += "  parado %dmin" % (idle / 60)
		var cl := UI.label(txt, 20, UI.PAPER, "bold")
		cl.autowrap_mode = TextServer.AUTOWRAP_OFF
		chip.add_child(cl)
		flow.add_child(chip)
	v.add_child(flow)
	var prog: Variant = t.get("progress")
	if prog is Array:
		var pf := HFlowContainer.new()
		pf.add_theme_constant_override("h_separation", 8)
		pf.add_theme_constant_override("v_separation", 8)
		var ltl := UI.label("Última teoria:", 19, UI.MIST)
		ltl.autowrap_mode = TextServer.AUTOWRAP_OFF
		pf.add_child(ltl)
		for cat in prog:
			var ok: bool = cat["status"] == "ok"
			var c2 := UI.GREEN if ok else (UI.RED if cat["status"] == "errado" else UI.YELLOW)
			var chip2 := PanelContainer.new()
			chip2.add_theme_stylebox_override("panel", UI.box(Color(c2, 0.2), c2, 2, 10, 8))
			var chl := UI.label(str(cat["label"]), 18, c2, "bold")
			chl.autowrap_mode = TextServer.AUTOWRAP_OFF
			chip2.add_child(chl)
			pf.add_child(chip2)
		v.add_child(pf)
	var row := UI.hbox(10)
	var see := UI.button("Ver quadro", "ghost", 70)
	see.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	see.pressed.connect(func() -> void: _open_viewer(t))
	row.add_child(see)
	var tip := UI.button("Mandar dica", "ghost", 70)
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip.pressed.connect(func() -> void: _open_hint(str(t["id"])))
	row.add_child(tip)
	var log := UI.button("Ações", "ghost", 70)
	log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log.pressed.connect(func() -> void:
		feed_filter = str(t["id"])
		game_tab = "aovivo"
		_feed_len = -1
		_refresh_game())
	row.add_child(log)
	v.add_child(row)
	p.add_child(v)
	return p


const FEED_COLORS := {"cena": Color("#ffc83d"), "conversa": Color("#6fd3ff"), "quadro": Color("#b9a3ff"), "teoria": Color("#ff9a4d"),
	"acerto": Color("#8ef0b5"), "alerta": Color("#ff6fae"), "dica": Color("#ffffff"), "sistema": Color("#a9bdf0"), "sala": Color("#a9bdf0")}


func _build_feed() -> void:
	var st := Net.state
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	var opts := [["", "TODAS", UI.PAPER]]
	for t in st.get("teams", []):
		opts.append([str(t["id"]), str(t["name"]).to_upper(), Color(str(t["color"]))])
	for o in opts:
		var on: bool = feed_filter == o[0]
		var b := UI.button(o[1], "ghost", 60)
		b.add_theme_font_override("font", UI.font("title"))
		b.add_theme_font_size_override("font_size", 26)
		b.custom_minimum_size.x = 140
		b.add_theme_stylebox_override("normal", UI.box(o[2] if on else Color(UI.NIGHT, 0.8), o[2], 2, 14))
		b.add_theme_color_override("font_color", UI.INK if on else o[2])
		b.pressed.connect(func() -> void:
			feed_filter = o[0]
			_feed_len = -1
			_refresh_game())
		chips.add_child(b)
	page_box.add_child(chips)
	var team_by := {}
	for t in st.get("teams", []):
		team_by[t["id"]] = t
	var feed: Array = st.get("feed", [])
	var shown := 0
	for i in range(feed.size() - 1, -1, -1):
		var e: Dictionary = feed[i]
		if feed_filter != "" and e.get("team") != feed_filter and e.get("team") != null:
			continue
		var t: Dictionary = team_by.get(e.get("team"), {})
		var tcol := Color(str(t.get("color", "#a9bdf0")))
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UI.box(Color(UI.NIGHT, 0.75), Color.TRANSPARENT, 0, 12, 12))
		var h := UI.hbox(10)
		var bar := ColorRect.new()
		bar.color = FEED_COLORS.get(str(e.get("kind", "")), UI.MIST)
		bar.custom_minimum_size = Vector2(6, 0)
		h.add_child(bar)
		var vv := UI.vbox(2)
		vv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ago := int((Net.server_now_ms() - float(e.get("at", 0))) / 1000.0)
		var meta := ("há %ds" % ago) if ago < 60 else ("há %dmin" % (ago / 60))
		if not t.is_empty():
			meta = str(t["name"]).to_upper() + "  ·  " + meta
		var ml := UI.label(meta, 17, tcol, "bold")
		ml.autowrap_mode = TextServer.AUTOWRAP_OFF
		vv.add_child(ml)
		vv.add_child(UI.label(UI.strip_emoji(str(e.get("text", ""))), 23, UI.PAPER))
		h.add_child(vv)
		row.add_child(h)
		page_box.add_child(row)
		shown += 1
		if shown >= 80:
			break
	if shown == 0:
		page_box.add_child(UI.label("Nada ainda. As ações dos alunos aparecem aqui em tempo real.", 24, UI.MIST, "type"))


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
		var s := Net.seconds_left()
		timer_l.text = UI.fmt_time(s)
		if s != _last_sec:
			_last_sec = s
			if s % 5 == 0 and game_tab != "quadros":
				_feed_len = -1
				_refresh_game()
			timer_l.add_theme_color_override("font_color", UI.RED if s <= 60 and s % 2 == 0 else UI.YELLOW)
			if s <= 10 and s > 0:
				Sfx.play("timer_urgent", -6.0)
	elif phase_built == "game" and timer_l:
		timer_l.text = "%ds" % Net.seconds_left()
