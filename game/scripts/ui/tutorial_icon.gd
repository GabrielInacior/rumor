extends Control
## Ilustração animada dos passos do quadro: carta sendo fixada, carta arrastada até outra
## (o fio nasce), pista arrastada até o fio (a prova gruda). Desenhada em código, em loop.

var kind := "pessoa"
var _t := 0.0


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


func _card(p: Vector2, col: Color, w := 34.0, h := 44.0) -> void:
	draw_rect(Rect2(p - Vector2(w, h) / 2.0 + Vector2(3, 4), Vector2(w, h)), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(p - Vector2(w, h) / 2.0, Vector2(w, h)), Color("#f3ecdc"))
	draw_rect(Rect2(p - Vector2(w, h) / 2.0 + Vector2(4, 4), Vector2(w - 8, h - 16)), col)
	draw_circle(p + Vector2(0, -h / 2.0 + 2), 4, UI.RED)


func _hand(p: Vector2) -> void:
	draw_circle(p + Vector2(6, 10), 9, Color("#e0ac84"))
	draw_rect(Rect2(p + Vector2(2, -6), Vector2(8, 16)), Color("#e0ac84"))
	draw_arc(p + Vector2(6, 10), 9, 0, TAU, 16, UI.INK, 2.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#7a5236"))
	var k := fmod(_t, 2.4) / 2.4
	var e := clampf(k * 1.6, 0.0, 1.0)
	e = e * e * (3.0 - 2.0 * e)
	var a := Vector2(size.x * 0.25, size.y * 0.55)
	var b := Vector2(size.x * 0.75, size.y * 0.5)
	match kind:
		"pessoa":
			var p := a.lerp(Vector2(size.x * 0.5, size.y * 0.5), e) - Vector2(0, (1.0 - e) * 20)
			_card(Vector2(size.x * 0.78, size.y * 0.42), Color("#3d6a8a"))
			_card(p, Color("#8a3d4f"))
			_hand(p + Vector2(8, 10))
		"fio":
			_card(b, Color("#3d6a8a"))
			var p := a.lerp(b - Vector2(30, 0), e)
			if k > 0.62:
				draw_line(a, b, UI.RED, 4.0)
				_card(a, Color("#8a3d4f"))
			else:
				draw_line(a, p, Color(UI.RED, 0.5), 3.0)
				_card(a, Color("#8a3d4f", 0.4))
				_card(p, Color("#8a3d4f"))
				_hand(p + Vector2(8, 10))
		"prova":
			_card(a, Color("#8a3d4f"))
			_card(b, Color("#3d6a8a"))
			draw_line(a, b, UI.RED, 4.0)
			var mid := (a + b) / 2.0
			var start := Vector2(size.x * 0.5, size.y * 0.12)
			var p := start.lerp(mid + Vector2(0, 16), e)
			draw_rect(Rect2(p - Vector2(22, 12), Vector2(44, 24)), UI.YELLOW)
			draw_rect(Rect2(p - Vector2(22, 12), Vector2(44, 7)), Color("#ff9a4d"))
			if k < 0.62:
				_hand(p + Vector2(10, 6))
