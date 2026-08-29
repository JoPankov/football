class_name GameMenu
extends CanvasLayer

## Title on launch; pause overlay in-match. ESC resumes pause, or backs out of Options.

signal hotseat_pressed
signal vs_ai_pressed
signal ai_vs_ai_pressed
signal new_game_pressed
signal exit_pressed
signal closed
signal settings_changed

const ACCENT := Color("3ecbff")
const GOLD := Color("f0c14b")
const TEXT := Color("f4fbff")
const MUTED := Color(0.78, 0.86, 0.92, 0.88)

var settings: GameSettings

var _title_mode: bool = false
var _dim: ColorRect
var _title_panel: PanelContainer
var _main_panel: PanelContainer
var _options_panel: PanelContainer
var _hotseat_btn: Button
var _vs_ai_btn: Button
var _ai_vs_ai_btn: Button
var _title_exit_btn: Button
var _resume_btn: Button
var _new_game_btn: Button
var _options_btn: Button
var _exit_btn: Button
var _back_btn: Button
var _end_turn_check: CheckBox
var _speed_slider: HSlider
var _speed_value: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func bind_settings(value: GameSettings) -> void:
	settings = value
	_sync_options()


func open() -> void:
	_title_mode = false
	_sync_options()
	_show_main()
	visible = true
	if _resume_btn != null:
		_resume_btn.grab_focus()


func open_title() -> void:
	_title_mode = true
	if _title_panel != null:
		_title_panel.visible = true
	if _main_panel != null:
		_main_panel.visible = false
	if _options_panel != null:
		_options_panel.visible = false
	visible = true
	if _hotseat_btn != null:
		_hotseat_btn.grab_focus()


func close() -> void:
	_title_mode = false
	visible = false


func is_open() -> bool:
	return visible


func is_title_open() -> bool:
	return visible and _title_mode


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_on_escape()
		get_viewport().set_input_as_handled()


func _on_escape() -> void:
	if _title_mode:
		return
	if _options_panel.visible:
		_show_main()
		if _options_btn != null:
			_options_btn.grab_focus()
	else:
		_resume()


func _resume() -> void:
	close()
	closed.emit()


func _show_main() -> void:
	_title_mode = false
	if _title_panel != null:
		_title_panel.visible = false
	_main_panel.visible = true
	_options_panel.visible = false


func _show_options() -> void:
	_sync_options()
	if _title_panel != null:
		_title_panel.visible = false
	_main_panel.visible = false
	_options_panel.visible = true
	if _end_turn_check != null:
		_end_turn_check.grab_focus()


func _sync_options() -> void:
	if settings == null:
		return
	if _end_turn_check != null:
		_end_turn_check.set_pressed_no_signal(settings.require_end_turn)
	if _speed_slider != null:
		_speed_slider.set_value_no_signal(settings.animation_speed)
	_refresh_speed_label()


func _refresh_speed_label() -> void:
	if _speed_value == null or settings == null:
		return
	_speed_value.text = str(settings.animation_speed)


func _on_hotseat() -> void:
	hotseat_pressed.emit()


func _on_vs_ai() -> void:
	vs_ai_pressed.emit()


func _on_ai_vs_ai() -> void:
	ai_vs_ai_pressed.emit()


func _on_new_game() -> void:
	new_game_pressed.emit()


func _on_options() -> void:
	_show_options()


func _on_exit() -> void:
	exit_pressed.emit()


func _on_back() -> void:
	_show_main()
	if _options_btn != null:
		_options_btn.grab_focus()


func _on_end_turn_toggled(pressed: bool) -> void:
	if settings == null:
		return
	settings.require_end_turn = pressed
	settings_changed.emit()


func _on_speed_changed(value: float) -> void:
	if settings == null:
		return
	settings.set_animation_speed(int(round(value)))
	_refresh_speed_label()
	settings_changed.emit()


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.03, 0.05, 0.72)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_gui_input)
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_title_panel = _panel()
	_title_panel.visible = false
	center.add_child(_title_panel)
	_build_title(_title_panel)

	_main_panel = _panel()
	center.add_child(_main_panel)
	_build_main(_main_panel)

	_options_panel = _panel()
	_options_panel.visible = false
	center.add_child(_options_panel)
	_build_options(_options_panel)


func _on_dim_gui_input(event: InputEvent) -> void:
	if _title_mode:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_escape()


func _build_title(panel: PanelContainer) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(360, 0)
	panel.add_child(box)

	box.add_child(_title("SCI-FI FOOTBALL"))
	box.add_child(_rule())

	_hotseat_btn = _menu_button("NEW HOTSEAT")
	_hotseat_btn.pressed.connect(_on_hotseat)
	box.add_child(_hotseat_btn)

	_vs_ai_btn = _menu_button("NEW VS AI")
	_vs_ai_btn.pressed.connect(_on_vs_ai)
	box.add_child(_vs_ai_btn)

	_ai_vs_ai_btn = _menu_button("NEW AI vs AI")
	_ai_vs_ai_btn.pressed.connect(_on_ai_vs_ai)
	box.add_child(_ai_vs_ai_btn)

	_title_exit_btn = _menu_button("EXIT")
	_title_exit_btn.pressed.connect(_on_exit)
	box.add_child(_title_exit_btn)


func _build_main(panel: PanelContainer) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(360, 0)
	panel.add_child(box)

	box.add_child(_title("MENU"))
	box.add_child(_rule())

	_resume_btn = _menu_button("RESUME")
	_resume_btn.pressed.connect(_resume)
	box.add_child(_resume_btn)

	_new_game_btn = _menu_button("NEW GAME")
	_new_game_btn.pressed.connect(_on_new_game)
	box.add_child(_new_game_btn)

	_options_btn = _menu_button("OPTIONS")
	_options_btn.pressed.connect(_on_options)
	box.add_child(_options_btn)

	_exit_btn = _menu_button("EXIT")
	_exit_btn.pressed.connect(_on_exit)
	box.add_child(_exit_btn)

	var hint := _label("ESC to resume", 13, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	hint.custom_minimum_size = Vector2(0, 22)
	box.add_child(hint)


func _build_options(panel: PanelContainer) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(420, 0)
	panel.add_child(box)

	box.add_child(_title("OPTIONS"))
	box.add_child(_rule())

	_end_turn_check = CheckBox.new()
	_end_turn_check.text = "Require END TURN to finish planning"
	_end_turn_check.add_theme_font_size_override("font_size", 15)
	_end_turn_check.add_theme_color_override("font_color", TEXT)
	_end_turn_check.add_theme_color_override("font_pressed_color", TEXT)
	_end_turn_check.add_theme_color_override("font_hover_color", GOLD)
	_end_turn_check.toggled.connect(_on_end_turn_toggled)
	box.add_child(_end_turn_check)

	var check_hint := _label(
		"When on, queuing the third action does not lock the turn.",
		12,
		MUTED,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	check_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(check_hint)

	var speed_header := HBoxContainer.new()
	speed_header.add_theme_constant_override("separation", 12)
	box.add_child(speed_header)

	var speed_title := _label("Resolution animation speed", 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	speed_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_header.add_child(speed_title)

	_speed_value = _label("5", 18, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_speed_value.custom_minimum_size = Vector2(28, 0)
	speed_header.add_child(_speed_value)

	_speed_slider = HSlider.new()
	_speed_slider.min_value = GameSettings.ANIM_SPEED_MIN
	_speed_slider.max_value = GameSettings.ANIM_SPEED_MAX
	_speed_slider.step = 1
	_speed_slider.rounded = true
	_speed_slider.tick_count = GameSettings.ANIM_SPEED_MAX
	_speed_slider.custom_minimum_size = Vector2(0, 28)
	_speed_slider.value_changed.connect(_on_speed_changed)
	box.add_child(_speed_slider)

	var speed_ends := HBoxContainer.new()
	speed_ends.add_theme_constant_override("separation", 8)
	box.add_child(speed_ends)
	var slow := _label("1  slow", 12, MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	slow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_ends.add_child(slow)
	speed_ends.add_child(_label("fast  10", 12, MUTED, HORIZONTAL_ALIGNMENT_RIGHT))

	_back_btn = _menu_button("BACK")
	_back_btn.pressed.connect(_on_back)
	box.add_child(_back_btn)


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.1, 0.97)
	style.border_color = ACCENT
	style.set_border_width_all(2)
	style.set_content_margin_all(22)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", GOLD)
	button.add_theme_color_override("font_pressed_color", ACCENT)
	button.add_theme_color_override("font_focus_color", GOLD)
	var normal := _button_style(Color(0.06, 0.1, 0.16, 0.96), ACCENT)
	var hover := _button_style(Color(0.1, 0.16, 0.24, 0.98), GOLD)
	var focus := _button_style(Color(0.08, 0.14, 0.22, 0.98), GOLD)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", focus)
	return button


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	return style


func _title(text: String) -> Label:
	var label := _label(text, 28, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	label.custom_minimum_size = Vector2(0, 36)
	return label


func _rule() -> ColorRect:
	var line := ColorRect.new()
	line.color = ACCENT
	line.custom_minimum_size = Vector2(0, 3)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _label(text: String, size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
