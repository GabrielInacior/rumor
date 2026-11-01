extends Control
## Tela de vitória do aluno: resultado, tempo, estrelas e o culpado, com um botão para
## COMPARTILHAR a vitória como imagem (cartão retrato pintado em código).

signal closed

var solved := false
var time_sec := 0
var place := 0
var stars := 1
var case_title := ""
var culprit_id := ""
var codename := ""
var missed := false     # errou o culpado: nada da resposta aparece
var culprit_ok := false
var obj_line := ""
var categories: Array = []   # objetivos da equipe (status) para o cartão
var team_name := ""
var team_color := UI.YELLOW


func setup_from_reveal(r: Dictionary) -> void:
	var mine := str(Net.state.get("me", {}).get("team", ""))
	case_title = str(Net.case_data.get("title", ""))
	culprit_id = str(r.get("culprit", "")) if r.get("culprit") != null else ""
	codename = str(Net.state.get("me", {}).get("name", Net.my_name))
	missed = bool(r.get("hidden", false))
	var res: Dictionary = r.get("mine", {}) if r.get("mine") is Dictionary else {}
	culprit_ok = bool(res.get("culpritOk", false))
	if not res.is_empty():
		obj_line = "%d de %d provas" % [int(res.get("objDone", 0)), int(res.get("objTotal", 0))]
		categories = res.get("categories", [])
	for row in r.get("ranking", []):
		if row["id"] == mine:
			solved = row.get("solved", false)
			time_sec = int(row["timeSec"]) if row.get("timeSec") != null else 0
			place = int(row.get("place", 0))
			team_name = str(row.get("name", ""))
			team_color = Color(str(row.get("color", "#ffc83d")))
			# estrelas: tudo cumprido 3; culpado certo 2; senão 1
			stars = 3 if solved else (2 if row.get("culpritOk", false) else 1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	add_child(UI.full(dim))
	var m := UI.margin(30, 50, 30)
	add_child(UI.full(m))
	var v := UI.vbox(16)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(v)
	var vs := get_viewport_rect().size
	var ch := clampf(vs.y - 330.0, 600.0, 1180.0)
	var card := _make_card(Vector2(ch * 9.0 / 16.0, ch))
	var cc := CenterContainer.new()
	cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cc.add_child(card)
	v.add_child(cc)
	var share := UI.button("COMPARTILHAR", "primary", 104)
	share.add_theme_font_size_override("font_size", 46)
	share.pressed.connect(_share)
	v.add_child(share)
	var cont := UI.button("Ver a revelação completa", "ghost", 80)
	cont.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	v.add_child(cont)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.4)
	Sfx.play("victory" if solved else "correct")


## O cartão é o mesmo na tela e na imagem compartilhada (formato story 1080x1920, reduzido na tela).
func _make_card(sz: Vector2) -> Control:
	var k := sz.x / 1080.0
	var card := Panel.new()
	card.custom_minimum_size = sz
	card.clip_contents = true
	card.add_theme_stylebox_override("panel", UI.box(UI.NIGHT, team_color, int(10 * k), int(36 * k), 0))
	var bg := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/backdrop.gdshader")
	mat.set_shader_parameter("px_size", sz)
	mat.set_shader_parameter("rain_amount", 0.5)
	bg.material = mat
	bg.position = Vector2(12, 12) * k
	bg.size = sz - Vector2(24, 24) * k
	card.add_child(bg)
	var v := UI.vbox(int(14 * k))
	v.position = Vector2(54, 44) * k
	v.size = sz - Vector2(108, 88) * k
	card.add_child(v)
	# 1) cabeçalho: logo, caso, carimbo
	var logo := UI.title("RUMOR", int(130 * k), UI.YELLOW)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_color_override("font_shadow_color", Color(UI.PINK, 0.85))
	logo.add_theme_constant_override("shadow_offset_x", int(8 * k))
	logo.add_theme_constant_override("shadow_offset_y", int(5 * k))
	v.add_child(logo)
	var t := UI.label(case_title.to_upper(), int(44 * k), UI.PAPER, "type")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	var stamp := Stamp.new()
	stamp.text = "CASO RESOLVIDO" if solved else ("CULPADO CERTO" if culprit_ok else "CASO ENCERRADO")
	stamp.col = UI.GREEN if solved else (UI.YELLOW if culprit_ok else UI.PINK)
	stamp.k = k
	stamp.custom_minimum_size = Vector2(0, 136 * k)
	v.add_child(stamp)
	# 2) placar: estrelas, tempo, colocação
	var row := UI.hbox(int(24 * k))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var st := Stars.new()
	st.count = stars
	st.custom_minimum_size = Vector2(300 * k, 90 * k)
	row.add_child(st)
	var tv := UI.vbox(0)
	var tl := UI.title(("em " + UI.fmt_time(time_sec)) if time_sec > 0 else (obj_line if obj_line != "" else ""), int(64 * k), UI.YELLOW)
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	tv.add_child(tl)
	if place > 0 and not Net.state.get("solo", false):
		var pl := UI.label("%dº lugar · %s" % [place, team_name], int(32 * k), team_color, "bold")
		pl.autowrap_mode = TextServer.AUTOWRAP_OFF
		tv.add_child(pl)
	row.add_child(tv)
	v.add_child(row)
	# 3) a história que o quadro contou (os fios da equipe, em quadrinhos)
	var links: Array = Net.state.get("board", {}).get("links", [])
	if not links.is_empty():
		var hdr := UI.label("A HISTÓRIA QUE O NOSSO QUADRO CONTOU", int(30 * k), UI.YELLOW, "type")
		hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hdr)
		var ordered := links.duplicate()
		ordered.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
			var tx := str(Net.clue_by_id(str(x.get("evidence", ""))).get("time", "99h99")) if x.get("evidence") != null else "99h99"
			var ty := str(Net.clue_by_id(str(y.get("evidence", ""))).get("time", "99h99")) if y.get("evidence") != null else "99h99"
			return tx < ty)
		var n := 0
		for l in ordered:
			if n >= 4:
				break
			n += 1
			var strip := StoryStrip.new()
			strip.link = l
			strip.n = n
			strip.k = k
			strip.custom_minimum_size = Vector2(0, 176 * k)
			v.add_child(strip)
	# 4) objetivos
	if not categories.is_empty():
		var ob := PanelContainer.new()
		ob.add_theme_stylebox_override("panel", UI.box(Color(UI.NIGHT, 0.75), Color(UI.YELLOW, 0.4), int(2 * k), int(16 * k), int(16 * k)))
		var obv := UI.vbox(int(2 * k))
		var sorted_cats := categories.duplicate()
		sorted_cats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) == "culpado" and str(b.get("id", "")) != "culpado")
		for cat in sorted_cats:
			var ok := str(cat.get("status", "")) == "ok"
			var lab := ("PRINCIPAL  " if str(cat.get("id", "")) == "culpado" else "") + str(cat.get("label", ""))
			var l2 := UI.label(("✓  " if ok else "✗  ") + lab, int(26 * k), UI.GREEN if ok else Color(UI.MIST, 0.7), "bold")
			l2.autowrap_mode = TextServer.AUTOWRAP_OFF
			l2.clip_text = true
			obv.add_child(l2)
		ob.add_child(obv)
		v.add_child(ob)
	# 5) culpado (só para quem acertou: quem errou não recebe a resposta)
	if culprit_id != "":
		var cb := UI.hbox(int(20 * k))
		cb.alignment = BoxContainer.ALIGNMENT_CENTER
		var tex := UI.portrait(culprit_id)
		if tex:
			var pf := PanelContainer.new()
			pf.add_theme_stylebox_override("panel", UI.box(UI.PAPER, Color.TRANSPARENT, 0, int(4 * k), int(8 * k)))
			var tr := TextureRect.new()
			tr.texture = tex
			tr.custom_minimum_size = Vector2(120, 120) * k
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			pf.add_child(tr)
			pf.rotation = -0.05
			cb.add_child(pf)
		var cv := UI.vbox(0)
		cv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var cl := UI.label("O CULPADO ERA", int(28 * k), UI.MIST, "type")
		cl.autowrap_mode = TextServer.AUTOWRAP_OFF
		cv.add_child(cl)
		var cn := UI.title(str(Net.card_by_id(culprit_id).get("name", "?")).to_upper(), int(64 * k), UI.RED)
		cn.autowrap_mode = TextServer.AUTOWRAP_OFF
		cv.add_child(cn)
		cb.add_child(cv)
		v.add_child(cb)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	# 6) rodapé
	var foot := UI.label("Detetive %s%s  ·  Prof. Ailson\nrumor.inaciodev.online" % [UI.short_name(codename, 18), ("  ·  equipe " + team_name) if team_name != "" and not Net.state.get("solo", false) else ""], int(28 * k), UI.MIST, "bold")
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(foot)
	return card


func _share() -> void:
	# monta o cartão em alta resolução fora da tela, tira a "foto" e entrega para compartilhar
	var vp := SubViewport.new()
	vp.size = Vector2i(1080, 1920)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var card := _make_card(Vector2(1080, 1920))
	card.theme = UI.build_theme()
	vp.add_child(card)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	var png := img.save_png_to_buffer()
	if OS.has_feature("web"):
		var b64 := Marshalls.raw_to_base64(png)
		var js := """(async function(){try{
			const bin=atob('%s');const arr=new Uint8Array(bin.length);for(let i=0;i<bin.length;i++)arr[i]=bin.charCodeAt(i);
			const blob=new Blob([arr],{type:'image/png'});const file=new File([blob],'rumor_vitoria.png',{type:'image/png'});
			if(navigator.canShare&&navigator.canShare({files:[file]})){await navigator.share({files:[file],title:'RUMOR',text:'Resolvi o caso no RUMOR!'});}
			else{const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='rumor_vitoria.png';document.body.appendChild(a);a.click();a.remove();}
		}catch(e){console.log('share',e)}})()""" % b64
		JavaScriptBridge.eval(js, true)
	else:
		var path := OS.get_user_data_dir().path_join("rumor_vitoria.png")
		img.save_png(path)
		OS.shell_open(path)
	Sfx.play("submit_stamp")


class Stars extends Control:
	var count := 1

	func _draw() -> void:
		var r := size.y * 0.42
		var gap := r * 2.4
		var start := size.x / 2.0 - gap
		for i in 3:
			var c := Vector2(start + gap * i, size.y / 2.0)
			var pts := PackedVector2Array()
			for j in 10:
				var a := -PI / 2.0 + TAU * j / 10.0
				var rr := r if j % 2 == 0 else r * 0.45
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			draw_colored_polygon(pts, UI.YELLOW if i < count else Color(1, 1, 1, 0.15))
			pts.append(pts[0])
			draw_polyline(pts, UI.INK, 3.0)



## Carimbo grande e torto (CASO RESOLVIDO / CULPADO CERTO / CASO ENCERRADO).
class Stamp extends Control:
	var text := ""
	var col := UI.GREEN
	var k := 1.0

	func _draw() -> void:
		var f := UI.font("title")
		var fs := int(96 * k)
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_set_transform(size / 2.0, -0.07)
		var r := Rect2(Vector2(-tw / 2.0 - 30 * k, -fs * 0.62), Vector2(tw + 60 * k, fs * 1.2))
		draw_rect(r, Color(col, 0.12))
		draw_rect(r, col, false, 8 * k)
		draw_rect(r.grow(-12 * k), Color(col, 0.6), false, 3 * k)
		draw_string(f, Vector2(-tw / 2.0, fs * 0.34), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Uma cena da história do quadro: duas fotos ligadas pelo barbante, o verbo e a prova.
class StoryStrip extends Control:
	var link: Dictionary = {}
	var n := 1
	var k := 1.0
	var _frames := 0

	# as fotos carregam durante o desenho: redesenha nos primeiros quadros para todas aparecerem
	func _process(_dt: float) -> void:
		_frames += 1
		if _frames < 12:
			queue_redraw()

	var _cache := {}

	func _img(id: String) -> Texture2D:
		if _cache.has(id) and _cache[id] != null:
			return _cache[id]
		var t := _img_raw(id)
		_cache[id] = t
		return t

	func _img_raw(id: String) -> Texture2D:
		var c := Net.card_by_id(id)
		match str(c.get("kind", "")):
			"pessoa": return UI.portrait(id)
			"lugar": return Snap.get_tex("scene:" + str(c.get("scene", id)))
		return Snap.get_tex("item:" + ItemModels.kind_for(c))

	func _photo(rect: Rect2, id: String, tilt: float) -> void:
		draw_set_transform(rect.get_center(), tilt)
		var lr := Rect2(-rect.size / 2.0, rect.size)
		draw_rect(Rect2(lr.position + Vector2(6, 8) * k, lr.size), Color(0, 0, 0, 0.4))
		draw_rect(lr, Color("#fbfaf6"))
		var ph := Rect2(lr.position + Vector2(8, 8) * k, Vector2(lr.size.x - 16 * k, lr.size.y - 44 * k))
		draw_rect(ph, Color("#1b2650"))
		var tex := _img(id)
		if tex:
			draw_texture_rect(tex, ph, false)

		var nm := UI.strip_emoji(str(Net.card_by_id(id).get("name", id)))
		var fm := UI.font("marker")
		var fsz := int(24 * k)
		while fsz > int(12 * k) and fm.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x > lr.size.x - 12 * k:
			fsz -= 1
		draw_string(fm, Vector2(lr.position.x + 6 * k, lr.end.y - 10 * k), nm, HORIZONTAL_ALIGNMENT_CENTER, lr.size.x - 12 * k, fsz, UI.INK)
		draw_circle(Vector2(0, lr.position.y + 4 * k), 9 * k, UI.RED)
		draw_set_transform(Vector2.ZERO, 0.0)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# fundo de papel da cena
		draw_rect(Rect2(0, 0, w, h), Color(UI.PAPER, 0.08))
		draw_rect(Rect2(0, 0, w, h), Color(UI.PAPER, 0.25), false, 2 * k)
		var f := UI.font("title")
		draw_rect(Rect2(0, 0, 70 * k, 40 * k), UI.YELLOW)
		draw_string(f, Vector2(10 * k, 32 * k), "CENA %d" % n, HORIZONTAL_ALIGNMENT_LEFT, 60 * k, int(22 * k), UI.INK)
		var pw := 150.0 * k
		var a_r := Rect2(Vector2(80 * k, 14 * k), Vector2(pw, h - 28 * k))
		var b_r := Rect2(Vector2(w - pw - 200 * k, 14 * k), Vector2(pw, h - 28 * k))
		# barbante vermelho com o verbo
		var p1 := a_r.get_center() + Vector2(pw * 0.4, -h * 0.15)
		var p2 := b_r.get_center() + Vector2(-pw * 0.4, -h * 0.15)
		draw_line(p1, p2, UI.RED, 5 * k, true)
		var verb := Net.link_label(str(link.get("type", ""))).to_upper()
		var vw := f.get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * k)).x + 24 * k
		var vr := Rect2((p1 + p2) / 2.0 - Vector2(vw / 2.0, 22 * k), Vector2(vw, 44 * k))
		draw_rect(vr, UI.PAPER)
		draw_string(f, vr.position + Vector2(12 * k, 34 * k), verb, HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * k), UI.INK)
		_photo(a_r, str(link.get("a", "")), -0.05)
		_photo(b_r, str(link.get("b", "")), 0.05)
		# prova presa (miniatura do objeto + selo)
		var pr: Array = link.get("proofs", []) if link.get("proofs") is Array else ([link["evidence"]] if link.get("evidence") != null else [])
		var box := Rect2(Vector2(w - 180 * k, 22 * k), Vector2(170 * k, h - 44 * k))
		if pr.is_empty():
			draw_string(UI.font("type"), box.position + Vector2(10 * k, box.size.y / 2.0), "sem prova", HORIZONTAL_ALIGNMENT_LEFT, box.size.x, int(24 * k), Color(UI.MIST, 0.7))
		else:
			var clue := Net.clue_by_id(str(pr[0]))
			var tex: Texture2D = Snap.get_tex("item:" + ClueView.icon_kind(clue))
			draw_rect(box, Color("#3a5596"))
			if tex:
				draw_texture_rect(tex, Rect2(box.position + Vector2(10, 4) * k, Vector2(box.size.x - 20 * k, box.size.y - 50 * k)), false)
			var stamp_r := Rect2(box.position + Vector2(0, box.size.y - 42 * k), Vector2(box.size.x, 42 * k))
			draw_rect(stamp_r, UI.GREEN.darkened(0.3))
			var tag := "COM PROVA" if pr.size() == 1 else "%d PROVAS" % pr.size()
			draw_string(f, stamp_r.position + Vector2(10 * k, 32 * k), tag, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 20 * k, int(26 * k), UI.PAPER)
