extends Node
## Sonda de auditoria da interface: simula uma sala completa sem servidor e captura cada tela e
## painel no tamanho de celular em pé. Rodar em janela (sempre mudo):
##   godot --audio-driver Dummy --path . --resolution 405x720 res://tools_dev/ui_audit.tscn
## Variáveis: RUMOR_SHOT=<pasta>, AUDIT_CASE=<id do caso>, AUDIT_ONLY=nome1,nome2

var main: Node
var dir := ""
var only: Array = []
var full_case: Dictionary = {}


func _ready() -> void:
	dir = OS.get_environment("RUMOR_SHOT")
	if OS.get_environment("AUDIT_ONLY") != "":
		only = Array(OS.get_environment("AUDIT_ONLY").split(","))
	var cid := OS.get_environment("AUDIT_CASE")
	if cid == "":
		cid = "rumor_1017"
	var path := ProjectSettings.globalize_path("res://").path_join("../server/cases/%s.json" % cid)
	full_case = JSON.parse_string(FileAccess.get_file_as_string(path))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _wait(1.0)
	await _run()
	get_tree().quit()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(name: String) -> void:
	if not only.is_empty() and not only.has(name):
		return
	await _wait(0.6)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("SHOT ", name)


func _public_case() -> Dictionary:
	var c := full_case.duplicate(true)
	var sol: Dictionary = c["solution"]
	c.erase("solution")
	c.erase("reveal")
	c.erase("clues")
	c["categories"] = sol["categories"]
	c["has_culprit"] = sol.has("culprit")
	c["culprit_question"] = sol.get("culprit_question", "Quem é o responsável?")
	return c


func _teams(phase: String) -> Array:
	var names := [["Corvo", "Lince", "Coruja", "Raposa"], ["Sombra", "Neblina", "Faro"], ["Lupa", "Gato Preto", "Trench", "Fumaça", "Morcego"]]
	var presets := [["t1", "Lanterna", "#ffc83d"], ["t2", "Neblina", "#6fd3ff"], ["t3", "Néon", "#ff6fae"]]
	var out := []
	for i in 3:
		var pl := []
		for n in names[i]:
			pl.append({"id": n, "name": n, "online": true})
		out.append({"id": presets[i][0], "name": presets[i][1], "color": presets[i][2], "players": pl,
			"solved": i == 1 and phase != "lobby", "place": 1 if i == 1 else 0, "submissions": i, "score": 250 * i,
			"progress": null, "cards": 6 + i, "links": 2 + i})
	return out


func _player_state(phase: String) -> Dictionary:
	var now := Time.get_unix_time_from_system() * 1000.0
	var clues: Array = full_case["clues"].slice(0, 6)
	var people := []
	for c in full_case["cards"]:
		if c["kind"] == "pessoa":
			people.append(c["id"])
	var e: Array = full_case["solution"]["edges"]
	var cards := []
	var pos := [[0.25, 0.3], [0.72, 0.28], [0.3, 0.72], [0.72, 0.7], [0.5, 0.5]]
	var i := 0
	for id in people.slice(0, 4):
		cards.append({"ref": "p:" + str(id), "x": pos[i][0], "y": pos[i][1], "by": "Corvo"})
		i += 1
	for edge in e:
		for k in ["from", "to"]:
			if not cards.any(func(c: Dictionary) -> bool: return c["ref"] == "p:" + str(edge[k])):
				cards.append({"ref": "p:" + str(edge[k]), "x": randf_range(0.2, 0.8), "y": randf_range(0.2, 0.8), "by": "Lince"})
	for c in full_case["cards"]:
		if c["kind"] in ["fato", "lugar"] and not cards.any(func(x: Dictionary) -> bool: return x["ref"] == "p:" + str(c["id"])):
			cards.append({"ref": "p:" + str(c["id"]), "x": randf_range(0.2, 0.8), "y": randf_range(0.25, 0.85), "by": "Faro"})
	var links := []
	for j in mini(2, e.size()):
		links.append({"id": "l%d" % j, "a": e[j]["from"], "b": e[j]["to"], "type": e[j]["type"], "evidence": clues[0]["id"] if j == 0 else null, "color": ["vermelho", "azul"][j % 2], "by": "Corvo"})
	cards.append({"ref": "c:" + str(clues[0]["id"]), "x": 0.5, "y": 0.12, "by": "Coruja"})
	var items := []
	for it in full_case.get("items", []).slice(0, 2):
		items.append(it["id"])
	return {
		"t": "state", "code": "4821", "phase": phase, "now": now, "endsAt": now + (12000.0 if phase == "briefing" else 540000.0),
		"startedAt": now, "settings": {"caseId": full_case["id"], "teamCount": 3, "penaltySec": 45},
		"teams": _teams(phase), "released": [], "me": {"id": "Corvo", "name": "Corvo", "team": "t1"},
		"clues": clues, "mine": [clues[1]["id"], clues[2]["id"]], "board": {"cards": cards, "links": links},
		"hotspots": [], "flags": {}, "items": items, "lockUntil": 0, "lastResult": null, "solved": false,
	}


func _host_state(phase: String) -> Dictionary:
	var s := _player_state(phase)
	s.erase("me")
	s["host"] = true
	s["cases"] = []
	for f in ["rumor_1017", "ninguem", "objeto_trocado"]:
		var p := ProjectSettings.globalize_path("res://").path_join("../server/cases/%s.json" % f)
		var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(p))
		s["cases"].append({"id": c["id"], "title": c["title"], "tagline": c["tagline"], "difficulty": c["difficulty"], "duration_sec": c["duration_sec"]})
	s["clues"] = full_case["clues"]
	s["boards"] = {"t1": s["board"], "t2": s["board"], "t3": {"cards": [], "links": []}}
	for t in s["teams"]:
		t["progress"] = [{"label": "Por onde passou", "status": "ok"}, {"label": "Quem espalhou", "status": "incompleto"}, {"label": "Culpado", "status": "errado"}]
	return s


func _apply(role: String, state: Dictionary) -> void:
	Net.role = role
	Net.code = "4821"
	Net.pid = "Corvo" if role == "player" else ""
	Net.host_secret = "x" if role == "host" else ""
	Net.my_name = "Corvo"
	Net.case_data = _public_case()
	Net.state = state
	main.forced = ""
	main._route()


func _run() -> void:
	# --- início
	Net.role = ""
	Net.code = ""
	main._route()
	await _shot("01_home")
	main.go_join()
	await _shot("02_join_codigo")
	var j: Node = main.current
	j.digits = "4821"
	j.step = 2
	j._build()
	await _shot("03_join_codinome")
	# --- aluno
	_apply("player", _player_state("lobby"))
	await _shot("04_lobby")
	_apply("player", _player_state("briefing"))
	await _wait(3.0)
	await _shot("05_briefing")
	_apply("player", _player_state("playing"))
	await _wait(1.5)
	await _shot("06_cena")
	var g: Node = main.current
	g._set_tab("pistas")
	await _shot("07_pistas")
	var kinds := {}
	for c in Net.state["clues"]:
		if not kinds.has(c["kind"]):
			kinds[c["kind"]] = c
	for k in kinds:
		g._open_clue(kinds[k])
		await _shot("08_pista_" + str(k))
		g._close_sheet()
	g._set_tab("quadro")
	await _wait(4.0)
	g.board.fit()
	await _shot("09_quadro")
	g.board.selected_ref = str(Net.state["board"]["cards"][0]["ref"])
	g._update_action_bar()
	await _shot("10_quadro_selecionado")
	g._open_palette()
	await _shot("11_paleta")
	g._close_sheet()
	g._on_link_tapped("l0")
	await _shot("12_fio")
	g._close_sheet()
	g._open_relation_picker(str(Net.state["board"]["links"][0]["a"]), str(Net.state["board"]["links"][0]["b"]))
	await _shot("13_tipo_ligacao")
	g._close_sheet()
	g._open_submit()
	await _shot("14_apresentar")
	g._close_sheet()
	g._show_result({"correct": false, "by": "Lince", "categories": [{"label": "Por onde passou", "status": "ok"}, {"label": "Quem espalhou", "status": "falta_prova"}, {"label": "Culpado", "status": "errado"}]})
	await _shot("15_resultado")
	g._close_sheet()
	# conversa com árvore
	var person := {}
	for c in full_case["cards"]:
		if c.get("talk", {}).has("tree"):
			person = c
			break
	if not person.is_empty():
		g._talk_to(str(person["id"]))
		await _wait(2.5)
		await _shot("16_conversa")
		var tv: Node = g.get_child(g.get_child_count() - 1)
		for i in 6:
			if tv.choices_box and tv.choices_box.visible:
				break
			tv._shown = 999.0
			tv._next()
			await _wait(0.4)
		await _shot("17_conversa_escolhas")
		tv.queue_free()
	# --- professor
	_apply("host", _host_state("lobby"))
	await _shot("18_prof_lobby")
	_apply("host", _host_state("playing"))
	await _shot("19_prof_rodada")
	# --- revelação
	Net.reveal_data = {"reveal": full_case["reveal"], "culprit": full_case["solution"].get("culprit"), "edges": full_case["solution"]["edges"],
		"categories": full_case["solution"]["categories"], "ranking": [
			{"place": 1, "id": "t2", "name": "Neblina", "color": "#6fd3ff", "solved": true, "timeSec": 412, "score": 650, "submissions": 2},
			{"place": 2, "id": "t1", "name": "Lanterna", "color": "#ffc83d", "solved": false, "timeSec": null, "score": 350, "submissions": 3},
			{"place": 3, "id": "t3", "name": "Néon", "color": "#ff6fae", "solved": false, "timeSec": null, "score": 100, "submissions": 1}]}
	_apply("player", _player_state("reveal"))
	await _shot("20_revelacao_placar")
	main.current._show("verdade")
	await _shot("21_revelacao_verdade")
	main.current._show("quadro")
	await _shot("22_revelacao_quadro")
