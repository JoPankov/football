class_name AiSelfPlay
extends RefCounted

## Node-free both-sides planner and headless match loop.
## Uses the existing greedy AiCoach independently on clones of one snapshot.

const DEFAULT_MAX_CYCLES := 40


static func fill_side(model: MatchModel) -> void:
	AiCoach.fill_plans(model)


static func fill_both_independently(live: MatchModel) -> void:
	var home_board := live.clone()
	var away_board := live.clone()
	_prepare_planning_copy(home_board, MatchRules.Team.HOME)
	_prepare_planning_copy(away_board, MatchRules.Team.AWAY)
	fill_side(home_board)
	fill_side(away_board)
	live.home_plans.clear()
	live.away_plans.clear()
	_commit_plans(live, home_board.home_plans)
	_commit_plans(live, away_board.away_plans)


static func resolve_cycle(model: MatchModel) -> Dictionary:
	return TurnResolver.resolve(model)


static func play_match(max_cycles: int = DEFAULT_MAX_CYCLES, seed: int = -1) -> Dictionary:
	var model := MatchModel.new()
	model.setup_kickoff()
	if seed >= 0:
		model.rng.seed = seed
	var cycles := 0
	while cycles < max_cycles:
		fill_both_independently(model)
		resolve_cycle(model)
		cycles += 1
	var holder := model.carrier()
	return {
		home_score = model.home_score,
		away_score = model.away_score,
		cycles = cycles,
		seed = seed,
		terminated = "cycles",
		carrier_id = model.ball.carrier_id,
		ball_pos = model.ball.pos,
		turn_index = model.turn_index,
		holder_pos = holder.pos if holder != null else model.ball.pos,
	}


static func _prepare_planning_copy(copy: MatchModel, team: int) -> void:
	copy.home_plans.clear()
	copy.away_plans.clear()
	copy.current_team = team
	copy.awaiting_other_side = false
	copy.ignore_team_gate = false


static func _commit_plans(live: MatchModel, plans: Array[Dictionary]) -> void:
	for plan in plans:
		var stored: Dictionary = plan.duplicate(true)
		live.plans_for(int(stored.get("team", 0))).append(stored)
		var player := live.player_by_id(int(stored.get("player_id", -1)))
		live.combat_log.event({
			ok = true,
			action = "queue",
			player_id = int(stored.get("player_id", -1)),
			team = int(stored.get("team", 0)),
			plan = stored,
			attacker_label = player.label() if player != null else "player",
			label = str(stored.get("label", stored.get("action", "act"))),
			plan_text = CombatLog.plan_summary(stored),
			dest = stored.get("dest", Vector2i.ZERO),
		})
