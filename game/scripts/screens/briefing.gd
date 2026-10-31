extends Control
## Abertura do caso: título, narração noir em máquina de escrever e contagem regressiva.

var text_l: Label
var count_l: Label
var full_text := ""
var shown := 0.0


func _ready() -> void:
	var m := UI.margin(44, 110, 70)
	add_child(UI.full(m))
	var v := UI.vbox(22)
	m.add_child(v)
	var c := Net.case_data
	v.add_child(UI.label("CASO", 30, UI.MIST, "type"))
	var t := UI.title(str(c.get("title", "")).to_upper(), 78, UI.YELLOW)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	v.add_child(UI.label(UI.strip_emoji(str(c.get("tagline", ""))), 30, UI.PINK, "bold"))
	# a narração vem numa folha de caderno, como as anotações de um detetive
	var p := Paper.make("notebook", true)
	text_l = UI.label("", 29, Color("#1b2140"), "type")
	text_l.add_theme_constant_override("line_spacing", 11)
	p.add_child(text_l)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pm := UI.margin(6, 14, 14)
	pm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pm.add_child(p)
	sc.add_child(pm)
	v.add_child(sc)
	var goal := UI.label("Objetivo: " + str(c.get("goal", "")), 28, UI.YELLOW, "bold")
	v.add_child(goal)
	count_l = UI.title("", 110, UI.PAPER)
	count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(count_l)
	full_text = UI.strip_emoji(str(c.get("briefing", "")))
	Sfx.set_ambience("ambience_rain_loop")


func _process(dt: float) -> void:
	var before := int(shown)
	shown = minf(full_text.length(), shown + dt * 38.0)
	text_l.text = full_text.substr(0, int(shown))
	if int(shown) != before and int(shown) % 3 == 0:
		Sfx.play("timer_tick", -18.0, randf_range(1.6, 2.0))
	var s := Net.seconds_left()
	count_l.text = str(s) if s > 0 else "VAI!"
