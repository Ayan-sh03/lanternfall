extends Node2D
## Wren's echo: when she dashes, the last two seconds of her fight play again
## where they happened, as a pale ghost of her. Its blows land at half weight,
## so a combo thrown before a dash is thrown twice.

const Art = preload("res://scripts/art.gd")
const COL := Color(0.55, 0.92, 1.0)

var g
## Frames of Wren: {"t", "p", "f" (sprite frame), "fl" (flipped), "sr", "sp", "so" (staff)}.
var track: Array = []
## Her blows in that time: {"t", "k": "slash"|"bolt", "a": aim, "heavy", "o": where from}.
var blows: Array = []
var clock := 0.0
var t_end := 0.0
var next_blow := 0
var fade := 0.0
var power := 0.5
var body: Sprite2D
var staff: Sprite2D


func setup(game, tr: Array, bl: Array, pw: float) -> void:
	g = game
	track = tr
	blows = bl
	power = pw
	clock = track[0]["t"]
	t_end = track[track.size() - 1]["t"]
	position = track[0]["p"]
	body = Sprite2D.new()
	body.material = Art.mat_unlit
	body.texture = Art.tex[track[0]["f"]]
	body.offset = g.pspr.offset
	add_child(body)
	staff = Sprite2D.new()
	staff.texture = Art.tex["staff"]
	staff.material = Art.mat_unlit
	staff.centered = false
	add_child(staff)
	modulate = Color(COL.r, COL.g, COL.b, 0.0)


func _process(dt: float) -> void:
	if g == null or g.hud.blocking() or g.hitstop > 0.0:
		return
	if g.slow_t > 0.0:
		dt *= 0.3
	clock += dt
	if clock >= t_end:
		fade += dt * 4.0
		modulate.a = 0.55 * (1.0 - fade)
		if fade >= 1.0:
			queue_free()
		return
	modulate.a = minf(0.55, modulate.a + dt * 5.0) * (0.85 + 0.15 * sin(clock * 40.0))
	# Find where Wren was at this moment and stand there.
	var k := 0
	while k < track.size() - 2 and track[k + 1]["t"] <= clock:
		k += 1
	var a: Dictionary = track[k]
	var b: Dictionary = track[mini(k + 1, track.size() - 1)]
	var span: float = maxf(b["t"] - a["t"], 0.0001)
	var w: float = clampf((clock - a["t"]) / span, 0.0, 1.0)
	position = a["p"].lerp(b["p"], w)
	body.texture = Art.tex[a["f"]]
	body.flip_h = a["fl"]
	staff.rotation = a["sr"]
	staff.position = a["sp"]
	staff.offset = a["so"]
	staff.flip_h = a["fl"]
	if g.rng.randf() < dt * 14.0:
		g.fx.spark(position + Vector2(0, -8), Color(COL.r, COL.g, COL.b, 0.5), 1, 12.0, 0.4, 1.5, -20.0)
	while next_blow < blows.size() and blows[next_blow]["t"] <= clock:
		_blow(blows[next_blow])
		next_blow += 1


func _blow(bw: Dictionary) -> void:
	var aim: Vector2 = bw["a"]
	var o: Vector2 = position + Vector2(0, -7)
	if bw["k"] == "bolt":
		g.add_shot(o + aim * 6.0, aim * 235.0, true, g.stats["bolt_dmg"] * power, COL, g.stats["pierce"], 0.32)
		Sfx.play("bolt", -12.0, 0.2)
		return
	var heavy: bool = bw["heavy"]
	var reach: float = (34.0 if heavy else 27.0) * g.stats["reach"]
	var arc := deg_to_rad(200.0 if heavy else 125.0)
	var dmg: float = g.stats["dmg"] * (1.8 if heavy else 1.0) * power
	g.fx.slash(o + aim * 2.0, aim.angle(), reach, arc, Color(COL.r, COL.g, COL.b, 0.8), 0.18)
	Sfx.play("slash", -11.0, 0.25)
	var hit := 0
	for e in g.enemies:
		if e.dead:
			continue
		var v: Vector2 = e.center() - o
		var d := v.length()
		if d < reach + e.hit_r and (d < 9.0 or absf(aim.angle_to(v)) < arc * 0.5 + 0.2):
			e.hurt(dmg, aim * 80.0, COL)
			g.fx.impact(e.center() - v.normalized() * e.hit_r * 0.6, aim.angle(), COL, 0.7)
			hit += 1
	if hit > 0:
		g.add_shake(1.5)
		g.main.tally("echo_hits", hit)
