extends Node
## Checks the rigged 3D figures and the turning camera. Run with:
##   godot --path . -- --autotest --models [--shotdir=<dir>]
## Exits 1 if anything fails.

const ActorsS = preload("res://scripts/actors3d.gd")

var main
var at
var fails := 0


func check(ok: bool, what: String) -> void:
	print("MODEL %s %s" % [what, "ok" if ok else "FAIL"])
	if not ok:
		fails += 1


func w(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _open_dir(g, need: float) -> Vector2:
	for cand in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if g.los(g.pcenter(), g.pcenter() + cand * need):
			return cand
	return Vector2.RIGHT


func _foe(g, kind: String, p: Vector2):
	var e = g.spawn_enemy(kind, p, -1)
	e.hp = 999.0
	e.max_hp = 999.0
	return e


func _anim(v, e) -> String:
	var a: Dictionary = v.actors.actors.get(0 if e == null else e.get_instance_id(), {})
	if a.is_empty() or a["ap"] == null:
		return ""
	return a["ap"].current_animation


## Each depth's look, one picture apiece:  --autotest --models --tour
func tour() -> void:
	main.slot = 9
	main.use_3d = true
	await w(0.5)
	main.hud._close_modal()
	main.new_game(1)
	await w(2.0)
	var g = main.game
	g.bot = true
	g.bot_manual = true
	g.god = true
	for d in range(1, 8):
		g.load_floor(d)
		await w(2.5)
		g.hud.card_t = 0.0
		g.hud.say_q.clear()
		g.hud.sub_t = 0.0
		# Stand somewhere with a torch or brazier in view, if the floor has one.
		for p in g.props:
			if p["type"] == "brazier":
				g.teleport(p["pos"] + Vector2(0, 30))
				break
		await w(1.5)
		await at.shot("tour_%d" % d)
	print("MODEL PASS")
	get_tree().quit(0)


func run() -> void:
	if OS.get_cmdline_user_args().has("--tour"):
		await tour()
		return
	if OS.get_cmdline_user_args().has("--title"):
		main.use_3d = true
		var keep_nem: Dictionary = main.profile["nemesis"]
		main.profile["nemesis"] = {"kind": "brute", "name": "Vorulch", "rank": 2, "wins": 2}
		main.title_scene(false)
		await get_tree().process_frame
		main.hud.show_title()
		await w(4.0)
		check(main.title3d != null or DisplayServer.get_name() == "headless", "the title stands in a 3D hall")
		if main.title3d != null:
			check(main.title3d.nem != null, "the nemesis waits in the archway")
		main.profile["nemesis"] = keep_nem
		await at.shot("title3d")
		main.new_game(1)
		await w(1.0)
		check(main.title3d == null, "and the hall is gone once the descent begins")
		print("MODEL %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
		get_tree().quit(1 if fails > 0 else 0)
		return
	main.slot = 9
	main.use_3d = true
	await w(0.5)
	main.hud._close_modal()
	main.new_game(1)
	await w(2.5)
	var g = main.game
	var v = g.view3d
	g.bot = true
	g.bot_manual = true
	g.hud.hint_t = 0.0
	g.hud.card_t = 0.0
	g.hud.say_q.clear()
	g.god = true
	check(v.models_on, "the models load")
	for e in g.enemies:
		e.dead = true
		e.visible = false
	for p in g.props:
		if p["type"] == "stairs":
			g.teleport(p["pos"] + Vector2(-30, 20))
	g.surf.clear()
	await w(0.6)
	g.cam_script = true
	g.cam.zoom = Vector2(5.5, 5.5)
	g.cam.position = g.ppos
	await w(0.8)
	check(v.actors.actors.has(0), "Wren is a model")
	check(v.actors.skip.has(g.pspr.get_instance_id()), "and her cut-out is not drawn")
	check(_anim(v, null) == "2H_Melee_Idle", "standing, she idles (%s)" % _anim(v, null))
	await at.shot("md_wren")

	# Keepers asleep, then waking.
	var d: Vector2 = _open_dir(g, 60.0)
	# Out past where it would notice her, then brought close once seen asleep.
	var h = _foe(g, "husk", g.ppos + d * 150.0)
	await w(0.3)
	h.position = g.ppos + d * 36.0
	g.cam.position = g.ppos + d * 18.0
	await get_tree().process_frame
	check(_anim(v, h) == "Skeleton_Inactive_Standing_Pose", "a sleeping keeper slumps (%s)" % _anim(v, h))
	await at.shot("md_asleep")
	h.wake()
	await get_tree().process_frame
	await get_tree().process_frame
	check(_anim(v, h) == "Skeletons_Awaken_Standing", "and stands up when it wakes (%s)" % _anim(v, h))
	await at.shot("md_waking")
	await w(1.5)

	# Wren's strikes.
	h.stun = 99.0
	g.aim = d
	g.atk_cd = 0.0
	g.combo_t = 0.0
	g.do_slash()
	await w(0.08)
	check(_anim(v, null).begins_with("1H_Melee_Attack"), "a strike swings the staff (%s)" % _anim(v, null))
	await at.shot("md_strike")
	await w(0.4)
	h.dead = true
	h.visible = false
	h.die()
	await w(0.5)
	check(v.actors.corpses.size() >= 1, "a foe put out falls where it stood")
	await at.shot("md_fall")
	await w(2.0)

	# A cantor casting and a Bellringer charging.
	var c = _foe(g, "cantor", g.ppos + d * 40.0)
	c.awake = true
	c.cd = 0.0
	c.state = "cast"
	c.st = 9.0
	await w(0.6)
	check(_anim(v, c) == "Spellcasting" or _anim(v, c) == "Spellcast_Raise", "a cantor casts (%s)" % _anim(v, c))
	await at.shot("md_cantor")
	c.dead = true
	c.visible = false
	var b = _foe(g, "brute", g.ppos + d * 50.0)
	b.awake = true
	b.state = "charge"
	b.st = 9.0
	b.dir = -d
	await w(0.15)
	check(_anim(v, b) == "Running_C", "a Bellringer charges (%s)" % _anim(v, b))
	await at.shot("md_brute")
	b.dead = true
	b.visible = false

	# The shapes: an ink maw, a cinder skull, a gloam bat.
	var made: Array = []
	for k in ["slime", "wisp", "moth"]:
		var f = _foe(g, k, g.ppos + d * 30.0 + d.orthogonal() * (made.size() - 1) * 16.0)
		f.awake = true
		f.stun = 99.0
		made.append(f)
	await w(0.5)
	var ok_all := true
	for f in made:
		ok_all = ok_all and v.actors.actors.has(f.get_instance_id()) and v.actors.skip.has(f.spr.get_instance_id())
	check(ok_all, "ink, skulls and bats are shapes in 3D too")
	await at.shot("md_shapes")
	for f in made:
		f.dead = true
		f.visible = false
	await w(0.3)

	# Maren.
	var m = _foe(g, "warden", g.ppos + d * 44.0)
	await w(0.6)
	await at.shot("md_maren")
	m.dead = true
	m.visible = false
	await w(0.5)

	# The camera turned: aiming and moving still answer to the screen.
	v.yaw_to = PI * 0.5
	v.yaw = PI * 0.5
	await w(0.4)
	# A point at chest height, where aim is measured, and back again.
	var q: Vector2 = g.pcenter() + Vector2(20, -12)
	var chest := Vector3(q.x / v.TS, v.LIFT * v.K / v.TS, (q.y + v.LIFT) / v.TS)
	Input.warp_mouse(v.cam.unproject_position(chest))
	await get_tree().process_frame
	var back: Vector2 = v.mouse_world()
	check((back - q).length() < 3.0 or DisplayServer.get_name() == "headless",
		"aim lands under the cursor with the camera turned (%.1f px)" % (back - q).length())
	var up: Vector2 = Vector2(0, -1).rotated(-v.yaw)
	var cam_fwd: Vector3 = -v.cam.global_basis.z
	var fwd := Vector2(cam_fwd.x, cam_fwd.z).normalized()
	check(up.dot(fwd) > 0.95, "W walks away from the camera (%.2f)" % up.dot(fwd))
	await at.shot("md_turned")
	v.zoom_to = 0.6
	await w(0.8)
	check(v.zoom_k < 0.75, "the wheel draws the camera in (%.2f)" % v.zoom_k)
	await at.shot("md_zoomed")
	v.yaw_to = 0.0
	v.zoom_to = 1.0
	await w(0.5)
	# Touch: a drag on the open right side turns; a second finger pinches.
	var pad = load("res://scripts/touch.gd").new()
	pad.hud = g.hud
	pad.game = g
	g.hud.hud_group.add_child(pad)
	await get_tree().process_frame
	g.hud._close_modal()
	var was_bot: bool = g.bot
	g.bot = false
	var r: float = pad.size.x * 0.62
	pad._press(5, Vector2(r, 120))
	for i in 10:
		var dr := InputEventScreenDrag.new()
		dr.index = 5
		dr.position = pad.get_global_transform() * Vector2(r - 10.0 * (i + 1), 120)
		pad._input(dr)
	check(v.yaw_to > 0.6, "a thumb drag turns the camera (%.2f)" % v.yaw_to)
	pad._press(6, Vector2(r - 100.0, 220))
	var d0: float = pad.cam_last.distance_to(pad.pinch_last)
	var pd := InputEventScreenDrag.new()
	pd.index = 6
	pd.position = pad.get_global_transform() * (pad.pinch_last + (pad.pinch_last - pad.cam_last).normalized() * d0)
	pad._input(pd)
	check(v.zoom_to < 0.6, "spreading two fingers draws the camera in (%.2f)" % v.zoom_to)
	pad._release(6)
	pad._release(5)
	check(pad.cam_id == -1 and pad.pinch_id == -1, "and lifting both lets the camera be")
	pad.queue_free()
	g.bot = was_bot
	v.yaw_to = 0.0
	v.zoom_to = 1.0
	print("MODEL %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	main.delete_save(9)
	get_tree().quit(1 if fails > 0 else 0)
