extends SceneTree

## Headless suite for the first slice: grid, movement, possession, turns.

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Sci-Fi Football tests ===")
	_test_bounds()
	_test_adjacency()
	_test_move_destinations()
	_test_facing()
	_test_action_points()
	_test_attacking_third()
	_test_offside_position()
	_test_kickoff()
	_test_helix_kickoff()
	_test_turn_and_selection()
	_test_possession()
	_test_ball_travels_with_carrier()
	_test_cannot_stack()
	_test_attributes()
	_test_dribble_win()
	_test_dribble_loss()
	_test_contest_bounce()
	_test_square_fight()
	_test_challenge_takes_ball()
	_test_tackle_direction()
	_test_contest_preview()
	_test_pass()
	_test_intercepts()
	_test_swap_and_choice()
	_test_offside()
	_test_shooting()
	_test_planning_and_resolve()
	_test_ap_waves()
	_test_game_settings()
	await _test_controller_click_flow()
	await _test_game_menu()
	await _test_vs_ai()
	if _failed == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		print("%d TEST(S) FAILED" % _failed)
		quit(1)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS  ", msg)
	else:
		print("  FAIL  ", msg)
		_failed += 1


func _spot(dx: int = 0, dy: int = 0) -> Vector2i:
	return MatchRules.CENTER_SPOT + Vector2i(dx, dy)


func _test_bounds() -> void:
	print("-- bounds")
	_assert(MatchRules.in_bounds(Vector2i(0, 0)), "origin in bounds")
	_assert(MatchRules.in_bounds(Vector2i(25, 12)), "far corner in bounds")
	_assert(MatchRules.in_bounds(MatchRules.HOME_NET), "aether net is playable")
	_assert(MatchRules.in_bounds(MatchRules.AWAY_NET), "helix net is playable")
	_assert(not MatchRules.in_bounds(Vector2i(-1, 0)), "negative x beside the net is out")
	_assert(not MatchRules.in_bounds(Vector2i(26, 0)), "x=26 beside the net is out")
	_assert(not MatchRules.in_bounds(Vector2i(-1, 2)), "net-adjacent off-pitch is out")
	_assert(not MatchRules.in_bounds(Vector2i(0, 13)), "y=13 out")
	var net_steps := MatchRules.move_destinations(MatchRules.HOME_NET, {})
	_assert(net_steps.size() == 3, "keeper in the net has 3 steps onto the pitch")
	_assert(Vector2i(0, MatchRules.CENTER_Y) in net_steps, "net opens onto the old goal-line tile")


func _test_adjacency() -> void:
	print("-- adjacency")
	_assert(MatchRules.is_adjacent(Vector2i(5, 4), Vector2i(6, 5)), "diagonal is 1 tile")
	_assert(MatchRules.is_adjacent(Vector2i(5, 4), Vector2i(5, 5)), "orthogonal is 1 tile")
	_assert(not MatchRules.is_adjacent(Vector2i(5, 4), Vector2i(5, 4)), "stay put is not a move")
	_assert(not MatchRules.is_adjacent(Vector2i(5, 4), Vector2i(7, 4)), "2 tiles is too far")


func _test_facing() -> void:
	print("-- facing")
	var from := Vector2i(8, 4)
	var east := Vector2i(1, 0)
	_assert(MatchRules.kickoff_facing(MatchRules.Team.HOME) == Vector2i(1, 0), "aether kickoff facing is +x")
	_assert(MatchRules.kickoff_facing(MatchRules.Team.AWAY) == Vector2i(-1, 0), "helix kickoff facing is -x")
	_assert(MatchRules.mirror_cell(MatchRules.CENTER_SPOT) == MatchRules.AWAY_SPOT, "helix kicking cell is 180° of aether's")
	_assert(MatchRules.mirror_cell(MatchRules.HOME_NET) == MatchRules.AWAY_NET, "nets swap under the pitch mirror")
	_assert(MatchRules.kickoff_spot(MatchRules.Team.HOME) == MatchRules.CENTER_SPOT, "aether kicks from the centre spot")
	_assert(MatchRules.kickoff_spot(MatchRules.Team.AWAY) == MatchRules.AWAY_SPOT, "helix kicks from the mirrored centre")
	_assert(MatchRules.step_direction(from, Vector2i(9, 5)) == Vector2i(1, 1), "step direction is 8-way")
	_assert(MatchRules.is_behind_step(from, Vector2i(7, 4), east), "west is behind when facing east")
	_assert(not MatchRules.is_behind_step(from, Vector2i(7, 3), east), "rear-diagonal is not the blocked step")
	_assert(not MatchRules.is_behind_step(from, Vector2i(9, 4), east), "forward is not behind")
	_assert(not MatchRules.is_back_pass(from, Vector2i(7, 4), east), "adjacent rear pass is allowed")
	_assert(MatchRules.is_back_pass(from, Vector2i(6, 4), east), "2 tiles directly back is a back pass")
	_assert(MatchRules.is_back_pass(from, Vector2i(6, 3), east), "2 back 1 side is inside 43°")
	_assert(not MatchRules.is_back_pass(from, Vector2i(6, 2), east), "45° rear-diagonal is outside 43°")
	_assert(not MatchRules.is_back_pass(from, Vector2i(10, 4), east), "forward pass is allowed")
	_assert(MatchRules.is_behind_step(from, Vector2i(7, 3), Vector2i(1, 1)), "diagonal facing blocks the opposite diagonal")

	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	_assert(st.facing == Vector2i(1, 0), "kickoff taker faces attack")
	_assert(_spot(-1, 0) not in model.valid_moves(st), "cannot step directly back")
	var refused := model.apply_move(st.id, _spot(-1, 0))
	_assert(not refused.ok, "apply_move rejects the rear square")
	_assert(st.pos == MatchRules.CENTER_SPOT and st.facing == Vector2i(1, 0), "failed back step does not turn")
	_assert(not model.can_pass_to_cell(st, _spot(-2, 0)), "cannot pass 2 tiles back")
	_assert(model.can_pass_to_cell(st, _spot(-1, 0)), "can still pass to the adjacent rear square")
	_assert(model.can_pass_to_cell(st, _spot(2, 0)), "can pass 2 tiles forward")

	var walked := model.apply_move(st.id, _spot(1, 0))
	_assert(walked.ok and st.facing == Vector2i(1, 0), "player faces the direction of the last move")
	_assert(MatchRules.CENTER_SPOT not in model.valid_moves(st), "cannot immediately step back to the previous tile")

	model.scripted_attacker_wins = true
	var press := model.player_at(MatchRules.AWAY_KICKOFF)
	press.pos = _spot(1, 1)
	var turned := model.apply_turn(st.id, press.pos)
	_assert(turned.ok and st.facing == Vector2i(0, 1), "turn 90° faces the clicked square")
	var dribble := model.apply_move(st.id, press.pos)
	_assert(dribble.ok and dribble.get("action") == "dribble", "dribble onto helix after turning")
	_assert(st.facing == Vector2i(0, 1), "dribbler faces the square they took")
	var away := model.player_at(_spot(1, 0))
	_assert(away != null and away.team == MatchRules.Team.AWAY, "shoved defender occupies the origin")
	_assert(away.facing == Vector2i(0, -1), "shoved defender faces the shove")
	_assert(st.pos not in model.valid_moves(away), "shoved player cannot immediately step back onto the dribbler")

	var swap_model := MatchModel.new()
	swap_model.setup_kickoff()
	var swap_st := swap_model.player_at(MatchRules.CENTER_SPOT)
	var partner := swap_model.player_at(_spot(0, -1))
	partner.pos = _spot(-1, 0)
	_assert(not swap_model.can_swap(swap_st, partner), "cannot swap onto the rear square")
	_assert(not swap_model.apply_swap(swap_st.id, partner.id).ok, "swap behind is rejected")
	partner.pos = _spot(0, -1)
	swap_st.facing = Vector2i(0, -1)
	var side_swap := swap_model.apply_swap(swap_st.id, partner.id)
	_assert(side_swap.ok, "side swap still works")
	_assert(swap_st.facing == Vector2i(0, -1), "swapper faces the tile they took")
	_assert(partner.facing == Vector2i(0, 1), "swapped teammate faces the tile they took")


func _test_action_points() -> void:
	print("-- action points")
	var east := Vector2i(1, 0)
	_assert(MatchRules.PLAYER_ACTION_POINTS == 6, "each player has 6 AP")
	_assert(MatchRules.move_facings(east).size() == 3, "move has 3 facings")
	_assert(Vector2i(1, 0) in MatchRules.move_facings(east), "move includes current facing")
	var turns := MatchRules.turn_facings(east)
	_assert(turns.size() == 4, "turn has 4 facings")
	_assert(Vector2i(1, 0) not in turns, "turn excludes current facing")
	_assert(Vector2i(-1, 0) not in turns, "turn excludes 180°")
	_assert(Vector2i(0, 1) in turns and Vector2i(0, -1) in turns, "turn includes 90°")
	_assert(MatchRules.rotate_facing(east, 4) == Vector2i(-1, 0), "four 45° steps is 180°")
	_assert(MatchRules.step_ap_cost(Vector2i(5, 5), Vector2i(6, 5)) == 2, "straight step costs 2 AP")
	_assert(MatchRules.step_ap_cost(Vector2i(5, 5), Vector2i(6, 6)) == 3, "diagonal step costs 3 AP")
	_assert(MatchRules.action_ap_cost("turn", Vector2i(5, 5), Vector2i(5, 6), 6) == 1, "turn costs 1 AP")
	_assert(MatchRules.action_ap_cost("pass", Vector2i(5, 5), Vector2i(7, 5), 6) == 1, "pass costs 1 AP")
	_assert(MatchRules.action_ap_cost("shoot", Vector2i(5, 5), MatchRules.AWAY_NET, 5) == 5, "shot spends leftover AP")
	_assert(MatchRules.action_ap_cost("shoot", Vector2i(5, 5), MatchRules.AWAY_NET, 1) == 1, "shot with 1 AP spends that point")
	_assert(MatchRules.action_ap_cost("done", Vector2i(5, 5), Vector2i(5, 5), 4) == 0, "done costs 0 AP")
	_assert(is_equal_approx(MatchRules.shot_ap_bonus(1), 0.03), "+3% hit per leftover AP")
	_assert(is_equal_approx(MatchRules.shot_ap_bonus(5), 0.15), "5 leftover AP is +15% hit")

	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	_assert(model.ap_spent(st.id) == 0, "fresh player has spent 0 AP")
	_assert(model.ap_remaining(st.id) == 6, "fresh player has 6 AP")
	_assert(_spot(1, 1) in model.command_dests(st, "move"), "diagonal is legal with a full AP pool")
	var first := model.queue_plan(st.id, {id = "move", dest = _spot(1, 0), label = "Move"})
	_assert(first.ok, "first AP queues")
	_assert(int(first.plan.get("ap_cost", 0)) == 2, "orthogonal move costs 2 AP")
	_assert(model.ap_spent(st.id) == 2 and model.can_queue(st), "4 AP remain after a straight step")
	_assert(model.acting_player_count() == 1, "one player is acting")
	var turn_dests := model.command_dests(st, "turn")
	_assert(not turn_dests.is_empty(), "turn dests exist after a queued move")
	var turn_cmd := model.action_for_command(st, "turn", turn_dests[0])
	_assert(not turn_cmd.is_empty() and turn_cmd.get("id") == "turn", "turn click maps after a queued move")
	var turn := model.queue_plan(st.id, turn_cmd)
	_assert(turn.ok, "leftover AP can be a turn")
	_assert(model.ap_spent(st.id) == 3, "straight move then turn spends 3 AP")
	_assert(model.can_queue(st), "player still has leftover AP")
	_assert(not model.planning_complete(), "other player slots remain")
	model.end_planning()
	var resolved := model.end_planning()
	_assert(resolved.get("action") == "resolve", "move then turn resolves")
	_assert(st.pos == _spot(1, 0), "move then turn ends on the stepped tile")
	_assert(
		st.facing == MatchRules.step_direction(_spot(1, 0), turn_dests[0]),
		"move then turn faces the clicked square"
	)

	var spend := MatchModel.new()
	spend.setup_kickoff()
	var runner := spend.player_at(MatchRules.CENTER_SPOT)
	_assert(spend.queue_plan(runner.id, {id = "move", dest = _spot(1, 0), label = "Move"}).ok, "first straight step queues")
	_assert(spend.queue_plan(runner.id, {id = "move", dest = _spot(2, 0), label = "Move"}).ok, "second straight step queues")
	_assert(spend.ap_spent(runner.id) == 4, "two straight steps spend 4 AP")
	_assert(_spot(3, 0) in spend.command_dests(runner, "move"), "2 leftover AP still allow a straight step")
	_assert(_spot(3, 1) not in spend.command_dests(runner, "move"), "2 leftover AP cannot afford a diagonal")
	var refused := spend.queue_plan(runner.id, {id = "move", dest = _spot(3, 1), label = "Move"})
	_assert(not refused.ok, "queue rejects a diagonal the player cannot afford")
	_assert(spend.queue_plan(runner.id, {id = "move", dest = _spot(3, 0), label = "Move"}).ok, "third straight step spends the last 2 AP")
	_assert(spend.ap_spent(runner.id) == 6, "three straight steps spend the full 6 AP")
	_assert(not spend.can_queue(runner), "player is out of AP")

	var diag := MatchModel.new()
	diag.setup_kickoff()
	var cutter := diag.player_at(MatchRules.CENTER_SPOT)
	var cut := diag.queue_plan(cutter.id, {id = "move", dest = _spot(1, 1), label = "Move"})
	_assert(cut.ok, "diagonal step queues")
	_assert(int(cut.plan.get("ap_cost", 0)) == 3, "diagonal move costs 3 AP")
	_assert(diag.ap_remaining(cutter.id) == 3, "3 AP remain after a diagonal")

	var shot_model := MatchModel.new()
	shot_model.setup_kickoff()
	var shooter := shot_model.player_at(MatchRules.CENTER_SPOT)
	shooter.pos = Vector2i(MatchRules.GRID_WIDTH - 1, MatchRules.CENTER_Y)
	shot_model.ball.pos = shooter.pos
	_assert(shot_model.can_plan_shoot(shooter), "penalty-box carrier can shoot")
	var full_shot := shot_model.queue_plan(shooter.id, {id = "shoot", dest = MatchRules.AWAY_NET, label = "Shoot"})
	_assert(full_shot.ok, "first-action shot queues")
	_assert(int(full_shot.plan.get("ap_cost", 0)) == 6, "shot spends every leftover AP")
	_assert(int(full_shot.plan.get("ap_left", 0)) == 6, "shot records leftover AP before the spend")
	_assert(shot_model.ap_spent(shooter.id) == 6, "shot ends the player's AP")
	_assert(not shot_model.can_queue(shooter), "player cannot queue after a shot")
	var preview6 := shot_model.shot_preview(shooter, 6)
	var preview1 := shot_model.shot_preview(shooter, 1)
	_assert(preview6.remaining_ap == 6, "preview accepts leftover AP")
	_assert(
		is_equal_approx(float(preview6.leftover_bonus), 0.18),
		"6 leftover AP is +18% hit"
	)
	_assert(
		is_equal_approx(float(preview1.leftover_bonus), 0.03),
		"1 leftover AP is +3% hit"
	)
	_assert(float(preview6.hit_chance) >= float(preview1.hit_chance), "more leftover AP hits more often")

	var paced := MatchModel.new()
	paced.setup_kickoff()
	var paced_st := paced.player_at(MatchRules.CENTER_SPOT)
	paced_st.pos = Vector2i(MatchRules.GRID_WIDTH - 1, MatchRules.CENTER_Y)
	paced.ball.pos = paced_st.pos
	var turn_away := paced.queue_plan(paced_st.id, {id = "turn", dest = Vector2i(MatchRules.GRID_WIDTH - 1, MatchRules.CENTER_Y - 1), label = "Turn"})
	_assert(turn_away.ok, "turn before a shot spends 1 AP")
	var leftover_shot := paced.queue_plan(paced_st.id, {id = "shoot", dest = MatchRules.AWAY_NET, label = "Shoot"})
	_assert(leftover_shot.ok, "shot after a turn still queues")
	_assert(int(leftover_shot.plan.get("ap_left", 0)) == 5, "shot after a 1-AP turn has 5 leftover")
	_assert(int(leftover_shot.plan.get("ap_cost", 0)) == 5, "that shot spends the remaining 5")
	_assert(not paced.can_queue(paced_st), "shot still ends the player's turn")

	var about := MatchModel.new()
	about.setup_kickoff()
	var kicker := about.player_at(MatchRules.CENTER_SPOT)
	var t1 := about.apply_turn(kicker.id, _spot(0, 1))
	_assert(t1.ok and kicker.facing == Vector2i(0, 1), "one turn is 90°")
	var t2 := about.apply_turn(kicker.id, _spot(-1, 0))
	_assert(t2.ok and kicker.facing == Vector2i(-1, 0), "second 90° turn completes a 180")
	_assert(not about.apply_turn(kicker.id, _spot(1, 0)).ok, "cannot turn 180 in one action")

	var parked := MatchModel.new()
	parked.setup_kickoff()
	var parker := parked.player_at(MatchRules.CENTER_SPOT)
	var ids: PackedStringArray = PackedStringArray()
	for command in parked.commands_for(parker):
		ids.append(str(command.get("id", "")))
	_assert("done" in ids, "action bar offers done while the player has leftover AP")
	var first_done := parked.queue_plan(parker.id, {id = "done", dest = parker.pos, label = "Done"})
	_assert(first_done.ok, "done queues with leftover AP")
	_assert(parked.player_is_done(parker.id), "queued done marks the player finished")
	_assert(parked.ap_remaining(parker.id) == 6, "done does not spend leftover AP")
	_assert(not parked.can_queue(parker), "a done player cannot queue more")
	_assert(parked.acting_player_count() == 1, "done occupies an acting slot")
	_assert(not parked.planning_complete(), "one done player is not a full side")
	_assert(not parked.queue_plan(parker.id, {id = "move", dest = _spot(1, 0), label = "Move"}).ok, "done blocks further actions")
	parked.clear_plan(parker.id)
	_assert(not parked.player_is_done(parker.id), "clearing the plan un-dones the player")
	_assert(parked.queue_plan(parker.id, {id = "move", dest = _spot(1, 0), label = "Move"}).ok, "after clearing, the player can act again")
	_assert(parked.queue_plan(parker.id, {id = "done", dest = _spot(1, 0), label = "Done"}).ok, "done still works after a queued move")
	_assert(parked.ap_remaining(parker.id) == 4, "done after a straight step leaves 4 AP unused")
	_assert(not parked.can_queue(parker), "done after a move still ends that player's planning")
	_fill_plans(parked, [])
	for player in parked.players:
		if player.team != MatchRules.Team.HOME or parked.plan_of(player.id).is_empty():
			continue
		if parked.player_is_done(player.id) or parked.ap_spent(player.id) >= MatchRules.PLAYER_ACTION_POINTS:
			continue
		_assert(parked.queue_plan(player.id, {id = "done", dest = parked.planning_pos(player), label = "Done"}).ok, "teammates can also mark done")
	_assert(parked.planning_complete(), "three finished players auto-complete the side")
	var energy_before := parker.energy
	parked.end_planning()
	_fill_plans(parked, [])
	var parked_resolve := parked.end_planning()
	_assert(parked_resolve.get("action") == "resolve", "done still lets the cycle resolve")
	_assert(parker.pos == _spot(1, 0), "the move before done still applies")
	_assert(parker.energy == energy_before - 1, "done does not spend energy")
	var saw_done := false
	for ev in parked_resolve.get("events", []):
		if str(ev.get("action", "")) == "done":
			saw_done = true
	_assert(not saw_done, "done is planning-only and is not resolved")


func _test_move_destinations() -> void:
	print("-- destinations")
	var center := MatchRules.move_destinations(Vector2i(5, 4), {})
	_assert(center.size() == 8, "open cell has 8 moves")
	var corner := MatchRules.move_destinations(Vector2i(0, 0), {})
	_assert(corner.size() == 3, "corner has 3 moves")
	var blocked := MatchRules.move_destinations(Vector2i(5, 4), {Vector2i(5, 5): true})
	_assert(blocked.size() == 7, "occupied neighbour is excluded")
	_assert(Vector2i(5, 5) not in blocked, "blocked cell missing from result")
	var faced := MatchRules.move_destinations(Vector2i(5, 4), {}, Vector2i(1, 0))
	_assert(faced.size() == 3, "move cone is three cells")
	_assert(Vector2i(6, 4) in faced, "forward is a move")
	_assert(Vector2i(6, 3) in faced, "forward-diagonal is a move")
	_assert(Vector2i(4, 4) not in faced, "square directly behind is not a move")
	_assert(Vector2i(4, 3) not in faced, "rear-diagonal is not a move")


func _test_attacking_third() -> void:
	print("-- attacking third")
	_assert(MatchRules.is_attacking_third(Vector2i(18, 0), MatchRules.Team.HOME), "home last third starts at x=18")
	_assert(not MatchRules.is_attacking_third(Vector2i(17, 0), MatchRules.Team.HOME), "x=17 is midfield for home")
	_assert(MatchRules.is_attacking_third(Vector2i(7, 0), MatchRules.Team.AWAY), "away last third ends at x=7")
	_assert(MatchRules.can_use_ball_action(true), "carrier may use ball actions later")
	_assert(not MatchRules.can_use_ball_action(false), "non-carrier cannot use ball actions")


func _test_offside_position() -> void:
	print("-- offside position")
	var line: Array[Vector2i] = [Vector2i(14, 3), Vector2i(14, 5), MatchRules.AWAY_NET]
	_assert(
		MatchRules.is_offside_position(MatchRules.Team.HOME, Vector2i(15, 4), Vector2i(12, 4), line),
		"ahead of the ball and only the keeper covering is offside"
	)
	_assert(
		not MatchRules.is_offside_position(MatchRules.Team.HOME, Vector2i(14, 4), Vector2i(12, 4), line),
		"level with two defenders is onside"
	)
	_assert(
		not MatchRules.is_offside_position(MatchRules.Team.HOME, Vector2i(15, 4), Vector2i(15, 3), line),
		"level with the ball is onside"
	)
	_assert(
		not MatchRules.is_offside_position(MatchRules.Team.HOME, Vector2i(8, 4), Vector2i(7, 4), line),
		"own half is never offside"
	)
	var home_line: Array[Vector2i] = [Vector2i(2, 3), Vector2i(2, 5), MatchRules.HOME_NET]
	_assert(
		MatchRules.is_offside_position(MatchRules.Team.AWAY, Vector2i(1, 4), Vector2i(3, 4), home_line),
		"helix ahead of the ball and last line is offside"
	)
	_assert(
		not MatchRules.is_offside_position(MatchRules.Team.AWAY, Vector2i(2, 4), Vector2i(3, 4), home_line),
		"helix level with two defenders is onside"
	)
	_assert(MatchRules.is_opponent_half(Vector2i(13, 0), MatchRules.Team.HOME), "x=13 is aether's attacking half")
	_assert(not MatchRules.is_opponent_half(Vector2i(12, 0), MatchRules.Team.HOME), "x=12 is aether's own half")


func _test_kickoff() -> void:
	print("-- kickoff")
	var model := MatchModel.new()
	model.setup_kickoff()
	_assert(model.players.size() == 22, "22 players on the pitch")
	var home := 0
	var away := 0
	var cells := {}
	for player in model.players:
		if player.team == MatchRules.Team.HOME:
			home += 1
		else:
			away += 1
		cells[player.pos] = true
	_assert(home == 11 and away == 11, "11v11")
	_assert(cells.size() == 22, "every player on a unique cell")
	_assert(model.current_team == MatchRules.Team.HOME, "home kicks off")
	var home_st := model.player_at(MatchRules.CENTER_SPOT)
	_assert(home_st != null and home_st.role == "ST", "home #9 ST takes kickoff")
	_assert(home_st.has_ball, "home starts in possession")
	_assert(not model.ball.is_loose(), "ball is not loose at kickoff")
	_assert(model.ball.pos == home_st.pos, "ball starts on the kickoff taker")
	_assert(model.player_at(MatchRules.HOME_NET).role == "GK", "aether keeper starts in the net")
	_assert(model.player_at(MatchRules.AWAY_NET).role == "GK", "helix keeper starts in the net")
	_assert(model.player_at(Vector2i(0, MatchRules.CENTER_Y)) == null, "goal-line tile in front of aether net is free")
	_assert(home_st.facing == Vector2i(1, 0), "aether faces +x at kickoff")
	var helix_st := model.player_at(MatchRules.AWAY_KICKOFF)
	_assert(helix_st != null and helix_st.role == "ST", "helix #9 starts on the away kickoff cell")
	_assert(helix_st.facing == Vector2i(-1, 0), "helix faces -x at kickoff")
	_assert(not MatchRules.is_adjacent(home_st.pos, helix_st.pos), "helix #9 cannot contest the first kickoff pass")
	_assert(MatchRules.chebyshev(home_st.pos, helix_st.pos) == 2, "helix #9 sits one cell off the centre")
	var helix_other := model.player_at(_spot(2, -1))
	_assert(helix_other != null and helix_other.role == "ST" and helix_other.team == MatchRules.Team.AWAY, "helix #10 also drops a cell toward their net")
	_assert(not MatchRules.is_adjacent(home_st.pos, helix_other.pos), "helix #10 cannot contest kickoff")
	var helix_cm := model.player_at(Vector2i(MatchRules.GRID_WIDTH - 9, MatchRules.CENTER_Y - 1))
	_assert(helix_cm != null and helix_cm.role == "RCM", "helix CMs sit one cell closer to their net")
	_assert(MatchRules.chebyshev(helix_st.pos, helix_cm.pos) == 3, "helix striker to CM is 3 Chebyshev tiles")


func _test_helix_kickoff() -> void:
	print("-- helix kickoff")
	var aether_kick := MatchModel.new()
	aether_kick.setup_kickoff(MatchRules.Team.HOME)
	var helix_kick := MatchModel.new()
	helix_kick.setup_kickoff(MatchRules.Team.AWAY)
	_assert(helix_kick.current_team == MatchRules.Team.AWAY, "helix plans first on its kickoff")
	var helix_taker := helix_kick.player_at(MatchRules.AWAY_SPOT)
	_assert(helix_taker != null and helix_taker.team == MatchRules.Team.AWAY and helix_taker.role == "ST", "helix #9 takes the mirrored centre")
	_assert(helix_taker.has_ball, "helix starts in possession on its kickoff")
	_assert(helix_kick.ball.pos == helix_taker.pos, "ball starts on the helix kickoff taker")
	_assert(helix_kick.player_at(MatchRules.CENTER_SPOT) == null, "aether's centre is empty when helix kicks")
	for player in aether_kick.players:
		var mirrored := helix_kick.player_at(MatchRules.mirror_cell(player.pos))
		_assert(mirrored != null, "every aether-kickoff cell has a mirrored occupant")
		_assert(mirrored.team == MatchRules.opposite_team(player.team), "mirrored occupant is the other team")
		_assert(mirrored.number == player.number and mirrored.role == player.role, "mirrored occupant keeps number and role")
	var aether_near := helix_kick.player_at(MatchRules.mirror_cell(MatchRules.AWAY_KICKOFF))
	_assert(aether_near != null and aether_near.team == MatchRules.Team.HOME and aether_near.role == "ST", "aether #9 sits in the mirrored receiving cell")
	_assert(not MatchRules.is_adjacent(helix_taker.pos, aether_near.pos), "aether strikers cannot contest helix's first pass")
	var locked := helix_kick.end_planning()
	_assert(locked.get("action") == "end_planning", "helix lock does not resolve the cycle")
	_assert(helix_kick.current_team == MatchRules.Team.HOME, "aether plans second on a helix kickoff")
	var resolved := helix_kick.end_planning()
	_assert(resolved.get("action") == "resolve", "aether lock resolves the helix-kickoff cycle")
	_assert(helix_kick.current_team == MatchRules.Team.HOME, "aether plans the next cycle after a helix kickoff")


func _test_turn_and_selection() -> void:
	print("-- turns")
	var model := MatchModel.new()
	model.setup_kickoff()
	var home := model.player_at(MatchRules.CENTER_SPOT)
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	_assert(model.can_select(home), "home can select own player")
	_assert(not model.can_select(away), "home cannot select helix")
	var illegal := model.apply_move(away.id, Vector2i(6, 3))
	_assert(not illegal.ok, "away cannot move during aether planning")
	var ok := model.apply_move(home.id, _spot(1, 0))
	_assert(ok.ok, "home ST can move with the ball")
	_assert(home.has_ball, "kickoff taker still has the ball after moving")
	_assert(model.current_team == MatchRules.Team.HOME, "planning team stays until End Turn")
	_assert(not model.can_select(away), "helix still cannot be selected")
	_assert(model.can_end_planning(), "end turn is allowed with no queued plan")


func _test_possession() -> void:
	print("-- possession")
	var model := MatchModel.new()
	model.setup_kickoff()
	var striker := model.player_at(MatchRules.CENTER_SPOT)
	_assert(striker.has_ball, "striker starts as carrier")
	_assert(model.ball.carrier_id == striker.id, "ball records the carrier")
	var result := model.apply_move(striker.id, _spot(1, 0))
	_assert(result.ok and not result.gained_possession, "moving with the ball is a normal carry")
	_assert(striker.has_ball, "striker kept possession")
	_assert(model.ball.pos == striker.pos, "ball cell matches carrier")


func _test_ball_travels_with_carrier() -> void:
	print("-- ball travel")
	var model := MatchModel.new()
	model.setup_kickoff()
	var striker := model.player_at(MatchRules.CENTER_SPOT)
	model.apply_move(striker.id, _spot(1, 0))
	model.ignore_team_gate = true
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	model.apply_move(away.id, _spot(1, 1))
	var carry := model.apply_move(striker.id, _spot(2, 0))
	_assert(carry.ok, "carrier can carry 1 tile")
	_assert(not carry.gained_possession, "already had the ball")
	_assert(model.ball.pos == _spot(2, 0), "ball followed the carrier")
	_assert(striker.has_ball, "possession kept")


func _test_cannot_stack() -> void:
	print("-- stacking")
	var model := MatchModel.new()
	model.setup_kickoff()
	var mid := model.player_at(_spot(-3, 1))
	var dest := MatchRules.CENTER_SPOT
	var result := model.apply_move(mid.id, dest)
	_assert(not result.ok, "cannot step onto a teammate")
	_assert(mid.pos == _spot(-3, 1), "mover stayed put")


func _test_attributes() -> void:
	print("-- attributes")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var gk := model.player_at(MatchRules.HOME_NET)
	var cm := model.player_at(_spot(-3, -1))
	var lb := model.player_at(Vector2i(2, 0))
	var lm := model.player_at(Vector2i(MatchRules.CENTER_SPOT.x - 3, 0))
	var cb := model.player_at(Vector2i(2, MatchRules.CENTER_Y - 1))
	_assert(st.role == "ST" and st.accuracy == 20 and st.defense == 10 and st.control == 15, "striker is 20/10/15")
	_assert(cm.role == "LCM" and cm.accuracy == 10 and cm.defense == 15 and cm.control == 15, "central mid is 10/15/15")
	_assert(lb.role == "LB" and lb.accuracy == 10 and lb.defense == 15 and lb.control == 15, "full back matches central mid")
	_assert(lm.role == "LM" and lm.accuracy == 15 and lm.defense == 10 and lm.control == 10, "wide mid is 15/10/10")
	_assert(cb.role == "LCB" and cb.accuracy == 10 and cb.defense == 20 and cb.control == 20, "centre back is 10/20/20")
	_assert(gk.role == "GK" and gk.accuracy == 10 and gk.defense == 20 and gk.control == 20, "keeper matches centre back")
	_assert(st.stamina == 10 and st.energy == 100 and st.max_energy == 100, "striker stamina fills a 10× energy pool")
	_assert(gk.stamina == 10 and gk.max_energy == 100, "keeper stamina matches the rest of the XI")
	_assert(cm.stamina == 10 and lb.stamina == 10 and lm.stamina == 10 and cb.stamina == 10, "every listed role has STA 10")
	_assert(st.live_accuracy() == 20, "full energy keeps printed stats")
	st.energy = 0
	_assert(st.live_accuracy() == 10, "empty energy halves ACC with rounding")
	_assert(st.live_defense() == 5, "empty energy halves DEF with rounding")
	st.energy = st.max_energy
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	away.pos = _spot(1, 1)
	_assert(away.pos in model.valid_moves(st), "opponent tile is a legal contest dest")
	_assert(away.pos in model.contest_moves(st), "opponent tile is listed as a contest")
	var tired := model.apply_move(st.id, _spot(1, 0))
	_assert(tired.ok, "move still works while spending energy")
	_assert(st.energy == 99, "a resolved move costs 1 energy")


func _test_dribble_win() -> void:
	print("-- dribble win")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	away.pos = _spot(1, 1)
	model.scripted_attacker_wins = true
	var result := model.apply_move(st.id, away.pos)
	_assert(result.action == "dribble", "on-ball step onto opponent is a dribble")
	_assert(result.attacker_stat_name == "CTR" and result.defender_stat_name == "DEF", "dribble is CTR vs DEF")
	_assert(result.contest_won, "scripted dribble succeeded")
	_assert(st.pos == _spot(1, 1), "dribbler took the square")
	_assert(away.pos == MatchRules.CENTER_SPOT, "beaten defender was shoved back")
	_assert(st.has_ball and not away.has_ball, "dribbler kept the ball")
	_assert(model.ball.pos == st.pos, "ball followed the successful dribble")


func _test_dribble_loss() -> void:
	print("-- dribble loss")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	away.pos = _spot(1, 1)
	model.scripted_attacker_wins = false
	var result := model.apply_move(st.id, away.pos)
	_assert(result.action == "dribble", "failed attempt is still a dribble")
	_assert(not result.contest_won, "scripted dribble failed")
	_assert(st.pos == MatchRules.CENTER_SPOT, "dribbler stayed put")
	_assert(away.pos == _spot(1, 1), "defender held the square")
	_assert(away.has_ball and not st.has_ball, "defender won the ball")
	_assert(result.lost_possession, "result reports lost possession")


func _test_contest_bounce() -> void:
	print("-- contest bounce")
	var interior := MatchRules.bounce_cells(Vector2i(10, 6))
	_assert(interior.size() == 9, "interior bounce has 9 cells")
	_assert(Vector2i(10, 6) in interior, "bounce can stay on the original cell")
	_assert(Vector2i(9, 5) in interior and Vector2i(11, 7) in interior, "bounce includes the 3×3 corners")
	var corner := MatchRules.bounce_cells(Vector2i(0, 0))
	_assert(corner.size() == 4, "pitch-corner bounce drops out-of-bounds cells")
	_assert(Vector2i(0, 0) in corner and Vector2i(1, 1) in corner, "corner bounce keeps the origin and the in-bounds diagonal")
	var net := MatchRules.bounce_cells(MatchRules.HOME_NET)
	_assert(MatchRules.HOME_NET in net, "a ball in the net can bounce in place")
	_assert(not Vector2i(-2, 6) in net, "bounce never leaves the playable grid")

	var stay := MatchModel.new()
	stay.setup_kickoff()
	var stay_st := stay.player_at(MatchRules.CENTER_SPOT)
	var stay_away := stay.player_at(MatchRules.AWAY_KICKOFF)
	stay_away.pos = _spot(1, 1)
	stay.scripted_contest_tie = true
	stay.scripted_bounce_cell = MatchRules.CENTER_SPOT
	var stay_result := stay.apply_move(stay_st.id, stay_away.pos)
	_assert(stay_result.action == "dribble", "tied dribble is still a dribble")
	_assert(stay_result.get("contest_tied", false) and stay_result.get("bounced", false), "tied dribble reports a bounce")
	_assert(not stay_result.get("contest_won", false), "a bounce is not a contest win")
	_assert(stay_st.pos == MatchRules.CENTER_SPOT and stay_away.pos == _spot(1, 1), "tied dribble leaves both players in place")
	_assert(stay_st.has_ball and stay.ball.pos == MatchRules.CENTER_SPOT, "bounce onto the original cell leaves the carrier with the ball")
	_assert(CombatLog.format_result(stay_result).contains("DRIBBLE BOUNCE"), "log names a dribble bounce")

	var loose := MatchModel.new()
	loose.setup_kickoff()
	var loose_st := loose.player_at(MatchRules.CENTER_SPOT)
	var loose_away := loose.player_at(MatchRules.AWAY_KICKOFF)
	loose_away.pos = _spot(1, 1)
	loose.scripted_contest_tie = true
	loose.scripted_bounce_cell = _spot(1, 0)
	var loose_result := loose.apply_move(loose_st.id, loose_away.pos)
	_assert(loose_result.get("bounced", false), "tied dribble onto an empty neighbour bounces")
	_assert(loose_result.get("bounce_cell") == _spot(1, 0), "bounce records the landing cell")
	_assert(loose_st.pos == MatchRules.CENTER_SPOT and loose_away.pos == _spot(1, 1), "players stay put when the ball bounces away")
	_assert(loose.ball.is_loose() and loose.ball.pos == _spot(1, 0), "ball is loose on the bounce cell")
	_assert(not loose_st.has_ball and not loose_away.has_ball, "neither contestant keeps a ball that bounced away")

	var steal := MatchModel.new()
	steal.setup_kickoff()
	var steal_st := steal.player_at(MatchRules.CENTER_SPOT)
	var steal_away := steal.player_at(MatchRules.AWAY_KICKOFF)
	steal_away.pos = _spot(1, 1)
	steal.scripted_contest_tie = true
	steal.scripted_bounce_cell = _spot(1, 1)
	var steal_result := steal.apply_move(steal_st.id, steal_away.pos)
	_assert(steal_result.get("bounced", false), "tied dribble can bounce onto the defender")
	_assert(steal_away.has_ball and not steal_st.has_ball, "defender collects a bounce onto their cell")
	_assert(steal.ball.pos == steal_away.pos, "ball sits with the player who collected the bounce")

	var poke := MatchModel.new()
	poke.setup_kickoff()
	var poke_st := poke.player_at(MatchRules.CENTER_SPOT)
	var poke_decoy := poke.player_at(Vector2i(MatchRules.CENTER_SPOT.x - 3, 0))
	poke.apply_move(poke_decoy.id, Vector2i(MatchRules.CENTER_SPOT.x - 3, 1))
	var poke_away := poke.player_at(MatchRules.AWAY_KICKOFF)
	poke_away.pos = _spot(1, 1)
	poke.scripted_contest_tie = true
	poke.scripted_bounce_cell = _spot(0, 1)
	poke.ignore_team_gate = true
	var poke_result := poke.apply_move(poke_away.id, MatchRules.CENTER_SPOT)
	_assert(poke_result.action == "tackle", "tied tackle is still a tackle")
	_assert(poke_result.get("contest_tied", false) and poke_result.get("bounced", false), "tied tackle reports a bounce")
	_assert(poke_away.pos == _spot(1, 1) and poke_st.pos == MatchRules.CENTER_SPOT, "tied tackle leaves both players in place")
	_assert(poke.ball.is_loose() and poke.ball.pos == _spot(0, 1), "tied tackle dumps the ball onto the bounce cell")
	_assert(not poke_st.has_ball and not poke_away.has_ball, "neither player keeps the ball after a tackle bounce")
	_assert(CombatLog.format_result(poke_result).contains("TACKLE BOUNCE"), "log names a tackle bounce")


func _test_square_fight() -> void:
	print("-- square fight")
	var model := MatchModel.new()
	model.setup_kickoff()
	var home := model.player_at(_spot(0, -1))
	var away := model.player_at(_spot(2, -1))
	away.pos = _spot(1, -1)
	_assert(not home.has_ball and not away.has_ball, "off-ball challenge starts without possession")
	model.scripted_attacker_wins = true
	var win := model.apply_move(home.id, away.pos)
	_assert(win.action == "challenge", "off-ball step onto opponent is a square fight")
	_assert(win.attacker_stat_name == "CTR" and win.defender_stat_name == "CTR", "square fight is CTR vs CTR")
	_assert(home.pos == _spot(1, -1), "winner took the square")
	_assert(away.pos == _spot(0, -1), "loser was shoved to the origin")
	_assert(not home.has_ball and not away.has_ball, "no ball changed hands")

	model.scripted_attacker_wins = false
	model.ignore_team_gate = true
	var origin := away.pos
	var dest := home.pos
	away.facing = MatchRules.step_direction(origin, dest)
	var lose := model.apply_move(away.id, dest)
	_assert(lose.action == "challenge", "second contest is still a square fight")
	_assert(not lose.contest_won, "scripted fight failed")
	_assert(away.pos == origin, "failed challenger stayed put")
	_assert(home.pos == dest, "occupant kept the square")


func _test_challenge_takes_ball() -> void:
	print("-- challenge takes ball")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var decoy := model.player_at(Vector2i(MatchRules.CENTER_SPOT.x - 3, 0))
	model.apply_move(decoy.id, Vector2i(MatchRules.CENTER_SPOT.x - 3, 1))
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	away.pos = _spot(1, 1)
	model.scripted_attacker_wins = true
	model.ignore_team_gate = true
	var result := model.apply_move(away.id, MatchRules.CENTER_SPOT)
	_assert(result.get("action") == "tackle", "off-ball step onto the carrier is a tackle")
	_assert(result.get("attacker_stat_name") == "DEF" and result.get("defender_stat_name") == "CTR", "tackle is DEF vs CTR")
	_assert(result.get("attacker_label") == away.label(), "log names the tackler")
	_assert(result.get("defender_label") == st.label(), "log names the carrier")
	_assert(result.get("gained_possession"), "winner of the tackle took the ball")
	_assert(away.has_ball and not st.has_ball, "challenger is the new carrier")
	_assert(away.pos == MatchRules.CENTER_SPOT and st.pos == _spot(1, 1), "players swapped")
	_assert(
		away.facing == MatchRules.step_direction(st.pos, away.pos),
		"tackle winner turns their back to the player they stole from"
	)


func _test_tackle_direction() -> void:
	print("-- tackle direction")
	var east := Vector2i(1, 0)
	var origin := Vector2i(8, 4)
	_assert(MatchRules.tackle_approach_angle_deg(east, origin + Vector2i(1, 0), origin) == 0, "cell ahead is a front tackle")
	_assert(MatchRules.tackle_approach_angle_deg(east, origin + Vector2i(1, 1), origin) == 45, "forward-diagonal is 45°")
	_assert(MatchRules.tackle_approach_angle_deg(east, origin + Vector2i(0, 1), origin) == 90, "cell to the side is 90°")
	_assert(MatchRules.tackle_approach_angle_deg(east, origin + Vector2i(-1, 1), origin) == 135, "rear-diagonal is 135°")
	_assert(MatchRules.tackle_approach_angle_deg(east, origin + Vector2i(-1, 0), origin) == 180, "cell behind is a back tackle")
	_assert(MatchRules.tackle_approach_angle_deg(east, origin + Vector2i(-1, -1), origin) == 135, "the other rear-diagonal is also 135°")
	_assert(MatchRules.tackle_angle_penalty(0) == 0.0, "front tackle has no penalty")
	_assert(MatchRules.tackle_angle_penalty(45) == -0.15, "45° costs 15 percentage points")
	_assert(MatchRules.tackle_angle_penalty(90) == -0.30, "side costs 30 percentage points")
	_assert(MatchRules.tackle_angle_penalty(135) == -0.50, "135° costs 50 percentage points")
	_assert(MatchRules.tackle_angle_penalty(180) == -0.85, "back tackle costs 85 percentage points")
	_assert(MatchRules.tackle_angle_label(90) == "side", "90° is labelled side")
	_assert(MatchRules.tackle_angle_label(180) == "back", "180° is labelled back")
	var even := MatchRules.contest_win_chance(9, 9, false)
	_assert(
		absi(MatchRules.apply_tackle_angle_chance(even, -0.30) - clampf(even - 0.30, 0.0, 1.0)) < 0.0001,
		"side penalty subtracts 30 percentage points from success"
	)
	_assert(MatchRules.apply_tackle_angle_chance(even, -0.85) == 0.0, "back penalty can clamp success to 0")

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var lost_back := {
		attacker_won = true,
		tied = false,
		attacker_stat = 9,
		defender_stat = 9,
	}
	MatchRules.apply_tackle_direction_penalty(lost_back, -0.85, rng)
	_assert(not bool(lost_back.attacker_won), "a 0% back tackle drops a dice win")
	var kept_front := {
		attacker_won = true,
		tied = false,
		attacker_stat = 9,
		defender_stat = 9,
	}
	MatchRules.apply_tackle_direction_penalty(kept_front, 0.0, rng)
	_assert(bool(kept_front.attacker_won), "front tackles do not drop a dice win")

	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var cb := model.player_at(Vector2i(MatchRules.GRID_WIDTH - 3, MatchRules.CENTER_Y - 1))
	_assert(cb != null and cb.role == "RCB" and cb.team == MatchRules.Team.AWAY, "helix centre back is the high-DEF tackler")
	st.facing = Vector2i(1, 0)
	cb.pos = _spot(1, 0)
	var base := MatchRules.contest_win_chance(cb.live_defense(), st.live_control(), false)
	var front := MatchRules.contest_preview(cb, st)
	_assert(front.action == "tackle" and int(front.angle_deg) == 0, "preview from ahead is a front tackle")
	_assert(absi(float(front.chance) - base) < 0.0001, "front preview chance matches DEF vs CTR")
	_assert(not front.text.contains("front"), "front preview omits a 0% penalty suffix")
	cb.pos = _spot(1, 1)
	var diag := MatchRules.contest_preview(cb, st)
	_assert(int(diag.angle_deg) == 45, "forward-diagonal preview is 45°")
	_assert(
		absi(float(diag.chance) - MatchRules.apply_tackle_angle_chance(base, -0.15)) < 0.0001,
		"45° preview subtracts 15 percentage points"
	)
	_assert(diag.text.contains("45° -15%"), "45° preview names the penalty")
	cb.pos = _spot(0, 1)
	var side := MatchRules.contest_preview(cb, st)
	_assert(int(side.angle_deg) == 90 and side.angle_label == "side", "preview from the wing is a side tackle")
	_assert(
		absi(float(side.chance) - MatchRules.apply_tackle_angle_chance(base, -0.30)) < 0.0001,
		"side preview subtracts 30 percentage points"
	)
	_assert(side.text.contains("side -30%"), "side preview names the penalty")
	cb.pos = _spot(-1, 1)
	var rear_diag := MatchRules.contest_preview(cb, st)
	_assert(int(rear_diag.angle_deg) == 135, "rear-diagonal preview is 135°")
	_assert(
		absi(float(rear_diag.chance) - MatchRules.apply_tackle_angle_chance(base, -0.50)) < 0.0001,
		"135° preview subtracts 50 percentage points"
	)
	cb.pos = _spot(-1, 0)
	var back := MatchRules.contest_preview(cb, st)
	_assert(int(back.angle_deg) == 180 and back.angle_label == "back", "preview from behind is a back tackle")
	_assert(absi(float(back.chance) - 0.0) < 0.0001, "back preview is clamped to 0% with these stats")
	_assert(back.text.contains("back -85%"), "back preview names the penalty")
	_assert(back.percent == 0, "HUD percent is 0 for an impossible back tackle")

	var steal := MatchModel.new()
	steal.setup_kickoff()
	var steal_st := steal.player_at(MatchRules.CENTER_SPOT)
	var steal_cb := steal.player_at(Vector2i(MatchRules.GRID_WIDTH - 3, MatchRules.CENTER_Y - 1))
	var steal_decoy := steal.player_at(Vector2i(MatchRules.CENTER_SPOT.x - 3, 0))
	steal.apply_move(steal_decoy.id, Vector2i(MatchRules.CENTER_SPOT.x - 3, 1))
	steal_cb.pos = _spot(1, 0)
	steal_cb.facing = Vector2i(-1, 0)
	steal.scripted_attacker_wins = true
	steal.ignore_team_gate = true
	var won := steal.apply_move(steal_cb.id, MatchRules.CENTER_SPOT)
	_assert(won.action == "tackle" and won.get("gained_possession"), "scripted front tackle still steals")
	_assert(int(won.get("angle_deg", -1)) == 0, "resolved front tackle records 0°")
	_assert(
		steal_cb.facing == MatchRules.step_direction(steal_st.pos, steal_cb.pos),
		"swap-tackle winner faces away from the old carrier"
	)
	_assert(CombatLog.format_result(won).contains("(front)"), "log names a front tackle")

	var from_behind := MatchModel.new()
	from_behind.setup_kickoff()
	var back_st := from_behind.player_at(MatchRules.CENTER_SPOT)
	var back_cb := from_behind.player_at(Vector2i(MatchRules.GRID_WIDTH - 3, MatchRules.CENTER_Y - 1))
	var back_decoy := from_behind.player_at(Vector2i(MatchRules.CENTER_SPOT.x - 3, 0))
	from_behind.apply_move(back_decoy.id, Vector2i(MatchRules.CENTER_SPOT.x - 3, 1))
	back_st.facing = Vector2i(1, 0)
	back_cb.pos = _spot(-1, 0)
	back_cb.facing = Vector2i(1, 0)
	from_behind.scripted_attacker_wins = false
	from_behind.ignore_team_gate = true
	var poke := from_behind.apply_move(back_cb.id, MatchRules.CENTER_SPOT)
	_assert(poke.action == "tackle", "back-angle step is still a tackle")
	_assert(int(poke.get("angle_deg", -1)) == 180, "resolved back tackle records 180°")
	_assert(not poke.get("contest_won", true), "failed back tackle does not steal")
	_assert(back_st.has_ball and back_st.pos == MatchRules.CENTER_SPOT, "carrier keeps the ball on a failed back tackle")
	_assert(back_cb.pos == _spot(-1, 0), "failed back tackler stays put")
	_assert(CombatLog.format_result(poke).contains("back -85%"), "log names the back-tackle penalty")


func _test_contest_preview() -> void:
	print("-- contest preview")
	_assert(MatchRules.scaled_stat(13, 0, 9) == 7, "zero energy scales 13 to 7")
	_assert(MatchRules.scaled_stat(13, 9, 9) == 13, "full energy keeps 13")
	_assert(MatchRules.PASS_RANGE == 5, "pass radius is 5 tile lengths")
	_assert(MatchRules.in_pass_range(Vector2i(0, 0), Vector2i(5, 0)), "orthogonal 5 is on the pass circle")
	_assert(MatchRules.in_pass_range(Vector2i(0, 0), Vector2i(4, 3)), "4,3 sits on the pass circle")
	_assert(MatchRules.in_pass_range(Vector2i(0, 0), Vector2i(3, 3)), "diagonal 3 is inside the pass circle")
	_assert(not MatchRules.in_pass_range(Vector2i(0, 0), Vector2i(5, 1)), "offset 5,1 is outside the pass circle")
	_assert(not MatchRules.in_pass_range(Vector2i(0, 0), Vector2i(4, 4)), "diagonal 4 is outside the pass circle")
	var even := MatchRules.contest_win_chance(9, 9, false)
	_assert(absi(even - 36.0 / 81.0) < 0.0001, "even 1d9 contest is 36/81 (ties to occupant)")
	var even_ball := MatchRules.contest_win_chance(9, 9, true)
	_assert(absi(even_ball - 45.0 / 81.0) < 0.0001, "even 1d9 contest is 45/81 (ties to the ball)")
	var dribble_favors := MatchRules.contest_win_chance(9, 9, true) > MatchRules.contest_win_chance(9, 9, false)
	_assert(dribble_favors, "ball-team ties raise the attacker win chance")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var dice_ok := true
	for _i in 40:
		var rolled := MatchRules.resolve_contest(9, 4, rng, true)
		if (
			rolled.attacker_dice < 1 or rolled.attacker_dice > 9
			or rolled.defender_dice < 1 or rolled.defender_dice > 4
		):
			dice_ok = false
	_assert(dice_ok, "1dSTAT rolls stay inside 1..stat")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	var preview := MatchRules.contest_preview(st, away)
	_assert(preview.action == "dribble", "preview of carrier vs opponent is a dribble")
	_assert(preview.text.contains(away.label()), "hint names the opponent")
	_assert(preview.text.contains("%d CTR" % st.control), "hint shows mover CTR")
	_assert(preview.text.contains("%d DEF" % away.defense), "hint shows occupant DEF")
	_assert(preview.text.contains("%d%% success" % preview.percent), "hint shows success percent")
	var decoy := model.player_at(Vector2i(MatchRules.CENTER_SPOT.x - 3, 0))
	model.apply_move(decoy.id, Vector2i(MatchRules.CENTER_SPOT.x - 3, 0))
	away.pos = _spot(1, 0)
	st.facing = Vector2i(1, 0)
	var tackle := MatchRules.contest_preview(away, st)
	_assert(tackle.action == "tackle", "preview of off-ball vs carrier is a tackle")
	_assert(tackle.text.begins_with("tackle "), "tackle hint starts with tackle")
	_assert(tackle.text.contains("%d DEF" % away.defense), "tackle hint uses mover DEF")
	_assert(tackle.text.contains("%d CTR" % st.control), "tackle hint uses carrier CTR")
	var front_chance := MatchRules.contest_win_chance(away.live_defense(), st.live_control(), false)
	_assert(int(tackle.get("angle_deg", -1)) == 0, "head-on preview is a front tackle")
	_assert(
		absi(float(tackle.chance) - front_chance) < 0.0001,
		"front tackle preview keeps the raw DEF vs CTR chance"
	)
	_assert(MatchRules.attacker_wins_ties(st, away), "the ball-holder still wins non-bounce ties")
	_assert(not MatchRules.attacker_wins_ties(away, st), "the ball-holder still wins non-bounce ties against a tackler")
	_assert(
		absi(float(preview.chance) - MatchRules.contest_win_chance(st.live_control(), away.live_defense(), false)) < 0.0001,
		"dribble success ignores ties — those bounce the ball"
	)
	var decoy_vs_wing := MatchRules.attacker_wins_ties(
		decoy, model.player_at(Vector2i(MatchRules.GRID_WIDTH - 10, 0)), MatchRules.Team.HOME
	)
	_assert(decoy_vs_wing, "square fight ties go to the team in possession")


func _test_pass() -> void:
	print("-- pass")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var near := model.player_at(_spot(0, -1))
	var gk := model.player_at(MatchRules.HOME_NET)
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	_assert(model.can_pass_to(st, near), "can pass to a teammate within range")
	_assert(not MatchRules.in_pass_range(st.pos, gk.pos), "keeper in the net is beyond pass range")
	_assert(not model.can_pass_to(st, gk), "cannot pass beyond the pass circle")
	_assert(not model.can_pass_to(st, away), "cannot pass to an opponent")
	_assert(not model.can_pass_to(near, st), "non-carrier cannot pass")
	model.scripted_first_intercept_wins = false
	var result := model.apply_pass(st.id, near.id)
	_assert(result.ok and result.action == "pass", "pass succeeds")
	_assert(near.has_ball and not st.has_ball, "receiver has the ball")
	_assert(model.ball.pos == near.pos, "ball moved to the receiver")
	_assert(st.pos == MatchRules.CENTER_SPOT and near.pos == _spot(0, -1), "neither player moved")
	_assert(model.current_team == MatchRules.Team.HOME, "a pass does not switch the planning team")
	_assert(not model.can_queue(away), "helix still cannot queue during aether planning")

	var open := MatchModel.new()
	open.setup_kickoff()
	var kicker := open.player_at(MatchRules.CENTER_SPOT)
	_assert(open.can_pass_to_cell(kicker, _spot(0, 1)), "can pass to an empty adjacent square")
	_assert(open.can_pass_to_cell(kicker, _spot(2, 0)), "can pass to an empty square 2 tiles away")
	_assert(open.can_pass_to_cell(kicker, _spot(5, 0)), "can pass onto the orthogonal edge of the circle")
	_assert(open.can_pass_to_cell(kicker, _spot(4, 3)), "can pass onto a 4,3 cell on the circle")
	_assert(not open.can_pass_to_cell(kicker, _spot(5, 2)), "cannot pass to a 5,2 cell outside the circle")
	_assert(not open.can_pass_to_cell(kicker, _spot(4, 4)), "cannot pass to a square-corner cell")
	_assert(not open.can_pass_to_cell(kicker, _spot(6, 0)), "cannot pass 6 tiles to empty")
	_assert(_spot(5, 0) in open.pass_cells(kicker), "pass highlights include the orthogonal edge")
	_assert(_spot(4, 3) in open.pass_cells(kicker), "pass highlights include 4,3 on the circle")
	_assert(_spot(5, 2) not in open.pass_cells(kicker), "pass highlights omit 5,2 outside the circle")
	_assert(_spot(4, 4) not in open.pass_cells(kicker), "pass highlights omit the square corners")
	var empty_actions := open.actions_for(kicker, _spot(1, 0))
	_assert(empty_actions.size() == 2, "adjacent empty square is move or pass")
	_assert(empty_actions[0].id == "move" and empty_actions[1].id == "pass", "move and pass are both offered")
	var through := open.actions_for(kicker, _spot(2, 0))
	_assert(through.size() == 1 and through[0].id == "pass", "empty square 2 tiles away is pass only")
	open.scripted_first_intercept_wins = false
	var laid := open.apply_pass_to(kicker.id, _spot(2, 0))
	_assert(laid.ok and laid.action == "pass", "pass to empty square succeeds")
	_assert(int(laid.get("receiver_id", 0)) < 0, "empty-square pass has no receiver")
	_assert(laid.dest == _spot(2, 0), "empty-square pass records the landing tile")
	_assert(not kicker.has_ball, "passer released the ball")
	_assert(open.ball.is_loose() and open.ball.pos == _spot(2, 0), "ball sits loose on the target square")
	_assert(kicker.pos == MatchRules.CENTER_SPOT, "passer stayed put")

	var back := MatchModel.new()
	back.setup_kickoff()
	var back_st := back.player_at(MatchRules.CENTER_SPOT)
	var back_gk := back.player_at(MatchRules.HOME_NET)
	var back_lcb := back.player_at(Vector2i(2, MatchRules.CENTER_Y - 1))
	back_lcb.pos = Vector2i(2, MatchRules.CENTER_Y)
	back_st.pos = Vector2i(5, MatchRules.CENTER_Y)
	back_st.facing = Vector2i(-1, 0)
	back.ball.pos = back_st.pos
	back.scripted_first_intercept_wins = false
	var to_cb := back.apply_pass(back_st.id, back_lcb.id)
	_assert(to_cb.ok and back_lcb.has_ball, "back line can receive a 3-tile orthogonal pass")
	back_lcb.facing = Vector2i(-1, 0)
	_assert(back.can_pass_to(back_lcb, back_gk), "can pass to the keeper in the net")
	_assert(MatchRules.HOME_NET in back.pass_cells(back_lcb), "own net highlights as a pass tile")
	_assert(not back.can_pass_to_cell(back_lcb, MatchRules.AWAY_NET), "cannot pass into the opponent net")
	var gk_spot := back_gk.pos
	back_gk.pos = Vector2i(0, MatchRules.CENTER_Y)
	_assert(not back.can_pass_to_cell(back_lcb, gk_spot), "cannot pass into an empty net")
	back_gk.pos = gk_spot
	var to_gk := back.apply_pass(back_lcb.id, back_gk.id)
	_assert(to_gk.ok and to_gk.action == "pass", "pass to the keeper in the net succeeds")
	_assert(back_gk.has_ball and not back_lcb.has_ball, "keeper in the net received the ball")
	_assert(back.ball.pos == MatchRules.HOME_NET, "ball sits on the net tile")
	_assert(back_gk.pos == MatchRules.HOME_NET, "keeper stayed in the net")


func _test_intercepts() -> void:
	print("-- intercepts")
	var radius := MatchRules.INTERCEPT_RADIUS
	var along := MatchRules.segment_intersects_circle(Vector2(0, 0), Vector2(4, 0), Vector2(2, 0), radius)
	_assert(along.hits, "player on the pass line intercepts")
	var touch := MatchRules.segment_intersects_circle(Vector2(0, 0), Vector2(4, 0), Vector2(2, radius), radius)
	_assert(touch.hits, "radius 1 touching the line intercepts")
	var miss := MatchRules.segment_intersects_circle(Vector2(0, 0), Vector2(4, 0), Vector2(2, radius + 0.01), radius)
	_assert(not miss.hits, "just outside the radius does not intercept")
	var beside_start := MatchRules.segment_intersects_circle(Vector2(0, 0), Vector2(4, 0), Vector2(0, 1), radius)
	_assert(not beside_start.hits, "player only next to the passer does not intercept")
	_assert(is_equal_approx(MatchRules.intercept_reach_factor(0.0), 1.0), "on the lane keeps full intercept chance")
	_assert(
		is_equal_approx(MatchRules.intercept_reach_factor(1.0), 0.5),
		"1 tile off the lane keeps half intercept chance"
	)
	_assert(
		MatchRules.intercept_reach_factor(0.5) > MatchRules.intercept_reach_factor(1.0),
		"reach falls as the interceptor sits further off the lane"
	)
	var on_lane := MatchRules.intercept_through_chance(16, 8, 0.0)
	var off_lane := MatchRules.intercept_through_chance(16, 8, 1.0)
	var raw_through := MatchRules.contest_win_chance(16, 8, true)
	_assert(is_equal_approx(on_lane, raw_through), "on-lane through chance is the raw ACC vs DEF contest")
	_assert(off_lane > on_lane, "1 tile off the lane is easier to pass through")
	_assert(
		is_equal_approx(1.0 - off_lane, (1.0 - on_lane) * MatchRules.intercept_reach_factor(1.0)),
		"off-lane intercept chance is scaled by reach"
	)

	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var lane := _spot(3, 0)
	var threats := model.interceptors_for_pass(st, lane)
	_assert(threats.size() >= 2, "a lane through midfield has interceptors")
	for threat in threats:
		var expected := MatchRules.intercept_through_chance(
			st.live_accuracy(), threat.player.live_defense(), float(threat.dist)
		)
		_assert(
			is_equal_approx(float(threat.through), expected),
			"threat through chance includes the off-lane penalty"
		)
		if float(threat.dist) > 0.05:
			_assert(
				float(threat.through) > MatchRules.contest_win_chance(
					st.live_accuracy(), threat.player.live_defense(), true
				),
				"off-lane interceptor is easier to beat than the raw contest"
			)
	var preview := model.pass_preview(st, lane)
	_assert(preview.text.contains("ACC vs"), "preview lists ACC vs DEF")
	_assert(preview.text.contains("tiles off"), "preview shows distance off the lane")
	_assert(preview.text.contains("Pass success:"), "preview shows total pass success")
	_assert(
		preview.text.contains("intercept") or preview.total < 1.0,
		"intercept threats are listed even when high ACC beats them"
	)

	model.scripted_first_intercept_wins = true
	var from_tile: Vector2i = threats[0].player.pos
	var stolen := model.apply_pass_to(st.id, lane)
	_assert(stolen.get("intercepted", false), "scripted interceptor takes the pass")
	var thief := model.player_by_id(stolen.interceptor_id)
	_assert(thief != null and thief.has_ball and thief.team == MatchRules.Team.AWAY, "an opponent now has the ball")
	_assert(not st.has_ball, "passer lost the ball")
	_assert(thief.pos != from_tile, "interceptor left their starting tile")
	_assert(model.ball.pos == thief.pos, "ball is on the intercept tile")
	_assert(model.player_at(from_tile) == null, "the interceptor's old tile is empty")

	var clean := MatchModel.new()
	clean.setup_kickoff()
	var kicker := clean.player_at(MatchRules.CENTER_SPOT)
	clean.scripted_first_intercept_wins = false
	var done := clean.apply_pass_to(kicker.id, lane)
	_assert(not done.get("intercepted", false), "beating every interceptor completes the pass")
	_assert(clean.ball.is_loose() and clean.ball.pos == lane, "completed pass still lands on the square")

	var spaced := MatchModel.new()
	spaced.setup_kickoff()
	var passer := spaced.player_at(MatchRules.CENTER_SPOT)
	var dest := Vector2i(passer.pos.x + 3, passer.pos.y)
	var park_y := 0
	var helix: Array[PlayerState] = []
	for player in spaced.players:
		if player.team != MatchRules.Team.AWAY or player.role == "GK":
			continue
		helix.append(player)
		player.pos = Vector2i(MatchRules.GRID_WIDTH - 1, park_y)
		park_y += 1
	_assert(helix.size() >= 2, "helix field players exist to place on and off the lane")
	var on_player: PlayerState = helix[0]
	var off_player: PlayerState = helix[1]
	on_player.defense = 8
	off_player.defense = 8
	on_player.energy = on_player.max_energy
	off_player.energy = off_player.max_energy
	on_player.pos = Vector2i(passer.pos.x + 2, passer.pos.y)
	off_player.pos = Vector2i(passer.pos.x + 2, passer.pos.y + 1)
	var placed := spaced.interceptors_for_pass(passer, dest)
	_assert(placed.size() == 2, "only the two placed helix players threaten the pass")
	var on_first := float(placed[0].dist) < float(placed[1].dist)
	var on_threat: Dictionary = placed[0] if on_first else placed[1]
	var off_threat: Dictionary = placed[1] if on_first else placed[0]
	_assert(is_equal_approx(float(on_threat.dist), 0.0), "on-lane interceptor sits on the pass")
	_assert(is_equal_approx(float(off_threat.dist), 1.0), "off-lane interceptor sits 1 tile off")
	_assert(
		int(off_threat.intercept_percent) < int(on_threat.intercept_percent),
		"same DEF intercepts less often from 1 tile off the lane"
	)


func _test_swap_and_choice() -> void:
	print("-- swap and choice")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var near := model.player_at(_spot(0, -1))
	var wing := model.player_at(Vector2i(MatchRules.CENTER_SPOT.x - 3, 0))
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	var lcm := model.player_at(_spot(-3, -1))
	_assert(not model.can_pass_to_cell(st, _spot(-2, 0)), "cannot pass into the rear cone")
	st.facing = Vector2i(-1, 0)
	lcm.pos = _spot(-3, 0)
	var far := model.actions_for(st, lcm.pos)
	_assert(far.size() == 1 and far[0].id == "pass", "in-range non-adjacent teammate is pass only")
	st.facing = Vector2i(0, -1)
	var adjacent := model.actions_for(st, near.pos)
	_assert(adjacent.size() == 2, "adjacent teammate offers two actions")
	_assert(adjacent[0].id == "pass" and adjacent[1].id == "swap", "pass and swap are both offered")
	_assert(not model.can_swap(st, lcm), "cannot swap from 3 tiles away")
	_assert(not model.can_swap(st, wing), "cannot swap from the wing")
	_assert(not model.can_swap(st, away), "cannot swap with an opponent")
	var swapped := model.apply_swap(st.id, near.id)
	_assert(swapped.ok and swapped.action == "swap", "swap succeeds")
	_assert(st.pos == _spot(0, -1) and near.pos == MatchRules.CENTER_SPOT, "players swapped places")
	_assert(st.has_ball and not near.has_ball, "carrier kept the ball")
	_assert(model.ball.pos == st.pos, "ball followed the carrier")
	_assert(model.current_team == MatchRules.Team.HOME, "a swap does not switch the planning team")


func _test_offside() -> void:
	print("-- offside")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var mate := model.player_at(_spot(0, -1))
	st.pos = Vector2i(23, MatchRules.CENTER_Y)
	model.ball.pos = st.pos
	mate.pos = Vector2i(24, MatchRules.CENTER_Y)
	_assert(model.is_offside_receiver(st, mate), "teammate ahead of the last line is offside")
	_assert(Vector2i(24, MatchRules.CENTER_Y) in model.offside_pass_cells(st), "offside target is listed")
	var acts := model.actions_for(st, mate.pos)
	_assert(acts.size() == 2, "adjacent offside teammate still offers pass or swap")
	_assert(acts[0].id == "pass" and acts[1].id == "swap", "pass and swap are both offered")
	_assert(acts[0].get("offside", false), "pass action is marked offside")
	_assert(str(acts[0].get("label", "")).contains("offside"), "chooser labels the offside pass")
	var preview := model.pass_preview(st, mate.pos)
	_assert(preview.get("offside", false), "preview flags offside")
	_assert(preview.text.contains("OFFSIDE") or preview.header.contains("OFFSIDE"), "preview names offside")
	var taker := model.closest_player(MatchRules.Team.AWAY, mate.pos)
	var taker_from := taker.pos if taker != null else Vector2i.ZERO
	_assert(taker != null, "closest helix is the RCB next to the tile")
	model.scripted_first_intercept_wins = false
	var flagged := model.apply_pass(st.id, mate.id)
	_assert(flagged.ok and flagged.action == "offside", "arriving pass to offside teammate is offside")
	_assert(taker.pos == Vector2i(24, MatchRules.CENTER_Y) and taker.has_ball, "closest opponent took the offside tile and the ball")
	_assert(mate.pos == taker_from, "offside player was swapped to the taker's old tile")
	_assert(not st.has_ball, "passer lost the ball")
	_assert(model.current_team == MatchRules.Team.HOME, "offside does not switch the planning team")
	_assert(model.ball.pos == taker.pos, "ball sits on the restart tile")

	var onside := MatchModel.new()
	onside.setup_kickoff()
	var kicker := onside.player_at(MatchRules.CENTER_SPOT)
	var partner := onside.player_at(_spot(0, -1))
	kicker.pos = _spot(-1, -1)
	onside.ball.pos = kicker.pos
	partner.pos = _spot(0, -1)
	_assert(not onside.is_offside_receiver(kicker, partner), "behind the last line is onside")
	onside.scripted_first_intercept_wins = false
	var completed := onside.apply_pass(kicker.id, partner.id)
	_assert(completed.ok and completed.action == "pass", "onside pass still completes")
	_assert(partner.has_ball, "onside receiver got the ball")

	var own_half := MatchModel.new()
	own_half.setup_kickoff()
	var holder := own_half.player_at(MatchRules.CENTER_SPOT)
	var wing := own_half.player_at(Vector2i(MatchRules.CENTER_SPOT.x - 3, 0))
	_assert(not own_half.is_offside_receiver(holder, wing), "own-half teammate is not offside")

	var ground := MatchModel.new()
	ground.setup_kickoff()
	var carrier := ground.player_at(MatchRules.CENTER_SPOT)
	carrier.pos = _spot(2, 0)
	ground.ball.pos = carrier.pos
	_assert(ground.player_at(_spot(5, 0)) == null, "empty square has no receiver")
	ground.scripted_first_intercept_wins = false
	var laid := ground.apply_pass_to(carrier.id, _spot(5, 0))
	_assert(laid.ok and laid.action == "pass", "pass to an empty square is not offside")
	_assert(ground.ball.is_loose() and ground.ball.pos == _spot(5, 0), "empty-square pass stayed a ground pass")

	var stolen := MatchModel.new()
	stolen.setup_kickoff()
	var passer := stolen.player_at(MatchRules.CENTER_SPOT)
	var target := stolen.player_at(_spot(0, -1))
	passer.pos = Vector2i(22, MatchRules.CENTER_Y)
	stolen.ball.pos = passer.pos
	target.pos = Vector2i(24, MatchRules.CENTER_Y)
	_assert(stolen.is_offside_receiver(passer, target), "setup is offside if the pass arrived")
	stolen.scripted_first_intercept_wins = true
	var cut := stolen.apply_pass_to(passer.id, target.pos)
	_assert(cut.get("intercepted", false), "intercept happens before offside")
	_assert(cut.action == "pass", "intercepted pass is not recorded as offside")
	_assert(not target.has_ball, "offside teammate did not receive the intercepted pass")


func _dummy_empty_move(model: MatchModel, team: int, except: Dictionary) -> Dictionary:
	for player in model.players:
		if player.team != team or except.has(player.id):
			continue
		for dest in model.valid_moves(player):
			if model.player_at(dest) == null:
				return {player = player, dest = dest}
	return {}


func _fill_plans(model: MatchModel, extras: Array) -> void:
	var except := {}
	for extra in extras:
		var player_id := int(extra.get("player_id", extra.get("id", -1)))
		var action: Dictionary = extra.get("action", extra)
		model.queue_plan(player_id, action)
		except[player_id] = true
	for existing in model.plans_for(model.current_team):
		except[int(existing.get("player_id", -1))] = true
	while model.acting_player_count() < MatchRules.ACTIONS_PER_SIDE:
		var dummy := _dummy_empty_move(model, model.current_team, except)
		if dummy.is_empty():
			_assert(false, "needed a dummy empty move")
			return
		var mover: PlayerState = dummy.player
		model.queue_plan(mover.id, {id = "move", dest = dummy.dest, label = "Move"})
		except[mover.id] = true


func _test_planning_and_resolve() -> void:
	print("-- planning and resolve")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var queued := model.queue_plan(st.id, {id = "move", dest = _spot(1, 0), label = "Move"})
	_assert(queued.ok and queued.action == "queue", "carrier can queue a move")
	_assert(st.pos == MatchRules.CENTER_SPOT, "queued move does not apply yet")
	_assert(model.plan_count() == 1, "one plan stored")
	_assert(model.can_end_planning(), "end turn is allowed after the first plan")
	_assert(not model.planning_complete(), "one plan is not a full side")
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	_assert(not model.can_queue(away), "cannot queue a helix player during aether planning")
	_fill_plans(model, [])
	_assert(model.plan_count() == 3, "three aether plans")
	_assert(model.acting_player_count() == 3, "three aether players planned")
	_assert(not model.planning_complete(), "those players still have a second AP")
	var extra: PlayerState = null
	for player in model.players:
		if player.team == MatchRules.Team.HOME and model.plan_of(player.id).is_empty():
			extra = player
			break
	_assert(extra != null, "an unplanned aether player remains")
	_assert(not model.can_select(extra), "a fourth aether player cannot be selected")
	var locked := model.end_planning()
	_assert(locked.ok and locked.action == "end_planning", "aether end turn hands planning to helix")
	_assert(model.current_team == MatchRules.Team.AWAY, "helix plans second")
	_assert(st.pos == MatchRules.CENTER_SPOT, "board is unchanged after aether locks in")
	_assert(model.combat_log.as_text().contains("PLAN  "), "full log still stores aether plans")
	_assert(
		model.combat_log.as_text(MatchRules.Team.HOME).contains("PLAN  "),
		"aether still sees own plan lines"
	)
	var helix_view := model.combat_log.as_text(MatchRules.Team.AWAY)
	_assert(not helix_view.contains("PLAN  "), "helix log hides aether plan lines")
	_assert(not helix_view.contains("locked in"), "helix log hides aether lock-in")

	var helix_st := model.player_at(MatchRules.AWAY_KICKOFF)
	_fill_plans(model, [])
	var resolved := model.end_planning()
	_assert(resolved.ok and resolved.action == "resolve", "helix end turn resolves the cycle")
	_assert(model.current_team == MatchRules.Team.HOME, "aether plans the next cycle")
	_assert(st.pos == _spot(1, 0), "queued aether move applied on resolve")
	_assert(model.home_plans.is_empty() and model.away_plans.is_empty(), "plans clear after resolve")
	_assert(model.combat_log.as_text().contains("Resolve cycle"), "log has a resolve header")
	var aether_after := model.combat_log.as_text(MatchRules.Team.HOME)
	var helix_after := model.combat_log.as_text(MatchRules.Team.AWAY)
	var public_after := model.combat_log.as_text(CombatLog.VIEWER_PUBLIC)
	_assert(aether_after.contains("PLAN  AETHER"), "aether still sees own past plans after resolve")
	_assert(not aether_after.contains("PLAN  HELIX"), "aether does not see helix plans")
	_assert(aether_after.contains("MOVE"), "aether sees public resolution results")
	_assert(helix_after.contains("PLAN  HELIX"), "helix still sees own past plans after resolve")
	_assert(not helix_after.contains("PLAN  AETHER"), "helix never sees aether plan lines")
	_assert(helix_after.contains("Resolve cycle"), "helix sees the public resolve header")
	_assert(helix_after.contains("MOVE"), "helix sees the public move result")
	_assert(not public_after.contains("PLAN  "), "resolution view hides every team's plans")
	_assert(public_after.contains("MOVE"), "resolution view shows the public move")

	var held := MatchModel.new()
	held.setup_kickoff()
	var held_st := held.player_at(MatchRules.CENTER_SPOT)
	var held_away := held.player_at(MatchRules.AWAY_KICKOFF)
	held_away.pos = _spot(2, 0)
	held.scripted_attacker_wins = false
	_fill_plans(held, [{
		player_id = held_st.id,
		id = "move",
		dest = _spot(1, 0),
		label = "Move",
	}])
	held.end_planning()
	_fill_plans(held, [{
		player_id = held_away.id,
		id = "move",
		dest = _spot(1, 0),
		label = "Move",
	}])
	var held_result := held.end_planning()
	_assert(held_result.action == "resolve", "arrival tackle cycle resolved")
	_assert(held_st.pos == _spot(1, 0) and held_st.has_ball, "carrier won the arrival tackle and kept the ball")
	_assert(held_away.pos == _spot(2, 0), "failed tackler stayed put")
	_assert(held.combat_log.as_text().contains("TACKLE"), "log records the arrival as a tackle")

	var poke := MatchModel.new()
	poke.setup_kickoff()
	var poke_st := poke.player_at(MatchRules.CENTER_SPOT)
	var poke_away := poke.player_at(MatchRules.AWAY_KICKOFF)
	poke_away.pos = _spot(2, 0)
	poke.scripted_attacker_wins = true
	_fill_plans(poke, [{
		player_id = poke_st.id,
		id = "move",
		dest = _spot(1, 0),
		label = "Move",
	}])
	poke.end_planning()
	_fill_plans(poke, [{
		player_id = poke_away.id,
		id = "move",
		dest = _spot(1, 0),
		label = "Move",
	}])
	var poke_result := poke.end_planning()
	_assert(poke_result.action == "resolve", "arrival tackle steal resolved")
	_assert(poke_away.pos == _spot(1, 0) and poke_away.has_ball, "tackler won the square and stole the ball")
	_assert(poke_st.pos == MatchRules.CENTER_SPOT and not poke_st.has_ball, "carrier lost the arrival tackle")
	_assert(
		poke_away.facing == MatchRules.step_direction(poke_st.pos, poke_away.pos),
		"arrival steal turns the winner's back to the old carrier"
	)

	var square := MatchModel.new()
	square.setup_kickoff()
	var square_mid := square.player_at(_spot(0, -1))
	var square_st := square.player_at(MatchRules.CENTER_SPOT)
	var square_away := square.player_at(MatchRules.AWAY_KICKOFF)
	square_away.facing = Vector2i(0, -1)
	square.scripted_attacker_wins = true
	_fill_plans(square, [
		{
			player_id = square_mid.id,
			id = "move",
			dest = _spot(1, 0),
			label = "Move",
		},
		{
			player_id = square_st.id,
			id = "turn",
			dest = _spot(0, 1),
			label = "Turn",
		},
	])
	square.end_planning()
	_fill_plans(square, [{
		player_id = square_away.id,
		id = "move",
		dest = _spot(1, 0),
		label = "Move",
	}])
	var square_result := square.end_planning()
	_assert(square_result.action == "resolve", "off-ball arrival contest resolved")
	_assert(square_mid.pos == _spot(1, 0), "lower-id mover won the CTR arrival fight")
	_assert(square_away.pos == MatchRules.AWAY_KICKOFF, "CTR arrival loser stayed put")
	_assert(square.combat_log.as_text().contains("SQUARE FIGHT"), "log records the off-ball arrival as a square fight")

	var interrupt := MatchModel.new()
	interrupt.setup_kickoff()
	var carrier := interrupt.player_at(MatchRules.CENTER_SPOT)
	var mate := interrupt.player_at(_spot(0, -1))
	var tackler := interrupt.player_at(MatchRules.AWAY_KICKOFF)
	tackler.pos = _spot(1, 0)
	interrupt.scripted_attacker_wins = true
	interrupt.scripted_first_intercept_wins = false
	_fill_plans(interrupt, [
		{
			player_id = carrier.id,
			id = "turn",
			dest = mate.pos,
			label = "Turn",
		},
		{
			player_id = carrier.id,
			id = "pass",
			dest = mate.pos,
			target_id = mate.id,
			label = "Pass",
		},
	])
	interrupt.end_planning()
	_fill_plans(interrupt, [{
		player_id = tackler.id,
		id = "tackle",
		dest = MatchRules.CENTER_SPOT,
		label = "Tackle",
	}])
	var fight := interrupt.end_planning()
	_assert(fight.action == "resolve", "tackle-then-pass cycle resolved")
	_assert(tackler.has_ball and tackler.pos == MatchRules.CENTER_SPOT, "tackle resolved first and won the ball")
	_assert(not carrier.has_ball, "passer lost the ball")
	_assert(not mate.has_ball, "pass did not arrive after the tackle")
	var log_text := interrupt.combat_log.as_text()
	_assert(log_text.contains("TACKLE"), "log shows the tackle")
	_assert(log_text.contains("CANCEL") and log_text.contains("lost the ball"), "log shows the cancelled pass")

	var lead := MatchModel.new()
	lead.setup_kickoff()
	lead.scripted_first_intercept_wins = false
	var lead_st := lead.player_at(MatchRules.CENTER_SPOT)
	var lead_mate := lead.player_at(_spot(0, -1))
	lead_mate.facing = Vector2i(0, -1)
	_fill_plans(lead, [
		{
			player_id = lead_st.id,
			id = "pass",
			dest = lead_mate.pos,
			target_id = lead_mate.id,
			label = "Pass",
		},
		{
			player_id = lead_mate.id,
			id = "move",
			dest = _spot(0, -2),
			label = "Move",
		},
	])
	lead.end_planning()
	_fill_plans(lead, [])
	var led := lead.end_planning()
	_assert(led.action == "resolve", "pass-then-move cycle resolved")
	_assert(lead_mate.pos == _spot(0, -2), "receiver moved after the pass")
	_assert(lead_mate.has_ball, "receiver kept the ball and carried it")
	_assert(lead.ball.pos == _spot(0, -2), "ball followed the receiver's move")
	_assert(not lead_st.has_ball, "passer no longer has the ball")

	var feed := MatchModel.new()
	feed.setup_kickoff()
	var feed_st := feed.player_at(MatchRules.CENTER_SPOT)
	var feed_mate := feed.player_at(_spot(0, -1))
	feed.queue_plan(feed_st.id, {
		id = "pass",
		dest = feed_mate.pos,
		target_id = feed_mate.id,
		label = "Pass",
	})
	_assert(feed.planning_has_ball(feed_mate), "queued pass lets the receiver plan with the ball")
	_assert(not feed.planning_has_ball(feed_st), "passer no longer has planning possession")
	_assert(feed.can_plan_pass_to_cell(feed_mate, _spot(0, -3)), "receiver can queue a follow-up pass")
	var feed_helix := feed.player_at(_spot(2, -1))
	feed_helix.pos = _spot(1, -1)
	var feed_acts := feed.actions_for(feed_mate, _spot(1, -1))
	var feed_ids: Array = []
	for act in feed_acts:
		feed_ids.append(act.id)
	_assert("dribble" in feed_ids, "receiver can queue a dribble as if they have the ball")

	var pickup := MatchModel.new()
	pickup.setup_kickoff()
	pickup.scripted_first_intercept_wins = false
	var pickup_st := pickup.player_at(MatchRules.CENTER_SPOT)
	var pickup_mate := pickup.player_at(_spot(0, -1))
	pickup.apply_pass_to(pickup_st.id, _spot(1, 0))
	_assert(pickup.ball.is_loose() and pickup.ball.pos == _spot(1, 0), "setup leaves the ball loose on an adjacent tile")
	_assert(not pickup.planning_has_ball(pickup_st), "a player next to a loose ball does not have it yet")
	var pickup_before: Array = []
	for cmd in pickup.commands_for(pickup_st):
		pickup_before.append(cmd.id)
	_assert("move" in pickup_before and "turn" in pickup_before, "before collecting, only movement commands are listed")
	_assert("pass" not in pickup_before and "dribble" not in pickup_before, "before collecting, ball actions are hidden")
	pickup.queue_plan(pickup_st.id, {id = "move", dest = _spot(1, 0), label = "Move"})
	_assert(pickup.planning_has_ball(pickup_st), "queued step onto the loose ball grants planning possession")
	_assert(pickup.ball.is_loose() and pickup.ball.pos == _spot(1, 0), "planning collect does not move the real ball")
	_assert(pickup_st.pos == MatchRules.CENTER_SPOT, "planning collect does not move the player")
	var pickup_after: Array = []
	for cmd in pickup.commands_for(pickup_st):
		pickup_after.append(cmd.id)
	_assert("pass" in pickup_after, "after stepping on the ball, pass is available")
	_assert("dribble" in pickup_after, "after stepping on the ball, dribble is available")
	_assert(pickup.can_plan_pass_to(pickup_st, pickup_mate), "collector can pass from the ball tile")
	var pickup_pass := pickup.queue_plan(pickup_st.id, {
		id = "pass",
		dest = pickup_mate.pos,
		target_id = pickup_mate.id,
		label = "Pass",
	})
	_assert(pickup_pass.ok, "collector can queue a pass with the second AP")
	_assert(bool(pickup_pass.plan.get("expects_ball", false)), "collect-then-pass is marked as expecting the ball")
	_assert(str(pickup_pass.plan.get("expects_reason", "")) == "did not get the ball", "failed collect uses the collect cancel reason")

	var laid_collect := MatchModel.new()
	laid_collect.setup_kickoff()
	laid_collect.scripted_first_intercept_wins = false
	var laid_st := laid_collect.player_at(MatchRules.CENTER_SPOT)
	var laid_mid := laid_collect.player_at(_spot(0, -1))
	laid_collect.queue_plan(laid_st.id, {
		id = "pass",
		dest = _spot(1, 0),
		target_id = -1,
		label = "Pass",
	})
	_assert(not laid_collect.planning_has_ball(laid_st), "ground pass drops planning possession")
	laid_collect.queue_plan(laid_mid.id, {id = "move", dest = _spot(1, 0), label = "Move"})
	_assert(laid_collect.planning_has_ball(laid_mid), "stepping onto a planned ground pass grants planning possession")
	_assert(not laid_collect.command_dests(laid_mid, "pass").is_empty(), "ground-pass collector can queue a follow-up pass")

	var fed := MatchModel.new()
	fed.setup_kickoff()
	fed.scripted_first_intercept_wins = false
	fed.scripted_attacker_wins = true
	var fed_st := fed.player_at(MatchRules.CENTER_SPOT)
	var fed_mate := fed.player_at(_spot(0, -1))
	fed.player_at(_spot(2, -1)).pos = _spot(1, -1)
	_fill_plans(fed, [
		{
			player_id = fed_st.id,
			id = "pass",
			dest = fed_mate.pos,
			target_id = fed_mate.id,
			label = "Pass",
		},
		{
			player_id = fed_mate.id,
			id = "dribble",
			dest = _spot(1, -1),
			label = "Dribble",
		},
	])
	fed.end_planning()
	_fill_plans(fed, [])
	var fed_result := fed.end_planning()
	_assert(fed_result.action == "resolve", "pass-then-dribble cycle resolved")
	_assert(fed_mate.pos == _spot(1, -1) and fed_mate.has_ball, "receiver dribbled after the pass arrived")

	var cut := MatchModel.new()
	cut.setup_kickoff()
	cut.scripted_first_intercept_wins = true
	var cut_st := cut.player_at(MatchRules.CENTER_SPOT)
	var cut_mate := cut.player_at(_spot(0, -1))
	cut.player_at(_spot(2, -1)).pos = _spot(1, -1)
	_fill_plans(cut, [
		{
			player_id = cut_st.id,
			id = "pass",
			dest = cut_mate.pos,
			target_id = cut_mate.id,
			label = "Pass",
		},
		{
			player_id = cut_mate.id,
			id = "dribble",
			dest = _spot(1, -1),
			label = "Dribble",
		},
	])
	cut.end_planning()
	_fill_plans(cut, [])
	var cut_result := cut.end_planning()
	_assert(cut_result.action == "resolve", "intercepted pass-then-dribble resolved")
	_assert(cut_mate.pos == _spot(0, -1), "receiver dribble did not play after the intercept")
	_assert(not cut_mate.has_ball, "receiver never got the intercepted pass")
	_assert(cut.combat_log.as_text().contains("pass did not arrive"), "log cancels the expected-ball dribble")

	var collect := MatchModel.new()
	collect.setup_kickoff()
	collect.scripted_first_intercept_wins = false
	var collect_st := collect.player_at(MatchRules.CENTER_SPOT)
	var collect_mid := collect.player_at(_spot(0, -1))
	_fill_plans(collect, [
		{
			player_id = collect_st.id,
			id = "pass",
			dest = _spot(1, 0),
			target_id = -1,
			label = "Pass",
		},
		{
			player_id = collect_mid.id,
			id = "move",
			dest = _spot(1, 0),
			label = "Move",
		},
	])
	collect.end_planning()
	_fill_plans(collect, [])
	var collected := collect.end_planning()
	_assert(collected.action == "resolve", "ground-pass collect cycle resolved")
	_assert(collect_mid.pos == _spot(1, 0), "teammate stepped onto the pass square")
	_assert(collect_mid.has_ball, "teammate collected the loose pass")
	_assert(not collect.ball.is_loose(), "ball is no longer loose after the collect")

	var steal := MatchModel.new()
	steal.setup_kickoff()
	steal.scripted_first_intercept_wins = false
	var steal_st := steal.player_at(MatchRules.CENTER_SPOT)
	var steal_helix := steal.player_at(MatchRules.AWAY_KICKOFF)
	steal_helix.pos = _spot(1, 1)
	_fill_plans(steal, [{
		player_id = steal_st.id,
		id = "pass",
		dest = _spot(0, 1),
		target_id = -1,
		label = "Pass",
	}])
	steal.end_planning()
	_fill_plans(steal, [{
		player_id = steal_helix.id,
		id = "move",
		dest = _spot(0, 1),
		label = "Move",
	}])
	var stolen_pass := steal.end_planning()
	_assert(stolen_pass.action == "resolve", "opponent collect cycle resolved")
	_assert(steal_helix.pos == _spot(0, 1), "helix stepped onto the pass square")
	_assert(steal_helix.has_ball, "helix collected the loose pass")
	_assert(not steal_st.has_ball, "passer does not keep a collected ground pass")

	var collect_play := MatchModel.new()
	collect_play.setup_kickoff()
	collect_play.scripted_first_intercept_wins = false
	var collect_play_st := collect_play.player_at(MatchRules.CENTER_SPOT)
	var collect_play_mate := collect_play.player_at(_spot(0, -1))
	collect_play.apply_pass_to(collect_play_st.id, _spot(1, 0))
	collect_play.queue_plan(collect_play_st.id, {id = "move", dest = _spot(1, 0), label = "Move"})
	collect_play.queue_plan(collect_play_st.id, {
		id = "pass",
		dest = collect_play_mate.pos,
		target_id = collect_play_mate.id,
		label = "Pass",
	})
	collect_play.end_planning()
	var collected_play := collect_play.end_planning()
	_assert(collected_play.action == "resolve", "collect-then-pass cycle resolved")
	_assert(collect_play_st.pos == _spot(1, 0), "collector stepped onto the loose ball")
	_assert(collect_play_mate.has_ball, "collector passed after picking the ball up")
	_assert(not collect_play_st.has_ball, "collector no longer has the ball after the pass")

	var denied := MatchModel.new()
	denied.setup_kickoff()
	denied.scripted_first_intercept_wins = false
	denied.scripted_attacker_wins = false
	var denied_st := denied.player_at(MatchRules.CENTER_SPOT)
	var denied_mate := denied.player_at(_spot(0, -1))
	var denied_helix := denied.player_at(MatchRules.AWAY_KICKOFF)
	denied_helix.pos = _spot(2, 0)
	denied.apply_pass_to(denied_st.id, _spot(1, 0))
	denied.queue_plan(denied_st.id, {id = "move", dest = _spot(1, 0), label = "Move"})
	denied.queue_plan(denied_st.id, {
		id = "pass",
		dest = denied_mate.pos,
		target_id = denied_mate.id,
		label = "Pass",
	})
	denied.end_planning()
	denied.queue_plan(denied_helix.id, {
		id = "move",
		dest = _spot(1, 0),
		label = "Move",
	})
	var denied_result := denied.end_planning()
	_assert(denied_result.action == "resolve", "contested collect cycle resolved")
	_assert(denied_helix.pos == _spot(1, 0) and denied_helix.has_ball, "helix won the square and took the loose ball")
	_assert(denied_st.pos == MatchRules.CENTER_SPOT and not denied_st.has_ball, "aether never collected the contested ball")
	_assert(not denied_mate.has_ball, "planned pass did not play after losing the collect")
	_assert(denied.combat_log.as_text().contains("did not get the ball"), "log ignores ball actions when the collect fails")

	var early := MatchModel.new()
	early.setup_kickoff()
	var early_st := early.player_at(MatchRules.CENTER_SPOT)
	early.queue_plan(early_st.id, {id = "move", dest = _spot(1, 0), label = "Move"})
	var early_lock := early.end_planning()
	_assert(early_lock.ok and early_lock.action == "end_planning", "end turn with one plan hands to helix")
	_assert(early.current_team == MatchRules.Team.AWAY, "helix plans after a premature aether end")
	_assert(early.home_plans.size() == 1, "aether's single plan is kept")
	_assert(early_st.pos == MatchRules.CENTER_SPOT, "premature end does not resolve yet")
	var early_helix := early.player_at(MatchRules.AWAY_KICKOFF)
	early.queue_plan(early_helix.id, {id = "move", dest = _spot(1, 1), label = "Move"})
	var early_resolve := early.end_planning()
	_assert(early_resolve.ok and early_resolve.action == "resolve", "helix can also end early")
	_assert(early_st.pos == _spot(1, 0), "lone aether plan still resolved")
	_assert(early_helix.pos == _spot(1, 1), "lone helix plan still resolved")

	var skip := MatchModel.new()
	skip.setup_kickoff()
	var skip_st := skip.player_at(MatchRules.CENTER_SPOT)
	_assert(skip.plan_count() == 0, "kickoff starts with an empty plan")
	var skip_lock := skip.end_planning()
	_assert(skip_lock.ok and skip_lock.action == "end_planning", "end turn with no plan hands to helix")
	_assert(skip.current_team == MatchRules.Team.AWAY, "helix plans after an empty aether end")
	_assert(skip.home_plans.is_empty(), "aether stored no actions")
	_assert(skip_st.pos == MatchRules.CENTER_SPOT, "empty aether end does not move anyone")
	var skip_resolve := skip.end_planning()
	_assert(skip_resolve.ok and skip_resolve.action == "resolve", "helix can also end with no plan")
	_assert(skip.current_team == MatchRules.Team.HOME, "empty cycle returns planning to aether")
	_assert(skip_st.pos == MatchRules.CENTER_SPOT, "empty cycle leaves the board unchanged")


func _test_ap_waves() -> void:
	print("-- AP waves")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var helix := model.player_at(MatchRules.AWAY_KICKOFF)
	var first := model.queue_plan(st.id, {id = "move", dest = _spot(1, 0), label = "Move"})
	_assert(int(first.plan.get("ap_end", 0)) == 2, "2-AP first action completes in wave 2")
	var second := model.queue_plan(st.id, {id = "move", dest = _spot(2, 0), label = "Move"})
	_assert(int(second.plan.get("ap_end", 0)) == 4, "second 2-AP action completes in wave 4")
	model.end_planning()
	var helix_step := model.queue_plan(helix.id, {id = "move", dest = _spot(1, 2), label = "Move"})
	_assert(int(helix_step.plan.get("ap_cost", 0)) == 3, "helix first step is a 3-AP diagonal")
	_assert(int(helix_step.plan.get("ap_end", 0)) == 3, "3-AP first action completes in wave 3")
	var resolved := model.end_planning()
	_assert(resolved.get("action") == "resolve", "staggered-cost cycle resolved")
	var moves: Array = []
	for event in resolved.get("events", []):
		if str(event.get("action", "")) != "move":
			continue
		if int(event.get("player_id", -1)) in [st.id, helix.id]:
			moves.append(event)
	_assert(moves.size() == 3, "both players' three steps played")
	_assert(int(moves[0].get("player_id", -1)) == st.id and moves[0].get("dest") == _spot(1, 0), "wave 2: aether's first 2-AP step")
	_assert(int(moves[1].get("player_id", -1)) == helix.id and moves[1].get("dest") == _spot(1, 2), "wave 3: helix's 3-AP step")
	_assert(int(moves[2].get("player_id", -1)) == st.id and moves[2].get("dest") == _spot(2, 0), "wave 4: aether's second 2-AP step")
	_assert(st.pos == _spot(2, 0), "aether finished on the second step")
	_assert(helix.pos == _spot(1, 2), "helix finished on the diagonal")
	_assert(model.combat_log.as_text().contains("Wave 3"), "log labels the AP-3 wave")
	_assert(model.combat_log.as_text().contains("Wave 4"), "log labels the AP-4 wave")

	var bounce_arrive := MatchModel.new()
	bounce_arrive.setup_kickoff()
	var arrive_st := bounce_arrive.player_at(MatchRules.CENTER_SPOT)
	var arrive_away := bounce_arrive.player_at(MatchRules.AWAY_KICKOFF)
	arrive_away.pos = _spot(2, 0)
	bounce_arrive.scripted_contest_tie = true
	bounce_arrive.scripted_bounce_cell = _spot(0, 1)
	bounce_arrive.queue_plan(arrive_st.id, {id = "move", dest = _spot(1, 0), label = "Move"})
	bounce_arrive.end_planning()
	bounce_arrive.queue_plan(arrive_away.id, {id = "move", dest = _spot(1, 0), label = "Move"})
	var arrive_result := bounce_arrive.end_planning()
	_assert(arrive_result.get("action") == "resolve", "tied arrival tackle resolved")
	_assert(arrive_st.pos == MatchRules.CENTER_SPOT, "tied arrival leaves the carrier in place")
	_assert(arrive_away.pos == _spot(2, 0), "tied arrival leaves the tackler in place")
	_assert(bounce_arrive.ball.is_loose() and bounce_arrive.ball.pos == _spot(0, 1), "tied arrival bounce dumps the ball")
	_assert(bounce_arrive.combat_log.as_text().contains("TACKLE BOUNCE"), "log names the arrival bounce")
	_assert(bounce_arrive.combat_log.as_text().contains("the ball bounced"), "both arrival steps cancel after the bounce")


func _test_shooting() -> void:
	print("-- shooting")
	var box := MatchRules.penalty_tiles(MatchRules.AWAY_NET)
	var six := Vector2i(MatchRules.GRID_WIDTH - 1, MatchRules.CENTER_Y)
	_assert(box.size() == 3, "penalty box is the three tiles on the goal line")
	_assert(six in box, "centre goal-line tile is in the box")
	_assert(MatchRules.is_in_shooting_zone(six, MatchRules.AWAY_NET), "box is a shooting zone")
	_assert(MatchRules.is_in_shooting_zone(Vector2i(MatchRules.GRID_WIDTH - 2, MatchRules.CENTER_Y - 2), MatchRules.AWAY_NET), "corner-touching ring can shoot")
	_assert(not MatchRules.is_in_shooting_zone(Vector2i(MatchRules.GRID_WIDTH - 3, MatchRules.CENTER_Y), MatchRules.AWAY_NET), "one tile further is too far")
	_assert(not MatchRules.is_in_shooting_zone(MatchRules.CENTER_SPOT, MatchRules.AWAY_NET), "midfield cannot shoot")

	var close := MatchRules.shot_geometry(six, MatchRules.AWAY_NET)
	var deep := MatchRules.shot_geometry(Vector2i(MatchRules.GRID_WIDTH - 2, MatchRules.CENTER_Y), MatchRules.AWAY_NET)
	var wide := MatchRules.shot_geometry(Vector2i(MatchRules.GRID_WIDTH - 1, MatchRules.CENTER_Y - 2), MatchRules.AWAY_NET)
	_assert(close.distance < deep.distance, "the six-yard tile is closer than the ring")
	_assert(close.angle_deg < 1.0, "shot from centre is straight on")
	_assert(wide.angle_deg > close.angle_deg, "shot from the corner is angled")
	var hit_close := MatchRules.shot_hit_chance(13, close.distance, close.angle)
	var hit_deep := MatchRules.shot_hit_chance(13, deep.distance, deep.angle)
	var hit_wide := MatchRules.shot_hit_chance(13, wide.distance, wide.angle)
	_assert(hit_close > hit_deep, "closer shots hit more often")
	_assert(hit_close > hit_wide, "straighter shots hit more often")
	var hit_close_5 := MatchRules.shot_hit_chance(13, close.distance, close.angle, 5)
	_assert(
		is_equal_approx(hit_close_5, clampf(hit_close + 0.15, 0.05, 0.98)),
		"5 leftover AP add 15 percentage points of hit"
	)
	var hit_1 := MatchRules.shot_hit_chance(13, close.distance, close.angle, 1)
	_assert(
		is_equal_approx(hit_1, clampf(hit_close + 0.03, 0.05, 0.98)),
		"1 leftover AP adds 3 percentage points of hit"
	)

	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	_assert(not model.can_shoot(st), "cannot shoot from kickoff")
	st.pos = Vector2i(MatchRules.GRID_WIDTH - 1, MatchRules.CENTER_Y)
	model.ball.pos = st.pos
	_assert(model.can_shoot(st), "can shoot from the penalty box")
	var acts := model.actions_for(st, MatchRules.AWAY_NET)
	var ids: Array = []
	for act in acts:
		ids.append(act.id)
	_assert("shoot" in ids, "clicking the net offers shoot")
	var preview := model.shot_preview(st)
	_assert(preview.text.contains("hit = ACC/(ACC+"), "preview shows the hit formula")
	_assert(preview.text.contains("leftover AP"), "preview shows leftover AP bonus")
	_assert(preview.text.contains("goal = hit"), "preview shows the goal product")
	_assert(int(preview.get("remaining_ap", -1)) == 6, "unspent shooter previews a 6 AP shot")
	_assert(is_equal_approx(float(preview.get("leftover_bonus", 0.0)), 0.18), "unspent shooter gets +18% hit")
	_assert(preview.keeper_in_net, "helix keeper starts in the net")

	model.scripted_shot_outcome = "goal"
	var scored := model.apply_shoot(st.id)
	_assert(scored.goal, "scripted shot is a goal")
	_assert(model.home_score == 1 and model.away_score == 0, "aether leads 1-0")
	_assert(model.current_team == MatchRules.Team.AWAY, "conceding team kicks off")
	_assert(model.player_at(MatchRules.AWAY_SPOT).has_ball, "helix striker takes the mirrored centre")
	_assert(model.player_at(MatchRules.CENTER_SPOT) == null, "aether leaves the centre after scoring")

	var miss_model := MatchModel.new()
	miss_model.setup_kickoff()
	var shooter := miss_model.player_at(MatchRules.CENTER_SPOT)
	shooter.pos = Vector2i(MatchRules.GRID_WIDTH - 1, MatchRules.CENTER_Y)
	miss_model.ball.pos = shooter.pos
	miss_model.scripted_shot_outcome = "miss"
	var missed := miss_model.apply_shoot(shooter.id)
	_assert(not missed.goal and not missed.hit, "scripted miss does not score")
	_assert(miss_model.home_score == 0, "score unchanged on a miss")
	_assert(miss_model.ball.is_loose() and miss_model.ball.pos == MatchRules.AWAY_NET, "missed shot is loose in the net")


func _test_controller_click_flow() -> void:
	print("-- controller")
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	var controller: Node = main
	controller.animate_moves = false
	controller._frame_camera()
	await process_frame
	var play: Rect2 = controller.hud.play_area()
	var aether_net: Vector2 = controller._cell_to_screen(MatchRules.HOME_NET)
	var helix_net: Vector2 = controller._cell_to_screen(MatchRules.AWAY_NET)
	_assert(aether_net.x >= play.position.x - 2.0, "aether net sits in the left play area")
	_assert(helix_net.x <= play.end.x + 2.0, "helix net is left of the match log")
	_assert(helix_net.x > aether_net.x, "pitch still runs left to right")
	_assert(not controller.hud._end_turn.disabled, "end turn is clickable with no plans")
	_assert(controller.hud._end_turn.text.contains("0/3"), "end turn shows an empty queue")
	var select_for_forecast: Dictionary = controller.handle_cell_clicked(MatchRules.CENTER_SPOT)
	_assert(select_for_forecast.get("action") == "select", "selecting the carrier sets up actions")
	_assert(controller._pending_action == "move", "move is selected by default")
	var pass_cmd: Dictionary = controller.select_command("pass")
	_assert(pass_cmd.get("ok", false), "pass is available for the carrier")
	controller._set_hover(_spot(0, -1))
	await process_frame
	_assert(controller.hud._forecast.visible, "pass hover shows the success forecast")
	_assert(controller.hud._forecast_label.text.contains("Pass success"), "forecast shows the pass success chance")
	var forecast_box: Rect2 = controller.hud._forecast.get_global_rect()
	_assert(forecast_box.position.y >= play.end.y - 4.0, "forecast sits below the playable pitch")
	_assert(forecast_box.end.x <= play.end.x + 8.0, "forecast does not overlap the match log")
	controller._deselect()
	var select_result: Dictionary = controller.handle_cell_clicked(MatchRules.CENTER_SPOT)
	_assert(select_result.get("action") == "select", "clicking own player selects")
	_assert(controller.selected_id >= 0, "selection stored")
	_assert(controller._pending_action == "move", "selecting a player arms move")
	_assert("move" in controller.hud._command_ids, "action bar lists move")
	var selected_before_spend: PlayerState = controller.model.player_by_id(controller.selected_id)
	_assert(selected_before_spend != null and controller.pieces[selected_before_spend.id].ap_left < 0, "AP pips stay hidden until the player spends")
	var move_result: Dictionary = controller.handle_cell_clicked(_spot(1, 0))
	_assert(move_result.get("action") == "queue", "clicking a highlighted tile queues the default move")
	var model: MatchModel = controller.model
	var striker := model.player_at(MatchRules.CENTER_SPOT)
	_assert(striker != null and striker.has_ball, "queued move left the board unchanged")
	_assert(model.plan_count() == 1, "one aether plan after the click")
	_assert(model.current_team == MatchRules.Team.HOME, "planning stays with aether")
	_assert(controller.selected_id == striker.id, "player stays selected with AP remaining")
	_assert(controller._pending_action == "move", "move stays armed after the first queued step")
	_assert(controller._plan_markers().size() == 1, "own plan arrow is visible")
	_assert(controller.pieces[striker.id].planned, "own gold ring is visible")
	_assert(controller.pieces[striker.id].ap_left == 4, "piece shows leftover AP after spending")
	var idle_pip := false
	for state in model.players:
		if state.team == MatchRules.Team.HOME and state.id != striker.id:
			var idle_piece: PlayerPiece = controller.pieces.get(state.id)
			_assert(idle_piece != null and idle_piece.ap_left < 0, "unspent teammates hide AP pips")
			idle_pip = true
			break
	_assert(idle_pip, "found an unspent teammate to check AP pips")
	_assert(controller.hud._phase.text.contains("AETHER"), "banner names the planning team")
	_assert(controller.hud._turn.text.contains("2 PLAYERS LEFT"), "banner shows remaining players")
	var enemy_select: Dictionary = controller.handle_cell_clicked(MatchRules.AWAY_NET)
	_assert(not enemy_select.get("ok", false), "cannot select helix during aether planning")
	main.queue_free()

	var chain: Node = packed.instantiate()
	root.add_child(chain)
	chain.animate_moves = false
	chain.handle_cell_clicked(MatchRules.CENTER_SPOT)
	_assert(chain._pending_action == "move", "selecting a player arms move")
	var first_step: Dictionary = chain.handle_cell_clicked(_spot(1, 0))
	_assert(first_step.get("action") == "queue", "first move click queues")
	_assert(chain._pending_action == "move", "move stays selected so the next tile can chain")
	var second_step: Dictionary = chain.handle_cell_clicked(_spot(2, 0))
	_assert(second_step.get("action") == "queue", "second move click chains without re-selecting the action")
	_assert(chain.model.ap_spent(chain.model.player_at(MatchRules.CENTER_SPOT).id) == 4, "two chained straight moves spend 4 AP")
	_assert(chain.selected_id >= 0, "player stays selected with leftover AP after two steps")
	var chain_st: PlayerState = chain.model.player_at(MatchRules.CENTER_SPOT)
	var chain_piece: PlayerPiece = chain.pieces.get(chain_st.id)
	_assert(chain_piece != null and chain_piece.ap_left == 2, "piece shows 2 leftover AP after two straight steps")
	_assert("done" in chain.hud._command_ids, "action bar lists done while AP remain")
	_assert(chain.hud._card_ap.text.contains("2/6"), "inspector shows leftover AP")
	var marked: Dictionary = chain.select_command("done")
	_assert(marked.get("action") == "queue", "choosing done queues immediately")
	_assert(chain.model.player_is_done(chain_st.id), "selecting done marks the player finished")
	_assert(chain.selected_id < 0, "done deselects the player")
	chain._refresh()
	_assert(chain_piece.finished, "piece shows a done badge after the action")
	chain.queue_free()

	var pickup_ui: Node = packed.instantiate()
	root.add_child(pickup_ui)
	pickup_ui.animate_moves = false
	pickup_ui.model.scripted_first_intercept_wins = false
	var ui_st: PlayerState = pickup_ui.model.player_at(MatchRules.CENTER_SPOT)
	pickup_ui.model.apply_pass_to(ui_st.id, _spot(1, 0))
	pickup_ui._refresh()
	pickup_ui.handle_cell_clicked(MatchRules.CENTER_SPOT)
	_assert("pass" not in pickup_ui.hud._command_ids, "action bar hides pass until the player steps on the ball")
	_assert("move" in pickup_ui.hud._command_ids, "action bar still lists move toward the loose ball")
	var step_on: Dictionary = pickup_ui.handle_cell_clicked(_spot(1, 0))
	_assert(step_on.get("action") == "queue", "clicking the loose-ball tile queues a move")
	_assert("pass" in pickup_ui.hud._command_ids, "action bar lists pass after stepping on the ball")
	_assert("dribble" in pickup_ui.hud._command_ids, "action bar lists dribble after stepping on the ball")
	_assert(pickup_ui.pieces[ui_st.id].has_ball, "preview shows the collector carrying the ball")
	_assert(pickup_ui.model.ball.is_loose(), "real ball stays on its tile until resolve")
	_assert(pickup_ui.hud._possession.text.contains(ui_st.label()), "possession banner follows the planned collect")
	pickup_ui.queue_free()

	var space_main: Node = packed.instantiate()
	root.add_child(space_main)
	space_main.animate_moves = false
	space_main.handle_cell_clicked(MatchRules.CENTER_SPOT)
	space_main.handle_cell_clicked(_spot(1, 0))
	_assert(space_main.model.current_team == MatchRules.Team.HOME, "space is tested before the turn ends")
	var space := InputEventKey.new()
	space.pressed = true
	space.keycode = KEY_SPACE
	space_main._input(space)
	_assert(space_main.model.current_team == MatchRules.Team.AWAY, "spacebar ends the turn")
	space_main.queue_free()

	var first_turn: Node = packed.instantiate()
	root.add_child(first_turn)
	first_turn.animate_moves = false
	first_turn.handle_cell_clicked(MatchRules.CENTER_SPOT)
	var first_turn_pick: Dictionary = first_turn.select_command("turn")
	_assert(first_turn_pick.get("ok", false), "turn is available as a first action")
	var first_turn_dests: Array = first_turn_pick.get("dests", [])
	_assert(not first_turn_dests.is_empty(), "first-action turn has highlighted cells")
	var first_turn_click: Dictionary = first_turn.handle_cell_clicked(first_turn_dests[0])
	_assert(first_turn_click.get("action") == "queue", "clicking a first-action turn highlight queues the turn")
	var first_turner: PlayerState = first_turn.model.player_at(MatchRules.CENTER_SPOT)
	_assert(
		first_turn.pieces[first_turner.id].facing
		== MatchRules.step_direction(MatchRules.CENTER_SPOT, first_turn_dests[0]),
		"queued first-action turn previews the new facing"
	)
	first_turn.queue_free()

	var move_then_turn: Node = packed.instantiate()
	root.add_child(move_then_turn)
	move_then_turn.animate_moves = false
	move_then_turn.handle_cell_clicked(MatchRules.CENTER_SPOT)
	var queued_step: Dictionary = move_then_turn.handle_cell_clicked(_spot(1, 0))
	_assert(queued_step.get("action") == "queue", "first AP move still queues")
	var stepper: PlayerState = move_then_turn.model.player_at(MatchRules.CENTER_SPOT)
	_assert(
		move_then_turn.pieces[stepper.id].position == move_then_turn.pitch.grid_to_world(_spot(1, 0)),
		"queued move previews the player on the destination"
	)
	var second_turn_pick: Dictionary = move_then_turn.select_command("turn")
	_assert(second_turn_pick.get("ok", false), "turn is available after a queued move")
	var second_turn_dests: Array = second_turn_pick.get("dests", [])
	_assert(not second_turn_dests.is_empty(), "second-action turn has highlighted cells")
	var cancel_on_piece: Dictionary = move_then_turn.handle_cell_clicked(_spot(1, 0))
	_assert(cancel_on_piece.get("action") == "command_cancel", "clicking the previewed player cancels turn")
	_assert(move_then_turn.model.ap_spent(stepper.id) == 2, "cancelling turn keeps the queued 2-AP move")
	move_then_turn.select_command("turn")
	var second_turn_click: Dictionary = move_then_turn.handle_cell_clicked(second_turn_dests[0])
	_assert(
		second_turn_click.get("action") == "queue",
		"clicking a turn highlight after a move queues the turn (got %s)" % str(second_turn_click)
	)
	_assert(move_then_turn.model.ap_spent(stepper.id) == 3, "move then turn spends 3 AP")
	_assert(move_then_turn.model.can_queue(stepper), "leftover AP remain after move then turn")
	_assert(
		move_then_turn.pieces[stepper.id].facing
		== MatchRules.step_direction(_spot(1, 0), second_turn_dests[0]),
		"queued second-action turn previews the new facing"
	)
	move_then_turn.queue_free()

	var pass_main: Node = packed.instantiate()
	root.add_child(pass_main)
	pass_main.animate_moves = false
	pass_main.handle_cell_clicked(MatchRules.CENTER_SPOT)
	pass_main.model.scripted_first_intercept_wins = false
	_assert("pass" in pass_main.hud._command_ids and "turn" in pass_main.hud._command_ids, "action bar lists pass and turn")
	var pass_pick: Dictionary = pass_main.select_command("pass")
	_assert(pass_pick.get("action") == "command", "pass is chosen from the action bar")
	var chosen_pass: Dictionary = pass_main.handle_cell_clicked(_spot(0, -1))
	_assert(chosen_pass.get("action") == "queue", "clicking the teammate queues the pass")
	_assert(pass_main.model.player_at(MatchRules.CENTER_SPOT).has_ball, "queued pass has not moved the ball")
	pass_main.queue_free()

	var swap_main: Node = packed.instantiate()
	root.add_child(swap_main)
	swap_main.animate_moves = false
	swap_main.model.player_at(MatchRules.CENTER_SPOT).facing = Vector2i(0, -1)
	swap_main.handle_cell_clicked(MatchRules.CENTER_SPOT)
	var swap_pick: Dictionary = swap_main.select_command("swap")
	_assert(swap_pick.get("action") == "command", "swap is chosen from the action bar")
	var chosen_swap: Dictionary = swap_main.handle_cell_clicked(_spot(0, -1))
	_assert(chosen_swap.get("action") == "queue", "clicking the teammate queues the swap")
	_assert(swap_main.model.player_at(MatchRules.CENTER_SPOT).number == 9, "queued swap left #9 in place")
	swap_main.queue_free()

	var auto_pass: Node = packed.instantiate()
	root.add_child(auto_pass)
	auto_pass.animate_moves = false
	auto_pass.handle_cell_clicked(MatchRules.CENTER_SPOT)
	auto_pass.model.scripted_first_intercept_wins = false
	var far_mate: PlayerState = auto_pass.model.player_at(_spot(0, -1))
	far_mate.pos = _spot(0, -3)
	auto_pass._refresh()
	auto_pass.select_command("pass")
	var far_pass: Dictionary = auto_pass.handle_cell_clicked(_spot(0, -3))
	_assert(far_pass.get("action") == "queue", "non-adjacent in-range teammate queues a pass")
	_assert(auto_pass.model.player_at(MatchRules.CENTER_SPOT).has_ball, "auto-pass is only queued")
	auto_pass.queue_free()

	var ground_pass: Node = packed.instantiate()
	root.add_child(ground_pass)
	ground_pass.animate_moves = false
	ground_pass.handle_cell_clicked(MatchRules.CENTER_SPOT)
	ground_pass.model.scripted_first_intercept_wins = false
	ground_pass.select_command("pass")
	var empty_pass: Dictionary = ground_pass.handle_cell_clicked(_spot(2, 0))
	_assert(empty_pass.get("action") == "queue", "clicking a distant empty square queues a pass")
	_assert(not ground_pass.model.ball.is_loose(), "queued ground pass has not released the ball")
	ground_pass.queue_free()

	var cycle_main: Node = packed.instantiate()
	root.add_child(cycle_main)
	cycle_main.animate_moves = false
	var cycle: MatchModel = cycle_main.model
	var cycle_st := cycle.player_at(MatchRules.CENTER_SPOT)
	_fill_plans(cycle, [{
		player_id = cycle_st.id,
		id = "move",
		dest = _spot(1, 0),
		label = "Move",
	}])
	var aether_end: Dictionary = cycle_main.end_planning()
	_assert(aether_end.get("action") == "end_planning", "controller end turn locks aether")
	_assert(cycle.current_team == MatchRules.Team.AWAY, "helix plans after aether ends")
	_assert(cycle_main.hud._phase.text.contains("HELIX"), "banner switches to helix planning")
	_assert(cycle_main.hud._turn.text.contains("3 PLAYERS LEFT"), "helix starts with three players left")
	_assert(cycle_main._plan_markers().is_empty(), "aether arrows hidden while helix plans")
	var aether_ring_visible := false
	for player in cycle.players:
		if player.team != MatchRules.Team.HOME:
			continue
		var piece: PlayerPiece = cycle_main.pieces.get(player.id)
		if piece != null and piece.planned:
			aether_ring_visible = true
	_assert(not aether_ring_visible, "aether gold rings hidden while helix plans")
	_assert(
		not cycle.combat_log.as_text(MatchRules.Team.AWAY).contains("PLAN  "),
		"helix match log hides aether plans"
	)
	_fill_plans(cycle, [])
	var helix_end: Dictionary = cycle_main.end_planning()
	_assert(helix_end.get("action") == "resolve", "controller end turn resolves after helix")
	_assert(cycle.player_at(_spot(1, 0)) != null, "queued move applied on resolve")
	_assert(cycle.combat_log.as_text().contains("MOVE"), "match log recorded the move")
	cycle_main.queue_free()

	var auto_main: Node = packed.instantiate()
	root.add_child(auto_main)
	auto_main.animate_moves = false
	var auto_model: MatchModel = auto_main.model
	var auto_except := {}
	var last_queue: Dictionary = {}
	for home_i in range(MatchRules.ACTIONS_PER_SIDE):
		var dummy := _dummy_empty_move(auto_model, MatchRules.Team.HOME, auto_except)
		_assert(not dummy.is_empty(), "needed an aether dummy move for auto-end")
		var mover: PlayerState = dummy.player
		auto_except[mover.id] = true
		auto_main.selected_id = mover.id
		last_queue = auto_main.perform_action({id = "move", dest = dummy.dest, label = "Move"})
	_assert(last_queue.get("action") == "queue", "third player with leftover AP does not auto-end")
	var done_except := {}
	var last_done: Dictionary = {}
	for home_id in auto_except:
		done_except[home_id] = true
		auto_main.selected_id = int(home_id)
		last_done = auto_main.select_command("done")
	_assert(last_done.get("action") == "end_planning", "marking the third leftover player done auto-ends")
	_assert(auto_model.current_team == MatchRules.Team.AWAY, "helix plans after three done players")
	auto_except = {}
	last_queue = {}
	for away_i in range(MatchRules.ACTIONS_PER_SIDE):
		var dummy := _dummy_empty_move(auto_model, MatchRules.Team.AWAY, auto_except)
		_assert(not dummy.is_empty(), "needed a helix dummy move after aether auto-end")
		var mover: PlayerState = dummy.player
		auto_except[mover.id] = true
		auto_main.selected_id = mover.id
		last_queue = auto_main.perform_action({id = "move", dest = dummy.dest, label = "Move"})
	_assert(last_queue.get("action") == "queue", "third helix player with leftover AP does not auto-resolve after aether done")
	last_queue = auto_main.end_planning()
	_assert(last_queue.get("action") == "resolve", "helix end turn still resolves after aether auto-end")
	_assert(auto_model.current_team == MatchRules.Team.HOME, "aether plans the next cycle after done auto-end")
	auto_main.queue_free()

	auto_main = packed.instantiate()
	root.add_child(auto_main)
	auto_main.animate_moves = false
	auto_model = auto_main.model
	auto_except = {}
	last_queue = {}
	for home_i in range(MatchRules.ACTIONS_PER_SIDE):
		var dummy := _dummy_empty_move(auto_model, MatchRules.Team.HOME, auto_except)
		_assert(not dummy.is_empty(), "needed an aether dummy move for leftover auto-end")
		var mover: PlayerState = dummy.player
		auto_except[mover.id] = true
		auto_main.selected_id = mover.id
		last_queue = auto_main.perform_action({id = "move", dest = dummy.dest, label = "Move"})
	_assert(last_queue.get("action") == "queue", "three leftover-AP players still need End Turn without done")
	last_queue = auto_main.end_planning()
	_assert(last_queue.get("action") == "end_planning", "end turn after three aether players")
	_assert(auto_model.current_team == MatchRules.Team.AWAY, "helix plans after aether locks in")
	auto_except = {}
	for away_i in range(MatchRules.ACTIONS_PER_SIDE):
		var dummy := _dummy_empty_move(auto_model, MatchRules.Team.AWAY, auto_except)
		_assert(not dummy.is_empty(), "needed a helix dummy move for auto-resolve")
		var mover: PlayerState = dummy.player
		auto_except[mover.id] = true
		auto_main.selected_id = mover.id
		last_queue = auto_main.perform_action({id = "move", dest = dummy.dest, label = "Move"})
	_assert(last_queue.get("action") == "queue", "third helix player with leftover AP does not auto-resolve")
	last_queue = auto_main.end_planning()
	_assert(last_queue.get("action") == "resolve", "helix end turn resolves the cycle")
	_assert(auto_model.current_team == MatchRules.Team.HOME, "aether plans the next cycle after auto-resolve")
	auto_main.queue_free()

	var early_main: Node = packed.instantiate()
	root.add_child(early_main)
	early_main.animate_moves = false
	early_main.handle_cell_clicked(MatchRules.CENTER_SPOT)
	early_main.select_command("move")
	var early_choice: Dictionary = early_main.handle_cell_clicked(_spot(1, 0))
	_assert(early_choice.get("action") == "queue", "first action only queues")
	_assert(early_main.model.current_team == MatchRules.Team.HOME, "one action does not auto-end")
	var early_end: Dictionary = early_main.end_planning()
	_assert(early_end.get("action") == "end_planning", "end turn with one queued action is allowed")
	_assert(early_main.model.current_team == MatchRules.Team.AWAY, "helix plans after a premature end turn")
	early_main.queue_free()

	var skip_main: Node = packed.instantiate()
	root.add_child(skip_main)
	skip_main.animate_moves = false
	_assert(not skip_main.hud._end_turn.disabled, "end turn stays enabled before any queue")
	var skip_end: Dictionary = skip_main.end_planning()
	_assert(skip_end.get("action") == "end_planning", "end turn with no queued action is allowed")
	_assert(skip_main.model.current_team == MatchRules.Team.AWAY, "helix plans after an empty end turn")
	_assert(not skip_main.hud._end_turn.disabled, "helix can also end with an empty queue")
	var skip_resolve: Dictionary = skip_main.end_planning()
	_assert(skip_resolve.get("action") == "resolve", "empty helix end turn still resolves the cycle")
	_assert(skip_main.model.current_team == MatchRules.Team.HOME, "aether plans after an empty cycle")
	skip_main.queue_free()

	var net_main: Node = packed.instantiate()
	root.add_child(net_main)
	net_main.animate_moves = false
	net_main.model.scripted_first_intercept_wins = false
	var net_st: PlayerState = net_main.model.player_at(MatchRules.CENTER_SPOT)
	net_st.pos = Vector2i(2, MatchRules.CENTER_Y)
	net_st.facing = Vector2i(-1, 0)
	net_main.model.ball.pos = net_st.pos
	net_main._refresh()
	net_main.handle_cell_clicked(Vector2i(2, MatchRules.CENTER_Y))
	var pass_net: Dictionary = net_main.select_command("pass")
	_assert(pass_net.get("ok", false), "carrier near the net can pick pass")
	var to_net: Dictionary = net_main.handle_cell_clicked(MatchRules.HOME_NET)
	_assert(to_net.get("action") == "queue", "clicking the keeper in the net queues a pass")
	var net_plan: Dictionary = net_main.model.plan_of(net_st.id)
	_assert(str(net_plan.get("action", "")) == "pass", "striker queued a pass")
	_assert(net_plan.get("dest", Vector2i.ZERO) == MatchRules.HOME_NET, "pass destination is the net")
	net_main.queue_free()

	var offside_main: Node = packed.instantiate()
	root.add_child(offside_main)
	offside_main.animate_moves = false
	var off_model: MatchModel = offside_main.model
	var off_st := off_model.player_at(MatchRules.CENTER_SPOT)
	var off_mate := off_model.player_at(_spot(0, -1))
	off_st.pos = Vector2i(23, MatchRules.CENTER_Y)
	off_model.ball.pos = off_st.pos
	off_mate.pos = Vector2i(24, MatchRules.CENTER_Y)
	offside_main._refresh()
	offside_main.handle_cell_clicked(Vector2i(23, MatchRules.CENTER_Y))
	off_model.scripted_first_intercept_wins = false
	var offside_pick: Dictionary = offside_main.select_command("pass")
	_assert(offside_pick.get("action") == "command", "adjacent offside teammate is a pass target")
	var offside_click: Dictionary = offside_main.handle_cell_clicked(Vector2i(24, MatchRules.CENTER_Y))
	_assert(offside_click.get("action") == "queue", "clicking the offside teammate queues the pass")
	_assert(off_st.has_ball, "offside pass has not resolved yet")
	offside_main.queue_free()
	await process_frame


func _test_game_settings() -> void:
	print("-- game settings")
	var cfg := GameSettings.new()
	_assert(is_equal_approx(cfg.anim_scale(), 1.0), "default animation speed is 1x")
	cfg.set_animation_speed(1)
	_assert(is_equal_approx(cfg.anim_scale(), 5.0), "speed 1 is 5x slower")
	cfg.set_animation_speed(10)
	_assert(is_equal_approx(cfg.anim_scale(), 0.5), "speed 10 is 2x faster")
	cfg.set_animation_speed(99)
	_assert(cfg.animation_speed == 10, "animation speed clamps to 10")
	cfg.set_animation_speed(0)
	_assert(cfg.animation_speed == 1, "animation speed clamps to 1")


func _test_game_menu() -> void:
	print("-- game menu")
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	main.animate_moves = false
	_assert(not main.menu.is_open(), "menu starts closed")

	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	main._unhandled_input(esc)
	_assert(main.menu.is_open(), "escape opens the pause menu")
	_assert(paused, "pause menu pauses the match")
	_assert(main.menu._main_panel.visible, "main menu is the first screen")
	_assert(main.menu._resume_btn != null, "menu lists resume")
	_assert(main.menu._new_game_btn != null, "menu lists new game")
	_assert(main.menu._options_btn != null, "menu lists options")
	_assert(main.menu._exit_btn != null, "menu lists exit")

	main.menu._on_options()
	_assert(main.menu._options_panel.visible, "options opens the second screen")
	_assert(not main.menu._main_panel.visible, "main menu hides while options is open")
	_assert(main.menu._end_turn_check != null, "options has the end-turn checkbox")
	_assert(
		is_equal_approx(main.menu._speed_slider.min_value, 1.0)
		and is_equal_approx(main.menu._speed_slider.max_value, 10.0),
		"speed slider is 1 to 10"
	)
	main.menu._end_turn_check.button_pressed = true
	_assert(main.settings.require_end_turn, "checkbox sets require end turn")
	_assert(main.hud.require_end_turn, "hud picks up require end turn")
	main.menu._speed_slider.value = 8
	_assert(main.settings.animation_speed == 8, "slider sets animation speed")

	main.menu._on_escape()
	_assert(main.menu.is_open() and main.menu._main_panel.visible, "escape from options returns to the main menu")
	main.menu._on_escape()
	_assert(not main.menu.is_open(), "escape from the main menu resumes")
	_assert(not paused, "resuming unpauses the match")

	main._unhandled_input(esc)
	_assert(main.menu.is_open(), "escape opens the pause menu again")
	main.menu._resume_btn.pressed.emit()
	_assert(not main.menu.is_open(), "resume returns to the match")
	_assert(not paused, "resume unpauses the match")

	var except := {}
	var last := {}
	for _i in range(MatchRules.ACTIONS_PER_SIDE):
		var dummy := _dummy_empty_move(main.model, MatchRules.Team.HOME, except)
		_assert(not dummy.is_empty(), "needed an aether dummy move for required end turn")
		var mover: PlayerState = dummy.player
		except[mover.id] = true
		main.selected_id = mover.id
		last = main.perform_action({id = "move", dest = dummy.dest, label = "Move"})
	_assert(last.get("action") == "queue", "third action only queues when end turn is required")
	_assert(main.model.current_team == MatchRules.Team.HOME, "aether still plans until end turn")
	_assert(not main.hud._end_turn.text.contains("CONFIRM"), "three leftover-AP players are not a full 6-AP lock")
	var locked: Dictionary = main.end_planning()
	_assert(locked.get("action") == "end_planning", "end turn still locks after three queued actions")
	_assert(main.model.current_team == MatchRules.Team.AWAY, "helix plans after a confirmed end turn")

	main.model.home_score = 3
	main.start_new_game()
	_assert(main.model.home_score == 0 and main.model.away_score == 0, "new game clears the score")
	_assert(main.model.current_team == MatchRules.Team.HOME, "new game is aether kickoff")
	_assert(main.model.player_at(MatchRules.CENTER_SPOT).has_ball, "new game restores kickoff possession")
	_assert(not main.menu.is_open(), "new game closes the menu")
	_assert(not paused, "new game unpauses")
	_assert(main.settings.require_end_turn, "new game keeps options")
	_assert(main.settings.animation_speed == 8, "new game keeps animation speed")

	main.menu.open_title()
	_assert(main.menu.is_title_open(), "title screen can open")
	_assert(main.menu._hotseat_btn != null, "title lists new hotseat")
	_assert(main.menu._vs_ai_btn != null, "title lists new vs ai")
	_assert(main.menu._title_exit_btn != null, "title lists exit")
	main.menu._on_escape()
	_assert(main.menu.is_title_open(), "escape does not leave the title screen")
	main.menu._hotseat_btn.pressed.emit()
	_assert(not main.menu.is_open(), "new hotseat closes the title")
	_assert(not main.menu.is_title_open(), "hotseat leaves title mode")
	_assert(main.model.player_at(MatchRules.CENTER_SPOT).has_ball, "hotseat starts at kickoff")
	_assert(not paused, "hotseat unpauses")
	_assert(not main.vs_ai, "hotseat is not vs-ai")
	main.queue_free()
	paused = false
	await process_frame


func _test_vs_ai() -> void:
	print("-- vs ai")
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	main.animate_moves = false
	main.start_vs_ai()
	_assert(main.vs_ai, "new vs ai sets the mode")
	_assert(main.model.current_team == MatchRules.Team.HOME, "human still plans aether")
	_assert(main.model.plan_count(MatchRules.Team.HOME) == 0, "aether has not queued yet")
	var helix_n: int = main.model.plan_count(MatchRules.Team.AWAY)
	_assert(helix_n >= 1, "helix preplanned before aether queued")
	_assert(
		helix_n <= MatchRules.ACTIONS_PER_SIDE * MatchRules.PLAYER_ACTION_POINTS,
		"helix stays within 3 players × 6 AP"
	)
	_assert(
		main.model.acting_player_count(MatchRules.Team.AWAY) <= MatchRules.ACTIONS_PER_SIDE,
		"helix does not queue a fourth player"
	)
	var helix_dests := {}
	for plan in main.model.plans_for(MatchRules.Team.AWAY):
		var hid := int(plan.get("player_id", -1))
		var helix: PlayerState = main.model.player_by_id(hid)
		_assert(helix != null and helix.team == MatchRules.Team.AWAY, "helix plan is a helix player")
		var dest: Vector2i = plan.get("dest", Vector2i.ZERO)
		_assert(MatchRules.in_bounds(dest), "helix destination is on the pitch")
		helix_dests[dest] = true
	var aether_except := {}
	var last := {}
	for _i in range(MatchRules.ACTIONS_PER_SIDE):
		var dummy := _dummy_empty_move(main.model, MatchRules.Team.HOME, aether_except)
		_assert(not dummy.is_empty(), "needed an aether dummy move vs ai")
		var mover: PlayerState = dummy.player
		aether_except[mover.id] = true
		main.selected_id = mover.id
		last = main.perform_action({id = "move", dest = dummy.dest, label = "Move"})
	_assert(last.get("action") == "queue", "three 1-AP aether plans do not auto-lock vs ai")
	last = main.end_planning()
	_assert(last.get("action") == "resolve", "aether lock resolves immediately vs ai")
	_assert(main.model.current_team == MatchRules.Team.HOME, "aether plans the next cycle vs ai")
	_assert(main.model.plan_count(MatchRules.Team.AWAY) >= 1, "helix preplanned the next cycle")
	main.queue_free()

	var skip_ai: Node = packed.instantiate()
	root.add_child(skip_ai)
	await process_frame
	skip_ai.animate_moves = false
	skip_ai.start_vs_ai()
	_assert(not skip_ai.hud._end_turn.disabled, "vs ai still allows an empty end turn")
	var skip_ai_end: Dictionary = skip_ai.end_planning()
	_assert(skip_ai_end.get("action") == "resolve", "empty aether end vs ai still resolves helix plans")
	_assert(skip_ai.model.current_team == MatchRules.Team.HOME, "aether plans the next cycle after skipping")
	_assert(skip_ai.model.plan_count(MatchRules.Team.AWAY) >= 1, "helix preplanned after an empty aether lock")
	skip_ai.queue_free()

	var kick: Node = packed.instantiate()
	root.add_child(kick)
	await process_frame
	kick.animate_moves = false
	kick.start_vs_ai()
	var shooter: PlayerState = kick.model.player_at(MatchRules.CENTER_SPOT)
	_assert(shooter != null, "kickoff striker exists")
	shooter.pos = Vector2i(MatchRules.GRID_WIDTH - 1, MatchRules.CENTER_Y)
	kick.model.ball.pos = shooter.pos
	kick.model.scripted_shot_outcome = "goal"
	var scored: Dictionary = kick.model.apply_shoot(shooter.id)
	_assert(scored.get("goal", false), "scripted shot is a goal")
	_assert(kick.model.current_team == MatchRules.Team.AWAY, "helix would kick off after conceding")
	kick._begin_vs_ai_cycle()
	_assert(kick.model.current_team == MatchRules.Team.HOME, "vs-ai still puts aether in the chair after scoring")
	_assert(kick.model.awaiting_other_side, "helix is already locked after aether scores vs-ai")
	_assert(kick.model.plan_count(MatchRules.Team.AWAY) >= 1, "helix still preplans on its kickoff")
	var helix_kicker: PlayerState = kick.model.player_at(MatchRules.AWAY_SPOT)
	_assert(helix_kicker != null and helix_kicker.has_ball, "helix #9 has the ball on the mirrored centre")
	_assert(kick._plan_markers().is_empty(), "helix plans stay hidden vs-ai after aether scores")
	var click_helix: Dictionary = kick.handle_cell_clicked(MatchRules.AWAY_SPOT)
	_assert(not click_helix.get("ok", false), "human cannot retarget helix after scoring vs-ai")
	var aether_pick: PlayerState = null
	for player in kick.model.players:
		if player.team == MatchRules.Team.HOME and kick.model.can_select(player):
			aether_pick = player
			break
	_assert(aether_pick != null, "aether has a selectable player after scoring vs-ai")
	var click_aether: Dictionary = kick.handle_cell_clicked(aether_pick.pos)
	_assert(click_aether.get("ok", false), "human can plan aether immediately after scoring vs-ai")
	_assert(click_aether.get("action") == "select", "click selects aether after scoring vs-ai")
	var aether_lock: Dictionary = kick.end_planning()
	_assert(aether_lock.get("action") == "resolve", "aether lock after helix kickoff vs-ai resolves immediately")
	_assert(kick.model.current_team == MatchRules.Team.HOME, "aether plans the next cycle after helix kickoff vs-ai")
	kick.queue_free()
	paused = false
	await process_frame
