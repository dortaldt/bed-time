extends Control
## Portrait UI: top bar, bottom planning / night / result panel, toasts.
## Built in code so the placeholder layout is easy to restyle later.

const T := preload("res://scripts/sim/tuning.gd")
const Nights := preload("res://scripts/sim/nights.gd")
const Predictor := preload("res://scripts/sim/predictor.gd")
const Timeline := preload("res://scripts/game/timeline.gd")

const SEL_LABELS := {"maya": "Maya", "ben": "Ben", "noa": "Noa", "lego": "LEGO"}

var game
var top: PanelContainer
var top_label: Label
var night_pick: OptionButton
var bottom: PanelContainer
var body: VBoxContainer
var footer: HBoxContainer
var timeline
var info: RichTextLabel
var toast: PanelContainer
var toast_label: Label
var _toast_t := 0.0
var log_label: RichTextLabel
var status_label: Label
var meters := {}
var _log: Array = []


func setup(g) -> void:
	game = g
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	_build_top()
	_build_bottom()
	_build_toast()
	get_viewport().size_changed.connect(_resize)
	_resize()


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		toast.modulate.a = clampf(_toast_t * 2.0, 0.0, 1.0)
		if _toast_t <= 0.0:
			toast.visible = false


# --- Layout ----------------------------------------------------------------

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 22
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.08, 0.17, 0.95)
	panel.set_corner_radius_all(18)
	panel.set_content_margin_all(14)
	th.set_stylebox("panel", "PanelContainer", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.17, 0.21, 0.38)
	btn.set_corner_radius_all(12)
	btn.set_content_margin_all(10)
	var hover: StyleBoxFlat = btn.duplicate()
	hover.bg_color = Color(0.22, 0.27, 0.48)
	var pressed: StyleBoxFlat = btn.duplicate()
	pressed.bg_color = Color(0.98, 0.78, 0.32)
	var disabled: StyleBoxFlat = btn.duplicate()
	disabled.bg_color = Color(0.12, 0.13, 0.2)
	th.set_stylebox("normal", "Button", btn)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", pressed)
	th.set_stylebox("hover_pressed", "Button", pressed)
	th.set_stylebox("disabled", "Button", disabled)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_pressed_color", "Button", Color(0.1, 0.08, 0.15))
	th.set_color("font_hover_pressed_color", "Button", Color(0.1, 0.08, 0.15))
	th.set_stylebox("normal", "OptionButton", btn)
	th.set_stylebox("hover", "OptionButton", hover)
	th.set_stylebox("pressed", "OptionButton", hover)
	th.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.12, 0.14, 0.25)
	bar_bg.set_corner_radius_all(6)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.95, 0.55, 0.3)
	bar_fill.set_corner_radius_all(6)
	th.set_stylebox("background", "ProgressBar", bar_bg)
	th.set_stylebox("fill", "ProgressBar", bar_fill)
	return th


func _build_top() -> void:
	top = PanelContainer.new()
	add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8
	top.offset_right = -8
	top.offset_top = 8
	var hb := HBoxContainer.new()
	top.add_child(hb)
	night_pick = OptionButton.new()
	for n in Nights.NAMES:
		night_pick.add_item(n)
	night_pick.item_selected.connect(func(i: int) -> void: game.start_night(i))
	hb.add_child(night_pick)
	top_label = Label.new()
	top_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(top_label)


func _build_bottom() -> void:
	bottom = PanelContainer.new()
	add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	bottom.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	outer.add_child(footer)


func _build_toast() -> void:
	toast = PanelContainer.new()
	add_child(toast)
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast.offset_top = 90
	toast.offset_left = -300
	toast.offset_right = 300
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label = Label.new()
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_child(toast_label)
	toast.visible = false


func _resize() -> void:
	var vs := get_viewport_rect().size
	var h := clampf(vs.y * 0.48, 420.0, 760.0)
	bottom.offset_top = -h
	bottom.offset_bottom = -8
	bottom.offset_left = 8
	bottom.offset_right = -8


func top_height() -> float:
	return top.get_global_rect().end.y if top.size.y > 0 else 80.0


func bottom_height() -> float:
	return -bottom.offset_top + 8.0


## True if a screen point is over UI (so map taps ignore it).
func blocks(pos: Vector2) -> bool:
	return top.get_global_rect().has_point(pos) or bottom.get_global_rect().has_point(pos)


func show_toast(text: String, secs: float = 2.8) -> void:
	toast_label.text = text
	toast.visible = true
	toast.modulate.a = 1.0
	_toast_t = secs


# --- Small builders --------------------------------------------------------

func _clear(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()


func _btn(text: String, cb: Callable, toggle: bool = false, on: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.toggle_mode = toggle
	if toggle:
		b.button_pressed = on
	b.pressed.connect(cb)
	return b


func _label(text: String, parent: Node, font_size: int = 20, col: Color = Color(0.85, 0.88, 1.0)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func _row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(92, 0)
	l.add_theme_color_override("font_color", Color(0.65, 0.7, 0.9))
	row.add_child(l)
	body.add_child(row)
	return row


## Exclusive choice buttons. options: [[label, value], ...]
func _choice(row: HBoxContainer, options: Array, current, cb: Callable) -> void:
	var group := ButtonGroup.new()
	for o in options:
		var value = o[1]
		var b := _btn(o[0], func() -> void: cb.call(value), true, current == value)
		b.button_group = group
		row.add_child(b)


# --- Planning --------------------------------------------------------------

func show_plan() -> void:
	_clear(body)
	_clear(footer)
	night_pick.select(game.night_index)
	night_pick.disabled = false
	var sel_row := HBoxContainer.new()
	sel_row.add_theme_constant_override("separation", 8)
	body.add_child(sel_row)
	var group := ButtonGroup.new()
	for id in ["maya", "ben", "noa", "lego"]:
		var b := _btn(SEL_LABELS[id], func() -> void: game.select(id), true, game.selected == id)
		b.button_group = group
		if T.COLORS.has(id):
			b.add_theme_color_override("font_color", T.COLORS[id])
		sel_row.add_child(b)
	match game.selected:
		"maya", "ben":
			_kid_panel(game.selected)
		"noa":
			_noa_panel()
		"lego":
			_lego_panel()
	timeline = Timeline.new()
	body.add_child(timeline)
	info = RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("normal_font_size", 19)
	info.add_theme_font_size_override("bold_font_size", 20)
	body.add_child(info)
	var go := _btn("LIGHTS OUT", func() -> void: game.lights_out())
	go.custom_minimum_size = Vector2(0, 64)
	go.add_theme_font_size_override("font_size", 28)
	footer.add_child(go)
	update_plan_info()


func _kid_panel(id: String) -> void:
	var kp: Dictionary = game.plan["kids"][id]
	var spec: Dictionary = T.KIDS[id]
	_label("%s, %s: %s." % [spec["name"], spec["title"], spec["blurb"]], body, 19, T.COLORS[id])
	_choice(_row("Job"), [["Stay in bed", "bed"], ["Cookie run", "run"]], kp["job"],
		func(v) -> void: game.set_kid(id, "job", v))
	var lrow := _row("Leave")
	var val := Label.new()
	val.text = T.fmt(kp["leave"])
	val.custom_minimum_size = Vector2(64, 0)
	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = T.LEAVE_MAX
	sl.step = 1
	sl.value = kp["leave"]
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(0, 44)
	sl.value_changed.connect(func(v: float) -> void:
		val.text = T.fmt(v)
		game.set_kid(id, "leave", v)
	)
	lrow.add_child(sl)
	lrow.add_child(val)
	_choice(_row("Route"), [["Living room", "living"], ["Hallway", "hall"]], kp["route"],
		func(v) -> void: game.set_kid(id, "route", v))
	var grow := _row("Gear")
	grow.add_child(_btn("Socks", func() -> void: game.give("socks", id), true, game.plan["socks"] == id))
	grow.add_child(_btn("Pillow decoy", func() -> void: game.give("pillow", id), true, game.plan["pillow"] == id))
	var other := "ben" if id == "maya" else "maya"
	var notes: Array = []
	if game.plan["socks"] == other:
		notes.append("%s has the socks" % T.NAMES[other])
	if game.plan["pillow"] == other:
		notes.append("%s has the pillow decoy" % T.NAMES[other])
	if not notes.is_empty():
		_label("(" + ", ".join(PackedStringArray(notes)) + ". Tapping takes it.)", body, 16, Color(0.6, 0.65, 0.85))


func _noa_panel() -> void:
	_label("Noa, the Baby: her cry pulls Mom across the house to settle her (4.5 s). Then Mom checks the beds.", body, 19, T.COLORS["noa"])
	var cry: float = game.plan["cry"]
	var row := _row("Cry")
	var val := Label.new()
	val.custom_minimum_size = Vector2(64, 0)
	val.text = T.fmt(cry) if cry >= 0.0 else "off"
	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = T.LEAVE_MAX
	sl.step = 1
	sl.value = maxf(cry, 0.0)
	sl.editable = cry >= 0.0
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(0, 44)
	var toggle := _btn("On" if cry >= 0.0 else "Off", func() -> void: pass, true, cry >= 0.0)
	toggle.size_flags_horizontal = Control.SIZE_FILL
	toggle.custom_minimum_size = Vector2(90, 52)
	toggle.toggled.connect(func(on: bool) -> void:
		toggle.text = "On" if on else "Off"
		sl.editable = on
		val.text = T.fmt(sl.value) if on else "off"
		game.set_cry(sl.value if on else -1.0)
	)
	sl.value_changed.connect(func(v: float) -> void:
		val.text = T.fmt(v)
		game.set_cry(v)
	)
	row.add_child(toggle)
	row.add_child(sl)
	row.add_child(val)
	if game.adapt.get("ignore_cry", false):
		_label("Mom has caught on: she'll ignore the next cry.", body, 18, Color(1, 0.6, 0.5))


func _lego_panel() -> void:
	_label("Tap a walkway on the map to drop the LEGO. A walking grown-up who steps on it stops for %d s, but yells (loud!)." % int(T.LEGO_STUN), body, 19)
	var row := _row("LEGO")
	row.add_child(_btn("Remove", func() -> void: game.set_lego(null)))
	if game.adapt.get("slippers", false):
		_label("The grown-ups wear slippers now. LEGO stops nobody.", body, 18, Color(1, 0.6, 0.5))


func update_plan_info() -> void:
	top_label.text = "Peeks left: %d" % game.peeks_left()
	if info == null or not is_instance_valid(info):
		return
	var pred: Dictionary = game.prediction
	if pred.is_empty():
		return
	timeline.set_data(pred["sim"], pred["know"], false)
	var txt := "[b]Intel[/b]\n"
	for l in Predictor.intel(game.house, game.night, game.plan, game.adapt):
		txt += "• " + l + "\n"
	var warns: Array = pred["warnings"]
	if warns.is_empty():
		txt += "\n[color=#8fe39a][b]No warnings[/b] (for what you've peeked at).[/color]\n"
	else:
		txt += "\n[b][color=#ffb070]Warnings[/color][/b]\n"
		for w in warns:
			txt += "[color=#ffb070]• " + w + "[/color]\n"
	var sim = pred["sim"]
	var last := 0.0
	for tr in sim.trips:
		last = maxf(last, tr["home"])
	if sim.delivered > 0:
		txt += "\n[b]Prediction:[/b] %d/%d cookies, back in bed by %s." % [sim.delivered, T.COOKIES_GOAL, T.fmt(last)]
	else:
		txt += "\n[b]Prediction:[/b] no cookies. Send someone on a cookie run."
	info.text = txt


# --- Night -----------------------------------------------------------------

func show_night() -> void:
	_clear(body)
	_clear(footer)
	_log.clear()
	night_pick.disabled = true
	status_label = _label("", body, 22, Color.WHITE)
	var speed_row := _row("Speed")
	_choice(speed_row, [["1x", 1.0], ["2x", 2.0], ["3x", 3.0]], game.speed,
		func(v) -> void: game.speed = v)
	for id in ["mom", "dad"]:
		var row := _row(T.NAMES[id])
		var bar := ProgressBar.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size = Vector2(0, 26)
		bar.show_percentage = false
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var l := Label.new()
		l.custom_minimum_size = Vector2(150, 0)
		row.add_child(l)
		meters[id] = {"bar": bar, "label": l}
	timeline = Timeline.new()
	body.add_child(timeline)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.scroll_active = false
	log_label.add_theme_font_size_override("normal_font_size", 18)
	body.add_child(log_label)
	footer.add_child(_btn("Skip to morning", func() -> void: game.skip_night()))


func update_night(sim) -> void:
	status_label.text = "%s / %s   Cookies %d/%d   Excuse: %s" % [
		T.fmt(sim.t), T.fmt(T.NIGHT_LEN), sim.delivered, T.COOKIES_GOAL, "used" if sim.excuse_used else "ready"]
	for id in meters:
		var a: Dictionary = sim.adults[id]
		var bar: ProgressBar = meters[id]["bar"]
		var l: Label = meters[id]["label"]
		bar.max_value = a["threshold"]
		bar.value = a["meter"]
		l.text = "zzz %d/%d" % [int(a["meter"]), int(a["threshold"])] if a["asleep"] else "AWAKE"
	timeline.set_data(sim, {}, true)


func log_event(e: Dictionary) -> void:
	var who: String = e["who"]
	var line := "[color=#8890b0]%s[/color] " % T.fmt(e["t"])
	if who == "":
		line += "[color=#ffd166]%s[/color]" % e["text"]
	else:
		line += "[color=#%s]%s:[/color] %s" % [T.COLORS[who].to_html(false), T.NAMES[who], e["text"]]
	_log.append(line)
	while _log.size() > 7:
		_log.pop_front()
	log_label.text = "\n".join(PackedStringArray(_log))


# --- Result ----------------------------------------------------------------

func show_result(sim, stars: int, best: int) -> void:
	_clear(body)
	_clear(footer)
	night_pick.disabled = false
	var star_text := ""
	for i in 3:
		star_text += "[*] " if i < stars else "[ ] "
	var title := "BUSTED!" if sim.busted else ("PERFECT HEIST!" if stars == 3 else ("Sweet success" if stars > 0 else "No cookies..."))
	_label(title, body, 40, Color(1, 0.4, 0.4) if sim.busted else Color(1, 0.85, 0.4))
	_label("%s  %d star%s   (best %d)" % [star_text, stars, "" if stars == 1 else "s", best], body, 28, Color(1, 0.85, 0.4))
	var lines: Array = []
	lines.append("Cookies: %d/%d" % [sim.delivered, T.COOKIES_GOAL])
	lines.append("Excuse card: %s" % ("used" if sim.excuse_used else "unused"))
	if sim.busted:
		lines.append(sim.busted_reason)
	_label("\n".join(PackedStringArray(lines)), body, 21)
	_label("Stars: 1 = at least one cookie, 2 = all three, 3 = all three without the excuse card.", body, 16, Color(0.6, 0.65, 0.85))
	timeline = Timeline.new()
	body.add_child(timeline)
	timeline.set_data(sim, {}, true)
	footer.add_child(_btn("Try again", func() -> void: game.retry()))
	if game.night_index < Nights.NAMES.size() - 1:
		footer.add_child(_btn("Next night", func() -> void: game.start_night(game.night_index + 1)))
