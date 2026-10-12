extends RefCounted
## The one that put Wren out. The first foe to do it is given a name and
## keeps it: it wears a scrap of her cloak, it waits for her on a later
## descent, and every time it puts her out again it grows. Putting it out
## pays well, and gives her the scrap back.

## Kinds that can hold a grudge. A Cinder Skull bursts and is gone; a gloam is
## only the dark; Maren is already someone.
const KINDS := ["husk", "moth", "cantor", "brute", "slime", "slimelet"]
const HEAD := ["Gr", "Sk", "Vor", "Mal", "Thr", "Kr", "Ul", "Dre", "Bal", "Sn", "Mor", "Hask", "Gl", "Ost"]
const TAIL := ["isk", "ag", "ulch", "ore", "ith", "ax", "em", "ugg", "och", "ane", "irr", "olt", "ub", "ock"]
const EPITHET := {
	"husk": "the Hollow", "moth": "the Fluttering", "cantor": "Who Sings Wrong", "brute": "Bell-Breaker",
	"slime": "the Spilt", "slimelet": "the Spilt",
}
## By rank: what the dark calls it after each time it puts her out.
const RANK := ["", "Who Put Out the Lamplighter", "Twice-Fed", "Wren's Bane", "the Dark's Favourite"]
const TAUNTS := [
	"\"Lamplighter. I kept your scrap of cloak.\"",
	"\"Back again? I hoped you'd come.\"",
	"\"Your light tastes better the second time.\"",
	"\"I told the others about you. They laughed.\"",
	"\"Mind your wick, little lamp.\"",
]
const SLAIN := [
	"My cloak. I'll be having that back.",
	"Remember that, wherever things like you go.",
	"Grudge settled. Lamp's still lit.",
]


static func make_name(rng: RandomNumberGenerator) -> String:
	return HEAD[rng.randi() % HEAD.size()] + TAIL[rng.randi() % TAIL.size()]


## "Grisk the Hollow"; with its title, "Grisk the Hollow, Twice-Fed".
static func full_name(n: Dictionary, with_rank: bool = false) -> String:
	var s := "%s %s" % [n["name"], EPITHET.get(n["kind"], "")]
	if with_rank:
		s += ", " + RANK[clampi(int(n["rank"]), 1, RANK.size() - 1)]
	return s


## Wren has just been put out. Returns a line for the death screen, or "".
static func on_death(main, kind: String, by_nemesis: bool, rng: RandomNumberGenerator) -> String:
	var n: Dictionary = main.profile["nemesis"]
	if by_nemesis and not n.is_empty():
		n["rank"] = mini(int(n["rank"]) + 1, RANK.size() - 1)
		n["wins"] = int(n.get("wins", 1)) + 1
		main.nem_due = true
		return "%s laughs. It grows. Now: %s." % [n["name"], RANK[int(n["rank"])]]
	if n.is_empty() and KINDS.has(kind):
		var k := "slime" if kind == "slimelet" else kind
		main.profile["nemesis"] = {"kind": k, "name": make_name(rng), "rank": 1, "wins": 1}
		main.nem_due = true
		return "It will remember you. The dark calls it %s now." % full_name(main.profile["nemesis"])
	return ""
