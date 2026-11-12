extends Node3D
## Game controller: night setup, peeking and planning on the map, running the night,
## results, parent adaptation and camera controls (drag to pan, pinch / wheel to zoom).

const T := preload("res://scripts/sim/tuning.gd")
const House := preload("res://scripts/sim/house.gd")
const Nights := preload("res://scripts/sim/nights.gd")
const Sim := preload("res://scripts/sim/simulation.gd")
const Predictor := preload("res://scripts/sim/predictor.gd")
const HouseView := preload("res://scripts/game/house_view.gd")
const UI := preload("res://scripts/game/ui.gd")

const SAVE_PATH := "user://past_bedtime.cfg"

var house
var view
var ui
var camera: Camera3D

var night_index := 0
var night: Dictionary = {}
var plan: Dictionary = {}
var adapt: Dictionary = {}
var history: Array = []       # [{cry: bool, lego: bool}] for adaptation
var best: Array = [0, 0, 0, 0]
var phase := "plan"           # plan | night | result
var selected := "maya"
var prediction: Dictionary = {}
var sim = null
var speed := 1.0

var _dirty := true
var _acc := 0.0
var _event_i := 0
var _end_timer := -1.0

# Camera / touch
var _zoom := 16.0
var _pan := Vector2.ZERO
var _touches := {}
var _press_pos := Vector2.ZERO
var _dragged := false
var _pinch_d := 0.0


func _ready() -> void:
	randomize()
	house = House.new()
	view = HouseView.new()
	add_child(view)
	view.build(house)
	_setup_camera()
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = UI.new()
	layer.add_child(ui)
	ui.setup(self)
	plan = _default_plan()
	_load()
	get_viewport().size_changed.connect(_frame_camera)
	start_night(night_index)
	_frame_camera.call_deferred()


func _default_plan() -> Dictionary:
	return {
		"kids": {
			"maya": {"job": "run", "leave": 0.0, "route": "living"},
			"ben": {"job": "bed", "leave": 0.0, "route": "living"},
		},
		"socks": "", "pillow": "", "lego": null, "cry": -1.0, "peeked": [],
	}


# --- Night flow ------------------------------------------------------------

func start_night(idx: int) -> void:
	night_index = clampi(idx, 0, Nights.NAMES.size() - 1)
	adapt = _adapt_from_history()
	night = Nights.roll(night_index, randi())
	plan["peeked"] = []
	phase = "plan"
	sim = null
	view.reset_for_night(night, plan)
	view.clear_overlay()
	ui.show_plan()
	_dirty = true
	if adapt.get("ignore_cry", false):
		ui.show_toast("Mom: \"Nice try. I know that cry by now.\"", 3.5)
	elif adapt.get("slippers", false):
		ui.show_toast("Dad bought slippers. The LEGO trap won't work tonight.", 3.5)


func retry() -> void:
	start_night(night_index)


func lights_out() -> void:
	if phase != "plan":
		return
	phase = "night"
	history.append({"cry": plan["cry"] >= 0.0, "lego": plan["lego"] != null})
	while history.size() > 2:
		history.pop_front()
	sim = Sim.new(house, night, plan.duplicate(true), adapt, false)
	_acc = 0.0
	_event_i = 0
	_end_timer = -1.0
	view.clear_overlay()
	view.clear_bubbles()
	view.reveal_all()
	ui.show_night()
	ui.update_night(sim)


func skip_night() -> void:
	if phase != "night":
		return
	while not sim.finished:
		sim.step()
	_end_timer = 0.0


func _show_result() -> void:
	phase = "result"
	var stars: int = sim.stars()
	best[night_index] = maxi(best[night_index], stars)
	_save()
	ui.show_result(sim, stars, best[night_index])


func _adapt_from_history() -> Dictionary:
	var a := {"ignore_cry": false, "slippers": false}
	if history.size() >= 2:
		var h1: Dictionary = history[history.size() - 1]
		var h2: Dictionary = history[history.size() - 2]
		a["ignore_cry"] = h1["cry"] and h2["cry"]
		a["slippers"] = h1["lego"] and h2["lego"]
	return a


func _process(delta: float) -> void:
	match phase:
		"plan":
			if _dirty:
				_dirty = false
				prediction = Predictor.predict(house, night, plan, adapt)
				view.draw_plan(night, plan, prediction, selected)
				view.set_decoys(plan, {})
				view.set_lego(plan["lego"])
				ui.update_plan_info()
		"night":
			if not sim.finished:
				_acc += delta * speed
				var steps := 0
				while _acc >= T.DT and not sim.finished and steps < 600:
					sim.step()
					_acc -= T.DT
					steps += 1
			_flush_events()
			view.update_from_sim(sim)
			ui.update_night(sim)
			if sim.finished:
				if _end_timer < 0.0:
					_end_timer = 2.0
				_end_timer -= delta
				if _end_timer <= 0.0:
					_show_result()
	view.tick(delta)


func _flush_events() -> void:
	while _event_i < sim.events.size():
		var e: Dictionary = sim.events[_event_i]
		_event_i += 1
		view.say(e["who"], e["text"])
		ui.log_event(e)


# --- Planning actions (called by UI and map taps) --------------------------

func peeks_left() -> int:
	return T.PEEKS - plan["peeked"].size()


func select(id: String) -> void:
	selected = id
	ui.show_plan.call_deferred()
	_dirty = true


func set_kid(id: String, key: String, value) -> void:
	plan["kids"][id][key] = value
	_dirty = true


func give(item: String, id: String) -> void:
	plan[item] = "" if plan[item] == id else id
	_dirty = true
	ui.show_plan.call_deferred()


func set_cry(t: float) -> void:
	plan["cry"] = t
	_dirty = true


func set_lego(pos) -> void:
	plan["lego"] = pos
	_dirty = true


func peek(room: String) -> void:
	if peeks_left() <= 0:
		ui.show_toast("No peeks left tonight.")
		return
	plan["peeked"].append(room)
	view.reveal(room)
	var msg := "You peek into the %s..." % house.title(room)
	match room:
		"parents":
			msg = "Mom wakes at noise %d." % int(night["mom_threshold"])
			if night["dad_spot"] == "couch":
				msg += " Dad's side is empty!"
		"living":
			msg = "Dad is snoring on the couch, TV on." if night["dad_spot"] == "couch" else "The living room is empty."
		"kitchen":
			msg = "The jar is on the %s." % ("fridge" if night["jar"] == "fridge" else "counter")
	ui.show_toast(msg)
	_dirty = true


func _on_tap(screen_pos: Vector2) -> void:
	if phase != "plan":
		return
	var hit = _screen_to_floor(screen_pos)
	if hit == null:
		return
	var p: Vector2 = hit
	if selected == "lego":
		if p.x < -0.5 or p.x > House.WIDTH + 0.5 or p.y < -0.5 or p.y > House.DEPTH + 0.5:
			return
		set_lego(house.snap_to_walkway(p))
		return
	var room: String = house.room_at(p)
	if House.DARK_ROOMS.has(room) and not plan["peeked"].has(room):
		peek(room)
		return
	for id in ["maya", "ben"]:
		if p.distance_to(house.nodes[id + "_bed"]) < 1.1:
			select(id)
			return
	if p.distance_to(house.nodes["crib"]) < 1.0:
		select("noa")


# --- Camera ----------------------------------------------------------------

func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = _zoom
	camera.far = 200.0
	add_child(camera)
	# Front-right corner, ~37 degrees down, like the prototype.
	var center := Vector3(House.WIDTH * 0.5, 0.0, House.DEPTH * 0.5)
	var pitch := deg_to_rad(37.0)
	var r := 30.0
	var flat := Vector3(1, 0, 1).normalized()
	camera.position = center + flat * r * cos(pitch) + Vector3.UP * r * sin(pitch)
	camera.look_at(center, Vector3.UP)
	camera.current = true


func _frame_camera() -> void:
	var vs := get_viewport().get_visible_rect().size
	if vs.x <= 0.0:
		return
	camera.size = _zoom
	var upp := _zoom / vs.x  # world units per pixel
	var top: float = ui.top_height()
	var bottom: float = ui.bottom_height()
	var map_center_y := top + (vs.y - top - bottom) * 0.5
	var off_px := map_center_y - vs.y * 0.5
	camera.v_offset = off_px * upp + _pan.y
	camera.h_offset = _pan.x


func _screen_to_floor(pos: Vector2):
	var origin := camera.project_ray_origin(pos)
	var dir := camera.project_ray_normal(pos)
	if absf(dir.y) < 0.0001:
		return null
	var k := -origin.y / dir.y
	var hit := origin + dir * k
	return Vector2(hit.x, hit.z)


func _touch_dist() -> float:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return 0.0
	return (pts[0] as Vector2).distance_to(pts[1])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if ui.blocks(st.position):
				return
			_touches[st.index] = st.position
			if _touches.size() == 1:
				_press_pos = st.position
				_dragged = false
			elif _touches.size() == 2:
				_pinch_d = _touch_dist()
				_dragged = true
		elif _touches.has(st.index):
			_touches.erase(st.index)
			if _touches.is_empty() and not _dragged:
				_on_tap(st.position)
			_pinch_d = _touch_dist()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if not _touches.has(sd.index):
			return
		_touches[sd.index] = sd.position
		if _touches.size() == 1:
			if sd.position.distance_to(_press_pos) > 14.0:
				_dragged = true
			if _dragged:
				var upp := _zoom / get_viewport().get_visible_rect().size.x
				_pan.x -= sd.relative.x * upp
				_pan.y += sd.relative.y * upp
				_pan = _pan.clamp(Vector2(-8, -8), Vector2(8, 8))
				_frame_camera()
		else:
			var d := _touch_dist()
			if _pinch_d > 0.0 and d > 0.0:
				_set_zoom(_zoom * _pinch_d / d)
			_pinch_d = d
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_zoom * 0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_zoom * 1.1)
	elif event is InputEventMagnifyGesture:
		_set_zoom(_zoom / (event as InputEventMagnifyGesture).factor)


func _set_zoom(z: float) -> void:
	_zoom = clampf(z, 7.0, 24.0)
	_frame_camera()


# --- Save ------------------------------------------------------------------

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "best", best)
	cfg.set_value("progress", "night", night_index)
	cfg.set_value("progress", "history", history)
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var b = cfg.get_value("progress", "best", best)
	if b is Array and b.size() == best.size():
		best = b
	night_index = int(cfg.get_value("progress", "night", 0))
	var h = cfg.get_value("progress", "history", [])
	if h is Array:
		history = h
