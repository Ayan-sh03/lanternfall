extends Node
## Self-play smoke test. Run with:  godot --path . -- --autotest --shotdir=<dir>
## Plays through every floor with a simple bot, exercises each interaction, saves
## screenshots along the way, then quits. Not used in normal play.

var main
var dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			dir = a.substr(10)
	run()


func w(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func shot(id: String) -> void:
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


var probe_on := false
var probe_frames := 0
var probe_sum := 0.0
var probe_worst := 0.0
var probe_script := 0.0
var probe_script_worst := 0.0


func _process(dt: float) -> void:
	if not probe_on:
		return
	probe_frames += 1
	probe_sum += dt
	probe_worst = maxf(probe_worst, dt)
	var sp: float = Performance.get_monitor(Performance.TIME_PROCESS)
	probe_script += sp
	probe_script_worst = maxf(probe_script_worst, sp)


func probe(label: String, secs: float) -> void:
	probe_frames = 0
	probe_sum = 0.0
	probe_worst = 0.0
	probe_script = 0.0
	probe_script_worst = 0.0
	probe_on = true
	await w(secs)
	probe_on = false
	var n := maxi(probe_frames, 1)
	print("PERF %-22s fps %6.1f   frame avg %5.2f ms  worst %5.1f ms   script avg %5.2f ms  worst %5.1f ms" % [
		label, n / maxf(probe_sum, 0.001), probe_sum / n * 1000.0, probe_worst * 1000.0,
		probe_script / n * 1000.0, probe_script_worst * 1000.0])


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


func run() -> void:
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
