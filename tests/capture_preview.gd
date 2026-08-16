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

	main.handle_cell_clicked(Vector2i(5, 3))
	main.hover_cell = Vector2i(6, 4)
	main.hud.refresh(main.model, main.model.player_at(Vector2i(5, 3)), main.model.player_at(Vector2i(6, 4)))
	await process_frame
	await process_frame
	_shot(out_dir.path_join("02_selected.png"))

	main.handle_cell_clicked(Vector2i(5, 4))
	await create_timer(0.35).timeout
	await process_frame
	_shot(out_dir.path_join("03_possession.png"))
	quit(0)


func _shot(path: String) -> void:
	var image: Image = root.get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("wrote %s (%s)" % [path, error_string(err)])
