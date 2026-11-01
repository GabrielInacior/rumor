class_name ItemModels
extends RefCounted
## Objetos low-poly do caso (mochila, celular, troféu...) montados com primitivas e o mesmo
## sombreamento pintado das cenas. Servem para a mochila em 3D e para as "fotos" do quadro.

const TOON := preload("res://shaders/toon.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")

static var _mats := {}


static func mat(col: Color, emit := 0.0) -> ShaderMaterial:
	var key := col.to_html() + str(emit)
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("emission_energy", emit)
	m.set_shader_parameter("emission_color", col)
	m.set_shader_parameter("halftone", 0.5)
	var o := ShaderMaterial.new()
	o.shader = OUTLINE
	o.set_shader_parameter("width", 0.012)
	m.next_pass = o
	_mats[key] = m
	return m


static func _add(root: Node3D, mesh: Mesh, pos: Vector3, col: Color, rot := Vector3.ZERO, scl := Vector3.ONE, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(col, emit)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	root.add_child(mi)
	return mi


static func box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


static func cyl(r: float, h: float, r2 := -1.0, seg := 14) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r if r2 < 0 else r2
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func ball(r: float, seg := 14) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = seg / 2
	return s


static func torus(ri: float, ro: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = ri
	t.outer_radius = ro
	t.rings = 16
	t.ring_segments = 8
	return t


## kind: celular, mensagem, onibus, trofeu, livro, carta, chocolate, carregador, baqueta, fita,
## computador, pizza, chave, mochila, coroa, camera, papel, microfone, bola, prancheta, caixa,
## cartaz, wifi, relogio, sacola. Desconhecido vira uma caixa de evidência.
static func build(kind: String) -> Node3D:
	var r := Node3D.new()
	var Y := Color("#ffc83d")
	var NAVY := Color("#1b2650")
	var PAPER := Color("#efe8d6")
	match kind:
		"celular", "mensagem":
			_add(r, box(Vector3(0.36, 0.7, 0.05)), Vector3.ZERO, Color("#151a2e"))
			_add(r, box(Vector3(0.31, 0.6, 0.01)), Vector3(0, 0.01, 0.028), Color("#9fd3ff"), Vector3.ZERO, Vector3.ONE, 1.2)
			if kind == "mensagem":
				_add(r, box(Vector3(0.22, 0.09, 0.01)), Vector3(-0.03, 0.12, 0.036), Color.WHITE, Vector3.ZERO, Vector3.ONE, 0.6)
				_add(r, box(Vector3(0.18, 0.08, 0.01)), Vector3(0.04, -0.02, 0.036), Y, Vector3.ZERO, Vector3.ONE, 0.6)
			_add(r, cyl(0.025, 0.01), Vector3(0, 0.31, 0.03), NAVY, Vector3(PI / 2, 0, 0))
		"onibus":
			_add(r, box(Vector3(1.0, 0.45, 0.42)), Vector3(0, 0.3, 0), Y)
			_add(r, box(Vector3(0.9, 0.16, 0.44)), Vector3(0.02, 0.4, 0), Color("#9fd3ff"), Vector3.ZERO, Vector3.ONE, 0.5)
			for x in [-0.32, 0.32]:
				_add(r, cyl(0.1, 0.46), Vector3(x, 0.08, 0), NAVY, Vector3(PI / 2, 0, 0))
			_add(r, box(Vector3(0.06, 0.06, 0.3)), Vector3(0.51, 0.18, 0), Color("#fff2b8"), Vector3.ZERO, Vector3.ONE, 1.5)
		"trofeu", "coroa":
			if kind == "trofeu":
				_add(r, box(Vector3(0.36, 0.1, 0.36)), Vector3(0, 0.05, 0), Color("#3b2a20"))
				_add(r, cyl(0.04, 0.22), Vector3(0, 0.2, 0), Y)
				_add(r, cyl(0.12, 0.3, 0.22), Vector3(0, 0.45, 0), Y)
				for x in [-0.24, 0.24]:
					_add(r, torus(0.05, 0.09), Vector3(x, 0.47, 0), Y, Vector3(0, 0, PI / 2))
			else:
				_add(r, cyl(0.26, 0.16, 0.26, 10), Vector3(0, 0.1, 0), Y)
				for i in 6:
					var a := TAU * i / 6.0
					_add(r, cyl(0.05, 0.16, 0.0, 4), Vector3(cos(a) * 0.23, 0.26, sin(a) * 0.23), Y)
				_add(r, ball(0.05), Vector3(0, 0.12, 0.27), Color("#e2384f"), Vector3.ZERO, Vector3.ONE, 0.4)
		"livro":
			_add(r, box(Vector3(0.5, 0.1, 0.66)), Vector3(0, 0.05, 0), Color("#8a3d4f"))
			_add(r, box(Vector3(0.46, 0.08, 0.63)), Vector3(0.02, 0.05, 0), PAPER)
			_add(r, box(Vector3(0.5, 0.1, 0.66)), Vector3(0.05, 0.16, 0.02), Color("#3d6a8a"), Vector3(0, 0.25, 0))
		"carta", "papel", "cartaz":
			var w := 0.6 if kind != "cartaz" else 0.7
			_add(r, box(Vector3(w, 0.02, w * 0.68)), Vector3(0, 0.01, 0), PAPER if kind != "carta" else Color("#f3dcc4"), Vector3(0, 0.15, 0))
			if kind == "carta":
				_add(r, ball(0.06), Vector3(0, 0.03, 0), Color("#e2384f"), Vector3.ZERO, Vector3(1, 0.3, 1))
			else:
				for i in 3:
					_add(r, box(Vector3(w * 0.7, 0.005, 0.02)), Vector3(0, 0.025, -0.08 + i * 0.08), NAVY, Vector3(0, 0.15, 0))
		"chocolate":
			_add(r, box(Vector3(0.6, 0.06, 0.3)), Vector3(0, 0.03, 0), Color("#5a3220"))
			_add(r, box(Vector3(0.36, 0.08, 0.32)), Vector3(0.14, 0.04, 0), Color("#e2384f"))
			_add(r, box(Vector3(0.1, 0.085, 0.33)), Vector3(0.14, 0.045, 0), Y)
		"carregador":
			_add(r, box(Vector3(0.22, 0.22, 0.14)), Vector3(0, 0.11, 0), Color("#e9e6dc"))
			for x in [-0.04, 0.04]:
				_add(r, box(Vector3(0.02, 0.1, 0.02)), Vector3(x, 0.27, 0), Color("#c8ccd8"))
			_add(r, torus(0.12, 0.15), Vector3(0.2, 0.03, 0.1), Color("#e9e6dc"), Vector3(PI / 2, 0, 0), Vector3(1.3, 1, 1))
		"baqueta":
			for x in [-0.05, 0.05]:
				_add(r, cyl(0.025, 0.9, 0.015), Vector3(x, 0.03, 0), Color("#c9a46b"), Vector3(PI / 2 - 0.05, 0.3, PI / 2))
			_add(r, box(Vector3(0.18, 0.01, 0.06)), Vector3(0.0, 0.07, 0.0), PAPER)
		"fita":
			_add(r, torus(0.11, 0.24), Vector3(0, 0.07, 0), Color("#b8bcc8"), Vector3.ZERO, Vector3(1, 1.6, 1))
		"computador":
			_add(r, box(Vector3(0.7, 0.45, 0.05)), Vector3(0, 0.42, 0), NAVY)
			_add(r, box(Vector3(0.62, 0.37, 0.01)), Vector3(0, 0.42, 0.03), Color("#6fd3ff"), Vector3.ZERO, Vector3.ONE, 1.0)
			_add(r, box(Vector3(0.1, 0.2, 0.06)), Vector3(0, 0.1, 0), NAVY)
			_add(r, box(Vector3(0.6, 0.03, 0.25)), Vector3(0, 0.015, 0.18), Color("#4a4a5a"))
		"pizza":
			_add(r, cyl(0.4, 0.04, 0.4, 16), Vector3(0, 0.02, 0), Color("#e0a050"))
			_add(r, cyl(0.36, 0.05, 0.36, 16), Vector3(0, 0.03, 0), Color("#d2483a"))
			for i in 6:
				var a := TAU * i / 6.0
				_add(r, cyl(0.05, 0.02), Vector3(cos(a) * 0.2, 0.06, sin(a) * 0.2), Color("#8a2a2a"))
		"chave":
			_add(r, torus(0.06, 0.12), Vector3(-0.2, 0.02, 0), Y, Vector3(PI / 2, 0, 0))
			_add(r, box(Vector3(0.36, 0.04, 0.05)), Vector3(0.04, 0.02, 0), Y)
			_add(r, box(Vector3(0.04, 0.04, 0.08)), Vector3(0.16, 0.02, 0.05), Y)
		"mochila", "sacola":
			var c := Color("#8a3a52") if kind == "mochila" else Color("#c9a43d")
			_add(r, box(Vector3(0.56, 0.7, 0.3)), Vector3(0, 0.36, 0), c)
			_add(r, cyl(0.28, 0.3, 0.28, 12), Vector3(0, 0.7, 0), c, Vector3(PI / 2, 0, 0), Vector3(1, 1, 0.6))
			_add(r, box(Vector3(0.4, 0.28, 0.08)), Vector3(0, 0.24, 0.17), c.darkened(0.2))
			_add(r, box(Vector3(0.3, 0.02, 0.02)), Vector3(0, 0.38, 0.215), Y)
			_add(r, torus(0.05, 0.08), Vector3(0, 0.86, 0), NAVY, Vector3(0, 0, 0))
		"camera":
			_add(r, box(Vector3(0.56, 0.36, 0.22)), Vector3(0, 0.18, 0), Color("#22263a"))
			_add(r, cyl(0.13, 0.16), Vector3(0, 0.18, 0.17), NAVY, Vector3(PI / 2, 0, 0))
			_add(r, cyl(0.09, 0.02), Vector3(0, 0.18, 0.26), Color("#6fd3ff"), Vector3(PI / 2, 0, 0), Vector3.ONE, 0.8)
			_add(r, box(Vector3(0.12, 0.06, 0.08)), Vector3(0.18, 0.39, 0), Y)
		"microfone":
			_add(r, cyl(0.04, 0.5, 0.06), Vector3(0, 0.25, 0), NAVY)
			_add(r, ball(0.11), Vector3(0, 0.56, 0), Color("#b8bcc8"))
		"bola":
			_add(r, ball(0.3, 16), Vector3(0, 0.3, 0), Color("#e07a3a"))
			_add(r, torus(0.29, 0.31), Vector3(0, 0.3, 0), Color("#3b2a20"))
			_add(r, torus(0.29, 0.31), Vector3(0, 0.3, 0), Color("#3b2a20"), Vector3(PI / 2, 0, 0))
		"prancheta":
			_add(r, box(Vector3(0.5, 0.03, 0.7)), Vector3(0, 0.015, 0), Color("#a07a4a"))
			_add(r, box(Vector3(0.42, 0.01, 0.58)), Vector3(0, 0.035, 0.03), PAPER)
			_add(r, box(Vector3(0.2, 0.05, 0.06)), Vector3(0, 0.045, -0.32), Color("#b8bcc8"))
		"wifi":
			for i in 3:
				var t := torus(0.1 + i * 0.12, 0.14 + i * 0.12)
				var mi := _add(r, t, Vector3(0, 0.05, 0), Y, Vector3(PI / 2, 0, 0), Vector3.ONE, 0.8)
				mi.scale = Vector3(1, 1, 0.4)
			_add(r, ball(0.06), Vector3(0, 0.0, 0), Y, Vector3.ZERO, Vector3.ONE, 0.8)
		"relogio":
			_add(r, cyl(0.32, 0.08, 0.32, 18), Vector3(0, 0.32, 0), PAPER, Vector3(PI / 2, 0, 0))
			_add(r, torus(0.3, 0.34), Vector3(0, 0.32, 0), NAVY, Vector3(PI / 2, 0, 0))
			_add(r, box(Vector3(0.03, 0.2, 0.02)), Vector3(0, 0.4, 0.05), NAVY)
			_add(r, box(Vector3(0.14, 0.03, 0.02)), Vector3(0.06, 0.32, 0.05), Color("#e2384f"))
		"cofre":
			# cofre de aço com disco de segredo, alavanca e porta entreaberta
			var steel := Color("#4a5470")
			_add(r, box(Vector3(0.62, 0.62, 0.52)), Vector3(0, 0.31, 0), steel)
			_add(r, box(Vector3(0.5, 0.5, 0.03)), Vector3(0, 0.31, 0.27), steel.lightened(0.15))
			_add(r, cyl(0.1, 0.04, 0.1, 18), Vector3(-0.06, 0.36, 0.3), Color("#c9ced9"), Vector3(PI / 2, 0, 0))
			_add(r, box(Vector3(0.015, 0.06, 0.02)), Vector3(-0.06, 0.42, 0.32), Color("#e2384f"))
			_add(r, box(Vector3(0.04, 0.18, 0.04)), Vector3(0.16, 0.3, 0.3), Y)
			_add(r, box(Vector3(0.66, 0.04, 0.56)), Vector3(0, 0.02, 0), steel.darkened(0.3))
			# maços de dinheiro caindo para fora
			_add(r, box(Vector3(0.18, 0.05, 0.09)), Vector3(0.36, 0.03, 0.3), Color("#7cc48a"), Vector3(0, 0.4, 0))
			_add(r, box(Vector3(0.18, 0.05, 0.09)), Vector3(0.42, 0.08, 0.22), Color("#8fd49c"), Vector3(0, -0.3, 0.1))
		"urna":
			_add(r, box(Vector3(0.56, 0.5, 0.44)), Vector3(0, 0.25, 0), Color("#e8e3d4"))
			_add(r, box(Vector3(0.58, 0.05, 0.46)), Vector3(0, 0.52, 0), Color("#2f4a8a"))
			_add(r, box(Vector3(0.26, 0.02, 0.05)), Vector3(0, 0.55, 0), Color("#0b0f1c"))
			_add(r, box(Vector3(0.2, 0.18, 0.01)), Vector3(0.02, 0.62, 0), PAPER, Vector3(0, 0, 0.12))
			_add(r, box(Vector3(0.3, 0.12, 0.01)), Vector3(0, 0.3, 0.225), Color("#2f4a8a"))
			_add(r, box(Vector3(0.08, 0.1, 0.02)), Vector3(0.22, 0.4, 0.23), Color("#e2384f"))
		"microscopio":
			var mc := Color("#d9dde6")
			_add(r, box(Vector3(0.4, 0.06, 0.32)), Vector3(0, 0.03, 0), NAVY)
			_add(r, box(Vector3(0.08, 0.5, 0.1)), Vector3(-0.1, 0.3, -0.06), mc, Vector3(0, 0, 0.12))
			_add(r, box(Vector3(0.26, 0.03, 0.22)), Vector3(0.04, 0.22, 0), NAVY)
			_add(r, cyl(0.05, 0.36, 0.04), Vector3(0.05, 0.48, 0), mc, Vector3(0, 0, -0.35))
			_add(r, cyl(0.03, 0.1), Vector3(-0.02, 0.69, 0), Color("#0b0f1c"), Vector3(0, 0, -0.35))
			_add(r, cyl(0.025, 0.08), Vector3(0.1, 0.3, 0), Y, Vector3(0, 0, -0.35))
		"spray":
			_add(r, cyl(0.12, 0.46), Vector3(0, 0.23, 0), Color("#e2384f"))
			_add(r, cyl(0.12, 0.08, 0.06), Vector3(0, 0.5, 0), Color("#c9ced9"))
			_add(r, box(Vector3(0.05, 0.05, 0.05)), Vector3(0, 0.57, 0.02), Color("#0b0f1c"))
			_add(r, box(Vector3(0.2, 0.1, 0.01)), Vector3(0, 0.26, 0.122), PAPER)
			# respingo de tinta no chão
			_add(r, cyl(0.2, 0.01, 0.2, 18), Vector3(0.18, 0.005, 0.14), Color("#e2384f"))
		"cadeado":
			_add(r, box(Vector3(0.36, 0.3, 0.14)), Vector3(0, 0.15, 0), Y.darkened(0.15))
			_add(r, torus(0.1, 0.14), Vector3(0, 0.32, 0), Color("#c9ced9"), Vector3(PI / 2, 0, 0))
			_add(r, cyl(0.03, 0.02), Vector3(0, 0.15, 0.075), Color("#0b0f1c"), Vector3(PI / 2, 0, 0))
			_add(r, box(Vector3(0.02, 0.06, 0.02)), Vector3(0, 0.11, 0.08), Color("#0b0f1c"))
		_:
			_add(r, box(Vector3(0.5, 0.36, 0.4)), Vector3(0, 0.18, 0), Color("#a07a4a"))
			_add(r, box(Vector3(0.52, 0.04, 0.12)), Vector3(0, 0.37, 0), Color("#c9a46b"))
			_add(r, box(Vector3(0.2, 0.12, 0.01)), Vector3(0, 0.2, 0.205), Y)
	return r


## Mesmas regras do caso: ícone explícito, senão adivinha pelo nome.
static func kind_for(card_or_item: Dictionary) -> String:
	var k := str(card_or_item.get("icon", ""))
	if k != "":
		return k
	var n := str(card_or_item.get("name", "")).to_lower()
	var guesses := {"viagem": "onibus", "troféu": "trofeu", "trofeu": "trofeu", "coroa": "coroa", "mensagem": "mensagem",
		"print": "mensagem", "grupo": "mensagem", "post": "celular", "celular": "celular", "livro": "livro",
		"carta": "carta", "bilhete": "papel", "aviso": "papel", "recado": "papel", "chocolate": "chocolate",
		"carregador": "carregador", "baqueta": "baqueta", "fita": "fita", "computador": "computador",
		"pizza": "pizza", "chave": "chave", "mochila": "mochila", "sacola": "sacola", "foto": "camera",
		"wifi": "wifi", "senha": "computador", "horário": "relogio", "hora": "relogio", "boato": "mensagem"}
	for key in guesses:
		if n.find(key) >= 0:
			return guesses[key]
	return "caixa"
