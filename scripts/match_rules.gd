class_name MatchRules
extends RefCounted

## Pure, side-effect-free rules for the 26×17 grid.

enum Team { HOME, AWAY }

const GRID_WIDTH := 26
const GRID_HEIGHT := 17
const MOVE_DISTANCE := 1
## Euclidean pass radius in tile lengths, centre to centre. Orthogonal 5 is in; (5,1) is out.
const PASS_RANGE := 5
const ACTIONS_PER_SIDE := 3
const PLAYER_ACTION_POINTS := 6
const DEFAULT_ACTION_COST := 1
const MOVE_ORTHO_COST := 2
const MOVE_DIAG_COST := 3
## Sprint is two tiles straight ahead, 2 AP, 3 energy. Facing cone does not apply.
const SPRINT_DISTANCE := 2
const SPRINT_AP_COST := 2
const SPRINT_ENERGY_COST := 3
## One AP turns up to this many 45° ring steps (90°). 135° and 180° cost 2 AP.
const TURN_STEPS_PER_AP := 2
const ACTION_ENERGY_COST := 1
const ENERGY_PER_STAMINA := 10
const ENERGY_EMPTY_FACTOR := 0.5
## Circle around each opponent, in tile lengths, that must touch the pass/shot segment.
const INTERCEPT_RADIUS := 0.7
## Off-lane intercept penalty: on the pass line is 1.0; 1 tile off is 1/(1+K).
const INTERCEPT_DIST_K := 1.0
const TILE_SIZE := 72.0
const CENTER_Y := GRID_HEIGHT / 2
const HALFWAY_X := GRID_WIDTH / 2
const CENTER_SPOT := Vector2i(HALFWAY_X - 1, CENTER_Y)
## Helix's kicking cell: 180° of CENTER_SPOT through the pitch centre.
const AWAY_SPOT := Vector2i(HALFWAY_X, CENTER_Y)
## Helix #9 when Aether kicks — own half, just outside the centre circle.
const AWAY_KICKOFF := Vector2i(HALFWAY_X + 1, CENTER_Y + 3)
## Drawn / legal centre circle. 9.15 m ≈ 2.5 tiles; hits cell borders around halfway.
const CENTRE_CIRCLE_R := 2.5
const HOME_NET := Vector2i(-1, CENTER_Y)
const AWAY_NET := Vector2i(GRID_WIDTH, CENTER_Y)
## FIFA pitch in metres. The 26×17 grid maps onto this, so a cell is not 1 m.
const PITCH_LENGTH_M := 105.0
const PITCH_WIDTH_M := 68.0
const TILE_M_X := PITCH_LENGTH_M / GRID_WIDTH
const TILE_M_Y := PITCH_WIDTH_M / GRID_HEIGHT
## FIFA goal mouth in metres. Convert tile deltas to metres before using these.
const SHOT_GOAL_W := 7.32
const SHOT_GOAL_H := 2.44
const SHOT_D_MIN := 1.0
const SHOT_COS_FLOOR := 0.15
const SHOT_SIGMA_MAX_DEG := 12.0
const SHOT_SIGMA_MIN_DEG := 1.0
const SHOT_SIGMA_POWER := 1.2
## +5% of the accuracy stat per leftover AP spent on the shot.
const SHOT_AP_ACC_BONUS := 0.05
## Minimum unclamped hit chance to offer a shot. The roll is also clamped here.
const SHOT_MIN_HIT := 0.05
const SHOT_MAX_HIT := 0.98
const STEP_ACTIONS: Array[String] = ["move", "dribble", "tackle", "challenge", "swap"]
## Rear pass cone: directly back plus this many degrees to each side.
const BACK_PASS_HALF_ANGLE_DEG := 43.0
## Tackle success penalty by approach angle vs the carrier's facing.
## Front is 0°; back is 180°. Values are percentage points on the dice chance.
const TACKLE_FRONT_PENALTY := 0.0
const TACKLE_45_PENALTY := -0.15
const TACKLE_SIDE_PENALTY := -0.30
const TACKLE_135_PENALTY := -0.50
const TACKLE_BACK_PENALTY := -0.85

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


## True when a shot from `from` at `goal` has at least SHOT_MIN_HIT to hit the net.
static func can_attempt_shot(
	from: Vector2i,
	goal: Vector2i,
	accuracy: int,
	remaining_ap: int = 0
) -> bool:
	if from == goal or is_goal_tile(from) or not in_bounds(from):
		return false
	var geo := shot_geometry(from, goal)
	return (
		shot_raw_hit_chance(accuracy, geo.distance_m, geo.angle, remaining_ap)
		>= SHOT_MIN_HIT
	)


## Cell delta in metres. Pitch length/width scales differ, so a cell is a rectangle.
static func cell_delta_metres(from: Vector2i, to: Vector2i) -> Vector2:
	var delta := tile_center(to) - tile_center(from)
	return Vector2(delta.x * TILE_M_X, delta.y * TILE_M_Y)


static func shot_geometry(from: Vector2i, goal: Vector2i) -> Dictionary:
	var to_goal := cell_delta_metres(from, goal)
	var raw_m := to_goal.length()
	var d := maxf(raw_m, SHOT_D_MIN)
	var forward := goal_axis(goal)
	if raw_m > 0.0001:
		forward = to_goal / raw_m
	var cos_a := clampf(forward.dot(goal_axis(goal)), -1.0, 1.0)
	var cos_th := maxf(SHOT_COS_FLOOR, cos_a)
	var angle := acos(cos_a)
	var tiles := (tile_center(goal) - tile_center(from)).length()
	return {
		distance = tiles,
		distance_m = raw_m,
		shot_d = d,
		angle = angle,
		angle_deg = rad_to_deg(angle),
		cos_th = cos_th,
		theta_w = (SHOT_GOAL_W * cos_th) / d,
		theta_h = SHOT_GOAL_H / d,
	}


## Abramowitz & Stegun 7.1.26. One approximation, used everywhere.
static func erf_approx(x: float) -> float:
	var ax := absf(x)
	var t := 1.0 / (1.0 + 0.3275911 * ax)
	var y := (
		1.0
		- (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592)
		* t
		* exp(-ax * ax)
	)
	return signf(x) * y


static func shot_sigma_deg(accuracy: int) -> float:
	var t := clampf(float(accuracy), 1.0, 100.0) / 100.0
	return lerpf(SHOT_SIGMA_MAX_DEG, SHOT_SIGMA_MIN_DEG, pow(t, SHOT_SIGMA_POWER))


static func shot_sigma_rad(accuracy: int) -> float:
	return maxf(deg_to_rad(shot_sigma_deg(accuracy)), 1e-4)


static func shot_ap_bonus(remaining_ap: int) -> float:
	return SHOT_AP_ACC_BONUS * float(maxi(0, remaining_ap))


## Live ACC times leftover-AP aiming bonus. Used for hit spray, intercepts, and saves.
static func shot_accuracy(accuracy: int, remaining_ap: int = 0) -> int:
	var factor := 1.0 + shot_ap_bonus(remaining_ap)
	return maxi(1, int(floor(float(maxi(0, accuracy)) * factor + 0.5)))


## Unclamped P(Gaussian miss lands in the goal rectangle). `distance` is metres. No leftover AP.
static func shot_base_hit_chance(distance: float, angle_rad: float, accuracy: int) -> float:
	var d := maxf(distance, SHOT_D_MIN)
	var cos_th := maxf(SHOT_COS_FLOOR, clampf(cos(angle_rad), -1.0, 1.0))
	var theta_w := (SHOT_GOAL_W * cos_th) / d
	var theta_h := SHOT_GOAL_H / d
	var s := shot_sigma_rad(accuracy) * sqrt(2.0)
	var half_w := 0.5 * theta_w
	var half_h := 0.5 * theta_h
	return erf_approx(half_w / s) * erf_approx(half_h / s)


## `distance` is metres, same as `shot_base_hit_chance`. Leftover AP raises ACC, not hit.
static func shot_raw_hit_chance(
	accuracy: int,
	distance: float,
	angle_rad: float,
	remaining_ap: int = 0
) -> float:
	return shot_base_hit_chance(distance, angle_rad, shot_accuracy(accuracy, remaining_ap))


## `distance` is metres, same as `shot_base_hit_chance`.
static func shot_hit_chance(
	accuracy: int,
	distance: float,
	angle_rad: float,
	remaining_ap: int = 0
) -> float:
	return clampf(
		shot_raw_hit_chance(accuracy, distance, angle_rad, remaining_ap),
		SHOT_MIN_HIT,
		SHOT_MAX_HIT
	)


static func is_diagonal_step(from: Vector2i, to: Vector2i) -> bool:
	var delta := to - from
	return delta.x != 0 and delta.y != 0


static func step_ap_cost(from: Vector2i, to: Vector2i) -> int:
	if from == to:
		return DEFAULT_ACTION_COST
	if is_diagonal_step(from, to):
		return MOVE_DIAG_COST
	return MOVE_ORTHO_COST


## Shortest 45° steps between two facings, 0 through 4.
static func facing_steps(from_facing: Vector2i, to_facing: Vector2i) -> int:
	var a := facing_index(from_facing)
	var b := facing_index(to_facing)
	var n := FACING_RING.size()
	var delta := absi(a - b)
	return mini(delta, n - delta)


## 1 AP for 45°/90°, 2 AP for 135°/180°. Current facing and zero vectors are illegal.
static func turn_ap_cost(from_facing: Vector2i, to_facing: Vector2i) -> int:
	var wanted := normalize_facing(to_facing)
	if wanted == Vector2i.ZERO:
		return PLAYER_ACTION_POINTS + 1
	var steps := facing_steps(from_facing, wanted)
	if steps <= 0:
		return PLAYER_ACTION_POINTS + 1
	return ceili(float(steps) / float(TURN_STEPS_PER_AP))


## Shoot spends every leftover AP. Done costs 0. Steps cost 2 orthogonal / 3 diagonal.
## Sprint costs 2 AP. Turn costs 1 AP up to 90°, 2 AP for 135°/180°. Else 1.
static func action_ap_cost(
	action_id: String,
	from: Vector2i,
	to: Vector2i,
	remaining_ap: int,
	facing: Vector2i = Vector2i.ZERO
) -> int:
	if action_id == "done":
		return 0
	if action_id == "shoot":
		return maxi(1, remaining_ap)
	if action_id == "sprint":
		return SPRINT_AP_COST
	if action_id == "turn":
		return turn_ap_cost(facing, step_direction(from, to))
	if action_id in STEP_ACTIONS:
		return step_ap_cost(from, to)
	return DEFAULT_ACTION_COST


static func action_energy_cost(action_id: String) -> int:
	if action_id == "done":
		return 0
	if action_id == "sprint":
		return SPRINT_ENERGY_COST
	return ACTION_ENERGY_COST


static func in_bounds(pos: Vector2i) -> bool:
	return is_pitch_tile(pos) or is_goal_tile(pos)


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Euclidean distance between cell centres, in tile lengths.
static func tile_distance(a: Vector2i, b: Vector2i) -> float:
	return tile_center(a).distance_to(tile_center(b))


static func in_pass_range(from: Vector2i, to: Vector2i) -> bool:
	return tile_distance(from, to) <= float(PASS_RANGE) + 0.0001


static func is_adjacent(from: Vector2i, to: Vector2i) -> bool:
	return chebyshev(from, to) == MOVE_DISTANCE


static func opposite_team(team: int) -> int:
	return Team.AWAY if team == Team.HOME else Team.HOME


## 180° through the pitch centre. Maps Aether's kickoff shape onto Helix's.
static func mirror_cell(pos: Vector2i) -> Vector2i:
	return Vector2i((GRID_WIDTH - 1) - pos.x, (GRID_HEIGHT - 1) - pos.y)


static func kickoff_spot(team: int) -> Vector2i:
	return CENTER_SPOT if team == Team.HOME else AWAY_SPOT


## Pitch centre in cell-corner units: halfway border, middle of the centre row.
static func pitch_centre() -> Vector2:
	return Vector2(float(HALFWAY_X), float(CENTER_Y) + 0.5)


## True when the cell's visual centre sits strictly inside the centre circle.
## On the circle line is outside (opponents must be at least the radius away).
static func in_centre_circle(cell: Vector2i) -> bool:
	var pos := Vector2(cell) + Vector2(0.5, 0.5)
	return pos.distance_to(pitch_centre()) < CENTRE_CIRCLE_R


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


## All 7 other facings. 45°/90° cost 1 AP; 135°/180° cost 2 AP.
static func turn_facings(facing: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for steps in range(1, FACING_RING.size()):
		result.append(rotate_facing(facing, steps))
	return result


static func is_move_step(from: Vector2i, to: Vector2i, facing: Vector2i) -> bool:
	var face := normalize_facing(facing)
	if face == Vector2i.ZERO:
		return is_adjacent(from, to)
	return (to - from) in move_facings(face)


## The empty cell two tiles straight ahead. Occupied through or dest tiles block it.
static func sprint_destinations(
	from: Vector2i,
	facing: Vector2i,
	occupied: Dictionary
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var face := normalize_facing(facing)
	if face == Vector2i.ZERO:
		return result
	var through: Vector2i = from + face
	var dest: Vector2i = from + face * SPRINT_DISTANCE
	if not in_bounds(through) or not in_bounds(dest):
		return result
	if occupied.has(through) or occupied.has(dest):
		return result
	result.append(dest)
	return result


static func sprint_through(from: Vector2i, dest: Vector2i) -> Vector2i:
	return from + normalize_facing(dest - from)


static func is_sprint_step(from: Vector2i, to: Vector2i, facing: Vector2i) -> bool:
	var face := normalize_facing(facing)
	if face == Vector2i.ZERO:
		return false
	return to == from + face * SPRINT_DISTANCE


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


## Every empty cell a cone-walk can hit by spending at most `remaining_ap`.
## No turns: facing only changes by stepping. Values are `{cost, path}` where
## `path` is the ordered destination cells (not including `from`).
static func move_reach(
	from: Vector2i,
	facing: Vector2i,
	blocked: Dictionary,
	remaining_ap: int
) -> Dictionary:
	var reach := {}
	if remaining_ap < MOVE_ORTHO_COST:
		return reach
	var face0 := normalize_facing(facing)
	var start_path: Array[Vector2i] = []
	var pending: Array[Dictionary] = [{
		pos = from,
		facing = face0,
		cost = 0,
		steps = 0,
		path = start_path,
	}]
	var best_cost := {_move_state_key(from, face0): 0}
	var done := {}
	while not pending.is_empty():
		var best_i := 0
		for i in range(1, pending.size()):
			if _move_pending_better(pending[i], pending[best_i]):
				best_i = i
		var cur: Dictionary = pending[best_i]
		pending.remove_at(best_i)
		var key := _move_state_key(cur.pos, cur.facing)
		if done.has(key):
			continue
		done[key] = true
		if cur.pos != from and not reach.has(cur.pos):
			reach[cur.pos] = {
				cost = int(cur.cost),
				path = cur.path,
			}
		if int(cur.cost) + MOVE_ORTHO_COST > remaining_ap:
			continue
		for dest in move_destinations(cur.pos, blocked, cur.facing):
			var next_cost: int = int(cur.cost) + step_ap_cost(cur.pos, dest)
			if next_cost > remaining_ap:
				continue
			var next_face := step_direction(cur.pos, dest)
			var next_key := _move_state_key(dest, next_face)
			if done.has(next_key):
				continue
			if best_cost.has(next_key) and int(best_cost[next_key]) <= next_cost:
				continue
			best_cost[next_key] = next_cost
			var next_path: Array[Vector2i] = []
			for cell in cur.path:
				next_path.append(cell)
			next_path.append(dest)
			pending.append({
				pos = dest,
				facing = next_face,
				cost = next_cost,
				steps = int(cur.steps) + 1,
				path = next_path,
			})
	return reach


static func _move_state_key(pos: Vector2i, facing: Vector2i) -> String:
	return "%d,%d,%d,%d" % [pos.x, pos.y, facing.x, facing.y]


static func _move_pending_better(a: Dictionary, b: Dictionary) -> bool:
	var ca := int(a.get("cost", 0))
	var cb := int(b.get("cost", 0))
	if ca != cb:
		return ca < cb
	return int(a.get("steps", 0)) < int(b.get("steps", 0))


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


## The 3×3 neighbourhood centred on `origin`, including the origin itself.
## Out-of-bounds cells are dropped, so edges and nets yield fewer than 9.
static func bounce_cells(origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell := origin + Vector2i(dx, dy)
			if in_bounds(cell):
				cells.append(cell)
	return cells


static func pick_bounce_cell(origin: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var cells := bounce_cells(origin)
	if cells.is_empty():
		return origin
	return cells[rng.randi_range(0, cells.size() - 1)]


## Each side rolls 1dSTAT (1..stat). Higher roll wins. Numeric ties set `tied`.
## When `tie_goes_to_attacker`, a numeric tie is still an attacker win.
static func resolve_contest(
	attacker_stat: int,
	defender_stat: int,
	rng: RandomNumberGenerator,
	tie_goes_to_attacker: bool = false
) -> Dictionary:
	var attacker_dice := roll_d_stat(attacker_stat, rng)
	var defender_dice := roll_d_stat(defender_stat, rng)
	var tied := attacker_dice == defender_dice
	var attacker_won := (
		attacker_dice > defender_dice
		or (tied and tie_goes_to_attacker)
	)
	return {
		attacker_stat = attacker_stat,
		defender_stat = defender_stat,
		attacker_dice = attacker_dice,
		defender_dice = defender_dice,
		attacker_total = attacker_dice,
		defender_total = defender_dice,
		attacker_won = attacker_won,
		tied = tied,
	}


## Tests force a winner; dice are filled in so the log still reads as 1dSTAT.
static func apply_scripted_winner(roll: Dictionary, attacker_won: bool) -> void:
	roll.attacker_won = attacker_won
	roll.tied = false
	if attacker_won:
		roll.attacker_dice = maxi(int(roll.get("attacker_stat", 1)), 2)
		roll.defender_dice = 1
	else:
		roll.attacker_dice = 1
		roll.defender_dice = maxi(int(roll.get("defender_stat", 1)), 2)
	roll.attacker_total = roll.attacker_dice
	roll.defender_total = roll.defender_dice


## Tests force a numeric tie. Dice share the smaller face so the log still reads 1dSTAT.
static func apply_scripted_tie(roll: Dictionary) -> void:
	var face := mini(
		maxi(int(roll.get("attacker_stat", 1)), 1),
		maxi(int(roll.get("defender_stat", 1)), 1)
	)
	roll.tied = true
	roll.attacker_won = false
	roll.attacker_dice = face
	roll.defender_dice = face
	roll.attacker_total = face
	roll.defender_total = face


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


## Angle between the carrier's facing and the cell the tackler is coming from.
## Snaps to the 8-dir ring: 0 front, 45, 90 side, 135, 180 back.
static func tackle_approach_angle_deg(
	carrier_facing: Vector2i,
	tackler_pos: Vector2i,
	from_cell: Vector2i
) -> int:
	var face := Vector2(normalize_facing(carrier_facing))
	var approach := Vector2(tackler_pos - from_cell)
	if face == Vector2.ZERO or approach == Vector2.ZERO:
		return 0
	var angle_deg := absf(rad_to_deg(face.angle_to(approach)))
	var snapped_deg := int(round(angle_deg / 45.0)) * 45
	return clampi(snapped_deg, 0, 180)


static func tackle_angle_penalty(angle_deg: int) -> float:
	match angle_deg:
		0:
			return TACKLE_FRONT_PENALTY
		45:
			return TACKLE_45_PENALTY
		90:
			return TACKLE_SIDE_PENALTY
		135:
			return TACKLE_135_PENALTY
		180:
			return TACKLE_BACK_PENALTY
		_:
			return TACKLE_FRONT_PENALTY


static func tackle_angle_label(angle_deg: int) -> String:
	match angle_deg:
		0:
			return "front"
		45:
			return "45°"
		90:
			return "side"
		135:
			return "135°"
		180:
			return "back"
		_:
			return "%d°" % angle_deg


static func tackle_direction(
	carrier_facing: Vector2i,
	tackler_pos: Vector2i,
	from_cell: Vector2i
) -> Dictionary:
	var angle_deg := tackle_approach_angle_deg(carrier_facing, tackler_pos, from_cell)
	var penalty := tackle_angle_penalty(angle_deg)
	return {
		angle_deg = angle_deg,
		penalty = penalty,
		label = tackle_angle_label(angle_deg),
	}


static func apply_tackle_angle_chance(base_chance: float, penalty: float) -> float:
	return clampf(base_chance + penalty, 0.0, 1.0)


## After a 1dSTAT win, drop some successes so overall P(win) matches the angled chance.
## Ties are left alone. A 0% final chance converts every dice win into a loss.
static func apply_tackle_direction_penalty(
	roll: Dictionary,
	penalty: float,
	rng: RandomNumberGenerator
) -> void:
	if penalty >= 0.0:
		return
	if not bool(roll.get("attacker_won", false)) or bool(roll.get("tied", false)):
		return
	var base := contest_win_chance(
		int(roll.get("attacker_stat", 1)),
		int(roll.get("defender_stat", 1)),
		false
	)
	var final_chance := apply_tackle_angle_chance(base, penalty)
	if final_chance <= 0.0:
		roll.attacker_won = false
		return
	if base <= 0.0:
		return
	var keep := final_chance / base
	if rng.randf() >= keep:
		roll.attacker_won = false


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
	## Dribble and tackle ties bounce the ball; they are not attacker wins.
	var ties_to_atk := false
	if on_ball or occupant.has_ball:
		ties_to_atk = false
	else:
		ties_to_atk = attacker_wins_ties(mover, occupant, possession_team)
	var chance := contest_win_chance(atk, deff, ties_to_atk)
	var angle_deg := 0
	var angle_penalty := 0.0
	var angle_label := "front"
	if action == "tackle":
		var direction := tackle_direction(occupant.facing, mover.pos, occupant.pos)
		angle_deg = int(direction.angle_deg)
		angle_penalty = float(direction.penalty)
		angle_label = str(direction.label)
		chance = apply_tackle_angle_chance(chance, angle_penalty)
	var pct := int(round(chance * 100.0))
	var text := "%s %s %d %s vs %d %s = %d%% success" % [
		verb, occupant.label(), atk, atk_name, deff, def_name, pct
	]
	if action == "tackle" and angle_penalty < 0.0:
		text += " (%s %d%%)" % [angle_label, int(round(angle_penalty * 100.0))]
	return {
		action = action,
		verb = verb,
		attacker_stat_name = atk_name,
		defender_stat_name = def_name,
		attacker_stat = atk,
		defender_stat = deff,
		chance = chance,
		percent = pct,
		angle_deg = angle_deg,
		angle_penalty = angle_penalty,
		angle_label = angle_label,
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
