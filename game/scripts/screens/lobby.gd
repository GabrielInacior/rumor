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
	v.add_child(UI.label("Toque numa equipe para entrar nela. Sentem juntos!", 26, UI.MIST))
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
	head.text = "SALA %s · %s" % [Net.code, Net.state.get("me", {}).get("name", Net.my_name)]
	UI.clear(list)
	var mine := str(Net.state.get("me", {}).get("team", ""))
	for t in Net.state.get("teams", []):
		var col := Color(str(t["color"]))
		var is_mine: bool = t["id"] == mine
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 130)
		b.add_theme_stylebox_override("normal", UI.box(Color(col, 0.22 if is_mine else 0.08), col, 5 if is_mine else 2, 22))
		b.add_theme_stylebox_override("hover", UI.box(Color(col, 0.3), col, 4, 22))
		b.add_theme_stylebox_override("pressed", UI.box(Color(col, 0.45), col, 4, 22))
		var inner := UI.vbox(4)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 26; inner.offset_top = 14; inner.offset_right = -20
		var name_l := UI.title(("EQUIPE " + str(t["name"]).to_upper()) + ("   (você)" if is_mine else ""), 46, col)
		inner.add_child(name_l)
		var names := []
		for p in t["players"]:
			names.append(str(p["name"]))
		var pl := UI.label(", ".join(names) if names.size() > 0 else "ninguém ainda", 24, UI.PAPER)
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(pl)
		b.add_child(inner)
		b.pressed.connect(func() -> void:
			Sfx.play("card_pin")
			Net.send({"t": "pick_team", "team": t["id"]}))
		list.add_child(b)
