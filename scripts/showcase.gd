extends Node
## A short scripted trailer, for recording. Run with:
##   godot --path . --write-movie trailer.avi --fixed-fps 60 -- --showcase
## Not used in normal play.

const Story = preload("res://scripts/story.gd")

var main
var hud
var g


func _ready() -> void:
	run()


func w(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func spawn(kind: String, off: Vector2, awake: bool = true, elite: bool = false):
	var e = g.spawn_enemy(kind, g.ppos + off, 0, elite)
	e.awake = awake
	return e


func ring(kind: String, n: int, radius: float, awake: bool = true) -> void:
	for k in n:
		spawn(kind, Vector2.from_angle(TAU * k / n + 0.3) * radius, awake)


func alive() -> int:
	var n := 0
	for e in g.enemies:
		if not e.dead:
			n += 1
	return n


func refill() -> void:
	g.hp = g.max_hp
	g.oil = g.max_oil
	g.dash_stock = g.stats["dash_n"]
	for k in g.pcd:
		g.pcd[k] = 0.0


func allow(list: Array) -> void:
	g.bot_manual = false
	for k in g.bot_allow:
		g.bot_allow[k] = list.has(k)


func manual() -> void:
	g.bot_manual = true
	g.bot_mv = Vector2.ZERO
	g.bot_atk = false
	g.bot_bolt = false


## Start a shot at one zoom and drift to another, so no shot sits still.
func drift(from: float, to: float, secs: float) -> void:
	g.cam.zoom = Vector2(from, from)
	create_tween().tween_property(g.cam, "zoom", Vector2(to, to), secs).set_trans(Tween.TRANS_SINE)


## Hard cut to a fresh hall in another depth's colours, on a white flash.
func cut(theme: String) -> void:
	hud.flash()
	g.gallery_theme = theme
	g.load_floor(0)
	Sfx.play_music("boss")
	reset()


## Same hall, cleared silently, for quick shots inside one scene.
func reset() -> void:
	for e in g.enemies:
		e.dead = true
		e.visible = false
	for s in g.shots:
		s["life"] = 0.0
	for wd in g.wards:
		wd["t"] = minf(wd["t"], 0.05)
	g.tidy()
	g.teleport(g.tile_center(Vector2i(22, 14)))
	g.pvel = Vector2.ZERO
	g.pknock = Vector2.ZERO
	g.aim = Vector2.RIGHT
	manual()
	refill()


func fight(secs: float) -> void:
	var t := 0.0
	while t < secs:
		await w(0.2)
		t += 0.2
		g.hp = g.max_hp
		g.oil = g.max_oil


func run() -> void:
	hud = main.hud
	main.slot = 9
	Sfx.play_music("boss")

	# --- Cold open on the key art -----------------------------------------------
	hud.show_art("res://trailer/key1.png", "LANTERNFALL", "The lantern is out.   Go down.")
	await w(4.0)
	main.new_game(0)
	g = main.game
	hud.showcase = true
	g.bot = true
	g.god = true
	g.cam_script = true
	g.xp_next = 9999999
	g.ambient_node.color = Color(0.3, 0.3, 0.42)
	hud._close_modal()

	# --- Descend ------------------------------------------------------------------
	cut("cellar")
	drift(6.5, 4.4, 2.6)
	hud.punch("DESCEND")
	g.bot_mv = Vector2.RIGHT
	await w(2.6)

	# --- Fight --------------------------------------------------------------------
	cut("choir")
	drift(4.0, 3.3, 3.8)
	for off in [Vector2(64, -22), Vector2(74, 22), Vector2(-62, -12), Vector2(-72, 26), Vector2(6, -72), Vector2(-10, 70)]:
		spawn("husk", off)
	hud.punch("FIGHT")
	allow(["atk", "move", "dash"])
	await fight(3.8)

	# --- Burn ---------------------------------------------------------------------
	cut("roots")
	drift(3.7, 3.0, 2.8)
	g.grant_power("nova")
	allow([])
	ring("husk", 12, 80.0)
	await w(1.15)
	hud.punch("BURN")
	g.cast_nova()
	g.slow_t = 0.7
	await w(1.7)

	# --- Storm --------------------------------------------------------------------
	cut("archive")
	drift(3.9, 3.3, 2.6)
	g.grant_power("spark")
	for k in 9:
		spawn("moth", Vector2(70 + (k % 3) * 30, -64 + k * 16), false)
	await w(0.45)
	hud.punch("STORM")
	for k in 3:
		g.aim = Vector2.RIGHT
		g.cast_spark()
		await w(0.6)
		refill()

	# --- Hold ---------------------------------------------------------------------
	cut("iron")
	drift(3.5, 3.0, 3.4)
	g.grant_power("ward")
	allow([])
	g.cast_ward()
	ring("husk", 7, 104.0)
	ring("slime", 4, 132.0)
	hud.punch("HOLD THE LIGHT")
	await fight(3.4)

	# --- Kindlings: four quick ones -----------------------------------------------
	cut("ash")
	drift(3.6, 3.2, 1.8)
	hud.punch("23 KINDLINGS")
	g.apply_boon("wave")
	for k in 6:
		spawn("husk", Vector2(26 + k * 24, (k % 2) * 8 - 4), false)
	await w(0.35)
	for k in 3:
		g.aim = Vector2.RIGHT
		g.do_slash()
		await w(0.34)
	await w(0.45)

	reset()
	drift(3.6, 3.1, 2.0)
	g.apply_boon("orbit")
	g.apply_boon("orbit")
	allow([])
	ring("moth", 12, 96.0)
	await fight(2.0)

	reset()
	drift(3.4, 3.0, 1.6)
	for id in ["blink", "sear", "trail"]:
		g.apply_boon(id)
	for k in 8:
		spawn("husk", Vector2(34 + k * 20, 0), false)
	await w(0.3)
	g.bot_mv = Vector2.RIGHT
	await w(0.05)
	g.try_dash()
	await w(0.22)
	g.try_dash()
	await w(0.25)
	g.bot_mv = Vector2.ZERO
	await w(0.8)

	reset()
	drift(3.6, 3.2, 1.6)
	g.apply_boon("shatter")
	g.apply_boon("shatter")
	for k in 16:
		spawn("moth", Vector2(96, 0) + Vector2.from_angle(k * 2.4) * (8.0 + k * 2.2), false)
	await w(0.35)
	g.aim = Vector2.RIGHT
	g.do_bolt()
	await w(1.25)

	# --- Six kinds of dark: a beat on each -----------------------------------------
	# Put the ember motes and cinderburst away, or nothing lives long enough to be seen.
	g.stats["orbit"] = 0
	g.stats["shatter"] = 0.0
	g._sync_motes()
	var themes := ["choir", "archive", "roots", "archive", "iron", "forge"]
	var packs := {"husk": 4, "moth": 6, "cantor": 2, "slime": 4, "brute": 2, "wisp": 4}
	for i in Story.BESTIARY.size():
		var b: Dictionary = Story.BESTIARY[i]
		cut(themes[i])
		drift(5.0, 4.3, 1.2)
		if i == 0:
			hud.punch("SIX KINDS OF DARK")
		hud.caption((b["name"] as String).to_upper())
		var n: int = packs[b["kind"]]
		for k in n:
			var side := 1.0 if k % 2 == 0 else -1.0
			var rank := int(k / 2.0)
			spawn(b["kind"], Vector2(side * (44.0 + rank * 14.0), (rank - (n / 2.0 - 1.0) * 0.5) * 24.0 - 6.0))
		await w(1.2)
	hud.caption("")

	# --- One Warden ---------------------------------------------------------------
	cut("forge")
	drift(3.8, 2.9, 6.5)
	var boss = spawn("warden", Vector2(0, -62), false)
	boss.hp = 9000.0
	boss.max_hp = 9000.0
	g.boss_started = true
	g.god = false
	g._boss_begin()
	hud.punch("ONE WARDEN")
	allow(["atk", "move", "bolt", "nova", "spark", "ward", "dash"])
	await fight(2.4)
	for frac in [0.64, 0.31]:
		if is_instance_valid(boss) and not boss.dead:
			boss.hp = boss.max_hp * frac
		await fight(2.4)
	g.god = true
	if is_instance_valid(boss) and not boss.dead:
		boss.hurt(999999.0, Vector2.ZERO)
	g.boss_end_t = -1.0
	manual()
	await w(2.0)

	# --- End card -----------------------------------------------------------------
	hud.flash()
	hud.show_art("res://trailer/key2.png", "LANTERNFALL", "Seven depths.     Six kinds of dark.     Two endings.")
	await w(4.6)
	main.delete_save(9)
	get_tree().quit()
