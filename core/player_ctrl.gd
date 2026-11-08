extends RefCounted
## Player state machine. Pure logic; reads input dict, mutates g.player, emits events via g.

var g
var p
var c: Dictionary

func _init(game) -> void:
	g = game
	p = game.player
	c = game.cfg

# ---------------------------------------------------------------- entry
func update(dt: float, inp: Dictionary) -> void:
	p.state_t += dt
	p.iframe = maxf(0.0, p.iframe - dt)
	p.flash = maxf(0.0, p.flash - dt)
	p.dodge_cd = maxf(0.0, p.dodge_cd - dt)
	p.chain_t = maxf(0.0, p.chain_t - dt)
	for k in p.cds.keys():
		p.cds[k] = maxf(0.0, float(p.cds[k]) - dt)
	p.mp = minf(p.max_mp, p.mp + float(c.player.mpRegen) * (1.0 + float(g.mods.mpRegenMul)) * dt)
	if p.state == "dead":
		return
	_track_hold(dt, inp)
	_handle_actions(inp)
	match p.state:
		"idle", "run":
			_locomotion(dt, inp, 1.0)
		"attack":
			_st_attack(dt, inp)
		"charge":
			_locomotion(dt, inp, 0.35, false)
			if not p.holding:
				_to_idle()
		"thrust":
			_st_thrust(dt)
		"thrust_end", "slam_end":
			if p.state_t >= p.state_dur:
				_to_idle()
		"dodge":
			_st_dodge(dt)
		"jump":
			_st_jump(dt, inp)
		"slam":
			_st_slam(dt)
		"cast":
			_st_cast(dt, inp)
		"hurt":
			_st_hurt(dt)
	_apply_kb(dt)
	_clamp()

func update_frozen(dt: float, inp: Dictionary) -> void:
	p.flash = maxf(0.0, p.flash - dt)
	if p.state == "ult":
		_st_ult(dt)
	_track_hold(dt, {"attack_held": false})

# ---------------------------------------------------------------- input / actions
func _track_hold(dt: float, inp: Dictionary) -> void:
	var held: bool = inp.get("attack_held", false)
	if p.holding:
		if held:
			p.hold_t += dt
			if not p.charged and p.hold_t >= float(c.attack.chargeTime) and _grounded_state():
				p.charged = true
				g.emit("charge_ready", {"x": p.x, "y": p.y})
		else:
			p.holding = false
			if p.charged:
				p.charged = false
				if p.state in ["attack", "charge", "idle", "run"]:
					_start_thrust()

func _grounded_state() -> bool:
	return p.state in ["idle", "run", "attack", "charge"]

func _handle_actions(inp: Dictionary) -> void:
	if inp.get("ult_pressed", false):
		try_ult()
	if inp.get("dodge_pressed", false):
		try_dodge(inp)
	if inp.get("jump_pressed", false) and p.state in ["idle", "run", "attack", "charge"]:
		p.state = "jump"
		p.state_t = 0.0
		p.vz = float(c.jump.velocity)
		p.air_attacked = false
		p.holding = false
		p.charged = false
		g.emit("jump", {"x": p.x, "y": p.y})
	for i in 3:
		if inp.get("skill%d_pressed" % (i + 1), false):
			try_skill(["crescent", "skyfall", "meteorSpear"][i])
	if inp.get("attack_pressed", false):
		_on_attack_pressed(inp)

func _on_attack_pressed(inp: Dictionary) -> void:
	if p.state == "jump":
		if not p.air_attacked:
			p.air_attacked = true
			p.state = "slam"
			p.state_t = 0.0
			p.vz = -float(c.jump.slamVelocity)
			g.emit("slam_start", {"x": p.x, "y": p.y, "z": p.z})
		return
	if p.state in ["idle", "run"]:
		p.holding = true
		p.hold_t = 0.0
		var nxt: int = (p.combo_step + 1) % 3 if p.chain_t > 0.0 else 0
		_start_attack(nxt, inp)
	elif p.state == "attack":
		p.buffered = true
		p.holding = true
		p.hold_t = 0.0

func _start_attack(step: int, inp: Dictionary) -> void:
	_auto_face(inp)
	p.state = "attack"
	p.state_t = 0.0
	p.combo_step = step
	p.state_dur = float(c.attack.steps[step].duration)
	p.hit_done = false
	p.buffered = false
	p.chain_t = 0.0
	g.emit("swing", {"step": step, "x": p.x, "y": p.y, "facing": p.facing})

func _auto_face(inp: Dictionary) -> void:
	var mx: float = inp.get("mx", 0.0)
	if absf(mx) > 0.2:
		p.facing = 1 if mx > 0.0 else -1
		return
	var best = null
	var bd := 300.0
	for e in g.enemies:
		if e.state == "dead" or e.state == "spawn":
			continue
		var d: float = g.ground_dist(p.x, p.y, e.x, e.y)
		if d < bd:
			bd = d
			best = e
	if best != null and absf(best.x - p.x) > 8.0:
		p.facing = 1 if best.x > p.x else -1

# ---------------------------------------------------------------- locomotion
func _locomotion(dt: float, inp: Dictionary, mul: float, turn := true) -> void:
	var mx: float = inp.get("mx", 0.0)
	var my: float = inp.get("my", 0.0)
	var mag := sqrt(mx * mx + my * my)
	p.moving = mag > 0.05
	if p.moving:
		var sp := float(c.player.moveSpeed) * mul
		p.x += mx * sp * dt
		p.y += my * sp * float(c.player.moveSpeedYScale) * dt
		if turn and absf(mx) > 0.1:
			p.facing = 1 if mx > 0.0 else -1
	if p.state in ["idle", "run"]:
		var ns := "run" if p.moving else "idle"
		if ns != p.state:
			p.state = ns
			p.state_t = 0.0

func _to_idle() -> void:
	p.state = "idle"
	p.state_t = 0.0

func _apply_kb(dt: float) -> void:
	if absf(p.kb_x) > 1.0 or absf(p.kb_y) > 1.0:
		p.x += p.kb_x * dt
		p.y += p.kb_y * dt
		var k := exp(-10.0 * dt)
		p.kb_x *= k
		p.kb_y *= k

func _clamp() -> void:
	var pad := float(c.world.edgePadding)
	p.x = clampf(p.x, g.bound_l + pad, g.bound_r - pad)
	p.y = g.clamp_ground_y(p.y)

# ---------------------------------------------------------------- attack
func _st_attack(dt: float, inp: Dictionary) -> void:
	var st: Dictionary = c.attack.steps[p.combo_step]
	var dur: float = p.state_dur
	var lunge_t := dur * 0.4
	if p.state_t <= lunge_t:
		p.x += p.facing * float(st.lunge) / lunge_t * dt
	_locomotion(dt, inp, float(c.attack.moveWhileAttackingScale), false)
	if not p.hit_done and p.state_t >= float(st.hitAt):
		p.hit_done = true
		var targets: Array = g.enemies_in_box(p.x, p.y, p.facing, float(st.range), float(st.width))
		for e in targets:
			g.damage_enemy(e, float(st.damage), {"src": "atk%d" % (p.combo_step + 1), "knockback": float(st.knockback)})
	if p.state_t >= dur:
		if p.buffered:
			_start_attack((p.combo_step + 1) % 3, inp)
		elif p.holding:
			p.state = "charge"
			p.state_t = 0.0
			p.chain_t = float(c.attack.comboWindow)
		else:
			_to_idle()
			p.chain_t = float(c.attack.comboWindow) if p.combo_step < 2 else 0.0
			if p.combo_step >= 2:
				p.combo_step = 2  # next press restarts at step 0 because chain_t is 0

func _start_thrust() -> void:
	var t: Dictionary = c.attack.chargedThrust
	p.state = "thrust"
	p.state_t = 0.0
	p.state_dur = float(t.duration)
	p.thrust_from = p.x
	p.thrust_hit = {}
	p.iframe = maxf(p.iframe, float(t.duration))
	p.chain_t = 0.0
	g.emit("thrust", {"x": p.x, "y": p.y, "facing": p.facing, "distance": float(t.distance), "dur": float(t.duration)})

func _st_thrust(dt: float) -> void:
	var t: Dictionary = c.attack.chargedThrust
	var spd := float(t.distance) / float(t.duration)
	p.x += p.facing * spd * dt
	_clamp()
	var lo := minf(p.thrust_from, p.x) - 30.0
	var hi := maxf(p.thrust_from, p.x) + 30.0
	if p.facing > 0:
		hi += 60.0
	else:
		lo -= 60.0
	for e in g.enemies:
		if e.state == "dead" or e.state == "spawn" or p.thrust_hit.has(e.id):
			continue
		if e.x < lo or e.x > hi or absf(e.y - p.y) > float(c.combat.depthTolerance) + float(t.width) * 0.3:
			continue
		p.thrust_hit[e.id] = true
		g.damage_enemy(e, float(t.damage), {"src": "thrust", "knockback": float(t.knockback)})
	if p.state_t >= p.state_dur:
		p.state = "thrust_end"
		p.state_t = 0.0
		p.state_dur = float(t.recovery)
		g.emit("thrust_end", {"x": p.x, "y": p.y, "from": p.thrust_from})

# ---------------------------------------------------------------- dodge
func try_dodge(inp: Dictionary) -> bool:
	if p.dodge_cd > 0.0 or not (p.state in ["idle", "run", "attack", "charge", "thrust_end", "slam_end"]):
		return false
	var mx: float = inp.get("mx", 0.0)
	var my: float = inp.get("my", 0.0)
	var v := Vector2(mx, my)
	if v.length() < 0.2:
		v = Vector2(p.facing, 0)
	v = v.normalized()
	if absf(v.x) > 0.1:
		p.facing = 1 if v.x > 0.0 else -1
	var d: Dictionary = c.dodge
	p.state = "dodge"
	p.state_t = 0.0
	p.state_dur = float(d.duration)
	p.dodge_dx = v.x
	p.dodge_dy = v.y
	p.dodge_from = Vector2(p.x, p.y)
	p.iframe = maxf(p.iframe, float(d.iframe))
	p.dodge_cd = float(d.cooldown)
	p.holding = false
	p.charged = false
	p.buffered = false
	p.flame_drop = 0.0
	if g.mods.dodgeCrit:
		p.dodge_crit_ready = true
	g.emit("dodge", {"x": p.x, "y": p.y, "dx": v.x, "dy": v.y, "facing": p.facing})
	return true

func _st_dodge(dt: float) -> void:
	var d: Dictionary = c.dodge
	var k0 := _ease_out(clampf((p.state_t - dt) / p.state_dur, 0.0, 1.0))
	var k1 := _ease_out(clampf(p.state_t / p.state_dur, 0.0, 1.0))
	var dist := float(d.distance) * (k1 - k0)
	p.x += p.dodge_dx * dist
	p.y += p.dodge_dy * dist * float(c.player.moveSpeedYScale)
	if g.mods.dodgeFlame:
		p.flame_drop -= dist
		if p.flame_drop <= 0.0:
			p.flame_drop = float(c.dodgeFlame.spacing)
			var h = g.add_hazard("flame", p.x, p.y, float(c.dodgeFlame.life))
			h.radius = float(c.dodgeFlame.radius)
			h.damage = float(c.dodgeFlame.damage)
	if p.state_t >= p.state_dur:
		_to_idle()

func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)

# ---------------------------------------------------------------- jump / slam
func _st_jump(dt: float, inp: Dictionary) -> void:
	p.vz -= float(c.world.gravity) * dt
	p.z += p.vz * dt
	_locomotion(dt, inp, float(c.jump.airControl))
	if p.z <= 0.0:
		p.z = 0.0
		p.vz = 0.0
		g.emit("land", {"x": p.x, "y": p.y})
		_to_idle()

func _st_slam(dt: float) -> void:
	p.z += p.vz * dt
	if p.z <= 0.0:
		p.z = 0.0
		p.vz = 0.0
		var j: Dictionary = c.jump
		g.emit("slam_land", {"x": p.x, "y": p.y, "r": float(j.slamRadius)})
		for e in g.enemies_in_radius(p.x, p.y, float(j.slamRadius)):
			g.damage_enemy(e, float(j.slamDamage), {"src": "slam", "knockback": float(j.slamKnockback), "launch": 260.0, "no_hitstop": true})
		g.hitstop = maxf(g.hitstop, float(c.combat.hitstopMax))
		p.state = "slam_end"
		p.state_t = 0.0
		p.state_dur = float(j.landRecovery)

# ---------------------------------------------------------------- skills
func try_skill(name: String, force := false) -> bool:
	var s: Dictionary = c.skills[name]
	if not force:
		if not (p.state in ["idle", "run", "attack", "charge", "thrust_end", "slam_end"]):
			return false
		if float(p.cds[name]) > 0.0:
			g.emit("skill_fail", {"skill": name, "why": "cd"})
			return false
		if p.mp < float(s.mp):
			g.emit("skill_fail", {"skill": name, "why": "mp"})
			return false
		p.mp -= float(s.mp)
	p.cds[name] = float(s.cooldown) * g.cd_mul()
	p.holding = false
	p.charged = false
	p.buffered = false
	p.state = "cast"
	p.state_t = 0.0
	p.cast_skill = name
	p.cast_data = {"n": 0}
	match name:
		"crescent":
			var spins := int(s.spins) + int(g.mods.crescentSpins)
			p.cast_data["spins"] = spins
			p.state_dur = float(s.spinDuration) * spins
			g.emit("crescent", {"x": p.x, "y": p.y, "spins": spins, "spin_dur": float(s.spinDuration), "r": float(s.radius)})
		"skyfall":
			p.state_dur = 0.32
			var r := float(s.radius) * (1.0 + float(g.mods.skyfallRadiusMul))
			var tx := clampf(p.x + p.facing * float(s.offset), g.bound_l + 40.0, g.bound_r - 40.0)
			var h = g.add_hazard("skyfall", tx, p.y, float(s.delay) + 0.5,
				{"delay": float(s.delay), "knockback": float(s.knockback), "launch": float(s.launch), "r": r})
			h.radius = r
			h.damage = float(s.damage) * (1.0 + float(g.mods.skyfallDamageMul))
			g.emit("skyfall_cast", {"x": tx, "y": p.y, "r": r, "delay": float(s.delay), "px": p.x})
		"meteorSpear":
			p.state_dur = 0.3
			g.emit("spear_cast", {"x": p.x, "y": p.y, "facing": p.facing})
	return true

func _st_cast(dt: float, inp: Dictionary) -> void:
	var name: String = p.cast_skill
	match name:
		"crescent":
			var s: Dictionary = c.skills.crescent
			_locomotion(dt, inp, 0.45, false)
			var sd := float(s.spinDuration)
			var n: int = p.cast_data.n
			if n < int(p.cast_data.spins) and p.state_t >= sd * (n + 0.5):
				p.cast_data.n = n + 1
				for e in g.enemies_in_radius(p.x, p.y, float(s.radius)):
					g.damage_enemy(e, float(s.damagePerSpin), {"src": "crescent", "knockback": float(s.knockback), "no_hitstop": n > 0})
				g.emit("crescent_tick", {"x": p.x, "y": p.y, "n": n})
		"meteorSpear":
			if p.cast_data.n == 0 and p.state_t >= 0.12:
				p.cast_data.n = 1
				_throw_spears()
	if p.state_t >= p.state_dur:
		_to_idle()

func _throw_spears() -> void:
	var s: Dictionary = c.skills.meteorSpear
	var dirs: Array = [Vector2(p.facing, 0)]
	if g.mods.spearSplit:
		var sp := float(s.splitSpread) / float(s.range)
		dirs = [Vector2(p.facing, 0), Vector2(p.facing, -sp).normalized(), Vector2(p.facing, sp).normalized()]
	for d in dirs:
		var sx: float = p.x + p.facing * 40.0
		var h = g.add_hazard("spear", sx, p.y, 2.0, {"speed": float(s.speed), "range": float(s.range),
			"width": float(s.width), "knockback": float(s.knockback), "emberInterval": float(s.emberInterval),
			"emberLife": float(s.emberLife), "dx": d.x, "dy": d.y})
		h.vx = d.x
		h.vy = d.y
		h.damage = float(s.damage)
	g.emit("spear_throw", {"x": p.x, "y": p.y, "facing": p.facing, "n": dirs.size()})

# ---------------------------------------------------------------- ultimate
func try_ult(force := false) -> bool:
	var u: Dictionary = c.skills.ultimate
	if p.state in ["dead", "ult"] or g.freeze > 0.0:
		return false
	if not force and p.rage < float(u.rage):
		g.emit("skill_fail", {"skill": "ultimate", "why": "rage"})
		return false
	p.rage = 0.0
	p.state = "ult"
	p.state_t = 0.0
	p.z = 0.0
	p.vz = 0.0
	p.holding = false
	p.charged = false
	var strikes := int(u.strikes)
	p.state_dur = float(u.cutinTime) + float(u.strikeInterval) * strikes + 0.55
	p.cast_data = {"n": 0}
	g.freeze = p.state_dur
	g.emit("ult_start", {"x": p.x, "y": p.y, "dur": p.state_dur, "cutin": float(u.cutinTime)})
	return true

func _st_ult(dt: float) -> void:
	p.state_t += dt
	var u: Dictionary = c.skills.ultimate
	var strikes := int(u.strikes)
	var n: int = p.cast_data.n
	var t0 := float(u.cutinTime)
	if n < strikes and p.state_t >= t0 + float(u.strikeInterval) * n:
		p.cast_data.n = n + 1
		var per := float(u.totalDamage) / float(strikes)
		var targets: Array = []
		for e in g.enemies:
			if e.state != "dead" and e.state != "spawn" and absf(e.x - p.x) < 900.0:
				targets.append(e)
		var pts: Array = []
		for e in targets:
			if pts.size() < 8:
				pts.append([e.x + g.rng.range_f(-30, 30), e.y + g.rng.range_f(-12, 12)])
		while pts.size() < 3:
			pts.append([p.x + g.rng.range_f(-560, 560), g.rng.range_f(float(c.world.groundTop), float(c.world.groundBottom))])
		g.emit("ult_strike", {"n": n, "points": pts, "last": n == strikes - 1})
		for e in targets:
			g.damage_enemy(e, per, {"src": "ult", "knockback": 20.0, "nocrit": true, "no_hitstop": true, "ult": true, "from_x": e.x - 1.0})
	if p.state_t >= p.state_dur:
		g.freeze = 0.0
		g.emit("ult_end", {})
		_to_idle()

# ---------------------------------------------------------------- hurt
func take_hit(dmg: float, from_x: float, src: String) -> bool:
	if p.state == "dead" or g.god or p.iframe > 0.0 or p.state in ["dodge", "thrust"]:
		if p.state == "dodge":
			g.emit("dodge_perfect", {"x": p.x, "y": p.y})
		return false
	p.hp = maxf(0.0, p.hp - dmg)
	# super armor while casting skills / ult (same rule as Cocos): take damage, never interrupted
	var armor: bool = p.state in ["cast", "ult"]
	p.flash = float(c.combat.hitFlash)
	p.iframe = float(c.combat.playerHurtIframe)
	if armor and p.hp > 0.0:
		g.emit("player_hit", {"dmg": dmg, "x": p.x, "y": p.y, "src": src, "armor": true})
		return true
	var dir := 1.0 if p.x >= from_x else -1.0
	p.kb_x = dir * float(c.combat.playerKnockback) * 6.0
	p.holding = false
	p.charged = false
	p.buffered = false
	p.chain_t = 0.0
	g.emit("player_hit", {"dmg": dmg, "x": p.x, "y": p.y, "src": src})
	if p.hp <= 0.0:
		p.state = "dead"
		p.state_t = 0.0
		g.emit("player_dead", {"x": p.x, "y": p.y})
	else:
		p.state = "hurt"
		p.state_t = 0.0
		p.state_dur = float(c.combat.playerHurtStun)
	return true

func _st_hurt(dt: float) -> void:
	if p.z > 0.0:
		p.vz -= float(c.world.gravity) * dt
		p.z = maxf(0.0, p.z + p.vz * dt)
	if p.state_t >= p.state_dur and p.z <= 0.0:
		_to_idle()
