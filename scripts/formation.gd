class_name Formation
extends RefCounted

## 4-4-2 kickoff on the 12×7 grid. Home attacks +x, away attacks −x.
## y=0 is the top touchline (home's left wing).


static func slots(team: int) -> Array[Dictionary]:
	if team == MatchRules.Team.HOME:
		return _home()
	return _away()


static func _home() -> Array[Dictionary]:
	return [
		_slot(1, "GK", Vector2i(0, 3)),
		_slot(2, "LB", Vector2i(2, 0)),
		_slot(3, "LCB", Vector2i(2, 2)),
		_slot(4, "RCB", Vector2i(2, 4)),
		_slot(5, "RB", Vector2i(2, 6)),
		_slot(6, "LM", Vector2i(4, 0)),
		_slot(7, "LCM", Vector2i(4, 2)),
		_slot(8, "RCM", Vector2i(4, 4)),
		_slot(11, "RM", Vector2i(4, 6)),
		_slot(10, "ST", Vector2i(5, 2)),
		_slot(9, "ST", Vector2i(5, 3)),
	]


static func _away() -> Array[Dictionary]:
	return [
		_slot(1, "GK", Vector2i(11, 3)),
		_slot(2, "RB", Vector2i(9, 0)),
		_slot(3, "RCB", Vector2i(9, 2)),
		_slot(4, "LCB", Vector2i(9, 4)),
		_slot(5, "LB", Vector2i(9, 6)),
		_slot(6, "RM", Vector2i(7, 0)),
		_slot(7, "RCM", Vector2i(7, 2)),
		_slot(8, "LCM", Vector2i(7, 4)),
		_slot(11, "LM", Vector2i(7, 6)),
		_slot(10, "ST", Vector2i(6, 2)),
		_slot(9, "ST", Vector2i(6, 4)),
	]


static func base_stats(role: String) -> Dictionary:
	match role:
		"GK":
			return _stats(4, 6, 13, 11)
		"LB", "RB":
			return _stats(5, 7, 11, 8)
		"LCB", "RCB":
			return _stats(4, 6, 13, 7)
		"LM", "RM":
			return _stats(8, 10, 6, 9)
		"LCM", "RCM":
			return _stats(6, 12, 8, 7)
		"ST":
			return _stats(13, 6, 4, 9)
		_:
			return _stats(8, 8, 8, 8)


static func _stats(accuracy: int, passing: int, defense: int, control: int) -> Dictionary:
	return {accuracy = accuracy, passing = passing, defense = defense, control = control}


static func _slot(number: int, role: String, pos: Vector2i) -> Dictionary:
	var stats := base_stats(role)
	return {
		number = number,
		role = role,
		pos = pos,
		accuracy = stats.accuracy,
		passing = stats.passing,
		defense = stats.defense,
		control = stats.control,
	}
