class_name TurnResolver
extends RefCounted

## Resolves one planned cycle: Aether's queued actions + Helix's queued actions.
## Order: tackles, dribbles, square fights, passes/shots, destination clashes, moves/swaps.


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
		reset = _run_phase(model, remaining, events, ["dribble"], "Dribbles")
	if not reset:
		reset = _run_phase(model, remaining, events, ["challenge"], "Square fights")
	if not reset:
		reset = _run_phase(model, remaining, events, ["pass", "shoot"], "Ball")
	if not reset:
		_resolve_destination_clashes(model, remaining, events)
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


static func _resolve_destination_clashes(
	model: MatchModel,
	remaining: Array[Dictionary],
	events: Array[Dictionary]
) -> void:
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
			model.combat_log.note("Destination clashes")
			had_clash = true
		var winner: Dictionary = _clash_winner(model, group, dest, events)
		for plan in group:
			if int(plan.player_id) == int(winner.player_id):
				continue
			_drop_plan(remaining, int(plan.player_id))
			events.append(_cancel(model, plan, "lost the square fight"))


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
		var roll := MatchRules.resolve_contest(attacker.control, defender.control, model.rng)
		if model.scripted_attacker_wins != null:
			roll.attacker_won = bool(model.scripted_attacker_wins)
			if roll.attacker_won:
				roll.attacker_total = attacker.control + 12
				roll.defender_total = defender.control + 2
				roll.attacker_dice = 12
				roll.defender_dice = 2
			else:
				roll.attacker_total = attacker.control + 2
				roll.defender_total = defender.control + 12
				roll.attacker_dice = 2
				roll.defender_dice = 12
		var winner_player := attacker
		if roll.attacker_total < roll.defender_total:
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
			attacker_stat = attacker.control,
			defender_stat = defender.control,
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
		return _cancel(model, plan, "lost the ball")
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
