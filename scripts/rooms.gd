extends Node
## Set-aside rooms and the second stair, as they behave in play: the shrine's
## bargains, the oil cache that springs an ambush, the vault that opens when its
## keeper falls, the dark room's hoard, the cursed altar, and the lamp that
## drinks faster the longer Wren lingers on a floor whose way down is open.
## Dungeon.generate decides where they are; game.gd hands their props here.

const Art = preload("res://scripts/art.gd")
const Dungeon = preload("res://scripts/dungeon.gd")
const Story = preload("res://scripts/story.gd")

## The prop types handled here, and what the prompt says over each.
const PROMPTS := {"shrine": "Kneel at the shrine", "cache": "Take the oil", "hoard": "Open the hoard",
	"altar": "Touch the altar", "vgate": "Locked"}
const MARK_COL := {"shrine": Color(0.45, 1.0, 0.9, 0.5), "cache": Color(1.0, 0.65, 0.2, 0.55),
	"dark": Color(0.62, 0.45, 1.0, 0.5), "altar": Color(1.0, 0.25, 0.3, 0.55)}
## Seconds after the way down opens before the lamp starts drinking faster,
## how long until it drinks its fastest, and how much faster that is (oil per
## second beyond cancelling the flask's own refilling).
const LINGER := 60.0
const LINGER_RAMP := 90.0
const LINGER_DRAIN := 2.0
## An ambush lets go after this long even if its foes are still about.
const AMBUSH_MAX := 45.0
const SHRINE_EMBERS := 30
const TS := 16

var g
var kinds: Array = []
var route := ""
var route_room := -1
var route_tile := Vector2i(-1, -1)
var route_sealed := false
var vault_room := -1
var vault_open := true
var keeper = null
var keeper_idx := -1
var wave: Array = []
var seal_tiles: Array = []
var seal_nodes: Array = []
var ambush_t := 0.0
var cursed := false
var linger_t := 0.0
var linger_said := false
var route_said := false
var scan_t := 0.0


## Called as the floor is grown, before the map is painted: the vault stays
## walled up unless its keeper already fell.
func setup(restore: Dictionary) -> void:
	for n in seal_nodes:
		if is_instance_valid(n):
			n.queue_free()
	seal_nodes.clear()
	seal_tiles.clear()
	wave.clear()
	keeper = null
	keeper_idx = -1
	cursed = false
	linger_t = 0.0
	linger_said = false
	route_said = false
	route_sealed = false
	route_tile = Vector2i(-1, -1)
	var d: Dictionary = g.dungeon
	kinds = d.get("kinds", [])
	route = g.floor_route
	route_room = d.get("route_room", -1)
	vault_room = d.get("vault", -1)
	var slist: Array = d["spawns"]
	for i in slist.size():
		if slist[i].get("keeper", false):
			keeper_idx = i
	var gone: Array = g._ints(restore.get("dead_spawns", []))
	vault_open = vault_room < 0 or gone.has(keeper_idx)
	if not vault_open:
		for t in d.get("vault_doors", []):
			g.tiles[t.y * g.W + t.x] = 0


## Called once the floor's props and foes are in place.
func after_load() -> void:
	for e in g.enemies:
		if e.spawn_idx >= 0 and e.spawn_idx == keeper_idx:
			_make_keeper(e)
		# Foes past the bloody stair carry more.
		if route == "blood" and e.spawn_idx >= 0:
			e.xp = int(ceil(e.xp * 1.5))
	if vault_open:
		for p in g.props:
			if p["type"] == "vgate" and not p["done"]:
				p["done"] = true
				p["node"].queue_free()
	route_sealed = _held(route_room)


## The keeper is tougher than the floor's other elites, and carries a light
## that says so.
func _make_keeper(e) -> void:
	keeper = e
	e.hp *= 1.4
	e.max_hp = e.hp
	var gl := Sprite2D.new()
	gl.texture = Art.tex["glow"]
	gl.material = Art.mat_add
	gl.modulate = Color(1.0, 0.8, 0.3, 0.7)
	gl.scale = Vector2(0.22, 0.22)
	gl.position = Vector2(0, -e.cy * 2.0 - 8.0)
	e.add_child(gl)


func room_at(t: Vector2i) -> int:
	if t.x < 0 or t.y < 0 or t.x >= g.W or t.y >= g.H:
		return -1
	return g.room_id[t.y * g.W + t.x]


func kind_at(t: Vector2i) -> String:
	var ri := room_at(t)
	return kinds[ri] if ri >= 0 and ri < kinds.size() else ""


func _held(ri: int) -> bool:
	if ri < 0:
		return false
	for e in g.enemies:
		if not e.dead and e.room == ri:
			return true
	return false


## Whether this stair is shut: the usual one by the foes of its room (the
## game's own seal), the second one by the foes of its own.
func stair_sealed(p: Dictionary) -> bool:
	return route_sealed if p.has("route") else g.sealed


# --- Props ---------------------------------------------------------------------

func _emi(node: Node2D, s: Sprite2D, id: String) -> Sprite2D:
	var em := Sprite2D.new()
	em.texture = Art.tex[id + "_e"]
	em.material = Art.mat_unlit
	em.offset = s.offset
	node.add_child(em)
	return em


## Builds the look of one of this file's props. game._add_prop has made the node
## and the bare sprite.
func add_prop(p: Dictionary, pd: Dictionary) -> void:
	var node: Node2D = p["node"]
	var s: Sprite2D = p["spr"]
	match p["type"]:
		"shrine":
			s.texture = Art.tex["shrine"]
			g._stand(s)
			p["emi"] = _emi(node, s, "shrine")
			p["glow"] = g._glow(node, Color(0.45, 1.0, 0.9, 0.5), 0.5, Vector2(0, -16))
			p["light"] = g._light(node, Color(0.55, 1.0, 0.92), 0.8, 1.2, Vector2(0, -14))
		"cache":
			s.texture = Art.tex["cache"]
			g._stand(s)
			p["emi"] = _emi(node, s, "cache")
			p["glow"] = g._glow(node, Color(1.0, 0.6, 0.2, 0.35), 0.35, Vector2(0, -6))
			p["room"] = pd["room"]
		"hoard":
			s.texture = Art.tex["hoard0"]
			g._stand(s)
			p["emi"] = _emi(node, s, "hoard0")
			p["vault"] = pd.get("vault", false)
			# The dark room's hoard shows only its lock; the vault's gleams.
			if p["vault"]:
				p["glow"] = g._glow(node, Color(1.0, 0.8, 0.35, 0.45), 0.5, Vector2(0, -5))
		"altar":
			s.texture = Art.tex["altar"]
			g._stand(s)
			p["emi"] = _emi(node, s, "altar")
			p["glow"] = g._glow(node, Color(1.0, 0.2, 0.25, 0.5), 0.45, Vector2(0, -15))
			p["light"] = g._light(node, Color(1.0, 0.3, 0.3), 0.6, 0.9, Vector2(0, -13))
		"vgate":
			# Stood at the wall's near face, so the 3D view shows it too.
			node.position.y += 7.0
			s.texture = Art.tex["vgate"]
			g._stand(s)
			p["emi"] = _emi(node, s, "vgate")
			p["glow"] = g._glow(node, Color(1.0, 0.8, 0.3, 0.4), 0.3, Vector2(0, -7))
		"sign":
			s.texture = Art.tex["sign"]
			g._stand(s)
			var info: Dictionary = Story.ROUTES.get(pd["route"], Story.ROUTES["shrine"])
			var col: Color = info["col"]
			p["glow"] = g._glow(node, Color(col.r, col.g, col.b, 0.55), 0.4, Vector2(0, -30))
			var ic := Sprite2D.new()
			ic.texture = Art.tex[info["icon"]]
			ic.material = Art.mat_unlit
			ic.position = Vector2(0, -30)
			var big := maxf(ic.texture.get_width(), ic.texture.get_height())
			ic.scale = Vector2.ONE * minf(1.0, 13.0 / big)
			node.add_child(ic)
			p["icon"] = ic
		"mark":
			s.texture = Art.tex["sigil"]
			s.material = Art.mat_unlit
			s.modulate = MARK_COL.get(pd["kind"], Color.WHITE)
			s.position = pd.get("off", Vector2.ZERO)
			p["a"] = s.modulate.a


## A prop put back as it was when the floor was saved.
func restore_prop(p: Dictionary) -> void:
	match p["type"]:
		"shrine", "cache", "hoard", "altar":
			_spend(p)
			if p["type"] == "altar":
				cursed = true
		"vgate":
			p["done"] = true
			p["node"].queue_free()


func _spend(p: Dictionary) -> void:
	p["done"] = true
	var s: Sprite2D = p["spr"]
	match p["type"]:
		"shrine":
			s.texture = Art.tex["shrine1"]
		"cache":
			s.texture = Art.tex["cache1"]
		"hoard":
			s.texture = Art.tex["hoard1"]
		"altar":
			s.texture = Art.tex["altar1"]
	g._stand(s)
	for k in ["emi", "glow"]:
		if p.has(k):
			p[k].visible = false
	if p.has("light"):
		g.lights.erase(p["light"])
		p["light"].enabled = false


func animate(p: Dictionary, near: bool) -> void:
	var t: float = p["t"]
	match p["type"]:
		"shrine":
			p["glow"].modulate.a = 0.4 + 0.15 * sin(t * 2.4)
			if near and g.vis_at(p["pos"]) and g.rng.randf() < 0.1:
				g.fx.flame(p["pos"] + Vector2(0, -19), Color(0.5, 1.0, 0.92, 0.8))
		"altar":
			p["glow"].modulate.a = 0.4 + 0.2 * sin(t * 3.1)
			if near and g.rng.randf() < 0.05:
				g.fx.spark(p["pos"] + Vector2(0, -15), Color(1.0, 0.25, 0.3, 0.9), 1, 10.0, 0.8, 1.2, -12.0)
		"sign":
			p["icon"].position.y = -30.0 + sin(t * 2.0) * 1.5
			p["glow"].modulate.a = 0.45 + 0.15 * sin(t * 2.0)
		"mark":
			p["spr"].modulate.a = p["a"] * (0.75 + 0.25 * sin(t * 1.6))


func prompt_for(p: Dictionary) -> String:
	return PROMPTS[p["type"]]


# --- What they do ------------------------------------------------------------

func interact(p: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	match p["type"]:
		"shrine":
			_shrine(p)
		"cache":
			_spend(p)
			Sfx.play("oil")
			Sfx.play("coins", -4.0)
			g.fx.spark(pos + Vector2(0, -6), Color(1.0, 0.65, 0.25), 18, 70.0, 0.6, 2.0)
			g.drop("oil", pos + Vector2(0, 6), 3)
			g.drop("cinder", pos + Vector2(0, 6), g.rng.randi_range(6, 10))
			g.main.bank(15)
			_spring(p)
		"hoard":
			_spend(p)
			Sfx.play("chest")
			Sfx.play("coins")
			Sfx.play("jingle", -6.0)
			g.fx.spark(pos + Vector2(0, -4), Color(1.0, 0.85, 0.4), 26, 85.0, 0.7, 2.0)
			g.drop("cinder", pos + Vector2(0, 4), g.rng.randi_range(14, 20))
			g.drop("heart", pos + Vector2(-4, 4))
			g.drop("oil", pos + Vector2(4, 4))
			if p["vault"]:
				g.main.bank(30)
				g.hud.say("The keeper's hoard. (+30 embers)", 3.5, g.hud.C_EMBER)
				g.cine(4.2, 1.0, pos + Vector2(0, -6))
				g._offer_boons("The keeper's hoard", "Kindling, kept back from the dark. Take one.")
			else:
				g.drop("heart", pos + Vector2(0, 8))
				g.main.bank(20)
				g.hud.say("Richer for the dark it was kept in. (+20 embers)", 3.5, g.hud.C_EMBER)
		"altar":
			Sfx.play("ember", -4.0)
			g.hud.show_choice("A cursed altar", "It gives. Then it takes, for as long as you stay.", Story.ALTAR,
				func(i): _altar(p, i))
		"vgate":
			Sfx.play("thud", -8.0)
			g.hud.say("Locked. Its keeper walks this floor; it carries the key in its light.", 3.5, g.hud.C_EMBER)


func _shrine(p: Dictionary) -> void:
	Sfx.play("chime", -6.0)
	var opts: Array = []
	for o in Story.SHRINE:
		var c: Dictionary = o.duplicate()
		if not _can_afford(c["id"]):
			c["desc"] = c["desc"] + "\n\n(You haven't it to give.)"
			c["col"] = Color(0.5, 0.46, 0.42)
		opts.append(c)
	g.hud.show_choice("The keepers' shrine", "It will hear one asking, once.", opts,
		func(i): _bargain(p, opts[i]["id"]), func(): g.hud._close_modal(), "Leave it be")


func _can_afford(id: String) -> bool:
	match id:
		"blood":
			return g.hp > 2
		"embers":
			return int(g.main.profile["embers"]) >= SHRINE_EMBERS
	return true


func _bargain(p: Dictionary, id: String) -> void:
	if not _can_afford(id):
		Sfx.play("thud", -8.0)
		g.hud.say("The shrine waits. You haven't that to give.", 3.0)
		return
	var pos: Vector2 = p["pos"]
	match id:
		"blood":
			g.hp -= 2
			g.max_oil += 20.0
			g.oil = g.max_oil
			Sfx.play("oil")
			g.hud.float_text(g.ppos + Vector2(0, -18), "+20 flask", Color(1.0, 0.7, 0.25))
		"embers":
			g.main.profile["embers"] = int(g.main.profile["embers"]) - SHRINE_EMBERS
			g.main.profile_dirty = true
			g.hp = g.max_hp
			Sfx.play("heart")
			g.hud.float_text(g.ppos + Vector2(0, -18), "-%d embers" % SHRINE_EMBERS, Color(1.0, 0.72, 0.35))
		"pray":
			g.hp = mini(g.max_hp, g.hp + 1)
			g.oil = g.max_oil
			Sfx.play("heart")
	_spend(p)
	Sfx.play("chime", -2.0)
	g.fx.spark(pos + Vector2(0, -16), Color(0.55, 1.0, 0.92), 22, 60.0, 0.8, 1.8, -30.0)
	g.fx.ring(pos, 4.0, 40.0, 0.6, Color(0.5, 1.0, 0.9), false, 2.0)
	g.hud.say("The cold flame bows, and goes out.", 3.0)


func _altar(p: Dictionary, i: int) -> void:
	if Story.ALTAR[i]["id"] != "take":
		return
	_spend(p)
	cursed = true
	Sfx.play("power", -2.0)
	Sfx.play("roar", -10.0)
	g.fx.spark(p["pos"] + Vector2(0, -14), Color(1.0, 0.25, 0.3), 26, 80.0, 0.8, 2.0)
	g.add_shake(3.0)
	g.hud.say("The lamp tastes of ash. It won't refill itself on this floor.", 4.5, Color(1.0, 0.45, 0.45))
	g._offer_boons("The altar's gift", "Take one. The lamp will thirst for it.")


## The cache was bait: the doorways wall up and the room fills.
func _spring(p: Dictionary) -> void:
	var ri: int = p["room"]
	var r: Rect2i = g.dungeon["rooms"][ri]
	seal_tiles = Dungeon.doorways(g.tiles, g.W, g.H, r)
	for t in seal_tiles:
		g.tiles[t.y * g.W + t.x] = 0
	# Nobody may be left standing in a doorway that is now a wall.
	var pt := Vector2i(int(g.ppos.x / TS), int(g.ppos.y / TS))
	if seal_tiles.has(pt):
		g.teleport(g.tile_center(_inside(r, pt)))
	for e in g.enemies:
		var et := Vector2i(int(e.position.x / TS), int(e.position.y / TS))
		if not e.dead and seal_tiles.has(et):
			e.position = g.tile_center(_inside(r, et))
	_rebuild()
	for t in seal_tiles:
		var n := Node2D.new()
		n.position = g.tile_center(t) + Vector2(0, 7)
		var s := Sprite2D.new()
		s.texture = Art.tex["ward"]
		s.material = Art.mat_unlit
		g._stand(s)
		n.add_child(s)
		g._glow(n, Color(1.0, 0.5, 0.15, 0.5), 0.35, Vector2(0, -7))
		g.ents.add_child(n)
		seal_nodes.append(n)
		g.fx.spark(n.position + Vector2(0, -6), Color(1.0, 0.6, 0.2), 8, 50.0, 0.5, 1.5)
	# They come up out of the dark corners, away from Wren.
	var table: Array = Dungeon.TABLES[clampi(g.depth, 1, 6)]
	var n_foes: int = 2 + int(g.depth / 2.0) + (1 if route == "blood" else 0)
	for k in n_foes:
		var at: Vector2 = g.tile_center(_corner_tile(r, g.ppos))
		var e = g.spawn_enemy(Dungeon._pick(table, g.rng), at, ri, k == 0 and g.depth >= 4)
		e.awake = true
		g.fx.spark(e.center(), Color(0.6, 0.3, 0.9, 0.8), 12, 50.0, 0.6, 2.0, -20.0)
		wave.append(e)
	ambush_t = 0.0
	Sfx.play("lock")
	Sfx.play("gong", -4.0)
	Sfx.play("roar", -6.0)
	g.add_shake(5.0)
	g.kick(-0.08)
	g.hud.say_now("The doorways seal. It was bait.", 3.5, g.hud.C_EMBER)


func _inside(r: Rect2i, t: Vector2i) -> Vector2i:
	return Vector2i(clampi(t.x, r.position.x, r.end.x - 1), clampi(t.y, r.position.y, r.end.y - 1))


## A tile in the room as far from p as a few tries can find.
func _corner_tile(r: Rect2i, p: Vector2) -> Vector2i:
	var best := r.position
	var bd := -1.0
	for i in 6:
		var t := Vector2i(g.rng.randi_range(r.position.x, r.end.x - 1), g.rng.randi_range(r.position.y, r.end.y - 1))
		var d: float = (g.tile_center(t) - p).length()
		if d > bd:
			bd = d
			best = t
	return best


func _unseal() -> void:
	for t in seal_tiles:
		g.tiles[t.y * g.W + t.x] = 1
	for n in seal_nodes:
		if is_instance_valid(n):
			g.fx.spark(n.position + Vector2(0, -6), Color(1.0, 0.6, 0.2), 8, 40.0, 0.5, 1.5)
			n.queue_free()
	seal_nodes.clear()
	seal_tiles.clear()
	wave.clear()
	_rebuild()
	Sfx.play("lock")
	Sfx.play("chime", -4.0)
	g.hud.say("The wards on the doorways gutter out.", 3.5, g.hud.C_EMBER)


func open_vault(quiet: bool = false) -> void:
	if vault_open:
		return
	vault_open = true
	for t in g.dungeon.get("vault_doors", []):
		g.tiles[t.y * g.W + t.x] = 1
	for p in g.props:
		if p["type"] == "vgate" and not p["done"]:
			p["done"] = true
			if not quiet:
				g.fx.spark(p["pos"] + Vector2(0, -4), Color(1.0, 0.8, 0.35), 10, 60.0, 0.6, 2.0, 120.0)
			p["node"].queue_free()
	if quiet:
		return
	_rebuild()
	Sfx.play("lock")
	Sfx.play("bell", -6.0)
	g.hud.say_now("Somewhere close, a lock gives. The vault stands open.", 4.0, g.hud.C_EMBER)
	g.cine(3.4, 1.4, g.tile_center(Dungeon._centeri(g.dungeon["rooms"][vault_room])))


func _rebuild() -> void:
	g.map_rev += 1
	g._paint_map()
	g._update_fov()
	g._update_flow()


# --- Every frame -------------------------------------------------------------

func tick(dt: float) -> void:
	if g.depth <= 0 or g.dead:
		return
	if keeper != null and (not is_instance_valid(keeper) or keeper.dead):
		keeper = null
		open_vault()
	if not wave.is_empty():
		ambush_t += dt
		var alive := false
		for e in wave:
			if is_instance_valid(e) and not e.dead:
				alive = true
				break
		if not alive or ambush_t > AMBUSH_MAX:
			_unseal()
	# The altar's curse: whatever the flask gives back by itself, it loses again.
	var regen: float = g.stats["oil_regen"] * (3.0 if g.snuffed else 1.0)
	if cursed:
		g.oil = maxf(0.0, g.oil - regen * dt)
	_linger(dt, regen)
	scan_t -= dt
	if scan_t <= 0.0:
		scan_t = 0.25
		_scan()


## The pressure clock: once the way down is open, the dark starts counting.
## After a while the lamp stops refilling and then drains, which in time
## brings the gloams. A shrine's room stops the count.
func _linger(dt: float, regen: float) -> void:
	if g.depth < 2 or g.depth >= Dungeon.LAST or g.sealed or g.bot or g.god:
		return
	if kind_at(g.ptile) != "shrine":
		linger_t += dt
	var k := clampf((linger_t - LINGER) / LINGER_RAMP, 0.0, 1.0)
	if k <= 0.0:
		return
	if not linger_said:
		linger_said = true
		g.hud.say("The lamp's drinking faster. The dark knows how long I've stayed.", 4.5)
	g.oil = maxf(0.0, g.oil - (regen + LINGER_DRAIN) * k * dt)


func _scan() -> void:
	var held := _held(route_room)
	if route_sealed and not held:
		Sfx.play("lock")
		Sfx.play("chime", -4.0)
		g.hud.say("The seal on the far stair gutters out.", 3.5, g.hud.C_EMBER)
	route_sealed = held
	var kind := kind_at(g.ptile)
	if kind != "" and Story.ROOM_LINES.has(kind):
		g._say_once("room_" + kind, Story.ROOM_LINES[kind])
	if not route_said and route_tile.x >= 0 and g.vis[route_tile.y * g.W + route_tile.x] == 1 \
			and (g.tile_center(route_tile) - g.ppos).length() < 130.0:
		route_said = true
		var info: Dictionary = Story.ROUTES.get(route_next(), {})
		if not info.is_empty():
			g.hud.say(info["line"], 4.5)


## What this floor's second stair promises for the floor below.
func route_next() -> String:
	return g.dungeon.get("route_next", "")


## Arriving by the second stair: Wren is told what it bought.
func arrived() -> void:
	if route == "":
		return
	var info: Dictionary = Story.ROUTES.get(route, {})
	if route == Dungeon.LAST_ROUTE:
		g.hp = g.max_hp
		g.max_oil += 20.0
		g.oil = g.max_oil
	if not info.is_empty():
		g.hud.say("By the second stair: " + (info["name"] as String).to_lower() + ".", 4.0, info["col"])
