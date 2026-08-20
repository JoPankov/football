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
var stamina: int = 8
var energy: int = 8
var max_energy: int = 8


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
	stamina = int(stats.get("stamina", stamina))
	max_energy = MatchRules.max_energy(stamina)
	energy = max_energy


func live_accuracy() -> int:
	return MatchRules.scaled_stat(accuracy, energy, max_energy)


func live_defense() -> int:
	return MatchRules.scaled_stat(defense, energy, max_energy)


func live_control() -> int:
	return MatchRules.scaled_stat(control, energy, max_energy)


func energy_ratio() -> float:
	if max_energy <= 0:
		return 0.0
	return clampf(float(energy) / float(max_energy), 0.0, 1.0)


func spend_energy(cost: int = MatchRules.ACTION_ENERGY_COST) -> void:
	energy = maxi(0, energy - cost)


func label() -> String:
	return "%s #%d %s" % [MatchRules.team_name(team), number, role]


func stats_line() -> String:
	return "ACC %d   DEF %d   CTR %d   STA %d   NRG %d/%d" % [
		live_accuracy(), live_defense(), live_control(), stamina, energy, max_energy
	]
