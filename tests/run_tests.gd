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
	_test_attacking_third()
	_test_offside_position()
	_test_kickoff()
	_test_turn_and_selection()
	_test_possession()
	_test_ball_travels_with_carrier()
	_test_cannot_stack()
	_test_attributes()
	_test_dribble_win()
	_test_dribble_loss()
	_test_square_fight()
	_test_challenge_takes_ball()
	_test_contest_preview()
	_test_pass()
	_test_intercepts()
	_test_swap_and_choice()
	_test_offside()
	_test_shooting()
	_test_planning_and_resolve()
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


func _test_bounds() -> void:
	print("-- bounds")
	_assert(MatchRules.in_bounds(Vector2i(0, 0)), "origin in bounds")
	_assert(MatchRules.in_bounds(Vector2i(17, 8)), "far corner in bounds")
	_assert(MatchRules.in_bounds(MatchRules.HOME_NET), "aether net is playable")
	_assert(MatchRules.in_bounds(MatchRules.AWAY_NET), "helix net is playable")
	_assert(not MatchRules.in_bounds(Vector2i(-1, 0)), "negative x beside the net is out")
	_assert(not MatchRules.in_bounds(Vector2i(18, 0)), "x=18 beside the net is out")
	_assert(not MatchRules.in_bounds(Vector2i(-1, 2)), "net-adjacent off-pitch is out")
	_assert(not MatchRules.in_bounds(Vector2i(0, 9)), "y=9 out")
	var net_steps := MatchRules.move_destinations(MatchRules.HOME_NET, {})
	_assert(net_steps.size() == 3, "keeper in the net has 3 steps onto the pitch")
	_assert(Vector2i(0, 4) in net_steps, "net opens onto the old goal-line tile")


func _test_adjacency() -> void:
	print("-- adjacency")
	_assert(MatchRules.is_adjacent(Vector2i(5, 4), Vector2i(6, 5)), "diagonal is 1 tile")
	_assert(MatchRules.is_adjacent(Vector2i(5, 4), Vector2i(5, 5)), "orthogonal is 1 tile")
	_assert(not MatchRules.is_adjacent(Vector2i(5, 4), Vector2i(5, 4)), "stay put is not a move")
	_assert(not MatchRules.is_adjacent(Vector2i(5, 4), Vector2i(7, 4)), "2 tiles is too far")


func _test_move_destinations() -> void:
	print("-- destinations")
	var center := MatchRules.move_destinations(Vector2i(5, 4), {})
	_assert(center.size() == 8, "open cell has 8 moves")
	var corner := MatchRules.move_destinations(Vector2i(0, 0), {})
	_assert(corner.size() == 3, "corner has 3 moves")
	var blocked := MatchRules.move_destinations(Vector2i(5, 4), {Vector2i(5, 5): true})
	_assert(blocked.size() == 7, "occupied neighbour is excluded")
	_assert(Vector2i(5, 5) not in blocked, "blocked cell missing from result")


func _test_attacking_third() -> void:
	print("-- attacking third")
	_assert(MatchRules.is_attacking_third(Vector2i(12, 0), MatchRules.Team.HOME), "home last third starts at x=12")
	_assert(not MatchRules.is_attacking_third(Vector2i(11, 0), MatchRules.Team.HOME), "x=11 is midfield for home")
	_assert(MatchRules.is_attacking_third(Vector2i(5, 0), MatchRules.Team.AWAY), "away last third ends at x=5")
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
	_assert(MatchRules.is_opponent_half(Vector2i(9, 0), MatchRules.Team.HOME), "x=9 is aether's attacking half")
	_assert(not MatchRules.is_opponent_half(Vector2i(8, 0), MatchRules.Team.HOME), "x=8 is aether's own half")


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
	_assert(model.player_at(Vector2i(0, 4)) == null, "goal-line tile in front of aether net is free")


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
	var ok := model.apply_move(home.id, Vector2i(8, 5))
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
	var result := model.apply_move(striker.id, Vector2i(8, 5))
	_assert(result.ok and not result.gained_possession, "moving with the ball is a normal carry")
	_assert(striker.has_ball, "striker kept possession")
	_assert(model.ball.pos == striker.pos, "ball cell matches carrier")


func _test_ball_travels_with_carrier() -> void:
	print("-- ball travel")
	var model := MatchModel.new()
	model.setup_kickoff()
	var striker := model.player_at(MatchRules.CENTER_SPOT)
	model.apply_move(striker.id, Vector2i(8, 5))
	model.ignore_team_gate = true
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	model.apply_move(away.id, Vector2i(9, 6))
	var carry := model.apply_move(striker.id, Vector2i(7, 4))
	_assert(carry.ok, "carrier can carry 1 tile")
	_assert(not carry.gained_possession, "already had the ball")
	_assert(model.ball.pos == Vector2i(7, 4), "ball followed the carrier")
	_assert(striker.has_ball, "possession kept")


func _test_cannot_stack() -> void:
	print("-- stacking")
	var model := MatchModel.new()
	model.setup_kickoff()
	var mid := model.player_at(Vector2i(5, 5))
	var dest := MatchRules.CENTER_SPOT
	var result := model.apply_move(mid.id, dest)
	_assert(not result.ok, "cannot step onto a teammate")
	_assert(mid.pos == Vector2i(5, 5), "mover stayed put")


func _test_attributes() -> void:
	print("-- attributes")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var gk := model.player_at(MatchRules.HOME_NET)
	var cm := model.player_at(Vector2i(5, 3))
	_assert(st.accuracy == 26 and st.control == 9, "striker is accuracy/control leaning")
	_assert(st.stamina == 9 and st.energy == 90 and st.max_energy == 90, "striker stamina fills a 10× energy pool")
	_assert(gk.defense == 13 and gk.control == 11, "keeper is defense/control leaning")
	_assert(gk.stamina == 7 and gk.max_energy == 70, "keeper stamina is lower")
	_assert(cm.accuracy == 12 and cm.defense == 8, "central mid keeps midfield ACC/DEF")
	_assert(cm.stamina == 13, "central mid has the biggest energy pool")
	_assert(st.live_accuracy() == 26, "full energy keeps printed stats")
	st.energy = 0
	_assert(st.live_accuracy() == 13, "empty energy halves ACC with rounding")
	_assert(st.live_defense() == 2, "empty energy halves DEF with rounding")
	st.energy = st.max_energy
	var tired := model.apply_move(st.id, Vector2i(8, 5))
	_assert(tired.ok, "move still works while spending energy")
	_assert(st.energy == 89, "a resolved move costs 1 energy")
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	_assert(away.pos in model.valid_moves(st), "opponent tile is a legal contest dest")
	_assert(away.pos in model.contest_moves(st), "opponent tile is listed as a contest")


func _test_dribble_win() -> void:
	print("-- dribble win")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	model.scripted_attacker_wins = true
	var result := model.apply_move(st.id, MatchRules.AWAY_KICKOFF)
	_assert(result.action == "dribble", "on-ball step onto opponent is a dribble")
	_assert(result.attacker_stat_name == "CTR" and result.defender_stat_name == "DEF", "dribble is CTR vs DEF")
	_assert(result.contest_won, "scripted dribble succeeded")
	_assert(st.pos == MatchRules.AWAY_KICKOFF, "dribbler took the square")
	_assert(away.pos == MatchRules.CENTER_SPOT, "beaten defender was shoved back")
	_assert(st.has_ball and not away.has_ball, "dribbler kept the ball")
	_assert(model.ball.pos == st.pos, "ball followed the successful dribble")


func _test_dribble_loss() -> void:
	print("-- dribble loss")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	model.scripted_attacker_wins = false
	var result := model.apply_move(st.id, MatchRules.AWAY_KICKOFF)
	_assert(result.action == "dribble", "failed attempt is still a dribble")
	_assert(not result.contest_won, "scripted dribble failed")
	_assert(st.pos == MatchRules.CENTER_SPOT, "dribbler stayed put")
	_assert(away.pos == MatchRules.AWAY_KICKOFF, "defender held the square")
	_assert(away.has_ball and not st.has_ball, "defender won the ball")
	_assert(result.lost_possession, "result reports lost possession")


func _test_square_fight() -> void:
	print("-- square fight")
	var model := MatchModel.new()
	model.setup_kickoff()
	var home := model.player_at(Vector2i(8, 3))
	var away := model.player_at(Vector2i(9, 3))
	_assert(not home.has_ball and not away.has_ball, "off-ball challenge starts without possession")
	model.scripted_attacker_wins = true
	var win := model.apply_move(home.id, Vector2i(9, 3))
	_assert(win.action == "challenge", "off-ball step onto opponent is a square fight")
	_assert(win.attacker_stat_name == "CTR" and win.defender_stat_name == "CTR", "square fight is CTR vs CTR")
	_assert(home.pos == Vector2i(9, 3), "winner took the square")
	_assert(away.pos == Vector2i(8, 3), "loser was shoved to the origin")
	_assert(not home.has_ball and not away.has_ball, "no ball changed hands")

	model.scripted_attacker_wins = false
	model.ignore_team_gate = true
	var origin := away.pos
	var dest := home.pos
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
	var decoy := model.player_at(Vector2i(5, 0))
	model.apply_move(decoy.id, Vector2i(5, 1))
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	model.scripted_attacker_wins = true
	model.ignore_team_gate = true
	var result := model.apply_move(away.id, MatchRules.CENTER_SPOT)
	_assert(result.get("action") == "tackle", "off-ball step onto the carrier is a tackle")
	_assert(result.get("attacker_stat_name") == "DEF" and result.get("defender_stat_name") == "CTR", "tackle is DEF vs CTR")
	_assert(result.get("attacker_label") == away.label(), "log names the tackler")
	_assert(result.get("defender_label") == st.label(), "log names the carrier")
	_assert(result.get("gained_possession"), "winner of the tackle took the ball")
	_assert(away.has_ball and not st.has_ball, "challenger is the new carrier")
	_assert(away.pos == MatchRules.CENTER_SPOT and st.pos == MatchRules.AWAY_KICKOFF, "players swapped")


func _test_contest_preview() -> void:
	print("-- contest preview")
	_assert(MatchRules.scaled_stat(13, 0, 9) == 7, "zero energy scales 13 to 7")
	_assert(MatchRules.scaled_stat(13, 9, 9) == 13, "full energy keeps 13")
	_assert(MatchRules.PASS_RANGE == 3, "pass range is 3 tiles")
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
	var decoy := model.player_at(Vector2i(5, 0))
	model.apply_move(decoy.id, Vector2i(5, 0))
	var tackle := MatchRules.contest_preview(away, st)
	_assert(tackle.action == "tackle", "preview of off-ball vs carrier is a tackle")
	_assert(tackle.text.begins_with("tackle "), "tackle hint starts with tackle")
	_assert(tackle.text.contains("%d DEF" % away.defense), "tackle hint uses mover DEF")
	_assert(tackle.text.contains("%d CTR" % st.control), "tackle hint uses carrier CTR")
	_assert(MatchRules.attacker_wins_ties(st, away), "dribble ties go to the carrier")
	_assert(not MatchRules.attacker_wins_ties(away, st), "tackle ties go to the carrier")
	var decoy_vs_wing := MatchRules.attacker_wins_ties(
		decoy, model.player_at(Vector2i(12, 0)), MatchRules.Team.HOME
	)
	_assert(decoy_vs_wing, "square fight ties go to the team in possession")


func _test_pass() -> void:
	print("-- pass")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var near := model.player_at(Vector2i(8, 3))
	var gk := model.player_at(MatchRules.HOME_NET)
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	_assert(model.can_pass_to(st, near), "can pass to a teammate within 3")
	_assert(MatchRules.chebyshev(st.pos, gk.pos) == 9, "keeper in the net is 9 tiles away")
	_assert(not model.can_pass_to(st, gk), "cannot pass beyond 3 tiles")
	_assert(not model.can_pass_to(st, away), "cannot pass to an opponent")
	_assert(not model.can_pass_to(near, st), "non-carrier cannot pass")
	model.scripted_first_intercept_wins = false
	var result := model.apply_pass(st.id, near.id)
	_assert(result.ok and result.action == "pass", "pass succeeds")
	_assert(near.has_ball and not st.has_ball, "receiver has the ball")
	_assert(model.ball.pos == near.pos, "ball moved to the receiver")
	_assert(st.pos == MatchRules.CENTER_SPOT and near.pos == Vector2i(8, 3), "neither player moved")
	_assert(model.current_team == MatchRules.Team.HOME, "a pass does not switch the planning team")
	_assert(not model.can_queue(away), "helix still cannot queue during aether planning")

	var open := MatchModel.new()
	open.setup_kickoff()
	var kicker := open.player_at(MatchRules.CENTER_SPOT)
	_assert(open.can_pass_to_cell(kicker, Vector2i(8, 5)), "can pass to an empty adjacent square")
	_assert(open.can_pass_to_cell(kicker, Vector2i(6, 4)), "can pass to an empty square 2 tiles away")
	_assert(not open.can_pass_to_cell(kicker, Vector2i(4, 4)), "cannot pass 4 tiles to empty")
	var empty_actions := open.actions_for(kicker, Vector2i(8, 5))
	_assert(empty_actions.size() == 2, "adjacent empty square is move or pass")
	_assert(empty_actions[0].id == "move" and empty_actions[1].id == "pass", "move and pass are both offered")
	var through := open.actions_for(kicker, Vector2i(6, 4))
	_assert(through.size() == 1 and through[0].id == "pass", "empty square 2 tiles away is pass only")
	open.scripted_first_intercept_wins = false
	var laid := open.apply_pass_to(kicker.id, Vector2i(6, 4))
	_assert(laid.ok and laid.action == "pass", "pass to empty square succeeds")
	_assert(int(laid.get("receiver_id", 0)) < 0, "empty-square pass has no receiver")
	_assert(laid.dest == Vector2i(6, 4), "empty-square pass records the landing tile")
	_assert(not kicker.has_ball, "passer released the ball")
	_assert(open.ball.is_loose() and open.ball.pos == Vector2i(6, 4), "ball sits loose on the target square")
	_assert(kicker.pos == MatchRules.CENTER_SPOT, "passer stayed put")

	var back := MatchModel.new()
	back.setup_kickoff()
	var back_st := back.player_at(MatchRules.CENTER_SPOT)
	var back_gk := back.player_at(MatchRules.HOME_NET)
	var back_lcb := back.player_at(Vector2i(2, 3))
	back_st.pos = Vector2i(5, 4)
	back.ball.pos = back_st.pos
	back.scripted_first_intercept_wins = false
	var to_cb := back.apply_pass(back_st.id, back_lcb.id)
	_assert(to_cb.ok and back_lcb.has_ball, "back line can receive a 3-tile pass")
	_assert(back.can_pass_to(back_lcb, back_gk), "can pass to the keeper in the net")
	_assert(MatchRules.HOME_NET in back.pass_cells(back_lcb), "own net highlights as a pass tile")
	_assert(not back.can_pass_to_cell(back_lcb, MatchRules.AWAY_NET), "cannot pass into the opponent net")
	var gk_spot := back_gk.pos
	back_gk.pos = Vector2i(0, 4)
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

	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var lane := Vector2i(11, 4)
	var threats := model.interceptors_for_pass(st, lane)
	_assert(threats.size() >= 2, "a lane through midfield has interceptors")
	var preview := model.pass_preview(st, lane)
	_assert(preview.text.contains("ACC vs"), "preview lists ACC vs DEF")
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


func _test_swap_and_choice() -> void:
	print("-- swap and choice")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var near := model.player_at(Vector2i(8, 3))
	var wing := model.player_at(Vector2i(5, 0))
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	var adjacent := model.actions_for(st, near.pos)
	_assert(adjacent.size() == 2, "adjacent teammate offers two actions")
	_assert(adjacent[0].id == "pass" and adjacent[1].id == "swap", "pass and swap are both offered")
	var lcm := model.player_at(Vector2i(5, 3))
	var far := model.actions_for(st, lcm.pos)
	_assert(far.size() == 1 and far[0].id == "pass", "3-tile teammate is pass only")
	_assert(not model.can_swap(st, lcm), "cannot swap from 3 tiles away")
	_assert(not model.can_swap(st, wing), "cannot swap from the wing")
	_assert(not model.can_swap(st, away), "cannot swap with an opponent")
	var swapped := model.apply_swap(st.id, near.id)
	_assert(swapped.ok and swapped.action == "swap", "swap succeeds")
	_assert(st.pos == Vector2i(8, 3) and near.pos == MatchRules.CENTER_SPOT, "players swapped places")
	_assert(st.has_ball and not near.has_ball, "carrier kept the ball")
	_assert(model.ball.pos == st.pos, "ball followed the carrier")
	_assert(model.current_team == MatchRules.Team.HOME, "a swap does not switch the planning team")


func _test_offside() -> void:
	print("-- offside")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	var mate := model.player_at(Vector2i(8, 3))
	st.pos = Vector2i(15, 4)
	model.ball.pos = st.pos
	mate.pos = Vector2i(16, 4)
	_assert(model.is_offside_receiver(st, mate), "teammate ahead of the last line is offside")
	_assert(Vector2i(16, 4) in model.offside_pass_cells(st), "offside target is listed")
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
	_assert(taker.pos == Vector2i(16, 4) and taker.has_ball, "closest opponent took the offside tile and the ball")
	_assert(mate.pos == taker_from, "offside player was swapped to the taker's old tile")
	_assert(not st.has_ball, "passer lost the ball")
	_assert(model.current_team == MatchRules.Team.HOME, "offside does not switch the planning team")
	_assert(model.ball.pos == taker.pos, "ball sits on the restart tile")

	var onside := MatchModel.new()
	onside.setup_kickoff()
	var kicker := onside.player_at(MatchRules.CENTER_SPOT)
	var partner := onside.player_at(Vector2i(8, 3))
	kicker.pos = Vector2i(7, 3)
	onside.ball.pos = kicker.pos
	partner.pos = Vector2i(8, 3)
	_assert(not onside.is_offside_receiver(kicker, partner), "behind the last line is onside")
	onside.scripted_first_intercept_wins = false
	var completed := onside.apply_pass(kicker.id, partner.id)
	_assert(completed.ok and completed.action == "pass", "onside pass still completes")
	_assert(partner.has_ball, "onside receiver got the ball")

	var own_half := MatchModel.new()
	own_half.setup_kickoff()
	var holder := own_half.player_at(MatchRules.CENTER_SPOT)
	var wing := own_half.player_at(Vector2i(5, 0))
	_assert(not own_half.is_offside_receiver(holder, wing), "own-half teammate is not offside")

	var ground := MatchModel.new()
	ground.setup_kickoff()
	var carrier := ground.player_at(MatchRules.CENTER_SPOT)
	carrier.pos = Vector2i(10, 4)
	ground.ball.pos = carrier.pos
	_assert(ground.player_at(Vector2i(13, 4)) == null, "empty square has no receiver")
	ground.scripted_first_intercept_wins = false
	var laid := ground.apply_pass_to(carrier.id, Vector2i(13, 4))
	_assert(laid.ok and laid.action == "pass", "pass to an empty square is not offside")
	_assert(ground.ball.is_loose() and ground.ball.pos == Vector2i(13, 4), "empty-square pass stayed a ground pass")

	var stolen := MatchModel.new()
	stolen.setup_kickoff()
	var passer := stolen.player_at(MatchRules.CENTER_SPOT)
	var target := stolen.player_at(Vector2i(8, 3))
	passer.pos = Vector2i(14, 4)
	stolen.ball.pos = passer.pos
	target.pos = Vector2i(16, 4)
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
	while model.plan_count() < MatchRules.ACTIONS_PER_SIDE:
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
	var queued := model.queue_plan(st.id, {id = "move", dest = Vector2i(8, 5), label = "Move"})
	_assert(queued.ok and queued.action == "queue", "carrier can queue a move")
	_assert(st.pos == MatchRules.CENTER_SPOT, "queued move does not apply yet")
	_assert(model.plan_count() == 1, "one plan stored")
	_assert(model.can_end_planning(), "end turn is allowed after the first plan")
	_assert(not model.planning_complete(), "one plan is not a full side")
	var away := model.player_at(MatchRules.AWAY_KICKOFF)
	_assert(not model.can_queue(away), "cannot queue a helix player during aether planning")
	_fill_plans(model, [])
	_assert(model.plan_count() == 3, "three aether plans")
	_assert(model.planning_complete(), "three plans fill the side")
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
	_assert(st.pos == Vector2i(8, 5), "queued aether move applied on resolve")
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
	held.scripted_attacker_wins = false
	_fill_plans(held, [{
		player_id = held_st.id,
		id = "move",
		dest = Vector2i(8, 5),
		label = "Move",
	}])
	held.end_planning()
	_fill_plans(held, [{
		player_id = held_away.id,
		id = "move",
		dest = Vector2i(8, 5),
		label = "Move",
	}])
	var held_result := held.end_planning()
	_assert(held_result.action == "resolve", "arrival tackle cycle resolved")
	_assert(held_st.pos == Vector2i(8, 5) and held_st.has_ball, "carrier won the arrival tackle and kept the ball")
	_assert(held_away.pos == MatchRules.AWAY_KICKOFF, "failed tackler stayed put")
	_assert(held.combat_log.as_text().contains("TACKLE"), "log records the arrival as a tackle")

	var poke := MatchModel.new()
	poke.setup_kickoff()
	var poke_st := poke.player_at(MatchRules.CENTER_SPOT)
	var poke_away := poke.player_at(MatchRules.AWAY_KICKOFF)
	poke.scripted_attacker_wins = true
	_fill_plans(poke, [{
		player_id = poke_st.id,
		id = "move",
		dest = Vector2i(8, 5),
		label = "Move",
	}])
	poke.end_planning()
	_fill_plans(poke, [{
		player_id = poke_away.id,
		id = "move",
		dest = Vector2i(8, 5),
		label = "Move",
	}])
	var poke_result := poke.end_planning()
	_assert(poke_result.action == "resolve", "arrival tackle steal resolved")
	_assert(poke_away.pos == Vector2i(8, 5) and poke_away.has_ball, "tackler won the square and stole the ball")
	_assert(poke_st.pos == MatchRules.CENTER_SPOT and not poke_st.has_ball, "carrier lost the arrival tackle")

	var square := MatchModel.new()
	square.setup_kickoff()
	var square_mid := square.player_at(Vector2i(8, 3))
	var square_st := square.player_at(MatchRules.CENTER_SPOT)
	var square_away := square.player_at(MatchRules.AWAY_KICKOFF)
	square.scripted_attacker_wins = true
	_fill_plans(square, [
		{
			player_id = square_mid.id,
			id = "move",
			dest = Vector2i(9, 4),
			label = "Move",
		},
		{
			player_id = square_st.id,
			id = "move",
			dest = Vector2i(7, 4),
			label = "Move",
		},
	])
	square.end_planning()
	_fill_plans(square, [{
		player_id = square_away.id,
		id = "move",
		dest = Vector2i(9, 4),
		label = "Move",
	}])
	var square_result := square.end_planning()
	_assert(square_result.action == "resolve", "off-ball arrival contest resolved")
	_assert(square_mid.pos == Vector2i(9, 4), "lower-id mover won the CTR arrival fight")
	_assert(square_away.pos == MatchRules.AWAY_KICKOFF, "CTR arrival loser stayed put")
	_assert(square.combat_log.as_text().contains("SQUARE FIGHT"), "log records the off-ball arrival as a square fight")

	var interrupt := MatchModel.new()
	interrupt.setup_kickoff()
	var carrier := interrupt.player_at(MatchRules.CENTER_SPOT)
	var mate := interrupt.player_at(Vector2i(8, 3))
	var tackler := interrupt.player_at(MatchRules.AWAY_KICKOFF)
	interrupt.scripted_attacker_wins = true
	interrupt.scripted_first_intercept_wins = false
	_fill_plans(interrupt, [{
		player_id = carrier.id,
		id = "pass",
		dest = mate.pos,
		target_id = mate.id,
		label = "Pass",
	}])
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
	var lead_mate := lead.player_at(Vector2i(8, 3))
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
			dest = Vector2i(8, 2),
			label = "Move",
		},
	])
	lead.end_planning()
	_fill_plans(lead, [])
	var led := lead.end_planning()
	_assert(led.action == "resolve", "pass-then-move cycle resolved")
	_assert(lead_mate.pos == Vector2i(8, 2), "receiver moved after the pass")
	_assert(lead_mate.has_ball, "receiver kept the ball and carried it")
	_assert(lead.ball.pos == Vector2i(8, 2), "ball followed the receiver's move")
	_assert(not lead_st.has_ball, "passer no longer has the ball")

	var feed := MatchModel.new()
	feed.setup_kickoff()
	var feed_st := feed.player_at(MatchRules.CENTER_SPOT)
	var feed_mate := feed.player_at(Vector2i(8, 3))
	feed.queue_plan(feed_st.id, {
		id = "pass",
		dest = feed_mate.pos,
		target_id = feed_mate.id,
		label = "Pass",
	})
	_assert(feed.planning_has_ball(feed_mate), "queued pass lets the receiver plan with the ball")
	_assert(not feed.planning_has_ball(feed_st), "passer no longer has planning possession")
	_assert(feed.can_plan_pass_to_cell(feed_mate, Vector2i(8, 1)), "receiver can queue a follow-up pass")
	var feed_acts := feed.actions_for(feed_mate, Vector2i(9, 3))
	var feed_ids: Array = []
	for act in feed_acts:
		feed_ids.append(act.id)
	_assert("dribble" in feed_ids, "receiver can queue a dribble as if they have the ball")

	var fed := MatchModel.new()
	fed.setup_kickoff()
	fed.scripted_first_intercept_wins = false
	fed.scripted_attacker_wins = true
	var fed_st := fed.player_at(MatchRules.CENTER_SPOT)
	var fed_mate := fed.player_at(Vector2i(8, 3))
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
			dest = Vector2i(9, 3),
			label = "Dribble",
		},
	])
	fed.end_planning()
	_fill_plans(fed, [])
	var fed_result := fed.end_planning()
	_assert(fed_result.action == "resolve", "pass-then-dribble cycle resolved")
	_assert(fed_mate.pos == Vector2i(9, 3) and fed_mate.has_ball, "receiver dribbled after the pass arrived")

	var cut := MatchModel.new()
	cut.setup_kickoff()
	cut.scripted_first_intercept_wins = true
	var cut_st := cut.player_at(MatchRules.CENTER_SPOT)
	var cut_mate := cut.player_at(Vector2i(8, 3))
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
			dest = Vector2i(9, 3),
			label = "Dribble",
		},
	])
	cut.end_planning()
	_fill_plans(cut, [])
	var cut_result := cut.end_planning()
	_assert(cut_result.action == "resolve", "intercepted pass-then-dribble resolved")
	_assert(cut_mate.pos == Vector2i(8, 3), "receiver dribble did not play after the intercept")
	_assert(not cut_mate.has_ball, "receiver never got the intercepted pass")
	_assert(cut.combat_log.as_text().contains("pass did not arrive"), "log cancels the expected-ball dribble")

	var collect := MatchModel.new()
	collect.setup_kickoff()
	collect.scripted_first_intercept_wins = false
	var collect_st := collect.player_at(MatchRules.CENTER_SPOT)
	var collect_mid := collect.player_at(Vector2i(8, 3))
	_fill_plans(collect, [
		{
			player_id = collect_st.id,
			id = "pass",
			dest = Vector2i(7, 3),
			target_id = -1,
			label = "Pass",
		},
		{
			player_id = collect_mid.id,
			id = "move",
			dest = Vector2i(7, 3),
			label = "Move",
		},
	])
	collect.end_planning()
	_fill_plans(collect, [])
	var collected := collect.end_planning()
	_assert(collected.action == "resolve", "ground-pass collect cycle resolved")
	_assert(collect_mid.pos == Vector2i(7, 3), "teammate stepped onto the pass square")
	_assert(collect_mid.has_ball, "teammate collected the loose pass")
	_assert(not collect.ball.is_loose(), "ball is no longer loose after the collect")

	var steal := MatchModel.new()
	steal.setup_kickoff()
	steal.scripted_first_intercept_wins = false
	var steal_st := steal.player_at(MatchRules.CENTER_SPOT)
	var steal_helix := steal.player_at(MatchRules.AWAY_KICKOFF)
	_fill_plans(steal, [{
		player_id = steal_st.id,
		id = "pass",
		dest = Vector2i(8, 5),
		target_id = -1,
		label = "Pass",
	}])
	steal.end_planning()
	_fill_plans(steal, [{
		player_id = steal_helix.id,
		id = "move",
		dest = Vector2i(8, 5),
		label = "Move",
	}])
	var stolen_pass := steal.end_planning()
	_assert(stolen_pass.action == "resolve", "opponent collect cycle resolved")
	_assert(steal_helix.pos == Vector2i(8, 5), "helix stepped onto the pass square")
	_assert(steal_helix.has_ball, "helix collected the loose pass")
	_assert(not steal_st.has_ball, "passer does not keep a collected ground pass")

	var early := MatchModel.new()
	early.setup_kickoff()
	var early_st := early.player_at(MatchRules.CENTER_SPOT)
	early.queue_plan(early_st.id, {id = "move", dest = Vector2i(8, 5), label = "Move"})
	var early_lock := early.end_planning()
	_assert(early_lock.ok and early_lock.action == "end_planning", "end turn with one plan hands to helix")
	_assert(early.current_team == MatchRules.Team.AWAY, "helix plans after a premature aether end")
	_assert(early.home_plans.size() == 1, "aether's single plan is kept")
	_assert(early_st.pos == MatchRules.CENTER_SPOT, "premature end does not resolve yet")
	var early_helix := early.player_at(MatchRules.AWAY_KICKOFF)
	early.queue_plan(early_helix.id, {id = "move", dest = Vector2i(9, 6), label = "Move"})
	var early_resolve := early.end_planning()
	_assert(early_resolve.ok and early_resolve.action == "resolve", "helix can also end early")
	_assert(early_st.pos == Vector2i(8, 5), "lone aether plan still resolved")
	_assert(early_helix.pos == Vector2i(9, 6), "lone helix plan still resolved")

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


func _test_shooting() -> void:
	print("-- shooting")
	var box := MatchRules.penalty_tiles(MatchRules.AWAY_NET)
	_assert(box.size() == 3, "penalty box is the three tiles on the goal line")
	_assert(Vector2i(17, 4) in box, "centre goal-line tile is in the box")
	_assert(MatchRules.is_in_shooting_zone(Vector2i(17, 4), MatchRules.AWAY_NET), "box is a shooting zone")
	_assert(MatchRules.is_in_shooting_zone(Vector2i(16, 2), MatchRules.AWAY_NET), "corner-touching ring can shoot")
	_assert(not MatchRules.is_in_shooting_zone(Vector2i(15, 4), MatchRules.AWAY_NET), "one tile further is too far")
	_assert(not MatchRules.is_in_shooting_zone(MatchRules.CENTER_SPOT, MatchRules.AWAY_NET), "midfield cannot shoot")

	var close := MatchRules.shot_geometry(Vector2i(17, 4), MatchRules.AWAY_NET)
	var deep := MatchRules.shot_geometry(Vector2i(16, 4), MatchRules.AWAY_NET)
	var wide := MatchRules.shot_geometry(Vector2i(17, 2), MatchRules.AWAY_NET)
	_assert(close.distance < deep.distance, "the six-yard tile is closer than the ring")
	_assert(close.angle_deg < 1.0, "shot from centre is straight on")
	_assert(wide.angle_deg > close.angle_deg, "shot from the corner is angled")
	var hit_close := MatchRules.shot_hit_chance(13, close.distance, close.angle)
	var hit_deep := MatchRules.shot_hit_chance(13, deep.distance, deep.angle)
	var hit_wide := MatchRules.shot_hit_chance(13, wide.distance, wide.angle)
	_assert(hit_close > hit_deep, "closer shots hit more often")
	_assert(hit_close > hit_wide, "straighter shots hit more often")

	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(MatchRules.CENTER_SPOT)
	_assert(not model.can_shoot(st), "cannot shoot from kickoff")
	st.pos = Vector2i(17, 4)
	model.ball.pos = st.pos
	_assert(model.can_shoot(st), "can shoot from the penalty box")
	var acts := model.actions_for(st, MatchRules.AWAY_NET)
	var ids: Array = []
	for act in acts:
		ids.append(act.id)
	_assert("shoot" in ids, "clicking the net offers shoot")
	var preview := model.shot_preview(st)
	_assert(preview.text.contains("hit = ACC/(ACC+"), "preview shows the hit formula")
	_assert(preview.text.contains("goal = hit"), "preview shows the goal product")
	_assert(preview.keeper_in_net, "helix keeper starts in the net")

	model.scripted_shot_outcome = "goal"
	var scored := model.apply_shoot(st.id)
	_assert(scored.goal, "scripted shot is a goal")
	_assert(model.home_score == 1 and model.away_score == 0, "aether leads 1-0")
	_assert(model.current_team == MatchRules.Team.AWAY, "conceding team kicks off")
	_assert(model.player_at(MatchRules.AWAY_KICKOFF).has_ball, "helix striker takes the restart")

	var miss_model := MatchModel.new()
	miss_model.setup_kickoff()
	var shooter := miss_model.player_at(MatchRules.CENTER_SPOT)
	shooter.pos = Vector2i(17, 4)
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
	controller._set_hover(Vector2i(8, 3))
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
	var move_result: Dictionary = controller.handle_cell_clicked(Vector2i(8, 5))
	_assert(move_result.get("action") == "queue", "clicking a highlighted tile queues the default move")
	var model: MatchModel = controller.model
	var striker := model.player_at(MatchRules.CENTER_SPOT)
	_assert(striker != null and striker.has_ball, "queued move left the board unchanged")
	_assert(model.plan_count() == 1, "one aether plan after the click")
	_assert(model.current_team == MatchRules.Team.HOME, "planning stays with aether")
	_assert(controller.selected_id < 0, "selection cleared after the queue")
	_assert(controller._plan_markers().size() == 1, "own plan arrow is visible")
	_assert(controller.pieces[striker.id].planned, "own gold ring is visible")
	_assert(controller.hud._phase.text.contains("AETHER"), "banner names the planning team")
	_assert(controller.hud._turn.text.contains("2 ACTIONS LEFT"), "banner shows remaining actions")
	var enemy_select: Dictionary = controller.handle_cell_clicked(MatchRules.AWAY_NET)
	_assert(not enemy_select.get("ok", false), "cannot select helix during aether planning")
	main.queue_free()

	var pass_main: Node = packed.instantiate()
	root.add_child(pass_main)
	pass_main.animate_moves = false
	pass_main.handle_cell_clicked(MatchRules.CENTER_SPOT)
	pass_main.model.scripted_first_intercept_wins = false
	_assert("pass" in pass_main.hud._command_ids and "swap" in pass_main.hud._command_ids, "action bar lists pass and swap")
	var pass_pick: Dictionary = pass_main.select_command("pass")
	_assert(pass_pick.get("action") == "command", "pass is chosen from the action bar")
	var chosen_pass: Dictionary = pass_main.handle_cell_clicked(Vector2i(8, 3))
	_assert(chosen_pass.get("action") == "queue", "clicking the teammate queues the pass")
	_assert(pass_main.model.player_at(MatchRules.CENTER_SPOT).has_ball, "queued pass has not moved the ball")
	pass_main.queue_free()

	var swap_main: Node = packed.instantiate()
	root.add_child(swap_main)
	swap_main.animate_moves = false
	swap_main.handle_cell_clicked(MatchRules.CENTER_SPOT)
	var swap_pick: Dictionary = swap_main.select_command("swap")
	_assert(swap_pick.get("action") == "command", "swap is chosen from the action bar")
	var chosen_swap: Dictionary = swap_main.handle_cell_clicked(Vector2i(8, 3))
	_assert(chosen_swap.get("action") == "queue", "clicking the teammate queues the swap")
	_assert(swap_main.model.player_at(MatchRules.CENTER_SPOT).number == 9, "queued swap left #9 in place")
	swap_main.queue_free()

	var auto_pass: Node = packed.instantiate()
	root.add_child(auto_pass)
	auto_pass.animate_moves = false
	auto_pass.handle_cell_clicked(MatchRules.CENTER_SPOT)
	auto_pass.model.scripted_first_intercept_wins = false
	auto_pass.select_command("pass")
	var far_pass: Dictionary = auto_pass.handle_cell_clicked(Vector2i(5, 3))
	_assert(far_pass.get("action") == "queue", "non-adjacent in-range teammate queues a pass")
	_assert(auto_pass.model.player_at(MatchRules.CENTER_SPOT).has_ball, "auto-pass is only queued")
	auto_pass.queue_free()

	var ground_pass: Node = packed.instantiate()
	root.add_child(ground_pass)
	ground_pass.animate_moves = false
	ground_pass.handle_cell_clicked(MatchRules.CENTER_SPOT)
	ground_pass.model.scripted_first_intercept_wins = false
	ground_pass.select_command("pass")
	var empty_pass: Dictionary = ground_pass.handle_cell_clicked(Vector2i(6, 4))
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
		dest = Vector2i(8, 5),
		label = "Move",
	}])
	var aether_end: Dictionary = cycle_main.end_planning()
	_assert(aether_end.get("action") == "end_planning", "controller end turn locks aether")
	_assert(cycle.current_team == MatchRules.Team.AWAY, "helix plans after aether ends")
	_assert(cycle_main.hud._phase.text.contains("HELIX"), "banner switches to helix planning")
	_assert(cycle_main.hud._turn.text.contains("3 ACTIONS LEFT"), "helix starts with three actions left")
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
	_assert(cycle.player_at(Vector2i(8, 5)) != null, "queued move applied on resolve")
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
	_assert(last_queue.get("action") == "end_planning", "third aether action ends the turn")
	_assert(auto_model.current_team == MatchRules.Team.AWAY, "helix plans after the third aether action")
	auto_except = {}
	for away_i in range(MatchRules.ACTIONS_PER_SIDE):
		var dummy := _dummy_empty_move(auto_model, MatchRules.Team.AWAY, auto_except)
		_assert(not dummy.is_empty(), "needed a helix dummy move for auto-resolve")
		var mover: PlayerState = dummy.player
		auto_except[mover.id] = true
		auto_main.selected_id = mover.id
		last_queue = auto_main.perform_action({id = "move", dest = dummy.dest, label = "Move"})
	_assert(last_queue.get("action") == "resolve", "third helix action resolves the cycle")
	_assert(auto_model.current_team == MatchRules.Team.HOME, "aether plans the next cycle after auto-resolve")
	auto_main.queue_free()

	var early_main: Node = packed.instantiate()
	root.add_child(early_main)
	early_main.animate_moves = false
	early_main.handle_cell_clicked(MatchRules.CENTER_SPOT)
	early_main.select_command("move")
	var early_choice: Dictionary = early_main.handle_cell_clicked(Vector2i(8, 5))
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
	net_st.pos = Vector2i(2, 4)
	net_main.model.ball.pos = net_st.pos
	net_main._refresh()
	net_main.handle_cell_clicked(Vector2i(2, 4))
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
	var off_mate := off_model.player_at(Vector2i(8, 3))
	off_st.pos = Vector2i(15, 4)
	off_model.ball.pos = off_st.pos
	off_mate.pos = Vector2i(16, 4)
	offside_main._refresh()
	offside_main.handle_cell_clicked(Vector2i(15, 4))
	off_model.scripted_first_intercept_wins = false
	var offside_pick: Dictionary = offside_main.select_command("pass")
	_assert(offside_pick.get("action") == "command", "adjacent offside teammate is a pass target")
	var offside_click: Dictionary = offside_main.handle_cell_clicked(Vector2i(16, 4))
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
	_assert(main.hud._end_turn.text.contains("CONFIRM"), "end turn prompts to confirm a full plan")
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
	_assert(helix_n <= MatchRules.ACTIONS_PER_SIDE, "helix does not queue a fourth action")
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
	shooter.pos = Vector2i(17, 4)
	kick.model.ball.pos = shooter.pos
	kick.model.scripted_shot_outcome = "goal"
	var scored: Dictionary = kick.model.apply_shoot(shooter.id)
	_assert(scored.get("goal", false), "scripted shot is a goal")
	_assert(kick.model.current_team == MatchRules.Team.AWAY, "helix would kick off after conceding")
	kick._begin_vs_ai_cycle()
	_assert(kick.model.current_team == MatchRules.Team.HOME, "vs-ai still lets aether plan after helix kickoff")
	_assert(kick.model.plan_count(MatchRules.Team.AWAY) >= 1, "helix still preplans on its kickoff")
	var aether_kicker: PlayerState = kick.model.player_at(MatchRules.CENTER_SPOT)
	_assert(aether_kicker == null or aether_kicker.team == MatchRules.Team.HOME, "aether kickoff spot is aether or empty after helix restart")
	kick.queue_free()
	paused = false
	await process_frame
