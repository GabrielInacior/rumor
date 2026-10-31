extends Node3D
## Um personagem do caso em 3D. Usa o modelo riggado (assets/characters/student.glb, animado pelo
## Mixamo) quando existe; senão monta um boneco provisório em código com a mesma interface.
## Interface usada pelas cenas e pela conversa: setup(card), set_expression(), set_talking(), play().

const TOON := preload("res://shaders/toon.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")
const FACE := preload("res://shaders/face_atlas.gdshader")
const MODEL_PATH := "res://assets/characters/student.glb"

const EYES := {"neutro": Vector2(0, 0), "feliz": Vector2(1, 0), "surpreso": Vector2(2, 0), "bravo": Vector2(3, 0),
	"desconfiado": Vector2(0, 1), "triste": Vector2(1, 1), "nervoso": Vector2(2, 1), "piscando": Vector2(3, 1)}
const MOUTH := {"neutro": Vector2(0, 0), "feliz": Vector2(1, 0), "falaA": Vector2(2, 0), "surpreso": Vector2(3, 0),
	"triste": Vector2(0, 1), "desconfiado": Vector2(1, 1), "nervoso": Vector2(2, 1), "falaE": Vector2(3, 1), "bravo": Vector2(2, 1)}

var card: Dictionary = {}
var expression := "neutro"
var talking := false
var model: Node3D
var anim: AnimationPlayer
var eyes_mat: ShaderMaterial
var mouth_mat: ShaderMaterial
var _blink_t := 2.0
var _talk_t := 0.0
var _talk_flip := false
var _bob := 0.0
var _placeholder := false
var _head: Node3D
var _body: Node3D


func setup(p_card: Dictionary) -> void:
	card = p_card
	for c in get_children():
		c.queue_free()
	if ResourceLoader.exists(MODEL_PATH):
		_build_model()
	else:
		_build_placeholder()
	var talk: Dictionary = card.get("talk", {})
	set_expression(str(talk.get("mood", "neutro")))
	play("idle")


func _look() -> Dictionary:
	return card.get("look", {})


func _toon(col: Color, outline := 0.012) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("halftone", 0.6)
	if outline > 0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("width", outline)
		m.next_pass = o
	return m


# ------------------------------------------------------------------ modelo riggado
func _build_model() -> void:
	var scn: PackedScene = load(MODEL_PATH)
	model = scn.instantiate()
	add_child(model)
	var look := _look()
	var colors := {
		"M_skin": Color(str(look.get("skin", "#c98d6b"))),
		"M_top": Color(str(look.get("top", "#4e6fc0"))),
		"M_pants": Color("#24305a"),
		"M_shoes": Color("#e9e6dc"),
		"M_hair": Color(str(look.get("hair_color", "#1c1830"))),
		"M_acc": Color("#1b2650"),
	}
	var hair := "Hair_" + str(look.get("hair", "curto"))
	var acc := "Acc_" + str(look.get("accessory", "nenhum"))
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var n := String(m.name)
		if n.begins_with("Hair_"):
			m.visible = n == hair
		elif n.begins_with("Acc_"):
			m.visible = n == acc
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s)
			var mname := src.resource_name if src else ""
			if mname.begins_with("M_face_eyes") or n.begins_with("Face_eyes"):
				eyes_mat = _face_mat(src, "eyes")
				m.set_surface_override_material(s, eyes_mat)
			elif mname.begins_with("M_face_mouth") or n.begins_with("Face_mouth"):
				mouth_mat = _face_mat(src, "mouth")
				m.set_surface_override_material(s, mouth_mat)
			else:
				var key := ""
				for k in colors:
					if mname.begins_with(k):
						key = k
				var col: Color = colors.get(key, Color("#7a86b0"))
				m.set_surface_override_material(s, _toon(col, 0.008))
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		anim = aps[0]


func _face_mat(src: Material, which: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FACE
	var tex: Texture2D = null
	var p := "res://assets/characters/%s_atlas.png" % which
	if ResourceLoader.exists(p):
		tex = load(p)
	elif src is BaseMaterial3D:
		tex = (src as BaseMaterial3D).albedo_texture
	m.set_shader_parameter("atlas", tex)
	return m


# ------------------------------------------------------------------ boneco provisório
func _build_placeholder() -> void:
	_placeholder = true
	var look := _look()
	_body = Node3D.new()
	add_child(_body)
	var top := Color(str(look.get("top", "#4e6fc0")))
	var skin := Color(str(look.get("skin", "#c98d6b")))
	var hair := Color(str(look.get("hair_color", "#1c1830")))
	_part(_body, _capsule(0.11, 0.85), Vector3(-0.1, 0.43, 0), _toon(Color("#24305a")))
	_part(_body, _capsule(0.11, 0.85), Vector3(0.1, 0.43, 0), _toon(Color("#24305a")))
	_part(_body, _capsule(0.27, 0.72), Vector3(0, 1.12, 0), _toon(top))
	_part(_body, _capsule(0.08, 0.6), Vector3(-0.32, 1.1, 0), _toon(top))
	_part(_body, _capsule(0.08, 0.6), Vector3(0.32, 1.1, 0), _toon(top))
	_head = Node3D.new()
	_head.position = Vector3(0, 1.66, 0)
	_body.add_child(_head)
	_part(_head, _sphere(0.24), Vector3.ZERO, _toon(skin), Vector3(1, 1.05, 0.95))
	_part(_head, _sphere(0.26), Vector3(0, 0.08, -0.04), _toon(hair), Vector3(1.0, 0.8, 1.0))
	# rosto: dois quadros com os atlas (ou desenhados provisoriamente se o atlas não existir)
	eyes_mat = _face_mat(null, "eyes")
	mouth_mat = _face_mat(null, "mouth")
	if eyes_mat.get_shader_parameter("atlas") != null:
		_face_quad(Vector3(0, 0.03, 0.235), Vector2(0.34, 0.17), eyes_mat)
		_face_quad(Vector3(0, -0.11, 0.22), Vector2(0.2, 0.1), mouth_mat)
	else:
		for x in [-0.08, 0.08]:
			_part(_head, _sphere(0.035), Vector3(x, 0.03, 0.22), _toon(Color("#0b0f1c"), 0.0))
		_part(_head, _capsule(0.015, 0.1), Vector3(0, -0.1, 0.22), _toon(Color("#5a2a2a"), 0.0)).rotation.z = PI / 2.0


func _face_quad(pos: Vector3, sz: Vector2, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = sz
	mi.mesh = q
	mi.material_override = mat
	mat.set("shader_parameter/full_uv", true)
	mi.position = pos
	_head.add_child(mi)


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 3
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s


# ------------------------------------------------------------------ expressão e animação
func set_expression(e: String) -> void:
	expression = e if EYES.has(e) else "neutro"
	_apply_face()


func set_talking(t: bool) -> void:
	talking = t
	_apply_face()


func _apply_face(blink := false) -> void:
	if eyes_mat:
		eyes_mat.set_shader_parameter("cell", EYES["piscando"] if blink else EYES.get(expression, Vector2.ZERO))
	if mouth_mat:
		var m: Vector2 = MOUTH.get(expression, Vector2.ZERO)
		if talking:
			m = MOUTH["falaA"] if _talk_flip else (MOUTH["falaE"] if expression in ["neutro", "feliz"] else MOUTH.get(expression, Vector2.ZERO))
		mouth_mat.set_shader_parameter("cell", m)


## Nome da animação do Mixamo (idle, falando, pensando...). No boneco provisório vira gesto simples.
func play(name: String) -> void:
	if anim:
		var target := ""
		for a in anim.get_animation_list():
			if String(a).to_lower().ends_with(name):
				target = a
		if target == "":
			for a in anim.get_animation_list():
				if String(a).to_lower().ends_with("idle"):
					target = a
		if target != "":
			var res := anim.get_animation(target)
			if res:
				res.loop_mode = Animation.LOOP_LINEAR
			anim.play(target, 0.3)
	_bob = 0.0


func _process(dt: float) -> void:
	_blink_t -= dt
	if _blink_t <= 0.0:
		_apply_face(true)
		get_tree().create_timer(0.12).timeout.connect(func() -> void:
			if is_instance_valid(self):
				_apply_face())
		_blink_t = randf_range(2.2, 4.5)
	if talking:
		_talk_t -= dt
		if _talk_t <= 0.0:
			_talk_flip = not _talk_flip
			_talk_t = randf_range(0.08, 0.16)
			_apply_face()
	if _placeholder and _body:
		_bob += dt
		_body.position.y = sin(_bob * 2.0) * 0.01
		if _head:
			_head.rotation.z = sin(_bob * 1.3) * (0.06 if talking else 0.02)
			_head.rotation.x = sin(_bob * 2.6) * (0.04 if talking else 0.0)
