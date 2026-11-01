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
	var card := _make_card(Vector2(640, 800))
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


## O cartão é o mesmo na tela e na imagem compartilhada (mesma montagem, tamanhos diferentes).
func _make_card(sz: Vector2) -> Control:
	var k := sz.x / 640.0
	var card := Panel.new()
	card.custom_minimum_size = sz
	var sb := UI.box(UI.NIGHT, team_color, int(6 * k), int(28 * k), 0)
	card.add_theme_stylebox_override("panel", sb)
	var bg := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/backdrop.gdshader")
	mat.set_shader_parameter("px_size", sz)
	mat.set_shader_parameter("rain_amount", 0.6)
	bg.material = mat
	bg.position = Vector2(8, 8) * k
	bg.size = sz - Vector2(16, 16) * k
	card.add_child(bg)
	var v := UI.vbox(int(6 * k))
	v.position = Vector2(30, 24) * k
	v.size = sz - Vector2(60, 48) * k
	card.add_child(v)
	var logo := UI.title("RUMOR", int(80 * k), UI.YELLOW)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_color_override("font_shadow_color", Color(UI.PINK, 0.8))
	logo.add_theme_constant_override("shadow_offset_x", int(5 * k))
	logo.add_theme_constant_override("shadow_offset_y", int(3 * k))
	v.add_child(logo)
	var htxt := "CASO RESOLVIDO!" if solved else ("CULPADO CERTO!" if culprit_ok else "CULPADO NÃO ENCONTRADO")
	var head := UI.title(htxt, int(56 * k), UI.GREEN if solved else (UI.YELLOW if culprit_ok else UI.PINK))
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var t := UI.label(case_title.to_upper(), int(30 * k), UI.PAPER, "type")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	# estrelas desenhadas
	var st := Stars.new()
	st.count = stars
	st.custom_minimum_size = Vector2(0, 70 * k)
	v.add_child(st)
	var tl := UI.title(("em " + UI.fmt_time(time_sec)) if solved and time_sec > 0 else (obj_line if obj_line != "" else "tempo esgotado"), int(48 * k), UI.YELLOW)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tl)
	if place > 0 and not Net.state.get("solo", false):
		var pl := UI.label("%dº lugar  ·  equipe %s" % [place, team_name], int(26 * k), team_color, "bold")
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(pl)
	if culprit_id != "":
		# culpado empilhado e centralizado (nada de texto lado a lado que possa cortar)
		var cbox := UI.vbox(int(4 * k))
		cbox.alignment = BoxContainer.ALIGNMENT_CENTER
		var tex := UI.portrait(culprit_id)
		if tex:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.custom_minimum_size = Vector2(0, 120 * k)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			cbox.add_child(tr)
		var cl := UI.label("O CULPADO ERA", int(24 * k), UI.MIST, "type")
		cl.autowrap_mode = TextServer.AUTOWRAP_OFF
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cbox.add_child(cl)
		var cn := UI.title(str(Net.card_by_id(culprit_id).get("name", "?")).to_upper(), int(48 * k), UI.RED)
		cn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cbox.add_child(cn)
		v.add_child(cbox)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var foot := UI.label("Detetive %s  ·  Prof. Ailson\nrumor.inaciodev.online" % codename, int(22 * k), UI.MIST, "bold")
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(foot)
	return card


func _share() -> void:
	# monta o cartão em alta resolução fora da tela, tira a "foto" e entrega para compartilhar
	var vp := SubViewport.new()
	vp.size = Vector2i(1080, 1350)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var card := _make_card(Vector2(1080, 1350))
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
