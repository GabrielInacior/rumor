extends Control
## Primeira tela: logotipo, frase de efeito e as duas portas (aluno entra, professor cria).

const Logo := preload("res://scripts/ui/logo.gd")


func _ready() -> void:
	var m := UI.margin(48, 120, 70)
	add_child(UI.full(m))
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
