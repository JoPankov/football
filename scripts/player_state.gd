class_name PlayerState
extends RefCounted

var id: int
var team: int
var number: int
var role: String
var pos: Vector2i
var has_ball: bool = false
var accuracy: int = 8
var defense: int = 8
var control: int = 8


func _init(
	p_id: int = 0,
	p_team: int = MatchRules.Team.HOME,
	p_number: int = 1,
	p_role: String = "GK",
	p_pos: Vector2i = Vector2i.ZERO
) -> void:
	id = p_id
	team = p_team
	number = p_number
	role = p_role
	pos = p_pos


func apply_stats(stats: Dictionary) -> void:
	accuracy = int(stats.get("accuracy", accuracy))
	defense = int(stats.get("defense", defense))
	control = int(stats.get("control", control))


func label() -> String:
	return "%s #%d %s" % [MatchRules.team_name(team), number, role]


func stats_line() -> String:
	return "ACC %d   DEF %d   CTR %d" % [accuracy, defense, control]
