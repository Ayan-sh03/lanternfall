extends Node2D
## Flit: a lamp moth Wren feeds a drop of oil, and keeps. It circles her
## lantern, flies off to light the dark corners she has not seen, hangs at
## walls with light behind them, and once it has grown, nips at what comes
## for her. It can be swatted, and if it dies, it is gone for the descent.

const Art = preload("res://scripts/art.gd")
const COL := Color(0.86, 0.92, 1.0)

static var frames: Array = []

var g
var lv := 1
var hp := 3
var fed := 0
var state := "orbit"
var st := 0.0
var target := Vector2.ZERO
var prey = null
var ang := 0.0
var scout_cd := 2.0
var nip_cd := 1.0
var t := 0.0
var flash := 0.0
var body: Sprite2D
var glow: Sprite2D
var light: PointLight2D


## Two frames of a small pale moth, wings up and wings down.
static func make_frames() -> Array:
	if not frames.is_empty():
		return frames
	var shapes := [
		["#.....#", "##...##", "###.###", ".#####.", "..###..", ".##.##.", "##...##"],
		[".......", ".......", "#######", "#######", ".#####.", "..#.#..", "......."],
	]
	for sh in shapes:
		var img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
		for y in 7:
			for x in 7:
				if sh[y][x] == "#":
					var body_px: bool = x == 3
					img.set_pixel(x, y, Color(0.55, 0.5, 0.45) if body_px else Color(0.93, 0.95, 1.0) if (x + y) % 3 else Color(0.78, 0.82, 0.92))
		frames.append(ImageTexture.create_from_image(img))
	return frames


func setup(game, level: int, life: int, food: int) -> void:
	g = game
	lv = level
	hp = life
	fed = food
	make_frames()
	body = Sprite2D.new()
	body.texture = frames[0]
	body.material = Art.mat_unlit
	add_child(body)
	glow = Sprite2D.new()
	glow.texture = Art.tex["glow"]
	glow.material = Art.mat_add
	glow.modulate = Color(0.75, 0.85, 1.0, 0.45)
	glow.scale = Vector2(0.3, 0.3)
	body.add_child(glow)
	light = PointLight2D.new()
	light.texture = Art.tex["light"]
	light.color = Color(0.8, 0.88, 1.0)
	body.add_child(light)
	position = g.ppos
	_size()


func _size() -> void:
	light.texture_scale = 0.55 + 0.22 * lv
	light.energy = 0.7 + 0.1 * lv
	glow.scale = Vector2.ONE * (0.24 + 0.05 * lv)


## Fed: a drop of oil, or a lamp lit nearby. Two feeds and five make it grow.
func feed(n: int = 1) -> void:
	fed += n
	var want := 1 + int(fed >= 2) + int(fed >= 5)
	if want > lv:
		lv = want
		hp = 2 + lv
		_size()
		g.fx.spark(position + body.position, COL, 16, 50.0, 0.6, 1.5)
		g.hud.float_text(position + body.position + Vector2(0, -8), "FLIT GROWS", COL)
		Sfx.play("chime", -8.0, 0.2)
		if lv == 2:
			g.hud.say("Flit's grown bolder. It bites now.", 3.5, g.hud.C_TEAL)


func hurt() -> void:
	if hp <= 0:
		return
	hp -= 1
	flash = 1.0
	g.fx.spark(position + body.position, COL, 6, 40.0, 0.3, 1.5)
	Sfx.play("pop", -6.0, 0.3)
	state = "back"
	if hp <= 0:
		g.moth_died(self)


func _process(dt: float) -> void:
	if g == null or g.hud.blocking() or g.hitstop > 0.0:
		return
	t += dt
	scout_cd -= dt
	nip_cd -= dt
	flash = maxf(0.0, flash - dt * 4.0)
	var home: Vector2 = g.ppos + Vector2(0, 2)
	var to := home
	var spd := 140.0
	match state:
		"orbit":
			ang += dt * 3.2
			to = home + Vector2(cos(ang) * 15.0, sin(ang) * 7.0)
			spd = 160.0
			if not g.dead and not g.snuffed:
				if lv >= 2 and nip_cd <= 0.0:
					prey = _prey()
					if prey != null:
						state = "nip"
						st = 1.2
				if state == "orbit" and scout_cd <= 0.0:
					scout_cd = 2.5
					var hint: Vector2 = g.secret_hint(position)
					if hint != Vector2.INF:
						target = hint
						state = "hollow"
						st = 3.0
					else:
						var dark: Vector2 = g.dark_tile_near(110.0 + 25.0 * lv)
						if dark != Vector2.INF:
							target = dark
							state = "scout"
							st = 3.0
		"scout", "hollow":
			st -= dt
			to = target + Vector2(sin(t * 7.0) * 4.0, cos(t * 5.0) * 2.0)
			spd = 90.0
			if (position - target).length() < 10.0:
				g.reveal_around(position, 1 + lv)
				if state == "hollow" and int(t * 3.0) % 3 == 0 and g.rng.randf() < dt * 6.0:
					# Fluttering against the wall: dust shaken loose.
					g.fx.spark(position + Vector2(0, -6), Color(0.7, 0.65, 0.55, 0.6), 1, 15.0, 0.6, 1.5, 30.0)
			if st <= 0.0 or (g.ppos - position).length() > 200.0:
				state = "back"
		"nip":
			st -= dt
			if prey == null or not is_instance_valid(prey) or prey.dead:
				state = "back"
			else:
				to = prey.center()
				spd = 200.0
				if (position - prey.center()).length() < 7.0:
					prey.hurt(3.0 + 2.0 * lv, Vector2.ZERO, COL, "ember_hit")
					prey.slow_t = maxf(prey.slow_t, 0.6)
					g.main.tally("flit_bites")
					nip_cd = 1.6
					# A foe it bites may swat back.
					if g.rng.randf() < 0.18:
						hurt()
					state = "back"
			if st <= 0.0:
				state = "back"
				nip_cd = 1.0
		"back":
			spd = 180.0
			if (position - home).length() < 16.0:
				state = "orbit"
	var step: Vector2 = (to - position)
	position += step.limit_length(spd * dt)
	body.position = Vector2(0, -12.0 + sin(t * 9.0) * 1.5)
	body.texture = frames[int(t * 14.0) % 2]
	body.flip_h = step.x < 0.0
	body.modulate = Color(1.0, 0.6, 0.6) if flash > 0.5 else Color.WHITE
	var dim: float = 0.25 if g.snuffed else 1.0
	light.energy = (0.7 + 0.1 * lv) * dim * (0.9 + 0.1 * sin(t * 13.0))
	glow.modulate.a = 0.45 * dim
	visible = not g.dead or hp > 0


func _prey():
	var best = null
	var bd := 55.0
	for e in g.enemies:
		if e.dead or not e.awake or not e.visible or e.kind == "warden":
			continue
		var d: float = (e.position - g.ppos).length()
		if d < bd:
			bd = d
			best = e
	return best
