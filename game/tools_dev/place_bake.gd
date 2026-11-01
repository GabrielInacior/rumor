extends Control
## Gera as fotos dos lugares para o quadro (uma por cena), em PNG: no celular o quadro usa estas
## imagens prontas em vez de renderizar a cena 3D. Rodar em janela 640x480 (mudo):
##   godot --audio-driver Dummy --path . --resolution 640x480 res://tools_dev/place_bake.tscn
const CaseScene := preload("res://scripts/scene3d/case_scene.gd")
const SCENES := ["corredor", "biblioteca", "teatro", "sala_aula", "cantina", "patio", "sala_professores", "quadra",
	"sala_diretor", "deposito", "laboratorio", "sala_musica", "fachada"]

func _ready() -> void:
	var out := ProjectSettings.globalize_path("res://assets/places")
	for id in SCENES:
		var cs := CaseScene.new()
		add_child(cs)
		cs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cs.setup(id, [], {}, [])
		await get_tree().create_timer(1.6).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(480, 360, Image.INTERPOLATE_LANCZOS)
		img.save_png(out.path_join(id + ".png"))
		print("lugar ", id)
		cs.queue_free()
		await get_tree().process_frame
	get_tree().quit()
