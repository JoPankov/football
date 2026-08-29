class_name Pitch
extends Node2D

const LINE := Color("3ecbff")
const MARK := Color("d4f6ff")
const MARK_WIDTH := 3.2
## Visual markings snapped to the 26×17 grid (nearest cell to FIFA).
## Penalty area 16.5 m ≈ 4 tiles deep, 40.32 m ≈ 11 tiles wide.
## Goal area 5.5 m ≈ 1 tile deep, 18.32 m ≈ 5 tiles wide.
## Penalty spot 11 m ≈ centre of the cell 2 in from the goal line.
## Centre circle / penalty arc 9.15 m ≈ 2.5 tiles (hits cell borders).
## Corner arc 1 m → 1 tile so it sits on the corner cell's inner borders.
const MARK_PENALTY_DEPTH := 4
const MARK_PENALTY_HALF := 5
const MARK_GOAL_AREA_DEPTH := 1
const MARK_GOAL_AREA_HALF := 2
const MARK_PENALTY_SPOT_X := 2
const MARK_CENTRE_R := MatchRules.CENTRE_CIRCLE_R
const MARK_CORNER_R := 1.0
const MARK_SPOT_R := 0.08
const TILE_A := Color("0b1d1a")
const TILE_B := Color("0d241c")
const HOME_THIRD := Color(0.09, 0.28, 0.36, 0.22)
const AWAY_THIRD := Color(0.36, 0.09, 0.22, 0.22)
const GOAL_HOME := Color(0.24, 0.8, 1.0, 0.18)
const GOAL_AWAY := Color(1.0, 0.3, 0.55, 0.18)
const MOVE_FILL := Color(0.24, 0.88, 0.63, 0.28)
const MOVE_LINE := Color("7dffe0")
const CONTEST_FILL := Color(1.0, 0.55, 0.16, 0.32)
const CONTEST_LINE := Color("ffb347")
const PASS_FILL := Color(0.44, 0.72, 1.0, 0.32)
const PASS_LINE := Color("6fd3ff")
const CHOICE_FILL := Color(0.72, 0.48, 1.0, 0.34)
const CHOICE_LINE := Color("c9a6ff")
const SHOOT_FILL := Color(1.0, 0.85, 0.25, 0.38)
const SHOOT_LINE := Color("ffe27a")
const OFFSIDE_FILL := Color(1.0, 0.28, 0.32, 0.34)
const OFFSIDE_LINE := Color("ff6b73")
const TURN_FILL := Color(0.85, 0.9, 1.0, 0.22)
const TURN_LINE := Color("d7e4ff")
const SELECT_FILL := Color(1.0, 0.92, 0.45, 0.22)
const HOVER_FILL := Color(1.0, 1.0, 1.0, 0.08)
const PLAN_MOVE := Color("ffe27a")
const PLAN_TURN := Color("6dff8a")
const PLAN_PASS := Color("6fd3ff")

var selected_cell: Vector2i = Vector2i(-1, -1)
var hover_cell: Vector2i = Vector2i(-1, -1)
var move_cells: Array[Vector2i] = []
var contest_cells: Array[Vector2i] = []
var pass_cells: Array[Vector2i] = []
var choice_cells: Array[Vector2i] = []
var shoot_cells: Array[Vector2i] = []
var offside_cells: Array[Vector2i] = []
var turn_cells: Array[Vector2i] = []
var plan_markers: Array[Dictionary] = []
var pass_lane_from: Vector2i = Vector2i(-1, -1)
var pass_lane_to: Vector2i = Vector2i(-1, -1)
var intercept_cells: Array[Vector2i] = []

@onready var pieces: Node2D = $Pieces
@onready var ball_piece: BallPiece = $Pieces/Ball


func _ready() -> void:
	queue_redraw()


func grid_to_world(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * MatchRules.TILE_SIZE


func world_to_grid(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / MatchRules.TILE_SIZE), floori(world.y / MatchRules.TILE_SIZE))


func pitch_size() -> Vector2:
	return Vector2(MatchRules.GRID_WIDTH, MatchRules.GRID_HEIGHT) * MatchRules.TILE_SIZE


func world_rect() -> Rect2:
	var tile := MatchRules.TILE_SIZE
	var pad := 24.0
	var left := float(MatchRules.HOME_NET.x) * tile
	var right := float(MatchRules.AWAY_NET.x + 1) * tile
	return Rect2(left, -pad, right - left, float(MatchRules.GRID_HEIGHT) * tile + pad * 2.0)


func carried_ball_offset(team: int) -> Vector2:
	var side := 1.0 if team == MatchRules.Team.HOME else -1.0
	return Vector2(side * 16.0, 14.0)


func set_highlights(
	selected: Vector2i,
	moves: Array[Vector2i],
	contests: Array[Vector2i] = [],
	passes: Array[Vector2i] = [],
	choices: Array[Vector2i] = [],
	shots: Array[Vector2i] = [],
	offsides: Array[Vector2i] = [],
	turns: Array[Vector2i] = []
) -> void:
	selected_cell = selected
	move_cells = moves
	contest_cells = contests
	pass_cells = passes
	choice_cells = choices
	shoot_cells = shots
	offside_cells = offsides
	turn_cells = turns
	queue_redraw()


func set_hover(cell: Vector2i) -> void:
	if hover_cell == cell:
		return
	hover_cell = cell
	queue_redraw()


func set_pass_preview(from_cell: Vector2i, to_cell: Vector2i, interceptors: Array[Vector2i]) -> void:
	if pass_lane_from == from_cell and pass_lane_to == to_cell and intercept_cells == interceptors:
		return
	pass_lane_from = from_cell
	pass_lane_to = to_cell
	intercept_cells = interceptors
	queue_redraw()


func set_plans(markers: Array[Dictionary]) -> void:
	plan_markers = markers
	queue_redraw()


func clear_pass_preview() -> void:
	set_pass_preview(Vector2i(-1, -1), Vector2i(-1, -1), [])


func clear_highlights() -> void:
	set_highlights(Vector2i(-1, -1), [])


func spawn_player(state: PlayerState) -> PlayerPiece:
	var piece := preload("res://scenes/player.tscn").instantiate() as PlayerPiece
	pieces.add_child(piece)
	piece.configure(state)
	piece.position = grid_to_world(state.pos)
	return piece


func sync_ball(state: BallState, carrier: PlayerState) -> void:
	ball_piece.set_carried(carrier != null)
	if carrier != null:
		ball_piece.position = grid_to_world(carrier.pos) + carried_ball_offset(carrier.team)
	else:
		ball_piece.position = grid_to_world(state.pos)
	ball_piece.z_index = 8


func _draw() -> void:
	var tile := MatchRules.TILE_SIZE
	var size := pitch_size()
	draw_rect(Rect2(Vector2(-24, -24), size + Vector2(48, 48)), Color("061018"))

	for x in MatchRules.GRID_WIDTH:
		for y in MatchRules.GRID_HEIGHT:
			var cell := Vector2i(x, y)
			var rect := Rect2(Vector2(x, y) * tile, Vector2(tile, tile))
			var base := TILE_A if (x + y) % 2 == 0 else TILE_B
			draw_rect(rect, base)
			if MatchRules.is_attacking_third(cell, MatchRules.Team.HOME):
				draw_rect(rect, AWAY_THIRD)
			elif MatchRules.is_attacking_third(cell, MatchRules.Team.AWAY):
				draw_rect(rect, HOME_THIRD)
			if x == 0:
				draw_rect(rect, GOAL_HOME)
			elif x == MatchRules.GRID_WIDTH - 1:
				draw_rect(rect, GOAL_AWAY)

	_draw_net_tile(MatchRules.HOME_NET, Color("0a2430"), Color("3ecbff"))
	_draw_net_tile(MatchRules.AWAY_NET, Color("300a18"), Color("ff4d8d"))
	_draw_markings(tile, size)
	_draw_interactive(tile)
	_draw_plans()
	_draw_pass_preview()


func _draw_net_tile(cell: Vector2i, fill: Color, line: Color) -> void:
	var tile := MatchRules.TILE_SIZE
	var rect := Rect2(Vector2(cell) * tile, Vector2(tile, tile))
	draw_rect(rect, fill)
	draw_rect(rect, Color(line, 0.35))
	var step := tile / 4.0
	for i in range(1, 4):
		var x := rect.position.x + step * float(i)
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(line, 0.28), 1.0)
	for i in range(1, 4):
		var y := rect.position.y + step * float(i)
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(line, 0.28), 1.0)
	draw_rect(rect, line, false, 2.0)


func _draw_markings(tile: float, size: Vector2) -> void:
	for x in MatchRules.GRID_WIDTH + 1:
		var alpha := 0.42 if x == 0 or x == MatchRules.GRID_WIDTH or x == MatchRules.GRID_WIDTH / 2 else 0.14
		draw_line(Vector2(x * tile, 0), Vector2(x * tile, size.y), Color(LINE, alpha), 1.0)
	for y in MatchRules.GRID_HEIGHT + 1:
		var alpha := 0.42 if y == 0 or y == MatchRules.GRID_HEIGHT else 0.12
		draw_line(Vector2(0, y * tile), Vector2(size.x, y * tile), Color(LINE, alpha), 1.0)
	_draw_pitch_markings(size)


func _cell_xy(x: float, y: float) -> Vector2:
	return Vector2(x, y) * MatchRules.TILE_SIZE


func _spot_px() -> float:
	return maxf(5.0, MARK_SPOT_R * MatchRules.TILE_SIZE)


func _draw_goal_box(goal_x: float, inner_x: float, y0: float, y1: float) -> void:
	draw_polyline(PackedVector2Array([
		_cell_xy(goal_x, y0),
		_cell_xy(inner_x, y0),
		_cell_xy(inner_x, y1),
		_cell_xy(goal_x, y1),
	]), MARK, MARK_WIDTH, true)


func _draw_goal_mouth(goal_x: float, back_x: float, y0: float, y1: float, color: Color) -> void:
	draw_polyline(PackedVector2Array([
		_cell_xy(goal_x, y0),
		_cell_xy(back_x, y0),
		_cell_xy(back_x, y1),
		_cell_xy(goal_x, y1),
	]), color, MARK_WIDTH + 0.4, true)


func _draw_pitch_markings(size: Vector2) -> void:
	var tile := MatchRules.TILE_SIZE
	var mid_x := float(MatchRules.HALFWAY_X)
	var cy := float(MatchRules.CENTER_Y) + 0.5
	var away_x := float(MatchRules.GRID_WIDTH)
	var penalty_y0 := float(MatchRules.CENTER_Y - MARK_PENALTY_HALF)
	var penalty_y1 := float(MatchRules.CENTER_Y + 1 + MARK_PENALTY_HALF)
	var six_y0 := float(MatchRules.CENTER_Y - MARK_GOAL_AREA_HALF)
	var six_y1 := float(MatchRules.CENTER_Y + 1 + MARK_GOAL_AREA_HALF)
	var centre := _cell_xy(mid_x, cy)
	var radius := MARK_CENTRE_R * tile

	draw_rect(Rect2(Vector2.ZERO, size), MARK, false, MARK_WIDTH)
	draw_line(_cell_xy(mid_x, 0.0), _cell_xy(mid_x, float(MatchRules.GRID_HEIGHT)), MARK, MARK_WIDTH, true)
	draw_arc(centre, radius, 0.0, TAU, 96, MARK, MARK_WIDTH, true)
	draw_circle(centre, _spot_px(), MARK)

	_draw_goal_box(0.0, float(MARK_PENALTY_DEPTH), penalty_y0, penalty_y1)
	_draw_goal_box(away_x, away_x - float(MARK_PENALTY_DEPTH), penalty_y0, penalty_y1)
	_draw_goal_box(0.0, float(MARK_GOAL_AREA_DEPTH), six_y0, six_y1)
	_draw_goal_box(away_x, away_x - float(MARK_GOAL_AREA_DEPTH), six_y0, six_y1)

	var home_spot := grid_to_world(Vector2i(MARK_PENALTY_SPOT_X, MatchRules.CENTER_Y))
	var away_spot := grid_to_world(Vector2i(MatchRules.GRID_WIDTH - 1 - MARK_PENALTY_SPOT_X, MatchRules.CENTER_Y))
	draw_circle(home_spot, _spot_px(), MARK)
	draw_circle(away_spot, _spot_px(), MARK)
	var spot_to_box := float(MARK_PENALTY_DEPTH) - (float(MARK_PENALTY_SPOT_X) + 0.5)
	var arc_half := acos(clampf(spot_to_box / MARK_CENTRE_R, -1.0, 1.0))
	draw_arc(home_spot, radius, -arc_half, arc_half, 32, MARK, MARK_WIDTH, true)
	draw_arc(away_spot, radius, PI - arc_half, PI + arc_half, 32, MARK, MARK_WIDTH, true)

	var corner_r := MARK_CORNER_R * tile
	draw_arc(_cell_xy(0.0, 0.0), corner_r, 0.0, PI * 0.5, 16, MARK, MARK_WIDTH, true)
	draw_arc(_cell_xy(0.0, float(MatchRules.GRID_HEIGHT)), corner_r, -PI * 0.5, 0.0, 16, MARK, MARK_WIDTH, true)
	draw_arc(_cell_xy(away_x, 0.0), corner_r, PI * 0.5, PI, 16, MARK, MARK_WIDTH, true)
	draw_arc(_cell_xy(away_x, float(MatchRules.GRID_HEIGHT)), corner_r, PI, PI * 1.5, 16, MARK, MARK_WIDTH, true)

	var net_y0 := float(MatchRules.CENTER_Y)
	var net_y1 := float(MatchRules.CENTER_Y + 1)
	_draw_goal_mouth(0.0, -1.0, net_y0, net_y1, LINE)
	_draw_goal_mouth(away_x, away_x + 1.0, net_y0, net_y1, Color("ff4d8d"))


func _draw_interactive(tile: float) -> void:
	if MatchRules.in_bounds(hover_cell):
		draw_rect(Rect2(Vector2(hover_cell) * tile, Vector2(tile, tile)), HOVER_FILL)
	if MatchRules.in_bounds(selected_cell):
		draw_rect(Rect2(Vector2(selected_cell) * tile, Vector2(tile, tile)), SELECT_FILL)
	for cell in move_cells:
		if cell in contest_cells:
			continue
		var rect := Rect2(Vector2(cell) * tile + Vector2(8, 8), Vector2(tile - 16, tile - 16))
		draw_rect(rect, MOVE_FILL)
		draw_rect(rect, MOVE_LINE, false, 1.5)
	for cell in contest_cells:
		var rect := Rect2(Vector2(cell) * tile + Vector2(8, 8), Vector2(tile - 16, tile - 16))
		draw_rect(rect, CONTEST_FILL)
		draw_rect(rect, CONTEST_LINE, false, 1.8)
	for cell in pass_cells:
		if cell in choice_cells or cell in offside_cells:
			continue
		var rect := Rect2(Vector2(cell) * tile + Vector2(10, 10), Vector2(tile - 20, tile - 20))
		draw_rect(rect, PASS_FILL)
		draw_rect(rect, PASS_LINE, false, 1.8)
	for cell in offside_cells:
		if cell in choice_cells:
			continue
		var rect := Rect2(Vector2(cell) * tile + Vector2(10, 10), Vector2(tile - 20, tile - 20))
		draw_rect(rect, OFFSIDE_FILL)
		draw_rect(rect, OFFSIDE_LINE, false, 1.8)
	for cell in choice_cells:
		var rect := Rect2(Vector2(cell) * tile + Vector2(8, 8), Vector2(tile - 16, tile - 16))
		draw_rect(rect, CHOICE_FILL)
		draw_rect(rect, CHOICE_LINE, false, 2.0)
	for cell in turn_cells:
		var rect := Rect2(Vector2(cell) * tile + Vector2(18, 18), Vector2(tile - 36, tile - 36))
		draw_rect(rect, TURN_FILL)
		draw_rect(rect, TURN_LINE, false, 1.6)
	for cell in shoot_cells:
		var rect := Rect2(Vector2(cell) * tile + Vector2(4, 4), Vector2(tile - 8, tile - 8))
		draw_rect(rect, SHOOT_FILL)
		draw_rect(rect, SHOOT_LINE, false, 2.4)


func _draw_plans() -> void:
	var tile := MatchRules.TILE_SIZE
	for plan in plan_markers:
		var act := str(plan.get("action", ""))
		if act == "done":
			continue
		var from_cell: Vector2i = plan.get("origin", Vector2i.ZERO)
		var to_cell: Vector2i = plan.get("dest", from_cell)
		var start := grid_to_world(from_cell)
		var finish := grid_to_world(to_cell)
		if act == "turn":
			_draw_turn_arrow(start, finish)
			continue
		var color := PLAN_PASS if act in ["pass", "shoot"] else PLAN_MOVE
		if from_cell != to_cell:
			_draw_plan_arrow(start, finish, color, 2.6, 12.0)
		var rect := Rect2(Vector2(to_cell) * tile + Vector2(16, 16), Vector2(tile - 32, tile - 32))
		draw_rect(rect, Color(color, 0.18))
		draw_rect(rect, color, false, 1.6)


func _draw_turn_arrow(start: Vector2, finish: Vector2) -> void:
	var delta := finish - start
	if delta == Vector2.ZERO:
		return
	var dir := delta.normalized()
	var tile := MatchRules.TILE_SIZE
	var shaft_start := start + dir * (tile * 0.20)
	var shaft_end := start + dir * (tile * 0.46)
	_draw_plan_arrow(shaft_start, shaft_end, PLAN_TURN, 3.4, 9.0)


func _draw_plan_arrow(start: Vector2, finish: Vector2, color: Color, width: float, head: float) -> void:
	var delta := finish - start
	if delta.length_squared() < 1.0:
		return
	var dir := delta.normalized()
	draw_line(start, finish, Color(color, 0.92), width, true)
	var tip := dir * head
	var side := dir.orthogonal() * (head * 0.48)
	draw_colored_polygon(PackedVector2Array([
		finish + dir * 1.5,
		finish - tip + side,
		finish - tip - side,
	]), color)


func _draw_pass_preview() -> void:
	if not MatchRules.in_bounds(pass_lane_from) or not MatchRules.in_bounds(pass_lane_to):
		return
	var start := grid_to_world(pass_lane_from)
	var finish := grid_to_world(pass_lane_to)
	var radius := MatchRules.INTERCEPT_RADIUS * MatchRules.TILE_SIZE
	for cell in intercept_cells:
		var center := grid_to_world(cell)
		draw_circle(center, radius, Color(1.0, 0.55, 0.16, 0.12))
		draw_arc(center, radius, 0.0, TAU, 72, Color("ffb347"), 2.0, true)
	draw_line(start, finish, Color(0.44, 0.83, 1.0, 0.95), 3.0, true)
	draw_circle(start, 5.0, Color("6fd3ff"))
	draw_circle(finish, 5.0, Color("6fd3ff"))
