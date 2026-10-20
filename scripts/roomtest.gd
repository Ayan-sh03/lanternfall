extends Node
## Checks for set-aside rooms and the second stair: that every grown floor can
## be walked (with the vault shut), that each room kind turns up as often as it
## should and does what it says, and that a save brings the same floor back.
## Run alone with:  godot --path . -- --autotest --rooms [--shotdir=<dir>]
## The mechanics check (--mechanics) runs it too. Exits 1 if anything fails.

const Dungeon = preload("res://scripts/dungeon.gd")
const RoomsS = preload("res://scripts/rooms.gd")
const Story = preload("res://scripts/story.gd")

var main
var at
var fails := 0


func check(ok: bool, what: String) -> void:
	print("ROOMS %s %s" % [what, "ok" if ok else "FAIL"])
	if not ok:
		fails += 1


func w(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func until(cond: Callable, sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await get_tree().process_frame


## Alone: a fresh descent, the checks, and out.
func run() -> void:
	main.slot = 9
	await w(0.5)
	main.hud._close_modal()
	main.new_game(1)
	await w(2.5)
	var n := await run_checks()
	print("ROOMS %s" % ("PASS" if n == 0 else "FAIL %d" % n))
	main.delete_save(9)
	get_tree().quit(1 if n > 0 else 0)


## Every check, on the game that is running. Returns how many failed.
func run_checks() -> int:
	fails = 0
	_generation()
	var g = main.game
	g.bot = true
	g.bot_manual = true
	g.hud.hint_t = 0.0
	# No level-up choices popping up between the checks.
	var xp_next: int = g.xp_next
	g.xp_next = 999999
	await _kinds_in_play(g)
	await _save_and_restore(g)
	await _second_stair(g)
	await _lingering(g)
	g.god = false
	g.xp_next = xp_next
	return fails


# --- Grown floors, without a game ------------------------------------------------

func _gen(d: int, s: int, route: String) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return Dungeon.generate(d, r, route)


func _count(fl: Dictionary, kind: String) -> int:
	return (fl["kinds"] as Array).count(kind)


## Fifty seeds of every depth, by each stair that can lead there.
func _generation() -> void:
	var seeds := 50
	var bad := {}
	var tally := {}
	var t0 := Time.get_ticks_msec()
	for d in range(1, Dungeon.LAST):
		var routes: Array = [""] if d == 1 else [""] + Dungeon.ROUTES
		for route in routes:
			for s in range(1, seeds + 1):
				var fl := _gen(d, s * 7919 + d, route)
				for why in _problems(fl, d, route):
					bad[why] = int(bad.get(why, 0)) + 1
				var key := "d%d%s" % [d, "" if route == "" else "/" + route]
				var tl: Dictionary = tally.get(key, {})
				for k in ["shrine", "cache", "vault", "dark", "altar"]:
					tl[k] = int(tl.get(k, 0)) + _count(fl, k)
				tl["n"] = int(tl.get("n", 0)) + 1
				tally[key] = tl
	for key in tally:
		var tl: Dictionary = tally[key]
		var n := float(tl["n"])
		print("ROOMS mix %-10s shrine %.2f cache %.2f vault %.2f dark %.2f altar %.2f" % [key,
			tl["shrine"] / n, tl["cache"] / n, tl["vault"] / n, tl["dark"] / n, tl["altar"] / n])
	for why in bad:
		print("ROOMS   %d floors: %s" % [bad[why], why])
	check(bad.is_empty(), "every grown floor is whole: rooms and both stairs reachable, the vault shut off cleanly, nothing in a wall (%d ms)" % (Time.get_ticks_msec() - t0))
	# How often each kind turns up, by depth and by the stair taken down.
	var ok := true
	for d in range(2, Dungeon.LAST):
		ok = ok and tally["d%d" % d]["cache"] >= seeds * 0.95
	for d in range(3, Dungeon.LAST):
		ok = ok and tally["d%d" % d]["vault"] >= seeds * 0.8
	check(ok, "from depth 2 nearly every floor has an oil cache, from depth 3 most have a vault")
	ok = tally["d2/vault"]["vault"] >= seeds * 0.8 and tally["d2"]["vault"] == 0
	check(ok, "the vault stair brings a vault to depth 2, where there is none otherwise (%d/%d)" % [tally["d2/vault"]["vault"], seeds])
	ok = true
	for d in range(2, Dungeon.LAST):
		ok = ok and tally["d%d/shrine" % d]["shrine"] >= seeds * 1.8 and tally["d%d/dark" % d]["dark"] >= seeds * 2.0
	check(ok, "the shrine stair brings two shrines, the dark stair two or more dark rooms")


## What is wrong with one grown floor, if anything.
func _problems(fl: Dictionary, d: int, route: String) -> Array:
	var out: Array = []
	var w: int = fl["w"]
	var h: int = fl["h"]
	var tiles: PackedByteArray = fl["tiles"]
	var rooms: Array = fl["rooms"]
	var kinds: Array = fl["kinds"]
	var start: Vector2i = fl["start"]
	var dist := Dungeon.bfs(tiles, w, h, start)
	for r in rooms:
		var c: Vector2i = r.position + r.size / 2
		if dist[c.y * w + c.x] >= 99999:
			out.append("a room cannot be reached")
	# The vault walled up, as the game does it.
	var shut := tiles.duplicate()
	for t in fl["vault_doors"]:
		shut[t.y * w + t.x] = 0
	var vault: int = fl["vault"]
	var sdist := Dungeon.bfs(shut, w, h, start)
	var vr: Rect2i = rooms[vault] if vault >= 0 else Rect2i()
	var stairs := 0
	var gates := 0
	for p in fl["props"]:
		var t: Vector2i = p["tile"]
		if tiles[t.y * w + t.x] != 1:
			out.append("a %s stands in a wall" % p["type"])
			continue
		if p["type"] == "vgate":
			gates += 1
			continue
		if sdist[t.y * w + t.x] >= 99999 and not (vault >= 0 and vr.has_point(t)) and p["type"] != "mark":
			out.append("a %s is cut off by the shut vault" % p["type"])
		if p["type"] == "stairs":
			stairs += 1
			if p.has("route") and not rooms[fl["route_room"]].has_point(t):
				out.append("the second stair is not in its room")
		if p["type"] == "brazier" and kinds[_room_of(rooms, t)] == "dark":
			out.append("a dark room has a brazier")
	if stairs != 2:
		out.append("%d stairs, not 2" % stairs)
	if vault >= 0 and gates != (fl["vault_doors"] as Array).size():
		out.append("a vault doorway has no gate")
	var keepers := 0
	for sd in fl["spawns"]:
		var t: Vector2i = sd["tile"]
		if tiles[t.y * w + t.x] != 1:
			out.append("a foe starts in a wall")
		if Dungeon.QUIET.has(kinds[sd["room"]]):
			out.append("a foe starts in a quiet room")
		if sdist[t.y * w + t.x] >= 99999:
			out.append("a foe is cut off by the shut vault")
		if sd.get("keeper", false):
			keepers += 1
	if keepers != (1 if vault >= 0 else 0):
		out.append("%d keepers for %d vaults" % [keepers, 1 if vault >= 0 else 0])
	var shrines := _count(fl, "shrine")
	if shrines < 1 or shrines > 2:
		out.append("%d shrines" % shrines)
	if d == 1:
		for k in ["cache", "vault", "dark", "altar"]:
			if _count(fl, k) > 0:
				out.append("depth 1 has a %s room" % k)
	var want_next: String = Dungeon.LAST_ROUTE if d == Dungeon.LAST - 1 else ""
	if want_next != "" and fl["route_next"] != want_next or want_next == "" and not Dungeon.ROUTES.has(fl["route_next"]):
		out.append("the second stair promises '%s'" % fl["route_next"])
	if fl["route"] != route:
		out.append("the floor forgot the stair it was reached by")
	return out


func _room_of(rooms: Array, t: Vector2i) -> int:
	for i in rooms.size():
		if rooms[i].has_point(t):
			return i
	return -1


## A seed whose floor at this depth has every one of these kinds of room.
func _seed_with(d: int, need: Array, route: String = "") -> int:
	for s in range(1, 2000):
		var fl := _gen(d, s, route)
		var ok := true
		for k in need:
			ok = ok and _count(fl, k) > 0
		if ok:
			return s
	return 1


# --- In play ---------------------------------------------------------------------

func _prop(g, type: String, extra: String = "") -> Variant:
	for p in g.props:
		if p["type"] == type and not p["done"] and (extra == "" or p.get(extra, false)):
			return p
	return null


## Walks up to a prop (as near as the floor allows) and uses it.
func _use(g, p) -> void:
	var at_p: Vector2 = p["pos"] + Vector2(0, 10)
	if g.solid_at(at_p):
		at_p = p["pos"]
	g.teleport(at_p)
	await get_tree().process_frame
	g.near_prop = p
	g.interact()
	await get_tree().process_frame


func _quiet_foes(g, keep = null) -> void:
	for e in g.enemies:
		if e != keep and not e.dead:
			e.dead = true
			e.visible = false


func _kinds_in_play(g) -> void:
	var s := _seed_with(4, ["shrine", "cache", "vault", "dark", "altar"])
	g.load_floor(4, {"seed": s})
	g.hud.card_t = 0.0
	await w(0.4)
	g.god = true
	var r = g.rooms
	var doors: Array = g.dungeon["vault_doors"]
	var shut: bool = not r.vault_open and not doors.is_empty()
	for t in doors:
		shut = shut and g.tiles[t.y * g.W + t.x] == 0
	check(shut, "the vault starts walled up (%d doorways)" % doors.size())
	check(r.keeper != null and r.keeper.elite, "its keeper waits, an elite")
	_quiet_foes(g, r.keeper)
	g.cam_script = true
	g.cam.zoom = Vector2(3.0, 3.0)

	# The shrine: a heart for a deeper flask.
	var p = _prop(g, "shrine")
	g.teleport(p["pos"] + Vector2(0, 30))
	await w(0.5)
	await at.shot("r_shrine")
	var hp0: int = g.hp
	var mo0: float = g.max_oil
	await _use(g, p)
	var asked: bool = main.hud.modal == "choice"
	await at.shot("r_shrine_choice")
	main.hud._choose(0)
	check(asked and g.hp == hp0 - 2 and g.max_oil == mo0 + 20.0 and p["done"],
		"the shrine trades a heart for a deeper flask (hp %d -> %d, flask %.0f -> %.0f)" % [hp0, g.hp, mo0, g.max_oil])
	check(_prop(g, "shrine") == null, "a spent shrine offers nothing more")

	# The dark room: no fire of its own, and a hoard in it.
	var dark := -1
	for i in (g.dungeon["kinds"] as Array).size():
		if g.dungeon["kinds"][i] == "dark":
			dark = i
	var rect: Rect2i = g.dungeon["rooms"][dark]
	var fires := 0
	for q in g.props:
		if q["type"] == "brazier" and rect.has_point(Vector2i(q["pos"] / 16.0)):
			fires += 1
	p = null
	for q in g.props:
		if q["type"] == "hoard" and not q["vault"] and rect.has_point(Vector2i(q["pos"] / 16.0)):
			p = q
	check(fires == 0 and p != null, "a dark room has no braziers and a hoard (%d braziers)" % fires)
	g.teleport(p["pos"] + Vector2(0, 26))
	await w(0.5)
	await at.shot("r_dark")
	var drops0: int = g.pickups.size()
	var em0 := int(main.profile["embers"])
	await _use(g, p)
	check(p["done"] and g.pickups.size() > drops0 + 10 and int(main.profile["embers"]) >= em0 + 20,
		"its hoard opens richer than a chest (%d drops)" % (g.pickups.size() - drops0))

	# The cursed altar: a kindling now, and a lamp that will not refill.
	p = _prop(g, "altar")
	g.teleport(p["pos"] + Vector2(0, 30))
	await w(0.5)
	await at.shot("r_altar")
	var boons0: int = g.boons.size()
	await _use(g, p)
	main.hud._choose(0)
	await get_tree().process_frame
	var offered: bool = main.hud.modal == "choice"
	main.hud._choose(0)
	g.oil = 50.0
	await w(1.0)
	check(offered and r.cursed and g.boons.size() == boons0 + 1 and g.oil <= 50.0,
		"the altar gives a kindling and the lamp stops refilling (oil %.1f)" % g.oil)
	r.cursed = false

	# The oil cache: the doorways wall up and the room fills.
	p = _prop(g, "cache")
	var croom: int = p["room"]
	g.teleport(p["pos"] + Vector2(0, 30))
	await w(0.4)
	await at.shot("r_cache")
	drops0 = g.pickups.size()
	await _use(g, p)
	var sealed_ok: bool = not r.seal_tiles.is_empty()
	for t in r.seal_tiles:
		sealed_ok = sealed_ok and g.tiles[t.y * g.W + t.x] == 0
	check(sealed_ok and r.wave.size() >= 3 and g.pickups.size() > drops0 and r.room_at(g.ptile) == croom,
		"taking the oil seals Wren in with %d foes" % r.wave.size())
	await w(0.5)
	await at.shot("r_ambush")
	var walls: Array = r.seal_tiles.duplicate()
	for e in r.wave:
		if not e.dead:
			e.hurt(99999.0, Vector2.ZERO)
	await until(func(): return r.seal_tiles.is_empty(), 3.0)
	var open_ok: bool = r.seal_tiles.is_empty()
	for t in walls:
		open_ok = open_ok and g.tiles[t.y * g.W + t.x] == 1
	check(open_ok, "the seal lifts when the ambush is beaten")

	# The vault: locked until its keeper falls.
	p = _prop(g, "vgate")
	g.near_prop = p
	check(g.prompt_for(p) == "Locked", "a vault gate says it is locked")
	var vc: Vector2 = g.tile_center(Dungeon._centeri(g.dungeon["rooms"][g.dungeon["vault"]]))
	g.teleport(p["pos"] + Vector2(0, 26) if not g.solid_at(p["pos"] + Vector2(0, 26)) else r.keeper.position + Vector2(0, 20))
	await w(0.4)
	await at.shot("r_vault_shut")
	r.keeper.hurt(99999.0, Vector2.ZERO)
	await until(func(): return r.vault_open, 3.0)
	open_ok = r.vault_open and _prop(g, "vgate") == null
	for t in doors:
		open_ok = open_ok and g.tiles[t.y * g.W + t.x] == 1
	check(open_ok, "the vault opens when its keeper falls")
	p = _prop(g, "hoard", "vault")
	await w(1.2)
	g.teleport(vc + Vector2(0, 26))
	await w(0.4)
	await at.shot("r_vault")
	boons0 = g.boons.size()
	await _use(g, p)
	offered = main.hud.modal == "choice"
	main.hud._choose(0)
	check(p["done"] and offered and g.boons.size() == boons0 + 1, "the keeper's hoard holds a kindling")
	g.cam_script = false


## A floor reached by the second stair, saved and loaded, comes back the same.
func _save_and_restore(g) -> void:
	g.floor_route = "dark"
	g.load_floor(3)
	g.hud.card_t = 0.0
	await w(0.4)
	var sv: Dictionary = main.read_save(main.slot)
	check(str(sv.get("route", "")) == "dark", "the arrival save remembers the stair taken (%s)" % sv.get("route", ""))
	var kinds0: Array = (g.dungeon["kinds"] as Array).duplicate()
	var sig0 := _signature(g)
	# Open a hoard and put the keeper out, then rest.
	var p = _prop(g, "hoard", "dark")
	if p == null:
		for q in g.props:
			if q["type"] == "hoard" and not q["vault"] and not q["done"]:
				p = q
	g.near_prop = p
	g.interact()
	var had_vault: bool = g.rooms.keeper != null
	if had_vault:
		g.rooms.keeper.hurt(99999.0, Vector2.ZERO)
		await until(func(): return g.rooms.vault_open, 3.0)
	await w(0.2)
	main.hud._close_modal()
	g.save_game(-1)
	sv = main.read_save(main.slot)
	g.floor_route = ""
	g.load_floor(3, sv)
	g.hud.card_t = 0.0
	await w(0.3)
	var p2: Variant = null
	for q in g.props:
		if q["idx"] == p["idx"]:
			p2 = q
	check(g.floor_route == "dark" and g.dungeon["kinds"] == kinds0 and _signature(g) == sig0,
		"loading the save grows the same floor, room kinds and all (%s)" % str(kinds0))
	check(p2 != null and p2["done"] and (not had_vault or g.rooms.vault_open),
		"an opened hoard stays open and an opened vault stays open")
	var shut := true
	for t in g.dungeon["vault_doors"]:
		shut = shut and g.tiles[t.y * g.W + t.x] == (1 if had_vault else 0)
	check(shut, "the vault's doorways are as they were left")


func _signature(g) -> String:
	var out := ""
	for q in g.dungeon["props"]:
		out += "%s%s%s;" % [q["type"], q["tile"], q.get("route", "")]
	return out


## The second stair: held by its own room, and it carries its promise down.
func _second_stair(g) -> void:
	g.floor_route = ""
	g.load_floor(2)
	g.hud.card_t = 0.0
	await w(0.4)
	var rs: Variant = null
	for q in g.props:
		if q["type"] == "stairs" and q.has("route"):
			rs = q
	check(rs != null and g.rooms.stair_sealed(rs) and g.prompt_for(rs) == "Sealed", "the second stair is held while its room's foes stand")
	g.teleport(rs["pos"] + Vector2(-20, 24))
	g.cam_script = true
	g.cam.zoom = Vector2(3.4, 3.4)
	await w(0.6)
	await at.shot("r_route_stair")
	for e in g.enemies:
		if e.room == g.dungeon["route_room"] and not e.dead:
			e.hurt(99999.0, Vector2.ZERO)
	await w(0.5)
	var want: String = rs["route"]
	check(not g.rooms.stair_sealed(rs) and g.prompt_for(rs).contains(Story.ROUTES[want]["name"]), "then opens, and says what is below (%s)" % g.prompt_for(rs))
	await at.shot("r_route_open")
	g.cam_script = false
	g.near_prop = rs
	g.interact()
	await until(func(): return g.depth == 3, 4.0)
	await w(0.3)
	check(g.depth == 3 and g.floor_route == want and g.dungeon["route"] == want,
		"taking it leads to depth 3, grown by its promise (%s)" % g.floor_route)


## The pressure clock: once the way down is open, the lamp drinks faster the
## longer Wren stays, except at a shrine.
func _lingering(g) -> void:
	g.floor_route = ""
	g.load_floor(3, {"seed": _seed_with(3, ["shrine"])})
	g.hud.card_t = 0.0
	await w(0.3)
	_quiet_foes(g)
	g._update_seal(true)
	g.god = false
	g.bot = false
	var r = g.rooms
	var plain := Vector2.ZERO
	for p in g.props:
		if p["type"] == "lamp":
			plain = p["pos"] + Vector2(0, 14)
	g.teleport(plain)
	r.linger_t = RoomsS.LINGER + RoomsS.LINGER_RAMP
	g.oil = 80.0
	await w(0.8)
	check(g.oil < 79.0 and not g.sealed, "lingering on a cleared floor drains the lamp (oil 80 -> %.1f)" % g.oil)
	var sp: Variant = null
	for p in g.props:
		if p["type"] == "shrine":
			sp = p
	g.teleport(sp["pos"] + Vector2(0, 14))
	await w(0.2)
	var t0: float = r.linger_t
	await w(0.5)
	check(r.linger_t == t0, "the count stops in a shrine's room")
	g.bot = true
