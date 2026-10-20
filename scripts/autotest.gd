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
	main.pick_mode()
	await w(1.0)
	await shot("u1_modes")
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
	main.hud._close_modal()
	# A lesson over play, and the bestiary with a few foes met and lessons learnt.
	main.profile["taught"] = ["snuff", "flask", "nova"]
	main.profile["seen"] = ["husk", "moth", "gloam"]
	g.hud.lesson_t = -9.0
	g.teach("parry")
	await w(0.8)
	await shot("u5_lesson")
	main.hud.show_pause()
	await w(0.4)
	await shot("u4_pause")
	main.hud.show_codex(main.hud.show_pause)
	await w(0.4)
	await shot("u6_codex")
	main.hud._codex_turn(2)
	await w(0.3)
	await shot("u7_codex_unmet")
	main.hud._codex_turn(6)
	await w(0.3)
	await shot("u8_codex_gloam")
	main.hud._codex_turn(Story.FOES.size())
	await w(0.3)
	await shot("u9_codex_lore")
	main.hud.close_codex()
	main.hud.show_town()
	await w(0.4)
	await shot("u10_town")
	# One wick: the badge on the way down, and the end of it.
	main.hud._close_modal()
	main.mode = "descent"
	main.new_game(3, {}, true)
	await w(5.0)
	main.game.hud.card_t = 0.0
	await shot("u5_descent_hud")
	# A Descent's slot card, in slot 1 - only where a save tag keeps it apart
	# from the player's own saves.
	if main._slot_path(0) != "user://save_0.json":
		main.game.save_game(-1)
		var f := FileAccess.open(main._slot_path(0), FileAccess.WRITE)
		f.store_string(JSON.stringify(main.read_save(9)))
		f.close()
		main.pick_load()
		await w(1.0)
		await shot("u5_descent_slot")
		main.hud._close_modal()
		main.delete_save(0)
	main.game.bot = true
	main.game.match_used = true
	main.game.invuln = 0.0
	main.game.hp = 1
	main.game.hurt_player(2, main.game.ppos + Vector2(10, 0), 100.0, "brute")
	main.bank(38)
	await w(3.6)
	await shot("u6_descent_death")
	main.mode = "pilgrim"
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
	fails += await _feel_checks(g)
	# Set-aside rooms and the second stair (roomtest.gd).
	var rt = load("res://scripts/roomtest.gd").new()
	rt.main = main
	rt.at = self
	add_child(rt)
	fails += await rt.run_checks()
	print("MECH %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	main.delete_save(9)
	get_tree().quit(1 if fails > 0 else 0)


## Combat feel: hitstop is the longest of a frame's hits, never their sum, and
## only Wren's blows (and blows on her) stop the world; shake is capped, moves
## in whole art pixels and obeys the setting; the setting survives a reload.
func _feel_checks(g) -> int:
	# Lambdas capture locals by value, so the count lives in an array.
	var fails := [0]
	var feel := func(ok: bool, what: String) -> void:
		print("MECH feel: %s %s" % [what, "ok" if ok else "FAIL"])
		if not ok:
			fails[0] += 1
	var keep: Dictionary = main.profile.duplicate(true)
	main.profile["shake"] = 2
	main.profile["resolve"] = false
	var crit0: float = g.stats["crit"]
	g.stats["crit"] = 0.0
	g.snuffed = false
	g.god = false
	g.aim = Vector2.RIGHT
	var crowd: Array = []
	for i in 12:
		var e = g.spawn_enemy("husk", g.ppos + Vector2(15.0 + (i % 3) * 3.0, (i / 3 - 1.5) * 3.0), 0)
		e.awake = true
		e.state = "rest"
		e.st = 99.0
		e.stun = 99.0
		e.hp = 999.0
		crowd.append(e)
	await get_tree().process_frame
	var reset := func() -> void:
		g.hitstop = 0.0
		g.stop_debt = 0.0
		g._stop_f = -1
		g.riposte_t = 0.0
		g.atk_cd = 0.0
	# A light swing through the whole crowd holds for one light hit.
	reset.call()
	g.combo_t = 0.0
	g.do_slash()
	var struck := 0
	for e in crowd:
		if e.hp < 999.0:
			struck += 1
	feel.call(struck >= 6 and is_equal_approx(g.hitstop, 0.04),
		"light swing hit %d foes, hitstop %.3f (want 0.040)" % [struck, g.hitstop])
	reset.call()
	g.combo = 2
	g.combo_t = 0.5
	g.do_slash()
	feel.call(is_equal_approx(g.hitstop, 0.08), "heavy swing through the crowd, hitstop %.3f (want 0.080)" % g.hitstop)
	reset.call()
	g.freeze(0.04)
	for i in 20:
		g.freeze(0.12)
	g.freeze(0.08)
	feel.call(is_equal_approx(g.hitstop, 0.12), "22 freezes in one frame hold %.3f, the longest (want 0.120)" % g.hitstop)
	reset.call()
	g.freeze(1.0)
	feel.call(is_equal_approx(g.hitstop, g.HITSTOP_CAP), "a huge freeze is capped at %.3f" % g.hitstop)
	# Freezes in quick succession are cut short.
	await get_tree().process_frame
	g.hitstop = 0.0
	g.freeze(0.12)
	feel.call(g.hitstop < 0.12, "a freeze straight after another is shorter: %.3f" % g.hitstop)
	# A burn kill, or fire on Wren, does not stop the world; a hex holds less than a charge.
	for e in crowd:
		e.dead = true
		e.visible = false
	var b = g.spawn_enemy("husk", g.ppos + Vector2(40, 0), 0)
	b.awake = true
	b.hp = 1.0
	reset.call()
	b.hurt(5.0, Vector2.ZERO, Color(1.0, 0.6, 0.2), "burn")
	feel.call(b.dead and g.hitstop == 0.0, "a foe burned out holds nothing: %.3f" % g.hitstop)
	var hits := {}
	var wash := {}
	for kind in ["fire", "hex", "claw", "charge", "claw_low"]:
		reset.call()
		g.invuln = 0.0
		g.hp = 2 if kind == "claw_low" else g.max_hp
		g.hud.hurt_wash = 0.0
		var brute = g.spawn_enemy("brute", g.ppos + Vector2(60, 0), 0)
		match kind:
			"fire":
				g.hurt_player(1, g.ppos + Vector2(0, 6), 90.0, "fire")
			"hex":
				g.hurt_player(1, g.ppos + Vector2(10, 0), 130.0, "cantor")
			"charge":
				g.hurt_player(2, g.ppos + Vector2(10, 0), 280.0, brute)
			_:
				g.hurt_player(1, g.ppos + Vector2(10, 0), 170.0, brute)
		brute.dead = true
		brute.visible = false
		hits[kind] = g.hitstop
		wash[kind] = g.hud.hurt_wash
	g.hp = g.max_hp
	g.invuln = 0.0
	feel.call(hits["fire"] == 0.0 and hits["hex"] < hits["claw"] and hits["claw"] < hits["charge"],
		"hitstop on Wren: fire %.2f < hex %.2f < claw %.2f < charge %.2f" % [hits["fire"], hits["hex"], hits["claw"], hits["charge"]])
	feel.call(wash["claw_low"] > wash["claw"], "the red flash is stronger near death: %.2f > %.2f" % [wash["claw_low"], wash["claw"]])
	g.hitstop = 0.0
	g.stats["crit"] = crit0

	# Twenty blows in one frame shake no harder than one.
	g.trauma = 0.0
	g._shake_f = -1
	for i in 20:
		g.add_shake(5.0)
	feel.call(is_equal_approx(g.trauma, sqrt(5.0 / g.SHAKE_PX)), "20 shakes in one frame: trauma %.3f, as one" % g.trauma)
	# Blows every frame for a second stack only up to the cap, in whole art pixels.
	var top := 0.0
	var worst := 0.0
	var whole := true
	for i in 60:
		g.add_shake(5.0)
		await get_tree().process_frame
		top = maxf(top, g.trauma)
		worst = maxf(worst, maxf(absf(g.shake_off.x), absf(g.shake_off.y)))
		whole = whole and g.shake_off == g.shake_off.round()
	feel.call(top <= g.TRAUMA_STACK + 0.001 and worst <= ceilf(g.TRAUMA_STACK * g.TRAUMA_STACK * g.SHAKE_PX) and worst >= 1.0,
		"a second of blows: trauma at most %.3f, shake at most %d px" % [top, int(worst)])
	feel.call(whole, "shake moves in whole art pixels")
	# Off: no shake, punch or zoom kick at all. Low: half.
	main.profile["shake"] = 0
	g.trauma = 0.0
	g._shake_f = -1
	g.cam_punch = Vector2.ZERO
	g.zoom_kick = 0.0
	g.add_shake(12.0)
	g.punch(Vector2.RIGHT, 6.0)
	g.kick(0.2)
	var moved := 0.0
	for i in 10:
		await get_tree().process_frame
		moved = maxf(moved, g.shake_off.length() + g.cam_punch.length())
	feel.call(moved == 0.0 and g.zoom_kick == 0.0, "shake off: view moved %.2f, zoom kick %.2f" % [moved, g.zoom_kick])
	main.profile["shake"] = 1
	g.trauma = 0.0
	g._shake_f = -1
	g.add_shake(12.0)
	worst = 0.0
	for i in 10:
		await get_tree().process_frame
		worst = maxf(worst, maxf(absf(g.shake_off.x), absf(g.shake_off.y)))
	feel.call(worst >= 1.0 and worst <= g.SHAKE_PX * 0.5, "shake low: at most %d px" % int(worst))
	# The setting goes into the profile and comes back out of it.
	var path := "user://feel_profile_%d.json" % OS.get_process_id()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(main.profile))
	f.close()
	main.profile["shake"] = 2
	main._load_profile(path)
	var back: int = main.profile["shake"]
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"shake": 7}))
	f.close()
	main._load_profile(path)
	var clamped: int = main.profile["shake"]
	DirAccess.remove_absolute(path)
	feel.call(back == 1 and clamped == 2 and main.hud._opt_text("shake") == "Shake:  full",
		"shake setting saved and loaded: %d, a bad one clamped to %d" % [back, clamped])
	main.profile = keep
	return fails[0]


var pfails := 0


func _key_ev(k: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.pressed = true
	return ev


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
	await build_checks()
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

	# Lessons: one comes the first time its moment does, and never again.
	# (A hollow wall close by would speak first; that one is tried on the bot tour.)
	pr["taught"] = ["hollow"]
	pr["seen"] = []
	g.teach_done = false
	g.hud.lesson_t = -9.0
	g.oil = g.max_oil * 0.25
	g.teach_t = 0.0
	await w(0.4)
	pcheck(main.knows("snuff") and g.hud.lesson_cur.get("id", "") == "snuff" and g.hud.lesson_box.visible,
		"low oil teaches the hooded lamp, on the screen")
	pcheck(g.hud.modal == "", "a lesson never stops play for input")
	g.hud.lesson_t = -9.0
	pcheck(not g.teach("snuff") and (pr["taught"] as Array).count("snuff") == 1, "a lesson taught is not taught again")
	g.oil = g.max_oil
	var seen_h = g.spawn_enemy("husk", g.ppos + Vector2(28, 0), 0)
	seen_h.stun = 9.0
	await w(0.5)
	pcheck((pr["seen"] as Array).has("husk") and not (pr["seen"] as Array).has("cantor"), "a foe in sight is met, for the bestiary")
	seen_h.dead = true
	seen_h.visible = false
	g.hud.lesson_t = -9.0

	# The bestiary, from the pause screen: met foes by name, the rest in shadow.
	main.hud.show_pause()
	for o in main.hud.modal_root.find_children("*", "Button", true, false):
		if (o as Button).text == "Bestiary":
			(o as Button).pressed.emit()
	pcheck(main.hud.modal == "codex", "the pause screen opens the bestiary")
	var names: Array = []
	for o in main.hud.modal_root.find_children("*", "Label", true, false):
		names.append((o as Label).text)
	for o in main.hud.modal_root.find_children("*", "Button", true, false):
		names.append((o as Button).text)
	pcheck(names.has("Hollow Keeper") and names.has("? ? ?") and not names.has("Choir Cantor"),
		"met foes are named and the rest are hidden")
	await w(0.3)
	await shot("p_codex")
	main.hud._codex_turn(Story.FOES.size())
	await w(0.3)
	var lore_lit := false
	for o in main.hud.modal_root.find_children("*", "Label", true, false):
		if (o as Label).text == Story.LESSONS[2]["lore"]:
			lore_lit = true
	pcheck(lore_lit, "the lamp lore page keeps the lesson taught")
	await shot("p_codex_lore")
	main.hud.close_codex()
	pcheck(main.hud.modal == "pause", "closing the bestiary goes back to the pause screen")
	main.hud._close_modal()

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
	main.hud.show_town()
	for o in main.hud.modal_root.find_children("*", "Button", true, false):
		if (o as Button).text == "Bestiary":
			(o as Button).pressed.emit()
	pcheck(main.hud.modal == "codex", "the town opens the bestiary")
	get_viewport().push_input(_key_ev(KEY_RIGHT))
	pcheck(main.hud.codex_page == 1, "the arrow keys turn the page")
	get_viewport().push_input(_key_ev(KEY_ESCAPE))
	pcheck(main.hud.modal == "town", "Esc goes back to the town")
	main.hud._close_modal()
	main.new_game(1)
	await w(2.0)
	g = main.game
	g.hud.card_t = 0.0
	pcheck(not g.teach("snuff"), "a lesson stays taught in the next descent")
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
	await ways_down_test()
	print("PROG %s" % ("PASS" if pfails == 0 else "FAIL %d" % pfails))
	main.delete_save(9)
	get_tree().quit(1 if pfails > 0 else 0)


## A fall that nothing catches: no spare match, no turned blow.
func _fall(g) -> void:
	g.match_used = true
	g.invuln = 0.0
	g.hp = 1
	g.hurt_player(2, g.ppos + Vector2(10, 0), 100.0, "husk")
	# Game time runs behind the clock on a slow frame, so wait for the screen itself.
	var waited := 0.0
	while main.hud.modal != "death" and waited < 12.0:
		await w(0.2)
		waited += 0.2
	await w(0.3)


func _modal_has(cls: String, text: String) -> bool:
	if main.hud.modal_root == null:
		return false
	for n in main.hud.modal_root.find_children("*", cls, true, false):
		if n.text.contains(text):
			return true
	return false


func _press(text: String) -> bool:
	for n in main.hud.modal_root.find_children("*", "Button", true, false):
		if (n as Button).text == text:
			(n as Button).pressed.emit()
			return true
	return false


## The two ways down: a pilgrim wakes at the lamp, a Descent's fall is the end
## of it, and each keeps its own records.
func ways_down_test() -> void:
	var pr: Dictionary = main.profile
	main.hud._close_modal()
	main.pick_mode()
	await w(0.6)
	pcheck(main.hud.modal == "choice" and main.hud.choice_n == 2, "a new slot asks which way down")
	await shot("p_modes")
	main.hud._close_modal()

	# Pilgrimage: the fall is caught at the last lamp, build and all.
	main.mode = "pilgrim"
	main.delete_save(9)
	main.new_game(1)
	await w(2.0)
	var g = main.game
	g.bot = true
	g.bot_manual = true
	g.level = 4
	g.apply_boon("edge")
	var lamp := -1
	var lamp_pos := Vector2.ZERO
	for p in g.props:
		if p["type"] == "lamp":
			lamp = p["idx"]
			lamp_pos = p["pos"]
	g.save_game(lamp)
	pcheck(main.mode_of(main.read_save(9)) == "pilgrim", "a pilgrimage's save says so")
	await _fall(g)
	pcheck(main.hud.modal == "death" and not main.read_save(9).is_empty() and _modal_has("Button", "Wake at your last lamp"),
		"a pilgrim's fall keeps the slot and offers the lamp")
	var dead_g = g
	main.retry()
	# Looked at the moment she wakes, before a foe on the floor can reach her.
	var waited := 0.0
	while (main.game == dead_g or main.game == null) and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	await get_tree().process_frame
	g = main.game
	pcheck(g.level == 4 and g.boons.has("edge") and g.hp == g.max_hp and main.mode == "pilgrim", "the pilgrim wakes whole, with her build (level %d, %s, hp %d/%d)" % [g.level, g.boons, g.hp, g.max_hp])
	pcheck(lamp < 0 or (g.ppos - lamp_pos).length() < 40.0, "and beside the lamp (%.0f away)" % (g.ppos - lamp_pos).length())

	# Descent: embers burn brighter, and the way down is kept in the save.
	main.mode = "descent"
	main.delete_save(9)
	main.new_game(1)
	await w(2.0)
	g = main.game
	var e0 := int(pr["embers"])
	main.bank(10)
	pcheck(int(pr["embers"]) == e0 + 15, "on one wick embers burn half again as bright (+%d)" % (int(pr["embers"]) - e0))
	g.level = 5
	g.apply_boon("edge")
	g.save_game(-1)
	pcheck(main.mode_of(main.read_save(9)) == "descent" and int(main.read_save(9).get("run_embers", 0)) == 15, "a Descent's save says so, and counts its embers")
	main.mode = "pilgrim"
	main.load_slot(9)
	await w(2.5)
	g = main.game
	pcheck(main.mode == "descent" and g.level == 5 and main.run_embers == 15, "a Descent loads as a Descent")
	# Saves from before the choice were all pilgrimages.
	var old: Dictionary = main.read_save(9)
	old.erase("mode")
	var f := FileAccess.open(main._slot_path(9), FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	main.mode = "descent"
	main.load_slot(9)
	await w(2.5)
	pcheck(main.mode == "pilgrim", "an old save with no way down loads as a pilgrimage")

	# A Descent left mid-floor keeps its wounds; a fall ends it for good.
	main.mode = "descent"
	main.delete_save(9)
	main.new_game(1)
	await w(2.0)
	g = main.game
	g.bot = true
	g.bot_manual = true
	g.level = 5
	g.apply_boon("edge")
	g.hp = 3
	main._keep_descent()
	pcheck(int(main.read_save(9).get("hp", 0)) == 3 and int(main.read_save(9).get("level", 0)) == 5, "leaving a Descent mid-floor saves it as it stands")
	var e1 := int(pr["embers"])
	var lit: int = (pr["town"] as Array).size()
	await _fall(g)
	pcheck(main.hud.modal == "death" and main.read_save(9).is_empty(), "a Descent's fall clears its slot")
	pcheck(int(pr["embers"]) >= e1 and (pr["town"] as Array).size() == lit, "but the embers and the town are kept")
	pcheck(_modal_has("Label", "Descent ended at Depth I") and not _modal_has("Button", "Wake at your last lamp"),
		"the death screen says where the Descent ended, and offers no lamp")
	pcheck(int(pr["best"].get("depth_descent", 0)) >= 1 and int(pr["best"].get("depth_pilgrim", 0)) >= 1, "each way down keeps its own deepest depth")
	await shot("p_descent_death")
	pcheck(_press("Begin a new Descent"), "a new Descent can be begun from the death screen")
	await w(2.5)
	g = main.game
	pcheck(g.depth == 1 and g.level == 1 and not g.boons.has("edge") and main.mode == "descent" and not g.dead,
		"it starts at the top with nothing carried")

	# Starting partway down is always a pilgrimage.
	main.pending_depth = 2
	main._start_depth_in_slot(9)
	await w(2.5)
	pcheck(main.mode == "pilgrim" and main.game.depth == 2, "depth select starts a pilgrimage")

	# Down to the fourth depth and out again on one wick: deeds and records.
	main.mode = "descent"
	main.new_game(4)
	await w(2.0)
	pcheck(int(pr["best"].get("depth_descent", 0)) == 4 and (pr["feats"] as Array).has("descent4"), "the fourth depth on one wick is a record and a deed")
	main.ending(0)
	await w(1.0)
	pcheck(int(pr["tally"].get("descent_wins", 0)) == 1 and (pr["feats"] as Array).has("descent_win") and main.read_save(9).is_empty(),
		"a finished Descent is counted, and is a deed")
	main._keep_descent()
	pcheck(main.read_save(9).is_empty(), "and nothing writes its slot back")
	main.mode = "pilgrim"


## Choices with stakes: the relic draft, the aspects the offers lean toward,
## stack caps, what each bargain gives and takes, and an old save still loading.
func build_checks() -> void:
	main.new_game(1)
	await w(2.0)
	var g = main.game
	var hud = main.hud
	g.bot = true
	g.bot_manual = true
	g.god = false
	hud.card_t = 0.0
	for e in g.enemies:
		e.dead = true
		e.visible = false

	# The relic draft: up to three distinct relics she lacks, until none are left.
	var got: Array = []
	var draft_ok := true
	for k in 4:
		g._offer_relics()
		var n_left: int = 4 - k
		var ids: Array = g.offer.duplicate()
		var distinct := true
		for id in ids:
			if ids.count(id) > 1 or got.has(id):
				distinct = false
		var ok: bool = hud.modal == "choice" and g.offer_kind == "relic" and ids.size() == mini(3, n_left) and distinct
		if k == 0:
			await w(0.6)
			await shot("p_relic_draft")
		if not ok:
			draft_ok = false
			print("PROG relic offer %d: %s" % [k, ids])
		hud._choose(0)
		got.append(ids[0])
		hud._close_modal()
	pcheck(draft_ok, "each relic stand offers up to three distinct relics Wren lacks (%s)" % [got])
	pcheck(g.powers["nova"] and g.powers["spark"] and g.powers["ward"] and g.spare_match, "four stands give all four relics, in the order chosen")
	g._offer_relics()
	pcheck(g.offer_kind == "boon", "with every relic held, a stand is a kindling cache")
	hud._close_modal()

	# The first offer shows one of each aspect.
	g.boons.clear()
	var first: Array = g.draw_offer(3)
	var seen := {}
	for c in first:
		seen[c["aspect"]] = true
	pcheck(seen.size() == 3, "the first offer holds one card of each aspect")

	# Two kindlings of Oil & Ember: the offers lean toward it, with one card from elsewhere.
	g.boons = ["kindle", "flask"]
	var lean := 0
	var slots := 0
	var always_off := true
	for k in 300:
		var opts: Array = g.draw_offer(3)
		var off := 0
		for c in opts:
			if c["aspect"] != "ember":
				off += 1
			if not c["off"]:
				slots += 1
				if c["aspect"] == "ember":
					lean += 1
		if off == 0:
			always_off = false
	var share := float(lean) / maxf(slots, 1.0)
	pcheck(share > 0.55, "after two Oil & Ember picks, %.0f%% of the leaning cards are Oil & Ember" % (share * 100.0))
	pcheck(always_off, "every offer still holds a card from another aspect")

	# A capped kindling stops being offered.
	g.boons = ["edge", "edge", "edge"]
	var capped_seen := false
	for k in 200:
		for c in g.draw_offer(4):
			if c["id"] == "edge":
				capped_seen = true
	pcheck(not g.can_offer(Story.BOONS[0]) and not capped_seen, "Keen Edge stops coming after three")
	var bargains := 0
	var two := false
	g.boons.clear()
	for k in 300:
		var nb := 0
		for c in g.draw_offer(4):
			if c.get("bargain", false):
				nb += 1
		bargains += nb
		two = two or nb > 1
	pcheck(bargains > 0 and not two, "bargains are offered, never two at once (%d seen)" % bargains)

	# Offer cards: an aspect on each, a bargain's price, and the half of a pair.
	g.boons = ["burn", "edge", "edge"]
	var cards: Array = [g.boon_card(Story.BOONS[19]), g.boon_card(Story.BOONS[24]), g.boon_card(Story.BOONS[0])]
	pcheck(cards[0]["id"] == "trail" and String(cards[0].get("hint", "")).contains("Wildfire") and cards[0].get("pairs", false),
		"Cinder Trail's card says it pairs with Afterburn (%s)" % cards[0].get("hint", ""))
	pcheck(cards[1]["id"] == "burnwick" and cards[1].has("cost"), "a bargain's card carries its price")
	pcheck(cards[2].get("held", "") == "2 of 3", "a stacking kindling's card says how many are held (%s)" % cards[2].get("held", ""))
	g._show_offer("boon", "The warmth below reaches up to you", "Level 4  -  choose a kindling", cards, func(_i): pass)
	await w(0.7)
	await shot("p_offer_cards")
	hud._close_modal()

	# Each bargain pays and costs.
	var s0: Dictionary = g.stats.duplicate()
	g.apply_boon("burnwick")
	pcheck(is_equal_approx(g.stats["bolt_dmg"], s0["bolt_dmg"] * 1.6) and is_equal_approx(g.stats["oil_regen"], s0["oil_regen"] * 0.5),
		"Burn the Wick: bolts +60%, oil back half as fast")
	g.apply_boon("lens")
	pcheck(is_equal_approx(g.stats["power"], s0["power"] * 1.5) and is_equal_approx(g.power_cost("nova"), 42.0),
		"Cracked Lens: powers +50%%, a nova costs %.0f oil" % g.power_cost("nova"))
	g.apply_boon("leaden")
	pcheck(is_equal_approx(g.stats["dmg"], s0["dmg"] * 1.45) and is_equal_approx(g.stats["speed"], s0["speed"] * 0.85),
		"Leaden Hook: strikes +45%, 15% slower")
	var mhp: int = g.max_hp
	g.apply_boon("hollow")
	pcheck(g.max_hp == mhp - 2 and is_equal_approx(g.stats["crit"], s0["crit"] + 0.25), "Hollow Heart: a heart gone, +25% sure strikes")
	# The pact: half again in embers, and the gloams come at a third of a flask.
	g.oil = g.max_oil
	var h = g.spawn_enemy("husk", g.ppos + Vector2(60, 0), 0)
	var e0 := int(main.profile["embers"])
	h.hurt(99999.0, Vector2.ZERO)
	var plain := int(main.profile["embers"]) - e0
	g.oil = g.max_oil * 0.3
	g.gloam_t = 0.0
	var gl0 := _gloams(g)
	g._update_gloam(0.1)
	var before_pact := _gloams(g) - gl0
	g.apply_boon("pact")
	# Full oil again, so the kill pays for the pact alone and not for the dark.
	g.oil = g.max_oil
	h = g.spawn_enemy("husk", g.ppos + Vector2(60, 0), 0)
	e0 = int(main.profile["embers"])
	h.hurt(99999.0, Vector2.ZERO)
	var paid := int(main.profile["embers"]) - e0
	g.gloam_t = 0.0
	g.oil = g.max_oil * 0.3
	gl0 = _gloams(g)
	g._update_gloam(0.1)
	var after_pact := _gloams(g) - gl0
	pcheck(paid == roundi(plain * 1.5) and before_pact == 0 and after_pact == 1,
		"Pact of Embers: a kill pays %d not %d, and gloams come at 30%% oil (%d -> %d)" % [paid, plain, before_pact, after_pact])
	for e in g.enemies:
		e.dead = true
		e.visible = false
	g.oil = g.max_oil
	g.apply_boon("moth_cloak")
	g.dash_t = 0.0
	g.dash_stock = 1
	g.try_dash()
	var dash_long: bool = is_equal_approx(g.dash_t, 0.24)
	g.dash_t = 0.0
	g.aim = Vector2.RIGHT
	g.hp = 8
	g.invuln = 0.0
	g.hurt_player(1, g.ppos + Vector2(20, 0), 0.0, "husk")
	var front: int = 8 - g.hp
	g.hp = 8
	g.invuln = 0.0
	g.hurt_player(1, g.ppos + Vector2(-20, 0), 0.0, "husk")
	var behind: int = 8 - g.hp
	pcheck(dash_long and front == 1 and behind == 2, "Moth-Eaten Cloak: a longer dash, and blows from behind land harder (%d, %d)" % [front, behind])
	g.hp = g.max_hp

	# A save from before any of this still loads, and the new numbers start plain.
	var old_stats := {"dmg": 12.5, "reach": 1.0, "speed": 80.0, "bolt_dmg": 13.0, "bolt_n": 1, "dash_cd": 0.9,
		"light": 1.0, "oil_regen": 2.0, "heart_drop": 0.05, "sear": 0.0, "siphon": 0.0, "thorns": 0.0, "pierce": 0,
		"power": 1.0, "cdr": 1.0, "orbit": 0, "wave": 0.0, "burn": 0.0, "shatter": 0.0, "dash_n": 1, "trail": 0.0,
		"magnet": 1.0, "xp_mult": 1.0, "crit": 0.0, "wildfire": 0.0, "starfall": 0.0, "flashstep": 0.0,
		"chainburst": 0.0, "riposte": 0.0, "mote_k": 1.0, "echo": 0.5, "echo_cd": 3.0}
	main.write_save({"v": 1, "depth": 2, "name": "The Buried Choir", "seed": 4242, "lamp_idx": -1, "hp": 6, "max_hp": 8,
		"oil": 80.0, "max_oil": 100.0, "xp": 3, "level": 2, "xp_next": 30, "stats": old_stats, "boons": ["edge"],
		"powers": {"nova": true, "spark": false, "ward": false}, "spare": false, "match_used": false, "kills": 5,
		"pages": 1, "run_time": 100.0, "said": {}, "done_props": [], "dead_spawns": []})
	var s: Dictionary = main.read_save(9)
	main.new_game(int(s["depth"]), s)
	await w(1.5)
	g = main.game
	var left: Array = []
	for r in g.relics_unowned():
		left.append(r["power"])
	pcheck(g.depth == 2 and g.boons == ["edge"] and is_equal_approx(g.stats["dmg"], 12.5) and is_equal_approx(g.stats["dash_len"], 1.0)
		and g.stats["frail"] == 0 and left == ["spark", "ward", "match"], "an old save loads, with the relics it lacks still to find (%s)" % [left])
	main.delete_save(9)


func _gloams(g) -> int:
	var n := 0
	for e in g.enemies:
		if e.kind == "gloam" and not e.dead:
			n += 1
	return n


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
	await tap_button("Bestiary")
	check("a tap opens the bestiary", main.hud.modal == "codex")
	await tap_button("Lamp lore")
	check("a tap turns to the lamp lore", main.hud.codex_page == Story.FOES.size())
	await shot("t_codex")
	await tap_button("Back")
	check("Back returns to the pause screen", main.hud.modal == "pause")
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
	if OS.get_cmdline_user_args().has("--balance"):
		var bal = load("res://scripts/balance.gd").new()
		bal.main = main
		bal.at = self
		add_child(bal)
		bal.run()
		return
	if OS.get_cmdline_user_args().has("--rooms"):
		var rt = load("res://scripts/roomtest.gd").new()
		rt.main = main
		rt.at = self
		add_child(rt)
		rt.run()
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
	# 1. Every Sfx.play("...") in the scripts resolves to something. A cue may be
	#    let off here while it waits for a recording; none is now.
	var silent_ok: Array[String] = []
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
