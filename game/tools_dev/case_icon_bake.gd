extends Node
## Gera a "foto de evidência" de cada caso (objeto 3D do campo cover_icon) para as pastas do
## solo e a janela de casos do professor. Nunca mostra uma pessoa (não entrega pista).
##   godot --audio-driver Dummy --path . --resolution 640x480 res://tools_dev/case_icon_bake.tscn
const FLAT := ["carta", "papel", "prancheta", "celular", "mensagem"]


func _ready() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../server/cases")
	var out := ProjectSettings.globalize_path("res://assets/case_icons")
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".json"):
			continue
		var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		var kind := str(c.get("cover_icon", "caixa"))
		var img := await _render(kind)
		img.save_png(out.path_join(str(c["id"]) + ".png"))
		print("icone ", c["id"], " ", kind)
	get_tree().quit()


func _render(kind: String) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 512)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#3a5596")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#9fb2e6")
	e.ambient_light_energy = 1.6
	env.environment = e
	vp.add_child(env)
	# mesa de evidência: um pano escuro com luz quente de luminária
	var model := ItemModels.build(kind)
	var pivot := Node3D.new()
	vp.add_child(pivot)
	pivot.add_child(model)
	if kind in FLAT:
		pivot.rotation.x = 0.55 if kind != "celular" and kind != "mensagem" else 0.0
	pivot.rotation.y = -0.45
	await get_tree().process_frame
	var aabb := Snap._aabb(model)
	model.position = -aabb.get_center()
	var key := OmniLight3D.new()
	key.light_color = Color("#ffe2b0")
	key.light_energy = 4.5
	key.omni_range = 8.0
	key.position = Vector3(1.4, 1.8, 2.0)
	vp.add_child(key)
	var fill := OmniLight3D.new()
	fill.light_color = Color("#c9d6ff")
	fill.light_energy = 2.0
	fill.omni_range = 8.0
	fill.position = Vector3(-1.8, 0.6, 1.6)
	vp.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 34
	var r := maxf(aabb.size.length() * 0.5, 0.2)
	cam.position = Vector3(0, r * 0.7, r * 3.4)
	vp.add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	vp.queue_free()
	return img
