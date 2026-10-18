extends Node
## Sound and music. Recorded effects and music tracks (CC0, three tracks CC-BY; see CREDITS.txt)
## are loaded from res://audio; anything without a file falls back to a sound
## synthesised here at startup.

const RATE := 22050
const MRATE := 11025

var sounds := {}
var pool: Array = []
var pool_i := 0
var mus: Array = []
var mus_i := 0
var tracks := {}
var want := ""
var playing := ""
var muted := false
var thread: Thread
var sfx_thread: Thread
var abort := false
var rng := RandomNumberGenerator.new()
var mrng := RandomNumberGenerator.new()
var file_sounds := {}
var music_db := -5.0

## Playback level for each recorded effect, in dB, on top of what the caller asks for.
const FILE_VOL := {"step": -15.0, "type": -12.0, "cinder": -10.0, "hit": -4.0, "punch": -2.0, "kill": -7.0,
	"slash": -6.0, "slash3": -3.0, "dash": -4.0, "bolt": -6.0, "shoot": -8.0, "pop": -8.0, "coins": -6.0,
	"page": -4.0, "chest": -3.0, "urn": -6.0, "stairs": -3.0, "lock": -4.0, "ui": -10.0, "ui_ok": -8.0,
	"boom": -1.0, "roar": -2.0, "bell": -5.0, "gong": -3.0, "thud": -3.0, "growl": -9.0, "slime": -10.0,
	"thunder": -3.0, "fire": -5.0, "clank": -6.0, "relic": -3.0,
	# The combat set (see CREDITS.txt), levelled against each other by build.
	"hit_heavy": -4.0, "crit": -3.0, "hit_bolt": -5.0, "burn": -8.0, "ember_hit": -10.0, "ward_hit": -8.0,
	"shatter": -5.0, "hurt_voice": -3.0, "death_voice": -2.0, "death": -2.0, "parry": -4.0, "deflect": -6.0,
	"husk_lunge": -4.0, "moth_bite": -5.0, "brute_roar": -3.0, "chant": -6.0, "wisp_fuse": -5.0}
## Synthesised stand-ins used when a music file is missing.
const MUSIC_FALLBACK := {"title": "vesper", "depth1": "vesper", "depth2": "vesper", "depth3": "deep",
	"depth4": "deep", "depth5": "deep", "depth6": "deep", "forge": "deep", "boss": "warden", "keep": "vesper", "dawn": "dawn"}


## A cue with no sound of its own borrows another's, so the game can name the
## sound it means (a burn, a bolt striking home) whether or not it has a file.
const ALIAS := {"hit_heavy": "hit", "crit": "hit_heavy", "hit_bolt": "hit", "burn": "cinder",
	"zap_hit": "zap", "ward_hit": "ember", "ember_hit": "ember", "shatter": "clank",
	"husk_lunge": "growl", "moth_bite": "lunge", "brute_roar": "roar", "wisp_fuse": "telegraph",
	"chant": "", "hurt_voice": "", "parry": "clank", "deflect": "clank", "swing": "slash",
	"swing_heavy": "slash3", "bolt_cast": "bolt"}
## When every voice is busy, a cue may take the place of one that matters less.
const PRIO := {"death": 5, "levelup": 5, "kill": 4, "boom": 4, "roar": 4, "sting": 4, "punch": 4,
	"telegraph": 4, "brute_roar": 4, "wisp_fuse": 4, "hurt_voice": 4, "husk_lunge": 3, "moth_bite": 3,
	"crit": 3, "hit_heavy": 3, "slash3": 3, "clank": 3, "parry": 3, "heart": 3, "shatter": 3,
	"step": 0, "type": 0, "burn": 1, "ember_hit": 1, "ward_hit": 1, "zap_hit": 1, "cinder": 1,
	"coins": 1, "pop": 1}
## The shortest time in seconds between two starts of one cue. A blow that lands
## on thirty foes at once is heard as one hit, not as thirty in a smear.
const GAP := {"hit": 0.06, "hit_heavy": 0.06, "crit": 0.06, "hit_bolt": 0.06, "burn": 0.15,
	"ember_hit": 0.1, "ward_hit": 0.12, "zap_hit": 0.08, "shatter": 0.08, "kill": 0.05, "step": 0.08,
	"cinder": 0.05, "coins": 0.05, "slime": 0.15, "growl": 0.2, "husk_lunge": 0.15, "moth_bite": 0.15}
const GAP_DEFAULT := 0.03
## At most this many of one cue sound at once; past that the oldest is cut.
const MAX_SAME := {"step": 2, "burn": 2, "ember_hit": 2, "ward_hit": 2, "zap_hit": 2, "type": 2}
const MAX_SAME_DEFAULT := 3
const VOICES := 28

var voice_id: Array[String] = []
var voice_prio := PackedInt32Array()
var voice_t := PackedFloat64Array()
var last_start := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.seed = 7
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
		voice_id.append("")
	voice_prio.resize(VOICES)
	voice_t.resize(VOICES)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.volume_db = -60.0
		add_child(m)
		mus.append(m)
	_load_files()
	# The synthesised cues take a moment to compute, so they are built on a
	# worker thread and swapped in when ready; recorded sounds work at once.
	sfx_thread = Thread.new()
	sfx_thread.start(_build_sfx)
	# Synthesised music takes a few seconds to render, so it happens off the main
	# thread, and only when a recorded track is missing.
	var missing := false
	for id in MUSIC_FALLBACK:
		if not tracks.has(id):
			missing = true
	if missing:
		thread = Thread.new()
		thread.start(_build_music)


func _load_files() -> void:
	var d := DirAccess.open("res://audio/sfx")
	if d != null:
		for f in d.get_files():
			if not f.ends_with(".ogg"):
				continue
			var id: String = f.get_basename().rsplit("_", true, 1)[0]
			var s = AudioStreamOggVorbis.load_from_file("res://audio/sfx/" + f)
			if s == null:
				continue
			if not file_sounds.has(id):
				file_sounds[id] = []
			file_sounds[id].append(s)
	d = DirAccess.open("res://audio/music")
	if d != null:
		for f in d.get_files():
			if not f.ends_with(".ogg"):
				continue
			var s = AudioStreamOggVorbis.load_from_file("res://audio/music/" + f)
			if s != null:
				s.loop = true
				tracks[f.get_basename()] = s


func _exit_tree() -> void:
	abort = true
	if thread != null and thread.is_started():
		thread.wait_to_finish()
	if sfx_thread != null and sfx_thread.is_started():
		sfx_thread.wait_to_finish()


## The cue that will actually sound for id: itself, or what it borrows from.
func resolve(id: String) -> String:
	for i in 4:
		if file_sounds.has(id) or sounds.has(id):
			return id
		id = ALIAS.get(id, "")
		if id == "":
			return ""
	return ""


func play(id: String, vol_db: float = 0.0, pitch_var: float = 0.07) -> void:
	if muted:
		return
	var asked := id
	id = resolve(id)
	if id == "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(last_start.get(id, -10.0)) < GAP.get(id, GAP_DEFAULT):
		return
	var prio: int = PRIO.get(asked, PRIO.get(id, 2))
	# A free voice if there is one; else the least needed (the oldest if tied),
	# as long as it matters no more than this cue does.
	var free := -1
	var same := 0
	var oldest_same := -1
	var victim := -1
	for i in pool.size():
		if not (pool[i] as AudioStreamPlayer).playing:
			if free < 0:
				free = i
			continue
		if voice_id[i] == id:
			same += 1
			if oldest_same < 0 or voice_t[i] < voice_t[oldest_same]:
				oldest_same = i
		if victim < 0 or voice_prio[i] < voice_prio[victim] \
				or (voice_prio[i] == voice_prio[victim] and voice_t[i] < voice_t[victim]):
			victim = i
	var v := free
	if same >= MAX_SAME.get(id, MAX_SAME_DEFAULT):
		v = oldest_same
	elif v < 0:
		if victim < 0 or voice_prio[victim] > prio:
			return
		v = victim
	var stream
	if file_sounds.has(id):
		var variants: Array = file_sounds[id]
		stream = variants[randi() % variants.size()]
		vol_db += FILE_VOL.get(id, -5.0)
	else:
		stream = sounds[id]
	last_start[id] = now
	voice_id[v] = id
	voice_prio[v] = prio
	voice_t[v] = now
	var p: AudioStreamPlayer = pool[v]
	p.stream = stream
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func play_music(id: String) -> void:
	if not tracks.has(id) and MUSIC_FALLBACK.has(id):
		id = MUSIC_FALLBACK[id]
	want = id


func _track_ready(id: String, stream: AudioStream) -> void:
	tracks[id] = stream


func _process(dt: float) -> void:
	if want != playing and (want == "" or tracks.has(want)):
		playing = want
		mus_i = 1 - mus_i
		if want != "":
			var np: AudioStreamPlayer = mus[mus_i]
			np.stream = tracks[want]
			np.volume_db = -45.0
			np.play()
	var target := -80.0 if muted else music_db
	for i in 2:
		var m: AudioStreamPlayer = mus[i]
		if i == mus_i and playing != "":
			m.volume_db = move_toward(m.volume_db, target, dt * 28.0)
		else:
			m.volume_db = move_toward(m.volume_db, -60.0, dt * 28.0)
			if m.volume_db <= -59.0 and m.playing:
				m.stop()


# --- Sound effects --------------------------------------------------------------

## One synth voice. Keys: dur, f0, f1 (pitch sweep), wave, vol, atk, curve (decay
## shape), lp / lp1 (low-pass sweep; 1 = open), vib, vibf.
func _g(p: Dictionary) -> PackedFloat32Array:
	var dur: float = p.get("dur", 0.2)
	var f0: float = p.get("f0", 440.0)
	var f1: float = p.get("f1", f0)
	var wave: String = p.get("wave", "sin")
	var vol: float = p.get("vol", 0.5)
	var atk: float = p.get("atk", 0.004)
	var curve: float = p.get("curve", 2.0)
	var lp0: float = p.get("lp", 1.0)
	var lp1: float = p.get("lp1", lp0)
	var vib: float = p.get("vib", 0.0)
	var vibf: float = p.get("vibf", 9.0)
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var last := 0.0
	var ratio := f1 / f0
	for i in n:
		var t := float(i) / n
		var f := f0 * pow(ratio, t)
		if vib > 0.0:
			f *= 1.0 + vib * sin(TAU * vibf * i / RATE)
		phase = fmod(phase + f / RATE, 1.0)
		var s := 0.0
		match wave:
			"sin":
				s = sin(TAU * phase)
			"sq":
				s = 1.0 if phase < 0.5 else -1.0
			"saw":
				s = 2.0 * phase - 1.0
			"tri":
				s = 4.0 * absf(phase - 0.5) - 1.0
			"noise":
				s = rng.randf_range(-1.0, 1.0)
		var env := minf(1.0, (float(i) / RATE) / atk) * pow(1.0 - t, curve)
		last += (s * env * vol - last) * lerpf(lp0, lp1, t)
		out[i] = last
	return out


## Layers voices: each entry is [buffer, start_time_in_seconds].
func _mix(layers: Array) -> PackedFloat32Array:
	var n := 0
	for l in layers:
		var b: PackedFloat32Array = l[0]
		var off: float = l[1]
		n = maxi(n, b.size() + int(off * RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	for l in layers:
		var b: PackedFloat32Array = l[0]
		var off: float = l[1]
		var o := int(off * RATE)
		for i in b.size():
			out[o + i] += b[i]
	return out


func _wav(buf: PackedFloat32Array, rate: int = RATE, loop: bool = false) -> AudioStreamWAV:
	var n := buf.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v := buf[i]
		if loop:
			v = tanh(v * 1.2)
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = n
	return s


func _arp(notes: Array, wave: String, each: float, gap: float, vol: float) -> PackedFloat32Array:
	var layers: Array = []
	for i in notes.size():
		layers.append([_g({"dur": each, "f0": notes[i], "wave": wave, "vol": vol, "curve": 2.5}), i * gap])
	return _mix(layers)


func _build_sfx() -> void:
	var s := {}
	s["slash"] = _wav(_g({"dur": 0.14, "wave": "noise", "vol": 0.6, "atk": 0.015, "curve": 1.3, "lp": 0.1, "lp1": 0.8}))
	s["slash3"] = _wav(_mix([
		[_g({"dur": 0.26, "wave": "noise", "vol": 0.75, "atk": 0.03, "curve": 1.2, "lp": 0.06, "lp1": 0.7}), 0.0],
		[_g({"dur": 0.22, "f0": 260.0, "f1": 70.0, "wave": "saw", "vol": 0.22, "lp": 0.25}), 0.0]]))
	s["hit"] = _wav(_mix([
		[_g({"dur": 0.09, "f0": 190.0, "f1": 60.0, "wave": "sq", "vol": 0.4, "lp": 0.4}), 0.0],
		[_g({"dur": 0.06, "wave": "noise", "vol": 0.45, "lp": 0.6}), 0.0]]))
	s["kill"] = _wav(_mix([
		[_g({"dur": 0.26, "f0": 420.0, "f1": 70.0, "wave": "saw", "vol": 0.32, "lp": 0.35}), 0.0],
		[_g({"dur": 0.18, "wave": "noise", "vol": 0.4, "lp": 0.3}), 0.0]]))
	s["hurt"] = _wav(_mix([
		[_g({"dur": 0.3, "f0": 240.0, "f1": 90.0, "wave": "sq", "vol": 0.42, "vib": 0.08, "lp": 0.35}), 0.0],
		[_g({"dur": 0.12, "wave": "noise", "vol": 0.45, "lp": 0.25}), 0.0]]))
	s["dash"] = _wav(_g({"dur": 0.2, "wave": "noise", "vol": 0.6, "atk": 0.03, "curve": 1.5, "lp": 0.05, "lp1": 0.5}))
	s["bolt"] = _wav(_mix([
		[_g({"dur": 0.2, "f0": 760.0, "f1": 240.0, "wave": "saw", "vol": 0.26, "lp": 0.45}), 0.0],
		[_g({"dur": 0.1, "wave": "noise", "vol": 0.22, "lp": 0.7}), 0.0]]))
	s["pop"] = _wav(_mix([
		[_g({"dur": 0.1, "wave": "noise", "vol": 0.3, "lp": 0.5}), 0.0],
		[_g({"dur": 0.1, "f0": 300.0, "f1": 120.0, "vol": 0.25}), 0.0]]))
	s["cinder"] = _wav(_g({"dur": 0.07, "f0": 1300.0, "f1": 1900.0, "vol": 0.2, "curve": 1.5}))
	s["heart"] = _wav(_arp([660.0, 990.0], "sin", 0.2, 0.09, 0.3))
	s["oil"] = _wav(_arp([420.0, 630.0, 840.0], "tri", 0.14, 0.06, 0.26))
	s["chest"] = _wav(_arp([523.0, 659.0, 784.0, 1047.0], "tri", 0.2, 0.07, 0.24))
	s["page"] = _wav(_mix([
		[_g({"dur": 0.9, "f0": 880.0, "vol": 0.22, "curve": 3.0}), 0.0],
		[_g({"dur": 0.9, "f0": 1320.0, "vol": 0.14, "curve": 3.0}), 0.05],
		[_g({"dur": 0.7, "f0": 1760.0, "vol": 0.08, "curve": 3.0}), 0.1]]))
	s["levelup"] = _wav(_arp([523.0, 659.0, 784.0, 1047.0, 1319.0], "sin", 0.4, 0.08, 0.24))
	s["lamp"] = _wav(_mix([
		[_g({"dur": 0.55, "wave": "noise", "vol": 0.5, "atk": 0.08, "curve": 1.5, "lp": 0.03, "lp1": 0.3}), 0.0],
		[_g({"dur": 0.45, "f0": 140.0, "f1": 320.0, "vol": 0.3, "atk": 0.05}), 0.0]]))
	s["urn"] = _wav(_mix([
		[_g({"dur": 0.13, "wave": "noise", "vol": 0.5, "lp": 0.9, "curve": 2.5}), 0.0],
		[_g({"dur": 0.1, "f0": 900.0, "f1": 260.0, "wave": "tri", "vol": 0.2}), 0.0]]))
	s["stairs"] = _wav(_mix([
		[_g({"dur": 0.7, "f0": 110.0, "f1": 50.0, "vol": 0.55, "curve": 1.5}), 0.0],
		[_g({"dur": 0.5, "wave": "noise", "vol": 0.22, "lp": 0.08}), 0.0]]))
	s["unseal"] = _wav(_mix([
		[_g({"dur": 0.5, "f0": 330.0, "f1": 660.0, "vol": 0.25, "atk": 0.1}), 0.0],
		[_g({"dur": 0.5, "f0": 495.0, "f1": 990.0, "vol": 0.15, "atk": 0.1}), 0.1]]))
	s["ui"] = _wav(_g({"dur": 0.04, "f0": 700.0, "vol": 0.2}))
	s["ui_ok"] = _wav(_arp([880.0, 1320.0], "sin", 0.1, 0.05, 0.22))
	s["type"] = _wav(_g({"dur": 0.018, "f0": 520.0, "wave": "sq", "vol": 0.14, "lp": 0.3}))
	s["shoot"] = _wav(_g({"dur": 0.16, "f0": 320.0, "f1": 520.0, "wave": "sq", "vol": 0.22, "vib": 0.1, "lp": 0.35}))
	s["telegraph"] = _wav(_g({"dur": 0.3, "f0": 480.0, "f1": 900.0, "wave": "tri", "vol": 0.22, "atk": 0.1, "curve": 1.0}))
	s["boom"] = _wav(_mix([
		[_g({"dur": 0.55, "wave": "noise", "vol": 0.85, "lp": 0.4, "lp1": 0.03, "curve": 1.6}), 0.0],
		[_g({"dur": 0.5, "f0": 95.0, "f1": 38.0, "vol": 0.6}), 0.0]]))
	s["roar"] = _wav(_mix([
		[_g({"dur": 1.1, "f0": 85.0, "f1": 48.0, "wave": "saw", "vol": 0.5, "vib": 0.12, "vibf": 11.0, "lp": 0.2, "atk": 0.08, "curve": 1.0}), 0.0],
		[_g({"dur": 1.0, "wave": "noise", "vol": 0.35, "lp": 0.06, "atk": 0.1}), 0.0]]))
	s["bell"] = _wav(_mix([
		[_g({"dur": 1.2, "f0": 220.0, "vol": 0.3, "curve": 3.0}), 0.0],
		[_g({"dur": 1.0, "f0": 554.0, "vol": 0.18, "curve": 3.0}), 0.0],
		[_g({"dur": 0.7, "f0": 831.0, "vol": 0.1, "curve": 3.0}), 0.0],
		[_g({"dur": 0.4, "f0": 1108.0, "vol": 0.06, "curve": 3.0}), 0.0]]))
	s["thud"] = _wav(_mix([
		[_g({"dur": 0.25, "f0": 120.0, "f1": 45.0, "vol": 0.65}), 0.0],
		[_g({"dur": 0.12, "wave": "noise", "vol": 0.4, "lp": 0.15}), 0.0]]))
	s["death"] = _wav(_mix([
		[_g({"dur": 1.3, "f0": 330.0, "f1": 55.0, "wave": "saw", "vol": 0.35, "lp": 0.2, "curve": 1.2, "vib": 0.05}), 0.0],
		[_g({"dur": 1.3, "f0": 165.0, "f1": 40.0, "vol": 0.3, "curve": 1.2}), 0.0]]))
	s["step"] = _wav(_g({"dur": 0.045, "wave": "noise", "vol": 0.3, "lp": 0.12}))
	s["lunge"] = _wav(_mix([
		[_g({"dur": 0.12, "wave": "noise", "vol": 0.4, "lp": 0.1, "lp1": 0.5}), 0.0],
		[_g({"dur": 0.1, "f0": 150.0, "f1": 260.0, "wave": "sq", "vol": 0.12, "lp": 0.3}), 0.0]]))
	# Synth-only cues that are layered over recorded effects.
	s["jingle"] = _wav(_arp([523.0, 659.0, 784.0, 1047.0], "tri", 0.2, 0.07, 0.2))
	s["chime"] = s["unseal"]
	s["whoomp"] = s["lamp"]
	s["sting"] = s["hurt"]
	s["zap"] = _wav(_mix([
		[_g({"dur": 0.22, "f0": 1800.0, "f1": 200.0, "wave": "saw", "vol": 0.3, "vib": 0.3, "vibf": 60.0, "lp": 0.6}), 0.0],
		[_g({"dur": 0.18, "wave": "noise", "vol": 0.35, "lp": 0.9, "curve": 1.5}), 0.0]]))
	s["ward"] = _wav(_mix([
		[_g({"dur": 1.4, "f0": 196.0, "vol": 0.22, "atk": 0.15, "curve": 2.0}), 0.0],
		[_g({"dur": 1.4, "f0": 294.0, "vol": 0.16, "atk": 0.15, "curve": 2.0}), 0.06],
		[_g({"dur": 1.2, "f0": 392.0, "vol": 0.12, "atk": 0.15, "curve": 2.0}), 0.12]]))
	s["power"] = _wav(_arp([392.0, 523.0, 659.0, 784.0, 1047.0, 1319.0, 1568.0], "sin", 0.5, 0.07, 0.2))
	s["ember"] = _wav(_mix([
		[_g({"dur": 2.2, "f0": 440.0, "vol": 0.16, "atk": 0.3, "curve": 2.0}), 0.0],
		[_g({"dur": 2.0, "f0": 554.0, "vol": 0.14, "atk": 0.3, "curve": 2.0}), 0.15],
		[_g({"dur": 1.8, "f0": 659.0, "vol": 0.12, "atk": 0.3, "curve": 2.0}), 0.3],
		[_g({"dur": 1.6, "f0": 880.0, "vol": 0.1, "atk": 0.3, "curve": 2.0}), 0.45]]))
	call_deferred("_synth_ready", s)


func _synth_ready(built: Dictionary) -> void:
	sounds = built


# --- Music ----------------------------------------------------------------------

func _build_music() -> void:
	mrng.seed = 11
	_publish("vesper", _compose_vesper())
	_publish("deep", _compose_deep())
	_publish("warden", _compose_warden())
	_publish("dawn", _compose_dawn())


func _publish(id: String, buf: PackedFloat32Array) -> void:
	if abort:
		return
	call_deferred("_track_ready", id, _wav(buf, MRATE, true))


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * MRATE))
	return b


## Renders one note into a looping buffer; anything past the end wraps to the
## start, so a track's tail blends into its own beginning.
## kind: 0 pad, 1 chime, 2 bass, 3 kick, 4 noise hit.
func _note(buf: PackedFloat32Array, t0: float, dur: float, midi: float, vol: float, kind: int, atk: float = 0.01, rel: float = 0.1) -> void:
	if abort:
		return
	var n := buf.size()
	var f := 440.0 * pow(2.0, (midi - 69.0) / 12.0)
	var w := TAU * f / MRATE
	var s0 := int(t0 * MRATE)
	var an := maxi(1, int(atk * MRATE))
	var dn := maxi(1, int(dur * MRATE))
	var rn := maxi(1, int(rel * MRATE))
	var total := dn + rn
	match kind:
		0:
			for i in total:
				var env := 1.0
				if i < an:
					env = float(i) / an
				elif i >= dn:
					env = 1.0 - float(i - dn) / rn
				var s := sin(w * i) + 0.5 * sin(w * 1.004 * i + 1.3) + 0.2 * sin(w * 2.0 * i)
				buf[(s0 + i) % n] += s * env * vol
		1:
			var decay := dn * 0.3 + 1.0
			for i in total:
				var env := exp(-float(i) / decay) * minf(1.0, i / 24.0)
				var s := sin(w * i) + 0.3 * env * sin(w * 3.0 * i)
				buf[(s0 + i) % n] += s * env * vol
		2:
			for i in total:
				var env := 1.0
				if i < an:
					env = float(i) / an
				elif i >= dn:
					env = 1.0 - float(i - dn) / rn
				var ph := fmod(f * i / MRATE, 1.0)
				var s := (4.0 * absf(ph - 0.5) - 1.0) + 0.5 * sin(w * 0.5 * i)
				buf[(s0 + i) % n] += s * env * vol
		3:
			for i in total:
				var tt := float(i) / MRATE
				var s := sin(TAU * (44.0 * tt + 4.2 * (1.0 - exp(-tt * 25.0))))
				buf[(s0 + i) % n] += s * exp(-tt * 9.0) * vol
		4:
			var rate := 5.0 / maxf(dur, 0.01)
			var last := 0.0
			for i in total:
				var tt := float(i) / MRATE
				last += (mrng.randf_range(-1.0, 1.0) - last) * midi
				buf[(s0 + i) % n] += last * exp(-tt * rate) * vol


func _echo(buf: PackedFloat32Array, delay: float, feedback: float) -> void:
	var n := buf.size()
	var d := int(delay * MRATE)
	for i in n:
		buf[i] += buf[(i - d + n) % n] * feedback


func _pads(buf: PackedFloat32Array, chords: Array, each: float, vol: float) -> void:
	for i in chords.size():
		for m in chords[i]:
			_note(buf, i * each, each * 0.75, m, vol, 0, each * 0.3, each * 0.4)


func _chimes(buf: PackedFloat32Array, length: float, scale: Array, vol: float, gaps: Array) -> void:
	var t := 1.0
	while t < length - 0.5:
		_note(buf, t, 1.6, scale[mrng.randi() % scale.size()], vol, 1)
		if mrng.randf() < 0.45:
			_note(buf, t + 0.5, 1.6, scale[mrng.randi() % scale.size()], vol * 0.7, 1)
		t += gaps[mrng.randi() % gaps.size()]


## Title and the upper floors: slow D minor, a drone, and far-off chimes.
func _compose_vesper() -> PackedFloat32Array:
	var length := 32.0
	var buf := _buf(length)
	_note(buf, 0.0, 16.0, 38, 0.1, 0, 4.0, 4.0)
	_note(buf, 16.0, 16.0, 38, 0.1, 0, 4.0, 4.0)
	_pads(buf, [[50, 57, 62, 65], [46, 53, 58, 62], [43, 55, 58, 62], [45, 52, 57, 61]], 8.0, 0.042)
	_chimes(buf, length, [62, 65, 67, 69, 72, 74, 77, 81], 0.11, [1.5, 2.0, 2.5, 3.0])
	_echo(buf, 0.375, 0.34)
	return buf


## The lower floors: colder harmony over a slow heartbeat.
func _compose_deep() -> PackedFloat32Array:
	var length := 32.0
	var buf := _buf(length)
	_note(buf, 0.0, 16.0, 36, 0.11, 0, 4.0, 4.0)
	_note(buf, 16.0, 16.0, 36, 0.11, 0, 4.0, 4.0)
	_pads(buf, [[48, 55, 60, 63], [44, 51, 56, 60], [41, 53, 56, 60], [43, 50, 55, 56]], 8.0, 0.04)
	var t := 0.0
	while t < length:
		_note(buf, t, 0.5, 0, 0.3, 3)
		_note(buf, t + 0.32, 0.5, 0, 0.18, 3)
		t += 2.0
	_chimes(buf, length, [72, 75, 79, 80, 84], 0.06, [3.0, 4.0, 5.5])
	_echo(buf, 0.5, 0.4)
	return buf


## The Warden: 100 bpm, a driving bass line, bells on the changes.
func _compose_warden() -> PackedFloat32Array:
	var beat := 0.6
	var length := beat * 32.0
	var buf := _buf(length)
	var roots := [38, 34, 31, 33]
	var chords := [[50, 53, 57], [46, 50, 53], [43, 46, 50], [45, 49, 52]]
	var pattern := [0, 0, 12, 0, 7, 0, 12, 10]
	var motifs := [[74, 77, 76, 74, 69, -1, 74, -1], [74, 77, 70, 74, 77, -1, 74, -1],
		[70, 74, 79, 77, 74, -1, 70, -1], [73, 76, 81, 79, 76, 73, 69, -1]]
	for c in 4:
		var c0 := c * beat * 8.0
		for m in chords[c]:
			_note(buf, c0, beat * 7.0, m, 0.035, 0, 0.4, 0.6)
		_note(buf, c0, 2.4, roots[c] + 36, 0.1, 1)
		for bar in 2:
			for e in 8:
				var t := c0 + bar * beat * 4.0 + e * beat * 0.5
				_note(buf, t, beat * 0.36, roots[c] + pattern[e], 0.15, 2, 0.005, 0.05)
				var mn: int = motifs[c][e]
				if mn > 0 and (bar == 1 or e % 2 == 0):
					_note(buf, t, 0.7, mn, 0.075, 1)
				if e % 2 == 0:
					_note(buf, t, 0.4, 0, 0.36, 3)
				else:
					_note(buf, t, 0.05, 0.9, 0.05, 4)
				if e == 2 or e == 6:
					_note(buf, t, 0.14, 0.35, 0.16, 4)
	_echo(buf, beat * 0.75, 0.25)
	return buf


## The Daybreak ending: the same shape as Vesper's theme, lifted into D major.
func _compose_dawn() -> PackedFloat32Array:
	var length := 24.0
	var buf := _buf(length)
	_note(buf, 0.0, 12.0, 38, 0.08, 0, 3.0, 3.0)
	_note(buf, 12.0, 12.0, 38, 0.08, 0, 3.0, 3.0)
	_pads(buf, [[50, 57, 62, 66], [43, 55, 59, 62], [47, 54, 59, 62], [45, 52, 57, 61]], 6.0, 0.045)
	_chimes(buf, length, [62, 64, 66, 69, 71, 74, 76, 78, 81], 0.12, [0.75, 1.0, 1.5, 2.0])
	_echo(buf, 0.375, 0.36)
	return buf
