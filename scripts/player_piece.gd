class_name PlayerPiece
extends Node2D

const HOME_FILL := Color("12485c")
const HOME_GLOW := Color("3ecbff")
const AWAY_FILL := Color("5c1232")
const AWAY_GLOW := Color("ff4d8d")
const GK_HOME := Color("0b3040")
const GK_AWAY := Color("401022")
const FACE := Color("071018")
const NUMBER := Color("f4fbff")

var player_id: int = -1
var team: int = MatchRules.Team.HOME
var number: int = 0
var role: String = ""
var selected: bool = false
var has_ball: bool = false
var on_turn: bool = false

@onready var _number_label: Label = $Number
@onready var _role_label: Label = $Role


func configure(state: PlayerState) -> void:
	player_id = state.id
	team = state.team
	number = state.number
	role = state.role
	has_ball = state.has_ball
	if _number_label:
		_refresh_labels()
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func set_has_ball(value: bool) -> void:
	has_ball = value
	queue_redraw()


func set_on_turn(value: bool) -> void:
	on_turn = value
	queue_redraw()


func _ready() -> void:
	_refresh_labels()
	queue_redraw()


func _refresh_labels() -> void:
	_number_label.text = str(number)
	_role_label.text = role
	var glow := HOME_GLOW if team == MatchRules.Team.HOME else AWAY_GLOW
	_number_label.add_theme_color_override("font_color", NUMBER)
	_role_label.add_theme_color_override("font_color", glow.lightened(0.25))


func _draw() -> void:
	var radius := MatchRules.TILE_SIZE * 0.34
	var glow := HOME_GLOW if team == MatchRules.Team.HOME else AWAY_GLOW
	var fill := HOME_FILL if team == MatchRules.Team.HOME else AWAY_FILL
	if role == "GK":
		fill = GK_HOME if team == MatchRules.Team.HOME else GK_AWAY

	if selected:
		draw_circle(Vector2.ZERO, radius + 10.0, Color(glow, 0.28))
		draw_arc(Vector2.ZERO, radius + 8.0, 0.0, TAU, 48, glow, 2.5, true)
	elif on_turn:
		draw_circle(Vector2.ZERO, radius + 7.0, Color(glow, 0.12))

	var outline := glow if (selected or on_turn) else glow.darkened(0.25)
	if role == "GK":
		_draw_shield(radius, fill, outline)
	else:
		_draw_hex(radius, fill, outline)

	draw_circle(Vector2.ZERO, radius * 0.46, FACE)
	if has_ball:
		draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 40, Color("f5e6a8"), 2.0, true)

	var chevron_dir := 1.0 if team == MatchRules.Team.HOME else -1.0
	var tip := Vector2(chevron_dir * (radius + 4.0), 0.0)
	var wing := Vector2(-chevron_dir * 5.0, 6.0)
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip + wing,
		tip + Vector2(-chevron_dir * 2.0, 0.0),
		tip + Vector2(wing.x, -wing.y),
	]), glow)


func _draw_hex(radius: float, fill: Color, outline: Color) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(-90.0 + float(i) * 60.0)
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, outline, 2.2, true)


func _draw_shield(radius: float, fill: Color, outline: Color) -> void:
	var pts := PackedVector2Array([
		Vector2(0, -radius),
		Vector2(radius * 0.78, -radius * 0.45),
		Vector2(radius * 0.72, radius * 0.25),
		Vector2(0, radius),
		Vector2(-radius * 0.72, radius * 0.25),
		Vector2(-radius * 0.78, -radius * 0.45),
	])
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, outline, 2.2, true)
