extends Control
## Modo solo: o aluno escolhe um caso feito para jogar sozinho (sem professor, sem equipe).
## Os casos vêm do servidor (só os marcados como solo), separados por dificuldade.

var list: VBoxContainer
var status_l: Label


func _ready() -> void:
	var m := UI.margin(36, 60, 36)
	add_child(UI.full(m))
	var v := UI.vbox(16)
	m.add_child(v)
	var top := UI.hbox()
	var back := UI.button("Voltar", "ghost", 72)
	back.custom_minimum_size.x = 170
	back.pressed.connect(func() -> void: get_meta("main").go_home())
	top.add_child(back)
	v.add_child(top)
	v.add_child(UI.title("JOGAR SOZINHO", 72, UI.YELLOW))
	v.add_child(UI.label("Casos feitos para um detetive só. Você tem todas as pistas e pode pedir dicas.", 26, UI.MIST))
	status_l = UI.label("Carregando casos...", 26, UI.PAPER, "type")
	v.add_child(status_l)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list = UI.vbox(14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	v.add_child(sc)
	Net.cases_listed.connect(_on_cases)
	Net.open()
	Net.send({"t": "list_cases"})


func _on_cases(cases: Array) -> void:
	UI.clear(list)
	var solo := cases.filter(func(c: Dictionary) -> bool: return str(c.get("mode", "multi")) == "solo")
	solo.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("difficulty", 1)) < int(b.get("difficulty", 1)))
	status_l.visible = solo.is_empty()
	status_l.text = "Ainda não há casos solo neste servidor."
	for c in solo:
		var d := clampi(int(c.get("difficulty", 1)), 1, 3)
		var col: Color = [UI.GREEN, UI.YELLOW, UI.PINK][d - 1]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UI.box(Color(UI.NIGHT, 0.85), col, 3, 22, 22))
		var cv := UI.vbox(6)
		var h := UI.hbox(10)
		var t := UI.title(str(c["title"]).to_upper(), 46, UI.PAPER)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(t)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UI.box(col, Color.TRANSPARENT, 0, 10, 12))
		var cl := UI.title(["MUITO FÁCIL", "FÁCIL", "MÉDIO", "DIFÍCIL"][clampi(d, 0, 3)] if false else ["FÁCIL", "MÉDIO", "DIFÍCIL"][d - 1], 26, UI.INK)
		cl.autowrap_mode = TextServer.AUTOWRAP_OFF
		chip.add_child(cl)
		chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(chip)
		cv.add_child(h)
		if Net.solo_done().has(str(c["id"])):
			var dn := UI.title("CASO RESOLVIDO", 30, UI.GREEN)
			cv.add_child(dn)
		cv.add_child(UI.label(UI.strip_emoji(str(c.get("tagline", ""))), 24, UI.MIST))
		cv.add_child(UI.label("%d min" % (int(c.get("duration_sec", 600)) * 3 / 120), 22, col, "bold"))
		var go := UI.button("INVESTIGAR", "primary", 90)
		var cid := str(c["id"])
		go.pressed.connect(func() -> void:
			Net.forget_session()
			Net.open()
			Net.send({"t": "solo_start", "caseId": cid, "name": "Detetive"})
			Net.role = "player")
		cv.add_child(go)
		card.add_child(cv)
		list.add_child(card)
	UI.scroll_friendly(list)
