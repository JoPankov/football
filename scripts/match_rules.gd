class_name MatchRules
extends RefCounted

## Pure, side-effect-free rules for the 12×7 grid.
## Shoot is not wired up in this slice.

enum Team { HOME, AWAY }

const GRID_WIDTH := 12
const GRID_HEIGHT := 7
const MOVE_DISTANCE := 1
const PASS_RANGE := 3
const INTERCEPT_RADIUS := 1.0
const TILE_SIZE := 72.0
const CENTER_SPOT := Vector2i(5, 3)
const HOME_NET := Vector2i(-1, 3)
const AWAY_NET := Vector2i(12, 3)
const SHOT_ACC_BIAS := 1
const SHOT_RANGE_K := 0.35
const SHOT_ANGLE_FLOOR := 0.15

## Ways to roll each 2d6 total (index = sum). 2..12.
const WAYS_2D6: Array[int] = [0, 0, 1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1]
const OUTCOMES_2D6 := 36
const CONTEST_PAIRS := 1296

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
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


static func shot_hit_chance(accuracy: int, distance: float, angle_rad: float) -> float:
	var acc_term := float(accuracy) / float(accuracy + SHOT_ACC_BIAS)
	var hit := acc_term * shot_range_factor(distance) * shot_angle_factor(angle_rad)
	return clampf(hit, 0.05, 0.98)


static func in_bounds(pos: Vector2i) -> bool:
	return is_pitch_tile(pos) or is_goal_tile(pos)


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func is_adjacent(from: Vector2i, to: Vector2i) -> bool:
	return chebyshev(from, to) == MOVE_DISTANCE


static func opposite_team(team: int) -> int:
	return Team.AWAY if team == Team.HOME else Team.HOME


static func team_name(team: int) -> String:
	return TEAM_NAME.get(team, "UNKNOWN")


## Opponent's last third: 4 columns (12 / 3). Home attacks +x.
static func is_attacking_third(pos: Vector2i, team: int) -> bool:
	if team == Team.HOME:
		return pos.x >= 8
	return pos.x <= 3


static func can_use_ball_action(has_ball: bool) -> bool:
	return has_ball


## Cells in `blocked` cannot be entered (teammates). Opponent cells are legal.
static func move_destinations(from: Vector2i, blocked: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in DIRECTIONS:
		var dest: Vector2i = from + dir
		if not in_bounds(dest):
			continue
		if blocked.has(dest):
			continue
		result.append(dest)
	return result


static func roll_2d6(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(1, 6) + rng.randi_range(1, 6)


## Two 2d6 rolls plus the relevant stats. Ties go to the occupant.
static func resolve_contest(attacker_stat: int, defender_stat: int, rng: RandomNumberGenerator) -> Dictionary:
	var attacker_dice := roll_2d6(rng)
	var defender_dice := roll_2d6(rng)
	var attacker_total := attacker_stat + attacker_dice
	var defender_total := defender_stat + defender_dice
	return {
		attacker_stat = attacker_stat,
		defender_stat = defender_stat,
		attacker_dice = attacker_dice,
		defender_dice = defender_dice,
		attacker_total = attacker_total,
		defender_total = defender_total,
		attacker_won = attacker_total > defender_total,
	}


## Chance the mover wins (strictly higher than occupant after 2d6). Ties stay with occupant.
static func contest_win_chance(attacker_stat: int, defender_stat: int) -> float:
	var wins := 0
	for atk_dice in range(2, 13):
		for def_dice in range(2, 13):
			if attacker_stat + atk_dice > defender_stat + def_dice:
				wins += WAYS_2D6[atk_dice] * WAYS_2D6[def_dice]
	return float(wins) / float(CONTEST_PAIRS)


static func contest_preview(mover: PlayerState, occupant: PlayerState) -> Dictionary:
	var action := "challenge"
	var verb := "square fight"
	var atk_name := "CTR"
	var def_name := "CTR"
	var atk := mover.control
	var deff := occupant.control
	if mover.has_ball:
		action = "dribble"
		verb = "dribble"
		atk_name = "CTR"
		def_name = "DEF"
		atk = mover.control
		deff = occupant.defense
	elif occupant.has_ball:
		action = "tackle"
		verb = "tackle"
		atk_name = "DEF"
		def_name = "CTR"
		atk = mover.defense
		deff = occupant.control
	var chance := contest_win_chance(atk, deff)
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
