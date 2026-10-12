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


var arena := Vector2.ZERO
var keep_oil := true


func _process(dt: float) -> void:
	super(dt)
	# The lamp stays full so every scene is lit; the reel is about the new things.
	if keep_oil and g != null and is_instance_valid(g) and not g.snuffed:
		g.oil = maxf(g.oil, g.max_oil * 0.8)


## The most open floor near the start: every scene is staged there, in the light.
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


## Clears the stage, puts Wren back in the middle of it, and returns which way
## to set out the next foes.
func _stage() -> Vector2:
	for e in g.enemies:
		if (e.position - arena).length() < 400.0 and e.kind != "warden":
			e.dead = true
			e.visible = false
	g.surf.clear()
	g.oil = g.max_oil
	g.bot_manual = true
	g.bot_mv = Vector2.ZERO
	g.teleport(arena - Vector2(40, 0))
	g.hud.say_q.clear()
	return Vector2.RIGHT


func _hold(at: Vector2, secs: float, zoom: float = 3.7) -> void:
	g.cine(zoom, secs, at)


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
	# No level-up choices in the way of the payoffs.
	g.xp_next = 1 << 30
	g.hud.say_q.clear()
	arena = _find_arena()
	await w(2.0)

	# --- Oil and fire ---
	var d := _stage()
	var pack: Array = []
	for k in 3:
		pack.append(_foe("husk", g.ppos + d * 66.0 + d.orthogonal() * (k - 1) * 12.0))
	for e in pack:
		e.stun = 6.0
	cap("Oil and fire", "X throws the flask. The oil pools where it lands...", 4.0)
	_hold(g.ppos + d * 36.0, 9.0)
	await w(1.2)
	g.throw_flask()
	await w(2.4)
	cap("...and any fire lights it", "An ember bolt across the pool, and everyone in it burns", 5.0)
	_face(pack[1])
	g.do_bolt()
	await w(4.5)
	await brawl(5.0)
	await w(0.5)

	# --- Webs ---
	d = _stage()
	var web: Dictionary = g.surf.add("web", g.ppos + d * 56.0, 15.0)
	var stuck = _foe("husk", web["p"] + d * 2.0, 30.0)
	stuck.stun = 5.0
	cap("Webs", "Cobwebs slow anything caught in them, Wren too. Fire takes them in a flash.", 5.5)
	_hold(g.ppos + d * 32.0, 6.0)
	await w(2.4)
	_face(stuck)
	g.do_bolt()
	await w(3.0)
	await brawl(4.0)

	# --- Oil trips a charge ---
	d = _stage()
	g.surf.spill(g.ppos + d * 40.0, 22.0)
	var br = _foe("brute", g.ppos + d * 86.0, 60.0)
	br.cd = 0.8
	cap("Slick", "A Bellringer charging across oil loses its feet", 5.5)
	_hold(g.ppos + d * 44.0, 6.0)
	var t := 0.0
	while t < 5.0 and br.stun <= 0.0 and not br.dead:
		await get_tree().process_frame
		t += get_process_delta_time()
	await w(2.2)
	await brawl(6.0)

	# --- The snuffed lamp ---
	d = _stage()
	var pair: Array = [_foe("husk", g.ppos + d * 80.0), _foe("husk", g.ppos + d * 86.0 + d.orthogonal() * 14.0)]
	pair[0].stun = 1.0
	pair[1].stun = 1.0
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
	g.combo_t = 0.0
	g.do_slash()
	_hold(g.ppos, 2.0, 3.9)
	await w(2.0)
	cap("The flare", "Uncover the lamp after a moment and it flares: everything near is dazzled", 5.0)
	# Both close by for it.
	for k in pair.size():
		var e = pair[k]
		if is_instance_valid(e) and not e.dead:
			e.position = g.ppos + d.rotated(0.6 * (k * 2 - 1)) * 34.0
			e.hp = maxf(e.hp, 30.0)
	g.snuff_t = maxf(g.snuff_t, 1.0)
	g.flare_cd = 0.0
	await w(0.6)
	_hold(g.ppos, 3.0, 3.6)
	g.relight()
	await w(3.0)
	await brawl(5.0)

	# --- The echo ---
	d = _stage()
	var duo: Array = [_foe("husk", g.ppos + d * 24.0, 70.0), _foe("husk", g.ppos + d * 26.0 + d.orthogonal() * 12.0, 70.0)]
	for e in duo:
		e.stun = 3.0
	cap("Wren's echo", "Dash after a fight and the last two seconds play again, where they happened", 7.0)
	_hold(g.ppos + d * 4.0, 7.5, 3.6)
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
	await brawl(4.0)

	# --- The nemesis ---
	d = _stage()
	pr["nemesis"] = {"kind": "brute", "name": "Grisk", "rank": 2, "wins": 2}
	cap("A nemesis", "The first foe to put Wren out is given a name. It keeps a scrap of her cloak, and waits.", 6.5)
	var nem = g.spawn_enemy("brute", g.ppos + d * 80.0, -1)
	nem.make_nemesis(pr["nemesis"])
	_hold(nem.position + Vector2(0, -10), 5.5, 3.8)
	await w(1.5)
	g.hud.say_q.clear()
	nem.wake()
	nem.stun = 3.5
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
			nem.hurt(14.0, Vector2.ZERO)
	g.bot_manual = true
	g.bot_mv = Vector2.ZERO
	_hold(g.ppos, 4.5, 3.6)
	await w(5.0)

	cap("New deeds", "Grudge Settled, Oil and Ember, Out of the Dark, Twice Over", 3.5)
	await w(0.6)
	main.hud.show_deeds()
	await w(4.0)
	main.hud._close_modal()
	main.hud.show_title()
	cap("LANTERNFALL", "F3 switches between the 3D and the flat view, any time", 4.0)
	await w(4.5)
	pr["nemesis"] = {}
	main.delete_save(9)
	get_tree().quit()
