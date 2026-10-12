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
	print("AUDIO %d recorded sounds, %d music tracks" % [Sfx.file_sounds.size(), Sfx.tracks.size()])
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


## The 3D view: the stairwell, the same moment in both views, and a check that
## the mouse aims where it points.
func view3d_test() -> void:
	main.slot = 9
	await w(0.5)
	main.hud._close_modal()
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
		get_viewport().warp_mouse(v.cam.unproject_position(Vector3(want.x / 16.0, v.LIFT * v.K / 16.0, (want.y + v.LIFT) / 16.0)))
		await w(0.15)
		# The camera leads toward the cursor, so check against where it is now.
		var mp := get_viewport().get_mouse_position()
		var got: Vector2 = g.mouse_world()
		var back: Vector2 = v.cam.unproject_position(Vector3(got.x / 16.0, v.LIFT * v.K / 16.0, (got.y + v.LIFT) / 16.0))
		var chest: Vector2 = v.cam.unproject_position(Vector3(g.ppos.x / 16.0, v.LIFT * v.K / 16.0, g.ppos.y / 16.0))
		var ok := back.distance_to(mp) < 1.0
		var on_screen := (mp - chest).normalized()
		var aim_screen: Vector2 = (v.cam.unproject_position(Vector3((g.ppos.x + g.aim.x * 30.0) / 16.0, v.LIFT * v.K / 16.0, (g.ppos.y + g.aim.y * 30.0) / 16.0)) - chest).normalized()
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


var probe_on := false
var probe_frames := 0
var probe_sum := 0.0
var probe_worst := 0.0
var probe_script := 0.0
var probe_script_worst := 0.0
var probe_draws := 0.0


func _process(dt: float) -> void:
	if not probe_on:
		return
	probe_frames += 1
	probe_sum += dt
	probe_worst = maxf(probe_worst, dt)
	var sp: float = Performance.get_monitor(Performance.TIME_PROCESS)
	probe_script += sp
	probe_script_worst = maxf(probe_script_worst, sp)
	probe_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)


func probe(label: String, secs: float) -> void:
	probe_frames = 0
	probe_sum = 0.0
	probe_worst = 0.0
	probe_script = 0.0
	probe_script_worst = 0.0
	probe_draws = 0.0
	probe_on = true
	await w(secs)
	probe_on = false
	var n := maxi(probe_frames, 1)
	print("PERF %-22s fps %6.1f   frame avg %5.2f ms  worst %5.1f ms   script avg %5.2f ms  worst %5.1f ms   draw calls %4.0f" % [
		label, n / maxf(probe_sum, 0.001), probe_sum / n * 1000.0, probe_worst * 1000.0,
		probe_script / n * 1000.0, probe_script_worst * 1000.0, probe_draws / n])


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
