class_name Hud
extends CanvasLayer
## Minimal atmospheric HUD, note reader, pause menu, fades and end screens.

const INK := Color(0.12, 0.11, 0.1)
const PALE := Color(0.86, 0.85, 0.8)

var world: Node
var root: Control
var fade: ColorRect
var vignette: TextureRect
var hurt_rect: ColorRect
var crosshair: Label
var prompt: Label
var objective: Label
var msg: Label
var subtitle: Label
var status: Label
var bars: Control
var fire_bar: ProgressBar
var health_bar: ProgressBar
var chop_bar: ProgressBar
var note_panel: Control
var note_title: Label
var note_body: Label
var pause_panel: Control
var end_panel: Control
var _msg_t := 0.0
var _obj_text := ""
var _hurt := 0.0
var note_open := false
var paused := false
var _settings: SettingsPanel

func _init() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

func _lbl(size: int, col: Color, hand := true, shadow := true) -> Label:
	Props.fonts()
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = Props.font_hand if hand else Props.font_type
	ls.font_size = size
	ls.font_color = col
	if shadow:
		ls.shadow_color = Color(0, 0, 0, 0.75)
		ls.shadow_size = 6
		ls.shadow_offset = Vector2(2, 2)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _bar(col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(220, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	vignette = TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.75))
	g.add_point(0.55, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	vignette.texture = gt
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)
	hurt_rect = ColorRect.new()
	hurt_rect.color = Color(0.35, 0.0, 0.0, 0.0)
	hurt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hurt_rect)
	crosshair = _lbl(26, Color(1, 1, 1, 0.5), false, false)
	crosshair.text = "·"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-5, -18)
	root.add_child(crosshair)
	prompt = _lbl(28, PALE, false)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.offset_top = -330; prompt.offset_bottom = -280
	prompt.offset_left = -700; prompt.offset_right = 700
	root.add_child(prompt)
	chop_bar = _bar(Color(0.8, 0.75, 0.65))
	chop_bar.set_anchors_preset(Control.PRESET_CENTER)
	chop_bar.position = Vector2(-110, 40)
	chop_bar.visible = false
	root.add_child(chop_bar)
	objective = _lbl(40, PALE)
	objective.position = Vector2(60, 46)
	objective.size = Vector2(1100, 120)
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(objective)
	msg = _lbl(46, PALE)
	msg.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.offset_left = -800; msg.offset_right = 800; msg.offset_top = 140; msg.offset_bottom = 260
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.modulate.a = 0.0
	root.add_child(msg)
	status = _lbl(26, PALE, false)
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	status.offset_left = -520; status.offset_top = -210; status.offset_right = -60; status.offset_bottom = -70
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	root.add_child(status)
	fire_bar = _bar(Color(1.0, 0.55, 0.2))
	fire_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fire_bar.position = Vector2(-280, -60)
	root.add_child(fire_bar)
	health_bar = _bar(Color(0.62, 0.1, 0.08))
	health_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_bar.position = Vector2(60, -60)
	root.add_child(health_bar)
	subtitle = _lbl(52, PALE)
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.offset_left = -800; subtitle.offset_right = 800; subtitle.offset_top = -60; subtitle.offset_bottom = 60
	subtitle.modulate.a = 0.0
	root.add_child(subtitle)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	move_child(fade, 0)
	root.move_child(subtitle, root.get_child_count() - 1)
	# put the fade above the HUD but below cinematic text
	remove_child(fade)
	root.add_child(fade)
	root.move_child(fade, root.get_child_count() - 2)
	_build_note()
	_build_pause()

func _paper_panel(size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = SettingsPanel.paper_theme()
	p.custom_minimum_size = size
	return p

func _build_note() -> void:
	note_panel = CenterContainer.new()
	note_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	note_panel.visible = false
	root.add_child(note_panel)
	var p := _paper_panel(Vector2(820, 760))
	p.rotation_degrees = 1.2
	p.pivot_offset = Vector2(410, 380)
	note_panel.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	note_title = Label.new()
	note_title.add_theme_font_size_override("font_size", 40)
	note_title.add_theme_color_override("font_color", Color(0.4, 0.38, 0.35))
	v.add_child(note_title)
	note_body = Label.new()
	note_body.add_theme_font_size_override("font_size", 40)
	note_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_body.custom_minimum_size = Vector2(720, 560)
	v.add_child(note_body)
	var hint := Label.new()
	hint.text = "[E] or [Esc] to put it down"
	hint.add_theme_font_override("font", Props.font_type)
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(0.35, 0.33, 0.3))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(hint)

func _build_pause() -> void:
	pause_panel = Control.new()
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.visible = false
	root.add_child(pause_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(c)
	var p := _paper_panel(Vector2(520, 520))
	p.rotation_degrees = -1.0
	c.add_child(p)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	var t := Label.new()
	t.text = "paused"
	t.add_theme_font_size_override("font_size", 60)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	for item in [["resume", toggle_pause], ["settings", open_settings], ["retry from last stop", func() -> void: Game.retry()], ["main menu", func() -> void: Game.goto_menu()], ["exit game", func() -> void: Game.quit()]]:
		var b := Button.new()
		b.text = item[0]
		b.add_theme_font_size_override("font_size", 42)
		b.pressed.connect(func() -> void:
			Sfx.play("ui_click", -4.0)
			item[1].call())
		b.mouse_entered.connect(func() -> void: Sfx.play("ui_hover", -10.0))
		v.add_child(b)

func open_settings() -> void:
	if _settings:
		return
	_settings = SettingsPanel.new()
	_settings.closed.connect(func() -> void: _settings = null)
	root.add_child(_settings)

func toggle_pause() -> void:
	if end_panel or world.cinematic:
		return
	paused = not paused
	pause_panel.visible = paused
	get_tree().paused = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	Sfx.muffle(paused, 900.0)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _settings:
			return
		if note_open:
			close_note()
		else:
			toggle_pause()
		get_viewport().set_input_as_handled()
	elif note_open and event.is_action_pressed("interact"):
		close_note()
		get_viewport().set_input_as_handled()

func show_note(title: String, body: String) -> void:
	note_title.text = title
	note_body.text = body
	note_panel.visible = true
	note_open = true
	get_tree().paused = true
	Sfx.play("paper")

func close_note() -> void:
	note_panel.visible = false
	note_open = false
	get_tree().paused = false
	Sfx.play("paper", -6.0, 1.2)

func message(text: String, dur := 3.0) -> void:
	msg.text = text
	_msg_t = dur
	msg.modulate.a = 1.0

func set_objective(text: String) -> void:
	if text == _obj_text:
		return
	_obj_text = text
	var tw := create_tween()
	tw.tween_property(objective, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: objective.text = text)
	tw.tween_property(objective, "modulate:a", 1.0, 0.8)

func set_prompt(text: String) -> void:
	prompt.text = text
	crosshair.modulate = Color(1, 0.85, 0.6, 1.0) if text != "" else Color(1, 1, 1, 0.6)

func hurt() -> void:
	_hurt = 1.0

func fade_to(a: float, t: float) -> Tween:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", a, t)
	return tw

func show_subtitle(text: String, t_in := 1.2, hold := 2.5, t_out := 1.2) -> Tween:
	subtitle.text = text
	var tw := create_tween()
	tw.tween_property(subtitle, "modulate:a", 1.0, t_in)
	tw.tween_interval(hold)
	tw.tween_property(subtitle, "modulate:a", 0.0, t_out)
	return tw

func update_status(s: Dictionary) -> void:
	var lines := []
	lines.append("GREYHAVEN  %.1f km" % s["dist_km"])
	if s["show_train"]:
		lines.append("%d km/h   ·   regulator %d/4%s" % [s["kmh"], s["notch"], "   ·   BRAKE" if s["brake"] else ""])
		lines.append("coal in tender  %d" % s["coal"])
	if s["carried"] > 0:
		lines.append("carrying coal  %d" % s["carried"])
	status.text = "\n".join(lines)
	fire_bar.visible = s["show_train"]
	fire_bar.value = s["fire"]
	health_bar.visible = s["health"] < 99.5
	health_bar.value = s["health"]
	var cp: float = s.get("chop", -1.0)
	chop_bar.visible = cp >= 0.0
	if cp >= 0.0:
		chop_bar.value = cp * 100.0

func _process(dt: float) -> void:
	if _msg_t > 0.0:
		_msg_t -= dt
		if _msg_t < 1.0:
			msg.modulate.a = maxf(0.0, _msg_t)
	_hurt = maxf(0.0, _hurt - dt * 0.8)
	var hp: float = world.player.health if world and world.player else 100.0
	hurt_rect.color.a = _hurt * 0.45 + (1.0 - hp / 100.0) * 0.12 * (0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.004))

## End screen. kind: "win" | "dead" | "derail" | "stranded"
func show_end(kind: String, title: String, sub: String, stats: String) -> void:
	if end_panel:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	end_panel = Control.new()
	end_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_panel.modulate.a = 0.0
	root.add_child(end_panel)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.82) if kind == "win" else Color(0.02, 0.0, 0.0, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_panel.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.offset_left = -700; v.offset_right = 700; v.offset_top = -330; v.offset_bottom = 380
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	end_panel.add_child(v)
	var t := _lbl(110, Color(0.95, 0.78, 0.5) if kind == "win" else Color(0.85, 0.82, 0.78))
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := _lbl(40, PALE)
	s.text = sub
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.custom_minimum_size = Vector2(1300, 0)
	v.add_child(s)
	var st := _lbl(26, Color(0.7, 0.68, 0.64), false)
	st.text = stats
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 50)
	h.theme = SettingsPanel.paper_theme()
	v.add_child(h)
	var buttons := []
	if kind != "win":
		buttons.append(["retry from last stop", func() -> void: Game.retry()])
	buttons.append(["restart journey", func() -> void: Game.start_new()])
	buttons.append(["main menu", func() -> void: Game.goto_menu()])
	if kind == "win":
		buttons.append(["exit game", func() -> void: Game.quit()])
	for item in buttons:
		var b := Button.new()
		b.text = item[0]
		b.add_theme_font_size_override("font_size", 42)
		b.add_theme_color_override("font_color", PALE)
		b.add_theme_color_override("font_hover_color", Color(1.0, 0.7, 0.4))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color(PALE, 0.5)
		sb.border_width_bottom = 2
		sb.content_margin_left = 14; sb.content_margin_right = 14
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.pressed.connect(func() -> void:
			Sfx.play("ui_click", -4.0)
			item[1].call())
		b.mouse_entered.connect(func() -> void: Sfx.play("ui_hover", -10.0))
		h.add_child(b)
	var tw := create_tween()
	tw.tween_property(end_panel, "modulate:a", 1.0, 2.0)
	prompt.text = ""
	objective.text = ""
	status.text = ""
