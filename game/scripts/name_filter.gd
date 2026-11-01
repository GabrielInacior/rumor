class_name NameFilter
extends RefCounted
## Mesmo filtro do servidor (server/src/namefilter.js), só para avisar na hora no celular.
## Quem decide é o servidor; a lista é a mesma (assets/data/name_block.json).

static var _any: Array = []
static var _word := {}
const SURNAMES := ["pinto", "rola", "rolla"]
const LEET := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "9": "g", "@": "a", "$": "s", "!": "i", "|": "i"}


static func _load() -> void:
	if not _any.is_empty():
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/name_block.json"))
	if not (d is Dictionary):
		return
	for w in d.get("anywhere", []):
		var x := _squeeze(_base(str(w)))
		if not _any.has(x):
			_any.append(x)
	for w in d.get("word", []):
		_word[_squeeze(_base(str(w)))] = true


static func _base(s: String) -> String:
	var t := s.to_lower()
	var acc := {"á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a", "é": "e", "ê": "e", "è": "e", "í": "i", "ì": "i", "î": "i", "ó": "o", "ô": "o", "õ": "o", "ò": "o",
		"ú": "u", "ù": "u", "û": "u", "ü": "u", "ç": "c", "ñ": "n"}
	var out := ""
	for ch in t:
		out += str(acc.get(ch, LEET.get(ch, ch)))
	return out.replace("ph", "f").replace("k", "c").replace("y", "i").replace("w", "v")


static func _squeeze(s: String) -> String:
	var out := ""
	for ch in s:
		if out.is_empty() or out[out.length() - 1] != ch:
			out += ch
	return out


static func _letters_only(s: String) -> String:
	var out := ""
	for ch in s:
		if ch >= "a" and ch <= "z":
			out += ch
	return out


static func _stem(w: String) -> String:
	var re := RegEx.create_from_string("(s|zinh[oa]s?|inh[oa]s?|zao|ao|ona|udo|uda|ada|ado)$")
	return re.sub(w, "")


static func blocked(name: String) -> bool:
	_load()
	var b := _base(name)
	var words: Array = []
	var cur := ""
	for ch in b + " ":
		if ch >= "a" and ch <= "z":
			cur += ch
		elif cur != "":
			words.append(_squeeze(cur))
			cur = ""
	var joined := _squeeze(_letters_only(b))
	for w in _any:
		if joined.find(w) >= 0:
			return true
	if words.size() > 1 and words.any(func(w: String) -> bool: return SURNAMES.has(w)):
		var rest := words.filter(func(w: String) -> bool: return not SURNAMES.has(w))
		if not rest.is_empty() and rest.all(func(w: String) -> bool: return not _word.has(w) and not _word.has(_stem(w))):
			return false
	for w in words + [joined]:
		if _word.has(w):
			return true
		var st := _stem(w)
		if st.length() >= 2 and st != w and _word.has(st):
			return true
	return false


## "" se o nome serve; senão a mensagem para o aluno.
static func problem(raw: String) -> String:
	var name := raw.strip_edges()
	var letters := 0
	for ch in name:
		if ch.to_lower() != ch.to_upper():
			letters += 1
		elif not ch in [" ", "'", ".", "-"]:
			return "Use só letras no nome."
	if letters < 2:
		return "Digite pelo menos 2 letras."
	if blocked(name):
		return "Esse nome não pode. Use seu nome de verdade ou um codinome."
	return ""
