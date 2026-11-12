extends RefCounted
## Planning helpers: what the player knows, predicted trips/errands and warnings.
## Warnings only cover what the player has peeked at.

const T := preload("res://scripts/sim/tuning.gd")
const Sim := preload("res://scripts/sim/simulation.gd")


static func knowledge(night: Dictionary, peeked: Array) -> Dictionary:
	var dad_room := "parents" if night["dad_spot"] == "bed" else "living"
	var boards: Array = []
	for b in night["boards"]:
		if b["room"] == "hall" or peeked.has(b["room"]):
			boards.append(b)
	return {
		"mom": peeked.has("parents"),
		"dad": peeked.has(dad_room),
		"dad_room": dad_room,
		"boards": boards,
		"jar": peeked.has("kitchen"),
	}


## Runs a prediction sim with only known info. Returns {sim, warnings, know}.
static func predict(house, night: Dictionary, plan: Dictionary, adapt: Dictionary, early: bool = false) -> Dictionary:
	var know := knowledge(night, plan["peeked"])
	var n2: Dictionary = night.duplicate(true)
	var errs: Array = []
	for e in night["errands"]:
		if (e["who"] == "mom" and know["mom"]) or (e["who"] == "dad" and know["dad"]):
			errs.append(e)
	n2["errands"] = errs
	if not know["jar"]:
		n2["jar"] = "counter"
	var sim = Sim.new(house, n2, plan, adapt, true)
	sim.early_end = early
	sim.run_to_end()
	return {"sim": sim, "warnings": warnings(house, night, plan, know, sim), "know": know}


static func warnings(house, night: Dictionary, plan: Dictionary, know: Dictionary, sim) -> Array:
	var out: Array = []
	for c in sim.checks:
		for id in c["out"]:
			out.append("Mom checks the beds at %s while %s is out. A pillow decoy would cover it." % [T.fmt(c["t"]), T.NAMES[id]])
	for c in sim.conflicts:
		out.append("%s is in the %s at %s while %s is there." % [
			T.NAMES[c["adult"]], house.title(c["room"]), T.fmt(c["t"]), T.NAMES[c["kid"]]])
	var ben: Dictionary = plan["kids"]["ben"]
	if ben["job"] == "run" and ben["route"] == "living" and night["dad_spot"] == "couch" and know["dad"]:
		out.append("Ben stomps right past the couch where Dad is dozing. Try the hallway.")
	var jar := "fridge" if (know["jar"] and night["jar"] == "fridge") else "counter"
	for id in ["maya", "ben"]:
		var kp: Dictionary = plan["kids"][id]
		if kp["job"] != "run" or plan["socks"] == id:
			continue
		var path: PackedVector2Array = house.find_path(id + "_bed", jar, kp["route"])
		for b in know["boards"]:
			if house.dist_to_path(b["pos"], path) > 0.2:
				continue
			for who in ["mom", "dad"]:
				if not know[who]:
					continue
				var head: Vector2 = sim.adults[who]["sleep_pos"]
				var thr: float = night[who + "_threshold"]
				if house.heard(T.CREAK, b["pos"], head) >= 0.75 * thr:
					out.append("%s steps on a creaky board that could wake %s. Socks would silence it." % [T.NAMES[id], T.NAMES[who]])
	for tr in sim.trips:
		if tr["home"] < 0.0:
			out.append("%s won't be back in bed before morning." % T.NAMES[tr["kid"]])
	return out


## Human-readable intel lines for the planning panel.
static func intel(house, night: Dictionary, plan: Dictionary, adapt: Dictionary) -> Array:
	var know := knowledge(night, plan["peeked"])
	var lines: Array = []
	if know["mom"]:
		lines.append("Mom wakes at noise %d%s. %s" % [int(night["mom_threshold"]),
			" (light sleeper)" if night["mom_threshold"] <= 6.0 else "", _errands_text(night, "mom")])
	else:
		lines.append("Mom: ? Peek the parents' room.")
	if know["dad"]:
		var where := "dozing on the couch" if night["dad_spot"] == "couch" else "asleep in bed"
		lines.append("Dad is %s, wakes at noise %d. %s" % [where, int(night["dad_threshold"]), _errands_text(night, "dad")])
	elif plan["peeked"].has("parents") and night["dad_spot"] == "couch":
		lines.append("Dad's side of the bed is empty... Is he on the couch?")
	else:
		lines.append("Dad: ? Peek where he sleeps.")
	if know["jar"]:
		if night["jar"] == "fridge":
			lines.append("The jar is on top of the fridge: Maya needs a chair (slow, loud). Ben can reach it.")
		else:
			lines.append("The jar is on the counter: a quick grab.")
	else:
		lines.append("Jar: ? Peek the kitchen.")
	var nb: int = know["boards"].size()
	lines.append("Known creaky boards: %d (hidden ones lurk in dark rooms)." % nb if nb > 0 else "No known creaky boards.")
	if adapt.get("ignore_cry", false):
		lines.append("Mom has learned Noa's tricks: she'll ignore the next cry.")
	if adapt.get("slippers", false):
		lines.append("The grown-ups are wearing slippers now. LEGO won't stop anyone.")
	return lines


static func _errands_text(night: Dictionary, who: String) -> String:
	var parts: Array = []
	for e in night["errands"]:
		if e["who"] == who:
			parts.append("%s at %s" % [T.ERRAND_TEXT[e["type"]], T.fmt(e["time"])])
	if parts.is_empty():
		return "No errands tonight."
	return "Gets up: " + ", ".join(PackedStringArray(parts)) + "."
