extends Control
## Entrar na sala sem teclado do celular: teclado numérico próprio para o código e
## nome digitado pelo aluno (com filtro de palavrão) e codinomes como sugestão.

const ALIASES := [
	"Corvo", "Lince", "Coruja", "Raposa", "Sombra", "Neblina", "Faro", "Lupa",
	"Gato Preto", "Trench", "Fumaça", "Agente Zero", "Morcego", "Vulto", "Cobra", "Pantera",
]

var digits := ""
var boxes: Array[Label] = []
var step := 1
var body: VBoxContainer
var title_l: Label
var err_l: Label
static var _last_name := ""


func _ready() -> void:
	var m := UI.margin(40, 70, 50)
	add_child(UI.full(m))
	var v := UI.vbox(24)
	m.add_child(v)
	var top := UI.hbox()
	var back := UI.button("Voltar", "ghost", 72)
	back.custom_minimum_size.x = 170
	back.pressed.connect(func() -> void:
		if step == 2:
			step = 1
			_build()
		else:
			get_meta("main").go_home())
	top.add_child(back)
	v.add_child(top)
	title_l = UI.title("", 72)
	v.add_child(title_l)
	body = UI.vbox(24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	_build()
	# recusa do servidor (nome proibido ou repetido) aparece embaixo do campo
	Net.error_msg.connect(func(t: String) -> void:
		if step == 2 and is_instance_valid(err_l):
			err_l.text = t
			err_l.visible = true)


func _build() -> void:
	UI.clear(body)
	boxes.clear()
	if step == 1:
		title_l.text = "CÓDIGO DA SALA"
		var hint := UI.label("Está no telão do professor.", 26, UI.MIST)
		body.add_child(hint)
		var row := UI.hbox(18)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for i in 4:
			var p := PanelContainer.new()
			# tela deitada (PC) tem pouca altura: quadrados e teclas menores para caber tudo
			p.custom_minimum_size = Vector2(130, 160)
			p.add_theme_stylebox_override("panel", UI.box(UI.NIGHT, UI.YELLOW, 4, 18))
			var l := UI.title("", 120, UI.YELLOW)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			p.add_child(l)
			boxes.append(l)
			row.add_child(p)
		body.add_child(row)
		body.add_child(UI.spacer(0, true))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 16)
		for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "<", "0", "OK"]:
			var b := UI.button(k, "primary" if k == "OK" else "ghost", 96 if _wide() else 110)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_override("font", UI.font("title"))
			b.add_theme_font_size_override("font_size", 60)
			b.pressed.connect(_key.bind(k))
			grid.add_child(b)
		body.add_child(grid)
		if _wide():
			var kb := UI.label("Dá para digitar o código no teclado.", 22, UI.MIST)
			kb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			body.add_child(kb)
		_show_digits()
	else:
		title_l.text = "SEU NOME"
		body.add_child(UI.label("Como a sua equipe vai te chamar.", 26, UI.MIST))
		var field := LineEdit.new()
		field.placeholder_text = "Digite seu nome"
		field.max_length = 20
		field.custom_minimum_size = Vector2(0, 104)
		field.add_theme_font_override("font", UI.font("marker"))
		field.add_theme_font_size_override("font_size", 40)
		field.add_theme_color_override("font_color", UI.INK)
		field.add_theme_color_override("font_placeholder_color", Color(UI.INK, 0.4))
		field.add_theme_color_override("caret_color", UI.INK)
		field.add_theme_stylebox_override("normal", UI.box(UI.PAPER, UI.YELLOW, 4, 16, 20))
		field.add_theme_stylebox_override("focus", UI.box(UI.PAPER, UI.PINK, 4, 16, 20))
		field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
		field.text = _last_name
		body.add_child(field)
		err_l = UI.label("", 22, UI.RED, "bold")
		err_l.visible = false
		body.add_child(err_l)
		var go := UI.button("ENTRAR", "primary", 100)
		go.add_theme_font_size_override("font_size", 46)
		var submit := func(_t: String = "") -> void:
			var msg := NameFilter.problem(field.text)
			err_l.text = msg
			err_l.visible = msg != ""
			if msg != "":
				Sfx.play("ui_tap")
				return
			_last_name = field.text.strip_edges()
			Net.open()
			Net.join(digits, _last_name)
		go.pressed.connect(submit)
		field.text_submitted.connect(submit)
		field.text_changed.connect(func(_t: String) -> void: err_l.visible = false)
		body.add_child(go)
		# codinomes continuam como sugestão (para quem não quer usar o nome)
		var sug := UI.label("ou toque num codinome:", 20, UI.MIST, "type")
		body.add_child(sug)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 10)
		var list := ALIASES.duplicate()
		list.shuffle()
		for a in list.slice(0, 8):
			var b := UI.button(a, "ghost", 64)
			b.add_theme_font_override("font", UI.font("marker"))
			b.add_theme_font_size_override("font_size", 26)
			b.custom_minimum_size.x = 0
			b.pressed.connect(func() -> void:
				field.text = a
				err_l.visible = false)
			flow.add_child(b)
		body.add_child(flow)


func _wide() -> bool:
	var vs := get_viewport_rect().size
	return vs.x > vs.y * 1.05


func _key(k: String) -> void:
	if k == "<":
		digits = digits.substr(0, maxi(0, digits.length() - 1))
	elif k == "OK":
		if digits.length() == 4:
			step = 2
			_build()
			return
	elif digits.length() < 4:
		digits += k
		if digits.length() == 4:
			Sfx.play("card_pin")
	_show_digits()


## PC: o código também entra pelo teclado (números, apagar, Enter).
func _unhandled_key_input(e: InputEvent) -> void:
	if step != 1 or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k := (e as InputEventKey).keycode
	if k >= KEY_0 and k <= KEY_9:
		_key(str(k - KEY_0))
	elif k >= KEY_KP_0 and k <= KEY_KP_9:
		_key(str(k - KEY_KP_0))
	elif k == KEY_BACKSPACE:
		_key("<")
	elif k == KEY_ENTER or k == KEY_KP_ENTER:
		_key("OK")
	else:
		return
	get_viewport().set_input_as_handled()


func _show_digits() -> void:
	for i in boxes.size():
		boxes[i].text = digits[i] if i < digits.length() else ""
