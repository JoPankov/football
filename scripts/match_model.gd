class_name MatchModel
extends RefCounted

const _CombatLog := preload("res://scripts/combat_log.gd")
const _TurnResolver := preload("res://scripts/turn_resolver.gd")

## Authoritative match state. No nodes, no visuals.

var current_team: int = MatchRules.Team.HOME
## False until the side that plans first this cycle has locked in.
var awaiting_other_side: bool = false
var turn_index: int = 0
var home_score: int = 0
var away_score: int = 0
var players: Array[PlayerState] = []
var ball: BallState = BallState.new()
var rng := RandomNumberGenerator.new()
var home_plans: Array[Dictionary] = []
var away_plans: Array[Dictionary] = []
var combat_log := _CombatLog.new()
## Resolver sets this so Helix actions can apply during a simultaneous resolve.
var ignore_team_gate: bool = false
## null = roll; true = attacker wins; false = occupant wins. Tests use this.
var scripted_attacker_wins = null
## null = roll; true = force a numeric tie (dribble/tackle bounce). Tests use this.
var scripted_contest_tie = null
## null = random bounce cell; Vector2i = that cell. Tests use this.
var scripted_bounce_cell = null
## null = roll; true = first interceptor wins the ball; false = passer beats every interceptor.
var scripted_first_intercept_wins = null
## null = roll; "goal", "save", or "miss".
var scripted_shot_outcome = null
## Teammate ids in an offside position at the last pass. Cleared when anyone
## else plays the ball, or when a marked player is flagged.
var offside_marked_ids: Array[int] = []
var offside_passer_id: int = -1


func setup_kickoff(kicking_team: int = MatchRules.Team.HOME) -> void:
	players.clear()
	_clear_offside_marks()
	var next_id := 0
	for team in [MatchRules.Team.HOME, MatchRules.Team.AWAY]:
		for slot in Formation.slots(team, kicking_team):
			var player := PlayerState.new(
				next_id,
				team,
				slot.number,
				slot.role,
				slot.pos
			)
			player.apply_stats(slot)
			players.append(player)
			next_id += 1
	ball = BallState.new()
	home_plans.clear()
	away_plans.clear()
	current_team = kicking_team
	awaiting_other_side = false
	turn_index = 0
	ignore_team_gate = false
	rng.randomize()
	combat_log.header("Kickoff — %s plans first." % MatchRules.team_name(kicking_team))
	var kicker := player_at(MatchRules.kickoff_spot(kicking_team))
	assert(kicker != null and kicker.team == kicking_team, "Kickoff taker missing.")
	_give_ball(kicker)
	assert(_positions_unique(), "Kickoff spawned two players on the same cell.")
	assert(not ball.is_loose(), "Kickoff must start with a team in possession.")
	for player in players:
		if player.team == kicking_team:
			continue
		assert(
			not MatchRules.in_centre_circle(player.pos),
			"Receiving player spawned inside the centre circle."
		)


func player_by_id(id: int) -> PlayerState:
	for player in players:
		if player.id == id:
			return player
	return null


func player_at(pos: Vector2i) -> PlayerState:
	for player in players:
		if player.pos == pos:
			return player
	return null


func carrier() -> PlayerState:
	if ball.is_loose():
		return null
	return player_by_id(ball.carrier_id)


func occupied_cells(except_id: int = -1) -> Dictionary:
	var cells := {}
	for player in players:
		if player.id != except_id:
			cells[player.pos] = player.id
	return cells


func teammate_cells(except_id: int = -1) -> Dictionary:
	var cells := {}
	var except_player := player_by_id(except_id)
	for player in players:
		if player.id == except_id:
			continue
		if except_player != null and player.team != except_player.team:
			continue
		cells[player.pos] = player.id
	return cells


func valid_moves(player: PlayerState) -> Array[Vector2i]:
	if player == null:
		return []
	return MatchRules.move_destinations(
		_query_pos(player), teammate_cells(player.id), _query_facing(player)
	)


## Cells the player can still walk to by spending leftover AP on move steps.
## Facing only changes by stepping — turns are not inserted.
func move_reach(player: PlayerState) -> Dictionary:
	if player == null or not can_queue(player):
		return {}
	return MatchRules.move_reach(
		_query_pos(player),
		_query_facing(player),
		occupied_cells(player.id),
		ap_remaining(player.id)
	)


func move_path(player: PlayerState, dest: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var info = move_reach(player).get(dest, null)
	if typeof(info) != TYPE_DICTIONARY:
		return path
	for cell in info.get("path", []):
		path.append(cell)
	return path


## The empty cell two tiles straight ahead of facing. AP is checked by command_dests.
func valid_sprints(player: PlayerState) -> Array[Vector2i]:
	if player == null:
		return []
	return MatchRules.sprint_destinations(
		_query_pos(player),
		_query_facing(player),
		occupied_cells(player.id)
	)


func contest_moves(player: PlayerState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if player == null:
		return result
	for cell in valid_moves(player):
		var occupant := player_at(cell)
		if occupant != null and occupant.team != player.team:
			result.append(cell)
	return result


func can_select(player: PlayerState) -> bool:
	if player == null or player.team != current_team:
		return false
	if not plans_of(player.id).is_empty():
		return true
	return acting_player_count(current_team) < MatchRules.ACTIONS_PER_SIDE


func _acting_allowed(player: PlayerState) -> bool:
	return player != null and (ignore_team_gate or player.team == current_team)


func plans_for(team: int) -> Array[Dictionary]:
	return home_plans if team == MatchRules.Team.HOME else away_plans


func plan_count(team: int = -1) -> int:
	if team < 0:
		team = current_team
	return plans_for(team).size()


func plan_of(player_id: int) -> Dictionary:
	var plans := plans_of(player_id)
	if plans.is_empty():
		return {}
	return plans[0]


func plans_of(player_id: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for plan in home_plans:
		if int(plan.get("player_id", -1)) == player_id:
			found.append(plan)
	for plan in away_plans:
		if int(plan.get("player_id", -1)) == player_id:
			found.append(plan)
	return found


func acting_player_count(team: int = -1) -> int:
	if team < 0:
		team = current_team
	var ids := {}
	for plan in plans_for(team):
		ids[int(plan.get("player_id", -1))] = true
	return ids.size()


func ap_spent(player_id: int) -> int:
	var spent := 0
	for plan in plans_of(player_id):
		spent += int(plan.get("ap_cost", MatchRules.DEFAULT_ACTION_COST))
	return spent


func ap_remaining(player_id: int) -> int:
	return maxi(0, MatchRules.PLAYER_ACTION_POINTS - ap_spent(player_id))


func team_ap_spent(team: int = -1) -> int:
	if team < 0:
		team = current_team
	var spent := 0
	for plan in plans_for(team):
		spent += int(plan.get("ap_cost", MatchRules.DEFAULT_ACTION_COST))
	return spent


func action_cost_for(player: PlayerState, action_id: String, dest: Vector2i) -> int:
	if player == null:
		return MatchRules.PLAYER_ACTION_POINTS + 1
	return MatchRules.action_ap_cost(
		action_id,
		_query_pos(player),
		dest,
		ap_remaining(player.id),
		_query_facing(player)
	)


func can_afford(player: PlayerState, action_id: String, dest: Vector2i) -> bool:
	if player == null:
		return false
	return action_cost_for(player, action_id, dest) <= ap_remaining(player.id)


func _query_pos(player: PlayerState) -> Vector2i:
	if player == null:
		return Vector2i.ZERO
	if ignore_team_gate:
		return player.pos
	return planning_pos(player)


func _query_facing(player: PlayerState) -> Vector2i:
	if player == null:
		return Vector2i.ZERO
	if ignore_team_gate:
		return player.facing
	return planning_facing(player)


func planning_pos(player: PlayerState) -> Vector2i:
	if player == null:
		return Vector2i.ZERO
	var pos := player.pos
	for plan in plans_of(player.id):
		var act := str(plan.get("action", ""))
		if act in ["move", "sprint", "dribble", "tackle", "challenge", "swap"]:
			pos = plan.get("dest", pos)
	return pos


func planning_facing(player: PlayerState) -> Vector2i:
	if player == null:
		return Vector2i.ZERO
	var pos := player.pos
	var facing := player.facing
	for plan in plans_of(player.id):
		var dest: Vector2i = plan.get("dest", pos)
		var act := str(plan.get("action", ""))
		if act == "turn" or act in ["move", "sprint", "dribble", "tackle", "challenge", "swap"]:
			var dir := MatchRules.step_direction(pos, dest)
			if dir != Vector2i.ZERO:
				facing = dir
			if act != "turn":
				pos = dest
	return facing


func clear_plan(player_id: int) -> Dictionary:
	var plan := plan_of(player_id)
	if plan.is_empty():
		return {ok = false, reason = "no_plan"}
	var bucket := plans_for(int(plan.get("team", current_team)))
	for i in range(bucket.size() - 1, -1, -1):
		if int(bucket[i].get("player_id", -1)) == player_id:
			bucket.remove_at(i)
	var player := player_by_id(player_id)
	combat_log.note(
		"Cleared plan for %s." % (player.label() if player != null else "player"),
		int(plan.get("team", current_team))
	)
	return {ok = true, action = "clear_plan", player_id = player_id}


func pop_last_plan(player_id: int = -1) -> Dictionary:
	var target_id := player_id
	var bucket: Array[Dictionary] = plans_for(current_team)
	if target_id >= 0:
		var player := player_by_id(target_id)
		if player == null:
			return {ok = false, reason = "no_player"}
		if not ignore_team_gate and player.team != current_team:
			return {ok = false, reason = "wrong_team"}
		bucket = plans_for(player.team)
	var index := -1
	if target_id < 0:
		if bucket.is_empty():
			return {ok = false, reason = "no_plan"}
		index = bucket.size() - 1
	else:
		for i in range(bucket.size() - 1, -1, -1):
			if int(bucket[i].get("player_id", -1)) == target_id:
				index = i
				break
		if index < 0:
			return {ok = false, reason = "no_plan"}
	var plan: Dictionary = bucket[index]
	bucket.remove_at(index)
	target_id = int(plan.get("player_id", -1))
	var actor := player_by_id(target_id)
	combat_log.drop_last_queue(target_id)
	return {
		ok = true,
		action = "pop_plan",
		player_id = target_id,
		team = int(plan.get("team", current_team)),
		plan = plan,
		attacker_label = actor.label() if actor != null else "player",
		label = str(plan.get("label", plan.get("action", "action"))),
		plan_text = _CombatLog.plan_summary(plan),
		dest = plan.get("dest", Vector2i.ZERO),
	}


func player_is_done(player_id: int) -> bool:
	for plan in plans_of(player_id):
		if str(plan.get("action", "")) == "done":
			return true
	return false


func can_queue(player: PlayerState) -> bool:
	if not _acting_allowed(player):
		return false
	if player_is_done(player.id):
		return false
	var spent := ap_spent(player.id)
	if spent >= MatchRules.PLAYER_ACTION_POINTS:
		return false
	if spent > 0:
		return true
	return acting_player_count(player.team) < MatchRules.ACTIONS_PER_SIDE


func queue_plan(player_id: int, action: Dictionary) -> Dictionary:
	var player := player_by_id(player_id)
	if not can_queue(player):
		return {ok = false, reason = "cannot_queue"}
	var action_id := str(action.get("id", ""))
	if action_id == "":
		return {ok = false, reason = "no_action"}
	var dest: Vector2i = action.get("dest", _query_pos(player))
	var origin := _query_pos(player)
	if action_id == "move":
		var steps := move_path(player, dest)
		if steps.size() > 1:
			return _queue_move_steps(player_id, action, steps)
		if (
			steps.is_empty()
			and origin != dest
			and not MatchRules.is_adjacent(origin, dest)
		):
			return {ok = false, reason = "illegal_dest"}
	var remaining := ap_remaining(player_id)
	var cost := MatchRules.action_ap_cost(
		action_id, origin, dest, remaining, _query_facing(player)
	)
	if cost > remaining:
		return {ok = false, reason = "not_enough_ap"}
	var ap_index := plans_of(player_id).size()
	var ap_end := ap_spent(player_id) + cost
	var plan := {
		player_id = player_id,
		team = player.team,
		action = action_id,
		dest = dest,
		target_id = int(action.get("target_id", -1)),
		origin = origin,
		ap_index = ap_index,
		ap_cost = cost,
		ap_end = ap_end,
		ap_left = remaining,
		label = str(action.get("label", action_id)),
		expects_ball = (
			not player.has_ball
			and planning_has_ball(player)
			and action_id in ["pass", "shoot", "dribble"]
		),
		expects_reason = _expects_ball_reason(player),
	}
	plans_for(player.team).append(plan)
	var result := {
		ok = true,
		action = "queue",
		player_id = player_id,
		team = player.team,
		plan = plan,
		attacker_label = player.label(),
		label = plan.label,
		plan_text = _CombatLog.plan_summary(plan),
		dest = dest,
	}
	combat_log.event(result)
	return result


func _queue_move_steps(
	player_id: int, action: Dictionary, steps: Array[Vector2i]
) -> Dictionary:
	var last := {}
	for cell in steps:
		var step: Dictionary = action.duplicate()
		step.id = "move"
		step.dest = cell
		last = queue_plan(player_id, step)
		if not last.get("ok", false):
			return last
	return last


func can_end_planning() -> bool:
	return true


func planning_complete() -> bool:
	for player in players:
		if can_queue(player):
			return false
	return true


func end_planning() -> Dictionary:
	combat_log.note("%s locked in %d actions." % [
		MatchRules.team_name(current_team),
		plan_count(current_team),
	], current_team)
	if not awaiting_other_side:
		awaiting_other_side = true
		current_team = MatchRules.opposite_team(current_team)
		return {ok = true, action = "end_planning", next_team = current_team}
	return _TurnResolver.resolve(self)


func planning_carrier() -> PlayerState:
	var holder := carrier()
	if holder != null and holder.team != current_team:
		return holder
	if holder == null:
		holder = _legal_planning_collector(null, ball.pos)
	var seen := {}
	while holder != null:
		if seen.has(holder.id):
			return holder
		seen[holder.id] = true
		var next_holder: PlayerState = holder
		var handed_off := false
		for plan in plans_of(holder.id):
			var act := str(plan.get("action", ""))
			if act == "pass":
				var target_id := int(plan.get("target_id", -1))
				if target_id >= 0:
					var nxt := player_by_id(target_id)
					if nxt != null and nxt.team == holder.team:
						if is_offside_receiver(holder, nxt):
							return null
						next_holder = nxt
						handed_off = true
						break
				var dest: Vector2i = plan.get("dest", Vector2i.ZERO)
				var collector := _legal_planning_collector(holder, dest)
				if collector != null:
					next_holder = collector
					handed_off = true
					break
				return null
			if act == "shoot":
				return null
		if not handed_off:
			return holder
		holder = next_holder
	return holder


func _planning_collector_at(dest: Vector2i) -> PlayerState:
	for plan in plans_for(current_team):
		var act := str(plan.get("action", ""))
		var plan_dest: Vector2i = plan.get("dest", Vector2i.ZERO)
		if act == "move":
			if plan_dest != dest:
				continue
			return player_by_id(int(plan.get("player_id", -1)))
		if act != "sprint":
			continue
		if plan_dest == dest:
			return player_by_id(int(plan.get("player_id", -1)))
		var origin: Vector2i = plan.get("origin", Vector2i.ZERO)
		if MatchRules.sprint_through(origin, plan_dest) == dest:
			return player_by_id(int(plan.get("player_id", -1)))
	return null


## A queued step onto `dest` that would legally collect (not a marked first touch).
func _legal_planning_collector(passer: PlayerState, dest: Vector2i) -> PlayerState:
	var collector := _planning_collector_at(dest)
	if collector == null:
		return null
	if passer != null:
		if is_offside_receiver(passer, collector):
			return null
	elif is_offside_marked(collector):
		return null
	return collector


func _expects_ball_reason(player: PlayerState) -> String:
	var real := carrier()
	if real != null and real.team == player.team:
		return "pass did not arrive"
	return "did not get the ball"


func planning_has_ball(player: PlayerState) -> bool:
	if player == null:
		return false
	var holder := planning_carrier()
	return holder != null and holder.id == player.id


func can_pass_to(passer: PlayerState, target: PlayerState) -> bool:
	if passer == null or target == null:
		return false
	if target.team != passer.team or target.id == passer.id:
		return false
	return can_pass_to_cell(passer, target.pos)


func can_pass_to_cell(passer: PlayerState, dest: Vector2i) -> bool:
	if passer == null or not passer.has_ball:
		return false
	return _pass_geometry_ok(passer, dest)


func can_plan_pass_to(passer: PlayerState, target: PlayerState) -> bool:
	if passer == null or target == null:
		return false
	if target.team != passer.team or target.id == passer.id:
		return false
	return can_plan_pass_to_cell(passer, target.pos)


func can_plan_pass_to_cell(passer: PlayerState, dest: Vector2i) -> bool:
	if not planning_has_ball(passer):
		return false
	return _pass_geometry_ok(passer, dest)


func _pass_geometry_ok(passer: PlayerState, dest: Vector2i) -> bool:
	if not _acting_allowed(passer):
		return false
	var from := _query_pos(passer)
	if not MatchRules.in_bounds(dest) or dest == from:
		return false
	if not MatchRules.in_pass_range(from, dest):
		return false
	if MatchRules.is_back_pass(from, dest, _query_facing(passer)):
		return false
	var occupant := player_at(dest)
	if occupant == null:
		return not MatchRules.is_goal_tile(dest)
	return occupant.team == passer.team and occupant.id != passer.id


func pass_targets(passer: PlayerState) -> Array[PlayerState]:
	var result: Array[PlayerState] = []
	if passer == null or not planning_has_ball(passer):
		return result
	for player in players:
		if can_plan_pass_to(passer, player):
			result.append(player)
	return result


func pass_cells(passer: PlayerState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if passer == null or not planning_has_ball(passer):
		return cells
	for dest in _cells_in_range(_query_pos(passer), MatchRules.PASS_RANGE):
		if can_plan_pass_to_cell(passer, dest):
			cells.append(dest)
	return cells


func offside_pass_cells(passer: PlayerState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if passer == null:
		return cells
	for dest in pass_cells(passer):
		var occupant := player_at(dest)
		if occupant != null and is_offside_receiver(passer, occupant):
			cells.append(dest)
	for mate in offside_teammates(passer):
		if mate.pos not in cells:
			cells.append(mate.pos)
	return cells


func offside_teammates(passer: PlayerState) -> Array[PlayerState]:
	var result: Array[PlayerState] = []
	if passer == null:
		return result
	for player in players:
		if is_offside_receiver(passer, player):
			result.append(player)
	return result


func is_offside_marked(player: PlayerState) -> bool:
	return player != null and offside_marked_ids.has(player.id)


func offside_marked_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for id in offside_marked_ids:
		var player := player_by_id(id)
		if player != null:
			cells.append(player.pos)
	return cells


## True if this player collecting at `dest` (or sprinting through it) would be offside.
func would_collect_offside(player: PlayerState, dest: Vector2i) -> bool:
	if player == null:
		return false
	if _cell_is_offside_first_touch(player, dest):
		return true
	var from := _query_pos(player)
	if MatchRules.is_sprint_step(from, dest, _query_facing(player)):
		return _cell_is_offside_first_touch(player, MatchRules.sprint_through(from, dest))
	return false


func _cell_is_offside_first_touch(player: PlayerState, cell: Vector2i) -> bool:
	if is_offside_marked(player) and ball.is_loose() and ball.pos == cell:
		return true
	for plan in plans_for(current_team):
		if str(plan.get("action", "")) != "pass":
			continue
		if int(plan.get("target_id", -1)) >= 0:
			continue
		if plan.get("dest", Vector2i.ZERO) != cell:
			continue
		var passer := player_by_id(int(plan.get("player_id", -1)))
		if is_offside_receiver(passer, player):
			return true
	return false


func team_positions(team: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for player in players:
		if player.team == team:
			cells.append(player.pos)
	return cells


func is_offside_receiver(passer: PlayerState, receiver: PlayerState) -> bool:
	if passer == null or receiver == null:
		return false
	if receiver.team != passer.team or receiver.id == passer.id:
		return false
	return MatchRules.is_offside_position(
		receiver.team,
		receiver.pos,
		passer.pos,
		team_positions(MatchRules.opposite_team(receiver.team))
	)


func closest_player(team: int, dest: Vector2i) -> PlayerState:
	var best: PlayerState = null
	var best_dist := 999
	for player in players:
		if player.team != team:
			continue
		var dist := MatchRules.chebyshev(player.pos, dest)
		if best == null or dist < best_dist or (dist == best_dist and player.id < best.id):
			best = player
			best_dist = dist
	return best


func _cells_in_range(origin: Vector2i, reach: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(origin.x - reach, origin.x + reach + 1):
		for y in range(origin.y - reach, origin.y + reach + 1):
			var dest := Vector2i(x, y)
			if dest == origin or not MatchRules.in_bounds(dest):
				continue
			if MatchRules.tile_distance(origin, dest) <= float(reach) + 0.0001:
				cells.append(dest)
	return cells


func can_swap(player: PlayerState, teammate: PlayerState) -> bool:
	if player == null or teammate == null:
		return false
	if not _acting_allowed(player) or teammate.team != player.team:
		return false
	if teammate.id == player.id:
		return false
	var from := _query_pos(player)
	if not MatchRules.is_move_step(from, teammate.pos, _query_facing(player)):
		return false
	return MatchRules.is_adjacent(from, teammate.pos)


func actions_for(player: PlayerState, dest: Vector2i) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if not _acting_allowed(player):
		return actions
	if not MatchRules.in_bounds(dest):
		return actions
	if dest in turn_dests(player):
		actions.append({id = "turn", label = "Turn", dest = dest})
	var occupant := player_at(dest)
	if occupant == null:
		if dest in valid_moves(player):
			var move_offside := would_collect_offside(player, dest)
			actions.append({
				id = "move",
				label = "Move (offside)" if move_offside else "Move",
				dest = dest,
				offside = move_offside,
			})
		if dest in valid_sprints(player):
			var sprint_offside := would_collect_offside(player, dest)
			actions.append({
				id = "sprint",
				label = "Sprint (offside)" if sprint_offside else "Sprint",
				dest = dest,
				offside = sprint_offside,
			})
		if can_plan_pass_to_cell(player, dest):
			actions.append({id = "pass", label = "Pass", dest = dest, target_id = -1, offside = false})
	elif occupant.team != player.team:
		if dest in valid_moves(player):
			var preview := MatchRules.contest_preview(player, occupant, planning_has_ball(player))
			actions.append({
				id = preview.action,
				label = preview.verb.capitalize(),
				dest = dest,
			})
	else:
		if can_plan_pass_to(player, occupant):
			var pass_label := "Pass (offside)" if is_offside_receiver(player, occupant) else "Pass"
			actions.append({
				id = "pass",
				label = pass_label,
				target_id = occupant.id,
				dest = dest,
				offside = is_offside_receiver(player, occupant),
			})
		if can_swap(player, occupant):
			actions.append({id = "swap", label = "Swap places", target_id = occupant.id, dest = dest})
	if can_plan_shoot(player) and dest == MatchRules.opponent_goal(player.team):
		var leftover := ap_remaining(player.id)
		var bonus_pct := int(round(MatchRules.shot_ap_bonus(leftover) * 100.0))
		actions.append({id = "shoot", label = "Shoot +%d%%" % bonus_pct, dest = dest})
	var affordable: Array[Dictionary] = []
	for action in actions:
		if can_afford(player, str(action.get("id", "")), action.get("dest", dest)):
			affordable.append(action)
	return affordable


func commands_for(player: PlayerState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if player == null or not can_select(player) or not can_queue(player):
		return result
	for spec in [
		{id = "move", label = "Move"},
		{id = "sprint", label = "Sprint"},
		{id = "turn", label = "Turn"},
		{id = "pass", label = "Pass"},
		{id = "dribble", label = "Dribble"},
		{id = "tackle", label = "Tackle"},
		{id = "challenge", label = "Fight"},
		{id = "swap", label = "Swap"},
		{id = "shoot", label = "Shoot"},
	]:
		var dests := command_dests(player, str(spec.id))
		if dests.is_empty():
			continue
		var label := str(spec.label)
		if str(spec.id) == "shoot":
			var leftover := ap_remaining(player.id)
			var bonus_pct := int(round(MatchRules.shot_ap_bonus(leftover) * 100.0))
			label = "Shoot +%d%%" % bonus_pct
		result.append({id = spec.id, label = label, dests = dests})
	if ap_remaining(player.id) > 0:
		result.append({id = "done", label = "Done", dests = []})
	return result


func command_dests(player: PlayerState, command_id: String) -> Array[Vector2i]:
	var dests: Array[Vector2i] = []
	if player == null or not can_select(player) or not can_queue(player):
		return dests
	match command_id:
		"move":
			for cell in move_reach(player):
				dests.append(cell)
			return dests
		"sprint":
			dests = valid_sprints(player)
		"turn":
			dests = MatchRules.turn_destinations(_query_pos(player), _query_facing(player))
		"pass":
			dests = pass_cells(player)
		"dribble":
			if planning_has_ball(player):
				for cell in contest_moves(player):
					dests.append(cell)
		"tackle":
			if planning_has_ball(player):
				return dests
			var holder := planning_carrier()
			if (
				holder != null
				and holder.team != player.team
				and holder.pos in contest_moves(player)
			):
				dests.append(holder.pos)
		"challenge":
			if planning_has_ball(player):
				return dests
			var holder := planning_carrier()
			for cell in contest_moves(player):
				var occupant := player_at(cell)
				if occupant == null:
					continue
				if holder != null and occupant.id == holder.id:
					continue
				dests.append(cell)
		"swap":
			for other in players:
				if can_swap(player, other):
					dests.append(other.pos)
		"shoot":
			dests = shoot_cells(player)
	var affordable: Array[Vector2i] = []
	for cell in dests:
		if can_afford(player, command_id, cell):
			affordable.append(cell)
	return affordable


func action_for_command(player: PlayerState, command_id: String, dest: Vector2i) -> Dictionary:
	if dest not in command_dests(player, command_id):
		return {}
	if command_id == "turn":
		return {id = "turn", label = "Turn", dest = dest}
	if command_id == "move":
		var move_offside := would_collect_offside(player, dest)
		return {
			id = "move",
			label = "Move (offside)" if move_offside else "Move",
			dest = dest,
			offside = move_offside,
		}
	if command_id == "sprint":
		var sprint_offside := would_collect_offside(player, dest)
		return {
			id = "sprint",
			label = "Sprint (offside)" if sprint_offside else "Sprint",
			dest = dest,
			offside = sprint_offside,
		}
	for action in actions_for(player, dest):
		if str(action.get("id", "")) == command_id:
			return action
	return {}


func can_shoot(player: PlayerState, remaining_ap: int = -1) -> bool:
	if player == null or not player.has_ball or not _acting_allowed(player):
		return false
	return MatchRules.can_attempt_shot(
		player.pos,
		MatchRules.opponent_goal(player.team),
		player.live_accuracy(),
		_shot_remaining_ap(player, remaining_ap)
	)


func can_plan_shoot(player: PlayerState) -> bool:
	if player == null or not planning_has_ball(player) or not _acting_allowed(player):
		return false
	return MatchRules.can_attempt_shot(
		_query_pos(player),
		MatchRules.opponent_goal(player.team),
		player.live_accuracy(),
		_shot_remaining_ap(player)
	)


func _shot_remaining_ap(player: PlayerState, remaining_ap: int = -1) -> int:
	if remaining_ap >= 0:
		return remaining_ap
	if player == null or ignore_team_gate:
		return 0
	return ap_remaining(player.id)


func shoot_cells(player: PlayerState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if can_plan_shoot(player):
		cells.append(MatchRules.opponent_goal(player.team))
	return cells


func choice_cells(player: PlayerState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if player == null:
		return cells
	for dest in _cells_in_range(_query_pos(player), MatchRules.PASS_RANGE):
		if actions_for(player, dest).size() > 1:
			cells.append(dest)
	var goal := MatchRules.opponent_goal(player.team)
	if goal not in cells and actions_for(player, goal).size() > 1:
		cells.append(goal)
	return cells


func shot_preview(player: PlayerState, remaining_ap: int = -1) -> Dictionary:
	remaining_ap = _shot_remaining_ap(player, remaining_ap)
	var goal := MatchRules.opponent_goal(player.team)
	var geo := MatchRules.shot_geometry(_query_pos(player), goal)
	var acc := player.live_accuracy()
	var leftover_bonus := MatchRules.shot_ap_bonus(remaining_ap)
	var leftover_pct := int(round(leftover_bonus * 100.0))
	var sigma_deg := MatchRules.shot_sigma_deg(acc)
	var s := MatchRules.shot_sigma_rad(acc) * sqrt(2.0)
	var erf_w := MatchRules.erf_approx(0.5 * float(geo.theta_w) / s)
	var erf_h := MatchRules.erf_approx(0.5 * float(geo.theta_h) / s)
	var hit := MatchRules.shot_hit_chance(acc, geo.distance_m, geo.angle, remaining_ap)
	var keeper := player_at(goal)
	var keeper_in_net := keeper != null and keeper.team != player.team
	var save := 0.0
	if keeper_in_net:
		save = 1.0 - MatchRules.contest_win_chance(acc, keeper.live_defense(), true)
	var threats := interceptors_for_pass(player, goal)
	var through := 1.0
	for threat in threats:
		through *= float(threat.through)
	var through_pct := int(round(through * 100.0))
	var goal_p := through * hit * (1.0 - save)
	var lines: PackedStringArray = []
	lines.append("SHOOT at %s net" % MatchRules.team_name(MatchRules.opposite_team(player.team)))
	lines.append(
		"d = %.2f tiles (%.1f m)   θ = %.0f°" % [geo.distance, geo.distance_m, geo.angle_deg]
	)
	lines.append(
		"mouth = %.2f × %.2f m   θw = %.3f   θh = %.3f"
		% [MatchRules.SHOT_GOAL_W, MatchRules.SHOT_GOAL_H, geo.theta_w, geo.theta_h]
	)
	lines.append("σ = %.1f°  (ACC %d)" % [sigma_deg, acc])
	lines.append("leftover AP = %d  (+%d%% hit)" % [remaining_ap, leftover_pct])
	lines.append("hit = erf(θw / 2σ√2) × erf(θh / 2σ√2) + leftover")
	lines.append("    = %.2f × %.2f + %.2f = %d%%" % [
		erf_w,
		erf_h,
		leftover_bonus,
		int(round(hit * 100.0)),
	])
	if keeper_in_net:
		lines.append("save = P(keeper 1dDEF > ACC 1dACC) = %d%%" % int(round(save * 100.0)))
	else:
		lines.append("save = 0% (no keeper in the net)")
	if threats.is_empty():
		lines.append("through = 100% (no interceptors)")
	else:
		for threat in threats:
			lines.append(
				"%s: %d ACC vs %d DEF, %.1f tiles off = %d%% intercept (%d%% through)" % [
					threat.player.label(),
					acc,
					threat.player.live_defense(),
					float(threat.dist),
					threat.intercept_percent,
					threat.through_percent,
				]
			)
		lines.append("through = %d%%" % through_pct)
	lines.append("goal = through × hit × (1 − save) = %d%%" % int(round(goal_p * 100.0)))
	var header := "shoot  +%d%% AP  goal %d%%  (hit %d%%, save %d%%)" % [
		leftover_pct,
		int(round(goal_p * 100.0)),
		int(round(hit * 100.0)),
		int(round(save * 100.0)),
	]
	if not threats.is_empty():
		header = "shoot  +%d%% AP  goal %d%%  (hit %d%%, save %d%%, through %d%%)" % [
			leftover_pct,
			int(round(goal_p * 100.0)),
			int(round(hit * 100.0)),
			int(round(save * 100.0)),
			through_pct,
		]
	return {
		goal = goal,
		distance = geo.distance,
		distance_m = geo.distance_m,
		angle_deg = geo.angle_deg,
		theta_w = geo.theta_w,
		theta_h = geo.theta_h,
		sigma_deg = sigma_deg,
		hit_chance = hit,
		save_chance = save,
		goal_chance = goal_p,
		through = through,
		through_percent = through_pct,
		threats = threats,
		keeper_in_net = keeper_in_net,
		remaining_ap = remaining_ap,
		leftover_bonus = leftover_bonus,
		text = "\n".join(lines),
		header = header,
	}


func apply_swap(player_id: int, teammate_id: int) -> Dictionary:
	var player := player_by_id(player_id)
	var teammate := player_by_id(teammate_id)
	if not can_swap(player, teammate):
		return {ok = false, reason = "illegal_swap"}
	var origin := player.pos
	var dest := teammate.pos
	player.relocate(dest)
	teammate.relocate(origin)
	if player.has_ball:
		ball.pos = dest
	elif teammate.has_ball:
		ball.pos = origin
	var result := {
		ok = true,
		action = "swap",
		player_id = player_id,
		receiver_id = teammate_id,
		displaced_id = teammate_id,
		dest = dest,
		origin = origin,
		gained_possession = false,
		lost_possession = false,
		contest_won = true,
		ball_holder_id = (
			player.id if player.has_ball else (teammate.id if teammate.has_ball else -1)
		),
		attacker_label = player.label(),
		defender_label = teammate.label(),
	}
	player.spend_energy()
	return result


func turn_dests(player: PlayerState) -> Array[Vector2i]:
	if player == null:
		return []
	return MatchRules.turn_destinations(_query_pos(player), _query_facing(player))


func apply_turn(player_id: int, dest: Vector2i) -> Dictionary:
	var player := player_by_id(player_id)
	if player == null:
		return {ok = false, reason = "no_player"}
	if not _acting_allowed(player):
		return {ok = false, reason = "wrong_team"}
	if dest not in MatchRules.turn_destinations(player.pos, player.facing):
		return {ok = false, reason = "illegal_turn"}
	var origin := player.pos
	var dir := MatchRules.step_direction(origin, dest)
	if dir == Vector2i.ZERO:
		return {ok = false, reason = "illegal_turn"}
	player.facing = dir
	return _finish_action(player, {
		ok = true,
		action = "turn",
		player_id = player_id,
		dest = dest,
		origin = origin,
		facing = dir,
		attacker_label = player.label(),
		contest_won = true,
	})


## Opponents whose intercept circle touches passer→dest. Shots reuse this with dest = opponent net.
## The occupant of dest never intercepts (pass receiver, or the keeper standing in the net).
func interceptors_for_pass(passer: PlayerState, dest: Vector2i) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if passer == null:
		return found
	var start := MatchRules.tile_center(_query_pos(passer))
	var finish := MatchRules.tile_center(dest)
	var receiver := player_at(dest)
	for player in players:
		if player.id == passer.id:
			continue
		if receiver != null and player.id == receiver.id:
			continue
		if player.team == passer.team:
			continue
		var hit := MatchRules.segment_intersects_circle(
			start, finish, MatchRules.tile_center(player.pos), MatchRules.INTERCEPT_RADIUS
		)
		if not hit.hits:
			continue
		var dist := float(hit.dist)
		var through := MatchRules.intercept_through_chance(
			passer.live_accuracy(), player.live_defense(), dist
		)
		found.append({
			player = player,
			player_id = player.id,
			t = hit.t,
			dist = dist,
			reach = MatchRules.intercept_reach_factor(dist),
			closest = hit.closest,
			through = through,
			through_percent = int(round(through * 100.0)),
			intercept_percent = int(round((1.0 - through) * 100.0)),
		})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)
	return found


func pass_preview(passer: PlayerState, dest: Vector2i) -> Dictionary:
	var threats := interceptors_for_pass(passer, dest)
	var total := 1.0
	var lines: PackedStringArray = []
	for threat in threats:
		total *= float(threat.through)
		lines.append(
			"%s: %d ACC vs %d DEF, %.1f tiles off = %d%% intercept (%d%% through)" % [
				threat.player.label(),
				passer.live_accuracy(),
				threat.player.live_defense(),
				float(threat.dist),
				threat.intercept_percent,
				threat.through_percent,
			]
		)
	var total_pct := int(round(total * 100.0))
	var occupant := player_at(dest)
	var target_name := occupant.label() if occupant != null else "open square"
	var dist := MatchRules.tile_distance(passer.pos, dest)
	var marked := offside_teammates(passer)
	var offside := occupant != null and is_offside_receiver(passer, occupant)
	var taker: PlayerState = null
	if offside:
		taker = closest_player(MatchRules.opposite_team(passer.team), dest)
	var dist_txt := str(int(round(dist))) if is_equal_approx(dist, round(dist)) else ("%.1f" % dist)
	var unit := "tile" if is_equal_approx(dist, 1.0) else "tiles"
	var header := "pass to %s (%s %s)" % [target_name, dist_txt, unit]
	if offside:
		header = "OFFSIDE pass to %s (%s %s)" % [target_name, dist_txt, unit]
	if offside and taker != null:
		lines.append(
			"If it arrives: offside. %s takes the tile and the ball." % taker.label()
		)
	var offside_note := ""
	if not offside and not marked.is_empty():
		offside_note = "Offside if %s is first to the ball." % _offside_name_list(marked)
		lines.append(offside_note)
	var body := "\n".join(lines)
	var footer := "Pass success: %d%%" % total_pct
	if threats.is_empty():
		footer = "No interceptors. Pass success: 100%"
	if offside and threats.is_empty():
		footer = "No interceptors. Offside if played."
	elif offside:
		footer += "  Offside if it arrives."
	elif offside_note != "" and threats.is_empty():
		footer = "No interceptors. %s" % offside_note
	elif offside_note != "":
		footer += "  %s" % offside_note
	var text := header + "\n" + (body + "\n" if body != "" else "") + footer
	var marked_ids: Array[int] = []
	for mate in marked:
		marked_ids.append(mate.id)
	return {
		threats = threats,
		total = total,
		total_percent = total_pct,
		header = header,
		text = text,
		offside = offside,
		offside_note = offside_note,
		marked_ids = marked_ids,
		taker_id = taker.id if taker != null else -1,
	}


func apply_pass(from_id: int, to_id: int) -> Dictionary:
	var target := player_by_id(to_id)
	if target == null:
		return {ok = false, reason = "illegal_pass"}
	return apply_pass_to(from_id, target.pos)


func apply_pass_to(from_id: int, dest: Vector2i) -> Dictionary:
	var passer := player_by_id(from_id)
	if not can_pass_to_cell(passer, dest):
		return {ok = false, reason = "illegal_pass"}
	var origin := passer.pos
	var intercept := _resolve_pass_intercepts(passer, dest)
	if intercept.get("intercepted", false):
		var thief: PlayerState = intercept.player
		var landing: Vector2i = intercept.landing
		var from_tile := thief.pos
		thief.relocate(landing)
		_give_ball(thief)
		return _finish_action(passer, {
			ok = true,
			action = "pass",
			intercepted = true,
			player_id = from_id,
			receiver_id = thief.id,
			interceptor_id = thief.id,
			dest = landing,
			interceptor_from = from_tile,
			origin = origin,
			gained_possession = false,
			lost_possession = true,
			attacker_label = passer.label(),
			defender_label = thief.label(),
			attacker_stat_name = "ACC",
			defender_stat_name = "DEF",
			attacker_stat = passer.live_accuracy(),
			defender_stat = thief.live_defense(),
			attacker_dice = intercept.attacker_dice,
			defender_dice = intercept.defender_dice,
			attacker_total = intercept.attacker_total,
			defender_total = intercept.defender_total,
		})

	_mark_offside_from_pass(passer)
	var occupant := player_at(dest)
	if occupant != null and is_offside_marked(occupant):
		return _finish_action(passer, _apply_offside(passer, occupant))

	var receiver_id := -1
	var receiver_label := "open square"
	if occupant != null:
		_give_ball(occupant)
		receiver_id = occupant.id
		receiver_label = occupant.label()
	else:
		_release_ball(dest)
	return _finish_action(passer, {
		ok = true,
		action = "pass",
		intercepted = false,
		player_id = from_id,
		receiver_id = receiver_id,
		dest = dest,
		origin = origin,
		gained_possession = false,
		lost_possession = occupant == null,
		attacker_label = passer.label(),
		defender_label = receiver_label,
	})


func _resolve_pass_intercepts(passer: PlayerState, dest: Vector2i) -> Dictionary:
	var threats := interceptors_for_pass(passer, dest)
	if threats.is_empty():
		return {intercepted = false}
	if scripted_first_intercept_wins != null:
		if bool(scripted_first_intercept_wins):
			var first: Dictionary = threats[0]
			return {
				intercepted = true,
				player = first.player,
				landing = _intercept_landing(first.player, first.closest),
				attacker_dice = 1,
				defender_dice = maxi(first.player.live_defense(), 2),
				attacker_total = 1,
				defender_total = maxi(first.player.live_defense(), 2),
			}
		return {intercepted = false}
	for threat in threats:
		var roll := MatchRules.resolve_contest(
			passer.live_accuracy(),
			threat.player.live_defense(),
			rng,
			true
		)
		if not roll.attacker_won:
			var reach := MatchRules.intercept_reach_factor(float(threat.dist))
			if rng.randf() >= reach:
				continue
			return {
				intercepted = true,
				player = threat.player,
				landing = _intercept_landing(threat.player, threat.closest),
				attacker_dice = roll.attacker_dice,
				defender_dice = roll.defender_dice,
				attacker_total = roll.attacker_total,
				defender_total = roll.defender_total,
			}
	return {intercepted = false}


func _intercept_landing(interceptor: PlayerState, closest: Vector2) -> Vector2i:
	var snapped := MatchRules.nearest_tile(closest)
	if _can_land_intercept(interceptor, snapped):
		return snapped
	var best := interceptor.pos
	var best_dist := MatchRules.tile_center(best).distance_to(closest)
	for radius in range(1, 4):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var cell := snapped + Vector2i(dx, dy)
				if not _can_land_intercept(interceptor, cell):
					continue
				var dist := MatchRules.tile_center(cell).distance_to(closest)
				if dist < best_dist:
					best = cell
					best_dist = dist
	return best


func _can_land_intercept(interceptor: PlayerState, cell: Vector2i) -> bool:
	if not MatchRules.in_bounds(cell):
		return false
	var occupant := player_at(cell)
	return occupant == null or occupant.id == interceptor.id


func _apply_offside(passer: PlayerState, receiver: PlayerState) -> Dictionary:
	if receiver == null:
		return {ok = false, reason = "no_taker"}
	var dest := receiver.pos
	var attacking := passer.team if passer != null else receiver.team
	var taker := closest_player(MatchRules.opposite_team(attacking), dest)
	if taker == null:
		return {ok = false, reason = "no_taker"}
	var origin := taker.pos
	taker.relocate(dest)
	receiver.relocate(origin)
	_give_ball(taker)
	return {
		ok = true,
		action = "offside",
		player_id = taker.id,
		receiver_id = taker.id,
		displaced_id = receiver.id,
		dest = dest,
		origin = origin,
		gained_possession = true,
		lost_possession = true,
		contest_won = true,
		attacker_label = passer.label() if passer != null else "passer",
		defender_label = receiver.label(),
		taker_label = taker.label(),
	}


func _mark_offside_from_pass(passer: PlayerState) -> void:
	offside_marked_ids.clear()
	offside_passer_id = -1
	if passer == null:
		return
	for player in offside_teammates(passer):
		offside_marked_ids.append(player.id)
	if not offside_marked_ids.is_empty():
		offside_passer_id = passer.id


func _clear_offside_marks() -> void:
	offside_marked_ids.clear()
	offside_passer_id = -1


func _offside_passer() -> PlayerState:
	return player_by_id(offside_passer_id)


func _take_loose_ball(player: PlayerState) -> Dictionary:
	if is_offside_marked(player):
		var flagged := _apply_offside(_offside_passer(), player)
		if flagged.get("ok", false):
			return flagged
	_give_ball(player)
	return {}


func _offside_name_list(group: Array[PlayerState]) -> String:
	if group.is_empty():
		return ""
	if group.size() == 1:
		return group[0].label()
	if group.size() == 2:
		return "%s or %s" % [group[0].label(), group[1].label()]
	var parts: PackedStringArray = []
	for i in range(group.size() - 1):
		parts.append(group[i].label())
	return "%s, or %s" % [", ".join(parts), group[group.size() - 1].label()]


func apply_shoot(player_id: int, remaining_ap: int = -1) -> Dictionary:
	var player := player_by_id(player_id)
	remaining_ap = _shot_remaining_ap(player, remaining_ap)
	if not can_shoot(player, remaining_ap):
		return {ok = false, reason = "illegal_shot"}
	var goal := MatchRules.opponent_goal(player.team)
	var intercept := _resolve_pass_intercepts(player, goal)
	if intercept.get("intercepted", false):
		var thief: PlayerState = intercept.player
		var landing: Vector2i = intercept.landing
		var from_tile := thief.pos
		thief.relocate(landing)
		_give_ball(thief)
		return _finish_action(player, {
			ok = true,
			action = "shoot",
			intercepted = true,
			player_id = player_id,
			receiver_id = thief.id,
			interceptor_id = thief.id,
			dest = landing,
			interceptor_from = from_tile,
			origin = player.pos,
			hit = false,
			saved = false,
			goal = false,
			reset = false,
			gained_possession = false,
			lost_possession = true,
			home_score = home_score,
			away_score = away_score,
			attacker_label = player.label(),
			defender_label = thief.label(),
			attacker_stat_name = "ACC",
			defender_stat_name = "DEF",
			attacker_stat = player.live_accuracy(),
			defender_stat = thief.live_defense(),
			attacker_dice = intercept.attacker_dice,
			defender_dice = intercept.defender_dice,
			attacker_total = intercept.attacker_total,
			defender_total = intercept.defender_total,
			remaining_ap = remaining_ap,
		})
	var preview := shot_preview(player, remaining_ap)
	var hit: bool = rng.randf() < float(preview.hit_chance)
	var saved: bool = false
	if scripted_shot_outcome == "miss":
		hit = false
	elif scripted_shot_outcome == "save":
		hit = true
		saved = preview.keeper_in_net
	elif scripted_shot_outcome == "goal":
		hit = true
		saved = false
	elif hit and preview.keeper_in_net:
		var keeper := player_at(goal)
		var roll := MatchRules.resolve_contest(
			player.live_accuracy(),
			keeper.live_defense(),
			rng,
			true
		)
		saved = not roll.attacker_won
		preview.attacker_dice = roll.attacker_dice
		preview.defender_dice = roll.defender_dice
		preview.attacker_total = roll.attacker_total
		preview.defender_total = roll.defender_total

	var result := {
		ok = true,
		action = "shoot",
		player_id = player_id,
		dest = goal,
		origin = player.pos,
		hit = hit,
		saved = saved,
		goal = false,
		reset = false,
		home_score = home_score,
		away_score = away_score,
		attacker_label = player.label(),
		header = preview.header,
		remaining_ap = remaining_ap,
		leftover_bonus = preview.leftover_bonus,
	}
	if not hit:
		_release_ball(goal)
		return _finish_action(player, result)
	if saved:
		var keeper := player_at(goal)
		if keeper != null:
			_give_ball(keeper)
		else:
			_release_ball(goal)
		return _finish_action(player, result)
	player.spend_energy()
	result.goal = true
	_award_goal(player.team)
	result.reset = true
	result.home_score = home_score
	result.away_score = away_score
	return result


func apply_move(player_id: int, dest: Vector2i) -> Dictionary:
	var player := player_by_id(player_id)
	if player == null:
		return {ok = false, reason = "no_player"}
	if not _acting_allowed(player):
		return {ok = false, reason = "wrong_team"}
	if dest not in valid_moves(player):
		return {ok = false, reason = "illegal_dest"}

	var occupant := player_at(dest)
	if occupant != null:
		return _apply_contest(player, occupant, dest)

	var origin := player.pos
	player.relocate(dest)
	var gained := false
	if player.has_ball:
		ball.pos = dest
	elif ball.is_loose() and ball.pos == dest:
		var flagged := _take_loose_ball(player)
		if not flagged.is_empty():
			return _finish_action(player, flagged)
		gained = true

	var result := {
		ok = true,
		action = "move",
		gained_possession = gained,
		lost_possession = false,
		carried = player.has_ball,
		player_id = player_id,
		dest = dest,
		origin = origin,
		goal = false,
		reset = false,
		attacker_label = player.label(),
	}
	if _carrier_in_opponent_net(player):
		player.spend_energy()
		_award_goal(player.team)
		result.goal = true
		result.reset = true
		result.home_score = home_score
		result.away_score = away_score
		return result
	return _finish_action(player, result)


func apply_sprint(player_id: int, dest: Vector2i) -> Dictionary:
	var player := player_by_id(player_id)
	if player == null:
		return {ok = false, reason = "no_player"}
	if not _acting_allowed(player):
		return {ok = false, reason = "wrong_team"}
	if dest not in valid_sprints(player):
		return {ok = false, reason = "illegal_dest"}

	var origin := player.pos
	var through := MatchRules.sprint_through(origin, dest)
	var energy := MatchRules.action_energy_cost("sprint")
	player.relocate(dest)
	var gained := false
	if player.has_ball:
		ball.pos = dest
	elif ball.is_loose() and (ball.pos == dest or ball.pos == through):
		var flagged := _take_loose_ball(player)
		if not flagged.is_empty():
			return _finish_action(player, flagged, energy)
		gained = true

	var result := {
		ok = true,
		action = "sprint",
		gained_possession = gained,
		lost_possession = false,
		carried = player.has_ball,
		player_id = player_id,
		dest = dest,
		origin = origin,
		through = through,
		goal = false,
		reset = false,
		attacker_label = player.label(),
	}
	if _carrier_in_opponent_net(player):
		player.spend_energy(energy)
		_award_goal(player.team)
		result.goal = true
		result.reset = true
		result.home_score = home_score
		result.away_score = away_score
		return result
	return _finish_action(player, result, energy)


func _apply_contest(player: PlayerState, occupant: PlayerState, dest: Vector2i) -> Dictionary:
	var origin := player.pos
	var is_dribble := player.has_ball
	var is_tackle := (not player.has_ball) and occupant.has_ball
	var attacker_stat := player.live_control()
	var defender_stat := occupant.live_control()
	var attacker_name := "CTR"
	var defender_name := "CTR"
	var action := "challenge"
	if is_dribble:
		action = "dribble"
		attacker_stat = player.live_control()
		defender_stat = occupant.live_defense()
		attacker_name = "CTR"
		defender_name = "DEF"
	elif is_tackle:
		action = "tackle"
		attacker_stat = player.live_defense()
		defender_stat = occupant.live_control()
		attacker_name = "DEF"
		defender_name = "CTR"
	var holder := carrier()
	var possession_team := holder.team if holder != null else -1
	var ties_to_atk := false
	if not is_dribble and not is_tackle:
		ties_to_atk = MatchRules.attacker_wins_ties(player, occupant, possession_team)
	var roll := MatchRules.resolve_contest(attacker_stat, defender_stat, rng, ties_to_atk)
	if scripted_attacker_wins != null:
		MatchRules.apply_scripted_winner(roll, bool(scripted_attacker_wins))
	elif scripted_contest_tie:
		MatchRules.apply_scripted_tie(roll)
	var tackle_dir := {}
	if is_tackle:
		tackle_dir = MatchRules.tackle_direction(occupant.facing, player.pos, dest)
		if scripted_attacker_wins == null and not scripted_contest_tie:
			MatchRules.apply_tackle_direction_penalty(roll, float(tackle_dir.penalty), rng)

	var result := {
		ok = true,
		action = action,
		player_id = player.id,
		defender_id = occupant.id,
		dest = dest,
		origin = origin,
		gained_possession = false,
		lost_possession = false,
		contest_won = roll.attacker_won,
		contest_tied = false,
		bounced = false,
		displaced_id = -1,
		attacker_label = player.label(),
		defender_label = occupant.label(),
		attacker_stat_name = attacker_name,
		defender_stat_name = defender_name,
		attacker_stat = attacker_stat,
		defender_stat = defender_stat,
		attacker_dice = roll.attacker_dice,
		defender_dice = roll.defender_dice,
		attacker_total = roll.attacker_total,
		defender_total = roll.defender_total,
	}
	if not tackle_dir.is_empty():
		result.angle_deg = tackle_dir.angle_deg
		result.angle_penalty = tackle_dir.penalty
		result.angle_label = tackle_dir.label

	if roll.attacker_won:
		if is_tackle:
			_give_ball(player)
			result.gained_possession = true
			_face_away_from(player, occupant)
			result.facing = player.facing
		else:
			player.relocate(dest)
			occupant.relocate(origin)
			result.displaced_id = occupant.id
			if is_dribble:
				ball.pos = dest
	elif (is_dribble or is_tackle) and bool(roll.get("tied", false)):
		var bounce_cell := _bounce_ball()
		result.contest_tied = true
		result.bounced = true
		result.bounce_cell = bounce_cell
		result.lost_possession = holder != null and not holder.has_ball
		result.gained_possession = player.has_ball and (holder == null or holder.id != player.id)
	elif is_dribble:
		_give_ball(occupant)
		result.lost_possession = true
	result.carried = player.has_ball

	if _carrier_in_opponent_net(player):
		player.spend_energy()
		_award_goal(player.team)
		result.goal = true
		result.reset = true
		result.home_score = home_score
		result.away_score = away_score
		return result
	return _finish_action(player, result)


func _finish_action(
	player: PlayerState,
	result: Dictionary,
	energy_cost: int = MatchRules.ACTION_ENERGY_COST
) -> Dictionary:
	if player != null and result.get("ok", false):
		player.spend_energy(energy_cost)
	return result


## Face away from `other` so the winner's back is toward the player they stole from.
func _face_away_from(player: PlayerState, other: PlayerState) -> void:
	if player == null or other == null:
		return
	if player.pos == other.pos:
		return
	player.facing = MatchRules.step_direction(other.pos, player.pos)


func _carrier_in_opponent_net(player: PlayerState) -> bool:
	return player != null and player.has_ball and player.pos == MatchRules.opponent_goal(player.team)


func _award_goal(scoring_team: int) -> void:
	if scoring_team == MatchRules.Team.HOME:
		home_score += 1
	else:
		away_score += 1
	setup_kickoff(MatchRules.opposite_team(scoring_team))


func _give_ball(player: PlayerState) -> void:
	_clear_offside_marks()
	var previous := carrier()
	if previous != null:
		previous.has_ball = false
	player.has_ball = true
	ball.carrier_id = player.id
	ball.pos = player.pos


func _release_ball(pos: Vector2i) -> void:
	var previous := carrier()
	if previous != null:
		previous.has_ball = false
	ball.carrier_id = -1
	ball.pos = pos


## Scatter the live ball to one cell of the 3×3 around its current tile.
## Occupied landings give that player the ball; empty landings leave it loose.
func _bounce_ball() -> Vector2i:
	var origin := ball.pos
	var cell: Vector2i = origin
	if scripted_bounce_cell != null:
		cell = scripted_bounce_cell
	else:
		cell = MatchRules.pick_bounce_cell(origin, rng)
	if not MatchRules.in_bounds(cell):
		cell = origin
	var occupant := player_at(cell)
	if occupant != null:
		_take_loose_ball(occupant)
	else:
		_clear_offside_marks()
		_release_ball(cell)
	return cell


func _positions_unique() -> bool:
	var seen := {}
	for player in players:
		if seen.has(player.pos):
			return false
		seen[player.pos] = true
	return true
