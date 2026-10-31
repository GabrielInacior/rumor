extends Control
## Sala de espera do aluno: escolhe a equipe (toque na cor) e espera o professor começar.

var list: VBoxContainer
var head: Label
var dots := 0.0
var wait_l: Label


func _ready() -> void:
	var m := UI.margin(36, 60, 40)
	add_child(UI.full(m))
	var v := UI.vbox(18)
	m.add_child(v)
	head = UI.title("", 56, UI.YELLOW)
	v.add_child(head)
	v.add_child(UI.label("Sentem juntos com a sua equipe. O professor pode trocar as equipes.", 24, UI.MIST))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list = UI.vbox(16)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	v.add_child(scroll)
	wait_l = UI.label("", 30, UI.PAPER, "type")
	wait_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(wait_l)
	var leave := UI.button("Sair da sala", "ghost", 70)
	leave.pressed.connect(func() -> void: get_meta("main").go_home())
	v.add_child(leave)


func _process(dt: float) -> void:
	dots += dt
	wait_l.text = "Esperando o professor começar" + ".".repeat(int(dots * 2.0) % 4)


func refresh() -> void:
	head.text = "SALA %s" % Net.code
	UI.clear(list)
	var me_name := str(Net.state.get("me", {}).get("name", Net.my_name))
	var you := UI.label("Você é  " + me_name, 30, UI.PAPER, "marker")
	list.add_child(you)
	var mine := str(Net.state.get("me", {}).get("team", ""))
	for t in Net.state.get("teams", []):
		var col := Color(str(t["color"]))
		var is_mine: bool = t["id"] == mine
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UI.box(Color(col, 0.2 if is_mine else 0.07), col, 5 if is_mine else 2, 22, 22))
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var v := UI.vbox(10)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var top := UI.hbox(10)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nm := UI.title("EQUIPE " + str(t["name"]).to_upper(), 48, col)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(nm)
		var count := UI.title("%d" % (t["players"] as Array).size(), 48, Color(col, 0.6))
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(count)
		v.add_child(top)
		# colegas como fichas, cabem várias por linha sem rolagem interna
		var flow := HFlowContainer.new()
		flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 10)
		for p in t["players"]:
			var chip := PanelContainer.new()
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var me: bool = str(p["name"]) == me_name
			chip.add_theme_stylebox_override("panel", UI.box(col if me else Color(UI.NIGHT, 0.8), col, 2, 30, 14))
			var cl := UI.label(str(p["name"]), 24, UI.INK if me else UI.PAPER, "bold")
			cl.autowrap_mode = TextServer.AUTOWRAP_OFF
			cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(cl)
			flow.add_child(chip)
		if (t["players"] as Array).is_empty():
			var e := UI.label("ninguém ainda", 22, UI.MIST, "type")
			e.mouse_filter = Control.MOUSE_FILTER_IGNORE
			flow.add_child(e)
		v.add_child(flow)
		if not is_mine:
			var hint := UI.label("toque para entrar nesta equipe", 20, Color(col, 0.8), "bold")
			hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(hint)
		card.add_child(v)
		card.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and not is_mine:
				Sfx.play("card_pin")
				Net.send({"t": "pick_team", "team": t["id"]}))
		list.add_child(card)
