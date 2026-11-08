extends RefCounted
## Enemy decisions + movement. Pure logic.

var g
var c: Dictionary
var token_t := 0.0

func _init(game) -> void:
	g = game
	c = game.cfg

func kill(e) -> void:
	if e.token:
		e.token = false
	e.state = "dead"
	e.state_t = 0.0
	e.dead_t = 0.0
	g.emit("enemy_dead", {"id": e.id, "enemy": e.type, "x": e.x, "y": e.y})
	if e.type == "boss":
		for o in g.enemies:
			if o != e and o.state != "dead":
				o.hp = 0.0
				kill(o)

func hurt(e, stun: float) -> void:
	if e.state in ["windup", "attack"]:
		g.emit("telegraph_cancel", {"id": e.id})
	e.state = "hurt"
	e.state_t = 0.0
	e.stun = stun
	if e.token and e.type == "imp":
		e.token = false
		e.cooldown = maxf(e.cooldown, 0.5)

# ---------------------------------------------------------------- update
func update(dt: float) -> void:
	var p = g.player
	token_t -= dt
	if token_t <= 0.0:
		token_t = float(c.ai.thinkInterval)
		_assign_tokens()
	for e in g.enemies:
		e.state_t += dt
		e.flash = maxf(0.0, e.flash - dt)
		if e.state == "dead":
			e.dead_t += dt
			_physics(e, dt)
			continue
		e.cooldown = maxf(0.0, e.cooldown - dt)
		if e.state == "spawn":
			if e.state_t >= e.state_dur:
				e.state = "idle" if e.type == "boss" else "move"
				e.state_t = 0.0
			continue
		if e.state == "hurt":
			_physics(e, dt)
			if e.state_t >= e.stun and e.z <= 0.0:
				e.state = "move" if e.type != "boss" else "idle"
				e.state_t = 0.0
			continue
		match e.type:
			"imp":
				_imp(e, dt, p)
			"lantern":
				_lantern(e, dt, p)
			"brute":
				_brute(e, dt, p)
			"boss":
				_boss(e, dt, p)
		_physics(e, dt)
	_separate(dt)

func _physics(e, dt: float) -> void:
	if absf(e.kb_x) > 1.0 or absf(e.kb_y) > 1.0:
		e.x += e.kb_x * dt
		e.y += e.kb_y * dt
		var k := exp(-9.0 * dt)
		e.kb_x *= k
		e.kb_y *= k
	if e.airborne or e.z > 0.0:
		e.vz -= float(c.world.gravity) * dt
		e.z += e.vz * dt
		if e.z <= 0.0:
			e.z = 0.0
			e.vz = 0.0
			if e.airborne:
				e.airborne = false
				g.emit("enemy_land", {"id": e.id, "x": e.x, "y": e.y})
	e.x = clampf(e.x, g.bound_l + 20.0, g.bound_r - 20.0)
	e.y = g.clamp_ground_y(e.y)

func _separate(dt: float) -> void:
	var sep := float(c.ai.separation)
	var n: int = g.enemies.size()
	for i in n:
		var a = g.enemies[i]
		if a.state == "dead":
			continue
		for j in range(i + 1, n):
			var b = g.enemies[j]
			if b.state == "dead":
				continue
			var dx: float = b.x - a.x
			var dy: float = (b.y - a.y) * 2.0
			var min_d: float = maxf(sep, a.radius + b.radius)
			var d2 := dx * dx + dy * dy
			if d2 < min_d * min_d and d2 > 0.0001:
				var d := sqrt(d2)
				var push := (min_d - d) * 0.5 * minf(1.0, dt * 10.0)
				var nx := dx / d
				var ny := dy / d * 0.5
				var wa := 0.2 if a.type in ["boss", "brute"] else 1.0
				var wb := 0.2 if b.type in ["boss", "brute"] else 1.0
				a.x -= nx * push * wa
				a.y -= ny * push * wa
				b.x += nx * push * wb
				b.y += ny * push * wb

func _assign_tokens() -> void:
	var p = g.player
	var holders := 0
	var waiting: Array = []
	for e in g.enemies:
		if e.state == "dead" or not (e.type in ["imp", "brute"]):
			continue
		if e.token:
			holders += 1
		elif e.state in ["move", "orbit"] and e.cooldown <= 0.0:
			waiting.append(e)
	var free := int(c.ai.maxMeleeAttackers) - holders
	if free <= 0 or waiting.is_empty():
		return
	waiting.sort_custom(func(a, b): return g.ground_dist(a.x, a.y, p.x, p.y) < g.ground_dist(b.x, b.y, p.x, p.y))
	for i in mini(free, waiting.size()):
		waiting[i].token = true

func melee_count() -> int:
	var n := 0
	for e in g.enemies:
		if e.token and e.state != "dead":
			n += 1
	return n

func _move_to(e, tx: float, ty: float, speed: float, dt: float) -> bool:
	var dx: float = tx - e.x
	var dy: float = ty - e.y
	var d := sqrt(dx * dx + dy * dy)
	if d < 6.0:
		return true
	var s := minf(d, speed * dt)
	e.x += dx / d * s
	e.y += dy / d * s * 0.75
	if absf(dx) > 4.0:
		e.facing = 1 if dx > 0.0 else -1
	return false

func _face_player(e, p) -> void:
	if absf(p.x - e.x) > 4.0:
		e.facing = 1 if p.x > e.x else -1

func _orbit(e, p, dt: float, speed: float) -> void:
	var side := 1.0 if e.x >= p.x else -1.0
	e.orbit_a += float(c.ai.orbitSpeed) * dt * (1.0 if e.id % 2 == 0 else -1.0)
	var r := float(c.ai.orbitRadius) + float(e.id % 3) * 40.0
	var tx: float = p.x + side * r * (0.8 + 0.2 * cos(e.orbit_a))
	var ty: float = p.y + sin(e.orbit_a) * 90.0
	ty = g.clamp_ground_y(ty)
	_move_to(e, tx, ty, speed * 0.7, dt)
	_face_player(e, p)

# ---------------------------------------------------------------- imp
func _imp(e, dt: float, p) -> void:
	var ec: Dictionary = e.cfg
	match e.state:
		"move", "orbit", "idle":
			if e.token:
				e.state = "move"
				var side := 1.0 if e.x >= p.x else -1.0
				var ar := float(ec.attackRange)
				var arrived := _move_to(e, p.x + side * ar * 0.8, p.y, float(ec.speed), dt)
				if arrived or (absf(e.x - p.x) <= ar and absf(e.y - p.y) < 24.0):
					_face_player(e, p)
					e.state = "windup"
					e.state_t = 0.0
					e.state_dur = float(ec.windup)
					g.emit("telegraph", {"id": e.id, "kind": "claw", "x": e.x, "y": e.y, "facing": e.facing, "dur": e.state_dur})
			else:
				e.state = "orbit"
				_orbit(e, p, dt, float(ec.speed))
		"windup":
			if e.state_t >= e.state_dur:
				e.state = "attack"
				e.state_t = 0.0
				e.state_dur = float(ec.attackDuration)
				g.emit("enemy_attack", {"id": e.id, "x": e.x, "y": e.y, "facing": e.facing})
				var dx: float = (p.x - e.x) * e.facing
				if dx > -10.0 and dx < float(ec.attackRange) + 20.0 and absf(p.y - e.y) < float(c.combat.depthTolerance) and p.z < 50.0:
					g.hurt_player(float(ec.damage), e.x, "imp")
		"attack":
			if e.state_t >= e.state_dur:
				e.state = "recover"
				e.state_t = 0.0
				e.token = false
				e.cooldown = float(ec.attackCooldown) * g.rng.range_f(0.8, 1.3)
		"recover":
			if e.state_t >= 0.35:
				e.state = "orbit"
				e.state_t = 0.0

# ---------------------------------------------------------------- lantern
func _lantern(e, dt: float, p) -> void:
	var ec: Dictionary = e.cfg
	var pr := float(ec.preferredRange)
	match e.state:
		"move", "idle", "orbit":
			e.state = "move"
			var side := 1.0 if e.x >= p.x else -1.0
			var tx: float = p.x + side * pr
			if tx > g.bound_r - 60.0 or tx < g.bound_l + 60.0:
				tx = p.x - side * pr
			var ty: float = g.clamp_ground_y(p.y + sin(g.time * 0.7 + e.id) * 80.0)
			_move_to(e, tx, ty, float(ec.speed), dt)
			_face_player(e, p)
			var dist := absf(e.x - p.x)
			if e.cooldown <= 0.0 and dist < pr + 220.0 and dist > 120.0:
				e.state = "windup"
				e.state_t = 0.0
				e.state_dur = float(ec.windup)
				_face_player(e, p)
				g.emit("telegraph", {"id": e.id, "kind": "lantern", "x": e.x, "y": e.y, "dur": e.state_dur})
		"windup":
			if e.state_t >= e.state_dur:
				var pj: Dictionary = ec.projectile
				var tx: float = p.x + g.rng.range_f(-30.0, 30.0)
				var ty: float = g.clamp_ground_y(p.y + g.rng.range_f(-15.0, 15.0))
				var h = g.add_hazard("fireball", e.x + e.facing * 20.0, e.y, float(pj.flightTime),
					{"arc": float(pj.arcHeight), "z0": 70.0, "tx": tx, "ty": ty, "r": float(pj.radius)})
				h.tx = tx
				h.ty = ty
				h.radius = float(pj.radius)
				h.damage = float(ec.damage)
				g.emit("enemy_attack", {"id": e.id, "x": e.x, "y": e.y, "facing": e.facing})
				e.state = "recover"
				e.state_t = 0.0
				e.cooldown = float(ec.attackCooldown) * g.rng.range_f(0.85, 1.25)
		"recover":
			if e.state_t >= 0.45:
				e.state = "move"
				e.state_t = 0.0

# ---------------------------------------------------------------- brute
func _brute(e, dt: float, p) -> void:
	var ec: Dictionary = e.cfg
	match e.state:
		"move", "orbit", "idle":
			e.state = "move"
			var dist := absf(e.x - p.x)
			if e.token:
				var side := 1.0 if e.x >= p.x else -1.0
				_move_to(e, p.x + side * minf(dist, 320.0), p.y, float(ec.speed), dt)
				_face_player(e, p)
				if dist < float(ec.triggerRange) and absf(e.y - p.y) < 30.0 and e.cooldown <= 0.0:
					e.state = "windup"
					e.state_t = 0.0
					e.state_dur = float(ec.chargeWindup)
					e.dir_x = 1.0 if p.x > e.x else -1.0
					e.facing = int(e.dir_x)
					e.travelled = 0.0
					e.hit_player = false
					g.emit("telegraph", {"id": e.id, "kind": "bar", "x": e.x, "y": e.y, "dir": e.dir_x,
						"len": float(ec.chargeDistance), "width": float(ec.chargeWidth), "dur": e.state_dur})
			else:
				_orbit(e, p, dt, float(ec.speed))
		"windup":
			if e.state_t >= e.state_dur:
				e.state = "charging"
				e.state_t = 0.0
				g.emit("brute_charge", {"id": e.id, "x": e.x, "y": e.y, "dir": e.dir_x})
		"charging":
			var s := float(ec.chargeSpeed) * dt
			e.x += e.dir_x * s
			e.travelled += s
			if not e.hit_player and absf(p.x - e.x) < e.radius + 26.0 and absf(p.y - e.y) < float(ec.chargeWidth) * 0.5 + 10.0 and p.z < 60.0:
				if g.hurt_player(float(ec.damage), e.x - e.dir_x * 40.0, "brute"):
					e.hit_player = true
			if e.travelled >= float(ec.chargeDistance) or e.x <= g.bound_l + 30.0 or e.x >= g.bound_r - 30.0:
				e.state = "recover"
				e.state_t = 0.0
				g.emit("brute_stop", {"id": e.id, "x": e.x, "y": e.y})
		"recover":
			if e.state_t >= float(ec.recover):
				e.state = "move"
				e.state_t = 0.0
				e.token = false
				e.cooldown = float(ec.attackCooldown)

# ---------------------------------------------------------------- boss
func _boss(e, dt: float, p) -> void:
	var bc: Dictionary = e.cfg
	var mv: Dictionary = bc.moves
	if not e.enraged and e.hp <= e.max_hp * float(bc.enrageAt):
		e.enraged = true
		g.emit("boss_enrage", {"id": e.id, "x": e.x, "y": e.y})
	var spd := float(bc.speed) * (float(bc.enrageSpeedMul) if e.enraged else 1.0)
	var cdm := float(bc.enrageCooldownMul) if e.enraged else 1.0
	match e.state:
		"idle", "move":
			_face_player(e, p)
			var dist: float = g.ground_dist(e.x, e.y, p.x, p.y)
			if e.state_t < float(bc.idleBetween) * cdm:
				if dist > 200.0:
					_move_to(e, p.x + (180.0 if e.x > p.x else -180.0), p.y, spd * 0.6, dt)
				return
			var keys: Array = []
			var ws: Array = []
			var imps := 0
			for o in g.enemies:
				if o.type == "imp" and o.state != "dead":
					imps += 1
			for k in mv.keys():
				var w := float(mv[k].weight)
				if k == "summon" and imps >= int(mv.summon.maxAlive):
					continue
				if k == "sweep" and dist > float(mv.sweep.range) * 1.6:
					w *= 0.3
				if k == "leap" and dist > 300.0:
					w *= 2.0
				keys.append(k)
				ws.append(w)
			var pick: String = g.rng.weighted(keys, ws)
			if pick == "sweep" and dist > float(mv.sweep.range) * 0.9:
				e.state = "walk"
				e.state_t = 0.0
				e.move = "sweep"
				return
			_boss_start(e, pick, p, cdm)
		"walk":
			_face_player(e, p)
			var side := 1.0 if e.x >= p.x else -1.0
			var arrived := _move_to(e, p.x + side * float(mv.sweep.range) * 0.6, p.y, spd, dt)
			if arrived or g.ground_dist(e.x, e.y, p.x, p.y) < float(mv.sweep.range) * 0.75 or e.state_t > 2.5:
				_boss_start(e, "sweep", p, cdm)
		"sweep_windup":
			if e.state_t >= e.state_dur:
				e.state = "sweep"
				e.state_t = 0.0
				g.emit("boss_sweep", {"id": e.id, "x": e.x, "y": e.y, "facing": e.facing, "range": float(mv.sweep.range)})
				var dx: float = (p.x - e.x) * e.facing
				var d: float = g.ground_dist(e.x, e.y, p.x, p.y)
				var ang := rad_to_deg(absf(atan2((p.y - e.y) * 2.0, maxf(0.001, dx))))
				if d <= float(mv.sweep.range) + 20.0 and dx > -20.0 and ang <= float(mv.sweep.angle) * 0.5 + 10.0:
					g.hurt_player(float(mv.sweep.damage), e.x, "boss_sweep")
		"sweep":
			if e.state_t >= 0.45:
				_boss_idle(e)
		"leap_windup":
			if e.state_t >= e.state_dur:
				e.state = "leap"
				e.state_t = 0.0
				e.tx = p.x
				e.ty = p.y
				e.dir_x = e.x
				e.dir_y = e.y
				e.state_dur = float(mv.leap.airTime) * (0.85 if e.enraged else 1.0)
				g.emit("telegraph", {"id": e.id, "kind": "circle", "x": e.tx, "y": e.ty, "r": float(mv.leap.radius), "dur": e.state_dur})
				g.emit("boss_leap", {"id": e.id, "x": e.x, "y": e.y, "tx": e.tx, "ty": e.ty, "dur": e.state_dur})
		"leap":
			var k: float = clampf(e.state_t / e.state_dur, 0.0, 1.0)
			e.x = lerpf(e.dir_x, e.tx, k)
			e.y = lerpf(e.dir_y, e.ty, k)
			e.z = 4.0 * 260.0 * k * (1.0 - k)
			if k >= 1.0:
				e.z = 0.0
				e.state = "leap_land"
				e.state_t = 0.0
				g.emit("boss_land", {"id": e.id, "x": e.x, "y": e.y, "r": float(mv.leap.radius)})
				if g.ground_dist(e.x, e.y, p.x, p.y) <= float(mv.leap.radius) + 20.0 and p.z < 60.0:
					g.hurt_player(float(mv.leap.damage), e.x, "boss_leap")
		"leap_land":
			if e.state_t >= 0.6:
				_boss_idle(e)
		"summon_windup":
			if e.state_t >= e.state_dur:
				var sm: Dictionary = mv.summon
				for i in int(sm.count):
					var ang2: float = TAU * float(i) / float(sm.count) + g.rng.range_f(0.0, 1.0)
					var sx: float = clampf(e.x + cos(ang2) * 160.0, g.bound_l + 60.0, g.bound_r - 60.0)
					var o = g.spawn_enemy(String(sm.type), sx, e.y + sin(ang2) * 70.0)
					o.cooldown = 1.0
				g.emit("boss_summon", {"id": e.id, "x": e.x, "y": e.y})
				_boss_idle(e)

func _boss_start(e, mv_name: String, p, cdm: float) -> void:
	var m: Dictionary = e.cfg.moves[mv_name]
	_face_player(e, p)
	e.move = mv_name
	e.state = mv_name + "_windup"
	e.state_t = 0.0
	e.state_dur = float(m.windup) * (0.8 if e.enraged else 1.0)
	match mv_name:
		"sweep":
			g.emit("telegraph", {"id": e.id, "kind": "fan", "x": e.x, "y": e.y, "facing": e.facing,
				"range": float(m.range), "angle": float(m.angle), "dur": e.state_dur})
		"leap":
			g.emit("boss_crouch", {"id": e.id, "x": e.x, "y": e.y, "dur": e.state_dur})
		"summon":
			g.emit("telegraph", {"id": e.id, "kind": "summon", "x": e.x, "y": e.y, "dur": e.state_dur})

func _boss_idle(e) -> void:
	e.state = "idle"
	e.state_t = 0.0
