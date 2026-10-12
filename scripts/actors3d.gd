extends Node3D
## Real 3D figures for the 3D view: Wren and the foes that have a model are
## drawn as rigged, animated low-poly characters (KayKit, CC0) instead of
## standing cut-outs. Like the rest of the 3D view this only watches the game:
## where each one stands, which way it faces and what it is doing are all read
## from the flat game, and turned into a position, a heading and an animation.
## Foes without a model (bats, ink, cinder skulls) stay as sprites.

const TS := 16.0

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
		if not MODELS.has(e.kind) or not is_instance_valid(e):
			continue
		var id: int = e.get_instance_id()
		if e.dead:
			continue
		var a: Dictionary = actors.get(id, {})
		if a.is_empty():
			a = _make(e.kind)
			if a.is_empty():
				continue
			actors[id] = a
			a["was_awake"] = e.awake
		live[id] = true
		_foe(a, e, dt)
		skip[e.spr.get_instance_id()] = true
		if e.trophy != null:
			skip[e.trophy.get_instance_id()] = true
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
	a["ov"].set_shader_parameter("col", Color(col.r, col.g, col.b, clampf(k, 0.0, 1.0) * 0.45))


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


## A foe put out keeps its body a moment: it falls, then sinks away.
func _fall(a: Dictionary) -> void:
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


func clear() -> void:
	for id in actors:
		actors[id]["root"].queue_free()
	actors.clear()
	for a in corpses:
		a["root"].queue_free()
	corpses.clear()
	wren_seen.clear()
