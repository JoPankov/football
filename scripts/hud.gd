class_name MatchHUD
extends CanvasLayer

const _CombatLog := preload("res://scripts/combat_log.gd")

const ACC_COLOR := Color("f0c14b")
const DEF_COLOR := Color("7dffe0")
const CTR_COLOR := Color("e39bff")
const STA_COLOR := Color("9dffb0")
const NRG_COLOR := Color("ffb347")
const BAR_TOP := 88.0
const BAR_BOTTOM := 108.0
const LOG_INSET := 308.0
const PLAY_MARGIN := 12.0

var _home_name: Label
var _away_name: Label
var _status: Label
var _possession: Label
var _hint: Label
var _phase: Label
var _turn: Label
var _event: Label
var _top_accent: ColorRect
var _phase_bar: ColorRect
var _log_title: Label
var _log_style: StyleBoxFlat
var _model: MatchModel
var _card: ColorRect
var _card_title: Label
var _card_acc: Label
var _card_def: Label
var _card_ctr: Label
var _card_sta: Label
var _card_nrg: Label
var _card_vs: Label
var _card_b_title: Label
var _card_b_acc: Label
var _card_b_def: Label
var _card_b_ctr: Label
var _card_b_sta: Label
var _card_b_nrg: Label
var last_event: Dictionary = {}

signal action_picked(action_id: String)
signal command_picked(action_id: String)
signal end_turn_pressed

var _choice_panel: PanelContainer
var _choice_box: VBoxContainer
var _choice_title: Label
var _forecast: ColorRect
var _forecast_label: Label
var _log_panel: PanelContainer
var _log_label: RichTextLabel
var _end_turn: Button
var _plan_list: Label
var _action_box: HBoxContainer
var _command_ids: PackedStringArray = []
var _shown_command_key: String = ""
var _resolving: bool = false
var require_end_turn: bool = false


func _ready() -> void:
	_build()
	_build_choice_panel()
	_build_forecast()
	_build_log()


func play_area() -> Rect2:
	var view := get_viewport().get_visible_rect().size
	var left := PLAY_MARGIN
	var top := BAR_TOP + 8.0
	var width := view.x - LOG_INSET - left
	var height := view.y - top - BAR_BOTTOM - 8.0
	return Rect2(left, top, maxf(width, 1.0), maxf(height, 1.0))


func refresh(
	model: MatchModel,
	selected: PlayerState,
	hovered: PlayerState = null,
	hover_cell: Vector2i = Vector2i(-1, -1),
	pending_action: String = ""
) -> void:
	_model = model
	var acting := MatchRules.team_name(model.current_team)
	_status.text = "%d   —   %d" % [model.home_score, model.away_score]
	_status.add_theme_color_override("font_color", Color("f4fbff"))
	_apply_phase(model)
	_refresh_end_turn(model)
	_refresh_plan_list(model)
	refresh_log(model)

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

	_hint.text = _hint_for(acting, selected, holder, hovered, hover_cell, model, pending_action)
	_event.text = _event_line(last_event)
	_show_inspector(model, selected, hovered)
	_show_forecast(model, selected, hover_cell, pending_action)
	_refresh_commands(model, selected, pending_action)


func _hint_for(
	acting: String,
	selected: PlayerState,
	holder: PlayerState,
	hovered: PlayerState,
	hover_cell: Vector2i,
	model: MatchModel,
	pending_action: String = ""
) -> String:
	if pending_action == "shoot" and selected != null and hover_cell == MatchRules.opponent_goal(selected.team):
		return model.shot_preview(selected).header
	if pending_action == "pass" and selected != null and model.can_plan_pass_to_cell(selected, hover_cell):
		return model.pass_preview(selected, hover_cell).header
	if pending_action in ["dribble", "tackle", "challenge"] and selected != null and hovered != null:
		if hover_cell in model.command_dests(selected, pending_action):
			var planning_holder := model.planning_carrier()
			var possession := planning_holder.team if planning_holder != null else -1
			return MatchRules.contest_preview(
				selected,
				hovered,
				model.planning_has_ball(selected),
				possession
			).text
	if selected != null and pending_action != "":
		return "Click a highlighted tile to queue %s for %s. Right-click or Esc cancels." % [
			pending_action.to_upper(),
			selected.label(),
		]
	if selected != null:
		return "Pick an action for %s, then click a highlighted tile. Keys 1–9 select actions." % selected.label()
	if _resolving:
		return "Resolution in progress — both teams' queued actions play out together."
	if require_end_turn:
		if holder == null:
			return "Pick up to %d %s players (one action each). Press End Turn to lock in. Hover a player to inspect ACC / DEF / CTR / STA." % [MatchRules.ACTIONS_PER_SIDE, acting]
		return "Pick up to %d %s players. Press End Turn to lock in. Click a planned player twice to clear their action." % [MatchRules.ACTIONS_PER_SIDE, acting]
	if holder == null:
		return "Pick up to %d %s players (one action each). The third action ends the turn; End Turn finishes early. Hover a player to inspect ACC / DEF / CTR / STA." % [MatchRules.ACTIONS_PER_SIDE, acting]
	return "Pick up to %d %s players. The third action ends the turn; End Turn finishes early. Click a planned player twice to clear their action." % [MatchRules.ACTIONS_PER_SIDE, acting]


func _event_line(event: Dictionary) -> String:
	return _CombatLog.format_result(event)


func _show_inspector(model: MatchModel, selected: PlayerState, hovered: PlayerState) -> void:
	var primary := selected if selected != null else hovered
	if primary == null:
		_card.visible = false
		return
	_card.visible = true
	_fill_card(primary, _card_title, _card_acc, _card_def, _card_ctr, _card_sta, _card_nrg)

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
	_card_b_sta.visible = compare
	_card_b_nrg.visible = compare
	if compare:
		var kind := "challenge"
		if model.planning_has_ball(selected):
			kind = "dribble"
		elif hovered.has_ball:
			kind = "tackle"
		_fill_card(hovered, _card_b_title, _card_b_acc, _card_b_def, _card_b_ctr, _card_b_sta, _card_b_nrg)
		if kind == "dribble":
			_emphasize_stat(_card_ctr, true)
			_emphasize_stat(_card_b_def, true)
		elif kind == "tackle":
			_emphasize_stat(_card_def, true)
			_emphasize_stat(_card_b_ctr, true)
		else:
			_emphasize_stat(_card_ctr, true)
			_emphasize_stat(_card_b_ctr, true)
	_card.offset_bottom = 400.0 if compare else 236.0


func _fill_card(
	player: PlayerState,
	title: Label,
	acc: Label,
	defense: Label,
	ctr: Label,
	sta: Label,
	nrg: Label
) -> void:
	title.text = player.label()
	title.add_theme_color_override(
		"font_color",
		Color("3ecbff") if player.team == MatchRules.Team.HOME else Color("ff4d8d")
	)
	acc.text = _stat_text("ACC", player.live_accuracy(), player.accuracy)
	defense.text = _stat_text("DEF", player.live_defense(), player.defense)
	ctr.text = _stat_text("CTR", player.live_control(), player.control)
	sta.text = "STA  %d" % player.stamina
	nrg.text = "NRG  %d/%d" % [player.energy, player.max_energy]
	acc.add_theme_color_override("font_color", ACC_COLOR)
	defense.add_theme_color_override("font_color", DEF_COLOR)
	ctr.add_theme_color_override("font_color", CTR_COLOR)
	sta.add_theme_color_override("font_color", STA_COLOR)
	nrg.add_theme_color_override("font_color", NRG_COLOR)


func _stat_text(name: String, live: int, base: int) -> String:
	if live == base:
		return "%s  %d" % [name, live]
	return "%s  %d (%d)" % [name, live, base]


func _emphasize_stat(label: Label, on: bool) -> void:
	if on:
		label.add_theme_color_override("font_color", Color("fff4c2"))


func set_resolving(value: bool) -> void:
	_resolving = value
	if _model != null:
		_apply_phase(_model)
		_refresh_end_turn(_model)
		_refresh_plan_list(_model)
		refresh_log(_model)
		if value:
			_hint.text = "Resolution in progress — both teams' queued actions play out together."
	elif _end_turn != null:
		_end_turn.disabled = true
		_end_turn.text = "RESOLVING..." if value else "END TURN"


func refresh_log(model: MatchModel) -> void:
	if _log_label == null:
		return
	_model = model
	var viewer := _CombatLog.VIEWER_PUBLIC if _resolving else model.current_team
	_log_label.text = model.combat_log.as_bbcode(viewer)
	if _resolving:
		_event.text = _event_line(last_event)


func _apply_phase(model: MatchModel) -> void:
	var home_turn := model.current_team == MatchRules.Team.HOME
	var acting := MatchRules.team_name(model.current_team)
	var queued := model.plan_count(model.current_team)
	var left := MatchRules.ACTIONS_PER_SIDE - queued
	var phase_color := Color("f0c14b") if _resolving else (
		Color("3ecbff") if home_turn else Color("ff4d8d")
	)
	if _phase != null:
		if _resolving:
			_phase.text = "RESOLVING"
		else:
			_phase.text = "%s PLANNING" % acting
		_phase.add_theme_color_override("font_color", phase_color)
	if _turn != null:
		if _resolving:
			_turn.text = "PLAYING OUT BOTH TEAMS"
		else:
			var left_word := "ACTION" if left == 1 else "ACTIONS"
			_turn.text = "%s   %d %s LEFT  ·  CYCLE %d" % [
				_pip_text(queued),
				left,
				left_word,
				model.turn_index + 1,
			]
		_turn.add_theme_color_override("font_color", phase_color.lightened(0.2))
	if _home_name != null:
		if _resolving:
			_home_name.modulate = Color(1, 1, 1, 0.8)
			_away_name.modulate = Color(1, 1, 1, 0.8)
		else:
			_home_name.modulate = Color.WHITE if home_turn else Color(1, 1, 1, 0.38)
			_away_name.modulate = Color.WHITE if not home_turn else Color(1, 1, 1, 0.38)
	if _top_accent != null:
		_top_accent.color = phase_color
	if _phase_bar != null:
		_phase_bar.color = phase_color
	if _log_title != null:
		_log_title.text = "RESOLUTION LOG" if _resolving else "%s LOG" % acting
		_log_title.add_theme_color_override("font_color", phase_color)
	if _log_style != null:
		_log_style.border_color = phase_color.darkened(0.25)


func _pip_text(queued: int) -> String:
	var marks: PackedStringArray = []
	for i in MatchRules.ACTIONS_PER_SIDE:
		marks.append("●" if i < queued else "○")
	return " ".join(marks)


func _refresh_end_turn(model: MatchModel) -> void:
	if _end_turn == null:
		return
	var ready := model.can_end_planning()
	_end_turn.disabled = _resolving or not ready
	if _resolving:
		_end_turn.text = "RESOLVING..."
	elif require_end_turn and model.planning_complete():
		_end_turn.text = "END TURN  %d/%d  — CONFIRM" % [model.plan_count(), MatchRules.ACTIONS_PER_SIDE]
	else:
		_end_turn.text = "END TURN  %d/%d" % [model.plan_count(), MatchRules.ACTIONS_PER_SIDE]


func _refresh_plan_list(model: MatchModel) -> void:
	if _plan_list == null:
		return
	if _resolving:
		_plan_list.text = "Playing out queued actions."
		return
	var lines: PackedStringArray = []
	var queued := model.plan_count(model.current_team)
	var left := MatchRules.ACTIONS_PER_SIDE - queued
	if queued == 0:
		lines.append("No actions queued · %d left" % left)
	else:
		lines.append("This turn  %s  ·  %d left" % [_pip_text(queued), left])
	for plan in model.plans_for(model.current_team):
		var player := model.player_by_id(int(plan.get("player_id", -1)))
		var name := player.label() if player != null else "player"
		lines.append("• %s  %s" % [name, _CombatLog.plan_summary(plan)])
	_plan_list.text = "\n".join(lines)


func _on_end_turn_pressed() -> void:
	end_turn_pressed.emit()


func _refresh_commands(model: MatchModel, selected: PlayerState, pending_action: String) -> void:
	if _action_box == null:
		return
	var key := "%s|%s|%s" % [
		str(selected.id) if selected != null else "-",
		pending_action,
		"busy" if _resolving else "ready",
	]
	if selected != null and not _resolving:
		for command in model.commands_for(selected):
			key += "," + str(command.get("id", ""))
	if key == _shown_command_key:
		return
	_shown_command_key = key
	for child in _action_box.get_children():
		_action_box.remove_child(child)
		child.queue_free()
	_command_ids = PackedStringArray()
	if selected == null or _resolving:
		return
	var commands := model.commands_for(selected)
	var index := 1
	for command in commands:
		var action_id := str(command.get("id", ""))
		_command_ids.append(action_id)
		var button := _command_button("%d  %s" % [index, str(command.get("label", action_id)).to_upper()])
		button.toggle_mode = true
		button.set_pressed_no_signal(action_id == pending_action)
		button.pressed.connect(_on_command_pressed.bind(action_id))
		_action_box.add_child(button)
		index += 1


func _on_command_pressed(action_id: String) -> void:
	command_picked.emit(action_id)


func _command_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(108, 36)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color("d6e4ee"))
	button.add_theme_color_override("font_hover_color", Color("ffe27a"))
	button.add_theme_color_override("font_pressed_color", Color("3ecbff"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.1, 0.16, 0.96)
	normal.border_color = Color("3ecbff")
	normal.set_border_width_all(1)
	normal.set_content_margin_all(8)
	var hover := normal.duplicate()
	hover.border_color = Color("ffe27a")
	hover.bg_color = Color(0.1, 0.16, 0.24, 0.98)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", hover)
	return button


func _build() -> void:
	var top := _panel(Color(0.03, 0.05, 0.08, 0.94))
	top.anchor_right = 1.0
	top.offset_bottom = 88.0
	add_child(top)

	_home_name = _label("AETHER", 28, Color("3ecbff"), HORIZONTAL_ALIGNMENT_LEFT)
	_home_name.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_home_name.offset_left = 28.0
	_home_name.offset_right = 280.0
	_home_name.offset_bottom = -44.0
	top.add_child(_home_name)

	_away_name = _label("HELIX", 28, Color("ff4d8d"), HORIZONTAL_ALIGNMENT_RIGHT)
	_away_name.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_away_name.offset_left = -280.0
	_away_name.offset_right = -28.0
	_away_name.offset_bottom = -44.0
	top.add_child(_away_name)

	_status = _label("0   —   0", 16, Color("f4fbff"), HORIZONTAL_ALIGNMENT_CENTER)
	_status.set_anchors_preset(Control.PRESET_FULL_RECT)
	_status.offset_top = 6.0
	_status.offset_bottom = -58.0
	top.add_child(_status)

	_phase = _label("AETHER PLANNING", 24, Color("3ecbff"), HORIZONTAL_ALIGNMENT_CENTER)
	_phase.set_anchors_preset(Control.PRESET_FULL_RECT)
	_phase.offset_left = 220.0
	_phase.offset_right = -220.0
	_phase.offset_top = 28.0
	_phase.offset_bottom = -22.0
	top.add_child(_phase)

	_turn = _label("○ ○ ○   3 ACTIONS LEFT  ·  CYCLE 1", 14, Color("3ecbff"), HORIZONTAL_ALIGNMENT_CENTER)
	_turn.set_anchors_preset(Control.PRESET_FULL_RECT)
	_turn.offset_top = 56.0
	top.add_child(_turn)

	_phase_bar = ColorRect.new()
	_phase_bar.color = Color("3ecbff")
	_phase_bar.anchor_top = 1.0
	_phase_bar.anchor_right = 1.0
	_phase_bar.anchor_bottom = 1.0
	_phase_bar.offset_top = -4.0
	top.add_child(_phase_bar)

	var bottom := _panel(Color(0.03, 0.05, 0.08, 0.88))
	bottom.anchor_top = 1.0
	bottom.anchor_right = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -BAR_BOTTOM
	add_child(bottom)

	_action_box = HBoxContainer.new()
	_action_box.add_theme_constant_override("separation", 8)
	_action_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_box.anchor_left = 0.0
	_action_box.anchor_right = 1.0
	_action_box.anchor_top = 0.0
	_action_box.anchor_bottom = 0.0
	_action_box.offset_left = 16.0
	_action_box.offset_right = -LOG_INSET
	_action_box.offset_top = 8.0
	_action_box.offset_bottom = 48.0
	_action_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_action_box)

	_possession = _label("BALL: LOOSE", 16, Color("f5e6a8"), HORIZONTAL_ALIGNMENT_LEFT)
	_possession.anchor_left = 0.0
	_possession.anchor_right = 0.0
	_possession.anchor_top = 1.0
	_possession.anchor_bottom = 1.0
	_possession.offset_left = 28.0
	_possession.offset_right = 520.0
	_possession.offset_top = -56.0
	_possession.offset_bottom = -28.0
	bottom.add_child(_possession)

	_event = _label("", 13, Color("ffb347"), HORIZONTAL_ALIGNMENT_LEFT)
	_event.anchor_left = 0.0
	_event.anchor_right = 0.0
	_event.anchor_top = 1.0
	_event.anchor_bottom = 1.0
	_event.offset_left = 28.0
	_event.offset_right = 700.0
	_event.offset_top = -28.0
	_event.offset_bottom = -4.0
	bottom.add_child(_event)

	_hint = _label("", 14, Color(0.78, 0.86, 0.92, 0.92), HORIZONTAL_ALIGNMENT_RIGHT)
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 240.0
	_hint.offset_right = -28.0
	_hint.offset_top = -56.0
	_hint.offset_bottom = -4.0
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_hint)

	_top_accent = ColorRect.new()
	_top_accent.color = Color("3ecbff")
	_top_accent.anchor_right = 1.0
	_top_accent.offset_bottom = 3.0
	top.add_child(_top_accent)

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
	_card.offset_top = 120.0
	_card.offset_right = 128.0
	_card.offset_bottom = 236.0
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
	_card_sta = _stat_label(8, 84, STA_COLOR)
	_card_nrg = _stat_label(8, 104, NRG_COLOR)
	_card.add_child(_card_acc)
	_card.add_child(_card_def)
	_card.add_child(_card_ctr)
	_card.add_child(_card_sta)
	_card.add_child(_card_nrg)

	_card_vs = _label("VS", 11, Color(0.85, 0.85, 0.9, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	_card_vs.offset_left = 8.0
	_card_vs.offset_top = 128.0
	_card_vs.offset_right = 116.0
	_card_vs.offset_bottom = 144.0
	_card_vs.visible = false
	_card.add_child(_card_vs)

	_card_b_title = _label("", 12, Color("ff4d8d"), HORIZONTAL_ALIGNMENT_LEFT)
	_card_b_title.offset_left = 8.0
	_card_b_title.offset_top = 146.0
	_card_b_title.offset_right = 116.0
	_card_b_title.offset_bottom = 164.0
	_card_b_title.visible = false
	_card.add_child(_card_b_title)

	_card_b_acc = _stat_label(8, 166, ACC_COLOR)
	_card_b_def = _stat_label(8, 186, DEF_COLOR)
	_card_b_ctr = _stat_label(8, 206, CTR_COLOR)
	_card_b_sta = _stat_label(8, 226, STA_COLOR)
	_card_b_nrg = _stat_label(8, 246, NRG_COLOR)
	for label in [_card_b_acc, _card_b_def, _card_b_ctr, _card_b_sta, _card_b_nrg]:
		label.visible = false
		_card.add_child(label)


func _show_forecast(
	model: MatchModel,
	selected: PlayerState,
	hover_cell: Vector2i,
	pending_action: String = ""
) -> void:
	if pending_action == "shoot" and selected != null and hover_cell == MatchRules.opponent_goal(selected.team):
		_forecast_label.text = _shot_forecast_text(model.shot_preview(selected))
		_forecast.visible = true
		return
	if pending_action == "pass" and selected != null and model.can_plan_pass_to_cell(selected, hover_cell):
		_forecast_label.text = _pass_forecast_text(selected, model.pass_preview(selected, hover_cell))
		_forecast.visible = true
		return
	_forecast.visible = false


func _shot_forecast_text(preview: Dictionary) -> String:
	return "%s\nd = %.2f tiles   θ = %.0f°   hit %d%%   save %d%%" % [
		str(preview.get("header", "shoot")),
		float(preview.get("distance", 0.0)),
		float(preview.get("angle_deg", 0.0)),
		int(round(float(preview.get("hit_chance", 0.0)) * 100.0)),
		int(round(float(preview.get("save_chance", 0.0)) * 100.0)),
	]


func _pass_forecast_text(passer: PlayerState, preview: Dictionary) -> String:
	var bits: PackedStringArray = [str(preview.get("header", "pass"))]
	for threat in preview.get("threats", []):
		var player: PlayerState = threat.get("player", null)
		var name := player.label() if player != null else "interceptor"
		bits.append(
			"%s: %d ACC vs %d DEF = %d%% intercept (%d%% through)" % [
				name,
				passer.live_accuracy() if passer != null else 0,
				player.live_defense() if player != null else 0,
				int(threat.get("intercept_percent", 0)),
				int(threat.get("through_percent", 0)),
			]
		)
	if bool(preview.get("offside", false)):
		bits.append("Offside if it arrives.")
	var total := int(preview.get("total_percent", 100))
	if preview.get("threats", []).is_empty():
		bits.append("No interceptors. Pass success: %d%%" % total)
	else:
		bits.append("Pass success: %d%%" % total)
	return "   ·   ".join(bits)


func _build_forecast() -> void:
	_forecast = _panel(Color(0.04, 0.06, 0.1, 0.94))
	_forecast.visible = false
	_forecast.anchor_left = 0.0
	_forecast.anchor_top = 1.0
	_forecast.anchor_right = 1.0
	_forecast.anchor_bottom = 1.0
	_forecast.offset_left = PLAY_MARGIN
	_forecast.offset_right = -LOG_INSET
	_forecast.offset_top = -60.0
	_forecast.offset_bottom = 0.0
	add_child(_forecast)

	var edge := ColorRect.new()
	edge.color = Color("6fd3ff")
	edge.anchor_right = 1.0
	edge.offset_bottom = 2.0
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_forecast.add_child(edge)

	_forecast_label = _label("", 12, Color(0.86, 0.92, 0.97, 0.95), HORIZONTAL_ALIGNMENT_LEFT)
	_forecast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forecast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_forecast_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_forecast_label.offset_left = 12.0
	_forecast_label.offset_top = 6.0
	_forecast_label.offset_right = -12.0
	_forecast_label.offset_bottom = -6.0
	_forecast.add_child(_forecast_label)


func _build_log() -> void:
	_log_panel = PanelContainer.new()
	_log_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.075, 0.94)
	style.border_color = Color("3ecbff")
	style.set_border_width_all(2)
	style.set_content_margin_all(8)
	_log_style = style
	_log_panel.add_theme_stylebox_override("panel", style)
	_log_panel.anchor_left = 1.0
	_log_panel.anchor_right = 1.0
	_log_panel.anchor_bottom = 1.0
	_log_panel.offset_left = -308.0
	_log_panel.offset_right = -8.0
	_log_panel.offset_top = 96.0
	_log_panel.offset_bottom = -(BAR_BOTTOM + 8.0)
	add_child(_log_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_log_panel.add_child(box)

	_log_title = _label("AETHER LOG", 13, Color("3ecbff"), HORIZONTAL_ALIGNMENT_LEFT)
	_log_title.custom_minimum_size = Vector2(0, 18)
	box.add_child(_log_title)

	_end_turn = Button.new()
	_end_turn.text = "END TURN  0/3"
	_end_turn.custom_minimum_size = Vector2(0, 34)
	_end_turn.disabled = false
	_end_turn.pressed.connect(_on_end_turn_pressed)
	box.add_child(_end_turn)

	_plan_list = _label("", 12, Color(0.78, 0.86, 0.92, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	_plan_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plan_list.custom_minimum_size = Vector2(0, 64)
	box.add_child(_plan_list)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.fit_content = false
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.add_theme_font_size_override("normal_font_size", 12)
	_log_label.add_theme_color_override("default_color", Color("d6e4ee"))
	_log_label.selection_enabled = true
	box.add_child(_log_label)


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
