extends RefCounted
## All tuning numbers from the Build spec (v3 prototype).
## Units are meters on the floor plan; times are seconds of game time.

const DT := 1.0 / 60.0
const NIGHT_LEN := 90.0
const LAST_TRIP := 62.0
const LEAVE_MAX := 60.0
const COOKIES_GOAL := 3
const PEEKS := 2

# Noise
const FALLOFF := 14.0          # a * 1 / (1 + d^2 / FALLOFF)
const WALL_HALL := 0.6         # hallway <-> room
const WALL_ROOM := 0.45        # room <-> other room
const SLEEP_DRAIN := 2.0       # sleep meter drain per second
const THRESH_RISE_MIN := 3.0   # threshold rise after going back to bed
const THRESH_RISE_MULT := 0.6  #   = max(MIN, MULT * starting threshold)
const CREAK := 22.0
const CREAK_SOCKS := 2.0
const LEGO_YELL := 22.0
const WAKE_NOISE := 5.0
const CRY_FIRST := 6.0
const CRY_REPEAT := 2.0
const CRY_INTERVAL := 1.3
const CRY_IGNORED_LEN := 8.0

# Catching
const CATCH_NEAR := 1.0
const CATCH_ROOM := 2.0

# Tools
const LEGO_STUN := 3.0
const LEGO_RADIUS := 0.35
const BOARD_RADIUS := 0.3

# Grown-ups
const MOM_SPEED := 1.25
const DAD_SPEED := 1.15
const SETTLE_TIME := 4.5
const INVESTIGATE_TIME := 2.0
const WATER_TIME := 3.0
const SNACK_TIME := 4.0
const BATH_TIME := 5.0

const KIDS := {
	"maya": {
		"name": "Maya", "title": "The Sneaker", "blurb": "quiet but slow",
		"speed": 1.15, "walk_noise": 2.2, "hall_mult": 1.0, "cap": 1,
		"grab_counter": 1.0, "grab_fridge": 3.4, "fridge_noise": 12.0,
		"color": Color(0.96, 0.47, 0.66),
	},
	"ben": {
		"name": "Ben", "title": "Big Brother", "blurb": "fast, carries 2, stomps",
		"speed": 1.55, "walk_noise": 8.0, "hall_mult": 1.4, "cap": 2,
		"grab_counter": 0.8, "grab_fridge": 1.0, "fridge_noise": 5.0,
		"color": Color(0.38, 0.62, 1.0),
	},
}

const NAMES := {"maya": "Maya", "ben": "Ben", "noa": "Noa", "mom": "Mom", "dad": "Dad"}
const COLORS := {
	"maya": Color(0.96, 0.47, 0.66),
	"ben": Color(0.38, 0.62, 1.0),
	"noa": Color(1.0, 0.86, 0.45),
	"mom": Color(0.72, 0.5, 0.95),
	"dad": Color(0.45, 0.82, 0.55),
}

const ERRAND_TEXT := {
	"check": "checks the kids' beds",
	"water": "gets a glass of water",
	"snack": "raids the fridge",
	"bath": "uses the bathroom",
	"settle": "settles the baby",
	"investigate": "investigates a noise",
}

const ERRAND_LINES := {
	"mom": {
		"check": "Just checking on my angels...",
		"water": "So thirsty...",
		"settle": "Coming, Noa...",
		"investigate": "I can hear you.",
	},
	"dad": {
		"snack": "Just one little snack...",
		"bath": "*yaaawn*",
		"investigate": "Who's there?",
	},
}

# [excuse, comeback]
const EXCUSES := [
	["I need water.", "You *just* had water!"],
	["Bad dream...", "Dreams don't eat cookies."],
	["I have to pee.", "The bathroom is the OTHER way."],
	["I heard a noise!", "Yes. It was you."],
]


static func fmt(sec: float) -> String:
	var s := int(maxf(sec, 0.0))
	return "%d:%02d" % [s / 60, s % 60]
