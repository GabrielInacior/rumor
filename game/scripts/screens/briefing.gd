extends Control
## Abertura do caso: título, narração noir em máquina de escrever e contagem regressiva.

var text_l: Label
var count_l: Label
var ready_btn: Button
var wait_l: Label
var chips: HFlowContainer
var full_text := ""
var shown := 0.0


func _ready() -> void:
	var m := UI.margin(36, 60, 36)
	add_child(UI.full(m))
	var outer := UI.vbox(12)
	m.add_child(outer)
	# sair sempre à mão, também na abertura
	var toprow := UI.hbox(10)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toprow.add_child(sp)
	var exit_btn := UI.button("SAIR", "ghost", 64)
	exit_btn.custom_minimum_size.x = 120
	exit_btn.pressed.connect(func() -> void:
		if Net.state.get("solo", false):
			UI.confirm(self, "SAIR DO CASO?", "Você volta para a lista de casos.", "SAIR PARA A LISTA", func() -> void: get_meta("main").leave_to_solo())
		else:
			UI.confirm(self, "SAIR DA SALA?", "Para voltar, entre de novo com o mesmo código e o mesmo nome.", "SAIR DA SALA", func() -> void: get_meta("main").go_home()))
	toprow.add_child(exit_btn)
	outer.add_child(toprow)
	# tudo que é leitura rola junto (no celular em pé nada fica espremido numa rolagem interna)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(sc)
	var v := UI.vbox(18)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var c := Net.case_data
	var diff := int(c.get("difficulty", 1))
	v.add_child(UI.label("CASO  ·  " + ["", "FÁCIL", "MÉDIO", "DIFÍCIL"][clampi(diff, 1, 3)], 26, UI.MIST, "type"))
	var t := UI.title(str(c.get("title", "")).to_upper(), 70, UI.YELLOW)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	v.add_child(UI.label(UI.strip_emoji(str(c.get("tagline", ""))), 28, UI.PINK, "bold"))
	# a narração vem numa folha de caderno, do tamanho do texto
	var p := Paper.make("notebook", true)
	text_l = UI.label("", 28, Color("#1b2140"), "type")
	text_l.add_theme_constant_override("line_spacing", 12)
	p.add_child(text_l)
	var pm := UI.margin(4, 14, 10)
	pm.add_child(p)
	v.add_child(pm)
	full_text = UI.strip_emoji(str(c.get("briefing", "")))
	text_l.text = full_text
	text_l.visible_characters = 0
	var goal := UI.panel(Color(UI.NIGHT, 0.85), Color(UI.YELLOW, 0.7), 16)
	goal.add_child(UI.label("OBJETIVO  " + str(c.get("goal", "")), 26, UI.YELLOW, "bold"))
	v.add_child(goal)
	# como jogar em 3 passos, para quem nunca jogou nada parecido
	for st in [["1", "EXPLORE", "Toque no que brilha nas cenas e troque de lugar no topo."], ["2", "CONVERSE", "Toque nas pessoas. Mostre pistas para elas abrirem o jogo."], ["3", "LIGUE", "Monte o quadro com fios e provas, aponte o culpado e entregue o caso."]]:
		var row := UI.hbox(14)
		var num := UI.title(st[0], 56, UI.YELLOW)
		num.custom_minimum_size.x = 44
		row.add_child(num)
		var sv := UI.vbox(0)
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sv.add_child(UI.title(st[1], 34, UI.PAPER))
		sv.add_child(UI.label(st[2], 22, UI.MIST))
		row.add_child(sv)
		v.add_child(row)
	# rodapé: PRONTO + quem falta (a contagem só começa com todos prontos)
	chips = HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	outer.add_child(chips)
	wait_l = UI.label("", 22, UI.MIST, "bold")
	wait_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(wait_l)
	count_l = UI.title("", 96, UI.PAPER)
	count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_l.visible = false
	outer.add_child(count_l)
	ready_btn = UI.button("ESTOU PRONTO", "primary", 104)
	ready_btn.add_theme_font_size_override("font_size", 46)
	ready_btn.pressed.connect(func() -> void:
		var me_ready := _me_ready()
		Net.send({"t": "ready", "ready": not me_ready})
		Sfx.play("card_pin" if not me_ready else "ui_tap"))
	outer.add_child(ready_btn)
	refresh()
	Sfx.set_ambience("ambience_rain_loop")


func _process(dt: float) -> void:
	var before := int(shown)
	shown = minf(full_text.length(), shown + dt * 38.0)
	text_l.visible_characters = int(shown)
	if int(shown) != before and int(shown) % 3 == 0:
		Sfx.play("timer_tick", -18.0, randf_range(1.6, 2.0))
	if Net.state.get("countdown", false):
		var s := Net.seconds_left()
		count_l.text = str(s) if s > 0 else "VAI!"


func _me_ready() -> bool:
	var me := str(Net.state.get("me", {}).get("id", Net.pid))
	for r in Net.state.get("readyList", []) if Net.state.get("readyList") is Array else []:
		if str(r["id"]) == me:
			return bool(r["ready"])
	return false


func refresh() -> void:
	if ready_btn == null:
		return
	var lst: Array = Net.state.get("readyList", []) if Net.state.get("readyList") is Array else []
	var counting := bool(Net.state.get("countdown", false))
	count_l.visible = counting
	ready_btn.visible = not counting
	var mine := _me_ready()
	ready_btn.text = "PRONTO!  (toque para desfazer)" if mine else "ESTOU PRONTO"
	ready_btn.add_theme_font_size_override("font_size", 34 if mine else 46)
	var my_team := str(Net.state.get("me", {}).get("team", ""))
	var col := {}
	for t in Net.state.get("teams", []):
		col[t["id"]] = Color(str(t["color"]))
	UI.clear(chips)
	var missing := []
	var n_ready := 0
	var n_on := 0
	for r in lst:
		if not r["online"]:
			continue
		n_on += 1
		if r["ready"]:
			n_ready += 1
		else:
			missing.append(UI.short_name(str(r["name"])))
		# só os colegas de equipe viram fichinhas (a turma inteira vira número)
		if str(r["team"]) != my_team:
			continue
		var c: Color = col.get(r["team"], UI.MIST)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UI.box(Color(UI.GREEN, 0.18) if r["ready"] else Color(UI.NIGHT, 0.8), UI.GREEN if r["ready"] else Color(c, 0.6), 2, 20, 8))
		var l := UI.label(("OK  " if r["ready"] else "") + UI.short_name(str(r["name"])), 20, UI.GREEN if r["ready"] else UI.PAPER, "bold")
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		chip.add_child(l)
		chips.add_child(chip)
	if counting:
		wait_l.text = "Todos prontos! O caso vai começar."
	elif bool(Net.state.get("solo", false)):
		wait_l.text = "Leia com calma e toque em PRONTO quando quiser começar."
	elif missing.is_empty():
		wait_l.text = "Esperando..."
	else:
		var shown := missing.slice(0, 4)
		wait_l.text = "%d de %d prontos  ·  falta: %s%s" % [n_ready, n_on, ", ".join(shown), (" e mais %d" % (missing.size() - 4)) if missing.size() > 4 else ""]
