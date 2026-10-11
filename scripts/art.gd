extends RefCounted
## Every texture in the game is drawn here, in code, at startup. No image files.

const OUTLINE := Color(0.05, 0.04, 0.08)

const THEMES := {
	"cellar": {"floor": "74665c", "wall": "9a826f", "top": "2b2527", "accent": "554941"},
	"choir": {"floor": "666480", "wall": "8b86aa", "top": "272530", "accent": "cfc9b4"},
	"archive": {"floor": "4a7578", "wall": "5f989a", "top": "1d2c30", "accent": "3aa9c4"},
	"roots": {"floor": "74535d", "wall": "9e5f56", "top": "2b1d23", "accent": "b82e41"},
	"forge": {"floor": "665552", "wall": "aa6a46", "top": "2b2121", "accent": "ff8a2a"},
	"iron": {"floor": "525b6e", "wall": "7d89a3", "top": "1e222b", "accent": "9fd4ff"},
	"ash": {"floor": "827d78", "wall": "aaa29a", "top": "2a2826", "accent": "ff5a2a"},
}

static var tex := {}
static var theme_cache := {}
static var glow_at := {}
static var glow_col := {}
## Blank border around each texture, so the game knows where the feet are.
static var pad := {}

## Room left around part-animated sprites for limbs to move into.
const PAD := 8

# Each animated character is one drawing cut into named parts (rectangles in the
# drawing's own rows and columns). A frame is just how far each part has moved.
# Parts whose name starts with "u_" are drawn under the body and stay planted
# when the body bobs (legs, hems); the rest ride on the body (arms, weapons).
const PLAYER_P := {"u_legL": Rect2i(4, 17, 2, 3), "u_legR": Rect2i(7, 17, 2, 3), "hem": Rect2i(0, 15, 12, 2),
	"armL": Rect2i(0, 8, 3, 7), "scarf": Rect2i(4, 8, 4, 3)}
const PLAYER_F := {
	"idle0": {}, "idle1": {"hem": Vector2i(1, 0), "scarf": Vector2i(0, 1)},
	"w0": {"u_legL": Vector2i(0, -2), "u_legR": Vector2i(1, 0), "hem": Vector2i(-2, 0), "armL": Vector2i(-1, -1), "scarf": Vector2i(1, 0), "body": Vector2i(0, -1)},
	"w1": {"hem": Vector2i(-1, 0)},
	"w2": {"u_legR": Vector2i(0, -2), "u_legL": Vector2i(-1, 0), "hem": Vector2i(2, 0), "armL": Vector2i(0, 1), "scarf": Vector2i(-1, 0), "body": Vector2i(0, -1)},
	"w3": {"hem": Vector2i(1, 0)},
	"dash": {"u_legL": Vector2i(-1, -1), "u_legR": Vector2i(1, -2), "hem": Vector2i(0, -1), "armL": Vector2i(-1, -2), "scarf": Vector2i(-1, -1)},
	"atk": {"u_legL": Vector2i(-2, 0), "u_legR": Vector2i(2, 0), "armL": Vector2i(-1, 1), "body": Vector2i(0, 1)},
}
const HUSK_P := {"armL": Rect2i(0, 12, 4, 4), "armR": Rect2i(14, 12, 4, 4), "u_hem": Rect2i(4, 18, 10, 3)}
const HUSK_F := {
	"idle": {},
	"w0": {"armL": Vector2i(0, -2), "armR": Vector2i(0, 1), "u_hem": Vector2i(-1, 0), "body": Vector2i(0, -1)}, "w1": {},
	"w2": {"armL": Vector2i(0, 1), "armR": Vector2i(0, -2), "u_hem": Vector2i(1, 0), "body": Vector2i(0, -1)}, "w3": {},
	"wind": {"armL": Vector2i(-1, -4), "armR": Vector2i(1, -4), "body": Vector2i(0, 1)},
	"lunge": {"armL": Vector2i(0, -7), "armR": Vector2i(0, -7), "body": Vector2i(0, -1), "u_hem": Vector2i(0, 1)},
}
const CANTOR_P := {"staff": Rect2i(13, 0, 5, 21), "u_hem": Rect2i(0, 18, 12, 3)}
const CANTOR_F := {
	"idle": {},
	"w0": {"u_hem": Vector2i(-1, 0), "staff": Vector2i(0, -1)}, "w1": {},
	"w2": {"u_hem": Vector2i(1, 0), "staff": Vector2i(0, 1)}, "w3": {},
	"cast": {"staff": Vector2i(-1, -5), "body": Vector2i(0, 1)},
}
const BRUTE_P := {"armL": Rect2i(0, 12, 8, 10), "armR": Rect2i(18, 12, 8, 10),
	"u_legL": Rect2i(9, 19, 4, 5), "u_legR": Rect2i(13, 19, 4, 5)}
const BRUTE_F := {
	"idle": {},
	"w0": {"u_legL": Vector2i(0, -2), "armL": Vector2i(0, 2), "armR": Vector2i(0, -1), "body": Vector2i(0, -1)}, "w1": {},
	"w2": {"u_legR": Vector2i(0, -2), "armL": Vector2i(0, -1), "armR": Vector2i(0, 2), "body": Vector2i(0, -1)}, "w3": {},
	"wind": {"armL": Vector2i(-1, -6), "armR": Vector2i(1, -6), "body": Vector2i(0, 1)},
	"c0": {"u_legL": Vector2i(0, -3), "armL": Vector2i(1, -3), "armR": Vector2i(-1, -3), "body": Vector2i(0, 1)},
	"c1": {"u_legR": Vector2i(0, -3), "armL": Vector2i(1, -2), "armR": Vector2i(-1, -2), "body": Vector2i(0, 1)},
}
const WARDEN_P := {"glaive": Rect2i(22, 0, 8, 32), "armL": Rect2i(1, 16, 6, 6), "hem": Rect2i(4, 25, 16, 4),
	"u_legL": Rect2i(7, 29, 4, 3), "u_legR": Rect2i(13, 29, 4, 3)}
const WARDEN_F := {
	"idle": {},
	"w0": {"u_legL": Vector2i(0, -2), "hem": Vector2i(-1, 0), "glaive": Vector2i(0, -1), "armL": Vector2i(0, 1), "body": Vector2i(0, -1)}, "w1": {},
	"w2": {"u_legR": Vector2i(0, -2), "hem": Vector2i(1, 0), "glaive": Vector2i(0, 1), "armL": Vector2i(0, -1), "body": Vector2i(0, -1)}, "w3": {},
	"wind": {"glaive": Vector2i(1, -6), "armL": Vector2i(0, -2), "body": Vector2i(0, 1)},
	"strike": {"glaive": Vector2i(-2, 4), "armL": Vector2i(0, 1), "body": Vector2i(0, 2)},
	"cast": {"armL": Vector2i(-1, -6), "glaive": Vector2i(0, -2)},
}
static var mat_add: CanvasItemMaterial
static var mat_unlit: CanvasItemMaterial
static var flash_shader: Shader


static func build() -> void:
	if not tex.is_empty():
		return
	mat_add = CanvasItemMaterial.new()
	mat_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat_add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	mat_unlit = CanvasItemMaterial.new()
	mat_unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	flash_shader = Shader.new()
	flash_shader.code = "shader_type canvas_item;\nuniform float flash = 0.0;\nvoid fragment() {\n\tCOLOR.rgb = mix(COLOR.rgb, vec3(1.0), flash);\n}\n"

	tex["glow"] = _radial(64, 2.0, false)
	tex["light"] = _radial(128, 1.5, true)
	tex["shadow"] = _shadow()
	tex["stairs"] = _stairs()
	var px := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	px.fill(Color.WHITE)
	tex["px"] = ImageTexture.create_from_image(px)

	# --- Wren, the last lampwright: a dark hooded figure, face lost in shadow but
	# for the eyes, a red scarf, and a lantern hung from the hook of a long staff.
	var p_pal := {"k": "0f1019", "c": "1f2236", "C": "363b5e", "h": "4a5282", "f": "07070d", "e": "ffd24a",
		"s": "9c222c", "S": "e2493a", "w": "7a5634", "m": "b4bace", "l": "4c4c60", "y": "ffb347", "Y": "fff1a8",
		"b": "0b0b12"}
	# The whole figure in one piece: used for the title screen and the window icon.
	_add("player0", [
		"......kkkk....mmm.",
		".....kcCCck...m.m.",
		"....kcChhCck..m.m.",
		"....kChfffhCk.wlll",
		"....kChefehCk.wlyl",
		"....kcCfffCck.wlYl",
		".....kcsssck..wlyl",
		"....kcSsssSck.wlll",
		"...kcCcsSscCckw...",
		"...kcCCcsScCCkw...",
		"...kcCCccsccCmw...",
		"...kcCCcccccCkw...",
		"...kcCCccccCCkw...",
		"..kcCCCcccCCCkw...",
		"..kcCCcccccCCkw...",
		"..kcCccccccCckw...",
		"..kck.kcck.kckw...",
		"..k...kbbk...kw...",
		"......bb.bb...w...",
		"......bb.bb...w...",
	], p_pal, true, "eyY")
	# In play the body and the staff are separate: the legs step and the cloak
	# sways frame by frame, while the staff is its own sprite and really swings.
	_anim("player", [
		"....kkkk....",
		"...kcCCck...",
		"..kcChhCck..",
		"..kChfffhCk.",
		"..kChefehCk.",
		"..kcCfffCck.",
		"...kcsssck..",
		"..kcSsssSck.",
		".kcCcsSscCck",
		".kcCCcsScCCk",
		".kcCCccsccCm",
		".kcCCcccccCk",
		".kcCCccccCCk",
		"kcCCCcccCCCk",
		"kcCCcccccCCk",
		"kcCccccccCck",
		"kck.kcck.kck",
		"k...bb.bb..k",
		"....bb.bb...",
		"....bb.bb...",
	], p_pal, PLAYER_P, PLAYER_F, "e")
	_add("staff", [
		".mmm.",
		".m.m.",
		".m.m.",
		".wlll",
		".wlyl",
		".wlYl",
		".wlyl",
		".wlll",
		".w...",
		".w...",
		".w...",
		".w...",
		".w...",
		".w...",
		".w...",
		".w...",
		".w...",
		".w...",
		".w...",
		".w...",
	], p_pal, true, "yY")

	# --- Hollow Keeper: a buried lampwright that will not lie still -----------
	var h_pal := {"k": "1e182a", "K": "3d3354", "b": "e4dcc6", "B": "9c937e", "e": "5cf2ff", "t": "140f1c",
		"r": "1d1729", "R": "372c4c", "c": "c9c0a8"}
	var h_top := [
		"......kkkkkk......",
		".....kKKKKKKk.....",
		"....kKKkkkkKKk....",
		"....kKkbbbbkKk....",
		"...kKKbbbbbbKKk...",
		"...kKKeebbeeKKk...",
		"...kKKeeBBeeKKk...",
		"...kKKbBbbBbKKk...",
		"...kKktbtbtbkKk...",
		"....kkKbbbbKkk....",
		"...rrRRkkkkRRrr...",
		"..rRRRRRrrRRRRRr..",
	]
	var h_legs := [
		".....rRRrrRRr.....",
		"....rRRRrrRRRr....",
		"....rRrRrrRrRr....",
		"....r.rR..Rr.r....",
		"......r....r......",
	]
	_anim("husk", h_top + [
		".rRRrRRRrrRRRrRRr.",
		"bbRr.rRRrrRRr.rRbb",
		"cb...rRRrrRRr...bc",
		"c.c..rRRrrRRr..c.c",
	] + h_legs, h_pal, HUSK_P, HUSK_F, "e")
	_add("husk1", h_top + [
		"brRRrRRRrrRRRrRRrb",
		"cb.r.rRRrrRRr.r.bc",
		"c.c..rRRrrRRr..c.c",
		".....rRRrrRRr.....",
	] + h_legs, h_pal, true, "e")

	# --- Gloam Bat --------------------------------------------------------------
	var m_pal := {"w": "241634", "W": "5d3f8c", "f": "17101f", "F": "3b2a57", "e": "ff2e44", "t": "ffffff"}
	_add("moth0", [
		"wW..................Ww",
		"wWW................WWw",
		".wWWw....f..f....wWWw.",
		".wWWWw..fFffFf..wWWWw.",
		"..wWWWwfFeFFeFfwWWWw..",
		"..wWwWWfFFFFFFfWWwWw..",
		"...w.wWWfFttFfWWw.w...",
		".....w.wWffffWw.w.....",
		".......w.ffff.w.......",
		"..........ff..........",
	], m_pal, true, "e")
	_add("moth1", [
		"......................",
		".........f..f.........",
		"........fFffFf........",
		"..wwwwwfFeFFeFfwwwww..",
		".wWWWWWWfFFFFfWWWWWWw.",
		"wWWwWWwWWFttFWWwWWwWWw",
		"wWw.wW.wWffffWw.Ww.wWw",
		"w....w...ffff...w....w",
		"..........ff..........",
		"......................",
	], m_pal, true, "e")

	# --- Choir Cantor: antlered, masked, carries a hex-bell staff ---------------
	_anim("cantor", [
		".a.......a....oo..",
		".aa.....aa...oOOo.",
		"..aa...aa....oOOo.",
		"...ahhha......oo..",
		"..hhHHHhh.....s...",
		".hHHHHHHHh....s...",
		".hHmmmmmHh....s...",
		".hHmeMemHh....s...",
		".hHmmMmmHh...ms...",
		".hHHmtmHHhhhhms...",
		".hHHgggHHHHHh.s...",
		".hHLHHHLHhhh..s...",
		".hHLHHHLHh....s...",
		".hHLHHHLHh....s...",
		"hHHLHHHLHHh...s...",
		"hHHLHHHLHHh...s...",
		"hHLLHHHLLHh...s...",
		"hHLHHHHHLHh...s...",
		"hHHHhHhHHHh...s...",
		"hhHh.h.hHhh...s...",
		".h.h.....h.h..s...",
	], {"h": "33101a", "H": "7c1d30", "L": "ad3644", "m": "f1e8d6", "M": "b3a790", "e": "ff4fd0", "t": "1a0c12",
		"g": "d6a640", "s": "5e4029", "o": "ff4fd0", "O": "ffd6f6", "a": "cfc6b0"}, CANTOR_P, CANTOR_F, "eoO")

	# --- Bellringer: a furnace in a cracked bronze bell, on legs ----------------
	_anim("brute", [
		"........bbbbbbbbbb........",
		".......bBBByBBBBBBb.......",
		"......bBByyBBBBBBBBb......",
		"......bBByBBBBBBBBBb......",
		"......bBBBBBBBBBBBBb......",
		".....bBBeeeBBBBeeeBBb.....",
		".....bBeEEeBBBBeEEeBb.....",
		".....bBBeeeBBBBeeeBBb.....",
		"....bBBBBBBeeeeBBBBBBb....",
		"....bbBBBBeEEEEeBBBBbb....",
		"...bbbbbbbbbbbbbbbbbbbb...",
		"..dDDDDddddddddddddDDDDd..",
		".dDLDDDDdDDDDDDDDdDDDDLDd.",
		"dDLDDDDd.dDDDDDDd.dDDDDLDd",
		"dDDDDDd..dDDDDDDd..dDDDDDd",
		"dDDDDDd..dDDddDDd..dDDDDDd",
		"dDDDDd...dDDddDDd...dDDDDd",
		"cDDDDc...dDDddDDd...cDDDDc",
		"fffffff..dDDddDDd..fffffff",
		"fLfffff..dDd..dDd..fffffLf",
		"fffffff..dDd..dDd..fffffff",
		".fffff...dDd..dDd...fffff.",
		".........ddd..ddd.........",
		"........dddd..dddd........",
	], {"b": "5c3d18", "B": "bd8330", "y": "f5d27c", "e": "ff8a2a", "E": "ffe08a", "d": "221e2a", "D": "4b4359",
		"L": "6e6486", "c": "9a9aac", "f": "5c5474"}, BRUTE_P, BRUTE_F, "eE")

	# --- Ink Maw ----------------------------------------------------------------
	var s_pal := {"i": "0c1430", "I": "22407e", "s": "7fb4ff", "e": "ffe94a", "t": "eef4ff", "m": "04060c"}
	_add("slime0", [
		"......iiiiii......",
		"....iiIIIIIIii....",
		"...iIIsIIIIIIIi...",
		"..iIIsIIIIIIIIIi..",
		".iIIeeIIIIIIeeIIi.",
		".iIIIeeIIIIeeIIIi.",
		"iIIIIIIIIIIIIIIIIi",
		"iItmtmtmtmtmtmtIIi",
		"iImmmmmmmmmmmmmIIi",
		"iIItmtmtmtmtmtIIIi",
		".iIIIIIIIIIIIIIIi.",
		"..iiIIIIIIIIIIii..",
		"....iiiiiiiiii....",
	], s_pal, true, "e")
	_add("slime1", [
		"..................",
		"..................",
		"..................",
		".....iiiiiiii.....",
		"..iiiIIIIIIIIiii..",
		".iIIeeIIIIIIeeIIi.",
		"iIIIIeeIIIIeeIIIIi",
		"iItmtmtmtmtmtmtIIi",
		"iImmmmmmmmmmmmmIIi",
		"iIItmtmtmtmtmtIIIi",
		"iIIIIIIIIIIIIIIIIi",
		".iiIIIIIIIIIIIIii.",
		"..iiiiiiiiiiiiii..",
	], s_pal, true, "e")

	# --- Cinder Skull -----------------------------------------------------------
	var w_pal := {"r": "c2331c", "o": "ff7a1f", "y": "ffd24a", "s": "f3ead4", "S": "b9a98a", "k": "1a0c08", "e": "ff2a12"}
	_add("wisp0", [
		"....r....r....",
		"...ro...ro.r..",
		"..roy..roy.o..",
		"..royorroyor..",
		".royyooyyyyor.",
		".roysssssyyor.",
		"royssssssssyor",
		"roskksssskksor",
		"roskesssseksor",
		".ossssskssssso",
		".oSssssssssSo.",
		"..SsksksksS...",
		"..SsssssssS...",
		"...SkSkSkS....",
		"....SSSSS.....",
	], w_pal, false)
	_add("wisp1", [
		"...r.....r....",
		"..ro..r.ro....",
		"..roy.roy.or..",
		".royorroyoor..",
		".royyooyyyyor.",
		"royysssssyyor.",
		"royssssssssyor",
		"roskksssskksor",
		"roskesssseksor",
		".ossssskssssso",
		".oSssssssssSo.",
		"..SsksksksS...",
		"..SsssssssS...",
		"...SkSkSkS....",
		"....SSSSS.....",
	], w_pal, false)

	# --- Maren, the Hollow Warden: horned helm, cage-lantern heart, lamp-glaive --
	_anim("warden", [
		"......h..........h.....WWW....",
		".....hh..........hh...WW.wW...",
		".....hH..kkkkkk..Hh...W..wW...",
		".....hHhkKKKKKKkhHh......w....",
		"......hkKKsKKKKKkh.......w....",
		".......kKKKKKKKKk........w....",
		".......kgGGggGGgk........w....",
		".......kKKKkkKKKk........w....",
		".......kKkKkkKkKk........w....",
		"....s...kkKKKKkk...s.....w....",
		"...sKk.kkkkkkkkkk.kKs....w....",
		"..kKKKkkcCCCCCCckkKKKk...w....",
		".kKKsKKkcCkkkkCckKKsKKk..w....",
		".kKKKKKkCkgGGgkCkKKKKKkkkw....",
		".kKKKKkcCkGGGGkCckKKKKKKKw....",
		"..kKKkccCkgGGgkCcckKKkkKkw....",
		"..kKKk.cCCkkkkCCc.kKKk.kkw....",
		"..kKKk.cCCCCCCCCc.kkkk...w....",
		"..kKKk.cCCcCCcCCc........w....",
		"..kkkk.cCCcCCcCCc........w....",
		"..gGg..cCCcCCcCCc........w....",
		"..ggg.cCCCcCCcCCCc.......w....",
		"......cCCCcCCcCCCc.......w....",
		".....cCCCCcCCcCCCCc......w....",
		".....cCCCccCCccCCCc......w....",
		"....cCCCCcCCCCcCCCCc.....w....",
		"....cCCCcCCCCCCcCCCc.....w....",
		"....cCCccCCccCCccCCc.....w....",
		"....cCc.cCc..cCc.cCc.....w....",
		"....c...kKk..kKk...c.....w....",
		".......kKKk..kKKk........w....",
		".......kkkk..kkkk........w....",
	], {"k": "15151d", "K": "4c4c62", "s": "a2a2bc", "c": "3a0d14", "C": "8a1d28", "g": "ff8a2a", "G": "ffe08a",
		"h": "cdc3ac", "H": "8c8472", "w": "3c2b1d", "W": "c0c0d4"}, WARDEN_P, WARDEN_F, "gG")

	# --- A lampwright's relic on its stand ---------------------------------------
	_add("relic", [
		"....gggg....",
		"...gGGGGg...",
		"...gGyyGg...",
		"...gGGGGg...",
		"....gggg....",
		".....kk.....",
		"..kkkKKkkk..",
		"..kKKKKKKk..",
		"...kKKKKk...",
		"...kKKKKk...",
		"..kkKKKKkk..",
		".kKKKKKKKKk.",
		".kkkkkkkkkk.",
	], {"g": "ffb347", "G": "ffe08a", "y": "ffffff", "k": "24242e", "K": "64647c"}, true, "gGy")

	# --- Pickups and props ------------------------------------------------
	var heart_rows := [
		".rr...rr.",
		"rRRr.rRRr",
		"rRwRrRRRr",
		"rRRRRRRRr",
		".rRRRRRr.",
		"..rRRRr..",
		"...rRr...",
		"....r....",
	]
	var full := _ascii(heart_rows, {"r": "7a1020", "R": "e8384f", "w": "ffb0b8"}, true)
	var empty := _ascii(heart_rows, {"r": "241820", "R": "3a2a32", "w": "3a2a32"}, true)
	var half := full.duplicate() as Image
	var hw := half.get_width()
	half.blit_rect(empty, Rect2i(hw / 2 + 1, 0, hw - hw / 2 - 1, half.get_height()), Vector2i(hw / 2 + 1, 0))
	tex["heart2"] = ImageTexture.create_from_image(full)
	tex["heart1"] = ImageTexture.create_from_image(half)
	tex["heart0"] = ImageTexture.create_from_image(empty)

	_add("oil", [
		"..ccc..",
		"..gGg..",
		".gGGGg.",
		"gGGGGGg",
		"goooyog",
		"gooooog",
		"gooooog",
		".ggggg.",
	], {"c": "8a6a4a", "g": "5a7a8a", "G": "a8d0d8", "o": "ffa02a", "y": "ffe08a"})

	_add("urn", [
		"..uuuu..",
		".uUUUUu.",
		"..uddu..",
		".uUUUUu.",
		"uUyUUUUu",
		"uUyUUUUu",
		"uUUUUUUu",
		"uddddddu",
		".uUUUUu.",
		"..uuuu..",
	], {"u": "63402e", "U": "b47a52", "y": "e0b488", "d": "3a2418"})

	_add("brazier", [
		".kooyyook.",
		"kKKooooKKk",
		".kKKKKKKk.",
		"..kkkkkk..",
		"....kk....",
		"....kk....",
		"...kkkk...",
		"..kKKKKk..",
		".kkkkkkkk.",
	], {"k": "20202a", "K": "62627a", "o": "ff7a1f", "y": "ffd24a"})

	var lamp_rows := [
		"...kk...",
		"..kkkk..",
		".kGGGGk.",
		".kGggGk.",
		".kGggGk.",
		".kGGGGk.",
		"..kkkk..",
		"...kk...",
		"...kk...",
		"...kk...",
		"...kk...",
		"...kk...",
		"...kk...",
		"...kk...",
		"...kk...",
		"..kkkk..",
		".kKKKKk.",
		".kkkkkk.",
	]
	_add("lamp0", lamp_rows, {"k": "20202a", "K": "62627a", "G": "2c333c", "g": "222830"})
	_add("lamp1", lamp_rows, {"k": "20202a", "K": "62627a", "G": "ffd24a", "g": "fff6c8"})

	_add("page", [
		".pppppp.",
		"pPPPPPPp",
		"pPkkkkPp",
		"pPPPPPPp",
		"pPkkkPPp",
		"pPPPPPPp",
		"pPkkkkPp",
		"pPPPPPPp",
		".pppppp.",
	], {"p": "b89a68", "P": "f4e6bc", "k": "6a5a40"})

	_add("plaque", [
		"..ssssssss..",
		".sSSSSSSSSs.",
		"sSSgSggSgSSs",
		"sSSSSSSSSSSs",
		"sSgSgSSgSgSs",
		"sSSSSSSSSSSs",
		"sSSggSgSggSs",
		"sSSSSSSSSSSs",
		"ssssssssssss",
	], {"s": "3e3e4e", "S": "74748c", "g": "8af0d0"})

	var chest_pal := {"w": "4a2e1a", "W": "96602e", "g": "e0b040", "k": "1a1210", "y": "ffe070"}
	_add("chest0", [
		".wwwwwwwwww.",
		"wWWWWWWWWWWw",
		"wWWWWWWWWWWw",
		"gggggkkggggg",
		"wWWWWkkWWWWw",
		"wWWWWWWWWWWw",
		"wWWWWWWWWWWw",
		"wwwwwwwwwwww",
	], chest_pal)
	_add("chest1", [
		".wwwwwwwwww.",
		"wkkkkkkkkkkw",
		"wkyykyykyykw",
		"gggggggggggg",
		"wWWWWWWWWWWw",
		"wWWWWWWWWWWw",
		"wWWWWWWWWWWw",
		"wwwwwwwwwwww",
	], chest_pal)

	_add("cage", [
		"......kKk......",
		".....kkkkk.....",
		"..kkkKKKKKkkk..",
		".kKKKKKKKKKKKk.",
		".k..k..k..k..k.",
		".k..k..k..k..k.",
		".k..k..k..k..k.",
		".k..k..k..k..k.",
		".k..k..k..k..k.",
		".k..k..k..k..k.",
		".k..k..k..k..k.",
		".k..k..k..k..k.",
		".k..k..k..k..k.",
		".kKKKKKKKKKKKk.",
		"kkkkkkkkkkkkkkk",
	], {"k": "30303e", "K": "7a7a94"}, false)


	# --- Interface: carved stone, iron and chain, at the same pixel size as the world
	_build_ui()


## Frames, niches, chains and upgrade icons for the menus. Everything is drawn
## small and scaled up 3x so a UI pixel is the same size as a world pixel.
static func _build_ui() -> void:
	var stone := Color(0.125, 0.115, 0.15)
	var rim := Color(0.36, 0.33, 0.37)
	var iron := Color(0.2, 0.2, 0.27)
	tex["ui_card"] = _slab(stone, rim, Color(0.26, 0.21, 0.18), iron, Color(0.58, 0.58, 0.66), true)
	tex["ui_card_hot"] = _slab(Color(0.19, 0.13, 0.12), Color(0.5, 0.4, 0.34), Color(1.0, 0.62, 0.2), iron.lightened(0.12), Color(1.0, 0.85, 0.45), true)
	tex["ui_panel"] = _slab(Color(0.09, 0.08, 0.11), rim, Color(0.55, 0.38, 0.2), iron, Color(0.75, 0.6, 0.35), true)
	tex["ui_btn"] = _slab(Color(0.15, 0.14, 0.18), rim, Color(0.24, 0.21, 0.2), iron, Color(0.5, 0.5, 0.58), false)
	tex["ui_btn_hot"] = _slab(Color(0.22, 0.15, 0.12), Color(0.52, 0.42, 0.34), Color(1.0, 0.62, 0.2), iron, Color(1.0, 0.85, 0.45), false)
	tex["ui_btn_down"] = _slab(Color(0.3, 0.18, 0.1), Color(0.45, 0.36, 0.3), Color(1.0, 0.75, 0.35), iron, Color(1.0, 0.9, 0.6), false)

	# A recess cut into the stone, to hold an icon.
	var nimg := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	for y in 12:
		for x in 12:
			var d := mini(mini(x, y), mini(11 - x, 11 - y))
			var c := Color(0.045, 0.04, 0.06)
			if d == 0:
				c = Color(0.03, 0.025, 0.04) if (x == 0 or y == 0) else rim.lightened(0.12)
			elif d == 1:
				c = Color(0.02, 0.02, 0.03) if (x == 1 or y == 1) else Color(0.08, 0.07, 0.1)
			nimg.set_pixel(x, y, c)
	nimg.resize(36, 36, Image.INTERPOLATE_NEAREST)
	tex["ui_niche"] = ImageTexture.create_from_image(nimg)

	# A key cap for the number hints.
	var kimg := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	for y in 12:
		for x in 12:
			var d := mini(mini(x, y), mini(11 - x, 11 - y))
			if d == 0 and (x == 0 or x == 11) and (y == 0 or y == 11):
				continue
			var c := Color(0.2, 0.19, 0.23)
			if d == 0:
				c = OUTLINE
			elif d == 1:
				c = rim.lightened(0.2) if (x == 1 or y == 1) else rim.darkened(0.45)
			elif y >= 9:
				c = Color(0.13, 0.12, 0.15)
			kimg.set_pixel(x, y, c)
	kimg.resize(36, 36, Image.INTERPOLATE_NEAREST)
	tex["ui_key"] = ImageTexture.create_from_image(kimg)

	# A rule with a diamond at its centre (tinted per card).
	var dimg := Image.create(44, 5, false, Image.FORMAT_RGBA8)
	for x in 44:
		var dc := absi(x - 22)
		if dc > 4 and dc < 20:
			dimg.set_pixel(x, 2, Color(1, 1, 1, 0.9 if dc < 16 else 0.45))
		for y in 5:
			if dc + absi(y - 2) <= 2:
				dimg.set_pixel(x, y, Color.WHITE)
	dimg.resize(132, 15, Image.INTERPOLATE_NEAREST)
	tex["ui_rule"] = ImageTexture.create_from_image(dimg)

	_add_ui("ui_chain", [
		"..kk..",
		".k..k.",
		".k..k.",
		".k..k.",
		"..kk..",
		"..KK..",
		"..KK..",
		"..KK..",
		"..kk..",
		".k..k.",
		".k..k.",
		".k..k.",
		"..kk..",
		"..KK..",
		"..KK..",
		"..KK..",
	], {"k": "5a5a6c", "K": "8a8aa0"})

	# --- Upgrade icons ----------------------------------------------------------
	var fire := {"r": "c2331c", "o": "ff7a1f", "y": "ffd24a", "w": "ffffff", "c": "7fe4f5"}
	_add("i_sword", [
		".........ss.",
		"........sSs.",
		".......sSs..",
		"......sSs...",
		".....sSs....",
		"....sSs.....",
		".g.sSs......",
		".ggSs.......",
		"..ggg.......",
		".hg.gg......",
		"hh..........",
		"h...........",
	], {"s": "aab0c4", "S": "ffffff", "g": "d6a640", "h": "6a4a2a"})
	_add("i_hook", [
		"....ssss....",
		"...sS..Ss...",
		"..sS....Ss..",
		"..s......s..",
		"..s.....ss..",
		"..s.........",
		"..h.........",
		"..h.........",
		"..h.........",
		"..h.........",
		"..h.........",
		"..h.........",
	], {"s": "aab0c4", "S": "ffffff", "h": "8a5c3c"})
	_add("i_eye", [
		"...kkkkkk...",
		".kkwwwwwwkk.",
		"kwwwyyyywwwk",
		"kwwyyrryywwk",
		"kwwyyrryywwk",
		"kwwwyyyywwwk",
		".kkwwwwwwkk.",
		"...kkkkkk...",
	], {"k": "30303e", "w": "f4eede", "y": "ffb347", "r": "30101a"})
	_add("i_boot", [
		"...bbbb.....",
		"...bBBb.....",
		"...bBBb.....",
		"...bBBb.....",
		"...bBBbb....",
		"...bBBBBbb..",
		"...bBBBBBBb.",
		"...bBBBBBBb.",
		"...kkkkkkkk.",
	], {"b": "5c3c26", "B": "a06c44", "k": "2a1c14"})
	_add("i_flame", [
		".....r......",
		"....ro......",
		"....ror.....",
		"...royo.r...",
		"...royor....",
		"..royyor....",
		"..roywyor...",
		".roywwyor...",
		".roywwyor...",
		".royywyor...",
		"..royyor....",
		"...rrrr.....",
	], fire)
	_add("i_fork", [
		"..y......y..",
		".ywy....ywy.",
		"..y..y...y..",
		"..o.ywy..o..",
		"...o.y..o...",
		"...o.o.o....",
		"....ooo.....",
		".....o......",
		".....r......",
		".....r......",
	], fire)
	_add("i_lance", [
		"..........yy",
		".........ywy",
		"........ywy.",
		".......oy...",
		"......oo....",
		".....oo.....",
		"....ro......",
		"...rr.......",
		"..rr........",
		".r..........",
	], fire)
	_add("i_dash", [
		".cc...cc....",
		"..cc...cc...",
		"...cc...cc..",
		"....cc...cc.",
		"...cc...cc..",
		"..cc...cc...",
		".cc...cc....",
	], fire)
	_add("i_trail", [
		"......cc....",
		".......cc...",
		"o.o.....cc..",
		"royo.....cc.",
		"oyyo....cc..",
		".oo....cc...",
		"......cc....",
	], fire)
	_add("i_lamp", [
		"....kkkk....",
		"...k....k...",
		"...kkkkkk...",
		"..kkyyyykk..",
		"..kyywwyyk..",
		"..kyywwyyk..",
		"..kyyyyyyk..",
		"..kkyyyykk..",
		"...kkkkkk...",
		"..kkkkkkkk..",
	], {"k": "56566a", "y": "ffb347", "w": "fff6c8"})
	_add("i_motes", [
		".....oo.....",
		".....oo.....",
		"............",
		"............",
		"oo...ww...oo",
		"oo...ww...oo",
		"............",
		"............",
		".....oo.....",
		".....oo.....",
	], fire)
	_add("i_wave", [
		"....www.....",
		"......yww...",
		".......yww..",
		"........yw..",
		"........yww.",
		"........yww.",
		"........yw..",
		".......yww..",
		"......yww...",
		"....www.....",
	], fire)
	_add("i_burst", [
		".....y......",
		".y...y...y..",
		"..y..o..y...",
		"...yoooy....",
		"....owo.....",
		"yyoowwwooyy.",
		"....owo.....",
		"...yoooy....",
		"..y..o..y...",
		".y...y...y..",
		".....y......",
	], fire)
	_add("i_magnet", [
		"..www..www..",
		"..www..www..",
		"..rrr..rrr..",
		"..rrr..rrr..",
		"..rrr..rrr..",
		"..rRr..rRr..",
		"..rRrrrrRr..",
		"...rRRRRr...",
		"....rrrr....",
	], {"r": "b8262e", "R": "ec5a5a", "w": "e8e8f0"})
	_add("i_cloak", [
		"....mmmm....",
		"...mMMMMm...",
		"..mMMkkMMm..",
		"..mMkkkkMm..",
		"..mMMkkMMm..",
		".mMMMMMMMMm.",
		".mMMMMMMMMm.",
		"mMMoMMMMoMMm",
		"mMoyoMMoyoMm",
		"moyyyooyyyom",
	], {"m": "5c1a22", "M": "a02c3a", "k": "14080c", "o": "ff7a1f", "y": "ffd24a"})
	_add("i_star", [
		".....y......",
		".....y......",
		"....ywy.....",
		"...ywwwy....",
		"yyywwwwwyyy.",
		"...ywwwy....",
		"....ywy.....",
		".....y......",
		".....y......",
	], {"y": "9fe8ff", "w": "ffffff"})


## A stone slab with a bevelled rim, a carved inner line and (optionally) iron
## corner brackets. Built 24 px square and used as a nine-patch.
static func _slab(base: Color, rim: Color, line: Color, iron: Color, rivet: Color, brackets: bool) -> ImageTexture:
	var n := 24
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for y in n:
		for x in n:
			var d := mini(mini(x, y), mini(n - 1 - x, n - 1 - y))
			var lit := x == d or y == d
			var c: Color
			if d == 0:
				if (x == 0 or x == n - 1) and (y == 0 or y == n - 1):
					continue
				c = OUTLINE
			elif d == 1:
				c = rim.lightened(0.3) if lit else rim.darkened(0.4)
			elif d == 2:
				c = rim
			elif d == 3:
				c = rim.darkened(0.55)
			elif d == 4:
				c = line
			elif d == 5:
				c = base.darkened(0.4) if lit else base.lightened(0.1)
			else:
				c = _jit(base, rng, 0.018)
			img.set_pixel(x, y, c)
	for corner in 4:
		var fx := corner % 2 == 1
		var fy := corner >= 2
		if brackets:
			for i in range(1, 8):
				for t in range(1, 4):
					var shade := iron.lightened(0.25) if t == 1 else (iron if t == 2 else iron.darkened(0.4))
					_corner_px(img, n, i, t, fx, fy, shade)
					_corner_px(img, n, t, i, fx, fy, shade)
			_corner_px(img, n, 2, 2, fx, fy, rivet)
			_corner_px(img, n, 6, 2, fx, fy, rivet.darkened(0.25))
			_corner_px(img, n, 2, 6, fx, fy, rivet.darkened(0.25))
		else:
			_corner_px(img, n, 4, 4, fx, fy, rivet)
	img.resize(n * 3, n * 3, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


static func _corner_px(img: Image, n: int, x: int, y: int, fx: bool, fy: bool, c: Color) -> void:
	img.set_pixel(n - 1 - x if fx else x, n - 1 - y if fy else y, c)


static func _add_ui(id: String, rows: Array, pal: Dictionary) -> void:
	var img := _ascii(rows, pal, true)
	img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	tex[id] = ImageTexture.create_from_image(img)


## A ring-and-dot crosshair for the mouse, in lamp colours.
static func cursor() -> Image:
	var n := 33
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(16, 16)
	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(c)
			if absf(d - 10.0) < 1.2 or d < 1.8:
				img.set_pixel(x, y, Color(1.0, 0.82, 0.5))
			elif absf(d - 10.0) < 2.5 or d < 3.2:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.75))
	return img


## Builds every frame of a part-animated character (see the *_P / *_F tables).
static func _anim(id: String, rows: Array, pal: Dictionary, parts: Dictionary, frames: Dictionary, emissive: String = "") -> void:
	var grid := _ascii_raw(rows, pal)
	var egrid: Image = null
	if emissive != "":
		var epal := {}
		for ch in emissive:
			epal[ch] = pal[ch]
		egrid = _ascii_raw(rows, epal)
	for fname in frames:
		var fid: String = id + "_" + fname
		var offs: Dictionary = frames[fname]
		var img := _compose(grid, parts, offs)
		_outline(img)
		tex[fid] = ImageTexture.create_from_image(img)
		pad[fid] = PAD
		if egrid == null:
			continue
		var eimg := _compose(egrid, parts, offs)
		tex[fid + "_e"] = ImageTexture.create_from_image(eimg)
		var sum := Vector2.ZERO
		var n := 0
		for y in eimg.get_height():
			for x in eimg.get_width():
				if eimg.get_pixel(x, y).a > 0.0:
					sum += Vector2(x + 0.5, y + 0.5)
					n += 1
		glow_at[fid] = (sum / maxi(n, 1) - Vector2(eimg.get_width(), eimg.get_height()) * 0.5) if n > 0 else Vector2.ZERO
		glow_col[fid] = Color(pal[emissive[0]] as String)


static func _compose(grid: Image, parts: Dictionary, offs: Dictionary) -> Image:
	var w := grid.get_width()
	var h := grid.get_height()
	var out := Image.create(w + PAD * 2, h + PAD * 2, false, Image.FORMAT_RGBA8)
	var body := grid.duplicate() as Image
	for pname in parts:
		body.fill_rect(parts[pname], Color(0, 0, 0, 0))
	var base := Vector2i(PAD, PAD)
	var bo: Vector2i = offs.get("body", Vector2i.ZERO)
	for pname in parts:
		if (pname as String).begins_with("u_"):
			var r: Rect2i = parts[pname]
			var o: Vector2i = offs.get(pname, Vector2i.ZERO)
			out.blend_rect(grid, r, base + r.position + o)
	out.blend_rect(body, Rect2i(0, 0, w, h), base + bo)
	for pname in parts:
		if not (pname as String).begins_with("u_"):
			var r: Rect2i = parts[pname]
			var o: Vector2i = offs.get(pname, Vector2i.ZERO)
			out.blend_rect(grid, r, base + r.position + o + bo)
	return out


## Rows of characters to pixels, with no border and no outline.
static func _ascii_raw(rows: Array, pal: Dictionary) -> Image:
	var h: int = rows.size()
	var w := 0
	for r in rows:
		w = maxi(w, (r as String).length())
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var row: String = rows[y]
		for x in row.length():
			var ch: String = row[x]
			if pal.has(ch):
				img.set_pixel(x, y, Color(pal[ch] as String))
	return img


## Traces a dark line around whatever is drawn in the image.
static func _outline(img: Image) -> void:
	var src := img.duplicate() as Image
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.0:
				continue
			if (x > 0 and src.get_pixel(x - 1, y).a > 0.0) or (x < w - 1 and src.get_pixel(x + 1, y).a > 0.0) \
					or (y > 0 and src.get_pixel(x, y - 1).a > 0.0) or (y < h - 1 and src.get_pixel(x, y + 1).a > 0.0):
				img.set_pixel(x, y, OUTLINE)


static func _add(id: String, rows: Array, pal: Dictionary, outline: bool = true, emissive: String = "") -> void:
	tex[id] = ImageTexture.create_from_image(_ascii(rows, pal, outline))
	if emissive == "":
		return
	# A second texture holding only the glowing pixels. It is drawn unlit on top
	# of the sprite, so eyes and furnace-mouths burn in the dark.
	var epal := {}
	for ch in emissive:
		epal[ch] = pal[ch]
	tex[id + "_e"] = ImageTexture.create_from_image(_ascii(rows, epal, false))
	var w := 0
	for r in rows:
		w = maxi(w, (r as String).length())
	var sum := Vector2.ZERO
	var n := 0
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if emissive.contains(row[x]):
				sum += Vector2(x + 0.5, y + 0.5)
				n += 1
	if n > 0:
		glow_at[id] = sum / n - Vector2(w, rows.size()) * 0.5
		glow_col[id] = Color(pal[emissive[0]] as String)


## Turns rows of characters into an image, one palette colour per character,
## with a dark outline traced around the shape so it reads on any floor.
static func _ascii(rows: Array, pal: Dictionary, outline: bool) -> Image:
	var h: int = rows.size()
	var w := 0
	for r in rows:
		w = maxi(w, (r as String).length())
	var img := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	for y in h:
		var row: String = rows[y]
		for x in row.length():
			var ch: String = row[x]
			if pal.has(ch):
				img.set_pixel(x + 1, y + 1, Color(pal[ch] as String))
	if outline:
		var src := img.duplicate() as Image
		for y in h + 2:
			for x in w + 2:
				if src.get_pixel(x, y).a > 0.0:
					continue
				var near := false
				if x > 0 and src.get_pixel(x - 1, y).a > 0.0:
					near = true
				elif x < w + 1 and src.get_pixel(x + 1, y).a > 0.0:
					near = true
				elif y > 0 and src.get_pixel(x, y - 1).a > 0.0:
					near = true
				elif y < h + 1 and src.get_pixel(x, y + 1).a > 0.0:
					near = true
				if near:
					img.set_pixel(x, y, OUTLINE)
	return img


static func _radial(size: int, power: float, as_light: bool) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - half, y + 0.5 - half).length() / half
			var f := pow(clampf(1.0 - d, 0.0, 1.0), power)
			img.set_pixel(x, y, Color(f, f, f, 1.0) if as_light else Color(1, 1, 1, f))
	return ImageTexture.create_from_image(img)


static func _shadow() -> ImageTexture:
	var img := Image.create(14, 6, false, Image.FORMAT_RGBA8)
	for y in 6:
		for x in 14:
			var d := Vector2((x + 0.5 - 7.0) / 7.0, (y + 0.5 - 3.0) / 3.0).length()
			if d < 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0.42))
	return ImageTexture.create_from_image(img)


static func _stairs() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var band := int(y / 3.0)
			var c := Color(0.56, 0.52, 0.5).darkened(minf(0.95, band * 0.19))
			if y % 3 == 0:
				c = c.lightened(0.14)
			if x < 2 or x > 13:
				c = Color(0.12, 0.1, 0.12)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


# --- Dungeon tiles ------------------------------------------------------------

static func _jit(c: Color, rng: RandomNumberGenerator, amt: float) -> Color:
	var j := rng.randf_range(-amt, amt)
	return Color(clampf(c.r + j, 0.0, 1.0), clampf(c.g + j, 0.0, 1.0), clampf(c.b + j, 0.0, 1.0))


static func theme_tiles(id: String) -> Dictionary:
	if theme_cache.has(id):
		return theme_cache[id]
	var t: Dictionary = THEMES[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var cf := Color(t["floor"] as String)
	var cw := Color(t["wall"] as String)
	var ct := Color(t["top"] as String)
	var ca := Color(t["accent"] as String)
	var floors: Array = []
	var faces: Array = []
	var tops: Array = []
	for v in 6:
		floors.append(_floor_tile(v, cf, ca, rng))
	for v in 3:
		faces.append(_face_tile(v, cw, ct, rng))
	for v in 2:
		tops.append(_top_tile(ct, rng))
	var out := {"floor": floors, "face": faces, "top": tops, "trim": cw.darkened(0.45)}
	theme_cache[id] = out
	return out


static func _floor_tile(v: int, base: Color, accent: Color, rng: RandomNumberGenerator) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var layout := v % 3
	for y in 16:
		for x in 16:
			var grout := false
			var bevel := false
			match layout:
				0:
					grout = x == 0 or y == 0
					bevel = x == 1 or y == 1
				1:
					grout = x % 8 == 0 or y % 8 == 0
					bevel = x % 8 == 1 or y % 8 == 1
				2:
					var sx := 0 if y < 8 else 8
					grout = y % 8 == 0 or x == sx
					bevel = y % 8 == 1 or x == sx + 1
			var c := _jit(base, rng, 0.025)
			if grout:
				c = c.darkened(0.32)
			elif bevel:
				c = c.lightened(0.07)
			img.set_pixel(x, y, c)
	if v >= 3:
		var p := Vector2i(rng.randi_range(3, 12), rng.randi_range(3, 12))
		for i in rng.randi_range(5, 9):
			img.set_pixel(p.x, p.y, base.darkened(0.45))
			p += Vector2i(rng.randi_range(-1, 1), rng.randi_range(0, 1))
			p = p.clamp(Vector2i(1, 1), Vector2i(14, 14))
		for i in 3:
			img.set_pixel(rng.randi_range(2, 13), rng.randi_range(2, 13), accent)
	return img


static func _face_tile(v: int, wall: Color, top: Color, rng: RandomNumberGenerator) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var c: Color
			if y < 4:
				c = _jit(top.lightened(0.05), rng, 0.012)
			elif y == 4:
				c = wall.lightened(0.2)
			else:
				var by := y - 5
				var rowi := int(by / 4.0)
				var off := 4 if rowi % 2 == 1 else 0
				var mortar := by % 4 == 3 or (x + off + v * 3) % 8 == 7
				c = _jit(wall, rng, 0.03)
				if mortar:
					c = c.darkened(0.38)
				elif by % 4 == 0:
					c = c.lightened(0.08)
				c = c.darkened(0.3 * by / 11.0)
				if y == 15:
					c = c.darkened(0.35)
			img.set_pixel(x, y, c)
	return img


static func _top_tile(top: Color, rng: RandomNumberGenerator) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			img.set_pixel(x, y, _jit(top, rng, 0.012))
	for i in 5:
		img.set_pixel(rng.randi_range(1, 14), rng.randi_range(1, 14), top.darkened(0.3))
	return img


## Paints the whole floor into one image: floor slabs, brick wall faces where a
## wall looks down onto floor, and soft shadows where walls meet the ground.
static func compose(tiles: PackedByteArray, w: int, h: int, theme: String) -> Image:
	var t := theme_tiles(theme)
	var floors: Array = t["floor"]
	var faces: Array = t["face"]
	var tops: Array = t["top"]
	var trim: Color = t["trim"]
	var img := Image.create(w * 16, h * 16, false, Image.FORMAT_RGBA8)
	var src := Rect2i(0, 0, 16, 16)
	for y in h:
		for x in w:
			var hsh := absi((x * 73856093) ^ (y * 19349663))
			var dst := Vector2i(x * 16, y * 16)
			if tiles[y * w + x] == 1:
				var v := hsh % 3
				if (hsh >> 4) % 100 >= 72:
					v += 3
				img.blit_rect(floors[v], src, dst)
			elif y + 1 < h and tiles[(y + 1) * w + x] == 1:
				img.blit_rect(faces[hsh % 3], src, dst)
			else:
				img.blit_rect(tops[hsh % 2], src, dst)

	var sh_n := Image.create(16, 7, false, Image.FORMAT_RGBA8)
	for y in 7:
		for x in 16:
			sh_n.set_pixel(x, y, Color(0, 0, 0, 0.5 * (1.0 - y / 7.0)))
	var sh_w := Image.create(5, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 5:
			sh_w.set_pixel(x, y, Color(0, 0, 0, 0.28 * (1.0 - x / 5.0)))

	for y in h:
		for x in w:
			var is_floor := tiles[y * w + x] == 1
			var n := y > 0 and tiles[(y - 1) * w + x] == 1
			var s := y + 1 < h and tiles[(y + 1) * w + x] == 1
			var e := x + 1 < w and tiles[y * w + x + 1] == 1
			var wst := x > 0 and tiles[y * w + x - 1] == 1
			if is_floor:
				if not n:
					img.blend_rect(sh_n, Rect2i(0, 0, 16, 7), Vector2i(x * 16, y * 16))
				if not wst:
					img.blend_rect(sh_w, Rect2i(0, 0, 5, 16), Vector2i(x * 16, y * 16))
			elif not s:
				# The top of a wall: trace a ledge wherever it borders open floor.
				if n:
					img.fill_rect(Rect2i(x * 16, y * 16, 16, 2), trim)
				if e:
					img.fill_rect(Rect2i(x * 16 + 14, y * 16, 2, 16), trim)
				if wst:
					img.fill_rect(Rect2i(x * 16, y * 16, 2, 16), trim)
	return img
