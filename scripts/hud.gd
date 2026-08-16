class_name MatchHUD
extends CanvasLayer

const ACC_COLOR := Color("f0c14b")
const DEF_COLOR := Color("7dffe0")
const CTR_COLOR := Color("e39bff")

var _home_name: Label
var _away_name: Label
var _status: Label
var _possession: Label
var _hint: Label
var _turn: Label
var _event: Label
var _card: ColorRect
var _card_title: Label
var _card_acc: Label
var _card_def: Label
var _card_ctr: Label
var _card_vs: Label
var _card_b_title: Label
var _card_b_acc: Label
var _card_b_def: Label
var _card_b_ctr: Label
var last_event: Dictionary = {}

signal action_picked(action_id: String)

var _choice_panel: PanelContainer
var _choice_box: VBoxContainer
var _choice_title: Label
var _forecast: ColorRect
var _forecast_label: Label


func _ready() -> void:
	_build()
	_build_choice_panel()
	_build_forecast()


func refresh(
	model: MatchModel,
	selected: PlayerState,
	hovered: PlayerState = null,
	hover_cell: Vector2i = Vector2i(-1, -1)
) -> void:
	var acting := MatchRules.team_name(model.current_team)
	var home_turn := model.current_team == MatchRules.Team.HOME
	_status.text = "%d   —   %d" % [model.home_score, model.away_score]
	_status.add_theme_color_override("font_color", Color("f4fbff"))
	_turn.text = "%s TO ACT  ·  CYCLE %d" % [acting, model.turn_index + 1]
	_turn.add_theme_color_override(
		"font_color",
		Color("3ecbff") if home_turn else Color("ff4d8d")
	)

	var holder := model.carrier()
	if holder == null:
		_possession.text = "BALL: LOOSE"
		_possession.add_theme_color_override("font_color", Color("f5e6a8"))
	else:
		_possession.text = "BALL: %s" % holder.label()
		_possession.add_theme_color_override(
			"font_color",
			Color("3ecbff") if holder.team == MatchRules.Team.HOME else Color("ff4d8d")
		)

	_hint.text = _hint_for(acting, selected, holder, hovered, hover_cell, model)
	_event.text = _event_line(last_event)
	_show_inspector(selected, hovered)
	_show_forecast(model, selected, hover_cell)


func _hint_for(
	acting: String,
	selected: PlayerState,
	holder: PlayerState,
	hovered: PlayerState,
	hover_cell: Vector2i,
	model: MatchModel
) -> String:
	if selected != null and model.can_shoot(selected) and hover_cell == MatchRules.opponent_goal(selected.team):
		return model.shot_preview(selected).header
	if selected != null and selected.has_ball and model.can_pass_to_cell(selected, hover_cell):
		var preview := model.pass_preview(selected, hover_cell)
		if hovered != null and hovered.team == selected.team and MatchRules.is_adjacent(selected.pos, hovered.pos):
			return preview.header + " or swap places"
		if hovered == null and MatchRules.is_adjacent(selected.pos, hover_cell):
			return preview.header + " or move there"
		return preview.header
	if selected != null and hovered != null and hovered.id != selected.id:
		if hovered.team != selected.team and MatchRules.is_adjacent(selected.pos, hovered.pos):
			return MatchRules.contest_preview(selected, hovered).text
	if selected != null:
		if selected.has_ball:
			if model.can_shoot(selected):
				return "Selected %s — gold: shoot at the net. Green: move. Blue: pass." % selected.label()
			return "Selected %s — green: move. Amber: dribble. Blue: pass. Red: offside pass. Adjacent teammate: pass or swap." % selected.label()
		return "Selected %s — green: move. Amber: tackle the carrier (DEF vs CTR) or fight for a square (CTR vs CTR)." % selected.label()
	if holder == null:
		return "Click any %s player. Hover a player to inspect ACC / DEF / CTR." % acting
	return "Click any %s player. The ball stays with the carrier when they move." % acting


func _event_line(event: Dictionary) -> String:
	if event.is_empty() or not event.get("ok", false):
		return ""
	var action: String = event.get("action", "move")
	if event.get("goal", false) and action != "shoot":
		return "GOAL  walked in  %d—%d" % [event.get("home_score", 0), event.get("away_score", 0)]
	if action == "shoot":
		if event.get("goal", false):
			return "GOAL  %s  %d—%d" % [
				event.get("attacker_label", "shooter"),
				event.get("home_score", 0),
				event.get("away_score", 0),
			]
		if event.get("saved", false):
			return "SAVE  %s's shot was held" % event.get("attacker_label", "shooter")
		return "MISS  %s's shot missed the net" % event.get("attacker_label", "shooter")
	if action == "offside":
		return "OFFSIDE  %s  →  %s takes the restart" % [
			event.get("defender_label", "receiver"),
			event.get("taker_label", "defender"),
		]
	if action == "pass":
		if event.get("intercepted", false):
			return "INTERCEPT  %s %s %d+%d=%d  vs  %s %s %d+%d=%d" % [
				event.get("attacker_label", "passer"),
				event.get("attacker_stat_name", "ACC"),
				event.get("attacker_stat", 0),
				event.get("attacker_dice", 0),
				event.get("attacker_total", 0),
				event.get("defender_label", "interceptor"),
				event.get("defender_stat_name", "DEF"),
				event.get("defender_stat", 0),
				event.get("defender_dice", 0),
				event.get("defender_total", 0),
			]
		return "PASS  %s  →  %s" % [
			event.get("attacker_label", "passer"),
			event.get("defender_label", "receiver"),
		]
	if action == "swap":
		return "SWAP  %s  ⇄  %s" % [
			event.get("attacker_label", "mover"),
			event.get("defender_label", "teammate"),
		]
	if action != "dribble" and action != "challenge" and action != "tackle":
		return ""
	var verb := "SQUARE FIGHT"
	if action == "dribble":
		verb = "DRIBBLE"
	elif action == "tackle":
		verb = "TACKLE"
	var outcome := "WON" if event.get("contest_won", false) else "LOST"
	return "%s %s  %s %s %d+%d=%d  vs  %s %s %d+%d=%d" % [
		verb,
		outcome,
		event.get("attacker_label", "attacker"),
		event.get("attacker_stat_name", "CTR"),
		event.get("attacker_stat", 0),
		event.get("attacker_dice", 0),
		event.get("attacker_total", 0),
		event.get("defender_label", "defender"),
		event.get("defender_stat_name", "DEF"),
		event.get("defender_stat", 0),
		event.get("defender_dice", 0),
		event.get("defender_total", 0),
	]


func _show_inspector(selected: PlayerState, hovered: PlayerState) -> void:
	var primary := selected if selected != null else hovered
	if primary == null:
		_card.visible = false
		return
	_card.visible = true
	_fill_card(primary, _card_title, _card_acc, _card_def, _card_ctr, "")

	var compare := (
		hovered != null
		and selected != null
		and hovered.id != selected.id
		and hovered.team != selected.team
		and MatchRules.is_adjacent(selected.pos, hovered.pos)
	)
	_card_vs.visible = compare
	_card_b_title.visible = compare
	_card_b_acc.visible = compare
	_card_b_def.visible = compare
	_card_b_ctr.visible = compare
	if compare:
		var kind := "challenge"
		if selected.has_ball:
			kind = "dribble"
		elif hovered.has_ball:
			kind = "tackle"
		_fill_card(hovered, _card_b_title, _card_b_acc, _card_b_def, _card_b_ctr, kind)
		if kind == "dribble":
			_emphasize_stat(_card_ctr, true)
			_emphasize_stat(_card_b_def, true)
		elif kind == "tackle":
			_emphasize_stat(_card_def, true)
			_emphasize_stat(_card_b_ctr, true)
		else:
			_emphasize_stat(_card_ctr, true)
			_emphasize_stat(_card_b_ctr, true)
	_card.offset_bottom = 348.0 if compare else 196.0


func _fill_card(
	player: PlayerState,
	title: Label,
	acc: Label,
	defense: Label,
	ctr: Label,
	_kind: String
) -> void:
	title.text = player.label()
	title.add_theme_color_override(
		"font_color",
		Color("3ecbff") if player.team == MatchRules.Team.HOME else Color("ff4d8d")
	)
	acc.text = "ACC  %d" % player.accuracy
	defense.text = "DEF  %d" % player.defense
	ctr.text = "CTR  %d" % player.control
	acc.add_theme_color_override("font_color", ACC_COLOR)
	defense.add_theme_color_override("font_color", DEF_COLOR)
	ctr.add_theme_color_override("font_color", CTR_COLOR)


func _emphasize_stat(label: Label, on: bool) -> void:
	if on:
		label.add_theme_color_override("font_color", Color("fff4c2"))


func _build() -> void:
	var top := _panel(Color(0.03, 0.05, 0.08, 0.92))
	top.anchor_right = 1.0
	top.offset_bottom = 64.0
	add_child(top)

	_home_name = _label("AETHER", 28, Color("3ecbff"), HORIZONTAL_ALIGNMENT_LEFT)
	_home_name.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_home_name.offset_left = 28.0
	_home_name.offset_right = 260.0
	top.add_child(_home_name)

	_away_name = _label("HELIX", 28, Color("ff4d8d"), HORIZONTAL_ALIGNMENT_RIGHT)
	_away_name.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_away_name.offset_left = -260.0
	_away_name.offset_right = -28.0
	top.add_child(_away_name)

	_status = _label("AETHER TO ACT", 22, Color("3ecbff"), HORIZONTAL_ALIGNMENT_CENTER)
	_status.set_anchors_preset(Control.PRESET_FULL_RECT)
	_status.offset_top = 6.0
	_status.offset_bottom = -22.0
	top.add_child(_status)

	_turn = _label("CYCLE 1", 13, Color(0.72, 0.82, 0.9, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	_turn.set_anchors_preset(Control.PRESET_FULL_RECT)
	_turn.offset_top = 34.0
	top.add_child(_turn)

	var bottom := _panel(Color(0.03, 0.05, 0.08, 0.88))
	bottom.anchor_top = 1.0
	bottom.anchor_right = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -72.0
	add_child(bottom)

	_possession = _label("BALL: LOOSE", 16, Color("f5e6a8"), HORIZONTAL_ALIGNMENT_LEFT)
	_possession.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_possession.offset_left = 28.0
	_possession.offset_right = 520.0
	_possession.offset_bottom = -28.0
	bottom.add_child(_possession)

	_event = _label("", 13, Color("ffb347"), HORIZONTAL_ALIGNMENT_LEFT)
	_event.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_event.offset_left = 28.0
	_event.offset_top = 32.0
	_event.offset_right = 700.0
	bottom.add_child(_event)

	_hint = _label("", 14, Color(0.78, 0.86, 0.92, 0.92), HORIZONTAL_ALIGNMENT_RIGHT)
	_hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hint.offset_left = 240.0
	_hint.offset_right = -28.0
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_hint)

	var accent := ColorRect.new()
	accent.color = Color("3ecbff")
	accent.anchor_right = 1.0
	accent.offset_bottom = 2.0
	top.add_child(accent)

	var accent_bottom := ColorRect.new()
	accent_bottom.color = Color("ff4d8d")
	accent_bottom.anchor_right = 1.0
	accent_bottom.offset_bottom = 2.0
	bottom.add_child(accent_bottom)

	_build_card()


func _build_card() -> void:
	_card = _panel(Color(0.04, 0.06, 0.1, 0.94))
	_card.visible = false
	_card.offset_left = 8.0
	_card.offset_top = 108.0
	_card.offset_right = 128.0
	_card.offset_bottom = 200.0
	add_child(_card)

	var edge := ColorRect.new()
	edge.color = Color("3ecbff")
	edge.offset_right = 3.0
	edge.anchor_bottom = 1.0
	_card.add_child(edge)

	_card_title = _label("", 12, Color("3ecbff"), HORIZONTAL_ALIGNMENT_LEFT)
	_card_title.offset_left = 8.0
	_card_title.offset_top = 4.0
	_card_title.offset_right = 116.0
	_card_title.offset_bottom = 22.0
	_card.add_child(_card_title)

	_card_acc = _stat_label(8, 24, ACC_COLOR)
	_card_def = _stat_label(8, 44, DEF_COLOR)
	_card_ctr = _stat_label(8, 64, CTR_COLOR)
	_card.add_child(_card_acc)
	_card.add_child(_card_def)
	_card.add_child(_card_ctr)

	_card_vs = _label("VS", 11, Color(0.85, 0.85, 0.9, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	_card_vs.offset_left = 8.0
	_card_vs.offset_top = 88.0
	_card_vs.offset_right = 116.0
	_card_vs.offset_bottom = 104.0
	_card_vs.visible = false
	_card.add_child(_card_vs)

	_card_b_title = _label("", 12, Color("ff4d8d"), HORIZONTAL_ALIGNMENT_LEFT)
	_card_b_title.offset_left = 8.0
	_card_b_title.offset_top = 106.0
	_card_b_title.offset_right = 116.0
	_card_b_title.offset_bottom = 124.0
	_card_b_title.visible = false
	_card.add_child(_card_b_title)

	_card_b_acc = _stat_label(8, 126, ACC_COLOR)
	_card_b_def = _stat_label(8, 146, DEF_COLOR)
	_card_b_ctr = _stat_label(8, 166, CTR_COLOR)
	for label in [_card_b_acc, _card_b_def, _card_b_ctr]:
		label.visible = false
		_card.add_child(label)


func _show_forecast(model: MatchModel, selected: PlayerState, hover_cell: Vector2i) -> void:
	if selected != null and model.can_shoot(selected) and hover_cell == MatchRules.opponent_goal(selected.team):
		_forecast_label.text = model.shot_preview(selected).text
		_forecast.visible = true
		return
	if selected == null or not selected.has_ball or not model.can_pass_to_cell(selected, hover_cell):
		_forecast.visible = false
		return
	var preview := model.pass_preview(selected, hover_cell)
	_forecast_label.text = preview.text
	_forecast.visible = true


func _build_forecast() -> void:
	_forecast = _panel(Color(0.04, 0.06, 0.1, 0.94))
	_forecast.visible = false
	_forecast.anchor_left = 1.0
	_forecast.anchor_right = 1.0
	_forecast.offset_left = -220.0
	_forecast.offset_right = -8.0
	_forecast.offset_top = 108.0
	_forecast.offset_bottom = 360.0
	add_child(_forecast)

	var edge := ColorRect.new()
	edge.color = Color("6fd3ff")
	edge.anchor_left = 1.0
	edge.anchor_right = 1.0
	edge.offset_left = -3.0
	edge.anchor_bottom = 1.0
	_forecast.add_child(edge)

	_forecast_label = _label("", 13, Color(0.86, 0.92, 0.97, 0.95), HORIZONTAL_ALIGNMENT_LEFT)
	_forecast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forecast_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_forecast_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_forecast_label.offset_left = 12.0
	_forecast_label.offset_top = 10.0
	_forecast_label.offset_right = -10.0
	_forecast_label.offset_bottom = -10.0
	_forecast.add_child(_forecast_label)


func show_choices(screen_pos: Vector2, title: String, options: Array) -> void:
	_clear_choice_buttons()
	_choice_title.text = title
	for option in options:
		var button := Button.new()
		button.text = str(option.get("label", option.get("id", "?")))
		button.custom_minimum_size = Vector2(168, 32)
		button.pressed.connect(_on_choice_pressed.bind(str(option.get("id", ""))))
		_choice_box.add_child(button)
	_choice_panel.visible = true
	await get_tree().process_frame
	var size := _choice_panel.size
	var view := get_viewport().get_visible_rect().size
	var pos := screen_pos + Vector2(20, -size.y * 0.35)
	pos.x = clampf(pos.x, 8.0, view.x - size.x - 8.0)
	pos.y = clampf(pos.y, 72.0, view.y - size.y - 80.0)
	_choice_panel.position = pos


func hide_choices() -> void:
	_choice_panel.visible = false
	_clear_choice_buttons()


func _on_choice_pressed(action_id: String) -> void:
	hide_choices()
	action_picked.emit(action_id)


func _clear_choice_buttons() -> void:
	if _choice_box == null:
		return
	for child in _choice_box.get_children():
		if child != _choice_title:
			child.queue_free()


func _build_choice_panel() -> void:
	_choice_panel = PanelContainer.new()
	_choice_panel.visible = false
	_choice_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.11, 0.96)
	style.border_color = Color("6fd3ff")
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	_choice_panel.add_theme_stylebox_override("panel", style)
	add_child(_choice_panel)

	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 6)
	_choice_panel.add_child(_choice_box)

	_choice_title = _label("Choose action", 13, Color(0.82, 0.9, 0.96, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	_choice_box.add_child(_choice_title)


func _stat_label(x: float, y: float, color: Color) -> Label:
	var label := _label("", 16, color, HORIZONTAL_ALIGNMENT_LEFT)
	label.offset_left = x
	label.offset_top = y
	label.offset_right = x + 90.0
	label.offset_bottom = y + 26.0
	return label


func _panel(color: Color) -> ColorRect:
	var panel := ColorRect.new()
	panel.color = color
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _label(text: String, size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
