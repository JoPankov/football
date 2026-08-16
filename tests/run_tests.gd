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
	await _test_controller_click_flow()
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
	_assert(MatchRules.in_bounds(Vector2i(11, 6)), "far corner in bounds")
	_assert(not MatchRules.in_bounds(Vector2i(-1, 0)), "negative x out")
	_assert(not MatchRules.in_bounds(Vector2i(12, 0)), "x=12 out")
	_assert(not MatchRules.in_bounds(Vector2i(0, 7)), "y=7 out")


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
	_assert(MatchRules.is_attacking_third(Vector2i(8, 0), MatchRules.Team.HOME), "home last third starts at x=8")
	_assert(not MatchRules.is_attacking_third(Vector2i(7, 0), MatchRules.Team.HOME), "x=7 is midfield for home")
	_assert(MatchRules.is_attacking_third(Vector2i(3, 0), MatchRules.Team.AWAY), "away last third ends at x=3")
	_assert(MatchRules.can_use_ball_action(true), "carrier may use ball actions later")
	_assert(not MatchRules.can_use_ball_action(false), "non-carrier cannot use ball actions")


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
	var home_st := model.player_at(Vector2i(5, 3))
	_assert(home_st != null and home_st.role == "ST", "home #9 ST takes kickoff")
	_assert(home_st.has_ball, "home starts in possession")
	_assert(not model.ball.is_loose(), "ball is not loose at kickoff")
	_assert(model.ball.pos == home_st.pos, "ball starts on the kickoff taker")


func _test_turn_and_selection() -> void:
	print("-- turns")
	var model := MatchModel.new()
	model.setup_kickoff()
	var home := model.player_at(Vector2i(5, 3))
	var away := model.player_at(Vector2i(6, 4))
	_assert(model.can_select(home), "home can select own player")
	_assert(not model.can_select(away), "home cannot select helix")
	var illegal := model.apply_move(away.id, Vector2i(6, 3))
	_assert(not illegal.ok, "away cannot move on home turn")
	var ok := model.apply_move(home.id, Vector2i(5, 4))
	_assert(ok.ok, "home ST can move with the ball")
	_assert(home.has_ball, "kickoff taker still has the ball after moving")
	_assert(model.current_team == MatchRules.Team.AWAY, "turn passed to away")
	_assert(model.can_select(away), "away can select after the turn")


func _test_possession() -> void:
	print("-- possession")
	var model := MatchModel.new()
	model.setup_kickoff()
	var striker := model.player_at(Vector2i(5, 3))
	_assert(striker.has_ball, "striker starts as carrier")
	_assert(model.ball.carrier_id == striker.id, "ball records the carrier")
	var result := model.apply_move(striker.id, Vector2i(5, 4))
	_assert(result.ok and not result.gained_possession, "moving with the ball is a normal carry")
	_assert(striker.has_ball, "striker kept possession")
	_assert(model.ball.pos == striker.pos, "ball cell matches carrier")


func _test_ball_travels_with_carrier() -> void:
	print("-- ball travel")
	var model := MatchModel.new()
	model.setup_kickoff()
	var striker := model.player_at(Vector2i(5, 3))
	model.apply_move(striker.id, Vector2i(5, 4))
	# Skip away turn by moving a dummy adjacent away player that does not contest.
	var away := model.player_at(Vector2i(6, 4))
	model.apply_move(away.id, Vector2i(6, 5))
	var carry := model.apply_move(striker.id, Vector2i(4, 3))
	_assert(carry.ok, "carrier can carry 1 tile")
	_assert(not carry.gained_possession, "already had the ball")
	_assert(model.ball.pos == Vector2i(4, 3), "ball followed the carrier")
	_assert(striker.has_ball, "possession kept")


func _test_cannot_stack() -> void:
	print("-- stacking")
	var model := MatchModel.new()
	model.setup_kickoff()
	var mid := model.player_at(Vector2i(4, 4))
	var dest := Vector2i(5, 3) # occupied by home ST
	var result := model.apply_move(mid.id, dest)
	_assert(not result.ok, "cannot step onto a teammate")
	_assert(mid.pos == Vector2i(4, 4), "mover stayed put")


func _test_attributes() -> void:
	print("-- attributes")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(Vector2i(5, 3))
	var gk := model.player_at(Vector2i(0, 3))
	var cm := model.player_at(Vector2i(4, 2))
	_assert(st.accuracy == 13 and st.control == 9, "striker is accuracy/control leaning")
	_assert(gk.defense == 13 and gk.control == 11, "keeper is defense/control leaning")
	_assert(cm.passing == 12, "central mid is passing leaning")
	var away := model.player_at(Vector2i(6, 4))
	_assert(away.pos in model.valid_moves(st), "opponent tile is a legal contest dest")
	_assert(away.pos in model.contest_moves(st), "opponent tile is listed as a contest")


func _test_dribble_win() -> void:
	print("-- dribble win")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(Vector2i(5, 3))
	var away := model.player_at(Vector2i(6, 4))
	model.scripted_attacker_wins = true
	var result := model.apply_move(st.id, Vector2i(6, 4))
	_assert(result.action == "dribble", "on-ball step onto opponent is a dribble")
	_assert(result.attacker_stat_name == "CTR" and result.defender_stat_name == "DEF", "dribble is CTR vs DEF")
	_assert(result.contest_won, "scripted dribble succeeded")
	_assert(st.pos == Vector2i(6, 4), "dribbler took the square")
	_assert(away.pos == Vector2i(5, 3), "beaten defender was shoved back")
	_assert(st.has_ball and not away.has_ball, "dribbler kept the ball")
	_assert(model.ball.pos == st.pos, "ball followed the successful dribble")


func _test_dribble_loss() -> void:
	print("-- dribble loss")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(Vector2i(5, 3))
	var away := model.player_at(Vector2i(6, 4))
	model.scripted_attacker_wins = false
	var result := model.apply_move(st.id, Vector2i(6, 4))
	_assert(result.action == "dribble", "failed attempt is still a dribble")
	_assert(not result.contest_won, "scripted dribble failed")
	_assert(st.pos == Vector2i(5, 3), "dribbler stayed put")
	_assert(away.pos == Vector2i(6, 4), "defender held the square")
	_assert(away.has_ball and not st.has_ball, "defender won the ball")
	_assert(result.lost_possession, "result reports lost possession")


func _test_square_fight() -> void:
	print("-- square fight")
	var model := MatchModel.new()
	model.setup_kickoff()
	var home := model.player_at(Vector2i(5, 2))
	var away := model.player_at(Vector2i(6, 2))
	_assert(not home.has_ball and not away.has_ball, "off-ball challenge starts without possession")
	model.scripted_attacker_wins = true
	var win := model.apply_move(home.id, Vector2i(6, 2))
	_assert(win.action == "challenge", "off-ball step onto opponent is a square fight")
	_assert(win.attacker_stat_name == "CTR" and win.defender_stat_name == "CTR", "square fight is CTR vs CTR")
	_assert(home.pos == Vector2i(6, 2), "winner took the square")
	_assert(away.pos == Vector2i(5, 2), "loser was shoved to the origin")
	_assert(not home.has_ball and not away.has_ball, "no ball changed hands")

	model.scripted_attacker_wins = false
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
	var st := model.player_at(Vector2i(5, 3))
	var decoy := model.player_at(Vector2i(4, 0))
	model.apply_move(decoy.id, Vector2i(5, 0))
	var away := model.player_at(Vector2i(6, 4))
	model.scripted_attacker_wins = true
	var result := model.apply_move(away.id, Vector2i(5, 3))
	_assert(result.get("action") == "tackle", "off-ball step onto the carrier is a tackle")
	_assert(result.get("attacker_stat_name") == "DEF" and result.get("defender_stat_name") == "CTR", "tackle is DEF vs CTR")
	_assert(result.get("attacker_label") == away.label(), "log names the tackler")
	_assert(result.get("defender_label") == st.label(), "log names the carrier")
	_assert(result.get("gained_possession"), "winner of the tackle took the ball")
	_assert(away.has_ball and not st.has_ball, "challenger is the new carrier")
	_assert(away.pos == Vector2i(5, 3) and st.pos == Vector2i(6, 4), "players swapped")


func _test_contest_preview() -> void:
	print("-- contest preview")
	_assert(MatchRules.PASS_RANGE == 3, "pass range is 3 tiles")
	var even := MatchRules.contest_win_chance(9, 9)
	_assert(absi(even - 575.0 / 1296.0) < 0.0001, "even contest is 575/1296 (ties to occupant)")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(Vector2i(5, 3))
	var away := model.player_at(Vector2i(6, 4))
	var preview := MatchRules.contest_preview(st, away)
	_assert(preview.action == "dribble", "preview of carrier vs opponent is a dribble")
	_assert(preview.text.contains(away.label()), "hint names the opponent")
	_assert(preview.text.contains("%d CTR" % st.control), "hint shows mover CTR")
	_assert(preview.text.contains("%d DEF" % away.defense), "hint shows occupant DEF")
	_assert(preview.text.contains("%d%% success" % preview.percent), "hint shows success percent")
	var decoy := model.player_at(Vector2i(4, 0))
	model.apply_move(decoy.id, Vector2i(5, 0))
	var tackle := MatchRules.contest_preview(away, st)
	_assert(tackle.action == "tackle", "preview of off-ball vs carrier is a tackle")
	_assert(tackle.text.begins_with("tackle "), "tackle hint starts with tackle")
	_assert(tackle.text.contains("%d DEF" % away.defense), "tackle hint uses mover DEF")
	_assert(tackle.text.contains("%d CTR" % st.control), "tackle hint uses carrier CTR")


func _test_pass() -> void:
	print("-- pass")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(Vector2i(5, 3))
	var near := model.player_at(Vector2i(5, 2))
	var gk := model.player_at(Vector2i(0, 3))
	var away := model.player_at(Vector2i(6, 4))
	_assert(model.can_pass_to(st, near), "can pass to a teammate within 3")
	_assert(MatchRules.chebyshev(st.pos, gk.pos) == 5, "keeper is 5 tiles away")
	_assert(not model.can_pass_to(st, gk), "cannot pass beyond 3 tiles")
	_assert(not model.can_pass_to(st, away), "cannot pass to an opponent")
	_assert(not model.can_pass_to(near, st), "non-carrier cannot pass")
	model.scripted_first_intercept_wins = false
	var result := model.apply_pass(st.id, near.id)
	_assert(result.ok and result.action == "pass", "pass succeeds")
	_assert(near.has_ball and not st.has_ball, "receiver has the ball")
	_assert(model.ball.pos == near.pos, "ball moved to the receiver")
	_assert(st.pos == Vector2i(5, 3) and near.pos == Vector2i(5, 2), "neither player moved")
	_assert(model.current_team == MatchRules.Team.AWAY, "pass ends the turn")
	var illegal := model.apply_pass(near.id, st.id)
	_assert(not illegal.ok, "cannot pass on the opponent's turn")

	var open := MatchModel.new()
	open.setup_kickoff()
	var kicker := open.player_at(Vector2i(5, 3))
	_assert(open.can_pass_to_cell(kicker, Vector2i(5, 4)), "can pass to an empty adjacent square")
	_assert(open.can_pass_to_cell(kicker, Vector2i(3, 3)), "can pass to an empty square 2 tiles away")
	_assert(not open.can_pass_to_cell(kicker, Vector2i(1, 3)), "cannot pass 4 tiles to empty")
	var empty_actions := open.actions_for(kicker, Vector2i(5, 4))
	_assert(empty_actions.size() == 2, "adjacent empty square is move or pass")
	_assert(empty_actions[0].id == "move" and empty_actions[1].id == "pass", "move and pass are both offered")
	var through := open.actions_for(kicker, Vector2i(3, 3))
	_assert(through.size() == 1 and through[0].id == "pass", "empty square 2 tiles away is pass only")
	open.scripted_first_intercept_wins = false
	var laid := open.apply_pass_to(kicker.id, Vector2i(3, 3))
	_assert(laid.ok and laid.action == "pass", "pass to empty square succeeds")
	_assert(not kicker.has_ball, "passer released the ball")
	_assert(open.ball.is_loose() and open.ball.pos == Vector2i(3, 3), "ball sits loose on the target square")
	_assert(kicker.pos == Vector2i(5, 3), "passer stayed put")


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
	var st := model.player_at(Vector2i(5, 3))
	var threats := model.interceptors_for_pass(st, Vector2i(8, 3))
	_assert(threats.size() >= 2, "a lane through midfield has interceptors")
	var preview := model.pass_preview(st, Vector2i(8, 3))
	_assert(preview.text.contains("PAS vs"), "preview lists PAS vs DEF")
	_assert(preview.text.contains("Pass success:"), "preview shows total pass success")
	_assert(preview.total < 1.0, "at least one interceptor lowers pass success")

	model.scripted_first_intercept_wins = true
	var from_tile: Vector2i = threats[0].player.pos
	var stolen := model.apply_pass_to(st.id, Vector2i(8, 3))
	_assert(stolen.get("intercepted", false), "scripted interceptor takes the pass")
	var thief := model.player_by_id(stolen.interceptor_id)
	_assert(thief != null and thief.has_ball and thief.team == MatchRules.Team.AWAY, "an opponent now has the ball")
	_assert(not st.has_ball, "passer lost the ball")
	_assert(thief.pos == Vector2i(6, 3), "interceptor moved onto the pass lane")
	_assert(thief.pos != from_tile, "interceptor left their starting tile")
	_assert(model.ball.pos == thief.pos, "ball is on the intercept tile")
	_assert(model.player_at(from_tile) == null, "the interceptor's old tile is empty")

	var clean := MatchModel.new()
	clean.setup_kickoff()
	var kicker := clean.player_at(Vector2i(5, 3))
	clean.scripted_first_intercept_wins = false
	var done := clean.apply_pass_to(kicker.id, Vector2i(8, 3))
	_assert(not done.get("intercepted", false), "beating every interceptor completes the pass")
	_assert(clean.ball.is_loose() and clean.ball.pos == Vector2i(8, 3), "completed pass still lands on the square")


func _test_swap_and_choice() -> void:
	print("-- swap and choice")
	var model := MatchModel.new()
	model.setup_kickoff()
	var st := model.player_at(Vector2i(5, 3))
	var near := model.player_at(Vector2i(5, 2))
	var wing := model.player_at(Vector2i(4, 0))
	var away := model.player_at(Vector2i(6, 4))
	var adjacent := model.actions_for(st, near.pos)
	_assert(adjacent.size() == 2, "adjacent teammate offers two actions")
	_assert(adjacent[0].id == "pass" and adjacent[1].id == "swap", "pass and swap are both offered")
	var far := model.actions_for(st, wing.pos)
	_assert(far.size() == 1 and far[0].id == "pass", "3-tile teammate is pass only")
	_assert(not model.can_swap(st, wing), "cannot swap from 3 tiles away")
	_assert(not model.can_swap(st, away), "cannot swap with an opponent")
	var swapped := model.apply_swap(st.id, near.id)
	_assert(swapped.ok and swapped.action == "swap", "swap succeeds")
	_assert(st.pos == Vector2i(5, 2) and near.pos == Vector2i(5, 3), "players swapped places")
	_assert(st.has_ball and not near.has_ball, "carrier kept the ball")
	_assert(model.ball.pos == st.pos, "ball followed the carrier")
	_assert(model.current_team == MatchRules.Team.AWAY, "swap ends the turn")


func _test_controller_click_flow() -> void:
	print("-- controller")
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	var controller: Node = main
	controller.animate_moves = false
	var select_result: Dictionary = controller.handle_cell_clicked(Vector2i(5, 3))
	_assert(select_result.get("action") == "select", "clicking own player selects")
	_assert(controller.selected_id >= 0, "selection stored")
	var move_choice: Dictionary = controller.handle_cell_clicked(Vector2i(5, 4))
	_assert(move_choice.get("action") == "choose", "adjacent empty tile offers move or pass")
	var move_result: Dictionary = controller.choose_action("move")
	_assert(move_result.get("ok", false), "selected carrier can move to an empty tile")
	var model: MatchModel = controller.model
	var striker := model.player_at(Vector2i(5, 4))
	_assert(striker != null and striker.has_ball, "click-move kept kickoff possession")
	_assert(model.current_team == MatchRules.Team.AWAY, "click-move ended the turn")
	_assert(controller.selected_id < 0, "selection cleared after the action")
	var enemy_select: Dictionary = controller.handle_cell_clicked(Vector2i(0, 3))
	_assert(not enemy_select.get("ok", false), "away turn cannot select aether")
	main.queue_free()

	var pass_main: Node = packed.instantiate()
	root.add_child(pass_main)
	pass_main.animate_moves = false
	pass_main.handle_cell_clicked(Vector2i(5, 3))
	pass_main.model.scripted_first_intercept_wins = false
	var choice_click: Dictionary = pass_main.handle_cell_clicked(Vector2i(5, 2))
	_assert(choice_click.get("action") == "choose", "adjacent teammate opens a pass/swap choice")
	var option_ids: Array = []
	for option in choice_click.get("options", []):
		option_ids.append(option.get("id", ""))
	_assert("pass" in option_ids and "swap" in option_ids, "chooser lists pass and swap")
	var chosen_pass: Dictionary = pass_main.choose_action("pass")
	_assert(chosen_pass.get("action") == "pass", "choosing pass completes the pass")
	_assert(pass_main.model.player_at(Vector2i(5, 2)).has_ball, "chosen pass delivered the ball")
	pass_main.queue_free()

	var swap_main: Node = packed.instantiate()
	root.add_child(swap_main)
	swap_main.animate_moves = false
	swap_main.handle_cell_clicked(Vector2i(5, 3))
	swap_main.handle_cell_clicked(Vector2i(5, 2))
	var chosen_swap: Dictionary = swap_main.choose_action("swap")
	_assert(chosen_swap.get("action") == "swap", "choosing swap swaps places")
	_assert(swap_main.model.player_at(Vector2i(5, 2)).has_ball, "carrier kept the ball after swap")
	_assert(swap_main.model.player_at(Vector2i(5, 2)).number == 9, "Aether #9 moved onto the teammate tile")
	swap_main.queue_free()

	var auto_pass: Node = packed.instantiate()
	root.add_child(auto_pass)
	auto_pass.animate_moves = false
	auto_pass.handle_cell_clicked(Vector2i(5, 3))
	auto_pass.model.scripted_first_intercept_wins = false
	var far_pass: Dictionary = auto_pass.handle_cell_clicked(Vector2i(4, 0))
	_assert(far_pass.get("action") == "pass", "non-adjacent in-range teammate still auto-passes")
	_assert(auto_pass.model.player_at(Vector2i(4, 0)).has_ball, "auto-pass delivered the ball")
	auto_pass.queue_free()

	var ground_pass: Node = packed.instantiate()
	root.add_child(ground_pass)
	ground_pass.animate_moves = false
	ground_pass.handle_cell_clicked(Vector2i(5, 3))
	ground_pass.model.scripted_first_intercept_wins = false
	var empty_pass: Dictionary = ground_pass.handle_cell_clicked(Vector2i(3, 3))
	_assert(empty_pass.get("action") == "pass", "clicking a distant empty square passes to it")
	_assert(ground_pass.model.ball.is_loose() and ground_pass.model.ball.pos == Vector2i(3, 3), "ground pass left the ball loose")
	ground_pass.queue_free()
	await process_frame
