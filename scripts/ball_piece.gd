class_name BallPiece
extends Node2D

const CORE := Color("f5e6a8")
const HIGHLIGHT := Color("fff6d4")
const GLOW := Color("d7b15a")

var carried: bool = false


func set_carried(value: bool) -> void:
	carried = value
	queue_redraw()


func _draw() -> void:
	var radius := 8.0 if carried else 10.0
	draw_circle(Vector2.ZERO, radius + 6.0, Color(GLOW, 0.28))
	draw_circle(Vector2.ZERO, radius, CORE)
	draw_circle(Vector2(-radius * 0.28, -radius * 0.28), radius * 0.28, HIGHLIGHT)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, Color.WHITE, 1.2, true)
