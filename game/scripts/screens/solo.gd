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
	v.add_child(UI.label("A gaveta de casos do Prof. Ailson. Escolha uma pasta: você tem todas as pistas e pode pedir dicas.", 26, UI.MIST))
	status_l = UI.label("Carregando casos...", 26, UI.PAPER, "type")
	v.add_child(status_l)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list = UI.vbox(34)
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
	var done := Net.solo_done()
	var n_done := solo.filter(func(c: Dictionary) -> bool: return done.has(str(c["id"]))).size()
	if not solo.is_empty():
		var prog := UI.label("%d de %d arquivos resolvidos" % [n_done, solo.size()], 24, UI.YELLOW, "type")
		list.add_child(prog)
	var n := 0
	for c in solo:
		n += 1
		var f := CaseFile.new()
		f.setup(c, n, done.has(str(c["id"])))
		var cid := str(c["id"])
		f.open_pressed.connect(func() -> void:
			Net.forget_session()
			Net.open()
			Net.send({"t": "solo_start", "caseId": cid, "name": "Detetive"})
			Net.role = "player")
		list.add_child(f)
	UI.scroll_friendly(list)
