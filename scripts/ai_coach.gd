class_name AiCoach
extends RefCounted

## Sequence planner for whichever side is model.current_team.
## Beams remaining-AP sequences per player from commands_for, then commits up to
## 3 players one sequence at a time so a pass can feed the next actor.
## fill_plans generates a handful of those joint plans and picks argmax E[V]
## against a 2–3 plan opponent belief. Does not peek at the other live queue.

const _MIN_KEEP := 0.4
const _BEAM_WIDTH := 6
const _MAX_EXPAND := 8
const _NEAR_PLAYERS := 5
const _DICE_SAMPLES := 2
const _W_SCORE := 10000.0
const _W_BALL := 18.0
const _W_XG_US := 400.0
const _W_XG_THEM := 300.0
const _W_ENERGY := 8.0
const _W_SHAPE := 2.5
const _W_GK_OUT := 40.0
const _W_DEST_CLASH := 40.0
const _W_KICKOFF_SHAPE := 1.0
const _RELOCATE_ACTIONS := ["move", "sprint", "dribble", "tackle", "challenge", "swap"]
const _KIND_QUOTA := {
	"move": 3,
	"sprint": 2,
	"turn": 2,
	"pass": 4,
	"shoot": 1,
	"dribble": 2,
	"tackle": 2,
	"challenge": 1,
	"swap": 1,
}


static func fill_plans(model: MatchModel) -> void:
	var coach := AiCoach.new()
	coach._choose_and_commit(model)


func _choose_and_commit(live: MatchModel) -> void:
	var us := live.current_team
	var snapshot := live.clone()
	var us_candidates := _our_candidates(snapshot, us)
	var them_belief := _their_belief(snapshot, us)
	var winner := _argmax_plan(snapshot, us, us_candidates, them_belief)
	_commit_winner(live, us, winner)


func _our_candidates(snapshot: MatchModel, us: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	var default_copy := _search_copy(snapshot, us, true)
	var meta := _fill(default_copy)
	_add_candidate(out, seen, default_copy.plans_for(us), true)
	var before_second := out.size()
	var second_seq: Dictionary = meta.get("second", {})
	if not second_seq.is_empty() and not (second_seq.get("actions", []) as Array).is_empty():
		var second_copy := _search_copy(snapshot, us, true)
		var claimed := _claimed_dests(second_copy, us)
		if _commit_sequence(second_copy, second_seq, claimed):
			_add_candidate(out, seen, second_copy.plans_for(us), false)
	var banned_id := int(meta.get("first_id", _first_actor_id(default_copy.plans_for(us))))
	if banned_id >= 0 and not _plans_finish(default_copy.plans_for(us), banned_id, us):
		var no_first: Array[Dictionary] = []
		for plan in default_copy.plans_for(us):
			if int(plan.get("player_id", -1)) != banned_id:
				no_first.append(plan.duplicate(true))
		if no_first.is_empty() and out.size() == before_second:
			var banned_copy := _search_copy(snapshot, us, true)
			var skip := {}
			skip[banned_id] = true
			_fill(banned_copy, skip, 0)
			_add_candidate(out, seen, banned_copy.plans_for(us), false)
		elif not no_first.is_empty():
			_add_candidate(out, seen, no_first, false)
	var shoot_copy := _shoot_now_copy(snapshot, us)
	if shoot_copy != null:
		_add_candidate(out, seen, shoot_copy.plans_for(us), false)
	if out.is_empty():
		_add_candidate(out, seen, default_copy.plans_for(us), true)
	return out


func _their_belief(snapshot: MatchModel, us: int) -> Array[Dictionary]:
	var them := MatchRules.opposite_team(us)
	var out: Array[Dictionary] = []
	var seen := {}
	var default_copy := _search_copy(snapshot, them, false)
	_fill(default_copy)
	_add_candidate(out, seen, default_copy.plans_for(them), false)
	# Empty opponent plan is a belief item: they might queue nothing this cycle.
	_add_candidate(out, seen, [], false)
	if out.is_empty():
		_add_candidate(out, seen, [], false)
	return out


func _add_candidate(out: Array[Dictionary], seen: Dictionary, plans: Array, is_default: bool) -> void:
	var key := _joint_sig(plans)
	if seen.has(key):
		return
	seen[key] = true
	out.append({
		plans = _clone_plan_list(plans),
		is_default = is_default,
	})


func _search_copy(snapshot: MatchModel, team: int, keep_prefix: bool) -> MatchModel:
	var copy := snapshot.clone()
	var prefix: Array[Dictionary] = []
	if keep_prefix:
		prefix = _clone_plan_list(snapshot.plans_for(team))
	copy.home_plans.clear()
	copy.away_plans.clear()
	copy.current_team = team
	copy.awaiting_other_side = false
	copy.ignore_team_gate = false
	for plan in prefix:
		copy.plans_for(team).append(plan)
	return copy


func _shoot_now_copy(snapshot: MatchModel, us: int) -> MatchModel:
	var copy := _search_copy(snapshot, us, true)
	var holder := copy.planning_carrier()
	if holder == null or holder.team != us or not copy.can_queue(holder):
		return null
	var goal := MatchRules.opponent_goal(us)
	if copy.can_plan_shoot(holder):
		var shoot := copy.action_for_command(holder, "shoot", goal)
		if shoot.is_empty():
			return null
		if not copy.queue_plan(holder.id, shoot).get("ok", false):
			return null
		return copy
	if copy.move_reach(holder).has(goal):
		var walk := copy.action_for_command(holder, "move", goal)
		if walk.is_empty():
			walk = {id = "move", dest = goal, label = "Move"}
		if copy.queue_plan(holder.id, walk).get("ok", false):
			return copy
	return null


func _argmax_plan(
	snapshot: MatchModel,
	us: int,
	candidates: Array[Dictionary],
	belief: Array[Dictionary]
) -> Array[Dictionary]:
	var best_plans: Array[Dictionary] = []
	var best_avg := -100000000.0
	var best_default := false
	var best_ap := -1
	var best_first := 1 << 30
	for cand in candidates:
		var plans: Array = cand.plans
		var total := 0.0
		var n := 0
		for item in belief:
			var them_plans: Array = item.plans
			for sample in _DICE_SAMPLES:
				total += _rollout(snapshot, us, plans, them_plans, sample)
				n += 1
		var avg := total / float(maxi(n, 1))
		avg -= _dest_clash_penalty(plans)
		var ap := _plans_ap(plans)
		var first_id := _first_actor_id(plans)
		if first_id < 0:
			first_id = 1 << 30
		var is_def := bool(cand.get("is_default", false))
		var better := false
		if avg > best_avg + 0.0001:
			better = true
		elif absf(avg - best_avg) <= 0.0001:
			if is_def and not best_default:
				better = true
			elif is_def == best_default:
				if ap > best_ap:
					better = true
				elif ap == best_ap and first_id < best_first:
					better = true
		if not better:
			continue
		best_avg = avg
		best_plans = _clone_plan_list(plans)
		best_default = is_def
		best_ap = ap
		best_first = first_id
	return best_plans


func _rollout(
	snapshot: MatchModel,
	us: int,
	us_plans: Array,
	them_plans: Array,
	sample_i: int
) -> float:
	var clone := snapshot.clone()
	clone.home_plans.clear()
	clone.away_plans.clear()
	for _i in sample_i:
		clone.rng.randi()
	_write_plans(clone, us, us_plans)
	_write_plans(clone, MatchRules.opposite_team(us), them_plans)
	var before_home := clone.home_score
	var before_away := clone.away_score
	var result := TurnResolver.resolve(clone)
	return _evaluate_position(clone, us, result, before_home, before_away)


func _write_plans(model: MatchModel, team: int, plans: Array) -> void:
	var dest := model.plans_for(team)
	dest.clear()
	for plan in plans:
		dest.append((plan as Dictionary).duplicate(true))


func _evaluate_position(
	model: MatchModel,
	us: int,
	result: Dictionary = {},
	before_home: int = -1,
	before_away: int = -1
) -> float:
	var them := MatchRules.opposite_team(us)
	var our_score := model.home_score if us == MatchRules.Team.HOME else model.away_score
	var their_score := model.away_score if us == MatchRules.Team.HOME else model.home_score
	var v := _W_SCORE * float(our_score - their_score)
	var scored := (
		before_home >= 0
		and (model.home_score != before_home or model.away_score != before_away)
	)
	if bool(result.get("reset", false)) or scored:
		return v + _kickoff_shape(model, us)
	v += _W_BALL * _ball_progress(model, us)
	v += _W_XG_US * _best_xg(model, us)
	v -= _W_XG_THEM * _best_xg(model, them)
	v += _W_ENERGY * (_energy_sum(model, us) - _energy_sum(model, them)) / 100.0
	v += _shape(model, us)
	return v


func _ball_progress(model: MatchModel, us: int) -> float:
	var holder := model.carrier()
	if holder != null and holder.team != us:
		return 0.0
	var progress := _progress(us, model.ball.pos)
	if holder == null:
		return 0.5 * progress
	return progress


func _best_xg(model: MatchModel, team: int) -> float:
	var best := 0.0
	var goal := MatchRules.opponent_goal(team)
	for player in model.players:
		if player.team != team or not player.has_ball:
			continue
		if not MatchRules.can_attempt_shot(player.pos, goal, player.live_accuracy(), 0):
			continue
		var preview := model.shot_preview(player, 0)
		best = maxf(best, float(preview.get("goal_chance", 0.0)))
	return best


func _energy_sum(model: MatchModel, team: int) -> float:
	var total := 0.0
	for player in model.players:
		if player.team == team:
			total += float(player.energy)
	return total


func _shape(model: MatchModel, us: int) -> float:
	var v := 0.0
	var net := MatchRules.HOME_NET if us == MatchRules.Team.HOME else MatchRules.AWAY_NET
	for player in model.players:
		if player.team != us:
			continue
		if player.role not in ["LCB", "RCB", "GK"]:
			continue
		v -= _W_SHAPE * float(MatchRules.chebyshev(player.pos, _home_slot(player)))
		if player.role == "GK" and player.pos != net:
			v -= _W_GK_OUT
	return v


func _kickoff_shape(model: MatchModel, us: int) -> float:
	var v := 0.0
	for player in model.players:
		if player.team != us:
			continue
		v -= float(MatchRules.chebyshev(player.pos, _home_slot(player)))
	return _W_KICKOFF_SHAPE * v


func _dest_clash_penalty(plans: Array) -> float:
	var seen := {}
	for plan in plans:
		var kind := str(plan.get("action", ""))
		if kind not in _RELOCATE_ACTIONS:
			continue
		var dest: Vector2i = plan.get("dest", Vector2i.ZERO)
		if seen.has(dest):
			return _W_DEST_CLASH
		seen[dest] = true
	return 0.0


func _commit_winner(live: MatchModel, us: int, plans: Array) -> void:
	live.plans_for(us).clear()
	for plan in plans:
		var stored: Dictionary = (plan as Dictionary).duplicate(true)
		live.plans_for(us).append(stored)
		var player := live.player_by_id(int(stored.get("player_id", -1)))
		live.combat_log.event({
			ok = true,
			action = "queue",
			player_id = int(stored.get("player_id", -1)),
			team = int(stored.get("team", us)),
			plan = stored,
			attacker_label = player.label() if player != null else "player",
			label = str(stored.get("label", stored.get("action", "act"))),
			plan_text = CombatLog.plan_summary(stored),
			dest = stored.get("dest", Vector2i.ZERO),
		})


func _clone_plan_list(plans: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for plan in plans:
		out.append((plan as Dictionary).duplicate(true))
	return out


func _joint_sig(plans: Array) -> String:
	var sig := PackedStringArray()
	for plan in plans:
		sig.append("%s:%s:%s:%s" % [
			int(plan.get("player_id", -1)),
			str(plan.get("action", "")),
			str(plan.get("dest", Vector2i.ZERO)),
			int(plan.get("ap_end", 0)),
		])
	sig.sort()
	return ",".join(sig)


func _first_actor_id(plans: Array) -> int:
	if plans.is_empty():
		return -1
	return int(plans[0].get("player_id", -1))


func _plans_ap(plans: Array) -> int:
	var spent := 0
	for plan in plans:
		spent += int(plan.get("ap_cost", 0))
	return spent


func _plans_finish(plans: Array, player_id: int, team: int) -> bool:
	var goal := MatchRules.opponent_goal(team)
	for plan in plans:
		if int(plan.get("player_id", -1)) != player_id:
			continue
		var act := str(plan.get("action", ""))
		var dest: Vector2i = plan.get("dest", Vector2i.ZERO)
		if act == "shoot" or dest == goal:
			return true
	return false


func _claimed_dests(model: MatchModel, team: int) -> Dictionary:
	var claimed: Dictionary = {}
	for plan in model.plans_for(team):
		claimed[plan.get("dest", Vector2i.ZERO)] = true
	return claimed


func _commit_sequence(model: MatchModel, seq: Dictionary, claimed: Dictionary) -> bool:
	if seq.is_empty() or (seq.get("actions", []) as Array).is_empty():
		return false
	var player_id := int(seq.get("player_id", -1))
	var queued_any := false
	for action in seq.actions:
		var queued: Dictionary = model.queue_plan(player_id, action)
		if not queued.get("ok", false):
			break
		queued_any = true
		var kind := str(action.get("id", ""))
		if kind in _RELOCATE_ACTIONS:
			claimed[action.get("dest", Vector2i.ZERO)] = true
	return queued_any


func _fill(model: MatchModel, skip_ids: Dictionary = {}, first_rank: int = 0) -> Dictionary:
	var claimed := _claimed_dests(model, model.current_team)
	var first_commit := true
	var meta := {first_id = -1, second = {}}
	while not model.planning_complete():
		var ranked := _ranked_sequences(model, claimed, skip_ids)
		var best := {}
		if first_commit:
			if not ranked.is_empty():
				meta.first_id = int(ranked[0].get("player_id", -1))
				if ranked.size() >= 2:
					meta.second = ranked[1]
				else:
					meta.second = ranked[0].get("second", {})
			if first_rank >= 1:
				if ranked.size() >= 2:
					best = ranked[1]
				else:
					var alt: Dictionary = ranked[0].get("second", {}) if not ranked.is_empty() else {}
					if not alt.is_empty() and not (alt.get("actions", []) as Array).is_empty():
						best = alt
					elif not ranked.is_empty():
						best = ranked[0]
			elif not ranked.is_empty():
				best = ranked[0]
			first_commit = false
		elif not ranked.is_empty():
			best = ranked[0]
		if best.is_empty() or (best.get("actions", []) as Array).is_empty():
			if not _mark_done(model):
				break
			continue
		if not _commit_sequence(model, best, claimed):
			if not _mark_done(model):
				break
	return meta


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


func _pick_sequence(
	model: MatchModel,
	claimed: Dictionary,
	skip_ids: Dictionary,
	first_rank: int
) -> Dictionary:
	var ranked := _ranked_sequences(model, claimed, skip_ids)
	if ranked.is_empty():
		return {}
	if first_rank >= 1:
		if ranked.size() >= 2:
			return ranked[1]
		var alt: Dictionary = ranked[0].get("second", {})
		if not alt.is_empty() and not (alt.get("actions", []) as Array).is_empty():
			return alt
	return ranked[0]


func _best_sequence(model: MatchModel, claimed: Dictionary, skip_ids: Dictionary = {}) -> Dictionary:
	var ranked := _ranked_sequences(model, claimed, skip_ids)
	if ranked.is_empty():
		return {}
	return ranked[0]


func _ranked_sequences(
	model: MatchModel,
	claimed: Dictionary,
	skip_ids: Dictionary
) -> Array[Dictionary]:
	var keep := _MIN_KEEP
	if model.plan_count() == 0:
		keep = -1000.0
	var ranked: Array[Dictionary] = []
	for player in _eligible_players(model, skip_ids):
		var seq := _beam_player(model, player, claimed)
		if seq.is_empty():
			continue
		var rank := float(seq.get("rank", seq.get("score", 0.0)))
		if rank <= keep:
			continue
		ranked.append(seq)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := float(a.get("rank", 0.0))
		var rb := float(b.get("rank", 0.0))
		if not is_equal_approx(ra, rb):
			return ra > rb
		var na := (a.get("actions", []) as Array).size()
		var nb := (b.get("actions", []) as Array).size()
		if na != nb:
			return na > nb
		return int(a.get("player_id", 0)) < int(b.get("player_id", 0))
	)
	return ranked


func _eligible_players(model: MatchModel, skip_ids: Dictionary = {}) -> Array[PlayerState]:
	var holder := model.planning_carrier()
	if (
		holder != null
		and holder.team == model.current_team
		and model.can_queue(holder)
		and model.acting_player_count() == 0
		and not skip_ids.has(holder.id)
	):
		return [holder]
	var scored: Array[Dictionary] = []
	for player in model.players:
		if skip_ids.has(player.id):
			continue
		if not model.can_select(player) or not model.can_queue(player):
			continue
		var focus := model.ball.pos
		if holder != null:
			focus = model.planning_pos(holder)
		scored.append({
			player = player,
			dist = MatchRules.chebyshev(model.planning_pos(player), focus),
		})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.dist) < int(b.dist)
	)
	var result: Array[PlayerState] = []
	var limit := mini(_NEAR_PLAYERS, scored.size())
	for i in limit:
		result.append(scored[i].player)
	return result


func _beam_player(live: MatchModel, player: PlayerState, claimed: Dictionary) -> Dictionary:
	var probe := live.clone()
	var committed_n := live.plans_of(player.id).size()
	var gen: Array[Dictionary] = [{actions = [], score = 0.0, rank = 0.0}]
	var best := {
		player_id = player.id,
		actions = [],
		score = -100000.0,
		rank = -100000.0,
	}
	var second := {
		player_id = player.id,
		actions = [],
		score = -100000.0,
		rank = -100000.0,
	}
	var depth := 0
	while not gen.is_empty() and depth <= MatchRules.PLAYER_ACTION_POINTS:
		depth += 1
		var next_gen: Array[Dictionary] = []
		for node in gen:
			_pop_to(probe, player.id, committed_n)
			if not _queue_actions(probe, player.id, node.actions):
				continue
			var actor := probe.player_by_id(player.id)
			if actor == null:
				continue
			var node_rank := float(node.score) + _prefix_bonus(probe, actor)
			if not (node.actions as Array).is_empty() and node_rank >= float(best.rank):
				if (
					not (best.actions as Array).is_empty()
					and _actions_key(best.actions) != _actions_key(node.actions)
					and float(best.rank) >= float(second.rank)
				):
					second = best
				best = {
					player_id = player.id,
					actions = node.actions,
					score = node.score,
					rank = node_rank,
				}
			elif (
				not (node.actions as Array).is_empty()
				and node_rank >= float(second.rank)
				and _actions_key(node.actions) != _actions_key(best.actions)
			):
				second = {
					player_id = player.id,
					actions = node.actions,
					score = node.score,
					rank = node_rank,
				}
			if _planning_in_opponent_net(probe, actor):
				continue
			if not probe.can_queue(actor):
				continue
			var prefix_n := probe.plans_of(player.id).size()
			var turns := _count_kind(node.actions, "turn")
			for action in _candidate_actions(probe, actor, claimed, turns):
				var step := _score(probe, actor, action, claimed)
				var queued: Dictionary = probe.queue_plan(player.id, action)
				if not queued.get("ok", false):
					_pop_to(probe, player.id, prefix_n)
					continue
				var child_score := float(node.score) + step
				var child_rank := child_score + _prefix_bonus(probe, actor)
				next_gen.append({
					actions = _with_action(node.actions, action),
					score = child_score,
					rank = child_rank,
				})
				_pop_to(probe, player.id, prefix_n)
		if next_gen.is_empty():
			break
		next_gen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ra := float(a.get("rank", 0.0))
			var rb := float(b.get("rank", 0.0))
			if not is_equal_approx(ra, rb):
				return ra > rb
			var na := (a.get("actions", []) as Array).size()
			var nb := (b.get("actions", []) as Array).size()
			return na > nb
		)
		if next_gen.size() > _BEAM_WIDTH:
			next_gen.resize(_BEAM_WIDTH)
		gen = next_gen
	if (best.actions as Array).is_empty():
		return {}
	if not (second.actions as Array).is_empty():
		best.second = second
	return best


func _actions_key(actions: Array) -> String:
	var parts := PackedStringArray()
	for action in actions:
		parts.append("%s:%s" % [action.get("id", ""), action.get("dest", Vector2i.ZERO)])
	return ",".join(parts)


func _queue_actions(model: MatchModel, player_id: int, actions: Array) -> bool:
	for action in actions:
		var queued: Dictionary = model.queue_plan(player_id, action)
		if not queued.get("ok", false):
			return false
	return true


func _pop_to(model: MatchModel, player_id: int, prefix_n: int) -> void:
	while model.plans_of(player_id).size() > prefix_n:
		if not model.pop_last_plan(player_id).get("ok", false):
			break


func _with_action(actions: Array, action: Dictionary) -> Array:
	var out: Array = actions.duplicate()
	out.append(action.duplicate())
	return out


## Legal commands from the model, ranked by 1-ply score. Skip planning-only `done`.
## New actions appear here automatically once they are in commands_for / command_dests.
func _candidate_actions(
	model: MatchModel,
	player: PlayerState,
	claimed: Dictionary,
	turns_already: int = 0
) -> Array[Dictionary]:
	var by_kind := {}
	for cmd in model.commands_for(player):
		var command_id := str(cmd.get("id", ""))
		if command_id == "" or command_id == "done":
			continue
		if command_id == "turn" and turns_already >= 2:
			continue
		var dests: Array = _search_dests(model, player, command_id, cmd.get("dests", []))
		var bucket: Array[Dictionary] = []
		for dest in dests:
			var action := model.action_for_command(player, command_id, dest)
			if action.is_empty():
				continue
			bucket.append({
				action = action,
				score = _score(model, player, action, claimed),
			})
		bucket.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.score) > float(b.score)
		)
		by_kind[command_id] = bucket
	var picked: Array[Dictionary] = []
	var seen := {}
	for kind in by_kind:
		var quota := int(_KIND_QUOTA.get(kind, 2))
		var bucket: Array = by_kind[kind]
		var taken := 0
		for i in bucket.size():
			if taken >= quota:
				break
			var action: Dictionary = bucket[i].action
			var key := "%s:%s" % [action.get("id", ""), action.get("dest", Vector2i.ZERO)]
			if seen.has(key):
				continue
			seen[key] = true
			picked.append(bucket[i])
			taken += 1
	picked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.score) > float(b.score)
	)
	var actions: Array[Dictionary] = []
	var limit := mini(_MAX_EXPAND, picked.size())
	for i in limit:
		actions.append(picked[i].action)
	return actions


func _search_dests(model: MatchModel, player: PlayerState, command_id: String, dests: Array) -> Array:
	if command_id != "pass":
		return dests
	var mates: Array[Vector2i] = []
	var dumps: Array[Dictionary] = []
	for dest in dests:
		var occupant := model.player_at(dest)
		if occupant != null and occupant.team == player.team:
			mates.append(dest)
			continue
		if occupant != null:
			continue
		var gain := _forward_gain(player.team, model.planning_pos(player), dest)
		if gain < 1.0:
			continue
		dumps.append({dest = dest, gain = gain})
	dumps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.gain) > float(b.gain)
	)
	var out: Array = []
	for cell in mates:
		out.append(cell)
	var dump_limit := mini(3, dumps.size())
	for i in dump_limit:
		out.append(dumps[i].dest)
	return out


func _count_kind(actions: Array, kind: String) -> int:
	var n := 0
	for action in actions:
		if str(action.get("id", "")) == kind:
			n += 1
	return n


func _planning_in_opponent_net(model: MatchModel, player: PlayerState) -> bool:
	return model.planning_pos(player) == MatchRules.opponent_goal(player.team)


func _prefix_bonus(model: MatchModel, player: PlayerState) -> float:
	var pos := model.planning_pos(player)
	var team := player.team
	var bonus := 0.0
	if model.planning_has_ball(player):
		bonus += 80.0 + 14.0 * _progress(team, pos)
		if pos == MatchRules.opponent_goal(team):
			bonus += 800.0
		elif model.can_plan_shoot(player):
			bonus += 400.0 * float(model.shot_preview(player).goal_chance)
	else:
		var ball_pos := model.ball.pos
		var holder := model.planning_carrier()
		if holder != null:
			ball_pos = model.planning_pos(holder)
		bonus += 8.0 * float(8 - MatchRules.chebyshev(pos, ball_pos))
		if _is_back(player) or player.role == "GK":
			var slot := _home_slot(player)
			bonus += 5.0 * float(6 - MatchRules.chebyshev(pos, slot))
		if player.role == "GK":
			var net := MatchRules.HOME_NET if team == MatchRules.Team.HOME else MatchRules.AWAY_NET
			bonus += 20.0 if pos == net else -25.0
	return bonus


func _score(model: MatchModel, player: PlayerState, action: Dictionary, claimed: Dictionary) -> float:
	var kind := str(action.get("id", ""))
	var dest: Vector2i = action.get("dest", model.planning_pos(player))
	var clash := 18.0 if claimed.has(dest) and kind in _RELOCATE_ACTIONS else 0.0
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
			value += 6.0 * _forward_gain(player.team, model.planning_pos(player), dest)
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
			value = _score_generic(model, player, dest)
	return value * energy - clash


func _score_generic(model: MatchModel, player: PlayerState, dest: Vector2i) -> float:
	var from := model.planning_pos(player)
	var gain := _forward_gain(player.team, from, dest)
	var value := 4.0 * gain
	if model.planning_has_ball(player):
		value += 10.0 * gain
		if dest == MatchRules.opponent_goal(player.team):
			value += 800.0
	else:
		var ball_pos := model.ball.pos
		value += 8.0 * float(
			MatchRules.chebyshev(from, ball_pos) - MatchRules.chebyshev(dest, ball_pos)
		)
	if dest == from:
		value += 0.6
	return value


func _score_pass(model: MatchModel, player: PlayerState, action: Dictionary, dest: Vector2i) -> float:
	var occupant := model.player_at(dest)
	if occupant != null and occupant.team != player.team:
		return -80.0
	var preview := model.pass_preview(player, dest)
	var through := float(preview.get("total", 1.0))
	var gain := _forward_gain(player.team, model.planning_pos(player), dest)
	var value := 42.0 * through * (1.0 + maxf(gain, 0.0) * 0.4)
	if occupant == null and int(action.get("target_id", -1)) < 0:
		value *= 0.3
	if bool(action.get("offside", false)) or bool(preview.get("offside", false)):
		value -= 90.0
	elif not preview.get("marked_ids", []).is_empty() and int(action.get("target_id", -1)) < 0:
		value -= 8.0
	if through < 0.28:
		value *= 0.35
	var receiver := occupant
	if receiver == null:
		receiver = model.player_by_id(int(action.get("target_id", -1)))
	if receiver != null and receiver.team == player.team:
		var goal := MatchRules.opponent_goal(player.team)
		var leftover := MatchRules.PLAYER_ACTION_POINTS
		if MatchRules.can_attempt_shot(dest, goal, receiver.live_accuracy(), leftover):
			var geo := MatchRules.shot_geometry(dest, goal)
			var hit := MatchRules.shot_hit_chance(
				receiver.live_accuracy(), geo.distance_m, geo.angle, leftover
			)
			var keeper := model.player_at(goal)
			var save := 0.0
			if keeper != null and keeper.team != player.team:
				var acc := MatchRules.shot_accuracy(receiver.live_accuracy(), leftover)
				save = 1.0 - MatchRules.contest_win_chance(acc, keeper.live_defense(), true)
			value += 280.0 * hit * (1.0 - save)
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
	var from := model.planning_pos(player)
	if model.planning_has_ball(player) and dest == MatchRules.opponent_goal(team):
		return 900.0
	var occupant := model.player_at(dest)
	if occupant != null:
		if occupant.team == team:
			return 0.4
		return _score_contest(model, player, dest, 8.0, 0.0)
	var value := 5.0 * _forward_gain(team, from, dest)
	if model.planning_has_ball(player):
		value += 18.0 * _forward_gain(team, from, dest)
	else:
		var ball_pos := model.ball.pos
		var closer := (
			MatchRules.chebyshev(from, ball_pos) - MatchRules.chebyshev(dest, ball_pos)
		)
		value += 14.0 * float(closer)
		if model.ball.is_loose() and dest == ball_pos and not model.would_collect_offside(player, dest):
			value += 40.0
		elif MatchRules.chebyshev(from, ball_pos) > 6:
			var slot := _home_slot(player)
			value += 4.0 * float(MatchRules.chebyshev(from, slot) - MatchRules.chebyshev(dest, slot))
	if model.would_collect_offside(player, dest):
		value -= 90.0
	var own_net := MatchRules.HOME_NET if team == MatchRules.Team.HOME else MatchRules.AWAY_NET
	if player.role == "GK" and dest != own_net:
		value -= 40.0
	var holder := model.carrier()
	if holder != null and holder.team != team and _is_back(player):
		var cover := (
			MatchRules.chebyshev(from, own_net) - MatchRules.chebyshev(dest, own_net)
		)
		value += 8.0 * float(cover)
	return value


func _score_turn(model: MatchModel, player: PlayerState, dest: Vector2i) -> float:
	var from := model.planning_pos(player)
	var new_face := MatchRules.step_direction(from, dest)
	if new_face == Vector2i.ZERO:
		return 0.0
	var ahead := from + new_face
	var current := model.planning_facing(player)
	var cur_ahead := from + current
	var value := 3.5 * _forward_gain(player.team, from, ahead)
	var aim := model.ball.pos
	if model.planning_has_ball(player):
		aim = MatchRules.opponent_goal(player.team)
	var closer := MatchRules.chebyshev(from, aim) - MatchRules.chebyshev(ahead, aim)
	value += 2.5 * float(closer)
	if _forward_gain(player.team, from, ahead) < _forward_gain(player.team, from, cur_ahead) and closer <= 0:
		value = minf(value, 0.15)
	return value


func _forward_gain(team: int, from: Vector2i, to: Vector2i) -> float:
	if team == MatchRules.Team.HOME:
		return float(to.x - from.x)
	return float(from.x - to.x)


func _progress(team: int, pos: Vector2i) -> float:
	if team == MatchRules.Team.HOME:
		return float(pos.x)
	return float(MatchRules.GRID_WIDTH - 1 - pos.x)


func _home_slot(player: PlayerState) -> Vector2i:
	for slot in Formation.slots(player.team, player.team):
		if int(slot.number) == player.number:
			return slot.pos
	return player.pos


func _possession_team(model: MatchModel) -> int:
	var holder := model.planning_carrier()
	if holder == null:
		return -1
	return holder.team


func _is_back(player: PlayerState) -> bool:
	return player.role in ["GK", "LB", "RB", "LCB", "RCB"]
