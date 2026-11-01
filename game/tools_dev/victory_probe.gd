extends Node
## Sonda: monta a imagem de compartilhar da vitória (1080x1920) com um quadro de exemplo e salva.
func _ready() -> void:
	var audit: Node = load("res://tools_dev/ui_audit.gd").new()
	var path := ProjectSettings.globalize_path("res://").path_join("../server/cases/cofre_formatura.json")
	audit.full_case = JSON.parse_string(FileAccess.get_file_as_string(path))
	Net.case_data = audit._public_case()
	var st: Dictionary = audit._player_state("reveal")
	var sol: Dictionary = audit.full_case["solution"]
	var links := []
	var n := 0
	for e in sol["edges"]:
		n += 1
		links.append({"id": "l%d" % n, "a": e["from"], "b": e["to"], "type": e["type"], "proofs": e.get("evidence", []).slice(0, 1 + n % 2), "evidence": e.get("evidence", [null])[0]})
	st["board"] = {"cards": [], "links": links}
	st["clues"] = audit.full_case["clues"]
	Net.state = st
	var cats := []
	var q := 0
	for c in sol["categories"]:
		cats.append({"id": c["id"], "label": c["label"], "status": "ok" if q != 1 else "falta_prova"})
		q += 1
	cats.append({"id": "culpado", "label": sol.get("culprit_question", "Culpado"), "status": "ok"})
	var r := {"culprit": sol["culprit"], "ranking": [{"id": "t1", "name": "Lanterna", "color": "#ffc83d", "place": 1, "solved": false, "culpritOk": true, "timeSec": 1312}],
		"mine": {"culpritOk": true, "objDone": 2, "objTotal": 3, "categories": cats}}
	var vic: Node = load("res://scripts/ui/victory.gd").new()
	vic.setup_from_reveal(r)
	var vp := SubViewport.new()
	vp.size = Vector2i(1080, 1920)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var card: Control = vic._make_card(Vector2(1080, 1920))
	card.theme = UI.build_theme()
	vp.add_child(card)
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(OS.get_environment("RUMOR_SHOT").path_join("vitoria_share.png"))
	var t := UI.portrait("rafa")
	print("RAFA tex=", t, " size=", t.get_size() if t else Vector2.ZERO, " pixel=", t.get_image().get_pixel(128, 160) if t else Color())
	print("OK")
	get_tree().quit()
