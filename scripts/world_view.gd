extends TextureRect
## The game world is drawn into its own small picture, one pixel for each pixel
## of the art, and that picture is scaled up to fill the window. Drawing pixel
## art at the window's full size costs the graphics card some twenty times the
## pixels for the same look. The HUD sits on top at full size, so text stays sharp.
## The 3D view, and the --hires switch, draw the world at full size instead.

var vp: SubViewport
var game = null
var hires := OS.get_cmdline_user_args().has("--hires")
## Takes a pixel of the world picture to a point in the window (in the same
## units the HUD lays itself out in).
var view_xf := Transform2D.IDENTITY
var _alloc := Vector2i.ZERO


func _init() -> void:
	vp = SubViewport.new()
	vp.transparent_bg = false
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.size = Vector2i(16, 16)
	add_child(vp)
	texture = vp.get_texture()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	# After everything else has moved the camera this frame (cutscenes and the
	# recorded reels set it from their own scripts).
	process_priority = 1000
	visible = false


func _process(_dt: float) -> void:
	sync()


## The size of the window in HUD units, and the mouse in the same units.
func screen_size() -> Vector2:
	return get_tree().root.get_visible_rect().size


func screen_mouse() -> Vector2:
	return get_tree().root.get_mouse_position()


## The mouse as a pixel of the world picture.
func view_mouse() -> Vector2:
	return view_xf.affine_inverse() * screen_mouse()


## Fits the world picture to the camera: its size, what it looks at, and where
## it lands in the window.
func sync() -> void:
	var on: bool = game != null and is_instance_valid(game) and game.cam != null
	visible = on
	if not on:
		return
	var root := get_tree().root
	var screen := screen_size()
	var cam: Camera2D = game.cam
	var z: float = maxf(cam.zoom.x, 0.05)
	var c: Vector2 = cam.position + cam.offset
	var full: bool = hires or (game.view3d != null and game.view3d.active)
	# s: picture pixels per world unit. k: window units per picture pixel.
	var s := 1.0
	var r := c
	if full:
		var phys := 1.0
		if root.content_scale_mode != Window.CONTENT_SCALE_MODE_VIEWPORT:
			phys = float(root.size.x) / maxf(screen.x, 1.0)
		s = z * phys
	else:
		# The view is held to whole pixels of the art, so sprites do not crawl
		# against each other; the picture is slid by the leftover fraction so the
		# camera still moves smoothly.
		r = c.round()
	var k := z / s
	var need := Vector2i(ceili(screen.x / k) + 4, ceili(screen.y / k) + 4)
	if full:
		_resize(need)
	elif need.x > _alloc.x or need.y > _alloc.y or need.x < _alloc.x * 0.6 or need.y < _alloc.y * 0.6:
		# The camera zooms all the time; the picture is only resized when it no
		# longer fits, and then with room to spare.
		_resize(Vector2i(ceili(need.x / 16.0) * 16 + 16, ceili(need.y / 16.0) * 16 + 16))
	vp.snap_2d_transforms_to_pixel = not full
	var half := Vector2(_alloc / 2)
	vp.canvas_transform = Transform2D(0.0, Vector2(s, s), 0.0, half - r * s)
	view_xf = Transform2D(0.0, Vector2(k, k), 0.0, screen * 0.5 - half * k + (r - c) * z)
	position = view_xf.origin
	size = Vector2(_alloc) * k


func _resize(sz: Vector2i) -> void:
	if sz == _alloc:
		return
	_alloc = sz
	vp.size = sz
