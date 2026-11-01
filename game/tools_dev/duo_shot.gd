extends Control
## Sonda: conversa a dois (discussão) com personagens de um caso, 3 falas alternadas.
const TalkView := preload("res://scripts/scene3d/talk_view.gd")

func _ready() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../server/cases/cofre_formatura.json")
	var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	Net.case_data = c
	var ppl := []
	for card in c["cards"]:
		if card["kind"] == "pessoa":
			ppl.append(card)
	var a: Dictionary = ppl[0]
	var b: Dictionary = ppl[1]
	var tree := {"cast": [b["id"]], "start": "n1", "nodes": {"n1": {"lines": [
		{"who": a["id"], "text": "Você sabia do cofre e ficou quieto?", "expr": "bravo", "anim": "apontando", "react": "nervoso"},
		{"who": b["id"], "text": "Eu? Quem mexeu no dinheiro foi você!", "expr": "bravo", "anim": "negando", "react": "surpreso"},
		{"who": a["id"], "text": "Fala baixo. Tem detetive ouvindo.", "expr": "nervoso", "anim": "nervoso", "react": "desconfiado"}],
		"choices": [{"text": "Ficar do lado de " + str(a["name"]), "next": "n1", "kind": "neutra"}, {"text": "Ficar do lado de " + str(b["name"]), "next": "n1", "kind": "neutra"}]}}}
	var tv := TalkView.new()
	tv.open_tree(a, tree, [])
	add_child(tv)
	tv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dir := OS.get_environment("RUMOR_SHOT")
	for i in 4:
		await get_tree().create_timer(2.0).timeout
		get_viewport().get_texture().get_image().save_png(dir.path_join("duo_%d.png" % i))
		tv._shown = 999.0
		tv._next()
	get_tree().quit()
