extends Node3D
## Real 3D figures for the 3D view: Wren and the foes that have a model are
## drawn as rigged, animated low-poly characters (KayKit, CC0) instead of
## standing cut-outs. Like the rest of the 3D view this only watches the game:
## where each one stands, which way it faces and what it is doing are all read
## from the flat game, and turned into a position, a heading and an animation.
## Foes without a model (bats, ink, cinder skulls) stay as sprites.

const TS := 16.0
const CreaturesS = preload("res://scripts/creatures3d.gd")
## Creatures built from shapes in code (creatures3d.gd) rather than loaded.
const PROC := ["slime", "slimelet", "wisp", "moth"]

## Model file, scale, and the meshes to hide (weapons the pack hands them).
const MODELS := {
	"wren": {"file": "wren", "scale": 0.72, "hide": ["Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Knife", "Throwable"]},
	"husk": {"file": "skeleton_minion", "scale": 0.7, "hide": []},
	"gloam": {"file": "skeleton_rogue", "scale": 0.7, "hide": []},
	"cantor": {"file": "skeleton_mage", "scale": 0.7, "hide": []},
	"brute": {"file": "skeleton_warrior", "scale": 0.86, "hide": []},
	"warden": {"file": "maren", "scale": 0.95, "hide": ["Spellbook", "Spellbook_open", "1H_Wand", "Mage_Hat"]},
}
const LOOPS := ["Idle", "Idle_Combat", "2H_Melee_Idle", "Running_A", "Running_B", "Running_C", "Walking_A",
	"Walking_D_Skeletons", "Spellcasting", "Skeleton_Inactive_Standing_Pose"]
const EYES := {"husk": Color(0.4, 0.9, 1.0), "gloam": Color(0.75, 0.45, 1.0), "cantor": Color(1.0, 0.35, 0.7),
	"brute": Color(1.0, 0.65, 0.25)}

static var scenes := {}

const OVERLAY := "shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 col : source_color = vec4(0.0);
void fragment() {
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
"
static var overlay_shader: Shader
static var wren_mat: Material = null

var view
var game
## Entity instance id -> actor: {"root", "ap", "kind", "anim", "act", "act_t", "yaw", "flash"}
var actors := {}
var corpses: Array = []
## The game's props drawn as kit models, by the instance id of their node.
var props := {}
var seal: OmniLight3D = null
## Sprites the 3D view must not draw because a model stands in for them.
var skip := {}
var wren_seen := {}


## Loads a model once (from raw .glb bytes, so nothing needs importing) and
## keeps it packed, ready to be stamped out.
static func scene(file: String) -> PackedScene:
	if scenes.has(file):
		return scenes[file]
	var ps: PackedScene = null
	var bytes := FileAccess.get_file_as_bytes("res://models/%s.glbx" % file)
	if not bytes.is_empty():
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_buffer(bytes, "res://models/", st) == OK:
			var root := doc.generate_scene(st)
			if root != null:
				ps = PackedScene.new()
				ps.pack(root)
				root.free()
	scenes[file] = ps
	return ps


static func available() -> bool:
	return scene("wren") != null


func _ready() -> void:
	if overlay_shader == null:
		overlay_shader = Shader.new()
		overlay_shader.code = OVERLAY


func _make(kind: String) -> Dictionary:
	var spec: Dictionary = MODELS[kind]
	var ps := scene(spec["file"])
	if ps == null:
		return {}
	var root: Node3D = ps.instantiate()
	var sk: Skeleton3D = root.find_child("Skeleton3D", true, false)
	for h in spec["hide"]:
		var n := root.find_child(h, true, false)
		if n != null:
			n.queue_free()
	if kind == "wren" and sk != null:
		_give_staff(sk)
	var holder := Node3D.new()
	holder.add_child(root)
	root.scale = Vector3.ONE * spec["scale"]
	add_child(holder)
	var ov := ShaderMaterial.new()
	ov.shader = overlay_shader
	var meshes: Array = []
	_meshes(root, meshes)
	# Wren carries the lamp that throws the shadows, so she throws none herself.
	var shadows: bool = view.shadow_on and kind != "wren"
	for m in meshes:
		m.material_overlay = ov
		# On their own light layer: the figure lights touch only them.
		m.layers = 1 | 2
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if kind == "wren" and m.name != "Lantern":
			_recolor(m)
		if m.name.ends_with("_Eyes") and EYES.has(kind):
			var em := StandardMaterial3D.new()
			em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			em.albedo_color = EYES[kind] * 1.6
			m.material_override = em
	if kind == "gloam":
		# A shade: the dark wearing a keeper's shape.
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.07, 0.05, 0.12)
		dark.roughness = 1.0
		for m in meshes:
			if not m.name.ends_with("_Eyes"):
				m.material_override = dark
	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	if ap != null:
		for a in LOOPS:
			if ap.has_animation(a):
				ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	return {"root": holder, "model": root, "ap": ap, "kind": kind, "anim": "", "act": "", "act_t": 0.0,
		"yaw": 0.0, "ov": ov, "meshes": meshes, "seen": {}}


## The pack's rogue wears forest green; Wren's cloak is lamplighter's navy.
func _recolor(m: MeshInstance3D) -> void:
	if m.mesh == null or m.mesh.get_surface_count() == 0:
		return
	var src = m.get_active_material(0)
	if not (src is StandardMaterial3D) or src.albedo_texture == null:
		return
	if wren_mat == null:
		var img: Image = src.albedo_texture.get_image()
		if img == null:
			return
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.s > 0.2 and c.h > 0.17 and c.h < 0.5:
					c = Color.from_hsv(0.61, c.s * 0.75, c.v * 0.85, c.a)
					img.set_pixel(x, y, c)
		var mat: StandardMaterial3D = src.duplicate()
		mat.albedo_texture = ImageTexture.create_from_image(img)
		wren_mat = mat
	for i in m.mesh.get_surface_count():
		m.set_surface_override_material(i, wren_mat)


func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


## Wren carries the lamplighter's staff (borrowed from the mage model) with a
## lantern burning at its head.
func _give_staff(sk: Skeleton3D) -> void:
	var mp := scene("maren")
	if mp == null:
		return
	var tmp: Node3D = mp.instantiate()
	var src := tmp.find_child("2H_Staff", true, false)
	var msk: Skeleton3D = tmp.find_child("Skeleton3D", true, false)
	var hand := sk.find_bone("handslot.r")
	if src is BoneAttachment3D and msk != null and hand >= 0:
		# The mage carries it on a bone of its own; Wren has none, so it hangs
		# from her right hand at the same offset from the hand as on the mage.
		var sb := msk.find_bone(src.bone_name)
		var hb := msk.find_bone("handslot.r")
		var rel := Transform3D()
		if sb >= 0 and hb >= 0:
			rel = msk.get_bone_global_rest(hb).affine_inverse() * msk.get_bone_global_rest(sb)
		var att := BoneAttachment3D.new()
		att.bone_name = "handslot.r"
		att.name = "Staff"
		sk.add_child(att)
		var holder := Node3D.new()
		holder.transform = rel
		att.add_child(holder)
		for c in src.get_children():
			holder.add_child(c.duplicate())
		var lantern := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.24, 0.3, 0.24)
		lantern.mesh = bm
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.25, 0.18, 0.1)
		lm.emission_enabled = true
		lm.emission = Color(1.0, 0.68, 0.3)
		lm.emission_energy_multiplier = 2.5
		lantern.material_override = lm
		lantern.position = Vector3(0.0, 1.32, 0.0)
		lantern.name = "Lantern"
		holder.add_child(lantern)
	tmp.free()


## Called by the 3D view each frame, before it draws the sprites.
func sync(dt: float) -> void:
	skip.clear()
	var live := {}
	# Wren.
	var w: Dictionary = actors.get(0, {})
	if w.is_empty():
		w = _make("wren")
		if w.is_empty():
			return
		actors[0] = w
	live[0] = true
	_wren(w, dt)
	skip[game.pspr.get_instance_id()] = true
	skip[game.staff.get_instance_id()] = true
	skip[game.pglow.get_instance_id()] = true
	# The foes that have a model.
	for e in game.enemies:
		if not is_instance_valid(e) or not (MODELS.has(e.kind) or PROC.has(e.kind)):
			continue
		var id: int = e.get_instance_id()
		if e.dead:
			continue
		var a: Dictionary = actors.get(id, {})
		if a.is_empty():
			a = _make_proc(e.kind) if PROC.has(e.kind) else _make(e.kind)
			if a.is_empty():
				continue
			actors[id] = a
			a["was_awake"] = e.awake
		live[id] = true
		if PROC.has(e.kind):
			_proc(a, e, dt)
		else:
			_foe(a, e, dt)
		skip[e.spr.get_instance_id()] = true
		if e.trophy != null:
			skip[e.trophy.get_instance_id()] = true
	_props()
	_flit(dt, live)
	# Foes that are gone fall where they stood.
	for id in actors.keys():
		if live.has(id):
			continue
		var a: Dictionary = actors[id]
		actors.erase(id)
		_fall(a)
	_corpses(dt)


func _play(a: Dictionary, anim: String, speed: float = 1.0, blend: float = 0.15) -> void:
	var ap: AnimationPlayer = a["ap"]
	if ap == null or not ap.has_animation(anim):
		return
	if a["anim"] != anim:
		ap.play(anim, blend)
		a["anim"] = anim
	ap.speed_scale = speed


## A one-shot that holds the stage until it ends, unless another takes over.
func _act(a: Dictionary, anim: String, speed: float = 1.0, from: float = 0.0) -> void:
	var ap: AnimationPlayer = a["ap"]
	if ap == null or not ap.has_animation(anim):
		return
	ap.play(anim, 0.06)
	ap.speed_scale = speed
	if from > 0.0:
		ap.seek(from, true)
	a["anim"] = anim
	a["act"] = anim
	a["act_t"] = (ap.get_animation(anim).length - from) / maxf(speed, 0.01)


func _face(a: Dictionary, dir: Vector2, dt: float, rate: float = 14.0) -> void:
	if dir.length() < 0.01:
		return
	var want := atan2(dir.x, dir.y)
	a["yaw"] = lerp_angle(a["yaw"], want, 1.0 - exp(-dt * rate))
	a["model"].rotation.y = a["yaw"]


func _flash(a: Dictionary, k: float, col: Color = Color(1, 1, 1)) -> void:
	a["ov"].set_shader_parameter("col", Color(col.r, col.g, col.b, clampf(k, 0.0, 1.0) * (0.22 if view.aaa else 0.45)))


func _wren(a: Dictionary, dt: float) -> void:
	var g = game
	a["root"].position = view.to3(g.ppos)
	a["root"].visible = true
	a["act_t"] -= dt
	var n: Dictionary = wren_seen
	# Each new swing, cast, throw or blow taken starts its own animation.
	if n.get("swing", -1) != g.swing_n:
		n["swing"] = g.swing_n
		if g.swing_n > 0:
			var anim: String = ["1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Slice_Horizontal", "2H_Melee_Attack_Spin"][clampi(g.combo, 1, 3) - 1]
			_act(a, anim, 2.4 if g.combo < 3 else 2.0, 0.18)
	if n.get("cast", -1) != g.cast_n:
		n["cast"] = g.cast_n
		if g.cast_n > 0:
			_act(a, "Spellcast_Shoot", 2.2, 0.1)
	if n.get("throw", -1) != g.throw_n:
		n["throw"] = g.throw_n
		if g.throw_n > 0:
			_act(a, "Throw", 2.0, 0.15)
	if n.get("hurt", -1) != g.hurt_n:
		n["hurt"] = g.hurt_n
		if g.hurt_n > 0 and not g.dead:
			_act(a, "Hit_A", 1.8)
	var moving: bool = g.last_mv != Vector2.ZERO and g.dash_t <= 0.0
	if g.dead:
		if a["act"] != "Death_A":
			_act(a, "Death_A", 1.0)
			a["act_t"] = 999.0
	elif g.dash_t > 0.0:
		if a["act"] != "Dodge_Forward":
			_act(a, "Dodge_Forward", 2.6, 0.1)
		_face(a, g.dash_dir, dt, 30.0)
	elif a["act_t"] > 0.0:
		_face(a, g.aim, dt, 30.0)
	else:
		a["act"] = ""
		if moving:
			var spd: float = g.pvel.length()
			_play(a, "Running_A", clampf(spd / 75.0, 0.6, 1.6))
			_face(a, g.pvel if spd > 5.0 else g.aim, dt)
		else:
			_play(a, "2H_Melee_Idle")
			_face(a, g.aim, dt, 8.0)
	_flash(a, g.flash, Color(1.0, 0.5, 0.5))
	# Snuffed, the lantern on the staff goes dark too.
	var lantern: MeshInstance3D = a["model"].find_child("Lantern", true, false)
	if lantern != null:
		var lm: StandardMaterial3D = lantern.material_override
		lm.emission_energy_multiplier = 2.5 * (1.0 - 0.9 * g.snuff_k) * g.light_k


func _foe(a: Dictionary, e, dt: float) -> void:
	a["root"].position = view.to3(e.position)
	a["root"].visible = e.visible
	# Out of sight in the dark, nothing needs to move its bones.
	if a["ap"] != null:
		a["ap"].active = e.visible
	var sc: float = MODELS[e.kind]["scale"] * (1.25 if e.elite else 1.0) * (1.2 if e.nemesis else 1.0)
	a["model"].scale = Vector3.ONE * sc
	a["act_t"] -= dt
	var to_p: Vector2 = game.ppos - e.position
	var st: String = e.state
	var moving: bool = e.vel.length() > 3.0
	# Waking: the keepers stand up out of their slump.
	if e.awake and not a.get("was_awake", true):
		a["was_awake"] = true
		if e.kind == "husk" or e.kind == "gloam":
			_act(a, "Skeletons_Awaken_Standing", 2.2)
	if a.get("state", "") != st:
		a["state"] = st
		_enter(a, e, st)
	if e.stun > 0.0 and a.get("stunned", false) == false:
		a["stunned"] = true
		_act(a, "Hit_B", 1.4)
	elif e.stun <= 0.0:
		a["stunned"] = false
	if a["act_t"] <= 0.0:
		a["act"] = ""
		if not e.awake:
			if e.kind == "husk" or e.kind == "gloam":
				_play(a, "Skeleton_Inactive_Standing_Pose")
			else:
				_play(a, "Idle")
		elif st == "cast" or st == "spiral" or st == "ring_w":
			_play(a, "Spellcasting", 1.2)
		elif st == "charge":
			_play(a, "Running_B" if e.kind == "warden" else "Running_C", 1.8)
		elif moving:
			var run: bool = e.vel.length() > 50.0
			if e.kind == "warden":
				_play(a, "Running_A" if run else "Walking_A", clampf(e.vel.length() / 60.0, 0.6, 1.6))
			else:
				_play(a, "Running_C" if run else "Walking_D_Skeletons", clampf(e.vel.length() / (60.0 if run else 35.0), 0.6, 1.8))
		else:
			_play(a, "2H_Melee_Idle" if e.kind == "warden" else "Idle_Combat")
	# Heading: along a charge or lunge, otherwise toward Wren once awake.
	if st == "charge" or st == "lunge":
		_face(a, e.dir, dt, 20.0)
	elif e.awake and e.stun <= 0.0:
		_face(a, to_p, dt, 8.0)
	var fl: float = e.flash
	var tint := Color(1, 1, 1)
	if e.state == "wind" or e.state == "fuse" or e.state.ends_with("_w"):
		# The tell before a blow: a pulsing red.
		if int(e.anim * 16.0) % 2 == 0:
			fl = maxf(fl, 0.5)
			tint = Color(1.0, 0.3, 0.2)
	_flash(a, fl, tint)


## The animation for each new thing a foe starts doing.
func _enter(a: Dictionary, e, st: String) -> void:
	match st:
		"wind":
			if e.kind == "brute":
				_act(a, "Taunt", 1.6)
			else:
				var anim := "1H_Melee_Attack_Stab"
				var len: float = a["ap"].get_animation(anim).length if a["ap"] != null and a["ap"].has_animation(anim) else 1.0
				# Slowed so the blow lands as the wind-up ends.
				_act(a, anim, len * 0.35 / 0.4)
		"lunge":
			if a["act"] == "1H_Melee_Attack_Stab":
				a["ap"].speed_scale = 2.2
				a["ap"].seek(len_of(a, "1H_Melee_Attack_Stab") * 0.35, true)
				a["act_t"] = 0.35
		"cast":
			_act(a, "Spellcast_Raise", 1.2)
		"sweep_w":
			_act(a, "2H_Melee_Attack_Spin", 1.0)
		"charge_w":
			_act(a, "2H_Melee_Idle", 1.0)
		"stagger":
			_act(a, "Hit_B", 0.8)
		"rest":
			if e.kind == "cantor":
				_act(a, "Spellcast_Shoot", 1.6)


func len_of(a: Dictionary, anim: String) -> float:
	if a["ap"] == null or not a["ap"].has_animation(anim):
		return 1.0
	return a["ap"].get_animation(anim).length


func _make_proc(kind: String) -> Dictionary:
	var a: Dictionary
	match kind:
		"slime", "slimelet":
			a = CreaturesS.slime(kind == "slimelet")
		"wisp":
			a = CreaturesS.skull(view)
		"moth":
			a = CreaturesS.bat()
		_:
			return {}
	var holder := Node3D.new()
	holder.add_child(a["root"])
	add_child(holder)
	var ov := ShaderMaterial.new()
	ov.shader = overlay_shader
	var meshes: Array = []
	_meshes(a["root"], meshes)
	for m in meshes:
		m.material_overlay = ov
		m.layers = 1 | 2
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if view.shadow_on or view.aaa else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a["model"] = a["root"]
	a["root"] = holder
	a["kind"] = kind
	a["ap"] = null
	a["anim"] = ""
	a["act"] = ""
	a["act_t"] = 0.0
	a["yaw"] = 0.0
	a["ov"] = ov
	a["t"] = 0.0
	return a


## Shapes have no animations of their own: they are moved here, from what
## the flat sprite is doing (its squash, its hover, its wind-up).
func _proc(a: Dictionary, e, dt: float) -> void:
	a["t"] += dt
	var t: float = a["t"]
	var h: float = 0.0
	if e.hover > 0.0:
		h = (e.hover + (sin(e.anim * 5.0 + e.seed_f) * 1.5)) * view.K / TS
	a["root"].position = view.to3(e.position) + Vector3(0, h, 0)
	a["root"].visible = e.visible
	# The flat sprite's squash and stretch, carried over.
	var sq := Vector2.ONE
	if e.base_scale != Vector2.ZERO:
		sq = e.spr.scale / e.base_scale
	var body: Node3D = a["body"]
	match e.kind:
		"slime", "slimelet":
			var hop := 0.0
			if e.state == "hop":
				hop = sin(clampf(1.0 - e.st / 0.3, 0.0, 1.0) * PI) * 0.28
			body.position.y = hop
			body.scale = Vector3(sq.x, sq.y * (1.0 + hop * 0.6), sq.x)
		"wisp":
			body.position.y = 0.1 * sin(t * 3.0)
			body.rotation.y = sin(t * 1.3) * 0.4
			var grow: float = e.spr.scale.x if e.state == "fuse" else 1.0
			body.scale = Vector3.ONE * 0.55 * grow
			a["fire"].speed_scale = 1.8 if e.state == "fuse" else 1.0
		"moth":
			for wg in a["wings"]:
				wg[0].rotation.z = wg[1] * (0.25 + 0.75 * sin(t * 22.0 + e.seed_f))
			body.rotation.x = 0.25
	var to_p: Vector2 = game.ppos - e.position
	if e.awake:
		_face(a, e.vel if e.vel.length() > 5.0 else to_p, dt, 10.0)
	var fl: float = e.flash
	var tint := Color(1, 1, 1)
	if e.state == "fuse" and int(e.anim * 16.0) % 2 == 0:
		fl = maxf(fl, 0.6)
		tint = Color(1.0, 0.5, 0.2)
	_flash(a, fl, tint)


## Flit flies about Wren's lantern as a pale moth with beating wings.
func _flit(dt: float, live: Dictionary) -> void:
	var m = game.moth
	if m == null or not is_instance_valid(m):
		return
	live[-1] = true
	var a: Dictionary = actors.get(-1, {})
	if a.is_empty():
		var c := CreaturesS.moth()
		var holder := Node3D.new()
		holder.add_child(c["root"])
		add_child(holder)
		a = c
		a["model"] = c["root"]
		a["root"] = holder
		a["kind"] = "flit"
		a["t"] = 0.0
		# Its own small light (the flat one is skipped along with its picture).
		var l := OmniLight3D.new()
		l.light_color = Color(0.8, 0.88, 1.0)
		l.light_energy = 0.9
		l.omni_range = 1.8
		c["root"].add_child(l)
		a["yaw"] = 0.0
		actors[-1] = a
	a["t"] += dt
	skip[m.body.get_instance_id()] = true
	var ground: Vector2 = m.position + Vector2(0, view.LIFT)
	var height: float = (-m.body.position.y + view.LIFT) * view.K / TS
	a["root"].position = view.to3(ground) + Vector3(0, height, 0)
	a["root"].visible = m.visible
	for wg in a["wings"]:
		wg[0].rotation.z = wg[1] * (0.2 + 0.9 * absf(sin(a["t"] * 16.0)))
	var prev: Vector3 = a.get("prev", a["root"].position)
	var mv: Vector3 = a["root"].position - prev
	a["prev"] = a["root"].position
	_face(a, Vector2(mv.x, mv.z), dt, 12.0)


## A foe put out keeps its body a moment: it falls, then sinks away.
func _fall(a: Dictionary) -> void:
	if a.get("ap") == null:
		# Shapes have no death to play: they simply go.
		a["root"].queue_free()
		return
	if not a["root"].visible:
		a["root"].queue_free()
		return
	_flash(a, 0.0)
	var anim := "Death_A" if a["kind"] == "warden" else "Death_C_Skeletons"
	_act(a, anim, 1.4)
	a["t"] = 0.0
	corpses.append(a)


func _corpses(dt: float) -> void:
	var i := corpses.size() - 1
	while i >= 0:
		var a: Dictionary = corpses[i]
		a["t"] += dt
		var t: float = a["t"]
		if t > 1.1:
			a["root"].position.y -= dt * 0.6
		if t > 2.2:
			a["root"].queue_free()
			corpses.remove_at(i)
		i -= 1


## Chests, braziers, urns and wayside lamps as kit models. Pages, plaques,
## relics and the cage stay as their glowing pictures.
func _props() -> void:
	var live := {}
	for p in game.props:
		var node = p["node"]
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var type: String = p["type"]
		if type == "stairs" and view.kit_on:
			# The seal on the stair: a red light down the stairwell, not a painted glow.
			for c in node.get_children():
				if c is Sprite2D:
					skip[c.get_instance_id()] = true
			if seal == null:
				seal = OmniLight3D.new()
				seal.light_color = Color(1.0, 0.15, 0.08)
				seal.omni_range = 2.6
				add_child(seal)
			seal.position = view.to3(p["pos"]) + Vector3(0, -0.2, 0.3)
			seal.visible = game.sealed
			seal.light_energy = 2.2 + 0.6 * sin(game.anim_t * 4.0)
			continue
		if not ["chest", "brazier", "urn", "lamp"].has(type):
			continue
		var id: int = node.get_instance_id()
		live[id] = true
		var m: Dictionary = props.get(id, {})
		if m.is_empty():
			m = _make_prop(p)
			if m.is_empty():
				continue
			props[id] = m
		# The model stands in for the picture and its painted glows alike.
		for c in node.get_children():
			if c is Sprite2D:
				skip[c.get_instance_id()] = true
		var root: Node3D = m["root"]
		root.visible = node.visible and game.seen[int(p["pos"].y / 16.0) * game.W + int(p["pos"].x / 16.0)] == 1
		match type:
			"chest":
				var lid: Node3D = m.get("lid")
				if lid != null:
					var want: float = -1.9 if p["done"] else 0.0
					lid.rotation.x = lerpf(lid.rotation.x, want, 0.15)
			"lamp":
				var lit: bool = p["done"]
				m["glass"].material_override.emission_energy_multiplier = 3.0 if lit else 0.15
				m["fire"].emitting = lit and root.visible
			"brazier":
				m["fire"].emitting = root.visible
	for id in props.keys():
		if not live.has(id):
			props[id]["root"].queue_free()
			props.erase(id)


func _make_prop(p: Dictionary) -> Dictionary:
	var type: String = p["type"]
	var root := Node3D.new()
	root.position = view.to3(p["pos"])
	root.rotation.y = float((int(p["idx"]) * 37) % 8) * PI * 0.25 if type != "chest" else 0.0
	add_child(root)
	var m := {"root": root}
	match type:
		"chest":
			var ps := scene("kit/chest_gold" if p.get("secret", false) else "kit/chest")
			if ps == null:
				root.queue_free()
				return {}
			var c: Node3D = ps.instantiate()
			c.scale = Vector3.ONE * 0.42
			root.add_child(c)
			m["lid"] = c.find_child("chest_lid", true, false)
		"brazier":
			_kit_mesh(root, "torch_lit", 0.95)
			var f = view.flame(0.9)
			f.position = Vector3(0, 0.62, 0)
			root.add_child(f)
			m["fire"] = f
		"urn":
			_kit_mesh(root, "barrel_small", 0.46)
		"lamp":
			# A wayside lamp: a short stone post with a lantern on top.
			var post := _kit_mesh(root, "column", 0.5)
			if post != null:
				post.scale = Vector3(0.45, 0.62, 0.45)
			var glass := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.2, 0.26, 0.2)
			glass.mesh = bm
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(0.2, 0.15, 0.08)
			gm.emission_enabled = true
			gm.emission = Color(1.0, 0.75, 0.4)
			glass.material_override = gm
			glass.position = Vector3(0, 1.0, 0)
			root.add_child(glass)
			m["glass"] = glass
			var f = view.flame(0.45)
			f.position = Vector3(0, 1.02, 0)
			root.add_child(f)
			m["fire"] = f
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if view.shadow_on or view.aaa else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


func _kit_mesh(parent: Node3D, piece: String, sc: float) -> MeshInstance3D:
	var DungeonS = view.DungeonS
	if not DungeonS.meshes.has(piece):
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = DungeonS.meshes[piece]
	mi.scale = Vector3.ONE * sc
	mi.material_override = view.kit.mat_floor
	parent.add_child(mi)
	return mi


func clear() -> void:
	for id in actors:
		actors[id]["root"].queue_free()
	actors.clear()
	for a in corpses:
		a["root"].queue_free()
	corpses.clear()
	wren_seen.clear()
	for id in props:
		props[id]["root"].queue_free()
	props.clear()
