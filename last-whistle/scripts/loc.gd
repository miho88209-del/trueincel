extends Node
## Localisation: flat JSON string tables in res://i18n, chosen by Settings.v["language"].
## Text set through bind() follows language changes live.

signal changed

const LANGS := ["en", "es", "ru", "zh"]
const NAMES := {"en": "English", "es": "Español", "ru": "Русский", "zh": "中文"}

var lang := ""
var _tables := {}
var _bound: Array = []   # [WeakRef, key]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for l in LANGS:
		var f := FileAccess.open("res://i18n/%s.json" % l, FileAccess.READ)
		if f == null:
			continue
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_tables[l] = d
	_apply()
	Settings.changed.connect(_apply)

## Picks the OS language on first launch when a translation exists.
static func detect() -> String:
	var os_lang := OS.get_locale_language()
	return os_lang if os_lang in LANGS else "en"

func _apply() -> void:
	var l: String = Settings.v.get("language", "en")
	if not _tables.has(l):
		l = "en"
	if l == lang:
		return
	lang = l
	TranslationServer.set_locale(l)
	var keep: Array = []
	for b in _bound:
		var n = b[0].get_ref()
		if n != null:
			n.text = t(b[1])
			keep.append(b)
	_bound = keep
	changed.emit()

func has(key: String) -> bool:
	return _tables.get("en", {}).has(key)

func t(key: String) -> String:
	var tab: Dictionary = _tables.get(lang, {})
	if tab.has(key):
		return tab[key]
	return _tables.get("en", {}).get(key, key)

## Sets node.text now and whenever the language changes.
func bind(node: Object, key: String) -> void:
	node.text = t(key)
	_bound.append([weakref(node), key])
