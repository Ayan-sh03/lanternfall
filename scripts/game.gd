extends Node2D
## The dungeon itself: the map, the fog of war, Wren, and everything that moves.

const Art = preload("res://scripts/art.gd")
const Dungeon = preload("res://scripts/dungeon.gd")
const EnemyS = preload("res://scripts/enemy.gd")
const FxS = preload("res://scripts/fx.gd")
const Story = preload("res://scripts/story.gd")
const View3DS = preload("res://scripts/view3d.gd")
const SurfS = preload("res://scripts/surfaces.gd")
const EchoS = preload("res://scripts/echo.gd")
const Nemesis = preload("res://scripts/nemesis.gd")
const MothS = preload("res://scripts/moth.gd")

const TS := 16
const AMBIENT := Color(0.14, 0.14, 0.23)
const FOGC := Color(0.012, 0.012, 0.03)
const MINI_FLOOR := Color(0.66, 0.6, 0.5, 0.95)
const MINI_WALL := Color(0.27, 0.24, 0.27, 0.95)
const MINI_STAIRS := Color(0.4, 0.95, 1.0, 1.0)
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const PROMPTS := {"chest": "Open", "lamp": "Light the wayside lamp", "page": "Read", "plaque": "Read the plaque",
	"stairs": "Descend", "cage": "The latch", "relic": "Take the relic", "moth": "Offer the moth a drop of oil"}

var main
var hud
var rng := RandomNumberGenerator.new()

# --- map ---
var depth := 1
var dungeon := {}
var W := 0
var H := 0
var tiles := PackedByteArray()
var room_id := PackedInt32Array()
var vis := PackedByteArray()
var seen := PackedByteArray()
var fog_a := PackedFloat32Array()
var flow := PackedInt32Array()
var flow_q := PackedInt32Array()
var vis_list := PackedInt32Array()
var fog_img: Image
var fog_tex: ImageTexture
var mini_img: Image
var mini_tex: ImageTexture
var stairs_tile := Vector2i(-1, -1)
var exit_room := -1
var sealed := false

# --- scene ---
var map_root: Node2D
var decal_node: Node2D
var ents: Node2D
var over: Node2D
var fx
var fog_sprite: Sprite2D
## The 3D view drawn over the same game; null when it is off.
var view3d = null
var ambient_node: CanvasModulate
var cam: Camera2D
## Draws the world small and scales it up; owns the mapping to the window.
var view = null
var enemies: Array = []
var shots: Array = []
var props: Array = []
var pickups: Array = []
var lights: Array = []
var decals: Array = []
var near_prop = null

# --- Wren ---
var pnode: Node2D
var pspr: Sprite2D
var pemi: Sprite2D
var staff: Sprite2D
var staff_e: Sprite2D
var swing_t := -1.0
var swing_dur := 0.14
var swing_from := 0.0
var swing_to := 0.0
var swing_dir := 1.0
var pose := ""
var pose_t := 0.0
var atk_pose := 0.0
var pmat: ShaderMaterial
var plight: PointLight2D
var pglow: Sprite2D
var ppos := Vector2.ZERO
var ptile := Vector2i(-1, -1)
var pvel := Vector2.ZERO
var pknock := Vector2.ZERO
var aim := Vector2.RIGHT
var last_mv := Vector2.ZERO
var hp := 8
var max_hp := 8
var oil := 100.0
var max_oil := 100.0
var xp := 0
var level := 1
var xp_next := 22
var stats := {"dmg": 10.0, "reach": 1.0, "speed": 80.0, "bolt_dmg": 13.0, "bolt_n": 1, "dash_cd": 0.9,
	"light": 1.0, "oil_regen": 2.0, "heart_drop": 0.05, "sear": 0.0, "siphon": 0.0, "thorns": 0.0, "pierce": 0,
	"power": 1.0, "cdr": 1.0, "orbit": 0, "wave": 0.0, "burn": 0.0, "shatter": 0.0, "dash_n": 1, "trail": 0.0,
	"magnet": 1.0, "xp_mult": 1.0, "crit": 0.0,
	# Kindlings that combine two others (Story.DUOS).
	"wildfire": 0.0, "starfall": 0.0, "flashstep": 0.0, "chainburst": 0.0, "riposte": 0.0, "mote_k": 1.0,
	# Wren's echo: how hard its blows land, and how soon another can follow.
	"echo": 0.5, "echo_cd": 3.0,
	# What the bargains (Story.BOONS) change: how far a dash carries, the extra
	# a blow from behind lands, what a power costs, embers paid per kill, and
	# how full the flask can be when the gloams start to come.
	"dash_len": 1.0, "frail": 0, "power_cost": 1.0, "ember_k": 1.0, "gloam_k": 1.0}
var boons: Array = []
## The cards on the table at the last offer (kindlings or relics), by id, and
## which kind it was; for the bots and their tallies.
var offer: Array = []
var offer_kind := ""
var atk_cd := 0.0
var bolt_cd := 0.0
## Input buffers: a press made slightly too early is remembered for a moment.
var atk_buf := 0.0
var bolt_buf := 0.0
var dash_buf := 0.0
## The on-screen pad when playing by touch; null with keyboard and mouse.
var pad = null
var dash_cd := 0.0
var dash_t := 0.0
var dash_dir := Vector2.RIGHT
var dash_hit: Array = []
var invuln := 0.0
var combo := 0
var combo_t := 0.0
var input_lock := 0.0
var step_t := 0.0
var flash := 0.0
var light_k := 1.0
var light_target := 1.0

# --- powers ---
var powers := {"nova": false, "spark": false, "ward": false}
var pcd := {"nova": 0.0, "spark": 0.0, "ward": 0.0}
var spare_match := false
var match_used := false
var dash_stock := 1
var wards: Array = []
var fires: Array = []
var fire_acc := 0.0
var motes: Array = []
var mote_a := 0.0
var nova_flash := 0.0
var growl_cd := 0.0

# --- run state ---
var dead := false
var death_t := 0.0
var death_shown := false
var hitstop := 0.0
var anim_t := 0.0
var run_time := 0.0
var kills := 0
var pages := 0
var levelup_t := -1.0
var floor_seed := 0
var dead_spawns: Array = []
var said := {}
var boss = null
var boss_started := false
var boss_dead := false
var boss_end_t := -1.0

# --- test driver ---
# --- camera ---
var cam_zoom := 3.0
var zoom_kick := 0.0
var intro_t := 0.0
var cine_t := 0.0
var cine_zoom := 3.0
var cine_pos := Vector2.ZERO
var cine_has_pos := false
var cam_script := false
## Lets the trailer dress the practice hall in any depth's colours.
var gallery_theme := ""
var slow_t := 0.0
## The camera's shove in the direction of a blow, easing back to centre.
var cam_punch := Vector2.ZERO
## Shake is kept as trauma, from 0 to 1, which every blow tops up and which
## drains by itself. The view moves by trauma squared, so a big blow jolts and
## then settles fast, and a small one barely stirs it.
var trauma := 0.0
## How far the shake has moved the view this frame, in whole art pixels.
var shake_off := Vector2.ZERO
## The line a blow of Wren's own rocks the view along (zero: any way).
var shake_axis := Vector2.ZERO
var _shake_f := -1
var _shake_base := 0.0
var _shake_clock := 0.0
var _shake_from := Vector2.ZERO
var _shake_to := Vector2.ZERO
## Shake has its own dice, so how often the camera rolls never changes the game's.
var _shake_rng := RandomNumberGenerator.new()
## Hitstop spent lately and not yet paid back; while it is high, new freezes are cut short.
var stop_debt := 0.0
var _stop_f := -1
var _stop_debt0 := 0.0
## Peak shake, in art pixels, at full trauma (the Warden falling).
const SHAKE_PX := 12.0
## How fast trauma drains, per second.
const TRAUMA_DECAY := 2.4
## Stacked blows never shake harder than this, unless one blow alone does.
const TRAUMA_STACK := 0.75
## How often the shake picks a new way to lean, per second.
const SHAKE_HZ := 30.0
## The pause screen's shake setting: off, low, full.
const SHAKE_LEVELS := [0.0, 0.5, 1.0]
## No ordinary blow holds the frame longer than this.
const HITSTOP_CAP := 0.12
## Freezes in quick succession shrink as their debt nears this, and the debt
## drains at STOP_DRAIN seconds per second.
const STOP_BUDGET := 0.3
const STOP_DRAIN := 0.3
## How long a kill holds the frame, by the blow that did it. Only Wren's own
## blows stop the world; fire, shrapnel and her familiars' work do not, and a
## bolt holds it less than the staff.
const KILL_STOP := {"hit": 0.05, "hit_heavy": 0.05, "crit": 0.05, "hit_bolt": 0.03, "zap_hit": 0.04}
## Wren's squash and stretch: how hard, and how long since it began.
var sq_amp := 0.0
var sq_t := 9.0
## The opaque pixels of each sprite frame, for breaking foes into embers.
var pix_cache := {}
## Gloams: shades that come out of the dark when the lamp burns low.
const GLOAM_LOW := 0.2
const GLOAM_SAFE := 0.4
var gloam_t := 0.0
## The light as a risk dial, after Darkest Dungeon's torch: the lower the lamp
## burns, the more the dark gives up, and the harder it bites. Tiers run 0 Bright,
## 1 Dim, 2 Shadowy, 3 Dark (see light_tier). Dark begins where the gloams do;
## Shadowy is the band where shades already out linger but no new ones come.
const LIGHT_DIM_AT := 0.65
const LIGHT_DARK := 3
## A hooded lamp counts as Dark only once the dark has settled round her, the
## same grace the gloams give, so flicking the hood over a chest buys nothing.
const SNUFF_SETTLE := 3.0
## What each tier pays: drop chances and amounts, the cinders a kill leaves
## (a little more experience), and how long a foe that wakes on her rushes.
const LOOT_BY_TIER := [1.0, 1.25, 1.6, 2.0]
const XP_BY_TIER := [1.0, 1.05, 1.15, 1.3]
const AMBUSH_BY_TIER := [0.0, 0.0, 0.8, 1.6]
## Oil spent to bring a lamp back after it has been properly dark.
const RELIGHT_COST := 10.0
## What last struck Wren (a key of Story.CAUSES), for the death screen.
var last_cause := ""
var riposte_t := 0.0
var dash_refunded := false
## The depth on which the bell tower's fresh choice was last used.
var reroll_depth := -99
## Oil, fire, webs and water on the floor (surfaces.gd).
var surf
var flask_cd := 0.0
const FLASK_COST := 20.0
## The lamp snuffed by choice: Wren hides in the dark, and relighting flares.
var snuffed := false
var snuff_t := 0.0
var snuff_k := 0.0
var flare_cd := 0.0
## The last two seconds of Wren, for her echo to play again when she dashes.
var echo_clock := 0.0
var echo_track: Array = []
var echo_blows: Array = []
var echo_cd := 0.0
## Whether the last blow Wren took came from her nemesis.
var last_by_nem := false
## Flit, the lamp moth, once befriended (moth.gd); null otherwise.
var moth = null
## Hollow walls: {"w": the false wall tile, "f": the floor before it,
## "c": the middle of the room behind it, "open": bool}.
var secrets: Array = []
## Bumped whenever the walls change, so the 3D view rebuilds them.
var map_rev := 0
var map_theme := ""

var bot := false
var bot_manual := false
var bot_allow := {"atk": true, "move": true, "bolt": true, "dash": true, "nova": true, "spark": true, "ward": true}
var god := false
var bot_mv := Vector2.ZERO
var bot_atk := false
var bot_bolt := false


## restore: a save to resume from. prepared: starting fresh at a chosen depth,
## so Wren arrives with the kit she would plausibly have by then.
func start(d: int, restore: Dictionary = {}, prepared: bool = false) -> void:
	rng.randomize()
	pad = hud.pad
	_build_nodes()
	view3d = View3DS.new()
	view3d.game = self
	view3d.active = main.use_3d
	add_child(view3d)
	if not restore.is_empty():
		_apply_save(restore)
	elif prepared:
		_prepare(d)
	if restore.is_empty():
		_apply_town()
	load_floor(d, restore)
	if restore.get("revive", false):
		hud.say(_wake_line(), 5.0, hud.C_TEAL)


func _build_nodes() -> void:
	ambient_node = CanvasModulate.new()
	ambient_node.color = AMBIENT
	add_child(ambient_node)
	map_root = Node2D.new()
	map_root.z_index = -10
	add_child(map_root)
	decal_node = Node2D.new()
	decal_node.z_index = -9
	decal_node.material = Art.mat_unlit
	decal_node.draw.connect(_draw_decals)
	add_child(decal_node)
	surf = SurfS.new()
	surf.g = self
	add_child(surf)
	ents = Node2D.new()
	ents.y_sort_enabled = true
	add_child(ents)
	over = Node2D.new()
	over.z_index = 15
	add_child(over)
	fx = FxS.new()
	fx.z_index = 20
	fx.wards = wards
	add_child(fx)
	fog_sprite = Sprite2D.new()
	fog_sprite.centered = false
	fog_sprite.scale = Vector2(TS, TS)
	fog_sprite.z_index = 50
	fog_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	fog_sprite.material = Art.mat_unlit
	add_child(fog_sprite)
	cam = Camera2D.new()
	cam.zoom = Vector2(3, 3)
	# The camera only says where to look; the world view (world_view.gd) does
	# the looking, at the art's own pixel size.
	cam.enabled = false
	add_child(cam)

	pnode = Node2D.new()
	ents.add_child(pnode)
	var sh := Sprite2D.new()
	sh.texture = Art.tex["shadow"]
	sh.z_index = -1
	sh.position = Vector2(0, 2)
	pnode.add_child(sh)
	pspr = Sprite2D.new()
	pspr.texture = Art.tex["player_idle0"]
	pspr.offset = Vector2(0, -pspr.texture.get_height() * 0.5 + 2.0 + Art.PAD)
	pmat = ShaderMaterial.new()
	pmat.shader = Art.flash_shader
	pspr.material = pmat
	pnode.add_child(pspr)
	# Eyes and lantern stay lit whatever the dungeon's darkness does to the cloak.
	pemi = Sprite2D.new()
	pemi.texture = Art.tex["player_idle0_e"]
	pemi.material = Art.mat_unlit
	pemi.offset = pspr.offset
	pspr.add_child(pemi)
	# The lantern-staff is its own sprite, pivoting at the grip, so it can swing.
	staff = Sprite2D.new()
	staff.texture = Art.tex["staff"]
	staff.centered = false
	staff.offset = Vector2(-2.5, -11.5)
	staff.position = Vector2(6.5, -7.5)
	pnode.add_child(staff)
	staff_e = Sprite2D.new()
	staff_e.texture = Art.tex["staff_e"]
	staff_e.material = Art.mat_unlit
	staff_e.centered = false
	staff.add_child(staff_e)
	plight = PointLight2D.new()
	plight.texture = Art.tex["light"]
	plight.color = Color(1.0, 0.8, 0.56)
	plight.energy = 1.3
	plight.position = Vector2(0, -6)
	pnode.add_child(plight)
	pglow = Sprite2D.new()
	pglow.texture = Art.tex["glow"]
	pglow.material = Art.mat_add
	pglow.modulate = Color(1.0, 0.7, 0.3, 0.5)
	pglow.scale = Vector2(0.4, 0.4)
	pglow.z_index = 1
	pnode.add_child(pglow)


# --- Floors ---------------------------------------------------------------------

func load_floor(d: int, restore: Dictionary = {}) -> void:
	depth = d
	_clear_floor()
	var info: Dictionary = Story.GALLERY if d <= 0 else Story.DEPTHS[d - 1]
	if d <= 0 and gallery_theme != "":
		info = info.duplicate()
		info["theme"] = gallery_theme
	# Each floor is grown from one seed, so a save only has to remember the seed
	# to get the same floor back.
	floor_seed = int(restore.get("seed", rng.randi()))
	var grng := RandomNumberGenerator.new()
	grng.seed = floor_seed
	dungeon = Dungeon.generate(d, grng)
	W = dungeon["w"]
	H = dungeon["h"]
	tiles = dungeon["tiles"]
	room_id = dungeon["room_id"]
	exit_room = dungeon["exit_room"]
	_carve_secrets()
	if moth == null and d > 0 and d < Story.DEPTHS.size():
		_place_wild_moth()
	map_theme = info["theme"]
	_paint_map()

	var n := W * H
	vis = PackedByteArray()
	vis.resize(n)
	seen = PackedByteArray()
	seen.resize(n)
	fog_a = PackedFloat32Array()
	fog_a.resize(n)
	fog_a.fill(1.0)
	flow = PackedInt32Array()
	flow.resize(n)
	flow.fill(9999)
	flow_q = PackedInt32Array()
	flow_q.resize(n)
	vis_list = PackedInt32Array()
	fog_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	fog_img.fill(Color(FOGC.r, FOGC.g, FOGC.b, 1.0))
	fog_tex = ImageTexture.create_from_image(fog_img)
	fog_sprite.texture = fog_tex
	mini_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	mini_tex = ImageTexture.create_from_image(mini_img)
	hud.set_map(mini_tex, W, H)

	var opened := _ints(restore.get("secrets_open", []))
	for i in secrets.size():
		if opened.has(i):
			open_secret(secrets[i], true)
	if not opened.is_empty():
		_paint_map()
	var done := _ints(restore.get("done_props", []))
	var gone := _ints(restore.get("dead_spawns", []))
	var lamp_idx := int(restore.get("lamp_idx", -1))
	var spawn_at := tile_center(dungeon["start"])
	var plist: Array = dungeon["props"]
	for i in plist.size():
		_add_prop(plist[i], i)
	for p in props:
		if done.has(p["idx"]):
			_restore_prop(p)
		if p["idx"] == lamp_idx:
			spawn_at = p["pos"] + Vector2(0, 12)
	dead_spawns = gone
	var slist: Array = dungeon["spawns"]
	for i in slist.size():
		if gone.has(i):
			continue
		var sd: Dictionary = slist[i]
		var e = spawn_enemy(sd["kind"], tile_center(sd["tile"]), sd["room"], sd.get("elite", false))
		e.spawn_idx = i
	surf.grow(floor_seed)
	_place_nemesis()

	# Put back the map the player had already uncovered.
	if restore.has("seen"):
		var raw := Marshalls.base64_to_raw(restore["seen"])
		if raw.size() == n:
			seen = raw
			for i in n:
				if seen[i] == 1:
					fog_a[i] = 0.6
					fog_img.set_pixel(i % W, int(i / float(W)), Color(FOGC.r, FOGC.g, FOGC.b, 0.6))
					mini_img.set_pixel(i % W, int(i / float(W)), MINI_FLOOR if tiles[i] == 1 else MINI_WALL)
			if stairs_tile.x >= 0 and seen[stairs_tile.y * W + stairs_tile.x] == 1:
				mini_img.set_pixel(stairs_tile.x, stairs_tile.y, MINI_STAIRS)
			fog_tex.update(fog_img)
			mini_tex.update(mini_img)

	teleport(spawn_at)
	if moth != null:
		moth.position = ppos
	snuffed = false
	snuff_k = 0.0
	echo_track.clear()
	echo_blows.clear()
	pvel = Vector2.ZERO
	pknock = Vector2.ZERO
	light_target = 1.0
	match_used = bool(restore.get("match_used", false))
	dash_stock = stats["dash_n"]
	_update_seal(true)
	# Arrive close in, then ease back out to the working view.
	cam_zoom = 5.4
	intro_t = 1.8
	cine_t = 0.0
	if info["name"] != "":
		hud.floor_card(info["sub"], info["name"])
		if restore.is_empty():
			hud.say(info["line"], 5.0)
	Sfx.play_music(info["music"])
	if d > 0:
		main.reached(d)
		if restore.is_empty():
			save_game(-1)


func _ints(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(int(v))
	return out


# --- Saving -------------------------------------------------------------------

## Writes the run to the current slot. lamp_idx is the lamp being rested at, or
## -1 for the automatic save made on arriving at a depth.
func save_game(lamp_idx: int) -> void:
	if depth <= 0 or dead:
		return
	var done: Array = []
	for p in props:
		if p["done"] or p.has("read"):
			done.append(p["idx"])
	main.write_save({"v": 1, "depth": depth, "name": Story.DEPTHS[depth - 1]["name"], "seed": floor_seed,
		"lamp_idx": lamp_idx, "hp": hp, "max_hp": max_hp, "oil": oil, "max_oil": max_oil, "xp": xp,
		"level": level, "xp_next": xp_next, "stats": stats.duplicate(), "boons": boons.duplicate(),
		"powers": powers.duplicate(), "spare": spare_match, "match_used": match_used, "kills": kills,
		"pages": pages, "run_time": run_time, "said": said.duplicate(), "done_props": done,
		"dead_spawns": dead_spawns.duplicate(), "seen": Marshalls.raw_to_base64(seen),
		"secrets_open": _opened_secrets(),
		"moth": {} if moth == null else {"lv": moth.lv, "hp": moth.hp, "fed": moth.fed}})


## The lamps lit in the town above, at the start of each fresh descent.
func _apply_town() -> void:
	if main.has_lamp("tinker"):
		max_hp += 2
		hp = max_hp
	if main.has_lamp("oil"):
		max_oil += 25.0
		oil = max_oil
	if main.has_lamp("smith"):
		stats["dmg"] *= 1.1
	if main.has_lamp("physician"):
		stats["heart_drop"] += 0.04
	if main.has_lamp("watch"):
		spare_match = true


## What Wren says on waking at the lamp: about what put her out, the first
## time it does; a landmark when the falls mount up.
func _wake_line() -> String:
	var deaths := int(main.profile["tally"].get("deaths", 0))
	if Story.WREN_STUBBORN.has(deaths):
		return Story.WREN_STUBBORN[deaths]
	var cause: String = main.last_cause
	if not Story.WREN_WAKE.has(cause):
		return "Up again. The lamp still burns."
	var lines: Array = Story.WREN_WAKE[cause]
	var seen := int(main.profile["tally"].get("fell_" + cause, 0))
	return lines[0] if seen <= 1 else lines[rng.randi() % lines.size()]


func bolt_cost() -> float:
	return 15.0 if main.has_lamp("chandler") else 18.0


func _apply_save(s: Dictionary) -> void:
	max_hp = int(s["max_hp"])
	hp = int(s["hp"])
	max_oil = float(s["max_oil"])
	oil = float(s["oil"])
	xp = int(s["xp"])
	level = int(s["level"])
	xp_next = int(s["xp_next"])
	var st: Dictionary = s["stats"]
	for k in st:
		if stats.has(k):
			# JSON has only one number type; keep counts as whole numbers.
			stats[k] = int(st[k]) if typeof(stats[k]) == TYPE_INT else float(st[k])
	boons = (s["boons"] as Array).duplicate()
	var pw: Dictionary = s["powers"]
	for k in pw:
		powers[k] = bool(pw[k])
	spare_match = bool(s["spare"])
	kills = int(s["kills"])
	pages = int(s["pages"])
	run_time = float(s["run_time"])
	said = (s["said"] as Dictionary).duplicate()
	var m = s.get("moth", {})
	if m is Dictionary and not m.is_empty():
		_make_moth(int(m.get("lv", 1)), int(m.get("hp", 3)), int(m.get("fed", 0)))
	if s.get("revive", false):
		# Coming back from a death: the lamp sets you fully to rights.
		hp = max_hp
		oil = max_oil
	_sync_motes()


## Starting fresh below the first depth: hand over the relics and roughly the
## kindlings a run would have collected by then.
func _prepare(d: int) -> void:
	for i in mini(d - 1, Story.RELICS.size()):
		grant_power(Story.RELICS[i]["power"])
	var picks := 2 * (d - 1)
	for i in picks:
		# Drawn the way the offers lean, so the build has a shape; never a
		# bargain, since nobody chose to pay for it.
		var pool: Array = []
		for b in Story.BOONS:
			if can_offer(b) and not b.get("bargain", false):
				pool.append(b)
		apply_boon(_draw_leaning(pool, aspect_counts())["id"])
	level = 1 + picks
	xp = 0
	xp_next = 14 + level * 8
	levelup_t = -1.0
	hp = max_hp
	oil = max_oil


func _restore_prop(p: Dictionary) -> void:
	match p["type"]:
		"chest":
			p["done"] = true
			p["spr"].texture = Art.tex["chest1"]
		"lamp":
			_light_lamp(p)
		"plaque":
			p["read"] = true
		"urn", "page", "relic", "moth":
			p["done"] = true
			if p.has("light"):
				lights.erase(p["light"])
			p["node"].queue_free()


func _light_lamp(p: Dictionary) -> void:
	p["done"] = true
	p["spr"].texture = Art.tex["lamp1"]
	_light(p["node"], Color(1.0, 0.85, 0.55), 1.2, 1.9, Vector2(0, -14))
	_glow(p["node"], Color(1.0, 0.8, 0.4, 0.6), 0.5, Vector2(0, -14))


func _clear_floor() -> void:
	for c in map_root.get_children():
		c.queue_free()
	for e in enemies:
		e.queue_free()
	for p in props:
		# Broken urns and collected pages have already freed their node.
		if is_instance_valid(p["node"]):
			p["node"].queue_free()
	for s in shots:
		s["node"].queue_free()
	for p in pickups:
		p["node"].queue_free()
	for wd in wards:
		wd["node"].queue_free()
	wards.clear()
	fires.clear()
	surf.clear()
	for c in ents.get_children():
		if c is EchoS:
			c.queue_free()
	enemies.clear()
	props.clear()
	shots.clear()
	pickups.clear()
	lights.clear()
	decals.clear()
	decal_node.queue_redraw()
	fx.clear()
	near_prop = null
	boss = null
	boss_started = false
	boss_dead = false
	boss_end_t = -1.0
	stairs_tile = Vector2i(-1, -1)


func tile_center(t: Vector2i) -> Vector2:
	return Vector2(t.x * TS + TS * 0.5, t.y * TS + TS * 0.5)


func teleport(p: Vector2) -> void:
	ppos = p
	pnode.position = p
	cam.position = p
	ptile = Vector2i(-1, -1)


func _stand(s: Sprite2D) -> void:
	s.offset = Vector2(0, -s.texture.get_height() * 0.5 + 3.0)


func _glow(parent: Node, col: Color, sc: float, pos: Vector2) -> Sprite2D:
	var gl := Sprite2D.new()
	gl.texture = Art.tex["glow"]
	gl.material = Art.mat_add
	gl.modulate = col
	gl.scale = Vector2(sc, sc)
	gl.position = pos
	parent.add_child(gl)
	return gl


func _light(parent: Node, col: Color, energy: float, sc: float, pos: Vector2) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = Art.tex["light"]
	l.color = col
	l.energy = energy
	l.texture_scale = sc
	l.position = pos
	parent.add_child(l)
	lights.append(l)
	return l


func _add_prop(pd: Dictionary, idx: int = -1) -> void:
	var type: String = pd["type"]
	var pos := tile_center(pd["tile"])
	var node := Node2D.new()
	node.position = pos
	var s := Sprite2D.new()
	node.add_child(s)
	var p := {"type": type, "pos": pos, "node": node, "spr": s, "done": false, "t": rng.randf() * 6.0, "idx": idx}
	match type:
		"brazier":
			s.texture = Art.tex["brazier"]
			_stand(s)
			p["light"] = _light(node, Color(1.0, 0.58, 0.28), 0.95, 1.15, Vector2(0, -8))
			_glow(node, Color(1.0, 0.5, 0.15, 0.45), 0.3, Vector2(0, -9))
		"urn":
			s.texture = Art.tex["urn"]
			_stand(s)
		"lamp":
			s.texture = Art.tex["lamp0"]
			_stand(s)
		"page":
			s.texture = Art.tex["page"]
			s.material = Art.mat_unlit
			_stand(s)
			p["glow"] = _glow(node, Color(1.0, 0.9, 0.6, 0.45), 0.45, Vector2(0, -3))
		"plaque":
			s.texture = Art.tex["plaque"]
			_stand(s)
			p["glow"] = _glow(node, Color(0.5, 1.0, 0.85, 0.3), 0.45, Vector2(0, -3))
		"relic":
			s.texture = Art.tex["relic"]
			_stand(s)
			var em := Sprite2D.new()
			em.texture = Art.tex["relic_e"]
			em.material = Art.mat_unlit
			em.offset = s.offset
			node.add_child(em)
			p["glow"] = _glow(node, Color(1.0, 0.75, 0.3, 0.6), 0.55, Vector2(0, -12))
			p["light"] = _light(node, Color(1.0, 0.8, 0.45), 0.9, 1.0, Vector2(0, -10))
		"stairs":
			s.texture = Art.tex["stairs"]
			stairs_tile = pd["tile"]
			p["glow"] = _glow(node, Color(1.0, 0.15, 0.1, 0.7), 0.5, Vector2.ZERO)
		"moth":
			s.texture = MothS.make_frames()[0]
			s.material = Art.mat_unlit
			s.position = Vector2(0, -14)
			p["glow"] = _glow(s, Color(0.75, 0.85, 1.0, 0.45), 0.28, Vector2.ZERO)
			p["light"] = _light(s, Color(0.8, 0.88, 1.0), 0.6, 0.6, Vector2.ZERO)
		"chest":
			s.texture = Art.tex["chest0"]
			_stand(s)
			p["secret"] = pd.get("secret", false)
		"cage":
			s.texture = Art.tex["cage"]
			_stand(s)
			var orb := _glow(node, Color(1.0, 0.75, 0.35, 1.0), 0.32, Vector2(0, -6))
			orb.z_index = -1
			p["glow"] = orb
			p["halo"] = _glow(node, Color(1.0, 0.55, 0.2, 0.5), 1.1, Vector2(0, -6))
			p["light"] = _light(node, Color(1.0, 0.7, 0.4), 1.2, 1.6, Vector2(0, -6))
	if type == "stairs":
		map_root.add_child(node)
	else:
		ents.add_child(node)
	props.append(p)


func spawn_enemy(kind: String, pos: Vector2, room: int, elite: bool = false):
	var e = EnemyS.new()
	ents.add_child(e)
	e.setup(self, kind, pos, room)
	if elite:
		e.make_elite()
	enemies.append(e)
	if kind == "warden":
		boss = e
	return e


# --- Grid queries ---------------------------------------------------------------

func solid_at(p: Vector2) -> bool:
	var tx := int(floor(p.x / TS))
	var ty := int(floor(p.y / TS))
	if tx < 0 or ty < 0 or tx >= W or ty >= H:
		return true
	return tiles[ty * W + tx] == 0


func _box_blocked(x: float, y: float, r: float) -> bool:
	return solid_at(Vector2(x - r, y - r)) or solid_at(Vector2(x + r, y - r)) \
		or solid_at(Vector2(x - r, y + r)) or solid_at(Vector2(x + r, y + r))


## Slides a body through the tile grid, one axis at a time.
func move_body(pos: Vector2, d: Vector2, r: float) -> Vector2:
	var steps := maxi(1, int(ceil(d.length() / 4.0)))
	var sd := d / steps
	for i in steps:
		if not _box_blocked(pos.x + sd.x, pos.y, r):
			pos.x += sd.x
		if not _box_blocked(pos.x, pos.y + sd.y, r):
			pos.y += sd.y
	return pos


func los(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var n := int(d.length() / 6.0) + 1
	for i in range(1, n):
		if solid_at(a + d * (float(i) / n)):
			return false
	return true


func vis_at(p: Vector2) -> bool:
	var tx := int(p.x / TS)
	var ty := int(p.y / TS)
	if tx < 0 or ty < 0 or tx >= W or ty >= H:
		return false
	return vis[ty * W + tx] == 1


## The map point under the cursor, whichever view is drawing.
func mouse_world() -> Vector2:
	if view3d != null and view3d.active:
		return view3d.mouse_world()
	return get_viewport().canvas_transform.affine_inverse() * view.view_mouse()


## Where a map point is drawn on screen, whichever view is drawing.
func screen_pos(p: Vector2) -> Vector2:
	if view3d != null and view3d.active:
		return view.view_xf * view3d.screen_pos(p)
	return view.view_xf * (get_viewport().canvas_transform * p)


func pcenter() -> Vector2:
	return ppos + Vector2(0, -7)


## Which way an enemy should walk to reach Wren when it cannot see her.
func flow_dir(pos: Vector2) -> Vector2:
	var tx := int(pos.x / TS)
	var ty := int(pos.y / TS)
	if tx < 1 or ty < 1 or tx >= W - 1 or ty >= H - 1:
		return Vector2.ZERO
	var best: int = flow[ty * W + tx]
	var bt := Vector2i(tx, ty)
	for o in DIRS:
		var nt: Vector2i = Vector2i(tx, ty) + o
		var v: int = flow[nt.y * W + nt.x]
		if v < best:
			best = v
			bt = nt
	if best >= 9999:
		return Vector2.ZERO
	return (tile_center(bt) - pos).normalized()


func _update_flow() -> void:
	flow.fill(9999)
	if ptile.x < 0 or ptile.y < 0 or ptile.x >= W or ptile.y >= H:
		return
	var head := 0
	var tail := 0
	var s := ptile.y * W + ptile.x
	var total := W * H
	flow[s] = 0
	flow_q[tail] = s
	tail += 1
	while head < tail:
		var i := flow_q[head]
		head += 1
		var d := flow[i] + 1
		if d > 44:
			continue
		for o in [1, -1, W, -W]:
			var j: int = i + o
			if j < 0 or j >= total:
				continue
			if tiles[j] == 1 and flow[j] > d:
				flow[j] = d
				flow_q[tail] = j
				tail += 1


## Casts rays out from Wren. Whatever they touch becomes visible and remembered.
func _update_fov() -> void:
	for i in vis_list:
		vis[i] = 0
	vis_list.clear()
	var dirty := false
	var ox := ptile.x + 0.5
	var oy := ptile.y + 0.5
	var rays := 200
	for a in rays:
		var ang := TAU * a / rays
		var dx := cos(ang) * 0.5
		var dy := sin(ang) * 0.5
		var x := ox
		var y := oy
		for s in (8 if snuffed else 27):
			var tx := int(x)
			var ty := int(y)
			if tx < 0 or ty < 0 or tx >= W or ty >= H:
				break
			var idx := ty * W + tx
			if vis[idx] == 0:
				vis[idx] = 1
				vis_list.append(idx)
				if seen[idx] == 0:
					seen[idx] = 1
					mini_img.set_pixel(tx, ty, MINI_FLOOR if tiles[idx] == 1 else MINI_WALL)
					dirty = true
			if tiles[idx] == 0:
				break
			x += dx
			y += dy
	if dirty:
		if stairs_tile.x >= 0 and seen[stairs_tile.y * W + stairs_tile.x] == 1:
			mini_img.set_pixel(stairs_tile.x, stairs_tile.y, MINI_STAIRS)
		mini_tex.update(mini_img)


func _update_fog(dt: float) -> void:
	var x0 := maxi(0, ptile.x - 17)
	var x1 := mini(W - 1, ptile.x + 17)
	var y0 := maxi(0, ptile.y - 17)
	var y1 := mini(H - 1, ptile.y + 17)
	var k := minf(1.0, dt * 9.0)
	var changed := false
	for y in range(y0, y1 + 1):
		var row := y * W
		for x in range(x0, x1 + 1):
			var i := row + x
			var target := 1.0
			if vis[i] == 1:
				target = 0.0
			elif seen[i] == 1:
				target = 0.6
			var a := fog_a[i]
			if absf(a - target) > 0.01:
				a = lerpf(a, target, k)
				fog_a[i] = a
				fog_img.set_pixel(x, y, Color(FOGC.r, FOGC.g, FOGC.b, a))
				changed = true
	if changed:
		fog_tex.update(fog_img)


# --- Main loop ------------------------------------------------------------------

func _process(dt: float) -> void:
	_tick(dt)
	# The world picture follows the camera in the same frame, so the HUD's
	# labels drawn over the world line up with it.
	if view != null:
		view.sync()


func _tick(dt: float) -> void:
	dt = minf(dt, 0.05)
	if hud == null or W == 0:
		return
	if hud.blocking():
		_update_camera(dt)
		return
	stop_debt = maxf(0.0, stop_debt - dt * STOP_DRAIN)
	if hitstop > 0.0:
		hitstop -= dt
		# The world holds still, but the shake runs on through the freeze: that
		# is what makes the pause read as a blow landing and not a stall.
		_update_shake(dt)
		cam.offset = shake_off + cam_punch
		return
	if slow_t > 0.0:
		slow_t -= dt
		dt *= 0.3
	anim_t += dt
	if not dead:
		run_time += dt
	var pt := Time.get_ticks_usec()
	_update_player(dt)
	pt = _pt("player", pt)
	var nt := Vector2i(int(ppos.x / TS), int(ppos.y / TS))
	if nt != ptile:
		ptile = nt
		_update_fov()
		pt = _pt("fov", pt)
		_update_flow()
		pt = _pt("flow", pt)
	for e in enemies.duplicate():
		if e.dead:
			continue
		# Sleeping monsters far off-screen do not need to think or animate.
		if not e.awake and (e.position - ppos).length_squared() > 160000.0:
			e.visible = false
			continue
		e.tick(dt)
	pt = _pt("enemies", pt)
	_update_shots(dt)
	pt = _pt("shots", pt)
	_update_powers(dt)
	pt = _pt("powers", pt)
	surf.tick(dt)
	pt = _pt("surfaces", pt)
	_update_pickups(dt)
	pt = _pt("pickups", pt)
	_update_gloam(dt)
	pt = _pt("gloam", pt)
	_update_props(dt)
	pt = _pt("props", pt)
	_update_fog(dt)
	pt = _pt("fog", pt)
	_update_camera(dt)
	pt = _pt("camera", pt)
	_purge()
	pt = _pt("purge", pt)
	_update_events(dt)
	pt = _pt("events", pt)
	_update_teach(dt)


## Profiling: microseconds spent in each part of the update, summed while on.
var prof := {}
var prof_max := {}
var prof_on := false


func _pt(part: String, t0: int) -> int:
	var t1 := Time.get_ticks_usec()
	if prof_on:
		prof[part] = prof.get(part, 0) + (t1 - t0)
		prof_max[part] = maxi(prof_max.get(part, 0), t1 - t0)
	if prof_on and t1 - t0 > 8000:
		print("PERF SPIKE %s %.1f ms (frame %d, enemies %d)" % [part, (t1 - t0) / 1000.0, Engine.get_frames_drawn(), enemies.size()])
	return t1


func _unhandled_input(ev: InputEvent) -> void:
	if hud == null or hud.blocking() or dead or bot:
		return
	if pad == null and ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			atk_buf = 0.22
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			bolt_buf = 0.22
		elif ev.button_index == MOUSE_BUTTON_MIDDLE:
			throw_flask()
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.physical_keycode:
			KEY_SPACE, KEY_SHIFT:
				try_dash()
			KEY_E:
				interact()
			KEY_C:
				toggle_snuff()
			KEY_X:
				throw_flask()
			KEY_Q:
				cast_nova()
			KEY_R:
				cast_spark()
			KEY_F:
				cast_ward()
			KEY_ESCAPE, KEY_P:
				hud.show_pause()


func _key(k: int) -> bool:
	return Input.is_physical_key_pressed(k)


func _update_player(dt: float) -> void:
	atk_cd -= dt
	bolt_cd -= dt
	atk_buf -= dt
	bolt_buf -= dt
	dash_buf -= dt
	growl_cd -= dt
	for k in pcd:
		pcd[k] = maxf(0.0, pcd[k] - dt)
	if dash_stock < stats["dash_n"]:
		dash_cd -= dt
		if dash_cd <= 0.0:
			dash_stock += 1
			dash_cd = stats["dash_cd"] if dash_stock < stats["dash_n"] else 0.0
	invuln -= dt
	riposte_t -= dt
	flask_cd -= dt
	flare_cd -= dt
	echo_cd -= dt
	echo_clock += dt
	if snuffed:
		snuff_t += dt
	combo_t -= dt
	input_lock -= dt
	flash = maxf(0.0, flash - dt * 5.0)
	pmat.set_shader_parameter("flash", flash)
	# A snuffed lamp burns nothing, so the flask fills faster.
	oil = minf(max_oil, oil + stats["oil_regen"] * (3.0 if snuffed else 1.0) * dt)

	var mv := Vector2.ZERO
	var want_atk := false
	var want_bolt := false
	if dead:
		pass
	elif bot:
		if not bot_manual:
			_bot_think()
		mv = bot_mv
		want_atk = bot_atk
		want_bolt = bot_bolt
	else:
		mv.x = float(_key(KEY_D) or _key(KEY_RIGHT)) - float(_key(KEY_A) or _key(KEY_LEFT))
		mv.y = float(_key(KEY_S) or _key(KEY_DOWN)) - float(_key(KEY_W) or _key(KEY_UP))
		if pad != null:
			mv += pad.move
			if input_lock <= 0.0:
				want_atk = pad.atk or atk_buf > 0.0
				want_bolt = pad.bolt or bolt_buf > 0.0
			_touch_aim(mv, want_atk, want_bolt)
		else:
			var m := mouse_world() - pcenter()
			if m.length() > 2.0:
				aim = m.normalized()
			if input_lock <= 0.0:
				want_atk = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or atk_buf > 0.0
				want_bolt = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or bolt_buf > 0.0
		if dash_buf > 0.0 and dash_stock > 0 and dash_t <= 0.0:
			try_dash()
	mv = mv.limit_length(1.0)
	last_mv = mv

	if dash_t > 0.0:
		dash_t -= dt
		pvel = dash_dir * 330.0
		fx.spark(pcenter(), Color(0.4, 0.85, 0.95, 0.7), 2, 12.0, 0.25, 2.5)
		if stats["trail"] > 0.0:
			fires.append({"p": ppos, "t": 2.2})
		if stats["sear"] > 0.0:
			for e in enemies:
				if not e.dead and not dash_hit.has(e) and (e.center() - pcenter()).length() < e.hit_r + 9.0:
					dash_hit.append(e)
					e.hurt(stats["sear"], dash_dir * 60.0, Color(1.0, 0.92, 0.65), "burn")
					if stats["flashstep"] > 0.0 and not dash_refunded:
						dash_refunded = true
						dash_stock = mini(stats["dash_n"], dash_stock + 1)
	else:
		pvel = pvel.move_toward(mv * stats["speed"] * surf.player_drag(), 1900.0 * dt)
	pknock = pknock.move_toward(Vector2.ZERO, 620.0 * dt)
	ppos = move_body(ppos, (pvel + pknock) * dt, 4.0)
	pnode.position = ppos

	if not dead and dash_t <= 0.0:
		if want_atk and atk_cd <= 0.0:
			do_slash()
		elif want_bolt and bolt_cd <= 0.0 and oil >= bolt_cost():
			do_bolt()

	# Animation.
	var moving := mv != Vector2.ZERO and dash_t <= 0.0
	if moving:
		step_t += dt
		if step_t > 0.3:
			step_t = 0.0
			Sfx.play("step", -17.0, 0.2)
	atk_pose -= dt
	var pframe := "player_idle%d" % (int(anim_t * 2.0) % 2)
	if dash_t > 0.0:
		pframe = "player_dash"
	elif atk_pose > 0.0:
		pframe = "player_atk"
	elif moving:
		pframe = "player_w%d" % (int(anim_t * 9.0) % 4)
	pspr.texture = Art.tex[pframe]
	sq_t += dt
	var sq := squash_k(sq_t) * sq_amp
	pspr.scale = Vector2(1.0 + sq, 1.0 - sq * 0.85)
	pspr.flip_h = aim.x < 0.0
	pemi.texture = Art.tex[pframe + "_e"]
	pemi.flip_h = pspr.flip_h
	pemi.visible = not dead
	_update_staff(dt, moving)
	pspr.modulate.a = 0.45 if invuln > 0.0 and dash_t <= 0.0 and int(anim_t * 22.0) % 2 == 0 and not dead else 1.0
	staff.modulate = pspr.modulate

	# The lamp: it flickers, it can be stolen, and it dies with its bearer.
	light_k = move_toward(light_k, 0.0 if dead else light_target, dt * (0.9 if dead else 0.5))
	var flick := 0.95 + 0.04 * sin(anim_t * 11.0) + 0.03 * sin(anim_t * 23.7)
	nova_flash = maxf(0.0, nova_flash - dt * 3.0)
	# The lamp burns on the oil in the flask: the emptier, the smaller the light.
	var fuel := pow(clampf(oil / maxf(max_oil, 1.0), 0.0, 1.0), 0.7)
	snuff_k = move_toward(snuff_k, 1.0 if snuffed else 0.0, dt * (5.0 if snuffed else 8.0))
	plight.texture_scale = 1.85 * stats["light"] * (0.35 + 0.65 * light_k) * (1.0 + 0.5 * nova_flash) * lerpf(0.5, 1.0, fuel) \
		* lerpf(1.0, 0.3, snuff_k)
	plight.energy = (1.3 * flick * (0.25 + 0.75 * light_k)) * lerpf(1.0, 0.3, snuff_k) + 1.6 * nova_flash
	pglow.modulate.a = 0.5 * flick * light_k * (1.0 - snuff_k)
	staff_e.modulate.a = 1.0 - 0.85 * snuff_k
	_record_echo(pframe)
	var reach: Vector2 = view.screen_size() * 0.5 / cam.zoom.x + Vector2(125, 125)
	for l in lights:
		var off: Vector2 = l.global_position - cam.position
		l.enabled = absf(off.x) < reach.x and absf(off.y) < reach.y


## Touch play has no cursor. A thumb dragged off STRIKE or BOLT aims by hand;
## otherwise a blow turns toward the nearest foe in sight, and Wren faces the
## way she walks.
func _touch_aim(mv: Vector2, striking: bool, casting: bool) -> void:
	if pad.aiming:
		aim = pad.aim
		return
	if striking or casting:
		var best = null
		var bd: float = 62.0 * stats["reach"] if striking else 250.0
		for e in enemies:
			if e.dead or not e.visible:
				continue
			var d: float = (e.center() - pcenter()).length() - e.hit_r
			if d < bd and los(pcenter(), e.center()):
				bd = d
				best = e
		if best != null:
			aim = (best.center() - pcenter()).normalized()
			return
	if mv.length() > 0.3:
		aim = mv.normalized()


func _bot_think() -> void:
	bot_mv = Vector2.ZERO
	bot_atk = false
	bot_bolt = false
	var best = null
	var bd := 220.0
	for e in enemies:
		if e.dead:
			continue
		var d: float = (e.position - ppos).length()
		if d < bd:
			bd = d
			best = e
	if best == null:
		return
	var v: Vector2 = best.center() - pcenter()
	aim = v.normalized()
	if bd > 20.0 and bot_allow["move"]:
		bot_mv = aim
	bot_atk = bd < 32.0 and bot_allow["atk"]
	bot_bolt = bd > 42.0 and bot_allow["bolt"]
	if bot_allow["dash"] and rng.randf() < 0.012:
		try_dash()
	if bot_allow["nova"] and bd < 40.0:
		cast_nova()
	elif bot_allow["spark"] and bd < 150.0:
		cast_spark()
	if bot_allow["ward"] and bd < 60.0 and rng.randf() < 0.02:
		cast_ward()


# --- The lamp snuffed, the flask thrown, the echo -----------------------------------

func toggle_snuff() -> void:
	if dead:
		return
	if snuffed:
		relight()
	else:
		snuff()


## Wren covers her lamp. Foes that cannot see her lose her, she sees only a
## little way, and only eyes and footsteps tell her what is out there.
func snuff() -> void:
	if snuffed or dead:
		return
	snuffed = true
	snuff_t = 0.0
	_update_fov()
	fx.spark(pcenter() + Vector2(0, -4), Color(0.5, 0.5, 0.55, 0.6), 10, 25.0, 0.8, 2.0, -30.0)
	Sfx.play("whoomp", -14.0, 0.0)
	_say_once("snuff", "Dark as the rest of them. Let them pass.")
	main.tally("snuffs")


## The lamp uncovered. After a moment in the dark it comes back as a flare:
## everything near is dazzled, shades come apart, and spilled oil catches.
func relight() -> void:
	if not snuffed:
		return
	snuffed = false
	_update_fov()
	# A wick left dark has to catch again, and a new flame drinks oil. This is
	# the price on hooding the lamp for the dark's loot and uncovering it for the
	# next fight; a slip of the key (under half a second) costs nothing.
	if snuff_t >= 0.5:
		oil = maxf(0.0, oil - RELIGHT_COST)
	if snuff_t >= 0.5 and flare_cd <= 0.0:
		_flare()
	else:
		Sfx.play("lamp", -10.0)


func _flare() -> void:
	flare_cd = 5.0
	snuff_k = 0.0
	nova_flash = 1.0
	var o := pcenter()
	var dazed := 0
	for e in enemies:
		if e.dead or (e.center() - o).length() > 78.0 or e.kind == "warden":
			continue
		if e.kind == "gloam":
			e.dead = true
			e.visible = false
			_disintegrate(e)
			continue
		e.hurt(6.0, (e.center() - o).normalized() * 160.0, Color(1.0, 0.9, 0.6), "hit_bolt")
		if not e.dead:
			e.stun = maxf(e.stun, 1.4)
			e.state = "rest" if e.state != "dormant" else e.state
			e.st = 0.4
			dazed += 1
	surf.ignite_at(ppos, 55.0)
	fx.ring(ppos, 6.0, 78.0, 0.3, Color(1.0, 0.85, 0.5), false, 5.0)
	fx.spark(o, Color(1.0, 0.85, 0.5), 40, 200.0, 0.5, 2.5)
	hud.flash_white(0.55)
	add_shake(5.0)
	slow_t = maxf(slow_t, 0.2)
	Sfx.play("whoomp", 0.0)
	Sfx.play("power", -6.0)
	hud.float_text(ppos + Vector2(0, -28), "FLARE", Color(1.0, 0.85, 0.5))
	if dazed > 0:
		main.tally("flares")


## X or the middle button: the flask, lobbed at the cursor. It costs oil, and
## the pool it leaves burns at a touch of fire, under anyone.
func throw_flask() -> void:
	if dead or flask_cd > 0.0 or oil < FLASK_COST:
		if oil < FLASK_COST and not dead and flask_cd <= 0.0:
			flask_cd = 0.4
			hud.float_text(ppos + Vector2(0, -26), "NO OIL", Color(0.8, 0.6, 0.4))
		return
	oil -= FLASK_COST
	flask_cd = 0.6
	var o := pcenter()
	var want: Vector2
	if pad == null and not bot:
		want = mouse_world()
	else:
		var best = null
		var bd := 150.0
		for e in enemies:
			if not e.dead and e.visible and (e.position - ppos).length() < bd:
				bd = (e.position - ppos).length()
				best = e
		want = best.position if best != null else ppos + aim * 70.0
	var v := (want - o).limit_length(120.0)
	# Stop short of the first wall in the way.
	var to := o
	var steps := int(v.length() / 4.0)
	for i in steps:
		var nx := o + v * float(i + 1) / maxf(steps, 1)
		if solid_at(nx):
			break
		to = nx
	pose = "point"
	pose_t = 0.2
	Sfx.play("dash", -10.0, 0.2)
	surf.throw_flask(o, to + Vector2(0, 7))
	_say_once("flask", "Oil burns. Mind where it pools.")


func _record_echo(frame: String) -> void:
	if dead:
		return
	echo_track.append({"t": echo_clock, "p": ppos, "f": frame, "fl": pspr.flip_h,
		"sr": staff.rotation, "sp": staff.position, "so": staff.offset})
	while echo_track.size() > 2 and echo_track[0]["t"] < echo_clock - 2.0:
		echo_track.pop_front()
	while not echo_blows.is_empty() and echo_blows[0]["t"] < echo_clock - 2.0:
		echo_blows.pop_front()


## Dashing leaves the last two seconds behind to happen again: but only if
## there was a fight in them, and not more often than the echo can recover.
func _spawn_echo() -> void:
	if echo_cd > 0.0 or echo_blows.is_empty() or echo_track.size() < 4:
		return
	echo_cd = stats["echo_cd"]
	var e = EchoS.new()
	e.setup(self, echo_track.duplicate(), echo_blows.duplicate(), stats["echo"])
	ents.add_child(e)
	echo_blows.clear()
	_say_once("echo", "That was me. A moment ago.")
	main.tally("echoes")


# --- Flit, and the hollow walls ------------------------------------------------------

func _make_moth(lv: int, life: int, food: int) -> void:
	if moth != null:
		moth.queue_free()
	moth = MothS.new()
	over.add_child(moth)
	moth.setup(self, lv, life, food)


func moth_died(m) -> void:
	fx.spark(m.position + m.body.position, Color(0.86, 0.92, 1.0), 24, 60.0, 1.0, 1.5, 40.0)
	hud.say("Flit...?  Oh, Flit. No.", 4.0, hud.C_TEAL)
	main.tally("flits_lost")
	moth = null
	var tw: Tween = m.create_tween()
	tw.tween_property(m, "modulate:a", 0.0, 0.6)
	tw.tween_callback(m.queue_free)
	m.set_process(false)


## A wild lamp moth somewhere on most floors (always on the first), well
## away from the start, where it flutters by itself until fed.
func _place_wild_moth() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = floor_seed ^ 0x307
	if depth > 1 and r.randf() > 0.5:
		return
	var start: Vector2i = dungeon["start"]
	var pool: Array = []
	for sd in dungeon["spawns"]:
		var t: Vector2i = sd["tile"]
		var dd := absi(t.x - start.x) + absi(t.y - start.y)
		if sd["room"] != exit_room and dd > 8 and dd < 40:
			pool.append(t)
	if pool.is_empty():
		return
	var t: Vector2i = pool[r.randi() % pool.size()]
	dungeon["props"].append({"type": "moth", "tile": t})


## One hollow wall on each floor that has room for it: a single wall tile with
## a small sealed room behind, and a chest in the room. Grown from the floor's
## seed, so a reloaded floor has it in the same place. Walls on the far side
## of a room (facing the camera) are preferred, so the 3D view can show them.
func _carve_secrets() -> void:
	secrets.clear()
	if depth <= 0:
		return
	var r := RandomNumberGenerator.new()
	r.seed = floor_seed ^ 0x5EC2
	var start: Vector2i = dungeon["start"]
	var best: Array = []
	var other: Array = []
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			if tiles[y * W + x] != 0:
				continue
			for dir in DIRS:
				var f: Vector2i = Vector2i(x, y) - dir
				if f.x < 0 or f.y < 0 or f.x >= W or f.y >= H or tiles[f.y * W + f.x] != 1:
					continue
				if absi(f.x - start.x) + absi(f.y - start.y) < 6:
					continue
				var c: Vector2i = Vector2i(x, y) + dir * 2
				var ok := true
				for yy in range(c.y - 2, c.y + 3):
					for xx in range(c.x - 2, c.x + 3):
						if xx < 1 or yy < 1 or xx >= W - 1 or yy >= H - 1 or tiles[yy * W + xx] != 0:
							ok = false
				if not ok:
					continue
				var cand := {"w": Vector2i(x, y), "f": f, "c": c, "open": false}
				if dir == Vector2i(0, -1):
					best.append(cand)
				else:
					other.append(cand)
	var pool: Array = best if not best.is_empty() else other
	if pool.is_empty():
		return
	var sc: Dictionary = pool[r.randi() % pool.size()]
	var c: Vector2i = sc["c"]
	for yy in range(c.y - 1, c.y + 2):
		for xx in range(c.x - 1, c.x + 2):
			tiles[yy * W + xx] = 1
			room_id[yy * W + xx] = -1
	secrets.append(sc)
	dungeon["props"].append({"type": "chest", "tile": c, "secret": true})


func _opened_secrets() -> Array:
	var out: Array = []
	for i in secrets.size():
		if secrets[i]["open"]:
			out.append(i)
	return out


## The map painted into a big image, then cut into chunks so that no single
## sprite is touched by more lights than the renderer allows.
func _paint_map() -> void:
	for c in map_root.get_children():
		if c is Sprite2D:
			c.queue_free()
	var img: Image = Art.compose(tiles, W, H, map_theme)
	var chunk := 64
	for cy in range(0, H * TS, chunk):
		for cx in range(0, W * TS, chunk):
			var r := Rect2i(cx, cy, mini(chunk, W * TS - cx), mini(chunk, H * TS - cy))
			var s := Sprite2D.new()
			s.centered = false
			s.position = Vector2(cx, cy)
			s.texture = ImageTexture.create_from_image(img.get_region(r))
			map_root.add_child(s)
			map_root.move_child(s, 0)


## A blow or a bolt that meets a hollow wall breaks it in.
func _strike_wall(p: Vector2, pad: float) -> void:
	var t := Vector2i(int(p.x / TS), int(p.y / TS))
	for sc in secrets:
		if not sc["open"] and (sc["w"] == t or (tile_center(sc["w"]) - p).length() < TS * 0.5 + pad):
			open_secret(sc)


func open_secret(sc: Dictionary, quiet: bool = false) -> void:
	if sc["open"]:
		return
	sc["open"] = true
	var w: Vector2i = sc["w"]
	tiles[w.y * W + w.x] = 1
	map_rev += 1
	if quiet:
		return
	_paint_map()
	_update_fov()
	_update_flow()
	var wc := tile_center(w)
	fx.spark(wc + Vector2(0, -6), Color(0.6, 0.55, 0.5, 0.9), 26, 90.0, 0.7, 2.5, 160.0)
	fx.spark(wc + Vector2(0, -6), Color(1.0, 0.8, 0.45), 10, 60.0, 0.5, 1.5)
	scorch(wc, 10.0)
	add_shake(5.0)
	freeze(0.08)
	Sfx.play("boom", -6.0)
	Sfx.play("thud", -2.0)
	hud.say("The wall was hollow.", 3.0, hud.C_EMBER)
	cine(3.6, 1.4, tile_center(sc["c"]))
	main.tally("secrets")


## For Flit: a hollow wall close by that it can flutter against, or INF.
func secret_hint(_from: Vector2) -> Vector2:
	for sc in secrets:
		if sc["open"]:
			continue
		var fp := tile_center(sc["f"])
		if (fp - ppos).length() < 120.0 and los(pcenter(), fp):
			var w: Vector2 = tile_center(sc["w"])
			return fp.lerp(w, 0.45)
	return Vector2.INF


## For Flit: the nearest floor Wren has not yet seen, within reach of her and
## in the open from her (INF if there is none).
func dark_tile_near(reach: float) -> Vector2:
	var best := Vector2.INF
	var bd := reach
	var rt := int(reach / TS) + 1
	for y in range(maxi(1, ptile.y - rt), mini(H - 1, ptile.y + rt + 1)):
		for x in range(maxi(1, ptile.x - rt), mini(W - 1, ptile.x + rt + 1)):
			var i := y * W + x
			if tiles[i] != 1 or seen[i] == 1 or flow[i] >= 9999:
				continue
			var p := tile_center(Vector2i(x, y))
			var d := (p - ppos).length()
			if d < bd:
				bd = d
				best = p
	return best


## Flit's light: the floor around it, as far as it can see, comes out of the dark.
func reveal_around(p: Vector2, r: int) -> void:
	var c := Vector2i(int(p.x / TS), int(p.y / TS))
	var dirty := false
	for y in range(maxi(0, c.y - r), mini(H, c.y + r + 1)):
		for x in range(maxi(0, c.x - r), mini(W, c.x + r + 1)):
			var i := y * W + x
			if vis[i] == 1:
				continue
			var tp := tile_center(Vector2i(x, y))
			if tiles[i] == 1 and not los(p, tp):
				continue
			vis[i] = 1
			vis_list.append(i)
			if seen[i] == 0:
				seen[i] = 1
				mini_img.set_pixel(x, y, MINI_FLOOR if tiles[i] == 1 else MINI_WALL)
				dirty = true
	if dirty:
		mini_tex.update(mini_img)


# --- The nemesis ------------------------------------------------------------------

## The named foe waits on the floor after it last put Wren out, and now and
## then on others: in a room well away from the start, never the stair room.
func _place_nemesis() -> void:
	var n: Dictionary = main.profile["nemesis"]
	if n.is_empty() or depth <= 0 or depth >= Story.DEPTHS.size():
		return
	if not main.nem_due and rng.randf() > 0.35:
		return
	var start: Vector2i = dungeon["start"]
	var pool: Array = []
	for sd in dungeon["spawns"]:
		var t: Vector2i = sd["tile"]
		if sd["room"] != exit_room and absi(t.x - start.x) + absi(t.y - start.y) > 14:
			pool.append(sd)
	if pool.is_empty():
		return
	var sd: Dictionary = pool[rng.randi() % pool.size()]
	var e = spawn_enemy(n["kind"], tile_center(sd["tile"]), sd["room"])
	e.make_nemesis(n)
	main.nem_due = false


func nemesis_woke(e) -> void:
	var line: String = Nemesis.TAUNTS[rng.randi() % Nemesis.TAUNTS.size()]
	hud.say_now("%s:  %s" % [Nemesis.full_name(e.nem, true), line], 5.0, Color(1.0, 0.45, 0.35))
	hud.float_text(e.position + Vector2(0, -e.cy * 2.0 - 12.0), "IT REMEMBERS YOU", Color(1.0, 0.4, 0.3))
	Sfx.play("roar", -4.0)
	slow_t = maxf(slow_t, 0.5)
	kick(0.08)
	add_shake(4.0)


func _nemesis_fell(e) -> void:
	var rank := int(e.nem["rank"])
	var pay := 40 + 30 * rank
	main.bank(pay)
	main.tally("nemeses")
	main.profile["nemesis"] = {}
	main.profile_dirty = true
	hud.say_now("Wren: \"%s\"   (+%d embers)" % [Nemesis.SLAIN[rng.randi() % Nemesis.SLAIN.size()], pay], 5.0, hud.C_EMBER)
	hud.float_text(e.position + Vector2(0, -e.cy * 2.0 - 12.0), "GRUDGE SETTLED", Color(1.0, 0.85, 0.4))
	hud.flash_white(0.7)
	slow_t = maxf(slow_t, 0.7)
	# A story beat, not a blow: it may hold longer than any hit.
	freeze(0.15, 0.15)
	Sfx.play("chime", -2.0)
	drop("heart", e.position)
	drop("heart", e.position + Vector2(6, 0))
	fx.spark(e.center(), Color(0.3, 0.7, 0.75), 20, 120.0, 0.8, 2.0, 60.0)


## A springy squash that overshoots and settles: 1 at the start, wobbling to 0.
static func squash_k(t: float) -> float:
	return exp(-t * 11.0) * cos(t * 30.0)


## Squash Wren: positive goes wide and short, negative tall and thin.
func squash(amp: float) -> void:
	sq_amp = amp
	sq_t = 0.0


## Shoves the camera along a direction; it springs back by itself. Shoves from
## many blows at once add up only so far.
func punch(dir: Vector2, amt: float) -> void:
	cam_punch = (cam_punch + dir.normalized() * amt * shake_scale()).limit_length(8.0)


func try_dash() -> void:
	if dead:
		return
	if dash_stock <= 0 or dash_t > 0.0:
		dash_buf = 0.15
		return
	dash_buf = 0.0
	dash_dir = last_mv if last_mv != Vector2.ZERO else aim
	dash_t = 0.16 * stats["dash_len"]
	dash_stock -= 1
	if dash_cd <= 0.0:
		dash_cd = stats["dash_cd"]
	invuln = maxf(invuln, 0.3)
	dash_hit.clear()
	dash_refunded = false
	squash(0.32)
	Sfx.play("dash", -5.0)
	fx.spark(pcenter(), Color(0.5, 0.9, 1.0), 8, 50.0, 0.3, 2.0)
	_spawn_echo()


func do_slash() -> void:
	combo = combo + 1 if combo_t > 0.0 and combo < 3 else 1
	combo_t = 0.75
	atk_buf = 0.0
	var heavy := combo == 3
	var reach: float = (34.0 if heavy else 27.0) * stats["reach"]
	var arc := deg_to_rad(200.0 if heavy else 125.0)
	var dmg: float = stats["dmg"] * (1.8 if heavy else 1.0)
	atk_cd = 0.44 if heavy else 0.27
	# The staff sweeps through the arc, alternating sides; the heavy blow goes all the way round.
	swing_dir = -swing_dir
	var sweep := arc * (0.5 if heavy else 0.46)
	swing_from = aim.angle() - sweep * swing_dir
	swing_to = aim.angle() + sweep * swing_dir
	swing_dur = 0.2 if heavy else 0.13
	swing_t = 0.0
	atk_pose = 0.22
	var o := pcenter()
	var hit := 0
	var crits := 0
	var killed := 0
	# A riposte readied by an earlier parry is spent on this swing; one this
	# swing earns waits for the next.
	var sure := riposte_t > 0.0
	riposte_t = 0.0
	squash(0.16 if heavy else 0.09)
	echo_blows.append({"t": echo_clock, "k": "slash", "a": aim, "heavy": heavy})
	for e in enemies:
		if e.dead:
			continue
		var v: Vector2 = e.center() - o
		var d := v.length()
		if d < reach + e.hit_r and (d < 9.0 or absf(aim.angle_to(v)) < arc * 0.5 + 0.2):
			if _parry(e):
				hit += 1
				continue
			# Out of the dark, on a foe that has lost her: it never sees it coming.
			var unseen: bool = snuffed and (not e.awake or e.lost) and e.kind != "warden"
			if unseen:
				hud.float_text(e.position + Vector2(0, -e.cy * 2.0 - 12.0), "UNSEEN", Color(0.7, 0.8, 1.0))
				main.tally("ambushes")
			var crit: bool = rng.randf() < stats["crit"] or sure or unseen
			if crit:
				e.hurt(dmg * 2.0, aim * 170.0, Color(1.0, 0.55, 0.15), "crit")
				fx.spark(e.center(), Color(1.0, 0.8, 0.3), 10, 110.0, 0.35, 2.0)
				crits += 1
			else:
				e.hurt(dmg * rng.randf_range(0.9, 1.1), aim * (150.0 if heavy else 95.0), Color(1.0, 0.92, 0.65),
					"hit_heavy" if heavy else "hit")
			# Where the staff meets the foe: on its near side, toward Wren.
			var at: Vector2 = e.center() - v.normalized() * e.hit_r * 0.6
			fx.impact(at, aim.angle(), e.tint, 1.25 if heavy or crit else 0.8)
			if e.dead:
				killed += 1
			hit += 1
	for p in props:
		if p["type"] == "urn" and not p["done"]:
			var v: Vector2 = p["pos"] - o
			if v.length() < reach + 5.0 and absf(aim.angle_to(v)) < arc * 0.5 + 0.3:
				_break_urn(p)
	# A well-timed strike sends hexes back the way they came, burning gold.
	for s in shots:
		if s["friendly"]:
			continue
		var v: Vector2 = s["pos"] - o
		if v.length() < reach + 4.0 and absf(aim.angle_to(v)) < arc * 0.5 + 0.2:
			_reflect(s)
	for sc in secrets:
		if not sc["open"]:
			var wc: Vector2 = tile_center(sc["w"])
			var v: Vector2 = wc - o
			if v.length() < reach + 9.0 and absf(aim.angle_to(v)) < arc * 0.5 + 0.3:
				open_secret(sc)
	if heavy and stats["wave"] > 0.0:
		add_shot(o + aim * 10.0, aim * 200.0, true, dmg * 0.6 * stats["wave"], Color(1.0, 0.92, 0.7), 99, 0.75, 0.55)
	pvel += aim * (75.0 if heavy else 40.0)
	fx.slash(o + aim * 2.0, aim.angle(), reach, arc, Color(1.0, 0.7, 0.35, 0.95) if heavy else Color(1.0, 0.9, 0.65, 0.85), 0.2 if heavy else 0.15)
	Sfx.play("slash3" if heavy else "slash", -4.0)
	if hit > 0:
		if heavy:
			kick(0.05)
		# One freeze for the swing, however many it struck: the hardest blow's.
		var stop := 0.08 if heavy else 0.04
		# A blow that kills, or lands twice as hard, holds the frame a little longer.
		if killed > 0 and (heavy or crits > 0):
			stop = 0.12
			hud.flash_white(0.6)
		elif crits > 0:
			stop = 0.1
		freeze(stop)
		punch(aim, 3.5 if heavy else 1.8)
		# A heavy swing rocks the view along the blow, not every which way.
		add_shake(4.0 if heavy else 2.0, aim if heavy else Vector2.ZERO)
		oil = minf(max_oil, oil + stats["siphon"] * hit)


func do_bolt() -> void:
	# An ember bolt is the lamp's own fire: casting one relights it.
	if snuffed:
		relight()
	echo_blows.append({"t": echo_clock, "k": "bolt", "a": aim, "heavy": false})
	# Relighting may have taken the oil this bolt was counted against.
	oil = maxf(0.0, oil - bolt_cost())
	bolt_cd = 0.38
	bolt_buf = 0.0
	pose = "point"
	pose_t = 0.18
	var n: int = stats["bolt_n"]
	for i in n:
		var a := aim.angle() + (i - (n - 1) * 0.5) * 0.2
		add_shot(pcenter() + aim * 6.0, Vector2.from_angle(a) * 235.0, true, stats["bolt_dmg"], Color(1.0, 0.62, 0.2), stats["pierce"])
	Sfx.play("bolt", -5.0)


func add_shot(pos: Vector2, vel: Vector2, friendly: bool, dmg, col: Color, pierce: int = 0, size: float = 0.0, life: float = 0.0) -> void:
	if size <= 0.0:
		size = 0.38 if friendly else 0.32
	var node := _glow(over, col, size, pos)
	var core := Sprite2D.new()
	core.texture = Art.tex["glow"]
	core.material = Art.mat_add
	core.scale = Vector2(0.4, 0.4)
	node.add_child(core)
	if friendly:
		var l := PointLight2D.new()
		l.texture = Art.tex["light"]
		l.color = col
		l.energy = 0.8
		l.texture_scale = 2.4
		node.add_child(l)
	shots.append({"pos": pos, "vel": vel, "friendly": friendly, "dmg": dmg, "col": col, "pierce": pierce,
		"life": life if life > 0.0 else (1.6 if friendly else 5.0), "node": node, "hit": [],
		"r": 4.0 + (size - 0.38) * 22.0})


## src is the foe (or, for a hex, the kind of foe) that dealt the blow.
func hurt_player(amount: int, from: Vector2, kb: float = 170.0, src = null) -> bool:
	if dead or invuln > 0.0 or god:
		return false
	# The lamp's resolve, if accepted: now and then a blow is turned aside.
	if rng.randf() < main.resolve_chance():
		invuln = 0.5
		pknock = (ppos - from).normalized() * kb * 0.5
		hud.float_text(ppos + Vector2(0, -26), "TURNED", Color(1.0, 0.85, 0.5))
		Sfx.play("clank", -4.0)
		return true
	if src is String:
		last_cause = src
		if src == "fire":
			last_by_nem = false
	elif src != null and is_instance_valid(src):
		last_cause = src.kind
		last_by_nem = src.nemesis
	# The Moth-Eaten Cloak: a blow from behind her finds the holes.
	if stats["frail"] > 0 and (from - ppos).dot(aim) < 0.0:
		amount += stats["frail"]
	# No single blow takes Wren from more than one heart straight to nothing.
	var spared: bool = amount >= hp and hp > 2
	hp -= amount
	if spared:
		hp = 1
	invuln = 0.9
	if hp > 0 and hp <= 2:
		# The last heart: a longer breath before the next blow can land.
		invuln = 1.6
		slow_t = maxf(slow_t, 0.3)
	flash = 1.0
	pknock = (ppos - from).normalized() * kb
	# A charge or a blast lands harder than a claw, and the camera says so.
	var big: bool = amount >= 2 or kb >= 240.0
	add_shake(7.0 if big else 5.0)
	squash(-0.28)
	punch(ppos - from, 7.0 if big else 4.0)
	# Fire does not stop the world, and a hex (src names its kind) holds it less
	# than a blow struck up close.
	if not (src is String and src == "fire"):
		freeze(0.04 if src is String else (0.09 if big else 0.06))
	hud.hurt_hit(1.0 - float(maxi(hp, 0)) / maxf(float(max_hp), 1.0))
	Sfx.play("sting", -8.0)
	Sfx.play("punch")
	if hp > 0:
		Sfx.play("hurt_voice", 0.0, 0.05)
	kick(0.1 if big else 0.06)
	if hp <= 0 and spare_match and not match_used:
		# The spare match: once per depth, the lamp relights itself.
		match_used = true
		hp = 2
		invuln = 2.0
		hud.say("The spare match catches.", 3.5, hud.C_EMBER)
		Sfx.play("power", -3.0)
		_nova_burst(70.0, 30.0)
	fx.spark(pcenter(), Color(1.0, 0.3, 0.3), 12, 90.0, 0.4, 2.0)
	if stats["thorns"] > 0.0:
		fx.ring(ppos, 6.0, 46.0, 0.3, Color(1.0, 0.6, 0.2), false, 3.0)
		for e in enemies:
			if not e.dead and (e.position - ppos).length() < 46.0:
				e.hurt(stats["thorns"], (e.position - ppos).normalized() * 160.0)
	if hp <= 0:
		hp = 0
		dead = true
		snuffed = false
		death_t = 1.6
		Sfx.play("death", 0.0, 0.0)
		Sfx.play("death_voice", 0.0, 0.03)
		Sfx.play_music("")
		slow_t = 0.9
		fx.spark(pcenter(), Color(1.0, 0.7, 0.3), 30, 110.0, 0.9, 2.0)
		pspr.modulate = Color(0.5, 0.5, 0.6)
	elif hp <= 2:
		_say_once("low", "Keep the wick trimmed. Keep moving.")
	return true


## Sweeps loot and stains off the floor (the showcase resets between scenes).
func tidy() -> void:
	surf.clear()
	for p in pickups:
		p["node"].queue_free()
	pickups.clear()
	decals.clear()
	decal_node.queue_redraw()
	fires.clear()


## Shakes the view by up to `a` art pixels at its peak (before the player's
## setting). Blows in the same frame count once, by the biggest; blows in a row
## stack, a quarter of the smaller on the larger, up to TRAUMA_STACK, so twenty
## hits at once shake no harder than the worst of them. dir, if given, is the
## line to rock along.
func add_shake(a: float, dir: Vector2 = Vector2.ZERO) -> void:
	var t := sqrt(clampf(a / SHAKE_PX, 0.0, 1.0))
	var f := Engine.get_process_frames()
	var fresh := f != _shake_f
	if fresh:
		_shake_f = f
		_shake_base = trauma
	var nt := minf(maxf(_shake_base, t) + 0.25 * minf(_shake_base, t), maxf(t, TRAUMA_STACK))
	if dir != Vector2.ZERO:
		shake_axis = dir.normalized()
	elif t > trauma:
		shake_axis = Vector2.ZERO
	trauma = maxf(trauma, nt)
	# On a phone, whatever shakes the screen is also felt in the hand (once a frame).
	if pad != null and fresh:
		hud.buzz(int(clampf(a * 6.0, 12.0, 70.0)))


## The player's shake setting as a scale: 0 off, 0.5 low, 1 full.
func shake_scale() -> float:
	return SHAKE_LEVELS[clampi(int(main.profile.get("shake", 2)), 0, 2)]


## Hitstop: the world holds still for a moment so a blow lands. Only Wren's own
## blows, and blows on Wren, call this. Many hits in one frame hold for the
## longest of them, never the sum, and none for more than cap; a run of freezes
## close together is cut shorter, so a crowd does not turn a fight into a stutter.
func freeze(t: float, cap: float = HITSTOP_CAP) -> void:
	var f := Engine.get_process_frames()
	if f != _stop_f:
		_stop_f = f
		_stop_debt0 = stop_debt
	t = minf(t, cap)
	# A story beat (a cap above the ordinary one) keeps its full length.
	if cap <= HITSTOP_CAP:
		t *= clampf(1.0 - _stop_debt0 / STOP_BUDGET, 0.3, 1.0)
	if t > hitstop:
		hitstop = t
		stop_debt = maxf(stop_debt, _stop_debt0 + t)


func scorch(pos: Vector2, r: float) -> void:
	for k in 5:
		decals.append({"p": pos + Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r)) * 0.5,
			"r": r * rng.randf_range(0.4, 0.8), "c": Color(0.03, 0.02, 0.02, 0.4)})
	decal_node.queue_redraw()


func _say_once(key: String, text: String) -> void:
	if said.has(key):
		return
	said[key] = true
	hud.say(text)


# --- Teaching, the first time each thing comes up -----------------------------------

## How often the moments worth a lesson are looked for, and the hollow walls listened at.
var teach_t := 0.0
var draught_t := 0.0
## True once every lesson is known and every foe met, so the look-out can stop.
var teach_done := false


## Shows a lesson the first time its moment comes on this profile, and never
## again (the bestiary's Lamp Lore page keeps them). A lesson still on the
## screen makes the next one wait for its own moment to come round again.
func teach(id: String) -> bool:
	if main.knows(id) or hud.lesson_busy():
		return false
	main.learn(id)
	hud.lesson(id)
	return true


## A few times a second: is something happening that the lamp has not taught
## yet, and has a new kind of foe come into sight? Also, near a hollow wall,
## a draught and a trickle of grit, so it can be found in the flat view too.
func _update_teach(dt: float) -> void:
	teach_t -= dt
	if teach_t > 0.0 or dead or depth <= 0:
		return
	teach_t = 0.25
	_listen_hollow()
	if teach_done:
		return
	var seen: Array = main.profile["seen"]
	for e in enemies:
		if not e.dead and e.visible and not seen.has(e.kind) and e.kind != "slimelet":
			main.saw(e.kind)
	if hud.lesson_busy():
		return
	var taught: Array = main.profile["taught"]
	if not taught.has("parry"):
		for e in enemies:
			if not e.dead and e.visible and e.state == "wind" and (e.kind == "husk" or e.kind == "brute") \
					and (e.position - ppos).length() < 90.0 and teach("parry"):
				return
	if not taught.has("reflect"):
		for s in shots:
			if not s["friendly"] and (s["pos"] - ppos).length() < 110.0 and teach("reflect"):
				return
	var k := oil / maxf(max_oil, 1.0)
	if not snuffed and k < 0.3 and teach("snuff"):
		return
	if snuffed and snuff_t > 1.0 and teach("dark"):
		return
	var near := 0
	if not taught.has("flask") or not taught.has("echo"):
		for e in enemies:
			if not e.dead and e.awake and e.visible and (e.position - ppos).length() < 110.0:
				near += 1
	if near >= 3 and oil >= FLASK_COST + 15.0 and teach("flask"):
		return
	# Swings in the last moment, and a fight still around her: an echo would land.
	if near >= 1 and echo_blows.size() >= 2 and echo_cd <= 0.0 and dash_stock > 0 and teach("echo"):
		return
	for id in powers:
		if powers[id] and teach(id):
			return
	if taught.size() >= Story.LESSONS.size() and seen.size() >= Story.FOES.size():
		teach_done = true


func _listen_hollow() -> void:
	draught_t -= 0.25
	if draught_t > 0.0:
		return
	for sc in secrets:
		if sc["open"]:
			continue
		var f: Vector2i = sc["f"]
		if vis[f.y * W + f.x] == 1 and (tile_center(f) - ppos).length() < 64.0:
			draught_t = 3.5
			var wc := tile_center(sc["w"])
			Sfx.play("thud", -24.0, 0.3)
			fx.spark(wc + Vector2(0, -12), Color(0.62, 0.57, 0.5, 0.8), 4, 10.0, 0.9, 1.5, 70.0)
			teach("hollow")


# --- Enemies, shots, loot -------------------------------------------------------

func on_wake(_e) -> void:
	if growl_cd <= 0.0:
		growl_cd = 0.7
		Sfx.play("growl", 0.0, 0.2)
	if depth == 1:
		_say_once("wake1", "Those are keepers' robes. Those were keepers.")
	elif depth == 3:
		_say_once("wake3", "The ink's got up and walked. Of course it has.")


func enemy_died(e) -> void:
	kills += 1
	main.tally("kills")
	# Read the light once: what this kill pays depends on how dark it was.
	var tier := light_tier()
	var loot: float = LOOT_BY_TIER[tier]
	if e.xp > 0:
		main.bank(roundi(e.xp * loot * stats["ember_k"]))
	# Only a kill by Wren's own hand holds the frame; one that burned or was
	# caught in a blast still shakes, but less.
	var stop: float = KILL_STOP.get(e.last_blow, 0.0)
	freeze(stop)
	add_shake(2.5 if stop > 0.0 else 1.5)
	Sfx.play("kill", -4.0)
	fx.spark(e.center(), e.tint, 6, 95.0, 0.4, 2.0)
	_disintegrate(e)
	if decals.size() < 240:
		# A ragged stain: a few overlapping blots rather than one clean disc.
		for k in 4:
			decals.append({"p": e.position + Vector2(rng.randf_range(-5, 5), rng.randf_range(-3, 3)),
				"r": e.radius * rng.randf_range(0.35, 0.9), "c": Color(0.05, 0.03, 0.07, 0.4)})
		decal_node.queue_redraw()
	if stats["shatter"] > 0.0 and e.xp > 0:
		fx.ring(e.position, 4.0, 34.0, 0.25, Color(1.0, 0.55, 0.15), false, 3.0)
		fx.spark(e.center(), Color(1.0, 0.6, 0.2), 14, 120.0, 0.4, 2.0)
		for o in enemies:
			if o != e and not o.dead and (o.position - e.position).length() < 36.0:
				o.hurt(stats["shatter"], (o.position - e.position).normalized() * 120.0, Color(1.0, 0.6, 0.2), "shatter")
				if stats["chainburst"] > 0.0 and not o.dead:
					o.burn_t = 3.0
					o.burn_dps = maxf(stats["burn"], 6.0)
	if e.spawn_idx >= 0:
		dead_spawns.append(e.spawn_idx)
	if e.xp > 0:
		drop("cinder", e.center(), int(ceil(e.xp * stats["xp_mult"] * XP_BY_TIER[tier])))
		var pity := 0.1 if hp <= 2 else 0.0
		if rng.randf() < (stats["heart_drop"] + pity) * loot:
			drop("heart", e.position)
		elif rng.randf() < 0.1 * loot:
			drop("oil", e.position)
	if e.kind == "slime":
		for k in 2:
			var c = spawn_enemy("slimelet", e.position + Vector2(k * 6.0 - 3.0, 0.0), e.room)
			c.awake = true
			c.st = 0.3 + 0.2 * k
	if e.kind == "warden":
		_boss_fell(e)
	if e.nemesis:
		_nemesis_fell(e)
	_update_seal(false)


## The opaque pixels of a sprite frame and their colours, read once and kept.
func _pixels(tex: Texture2D) -> Array:
	var id := tex.get_instance_id()
	if pix_cache.has(id):
		return pix_cache[id]
	var out: Array = []
	var img := Art.image_of(tex)
	if img != null:
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.5:
					out.append([Vector2(x + 0.5, y + 0.5), c])
	pix_cache[id] = out
	return out


## A fallen foe does not just vanish: its last frame flashes white and
## collapses, and its own pixels come loose and drift up as embers.
func _disintegrate(e) -> void:
	var spr: Sprite2D = e.spr
	if spr.texture == null:
		return
	var px := _pixels(spr.texture)
	if px.is_empty():
		return
	var rect := spr.get_rect()
	var xf := spr.global_transform
	var n := mini(px.size(), 160 if e.kind == "warden" else 70)
	var ember := Color(1.0, 0.55, 0.2)
	for i in n:
		var pick: Array = px[rng.randi() % px.size()]
		var lp: Vector2 = pick[0]
		if spr.flip_h:
			lp.x = rect.size.x - lp.x
		var wp: Vector2 = xf * (rect.position + lp)
		var c: Color = pick[1]
		# Each mote keeps a trace of the colour it was, but burns.
		var col := c.lerp(ember, 0.45).lightened(0.25)
		var out: Vector2 = (wp - e.center()).normalized()
		var vel: Vector2 = out * rng.randf_range(12.0, 45.0) + Vector2(rng.randf_range(-8.0, 8.0), -rng.randf_range(15.0, 50.0))
		fx.add_part(wp, e.position.y, vel, rng.randf_range(0.45, 1.1), rng.randf_range(1.2, 2.0), col, -55.0)
	# The husk of it: a white silhouette that squashes flat and fades.
	var ghost := Sprite2D.new()
	ghost.texture = spr.texture
	ghost.offset = spr.offset
	ghost.flip_h = spr.flip_h
	ghost.position = e.position
	ghost.scale = spr.scale
	ghost.material = Art.ghost_mat
	ents.add_child(ghost)
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_property(ghost, "scale", Vector2(spr.scale.x * 1.35, spr.scale.y * 0.15), 0.2).set_ease(Tween.EASE_IN)
	tw.tween_property(ghost, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(ghost.queue_free)


## A strike that meets a foe mid-attack, or in the last instant of its wind-up,
## turns the blow aside: the foe is staggered and Wren is spared.
func _parry(e) -> bool:
	var attacking: bool = e.state == "lunge" or e.state == "charge" or (e.state == "wind" and e.st < 0.14)
	if not attacking or e.kind == "warden":
		return false
	e.hurt(stats["dmg"] * 1.5, aim * 260.0, Color(1.0, 0.92, 0.65), "crit")
	if not e.dead:
		e.state = "rest"
		e.st = 0.4
		e.stun = 1.3
		e.touch_cd = 0.8
		e.sq_amp = 0.4
	invuln = maxf(invuln, 0.35)
	fx.impact(e.center() - aim * e.hit_r * 0.5, aim.angle(), Color(1.0, 0.85, 0.4), 1.9)
	fx.ring(e.center(), 4.0, 30.0, 0.25, Color(1.0, 0.85, 0.45), false, 3.0)
	hud.float_text(e.position + Vector2(0, -e.cy * 2.0 - 10.0), "PARRY", Color(1.0, 0.85, 0.4))
	hud.flash_white(0.45)
	slow_t = maxf(slow_t, 0.22)
	Sfx.play("parry", 0.0, 0.05)
	Sfx.play("punch", -6.0)
	_say_once("parry", "Meet them as they come, and they break on you.")
	main.tally("parries")
	if stats["riposte"] > 0.0:
		riposte_t = 1.5
	return true


## A hex struck out of the air flies back at whoever sent it, hotter.
func _reflect(s: Dictionary) -> void:
	var spd: float = maxf(s["vel"].length() * 2.2, 200.0)
	var dir := aim
	# Aim it back at the nearest foe in front, if there is one.
	var best = null
	var bd := 220.0
	for e in enemies:
		if e.dead or not e.visible:
			continue
		var v: Vector2 = e.center() - s["pos"]
		if v.length() < bd and aim.dot(v.normalized()) > 0.5:
			bd = v.length()
			best = e
	if best != null:
		dir = (best.center() - s["pos"]).normalized()
	var gold := Color(1.0, 0.8, 0.3)
	s["friendly"] = true
	s["vel"] = dir * spd
	s["dmg"] = stats["bolt_dmg"] * 1.5
	s["col"] = gold
	s["life"] = 1.4
	s["hit"] = []
	s["node"].modulate = gold
	fx.impact(s["pos"], dir.angle(), gold, 1.1)
	freeze(0.04)
	Sfx.play("deflect", -2.0, 0.15)
	_say_once("reflect", "Struck back. Let it learn what it threw.")
	main.tally("reflects")


## How dark Wren walks, from 0 Bright to 3 Dark (LIGHT_DARK). The one place the
## tier is worked out: loot, ambushes, the gloams' bark and the HUD all ask here.
func light_tier() -> int:
	if snuffed and snuff_t >= SNUFF_SETTLE:
		return LIGHT_DARK
	var k := oil / maxf(max_oil, 1.0)
	if k <= GLOAM_LOW:
		return LIGHT_DARK
	if k <= GLOAM_SAFE:
		return 2
	if k <= LIGHT_DIM_AT:
		return 1
	return 0


## What the dark pays right now, as a multiplier on drops (1.0 to 2.0).
func loot_mult() -> float:
	return LOOT_BY_TIER[light_tier()]


## How long a foe that notices Wren now rushes her (0 in good light).
func ambush_time() -> float:
	return AMBUSH_BY_TIER[light_tier()]


func _update_gloam(dt: float) -> void:
	if depth <= 0 or dead or god:
		return
	if light_tier() == LIGHT_DARK:
		_say_once("dark_tier", Story.LIGHT_DARK_LINE)
	var k := oil / maxf(max_oil, 1.0)
	var shades: Array = []
	for e in enemies:
		if e.kind == "gloam" and not e.dead:
			shades.append(e)
	# Snuffed by choice, the dark comes for her whatever the flask holds;
	# a few seconds' grace first, then faster the longer she hides.
	if snuffed:
		if snuff_t < SNUFF_SETTLE:
			return
		gloam_t -= dt * (1.0 + minf(snuff_t / 8.0, 1.5))
		if gloam_t > 0.0 or shades.size() >= 3:
			return
		gloam_t = rng.randf_range(2.5, 4.0)
		_spawn_gloam()
		return
	if k > GLOAM_SAFE:
		# With the lamp bright again, the shades come apart where they stand.
		for e in shades:
			e.dead = true
			e.visible = false
			_disintegrate(e)
		gloam_t = 2.0
		return
	if k > GLOAM_LOW * stats["gloam_k"]:
		return
	gloam_t -= dt
	if gloam_t > 0.0 or shades.size() >= 3:
		return
	gloam_t = rng.randf_range(2.5, 4.0)
	_spawn_gloam()


func _spawn_gloam() -> void:
	# Somewhere out past the light, on a tile that can reach her; in a cramped
	# spot with nowhere that far, somewhere closer will do.
	var far: Array = []
	var near: Array = []
	for y in range(maxi(1, ptile.y - 10), mini(H - 1, ptile.y + 11)):
		for x in range(maxi(1, ptile.x - 10), mini(W - 1, ptile.x + 11)):
			var idx := y * W + x
			if tiles[idx] != 1 or flow[idx] >= 9999:
				continue
			var d := (tile_center(Vector2i(x, y)) - ppos).length()
			if d >= 85.0 and d <= 150.0:
				far.append(Vector2i(x, y))
			elif d >= 50.0 and d < 85.0:
				near.append(Vector2i(x, y))
	var pool: Array = far if not far.is_empty() else near
	if pool.is_empty():
		return
	var t: Vector2i = pool[rng.randi() % pool.size()]
	var e = spawn_enemy("gloam", tile_center(t), -1)
	e.awake = true
	fx.spark(e.center(), Color(0.4, 0.25, 0.7, 0.8), 10, 40.0, 0.6, 2.0, -20.0)
	_say_once("gloam", "The light's thinning. Something's moving out there.")


func _purge() -> void:
	var gone := false
	for e in enemies:
		if e.dead:
			gone = true
			break
	if not gone:
		return
	var alive: Array = []
	for e in enemies:
		if e.dead:
			e.queue_free()
		else:
			alive.append(e)
	enemies = alive


func _update_seal(quiet: bool) -> void:
	if exit_room < 0:
		sealed = false
		return
	var now := false
	for e in enemies:
		if not e.dead and e.room == exit_room:
			now = true
			break
	if sealed and not now and not quiet:
		Sfx.play("lock")
		Sfx.play("chime", -4.0)
		hud.say("The seal on the stair gutters out.", 3.5, hud.C_EMBER)
	sealed = now


func drop(type: String, pos: Vector2, n: int = 1) -> void:
	for i in n:
		var s: Sprite2D
		if type == "cinder":
			s = _glow(over, Color(1.0, 0.62, 0.2, 1.0), 0.13, pos)
			var core := Sprite2D.new()
			core.texture = Art.tex["px"]
			core.material = Art.mat_unlit
			core.scale = Vector2(12, 12)
			core.modulate = Color(1.0, 0.95, 0.7)
			s.add_child(core)
		else:
			s = Sprite2D.new()
			s.texture = Art.tex["heart2" if type == "heart" else "oil"]
			s.material = Art.mat_unlit
			s.position = pos
			over.add_child(s)
		pickups.append({"type": type, "node": s, "pos": pos, "t": 0.0,
			"vel": Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(25.0, 95.0)})


func _update_shots(dt: float) -> void:
	var i := shots.size() - 1
	while i >= 0:
		var s: Dictionary = shots[i]
		s["pos"] += s["vel"] * dt
		s["life"] -= dt
		var pos: Vector2 = s["pos"]
		var gone: bool = s["life"] <= 0.0 or solid_at(pos)
		if gone and s["friendly"] and s["life"] > 0.0:
			_strike_wall(pos, 2.0)
		if not gone and s["friendly"]:
			# Ember fire: a bolt that crosses oil or web sets it alight.
			surf.ignite_at(pos, 3.0)
		if not gone and s["friendly"]:
			for e in enemies:
				if e.dead or s["hit"].has(e):
					continue
				if (e.center() - pos).length() < e.hit_r + s["r"]:
					e.hurt(s["dmg"], s["vel"].normalized() * 90.0, Color(1.0, 0.92, 0.65), "hit_bolt")
					fx.impact(pos, s["vel"].angle(), s["col"], 0.6)
					if stats["starfall"] > 0.0 and not s.get("split", false):
						for sgn in [-1.0, 1.0]:
							add_shot(pos, s["vel"].rotated(0.65 * sgn) * 0.85, true, s["dmg"] * 0.5, s["col"], 0, 0.28, 0.6)
							shots[shots.size() - 1]["split"] = true
							shots[shots.size() - 1]["hit"] = [e]
					if stats["burn"] > 0.0 and not e.dead:
						e.burn_t = 3.0
						e.burn_dps = stats["burn"]
					s["hit"].append(e)
					if s["pierce"] <= 0:
						gone = true
						break
					s["pierce"] -= 1
			for p in props:
				if p["type"] == "urn" and not p["done"] and (p["pos"] - pos).length() < 8.0:
					_break_urn(p)
		elif not gone and moth != null and (moth.position + moth.body.position - pos).length() < 5.0:
			moth.hurt()
			gone = true
		elif not gone and (pcenter() - pos).length() < 5.0:
			last_by_nem = s.get("nem", false)
			if hurt_player(s["dmg"], pos - s["vel"] * 0.1, 130.0, s.get("src", "")):
				gone = true
		s["node"].position = pos
		if gone:
			fx.spark(pos, s["col"], 7, 55.0, 0.3, 1.5)
			s["node"].queue_free()
			shots.remove_at(i)
		i -= 1


func _update_pickups(dt: float) -> void:
	var pc := pcenter()
	var i := pickups.size() - 1
	while i >= 0:
		var p: Dictionary = pickups[i]
		p["t"] += dt
		var pos: Vector2 = p["pos"]
		var vel: Vector2 = p["vel"]
		var type: String = p["type"]
		var wanted := not dead and (type == "cinder" or (type == "heart" and hp < max_hp) or (type == "oil" and oil < max_oil - 1.0))
		var to := pc - pos
		var d := to.length()
		if wanted and p["t"] > 0.3 and d < (70.0 if type == "cinder" else 34.0) * stats["magnet"]:
			vel = vel.move_toward(to / maxf(d, 0.01) * 260.0, 1400.0 * dt)
		else:
			vel = vel.move_toward(Vector2.ZERO, 260.0 * dt)
		var np := pos + vel * dt
		if solid_at(np) and not (wanted and d < 70.0 * stats["magnet"]):
			vel = Vector2.ZERO
			np = pos
		p["pos"] = np
		p["vel"] = vel
		var node: Sprite2D = p["node"]
		node.position = np + Vector2(0, sin(p["t"] * 5.0) * 1.2 if type != "cinder" else 0.0)
		if wanted and p["t"] > 0.3 and d < 9.0:
			match type:
				"cinder":
					add_xp(1)
					Sfx.play("cinder", -9.0, 0.15)
				"heart":
					hp = mini(max_hp, hp + 2)
					Sfx.play("heart")
					hud.float_text(ppos + Vector2(0, -18), "+1 heart", Color(1.0, 0.45, 0.55))
				"oil":
					oil = minf(max_oil, oil + 35.0)
					Sfx.play("oil")
					if moth != null:
						moth.feed()
					hud.float_text(ppos + Vector2(0, -18), "+oil", Color(1.0, 0.7, 0.25))
			node.queue_free()
			pickups.remove_at(i)
		i -= 1


func add_xp(n: int) -> void:
	xp += n
	if xp >= xp_next and levelup_t < 0.0:
		levelup_t = 0.3


func _level_up() -> void:
	xp -= xp_next
	level += 1
	xp_next = 14 + level * 8
	Sfx.play("levelup")
	fx.ring(ppos, 6.0, 60.0, 0.5, Color(1.0, 0.8, 0.4), false, 3.0)
	kick(0.07)
	_offer_boons("The warmth below reaches up to you", "Level %d  -  choose a kindling" % level)


## How hard the offers lean toward an aspect Wren has taken from: each
## kindling she holds of it adds this to its cards' weight (counting up to
## three), against 1 for any card. With two of one aspect held and the pool
## about even, roughly three in four of the leaning cards are of it.
const ASPECT_PULL := 2.0


func _offer_boons(title: String, sub: String) -> void:
	var opts := draw_offer(4 if main.has_lamp("chapel") else 3)
	# Once Wren holds both halves of a pair, its combined kindling may take a
	# place; never the card from another aspect.
	var ready: Array = []
	for d in Story.DUOS:
		if not boons.has(d["id"]) and boons.has(d["needs"][0]) and boons.has(d["needs"][1]):
			ready.append(d)
	if not ready.is_empty() and rng.randf() < 0.65:
		var d: Dictionary = ready[rng.randi() % ready.size()]
		var card := {"id": d["id"], "name": d["name"], "desc": d["desc"], "tag": "Two kindlings, made one",
			"col": Story.DUO_COL, "icon": hud.ICONS.get(d["needs"][0], "i_flame")}
		var slots: Array = []
		for i in opts.size():
			if not opts[i].get("off", false):
				slots.append(i)
		if slots.is_empty():
			opts.append(card)
		else:
			opts[slots[rng.randi() % slots.size()]] = card
	if opts.is_empty():
		return
	var again := Callable()
	if main.has_lamp("belltower") and reroll_depth != depth:
		again = func():
			reroll_depth = depth
			_offer_boons(title, sub)
	_show_offer("boon", title, sub, opts, func(i): apply_boon(opts[i]["id"]), again, "Ring the bell: a fresh choice")


## Every offer of cards (kindlings, relics) goes through here, so the bots and
## their tallies can see what was on the table. A bot picks through the
## HUD's own auto-pick, like any other choice.
func _show_offer(kind: String, title: String, sub: String, opts: Array, cb: Callable,
		again: Callable = Callable(), again_label: String = "Back") -> void:
	offer_kind = kind
	offer.clear()
	for o in opts:
		offer.append(o["id"])
	hud.show_choice(title, sub, opts, cb, again, again_label)


## Whether a kindling may still be offered: not a one-time kindling Wren
## already holds, not one stacked to its cap (Story.BOONS "max"), and not
## Hollow Heart when it would leave her a single heart.
func can_offer(b: Dictionary) -> bool:
	var cap: int = 1 if b.get("unique", false) else int(b.get("max", 99))
	if boons.count(b["id"]) >= cap:
		return false
	if b["id"] == "hollow" and max_hp <= 4:
		return false
	return true


## How many kindlings Wren holds of each lantern aspect (Story.ASPECTS).
func aspect_counts() -> Dictionary:
	var out := {}
	for a in Story.ASPECTS:
		out[a] = 0
	for b in Story.BOONS:
		out[b["aspect"]] += boons.count(b["id"])
	return out


## n kindlings for an offer, as cards. With nothing taken yet, one of each
## aspect, so the first pick chooses a road. After that the draw leans toward
## the aspects Wren holds, but one card always comes from outside her leading
## aspect, so a turn is still on the table. At most one bargain at a time.
func draw_offer(n: int) -> Array:
	var pool: Array = []
	for b in Story.BOONS:
		if can_offer(b):
			pool.append(b)
	var held := aspect_counts()
	var lead := ""
	for a in held:
		if held[a] > 0 and (lead == "" or held[a] > held[lead]):
			lead = a
	var picked: Array = []
	var off_id := ""
	if lead == "":
		for a in Story.ASPECTS:
			_offer_take(picked, pool, _offer_of(pool, a, true))
	else:
		_offer_take(picked, pool, _offer_of(pool, lead, false))
		if not picked.is_empty():
			off_id = picked[0]["id"]
	while picked.size() < n and not pool.is_empty():
		_offer_take(picked, pool, _draw_leaning(pool, held))
	picked = picked.slice(0, n)
	# Shuffled, so the card from elsewhere is not always in the same place.
	for i in range(picked.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = picked[i]
		picked[i] = picked[j]
		picked[j] = tmp
	var cards: Array = []
	for b in picked:
		var c := boon_card(b)
		c["off"] = b["id"] == off_id
		cards.append(c)
	return cards


func _offer_take(picked: Array, pool: Array, b: Dictionary) -> void:
	if b.is_empty():
		return
	picked.append(b)
	pool.erase(b)
	if b.get("bargain", false):
		for o in pool.duplicate():
			if o.get("bargain", false):
				pool.erase(o)


## A random kindling from the pool that is (same) or is not (not same) of aspect a.
func _offer_of(pool: Array, a: String, same: bool) -> Dictionary:
	var c: Array = []
	for b in pool:
		if (b["aspect"] == a) == same:
			c.append(b)
	return {} if c.is_empty() else c[rng.randi() % c.size()]


## A kindling drawn from the pool, weighted toward the aspects Wren holds.
func _draw_leaning(pool: Array, held: Dictionary) -> Dictionary:
	if pool.is_empty():
		return {}
	var total := 0.0
	for b in pool:
		total += 1.0 + ASPECT_PULL * mini(held[b["aspect"]], 3)
	var r := rng.randf() * total
	for b in pool:
		r -= 1.0 + ASPECT_PULL * mini(held[b["aspect"]], 3)
		if r <= 0.0:
			return b
	return pool[pool.size() - 1]


## A kindling as an offer card: its Story entry, how many of it Wren already
## holds against its cap, and whether taking it finishes a pair she has half
## of (Story.DUOS) or starts one.
func boon_card(b: Dictionary) -> Dictionary:
	var o := b.duplicate()
	var have := boons.count(b["id"])
	if have > 0 and b.has("max"):
		o["held"] = "%d of %d" % [have, int(b["max"])]
	if have > 0:
		return o
	for d in Story.DUOS:
		var needs: Array = d["needs"]
		if boons.has(d["id"]) or not needs.has(b["id"]):
			continue
		var other: String = needs[1] if needs[0] == b["id"] else needs[0]
		if boons.has(other):
			o["hint"] = "Pairs with %s  >  %s" % [boon_name(other), d["name"]]
			o["pairs"] = true
			break
		if not o.has("hint"):
			o["hint"] = "Half of %s, with %s" % [d["name"], boon_name(other)]
	return o


func boon_name(id: String) -> String:
	for b in Story.BOONS:
		if b["id"] == id:
			return b["name"]
	return id


# --- Relics ---------------------------------------------------------------------

## The relics Wren does not carry yet, in Story.RELICS order.
func relics_unowned() -> Array:
	var out: Array = []
	for r in Story.RELICS:
		var id: String = r["power"]
		if not (spare_match if id == "match" else powers[id]):
			out.append(r)
	return out


## A relic stand: up to three of Maren's tools that Wren does not carry, and
## she takes one. Each answers a different trouble, and whatever she passes
## over waits on a deeper stand, so by the fourth depth she holds them all
## whichever order she chose. With nothing left, the stand is a kindling cache.
func _offer_relics() -> void:
	var left := relics_unowned()
	if left.is_empty():
		_offer_boons("A cache of kindling", "Maren left these on her way down. Take one.")
		return
	for i in range(left.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = left[i]
		left[i] = left[j]
		left[j] = tmp
	left = left.slice(0, 3)
	var opts: Array = []
	for r in left:
		opts.append({"id": r["power"], "name": r["name"], "desc": r["card"], "tag": r["role"],
			"icon": r["icon"], "col": Color(1.0, 0.85, 0.5)})
	var sub := "She left these on the stand. Take one; the others wait deeper down."
	if left.size() == 1:
		sub = "The last of them. Take it."
	_show_offer("relic", "Maren's tools", sub, opts, func(i): take_relic(left[i]["power"]))


func take_relic(id: String) -> void:
	var rel: Dictionary = {}
	for r in Story.RELICS:
		if r["power"] == id:
			rel = r
	grant_power(id)
	var how: String = "" if rel["key"] == "" else "\n\n[ Press %s to use it. ]" % rel["key"]
	if pad != null and how != "":
		how = "\n\n[ Its rune now sits by your right thumb. ]"
	hud.dialog([["RELIC  -  " + (rel["name"] as String).to_upper(), rel["text"] + how]])


func apply_boon(id: String) -> void:
	boons.append(id)
	match id:
		"edge":
			stats["dmg"] *= 1.25
		"reach":
			stats["reach"] *= 1.2
		"swift":
			stats["speed"] *= 1.12
		"heart":
			max_hp += 2
			hp = mini(max_hp, hp + 2)
		"flask":
			max_oil += 35.0
			oil = max_oil
		"kindle":
			stats["bolt_dmg"] *= 1.4
		"twin":
			stats["bolt_n"] += 2
		"step":
			stats["dash_cd"] *= 0.75
		"wick":
			stats["light"] *= 1.2
			stats["oil_regen"] += 1.5
		"glean":
			stats["heart_drop"] += 0.06
		"sear":
			stats["sear"] = 16.0
		"siphon":
			stats["siphon"] += 3.0
		"thorn":
			stats["thorns"] = 18.0
		"pierce":
			stats["pierce"] += 1
		"orbit":
			stats["orbit"] += 2
			_sync_motes()
		"wave":
			stats["wave"] += 1.0
		"burn":
			stats["burn"] += 6.0
		"shatter":
			stats["shatter"] += 12.0
		"blink":
			stats["dash_n"] = 2
			dash_stock = 2
		"trail":
			stats["trail"] = 5.0
		"magnet":
			stats["magnet"] *= 1.8
			stats["xp_mult"] += 0.25
		"crit":
			stats["crit"] += 0.15
		"focus":
			stats["power"] *= 1.3
			stats["cdr"] *= 0.82
		"wildfire", "starfall", "flashstep", "chainburst", "riposte":
			stats[id] = 1.0
		"echo":
			stats["echo"] += 0.35
			stats["echo_cd"] *= 0.6
		"conflux":
			stats["orbit"] += 2
			stats["mote_k"] = 1.5
			_sync_motes()
		# Bargains: the gain, then the price.
		"burnwick":
			stats["bolt_dmg"] *= 1.6
			stats["oil_regen"] *= 0.5
		"pact":
			stats["ember_k"] = 1.5
			stats["xp_mult"] += 0.5
			# Gloams come below 35% of the flask, not 20% (they melt above 40%).
			stats["gloam_k"] = 1.75
		"lens":
			stats["power"] *= 1.5
			stats["power_cost"] *= 1.4
		"leaden":
			stats["dmg"] *= 1.45
			stats["speed"] *= 0.85
		"hollow":
			max_hp = maxi(2, max_hp - 2)
			hp = clampi(hp, 1, max_hp)
			stats["crit"] += 0.25
		"moth_cloak":
			stats["dash_len"] = 1.5
			stats["frail"] = 1
	for d in Story.DUOS:
		if d["id"] == id:
			main.tally("duos")
	if xp >= xp_next:
		levelup_t = 0.5


func boon_names() -> Array:
	var out: Array = []
	for b in Story.BOONS:
		var n := boons.count(b["id"])
		if n == 1:
			out.append(b["name"])
		elif n > 1:
			out.append("%s x%d" % [b["name"], n])
	return out


# --- Props ----------------------------------------------------------------------

func _break_urn(p: Dictionary) -> void:
	p["done"] = true
	p["node"].queue_free()
	var pos: Vector2 = p["pos"]
	Sfx.play("urn", -4.0, 0.15)
	fx.spark(pos + Vector2(0, -4), Color(0.8, 0.55, 0.35), 10, 70.0, 0.4, 2.0, 160.0)
	# Broken in the dark, an urn gives up more (loot_mult, up to twice).
	var loot := loot_mult()
	drop("cinder", pos, roundi(rng.randi_range(1, 3) * loot))
	var roll := rng.randf()
	if roll < 0.1 * loot:
		drop("heart", pos)
	elif roll < 0.3 * loot:
		drop("oil", pos)


func _update_props(dt: float) -> void:
	near_prop = null
	var bd := 26.0
	for p in props:
		if p["done"] and p["type"] != "lamp" and p["type"] != "chest":
			continue
		p["t"] += dt
		var pos: Vector2 = p["pos"]
		var t: float = p["t"]
		var near := (pos - ppos).length_squared() < 52000.0
		match p["type"]:
			"brazier":
				if near:
					if vis_at(pos) and rng.randf() < dt * 16.0:
						fx.flame(pos + Vector2(0, -9))
					p["light"].energy = 0.95 * (0.92 + 0.08 * sin(t * 9.0) + 0.05 * sin(t * 21.3))
			"lamp":
				if p["done"] and near and vis_at(pos) and rng.randf() < dt * 10.0:
					fx.flame(pos + Vector2(0, -15), Color(1.0, 0.85, 0.4, 0.8))
			"page":
				p["spr"].position.y = sin(t * 2.5) * 1.5 - 2.0
				p["glow"].modulate.a = 0.4 + 0.15 * sin(t * 3.0)
			"plaque":
				p["glow"].modulate.a = 0.22 + 0.1 * sin(t * 2.0)
			"moth":
				# Fluttering about its own small light.
				p["spr"].position = Vector2(sin(t * 2.3) * 5.0, -14.0 + sin(t * 3.7) * 3.0)
				p["spr"].texture = MothS.make_frames()[int(t * 12.0) % 2]
				p["spr"].flip_h = cos(t * 2.3) < 0.0
			"stairs":
				p["glow"].visible = sealed
				p["glow"].modulate.a = 0.55 + 0.2 * sin(t * 4.0)
			"cage":
				var pulse := 1.0 + 0.12 * sin(t * 2.2) + 0.05 * sin(t * 7.0)
				p["glow"].scale = Vector2(0.32, 0.32) * pulse
				p["halo"].modulate.a = 0.4 + 0.15 * sin(t * 2.2)
				if near and rng.randf() < dt * 8.0:
					fx.spark(pos + Vector2(0, -6), Color(1.0, 0.8, 0.4, 0.9), 1, 14.0, 0.9, 1.5, -18.0)
		if (p["done"] and p["type"] != "lamp") or not PROMPTS.has(p["type"]):
			continue
		if p["type"] == "cage" and not boss_dead:
			continue
		var d := (pos - ppos).length()
		if d < bd:
			bd = d
			near_prop = p


func prompt_for(p: Dictionary) -> String:
	if p["type"] == "stairs" and sealed:
		return "Sealed"
	if p["type"] == "lamp" and p["done"]:
		return "Rest at the lamp  (save)"
	return PROMPTS[p["type"]]


func interact() -> void:
	var p = near_prop
	if p == null or dead:
		return
	var pos: Vector2 = p["pos"]
	match p["type"]:
		"chest":
			p["done"] = true
			p["spr"].texture = Art.tex["chest1"]
			Sfx.play("chest")
			Sfx.play("coins")
			Sfx.play("jingle", -8.0)
			fx.spark(pos + Vector2(0, -4), Color(1.0, 0.85, 0.4), 16, 70.0, 0.6, 2.0)
			# Opened in the dark, a chest gives up more: at Dark, a heart and a
			# flask for certain and twice the embers.
			var loot := loot_mult()
			if loot > 1.0:
				hud.float_text(pos + Vector2(0, -16), "+%d%% in the dark" % roundi((loot - 1.0) * 100.0), Color(0.75, 0.65, 1.0))
			drop("cinder", pos + Vector2(0, 4), roundi(rng.randi_range(8, 13) * loot))
			if rng.randf() < 0.5 * loot:
				drop("heart", pos + Vector2(0, 4))
			if rng.randf() < 0.6 * loot:
				drop("oil", pos + Vector2(0, 4))
			if p.get("secret", false):
				# A hollow-wall hoard: a heart for certain, and embers for the town.
				drop("heart", pos + Vector2(4, 4))
				drop("cinder", pos + Vector2(0, 4), 10)
				var hoard := roundi(25 * loot)
				main.bank(hoard)
				hud.say("A hoard behind the wall. (+%d embers)" % hoard, 3.5, hud.C_EMBER)
		"lamp":
			if main.has_lamp("maren"):
				hp = max_hp
			if p["done"]:
				# Already lit: resting here just writes the save again.
				oil = max_oil
				Sfx.play("chime", -4.0)
				fx.spark(pos + Vector2(0, -14), Color(1.0, 0.85, 0.45), 12, 50.0, 0.6, 1.5)
				hud.say("You rest by the lamp. Your descent is saved.", 3.0, hud.C_EMBER)
			else:
				_light_lamp(p)
				hp = mini(max_hp, hp + 2)
				oil = max_oil
				Sfx.play("fire")
				Sfx.play("whoomp", -4.0)
				fx.spark(pos + Vector2(0, -14), Color(1.0, 0.85, 0.45), 24, 80.0, 0.7, 2.0)
				hud.say("The wayside lamp catches. Wounds ease, the flask fills, and your descent is saved.", 4.5, hud.C_EMBER)
				if moth != null:
					moth.feed(2)
				_say_once("lamp", "\"Light every one you pass,\" she used to say. \"Somebody's always behind you.\"")
			cine(3.9, 1.2, pos + Vector2(0, -8))
			save_game(p["idx"])
		"moth":
			if oil < 10.0:
				hud.float_text(ppos + Vector2(0, -26), "NO OIL", Color(0.8, 0.6, 0.4))
				return
			oil -= 10.0
			p["done"] = true
			lights.erase(p["light"])
			p["node"].queue_free()
			_make_moth(1, 3, 0)
			moth.position = pos + Vector2(0, -14)
			Sfx.play("chime", -4.0)
			fx.spark(pos + Vector2(0, -14), Color(0.85, 0.92, 1.0), 14, 40.0, 0.7, 1.5)
			hud.say("The moth drinks, and settles on the lantern. Wren calls it Flit.", 4.5, hud.C_TEAL)
			main.tally("flits")
		"page":
			p["done"] = true
			p["node"].queue_free()
			pages += 1
			main.bank(5)
			Sfx.play("page")
			add_xp(5)
			hud.dialog([Story.PAGES[depth - 1]])
		"plaque":
			if not p.has("read"):
				p["read"] = true
				pages += 1
				main.bank(3)
				add_xp(3)
			Sfx.play("page", -4.0)
			hud.dialog([Story.PLAQUES[depth - 1]])
		"relic":
			p["done"] = true
			lights.erase(p["light"])
			p["node"].queue_free()
			Sfx.play("relic")
			Sfx.play("power", -4.0)
			fx.spark(pos + Vector2(0, -12), Color(1.0, 0.85, 0.45), 30, 90.0, 0.8, 2.0)
			cine(4.2, 1.0, pos + Vector2(0, -8))
			_offer_relics()
		"stairs":
			if sealed:
				Sfx.play("thud", -8.0)
				hud.say("Sealed. Something in this room still holds it shut.", 3.0, hud.C_EMBER)
			else:
				Sfx.play("stairs")
				cine(4.6, 1.5, pos)
				hud.fade_through(func(): load_floor(depth + 1))
		"cage":
			Sfx.play("ember")
			hud.show_choice("Your hands now, Lampwright", "The latch is small and plain.", Story.CHOICE,
				func(i): main.ending(i))


# --- Camera, decals, scripted moments ------------------------------------------

## Holds the camera on a point (or just a zoom level) for a moment.
func cine(zoom: float, secs: float, at = null) -> void:
	cine_zoom = zoom
	cine_t = secs
	cine_has_pos = at != null
	if at != null:
		cine_pos = at


## A quick punch in (positive) or out (negative) that settles by itself. It is
## a jolt like the shake, so the shake setting tones it down too.
func kick(a: float) -> void:
	a *= shake_scale()
	if absf(a) > absf(zoom_kick):
		zoom_kick = a


## The camera leads where Wren is heading and looking, pulls back as a fight
## grows, frames the Warden, and leans in for conversations and deaths.
func _update_camera(dt: float) -> void:
	var talking: bool = hud.modal == "dialog" or hud.modal == "choice"
	var look := Vector2.ZERO
	if pad == null and not bot and not dead and not hud.blocking():
		look = (view.screen_mouse() - view.screen_size() * 0.5) / cam.zoom.x * 0.18
	var target := ppos + Vector2(0, -6) + look
	if not hud.blocking():
		target += pvel * 0.16
	var near := 0
	for e in enemies:
		if e.awake and not e.dead and (e.position - ppos).length_squared() < 30000.0:
			near += 1
	var zt := 3.0 - clampf((near - 2) * 0.07, 0.0, 0.42)
	var fighting_boss: bool = boss_started and not boss_dead and is_instance_valid(boss)
	if fighting_boss:
		zt = 2.6
		target = target.lerp(boss.position + Vector2(0, -12), 0.6 if talking else 0.35)
	if dead:
		zt = 4.4
		target = ppos + Vector2(0, -6)
	elif talking:
		zt = 3.7
		if near_prop != null and not fighting_boss:
			target = target.lerp(near_prop["pos"], 0.45)
	if cine_t > 0.0:
		cine_t -= dt
		zt = cine_zoom
		if cine_has_pos:
			target = cine_pos
	intro_t = maxf(0.0, intro_t - dt)
	if not cam_script:
		cam_zoom = lerpf(cam_zoom, zt, 1.0 - exp(-dt * 3.0))
		zoom_kick = lerpf(zoom_kick, 0.0, 1.0 - exp(-dt * 9.0))
		var z := cam_zoom * (1.0 + zoom_kick)
		cam.zoom = Vector2(z, z)
	cam.position = cam.position.lerp(target, 1.0 - exp(-dt * (4.5 if cine_t > 0.0 or talking else 9.0)))
	_update_shake(dt)
	cam_punch = cam_punch.lerp(Vector2.ZERO, 1.0 - exp(-dt * 14.0))
	cam.offset = shake_off + cam_punch


## Drains the trauma and picks this frame's shake. The lean wanders smoothly
## between fresh random points, thirty a second, rather than jumping every frame
## (at 200 fps that is a blur, not a shake), and is rounded to whole art pixels:
## the world picture then jumps cleanly by its own pixels, and only the camera's
## smooth motions (following Wren, the punch) go through world_view's
## leftover-fraction slide.
func _update_shake(dt: float) -> void:
	trauma = maxf(0.0, trauma - dt * TRAUMA_DECAY)
	var amp: float = trauma * trauma * SHAKE_PX * shake_scale()
	if amp < 0.5:
		shake_off = Vector2.ZERO
		return
	_shake_clock += dt * SHAKE_HZ
	if _shake_clock >= 1.0:
		_shake_clock = fmod(_shake_clock, 1.0)
		_shake_from = _shake_to
		_shake_to = Vector2(_shake_rng.randf_range(-1.0, 1.0), _shake_rng.randf_range(-1.0, 1.0))
	var n := _shake_from.lerp(_shake_to, _shake_clock)
	if shake_axis != Vector2.ZERO:
		n = shake_axis * n.x + shake_axis.orthogonal() * n.y * 0.3
	shake_off = (n * amp).round()


func _draw_decals() -> void:
	for d in decals:
		decal_node.draw_circle(d["p"], d["r"], d["c"])


func _update_events(dt: float) -> void:
	if dead:
		death_t -= dt
		if death_t <= 0.0 and not death_shown:
			death_shown = true
			main.player_died()
		return
	if levelup_t >= 0.0:
		levelup_t -= dt
		if levelup_t < 0.0:
			_level_up()
			return
	# In the 3D view a hollow wall leaks light; the first one seen, Wren says so.
	if view3d != null and view3d.active and not said.has("hollow"):
		for sc in secrets:
			var f: Vector2i = sc["f"]
			if not sc["open"] and vis[f.y * W + f.x] == 1 and (tile_center(f) - ppos).length() < 110.0:
				_say_once("hollow", "Light through the cracks. That wall's hollow.")
	if boss != null and not boss_started and (boss.position - ppos).length() < 105.0:
		boss_started = true
		hud.dialog(Story.BOSS_RETRY if main.boss_seen else Story.BOSS_INTRO, _boss_begin)
		main.boss_seen = true
		return
	if boss_end_t >= 0.0:
		boss_end_t -= dt
		if boss_end_t < 0.0:
			hud.dialog(Story.BOSS_END, func(): hud.say("The Ember waits in its cage.", 5.0, hud.C_EMBER))


func _boss_begin() -> void:
	boss.rouse()
	Sfx.play("roar")
	Sfx.play("gong")
	Sfx.play_music("boss")
	add_shake(6.0)
	fx.ring(boss.position, 8.0, 80.0, 0.6, Color(1.0, 0.5, 0.2), false, 3.0)


func boss_phase(p: int) -> void:
	kick(-0.12)
	Sfx.play("roar", 0.0)
	Sfx.play("gong")
	add_shake(8.0)
	fx.ring(boss.position, 8.0, 100.0, 0.6, Color(1.0, 0.5, 0.2), false, 4.0)
	hud.say(Story.BOSS_TAUNTS[p - 2], 5.0, hud.C_EMBER)
	if p == 3:
		light_target = 0.45
	# Shove Wren clear and sweep the air so a phase change is never a cheap hit.
	var away: Vector2 = ppos - boss.position
	if away.length() < 70.0:
		pknock = away.normalized() * 260.0
	for s in shots:
		if not s["friendly"]:
			s["life"] = 0.0


func _boss_fell(e) -> void:
	main.bank(80)
	main.tally("wardens")
	boss_dead = true
	light_target = 1.0
	slow_t = 1.5
	cine(4.2, 2.6, e.position + Vector2(0, -12))
	freeze(0.25, 0.25)
	add_shake(12.0)
	Sfx.play("boom")
	Sfx.play("bell", 2.0, 0.0)
	Sfx.play_music("title")
	fx.spark(e.center(), Color(1.0, 0.6, 0.2), 60, 170.0, 1.2, 3.0)
	fx.ring(e.position, 10.0, 160.0, 0.9, Color(1.0, 0.7, 0.3), false, 5.0)
	scorch(e.position, 16.0)
	for s in shots:
		s["life"] = 0.0
	for o in enemies:
		if o != e and not o.dead:
			o.xp = 0
			o.die()
	boss_end_t = 1.8


# --- Powers ---------------------------------------------------------------------

func grant_power(id: String) -> void:
	if id == "match":
		spare_match = true
		return
	powers[id] = true
	pcd[id] = 0.0


## What a power costs in oil; the Cracked Lens bargain raises it.
func power_cost(id: String) -> float:
	return Story.POWERS[id]["cost"] * stats["power_cost"]


func _power_ready(id: String) -> bool:
	if dead or not powers[id] or pcd[id] > 0.0:
		return false
	var cost: float = power_cost(id)
	if oil < cost:
		hud.float_text(ppos + Vector2(0, -20), "no oil", Color(1.0, 0.5, 0.3))
		Sfx.play("ui", 0.0)
		pcd[id] = 0.3
		return false
	oil -= cost
	pcd[id] = Story.POWERS[id]["cd"] * stats["cdr"]
	return true


## Q: a ring of fire that throws everything back.
func cast_nova() -> void:
	if not _power_ready("nova"):
		return
	_nova_burst(64.0, 24.0 * stats["power"] * (1.0 + 0.06 * (level - 1)))


func _nova_burst(radius: float, dmg: float) -> void:
	pose = "raise"
	pose_t = 0.35
	var o := pcenter()
	for e in enemies:
		if e.dead:
			continue
		var v: Vector2 = e.center() - o
		if v.length() < radius + e.hit_r:
			e.hurt(dmg, v.normalized() * 240.0, Color(1.0, 0.6, 0.2), "hit_heavy")
			e.stun = maxf(e.stun, 0.4)
	for s in shots:
		if not s["friendly"] and (s["pos"] - o).length() < radius + 6.0:
			s["life"] = 0.0
	for p in props:
		if p["type"] == "urn" and not p["done"] and (p["pos"] - ppos).length() < radius:
			_break_urn(p)
	fx.ring(ppos, 6.0, radius, 0.28, Color(1.0, 0.75, 0.3), false, 6.0)
	fx.ring(ppos, 4.0, radius * 0.8, 0.4, Color(1.0, 0.45, 0.1, 0.5), false, 3.0)
	fx.spark(o, Color(1.0, 0.7, 0.25), 50, 220.0, 0.55, 2.5)
	scorch(ppos, 14.0)
	surf.ignite_at(ppos, radius * 0.7)
	add_shake(7.0)
	kick(-0.08)
	freeze(0.06)
	nova_flash = 1.0
	Sfx.play("fire", 2.0)
	Sfx.play("boom", -6.0)


## R: lightning that picks a target near where you are aiming, then chains.
func cast_spark() -> void:
	if not powers["spark"] or pcd["spark"] > 0.0 or dead:
		return
	var o := pcenter()
	var focus := o + aim * 70.0
	var first = null
	var bd := 1e9
	for e in enemies:
		if e.dead or (e.center() - o).length() > 190.0 or not los(o, e.center()):
			continue
		var d: float = (e.center() - focus).length()
		if d < bd:
			bd = d
			first = e
	if first == null:
		return
	if not _power_ready("spark"):
		return
	var dmg: float = 18.0 * stats["power"] * (1.0 + 0.06 * (level - 1))
	pose = "point"
	pose_t = 0.3
	var from := o
	var cur = first
	var struck: Array = []
	for jump in 6:
		struck.append(cur)
		var to: Vector2 = cur.center()
		fx.bolt(from, to, Color(0.65, 0.85, 1.0))
		fx.spark(to, Color(0.7, 0.9, 1.0), 8, 90.0, 0.3, 1.5)
		cur.hurt(dmg, (to - from).normalized() * 60.0, Color(0.7, 0.9, 1.0), "zap_hit")
		cur.stun = maxf(cur.stun, 0.7)
		dmg *= 0.85
		from = to
		var nxt = null
		var nd := 82.0
		for e in enemies:
			if e.dead or struck.has(e):
				continue
			var d2: float = (e.center() - from).length()
			if d2 < nd:
				nd = d2
				nxt = e
		if nxt == null:
			break
		cur = nxt
	add_shake(4.0)
	nova_flash = maxf(nova_flash, 0.5)
	Sfx.play("zap", 0.0)
	Sfx.play("thunder")


## F: a circle of hearth-light that slows and burns what enters it.
func cast_ward() -> void:
	if not _power_ready("ward"):
		return
	pose = "raise"
	pose_t = 0.4
	var node := Node2D.new()
	node.position = ppos
	over.add_child(node)
	_glow(node, Color(1.0, 0.7, 0.3, 0.35), 1.6, Vector2.ZERO)
	var l := PointLight2D.new()
	l.texture = Art.tex["light"]
	l.color = Color(1.0, 0.8, 0.5)
	l.energy = 1.1
	l.texture_scale = 1.3
	node.add_child(l)
	wards.append({"p": ppos, "t": 6.0, "r": 50.0, "node": node, "acc": 0.0})
	fx.ring(ppos, 4.0, 50.0, 0.35, Color(1.0, 0.8, 0.4), false, 4.0)
	Sfx.play("ward")
	Sfx.play("fire", -6.0)


func _sync_motes() -> void:
	while motes.size() > stats["orbit"]:
		motes.pop_back().queue_free()
	while motes.size() < stats["orbit"]:
		var m := _glow(over, Color(1.0, 0.65, 0.2, 1.0), 0.26, ppos)
		var core := Sprite2D.new()
		core.texture = Art.tex["glow"]
		core.material = Art.mat_add
		core.scale = Vector2(0.4, 0.4)
		m.add_child(core)
		motes.append(m)


func _update_powers(dt: float) -> void:
	# Hearth wards.
	var i := wards.size() - 1
	while i >= 0:
		var wd: Dictionary = wards[i]
		wd["t"] -= dt
		wd["acc"] += dt
		var wp: Vector2 = wd["p"]
		var wr: float = wd["r"]
		var pulse: bool = wd["acc"] >= 0.5
		if pulse:
			wd["acc"] = 0.0
		for e in enemies:
			if e.dead or (e.position - wp).length() > wr + e.radius:
				continue
			e.slow_t = 0.3
			if pulse:
				e.hurt(7.0 * stats["power"], Vector2.ZERO, Color(1.0, 0.75, 0.35), "ward_hit")
		for s in shots:
			if not s["friendly"] and (s["pos"] - wp).length() < wr:
				s["life"] = 0.0
		if (ppos - wp).length() < wr:
			oil = minf(max_oil, oil + 14.0 * dt)
		if rng.randf() < dt * 20.0:
			fx.flame(wp + Vector2.from_angle(rng.randf() * TAU) * wr * rng.randf_range(0.3, 1.0), Color(1.0, 0.7, 0.3, 0.7))
		wd["node"].modulate.a = clampf(wd["t"], 0.0, 1.0)
		if wd["t"] <= 0.0:
			wd["node"].queue_free()
			wards.remove_at(i)
		i -= 1

	# Cinder trail left by a dash.
	fire_acc += dt
	var burn_tick := fire_acc >= 0.25
	if burn_tick:
		fire_acc = 0.0
	i = fires.size() - 1
	while i >= 0:
		var f: Dictionary = fires[i]
		f["t"] -= dt
		var fp: Vector2 = f["p"]
		if rng.randf() < dt * 9.0:
			fx.flame(fp + Vector2(rng.randf_range(-3.0, 3.0), 0.0))
		if burn_tick:
			surf.ignite_at(fp, 4.0)
			for e in enemies:
				if not e.dead and (e.position - fp).length() < 11.0 and e.orbit_cd <= 0.0:
					e.orbit_cd = 0.25
					e.hurt(stats["trail"], Vector2.ZERO, Color(1.0, 0.6, 0.2), "burn")
		if f["t"] <= 0.0:
			fires.remove_at(i)
		i -= 1

	# Ember motes.
	if motes.size() > 0:
		mote_a += dt * 3.4
		var pc := pcenter()
		for k in motes.size():
			var mp := pc + Vector2.from_angle(mote_a + TAU * k / motes.size()) * 27.0
			motes[k].position = mp
			motes[k].visible = not dead
			if dead:
				continue
			for e in enemies:
				if not e.dead and e.orbit_cd <= 0.0 and (e.center() - mp).length() < e.hit_r + 4.0:
					e.orbit_cd = 0.45
					e.hurt(7.0 * stats["power"] * stats["mote_k"], (e.center() - pc).normalized() * 50.0, Color(1.0, 0.7, 0.3), "ember_hit")
			for s in shots:
				if not s["friendly"] and (s["pos"] - mp).length() < 6.0:
					s["life"] = 0.0


## Poses the lantern-staff: swung through a strike, levelled to cast a bolt,
## raised for a burst, trailing in a dash, and bobbing at Wren's side otherwise.
func _update_staff(dt: float, moving: bool) -> void:
	var face := -1.0 if aim.x < 0.0 else 1.0
	var chest := Vector2(0, -8)
	var rot := 0.0
	var pos := Vector2(6.5 * face, -7.5)
	var snap := false
	if dead:
		rot = 1.45 * face
		pos = Vector2(7.0 * face, -1.0)
	elif swing_t >= 0.0:
		swing_t += dt / swing_dur
		var k := clampf(swing_t, 0.0, 1.0)
		k = 1.0 - (1.0 - k) * (1.0 - k)
		var a := lerpf(swing_from, swing_to, k)
		rot = a + PI * 0.5
		pos = chest + Vector2.from_angle(a) * 4.0
		snap = true
		if swing_t >= 1.4:
			swing_t = -1.0
	elif pose_t > 0.0:
		pose_t -= dt
		if pose == "point":
			rot = aim.angle() + PI * 0.5
			pos = chest + aim * 5.0
		else:
			pos += Vector2(0, -6)
	elif dash_t > 0.0:
		rot = (-dash_dir).angle() + PI * 0.5
		pos = chest - dash_dir * 3.0
	elif moving:
		var step := anim_t * 9.0 * PI * 0.5
		rot = sin(step) * 0.09
		pos.y -= absf(sin(step))
	if snap:
		staff.rotation = rot
		staff.position = pos
	else:
		var k2 := 1.0 - exp(-dt * 20.0)
		staff.rotation = lerp_angle(staff.rotation, rot, k2)
		staff.position = staff.position.lerp(pos, k2)
	var flip := face < 0.0
	staff.flip_h = flip
	staff.offset = Vector2(-4.5, -11.5) if flip else Vector2(-2.5, -11.5)
	staff_e.flip_h = flip
	staff_e.offset = staff.offset
	staff_e.visible = not dead
	# The glow rides on the lantern itself, so light swings with the staff.
	pglow.position = staff.position + Vector2(-2.0 if flip else 2.0, -5.0).rotated(staff.rotation)

