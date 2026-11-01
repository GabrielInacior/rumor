extends Node
## Fotos do quadro: renderiza UMA vez cada objeto 3D (fatos, itens) ou cena de lugar numa
## imagem pequena e guarda em cache. Fila de um por vez para não pesar no celular.

signal photo_ready(key: String)

const CaseScene := preload("res://scripts/scene3d/case_scene.gd")
const SIZE := Vector2i(320, 240)

var _cache := {}
var _queue: Array = []
var _busy := false


## kind = "item:<icone>" ou "scene:<id da cena>". Devolve a textura se pronta, senão null e agenda.
func get_tex(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	if not _queue.has(key):
		_queue.append(key)
		_pump.call_deferred()
	return null


func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var key: String = _queue.pop_front()
	var tex: Texture2D = null
	if key.begins_with("scene:"):
		tex = await _render_scene(key.substr(6))
	else:
		tex = await _render_item(key.substr(5))
	_cache[key] = tex
	_busy = false
	photo_ready.emit(key)
	_pump.call_deferred()


func _render_item(kind: String) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#1d2c5a")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#3a52a0")
	e.ambient_light_energy = 1.0
	env.environment = e
	vp.add_child(env)
	var model := ItemModels.build(kind)
	vp.add_child(model)
	var aabb := _aabb(model)
	model.position = -aabb.get_center()
	model.rotation.y = -0.5
	var key := OmniLight3D.new()
	key.light_color = Color("#ffd99a")
	key.light_energy = 2.2
	key.omni_range = 6.0
	key.position = Vector3(1.2, 1.6, 1.6)
	vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color("#7fa0ff")
	rim.light_energy = 1.6
	rim.omni_range = 5.0
	rim.position = Vector3(-1.4, 0.8, -1.0)
	vp.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 38
	var r := maxf(aabb.size.length() * 0.5, 0.2)
	cam.position = Vector3(0, r * 0.9, r * 2.6)
	vp.add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	return await _grab(vp)


func _render_scene(scene_id: String) -> Texture2D:
	var cs := CaseScene.new()
	cs.position = Vector2(-4000, -4000)
	cs.size = Vector2(SIZE)
	cs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	layer.add_child(cs)
	cs.setup(scene_id, [], {}, [])
	return await _grab(cs.vp, layer)


func _grab(vp: SubViewport, owner_node: Node = null) -> Texture2D:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	(owner_node if owner_node else vp).queue_free()
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.transform * m.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
