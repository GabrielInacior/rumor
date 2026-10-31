class_name Paper
extends PanelContainer
## Papel desenhado à mão em código: o "frame" de quase tudo que se lê no jogo.
## style: "notebook" (folha pautada com espiral), "sticky" (post-it), "receipt" (registro impresso,
## borda picotada), "polaroid" (foto de evidência), "card" (ficha lisa). Os filhos ficam por cima.

var style := "notebook"
var tilt := 0.0
var tape := false
var ink_margin := true
var paper_color := Color("#f4eedf")

const LINE := Color(0.36, 0.5, 0.78, 0.28)
const MARGIN := Color(0.88, 0.25, 0.3, 0.45)


static func make(p_style: String, p_tape := false) -> Paper:
	var p := Paper.new()
	p.style = p_style
	p.tape = p_tape
	match p_style:
		"sticky": p.paper_color = Color("#ffe27a")
		"receipt": p.paper_color = Color("#f7f5ee")
		"polaroid": p.paper_color = Color("#fbfaf6")
		"card": p.paper_color = Color("#efe8d6")
	var sb := StyleBoxEmpty.new()
	var pad: Array = {"notebook": [74, 46, 30, 30], "sticky": [26, 30, 26, 26], "receipt": [30, 34, 30, 34],
		"polaroid": [22, 22, 22, 70], "card": [26, 22, 26, 22]}[p_style]
	sb.content_margin_left = pad[0]
	sb.content_margin_top = pad[1]
	sb.content_margin_right = pad[2]
	sb.content_margin_bottom = pad[3]
	p.add_theme_stylebox_override("panel", sb)
	return p


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# sombra suave deslocada (papel sobre a mesa)
	draw_rect(Rect2(r.position + Vector2(6, 9), r.size), Color(0, 0, 0, 0.35))
	match style:
		"notebook":
			draw_rect(r, paper_color)
			var y := 46.0 + 40.0
			while y < r.size.y - 12:
				draw_line(Vector2(10, y), Vector2(r.size.x - 10, y), LINE, 1.5)
				y += 40.0
			if ink_margin:
				draw_line(Vector2(58, 0), Vector2(58, r.size.y), MARGIN, 2.0)
			# espiral no topo
			var x := 30.0
			while x < r.size.x - 20:
				draw_circle(Vector2(x, 14), 7, Color("#1b2650"))
				draw_arc(Vector2(x, 6), 10, PI * 0.15, PI * 0.85, 8, Color("#9aa3b8"), 3.0)
				x += 34.0
		"sticky":
			draw_rect(r, paper_color)
			draw_rect(Rect2(0, 0, r.size.x, 22), paper_color.darkened(0.06))
			# canto levemente dobrado
			var c := r.size
			draw_colored_polygon(PackedVector2Array([c - Vector2(34, 0), c, c - Vector2(0, 34)]), Color(0, 0, 0, 0.12))
			draw_colored_polygon(PackedVector2Array([c - Vector2(34, 0), c - Vector2(34, 34), c - Vector2(0, 34)]), paper_color.lightened(0.2))
		"receipt":
			draw_rect(r, paper_color)
			var zig := PackedVector2Array()
			var xx := 0.0
			while xx <= r.size.x:
				zig.append(Vector2(xx, r.size.y - (6.0 if int(xx / 12.0) % 2 == 0 else 0.0)))
				xx += 12.0
			draw_polyline(zig, Color(0, 0, 0, 0.18), 2.0)
			for i in 3:
				draw_line(Vector2(16, 14 + i * 4), Vector2(r.size.x - 16, 14 + i * 4), Color(0, 0, 0, 0.07), 1.0)
		"polaroid":
			draw_rect(r, paper_color)
		_:
			draw_rect(r, paper_color)
	if tape:
		var tw := 120.0
		draw_set_transform(Vector2(r.size.x / 2.0, 2), -0.05, Vector2.ONE)
		draw_rect(Rect2(-tw / 2.0, -14, tw, 30), Color(1, 1, 0.92, 0.55))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
