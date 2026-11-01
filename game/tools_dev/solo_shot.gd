extends Node
## Captura da tela do solo com os casos reais (sem servidor).

func _ready() -> void:
	var out := OS.get_environment("RUMOR_SHOT")
	var scr: Control = load("res://scripts/screens/solo.gd").new()
	scr.set_meta("main", self)
	scr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scr)
	await get_tree().process_frame
	var dir := ProjectSettings.globalize_path("res://").path_join("../server/cases")
	var cases: Array = []
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".json"):
			continue
		var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		var cover := ""
		var cover_name := ""
		var place := ""
		var people := 0
		for k in c["cards"]:
			if k["kind"] == "pessoa":
				people += 1
				if cover == "" and k["id"] != c["solution"]["culprit"]:
					cover = k["id"]; cover_name = k["name"]
			if k["kind"] == "lugar" and place == "":
				place = k["name"]
		cases.append({"id": c["id"], "title": c["title"], "tagline": c.get("tagline", ""), "difficulty": c["difficulty"],
			"duration_sec": c["duration_sec"], "mode": c.get("mode", "multi"), "cover": cover, "cover_name": cover_name,
			"place": place, "people": people})
	Net.cases_listed.emit(cases)
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("solo_0.png"))
	var sc: ScrollContainer = scr.find_children("*", "ScrollContainer", true, false)[0]
	sc.scroll_vertical = 1100
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("solo_1.png"))
	get_tree().quit()


func go_home() -> void:
	pass
