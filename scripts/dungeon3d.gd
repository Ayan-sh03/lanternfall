extends Node3D
## The dungeon in 3D, built from a modular kit (KayKit Dungeon Remastered,
## CC0): stone floor tiles over every walkable tile, a brick wall along every
## edge where floor meets rock, pillars on the outside corners, and torches on
## room walls. One game tile is one unit and the kit is drawn at half size, so
## a small floor tile covers a tile exactly and a half-length wall spans one
## tile edge. Walls stand on the rock side of the edge, so their faces are
## exactly where the flat game's walls are.
##
## Everything of one kind is a single MultiMesh; one shader draws them all,
## darkens what the fog of war still hides, and dissolves walls that stand
## between the camera and Wren.

const S := 0.5
const WALL_H := 2.0

const PIECES := ["floor_tile_small", "floor_tile_small_broken_A", "floor_tile_small_broken_B",
	"floor_tile_small_decorated", "floor_tile_small_weeds_A", "floor_dirt_small_A", "floor_dirt_small_B",
	"floor_tile_grate", "wall_half", "wall", "wall_cracked", "wall_broken", "wall_arched", "wall_shelves",
	"wall_pillar", "pillar", "torch_mounted", "barrel_small", "barrel_small_stack", "box_small", "box_large",
	"crates_stacked", "keg", "candle_lit", "candle_triple", "trunk_medium_A", "coin_stack_small", "bottle_A_brown",
	"table_small", "stool", "rubble_half", "banner_thin_red", "banner_patternA_red", "table_medium_broken",
	"torch_lit", "column", "stairs_walled"]

## What stands about against the walls of rooms: piece, scale, how common.
const DECO := [["barrel_small", 0.5, 4], ["barrel_small_stack", 0.36, 2], ["box_small", 0.42, 3],
	["box_large", 0.36, 2], ["crates_stacked", 0.32, 2], ["keg", 0.32, 2], ["candle_triple", 0.5, 3],
	["trunk_medium_A", 0.5, 2], ["coin_stack_small", 0.45, 1], ["bottle_A_brown", 0.5, 2], ["table_small", 0.5, 1],
	["rubble_half", 0.2, 2], ["table_medium_broken", 0.28, 1]]

static var meshes := {}
static var atlas: Texture2D = null

const KIT_SHADER := "shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform bool cut = false;
uniform float rough = 0.85;
uniform vec3 tint = vec3(1.0);
global uniform sampler2D lf_fog : filter_linear;
global uniform vec2 lf_size;
global uniform vec3 lf_player;
global uniform vec2 lf_camdir;
varying vec3 wpos;
varying vec3 wnrm;
float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 c = texture(atlas, UV).rgb;
	// Hidden by the fog of war: read just behind the surface, in the tile it belongs to.
	float f = texture(lf_fog, (wpos.xz - wnrm.xz * 0.2) / lf_size).a;
	if (cut && wpos.y > 0.08) {
		// Walls between the camera and Wren thin away so she is never lost.
		vec2 side_dir = vec2(lf_camdir.y, -lf_camdir.x);
		vec2 dd = wpos.xz - lf_player.xz;
		vec2 d = vec2(dot(dd, side_dir), dot(dd, lf_camdir));
		float k = (1.0 - smoothstep(1.3, 2.6, abs(d.x))) * smoothstep(0.0, 0.5, d.y) * (1.0 - smoothstep(2.6, 3.8, d.y));
		k *= smoothstep(0.1, 0.6, wpos.y);
		// Clean through the middle, a soft dither only at the edges.
		if (k > 0.92 || bayer4(FRAGCOORD.xy) < k) discard;
	}
	ALBEDO = c * tint * (1.0 - f);
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
"


## Loads each kit piece once: its mesh and the one texture they all share.
static func load_kit() -> bool:
	if not meshes.is_empty():
		return true
	for p in PIECES:
		var bytes := FileAccess.get_file_as_bytes("res://models/kit/%s.glbx" % p)
		if bytes.is_empty():
			continue
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_buffer(bytes, "res://models/kit/", st) != OK:
			continue
		var root: Node = doc.generate_scene(st)
		var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0] if not root.find_children("*", "MeshInstance3D", true, false).is_empty() else null
		if mi != null and mi.mesh != null:
			meshes[p] = mi.mesh
			if atlas == null:
				var m = mi.get_active_material(0)
				if m is StandardMaterial3D:
					atlas = m.albedo_texture
		root.free()
	return meshes.has("floor_tile_small") and meshes.has("wall_half") and atlas != null


var game
var mat_floor: ShaderMaterial
var mat_wall: ShaderMaterial
var torches: Array = []
## Where small flames burn on the decoration (candles), for the 3D view to light.
var candles: Array = []


func set_tint(t: Color) -> void:
	for m in [mat_floor, mat_wall]:
		if m != null:
			m.set_shader_parameter("tint", Vector3(t.r, t.g, t.b))


func _hash(x: int, y: int, salt: int = 0) -> int:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791) ^ int(game.floor_seed)
	return absi(h)


func tile(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= game.W or y >= game.H:
		return 0
	return game.tiles[y * game.W + x]


func build() -> void:
	for c in get_children():
		c.queue_free()
	torches.clear()
	candles.clear()
	var sh := Shader.new()
	sh.code = KIT_SHADER
	mat_floor = ShaderMaterial.new()
	mat_floor.shader = sh
	mat_floor.set_shader_parameter("atlas", atlas)
	mat_floor.set_shader_parameter("rough", 0.9)
	mat_wall = ShaderMaterial.new()
	mat_wall.shader = sh
	mat_wall.set_shader_parameter("atlas", atlas)
	mat_wall.set_shader_parameter("cut", true)
	mat_wall.set_shader_parameter("rough", 0.8)
	var lists := {}
	var W: int = game.W
	var H: int = game.H
	var hollow := {}
	for sc in game.secrets:
		if not sc["open"]:
			hollow[[sc["w"], sc["f"] - sc["w"]]] = true

	# Floors: mostly plain slabs, now and then cracked, worn, grown over or bare earth.
	for y in H:
		for x in W:
			if tile(x, y) != 1 or Vector2i(x, y) == game.stairs_tile:
				continue
			var h := _hash(x, y)
			var r := h % 100
			var piece := "floor_tile_small"
			if r < 6:
				piece = "floor_tile_small_broken_A"
			elif r < 11:
				piece = "floor_tile_small_broken_B"
			elif r < 15:
				piece = "floor_tile_small_decorated"
			elif r < 19:
				piece = "floor_tile_small_weeds_A"
			elif r < 22:
				piece = "floor_dirt_small_A"
			elif r < 25:
				piece = "floor_dirt_small_B"
			elif r < 27:
				piece = "floor_tile_grate"
			var rot := float((h / 100) % 4) * PI * 0.5
			var xf := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * S), Vector3(x + 0.5, 0.0, y + 0.5))
			_add(lists, piece, xf)

	# Walls: one segment for each edge where floor meets rock, laid along the
	# edge with its face toward the floor. Two in a row along the same line
	# become one long piece, which lets the arches, cracks and shelves in.
	var used := {}
	var room_edges := []
	for y in H:
		for x in W:
			if tile(x, y) == 1:
				continue
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				if tile(x + d.x, y + d.y) != 1 or used.has([x, y, d]):
					continue
				used[[x, y, d]] = true
				var along := Vector2i(absi(d.y), absi(d.x))
				var nx: int = x + along.x
				var ny: int = y + along.y
				var pair: bool = tile(nx, ny) != 1 and tile(nx + d.x, ny + d.y) == 1 and not used.has([nx, ny, d]) \
					and not hollow.has([Vector2i(x, y), d]) and not hollow.has([Vector2i(nx, ny), d])
				var piece := "wall_half"
				if hollow.has([Vector2i(x, y), d]):
					piece = "wall_cracked"
				elif pair:
					used[[nx, ny, d]] = true
					var r := _hash(x, y, 7) % 100
					piece = "wall"
					if r < 10:
						piece = "wall_cracked"
					elif r < 16:
						piece = "wall_broken"
					elif r < 22:
						piece = "wall_arched"
					elif r < 26 and game.room_id[(y + d.y) * W + x + d.x] >= 0:
						piece = "wall_shelves"
				_add(lists, piece, _wall_xf(x, y, d, 2 if pair else 1, piece))
				if game.room_id[(y + d.y) * W + x + d.x] >= 0:
					room_edges.append([x, y, d])

	# Pillars on the outside corners, where two faces of the same rock meet.
	for y in H:
		for x in W:
			if tile(x, y) == 1:
				continue
			for dx in [-1, 1]:
				for dy in [-1, 1]:
					if tile(x + dx, y) == 1 and tile(x, y + dy) == 1:
						var cx: float = x + 0.5 + dx * 0.5 - dx * 0.2
						var cz: float = y + 0.5 + dy * 0.5 - dy * 0.2
						_add(lists, "pillar", Transform3D(Basis().scaled(Vector3(S * 0.55, S * 1.02, S * 0.55)), Vector3(cx, 0, cz)))

	# Torches on room walls, a few to a room.
	var per_room := {}
	for e in room_edges:
		var x: int = e[0]
		var y: int = e[1]
		var d: Vector2i = e[2]
		var rid: int = game.room_id[(y + d.y) * W + x + d.x]
		if _hash(x, y, 3) % 100 > 22 or per_room.get(rid, 0) >= 3:
			continue
		per_room[rid] = per_room.get(rid, 0) + 1
		var face := Vector3(x + 0.5 + d.x * 0.5, 0.0, y + 0.5 + d.y * 0.5)
		var yaw := atan2(float(d.x), float(d.y))
		var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * S), face + Vector3(0, 1.15, 0))
		_add(lists, "torch_mounted", xf)
		torches.append({"p": face + Vector3(d.x, 0, d.y) * 0.32 + Vector3(0, 1.55, 0), "seed": _hash(x, y, 9) % 1000})

	_dress(lists, room_edges)
	# The way down: a walled stair sunk into the floor, falling away to the south.
	var stt: Vector2i = game.stairs_tile
	if stt.x >= 0:
		_add(lists, "stairs_walled", Transform3D(Basis().scaled(Vector3(0.2, 0.2, 0.235)), Vector3(stt.x + 0.5, -0.8, stt.y + 0.03)))

	for key in lists:
		var piece: String = key[0]
		if not meshes.has(piece):
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[piece]
		var xs: Array = lists[key]
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		# Whatever hangs on a wall fades with the wall in front of Wren.
		var is_wall: bool = piece.begins_with("wall") or piece == "pillar" or piece == "torch_mounted" or piece.begins_with("banner")
		if piece.begins_with("stairs"):
			is_wall = false
		mmi.material_override = mat_wall if is_wall else mat_floor
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if piece.begins_with("floor") \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)


## Rooms are lived-in: barrels, crates, kegs, candles and the odd broken
## table against the walls, and banners hanging on them. Only along walls, in
## rooms, never in a doorway or on a tile something of the game's stands on.
func _dress(lists: Dictionary, room_edges: Array) -> void:
	var W: int = game.W
	var busy := {}
	for p in game.props:
		busy[Vector2i(int(p["pos"].x / 16.0), int(p["pos"].y / 16.0))] = true
	busy[game.dungeon["start"]] = true
	busy[game.stairs_tile] = true
	var total := 0
	for dd in DECO:
		total += int(dd[2])
	for y in range(1, game.H - 1):
		for x in range(1, W - 1):
			if tile(x, y) != 1 or game.room_id[y * W + x] < 0 or busy.has(Vector2i(x, y)):
				continue
			var walls: Array = []
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				if tile(x + d.x, y + d.y) != 1:
					walls.append(d)
			# Nothing in the open, nor in a gap between two walls.
			if walls.is_empty() or (walls.size() == 2 and walls[0] == -walls[1]):
				continue
			var h := _hash(x, y, 21)
			if h % 100 >= 11:
				continue
			var pick := (h / 100) % total
			var piece: String = DECO[0][0]
			var sc: float = DECO[0][1]
			for dd in DECO:
				pick -= int(dd[2])
				if pick < 0:
					piece = dd[0]
					sc = dd[1]
					break
			var wd: Vector2i = walls[(h / 7) % walls.size()]
			var at := Vector3(x + 0.5 + wd.x * 0.24, 0.02, y + 0.5 + wd.y * 0.24)
			var yaw := atan2(float(-wd.x), float(-wd.y)) + (float((h / 13) % 60) - 30.0) * 0.01
			_add(lists, piece, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), at))
			if piece == "candle_triple":
				candles.append(at + Vector3(0, 0.42, 0))
	# Banners on the walls, where no torch hangs.
	for e in room_edges:
		var x: int = e[0]
		var y: int = e[1]
		var d: Vector2i = e[2]
		var h := _hash(x, y, 33)
		if h % 100 >= 7:
			continue
		var face := Vector3(x + 0.5 + d.x * 0.5, 0.0, y + 0.5 + d.y * 0.5)
		var yaw := atan2(float(d.x), float(d.y))
		var piece := "banner_thin_red" if h % 2 == 0 else "banner_patternA_red"
		_add(lists, piece, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * S), face - Vector3(d.x, 0, d.y) * 0.17))


## A wall piece along the edge of rock tile (x, y) that faces direction d,
## n tiles long, standing on the rock side of the edge.
func _wall_xf(x: int, y: int, d: Vector2i, n: int, piece: String) -> Transform3D:
	# The piece's own x runs along its length and its depth is z.
	var yaw := atan2(float(d.x), float(d.y))
	var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * S)
	var along := Vector3(absf(d.y), 0, absf(d.x))
	var face := Vector3(x + 0.5 + d.x * 0.5, 0.0, y + 0.5 + d.y * 0.5)
	var back := -Vector3(d.x, 0, d.y) * 0.25
	var start := face - along * 0.5
	var mid := start + along * (n * 0.5)
	if piece == "wall_half":
		# This one starts at its own origin rather than being centred on it.
		var unit_x := (b * Vector3(1, 0, 0)) / S
		return Transform3D(b, mid - unit_x * 0.5 + back)
	return Transform3D(b, mid + back)


## Pieces are grouped by kind and by 8 x 8 tile block: the renderer can skip
## blocks off screen, and on phones no one mesh is lit by more lamps than the
## renderer allows per mesh.
func _add(lists: Dictionary, piece: String, xf: Transform3D) -> void:
	var key := [piece, int(xf.origin.x) / 8, int(xf.origin.z) / 8]
	if not lists.has(key):
		lists[key] = []
	lists[key].append(xf)
