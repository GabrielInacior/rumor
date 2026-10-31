extends Control
## Tela-mãe: fundo animado, troca de telas conforme o papel e a fase da sala, avisos (toasts).

const HomeScreen := preload("res://scripts/screens/home.gd")
const JoinScreen := preload("res://scripts/screens/join.gd")
const LobbyScreen := preload("res://scripts/screens/lobby.gd")
const BriefingScreen := preload("res://scripts/screens/briefing.gd")
const GameScreen := preload("res://scripts/screens/game.gd")
const HostScreen := preload("res://scripts/screens/host.gd")
const RevealScreen := preload("res://scripts/screens/reveal.gd")

var backdrop: ColorRect
var holder: Control
var toast_box: VBoxContainer
var conn_label: Label
var current: Control
var current_kind := ""
var forced := ""   # "join" enquanto o aluno digita o código


func _ready() -> void:
	theme = UI.build_theme()
	UI.full(self)
	backdrop = ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/backdrop.gdshader")
	backdrop.material = mat
	add_child(UI.full(backdrop))
	holder = Control.new()
	add_child(UI.full(holder))

	toast_box = VBoxContainer.new()
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toast_box.offset_top = 150
	toast_box.add_theme_constant_override("separation", 10)
	toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(toast_box)

	conn_label = UI.label("Reconectando...", 22, UI.NIGHT, "bold")
	conn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cl_bg := PanelContainer.new()
	cl_bg.add_theme_stylebox_override("panel", UI.box(UI.YELLOW, UI.INK, 0, 0, 8))
	cl_bg.add_child(conn_label)
	cl_bg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	cl_bg.offset_top = -44
	cl_bg.name = "Conn"
	cl_bg.visible = false
	add_child(cl_bg)

	Net.state_changed.connect(_route)
	Net.case_loaded.connect(_route)
	Net.revealed.connect(_route)
	Net.joined.connect(func() -> void: forced = ""; _route())
	Net.hosted.connect(_route)
	Net.kicked.connect(func() -> void: toast("O professor removeu você da sala.", UI.RED); _route())
	Net.error_msg.connect(func(t: String) -> void: toast(t, UI.RED))
	Net.event.connect(_on_event)
	Net.connected.connect(func() -> void: get_node("Conn").visible = false)
	Net.disconnected.connect(func() -> void: get_node("Conn").visible = Net.role != "")
	resized.connect(_on_resize)
	get_window().size_changed.connect(_apply_scale)
	_apply_scale()
	_on_resize()

	if Net.has_saved_session():
		Net.open()
	_route()
	_dev_hooks()
	# o navegador só libera som depois do primeiro toque; o Godot retoma o áudio sozinho nessa hora
	if OS.get_environment("RUMOR_SHOT") == "":
		Sfx.start_music()


## Ganchos só para teste automático (variáveis de ambiente; no navegador não existem).
func _dev_hooks() -> void:
	var auto_join := OS.get_environment("RUMOR_AUTO_JOIN")
	if auto_join != "":
		var parts := auto_join.split(":")
		Net.forget_session()
		Net.open()
		Net.join(parts[0], parts[1] if parts.size() > 1 else "Corvo")
	if OS.get_environment("RUMOR_AUTO_HOST") != "":
		Net.forget_session()
		Net.open()
		Net.host_create()
	var shot_dir := OS.get_environment("RUMOR_SHOT")
	if shot_dir == "":
		return
	var plan := OS.get_environment("RUMOR_SHOT_PLAN")   # "6:cena,9:pistas,12:quadro"
	for step in plan.split(","):
		var kv := step.split(":")
		if kv.size() < 2:
			continue
		var t := float(kv[0])
		var what := kv[1]
		get_tree().create_timer(t).timeout.connect(func() -> void:
			if what.begins_with("tab_") and current and current.has_method("_set_tab"):
				current._set_tab(what.substr(4))
				return
			if what == "open_first_clue" and current and current.has_method("_open_clue"):
				var cl: Array = Net.state.get("clues", [])
				if cl.size() > 0:
					current._open_clue(cl[0])
				return
			if what == "palette" and current and current.has_method("_open_palette"):
				current._open_palette()
				return
			if what == "close" and current and current.has_method("_close_sheet"):
				current._close_sheet()
				return
			if what == "quit":
				get_tree().quit()
				return
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot_dir.path_join(what + ".png")))


## Celular em pé usa a base 720x1280; tela deitada (computador, projetor, tablet deitado) usa 1600x900,
## senão tudo encolheria pela altura e ficaria minúsculo no telão.
func _apply_scale() -> void:
	var win := get_window()
	var s := win.size
	var want := Vector2i(1600, 900) if s.x > s.y * 1.05 else Vector2i(720, 1280)
	if win.content_scale_size != want:
		win.content_scale_size = want


func is_wide() -> bool:
	return size.x > size.y * 1.05


func _on_resize() -> void:
	(backdrop.material as ShaderMaterial).set_shader_parameter("px_size", size)
	_fit_column()


## Telas de leitura viram uma coluna central na tela larga (o quadro e a cena usam a largura toda).
func _fit_column() -> void:
	if current == null:
		return
	var narrow := current_kind in ["join", "lobby", "briefing", "reveal"] and is_wide()
	if narrow:
		current.anchor_left = 0.5
		current.anchor_right = 0.5
		current.offset_left = -480
		current.offset_right = 480
	else:
		current.anchor_left = 0.0
		current.anchor_right = 1.0
		current.offset_left = 0
		current.offset_right = 0


func go_join() -> void:
	forced = "join"
	_route()


func go_home() -> void:
	forced = ""
	Net.forget_session()
	_route()


func _route() -> void:
	var kind := "home"
	var phase := str(Net.state.get("phase", ""))
	if forced == "join":
		kind = "join"
	elif Net.role == "host" and Net.code != "":
		kind = "reveal" if phase == "reveal" and not Net.reveal_data.is_empty() else "host"
	elif Net.role == "player" and Net.pid != "":
		match phase:
			"lobby": kind = "lobby"
			"briefing": kind = "briefing" if not Net.case_data.is_empty() else "lobby"
			"playing": kind = "game" if not Net.case_data.is_empty() else "lobby"
			"reveal": kind = "reveal" if not Net.reveal_data.is_empty() else "game"
			_: kind = "lobby"
	if kind != current_kind:
		_swap(kind)
	elif current and current.has_method("refresh"):
		current.refresh()


func _swap(kind: String) -> void:
	if current:
		current.queue_free()
	current_kind = kind
	var scr: Control
	match kind:
		"home": scr = HomeScreen.new()
		"join": scr = JoinScreen.new()
		"lobby": scr = LobbyScreen.new()
		"briefing": scr = BriefingScreen.new()
		"game": scr = GameScreen.new()
		"host": scr = HostScreen.new()
		"reveal": scr = RevealScreen.new()
	scr.set_meta("main", self)
	holder.add_child(UI.full(scr))
	current = scr
	_fit_column()
	if scr.has_method("refresh"):
		scr.refresh()
	scr.modulate.a = 0.0
	create_tween().tween_property(scr, "modulate:a", 1.0, 0.3)
	# menos chuva durante a investigação, para não competir com o quadro
	(backdrop.material as ShaderMaterial).set_shader_parameter("rain_amount", 0.35 if kind == "game" else 1.0)


func _on_event(evt: Dictionary) -> void:
	match str(evt.get("k", "")):
		"join":
			if Net.role == "host":
				Sfx.play("join_ping")
		"go":
			Sfx.play("countdown_go")
		"clue_new":
			Sfx.play("clue_new")
			if Net.role == "player":
				toast("Nova pista chegou: " + UI.strip_emoji(str(evt.get("title", ""))), UI.YELLOW)
		"hotspot":
			Sfx.play("hotspot_found")
			if Net.role == "player":
				toast("%s achou: %s" % [evt.get("by", "Alguém"), evt.get("label", "uma pista")], UI.YELLOW)
		"item":
			Sfx.play("hotspot_found")
			if Net.role == "player":
				toast("%s pegou: %s (foi para a mochila)" % [evt.get("by", "Alguém"), UI.strip_emoji(str(evt.get("label", "")))], UI.YELLOW)
		"interrogated":
			Sfx.play("clue_new")
			if Net.role == "player":
				toast("%s fez %s abrir o jogo: %s" % [evt.get("by", "Alguém"), evt.get("person", "alguém"), UI.strip_emoji(str(evt.get("title", "")))], UI.YELLOW)
		"wrong":
			Sfx.play("wrong")
		"solved":
			Sfx.play("correct")
			toast("Equipe %s resolveu o caso! (%dº lugar)" % [evt.get("name", ""), int(evt.get("place", 1))], UI.GREEN)
		"reveal":
			Sfx.play("victory")
	if current and current.has_method("on_event"):
		current.on_event(evt)


func toast(text: String, color := UI.YELLOW) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(UI.NIGHT, 0.95), color, 3, 18, 20))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.label(text, 26, UI.PAPER, "bold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	var m := UI.margin(24, 0, 0)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(p)
	toast_box.add_child(m)
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(3.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(m.queue_free)
