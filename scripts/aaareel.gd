extends "res://scripts/wildreel.gd"
## A short trailer of the full 3D look, for the Forward+ renderer:
##   godot --path . --rendering-method forward_plus --write-movie t.avi --fixed-fps 30 -- --autotest --aaareel


func run() -> void:
	main.slot = 9
	main.delete_save(9)
	main.profile["nemesis"] = {}
	main.use_3d = true
	keep_oil = true
	await w(0.5)
	main.hud.show_title()
	cap("LANTERNFALL", "The 3D build: rigged figures, a modular dungeon, Forward+ lighting", 4.0)
	await w(5.0)
	main.hud._close_modal()
	main.new_game(1)
	await w(0.5)
	_setup_game()
	g.xp_next = 1 << 30
	g.hud.say_q.clear()
	arena = _find_arena()
	await w(1.5)

	# Round Wren, slowly, in the torchlight.
	var d := _stage()
	var v = g.view3d
	cap("Depth I", "Torchlit stone, haze in the air, every lamp throwing shadows", 5.0)
	var t0 := 0.0
	while t0 < 5.0:
		v.yaw_to = t0 / 5.0 * PI * 0.9
		v.zoom_to = 1.0 - 0.3 * sin(t0 / 5.0 * PI)
		await get_tree().process_frame
		t0 += get_process_delta_time()
	v.yaw_to = PI * 0.9
	v.zoom_to = 1.0

	# A fight.
	cap("Keepers", "They slump asleep, stand when they wake, and fall apart when put out", 7.0)
	var pack: Array = []
	for k in 3:
		var f = _foe("husk", g.ppos + d.rotated(-0.5 + k * 0.5) * 40.0, 20.0)
		pack.append(f)
	await brawl(7.0)
	v.yaw = 0.0
	v.yaw_to = 0.0

	# Oil and fire.
	d = _stage()
	var trio: Array = []
	for k in 3:
		trio.append(_foe("husk", g.ppos + d * 62.0 + d.orthogonal() * (k - 1) * 12.0, 40.0))
	for e in trio:
		e.stun = 6.0
	cap("Oil and fire", "Throw the flask, light it with a bolt", 6.0)
	_hold(g.ppos + d * 32.0, 7.0)
	await w(0.6)
	g.throw_flask()
	await w(1.6)
	_face(trio[1])
	g.do_bolt()
	await w(3.5)
	await brawl(4.0)

	# The snuffed lamp, and the flare.
	d = _stage()
	var pair: Array = [_foe("husk", g.ppos + d * 36.0), _foe("husk", g.ppos + d * 34.0 + d.orthogonal() * 16.0)]
	for e in pair:
		e.stun = 2.5
	cap("The dark", "Snuff the lamp to hide; relight it and it flares", 6.0)
	await w(0.8)
	g.snuff()
	await w(2.2)
	g.snuff_t = 1.0
	g.flare_cd = 0.0
	_hold(g.ppos, 2.5, 3.6)
	g.relight()
	await w(2.5)
	await brawl(4.0)

	# Every depth its own air.
	cap("Seven depths", "Each with its own stone, haze and fire", 15.0)
	for dep in range(2, 8):
		g.load_floor(dep)
		await w(0.4)
		g.hud.card_t = 0.0
		g.hud.say_q.clear()
		g.hud.sub_t = 0.0
		for p in g.props:
			if p["type"] == "brazier":
				g.teleport(p["pos"] + Vector2(0, 30))
				break
		await w(2.0)

	# Maren, waiting at the bottom of the Heartforge.
	if g.boss != null and is_instance_valid(g.boss):
		g.teleport(g.boss.position + Vector2(0, 118))
		_hold(g.boss.position + Vector2(0, -8), 5.0, 3.3)
	cap("The Hollow Warden", "Maren, waiting at the bottom of the world", 4.5)
	await w(5.0)
	main.hud.show_title()
	cap("LANTERNFALL", "F3 switches between 3D and the flat view, any time", 4.0)
	await w(4.5)
	main.delete_save(9)
	get_tree().quit()
