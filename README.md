# Past Bedtime: v1 (block placeholders)

A Godot 4 build of the design doc's core loop. Siblings sneak to the cookie jar and the parents are the security. All art is placeholder boxes, which will be replaced later. This build is for testing the mechanics and the design.

## Run it

1. Install **Godot 4.3+** (standard build, not .NET).
2. Open `project.godot` in the editor and press **F5**.
   The window is a 720×1280 portrait phone frame. The mouse acts as touch: click to tap, drag to pan, wheel to zoom.

Run these from the repo root. Headless balance test (prints a star histogram per night and strategy):

```sh
godot --headless --path . -s res://tools/balance_test.gd
godot --headless --path . -s res://tools/balance_test.gd -- --runs=32 --planner-runs=8
```

Screenshots of each phase (needs a display, or `xvfb-run` on Linux):

```sh
godot --path . --rendering-method gl_compatibility -s res://tools/screenshots.gd -- --out=/tmp/shots
```

iOS: **Project > Export > Add… > iOS**, then set your Apple team ID and bundle ID. Exporting needs a Mac with Xcode.

## How a night plays

1. **Peek.** The parents' room, living room and kitchen start dark. Tap one to peek (2 per night). A peek reveals that room's grown-up (wake threshold and schedule), its creaky boards and where the jar is.
2. **Plan on the map.** Tap a kid's bed, or use the Maya / Ben / Noa / LEGO tabs. Set each kid's job, leave time (0:00–1:00), route (living room or hallway) and gear (socks, pillow decoy). Noa can cry at a set time. On the LEGO tab, tap a walkway to drop the LEGO.
   The selected kid's route is drawn as dots with jar and bed time tags. Known grown-up routes are drawn in red.
3. **Read the timeline and warnings.** They are predicted from what you've peeked at.
4. **Lights out.** The plan runs for 90 s of game time at 1–3× speed, or you can skip to the end.
5. **Result.** 1 star for at least one cookie, 2 for all three, 3 for all three without using the excuse card.

## Code map

| Path | What |
| --- | --- |
| `scripts/sim/tuning.gd` | Every number from the Build spec, plus the lines and excuses |
| `scripts/sim/house.gd` | Rooms, walls and doors, the 24-node waypoint graph (AStar3D), route blocking, noise falloff |
| `scripts/sim/nights.gd` | Nights 1–3 and Bonus, re-rolled from a seed on every attempt |
| `scripts/sim/simulation.gd` | Deterministic 60 Hz sim: kids, grown-up errands, sleep meters, LEGO, baby cry, catches, excuse card, stars |
| `scripts/sim/predictor.gd` | Known info, predicted trips and errands (the same sim in `predict` mode) and warnings |
| `scripts/game/main.gd` | Game flow, map taps, peeks, camera (orthographic, front-right, 37°), adaptation, save |
| `scripts/game/house_view.gd` | Block-art house, fog, actors, speech bubbles, lights and the plan overlay |
| `scripts/game/ui.gd`, `timeline.gd` | Portrait UI built in code, and the timeline |
| `tools/balance_test.gd` | Headless balance harness |
| `tools/screenshots.gd` | Renders a screenshot of each game phase |

The simulation never touches nodes, so it runs the same way in the game, in predictions and in the headless test.

## Rules implemented (from the Build spec)

- **Movement:** speeds per the spec (Maya 1.15, Ben 1.55, Mom 1.25, Dad 1.15). A kid's route choice works by blocking one door edge. Grown-ups always take the shortest path.
- **Noise:** loudness × 1/(1 + d²/14), × 0.6 through a hallway wall and × 0.45 between other rooms.
  - Sleep meters drain at 2/s. A grown-up who crosses their threshold wakes and investigates the loudest recent spot.
  - The threshold rises by max(3, 0.6 × base) after every return to bed.
  - Loudness: walking noise per kid (Ben × 1.4 in the hallway), creaky boards 22 (2 with socks), fridge climb (Maya 12, Ben 5), LEGO yell 22, a grown-up waking 5, Noa's cry 6 and then 2 every 1.3 s.
- **Errands:** check, water, snack, bath, settle the baby and investigate. After any time out of bed, Mom checks the beds.
- **Catching:**
  - An awake grown-up catches a kid within 1.0, or within 2.0 if they share a room.
  - A bed check catches every kid who is out without the decoy.
  - The first catch uses the excuse card: the kid goes back to bed empty-handed and is out for the night. A second catch means busted.
  - A kid still out at 1:30 is busted.
- **Trips:** a kid leaves at their set time and makes trips until 3 cookies are claimed. No new trips start after 1:02.
- **Adaptation:** based on the last two nights played. Noa's cry in both means Mom ignores the next cry. The LEGO in both means the grown-ups wear slippers and the LEGO stops nobody.

## Not in v1 yet

Other crew (Twins, Techie, Dog), other tools (squeaky toy, skateboard, snoring recorder, walkie-talkies, flashlight), Pillow Fort HQ, skill trees, nightly modifiers, worlds 2–7, audio, and data in `.tres` Resources. Tuning currently lives in `tuning.gd` and `nights.gd`.
