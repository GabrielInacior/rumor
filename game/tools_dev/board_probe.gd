extends Node
## Sonda de intuitividade do quadro: percorre as tarefas de um aluno iniciante e fotografa cada
## passo (o que ele vê, quais botões aparecem, que texto explica). Rodar em janela, mudo:
##   RUMOR_SHOT=<pasta> godot --audio-driver Dummy --path . --resolution 405x720 res://tools_dev/board_probe.tscn
var main: Node
var audit: Node
var dir := ""
var g: Node


func _shot(name: String) -> void:
	await get_tree().create_timer(0.7).timeout
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("PASSO ", name)


func _ready() -> void:
	dir = OS.get_environment("RUMOR_SHOT")
	audit = load("res://tools_dev/ui_audit.gd").new()
	var path := ProjectSettings.globalize_path("res://").path_join("../server/cases/cofre_formatura.json")
	audit.full_case = JSON.parse_string(FileAccess.get_file_as_string(path))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	audit.main = main
	await get_tree().create_timer(1.0).timeout
	var st: Dictionary = audit._player_state("playing")
	st["board"] = {"cards": [], "links": []}
	audit._apply("player", st)
	await get_tree().create_timer(1.0).timeout
	g = main.current
	g._set_tab("quadro")
	await _shot("p01_quadro_vazio")
	g._open_palette()
	await _shot("p02_fixar")
	g._close_sheet()
	# monta um quadro pequeno local (como se a equipe tivesse fixado)
	var cards := [{"ref": "p:lari", "x": 0.25, "y": 0.3}, {"ref": "p:caio", "x": 0.7, "y": 0.3}, {"ref": "p:bia", "x": 0.3, "y": 0.7},
		{"ref": "p:rafa", "x": 0.75, "y": 0.72}, {"ref": "p:sala_diretor", "x": 0.5, "y": 0.5}]
	_set_board(cards, [])
	await _shot("p03_quadro_com_cartas")
	g.board.selected_ref = "p:lari"
	g._update_action_bar()
	g.board.queue_redraw()
	await _shot("p04_pessoa_selecionada")
	g.board.link_from = "p:lari"
	g.board.selected_ref = ""
	g.link_banner.visible = true
	await _shot("p04b_modo_ligar_pessoa")
	g.board.link_from = "p:sala_diretor"
	await _shot("p04c_modo_ligar_lugar")
	g.board.link_from = ""
	g.link_banner.visible = false
	g._open_relation_picker("lari", "caio")
	await _shot("p05_ligar_pessoa_pessoa")
	g._close_sheet()
	g.board.selected_ref = "p:sala_diretor"
	g._update_action_bar()
	await _shot("p06_lugar_selecionado")
	g._open_involve("sala_diretor")
	await _shot("p07_envolver_pessoas")
	g._close_sheet()
	g._open_tag_picker("p:bia")
	await _shot("p08_marcar")
	g._close_sheet()
	cards[2]["tag"] = "inocente"
	cards[3]["tag"] = "mentiu"
	var cl: Array = audit.full_case["clues"]
	var links := [{"id": "l1", "a": "lari", "b": "sala_diretor", "type": "estava", "color": "vermelho", "proofs": [cl[0]["id"], cl[1]["id"]], "evidence": cl[0]["id"]},
		{"id": "l2", "a": "bia", "b": "lari", "type": "g_acobertou", "color": "azul", "proofs": [], "evidence": null},
		{"id": "l3", "a": "rafa", "b": "caio", "type": "g_mentiu", "color": "rosa", "proofs": [cl[2]["id"]], "evidence": cl[2]["id"]}]
	_set_board(cards, links)
	g.board.selected_ref = ""
	g._update_action_bar()
	g.board.fit()
	await _shot("p09_panorama_no_quadro")
	g._on_link_tapped("l1")
	await _shot("p10_fio_com_provas")
	g._close_sheet()
	g._open_story()
	await _shot("p11_historia")
	get_tree().quit()


func _set_board(cards: Array, links: Array) -> void:
	Net.state["board"] = {"cards": cards, "links": links}
	g.board.set_data(cards, links)
	g.board.queue_redraw()
