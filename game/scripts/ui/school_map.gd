extends Control
## Mapa da escola: planta vista de cima com as salas do caso destacadas, quantas coisas ainda
## brilham em cada uma, quem está lá e onde o aluno está. Tocar numa sala vai até ela.
## Usa a planta pintada (assets/map/school_map.png + .json); sem ela, desenha a planta em código.

signal room_chosen(id: String)

const MAP_PNG := "res://assets/map/school_map.png"
const MAP_JSON := "res://assets/map/school_map.json"
const DEFAULT_SIZE := Vector2(1080, 1600)
# planta padrão: corredor no meio, salas dos dois lados (mesmo layout pedido para a arte)
const DEFAULT_ROOMS := {
	"corredor": [440, 40, 200, 1520], "biblioteca": [40, 40, 380, 240], "sala_aula": [660, 40, 380, 240],
	"laboratorio": [40, 300, 380, 240], "sala_musica": [660, 300, 380, 240], "sala_professores": [40, 560, 380, 240],
	"sala_diretor": [660, 560, 380, 240], "cantina": [40, 820, 380, 240], "deposito": [660, 820, 380, 240],
	"teatro": [40, 1080, 380, 240], "quadra": [660, 1080, 380, 480], "patio": [40, 1340, 380, 220],
}
const NAMES := {
	"corredor": "Corredor", "biblioteca": "Biblioteca", "teatro": "Teatro", "sala_aula": "Sala de aula",
	"cantina": "Cantina", "patio": "Pátio", "sala_professores": "Sala dos profs", "quadra": "Quadra",
	"sala_diretor": "Diretoria", "deposito": "Depósito", "laboratorio": "Laboratório", "sala_musica": "Sala de música",
}

var locations: Array = []       # salas que fazem parte do caso
var current := ""
var remaining := {}             # sala -> quantas coisas ainda brilham
var people := {}                # sala -> [nomes]
var _tex: Texture2D
var _rooms := {}
var _map_size := DEFAULT_SIZE
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists(MAP_PNG):
		_tex = load(MAP_PNG)
	if FileAccess.file_exists(MAP_JSON):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_JSON))
		if j is Dictionary:
			_map_size = Vector2(j.get("size", [1080, 1600])[0], j.get("size", [1080, 1600])[1])
			for k in j.get("rooms", {}):
				var r: Dictionary = j["rooms"][k]
				_rooms[k] = r.get("rect", [0, 0, 10, 10])
	if _rooms.is_empty():
		_rooms = DEFAULT_ROOMS.duplicate()


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


func _fit() -> Rect2:
	var s := minf(size.x / _map_size.x, size.y / _map_size.y)
	var w := _map_size * s
	return Rect2((size - w) / 2.0, w)


func _room_rect(id: String) -> Rect2:
	var a: Array = _rooms.get(id, [0, 0, 0, 0])
	var f := _fit()
	var k := f.size.x / _map_size.x
	return Rect2(f.position + Vector2(a[0], a[1]) * k, Vector2(a[2], a[3]) * k)


func _draw() -> void:
	var f := _fit()
	if _tex:
		draw_texture_rect(_tex, f, false)
	else:
		# planta em código: papel azulado com grade, paredes de tinta e o nome de cada sala
		draw_rect(f, Color("#1d2c5a"))
		var step := f.size.x / 18.0
		var x := f.position.x
		while x < f.end.x:
			draw_line(Vector2(x, f.position.y), Vector2(x, f.end.y), Color(1, 1, 1, 0.05), 1.0)
			x += step
		var y := f.position.y
		while y < f.end.y:
			draw_line(Vector2(f.position.x, y), Vector2(f.end.x, y), Color(1, 1, 1, 0.05), 1.0)
			y += step
		for id in _rooms:
			var r := _room_rect(id)
			draw_rect(r, Color("#26407a") if id != "corredor" else Color("#2f4a8a"))
			draw_rect(r, Color("#a9bdf0"), false, 2.0)
	var fnt := UI.font("title")
	for id in _rooms:
		var r := _room_rect(id)
		var in_case := locations.has(id)
		if not in_case:
			# fora do caso: apagada (não dá para ir)
			draw_rect(r, Color(UI.NIGHT, 0.62))
		else:
			var pulse := 0.5 + 0.5 * sin(_t * 3.0)
			var col := UI.YELLOW if id == current else Color("#8ef0b5") if int(remaining.get(id, 0)) > 0 else UI.SKY
			draw_rect(r.grow(-3), Color(col, 0.12 + (0.08 * pulse if id == current else 0.0)))
			draw_rect(r.grow(-3), col, false, 4.0 if id == current else 3.0)
		# nome da sala
		var nm := str(NAMES.get(id, id)).to_upper()
		var fs := int(clampf(r.size.x / 9.0, 18, 34))
		var tw := fnt.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tp := r.position + Vector2((r.size.x - tw) / 2.0, 30 if id != "corredor" else r.size.y / 2.0)
		if id == "corredor":
			draw_set_transform(r.get_center(), -PI / 2.0, Vector2.ONE)
			draw_string(fnt, Vector2(-tw / 2.0, fs * 0.35), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UI.PAPER, 0.9 if in_case else 0.35))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_rect(Rect2(tp + Vector2(-8, -fs + 2), Vector2(tw + 16, fs + 8)), Color(UI.NIGHT, 0.75 if in_case else 0.4))
			draw_string(fnt, tp, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UI.PAPER, 1.0 if in_case else 0.35))
		if not in_case:
			continue
		# marcadores: brilhos restantes, pessoas, "você está aqui"
		var badge_y := r.position.y + r.size.y - 30
		var left := int(remaining.get(id, 0))
		if left > 0:
			var bt := "%d pista%s aqui" % [left, "" if left == 1 else "s"]
			var bw := fnt.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 16
			var br := Rect2(Vector2(r.position.x + 8, badge_y), Vector2(bw, 24))
			draw_rect(br, Color("#8ef0b5"))
			draw_string(fnt, br.position + Vector2(8, 20), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.INK)
		var ppl: Array = people.get(id, [])
		for i in mini(ppl.size(), 3):
			var c := Vector2(r.end.x - 22 - i * 34, badge_y + 12)
			draw_circle(c, 15, Color("#ffd99a"))
			draw_circle(c, 15, UI.INK, false, 2.0)
			var ini := str(ppl[i]).substr(0, 1).to_upper()
			draw_string(fnt, c + Vector2(-6, 7), ini, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.INK)
		if id == current:
			var tag := "VOCÊ ESTÁ AQUI"
			var tw2 := fnt.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 16
			var tr := Rect2(r.get_center() - Vector2(tw2 / 2.0, 6), Vector2(tw2, 26))
			draw_rect(tr, UI.YELLOW)
			draw_string(fnt, tr.position + Vector2(8, 20), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.INK)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var p := (e as InputEventMouseButton).position
		# salas antes do corredor (o corredor é comprido e passa por trás de todas)
		var order: Array = _rooms.keys()
		order.erase("corredor")
		order.append("corredor")
		for id in order:
			if _room_rect(id).has_point(p) and locations.has(id):
				Sfx.play("paper_flip")
				room_chosen.emit(id)
				accept_event()
				return
