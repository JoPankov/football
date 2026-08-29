extends Node2D

## Grid, 11v11. Each side plans up to 3 players (6 AP each); filling their AP locks the turn.

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
var _pending_action: String = ""
var _resolve_generation: int = 0
var _active_tween: Tween
var _cycle_snapshot: Dictionary = {}


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
	hud.command_picked.connect(select_command)
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
		if _pending_action != "":
			_cancel_command()
			get_viewport().set_input_as_handled()
			return
		if selected_id >= 0:
			_deselect()
			get_viewport().set_input_as_handled()
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
			handle_cell_right_clicked(cell)
	elif _is_end_turn_key(event):
		end_planning()
		get_viewport().set_input_as_handled()
	elif _is_undo_key(event):
		undo_last_action()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		_try_command_hotkey(event.keycode)
	elif event is InputEventMouseMotion:
		_set_hover(pitch.world_to_grid(pitch.get_global_mouse_position()))


func open_menu() -> void:
	if menu == null or menu.is_open() or menu.is_title_open():
		return
	_cancel_choice()
	_pending_action = ""
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
	_pending_action = ""
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
	# Helix kickoff still preplans invisibly. The human never sits through a Helix
	# chair — Helix is already locked, Aether plans the same cycle immediately.
	if model.current_team == MatchRules.Team.AWAY:
		model.awaiting_other_side = true
	model.current_team = MatchRules.Team.HOME


func _preplan_ai() -> void:
	var previous := model.current_team
	model.away_plans.clear()
	model.current_team = MatchRules.Team.AWAY
	AiCoach.fill_plans(model)
	model.current_team = previous


func _quit_game() -> void:
	get_tree().paused = false
	get_tree().quit()


func _on_menu_closed() -> void:
	get_tree().paused = false


func _on_settings_changed() -> void:
	hud.require_end_turn = settings.require_end_turn
	if model != null:
		hud.refresh(model, _selected_player(), _hovered_player(), hover_cell, _pending_action)
	if DisplayServer.get_name() != "headless":
		settings.save_to_disk()


func handle_cell_clicked(cell: Vector2i) -> Dictionary:
	if busy:
		return {ok = false, reason = "busy"}
	if vs_ai and model != null and model.current_team == MatchRules.Team.AWAY:
		return {ok = false, reason = "ai_planning"}
	if not MatchRules.in_bounds(cell):
		_deselect()
		return {ok = false, reason = "out_of_bounds"}

	if not _pending_choice.is_empty():
		var same_cell: bool = cell == _pending_choice.get("cell", Vector2i(-99, -99))
		_cancel_choice()
		if same_cell:
			return {ok = true, action = "choose_cancel"}

	var selected := _selected_player()
	if selected != null and _pending_action != "":
		var command := model.action_for_command(selected, _pending_action, cell)
		if not command.is_empty():
			return perform_action(command)

	var occupant := _occupant_for_click(cell)
	if selected != null and _is_selected_cell(selected, cell):
		if _pending_action != "":
			_cancel_command()
			return {ok = true, action = "command_cancel"}
		if not model.plan_of(selected.id).is_empty():
			model.clear_plan(selected.id)
			_deselect()
			return {ok = true, action = "clear_plan", player_id = selected.id}
		_deselect()
		return {ok = true, action = "deselect"}
	if selected != null and _pending_action != "":
		if occupant != null and model.can_select(occupant) and occupant.id != selected.id:
			_select(occupant)
			return {ok = true, action = "select", player_id = occupant.id}
		return {ok = false, reason = "not_a_target"}

	if occupant != null and model.can_select(occupant):
		_select(occupant)
		return {ok = true, action = "select", player_id = occupant.id}

	_deselect()
	return {ok = false, reason = "no_selection"}


func handle_cell_right_clicked(cell: Vector2i) -> Dictionary:
	if busy:
		return {ok = false, reason = "busy"}
	if vs_ai and model != null and model.current_team == MatchRules.Team.AWAY:
		return {ok = false, reason = "ai_planning"}
	if not _pending_choice.is_empty():
		_cancel_choice()
	var selected := _selected_player()
	if selected != null and MatchRules.in_bounds(cell):
		var command := model.action_for_command(selected, "turn", cell)
		if not command.is_empty():
			return perform_action(command)
	if not _cancel_command():
		_deselect()
	return {ok = true, action = "cancel"}


func _is_selected_cell(selected: PlayerState, cell: Vector2i) -> bool:
	return selected != null and cell == model.planning_pos(selected)


func _occupant_for_click(cell: Vector2i) -> PlayerState:
	var live := model.player_at(cell)
	if live != null:
		var previewed := model.planning_pos(live)
		if live.team == model.current_team and previewed != live.pos and previewed != cell:
			live = null
		else:
			return live
	for player in model.players:
		if player.team != model.current_team:
			continue
		if model.planning_pos(player) == cell:
			return player
	return null


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
	if not _pending_choice.is_empty():
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
	return select_command(action_id)


func select_command(action_id: String) -> Dictionary:
	var selected := _selected_player()
	if selected == null:
		return {ok = false, reason = "no_selection"}
	if action_id == "done":
		return perform_action({
			id = "done",
			label = "Done",
			dest = model.planning_pos(selected),
		})
	var dests := model.command_dests(selected, action_id)
	if dests.is_empty():
		return {ok = false, reason = "no_targets"}
	_pending_action = action_id
	_refresh()
	return {ok = true, action = "command", command = action_id, dests = dests}


func _input(event: InputEvent) -> void:
	if busy or get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		end_planning()
		get_viewport().set_input_as_handled()


func _is_end_turn_key(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	return (
		event.keycode == KEY_ENTER
		or event.keycode == KEY_KP_ENTER
		or event.keycode == KEY_SPACE
	)


func _is_undo_key(event: InputEvent) -> bool:
	return (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_BACKSPACE
	)


func undo_last_action() -> Dictionary:
	if busy:
		return {ok = false, reason = "busy"}
	if vs_ai and model != null and model.current_team == MatchRules.Team.AWAY:
		return {ok = false, reason = "ai_planning"}
	_cancel_choice()
	var player_id := selected_id
	if player_id < 0 or model.plans_of(player_id).is_empty():
		player_id = -1
	var result := model.pop_last_plan(player_id)
	if not result.ok:
		return result
	hud.last_event = result
	var actor := model.player_by_id(int(result.get("player_id", -1)))
	if actor != null:
		_select(actor)
	else:
		_deselect()
	return result


func _try_command_hotkey(keycode: int) -> void:
	var index := -1
	if keycode >= KEY_1 and keycode <= KEY_9:
		index = keycode - KEY_1
	elif keycode >= KEY_KP_1 and keycode <= KEY_KP_9:
		index = keycode - KEY_KP_1
	if index < 0:
		return
	var selected := _selected_player()
	if selected == null:
		return
	var commands := model.commands_for(selected)
	if index >= commands.size():
		return
	select_command(str(commands[index].get("id", "")))


func _cancel_choice() -> void:
	_pending_choice = {}
	hud.hide_choices()


func _cancel_command() -> bool:
	if _pending_action == "":
		return false
	_pending_action = ""
	_refresh()
	return true


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
	if not model.can_queue(selected):
		_deselect()
	else:
		_arm_move(selected)
		_refresh()
	if model.planning_complete() and not settings.require_end_turn:
		return end_planning()
	return result


func end_planning() -> Dictionary:
	if busy:
		return {ok = false, reason = "busy"}
	_cancel_choice()
	var snapshot := _snapshot_visual_board()
	var result := model.end_planning()
	if not result.ok:
		return result
	if vs_ai and str(result.get("action", "")) == "end_planning":
		if model.current_team == MatchRules.Team.AWAY:
			if model.plan_count() == 0:
				_preplan_ai()
				model.current_team = MatchRules.Team.AWAY
			result = model.end_planning()
			if not result.ok:
				return result
	hud.last_event = result
	if str(result.get("action", "")) == "resolve":
		_cycle_snapshot = snapshot
		return _finish_resolve(result)
	_deselect()
	return result


func _snapshot_visual_board() -> Dictionary:
	var pos := {}
	var facing := {}
	for player in model.players:
		pos[player.id] = player.pos
		facing[player.id] = player.facing
	var holder := model.carrier()
	return {
		pos = pos,
		facing = facing,
		ball_pos = model.ball.pos,
		carrier_id = model.ball.carrier_id,
		carrier_team = holder.team if holder != null else 0,
	}


func _restore_visual_board(snap: Dictionary) -> void:
	if snap.is_empty():
		return
	var pos: Dictionary = snap.get("pos", {})
	var facing: Dictionary = snap.get("facing", {})
	for id in pieces:
		var piece: PlayerPiece = pieces[id]
		if piece == null:
			continue
		if pos.has(id):
			piece.position = pitch.grid_to_world(pos[id])
		if facing.has(id):
			piece.set_facing(facing[id])
	var carrier_id := int(snap.get("carrier_id", -1))
	pitch.ball_piece.set_carried(carrier_id >= 0)
	var ball_pos := pitch.grid_to_world(snap.get("ball_pos", Vector2i.ZERO))
	if carrier_id >= 0:
		ball_pos += pitch.carried_ball_offset(int(snap.get("carrier_team", 0)))
	pitch.ball_piece.position = ball_pos


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
	_restore_visual_board(_cycle_snapshot)
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
	if action == "cancelled" or action == "queue" or action == "end_planning" or action == "done":
		return await _anim_wait(0.08)
	if action == "clash":
		return await _anim_wait(0.18)
	var piece: PlayerPiece = pieces.get(result.get("player_id", -1))
	if piece == null:
		return true
	var dest: Vector2i = result.dest
	var won: bool = result.get("contest_won", true)
	if action == "shoot" and not result.get("intercepted", false):
		pitch.ball_piece.set_carried(false)
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(pitch.ball_piece, "position", pitch.grid_to_world(dest), _anim(0.28))
		return await _wait_for_tween(tween)
	if action == "pass" or result.get("intercepted", false):
		var receiver := model.player_by_id(int(result.get("receiver_id", -1)))
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.set_parallel(true)
		if result.get("intercepted", false) and receiver != null:
			var interceptor_piece: PlayerPiece = pieces.get(receiver.id)
			if interceptor_piece != null:
				var from_tile: Vector2i = result.get("interceptor_from", dest)
				interceptor_piece.set_facing(MatchRules.step_direction(from_tile, dest))
				tween.tween_property(interceptor_piece, "position", pitch.grid_to_world(dest), _anim(0.22))
		var ball_target := _pass_ball_target(result, dest, receiver)
		pitch.ball_piece.set_carried(receiver != null)
		tween.tween_property(pitch.ball_piece, "position", ball_target, _anim(0.22))
		return await _wait_for_tween(tween)
	if action == "turn":
		var origin: Vector2i = result.get("origin", dest)
		piece.set_facing(MatchRules.step_direction(origin, dest))
		return await _anim_wait(0.12)
	if action == "move" or action == "offside" or won:
		var origin: Vector2i = result.get("origin", dest)
		var face: Vector2i = result.get("facing", MatchRules.step_direction(origin, dest))
		piece.set_facing(face)
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.set_parallel(true)
		tween.tween_property(piece, "position", pitch.grid_to_world(dest), _anim(0.2))
		var displaced_id: int = result.get("displaced_id", -1)
		if displaced_id >= 0:
			var other: PlayerPiece = pieces.get(displaced_id)
			if other != null:
				other.set_facing(MatchRules.step_direction(dest, origin))
				tween.tween_property(other, "position", pitch.grid_to_world(origin), _anim(0.2))
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
	if result.get("bounced", false):
		var cell: Vector2i = result.get("bounce_cell", dest)
		var occupant := model.player_at(cell)
		if occupant != null and occupant.has_ball:
			return pitch.grid_to_world(cell) + pitch.carried_ball_offset(occupant.team)
		return pitch.grid_to_world(cell)
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
	_arm_move(player)
	_refresh()


func _arm_move(player: PlayerState) -> void:
	_pending_action = ""
	if player != null and not model.command_dests(player, "move").is_empty():
		_pending_action = "move"


func _deselect() -> void:
	_cancel_choice()
	_pending_action = ""
	selected_id = -1
	_refresh()


func _selected_player() -> PlayerState:
	if selected_id < 0:
		return null
	return model.player_by_id(selected_id)


func _sync_ball_visual() -> void:
	if busy:
		pitch.sync_ball(model.ball, model.carrier())
		return
	var holder := model.planning_carrier()
	if holder != null:
		var cell := model.planning_pos(holder) if holder.team == model.current_team else holder.pos
		pitch.ball_piece.set_carried(true)
		pitch.ball_piece.position = pitch.grid_to_world(cell) + pitch.carried_ball_offset(holder.team)
		pitch.ball_piece.z_index = 8
		return
	pitch.sync_ball(model.ball, null)


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
	hud.refresh(model, _selected_player(), _hovered_player(), hover_cell, _pending_action)


func _update_pass_preview(selected: PlayerState) -> void:
	if selected == null or not model.planning_has_ball(selected):
		pitch.clear_pass_preview()
		return
	var dest := hover_cell
	if _pending_action == "pass":
		if not model.can_plan_pass_to_cell(selected, dest):
			pitch.clear_pass_preview()
			return
	elif _pending_action == "shoot":
		dest = MatchRules.opponent_goal(selected.team)
		if hover_cell != dest or not model.can_plan_shoot(selected):
			pitch.clear_pass_preview()
			return
	else:
		pitch.clear_pass_preview()
		return
	var threats := model.interceptors_for_pass(selected, dest)
	var cells: Array[Vector2i] = []
	for threat in threats:
		cells.append(threat.player.pos)
	pitch.set_pass_preview(model.planning_pos(selected), dest, cells)


func _hovered_player() -> PlayerState:
	if not MatchRules.in_bounds(hover_cell):
		return null
	return _occupant_for_click(hover_cell)


func _refresh() -> void:
	var selected := _selected_player()
	var moves: Array[Vector2i] = []
	var contests: Array[Vector2i] = []
	var passes: Array[Vector2i] = []
	var choices: Array[Vector2i] = []
	var shots: Array[Vector2i] = []
	var offsides: Array[Vector2i] = []
	var turns: Array[Vector2i] = []
	if selected != null and _pending_action != "":
		var dests := model.command_dests(selected, _pending_action)
		match _pending_action:
			"move":
				moves = dests
			"turn":
				turns = dests
			"pass":
				offsides = model.offside_pass_cells(selected)
				for cell in dests:
					if cell not in offsides:
						passes.append(cell)
			"dribble", "tackle", "challenge":
				contests = dests
			"swap":
				choices = dests
			"shoot":
				shots = dests
		pitch.set_highlights(
			model.planning_pos(selected), moves, contests, passes, choices, shots, offsides, turns
		)
	elif selected != null:
		pitch.set_highlights(model.planning_pos(selected), [], [], [], [], [], [], [])
	else:
		pitch.clear_highlights()
	_update_pass_preview(selected)
	pitch.set_plans(_plan_markers())

	for state in model.players:
		var piece: PlayerPiece = pieces.get(state.id)
		if piece == null:
			continue
		var preview := not busy and state.team == model.current_team
		var cell := model.planning_pos(state) if preview else state.pos
		var face := model.planning_facing(state) if preview else state.facing
		piece.position = pitch.grid_to_world(cell)
		piece.set_selected(selected != null and state.id == selected.id)
		piece.set_has_ball(model.planning_has_ball(state) if preview else state.has_ball)
		var planned := (
			state.team == model.current_team
			and not model.plan_of(state.id).is_empty()
		)
		piece.set_planned(planned)
		piece.set_energy_ratio(state.energy_ratio())
		piece.set_facing(face)
		piece.set_on_turn(state.team == model.current_team and (planned or model.can_select(state)))
		if preview:
			var remaining := model.ap_remaining(state.id)
			if remaining < MatchRules.PLAYER_ACTION_POINTS:
				piece.set_ap_left(remaining)
			else:
				piece.set_ap_left(-1)
			piece.set_finished(model.player_is_done(state.id))
		else:
			piece.set_ap_left(-1)
			piece.set_finished(false)
		piece.z_index = 5 if piece.selected else 3

	_sync_ball_visual()
	hud.refresh(model, selected, _hovered_player(), hover_cell, _pending_action)


func _plan_markers() -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	for plan in model.plans_for(model.current_team):
		markers.append(plan)
	return markers
