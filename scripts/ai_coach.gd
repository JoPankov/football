class_name AiCoach
extends RefCounted

## Greedy Helix planner. Queues up to 3 players × 6 AP on the current board.
## Call only while model.current_team is the side to fill.

const _MIN_KEEP := 0.4


static func fill_plans(model: MatchModel) -> void:
	var coach := AiCoach.new()
	coach._fill(model)


func _fill(model: MatchModel) -> void:
	var claimed: Dictionary = {}
	for plan in model.plans_for(model.current_team):
		claimed[plan.get("dest", Vector2i.ZERO)] = true
	while not model.planning_complete():
		var best := _best_action(model, claimed)
		if best.is_empty():
			if not _mark_done(model):
				break
			continue
		var queued: Dictionary = model.queue_plan(int(best.player_id), best.action)
		if not queued.get("ok", false):
			break
		claimed[best.action.get("dest", Vector2i.ZERO)] = true


func _mark_done(model: MatchModel) -> bool:
	for player in model.players:
		if not model.can_queue(player):
			continue
		var queued := model.queue_plan(player.id, {
			id = "done",
			label = "Done",
			dest = model.planning_pos(player),
		})
		return bool(queued.get("ok", false))
	return false


func _best_action(model: MatchModel, claimed: Dictionary) -> Dictionary:
	var best := {}
	var best_score := _MIN_KEEP
	if model.plan_count() == 0:
		best_score = -1000.0
	for player in model.players:
		if not model.can_select(player) or not model.can_queue(player):
			continue
		for dest in _dests_for(model, player):
			for action in model.actions_for(player, dest):
				var score := _score(model, player, action, claimed)
				if score > best_score:
					best_score = score
					best = {player_id = player.id, action = action, score = score}
	return best


func _dests_for(model: MatchModel, player: PlayerState) -> Array[Vector2i]:
	var seen := {}
	var dests: Array[Vector2i] = []
	for cell in model.valid_moves(player):
		if not seen.has(cell):
			seen[cell] = true
			dests.append(cell)
	for cell in model.valid_sprints(player):
		if not seen.has(cell):
			seen[cell] = true
			dests.append(cell)
	for cell in model.turn_dests(player):
		if not seen.has(cell):
			seen[cell] = true
			dests.append(cell)
	for cell in model.pass_cells(player):
		if not seen.has(cell):
			seen[cell] = true
			dests.append(cell)
	for cell in model.shoot_cells(player):
		if not seen.has(cell):
			seen[cell] = true
			dests.append(cell)
	return dests


func _score(model: MatchModel, player: PlayerState, action: Dictionary, claimed: Dictionary) -> float:
	var kind := str(action.get("id", ""))
	var dest: Vector2i = action.get("dest", player.pos)
	var clash := 18.0 if claimed.has(dest) and kind in ["move", "sprint", "dribble", "tackle", "challenge"] else 0.0
	var energy := 0.7 + 0.3 * player.energy_ratio()
	var value := 0.0
	match kind:
		"shoot":
			value = 1000.0 * float(model.shot_preview(player).goal_chance)
		"pass":
			value = _score_pass(model, player, action, dest)
		"tackle":
			value = _score_contest(model, player, dest, 85.0, 12.0)
		"dribble":
			value = _score_contest(model, player, dest, 60.0, 8.0)
			value += 6.0 * _forward_gain(player.team, player.pos, dest)
		"challenge":
			value = _score_contest(model, player, dest, 10.0, 0.0)
		"swap":
			value = 1.5
		"move":
			value = _score_move(model, player, dest)
		"sprint":
			value = _score_move(model, player, dest) * 1.15
		"turn":
			value = _score_turn(model, player, dest)
		_:
			value = 0.0
	return value * energy - clash


func _score_pass(model: MatchModel, player: PlayerState, action: Dictionary, dest: Vector2i) -> float:
	var preview := model.pass_preview(player, dest)
	var through := float(preview.get("total", 1.0))
	var gain := _forward_gain(player.team, player.pos, dest)
	var value := 42.0 * through * (1.0 + maxf(gain, 0.0) * 0.4)
	if bool(action.get("offside", false)) or bool(preview.get("offside", false)):
		value -= 90.0
	elif not preview.get("marked_ids", []).is_empty() and int(action.get("target_id", -1)) < 0:
		value -= 8.0
	if through < 0.28:
		value *= 0.35
	return value


func _score_contest(model: MatchModel, player: PlayerState, dest: Vector2i, win_w: float, bonus: float) -> float:
	var occupant := model.player_at(dest)
	if occupant == null:
		return 0.0
	var preview := MatchRules.contest_preview(
		player, occupant, model.planning_has_ball(player), _possession_team(model)
	)
	return win_w * float(preview.chance) + bonus


func _score_move(model: MatchModel, player: PlayerState, dest: Vector2i) -> float:
	var team := player.team
	if model.planning_has_ball(player) and dest == MatchRules.opponent_goal(team):
		return 900.0
	var value := 5.0 * _forward_gain(team, player.pos, dest)
	if model.planning_has_ball(player):
		value += 18.0 * _forward_gain(team, player.pos, dest)
	else:
		var ball_pos := model.ball.pos
		var closer := (
			MatchRules.chebyshev(player.pos, ball_pos) - MatchRules.chebyshev(dest, ball_pos)
		)
		value += 14.0 * float(closer)
		if model.ball.is_loose() and dest == ball_pos and not model.would_collect_offside(player, dest):
			value += 40.0
	if model.would_collect_offside(player, dest):
		value -= 90.0
	var own_net := MatchRules.HOME_NET if team == MatchRules.Team.HOME else MatchRules.AWAY_NET
	var holder := model.carrier()
	if holder != null and holder.team != team and _is_back(player):
		var cover := (
			MatchRules.chebyshev(player.pos, own_net) - MatchRules.chebyshev(dest, own_net)
		)
		value += 8.0 * float(cover)
	return value


func _score_turn(model: MatchModel, player: PlayerState, dest: Vector2i) -> float:
	var from := model.planning_pos(player)
	var new_face := MatchRules.step_direction(from, dest)
	if new_face == Vector2i.ZERO:
		return 0.0
	return 3.5 * _forward_gain(player.team, from, from + new_face)


func _forward_gain(team: int, from: Vector2i, to: Vector2i) -> float:
	if team == MatchRules.Team.HOME:
		return float(to.x - from.x)
	return float(from.x - to.x)


func _possession_team(model: MatchModel) -> int:
	var holder := model.planning_carrier()
	if holder == null:
		return -1
	return holder.team


func _is_back(player: PlayerState) -> bool:
	return player.role in ["GK", "LB", "RB", "LCB", "RCB"]
