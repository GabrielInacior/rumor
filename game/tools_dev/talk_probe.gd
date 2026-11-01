extends Control
## Sonda das conversas: para cada caso, abre cada pessoa, passa por TODOS os nós e falas e confere
## se quem fala está em cena (conversa a dois), se a escolha leva a um nó existente e se a cena
## de cada lugar carrega com as pessoas. Rodar em janela, mudo:
##   godot --audio-driver Dummy --path . --resolution 405x720 res://tools_dev/talk_probe.tscn
const TalkView := preload("res://scripts/scene3d/talk_view.gd")
const CaseScene := preload("res://scripts/scene3d/case_scene.gd")

var problems := 0


func _ready() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../server/cases")
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".json"):
			continue
		var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		await _probe_case(c)
	print("SONDA_CONVERSAS problemas=%d" % problems)
	get_tree().quit()


func _bad(c: Dictionary, msg: String) -> void:
	problems += 1
	print("PROBLEMA %s: %s" % [c["id"], msg])


func _probe_case(c: Dictionary) -> void:
	Net.case_data = c
	var all_clues: Array = c["clues"].map(func(x: Dictionary) -> String: return str(x["id"]))
	var items: Array = (c.get("items", []) as Array).map(func(x: Dictionary) -> String: return str(x["id"]))
	Net.state = {"flags": {}, "items": items, "phase": "playing"}
	var n_nodes := 0
	for p in c["cards"]:
		var tree: Dictionary = p.get("talk", {}).get("tree", {})
		if tree.is_empty():
			continue
		var tv := TalkView.new()
		tv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tv.open_tree(p, tree, all_clues)
		add_child(tv)
		await get_tree().process_frame
		await get_tree().process_frame
		for nid in tree["nodes"]:
			var node: Dictionary = tree["nodes"][nid]
			tv.node_id = str(nid)
			tv._enter_node()
			n_nodes += 1
			for k in (node.get("lines", []) as Array).size():
				tv._shown = 999.0
				tv.idx = k - 1
				tv._next()
				var l: Dictionary = node["lines"][k]
				var who := str(l.get("who", p["id"]))
				if tv.speaker != who:
					_bad(c, "%s.%s fala %d: deveria falar %s, falou %s (não está em cena)" % [p["id"], nid, k, who, tv.speaker])
			for ch in node.get("choices", []):
				var nx := str(ch.get("next", ""))
				if nx != "" and not tree["nodes"].has(nx):
					_bad(c, "%s.%s escolha leva a %s inexistente" % [p["id"], nid, nx])
		tv.queue_free()
		await get_tree().process_frame
	# cenas: cada lugar com as pessoas que ficam lá no começo
	for loc in c.get("locations", []):
		var people := []
		var seen := {}
		for e in c.get("scene_people", []):
			var pid := str(e["id"])
			if seen.has(pid):
				continue
			if not (e.get("if", []) as Array).is_empty():
				continue
			seen[pid] = true
			if str(e["scene"]) == str(loc):
				people.append(Net.card_by_id(pid))
		var cs := CaseScene.new()
		cs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(cs)
		cs.setup(str(loc), c.get("hotspots", []).filter(func(h: Dictionary) -> bool: return h["scene"] == loc), {}, people)
		await get_tree().process_frame
		await get_tree().process_frame
		cs.queue_free()
		await get_tree().process_frame
	print("caso %s: %d nós percorridos" % [c["id"], n_nodes])
