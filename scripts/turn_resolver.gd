class_name TurnResolver
extends RefCounted

## Resolves one planned cycle: Aether's queued actions + Helix's queued actions.
## Order: tackles, passes/shots (follow the ball), dribbles, square fights, destination contests, moves/swaps.


static func resolve(model: MatchModel) -> Dictionary:
	var plans: Array[Dictionary] = []
	for plan in model.home_plans:
		plans.append(plan)
	for plan in model.away_plans:
		plans.append(plan)
	model.combat_log.header("── Resolve cycle %d ──" % (model.turn_index + 1))
	model.ignore_team_gate = true
	var events: Array[Dictionary] = []
	var remaining := _copy_plans(plans)
	var reset := false

	reset = _run_phase(model, remaining, events, ["tackle"], "Tackles")
	if not reset:
		reset = _run_ball_phase(model, remaining, events)
	if not reset:
		reset = _run_phase(model, remaining, events, ["dribble"], "Dribbles")
	if not reset:
		reset = _run_phase(model, remaining, events, ["challenge"], "Square fights")
	if not reset:
		reset = _resolve_destination_clashes(model, remaining, events)
	if not reset:
		reset = _run_phase(model, remaining, events, ["move", "swap"], "Movement")

	if reset:
		for leftover in remaining:
			events.append(_cancel(model, leftover, "play stopped — goal"))
	else:
		for leftover in remaining:
			events.append(_cancel(model, leftover, "could not be completed"))
		model.current_team = MatchRules.Team.HOME
		model.turn_index += 1
		model.combat_log.note("Next: AETHER plans 3 actions.")

	model.home_plans.clear()
	model.away_plans.clear()
	model.ignore_team_gate = false
	return {
		ok = true,
		action = "resolve",
		events = events,
		reset = reset,
		home_score = model.home_score,
		away_score = model.away_score,
	}


static func _copy_plans(plans: Array[Dictionary]) -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for plan in plans:
		copy.append(plan.duplicate(true))
	return copy


static func _run_phase(
	model: MatchModel,
	remaining: Array[Dictionary],
	events: Array[Dictionary],
	kinds: Array,
	title: String
) -> bool:
	var batch: Array[Dictionary] = []
	for plan in remaining:
		if str(plan.get("action", "")) in kinds:
			batch.append(plan)
	if batch.is_empty():
		return false
	batch.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.player_id) < int(b.player_id))
	model.combat_log.note(title)
	for plan in batch:
		_drop_plan(remaining, int(plan.player_id))
		var result := _apply_plan(model, plan)
		events.append(result)
		if result.get("reset", false):
			return true
	return false


static func _run_ball_phase(
	model: MatchModel,
	remaining: Array[Dictionary],
	events: Array[Dictionary]
) -> bool:
	var batch: Array[Dictionary] = []
	for plan in remaining:
		if str(plan.get("action", "")) in ["pass", "shoot"]:
			batch.append(plan)
	if batch.is_empty():
		return false
	model.combat_log.note("Ball")
	while not batch.is_empty():
		var plan := _next_ball_plan(model, batch)
		_drop_plan(remaining, int(plan.player_id))
		_drop_plan(batch, int(plan.player_id))
		var result := _apply_plan(model, plan)
		events.append(result)
		if result.get("reset", false):
			return true
	return false


static func _next_ball_plan(model: MatchModel, batch: Array[Dictionary]) -> Dictionary:
	var holder := model.carrier()
	if holder != null:
		for plan in batch:
			if int(plan.get("player_id", -1)) == holder.id:
				return plan
	var copy := batch.duplicate()
	copy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.player_id) < int(b.player_id))
	return copy[0]


static func _resolve_destination_clashes(
	model: MatchModel,
	remaining: Array[Dictionary],
	events: Array[Dictionary]
) -> bool:
	var by_dest := {}
	for plan in remaining:
		if str(plan.get("action", "")) != "move":
			continue
		var dest: Vector2i = plan.get("dest", Vector2i.ZERO)
		if not by_dest.has(dest):
			by_dest[dest] = []
		by_dest[dest].append(plan)
	var had_clash := false
	for dest in by_dest.keys():
		var group: Array = by_dest[dest]
		if group.size() < 2:
			continue
		if not had_clash:
			model.combat_log.note("Destination contests")
			had_clash = true
		if _all_same_team(model, group):
			var winner: Dictionary = _clash_winner(model, group, dest, events)
			for plan in group:
				if int(plan.player_id) == int(winner.player_id):
					continue
				_drop_plan(remaining, int(plan.player_id))
				events.append(_cancel(model, plan, "lost the square fight"))
			continue
		var arrival := _arrival_winner(model, group, dest, events)
		if _apply_arrival_result(model, remaining, events, group, arrival, dest):
			return true
	return false


static func _all_same_team(model: MatchModel, group: Array) -> bool:
	var team := -1
	for plan in group:
		var player := model.player_by_id(int(plan.get("player_id", -1)))
		if player == null:
			continue
		if team < 0:
			team = player.team
		elif player.team != team:
			return false
	return true


static func _group_carrier(model: MatchModel, group: Array) -> PlayerState:
	for plan in group:
		var player := model.player_by_id(int(plan.get("player_id", -1)))
		if player != null and player.has_ball:
			return player
	return null


static func _arrival_winner(
	model: MatchModel,
	group: Array,
	dest: Vector2i,
	events: Array[Dictionary]
) -> Dictionary:
	var contenders: Array = group.duplicate()
	contenders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.player_id) < int(b.player_id))
	var champ: Dictionary = contenders[0]
	for i in range(1, contenders.size()):
		champ = _arrival_pair(model, champ, contenders[i], dest, events)
	return champ


static func _arrival_pair(
	model: MatchModel,
	plan_a: Dictionary,
	plan_b: Dictionary,
	dest: Vector2i,
	events: Array[Dictionary]
) -> Dictionary:
	var player_a := model.player_by_id(int(plan_a.get("player_id", -1)))
	var player_b := model.player_by_id(int(plan_b.get("player_id", -1)))
	if player_a == null:
		return plan_b
	if player_b == null:
		return plan_a
	var opposite := player_a.team != player_b.team
	var carrier := player_a if player_a.has_ball else (player_b if player_b.has_ball else null)
	var attacker := player_a
	var defender := player_b
	var attacker_stat := player_a.live_control()
	var defender_stat := player_b.live_control()
	var attacker_name := "CTR"
	var defender_name := "CTR"
	var action := "challenge"
	if opposite and carrier != null:
		var tackler := player_b if carrier.id == player_a.id else player_a
		attacker = tackler
		defender = carrier
		attacker_stat = tackler.live_defense()
		defender_stat = carrier.live_control()
		attacker_name = "DEF"
		defender_name = "CTR"
		action = "tackle"
	elif player_b.id < player_a.id:
		attacker = player_b
		defender = player_a
		attacker_stat = player_b.live_control()
		defender_stat = player_a.live_control()
	var holder := model.carrier()
	var possession_team := holder.team if holder != null else -1
	var ties_to_atk := MatchRules.attacker_wins_ties(attacker, defender, possession_team)
	var roll := MatchRules.resolve_contest(attacker_stat, defender_stat, model.rng, ties_to_atk)
	if model.scripted_attacker_wins != null:
		MatchRules.apply_scripted_winner(roll, bool(model.scripted_attacker_wins))
	var winner_player := attacker if roll.attacker_won else defender
	var contest := {
		ok = true,
		action = action,
		player_id = attacker.id,
		defender_id = defender.id,
		dest = dest,
		attacker_label = attacker.label(),
		defender_label = defender.label(),
		winner_label = winner_player.label(),
		attacker_stat = attacker_stat,
		defender_stat = defender_stat,
		attacker_stat_name = attacker_name,
		defender_stat_name = defender_name,
		attacker_dice = roll.attacker_dice,
		defender_dice = roll.defender_dice,
		attacker_total = roll.attacker_total,
		defender_total = roll.defender_total,
		contest_won = roll.attacker_won,
	}
	events.append(contest)
	model.combat_log.event(contest)
	if winner_player.id == int(plan_a.get("player_id", -1)):
		return plan_a
	return plan_b


static func _apply_arrival_result(
	model: MatchModel,
	remaining: Array[Dictionary],
	events: Array[Dictionary],
	group: Array,
	winner: Dictionary,
	dest: Vector2i
) -> bool:
	var winner_id := int(winner.get("player_id", -1))
	var winner_player := model.player_by_id(winner_id)
	var carrier := _group_carrier(model, group)
	if (
		winner_player != null
		and carrier != null
		and carrier.id != winner_id
		and not _all_same_team(model, group)
	):
		model._give_ball(winner_player)
	var applied := false
	if winner_player != null and dest in model.valid_moves(winner_player):
		var moved: Dictionary = model.apply_move(winner_id, dest)
		if moved.get("ok", false):
			if not moved.has("attacker_label"):
				moved.attacker_label = winner_player.label()
			model.combat_log.event(moved)
			events.append(moved)
			applied = true
			if moved.get("reset", false):
				for plan in group:
					_drop_plan(remaining, int(plan.get("player_id", -1)))
					if int(plan.get("player_id", -1)) != winner_id:
						events.append(_cancel(model, plan, "play stopped — goal"))
				return true
	var reason := "lost the square fight"
	if carrier != null:
		reason = "lost the tackle"
	for plan in group:
		_drop_plan(remaining, int(plan.get("player_id", -1)))
		if int(plan.get("player_id", -1)) == winner_id and applied:
			continue
		if int(plan.get("player_id", -1)) == winner_id:
			events.append(_cancel(model, plan, "destination no longer legal"))
			continue
		events.append(_cancel(model, plan, reason))
	return false


static func _clash_winner(
	model: MatchModel,
	group: Array,
	dest: Vector2i,
	events: Array[Dictionary]
) -> Dictionary:
	var contenders: Array = group.duplicate()
	contenders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.player_id) < int(b.player_id))
	var champ: Dictionary = contenders[0]
	for i in range(1, contenders.size()):
		var other: Dictionary = contenders[i]
		var attacker := model.player_by_id(int(champ.player_id))
		var defender := model.player_by_id(int(other.player_id))
		if attacker == null or defender == null:
			continue
		var holder := model.carrier()
		var possession_team := holder.team if holder != null else -1
		var ties_to_atk := MatchRules.attacker_wins_ties(attacker, defender, possession_team)
		var roll := MatchRules.resolve_contest(
			attacker.live_control(),
			defender.live_control(),
			model.rng,
			ties_to_atk
		)
		if model.scripted_attacker_wins != null:
			MatchRules.apply_scripted_winner(roll, bool(model.scripted_attacker_wins))
		var winner_player := attacker
		if not roll.attacker_won:
			winner_player = defender
			champ = other
		var clash := {
			ok = true,
			action = "clash",
			player_id = winner_player.id,
			defender_id = defender.id if winner_player.id == attacker.id else attacker.id,
			dest = dest,
			attacker_label = attacker.label(),
			defender_label = defender.label(),
			winner_label = winner_player.label(),
			attacker_stat = attacker.live_control(),
			defender_stat = defender.live_control(),
			attacker_stat_name = "CTR",
			defender_stat_name = "CTR",
			attacker_dice = roll.attacker_dice,
			defender_dice = roll.defender_dice,
			attacker_total = roll.attacker_total,
			defender_total = roll.defender_total,
			contest_won = winner_player.id == attacker.id,
		}
		events.append(clash)
		model.combat_log.event(clash)
	return champ


static func _apply_plan(model: MatchModel, plan: Dictionary) -> Dictionary:
	var player := model.player_by_id(int(plan.get("player_id", -1)))
	if player == null:
		return _cancel(model, plan, "player missing")
	var action := str(plan.get("action", ""))
	if action in ["pass", "shoot", "dribble"] and not player.has_ball:
		var reason := "pass did not arrive" if bool(plan.get("expects_ball", false)) else "lost the ball"
		return _cancel(model, plan, reason)
	if action == "tackle":
		var occupant := model.player_at(plan.get("dest", player.pos))
		if occupant == null or not occupant.has_ball:
			return _cancel(model, plan, "target no longer has the ball")
	var result := {}
	match action:
		"move", "dribble", "tackle", "challenge":
			var dest: Vector2i = plan.get("dest", player.pos)
			if dest not in model.valid_moves(player):
				return _cancel(model, plan, "destination no longer legal")
			result = model.apply_move(player.id, dest)
		"swap":
			result = model.apply_swap(player.id, int(plan.get("target_id", -1)))
			if not result.get("ok", false):
				return _cancel(model, plan, "swap no longer legal")
		"pass":
			var dest: Vector2i = plan.get("dest", player.pos)
			var target_id := int(plan.get("target_id", -1))
			if target_id >= 0:
				var target := model.player_by_id(target_id)
				if target == null:
					return _cancel(model, plan, "receiver missing")
				dest = target.pos
			if not model.can_pass_to_cell(player, dest):
				return _cancel(model, plan, "pass no longer legal")
			result = model.apply_pass_to(player.id, dest)
		"shoot":
			if not model.can_shoot(player):
				return _cancel(model, plan, "shot no longer legal")
			result = model.apply_shoot(player.id)
		_:
			return _cancel(model, plan, "unknown action")
	if not result.get("ok", false):
		return _cancel(model, plan, str(result.get("reason", "failed")))
	if result.get("action", "") == "move" and not result.has("attacker_label"):
		result.attacker_label = player.label()
	model.combat_log.event(result)
	return result


static func _drop_plan(remaining: Array[Dictionary], player_id: int) -> void:
	for i in range(remaining.size() - 1, -1, -1):
		if int(remaining[i].get("player_id", -1)) == player_id:
			remaining.remove_at(i)


static func _cancel(model: MatchModel, plan: Dictionary, reason: String) -> Dictionary:
	var player := model.player_by_id(int(plan.get("player_id", -1)))
	var result := {
		ok = true,
		action = "cancelled",
		player_id = int(plan.get("player_id", -1)),
		label = str(plan.get("action", "action")),
		reason = reason,
		reason_text = reason,
		attacker_label = player.label() if player != null else "player",
		dest = plan.get("dest", Vector2i.ZERO),
	}
	model.combat_log.event(result)
	return result
