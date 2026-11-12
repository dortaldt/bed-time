extends Control
## Timeline under the map: each kid's trips against the known grown-up errands.
## In planning it draws the prediction; during the night it draws the live sim.

const T := preload("res://scripts/sim/tuning.gd")

const ROWS := ["maya", "ben", "mom", "dad"]
const LEFT := 62.0

var sim = null          # Simulation (predict or live)
var know: Dictionary = {}
var live := false


func _init() -> void:
	custom_minimum_size = Vector2(0, 168)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(p_sim, p_know: Dictionary, p_live: bool) -> void:
	sim = p_sim
	know = p_know
	live = p_live
	queue_redraw()


func _x(t: float) -> float:
	return LEFT + (size.x - LEFT - 10.0) * clampf(t / T.NIGHT_LEN, 0.0, 1.0)


func _row_y(i: int) -> float:
	return 8.0 + i * _row_h()


func _row_h() -> float:
	return (size.y - 30.0) / ROWS.size()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.06, 0.13, 0.95))
	var bottom := size.y - 22.0
	for s in range(0, 91, 15):
		var x := _x(s)
		draw_line(Vector2(x, 4), Vector2(x, bottom), Color(1, 1, 1, 0.08))
		draw_string(font, Vector2(x - 14, size.y - 5), T.fmt(s), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.45))
	var lx := _x(T.LAST_TRIP)
	for y in range(4, int(bottom), 8):
		draw_line(Vector2(lx, y), Vector2(lx, y + 4), Color(1, 1, 1, 0.3))
	var rh := _row_h()
	for i in ROWS.size():
		var id: String = ROWS[i]
		draw_string(font, Vector2(8, _row_y(i) + rh * 0.62), T.NAMES[id], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, T.COLORS[id])
	if sim == null:
		return
	var now: float = sim.t if live else T.NIGHT_LEN
	# Kid trips.
	for tr in sim.trips:
		var i := ROWS.find(tr["kid"])
		var end: float = tr["home"] if tr["home"] >= 0.0 else now
		var col: Color = T.COLORS[tr["kid"]]
		if tr["result"] == "caught" or tr["result"] == "busted":
			col = Color(1, 0.3, 0.3)
		_bar(i, tr["leave"], end, col)
		if tr["jar"] >= 0.0:
			var jx := _x(tr["jar"])
			draw_rect(Rect2(jx - 3, _row_y(i) + 2, 6, rh - 8), Color(1.0, 0.8, 0.35))
	# Grown-up errands.
	for rec in sim.errand_log:
		var i := ROWS.find(rec["who"])
		var end: float = rec["back"] if rec["back"] >= 0.0 else now
		_bar(i, rec["start"], end, Color(0.95, 0.28, 0.28, 0.85))
		draw_string(font, Vector2(_x(rec["start"]) + 3, _row_y(i) + rh * 0.62), rec["type"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9))
	if not live:
		for i in [2, 3]:
			var who: String = ROWS[i]
			if not know.get(who, false):
				draw_string(font, Vector2(_x(30), _row_y(i) + rh * 0.62), "?  peek to learn the schedule", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.35))
	# Bed checks: a red tick across the kid rows.
	for c in sim.checks:
		var cx := _x(c["t"])
		var bad: bool = not c["out"].is_empty()
		draw_line(Vector2(cx, 4), Vector2(cx, _row_y(2)), Color(1, 0.2, 0.2) if bad else Color(1, 0.6, 0.6, 0.6), 3.0 if bad else 1.5)
	if live:
		var px := _x(sim.t)
		draw_line(Vector2(px, 0), Vector2(px, bottom), Color(1, 1, 1, 0.9), 2.0)


func _bar(i: int, a: float, b: float, col: Color) -> void:
	if i < 0:
		return
	var x0 := _x(a)
	var x1 := maxf(_x(b), x0 + 3.0)
	draw_rect(Rect2(x0, _row_y(i) + 5, x1 - x0, _row_h() - 14), col)
