extends Node
## A recorded tour of depth 1 that shows each feature in turn, with captions.
## Run with Godot's movie maker so every frame is kept however slow the
## machine renders:
##   godot --path . --write-movie reel.avi --fixed-fps 30 -- --autotest --showreel
## Wren walks the real map (by the shortest path over the tiles), fights with
## the game's own bot, and a few scripted moments stage the rest: a parry, a
## struck-back hex, a kindling that combines, the lamp running low, a fall and
## the waking after it, and the way down.

const Story = preload("res://scripts/story.gd")

var main
var g
var cap_layer: CanvasLayer
var cap_box: PanelContainer
var cap_title: Label
var cap_sub: Label
## While on, Wren cannot drop below a few hearts (off for the staged fall).
var guard := true
## Level-ups that happen on their own are shown for a moment, then the first
## kindling is taken; off while a choice is being staged.
var auto_pick := true
var choice_t := 0.0


func _ready() -> void:
	_build_caption()
	run()


func w(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _process(dt: float) -> void:
	if guard and g != null and is_instance_valid(g) and not g.dead:
		g.hp = maxi(g.hp, 5)
	if auto_pick and main.hud.modal == "choice":
		choice_t += dt
		if choice_t > 1.6:
			choice_t = 0.0
			main.hud._choose(0)
	else:
		choice_t = 0.0


# --- Captions ------------------------------------------------------------------

func _build_caption() -> void:
	cap_layer = CanvasLayer.new()
	cap_layer.layer = 30
	add_child(cap_layer)
	cap_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.02, 0.05, 0.82)
	sb.border_color = Color(1.0, 0.72, 0.35, 0.9)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(12)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	cap_box.add_theme_stylebox_override("panel", sb)
	# A lower-left panel: clear of the title, the death screen's heading, the
	# kindling plaques and the hotbar.
	cap_box.anchor_top = 1.0
	cap_box.anchor_bottom = 1.0
	cap_box.offset_left = 18
	cap_box.offset_bottom = -22
	cap_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	cap_box.modulate.a = 0.0
	cap_layer.add_child(cap_box)
	var vb := VBoxContainer.new()
	cap_box.add_child(vb)
	cap_title = Label.new()
	cap_title.add_theme_font_size_override("font_size", 28)
	cap_title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.35))
	vb.add_child(cap_title)
	cap_sub = Label.new()
	cap_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap_sub.custom_minimum_size = Vector2(360, 0)
	cap_sub.add_theme_font_size_override("font_size", 17)
	cap_sub.add_theme_color_override("font_color", Color(0.93, 0.87, 0.72))
	vb.add_child(cap_sub)


## A chapter title across the top of the picture; it fades out by itself.
func cap(title: String, sub: String = "", secs: float = 4.5) -> void:
	print("REEL %s  |  depth %d dead %s" % [title, g.depth if g != null and is_instance_valid(g) else 0, g.dead if g != null and is_instance_valid(g) else false])
	var f: Font = main.hud.font_b
	cap_title.add_theme_font_override("font", main.hud.font_t)
	cap_sub.add_theme_font_override("font", f)
	cap_title.text = title
	cap_sub.text = sub
	cap_sub.visible = sub != ""
	cap_box.reset_size()
	cap_box.offset_top = cap_box.offset_bottom - cap_box.get_combined_minimum_size().y
	cap_box.offset_right = cap_box.offset_left + 400
	var tw := cap_box.create_tween()
	tw.tween_property(cap_box, "modulate:a", 1.0, 0.3)
	tw.tween_interval(secs)
	tw.tween_property(cap_box, "modulate:a", 0.0, 0.5)


# --- Getting about -------------------------------------------------------------

## Distance in steps from every floor tile to the target tile.
func _steps_to(target: Vector2) -> PackedInt32Array:
	var W: int = g.W
	var H: int = g.H
	var d := PackedInt32Array()
	d.resize(W * H)
	d.fill(99999)
	var t := Vector2i(int(target.x / 16.0), int(target.y / 16.0))
	var q: Array = [t]
	d[t.y * W + t.x] = 0
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H:
				continue
			var i := n.y * W + n.x
			if g.tiles[i] == 1 and d[i] > d[c.y * W + c.x] + 1:
				d[i] = d[c.y * W + c.x] + 1
				q.append(n)
	return d


func _nearest_foe(r: float):
	var best = null
	var bd := r
	for e in g.enemies:
		if e.dead or e.kind == "warden":
			continue
		var dd: float = (e.position - g.ppos).length()
		if dd < bd and g.los(g.pcenter(), e.center()):
			bd = dd
			best = e
	return best


## Walks Wren to a point by the shortest way over the floor, stopping to fight
## whatever comes close.
func walk_to(target: Vector2, limit: float = 25.0, fight: bool = true) -> void:
	var d := _steps_to(target)
	var W: int = g.W
	var t := 0.0
	while t < limit and is_instance_valid(g) and not g.dead:
		if (g.ppos - target).length() < 9.0:
			break
		if fight and _nearest_foe(70.0) != null:
			g.bot_manual = false
			await w(0.2)
			t += 0.2
			continue
		g.bot_manual = true
		g.bot_atk = false
		g.bot_bolt = false
		var c := Vector2i(int(g.ppos.x / 16.0), int(g.ppos.y / 16.0))
		var best := c
		var bv: int = d[c.y * W + c.x]
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if d[n.y * W + n.x] < bv:
				bv = d[n.y * W + n.x]
				best = n
		var goal: Vector2 = target if best == c else g.tile_center(best)
		var dir: Vector2 = (goal - g.ppos).normalized()
		g.bot_mv = dir
		g.aim = dir
		await get_tree().process_frame
		t += get_process_delta_time()
	g.bot_mv = Vector2.ZERO


## Lets the bot fight until nothing is left near, or time runs out.
func brawl(limit: float) -> void:
	var t := 0.0
	g.bot_manual = false
	while t < limit and _nearest_foe(160.0) != null:
		await w(0.25)
		t += 0.25
	g.bot_manual = true
	g.bot_mv = Vector2.ZERO


func _clear_dir(reach: float) -> Vector2:
	for cand in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if g.los(g.pcenter(), g.pcenter() + cand * reach):
			return cand
	return Vector2.RIGHT


func _prop(type: String) -> Dictionary:
	for p in g.props:
		if p["type"] == type:
			return p
	return {}


func _setup_game() -> void:
	g = main.game
	g.bot = true
	g.bot_manual = true
	g.hud.hint_t = 0.0
	# The tour shows the bolts on its own terms; the bot keeps to the staff.
	g.bot_allow["bolt"] = false


# --- The tour ------------------------------------------------------------------

func run() -> void:
	main.slot = 9
	main.delete_save(9)
	var pr: Dictionary = main.profile
	pr["embers"] = 220
	pr["town"] = []
	pr["tally"] = {"deaths": 2}
	pr["feats"] = []
	pr["best"] = {}
	pr["resolve"] = false
	main.use_3d = true
	await w(1.0)
	main.hud.show_title()
	await w(0.5)
	cap("LANTERNFALL", "A tour of depth I in the 3D build, showing what is new")
	await w(4.0)

	# The town above.
	main.hud.show_town()
	cap("The town above", "Embers carried home light its lamps; each helps every descent after")
	await w(3.0)
	for id in ["tinker", "smith", "watch"]:
		main.light_town_lamp(id)
		main.hud.show_town()
		Sfx.play("whoomp", -4.0)
		await w(1.0)
	await w(1.5)
	main.hud.show_deeds()
	cap("Deeds", "Milestones across every descent, each paid in embers")
	await w(3.5)

	# Down into the cellars.
	main.hud._close_modal()
	main.new_game(1)
	await w(0.5)
	_setup_game()
	cap("Depth I in 3D", "Real walls and light; Wren's lantern throws shadows. Walls in the way dissolve.", 5.0)
	await w(5.5)

	# Into the first fight.
	var foe = null
	for e in g.enemies:
		if not e.dead and (foe == null or (e.position - g.ppos).length() < (foe.position - g.ppos).length()):
			foe = e
	if foe != null:
		cap("Fights that land", "Impact bursts, squash and stretch; the fallen break into their own embers")
		await walk_to(foe.position, 14.0)
		await brawl(10.0)
	await w(1.0)

	# Parry.
	cap("Parry", "Strike a foe as it lunges: it staggers and Wren is spared")
	g.bot_manual = true
	var dir := _clear_dir(70.0)
	var h = g.spawn_enemy("husk", g.ppos + dir * 34.0, 0)
	h.awake = true
	h.hp = 999.0
	for k in 2:
		var t := 0.0
		while t < 4.0 and not (h.state == "wind" and h.st < 0.1):
			g.aim = (h.center() - g.pcenter()).normalized()
			await get_tree().process_frame
			t += get_process_delta_time()
		g.atk_cd = 0.0
		g.aim = (h.center() - g.pcenter()).normalized()
		g.do_slash()
		await w(1.6)
	h.hp = 1.0
	g.atk_cd = 0.0
	g.do_slash()
	await w(1.2)

	# Struck-back hexes.
	cap("Struck-back hexes", "Swing at a hex as it reaches you and it flies back at whoever cast it")
	dir = _clear_dir(110.0)
	var c = g.spawn_enemy("cantor", g.ppos + dir * 90.0, 0)
	c.awake = true
	c.hp = 40.0
	c.cd = 0.3
	var sent := 0
	var tt := 0.0
	while sent < 2 and tt < 9.0:
		for s in g.shots:
			if not s["friendly"] and (s["pos"] - g.pcenter()).length() < 24.0:
				g.aim = (s["pos"] - g.pcenter()).normalized()
				g.atk_cd = 0.0
				g.do_slash()
				sent += 1
				break
		await get_tree().process_frame
		tt += get_process_delta_time()
	await w(1.5)
	if not c.dead:
		c.hurt(999.0, Vector2.ZERO)
	await w(1.0)

	# Both views.
	cap("Two views, one game", "F3 switches to the classic flat view and back, mid-fight")
	await w(1.5)
	main.use_3d = false
	g.view3d.set_active(false)
	await w(3.5)
	main.use_3d = true
	g.view3d.set_active(true)
	await w(1.5)

	# A kindling that combines.
	auto_pick = false
	g.apply_boon("burn")
	g.apply_boon("trail")
	cap("Kindlings that combine", "Hold Afterburn and Cinder Trail, and Wildfire can be offered")
	for k in 40:
		g._offer_boons("The warmth below reaches up to you", "Level %d  -  choose a kindling" % g.level)
		var at := -1
		var plaques: Array = main.hud.modal_root.find_children("*", "Label", true, false)
		for i in plaques.size():
			if (plaques[i] as Label).text == "Wildfire":
				at = i
		if at >= 0:
			break
		main.hud._close_modal()
	await w(3.5)
	var pick := 0
	# Find which plaque is Wildfire by the order the options were laid out.
	var row: Array = main.hud.modal_root.find_children("*", "Button", true, false)
	for i in row.size():
		for l in (row[i] as Button).find_children("*", "Label", true, false):
			if (l as Label).text == "Wildfire":
				pick = i
	main.hud._choose(pick)
	auto_pick = true
	await w(1.0)

	# The lamp running low.
	cap("The lamp burns on your oil", "Ember bolts spend it, and the light shrinks with it")
	g.bot_allow["bolt"] = true
	var regen: float = g.stats["oil_regen"]
	g.stats["oil_regen"] = 0.0
	var lamp := _prop("lamp")
	if not lamp.is_empty():
		await walk_to(lamp["pos"] + Vector2(0, 40), 20.0)
	g.bot_manual = true
	for k in 6:
		g.aim = Vector2.from_angle(k * 1.1)
		g.bolt_cd = 0.0
		if g.oil >= g.bolt_cost():
			g.do_bolt()
		await w(0.35)
	g.oil = minf(g.oil, 8.0)
	g.gloam_t = 0.5
	cap("Gloams", "Below a fifth of a flask, shades come out of the dark after her")
	await w(5.0)
	g.bot_manual = false
	await w(3.0)
	g.bot_manual = true
	if not lamp.is_empty():
		cap("A wayside lamp", "Light it: the flask fills, the light returns, and the gloams come apart")
		await walk_to(lamp["pos"] + Vector2(0, 10), 8.0, false)
		g.interact()
		await w(4.5)
	else:
		g.oil = g.max_oil
		await w(2.0)
	g.stats["oil_regen"] = regen
	g.bot_allow["bolt"] = false

	# Out of sight, not out of mind.
	cap("No blow from nowhere", "A foe winding up out of sight is marked at the edge of the screen")
	var br = g.spawn_enemy("brute", g.ppos + Vector2(0, -170), 0)
	br.awake = true
	br.state = "wind"
	br.st = 4.0
	await w(3.5)
	br.dead = true
	br.visible = false

	# A fall, and what it teaches.
	cap("Fair deaths", "No single blow takes more than a heart; the death screen says what did it")
	guard = false
	dir = _clear_dir(80.0)
	var b2 = g.spawn_enemy("brute", g.ppos + dir * 60.0, 0)
	b2.awake = true
	b2.cd = 0.0
	g.hp = 2
	g.invuln = 0.0
	g.bot_manual = true
	var tw := 0.0
	while not g.dead and tw < 8.0:
		g.invuln = minf(g.invuln, 0.0)
		await get_tree().process_frame
		tw += get_process_delta_time()
	if not g.dead:
		g.hurt_player(2, b2.position, 200.0, b2)
	await w(5.5)
	cap("Nothing earned is lost", "Every foe's embers are already kept; after a few falls, the lamp's resolve is offered")
	await w(4.5)
	main.retry()
	await w(1.5)
	_setup_game()
	guard = true
	cap("Wren remembers", "On waking she says what put her out")
	await w(5.0)

	# The way down.
	cap("The way down", "Clear the stair's guards and descend")
	var stairs := _prop("stairs")
	for round in 6:
		if not g.sealed:
			break
		var guard_foe = null
		for e in g.enemies:
			if not e.dead and e.room == g.exit_room:
				guard_foe = e
				break
		if guard_foe == null:
			break
		await walk_to(guard_foe.position, 15.0)
		await brawl(8.0)
	for e in g.enemies:
		if not e.dead and e.room == g.exit_room:
			e.hurt(99999.0, Vector2.ZERO)
	await w(0.5)
	if not stairs.is_empty():
		await walk_to(stairs["pos"], 25.0)
		g.teleport(stairs["pos"])
		await w(0.4)
		print("REEL at the stairs: sealed %s, near %s, modal '%s'" % [g.sealed, g.near_prop == stairs, main.hud.modal])
		g.interact()
	await w(5.5)
	cap("Depth I, done", "%d embers waiting in the town above" % int(pr["embers"]), 5.0)
	await w(5.5)
	main.delete_save(9)
	get_tree().quit()
