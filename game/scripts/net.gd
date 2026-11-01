extends Node
## Conexão com o servidor da sala (WebSocket) e o estado que ele manda.
## Tudo que a interface mostra vem daqui: as telas só leem `state`/`case_data` e
## reagem aos sinais. O servidor é a autoridade; o cliente só pede ações.

signal connected
signal disconnected
signal state_changed
signal case_loaded
signal event(evt: Dictionary)
signal error_msg(text: String)
signal joined
signal hosted
signal revealed
signal kicked
signal cases_listed(cases: Array)

const RECONNECT_SEC := 2.0

var ws := WebSocketPeer.new()
var url := ""
var is_open := false
var role := ""            # "" | "player" | "host"
var code := ""
var pid := ""
var secret := ""
var host_secret := ""
var my_name := ""

var state: Dictionary = {}
var case_data: Dictionary = {}
var reveal_data: Dictionary = {}
var clock_offset_ms := 0.0   # servidor - local, para o cronômetro bater em todos os celulares

var _want_open := false
var _retry_at := 0.0
var _queue: Array = []


func _ready() -> void:
	url = _default_url()
	var saved := _load_session()
	if not saved.is_empty():
		code = str(saved.get("code", ""))
		role = str(saved.get("role", ""))
		pid = str(saved.get("pid", ""))
		secret = str(saved.get("secret", ""))
		host_secret = str(saved.get("host_secret", ""))


func _default_url() -> String:
	# No navegador o servidor é o mesmo que entregou a página. No editor/PC, localhost.
	var env := OS.get_environment("RUMOR_URL")
	if env != "":
		return env
	if OS.has_feature("web"):
		var loc: String = str(JavaScriptBridge.eval("location.host", true))
		var proto: String = str(JavaScriptBridge.eval("location.protocol", true))
		return ("wss://" if proto == "https:" else "ws://") + loc + "/ws"
	return "ws://127.0.0.1:8080/ws"


func open() -> void:
	_want_open = true
	if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		ws = WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 20
		ws.connect_to_url(url)


func has_saved_session() -> bool:
	return code != "" and ((role == "player" and pid != "") or (role == "host" and host_secret != ""))


func forget_session() -> void:
	role = ""; code = ""; pid = ""; secret = ""; host_secret = ""
	state = {}; case_data = {}; reveal_data = {}
	_save_session()


func send(msg: Dictionary) -> void:
	if is_open:
		ws.send_text(JSON.stringify(msg))
	else:
		_queue.append(msg)
		open()


# ------------------------------------------------------------------ pedidos
func host_create() -> void:
	role = "host"
	send({"t": "host_create"})


func join(room_code: String, name: String) -> void:
	role = "player"
	send({"t": "join", "code": room_code, "name": name})


func board_op(op: Dictionary) -> void:
	send({"t": "board", "op": op})


func server_now_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + clock_offset_ms


func seconds_left() -> int:
	var ends := float(state.get("endsAt", 0))
	if ends <= 0.0:
		return 0
	return maxi(0, int(ceil((ends - server_now_ms()) / 1000.0)))


func my_team() -> Dictionary:
	var me: Dictionary = state.get("me", {})
	for t in state.get("teams", []):
		if t["id"] == me.get("team", ""):
			return t
	return {}


func card_by_id(id: String) -> Dictionary:
	for c in case_data.get("cards", []):
		if c["id"] == id:
			return c
	return {}


func clue_by_id(id: String) -> Dictionary:
	for c in state.get("clues", []):
		if c["id"] == id:
			return c
	return {}


func link_label(type_id: String) -> String:
	for lt in case_data.get("link_types", []):
		if lt["id"] == type_id:
			return str(lt["label"])
	return type_id


# ------------------------------------------------------------------ laço
func _process(_dt: float) -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not is_open:
			is_open = true
			_on_open()
		while ws.get_available_packet_count() > 0:
			var txt := ws.get_packet().get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(txt)
			if parsed is Dictionary:
				_on_message(parsed)
	elif st == WebSocketPeer.STATE_CLOSED:
		if is_open:
			is_open = false
			disconnected.emit()
			_retry_at = Time.get_ticks_msec() / 1000.0 + RECONNECT_SEC
		if _want_open and Time.get_ticks_msec() / 1000.0 >= _retry_at:
			_retry_at = Time.get_ticks_msec() / 1000.0 + RECONNECT_SEC
			ws = WebSocketPeer.new()
			ws.inbound_buffer_size = 1 << 20
			ws.connect_to_url(url)


func _on_open() -> void:
	connected.emit()
	# celular que apagou a tela volta para a mesma equipe sem perder nada
	if role == "player" and pid != "" and code != "":
		ws.send_text(JSON.stringify({"t": "resume", "code": code, "pid": pid, "secret": secret}))
	elif role == "host" and host_secret != "" and code != "":
		ws.send_text(JSON.stringify({"t": "host_resume", "code": code, "hostSecret": host_secret}))
	for m in _queue:
		ws.send_text(JSON.stringify(m))
	_queue.clear()
	ws.send_text(JSON.stringify({"t": "ping"}))


func _on_message(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"pong":
			clock_offset_ms = float(m["now"]) - Time.get_unix_time_from_system() * 1000.0
		"state":
			if m.has("now"):
				clock_offset_ms = lerpf(clock_offset_ms, float(m["now"]) - Time.get_unix_time_from_system() * 1000.0, 0.3)
			var prev_phase := str(state.get("phase", ""))
			state = m
			if str(m.get("phase", "")) == "lobby" and prev_phase != "lobby":
				reveal_data = {}
			state_changed.emit()
		"case":
			case_data = m["case"]
			case_loaded.emit()
		"evt":
			event.emit(m["evt"])
		"joined":
			code = str(m["code"]); pid = str(m["pid"]); secret = str(m["secret"]); my_name = str(m["name"])
			role = "player"
			_save_session()
			joined.emit()
		"hosted":
			code = str(m["code"]); host_secret = str(m["hostSecret"]); role = "host"
			_save_session()
			hosted.emit()
		"reveal":
			reveal_data = m["reveal"]
			revealed.emit()
		"resume_failed":
			forget_session()
			error_msg.emit("A sala anterior terminou. Entre de novo com o código.")
		"kicked":
			forget_session()
			kicked.emit()
		"cases":
			cases_listed.emit(m.get("cases", []))
		"error":
			error_msg.emit(str(m.get("msg", "Erro.")))


# ------------------------------------------------------------------ sessão salva
# No navegador usa localStorage (sobrevive a recarregar a página); no PC, user://.
func _save_session() -> void:
	var d := {"code": code, "role": role, "pid": pid, "secret": secret, "host_secret": host_secret}
	var txt := JSON.stringify(d)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('rumor_session', %s)}catch(e){}" % JSON.stringify(txt), true)
	elif OS.get_environment("RUMOR_NO_SAVE") == "":
		var f := FileAccess.open("user://session.json", FileAccess.WRITE)
		if f:
			f.store_string(txt)


func _load_session() -> Dictionary:
	var txt := ""
	if OS.has_feature("web"):
		var v: Variant = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('rumor_session')||''}catch(e){return ''}})()", true)
		txt = str(v) if v != null else ""
	elif OS.get_environment("RUMOR_NO_SAVE") == "" and FileAccess.file_exists("user://session.json"):
		txt = FileAccess.get_file_as_string("user://session.json")
	if txt == "":
		return {}
	var parsed: Variant = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}
