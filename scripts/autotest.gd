extends Node
## Self-play smoke test. Run with:  godot --path . -- --autotest --shotdir=<dir>
## Plays through every floor with a simple bot, exercises each interaction, saves
## screenshots along the way, then quits. Not used in normal play.

const Story = preload("res://scripts/story.gd")

var main
var dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			dir = a.substr(10)
	print("AUDIO %d recorded sounds, %d music tracks" % [Sfx.file_sounds.size(), Sfx.tracks.size()])
	run()


func w(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func shot(id: String) -> void:
	# Without a screen (CI runs headless) frames are never drawn: just step one.
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		print("SHOT ", id)
		return
	await RenderingServer.frame_post_draw
	if dir != "":
		get_viewport().get_texture().get_image().save_png(dir.path_join(id + ".png"))
	print("SHOT ", id)


func goto_prop(g, type: String) -> bool:
	for p in g.props:
		if p["type"] == type and not p["done"]:
			# Stand still, or the fighting bot wanders off before the interaction.
			g.bot_manual = true
			g.bot_mv = Vector2.ZERO
			g.teleport(p["pos"] + Vector2(0, 10))
			await w(0.25)
			return true
	return false


func fight(g, rounds: int, tag: String) -> void:
	g.bot_manual = false
	for i in rounds:
		var target = null
		for e in g.enemies:
			if not e.dead:
				target = e
				break
		if target == null:
			return
		g.teleport(target.position + Vector2(0, 14))
		for k in 5:
			await w(0.5)
			g.hp = g.max_hp
			if i == 0 and k == 2 and tag != "":
				await shot(tag)


func quick() -> void:
	await w(0.5)
	main.hud._close_modal()
	main.new_game(1)
	await w(1.0)
	var g = main.game
	var mode := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = int(a.substr(7))
	print("MODE ", mode)
	if mode & 1:
		for p in g.props:
			if p["type"] == "urn":
				g._break_urn(p)
	if mode & 2:
		for e in g.enemies:
			e.hurt(99999.0, Vector2.ZERO)
	if mode & 4:
		g.bot = true
		g.oil = 9999.0
		g.max_oil = 9999.0
		g.teleport(g.enemies[0].position + Vector2(0, 30))
	if mode & 8:
		for t in ["lamp", "chest", "page"]:
			if await goto_prop(g, t):
				g.interact()
				await w(0.3)
				main.hud._close_modal()
	await w(2.5)
	for d in range(2, 6):
		print("LOAD ", d)
		g.load_floor(d)
		await w(1.0)
		await shot("q_floor%d" % d)
	await w(12.0)
	print("FILES sfx ", Sfx.file_sounds.keys().size(), " music ", Sfx.tracks.keys())
	for id in Sfx.sounds.keys():
		var st: AudioStreamWAV = Sfx.sounds[id]
		var data := st.data
		var peak := 0
		var sum := 0.0
		var cnt := int(data.size() / 2.0)
		for i in cnt:
			var v := data.decode_s16(i * 2)
			peak = maxi(peak, absi(v))
			sum += float(v) * v
		print("AUDIO %-10s %6.2fs peak %.2f rms %.3f" % [id, cnt / float(st.mix_rate), peak / 32768.0, sqrt(sum / maxi(cnt, 1)) / 32768.0])
	print("QUICK DONE")
	get_tree().quit()


func sheet() -> void:
	var Art = load("res://scripts/art.gd")
	var ids := ["player0", "player_idle0", "player_w0", "player_w2", "player_dash", "player_atk", "staff",
		"husk_idle", "husk_w0", "husk_w2", "husk_wind", "husk_lunge", "cantor_idle", "cantor_w0", "cantor_cast",
		"brute_idle", "brute_w0", "brute_w2", "brute_wind", "brute_c0", "warden_idle", "warden_w0", "warden_wind",
		"warden_strike", "warden_cast"]
	var sc := 4
	var img := Image.create(2560, 560, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.27, 0.25))
	img.fill_rect(Rect2i(0, 280, 2560, 280), Color(0.05, 0.05, 0.08))
	var x := 10
	for id in ids:
		var src: Image = Art.tex[id].get_image()
		src.resize(src.get_width() * sc, src.get_height() * sc, Image.INTERPOLATE_NEAREST)
		img.blend_rect(src, Rect2i(0, 0, src.get_width(), src.get_height()), Vector2i(x, 270 - src.get_height()))
		var dim: Image = src.duplicate()
		for yy in dim.get_height():
			for xx in dim.get_width():
				var c := dim.get_pixel(xx, yy)
				dim.set_pixel(xx, yy, Color(c.r * 0.25, c.g * 0.25, c.b * 0.35, c.a))
		img.blend_rect(dim, Rect2i(0, 0, dim.get_width(), dim.get_height()), Vector2i(x, 550 - dim.get_height()))
		if Art.tex.has(id + "_e"):
			var em: Image = Art.tex[id + "_e"].get_image()
			em.resize(em.get_width() * sc, em.get_height() * sc, Image.INTERPOLATE_NEAREST)
			img.blend_rect(em, Rect2i(0, 0, em.get_width(), em.get_height()), Vector2i(x, 550 - em.get_height()))
		x += src.get_width() - 40
	img.save_png(dir.path_join("sheet.png"))
	print("SHEET DONE")
	get_tree().quit()


func ui_shots() -> void:
	main.slot = 9
	await w(0.8)
	await shot("u0_title")
	main.pick_new()
	await w(1.0)
	await shot("u1_slots")
	main.hud._close_modal()
	main.new_game(1)
	await w(1.2)
	var g = main.game
	g.add_xp(60)
	await w(1.4)
	await shot("u2_levelup")
	main.hud._choose(0)
	await w(0.3)
	g.xp = 0
	g.levelup_t = -1.0
	main.hud.dialog([load("res://scripts/story.gd").PAGES[2]])
	await w(2.5)
	await shot("u3_dialog")
	main.hud.show_pause()
	await w(0.4)
	await shot("u4_pause")
	main.delete_save(9)
	get_tree().quit()


## Close-up frame bursts of walking and fighting, to check limbs really move.
func anim_shots() -> void:
	main.slot = 9
	await w(0.5)
	main.hud._close_modal()
	main.new_game(0)
	await w(0.8)
	var g = main.game
	main.hud.showcase = true
	g.bot = true
	g.bot_manual = true
	g.god = true
	g.cam_script = true
	g.xp_next = 9999999
	g.ambient_node.color = Color(0.45, 0.45, 0.55)
	g.cam.zoom = Vector2(7, 7)
	# Walk.
	g.bot_mv = Vector2.RIGHT
	g.aim = Vector2.RIGHT
	for i in 4:
		await w(0.11)
		await shot("a_walk%d" % i)
	g.bot_mv = Vector2.ZERO
	# Strike combo against a keeper that is winding up.
	var h = g.spawn_enemy("husk", g.ppos + Vector2(24, 0), 0)
	h.awake = true
	h.hp = 9999.0
	await w(0.45)
	for i in 6:
		if i % 2 == 0:
			g.aim = Vector2.RIGHT
			g.do_slash()
		await w(0.07)
		await shot("a_slash%d" % i)
	h.dead = true
	h.visible = false
	# Bellringer and Warden walking in and winding up.
	g.cam.zoom = Vector2(5, 5)
	var br = g.spawn_enemy("brute", g.ppos + Vector2(70, -10), 0)
	br.awake = true
	g.boss_started = true
	var wd = g.spawn_enemy("warden", g.ppos + Vector2(-66, 0), 0)
	wd.rouse()
	wd.cd = 0.9
	for i in 8:
		await w(0.28)
		await shot("a_foes%d" % i)
	main.delete_save(9)
	get_tree().quit()


## The 3D view: the stairwell, the same moment in both views, and a check that
## the mouse aims where it points.
func view3d_test() -> void:
	main.slot = 9
	await w(0.5)
	main.hud._close_modal()
	main.use_3d = true
	main.new_game(1)
	await w(2.5)
	var g = main.game
	var v = g.view3d
	g.bot = true
	g.bot_manual = true
	g.god = true
	g.hud.hint_t = 0.0
	var fails := 0

	# Mouse aim: the map point the game reads under the cursor must be drawn
	# exactly under the cursor, and Wren must aim toward the cursor on screen.
	g.bot = false
	for off in [Vector2(40, 0), Vector2(-25, 30), Vector2(10, -45), Vector2(-60, -20)]:
		var want: Vector2 = g.pcenter() + off
		get_viewport().warp_mouse(g.view.view_xf * v.cam.unproject_position(Vector3(want.x / 16.0, v.LIFT * v.K / 16.0, (want.y + v.LIFT) / 16.0)))
		await w(0.15)
		# The camera leads toward the cursor, so check against where it is now.
		var mp := get_viewport().get_mouse_position()
		var got: Vector2 = g.mouse_world()
		var back: Vector2 = g.view.view_xf * v.cam.unproject_position(Vector3(got.x / 16.0, v.LIFT * v.K / 16.0, (got.y + v.LIFT) / 16.0))
		var chest: Vector2 = g.view.view_xf * v.cam.unproject_position(Vector3(g.ppos.x / 16.0, v.LIFT * v.K / 16.0, g.ppos.y / 16.0))
		var ok := back.distance_to(mp) < 1.0
		var on_screen := (mp - chest).normalized()
		var aim_screen: Vector2 = (g.view.view_xf * v.cam.unproject_position(Vector3((g.ppos.x + g.aim.x * 30.0) / 16.0, v.LIFT * v.K / 16.0, (g.ppos.y + g.aim.y * 30.0) / 16.0)) - chest).normalized()
		var aims := aim_screen.dot(on_screen) > 0.995
		if not (ok and aims):
			fails += 1
		print("AIM3D cursor %s reads %s, drawn at %s, aim off by %.1f deg %s" % [mp, got, back,
			rad_to_deg(acos(clampf(aim_screen.dot(on_screen), -1.0, 1.0))), "ok" if ok and aims else "FAIL"])
	g.bot = true

	# The way down, close in.
	for e in g.enemies:
		e.dead = true
		e.visible = false
	for p in g.props:
		if p["type"] == "stairs":
			g.teleport(p["pos"] + Vector2(-22, 14))
	g.cam_script = true
	g.cam.zoom = Vector2(5, 5)
	await w(0.8)
	await shot("v_stairs")
	g.cam_script = false

	# One moment, both ways.
	for p in g.props:
		if p["type"] == "brazier":
			g.teleport(p["pos"] + Vector2(0, 30))
			break
	await w(1.0)
	await shot("v_3d")
	main.use_3d = false
	v.set_active(false)
	await w(0.3)
	await shot("v_2d")
	if g.visible != true:
		fails += 1
		print("VIEW3D 2D view did not come back FAIL")
	main.use_3d = true
	v.set_active(true)
	await w(0.3)
	if g.visible:
		fails += 1
		print("VIEW3D 2D view still drawn under 3D FAIL")
	await shot("v_back")

	# A kill, frame by frame: the impact, the white husk, the embers. With
	# --2d it is shot in the flat view, for comparison.
	if OS.get_cmdline_user_args().has("--2d"):
		v.set_active(false)
	for p in g.props:
		if p["type"] == "stairs":
			g.teleport(p["pos"] + Vector2(-30, 20))
	g.cam_script = true
	g.cam.zoom = Vector2(5.5, 5.5)
	g.aim = Vector2.RIGHT
	var foe = g.spawn_enemy("husk", g.ppos + Vector2(20, 4), 0)
	foe.awake = true
	foe.hp = 1.0
	await w(0.3)
	g.combo = 2
	g.combo_t = 1.0
	g.atk_cd = 0.0
	g.do_slash()
	for i in 5:
		await shot("v_kill%d" % i)
		await w(0.06 if i < 2 else 0.18)
	print("VIEW3D %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	main.delete_save(9)
	get_tree().quit()


## Parry, struck-back hexes, and the lamp's oil: each checked for what it
## should do, with screenshots of each.
func mechanics_test() -> void:
	main.slot = 9
	await w(0.5)
	main.hud._close_modal()
	main.new_game(1)
	await w(2.5)
	var g = main.game
	g.bot = true
	g.bot_manual = true
	g.hud.hint_t = 0.0
	g.hud.card_t = 0.0
	var fails := 0
	for e in g.enemies:
		e.dead = true
		e.visible = false
	for p in g.props:
		if p["type"] == "stairs":
			g.teleport(p["pos"] + Vector2(-30, 20))
	await w(0.5)

	# Parry: a husk caught mid-lunge is staggered, and Wren takes nothing.
	g.aim = Vector2.RIGHT
	var h = g.spawn_enemy("husk", g.ppos + Vector2(18, 0), 0)
	h.awake = true
	h.hp = 999.0
	h.state = "lunge"
	h.st = 0.2
	h.dir = Vector2.LEFT
	var hp0: int = g.hp
	g.invuln = 0.0
	g.atk_cd = 0.0
	g.do_slash()
	# Let the burst and the PARRY reach the screen before shooting it.
	await get_tree().process_frame
	await get_tree().process_frame
	await shot("m_parry")
	await w(0.3)
	var ok: bool = h.stun > 0.0 and g.hp == hp0
	print("MECH parry: stun %.2f, hp %d -> %d %s" % [h.stun, hp0, g.hp, "ok" if ok else "FAIL"])
	if not ok:
		fails += 1
	# An ordinary strike on a foe that is not attacking is not a parry.
	h.stun = 0.0
	h.state = "chase"
	g.atk_cd = 0.0
	g.combo_t = 0.0
	g.do_slash()
	ok = h.stun <= 0.0
	print("MECH no parry when idle: stun %.2f %s" % [h.stun, "ok" if ok else "FAIL"])
	if not ok:
		fails += 1
	h.dead = true
	h.visible = false
	await w(1.2)

	# A hex struck out of the air goes back, friendly, toward the cantor:
	# put the cantor along a line with no wall in the way.
	var dir := Vector2.RIGHT
	for cand in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if g.los(g.pcenter(), g.pcenter() + cand * 60.0):
			dir = cand
			break
	var c = g.spawn_enemy("cantor", g.ppos + dir * 50.0, 0)
	c.awake = true
	c.hp = 999.0
	c.cd = 99.0
	await get_tree().process_frame
	g.add_shot(g.pcenter() + dir * 14.0, -dir * 92.0, false, 1, Color(1.0, 0.3, 0.75))
	var hex: Dictionary = g.shots[g.shots.size() - 1]
	g.atk_cd = 0.0
	g.combo_t = 0.0
	g.aim = dir
	g.do_slash()
	ok = hex["friendly"] and hex["vel"].dot(dir) > 0.0
	print("MECH reflect: friendly %s vel %s %s" % [hex["friendly"], hex["vel"], "ok" if ok else "FAIL"])
	if not ok:
		fails += 1
	var chp: float = c.hp
	await w(0.1)
	await shot("m_reflect")
	await w(0.6)
	ok = c.hp < chp
	print("MECH reflected hex hits its caster: hp %.0f -> %.0f %s" % [chp, c.hp, "ok" if ok else "FAIL"])
	if not ok:
		fails += 1
	c.dead = true
	c.visible = false

	# The lamp: a near-empty flask shrinks the light and calls gloams.
	g.oil = g.max_oil
	await w(0.3)
	var full_r: float = g.plight.texture_scale
	g.stats["oil_regen"] = 0.0
	g.oil = 4.0
	await w(0.3)
	var low_r: float = g.plight.texture_scale
	ok = low_r < full_r * 0.7
	print("MECH light follows oil: %.2f -> %.2f %s" % [full_r, low_r, "ok" if ok else "FAIL"])
	if not ok:
		fails += 1
	g.gloam_t = 0.0
	var n := 0
	for k in 40:
		await w(0.25)
		n = 0
		for e in g.enemies:
			if e.kind == "gloam" and not e.dead:
				n += 1
		if n >= 2:
			break
	ok = n >= 1
	print("MECH gloams come when the oil is low: %d %s" % [n, "ok" if ok else "FAIL"])
	if not ok:
		fails += 1
	g.god = false
	g.cam_script = true
	g.cam.zoom = Vector2(3.4, 3.4)
	for e in g.enemies:
		if e.kind == "gloam" and not e.dead:
			g.teleport(e.position + Vector2(-26, 10))
			break
	await w(0.4)
	await shot("m_gloam")
	g.oil = g.max_oil
	await w(0.3)
	n = 0
	for e in g.enemies:
		if e.kind == "gloam" and not e.dead:
			n += 1
	ok = n == 0
	print("MECH gloams melt when the lamp is full again: %d left %s" % [n, "ok" if ok else "FAIL"])
	if not ok:
		fails += 1
	await shot("m_gloam_gone")
	print("MECH %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	main.delete_save(9)
	get_tree().quit(1 if fails > 0 else 0)


var pfails := 0


func pcheck(ok: bool, what: String) -> void:
	print("PROG %s %s" % [what, "ok" if ok else "FAIL"])
	if not ok:
		pfails += 1


## Fair deaths, kept embers, the town, deeds and the kindlings that combine:
## each checked for what it should do, with screenshots of the new screens.
func progress_test() -> void:
	main.slot = 9
	var pr: Dictionary = main.profile
	pr["embers"] = 0
	pr["town"] = []
	pr["tally"] = {}
	pr["feats"] = []
	pr["best"] = {}
	pr["resolve"] = false
	await w(0.5)
	main.hud._close_modal()
	main.new_game(1)
	await w(2.5)
	var g = main.game
	g.bot = true
	g.bot_manual = true
	g.hud.hint_t = 0.0
	g.hud.card_t = 0.0
	for e in g.enemies:
		e.dead = true
		e.visible = false
	for p in g.props:
		if p["type"] == "stairs":
			g.teleport(p["pos"] + Vector2(-30, 20))
	await w(0.3)

	# Mercy: one blow cannot take Wren from more than a heart to nothing.
	g.hp = 8
	g.invuln = 0.0
	g.hurt_player(20, g.ppos + Vector2(10, 0), 100.0, "brute")
	pcheck(g.hp == 1 and not g.dead, "a huge blow from full health leaves one half-heart (hp %d)" % g.hp)
	pcheck(g.invuln >= 1.5, "the last heart gets a longer breath (invuln %.2f)" % g.invuln)
	pcheck(g.last_cause == "brute", "the blow's source is remembered (%s)" % g.last_cause)

	# Embers: a kill pays at once, into the profile.
	var e0 := int(pr["embers"])
	var h = g.spawn_enemy("husk", g.ppos + Vector2(60, 0), 0)
	var xp: int = h.xp
	h.hurt(99999.0, Vector2.ZERO)
	pcheck(int(pr["embers"]) == e0 + xp and xp > 0, "a kill banks its embers (%d -> %d)" % [e0, int(pr["embers"])])

	# Deeds: the first parry pays out.
	var e1 := int(pr["embers"])
	main.tally("parries")
	pcheck((pr["feats"] as Array).has("parry1") and int(pr["embers"]) == e1 + 15, "the first-parry deed pays 15 embers")

	# The lamp's resolve turns some blows, about as often as it says.
	pr["resolve"] = true
	pr["tally"]["deaths"] = 20
	var turned := 0
	for i in 300:
		g.hp = 8
		g.invuln = 0.0
		var hp0: int = g.hp
		g.hurt_player(1, g.ppos + Vector2(10, 0), 0.0, "husk")
		if g.hp == hp0:
			turned += 1
	var rate := turned / 300.0
	pcheck(absf(rate - main.resolve_chance()) < 0.1, "resolve turns %.0f%% of blows (meant %.0f%%)" % [rate * 100.0, main.resolve_chance() * 100.0])
	pr["resolve"] = false
	pr["tally"]["deaths"] = 0
	g.hp = g.max_hp

	# Kindlings that combine.
	g.apply_boon("burn")
	g.apply_boon("trail")
	var offered := false
	for k in 30:
		g._offer_boons("t", "s")
		for o in g.hud.modal_root.find_children("*", "Label", true, false):
			if (o as Label).text == "Wildfire":
				offered = true
		g.hud._close_modal()
		if offered:
			break
	pcheck(offered, "Wildfire is offered once Afterburn and Cinder Trail are held")
	g.apply_boon("wildfire")
	pcheck(int(pr["tally"].get("duos", 0)) == 1 and (pr["feats"] as Array).has("duo"), "taking a combined kindling counts as a deed")
	# Along a line clear of walls, so nothing but the foes gets in the way.
	var dir := Vector2.RIGHT
	for cand in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if g.los(g.pcenter(), g.pcenter() + cand * 100.0):
			dir = cand
			break
	# No puddle underfoot to put the fire out.
	g.surf.clear()
	var a = g.spawn_enemy("husk", g.ppos + dir * 60.0, 0)
	var b = g.spawn_enemy("husk", g.ppos + dir * 74.0, 0)
	for e in [a, b]:
		e.hp = 999.0
		e.awake = true
		e.stun = 5.0
	a.burn_t = 3.0
	a.burn_dps = 6.0
	await w(1.2)
	pcheck(b.burn_t > 0.0, "Wildfire spreads a burn to the foe beside")
	g.apply_boon("starfall")
	var n0: int = g.shots.size()
	g.add_shot(a.center() - dir * 6.0, dir * 200.0, true, 5.0, Color(1, 0.6, 0.2))
	# One frame: the split bolts are short-lived with the second foe so near.
	await get_tree().process_frame
	await get_tree().process_frame
	var splits := 0
	for sh in g.shots:
		if sh.get("split", false):
			splits += 1
	pcheck(splits >= 2, "Starfall breaks a bolt into two on a hit (%d)" % splits)
	g.apply_boon("riposte")
	g.teleport(a.position - dir * 18.0)
	a.state = "lunge"
	a.st = 0.2
	a.stun = 0.0
	a.touch_cd = 1.0
	a.dir = -dir
	g.aim = (a.center() - g.pcenter()).normalized()
	g.atk_cd = 0.0
	g.do_slash()
	pcheck(g.riposte_t > 0.0, "a parry with Riposte readies a sure strike")
	a.state = "chase"
	var hp_a: float = a.hp
	g.atk_cd = 0.0
	g.combo_t = 0.0
	g.do_slash()
	pcheck(g.riposte_t <= 0.0 and hp_a - a.hp >= g.stats["dmg"] * 1.9, "the next strike lands twice as hard (%.0f)" % (hp_a - a.hp))
	for e in [a, b]:
		e.dead = true
		e.visible = false
	await w(0.5)

	# The death screen: what did it, what to do about it, embers kept.
	g.invuln = 0.0
	g.hp = 1
	g.hurt_player(2, g.ppos + Vector2(10, 0), 100.0, "brute")
	await w(3.4)
	pcheck(main.hud.modal == "death" and main.last_cause == "brute", "the death screen names the Bellringer")
	await shot("p_death")
	pcheck(g._wake_line() == Story.WREN_WAKE["brute"][0], "Wren's waking line is about the bell")

	# The town: light everything, then a fresh descent carries it all.
	pr["embers"] = 2000
	main.hud.show_town()
	await w(0.4)
	await shot("p_town")
	for l in Story.TOWN:
		main.light_town_lamp(l["id"])
	pcheck((pr["town"] as Array).size() == Story.TOWN.size() and (pr["feats"] as Array).has("lamps"), "every lamp lights, and the deed for it")
	main.hud.show_town()
	await w(0.3)
	await shot("p_town_lit")
	main.hud.show_deeds()
	await w(0.3)
	await shot("p_deeds")
	main.hud._close_modal()
	main.new_game(1)
	await w(2.0)
	g = main.game
	g.hud.card_t = 0.0
	pcheck(g.max_hp == 10 and g.max_oil == 125.0 and g.spare_match and g.bolt_cost() == 15.0, "the lit town strengthens a fresh descent")
	g.add_xp(g.xp_next)
	await w(1.0)
	pcheck(main.hud.modal == "choice" and main.hud.choice_n == 4, "the chapel lamp offers four kindlings (%d)" % main.hud.choice_n)
	await shot("p_choice4")
	var bell := false
	for o in main.hud.modal_root.find_children("*", "Button", true, false):
		if (o as Button).text.begins_with("Ring the bell"):
			bell = true
	pcheck(bell, "the bell tower lamp offers a fresh choice")
	main.hud._choose(0)

	# A foe winding up off the screen gets a chevron at the edge.
	g.bot = true
	g.bot_manual = true
	var br = g.spawn_enemy("brute", g.ppos + Vector2(0, -150), 0)
	br.awake = true
	br.state = "wind"
	br.st = 5.0
	await w(0.3)
	await shot("p_warning")
	print("PROG %s" % ("PASS" if pfails == 0 else "FAIL %d" % pfails))
	main.delete_save(9)
	get_tree().quit(1 if pfails > 0 else 0)


var probe_on := false
var probe_frames := 0
var probe_sum := 0.0
var probe_worst := 0.0
var probe_script := 0.0
var probe_script_worst := 0.0
var probe_draws := 0.0
var probe_rcpu := 0.0
var probe_rgpu := 0.0
var probe_t0 := 0
var probe_hist := PackedFloat32Array()


## The window, and the world picture drawn into it (see world_view.gd).
func _probe_vps() -> Array:
	var out := [get_viewport().get_viewport_rid()]
	if main.world != null:
		out.append(main.world.vp.get_viewport_rid())
	return out


func _probe_frame_start() -> void:
	probe_t0 = Time.get_ticks_usec()


func _process(dt: float) -> void:
	if not probe_on:
		return
	# This node runs last (highest process priority), so this is the time all
	# scripts' _process took this frame.
	var sp := (Time.get_ticks_usec() - probe_t0) / 1000000.0
	probe_frames += 1
	probe_sum += dt
	probe_worst = maxf(probe_worst, dt)
	probe_hist.append(dt)
	probe_script += sp
	probe_script_worst = maxf(probe_script_worst, sp)
	probe_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	probe_rcpu += RenderingServer.get_frame_setup_time_cpu()
	for vp in _probe_vps():
		probe_rcpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		probe_rgpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)


func probe(label: String, secs: float) -> void:
	process_priority = 1 << 20
	if not get_tree().process_frame.is_connected(_probe_frame_start):
		get_tree().process_frame.connect(_probe_frame_start)
	for vp in _probe_vps():
		RenderingServer.viewport_set_measure_render_time(vp, true)
	probe_frames = 0
	probe_sum = 0.0
	probe_worst = 0.0
	probe_script = 0.0
	probe_script_worst = 0.0
	probe_draws = 0.0
	probe_rcpu = 0.0
	probe_rgpu = 0.0
	probe_hist = PackedFloat32Array()
	var g = main.game
	if g != null:
		g.prof = {}
		g.prof_max = {}
		g.prof_on = true
	probe_on = true
	await w(secs)
	probe_on = false
	var n := maxi(probe_frames, 1)
	probe_hist.sort()
	var p99: float = probe_hist[int(probe_hist.size() * 0.99)] if probe_hist.size() > 0 else 0.0
	print("PERF %-22s fps %6.1f   frame avg %5.2f ms  p99 %5.1f  worst %5.1f ms   scripts avg %5.2f ms  worst %5.1f ms   draw cpu %5.2f ms  gpu %5.2f ms   draw calls %4.0f   nodes %d" % [
		label, n / maxf(probe_sum, 0.001), probe_sum / n * 1000.0, p99 * 1000.0, probe_worst * 1000.0,
		probe_script / n * 1000.0, probe_script_worst * 1000.0, probe_rcpu / n, probe_rgpu / n, probe_draws / n,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	if g != null and is_instance_valid(g):
		g.prof_on = false
		var parts: Array = g.prof.keys()
		parts.sort_custom(func(a, b): return g.prof[a] > g.prof[b])
		var line := "PERF   game update per frame:"
		for k in parts:
			line += "  %s %.2f/%.1f" % [k, g.prof[k] / 1000.0 / n, g.prof_max[k] / 1000.0]
		print(line + "  (avg/worst ms)")


## Timing run: startup, floor generation, and frame time idle and in a big fight.
## Launch with --disable-vsync so the frame rate is not capped.
func perf() -> void:
	print("PERF startup to first frame: %d ms" % Time.get_ticks_msec())
	main.slot = 9
	await w(1.0)
	await probe("title screen", 2.0)
	main.hud._close_modal()
	var t0 := Time.get_ticks_msec()
	main.new_game(1)
	print("PERF new game + depth 1: %d ms" % (Time.get_ticks_msec() - t0))
	var g = main.game
	for d in [2, 4, 7]:
		t0 = Time.get_ticks_msec()
		g.load_floor(d)
		print("PERF load depth %d: %d ms" % [d, Time.get_ticks_msec() - t0])
		await w(0.3)
	g.load_floor(3)
	await w(1.0)
	g.bot = true
	g.bot_manual = true
	g.bot_mv = Vector2.RIGHT
	await probe("walking, depth 3", 3.0)
	g.bot_manual = false
	g.god = true
	g.xp_next = 9999999
	for id in ["nova", "spark", "ward"]:
		g.grant_power(id)
	for id in ["orbit", "trail", "shatter", "twin", "wave", "burn"]:
		g.apply_boon(id)
	for k in 30:
		var kind: String = ["husk", "moth", "cantor", "slime", "brute", "wisp"][k % 6]
		var e = g.spawn_enemy(kind, g.ppos + Vector2.from_angle(k * 0.7) * (30.0 + k * 2.0), 0)
		e.awake = true
		e.hp *= 6.0
	await probe("30-enemy fight", 6.0)
	main.delete_save(9)
	get_tree().quit()


func tap(idx: int, pos: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = pos
	ev.pressed = down
	get_viewport().push_input(ev, true)


func drag(idx: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = pos
	get_viewport().push_input(ev, true)


func pad_pos(g, id: String) -> Vector2:
	g.pad._layout()
	for b in g.pad.btns:
		if b["id"] == id:
			return g.pad.get_global_transform() * (b["c"] as Vector2)
	return Vector2(-1, -1)


func buttons_in(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button:
			out.append(c)
		buttons_in(c, out)


func tap_button(text: String, finger: int = 3) -> bool:
	var all: Array = []
	buttons_in(main.hud.modal_root, all)
	for b in all:
		if (b.text as String).begins_with(text):
			var c: Vector2 = (b as Button).get_global_rect().get_center()
			tap(finger, c, true)
			await w(0.08)
			tap(finger, c, false)
			await w(0.15)
			return true
	return false


func check(label: String, ok: bool) -> void:
	print("TOUCH %s  %s" % ["ok  " if ok else "FAIL", label])


## Drives the on-screen pad with injected touches (-- --autotest --touch).
func touch_test() -> void:
	main.slot = 9
	await w(0.8)
	await shot("t_title")
	await tap_button("New Descent")
	check("a tap presses a menu button", main.hud.modal == "choice")
	await shot("t_slots")
	main.hud._close_modal()
	main.new_game(1)
	var g = main.game
	g.god = true
	g.xp_next = 9999999
	await w(1.2)
	await shot("t_idle")
	var vs: Vector2 = main.hud.root.size
	var so := Vector2(170, vs.y - 170)
	var x0: float = g.ppos.x
	tap(0, so, true)
	drag(0, so + Vector2(70, 0))
	await w(0.5)
	check("the stick moves Wren", g.ppos.x > x0 + 10.0)
	var e = g.spawn_enemy("husk", g.ppos + Vector2(-24, 0), 0)
	e.awake = true
	e.hp = 99999.0
	var hp0: float = e.hp
	var sp := pad_pos(g, "strike")
	tap(1, sp, true)
	await w(0.45)
	await shot("t_fight")
	check("STRIKE turns to the nearest foe", g.aim.dot((e.center() - g.pcenter()).normalized()) > 0.9)
	check("STRIKE lands", e.hp < hp0)
	drag(1, sp + Vector2(0, -60))
	await w(0.12)
	check("dragging off the stone aims by hand", g.aim.y < -0.9)
	tap(1, sp, false)
	tap(0, so, false)
	await w(0.2)
	check("letting go stops everything", g.pad.move == Vector2.ZERO and not g.pad.atk and not g.pad.aiming)
	e.dead = true
	e.visible = false
	for id in ["nova", "spark", "ward"]:
		g.grant_power(id)
	g.oil = g.max_oil
	await w(0.2)
	tap(2, pad_pos(g, "nova"), true)
	tap(2, pad_pos(g, "nova"), false)
	await w(0.1)
	check("a power stone casts", g.pcd["nova"] > 0.0)
	var stock: int = g.dash_stock
	tap(2, pad_pos(g, "dash"), true)
	tap(2, pad_pos(g, "dash"), false)
	await w(0.05)
	check("DASH dashes", g.dash_t > 0.0 or g.dash_stock < stock)
	await w(0.6)
	check("no USE stone away from props", pad_pos(g, "use").x < 0.0)
	await goto_prop(g, "chest")
	await w(0.3)
	var up := pad_pos(g, "use")
	check("USE stone appears by a chest", up.x > 0.0)
	await shot("t_full")
	var chest = g.near_prop
	tap(2, up, true)
	tap(2, up, false)
	await w(0.3)
	check("USE opens the chest", chest != null and chest["done"])
	tap(2, pad_pos(g, "pause"), true)
	tap(2, pad_pos(g, "pause"), false)
	await w(0.3)
	check("the pause stone pauses", main.hud.modal == "pause")
	await shot("t_pause")
	await tap_button("Picture")
	check("the picture switch flips", main.profile["fast"])
	await tap_button("Frame rate")
	await tap_button("Resume")
	check("Resume resumes", main.hud.modal == "")
	await w(0.6)
	await shot("t_fast")
	main.profile["fast"] = false
	main.apply_options()
	# A thumb resting on the stick must not stop another finger using a menu.
	tap(0, so, true)
	drag(0, so + Vector2(0, -70))
	await w(0.2)
	g._offer_boons("A test of kindling", "Pick one.")
	await w(0.1)
	var all: Array = []
	buttons_in(main.hud.modal_root, all)
	var c: Vector2 = (all[0] as Button).get_global_rect().get_center()
	tap(3, c, true)
	tap(3, c, false)
	await w(0.15)
	check("a plaque cannot be picked as it drops in", main.hud.modal == "choice")
	await w(0.6)
	await shot("t_choice")
	tap(3, c, true)
	await w(0.08)
	tap(3, c, false)
	await w(0.2)
	check("a menu answers a second finger", main.hud.modal == "")
	tap(0, so, false)
	main.delete_save(9)
	get_tree().quit()


## A dark square with the lamp's glow in it, drawn in big pixels.
func _icon_back(px: int, block: int) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var n := px / block
	for by in n:
		for bx in n:
			var d := Vector2(bx + 0.5 - n * 0.5, by + 0.5 - n * 0.52).length() / (n * 0.66)
			var k := clampf(1.0 - d, 0.0, 1.0)
			k = floorf(k * 6.0 + 0.5) / 6.0
			var col := Color(0.03, 0.025, 0.06).lerp(Color(1.0, 0.56, 0.18), k * 0.9)
			img.fill_rect(Rect2i(bx * block, by * block, block, block), col)
	return img


func _icon_figure(px: int, scale: int) -> Image:
	var art = preload("res://scripts/art.gd")
	var src: Image = art.tex["player0"].get_image()
	src.convert(Image.FORMAT_RGBA8)
	if art.tex.has("player0_e"):
		var glow: Image = art.tex["player0_e"].get_image()
		glow.convert(Image.FORMAT_RGBA8)
		src.blend_rect(glow, Rect2i(Vector2i.ZERO, glow.get_size()), Vector2i.ZERO)
	var used := src.get_used_rect()
	var fig := src.get_region(used)
	fig.resize(used.size.x * scale, used.size.y * scale, Image.INTERPOLATE_NEAREST)
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.blit_rect(fig, Rect2i(Vector2i.ZERO, fig.get_size()), (Vector2i(px, px) - fig.get_size()) / 2)
	return img


## Writes the launcher icons for the Android build (-- --autotest --icons).
func icons() -> void:
	await w(0.3)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://android"))
	var back := _icon_back(432, 12)
	back.save_png("res://android/icon_bg.png")
	var fig := _icon_figure(432, 10)
	fig.save_png("res://android/icon_fg.png")
	var flat := _icon_back(192, 8)
	var small := _icon_figure(192, 7)
	flat.blend_rect(small, Rect2i(0, 0, 192, 192), Vector2i.ZERO)
	flat.save_png("res://android/icon.png")
	# The Windows build's icon starts from this; ci/make-ico.py packs it into an .ico.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://windows"))
	var win := _icon_back(256, 8)
	win.blend_rect(_icon_figure(256, 9), Rect2i(0, 0, 256, 256), Vector2i.ZERO)
	win.save_png("res://windows/icon.png")
	print("ICONS written, figure %s" % [fig.get_used_rect().size])
	get_tree().quit()


func run() -> void:
	if OS.get_cmdline_user_args().has("--icons"):
		icons()
		return
	if OS.get_cmdline_user_args().has("--touch"):
		touch_test()
		return
	if OS.get_cmdline_user_args().has("--audio"):
		audio_test()
		return
	if OS.get_cmdline_user_args().has("--perfab"):
		perf_ablate()
		return
	if OS.get_cmdline_user_args().has("--perf"):
		perf()
		return
	if OS.get_cmdline_user_args().has("--anim"):
		anim_shots()
		return
	if OS.get_cmdline_user_args().has("--ui"):
		ui_shots()
		return
	if OS.get_cmdline_user_args().has("--sheet"):
		sheet()
		return
	if OS.get_cmdline_user_args().has("--quick"):
		quick()
		return
	if OS.get_cmdline_user_args().has("--view3d"):
		view3d_test()
		return
	if OS.get_cmdline_user_args().has("--mechanics"):
		mechanics_test()
		return
	if OS.get_cmdline_user_args().has("--progress"):
		progress_test()
		return
	if OS.get_cmdline_user_args().has("--wild"):
		var wt = load("res://scripts/wildtest.gd").new()
		wt.main = main
		wt.at = self
		add_child(wt)
		wt.run()
		return
	if OS.get_cmdline_user_args().has("--wildreel"):
		var wr = load("res://scripts/wildreel.gd").new()
		wr.main = main
		add_child(wr)
		return
	if OS.get_cmdline_user_args().has("--showreel"):
		var reel = load("res://scripts/showreel.gd").new()
		reel.main = main
		add_child(reel)
		return
	var hud = main.hud
	main.slot = 9
	main.delete_save(9)
	await w(1.5)
	await shot("01_title")
	main.pick_depth()
	await w(0.6)
	await shot("00_depths")
	main.pick_load()
	await w(0.6)
	await shot("00_slots")
	main.slot = 9
	main.start_run()
	await w(3.0)
	await shot("02_intro")
	hud.auto = true
	while main.game == null:
		await w(0.2)
	await w(2.2)
	var g = main.game
	await shot("03_floor1")

	for d in range(1, 7):
		g = main.game
		g.bot = true
		await fight(g, 3, "1%d_fight" % d)
		if d == 1:
			hud.auto = false
			if await goto_prop(g, "page"):
				g.interact()
				await w(2.0)
				await shot("04_page")
			hud.auto = true
			await w(1.0)
			hud.auto = false
			g.add_xp(60)
			await w(1.2)
			await shot("05_levelup")
			hud.auto = true
			await w(1.5)
			hud.auto = false
			hud.show_pause()
			await w(0.4)
			await shot("06_pause")
			hud._close_modal()
			hud.auto = true
		if d == 1:
			# Exercise every kindling once.
			for b in load("res://scripts/story.gd").BOONS:
				g.apply_boon(b["id"])
			g.xp = 0
		for type in ["relic", "chest", "lamp", "plaque", "chest"]:
			if await goto_prop(g, type):
				g.interact()
				await w(0.9)
		if d == 2:
			g.invuln = 0.0
			g.hp = 1
			g.hurt_player(9, g.ppos + Vector2(4, 0))
			await w(2.8)
			await shot("07_death")
			main.retry()
			await w(2.5)
			g = main.game
			g.bot = true
			print("RELOADED depth ", g.depth, " level ", g.level, " boons ", g.boons.size(), " powers ", g.powers)
		for e in g.enemies:
			if not e.dead:
				e.hurt(99999.0, Vector2.ZERO)
		await w(0.8)
		await goto_prop(g, "stairs")
		await w(0.6)
		await shot("2%d_stairs" % d)
		g.interact()
		await w(3.0)
		await shot("3%d_arrive" % (d + 1))

	# The Heartforge.
	g = main.game
	g.bot = true
	g.bot_manual = false
	print("FINAL DEPTH ", g.depth)
	g.teleport(g.boss.position + Vector2(0, 70))
	await w(4.0)
	for k in 6:
		await w(0.5)
		g.hp = g.max_hp
	await shot("40_boss_p1")
	if not g.boss_dead:
		g.boss.hp = g.boss.max_hp * 0.6
	for k in 8:
		await w(0.5)
		g.hp = g.max_hp
	await shot("41_boss_p2")
	if not g.boss_dead:
		g.boss.hp = g.boss.max_hp * 0.3
	for k in 8:
		await w(0.5)
		g.hp = g.max_hp
	await shot("42_boss_p3")
	if not g.boss_dead:
		g.boss.hurt(99999.0, Vector2.ZERO)
	await w(6.0)
	hud.auto = false
	await goto_prop(g, "cage")
	await w(0.4)
	await shot("43_cage")
	g.interact()
	await w(1.0)
	await shot("44_choice")
	hud._choose(1)
	await w(2.5)
	await shot("45_ending_card")
	hud.auto = true
	var waited := 0.0
	while hud.modal != "end" and waited < 30.0:
		await w(0.3)
		waited += 0.3
	await w(0.6)
	await shot("46_end")
	main.delete_save(9)
	print("AUTOTEST DONE")
	get_tree().quit()


func _all(n: Node, out: Array) -> void:
	for c in n.get_children():
		out.append(c)
		_all(c, out)


## Turns the picture's layers off one at a time in a fixed fight, to see what
## each one costs (-- --autotest --perfab, with --disable-vsync).
func perf_ablate() -> void:
	main.slot = 9
	await w(1.0)
	main.hud._close_modal()
	main.new_game(1)
	var g = main.game
	g.load_floor(3)
	await w(1.0)
	g.god = true
	g.xp_next = 9999999
	for id in ["orbit", "trail", "shatter", "twin", "wave", "burn"]:
		g.apply_boon(id)
	for k in 30:
		var kind: String = ["husk", "moth", "cantor", "slime", "brute", "wisp"][k % 6]
		var e = g.spawn_enemy(kind, g.ppos + Vector2.from_angle(k * 0.7) * (30.0 + k * 2.0), 0)
		e.awake = true
		e.hp *= 60.0
	await w(1.5)
	var nodes: Array = []
	_all(g, nodes)
	var lights_n := 0
	var lights_on := 0
	var glows: Array = []
	var sprites := 0
	for n in nodes:
		if n is PointLight2D:
			lights_n += 1
			lights_on += int(n.enabled)
		elif n is CanvasItem and n.material == g.Art.mat_add:
			glows.append(n)
		if n is Sprite2D:
			sprites += 1
	print("PERF scene: %d nodes, %d sprites, %d additive glows, %d lights (%d on), window %s" % [
		nodes.size(), sprites, glows.size(), lights_n, lights_on, get_window().size])
	var lit: Array = nodes.filter(func(n): return is_instance_valid(n) and n is PointLight2D)
	var tests := {
		"no lights": func(on):
			for l in lit:
				if is_instance_valid(l):
					l.visible = on,
		"only Wren's light": func(on):
			for l in lit:
				if is_instance_valid(l) and l != g.plight:
					l.visible = on,
		"no glows": func(on):
			for n in glows:
				if is_instance_valid(n):
					n.visible = on,
		"no fog": func(on): g.fog_sprite.visible = on,
		"no fx": func(on): g.fx.visible = on,
		"no surfaces": func(on): g.surf.visible = on,
		"no decals": func(on): g.decal_node.visible = on,
		"no map": func(on): g.map_root.visible = on,
		"no enemies/props": func(on): g.ents.visible = on,
		"no hud": func(on):
			for c in main.hud.get_children():
				if c is CanvasItem:
					c.visible = on,
		"full-size world (--hires)": func(on):
			main.world.hires = not on if not OS.get_cmdline_user_args().has("--hires") else on,
	}
	for k in tests:
		await probe("  base", 1.5)
		tests[k].call(false)
		await w(0.2)
		await probe(k, 1.5)
		tests[k].call(true)
		await w(0.2)
	main.delete_save(9)
	get_tree().quit()


## The sound mixer's rules (-- --autotest --audio): every cue the game names can
## sound, a burst of one cue is heard once, and an important cue always finds a
## voice while a trivial one gives way.
func audio_test() -> void:
	await w(1.5)
	var fails := 0
	var was_muted: bool = Sfx.muted
	Sfx.muted = false
	# 1. Every Sfx.play("...") in the scripts resolves to something, unless it is
	#    a cue that is allowed to stay silent until it has a recording.
	var silent_ok := ["chant", "hurt_voice"]
	var re := RegEx.new()
	re.compile("Sfx\\.play\\(\"([a-z0-9_]+)\"")
	var ids := {}
	for f in DirAccess.get_files_at("res://scripts"):
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string("res://scripts/" + f)
		for m in re.search_all(src):
			ids[m.get_string(1)] = f
	# Kinds of blow reach Sfx.play through a variable, so take them from the table.
	for id in Sfx.ALIAS:
		if not ids.has(id):
			ids[id] = "sfx.gd ALIAS"
	for id in ids:
		var r: String = Sfx.resolve(id)
		if r == "" and not silent_ok.has(id):
			fails += 1
			print("AUDIO FAIL cue \"%s\" (in %s) has no sound" % [id, ids[id]])
		elif r != id:
			print("AUDIO      cue %-12s plays %s" % [id, r if r != "" else "(nothing yet)"])
	print("AUDIO %d cues named in the scripts" % ids.size())
	# 2. Thirty hits in one frame are one hit.
	for i in 30:
		Sfx.play("hit")
	var n := 0
	for i in Sfx.pool.size():
		if Sfx.pool[i].playing and Sfx.voice_id[i] == Sfx.resolve("hit"):
			n += 1
	print("AUDIO %s a burst of 30 hits plays %d" % ["ok  " if n == 1 else "FAIL", n])
	fails += int(n != 1)
	# 3. With every voice busy on footsteps, a kill still sounds.
	var long_stream = Sfx.tracks.values()[0] if Sfx.tracks.size() > 0 else null
	if long_stream != null:
		for i in Sfx.pool.size():
			Sfx.pool[i].stream = long_stream
			Sfx.pool[i].volume_db = -80.0
			Sfx.pool[i].play()
			Sfx.voice_id[i] = "step"
			Sfx.voice_prio[i] = 0
			Sfx.voice_t[i] = 0.0
		await get_tree().process_frame
		Sfx.play("kill")
		var got := Sfx.voice_id.has(Sfx.resolve("kill"))
		print("AUDIO %s a kill takes a footstep's voice" % ("ok  " if got else "FAIL"))
		fails += int(not got)
		# 4. With every voice busy on things that matter more, a hit gives way.
		for i in Sfx.pool.size():
			Sfx.voice_id[i] = "death"
			Sfx.voice_prio[i] = 5
		Sfx.last_start.clear()
		Sfx.play("hit")
		var stole := Sfx.voice_id.has(Sfx.resolve("hit"))
		print("AUDIO %s a hit does not cut a death cry" % ("FAIL" if stole else "ok  "))
		fails += int(stole)
		for p in Sfx.pool:
			p.stop()
	Sfx.muted = was_muted
	print("AUDIO %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	get_tree().quit(1 if fails > 0 else 0)
