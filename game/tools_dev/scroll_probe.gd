extends Node
## Sonda: a lista do professor rola? Manda roda do mouse e arrasto de toque e mede o scroll.
var main: Node

func _ready() -> void:
	var audit: Node = load("res://tools_dev/ui_audit.gd").new()
	audit.dir = ""
	var path := ProjectSettings.globalize_path("res://").path_join("../server/cases/cofre_formatura.json")
	audit.full_case = JSON.parse_string(FileAccess.get_file_as_string(path))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	audit.main = main
	await get_tree().create_timer(1.0).timeout
	audit._apply("host", audit._host_state("playing"))
	await get_tree().create_timer(1.0).timeout
	var host: Node = main.current
	for tab in ["aovivo", "guia"]:
		host.game_tab = tab
		host._feed_len = -1
		host._guide_dirty = true
		Net.guide_data = audit.full_case.duplicate(true)
		host._refresh_game()
		await get_tree().create_timer(0.8).timeout
		var sc: ScrollContainer = host.page_scroll
		var before := sc.scroll_vertical
		var at := get_viewport().get_final_transform() * sc.get_global_rect().get_center()
		for i in 8:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
			ev.pressed = true
			ev.position = at
			ev.global_position = at
			Input.parse_input_event(ev)
			await get_tree().process_frame
		await get_tree().create_timer(0.3).timeout
		var after_wheel := sc.scroll_vertical
		sc.scroll_vertical = 0
		await get_tree().create_timer(0.3).timeout
		# arrasto de toque (dedo subindo)
		var t := InputEventScreenTouch.new()
		t.pressed = true; t.position = at
		Input.parse_input_event(t)
		for i in 10:
			var d := InputEventScreenDrag.new()
			d.position = at - Vector2(0, 30 * (i + 1)); d.relative = Vector2(0, -30)
			Input.parse_input_event(d)
			await get_tree().process_frame
		t = InputEventScreenTouch.new(); t.pressed = false; t.position = at - Vector2(0, 300)
		Input.parse_input_event(t)
		await get_tree().create_timer(0.5).timeout
		var after_touch := sc.scroll_vertical
		var keepv := sc.scroll_vertical
		sc.scroll_vertical = 400
		await get_tree().process_frame
		await get_tree().process_frame
		var forced := sc.scroll_vertical
		await get_tree().create_timer(1.2).timeout
		print("  filtro=%d forcado_400 -> %d -> depois de 1,2s %d" % [sc.mouse_filter, forced, sc.scroll_vertical])
		var hovered := get_viewport().gui_get_hovered_control()
		print("ROLAGEM %s antes=%d roda=%d toque=%d max=%d  sob_o_mouse=%s" % [tab, before, after_wheel, after_touch, int(sc.get_v_scroll_bar().max_value), hovered.get_path() if hovered else "nada"])
	get_tree().quit()
