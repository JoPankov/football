class_name CombatLog
extends RefCounted

## Sequential match log: plans, rolls, and resolution events.
## Plan lines stay private to the team that queued them. Resolution events are public.

const VIEWER_ALL := -1
const VIEWER_PUBLIC := -2

var entries: Array[Dictionary] = []


func clear() -> void:
	entries.clear()


func header(text: String) -> void:
	entries.append({kind = "header", text = text})


func note(text: String, team: int = -1) -> void:
	var entry := {kind = "note", text = text}
	if team >= 0:
		entry.hidden_from_opponent = true
		entry.team = team
	entries.append(entry)


func event(result: Dictionary) -> void:
	var text := format_result(result)
	if text == "":
		return
	var entry := {kind = "event", text = text, result = result}
	if str(result.get("action", "")) == "queue":
		entry.hidden_from_opponent = true
		var plan: Dictionary = result.get("plan", {})
		entry.team = int(result.get("team", plan.get("team", -1)))
	entries.append(entry)


func drop_last_queue(player_id: int) -> bool:
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		if str(entry.get("kind", "")) != "event":
			continue
		var result: Dictionary = entry.get("result", {})
		if str(result.get("action", "")) != "queue":
			continue
		if int(result.get("player_id", -1)) != player_id:
			continue
		entries.remove_at(i)
		return true
	return false


func as_text(viewer_team: int = VIEWER_ALL) -> String:
	var lines: PackedStringArray = []
	for entry in _visible_entries(viewer_team):
		lines.append(str(entry.get("text", "")))
	return "\n".join(lines)


func as_bbcode(viewer_team: int = VIEWER_ALL) -> String:
	var lines: PackedStringArray = []
	for entry in _visible_entries(viewer_team):
		var kind := str(entry.get("kind", "event"))
		var text := str(entry.get("text", "")).replace("[", "(").replace("]", ")")
		match kind:
			"header":
				lines.append("[color=#f0c14b][b]%s[/b][/color]" % text)
			"note":
				lines.append("[color=#9bb0c0]%s[/color]" % text)
			_:
				var color := "#d6e4ee"
				var raw := text
				if raw.begins_with("PLAN  AETHER") or raw.contains("AETHER") and not raw.contains("HELIX"):
					color = "#7dd8ff"
				if raw.begins_with("PLAN  HELIX") or (raw.contains("HELIX") and not raw.contains("AETHER")):
					color = "#ff8ab0"
				if raw.begins_with("CANCEL") or raw.begins_with("CLASH"):
					color = "#ffb347"
				if raw.begins_with("GOAL") or raw.begins_with("──"):
					color = "#ffe27a"
				if raw.begins_with("TACKLE") or raw.begins_with("DRIBBLE") or raw.begins_with("SQUARE") or raw.begins_with("INTERCEPT"):
					color = "#e8dcc8"
				lines.append("[color=%s]%s[/color]" % [color, text])
	return "\n".join(lines)


func _visible_entries(viewer_team: int) -> Array[Dictionary]:
	var visible: Array[Dictionary] = []
	for entry in entries:
		if not bool(entry.get("hidden_from_opponent", false)):
			visible.append(entry)
			continue
		if viewer_team == VIEWER_ALL:
			visible.append(entry)
			continue
		if viewer_team == VIEWER_PUBLIC:
			continue
		if int(entry.get("team", -1)) == viewer_team:
			visible.append(entry)
	return visible


static func cell_text(cell: Vector2i) -> String:
	return "(%d, %d)" % [cell.x, cell.y]


static func format_result(event: Dictionary) -> String:
	if event.is_empty() or not event.get("ok", false):
		return ""
	var action: String = event.get("action", "move")
	if action == "queue":
		return "PLAN  %s  %s" % [
			event.get("attacker_label", "player"),
			event.get("plan_text", event.get("label", "act")),
		]
	if action == "pop_plan":
		return "UNDO  %s  %s" % [
			event.get("attacker_label", "player"),
			event.get("plan_text", event.get("label", "act")),
		]
	if action == "cancelled":
		return "CANCEL  %s  %s — %s" % [
			event.get("attacker_label", "player"),
			event.get("label", "action"),
			event.get("reason_text", event.get("reason", "interrupted")),
		]
	if action == "clash":
		return "CLASH  %s CTR %s  vs  %s CTR %s  on %s  ·  %s takes the square" % [
			event.get("attacker_label", "a"),
			dice_text(event.get("attacker_stat", 0), event.get("attacker_dice", 0)),
			event.get("defender_label", "b"),
			dice_text(event.get("defender_stat", 0), event.get("defender_dice", 0)),
			cell_text(event.get("dest", Vector2i.ZERO)),
			event.get("winner_label", "winner"),
		]
	if event.get("in_flight", false):
		return ""
	if event.get("intercepted", false):
		return "INTERCEPT  %s %s %s  vs  %s %s %s" % [
			event.get("attacker_label", "passer"),
			event.get("attacker_stat_name", "ACC"),
			dice_text(event.get("attacker_stat", 0), event.get("attacker_dice", 0)),
			event.get("defender_label", "interceptor"),
			event.get("defender_stat_name", "DEF"),
			dice_text(event.get("defender_stat", 0), event.get("defender_dice", 0)),
		]
	if event.get("goal", false) and action != "shoot":
		return "GOAL  walked in  %d—%d" % [event.get("home_score", 0), event.get("away_score", 0)]
	if action == "shoot":
		if event.get("goal", false):
			return "GOAL  %s  %d—%d" % [
				event.get("attacker_label", "shooter"),
				event.get("home_score", 0),
				event.get("away_score", 0),
			]
		if event.get("saved", false):
			return "SAVE  %s's shot was held" % event.get("attacker_label", "shooter")
		return "MISS  %s's shot missed the net" % event.get("attacker_label", "shooter")
	if action == "offside":
		return "OFFSIDE  %s  →  %s takes the restart" % [
			event.get("defender_label", "receiver"),
			event.get("taker_label", "defender"),
		]
	if action == "pass":
		return "PASS  %s  →  %s" % [
			event.get("attacker_label", "passer"),
			event.get("defender_label", "receiver"),
		]
	if action == "swap":
		return "SWAP  %s  ⇄  %s" % [
			event.get("attacker_label", "mover"),
			event.get("defender_label", "teammate"),
		]
	if action == "turn":
		return "TURN  %s  faces %s" % [
			event.get("attacker_label", "player"),
			cell_text(event.get("dest", Vector2i.ZERO)),
		]
	if action == "move":
		return "MOVE  %s  →  %s" % [
			event.get("attacker_label", event.get("label", "player")),
			cell_text(event.get("dest", Vector2i.ZERO)),
		]
	if action == "sprint":
		return "SPRINT  %s  →  %s" % [
			event.get("attacker_label", event.get("label", "player")),
			cell_text(event.get("dest", Vector2i.ZERO)),
		]
	if action != "dribble" and action != "challenge" and action != "tackle":
		return ""
	var verb := "SQUARE FIGHT"
	if action == "dribble":
		verb = "DRIBBLE"
	elif action == "tackle":
		verb = "TACKLE"
	var outcome := "WON" if event.get("contest_won", false) else "LOST"
	if event.get("contest_tied", false) or event.get("bounced", false):
		outcome = "BOUNCE"
	var line := "%s %s  %s %s %s  vs  %s %s %s" % [
		verb,
		outcome,
		event.get("attacker_label", "attacker"),
		event.get("attacker_stat_name", "CTR"),
		dice_text(event.get("attacker_stat", 0), event.get("attacker_dice", 0)),
		event.get("defender_label", "defender"),
		event.get("defender_stat_name", "DEF"),
		dice_text(event.get("defender_stat", 0), event.get("defender_dice", 0)),
	]
	if event.get("bounced", false):
		line += "  →  %s" % cell_text(event.get("bounce_cell", event.get("dest", Vector2i.ZERO)))
	if action == "tackle" and event.has("angle_label"):
		var bonus := float(event.get("angle_bonus", 0.0))
		if bonus > 0.0:
			line += "  (%s +%d%%)" % [
				event.get("angle_label", "angle"),
				int(round(bonus * 100.0)),
			]
		else:
			line += "  (%s)" % event.get("angle_label", "front")
	return line


static func dice_text(stat: int, roll: int) -> String:
	return "1d%d=%d" % [stat, roll]


static func plan_summary(plan: Dictionary) -> String:
	var action := str(plan.get("action", "act"))
	var dest: Vector2i = plan.get("dest", Vector2i.ZERO)
	var cost := int(plan.get("ap_cost", MatchRules.DEFAULT_ACTION_COST))
	var core := ""
	match action:
		"pass":
			core = "pass → %s" % cell_text(dest)
		"shoot":
			var leftover := int(plan.get("ap_left", cost))
			var bonus := int(round(MatchRules.shot_ap_bonus(leftover) * 100.0))
			core = "shoot at %s (+%d%% ACC)" % [cell_text(dest), bonus]
		"swap":
			core = "swap → %s" % cell_text(dest)
		"dribble", "tackle", "challenge":
			core = "%s → %s" % [action, cell_text(dest)]
		"turn":
			core = "turn → %s" % cell_text(dest)
		"sprint":
			core = "sprint → %s" % cell_text(dest)
		"done":
			return "done"
		_:
			core = "move → %s" % cell_text(dest)
	return "%s  %d AP" % [core, cost]
