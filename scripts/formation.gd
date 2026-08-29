class_name Formation
extends RefCounted

## 4-4-2 kickoff on the 26×17 grid. Home attacks +x, away attacks −x.
## y=0 is the top touchline (home's left wing).
## Forwards and central mids sit 3 Chebyshev tiles apart around halfway.
## Receiving strikers stay in their own half, just outside the centre circle,
## so they cannot contest the first pass.
## When Helix kicks, both shapes are rotated 180° through the pitch centre.
## The extra length sits behind the back four; full-backs stay on the touchlines.


static func slots(team: int, kicking_team: int = MatchRules.Team.HOME) -> Array[Dictionary]:
	var kicking := team == kicking_team
	var shape := _home() if kicking else _away()
	if kicking_team == MatchRules.Team.HOME:
		return shape
	return _mirrored(shape)


static func _mirrored(source: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in source:
		var copy: Dictionary = slot.duplicate()
		copy.pos = MatchRules.mirror_cell(slot.pos)
		out.append(copy)
	return out


static func _home() -> Array[Dictionary]:
	var cy := MatchRules.CENTER_Y
	var st := MatchRules.CENTER_SPOT
	return [
		_slot(1, "GK", MatchRules.HOME_NET),
		_slot(2, "LB", Vector2i(2, 0)),
		_slot(3, "LCB", Vector2i(2, cy - 1)),
		_slot(4, "RCB", Vector2i(2, cy + 1)),
		_slot(5, "RB", Vector2i(2, MatchRules.GRID_HEIGHT - 1)),
		_slot(6, "LM", Vector2i(st.x - 3, 0)),
		_slot(7, "LCM", Vector2i(st.x - 3, cy - 1)),
		_slot(8, "RCM", Vector2i(st.x - 3, cy + 1)),
		_slot(11, "RM", Vector2i(st.x - 3, MatchRules.GRID_HEIGHT - 1)),
		_slot(10, "ST", Vector2i(st.x, cy - 1)),
		_slot(9, "ST", st),
	]


static func _away() -> Array[Dictionary]:
	var cy := MatchRules.CENTER_Y
	var last := MatchRules.GRID_WIDTH - 1
	return [
		_slot(1, "GK", MatchRules.AWAY_NET),
		_slot(2, "RB", Vector2i(last - 2, 0)),
		_slot(3, "RCB", Vector2i(last - 2, cy - 1)),
		_slot(4, "LCB", Vector2i(last - 2, cy + 1)),
		_slot(5, "LB", Vector2i(last - 2, MatchRules.GRID_HEIGHT - 1)),
		_slot(6, "RM", Vector2i(last - 9, 0)),
		_slot(7, "RCM", Vector2i(last - 8, cy - 1)),
		_slot(8, "LCM", Vector2i(last - 8, cy + 1)),
		_slot(11, "LM", Vector2i(last - 9, MatchRules.GRID_HEIGHT - 1)),
		_slot(10, "ST", Vector2i(MatchRules.HALFWAY_X + 1, cy - 3)),
		_slot(9, "ST", MatchRules.AWAY_KICKOFF),
	]


static func base_stats(role: String) -> Dictionary:
	match role:
		"GK":
			return _stats(10, 20, 20, 10)
		"LB", "RB":
			return _stats(10, 15, 15, 10)
		"LCB", "RCB":
			return _stats(10, 20, 20, 10)
		"LM", "RM":
			return _stats(15, 10, 10, 10)
		"LCM", "RCM":
			return _stats(10, 15, 15, 10)
		"ST":
			return _stats(20, 10, 15, 10)
		_:
			return _stats(10, 10, 10, 10)


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
