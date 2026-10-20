extends Node
## Balance statistics from bot runs: Slay the Spire's metrics, scaled to one
## developer. A bot plays whole descents from the first depth, fighting for
## real, and every run is logged: how long each depth took, what hurt, what
## killed, which kindlings were offered and taken, embers earned. Run with:
##   godot --headless --path . --fixed-fps 60 -- --autotest --balance [--runs=5]
##     [--depth=7] [--policy=random|first] [--skill=1] [--seed=N] [--lives=5] [--timeout=900]
##     [--town=all|id,id] [--speed=K] [--shotdir=<dir>] [--savetag=<name>]
## Prints BAL lines and writes balance.json and two CSVs to --shotdir (or
## user://balance/). Too slow for CI; run it by hand after a balance change.

const Story = preload("res://scripts/story.gd")
const Dungeon = preload("res://scripts/dungeon.gd")

var main
var at

var runs := 5
var max_depth := Dungeon.LAST
var policy := "random"
var lives := 5
var timeout_s := 900.0
## A depth that takes longer than this in game seconds is left by the stair
## as soon as it can be; one twice as long ends the run as stuck.
var floor_budget := 300.0
var town: Array = []
var speed := 0.0
## 1 plays with instant reactions, true aim and every hex parried; lower
## is slower to react, wilder in aim, and misses parries (a human-ish 0.5).
var skill := 1.0
var prng := RandomNumberGenerator.new()

# The bot's state for the game it is driving.
var g = null
var rec: Dictionary = {}
var dist := PackedInt32Array()
var queue := PackedInt32Array()
var dist_from := Vector2i(-1, -1)
var dist_age := 0.0
var goal_key := ""
var goal_best := 99999
var goal_t := 0.0
var shun: Dictionary = {}
var still_t := 0.0
var still_at := Vector2.ZERO
var wiggle_t := 0.0
var wiggle := Vector2.ZERO
var floor_t := 0.0
var hold_t := 0.0
var since := 0.0
var held := {"mv": Vector2.ZERO, "aim": Vector2.RIGHT, "atk": false, "bolt": false}


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.get_slice("=", 1)
	return def


func run() -> void:
	runs = maxi(1, int(_arg("runs", "5")))
	max_depth = clampi(int(_arg("depth", str(Dungeon.LAST))), 1, Dungeon.LAST)
	policy = _arg("policy", "random")
	lives = maxi(1, int(_arg("lives", "5")))
	timeout_s = float(_arg("timeout", "900"))
	speed = float(_arg("speed", "0"))
	skill = clampf(float(_arg("skill", "1")), 0.0, 1.0)
	var tw := _arg("town", "")
	for l in Story.TOWN:
		if tw == "all" or tw.split(",").has(l["id"]):
			town.append(l["id"])
	var seed_arg := _arg("seed", "")
	if seed_arg != "":
		prng.seed = int(seed_arg)
	else:
		prng.randomize()
	if speed > 0.0:
		Engine.time_scale = speed
	print("BAL start: %d runs, to depth %d, policy %s, skill %.2f, seed %s, lives %d per depth, town [%s], %s" % [runs, max_depth,
		policy, skill, seed_arg if seed_arg != "" else "random", lives, ",".join(town),
		"time x%.1f" % speed if speed > 0.0 else "about 60 game steps per game second"])
	main.hud.auto = true
	var results: Array = []
	for i in runs:
		var r: Dictionary = await _play(i, prng.randi())
		results.append(r)
		print("BAL run %d: %s at depth %d%s, %d deaths, %.0f s game (%.0f s wall, x%.1f), level %d, %d embers, %d kills, boons [%s]" % [
			i + 1, r["outcome"], r["depth"], (" by " + r["cause"]) if r["cause"] != "" else "", r["deaths"],
			r["game_secs"], r["wall_secs"], r["game_secs"] / maxf(r["wall_secs"], 0.01), r["level"], r["embers"],
			r["kills_total"], ",".join(r["boons"])])
	Engine.time_scale = 1.0
	main.hud.auto = false
	var summary := _summarise(results)
	_write(results, summary)
	main.delete_save(9)
	print("BAL DONE")
	get_tree().quit()


# --- One run ----------------------------------------------------------------------

func _fresh_profile() -> void:
	var p: Dictionary = main.profile
	p["embers"] = 0
	p["town"] = town.duplicate()
	p["tally"] = {}
	p["feats"] = []
	p["best"] = {}
	p["resolve"] = false
	p["nemesis"] = {}
	main.last_cause = ""
	main.nem_due = false
	main.nem_news = ""
	main.boss_seen = false


func _new_rec(i: int, rseed: int) -> Dictionary:
	return {"run": i + 1, "seed": rseed, "policy": policy, "skill": skill, "outcome": "", "depth": 1, "cause": "", "deaths": 0,
		"game_secs": 0.0, "wall_secs": 0.0, "embers": 0, "level": 1, "kills_total": 0, "boons": [], "relics": [],
		"depths": {}, "killed_by": {}, "hurt_by": {}, "kills": {}, "offers": {}, "picks": {},
		"oil": {"bolt": 0.0, "flask": 0.0, "power": 0.0}, "snuffed_secs": 0.0, "low_oil_secs": 0.0,
		"metrics": {}}


func _depth_rec(d: int) -> Dictionary:
	if not rec["depths"].has(d):
		rec["depths"][d] = {"secs": 0.0, "hp_lost": 0.0, "deaths": 0, "revives": 0, "kills": 0}
	return rec["depths"][d]


## Takes charge of a game: a fresh one at the start, or the one a revive makes.
func _adopt(ng, rseed: int, first: bool) -> void:
	g = ng
	g.bot = true
	g.bot_manual = true
	g.metrics = rec["metrics"]
	g.bot_policy = _choose
	# Floors and fights follow the run's seed (a revive continues on its own branch).
	g.rng.seed = rseed + rec["deaths"] * 7919
	if first:
		g.load_floor(1)
	dist_from = Vector2i(-1, -1)
	goal_key = ""
	shun.clear()


func _choose(options: Array) -> int:
	if policy == "first" or options.is_empty():
		return 0
	return prng.randi() % options.size()


func _play(i: int, rseed: int) -> Dictionary:
	rec = _new_rec(i, rseed)
	_fresh_profile()
	main.slot = 9
	main.delete_save(9)
	main.hud._close_modal()
	main.new_game(1)
	_adopt(main.game, rseed, true)
	var wall0 := Time.get_ticks_msec()
	var last_rt: float = g.run_time
	var cur_depth: int = g.depth
	var snap: Dictionary = {}
	var dead_seen = null
	floor_t = 0.0
	while true:
		await get_tree().process_frame
		# Time is scaled so each frame carries about a sixtieth of a second of
		# game time: as fast as the machine allows, in the same steps as play
		# at 60 fps. Under --fixed-fps 60 the frames already do, and this is 1.
		if speed <= 0.0:
			var raw := maxf(get_process_delta_time() / Engine.time_scale, 0.0005)
			Engine.time_scale = lerpf(Engine.time_scale, clampf((1.0 / 60.0) / raw, 1.0, 16.0), 0.2)
		rec["wall_secs"] = (Time.get_ticks_msec() - wall0) / 1000.0
		if main.game != g and main.game != null:
			_adopt(main.game, rseed, false)
			last_rt = g.run_time
			_depth_rec(g.depth)["revives"] += 1
		if g == null or not is_instance_valid(g):
			continue
		# Game time, as the game counts it (it stops for menus, hitstop and death).
		var dt: float = g.run_time - last_rt
		last_rt = g.run_time
		if dt > 0.0 and g.depth <= max_depth:
			rec["game_secs"] += dt
			floor_t += dt
			_depth_rec(g.depth)["secs"] += dt
			if g.snuffed:
				rec["snuffed_secs"] += dt
			if g.oil / maxf(g.max_oil, 1.0) < g.GLOAM_LOW:
				rec["low_oil_secs"] += dt
		if g.depth != cur_depth:
			_close_depth(cur_depth, snap)
			snap = rec["metrics"].duplicate()
			cur_depth = g.depth
			floor_t = 0.0
		rec["depth"] = maxi(rec["depth"], g.depth)
		if g.boss_dead:
			rec["outcome"] = "won"
			break
		if g.depth > max_depth:
			rec["outcome"] = "cleared"
			rec["depth"] = max_depth
			break
		if main.hud.modal == "death" and dead_seen != g:
			dead_seen = g
			rec["deaths"] += 1
			rec["cause"] = str(g.last_cause)
			rec["killed_by"][rec["cause"]] = rec["killed_by"].get(rec["cause"], 0) + 1
			var dr := _depth_rec(g.depth)
			dr["deaths"] += 1
			if dr["deaths"] >= lives:
				rec["outcome"] = "fell"
				break
			main.retry()
			continue
		if rec["wall_secs"] > timeout_s:
			rec["outcome"] = "timeout"
			break
		if floor_t > floor_budget * 2.0:
			rec["outcome"] = "stuck"
			break
		if not main.hud.blocking() and not g.dead:
			_think(dt)
	if cur_depth <= max_depth:
		_close_depth(cur_depth, snap)
	_finish()
	return rec


func _close_depth(d: int, snap: Dictionary) -> void:
	var m: Dictionary = rec["metrics"]
	var dr := _depth_rec(d)
	dr["hp_lost"] += m.get("hp_lost", 0.0) - snap.get("hp_lost", 0.0)
	var k := 0.0
	for key in m:
		if (key as String).begins_with("kill:"):
			k += m[key] - snap.get(key, 0.0)
	dr["kills"] += int(k)


func _finish() -> void:
	if g != null and is_instance_valid(g):
		rec["level"] = g.level
		rec["boons"] = g.boons.duplicate()
		g.metrics = null
		g.bot_policy = Callable()
	rec["embers"] = int(main.profile["embers"])
	if rec["outcome"] == "won" or rec["outcome"] == "cleared":
		rec["cause"] = ""
	var m: Dictionary = rec["metrics"]
	for key in m:
		var s := key as String
		var name := s.get_slice(":", 1)
		if s.begins_with("kill:"):
			rec["kills"][name] = int(m[key])
			rec["kills_total"] += int(m[key])
		elif s.begins_with("hurt_by:"):
			rec["hurt_by"][name] = int(m[key])
		elif s.begins_with("offer:"):
			rec["offers"][name] = int(m[key])
		elif s.begins_with("pick:"):
			rec["picks"][name] = int(m[key])
		elif s.begins_with("relic:"):
			rec["relics"].append(name)
	rec["oil"] = {"bolt": m.get("oil_bolt", 0.0), "flask": m.get("oil_flask", 0.0), "power": m.get("oil_power", 0.0)}
	rec.erase("metrics")
	main.hud._close_modal()
	main.delete_save(9)


# --- The bot ------------------------------------------------------------------------

## Walking distances in tiles from Wren to everywhere she can reach.
func _flood() -> void:
	var n: int = g.W * g.H
	if dist.size() != n:
		dist.resize(n)
		queue.resize(n)
	dist.fill(99999)
	var t: Vector2i = Vector2i(int(g.ppos.x / g.TS), int(g.ppos.y / g.TS))
	dist_from = t
	dist_age = 0.0
	if t.x < 0 or t.y < 0 or t.x >= g.W or t.y >= g.H:
		return
	var s: int = t.y * g.W + t.x
	dist[s] = 0
	queue[0] = s
	var head := 0
	var tail := 1
	var w: int = g.W
	while head < tail:
		var i := queue[head]
		head += 1
		var d := dist[i] + 1
		for o in [1, -1, w, -w]:
			var j: int = i + o
			if j >= 0 and j < n and g.tiles[j] == 1 and dist[j] > d:
				dist[j] = d
				queue[tail] = j
				tail += 1


func _dist_to(p: Vector2) -> int:
	var tx := int(p.x / g.TS)
	var ty := int(p.y / g.TS)
	if tx < 0 or ty < 0 or tx >= g.W or ty >= g.H:
		return 99999
	return dist[ty * g.W + tx]


## The way to walk toward `p`: along the flood back from it, to the first tile.
func _step_to(p: Vector2) -> Vector2:
	var w: int = g.W
	var tx := int(p.x / g.TS)
	var ty := int(p.y / g.TS)
	var i: int = ty * w + tx
	if dist[i] >= 99999:
		return Vector2.ZERO
	if dist[i] <= 1:
		return (p - g.ppos).normalized()
	while dist[i] > 1:
		var d := dist[i]
		for o in [1, -1, w, -w]:
			if dist[i + o] == d - 1:
				i += o
				break
		if dist[i] == d:
			return Vector2.ZERO
	var c: Vector2 = g.tile_center(Vector2i(i % w, i / w))
	return (c - g.ppos).normalized()


func _think(dt: float) -> void:
	# A slower player keeps doing what she last decided for a moment.
	hold_t -= dt
	since += dt
	if hold_t > 0.0:
		g.bot_mv = held["mv"]
		g.aim = held["aim"]
		g.bot_atk = held["atk"]
		g.bot_bolt = held["bolt"]
		return
	hold_t = (1.0 - skill) * prng.randf_range(0.15, 0.45)
	_decide(since)
	since = 0.0
	if skill < 1.0:
		g.aim = g.aim.rotated(prng.randf_range(-1.0, 1.0) * (1.0 - skill) * 0.6)
	held["mv"] = g.bot_mv
	held["aim"] = g.aim
	held["atk"] = g.bot_atk
	held["bolt"] = g.bot_bolt


func _decide(dt: float) -> void:
	g.bot_mv = Vector2.ZERO
	g.bot_atk = false
	g.bot_bolt = false
	dist_age += dt
	var pt := Vector2i(int(g.ppos.x / g.TS), int(g.ppos.y / g.TS))
	if pt != dist_from or dist_age > 0.25:
		_flood()
	for k in shun.keys():
		shun[k] -= dt
		if shun[k] <= 0.0:
			shun.erase(k)
	# Stuck against something: shove off sideways for a moment.
	if wiggle_t > 0.0:
		wiggle_t -= dt
		g.bot_mv = wiggle
		return
	var pc: Vector2 = g.pcenter()
	# Hexes about to land are struck back: a parry costs nothing.
	for s in g.shots:
		if s["friendly"]:
			continue
		var v: Vector2 = s["pos"] - pc
		if not s.has("bot_parry"):
			s["bot_parry"] = prng.randf() < skill
		if s["bot_parry"] and v.length() < 24.0 and (s["vel"] as Vector2).dot(v) < 0.0 and g.atk_cd <= 0.0:
			g.aim = v.normalized()
			g.bot_atk = true
			return
	var foe = _foe(pc)
	if foe != null:
		_fight(foe, pc)
	else:
		_travel(dt)
	_unstick(dt)


## The nearest foe she can see and reach with a blow or a bolt.
func _foe(pc: Vector2):
	var best = null
	var bd := 150.0
	for e in g.enemies:
		if e.dead or e.state == "dormant":
			continue
		var d: float = (e.center() - pc).length()
		if d < bd and g.los(pc, e.center()):
			bd = d
			best = e
	return best


func _fight(e, pc: Vector2) -> void:
	var v: Vector2 = e.center() - pc
	var d := v.length()
	g.aim = v / maxf(d, 0.01)
	var reach: float = 27.0 * g.stats["reach"] + e.hit_r
	var oil_k: float = g.oil / maxf(g.max_oil, 1.0)
	if d < reach - 3.0:
		g.bot_atk = true
	elif d > 48.0 and oil_k > 0.45 + g.bolt_cost() / g.max_oil:
		g.bot_bolt = true
	g.bot_mv = g.aim if d > reach * 0.55 else Vector2.ZERO
	if g.bot_mv != Vector2.ZERO and _dist_to(e.position) < 99999 and not g.los(g.ppos, e.position):
		g.bot_mv = _step_to(e.position)
	var near := 0
	for o in g.enemies:
		if not o.dead and (o.center() - pc).length() < 56.0:
			near += 1
	if g.powers["nova"] and g.pcd["nova"] <= 0.0 and (near >= 3 or (near >= 1 and g.hp <= 2)) and oil_k > 0.35:
		g.cast_nova()
	elif g.powers["spark"] and g.pcd["spark"] <= 0.0 and d < 150.0 and oil_k > 0.5:
		g.cast_spark()
	if g.powers["ward"] and g.pcd["ward"] <= 0.0 and near >= 3 and oil_k > 0.55:
		g.cast_ward()
	# Low on hearts with a foe at her heels: a dash away.
	if g.hp <= 2 and d < 24.0 and g.dash_stock > 0 and prng.randf() < 0.08 * skill:
		g.last_mv = -g.aim
		g.try_dash()


## Out of a fight: the next thing worth walking to, nearest first.
func _travel(dt: float) -> void:
	var best_d := 99999.0
	var best_p := Vector2.ZERO
	var best_key := ""
	var oil_k: float = g.oil / maxf(g.max_oil, 1.0)
	var hurry: bool = floor_t > floor_budget
	if not hurry:
		for p in g.pickups:
			var t: String = p["type"]
			if t == "heart" and g.hp >= g.max_hp or t == "oil" and g.oil >= g.max_oil - 1.0:
				continue
			var d := float(_dist_to(p["pos"])) * 0.5
			if d < best_d:
				best_d = d
				best_p = p["pos"]
				best_key = ""
		for p in g.props:
			var want := false
			match p["type"]:
				"chest", "relic", "page":
					want = not p["done"]
				"lamp":
					want = not p["done"] or oil_k < 0.35
				"plaque":
					want = not p.has("read")
				"moth":
					want = not p["done"] and g.moth == null and g.oil > 40.0
				"cage":
					want = g.boss_dead
			var key := "p%d" % p["idx"]
			if not want or shun.has(key):
				continue
			var d := float(_dist_to(p["pos"]))
			if d < best_d:
				best_d = d
				best_p = p["pos"]
				best_key = key
	for e in g.enemies:
		if e.dead:
			continue
		if hurry and not (g.sealed and e.room == g.exit_room):
			continue
		var key := "e%d" % e.get_instance_id()
		if shun.has(key):
			continue
		var d := float(_dist_to(e.position)) + 2.0
		if d < best_d:
			best_d = d
			best_p = e.position
			best_key = key
	if best_d >= 99999.0:
		# Nothing left to do here: the stair.
		for p in g.props:
			if p["type"] == "stairs":
				best_p = p["pos"]
				best_key = "stairs"
				best_d = float(_dist_to(p["pos"]))
	if best_key == "" and best_d >= 99999.0:
		return
	# Close enough to use it: use it.
	# (near_prop is only refreshed by the game's own update, so after a dialog
	# it can still name something already used.)
	if g.near_prop != null and (not g.near_prop["done"] or g.near_prop["type"] == "lamp"):
		var np: Dictionary = g.near_prop
		var use := false
		match np["type"]:
			"stairs":
				use = not g.sealed and best_key == "stairs"
			"lamp":
				use = not np["done"] or oil_k < 0.35
			"plaque":
				use = not np.has("read")
			"moth":
				use = g.moth == null and g.oil > 40.0
			_:
				use = true
		if use:
			g.interact()
			if np["type"] == "lamp" or np["type"] == "plaque":
				shun["p%d" % np["idx"]] = 60.0
			return
	# Walking toward something that gets no nearer is given up for a while.
	if best_key != goal_key:
		goal_key = best_key
		goal_best = int(best_d)
		goal_t = 0.0
	elif int(best_d) < goal_best:
		goal_best = int(best_d)
		goal_t = 0.0
	else:
		goal_t += dt
		if goal_t > 6.0 and goal_key != "" and goal_key != "stairs":
			shun[goal_key] = 40.0
			goal_key = ""
	g.bot_mv = _step_to(best_p)


func _unstick(dt: float) -> void:
	if g.bot_mv == Vector2.ZERO:
		still_t = 0.0
		still_at = g.ppos
		return
	if (g.ppos - still_at).length() > 3.0:
		still_t = 0.0
		still_at = g.ppos
		return
	still_t += dt
	if still_t > 1.2:
		still_t = 0.0
		wiggle = g.bot_mv.orthogonal() * (1.0 if prng.randf() < 0.5 else -1.0)
		wiggle_t = 0.35


# --- Totals -------------------------------------------------------------------------

func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	var n := s.size()
	return float(s[n / 2]) if n % 2 == 1 else (float(s[n / 2 - 1]) + float(s[n / 2])) * 0.5


func _is_kindling(id: String) -> bool:
	for b in Story.BOONS:
		if b["id"] == id:
			return true
	for d in Story.DUOS:
		if d["id"] == id:
			return true
	return false


func _summarise(results: Array) -> Dictionary:
	var n := results.size()
	var wins := 0
	var clean := 0
	var times: Array = []
	var win_times: Array = []
	var depths: Array = []
	var embers: Array = []
	var levels: Array = []
	var killed_by := {}
	var hurt_by := {}
	var kills := {}
	var per_depth := {}
	var kind := {}
	var oil := {"bolt": 0.0, "flask": 0.0, "power": 0.0}
	var outcomes := {}
	for r in results:
		var won: bool = r["outcome"] == "won"
		wins += int(won)
		clean += int(won and r["deaths"] == 0)
		outcomes[r["outcome"]] = outcomes.get(r["outcome"], 0) + 1
		times.append(r["game_secs"])
		if won:
			win_times.append(r["game_secs"])
		depths.append(r["depth"])
		embers.append(r["embers"])
		levels.append(r["level"])
		for k in r["killed_by"]:
			killed_by[k] = killed_by.get(k, 0) + r["killed_by"][k]
		for k in r["hurt_by"]:
			hurt_by[k] = hurt_by.get(k, 0) + r["hurt_by"][k]
		for k in r["kills"]:
			kills[k] = kills.get(k, 0) + r["kills"][k]
		for k in oil:
			oil[k] += r["oil"][k] / n
		for d in r["depths"]:
			var dr: Dictionary = r["depths"][d]
			if not per_depth.has(d):
				per_depth[d] = {"runs": 0, "secs": [], "hp_lost": 0.0, "deaths": 0, "kills": 0}
			var pd: Dictionary = per_depth[d]
			pd["runs"] += 1
			pd["secs"].append(dr["secs"])
			pd["hp_lost"] += dr["hp_lost"]
			pd["deaths"] += dr["deaths"]
			pd["kills"] += dr["kills"]
		var taken := {}
		for id in r["offers"]:
			if not kind.has(id):
				kind[id] = {"offered": 0, "picked": 0, "runs": 0, "wins": 0}
			kind[id]["offered"] += r["offers"][id]
		for id in r["picks"]:
			if not kind.has(id):
				kind[id] = {"offered": 0, "picked": 0, "runs": 0, "wins": 0}
			kind[id]["picked"] += r["picks"][id]
			taken[id] = true
		for id in taken:
			kind[id]["runs"] += 1
			kind[id]["wins"] += int(won)
	var depth_rows := {}
	for d in per_depth:
		var pd: Dictionary = per_depth[d]
		depth_rows[d] = {"runs": pd["runs"], "median_secs": _median(pd["secs"]),
			"hp_lost_avg": pd["hp_lost"] / pd["runs"], "deaths": pd["deaths"], "kills_avg": float(pd["kills"]) / pd["runs"]}
	var kindlings := {}
	var others := {}
	for id in kind:
		var k: Dictionary = kind[id]
		var row := {"offered": k["offered"], "picked": k["picked"],
			"pick_rate": float(k["picked"]) / maxf(k["offered"], 1.0), "runs_picked": k["runs"],
			"win_rate_picked": float(k["wins"]) / maxf(k["runs"], 1.0)}
		if _is_kindling(id):
			kindlings[id] = row
		else:
			others[id] = row
	var ember_sum := 0.0
	var secs_sum := 0.0
	for r in results:
		ember_sum += r["embers"]
		secs_sum += r["game_secs"]
	var s := {"runs": n, "policy": policy, "skill": skill, "max_depth": max_depth, "outcomes": outcomes,
		"win_rate": float(wins) / n, "deathless_win_rate": float(clean) / n,
		"median_game_secs": _median(times), "median_win_secs": _median(win_times),
		"median_depth": _median(depths), "median_level": _median(levels),
		"embers_median": _median(embers), "embers_avg": ember_sum / n,
		"embers_per_min": ember_sum / maxf(secs_sum / 60.0, 0.01),
		"deaths_by": killed_by, "hp_lost_by": hurt_by, "kills": kills, "oil_spent_avg": oil,
		"depths": depth_rows, "kindlings": kindlings, "other_choices": others}

	print("BAL win rate %.0f%% (%d/%d), deathless %.0f%%, outcomes %s" % [s["win_rate"] * 100.0, wins, n,
		s["deathless_win_rate"] * 100.0, JSON.stringify(outcomes)])
	print("BAL run length: median %s game (wins: %s), median depth %.1f, median level %.1f" % [_clock(s["median_game_secs"]),
		_clock(s["median_win_secs"]), s["median_depth"], s["median_level"]])
	print("BAL embers per run: median %.0f, mean %.0f, %.1f per game minute" % [s["embers_median"], s["embers_avg"], s["embers_per_min"]])
	var ds: Array = depth_rows.keys()
	ds.sort()
	for d in ds:
		var row: Dictionary = depth_rows[d]
		print("BAL depth %d: %d runs, median %s, hp lost %.1f avg, %d deaths, %.1f kills avg" % [d, row["runs"],
			_clock(row["median_secs"]), row["hp_lost_avg"], row["deaths"], row["kills_avg"]])
	print("BAL deadliest (deaths): %s" % _ranked(killed_by))
	print("BAL deadliest (hearts taken): %s" % _ranked(hurt_by))
	print("BAL kills: %s" % _ranked(kills))
	print("BAL oil spent per run: bolts %.0f, flask %.0f, powers %.0f" % [oil["bolt"], oil["flask"], oil["power"]])
	var ids: Array = kindlings.keys()
	ids.sort_custom(func(a, b): return kindlings[a]["pick_rate"] > kindlings[b]["pick_rate"])
	for id in ids:
		var k: Dictionary = kindlings[id]
		print("BAL kindling %-10s offered %3d picked %3d (%3.0f%%), in %d runs, win rate when picked %3.0f%%" % [id,
			k["offered"], k["picked"], k["pick_rate"] * 100.0, k["runs_picked"], k["win_rate_picked"] * 100.0])
	for id in others:
		print("BAL other choice %s: offered %d picked %d" % [id, others[id]["offered"], others[id]["picked"]])
	return s


func _ranked(d: Dictionary) -> String:
	var keys: Array = d.keys()
	keys.sort_custom(func(a, b): return d[a] > d[b])
	var out: Array = []
	for k in keys:
		out.append("%s %d" % [k, d[k]])
	return ", ".join(out) if not out.is_empty() else "none"


func _clock(secs: float) -> String:
	return "%d:%02d" % [int(secs) / 60, int(secs) % 60]


func _write(results: Array, summary: Dictionary) -> void:
	var out: String = at.dir if at != null and at.dir != "" else "user://balance"
	DirAccess.make_dir_recursive_absolute(out)
	var f := FileAccess.open(out.path_join("balance.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"summary": summary, "runs": results}, "\t"))
		f.close()
	var cols := ["run", "seed", "policy", "outcome", "depth", "cause", "deaths", "game_secs", "wall_secs", "embers",
		"level", "kills", "hp_lost", "oil_bolt", "oil_flask", "oil_power", "snuffed_secs", "low_oil_secs"]
	for d in range(1, Dungeon.LAST + 1):
		cols.append_array(["d%d_secs" % d, "d%d_hp_lost" % d, "d%d_deaths" % d])
	cols.append_array(["boons", "relics", "picks"])
	var lines: Array = [",".join(cols)]
	for r in results:
		var hp := 0.0
		for d in r["depths"]:
			hp += r["depths"][d]["hp_lost"]
		var row: Array = [r["run"], r["seed"], r["policy"], r["outcome"], r["depth"], r["cause"], r["deaths"],
			"%.1f" % r["game_secs"], "%.1f" % r["wall_secs"], r["embers"], r["level"], r["kills_total"], hp,
			"%.0f" % r["oil"]["bolt"], "%.0f" % r["oil"]["flask"], "%.0f" % r["oil"]["power"],
			"%.1f" % r["snuffed_secs"], "%.1f" % r["low_oil_secs"]]
		for d in range(1, Dungeon.LAST + 1):
			var dr: Dictionary = r["depths"].get(d, {})
			row.append_array(["%.1f" % dr.get("secs", 0.0), dr.get("hp_lost", 0.0), dr.get("deaths", 0)])
		var picks: Array = []
		for id in r["picks"]:
			picks.append("%s:%d" % [id, r["picks"][id]])
		row.append_array([" ".join(r["boons"]), " ".join(r["relics"]), " ".join(picks)])
		var cells: Array = []
		for c in row:
			cells.append(str(c))
		lines.append(",".join(cells))
	f = FileAccess.open(out.path_join("balance_runs.csv"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	var kl: Array = ["kindling,offered,picked,pick_rate,runs_picked,win_rate_picked"]
	var ks: Dictionary = summary["kindlings"]
	for id in ks:
		var k: Dictionary = ks[id]
		kl.append("%s,%d,%d,%.3f,%d,%.3f" % [id, k["offered"], k["picked"], k["pick_rate"], k["runs_picked"], k["win_rate_picked"]])
	f = FileAccess.open(out.path_join("balance_kindlings.csv"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(kl) + "\n")
		f.close()
	print("BAL wrote %s (balance.json, balance_runs.csv, balance_kindlings.csv)" % ProjectSettings.globalize_path(out))
