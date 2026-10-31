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
	var m := UI.margin(36, 40, 30)
	body.add_child(UI.full(m))
	var outer: BoxContainer = UI.hbox(30) if _wide() else UI.vbox(18)
	m.add_child(outer)

	var left := UI.vbox(14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(left)
	left.add_child(UI.label("Entrem em  " + _host_url() + "  e digitem o código:", 30, UI.MIST, "bold"))
	var code := UI.title("SALA " + Net.code, 150 if _wide() else 110, UI.YELLOW)
	left.add_child(code)
	lobby_count = UI.label("", 30, UI.PAPER, "bold")
	left.add_child(lobby_count)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lobby_teams = GridContainer.new()
	(lobby_teams as GridContainer).columns = 3 if _wide() else 2
	lobby_teams.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_teams.add_theme_constant_override("h_separation", 14)
	lobby_teams.add_theme_constant_override("v_separation", 14)
	scroll.add_child(lobby_teams)
	left.add_child(scroll)

	var right := UI.vbox(14)
	right.custom_minimum_size.x = 560 if _wide() else 0
	outer.add_child(right)
	right.add_child(UI.title("CASO", 44, UI.PAPER))
	var cs := ScrollContainer.new()
	cs.custom_minimum_size.y = 420 if _wide() else 360
	cs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lobby_cases = UI.vbox(12)
	lobby_cases.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cs.add_child(lobby_cases)
	right.add_child(cs)
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
	var start := UI.button("COMEÇAR O CASO", "primary", 120)
	start.add_theme_font_size_override("font_size", 54)
	start.name = "Start"
	start.pressed.connect(func() -> void: Net.send({"t": "host_start"}))
	right.add_child(start)
	var leave := UI.button("Fechar a sala", "ghost", 64)
	leave.pressed.connect(func() -> void: get_meta("main").go_home())
	right.add_child(leave)


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
		p.custom_minimum_size.y = 150
		p.add_theme_stylebox_override("panel", UI.box(Color(col, 0.1), col, 3, 18, 18))
		var v := UI.vbox(4)
		v.add_child(UI.title(str(t["name"]).to_upper(), 42, col))
		for pl in t["players"]:
			v.add_child(UI.label(str(pl["name"]), 26, UI.PAPER if pl["online"] else UI.MIST))
		if (t["players"] as Array).is_empty():
			v.add_child(UI.label("vazia", 24, UI.MIST, "type"))
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


# ================================================================== RODADA
func _build_game() -> void:
	UI.clear(body)
	var m := UI.margin(30, 26, 24)
	body.add_child(UI.full(m))
	var v := UI.vbox(16)
	m.add_child(v)
	var top := UI.hbox(24)
	timer_l = UI.title("0:00", 130, UI.YELLOW)
	top.add_child(timer_l)
	var tv := UI.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UI.label("SALA %s" % Net.code, 26, UI.MIST, "bold"))
	var tt := UI.title(str(Net.case_data.get("title", "")).to_upper(), 60, UI.PAPER)
	tt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(tt)
	var goal := UI.label(str(Net.case_data.get("goal", "")), 26, UI.YELLOW)
	tv.add_child(goal)
	top.add_child(tv)
	v.add_child(top)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 3 if _wide() else 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	teams_box = grid
	scroll.add_child(grid)
	v.add_child(scroll)

	var ctrl := UI.hbox(12)
	var rel := UI.button("Liberar próxima pista", "ghost")
	rel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rel.pressed.connect(func() -> void: Net.send({"t": "host_release"}))
	ctrl.add_child(rel)
	var more := UI.button("+1 minuto", "ghost")
	more.custom_minimum_size.x = 200
	more.pressed.connect(func() -> void: Net.send({"t": "host_add_time"}))
	ctrl.add_child(more)
	var end := UI.button("ENCERRAR E REVELAR", "danger")
	end.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end.pressed.connect(func() -> void: Net.send({"t": "host_end"}))
	ctrl.add_child(end)
	v.add_child(ctrl)


func _refresh_game() -> void:
	var st := Net.state
	if str(st.get("phase", "")) == "briefing":
		timer_l.text = "%ds" % Net.seconds_left()
	UI.clear(teams_box)
	for t in st.get("teams", []):
		teams_box.add_child(_team_card(t))
	if viewer_team != "" and viewer_board:
		var b: Dictionary = st.get("boards", {}).get(viewer_team, {})
		viewer_board.set_data(b.get("cards", []), b.get("links", []))


func _team_card(t: Dictionary) -> Control:
	var col := Color(str(t["color"]))
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", UI.box(Color(col, 0.08), col, 3, 20, 20))
	var v := UI.vbox(8)
	var h := UI.hbox(10)
	var name := UI.title(str(t["name"]).to_upper(), 50, col)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name)
	if t.get("solved", false):
		var stamp := PanelContainer.new()
		stamp.add_theme_stylebox_override("panel", UI.box(Color(UI.GREEN, 0.15), UI.GREEN, 4, 6, 12))
		stamp.add_child(UI.title("RESOLVIDO %dº" % int(t.get("place", 1)), 34, UI.GREEN))
		h.add_child(stamp)
	v.add_child(h)
	var names := []
	for pl in t["players"]:
		names.append(str(pl["name"]))
	v.add_child(UI.label(", ".join(names) if names.size() else "sem alunos", 22, UI.MIST))
	v.add_child(UI.label("%d cartas · %d fios · %d teoria%s" % [int(t["cards"]), int(t["links"]), int(t["submissions"]), "" if int(t["submissions"]) == 1 else "s"], 26, UI.PAPER, "bold"))
	var prog: Variant = t.get("progress")
	if prog is Array:
		var row := UI.hbox(8)
		for cat in prog:
			var ok: bool = cat["status"] == "ok"
			var c2 := UI.GREEN if ok else (UI.RED if cat["status"] == "errado" else UI.YELLOW)
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", UI.box(Color(c2, 0.2), c2, 2, 10, 8))
			chip.add_child(UI.label(str(cat["label"]), 18, c2, "bold"))
			row.add_child(chip)
		var flow := HFlowContainer.new()
		for ch in row.get_children():
			row.remove_child(ch)
			flow.add_child(ch)
		v.add_child(flow)
	var see := UI.button("Ver quadro ao vivo", "ghost", 72)
	see.pressed.connect(func() -> void: _open_viewer(t))
	v.add_child(see)
	p.add_child(v)
	return p


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
	if phase_built == "game" and timer_l and str(Net.state.get("phase", "")) == "playing":
		var s := Net.seconds_left()
		timer_l.text = UI.fmt_time(s)
		if s != _last_sec:
			_last_sec = s
			timer_l.add_theme_color_override("font_color", UI.RED if s <= 60 and s % 2 == 0 else UI.YELLOW)
			if s <= 10 and s > 0:
				Sfx.play("timer_urgent", -6.0)
	elif phase_built == "game" and timer_l:
		timer_l.text = "%ds" % Net.seconds_left()
