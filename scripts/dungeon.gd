extends RefCounted
## Procedural floor layouts: rooms, corridors, monsters and furniture.

const TABLES := {
	1: [["husk", 6], ["moth", 3]],
	2: [["husk", 4], ["moth", 3], ["cantor", 3]],
	3: [["slime", 4], ["cantor", 3], ["moth", 2], ["husk", 2], ["brute", 1]],
	4: [["wisp", 4], ["cantor", 3], ["husk", 3], ["brute", 2], ["slime", 2]],
	5: [["cantor", 4], ["brute", 3], ["wisp", 3], ["moth", 3], ["husk", 2]],
	6: [["wisp", 4], ["cantor", 4], ["brute", 3], ["slime", 3], ["husk", 3], ["moth", 2]],
}
## The floor that holds the Warden.
const LAST := 7
## What a floor's second stair can promise for the floor below it.
const ROUTES := ["shrine", "vault", "blood", "dark"]
## The last generated floor leads to the Warden, whose arena is not grown, so
## its second stair offers Wren something for the fight instead.
const LAST_ROUTE := "whole"
## Rooms a floor can set aside, besides ordinary ones (""). Quiet kinds hold no
## foes of their own.
const QUIET := ["shrine", "cache", "vault"]


## route: what the stair Wren came down promised for this floor ("" for the
## usual one). It is part of the floor's recipe, so a save keeps it with the seed.
static func generate(depth: int, rng: RandomNumberGenerator, route: String = "") -> Dictionary:
	if depth >= LAST:
		return _boss()
	if depth <= 0:
		return _gallery()
	var w := 54
	var h := 40
	var tiles := PackedByteArray()
	tiles.resize(w * h)
	var room_id := PackedInt32Array()
	room_id.resize(w * h)
	room_id.fill(-1)

	# Scatter rooms, rejecting any that crowd an earlier one.
	var rooms: Array = []
	var want := mini(12, 8 + depth)
	var tries := 0
	while rooms.size() < want and tries < 600:
		tries += 1
		var nr := Rect2i(0, 0, rng.randi_range(6, 11), rng.randi_range(5, 9))
		nr.position = Vector2i(rng.randi_range(2, w - nr.size.x - 3), rng.randi_range(3, h - nr.size.y - 3))
		var ok := true
		for o in rooms:
			if nr.grow(2).intersects(o):
				ok = false
				break
		if ok:
			rooms.append(nr)
	for i in rooms.size():
		var r: Rect2i = rooms[i]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				tiles[y * w + x] = 1
				room_id[y * w + x] = i

	# Join every room to its nearest earlier neighbour, then add a couple of loops.
	for i in range(1, rooms.size()):
		var best := 0
		var bd := 1e9
		for j in i:
			var d := _center(rooms[i]).distance_to(_center(rooms[j]))
			if d < bd:
				bd = d
				best = j
		_corridor(tiles, w, h, _centeri(rooms[i]), _centeri(rooms[best]), rng)
	for k in 2:
		var a := rng.randi() % rooms.size()
		var b := rng.randi() % rooms.size()
		if a != b:
			_corridor(tiles, w, h, _centeri(rooms[a]), _centeri(rooms[b]), rng)

	# Start in one room; the stair goes in whichever room is the longest walk away.
	var start_room := 0
	var start := _centeri(rooms[start_room])
	var dist := bfs(tiles, w, h, start)
	var order: Array = []
	for i in rooms.size():
		order.append(i)
	var room_dist: Array = []
	for i in rooms.size():
		var c := _centeri(rooms[i])
		room_dist.append(dist[c.y * w + c.x])
	order.sort_custom(func(x, y): return room_dist[x] < room_dist[y])
	var exit_room: int = order[order.size() - 1]
	var tut_room: int = order[1] if depth == 1 and order.size() > 1 else -1

	# A second way down, in another branch: the room furthest both from the
	# start and from the first stair. What waits below it is chosen now, so the
	# floor can show it before Wren commits.
	var exit_dist := bfs(tiles, w, h, _centeri(rooms[exit_room]))
	var route_room := -1
	var best_score := 0
	for i in rooms.size():
		if i == start_room or i == exit_room or i == tut_room:
			continue
		var c := _centeri(rooms[i])
		var score := mini(dist[c.y * w + c.x], exit_dist[c.y * w + c.x])
		if score > best_score:
			best_score = score
			route_room = i
	var route_next := ""
	if route_room >= 0:
		route_next = LAST_ROUTE if depth == LAST - 1 else ROUTES[rng.randi() % ROUTES.size()]

	# Some rooms are set aside. The first depth only gets a shrine: it is for
	# learning, not for ambushes.
	var kinds: Array = []
	kinds.resize(rooms.size())
	kinds.fill("")
	var pool: Array = []
	for i in order:
		if i != start_room and i != exit_room and i != route_room and i != tut_room:
			pool.append(i)
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var wanted: Array = []
	if depth >= 3 or route == "vault":
		wanted.append("vault")
	wanted.append("shrine")
	if route == "shrine":
		wanted.append("shrine")
	if depth >= 2:
		wanted.append("cache")
		for k in (3 if route == "dark" else 1):
			wanted.append("dark")
	if depth >= 3 and rng.randf() < 0.5:
		wanted.append("altar")
	var vault_room := -1
	var vault_doors: Array = []
	for kind in wanted:
		# Keep a few ordinary rooms for the lamp, the relic, the page, the plaque
		# and the vault's keeper. A dark room can hold a page or a chest itself.
		if pool.size() <= (2 if kind == "dark" else 3):
			continue
		var pick := -1
		for j in pool.size():
			if kind == "vault":
				# Locked until its keeper falls, so nothing else may lie behind it.
				var doors := doorways(tiles, w, h, rooms[pool[j]])
				if doors.is_empty() or not _reach_without(tiles, w, h, start, rooms, pool[j], doors):
					continue
				vault_doors = doors
			pick = j
			break
		if pick < 0:
			continue
		var ri: int = pool[pick]
		pool.remove_at(pick)
		kinds[ri] = kind
		if kind == "vault":
			vault_room = ri

	var spawns: Array = []
	var table: Array = TABLES[depth]
	for idx in order.size():
		var ri: int = order[idx]
		if ri == start_room or QUIET.has(kinds[ri]):
			continue
		var r: Rect2i = rooms[ri]
		var n := 2 + int(r.get_area() / 24.0) + int((depth - 1) / 2.0)
		var tutorial := depth == 1 and idx == 1
		if tutorial:
			n = 2
		# Both stairs are held.
		var held := ri == exit_room or ri == route_room
		if held:
			n += 2
		if kinds[ri] == "dark":
			n += 1
		if route == "blood":
			n += 1
		n = mini(n, 9 if route == "blood" else 8)
		for k in n:
			var kind := _pick(table, rng)
			if tutorial:
				kind = "husk"
			var t := Vector2i(rng.randi_range(r.position.x + 1, r.end.x - 2), rng.randi_range(r.position.y + 1, r.end.y - 2))
			spawns.append({"kind": kind, "tile": t, "room": ri, "elite": depth >= 2 and held and k < (2 if depth >= 5 else 1)})
	if vault_room >= 0:
		# The vault's keeper waits in the ordinary room nearest it.
		var vc := _center(rooms[vault_room])
		var kr: int = pool[0]
		for ri in pool:
			if _center(rooms[ri]).distance_to(vc) < _center(rooms[kr]).distance_to(vc):
				kr = ri
		var kind := _pick(table, rng)
		for k in 4:
			if kind != "moth":
				break
			kind = _pick(table, rng)
		spawns.append({"kind": kind, "tile": _centeri(rooms[kr]) + Vector2i(0, 1), "room": kr, "elite": true, "keeper": true})

	var props: Array = []
	var used := {}
	used[start] = true
	_prop(props, used, "stairs", _centeri(rooms[exit_room]))
	if route_room >= 0:
		var rt := _centeri(rooms[route_room])
		_prop_d(props, used, {"type": "stairs", "tile": rt, "route": route_next})
		_prop_d(props, used, {"type": "sign", "tile": rt + Vector2i(1, -1), "route": route_next})
	var n_rooms := rooms.size()
	_prop(props, used, "page", _free_tile(rooms[_plain(order, maxi(1, int(n_rooms / 3.0)), kinds, true)], used, rng))
	_prop(props, used, "lamp", _free_tile(rooms[_plain(order, int(n_rooms / 2.0), kinds, false)], used, rng))
	_prop(props, used, "plaque", _free_tile(rooms[_plain(order, mini(n_rooms - 2, int(n_rooms * 2 / 3.0) + 1), kinds, true)], used, rng))
	_prop(props, used, "relic", _free_tile(rooms[_plain(order, maxi(1, n_rooms - 3), kinds, false)], used, rng))
	for k in 2:
		var ri: int = _plain(order, rng.randi_range(1, n_rooms - 1), kinds, true)
		_prop(props, used, "chest", _free_tile(rooms[ri], used, rng))
	for t in vault_doors:
		_prop_d(props, used, {"type": "vgate", "tile": t})
	for ri in rooms.size():
		var kind: String = kinds[ri]
		var r: Rect2i = rooms[ri]
		var mid := _centeri(r)
		match kind:
			"shrine":
				_prop_d(props, used, {"type": "shrine", "tile": mid})
			"cache":
				_prop_d(props, used, {"type": "cache", "tile": mid, "room": ri})
			"vault":
				_prop_d(props, used, {"type": "hoard", "tile": mid, "vault": true})
			"dark":
				_prop_d(props, used, {"type": "hoard", "tile": _free_tile(r, used, rng), "dark": true})
			"altar":
				_prop_d(props, used, {"type": "altar", "tile": mid})
		if kind != "" and kind != "vault":
			_mark_doors(props, used, doorways(tiles, w, h, r), r, kind)
	for ri in rooms.size():
		var r: Rect2i = rooms[ri]
		var corners := [r.position, Vector2i(r.end.x - 1, r.position.y), Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i(1, 1)]
		var c0 := rng.randi() % 4
		# A dark room keeps no fire of its own; a dark floor keeps less of it.
		if kinds[ri] != "dark":
			_prop(props, used, "brazier", corners[c0])
		if kinds[ri] != "dark" and rng.randf() < (0.2 if route == "dark" else 0.65):
			_prop(props, used, "brazier", corners[3 - c0])
		for k in rng.randi_range(0, 3):
			var t := Vector2i.ZERO
			match rng.randi() % 4:
				0: t = Vector2i(rng.randi_range(r.position.x, r.end.x - 1), r.position.y)
				1: t = Vector2i(rng.randi_range(r.position.x, r.end.x - 1), r.end.y - 1)
				2: t = Vector2i(r.position.x, rng.randi_range(r.position.y, r.end.y - 1))
				3: t = Vector2i(r.end.x - 1, rng.randi_range(r.position.y, r.end.y - 1))
			_prop(props, used, "urn", t)

	return {"w": w, "h": h, "tiles": tiles, "room_id": room_id, "rooms": rooms, "start": start,
		"exit_room": exit_room, "spawns": spawns, "props": props, "boss": false,
		"kinds": kinds, "route": route, "route_room": route_room, "route_next": route_next,
		"vault": vault_room, "vault_doors": vault_doors}


## The last floor is hand-built: a small antechamber, a short passage, and the forge.
static func _boss() -> Dictionary:
	var w := 41
	var h := 46
	var tiles := PackedByteArray()
	tiles.resize(w * h)
	var room_id := PackedInt32Array()
	room_id.resize(w * h)
	room_id.fill(-1)
	var c := Vector2i(20, 17)
	for y in h:
		for x in w:
			var dx := x - c.x
			var dy := y - c.y
			if dx * dx + dy * dy <= 125:
				tiles[y * w + x] = 1
				room_id[y * w + x] = 1
	for y in range(27, 38):
		for x in range(19, 22):
			tiles[y * w + x] = 1
	var entry := Rect2i(16, 37, 9, 5)
	for y in range(entry.position.y, entry.end.y):
		for x in range(entry.position.x, entry.end.x):
			tiles[y * w + x] = 1
			room_id[y * w + x] = 0
	var props: Array = []
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		props.append({"type": "brazier", "tile": Vector2i(c.x + roundi(cos(a) * 9.0), c.y + roundi(sin(a) * 9.0))})
	props.append({"type": "brazier", "tile": Vector2i(16, 37)})
	props.append({"type": "brazier", "tile": Vector2i(24, 37)})
	props.append({"type": "cage", "tile": Vector2i(20, 8)})
	return {"w": w, "h": h, "tiles": tiles, "room_id": room_id, "rooms": [entry, Rect2i(9, 6, 23, 23)],
		"start": Vector2i(20, 40), "exit_room": -1,
		"spawns": [{"kind": "warden", "tile": Vector2i(20, 16), "room": 1}], "props": props, "boss": true}


## One big lit hall, for the showcase.
static func _gallery() -> Dictionary:
	var w := 44
	var h := 28
	var tiles := PackedByteArray()
	tiles.resize(w * h)
	var room_id := PackedInt32Array()
	room_id.resize(w * h)
	room_id.fill(-1)
	var hall := Rect2i(6, 6, 32, 16)
	for y in range(hall.position.y, hall.end.y):
		for x in range(hall.position.x, hall.end.x):
			tiles[y * w + x] = 1
			room_id[y * w + x] = 0
	var props: Array = []
	for x in range(hall.position.x, hall.end.x, 5):
		props.append({"type": "brazier", "tile": Vector2i(x + 1, hall.position.y)})
		props.append({"type": "brazier", "tile": Vector2i(x + 1, hall.end.y - 1)})
	for y in [10, 14, 18]:
		props.append({"type": "brazier", "tile": Vector2i(hall.position.x, y)})
		props.append({"type": "brazier", "tile": Vector2i(hall.end.x - 1, y)})
	return {"w": w, "h": h, "tiles": tiles, "room_id": room_id, "rooms": [hall], "start": Vector2i(22, 14),
		"exit_room": -1, "spawns": [], "props": props, "boss": false}


static func bfs(tiles: PackedByteArray, w: int, h: int, start: Vector2i) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(99999)
	var q := PackedInt32Array()
	q.resize(w * h)
	var head := 0
	var tail := 0
	var s := start.y * w + start.x
	dist[s] = 0
	q[tail] = s
	tail += 1
	while head < tail:
		var i := q[head]
		head += 1
		var d := dist[i] + 1
		for o in [1, -1, w, -w]:
			var j: int = i + o
			if j < 0 or j >= w * h:
				continue
			if tiles[j] == 1 and dist[j] > d:
				dist[j] = d
				q[tail] = j
				tail += 1
	return dist


static func _center(r: Rect2i) -> Vector2:
	return Vector2(r.position) + Vector2(r.size) * 0.5


static func _centeri(r: Rect2i) -> Vector2i:
	return r.position + r.size / 2


static func _carve(tiles: PackedByteArray, w: int, h: int, x: int, y: int) -> void:
	if x >= 1 and y >= 2 and x < w - 1 and y < h - 1:
		tiles[y * w + x] = 1


static func _corridor(tiles: PackedByteArray, w: int, h: int, a: Vector2i, b: Vector2i, rng: RandomNumberGenerator) -> void:
	if rng.randf() < 0.5:
		_hline(tiles, w, h, a.x, b.x, a.y)
		_vline(tiles, w, h, a.y, b.y, b.x)
	else:
		_vline(tiles, w, h, a.y, b.y, a.x)
		_hline(tiles, w, h, a.x, b.x, b.y)


static func _hline(tiles: PackedByteArray, w: int, h: int, x0: int, x1: int, y: int) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 2):
		_carve(tiles, w, h, x, y)
		_carve(tiles, w, h, x, y + 1)


static func _vline(tiles: PackedByteArray, w: int, h: int, y0: int, y1: int, x: int) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 2):
		_carve(tiles, w, h, x, y)
		_carve(tiles, w, h, x + 1, y)


static func _pick(table: Array, rng: RandomNumberGenerator) -> String:
	var total := 0
	for e in table:
		total += e[1]
	var roll := rng.randi() % total
	for e in table:
		roll -= e[1]
		if roll < 0:
			return e[0]
	return table[0][0]


static func _prop(props: Array, used: Dictionary, type: String, tile: Vector2i) -> void:
	if used.has(tile):
		return
	used[tile] = true
	props.append({"type": type, "tile": tile})


static func _prop_d(props: Array, used: Dictionary, d: Dictionary) -> void:
	if used.has(d["tile"]):
		return
	used[d["tile"]] = true
	props.append(d)


## The room at this place in walk order, or the nearest one to it that is
## plain enough for the floor's usual furniture (a dark room will do for a
## chest or a page, but not for the wayside lamp or the relic).
static func _plain(order: Array, idx: int, kinds: Array, dark_ok: bool) -> int:
	var n := order.size()
	for k in n:
		for j in [idx + k, idx - k]:
			if j < 1 or j >= n:
				continue
			var kind: String = kinds[order[j]]
			if kind == "" or (dark_ok and kind == "dark"):
				return order[j]
	return order[clampi(idx, 1, n - 1)]


## The floor tiles just outside a room's edge: where the corridors come in.
static func doorways(tiles: PackedByteArray, w: int, _h: int, r: Rect2i) -> Array:
	var out: Array = []
	var g := r.grow(1)
	for y in range(g.position.y, g.end.y):
		for x in range(g.position.x, g.end.x):
			if not r.has_point(Vector2i(x, y)) and tiles[y * w + x] == 1:
				out.append(Vector2i(x, y))
	return out


## Whether every other room can still be walked to from the start with this
## room's doorways walled up.
static func _reach_without(tiles: PackedByteArray, w: int, h: int, start: Vector2i, rooms: Array, skip: int, doors: Array) -> bool:
	var t2 := tiles.duplicate()
	for d in doors:
		t2[d.y * w + d.x] = 0
	var dist := bfs(t2, w, h, start)
	for i in rooms.size():
		var c := _centeri(rooms[i])
		if i != skip and dist[c.y * w + c.x] >= 99999:
			return false
	return true


## A sigil on the floor at each way into a set-aside room, in its colour, so
## the room reads before Wren steps in.
static func _mark_doors(props: Array, used: Dictionary, doors: Array, r: Rect2i, kind: String) -> void:
	var g := r.grow(1)
	for t in doors:
		var horiz: bool = t.y == g.position.y or t.y == g.end.y - 1
		var vert: bool = t.x == g.position.x or t.x == g.end.x - 1
		if horiz and vert:
			continue
		var step := Vector2i(1, 0) if horiz else Vector2i(0, 1)
		# One sigil per way in, at the first tile of each run of doorway.
		if doors.has(t - step):
			continue
		_prop_d(props, used, {"type": "mark", "tile": t, "kind": kind,
			"off": Vector2(step) * 8.0 if doors.has(t + step) else Vector2.ZERO})


static func _free_tile(r: Rect2i, used: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	for i in 30:
		var t := Vector2i(rng.randi_range(r.position.x + 1, r.end.x - 2), rng.randi_range(r.position.y + 1, r.end.y - 2))
		if not used.has(t):
			return t
	return r.position + Vector2i(1, 1)
