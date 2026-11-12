extends SceneTree
## Renders screenshots of the game through each phase. Needs a display (or Xvfb):
##   godot --path . --rendering-method gl_compatibility -s res://tools/screenshots.gd -- --out=/some/dir

const T := preload("res://scripts/sim/tuning.gd")

var out_dir := "user://screenshots"
var game


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _wait(frames: int = 4) -> void:
	for i in frames:
		await process_frame


func _shot(name: String) -> void:
	await _wait(6)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved ", path)


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	await _wait(4)

	# 1. Night 2 planning, nothing peeked yet.
	seed(4)
	game.start_night(1)
	game.select("maya")
	await _shot("01_plan_fog")

	# 2. Peek the parents' room and the kitchen; Maya on the hallway route.
	game.peek("parents")
	game.peek("kitchen")
	game.set_kid("maya", "route", "hall")
	game.set_kid("maya", "leave", 12.0)
	game.give("pillow", "maya")
	await _shot("02_plan_peeked_maya")

	# 3. Ben selected, LEGO dropped in the hallway.
	game.set_kid("ben", "job", "run")
	game.set_kid("ben", "leave", 30.0)
	game.set_kid("ben", "route", "hall")
	game.give("socks", "ben")
	game.set_lego(game.house.snap_to_walkway(Vector2(8.0, 4.8)))
	game.select("ben")
	await _shot("03_plan_ben_lego")

	# 4. Lights out: run the night until something is happening.
	game.lights_out()
	while not game.sim.finished and game.sim.t < 70.0:
		game.sim.step()
		var awake := false
		for a in game.sim.adults.values():
			if not a["asleep"]:
				awake = true
		var out := false
		for k in game.sim.kids.values():
			if k["state"] != "bed":
				out = true
		if awake and out and game.sim.t > 8.0:
			break
	game.speed = 0.0
	await _wait(3)
	await _shot("04_night_action")

	# 5. Finish the night and show the result.
	game.speed = 1.0
	game.skip_night()
	await _wait(150)
	await _shot("05_result")

	# 6. Night 3 with the living room peeked, Noa crying.
	seed(11)
	game.start_night(2)
	game.peek("living")
	game.peek("parents")
	game.set_cry(20.0)
	game.select("noa")
	await _shot("06_plan_night3_noa")
	quit()
