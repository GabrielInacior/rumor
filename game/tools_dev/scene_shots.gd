extends Node
## Sonda de desenvolvimento: monta cada cena 3D do caso, espera ela assentar e salva um PNG 720x1280.
## No fim junta tudo numa folha de contato. Rodar em janela com --audio-driver Dummy e timeout externo.

const CaseScene := preload("res://scripts/scene3d/case_scene.gd")
const OUT := "C:/Users/gabri/AppData/Local/Temp/claude/C--Project-detetive/087135be-14c9-4d43-8227-07aba97a3b78/scratchpad/scenes/"
const SHEET := "C:/Project/detetive/docs/arte_exploracao/cenas_folha.png"
const ANCHORS := {
	"corredor": ["quadro_avisos", "mural", "celular", "armario_aberto", "lixeira"],
	"biblioteca": ["caderno_entrada", "pasta_gremio", "computador", "estante", "mesa_estudo"],
	"teatro": ["caixa_props", "quadro_teatro", "trono", "arara_figurino", "cortina"],
	"sala_aula": ["lousa", "mesa_professor", "carteira_fundo", "mochila", "janela"],
	"cantina": ["balcao", "cardapio", "bandeja", "geladeira", "mural_cantina"],
	"patio": ["banco_patio", "arvore", "bicicletario", "lixeira_patio", "poste"],
	"sala_professores": ["escaninho", "cafeteira", "mural_recados", "computador_prof", "armario_prof"],
	"quadra": ["arquibancada", "placar", "bolsa_esportiva", "vestiario_porta", "rede"],
	"sala_diretor": ["mesa_diretor", "gaveta", "quadro_fotos", "telefone", "cofre"],
	"deposito": ["caixa_achados", "prateleira", "vassoura", "caixa_fusiveis", "porta_fundos"],
	"laboratorio": ["bancada", "microscopio", "armario_vidros", "quadro_tabela", "pia"],
	"sala_musica": ["piano", "bateria", "estante_partituras", "armario_instrumentos", "quadro_horarios"],
	"fachada": [],
}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var only := OS.get_environment("SHOT_ONLY")
	var shots: Array[Image] = []
	for id in ANCHORS.keys():
		if only != "" and not (id in only.split(",")):
			continue
		var cs: SubViewportContainer = CaseScene.new()
		var hs := []
		var anchors: Array = ANCHORS[id]
		# duas pistas acesas para ver o brilho; o resto fica como objeto normal
		for i in mini(2, anchors.size()):
			hs.append({"id": "h%d" % i, "object": anchors[i], "label": anchors[i]})
		var ppl := []
		if id != "fachada":
			ppl = [{"id": "a", "look": {"top": "#c84a5e", "hair_color": "#2a1a14"}},
				{"id": "b", "look": {"top": "#4e8a6a", "hair_color": "#e0b040", "skin": "#8a5a3e"}},
				{"id": "c", "look": {"top": "#6a5aa8", "hair_color": "#1c1830"}}]
		cs.setup(id, hs, {}, ppl)
		cs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(cs)
		if id == "fachada":
			cs.set_showcase(true)
		for f in 30:
			await get_tree().process_frame
		var img: Image = cs.vp.get_texture().get_image()
		img.save_png(OUT + id + OS.get_environment("SHOT_SUFFIX") + ".png")
		shots.append(img)
		# auditoria: âncoras faltando, malhas e luzes
		var missing := []
		for a in anchors:
			if not cs._anchors.has(a) or not cs._anchors[a].has("mesh"):
				missing.append(a)
		# enquadramento: âncora (ou pessoa) cujo centro cai fora da tela do celular em pé
		var off := []
		var vs: Vector2 = cs.vp.size
		for a in cs._anchors:
			var mi = cs._anchors[a].get("mesh")
			if mi is Node3D:
				var sp: Vector2 = cs.cam.unproject_position((mi as Node3D).global_position)
				if sp.x < 0 or sp.y < 0 or sp.x > vs.x or sp.y > vs.y or cs.cam.is_position_behind((mi as Node3D).global_position):
					off.append("%s(%d,%d)" % [a, sp.x, sp.y])
		for i in mini(ppl.size(), cs.PEOPLE_SPOTS[id].size()):
			var hp: Vector3 = cs.PEOPLE_SPOTS[id][i] + Vector3(0, 1.0, 0)
			var sp2: Vector2 = cs.cam.unproject_position(hp)
			if sp2.x < 0 or sp2.y < 0 or sp2.x > vs.x or sp2.y > vs.y:
				off.append("pessoa%d(%d,%d)" % [i, sp2.x, sp2.y])
		print("FRAME %s fora=%s" % [id, off])
		var counts := _count(cs.world)
		print("SHOT %s size=%s meshes=%d char_meshes=%d omni_spot=%d dir=%d flavors=%d missing=%s" % [id, img.get_size(), counts[0], counts[3], counts[1], counts[2], _flavors(cs), missing])
		cs.queue_free()
		await get_tree().process_frame
	if only == "" and OS.get_environment("SHOT_SUFFIX") == "":
		_sheet(shots)
	get_tree().quit()


func _flavors(cs) -> int:
	var n := 0
	for k in cs._targets:
		if cs._targets[k]["kind"] == "flavor":
			n += 1
	return n


## [malhas visíveis do cenário, luzes omni/spot, direcionais, malhas visíveis de personagens]
func _count(n: Node, in_char := false) -> Array:
	var m := 0
	var l := 0
	var d := 0
	var ch := 0
	for c in n.get_children():
		var is_char := in_char or (c.get_script() != null and (c.get_script() as Script).resource_path.ends_with("character.gd"))
		if c is GeometryInstance3D and (c as Node3D).is_visible_in_tree() and (c is MeshInstance3D or c is MultiMeshInstance3D):
			if is_char:
				ch += 1
			else:
				m += 1
		elif c is DirectionalLight3D:
			d += 1
		elif c is Light3D and (c as Light3D).visible:
			l += 1
		var sub := _count(c, is_char)
		m += sub[0]; l += sub[1]; d += sub[2]; ch += sub[3]
	return [m, l, d, ch]


func _sheet(shots: Array[Image]) -> void:
	# grade 5 colunas de miniaturas 288x512
	var w := 288
	var h := 512
	var cols := 5
	var rows := int(ceil(shots.size() / float(cols)))
	var sheet := Image.create(w * cols + 8 * (cols + 1), h * rows + 8 * (rows + 1), false, Image.FORMAT_RGB8)
	sheet.fill(Color("#05070f"))
	for i in shots.size():
		var im: Image = shots[i].duplicate()
		im.convert(Image.FORMAT_RGB8)
		im.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(8 + (i % cols) * (w + 8), 8 + (i / cols) * (h + 8)))
	sheet.save_png(SHEET)
	print("SHEET saved")
