extends Control
## Revelação: placar, a verdade em linha do tempo, o quadro oficial e as hipóteses derrubadas.
## No telão vira a conversa final da aula; no celular cada aluno vê onde a equipe acertou.

const BoardView := preload("res://scripts/board/board_view.gd")

var tabs := {}
var page_holder: Control
var pages := {}


func _ready() -> void:
	var r: Dictionary = Net.reveal_data
	var m := UI.margin(28, 36, 24)
	add_child(UI.full(m))
	var v := UI.vbox(14)
	m.add_child(v)
	v.add_child(UI.label("CASO ENCERRADO", 28, UI.MIST, "type"))
	var t := UI.title(str(Net.case_data.get("title", "")).to_upper(), 64, UI.YELLOW)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)

	var tb := UI.hbox(10)
	for k in [["placar", "PLACAR"], ["verdade", "A VERDADE"], ["quadro", "QUADRO OFICIAL"]]:
		var b := UI.button(k[1], "ghost", 84)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", UI.font("title"))
		b.add_theme_font_size_override("font_size", 32)
		b.pressed.connect(_show.bind(k[0]))
		tb.add_child(b)
		tabs[k[0]] = b
	v.add_child(tb)

	page_holder = Control.new()
	page_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(page_holder)
	pages["placar"] = _build_ranking(r)
	pages["verdade"] = _build_truth(r)
	pages["quadro"] = _build_board(r)
	for k in pages:
		page_holder.add_child(UI.full(pages[k]))

	if Net.role == "host":
		var again := UI.button("NOVA RODADA", "primary", 100)
		again.pressed.connect(func() -> void: Net.send({"t": "host_lobby"}))
		v.add_child(again)
	else:
		var leave := UI.button("Sair da sala", "ghost", 76)
		leave.pressed.connect(func() -> void: get_meta("main").go_home())
		v.add_child(leave)
	_show("placar")


func _show(k: String) -> void:
	for key in pages:
		(pages[key] as Control).visible = key == k
	for key in tabs:
		var on: bool = key == k
		(tabs[key] as Button).add_theme_stylebox_override("normal", UI.box(UI.YELLOW if on else Color(0, 0, 0, 0.25), UI.YELLOW.darkened(0.4), 0 if on else 2, 18))
		(tabs[key] as Button).add_theme_color_override("font_color", UI.INK if on else UI.PAPER)
	if k == "quadro":
		var bv := pages["quadro"].get_meta("board") as Control
		bv.call_deferred("fit")


func _build_ranking(r: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := UI.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var mine := str(Net.state.get("me", {}).get("team", ""))
	var i := 0
	for row in r.get("ranking", []):
		var col := Color(str(row["color"]))
		var p := PanelContainer.new()
		var first: bool = int(row["place"]) == 1
		p.add_theme_stylebox_override("panel", UI.box(Color(col, 0.22 if first else 0.1), col, 5 if row["id"] == mine else 2, 20, 22))
		var h := UI.hbox(18)
		h.add_child(UI.title("%dº" % int(row["place"]), 110 if first else 80, col))
		var tv := UI.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UI.title("EQUIPE " + str(row["name"]).to_upper() + ("  (vocês)" if row["id"] == mine else ""), 50 if first else 40, UI.PAPER))
		var info := ""
		if row["solved"]:
			info = "Resolveu em %s" % UI.fmt_time(int(row["timeSec"]))
		else:
			info = "Não fechou o caso · %d pontos de dedução" % int(row["score"])
		info += " · %d teoria%s" % [int(row["submissions"]), "" if int(row["submissions"]) == 1 else "s"]
		tv.add_child(UI.label(info, 26, UI.GREEN if row["solved"] else UI.MIST, "bold"))
		h.add_child(tv)
		p.add_child(h)
		v.add_child(p)
		UI.pop_in(p, i * 0.25)
		i += 1
	return scroll


func _build_truth(r: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := UI.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var rv: Dictionary = r.get("reveal", {})
	if r.get("culprit") != null:
		# cartaz de "procurado" do culpado, o grande momento da revelação
		var cp := Net.card_by_id(str(r["culprit"]))
		var poster := Paper.make("polaroid", true)
		var ph := UI.hbox(18)
		var tr := TextureRect.new()
		tr.texture = UI.portrait(str(r["culprit"]))
		tr.custom_minimum_size = Vector2(180, 225)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ph.add_child(tr)
		var pv := UI.vbox(4)
		pv.add_child(UI.title("FOI ELE(A)", 40, UI.RED))
		pv.add_child(UI.title(UI.strip_emoji(str(cp.get("name", "?"))).to_upper(), 64, UI.INK))
		pv.add_child(UI.label(str(cp.get("role", "")), 22, Color(UI.INK, 0.7)))
		ph.add_child(pv)
		poster.add_child(ph)
		v.add_child(poster)
		UI.pop_in(poster, 0.2)
	var exp := UI.panel(Color(UI.PAPER, 0.96), UI.INK)
	exp.add_child(UI.label(UI.strip_emoji(str(rv.get("explanation", ""))), 28, UI.INK, "type"))
	v.add_child(exp)
	v.add_child(UI.title("O QUE ACONTECEU DE VERDADE", 40, UI.YELLOW))
	for step in rv.get("timeline", []):
		var h := UI.hbox(16)
		var tm := UI.title(str(step.get("time", "")), 40, UI.PINK)
		tm.custom_minimum_size.x = 120
		h.add_child(tm)
		var tx := UI.label(UI.strip_emoji(str(step.get("text", ""))), 26, UI.PAPER)
		tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(tx)
		v.add_child(h)
	if not (rv.get("refuted", []) as Array).is_empty():
		v.add_child(UI.title("PISTAS FALSAS QUE ENGANARAM", 40, UI.RED))
		for s in rv.get("refuted", []):
			v.add_child(UI.label("·  " + UI.strip_emoji(str(s)), 26, UI.MIST))
	return scroll


func _build_board(r: Dictionary) -> Control:
	# monta o quadro oficial a partir das ligações exigidas, em círculo
	var page := Control.new()
	var bv := BoardView.new()
	bv.readonly = true
	page.add_child(UI.full(bv))
	page.set_meta("board", bv)
	var ids: Array = []
	for e in r.get("edges", []):
		for k in ["from", "to"]:
			if not ids.has(e[k]):
				ids.append(e[k])
	var cards := []
	for i in ids.size():
		var a := TAU * i / maxf(1, ids.size()) - PI / 2.0
		cards.append({"ref": "p:" + str(ids[i]), "x": 0.5 + cos(a) * 0.33, "y": 0.5 + sin(a) * 0.33})
	var links := []
	var n := 0
	for e in r.get("edges", []):
		n += 1
		var ev: Variant = null
		if not (e.get("evidence", []) as Array).is_empty():
			ev = e["evidence"][0]
		links.append({"id": "o%d" % n, "a": e["from"], "b": e["to"], "type": e["type"], "evidence": ev})
	bv.set_data(cards, links)
	return page
