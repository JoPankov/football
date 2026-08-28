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
## null = roll; true = first interceptor wins the ball; false = passer beats every interceptor.
var scripted_first_intercept_wins = null
## null = roll; "goal", "save", or "miss".
var scripted_shot_outcome = null


func setup_kickoff(kicking_team: int = MatchRules.Team.HOME) -> void:
	players.clear()
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
		action_id, _query_pos(player), dest, ap_remaining(player.id)
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
		if act in ["move", "dribble", "tackle", "challenge", "swap"]:
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
		if act == "turn" or act in ["move", "dribble", "tackle", "challenge", "swap"]:
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


func can_queue(player: PlayerState) -> bool:
	if not _acting_allowed(player):
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
	var remaining := ap_remaining(player_id)
	var cost := MatchRules.action_ap_cost(action_id, origin, dest, remaining)
	if cost > remaining:
		return {ok = false, reason = "not_enough_ap"}
	var ap_index := plans_of(player_id).size()
	var plan := {
		player_id = player_id,
		team = player.team,
		action = action_id,
		dest = dest,
		target_id = int(action.get("target_id", -1)),
		origin = origin,
		ap_index = ap_index,
		ap_cost = cost,
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
		holder = _planning_collector_at(ball.pos)
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
						next_holder = nxt
						handed_off = true
						break
				var collector := _planning_collector_at(plan.get("dest", Vector2i.ZERO))
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
		if str(plan.get("action", "")) != "move":
			continue
		var plan_dest: Vector2i = plan.get("dest", Vector2i.ZERO)
		if plan_dest != dest:
			continue
		return player_by_id(int(plan.get("player_id", -1)))
	return null


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
	if MatchRules.chebyshev(from, dest) > MatchRules.PASS_RANGE:
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
	return cells


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
			if MatchRules.chebyshev(origin, dest) <= reach:
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
			actions.append({id = "move", label = "Move", dest = dest})
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
	return result


func command_dests(player: PlayerState, command_id: String) -> Array[Vector2i]:
	var dests: Array[Vector2i] = []
	if player == null or not can_select(player) or not can_queue(player):
		return dests
	match command_id:
		"move":
			for cell in valid_moves(player):
				if player_at(cell) == null:
					dests.append(cell)
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
	for action in actions_for(player, dest):
		if str(action.get("id", "")) == command_id:
			return action
	return {}


func can_shoot(player: PlayerState) -> bool:
	if player == null or not player.has_ball or not _acting_allowed(player):
		return false
	return MatchRules.is_in_shooting_zone(player.pos, MatchRules.opponent_goal(player.team))


func can_plan_shoot(player: PlayerState) -> bool:
	if player == null or not planning_has_ball(player) or not _acting_allowed(player):
		return false
	return MatchRules.is_in_shooting_zone(
		_query_pos(player), MatchRules.opponent_goal(player.team)
	)


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
	if remaining_ap < 0:
		remaining_ap = 0 if ignore_team_gate else ap_remaining(player.id)
	var goal := MatchRules.opponent_goal(player.team)
	var geo := MatchRules.shot_geometry(_query_pos(player), goal)
	var range_f := MatchRules.shot_range_factor(geo.distance)
	var angle_f := MatchRules.shot_angle_factor(geo.angle)
	var acc := player.live_accuracy()
	var acc_term := float(acc) / float(acc + MatchRules.SHOT_ACC_BIAS)
	var leftover_bonus := MatchRules.shot_ap_bonus(remaining_ap)
	var leftover_pct := int(round(leftover_bonus * 100.0))
	var hit := MatchRules.shot_hit_chance(acc, geo.distance, geo.angle, remaining_ap)
	var keeper := player_at(goal)
	var keeper_in_net := keeper != null and keeper.team != player.team
	var save := 0.0
	if keeper_in_net:
		save = 1.0 - MatchRules.contest_win_chance(acc, keeper.live_defense(), true)
	var goal_p := hit * (1.0 - save)
	var lines: PackedStringArray = []
	lines.append("SHOOT at %s net" % MatchRules.team_name(MatchRules.opposite_team(player.team)))
	lines.append("d = %.2f tiles   θ = %.0f°" % [geo.distance, geo.angle_deg])
	lines.append("range = 1 / (1 + %.2f×(d−1)) = %.2f" % [MatchRules.SHOT_RANGE_K, range_f])
	lines.append("angle = max(%.2f, cos θ) = %.2f" % [MatchRules.SHOT_ANGLE_FLOOR, angle_f])
	lines.append("leftover AP = %d  (+%d%% hit)" % [remaining_ap, leftover_pct])
	lines.append("hit = ACC/(ACC+%d) × range × angle + leftover" % MatchRules.SHOT_ACC_BIAS)
	lines.append("    = %d/%d × %.2f × %.2f + %.2f = %d%%" % [
		acc,
		acc + MatchRules.SHOT_ACC_BIAS,
		range_f,
		angle_f,
		leftover_bonus,
		int(round(hit * 100.0)),
	])
	if keeper_in_net:
		lines.append("save = P(keeper 1dDEF > ACC 1dACC) = %d%%" % int(round(save * 100.0)))
	else:
		lines.append("save = 0% (no keeper in the net)")
	lines.append("goal = hit × (1 − save) = %d%%" % int(round(goal_p * 100.0)))
	return {
		goal = goal,
		distance = geo.distance,
		angle_deg = geo.angle_deg,
		range_factor = range_f,
		angle_factor = angle_f,
		hit_chance = hit,
		save_chance = save,
		goal_chance = goal_p,
		keeper_in_net = keeper_in_net,
		remaining_ap = remaining_ap,
		leftover_bonus = leftover_bonus,
		text = "\n".join(lines),
		header = "shoot  +%d%% AP  goal %d%%  (hit %d%%, save %d%%)" % [
			leftover_pct,
			int(round(goal_p * 100.0)),
			int(round(hit * 100.0)),
			int(round(save * 100.0)),
		],
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
		var through := MatchRules.contest_win_chance(passer.live_accuracy(), player.live_defense(), true)
		found.append({
			player = player,
			player_id = player.id,
			t = hit.t,
			dist = hit.dist,
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
			"%s: %d ACC vs %d DEF = %d%% intercept (%d%% through)" % [
				threat.player.label(),
				passer.live_accuracy(),
				threat.player.live_defense(),
				threat.intercept_percent,
				threat.through_percent,
			]
		)
	var total_pct := int(round(total * 100.0))
	var occupant := player_at(dest)
	var target_name := occupant.label() if occupant != null else "open square"
	var dist := MatchRules.chebyshev(passer.pos, dest)
	var offside := occupant != null and is_offside_receiver(passer, occupant)
	var taker: PlayerState = null
	if offside:
		taker = closest_player(MatchRules.opposite_team(passer.team), dest)
	var header := "pass to %s (%d %s)" % [target_name, dist, "tile" if dist == 1 else "tiles"]
	if offside:
		header = "OFFSIDE pass to %s (%d %s)" % [target_name, dist, "tile" if dist == 1 else "tiles"]
	if offside and taker != null:
		lines.append(
			"If it arrives: offside. %s takes the tile and the ball." % taker.label()
		)
	var body := "\n".join(lines)
	var footer := "Pass success: %d%%" % total_pct
	if threats.is_empty():
		footer = "No interceptors. Pass success: 100%"
	if offside and threats.is_empty():
		footer = "No interceptors. Offside if played."
	elif offside:
		footer += "  Offside if it arrives."
	var text := header + "\n" + (body + "\n" if body != "" else "") + footer
	return {
		threats = threats,
		total = total,
		total_percent = total_pct,
		header = header,
		text = text,
		offside = offside,
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

	var occupant := player_at(dest)
	if occupant != null and is_offside_receiver(passer, occupant):
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
	var dest := receiver.pos
	var taker := closest_player(MatchRules.opposite_team(passer.team), dest)
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
		attacker_label = passer.label(),
		defender_label = receiver.label(),
		taker_label = taker.label(),
	}


func apply_shoot(player_id: int, remaining_ap: int = -1) -> Dictionary:
	var player := player_by_id(player_id)
	if not can_shoot(player):
		return {ok = false, reason = "illegal_shot"}
	if remaining_ap < 0:
		remaining_ap = 0 if ignore_team_gate else ap_remaining(player_id)
	var preview := shot_preview(player, remaining_ap)
	var goal := MatchRules.opponent_goal(player.team)
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
		_give_ball(player)
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
	var ties_to_atk := MatchRules.attacker_wins_ties(player, occupant, possession_team)
	var roll := MatchRules.resolve_contest(attacker_stat, defender_stat, rng, ties_to_atk)
	if scripted_attacker_wins != null:
		MatchRules.apply_scripted_winner(roll, bool(scripted_attacker_wins))

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

	if roll.attacker_won:
		player.relocate(dest)
		occupant.relocate(origin)
		result.displaced_id = occupant.id
		if is_dribble:
			ball.pos = dest
		elif is_tackle:
			_give_ball(player)
			result.gained_possession = true
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


func _finish_action(player: PlayerState, result: Dictionary) -> Dictionary:
	if player != null and result.get("ok", false):
		player.spend_energy()
	return result


func _carrier_in_opponent_net(player: PlayerState) -> bool:
	return player != null and player.has_ball and player.pos == MatchRules.opponent_goal(player.team)


func _award_goal(scoring_team: int) -> void:
	if scoring_team == MatchRules.Team.HOME:
		home_score += 1
	else:
		away_score += 1
	setup_kickoff(MatchRules.opposite_team(scoring_team))


func _give_ball(player: PlayerState) -> void:
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


func _positions_unique() -> bool:
	var seen := {}
	for player in players:
		if seen.has(player.pos):
			return false
		seen[player.pos] = true
	return true
