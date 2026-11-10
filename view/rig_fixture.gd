class_name RigFixture
extends RefCounted
## Local square-part rig: deliberately uses no shared art or shared rig files.
static func definition() -> Dictionary:
	return {"version": 1, "displayScale": 1, "bones": [
		{"name": "root", "parent": null}, {"name": "hip", "parent": "root", "y": -45},
		{"name": "chest", "parent": "hip", "y": -35}, {"name": "head", "parent": "chest", "y": -30},
		{"name": "spear", "parent": "chest", "x": 15, "rot": -20},
		{"name": "hair1", "parent": "head", "x": -10, "y": 8},
		{"name": "hair2", "parent": "hair1", "y": 24, "length": 24},
		{"name": "legL", "parent": "hip", "x": -12, "y": 25, "rot": 90},
		{"name": "legR", "parent": "hip", "x": 12, "y": 25, "rot": 90}],
		"slots": [
		{"name": "torso", "bone": "chest", "image": "block", "z": 10},
		{"name": "head", "bone": "head", "image": "block", "z": 11},
		{"name": "spear", "bone": "spear", "image": "block", "pivot": [0, 0.5], "z": 12},
		{"name": "hair1", "bone": "hair1", "image": "block", "z": 8},
		{"name": "hair2", "bone": "hair2", "image": "block", "z": 9},
		{"name": "legL", "bone": "legL", "image": "block", "z": 6},
		{"name": "legR", "bone": "legR", "image": "block", "z": 7}],
		"springs": [{"bones": ["hair1", "hair2"], "stiffness": 120, "damping": 12, "gravity": 20}],
		"sockets": {"spearTip": {"bone": "spear", "x": 110, "y": 0}}}

static func clips() -> Dictionary:
	var a := {}
	for name in ["idle", "run", "charge", "thrust", "dodge", "jump_up", "jump_fall", "slam", "land", "hurt", "dead", "cast_crescent", "cast_skyfall", "cast_meteor", "ult", "victory"]:
		a[name] = {"duration": 0.6, "loop": name in ["idle", "run", "charge"], "bones": {
			"chest": [{"t": 0, "rot": -8}, {"t": 0.3, "rot": 8, "sy": 1.02, "ease": "sineInOut"}, {"t": 0.6, "rot": -8, "sy": 1.0}],
			"legL": [{"t": 0, "rot": -20}, {"t": 0.3, "rot": 20}, {"t": 0.6, "rot": -20}]}}
	for i in 3:
		a["attack%d" % (i + 1)] = {"duration": 0.4, "loop": false,
			"phases": {"windup": 0.06, "active": 0.12, "recovery": 0.4},
			"bones": {"spear": [{"t": 0, "rot": 0}, {"t": 0.06, "rot": -100, "ease": "quadOut"}, {"t": 0.12, "rot": 75, "ease": "expoOut"}, {"t": 0.4, "rot": 0, "ease": "sineInOut"}],
			"chest": [{"t": 0, "x": -5}, {"t": 0.12, "x": 12}, {"t": 0.4, "x": 0}]},
			"slots": {"spear": [{"t": 0.06, "image": "smear", "z": 20}, {"t": 0.16, "image": "block", "z": 12}]},
			"events": [{"t": 0.04, "name": "trail_on"}, {"t": 0.12, "name": "hit"}, {"t": 0.18, "name": "trail_off"}]}
	return a
