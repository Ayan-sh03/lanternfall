extends Node2D
## Everything hostile, including the Warden. Each kind is a small state machine.

const Art = preload("res://scripts/art.gd")

var g
var kind := ""
var hp := 10.0
var max_hp := 10.0
var speed := 40.0
var radius := 5.0
var cy := 6.0
var hit_r := 6.0
var dmg := 1
var xp := 2
var weight := 1.0
var tint := Color.WHITE
var room := -1

var state := "chase"
var st := 0.0
var cd := 0.0
var sub := 0
var sub_t := 0.0
var spin := 0.0
var phase := 1
var last_atk := ""
var vel := Vector2.ZERO
var knock := Vector2.ZERO
var dir := Vector2.RIGHT
var blocked := false
var awake := false
var dead := false
var has_los := false
var think := 0.0
var touch_cd := 0.0
var strafe := 1.0

var spr: Sprite2D
var mat: ShaderMaterial
var frames: Array = []
var flash := 0.0
var anim := 0.0
var seed_f := 0.0
var hover := 0.0
var base_mod := Color.WHITE
var frame_ids: Array = []
var emi: Sprite2D
var eglow: Sprite2D
var elite := false
var stun := 0.0
var slow_t := 0.0
var burn_t := 0.0
var burn_dps := 0.0
var burn_acc := 0.0
var orbit_cd := 0.0
var spawn_idx := -1
## Set for characters whose limbs are animated part by part (see Art._anim).
var prefix := ""
var walk_fps := 6.0
## Squash and stretch when struck, springing back; scale before any squash.
var sq_amp := 0.0
var sq_t := 9.0
var base_scale := Vector2.ZERO


func setup(game, k: String, pos: Vector2, r: int) -> void:
	g = game
	kind = k
	position = pos
	room = r
	seed_f = g.rng.randf() * 10.0
	strafe = 1.0 if g.rng.randf() < 0.5 else -1.0
	match kind:
		"husk":
			_stats(22.0, 46.0, 5.0, 2, ["husk_idle"], Color(0.85, 0.82, 0.75))
			prefix = "husk"
			walk_fps = 7.0
		"moth":
			_stats(9.0, 64.0, 4.0, 1, ["moth0", "moth1"], Color(0.6, 0.45, 0.85))
			hover = 7.0
			cy += hover
		"cantor":
			_stats(16.0, 34.0, 5.0, 3, ["cantor_idle"], Color(0.85, 0.25, 0.35))
			prefix = "cantor"
			walk_fps = 5.0
			cd = g.rng.randf_range(0.6, 1.6)
			hover = 1.0
		"brute":
			_stats(70.0, 27.0, 6.0, 8, ["brute_idle"], Color(0.8, 0.6, 0.3))
			prefix = "brute"
			walk_fps = 5.0
			weight = 3.0
			cd = 1.0
		"slime":
			_stats(26.0, 108.0, 5.0, 3, ["slime0", "slime1"], Color(0.3, 0.5, 0.95))
		"slimelet":
			_stats(8.0, 120.0, 3.5, 1, ["slime0", "slime1"], Color(0.3, 0.5, 0.95))
			spr.scale = Vector2(0.65, 0.65)
			cy *= 0.65
			hit_r = 5.0
		"wisp":
			_stats(8.0, 60.0, 4.0, 2, ["wisp0", "wisp1"], Color(1.0, 0.55, 0.15))
			spr.material = Art.mat_unlit
			mat = null
			hover = 4.0
			cy += hover
			var gl := Sprite2D.new()
			gl.texture = Art.tex["glow"]
			gl.material = Art.mat_add
			gl.modulate = Color(1.0, 0.45, 0.12, 0.6)
			gl.scale = Vector2(0.6, 0.6)
			gl.position = Vector2(0, -cy)
			add_child(gl)
		"gloam":
			# A shade in a keeper's shape, all but its eyes swallowed by the dark.
			_stats(10.0, 60.0, 4.5, 0, ["husk_idle"], Color(0.4, 0.25, 0.7))
			prefix = "husk"
			walk_fps = 9.0
			base_mod = Color(0.1, 0.07, 0.18)
		"warden":
			_stats(950.0, 34.0, 7.0, 0, ["warden_idle"], Color(1.0, 0.55, 0.2))
			prefix = "warden"
			walk_fps = 5.0
			weight = 9.0
			spr.scale = Vector2(1.25, 1.25)
			cy *= 1.25
			hit_r = 14.0
			dmg = 1
			state = "dormant"
			base_mod = Color(0.5, 0.5, 0.62)
	if kind != "warden":
		hp *= 1.0 + 0.22 * (g.depth - 1)
	max_hp = hp
	spr.modulate = base_mod


func _stats(h: float, sp: float, r: float, x: int, fr: Array, col: Color) -> void:
	hp = h
	speed = sp
	radius = r
	xp = x
	tint = col
	for f in fr:
		frames.append(Art.tex[f])
	var sh := Sprite2D.new()
	sh.texture = Art.tex["shadow"]
	sh.z_index = -1
	sh.position = Vector2(0, 2)
	sh.scale = Vector2(r / 5.0, r / 5.0)
	add_child(sh)
	spr = Sprite2D.new()
	spr.texture = frames[0]
	var th: float = spr.texture.get_height()
	var border: int = Art.pad.get(fr[0], 1)
	var art_w: float = spr.texture.get_width() - border * 2 + 2
	spr.offset = Vector2(0, -th * 0.5 + 2.0 + border)
	cy = th * 0.5 - 2.0 - border
	hit_r = maxf(r + 1.5, art_w * 0.36)
	mat = ShaderMaterial.new()
	mat.shader = Art.flash_shader
	spr.material = mat
	add_child(spr)
	frame_ids = fr
	if Art.tex.has(str(fr[0]) + "_e"):
		# Eyes and other burning parts ignore the dungeon's darkness.
		emi = Sprite2D.new()
		emi.material = Art.mat_unlit
		emi.offset = spr.offset
		spr.add_child(emi)
		eglow = Sprite2D.new()
		eglow.texture = Art.tex["glow"]
		eglow.material = Art.mat_add
		var gc: Color = Art.glow_col[fr[0]]
		eglow.modulate = Color(gc.r, gc.g, gc.b, 0.4)
		var gs: float = clampf(art_w / 64.0, 0.22, 0.5)
		eglow.scale = Vector2(gs, gs)
		spr.add_child(eglow)


## Elites guard the stair: bigger, tougher, and wreathed in a sickly light.
func make_elite() -> void:
	elite = true
	hp *= 2.6
	max_hp = hp
	xp *= 3
	speed *= 1.1
	spr.scale *= 1.25
	cy *= 1.25
	hit_r *= 1.2
	weight *= 1.6
	var aura := Sprite2D.new()
	aura.texture = Art.tex["glow"]
	aura.material = Art.mat_add
	aura.modulate = Color(0.8, 0.2, 1.0, 0.4)
	aura.scale = Vector2(0.75, 0.75)
	aura.position = Vector2(0, -cy)
	aura.z_index = -1
	add_child(aura)


func center() -> Vector2:
	return position + Vector2(0, -cy)


func wake() -> void:
	if awake:
		return
	awake = true
	g.on_wake(self)
	g.hud.float_text(position + Vector2(0, -cy * 2.0 - 4.0), "!", Color(1.0, 0.3, 0.25))
	for o in g.enemies:
		if o.room == room and not o.awake and o.kind != "warden":
			o.awake = true


func rouse() -> void:
	# The Warden stands up.
	awake = true
	state = "chase"
	cd = 1.2
	base_mod = Color.WHITE


func hurt(amount: float, kb: Vector2, col: Color = Color(1.0, 0.92, 0.65)) -> void:
	if dead or state == "dormant":
		return
	hp -= amount
	flash = 1.0
	knock += kb / weight
	# Heavier foes give less.
	sq_amp = clampf(0.12 + amount * 0.008, 0.12, 0.34) / sqrt(weight)
	sq_t = 0.0
	if not awake:
		wake()
	g.hud.float_text(position + Vector2(randf_range(-4.0, 4.0), -cy * 2.0 - 2.0), str(maxi(1, roundi(amount))), col)
	g.fx.spark(center(), tint, 5, 70.0, 0.3)
	if hp <= 0.0:
		die()
	else:
		Sfx.play("hit", -5.0)


func die() -> void:
	if dead:
		return
	dead = true
	visible = false
	g.enemy_died(self)


func tick(dt: float) -> void:
	anim += dt
	flash = maxf(0.0, flash - dt * 6.0)
	touch_cd -= dt
	visible = g.vis_at(position)
	var to_p: Vector2 = g.ppos - position
	var dist := to_p.length()
	if not awake:
		if state != "dormant" and dist < 125.0 and visible and g.los(position, g.ppos):
			wake()
		_animate()
		return
	think -= dt
	if think <= 0.0:
		think = 0.16 + 0.01 * seed_f
		has_los = dist < 240.0 and g.los(position, g.ppos)
	knock = knock.move_toward(Vector2.ZERO, 520.0 * dt)
	vel = Vector2.ZERO
	orbit_cd -= dt
	if burn_t > 0.0:
		burn_t -= dt
		burn_acc += dt
		if g.rng.randf() < dt * 14.0:
			g.fx.flame(center() + Vector2(g.rng.randf_range(-4.0, 4.0), 2.0))
		if burn_acc >= 0.5:
			burn_acc = 0.0
			# Wildfire: the flames reach whoever stands too close.
			if g.stats["wildfire"] > 0.0:
				for o in g.enemies:
					if o != self and not o.dead and o.burn_t <= 0.0 and (o.position - position).length() < 24.0:
						o.burn_t = 2.5
						o.burn_dps = burn_dps
			hurt(burn_dps * 0.5, Vector2.ZERO, Color(1.0, 0.6, 0.2))
			if dead:
				return
	if stun > 0.0:
		# Stunned: no thinking, just skid to a halt.
		stun -= dt * (3.0 if kind == "warden" else 1.0)
		position = g.move_body(position, knock * dt, radius)
		if g.rng.randf() < dt * 20.0:
			g.fx.spark(center(), Color(0.6, 0.85, 1.0), 1, 30.0, 0.25, 1.5)
		_animate()
		return
	match kind:
		"husk", "gloam":
			_ai_husk(dt, to_p, dist)
		"moth":
			_ai_moth(dt, to_p, dist)
		"cantor":
			_ai_cantor(dt, to_p, dist)
		"brute":
			_ai_brute(dt, to_p, dist)
		"slime", "slimelet":
			_ai_slime(dt, dist)
		"wisp":
			_ai_wisp(dt, dist)
		"warden":
			_ai_warden(dt, to_p, dist)
	if dead:
		return
	if slow_t > 0.0:
		slow_t -= dt
		vel *= 0.6 if kind == "warden" else 0.4
	var before := position
	var step: Vector2 = (vel + knock) * dt
	position = g.move_body(position, step, radius)
	blocked = vel.length() > 60.0 and (position - before).length() < step.length() * 0.4
	_separate(dt)
	_animate()


func _seek() -> Vector2:
	if has_los:
		return (g.ppos - position).normalized()
	return g.flow_dir(position)


func _touch(dist: float, reach: float, amount: int = -1, kb: float = 170.0) -> void:
	# A little short of the full reach: near misses should miss.
	if dist < reach * 0.85 and touch_cd <= 0.0:
		g.hurt_player(dmg if amount < 0 else amount, position, kb, self)
		touch_cd = 0.7


func _shoot(d: Vector2, spd: float) -> void:
	g.add_shot(center(), d * spd, false, 1, Color(1.0, 0.3, 0.75))
	g.shots[g.shots.size() - 1]["src"] = kind


func _separate(dt: float) -> void:
	for o in g.enemies:
		if o == self or o.dead or not o.awake:
			continue
		var d: Vector2 = position - o.position
		var rr: float = radius + o.radius + 2.0
		var l2 := d.length_squared()
		if l2 < rr * rr and l2 > 0.01:
			position = g.move_body(position, d.normalized() * 34.0 * dt / weight, radius)


func _animate() -> void:
	var fid: String
	if prefix != "":
		fid = _frame_id()
	else:
		var fi := int(anim * (9.0 if kind == "moth" else 6.0) + seed_f) % frame_ids.size()
		if kind == "slime" or kind == "slimelet":
			fi = 0 if state == "hop" else 1
		fid = frame_ids[fi]
	spr.texture = Art.tex[fid]
	var tele := state == "wind" or state == "cast" or state == "fuse" or state.ends_with("_w")
	var blink := 0.6 if tele and int(anim * 16.0) % 2 == 0 else 0.0
	if mat != null:
		mat.set_shader_parameter("flash", maxf(flash, blink))
	spr.position.x = sin(anim * 70.0) * 0.8 if tele else 0.0
	if base_scale == Vector2.ZERO:
		base_scale = spr.scale
	sq_t += get_process_delta_time()
	var sq: float = g.squash_k(sq_t) * sq_amp
	# Winding up, a foe draws itself tall: the tell before the blow.
	if tele:
		sq -= 0.07
	spr.scale = base_scale * Vector2(1.0 + sq, 1.0 - sq * 0.85)
	spr.position.y = -hover + (sin(anim * 5.0 + seed_f) * 1.5 if hover > 0.0 else 0.0)
	spr.modulate = base_mod
	if awake and state != "charge" and state != "lunge" and stun <= 0.0:
		spr.flip_h = g.ppos.x < position.x
	if emi != null:
		emi.texture = Art.tex[fid + "_e"]
		emi.flip_h = spr.flip_h
		var at: Vector2 = Art.glow_at[fid]
		eglow.position = spr.offset + Vector2(-at.x if spr.flip_h else at.x, at.y)
		eglow.modulate.a = (0.36 + 0.1 * sin(anim * 6.0 + seed_f)) if awake else 0.15
		emi.modulate.a = 1.0 if awake or state == "dormant" else 0.5


## Which pose a part-animated character should be in right now: an attack
## pose if it is winding up or striking, a step of the walk if it is moving.
func _frame_id() -> String:
	match kind:
		"husk", "gloam":
			if state == "wind":
				return "husk_wind"
			if state == "lunge":
				return "husk_lunge"
		"cantor":
			if state == "cast":
				return "cantor_cast"
		"brute":
			if state == "wind":
				return "brute_wind"
			if state == "charge":
				return "brute_c%d" % (int(anim * 14.0) % 2)
		"warden":
			if state == "sweep_w" or state == "charge_w" or state == "charge":
				return "warden_wind"
			if state == "ring_w" or state == "spiral" or state == "stagger":
				return "warden_cast"
			if state == "rest" and last_atk == "sweep" and st > 0.25:
				return "warden_strike"
	if awake and vel.length() > 2.0:
		return "%s_w%d" % [prefix, int(anim * walk_fps + seed_f) % 4]
	return prefix + "_idle"


# --- Behaviours ---------------------------------------------------------------

func _ai_husk(dt: float, to_p: Vector2, dist: float) -> void:
	match state:
		"chase":
			vel = _seek() * speed
			if dist < 25.0 and has_los:
				state = "wind"
				st = 0.4
				dir = to_p.normalized()
		"wind":
			st -= dt
			if st <= 0.0:
				state = "lunge"
				st = 0.2
				dir = to_p.normalized()
				Sfx.play("growl", -2.0)
		"lunge":
			st -= dt
			vel = dir * 200.0
			_touch(dist, 11.0)
			if st <= 0.0:
				state = "rest"
				st = 0.55
		"rest":
			st -= dt
			if st <= 0.0:
				state = "chase"


func _ai_moth(dt: float, to_p: Vector2, dist: float) -> void:
	if state == "back":
		st -= dt
		vel = -to_p.normalized().rotated(sin(anim * 3.0 + seed_f)) * speed
		if st <= 0.0:
			state = "chase"
	else:
		vel = _seek().rotated(sin(anim * 4.0 + seed_f) * 0.9) * speed
		if dist < 10.0 and touch_cd <= 0.0:
			g.hurt_player(dmg, position, 120.0, self)
			touch_cd = 0.9
			state = "back"
			st = 0.7


func _ai_cantor(dt: float, to_p: Vector2, dist: float) -> void:
	match state:
		"chase":
			cd -= dt
			if has_los:
				var n := to_p / maxf(dist, 0.01)
				if dist < 62.0:
					vel = -n * speed
				elif dist > 120.0:
					vel = n * speed
				else:
					vel = n.orthogonal() * speed * 0.6 * strafe
				if cd <= 0.0 and dist < 200.0:
					state = "cast"
					st = 0.55
					Sfx.play("telegraph", -10.0)
					g.fx.ring(center(), 16.0, 3.0, 0.55, Color(1.0, 0.3, 0.75, 0.8))
			else:
				vel = _seek() * speed
		"cast":
			st -= dt
			if st <= 0.0:
				var d := to_p.normalized()
				_shoot(d, 92.0)
				if g.depth >= 4:
					_shoot(d.rotated(0.32), 92.0)
					_shoot(d.rotated(-0.32), 92.0)
				Sfx.play("shoot", -8.0)
				cd = 2.4 - 0.15 * g.depth
				strafe = -strafe
				state = "chase"


func _ai_brute(dt: float, to_p: Vector2, dist: float) -> void:
	match state:
		"chase":
			cd -= dt
			vel = _seek() * speed
			_touch(dist, 13.0)
			if has_los and dist < 125.0 and cd <= 0.0:
				state = "wind"
				st = 0.7
				dir = to_p.normalized()
				Sfx.play("bell", -6.0)
		"wind":
			st -= dt
			dir = dir.lerp(to_p.normalized(), dt * 3.0).normalized()
			if st <= 0.0:
				state = "charge"
				st = 0.75
				Sfx.play("dash", -3.0)
		"charge":
			st -= dt
			vel = dir * 215.0
			spr.flip_h = dir.x < 0.0
			_touch(dist, 14.0, 2, 280.0)
			if g.rng.randf() < 0.5:
				g.fx.spark(position, Color(0.6, 0.55, 0.5, 0.5), 1, 20.0, 0.3, 2.0)
			if blocked:
				state = "rest"
				st = 1.2
				g.add_shake(4.0)
				Sfx.play("thud", -2.0)
				g.fx.spark(position, Color(0.8, 0.7, 0.6), 10, 80.0, 0.4, 2.0)
			elif st <= 0.0:
				state = "rest"
				st = 0.6
		"rest":
			st -= dt
			if st <= 0.0:
				state = "chase"
				cd = 2.2


func _ai_slime(dt: float, dist: float) -> void:
	_touch(dist, 10.0)
	match state:
		"chase":
			st -= dt
			if st <= 0.0:
				dir = _seek()
				if dir == Vector2.ZERO:
					dir = Vector2.from_angle(g.rng.randf() * TAU)
				state = "hop"
				st = 0.3
				if visible and g.rng.randf() < 0.4:
					Sfx.play("slime", -4.0)
		"hop":
			st -= dt
			vel = dir * speed
			if st <= 0.0:
				state = "chase"
				st = g.rng.randf_range(0.35, 0.6)


func _ai_wisp(dt: float, dist: float) -> void:
	match state:
		"chase":
			vel = _seek().rotated(sin(anim * 3.0 + seed_f) * 0.4) * speed
			if dist < 24.0 and has_los:
				state = "fuse"
				st = 0.75
				Sfx.play("telegraph", -6.0)
				g.fx.ring(position, 34.0, 34.0, 0.75, Color(1.0, 0.3, 0.05, 0.3), true)
		"fuse":
			st -= dt
			spr.scale = Vector2.ONE * (1.0 + (0.75 - st) * 1.1 + sin(anim * 40.0) * 0.1)
			if st <= 0.0:
				g.fx.spark(center(), Color(1.0, 0.6, 0.15), 40, 150.0, 0.6, 2.5)
				g.fx.ring(position, 6.0, 38.0, 0.3, Color(1.0, 0.7, 0.3), false, 3.0)
				g.scorch(position, 12.0)
				g.add_shake(6.0)
				Sfx.play("boom", -2.0)
				if dist < 36.0:
					g.hurt_player(2, position, 240.0, self)
				xp = 0
				die()


# --- The Hollow Warden --------------------------------------------------------

func _ai_warden(dt: float, to_p: Vector2, dist: float) -> void:
	var frac := hp / max_hp
	var np := 1
	if frac <= 0.33:
		np = 3
	elif frac <= 0.66:
		np = 2
	if np > phase:
		phase = np
		state = "stagger"
		st = 1.1
		g.boss_phase(phase)
		_summon(2 if phase == 2 else 3)
		return
	match state:
		"stagger":
			st -= dt
			if st <= 0.0:
				state = "chase"
				cd = 0.5
		"chase":
			vel = _seek() * speed * (1.0 + 0.3 * (phase - 1))
			cd -= dt
			_touch(dist, 15.0)
			if cd <= 0.0:
				_warden_pick(to_p, dist)
		"sweep_w":
			st -= dt
			if st <= 0.0:
				g.fx.ring(position, 12.0, 52.0, 0.22, Color(1.0, 0.55, 0.2, 0.9), false, 4.0)
				g.fx.slash(center(), 0.0, 50.0, TAU, Color(1.0, 0.5, 0.2, 0.7), 0.25)
				Sfx.play("slash3", 2.0)
				g.add_shake(5.0)
				if dist < 52.0:
					g.hurt_player(2, position, 280.0, self)
				state = "rest"
				st = 0.6
		"ring_w":
			st -= dt
			if st <= 0.0:
				_ring(9 + phase * 3, 72.0 + phase * 6.0)
				Sfx.play("shoot", -3.0)
				sub -= 1
				if sub > 0:
					st = 0.5
				else:
					state = "rest"
					st = 0.5
		"charge_w":
			st -= dt
			dir = dir.lerp(to_p.normalized(), dt * 4.0).normalized()
			if st <= 0.0:
				state = "charge"
				st = 0.55
				Sfx.play("dash", 0.0)
		"charge":
			st -= dt
			vel = dir * 250.0
			spr.flip_h = dir.x < 0.0
			_touch(dist, 18.0, 2, 300.0)
			g.fx.spark(center(), Color(1.0, 0.5, 0.2, 0.6), 1, 20.0, 0.3, 2.5)
			if blocked or st <= 0.0:
				if blocked:
					g.add_shake(5.0)
					Sfx.play("thud", 0.0)
				state = "rest"
				st = 0.7
		"spiral":
			st -= dt
			sub_t -= dt
			if sub_t <= 0.0:
				sub_t = 0.12
				spin += 0.31
				var arms := 2 if phase < 3 else 3
				for k in arms:
					_shoot(Vector2.from_angle(spin + TAU * k / arms), 78.0)
				Sfx.play("shoot", -12.0)
			if st <= 0.0:
				state = "rest"
				st = 0.8
		"rest":
			st -= dt
			if st <= 0.0:
				state = "chase"
				cd = [1.25, 0.9, 0.6][phase - 1]


func _warden_pick(to_p: Vector2, dist: float) -> void:
	var opts: Array = ["ring"]
	if dist < 58.0:
		opts.append("sweep")
		opts.append("sweep")
	if phase >= 2:
		opts.append("charge")
		opts.append("spiral")
	if phase >= 3:
		opts.append("charge")
		opts.append("spiral")
	var pick: String = opts[g.rng.randi() % opts.size()]
	if pick == last_atk:
		pick = opts[g.rng.randi() % opts.size()]
	last_atk = pick
	match pick:
		"sweep":
			state = "sweep_w"
			st = 0.6
			g.fx.ring(position, 52.0, 52.0, 0.6, Color(1.0, 0.25, 0.08, 0.3), true)
			Sfx.play("telegraph", -4.0)
		"ring":
			state = "ring_w"
			st = 0.5
			sub = 1 if phase == 1 else 2
			g.fx.ring(center(), 44.0, 6.0, 0.5, Color(1.0, 0.35, 0.8, 0.8), false, 2.0)
			Sfx.play("telegraph", -4.0)
		"charge":
			state = "charge_w"
			st = 0.6
			dir = to_p.normalized()
			Sfx.play("bell", -2.0)
		"spiral":
			state = "spiral"
			st = 2.2 + 0.4 * phase
			sub_t = 0.35
			Sfx.play("roar", -8.0)


func _ring(n: int, spd: float) -> void:
	spin += 0.21
	for k in n:
		_shoot(Vector2.from_angle(spin + TAU * k / n), spd)


func _summon(n: int) -> void:
	for k in n:
		var p := position + Vector2.from_angle(TAU * k / n + 0.5) * 34.0
		if g.solid_at(p):
			p = position
		var m = g.spawn_enemy("moth", p, room)
		m.awake = true
		g.fx.spark(p, Color(0.7, 0.4, 1.0), 12, 60.0, 0.5, 2.0)
