extends Control
## Primeira tela: logotipo, frase de efeito e as duas portas (aluno entra, professor cria).

const Logo := preload("res://scripts/ui/logo.gd")


const CaseScene := preload("res://scripts/scene3d/case_scene.gd")

var _col: Control


## na tela larga a cena ocupa tudo e os botões ficam numa coluna central
func _fit() -> void:
	var wide := size.x > size.y * 1.05
	_col.anchor_left = 0.5 if wide else 0.0
	_col.anchor_right = 0.5 if wide else 1.0
	_col.offset_left = -440 if wide else 0
	_col.offset_right = 440 if wide else 0


func _ready() -> void:
	# fundo: a escola à noite na chuva, em 3D, com a câmera passeando devagar
	var bg := CaseScene.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UI.full(bg))
	bg.setup("fachada", [], {}, [])
	if bg.has_method("set_showcase"):
		bg.call("set_showcase", true)
	var shade := TextureRect.new()
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(UI.NIGHT, 0.0))
	g.set_color(1, Color(UI.NIGHT, 0.92))
	g.add_point(0.45, Color(UI.NIGHT, 0.15))
	grad.gradient = g
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0, 1)
	shade.texture = grad
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UI.full(shade))
	var m := UI.margin(48, 120, 70)
	add_child(UI.full(m))
	_col = m
	resized.connect(_fit)
	var v := UI.vbox(20)
	m.add_child(v)

	v.add_child(UI.spacer(0, true))
	var logo := Logo.new()
	v.add_child(logo)
	var tag := UI.label("Nada começa como parece.", 34, UI.PAPER, "type")
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	var sub := UI.label("Mistérios em equipe para a sala de aula", 24, UI.MIST)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(UI.spacer(0, true))

	var join := UI.button("ENTRAR NA SALA")
	join.custom_minimum_size.y = 120
	join.add_theme_font_size_override("font_size", 52)
	join.pressed.connect(func() -> void: get_meta("main").go_join())
	v.add_child(join)
	var host := UI.button("Sou professor: criar uma sala", "ghost")
	host.pressed.connect(func() -> void:
		Net.forget_session()
		Net.open()
		Net.host_create())
	v.add_child(host)

	var snd := UI.button("Som: ligado", "ghost", 64)
	snd.add_theme_font_size_override("font_size", 22)
	snd.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	snd.custom_minimum_size.x = 260
	snd.pressed.connect(func() -> void:
		Sfx.set_muted(not Sfx.muted)
		snd.text = "Som: desligado" if Sfx.muted else "Som: ligado")
	v.add_child(snd)
