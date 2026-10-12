extends Control
## On-screen controls for phones and tablets: a thumbstick that appears wherever
## the left thumb lands, and a cluster of rune-stones under the right thumb.
## Holding STRIKE or BOLT turns Wren toward the nearest foe; dragging off either
## stone aims by hand instead.

const Art = preload("res://scripts/art.gd")
const Story = preload("res://scripts/story.gd")

const STICK_R := 74.0
const C_STONE := Color(0.05, 0.04, 0.07, 0.6)
const C_EDGE := Color(0.42, 0.33, 0.25, 0.75)
const USE_ICONS := {"chest": "chest0", "lamp": "lamp1", "page": "page", "plaque": "plaque", "stairs": "stairs",
	"cage": "cage", "relic": "relic"}

var hud
var game = null

## What the game reads each frame.
var move := Vector2.ZERO
var atk := false
var bolt := false
var aiming := false
var aim := Vector2.RIGHT

var stick_id := -1
## The finger turning the 3D camera (a drag on the open right side), and where it was.
var cam_id := -1
var cam_last := Vector2.ZERO
## A second finger there pinches to zoom.
var pinch_id := -1
var pinch_last := Vector2.ZERO
var stick_o := Vector2.ZERO
var stick_p := Vector2.ZERO
## Finger index -> the stone it is holding, and where it first came down.
var held := {}
var held_at := {}
var btns: Array = []
var glow := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func active() -> bool:
	return game != null and is_instance_valid(game) and not hud.blocking() and not game.dead and not game.bot \
		and is_visible_in_tree()


func reset() -> void:
	stick_id = -1
	cam_id = -1
	pinch_id = -1
	held.clear()
	held_at.clear()
	move = Vector2.ZERO
	atk = false
	bolt = false
	aiming = false


## The stones are laid out from the bottom-right corner on an arc around STRIKE,
## so each sits where the thumb can roll onto it. Powers appear as they are found.
func _layout() -> void:
	btns.clear()
	var s := size - Vector2(118, 116)
	btns.append({"id": "strike", "c": s, "r": 62.0})
	btns.append({"id": "dash", "c": s + Vector2(-150, 16), "r": 44.0})
	btns.append({"id": "bolt", "c": s + Vector2(-110, -104), "r": 44.0})
	var spots := [Vector2(8, -158), Vector2(-76, -198), Vector2(-198, -180)]
	var n := 0
	for id in ["nova", "spark", "ward"]:
		if game.powers[id]:
			btns.append({"id": id, "c": s + spots[n], "r": 36.0})
			n += 1
	btns.append({"id": "flask", "c": s + Vector2(-268, 58), "r": 34.0})
	btns.append({"id": "snuff", "c": s + Vector2(-300, -148), "r": 34.0})
	if game.near_prop != null:
		btns.append({"id": "use", "c": s + Vector2(-262, -52), "r": 40.0})
	btns.append({"id": "pause", "c": Vector2(size.x * 0.5 + 250.0, 30.0), "r": 22.0})


func _hit(p: Vector2) -> String:
	var best := ""
	var bd := 1e9
	for b in btns:
		var d: float = (p - b["c"]).length()
		# A little slack around each stone: thumbs are not cursors.
		if d < b["r"] + 12.0 and d - b["r"] < bd:
			bd = d - b["r"]
			best = b["id"]
	return best


func _input(ev: InputEvent) -> void:
	if not (ev is InputEventScreenTouch or ev is InputEventScreenDrag):
		return
	if not active():
		return
	var p: Vector2 = get_global_transform().affine_inverse() * ev.position
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_press(ev.index, p)
		else:
			_release(ev.index)
		get_viewport().set_input_as_handled()
	elif ev.index == stick_id:
		stick_p = p
		_update_stick()
	elif ev.index == cam_id or ev.index == pinch_id:
		var v = game.view3d
		if pinch_id != -1:
			# Two fingers: pinch to zoom.
			var before := cam_last.distance_to(pinch_last)
			if ev.index == cam_id:
				cam_last = p
			else:
				pinch_last = p
			var after := cam_last.distance_to(pinch_last)
			if v != null and v.active and before > 10.0 and after > 10.0:
				v.zoom_to = clampf(v.zoom_to * before / after, 0.55, 1.6)
		else:
			# A thumb dragged across the open right side turns the 3D camera.
			if v != null and v.active:
				v.yaw_to -= (p.x - cam_last.x) * 0.008
			cam_last = p
	elif held.has(ev.index) and (held[ev.index] == "strike" or held[ev.index] == "bolt"):
		var d: Vector2 = p - held_at[ev.index]
		if d.length() > 26.0:
			aiming = true
			aim = d.normalized()


func _press(idx: int, p: Vector2) -> void:
	_layout()
	var id := _hit(p)
	if id == "":
		if stick_id == -1 and p.x < size.x * 0.5:
			stick_id = idx
			stick_o = Vector2(clampf(p.x, STICK_R + 8.0, size.x * 0.5), clampf(p.y, STICK_R + 60.0, size.y - STICK_R - 8.0))
			stick_p = p
			_update_stick()
		elif game.view3d != null and game.view3d.active:
			if cam_id == -1:
				cam_id = idx
				cam_last = p
			elif pinch_id == -1:
				pinch_id = idx
				pinch_last = p
		return
	held[idx] = id
	held_at[idx] = p
	glow[id] = 1.0
	hud.buzz(12)
	match id:
		"strike":
			atk = true
			aiming = false
			game.atk_buf = 0.22
		"bolt":
			bolt = true
			aiming = false
			game.bolt_buf = 0.22
		"dash":
			game.try_dash()
		"nova":
			game.cast_nova()
		"spark":
			game.cast_spark()
		"ward":
			game.cast_ward()
		"flask":
			game.throw_flask()
		"snuff":
			game.toggle_snuff()
		"use":
			game.interact()
		"pause":
			hud.show_pause()


func _release(idx: int) -> void:
	if idx == pinch_id:
		pinch_id = -1
		return
	if idx == cam_id:
		# The pinching finger, if any, carries on turning.
		cam_id = pinch_id
		cam_last = pinch_last
		pinch_id = -1
		return
	if idx == stick_id:
		stick_id = -1
		move = Vector2.ZERO
		return
	if not held.has(idx):
		return
	var id: String = held[idx]
	held.erase(idx)
	held_at.erase(idx)
	if not held.values().has(id):
		if id == "strike":
			atk = false
		elif id == "bolt":
			bolt = false
	if not atk and not bolt:
		aiming = false


func _update_stick() -> void:
	var d := stick_p - stick_o
	var k := d.length() / STICK_R
	# A small dead zone, then full speed well before the rim: quick to answer.
	move = d.normalized() * clampf((k - 0.16) / 0.5, 0.0, 1.0) if k > 0.16 else Vector2.ZERO


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	if not active():
		if stick_id != -1 or not held.is_empty():
			reset()
	for id in glow:
		glow[id] = maxf(0.0, glow[id] - dt * 5.0)
	queue_redraw()


# --- Drawing ----------------------------------------------------------------------

## A square with its corners cut off: reads as cut stone, and stays crisp in pixels.
func _stone(c: Vector2, r: float) -> PackedVector2Array:
	var k := r * 0.42
	return PackedVector2Array([c + Vector2(-k, -r), c + Vector2(k, -r), c + Vector2(r, -k), c + Vector2(r, k),
		c + Vector2(k, r), c + Vector2(-k, r), c + Vector2(-r, k), c + Vector2(-r, -k)])


## The part of a stone that lies below a given height (the cooldown shade).
func _stone_below(c: Vector2, r: float, top: float) -> PackedVector2Array:
	var k := r * 0.42
	var ys: Array = [maxf(top, c.y - r)]
	for y in [c.y - k, c.y + k, c.y + r]:
		if y > ys[0] + 0.5:
			ys.append(y)
	var pts := PackedVector2Array()
	for y in ys:
		pts.append(Vector2(c.x + _half(r, k, y - c.y), y))
	for i in range(ys.size() - 1, -1, -1):
		pts.append(Vector2(c.x - _half(r, k, ys[i] - c.y), ys[i]))
	return pts


func _half(r: float, k: float, dy: float) -> float:
	return r if absf(dy) <= k else r - (absf(dy) - k)


func _outline(pts: PackedVector2Array, col: Color, w: float) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, col, w)


func _draw() -> void:
	if game == null or not is_instance_valid(game) or game.dead or game.bot:
		return
	_layout()
	var ember: Color = hud.C_EMBER
	# The thumbstick: a faint ghost where it rests, solid once a thumb is on it.
	var on := stick_id != -1
	var so := stick_o if on else Vector2(150.0, size.y - 150.0)
	draw_colored_polygon(_stone(so, STICK_R), Color(0.05, 0.04, 0.07, 0.34 if on else 0.16))
	_outline(_stone(so, STICK_R), Color(C_EDGE.r, C_EDGE.g, C_EDGE.b, 0.7 if on else 0.3), 2.0)
	var knob := so + (stick_p - stick_o).limit_length(STICK_R) if on else so
	draw_colored_polygon(_stone(knob, 30.0), Color(0.16, 0.12, 0.1, 0.85 if on else 0.35))
	_outline(_stone(knob, 30.0), Color(ember.r, ember.g, ember.b, 0.9 if on else 0.35), 2.0)

	for b in btns:
		var id: String = b["id"]
		var c: Vector2 = b["c"]
		var r: float = b["r"]
		var cdk := 0.0
		var can_pay := true
		match id:
			"bolt":
				can_pay = game.oil >= 18.0
			"flask":
				can_pay = game.oil >= game.FLASK_COST
			"dash":
				if game.dash_stock <= 0:
					cdk = clampf(game.dash_cd / game.stats["dash_cd"], 0.0, 1.0)
			"nova", "spark", "ward":
				cdk = clampf(game.pcd[id] / (Story.POWERS[id]["cd"] * game.stats["cdr"]), 0.0, 1.0)
				can_pay = game.oil >= Story.POWERS[id]["cost"]
		var ready := can_pay and cdk <= 0.0
		var g: float = glow.get(id, 0.0)
		var down: bool = held.values().has(id)
		draw_colored_polygon(_stone(c, r), Color(0.05 + 0.2 * g, 0.04 + 0.12 * g, 0.07, 0.6 + 0.2 * g))
		match id:
			"use":
				var tex: Texture2D = Art.tex[USE_ICONS.get(game.near_prop["type"], "chest0")]
				var k := minf(46.0 / tex.get_width(), 46.0 / tex.get_height())
				var ts := tex.get_size() * k
				draw_texture_rect(tex, Rect2(c - ts * 0.5, ts), false)
			"pause":
				draw_rect(Rect2(c + Vector2(-8, -9), Vector2(5, 18)), hud.C_PARCH)
				draw_rect(Rect2(c + Vector2(3, -9), Vector2(5, 18)), hud.C_PARCH)
			_:
				var sc := r / 34.0
				draw_set_transform(c, 0.0, Vector2(sc, sc))
				hud._draw_icon(self, id, Vector2.ZERO, ready)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if cdk > 0.0:
			# The stone fills back up from the bottom as the power returns.
			var cut := _stone_below(c, r, c.y + r - 2.0 * r * cdk)
			if cut.size() >= 4:
				draw_colored_polygon(cut, Color(0, 0, 0, 0.55))
		var edge := C_EDGE
		if id == "use":
			edge = Color(ember.r, ember.g, ember.b, 0.75 + 0.25 * sin(hud.t * 6.0))
		elif ready and id != "pause":
			edge = Color(ember.r, ember.g, ember.b, 1.0 if down else 0.8)
		_outline(_stone(c, r), edge, 3.0 if down else 2.0)
		if id == "dash" and game.stats["dash_n"] > 1:
			for k in game.stats["dash_n"]:
				draw_rect(Rect2(c.x - 5.0 * game.stats["dash_n"] + k * 10.0 + 1.0, c.y + r - 14.0, 7, 5),
					Color(0.7, 0.95, 1.0) if k < game.dash_stock else Color(0.2, 0.25, 0.3))
	# While aiming by hand, a short tick shows which way the blow will go.
	if aiming and (atk or bolt):
		for b in btns:
			if (b["id"] == "strike" and atk) or (b["id"] == "bolt" and bolt and not atk):
				var c2: Vector2 = b["c"]
				draw_line(c2 + aim * (b["r"] + 6.0), c2 + aim * (b["r"] + 22.0), ember, 4.0)
