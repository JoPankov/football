class_name Pitch
extends Node2D

const LINE := Color("3ecbff")
const LINE_DIM := Color(0.24, 0.88, 0.63, 0.35)
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
const SELECT_FILL := Color(1.0, 0.92, 0.45, 0.22)
const HOVER_FILL := Color(1.0, 1.0, 1.0, 0.08)

var selected_cell: Vector2i = Vector2i(-1, -1)
var hover_cell: Vector2i = Vector2i(-1, -1)
var move_cells: Array[Vector2i] = []
var contest_cells: Array[Vector2i] = []
var pass_cells: Array[Vector2i] = []
var choice_cells: Array[Vector2i] = []
var shoot_cells: Array[Vector2i] = []
var offside_cells: Array[Vector2i] = []
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
	offsides: Array[Vector2i] = []
) -> void:
	selected_cell = selected
	move_cells = moves
	contest_cells = contests
	pass_cells = passes
	choice_cells = choices
	shoot_cells = shots
	offside_cells = offsides
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
		var alpha := 0.55 if x == 0 or x == MatchRules.GRID_WIDTH or x == MatchRules.GRID_WIDTH / 2 else 0.22
		draw_line(Vector2(x * tile, 0), Vector2(x * tile, size.y), Color(LINE, alpha), 1.5)
	for y in MatchRules.GRID_HEIGHT + 1:
		var alpha := 0.55 if y == 0 or y == MatchRules.GRID_HEIGHT else 0.18
		draw_line(Vector2(0, y * tile), Vector2(size.x, y * tile), Color(LINE, alpha), 1.5)

	var mid_x := size.x * 0.5
	draw_line(Vector2(mid_x, 0), Vector2(mid_x, size.y), LINE, 2.0)
	draw_arc(Vector2(mid_x, size.y * 0.5), tile * 1.15, 0.0, TAU, 64, LINE_DIM, 2.0, true)
	draw_circle(Vector2(mid_x, size.y * 0.5), 4.0, LINE)

	var box_rows := 3.0 if MatchRules.GRID_HEIGHT % 2 == 1 else 4.0
	var box_h := tile * box_rows
	var box_y := (size.y - box_h) * 0.5
	draw_rect(Rect2(0, box_y, tile, box_h), Color.TRANSPARENT, false, 2.0)
	draw_rect(Rect2(size.x - tile, box_y, tile, box_h), Color.TRANSPARENT, false, 2.0)
	draw_polyline(PackedVector2Array([
		Vector2(0, box_y), Vector2(tile, box_y), Vector2(tile, box_y + box_h), Vector2(0, box_y + box_h)
	]), LINE, 2.0)
	draw_polyline(PackedVector2Array([
		Vector2(size.x, box_y), Vector2(size.x - tile, box_y),
		Vector2(size.x - tile, box_y + box_h), Vector2(size.x, box_y + box_h)
	]), Color("ff4d8d"), 2.0)


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
	for cell in shoot_cells:
		var rect := Rect2(Vector2(cell) * tile + Vector2(4, 4), Vector2(tile - 8, tile - 8))
		draw_rect(rect, SHOOT_FILL)
		draw_rect(rect, SHOOT_LINE, false, 2.4)


func _draw_plans() -> void:
	var tile := MatchRules.TILE_SIZE
	for plan in plan_markers:
		var from_cell: Vector2i = plan.get("origin", Vector2i.ZERO)
		var to_cell: Vector2i = plan.get("dest", from_cell)
		var team := int(plan.get("team", MatchRules.Team.HOME))
		var color := Color("3ecbff") if team == MatchRules.Team.HOME else Color("ff4d8d")
		var start := grid_to_world(from_cell)
		var finish := grid_to_world(to_cell)
		if from_cell != to_cell:
			draw_line(start, finish, Color(color, 0.75), 2.0, true)
			var tip := (finish - start).normalized() * 10.0
			var side := tip.orthogonal() * 0.45
			draw_colored_polygon(PackedVector2Array([
				finish,
				finish - tip + side,
				finish - tip - side,
			]), color)
		var rect := Rect2(Vector2(to_cell) * tile + Vector2(16, 16), Vector2(tile - 32, tile - 32))
		draw_rect(rect, Color(color, 0.18))
		draw_rect(rect, color, false, 1.6)


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
