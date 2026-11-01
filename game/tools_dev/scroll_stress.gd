extends Node
## Sonda: a tela do professor rola enquanto os alunos mandam ações sem parar?
## A cada 150 ms chega um estado novo (como no servidor) durante o arrasto e depois dele.
var main: Node
var audit: Node
var n := 0


func _push() -> void:
	n += 1
	var st: Dictionary = Net.state
	(st["feed"] as Array).append({"at": Time.get_unix_time_from_system() * 1000.0, "team": "t1", "who": "Corvo", "text": "Corvo achou uma pista %d" % n, "kind": "cena"})
	for tid in st["insight"]:
		st["insight"][tid]["members"][0]["idleSec"] = n
	st["insight"]["t1"]["cluesFound"] = 4 + n
	main.current.refresh()


func _ready() -> void:
	audit = load("res://tools_dev/ui_audit.gd").new()
	var path := ProjectSettings.globalize_path("res://").path_join("../server/cases/cofre_formatura.json")
	audit.full_case = JSON.parse_string(FileAccess.get_file_as_string(path))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	audit.main = main
	await get_tree().create_timer(1.0).timeout
	var hs: Dictionary = audit._host_state("playing")
	# muitas ações para a lista ficar comprida
	for i in 30:
		(hs["feed"] as Array).append({"at": 0.0, "team": "t2", "who": "Faro", "text": "Faro ligou Caio estava em Cantina %d" % i, "kind": "quadro"})
	audit._apply("host", hs)
	await get_tree().create_timer(1.0).timeout
	var host: Node = main.current
	var bad := 0
	for tab in ["equipes", "aovivo"]:
		host.game_tab = tab
		host._feed_len = -1
		host._refresh_game()
		await get_tree().create_timer(0.8).timeout
		var sc: ScrollContainer = host.page_scroll
		sc.scroll_vertical = 0
		await get_tree().create_timer(0.3).timeout
		var at := get_viewport().get_final_transform() * (sc.get_global_rect().get_center() + Vector2(0, 200))
		var t := InputEventScreenTouch.new()
		t.pressed = true; t.position = at
		Input.parse_input_event(t)
		var vals := []
		var drops := 0
		var prev := 0
		for i in 40:
			var d := InputEventScreenDrag.new()
			d.position = at - Vector2(0, 12 * (i + 1)); d.relative = Vector2(0, -12)
			Input.parse_input_event(d)
			if i % 3 == 0:
				_push()
			await get_tree().create_timer(0.05).timeout
			var v: int = sc.scroll_vertical
			if v < prev - 2:
				drops += 1
			prev = v
			vals.append(v)
		t = InputEventScreenTouch.new(); t.pressed = false; t.position = at - Vector2(0, 480)
		Input.parse_input_event(t)
		await get_tree().create_timer(0.6).timeout
		var rest: int = sc.scroll_vertical
		var after := []
		var rebuilds := 0
		for i in 30:
			var first: Object = host.page_box.get_child(0) if host.page_box.get_child_count() > 0 else null
			_push()
			await get_tree().process_frame
			var now_first: Object = host.page_box.get_child(0) if host.page_box.get_child_count() > 0 else null
			if now_first != first:
				rebuilds += 1
			await get_tree().create_timer(0.15).timeout
			after.append(sc.scroll_vertical)
		var moved_after := 0
		var fb: Object = host.page_box.get_child(0) if host.page_box.get_child_count() > 0 else null
		await get_tree().create_timer(4.0).timeout
		var fa: Object = host.page_box.get_child(0) if host.page_box.get_child_count() > 0 else null
		print("  novidades apareceram depois de soltar: ", fa != fb, " | rolagem mantida: ", sc.scroll_vertical)
		if fa == fb:
			bad += 1
		var t0 := Time.get_ticks_usec()
		host._do_refresh_game()
		var cost := (Time.get_ticks_usec() - t0) / 1000.0
		print("  custo de refazer %s: %.1f ms | refeitas em 30 estados: %d" % [tab, cost, rebuilds])
		for v in after:
			if absi(int(v) - rest) > 4:
				moved_after += 1
		print("ESTRESSE %s: arrasto %d -> %d, quedas=%d | parado em %d, pulos depois=%d (min %d max %d) max=%d" % [tab, vals[0], vals[-1], drops, rest, moved_after, after.min(), after.max(), int(sc.get_v_scroll_bar().max_value)])
		var lim := int(sc.get_v_scroll_bar().max_value - sc.get_v_scroll_bar().page)
		print("  fim da lista em ", lim)
		if drops > 0 or moved_after > 0 or vals[-1] < mini(300, lim - 4):
			bad += 1
	print("RESULTADO ", "OK" if bad == 0 else "FALHOU")
	get_tree().quit()
