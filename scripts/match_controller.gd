extends Node2D

## Grid, 11v11. Each side plans up to 3 actions; the third locks the turn.

@onready var pitch: Pitch = $Pitch
@onready var hud: MatchHUD = $HUD
@onready var camera: Camera2D = $Camera2D
@onready var menu: GameMenu = $GameMenu

var model: MatchModel
var settings := GameSettings.new()
var vs_ai: bool = false
var pieces: Dictionary = {}
var selected_id: int = -1
var hover_cell: Vector2i = Vector2i(-1, -1)
var busy: bool = false
var animate_moves: bool = true
var _pending_choice: Dictionary = {}
var _resolve_generation: int = 0
var _active_tween: Tween


func _ready() -> void:
	animate_moves = DisplayServer.get_name() != "headless"
	if animate_moves:
		settings.load_from_disk()
	model = MatchModel.new()
	model.setup_kickoff()
	_spawn_visuals()
	get_viewport().size_changed.connect(_frame_camera)
	_frame_camera()
	hud.action_picked.connect(choose_action)
	hud.end_turn_pressed.connect(end_planning)
	hud.require_end_turn = settings.require_end_turn
	menu.bind_settings(settings)
	menu.hotseat_pressed.connect(start_hotseat)
	menu.vs_ai_pressed.connect(start_vs_ai)
	menu.new_game_pressed.connect(start_new_game)
	menu.exit_pressed.connect(_quit_game)
	menu.closed.connect(_on_menu_closed)
	menu.settings_changed.connect(_on_settings_changed)
	_refresh()
	if animate_moves:
		menu.open_title()
		get_tree().paused = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if menu != null and menu.is_open():
			return
		open_menu()
		get_viewport().set_input_as_handled()
		return
	if busy or get_tree().paused:
		return
	if event is InputEventMouseButton and event.pressed:
		var cell := pitch.world_to_grid(pitch.get_global_mouse_position())
		if event.button_index == MOUSE_BUTTON_LEFT:
			handle_cell_clicked(cell)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if not _pending_choice.is_empty():
				_cancel_choice()
			else:
				_deselect()
	elif event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		end_planning()
	elif event is InputEventMouseMotion:
		_set_hover(pitch.world_to_grid(pitch.get_global_mouse_position()))


func open_menu() -> void:
	if menu == null or menu.is_open() or menu.is_title_open():
		return
	_cancel_choice()
	menu.open()
	get_tree().paused = true


func close_menu() -> void:
	if menu != null:
		menu.close()
	get_tree().paused = false


func start_hotseat() -> void:
	vs_ai = false
	start_new_game()


func start_vs_ai() -> void:
	vs_ai = true
	start_new_game()


func start_new_game() -> void:
	_resolve_generation += 1
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null
	busy = false
	hud.set_resolving(false)
	hud.last_event = {}
	_pending_choice = {}
	hud.hide_choices()
	selected_id = -1
	hover_cell = Vector2i(-1, -1)
	pitch.clear_pass_preview()
	model = MatchModel.new()
	model.setup_kickoff()
	_spawn_visuals()
	close_menu()
	_begin_vs_ai_cycle()
	_refresh()


func _begin_vs_ai_cycle() -> void:
	if not vs_ai or model == null:
		return
	_preplan_ai()
	model.current_team = MatchRules.Team.HOME


func _preplan_ai() -> void:
	model.away_plans.clear()
	model.current_team = MatchRules.Team.AWAY
	AiCoach.fill_plans(model)
	model.current_team = MatchRules.Team.HOME


func _quit_game() -> void:
	get_tree().paused = false
	get_tree().quit()


func _on_menu_closed() -> void:
	get_tree().paused = false


func _on_settings_changed() -> void:
	hud.require_end_turn = settings.require_end_turn
	if model != null:
		hud.refresh(model, _selected_player(), _hovered_player(), hover_cell)
	if DisplayServer.get_name() != "headless":
		settings.save_to_disk()


func handle_cell_clicked(cell: Vector2i) -> Dictionary:
	if busy:
		return {ok = false, reason = "busy"}
	if not MatchRules.in_bounds(cell):
		_deselect()
		return {ok = false, reason = "out_of_bounds"}

	if not _pending_choice.is_empty():
		var same_cell: bool = cell == _pending_choice.get("cell", Vector2i(-99, -99))
		_cancel_choice()
		if same_cell:
			return {ok = true, action = "choose_cancel"}

	var occupant := model.player_at(cell)
	var selected := _selected_player()
	if selected != null:
		var actions: Array[Dictionary] = model.actions_for(selected, cell)
		if actions.size() > 1:
			return _open_choice(cell, actions)
		if actions.size() == 1:
			var only: Dictionary = actions[0]
			var only_swap: bool = str(only.get("id", "")) == "swap"
			if only_swap and occupant != null and model.can_select(occupant):
				_select(occupant)
				return {ok = true, action = "select", player_id = occupant.id}
			return perform_action(only)
		if occupant != null and model.can_select(occupant):
			if selected_id == occupant.id:
				if not model.plan_of(occupant.id).is_empty():
					model.clear_plan(occupant.id)
					_deselect()
					return {ok = true, action = "clear_plan", player_id = occupant.id}
				_deselect()
				return {ok = true, action = "deselect"}
			_select(occupant)
			return {ok = true, action = "select", player_id = occupant.id}
		_deselect()
		return {ok = false, reason = "no_action"}

	if occupant != null and model.can_select(occupant):
		_select(occupant)
		return {ok = true, action = "select", player_id = occupant.id}

	_deselect()
	return {ok = false, reason = "no_selection"}


func _open_choice(cell: Vector2i, actions: Array[Dictionary]) -> Dictionary:
	_pending_choice = {cell = cell, actions = actions}
	var screen := _cell_to_screen(cell)
	var occupant := model.player_at(cell)
	var title := "Choose action"
	if occupant != null:
		title = occupant.label()
	hud.show_choices(screen, title, actions)
	return {ok = true, action = "choose", options = actions, cell = cell}


func choose_action(action_id: String) -> Dictionary:
	if _pending_choice.is_empty():
		return {ok = false, reason = "no_choice"}
	var actions: Array = _pending_choice.get("actions", [])
	var chosen := {}
	for action in actions:
		if str(action.get("id", "")) == action_id:
			chosen = action
			break
	_pending_choice = {}
	hud.hide_choices()
	if chosen.is_empty():
		return {ok = false, reason = "unknown_action"}
	return perform_action(chosen)


func _cancel_choice() -> void:
	_pending_choice = {}
	hud.hide_choices()


func _cell_to_screen(cell: Vector2i) -> Vector2:
	return pitch.get_viewport().get_canvas_transform() * pitch.grid_to_world(cell)


func perform_action(action: Dictionary) -> Dictionary:
	var selected := _selected_player()
	if selected == null:
		return {ok = false, reason = "no_selection"}
	if not action.has("dest"):
		action.dest = hover_cell
	var result := model.queue_plan(selected.id, action)
	if not result.ok:
		return result
	hud.last_event = result
	_deselect()
	if model.planning_complete() and not settings.require_end_turn:
		return end_planning()
	return result


func end_planning() -> Dictionary:
	if busy:
		return {ok = false, reason = "busy"}
	_cancel_choice()
	var result := model.end_planning()
	if not result.ok:
		return result
	if vs_ai and str(result.get("action", "")) == "end_planning":
		if model.plan_count() == 0:
			_preplan_ai()
			model.current_team = MatchRules.Team.AWAY
		result = model.end_planning()
		if not result.ok:
			return result
	hud.last_event = result
	if str(result.get("action", "")) == "resolve":
		return _finish_resolve(result)
	_deselect()
	return result


func _finish_resolve(result: Dictionary) -> Dictionary:
	if animate_moves:
		_play_resolve(result)
	else:
		if result.get("reset", false):
			_spawn_visuals()
		_begin_vs_ai_cycle()
		_deselect()
	return result


func _play_resolve(result: Dictionary) -> void:
	busy = true
	hud.set_resolving(true)
	var token := _resolve_generation
	var events: Array = result.get("events", [])
	for event in events:
		if _resolve_generation != token:
			return
		hud.last_event = event
		hud.refresh_log(model)
		if not await _present_result(event):
			return
	if _resolve_generation != token:
		return
	if result.get("reset", false):
		_spawn_visuals()
	hud.set_resolving(false)
	busy = false
	_begin_vs_ai_cycle()
	_deselect()


func _anim(base: float) -> float:
	return maxf(0.02, base * settings.anim_scale())


func _anim_wait(base: float) -> bool:
	var token := _resolve_generation
	await get_tree().create_timer(_anim(base)).timeout
	return _resolve_generation == token


func _wait_for_tween(tween: Tween) -> bool:
	_active_tween = tween
	var token := _resolve_generation
	while is_instance_valid(tween) and tween.is_valid() and tween.is_running():
		if _resolve_generation != token:
			return false
		await get_tree().process_frame
	_active_tween = null
	return _resolve_generation == token


func _present_result(result: Dictionary) -> bool:
	var action: String = result.get("action", "move")
	if action == "cancelled" or action == "queue" or action == "end_planning":
		return await _anim_wait(0.08)
	if action == "clash":
		return await _anim_wait(0.18)
	var piece: PlayerPiece = pieces.get(result.get("player_id", -1))
	if piece == null:
		return true
	var dest: Vector2i = result.dest
	var won: bool = result.get("contest_won", true)
	if action == "shoot":
		pitch.ball_piece.set_carried(false)
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(pitch.ball_piece, "position", pitch.grid_to_world(dest), _anim(0.28))
		return await _wait_for_tween(tween)
	if action == "pass":
		var receiver := model.player_by_id(int(result.get("receiver_id", -1)))
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.set_parallel(true)
		if result.get("intercepted", false) and receiver != null:
			var interceptor_piece: PlayerPiece = pieces.get(receiver.id)
			if interceptor_piece != null:
				tween.tween_property(interceptor_piece, "position", pitch.grid_to_world(dest), _anim(0.22))
		var ball_target := _pass_ball_target(result, dest, receiver)
		pitch.ball_piece.set_carried(receiver != null)
		tween.tween_property(pitch.ball_piece, "position", ball_target, _anim(0.22))
		return await _wait_for_tween(tween)
	if action == "move" or action == "offside" or won:
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.set_parallel(true)
		tween.tween_property(piece, "position", pitch.grid_to_world(dest), _anim(0.2))
		var displaced_id: int = result.get("displaced_id", -1)
		if displaced_id >= 0:
			var other: PlayerPiece = pieces.get(displaced_id)
			if other != null:
				tween.tween_property(other, "position", pitch.grid_to_world(result.origin), _anim(0.2))
		var ball_target := _event_ball_target(result, dest)
		if ball_target != Vector2.INF:
			tween.tween_property(pitch.ball_piece, "position", ball_target, _anim(0.2))
		return await _wait_for_tween(tween)
	var start := piece.position
	var bump: Vector2 = start.lerp(pitch.grid_to_world(dest), 0.4)
	var tween := create_tween()
	tween.tween_property(piece, "position", bump, _anim(0.1))
	tween.tween_property(piece, "position", start, _anim(0.12))
	var ball_target := _event_ball_target(result, dest)
	if ball_target != Vector2.INF:
		tween.parallel().tween_property(pitch.ball_piece, "position", ball_target, _anim(0.18))
	return await _wait_for_tween(tween)


func _pass_ball_target(_result: Dictionary, dest: Vector2i, receiver: PlayerState) -> Vector2:
	if receiver == null:
		return pitch.grid_to_world(dest)
	return pitch.grid_to_world(dest) + pitch.carried_ball_offset(receiver.team)


func _event_ball_target(result: Dictionary, dest: Vector2i) -> Vector2:
	var action := str(result.get("action", ""))
	if result.get("lost_possession", false):
		var defender := model.player_by_id(int(result.get("defender_id", -1)))
		if defender != null:
			return pitch.grid_to_world(dest) + pitch.carried_ball_offset(defender.team)
		return pitch.grid_to_world(dest)
	if action == "swap":
		var holder_id := int(result.get("ball_holder_id", -1))
		var holder := model.player_by_id(holder_id)
		if holder == null:
			return Vector2.INF
		var cell: Vector2i = dest
		if holder_id != int(result.get("player_id", -1)):
			cell = result.origin
		return pitch.grid_to_world(cell) + pitch.carried_ball_offset(holder.team)
	if (
		result.get("gained_possession", false)
		or result.get("carried", false)
		or (action == "dribble" and result.get("contest_won", false))
		or action == "offside"
	):
		var holder := model.player_by_id(int(result.get("player_id", -1)))
		var team := holder.team if holder != null else MatchRules.Team.HOME
		return pitch.grid_to_world(dest) + pitch.carried_ball_offset(team)
	return Vector2.INF


func _select(player: PlayerState) -> void:
	selected_id = player.id
	_refresh()


func _deselect() -> void:
	_cancel_choice()
	selected_id = -1
	_refresh()


func _selected_player() -> PlayerState:
	if selected_id < 0:
		return null
	return model.player_by_id(selected_id)


func _spawn_visuals() -> void:
	pieces.clear()
	for child in pitch.pieces.get_children():
		if child != pitch.ball_piece:
			child.queue_free()
	for state in model.players:
		var piece := pitch.spawn_player(state)
		pieces[state.id] = piece
	pitch.sync_ball(model.ball, model.carrier())


func _frame_camera() -> void:
	var view := get_viewport().get_visible_rect().size
	var play := hud.play_area()
	var bounds := pitch.world_rect()
	var zoom := minf(play.size.x / bounds.size.x, play.size.y / bounds.size.y)
	camera.make_current()
	camera.zoom = Vector2(zoom, zoom)
	camera.position = Vector2(
		bounds.position.x - (play.position.x - view.x * 0.5) / zoom,
		bounds.get_center().y - (play.get_center().y - view.y * 0.5) / zoom
	)


func _set_hover(cell: Vector2i) -> void:
	if hover_cell == cell:
		return
	hover_cell = cell
	pitch.set_hover(cell)
	_update_pass_preview(_selected_player())
	hud.refresh(model, _selected_player(), _hovered_player(), hover_cell)


func _update_pass_preview(selected: PlayerState) -> void:
	if selected == null or not model.planning_has_ball(selected) or not model.can_plan_pass_to_cell(selected, hover_cell):
		pitch.clear_pass_preview()
		return
	var threats := model.interceptors_for_pass(selected, hover_cell)
	var cells: Array[Vector2i] = []
	for threat in threats:
		cells.append(threat.player.pos)
	pitch.set_pass_preview(selected.pos, hover_cell, cells)


func _hovered_player() -> PlayerState:
	if not MatchRules.in_bounds(hover_cell):
		return null
	return model.player_at(hover_cell)


func _refresh() -> void:
	var selected := _selected_player()
	var moves: Array[Vector2i] = []
	var contests: Array[Vector2i] = []
	var passes: Array[Vector2i] = []
	if selected != null:
		moves = model.valid_moves(selected)
		contests = model.contest_moves(selected)
		passes = model.pass_cells(selected)
		var choices: Array[Vector2i] = model.choice_cells(selected)
		var shots: Array[Vector2i] = model.shoot_cells(selected)
		var offsides: Array[Vector2i] = model.offside_pass_cells(selected)
		pitch.set_highlights(selected.pos, moves, contests, passes, choices, shots, offsides)
	else:
		pitch.clear_highlights()
	_update_pass_preview(selected)
	pitch.set_plans(_plan_markers())

	for state in model.players:
		var piece: PlayerPiece = pieces.get(state.id)
		if piece == null:
			continue
		piece.position = pitch.grid_to_world(state.pos)
		piece.set_selected(selected != null and state.id == selected.id)
		piece.set_has_ball(state.has_ball)
		var planned := (
			state.team == model.current_team
			and not model.plan_of(state.id).is_empty()
		)
		piece.set_planned(planned)
		piece.set_energy_ratio(state.energy_ratio())
		piece.set_on_turn(state.team == model.current_team and (planned or model.can_select(state)))
		piece.z_index = 5 if piece.selected else 3

	pitch.sync_ball(model.ball, model.carrier())
	hud.refresh(model, selected, _hovered_player(), hover_cell)


func _plan_markers() -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	for plan in model.plans_for(model.current_team):
		markers.append(plan)
	return markers
