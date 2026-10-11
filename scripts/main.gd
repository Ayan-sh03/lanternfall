extends Node
## Entry point: owns the HUD, the current run and the save files, and moves
## between title, story, play and the endings.

const Art = preload("res://scripts/art.gd")
const GameS = preload("res://scripts/game.gd")
const HudS = preload("res://scripts/hud.gd")
const Story = preload("res://scripts/story.gd")
const AutoS = preload("res://scripts/autotest.gd")
const ShowS = preload("res://scripts/showcase.gd")

const SLOTS := 3

var game = null
var hud
var boss_seen := false
var slot := 0
var pending_depth := 1
## Depths reached at least once (for the depth-select screen) and endings seen.
var profile := {"max_depth": 1, "endings": [false, false]}
## Test and recording runs switch this off so they never touch the player's progress.
var persist := true


func _ready() -> void:
	randomize()
	Art.build()
	get_window().title = "Lanternfall"
	_set_icon()
	Input.set_custom_mouse_cursor(Art.cursor(), Input.CURSOR_ARROW, Vector2(16, 16))
	_load_profile()
	hud = HudS.new()
	hud.main = self
	add_child(hud)
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
	var src: Image = Art.tex["player0"].get_image()
	var icon := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	icon.blit_rect(src, Rect2i(0, 0, src.get_width(), src.get_height()), Vector2i((24 - src.get_width()) / 2, 1))
	icon.resize(128, 128, Image.INTERPOLATE_NEAREST)
	DisplayServer.set_icon(icon)


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.physical_keycode == KEY_F11:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif ev.physical_keycode == KEY_M:
			Sfx.muted = not Sfx.muted


# --- Save files -----------------------------------------------------------------

func _slot_path(i: int) -> String:
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
	data["time"] = Time.get_unix_time_from_system()
	data["boss_seen"] = boss_seen
	var f := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()


func delete_save(i: int) -> void:
	if FileAccess.file_exists(_slot_path(i)):
		DirAccess.remove_absolute(_slot_path(i))


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
			cards.append({"name": "Slot %d" % (i + 1), "icon": "lamp1", "col": Color(1.0, 0.72, 0.35),
				"desc": "Depth %s\n%s\n\nLevel %d      %d:%02d" % [Story.ROMAN[d - 1], Story.DEPTHS[d - 1]["name"],
					int(s["level"]), secs / 60, secs % 60]})
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


func _save_profile() -> void:
	if not persist:
		return
	var f := FileAccess.open("user://profile.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(profile))
		f.close()


## The game reports each depth as it is entered; this unlocks it for depth select.
func reached(depth: int) -> void:
	if depth > int(profile["max_depth"]):
		profile["max_depth"] = depth
		_save_profile()


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


func _new_in_slot(i: int) -> void:
	slot = i
	delete_save(i)
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
		"Choose a slot for this descent. A slot that is in use will be overwritten.", _slot_cards(),
		_start_depth_in_slot, pick_depth)


func _start_depth_in_slot(i: int) -> void:
	slot = i
	delete_save(i)
	boss_seen = false
	if pending_depth <= 1:
		start_run()
	else:
		hud.fade_through(func(): new_game(pending_depth, {}, true))


func start_run() -> void:
	boss_seen = false
	hud.show_cards(Story.INTRO, func(): hud.fade_through(func(): new_game(1)))


func new_game(depth: int, restore: Dictionary = {}, prepared: bool = false) -> void:
	_drop_game()
	game = GameS.new()
	game.main = self
	game.hud = hud
	add_child(game)
	move_child(game, 0)
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
	hud.show_death()


## After a death: wake at the last save point with the lamp's blessing.
func retry() -> void:
	var s := read_save(slot)
	if s.is_empty():
		hud.fade_through(func(): new_game(1))
		return
	s["revive"] = true
	hud.fade_through(func(): new_game(int(s["depth"]), s))


func to_title() -> void:
	hud.fade_through(_to_title_now)


func _to_title_now() -> void:
	_drop_game()
	hud.show_title()
	Sfx.play_music("title")


## kind 0: carry the Ember up. kind 1: open the cage.
func ending(kind: int) -> void:
	delete_save(slot)
	profile["endings"][kind] = true
	_save_profile()
	Sfx.play_music("keep" if kind == 0 else "dawn")
	var cards: Array = Story.ENDING_KEEP if kind == 0 else Story.ENDING_FREE
	hud.fade_through(func(): hud.show_cards(cards, func(): hud.show_end(kind)))


func quit_game() -> void:
	get_tree().quit()
