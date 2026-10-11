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


static func generate(depth: int, rng: RandomNumberGenerator) -> Dictionary:
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

	var spawns: Array = []
	var table: Array = TABLES[depth]
	for idx in order.size():
		var ri: int = order[idx]
		if ri == start_room:
			continue
		var r: Rect2i = rooms[ri]
		var n := 2 + int(r.get_area() / 24.0) + int((depth - 1) / 2.0)
		var tutorial := depth == 1 and idx == 1
		if tutorial:
			n = 2
		if ri == exit_room:
			n += 2
		n = mini(n, 8)
		for k in n:
			var kind := _pick(table, rng)
			if tutorial:
				kind = "husk"
			var t := Vector2i(rng.randi_range(r.position.x + 1, r.end.x - 2), rng.randi_range(r.position.y + 1, r.end.y - 2))
			spawns.append({"kind": kind, "tile": t, "room": ri, "elite": depth >= 2 and ri == exit_room and k < (2 if depth >= 5 else 1)})

	var props: Array = []
	var used := {}
	used[start] = true
	_prop(props, used, "stairs", _centeri(rooms[exit_room]))
	var n_rooms := rooms.size()
	_prop(props, used, "page", _free_tile(rooms[order[maxi(1, int(n_rooms / 3.0))]], used, rng))
	_prop(props, used, "lamp", _free_tile(rooms[order[int(n_rooms / 2.0)]], used, rng))
	_prop(props, used, "plaque", _free_tile(rooms[order[mini(n_rooms - 2, int(n_rooms * 2 / 3.0) + 1)]], used, rng))
	_prop(props, used, "relic", _free_tile(rooms[order[maxi(1, n_rooms - 3)]], used, rng))
	for k in 2:
		var ri: int = order[rng.randi_range(1, n_rooms - 1)]
		_prop(props, used, "chest", _free_tile(rooms[ri], used, rng))
	for ri in rooms.size():
		var r: Rect2i = rooms[ri]
		var corners := [r.position, Vector2i(r.end.x - 1, r.position.y), Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i(1, 1)]
		var c0 := rng.randi() % 4
		_prop(props, used, "brazier", corners[c0])
		if rng.randf() < 0.65:
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
		"exit_room": exit_room, "spawns": spawns, "props": props, "boss": false}


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


static func _free_tile(r: Rect2i, used: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	for i in 30:
		var t := Vector2i(rng.randi_range(r.position.x + 1, r.end.x - 2), rng.randi_range(r.position.y + 1, r.end.y - 2))
		if not used.has(t):
			return t
	return r.position + Vector2i(1, 1)
