class_name Formation
extends RefCounted

## 4-4-2 kickoff on the 18×9 grid. Home attacks +x, away attacks −x.
## y=0 is the top touchline (home's left wing).


static func slots(team: int) -> Array[Dictionary]:
	if team == MatchRules.Team.HOME:
		return _home()
	return _away()


static func _home() -> Array[Dictionary]:
	return [
		_slot(1, "GK", MatchRules.HOME_NET),
		_slot(2, "LB", Vector2i(2, 0)),
		_slot(3, "LCB", Vector2i(2, 3)),
		_slot(4, "RCB", Vector2i(2, 5)),
		_slot(5, "RB", Vector2i(2, 8)),
		_slot(6, "LM", Vector2i(5, 0)),
		_slot(7, "LCM", Vector2i(5, 3)),
		_slot(8, "RCM", Vector2i(5, 5)),
		_slot(11, "RM", Vector2i(5, 8)),
		_slot(10, "ST", Vector2i(8, 3)),
		_slot(9, "ST", MatchRules.CENTER_SPOT),
	]


static func _away() -> Array[Dictionary]:
	return [
		_slot(1, "GK", MatchRules.AWAY_NET),
		_slot(2, "RB", Vector2i(15, 0)),
		_slot(3, "RCB", Vector2i(15, 3)),
		_slot(4, "LCB", Vector2i(15, 5)),
		_slot(5, "LB", Vector2i(15, 8)),
		_slot(6, "RM", Vector2i(12, 0)),
		_slot(7, "RCM", Vector2i(12, 3)),
		_slot(8, "LCM", Vector2i(12, 5)),
		_slot(11, "LM", Vector2i(12, 8)),
		_slot(10, "ST", Vector2i(9, 3)),
		_slot(9, "ST", MatchRules.AWAY_KICKOFF),
	]


static func base_stats(role: String) -> Dictionary:
	match role:
		"GK":
			return _stats(8, 13, 11, 7)
		"LB", "RB":
			return _stats(10, 11, 8, 10)
		"LCB", "RCB":
			return _stats(8, 13, 7, 8)
		"LM", "RM":
			return _stats(16, 6, 9, 11)
		"LCM", "RCM":
			return _stats(12, 8, 7, 13)
		"ST":
			return _stats(26, 4, 9, 9)
		_:
			return _stats(16, 8, 8, 8)


static func _stats(accuracy: int, defense: int, control: int, stamina: int) -> Dictionary:
	return {accuracy = accuracy, defense = defense, control = control, stamina = stamina}


static func _slot(number: int, role: String, pos: Vector2i) -> Dictionary:
	var stats := base_stats(role)
	return {
		number = number,
		role = role,
		pos = pos,
		accuracy = stats.accuracy,
		defense = stats.defense,
		control = stats.control,
		stamina = stats.stamina,
	}
