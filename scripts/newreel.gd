extends "res://scripts/showreel.gd"
## A recorded tour of what the roguelike-depth work added, in the flat view:
## the light dial, the lamp's lessons and the bestiary, blows that land, kindling
## and relic choices, the set-aside rooms and the second stair, and the Descent.
##   godot --path . --write-movie reel.avi --fixed-fps 30 -- --autotest --newreel

const DungeonS = preload("res://scripts/dungeon.gd")

var arena := Vector2.ZERO


func _process(dt: float) -> void:
	super(dt)
	# Lessons turn up by themselves in play; here they come only when called.
	if g != null and is_instance_valid(g):
		g.teach_done = true


func _foe(kind: String, at: Vector2, hp: float = 40.0, awake: bool = true):
	var e = g.spawn_enemy(kind, at, -1)
	e.hp = hp
	e.max_hp = hp
	e.awake = awake
	return e


func _face(e) -> void:
	if is_instance_valid(e):
		g.aim = (e.center() - g.pcenter()).normalized()


func _find_arena() -> Vector2:
	var start: Vector2i = g.dungeon["start"]
	for rad in [4, 3, 2]:
		var best := Vector2i(-1, -1)
		var bd := 1 << 30
		for y in range(1, g.H - 1):
			for x in range(1, g.W - 1):
				if not g.surf._all_open(x, y, rad):
					continue
				var dd := absi(x - start.x) + absi(y - start.y)
				if dd < bd:
					bd = dd
					best = Vector2i(x, y)
		if best.x >= 0:
			return g.tile_center(best)
	return g.ppos


func _stage() -> Vector2:
	for e in g.enemies:
		if (e.position - arena).length() < 400.0 and e.kind != "warden":
			e.dead = true
			e.visible = false
	g.surf.clear()
	g.bot_manual = true
	g.bot_mv = Vector2.ZERO
	g.teleport(arena - Vector2(40, 0))
	g.hud.say_q.clear()
	return Vector2.RIGHT


func _quiet(keep = null) -> void:
	for e in g.enemies:
		if e != keep and not e.dead:
			e.dead = true
			e.visible = false


func _fresh_game(depth: int) -> void:
	main.new_game(depth)
	await w(0.5)
	_setup_game()
	g.teach_done = true
	g.xp_next = 1 << 30
	g.hud.say_q.clear()


func _prop_of(type: String, extra: String = "") -> Variant:
	for p in g.props:
		if p["type"] == type and not p["done"] and (extra == "" or p.get(extra, false)):
			return p
	return null


## Beside a prop, as near as the floor allows, and use it.
func _go_use(p, hold: float = 1.0) -> void:
	var at_p: Vector2 = p["pos"] + Vector2(0, 12)
	if g.solid_at(at_p):
		at_p = p["pos"]
	g.teleport(at_p)
	await w(hold)
	g.near_prop = p
	g.interact()


func _seed_with(d: int, need: Array) -> int:
	for s in range(1, 3000):
		var r := RandomNumberGenerator.new()
		r.seed = s
		var fl: Dictionary = DungeonS.generate(d, r, "")
		var ok := true
		for k in need:
			ok = ok and (fl["kinds"] as Array).count(k) > 0
		if ok:
			return s
	return 1


func _choice_has(label: String) -> int:
	var row: Array = main.hud.modal_root.find_children("*", "Label", true, false)
	for l in row:
		if (l as Label).text.begins_with(label):
			return 1
	return 0


func run() -> void:
	main.slot = 9
	main.delete_save(9)
	var pr: Dictionary = main.profile
	pr["embers"] = 160
	pr["town"] = []
	pr["feats"] = []
	pr["best"] = {}
	pr["taught"] = []
	pr["seen"] = []
	pr["nemesis"] = {}
	main.use_3d = false
	main.mode = "pilgrim"
	await w(1.0)
	main.hud.show_title()
	await w(0.5)
	cap("LANTERNFALL", "What is new: the light dial, lessons, build choices, rooms and the Descent", 4.0)
	await w(3.0)
	main.hud._close_modal()
	await _fresh_game(1)
	arena = _find_arena()
	# Every lesson is known, so none butts in; the teaching scene sets its own.
	var all_lessons: Array = []
	for l in Story.LESSONS:
		all_lessons.append(l["id"])
	pr["taught"] = all_lessons.duplicate()
	await w(1.0)

	# --- 1. The light dial ---
	print("REELT 1 light dial ", Time.get_ticks_msec())
	var d := _stage()
	g.stats["oil_regen"] = 0.0
	g.oil = g.max_oil
	g.gloam_t = -999.0
	cap("The light is a dial", "The lower the lamp burns, the more the dark pays: Dim +25% loot, Shadowy +60%, Dark +100%.", 8.0)
	g.cine(3.6, 30.0, g.ppos + Vector2(10, -4))
	await w(1.5)
	var sleeper = _foe("husk", g.ppos + d * 70.0, 40.0, false)
	var t := 0.0
	var woke := false
	while g.oil > g.max_oil * 0.22:
		g.oil -= g.max_oil * 0.3 * get_process_delta_time()
		await get_tree().process_frame
		t += get_process_delta_time()
		# In the Shadowy band a foe that stirs rushes her: the violet "!!".
		if not woke and g.light_tier() >= 2:
			woke = true
			g.hud.say_q.clear()
			cap("Caught in the dark", "A foe that wakes in poor light is on her at once. Violet !! marks the ambush.", 5.0)
			sleeper.wake()
			await w(2.6)
			_face(sleeper)
			g.atk_cd = 0.0
			g.do_slash()
	await w(0.6)
	if is_instance_valid(sleeper) and not sleeper.dead:
		_face(sleeper)
		g.atk_cd = 0.0
		g.do_slash()
		await w(1.5)
	cap("Snuff it, light it again", "C hoods the lamp: darkest loot, but the wick drinks oil to catch again.", 6.5)
	g.oil = g.max_oil * 0.8
	await w(1.2)
	g.snuff()
	await w(3.8)
	var oil0: float = g.oil
	g.relight()
	await w(0.3)
	g.hud.float_text(g.ppos + Vector2(0, -22), "-%d oil" % int(oil0 - g.oil), Color(1.0, 0.7, 0.25))
	await w(3.0)
	g.cine_t = 0.0
	g.oil = g.max_oil
	_quiet()

	# --- 2. Teaching and the bestiary ---
	print("REELT 2 teaching ", Time.get_ticks_msec())
	d = _stage()
	pr["taught"] = ["snuff", "flask", "nova"]
	pr["seen"] = ["husk", "moth", "gloam"]
	g.hud.lesson_t = -9.0
	cap("The lamp teaches", "Each lesson appears once, when its moment first comes. Never a menu.", 5.5)
	await w(1.0)
	g.teach("parry")
	await w(3.8)
	g.hud.lesson_t = -9.0
	g.teach("echo")
	await w(2.2)
	main.hud.show_pause()
	cap("The bestiary", "Pause, then Bestiary: foes you have met, and the Lamp Lore page of every lesson.", 8.5)
	await w(1.2)
	main.hud.show_codex(main.hud.show_pause)
	await w(2.2)
	main.hud._codex_turn(6)
	await w(2.2)
	main.hud._codex_turn(Story.FOES.size())
	await w(2.8)
	main.hud.close_codex()
	main.hud._close_modal()
	pr["taught"] = all_lessons.duplicate()
	await w(0.4)

	# --- 3. Combat feel ---
	print("REELT 3 combat ", Time.get_ticks_msec())
	d = _stage()
	g.oil = g.max_oil
	cap("Blows that land", "Heavy hits shake the screen, but never past a cap. Wren struck: the edges flush red.", 7.0)
	g.cine(3.5, 30.0, g.ppos + d * 22.0)
	var br = _foe("brute", g.ppos + d * 46.0, 70.0)
	br.cd = 0.4
	br.stun = 0.0
	await w(1.0)
	for k in 3:
		_face(br)
		g.atk_cd = 0.0
		g.combo_t = 0.0
		g.do_slash()
		await w(0.45)
	var tw := 0.0
	g.invuln = 0.0
	while tw < 4.5:
		_face(br)
		if int(tw * 3.0) % 2 == 0:
			g.atk_cd = 0.0
			g.do_slash()
		await w(0.4)
		tw += 0.4
	if is_instance_valid(br) and not br.dead:
		br.hurt(999.0, d * 60.0)
	await w(1.8)
	g.cine_t = 0.0
	_quiet()

	# --- 4. Build choices ---
	print("REELT 4 builds ", Time.get_ticks_msec())
	d = _stage()
	auto_pick = false
	g.apply_boon("burn")
	g.apply_boon("trail")
	cap("Kindling with a shape", "Cards carry an aspect tag. A red BARGAIN has a real cost. Pairs hint at a duo.", 8.0)
	var found := false
	for k in 80:
		g._offer_boons("The warmth below reaches up to you", "Level %d  -  choose a kindling" % g.level)
		var bargain := false
		for id in g.offer:
			for b in Story.BOONS:
				if b["id"] == id and b.get("bargain", false):
					bargain = true
		if bargain and g.offer.has("wildfire"):
			found = true
			break
		main.hud._close_modal()
	print("REEL offer with bargain and duo: ", found, " ", g.offer)
	await w(5.0)
	var pick := 0
	for i in g.offer.size():
		var is_b := false
		for b in Story.BOONS:
			if b["id"] == g.offer[i] and b.get("bargain", false):
				is_b = true
		if g.offer[i] == "wildfire":
			pick = i
	main.hud._choose(pick)
	await w(1.5)
	cap("Relic stands", "Maren left three tools on the stand. Take one; the rest wait deeper down.", 6.5)
	g._offer_relics()
	await w(4.5)
	main.hud._choose(0)
	await w(2.0)
	main.hud._close_modal()
	auto_pick = true
	await w(0.5)

	# --- 5. Rooms ---
	print("REELT 5 rooms ", Time.get_ticks_msec())
	var s := _seed_with(4, ["shrine", "cache", "vault", "dark", "altar"])
	g.load_floor(4, {"seed": s})
	g.teach_done = true
	g.hud.card_t = 0.0
	g.hud.say_q.clear()
	g.hp = g.max_hp
	await w(0.5)
	var rm = g.rooms
	var keeper = rm.keeper
	_quiet(keeper)
	g.oil = g.max_oil
	g.stats["oil_regen"] = 3.0
	g.bot_manual = true

	# The shrine.
	var p = _prop_of("shrine")
	g.teleport(p["pos"] + Vector2(0, 34))
	cap("The keepers' shrine", "A cold flame that bargains: a heart for a deeper flask, embers for mending, or a quiet word.", 6.5)
	g.cine(3.5, 30.0, p["pos"] + Vector2(0, 8))
	await w(2.5)
	await _go_use(p, 0.8)
	await w(3.0)
	main.hud._choose(0)
	await w(2.2)

	# The oil cache, which is bait.
	p = _prop_of("cache")
	g.teleport(p["pos"] + Vector2(0, 34))
	cap("The oil cache is bait", "Take it and the doorways seal; the room fills. Clear it and the doors open.", 7.5)
	g.cine(3.2, 30.0, p["pos"] + Vector2(0, 8))
	await w(2.0)
	await _go_use(p, 0.6)
	await w(2.5)
	g.invuln = 0.0
	await brawl(6.0)
	for e in rm.wave:
		if is_instance_valid(e) and not e.dead:
			e.hurt(99999.0, Vector2.ZERO)
	await w(1.8)

	# The vault gate and its keeper.
	var gate = null
	for q in g.props:
		if q["type"] == "vgate":
			gate = q
	if gate != null:
		g.teleport(gate["pos"] + Vector2(0, 30))
		cap("The vault", "Walled up. Its keeper walks the floor, carrying the key in its light.", 6.0)
		g.cine(3.3, 30.0, gate["pos"] + Vector2(0, 8))
		await w(2.0)
		await _go_use(gate, 0.5)
		await w(2.5)
		if is_instance_valid(keeper) and not keeper.dead:
			keeper.visible = true
			g.hud.say_q.clear()
			cap("Its keeper falls", "The way into the vault opens.", 4.0)
			keeper.hurt(99999.0, Vector2.ZERO)
		await w(3.5)

	# The dark room.
	var dark := -1
	for i in (g.dungeon["kinds"] as Array).size():
		if g.dungeon["kinds"][i] == "dark":
			dark = i
	var rect: Rect2i = g.dungeon["rooms"][dark]
	p = null
	for q in g.props:
		if q["type"] == "hoard" and not q["vault"] and rect.has_point(Vector2i(q["pos"] / 16.0)):
			p = q
	if p != null:
		g.teleport(p["pos"] + Vector2(0, 28))
		cap("The dark room", "No fire of its own. Its hoard is richer than any chest.", 6.5)
		g.cine(3.3, 30.0, p["pos"] + Vector2(0, 6))
		await w(2.6)
		await _go_use(p, 0.5)
		await w(3.0)
	g.hud.say_q.clear()

	# The cursed altar.
	p = _prop_of("altar")
	if p != null:
		g.teleport(p["pos"] + Vector2(0, 32))
		cap("The cursed altar", "A kindling now. Then the lamp stops refilling itself for as long as she stays.", 7.0)
		g.cine(3.4, 30.0, p["pos"] + Vector2(0, 8))
		await w(2.0)
		await _go_use(p, 0.6)
		await w(3.0)
		main.hud._choose(0)
		await w(3.0)
		main.hud._choose(0)
		await w(1.5)
		main.hud._close_modal()

	# The second stair.
	g.floor_route = ""
	g.load_floor(2)
	g.teach_done = true
	g.hud.card_t = 0.0
	g.hp = g.max_hp
	g.hud.say_q.clear()
	await w(0.5)
	var rs = null
	for q in g.props:
		if q["type"] == "stairs" and q.has("route"):
			rs = q
	if rs != null:
		cap("A second way down", "It promises what the next floor will be. Its guards hold it shut, then the sign reads true.", 8.0)
		g.teleport(rs["pos"] + Vector2(-18, 26))
		g.cine(3.4, 30.0, rs["pos"] + Vector2(0, 6))
		_quiet()
		await w(1.0)
		for e in g.enemies:
			if e.room == g.dungeon["route_room"] and not e.dead:
				e.hurt(99999.0, Vector2.ZERO)
		await w(0.6)
		g.near_prop = rs
		await w(4.5)
	g.cine_t = 0.0
	g.cam_script = false

	# --- 6. The Descent ---
	print("REELT 6 descent ", Time.get_ticks_msec())
	main.hud._close_modal()
	cap("Two ways down", "Chosen once per descent: a Pilgrimage wakes you at the last lamp. A Descent does not forgive.", 7.0)
	main.pick_mode()
	await w(5.5)
	main.hud._close_modal()
	main.mode = "descent"
	main.new_game(3, {}, true)
	await w(0.5)
	_setup_game()
	g.teach_done = true
	guard = false
	g.hud.card_t = 0.0
	g.hud.say_q.clear()
	cap("The Descent", "The badge stays in the corner. One life; the slot is deleted when she falls.", 5.5)
	await w(5.5)
	g.bot = true
	g.match_used = true
	g.invuln = 0.0
	g.hp = 1
	g.hurt_player(2, g.ppos + Vector2(10, 0), 100.0, "brute")
	main.bank(38)
	await w(4.2)
	cap("No second chance", "Its embers are banked all the same.", 4.0)
	await w(2.5)

	main.mode = "pilgrim"
	main.delete_save(9)
	main.hud._close_modal()
	main.hud.show_title()
	cap("LANTERNFALL", "Light it low for the dark's gold. Choose how you go down.", 4.0)
	await w(4.5)
	main.delete_save(9)
	get_tree().quit()
