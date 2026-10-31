extends Control
## Logotipo "RUMOR" com o desalinhamento de impressão do Aranhaverso (rosa e ciano deslocados)
## e um tremor de vez em quando, como um boato que não para quieto.

var text := "RUMOR"
var font_size := 170
var _t := 0.0
var _glitch := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, font_size * 0.95)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	_t += dt
	_glitch = maxf(0.0, _glitch - dt * 3.0)
	if randf() < dt * 0.35:
		_glitch = 1.0
	queue_redraw()


func _draw() -> void:
	var f := UI.font("title")
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var base := Vector2((size.x - w) / 2.0, font_size * 0.82)
	var j := _glitch * 10.0
	var off := Vector2(5 + sin(_t * 1.3) * 2.0 + j, 3)
	draw_string(f, base + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(UI.PINK, 0.85))
	draw_string(f, base - off * Vector2(0.8, 0.6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#6fd3ff", 0.6))
	draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UI.YELLOW)
	# faixa de "fita" atravessando quando treme
	if _glitch > 0.3:
		var y := base.y - font_size * (0.2 + randf() * 0.5)
		draw_rect(Rect2(0, y, size.x, 6), Color(UI.NIGHT, 0.8))
