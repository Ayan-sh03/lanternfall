extends Node2D
## What lies on the floor and changes the fight: lamp oil thrown from the
## flask, the fire it turns into, cobwebs in the corners, and standing water.
## Fire spreads into oil and webs it touches, burns whoever stands in it (Wren
## too), and goes out on whatever walks through water. Webs slow everyone;
## oil trips anything that charges across it.

const Art = preload("res://scripts/art.gd")
const TS := 16

const OIL_COL := Color(0.1, 0.065, 0.025, 0.8)
const SHEEN_COL := Color(0.55, 0.42, 0.2, 0.35)
const WATER_COL := Color(0.12, 0.22, 0.34, 0.55)
const WATER_HI := Color(0.45, 0.62, 0.8, 0.35)
const WEB_COL := Color(0.78, 0.78, 0.84, 0.55)
const FIRE_COL := Color(1.0, 0.42, 0.1, 0.35)
const MAX_LIGHTS := 6

var g
## Each surface: {"k": "oil"|"fire"|"web"|"water", "p": Vector2, "r": float,
## "t": seconds left (fire only), "seed": int for its ragged shape,
## "ign": seconds until a touched oil or web catches (-1 when not catching),
## "was": what a fire was before it caught}.
var list: Array = []
## Flasks in the air: {"a": from, "b": to, "t": 0..1, "dur": seconds, "node": Node2D, "body": Sprite2D}
var flasks: Array = []
var glow_node: Node2D
var acc := 0.0
var version := 0


func _ready() -> void:
	z_index = -9
	glow_node = Node2D.new()
	glow_node.material = Art.mat_add
	glow_node.draw.connect(_draw_glow)
	add_child(glow_node)


func clear() -> void:
	for s in list:
		_drop_light(s)
	list.clear()
	for f in flasks:
		f["node"].queue_free()
	flasks.clear()
	version += 1
	queue_redraw()
	glow_node.queue_redraw()


# --- Making them ----------------------------------------------------------------

## Webs in the corners and water in the open, grown from the floor's seed so
## a reloaded floor gets them back in the same places.
func grow(seed_v: int) -> void:
	clear()
	if g.depth <= 0:
		return
	var r := RandomNumberGenerator.new()
	r.seed = seed_v ^ 0x51ED
	var corners: Array = []
	var open: Array = []
	var start: Vector2i = g.dungeon["start"]
	for y in range(1, g.H - 1):
		for x in range(1, g.W - 1):
			if g.tiles[y * g.W + x] != 1:
				continue
			if absi(x - start.x) + absi(y - start.y) < 6 or Vector2i(x, y) == g.stairs_tile:
				continue
			var n := 0
			var walls := 0
			for d in g.DIRS:
				if g.tiles[(y + d.y) * g.W + x + d.x] == 1:
					n += 1
				else:
					walls += 1
			var corner: bool = walls == 2 and (g.tiles[y * g.W + x - 1] != 1) != (g.tiles[y * g.W + x + 1] != 1)
			if corner:
				corners.append(Vector2i(x, y))
			elif n == 4 and _all_open(x, y, 2):
				open.append(Vector2i(x, y))
	_scatter(r, corners, "web", 5 + g.depth, 9.0, 13.0, true)
	_scatter(r, open, "water", 2 + (g.depth % 3), 13.0, 21.0, false)


func _all_open(x: int, y: int, rad: int) -> bool:
	for yy in range(y - rad, y + rad + 1):
		for xx in range(x - rad, x + rad + 1):
			if xx < 0 or yy < 0 or xx >= g.W or yy >= g.H or g.tiles[yy * g.W + xx] != 1:
				return false
	return true


func _scatter(r: RandomNumberGenerator, pool: Array, k: String, n: int, r0: float, r1: float, tuck: bool) -> void:
	for i in n:
		if pool.is_empty():
			return
		var t: Vector2i = pool[r.randi() % pool.size()]
		var p: Vector2 = g.tile_center(t)
		if tuck:
			# Pushed into the corner it hangs in.
			for d in g.DIRS:
				if g.tiles[(t.y + d.y) * g.W + t.x + d.x] != 1:
					p += Vector2(d) * 5.0
		var near := false
		for s in list:
			if (s["p"] - p).length() < s["r"] + r1 + 6.0:
				near = true
				break
		if near:
			continue
		add(k, p, r.randf_range(r0, r1), r.randi())


func add(k: String, p: Vector2, r: float, seed_v: int = -1) -> Dictionary:
	var s := {"k": k, "p": p, "r": r, "t": 0.0, "seed": seed_v if seed_v >= 0 else randi(), "ign": -1.0, "was": k}
	list.append(s)
	version += 1
	queue_redraw()
	return s


## Oil poured at p: it pools with any oil already there, floats out across
## water, and catches at once if it lands in fire.
func spill(p: Vector2, r: float) -> void:
	var into_fire := false
	for s in list:
		var d: float = (s["p"] - p).length()
		if s["k"] == "fire" and d < s["r"] + r * 0.6:
			into_fire = true
		elif s["k"] == "water" and d < s["r"]:
			r *= 1.4
	for s in list:
		if s["k"] == "oil" and (s["p"] - p).length() < s["r"] * 0.7:
			s["r"] = minf(34.0, maxf(s["r"], r) + 5.0)
			s["p"] = s["p"].lerp(p, 0.3)
			version += 1
			queue_redraw()
			if into_fire:
				ignite(s)
			return
	var o := add("oil", p, r)
	if into_fire:
		ignite(o)


func throw_flask(from: Vector2, to: Vector2) -> void:
	var node := Node2D.new()
	node.position = from
	var body := Sprite2D.new()
	body.texture = Art.tex["oil"]
	body.scale = Vector2(0.8, 0.8)
	node.add_child(body)
	var gl := Sprite2D.new()
	gl.texture = Art.tex["glow"]
	gl.material = Art.mat_add
	gl.modulate = Color(1.0, 0.6, 0.2, 0.35)
	gl.scale = Vector2(0.18, 0.18)
	body.add_child(gl)
	g.over.add_child(node)
	var dur := 0.22 + (to - from).length() / 420.0
	flasks.append({"a": from, "b": to, "t": 0.0, "dur": dur, "node": node, "body": body})


# --- Fire ---------------------------------------------------------------------------

func ignite(s: Dictionary) -> void:
	if s["k"] != "oil" and s["k"] != "web":
		return
	s["was"] = s["k"]
	s["k"] = "fire"
	s["ign"] = -1.0
	# Oil burns long and hot; a web goes up in a flash.
	s["t"] = 4.5 if s["was"] == "oil" else 1.3
	if s["was"] == "web":
		s["r"] *= 1.15
	version += 1
	queue_redraw()
	glow_node.queue_redraw()
	g.fx.spark(s["p"], Color(1.0, 0.6, 0.2), 14, 70.0, 0.5, 2.0, -40.0)
	g.fx.ring(s["p"], 4.0, s["r"] + 6.0, 0.25, Color(1.0, 0.6, 0.2), false, 3.0)
	Sfx.play("whoomp", -6.0 if s["was"] == "oil" else -12.0, 0.15)
	if s["was"] == "oil":
		g.add_shake(2.5)
		g.main.tally("ignites")
	var l := PointLight2D.new()
	l.texture = Art.tex["light"]
	l.color = Color(1.0, 0.55, 0.22)
	l.energy = 1.1
	l.texture_scale = 1.0 + s["r"] / 22.0
	l.position = s["p"] + Vector2(0, -4)
	g.over.add_child(l)
	s["light"] = l
	# Too many lit at once and the renderer drops some; the oldest give way.
	var lit: Array = []
	for o in list:
		if o.has("light"):
			lit.append(o)
	while lit.size() > MAX_LIGHTS:
		_drop_light(lit.pop_front())


func _drop_light(s: Dictionary) -> void:
	if s.has("light"):
		if is_instance_valid(s["light"]):
			s["light"].queue_free()
		s.erase("light")


## Anything that burns catches from a flame of radius r at p.
func ignite_at(p: Vector2, r: float) -> bool:
	var any := false
	for s in list:
		if (s["k"] == "oil" or s["k"] == "web") and (s["p"] - p).length() < s["r"] + r:
			ignite(s)
			any = true
	return any


func burning_at(p: Vector2, pad: float = 0.0) -> bool:
	for s in list:
		if s["k"] == "fire" and (s["p"] - p).length() < s["r"] + pad:
			return true
	return false


## What kind of ground is underfoot at p ("" for bare stone). Fire wins over
## oil, oil over web, web over water.
func under(p: Vector2) -> String:
	var best := ""
	var rank := {"": 0, "water": 1, "web": 2, "oil": 3, "fire": 4}
	for s in list:
		if (s["p"] - p).length() < s["r"] and rank[s["k"]] > rank[best]:
			best = s["k"]
	return best


# --- Each frame ------------------------------------------------------------------------

func tick(dt: float) -> void:
	_fly(dt)
	if list.is_empty():
		return
	acc += dt
	var step := acc >= 0.1
	if step:
		acc = 0.0
	var i := list.size() - 1
	var changed := false
	while i >= 0:
		var s: Dictionary = list[i]
		if s["k"] == "fire":
			s["t"] -= dt
			var fp: Vector2 = s["p"]
			var fr: float = s["r"]
			if g.rng.randf() < dt * (6.0 + fr * 0.6):
				g.fx.flame(fp + Vector2.from_angle(g.rng.randf() * TAU) * fr * sqrt(g.rng.randf()) * 0.9)
			if s.has("light"):
				s["light"].energy = 1.0 + 0.25 * sin(g.anim_t * 13.0 + s["seed"]) * minf(1.0, s["t"])
			if step:
				# Fire reaches what touches it, a moment later.
				for o in list:
					if (o["k"] == "oil" or o["k"] == "web") and o["ign"] < 0.0 and (o["p"] - fp).length() < o["r"] + fr - 2.0:
						o["ign"] = 0.18 if o["k"] == "oil" else 0.08
			if s["t"] <= 0.0:
				_drop_light(s)
				g.scorch(fp, fr * 1.4)
				list.remove_at(i)
				changed = true
		elif s["ign"] >= 0.0:
			s["ign"] -= dt
			if s["ign"] < 0.0:
				ignite(s)
		i -= 1
	if changed:
		version += 1
		queue_redraw()
	glow_node.queue_redraw()
	_slips()
	if step:
		_burn_creatures()


## Anything rushing across oil loses its feet. Checked every frame: a charge
## crosses a pool faster than the slower checks come round.
func _slips() -> void:
	for e in g.enemies:
		if e.dead or e.stun > 0.0 or e.kind == "warden" or (e.state != "charge" and e.state != "lunge"):
			continue
		if under(e.position) != "oil":
			continue
		e.state = "rest"
		e.st = 0.5
		e.stun = 1.0
		e.knock += e.dir * 120.0
		g.hud.float_text(e.position + Vector2(0, -e.cy * 2.0 - 8.0), "SLIP", Color(0.9, 0.75, 0.45))
		Sfx.play("thud", -6.0)
		g.main.tally("slips")


func _burn_creatures() -> void:
	var heat: float = 9.0 + 1.5 * g.depth
	for e in g.enemies:
		if e.dead:
			continue
		var k := under(e.position)
		match k:
			"fire":
				if e.burn_t <= 0.0:
					e.hurt(heat * 0.5, Vector2.ZERO, Color(1.0, 0.55, 0.2), "burn")
				e.burn_t = maxf(e.burn_t, 2.5)
				e.burn_dps = maxf(e.burn_dps, heat)
				if e.kind == "gloam" and not e.dead:
					# Shades are made of the dark; fire undoes them.
					e.hurt(99.0, Vector2.ZERO, Color(1.0, 0.55, 0.2), "burn")
			"water":
				if e.burn_t > 0.0:
					e.burn_t = 0.0
					g.fx.spark(e.center(), Color(0.7, 0.75, 0.8, 0.6), 8, 30.0, 0.6, 2.0, -30.0)
					Sfx.play("pop", -10.0)
			"web":
				e.slow_t = maxf(e.slow_t, 0.2)
		# A burning foe sets light to what it walks through.
		if e.burn_t > 0.0 and not e.dead:
			ignite_at(e.position, 2.0)
	if not g.dead and under(g.ppos) == "fire":
		g.hurt_player(1, g.ppos + Vector2(0, 6), 90.0, "fire")


## How much the ground slows Wren where she stands.
func player_drag() -> float:
	match under(g.ppos):
		"web":
			return 0.6
		"oil":
			return 0.85
	return 1.0


func _fly(dt: float) -> void:
	var i := flasks.size() - 1
	while i >= 0:
		var f: Dictionary = flasks[i]
		f["t"] += dt / f["dur"]
		var k: float = minf(f["t"], 1.0)
		var node: Node2D = f["node"]
		node.position = f["a"].lerp(f["b"], k)
		# Up and over: the arc rides on the bottle, above its spot on the floor.
		var b: Sprite2D = f["body"]
		b.position = Vector2(0, -6.0 - sin(k * PI) * 26.0)
		b.rotation = k * TAU * 1.5
		if f["t"] >= 1.0:
			var at: Vector2 = f["b"]
			Sfx.play("urn", -2.0, 0.15)
			Sfx.play("oil", -10.0)
			g.fx.spark(at, Color(0.55, 0.4, 0.15, 0.9), 14, 70.0, 0.4, 2.0, 120.0)
			g.fx.spark(at, Color(0.85, 0.9, 1.0, 0.8), 6, 60.0, 0.25, 1.5)
			spill(at, 20.0)
			node.queue_free()
			flasks.remove_at(i)
		i -= 1


# --- Drawing (the flat view; the 3D view reads the same list) ---------------------------

## The ragged outline of a surface as a few overlapping blobs: (centre, radius).
static func blobs(s: Dictionary) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = s["seed"]
	var rad: float = s["r"]
	var out: Array = [[s["p"], rad * 0.78]]
	for i in 4:
		var a := r.randf() * TAU
		out.append([s["p"] + Vector2.from_angle(a) * rad * r.randf_range(0.25, 0.45), rad * r.randf_range(0.42, 0.6)])
	return out


## A web as straight strands: spokes from the middle, and rings across them.
static func web_lines(s: Dictionary) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = s["seed"]
	var c: Vector2 = s["p"]
	var rad: float = s["r"]
	var out: Array = []
	var spokes := 7
	var a0 := r.randf() * TAU
	var tips: Array = []
	for i in spokes:
		var a := a0 + TAU * i / spokes + r.randf_range(-0.2, 0.2)
		tips.append(Vector2.from_angle(a))
		out.append([c, c + Vector2.from_angle(a) * rad * r.randf_range(0.85, 1.05)])
	for ring_k in [0.35, 0.65, 0.92]:
		for i in spokes:
			var j := (i + 1) % spokes
			out.append([c + tips[i] * rad * ring_k, c + tips[j] * rad * ring_k])
	return out


func _draw() -> void:
	for s in list:
		match s["k"]:
			"water":
				for b in blobs(s):
					draw_circle(b[0], b[1], WATER_COL)
				draw_arc(s["p"] + Vector2(-s["r"] * 0.2, -s["r"] * 0.25), s["r"] * 0.45, PI * 1.1, PI * 1.6, 8, WATER_HI, 1.0)
			"oil":
				for b in blobs(s):
					draw_circle(b[0], b[1], OIL_COL)
				draw_arc(s["p"] + Vector2(s["r"] * 0.1, -s["r"] * 0.15), s["r"] * 0.5, PI * 1.15, PI * 1.7, 8, SHEEN_COL, 1.0)
			"web":
				for l in web_lines(s):
					draw_line(l[0], l[1], WEB_COL, 0.6)
			"fire":
				for b in blobs(s):
					draw_circle(b[0], b[1], Color(0.06, 0.02, 0.0, 0.55))


func _draw_glow() -> void:
	for s in list:
		if s["k"] != "fire":
			continue
		var k := clampf(s["t"], 0.0, 1.0)
		var flick := 0.8 + 0.2 * sin(g.anim_t * 17.0 + s["seed"])
		for b in blobs(s):
			glow_node.draw_circle(b[0], b[1], Color(FIRE_COL.r, FIRE_COL.g, FIRE_COL.b, FIRE_COL.a * k * flick))
