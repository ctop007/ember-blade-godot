class_name Bot
extends RefCounted
## Simple scripted player used by tools/sim.gd and --autoplay. Produces core input dicts.
var held := false
var dodge_wish := false

func think(g: CoreGame) -> Dictionary:
	var inp := {"mx": 0.0, "my": 0.0, "attack_held": false}
	var p = g.player
	for ev in g.events:
		if ev.type == "telegraph" and absf(float(ev.x) - p.x) < 260.0:
			dodge_wish = true
	var target = null
	var bd := INF
	for e in g.enemies:
		if e.state == "dead" or e.state == "spawn":
			continue
		var d: float = g.ground_dist(p.x, p.y, e.x, e.y)
		if d < bd:
			bd = d
			target = e
	if target == null:
		inp.mx = 1.0
		return inp
	var dx: float = target.x - p.x
	var dy: float = target.y - p.y
	if absf(dx) > 90.0 or absf(dy) > 20.0:
		inp.mx = clampf(dx / 100.0, -1.0, 1.0)
		inp.my = clampf(dy / 40.0, -1.0, 1.0)
	else:
		inp.mx = 0.01 * signf(dx)
	if bd < 160.0:
		if not held:
			inp["attack_pressed"] = true
		held = not held
		inp.attack_held = held
		if p.mp > 40.0 and bd < 140.0:
			inp["skill1_pressed"] = true
		if p.mp > 60.0:
			inp["skill2_pressed"] = true
		if p.mp > 80.0:
			inp["skill3_pressed"] = true
		if p.rage >= 100.0:
			inp["ult_pressed"] = true
	if dodge_wish:
		inp["dodge_pressed"] = true
		dodge_wish = false
	return inp
