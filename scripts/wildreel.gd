extends "res://scripts/showreel.gd"
## A recorded tour of oil and fire, the snuffed lamp, Wren's echo and the
## nemesis, in the 3D build. Run with Godot's movie maker:
##   godot --path . --write-movie reel.avi --fixed-fps 30 -- --autotest --wildreel


func _foe(kind: String, at: Vector2, hp: float = 40.0):
	var e = g.spawn_enemy(kind, at, -1)
	e.hp = hp
	e.max_hp = hp
	e.awake = true
	return e


func _alive(list: Array) -> bool:
	for e in list:
		if is_instance_valid(e) and not e.dead:
			return true
	return false


func _face(e) -> void:
	if is_instance_valid(e):
		g.aim = (e.center() - g.pcenter()).normalized()


## Somewhere roomy to stage the next scene: the start room is cleared and Wren
## stands where the longest clear line runs.
func _stage() -> Vector2:
	for e in g.enemies:
		if (e.position - g.ppos).length() < 260.0 and e.kind != "warden":
			e.dead = true
			e.visible = false
	g.surf.clear()
	g.oil = g.max_oil
	return _clear_dir(110.0)


func run() -> void:
	main.slot = 9
	main.delete_save(9)
	var pr: Dictionary = main.profile
	pr["embers"] = 120
	pr["nemesis"] = {}
	main.use_3d = true
	await w(1.0)
	main.hud.show_title()
	cap("LANTERNFALL", "What is new: oil and fire, the dark, Wren's echo, and a grudge")
	await w(3.5)
	main.hud._close_modal()
	main.new_game(1)
	await w(0.5)
	_setup_game()
	g.hud.say_q.clear()
	await w(3.0)

	# --- Oil and fire ---
	var d := _stage()
	var pack: Array = []
	for k in 3:
		pack.append(_foe("husk", g.ppos + d * 78.0 + d.orthogonal() * (k - 1) * 13.0))
	for e in pack:
		e.stun = 0.6
	cap("Oil and fire", "X throws the flask. The oil pools where it lands...", 5.5)
	await w(0.4)
	g.throw_flask()
	await w(1.4)
	cap("...and any fire lights it", "An ember bolt across the pool, and everyone in it burns", 5.0)
	g.oil = g.max_oil
	_face(pack[1])
	g.do_bolt()
	await w(3.5)
	await brawl(8.0)
	await w(1.0)

	# --- Webs ---
	d = _stage()
	var web: Dictionary = g.surf.add("web", g.ppos + d * 52.0, 13.0)
	var stuck = _foe("husk", web["p"] + d * 4.0, 30.0)
	cap("Webs", "Cobwebs in the corners slow anything caught in them, Wren too. Fire takes them in a flash.", 6.0)
	await w(2.2)
	_face(stuck)
	g.do_bolt()
	await w(2.5)
	await brawl(6.0)

	# --- Oil trips a charge ---
	d = _stage()
	g.surf.spill(g.ppos + d * 46.0, 22.0)
	var br = _foe("brute", g.ppos + d * 100.0, 60.0)
	br.cd = 0.4
	cap("Slick", "A Bellringer charging across oil loses its feet", 5.0)
	var t := 0.0
	while t < 5.0 and br.stun <= 0.0 and not br.dead:
		await get_tree().process_frame
		t += get_process_delta_time()
	await w(1.6)
	await brawl(10.0)

	# --- The snuffed lamp ---
	d = _stage()
	var pair: Array = [_foe("husk", g.ppos + d * 105.0), _foe("husk", g.ppos + d * 112.0 + d.orthogonal() * 12.0)]
	pair[0].stun = 0.8
	pair[1].stun = 0.8
	cap("Snuff the lamp", "C covers it. Foes that cannot see her lose her, and go looking where she was.", 6.5)
	await w(1.2)
	g.snuff()
	# Slip aside in the dark.
	var side: Vector2 = d.orthogonal()
	if not g.los(g.pcenter(), g.pcenter() + side * 40.0):
		side = -side
	g.bot_mv = side
	await w(0.7)
	g.bot_mv = Vector2.ZERO
	await w(3.2)
	cap("Out of the dark", "Only their eyes and footsteps give them away. A blow from the dark lands twice as hard.", 6.0)
	var mark = pair[0] if pair[0].lost else pair[1]
	t = 0.0
	while t < 4.0 and is_instance_valid(mark) and not mark.dead and (mark.center() - g.pcenter()).length() > 24.0:
		g.bot_mv = (mark.position - g.ppos).normalized()
		_face(mark)
		await get_tree().process_frame
		t += get_process_delta_time()
	g.bot_mv = Vector2.ZERO
	_face(mark)
	g.atk_cd = 0.0
	g.do_slash()
	await w(1.6)
	cap("The flare", "Uncover the lamp after a moment and it flares: everything near is dazzled", 5.0)
	g.snuff_t = maxf(g.snuff_t, 1.0)
	g.flare_cd = 0.0
	g.relight()
	await w(2.5)
	await brawl(8.0)

	# --- The echo ---
	d = _stage()
	var duo: Array = [_foe("husk", g.ppos + d * 24.0, 70.0), _foe("husk", g.ppos + d * 26.0 + d.orthogonal() * 12.0, 70.0)]
	for e in duo:
		e.stun = 3.0
	cap("Wren's echo", "Dash after a fight and the last two seconds play again, where they happened", 7.0)
	g.echo_cd = 0.0
	for k in 3:
		_face(duo[0])
		g.atk_cd = 0.0
		g.do_slash()
		await w(0.32)
	g.last_mv = -d
	g.dash_stock = g.stats["dash_n"]
	g.try_dash()
	await w(2.6)
	for e in duo:
		if is_instance_valid(e) and not e.dead:
			e.stun = 2.0
	g.echo_cd = 0.0
	g.bot_mv = d
	await w(0.35)
	g.bot_mv = Vector2.ZERO
	for k in 3:
		_face(duo[1])
		g.atk_cd = 0.0
		g.do_slash()
		await w(0.32)
	g.last_mv = -d
	g.dash_stock = g.stats["dash_n"]
	g.try_dash()
	await w(2.6)
	await brawl(6.0)

	# --- The nemesis ---
	d = _stage()
	pr["nemesis"] = {"kind": "brute", "name": "Grisk", "rank": 2, "wins": 2}
	cap("A nemesis", "The first foe to put Wren out is given a name. It keeps a scrap of her cloak, and waits.", 6.5)
	var nem = g.spawn_enemy("brute", g.ppos + d * 92.0, -1)
	nem.make_nemesis(pr["nemesis"])
	await w(1.5)
	g.hud.say_q.clear()
	nem.wake()
	await w(4.5)
	cap("Settle it", "It grows each time it wins. Oil and an ember bolt help.", 6.0)
	g.oil = g.max_oil
	g.throw_flask()
	await w(1.2)
	g.oil = g.max_oil
	_face(nem)
	g.do_bolt()
	t = 0.0
	g.bot_manual = false
	while t < 30.0 and is_instance_valid(nem) and not nem.dead:
		await w(0.25)
		t += 0.25
		if t > 6.0 and is_instance_valid(nem) and not nem.dead:
			# Keep the reel moving: the fight is shown, not played out in full.
			nem.hurt(9.0, Vector2.ZERO)
	g.bot_manual = true
	g.bot_mv = Vector2.ZERO
	await w(4.5)

	main.hud.show_deeds()
	cap("New deeds", "Grudge Settled, Oil and Ember, Out of the Dark, Twice Over", 4.0)
	await w(4.5)
	main.hud._close_modal()
	main.hud.show_title()
	cap("LANTERNFALL", "F3 switches between the 3D and the flat view, any time", 4.0)
	await w(4.5)
	pr["nemesis"] = {}
	main.delete_save(9)
	get_tree().quit()
