extends RefCounted
## All of the game's writing lives here.

const INTRO := [
	"Vesper has never seen a sunrise.\n\nFor three hundred years the Great Lantern has burned above the town, and the night has kept its distance.",
	"Nine days ago, the Lantern guttered.\n\nOld Maren, the Lampwright, took her tools and went down into the vaults beneath the tower - down to the Heartforge, where the first flame was kindled.\n\nShe did not come back.",
	"Last night the Lantern went out.\n\nNow the dark presses at the windows like deep water, and things move in it.",
	"You are Wren, her apprentice.\n\nYou have a hand-lamp, half a flask of oil, a lamp-hook, and her last instruction:\n\n\"If I'm not back in a week - don't follow me.\"\n\nIt has been nine days.",
]

const DEPTHS := [
	{"sub": "DEPTH  I", "name": "The Lamp Cellars", "theme": "cellar", "music": "depth1",
		"line": "Nine days. Sorry, Maren - I waited as long as I could."},
	{"sub": "DEPTH  II", "name": "The Buried Choir", "theme": "choir", "music": "depth2",
		"line": "That sound... the whole dark is humming."},
	{"sub": "DEPTH  III", "name": "The Drowned Archive", "theme": "archive", "music": "depth3",
		"line": "Water in the archive. She'd have wept. All those ledgers."},
	{"sub": "DEPTH  IV", "name": "The Cinder Roots", "theme": "roots", "music": "depth4",
		"line": "It's warm down here. Why is it getting warmer?"},
	{"sub": "DEPTH  V", "name": "The Singing Iron", "theme": "iron", "music": "depth5",
		"line": "The walls are humming. Don't hum back."},
	{"sub": "DEPTH  VI", "name": "The Ashen Stair", "theme": "ash", "music": "depth6",
		"line": "Ash. Three hundred years of it, and it's still falling."},
	{"sub": "DEPTH  VII", "name": "The Heartforge", "theme": "forge", "music": "forge",
		"line": "The Heartforge. She's here. I know she's here."},
]

## The practice hall used by the showcase recording.
const GALLERY := {"sub": "", "name": "", "theme": "choir", "music": "depth2", "line": ""}

## Maren left her tools behind her on the way down. One relic per depth.
const RELICS := [
	{"power": "nova", "key": "Q", "name": "Flare Salt",
		"text": "Maren's flare-salt, in its waxed pouch. A pinch on the wick and the lamp roars outward.\n\n\"For when they crowd you. Don't waste it on one.\""},
	{"power": "spark", "key": "R", "name": "Storm-Glass",
		"text": "A sealed glass with a thread of caught lightning turning inside it. It leaps to whatever is nearest, and then to whatever is nearest that.\n\n\"It doesn't much care who. Aim it first.\""},
	{"power": "ward", "key": "F", "name": "Hearth-Stone",
		"text": "A flat grey stone, still warm. Set down, it remembers being a fireplace: the dark slows at its edge, and what crosses it burns.\n\n\"Stand in the light when you can. That's the whole trade.\""},
	{"power": "match", "key": "", "name": "The Spare Match",
		"text": "A single long match in a brass case, with her initials scratched into the lid.\n\n\"Lampwrights are just the ones who carry a spare.\"\n\nOnce on each depth, a blow that would put you out will not."},
]

const POWERS := {
	"nova": {"name": "Flare Nova", "key": "Q", "cost": 30.0, "cd": 6.0, "desc": "A ring of fire bursts from the lamp, hurling foes back and burning hexes out of the air."},
	"spark": {"name": "Storm Spark", "key": "R", "cost": 25.0, "cd": 5.0, "desc": "Lightning leaps to the nearest foe and chains through the pack, stunning each."},
	"ward": {"name": "Hearth Ward", "key": "F", "cost": 35.0, "cd": 12.0, "desc": "A circle of hearth-light. Foes inside are slowed and scorched; you regain oil."},
}

const BESTIARY := [
	{"kind": "husk", "name": "Hollow Keeper", "desc": "A buried lampwright. Winds up, then lunges."},
	{"kind": "moth", "name": "Gloam Bat", "desc": "Fast and erratic. Bites, then wheels away."},
	{"kind": "cantor", "name": "Choir Cantor", "desc": "Keeps its distance and throws hexes. Strike them out of the air."},
	{"kind": "slime", "name": "Ink Maw", "desc": "The archive's ink, walking. Splits when slain."},
	{"kind": "brute", "name": "Bellringer", "desc": "Tolls once, then charges. Make it hit a wall."},
	{"kind": "wisp", "name": "Cinder Skull", "desc": "Rushes in and bursts. Kill it first or get clear."},
]

const PAGES := [
	["MAREN'S JOURNAL  -  DAY 1", "The cellars are as I left them, save for the cold.\n\nThe oil in the reservoirs hasn't run dry. It's full to the brim. The Lantern isn't starving.\n\nSo why is it dying?"],
	["MAREN'S JOURNAL  -  DAY 3", "Found the old choir. Three hundred years of lampwrights are buried here, and none of them are lying still.\n\nThey sing one note, all together. It's the note the Lantern hums on a still night.\n\nI always thought that hum was the glass."],
	["MAREN'S JOURNAL  -  DAY 5", "The founders' ledgers, half rotted. They never write \"the flame.\" They write \"the captive.\" They write \"her.\"\n\nOne entry, underlined twice: She asked again today when she may go home. We did not answer.\n\nI have tended that light for forty years, Wren. I have polished her bars."],
	["MAREN'S JOURNAL  -  DAY 6", "The roots of the tower go down further than the tower goes up. They are warm to the touch, and they pulse - slow, like something asleep.\n\nI put my ear to one. Under the hum there is a second sound.\n\nI think it is counting. Three hundred years of nights, one at a time."],
	["MAREN'S JOURNAL  -  DAY 7", "The iron here sings on its own. No wind, no hand.\n\nI caught myself humming with it. Then I caught my feet walking, and they were not walking the way I meant to go.\n\nThe founders didn't only build a cage for her, Wren. They built one for whoever came down here feeling sorry."],
	["MAREN'S JOURNAL  -  DAY 8, I THINK", "I understand the night now. The sun never left us. It has been circling out there in the dark for three hundred years, looking for its child - and the cage hides her, and so it hides us.\n\nWe didn't keep the night away. We made it.\n\nI'm going to open the cage. If I fail, the forge will take me for a warden, the way it took the others.\n\nIf you're reading this, I failed. I'm sorry. Don't let me stop you."],
]

const PLAQUES := [
	["FOUNDERS' PLAQUE", "\"Here we brought the light down out of the sky, and here we keep it.\n\nLet no keeper pity it.\""],
	["FOUNDERS' PLAQUE", "\"The keepers shall sing to it, that it may sleep.\n\nA sleeping light does not struggle.\""],
	["FOUNDERS' PLAQUE", "\"It fell on the ninth night of the comet. Small as a child. Bright as noon. It asked us the way back up.\n\nWe built a cage of singing iron instead, and a town around the cage.\""],
	["FOUNDERS' PLAQUE", "\"Should a keeper falter, let the iron keep the keeper.\n\nThe cage must have its warden.\""],
	["FOUNDERS' PLAQUE", "\"The iron was quenched in a keeper's last breath, that it might know the shape of obedience.\n\nIt will teach that shape to others.\""],
	["FOUNDERS' PLAQUE", "\"If you have read this far, you have already decided.\n\nSo did we. We were only afraid, and it was very bright.\""],
]

const BOSS_INTRO := [
	["WREN", "Maren?"],
	["MAREN", "Wren. I told you not to follow."],
	["MAREN", "I had my hand on the latch. Then the iron sang, and I... I am very good at my job, child."],
	["MAREN", "Go back up. Please. I can't make it let go of me."],
	["WREN", "I'm not leaving you down here."],
]

const BOSS_RETRY := [
	["MAREN", "Again, then. Wrist loose. Don't watch the blade - watch my shoulders."],
]

const BOSS_TAUNTS := [
	"\"That's it - like I taught you. It won't let me miss on purpose.\"",
	"\"It's taking the light, Wren. Put me out. Put me OUT.\"",
]

const BOSS_END := [
	["MAREN", "There you are. Look at you. Taller than the lamp-hook."],
	["MAREN", "Listen. She'll go back in the Lantern if you carry her. Vesper keeps its light. Another three hundred years of night - and someday, another warden."],
	["MAREN", "Or you open the latch. She goes home. The Lantern stays dark... and I think - I think - the morning finally finds us."],
	["MAREN", "I never got to see if I was right."],
	["MAREN", "Your hands now, Lampwright."],
]

const CHOICE := [
	{"name": "Carry the Ember up", "icon": "cage", "desc": "Relight the Great Lantern. Vesper keeps its light, and its night, and its cage.", "col": Color(1.0, 0.6, 0.2)},
	{"name": "Open the latch", "icon": "i_star", "desc": "Let her go home. The Lantern stays dark. Trust Maren that morning will come.", "col": Color(0.6, 0.9, 1.0)},
]

const ENDING_KEEP := [
	"You carry her up the long stair in Maren's own tongs.\n\nShe does not struggle. She has not struggled for a long time.",
	"The Great Lantern blazes. Vesper cheers your name. The night steps back to its old distance, and the things in it go quiet.",
	"On still evenings you hear the glass humming - and now you know the words.\n\nYou are a very good Lampwright.\n\nThe cage has its keeper.",
]

const ENDING_FREE := [
	"The latch is small and plain. It was never locked. Only held.",
	"The Ember rises - through the forge, the roots, the archive, the choir - through three hundred years of stone.\n\nThe buried keepers fall quiet as she passes.",
	"Vesper spends one terrible hour in perfect dark.\n\nThen the eastern sky, which no one living has ever seen be anything but black, goes grey.\n\nThen gold.",
	"You sit on the tower steps with soot on your hands and watch the first morning.\n\nSomewhere very far above, something small and bright is finally home.",
]

const ENDING_NAMES := ["THE KEPT FLAME", "DAYBREAK"]
const ENDING_HINTS := [
	"There was another choice at the latch.",
	"There was another choice at the latch.",
]

const DEATH_LINES := [
	"\"A lamp that goes out can be lit again. That's the whole trade.\"  - Maren",
	"\"Trim the wick, mind your feet, and never fight in the dark if you can fight in the light.\"  - Maren",
	"\"You'll fall. Everybody falls. Lampwrights are just the ones who carry a spare match.\"  - Maren",
	"\"The dark isn't cruel, Wren. It's only patient.\"  - Maren",
]

const BOONS := [
	{"id": "edge", "name": "Keen Edge", "desc": "Your lamp-hook bites deeper.\n+25% strike damage.", "col": Color(1.0, 0.85, 0.55)},
	{"id": "reach", "name": "Long Hook", "desc": "A longer haft, a wider sweep.\n+20% strike reach.", "col": Color(1.0, 0.85, 0.55)},
	{"id": "swift", "name": "Lamplighter's Stride", "desc": "A hundred streets before dusk.\n+12% movement speed.", "col": Color(0.55, 0.9, 0.95)},
	{"id": "heart", "name": "Stubborn Heart", "desc": "+1 heart, and one heart mended.", "col": Color(0.95, 0.3, 0.4)},
	{"id": "flask", "name": "Deep Flask", "desc": "+35 oil capacity.\nYour flask is refilled.", "col": Color(1.0, 0.65, 0.15)},
	{"id": "kindle", "name": "Kindled Bolt", "desc": "Ember bolts burn hotter.\n+40% bolt damage.", "col": Color(1.0, 0.55, 0.15)},
	{"id": "twin", "name": "Forked Flame", "desc": "Each cast throws two more ember bolts in a fan.", "col": Color(1.0, 0.55, 0.15)},
	{"id": "step", "name": "Quick Step", "desc": "Your dash recovers 25% faster.", "col": Color(0.55, 0.9, 0.95)},
	{"id": "wick", "name": "Bright Wick", "desc": "Your lamp burns wider, and oil seeps back faster.", "col": Color(1.0, 0.9, 0.6)},
	{"id": "glean", "name": "Gleaner", "desc": "The fallen leave hearts behind more often.", "col": Color(0.95, 0.3, 0.4)},
	{"id": "sear", "name": "Searing Dash", "desc": "Dashing through a foe burns it.", "col": Color(0.55, 0.9, 0.95), "unique": true},
	{"id": "siphon", "name": "Wick-Thief", "desc": "Every strike that lands returns a little oil.", "col": Color(1.0, 0.65, 0.15)},
	{"id": "thorn", "name": "Ember Cloak", "desc": "When you are struck, you flare and scorch everything near you.", "col": Color(1.0, 0.45, 0.2), "unique": true},
	{"id": "pierce", "name": "Lance of Light", "desc": "Ember bolts pass through one more foe.", "col": Color(1.0, 0.55, 0.15)},
	{"id": "orbit", "name": "Ember Motes", "desc": "Two motes of fire circle you, searing whatever they touch.", "col": Color(1.0, 0.7, 0.25)},
	{"id": "wave", "name": "Crescent Wave", "desc": "Your heavy third strike throws a blade of light that cuts through everything in its path.", "col": Color(1.0, 0.9, 0.6)},
	{"id": "burn", "name": "Afterburn", "desc": "Ember bolts set foes alight. They keep burning.", "col": Color(1.0, 0.45, 0.15)},
	{"id": "shatter", "name": "Cinderburst", "desc": "Slain foes burst, scorching everything beside them.", "col": Color(1.0, 0.45, 0.15)},
	{"id": "blink", "name": "Double Step", "desc": "You can dash twice before needing to recover.", "col": Color(0.55, 0.9, 0.95), "unique": true},
	{"id": "trail", "name": "Cinder Trail", "desc": "Your dash leaves a line of fire behind it.", "col": Color(1.0, 0.55, 0.2), "unique": true},
	{"id": "magnet", "name": "Lodestone Wick", "desc": "Cinders fly to you from much farther off, and the fallen leave more of them.", "col": Color(1.0, 0.8, 0.4)},
	{"id": "crit", "name": "Keen Eye", "desc": "+15% chance for a strike to land twice as hard.", "col": Color(1.0, 0.85, 0.55)},
	{"id": "echo", "name": "Second Self", "desc": "Your echo strikes harder and comes back sooner after a dash.", "col": Color(0.55, 0.9, 0.95)},
	{"id": "focus", "name": "Maren's Notes", "desc": "Flare Nova, Storm Spark and Hearth Ward hit 30% harder and return sooner.", "col": Color(0.7, 0.85, 1.0)},
]

const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII"]


# --- Deaths ---------------------------------------------------------------------

## What put Wren out, by the kind of foe: who it was, and how it does it.
const CAUSES := {
	"husk": {"who": "a Hollow Keeper", "how": "lunge", "icon": "husk_lunge",
		"tip": "Keepers wind up before they lunge. Step aside, or strike as they come and the blow breaks on you."},
	"gloam": {"who": "a gloam", "how": "lunge, out of the dark", "icon": "husk_lunge",
		"tip": "Gloams only come when the lamp burns low. Save some oil, or rest at a lamp to fill it."},
	"moth": {"who": "a Gloam Bat", "how": "bite", "icon": "moth0",
		"tip": "Bats bite and wheel away. Swing as they come back in; a sweep catches them mid-turn."},
	"cantor": {"who": "a Choir Cantor", "how": "hex", "icon": "cantor_cast",
		"tip": "A struck hex flies back at whoever threw it. Swing at it as it reaches you."},
	"slime": {"who": "an Ink Maw", "how": "hop", "icon": "slime0",
		"tip": "Ink Maws split when they die. Back away from the pieces rather than through them."},
	"slimelet": {"who": "a scrap of Ink Maw", "how": "hop", "icon": "slime0",
		"tip": "The small ones are quick but frail. One sweep clears them."},
	"brute": {"who": "a Bellringer", "how": "charge", "icon": "brute_wind",
		"tip": "The bell tolls before the charge. Put a wall behind you and step aside; strike it as it comes to stop it dead."},
	"wisp": {"who": "a Cinder Skull", "how": "burst", "icon": "wisp0",
		"tip": "Cinder Skulls burst when they reach you. Kill them at range with a bolt, or dash clear."},
	"fire": {"who": "spilled oil", "how": "flames", "icon": "oil",
		"tip": "Burning oil hurts whoever stands in it, Wren too. Throw the flask at them, and light it from afar with a bolt."},
	"warden": {"who": "Maren", "how": "glaive", "icon": "warden_strike",
		"tip": "She signals every blow. Watch her hands, not her eyes."},
}

## What Wren says on waking at the lamp, by what put her out. Each line is said
## the first time; after that a random one.
const WREN_WAKE := {
	"husk": ["Too close to a keeper. I know the wind-up now.", "They lean back before they lunge. I saw it too late."],
	"gloam": ["I let the lamp burn down. That's on me.", "The dark has teeth when the oil's gone. Noted."],
	"moth": ["Bats. Bats! Maren would laugh.", "Swing when they turn back. When they turn back."],
	"cantor": ["Their hexes come back if I hit them. I'll hit them.", "I stood still for a choir. Never again."],
	"slime": ["The ink splits. Back off when it bursts.", "Don't fight ink head-on. Noted."],
	"slimelet": ["Little pieces, big trouble.", "Sweep the scraps, don't chase them."],
	"brute": ["Bellringers again. I'll remember the bell this time.", "Wall at my back next time. Let it hit stone."],
	"wisp": ["Kill the skulls first. Always the skulls first.", "Should have dashed. Should have dashed."],
	"fire": ["My own fire. Throw it farther next time.", "Oil burns both ways. I knew that."],
	"warden": ["Maren. I'm not done. Neither are you.", "She's slower after the third swing. I think."],
}

## Said on waking as the deaths mount, in place of the line above.
const WREN_STUBBORN := {
	3: "Third time. The lamp still catches. So do I.",
	7: "Seven. Maren fell more than this. She said so.",
	12: "Twelve. Every one of them taught me something.",
	20: "Twenty. The dark isn't patient enough to outlast me.",
}


# --- Kindlings that combine ----------------------------------------------------

## Offered once Wren holds both of their kindlings. Each is a new effect, not
## just a bigger number.
const DUOS := [
	{"id": "wildfire", "needs": ["burn", "trail"], "name": "Wildfire",
		"desc": "DUO: Afterburn + Cinder Trail\nBurning foes set alight the foes beside them."},
	{"id": "starfall", "needs": ["twin", "pierce"], "name": "Starfall",
		"desc": "DUO: Forked Flame + Lance of Light\nAn ember bolt that strikes a foe breaks into two more."},
	{"id": "flashstep", "needs": ["blink", "sear"], "name": "Flashstep",
		"desc": "DUO: Double Step + Searing Dash\nDashing through a foe gives the dash straight back."},
	{"id": "chainburst", "needs": ["shatter", "burn"], "name": "Chain of Cinders",
		"desc": "DUO: Cinderburst + Afterburn\nWhat a burst scorches, it also sets alight."},
	{"id": "conflux", "needs": ["orbit", "focus"], "name": "Conflux",
		"desc": "DUO: Ember Motes + Maren's Notes\nTwo more motes, and every mote burns half again as hot."},
	{"id": "riposte", "needs": ["crit", "swift"], "name": "Riposte",
		"desc": "DUO: Keen Eye + Lamplighter's Stride\nA parry makes your next strike land twice as hard."},
]
const DUO_COL := Color(0.85, 0.6, 1.0)


# --- The town above ------------------------------------------------------------

## Lamps in the town, lit with embers brought home. Each lights for good and
## helps every descent after it.
const TOWN := [
	{"id": "tinker", "name": "The Tinker's Lamp", "cost": 40, "icon": "heart2",
		"desc": "The tinker patches your coat.\nStart with one more heart."},
	{"id": "oil", "name": "The Oilmonger's Lamp", "cost": 40, "icon": "oil",
		"desc": "A deeper flask, filled.\n+25 oil to start with."},
	{"id": "smith", "name": "The Smith's Lamp", "cost": 60, "icon": "i_sword",
		"desc": "The hook is ground keen.\n+10% strike damage."},
	{"id": "chandler", "name": "The Chandler's Lamp", "cost": 60, "icon": "i_flame",
		"desc": "Better oil, cleaner flame.\nEmber bolts cost 15 oil, not 18."},
	{"id": "physician", "name": "The Physician's Lamp", "cost": 70, "icon": "heart2",
		"desc": "Bandages in every pocket.\nFoes drop hearts more often."},
	{"id": "watch", "name": "The Watch Lamp", "cost": 100, "icon": "i_lamp",
		"desc": "The night watch lends a match.\nStart with the spare match."},
	{"id": "chapel", "name": "The Chapel Lamp", "cost": 120, "icon": "page",
		"desc": "The chapel keeps Maren's notes.\nChoose from four kindlings."},
	{"id": "belltower", "name": "The Bell Tower Lamp", "cost": 90, "icon": "i_eye",
		"desc": "The bell rings true.\nA fresh choice, once per depth."},
	{"id": "maren", "name": "Maren's Lamp", "cost": 200, "icon": "lamp1",
		"desc": "Her window, lit again.\nWayside lamps heal you fully."},
]


# --- The light dial ---------------------------------------------------------------

## The lamp's light tiers as the HUD names them (Game.light_tier: 0 to 3).
const LIGHT_TIERS := ["Bright", "Dim", "Shadowy", "Dark"]
## Wren, the first time on a descent her light falls to Dark.
const LIGHT_DARK_LINE := "This dark gives up what the light walks past. It'll want something back."


# --- Deeds ---------------------------------------------------------------------

## Milestones kept across every descent. Each pays embers once, when first done.
const FEATS := [
	{"id": "parry1", "name": "First Parry", "desc": "Turn a blow aside.", "stat": "parries", "goal": 1, "reward": 15},
	{"id": "parry50", "name": "Unbroken", "desc": "Parry fifty blows.", "stat": "parries", "goal": 50, "reward": 60},
	{"id": "reflect10", "name": "Return to Sender", "desc": "Strike ten hexes back.", "stat": "reflects", "goal": 10, "reward": 40},
	{"id": "kills300", "name": "Lamplighter's Round", "desc": "Put out three hundred foes.", "stat": "kills", "goal": 300, "reward": 60},
	{"id": "depth4", "name": "Halfway Down", "desc": "Reach the fourth depth.", "stat": "max_depth", "goal": 4, "reward": 40},
	{"id": "warden", "name": "The Hollow Warden", "desc": "Bring Maren down.", "stat": "wardens", "goal": 1, "reward": 120},
	{"id": "duo", "name": "Kindred Flames", "desc": "Take a kindling that combines two.", "stat": "duos", "goal": 1, "reward": 30},
	{"id": "stubborn", "name": "Stubborn", "desc": "Wake at the lamp ten times.", "stat": "deaths", "goal": 10, "reward": 30},
	{"id": "grudge", "name": "Grudge Settled", "desc": "Put out the foe that named itself on you.", "stat": "nemeses", "goal": 1, "reward": 50},
	{"id": "ignite", "name": "Oil and Ember", "desc": "Set twenty pools of oil alight.", "stat": "ignites", "goal": 20, "reward": 30},
	{"id": "ambush", "name": "Out of the Dark", "desc": "Strike ten foes that lost you in the dark.", "stat": "ambushes", "goal": 10, "reward": 30},
	{"id": "echo", "name": "Twice Over", "desc": "Land fifty blows with your echo.", "stat": "echo_hits", "goal": 50, "reward": 30},
	{"id": "flit", "name": "A Friend in the Dark", "desc": "Feed a lamp moth, and keep it.", "stat": "flits", "goal": 1, "reward": 20},
	{"id": "hollow", "name": "Hollow Walls", "desc": "Break into three hidden rooms.", "stat": "secrets", "goal": 3, "reward": 40},
	{"id": "lamps", "name": "The Street Remembers", "desc": "Light every lamp in town.", "stat": "town", "goal": 9, "reward": 0},
	{"id": "descent4", "name": "No Way Back", "desc": "Reach the fourth depth on one wick.", "stat": "descent_depth", "goal": 4, "reward": 60},
	{"id": "descent_win", "name": "One Wick", "desc": "Finish a Descent.", "stat": "descent_wins", "goal": 1, "reward": 250},
]


# --- Ways down -------------------------------------------------------------------

## The two ways to go down, chosen when a slot is started. A Pilgrimage wakes
## at the last lit lamp; a Descent has one wick, and a fall ends it.
const MODES := {
	"pilgrim": {"name": "Pilgrimage", "badge": "PILGRIMAGE", "icon": "lamp1", "col": Color(0.6, 0.9, 0.94),
		"desc": "Every lamp you light keeps you.\n\nFall, and you wake beside the last one with everything you carried."},
	"descent": {"name": "Descent", "badge": "DESCENT  -  ONE WICK", "icon": "i_flame", "col": Color(1.0, 0.45, 0.35),
		"desc": "One wick, all the way down.\n\nFall, and all you carried is lost. Embers burn half again as bright."},
}

## Said on the death screen when a Descent ends, under the tally.
const DESCENT_END := [
	"\"Nobody goes down twice the same way. Go down again.\"  - Maren",
	"\"The wick's spent. The lamp isn't.\"  - Maren",
	"\"Count what you learned, not what you lost.\"  - Maren",
]
