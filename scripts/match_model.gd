class_name MatchModel
extends RefCounted

## Authoritative match state. No nodes, no visuals.

var current_team: int = MatchRules.Team.HOME
var turn_index: int = 0
var home_score: int = 0
var away_score: int = 0
var players: Array[PlayerState] = []
var ball: BallState = BallState.new()
var rng := RandomNumberGenerator.new()
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
		for slot in Formation.slots(team):
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
	current_team = kicking_team
	turn_index = 0
	rng.randomize()
	var kicker: PlayerState = null
	if kicking_team == MatchRules.Team.HOME:
		kicker = player_at(Vector2i(5, 3))
	else:
		kicker = player_at(Vector2i(6, 4))
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
	return MatchRules.move_destinations(player.pos, teammate_cells(player.id))


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
	return player != null and player.team == current_team


func can_pass_to(passer: PlayerState, target: PlayerState) -> bool:
	if passer == null or target == null:
		return false
	if target.team != passer.team or target.id == passer.id:
		return false
	return can_pass_to_cell(passer, target.pos)


func can_pass_to_cell(passer: PlayerState, dest: Vector2i) -> bool:
	if passer == null or not passer.has_ball:
		return false
	if passer.team != current_team:
		return false
	if not MatchRules.in_bounds(dest) or dest == passer.pos:
		return false
	if MatchRules.is_goal_tile(dest):
		return false
	if MatchRules.chebyshev(passer.pos, dest) > MatchRules.PASS_RANGE:
		return false
	var occupant := player_at(dest)
	if occupant == null:
		return true
	return occupant.team == passer.team and occupant.id != passer.id


func pass_targets(passer: PlayerState) -> Array[PlayerState]:
	var result: Array[PlayerState] = []
	if passer == null or not passer.has_ball:
		return result
	for player in players:
		if can_pass_to(passer, player):
			result.append(player)
	return result


func pass_cells(passer: PlayerState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if passer == null or not passer.has_ball:
		return cells
	for dest in _cells_in_range(passer.pos, MatchRules.PASS_RANGE):
		if can_pass_to_cell(passer, dest):
			cells.append(dest)
	return cells


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
	if player.team != current_team or teammate.team != player.team:
		return false
	if teammate.id == player.id:
		return false
	return MatchRules.is_adjacent(player.pos, teammate.pos)


func actions_for(player: PlayerState, dest: Vector2i) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if player == null or player.team != current_team:
		return actions
	if not MatchRules.in_bounds(dest):
		return actions
	var occupant := player_at(dest)
	if occupant == null:
		if dest in valid_moves(player):
			actions.append({id = "move", label = "Move", dest = dest})
		if can_pass_to_cell(player, dest):
			actions.append({id = "pass", label = "Pass", dest = dest, target_id = -1})
	elif occupant.team != player.team:
		if dest in valid_moves(player):
			var preview := MatchRules.contest_preview(player, occupant)
			actions.append({
				id = preview.action,
				label = preview.verb.capitalize(),
				dest = dest,
			})
	else:
		if can_pass_to(player, occupant):
			actions.append({id = "pass", label = "Pass", target_id = occupant.id, dest = dest})
		if can_swap(player, occupant):
			actions.append({id = "swap", label = "Swap places", target_id = occupant.id, dest = dest})
	if can_shoot(player) and dest == MatchRules.opponent_goal(player.team):
		actions.append({id = "shoot", label = "Shoot", dest = dest})
	return actions


func can_shoot(player: PlayerState) -> bool:
	if player == null or not player.has_ball or player.team != current_team:
		return false
	return MatchRules.is_in_shooting_zone(player.pos, MatchRules.opponent_goal(player.team))


func shoot_cells(player: PlayerState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if can_shoot(player):
		cells.append(MatchRules.opponent_goal(player.team))
	return cells


func choice_cells(player: PlayerState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if player == null:
		return cells
	for dest in _cells_in_range(player.pos, MatchRules.PASS_RANGE):
		if actions_for(player, dest).size() > 1:
			cells.append(dest)
	var goal := MatchRules.opponent_goal(player.team)
	if goal not in cells and actions_for(player, goal).size() > 1:
		cells.append(goal)
	return cells


func shot_preview(player: PlayerState) -> Dictionary:
	var goal := MatchRules.opponent_goal(player.team)
	var geo := MatchRules.shot_geometry(player.pos, goal)
	var range_f := MatchRules.shot_range_factor(geo.distance)
	var angle_f := MatchRules.shot_angle_factor(geo.angle)
	var acc_term := float(player.accuracy) / float(player.accuracy + MatchRules.SHOT_ACC_BIAS)
	var hit := MatchRules.shot_hit_chance(player.accuracy, geo.distance, geo.angle)
	var keeper := player_at(goal)
	var keeper_in_net := keeper != null and keeper.team != player.team
	var save := 0.0
	if keeper_in_net:
		save = 1.0 - MatchRules.contest_win_chance(player.accuracy, keeper.defense)
	var goal_p := hit * (1.0 - save)
	var lines: PackedStringArray = []
	lines.append("SHOOT at %s net" % MatchRules.team_name(MatchRules.opposite_team(player.team)))
	lines.append("d = %.2f tiles   θ = %.0f°" % [geo.distance, geo.angle_deg])
	lines.append("range = 1 / (1 + %.2f×(d−1)) = %.2f" % [MatchRules.SHOT_RANGE_K, range_f])
	lines.append("angle = max(%.2f, cos θ) = %.2f" % [MatchRules.SHOT_ANGLE_FLOOR, angle_f])
	lines.append("hit = ACC/(ACC+%d) × range × angle" % MatchRules.SHOT_ACC_BIAS)
	lines.append("    = %d/%d × %.2f × %.2f = %d%%" % [
		player.accuracy,
		player.accuracy + MatchRules.SHOT_ACC_BIAS,
		range_f,
		angle_f,
		int(round(hit * 100.0)),
	])
	if keeper_in_net:
		lines.append("save = P(keeper DEF+2d6 ≥ ACC+2d6) = %d%%" % int(round(save * 100.0)))
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
		text = "\n".join(lines),
		header = "shoot  goal %d%%  (hit %d%%, save %d%%)" % [
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
	player.pos = dest
	teammate.pos = origin
	if player.has_ball:
		ball.pos = dest
	elif teammate.has_ball:
		ball.pos = origin
	_advance_turn()
	return {
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
		attacker_label = player.label(),
		defender_label = teammate.label(),
	}


func interceptors_for_pass(passer: PlayerState, dest: Vector2i) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if passer == null:
		return found
	var start := MatchRules.tile_center(passer.pos)
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
		var through := MatchRules.contest_win_chance(passer.accuracy, player.defense)
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
				passer.accuracy,
				threat.player.defense,
				threat.intercept_percent,
				threat.through_percent,
			]
		)
	var total_pct := int(round(total * 100.0))
	var occupant := player_at(dest)
	var target_name := occupant.label() if occupant != null else "open square"
	var dist := MatchRules.chebyshev(passer.pos, dest)
	var header := "pass to %s (%d %s)" % [target_name, dist, "tile" if dist == 1 else "tiles"]
	var body := "\n".join(lines)
	var footer := "Pass success: %d%%" % total_pct
	if threats.is_empty():
		footer = "No interceptors. Pass success: 100%"
	var text := header + "\n" + (body + "\n" if body != "" else "") + footer
	return {
		threats = threats,
		total = total,
		total_percent = total_pct,
		header = header,
		text = text,
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
		thief.pos = landing
		_give_ball(thief)
		_advance_turn()
		return {
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
			attacker_stat = passer.accuracy,
			defender_stat = thief.defense,
			attacker_dice = intercept.attacker_dice,
			defender_dice = intercept.defender_dice,
			attacker_total = intercept.attacker_total,
			defender_total = intercept.defender_total,
		}

	var occupant := player_at(dest)
	var receiver_id := -1
	var receiver_label := "open square"
	if occupant != null:
		_give_ball(occupant)
		receiver_id = occupant.id
		receiver_label = occupant.label()
	else:
		_release_ball(dest)
	_advance_turn()
	return {
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
	}


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
				attacker_dice = 2,
				defender_dice = 12,
				attacker_total = passer.accuracy + 2,
				defender_total = first.player.defense + 12,
			}
		return {intercepted = false}
	for threat in threats:
		var roll := MatchRules.resolve_contest(passer.accuracy, threat.player.defense, rng)
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


func apply_shoot(player_id: int) -> Dictionary:
	var player := player_by_id(player_id)
	if not can_shoot(player):
		return {ok = false, reason = "illegal_shot"}
	var preview := shot_preview(player)
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
		var roll := MatchRules.resolve_contest(player.accuracy, keeper.defense, rng)
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
	}
	if not hit:
		_release_ball(goal)
		_advance_turn()
		return result
	if saved:
		var keeper := player_at(goal)
		if keeper != null:
			_give_ball(keeper)
		else:
			_release_ball(goal)
		_advance_turn()
		return result
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
	if player.team != current_team:
		return {ok = false, reason = "wrong_team"}
	if dest not in valid_moves(player):
		return {ok = false, reason = "illegal_dest"}

	var occupant := player_at(dest)
	if occupant != null:
		return _apply_contest(player, occupant, dest)

	var origin := player.pos
	player.pos = dest
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
		player_id = player_id,
		dest = dest,
		origin = origin,
		goal = false,
		reset = false,
	}
	if _carrier_in_opponent_net(player):
		_award_goal(player.team)
		result.goal = true
		result.reset = true
		result.home_score = home_score
		result.away_score = away_score
		return result
	_advance_turn()
	return result


func _apply_contest(player: PlayerState, occupant: PlayerState, dest: Vector2i) -> Dictionary:
	var origin := player.pos
	var is_dribble := player.has_ball
	var is_tackle := (not player.has_ball) and occupant.has_ball
	var attacker_stat := player.control
	var defender_stat := occupant.control
	var attacker_name := "CTR"
	var defender_name := "CTR"
	var action := "challenge"
	if is_dribble:
		action = "dribble"
		attacker_stat = player.control
		defender_stat = occupant.defense
		attacker_name = "CTR"
		defender_name = "DEF"
	elif is_tackle:
		action = "tackle"
		attacker_stat = player.defense
		defender_stat = occupant.control
		attacker_name = "DEF"
		defender_name = "CTR"
	var roll := MatchRules.resolve_contest(attacker_stat, defender_stat, rng)
	if scripted_attacker_wins != null:
		roll.attacker_won = bool(scripted_attacker_wins)

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
		occupant.pos = origin
		player.pos = dest
		result.displaced_id = occupant.id
		if is_dribble:
			ball.pos = dest
		elif is_tackle:
			_give_ball(player)
			result.gained_possession = true
	elif is_dribble:
		_give_ball(occupant)
		result.lost_possession = true

	if _carrier_in_opponent_net(player):
		_award_goal(player.team)
		result.goal = true
		result.reset = true
		result.home_score = home_score
		result.away_score = away_score
		return result
	_advance_turn()
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


func _advance_turn() -> void:
	turn_index += 1
	current_team = MatchRules.opposite_team(current_team)


func _positions_unique() -> bool:
	var seen := {}
	for player in players:
		if seen.has(player.pos):
			return false
		seen[player.pos] = true
	return true
