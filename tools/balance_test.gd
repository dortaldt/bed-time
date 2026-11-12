extends SceneTree
## Headless balance test, like the prototype's test harness.
##
##   godot --headless --path . -s res://tools/balance_test.gd
##   godot --headless --path . -s res://tools/balance_test.gd -- --runs=32 --planner-runs=8
##
## Strategies:
##   default     Maya leaves at once on the living-room route, nothing else.
##   blind_both  Both kids leave at once, no peeks, no gear.
##   planner     Full information; searches plans and picks one with no warnings
##               (falling back to the fewest warnings), then plays it for real.

const T := preload("res://scripts/sim/tuning.gd")
const House := preload("res://scripts/sim/house.gd")
const Nights := preload("res://scripts/sim/nights.gd")
const Sim := preload("res://scripts/sim/simulation.gd")
const Predictor := preload("res://scripts/sim/predictor.gd")

var house


func _init() -> void:
	house = House.new()
	var runs := 16
	var planner_runs := 6
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):
			runs = int(arg.get_slice("=", 1))
		elif arg.begins_with("--planner-runs="):
			planner_runs = int(arg.get_slice("=", 1))
	print("Past Bedtime balance test (%d runs, planner %d runs)" % [runs, planner_runs])
	for idx in Nights.NAMES.size():
		print("\nNight %s" % Nights.NAMES[idx])
		for strat in ["default", "blind_both", "planner"]:
			var n := planner_runs if strat == "planner" else runs
			var hist := [0, 0, 0, 0]
			var no_safe := 0
			for i in n:
				var night := Nights.roll(idx, 1000 + i)
				var plan: Dictionary
				match strat:
					"default":
						plan = _base_plan()
					"blind_both":
						plan = _base_plan()
						plan["kids"]["ben"]["job"] = "run"
					_:
						var r := _plan_with_full_info(night)
						plan = r["plan"]
						if r["warnings"] > 0:
							no_safe += 1
				var sim = Sim.new(house, night, plan, {}, false)
				sim.run_to_end()
				hist[sim.stars()] += 1
			var line := "  %-11s 0*: %2d  1*: %2d  2*: %2d  3*: %2d" % [strat, hist[0], hist[1], hist[2], hist[3]]
			if strat == "planner":
				line += "   (no warning-free plan on %d/%d)" % [no_safe, n]
			print(line)
	quit()


func _base_plan() -> Dictionary:
	return {
		"kids": {
			"maya": {"job": "run", "leave": 0.0, "route": "living"},
			"ben": {"job": "bed", "leave": 0.0, "route": "living"},
		},
		"socks": "", "pillow": "", "lego": null, "cry": -1.0, "peeked": [],
	}


func _plan_with_full_info(night: Dictionary) -> Dictionary:
	var best_plan: Dictionary = {}
	var best_score := -INF
	var best_warn := 0
	var leaves := [0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0]
	var candidates: Array = []
	for route in ["living", "hall"]:
		for leave in leaves:
			for runner in ["maya", "ben"]:
				var p := _base_plan()
				p["kids"]["maya"]["job"] = "bed"
				p["kids"][runner] = {"job": "run", "leave": leave, "route": route}
				p["socks"] = runner
				p["pillow"] = runner
				candidates.append(p)
			for gear in [["maya", "ben"], ["ben", "maya"], ["maya", "maya"], ["ben", "ben"]]:
				var p := _base_plan()
				p["kids"]["maya"] = {"job": "run", "leave": leave, "route": route}
				p["kids"]["ben"] = {"job": "run", "leave": leave, "route": route}
				p["socks"] = gear[0]
				p["pillow"] = gear[1]
				candidates.append(p)
	for p in candidates:
		p["peeked"] = ["parents", "living", "kitchen"]
		var pred := Predictor.predict(house, night, p, {}, true)
		var nw: int = pred["warnings"].size()
		var sim = pred["sim"]
		var last := 0.0
		for tr in sim.trips:
			last = maxf(last, tr["home"])
		# Prefer: no warnings, then more cookies, then finishing early.
		var score: float = -nw * 1000.0 + sim.delivered * 100.0 - last * 0.1
		if score > best_score:
			best_score = score
			best_plan = p
			best_warn = nw
	return {"plan": best_plan, "warnings": best_warn}
