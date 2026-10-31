extends SubViewportContainer
## Cena 3D interativa do caso, leve para celular: poucas formas, um shader de pintura,
## contorno de tinta, uma lua azul e luzes amarelas marcando o que importa.
## Arrastar gira a câmera um pouco; tocar num objeto brilhante abre a pista para a equipe.
## Objetos sem pista respondem com uma frase de narrador (clima e humor, sem informação extra).

signal hotspot_tapped(id: String, label: String)
signal flavor_tapped(text: String)
signal person_tapped(id: String)

const TOON := preload("res://shaders/toon.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")
const Character := preload("res://scripts/scene3d/character.gd")
const PEOPLE_SPOTS := {
	"corredor": [Vector3(0.9, 0, -3.2), Vector3(-0.9, 0, -9.6), Vector3(1.0, 0, -11.4)],
	"biblioteca": [Vector3(-1.1, 0, -2.4), Vector3(1.6, 0, -4.6), Vector3(-0.6, 0, -8.6)],
	"teatro": [Vector3(-0.6, 0.9, -7.0), Vector3(1.9, 0.9, -7.3), Vector3(-1.4, 0, -4.4)],
	"sala_aula": [Vector3(2.4, 0, -5.4), Vector3(-2.6, 0, -1.6), Vector3(1.25, 0, -3.2)],
	"cantina": [Vector3(-2.5, 0, -5.4), Vector3(1.6, 0, -3.2), Vector3(-1.2, 0, -2.9)],
	"patio": [Vector3(0.2, 0, -4.4), Vector3(-1.4, 0, -6.2), Vector3(-0.5, 0, -2.4)],
	"sala_professores": [Vector3(0.9, 0, -5.0), Vector3(1.7, 0, -2.6), Vector3(-1.1, 0, -3.0)],
	"quadra": [Vector3(-1.2, 0, -4.0), Vector3(2.2, 0, -7.4), Vector3(1.4, 0, -2.6)],
	"sala_diretor": [Vector3(-0.9, 0, -5.4), Vector3(1.6, 0, -4.8), Vector3(-1.3, 0, -2.2)],
	"deposito": [Vector3(-0.6, 0, -4.2), Vector3(1.3, 0, -3.6), Vector3(-0.9, 0, -2.6)],
	"laboratorio": [Vector3(-1.6, 0, -3.8), Vector3(2.0, 0, -3.6), Vector3(-1.2, 0, -2.0)],
	"sala_musica": [Vector3(-1.6, 0, -5.6), Vector3(1.7, 0, -4.6), Vector3(-1.3, 0, -3.0)],
	"fachada": [Vector3(-1.5, 0, 0.6), Vector3(0.0, 0, 1.0), Vector3(1.5, 0, 0.6)],
}

var scene_id := "corredor"
var hotspots: Array = []        # do caso: [{id, object, label}]
var found := {}                 # hotspot id -> true
var people: Array = []          # cartas de pessoa que aparecem na cena

var vp: SubViewport
var world: Node3D
var cam: Camera3D
var pivot: Node3D
var _mats := {}
var _targets := {}              # nome do corpo -> {kind, id, label|text, mesh}
var _glows: Array = []          # [{mesh, light, ring, id}]
var _yaw := 0.0
var _pitch := 0.0
var _yaw_limit := 0.5
var _press := Vector2.ZERO
var _moved := false
var _down := false
var _t := 0.0


func _ready() -> void:
	stretch = true
	vp = SubViewport.new()
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.own_world_3d = true
	vp.handle_input_locally = false
	# meia resolução: o celular agradece e o visual pintado esconde a diferença
	stretch_shrink = 2 if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") else 1
	add_child(vp)
	world = Node3D.new()
	vp.add_child(world)
	_build()


func setup(p_scene: String, p_hotspots: Array, p_found: Dictionary, p_people: Array = []) -> void:
	scene_id = p_scene
	hotspots = p_hotspots
	found = p_found
	people = p_people
	if world:
		_build()


func mark_found(id: String) -> void:
	found[id] = true
	for g in _glows:
		if g["id"] == id:
			(g["ring"] as Node3D).visible = false
			((g["light"]) as OmniLight3D).light_energy = 0.4


# ------------------------------------------------------------------ montagem
func _build() -> void:
	for c in world.get_children():
		c.queue_free()
	_targets.clear()
	_glows.clear()
	_mats.clear()
	_rains.clear()
	_flickers.clear()
	_spinners.clear()
	_anchors = {}
	_free_anchors = []
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0a1430")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#2a3f78")
	e.ambient_light_energy = 1.35
	e.fog_enabled = true
	e.fog_light_color = Color("#16244d")
	e.fog_density = 0.025
	env.environment = e
	world.add_child(env)
	_env = e

	pivot = Node3D.new()
	world.add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 62
	pivot.add_child(cam)

	match scene_id:
		"biblioteca": _scene_biblioteca()
		"teatro": _scene_teatro()
		"sala_aula": _scene_sala_aula()
		"cantina": _scene_cantina()
		"patio": _scene_patio()
		"sala_professores": _scene_sala_professores()
		"quadra": _scene_quadra()
		"sala_diretor": _scene_sala_diretor()
		"deposito": _scene_deposito()
		"laboratorio": _scene_laboratorio()
		"sala_musica": _scene_sala_musica()
		"fachada": _scene_fachada()
		_: _scene_corredor()
	_place_hotspots()
	_place_people()
	# âncora que não recebeu pista ainda responde com uma frase de narrador (nada fica "morto" ao toque)
	var used := {}
	for h in hotspots:
		used[str(h.get("object", ""))] = true
	for k in _anchors:
		var a: Dictionary = _anchors[k]
		if not used.has(k) and a.has("say") and a.get("mesh") != null:
			_flavor(a["mesh"], str(a["say"]))


func _mat(col: Color, emit := 0.0, emit_col := Color("#ffc83d"), outline := 0.025) -> ShaderMaterial:
	var key := "%s|%.2f|%s|%.3f" % [col.to_html(), emit, emit_col.to_html(), outline]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("emission_energy", emit)
	m.set_shader_parameter("emission_color", emit_col)
	if outline > 0.0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("width", outline)
		m.next_pass = o
	_mats[key] = m
	return m


func _box(pos: Vector3, sz: Vector3, col: Color, rot_y := 0.0, emit := 0.0, outline := 0.025, emit_col := Color("#ffc83d")) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = _mat(col, emit, emit_col, outline)
	mi.position = pos
	mi.rotation.y = rot_y
	world.add_child(mi)
	return mi


func _cyl(pos: Vector3, r: float, h: float, col: Color, r_top := -1.0, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r if r_top < 0 else r_top
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _mat(col, emit)
	mi.position = pos
	world.add_child(mi)
	return mi


func _ball(pos: Vector3, r: float, col: Color, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 14
	sm.rings = 7
	mi.mesh = sm
	mi.material_override = _mat(col)
	mi.position = pos
	mi.scale = scale
	world.add_child(mi)
	return mi


func _light(pos: Vector3, col: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.2
	world.add_child(l)
	return l


func _moon(dir: Vector3, energy := 1.1) -> void:
	var s := DirectionalLight3D.new()
	s.light_color = Color("#9fb8ff")
	s.light_energy = energy
	s.shadow_enabled = true
	s.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	s.directional_shadow_max_distance = 22.0
	world.add_child(s)
	s.look_at_from_position(Vector3.ZERO, dir, Vector3.UP)


func _camera(pos: Vector3, target: Vector3, yaw_limit := 0.5) -> void:
	# a câmera fica presa num pivô no alvo: girar o pivô = olhar em volta sem sair do lugar errado
	pivot.position = target
	cam.position = pos - target
	cam.look_at(target, Vector3.UP)
	_yaw_limit = yaw_limit


## objeto tocável: registra o corpo de colisão com o que ele faz
func _target(mi: MeshInstance3D, kind: String, data: Dictionary) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var aabb := mi.get_aabb()
	bs.size = (aabb.size * mi.scale).max(Vector3(0.35, 0.35, 0.35))
	shape.shape = bs
	shape.position = aabb.get_center()
	body.add_child(shape)
	mi.add_child(body)
	var d := data.duplicate()
	d["kind"] = kind
	d["mesh"] = mi
	_targets[body.get_instance_id()] = d


func _flavor(mi: MeshInstance3D, text: String) -> void:
	_target(mi, "flavor", {"text": text})


# Âncoras onde cada cena aceita objetos de pista. Objeto com id desconhecido vai para a próxima livre.
var _anchors := {}
var _free_anchors: Array = []


func _place_hotspots() -> void:
	var used := 0
	for h in hotspots:
		var obj := str(h.get("object", ""))
		var a: Dictionary = _anchors.get(obj, {})
		if a.is_empty():
			if used < _free_anchors.size():
				a = _free_anchors[used]
				used += 1
			else:
				a = {"pos": Vector3(0, 0.6, -2), "size": Vector3(0.5, 0.4, 0.4)}
		var mi: MeshInstance3D = a.get("mesh") if a.has("mesh") else _box(a["pos"], a["size"], Color("#e8e2cc"), 0.0, 0.25)
		_target(mi, "hotspot", {"id": h["id"], "label": h["label"]})
		var lpos: Vector3 = mi.global_position if mi.is_inside_tree() else mi.position
		var light := _light(lpos + Vector3(0, 0.6, 0.4), Color("#ffc83d"), 1.6, 2.6)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.16
		tm.outer_radius = 0.22
		tm.rings = 16
		tm.ring_segments = 6
		ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Color("#ffc83d")
		ring.material_override = rm
		ring.position = lpos + Vector3(0, 0.75, 0)
		ring.rotation.x = PI / 2.0
		world.add_child(ring)
		_glows.append({"mesh": mi, "light": light, "ring": ring, "id": h["id"]})
		if found.has(h["id"]):
			ring.visible = false
			light.light_energy = 0.4


func _place_people() -> void:
	var spots: Array = PEOPLE_SPOTS.get(scene_id, PEOPLE_SPOTS["corredor"])
	for i in mini(people.size(), spots.size()):
		var c: Dictionary = people[i]
		var ch := Character.new()
		world.add_child(ch)
		ch.setup(c)
		ch.position = spots[i]
		# vira para a câmera, com um leve desvio para não ficar "posando"
		var to_cam := cam.global_position - ch.global_position
		ch.rotation.y = atan2(to_cam.x, to_cam.z) + randf_range(-0.35, 0.35)
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.4
		cap.height = 1.9
		shape.shape = cap
		shape.position = Vector3(0, 0.95, 0)
		body.add_child(shape)
		ch.add_child(body)
		_targets[body.get_instance_id()] = {"kind": "person", "id": c["id"], "mesh": null}
		# luz amarela fraca de "holofote" para a pessoa ler bem no escuro
		_light(spots[i] + Vector3(0.3, 2.0, 0.8), Color("#ffd99a"), 0.9, 2.6)


# ------------------------------------------------------------------ peças extras das cenas
# Paleta curta: quase tudo é azul-noite; madeira e papel aquecem; vermelho é acento raro;
# amarelo (luz) fica reservado para o que importa. Poucas cores = poucos materiais no cache.
const NAVY := Color("#1b2650")
const INK := Color("#111a33")
const WALL := Color("#3d4a85")
const WALL_L := Color("#6d7fb0")
const WALL_M := Color("#4c5c94")
const CEIL := Color("#2a3866")
const WOOD := Color("#7a5a3e")
const WOOD_D := Color("#5a3d2a")
const WOOD_DD := Color("#3b2a20")
const PAPER := Color("#efe8d6")
const CREAM := Color("#e8e2cc")
const RED := Color("#b34a5e")
const RED_D := Color("#8a2a3e")
const YEL := Color("#ffc83d")
const WARM := Color("#ffc380")
const SKY := Color("#3557a8")
const METAL := Color("#8a96b8")
const METAL_D := Color("#4a5580")
const BOARD := Color("#1e3a2e")
const LEAF := Color("#24425a")
const TEAL := Color("#3d6a8a")
const BOOK_COLS := [Color("#6b4a8a"), Color("#3d6a8a"), Color("#8a3d4f"), Color("#4f7a5a"), Color("#a8873d"), Color("#2e3b6b"), Color("#c9bfa6"), Color("#55608f")]

var _env: Environment
var _rains: Array = []          # [{node, y0, h, speed}]
var _flickers: Array = []       # [{light, mat, base, emit, seed}]
var _spinners: Array = []       # [{node, speed}]
var _showcase := false
var _mm_shader: Shader
var _mm_material: ShaderMaterial
var _fonts := {}


## Modo vitrine (menu inicial): a câmera passeia sozinha, devagar, e o toque é ignorado.
func set_showcase(on: bool) -> void:
	_showcase = on
	if not on:
		_yaw = 0.0
		_pitch = 0.0


func _sky(bg: Color, ambient: Color, ambient_energy: float, fog: Color, fog_density: float) -> void:
	_env.background_color = bg
	_env.ambient_light_color = ambient
	_env.ambient_light_energy = ambient_energy
	_env.fog_light_color = fog
	_env.fog_density = fog_density


func _mesh(m: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	world.add_child(mi)
	return mi


## caixa sem contorno (parede, piso, detalhe pequeno demais para tinta)
func _flat(pos: Vector3, sz: Vector3, col: Color, rot_y := 0.0, emit := 0.0, emit_col := Color("#ffc83d")) -> MeshInstance3D:
	return _box(pos, sz, col, rot_y, emit, 0.0, emit_col)


func _glow(col: Color, energy: float) -> ShaderMaterial:
	return _mat(col, energy, col, 0.0)


func _torus(pos: Vector3, r_in: float, r_out: float, col: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = r_in
	tm.outer_radius = r_out
	tm.rings = 16
	tm.ring_segments = 6
	return _mesh(tm, pos, _mat(col, 0.0, YEL, 0.01), rot)


func _disc(pos: Vector3, r: float, col: Color, scl := Vector3.ONE, emit := 0.0) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.01
	cm.radial_segments = 16
	cm.rings = 1
	return _mesh(cm, pos, _mat(col, emit, col, 0.0), Vector3.ZERO, scl)


## texto pintado na cena (giz, cartaz, placar). Label3D é barato e não conta como malha.
func _text(pos: Vector3, txt: String, line_h: float, col: Color, font := "marker", rot_y := 0.0, outline := 0) -> Label3D:
	if not _fonts.has(font):
		var path: String = {"marker": "res://assets/fonts/PermanentMarker-Regular.ttf", "bebas": "res://assets/fonts/BebasNeue-Regular.ttf",
			"type": "res://assets/fonts/SpecialElite-Regular.ttf"}.get(font, "res://assets/fonts/PermanentMarker-Regular.ttf")
		_fonts[font] = load(path)
	var l := Label3D.new()
	l.text = txt
	l.font = _fonts[font]
	l.font_size = 48
	l.pixel_size = line_h / 48.0
	l.modulate = col
	l.outline_size = outline
	l.outline_modulate = INK
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.line_spacing = -line_h * 8.0
	l.position = pos
	l.rotation.y = rot_y
	world.add_child(l)
	return l


## muitas caixas numa chamada só (livros, garrafas, partituras): uma malha, cor por instância.
## item = [pos, size, cor] ou [pos, size, cor, Basis]
func _mm(items: Array) -> MultiMeshInstance3D:
	if _mm_shader == null:
		_mm_shader = Shader.new()
		_mm_shader.code = TOON.code.replace("ALBEDO = albedo.rgb *", "ALBEDO = albedo.rgb * COLOR.rgb *")
	if _mm_material == null:
		_mm_material = ShaderMaterial.new()
		_mm_material.shader = _mm_shader
		_mm_material.set_shader_parameter("albedo", Color.WHITE)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = items.size()
	for i in items.size():
		var it: Array = items[i]
		var rot: Basis = it[3] if it.size() > 3 else Basis.IDENTITY
		mm.set_instance_transform(i, Transform3D(rot * Basis.from_scale(it[1]), it[0]))
		mm.set_instance_color(i, it[2])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mm_material
	world.add_child(mmi)
	return mmi


## fileira de livros numa prateleira; along_x = lombadas viradas para +Z, senão para +X
func _books(base: Vector3, along_x: bool, length: float, rows: int, row_h: float, depth: float, seed: int, items: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for r in rows:
		var t := -length * 0.5
		var lean_next := false
		while t < length * 0.5 - 0.12:
			var w := rng.randf_range(0.045, 0.1)
			var hh := rng.randf_range(row_h * 0.55, row_h * 0.86)
			var col: Color = BOOK_COLS[rng.randi() % BOOK_COLS.size()]
			var rot := Basis.IDENTITY
			var lift := 0.0
			if lean_next:
				# livro tombado no buraco deixado pelo vizinho: cara de estante usada de verdade
				rot = Basis(Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0), 0.32 if along_x else -0.32)
				t += 0.06
				lift = -0.02
				lean_next = false
			var off := t + w * 0.5
			var p := base + Vector3(0, r * row_h + hh * 0.5 + 0.03 + lift, 0) + (Vector3(off, 0, 0) if along_x else Vector3(0, 0, off))
			var s := Vector3(w, hh, depth) if along_x else Vector3(depth, hh, w)
			items.append([p, s, col, rot])
			t += w + 0.006
			if rng.randf() < 0.07:
				t += rng.randf_range(0.08, 0.16)
				lean_next = true


## estante de madeira: fundo, laterais, tampo e tábuas; along_x = frente para +Z
func _shelf(center: Vector3, along_x: bool, length: float, height: float, depth: float, rows: int, col: Color) -> MeshInstance3D:
	var sz := Vector3(length, height, 0.05) if along_x else Vector3(0.05, height, length)
	var back_off := Vector3(0, 0, -depth * 0.5) if along_x else Vector3(-depth * 0.5, 0, 0)
	var back := _box(center + back_off + Vector3(0, height * 0.5, 0), sz, WOOD_DD, 0.0, 0.0, 0.0)
	for s in [-1, 1]:
		var side_off := Vector3(s * length * 0.5, 0, 0) if along_x else Vector3(0, 0, s * length * 0.5)
		_box(center + side_off + Vector3(0, height * 0.5, 0), Vector3(0.06, height, depth) if along_x else Vector3(depth, height, 0.06), col, 0.0, 0.0, 0.015)
	var row_h := (height - 0.1) / rows
	for r in rows + 1:
		_box(center + Vector3(0, 0.03 + r * row_h, 0), Vector3(length, 0.04, depth) if along_x else Vector3(depth, 0.04, length), col, 0.0, 0.0, 0.0)
	return back


## parede com janelas para a noite: peitoril, verga, pilares, caixilhos; lá fora céu aceso e chuva.
## along_x: a parede corre no eixo X (fica em z = at); senão corre no Z (fica em x = at).
## wins = [[centro, largura], ...]; out = lado de fora (+1 ou -1). Devolve o peitoril de cada janela.
func _win_wall(along_x: bool, at: float, a0: float, a1: float, h: float, sill: float, head: float, wins: Array, col: Color, out: float, rain := true) -> Array:
	var th := 0.12
	var mid := (a0 + a1) * 0.5
	var length := a1 - a0
	_wpiece(along_x, at, mid, sill * 0.5, length, sill, th, col)
	_wpiece(along_x, at, mid, (head + h) * 0.5, length, h - head, th, col)
	var cursor := a0
	var ledges := []
	for w in wins:
		var c: float = w[0]
		var ww: float = w[1]
		if c - ww * 0.5 - cursor > 0.02:
			_wpiece(along_x, at, (cursor + c - ww * 0.5) * 0.5, (sill + head) * 0.5, c - ww * 0.5 - cursor, head - sill, th, col)
		cursor = c + ww * 0.5
		# caixilho em cruz e peitoril claro saltado para dentro
		_wpiece(along_x, at, c, (sill + head) * 0.5, 0.05, head - sill, th * 0.6, INK)
		_wpiece(along_x, at, c, sill + (head - sill) * 0.55, ww, 0.05, th * 0.6, INK)
		var lin := -out * 0.08
		var ledge: MeshInstance3D
		if along_x:
			ledge = _box(Vector3(c, sill + 0.02, at + lin), Vector3(ww + 0.1, 0.05, 0.2), WALL_L, 0.0, 0.0, 0.012)
		else:
			ledge = _box(Vector3(at + lin, sill + 0.02, c), Vector3(0.2, 0.05, ww + 0.1), WALL_L, 0.0, 0.0, 0.012)
		ledges.append(ledge)
		if sill < 2.0:
			for half in [-1.0, 1.0]:
				var pc := c + half * ww * 0.25
				var pdepth := -out * 1.25
				var ppos := Vector3(pc, 0.008, at + pdepth) if along_x else Vector3(at + pdepth, 0.008, pc)
				var psz := Vector3(ww * 0.45, 0.004, 1.1) if along_x else Vector3(1.1, 0.004, ww * 0.45)
				_flat(ppos, psz, Color("#7d9be0"), 0.0, 0.3, Color("#7d9be0"))
	if a1 - cursor > 0.02:
		_wpiece(along_x, at, (cursor + a1) * 0.5, (sill + head) * 0.5, a1 - cursor, head - sill, th, col)
	# céu lá fora: um painel aceso longe da parede e a chuva entre os dois
	var sky_pos := Vector3(mid, h * 0.5, at + out * 2.2) if along_x else Vector3(at + out * 2.2, h * 0.5, mid)
	_flat(sky_pos, Vector3(length + 4, h + 4, 0.1) if along_x else Vector3(0.1, h + 4, length + 4), SKY, 0.0, 1.5, SKY)
	if rain:
		var rc := Vector3(mid, h * 0.5, at + out * 1.0) if along_x else Vector3(at + out * 1.0, h * 0.5, mid)
		_rain(rc, Vector3(length, h + 1.0, 1.2) if along_x else Vector3(1.2, h + 1.0, length), int(length * 14))
	return ledges


func _wpiece(along_x: bool, at: float, a: float, y: float, length: float, hgt: float, th: float, col: Color) -> void:
	if along_x:
		_flat(Vector3(a, y, at), Vector3(length, hgt, th), col)
	else:
		_flat(Vector3(at, y, a), Vector3(th, hgt, length), col)


## chuva: riscos finos numa MultiMesh só, empilhados em duas alturas para o laço não "pular"
func _rain(center: Vector3, size: Vector3, count: int, seed := 7) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.42, 0.012)
	mm.mesh = bm
	mm.instance_count = count * 2
	var b := Basis(Vector3(1, 0, 0), 0.1)
	for i in count:
		var p := Vector3(rng.randf_range(-0.5, 0.5) * size.x, rng.randf() * size.y, rng.randf_range(-0.5, 0.5) * size.z)
		mm.set_instance_transform(i, Transform3D(b, p))
		mm.set_instance_transform(i + count, Transform3D(b, p + Vector3(0, size.y, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.62, 0.74, 1.0, 0.38)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.position = Vector3(center.x, center.y - size.y * 0.5, center.z)
	world.add_child(mmi)
	_rains.append({"node": mmi, "y0": mmi.position.y, "h": size.y, "speed": 9.0})


## facho de luz falso (cone aditivo transparente): holofote e poste parecem ter ar com poeira
func _beam(from: Vector3, to: Vector3, r_from: float, r_to: float, col: Color, alpha := 0.1) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_from
	cm.bottom_radius = r_to
	cm.height = from.distance_to(to)
	cm.radial_segments = 16
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	var mi := _mesh(cm, (from + to) * 0.5, m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.basis = Basis(Quaternion(Vector3.UP, (from - to).normalized()))
	return mi


## poça: mancha escura com o reflexo esticado da luz mais próxima (reflexo falso, custo zero)
func _puddle(pos: Vector3, size: Vector2, refl: Color, refl_off := 0.0) -> void:
	_disc(pos + Vector3(0, 0.006, 0), 1.0, Color("#0e1a40"), Vector3(size.x, 1, size.y))
	_disc(pos + Vector3(refl_off, 0.012, 0), 1.0, Color("#3a52a0"), Vector3(size.x * 0.75, 1, size.y * 0.6), 0.12)
	_flat(pos + Vector3(refl_off, 0.016, size.y * 0.1), Vector3(0.07, 0.004, size.y * 1.1), refl, 0.0, 0.8, refl)


## lua no céu: disco aceso e halo
func _moon_disc(pos: Vector3, r: float) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2
	sm.radial_segments = 16
	sm.rings = 8
	_mesh(sm, pos, _glow(Color("#e9efff"), 1.4))
	var halo := SphereMesh.new()
	halo.radius = r * 2.4
	halo.height = r * 4.8
	halo.radial_segments = 16
	halo.rings = 8
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.55, 0.65, 1.0, 0.12)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mesh(halo, pos, m)


## lâmpada que pisca de vez em quando (o clássico do corredor à noite)
func _flicker(mi: MeshInstance3D, light: OmniLight3D, emit: float) -> void:
	var m: ShaderMaterial = (mi.material_override as ShaderMaterial).duplicate()
	mi.material_override = m
	_flickers.append({"light": light, "mat": m, "base": light.light_energy, "emit": emit, "seed": randf() * 5.0})


## luminária fluorescente de teto
func _tube(pos: Vector3, length: float, along_x := false) -> MeshInstance3D:
	_flat(pos + Vector3(0, 0.04, 0), Vector3(length + 0.1, 0.04, 0.3) if along_x else Vector3(0.3, 0.04, length + 0.1), METAL_D)
	return _flat(pos, Vector3(length, 0.04, 0.16) if along_x else Vector3(0.16, 0.04, length), Color("#dfe8ff"), 0.0, 1.1, Color("#dfe8ff"))


## cadeira escolar simples: assento, encosto e armação
func _chair(pos: Vector3, rot_y: float, col: Color) -> MeshInstance3D:
	var fwd := Vector3(sin(rot_y), 0, cos(rot_y))
	var seat := _box(pos + Vector3(0, 0.45, 0), Vector3(0.42, 0.05, 0.4), col, rot_y, 0.0, 0.012)
	_box(pos + Vector3(0, 0.72, 0) - fwd * 0.19, Vector3(0.42, 0.3, 0.04), col, rot_y, 0.0, 0.012)
	# armação em trenó: duas laterais finas de metal (lê como pés, custa duas caixas)
	var side := Vector3(cos(rot_y), 0, -sin(rot_y))
	for s in [-1.0, 1.0]:
		_flat(pos + Vector3(0, 0.22, 0) + side * (0.18 * s), Vector3(0.025, 0.44, 0.34), METAL_D, rot_y)
	return seat


## carteira escolar: tampo, pés metálicos e cadeira atrás
func _desk(pos: Vector3, rot_y := 0.0) -> MeshInstance3D:
	var top := _box(pos + Vector3(0, 0.74, 0), Vector3(0.62, 0.04, 0.46), WOOD, rot_y, 0.0, 0.012)
	_box(pos + Vector3(0, 0.37, 0), Vector3(0.5, 0.72, 0.04), METAL_D, rot_y, 0.0, 0.0)
	var back := Vector3(sin(rot_y), 0, cos(rot_y)) * 0.45
	_chair(pos + back, rot_y + PI, WOOD_D)
	return top


## bilhetes e cartazes num quadro (lista de [y, z_ou_x, w, h, cor])
func _notes(base: Vector3, along_x: bool, list: Array) -> void:
	for n in list:
		var a: float = n[1]
		var p := base + (Vector3(a, n[0], 0) if along_x else Vector3(0, n[0], a))
		var s := Vector3(n[2], n[3], 0.01) if along_x else Vector3(0.01, n[3], n[2])
		_flat(p, s, n[4] if n.size() > 4 else PAPER)


# ------------------------------------------------------------------ cenas
func _person(pos: Vector3, top: Color, hair: Color, face_y := 0.0) -> void:
	# figura estilizada de fundo (silhueta), só para dar vida; não é tocável
	_cyl(pos + Vector3(0, 0.45, 0), 0.12, 0.9, Color("#1b2650"), 0.1)
	_cyl(pos + Vector3(0, 1.15, 0), 0.24, 0.6, top, 0.18)
	_ball(pos + Vector3(0, 1.62, 0), 0.19, Color("#c98d6b"))
	_ball(pos + Vector3(0, 1.72, -0.03), 0.2, hair, Vector3(1, 0.8, 1))


func _scene_corredor() -> void:
	var W := 2.4
	for i in 8:
		for j in 2:
			_flat(Vector3(-W / 2 + j * W + (W / 2 if j == 0 else -W / 2), -0.05, -i * 2.0), Vector3(W, 0.1, 2.0),
				Color("#5d6f9e") if (i + j) % 2 == 0 else Color("#46578a"))
	_flat(Vector3(0, 3.3, -7), Vector3(W * 2, 0.1, 16), CEIL)
	_flat(Vector3(-W - 0.05, 1.65, -7), Vector3(0.1, 3.3, 16), WALL_L)
	# armários à esquerda: rodapé e tampo contínuos; um vermelho, um escancarado
	_flat(Vector3(-W + 0.25, 0.04, -5.45), Vector3(0.52, 0.08, 12.9), INK)
	_flat(Vector3(-W + 0.25, 2.0, -5.45), Vector3(0.54, 0.05, 12.9), WALL)
	var aberto: MeshInstance3D
	for k in 26:
		var z := 0.8 - k * 0.5
		if z < -4.2 and z > -5.8:
			continue
		var col := Color("#5a7ab8") if k % 2 == 0 else Color("#4c68a6")
		if k == 7:
			col = RED
		if k == 17:
			# armário aberto: miolo escuro, prateleira bagunçada e a porta para fora, pedindo atenção
			_flat(Vector3(-W + 0.22, 1.0, z), Vector3(0.44, 1.9, 0.46), INK)
			_flat(Vector3(-W + 0.3, 1.45, z), Vector3(0.36, 0.03, 0.42), METAL_D)
			_box(Vector3(-W + 0.33, 1.55, z + 0.06), Vector3(0.24, 0.16, 0.2), BOOK_COLS[0], 0.15, 0.0, 0.01)
			_box(Vector3(-W + 0.33, 1.52, z - 0.12), Vector3(0.22, 0.1, 0.16), BOOK_COLS[3], -0.1, 0.0, 0.01)
			_ball(Vector3(-W + 0.3, 0.32, z), 0.2, RED_D, Vector3(1.0, 0.7, 1.1))     # moletom embolado
			_flat(Vector3(-W + 0.44, 1.75, z), Vector3(0.01, 0.16, 0.12), PAPER)        # foto colada
			var hinge := Vector3(-W + 0.5, 1.0, z - 0.235)
			var dir := Vector3(0.94, 0, 0.34)
			aberto = _box(hinge + dir * 0.235, Vector3(0.03, 1.92, 0.47), Color("#5a7ab8"), atan2(dir.x, dir.z), 0.0, 0.015)
			_flat(hinge + dir * 0.235 + Vector3(-0.02, 0.55, 0.06), Vector3(0.12, 0.16, 0.01), RED, atan2(dir.x, dir.z))
			continue
		var lk := _box(Vector3(-W + 0.25, 1.0, z), Vector3(0.5, 1.9, 0.47), col, 0.0, 0.0, 0.015)
		_flat(Vector3(-W + 0.505, 1.6, z), Vector3(0.01, 0.16, 0.28), INK)
		if k == 7:
			_flavor(lk, "O armário vermelho. Todo corredor tem um. Ninguém sabe por quê.")
		elif k == 11:
			_flat(Vector3(-W + 0.51, 1.25, z), Vector3(0.01, 0.1, 0.14), CREAM)
			_flavor(lk, "Um adesivo de banda que você nunca ouviu falar. Respeito.")
	_ball(Vector3(-W + 0.3, 2.17, -9.3), 0.13, Color("#a0603e"))   # bola esquecida em cima dos armários
	# parede direita com janelas e chuva lá fora
	_win_wall(false, W + 0.05, -15.0, 1.0, 3.3, 1.0, 2.7, [[0.0, 2.4], [-3.0, 2.4], [-6.0, 2.4], [-9.0, 2.4], [-12.0, 2.4]], WALL_M, 1.0)
	var banco := _box(Vector3(W - 0.35, 0.42, -2.2), Vector3(0.5, 0.08, 1.6), WOOD)
	_box(Vector3(W - 0.35, 0.2, -1.6), Vector3(0.4, 0.4, 0.06), WOOD_DD)
	_box(Vector3(W - 0.35, 0.2, -2.8), Vector3(0.4, 0.4, 0.06), WOOD_DD)
	var cel := _box(Vector3(W - 0.3, 0.48, -2.4), Vector3(0.12, 0.02, 0.2), INK, 0.4, 0.0, 0.006)
	_flat(Vector3(W - 0.3, 0.495, -2.4), Vector3(0.1, 0.005, 0.17), Color("#fff2b8"), 0.4, 2.5, Color("#fff2b8"))
	# lixeira com bolinhas de papel: duas erraram o arremesso
	var lixo := _cyl(Vector3(1.85, 0.36, -5.2), 0.22, 0.72, METAL_D, 0.25)
	_torus(Vector3(1.85, 0.72, -5.2), 0.22, 0.26, METAL)
	_ball(Vector3(1.82, 0.74, -5.15), 0.08, PAPER)
	_ball(Vector3(1.5, 0.07, -4.7), 0.07, PAPER)
	_ball(Vector3(1.3, 0.07, -5.5), 0.07, PAPER)
	# bebedouro e extintor na parede das janelas
	var beb := _box(Vector3(W - 0.2, 0.75, -7.5), Vector3(0.34, 0.5, 0.5), METAL)
	_box(Vector3(W - 0.2, 1.02, -7.5), Vector3(0.38, 0.06, 0.54), METAL_D, 0.0, 0.0, 0.01)
	_flat(Vector3(W - 0.2, 0.25, -7.5), Vector3(0.12, 0.5, 0.12), METAL_D)
	_flavor(beb, "O bebedouro. Água morna desde a inauguração. A placa diz \"gelada\". Mentira.")
	_cyl(Vector3(W - 0.12, 0.62, -5.3), 0.09, 0.46, RED)
	# placa de chão molhado (o chão está seco)
	var placa := _box(Vector3(-0.7, 0.32, -10.3), Vector3(0.36, 0.62, 0.03), CREAM, 0.5, 0.0, 0.012)
	placa.rotation.x = -0.25
	_flat(Vector3(-0.7, 0.42, -10.31) + Vector3(0.0, 0.0, 0.0), Vector3(0.3, 0.06, 0.035), RED, 0.5).rotation.x = -0.25
	_flavor(placa, "Chão molhado, diz a placa. O chão está seco. A placa está aqui desde março.")
	# porta do fundo acesa
	_flat(Vector3(0, 1.65, -15), Vector3(W * 2, 3.3, 0.1), WALL_L)
	var porta := _box(Vector3(0, 1.1, -14.92), Vector3(1.3, 2.2, 0.06), Color("#33406e"))
	_flat(Vector3(0, 1.6, -14.88), Vector3(0.45, 0.6, 0.02), YEL, 0.0, 3.0, YEL)
	_text(Vector3(0, 2.45, -14.9), "DIRETORIA", 0.2, CREAM, "type")
	var relogio := _cyl(Vector3(0, 2.95, -14.92), 0.2, 0.05, PAPER)
	relogio.rotation.x = PI / 2.0
	_flat(Vector3(0, 3.0, -14.88), Vector3(0.025, 0.14, 0.01), INK)
	_flat(Vector3(0.05, 2.95, -14.88), Vector3(0.11, 0.025, 0.01), INK)
	_flavor(porta, "A porta da diretoria. A luz está acesa. Sempre está.")
	_light(Vector3(0, 1.7, -13.8), WARM, 2.2, 6.0)
	# luminárias de teto, a do meio pisca
	_tube(Vector3(0, 3.22, -2.0), 1.4)
	var pisca := _tube(Vector3(0, 3.22, -7.5), 1.4)
	_tube(Vector3(0, 3.22, -12.0), 1.4)
	_flicker(pisca, _light(Vector3(0, 2.9, -7.5), Color("#cfdcff"), 0.9, 5.0), 1.1)
	# vão com quadro de avisos e mural da banda
	var quadro := _box(Vector3(-W + 0.04, 1.6, -4.6), Vector3(0.06, 1.0, 1.1), WOOD)
	_notes(Vector3(-W + 0.08, 0, 0), false, [[1.8, -4.35, 0.24, 0.3], [1.75, -4.75, 0.24, 0.28, CREAM], [1.4, -4.5, 0.24, 0.3], [1.38, -4.85, 0.2, 0.24, RED]])
	var mural := _box(Vector3(-W + 0.04, 1.5, -5.5), Vector3(0.06, 1.1, 0.7), Color("#26407a"))
	_text(Vector3(-W + 0.09, 1.82, -5.5), "SHOW\nSEXTA", 0.14, CREAM, "marker", PI / 2.0)
	_flat(Vector3(-W + 0.08, 1.35, -5.5), Vector3(0.01, 0.4, 0.4), WALL_L)
	_ball(Vector3(-W + 0.09, 1.38, -5.5), 0.1, INK, Vector3(0.2, 1, 1))
	_light(Vector3(-0.8, 2.4, -4.6), WARM, 0.8, 3.0)
	_anchors = {
		"quadro_avisos": {"mesh": quadro, "say": "Avisos: excursão cancelada, prova adiada, gato perdido. A vida escolar resumida."},
		"mural": {"mesh": mural, "say": "Cartaz de show da banda do grêmio. A arte é melhor que a banda."},
		"celular": {"mesh": cel, "say": "Um celular esquecido no banco. Bloqueado. A tela pisca mensagens de \"cadê vc\"."},
		"armario_aberto": {"mesh": aberto, "say": "Um armário escancarado. Moletom, livro de história e zero pistas. Por enquanto."},
		"lixeira": {"mesh": lixo, "say": "A lixeira. Duas bolinhas de papel erraram o alvo. O time de basquete agradece a ausência."},
	}
	_free_anchors = [{"mesh": banco}, {"pos": Vector3(-W + 0.6, 0.15, -1.0), "size": Vector3(0.3, 0.05, 0.25)}]
	_moon(Vector3(-1.0, -0.6, 0.25), 1.15)
	# piso encerado: reflexo comprido da porta acesa e folhas caídas perto da câmera
	_flat(Vector3(0, 0.004, -10.5), Vector3(0.7, 0.004, 8.0), Color("#c8a868"), 0.0, 0.22, Color("#c8a868"))
	_flat(Vector3(0, 0.003, -12.5), Vector3(0.35, 0.004, 4.0), Color("#e8c070"), 0.0, 0.5, Color("#e8c070"))
	_box(Vector3(-0.5, 0.01, -1.4), Vector3(0.22, 0.01, 0.3), PAPER, 0.5, 0.0, 0.006)
	_box(Vector3(-0.2, 0.01, -1.9), Vector3(0.22, 0.01, 0.3), CREAM, -0.3, 0.0, 0.006)
	_camera(Vector3(0.5, 1.75, 2.8), Vector3(-0.5, 1.15, -5.0), 0.42)


func _scene_biblioteca() -> void:
	_flat(Vector3(0, -0.05, -5), Vector3(10, 0.1, 14), Color("#4a3f6e"))
	# tapete gasto no meio
	_flat(Vector3(0.2, 0.005, -4.6), Vector3(2.6, 0.01, 4.4), Color("#5e3a4e"))
	_flat(Vector3(0.2, 0.01, -4.6), Vector3(2.3, 0.01, 4.1), Color("#6e4a5a"))
	_flat(Vector3(0, 3.6, -5), Vector3(10, 0.1, 14), Color("#241f45"))
	_flat(Vector3(-5, 1.8, -5), Vector3(0.1, 3.6, 14), WALL)
	_flat(Vector3(5, 1.8, -5), Vector3(0.1, 3.6, 14), WALL)
	# parede do fundo: janelão no meio, estantes altas dos dois lados
	_win_wall(true, -11.95, -5.0, 5.0, 3.6, 0.9, 3.1, [[0.4, 2.4]], WALL, -1.0)
	var items := []
	for sx in [-2.8, 3.4]:
		_shelf(Vector3(sx, 0, -11.6), true, 2.6, 3.0, 0.45, 5, WOOD_D)
		_books(Vector3(sx, 0, -11.55), true, 2.5, 5, 0.58, 0.32, int(sx * 10) + 40, items)
	# estante solta à esquerda, de lado para a câmera (lombadas para +X), com escada encostada
	var estante := _shelf(Vector3(-1.9, 0, -6.4), false, 2.6, 2.3, 0.5, 4, WOOD_D)
	_books(Vector3(-1.84, 0, -6.4), false, 2.5, 4, 0.55, 0.34, 21, items)
	_text(Vector3(-1.62, 2.42, -6.4), "FICÇÃO", 0.18, CREAM, "bebas", PI / 2.0)
	for s in [-0.2, 0.2]:
		var rail := _box(Vector3(-1.4, 1.1, -7.0 + s), Vector3(0.04, 2.3, 0.04), WOOD_DD, 0.0, 0.0, 0.01)
		rail.rotation.z = 0.18
	for r in 5:
		var rung := _flat(Vector3(-1.32 - r * 0.075, 0.3 + r * 0.42, -7.0), Vector3(0.03, 0.03, 0.4), WOOD_DD)
		rung.rotation.z = 0.18
	# mesas de estudo com abajures amarelos
	var mesas := []
	for t in 2:
		var tz := -3.4 - t * 3.2
		var tx := -0.2 + t * 1.3
		var mesa := _box(Vector3(tx, 0.75, tz), Vector3(1.8, 0.08, 1.0), WOOD)
		for lx in [-0.8, 0.8]:
			_box(Vector3(tx + lx, 0.37, tz), Vector3(0.08, 0.74, 0.8), WOOD_DD, 0.0, 0.0, 0.0)
		_cyl(Vector3(tx + 0.6, 0.95, tz - 0.3), 0.03, 0.4, NAVY)
		_cyl(Vector3(tx + 0.6, 1.17, tz - 0.3), 0.16, 0.14, YEL, 0.06, 1.2)
		_light(Vector3(tx + 0.6, 1.1, tz - 0.3), WARM, 1.4, 3.0)
		_chair(Vector3(tx - 0.4, 0, tz + 0.75), PI, WOOD_D)
		_chair(Vector3(tx + 0.3, 0, tz - 0.75), 0.15, WOOD_D)
		mesas.append(mesa)
	# mesa 1: livros abertos e lápis; mesa 2: a pasta do grêmio
	_box(Vector3(-0.5, 0.8, -3.3), Vector3(0.42, 0.02, 0.3), PAPER, 0.2, 0.0, 0.008)
	_box(Vector3(-0.1, 0.84, -3.5), Vector3(0.24, 0.1, 0.32), BOOK_COLS[2], -0.3, 0.0, 0.01)
	_flat(Vector3(-0.3, 0.8, -3.15), Vector3(0.16, 0.012, 0.012), YEL, 0.7)
	var pasta := _box(Vector3(0.9, 0.82, -6.5), Vector3(0.34, 0.05, 0.26), RED, -0.2)
	_text(Vector3(0.9, 0.86, -6.5), "GRÊMIO", 0.06, CREAM, "bebas").rotation = Vector3(-PI / 2.0, -0.2, 0)
	# balcão da monitoria à direita: livro de entrada, computador, sino, placa de silêncio
	var balcao := _box(Vector3(1.5, 0.55, -1.2), Vector3(0.7, 1.1, 1.8), WOOD_D)
	_box(Vector3(1.5, 1.12, -1.2), Vector3(0.8, 0.05, 1.9), WOOD, 0.0, 0.0, 0.012)
	var caderno := _box(Vector3(1.4, 1.17, -0.6), Vector3(0.3, 0.04, 0.4), CREAM, 0.3)
	_flat(Vector3(1.4, 1.195, -0.6), Vector3(0.01, 0.01, 0.38), INK, 0.3)
	var pc := _box(Vector3(1.6, 1.42, -1.55), Vector3(0.05, 0.36, 0.5), INK, -0.35)
	_flat(Vector3(1.575, 1.42, -1.54), Vector3(0.01, 0.3, 0.44), Color("#6fd3ff"), -0.35, 1.5, Color("#6fd3ff"))
	_flat(Vector3(1.65, 1.2, -1.55), Vector3(0.12, 0.12, 0.08), INK)
	_cyl(Vector3(1.35, 1.19, -1.9), 0.06, 0.06, Color("#c9a24a"), 0.02)
	var placa := _box(Vector3(1.6, 1.3, -2.05), Vector3(0.04, 0.2, 0.42), PAPER, 0.0, 0.0, 0.01)
	_text(Vector3(1.57, 1.3, -2.05), "SILÊNCIO", 0.08, INK, "type", -PI / 2.0)
	_flavor(placa, "Uma placa: \"Silêncio, por favor\". Alguém escreveu embaixo: \"tá ligado??\"")
	# globo e carrinho de devolução
	_cyl(Vector3(-3.2, 0.4, -2.6), 0.05, 0.8, WOOD_DD)
	var globo := _ball(Vector3(-3.2, 1.0, -2.6), 0.26, TEAL)
	_torus(Vector3(-3.2, 1.0, -2.6), 0.27, 0.3, Color("#c9a24a"), Vector3(0, 0, 0.4))
	_flavor(globo, "O globo ainda tem a URSS. A bibliotecária jura que é peça vintage.")
	var carrinho := _box(Vector3(2.6, 0.55, -5.2), Vector3(0.5, 0.06, 1.0), METAL_D)
	_box(Vector3(2.6, 0.2, -5.2), Vector3(0.5, 0.06, 1.0), METAL_D, 0.0, 0.0, 0.01)
	for cz in [-5.65, -4.75]:
		_flat(Vector3(2.6, 0.4, cz), Vector3(0.04, 0.8, 0.04), METAL)
	_books(Vector3(2.6, 0.55, -5.2), false, 0.95, 1, 0.4, 0.3, 77, items)
	_flavor(carrinho, "Carrinho de devolução. Um livro atrasado desde 2019. A multa já virou lenda.")
	_mm(items)
	_anchors = {
		"caderno_entrada": {"mesh": caderno, "say": "O caderno de entrada. Metade dos nomes é \"Batman\"."},
		"pasta_gremio": {"mesh": pasta, "say": "A pasta do grêmio. Atas, rifas e um adesivo de unicórnio."},
		"computador": {"mesh": pc, "say": "O computador da biblioteca. Mesmo papel de parede desde 2015."},
		"estante": {"mesh": estante, "say": "Ficção. Alguém escondeu um mangá dentro de um livro de química. Clássico."},
		"mesa_estudo": {"mesh": mesas[0], "say": "Riscado na mesa: \"Prova de mat. é sexta?? socorro\". Atemporal."},
	}
	_free_anchors = [{"pos": Vector3(0.4, 0.82, -6.2), "size": Vector3(0.3, 0.05, 0.25)}, {"pos": Vector3(-2.8, 0.1, -1.4), "size": Vector3(0.3, 0.15, 0.3)}]
	_moon(Vector3(0.3, -0.7, 1.0), 0.9)
	_light(Vector3(0.4, 2.2, -10.6), Color("#9fb8ff"), 1.0, 4.5)
	# pilha de livros no chão perto da câmera, esperando alguém guardar
	for b in 4:
		_box(Vector3(-0.55, 0.05 + b * 0.09, -0.5), Vector3(0.34 - b * 0.03, 0.08, 0.26), BOOK_COLS[b + 1], b * 0.35 - 0.4, 0.0, 0.01)
	_camera(Vector3(0.7, 2.3, 2.8), Vector3(0.1, 0.9, -4.4), 0.5)


func _scene_teatro() -> void:
	_flat(Vector3(0, -0.05, -4), Vector3(12, 0.1, 15), Color("#4e3a52"))
	_flat(Vector3(0, 6.0, -4), Vector3(12, 0.1, 15), INK)
	_flat(Vector3(-5.5, 3, -4), Vector3(0.1, 6, 15), WALL)
	_flat(Vector3(5.5, 3, -4), Vector3(0.1, 6, 15), WALL)
	# palco elevado: tábuas, ribalta e boca de cena com cortina vermelha (o acento quente do lugar)
	_box(Vector3(0, 0.45, -7.6), Vector3(9, 0.9, 4.2), WOOD_D)
	for p in 6:
		_flat(Vector3(-3.75 + p * 1.5, 0.905, -7.6), Vector3(0.02, 0.005, 4.2), WOOD_DD)
	_flat(Vector3(0, 0.45, -5.48), Vector3(9, 0.9, 0.02), WOOD_DD)
	for f in 7:
		_cyl(Vector3(-2.7 + f * 0.9, 0.95, -5.65), 0.08, 0.08, CREAM, 0.05, 1.5)
	_flat(Vector3(0, 3, -9.7), Vector3(11, 6, 0.1), NAVY)
	# cenário pintado ao fundo: lua de papelão e cidade recortada
	var lua := _cyl(Vector3(-1.6, 3.6, -9.55), 0.75, 0.05, CREAM, -1.0, 0.35)
	lua.rotation.x = PI / 2.0
	_flavor(lua, "A lua do cenário. Papelão, cola quente e muita fé.")
	for b in [[-3.6, 1.6, 1.0], [-2.5, 2.4, 0.8], [-1.5, 1.3, 1.0], [-0.3, 2.9, 0.9], [0.9, 1.8, 1.1], [2.1, 2.5, 0.8], [3.2, 1.5, 1.2]]:
		_box(Vector3(b[0], 0.9 + b[1] * 0.5, -9.5), Vector3(b[2], b[1], 0.06), Color("#26335f"), 0.0, 0.0, 0.015)
		_flat(Vector3(b[0] + 0.15, 0.9 + b[1] * 0.7, -9.46), Vector3(0.14, 0.18, 0.01), Color("#a8873d"))
	var cortina: MeshInstance3D
	for side in [-1, 1]:
		var cort := _box(Vector3(side * 3.3, 3.0, -5.6), Vector3(1.6, 4.8, 0.25), RED_D)
		for f in 5:
			_flat(Vector3(side * (2.65 + f * 0.32), 3.0, -5.45), Vector3(0.06, 4.8, 0.06), Color("#5e1a2a"))
		if side == -1:
			cortina = cort
		# cordão dourado prendendo a cortina
		_torus(Vector3(side * 2.55, 2.0, -5.45), 0.06, 0.1, Color("#c9a24a"), Vector3(0, 0, PI / 2.0))
	_box(Vector3(0, 5.3, -5.6), Vector3(9, 0.9, 0.3), RED_D)
	for f in 9:
		_flat(Vector3(-4.0 + f * 1.0, 4.8, -5.42), Vector3(0.5, 0.12, 0.02), Color("#5e1a2a"))
	# trono de papelão sob o holofote, com o facho visível no ar
	var trono := _box(Vector3(0.7, 1.35, -7.8), Vector3(0.9, 0.9, 0.7), Color("#a8873d"))
	_box(Vector3(0.7, 2.2, -8.1), Vector3(0.9, 1.2, 0.12), Color("#a8873d"))
	for c in 3:
		_box(Vector3(0.4 + c * 0.3, 2.9, -8.1), Vector3(0.14, 0.24, 0.1), Color("#a8873d"), 0.0, 0.0, 0.01)
	_box(Vector3(0.7, 1.82, -7.75), Vector3(0.8, 0.06, 0.6), RED_D, 0.0, 0.0, 0.01)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0.7, 5.6, -4.6)
	spot.light_color = Color("#ffd27a")
	spot.light_energy = 3.2
	spot.spot_range = 10.0
	spot.spot_angle = 20.0
	world.add_child(spot)
	spot.look_at(Vector3(0.7, 0.9, -7.8), Vector3.UP)
	_beam(Vector3(0.7, 5.6, -4.6), Vector3(0.7, 0.92, -7.8), 0.08, 1.1, Color("#ffd27a"), 0.035)
	_cyl(Vector3(0.7, 5.7, -4.5), 0.16, 0.35, INK)
	# arara de figurinos no palco
	var arara := _box(Vector3(-1.7, 2.6, -7.4), Vector3(1.4, 0.05, 0.05), METAL, 0.0, 0.0, 0.012)
	for s in [-0.7, 0.7]:
		_flat(Vector3(-1.7 + s, 1.75, -7.4), Vector3(0.05, 1.7, 0.05), METAL)
		_flat(Vector3(-1.7 + s, 0.92, -7.4), Vector3(0.05, 0.03, 0.5), METAL_D)
	var roupas := [[-2.2, 0.9, Color("#26407a")], [-1.9, 1.1, RED_D], [-1.55, 0.8, Color("#4f7a5a")], [-1.25, 1.3, INK]]
	for r in roupas:
		_box(Vector3(r[0], 2.55 - r[1] * 0.5, -7.4), Vector3(0.24, r[1], 0.32), r[2], 0.0, 0.0, 0.012)
	# caixa de objetos de cena na beira do palco: espada de madeira e máscara
	var caixa := _box(Vector3(-1.95, 1.2, -6.2), Vector3(0.8, 0.6, 0.6), Color("#a07a4a"))
	_box(Vector3(-1.9, 1.6, -6.2), Vector3(0.06, 0.9, 0.06), Color("#c9bfa6"), 0.0, 0.0, 0.01).rotation.z = 0.4
	_ball(Vector3(-2.15, 1.56, -6.1), 0.14, CREAM, Vector3(1, 1, 0.4))
	_flat(Vector3(-1.95, 1.2, -5.89), Vector3(0.5, 0.12, 0.01), INK)
	# quadro de ensaio no cavalete, no chão à direita
	var quadro := _box(Vector3(2.4, 1.5, -4.5), Vector3(1.0, 0.8, 0.05), BOARD, -0.3)
	_text(Vector3(2.4, 1.6, -4.46), "ENSAIO GERAL\nSEXTA 19H", 0.12, CREAM, "marker", -0.3)
	for lx in [-0.35, 0.35]:
		var perna := _box(Vector3(2.4 + lx * 0.95, 0.75, -4.5 + lx * 0.3), Vector3(0.05, 1.6, 0.05), WOOD_DD, -0.3, 0.0, 0.01)
		perna.rotation.x = -0.12
	# plateia: fileiras de poltronas
	for r in 3:
		for c in 6:
			var cx := -2.5 + c * 1.0
			var cz := -2.6 + r * 1.2
			var assento := _box(Vector3(cx, 0.45, cz), Vector3(0.66, 0.12, 0.6), Color("#94485f"), 0.0, 0.0, 0.015)
			_box(Vector3(cx, 0.78, cz + 0.28), Vector3(0.66, 0.56, 0.1), Color("#94485f"), 0.0, 0.0, 0.015)
			if r == 0 and c == 4:
				_flavor(assento, "Poltrona 12F. Tem um chiclete aqui de uma estreia antiga.")
	# escada do iluminador e saco de areia
	var escada := _box(Vector3(4.3, 1.8, -6.6), Vector3(0.06, 3.6, 0.6), METAL, 0.0, 0.0, 0.012)
	escada.rotation.z = -0.1
	for r in 7:
		_flat(Vector3(4.3 + r * 0.04 - 0.15, 0.3 + r * 0.48, -6.6), Vector3(0.05, 0.03, 0.55), METAL_D)
	_flavor(escada, "A escada do iluminador. \"Proibido subir\" está escrito no terceiro degrau.")
	var saco := _ball(Vector3(3.6, 1.1, -6.4), 0.22, Color("#8a7a5a"), Vector3(1, 0.8, 1))
	_flavor(saco, "Um saco de areia. Segura o cenário. E segura a ansiedade do diretor, dizem.")
	_flat(Vector3(-5.44, 2.6, -2.4), Vector3(0.02, 0.5, 1.2), Color("#26407a"))
	_light(Vector3(-2.0, 2.4, -6.0), WARM, 1.0, 3.5)
	_light(Vector3(0, 1.4, -4.0), Color("#ffb070"), 0.9, 4.0)
	_anchors = {
		"caixa_props": {"mesh": caixa, "say": "Caixa de objetos de cena. Espada de madeira, máscara e zero coroas."},
		"quadro_teatro": {"mesh": quadro, "say": "\"Ensaio geral sexta\". Alguém sublinhou três vezes. Tensão."},
		"trono": {"mesh": trono, "say": "O trono do rei. É papelão pintado. A coroa sumiu faz duas peças."},
		"arara_figurino": {"mesh": arara, "say": "Arara de figurinos. Uma capa de vampiro, um bigode falso e... uma meia?"},
		"cortina": {"mesh": cortina, "say": "A cortina do teatro. Se você puxar, sai uma nuvem de poeira e um grilo."},
	}
	_free_anchors = [{"pos": Vector3(-0.8, 1.0, -6.6), "size": Vector3(0.4, 0.2, 0.3)}, {"pos": Vector3(2.4, 1.0, -7.0), "size": Vector3(0.3, 0.3, 0.3)}]
	_moon(Vector3(0.6, -0.8, -0.4), 0.55)
	for r in 4:
		for sx in [-3.15, 3.15]:
			_flat(Vector3(sx, 0.03, -3.2 + r * 1.2), Vector3(0.12, 0.05, 0.08), WARM, 0.0, 1.6, WARM)
	_light(Vector3(0, 3.2, -1.2), Color("#ffb070"), 0.7, 5.0)
	_camera(Vector3(0.0, 3.3, 5.2), Vector3(0.0, 1.25, -6.0), 0.5)


func _scene_sala_aula() -> void:
	_flat(Vector3(0, -0.05, -3), Vector3(7, 0.1, 10), Color("#55618f"))
	for i in 5:
		_flat(Vector3(0, 0.003, -7 + i * 2.0), Vector3(7, 0.005, 0.03), Color("#46528a"))
	_flat(Vector3(0, 3.2, -3), Vector3(7, 0.1, 10), CEIL)
	_flat(Vector3(0, 1.6, -7.55), Vector3(7, 3.2, 0.1), WALL_L)
	_flat(Vector3(3.5, 1.6, -3), Vector3(0.1, 3.2, 10), WALL_M)
	_flat(Vector3(3.44, 0.06, -3), Vector3(0.02, 0.12, 10), NAVY)
	# janelas à esquerda com chuva; a do meio está aberta (vidro deslizado) e molhou o peitoril
	var ledges := _win_wall(false, -3.5, -8.0, 2.0, 3.2, 0.95, 2.6, [[-5.6, 1.8], [-3.0, 1.8], [-0.4, 1.8]], WALL_M, -1.0)
	var janela := _box(Vector3(-3.42, 1.75, -2.6), Vector3(0.05, 1.5, 0.95), Color("#7d9be0"), 0.0, 0.25, 0.012, Color("#7d9be0"))
	_disc(Vector3(-3.2, 0.006, -3.0), 0.5, Color("#0e1a40"), Vector3(0.8, 1, 1.3))
	# lousa: verde-escura, moldura de madeira, escrita em giz e marcas de apagador
	var lousa := _box(Vector3(-0.4, 1.65, -7.47), Vector3(4.4, 1.35, 0.06), BOARD)
	_flat(Vector3(-0.4, 0.95, -7.42), Vector3(4.4, 0.05, 0.12), WOOD)
	_flat(Vector3(-1.9, 1.85, -7.435), Vector3(0.9, 0.35, 0.005), Color("#2c4a3c"))
	_flat(Vector3(0.9, 1.35, -7.435), Vector3(1.1, 0.25, 0.005), Color("#2c4a3c"))
	_text(Vector3(-0.9, 2.05, -7.43), "PROVA SEXTA!!", 0.26, Color(0.92, 0.94, 0.86, 0.95))
	_text(Vector3(-1.2, 1.55, -7.43), "x² + 3x - 4 = 0\nΔ = b² - 4ac", 0.16, Color(0.86, 0.9, 0.82, 0.9))
	_text(Vector3(1.0, 1.75, -7.43), "NÃO APAGAR", 0.13, Color(0.86, 0.9, 0.82, 0.9))
	_flat(Vector3(1.0, 1.66, -7.435), Vector3(0.7, 0.015, 0.005), CREAM)
	_flat(Vector3(0.6, 0.99, -7.38), Vector3(0.22, 0.05, 0.08), INK)
	_flat(Vector3(-1.4, 0.98, -7.38), Vector3(0.08, 0.02, 0.02), PAPER)
	# relógio e cartaz
	var relogio := _cyl(Vector3(2.2, 2.7, -7.48), 0.22, 0.05, PAPER)
	relogio.rotation.x = PI / 2.0
	_flat(Vector3(2.2, 2.74, -7.44), Vector3(0.025, 0.15, 0.01), INK)
	_flat(Vector3(2.15, 2.7, -7.44), Vector3(0.12, 0.025, 0.01), INK)
	_flavor(relogio, "O relógio da sala. Atrasado ou adiantado, ninguém nunca soube.")
	var cartaz := _box(Vector3(3.44, 1.9, -5.0), Vector3(0.02, 0.8, 0.6), CREAM, 0.0, 0.0, 0.01)
	_text(Vector3(3.42, 2.05, -5.0), "CELULAR\nNA MOCHILA", 0.08, RED_D, "marker", -PI / 2.0)
	_flavor(cartaz, "\"Celular na mochila\". Escrito à mão por alguém que perdeu essa guerra.")
	# mesa do professor: provas, maçã, caneca, caneta vermelha
	var mesa := _box(Vector3(-1.4, 0.76, -6.2), Vector3(1.5, 0.06, 0.75), WOOD)
	_box(Vector3(-1.4, 0.38, -6.5), Vector3(1.4, 0.72, 0.06), WOOD_D, 0.0, 0.0, 0.0)
	_box(Vector3(-0.85, 0.38, -6.2), Vector3(0.4, 0.72, 0.65), WOOD_D, 0.0, 0.0, 0.012)
	_box(Vector3(-1.7, 0.83, -6.15), Vector3(0.32, 0.08, 0.24), PAPER, 0.1, 0.0, 0.008)
	_ball(Vector3(-1.2, 0.86, -6.05), 0.07, RED)
	_cyl(Vector3(-0.9, 0.85, -6.3), 0.05, 0.12, TEAL)
	_flat(Vector3(-1.5, 0.8, -5.95), Vector3(0.14, 0.012, 0.012), RED, 0.4)
	_chair(Vector3(-1.4, 0, -6.95), 0.0, WOOD_D)
	# carteiras em fileiras; a do fundo, perto da câmera, tem coração riscado
	var fundo: MeshInstance3D
	for r in 3:
		for c in 3:
			var p := Vector3(-2.2 + c * 1.35, 0, -4.4 + r * 1.55)
			var top := _desk(p)
			if r == 2 and c == 2:
				fundo = top
				_text(p + Vector3(0, 0.765, 0.05), "J + ? <3", 0.07, CREAM, "marker").rotation = Vector3(-PI / 2.0, 0, 0)
			elif r == 0 and c == 1:
				_box(p + Vector3(0.1, 0.78, 0), Vector3(0.22, 0.02, 0.1), PAPER, 0.6, 0.0, 0.006)   # avião de papel
	var aviao := _box(Vector3(0.6, 0.03, -1.0), Vector3(0.24, 0.03, 0.12), PAPER, 0.9, 0.0, 0.008)
	_flavor(aviao, "Um avião de papel. Pousou mal. Piloto não identificado.")
	# mochila no chão ao lado da carteira do fundo
	var mochila := _box(Vector3(1.2, 0.22, -0.95), Vector3(0.34, 0.44, 0.22), Color("#4f7a5a"), -0.3)
	_box(Vector3(1.23, 0.15, -0.83), Vector3(0.26, 0.2, 0.06), Color("#3d6a4a"), -0.3, 0.0, 0.01)
	_torus(Vector3(1.2, 0.46, -0.95), 0.05, 0.08, INK, Vector3(PI / 2.0, -0.3, 0))
	var lixo := _cyl(Vector3(2.9, 0.3, -6.6), 0.2, 0.6, METAL_D, 0.22)
	_ball(Vector3(2.9, 0.62, -6.6), 0.09, PAPER)
	_flavor(lixo, "Lixeira cheia de rascunhos de redação sobre \"o futuro\". Ninguém passou do título.")
	_tube(Vector3(-0.5, 3.12, -5.0), 1.6, true)
	_tube(Vector3(-0.5, 3.12, -1.5), 1.6, true)
	# porta entreaberta à direita: luz amarela do corredor entrando no chão
	_flat(Vector3(3.43, 1.05, -0.5), Vector3(0.04, 2.1, 1.0), Color("#33406e"))
	_flat(Vector3(2.9, 0.004, -0.6), Vector3(1.1, 0.005, 0.5), Color("#e8c070"), 0.0, 0.5, Color("#e8c070"))
	_light(Vector3(2.8, 1.6, -0.6), WARM, 1.2, 3.5)
	_light(Vector3(-1.2, 2.2, -5.6), Color("#cfdcff"), 0.8, 4.0)
	_anchors = {
		"lousa": {"mesh": lousa, "say": "A lousa. \"Prova sexta\" com dois pontos de exclamação. O professor quis ser claro."},
		"mesa_professor": {"mesh": mesa, "say": "A mesa do professor. Uma maçã. Alguém ainda acredita nisso."},
		"carteira_fundo": {"mesh": fundo, "say": "A carteira do fundo. Um coração riscado com um \"?\". Mistério de outro caso."},
		"mochila": {"mesh": mochila, "say": "Uma mochila esquecida. Pesa como se carregasse a matéria do ano inteiro."},
		"janela": {"mesh": janela, "say": "A janela ficou aberta. A chuva entrou para assistir à aula."},
	}
	_free_anchors = [{"mesh": ledges[0]}, {"pos": Vector3(0.0, 0.8, -4.4), "size": Vector3(0.3, 0.04, 0.25)}]
	_moon(Vector3(0.9, -0.6, -0.3), 1.0)
	_camera(Vector3(1.6, 2.5, 2.6), Vector3(-0.5, 0.95, -4.8), 0.45)


func _scene_cantina() -> void:
	for i in 5:
		for j in 4:
			_flat(Vector3(-3 + j * 2.0, -0.05, -7.0 + i * 2.0), Vector3(2.0, 0.1, 2.0), Color("#5d6f9e") if (i + j) % 2 == 0 else Color("#506094"))
	_flat(Vector3(0, 3.2, -3), Vector3(8, 0.1, 11), CEIL)
	_flat(Vector3(-4, 1.6, -3), Vector3(0.1, 3.2, 11), WALL_M)
	_flat(Vector3(4, 1.6, -3), Vector3(0.1, 3.2, 11), WALL_M)
	_flat(Vector3(0, 1.6, -8.05), Vector3(8, 3.2, 0.1), WALL_L)
	# azulejo até meia altura na parede da cozinha
	_flat(Vector3(0, 0.7, -7.98), Vector3(8, 1.4, 0.04), Color("#8a9ac0"))
	for i in 8:
		_flat(Vector3(-3.5 + i * 1.0, 0.7, -7.955), Vector3(0.02, 1.4, 0.01), Color("#6d7fb0"))
	# balcão com vidro de proteção, cubas, bandejas empilhadas
	var balcao := _box(Vector3(-0.4, 0.5, -6.4), Vector3(3.6, 1.0, 0.8), METAL_D)
	_box(Vector3(-0.4, 1.02, -6.4), Vector3(3.7, 0.05, 0.9), METAL, 0.0, 0.0, 0.012)
	_flat(Vector3(-0.4, 1.7, -6.05), Vector3(3.5, 0.03, 0.03), METAL)
	for gx in [-2.1, -0.4, 1.3]:
		_flat(Vector3(gx, 1.36, -6.05), Vector3(0.03, 0.68, 0.03), METAL)
	for cx in [-1.7, -0.9, -0.1, 0.7]:
		_flat(Vector3(cx, 1.03, -6.5), Vector3(0.65, 0.04, 0.45), INK)
	_flat(Vector3(-1.7, 1.05, -6.5), Vector3(0.55, 0.02, 0.35), Color("#c9bfa6"))
	_flat(Vector3(-0.9, 1.05, -6.5), Vector3(0.55, 0.02, 0.35), Color("#8a5a3e"))
	_flat(Vector3(-0.1, 1.05, -6.5), Vector3(0.55, 0.02, 0.35), Color("#4f7a5a"))
	for t in 5:
		_flat(Vector3(1.25, 1.07 + t * 0.03, -6.3), Vector3(0.45, 0.02, 0.32), Color("#a05a4a") if t % 2 == 0 else Color("#8a4a3e"))
	# cardápio no quadro preto acima do balcão
	var cardapio := _box(Vector3(-0.6, 2.35, -7.97), Vector3(2.4, 1.1, 0.05), INK)
	_flat(Vector3(-0.6, 2.35, -7.95), Vector3(2.5, 1.2, 0.02), WOOD)
	_text(Vector3(-0.6, 2.75, -7.92), "CARDÁPIO", 0.2, CREAM, "bebas")
	_text(Vector3(-0.6, 2.25, -7.92), "SEG  arroz e feijão\nTER  feijão e arroz\nQUA  surpresa (?)", 0.11, Color(0.86, 0.9, 0.82), "type")
	# geladeira de bebidas com porta de vidro acesa
	var gel := _box(Vector3(2.9, 1.0, -7.4), Vector3(1.0, 2.0, 0.8), Color("#c9d2e8"))
	_flat(Vector3(2.9, 1.05, -6.99), Vector3(0.8, 1.6, 0.02), Color("#cfe8ff"), 0.0, 0.7, Color("#cfe8ff"))
	var bottles := []
	for r in 4:
		for c in 6:
			bottles.append([Vector3(2.6 + c * 0.12, 0.42 + r * 0.38, -7.05), Vector3(0.07, 0.24, 0.07), BOOK_COLS[(r * 3 + c) % 5]])
	_mm(bottles)
	_flat(Vector3(2.9, 1.95, -6.98), Vector3(0.8, 0.12, 0.02), RED)
	_light(Vector3(2.9, 1.2, -6.4), Color("#d8ecff"), 1.0, 2.8)
	# coluna com o mural da cantina
	_box(Vector3(-2.4, 1.6, -3.6), Vector3(0.5, 3.2, 0.5), WALL_L, 0.0, 0.0, 0.0)
	var mural := _box(Vector3(-2.4, 1.6, -3.33), Vector3(0.45, 0.7, 0.04), WOOD, 0.0, 0.0, 0.012)
	_notes(Vector3(-2.4, 0, -3.3), true, [[1.75, -0.1, 0.16, 0.2], [1.72, 0.1, 0.14, 0.18, CREAM], [1.45, 0.05, 0.22, 0.16, RED]])
	# mesas compridas; numa delas as cadeiras estão viradas para a faxina
	var bandeja: MeshInstance3D
	var viradas: MeshInstance3D
	for t in 2:
		var tz := -1.6 - t * 2.6
		var tx := 0.6 - t * 0.4
		var mesa := _box(Vector3(tx, 0.74, tz), Vector3(2.4, 0.06, 0.8), WOOD)
		for lx in [-1.0, 1.0]:
			_flat(Vector3(tx + lx, 0.37, tz), Vector3(0.06, 0.72, 0.6), METAL_D)
		if t == 0:
			for s in [-1, 1]:
				_box(Vector3(tx, 0.44, tz + s * 0.65), Vector3(2.2, 0.05, 0.3), WOOD_D, 0.0, 0.0, 0.012)
				_flat(Vector3(tx, 0.22, tz + s * 0.65), Vector3(1.9, 0.42, 0.04), METAL_D)
			bandeja = _box(Vector3(tx - 0.3, 0.79, tz + 0.1), Vector3(0.46, 0.03, 0.32), Color("#a05a4a"), 0.15, 0.0, 0.01)
			_cyl(Vector3(tx - 0.35, 0.82, tz + 0.08), 0.11, 0.02, PAPER)
			_ball(Vector3(tx - 0.33, 0.85, tz + 0.08), 0.04, Color("#6a3e2e"))
			_box(Vector3(tx - 0.12, 0.86, tz + 0.15), Vector3(0.07, 0.12, 0.05), Color("#e0a040"), 0.15, 0.0, 0.008)
			_flat(Vector3(tx - 0.11, 0.95, tz + 0.15), Vector3(0.01, 0.08, 0.01), RED)
		else:
			for c in 3:
				var ch := _box(Vector3(tx - 0.8 + c * 0.8, 1.02, tz), Vector3(0.42, 0.05, 0.4), RED_D, 0.0, 0.0, 0.012)
				_box(Vector3(tx - 0.8 + c * 0.8, 1.28, tz + 0.19), Vector3(0.42, 0.04, 0.3), RED_D, 0.0, 0.0, 0.012).rotation.x = 0.2
				for lx in [-0.18, 0.18]:
					_flat(Vector3(tx - 0.8 + c * 0.8 + lx, 1.25, tz - 0.15), Vector3(0.025, 0.45, 0.025), METAL)
				if c == 1:
					viradas = ch
	_flavor(viradas, "Cadeiras de pernas pro ar. A faxina passou. Ou foi um protesto.")
	# esfregão e balde, porta-guardanapo, cartaz da fruta
	var balde := _cyl(Vector3(2.4, 0.18, -2.8), 0.18, 0.36, Color("#e0a040"), 0.2)
	_flat(Vector3(2.5, 0.7, -2.85), Vector3(0.03, 1.4, 0.03), WOOD).rotation.z = -0.25
	_flavor(balde, "O esfregão e o balde. Testemunhas silenciosas de todo suco derramado.")
	var guard := _box(Vector3(1.0, 0.84, -1.55), Vector3(0.12, 0.14, 0.1), METAL, 0.0, 0.0, 0.008)
	_flavor(guard, "O porta-guardanapo. Vazio. Como sempre que você precisa.")
	var fruta := _box(Vector3(3.94, 1.8, -4.5), Vector3(0.02, 0.8, 0.6), CREAM, 0.0, 0.0, 0.01)
	_text(Vector3(3.92, 2.05, -4.5), "COMA\nFRUTAS!", 0.09, RED_D, "marker", -PI / 2.0)
	_ball(Vector3(3.91, 1.65, -4.5), 0.12, Color("#e0c040"), Vector3(0.1, 0.6, 1.4))
	_flavor(fruta, "\"Coma frutas!\". A banana desenhada parece estar com medo.")
	# luminárias pendentes sobre o balcão
	for lx in [-1.4, 0.6]:
		_flat(Vector3(lx, 2.75, -6.2), Vector3(0.01, 0.9, 0.01), INK)
		_cyl(Vector3(lx, 2.25, -6.2), 0.28, 0.2, NAVY, 0.08)
		_cyl(Vector3(lx, 2.14, -6.2), 0.2, 0.02, YEL, -1.0, 1.4)
	_light(Vector3(-0.4, 2.0, -6.0), WARM, 1.6, 4.0)
	_anchors = {
		"balcao": {"mesh": balcao, "say": "O balcão. Arroz frio e a lembrança de um pastel que nunca veio."},
		"cardapio": {"mesh": cardapio, "say": "O cardápio. Quarta é \"surpresa\". Ninguém quer descobrir."},
		"bandeja": {"mesh": bandeja, "say": "Uma bandeja abandonada com meia almôndega. A outra metade fugiu."},
		"geladeira": {"mesh": gel, "say": "A geladeira de sucos. Zumbe a noite toda como quem guarda segredo."},
		"mural_cantina": {"mesh": mural, "say": "Mural da cantina: \"Proibido guardar lugar\". Escrito com raiva."},
	}
	_free_anchors = [{"pos": Vector3(0.9, 0.8, -1.4), "size": Vector3(0.3, 0.05, 0.25)}, {"pos": Vector3(-1.0, 0.8, -4.2), "size": Vector3(0.3, 0.05, 0.25)}]
	_moon(Vector3(-0.6, -0.7, -0.4), 0.8)
	_camera(Vector3(0.4, 2.6, 2.8), Vector3(-0.2, 0.95, -5.5), 0.45)


func _scene_patio() -> void:
	_sky(Color("#070e26"), Color("#24386e"), 0.8, Color("#101c40"), 0.03)
	_flat(Vector3(0, -0.05, -6), Vector3(26, 0.1, 26), Color("#3a4a7a"))
	for i in 7:
		_flat(Vector3(0, 0.002, 2.0 - i * 2.4), Vector3(26, 0.004, 0.04), Color("#2e3c6a"))
	# prédio da escola ao fundo: janelas apagadas, uma acesa
	_flat(Vector3(0, 3.5, -13), Vector3(20, 7, 0.4), WALL)
	_flat(Vector3(0, 7.1, -12.9), Vector3(20.4, 0.25, 0.7), WALL_L)
	for f in 2:
		for c in 7:
			var lit := f == 1 and c == 4
			_flat(Vector3(-6 + c * 2.0, 1.8 + f * 3.0, -12.78), Vector3(1.1, 1.3, 0.05), YEL if lit else Color("#1e2c5a"), 0.0, 1.6 if lit else 0.0, YEL)
			_flat(Vector3(-6 + c * 2.0, 1.1 + f * 3.0, -12.72), Vector3(1.3, 0.08, 0.15), WALL_L)
	var janela_acesa := _flat(Vector3(2.0, 4.8, -12.76), Vector3(1.1, 1.3, 0.01), YEL, 0.0, 1.6, YEL)
	_flat(Vector3(2.0, 4.8, -12.7), Vector3(0.05, 1.3, 0.03), INK)
	_flat(Vector3(2.0, 4.95, -12.7), Vector3(1.1, 0.05, 0.03), INK)
	_flavor(janela_acesa, "Uma janela acesa no segundo andar. Alguém ainda está lá dentro. Ou esqueceram a luz.")
	_moon_disc(Vector3(-3.6, 12.5, -24.0), 1.1)
	# muros laterais
	_flat(Vector3(-6.5, 1.2, -5), Vector3(0.3, 2.4, 16), WALL_M)
	_flat(Vector3(6.5, 1.2, -5), Vector3(0.3, 2.4, 16), WALL_M)
	# poste com luz amarela, facho na chuva e tênis pendurado no fio
	var poste := _cyl(Vector3(1.9, 1.9, -4.6), 0.08, 3.8, METAL_D, 0.06)
	_box(Vector3(1.6, 3.8, -4.6), Vector3(0.7, 0.08, 0.12), METAL_D, 0.0, 0.0, 0.012)
	_cyl(Vector3(1.3, 3.72, -4.6), 0.18, 0.12, INK, 0.1)
	_cyl(Vector3(1.3, 3.65, -4.6), 0.13, 0.03, YEL, -1.0, 2.5)
	var luz := SpotLight3D.new()
	luz.position = Vector3(1.3, 3.6, -4.6)
	luz.light_color = Color("#ffcf70")
	luz.light_energy = 3.5
	luz.spot_range = 7.0
	luz.spot_angle = 38.0
	world.add_child(luz)
	luz.look_at(Vector3(1.2, 0, -4.4), Vector3(0, 0, -1))
	_beam(Vector3(1.3, 3.6, -4.6), Vector3(1.2, 0.0, -4.4), 0.1, 1.9, Color("#ffcf70"), 0.07)
	_flat(Vector3(-1.5, 4.3, -4.6), Vector3(7, 0.015, 0.015), INK)
	var tenis := _box(Vector3(-0.8, 4.05, -4.6), Vector3(0.12, 0.1, 0.26), CREAM, 0.3, 0.0, 0.01)
	_box(Vector3(-0.6, 3.95, -4.6), Vector3(0.12, 0.1, 0.26), CREAM, -0.4, 0.0, 0.01)
	_flavor(tenis, "Um par de tênis pendurado no fio. A lenda diz que é de um aluno de 2009.")
	# banco de praça sob a luz, com guarda-chuva esquecido
	var banco := _box(Vector3(0.9, 0.45, -5.2), Vector3(1.6, 0.06, 0.45), WOOD)
	_box(Vector3(0.9, 0.78, -5.42), Vector3(1.6, 0.3, 0.05), WOOD, 0.0, 0.0, 0.012)
	for lx in [-0.65, 0.65]:
		_flat(Vector3(0.9 + lx, 0.22, -5.2), Vector3(0.06, 0.44, 0.4), INK)
	var guarda := _box(Vector3(1.4, 0.55, -5.15), Vector3(0.06, 0.06, 0.8), RED_D, 0.6, 0.0, 0.01)
	guarda.rotation.x = -0.15
	_flavor(guarda, "Um guarda-chuva esquecido. Na chuva. A ironia dói.")
	# árvore com canteiro redondo
	var arvore := _cyl(Vector3(-2.6, 1.3, -7.0), 0.18, 2.6, WOOD_DD, 0.13)
	_cyl(Vector3(-2.6, 0.18, -7.0), 0.9, 0.36, WALL_L)
	_cyl(Vector3(-2.6, 0.37, -7.0), 0.8, 0.02, Color("#2a2a3e"))
	for b in [[0, 3.1, 0, 1.2], [-0.7, 2.7, 0.2, 0.85], [0.7, 2.8, -0.2, 0.9], [0.1, 3.7, 0.1, 0.8], [-0.3, 2.6, 0.7, 0.7]]:
		_ball(Vector3(-2.6 + b[0], b[1], -7.0 + b[2]), b[3], LEAF)
	# bicicletário com uma bicicleta sem roda da frente
	var bici := _box(Vector3(-1.9, 0.35, -2.8), Vector3(1.6, 0.05, 0.05), METAL, 0.0, 0.0, 0.01)
	for i in 4:
		_torus(Vector3(-2.5 + i * 0.4, 0.38, -2.8), 0.16, 0.19, METAL, Vector3(0, PI / 2.0, PI / 2.0))
	_torus(Vector3(-1.7, 0.33, -2.45), 0.26, 0.3, INK, Vector3(0, PI / 2.0, PI / 2.0))
	_box(Vector3(-1.7, 0.6, -2.1), Vector3(0.04, 0.04, 0.7), RED, 0.0, 0.0, 0.01).rotation.x = 0.3
	_box(Vector3(-1.7, 0.75, -1.85), Vector3(0.3, 0.03, 0.03), INK, 0.0, 0.0, 0.0)
	_box(Vector3(-1.7, 0.55, -2.35), Vector3(0.04, 0.4, 0.04), RED, 0.0, 0.0, 0.01).rotation.x = -0.3
	_flat(Vector3(-1.7, 0.78, -2.4), Vector3(0.1, 0.03, 0.2), INK)
	# lixeira do pátio
	var lixo := _cyl(Vector3(2.6, 0.45, -2.6), 0.26, 0.9, Color("#4f7a5a"), 0.28)
	_cyl(Vector3(2.6, 0.95, -2.6), 0.3, 0.1, Color("#3d5a4a"), 0.22)
	_ball(Vector3(2.4, 0.06, -2.2), 0.06, PAPER)
	# amarelinha desbotada no chão
	var amarelinha := _flat(Vector3(0.0, 0.004, -1.2), Vector3(0.5, 0.004, 0.5), Color("#8a96b8"))
	for q in [[0, -1.8], [-0.27, -2.35], [0.27, -2.35], [0, -2.9]]:
		_flat(Vector3(q[0], 0.004, q[1]), Vector3(0.48, 0.004, 0.48), Color("#7280a8"))
	_flavor(amarelinha, "Uma amarelinha desbotada. O 7 foi pulado tantas vezes que sumiu.")
	# poças com o reflexo da luz
	_puddle(Vector3(1.0, 0, -3.4), Vector2(1.0, 0.6), YEL, 0.2)
	_puddle(Vector3(-0.6, 0, -0.2), Vector2(0.7, 0.4), Color("#9fb8ff"))
	_puddle(Vector3(-3.6, 0, -4.6), Vector2(0.8, 0.5), Color("#9fb8ff"))
	_rain(Vector3(0, 4, -6.5), Vector3(12, 8, 8), 360)
	_light(Vector3(2.0, 3.2, -11.8), YEL, 1.4, 4.0)
	_anchors = {
		"banco_patio": {"mesh": banco, "say": "O banco do pátio. Encharcado. Já ouviu mais segredos que o diário de qualquer um."},
		"arvore": {"mesh": arvore, "say": "A árvore do pátio. Tem iniciais gravadas desde antes da sua mãe estudar aqui."},
		"bicicletario": {"mesh": bici, "say": "Uma bicicleta presa sem a roda da frente. O cadeado venceu, a roda não."},
		"lixeira_patio": {"mesh": lixo, "say": "A lixeira do pátio. Cheiro de chuva e de salgadinho de ontem."},
		"poste": {"mesh": poste, "say": "O poste. A única luz amarela do pátio. As mariposas fizeram reunião aqui."},
	}
	_free_anchors = [{"pos": Vector3(0.5, 0.5, -5.2), "size": Vector3(0.3, 0.06, 0.25)}, {"pos": Vector3(-1.0, 0.05, -3.4), "size": Vector3(0.3, 0.06, 0.3)}]
	_moon(Vector3(0.7, -0.6, 0.5), 0.9)
	_camera(Vector3(0.0, 1.9, 3.6), Vector3(0.0, 1.5, -6.0), 0.45)


func _scene_sala_professores() -> void:
	_flat(Vector3(0, -0.05, -2.8), Vector3(7, 0.1, 9.6), Color("#4e5a86"))
	_flat(Vector3(-0.3, 0.005, -3.6), Vector3(3.6, 0.01, 2.6), Color("#3e4a7a"))
	_flat(Vector3(0, 3.0, -2.8), Vector3(7, 0.1, 9.6), CEIL)
	_flat(Vector3(0, 1.5, -7.05), Vector3(7, 3.0, 0.1), WALL_L)
	_flat(Vector3(3.5, 1.5, -2.8), Vector3(0.1, 3.0, 9.6), WALL_M)
	# janela à esquerda com persiana: faixas de luar
	_win_wall(false, -3.5, -7.0, 2.0, 3.0, 1.0, 2.5, [[-3.8, 2.0]], WALL_M, -1.0)
	for s in 9:
		_flat(Vector3(-3.38, 2.42 - s * 0.16, -3.8), Vector3(0.02, 0.06, 1.9), Color("#9aa6c8")).rotation.z = 0.35
	# escaninho de madeira: nichos com papéis saindo
	var esc := _box(Vector3(-2.0, 1.25, -6.8), Vector3(1.5, 1.7, 0.4), WOOD_D)
	for r in 4:
		for c in 4:
			_flat(Vector3(-2.54 + c * 0.36, 0.6 + r * 0.42, -6.59), Vector3(0.3, 0.34, 0.02), WOOD_DD)
			if (r + c) % 3 != 1:
				_flat(Vector3(-2.54 + c * 0.36, 0.52 + r * 0.42, -6.57), Vector3(0.24, 0.12, 0.03), PAPER if (r * c) % 2 == 0 else CREAM)
	_flat(Vector3(-2.0, 2.15, -6.58), Vector3(1.3, 0.02, 0.02), INK)
	# mural de recados
	var mural := _box(Vector3(0.4, 1.75, -6.97), Vector3(1.6, 1.0, 0.05), Color("#a07a4a"))
	_notes(Vector3(0.4, 0, -6.93), true, [[1.95, -0.5, 0.25, 0.2, YEL], [1.9, -0.1, 0.3, 0.36], [1.6, 0.35, 0.28, 0.22, CREAM], [1.5, -0.45, 0.22, 0.26, RED], [2.0, 0.5, 0.2, 0.18]])
	_text(Vector3(0.0, 1.95, -6.91), "reunião 3ª!!", 0.06, INK, "marker")
	# armário de aço com porta entreaberta
	var arm := _box(Vector3(2.5, 1.05, -6.7), Vector3(1.0, 2.1, 0.5), METAL)
	_flat(Vector3(2.5, 1.05, -6.44), Vector3(0.01, 2.0, 0.01), INK)
	_box(Vector3(2.9, 1.05, -6.2), Vector3(0.03, 2.0, 0.48), METAL, -1.0, 0.0, 0.012)
	_flat(Vector3(2.6, 1.6, -6.5), Vector3(0.4, 0.3, 0.3), Color("#c9bfa6"))
	# mesa de reunião, cadeiras, pilha de provas com tinta vermelha
	var mesa := _box(Vector3(-0.3, 0.75, -3.6), Vector3(2.6, 0.06, 1.2), WOOD)
	for lx in [-1.1, 1.1]:
		_flat(Vector3(-0.3 + lx, 0.37, -3.6), Vector3(0.08, 0.72, 1.0), WOOD_DD)
	for cpos in [[-1.0, -2.85, PI], [0.4, -2.85, PI + 0.2], [-0.6, -4.35, 0.1], [0.6, -4.35, -0.1]]:
		_chair(Vector3(cpos[0], 0, cpos[1]), cpos[2], RED_D)
	var provas := _box(Vector3(-0.8, 0.86, -3.5), Vector3(0.3, 0.16, 0.22), PAPER, 0.2, 0.0, 0.008)
	_flat(Vector3(-0.8, 0.945, -3.5), Vector3(0.2, 0.004, 0.02), RED, 0.2)
	_flavor(provas, "Uma pilha de provas corrigidas. Muita tinta vermelha. Você sente a dor de outra pessoa.")
	_cyl(Vector3(0.3, 0.83, -3.4), 0.05, 0.1, CREAM)
	_disc(Vector3(0.0, 0.785, -3.8), 0.06, Color("#5a3d2a"))
	# bancada da copa: cafeteira, canecas e o aviso
	_box(Vector3(2.9, 0.45, -3.4), Vector3(0.9, 0.9, 1.8), WOOD_D)
	_box(Vector3(2.9, 0.92, -3.4), Vector3(0.95, 0.04, 1.85), CREAM, 0.0, 0.0, 0.01)
	var cafe := _box(Vector3(3.0, 1.15, -3.0), Vector3(0.35, 0.42, 0.3), INK)
	_cyl(Vector3(2.88, 1.02, -3.0), 0.1, 0.16, Color("#6a3e2e"), 0.09)
	_flat(Vector3(2.84, 1.25, -3.0), Vector3(0.02, 0.04, 0.04), RED, 0.0, 2.0, RED)
	for m in 3:
		_cyl(Vector3(2.8, 0.99, -3.5 - m * 0.18), 0.05, 0.1, [CREAM, TEAL, RED_D][m])
	_box(Vector3(2.75, 1.2, -3.75), Vector3(0.02, 0.15, 0.2), YEL, -0.0, 0.0, 0.005)
	_light(Vector3(2.6, 1.6, -3.2), WARM, 1.0, 2.6)
	# galão d'água vazio
	var galao := _cyl(Vector3(2.9, 1.35, -4.1), 0.15, 0.4, Color("#8fb0e8"), 0.13)
	_flavor(galao, "O galão de água está vazio. Ninguém troca. É um jogo de paciência entre adultos.")
	# mesa do computador encostada à esquerda
	var DZ := -3.0
	_box(Vector3(-2.4, 0.74, -1.6 + DZ), Vector3(0.8, 0.05, 1.4), WOOD, 0.0, 0.0, 0.012)
	_flat(Vector3(-2.4, 0.37, -2.2 + DZ), Vector3(0.7, 0.72, 0.05), WOOD_DD)
	_flat(Vector3(-2.4, 0.37, -1.0 + DZ), Vector3(0.7, 0.72, 0.05), WOOD_DD)
	var pc := _box(Vector3(-2.55, 1.0, -1.7 + DZ), Vector3(0.4, 0.4, 0.4), Color("#c9bfa6"), 0.5)
	_flat(Vector3(-2.45, 1.02, -1.51 + DZ), Vector3(0.32, 0.28, 0.02), Color("#8fe8c8"), 0.5, 1.4, Color("#8fe8c8"))
	_flat(Vector3(-2.2, 0.78, -1.45 + DZ), Vector3(0.18, 0.02, 0.4), INK, 0.5)
	for n in 3:
		_flat(Vector3(-2.32 + n * 0.02, 1.22, -1.82 + n * 0.12 + DZ), Vector3(0.01, 0.06, 0.06), YEL, 0.5)
	_chair(Vector3(-1.75, 0, -1.6 + DZ), -PI / 2.0, RED_D)
	_light(Vector3(-2.0, 1.3, -1.4 + DZ), Color("#a8f0d0"), 0.6, 2.2)
	# planta cansada no canto
	var vaso := _cyl(Vector3(1.6, 0.22, -6.6), 0.2, 0.44, Color("#a05a4a"), 0.24)
	for f in 4:
		var folha := _box(Vector3(1.6 + cos(f * 1.6) * 0.15, 0.6, -6.6 + sin(f * 1.6) * 0.15), Vector3(0.06, 0.4, 0.14), Color("#4f6a4a"), f * 1.6, 0.0, 0.01)
		folha.rotation.z = 0.6 + f * 0.1
	_flavor(vaso, "Uma planta que já viu três diretores. Ela está cansada.")
	# ventilador de teto girando devagar
	var fan := Node3D.new()
	fan.position = Vector3(-0.3, 2.75, -3.6)
	world.add_child(fan)
	_cyl(Vector3(-0.3, 2.9, -3.6), 0.02, 0.2, INK)
	for b in 4:
		var pa := _box(Vector3.ZERO, Vector3(0.9, 0.02, 0.14), WOOD_D, 0.0, 0.0, 0.01)
		pa.reparent(fan, false)
		pa.position = Vector3(cos(b * PI / 2.0) * 0.5, 0, sin(b * PI / 2.0) * 0.5)
		pa.rotation.y = -b * PI / 2.0
	_spinners.append({"node": fan, "speed": 1.4})
	_light(Vector3(-0.3, 2.4, -3.6), Color("#cfdcff"), 0.7, 4.0)
	_anchors = {
		"escaninho": {"mesh": esc, "say": "O escaninho dos professores. Cada nicho tem um nome e uma pilha de sonhos adiados."},
		"cafeteira": {"mesh": cafe, "say": "A cafeteira. O café está ali desde a primeira aula. Ele sabe coisas."},
		"mural_recados": {"mesh": mural, "say": "Mural de recados: \"Quem pegou meu grampeador, devolva\". Três exclamações."},
		"computador_prof": {"mesh": pc, "say": "O computador da sala. Cheio de post-its com senhas. Segurança total."},
		"armario_prof": {"mesh": arm, "say": "O armário de aço. A porta não fecha direito desde 2012."},
	}
	_free_anchors = [{"pos": Vector3(0.2, 0.8, -3.7), "size": Vector3(0.3, 0.05, 0.25)}, {"pos": Vector3(2.9, 0.98, -2.7), "size": Vector3(0.2, 0.1, 0.2)}]
	_moon(Vector3(0.8, -0.5, -0.2), 1.0)
	_camera(Vector3(0.8, 2.4, 2.6), Vector3(-0.3, 0.95, -4.6), 0.45)


func _scene_quadra() -> void:
	_sky(Color("#0a1430"), Color("#2a3f78"), 0.95, Color("#16244d"), 0.02)
	_flat(Vector3(0, -0.05, -5.5), Vector3(14, 0.1, 18), Color("#7a6450"))
	for i in 9:
		_flat(Vector3(-6 + i * 1.5, 0.002, -5.5), Vector3(0.02, 0.004, 18), Color("#5e4a3e"))
	# linhas da quadra
	for lz in [-0.5, -10.5]:
		_flat(Vector3(0, 0.006, lz), Vector3(6.4, 0.004, 0.06), CREAM)
	for lx in [-3.2, 3.2]:
		_flat(Vector3(lx, 0.006, -5.5), Vector3(0.06, 0.004, 10), CREAM)
	_flat(Vector3(0, 0.006, -5.5), Vector3(6.4, 0.004, 0.06), CREAM)
	_torus(Vector3(0, 0.006, -5.5), 1.0, 1.06, CREAM, Vector3.ZERO).scale = Vector3(1, 0.02, 1)
	_flat(Vector3(0, 7.0, -5.5), Vector3(14, 0.1, 18), INK)
	_flat(Vector3(-7, 3.5, -5.5), Vector3(0.1, 7, 18), WALL_M)
	_flat(Vector3(0, 3.5, -14.5), Vector3(14, 7, 0.1), WALL)
	_flat(Vector3(0, 0.6, -14.42), Vector3(14, 1.2, 0.06), Color("#3a4a7a"))
	# janelas altas na parede direita com chuva
	_win_wall(false, 7.0, -14.5, 3.5, 7.0, 4.2, 6.2, [[-11.0, 2.2], [-7.0, 2.2], [-3.0, 2.2], [1.0, 2.2]], WALL_M, 1.0)
	# placar aceso no fundo (o time da casa está perdendo)
	var placar := _box(Vector3(2.2, 5.3, -14.35), Vector3(3.2, 1.3, 0.2), INK)
	_text(Vector3(2.2, 5.65, -14.22), "CASA      VISITA", 0.16, CREAM, "bebas")
	_text(Vector3(1.45, 5.15, -14.22), "03", 0.5, YEL, "bebas")
	_text(Vector3(2.95, 5.15, -14.22), "21", 0.5, YEL, "bebas")
	_light(Vector3(2.2, 4.6, -13.4), Color("#ffd27a"), 1.2, 4.0)
	# tabela de basquete
	_box(Vector3(-0.9, 3.6, -14.0), Vector3(1.6, 1.0, 0.06), PAPER, 0.0, 0.0, 0.015)
	_flat(Vector3(-0.9, 3.45, -13.96), Vector3(0.5, 0.4, 0.01), RED)
	_flat(Vector3(-0.9, 3.45, -13.955), Vector3(0.4, 0.3, 0.012), PAPER)
	_flat(Vector3(-0.9, 3.6, -14.3), Vector3(0.1, 0.1, 0.5), METAL_D)
	_torus(Vector3(-0.9, 3.1, -13.75), 0.2, 0.23, RED)
	var cesta := _cyl(Vector3(-0.9, 2.9, -13.75), 0.2, 0.36, CREAM, 0.13)
	_flavor(cesta, "Placa: \"Proibido pendurar no aro\". O aro está torto. Alguém leu tarde.")
	# porta do vestiário no fundo
	_flat(Vector3(-3.9, 1.15, -14.42), Vector3(1.3, 2.3, 0.06), WALL_L)
	var vest := _box(Vector3(-3.9, 1.1, -14.38), Vector3(1.1, 2.1, 0.06), TEAL)
	_flat(Vector3(-3.9, 1.6, -14.34), Vector3(0.4, 0.5, 0.01), Color("#8fb0e8"), 0.0, 0.3, Color("#8fb0e8"))
	_text(Vector3(-3.9, 2.5, -14.36), "VESTIÁRIO", 0.18, CREAM, "bebas")
	_flat(Vector3(-3.45, 1.05, -14.33), Vector3(0.12, 0.04, 0.04), METAL)
	# arquibancada de degraus à direita
	var arq: MeshInstance3D
	for s in 5:
		var st := _box(Vector3(5.9 - s * 0.0 + s * 0.0, 0.25 + s * 0.5, -6.5), Vector3(1.8 - s * 0.36, 0.5, 11), Color("#5a6a9e") if s % 2 == 0 else Color("#4c5c94"), 0.0, 0.0, 0.015)
		st.position.x = 4.6 + s * 0.18
		if s == 0:
			arq = st
		_flat(Vector3(3.7 + s * 0.36, 0.52 + s * 0.5, -6.5), Vector3(0.12, 0.04, 11), WOOD)
	_box(Vector3(3.9, 0.7, -4.5), Vector3(0.3, 0.2, 0.25), RED, 0.3, 0.0, 0.01)
	# rede de vôlei atravessando a quadra
	var rede := _box(Vector3(0, 2.38, -5.5), Vector3(6.6, 0.08, 0.04), PAPER, 0.0, 0.0, 0.012)
	for px in [-3.35, 3.35]:
		_cyl(Vector3(px, 1.25, -5.5), 0.05, 2.5, METAL_D)
	var net := []
	for i in 33:
		net.append([Vector3(-3.2 + i * 0.2, 1.9, -5.5), Vector3(0.012, 0.9, 0.012), INK])
	for j in 5:
		net.append([Vector3(0, 1.48 + j * 0.2, -5.5), Vector3(6.6, 0.012, 0.012), INK])
	_flat(Vector3(0, 1.45, -5.5), Vector3(6.6, 0.03, 0.02), PAPER)
	_mm(net)
	# banco com a bolsa esportiva, bolas espalhadas, carrinho e cone
	_box(Vector3(-1.3, 0.42, -2.0), Vector3(2.0, 0.06, 0.4), WOOD, 0.0, 0.0, 0.012)
	for lx in [-0.85, 0.85]:
		_flat(Vector3(-1.3 + lx, 0.2, -2.0), Vector3(0.06, 0.4, 0.34), METAL_D)
	var bolsa := _cyl(Vector3(-1.1, 0.62, -2.0), 0.17, 0.75, Color("#26407a"))
	bolsa.rotation.z = PI / 2.0
	_flat(Vector3(-1.1, 0.62, -1.82), Vector3(0.6, 0.04, 0.02), CREAM)
	_torus(Vector3(-1.1, 0.8, -2.0), 0.12, 0.15, INK, Vector3(PI / 2.0, 0, 0))
	_ball(Vector3(-1.8, 0.55, -2.0), 0.1, CREAM, Vector3(1.4, 0.6, 1))   # toalha
	var murcha := _ball(Vector3(0.6, 0.08, -3.4), 0.13, Color("#a0603e"), Vector3(1.2, 0.55, 1.2))
	_flavor(murcha, "Uma bola de basquete murcha. Ela também desistiu do campeonato.")
	_ball(Vector3(2.8, 0.12, -8.5), 0.12, CREAM)
	_ball(Vector3(-0.8, 0.12, -9.2), 0.12, Color("#a0603e"))
	var carr := _box(Vector3(-3.0, 0.55, -8.0), Vector3(0.8, 0.9, 0.6), METAL_D, 0.3, 0.0, 0.012)
	for b in 4:
		_ball(Vector3(-3.2 + (b % 2) * 0.35, 1.1, -8.1 + (b / 2) * 0.25), 0.13, Color("#a0603e") if b % 2 == 0 else CREAM)
	_flavor(carr, "O carrinho de bolas. Metade murcha, metade fugiu. Típico fim de bimestre.")
	var cone := _cyl(Vector3(2.7, 0.2, -3.6), 0.16, 0.4, RED, 0.02)
	_flavor(cone, "Um cone. Ninguém sabe de onde veio, mas ele sempre volta para a quadra.")
	# refletores do teto: um aceso
	for lx in [-3.0, 3.0]:
		_cyl(Vector3(lx, 6.7, -6.0), 0.4, 0.3, METAL_D, 0.3)
	_cyl(Vector3(-3.0, 6.53, -6.0), 0.32, 0.02, Color("#dfe8ff"), -1.0, 1.4)
	_light(Vector3(-3.0, 5.0, -6.0), Color("#cfdcff"), 1.5, 9.0)
	_light(Vector3(2.0, 3.5, -3.0), Color("#9fb8ff"), 0.8, 7.0)
	_anchors = {
		"arquibancada": {"mesh": arq, "say": "A arquibancada. Chiclete grudado em cada degrau, como fósseis."},
		"placar": {"mesh": placar, "say": "Casa 03, visita 21. O placar ficou ligado para a humilhação durar."},
		"bolsa_esportiva": {"mesh": bolsa, "say": "Uma bolsa esportiva. Cheiro de tênis molhado. Investigue com o nariz tampado."},
		"vestiario_porta": {"mesh": vest, "say": "A porta do vestiário. Rangeu tão alto que você se arrependeu de chegar perto."},
		"rede": {"mesh": rede, "say": "A rede de vôlei. Tem um buraco do tamanho exato de uma bola. Coincidência?"},
	}
	_free_anchors = [{"pos": Vector3(-1.6, 0.48, -1.2), "size": Vector3(0.3, 0.06, 0.25)}, {"pos": Vector3(4.4, 1.02, -7.5), "size": Vector3(0.3, 0.06, 0.25)}]
	_moon(Vector3(-0.8, -0.5, -0.3), 0.9)
	_camera(Vector3(-0.6, 3.2, 4.0), Vector3(0.8, 1.5, -8.5), 0.5)


func _scene_sala_diretor() -> void:
	_flat(Vector3(0, -0.05, -2.5), Vector3(6, 0.1, 9), Color("#4a3a52"))
	_flat(Vector3(0, 0.006, -3.6), Vector3(3.4, 0.01, 2.6), RED_D)
	_flat(Vector3(0, 0.01, -3.6), Vector3(3.1, 0.01, 2.3), Color("#6b2a3e"))
	_flat(Vector3(0, 3.0, -2.5), Vector3(6, 0.1, 9), Color("#241f45"))
	_flat(Vector3(0, 1.5, -6.55), Vector3(6, 3.0, 0.1), Color("#3a4a7a"))
	_flat(Vector3(0, 0.5, -6.48), Vector3(6, 1.0, 0.04), WOOD_D)   # lambri
	_flat(Vector3(0, 1.0, -6.45), Vector3(6, 0.05, 0.06), WOOD)
	_flat(Vector3(-3.0, 1.5, -2.5), Vector3(0.1, 3.0, 9), Color("#3a4a7a"))
	# janela com persiana à direita: luar em faixas, chuva lá fora
	_win_wall(false, 3.0, -6.5, 2.0, 3.0, 0.9, 2.6, [[-3.6, 1.8]], Color("#3a4a7a"), 1.0)
	for s in 10:
		_flat(Vector3(2.9, 2.5 - s * 0.16, -3.6), Vector3(0.02, 0.07, 1.75), Color("#9aa6c8")).rotation.z = -0.35
	_flat(Vector3(1.8, 0.012, -3.4), Vector3(1.6, 0.004, 0.08), Color("#9fb8ff"), 0.0, 0.5, Color("#9fb8ff"))
	_flat(Vector3(1.8, 0.012, -3.7), Vector3(1.6, 0.004, 0.08), Color("#9fb8ff"), 0.0, 0.5, Color("#9fb8ff"))
	_flat(Vector3(1.8, 0.012, -4.0), Vector3(1.6, 0.004, 0.08), Color("#9fb8ff"), 0.0, 0.5, Color("#9fb8ff"))
	# mesa grande de madeira escura, cadeira de couro alta atrás
	var mesa := _box(Vector3(0, 0.8, -4.4), Vector3(2.2, 0.08, 1.0), WOOD_D)
	_box(Vector3(-0.8, 0.4, -4.4), Vector3(0.55, 0.76, 0.9), WOOD_DD, 0.0, 0.0, 0.015)
	_box(Vector3(0.0, 0.45, -4.85), Vector3(1.6, 0.6, 0.05), WOOD_DD, 0.0, 0.0, 0.0)
	var gaveta := _box(Vector3(0.75, 0.55, -3.86), Vector3(0.55, 0.22, 0.4), WOOD, 0.0, 0.0, 0.012)
	_box(Vector3(0.75, 0.4, -4.4), Vector3(0.55, 0.76, 0.9), WOOD_DD, 0.0, 0.0, 0.015)
	_flat(Vector3(0.75, 0.55, -3.65), Vector3(0.16, 0.03, 0.02), Color("#c9a24a"))
	_box(Vector3(0.0, 0.58, -5.2), Vector3(0.7, 0.12, 0.65), Color("#3a2a32"), 0.0, 0.0, 0.015)
	_box(Vector3(0.0, 1.25, -5.5), Vector3(0.75, 1.3, 0.14), Color("#3a2a32"), 0.0, 0.0, 0.015)
	_cyl(Vector3(0.0, 0.26, -5.2), 0.05, 0.5, INK)
	# objetos na mesa: telefone com fio, placa de nome, carimbo, pilha de advertências, abajur verde
	var tel := _box(Vector3(-0.6, 0.9, -4.2), Vector3(0.26, 0.1, 0.2), RED_D, 0.2)
	_box(Vector3(-0.6, 0.98, -4.2), Vector3(0.28, 0.05, 0.07), INK, 0.2, 0.0, 0.01)
	_box(Vector3(0.2, 0.9, -3.98), Vector3(0.5, 0.1, 0.05), Color("#c9a24a"), 0.0, 0.0, 0.008)
	_text(Vector3(0.2, 0.9, -3.95), "DIRETOR", 0.06, INK, "bebas")
	var adv := _box(Vector3(0.65, 0.9, -4.3), Vector3(0.28, 0.12, 0.22), PAPER, -0.15, 0.0, 0.008)
	_flavor(adv, "Uma pilha de advertências em branco. Prontas. Esperando um nome. Talvez o seu.")
	_cyl(Vector3(-0.15, 0.9, -4.6), 0.06, 0.12, INK)
	_cyl(Vector3(-0.9, 1.1, -4.6), 0.02, 0.5, Color("#c9a24a"))
	_cyl(Vector3(-0.9, 1.35, -4.6), 0.15, 0.1, Color("#2e5a4a"), 0.1, 0.4)
	_light(Vector3(-0.8, 1.3, -4.2), WARM, 1.5, 3.0)
	# duas cadeiras baixas na frente: o lugar de quem está encrencado
	_chair(Vector3(-0.6, 0, -3.0), PI, Color("#55608f"))
	var banquinho := _chair(Vector3(0.5, 0, -3.0), PI - 0.15, Color("#55608f"))
	_flavor(banquinho, "A cadeira de quem está encrencado. É mais baixa que as outras. De propósito.")
	# estante com troféus e quadro de fotos de turmas
	var tr_items := []
	_shelf(Vector3(-2.65, 0, -2.6), false, 1.8, 2.2, 0.45, 4, WOOD_D)
	_books(Vector3(-2.6, 0, -2.6), false, 1.7, 2, 0.53, 0.3, 91, tr_items)
	_mm(tr_items)
	for t in 3:
		var ty := 1.62
		var tz := -3.2 + t * 0.55
		_cyl(Vector3(-2.6, ty + 0.05, tz), 0.08, 0.1, WOOD_DD)
		_cyl(Vector3(-2.6, ty + 0.25, tz), 0.03, 0.3, Color("#c9a24a"))
		_ball(Vector3(-2.6, ty + 0.45, tz), 0.1, Color("#c9a24a"), Vector3(1.2, 0.8, 1.2))
	var trofeu := _box(Vector3(-2.6, 2.15, -2.6), Vector3(0.2, 0.12, 0.2), Color("#c9a24a"), 0.0, 0.0, 0.01)
	_flavor(trofeu, "Troféu de 3º lugar em vôlei, 1998. O auge da instituição.")
	var fotos := _box(Vector3(-1.4, 1.95, -6.45), Vector3(1.3, 0.8, 0.05), WOOD_DD)
	for f in 6:
		_flat(Vector3(-1.85 + (f % 3) * 0.45, 2.12 - (f / 3) * 0.36, -6.42), Vector3(0.38, 0.28, 0.01), CREAM if f != 4 else PAPER)
		_flat(Vector3(-1.85 + (f % 3) * 0.45, 2.08 - (f / 3) * 0.36, -6.415), Vector3(0.3, 0.08, 0.01), WALL_M)
	# bandeira e cofre no canto
	_cyl(Vector3(1.9, 1.1, -6.1), 0.025, 2.2, Color("#c9a24a"))
	var band := _box(Vector3(1.6, 1.85, -6.1), Vector3(0.6, 0.45, 0.02), Color("#3d6a4a"), 0.0, 0.0, 0.01)
	_flat(Vector3(1.6, 1.85, -6.09), Vector3(0.35, 0.25, 0.01), Color("#c9a24a"))
	_flavor(band, "A bandeira da escola. O lema em latim que ninguém sabe traduzir. Nem o diretor.")
	var cofre := _box(Vector3(1.05, 0.4, -6.1), Vector3(0.7, 0.8, 0.6), Color("#3a4250"))
	_cyl(Vector3(1.05, 0.5, -5.79), 0.1, 0.03, METAL).rotation.x = PI / 2.0
	_flat(Vector3(1.25, 0.3, -5.79), Vector3(0.12, 0.03, 0.02), METAL)
	_light(Vector3(1.2, 2.4, -5.0), Color("#9fb8ff"), 0.6, 3.0)
	_anchors = {
		"mesa_diretor": {"mesh": mesa, "say": "A mesa do diretor. Tão grande que dá pra jogar pingue-pongue. Ninguém nunca jogou."},
		"gaveta": {"mesh": gaveta, "say": "A gaveta. Trancada. Lenda diz que guarda celulares confiscados desde 2010."},
		"quadro_fotos": {"mesh": fotos, "say": "Fotos de turmas antigas. Os cortes de cabelo contam uma história de terror."},
		"telefone": {"mesh": tel, "say": "O telefone vermelho. Quando toca, alguém liga pros seus pais."},
		"cofre": {"mesh": cofre, "say": "O cofre. Ninguém sabe a senha. Nem se tem algo dentro. Isso é poder."},
	}
	_free_anchors = [{"pos": Vector3(0.3, 0.9, -4.5), "size": Vector3(0.3, 0.05, 0.25)}, {"pos": Vector3(-2.3, 0.1, -4.6), "size": Vector3(0.3, 0.15, 0.3)}]
	_moon(Vector3(-1.0, -0.5, -0.3), 1.0)
	_camera(Vector3(0.3, 2.2, 2.1), Vector3(-0.1, 0.95, -4.6), 0.45)


func _scene_deposito() -> void:
	_sky(Color("#080f26"), Color("#22356a"), 0.8, Color("#121d40"), 0.035)
	_flat(Vector3(0, -0.05, -2.5), Vector3(5, 0.1, 8), Color("#454a6a"))
	_disc(Vector3(0.4, 0.005, -2.0), 0.5, Color("#383c5a"), Vector3(1.4, 1, 0.9))     # mancha de óleo antiga
	_flat(Vector3(0, 2.8, -2.5), Vector3(5, 0.1, 8), INK)
	_flat(Vector3(0, 1.4, -6.05), Vector3(5, 2.8, 0.1), WALL)
	_flat(Vector3(-2.5, 1.4, -2.5), Vector3(0.1, 2.8, 8), WALL_M)
	_flat(Vector3(2.5, 1.4, -2.5), Vector3(0.1, 2.8, 8), WALL_M)
	# cano exposto no teto
	_flat(Vector3(-1.0, 2.6, -2.5), Vector3(0.1, 0.1, 8), METAL_D)
	_flat(Vector3(-1.0, 2.6, -5.0), Vector3(0.14, 0.14, 0.14), METAL)
	# lâmpada pendurada no fio, a única luz amarela
	_flat(Vector3(0.1, 2.45, -3.0), Vector3(0.01, 0.7, 0.01), INK)
	var bulbo := _ball(Vector3(0.1, 2.05, -3.0), 0.08, YEL)
	bulbo.material_override = _glow(YEL, 2.5)
	_cyl(Vector3(0.1, 2.15, -3.0), 0.04, 0.06, METAL_D)
	_light(Vector3(0.1, 1.95, -3.0), Color("#ffc870"), 2.4, 5.5)
	_beam(Vector3(0.1, 2.05, -3.0), Vector3(0.1, 0.0, -3.0), 0.05, 1.4, Color("#ffcf70"), 0.05)
	# prateleira de aço cheia de coisa
	var prat := _box(Vector3(-1.95, 1.1, -3.4), Vector3(0.6, 0.04, 2.4), METAL, 0.0, 0.0, 0.012)
	for py in [0.25, 1.95]:
		_box(Vector3(-1.95, py, -3.4), Vector3(0.6, 0.04, 2.4), METAL, 0.0, 0.0, 0.012)
	for pz in [-4.58, -2.22]:
		for px in [-2.23, -1.67]:
			_flat(Vector3(px, 1.1, pz), Vector3(0.04, 2.2, 0.04), METAL_D)
	var stuff := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for py in [0.27, 1.12, 1.97]:
		var z := -4.5
		while z < -2.4:
			var w := rng.randf_range(0.22, 0.45)
			var h := rng.randf_range(0.18, 0.5)
			stuff.append([Vector3(-1.95, py + h * 0.5 + 0.02, z + w * 0.5), Vector3(0.5, h, w), [Color("#a07a4a"), Color("#8a6a3e"), CREAM, Color("#55608f"), Color("#4f7a5a")][rng.randi() % 5]])
			z += w + 0.04
	_mm(stuff)
	_text(Vector3(-1.64, 1.6, -3.4), "NÃO MEXER", 0.08, RED_D, "marker", PI / 2.0)
	# caixas empilhadas no fundo e a caixa de achados e perdidos transbordando
	for b in [[-0.9, 0.3, -5.5, 0.8, 0.6, 0.7, 0.1], [-0.85, 0.85, -5.55, 0.7, 0.5, 0.6, -0.1], [-0.9, 1.3, -5.5, 0.55, 0.4, 0.5, 0.25], [0.2, 0.25, -5.6, 0.6, 0.5, 0.6, -0.05]]:
		_box(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Color("#a07a4a") if b[1] < 1.0 else Color("#8a6a3e"), b[6])
	_flat(Vector3(-0.9, 0.3, -5.14), Vector3(0.5, 0.06, 0.01), INK, 0.1)
	var achados := _box(Vector3(0.7, 0.28, -3.9), Vector3(0.7, 0.55, 0.55), Color("#a07a4a"), 0.25)
	_text(Vector3(0.75, 0.32, -3.6), "ACHADOS\nE PERDIDOS", 0.07, INK, "marker", 0.25)
	_ball(Vector3(0.6, 0.6, -3.95), 0.18, Color("#26407a"), Vector3(1.3, 0.6, 1))   # moletom
	_box(Vector3(0.85, 0.62, -3.85), Vector3(0.1, 0.1, 0.28), CREAM, 0.6, 0.0, 0.01)   # tênis sem par
	_cyl(Vector3(0.55, 0.65, -3.75), 0.04, 0.22, TEAL).rotation.z = 0.9            # garrafinha
	_box(Vector3(0.95, 0.06, -3.4), Vector3(0.16, 0.12, 0.24), RED_D, 0.4, 0.0, 0.01)  # estojo caído
	# vassoura encostada e carrinho de limpeza
	var vassoura := _cyl(Vector3(1.9, 0.75, -5.4), 0.022, 1.5, WOOD)
	vassoura.rotation.x = 0.18
	_box(Vector3(1.9, 0.08, -5.27), Vector3(0.35, 0.12, 0.1), RED_D, 0.0, 0.0, 0.01)
	var carrinho := _box(Vector3(1.6, 0.45, -2.4), Vector3(0.5, 0.06, 0.8), Color("#e0a040"), 0.2, 0.0, 0.012)
	_cyl(Vector3(1.6, 0.68, -2.2), 0.17, 0.4, Color("#3d6a8a"), 0.15)
	_box(Vector3(1.6, 0.85, -2.65), Vector3(0.46, 0.7, 0.08), Color("#e0a040"), 0.2, 0.0, 0.01)
	for w in [[-0.22, -0.32], [0.22, -0.32], [-0.22, 0.32], [0.22, 0.32]]:
		_ball(Vector3(1.6 + w[0], 0.06, -2.4 + w[1]), 0.06, INK)
	_flavor(carrinho, "O carrinho de limpeza. Tem mais produto que a farmácia do bairro.")
	# caixa de fusíveis na parede, porta dos fundos com fresta de luz
	var fus := _box(Vector3(2.44, 1.5, -4.2), Vector3(0.1, 0.6, 0.45), Color("#7a8298"))
	_flat(Vector3(2.38, 1.5, -4.2), Vector3(0.01, 0.12, 0.12), YEL)
	_flat(Vector3(2.38, 1.66, -4.2), Vector3(0.01, 0.05, 0.3), INK)
	_flat(Vector3(2.4, 2.1, -4.05), Vector3(0.02, 1.4, 0.02), INK)
	var porta := _box(Vector3(0.9, 1.05, -5.98), Vector3(0.95, 2.1, 0.06), Color("#3a4250"))
	_flat(Vector3(1.39, 1.05, -5.96), Vector3(0.03, 2.0, 0.02), Color("#9fb8ff"), 0.0, 1.4, Color("#9fb8ff"))
	_flat(Vector3(0.9, 0.003, -5.7), Vector3(0.9, 0.004, 0.5), Color("#4a5a8e"))
	_flat(Vector3(0.5, 1.05, -5.93), Vector3(0.12, 0.04, 0.04), METAL)
	_text(Vector3(0.9, 1.75, -5.94), "SAÍDA", 0.12, Color("#8fe8a8"), "bebas")
	# rato de borracha e balde de tinta
	var balde := _cyl(Vector3(-1.2, 0.18, -1.8), 0.17, 0.36, PAPER, 0.16)
	_flat(Vector3(-1.2, 0.37, -1.8), Vector3(0.24, 0.005, 0.24), SKY)
	_flavor(balde, "Um balde de tinta azul. Ninguém sabe o que pintaram. Ninguém quer saber.")
	var rato := _ball(Vector3(-0.4, 0.06, -4.6), 0.06, Color("#6a6a7a"), Vector3(1.6, 0.8, 1))
	_flavor(rato, "Um rato de borracha. Ou não. Você decide não verificar.")
	_anchors = {
		"caixa_achados": {"mesh": achados, "say": "Achados e perdidos. Um pé de tênis, três moletons e a dignidade de alguém."},
		"prateleira": {"mesh": prat, "say": "A prateleira do almoxarifado. Giz, papel A4 e caixas que ninguém abre desde a reforma."},
		"vassoura": {"mesh": vassoura, "say": "A vassoura do zelador. Já viu tudo. Não conta nada."},
		"caixa_fusiveis": {"mesh": fus, "say": "A caixa de fusíveis. Uma etiqueta diz \"NÃO DESLIGAR (sério)\"."},
		"porta_fundos": {"mesh": porta, "say": "A porta dos fundos. Entra um ventinho gelado. E talvez alguém."},
	}
	_free_anchors = [{"pos": Vector3(-1.95, 1.2, -2.8), "size": Vector3(0.3, 0.1, 0.25)}, {"pos": Vector3(0.0, 0.05, -2.4), "size": Vector3(0.3, 0.1, 0.3)}]
	_moon(Vector3(0.4, -0.8, -0.3), 0.5)
	_camera(Vector3(0.2, 2.1, 1.8), Vector3(0.0, 0.9, -4.0), 0.42)


func _scene_laboratorio() -> void:
	_flat(Vector3(0, -0.05, -2.8), Vector3(7, 0.1, 9.6), Color("#55628e"))
	for i in 4:
		for j in 4:
			if (i + j) % 2 == 0:
				_flat(Vector3(-2.6 + j * 1.75, 0.003, -6.6 + i * 2.4), Vector3(1.75, 0.005, 2.4), Color("#4c5888"))
	_flat(Vector3(0, 3.1, -2.8), Vector3(7, 0.1, 9.6), CEIL)
	_flat(Vector3(0, 1.55, -7.05), Vector3(7, 3.1, 0.1), WALL_L)
	_flat(Vector3(3.5, 1.55, -2.8), Vector3(0.1, 3.1, 9.6), WALL_M)
	_win_wall(false, -3.5, -7.0, 2.0, 3.1, 1.0, 2.6, [[-4.6, 1.8], [-1.6, 1.8]], WALL_M, -1.0)
	# quadro da tabela periódica no fundo: grade de quadradinhos coloridos (MultiMesh)
	var tab := _box(Vector3(-0.6, 1.95, -6.97), Vector3(2.6, 1.3, 0.04), CREAM)
	var cells := []
	var cc := [Color("#8a3d4f"), Color("#3d6a8a"), Color("#4f7a5a"), Color("#a8873d"), Color("#6b4a8a")]
	for r in 7:
		for c in 18:
			if r == 0 and c > 0 and c < 17:
				continue
			if (r == 1 or r == 2) and c > 1 and c < 12:
				continue
			cells.append([Vector3(-1.75 + c * 0.13, 2.45 - r * 0.14, -6.94), Vector3(0.11, 0.12, 0.01), cc[(c / 4 + r) % 5]])
	_text(Vector3(-0.6, 2.71, -6.93), "TABELA PERIÓDICA", 0.08, INK, "bebas")
	# cartaz de segurança
	var seg := _box(Vector3(1.6, 2.0, -6.97), Vector3(0.7, 0.9, 0.03), Color("#e0c040"), 0.0, 0.0, 0.01)
	_text(Vector3(1.6, 2.1, -6.94), "USE ÓCULOS\nDE PROTEÇÃO", 0.08, INK, "bebas")
	_flavor(seg, "\"Use óculos de proteção\". Os óculos estão numa caixa trancada. A chave sumiu em 2017.")
	# bancadas com pia, banquetas e vidraria
	var bancadas := []
	for b in 2:
		var bz := -2.6 - b * 2.4
		var bx := 0.2 - b * 0.3
		var top := _box(Vector3(bx, 0.9, bz), Vector3(3.0, 0.08, 0.9), Color("#26335f"))
		_box(Vector3(bx, 0.44, bz), Vector3(2.9, 0.86, 0.8), CREAM, 0.0, 0.0, 0.0)
		for d in 3:
			_flat(Vector3(bx - 1.0 + d * 1.0, 0.6, bz + 0.405), Vector3(0.8, 0.5, 0.01), Color("#c9bfa6"))
		for s in 3:
			var sx := bx - 1.0 + s * 1.0
			_cyl(Vector3(sx, 0.62, bz + 0.75), 0.17, 0.05, NAVY)
			_cyl(Vector3(sx, 0.3, bz + 0.75), 0.03, 0.6, METAL_D)
			_torus(Vector3(sx, 0.18, bz + 0.75), 0.12, 0.14, METAL_D)
		bancadas.append(top)
	var pia := _box(Vector3(1.3, 0.95, -2.6), Vector3(0.5, 0.04, 0.4), METAL)
	_flat(Vector3(1.3, 0.97, -2.6), Vector3(0.4, 0.01, 0.3), INK)
	_cyl(Vector3(1.3, 1.12, -2.85), 0.02, 0.32, METAL)
	_box(Vector3(1.3, 1.27, -2.75), Vector3(0.04, 0.03, 0.2), METAL, 0.0, 0.0, 0.006)
	_flat(Vector3(1.3, 1.12, -2.66), Vector3(0.01, 0.2, 0.01), Color("#9fd8ff"), 0.0, 0.8, Color("#9fd8ff"))   # torneira pingando
	# vidraria: béquer, erlenmeyer com líquido, tubos de ensaio no suporte
	_cyl(Vector3(-0.5, 1.02, -2.5), 0.07, 0.16, Color("#9fd8ff"))
	_cyl(Vector3(-0.5, 0.99, -2.5), 0.065, 0.08, Color("#6fe0a0"), -1.0, 0.6)
	_cyl(Vector3(-0.15, 1.04, -2.7), 0.1, 0.2, Color("#9fd8ff"), 0.03)
	_cyl(Vector3(-0.15, 0.99, -2.7), 0.09, 0.08, Color("#e070a0"), 0.06, 0.6)
	_box(Vector3(0.3, 0.98, -2.5), Vector3(0.3, 0.06, 0.1), WOOD, 0.0, 0.0, 0.01)
	for t in 4:
		_cyl(Vector3(0.18 + t * 0.08, 1.05, -2.5), 0.015, 0.16, [Color("#6fe0a0"), CREAM, Color("#e070a0"), Color("#9fd8ff")][t])
	_light(Vector3(-0.3, 1.4, -2.3), Color("#a8f0d0"), 0.8, 2.4)
	# microscópio na segunda bancada
	var micro := _box(Vector3(-0.8, 0.98, -5.0), Vector3(0.22, 0.06, 0.28), INK)
	_box(Vector3(-0.8, 1.16, -5.1), Vector3(0.06, 0.32, 0.06), METAL_D, 0.0, 0.0, 0.01)
	var tubo := _cyl(Vector3(-0.8, 1.3, -5.0), 0.035, 0.26, INK)
	tubo.rotation.x = 0.4
	_flat(Vector3(-0.8, 1.05, -4.98), Vector3(0.14, 0.01, 0.12), METAL)
	_cyl(Vector3(-0.6, 1.25, -5.0), 0.03, 0.5, NAVY)
	_cyl(Vector3(-0.6, 1.5, -5.0), 0.11, 0.08, YEL, 0.04, 1.0)
	_light(Vector3(-0.65, 1.4, -4.8), WARM, 1.2, 2.5)
	# armário de vidros à direita, com frascos
	var arm := _box(Vector3(2.9, 1.2, -5.2), Vector3(0.9, 2.4, 0.5), WOOD_D)
	_flat(Vector3(2.9, 1.4, -4.94), Vector3(0.75, 1.7, 0.01), Color("#6f8fd8"), 0.0, 0.25, Color("#6f8fd8"))
	var jars := []
	for r in 3:
		for j in 5:
			jars.append([Vector3(2.62 + j * 0.14, 0.8 + r * 0.55, -5.0), Vector3(0.09, 0.18 + (j % 2) * 0.06, 0.09), [CREAM, Color("#6fe0a0"), Color("#a8873d"), Color("#e070a0")][(r + j) % 4]])
	for r in 3:
		_flat(Vector3(2.9, 0.7 + r * 0.55, -5.05), Vector3(0.75, 0.02, 0.35), WOOD)
	jars.append_array(cells)
	_mm(jars)
	# esqueleto de plástico de enfeite, com boné
	var esq := _cyl(Vector3(2.7, 1.1, -2.2), 0.05, 0.9, CREAM)
	_ball(Vector3(2.7, 1.72, -2.2), 0.13, CREAM, Vector3(1, 1.1, 1))
	_cyl(Vector3(2.7, 1.83, -2.2), 0.14, 0.06, RED, 0.12)
	_box(Vector3(2.7, 1.8, -2.08), Vector3(0.16, 0.02, 0.12), RED, 0.0, 0.0, 0.006)
	for r in 3:
		_box(Vector3(2.7, 1.38 - r * 0.1, -2.2), Vector3(0.3 - r * 0.03, 0.025, 0.14), CREAM, 0.0, 0.0, 0.008)
	_box(Vector3(2.7, 0.95, -2.2), Vector3(0.3, 0.1, 0.12), CREAM, 0.0, 0.0, 0.01)
	for s in [-1, 1]:
		_box(Vector3(2.7 + s * 0.2, 1.2, -2.2), Vector3(0.03, 0.5, 0.03), CREAM, 0.0, 0.0, 0.008).rotation.z = s * 0.25
		_box(Vector3(2.7 + s * 0.08, 0.5, -2.2), Vector3(0.035, 0.75, 0.035), CREAM, 0.0, 0.0, 0.008)
	_cyl(Vector3(2.7, 0.04, -2.2), 0.2, 0.06, METAL_D)
	_ball(Vector3(2.66, 1.73, -2.08), 0.025, INK)
	_ball(Vector3(2.74, 1.73, -2.08), 0.025, INK)
	_flavor(esq, "O esqueleto Juvenal. Usa boné desde a última festa junina. Ninguém teve coragem de tirar.")
	# extintor e lava-olhos
	var ext := _cyl(Vector3(3.38, 0.5, -3.6), 0.1, 0.5, RED)
	_flavor(ext, "O extintor. Validade vencida, mas a postura é impecável.")
	_tube(Vector3(0, 3.02, -3.8), 1.6, true)
	_anchors = {
		"bancada": {"mesh": bancadas[1], "say": "A bancada do fundo. Uma mancha queimada no formato do Brasil."},
		"microscopio": {"mesh": micro, "say": "O microscópio. Na lâmina, uma célula de cebola. Ou um fio de cabelo. Ou um crime."},
		"armario_vidros": {"mesh": arm, "say": "O armário de vidros. Frascos com rótulos que você prefere não ler."},
		"quadro_tabela": {"mesh": tab, "say": "A tabela periódica. Alguém colou um adesivo de \"Ca\" + \"Fé\" no canto."},
		"pia": {"mesh": pia, "say": "A pia do laboratório. A torneira pinga num ritmo que parece código Morse."},
	}
	_free_anchors = [{"pos": Vector3(0.6, 0.98, -5.0), "size": Vector3(0.3, 0.05, 0.25)}, {"pos": Vector3(-1.0, 0.98, -2.6), "size": Vector3(0.2, 0.1, 0.2)}]
	_moon(Vector3(0.9, -0.6, -0.3), 1.0)
	_camera(Vector3(0.7, 2.5, 2.6), Vector3(-0.2, 1.0, -4.8), 0.45)


func _scene_sala_musica() -> void:
	_flat(Vector3(0, -0.05, -2.8), Vector3(7, 0.1, 9.6), Color("#5a4a5e"))
	_disc(Vector3(-0.6, 0.006, -4.4), 1.4, Color("#3a2a4e"), Vector3(1.2, 1, 0.9))
	_flat(Vector3(0, 3.0, -2.8), Vector3(7, 0.1, 9.6), CEIL)
	_flat(Vector3(-3.5, 1.5, -2.8), Vector3(0.1, 3.0, 9.6), WALL_M)
	_flat(Vector3(3.5, 1.5, -2.8), Vector3(0.1, 3.0, 9.6), WALL_M)
	_flat(Vector3(0, 1.5, -7.05), Vector3(7, 3.0, 0.1), WALL)
	# isolamento acústico: placas de espuma no fundo (cunhas em MultiMesh)
	var foam := []
	for r in 4:
		for c in 10:
			var rot := Basis(Vector3.UP, 0.0) if (r + c) % 2 == 0 else Basis(Vector3(0, 0, 1), PI / 2.0)
			foam.append([Vector3(-3.0 + c * 0.6, 1.0 + r * 0.55, -6.95), Vector3(0.52, 0.48, 0.08), Color("#2e3b6b") if (r * c) % 3 else Color("#26335f"), rot])
	_mm(foam)
	# piano de armário à esquerda, com tampa aberta e partitura
	var piano := _box(Vector3(-2.7, 0.65, -4.4), Vector3(0.6, 1.3, 1.5), INK)
	_box(Vector3(-2.35, 0.72, -4.4), Vector3(0.3, 0.06, 1.4), INK, 0.0, 0.0, 0.012)
	_flat(Vector3(-2.3, 0.76, -4.4), Vector3(0.18, 0.02, 1.35), PAPER)
	var keys := []
	for k in 20:
		if k % 7 != 2 and k % 7 != 6:
			keys.append([Vector3(-2.36, 0.785, -5.0 + k * 0.064), Vector3(0.1, 0.02, 0.035), INK])
	_flat(Vector3(-2.4, 1.05, -4.4), Vector3(0.02, 0.26, 0.36), CREAM).rotation.z = 0.2
	_box(Vector3(-2.0, 0.25, -4.4), Vector3(0.35, 0.5, 0.9), WOOD_D, 0.0, 0.0, 0.012)
	_cyl(Vector3(-2.7, 1.38, -4.0), 0.06, 0.14, YEL, 0.04, 0.4)   # metrônomo
	_cyl(Vector3(-2.7, 1.33, -4.8), 0.05, 0.05, CREAM)
	# bateria no tapete
	var bumbo := _cyl(Vector3(-0.6, 0.32, -4.6), 0.32, 0.36, RED_D)
	bumbo.rotation.x = PI / 2.0
	_disc(Vector3(-0.6, 0.32, -4.41), 0.27, CREAM).rotation.x = PI / 2.0
	_text(Vector3(-0.6, 0.32, -4.4), "OS\nSUSPEITOS", 0.06, INK, "marker")
	_cyl(Vector3(-1.05, 0.55, -4.4), 0.17, 0.14, RED_D)
	_cyl(Vector3(-0.3, 0.75, -4.75), 0.14, 0.12, RED_D)
	_cyl(Vector3(-0.85, 0.75, -4.75), 0.14, 0.12, RED_D)
	for p in [[-1.35, 1.0, -4.6, 0.24], [0.1, 1.2, -4.85, 0.28]]:
		_cyl(Vector3(p[0], p[1] * 0.5, p[2]), 0.015, p[1], METAL_D)
		_cyl(Vector3(p[0], p[1], p[2]), p[3], 0.015, Color("#c9a24a"), 0.02)
	_cyl(Vector3(-0.6, 0.25, -5.3), 0.16, 0.04, INK)
	_cyl(Vector3(-0.6, 0.12, -5.3), 0.02, 0.24, METAL_D)
	_flat(Vector3(-0.3, 0.6, -4.3), Vector3(0.01, 0.01, 0.35), WOOD).rotation.x = 0.5   # baqueta
	# amplificador com luzinha e cabo, guitarra encostada
	var amp := _box(Vector3(1.2, 0.35, -5.6), Vector3(0.7, 0.7, 0.4), INK)
	_flat(Vector3(1.2, 0.3, -5.39), Vector3(0.6, 0.5, 0.01), Color("#2a2a3e"))
	_flat(Vector3(1.0, 0.64, -5.39), Vector3(0.03, 0.03, 0.01), RED, 0.0, 2.0, RED)
	_flat(Vector3(1.2, 0.65, -5.39), Vector3(0.4, 0.04, 0.01), Color("#c9a24a"))
	_flavor(amp, "O amplificador. Volume no 11. A diretoria colocou fita no botão.")
	var guit := _ball(Vector3(1.7, 0.45, -5.5), 0.2, Color("#a8873d"), Vector3(1, 1.3, 0.35))
	guit.rotation.z = 0.2
	_box(Vector3(1.6, 0.95, -5.5), Vector3(0.06, 0.7, 0.04), WOOD_DD, 0.2, 0.0, 0.01).rotation.z = 0.2
	_flat(Vector3(1.0, 0.004, -5.0), Vector3(1.4, 0.008, 0.02), INK, 0.6)
	# estante de partituras com folhas
	var est := _box(Vector3(0.6, 1.1, -3.2), Vector3(0.5, 0.36, 0.03), METAL_D, -0.4)
	est.rotation.x = -0.3
	_flat(Vector3(0.6, 0.55, -3.15), Vector3(0.025, 1.1, 0.025), METAL_D)
	_flat(Vector3(0.62, 1.12, -3.17), Vector3(0.38, 0.28, 0.01), PAPER, -0.4).rotation.x = -0.3
	_flat(Vector3(0.6, 0.02, -3.15), Vector3(0.4, 0.02, 0.04), METAL_D, 0.6)
	_box(Vector3(0.9, 0.02, -2.9), Vector3(0.22, 0.01, 0.3), PAPER, 0.8, 0.0, 0.006)
	# armário de instrumentos à direita: violão, flautas, pandeiro
	var arm := _box(Vector3(3.1, 1.15, -4.8), Vector3(0.7, 2.3, 1.6), WOOD_D)
	_flat(Vector3(2.74, 1.15, -4.8), Vector3(0.02, 2.1, 1.45), WOOD_DD)
	_box(Vector3(2.7, 1.15, -4.0), Vector3(0.03, 2.1, 0.7), WOOD, 0.6, 0.0, 0.012)
	_ball(Vector3(2.85, 0.65, -4.5), 0.2, Color("#a8873d"), Vector3(0.4, 1.3, 1))
	_flat(Vector3(2.85, 1.25, -4.5), Vector3(0.04, 0.8, 0.05), WOOD_DD)
	_torus(Vector3(2.8, 1.7, -5.2), 0.12, 0.16, Color("#c9a24a"), Vector3(0, 0, PI / 2.0))
	for f in 3:
		_flat(Vector3(2.85, 2.05, -5.3 + f * 0.08), Vector3(0.03, 0.03, 0.4), CREAM)
	_flavor(_box(Vector3(2.9, 0.12, -3.4), Vector3(0.3, 0.24, 0.3), INK, 0.3), "Um estojo de triângulo. O triângulo sumiu. O silêncio agradece.")
	# quadro de horários na porta / parede direita, perto da câmera
	var quadro := _box(Vector3(3.44, 1.6, -2.4), Vector3(0.04, 0.8, 1.0), CREAM, 0.0, 0.0, 0.012)
	_text(Vector3(3.41, 1.85, -2.4), "HORÁRIOS", 0.1, INK, "bebas", -PI / 2.0)
	for r in 4:
		_flat(Vector3(3.41, 1.68 - r * 0.13, -2.4), Vector3(0.005, 0.02, 0.8), WALL_M)
	_flat(Vector3(3.41, 1.42, -2.2), Vector3(0.005, 0.1, 0.3), YEL)
	# cadeiras em meia-lua
	for c in 3:
		_chair(Vector3(-0.4 + c * 0.75, 0, -2.4 + absf(c - 1) * 0.25), PI - (c - 1) * 0.4, Color("#55608f"))
	var cartaz := _box(Vector3(-3.44, 2.0, -2.4), Vector3(0.02, 0.9, 0.65), Color("#26407a"), 0.0, 0.0, 0.01)
	_text(Vector3(-3.42, 2.1, -2.4), "FESTIVAL\nDA CANÇÃO", 0.1, CREAM, "marker", PI / 2.0)
	_flavor(cartaz, "Cartaz do festival da canção. A vencedora do ano passado ainda canta no recreio. Sem parar.")
	_mm(keys)
	_light(Vector3(-0.6, 2.2, -4.4), WARM, 2.2, 4.5)
	_light(Vector3(2.0, 2.2, -3.0), Color("#9fb8ff"), 1.0, 4.0)
	_anchors = {
		"piano": {"mesh": piano, "say": "O piano. Duas teclas não tocam. Por isso todo mundo só sabe tocar música triste."},
		"bateria": {"mesh": bumbo, "say": "A bateria da banda \"Os Suspeitos\". O nome não ajuda nesse momento."},
		"estante_partituras": {"mesh": est, "say": "Partitura de \"Asa Branca\" com anotações: \"aqui erra sempre\"."},
		"armario_instrumentos": {"mesh": arm, "say": "O armário de instrumentos. Uma flauta doce que já viu coisas demais."},
		"quadro_horarios": {"mesh": quadro, "say": "Horários da sala. Alguém riscou \"ensaio do coral\" e escreveu \"FUGA\"."},
	}
	_free_anchors = [{"pos": Vector3(0.0, 0.5, -2.4), "size": Vector3(0.3, 0.05, 0.25)}, {"pos": Vector3(-1.6, 0.1, -3.2), "size": Vector3(0.3, 0.15, 0.3)}]
	_moon(Vector3(0.6, -0.7, -0.3), 0.7)
	_camera(Vector3(0.5, 2.4, 2.6), Vector3(-0.3, 0.9, -4.6), 0.45)


## fachada da escola à noite, só para o menu: chuva, poste amarelo e uma janela acesa no 2º andar
func _scene_fachada() -> void:
	_sky(Color("#060c22"), Color("#22356a"), 0.75, Color("#0e1838"), 0.022)
	# rua, calçada e meio-fio
	_flat(Vector3(0, -0.05, 4), Vector3(40, 0.1, 12), Color("#26304e"))
	for i in 5:
		_flat(Vector3(-8 + i * 4.0, 0.003, 6.5), Vector3(1.8, 0.004, 0.14), Color("#8a96b8"))
	_flat(Vector3(0, 0.08, -1.0), Vector3(40, 0.16, 2.6), Color("#4a5684"))
	_flat(Vector3(0, 0.08, 0.32), Vector3(40, 0.16, 0.08), WALL_L)
	_flat(Vector3(0, -0.04, -8), Vector3(40, 0.1, 12), Color("#3a4a7a"))
	# prédio: dois andares, faixa de cornija, caixa d'água no telhado
	var BZ := -9.0
	_flat(Vector3(0, 3.6, BZ), Vector3(16, 7.2, 0.4), WALL)
	_flat(Vector3(0, 3.6, BZ + 0.22), Vector3(16, 0.18, 0.12), WALL_L)
	_flat(Vector3(0, 7.25, BZ + 0.1), Vector3(16.4, 0.3, 0.7), WALL_L)
	_flat(Vector3(0, 0.3, BZ + 0.21), Vector3(16, 0.6, 0.05), NAVY)
	_box(Vector3(5.0, 8.1, BZ - 0.5), Vector3(1.6, 1.2, 1.4), METAL, 0.0, 0.0, 0.02)
	for lx in [4.4, 5.6]:
		_flat(Vector3(lx, 7.45, BZ - 0.5), Vector3(0.08, 0.5, 0.08), METAL_D)
	for f in 2:
		for c in 8:
			var x := -7.0 + c * 2.0
			if f == 0 and absf(x) < 1.5:
				continue
			var lit := f == 1 and c == 5
			_flat(Vector3(x, 2.0 + f * 3.4, BZ + 0.21), Vector3(1.1, 1.4, 0.04), YEL if lit else Color("#1a2856"), 0.0, 1.8 if lit else 0.0, YEL)
			_flat(Vector3(x, 1.25 + f * 3.4, BZ + 0.28), Vector3(1.3, 0.08, 0.14), WALL_L)
			_flat(Vector3(x, 2.0 + f * 3.4, BZ + 0.24), Vector3(0.04, 1.4, 0.03), INK)
	_light(Vector3(3.0, 5.4, BZ + 1.2), YEL, 1.6, 4.5)
	# silhueta na janela acesa (alguém ficou até tarde...)
	_flat(Vector3(3.15, 5.3, BZ + 0.25), Vector3(0.3, 0.7, 0.02), INK)
	_ball(Vector3(3.15, 5.78, BZ + 0.25), 0.15, INK, Vector3(1, 1, 0.1))
	# entrada: porta dupla, marquise e letreiro
	_flat(Vector3(0, 1.3, BZ + 0.22), Vector3(2.0, 2.6, 0.06), Color("#26335f"))
	_flat(Vector3(0, 1.3, BZ + 0.26), Vector3(0.04, 2.6, 0.03), INK)
	_flat(Vector3(0, 2.9, BZ + 0.7), Vector3(3.0, 0.15, 1.4), WALL_L)
	_flat(Vector3(0, 2.8, BZ + 1.0), Vector3(0.3, 0.04, 0.3), Color("#dfe8ff"), 0.0, 1.0, Color("#dfe8ff"))
	_box(Vector3(0, 3.55, BZ + 0.28), Vector3(4.2, 0.85, 0.12), NAVY, 0.0, 0.0, 0.02)
	_text(Vector3(0, 3.55, BZ + 0.36), "ESCOLA", 0.62, CREAM, "bebas", 0.0, 10)
	_text(Vector3(0, 3.2, BZ + 0.36), "DESDE 1974", 0.13, Color("#9aa6c8"), "bebas")
	_light(Vector3(0, 2.6, BZ + 1.5), Color("#cfdcff"), 0.9, 4.0)
	# muro com grade e portão entreaberto
	for side in [-1, 1]:
		_flat(Vector3(side * 5.25, 0.55, -2.4), Vector3(7.5, 1.1, 0.3), WALL_M)
		_flat(Vector3(side * 5.25, 1.12, -2.4), Vector3(7.6, 0.06, 0.36), WALL_L)
		_flat(Vector3(side * 1.55, 1.2, -2.4), Vector3(0.3, 2.4, 0.35), WALL_L)
	var bars := []
	for side in [-1, 1]:
		for b in 24:
			bars.append([Vector3(side * (1.9 + b * 0.3), 1.65, -2.4), Vector3(0.03, 1.0, 0.03), INK])
		bars.append([Vector3(side * 5.25, 2.1, -2.4), Vector3(7.4, 0.04, 0.04), INK])
	# portão: uma folha fechada e outra entreaberta
	for b in 6:
		bars.append([Vector3(-1.25 + b * 0.22, 1.05, -2.4), Vector3(0.03, 2.0, 0.03), INK])
	var gate_rot := Basis(Vector3.UP, -0.7)
	for b in 6:
		var off := gate_rot * Vector3(-b * 0.22, 0, 0)
		bars.append([Vector3(1.38, 1.05, -2.4) + off, Vector3(0.03, 2.0, 0.03), INK])
	bars.append([Vector3(-0.7, 2.02, -2.4), Vector3(1.2, 0.05, 0.05), INK])
	bars.append([Vector3(-0.7, 0.1, -2.4), Vector3(1.2, 0.05, 0.05), INK])
	bars.append([Vector3(1.38, 2.02, -2.4) + gate_rot * Vector3(-0.55, 0, 0), Vector3(1.2, 0.05, 0.05), INK, gate_rot])
	_mm(bars)
	# gato no muro (o único que não tem medo da escola à noite)
	_ball(Vector3(-3.4, 1.32, -2.4), 0.14, INK, Vector3(1.4, 0.9, 0.9))
	_ball(Vector3(-3.25, 1.48, -2.4), 0.09, INK)
	_box(Vector3(-3.22, 1.58, -2.43), Vector3(0.04, 0.07, 0.03), INK, 0.0, 0.0, 0.0)
	_box(Vector3(-3.28, 1.58, -2.37), Vector3(0.04, 0.07, 0.03), INK, 0.0, 0.0, 0.0)
	_box(Vector3(-3.6, 1.25, -2.4), Vector3(0.04, 0.3, 0.04), INK, 0.0, 0.0, 0.0).rotation.z = 0.6
	# poste de luz amarela com facho na chuva
	_cyl(Vector3(-3.0, 2.2, 0.6), 0.09, 4.4, METAL_D, 0.07)
	_box(Vector3(-2.6, 4.35, 0.6), Vector3(0.9, 0.08, 0.12), METAL_D, 0.0, 0.0, 0.015)
	_cyl(Vector3(-2.2, 4.28, 0.6), 0.2, 0.14, INK, 0.12)
	_cyl(Vector3(-2.2, 4.2, 0.6), 0.15, 0.03, YEL, -1.0, 2.5)
	var luz := SpotLight3D.new()
	luz.position = Vector3(-2.2, 4.15, 0.6)
	luz.light_color = Color("#ffcf70")
	luz.light_energy = 4.0
	luz.spot_range = 8.0
	luz.spot_angle = 40.0
	world.add_child(luz)
	luz.look_at(Vector3(-2.0, 0, 0.8), Vector3(0, 0, -1))
	_beam(Vector3(-2.2, 4.15, 0.6), Vector3(-2.0, 0.0, 0.8), 0.12, 2.2, Color("#ffcf70"), 0.07)
	# árvore do lado direito, por cima do muro
	_cyl(Vector3(4.2, 1.6, -3.6), 0.2, 3.2, WOOD_DD, 0.15)
	for b in [[0, 3.6, 0, 1.4], [-0.9, 3.1, 0.3, 1.0], [0.9, 3.2, -0.2, 1.1], [0.2, 4.4, 0.1, 0.9], [-0.4, 3.0, 0.8, 0.8]]:
		_ball(Vector3(4.2 + b[0], b[1], -3.6 + b[2]), b[3], LEAF)
	# placa de rua e lixeira na calçada
	_cyl(Vector3(2.4, 1.1, -0.4), 0.03, 2.2, METAL_D)
	_box(Vector3(2.4, 2.1, -0.4), Vector3(0.6, 0.6, 0.03), Color("#e0c040"), 0.785, 0.0, 0.01).rotation = Vector3(0, 0, PI / 4.0)
	_cyl(Vector3(1.5, 0.5, -0.6), 0.2, 0.7, Color("#4f7a5a"), 0.22)
	# poças refletindo o poste e a janela acesa
	_puddle(Vector3(-2.0, 0, 2.2), Vector2(1.3, 0.7), YEL, 0.1)
	_puddle(Vector3(1.4, 0, 3.6), Vector2(1.0, 0.5), Color("#9fb8ff"))
	_puddle(Vector3(3.0, 0, 1.6), Vector2(0.8, 0.4), YEL, 0.0)
	_moon_disc(Vector3(-2.4, 13.5, -26.0), 1.3)
	# morros/prédios distantes atrás da escola
	for b in [[-12, 4, 6], [-6, 3, 5], [9, 5, 6], [14, 3.5, 5]]:
		_flat(Vector3(b[0], b[1] * 0.5 + 1.0, -16), Vector3(b[2], b[1] + 2, 0.5), Color("#141e44"))
	_rain(Vector3(0, 4.5, -1.5), Vector3(13, 9, 7), 380)
	_anchors = {}
	_free_anchors = []
	_moon(Vector3(0.6, -0.6, -0.5), 0.8)
	_camera(Vector3(0.4, 1.7, 7.2), Vector3(0.2, 3.9, -6.0), 0.35)


# ------------------------------------------------------------------ interação
func _process(dt: float) -> void:
	_t += dt
	for g in _glows:
		var r: Node3D = g["ring"]
		if r.visible:
			r.position.y += sin(_t * 3.0) * 0.002
			r.rotation.z += dt * 1.5
			var s := 1.0 + sin(_t * 4.0) * 0.12
			r.scale = Vector3(s, s, s)
			(g["light"] as OmniLight3D).light_energy = 1.3 + sin(_t * 4.0) * 0.5
	# vida barata da cena: chuva caindo, lâmpada que pisca, ventilador girando
	for r in _rains:
		var n: Node3D = r["node"]
		n.position.y -= dt * float(r["speed"])
		if n.position.y < float(r["y0"]) - float(r["h"]):
			n.position.y += float(r["h"])
	for f in _flickers:
		var k := 1.0
		if fmod(_t + float(f["seed"]), 5.3) < 0.55:
			k = 0.12 if sin(_t * 47.0) > 0.1 else 1.0
		(f["light"] as OmniLight3D).light_energy = float(f["base"]) * k
		(f["mat"] as ShaderMaterial).set_shader_parameter("emission_energy", float(f["emit"]) * k)
	for s in _spinners:
		(s["node"] as Node3D).rotation.y += dt * float(s["speed"])
	if _showcase:
		# vitrine do menu: deriva lenta em yaw e pitch, como quem passeia na frente da escola
		_yaw = sin(_t * 0.11) * _yaw_limit
		_pitch = sin(_t * 0.07 + 1.0) * 0.05
	if pivot:
		pivot.rotation.y = lerpf(pivot.rotation.y, _yaw, 0.15)
		pivot.rotation.x = lerpf(pivot.rotation.x, _pitch, 0.15)


func _gui_input(e: InputEvent) -> void:
	if _showcase:
		return
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := e as InputEventMouseButton
		if mb.pressed:
			_down = true
			_moved = false
			_press = mb.position
		else:
			_down = false
			if not _moved:
				_tap(mb.position)
		accept_event()
	elif e is InputEventMouseMotion and _down:
		var mm := e as InputEventMouseMotion
		if mm.position.distance_to(_press) > 12.0:
			_moved = true
		_yaw = clampf(_yaw - mm.relative.x * 0.004, -_yaw_limit, _yaw_limit)
		_pitch = clampf(_pitch - mm.relative.y * 0.002, -0.15, 0.12)
		accept_event()


func _tap(pos: Vector2) -> void:
	var vp_pos := pos / float(stretch_shrink)
	var from := cam.project_ray_origin(vp_pos)
	var dir := cam.project_ray_normal(vp_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 40.0)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var d: Dictionary = _targets.get((hit["collider"] as Object).get_instance_id(), {})
	if d.is_empty():
		return
	if d["kind"] == "person":
		person_tapped.emit(str(d["id"]))
		return
	var mi: MeshInstance3D = d["mesh"]
	var tw := create_tween()
	tw.tween_property(mi, "scale", mi.scale * 1.08, 0.08)
	tw.tween_property(mi, "scale", mi.scale, 0.12)
	if d["kind"] == "hotspot":
		hotspot_tapped.emit(str(d["id"]), str(d["label"]))
	else:
		flavor_tapped.emit(str(d["text"]))
