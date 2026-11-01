extends Node
## CENAS DO TRAILER. Uma cena por execução (TRAILER_CLIP), gravada com
##   godot --audio-driver Dummy --path . --resolution 1920x1080 --write-movie <saida>.avi --fixed-fps 30 res://tools_dev/trailer.tscn
## Ao começar a parte útil imprime "TRAILER_T0 <quadro>"; a montagem corta o que vem antes.
## Sem servidor: o estado é simulado (as mesmas receitas do ui_audit). Toques do dedo aparecem
## como círculos na tela (camada Tap).

const FPS := 30
const CaseScene := preload("res://scripts/scene3d/case_scene.gd")
const Victory := preload("res://scripts/ui/victory.gd")
const ClueView := preload("res://scripts/ui/clue_view.gd")

var clip := ""
var main: Node
var audit: Node
var g: Node
var tap_layer: TapLayer
var _t0_done := false
var full_case: Dictionary = {}


# ─────────────────────────────────────────────── dedo na tela
class TapLayer extends Control:
	var taps: Array = []      # [{p, t}]
	var finger := Vector2(-999, -999)
	var finger_on := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func tap(p: Vector2) -> void:
		taps.append({"p": p, "t": 0.0})

	func _process(dt: float) -> void:
		for t in taps:
			t["t"] = float(t["t"]) + dt
		taps = taps.filter(func(t: Dictionary) -> bool: return float(t["t"]) < 0.6)
		queue_redraw()

	func _draw() -> void:
		var s := get_viewport_rect().size.y / 1280.0
		for t in taps:
			var k := float(t["t"]) / 0.6
			var p: Vector2 = t["p"]
			draw_circle(p, 34.0 * s * (1.0 - k * 0.3), Color(1, 1, 1, 0.45 * (1.0 - k)))
			draw_arc(p, (34.0 + 70.0 * k) * s, 0, TAU, 48, Color(1, 0.85, 0.3, 1.0 - k), 5.0 * s, true)
		if finger_on:
			draw_circle(finger, 30.0 * s, Color(1, 1, 1, 0.42))
			draw_arc(finger, 34.0 * s, 0, TAU, 40, Color(1, 0.85, 0.3, 0.9), 4.0 * s, true)


func _ready() -> void:
	clip = OS.get_environment("TRAILER_CLIP")
	audit = load("res://tools_dev/ui_audit.gd").new()
	var cid := OS.get_environment("TRAILER_CASE")
	if cid == "":
		cid = "cofre_formatura"
	var path := ProjectSettings.globalize_path("res://").path_join("../server/cases/%s.json" % cid)
	full_case = JSON.parse_string(FileAccess.get_file_as_string(path))
	audit.full_case = full_case
	var cl := CanvasLayer.new()
	cl.layer = 120
	add_child(cl)
	tap_layer = TapLayer.new()
	cl.add_child(tap_layer)
	_run.call_deferred()


func _run() -> void:
	match clip:
		"room": await _room(OS.get_environment("TRAILER_ROOM"))
		"explore": await _explore()
		"talk": await _talk()
		"duo": await _duo()
		"board": await _board()
		"host": await _host()
		"clues": await _clues()
		"vote": await _vote()
		"victory": await _victory()
		"phone_scene": await _phone_scene()
		"faces": await _faces(OS.get_environment("TRAILER_WHO"))
		_: print("TRAILER_ABORT clipe desconhecido ", clip)
	print("TRAILER_DONE ", clip)
	get_tree().quit()


## faixa de passos do quadro sempre fechada no trailer (a cena mostra o quadro limpo)
func _process(_dt: float) -> void:
	if g != null and is_instance_valid(g) and g.get("guide") != null and is_instance_valid(g.guide):
		g.guide.visible = false


func _secs(s: float) -> void:
	for _i in int(round(s * FPS)):
		await get_tree().process_frame


func _t0() -> void:
	if not _t0_done:
		_t0_done = true
		print("TRAILER_T0 ", Engine.get_frames_drawn())


func _start_main() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	move_child(main, 0)
	audit.main = main
	await _secs(1.0)


func _state(phase := "playing") -> Dictionary:
	var st: Dictionary = audit._player_state(phase)
	st["clues"] = full_case["clues"]
	st["mine"] = []
	st["hotspots"] = []
	st["flags"] = {}
	st["me"] = {"id": "Maria", "name": "Maria", "team": "t1"}
	return st


func _play_game(st: Dictionary) -> void:
	audit._apply("player", st)
	Net.my_name = "Maria"
	await _secs(1.2)
	g = main.current
	# dicas de primeira vez fora (o trailer mostra o jogo andando): tutorial do quadro e faixa de guia
	g._board_tutorial_shown = true
	g._guide_closed = true
	g._close_sheet()
	if g.get("scene_hint") and is_instance_valid(g.scene_hint):
		g.scene_hint.visible = false
	for ch in g.get_children():
		if ch is CanvasLayer:
			ch.queue_free()


## Câmera da cena 3D conduzida pelo roteiro: giro (yaw), inclinação e aproximação suave.
func _sweep(sc: Node, dur: float, yaw_a: float, yaw_b: float, push := 0.0, pitch_a := 0.0, pitch_b := 0.0) -> void:
	var cam: Camera3D = sc.cam
	var base: Vector3 = cam.position
	var n := int(round(dur * FPS))
	for i in n:
		var u := float(i) / maxf(1.0, n - 1)
		var e := u * u * (3.0 - 2.0 * u)
		sc._yaw = lerpf(yaw_a, yaw_b, e)
		sc._pitch = lerpf(pitch_a, pitch_b, e)
		sc._vel = Vector2.ZERO
		if push != 0.0:
			cam.position = base + cam.transform.basis.z * (-push * e)
		await get_tree().process_frame


func _ring_screen(sc: Node, hs_id: String) -> Vector2:
	for gl in sc._glows:
		if str(gl["id"]) == hs_id:
			var p: Vector2 = sc.cam.unproject_position((gl["ring"] as Node3D).global_position)
			return p
	return Vector2(-1, -1)


func _person_screen(sc: Node, pid: String) -> Vector2:
	if sc._talkers.has(pid):
		var ring: Node3D = sc._talkers[pid]["ring"]
		return sc.cam.unproject_position(ring.global_position + Vector3(0, 1.0, 0))
	return Vector2(-1, -1)


func _tap_at(p: Vector2) -> void:
	tap_layer.tap(p)


func _center_of(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


# ─────────────────────────────────────────────── 1) cômodos em 3D, câmera girando
func _room(room: String) -> void:
	var people := []
	var spots := {
		"corredor": ["caio", "rafa", "bia"], "biblioteca": ["joana", "lari", "bia"], "sala_diretor": ["otavio", "lari"],
		"cantina": ["cida", "bia", "caio"], "sala_professores": ["jorge", "rafa"], "teatro": ["caio", "lari", "rafa"],
		"laboratorio": ["joana", "bia"], "quadra": ["rafa", "caio", "lari"], "fachada": ["otavio", "jorge", "cida"],
		"patio": ["bia", "caio", "rafa"], "sala_aula": ["lari", "caio", "joana"], "sala_musica": ["rafa", "bia"], "deposito": ["jorge"]}
	for pid in spots.get(room, []):
		for c in full_case["cards"]:
			if c["id"] == pid:
				people.append(c)
	var hs := []
	for h in full_case.get("hotspots", []):
		hs.append({"id": h["id"], "object": h["object"], "label": h.get("label", "")})
	var sc := CaseScene.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	move_child(holder, 0)
	holder.add_child(sc)
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.setup(room, hs, {}, people)
	await _secs(1.5)
	var lim: float = sc._yaw_limit
	var dir := 1.0 if hash(room) % 2 == 0 else -1.0
	_t0()
	await _sweep(sc, float(OS.get_environment("TRAILER_SECONDS")) if OS.get_environment("TRAILER_SECONDS") != "" else 5.0,
		-lim * 0.95 * dir, lim * 0.95 * dir, 0.9, 0.04, -0.06)


# ─────────────────────────────────────────────── 2) explorar: gira, toca no brilho, pista
func _explore() -> void:
	await _start_main()
	var st := _state()
	await _play_game(st)
	g._load_location("sala_diretor")
	await _secs(1.5)
	var sc: Node = g.scene3d
	var lim: float = sc._yaw_limit
	_t0()
	await _sweep(sc, 2.2, -lim * 0.9, lim * 0.3, 0.5)
	# toca no anel da pista do cofre
	var sp := _ring_screen(sc, "hs_cofre")
	var gp: Vector2 = sc.get_global_transform() * sp
	_tap_at(gp)
	sc._tap(sp)
	await _secs(1.4)
	for c in full_case["clues"]:
		if c["id"] == "c_log_cofre":
			g._open_clue(c)
	await _secs(2.6)
	g._close_sheet()
	await _secs(0.3)
	sp = _ring_screen(sc, "hs_gaveta")
	if sp.x > 0:
		_tap_at(sc.get_global_transform() * sp)
		sc._tap(sp)
	await _secs(1.6)


# ─────────────────────────────────────────────── 3) interrogatório: escolha, prova, contradição
func _talk_common(pid: String, flags: Dictionary) -> Node:
	await _start_main()
	var st := _state()
	st["flags"] = flags
	await _play_game(st)
	g._load_location("corredor")
	await _secs(1.0)
	var sc: Node = g.scene3d
	_t0()
	var lim: float = sc._yaw_limit
	await _sweep(sc, 1.2, lim * 0.4, 0.0, 0.3)
	var pp := _person_screen(sc, pid)
	if pp.x > 0:
		_tap_at(sc.get_global_transform() * pp)
	await _secs(0.25)
	g._talk_to(pid)
	await _secs(0.2)
	return g.get_child(g.get_child_count() - 1)


func _skip_to_choices(tv: Node, read_s: float) -> void:
	for i in 8:
		if tv.choices_box and tv.choices_box.visible:
			return
		await _secs(read_s)
		if tv.choices_box and tv.choices_box.visible:
			return
		tv._shown = 999.0
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = tv.get_global_rect().get_center()
		_tap_at(tv.get_global_rect().get_center() + Vector2(0, -120))
		tv._next()


func _press_choice(tv: Node, contains: String) -> void:
	for b in tv.choices_box.get_children():
		if b is Button and (b as Button).text.findn(contains) >= 0:
			_tap_at(_center_of(b))
			await _secs(0.35)
			(b as Button).pressed.emit()
			return


func _talk() -> void:
	var tv: Node = await _talk_common("rafa", {})
	await _skip_to_choices(tv, 2.6)
	await _secs(1.6)
	await _press_choice(tv, "câmera")
	await _secs(3.0)
	tv._shown = 999.0
	_tap_at(tv.get_global_rect().get_center() + Vector2(0, -120))
	tv._next()
	await _secs(3.2)


func _duo() -> void:
	var tv: Node = await _talk_common("caio", {"rafa_falou": true})
	for i in 3:
		await _secs(2.3)
		tv._shown = 999.0
		_tap_at(tv.get_global_rect().get_center() + Vector2(0, -120))
		tv._next()
	await _secs(2.0)


# ─────────────────────────────────────────────── 4) o quadro: ligar, provar, marcar, panorama
var _cards: Array = []
var _links: Array = []


func _bset() -> void:
	Net.state["board"] = {"cards": _cards, "links": _links}
	g.board.set_data(_cards, _links)


func _cam_to(bp: Vector2, z: float, dur: float) -> void:
	var b: Control = g.board
	var z0: float = b.zoom
	var o0: Vector2 = b.offset
	var n := int(round(dur * FPS))
	for i in n:
		var u := float(i + 1) / n
		var e := u * u * (3.0 - 2.0 * u)
		var zz := lerpf(z0, z, e)
		var target_o: Vector2 = b.size / 2.0 - bp * zz
		b.zoom = zz
		b.offset = o0.lerp(target_o, e)
		b.queue_redraw()
		await get_tree().process_frame


func _card_screen(ref: String) -> Vector2:
	var b: Control = g.board
	for c in _cards:
		if c["ref"] == ref:
			var bp: Vector2 = Vector2(c["x"], c["y"]) * b.BOARD
			return b.get_global_transform() * (b.offset + bp * b.zoom)
	return Vector2.ZERO


func _bp(ref: String) -> Vector2:
	for c in _cards:
		if c["ref"] == ref:
			return Vector2(c["x"], c["y"]) * g.board.BOARD
	return Vector2.ZERO


func _link_step(a: String, b: String, type: String, color: String, id: String, focus_z: float) -> void:
	_cam_to((_bp("p:" + a) + _bp("p:" + b)) / 2.0, focus_z, 0.6)
	_tap_at(_card_screen("p:" + a))
	g.board.selected_ref = "p:" + a
	g._update_action_bar()
	await _secs(0.5)
	g.board.selected_ref = ""
	g.board.link_from = "p:" + a
	g.link_banner.visible = true
	await _secs(1.1)
	_tap_at(_card_screen("p:" + b))
	await _secs(0.2)
	g.board.link_from = ""
	g.link_banner.visible = false
	_links.append({"id": id, "a": a, "b": b, "type": type, "color": color, "proofs": [], "evidence": null})
	_bset()
	await _secs(0.7)


func _proof_step(link_id: String, clue: String) -> void:
	_tap_at(_card_screen("c:" + clue))
	await _secs(0.25)
	for l in _links:
		if l["id"] == link_id:
			var pr: Array = l["proofs"]
			pr.append(clue)
			l["evidence"] = pr[0]
	_bset()
	await _secs(0.55)


func _board_state() -> void:
	_cards = [
		{"ref": "p:caio", "x": 0.2, "y": 0.26}, {"ref": "p:rafa", "x": 0.78, "y": 0.24}, {"ref": "p:jorge", "x": 0.5, "y": 0.12},
		{"ref": "p:bia", "x": 0.16, "y": 0.74}, {"ref": "p:lari", "x": 0.5, "y": 0.86}, {"ref": "p:cantina", "x": 0.3, "y": 0.5},
		{"ref": "p:sala_professores", "x": 0.68, "y": 0.52}, {"ref": "p:alarme", "x": 0.86, "y": 0.78},
		{"ref": "c:c_dep_caio", "x": 0.06, "y": 0.44}, {"ref": "c:c_chat_formatura", "x": 0.08, "y": 0.94},
		{"ref": "c:c_camera", "x": 0.94, "y": 0.46}, {"ref": "c:c_armario_cel", "x": 0.95, "y": 0.96},
		{"ref": "c:c_dm_bia_lari", "x": 0.3, "y": 0.96}]
	_links = []


func _board() -> void:
	await _start_main()
	var st := _state()
	_board_state()
	st["board"] = {"cards": _cards, "links": _links}
	await _play_game(st)
	g._set_tab("quadro")
	await _secs(1.0)
	_bset()
	g.board.fit()
	await _secs(0.4)
	var z_fit: float = g.board.zoom
	_t0()
	await _cam_to(g.board.BOARD * 0.5, z_fit * 1.12, 1.0)
	await _link_step("caio", "cantina", "estava", "azul", "l1", z_fit * 1.6)
	await _proof_step("l1", "c_dep_caio")
	await _proof_step("l1", "c_chat_formatura")
	await _link_step("rafa", "sala_professores", "estava", "vermelho", "l2", z_fit * 1.6)
	await _proof_step("l2", "c_camera")
	await _proof_step("l2", "c_armario_cel")
	await _link_step("alarme", "sala_professores", "g_aconteceu", "rosa", "l3", z_fit * 1.5)
	await _link_step("bia", "lari", "g_amigo", "amarelo", "l4", z_fit * 1.5)
	await _proof_step("l4", "c_dm_bia_lari")
	# marcas nas pessoas
	_cam_to((_bp("p:caio") + _bp("p:rafa")) / 2.0, z_fit * 1.25, 0.6)
	for c in _cards:
		if c["ref"] == "p:rafa":
			c["tag"] = "mentiu"
	_tap_at(_card_screen("p:rafa"))
	_bset()
	await _secs(0.6)
	for c in _cards:
		if c["ref"] == "p:caio":
			c["tag"] = "alibi"
	_tap_at(_card_screen("p:caio"))
	_bset()
	await _secs(0.8)
	# panorama inteiro
	await _cam_to(g.board.BOARD * 0.5, z_fit * 0.98, 1.2)
	await _secs(1.0)
	g._open_story()
	await _secs(3.2)


# ─────────────────────────────────────────────── 5) professor ao vivo (PC)
func _host() -> void:
	await _start_main()
	var hs: Dictionary = audit._host_state("playing")
	audit._apply("host", hs)
	await _secs(1.2)
	var h: Node = main.current
	h.game_tab = "aovivo"
	h._feed_len = -1
	h._refresh_game()
	await _secs(0.6)
	_t0()
	await _secs(2.4)
	for b in h.tab_btns:
		if b == "equipes":
			_tap_at(_center_of(h.tab_btns[b]))
	await _secs(0.3)
	h.game_tab = "equipes"
	h._feed_len = -1
	h._refresh_game()
	await _secs(2.6)


# ─────────────────────────────────────────────── celular: pistas com imagem
func _clues() -> void:
	await _start_main()
	var st := _state()
	await _play_game(st)
	g._set_tab("pistas")
	await _secs(0.8)
	_t0()
	await _secs(1.0)
	var picks := []
	for c in full_case["clues"]:
		if c["id"] == "c_camera":
			picks.append(c)
	for cid in ["conta_sem_rosto", "solo_bilhete"]:
		var p := ProjectSettings.globalize_path("res://").path_join("../server/cases/%s.json" % cid)
		var other: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(p))
		for c in other["clues"]:
			var v: Dictionary = c.get("visual", {}) if c.get("visual") is Dictionary else {}
			if str(v.get("art", "")) in ["pix", "ransom"]:
				picks.append(c)
				break
	for c in picks:
		_tap_at(Vector2(360, 520))
		g._open_clue(c)
		await _secs(1.9)
		g._close_sheet()
		await _secs(0.15)


# ─────────────────────────────────────────────── celular: votação da equipe e resultado
func _vote() -> void:
	await _start_main()
	var st := _state()
	_board_state()
	st["board"] = {"cards": _cards, "links": _links}
	await _play_game(st)
	g._set_tab("quadro")
	await _secs(0.5)
	Net.state["vote"] = {"culprit": "", "by": "Pedro", "mine": false, "yes": 2, "need": 4}
	g._open_vote()
	_t0()
	await _secs(1.6)
	Net.state["vote"]["yes"] = 3
	g._open_vote()
	await _secs(1.0)
	for b in g.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("SIM, ENTREGAR") and (b as Button).is_visible_in_tree():
			_tap_at(_center_of(b))
	await _secs(0.3)
	Net.state["vote"]["yes"] = 4
	Net.state["vote"]["mine"] = true
	g._open_vote()
	await _secs(0.8)
	g._close_sheet()
	Net.state["vote"] = null
	var cats := []
	for cat in full_case["solution"]["categories"]:
		cats.append({"id": cat["id"], "label": cat["label"], "status": "ok"})
	Net.state["finished"] = true
	Net.state["objectives"] = {"primary": true, "secDone": cats.size(), "secTotal": cats.size()}
	Net.state["teamsFinished"] = 1
	Net.state["teamsPlaying"] = 3
	g._show_result({"correct": true, "by": "Maria", "categories": cats})
	await _secs(2.6)


func _victory() -> void:
	await _start_main()
	var st := _state()
	_board_state()
	_links = [
		{"id": "l1", "a": "caio", "b": "cantina", "type": "estava", "color": "azul", "proofs": ["c_dep_caio", "c_chat_formatura"], "evidence": "c_dep_caio"},
		{"id": "l2", "a": "rafa", "b": "sala_professores", "type": "estava", "color": "vermelho", "proofs": ["c_camera", "c_armario_cel"], "evidence": "c_camera"},
		{"id": "l3", "a": "alarme", "b": "sala_professores", "type": "g_aconteceu", "color": "rosa", "proofs": [], "evidence": null},
		{"id": "l4", "a": "bia", "b": "lari", "type": "g_amigo", "color": "amarelo", "proofs": ["c_dm_bia_lari"], "evidence": "c_dm_bia_lari"}]
	st["board"] = {"cards": _cards, "links": _links}
	await _play_game(st)
	var vic := Victory.new()
	vic.solved = true
	vic.time_sec = 754
	vic.place = 1
	vic.stars = 3
	vic.case_title = str(full_case["title"])
	vic.culprit_id = ""
	vic.codename = "Maria"
	vic.culprit_ok = true
	vic.team_name = "Lanterna"
	vic.team_color = UI.YELLOW
	var cats := []
	for cat in full_case["solution"]["categories"]:
		cats.append({"id": cat["id"], "label": cat["label"], "status": "ok"})
	vic.categories = cats
	vic.obj_line = "%d de %d provas" % [cats.size(), cats.size()]
	g.add_child(UI.full(vic))
	_t0()
	await _secs(4.0)


# ─────────────────────────────────────────────── celular: cena 3D com dedo girando
func _phone_scene() -> void:
	await _start_main()
	var st := _state()
	await _play_game(st)
	g._load_location(OS.get_environment("TRAILER_ROOM") if OS.get_environment("TRAILER_ROOM") != "" else "cantina")
	await _secs(1.2)
	var sc: Node = g.scene3d
	var lim: float = sc._yaw_limit
	_t0()
	tap_layer.finger_on = true
	var n := int(3.4 * FPS)
	for i in n:
		var u := float(i) / (n - 1)
		var e := u * u * (3.0 - 2.0 * u)
		sc._yaw = lerpf(-lim, lim, e)
		sc._vel = Vector2.ZERO
		tap_layer.finger = Vector2(lerpf(560, 160, e), 700 + sin(u * PI) * 40)
		await get_tree().process_frame
	tap_layer.finger_on = false
	await _secs(1.0)


# ─────────────────────────────────────────────── expressões: o rosto muda a cada fala
func _faces(who: String) -> void:
	await _start_main()
	var st := _state()
	await _play_game(st)
	var card: Dictionary = Net.card_by_id(who if who != "" else "rafa")
	var seqs := {
		"rafa": [["Eu? Na escola à noite? Imagina.", "neutro", "dando_de_ombros"], ["Tá bom, tá bom... era eu no print.", "nervoso", "nervoso"],
			["Mas eu NÃO peguei o dinheiro!", "bravo", "negando"], ["Espera. Alguém mais tinha a chave?", "surpreso", "pensando"]],
		"jorge": [["Eu tava em casa dormindo, rapaz.", "desconfiado", "negando"], ["Minhas chaves! Onde você achou?", "surpreso", "apontando"],
			["Pois é... perdi mesmo. Que vergonha.", "triste", "pensando"], ["Agora sim a gente conversa!", "feliz", "rindo"]],
		"bia": [["Eu não sei de nada, tá?", "desconfiado", "negando"], ["Quem te mostrou essa mensagem?!", "bravo", "apontando"],
			["Ela me pediu pra não contar...", "triste", "pensando"], ["Ok. Eu conto tudo.", "nervoso", "nervoso"]]}
	var seq: Array = seqs.get(str(card.get("id", "rafa")), seqs["rafa"])
	var lines := []
	for l in seq:
		lines.append({"text": l[0], "expr": l[1], "anim": l[2]})
	g._open_talk(card, lines, "INTERROGATÓRIO")
	var tv: Node = g.get_child(g.get_child_count() - 1)
	await _secs(1.0)
	_t0()
	for i in lines.size():
		await _secs(1.9)
		if i < lines.size() - 1:
			tv._shown = 999.0
			tv._next()
	await _secs(0.4)
