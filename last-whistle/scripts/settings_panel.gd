class_name SettingsPanel
extends Control
## Paper-styled settings sheet: graphics presets and options, display, audio, controls.

signal closed

const INK := Color(0.12, 0.11, 0.1)
const PAPER := Color(0.85, 0.83, 0.77)

var _rows: VBoxContainer
var _widgets := {}
var _building := false

static func paper_style(col := PAPER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(6, 8)
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	sb.content_margin_top = 30
	sb.content_margin_bottom = 30
	return sb

static func paper_theme() -> Theme:
	Props.fonts()
	var th := Theme.new()
	th.default_font = Props.font_hand
	th.default_font_size = 34
	for t in ["Label", "Button", "OptionButton", "CheckBox", "PopupMenu"]:
		th.set_color("font_color", t, INK)
	th.set_color("font_hover_color", "Button", Color(0.45, 0.12, 0.08))
	th.set_color("font_pressed_color", "Button", Color(0.45, 0.12, 0.08))
	th.set_color("font_focus_color", "Button", Color(0.45, 0.12, 0.08))
	th.set_color("font_hover_color", "OptionButton", Color(0.45, 0.12, 0.08))
	th.set_color("font_hover_color", "CheckBox", Color(0.45, 0.12, 0.08))
	th.set_color("font_pressed_color", "CheckBox", INK)
	th.set_color("font_hover_pressed_color", "CheckBox", Color(0.45, 0.12, 0.08))
	th.set_color("font_focus_color", "CheckBox", INK)
	th.set_color("font_hover_color", "PopupMenu", Color(0.45, 0.12, 0.08))
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0)
	flat.border_color = Color(INK, 0.6)
	flat.border_width_bottom = 2
	flat.content_margin_left = 10
	flat.content_margin_right = 10
	var hover := flat.duplicate()
	hover.bg_color = Color(0, 0, 0, 0.06)
	var empty := StyleBoxEmpty.new()
	for t in ["Button", "OptionButton"]:
		th.set_stylebox("normal", t, flat)
		th.set_stylebox("hover", t, hover)
		th.set_stylebox("pressed", t, hover)
		th.set_stylebox("focus", t, empty)
	for t in ["CheckBox"]:
		th.set_stylebox("normal", t, empty)
		th.set_stylebox("hover", t, empty)
		th.set_stylebox("pressed", t, empty)
		th.set_stylebox("focus", t, empty)
		th.set_stylebox("hover_pressed", t, empty)
	var pop := StyleBoxFlat.new()
	pop.bg_color = Color(0.9, 0.88, 0.82)
	pop.border_color = INK
	pop.border_width_bottom = 1; pop.border_width_top = 1; pop.border_width_left = 1; pop.border_width_right = 1
	pop.content_margin_left = 8; pop.content_margin_right = 8; pop.content_margin_top = 6; pop.content_margin_bottom = 6
	th.set_stylebox("panel", "PopupMenu", pop)
	var phover := StyleBoxFlat.new()
	phover.bg_color = Color(0, 0, 0, 0.1)
	th.set_stylebox("hover", "PopupMenu", phover)
	th.set_font_size("font_size", "PopupMenu", 30)
	var line := StyleBoxFlat.new()
	line.bg_color = Color(INK, 0.55)
	line.content_margin_top = 2
	line.content_margin_bottom = 2
	th.set_stylebox("slider", "HSlider", line)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.45, 0.12, 0.08)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var grab := _circle_tex(22, INK)
	th.set_icon("grabber", "HSlider", grab)
	th.set_icon("grabber_highlight", "HSlider", _circle_tex(24, Color(0.45, 0.12, 0.08)))
	th.set_icon("checked", "CheckBox", _box_tex(26, true))
	th.set_icon("unchecked", "CheckBox", _box_tex(26, false))
	th.set_stylebox("panel", "PanelContainer", paper_style())
	var sbar := StyleBoxFlat.new()
	sbar.bg_color = Color(INK, 0.12)
	th.set_stylebox("scroll", "VScrollBar", sbar)
	var sgrab := StyleBoxFlat.new()
	sgrab.bg_color = Color(INK, 0.5)
	th.set_stylebox("grabber", "VScrollBar", sgrab)
	th.set_stylebox("grabber_highlight", "VScrollBar", sgrab)
	return th

static func _circle_tex(size: int, col: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			img.set_pixel(x, y, Color(col, clampf(size * 0.42 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

static func _box_tex(size: int, checked: bool) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var edge := x < 2 or y < 2 or x >= size - 2 or y >= size - 2
			var a := 0.0
			if edge:
				a = 0.85
			elif checked and (absi(x - y) < 2 or absi(x - (size - 1 - y)) < 2) and x > 4 and x < size - 5:
				a = 1.0
			img.set_pixel(x, y, Color(INK, a))
	return ImageTexture.create_from_image(img)

func _ready() -> void:
	theme = paper_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 900)
	panel.rotation_degrees = -0.6
	panel.pivot_offset = Vector2(490, 450)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var title := Label.new()
	title.text = "settings"
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(880, 690)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)
	_build()
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 60)
	v.add_child(bottom)
	var reset := Button.new()
	reset.text = "reset to defaults"
	reset.pressed.connect(func() -> void:
		Sfx.play("ui_click", -4.0)
		Settings.reset_defaults()
		_refresh())
	bottom.add_child(reset)
	var back := Button.new()
	back.text = "back"
	back.add_theme_font_size_override("font_size", 44)
	back.pressed.connect(close)
	bottom.add_child(back)

func close() -> void:
	Sfx.play("ui_click", -4.0)
	Settings.save_settings()
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()

func _section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 42)
	l.add_theme_color_override("font_color", Color(0.45, 0.12, 0.08))
	_rows.add_child(l)

func _row(text: String, w: Control) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(380, 0)
	h.add_child(l)
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w.custom_minimum_size = Vector2(0, 46)
	h.add_child(w)
	_rows.add_child(h)

func _option(key: String, label: String, items: Array, to_value: Callable = Callable(), from_value: Callable = Callable()) -> void:
	var ob := OptionButton.new()
	for it in items:
		ob.add_item(str(it))
	ob.item_selected.connect(func(i: int) -> void:
		if _building:
			return
		Sfx.play("ui_click", -6.0)
		Settings.set_val(key, to_value.call(i) if to_value.is_valid() else i)
		_refresh())
	_widgets[key] = [ob, from_value]
	_row(label, ob)

func _slider(key: String, label: String, mn: float, mx: float, step: float) -> void:
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := Label.new()
	val.custom_minimum_size = Vector2(90, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(s)
	h.add_child(val)
	s.value_changed.connect(func(x: float) -> void:
		val.text = _fmt(key, x)
		if _building:
			return
		Settings.set_val(key, x)
		_refresh_quality_only())
	_widgets[key] = [s, val]
	_row(label, h)

func _check(key: String, label: String) -> void:
	var c := CheckBox.new()
	c.text = ""
	c.toggled.connect(func(on: bool) -> void:
		if _building:
			return
		Sfx.play("ui_click", -6.0)
		Settings.set_val(key, on)
		_refresh_quality_only())
	_widgets[key] = [c]
	_row(label, c)

func _fmt(key: String, x: float) -> String:
	if key in ["master", "music", "sfx", "ambience", "grass", "render_scale"]:
		return "%d%%" % roundi(x * 100.0)
	if key == "fov":
		return "%d°" % roundi(x)
	return "%.2f" % x

func _build() -> void:
	_section("graphics")
	_option("quality", "quality preset", Settings.QUALITY_NAMES.slice(0, 4),
		func(i: int): return Settings.QUALITY_NAMES[i],
		func(val) -> int: return Settings.QUALITY_NAMES.find(val))
	_option("shadows", "shadows", Settings.SHADOW_NAMES)
	_check("post_fx", "post-processing (bloom, grading)")
	_check("ssao", "ambient occlusion")
	_check("volumetric", "volumetric fog & light")
	_option("aa", "anti-aliasing", Settings.AA_NAMES)
	_option("view", "view distance", Settings.VIEW_NAMES)
	_slider("grass", "grass density", 0.0, 1.0, 0.05)
	_slider("render_scale", "render scale", 0.5, 1.0, 0.05)
	_section("display")
	_option("window_mode", "display mode", Settings.MODE_NAMES)
	var res := []
	for r in Settings.RESOLUTIONS:
		res.append("%d × %d" % [r.x, r.y])
	_option("resolution", "window resolution", res)
	_check("vsync", "vertical sync")
	_section("audio")
	_slider("master", "master volume", 0.0, 1.0, 0.05)
	_slider("music", "music", 0.0, 1.0, 0.05)
	_slider("sfx", "effects", 0.0, 1.0, 0.05)
	_slider("ambience", "ambience", 0.0, 1.0, 0.05)
	_section("controls")
	_slider("sensitivity", "mouse sensitivity", 0.05, 0.6, 0.01)
	_slider("fov", "field of view", 60.0, 100.0, 1.0)
	_check("invert_y", "invert mouse Y")
	_refresh()

func _refresh() -> void:
	_building = true
	for key in _widgets:
		var w = _widgets[key]
		var val = Settings.v[key]
		if w[0] is OptionButton:
			var idx: int = w[1].call(val) if w.size() > 1 and w[1] is Callable and (w[1] as Callable).is_valid() else int(val)
			if key == "quality" and idx < 0:
				(w[0] as OptionButton).text = "custom"
				(w[0] as OptionButton).selected = -1
			else:
				(w[0] as OptionButton).selected = idx
		elif w[0] is HSlider:
			(w[0] as HSlider).value = float(val)
			(w[1] as Label).text = _fmt(key, float(val))
		elif w[0] is CheckBox:
			(w[0] as CheckBox).button_pressed = bool(val)
	_building = false

func _refresh_quality_only() -> void:
	_refresh()
