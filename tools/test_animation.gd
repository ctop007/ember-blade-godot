extends SceneTree
var failed := false
func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001
func _init() -> void:
	var r := RigPlayer.new()
	root.add_child(r)
	var def := RigFixture.definition()
	var clips := RigFixture.clips()
	clips["test"] = {"duration": 1.0, "loop": true, "bones": {"chest": [
		{"t": 0, "rot": 0}, {"t": 0.2, "x": 5}, {"t": 1, "rot": 100, "ease": "quadIn"}]},
		"slots": {"torso": [{"t": 0.5, "image": "changed", "alpha": 0.4, "z": 30}]},
		"events": [{"t": 0, "name": "start"}, {"t": 0.5, "name": "middle"}]}
	r.configure(def, clips, "", true)
	var events: Array = []
	r.event_fired.connect(func(e): events.append(e.name))
	r.play("test")
	r.advance(0.5)
	check(near(r.pose.chest.rot, 25), "per-property interpolation must ignore x-only key and use target quadIn")
	check(near(r.pose.chest.y, -35), "missing property must retain setup pose")
	check(r.pose["slot:torso"].image == "changed" and r.pose["slot:torso"].z == 30, "discrete image/z keys")
	check(events == ["start", "middle"], "events once, including time zero")
	r.advance(0.5)
	check(events == ["start", "middle", "start"], "loop event boundary")
	r.play("attack1", 0.8, 0.24)
	check(near(r.source_time(0.12), 0.06) and near(r.source_time(0.24), 0.12) and near(r.source_time(0.8), 0.4), "phase remap windup/active/recovery")
	r.advance(0.24)
	check(near(r.pose.spear.rot, 55), "relative rotation adds setup -20")
	var snap := r.pose.duplicate(true)
	var springs := r.spring_state.duplicate(true)
	r.advance(0)
	check(r.pose == snap and r.spring_state == springs, "hitstop freezes pose and springs")
	r.play("idle", -1, -1, 0.12)
	check(near(r.pose.spear.rot, snap.spear.rot), "crossfade begins at previous pose")
	r.advance(0.06)
	check(r.pose.spear.rot < float(snap.spear.rot) and r.pose.spear.rot > -20, "crossfade intermediate pose")
	def.keyMode = "absolute"
	r.configure(def, clips, "", true)
	r.play("attack1", 0.4, 0.12, 0.06, true)
	r.advance(0.12)
	check(near(r.pose.spear.rot, 75), "absolute key mode")
	for ease in ["linear", "quadIn", "quadOut", "quadInOut", "cubicIn", "cubicOut", "expoOut", "backOut", "sineInOut", "step"]:
		check(near(Ease.apply(ease, 0), 0) and near(Ease.apply(ease, 1), 1), "ease endpoints: " + ease)
	for i in 60:
		r.advance(1.0 / 60)
	check(r.socket("spearTip").is_finite(), "spring and socket stay finite")
	for kind in ["hero", "imp", "lantern", "brute", "boss"]:
		var dir: String = "res://rigs/" + String(kind)
		var rdef: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "/rig.json"))
		var rclips: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "/anims.json"))
		r.configure(rdef, rclips, dir, false)
		for cname in rclips.keys():
			r.play(String(cname), -1, -1, 0.08, true)
			r.advance(0.1)
			for sname in rdef.get("sockets", {}).keys():
				check(r.socket(String(sname)).is_finite(), "%s.%s socket %s finite" % [kind, cname, sname])
	r.queue_free()
	_test_core()
	print("ANIMATION_TEST_OK" if not failed else "ANIMATION_TEST_FAILED")
	quit(1 if failed else 0)

func _test_core() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/game.json"))
	var g := CoreGame.new(cfg, 123)
	var p = g.player
	g.phase = "benchmark"
	g.enemies.clear()
	var ctl = g.pctl
	ctl.update(0.01, {"attack_pressed": true})
	ctl.update(0.01, {"attack_pressed": true})
	for i in 20:
		ctl.update(0.01, {})
	check(p.combo_step == 1, "combo cancels recovery before original duration")
	ctl.update(0.01, {"dodge_pressed": true})
	check(p.state == "dodge", "dodge cancels attack")
	p.state = "hurt"
	p.state_t = 0.20
	p.state_dur = 0.25
	ctl.update(0.01, {"attack_pressed": true})
	for i in 7:
		ctl.update(0.01, {})
	check(p.state == "attack", "buffered press fires after hurt ends")
	p.state = "hurt"
	p.state_t = 0
	p.state_dur = 0.5
	p.buf.clear()
	ctl.update(0.01, {"attack_pressed": true})
	for i in 55:
		ctl.update(0.01, {})
	check(p.state == "idle", "expired buffer does not execute")
	check(near(Ease.delta("quadOut", 0, 1), 1), "displacement integral preserves total distance")
	g.dispose()
