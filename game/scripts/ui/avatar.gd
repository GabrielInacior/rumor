extends Control
## Foto de perfil redonda: recorte circular do retrato do personagem, ou inicial sobre a cor da
## roupa dele quando o retrato não existe. Usada nos apps simulados e nas listas.

var who := ""
var radius := 30.0
var fallback_name := ""
var ring := Color.TRANSPARENT
var _tex: Texture2D


func setup(p_who: String, p_radius: float, p_name := "") -> void:
	who = p_who
	radius = p_radius
	fallback_name = p_name
	custom_minimum_size = Vector2(p_radius * 2.0 + 6, p_radius * 2.0 + 6)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_tex = UI.portrait(who) if who != "" else null
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var c := Vector2(radius + 3, radius + 3)
	if ring.a > 0:
		draw_circle(c, radius + 3, ring)
	var card := Net.card_by_id(who)
	var col := Color(str(card.get("look", {}).get("top", "#4e6fc0")))
	draw_circle(c, radius, col.darkened(0.2))
	if _tex:
		# polígono circular com UV mapeando o terço de cima do retrato (o rosto)
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in 32:
			var a := TAU * i / 32.0
			var d := Vector2(cos(a), sin(a))
			pts.append(c + d * radius)
			uvs.append(Vector2(0.5, 0.36) + d * Vector2(0.4, 0.32))
		draw_colored_polygon(pts, Color.WHITE, uvs, _tex)
	else:
		var n := fallback_name if fallback_name != "" else who
		var initial := n.substr(0, 1).to_upper() if n != "" else "?"
		if n.begins_with("@") and n.length() > 1:
			initial = n.substr(1, 1).to_upper()
		var f := UI.font("title")
		var fs := int(radius * 1.25)
		var w := f.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, c + Vector2(-w / 2.0, fs * 0.36), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	draw_arc(c, radius, 0, TAU, 32, Color(0, 0, 0, 0.35), 2.0)
