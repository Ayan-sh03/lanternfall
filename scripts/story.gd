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
	{"id": "focus", "name": "Maren's Notes", "desc": "Flare Nova, Storm Spark and Hearth Ward hit 30% harder and return sooner.", "col": Color(0.7, 0.85, 1.0)},
]

const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII"]
