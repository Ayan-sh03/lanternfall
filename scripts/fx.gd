extends Node2D
## Glowing particles, sword arcs and warning rings, all drawn additively.

const Art = preload("res://scripts/art.gd")

var parts: Array = []
var slashes: Array = []
var rings: Array = []
var bolts: Array = []
var wards: Array = []
var t := 0.0


func _ready() -> void:
	material = Art.mat_add


func clear() -> void:
	parts.clear()
	slashes.clear()
	rings.clear()
	bolts.clear()


func spark(pos: Vector2, col: Color, n: int = 6, spd: float = 60.0, life: float = 0.4, size: float = 1.5, grav: float = 0.0) -> void:
	for i in n:
		if parts.size() > 600:
			return
		var l := life * randf_range(0.6, 1.0)
		parts.append({"p": pos, "v": Vector2.from_angle(randf() * TAU) * spd * randf_range(0.3, 1.0),
			"l": l, "m": l, "s": size, "c": col, "g": grav})


func flame(pos: Vector2, col: Color = Color(1.0, 0.5, 0.12, 0.9)) -> void:
	if parts.size() > 600:
		return
	parts.append({"p": pos + Vector2(randf_range(-2.5, 2.5), 0.0), "v": Vector2(randf_range(-5.0, 5.0), randf_range(-30.0, -14.0)),
		"l": 0.5, "m": 0.5, "s": 2.2, "c": col, "g": -12.0})


func slash(pos: Vector2, ang: float, reach: float, arc: float, col: Color, dur: float = 0.16) -> void:
	slashes.append({"p": pos, "g": ang, "r": reach, "a": arc, "c": col, "t": 0.0, "d": dur})


## A ring that grows or shrinks from r0 to r1. With fill it becomes a danger zone.
func ring(pos: Vector2, r0: float, r1: float, dur: float, col: Color, fill: bool = false, width: float = 1.5) -> void:
	rings.append({"p": pos, "r0": r0, "r1": r1, "c": col, "t": 0.0, "d": dur, "f": fill, "w": width})


## A jagged stroke of lightning between two points.
func bolt(a: Vector2, b: Vector2, col: Color) -> void:
	bolts.append({"a": a, "b": b, "c": col, "t": 0.0, "d": 0.28})


func _process(dt: float) -> void:
	t += dt
	var j := bolts.size() - 1
	while j >= 0:
		bolts[j]["t"] += dt
		if bolts[j]["t"] >= bolts[j]["d"]:
			bolts.remove_at(j)
		j -= 1
	var i := parts.size() - 1
	while i >= 0:
		var p: Dictionary = parts[i]
		p["l"] -= dt
		if p["l"] <= 0.0:
			parts[i] = parts[parts.size() - 1]
			parts.pop_back()
		else:
			p["v"] = p["v"] * (1.0 - 3.0 * dt) + Vector2(0.0, p["g"] * dt)
			p["p"] += p["v"] * dt
		i -= 1
	i = slashes.size() - 1
	while i >= 0:
		slashes[i]["t"] += dt
		if slashes[i]["t"] >= slashes[i]["d"]:
			slashes.remove_at(i)
		i -= 1
	i = rings.size() - 1
	while i >= 0:
		rings[i]["t"] += dt
		if rings[i]["t"] >= rings[i]["d"]:
			rings.remove_at(i)
		i -= 1
	queue_redraw()


func _draw() -> void:
	for p in parts:
		var k: float = p["l"] / p["m"]
		var sz: float = p["s"] * (0.5 + 0.5 * k)
		var c: Color = p["c"]
		var pos: Vector2 = p["p"]
		draw_rect(Rect2(pos - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(c.r, c.g, c.b, c.a * k))

	for sl in slashes:
		var k: float = 1.0 - sl["t"] / sl["d"]
		var reach: float = sl["r"] * (0.8 + 0.2 * (1.0 - k))
		var arc: float = sl["a"]
		var a_start: float = sl["g"] - arc * 0.5
		var o: Vector2 = sl["p"]
		var c: Color = sl["c"]
		var col := Color(c.r, c.g, c.b, c.a * k)
		var segs := 12
		for j in segs:
			var u0 := float(j) / segs
			var u1 := float(j + 1) / segs
			var d0 := Vector2.from_angle(a_start + arc * u0)
			var d1 := Vector2.from_angle(a_start + arc * u1)
			var in0 := reach * (0.6 + 0.34 * pow(absf(u0 * 2.0 - 1.0), 1.5))
			var in1 := reach * (0.6 + 0.34 * pow(absf(u1 * 2.0 - 1.0), 1.5))
			draw_colored_polygon(PackedVector2Array([o + d0 * reach, o + d1 * reach, o + d1 * in1, o + d0 * in0]), col)

	for bl in bolts:
		var k: float = 1.0 - bl["t"] / bl["d"]
		var a: Vector2 = bl["a"]
		var b: Vector2 = bl["b"]
		var c: Color = bl["c"]
		var n := maxi(3, int(a.distance_to(b) / 9.0))
		var side := (b - a).orthogonal().normalized()
		# Redrawn with fresh jitter every frame, so it crackles.
		for pass_i in 2:
			var pts := PackedVector2Array([a])
			for s in range(1, n):
				pts.append(a.lerp(b, float(s) / n) + side * randf_range(-5.0, 5.0))
			pts.append(b)
			draw_polyline(pts, Color(c.r, c.g, c.b, k * (0.9 if pass_i == 0 else 0.5)), 2.5 if pass_i == 0 else 1.0)

	for wd in wards:
		var wp: Vector2 = wd["p"]
		var wr: float = wd["r"]
		var wa: float = clampf(wd["t"], 0.0, 1.0)
		draw_arc(wp, wr, 0.0, TAU, 48, Color(1.0, 0.75, 0.35, 0.8 * wa), 2.0)
		draw_arc(wp, wr * 0.62, 0.0, TAU, 40, Color(1.0, 0.6, 0.25, 0.35 * wa), 1.0)
		draw_circle(wp, wr, Color(1.0, 0.55, 0.2, 0.07 * wa))
		for q in 8:
			var ang := t * 0.8 + TAU * q / 8.0
			var d0 := Vector2.from_angle(ang)
			draw_line(wp + d0 * (wr - 6.0), wp + d0 * (wr + 1.0), Color(1.0, 0.85, 0.5, 0.9 * wa), 2.0)
			var d1 := Vector2.from_angle(-ang * 1.3)
			draw_rect(Rect2(wp + d1 * wr * 0.62 - Vector2(1.5, 1.5), Vector2(3, 3)), Color(1.0, 0.8, 0.45, 0.8 * wa))

	for r in rings:
		var k: float = r["t"] / r["d"]
		var rad: float = lerpf(r["r0"], r["r1"], k)
		var c: Color = r["c"]
		var pos: Vector2 = r["p"]
		if r["f"]:
			draw_circle(pos, rad, Color(c.r, c.g, c.b, c.a * (0.35 + 0.65 * k)))
			draw_arc(pos, rad, 0.0, TAU, 40, Color(c.r, c.g, c.b, 0.9), 1.5)
		else:
			draw_arc(pos, maxf(rad, 0.5), 0.0, TAU, 40, Color(c.r, c.g, c.b, c.a * (1.0 - k * k)), r["w"])
