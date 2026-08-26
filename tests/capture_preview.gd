extends SceneTree

## Renders kickoff / selection / possession frames for visual checks.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := "/tmp/sci-fi-football"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	_shot(out_dir.path_join("01_kickoff.png"))

	main.handle_cell_clicked(MatchRules.CENTER_SPOT)
	main.select_command("move")
	main.hover_cell = MatchRules.AWAY_KICKOFF
	main.hud.refresh(main.model, main.model.player_at(MatchRules.CENTER_SPOT), main.model.player_at(MatchRules.AWAY_KICKOFF), main.hover_cell, main._pending_action)
	await process_frame
	await process_frame
	_shot(out_dir.path_join("02_selected.png"))

	main.handle_cell_clicked(Vector2i(8, 5))
	await create_timer(0.35).timeout
	await process_frame
	_shot(out_dir.path_join("03_possession.png"))
	quit(0)


func _shot(path: String) -> void:
	var image: Image = root.get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("wrote %s (%s)" % [path, error_string(err)])
