class_name MatchRules
extends RefCounted

## Pure, side-effect-free rules for the 26×13 grid.

enum Team { HOME, AWAY }

const GRID_WIDTH := 26
const GRID_HEIGHT := 13
const MOVE_DISTANCE := 1
const PASS_RANGE := 3
const ACTIONS_PER_SIDE := 3
const PLAYER_ACTION_POINTS := 6
const DEFAULT_ACTION_COST := 1
const MOVE_ORTHO_COST := 2
const MOVE_DIAG_COST := 3
const ACTION_ENERGY_COST := 1
const ENERGY_PER_STAMINA := 10
const ENERGY_EMPTY_FACTOR := 0.5
const INTERCEPT_RADIUS := 1.0
## Off-lane intercept penalty: on the pass line is 1.0; 1 tile off is 1/(1+K).
const INTERCEPT_DIST_K := 1.0
const TILE_SIZE := 72.0
const CENTER_Y := GRID_HEIGHT / 2
const HALFWAY_X := GRID_WIDTH / 2
const CENTER_SPOT := Vector2i(HALFWAY_X - 1, CENTER_Y)
## Helix's kicking cell: 180° of CENTER_SPOT through the pitch centre.
const AWAY_SPOT := Vector2i(HALFWAY_X, CENTER_Y)
## Helix #9 when Aether kicks — one cell off the centre so they cannot contest.
const AWAY_KICKOFF := Vector2i(HALFWAY_X + 1, CENTER_Y + 1)
const HOME_NET := Vector2i(-1, CENTER_Y)
const AWAY_NET := Vector2i(GRID_WIDTH, CENTER_Y)
const SHOT_ACC_BIAS := 1
const SHOT_RANGE_K := 0.35
const SHOT_ANGLE_FLOOR := 0.15
## +3 percentage points of hit chance per leftover AP spent on the shot.
const SHOT_AP_HIT_BONUS := 0.03
const STEP_ACTIONS: Array[String] = ["move", "dribble", "tackle", "challenge", "swap"]
## Rear pass cone: directly back plus this many degrees to each side.
const BACK_PASS_HALF_ANGLE_DEG := 43.0

## 1dSTAT faces are 1..stat. Live stats are already at least 1.

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

## Clockwise 8-dir ring starting at +x (east). 45° per step.
const FACING_RING: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
]

const TEAM_NAME := {
	Team.HOME: "AETHER",
	Team.AWAY: "HELIX",
}


static func is_pitch_tile(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < GRID_WIDTH and pos.y >= 0 and pos.y < GRID_HEIGHT


static func is_goal_tile(pos: Vector2i) -> bool:
	return pos == HOME_NET or pos == AWAY_NET


static func opponent_goal(team: int) -> Vector2i:
	return AWAY_NET if team == Team.HOME else HOME_NET


static func goal_axis(goal: Vector2i) -> Vector2:
	return Vector2(-1, 0) if goal == HOME_NET else Vector2(1, 0)


static func penalty_tiles(goal: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for dir in DIRECTIONS:
		var cell: Vector2i = goal + dir
		if is_pitch_tile(cell):
			tiles.append(cell)
	return tiles


static func is_in_shooting_zone(pos: Vector2i, goal: Vector2i) -> bool:
	if pos == goal or is_goal_tile(pos) or not in_bounds(pos):
		return false
	var box := penalty_tiles(goal)
	if pos in box:
		return true
	for cell in box:
		if is_adjacent(pos, cell):
			return true
	return false


static func shot_geometry(from: Vector2i, goal: Vector2i) -> Dictionary:
	var shot := tile_center(goal) - tile_center(from)
	var distance := shot.length()
	var angle := 0.0
	if distance > 0.0001:
		var dir := shot / distance
		var cos_a := clampf(dir.dot(goal_axis(goal)), -1.0, 1.0)
		angle = acos(cos_a)
	return {distance = distance, angle = angle, angle_deg = rad_to_deg(angle)}


static func shot_range_factor(distance: float) -> float:
	return 1.0 / (1.0 + SHOT_RANGE_K * maxf(0.0, distance - 1.0))


static func shot_angle_factor(angle_rad: float) -> float:
	return maxf(SHOT_ANGLE_FLOOR, cos(angle_rad))


static func shot_ap_bonus(remaining_ap: int) -> float:
	return SHOT_AP_HIT_BONUS * float(maxi(0, remaining_ap))


static func shot_hit_chance(
	accuracy: int,
	distance: float,
	angle_rad: float,
	remaining_ap: int = 0
) -> float:
	var acc_term := float(accuracy) / float(accuracy + SHOT_ACC_BIAS)
	var hit := acc_term * shot_range_factor(distance) * shot_angle_factor(angle_rad)
	hit += shot_ap_bonus(remaining_ap)
	return clampf(hit, 0.05, 0.98)


static func is_diagonal_step(from: Vector2i, to: Vector2i) -> bool:
	var delta := to - from
	return delta.x != 0 and delta.y != 0


static func step_ap_cost(from: Vector2i, to: Vector2i) -> int:
	if from == to:
		return DEFAULT_ACTION_COST
	if is_diagonal_step(from, to):
		return MOVE_DIAG_COST
	return MOVE_ORTHO_COST


## Shoot spends every leftover AP. Steps cost 2 orthogonal / 3 diagonal. Else 1.
static func action_ap_cost(
	action_id: String,
	from: Vector2i,
	to: Vector2i,
	remaining_ap: int
) -> int:
	if action_id == "shoot":
		return maxi(1, remaining_ap)
	if action_id in STEP_ACTIONS:
		return step_ap_cost(from, to)
	return DEFAULT_ACTION_COST


static func in_bounds(pos: Vector2i) -> bool:
	return is_pitch_tile(pos) or is_goal_tile(pos)


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func is_adjacent(from: Vector2i, to: Vector2i) -> bool:
	return chebyshev(from, to) == MOVE_DISTANCE


static func opposite_team(team: int) -> int:
	return Team.AWAY if team == Team.HOME else Team.HOME


## 180° through the pitch centre. Maps Aether's kickoff shape onto Helix's.
static func mirror_cell(pos: Vector2i) -> Vector2i:
	return Vector2i((GRID_WIDTH - 1) - pos.x, (GRID_HEIGHT - 1) - pos.y)


static func kickoff_spot(team: int) -> Vector2i:
	return CENTER_SPOT if team == Team.HOME else AWAY_SPOT


static func kickoff_facing(team: int) -> Vector2i:
	return Vector2i(1, 0) if team == Team.HOME else Vector2i(-1, 0)


static func normalize_facing(facing: Vector2i) -> Vector2i:
	if facing == Vector2i.ZERO:
		return Vector2i.ZERO
	return Vector2i(signi(facing.x), signi(facing.y))


static func step_direction(from: Vector2i, to: Vector2i) -> Vector2i:
	return normalize_facing(to - from)


static func facing_index(facing: Vector2i) -> int:
	var face := normalize_facing(facing)
	for i in FACING_RING.size():
		if FACING_RING[i] == face:
			return i
	return 0


static func rotate_facing(facing: Vector2i, steps: int) -> Vector2i:
	var n := FACING_RING.size()
	var i := facing_index(facing) + steps
	i %= n
	if i < 0:
		i += n
	return FACING_RING[i]


## Facing plus 45° either side: three legal step directions.
static func move_facings(facing: Vector2i) -> Array[Vector2i]:
	return [
		rotate_facing(facing, -1),
		normalize_facing(facing),
		rotate_facing(facing, 1),
	]


## 45° and 90° either side, not current facing: four turn directions (180° takes two turns).
static func turn_facings(facing: Vector2i) -> Array[Vector2i]:
	return [
		rotate_facing(facing, -2),
		rotate_facing(facing, -1),
		rotate_facing(facing, 1),
		rotate_facing(facing, 2),
	]


static func is_move_step(from: Vector2i, to: Vector2i, facing: Vector2i) -> bool:
	var face := normalize_facing(facing)
	if face == Vector2i.ZERO:
		return is_adjacent(from, to)
	return (to - from) in move_facings(face)


static func turn_destinations(from: Vector2i, facing: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var face := normalize_facing(facing)
	if face == Vector2i.ZERO:
		return result
	for dir in turn_facings(face):
		var dest: Vector2i = from + dir
		if in_bounds(dest):
			result.append(dest)
	return result


## The one adjacent square opposite the way the player faces.
static func is_behind_step(from: Vector2i, to: Vector2i, facing: Vector2i) -> bool:
	var face := normalize_facing(facing)
	if face == Vector2i.ZERO:
		return false
	return (to - from) == -face


## Non-adjacent pass into the rear cone (directly back ± 43°). Adjacent cells are allowed.
static func is_back_pass(from: Vector2i, to: Vector2i, facing: Vector2i) -> bool:
	if is_adjacent(from, to):
		return false
	var face := Vector2(normalize_facing(facing))
	var delta := Vector2(to - from)
	if face == Vector2.ZERO or delta == Vector2.ZERO:
		return false
	var angle_deg := absf(rad_to_deg((-face).angle_to(delta)))
	return angle_deg <= BACK_PASS_HALF_ANGLE_DEG + 0.0001


static func team_name(team: int) -> String:
	return TEAM_NAME.get(team, "UNKNOWN")


## Opponent's last third: GRID_WIDTH / 3 columns. Home attacks +x.
static func is_attacking_third(pos: Vector2i, team: int) -> bool:
	var depth := GRID_WIDTH / 3
	if team == Team.HOME:
		return pos.x >= GRID_WIDTH - depth
	return pos.x < depth


## Opponent's half. Halfway sits between x=HALFWAY_X-1 and x=HALFWAY_X. Home attacks +x.
static func is_opponent_half(pos: Vector2i, team: int) -> bool:
	if team == Team.HOME:
		return pos.x >= GRID_WIDTH / 2
	return pos.x < GRID_WIDTH / 2


## Football offside: opponent's half, nearer the goal than the ball, and
## fewer than two opponents as near the goal as this player. Level is onside.
static func is_offside_position(
	team: int,
	pos: Vector2i,
	ball_pos: Vector2i,
	opponent_positions: Array[Vector2i]
) -> bool:
	if not is_opponent_half(pos, team):
		return false
	if team == Team.HOME:
		if pos.x <= ball_pos.x:
			return false
		var covering := 0
		for opp in opponent_positions:
			if opp.x >= pos.x:
				covering += 1
		return covering < 2
	if pos.x >= ball_pos.x:
		return false
	var covering := 0
	for opp in opponent_positions:
		if opp.x <= pos.x:
			covering += 1
	return covering < 2


static func can_use_ball_action(has_ball: bool) -> bool:
	return has_ball


## Cells in `blocked` cannot be entered (teammates). Opponent cells are legal.
## `facing` ZERO keeps all 8 dirs (geometry-only callers). Otherwise the 3-cell move cone.
static func move_destinations(
	from: Vector2i,
	blocked: Dictionary,
	facing: Vector2i = Vector2i.ZERO
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var dirs: Array[Vector2i] = DIRECTIONS
	var face := normalize_facing(facing)
	if face != Vector2i.ZERO:
		dirs = move_facings(face)
	for dir in dirs:
		var dest: Vector2i = from + dir
		if not in_bounds(dest):
			continue
		if blocked.has(dest):
			continue
		result.append(dest)
	return result


static func roll_d_stat(stat: int, rng: RandomNumberGenerator) -> int:
	return rng.randi_range(1, maxi(1, stat))


static func max_energy(stamina: int) -> int:
	return maxi(ENERGY_PER_STAMINA, stamina * ENERGY_PER_STAMINA)


static func energy_factor(energy: int, pool: int) -> float:
	if pool <= 0:
		return ENERGY_EMPTY_FACTOR
	var t := clampf(float(energy) / float(pool), 0.0, 1.0)
	return ENERGY_EMPTY_FACTOR + (1.0 - ENERGY_EMPTY_FACTOR) * t


static func scaled_stat(base: int, energy: int, pool: int) -> int:
	return maxi(1, int(floor(float(base) * energy_factor(energy, pool) + 0.5)))


## Each side rolls 1dSTAT (1..stat). Higher roll wins. Ties go to the team with the ball.
static func resolve_contest(
	attacker_stat: int,
	defender_stat: int,
	rng: RandomNumberGenerator,
	tie_goes_to_attacker: bool = false
) -> Dictionary:
	var attacker_dice := roll_d_stat(attacker_stat, rng)
	var defender_dice := roll_d_stat(defender_stat, rng)
	var attacker_won := (
		attacker_dice > defender_dice
		or (attacker_dice == defender_dice and tie_goes_to_attacker)
	)
	return {
		attacker_stat = attacker_stat,
		defender_stat = defender_stat,
		attacker_dice = attacker_dice,
		defender_dice = defender_dice,
		attacker_total = attacker_dice,
		defender_total = defender_dice,
		attacker_won = attacker_won,
	}


## Tests force a winner; dice are filled in so the log still reads as 1dSTAT.
static func apply_scripted_winner(roll: Dictionary, attacker_won: bool) -> void:
	roll.attacker_won = attacker_won
	if attacker_won:
		roll.attacker_dice = maxi(int(roll.get("attacker_stat", 1)), 2)
		roll.defender_dice = 1
	else:
		roll.attacker_dice = 1
		roll.defender_dice = maxi(int(roll.get("defender_stat", 1)), 2)
	roll.attacker_total = roll.attacker_dice
	roll.defender_total = roll.defender_dice


## If one contestant has the ball they win ties. Else the side in possession.
## Same-team clashes and a loose ball leave the first claimer / occupant.
static func attacker_wins_ties(
	attacker: PlayerState,
	defender: PlayerState,
	possession_team: int = -1
) -> bool:
	if attacker == null:
		return false
	if attacker.has_ball:
		return true
	if defender != null and defender.has_ball:
		return false
	if defender != null and attacker.team == defender.team:
		return true
	if possession_team < 0:
		return false
	return attacker.team == possession_team


## Chance the attacker wins a 1dSTAT vs 1dSTAT contest.
static func contest_win_chance(
	attacker_stat: int,
	defender_stat: int,
	tie_goes_to_attacker: bool = false
) -> float:
	var atk := maxi(1, attacker_stat)
	var deff := maxi(1, defender_stat)
	var wins := 0
	var ties := 0
	for roll in range(1, atk + 1):
		wins += mini(roll - 1, deff)
		if roll <= deff:
			ties += 1
	if tie_goes_to_attacker:
		wins += ties
	return float(wins) / float(atk * deff)


static func contest_preview(
	mover: PlayerState,
	occupant: PlayerState,
	mover_on_ball = null,
	possession_team: int = -1
) -> Dictionary:
	var action := "challenge"
	var verb := "square fight"
	var atk_name := "CTR"
	var def_name := "CTR"
	var atk := mover.live_control()
	var deff := occupant.live_control()
	var on_ball := mover.has_ball if mover_on_ball == null else bool(mover_on_ball)
	if on_ball:
		action = "dribble"
		verb = "dribble"
		atk_name = "CTR"
		def_name = "DEF"
		atk = mover.live_control()
		deff = occupant.live_defense()
	elif occupant.has_ball:
		action = "tackle"
		verb = "tackle"
		atk_name = "DEF"
		def_name = "CTR"
		atk = mover.live_defense()
		deff = occupant.live_control()
	var ties_to_atk := false
	if on_ball:
		ties_to_atk = true
	elif occupant.has_ball:
		ties_to_atk = false
	else:
		ties_to_atk = attacker_wins_ties(mover, occupant, possession_team)
	var chance := contest_win_chance(atk, deff, ties_to_atk)
	var pct := int(round(chance * 100.0))
	var text := "%s %s %d %s vs %d %s = %d%% success" % [
		verb, occupant.label(), atk, atk_name, deff, def_name, pct
	]
	return {
		action = action,
		verb = verb,
		attacker_stat_name = atk_name,
		defender_stat_name = def_name,
		attacker_stat = atk,
		defender_stat = deff,
		chance = chance,
		percent = pct,
		text = text,
	}


static func tile_center(cell: Vector2i) -> Vector2:
	return Vector2(cell)


static func nearest_tile(point: Vector2) -> Vector2i:
	return Vector2i(roundi(point.x), roundi(point.y))


## Closest point on segment a→b to p. t is 0 at a, 1 at b.
static func closest_on_segment(a: Vector2, b: Vector2, p: Vector2) -> Dictionary:
	var ab := b - a
	var length_sq := ab.length_squared()
	var t := 0.0
	if length_sq > 0.000001:
		t = clampf((p - a).dot(ab) / length_sq, 0.0, 1.0)
	var closest := a + ab * t
	return {t = t, closest = closest, dist = p.distance_to(closest)}


## True when the pass segment comes within radius of p, not counting the start point.
static func segment_intersects_circle(a: Vector2, b: Vector2, p: Vector2, radius: float) -> Dictionary:
	var hit := closest_on_segment(a, b, p)
	var along_lane: bool = hit.t > 0.0001
	hit.hits = along_lane and hit.dist <= radius + 0.0001
	return hit


## Fraction of intercept chance kept at this distance from the pass segment.
static func intercept_reach_factor(dist: float) -> float:
	return 1.0 / (1.0 + INTERCEPT_DIST_K * maxf(0.0, dist))


## Chance the passer beats this interceptor, including the off-lane reach penalty.
static func intercept_through_chance(accuracy: int, defense: int, dist: float) -> float:
	var through := contest_win_chance(accuracy, defense, true)
	var intercept := (1.0 - through) * intercept_reach_factor(dist)
	return 1.0 - intercept
