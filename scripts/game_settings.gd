class_name GameSettings
extends RefCounted

## Session options. Persisted to user:// so New Game does not wipe them.

const PATH := "user://settings.cfg"
const ANIM_SPEED_MIN := 1
const ANIM_SPEED_MAX := 10
const ANIM_SPEED_DEFAULT := 5

## When true, the third queued action does not lock the turn; End Turn does.
var require_end_turn: bool = false
## Resolution playback: 1 is slowest, 10 is fastest. 5 matches the original timing.
var animation_speed: int = ANIM_SPEED_DEFAULT


func anim_scale() -> float:
	return float(ANIM_SPEED_DEFAULT) / float(clampi(animation_speed, ANIM_SPEED_MIN, ANIM_SPEED_MAX))


func set_animation_speed(value: int) -> void:
	animation_speed = clampi(value, ANIM_SPEED_MIN, ANIM_SPEED_MAX)


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	require_end_turn = bool(cfg.get_value("game", "require_end_turn", false))
	set_animation_speed(int(cfg.get_value("game", "animation_speed", ANIM_SPEED_DEFAULT)))


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "require_end_turn", require_end_turn)
	cfg.set_value("game", "animation_speed", animation_speed)
	cfg.save(PATH)
