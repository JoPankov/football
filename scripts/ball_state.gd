class_name BallState
extends RefCounted

var pos: Vector2i = MatchRules.CENTER_SPOT
var carrier_id: int = -1


func is_loose() -> bool:
	return carrier_id < 0
