extends SubViewportContainer
## Objeto 3D low-poly girando devagar (a mochila da equipe na aba Pistas). Uma vista viva só,
## o resto usa as fotos em cache do Snap para não pesar no celular.

var kind := "mochila"
var _model: Node3D
var _t := 0.0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#3a52a0")
	e.ambient_light_energy = 1.0
	env.environment = e
	vp.add_child(env)
	_model = ItemModels.build(kind)
	vp.add_child(_model)
	var key := OmniLight3D.new()
	key.light_color = Color("#ffd99a")
	key.light_energy = 2.4
	key.omni_range = 6.0
	key.position = Vector3(1.2, 1.8, 1.6)
	vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color("#7fa0ff")
	rim.light_energy = 1.8
	rim.omni_range = 5.0
	rim.position = Vector3(-1.4, 1.0, -1.0)
	vp.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 34
	vp.add_child(cam)
	cam.position = Vector3(0, 0.85, 3.1)
	cam.look_at(Vector3(0, 0.45, 0), Vector3.UP)


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	_t += dt
	_model.rotation.y = sin(_t * 0.6) * 0.7
	_model.position.y = sin(_t * 1.4) * 0.02
