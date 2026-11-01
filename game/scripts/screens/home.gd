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
	# escurece atrás do logotipo e dos botões; a fachada aparece entre os dois
	g.set_color(0, Color(UI.NIGHT, 0.55))
	g.set_color(1, Color(UI.NIGHT, 0.95))
	g.add_point(0.3, Color(UI.NIGHT, 0.62))
	g.add_point(0.5, Color(UI.NIGHT, 0.08))
	g.add_point(0.68, Color(UI.NIGHT, 0.5))
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
	_fit.call_deferred()
	var v := UI.vbox(20)
	m.add_child(v)

	v.add_child(UI.spacer(10))
	var logo := Logo.new()
	v.add_child(logo)
	var tag := UI.label("Nada começa como parece.", 34, UI.PAPER, "type")
	tag.add_theme_color_override("font_outline_color", UI.NIGHT)
	tag.add_theme_constant_override("outline_size", 10)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	# selo do professor: "carimbo" de papel com fita, como nas pistas do jogo
	var seal_row := CenterContainer.new()
	var seal := Paper.make("card", true)
	seal.rotation = -0.04
	var sv := UI.vbox(0)
	var s1 := UI.label("UMA INVESTIGAÇÃO DO", 20, Color(UI.INK, 0.7), "type")
	s1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(s1)
	var s2 := UI.title("PROF. AILSON", 64, UI.RED)
	s2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(s2)
	seal.add_child(sv)
	seal_row.add_child(seal)
	v.add_child(seal_row)
	seal.pivot_offset = Vector2(150, 50)
	var sub := UI.label("Mistérios em equipe para a sala de aula", 24, UI.MIST)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(UI.spacer(0, true))

	var join := UI.button("ENTRAR NA SALA")
	join.custom_minimum_size.y = 120
	join.add_theme_font_size_override("font_size", 52)
	join.pressed.connect(func() -> void: get_meta("main").go_join())
	v.add_child(join)
	var solo := UI.button("JOGAR SOZINHO", "ghost", 96)
	solo.add_theme_font_override("font", UI.font("title"))
	solo.add_theme_font_size_override("font_size", 40)
	solo.add_theme_stylebox_override("normal", UI.box(Color(UI.NIGHT, 0.8), UI.YELLOW, 3, 20))
	solo.pressed.connect(func() -> void: get_meta("main").go_solo())
	v.add_child(solo)
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
