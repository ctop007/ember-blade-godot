class_name CoreGame
extends RefCounted
## Pure-logic simulation. Advance with step(dt, input). Never touches engine nodes.
## View drains `events` every frame and reads entity state.

const E := preload("res://core/entities.gd")
const PlayerCtrl := preload("res://core/player_ctrl.gd")
const EnemyAI := preload("res://core/enemy_ai.gd")

var cfg: Dictionary
var rng: CoreRng
var player: E.Player
var enemies: Array = []
var hazards: Array = []
var events: Array = []
var pctl
var ai

var time := 0.0
var phase := "advance"   # advance wave draft boss_intro end
var phase_t := 0.0
var wave_index := -1     # 0-based index into cfg.waves of current/last wave
var arena_l := 0.0
var arena_r := 1280.0
var bound_l := 0.0
var bound_r := 1280.0
var spawn_queue: Array = []
var spawn_t := 0.0
var next_id := 1
var draft_options: Array = []
var picked: Dictionary = {}
var mods := {
	"attackMul": 0.0, "critChance": 0.0, "mpRegenMul": 0.0, "rageMul": 0.0, "cooldownMul": 0.0,
	"crescentSpins": 0, "spearSplit": false, "dodgeFlame": false, "skyfallRadiusMul": 0.0,
	"skyfallDamageMul": 0.0, "killHeal": 0.0, "dodgeCrit": false,
}
var combo := 0
var combo_damage := 0.0
var combo_t := 0.0
var max_combo := 0
var total_damage := 0.0
var kills := 0
var hitstop := 0.0
var freeze := 0.0          # world freeze (ult cut-in, boss intro): enemies & hazards paused
var god := false
var result := ""           # "" / "win" / "lose"
var pending := {}
var tip := ""
var draft_return := ""

func _init(config: Dictionary, seed_value: int = -1) -> void:
	cfg = config
	rng = CoreRng.new(int(cfg.get("seed", 1)) if seed_value < 0 else seed_value)
	player = E.Player.new()
	var pc: Dictionary = cfg.player
	player.x = float(pc.spawnX)
	player.y = float(pc.spawnY)
	player.max_hp = float(pc.maxHp)
	player.hp = player.max_hp
	player.max_mp = float(pc.maxMp)
	player.mp = player.max_mp
	pctl = PlayerCtrl.new(self)
	ai = EnemyAI.new(self)
	var a0: Array = arena(0)
	arena_l = a0[0]
	arena_r = a0[1]
	bound_l = arena_l
	bound_r = arena_r
	phase = "advance"
	tip = "向右前进"
	start_wave(0)

# ---------------------------------------------------------------- helpers
func arena(i: int) -> Array:
	var arr: Array = cfg.world.arenas
	var a: Array = arr[clampi(i, 0, arr.size() - 1)]
	return [float(a[0]), float(a[1])]

func emit(type: String, data: Dictionary = {}) -> void:
	data["type"] = type
	events.append(data)

func ground_dist(ax: float, ay: float, bx: float, by: float) -> float:
	var dx := ax - bx
	var dy := (ay - by) * 2.0
	return sqrt(dx * dx + dy * dy)

func alive_enemies() -> Array:
	var out: Array = []
	for e in enemies:
		if e.state != "dead":
			out.append(e)
	return out

func clamp_ground_y(y: float) -> float:
	return clampf(y, float(cfg.world.groundTop), float(cfg.world.groundBottom))

func cd_mul() -> float:
	return maxf(0.3, 1.0 + float(mods.cooldownMul))

# ---------------------------------------------------------------- step
func step(dt: float, input: Dictionary) -> void:
	_merge_edges(input)
	if result != "" and phase == "end":
		phase_t += dt
		return
	if phase == "draft":
		return
	if hitstop > 0.0:
		hitstop -= dt
		return
	var inp := pending
	pending = {}
	time += dt
	phase_t += dt
	if freeze > 0.0:
		freeze -= dt
		pctl.update_frozen(dt, inp)
		if phase == "boss_intro" and freeze <= 0.0:
			phase = "wave"
			phase_t = 0.0
		return
	pctl.update(dt, inp)
	ai.update(dt)
	_update_hazards(dt)
	_update_combo(dt)
	_update_phase(dt)
	if player.hp <= 0.0 and result == "":
		result = "lose"
		phase = "end"
		phase_t = 0.0
		emit("defeat")

func _merge_edges(input: Dictionary) -> void:
	for k in input.keys():
		var v: Variant = input[k]
		if v is bool and (k.ends_with("_pressed") or k.ends_with("_released")):
			pending[k] = bool(pending.get(k, false)) or v
		else:
			pending[k] = v

func _update_combo(dt: float) -> void:
	if combo > 0:
		combo_t -= dt
		if combo_t <= 0.0:
			combo = 0
			combo_damage = 0.0
			emit("combo_end")

# ---------------------------------------------------------------- damage
func roll_damage(base: float, can_crit := true) -> Array:
	var dmg := base * float(cfg.player.attack) * (1.0 + float(mods.attackMul))
	var v := float(cfg.combat.damageVariance)
	dmg *= rng.range_f(1.0 - v, 1.0 + v)
	var crit := false
	if can_crit:
		if player.dodge_crit_ready:
			crit = true
			player.dodge_crit_ready = false
		elif rng.chance(float(cfg.player.critChance) + float(mods.critChance)):
			crit = true
	if crit:
		dmg *= float(cfg.player.critMul)
	return [maxf(1.0, round(dmg)), crit]

func damage_enemy(e, base: float, opts: Dictionary = {}) -> float:
	if e.state == "dead" or e.state == "spawn":
		return 0.0
	var r: Array = roll_damage(base, not opts.get("nocrit", false))
	var dmg: float = r[0]
	var crit: bool = r[1]
	e.hp -= dmg
	e.flash = float(cfg.combat.hitFlash)
	total_damage += dmg
	var src_x: float = opts.get("from_x", player.x)
	var dir := 1.0 if e.x >= src_x else -1.0
	var resist := float(e.cfg.get("knockbackResist", 0.0))
	var kb := float(opts.get("knockback", 30.0)) * (1.0 - resist)
	var killed: bool = e.hp <= 0.0
	if killed:
		e.hp = 0.0
		ai.kill(e)
		kills += 1
		if float(mods.killHeal) > 0.0:
			heal_player(float(mods.killHeal))
		add_rage(float(cfg.combat.ragePerKill))
	else:
		var super_armor: bool = e.cfg.get("superArmor", false)
		if not super_armor:
			ai.hurt(e, float(cfg.combat.enemyHurtStun))
		e.kb_x += dir * kb * 6.0
		var launch := float(opts.get("launch", 0.0))
		if launch > 0.0 and not super_armor:
			e.vz = launch
			e.airborne = true
	if killed:
		e.kb_x += dir * kb * 6.0
	combo += 1
	combo_t = float(cfg.combat.comboTimeout)
	combo_damage += dmg
	max_combo = maxi(max_combo, combo)
	if not opts.get("ult", false):
		var gain := minf(float(cfg.combat.rageMaxPerHit), dmg * float(cfg.combat.ragePerHitMul))
		add_rage(gain * (1.0 + float(mods.rageMul)))
	var hs_min := float(cfg.combat.hitstopMin)
	var hs_max := float(cfg.combat.hitstopMax)
	var heavy := dmg >= float(cfg.combat.hitstopHeavyThreshold) or crit
	if not opts.get("no_hitstop", false):
		hitstop = maxf(hitstop, hs_max if heavy else hs_min)
	emit("hit", {"id": e.id, "x": e.x, "y": e.y, "z": e.z, "dmg": dmg, "crit": crit,
		"killed": killed, "src": opts.get("src", "melee"), "heavy": heavy, "dir": dir})
	return dmg

func add_rage(v: float) -> void:
	var before := player.rage
	player.rage = minf(float(cfg.player.maxRage), player.rage + v)
	if before < float(cfg.player.maxRage) and player.rage >= float(cfg.player.maxRage):
		emit("rage_full")

func heal_player(v: float) -> void:
	player.hp = minf(player.max_hp, player.hp + v)
	emit("heal", {"v": v})

func hurt_player(dmg: float, from_x: float, src := "enemy") -> bool:
	return pctl.take_hit(dmg, from_x, src)

## Enemies in a forward box from (x,y) facing `f`.
func enemies_in_box(x: float, y: float, f: int, rng_len: float, width: float) -> Array:
	var out: Array = []
	var tol := float(cfg.combat.depthTolerance)
	for e in enemies:
		if e.state == "dead" or e.state == "spawn":
			continue
		var dx: float = (e.x - x) * f
		if dx < -e.radius * 0.6 or dx > rng_len + e.radius:
			continue
		if absf(e.y - y) > tol + width * 0.2:
			continue
		out.append(e)
	return out

func enemies_in_radius(x: float, y: float, r: float) -> Array:
	var out: Array = []
	for e in enemies:
		if e.state == "dead" or e.state == "spawn":
			continue
		if ground_dist(e.x, e.y, x, y) <= r + e.radius:
			out.append(e)
	return out

# ---------------------------------------------------------------- hazards
func add_hazard(kind: String, x: float, y: float, life: float, data: Dictionary = {}) -> E.Hazard:
	var h := E.Hazard.new()
	h.id = next_id
	next_id += 1
	h.kind = kind
	h.x = x
	h.y = y
	h.sx = x
	h.sy = y
	h.life = life
	h.data = data
	hazards.append(h)
	emit("hazard_add", {"id": h.id, "kind": kind, "x": x, "y": y, "life": life, "data": data})
	return h

func _update_hazards(dt: float) -> void:
	for h in hazards:
		h.t += dt
		match h.kind:
			"fireball":
				_hz_fireball(h)
			"skyfall":
				_hz_skyfall(h)
			"spear":
				_hz_spear(h, dt)
			"flame":
				_hz_flame(h, dt)
		if h.t >= h.life:
			h.done = true
	var keep: Array = []
	for h in hazards:
		if h.done:
			emit("hazard_end", {"id": h.id, "kind": h.kind, "x": h.x, "y": h.y})
		else:
			keep.append(h)
	hazards = keep

func _hz_fireball(h) -> void:
	var k := clampf(h.t / h.life, 0.0, 1.0)
	h.x = lerpf(h.sx, h.tx, k)
	h.y = lerpf(h.sy, h.ty, k)
	h.z = float(h.data.get("z0", 60.0)) * (1.0 - k) + 4.0 * float(h.data.arc) * k * (1.0 - k)
	if k >= 1.0 and not h.data.get("landed", false):
		h.data["landed"] = true
		emit("fireball_land", {"x": h.tx, "y": h.ty, "r": h.radius})
		if ground_dist(player.x, player.y, h.tx, h.ty) <= h.radius + 20.0 and player.z < 40.0:
			hurt_player(h.damage, h.tx, "fireball")

func _hz_skyfall(h) -> void:
	if h.t >= float(h.data.delay) and not h.data.get("struck", false):
		h.data["struck"] = true
		emit("skyfall_strike", {"x": h.x, "y": h.y, "r": h.radius})
		for e in enemies_in_radius(h.x, h.y, h.radius):
			damage_enemy(e, h.damage, {"src": "skyfall", "knockback": float(h.data.knockback),
				"launch": float(h.data.launch), "from_x": h.x})
		hitstop = maxf(hitstop, float(cfg.combat.hitstopMax))

func _hz_spear(h, dt: float) -> void:
	var step_len: float = float(h.data.speed) * dt
	if h.travelled >= float(h.data.range):
		h.done = true
		return
	var px: float = h.x
	h.x += h.vx * step_len
	h.y += h.vy * step_len
	h.travelled += step_len
	var lo := minf(px, h.x) - 20.0
	var hi := maxf(px, h.x) + 20.0
	for e in enemies:
		if e.state == "dead" or e.state == "spawn" or h.hit.has(e.id):
			continue
		if e.x + e.radius < lo or e.x - e.radius > hi:
			continue
		if absf(e.y - h.y) > float(h.data.width) * 0.5 + float(cfg.combat.depthTolerance) * 0.5:
			continue
		h.hit[e.id] = true
		damage_enemy(e, h.damage, {"src": "spear", "knockback": float(h.data.knockback), "from_x": h.x - h.vx * 50.0, "no_hitstop": h.hit.size() > 1})
	var interval := float(h.data.emberInterval)
	while h.tick_t + interval <= h.travelled:
		h.tick_t += interval
		emit("ember", {"x": h.sx + h.vx * h.tick_t, "y": h.sy + h.vy * h.tick_t, "life": float(h.data.emberLife)})
	if h.travelled >= float(h.data.range):
		h.done = true

func _hz_flame(h, dt: float) -> void:
	h.tick_t -= dt
	if h.tick_t <= 0.0:
		h.tick_t = float(cfg.dodgeFlame.tick)
		for e in enemies_in_radius(h.x, h.y, h.radius):
			damage_enemy(e, h.damage, {"src": "flame", "knockback": 0.0, "nocrit": true, "no_hitstop": true})

# ---------------------------------------------------------------- waves
func start_wave(i: int) -> void:
	wave_index = i
	var w: Dictionary = cfg.waves[i]
	var a: Array = arena(i)
	arena_l = a[0]
	arena_r = a[1]
	bound_l = arena_l
	bound_r = arena_r
	spawn_queue.clear()
	for s in w.spawns:
		for n in int(s.count):
			spawn_queue.append(String(s.type))
	rng.shuffle(spawn_queue)
	# imps first so ranged/brutes arrive a bit later
	spawn_queue.sort_custom(func(p, q): return _spawn_order(p) < _spawn_order(q))
	spawn_t = 0.3
	tip = String(w.tip)
	phase_t = 0.0
	if w.get("boss", false):
		phase = "boss_intro"
		freeze = float(cfg.enemies.boss.titleCardTime)
		spawn_queue.clear()
		var b = spawn_enemy("boss", minf(arena_r - 260.0, player.x + 620.0), 580.0)
		b.state = "idle"
		b.state_t = 0.0
		emit("boss_intro", {"name": String(cfg.enemies.boss.name)})
	else:
		phase = "wave"
	emit("wave_start", {"index": i, "title": String(w.title), "tip": tip, "boss": w.get("boss", false)})

func _spawn_order(t: String) -> int:
	return {"imp": 0, "lantern": 1, "brute": 2}.get(t, 0)

func spawn_enemy(type: String, x: float, y: float):
	var c: Dictionary = cfg.enemies[type]
	var e := E.Enemy.new()
	e.id = next_id
	next_id += 1
	e.type = type
	e.kind = String(c.kind)
	e.cfg = c
	e.x = x
	e.y = clamp_ground_y(y)
	e.hp = float(c.hp)
	e.max_hp = e.hp
	e.radius = float(c.radius)
	e.facing = -1 if x > player.x else 1
	e.state = "spawn"
	e.state_dur = 0.5
	e.cooldown = rng.range_f(0.4, 1.2)
	e.orbit_a = rng.range_f(0.0, TAU)
	e.side = 1 if x > player.x else -1
	enemies.append(e)
	emit("spawn", {"id": e.id, "enemy": type, "x": e.x, "y": e.y})
	return e

func _update_phase(dt: float) -> void:
	match phase:
		"wave":
			if not spawn_queue.is_empty():
				spawn_t -= dt
				if spawn_t <= 0.0:
					spawn_t = float(cfg.waves[wave_index].spawnInterval)
					var t: String = spawn_queue.pop_front()
					var right := rng.chance(0.65) if player.x < (arena_l + arena_r) * 0.5 else rng.chance(0.35)
					var x := (arena_r - rng.range_f(30.0, 160.0)) if right else (arena_l + rng.range_f(30.0, 160.0))
					spawn_enemy(t, x, rng.range_f(float(cfg.world.groundTop) + 10.0, float(cfg.world.groundBottom) - 10.0))
			elif alive_enemies().is_empty() and phase_t > 1.0:
				_wave_cleared()
		"advance":
			var nxt := wave_index + 1
			var a: Array = arena(nxt)
			var trig: float = a[0] + float(cfg.world.waveTriggerOffset)
			if a[0] <= arena_l + 1.0:
				trig = -INF
			if phase_t >= float(cfg.waveIntermission) and player.x >= trig:
				start_wave(nxt)
	# remove corpses
	var keep: Array = []
	for e in enemies:
		if e.state == "dead" and e.dead_t > 1.2:
			continue
		keep.append(e)
	enemies = keep

func _wave_cleared() -> void:
	var w: Dictionary = cfg.waves[wave_index]
	emit("wave_clear", {"index": wave_index})
	if w.get("boss", false):
		result = "win"
		phase = "end"
		phase_t = 0.0
		emit("victory")
		return
	var draft_after: Array = cfg.draftAfterWaves
	if draft_after.has(float(wave_index + 1)) or draft_after.has(wave_index + 1):
		open_draft()
	else:
		_to_advance()

func _to_advance() -> void:
	phase = "advance"
	phase_t = 0.0
	var nxt := wave_index + 1
	if nxt >= cfg.waves.size():
		return
	var a: Array = arena(nxt)
	bound_l = minf(arena_l, a[0])
	bound_r = maxf(arena_r, a[1])
	tip = "向右前进" if a[0] > arena_l + 1.0 else "强敌将至……"
	emit("advance", {"tip": tip, "to": a[0]})

# ---------------------------------------------------------------- draft
func open_draft(resume_wave := false) -> void:
	draft_options = roll_cards(int(cfg.draft.choices))
	draft_return = "wave" if resume_wave else ""
	phase = "draft"
	emit("draft_open", {"options": draft_options.duplicate()})

func card_by_id(id: String) -> Dictionary:
	for c in cfg.cards:
		if String(c.id) == id:
			return c
	return {}

func roll_cards(n: int) -> Array:
	var pool: Array = []
	for c in cfg.cards:
		if c.get("unique", false) and picked.has(String(c.id)):
			continue
		pool.append(c)
	var out: Array = []
	var weights: Dictionary = cfg.draft.rarityWeights
	var rar_keys: Array = weights.keys()
	var rar_w: Array = []
	for k in rar_keys:
		rar_w.append(float(weights[k]))
	var guard := 0
	while out.size() < n and not pool.is_empty() and guard < 50:
		guard += 1
		var r: String = rng.weighted(rar_keys, rar_w)
		var cands: Array = pool.filter(func(c): return String(c.rarity) == r)
		if cands.is_empty():
			cands = pool
		var c: Dictionary = rng.pick(cands)
		out.append(String(c.id))
		pool.erase(c)
	return out

func choose_card(id: String) -> bool:
	if phase != "draft" or not draft_options.has(id):
		return false
	apply_card(id)
	draft_options = []
	emit("draft_pick", {"id": id})
	if draft_return == "wave":
		phase = "wave"   # debug draft opened mid-wave
	else:
		_to_advance()
	return true

func apply_card(id: String) -> void:
	var c := card_by_id(id)
	if c.is_empty():
		return
	picked[id] = int(picked.get(id, 0)) + 1
	var ef: Dictionary = c.effect
	for k in ef.keys():
		var v: Variant = ef[k]
		match k:
			"maxHp":
				player.max_hp += float(v)
			"heal":
				heal_player(float(v))
			_:
				if v is bool:
					mods[k] = v
				elif mods.has(k):
					mods[k] = mods[k] + v

# ---------------------------------------------------------------- debug / bridge
func debug_state() -> Dictionary:
	var es: Array = []
	for e in enemies:
		if e.state != "dead":
			es.append({"type": e.type, "hp": e.hp, "x": e.x, "y": e.y, "state": e.state})
	return {"hp": player.hp, "maxHp": player.max_hp, "mp": player.mp, "rage": player.rage, "combo": combo,
		"wave": wave_index + 1, "phase": phase, "result": result, "enemies": es, "px": player.x, "py": player.y,
		"pstate": player.state, "kills": kills, "cds": player.cds.duplicate(), "draft": draft_options.duplicate(),
		"maxCombo": max_combo, "totalDamage": total_damage}

func debug_spawn(type: String, n: int) -> void:
	for i in n:
		spawn_enemy(type, rng.range_f(arena_l + 60.0, arena_r - 60.0), rng.range_f(float(cfg.world.groundTop), float(cfg.world.groundBottom)))

func debug_set_wave(n: int) -> void:
	for e in enemies:
		if e.state != "dead":
			ai.kill(e)
	enemies.clear()
	hazards.clear()
	freeze = 0.0
	var i := clampi(n - 1, 0, cfg.waves.size() - 1)
	var a: Array = arena(i)
	player.x = a[0] + 220.0
	start_wave(i)

func dispose() -> void:
	## break RefCounted cycles (game <-> controllers)
	if pctl:
		pctl.g = null
		pctl.p = null
	if ai:
		ai.g = null
	pctl = null
	ai = null
