extends RefCounted
## Night definitions. Every attempt re-rolls times, Dad's spot, jar and boards from a seed,
## so peeking always matters.

const NAMES := ["1: The cookie jar", "2: Dad's movie night", "3: The light sleeper", "Bonus: Wild card"]

# Creaky boards only sit on route-specific walkways, so picking a route
# also means picking which boards to cross.
const HALL_BOARDS := [Vector2(7.5, 4.75), Vector2(9.25, 4.75)]     # hallway route only
const LIVING_BOARDS := [Vector2(6.85, 6.8), Vector2(7.85, 6.9)]    # living room route only
const KITCHEN_BOARDS := [Vector2(10.6, 6.25), Vector2(9.8, 6.6)]   # [hallway entry, living-room entry]

const ERRAND_POOL := [["mom", "check"], ["mom", "water"], ["dad", "snack"], ["dad", "bath"]]


static func roll(index: int, seed_val: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var n := {
		"index": index, "name": NAMES[index], "seed": seed_val,
		"mom_threshold": 12.0, "dad_spot": "bed", "dad_threshold": 20.0,
		"jar": "counter", "boards": [], "errands": [],
	}
	match index:
		0:
			n["mom_threshold"] = 12.0
			n["dad_spot"] = "bed"
			n["dad_threshold"] = 20.0
			n["jar"] = "counter"
			_errand(n, "mom", "check", rng.randf_range(8.0, 22.0))
		1:
			n["mom_threshold"] = 9.0
			if rng.randf() < 0.8:
				n["dad_spot"] = "couch"
				n["dad_threshold"] = 7.0
			else:
				n["dad_spot"] = "bed"
				n["dad_threshold"] = 16.0
			n["jar"] = "fridge"
			_board(n, _pick(rng, HALL_BOARDS), "hall")
			if rng.randf() < 0.5:
				_board(n, _pick(rng, LIVING_BOARDS), "living")
			else:
				_board(n, _pick(rng, KITCHEN_BOARDS), "kitchen")
			_errand(n, "dad", "snack" if rng.randf() < 0.5 else "bath", rng.randf_range(10.0, 50.0))
			if rng.randf() < 0.7:
				_errand(n, "mom", "check", rng.randf_range(6.0, 50.0))
		2:
			n["mom_threshold"] = 4.0
			if rng.randf() < 0.6:
				n["dad_spot"] = "couch"
				n["dad_threshold"] = 8.0
			else:
				n["dad_spot"] = "bed"
				n["dad_threshold"] = 14.0
			n["jar"] = "counter" if rng.randf() < 0.5 else "fridge"
			var hall_i := rng.randi_range(0, HALL_BOARDS.size() - 1)
			var liv_i := rng.randi_range(0, LIVING_BOARDS.size() - 1)
			_board(n, HALL_BOARDS[hall_i], "hall")
			_board(n, LIVING_BOARDS[liv_i], "living")
			var rest: Array = []
			for i in HALL_BOARDS.size():
				if i != hall_i:
					rest.append([HALL_BOARDS[i], "hall"])
			for i in LIVING_BOARDS.size():
				if i != liv_i:
					rest.append([LIVING_BOARDS[i], "living"])
			for b in KITCHEN_BOARDS:
				rest.append([b, "kitchen"])
			var extra: Array = rest[rng.randi_range(0, rest.size() - 1)]
			_board(n, extra[0], extra[1])
			_errand(n, "mom", "check", rng.randf_range(6.0, 20.0))
			_errand(n, "mom", "water", rng.randf_range(34.0, 54.0))
			_errand(n, "dad", "snack" if rng.randf() < 0.5 else "bath", rng.randf_range(10.0, 50.0))
		_:
			n["mom_threshold"] = snappedf(rng.randf_range(4.0, 11.0), 0.5)
			if rng.randf() < 0.5:
				n["dad_spot"] = "couch"
				n["dad_threshold"] = snappedf(rng.randf_range(6.0, 10.0), 0.5)
			else:
				n["dad_spot"] = "bed"
				n["dad_threshold"] = snappedf(rng.randf_range(12.0, 20.0), 0.5)
			n["jar"] = "counter" if rng.randf() < 0.5 else "fridge"
			var all: Array = []
			for b in HALL_BOARDS:
				all.append([b, "hall"])
			for b in LIVING_BOARDS:
				all.append([b, "living"])
			for b in KITCHEN_BOARDS:
				all.append([b, "kitchen"])
			_shuffle(rng, all)
			for i in rng.randi_range(2, 3):
				_board(n, all[i][0], all[i][1])
			var pool := ERRAND_POOL.duplicate()
			_shuffle(rng, pool)
			for i in rng.randi_range(2, 3):
				_errand(n, pool[i][0], pool[i][1], rng.randf_range(6.0, 55.0))
	n["errands"].sort_custom(func(a, b): return a["time"] < b["time"])
	return n


static func _errand(n: Dictionary, who: String, type: String, time: float) -> void:
	n["errands"].append({"who": who, "type": type, "time": snappedf(time, 0.1)})


static func _board(n: Dictionary, pos: Vector2, room: String) -> void:
	n["boards"].append({"id": n["boards"].size(), "pos": pos, "room": room})


static func _pick(rng: RandomNumberGenerator, arr: Array):
	return arr[rng.randi_range(0, arr.size() - 1)]


static func _shuffle(rng: RandomNumberGenerator, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
