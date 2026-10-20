extends CanvasLayer
## Everything drawn over the world: the HUD, dialogue, menus and story cards.

const Art = preload("res://scripts/art.gd")
const Story = preload("res://scripts/story.gd")
const TouchS = preload("res://scripts/touch.gd")

const C_PARCH := Color(0.93, 0.87, 0.72)
const C_EMBER := Color(1.0, 0.72, 0.35)
const C_DIM := Color(0.62, 0.58, 0.52)
const C_TEAL := Color(0.6, 0.9, 0.94)
## Which icon each kindling shows in its niche.
const ICONS := {"edge": "i_sword", "reach": "i_hook", "crit": "i_eye", "swift": "i_boot", "heart": "heart2",
	"glean": "heart2", "flask": "oil", "siphon": "oil", "kindle": "i_flame", "burn": "i_flame", "twin": "i_fork",
	"pierce": "i_lance", "step": "i_dash", "blink": "i_dash", "sear": "i_trail", "trail": "i_trail",
	"wick": "i_lamp", "orbit": "i_motes", "wave": "i_wave", "shatter": "i_burst", "magnet": "i_magnet",
	"thorn": "i_cloak", "focus": "page"}
const SPEAKERS := {"MAREN": Color(1.0, 0.72, 0.35), "WREN": Color(0.6, 0.9, 0.94)}

var main
var game = null
var auto := false
var auto_t := 0.0
var t := 0.0

var font: Font
var font_b: Font
var font_i: Font
var font_t: Font
var showcase := false
## Touch play: an on-screen pad replaces the keys, and taps stand in for clicks.
var touch := false
var pad = null
var ui_finger := -1
var buzz_t := -1.0
var fps_lbl: Label
var cap_box: VBoxContainer
var cap_a: Label
var cap_b: Label
var cap_t := 0.0
var punch_lbl: Label
var punch_t := 9.0
var root: Control
var hud_group: Control
var hud_c: Control
var float_c: Control
var mini: TextureRect
var mini_bg: Panel
var depth_lbl: Label
var sub_lbl: Label
var prompt_lbl: Label
var hint_lbl: Label
var card_box: VBoxContainer
var card_a: Label
var card_b: Label
var card_t := 0.0
var vmat: ShaderMaterial
var vig: ColorRect
var fader: ColorRect
var fade_cb := Callable()
var hurt := 0.0
## A brief red blush over the whole screen when Wren is struck.
var hurt_wash := 0.0
## A brief white flash over the whole picture, for the heaviest blows.
var flash_w := 0.0
var flash_rect: ColorRect
var floats: Array = []
var say_q: Array = []
var sub_t := 0.0
var sub_dur := 1.0
var hint_t := 0.0
var map_w := 1
var map_h := 1

var modal := ""
var modal_root: Control = null
var modal_cb := Callable()
var choice_cb := Callable()
var choice_n := 0
var lines: Array = []
var line_i := -1
var type_lbl: Label = null
var name_lbl: Label = null
var blink_lbl: Label = null
var typing := false
var type_acc := 0.0
var type_last := 0
var bg_c: Control = null
var modal_t0 := 0.0
var embers: Array = []


func _ready() -> void:
	layer = 10
	# Jersey 10 is drawn on a 10-pixel grid, so it is only ever used at multiples
	# of 10: at 30 its pixels are exactly the size of the world's.
	font = _load_font("Jersey10-Regular.ttf")
	font_b = font
	font_i = font
	font_t = _load_font("NewRocker-Regular.ttf")
	for i in 70:
		embers.append({"p": Vector2(randf(), randf()), "v": randf_range(0.02, 0.07), "s": randf_range(1.5, 4.0),
			"ph": randf() * TAU})

	root = Control.new()
	_full(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	vig = ColorRect.new()
	vig.visible = false
	_full(vig)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform float hurt = 0.0;\nuniform float wash = 0.0;\nvoid fragment() {\n\tvec2 uv = UV - 0.5;\n\tfloat v = smoothstep(0.32, 0.86, length(uv * vec2(1.0, 0.92)));\n\tCOLOR = vec4(0.65, 0.02, 0.03, max(v * hurt * 0.85, wash * 0.13));\n}\n"
	vmat = ShaderMaterial.new()
	vmat.shader = sh
	vig.material = vmat
	root.add_child(vig)

	flash_rect = ColorRect.new()
	_full(flash_rect)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = Color(1.0, 0.96, 0.88, 0.0)
	flash_rect.visible = false
	root.add_child(flash_rect)

	hud_group = Control.new()
	_full(hud_group)
	hud_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_group.visible = false
	root.add_child(hud_group)

	mini_bg = Panel.new()
	mini_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_bg.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0.45), Color(0.4, 0.3, 0.2, 0.8), 4, 1))
	hud_group.add_child(mini_bg)
	mini = TextureRect.new()
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mini.stretch_mode = TextureRect.STRETCH_SCALE
	hud_group.add_child(mini)

	hud_c = Control.new()
	_full(hud_c)
	hud_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_c.draw.connect(_draw_hud)
	hud_group.add_child(hud_c)
	float_c = Control.new()
	_full(float_c)
	float_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	float_c.draw.connect(_draw_floats)
	hud_group.add_child(float_c)
	if touch:
		pad = TouchS.new()
		pad.hud = self
		hud_group.add_child(pad)
	fps_lbl = _lbl("", 20, C_DIM, font, 4)
	_place(fps_lbl, 0.0, 0.0, Vector2(24, 100), Vector2(160, 24))
	fps_lbl.visible = false
	hud_group.add_child(fps_lbl)

	depth_lbl = _lbl("", 18, C_DIM, font, 4)
	depth_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(depth_lbl, 0.5, 0.0, Vector2(0, 14), Vector2(600, 26))
	hud_group.add_child(depth_lbl)

	hint_lbl = _lbl("WASD  move        Mouse  aim\nLeft click  strike  (third strike is heavy)\nRight click  ember bolt        X / middle click  throw oil\nSpace  dash  (your last blows echo)        C  snuff the lamp\nE  interact        Esc  pause        Q / R / F  relic powers", 20, C_PARCH, font, 5)
	_place(hint_lbl, 0.0, 1.0, Vector2(24, -18), Vector2(520, 156))
	hint_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	if touch:
		hint_lbl.text = "Left thumb  move\nHold STRIKE  fight  (third strike is heavy)\nHold BOLT  ember bolt  (uses oil)\nDrag off either stone to aim by hand\nFlask throws oil; the hooded lamp snuffs yours"
		hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_place(hint_lbl, 0.5, 0.0, Vector2(0, 46), Vector2(560, 136))
	hud_group.add_child(hint_lbl)

	prompt_lbl = _lbl("", 20, C_PARCH, font_b, 6)
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.size = Vector2(360, 30)
	prompt_lbl.visible = false
	hud_group.add_child(prompt_lbl)

	sub_lbl = _lbl("", 30, C_TEAL, font_i, 7)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place(sub_lbl, 0.5, 1.0, Vector2(0, -128), Vector2(980, 110))
	sub_lbl.modulate.a = 0.0
	if touch:
		# No power bar along the bottom on a phone, and thumbs on either side.
		_place(sub_lbl, 0.5, 1.0, Vector2(-20, -26), Vector2(620, 150))
	hud_group.add_child(sub_lbl)

	var cc := CenterContainer.new()
	_full(cc)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_group.add_child(cc)
	card_box = VBoxContainer.new()
	card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_box.add_theme_constant_override("separation", 4)
	card_box.modulate.a = 0.0
	cc.add_child(card_box)
	card_a = _lbl("", 30, C_EMBER, _spaced(font, 6), 6)
	card_a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_box.add_child(card_a)
	card_b = _lbl("", 76, C_PARCH, font_t, 10)
	card_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_box.add_child(card_b)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 180)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_box.add_child(pad)

	cap_box = VBoxContainer.new()
	cap_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap_box.add_theme_constant_override("separation", 0)
	_place(cap_box, 0.5, 0.0, Vector2(0, 26), Vector2(1200, 130))
	cap_box.modulate.a = 0.0
	hud_group.add_child(cap_box)
	cap_a = _lbl("", 52, C_EMBER, font_t, 10)
	cap_a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap_box.add_child(cap_a)
	cap_b = _lbl("", 30, C_PARCH, font, 8)
	cap_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap_box.add_child(cap_b)

	punch_lbl = _lbl("", 120, Color(1.0, 0.93, 0.78), font_t, 16)
	_full(punch_lbl)
	punch_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	punch_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	punch_lbl.modulate.a = 0.0
	root.add_child(punch_lbl)

	fader = ColorRect.new()
	_full(fader)
	fader.color = Color(0, 0, 0, 0)
	fader.visible = false
	fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fader)


# --- Small builders -------------------------------------------------------------

func _load_font(file: String) -> Font:
	var f := FontFile.new()
	if f.load_dynamic_font("res://fonts/" + file) != OK:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["Georgia", "Times New Roman"])
		return sys
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f


func _is_title_font(f: Font) -> bool:
	return f == font_t or (f is FontVariation and (f as FontVariation).base_font == font_t)


func _spaced(base: Font, px: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.spacing_glyph = px
	return fv


func _full(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Pins a control of a given size to a point on the screen (0..1 on each axis),
## so the layout holds at any window shape.
func _place(c: Control, ax: float, ay: float, off: Vector2, sz: Vector2) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = off.x - sz.x * ax
	c.offset_right = off.x + sz.x * (1.0 - ax)
	c.offset_top = off.y - sz.y * ay
	c.offset_bottom = off.y + sz.y * (1.0 - ay)


func _lbl(text: String, size: int, col: Color, f: Font = null, outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	if f == null:
		f = font
	if not _is_title_font(f):
		size = maxi(20, roundi(size / 10.0) * 10)
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _wrapped(text: String, size: int, col: Color, width: float, f: Font = null) -> Label:
	var l := _lbl(text, size, col, f)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _sb(bg: Color, border: Color, radius: int = 6, bw: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(24)
	return s


## A nine-patch style cut from one of the stone frames in Art.
func _frame_sb(id: String, pad: int) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = Art.tex[id]
	s.set_texture_margin_all(24)
	s.set_content_margin_all(pad)
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return s


func _btn(text: String, cb: Callable, w: float = 380.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 54)
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", C_PARCH)
	b.add_theme_color_override("font_hover_color", C_EMBER)
	b.add_theme_color_override("font_pressed_color", C_EMBER)
	b.add_theme_stylebox_override("normal", _frame_sb("ui_btn", 20))
	b.add_theme_stylebox_override("hover", _frame_sb("ui_btn_hot", 20))
	b.add_theme_stylebox_override("pressed", _frame_sb("ui_btn_down", 20))
	b.add_theme_stylebox_override("disabled", _frame_sb("ui_btn", 20))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if cb.is_valid():
		b.pressed.connect(cb)
	b.mouse_entered.connect(func(): Sfx.play("ui", -10.0))
	return b


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Starts a full-screen modal and returns a centred column to fill.
func _modal(id: String, dim: Color, backdrop: String = "") -> VBoxContainer:
	_close_modal()
	modal = id
	modal_t0 = t
	modal_root = Control.new()
	_full(modal_root)
	root.add_child(modal_root)
	root.move_child(fader, -1)
	if backdrop != "":
		bg_c = Control.new()
		_full(bg_c)
		bg_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_c.draw.connect(_draw_backdrop.bind(bg_c, backdrop))
		modal_root.add_child(bg_c)
	else:
		var d := ColorRect.new()
		_full(d)
		d.color = dim
		modal_root.add_child(d)
	var cc := CenterContainer.new()
	_full(cc)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_root.add_child(cc)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(vb)
	return vb


func _close_modal() -> void:
	if modal_root != null:
		modal_root.queue_free()
	modal_root = null
	bg_c = null
	type_lbl = null
	name_lbl = null
	blink_lbl = null
	typing = false
	modal = ""
	auto_t = 0.0
	if game != null:
		game.input_lock = 0.25


func _finish_modal() -> void:
	var cb := modal_cb
	modal_cb = Callable()
	_close_modal()
	if cb.is_valid():
		cb.call()


func blocking() -> bool:
	return modal != ""


# --- Public API used by the game ------------------------------------------------

func set_map(tex: Texture2D, w: int, h: int) -> void:
	map_w = w
	map_h = h
	mini.texture = tex
	var sz := Vector2(w * 3, h * 3)
	_place(mini, 1.0, 0.0, Vector2(-20, 20), sz)
	_place(mini_bg, 1.0, 0.0, Vector2(-16, 16), sz + Vector2(8, 8))


func floor_card(a: String, b: String) -> void:
	card_a.text = a
	card_b.text = b
	card_t = 4.0
	depth_lbl.text = "%s   -   %s" % [a, b]
	hint_t = 26.0 if game != null and game.depth == 1 else 0.0


## One huge word slammed into the middle of the screen, then gone (trailer).
func punch(text: String) -> void:
	punch_lbl.text = text
	punch_t = 0.0


## A flash to cut on.
func flash(col: Color = Color(1.0, 0.95, 0.85), strength: float = 0.8) -> void:
	fader.color = Color(col.r, col.g, col.b, strength)
	fader.visible = true
	var tw := create_tween()
	tw.tween_property(fader, "color:a", 0.0, 0.24)
	tw.tween_callback(fader.hide)


## A full-screen painting with the title over it, slowly pushing in (trailer).
func show_art(path: String, title: String, sub: String) -> void:
	_close_modal()
	modal = "art"
	modal_root = Control.new()
	_full(modal_root)
	modal_root.clip_contents = true
	root.add_child(modal_root)
	root.move_child(punch_lbl, -1)
	root.move_child(fader, -1)
	var back := ColorRect.new()
	_full(back)
	back.color = Color(0.015, 0.012, 0.03)
	modal_root.add_child(back)
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			var pic := TextureRect.new()
			_full(pic)
			pic.texture = ImageTexture.create_from_image(img)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			pic.pivot_offset = root.size * 0.5
			pic.scale = Vector2(1.13, 1.13)
			modal_root.add_child(pic)
			pic.create_tween().tween_property(pic, "scale", Vector2(1.27, 1.27), 6.0)
	# Darken the lower half so the title reads.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0.25), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.9)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 8
	gt.height = 128
	var shade := TextureRect.new()
	_full(shade)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	modal_root.add_child(shade)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_theme_constant_override("separation", 0)
	_full(vb)
	vb.offset_bottom = -46
	modal_root.add_child(vb)
	var tl := _lbl(title, 128, C_EMBER, _spaced(font_t, 8), 16)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_color_override("font_outline_color", Color(0.12, 0.04, 0.02, 0.95))
	vb.add_child(tl)
	var sl := _lbl(sub, 30, C_PARCH, font, 8)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sl)
	vb.modulate.a = 0.0
	var tw := vb.create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(vb, "modulate:a", 1.0, 0.9)


## A large heading across the top of the screen (used by the showcase reel).
func caption(a: String, b: String = "") -> void:
	cap_a.text = a
	cap_a.add_theme_font_size_override("font_size", 52 if a.length() <= 28 else 36)
	cap_b.text = b
	cap_t = 0.0


func say(text: String, dur: float = 4.5, col: Color = C_TEAL) -> void:
	say_q.append([text, dur, col])


## A line that cannot wait its turn: whatever is showing fades out at once.
func say_now(text: String, dur: float = 4.5, col: Color = C_TEAL) -> void:
	say_q.push_front([text, dur, col])
	sub_t = minf(sub_t, 0.2)


func float_text(wpos: Vector2, text: String, col: Color) -> void:
	floats.append({"w": wpos, "s": text, "c": col, "t": 0.0})


func fade_through(cb: Callable) -> void:
	_close_modal()
	modal = "fade"
	fade_cb = cb
	fader.color = Color(0, 0, 0, fader.color.a)
	fader.visible = true
	var tw := create_tween()
	tw.tween_property(fader, "color:a", 1.0, 0.26)
	tw.tween_callback(_fade_mid)
	tw.tween_property(fader, "color:a", 0.0, 0.42)
	tw.tween_callback(fader.hide)


func _fade_mid() -> void:
	if modal == "fade":
		modal = ""
	var cb := fade_cb
	fade_cb = Callable()
	if cb.is_valid():
		cb.call()


# --- Title ----------------------------------------------------------------------

func show_title() -> void:
	var vb := _modal("title", Color.BLACK, "title")
	vb.add_theme_constant_override("separation", 4)
	var title := _lbl("LANTERNFALL", 120, C_EMBER, _spaced(font_t, 8), 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.02, 0.9))
	vb.add_child(title)
	var s := _lbl("A  DESCENT  IN  SEVEN  DEPTHS", 30, C_DIM, font_i)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(s)
	vb.add_child(_spacer(150))
	var has_save: bool = main.latest_slot() >= 0
	var items: Array = []
	if has_save:
		items.append(["Continue", main.continue_game])
	items.append(["New Descent", main.pick_new])
	if has_save:
		items.append(["Load", main.pick_load])
	items.append(["Depths", main.pick_depth])
	items.append(["Town (%d embers)" % int(main.profile["embers"]), show_town])
	items.append(["Quit", main.quit_game])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	for it in items:
		grid.add_child(_btn(it[0], it[1], 290.0))
	var cc := CenterContainer.new()
	cc.add_child(grid)
	vb.add_child(cc)
	vb.add_child(_spacer(8))
	var k := _lbl("WASD move    Mouse aim    LMB strike    RMB bolt    Space dash    E interact    Q R F powers    F11 fullscreen    F3 2D / 3D    M mute", 20, C_DIM)
	if touch:
		k.text = "Left thumb moves    Hold STRIKE to fight    Drag off a stone to aim by hand"
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(k)


## Pick a depth to start from. Depths unlock the first time they are reached.
func show_depths(unlocked: int, cb: Callable, back: Callable) -> void:
	var vb := _modal("depths", Color.BLACK, "dark")
	vb.add_theme_constant_override("separation", 8)
	var tl := _lbl("Choose a depth", 56, C_EMBER, font_t, 8)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tl)
	vb.add_child(_wrapped("Start below the first depth and you arrive with the relics and kindlings you would have gathered on the way. Reach a depth once to unlock it.", 20, C_DIM, 980.0))
	vb.add_child(_spacer(6))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	for i in Story.DEPTHS.size():
		var open := i + 1 <= unlocked
		var text: String = "%s      %s" % [Story.ROMAN[i], Story.DEPTHS[i]["name"]] if open else "%s      - not yet reached -" % Story.ROMAN[i]
		var b := _btn(text, cb.bind(i + 1), 430.0)
		b.custom_minimum_size.y = 44
		b.disabled = not open
		b.add_theme_color_override("font_disabled_color", Color(0.36, 0.33, 0.31))
		if not open:
			b.modulate = Color(0.62, 0.6, 0.62)
		grid.add_child(b)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	vb.add_child(gc)
	vb.add_child(_spacer(6))
	var bc := CenterContainer.new()
	bc.add_child(_btn("Back", back, 240.0))
	vb.add_child(bc)


func _draw_backdrop(c: Control, kind: String) -> void:
	var sz := c.size
	var glow: Texture2D = Art.tex["glow"]
	var cx := sz.x * 0.5
	if kind == "dawn":
		_draw_dawn(c, sz, glow)
		return
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.015, 0.012, 0.03))
	if kind == "title":
		var gy := sz.y * 0.5 - 14.0
		var pul := 1.0 + 0.04 * sin(t * 2.3) + 0.02 * sin(t * 7.1)
		var r := 400.0 * pul
		c.draw_texture_rect(glow, Rect2(cx - r, gy - r, r * 2.0, r * 2.0), false, Color(1.0, 0.45, 0.12, 0.32))
		r = 150.0 * pul
		c.draw_texture_rect(glow, Rect2(cx + 42.0 - r, gy - 34.0 - r, r * 2.0, r * 2.0), false, Color(1.0, 0.75, 0.35, 0.55))
		var pt: Texture2D = Art.tex["player0"]
		var ps := Vector2(pt.get_width(), pt.get_height()) * 6.0
		var top := Vector2(cx, gy) - ps * 0.5
		c.draw_rect(Rect2(cx - 380.0, top.y + ps.y - 6.0, 760.0, 3.0), Color(0.4, 0.22, 0.1, 0.6))
		c.draw_texture_rect(pt, Rect2(top, ps), false)
	else:
		var r2 := 520.0
		c.draw_texture_rect(glow, Rect2(cx - r2, sz.y - 220.0, r2 * 2.0, r2 * 2.0), false, Color(1.0, 0.45, 0.12, 0.16))
	for e in embers:
		var p: Vector2 = e["p"]
		var a: float = 0.25 + 0.55 * (0.5 + 0.5 * sin(t * 2.0 + e["ph"])) * p.y
		var es: float = e["s"]
		c.draw_rect(Rect2(p.x * sz.x + sin(t + e["ph"]) * 12.0, p.y * sz.y, es, es), Color(1.0, 0.6, 0.2, a))


## The first morning Vesper has ever had: the sky warms, the sun clears the
## rooftops, and the Great Lantern stands dark against it.
func _draw_dawn(c: Control, sz: Vector2, glow: Texture2D) -> void:
	var k := clampf((t - modal_t0) / 9.0, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var top := Color(0.03, 0.04, 0.12).lerp(Color(0.16, 0.22, 0.45), k)
	var mid := Color(0.12, 0.08, 0.2).lerp(Color(0.75, 0.42, 0.42), k)
	var low := Color(0.3, 0.14, 0.12).lerp(Color(1.0, 0.8, 0.45), k)
	var hy := sz.y * 0.82
	c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(sz.x, 0), Vector2(sz.x, hy * 0.6), Vector2(0, hy * 0.6)]),
		PackedColorArray([top, top, mid, mid]))
	c.draw_polygon(PackedVector2Array([Vector2(0, hy * 0.6), Vector2(sz.x, hy * 0.6), Vector2(sz.x, sz.y), Vector2(0, sz.y)]),
		PackedColorArray([mid, mid, low, low]))
	var cx := sz.x * 0.5
	var sun_y := hy + 60.0 - 150.0 * k
	var r := 620.0
	c.draw_texture_rect(glow, Rect2(cx - r, sun_y - r, r * 2.0, r * 2.0), false, Color(1.0, 0.8, 0.45, 0.25 + 0.6 * k))
	r = 150.0
	c.draw_texture_rect(glow, Rect2(cx - r, sun_y - r, r * 2.0, r * 2.0), false, Color(1.0, 0.97, 0.85, 0.3 + 0.7 * k))
	c.draw_circle(Vector2(cx, sun_y), 34.0, Color(1.0, 0.97, 0.86, k))
	# Rooftops, and the lantern tower in the middle of town.
	var dark := Color(0.035, 0.03, 0.07)
	var n := 46
	var bw := sz.x / n
	for i in n:
		var hh := 26.0 + float((i * 7919 + 13) % 61) + (18.0 if i % 5 == 0 else 0.0)
		c.draw_rect(Rect2(i * bw, hy - hh, bw + 1.0, sz.y - hy + hh), dark)
		if (i * 31) % 4 == 0:
			c.draw_colored_polygon(PackedVector2Array([Vector2(i * bw, hy - hh), Vector2(i * bw + bw * 0.5, hy - hh - 16.0),
				Vector2(i * bw + bw, hy - hh)]), dark)
	var tx := sz.x * 0.74
	c.draw_rect(Rect2(tx - 22.0, hy - 250.0, 44.0, 260.0), dark)
	c.draw_rect(Rect2(tx - 32.0, hy - 258.0, 64.0, 10.0), dark)
	c.draw_colored_polygon(PackedVector2Array([Vector2(tx - 26.0, hy - 322.0), Vector2(tx, hy - 356.0), Vector2(tx + 26.0, hy - 322.0)]), dark)
	c.draw_rect(Rect2(tx - 26.0, hy - 324.0, 52.0, 5.0), dark)
	for bx in [-24.0, -9.0, 6.0, 21.0]:
		c.draw_rect(Rect2(tx + bx, hy - 322.0, 3.0, 66.0), dark)
	for e in embers:
		var p: Vector2 = e["p"]
		var es: float = e["s"] * 0.7
		c.draw_rect(Rect2(p.x * sz.x + sin(t + e["ph"]) * 12.0, p.y * sz.y, es, es), Color(1.0, 0.95, 0.75, 0.35 * k))


# --- Story cards and dialogue ---------------------------------------------------

func show_cards(cards: Array, cb: Callable) -> void:
	var vb := _modal("cards", Color.BLACK, "dark")
	modal_cb = cb
	lines = cards.duplicate()
	line_i = -1
	name_lbl = null
	type_lbl = _wrapped("", 30, C_PARCH, 900.0)
	type_lbl.custom_minimum_size = Vector2(900, 340)
	type_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_lbl.add_theme_constant_override("line_spacing", 8)
	vb.add_child(type_lbl)
	blink_lbl = _lbl("tap to continue" if touch else "click to continue", 17, C_DIM, font_i)
	blink_lbl.visible = not showcase
	blink_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(blink_lbl)
	_next_line()


func dialog(entries: Array, cb: Callable = Callable()) -> void:
	_close_modal()
	modal = "dialog"
	modal_cb = cb
	lines = entries.duplicate()
	line_i = -1
	modal_root = Control.new()
	_full(modal_root)
	root.add_child(modal_root)
	root.move_child(fader, -1)
	var d := ColorRect.new()
	_full(d)
	d.color = Color(0, 0, 0, 0.35)
	modal_root.add_child(d)
	var mc := MarginContainer.new()
	_full(mc)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_bottom", 44)
	modal_root.add_child(mc)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(col)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cc)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _frame_sb("ui_panel", 32))
	cc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	name_lbl = _lbl("", 30, C_EMBER, font)
	vb.add_child(name_lbl)
	type_lbl = _wrapped("", 30, C_PARCH, 880.0)
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	type_lbl.add_theme_constant_override("line_spacing", 5)
	vb.add_child(type_lbl)
	blink_lbl = _lbl("tap" if touch else "Space / click", 15, C_DIM, font_i)
	blink_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(blink_lbl)
	_next_line()


func _next_line() -> void:
	line_i += 1
	if line_i >= lines.size():
		_finish_modal()
		return
	var entry = lines[line_i]
	var text: String
	if entry is Array:
		var who: String = entry[0]
		text = entry[1]
		if name_lbl != null:
			name_lbl.text = who
			name_lbl.add_theme_color_override("font_color", SPEAKERS.get(who, Color(0.85, 0.78, 0.6)))
	else:
		text = entry
	type_lbl.text = text
	type_lbl.visible_characters = 0
	typing = true
	type_acc = 0.0
	type_last = 0


func _advance() -> void:
	if type_lbl == null:
		return
	if typing:
		typing = false
		type_lbl.visible_characters = -1
	else:
		Sfx.play("ui", -8.0)
		_next_line()


# --- Choices (boons, and the last decision) -------------------------------------

func show_choice(title: String, sub: String, opts: Array, cb: Callable, back: Callable = Callable(),
		back_label: String = "Back") -> void:
	var vb := _modal("choice", Color(0.0, 0.0, 0.02, 0.82))
	choice_cb = cb
	choice_n = opts.size()
	var tl := _lbl(title, 50, C_EMBER, font_t, 8)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tl)
	var sl := _lbl(sub, 21, C_DIM, font_i)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sl)
	vb.add_child(_spacer(6))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(row)
	for i in opts.size():
		row.add_child(_plaque(opts[i], i))
	if back.is_valid():
		vb.add_child(_spacer(4))
		var bc := CenterContainer.new()
		bc.add_child(_btn(back_label, back, 240.0 if back_label == "Back" else 520.0))
		vb.add_child(bc)


## One choice, as a stone plaque hung on two chains: an icon set into a niche,
## the name, a rule, what it does, and the key that picks it. It drops into
## place when the choice opens and lifts toward the lamp when pointed at.
func _plaque(o: Dictionary, i: int) -> Control:
	var col: Color = o.get("col", C_EMBER)
	# Four plaques (the chapel lamp) hang a little narrower to fit the row.
	var w := 300.0 if choice_n <= 3 else 268.0
	var h := 396.0
	var hang := 42.0
	# The holder keeps its place in the row; the card inside is free to move.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(w, h)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := Control.new()
	card.size = Vector2(w, h)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(card)
	for cx in [54.0, w - 54.0 - 24.0]:
		var chain := TextureRect.new()
		chain.texture = Art.tex["ui_chain"]
		chain.position = Vector2(cx, -6)
		chain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(chain)

	var b := Button.new()
	b.position = Vector2(0, hang)
	b.size = Vector2(w, h - hang)
	b.add_theme_stylebox_override("normal", _frame_sb("ui_card", 26))
	b.add_theme_stylebox_override("hover", _frame_sb("ui_card_hot", 26))
	b.add_theme_stylebox_override("pressed", _frame_sb("ui_card_hot", 26))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(_choose.bind(i))
	card.add_child(b)

	var mc := MarginContainer.new()
	_full(mc)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + side, 28)
	mc.add_theme_constant_override("margin_top", 30)
	mc.add_theme_constant_override("margin_bottom", 24)
	b.add_child(mc)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(cv)

	var niche := PanelContainer.new()
	niche.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nsb := StyleBoxTexture.new()
	nsb.texture = Art.tex["ui_niche"]
	nsb.set_texture_margin_all(9)
	nsb.set_content_margin_all(12)
	niche.add_theme_stylebox_override("panel", nsb)
	var icon := TextureRect.new()
	var key: String = o.get("icon", ICONS.get(o.get("id", ""), "i_flame"))
	icon.texture = Art.tex[key]
	icon.custom_minimum_size = Vector2(60, 60)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	niche.add_child(icon)
	var nc := CenterContainer.new()
	nc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nc.add_child(niche)
	cv.add_child(nc)

	cv.add_child(_wrapped(o["name"], 30, col.lightened(0.3), 240.0, font_t))
	var rule := TextureRect.new()
	rule.texture = Art.tex["ui_rule"]
	rule.modulate = Color(col.r, col.g, col.b, 0.9)
	rule.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(rule)
	var desc := _wrapped(o["desc"], 20, C_PARCH, 240.0)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cv.add_child(desc)

	var cap := TextureRect.new()
	cap.texture = Art.tex["ui_key"]
	cap.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var num := _lbl(str(i + 1), 20, C_PARCH)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_full(num)
	num.offset_bottom = -6
	cap.add_child(num)
	cap.visible = not touch
	cv.add_child(cap)

	b.mouse_entered.connect(_plaque_hover.bind(card, true))
	b.mouse_exited.connect(_plaque_hover.bind(card, false))
	# Drop in from above, one after another, with a little overshoot.
	card.position.y = -70.0
	card.modulate.a = 0.0
	var tw := card.create_tween()
	tw.tween_interval(0.02 + 0.05 * i)
	tw.tween_callback(Sfx.play.bind("clank", -10.0, 0.25))
	tw.set_parallel(true)
	tw.tween_property(card, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.1)
	return holder


func _plaque_hover(card: Control, on: bool) -> void:
	if not is_instance_valid(card):
		return
	if on:
		Sfx.play("ui", -10.0)
	card.create_tween().tween_property(card, "position:y", -10.0 if on else 0.0, 0.12).set_trans(Tween.TRANS_SINE)


func _choose(i: int) -> void:
	if modal != "choice" or i < 0 or i >= choice_n:
		return
	# A thumb already hammering STRIKE must not pick a plaque as it drops in.
	if touch and t - modal_t0 < 0.45:
		return
	Sfx.play("ui_ok")
	var cb := choice_cb
	choice_cb = Callable()
	_close_modal()
	if cb.is_valid():
		cb.call(i)


# --- Pause, death, ending -------------------------------------------------------

func _stats_text() -> String:
	if game == null:
		return ""
	var secs := int(game.run_time)
	return "Depth %s      Level %d      Foes put out: %d      Writings found: %d / %d      Time %d:%02d" % [
		Story.ROMAN[maxi(game.depth, 1) - 1], game.level, game.kills, game.pages,
		Story.PAGES.size() + Story.PLAQUES.size(), secs / 60, secs % 60]


func show_pause() -> void:
	var vb := _modal("pause", Color(0.0, 0.0, 0.02, 0.8))
	var tl := _lbl("PAUSED", 60, C_EMBER, _spaced(font_t, 6))
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tl)
	vb.add_child(_wrapped(_stats_text(), 18, C_DIM, 900.0))
	var names: Array = game.boon_names()
	var bt := "Kindlings:  " + (", ".join(PackedStringArray(names)) if names.size() > 0 else "none yet")
	vb.add_child(_wrapped(bt, 18, C_PARCH, 900.0))
	vb.add_child(_spacer(12))
	vb.add_child(_wrapped("Your descent is saved at every lamp you light and every depth you reach.", 20, C_DIM, 900.0))
	vb.add_child(_options_row())
	for b in [_btn("Resume", _close_modal), _btn("Quit to title", main.to_title),
			_btn("Quit game" if touch else "Quit to desktop", main.quit_game)]:
		var cc := CenterContainer.new()
		cc.add_child(b)
		vb.add_child(cc)


## Small switches on the pause screen. Each press flips one and rewrites its label.
func _options_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var keys := ["sound", "shake", "fps", "fast"]
	if touch:
		keys.insert(1, "haptics")
	for k in keys:
		var b := _btn(_opt_text(k), func(): pass, 215.0 if keys.size() < 5 else 196.0)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_opt_flip.bind(k, b))
		row.add_child(b)
	return row


func _opt_text(k: String) -> String:
	if k == "shake":
		return "Shake:  " + ["off", "low", "full"][clampi(int(main.profile["shake"]), 0, 2)]
	var on: bool = main.profile[k]
	match k:
		"sound":
			return "Sound:  " + ("on" if on else "off")
		"haptics":
			return "Rumble:  " + ("on" if on else "off")
		"fps":
			return "Frame rate:  " + ("shown" if on else "hidden")
	return "Picture:  " + ("fast" if on else "sharp")


func _opt_flip(k: String, b: Button) -> void:
	if k == "shake":
		# Full, then low, then off, then round again.
		main.profile[k] = (int(main.profile[k]) + 2) % 3
	else:
		main.profile[k] = not main.profile[k]
	main.apply_options()
	main._save_profile()
	b.text = _opt_text(k)
	Sfx.play("ui_ok")


func flash_white(a: float) -> void:
	flash_w = maxf(flash_w, a)


## Wren is struck: the edges redden and the screen blushes for an instant, both
## more the nearer she is to going out (k from 0, unhurt, to 1, out).
func hurt_hit(k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	hurt = maxf(hurt, 0.6 + 0.4 * k)
	hurt_wash = maxf(hurt_wash, 0.3 + 0.7 * k)


## A short rumble on phones; calls that come too close together are dropped.


func buzz(ms: int) -> void:
	if not touch or not main.profile["haptics"] or t - buzz_t < 0.07:
		return
	buzz_t = t
	Input.vibrate_handheld(ms)


## Keeps the HUD clear of camera cut-outs and rounded corners.
func _fit_safe_area() -> void:
	var win := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0.0 or safe.size.x <= 0:
		return
	var k := root.size.x / win.x
	hud_group.offset_left = clampf(safe.position.x * k, 0.0, 120.0)
	hud_group.offset_right = -clampf((win.x - safe.end.x) * k, 0.0, 120.0)


## Menus are built from ordinary buttons, which listen for a mouse. On a touch
## screen every finger is turned into a click here, so a menu still answers
## while another thumb is resting on the stick.
func _touch_ui(ev: InputEventScreenTouch) -> void:
	if ev.pressed:
		if ui_finger != -1 or modal == "" or modal == "fade":
			return
		ui_finger = ev.index
	elif ev.index != ui_finger:
		return
	else:
		ui_finger = -1
	var vp := get_viewport()
	var mm := InputEventMouseMotion.new()
	mm.position = ev.position
	mm.global_position = ev.position
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = ev.pressed
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if ev.pressed else 0
	mb.position = ev.position
	mb.global_position = ev.position
	if ev.pressed:
		vp.push_input.call_deferred(mm, true)
	vp.push_input.call_deferred(mb, true)
	if not ev.pressed:
		# Lift the pointer away again so nothing stays lit as if hovered.
		var off := InputEventMouseMotion.new()
		off.position = Vector2(-200, -200)
		off.global_position = off.position
		vp.push_input.call_deferred(off, true)


func show_death() -> void:
	var vb := _modal("death", Color(0.05, 0.0, 0.01, 0.86))
	var tl := _lbl("The dark takes you.", 70, Color(0.9, 0.3, 0.3), font_t, 8)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tl)
	# What did it, shown, and what to do about it next time.
	var cause: Dictionary = Story.CAUSES.get(main.last_cause, {})
	if not cause.is_empty():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 18)
		var icon := TextureRect.new()
		icon.texture = Art.tex.get(cause["icon"], Art.tex["glow"])
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(96, 96)
		icon.modulate = Color(1.0, 0.75, 0.7)
		row.add_child(icon)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		var who := "Put out by %s%s." % [cause["who"], "'s " + cause["how"] if not cause["how"].contains(",") else ", " + cause["how"]]
		col.add_child(_lbl(who, 30, C_PARCH, font_b))
		col.add_child(_wrapped(cause["tip"], 19, C_TEAL, 640.0, font_i))
		row.add_child(col)
		vb.add_child(row)
	if main.nem_news != "":
		vb.add_child(_wrapped(main.nem_news, 22, Color(1.0, 0.45, 0.35), 900.0, font_b))
	else:
		vb.add_child(_wrapped(Story.DEATH_LINES[randi() % Story.DEATH_LINES.size()], 20, C_DIM, 900.0, font_i))
	vb.add_child(_wrapped(_stats_text(), 18, C_DIM, 900.0))
	# Nothing earned is lost: say so.
	var got: int = main.run_embers
	var em := _lbl("%s%d embers wait for you in the town above." % [("+%d embers kept.   " % got) if got > 0 else "",
		int(main.profile["embers"])], 22, C_EMBER, font)
	em.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(em)
	vb.add_child(_spacer(8))
	var btns: Array = [_btn("Wake at your last lamp", main.retry), _btn("Quit to title", main.to_title)]
	# After a few falls, offer the lamp's resolve; it can be put down again any time.
	if int(main.profile["tally"].get("deaths", 0)) >= 3 or main.profile["resolve"]:
		var rb := _btn("", Callable(), 620.0)
		rb.add_theme_font_size_override("font_size", 22)
		_resolve_text(rb)
		rb.pressed.connect(func():
			main.set_resolve(not main.profile["resolve"])
			_resolve_text(rb))
		btns.append(rb)
	for b in btns:
		var cc := CenterContainer.new()
		cc.add_child(b)
		vb.add_child(cc)


func _resolve_text(b: Button) -> void:
	if main.profile["resolve"]:
		b.text = "The lamp's resolve: ON  (%d%% of blows turned)" % roundi(main.resolve_chance() * 100.0)
	else:
		b.text = "Accept the lamp's resolve (blows sometimes turned)"


# --- The town above ----------------------------------------------------------------

## The town Wren comes home to between descents. Embers carried up light its
## lamps one by one, and each lit lamp helps every descent after.
func show_town() -> void:
	var vb := _modal("town", Color.BLACK, "dark")
	vb.add_theme_constant_override("separation", 10)
	var tl := _lbl("THE LAMPLIT STREET", 56, C_EMBER, _spaced(font_t, 6), 8)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tl)
	var lit: int = (main.profile["town"] as Array).size()
	var sub := _lbl("%d embers      %d of %d lamps lit" % [int(main.profile["embers"]), lit, Story.TOWN.size()], 24, C_PARCH, font)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	for l in Story.TOWN:
		grid.add_child(_town_card(l))
	var cc := CenterContainer.new()
	cc.add_child(grid)
	vb.add_child(cc)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.add_child(_btn("Deeds", show_deeds, 260.0))
	row.add_child(_btn("Back", show_title, 260.0))
	vb.add_child(row)


func _town_card(l: Dictionary) -> Control:
	var have: bool = main.has_lamp(l["id"])
	var cost := int(l["cost"])
	var afford: bool = int(main.profile["embers"]) >= cost
	var b := Button.new()
	b.custom_minimum_size = Vector2(390, 150)
	b.add_theme_stylebox_override("normal", _frame_sb("ui_btn_hot" if have else "ui_btn", 20))
	b.add_theme_stylebox_override("hover", _frame_sb("ui_btn_hot", 20))
	b.add_theme_stylebox_override("pressed", _frame_sb("ui_btn_down", 20))
	b.add_theme_stylebox_override("disabled", _frame_sb("ui_btn", 20))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.disabled = have or not afford
	b.pressed.connect(func():
		if main.light_town_lamp(l["id"]):
			Sfx.play("whoomp", -4.0)
			Sfx.play("chime", -6.0)
			show_town())
	var hb := HBoxContainer.new()
	_full(hb)
	# Keep clear of the carved frame.
	hb.offset_left = 14
	hb.offset_right = -14
	hb.offset_top = 12
	hb.offset_bottom = -12
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 10)
	b.add_child(hb)
	var lamp := TextureRect.new()
	lamp.texture = Art.tex["lamp1" if have else "lamp0"]
	lamp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lamp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lamp.custom_minimum_size = Vector2(64, 0)
	lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(lamp)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.add_child(_lbl(l["name"], 21, C_EMBER if have else C_PARCH, font_b))
	var d := _wrapped(l["desc"], 15, C_DIM, 268.0)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(d)
	var price := _lbl("LIT" if have else "%d embers" % cost, 18, C_EMBER if have else (C_TEAL if afford else Color(0.55, 0.4, 0.38)), font)
	v.add_child(price)
	hb.add_child(v)
	for n in [v, d, price]:
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## Deeds done and to do, and the best of all descents.
func show_deeds() -> void:
	var vb := _modal("deeds", Color.BLACK, "dark")
	vb.add_theme_constant_override("separation", 6)
	var tl := _lbl("DEEDS", 56, C_EMBER, _spaced(font_t, 6), 8)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tl)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	for f in Story.FEATS:
		var done: bool = (main.profile["feats"] as Array).has(f["id"])
		var prog: int = mini(main.feat_progress(f), int(f["goal"]))
		var left := _lbl(("[x]  " if done else "[  ]  ") + f["name"], 22, C_EMBER if done else C_PARCH, font_b)
		left.custom_minimum_size = Vector2(380, 0)
		grid.add_child(left)
		var right := _lbl("%s   %d / %d%s" % [f["desc"], prog, int(f["goal"]),
			("   +%d" % int(f["reward"])) if int(f["reward"]) > 0 else ""], 18, C_DIM if not done else C_PARCH, font)
		grid.add_child(right)
	var cc := CenterContainer.new()
	cc.add_child(grid)
	vb.add_child(cc)
	vb.add_child(_spacer(6))
	var b: Dictionary = main.profile["best"]
	var ws := int(b.get("win_secs", 0))
	var best := _lbl("Deepest reached: %s      Most put out in one descent: %d      Quickest finish: %s      Falls: %d" % [
		Story.ROMAN[clampi(int(b.get("depth", 1)), 1, 7) - 1], int(b.get("kills", 0)),
		("%d:%02d" % [ws / 60, ws % 60]) if ws > 0 else "-", int(main.profile["tally"].get("deaths", 0))], 19, C_TEAL, font)
	best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(best)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	var rb := _btn("", Callable(), 620.0)
	rb.add_theme_font_size_override("font_size", 22)
	_resolve_text(rb)
	rb.pressed.connect(func():
		main.set_resolve(not main.profile["resolve"])
		_resolve_text(rb))
	row.add_child(rb)
	row.add_child(_btn("Back", show_town, 240.0))
	vb.add_child(row)


func show_end(kind: int) -> void:
	var vb := _modal("end", Color.BLACK, "dawn" if kind == 1 else "dark")
	var a := _lbl("LANTERNFALL", 24, C_DIM, _spaced(font, 8))
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(a)
	var tl := _lbl(Story.ENDING_NAMES[kind], 88, C_EMBER if kind == 0 else Color(1.0, 0.92, 0.7), _spaced(font_t, 6), 10)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tl)
	vb.add_child(_spacer(10))
	var st := _wrapped(_stats_text(), 19, C_PARCH, 1000.0)
	st.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	st.add_theme_constant_override("outline_size", 6)
	vb.add_child(st)
	var hint := _wrapped(Story.ENDING_HINTS[kind], 18, Color(0.85, 0.82, 0.75), 900.0, font_i)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override("outline_size", 6)
	vb.add_child(hint)
	vb.add_child(_spacer(250 if kind == 1 else 20))
	var cc := CenterContainer.new()
	cc.add_child(_btn("Return to the title", main.to_title))
	vb.add_child(cc)


# --- Input ----------------------------------------------------------------------

func _input(ev: InputEvent) -> void:
	if touch and ev is InputEventScreenTouch:
		_touch_ui(ev)
		return
	if modal == "" or modal == "fade":
		return
	var press := false
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k: int = ev.physical_keycode
		if modal == "choice" and k >= KEY_1 and k <= KEY_9:
			get_viewport().set_input_as_handled()
			_choose(k - KEY_1)
			return
		if modal == "pause" and (k == KEY_ESCAPE or k == KEY_P):
			get_viewport().set_input_as_handled()
			_close_modal()
			return
		press = k == KEY_SPACE or k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_E
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		press = true
	if not press:
		return
	match modal:
		"title":
			if ev is InputEventKey:
				get_viewport().set_input_as_handled()
				Sfx.play("ui_ok")
				main.continue_game()
		"cards", "dialog":
			get_viewport().set_input_as_handled()
			_advance()


# --- Per-frame ------------------------------------------------------------------

func _process(dt: float) -> void:
	t += dt
	hurt = maxf(0.0, hurt - dt * 2.2)
	var low := 0.0
	var in_game: bool = game != null and modal != "title" and modal != "cards" and modal != "end"
	if in_game and not game.dead and game.hp <= 2:
		low = 0.22 + 0.14 * sin(t * 5.0)
	var red := maxf(hurt, low) if in_game else 0.0
	hurt_wash = maxf(0.0, hurt_wash - dt * 7.0)
	var wash := hurt_wash if in_game else 0.0
	vmat.set_shader_parameter("hurt", red)
	vmat.set_shader_parameter("wash", wash)
	# Full-screen layers are only drawn while they have something to show.
	vig.visible = red > 0.01 or wash > 0.01
	flash_w = maxf(0.0, flash_w - dt * 9.0)
	flash_rect.color.a = flash_w * 0.2
	flash_rect.visible = flash_w > 0.01 and in_game
	hud_group.visible = in_game

	for e in embers:
		var p: Vector2 = e["p"]
		p.y -= e["v"] * dt
		if p.y < -0.02:
			p = Vector2(randf(), 1.02)
		e["p"] = p
	if bg_c != null:
		bg_c.queue_redraw()
	if blink_lbl != null:
		blink_lbl.modulate.a = 0.75 + 0.25 * sin(t * 3.0) if not typing else 0.0

	punch_t += dt
	if punch_t < 1.3:
		var ps := 1.0 + 0.7 * exp(-punch_t * 16.0)
		punch_lbl.pivot_offset = punch_lbl.size * 0.5
		punch_lbl.scale = Vector2(ps, ps)
		punch_lbl.modulate.a = clampf(punch_t * 14.0, 0.0, 1.0) * clampf((1.15 - punch_t) * 6.0, 0.0, 1.0)
		punch_lbl.visible = true
	else:
		punch_lbl.visible = false

	if typing and type_lbl != null:
		type_acc += dt * 60.0
		var n := int(type_acc)
		if n >= type_lbl.text.length():
			typing = false
			type_lbl.visible_characters = -1
		else:
			type_lbl.visible_characters = n
			if n - type_last >= 3:
				type_last = n
				Sfx.play("type", -15.0, 0.2)

	if auto and modal != "":
		auto_t += dt
		if auto_t > 0.3:
			auto_t = 0.0
			match modal:
				"cards", "dialog":
					typing = false
					_advance()
				"choice":
					_choose(0)

	if pad != null:
		pad.game = game
	if not in_game:
		return
	if OS.has_feature("mobile") and Engine.get_frames_drawn() % 30 == 0:
		_fit_safe_area()
	fps_lbl.visible = main.profile["fps"] and not showcase
	if fps_lbl.visible and Engine.get_frames_drawn() % 15 == 0:
		fps_lbl.text = "%d fps" % roundi(Engine.get_frames_per_second())
	hud_c.queue_redraw()
	float_c.queue_redraw()
	var i := floats.size() - 1
	while i >= 0:
		floats[i]["t"] += dt
		if floats[i]["t"] >= 0.8:
			floats.remove_at(i)
		i -= 1

	# Wren's thoughts and other one-line notices, shown one at a time.
	if sub_t > 0.0:
		sub_t -= dt
		sub_lbl.modulate.a = clampf(minf(sub_t * 2.0, (sub_dur - sub_t) * 4.0), 0.0, 1.0)
	elif say_q.size() > 0 and modal == "":
		var s: Array = say_q.pop_front()
		sub_lbl.text = s[0]
		sub_dur = s[1]
		sub_t = sub_dur
		sub_lbl.add_theme_color_override("font_color", s[2])
	else:
		sub_lbl.modulate.a = 0.0
	# Under a full-screen choice or the death screen, in-world lines only clutter.
	sub_lbl.visible = sub_lbl.modulate.a > 0.0 and modal == ""

	if card_t > 0.0:
		card_t -= dt
		card_box.modulate.a = clampf(minf(card_t * 0.9, (4.0 - card_t) * 2.0), 0.0, 1.0)
	else:
		card_box.modulate.a = 0.0
	card_box.visible = card_t > 0.0
	hint_t -= dt
	hint_lbl.modulate.a = clampf(hint_t * 0.5, 0.0, 0.9)
	cap_t += dt
	cap_box.modulate.a = clampf(cap_t * 3.0, 0.0, 1.0) if cap_a.text != "" else 0.0
	cap_box.visible = cap_a.text != ""
	depth_lbl.visible = not showcase
	hint_lbl.visible = not showcase and hint_t > 0.0 and modal == ""
	mini.visible = not showcase
	mini_bg.visible = not showcase

	var p = game.near_prop
	if p != null and modal == "" and not game.dead:
		prompt_lbl.text = ("" if touch else "[E]   ") + game.prompt_for(p)
		var sp: Vector2 = game.screen_pos(p["pos"])
		prompt_lbl.position = sp + Vector2(-180, -78) - hud_group.position
		prompt_lbl.visible = true
	else:
		prompt_lbl.visible = false


func _draw_hud() -> void:
	if game == null:
		return
	var c := hud_c
	var vs := hud_c.size
	_draw_warnings(c, vs)
	# Hearts.
	var hearts := int(ceil(game.max_hp / 2.0))
	for i in hearts:
		var v: int = game.hp - i * 2
		var key := "heart2" if v >= 2 else ("heart1" if v == 1 else "heart0")
		c.draw_texture_rect(Art.tex[key], Rect2(22 + i * 37, 18, 33, 30), false)
	# Oil, then experience, then the dash meter.
	var bx := 24.0
	var by := 58.0
	var oil_k: float = clampf(game.oil / game.max_oil, 0.0, 1.0)
	var bw: float = 150.0 + (game.max_oil - 100.0) * 0.8
	c.draw_rect(Rect2(bx - 2, by - 2, bw + 4, 16), Color(0, 0, 0, 0.65))
	c.draw_rect(Rect2(bx, by, bw * oil_k, 12), Color(1.0, 0.6, 0.14) if game.oil >= game.bolt_cost() else Color(0.6, 0.3, 0.12))
	c.draw_rect(Rect2(bx, by, bw * oil_k, 4), Color(1.0, 0.82, 0.4, 0.8))
	c.draw_texture_rect(Art.tex["oil"], Rect2(bx + bw + 10, by - 8, 18, 20), false)
	var xp_k: float = clampf(float(game.xp) / game.xp_next, 0.0, 1.0)
	c.draw_rect(Rect2(bx - 2, by + 20, 154, 9), Color(0, 0, 0, 0.65))
	c.draw_rect(Rect2(bx, by + 22, 150.0 * xp_k, 5), Color(0.55, 0.9, 0.95))
	c.draw_string(font, Vector2(bx + 162, by + 32), "Lv %d" % game.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, C_DIM)
	if game.spare_match:
		# The spare match sits beside the hearts until it is spent.
		var mx := 26.0 + hearts * 37.0
		var lit: bool = not game.match_used
		c.draw_rect(Rect2(mx + 5, 26, 4, 20), Color(0.85, 0.7, 0.45) if lit else Color(0.3, 0.26, 0.22))
		c.draw_rect(Rect2(mx + 3, 18, 8, 9), Color(1.0, 0.55, 0.15) if lit else Color(0.18, 0.15, 0.14))
		if lit:
			c.draw_rect(Rect2(mx + 5, 20, 4, 4), Color(1.0, 0.95, 0.6))
	if not touch:
		_draw_bar(c, vs)
	# Minimap marker.
	var pt: Vector2i = game.ptile
	var mp := mini.position + Vector2(pt) * 3.0
	c.draw_rect(Rect2(mp - Vector2(2, 2), Vector2(6, 6)), Color(0, 0, 0, 0.9))
	c.draw_rect(Rect2(mp - Vector2(1, 1), Vector2(4, 4)), Color(1.0, 0.85, 0.4) if int(t * 4.0) % 2 == 0 else Color(1.0, 1.0, 0.9))
	# The Warden's health.
	if game.boss_started and not game.boss_dead and is_instance_valid(game.boss) and game.boss.awake:
		var w := 560.0
		var x0 := (vs.x - w) * 0.5
		var y0 := 84.0
		var fr: float = clampf(game.boss.hp / game.boss.max_hp, 0.0, 1.0)
		c.draw_string(font_b, Vector2(x0, y0 - 9), "MAREN,  THE  HOLLOW  WARDEN", HORIZONTAL_ALIGNMENT_CENTER, w, 30, C_EMBER)
		c.draw_rect(Rect2(x0 - 3, y0 - 3, w + 6, 18), Color(0, 0, 0, 0.75))
		c.draw_rect(Rect2(x0, y0, w * fr, 12), Color(0.85, 0.25, 0.15))
		c.draw_rect(Rect2(x0, y0, w * fr, 4), Color(1.0, 0.55, 0.3))
		for m in [0.33, 0.66]:
			c.draw_rect(Rect2(x0 + w * m - 1, y0, 2, 12), Color(0, 0, 0, 0.8))


## The row of powers along the bottom: what you have, what it is bound to,
## and how long until it is ready again.
func _draw_bar(c: Control, vs: Vector2) -> void:
	var slots := [["LMB", "strike"], ["RMB", "bolt"], ["SPACE", "dash"], ["Q", "nova"], ["R", "spark"], ["F", "ward"]]
	var sw := 54.0
	var gap := 10.0
	var total := slots.size() * sw + (slots.size() - 1) * gap
	var sx := (vs.x - total) * 0.5
	var sy := vs.y - sw - 16.0
	for i in slots.size():
		var id: String = slots[i][1]
		var r := Rect2(sx + i * (sw + gap), sy, sw, sw)
		var owned := true
		var cdk := 0.0
		var can_pay := true
		match id:
			"strike":
				pass
			"bolt":
				can_pay = game.oil >= 18.0
			"dash":
				if game.dash_stock <= 0:
					cdk = clampf(game.dash_cd / game.stats["dash_cd"], 0.0, 1.0)
			_:
				owned = game.powers[id]
				cdk = clampf(game.pcd[id] / (Story.POWERS[id]["cd"] * game.stats["cdr"]), 0.0, 1.0)
				can_pay = game.oil >= Story.POWERS[id]["cost"]
		var ready := owned and can_pay and cdk <= 0.0
		c.draw_rect(r, Color(0.05, 0.04, 0.07, 0.82))
		if owned:
			_draw_icon(c, id, r.get_center(), ready)
		else:
			c.draw_rect(Rect2(r.get_center() - Vector2(7, 2), Vector2(14, 12)), Color(0.3, 0.27, 0.25))
			c.draw_arc(r.get_center() + Vector2(0, -3), 6.0, PI, TAU, 10, Color(0.3, 0.27, 0.25), 2.5)
		if cdk > 0.0:
			c.draw_rect(Rect2(r.position.x, r.position.y + sw * (1.0 - cdk), sw, sw * cdk), Color(0, 0, 0, 0.7))
		c.draw_rect(r, C_EMBER if ready else Color(0.35, 0.28, 0.22), false, 2.0)
		if id == "dash" and game.stats["dash_n"] > 1:
			for k in game.stats["dash_n"]:
				c.draw_rect(Rect2(r.position.x + 6 + k * 10, r.end.y - 10, 7, 5), Color(0.7, 0.95, 1.0) if k < game.dash_stock else Color(0.2, 0.25, 0.3))
		var key: String = slots[i][0]
		var kw := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var kp := Vector2(r.position.x + (sw - kw) * 0.5, sy - 6.0)
		c.draw_string_outline(font, kp, key, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0, 0, 0, 0.85))
		c.draw_string(font, kp, key, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, C_PARCH if owned else C_DIM)


func _draw_icon(c: Control, id: String, o: Vector2, on: bool) -> void:
	var col := Color(1.0, 0.8, 0.45) if on else Color(0.42, 0.37, 0.33)
	match id:
		"strike":
			c.draw_arc(o + Vector2(-7, 8), 22.0, -1.45, 0.1, 14, col, 5.0)
			c.draw_arc(o + Vector2(-7, 8), 15.0, -1.2, -0.2, 10, Color(col.r, col.g, col.b, 0.5), 2.0)
		"bolt":
			c.draw_line(o + Vector2(-16, 14), o + Vector2(2, -1), Color(col.r, col.g, col.b, 0.55), 4.0)
			c.draw_circle(o + Vector2(7, -6), 8.0, col)
			c.draw_circle(o + Vector2(7, -6), 3.5, Color(1, 1, 0.9) if on else col)
		"dash":
			var blue := Color(0.6, 0.92, 1.0) if on else col
			for k in 3:
				var x := -14.0 + k * 11.0
				c.draw_polyline(PackedVector2Array([o + Vector2(x, -12), o + Vector2(x + 10, 0), o + Vector2(x, 12)]),
					Color(blue.r, blue.g, blue.b, 0.4 + 0.3 * k), 3.5)
		"nova":
			c.draw_arc(o, 15.0, 0.0, TAU, 24, col, 3.5)
			c.draw_circle(o, 5.0, Color(1, 1, 0.9) if on else col)
			for k in 8:
				var d := Vector2.from_angle(TAU * k / 8.0)
				c.draw_line(o + d * 18.0, o + d * 24.0, col, 3.0)
		"spark":
			var blue := Color(0.65, 0.88, 1.0) if on else col
			c.draw_polyline(PackedVector2Array([o + Vector2(6, -22), o + Vector2(-8, -2), o + Vector2(3, -2), o + Vector2(-7, 22)]), blue, 4.0)
			c.draw_polyline(PackedVector2Array([o + Vector2(14, -10), o + Vector2(8, 2), o + Vector2(15, 2), o + Vector2(9, 14)]),
				Color(blue.r, blue.g, blue.b, 0.6), 2.0)
		"snuff":
			# A lamp with a hood over it; open when the lamp is covered.
			var lit: bool = game != null and not game.snuffed
			c.draw_rect(Rect2(o + Vector2(-9, -8), Vector2(18, 20)), Color(col.r, col.g, col.b, 0.35), false, 2.5)
			c.draw_circle(o + Vector2(0, 2), 5.0, Color(1, 0.85, 0.5) if lit else Color(0.25, 0.25, 0.32))
			c.draw_line(o + Vector2(-15, -12), o + Vector2(15, -12), col, 4.0)
			c.draw_line(o + Vector2(0, -18), o + Vector2(0, -12), col, 3.0)
		"flask":
			c.draw_circle(o + Vector2(0, 5), 11.0, col)
			c.draw_rect(Rect2(o + Vector2(-4, -15), Vector2(8, 10)), col)
			c.draw_circle(o + Vector2(-3, 3), 3.0, Color(1, 1, 0.9, 0.7) if on else Color(0, 0, 0, 0.3))
		"ward":
			c.draw_arc(o, 19.0, 0.0, TAU, 28, col, 3.0)
			c.draw_polyline(PackedVector2Array([o + Vector2(0, -11), o + Vector2(11, 0), o + Vector2(0, 11), o + Vector2(-11, 0),
				o + Vector2(0, -11)]), col, 2.5)
			c.draw_circle(o, 3.0, Color(1, 1, 0.9) if on else col)


## A foe winding up out of sight (off the screen, or lost in the dark) gets a
## red chevron at the edge of the screen, pointing at it: no blow should come
## from nowhere.
func _draw_warnings(c: Control, vs: Vector2) -> void:
	if game.dead or blocking():
		return
	var mid := vs * 0.5
	var pulse := 0.6 + 0.4 * sin(t * 18.0)
	for e in game.enemies:
		if e.dead or not e.awake:
			continue
		var tele: bool = e.state == "wind" or e.state == "cast" or e.state == "fuse" or e.state.ends_with("_w") \
			or e.state == "charge" or e.state == "lunge"
		if not tele:
			continue
		var sp: Vector2 = game.screen_pos(e.position) - hud_group.position
		var on_screen := Rect2(Vector2(40, 40), vs - Vector2(80, 80)).has_point(sp)
		if on_screen and e.visible:
			continue
		if (e.position - game.ppos).length() > 260.0:
			continue
		var d := (sp - mid).normalized() if sp != mid else Vector2.UP
		# Where the line from the centre toward it leaves the screen.
		var k := minf((mid.x - 44.0) / maxf(absf(d.x), 0.001), (mid.y - 44.0) / maxf(absf(d.y), 0.001))
		var at := mid + d * k
		if on_screen:
			at = sp
		var side := d.orthogonal()
		var col := Color(1.0, 0.25, 0.2, 0.9 * pulse)
		c.draw_colored_polygon(PackedVector2Array([at + d * 16.0, at - d * 6.0 + side * 13.0, at - d * 6.0 - side * 13.0]), col)
		c.draw_colored_polygon(PackedVector2Array([at - d * 4.0, at - d * 20.0 + side * 13.0, at - d * 20.0 - side * 13.0]),
			Color(col.r, col.g, col.b, col.a * 0.5))


## Over the world: the nemesis's name above its head, and, with the lamp
## snuffed, the eyes of whatever is moving out in the dark.
func _draw_marks() -> void:
	if game.dead or blocking():
		return
	for e in game.enemies:
		if e.dead:
			continue
		var d: float = (e.position - game.ppos).length()
		if e.nemesis and e.visible and d < 260.0:
			var s: String = e.nem["name"]
			var sp: Vector2 = game.screen_pos(e.position + Vector2(0, -e.cy * 2.0 - 6.0)) - hud_group.position
			var w := font_b.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			var at := sp - Vector2(w * 0.5, 0)
			float_c.draw_string_outline(font_b, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.9))
			float_c.draw_string(font_b, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.45, 0.35))
			var bw := 60.0
			var hp_k: float = clampf(e.hp / e.max_hp, 0.0, 1.0)
			float_c.draw_rect(Rect2(sp + Vector2(-bw * 0.5, 6), Vector2(bw, 5)), Color(0, 0, 0, 0.7))
			float_c.draw_rect(Rect2(sp + Vector2(-bw * 0.5, 6), Vector2(bw * hp_k, 5)), Color(1.0, 0.35, 0.25))
		if game.snuffed and not e.visible and d < 170.0 and (e.awake or d < 90.0) and e.kind != "slime" and e.kind != "slimelet":
			var ep: Vector2 = game.screen_pos(e.center() + Vector2(0, -2)) - hud_group.position
			var blink := 1.0 if fmod(t * 0.7 + e.seed_f, 3.0) > 0.12 else 0.0
			var a := (1.0 - d / 170.0) * 0.9 * blink
			var col := Color(1.0, 0.25, 0.2, a) if e.kind != "gloam" else Color(0.7, 0.45, 1.0, a)
			var gap := 4.0 if e.kind != "brute" else 6.0
			float_c.draw_circle(ep + Vector2(-gap, 0), 2.2, col)
			float_c.draw_circle(ep + Vector2(gap, 0), 2.2, col)
			float_c.draw_circle(ep, 9.0, Color(col.r, col.g, col.b, a * 0.12))


## A deed done: a line in ember, and the embers it pays.
func deed(f: Dictionary) -> void:
	var r := int(f["reward"])
	say("Deed done: %s%s" % [f["name"], ("   (+%d embers)" % r) if r > 0 else ""], 4.0, C_EMBER)
	Sfx.play("chime", -4.0)


func _draw_floats() -> void:
	if game == null:
		return
	_draw_marks()
	for f in floats:
		var k: float = f["t"] / 0.8
		var sp: Vector2 = game.screen_pos(f["w"]) - hud_group.position + Vector2(0, -36.0 * k)
		var c: Color = f["c"]
		c.a = 1.0 - k * k
		var s: String = f["s"]
		var w := font_b.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var pos := sp - Vector2(w * 0.5, 0)
		float_c.draw_string_outline(font_b, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0, 0, 0, c.a))
		float_c.draw_string(font_b, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, c)
