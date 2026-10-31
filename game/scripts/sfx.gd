extends Node
## Sons do jogo: efeitos sintetizados (tools/audio/gen_sfx.py) e a trilha de assets/audio/musica.
## Efeito que ainda não existe em disco é ignorado em silêncio, para o jogo nunca travar por áudio.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/musica/"
const POOL := 6

var _players: Array[AudioStreamPlayer] = []
var _cache := {}
var _music := AudioStreamPlayer.new()
var _ambience := AudioStreamPlayer.new()
var _tracks: Array[String] = []
var _track_i := 0
var muted := false


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music.volume_db = -14.0
	add_child(_music)
	_music.finished.connect(_next_track)
	_ambience.volume_db = -20.0
	add_child(_ambience)
	_tracks = _list_audio(MUSIC_DIR)
	_tracks.shuffle()


func _list_audio(dir_path: String) -> Array[String]:
	# Exportado, o arquivo vira "x.ogg.import"/".remap"; tira o sufixo pra carregar pelo nome original.
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		var name := f.trim_suffix(".import").trim_suffix(".remap")
		if (name.ends_with(".ogg") or name.ends_with(".mp3") or name.ends_with(".wav")) and not out.has(dir_path + name):
			out.append(dir_path + name)
	return out


func _stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := SFX_DIR + name + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_cache[name] = s
	return s


func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if muted:
		return
	var s := _stream(name)
	if s == null:
		return
	for p in _players:
		if not p.playing:
			p.stream = s
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return
	_players[0].stream = s
	_players[0].play()


func start_music() -> void:
	if _tracks.is_empty() or _music.playing:
		return
	_next_track()


func _next_track() -> void:
	# por decisão do autor, por enquanto toca só a trilha principal, em loop
	if muted:
		return
	var path := MUSIC_DIR + "bloodline.mp3"
	if not ResourceLoader.exists(path):
		if _tracks.is_empty():
			return
		path = _tracks[_track_i % _tracks.size()]
		_track_i += 1
	var s: AudioStream = load(path)
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	if s:
		_music.stream = s
		_music.play()


func set_ambience(name: String) -> void:
	var s := _stream(name)
	if s == null or muted:
		_ambience.stop()
		return
	if s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).get_length() * (s as AudioStreamWAV).mix_rate)
	if _ambience.stream != s:
		_ambience.stream = s
		_ambience.play()


func set_muted(m: bool) -> void:
	muted = m
	if m:
		_music.stop()
		_ambience.stop()
	else:
		start_music()
