class_name GuideView
extends RefCounted
## Guia do caso para o professor: a verdade, o caminho da solução, onde está cada pista,
## o quadro oficial, pistas falsas, dúvidas comuns e perguntas para a revelação.
## Usa o "teacher_guide" escrito no caso; se faltar alguma parte, monta a partir da solução.

const SCENE_NAMES := {
	"corredor": "Corredor", "biblioteca": "Biblioteca", "teatro": "Teatro", "sala_aula": "Sala de aula",
	"cantina": "Cantina", "patio": "Pátio", "sala_professores": "Sala dos professores", "quadra": "Quadra",
	"sala_diretor": "Diretoria", "deposito": "Depósito", "laboratorio": "Laboratório", "sala_musica": "Sala de música",
}


static func build(g: Dictionary) -> Control:
	var v := UI.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if g.is_empty():
		v.add_child(UI.label("Carregando o guia do caso...", 26, UI.MIST, "type"))
		return v
	var tg: Dictionary = g.get("teacher_guide") if g.get("teacher_guide") is Dictionary else {}
	var sol: Dictionary = g.get("solution", {})
	var rv: Dictionary = g.get("reveal", {})
	var names := {}
	for c in g.get("cards", []):
		names[c["id"]] = UI.strip_emoji(str(c.get("name", c["id"])))
	var clue_titles := {}
	for c in g.get("clues", []):
		clue_titles[c["id"]] = UI.strip_emoji(str(c.get("title", c["id"])))
	var lt_labels := {}
	for lt in g.get("link_types", []):
		lt_labels[lt["id"]] = str(lt["label"])

	v.add_child(UI.title("GUIA DO CASO", 50, UI.YELLOW))
	v.add_child(UI.label(str(g.get("title", "")).to_upper() + "  ·  só o professor vê", 22, UI.MIST, "bold"))

	# 1. a verdade + culpado
	var truth := UI.vbox(10)
	if sol.get("culprit") != null:
		var row := UI.hbox(14)
		var tex := UI.portrait(str(sol["culprit"]))
		if tex:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.custom_minimum_size = Vector2(96, 120)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(tr)
		var cv := UI.vbox(2)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cv.add_child(UI.label(str(sol.get("culprit_question", "Culpado")), 20, UI.MIST))
		cv.add_child(UI.title(str(names.get(sol["culprit"], sol["culprit"])).to_upper(), 46, UI.RED))
		row.add_child(cv)
		truth.add_child(row)
	truth.add_child(_para(str(tg.get("summary", rv.get("explanation", "")))))
	v.add_child(_section("A VERDADE", truth, true))

	# objetivos e como a partida termina
	var ov := UI.vbox(8)
	if sol.get("culprit") != null:
		ov.add_child(UI.label("PRINCIPAL", 20, UI.PINK, "bold"))
		ov.add_child(_bullet("1", "%s  Resposta: %s." % [str(sol.get("culprit_question", "Quem é o culpado?")), str(names.get(sol["culprit"], sol["culprit"]))]))
	ov.add_child(UI.label("SECUNDÁRIOS (cada parte provada no quadro, com a pista certa presa no fio)", 20, UI.PINK, "bold"))
	var k := 0
	for cat in sol.get("categories", []):
		k += 1
		var n_edges := 0
		for e in sol.get("edges", []):
			if e.get("category", "") == cat["id"]:
				n_edges += 1
		ov.add_child(_bullet(str(k), "%s  (%d fio%s)" % [str(cat["label"]), n_edges, "" if n_edges == 1 else "s"]))
	ov.add_child(UI.label("COMO TERMINAR", 20, UI.PINK, "bold"))
	ov.add_child(_para("A equipe toca em ENTREGAR O CASO, aponta o culpado e todos votam. Um voto contra cancela e a equipe continua investigando. Depois de entregue, o quadro fecha e a equipe vê os próprios resultados enquanto espera as outras."))
	ov.add_child(_para("Placar: primeiro quem acertou o culpado; depois quem provou mais partes; no empate, quem entregou antes. Se o tempo acabar, vale o quadro que a equipe tiver. A revelação aparece quando todas entregam ou quando a partida for encerrada no botão ENCERRAR."))
	ov.add_child(_para("No modo solo, o aluno confirma a entrega sozinho."))
	v.add_child(_section("OBJETIVOS E COMO TERMINAR", ov, true))

	# 2. caminho da solução
	var steps: Array = tg.get("solution_steps", [])
	var sv := UI.vbox(8)
	if steps.is_empty():
		for st in rv.get("timeline", []):
			sv.add_child(_bullet(str(st.get("time", "")), UI.strip_emoji(str(st.get("text", "")))))
	else:
		var n := 0
		for st in steps:
			n += 1
			sv.add_child(_bullet(str(n), UI.strip_emoji(str(st))))
	v.add_child(_section("CAMINHO DA SOLUÇÃO" if not steps.is_empty() else "LINHA DO TEMPO DA VERDADE", sv, true))

	# plot twist: onde foi plantado (para o professor saber o que a turma vai "ler errado")
	if tg.get("twist") != null and str(tg.get("twist", "")) != "":
		var tw := UI.vbox(8)
		tw.add_child(_para(str(tg["twist"])))
		v.add_child(_section("O PLOT TWIST", tw, false))
	if tg.get("pacing") != null:
		var pv := UI.vbox(8)
		var pc: Variant = tg["pacing"]
		if pc is Array:
			for item in pc:
				if item is Dictionary:
					pv.add_child(_bullet(str(item.get("when", "·")), UI.strip_emoji(str(item.get("what", item.get("text", ""))))))
					if str(item.get("ask", "")) != "":
						pv.add_child(UI.label("Se travar, pergunte: " + UI.strip_emoji(str(item["ask"])), 20, UI.YELLOW))
				else:
					pv.add_child(_bullet("·", UI.strip_emoji(str(item))))
		else:
			pv.add_child(_para(str(pc)))
		v.add_child(_section("RITMO DA PARTIDA", pv, false))

	# 3. quadro oficial (ligações exigidas e provas aceitas)
	var bv := UI.vbox(8)
	for e in sol.get("edges", []):
		var ev := []
		for cid in e.get("evidence", []):
			ev.append(clue_titles.get(cid, cid))
		var line := "%s  %s  %s" % [names.get(e["from"], e["from"]), str(lt_labels.get(e["type"], e["type"])).to_upper(), names.get(e["to"], e["to"])]
		var box := UI.vbox(2)
		box.add_child(UI.label(line, 24, UI.PAPER, "bold"))
		if not ev.is_empty():
			box.add_child(UI.label("Prova aceita: " + ", ".join(ev), 20, UI.GREEN))
		bv.add_child(box)
	if not (sol.get("traps", []) as Array).is_empty():
		bv.add_child(UI.label("Ligações erradas que as equipes costumam fazer:", 20, UI.PINK, "bold"))
		for tr2 in sol.get("traps", []):
			bv.add_child(UI.label("·  %s  %s  %s" % [names.get(tr2["from"], tr2["from"]), str(lt_labels.get(tr2["type"], tr2["type"])), names.get(tr2["to"], tr2["to"])], 20, UI.PINK))
	v.add_child(_section("QUADRO OFICIAL", bv, false))

	# 4. onde está cada pista
	var cm := UI.vbox(10)
	var cmap: Array = tg.get("clue_map", [])
	if cmap.is_empty():
		cmap = _derive_clue_map(g)
	for item in cmap:
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", UI.box(Color(UI.NIGHT, 0.7), Color(UI.SKY, 0.4), 1, 12, 14))
		var bb := UI.vbox(2)
		bb.add_child(UI.label(str(clue_titles.get(item.get("clue", ""), item.get("clue", ""))), 23, UI.YELLOW, "bold"))
		bb.add_child(UI.label("Onde: " + UI.strip_emoji(str(item.get("where", ""))), 20, UI.PAPER))
		if str(item.get("proves", "")) != "":
			bb.add_child(UI.label("Prova: " + UI.strip_emoji(str(item.get("proves", ""))), 20, UI.MIST))
		box.add_child(bb)
		cm.add_child(box)
	v.add_child(_section("ONDE ESTÁ CADA PISTA", cm, false))

	# 5. pistas falsas
	var rh: Array = tg.get("red_herrings", rv.get("refuted", []))
	if not rh.is_empty():
		var rv2 := UI.vbox(8)
		for r in rh:
			rv2.add_child(_bullet("·", UI.strip_emoji(str(r))))
		v.add_child(_section("PISTAS FALSAS", rv2, false))

	# 6. dúvidas comuns
	var faq: Array = tg.get("faq", [])
	var fv := UI.vbox(10)
	for f in faq:
		fv.add_child(UI.label("P: " + UI.strip_emoji(str(f.get("q", ""))), 22, UI.YELLOW, "bold"))
		fv.add_child(UI.label("R: " + UI.strip_emoji(str(f.get("a", ""))), 21, UI.PAPER))
	var hints: Array = g.get("hints", [])
	if not hints.is_empty():
		fv.add_child(UI.label("Dicas prontas (da mais sutil à mais forte):", 20, UI.MIST, "bold"))
		var n2 := 0
		for h in hints:
			n2 += 1
			fv.add_child(_bullet(str(n2), UI.strip_emoji(str(h))))
	v.add_child(_section("DÚVIDAS COMUNS E DICAS", fv, false))

	# 7. para conversar na revelação
	var tp: Array = tg.get("talking_points", [])
	if not tp.is_empty():
		var tv := UI.vbox(8)
		for t in tp:
			tv.add_child(_bullet("?", UI.strip_emoji(str(t))))
		v.add_child(_section("PARA CONVERSAR NA REVELAÇÃO", tv, false))
	_inkify(v)
	return _folder(v, str(g.get("title", "")))


const DOC_INK := Color("#1b2140")
const DOC_RED := Color("#c42c3f")
const MANILA := Color("#d9b977")
const MANILA_EDGE := Color("#b8944f")
const SHEET := Color("#f4efe2")


## Cores de tela escura viram cores de tinta sobre papel (o dossiê do diretor).
static func _inkify(n: Node) -> void:
	for c in n.get_children():
		if c is Label:
			var l := c as Label
			var col: Color = l.get_theme_color("font_color")
			var out := DOC_INK
			if col.is_equal_approx(UI.MIST):
				out = Color(DOC_INK, 0.65)
			elif col.is_equal_approx(UI.YELLOW) or col.is_equal_approx(UI.RED) or col.is_equal_approx(UI.PINK):
				out = DOC_RED
			elif col.is_equal_approx(UI.GREEN):
				out = Color("#2f6b3a")
			l.add_theme_color_override("font_color", out)
		_inkify(c)


## Pasta parda com etiqueta, carimbo e a folha do guia dentro.
static func _folder(content: Control, title: String) -> Control:
	var outer := PanelContainer.new()
	# no PC o dossiê vira uma coluna de leitura (linha de 1800 px cansa); no celular ocupa tudo
	outer.custom_minimum_size.x = 0
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_stylebox_override("panel", UI.box(MANILA, MANILA_EDGE, 2, 8, 14))
	var v := UI.vbox(10)
	var h := UI.hbox(10)
	var lab := UI.label("ARQUIVO DA DIRETORIA  ·  " + title.to_upper(), 18, Color(DOC_INK, 0.75), "type")
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.autowrap_mode = TextServer.AUTOWRAP_OFF
	lab.clip_text = true
	h.add_child(lab)
	var stamp := PanelContainer.new()
	stamp.add_theme_stylebox_override("panel", UI.box(Color.TRANSPARENT, DOC_RED, 3, 4, 6))
	var st := UI.title("CONFIDENCIAL", 26, DOC_RED)
	st.autowrap_mode = TextServer.AUTOWRAP_OFF
	stamp.add_child(st)
	stamp.rotation = -0.06
	h.add_child(stamp)
	v.add_child(h)
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", UI.box(SHEET, Color("#c9bfa5"), 1, 4, 20))
	sheet.add_child(content)
	v.add_child(sheet)
	outer.add_child(v)
	return outer


static func _derive_clue_map(g: Dictionary) -> Array:
	var out := []
	var by_hs := {}
	for h in g.get("hotspots", []):
		if h.get("clue"):
			by_hs[h["clue"]] = h
	var by_talk := {}
	for c in g.get("cards", []):
		var nodes: Dictionary = c.get("talk", {}).get("tree", {}).get("nodes", {})
		for nid in nodes:
			var u := str(nodes[nid].get("unlock", ""))
			if u != "":
				by_talk[u] = UI.strip_emoji(str(c.get("name", "")))
	var proves := {}
	var names := {}
	for c in g.get("cards", []):
		names[c["id"]] = UI.strip_emoji(str(c.get("name", c["id"])))
	for e in g.get("solution", {}).get("edges", []):
		for cid in e.get("evidence", []):
			proves[cid] = "%s → %s" % [names.get(e["from"], e["from"]), names.get(e["to"], e["to"])]
	for c in g.get("clues", []):
		var cid: String = c["id"]
		var where := ""
		var rel := str(c.get("release", "start"))
		if by_hs.has(cid):
			var h: Dictionary = by_hs[cid]
			where = "%s, no objeto \"%s\"" % [SCENE_NAMES.get(str(h.get("scene", "")), str(h.get("scene", ""))), str(h.get("label", ""))]
		elif rel == "interrogatorio" or by_talk.has(cid):
			where = "interrogando %s (mostrando a pista certa)" % by_talk.get(cid, "um personagem")
		elif rel.begins_with("t+"):
			where = "chega sozinha aos %d min de jogo" % int(int(rel.substr(2)) / 60.0)
		else:
			where = "desde o início"
		if str(c.get("deal", "team")) == "split":
			where += " · só UM aluno da equipe recebe"
		out.append({"clue": cid, "where": where, "proves": proves.get(cid, "")})
	return out


static func _section(title: String, content: Control, open: bool) -> Control:
	var wrap := UI.vbox(8)
	var head := UI.button(("▼  " if false else "") + title, "ghost", 70)
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_theme_font_override("font", UI.font("title"))
	head.add_theme_font_size_override("font_size", 30)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		head.add_theme_color_override(k, Color("#1b2140"))
	head.add_theme_stylebox_override("normal", UI.box(Color("#e6d3a3"), Color("#b8944f"), 2, 6, 14))
	head.add_theme_stylebox_override("hover", UI.box(Color("#d9b977"), Color("#b8944f"), 2, 6, 14))
	head.add_theme_stylebox_override("pressed", UI.box(Color("#c7a25e"), Color("#b8944f"), 2, 6, 14))
	var body := PanelContainer.new()
	body.add_theme_stylebox_override("panel", UI.box(Color("#fbf8f0"), Color("#d8ccb0"), 1, 4, 18))
	body.add_child(content)
	body.visible = open
	head.text = ("—  " if false else "") + title + ("   (fechar)" if open else "   (abrir)")
	head.pressed.connect(func() -> void:
		body.visible = not body.visible
		head.text = title + ("   (fechar)" if body.visible else "   (abrir)"))
	wrap.add_child(head)
	wrap.add_child(body)
	return wrap


static func _para(t: String) -> Control:
	return UI.label(UI.strip_emoji(t), 24, UI.PAPER)


static func _bullet(num: String, text: String) -> Control:
	var h := UI.hbox(12)
	var n := UI.title(num, 30, UI.YELLOW)
	n.custom_minimum_size.x = 50
	n.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(n)
	var l := UI.label(text, 22, UI.PAPER)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h
