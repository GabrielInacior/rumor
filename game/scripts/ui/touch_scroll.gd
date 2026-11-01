class_name TouchScroll
extends Node
## Rolagem por arrasto de dedo garantida para um ScrollContainer (tela do professor no celular).
## A lista do professor se refaz o tempo todo (ações dos alunos) e botões embaixo do dedo podem
## segurar o gesto: aqui o arrasto é lido antes da interface; passou do limiar, este nó assume
## o gesto (rola com inércia) e o toque não vira clique.

const THRESHOLD := 14.0

var sc: ScrollContainer
var _down := false
var _start := Vector2.ZERO
var _last := Vector2.ZERO
var _dragging := false
var _vel := 0.0
var _touch_id := -1


static func attach(scroll: ScrollContainer) -> TouchScroll:
	var t := TouchScroll.new()
	t.sc = scroll
	# o arrasto nativo fica desligado aqui (senão rolaria em dobro)
	scroll.scroll_deadzone = 100000
	scroll.add_child(t)
	return t


func busy() -> bool:
	return _down or absf(_vel) > 20.0


func _input(e: InputEvent) -> void:
	if sc == null or not sc.is_visible_in_tree():
		return
	# no _input os toques já chegam nas coordenadas da interface (não converter de novo)
	var to_canvas := Transform2D.IDENTITY
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		var p := to_canvas * t.position
		if t.pressed:
			if _touch_id == -1 and sc.get_global_rect().has_point(p):
				_touch_id = t.index
				_down = true
				_dragging = false
				_start = p
				_last = p
				_vel = 0.0
		elif t.index == _touch_id:
			_touch_id = -1
			_down = false
			_dragging = false
	elif e is InputEventScreenDrag and _down:
		var d := e as InputEventScreenDrag
		if d.index != _touch_id:
			return
		var p := to_canvas * d.position
		if not _dragging and absf(p.y - _start.y) > THRESHOLD:
			_dragging = true
		if _dragging:
			var dy := p.y - _last.y
			sc.scroll_vertical = int(sc.scroll_vertical - dy)
			_vel = -dy / maxf(get_process_delta_time(), 0.008)
		_last = p
	# nada é "engolido": a interface continua vendo o toque inteiro (soltar o dedo sempre chega),
	# e um botão não dispara depois de arrastar porque o dedo saiu de cima dele


func _process(dt: float) -> void:
	if _down or absf(_vel) < 20.0:
		return
	sc.scroll_vertical = int(sc.scroll_vertical + _vel * dt)
	_vel = lerpf(_vel, 0.0, clampf(dt * 4.0, 0.0, 1.0))
