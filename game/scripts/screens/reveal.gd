extends Control
## Revelação: placar, a verdade em linha do tempo, o quadro oficial e as hipóteses derrubadas.
## No telão vira a conversa final da aula; no celular cada aluno vê onde a equipe acertou.

const BoardView := preload("res://scripts/board/board_view.gd")
const Victory := preload("res://scripts/ui/victory.gd")

var tabs := {}
var page_holder: Control
var pages := {}


func _ready() -> void:
	var r: Dictionary = Net.reveal_data
	# modo solo resolvido: guarda como concluído para aparecer na lista de casos
	if Net.state.get("solo", false):
		for row in r.get("ranking", []):
			if row.get("solved", false):
				Net.mark_solo_done(str(Net.state.get("settings", {}).get("caseId", "")))
	var m := UI.margin(28, 36, 24)
	add_child(UI.full(m))
	var v := UI.vbox(14)
	m.add_child(v)
	v.add_child(UI.label("CASO ENCERRADO", 28, UI.MIST, "type"))
	var t := UI.title(str(Net.case_data.get("title", "")).to_upper(), 64, UI.YELLOW)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)

	var hidden := bool(r.get("hidden", false))
	var tb := UI.hbox(10)
	var tab_list := [["placar", "PLACAR"], ["resultado", "SEU RESULTADO"]] if hidden else [["placar", "PLACAR"], ["verdade", "A VERDADE"], ["quadro", "QUADRO OFICIAL"]]
	for k in tab_list:
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
	if hidden:
		# errou o culpado: a resposta não aparece (dá para tentar de novo outro dia)
		pages["resultado"] = _build_missed(r)
	else:
		pages["verdade"] = _build_truth(r)
		pages["quadro"] = _build_board(r)
	for k in pages:
		page_holder.add_child(UI.full(pages[k]))

	if Net.role == "host":
		var hrow := UI.hbox(10)
		var close := UI.button("FECHAR A SALA", "ghost", 100)
		close.custom_minimum_size.x = 240
		close.pressed.connect(func() -> void:
			UI.confirm(self, "FECHAR A SALA?", "Os alunos saem da sala. Para jogar de novo, crie outra.", "FECHAR", func() -> void: get_meta("main").go_home()))
		hrow.add_child(close)
		var again := UI.button("NOVA RODADA", "primary", 100)
		again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		again.pressed.connect(func() -> void: Net.send({"t": "host_lobby"}))
		hrow.add_child(again)
		v.add_child(hrow)
	else:
		var row := UI.hbox(10)
		if hidden and Net.state.get("solo", false):
			var retry := UI.button("TENTAR DE NOVO", "primary", 84)
			retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var cid := str(Net.state.get("settings", {}).get("caseId", ""))
			retry.pressed.connect(func() -> void:
				Net.forget_session()
				Net.open()
				Net.send({"t": "solo_start", "caseId": cid, "name": "Detetive"})
				Net.role = "player")
			row.add_child(retry)
		var solo := bool(Net.state.get("solo", false))
		var leave := UI.button("VOLTAR AOS CASOS" if solo else "Sair da sala", "ghost", 84)
		leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		leave.pressed.connect(func() -> void:
			if solo:
				get_meta("main").leave_to_solo()
			else:
				get_meta("main").go_home())
		row.add_child(leave)
		v.add_child(row)
	_show("resultado" if hidden else "placar")
	# aluno: primeiro a tela de vitória (com compartilhar), depois a revelação completa
	if Net.role == "player":
		var vic := Victory.new()
		vic.setup_from_reveal(r)
		add_child(UI.full(vic))


## Quem errou o culpado vê só o próprio resultado: o que cumpriu, sem a resposta.
func _build_missed(r: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := UI.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.box(Color("#d9b977"), Color("#b8944f"), 2, 8, 20))
	var cv := UI.vbox(8)
	var st := UI.title("CULPADO NÃO ENCONTRADO", 44, Color("#c42c3f"))
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(st)
	var msg := "A pessoa acusada não era a culpada. A resposta continua em segredo: dá para investigar de novo." if Net.state.get("solo", false) \
		else "A pessoa acusada não era a culpada. A resposta continua em segredo para a próxima vez."
	cv.add_child(UI.label(msg, 24, Color("#1b2140"), "type"))
	card.add_child(cv)
	v.add_child(card)
	var mine: Dictionary = r.get("mine", {}) if r.get("mine") is Dictionary else {}
	v.add_child(UI.label("O QUE VOCÊS CUMPRIRAM", 20, UI.YELLOW, "type"))
	for cat in mine.get("categories", []):
		if str(cat.get("id", "")) == "culpado":
			continue
		var ok := str(cat["status"]) == "ok"
		var row := UI.hbox(10)
		var l := UI.label(str(cat["label"]), 24, UI.PAPER, "bold")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var stamp := PanelContainer.new()
		var c := UI.GREEN if ok else UI.MIST
		stamp.add_theme_stylebox_override("panel", UI.box(Color(c, 0.15), c, 2, 6, 8))
		var sl := UI.title("PROVADO" if ok else "NÃO PROVADO", 24, c)
		sl.autowrap_mode = TextServer.AUTOWRAP_OFF
		stamp.add_child(sl)
		stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(stamp)
		v.add_child(row)
	return scroll


func _show(k: String) -> void:
	if not pages.has(k):
		return
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
		# objetivos: culpado (principal) + partes provadas (secundários) + tempo de entrega
		var info := ("Culpado certo" if row.get("culpritOk", false) else "Culpado errado")
		info += " · %d de %d provas" % [int(row.get("objDone", 0)), int(row.get("objTotal", 0))]
		if row.get("timeSec") != null:
			info += " · entregou em %s" % UI.fmt_time(int(row["timeSec"]))
		elif not row.get("finished", true):
			info += " · não entregou a tempo"
		tv.add_child(UI.label(info, 26, UI.GREEN if row.get("culpritOk", false) else UI.MIST, "bold"))
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
	var all_edges: Array = (r.get("edges", []) as Array) + (r.get("panorama", []) as Array)
	for e in all_edges:
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
		links.append({"id": "o%d" % n, "a": e["from"], "b": e["to"], "type": e["type"], "evidence": ev, "color": "vermelho"})
	# panorama: o resto da história (quem mentiu, acobertou, quem é inocente), em fios azuis
	for e in r.get("panorama", []):
		n += 1
		var pev: Variant = null
		if not (e.get("evidence", []) as Array).is_empty():
			pev = e["evidence"][0]
		links.append({"id": "o%d" % n, "a": e["from"], "b": e["to"], "type": e["type"], "evidence": pev, "color": "azul"})
	bv.set_data(cards, links)
	return page
