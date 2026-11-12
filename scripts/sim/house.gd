extends RefCounted
## House geometry: rooms, walls, the waypoint graph (AStar3D) and noise falloff.
## Floor-plan coordinates are Vector2(x, z): x runs left to right, z back to front.

const T := preload("res://scripts/sim/tuning.gd")

const WIDTH := 12.0
const DEPTH := 9.0
const DARK_ROOMS := ["parents", "living", "kitchen"]
const ROOM_ORDER := ["kids", "nursery", "parents", "hall", "bath", "living", "kitchen"]
const ROOM_TITLES := {
	"kids": "kids' room", "nursery": "nursery", "parents": "parents' room",
	"hall": "hallway", "bath": "bathroom", "living": "living room", "kitchen": "kitchen",
	"outside": "garden",
}
# A kid's route is enforced by blocking one edge of the graph.
const ROUTE_BLOCKS := {
	"living": [["hall_kit", "kit_door"]],
	"hall": [["hall_liv", "liv_door"]],
}

var rooms := {}          # name -> Rect2(x, z, w, h)
var nodes := {}          # name -> Vector2
var node_room := {}      # name -> room
var edges: Array = []    # [a, b]
var walls: Array = []    # {a, b, doors: [coord along wall], tall}
var _ids := {}
var _names: Array = []
var _astar_cache := {}


func _init() -> void:
	rooms = {
		"kids": Rect2(0, 0, 4, 4),
		"nursery": Rect2(4, 0, 3, 4),
		"parents": Rect2(7, 0, 5, 4),
		"hall": Rect2(0, 4, 12, 1.5),
		"bath": Rect2(0, 5.5, 3, 3.5),
		"living": Rect2(3, 5.5, 6, 3.5),
		"kitchen": Rect2(9, 5.5, 3, 3.5),
	}
	var pts := {
		"maya_bed": Vector2(1.0, 1.4),
		"ben_bed": Vector2(3.0, 1.4),
		"kids_door": Vector2(2.0, 3.6),
		"hall_w": Vector2(2.2, 4.75),
		"bath_in": Vector2(2.4, 6.3),
		"toilet": Vector2(1.0, 7.8),
		"hall_nurs": Vector2(5.5, 4.75),
		"nurs_in": Vector2(5.5, 3.3),
		"crib": Vector2(5.5, 2.0),
		"hall_liv": Vector2(6.5, 4.75),
		"hall_par": Vector2(8.5, 4.75),
		"par_in": Vector2(8.5, 3.3),
		"mom_bed": Vector2(9.4, 1.2),
		"dad_bed": Vector2(10.8, 1.2),
		"hall_kit": Vector2(10.0, 4.75),
		"liv_door": Vector2(6.5, 6.2),
		"couch": Vector2(4.6, 7.9),
		"liv_mid": Vector2(7.2, 7.4),
		"liv_side": Vector2(8.5, 6.4),
		"kit_side": Vector2(9.6, 6.4),
		"kit_door": Vector2(10.0, 6.1),
		"kit_mid": Vector2(10.4, 7.2),
		"counter": Vector2(11.2, 6.4),
		"fridge": Vector2(10.4, 8.2),
	}
	for n in pts:
		_ids[n] = _names.size()
		_names.append(n)
		nodes[n] = pts[n]
		node_room[n] = room_at(pts[n])
	edges = [
		["maya_bed", "kids_door"], ["ben_bed", "kids_door"], ["kids_door", "hall_w"],
		["hall_w", "bath_in"], ["bath_in", "toilet"],
		["hall_w", "hall_nurs"], ["hall_nurs", "nurs_in"], ["nurs_in", "crib"],
		["hall_nurs", "hall_liv"], ["hall_liv", "hall_par"], ["hall_par", "par_in"],
		["par_in", "mom_bed"], ["par_in", "dad_bed"], ["hall_par", "hall_kit"],
		["hall_kit", "kit_door"], ["kit_door", "kit_mid"], ["kit_door", "counter"],
		["hall_liv", "liv_door"], ["liv_door", "couch"], ["liv_door", "liv_mid"],
		["couch", "liv_mid"], ["liv_mid", "liv_side"], ["liv_side", "kit_side"],
		["kit_side", "kit_mid"], ["kit_mid", "counter"], ["kit_mid", "fridge"],
	]
	walls = [
		{"a": Vector2(0, 0), "b": Vector2(12, 0), "doors": [], "tall": true},
		{"a": Vector2(0, 0), "b": Vector2(0, 9), "doors": [], "tall": true},
		{"a": Vector2(12, 0), "b": Vector2(12, 9), "doors": [], "tall": false},
		{"a": Vector2(0, 9), "b": Vector2(12, 9), "doors": [], "tall": false},
		{"a": Vector2(0, 4), "b": Vector2(12, 4), "doors": [2.0, 5.5, 8.5], "tall": false},
		{"a": Vector2(0, 5.5), "b": Vector2(12, 5.5), "doors": [2.4, 6.5, 10.0], "tall": false},
		{"a": Vector2(4, 0), "b": Vector2(4, 4), "doors": [], "tall": false},
		{"a": Vector2(7, 0), "b": Vector2(7, 4), "doors": [], "tall": false},
		{"a": Vector2(3, 5.5), "b": Vector2(3, 9), "doors": [], "tall": false},
		{"a": Vector2(9, 5.5), "b": Vector2(9, 9), "doors": [6.4], "tall": false},
	]


func room_at(p: Vector2) -> String:
	for r in ROOM_ORDER:
		var rect: Rect2 = rooms[r]
		if rect.has_point(p):
			return r
	return "outside"


func title(room: String) -> String:
	return ROOM_TITLES.get(room, room)


# --- Pathfinding -----------------------------------------------------------

func _astar(blocked: Array) -> AStar3D:
	var key := str(blocked)
	if _astar_cache.has(key):
		return _astar_cache[key]
	var a := AStar3D.new()
	for n in _names:
		var p: Vector2 = nodes[n]
		a.add_point(_ids[n], Vector3(p.x, 0.0, p.y))
	for e in edges:
		var skip := false
		for b in blocked:
			if (b[0] == e[0] and b[1] == e[1]) or (b[0] == e[1] and b[1] == e[0]):
				skip = true
		if not skip:
			a.connect_points(_ids[e[0]], _ids[e[1]])
	_astar_cache[key] = a
	return a


## Node-to-node path. `route` is "living", "hall" or "" (grown-ups: shortest path).
func find_path(from_node: String, to_node: String, route: String = "") -> PackedVector2Array:
	var blocked: Array = ROUTE_BLOCKS.get(route, [])
	var ids := _astar(blocked).get_id_path(_ids[from_node], _ids[to_node])
	var out := PackedVector2Array()
	for id in ids:
		out.append(nodes[_names[id]])
	return out


## Nearest graph node, preferring nodes in the same room as p.
func nearest_node(p: Vector2) -> String:
	var room := room_at(p)
	var best := ""
	var best_d := INF
	for pass_i in 2:
		for n in _names:
			if pass_i == 0 and node_room[n] != room:
				continue
			var d := p.distance_squared_to(nodes[n])
			if d < best_d:
				best_d = d
				best = n
		if best != "":
			return best
	return best


## Point-to-point path through the graph (shortest, no route restriction).
func path_points(from: Vector2, to: Vector2, route: String = "") -> PackedVector2Array:
	var a := nearest_node(from)
	var b := nearest_node(to)
	var mid := find_path(a, b, route)
	var out := PackedVector2Array()
	if mid.is_empty() or from.distance_to(mid[0]) > 0.01:
		out.append(from)
	out.append_array(mid)
	if out[out.size() - 1].distance_to(to) > 0.01:
		out.append(to)
	return out


func path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


func dist_to_path(p: Vector2, path: PackedVector2Array) -> float:
	var best := INF
	for i in range(1, path.size()):
		var c := Geometry2D.get_closest_point_to_segment(p, path[i - 1], path[i])
		best = minf(best, p.distance_to(c))
	return best


## Snap a tapped floor point to the nearest walkway (graph edge).
func snap_to_walkway(p: Vector2) -> Vector2:
	var best := p
	var best_d := INF
	for e in edges:
		var c := Geometry2D.get_closest_point_to_segment(p, nodes[e[0]], nodes[e[1]])
		var d := p.distance_to(c)
		if d < best_d:
			best_d = d
			best = c
	return best


# --- Noise -----------------------------------------------------------------

func wall_factor(a: Vector2, b: Vector2) -> float:
	var ra := room_at(a)
	var rb := room_at(b)
	if ra == rb:
		return 1.0
	if ra == "hall" or rb == "hall":
		return T.WALL_HALL
	return T.WALL_ROOM


## How much of a sound of loudness `loud` at `src` reaches a listener at `listener`.
func heard(loud: float, src: Vector2, listener: Vector2) -> float:
	var d2 := src.distance_squared_to(listener)
	return loud / (1.0 + d2 / T.FALLOFF) * wall_factor(src, listener)
