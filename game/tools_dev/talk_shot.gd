extends Control
## Sonda: abre uma conversa 3D com um personagem do caso e salva capturas de 3 expressões.
const TalkView := preload("res://scripts/scene3d/talk_view.gd")
var tv: Control

func _ready() -> void:
	var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../server/cases/rumor_1017.json")) if false else {}
	var card := {"id": "duda", "name": "Duda", "role": "baixista da banda", "look": {"skin": "#a8714f", "hair": "cacheado", "hair_color": "#1c1830", "top": "#5a3d6b", "accessory": "fones"}}
	tv = TalkView.new()
	tv.open(card, [
		{"text": "Eu? Eu só li a notificação, tá?", "expr": "nervoso", "anim": "nervoso"},
		{"text": "Tava correndo pro ensaio, juro!", "expr": "surpreso", "anim": "dando_de_ombros"},
		{"text": "Tá bom... talvez eu tenha exagerado.", "expr": "triste", "anim": "pensando"}], "DEPOIMENTO")
	add_child(tv)
	tv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dir := OS.get_environment("RUMOR_SHOT")
	for i in 3:
		await get_tree().create_timer(2.2).timeout
		get_viewport().get_texture().get_image().save_png(dir.path_join("talk_%d.png" % i))
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true
		tv._gui_input(ev); tv._gui_input(ev)
	var ch = tv.ch
	if ch.anim:
		print("ANIMS ", ch.anim.get_animation_list())
	else:
		print("SEM ANIMATIONPLAYER")
	get_tree().quit()
