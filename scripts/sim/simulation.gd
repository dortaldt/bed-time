extends RefCounted
## Deterministic fixed-step (60 Hz) night simulation, kept separate from visuals so
## planning predictions and balance tests can run headless.
##
## predict = true runs the same rules as a "planner's dream": no noise, no catches,
## and only the errands the player knows about. It records bed checks and room
## conflicts instead of acting on them.

const T := preload("res://scripts/sim/tuning.gd")

var house
var night: Dictionary
var plan: Dictionary
var adapt: Dictionary
var predict := false
var early_end := true

var t := 0.0
var finished := false
var busted := false
var busted_reason := ""
var caught_kid := ""
var excuse_used := false
var delivered := 0

var kids := {}          # id -> state dict
var adults := {}        # id -> state dict
var events: Array = []  # {t, who, text}
var trips: Array = []   # {kid, leave, jar, home, result}
var checks: Array = []  # {t, out: [kid ids], decoyed: [kid ids]}
var conflicts: Array = []  # predict only: {t, kid, adult, room}
var errand_log: Array = []  # {who, type, start, arrive, back, dest}

var _schedule: Array = []
var _cry := {"time": -1.0, "started": false, "active": false, "next": 0.0, "end": 0.0}
var _conflict_keys := {}


func _init(p_house, p_night: Dictionary, p_plan: Dictionary, p_adapt: Dictionary = {}, p_predict: bool = false) -> void:
	house = p_house
	night = p_night
	plan = p_plan
	adapt = p_adapt
	predict = p_predict
	for id in ["maya", "ben"]:
		var spec: Dictionary = T.KIDS[id]
		var kp: Dictionary = plan["kids"][id]
		var bed: Vector2 = house.nodes[id + "_bed"]
		kids[id] = {
			"id": id, "spec": spec, "pos": bed, "dir": Vector2(0, 1),
			"bed_node": id + "_bed", "bed_pos": bed, "state": "bed",
			"path": PackedVector2Array(), "path_i": 0, "grab_t": 0.0,
			"reserve": 0, "carry": 0, "benched": false,
			"on_boards": {}, "trip": {},
			"job": kp["job"], "leave": float(kp["leave"]), "route": kp["route"],
			"socks": plan["socks"] == id, "pillow": plan["pillow"] == id,
		}
	var dad_node := "couch" if night["dad_spot"] == "couch" else "dad_bed"
	adults["mom"] = _make_adult("mom", T.MOM_SPEED, "mom_bed", float(night["mom_threshold"]))
	adults["dad"] = _make_adult("dad", T.DAD_SPEED, dad_node, float(night["dad_threshold"]))
	for e in night["errands"]:
		_schedule.append({"who": e["who"], "type": e["type"], "time": float(e["time"]), "fired": false})
	_cry["time"] = float(plan.get("cry", -1.0))


func _make_adult(id: String, speed: float, sleep_node: String, threshold: float) -> Dictionary:
	var p: Vector2 = house.nodes[sleep_node]
	return {
		"id": id, "speed": speed, "sleep_node": sleep_node, "sleep_pos": p, "pos": p,
		"dir": Vector2(0, 1), "asleep": true, "steps": [], "step_i": 0,
		"path": PackedVector2Array(), "path_i": 0, "wait_t": 0.0, "stun_t": 0.0,
		"meter": 0.0, "threshold": threshold, "base": threshold,
		"loudest_val": 0.0, "loudest_pos": p, "pending": [], "lego_hit": false,
		"errand": "", "rec": {},
	}


# --- Main loop -------------------------------------------------------------

func run_to_end() -> void:
	while not finished:
		step()


func step() -> void:
	if finished:
		return
	var dt := T.DT
	t += dt
	_fire_schedule()
	_update_cry()
	for k in kids.values():
		_step_kid(k, dt)
	for a in adults.values():
		_step_adult(a, dt)
	_check_catches()
	_check_end()


func stars() -> int:
	if busted or delivered <= 0:
		return 0
	if delivered >= T.COOKIES_GOAL:
		return 2 if excuse_used else 3
	return 1


func jar_node() -> String:
	return "fridge" if night["jar"] == "fridge" else "counter"


# --- Kids ------------------------------------------------------------------

func _step_kid(k: Dictionary, dt: float) -> void:
	match k["state"]:
		"bed":
			if _can_start_trip(k):
				_start_trip(k)
		"to_jar":
			var done := _move(k, k["spec"]["speed"], dt)
			_kid_noise(k, dt)
			if done:
				k["state"] = "grab"
				var fridge: bool = night["jar"] == "fridge"
				k["grab_t"] = k["spec"]["grab_fridge"] if fridge else k["spec"]["grab_counter"]
				k["trip"]["jar"] = t
				if fridge and k["id"] == "maya":
					_say(k["id"], "*drags a chair*")
		"grab":
			k["grab_t"] -= dt
			if k["grab_t"] <= 0.0:
				if night["jar"] == "fridge":
					_emit(k["spec"]["fridge_noise"], k["pos"])
				k["carry"] = k["reserve"]
				_say(k["id"], "Got %d!" % k["carry"] if k["carry"] > 1 else "Got one!")
				k["path"] = house.find_path(jar_node(), k["bed_node"], k["route"])
				k["path_i"] = 0
				k["state"] = "to_bed"
		"to_bed":
			var done := _move(k, k["spec"]["speed"], dt)
			_kid_noise(k, dt)
			if done:
				delivered += int(k["carry"])
				k["carry"] = 0
				k["reserve"] = 0
				k["state"] = "bed"
				k["trip"]["home"] = t
				k["trip"]["result"] = "home"
				k["on_boards"] = {}
				if delivered >= T.COOKIES_GOAL:
					_say(k["id"], "Mission complete!")
		"returning":
			if _move(k, k["spec"]["speed"], dt):
				k["state"] = "bed"
				k["pos"] = k["bed_pos"]


func _kid_exposed(k: Dictionary) -> bool:
	var s: String = k["state"]
	return s == "to_jar" or s == "grab" or s == "to_bed"


func _remaining() -> int:
	var r := T.COOKIES_GOAL - delivered
	for k in kids.values():
		if k["state"] != "bed":
			r -= int(k["reserve"])
	return r


func _can_start_trip(k: Dictionary) -> bool:
	return (k["job"] == "run" and not k["benched"] and t >= k["leave"]
		and t <= T.LAST_TRIP and _remaining() > 0)


func _start_trip(k: Dictionary) -> void:
	k["reserve"] = mini(int(k["spec"]["cap"]), _remaining())
	k["path"] = house.find_path(k["bed_node"], jar_node(), k["route"])
	k["path_i"] = 0
	k["state"] = "to_jar"
	k["on_boards"] = {}
	var trip := {"kid": k["id"], "leave": t, "jar": -1.0, "home": -1.0, "result": "out"}
	k["trip"] = trip
	trips.append(trip)
	_say(k["id"], "Tiptoe time..." if k["id"] == "maya" else "Cookie time!")


func _kid_noise(k: Dictionary, dt: float) -> void:
	if predict:
		return
	var rate: float = k["spec"]["walk_noise"]
	if house.room_at(k["pos"]) == "hall":
		rate *= float(k["spec"]["hall_mult"])
	_emit(rate * dt, k["pos"], true)
	var on: Dictionary = k["on_boards"]
	for b in night["boards"]:
		var near: bool = k["pos"].distance_to(b["pos"]) <= T.BOARD_RADIUS
		if near and not on.has(b["id"]):
			on[b["id"]] = true
			if k["socks"]:
				_emit(T.CREAK_SOCKS, b["pos"])
				_say(k["id"], "(sock-slide)")
			else:
				_emit(T.CREAK, b["pos"])
				_say(k["id"], "*CREEEAK*")
		elif not near and on.has(b["id"]):
			on.erase(b["id"])


# --- Grown-ups -------------------------------------------------------------

func _step_adult(a: Dictionary, dt: float) -> void:
	if a["asleep"]:
		if predict:
			return
		a["meter"] = maxf(0.0, a["meter"] - T.SLEEP_DRAIN * dt)
		a["loudest_val"] = maxf(0.0, a["loudest_val"] - 4.0 * dt)
		if a["meter"] > a["threshold"]:
			_wake(a)
		return
	if a["stun_t"] > 0.0:
		a["stun_t"] -= dt
		return
	_run_steps(a, dt)


func _wake(a: Dictionary) -> void:
	_start_errand(a, "investigate", a["loudest_pos"])
	_emit(T.WAKE_NOISE, a["pos"])


func _start_errand(a: Dictionary, type: String, data = null) -> void:
	if not a["asleep"]:
		a["pending"].append([type, data])
		return
	var nodes: Dictionary = house.nodes
	var steps: Array = []
	match type:
		"check":
			steps.append({"do": "walk", "to": nodes["kids_door"]})
			steps.append({"do": "check"})
		"water":
			steps.append({"do": "walk", "to": nodes["kit_mid"]})
			steps.append({"do": "wait", "t": T.WATER_TIME})
		"snack":
			steps.append({"do": "walk", "to": nodes["fridge"]})
			steps.append({"do": "wait", "t": T.SNACK_TIME})
		"bath":
			steps.append({"do": "walk", "to": nodes["toilet"]})
			steps.append({"do": "wait", "t": T.BATH_TIME})
		"settle":
			steps.append({"do": "walk", "to": nodes["crib"]})
			steps.append({"do": "wait", "t": T.SETTLE_TIME, "settle": true})
		"investigate":
			steps.append({"do": "walk", "to": data})
			steps.append({"do": "wait", "t": T.INVESTIGATE_TIME})
		_:
			return
	# After any time out of bed, Mom checks the kids' beds before going back to sleep.
	if a["id"] == "mom" and type != "check":
		steps.append({"do": "walk", "to": nodes["kids_door"]})
		steps.append({"do": "check"})
	steps.append({"do": "walk", "to": a["sleep_pos"]})
	steps.append({"do": "sleep"})
	a["asleep"] = false
	a["errand"] = type
	a["steps"] = steps
	a["step_i"] = 0
	var rec := {"who": a["id"], "type": type, "start": t, "arrive": -1.0, "back": -1.0, "dest": steps[0]["to"]}
	a["rec"] = rec
	errand_log.append(rec)
	var line: String = T.ERRAND_LINES.get(a["id"], {}).get(type, "")
	if line != "":
		_say(a["id"], line)


func _run_steps(a: Dictionary, dt: float) -> void:
	var steps: Array = a["steps"]
	if a["step_i"] >= steps.size():
		return
	var s: Dictionary = steps[a["step_i"]]
	match s["do"]:
		"walk":
			if not s.has("started"):
				s["started"] = true
				a["path"] = house.path_points(a["pos"], s["to"])
				a["path_i"] = 0
			var done := _move(a, a["speed"], dt)
			_check_lego(a)
			if done:
				if a["step_i"] == 0:
					a["rec"]["arrive"] = t
				a["step_i"] += 1
		"wait":
			if not s.has("started"):
				s["started"] = true
				a["wait_t"] = s["t"]
			a["wait_t"] -= dt
			if a["wait_t"] <= 0.0:
				if s.get("settle", false):
					_cry["active"] = false
					_say("mom", "Shhh... there, there.")
				a["step_i"] += 1
		"check":
			_bed_check(a)
			a["step_i"] += 1
		"sleep":
			_go_to_sleep(a)


func _go_to_sleep(a: Dictionary) -> void:
	a["rec"]["back"] = t
	a["asleep"] = true
	a["pos"] = a["sleep_pos"]
	a["errand"] = ""
	a["steps"] = []
	a["step_i"] = 0
	a["threshold"] += maxf(T.THRESH_RISE_MIN, T.THRESH_RISE_MULT * float(a["base"]))
	a["meter"] = 0.0
	a["loudest_val"] = 0.0
	var pending: Array = a["pending"]
	if not pending.is_empty():
		var p: Array = pending.pop_front()
		_start_errand(a, p[0], p[1])


func _check_lego(a: Dictionary) -> void:
	var lego = plan.get("lego")
	if lego == null or a["lego_hit"]:
		return
	if a["pos"].distance_to(lego) > T.LEGO_RADIUS:
		return
	a["lego_hit"] = true
	if adapt.get("slippers", false):
		_say(a["id"], "*crunch* Good thing I wore slippers.")
		return
	a["stun_t"] = T.LEGO_STUN
	_say(a["id"], "OWWW! LEGO!")
	_emit(T.LEGO_YELL, lego)


func _bed_check(a: Dictionary) -> void:
	var out: Array = []
	var decoyed: Array = []
	for k in kids.values():
		if not _kid_exposed(k):
			continue
		if k["pillow"]:
			decoyed.append(k["id"])
		else:
			out.append(k["id"])
	checks.append({"t": t, "out": out, "decoyed": decoyed})
	if out.is_empty():
		_say(a["id"], "Sleeping like angels.")
	if predict:
		return
	for id in out:
		if finished:
			return
		_catch(kids[id], a, "bed check")


# --- Noise, baby, schedule -------------------------------------------------

## Emit a sound. `continuous` = a per-step slice of an ongoing sound (walking).
func _emit(amount: float, pos: Vector2, continuous: bool = false) -> void:
	if predict:
		return
	for a in adults.values():
		if not a["asleep"]:
			continue
		var h: float = house.heard(amount, pos, a["pos"])
		a["meter"] += h
		var intensity := h / T.DT if continuous else h
		if intensity >= a["loudest_val"]:
			a["loudest_val"] = intensity
			a["loudest_pos"] = pos


func _update_cry() -> void:
	var ct: float = _cry["time"]
	if ct < 0.0:
		return
	if not _cry["started"]:
		if t < ct:
			return
		_cry["started"] = true
		_cry["active"] = true
		_cry["next"] = t + T.CRY_INTERVAL
		_say("noa", "WAAAAH!")
		_emit(T.CRY_FIRST, house.nodes["crib"])
		if adapt.get("ignore_cry", false):
			_cry["end"] = t + T.CRY_IGNORED_LEN
			_say("mom", "(sleeps right through it)")
		else:
			_cry["end"] = t + 40.0
			_start_errand(adults["mom"], "settle")
		return
	if _cry["active"]:
		if t >= _cry["end"]:
			_cry["active"] = false
		elif t >= _cry["next"]:
			_cry["next"] += T.CRY_INTERVAL
			_emit(T.CRY_REPEAT, house.nodes["crib"])


func crying() -> bool:
	return _cry["active"]


func _fire_schedule() -> void:
	for e in _schedule:
		if not e["fired"] and t >= e["time"]:
			e["fired"] = true
			_start_errand(adults[e["who"]], e["type"])


# --- Catching --------------------------------------------------------------

func _check_catches() -> void:
	for a in adults.values():
		if a["asleep"] or finished:
			continue
		var ar: String = house.room_at(a["pos"])
		for k in kids.values():
			if not _kid_exposed(k):
				continue
			var same: bool = ar == house.room_at(k["pos"])
			if predict:
				if same:
					var key := "%s|%s|%s" % [k["id"], a["id"], a["rec"]["start"]]
					if not _conflict_keys.has(key):
						_conflict_keys[key] = true
						conflicts.append({"t": t, "kid": k["id"], "adult": a["id"], "room": ar})
				continue
			var d: float = a["pos"].distance_to(k["pos"])
			if d <= (T.CATCH_ROOM if same else T.CATCH_NEAR):
				_catch(k, a, "spotted")
				if finished:
					return


func _catch(k: Dictionary, a: Dictionary, how: String) -> void:
	if not excuse_used:
		excuse_used = true
		var pair: Array = T.EXCUSES[int(t * 7.0) % T.EXCUSES.size()]
		_say(k["id"], pair[0])
		_say(a["id"], pair[1])
		events.append({"t": t, "who": "", "text": "Excuse card used: %s goes back to bed empty-handed." % T.NAMES[k["id"]]})
		k["carry"] = 0
		k["reserve"] = 0
		k["benched"] = true
		k["state"] = "returning"
		k["trip"]["home"] = t
		k["trip"]["result"] = "caught"
		k["path"] = house.path_points(k["pos"], k["bed_pos"])
		k["path_i"] = 0
		return
	busted = true
	finished = true
	caught_kid = k["id"]
	k["trip"]["home"] = t
	k["trip"]["result"] = "busted"
	busted_reason = "%s caught %s (%s)." % [T.NAMES[a["id"]], T.NAMES[k["id"]], how]
	_say(a["id"], "BED. NOW.")


func _check_end() -> void:
	if finished:
		return
	if t >= T.NIGHT_LEN:
		for k in kids.values():
			if _kid_exposed(k):
				busted = true
				caught_kid = k["id"]
				busted_reason = "%s was still out of bed at sunrise." % T.NAMES[k["id"]]
		finished = true
		return
	if not early_end:
		return
	for k in kids.values():
		if k["state"] != "bed":
			return
		if k["job"] == "run" and not k["benched"] and t <= T.LAST_TRIP and _remaining() > 0:
			return
	if predict:
		# Keep running until every known errand has played out (for the timeline).
		for a in adults.values():
			if not a["asleep"] or not a["pending"].is_empty():
				return
		for e in _schedule:
			if not e["fired"]:
				return
		if _cry["active"] or (_cry["time"] >= 0.0 and not _cry["started"]):
			return
	finished = true


# --- Helpers ---------------------------------------------------------------

## Move a character along its path. Returns true once the path is finished.
func _move(c: Dictionary, speed: float, dt: float) -> bool:
	var path: PackedVector2Array = c["path"]
	var budget := speed * dt
	while budget > 0.0 and c["path_i"] < path.size():
		var target: Vector2 = path[c["path_i"]]
		var pos: Vector2 = c["pos"]
		var d := pos.distance_to(target)
		if d > 0.0001:
			c["dir"] = (target - pos) / d
		if d <= budget:
			c["pos"] = target
			budget -= d
			c["path_i"] += 1
		else:
			c["pos"] = pos + (target - pos) / d * budget
			budget = 0.0
	return c["path_i"] >= path.size()


func _say(who: String, text: String) -> void:
	events.append({"t": t, "who": who, "text": text})
