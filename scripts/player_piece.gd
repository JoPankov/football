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
var planned: bool = false
var finished: bool = false
var energy_ratio: float = 1.0
var ap_left: int = -1
var ap_max: int = MatchRules.PLAYER_ACTION_POINTS
var facing: Vector2i = Vector2i(1, 0)

@onready var _number_label: Label = $Number
@onready var _role_label: Label = $Role


func configure(state: PlayerState) -> void:
	player_id = state.id
	team = state.team
	number = state.number
	role = state.role
	has_ball = state.has_ball
	set_facing(state.facing)
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


func set_planned(value: bool) -> void:
	planned = value
	queue_redraw()


func set_finished(value: bool) -> void:
	if finished == value:
		return
	finished = value
	queue_redraw()


func set_ap_left(remaining: int, maximum: int = MatchRules.PLAYER_ACTION_POINTS) -> void:
	if ap_left == remaining and ap_max == maximum:
		return
	ap_left = remaining
	ap_max = maxi(1, maximum)
	queue_redraw()


func set_energy_ratio(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if is_equal_approx(energy_ratio, next):
		return
	energy_ratio = next
	queue_redraw()


func set_facing(value: Vector2i) -> void:
	var next := MatchRules.normalize_facing(value)
	if next == Vector2i.ZERO:
		next = MatchRules.kickoff_facing(team)
	if facing == next:
		return
	facing = next
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
	elif planned:
		var ring := Color("6dff8a") if finished else Color("ffe27a")
		draw_circle(Vector2.ZERO, radius + 8.0, Color(glow, 0.2))
		draw_arc(Vector2.ZERO, radius + 7.0, 0.0, TAU, 48, ring, 2.2, true)
	elif on_turn:
		draw_circle(Vector2.ZERO, radius + 7.0, Color(glow, 0.12))

	var outline := glow if (selected or on_turn) else glow.darkened(0.25)
	draw_circle(Vector2.ZERO, radius, fill)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, outline, 2.6, true)
	if role == "GK":
		draw_arc(Vector2.ZERO, radius * 0.78, 0.0, TAU, 40, outline, 1.7, true)

	draw_circle(Vector2.ZERO, radius * 0.46, FACE)
	if has_ball:
		draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 40, Color("f5e6a8"), 2.0, true)

	_draw_energy_bar(radius)
	_draw_ap_pips(radius)
	_draw_facing(radius, glow)
	if finished:
		_draw_done_badge(radius)


func _draw_energy_bar(radius: float) -> void:
	var bar_w := radius * 1.7
	var bar_h := 3.5
	var origin := Vector2(-bar_w * 0.5, radius + 8.0)
	draw_rect(Rect2(origin, Vector2(bar_w, bar_h)), Color(0.02, 0.04, 0.06, 0.75))
	var fill := Color("6dff8a")
	if energy_ratio <= 0.001:
		fill = Color("ff4d5a")
	elif energy_ratio <= 0.34:
		fill = Color("ff6b4d")
	elif energy_ratio <= 0.67:
		fill = Color("ffd15a")
	draw_rect(Rect2(origin, Vector2(bar_w * energy_ratio, bar_h)), fill)
	draw_rect(Rect2(origin, Vector2(bar_w, bar_h)), Color(1, 1, 1, 0.22), false, 1.0)


func _draw_ap_pips(radius: float) -> void:
	if ap_left < 0 or ap_left >= ap_max:
		return
	var count := ap_max
	for i in count:
		var t := (float(i) + 0.5) / float(count)
		var ang := PI + t * PI
		var pos := Vector2(cos(ang), sin(ang)) * (radius + 9.0)
		if i < ap_left:
			draw_circle(pos, 2.7, Color("ffe27a"))
		else:
			draw_circle(pos, 2.4, Color(0.04, 0.06, 0.08, 0.85))
			draw_arc(pos, 2.4, 0.0, TAU, 12, Color(1, 1, 1, 0.28), 1.0, true)


func _draw_done_badge(radius: float) -> void:
	var pos := Vector2(radius * 0.78, -radius * 0.78)
	draw_circle(pos, 7.2, Color("0b2418"))
	draw_arc(pos, 7.2, 0.0, TAU, 24, Color("6dff8a"), 1.7, true)
	var a := pos + Vector2(-3.1, 0.3)
	var b := pos + Vector2(-0.7, 3.1)
	var c := pos + Vector2(3.7, -2.9)
	draw_line(a, b, Color("6dff8a"), 1.8, true)
	draw_line(b, c, Color("6dff8a"), 1.8, true)


func _draw_facing(radius: float, glow: Color) -> void:
	var dir := Vector2(facing)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT if team == MatchRules.Team.HOME else Vector2.LEFT
	dir = dir.normalized()
	var ortho := dir.orthogonal()
	var tip := dir * (radius + 12.0)
	var base := dir * (radius - 8.0)
	var wing := 9.5
	var outer := PackedVector2Array([
		tip + dir * 1.5,
		base + ortho * (wing + 1.6),
		base - ortho * (wing + 1.6),
	])
	var inner := PackedVector2Array([
		tip,
		base + dir * 1.5 + ortho * wing,
		base + dir * 1.5 - ortho * wing,
	])
	draw_colored_polygon(outer, Color("071018"))
	draw_colored_polygon(inner, Color("fff4b0"))
	var accent := PackedVector2Array([
		tip - dir * 3.0,
		base + dir * 3.5 + ortho * (wing * 0.45),
		base + dir * 3.5 - ortho * (wing * 0.45),
	])
	draw_colored_polygon(accent, glow.lightened(0.15))
