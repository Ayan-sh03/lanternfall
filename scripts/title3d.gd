extends Node3D
## The title screen's backdrop in the 3D builds: Wren with her lantern in a
## torch-lit hall under an archway, two keepers slumped in the shadows behind
## her, dust in the air, and the camera drifting slowly round. The menu is
## drawn over it by the HUD.

const ActorsS = preload("res://scripts/actors3d.gd")
const DungeonS = preload("res://scripts/dungeon3d.gd")
const View3DS = preload("res://scripts/view3d.gd")
const CreaturesS = preload("res://scripts/creatures3d.gd")

var main
var cam: Camera3D
var t := 0.0
var aaa := false
var shadow_on := true
var actors
var torches: Array = []
var lamp: OmniLight3D
var lantern: Node3D
var nem: Node3D
var nem_y := 0.0
var nem_light: OmniLight3D
var bat_wings: Array = []


func _ready() -> void:
	aaa = RenderingServer.get_rendering_device() != null and not OS.get_cmdline_user_args().has("--lowfx")
	shadow_on = not OS.has_feature("mobile")
	DungeonS.load_kit()
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.1
	add_child(cam)
	cam.make_current()
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.004, 0.004, 0.01)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.32, 0.5)
	e.ambient_light_energy = 0.3
	if aaa:
		e.tonemap_mode = Environment.TONE_MAPPER_ACES
		e.tonemap_exposure = 1.3
		e.tonemap_white = 6.0
		e.glow_enabled = true
		e.glow_intensity = 1.0
		e.glow_bloom = 0.05
		e.glow_hdr_threshold = 0.9
		e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
		e.ssao_enabled = true
		e.ssao_intensity = 2.4
		e.ssil_enabled = true
		e.volumetric_fog_enabled = true
		e.volumetric_fog_density = 0.045
		e.volumetric_fog_albedo = Color(0.9, 0.8, 0.7)
		e.volumetric_fog_anisotropy = 0.5
		e.adjustment_enabled = true
		e.adjustment_contrast = 1.1
		e.adjustment_saturation = 1.15
		get_viewport().msaa_3d = Viewport.MSAA_2X
	we.environment = e
	add_child(we)
	_hall()
	actors = ActorsS.new()
	actors.view = self
	add_child(actors)
	var w: Dictionary = actors._make("wren")
	if not w.is_empty():
		w["root"].position = Vector3(0, 0, 0.3)
		w["model"].rotation.y = 0.35
		if w["ap"] != null:
			w["ap"].play("2H_Melee_Idle")
		var lp := OmniLight3D.new()
		lp.light_color = Color(1.0, 0.75, 0.42)
		lp.light_energy = 1.3 if aaa else 1.0
		lp.omni_range = 3.4
		lp.omni_attenuation = 1.3
		lp.shadow_enabled = shadow_on
		lp.position = Vector3(0.35, 1.1, 0.55)
		add_child(lp)
		lamp = lp
		lantern = w["model"].find_child("Lantern", true, false)
	for i in 2:
		var k: Dictionary = actors._make("husk")
		if k.is_empty():
			continue
		k["root"].position = Vector3(-2.6 + i * 5.2, 0, -1.55)
		k["model"].rotation.y = 0.5 - i * 1.0
		if k["ap"] != null:
			k["ap"].play("Skeleton_Inactive_Standing_Pose")
	_nemesis()
	# Figure light: a rim from behind so Wren stands out against the hall.
	var rim := DirectionalLight3D.new()
	rim.light_cull_mask = 2
	rim.light_color = Color(0.55, 0.7, 1.0)
	rim.light_energy = 1.4 if aaa else 0.7
	rim.light_volumetric_fog_energy = 0.0
	rim.rotation = Vector3(-0.6, PI, 0)
	add_child(rim)
	var dust := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.03)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.albedo_color = Color(1.0, 0.85, 0.6, 0.8)
	q.material = dm
	dust.mesh = q
	dust.amount = 90
	dust.lifetime = 10.0
	dust.preprocess = 10.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(4.0, 1.5, 3.0)
	dust.position = Vector3(0, 1.2, 0)
	dust.spread = 180.0
	dust.gravity = Vector3(0, -0.01, 0)
	dust.initial_velocity_max = 0.06
	add_child(dust)


## The foe that last put Wren out (main.profile["nemesis"]) waits awake in
## the archway behind her, lit red from below.
func _nemesis() -> void:
	var nm: Dictionary = main.profile.get("nemesis", {}) if main != null else {}
	if nm.is_empty():
		return
	var kind := str(nm.get("kind", ""))
	var root: Node3D = null
	match kind:
		"husk", "cantor", "brute":
			var a: Dictionary = actors._make(kind)
			if a.is_empty():
				return
			root = a["root"]
			if a["ap"] != null:
				a["ap"].play("Idle_Combat")
		"slime", "slimelet":
			root = CreaturesS.slime(kind == "slimelet")["root"]
			add_child(root)
		"moth":
			var b: Dictionary = CreaturesS.bat()
			root = b["root"]
			bat_wings = b["wings"]
			root.scale = Vector3.ONE * 1.6
			add_child(root)
		_:
			return
	nem = root
	nem_y = 1.1 if kind == "moth" else 0.0
	root.position = Vector3(0.8, nem_y, -1.95)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.18, 0.12)
	l.light_energy = 2.2 if aaa else 1.4
	l.omni_range = 2.6
	l.position = Vector3(0.8, 0.25, -1.5)
	add_child(l)
	nem_light = l


## The hall: a stone floor, a back wall with an archway between two torches,
## banners, pillars, and the clutter of a place long left.
func _hall() -> void:
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nuniform sampler2D atlas : source_color, filter_linear_mipmap;\nvoid fragment() { ALBEDO = texture(atlas, UV).rgb; ROUGHNESS = 0.85; }\n"
	mat.shader = sh
	mat.set_shader_parameter("atlas", DungeonS.atlas)
	var S := 0.5
	for z in range(-2, 4):
		for x in range(-5, 6):
			var piece := "floor_tile_small" if (x * 7 + z * 13) % 9 != 0 else "floor_tile_small_broken_A"
			_put(piece, Transform3D(Basis().scaled(Vector3.ONE * S), Vector3(x + 0.5, 0, z + 0.5)), mat)
	# Back wall, with the archway in the middle.
	for x in range(-5, 6, 2):
		var piece := "wall_arched" if x == -1 else ("wall_cracked" if x == 3 else "wall")
		_put(piece, Transform3D(Basis().scaled(Vector3.ONE * S), Vector3(x + 1.0, 0, -2.25)), mat)
	for side in [-1.0, 1.0]:
		_put("wall", Transform3D(Basis(Vector3.UP, PI * 0.5 * side).scaled(Vector3.ONE * S), Vector3(-5.25 * side, 0, 0.0)), mat)
		_put("pillar", Transform3D(Basis().scaled(Vector3(S * 0.55, S * 1.02, S * 0.55)), Vector3(2.0 * side, 0, -1.85)), mat)
		_put("banner_patternA_red", Transform3D(Basis().scaled(Vector3.ONE * S), Vector3(3.5 * side, 0, -1.95)), mat)
		var tp := Vector3(1.15 * side, 1.15, -1.98)
		_put("torch_mounted", Transform3D(Basis().scaled(Vector3.ONE * S), tp), mat)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.56, 0.24)
		l.light_energy = 2.8 if aaa else 1.5
		l.omni_range = 6.0
		l.omni_attenuation = 1.0
		l.shadow_enabled = aaa
		l.position = tp + Vector3(0, 0.4, 0.3)
		add_child(l)
		var f: CPUParticles3D = View3DS.flame(0.5)
		f.position = tp + Vector3(0, 0.38, 0.3)
		add_child(f)
		torches.append(l)
	var clutter := [["barrel_small", Vector3(-3.6, 0, -1.4), 0.5, 0.3], ["barrel_small_stack", Vector3(4.2, 0, -1.3), 0.36, -0.4],
		["crates_stacked", Vector3(-4.3, 0, 0.6), 0.32, 0.9], ["candle_triple", Vector3(-1.2, 0, -1.5), 0.5, 0.0],
		["candle_triple", Vector3(1.4, 0, -1.6), 0.5, 1.0], ["keg", Vector3(4.4, 0, 1.0), 0.32, -1.2],
		["rubble_half", Vector3(2.8, 0, 2.2), 0.2, 2.0], ["trunk_medium_A", Vector3(-2.6, 0, 1.6), 0.5, 0.6]]
	for c in clutter:
		_put(c[0], Transform3D(Basis(Vector3.UP, c[3]).scaled(Vector3.ONE * c[2]), c[1]), mat)
		if c[0] == "candle_triple":
			var cf: CPUParticles3D = View3DS.flame(0.28)
			cf.amount = 8
			cf.position = c[1] + Vector3(0, 0.42, 0)
			add_child(cf)


func _put(piece: String, xf: Transform3D, mat: Material) -> void:
	if not DungeonS.meshes.has(piece):
		return
	var mi := MeshInstance3D.new()
	mi.mesh = DungeonS.meshes[piece]
	mi.transform = xf
	mi.material_override = mat
	add_child(mi)


func _process(dt: float) -> void:
	t += dt
	# A slow drift round Wren, a little above her, looking slightly down.
	var a := 0.3 * sin(t * 0.12)
	var target := Vector3(0, 0.75, 0)
	cam.position = target + Vector3(sin(a) * 9.0, 2.7 + 0.15 * sin(t * 0.21), cos(a) * 9.0)
	cam.look_at(target + Vector3(0, -0.35, 0), Vector3.UP)
	# Wren's light burns in the lantern on her staff, not at her face.
	if lamp != null and lantern != null:
		lamp.position = lantern.global_position + Vector3(0.05, 0.05, 0.12)
	if nem != null:
		# It watches Wren, and the red light under it breathes.
		nem.rotation.y = -0.35 + 0.15 * sin(t * 0.4)
		if not bat_wings.is_empty():
			nem.position.y = nem_y + 0.08 * sin(t * 3.0)
			for wg in bat_wings:
				wg[0].rotation.z = wg[1] * 0.7 * sin(t * 14.0)
		nem_light.light_energy = (2.2 if aaa else 1.4) * (0.75 + 0.25 * sin(t * 1.7))
	for i in torches.size():
		torches[i].light_energy = (2.8 if aaa else 1.5) + 0.25 * sin(t * 9.0 + i * 2.0) + 0.12 * sin(t * 23.0 + i)
