extends Control
## Abertura do caso: título, narração noir em máquina de escrever e contagem regressiva.

var text_l: Label
var count_l: Label
var full_text := ""
var shown := 0.0


func _ready() -> void:
	var m := UI.margin(36, 60, 36)
	add_child(UI.full(m))
	var outer := UI.vbox(12)
	m.add_child(outer)
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
	for st in [["1", "EXPLORE", "Toque no que brilha nas cenas e troque de lugar no topo."], ["2", "CONVERSE", "Toque nas pessoas. Mostre pistas para elas abrirem o jogo."], ["3", "LIGUE", "Monte o quadro com fios e provas, aponte o culpado e apresente."]]:
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
	count_l = UI.title("", 96, UI.PAPER)
	count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(count_l)
	Sfx.set_ambience("ambience_rain_loop")


func _process(dt: float) -> void:
	var before := int(shown)
	shown = minf(full_text.length(), shown + dt * 38.0)
	text_l.visible_characters = int(shown)
	if int(shown) != before and int(shown) % 3 == 0:
		Sfx.play("timer_tick", -18.0, randf_range(1.6, 2.0))
	var s := Net.seconds_left()
	count_l.text = str(s) if s > 0 else "VAI!"
