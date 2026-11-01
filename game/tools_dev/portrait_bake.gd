extends Node
## Gera os retratos das cartas a partir do PRÓPRIO personagem 3D do jogo (mesmo cabelo, gênero,
## roupa e rosto), para o quadro e o modelo nunca divergirem. Rodar em janela, mudo:
##   godot --audio-driver Dummy --path . res://tools_dev/portrait_bake.tscn
const Character := preload("res://scripts/scene3d/character.gd")
const SIZE := Vector2i(256, 320)

func _ready() -> void:
	var out := ProjectSettings.globalize_path("res://assets/portraits/")
	var cases_dir := ProjectSettings.globalize_path("res://").path_join("../server/cases")
	var done := {}
	for f in DirAccess.get_files_at(cases_dir):
		if not f.ends_with(".json"):
			continue
		var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(cases_dir.path_join(f)))
		for card in c["cards"]:
			if card["kind"] != "pessoa" or done.has(card["id"]):
				continue
			done[card["id"]] = true
			await _bake(card, out.path_join(str(card["id"]) + ".png"))
	print("RETRATOS ", done.size())
	get_tree().quit()

func _bake(card: Dictionary, path: String) -> void:
	var vp := SubViewport.new()
	vp.size = SIZE * 2
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#4a62b0")
	e.ambient_light_energy = 1.5
	env.environment = e
	vp.add_child(env)
	var ch := Character.new()
	vp.add_child(ch)
	# retrato com expressão neutra/simpática (o humor fica para a conversa)
	var c2 := card.duplicate(true)
	c2["talk"] = {"mood": "neutro"}
	ch.setup(c2)
	ch.rotation.y = 0.32
	var key := OmniLight3D.new()
	key.light_color = Color("#ffd99a")
	key.light_energy = 4.2
	key.omni_range = 5.0
	key.position = Vector3(0.9, 1.9, 1.3)
	vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color("#7fa0ff")
	rim.light_energy = 2.6
	rim.omni_range = 4.0
	rim.position = Vector3(-1.0, 1.9, -0.8)
	vp.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 24
	vp.add_child(cam)
	var lift := 0.17 if bool(card.get("adult", false)) else 0.0
	cam.position = Vector3(0.1, 1.52 + lift, 1.55)
	cam.look_at(Vector3(0.0, 1.43 + lift, 0), Vector3.UP)
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	img.save_png(path)
	vp.queue_free()
