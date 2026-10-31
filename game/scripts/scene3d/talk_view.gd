extends Control
## Conversa em 3D: close no personagem sob a luz do abajur, uma fala por vez num balão de
## quadrinho, com a expressão e o gesto de cada fala. Toque em qualquer lugar para avançar.

signal finished

const Character := preload("res://scripts/scene3d/character.gd")

var lines: Array = []
var idx := -1
var card: Dictionary = {}
var subtitle := ""
var ch: Node3D
var name_l: Label
var text_l: Label
var hint_l: Label
var tag_l: Label
var _full := ""
var _shown := 0.0
var _vp: SubViewport


func open(p_card: Dictionary, p_lines: Array, p_subtitle := "") -> void:
	card = p_card
	lines = p_lines
	subtitle = p_subtitle


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color("#04070f")
	add_child(UI.full(bg))
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UI.full(svc))
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	svc.add_child(_vp)
	_build_set()

	# barra de cinema em cima com o nome
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0.75), Color.TRANSPARENT, 0, 0, 20))
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tv := UI.vbox(0)
	tag_l = UI.label(subtitle if subtitle != "" else "CONVERSA", 22, UI.MIST, "type")
	tv.add_child(tag_l)
	name_l = UI.title(UI.strip_emoji(str(card.get("name", ""))).to_upper(), 64, UI.YELLOW)
	tv.add_child(name_l)
	if str(card.get("role", "")) != "":
		tv.add_child(UI.label(str(card["role"]), 22, UI.PAPER))
	top.add_child(tv)
	add_child(top)

	# balão de fala estilo quadrinho
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", UI.box(Color("#fbf8ef"), UI.INK, 5, 30, 28))
	bubble.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bubble.offset_left = 22; bubble.offset_right = -22; bubble.offset_bottom = -30
	bubble.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bv := UI.vbox(10)
	text_l = UI.label("", 32, UI.INK, "type")
	text_l.custom_minimum_size.y = 150
	text_l.add_theme_constant_override("line_spacing", 8)
	bv.add_child(text_l)
	hint_l = UI.label("toque para continuar", 20, Color(UI.INK, 0.5), "bold")
	hint_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bv.add_child(hint_l)
	bubble.add_child(bv)
	add_child(bubble)
	var tail := Tail.new()
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tail.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	tail.offset_bottom = -30
	add_child(tail)
	tail.bubble = bubble
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)
	_next()


func _build_set() -> void:
	var w := Node3D.new()
	_vp.add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0a1226")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#2a3f78")
	e.ambient_light_energy = 0.7
	env.environment = e
	w.add_child(env)
	# parede com persiana: faixas de luz da lua atravessando (clichê noir obrigatório)
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(6, 4, 0.1)
	wall.mesh = wm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/toon.gdshader")
	mat.set_shader_parameter("albedo", Color("#3d4f8a"))
	wall.material_override = mat
	wall.position = Vector3(0, 1.6, -1.6)
	w.add_child(wall)
	for i in 7:
		var slat := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(1.6, 0.06, 0.02)
		slat.mesh = sm
		var em := StandardMaterial3D.new()
		em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		em.albedo_color = Color("#9fb8ff", 0.35)
		em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		slat.material_override = em
		slat.position = Vector3(-1.1, 1.3 + i * 0.16, -1.54)
		slat.rotation.z = 0.25
		w.add_child(slat)
	ch = Character.new()
	w.add_child(ch)
	ch.setup(card)
	ch.rotation.y = 0.18
	var key := OmniLight3D.new()
	key.light_color = Color("#ffcf7a")
	key.light_energy = 2.4
	key.omni_range = 4.0
	key.position = Vector3(0.9, 1.9, 1.1)
	w.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color("#7fa0ff")
	rim.light_energy = 2.0
	rim.omni_range = 4.0
	rim.position = Vector3(-1.1, 2.0, -0.8)
	w.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 32
	w.add_child(cam)
	cam.position = Vector3(0.15, 1.58, 1.9)
	cam.look_at(Vector3(0.0, 1.42, 0), Vector3.UP)


func _next() -> void:
	idx += 1
	if idx >= lines.size():
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.2)
		tw.tween_callback(func() -> void:
			finished.emit()
			queue_free())
		return
	var l: Dictionary = lines[idx]
	_full = UI.strip_emoji(str(l.get("text", "")))
	_shown = 0.0
	ch.set_expression(str(l.get("expr", "neutro")))
	ch.play(str(l.get("anim", "falando")))
	ch.set_talking(true)
	hint_l.text = "toque para continuar" if idx < lines.size() - 1 else "toque para fechar"
	Sfx.play("paper_flip", -14.0, 1.3)


func _process(dt: float) -> void:
	if _shown < _full.length():
		var before := int(_shown)
		_shown = minf(_full.length(), _shown + dt * 42.0)
		text_l.text = _full.substr(0, int(_shown))
		if int(_shown) != before and int(_shown) % 2 == 0:
			Sfx.play("ui_tap", -22.0, randf_range(1.8, 2.3))
		if _shown >= _full.length():
			ch.set_talking(false)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if _shown < _full.length():
			_shown = _full.length()
			text_l.text = _full
			ch.set_talking(false)
		else:
			_next()


## rabicho do balão apontando para o personagem
class Tail extends Control:
	var bubble: Control

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if bubble == null:
			return
		var top := bubble.position.y - position.y
		var x := size.x * 0.5
		var pts := PackedVector2Array([Vector2(x - 40, top + 4), Vector2(x + 10, top + 4), Vector2(x - 30, top - 60)])
		draw_colored_polygon(pts, Color("#fbf8ef"))
		draw_polyline(PackedVector2Array([pts[0], pts[2], pts[1]]), UI.INK, 5.0)
