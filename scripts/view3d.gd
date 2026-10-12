extends Node3D
## A 3D view of the running game. The game itself still thinks in 2D: positions,
## collisions, AI and combat all stay on the flat tile grid in game.gd. This node
## only watches that state and draws it again in 3D: the tile grid becomes floor
## slabs and brick walls, each 2D sprite becomes a standing (or lying) card in
## the world, every 2D light becomes a real point light, and the particle effects
## are rebuilt as geometry each frame.
##
## The 2D x axis is the 3D x axis and the 2D y axis is the 3D z axis, so one tile
## (16 pixels) is one unit. Height above the floor is 3D y.

const Art = preload("res://scripts/art.gd")
const Story = preload("res://scripts/story.gd")

const TS := 16.0
## How steeply the camera looks down.
const PITCH := deg_to_rad(52.0)
const FOV := 36.0
## Standing sprites are stretched upward by this much so that, seen from the
## tilted camera, they keep the proportions they were drawn with.
var K := tan(PITCH)
const WALL_H := 1.5
## Things in the overlay layer (bolts, motes, pickups) float about chest high.
const LIFT := 7.0
const CHUNK := 8
const FOOT := 3.0

const BAYER := "
float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}
"

const GLOBALS := "
global uniform sampler2D lf_fog : filter_linear;
global uniform vec2 lf_size;
global uniform vec3 lf_player;
"

## The walls and floor. Walls between the camera and Wren dissolve so she is
## never lost behind them.
const MAP_SHADER := "shader_type spatial;
render_mode cull_disabled, specular_disabled, diffuse_lambert;
uniform sampler2D atlas : source_color, filter_nearest;
" + GLOBALS + BAYER + "
varying vec3 wpos;
varying vec3 wnrm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = NORMAL;
}
void fragment() {
	vec3 c = texture(atlas, UV).rgb * COLOR.rgb;
	float f = texture(lf_fog, (wpos.xz - wnrm.xz * 0.3) / lf_size).a;
	// Only the faces and tops that can actually hide her: just south of her,
	// not the side walls of the corridor she walks down.
	if (wpos.y > 0.05 && abs(wnrm.x) < 0.5) {
		vec2 d = wpos.xz - lf_player.xz;
		float k = (1.0 - smoothstep(1.1, 2.2, abs(d.x))) * smoothstep(0.1, 0.6, d.y) * (1.0 - smoothstep(2.0, 3.0, d.y));
		if (bayer4(FRAGCOORD.xy) < k * 0.92) discard;
	}
	ALBEDO = c * (1.0 - f);
	// Wall tops sit above every lamp, so give them a little light of their own
	// or they read as holes in the world.
	if (wnrm.y > 0.5 && wpos.y > 1.0) EMISSION = c * 0.55 * (1.0 - f);
}
"

const SPRITE_HEAD := "
uniform sampler2D tex : source_color, filter_nearest;
uniform vec4 modulate : source_color = vec4(1.0);
uniform float flash = 0.0;
uniform bool flip = false;
" + GLOBALS + BAYER

## Cut-out sprites: hard pixel edges, write depth. Faded sprites dither.
const SPRITE_FRAG := "
void fragment() {
	vec2 uv = UV;
	if (flip) uv.x = 1.0 - uv.x;
	vec4 c = texture(tex, uv);
	if (c.a < 0.5) discard;
	if (modulate.a < 0.99 && bayer4(FRAGCOORD.xy) > modulate.a) discard;
	float f = texture(lf_fog, NODE_POSITION_WORLD.xz / lf_size).a;
	ALBEDO = mix(c.rgb * modulate.rgb, vec3(1.0), flash) * (1.0 - f);
}
"

## Lit sprites take light from every direction, as they did in 2D, rather than
## only on the face turned toward the lamp.
const SPRITE_LIT := "shader_type spatial;
render_mode cull_disabled, specular_disabled;
" + SPRITE_HEAD + SPRITE_FRAG + "
void light() {
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION / PI;
}
"

const SPRITE_UNLIT := "shader_type spatial;
render_mode cull_disabled, unshaded;
" + SPRITE_HEAD + SPRITE_FRAG

const SPRITE_ADD := "shader_type spatial;
render_mode cull_disabled, unshaded, blend_add, depth_draw_never;
uniform sampler2D tex : source_color, filter_linear;
uniform vec4 modulate : source_color = vec4(1.0);
uniform bool flip = false;
" + GLOBALS + "
void fragment() {
	vec4 c = texture(tex, UV) * modulate;
	float f = texture(lf_fog, NODE_POSITION_WORLD.xz / lf_size).a;
	ALBEDO = c.rgb * (1.0 - f);
	ALPHA = c.a;
}
"

const SPRITE_BLEND := "shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_never;
uniform sampler2D tex : source_color, filter_linear;
uniform vec4 modulate : source_color = vec4(1.0);
uniform bool flip = false;
void fragment() {
	vec4 c = texture(tex, UV) * modulate;
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
"

const FX_ADD := "shader_type spatial;
render_mode cull_disabled, unshaded, blend_add, depth_draw_never;
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
"

const FX_MIX := "shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_never;
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
"

static var shaders := {}
static var globals_made := false

var game
var active := true
var cam: Camera3D
var env: WorldEnvironment
var map_node: Node3D
var built_seed := -1
var built_depth := -99
var quad := QuadMesh.new()
var sprites := {}
var lights := {}
var fx_mesh := ImmediateMesh.new()
var fx_inst: MeshInstance3D
var decal_mesh := ImmediateMesh.new()
var decal_inst: MeshInstance3D
var decal_n := -1
var seen := {}
var order := 0


static func _shader(id: String, code: String) -> Shader:
	if not shaders.has(id):
		var s := Shader.new()
		s.code = code
		shaders[id] = s
	return shaders[id]


## Shader values every 3D material reads: the fog-of-war map, its size in
## tiles, and where Wren stands (for the see-through walls).
static func _globals() -> void:
	if globals_made:
		return
	globals_made = true
	RenderingServer.global_shader_parameter_add("lf_fog", RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D, Art.tex["px"])
	RenderingServer.global_shader_parameter_add("lf_size", RenderingServer.GLOBAL_VAR_TYPE_VEC2, Vector2.ONE)
	RenderingServer.global_shader_parameter_add("lf_player", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)


func _ready() -> void:
	_globals()
	cam = Camera3D.new()
	cam.fov = FOV
	cam.near = 0.5
	cam.far = 200.0
	add_child(cam)
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = game.FOGC
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = game.AMBIENT
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env = WorldEnvironment.new()
	env.environment = e
	add_child(env)
	map_node = Node3D.new()
	add_child(map_node)
	fx_inst = MeshInstance3D.new()
	fx_inst.mesh = fx_mesh
	fx_inst.material_override = _mat("fx_add", FX_ADD)
	fx_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fx_inst)
	decal_inst = MeshInstance3D.new()
	decal_inst.mesh = decal_mesh
	decal_inst.material_override = _mat("fx_mix", FX_MIX)
	decal_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(decal_inst)
	set_active(active)


func _mat(id: String, code: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(id, code)
	return m


## Switches between this view and the original flat one, live, mid-run.
func set_active(on: bool) -> void:
	active = on
	visible = on
	if cam != null:
		cam.current = on
	if game != null:
		game.visible = not on


# --- Mapping between the two worlds ------------------------------------------------

## A point on the 2D map, h pixels above the floor.
func to3(p: Vector2, h: float = 0.0) -> Vector3:
	return Vector3(p.x / TS, h * K / TS, p.y / TS)


## Where a 2D map point lands on screen, for the HUD's labels and numbers.
func screen_pos(p: Vector2) -> Vector2:
	return cam.unproject_position(to3(p))


## The point under the mouse, as the 2D game would see it: aim is measured from
## Wren's chest, so the ray is met at chest height.
func mouse_world() -> Vector2:
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	var h := LIFT * K / TS
	if absf(d.y) < 0.001:
		return game.pcenter()
	var t := (h - o.y) / d.y
	var hit := o + d * t
	return Vector2(hit.x * TS, hit.z * TS - LIFT)


# --- Per frame -----------------------------------------------------------------------

func _process(_dt: float) -> void:
	if not active or game == null or game.W == 0:
		return
	if game.floor_seed != built_seed or game.depth != built_depth:
		_build_map()
	RenderingServer.global_shader_parameter_set("lf_player", to3(game.ppos))
	_update_camera()
	seen.clear()
	order = 0
	var roots: Array = []
	for c in game.map_root.get_children():
		if not (c is Sprite2D):
			roots.append([c, true, 0.0])
	for c in game.ents.get_children():
		roots.append([c, false, 0.0])
	for c in game.over.get_children():
		roots.append([c, false, LIFT])
	for r in roots:
		var node: Node2D = r[0]
		if node.is_queued_for_deletion() or not node.visible:
			continue
		var ground: Vector2 = node.global_position + Vector2(0, r[2])
		_walk(node, ground, r[1], Color.WHITE, 0)
	_sweep(sprites)
	_sweep(lights)
	_draw_fx()
	if game.decals.size() != decal_n:
		_draw_decals()


func _sweep(pool: Dictionary) -> void:
	for id in pool.keys():
		if not seen.has(id):
			pool[id].queue_free()
			pool.erase(id)


func _walk(n: Node, ground: Vector2, flat: bool, tint: Color, depth: int) -> void:
	if n is CanvasItem:
		tint = tint * n.modulate * n.self_modulate
	if n is Sprite2D:
		_mirror_sprite(n, ground, flat, tint)
	elif n is PointLight2D:
		_mirror_light(n, ground)
	for c in n.get_children():
		if c is CanvasItem and not c.visible:
			continue
		_walk(c, ground, flat, tint, depth + 1)


func _kind(s: Sprite2D) -> String:
	if s.texture == Art.tex["shadow"]:
		return "blend"
	if s.material == Art.mat_add:
		return "add"
	if s.material == Art.mat_unlit:
		return "unlit"
	return "lit"


func _mirror_sprite(s: Sprite2D, ground: Vector2, flat: bool, tint: Color) -> void:
	if s.texture == null or s.texture == Art.tex["stairs"]:
		return
	var id := s.get_instance_id()
	seen[id] = true
	order += 1
	var kind := _kind(s)
	var mi: MeshInstance3D = sprites.get(id)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.mesh = quad
		match kind:
			"lit":
				mi.material_override = _mat("lit", SPRITE_LIT)
			"unlit":
				mi.material_override = _mat("unlit", SPRITE_UNLIT)
			"add":
				mi.material_override = _mat("add", SPRITE_ADD)
			_:
				mi.material_override = _mat("blend", SPRITE_BLEND)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		sprites[id] = mi
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("tex", s.texture)
	m.set_shader_parameter("modulate", tint)
	m.set_shader_parameter("flip", s.flip_h)
	if kind == "lit" and s.material is ShaderMaterial:
		m.set_shader_parameter("flash", s.material.get_shader_parameter("flash"))

	var rect := s.get_rect()
	var c: Vector2 = s.global_transform * rect.get_center()
	var gs := s.global_scale.abs()
	var w := rect.size.x * gs.x / TS
	var h := rect.size.y * gs.y / TS
	var r := s.global_rotation
	# Shadows, auras and the big pools of light lie on the floor; everything
	# else stands up and faces the camera.
	var lies := flat or kind == "blend" or (kind == "add" and gs.x >= 0.7)
	var xf := Transform3D()
	if lies:
		xf.basis.x = Vector3(cos(r), 0.0, sin(r)) * w
		xf.basis.y = Vector3(sin(r), 0.0, -cos(r)) * h
		xf.basis.z = Vector3.UP
		xf.origin = Vector3(c.x / TS, 0.015 + order * 0.0004, c.y / TS)
	else:
		xf.basis.x = Vector3(cos(r), -sin(r) * K, 0.0) * w
		xf.basis.y = Vector3(sin(r), cos(r) * K, 0.0) * h
		xf.basis.z = Vector3.BACK
		# Later children are drawn over earlier ones in 2D; nudge them toward
		# the camera so they still win.
		# In 2D the feet hang a few pixels below the anchor; here that would
		# put them under the floor.
		xf.origin = Vector3(c.x / TS, (ground.y - c.y + FOOT) * K / TS, ground.y / TS + order * 0.002)
	mi.transform = xf


func _mirror_light(l: PointLight2D, ground: Vector2) -> void:
	var id := l.get_instance_id()
	seen[id] = true
	var o: OmniLight3D = lights.get(id)
	if o == null:
		o = OmniLight3D.new()
		o.omni_attenuation = 1.2
		o.light_specular = 0.0
		add_child(o)
		lights[id] = o
		# Only Wren's own lantern throws shadows: it is the one that matters,
		# and phones and the "fast" picture go without.
		o.shadow_enabled = l == game.plight and not OS.has_feature("mobile") and not game.main.profile["fast"]
	var p := l.global_position
	var hgt := maxf(6.0, ground.y - p.y + 4.0)
	o.position = Vector3(p.x / TS, hgt * K / TS, ground.y / TS)
	o.light_color = l.color
	o.light_energy = l.energy * 1.6
	o.omni_range = l.texture_scale * 64.0 / TS * 1.15
	o.visible = l.enabled


# --- Camera ---------------------------------------------------------------------------

func _update_camera() -> void:
	var c2: Vector2 = game.cam.position + game.cam.offset
	var z: float = game.cam.zoom.x
	var target := Vector3(c2.x / TS, 0.4, (c2.y + 6.0) / TS)
	var vis_h: float = get_viewport().get_visible_rect().size.y / (z * TS)
	var dist := vis_h * 0.5 / tan(deg_to_rad(FOV) * 0.5) * 0.9
	cam.position = target + Vector3(0.0, sin(PITCH), cos(PITCH)) * dist
	cam.look_at(target, Vector3.UP)


# --- The dungeon ----------------------------------------------------------------------

func _build_map() -> void:
	built_seed = game.floor_seed
	built_depth = game.depth
	for c in map_node.get_children():
		c.queue_free()
	var info: Dictionary = Story.GALLERY if game.depth <= 0 else Story.DEPTHS[game.depth - 1]
	var theme: String = info["theme"]
	if game.depth <= 0 and game.gallery_theme != "":
		theme = game.gallery_theme
	var atlas := _atlas(theme)
	var mat := _mat("map", MAP_SHADER)
	mat.set_shader_parameter("atlas", ImageTexture.create_from_image(atlas))
	RenderingServer.global_shader_parameter_set("lf_fog", game.fog_tex)
	RenderingServer.global_shader_parameter_set("lf_size", Vector2(game.W, game.H))
	var aw := float(atlas.get_width())
	var ah := float(atlas.get_height())
	var W: int = game.W
	var H: int = game.H
	for cy in range(0, H, CHUNK):
		for cx in range(0, W, CHUNK):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var any := false
			for y in range(cy, mini(cy + CHUNK, H)):
				for x in range(cx, mini(cx + CHUNK, W)):
					if Vector2i(x, y) == game.stairs_tile:
						_stairwell(st, x, y, aw, ah)
						any = true
					elif _tile(x, y) == 1:
						_floor(st, x, y, aw, ah)
						any = true
					elif _near_floor(x, y):
						_wall(st, x, y, aw, ah)
						any = true
			if not any:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = mat
			map_node.add_child(mi)


func _tile(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= game.W or y >= game.H:
		return 0
	return game.tiles[y * game.W + x]


func _near_floor(x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if _tile(x + dx, y + dy) == 1:
				return true
	return false


## The floor slabs, wall tops and a taller brick face, side by side in one image.
## Cells 0-5 floors, 6-7 tops, 8-10 brick faces (16 x 24), 11 the ledge trim.
func _atlas(theme: String) -> Image:
	var t := Art.theme_tiles(theme)
	var img := Image.create(16 * 12, 24, false, Image.FORMAT_RGBA8)
	for i in 6:
		img.blit_rect(t["floor"][i], Rect2i(0, 0, 16, 16), Vector2i(i * 16, 0))
	for i in 2:
		img.blit_rect(t["top"][i], Rect2i(0, 0, 16, 16), Vector2i((6 + i) * 16, 0))
	var th: Dictionary = Art.THEMES[theme]
	var wall := Color(th["wall"] as String)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(theme + "3d")
	for v in 3:
		for y in 24:
			for x in 16:
				var c: Color
				if y == 0:
					c = wall.lightened(0.22)
				else:
					var by := y - 1
					var rowi := int(by / 4.0)
					var off := 4 if rowi % 2 == 1 else 0
					var mortar := by % 4 == 3 or (x + off + v * 3) % 8 == 7
					c = wall.lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.03)
					if mortar:
						c = c.darkened(0.38)
					elif by % 4 == 0:
						c = c.lightened(0.08)
					c = c.darkened(0.25 * by / 23.0)
				img.set_pixel((8 + v) * 16 + x, y, c)
	img.fill_rect(Rect2i(11 * 16, 0, 16, 24), wall.darkened(0.15))
	return img


func _hash(x: int, y: int) -> int:
	return absi((x * 73856093) ^ (y * 19349663))


func _quad(st: SurfaceTool, p: Array, uv: Array, col: Array, n: Vector3) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_color(col[i])
		st.set_uv(uv[i])
		st.add_vertex(p[i])


func _cell_uv(cell: int, w: float, h: float, aw: float, ah: float) -> Array:
	var u0 := cell * 16.0 / aw
	var u1 := (cell * 16.0 + w) / aw
	var v1 := h / ah
	return [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, v1), Vector2(u0, v1)]


## Corners of a floor slab darken where walls stand beside them.
func _ao(x: int, y: int) -> Color:
	var walls := 0
	for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		if _tile(x + o.x, y + o.y) == 0:
			walls += 1
	var k := 1.0 - 0.22 * walls
	return Color(k, k, k)


func _floor(st: SurfaceTool, x: int, y: int, aw: float, ah: float) -> void:
	var hsh := _hash(x, y)
	var v := hsh % 3
	if (hsh >> 4) % 100 >= 72:
		v += 3
	var p := [Vector3(x, 0, y), Vector3(x + 1, 0, y), Vector3(x + 1, 0, y + 1), Vector3(x, 0, y + 1)]
	var col := [_ao(x, y), _ao(x + 1, y), _ao(x + 1, y + 1), _ao(x, y + 1)]
	_quad(st, p, _cell_uv(v, 16, 16, aw, ah), col, Vector3.UP)


func _wall(st: SurfaceTool, x: int, y: int, aw: float, ah: float) -> void:
	var hsh := _hash(x, y)
	var top := Color(1, 1, 1)
	var p := [Vector3(x, WALL_H, y), Vector3(x + 1, WALL_H, y), Vector3(x + 1, WALL_H, y + 1), Vector3(x, WALL_H, y + 1)]
	_quad(st, p, _cell_uv(6 + hsh % 2, 16, 16, aw, ah), [top, top, top, top], Vector3.UP)
	# A pale ledge traces every edge of the top that overlooks open floor.
	var trim := _cell_uv(11, 16, 16, aw, ah)
	var tw := 2.0 / TS
	var th := WALL_H + 0.003
	if _tile(x, y + 1) == 1:
		_quad(st, [Vector3(x, th, y + 1 - tw), Vector3(x + 1, th, y + 1 - tw), Vector3(x + 1, th, y + 1), Vector3(x, th, y + 1)], trim, [top, top, top, top], Vector3.UP)
	if _tile(x, y - 1) == 1:
		_quad(st, [Vector3(x, th, y), Vector3(x + 1, th, y), Vector3(x + 1, th, y + tw), Vector3(x, th, y + tw)], trim, [top, top, top, top], Vector3.UP)
	if _tile(x + 1, y) == 1:
		_quad(st, [Vector3(x + 1 - tw, th, y), Vector3(x + 1, th, y), Vector3(x + 1, th, y + 1), Vector3(x + 1 - tw, th, y + 1)], trim, [top, top, top, top], Vector3.UP)
	if _tile(x - 1, y) == 1:
		_quad(st, [Vector3(x, th, y), Vector3(x + tw, th, y), Vector3(x + tw, th, y + 1), Vector3(x, th, y + 1)], trim, [top, top, top, top], Vector3.UP)
	var face := _cell_uv(8 + hsh % 3, 16, 24, aw, ah)
	var hi := Color(1, 1, 1)
	var lo := Color(0.5, 0.5, 0.55)
	var cols := [hi, hi, lo, lo]
	# Each side that looks out onto open floor gets a brick face.
	if _tile(x, y + 1) == 1:
		_quad(st, [Vector3(x, WALL_H, y + 1), Vector3(x + 1, WALL_H, y + 1), Vector3(x + 1, 0, y + 1), Vector3(x, 0, y + 1)],
			face, cols, Vector3.BACK)
	if _tile(x, y - 1) == 1:
		_quad(st, [Vector3(x + 1, WALL_H, y), Vector3(x, WALL_H, y), Vector3(x, 0, y), Vector3(x + 1, 0, y)],
			face, cols, Vector3.FORWARD)
	if _tile(x + 1, y) == 1:
		_quad(st, [Vector3(x + 1, WALL_H, y + 1), Vector3(x + 1, WALL_H, y), Vector3(x + 1, 0, y), Vector3(x + 1, 0, y + 1)],
			face, cols, Vector3.RIGHT)
	if _tile(x - 1, y) == 1:
		_quad(st, [Vector3(x, WALL_H, y), Vector3(x, WALL_H, y + 1), Vector3(x, 0, y + 1), Vector3(x, 0, y)],
			face, cols, Vector3.LEFT)


## The way down: a real stairwell cut into the floor, steps dropping away
## southward into the dark.
func _stairwell(st: SurfaceTool, x: int, y: int, aw: float, ah: float) -> void:
	var steps := 5
	var drop := 0.24
	var uv := _cell_uv(0, 16, 16, aw, ah)
	var face := _cell_uv(8, 16, 24, aw, ah)
	var m := 0.12
	var x0 := x + m
	var x1 := x + 1 - m
	for i in steps:
		var z0 := y + float(i) / steps
		var z1 := y + float(i + 1) / steps
		var h := -drop * (i + 1)
		var k := 0.85 - 0.15 * i
		var c := Color(k, k, k)
		var dk := Color(k * 0.6, k * 0.6, k * 0.6)
		var su := [Vector2(uv[0].x, uv[0].y), Vector2(uv[1].x, uv[0].y), Vector2(uv[1].x, uv[0].y + (uv[2].y - uv[0].y) * 0.2), Vector2(uv[0].x, uv[0].y + (uv[2].y - uv[0].y) * 0.2)]
		# Tread, then the riser in front of it.
		_quad(st, [Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, h, z1), Vector3(x0, h, z1)], su, [c, c, c, c], Vector3.UP)
		_quad(st, [Vector3(x0, h + drop, z0), Vector3(x1, h + drop, z0), Vector3(x1, h, z0), Vector3(x0, h, z0)], su, [dk, dk, dk, dk], Vector3.BACK)
	var bottom := -drop * steps - 0.05
	var hi := Color(0.7, 0.7, 0.7)
	var lo := Color(0.12, 0.12, 0.14)
	# The well's sides and far end, and the floor ledge around its mouth.
	_quad(st, [Vector3(x0, 0, y), Vector3(x0, 0, y + 1), Vector3(x0, bottom, y + 1), Vector3(x0, bottom, y)], face, [hi, hi, lo, lo], Vector3.RIGHT)
	_quad(st, [Vector3(x1, 0, y + 1), Vector3(x1, 0, y), Vector3(x1, bottom, y), Vector3(x1, bottom, y + 1)], face, [hi, hi, lo, lo], Vector3.LEFT)
	_quad(st, [Vector3(x0, 0, y + 1), Vector3(x1, 0, y + 1), Vector3(x1, bottom, y + 1), Vector3(x0, bottom, y + 1)], face, [lo, lo, lo, lo], Vector3.FORWARD)
	var fu := _cell_uv(1, 16, 16, aw, ah)
	var w := Color(0.8, 0.8, 0.8)
	_quad(st, [Vector3(x, 0, y), Vector3(x0, 0, y), Vector3(x0, 0, y + 1), Vector3(x, 0, y + 1)], fu, [w, w, w, w], Vector3.UP)
	_quad(st, [Vector3(x1, 0, y), Vector3(x + 1, 0, y), Vector3(x + 1, 0, y + 1), Vector3(x1, 0, y + 1)], fu, [w, w, w, w], Vector3.UP)


# --- Effects --------------------------------------------------------------------------

## A point the 2D effects drew at chest height: lifted off the floor in 3D.
func _fx3(p: Vector2, h: float = LIFT) -> Vector3:
	return Vector3(p.x / TS, h * K / TS, (p.y + h) / TS)


func _tri(m: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	m.surface_set_color(col)
	m.surface_add_vertex(a)
	m.surface_add_vertex(b)
	m.surface_add_vertex(c)


func _quad_fx(m: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(m, a, b, c, col)
	_tri(m, a, c, d, col)


## A ring lying on the floor, from radius r0 to r1 (pixels).
func _ring(m: ImmediateMesh, p: Vector2, r0: float, r1: float, col: Color, segs: int = 40) -> void:
	var c := to3(p) + Vector3(0, 0.03, 0)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0)) / TS
		var d1 := Vector3(cos(a1), 0, sin(a1)) / TS
		_quad_fx(m, c + d0 * r0, c + d1 * r0, c + d1 * r1, c + d0 * r1, col)


func _draw_fx() -> void:
	var fx = game.fx
	var m := fx_mesh
	m.clear_surfaces()
	var any := false
	m.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var right := cam.global_basis.x
	var up := cam.global_basis.y

	# Sparks and embers: little glowing squares. Their 2D drift up the screen
	# becomes a real rise into the air.
	for p in fx.parts:
		var k: float = p["l"] / p["m"]
		var sz: float = p["s"] * (0.5 + 0.5 * k) / TS * 0.5
		var c: Color = p["c"]
		var pos: Vector2 = p["p"]
		var o: Vector2 = p.get("o", pos)
		var h := maxf(1.0, LIFT + (o.y - pos.y))
		var at := Vector3(pos.x / TS, h * K / TS, (o.y + LIFT) / TS)
		_quad_fx(m, at - right * sz - up * sz, at + right * sz - up * sz, at + right * sz + up * sz, at - right * sz + up * sz,
			Color(c.r, c.g, c.b, c.a * k))
		any = true

	# Staff sweeps: a crescent swung flat around Wren at waist height.
	for sl in fx.slashes:
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
			_quad_fx(m, _fx3(o + d0 * reach, 5.0), _fx3(o + d1 * reach, 5.0), _fx3(o + d1 * in1, 5.0), _fx3(o + d0 * in0, 5.0), col)
		any = true

	# Chain lightning: a jagged ribbon between the two chests.
	for bl in fx.bolts:
		var k: float = 1.0 - bl["t"] / bl["d"]
		var a: Vector2 = bl["a"]
		var b: Vector2 = bl["b"]
		var c: Color = bl["c"]
		var n := maxi(3, int(a.distance_to(b) / 9.0))
		var side := (b - a).orthogonal().normalized()
		var prev := _fx3(a)
		for s in range(1, n + 1):
			var q := b if s == n else a.lerp(b, float(s) / n) + side * randf_range(-5.0, 5.0)
			var cur := _fx3(q)
			var wv := Vector3(0, 0.07, 0)
			_quad_fx(m, prev - wv, cur - wv, cur + wv, prev + wv, Color(c.r, c.g, c.b, k * 0.9))
			prev = cur
		any = true

	for wd in fx.wards:
		var wa: float = clampf(wd["t"], 0.0, 1.0)
		var wp: Vector2 = wd["p"]
		var wr: float = wd["r"]
		_ring(m, wp, wr - 1.0, wr + 1.0, Color(1.0, 0.75, 0.35, 0.8 * wa), 48)
		_ring(m, wp, wr * 0.62 - 0.5, wr * 0.62 + 0.5, Color(1.0, 0.6, 0.25, 0.35 * wa))
		_ring(m, wp, 0.0, wr, Color(1.0, 0.55, 0.2, 0.07 * wa))
		any = true

	# Warning rings and danger zones are painted on the floor.
	for r in fx.rings:
		var k: float = r["t"] / r["d"]
		var rad: float = lerpf(r["r0"], r["r1"], k)
		var c: Color = r["c"]
		var p: Vector2 = r["p"]
		if r["f"]:
			_ring(m, p, 0.0, rad, Color(c.r, c.g, c.b, c.a * (0.35 + 0.65 * k)))
			_ring(m, p, rad - 0.75, rad + 0.75, Color(c.r, c.g, c.b, 0.9))
		else:
			var wdt: float = r["w"]
			_ring(m, p, maxf(0.0, rad - wdt * 0.5), rad + wdt * 0.5, Color(c.r, c.g, c.b, c.a * (1.0 - k * k)))
		any = true

	if any:
		m.surface_end()
	else:
		# An empty surface is an error; close it with one invisible triangle.
		_tri(m, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Color(0, 0, 0, 0))
		m.surface_end()


func _draw_decals() -> void:
	decal_n = game.decals.size()
	decal_mesh.clear_surfaces()
	if decal_n == 0:
		return
	decal_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for d in game.decals:
		_ring(decal_mesh, d["p"], 0.0, d["r"], d["c"], 16)
	decal_mesh.surface_end()
