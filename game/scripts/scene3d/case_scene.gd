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
	"corredor": [Vector3(0.9, 0, -3.6), Vector3(-1.1, 0, -6.6), Vector3(1.1, 0, -8.8)],
	"biblioteca": [Vector3(-1.4, 0, -2.6), Vector3(0.4, 0, -5.4), Vector3(2.3, 0, -1.7)],
	"teatro": [Vector3(-1.0, 0.9, -7.0), Vector3(1.9, 0.9, -7.3), Vector3(-3.5, 0, -2.6)],
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
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0a1430")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#2a3f78")
	e.ambient_light_energy = 0.9
	e.fog_enabled = true
	e.fog_light_color = Color("#16244d")
	e.fog_density = 0.025
	env.environment = e
	world.add_child(env)

	pivot = Node3D.new()
	world.add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 62
	pivot.add_child(cam)

	match scene_id:
		"biblioteca": _scene_biblioteca()
		"teatro": _scene_teatro()
		_: _scene_corredor()
	_place_hotspots()
	_place_people()


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
			_box(Vector3(-W / 2 + j * W + (W / 2 if j == 0 else -W / 2), -0.05, -i * 2.0), Vector3(W, 0.1, 2.0),
				Color("#5d6f9e") if (i + j) % 2 == 0 else Color("#46578a"), 0.0, 0.0, 0.0)
	_box(Vector3(0, 3.3, -7), Vector3(W * 2, 0.1, 16), Color("#2a3866"), 0.0, 0.0, 0.0)
	_box(Vector3(-W - 0.05, 1.65, -7), Vector3(0.1, 3.3, 16), Color("#6d7fb0"), 0.0, 0.0, 0.0)
	# armários à esquerda (um vermelho, um entreaberto)
	for k in 26:
		var z := 0.8 - k * 0.5
		if z < -4.2 and z > -5.8:
			continue
		var col := Color("#5a7ab8") if k % 2 == 0 else Color("#4c68a6")
		if k == 7:
			col = Color("#b34a5e")
		var lk := _box(Vector3(-W + 0.25, 1.0, z), Vector3(0.5, 1.95, 0.47), col, 0.0, 0.0, 0.015)
		_box(Vector3(-W + 0.505, 1.65, z), Vector3(0.01, 0.06, 0.28), Color("#1b2650"), 0.0, 0.0, 0.0)
		_box(Vector3(-W + 0.505, 1.55, z), Vector3(0.01, 0.06, 0.28), Color("#1b2650"), 0.0, 0.0, 0.0)
		if k == 3:
			_flavor(lk, "Um armário trancado. Cheira a meia de educação física. Melhor não.")
		elif k == 7:
			_flavor(lk, "O armário vermelho. Todo corredor tem um. Ninguém sabe por quê.")
		elif k == 11:
			_flavor(lk, "Um adesivo de banda que você nunca ouviu falar. Respeito.")
	# parede direita com janelas e chuva lá fora
	_box(Vector3(W + 0.05, 0.5, -7), Vector3(0.1, 1.0, 16), Color("#3b4c80"), 0.0, 0.0, 0.0)
	_box(Vector3(W + 0.05, 3.0, -7), Vector3(0.1, 0.6, 16), Color("#6d7fb0"), 0.0, 0.0, 0.0)
	for j in 6:
		var z := 0.6 - j * 3.0
		_box(Vector3(W + 0.05, 1.85, z - 1.5), Vector3(0.14, 1.7, 0.6), Color("#6d7fb0"), 0.0, 0.0, 0.0)
		_box(Vector3(W + 0.05, 1.95, z), Vector3(0.06, 0.05, 2.4), Color("#26335f"), 0.0, 0.0, 0.0)
		_box(Vector3(W + 0.05, 1.85, z), Vector3(0.06, 1.7, 0.05), Color("#26335f"), 0.0, 0.0, 0.0)
	_box(Vector3(W + 2.0, 2, -7), Vector3(0.1, 8, 30), Color("#3557a8"), 0.0, 0.9, 0.0, Color("#3557a8"))
	var banco := _box(Vector3(W - 0.35, 0.42, -2.2), Vector3(0.5, 0.08, 1.6), Color("#7a5a3e"))
	_box(Vector3(W - 0.35, 0.2, -1.6), Vector3(0.4, 0.4, 0.06), Color("#3b2a20"))
	_box(Vector3(W - 0.35, 0.2, -2.8), Vector3(0.4, 0.4, 0.06), Color("#3b2a20"))
	# porta do fundo acesa e luz de saída
	_box(Vector3(0, 1.65, -15), Vector3(W * 2, 3.3, 0.1), Color("#6d7fb0"), 0.0, 0.0, 0.0)
	var porta := _box(Vector3(0, 1.1, -14.92), Vector3(1.3, 2.2, 0.06), Color("#33406e"))
	_box(Vector3(0, 1.6, -14.88), Vector3(0.45, 0.6, 0.02), Color("#ffc83d"), 0.0, 3.0, 0.0, Color("#ffc83d"))
	_flavor(porta, "A porta da diretoria. A luz está acesa. Sempre está.")
	_light(Vector3(0, 1.7, -13.8), Color("#ffc380"), 2.2, 6.0)
	# vão com quadro de avisos e mural da banda
	var quadro := _box(Vector3(-W + 0.04, 1.6, -4.6), Vector3(0.06, 1.0, 1.1), Color("#7a5a3e"))
	var mural := _box(Vector3(-W + 0.04, 1.5, -5.6), Vector3(0.06, 0.9, 0.7), Color("#26407a"))
	for p in [[-4.35, 1.8], [-4.75, 1.75], [-4.5, 1.4], [-4.85, 1.38]]:
		_box(Vector3(-W + 0.08, p[1], p[0]), Vector3(0.01, 0.3, 0.24), Color("#efe8d6"), 0.0, 0.0, 0.006)
	var cel := _box(Vector3(W - 0.3, 0.48, -2.4), Vector3(0.12, 0.02, 0.2), Color("#111a33"), 0.4, 0.0, 0.006)
	_box(Vector3(W - 0.3, 0.495, -2.4), Vector3(0.1, 0.005, 0.17), Color("#fff2b8"), 0.4, 2.5, 0.0, Color("#fff2b8"))
	_anchors = {
		"quadro_avisos": {"mesh": quadro}, "mural": {"mesh": mural}, "celular": {"mesh": cel},
	}
	_free_anchors = [{"mesh": banco}, {"pos": Vector3(-W + 0.6, 0.15, -1.0), "size": Vector3(0.3, 0.05, 0.25)}]
	_moon(Vector3(-1.0, -0.6, 0.25), 1.15)
	_camera(Vector3(-0.3, 1.55, 2.6), Vector3(0.1, 1.2, -4.5), 0.42)


func _scene_biblioteca() -> void:
	_box(Vector3(0, -0.05, -5), Vector3(10, 0.1, 14), Color("#4a3f6e"), 0.0, 0.0, 0.0)
	_box(Vector3(0, 3.6, -5), Vector3(10, 0.1, 14), Color("#241f45"), 0.0, 0.0, 0.0)
	_box(Vector3(0, 1.8, -12), Vector3(10, 3.6, 0.1), Color("#3d4a85"), 0.0, 0.0, 0.0)
	_box(Vector3(-5, 1.8, -5), Vector3(0.1, 3.6, 14), Color("#3d4a85"), 0.0, 0.0, 0.0)
	# janelão em arco no fundo com chuva
	_box(Vector3(1.5, 2.0, -11.9), Vector3(2.2, 2.4, 0.02), Color("#3557a8"), 0.0, 1.0, 0.0, Color("#3557a8"))
	_box(Vector3(1.5, 2.0, -11.85), Vector3(0.06, 2.4, 0.04), Color("#1b2650"), 0.0, 0.0, 0.0)
	_box(Vector3(1.5, 2.0, -11.85), Vector3(2.2, 0.06, 0.04), Color("#1b2650"), 0.0, 0.0, 0.0)
	# estantes com livros coloridos (cores apagadas, um ou outro vivo)
	var book_cols := [Color("#6b4a8a"), Color("#3d6a8a"), Color("#8a3d4f"), Color("#4f7a5a"), Color("#a8873d"), Color("#2e3b6b")]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for s in 3:
		var x := -3.6 + s * 0.0
		var z := -2.5 - s * 2.6
		var shelf := _box(Vector3(-3.4, 1.2, z), Vector3(0.5, 2.4, 2.0), Color("#5a3d2a"))
		for row in 4:
			var bz := z - 0.9
			while bz < z + 0.9:
				var w := rng.randf_range(0.06, 0.12)
				var h := rng.randf_range(0.32, 0.46)
				_box(Vector3(-3.15, 0.25 + row * 0.55 + h / 2.0, bz + w / 2.0), Vector3(0.36, h, w), book_cols[rng.randi() % book_cols.size()], 0.0, 0.0, 0.0)
				bz += w + 0.01
		if s == 0:
			_flavor(shelf, "Seção de enciclopédias. A poeira aqui tem mais idade que você.")
		elif s == 2:
			_flavor(shelf, "Alguém escondeu um mangá dentro de um livro de química. Clássico.")
	# mesas de estudo com abajures amarelos
	for t in 2:
		var tz := -3.0 - t * 3.0
		var mesa := _box(Vector3(1.2, 0.75, tz), Vector3(2.2, 0.08, 1.1), Color("#7a5a3e"))
		for lx in [0.2, 2.2]:
			_box(Vector3(lx, 0.37, tz), Vector3(0.08, 0.74, 0.9), Color("#3b2a20"))
		_cyl(Vector3(2.0, 0.95, tz - 0.3), 0.03, 0.4, Color("#26335f"))
		_cyl(Vector3(2.0, 1.17, tz - 0.3), 0.16, 0.14, Color("#ffc83d"), 0.06, 1.2)
		_light(Vector3(2.0, 1.1, tz - 0.3), Color("#ffc380"), 1.4, 3.0)
		if t == 1:
			_flavor(mesa, "Riscado na mesa: \"Prova de mat. é sexta?? socorro\". Atemporal.")
	# balcão da monitoria com caderno e pasta
	var balcao := _box(Vector3(2.6, 0.55, -0.8), Vector3(1.6, 1.1, 0.7), Color("#5a3d2a"))
	var caderno := _box(Vector3(2.3, 1.13, -0.8), Vector3(0.36, 0.04, 0.26), Color("#e8e2cc"), 0.3)
	var pasta := _box(Vector3(1.2, 0.82, -3.0), Vector3(0.34, 0.05, 0.26), Color("#c84a5e"), -0.2)
	var pc := _box(Vector3(3.1, 1.3, -0.85), Vector3(0.5, 0.35, 0.05), Color("#111a33"))
	_box(Vector3(3.1, 1.3, -0.82), Vector3(0.44, 0.29, 0.01), Color("#6fd3ff"), 0.0, 1.5, 0.0, Color("#6fd3ff"))
	_flavor(pc, "O computador da biblioteca. Ainda roda o mesmo papel de parede desde 2015.")
	_flavor(balcao, "Uma placa: \"Silêncio, por favor\". Alguém escreveu embaixo: \"tá ligado??\"")
	_anchors = {"caderno_entrada": {"mesh": caderno}, "pasta_gremio": {"mesh": pasta}}
	_free_anchors = [{"pos": Vector3(1.0, 0.82, -6.0), "size": Vector3(0.3, 0.05, 0.25)}, {"pos": Vector3(-2.8, 0.1, -1.4), "size": Vector3(0.3, 0.15, 0.3)}]
	_moon(Vector3(0.3, -0.7, 1.0), 0.9)
	_camera(Vector3(0.6, 1.9, 2.2), Vector3(0.3, 0.9, -3.8), 0.5)


func _scene_teatro() -> void:
	_box(Vector3(0, -0.05, -4), Vector3(12, 0.1, 14), Color("#3a2a3e"), 0.0, 0.0, 0.0)
	# palco elevado com cortina vermelha (o acento quente do lugar)
	_box(Vector3(0, 0.45, -7.5), Vector3(8, 0.9, 4), Color("#5a3d2a"))
	_box(Vector3(0, 2.5, -9.6), Vector3(8, 5, 0.1), Color("#1b2650"), 0.0, 0.0, 0.0)
	for side in [-1, 1]:
		var cort := _box(Vector3(side * 3.4, 2.6, -5.6), Vector3(1.4, 4.2, 0.25), Color("#8a2a3e"))
		for f in 4:
			_box(Vector3(side * (2.8 + f * 0.3), 2.6, -5.45), Vector3(0.05, 4.2, 0.05), Color("#5e1a2a"), 0.0, 0.0, 0.0)
		if side == -1:
			_flavor(cort, "A cortina do teatro. Se você puxar, sai uma nuvem de poeira e um grilo.")
	_box(Vector3(0, 4.6, -5.6), Vector3(8, 0.6, 0.3), Color("#8a2a3e"))
	# trono de papelão no palco e holofote amarelo
	var trono := _box(Vector3(0.6, 1.4, -7.8), Vector3(0.8, 1.0, 0.6), Color("#a8873d"))
	_box(Vector3(0.6, 2.1, -8.05), Vector3(0.8, 0.9, 0.1), Color("#a8873d"))
	_flavor(trono, "O trono do rei. É papelão pintado. A coroa sumiu faz duas peças.")
	var spot := SpotLight3D.new()
	spot.position = Vector3(0.6, 5.0, -5.0)
	spot.light_color = Color("#ffd27a")
	spot.light_energy = 3.0
	spot.spot_range = 9.0
	spot.spot_angle = 22.0
	world.add_child(spot)
	spot.look_at(Vector3(0.6, 0.9, -7.8), Vector3.UP)
	# fileiras de cadeiras
	for r in 3:
		for c in 6:
			var cx := -2.5 + c * 1.0
			var cz := -2.0 + r * 1.2
			_box(Vector3(cx, 0.45, cz), Vector3(0.7, 0.1, 0.6), Color("#6b2a3e"), 0.0, 0.0, 0.015)
			_box(Vector3(cx, 0.8, cz + 0.28), Vector3(0.7, 0.6, 0.08), Color("#6b2a3e"), 0.0, 0.0, 0.015)
	# depósito à esquerda: porta aberta, caixas de objetos de cena
	_box(Vector3(-5.5, 1.6, -4), Vector3(0.1, 3.2, 10), Color("#3d4a85"), 0.0, 0.0, 0.0)
	var caixa := _box(Vector3(-4.6, 0.3, -3.6), Vector3(0.8, 0.6, 0.6), Color("#a07a4a"))
	_box(Vector3(-4.6, 0.75, -4.4), Vector3(0.6, 0.5, 0.5), Color("#8a6a3e"))
	var figurino := _box(Vector3(-4.9, 1.2, -2.2), Vector3(0.1, 1.6, 1.0), Color("#26407a"))
	_flavor(figurino, "Arara de figurinos. Uma capa de vampiro, um bigode falso e... uma meia?")
	var quadro := _box(Vector3(4.2, 1.7, -3.2), Vector3(0.06, 1.0, 1.3), Color("#1e3a2e"))
	_box(Vector3(4.6, 1.6, -4), Vector3(0.1, 3.2, 10), Color("#3d4a85"), 0.0, 0.0, 0.0)
	_light(Vector3(-4.2, 2.0, -3.4), Color("#ffc380"), 1.2, 3.5)
	_anchors = {"caixa_props": {"mesh": caixa}, "quadro_teatro": {"mesh": quadro}}
	_free_anchors = [{"pos": Vector3(-1.4, 1.0, -6.6), "size": Vector3(0.4, 0.2, 0.3)}, {"pos": Vector3(2.4, 1.0, -7.0), "size": Vector3(0.3, 0.3, 0.3)}]
	_moon(Vector3(0.6, -0.8, -0.4), 0.6)
	_camera(Vector3(0.0, 2.6, 3.6), Vector3(-0.4, 1.0, -4.2), 0.55)


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
	if pivot:
		pivot.rotation.y = lerpf(pivot.rotation.y, _yaw, 0.15)
		pivot.rotation.x = lerpf(pivot.rotation.x, _pitch, 0.15)


func _gui_input(e: InputEvent) -> void:
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
