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
		cid = "cofre_formatura"
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
	var names := [["Corvo", "Maria Eduarda Santos", "Coruja", "Raposa"], ["Sombra", "Neblina", "Faro"], ["Lupa", "Gato Preto", "Trench", "Fumaça", "Morcego"]]
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
	cards.append({"ref": "c:" + str(clues[1]["id"]), "x": 0.2, "y": 0.9, "by": "Coruja"})
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
	var cdir := ProjectSettings.globalize_path("res://").path_join("../server/cases")
	for fn in DirAccess.get_files_at(cdir):
		if not fn.ends_with(".json"):
			continue
		var p := cdir.path_join(fn)
		var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(p))
		if str(c.get("mode", "multi")) == "solo":
			continue
		var cover := ""
		var people := 0
		for k in c["cards"]:
			if k["kind"] == "pessoa":
				people += 1
				if cover == "" and k["id"] != c["solution"]["culprit"]:
					cover = k["id"]
		s["cases"].append({"id": c["id"], "title": c["title"], "tagline": c["tagline"], "difficulty": c["difficulty"], "duration_sec": c["duration_sec"],
			"cover": cover, "people": people, "places": (c.get("locations", []) as Array).size()})
	s["clues"] = full_case["clues"]
	s["boards"] = {"t1": s["board"], "t2": s["board"], "t3": {"cards": [], "links": []}}
	var feed := []
	var now := Time.get_unix_time_from_system() * 1000.0
	var acts := [["t1", "Corvo", "Corvo achou uma pista: Quadro de avisos", "cena"], ["t2", "Sombra", "Sombra fez Caio contar: Depoimento do Caio", "conversa"],
		["t1", "Lince", "Lince ligou Caio contou para Duda", "quadro"], ["t3", "Lupa", "Caio se fechou com Lupa (escolha ruim)", "alerta"],
		["t2", "Faro", "Faro apresentou a teoria acusando Duda: CERTA", "acerto"], [null, null, "Nova pista liberada para todas as equipes: Print do grêmio", "sistema"],
		["t3", "Trench", "Trench pegou Carregador de celular (Mochila)", "cena"], [null, null, "Professor mandou dica para todos: \"Conversem!\"", "dica"],
		["t1", "Coruja", "Coruja fixou no quadro: Sala do diretor", "quadro"], ["t1", "Coruja", "Coruja ligou Lari esteve em Sala do diretor", "quadro"],
		["t1", "Corvo", "Corvo prendeu a prova: Relatório do cofre", "quadro"], ["t3", "Lupa", "Lupa propôs entregar o caso acusando Lari", "teoria"],
		["t2", "Faro", "Neblina entregou o caso: culpado CERTO, 2 de 3 partes provadas", "acerto"], ["t3", "Gato Preto", "Gato Preto quer continuar investigando (entrega cancelada)", "teoria"]]
	for i in acts.size():
		feed.append({"at": now - (acts.size() - i) * 40000.0, "team": acts[i][0], "who": acts[i][1], "text": acts[i][2], "kind": acts[i][3]})
	s["feed"] = feed
	s["insight"] = {}
	for t in s["teams"]:
		var mem := []
		var k := 0
		for pl in t["players"]:
			mem.append({"name": pl["name"], "online": k != 3, "idleSec": [12, 95, 260, 30, 400][k % 5], "actions": 5 + k})
			k += 1
		var cts := []
		var q := 0
		for cat in full_case["solution"]["categories"]:
			cts.append({"label": cat["label"], "status": ["ok", "incompleto", "falta_prova"][(q + k) % 3]})
			q += 1
		s["insight"][t["id"]] = {"edgesOk": 1 + k % 3, "edgesTotal": 3, "cluesFound": 4 + k, "cluesTotal": 8, "items": k % 2, "lockLeft": 0, "members": mem,
			"cats": cts, "finished": t["id"] == "t2", "voting": t["id"] == "t3", "culpritOk": true}
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
	var bs := _player_state("briefing")
	var rl := []
	var ri := 0
	for t in bs["teams"]:
		for pl in t["players"]:
			rl.append({"id": pl["name"], "name": pl["name"], "team": t["id"], "ready": ri % 3 != 1, "online": ri != 5})
			ri += 1
	bs["readyList"] = rl
	bs["countdown"] = false
	_apply("player", bs)
	await _wait(3.0)
	await _shot("05_briefing")
	var hb := _host_state("briefing")
	hb["readyList"] = rl
	hb["countdown"] = false
	_apply("host", hb)
	await _shot("05b_prof_chamada")
	_apply("player", _player_state("playing"))
	await _wait(1.5)
	await _shot("06_cena")
	main.current._open_map()
	await _shot("06b_mapa")
	if main.current.has_method("_confirm_exit"):
		main.current._confirm_exit()
		await _shot("06c_sair")
		for ch in main.current.get_children():
			if ch is CanvasLayer:
				ch.queue_free()
	main.current._close_sheet()
	var g: Node = main.current
	g._set_tab("pistas")
	await _shot("07_pistas")
	# todas as pistas do caso (não só uma por tipo): pega quebra de layout em qualquer uma
	var all_clues: Array = full_case["clues"]
	Net.state["clues"] = all_clues
	var n := 0
	for c in all_clues:
		g._open_clue(c)
		n += 1
		await _shot("08_pista_%02d_%s" % [n, str(c["kind"])])
		g._close_sheet()
	g._set_tab("quadro")
	await _wait(4.0)
	g.board.fit()
	await _shot("09_quadro")
	g.board.zoom = 0.85
	var lk: Dictionary = Net.state["board"]["links"][0]
	var kp: Vector2 = g.board._knot(lk)
	g.board.offset = g.board.size / 2.0 - kp * g.board.zoom
	g.board.queue_redraw()
	await _shot("09b_quadro_zoom")
	g._organize_board()
	await _wait(0.6)
	await _shot("09c_organizado")
	g.board.selected_ref = "c:" + str(Net.state["clues"][1]["id"])
	g._update_action_bar()
	g.board.queue_redraw()
	await _shot("09d_pista_selecionada")
	g._open_link_picker_for_clue(str(Net.state["clues"][1]["id"]))
	await _shot("09e_prender_em_fio")
	g._close_sheet()
	g.board.selected_ref = ""
	g._update_action_bar()
	g._board_tutorial()
	await _shot("09f_tutorial_quadro")
	g._close_sheet()
	g.board.selected_ref = str(Net.state["board"]["cards"][0]["ref"])
	g._update_action_bar()
	await _shot("10_quadro_selecionado")
	g._open_palette()
	await _shot("11_paleta")
	g._close_sheet()
	g._on_link_tapped("l0")
	await _shot("12_fio")
	g._close_sheet()
	await _shot("12c_fio_selecionado_quadro")
	var bd3: Dictionary = Net.state["board"]
	if not (bd3["links"] as Array).is_empty():
		var cl3: Array = (Net.state.get("clues", full_case["clues"]) as Array)
		bd3["links"][0]["proofs"] = [str(cl3[0]["id"]), str(cl3[1]["id"]), str(cl3[2]["id"])]
		bd3["links"][0]["evidence"] = str(cl3[0]["id"])
		g.board.set_data(bd3["cards"], bd3["links"])
		var kp3: Vector2 = g.board._knot(bd3["links"][0])
		g.board.zoom = 1.0
		g.board.offset = g.board.size / 2.0 - kp3 * g.board.zoom
		g.board.queue_redraw()
		await _shot("12e_tres_provas")
		g._on_link_tapped(str(bd3["links"][0]["id"]))
		await _shot("12f_fio_tres_provas")
		g._close_sheet()
	g._open_evidence_picker("l1")
	await _shot("12b_escolher_prova")
	g._close_sheet()
	g._open_story()
	await _wait(1.5)
	await _shot("12d_historia")
	g._close_sheet()
	g._open_relation_picker(str(Net.state["board"]["links"][0]["a"]), str(Net.state["board"]["links"][0]["b"]))
	await _shot("13_tipo_ligacao")
	g._close_sheet()
	var place := ""
	var someone := ""
	for c in full_case["cards"]:
		if c["kind"] == "lugar" and place == "":
			place = str(c["id"])
		if c["kind"] == "pessoa" and someone == "":
			someone = str(c["id"])
	if place != "":
		g._open_relation_picker(place, someone)
		await _shot("13b_lugar_pessoa")
	g._close_sheet()
	g._open_submit()
	await _shot("14_apresentar")
	g._close_sheet()
	Net.state["vote"] = {"culprit": str(full_case["solution"].get("culprit", "")), "by": "Lince", "mine": false, "yes": 1, "need": 3}
	g._open_vote()
	await _shot("14b_votacao")
	g._close_sheet()
	Net.state["vote"] = null
	var cats := []
	var stt := ["ok", "falta_prova", "incompleto", "ok"]
	var ci := 0
	for cat in full_case["solution"]["categories"]:
		cats.append({"id": cat["id"], "label": cat["label"], "status": stt[ci % 4]})
		ci += 1
	cats.append({"id": "culpado", "label": "Culpado", "status": "ok"})
	Net.state["finished"] = true
	Net.state["objectives"] = {"primary": true, "secDone": 2, "secTotal": cats.size() - 1}
	Net.state["teamsFinished"] = 1
	Net.state["teamsPlaying"] = 3
	g._show_result({"correct": false, "by": "Lince", "categories": cats})
	await _shot("15_resultado")
	g._close_sheet()
	Net.state["finished"] = false
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
	main.current._open_case_picker()
	await _shot("18b_prof_escolher_caso")
	Net.guide_data = full_case.duplicate(true)
	main.current._open_guide_overlay()
	await _wait(1.0)
	await _shot("18c_prof_guia_lobby")
	main.current.viewer_layer.get_children().map(func(c: Node) -> void: c.queue_free())
	_apply("host", _host_state("playing"))
	await _shot("19_prof_rodada")
	main.current.game_tab = "aovivo"
	main.current._feed_len = -1
	main.current._refresh_game()
	await _shot("19b_prof_aovivo")
	main.current.game_tab = "quadros"
	main.current._refresh_game()
	await _wait(3.0)
	await _shot("19c_prof_quadros")
	main.current._open_hint("t1")
	await _shot("19d_prof_dica")
	main.current.viewer_layer.get_children().map(func(c: Node) -> void: c.queue_free())
	Net.guide_data = full_case.duplicate(true)
	main.current.game_tab = "guia"
	main.current._guide_dirty = true
	main.current._refresh_game()
	await _shot("19e_prof_guia")
	# --- revelação
	Net.reveal_data = {"reveal": full_case["reveal"], "culprit": full_case["solution"].get("culprit"), "edges": full_case["solution"]["edges"],
		"categories": full_case["solution"]["categories"], "ranking": [
			{"place": 1, "id": "t2", "name": "Neblina", "color": "#6fd3ff", "solved": true, "timeSec": 412, "score": 650, "submissions": 2},
			{"place": 2, "id": "t1", "name": "Lanterna", "color": "#ffc83d", "solved": false, "timeSec": null, "score": 350, "submissions": 3},
			{"place": 3, "id": "t3", "name": "Néon", "color": "#ff6fae", "solved": false, "timeSec": null, "score": 100, "submissions": 1}]}
	var full_reveal: Dictionary = Net.reveal_data.duplicate(true)
	var cats_m := []
	var qq := 0
	for cat in full_case["solution"]["categories"]:
		cats_m.append({"id": cat["id"], "label": cat["label"], "status": "ok" if qq % 2 == 0 else "incompleto"})
		qq += 1
	Net.reveal_data = {"hidden": true, "ranking": full_reveal["ranking"], "mine": {"culpritOk": false, "objDone": 1, "objTotal": cats_m.size(), "categories": cats_m}}
	_apply("player", _player_state("reveal"))
	await _wait(1.0)
	await _shot("20a_errou_vitoria")
	for c in main.current.get_children():
		if c.get_script() == load("res://scripts/ui/victory.gd") or (c.get_child_count() > 0 and c.get_child(0).get_script() == load("res://scripts/ui/victory.gd")):
			c.queue_free()
	await _shot("20b_errou_resultado")
	Net.reveal_data = full_reveal
	_apply("player", _player_state("reveal"))
	await _shot("20_revelacao_placar")
	main.current._show("verdade")
	await _shot("21_revelacao_verdade")
	main.current._show("quadro")
	await _shot("22_revelacao_quadro")
