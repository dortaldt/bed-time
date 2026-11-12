extends Node3D
## Block-art view of the house. Everything is a placeholder BoxMesh, meant to be
## swapped for real assets later. Reads simulation state; never changes it.

const T := preload("res://scripts/sim/tuning.gd")
const House := preload("res://scripts/sim/house.gd")

const FLOOR_COLORS := {
	"kids": Color(0.25, 0.3, 0.5), "nursery": Color(0.29, 0.33, 0.52),
	"parents": Color(0.24, 0.26, 0.44), "hall": Color(0.2, 0.24, 0.38),
	"bath": Color(0.3, 0.42, 0.52), "living": Color(0.26, 0.29, 0.46),
	"kitchen": Color(0.32, 0.37, 0.5),
}
const WALL_COLOR := Color(0.62, 0.66, 0.82)
const SKIN := Color(1.0, 0.85, 0.72)

var house
var _mats := {}
var fog := {}             # room -> Node3D
var lights := {}          # room -> OmniLight3D
var actors := {}          # id -> {root, pivot, bubble, bubble_t, scale}
var boards: Array = []    # {node, room}
var decoys := {}          # kid id -> MeshInstance3D
var dynamic: Node3D
var overlay: Node3D
var jar_node: MeshInstance3D
var lego_node: MeshInstance3D
var tv_screen: MeshInstance3D
var tv_light: OmniLight3D
var tv_on := false
var dad_on_couch := false
var _time := 0.0
var _lights_all := false


func build(h) -> void:
	house = h
	_build_ground()
	_build_floors()
	_build_walls()
	_build_furniture()
	_build_lights()
	dynamic = Node3D.new()
	add_child(dynamic)
	overlay = Node3D.new()
	add_child(overlay)
	for id in ["maya", "ben", "noa", "mom", "dad"]:
		_make_actor(id)
	for id in ["maya", "ben"]:
		var bed: Vector2 = house.nodes[id + "_bed"]
		var d := block(self, bed.x - 0.28, bed.y - 0.45, bed.x + 0.28, bed.y + 0.55, 0.22, T.COLORS[id].darkened(0.25), 0.36)
		d.visible = false
		decoys[id] = d
	lego_node = box(self, Vector3(0.22, 0.1, 0.16), Vector3.ZERO, Color(0.95, 0.15, 0.15), 0.6)
	lego_node.visible = false


# --- Primitives ------------------------------------------------------------

func _mat(c: Color, glow: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%s" % [c.to_html(), glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m


func box(parent: Node, size: Vector3, center: Vector3, c: Color, glow: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c, glow)
	mi.position = center
	parent.add_child(mi)
	return mi


## Axis-aligned block on the floor plan: x0..x1, z0..z1, height h starting at y0.
func block(parent: Node, x0: float, z0: float, x1: float, z1: float, h: float, c: Color, y0: float = 0.0, glow: float = 0.0) -> MeshInstance3D:
	return box(parent, Vector3(x1 - x0, h, z1 - z0), Vector3((x0 + x1) * 0.5, y0 + h * 0.5, (z0 + z1) * 0.5), c, glow)


func label3d(parent: Node, text: String, pos: Vector3, size: int = 40, col: Color = Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.font_size = size
	l.pixel_size = 0.006
	l.outline_size = 12
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.position = pos
	l.render_priority = 10
	l.outline_render_priority = 9
	parent.add_child(l)
	return l


# --- Static house ----------------------------------------------------------

func _build_ground() -> void:
	block(self, -4, -4, 16, 13, 0.1, Color(0.09, 0.16, 0.14), -0.25)
	# A few garden shrubs and a path, just to frame the lot.
	for p in [Vector2(-1.2, 2), Vector2(-1.5, 6.5), Vector2(13.2, 3), Vector2(13.5, 7.5), Vector2(3, 10.5), Vector2(9, 10.8)]:
		block(self, p.x - 0.5, p.y - 0.5, p.x + 0.5, p.y + 0.5, 0.6, Color(0.12, 0.25, 0.18), -0.15)
	block(self, 5.8, 9.1, 7.2, 12.5, 0.04, Color(0.3, 0.32, 0.38), -0.15)


func _build_floors() -> void:
	for r in House.ROOM_ORDER:
		var rect: Rect2 = house.rooms[r]
		block(self, rect.position.x, rect.position.y, rect.end.x, rect.end.y, 0.1, FLOOR_COLORS[r], -0.1)


func _build_walls() -> void:
	for w in house.walls:
		var a: Vector2 = w["a"]
		var b: Vector2 = w["b"]
		var horizontal := absf(a.y - b.y) < 0.001
		var start := a.x if horizontal else a.y
		var stop := b.x if horizontal else b.y
		var segs: Array = []
		var cur := start
		for d in w["doors"]:
			segs.append([cur, float(d) - 0.45])
			cur = float(d) + 0.45
		segs.append([cur, stop])
		var h := 2.4 if w["tall"] else 0.4
		for s in segs:
			if s[1] - s[0] < 0.01:
				continue
			if horizontal:
				block(self, s[0], a.y - 0.06, s[1], a.y + 0.06, h, WALL_COLOR)
			else:
				block(self, a.x - 0.06, s[0], a.x + 0.06, s[1], h, WALL_COLOR)


func _build_furniture() -> void:
	# Kids' room
	for id in ["maya", "ben"]:
		var x: float = house.nodes[id + "_bed"].x
		block(self, x - 0.45, 0.2, x + 0.45, 2.4, 0.3, Color(0.42, 0.31, 0.23))
		block(self, x - 0.4, 0.75, x + 0.4, 2.35, 0.06, T.COLORS[id].darkened(0.35), 0.3)
		block(self, x - 0.35, 0.25, x + 0.35, 0.65, 0.1, Color(0.92, 0.92, 0.96), 0.3)
	block(self, 1.85, 0.05, 2.15, 0.25, 0.22, Color(1.0, 0.85, 0.4), 0.0, 2.0)  # nightlight
	block(self, 1.4, 2.7, 2.6, 3.4, 0.02, Color(0.55, 0.35, 0.55))
	# Nursery
	block(self, 4.95, 1.3, 6.05, 2.7, 0.1, Color(0.9, 0.9, 0.95), 0.3)
	block(self, 4.95, 1.3, 5.05, 2.7, 0.7, Color(0.95, 0.95, 1.0))
	block(self, 5.95, 1.3, 6.05, 2.7, 0.7, Color(0.95, 0.95, 1.0))
	block(self, 4.3, 0.2, 4.9, 0.6, 0.6, Color(0.6, 0.5, 0.7))
	# Parents' room
	block(self, 8.7, 0.1, 11.5, 2.6, 0.35, Color(0.35, 0.27, 0.21))
	block(self, 8.75, 0.95, 11.45, 2.55, 0.06, Color(0.48, 0.4, 0.66), 0.35)
	block(self, 8.9, 0.2, 9.9, 0.6, 0.12, Color(0.92, 0.92, 0.96), 0.35)
	block(self, 10.3, 0.2, 11.3, 0.6, 0.12, Color(0.92, 0.92, 0.96), 0.35)
	block(self, 11.6, 0.1, 11.95, 0.5, 0.5, Color(0.4, 0.3, 0.22))
	block(self, 11.68, 0.2, 11.88, 0.4, 0.3, Color(1.0, 0.9, 0.6), 0.5, 1.0)
	# Hallway
	block(self, 0.4, 4.5, 11.6, 5.0, 0.02, Color(0.45, 0.22, 0.25))
	# Bathroom
	block(self, 0.1, 5.65, 0.95, 7.4, 0.5, Color(0.9, 0.93, 0.97))
	block(self, 0.6, 8.3, 1.3, 8.9, 0.45, Color(0.95, 0.95, 0.97))
	block(self, 1.9, 8.55, 2.7, 8.95, 0.8, Color(0.85, 0.89, 0.94))
	# Living room
	block(self, 3.6, 8.15, 5.6, 8.9, 0.4, Color(0.55, 0.3, 0.3))
	block(self, 3.6, 8.7, 5.6, 8.95, 0.85, Color(0.5, 0.27, 0.27))
	block(self, 3.8, 5.6, 5.4, 5.95, 0.45, Color(0.15, 0.15, 0.18))
	tv_screen = block(self, 3.9, 5.65, 5.3, 5.75, 0.75, Color(0.15, 0.2, 0.3), 0.45)
	block(self, 3.6, 6.6, 4.4, 7.2, 0.35, Color(0.45, 0.33, 0.24))
	block(self, 8.45, 8.4, 8.75, 8.7, 1.3, Color(0.3, 0.25, 0.2))
	block(self, 8.4, 8.35, 8.8, 8.75, 0.25, Color(1.0, 0.85, 0.55), 1.3, 0.8)
	# Kitchen
	block(self, 11.45, 5.6, 11.95, 7.6, 0.9, Color(0.72, 0.62, 0.48))
	block(self, 9.85, 8.45, 10.95, 8.95, 1.9, Color(0.86, 0.9, 0.94))
	block(self, 11.0, 8.0, 11.7, 8.8, 0.7, Color(0.5, 0.38, 0.28))
	block(self, 10.75, 8.1, 10.95, 8.7, 0.45, Color(0.45, 0.33, 0.24))


func _build_lights() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.04, 0.1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.42, 0.75)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_energy = 0.55
	moon.shadow_enabled = true
	moon.rotation_degrees = Vector3(-55, -30, 0)
	add_child(moon)
	# Star field: tiny glowing dots far behind the house.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 70:
		var p := Vector3(rng.randf_range(-30, 20), rng.randf_range(-8, 12), rng.randf_range(-30, 0))
		if p.x > -2 and p.z > -4:
			continue
		box(self, Vector3.ONE * 0.12, p, Color(1, 1, 0.9), 3.0)
	for r in House.ROOM_ORDER:
		var rect: Rect2 = house.rooms[r]
		var l := OmniLight3D.new()
		l.position = Vector3(rect.get_center().x, 2.0, rect.get_center().y)
		l.omni_range = maxf(rect.size.x, rect.size.y) * 0.9 + 1.0
		l.light_color = Color(1.0, 0.82, 0.55)
		l.light_energy = 0.0
		add_child(l)
		lights[r] = l
	var night_light := OmniLight3D.new()
	night_light.position = Vector3(2.0, 0.5, 0.5)
	night_light.omni_range = 2.5
	night_light.light_color = Color(1.0, 0.85, 0.4)
	night_light.light_energy = 0.6
	add_child(night_light)
	tv_light = OmniLight3D.new()
	tv_light.position = Vector3(4.6, 1.0, 6.4)
	tv_light.omni_range = 4.0
	tv_light.light_color = Color(0.5, 0.7, 1.0)
	tv_light.light_energy = 0.0
	add_child(tv_light)


# --- Actors ----------------------------------------------------------------

func _make_actor(id: String) -> void:
	var col: Color = T.COLORS[id]
	var s := 1.0
	if id == "maya" or id == "ben":
		s = 0.72
	elif id == "noa":
		s = 0.45
	var root := Node3D.new()
	add_child(root)
	var pivot := Node3D.new()
	root.add_child(pivot)
	box(pivot, Vector3(0.42, 0.62, 0.3) * s, Vector3(0, 0.31 * s, 0), col)
	box(pivot, Vector3(0.34, 0.34, 0.34) * s, Vector3(0, 0.8 * s, 0), SKIN)
	box(pivot, Vector3(0.36, 0.12, 0.36) * s, Vector3(0, 1.0 * s, 0), col.lightened(0.35))  # nightcap
	box(pivot, Vector3(0.16, 0.16, 0.16) * s, Vector3(0.1 * s, 1.12 * s, 0), col.lightened(0.6))
	box(pivot, Vector3(0.08, 0.06, 0.04) * s, Vector3(0, 0.82 * s, 0.18 * s), Color(0.15, 0.1, 0.1))  # face
	var bubble := label3d(root, "", Vector3(0, 1.35 * s + 0.35, 0), 44)
	bubble.visible = false
	actors[id] = {"root": root, "pivot": pivot, "bubble": bubble, "bubble_t": 0.0, "scale": s}


## lying: in bed / on couch. along_x: lie along the x axis (couch).
func set_actor(id: String, pos: Vector2, lying: bool, dir: Vector2 = Vector2(0, 1), along_x: bool = false) -> void:
	var a: Dictionary = actors[id]
	var root: Node3D = a["root"]
	var pivot: Node3D = a["pivot"]
	var s: float = a["scale"]
	if lying:
		if along_x:
			root.position = Vector3(pos.x + 0.45 * s, 0.45, pos.y + 0.5)
			pivot.rotation = Vector3(-PI / 2, PI / 2, 0)
		else:
			root.position = Vector3(pos.x, 0.42, pos.y + 0.45 * s)
			pivot.rotation = Vector3(-PI / 2, 0, 0)
	else:
		root.position = Vector3(pos.x, 0.0, pos.y)
		pivot.rotation = Vector3(0, atan2(dir.x, dir.y), 0)


func say(who: String, text: String) -> void:
	if not actors.has(who):
		return
	var a: Dictionary = actors[who]
	var b: Label3D = a["bubble"]
	b.text = text
	b.visible = true
	a["bubble_t"] = 2.4


func clear_bubbles() -> void:
	for id in actors:
		actors[id]["bubble"].visible = false
		actors[id]["bubble_t"] = 0.0


# --- Per-night setup -------------------------------------------------------

func reset_for_night(night: Dictionary, plan: Dictionary) -> void:
	for c in dynamic.get_children():
		c.queue_free()
	for r in fog:
		fog[r].queue_free()
	fog.clear()
	boards.clear()
	_lights_all = false
	clear_bubbles()
	for r in House.DARK_ROOMS:
		var rect: Rect2 = house.rooms[r]
		var f := Node3D.new()
		add_child(f)
		block(f, rect.position.x + 0.07, rect.position.y + 0.07, rect.end.x - 0.07, rect.end.y - 0.07, 2.3, Color(0.03, 0.04, 0.09))
		label3d(f, "?\ntap to peek", Vector3(rect.get_center().x, 2.7, rect.get_center().y), 46, Color(0.75, 0.8, 1.0))
		fog[r] = f
	for b in night["boards"]:
		var p: Vector2 = b["pos"]
		var n := block(dynamic, p.x - 0.32, p.y - 0.14, p.x + 0.32, p.y + 0.14, 0.03, Color(1.0, 0.55, 0.15), 0.0, 0.7)
		n.visible = b["room"] == "hall" or plan["peeked"].has(b["room"])
		boards.append({"node": n, "room": b["room"]})
	if night["jar"] == "fridge":
		jar_node = block(dynamic, 10.25, 8.55, 10.55, 8.85, 0.32, Color(0.85, 0.6, 0.3), 1.9, 0.4)
	else:
		jar_node = block(dynamic, 11.55, 6.25, 11.85, 6.55, 0.32, Color(0.85, 0.6, 0.3), 0.9, 0.4)
	dad_on_couch = night["dad_spot"] == "couch"
	tv_on = dad_on_couch
	tv_screen.material_override = _mat(Color(0.45, 0.65, 1.0), 1.6) if tv_on else _mat(Color(0.15, 0.2, 0.3))
	for r in lights:
		lights[r].light_energy = 0.0
	place_sleepers(night)
	set_decoys(plan, {})
	set_lego(plan.get("lego"))


func place_sleepers(night: Dictionary) -> void:
	for id in ["maya", "ben"]:
		set_actor(id, house.nodes[id + "_bed"], true)
	set_actor("noa", house.nodes["crib"] + Vector2(0, -0.3), true)
	set_actor("mom", house.nodes["mom_bed"], true)
	set_actor("dad", house.nodes["couch" if night["dad_spot"] == "couch" else "dad_bed"], true, Vector2(0, 1), night["dad_spot"] == "couch")


func reveal(room: String) -> void:
	if fog.has(room):
		fog[room].queue_free()
		fog.erase(room)
	for b in boards:
		if b["room"] == room:
			b["node"].visible = true


func reveal_all() -> void:
	for r in fog.keys():
		reveal(r)
	for b in boards:
		b["node"].visible = true


func set_lego(pos) -> void:
	if pos == null:
		lego_node.visible = false
		return
	lego_node.visible = true
	lego_node.position = Vector3(pos.x, 0.05, pos.y)


## Show a pillow-decoy lump on the bed of a kid who has the decoy and is out.
## kid_states: id -> state ("bed" etc). Empty means planning (show assigned decoy).
func set_decoys(plan: Dictionary, kid_states: Dictionary) -> void:
	for id in decoys:
		var has_it: bool = plan["pillow"] == id
		if kid_states.is_empty():
			decoys[id].visible = has_it
		else:
			decoys[id].visible = has_it and kid_states[id] != "bed"


# --- Planning overlay ------------------------------------------------------

func clear_overlay() -> void:
	for c in overlay.get_children():
		c.queue_free()


func _dots(path: PackedVector2Array, col: Color, spacing: float = 0.32, size: float = 0.11) -> void:
	var carry := 0.0
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var seg := a.distance_to(b)
		var d := spacing - carry
		while d <= seg:
			var p := a.lerp(b, d / seg)
			box(overlay, Vector3(size, 0.02, size), Vector3(p.x, 0.03, p.y), col, 1.2)
			d += spacing
		carry = seg - (d - spacing)


func draw_plan(night: Dictionary, plan: Dictionary, prediction: Dictionary, selected: String) -> void:
	clear_overlay()
	var sim = prediction.get("sim")
	if sim == null:
		return
	var know: Dictionary = prediction["know"]
	# Known grown-up routes in red.
	for rec in sim.errand_log:
		var who: String = rec["who"]
		var from: Vector2 = sim.adults[who]["sleep_pos"]
		var to: Vector2 = rec["dest"]
		_dots(house.path_points(from, to), Color(1.0, 0.25, 0.25, 0.9), 0.4, 0.09)
		label3d(overlay, "%s %s" % [T.NAMES[who], T.fmt(rec["start"])], Vector3(to.x, 1.1, to.y), 34, Color(1.0, 0.55, 0.55))
	# Selected kid route + time tags.
	if selected == "maya" or selected == "ben":
		var kp: Dictionary = plan["kids"][selected]
		var jar := "fridge" if (know["jar"] and night["jar"] == "fridge") else "counter"
		var path: PackedVector2Array = house.find_path(selected + "_bed", jar, kp["route"])
		var col: Color = T.COLORS[selected]
		if kp["job"] != "run":
			col = col.darkened(0.55)
		_dots(path, col)
		for tr in sim.trips:
			if tr["kid"] != selected:
				continue
			if tr["jar"] >= 0.0:
				var jp: Vector2 = house.nodes[jar]
				label3d(overlay, "jar " + T.fmt(tr["jar"]), Vector3(jp.x, 1.5, jp.y), 36, col.lightened(0.3))
			if tr["home"] >= 0.0:
				var bp: Vector2 = house.nodes[selected + "_bed"]
				label3d(overlay, "bed " + T.fmt(tr["home"]), Vector3(bp.x, 1.2, bp.y), 36, col.lightened(0.3))
			break
		var ring_p: Vector2 = house.nodes[selected + "_bed"]
		block(overlay, ring_p.x - 0.55, ring_p.y - 1.15, ring_p.x + 0.55, ring_p.y + 1.15, 0.02, col, 0.02, 0.8)


# --- Live update -----------------------------------------------------------

func update_from_sim(sim) -> void:
	var states := {}
	for id in sim.kids:
		var k: Dictionary = sim.kids[id]
		states[id] = k["state"]
		set_actor(id, k["pos"], k["state"] == "bed", k["dir"])
	for id in sim.adults:
		var a: Dictionary = sim.adults[id]
		var couch: bool = a["asleep"] and a["sleep_node"] == "couch"
		set_actor(id, a["pos"], a["asleep"], a["dir"], couch)
	set_decoys(sim.plan, states)
	# Lights follow awake grown-ups. Mom's tell: the hallway light flicks on whenever she's up.
	var lit := {}
	for id in sim.adults:
		var a: Dictionary = sim.adults[id]
		if not a["asleep"]:
			lit[house.room_at(a["pos"])] = true
			if id == "mom":
				lit["hall"] = true
	if sim.busted:
		_lights_all = true
	for r in lights:
		var target := 1.6 if (_lights_all or lit.has(r)) else 0.0
		lights[r].light_energy = lerpf(lights[r].light_energy, target, 0.15)
	var dad: Dictionary = sim.adults["dad"]
	tv_on = dad_on_couch and dad["asleep"]
	tv_screen.material_override = _mat(Color(0.45, 0.65, 1.0), 1.6) if tv_on else _mat(Color(0.15, 0.2, 0.3))


func tick(delta: float) -> void:
	_time += delta
	tv_light.light_energy = (0.7 + 0.35 * sin(_time * 11.0) * sin(_time * 2.7)) if tv_on else 0.0
	for id in actors:
		var a: Dictionary = actors[id]
		if a["bubble_t"] > 0.0:
			a["bubble_t"] -= delta
			if a["bubble_t"] <= 0.0:
				a["bubble"].visible = false
