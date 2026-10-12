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
const ActorsS = preload("res://scripts/actors3d.gd")
const DungeonS = preload("res://scripts/dungeon3d.gd")

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
global uniform vec2 lf_camdir;
"

## The walls and floor. Walls between the camera and Wren dissolve so she is
## never lost behind them.
const MAP_SHADER := "shader_type spatial;
render_mode cull_disabled, specular_disabled, diffuse_lambert;
uniform sampler2D atlas : source_color, filter_nearest;
uniform sampler2D atlas_n : hint_normal, filter_nearest;
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
	// Measured along the camera's heading, so this holds however it is turned.
	vec2 side_dir = vec2(lf_camdir.y, -lf_camdir.x);
	if (wpos.y > 0.05 && abs(dot(wnrm.xz, side_dir)) < 0.75) {
		vec2 dd = wpos.xz - lf_player.xz;
		vec2 d = vec2(dot(dd, side_dir), dot(dd, lf_camdir));
		float k = (1.0 - smoothstep(1.1, 2.2, abs(d.x))) * smoothstep(0.1, 0.6, d.y) * (1.0 - smoothstep(2.0, 3.0, d.y));
		if (bayer4(FRAGCOORD.xy) < k * 0.92) discard;
	}
	ALBEDO = c * (1.0 - f);
	NORMAL_MAP = texture(atlas_n, UV).rgb;
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

## Lit sprites carry a normal map made from their own outline (see _nmap), so
## a lamp to one side catches that side of a cloak. The light wraps well round
## the back, so nothing goes flat black just for standing past the lamp.
const SPRITE_LIT := "shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform sampler2D nmap : hint_normal, filter_nearest;
" + SPRITE_HEAD + "
void fragment() {
	vec2 uv = UV;
	if (flip) uv.x = 1.0 - uv.x;
	vec4 c = texture(tex, uv);
	if (c.a < 0.5) discard;
	if (modulate.a < 0.99 && bayer4(FRAGCOORD.xy) > modulate.a) discard;
	float f = texture(lf_fog, NODE_POSITION_WORLD.xz / lf_size).a;
	ALBEDO = mix(c.rgb * modulate.rgb, vec3(1.0), flash) * (1.0 - f);
	vec3 n = texture(nmap, uv).rgb;
	if (flip) n.x = 1.0 - n.x;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 1.0;
}
void light() {
	float wrap = clamp((dot(NORMAL, LIGHT) + 0.7) / 1.7, 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION / PI * (0.2 + 0.85 * wrap);
}
"

const SPRITE_UNLIT := "shader_type spatial;
render_mode cull_disabled, unshaded;
" + SPRITE_HEAD + SPRITE_FRAG

const SPRITE_ADD := "shader_type spatial;
render_mode cull_disabled, unshaded, blend_add, depth_draw_never;
uniform float hdr = 1.0;
uniform sampler2D tex : source_color, filter_linear;
uniform vec4 modulate : source_color = vec4(1.0);
uniform bool flip = false;
" + GLOBALS + "
void fragment() {
	vec4 c = texture(tex, UV) * modulate;
	float f = texture(lf_fog, NODE_POSITION_WORLD.xz / lf_size).a;
	ALBEDO = c.rgb * (1.0 - f) * hdr;
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

## Glowing effects. UV2.x picks how a piece is shaded: 0 flat, 1 a soft
## round spark (UV across it), 2 a staff sweep (UV.x along the swing, 1 at
## the leading edge; UV.y across it, 1 at the rim). hdr lifts them above white
## on the renderer that blooms.
const FX_ADD := "shader_type spatial;
render_mode cull_disabled, unshaded, blend_add, depth_draw_never;
uniform float hdr = 1.0;
void fragment() {
	vec3 c = COLOR.rgb;
	float a = COLOR.a;
	if (UV2.x > 0.5 && UV2.x < 1.5) {
		float r = length(UV * 2.0 - 1.0);
		a *= clamp(1.0 - r * r, 0.0, 1.0);
	} else if (UV2.x > 1.5) {
		float lead = pow(UV.x, 1.4);
		float rim = smoothstep(0.35, 1.0, UV.y);
		a *= lead * (0.18 + 0.82 * rim) * smoothstep(0.0, 0.15, 1.0 - UV.y + 0.15);
		c = mix(c, vec3(1.0), smoothstep(0.8, 1.0, UV.y) * lead);
	}
	ALBEDO = c * hdr;
	ALPHA = a;
}
"

const FX_MIX := "shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_never;
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
"

## Oil, water and webs on the floor: lit like the floor, and hidden under the
## fog of war like it.
const SURF := "shader_type spatial;
render_mode cull_disabled, specular_disabled, diffuse_lambert, depth_draw_never;
" + GLOBALS + "
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float f = texture(lf_fog, wpos.xz / lf_size).a;
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * (1.0 - f);
}
"

## Bloom: the bright parts of the finished picture, blurred by reading ever
## smaller copies of the screen, laid back over it. Only light that is already
## bright spills, so embers, eyes and the lantern glow and the rest stays crisp.
const BLOOM := "shader_type canvas_item;
uniform sampler2D scr : hint_screen_texture, filter_linear_mipmap;
uniform float threshold = 0.62;
uniform float strength = 0.8;
vec3 bright(vec2 uv, float lod) {
	vec3 c = textureLod(scr, uv, lod).rgb;
	float l = max(c.r, max(c.g, c.b));
	return c * max(l - threshold, 0.0) / max(l, 0.0001);
}
void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 base = textureLod(scr, uv, 0.0).rgb;
	// One look per level is enough: each smaller copy is already a blur, and
	// the graphics chip smooths between its pixels for free.
	vec3 b = bright(uv, 2.0) * 0.5 + bright(uv, 3.5) * 0.8 + bright(uv, 5.0) * 0.8 + bright(uv, 6.0) * 0.6;
	COLOR = vec4(base + b * strength, 1.0);
}
"

static var shaders := {}
## Normal maps made from each sprite frame, by texture.
static var nmaps := {}
static var globals_made := false

var game
var active := true
var cam: Camera3D
var env: WorldEnvironment
var map_node: Node3D
var built_seed := -1
var built_depth := -99
var built_rev := -1
## The light leaking out of hollow walls: cracks drawn every frame, and a
## lamp inside each sealed room that only this view has.
var crack_mesh := ImmediateMesh.new()
var crack_inst: MeshInstance3D
var secret_lights: Array = []
var quad := QuadMesh.new()
var sprites := {}
var lights := {}
var fx_mesh := ImmediateMesh.new()
var fx_inst: MeshInstance3D
var decal_mesh := ImmediateMesh.new()
var decal_inst: MeshInstance3D
var decal_n := -1
var surf_mesh := ImmediateMesh.new()
var surf_inst: MeshInstance3D
var surf_v := -1
var seen := {}
var order := 0
var shadow_on := false
var bloom: CanvasLayer
var shadow_light: OmniLight3D = null
## Rigged figures for Wren and the foes that have models (actors3d.gd); off
## with --billboards, which brings back the standing cut-outs.
var actors
var models_on := false
## The dungeon built from the modular kit (dungeon3d.gd); off with --pixel3d,
## which brings back the pixel-textured blocks.
var kit
var kit_on := false
var torch_lights: Array = []
var candle_fires: Array = []
## True on the Forward+ (Vulkan / Direct3D) renderer: volumetric fog, screen-
## space shadowing and bounce light, real glow, shadows from every torch.
## The phone and compatibility builds keep the lighter look.
var aaa := false
## Light for the figures alone: a soft fill from the camera's side and a cool
## rim from behind, so they read against the dark without lifting the dungeon.
var fill: DirectionalLight3D
var rim: DirectionalLight3D
## The camera can be turned around Wren and drawn in or out.
var yaw := 0.0
var yaw_to := 0.0
var zoom_k := 1.0
var zoom_to := 1.0


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
	RenderingServer.global_shader_parameter_add("lf_camdir", RenderingServer.GLOBAL_VAR_TYPE_VEC2, Vector2(0, 1))


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
	aaa = RenderingServer.get_rendering_device() != null and not OS.get_cmdline_user_args().has("--lowfx")
	if aaa:
		_grade(e)
	env = WorldEnvironment.new()
	env.environment = e
	add_child(env)
	map_node = Node3D.new()
	add_child(map_node)
	fx_inst = MeshInstance3D.new()
	fx_inst.mesh = fx_mesh
	fx_inst.material_override = _mat("fx_add", FX_ADD)
	fx_inst.material_override.set_shader_parameter("hdr", 2.6 if aaa else 1.0)
	fx_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fx_inst)
	decal_inst = MeshInstance3D.new()
	decal_inst.mesh = decal_mesh
	decal_inst.material_override = _mat("fx_mix", FX_MIX)
	decal_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(decal_inst)
	crack_inst = MeshInstance3D.new()
	crack_inst.mesh = crack_mesh
	crack_inst.material_override = _mat("fx_add", FX_ADD)
	crack_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(crack_inst)
	surf_inst = MeshInstance3D.new()
	surf_inst.mesh = surf_mesh
	surf_inst.material_override = _mat("surf", SURF)
	surf_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surf_inst)
	shadow_on = not OS.has_feature("mobile") and not game.main.profile["fast"]
	# Between the game (layer 0) and the HUD (layer 10), so text never blooms.
	bloom = CanvasLayer.new()
	bloom.layer = 5
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bm := ShaderMaterial.new()
	bm.shader = _shader("bloom", BLOOM)
	rect.material = bm
	bloom.add_child(rect)
	add_child(bloom)
	fill = DirectionalLight3D.new()
	fill.light_cull_mask = 2
	fill.light_color = Color(1.0, 0.9, 0.8)
	fill.light_energy = 0.55 if aaa else 0.35
	fill.light_specular = 0.2
	add_child(fill)
	rim = DirectionalLight3D.new()
	rim.light_cull_mask = 2
	rim.light_color = Color(0.55, 0.7, 1.0)
	rim.light_energy = 1.6 if aaa else 0.8
	rim.light_specular = 1.0
	add_child(rim)
	# Light for the figures only, never the haze in the air.
	fill.light_volumetric_fog_energy = 0.0
	rim.light_volumetric_fog_energy = 0.0
	actors = ActorsS.new()
	actors.view = self
	actors.game = game
	add_child(actors)
	models_on = not OS.get_cmdline_user_args().has("--billboards") and ActorsS.available()
	kit_on = not OS.get_cmdline_user_args().has("--pixel3d") and DungeonS.load_kit()
	kit = DungeonS.new()
	kit.game = game
	add_child(kit)
	_make_dust()
	if aaa:
		post = CanvasLayer.new()
		post.layer = 5
		var pr := ColorRect.new()
		pr.set_anchors_preset(Control.PRESET_FULL_RECT)
		pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		post_mat = _mat("post", POST)
		pr.material = post_mat
		post.add_child(pr)
		add_child(post)
		if OS.get_cmdline_user_args().has("--nopost"):
			post.visible = false
		# A shallow depth of field: the far side of the room softens a touch.
		cam_attr = CameraAttributesPractical.new()
		# Off unless asked for: at this camera height it softened Wren as well.
		cam_attr.dof_blur_far_enabled = OS.get_cmdline_user_args().has("--dof")
		cam_attr.dof_blur_far_transition = 7.0
		cam_attr.dof_blur_amount = 0.05
		cam.attributes = cam_attr
		get_viewport().msaa_3d = Viewport.MSAA_2X
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	set_active(active)


## The last touch on the finished picture: a vignette, a little fringing of
## colour toward the corners as a real lens has, and fine moving film grain.
const POST := "shader_type canvas_item;
uniform sampler2D scr : hint_screen_texture, filter_linear;
uniform float t = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float d = dot(c, c);
	float ca = 0.006 * d;
	vec3 col;
	col.r = texture(scr, uv + c * ca).r;
	col.g = texture(scr, uv).g;
	col.b = texture(scr, uv - c * ca).b;
	col *= 1.0 - smoothstep(0.12, 0.6, d) * 0.6;
	float n = fract(sin(dot(floor(FRAGCOORD.xy) + vec2(t * 61.0, t * 17.0), vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) * 0.028;
	COLOR = vec4(col, 1.0);
}
"

var post: CanvasLayer
var post_mat: ShaderMaterial
var dust: CPUParticles3D
var cam_attr: CameraAttributesPractical


## Specks of dust drifting in the air around Wren, catching the light.
func _make_dust() -> void:
	dust = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var dm := StandardMaterial3D.new()
	# Lit, not glowing: dust only shows where a lamp's light falls on it.
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.albedo_texture = Art.tex["glow"]
	dm.vertex_color_use_as_albedo = true
	q.material = dm
	dust.mesh = q
	dust.amount = 110
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(7.0, 1.2, 5.0)
	dust.direction = Vector3(1, 0.3, 0)
	dust.spread = 180.0
	dust.gravity = Vector3(0, -0.015, 0)
	dust.initial_velocity_min = 0.02
	dust.initial_velocity_max = 0.09
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.6
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.6, 0.0))
	g.add_point(0.2, Color(1.0, 0.85, 0.6, 0.9))
	g.add_point(0.8, Color(1.0, 0.8, 0.55, 0.8))
	g.set_color(g.get_point_count() - 1, Color(1.0, 0.8, 0.5, 0.0))
	dust.color_ramp = g
	add_child(dust)


## Each depth has its own air: the colour of the stone, of the haze and of
## the torches, and what drifts in the light (dust, or on the Ashen Stair, ash).
const MOODS := {
	"cellar": {"tint": Color(1.0, 0.95, 0.9), "fog": Color(0.9, 0.8, 0.7), "dens": 0.03, "glow": Color(0, 0, 0),
		"torch": Color(1.0, 0.58, 0.26), "amb": Color(0.32, 0.36, 0.55), "dust": Color(1.0, 0.85, 0.6), "fall": -0.015},
	"choir": {"tint": Color(0.86, 0.82, 0.96), "fog": Color(0.78, 0.7, 0.95), "dens": 0.04, "glow": Color(0.02, 0.0, 0.03),
		"torch": Color(1.0, 0.55, 0.62), "amb": Color(0.42, 0.32, 0.6), "dust": Color(0.9, 0.8, 1.0), "fall": -0.01},
	"archive": {"tint": Color(0.8, 0.94, 1.0), "fog": Color(0.6, 0.82, 0.88), "dens": 0.05, "glow": Color(0.0, 0.015, 0.02),
		"torch": Color(1.0, 0.68, 0.38), "amb": Color(0.25, 0.45, 0.55), "dust": Color(0.75, 0.95, 1.0), "fall": 0.02},
	"roots": {"tint": Color(1.0, 0.86, 0.72), "fog": Color(1.0, 0.62, 0.38), "dens": 0.04, "glow": Color(0.03, 0.008, 0.0),
		"torch": Color(1.0, 0.5, 0.2), "amb": Color(0.45, 0.3, 0.28), "dust": Color(1.0, 0.6, 0.3), "fall": 0.03},
	"iron": {"tint": Color(0.84, 0.88, 0.94), "fog": Color(0.72, 0.76, 0.82), "dens": 0.035, "glow": Color(0, 0, 0),
		"torch": Color(1.0, 0.75, 0.45), "amb": Color(0.34, 0.38, 0.48), "dust": Color(0.85, 0.9, 1.0), "fall": -0.01},
	"ash": {"tint": Color(0.76, 0.73, 0.7), "fog": Color(0.62, 0.6, 0.58), "dens": 0.06, "glow": Color(0.01, 0.005, 0.0),
		"torch": Color(1.0, 0.5, 0.25), "amb": Color(0.36, 0.34, 0.36), "dust": Color(0.8, 0.78, 0.76), "fall": -0.12},
	"forge": {"tint": Color(1.0, 0.76, 0.62), "fog": Color(1.0, 0.45, 0.22), "dens": 0.05, "glow": Color(0.06, 0.015, 0.0),
		"torch": Color(1.0, 0.42, 0.15), "amb": Color(0.5, 0.25, 0.2), "dust": Color(1.0, 0.55, 0.25), "fall": 0.05},
}
var torch_col := Color(1.0, 0.58, 0.26)


func _mood(theme: String) -> void:
	var m: Dictionary = MOODS.get(theme, MOODS["cellar"])
	kit.set_tint(m["tint"])
	torch_col = m["torch"]
	var e: Environment = env.environment
	if aaa:
		e.volumetric_fog_albedo = m["fog"]
		e.volumetric_fog_density = m["dens"] * 0.55
		e.volumetric_fog_emission = m["glow"]
		e.ambient_light_color = m["amb"]
	if dust != null:
		dust.gravity = Vector3(0, m["fall"], 0)
		var g: Gradient = dust.color_ramp
		var c: Color = m["dust"]
		for i in g.get_point_count():
			var a := g.get_color(i).a
			g.set_color(i, Color(c.r, c.g, c.b, a))
		dust.amount = 220 if theme == "ash" else 110


## The full look: filmic tonemapping, glow from anything bright, contact
## shadows and bounce light, and a haze in the air that the lamps light up.
func _grade(e: Environment) -> void:
	e.background_color = Color(0.004, 0.004, 0.01)
	e.ambient_light_color = Color(0.32, 0.36, 0.55)
	e.ambient_light_energy = 0.38
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.35
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_normalized = false
	e.glow_intensity = 0.9
	e.glow_strength = 1.0
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 0.95
	e.glow_hdr_scale = 2.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		e.set_glow_level(i, 1.0 if i in [1, 2, 3, 4] else 0.0)
	e.ssao_enabled = true
	e.ssao_radius = 0.9
	e.ssao_intensity = 2.6
	e.ssao_power = 1.6
	e.ssao_detail = 0.6
	e.ssil_enabled = true
	e.ssil_radius = 3.0
	e.ssil_intensity = 0.9
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.035
	e.volumetric_fog_albedo = Color(0.85, 0.8, 0.75)
	e.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	e.volumetric_fog_anisotropy = 0.45
	e.volumetric_fog_length = 48.0
	e.volumetric_fog_detail_spread = 2.0
	e.volumetric_fog_ambient_inject = 0.15
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 1.12


func _mat(id: String, code: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(id, code)
	return m


## Bloom copies and shrinks the whole picture every frame: nothing for a
## desktop graphics card, but phones and the "fast" picture go without.
func bloom_ok() -> bool:
	# Forward+ has real glow of its own; this one is for the other renderer.
	return not aaa and not OS.has_feature("mobile") and not game.main.profile["fast"] \
		and not OS.get_cmdline_user_args().has("--nobloom")


## Switches between this view and the original flat one, live, mid-run.
func set_active(on: bool) -> void:
	active = on
	visible = on
	if game != null:
		game.mid_down = false
	if cam != null:
		cam.current = on
	if bloom != null:
		bloom.visible = on and bloom_ok()
	if post != null:
		post.visible = on and not OS.get_cmdline_user_args().has("--nopost")
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

func _process(dt: float) -> void:
	if not active or game == null or game.W == 0:
		return
	_turn(dt)
	if game.floor_seed != built_seed or game.depth != built_depth or game.map_rev != built_rev:
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
	if models_on:
		actors.sync(dt)
	for r in roots:
		var node: Node2D = r[0]
		if node.is_queued_for_deletion() or not node.visible:
			continue
		if models_on and node.has_meta("ghost") and ActorsS.MODELS.has(node.get_meta("ghost")):
			continue
		var ground: Vector2 = node.global_position + Vector2(0, r[2])
		_walk(node, ground, r[1], Color.WHITE, 0)
	_sweep(sprites)
	_sweep(lights)
	# Wren's light comes from the lantern itself, so it swings with the staff.
	if models_on and shadow_light != null:
		var lp: Vector3 = actors.lantern_pos()
		if lp != Vector3.INF:
			shadow_light.position = shadow_light.position.lerp(lp + Vector3(0, 0.05, 0), 0.6)
	_draw_fx()
	if game.decals.size() != decal_n:
		_draw_decals()
	if game.surf.version != surf_v:
		_draw_surfaces()
	_draw_cracks()
	_flicker()


func _sweep(pool: Dictionary) -> void:
	for id in pool.keys():
		if not seen.has(id):
			pool[id].queue_free()
			pool.erase(id)


func _walk(n: Node, ground: Vector2, flat: bool, tint: Color, depth: int) -> void:
	if models_on and actors.skip.has(n.get_instance_id()):
		return
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
	# Anything standing in Wren's light throws a shadow away from it, except
	# Wren herself, who carries the lamp.
	var casts: bool = shadow_on and not flat and (kind == "lit" or kind == "unlit") and ground != game.ppos
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
				mi.material_override.set_shader_parameter("hdr", 1.8 if aaa else 1.0)
			_:
				mi.material_override = _mat("blend", SPRITE_BLEND)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		sprites[id] = mi
		if casts:
			# The visible card faces the camera; this one, seen only by the
			# shadow, turns to face the lamp so the shadow has its full shape.
			var sh := MeshInstance3D.new()
			sh.mesh = quad
			sh.material_override = mi.material_override
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			mi.add_child(sh)
			mi.set_meta("shadow", sh)
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("tex", s.texture)
	m.set_shader_parameter("modulate", tint)
	m.set_shader_parameter("flip", s.flip_h)
	if kind == "lit" and s.material is ShaderMaterial:
		m.set_shader_parameter("flash", s.material.get_shader_parameter("flash"))
	if kind == "lit":
		m.set_shader_parameter("nmap", _nmap(s.texture))

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
		if yaw != 0.0:
			# Still square to the camera, however it has been turned.
			xf.basis = Basis(Vector3.UP, yaw) * xf.basis
		# Later children are drawn over earlier ones in 2D; nudge them toward
		# the camera so they still win.
		# In 2D the feet hang a few pixels below the anchor; here that would
		# put them under the floor.
		var side_off := Vector3((c.x - ground.x) / TS, 0.0, order * 0.002)
		if yaw != 0.0:
			side_off = Basis(Vector3.UP, yaw) * side_off
		xf.origin = Vector3(ground.x / TS, (ground.y - c.y + FOOT) * K / TS, ground.y / TS) + side_off
	mi.transform = xf
	if mi.has_meta("shadow"):
		var sh: MeshInstance3D = mi.get_meta("shadow")
		sh.visible = not lies and shadow_light != null and shadow_light.visible
		if sh.visible:
			var to := Vector2(shadow_light.position.x - xf.origin.x, shadow_light.position.z - xf.origin.z)
			if to.length() > 0.01:
				var d := to.normalized()
				var side := Vector3(d.y, 0.0, -d.x)
				var sx := Transform3D()
				sx.basis.x = (side * cos(r) + Vector3(0, -sin(r) * K, 0)) * w
				sx.basis.y = (side * sin(r) + Vector3(0, cos(r) * K, 0)) * h
				sx.basis.z = Vector3(d.x, 0.0, d.y)
				sx.origin = xf.origin
				# The child sits under the visible card; undo the card's own transform.
				sh.transform = xf.affine_inverse() * sx


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
		o.shadow_enabled = l == game.plight and shadow_on
		if l == game.plight:
			shadow_light = o
	var p := l.global_position
	var hgt := maxf(6.0, ground.y - p.y + 4.0)
	o.position = Vector3(p.x / TS, hgt * K / TS, ground.y / TS)
	o.light_color = l.color
	# Wren's lamp is right beside her, so it is held back a little or her own
	# cloak would glare.
	if aaa:
		# Filmic tonemapping and the haze both eat light: lamps burn hotter here.
		o.light_energy = l.energy * (2.6 if l == game.plight else 2.4)
		o.omni_attenuation = 0.85
	else:
		o.light_energy = l.energy * (1.05 if l == game.plight else 1.6)
	o.omni_range = l.texture_scale * 64.0 / TS * 1.15
	o.visible = l.enabled


# --- Camera ---------------------------------------------------------------------------

func _update_camera() -> void:
	var c2: Vector2 = game.cam.position + game.cam.offset
	var z: float = game.cam.zoom.x
	var target := Vector3(c2.x / TS, 0.4, (c2.y + 6.0) / TS)
	var vis_h: float = get_viewport().get_visible_rect().size.y / (z * TS)
	var dist := vis_h * 0.5 / tan(deg_to_rad(FOV) * 0.5) * 0.9 * zoom_k
	var back := Vector3(sin(yaw) * cos(PITCH), sin(PITCH), cos(yaw) * cos(PITCH))
	cam.position = target + back * dist
	cam.look_at(target, Vector3.UP)
	if cam_attr != null:
		cam_attr.dof_blur_far_distance = dist + 3.0
	if post_mat != null:
		post_mat.set_shader_parameter("t", fmod(game.anim_t, 100.0))
	if dust != null:
		dust.position = target + Vector3(0, 0.9, 0)
	RenderingServer.global_shader_parameter_set("lf_camdir", Vector2(sin(yaw), cos(yaw)))
	# Fill comes from over the camera's shoulder; rim from the far side, high.
	fill.global_transform = Transform3D(Basis.looking_at(-back + Vector3(0.3, 0, 0), Vector3.UP), Vector3.ZERO)
	var behind := Vector3(-back.x, 0.0, -back.z).normalized()
	rim.global_transform = Transform3D(Basis.looking_at(-(behind + Vector3(0, 1.1, 0)).normalized(), Vector3.UP), Vector3.ZERO)


## Turning and zooming: drag with the middle button, or hold [ and ] to turn;
## the wheel zooms. Home puts the camera back.
func _turn(dt: float) -> void:
	if not game.hud.blocking() and not game.bot:
		var k := float(Input.is_physical_key_pressed(KEY_BRACKETRIGHT)) - float(Input.is_physical_key_pressed(KEY_BRACKETLEFT))
		yaw_to += k * dt * 2.0
		if Input.is_physical_key_pressed(KEY_HOME):
			yaw_to = 0.0
			zoom_to = 1.0
	yaw = lerp_angle(yaw, yaw_to, 1.0 - exp(-dt * 12.0))
	zoom_k = lerpf(zoom_k, zoom_to, 1.0 - exp(-dt * 10.0))


func _unhandled_input(ev: InputEvent) -> void:
	if not active or game == null or game.hud.blocking():
		return
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_to = maxf(0.55, zoom_to * 0.9)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_to = minf(1.6, zoom_to / 0.9)
	elif ev is InputEventMouseMotion and game.mid_down:
		if absf(ev.relative.x) > 0.0:
			yaw_to -= ev.relative.x * 0.008
			if absf(ev.relative.x) > 2.0:
				game.mid_dragged = true


# --- The dungeon ----------------------------------------------------------------------

func _build_map() -> void:
	built_seed = game.floor_seed
	built_depth = game.depth
	built_rev = game.map_rev
	for l in secret_lights:
		l.queue_free()
	secret_lights.clear()
	for t in torch_lights:
		t["light"].queue_free()
		t["fire"].queue_free()
	torch_lights.clear()
	for f in candle_fires:
		f.queue_free()
	candle_fires.clear()
	if kit_on:
		kit.build()
		var info0: Dictionary = Story.GALLERY if game.depth <= 0 else Story.DEPTHS[game.depth - 1]
		_mood(game.gallery_theme if game.depth <= 0 and game.gallery_theme != "" else str(info0["theme"]))
		for t in kit.torches:
			_torch(t)
		for c in kit.candles:
			var f := flame(0.28)
			f.amount = 8
			f.position = c
			add_child(f)
			candle_fires.append(f)
	for sc in game.secrets:
		if sc["open"]:
			continue
		var c: Vector2i = sc["c"]
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.7, 0.35)
		l.light_energy = 2.0
		l.omni_range = 3.8
		l.omni_attenuation = 1.3
		l.light_specular = 0.0
		l.position = Vector3(c.x + 0.5, wall_h() + 0.3, c.y + 0.5)
		add_child(l)
		secret_lights.append(l)
	for c in map_node.get_children():
		c.queue_free()
	var info: Dictionary = Story.GALLERY if game.depth <= 0 else Story.DEPTHS[game.depth - 1]
	var theme: String = info["theme"]
	if game.depth <= 0 and game.gallery_theme != "":
		theme = game.gallery_theme
	var atlas := _atlas(theme)
	var mat := _mat("map", MAP_SHADER)
	mat.set_shader_parameter("atlas", ImageTexture.create_from_image(atlas))
	mat.set_shader_parameter("atlas_n", ImageTexture.create_from_image(_atlas_normals(atlas)))
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
					if Vector2i(x, y) == game.stairs_tile and not kit_on:
						_stairwell(st, x, y, aw, ah)
						any = true
					elif kit_on:
						continue
					elif _tile(x, y) == 1:
						_floor(st, x, y, aw, ah)
						any = true
					elif _near_floor(x, y):
						_wall(st, x, y, aw, ah)
						any = true
			if not any:
				continue
			st.generate_tangents()
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


## A normal map for a sprite frame, worked out from its shape: each pixel's
## height is how far it sits inside the outline, so a figure reads as rounded,
## with a little of its own shading pressed in for surface detail.
static func _nmap(tex: Texture2D) -> Texture2D:
	var id := tex.get_instance_id()
	if nmaps.has(id):
		return nmaps[id]
	var img := tex.get_image()
	var w := img.get_width()
	var h := img.get_height()
	var far := 99.0
	var d := PackedFloat32Array()
	d.resize(w * h)
	for y in h:
		for x in w:
			d[y * w + x] = far if img.get_pixel(x, y).a > 0.5 else 0.0
	# Two sweeps give each pixel its distance to the nearest empty one.
	for y in h:
		for x in w:
			var i := y * w + x
			if d[i] == 0.0:
				continue
			var v := far
			if x > 0: v = minf(v, d[i - 1] + 1.0)
			else: v = 1.0
			if y > 0: v = minf(v, d[i - w] + 1.0)
			else: v = 1.0
			if x > 0 and y > 0: v = minf(v, d[i - w - 1] + 1.41)
			if x < w - 1 and y > 0: v = minf(v, d[i - w + 1] + 1.41)
			d[i] = minf(d[i], v)
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			if d[i] == 0.0:
				continue
			var v := d[i]
			if x < w - 1: v = minf(v, d[i + 1] + 1.0)
			else: v = 1.0
			if y < h - 1: v = minf(v, d[i + w] + 1.0)
			else: v = 1.0
			if x < w - 1 and y < h - 1: v = minf(v, d[i + w + 1] + 1.41)
			if x > 0 and y < h - 1: v = minf(v, d[i + w - 1] + 1.41)
			d[i] = v
	var hgt := PackedFloat32Array()
	hgt.resize(w * h)
	for y in h:
		for x in w:
			var i := y * w + x
			if d[i] == 0.0:
				continue
			var c := img.get_pixel(x, y)
			hgt[i] = sqrt(clampf(d[i] / 3.5, 0.0, 1.0)) + 0.18 * c.get_luminance()
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var i := y * w + x
			var hl := hgt[y * w + maxi(x - 1, 0)]
			var hr := hgt[y * w + mini(x + 1, w - 1)]
			var hu := hgt[maxi(y - 1, 0) * w + x]
			var hd := hgt[mini(y + 1, h - 1) * w + x]
			# Image rows run down, normal-map green runs up.
			var n := Vector3((hl - hr) * 1.6, (hd - hu) * 1.6, 1.0).normalized()
			out.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	var t := ImageTexture.create_from_image(out)
	nmaps[id] = t
	return t


## A normal map for the floor and wall atlas: mortar and grout are dark, so
## brightness stands in for height and every slab edge catches the light.
func _atlas_normals(atlas: Image) -> Image:
	var w := atlas.get_width()
	var h := atlas.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			# Stay inside each 16-pixel cell so neighbouring tiles do not bleed.
			var cx := int(x / 16.0) * 16
			var ch := 24 if cx >= 8 * 16 else 16
			var l := atlas.get_pixel(maxi(x - 1, cx), y).get_luminance()
			var r := atlas.get_pixel(mini(x + 1, cx + 15), y).get_luminance()
			var u := atlas.get_pixel(x, maxi(y - 1, 0)).get_luminance()
			var dn := atlas.get_pixel(x, mini(y + 1, ch - 1)).get_luminance()
			var n := Vector3((l - r) * 1.2, (dn - u) * 1.2, 1.0).normalized()
			out.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	return out


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
	m.surface_set_uv(Vector2(0.5, 0.5))
	m.surface_set_uv2(Vector2.ZERO)
	m.surface_add_vertex(a)
	m.surface_add_vertex(b)
	m.surface_add_vertex(c)


## A quad with its own UVs and shading mode (see FX_ADD).
func _quad_uv(m: ImmediateMesh, v: Array, uv: Array, col: Color, mode: float) -> void:
	m.surface_set_color(col)
	m.surface_set_uv2(Vector2(mode, 0.0))
	for i in [0, 1, 2, 0, 2, 3]:
		m.surface_set_uv(uv[i])
		m.surface_add_vertex(v[i])


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
		var sz: float = p["s"] * (0.5 + 0.5 * k) / TS * 0.95
		var c: Color = p["c"]
		var pos: Vector2 = p["p"]
		var o: Vector2 = p.get("o", pos)
		var h := maxf(1.0, LIFT + (o.y - pos.y))
		var at := Vector3(pos.x / TS, h * K / TS, (o.y + LIFT) / TS)
		_quad_uv(m, [at - right * sz - up * sz, at + right * sz - up * sz, at + right * sz + up * sz, at - right * sz + up * sz],
			[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Color(c.r, c.g, c.b, c.a * k), 1.0)
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
		var segs := 20
		# The sweep is drawn as it happens: it grows from where the staff
		# started to where it is now, brightest at the leading edge.
		var cw: bool = sl.get("cw", true)
		var pr := clampf((1.0 - k) * 2.6, 0.25, 1.0)
		for j in segs:
			var u0 := float(j) / segs
			var u1 := float(j + 1) / segs
			var s0 := u0 if cw else 1.0 - u0
			var s1 := u1 if cw else 1.0 - u1
			if minf(s0, s1) > pr:
				continue
			var d0 := Vector2.from_angle(a_start + arc * u0)
			var d1 := Vector2.from_angle(a_start + arc * u1)
			var in0 := reach * (0.45 + 0.5 * pow(absf(u0 * 2.0 - 1.0), 1.5))
			var in1 := reach * (0.45 + 0.5 * pow(absf(u1 * 2.0 - 1.0), 1.5))
			var l0 := clampf(s0 / pr, 0.0, 1.0)
			var l1 := clampf(s1 / pr, 0.0, 1.0)
			_quad_uv(m, [_fx3(o + d0 * reach, 5.0), _fx3(o + d1 * reach, 5.0), _fx3(o + d1 * in1, 5.0), _fx3(o + d0 * in0, 5.0)],
				[Vector2(l0, 1.0), Vector2(l1, 1.0), Vector2(l1, 0.0), Vector2(l0, 0.0)], col, 2.0)
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

	# Impact bursts face the camera, like the flash they are.
	for im in fx.impacts:
		var k: float = 1.0 - im["t"] / im["d"]
		var c: Color = im["c"]
		var col := Color(1, 1, 1, k).lerp(Color(c.r, c.g, c.b, k), clampf(1.0 - k * 1.6, 0.0, 1.0))
		var o3 := _fx3(im["p"])
		for sp in fx.impact_spikes(im):
			var d := Vector2.from_angle(sp.x)
			var dv: Vector3 = (right * d.x - up * d.y) / TS
			var sv: Vector3 = (right * -d.y - up * d.x) / TS * sp.z * k
			var tip: Vector3 = o3 + dv * sp.y * (0.55 + 0.45 * (1.0 - k))
			_quad_fx(m, tip, o3 + sv, o3 - dv * 2.0, o3 - sv, col)
		var cr: float = 4.0 * im["s"] * k / TS
		_quad_fx(m, o3 - right * cr - up * cr, o3 + right * cr - up * cr, o3 + right * cr + up * cr, o3 - right * cr + up * cr, Color(1, 1, 1, k))
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

	# Burning oil and webs: a glow on the floor under the flames.
	for sf in game.surf.list:
		if sf["k"] != "fire" or not game.vis_at(sf["p"]):
			continue
		var fk := clampf(sf["t"], 0.0, 1.0) * (0.8 + 0.2 * sin(game.anim_t * 17.0 + sf["seed"]))
		for b in game.SurfS.blobs(sf):
			_ring(m, b[0], 0.0, b[1], Color(1.0, 0.42, 0.1, 0.5 * fk), 16)
			_ring(m, b[0], 0.0, b[1] * 0.55, Color(1.0, 0.7, 0.3, 0.35 * fk), 12)
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


## The floor's oil, water and webs, rebuilt only when they change. Fire is
## drawn with the other glowing effects, every frame.
func _draw_surfaces() -> void:
	surf_v = game.surf.version
	surf_mesh.clear_surfaces()
	var list: Array = game.surf.list
	if list.is_empty():
		return
	var SurfS = game.SurfS
	surf_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	surf_mesh.surface_set_normal(Vector3.UP)
	var n := 0
	for s in list:
		var h := 0.02 + n * 0.0005
		n += 1
		match s["k"]:
			"water", "oil", "fire":
				var col: Color = SurfS.WATER_COL if s["k"] == "water" else (SurfS.OIL_COL if s["k"] == "oil" else Color(0.06, 0.02, 0.0, 0.55))
				for b in SurfS.blobs(s):
					_disc(surf_mesh, b[0], b[1], col, h)
			"web":
				for l in SurfS.web_lines(s):
					_strand(surf_mesh, l[0], l[1], 0.7, SurfS.WEB_COL, h)
	surf_mesh.surface_end()


func _disc(m: ImmediateMesh, p: Vector2, r: float, col: Color, h: float) -> void:
	var c := to3(p) + Vector3(0, h, 0)
	var segs := 14
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		m.surface_set_color(col)
		m.surface_add_vertex(c)
		m.surface_add_vertex(c + Vector3(cos(a0), 0, sin(a0)) * r / TS)
		m.surface_add_vertex(c + Vector3(cos(a1), 0, sin(a1)) * r / TS)


func _strand(m: ImmediateMesh, a: Vector2, b: Vector2, w: float, col: Color, h: float) -> void:
	var d := (b - a).normalized().orthogonal() * w * 0.5
	var y := Vector3(0, h, 0)
	var p0 := to3(a + d) + y
	var p1 := to3(b + d) + y
	var p2 := to3(b - d) + y
	var p3 := to3(a - d) + y
	for v in [p0, p1, p2, p0, p2, p3]:
		m.surface_set_color(col)
		m.surface_add_vertex(v)


## A hollow wall shows itself here and nowhere else: light seeps through a
## jagged crack in the face toward the room, and glows above the sealed room.
func _draw_cracks() -> void:
	crack_mesh.clear_surfaces()
	var any := false
	var t: float = game.anim_t
	for k in secret_lights.size():
		secret_lights[k].light_energy = 1.8 + 0.5 * sin(t * 2.1 + k)
	for sc in game.secrets:
		if sc["open"]:
			continue
		var f: Vector2i = sc["f"]
		if game.seen[f.y * game.W + f.x] == 0:
			continue
		if not any:
			crack_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			any = true
		var w: Vector2i = sc["w"]
		var d: Vector2i = f - w
		# The face of the wall tile that looks onto the floor before it.
		var mid := Vector3(w.x + 0.5 + d.x * 0.51, 0.0, w.y + 0.5 + d.y * 0.51)
		var along := Vector3(absf(d.y), 0, absf(d.x))
		var r := RandomNumberGenerator.new()
		r.seed = w.x * 7919 + w.y
		var pulse := 0.75 + 0.25 * sin(t * 2.1)
		var col := Color(1.0, 0.68, 0.3, 0.9 * pulse)
		var p := mid + along * r.randf_range(-0.15, 0.15)
		var steps := 7
		for i in steps:
			var q := mid + along * r.randf_range(-0.3, 0.3) + Vector3(0, wall_h() * (i + 1) / steps, 0)
			_crack_seg(p, q, along, 0.055, col)
			_crack_seg(p, q, along, 0.14, Color(col.r, col.g * 0.8, col.b * 0.6, col.a * 0.25))
			if r.randf() < 0.45:
				var br := q + along * r.randf_range(-0.25, 0.25) + Vector3(0, -0.15, 0)
				_crack_seg(q, br, along, 0.02, Color(col.r, col.g, col.b, col.a * 0.7))
			p = q
		# A soft spill of light on the floor at its foot.
		var foot := Vector2((mid.x + d.x * 0.1) * TS, (mid.z + d.y * 0.1) * TS)
		var cc := to3(foot) + Vector3(0, 0.03, 0)
		for i in 12:
			var a0 := TAU * i / 12
			var a1 := TAU * (i + 1) / 12
			_tri(crack_mesh, cc, cc + Vector3(cos(a0), 0, sin(a0)) * 0.45, cc + Vector3(cos(a1), 0, sin(a1)) * 0.45,
				Color(1.0, 0.6, 0.25, 0.12 * pulse))
	if any:
		crack_mesh.surface_end()


## Torches flicker, and only those near Wren are lit at all.
func _flicker() -> void:
	var t: float = game.anim_t
	var pp := to3(game.ppos)
	for tl in torch_lights:
		var l: OmniLight3D = tl["light"]
		var near := l.position.distance_squared_to(pp) < 196.0
		l.visible = near
		tl["fire"].emitting = near
		if near:
			var s: float = tl["seed"]
			l.light_energy = (2.5 if aaa else 1.35) + 0.2 * sin(t * 9.0 + s) + 0.12 * sin(t * 23.0 + s * 2.0)
	for f in candle_fires:
		f.emitting = f.position.distance_squared_to(pp) < 196.0


func wall_h() -> float:
	return DungeonS.WALL_H if kit_on else WALL_H


## A torch on the wall: a flickering light, and real flames rising off it.
func _torch(t: Dictionary) -> void:
	var l := OmniLight3D.new()
	l.light_color = torch_col
	l.light_energy = 2.6 if aaa else 1.4
	l.omni_range = 5.6 if aaa else 4.6
	l.omni_attenuation = 1.0 if aaa else 1.4
	l.light_specular = 0.25
	l.shadow_enabled = aaa
	l.shadow_bias = 0.05
	l.position = t["p"]
	add_child(l)
	var fire := flame(0.5)
	fire.position = t["p"] + Vector3(0, -0.12, 0)
	add_child(fire)
	torch_lights.append({"light": l, "fire": fire, "seed": float(t["seed"])})


static var flame_mat: StandardMaterial3D = null


## A small fire that works on every renderer: soft additive sprites that rise,
## brighten to yellow and fade out through orange to nothing.
static func flame(size: float) -> CPUParticles3D:
	if flame_mat == null:
		flame_mat = StandardMaterial3D.new()
		flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		flame_mat.albedo_texture = Art.tex["glow"]
		flame_mat.vertex_color_use_as_albedo = true
		flame_mat.no_depth_test = false
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3) * size
	q.material = flame_mat
	p.mesh = q
	p.amount = 18
	p.lifetime = 0.55
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.05 * size
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 1.4, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.5
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.25, 1.0))
	sc.add_point(Vector2(1, 0.15))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.6, 0.9))
	g.add_point(0.35, Color(1.0, 0.55, 0.15, 0.8))
	g.set_color(g.get_point_count() - 1, Color(0.6, 0.1, 0.02, 0.0))
	p.color_ramp = g
	return p


func _crack_seg(a: Vector3, b: Vector3, along: Vector3, wdt: float, col: Color) -> void:
	var o := along * wdt
	_quad_fx(crack_mesh, a - o, b - o, b + o, a + o, col)
