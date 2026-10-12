extends RefCounted
## The creatures the model packs have nothing for, built from simple shapes:
## an ink maw (a glossy blob that squashes as it hops), a cinder skull (a
## skull borrowed from the skeleton model, wreathed in fire), a gloam bat
## with wings that beat, and Flit, the pale lamp moth.
## Each builder returns {"root": Node3D, ...parts to animate}.

const ActorsS = preload("res://scripts/actors3d.gd")

static var mats := {}


static func _mat(id: String) -> Material:
	if mats.has(id):
		return mats[id]
	var m := StandardMaterial3D.new()
	match id:
		"ink":
			m.albedo_color = Color(0.03, 0.05, 0.16)
			m.roughness = 0.12
			m.metallic_specular = 0.9
			m.rim_enabled = true
			m.rim = 0.7
			m.rim_tint = 0.2
			m.emission_enabled = true
			m.emission = Color(0.05, 0.12, 0.4)
			m.emission_energy_multiplier = 0.4
		"eye_white":
			m.albedo_color = Color(0.95, 0.95, 1.0)
			m.roughness = 0.2
		"pupil":
			m.albedo_color = Color(0.01, 0.01, 0.02)
			m.roughness = 0.1
		"bat":
			m.albedo_color = Color(0.13, 0.08, 0.2)
			m.roughness = 0.7
		"wing":
			m.albedo_color = Color(0.22, 0.12, 0.3)
			m.roughness = 0.8
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"glow_red":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.6, 0.25, 0.2)
		"glow_ember":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(2.0, 0.9, 0.3)
		"char":
			m.albedo_color = Color(0.22, 0.17, 0.14)
			m.roughness = 0.9
			m.emission_enabled = true
			m.emission = Color(1.0, 0.35, 0.08)
			m.emission_energy_multiplier = 0.35
		"moth":
			m.albedo_color = Color(0.92, 0.95, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.75, 0.85, 1.0)
			m.emission_energy_multiplier = 1.4
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats[id] = m
	return m


static func _sphere(r: float, h: float, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = h
	sm.radial_segments = 20
	sm.rings = 10
	mi.mesh = sm
	mi.material_override = _mat(mat)
	return mi


static func _eyes(parent: Node3D, y: float, z: float, gap: float, r: float, glow: String = "") -> void:
	for sx in [-1.0, 1.0]:
		if glow != "":
			var g := _sphere(r, r * 2.0, glow)
			g.position = Vector3(sx * gap, y, z)
			parent.add_child(g)
			continue
		var w := _sphere(r, r * 2.0, "eye_white")
		w.position = Vector3(sx * gap, y, z)
		parent.add_child(w)
		var p := _sphere(r * 0.5, r, "pupil")
		p.position = Vector3(sx * gap, y, z + r * 0.75)
		parent.add_child(p)


## An ink maw: a dome of glossy ink with two goggling eyes.
static func slime(small: bool) -> Dictionary:
	var root := Node3D.new()
	var body := Node3D.new()
	root.add_child(body)
	var blob := _sphere(0.34, 0.5, "ink")
	blob.position = Vector3(0, 0.2, 0)
	body.add_child(blob)
	var drip := _sphere(0.42, 0.14, "ink")
	drip.position = Vector3(0, 0.03, 0)
	body.add_child(drip)
	_eyes(body, 0.3, 0.24, 0.11, 0.07)
	if small:
		root.scale = Vector3.ONE * 0.6
	return {"root": root, "body": body}


## A cinder skull: the keeper's skull, charred and burning.
static func skull(view) -> Dictionary:
	var root := Node3D.new()
	var body := Node3D.new()
	root.add_child(body)
	var ps: PackedScene = ActorsS.scene("skeleton_minion")
	if ps != null:
		var tmp: Node3D = ps.instantiate()
		for part in ["Skeleton_Minion_Head", "Skeleton_Minion_Jaw", "Skeleton_Minion_Eyes"]:
			var src: MeshInstance3D = tmp.find_child(part, true, false)
			if src != null:
				var mi := MeshInstance3D.new()
				mi.mesh = src.mesh
				mi.material_override = _mat("glow_ember" if part.ends_with("Eyes") else "char")
				# The head sits about 1.3 to 2.2 up the body; bring it down to here.
				mi.position = Vector3(0, -1.55, 0)
				body.add_child(mi)
		tmp.free()
	body.scale = Vector3.ONE * 0.55
	var fire = view.flame(1.1)
	fire.amount = 26
	fire.position = Vector3(0, 0.1, 0)
	root.add_child(fire)
	return {"root": root, "body": body, "fire": fire}


## A gloam bat: a furred body, pricked ears, red eyes, and wings that beat.
static func bat() -> Dictionary:
	var root := Node3D.new()
	var body := Node3D.new()
	root.add_child(body)
	var torso := _sphere(0.13, 0.3, "bat")
	body.add_child(torso)
	var head := _sphere(0.1, 0.19, "bat")
	head.position = Vector3(0, 0.13, 0.06)
	body.add_child(head)
	for sx in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.07, 0.12, 0.03)
		ear.mesh = pm
		ear.material_override = _mat("bat")
		ear.position = Vector3(sx * 0.055, 0.24, 0.05)
		body.add_child(ear)
	_eyes(head, 0.02, 0.085, 0.04, 0.022, "glow_red")
	var wings: Array = []
	for sx in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(sx * 0.1, 0.05, 0)
		body.add_child(pivot)
		var w := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.42, 0.24, 0.02)
		pm.left_to_right = 0.0 if sx > 0 else 1.0
		w.mesh = pm
		w.material_override = _mat("wing")
		w.position = Vector3(sx * 0.21, -0.02, 0)
		w.rotation.x = -PI * 0.5
		pivot.add_child(w)
		wings.append([pivot, sx])
	return {"root": root, "body": body, "wings": wings}


## Flit: a small pale moth, glowing faintly.
static func moth() -> Dictionary:
	var root := Node3D.new()
	var body := Node3D.new()
	root.add_child(body)
	var torso := _sphere(0.035, 0.12, "moth")
	torso.rotation.x = PI * 0.5
	body.add_child(torso)
	var wings: Array = []
	for sx in [-1.0, 1.0]:
		var pivot := Node3D.new()
		body.add_child(pivot)
		var w := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.14, 0.12)
		w.mesh = q
		w.material_override = _mat("moth")
		w.position = Vector3(sx * 0.075, 0, 0)
		w.rotation.x = -PI * 0.5
		pivot.add_child(w)
		wings.append([pivot, sx])
	return {"root": root, "body": body, "wings": wings}
