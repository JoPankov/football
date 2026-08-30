class_name BallState
extends RefCounted

var pos: Vector2i = MatchRules.CENTER_SPOT
var carrier_id: int = -1
## True while a pass or shot is still travelling between tiles.
var in_flight: bool = false
var flight_from: Vector2i = Vector2i.ZERO
var flight_to: Vector2i = Vector2i.ZERO
var flight_pos: Vector2 = Vector2.ZERO
var flight_passer_id: int = -1
var flight_accuracy: int = 0
var flight_action: String = "pass"
var flight_remaining_ap: int = 0


func is_loose() -> bool:
	return carrier_id < 0


func is_collectable() -> bool:
	return is_loose() and not in_flight


func clear_flight() -> void:
	in_flight = false
	flight_passer_id = -1
	flight_accuracy = 0
	flight_action = "pass"
	flight_remaining_ap = 0


func clone() -> BallState:
	var copy := BallState.new()
	copy.pos = pos
	copy.carrier_id = carrier_id
	copy.in_flight = in_flight
	copy.flight_from = flight_from
	copy.flight_to = flight_to
	copy.flight_pos = flight_pos
	copy.flight_passer_id = flight_passer_id
	copy.flight_accuracy = flight_accuracy
	copy.flight_action = flight_action
	copy.flight_remaining_ap = flight_remaining_ap
	return copy
