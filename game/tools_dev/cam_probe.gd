extends Control
## Sonda da câmera: para cada cena, captura o olhar nos extremos (esq., dir., cima, baixo).
const CaseScene := preload("res://scripts/scene3d/case_scene.gd")

func _ready() -> void:
	var dir := OS.get_environment("RUMOR_SHOT")
	for sid in ["corredor", "sala_aula", "teatro", "deposito"]:
		var cs := CaseScene.new()
		add_child(cs)
		cs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cs.setup(sid, [], {}, [])
		await get_tree().create_timer(0.8).timeout
		var poses := [["esq", cs._yaw_limit, 0.0], ["dir", -cs._yaw_limit, 0.0], ["cima", 0.0, cs.PITCH_MAX], ["baixo", 0.0, cs.PITCH_MIN]]
		for p in poses:
			cs._yaw = p[1]
			cs._pitch = p[2]
			await get_tree().create_timer(0.9).timeout
			get_viewport().get_texture().get_image().save_png(dir.path_join("%s_%s.png" % [sid, p[0]]))
		cs.queue_free()
		await get_tree().process_frame
	get_tree().quit()
