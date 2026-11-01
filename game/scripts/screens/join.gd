extends Control
## Entrar na sala sem teclado do celular: teclado numérico próprio para o código e
## codinomes de detetive prontos (ninguém expõe o nome real, e é mais divertido).

const ALIASES := [
	"Corvo", "Lince", "Coruja", "Raposa", "Sombra", "Neblina", "Faro", "Lupa",
	"Gato Preto", "Trench", "Fumaça", "Agente Zero", "Morcego", "Vulto", "Cobra", "Pantera",
]

var digits := ""
var boxes: Array[Label] = []
var step := 1
var body: VBoxContainer
var title_l: Label


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
			p.custom_minimum_size = Vector2(110, 120) if _wide() else Vector2(130, 160)
			p.add_theme_stylebox_override("panel", UI.box(UI.NIGHT, UI.YELLOW, 4, 18))
			var l := UI.title("", 90 if _wide() else 120, UI.YELLOW)
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
			var b := UI.button(k, "primary" if k == "OK" else "ghost", 66 if _wide() else 110)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_override("font", UI.font("title"))
			b.add_theme_font_size_override("font_size", 60)
			b.pressed.connect(_key.bind(k))
			grid.add_child(b)
		body.add_child(grid)
		_show_digits()
	else:
		title_l.text = "SEU CODINOME"
		body.add_child(UI.label("Escolha como sua equipe vai te chamar.", 26, UI.MIST))
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 16)
		var list := ALIASES.duplicate()
		list.shuffle()
		for a in list:
			var b := UI.button(a, "ghost", 100)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_override("font", UI.font("marker"))
			b.add_theme_font_size_override("font_size", 34)
			b.pressed.connect(func() -> void:
				Net.open()
				Net.join(digits, a))
			grid.add_child(b)
		scroll.add_child(grid)
		body.add_child(scroll)


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


func _show_digits() -> void:
	for i in boxes.size():
		boxes[i].text = digits[i] if i < digits.length() else ""
