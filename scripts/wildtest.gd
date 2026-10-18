extends Node
## Checks for the oil and fire on the floor, the snuffed lamp, Wren's echo and
## the nemesis. Run with:  godot --path . -- --autotest --wild [--shotdir=<dir>]
## Exits 1 if anything fails.

const Nemesis = preload("res://scripts/nemesis.gd")
const EchoS = preload("res://scripts/echo.gd")

var main
var at
var fails := 0


func check(ok: bool, what: String) -> void:
	print("WILD %s %s" % [what, "ok" if ok else "FAIL"])
	if not ok:
		fails += 1


func w(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Waits until `cond` holds, or `sec` seconds pass. A fixed wait is not enough
## on a slow CI machine: game time per frame is capped, so few frames there
## means little game time.
func until(cond: Callable, sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await get_tree().process_frame


## A direction from Wren with open floor for at least `need` pixels.
func open_dir(g, need: float = 70.0) -> Vector2:
	for cand in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if g.los(g.pcenter(), g.pcenter() + cand * need) and not g.solid_at(g.ppos + cand * need):
			return cand
	return Vector2.RIGHT


func clear_foes(g) -> void:
	for e in g.enemies:
		e.dead = true
		e.visible = false
	await frames(2)


func foe(g, kind: String, pos: Vector2, hp: float = 999.0):
	var e = g.spawn_enemy(kind, pos, -1)
	e.hp = hp
	e.max_hp = hp
	return e


func e_name(e) -> String:
	return str(e.nem["name"])


func run() -> void:
	main.slot = 9
	main.profile["nemesis"] = {}
	main.nem_due = false
	await w(0.5)
	main.hud._close_modal()
	main.new_game(1)
	await w(2.5)
	var g = main.game
	# The floor is made with one sealed hollow wall. Look now: a stray blow or
	# bolt in the tests below can find it by chance.
	var sealed: bool = g.secrets.size() == 1 		and g.tiles[g.secrets[0]["w"].y * g.W + g.secrets[0]["w"].x] == 0 		and g.tiles[g.secrets[0]["c"].y * g.W + g.secrets[0]["c"].x] == 1
	g.bot = true
	g.bot_manual = true
	g.hud.hint_t = 0.0
	g.hud.card_t = 0.0
	g.cam_script = true
	g.cam.zoom = Vector2(3.4, 3.4)
	await clear_foes(g)
	# Somewhere roomy, near the stair, clear of anything grown on this floor.
	for p in g.props:
		if p["type"] == "stairs":
			g.teleport(p["pos"] + Vector2(-30, 20))
	g.surf.clear()
	await w(0.4)
	var d: Vector2 = open_dir(g)

	# --- Oil and fire ---
	g.oil = g.max_oil
	var oil0: float = g.oil
	g.aim = d
	g.throw_flask()
	await w(1.0)
	var pools := 0
	for s in g.surf.list:
		if s["k"] == "oil":
			pools += 1
	check(pools == 1 and g.oil < oil0 - 15.0, "flask leaves a pool of oil (%d pools, oil %.0f -> %.0f)" % [pools, oil0, g.oil])
	await at.shot("w_oil")
	var pool: Dictionary = g.surf.list[0] if pools > 0 else g.surf.add("oil", g.ppos + d * 50.0, 20.0)
	# A husk standing in it, then a bolt across it.
	var hk = foe(g, "husk", pool["p"])
	hk.awake = true
	hk.stun = 99.0
	g.add_shot(g.pcenter() + d * 8.0, d * 235.0, true, 1.0, Color(1.0, 0.62, 0.2))
	await w(0.6)
	check(pool["k"] == "fire", "an ember bolt sets the oil alight (%s)" % pool["k"])
	await at.shot("w_fire")
	await w(0.8)
	check(hk.hp < 999.0 and hk.burn_t > 0.0, "fire burns the foe standing in it (hp %.0f, burn %.1f)" % [hk.hp, hk.burn_t])
	# Fire spreads to oil that touches it.
	var o2: Dictionary = g.surf.add("oil", pool["p"] + Vector2(pool["r"] + 8.0, 0).rotated(d.angle() + PI * 0.5), 14.0)
	await w(0.6)
	check(o2["k"] == "fire", "fire spreads into oil beside it (%s)" % o2["k"])
	# Water puts out a burning foe.
	hk.position = g.ppos - d * 40.0
	var wat: Dictionary = g.surf.add("water", hk.position, 16.0)
	hk.burn_t = 3.0
	await w(0.4)
	check(hk.burn_t <= 0.0, "water puts out a burning foe (burn %.1f)" % hk.burn_t)
	g.surf.list.erase(wat)
	hk.dead = true
	hk.visible = false
	# Wren burns too.
	g.invuln = 0.0
	var hp0: int = g.hp
	g.surf.add("oil", g.ppos, 14.0)
	g.surf.ignite_at(g.ppos, 2.0)
	await w(0.5)
	check(g.hp < hp0, "fire hurts Wren as well (hp %d -> %d)" % [hp0, g.hp])
	check(g.last_cause == "fire", "the death screen would know it was fire (%s)" % g.last_cause)
	g.hp = g.max_hp
	await w(1.0)
	# Webs slow, oil trips a charge.
	g.surf.clear()
	await frames(2)
	var web: Dictionary = g.surf.add("web", g.ppos, 12.0)
	await frames(2)
	check(g.surf.player_drag() < 0.7, "a web slows Wren (%.2f)" % g.surf.player_drag())
	g.surf.list.erase(web)
	var br = foe(g, "brute", g.ppos + d * 60.0)
	br.awake = true
	g.surf.add("oil", br.position, 16.0)
	br.state = "charge"
	br.st = 0.7
	br.dir = -d
	await w(0.35)
	check(br.stun > 0.0, "a charging Bellringer slips in oil (stun %.2f)" % br.stun)
	await at.shot("w_slip")
	br.dead = true
	br.visible = false
	# A web catches from fire and is gone.
	g.surf.clear()
	var web2: Dictionary = g.surf.add("web", g.ppos + d * 40.0, 12.0)
	g.surf.ignite_at(web2["p"], 2.0)
	await w(2.0)
	check(not g.surf.list.has(web2), "a burning web is gone in moments")
	g.surf.clear()
	await w(0.3)

	# --- The snuffed lamp ---
	await clear_foes(g)
	g.oil = g.max_oil
	g.stats["oil_regen"] = 2.0
	var hu = foe(g, "husk", g.ppos + d * 90.0)
	hu.awake = true
	hu.cd = 0.0
	await w(0.5)
	var lit_r: float = g.plight.texture_scale
	g.snuff()
	# Step aside so she is not where it last saw her.
	g.teleport(g.ppos + d.orthogonal() * 24.0 if not g.solid_at(g.ppos + d.orthogonal() * 24.0) else g.ppos - d.orthogonal() * 24.0)
	await w(0.6)
	check(g.plight.texture_scale < lit_r * 0.5, "snuffing shrinks the light (%.2f -> %.2f)" % [lit_r, g.plight.texture_scale])
	check(hu.lost or (hu.position - g.ppos).length() < 46.0, "a foe that cannot see her loses her (lost %s)" % hu.lost)
	await at.shot("w_snuffed")
	# Out of the dark, on a foe that has lost her: never sees it coming.
	hu.position = g.ppos + d * 20.0
	hu.lost = true
	hu.state = "chase"
	g.aim = d
	g.atk_cd = 0.0
	g.combo_t = 0.0
	var amb0 := int(main.profile["tally"].get("ambushes", 0))
	g.do_slash()
	check(int(main.profile["tally"].get("ambushes", 0)) == amb0 + 1, "a strike from the dark is an ambush")
	await frames(3)
	await at.shot("w_unseen")
	# Relighting after a moment in the dark flares and dazzles.
	hu.stun = 0.0
	hu.position = g.ppos + d * 30.0
	g.snuff_t = 1.0
	g.flare_cd = 0.0
	g.relight()
	check(hu.stun > 1.0 and not g.snuffed, "relighting flares and dazzles (stun %.2f)" % hu.stun)
	await frames(3)
	await at.shot("w_flare")
	hu.dead = true
	hu.visible = false
	# Hide too long and the dark sends its shades, full flask or not.
	g.oil = g.max_oil
	g.snuff()
	g.snuff_t = 3.5
	g.gloam_t = 0.0
	var n := 0
	for k in 30:
		await w(0.2)
		n = 0
		for e in g.enemies:
			if e.kind == "gloam" and not e.dead:
				n += 1
		if n > 0:
			break
	check(n > 0, "hiding too long brings gloams, flask full (%d)" % n)
	g.relight()
	g.flare_cd = 0.0
	await clear_foes(g)

	# --- The echo ---
	g.echo_cd = 0.0
	g.echo_track.clear()
	g.echo_blows.clear()
	var tgt = foe(g, "husk", g.ppos + d * 22.0)
	tgt.awake = true
	tgt.stun = 99.0
	g.aim = d
	for k in 3:
		g.atk_cd = 0.0
		g.do_slash()
		await w(0.3)
	var hp_before: float = tgt.hp
	g.last_mv = -d
	g.dash_stock = 1
	g.try_dash()
	var echoes := 0
	for c in g.ents.get_children():
		if c is EchoS:
			echoes += 1
	check(echoes == 1, "dashing after a fight leaves an echo (%d)" % echoes)
	tgt.position = g.ppos + d * 22.0 + d * 0.0
	await w(0.5)
	await at.shot("w_echo")
	await w(1.8)
	check(tgt.hp < hp_before, "the echo's blows land (hp %.0f -> %.0f)" % [hp_before, tgt.hp])
	g.dash_stock = 1
	g.try_dash()
	echoes = 0
	for c in g.ents.get_children():
		if c is EchoS and not c.is_queued_for_deletion():
			echoes += 1
	check(echoes == 0, "no echo without a fight to echo, or too soon (%d)" % echoes)
	tgt.dead = true
	tgt.visible = false

	# --- Flit, the lamp moth ---
	await clear_foes(g)
	var mp = null
	for p in g.props:
		if p["type"] == "moth" and not p["done"]:
			mp = p
	check(mp != null and g.moth == null, "a wild lamp moth flutters on the first floor")
	if mp != null:
		g.teleport(mp["pos"] + Vector2(0, 14))
		await w(0.4)
		g.oil = g.max_oil
		g.near_prop = mp
		g.interact()
		check(g.moth != null and g.oil < g.max_oil - 9.0, "a drop of oil and it stays (oil %.0f)" % g.oil)
		await w(1.0)
		await at.shot("w_flit")
		g.moth.feed(2)
		check(g.moth.lv == 2, "fed, it grows (level %d)" % g.moth.lv)
		var dd: Vector2 = open_dir(g, 50.0)
		var bitten = foe(g, "husk", g.ppos + dd * 30.0)
		bitten.awake = true
		bitten.stun = 99.0
		g.moth.nip_cd = 0.0
		await w(3.0)
		check(bitten.hp < 999.0, "grown, it bites what comes near (hp %.0f)" % bitten.hp)
		bitten.dead = true
		bitten.visible = false
		var mhp: int = g.moth.hp
		# Held still over open floor for the shot: it never stops circling otherwise.
		# Along `dd`, which is known to be clear: a shot made inside a wall is gone
		# at once, and right above Wren's feet can be wall on a random floor.
		g.moth.set_process(false)
		g.moth.body.position = Vector2(0, -12)
		var aim_at: Vector2 = g.pcenter() + dd * 20.0
		g.moth.position = aim_at - g.moth.body.position
		g.add_shot(aim_at - dd * 6.0, dd * 60.0, false, 1, Color(1.0, 0.3, 0.75))
		await until(func(): return g.moth == null or g.moth.hp < mhp, 3.0)
		check(g.moth == null or g.moth.hp < mhp, "a hex can hit it")
		if g.moth != null:
			g.moth.set_process(true)
		g.save_game(-1)
		var sv: Dictionary = main.read_save(9)
		check(g.moth != null and int(sv.get("moth", {}).get("lv", 0)) == 2, "it is kept in the save")
		if g.moth != null:
			g.moth.hp = 1
			g.moth.hurt()
		await w(0.3)
		check(g.moth == null, "and it can be lost")

	# --- A hollow wall ---
	check(g.secrets.size() == 1, "the floor has a hollow wall (%d)" % g.secrets.size())
	if g.secrets.size() == 1:
		var sc: Dictionary = g.secrets[0]
		var wt: Vector2i = sc["w"]
		var ct: Vector2i = sc["c"]
		check(sealed, "a sealed room behind a wall")
		if sc["open"]:
			# Broken by chance above; close it again so the blow below has a wall to find.
			sc["open"] = false
			g.tiles[wt.y * g.W + wt.x] = 0
			g.map_rev += 1
			g._paint_map()
			g._update_fov()
			g._update_flow()
		var hoard := false
		for p in g.props:
			if p["type"] == "chest" and p.get("secret", false):
				hoard = true
		check(hoard, "with a chest in it")
		var fp: Vector2 = g.tile_center(sc["f"])
		var back: Vector2 = fp + (fp - g.tile_center(wt)) * 2.0
		g.teleport(back if not g.solid_at(back) else fp)
		g.cam_script = true
		g.cam.zoom = Vector2(3.4, 3.4)
		await w(0.8)
		await at.shot("w_crack")
		var rev: int = g.map_rev
		g.teleport(fp)
		await w(0.3)
		g.aim = (g.tile_center(wt) - g.pcenter()).normalized()
		g.atk_cd = 0.0
		g.combo_t = 0.0
		g.do_slash()
		await w(0.3)
		check(sc["open"] and g.tiles[wt.y * g.W + wt.x] == 1 and g.map_rev > rev, "a blow breaks it in")
		check(g.flow[ct.y * g.W + ct.x] < 9999, "and the room behind can be walked into")
		await w(1.2)
		await at.shot("w_hollow")
		g.save_game(-1)
		var sv2: Dictionary = main.read_save(9)
		check((sv2.get("secrets_open", []) as Array).size() == 1, "a broken wall stays broken in the save")

	# --- The nemesis ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	main.profile["nemesis"] = {}
	var news: String = Nemesis.on_death(main, "brute", false, rng)
	var nm: Dictionary = main.profile["nemesis"]
	check(not nm.is_empty() and nm["kind"] == "brute" and main.nem_due and news != "", "a death names the foe that did it: %s" % news)
	var none: String = Nemesis.on_death(main, "cantor", false, rng)
	check(main.profile["nemesis"]["kind"] == "brute" and none == "", "only one nemesis at a time")
	main.nem_due = true
	g.load_floor(2)
	await w(2.5)
	g.hud.card_t = 0.0
	g.hud.say_q.clear()
	var nem = null
	for e in g.enemies:
		if e.nemesis:
			nem = e
	check(nem != null, "the nemesis waits on the next floor")
	if nem != null:
		check(nem.max_hp > 70.0 * 2.0, "it is tougher than its kind (hp %.0f)" % nem.max_hp)
		g.teleport(nem.position + Vector2(-40, 10) if not g.solid_at(nem.position + Vector2(-40, 10)) else nem.position + Vector2(40, 10))
		await w(0.2)
		# Woken the usual way: something else in its room sees her first.
		var mate = foe(g, "husk", nem.position + Vector2(8, 0))
		mate.room = nem.room
		mate.wake()
		mate.dead = true
		mate.visible = false
		nem.wake()
		await w(0.6)
		check(g.hud.sub_lbl.text.contains(e_name(nem)), "it names itself and taunts her (%s)" % g.hud.sub_lbl.text)
		await at.shot("w_nemesis")
		# Hit by it at one heart left: the death screen should read it as the nemesis.
		g.invuln = 0.0
		g.hurt_player(1, nem.position, 100.0, nem)
		check(g.last_by_nem, "a blow from it is known as the nemesis's")
		g.hp = g.max_hp
		var em0 := int(main.profile["embers"])
		nem.hurt(99999.0, Vector2.ZERO)
		await w(0.5)
		check(int(main.profile["embers"]) >= em0 + 70 and main.profile["nemesis"].is_empty(), "putting it out pays well and settles it (+%d)" % (int(main.profile["embers"]) - em0))
		await at.shot("w_nemesis_down")
	main.profile["nemesis"] = {"kind": "husk", "name": "Grisk", "rank": 1, "wins": 1}
	Nemesis.on_death(main, "husk", true, rng)
	check(int(main.profile["nemesis"]["rank"]) == 2, "putting her out again ranks it up (%d)" % int(main.profile["nemesis"]["rank"]))

	# The death screen, with the nemesis's line on it.
	main.nem_news = "Grisk laughs. It grows. Now: Twice-Fed."
	main.last_cause = "husk"
	main.hud.show_death()
	await w(0.5)
	await at.shot("w_death")
	main.hud._close_modal()
	main.hud.show_deeds()
	await w(0.5)
	await at.shot("w_deeds")
	main.hud._close_modal()
	main.profile["nemesis"] = {}

	print("WILD %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	main.delete_save(9)
	get_tree().quit(1 if fails > 0 else 0)
