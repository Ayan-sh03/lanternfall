extends Node
## Entry point: owns the HUD, the current run and the save files, and moves
## between title, story, play and the endings.

const Art = preload("res://scripts/art.gd")
const GameS = preload("res://scripts/game.gd")
const HudS = preload("res://scripts/hud.gd")
const Story = preload("res://scripts/story.gd")
const AutoS = preload("res://scripts/autotest.gd")
const ShowS = preload("res://scripts/showcase.gd")
const Nemesis = preload("res://scripts/nemesis.gd")
const WorldViewS = preload("res://scripts/world_view.gd")

const SLOTS := 3

var game = null
var hud
## The world is drawn into this small picture and scaled up (see world_view.gd).
var world: WorldViewS
var boss_seen := false
var slot := 0
var pending_depth := 1
## The way down for the run in hand: "pilgrim" wakes at the last lamp after a
## fall, "descent" has one wick and a fall ends it (see Story.MODES). Chosen
## when a slot is started, kept in the save; tests start as pilgrims.
var mode := "pilgrim"
## The depth the last Descent ended on, for the death screen.
var fallen_depth := 0
## Set once a run has ended (a win), so nothing writes its slot back.
var run_over := false
## Depths reached at least once (for the depth-select screen) and endings seen.
var profile := {"max_depth": 1, "endings": [false, false], "sound": true, "haptics": true, "fps": false,
	"fast": false, "auto_fast": false,
	# What every descent leaves behind: embers to spend in the town, the town's
	# lit lamps, running tallies for the deeds, deeds done, the best runs, and
	# whether the lamp's resolve (an optional easing) is accepted.
	"embers": 0, "town": [], "tally": {}, "feats": [], "best": {}, "resolve": false,
	# The foe that put Wren out and earned a name for it (see nemesis.gd); empty if none.
	"nemesis": {},
	# Lessons the lamp has taught (Story.LESSONS ids) and kinds of foe met, for the bestiary.
	"taught": [], "seen": []}
## What last put Wren out, as an entry in Story.CAUSES (empty if nothing yet).
var last_cause := ""
## Embers earned since the run (or the life) began, for the death screen.
var run_embers := 0
var profile_dirty := false
## The nemesis waits on the next floor entered after it was made or fed.
var nem_due := false
## What the nemesis made of the last death, for the death screen.
var nem_news := ""
## Test and recording runs switch this off so they never touch the player's progress.
var persist := true
## True on phones and tablets (or with --touch, for trying the pad on a desktop).
var touch := false
var perf_ms := 0
var perf_n := 0
var perf_bad := 0
## Draw the dungeon in 3D. The 3D builds start that way (their export preset
## carries the "view3d" feature), the classic ones flat; --3d and --2d choose
## when running from source, and F3 switches either way, live.
var use_3d := false


func _ready() -> void:
	randomize()
	Art.build()
	get_window().title = "Lanternfall"
	use_3d = (OS.has_feature("view3d") or OS.get_cmdline_user_args().has("--3d")) \
		and not OS.get_cmdline_user_args().has("--2d")
	touch = OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")
	if touch:
		# The HUD turns touches into clicks itself, one finger at a time.
		Input.emulate_mouse_from_touch = false
	else:
		Input.set_custom_mouse_cursor(Art.cursor(), Input.CURSOR_ARROW, Vector2(16, 16))
	if not OS.has_feature("mobile"):
		_set_icon()
	_load_profile()
	world = WorldViewS.new()
	add_child(world)
	hud = HudS.new()
	hud.main = self
	hud.touch = touch
	add_child(hud)
	apply_options()
	hud.show_title()
	Sfx.play_music("title")
	if OS.get_cmdline_user_args().has("--showcase"):
		persist = false
		var sc = ShowS.new()
		sc.main = self
		add_child(sc)
	if OS.get_cmdline_user_args().has("--autotest"):
		persist = false
		var a = AutoS.new()
		a.main = self
		add_child(a)


func _set_icon() -> void:
	var src: Image = Art.image_of(Art.tex["player0"])
	var icon := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	icon.blit_rect(src, Rect2i(0, 0, src.get_width(), src.get_height()), Vector2i((24 - src.get_width()) / 2, 1))
	icon.resize(128, 128, Image.INTERPOLATE_NEAREST)
	DisplayServer.set_icon(icon)


## The game lives in the world picture's own viewport, which hears nothing by
## itself; whatever the HUD leaves is handed on to it.
func _unhandled_input(ev: InputEvent) -> void:
	if game != null and is_instance_valid(game) and not game.is_queued_for_deletion():
		game._unhandled_input(ev)


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.physical_keycode == KEY_F11:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif ev.physical_keycode == KEY_F3:
			use_3d = not use_3d
			if game != null and game.view3d != null:
				game.view3d.set_active(use_3d)
		elif ev.physical_keycode == KEY_M:
			profile["sound"] = not profile["sound"]
			apply_options()
			_save_profile()


func _notification(what: int) -> void:
	if hud == null:
		return
	var playing: bool = game != null and hud.modal == "" and not game.dead and not game.bot
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_keep_descent()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# The phone's back gesture pauses, and un-pauses.
		if hud.modal == "pause":
			hud._close_modal()
		elif hud.modal == "codex":
			hud.close_codex()
		elif playing:
			hud.show_pause()
	elif what == NOTIFICATION_APPLICATION_PAUSED and touch and playing:
		hud.show_pause()


## Sound, and how the picture is drawn. "Fast" draws the whole frame at 720 lines
## and scales it up: softer, but far less work for a weak graphics chip.
func apply_options() -> void:
	Sfx.muted = not profile["sound"]
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT if profile["fast"] \
		else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS


## A phone that cannot hold the pace at full sharpness is dropped to the fast
## picture, once, rather than left to stutter. The pause screen switches it back.
func _process(_dt: float) -> void:
	if not touch or profile["fast"] or profile["auto_fast"] or game == null or hud.blocking():
		perf_n = 0
		return
	var now := Time.get_ticks_msec()
	if perf_n == 0:
		perf_ms = now
	perf_n += 1
	if now - perf_ms < 5000:
		return
	var fps := perf_n * 1000.0 / (now - perf_ms)
	perf_n = 0
	perf_bad = perf_bad + 1 if fps < 48.0 else 0
	if perf_bad >= 2:
		profile["fast"] = true
		profile["auto_fast"] = true
		apply_options()
		_save_profile()
		hud.say("The picture is now set to fast, to keep the pace. The pause screen can change it back.", 6.0, hud.C_EMBER)


# --- Save files -----------------------------------------------------------------

## `--savetag=<name>` keeps a test run's saves apart from another run's, so
## checks can run side by side in several checkouts without sharing slot 9.
func _slot_path(i: int) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--savetag="):
			return "user://save_%s_%d.json" % [a.get_slice("=", 1).validate_filename(), i]
	return "user://save_%d.json" % i


func read_save(i: int) -> Dictionary:
	var path := _slot_path(i)
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.has("depth") and data.has("stats") and data.has("seed"):
		return data
	return {}


## Called by the game at each save point (arriving at a depth, or resting at a lamp).
func write_save(data: Dictionary) -> void:
	if profile_dirty:
		_save_profile()
	data["time"] = Time.get_unix_time_from_system()
	data["boss_seen"] = boss_seen
	data["mode"] = mode
	# A Descent counts its embers from the very top, across closing the app.
	data["run_embers"] = run_embers
	var f := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()


func delete_save(i: int) -> void:
	if FileAccess.file_exists(_slot_path(i)):
		DirAccess.remove_absolute(_slot_path(i))


## The way down a save was made on. Saves from before there was a choice were
## all pilgrimages.
static func mode_of(s: Dictionary) -> String:
	var m := str(s.get("mode", "pilgrim"))
	return m if Story.MODES.has(m) else "pilgrim"


func descent() -> bool:
	return mode == "descent"


## A Descent left mid-floor (quit, window closed, app sent away) is written
## where it stands, wounds and all, so leaving is never a way out of a fall.
## A Descent closed while Wren is already falling is over.
func _keep_descent() -> void:
	if not descent() or run_over or game == null or not is_instance_valid(game) or game.depth <= 0:
		return
	if game.dead:
		delete_save(slot)
	else:
		game.save_game(int(read_save(slot).get("lamp_idx", -1)))


## The most recently written slot, or -1 if there are no saves.
func latest_slot() -> int:
	var best := -1
	var best_t := -1.0
	for i in SLOTS:
		var s := read_save(i)
		if not s.is_empty() and float(s.get("time", 0.0)) > best_t:
			best_t = float(s.get("time", 0.0))
			best = i
	return best


func _slot_cards() -> Array:
	var cards: Array = []
	for i in SLOTS:
		var s := read_save(i)
		if s.is_empty():
			cards.append({"name": "Slot %d" % (i + 1), "desc": "Empty", "icon": "lamp0", "col": Color(0.5, 0.47, 0.44)})
		else:
			var d := clampi(int(s["depth"]), 1, Story.DEPTHS.size())
			var secs := int(s.get("run_time", 0.0))
			var m: Dictionary = Story.MODES[mode_of(s)]
			cards.append({"name": "Slot %d" % (i + 1), "icon": "lamp1" if mode_of(s) == "pilgrim" else m["icon"],
				"col": Color(1.0, 0.72, 0.35) if mode_of(s) == "pilgrim" else m["col"],
				"desc": "Depth %s\n%s\n%s\nLevel %d      %d:%02d" % [Story.ROMAN[d - 1], Story.DEPTHS[d - 1]["name"],
					m["name"], int(s["level"]), secs / 60, secs % 60]})
	return cards


func _load_profile() -> void:
	if not FileAccess.file_exists("user://profile.json"):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string("user://profile.json"))
	if data is Dictionary:
		profile["max_depth"] = clampi(int(data.get("max_depth", 1)), 1, Story.DEPTHS.size())
		var e = data.get("endings", [false, false])
		if e is Array and e.size() == 2:
			profile["endings"] = [bool(e[0]), bool(e[1])]
		for k in ["sound", "haptics", "fps", "fast", "auto_fast", "resolve"]:
			if data.has(k):
				profile[k] = bool(data[k])
		profile["embers"] = maxi(0, int(data.get("embers", 0)))
		for k in ["town", "feats", "taught", "seen"]:
			var a = data.get(k, [])
			profile[k] = (a as Array).duplicate() if a is Array else []
		for k in ["tally", "best"]:
			var d = data.get(k, {})
			if d is Dictionary:
				for n in d:
					profile[k][n] = int(d[n])
		# Every run before there was a choice was a pilgrimage.
		if not profile["best"].has("depth_pilgrim") and profile["best"].has("depth"):
			profile["best"]["depth_pilgrim"] = int(profile["best"]["depth"])
		var nm = data.get("nemesis", {})
		if nm is Dictionary and Nemesis.KINDS.has(str(nm.get("kind", ""))) and str(nm.get("name", "")) != "":
			profile["nemesis"] = {"kind": str(nm["kind"]), "name": str(nm["name"]),
				"rank": clampi(int(nm.get("rank", 1)), 1, Nemesis.RANK.size() - 1), "wins": int(nm.get("wins", 1))}


func _save_profile() -> void:
	profile_dirty = false
	if not persist:
		return
	var f := FileAccess.open("user://profile.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(profile))
		f.close()


## The game reports each depth as it is entered; this unlocks it for depth select.
## Each way down keeps its own deepest depth, too.
func reached(depth: int) -> void:
	var b: Dictionary = profile["best"]
	var k := "depth_" + mode
	if depth > int(b.get(k, 0)):
		b[k] = depth
		profile_dirty = true
	if depth > int(profile["max_depth"]):
		profile["max_depth"] = depth
	if profile_dirty:
		_check_feats()
		_save_profile()


# --- What carries over between descents --------------------------------------------

## Embers go into the profile straight away: whatever happens below, what was
## earned is kept. The file itself is written at the next save point. On one
## wick they burn half again as bright: a Descent risks more, so it pays more.
func bank(n: int) -> void:
	if n <= 0:
		return
	if descent():
		n = roundi(n * 1.5)
	profile["embers"] = int(profile["embers"]) + n
	run_embers += n
	profile_dirty = true


func has_lamp(id: String) -> bool:
	return (profile["town"] as Array).has(id)


## Lights a lamp in the town if the embers are there. Returns whether it lit.
func light_town_lamp(id: String) -> bool:
	if has_lamp(id):
		return false
	for l in Story.TOWN:
		if l["id"] == id and int(profile["embers"]) >= int(l["cost"]):
			profile["embers"] = int(profile["embers"]) - int(l["cost"])
			profile["town"].append(id)
			_check_feats()
			_save_profile()
			return true
	return false


## Counts toward the deeds: parries, kills, deaths and the like.
func tally(stat: String, n: int = 1) -> void:
	profile["tally"][stat] = int(profile["tally"].get(stat, 0)) + n
	profile_dirty = true
	_check_feats()


## Whether a lesson has been taught on this profile (see game.teach).
func knows(id: String) -> bool:
	return (profile["taught"] as Array).has(id)


func learn(id: String) -> void:
	if not knows(id):
		profile["taught"].append(id)
		profile_dirty = true


## A kind of foe met, for the bestiary. The scraps of an Ink Maw are an Ink Maw.
func saw(kind: String) -> void:
	if kind == "slimelet":
		kind = "slime"
	if not (profile["seen"] as Array).has(kind):
		profile["seen"].append(kind)
		profile_dirty = true


func feat_progress(f: Dictionary) -> int:
	match f["stat"]:
		"max_depth":
			return int(profile["max_depth"])
		"town":
			return (profile["town"] as Array).size()
		"descent_depth":
			return int(profile["best"].get("depth_descent", 0))
	return int(profile["tally"].get(f["stat"], 0))


## Pays out any deed just completed, once, and says so.
func _check_feats() -> void:
	for f in Story.FEATS:
		if (profile["feats"] as Array).has(f["id"]) or feat_progress(f) < int(f["goal"]):
			continue
		profile["feats"].append(f["id"])
		profile["embers"] = int(profile["embers"]) + int(f["reward"])
		profile_dirty = true
		if hud != null:
			hud.deed(f)


## The lamp's resolve: with it accepted, each fall makes the next descent a
## little gentler (a chance for a blow to be turned), up to two in five.
func resolve_chance() -> float:
	if not profile["resolve"]:
		return 0.0
	return minf(0.4, 0.03 * int(profile["tally"].get("deaths", 0)))


func set_resolve(on: bool) -> void:
	profile["resolve"] = on
	_save_profile()


## Keeps the best of each run: deepest reached, most put out, quickest finish.
func record_run(depth: int, kills: int, secs: float, won: bool) -> void:
	var b: Dictionary = profile["best"]
	b["depth"] = maxi(int(b.get("depth", 0)), depth)
	b["kills"] = maxi(int(b.get("kills", 0)), kills)
	if won and (int(b.get("win_secs", 0)) == 0 or int(secs) < int(b["win_secs"])):
		b["win_secs"] = int(secs)
	profile_dirty = true


# --- Title screen actions -------------------------------------------------------

func continue_game() -> void:
	var i := latest_slot()
	if i < 0:
		pick_new()
	else:
		load_slot(i)


func pick_new() -> void:
	hud.show_choice("New descent", "Choose a slot. A slot that is in use will be overwritten.", _slot_cards(),
		_new_in_slot, hud.show_title)


## A slot picked for a new run: next, the way down. The old save is only
## cleared once that is chosen, so backing out loses nothing.
func _new_in_slot(i: int) -> void:
	slot = i
	pick_mode()


## The two ways down, with how far each has gone so far.
func pick_mode() -> void:
	var sub := "Chosen once, for the whole of this descent."
	var b: Dictionary = profile["best"]
	var parts := PackedStringArray()
	for k in Story.MODES:
		var deep := int(b.get("depth_" + k, 0))
		if deep > 0:
			parts.append("%s: deepest %s" % [Story.MODES[k]["name"], Story.ROMAN[clampi(deep, 1, Story.DEPTHS.size()) - 1]])
	if int(profile["tally"].get("descent_wins", 0)) > 0:
		parts.append("Descents finished: %d" % int(profile["tally"]["descent_wins"]))
	if not parts.is_empty():
		sub += "      " + "    ".join(parts)
	var cards: Array = []
	for k in Story.MODES:
		var m: Dictionary = Story.MODES[k]
		cards.append({"name": m["name"], "icon": m["icon"], "col": m["col"], "desc": m["desc"]})
	hud.show_choice("How will you go down?", sub, cards, _mode_chosen, pick_new)


func _mode_chosen(i: int) -> void:
	mode = Story.MODES.keys()[i]
	delete_save(slot)
	start_run()


func pick_load() -> void:
	hud.show_choice("Load a descent", "Each lamp you light, and each depth you reach, is a save point.", _slot_cards(),
		_load_checked, hud.show_title)


func _load_checked(i: int) -> void:
	if read_save(i).is_empty():
		pick_load()
	else:
		load_slot(i)


func load_slot(i: int) -> void:
	slot = i
	var s := read_save(i)
	if s.is_empty():
		hud.show_title()
		return
	boss_seen = bool(s.get("boss_seen", false))
	hud.fade_through(func(): new_game(int(s["depth"]), s))


func pick_depth() -> void:
	hud.show_depths(int(profile["max_depth"]), _depth_chosen, hud.show_title)


func _depth_chosen(depth: int) -> void:
	pending_depth = depth
	hud.show_choice("Depth %s  -  %s" % [Story.ROMAN[depth - 1], Story.DEPTHS[depth - 1]["name"]],
		"A pilgrimage from this depth. Choose a slot; one in use will be overwritten.", _slot_cards(),
		_start_depth_in_slot, pick_depth)


## Starting partway down is always a pilgrimage: a Descent is the whole way on
## one wick, or its depth record would mean nothing.
func _start_depth_in_slot(i: int) -> void:
	slot = i
	mode = "pilgrim"
	delete_save(i)
	boss_seen = false
	if pending_depth <= 1:
		start_run()
	else:
		hud.fade_through(func(): new_game(pending_depth, {}, true))


func start_run() -> void:
	boss_seen = false
	hud.show_cards(Story.INTRO, func(): hud.fade_through(func(): new_game(1)))


## A fresh run goes down the way `mode` already says; a restored one the way
## its save says.
func new_game(depth: int, restore: Dictionary = {}, prepared: bool = false) -> void:
	_drop_game()
	run_embers = 0
	run_over = false
	if not restore.is_empty():
		mode = mode_of(restore)
		if descent():
			run_embers = int(restore.get("run_embers", 0))
	hud.show_mode(mode)
	game = GameS.new()
	game.main = self
	game.hud = hud
	game.view = world
	world.game = game
	world.vp.add_child(game)
	hud.game = game
	game.start(depth, restore, prepared)


func _drop_game() -> void:
	if game != null:
		game.queue_free()
	game = null
	hud.game = null
	hud.floats.clear()
	hud.say_q.clear()
	hud.sub_t = 0.0
	hud.card_t = 0.0


func player_died() -> void:
	last_cause = game.last_cause
	nem_news = Nemesis.on_death(self, game.last_cause, game.last_by_nem, game.rng)
	tally("deaths")
	record_run(game.depth, game.kills, game.run_time, false)
	if descent():
		# One wick: the run is over and its slot with it. Embers, the town and
		# the deeds were never in the slot, so they stay.
		fallen_depth = game.depth
		delete_save(slot)
	_save_profile()
	hud.show_death()


## After a death: wake at the last save point with the lamp's blessing. A
## Descent has no lamp to wake at, only the top of the stair again.
func retry() -> void:
	if descent():
		new_descent()
		return
	var s := read_save(slot)
	if s.is_empty():
		hud.fade_through(func(): new_game(1))
		return
	s["revive"] = true
	hud.fade_through(func(): new_game(int(s["depth"]), s))


## Another Descent in the same slot, from the first depth, with nothing but
## the town's lamps.
func new_descent() -> void:
	mode = "descent"
	delete_save(slot)
	boss_seen = false
	hud.fade_through(func(): new_game(1))


## From the end of a Descent straight to the town, to spend what was kept.
func to_town() -> void:
	hud.fade_through(func():
		_to_title_now()
		hud.show_town())


func to_title() -> void:
	_keep_descent()
	hud.fade_through(_to_title_now)


func _to_title_now() -> void:
	if profile_dirty:
		_save_profile()
	_drop_game()
	hud.show_title()
	Sfx.play_music("title")


## kind 0: carry the Ember up. kind 1: open the cage.
func ending(kind: int) -> void:
	run_over = true
	delete_save(slot)
	profile["endings"][kind] = true
	if game != null:
		record_run(game.depth, game.kills, game.run_time, true)
	if descent():
		tally("descent_wins")
	_save_profile()
	Sfx.play_music("keep" if kind == 0 else "dawn")
	var cards: Array = Story.ENDING_KEEP if kind == 0 else Story.ENDING_FREE
	hud.fade_through(func(): hud.show_cards(cards, func(): hud.show_end(kind)))


func quit_game() -> void:
	_keep_descent()
	get_tree().quit()
