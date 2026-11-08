class_name BattleView
extends Node2D
## Renders a CoreGame: camera, y-sorted actors, hazards, and maps core events to fx + sfx.

var game: CoreGame
var sfx: Sfx
var fx: Fx
var hud                          # Hud (set by main)
var cam: Camera2D
var actors: Node2D
var ground_fx: Node2D
var top_fx: Node2D
var nums: Node2D
var overlay: CanvasLayer
var dim: ColorRect
var flash_rect: ColorRect
var actor_views: Dictionary = {}
var hero: ActorView
var hazard_nodes: Dictionary = {}
var shake_amp := 0.0
var shake_t := 0.0
var cam_x := 640.0
var last_hit_ids: Array = []
var charge_fx_t := 0.0
var ghost_t := 0.0
var fx_skill_fail: Array = []

func setup(g: CoreGame, s: Sfx) -> void:
	game = g
	sfx = s
	var layers := Bg.build(self, float(g.cfg.world.length))
	ground_fx = Node2D.new()
	ground_fx.name = "Ground"
	add_child(ground_fx)
	actors = Node2D.new()
	actors.name = "Actors"
	actors.y_sort_enabled = true
	add_child(actors)
	top_fx = Node2D.new()
	top_fx.name = "Top"
	add_child(top_fx)
	add_child(layers[1])
	nums = Node2D.new()
	nums.name = "Nums"
	add_child(nums)
	cam = Camera2D.new()
	cam.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	add_child(cam)
	cam.make_current()
	overlay = CanvasLayer.new()
	overlay.layer = 5
	add_child(overlay)
	dim = ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.04, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(flash_rect)
	fx = Fx.new()
	add_child(fx)
	fx.setup(self, ground_fx, top_fx, nums)
	hero = ActorView.new()
	hero.setup("hero", 0)
	actors.add_child(hero)
	cam_x = g.player.x
	_update_camera(0.0, true)

func view_size() -> Vector2:
	return get_viewport().get_visible_rect().size

func cam_top() -> float:
	return cam.global_position.y - view_size().y * 0.5

# ------------------------------------------------------------------ per frame
func sync(dt: float) -> void:
	var frozen := game.hitstop > 0.0
	for ev in game.events:
		_on_event(ev)
	game.events.clear()
	hero.sync(game.player, dt, false)
	var seen := {}
	for e in game.enemies:
		seen[e.id] = true
		var av: ActorView = actor_views.get(e.id)
		if av == null:
			av = ActorView.new()
			av.setup(e.type, e.id)
			actors.add_child(av)
			actor_views[e.id] = av
		av.sync(e, dt, frozen)
		if frozen and last_hit_ids.has(e.id):
			av.position += Vector2(randf_range(-3, 3), randf_range(-1.5, 1.5))
	for id in actor_views.keys():
		if not seen.has(id):
			actor_views[id].queue_free()
			actor_views.erase(id)
			fx.clear_telegraph(id)
	if not frozen:
		last_hit_ids.clear()
	# hazards follow core positions
	for h in game.hazards:
		var n: Node2D = hazard_nodes.get(h.id)
		if n == null:
			continue
		n.position = Vector2(h.x, h.y - h.z - (46.0 if h.kind == "spear" else 0.0))
		match h.kind:
			"spear":
				fx.spear_tick(n)
			"flame":
				if randf() < 0.3:
					fx.flame_tick(n)
			"fireball":
				if randf() < 0.5:
					fx.p_add.emit_one(n.position, Vector2(randf_range(-20, 20), -30), 0.3, 14.0, 3.0, Color(1.0, 0.5, 0.2), 0.0, 1.0)
	# charging glints
	var p = game.player
	if p.charged or (p.state == "charge" and p.hold_t > 0.1):
		charge_fx_t -= dt
		if charge_fx_t <= 0.0:
			charge_fx_t = 0.03
			fx.charging(Vector2(p.x, p.y), p.facing)
	if p.state == "dodge":
		ghost_t -= dt
		if ghost_t <= 0.0:
			ghost_t = float(game.cfg.dodge.duration) / float(game.cfg.dodge.afterimages)
			fx.dodge_ghost(hero)
	_update_camera(dt, false)

func _update_camera(dt: float, snap: bool) -> void:
	var vs := view_size()
	var p = game.player
	var target: float = p.x + p.facing * float(game.cfg.world.cameraLookAhead)
	var half := vs.x * 0.5
	var lo: float = game.bound_l + half
	var hi: float = game.bound_r - half
	if lo > hi:
		target = (game.bound_l + game.bound_r) * 0.5
	else:
		target = clampf(target, lo, hi)
	var wl := float(game.cfg.world.length)
	if vs.x < wl:
		target = clampf(target, half, wl - half)
	if snap:
		cam_x = target
	else:
		cam_x = lerpf(cam_x, target, 1.0 - exp(-float(game.cfg.world.cameraLerp) * dt))
	var off := Vector2.ZERO
	if shake_t > 0.0:
		shake_t -= dt
		var k := clampf(shake_t / float(game.cfg.combat.shakeDecay), 0.0, 1.0)
		off = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amp * k
	cam.position = Vector2(cam_x, 360.0) + off

func shake(amp: float) -> void:
	var mx := float(game.cfg.combat.shakeMax)
	amp = minf(amp, mx)
	# a new kick only overrides if stronger than what remains; always short decay, never continuous
	var remain := shake_amp * clampf(shake_t / float(game.cfg.combat.shakeDecay), 0.0, 1.0)
	if amp >= remain:
		shake_amp = amp
		shake_t = float(game.cfg.combat.shakeDecay)

func screen_flash(col: Color, dur: float) -> void:
	flash_rect.color = col
	var tw := flash_rect.create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, dur)

# ------------------------------------------------------------------ events
func _on_event(ev: Dictionary) -> void:
	var p = game.player
	match ev.type:
		"hit":
			var av: ActorView = actor_views.get(int(ev.id))
			var h := 80.0
			if av:
				h = av.h
				av.kick(-2.2, 2.6)
			last_hit_ids.append(int(ev.id))
			fx.hit(ev, h)
			if ev.src != "flame" and ev.src != "ult":
				sfx.play("hit_crit" if ev.crit else "hit", -2.0 if ev.src != "spear" else -5.0)
				sfx.play("enemy_hurt", -8.0, 0.1, 0.06)
			if ev.src in ["atk1", "atk2"]:
				shake(1.5)
			elif ev.src in ["atk3", "thrust", "spear"] or ev.crit:
				shake(3.0)
			if hud:
				hud.on_combo(game.combo, game.combo_damage)
		"enemy_dead":
			var big := String(ev.enemy) in ["brute", "boss"]
			fx.enemy_dead(Vector2(ev.x, ev.y), big)
			sfx.play("enemy_die", -4.0, 0.1, 0.05)
			fx.clear_telegraph(int(ev.id))
		"spawn":
			fx.dust(Vector2(ev.x, ev.y), 4)
			fx.ring(Vector2(ev.x, ev.y), 10, 60, Color(1.0, 0.45, 0.15, 0.7), 0.4)
		"swing":
			var step := int(ev.step)
			hero.kick(1.6 if step == 2 else 1.0, -1.0)
			fx.swing(ev, step)
			sfx.play("swing%d" % (step + 1), -3.0)
		"charge_ready":
			fx.charge_ready(Vector2(ev.x, ev.y))
			sfx.play("card_flip", -6.0, 0.0)
		"thrust":
			hero.kick(2.5, -1.5)
			fx.thrust(ev)
			sfx.play("charge_thrust")
		"dodge":
			ghost_t = 0.0
			sfx.play("dodge", -3.0)
			fx.dust(Vector2(ev.x, ev.y), 3)
		"dodge_perfect":
			fx.word(Vector2(ev.x, ev.y - 150), "闪避！", Color(0.6, 0.9, 1.0))
		"jump":
			hero.kick(-1.5, 2.5)
			sfx.play("jump", -4.0)
			fx.dust(Vector2(ev.x, ev.y), 3)
		"land":
			hero.kick(2.0, -2.5)
			fx.dust(Vector2(ev.x, ev.y), 4)
		"slam_start":
			hero.kick(-1.0, 2.0)
		"slam_land":
			hero.kick(3.0, -3.5)
			fx.slam_land(ev)
			sfx.play("land_slam")
		"crescent":
			fx.crescent(ev, hero)
		"crescent_tick":
			fx.crescent_tick(ev)
		"skyfall_cast":
			hero.kick(-0.8, 1.6)
			fx.skyfall_cast(ev)
		"skyfall_strike":
			fx.skyfall_strike(ev)
		"spear_cast":
			hero.kick(-1.0, 1.0)
		"spear_throw":
			hero.kick(2.0, -1.0)
			sfx.play("skill3_throw")
		"hazard_add":
			var n: Node2D = null
			match String(ev.kind):
				"spear":
					n = fx.spear_node(ev.data)
					top_fx.add_child(n)
				"fireball":
					n = fx.fireball_node(ev.data)
					actors.add_child(n)
				"flame":
					n = fx.flame_node()
					ground_fx.add_child(n)
			if n:
				n.position = Vector2(ev.x, ev.y)
				hazard_nodes[int(ev.id)] = n
		"hazard_end":
			var n2: Node2D = hazard_nodes.get(int(ev.id))
			if n2:
				hazard_nodes.erase(int(ev.id))
				if String(ev.kind) == "spear":
					fx.spear_end(n2.position)
				fx.fade_out(n2, 0.15)
		"ember":
			fx.ember(ev)
		"ult_start":
			_ult_cutin(float(ev.cutin))
		"ult_strike":
			for pt in ev.points:
				fx.meteor(Vector2(pt[0], pt[1]), randf_range(0.0, 0.08))
			if ev.last:
				var tw := create_tween()
				tw.tween_interval(0.3)
				tw.tween_callback(func(): screen_flash(Color(1, 0.95, 0.85, 0.85), 0.35))
		"ult_end":
			var tw2 := dim.create_tween()
			tw2.tween_property(dim, "color:a", 0.0, 0.3)
		"telegraph":
			fx.telegraph(ev)
		"telegraph_cancel":
			fx.clear_telegraph(int(ev.id))
		"enemy_attack":
			var av2: ActorView = actor_views.get(int(ev.id))
			if av2:
				av2.kick(1.8, -1.2)
			fx.clear_telegraph(int(ev.id))
			sfx.play("swing1", -8.0, 0.15)
		"brute_charge":
			sfx.play("brute_charge")
			shake(2.0)
		"brute_stop":
			fx.clear_telegraph(int(ev.id))
			fx.dust(Vector2(ev.x, ev.y), 5)
		"boss_intro":
			sfx.play("boss_appear")
			if hud:
				hud.boss_card(String(ev.name), float(game.cfg.enemies.boss.titleCardTime))
		"boss_sweep":
			fx.clear_telegraph(int(ev.id))
			fx.boss_sweep(ev)
		"boss_crouch":
			var av3: ActorView = actor_views.get(int(ev.id))
			if av3:
				av3.kick(-1.5, 1.5)
		"boss_leap":
			sfx.play("jump", 0.0, 0.0)
		"boss_land":
			fx.clear_telegraph(int(ev.id))
			fx.boss_land(ev)
		"boss_summon":
			fx.clear_telegraph(int(ev.id))
			fx.ring(Vector2(ev.x, ev.y), 30, 220, Color(0.7, 0.3, 1.0), 0.5)
		"boss_enrage":
			fx.enrage(Vector2(ev.x, ev.y))
			sfx.play("boss_appear", -4.0)
			if hud:
				hud.banner("灰烬骑士 狂暴了！", Color(1.0, 0.35, 0.25))
		"player_hit":
			hero.kick(-1.5, 1.5)
			shake(4.0)
			screen_flash(Color(1, 0.1, 0.05, 0.22), 0.2)
			fx.number(Vector2(ev.x, ev.y - 150), int(ev.dmg), false, "player")
			sfx.play("player_hurt")
			if String(ev.src) == "fireball":
				pass
		"heal":
			fx.number(Vector2(p.x, p.y - 160), int(ev.v), false, "heal")
		"rage_full":
			if hud:
				hud.rage_full()
		"skill_fail":
			fx_skill_fail.append({"crescent": "skill1", "skyfall": "skill2", "meteorSpear": "skill3", "ultimate": "ult"}.get(String(ev.skill), ""))
			if hud:
				hud.skill_fail(String(ev.skill), String(ev.why))
		"wave_start", "wave_clear", "advance", "draft_open", "victory", "defeat", "combo_end", "player_dead":
			if hud:
				hud.on_core_event(ev)

# ------------------------------------------------------------------ ultimate cut-in
func _ult_cutin(cutin: float) -> void:
	sfx.play("ult_start")
	var tw := dim.create_tween()
	tw.tween_property(dim, "color:a", float(game.cfg.skills.ultimate.dimAlpha), 0.15)
	var vs := view_size()
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(root)
	# speed lines
	for i in 14:
		var ln := ColorRect.new()
		ln.color = Color(1.0, 0.8, 0.5, randf_range(0.15, 0.4))
		ln.size = Vector2(randf_range(200, 500), randf_range(2, 5))
		ln.position = Vector2(vs.x + randf_range(0, 300), randf_range(vs.y * 0.2, vs.y * 0.8))
		root.add_child(ln)
		var lt := ln.create_tween()
		lt.tween_property(ln, "position:x", -600.0, randf_range(0.35, 0.6))
	# banner
	var banner := UltBanner.new()
	banner.size = Vector2(vs.x + 200, 150)
	banner.position = Vector2(vs.x, vs.y * 0.5 - 40)
	root.add_child(banner)
	var name_l := Label.new()
	name_l.text = String(game.cfg.skills.ultimate.name)
	var ls := LabelSettings.new()
	ls.font_size = 72
	ls.font_color = Color(1.0, 0.86, 0.4)
	ls.outline_size = 14
	ls.outline_color = Color(0.35, 0.06, 0.0)
	ls.shadow_size = 6
	ls.shadow_color = Color(1.0, 0.35, 0.1, 0.6)
	name_l.label_settings = ls
	name_l.position = Vector2(vs.x * 0.42 + 200, 22)
	banner.add_child(name_l)
	var tb := banner.create_tween()
	tb.tween_property(banner, "position:x", -200.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tb.tween_property(banner, "position:x", -240.0, cutin - 0.36)
	tb.tween_property(banner, "modulate:a", 0.0, 0.18)
	# portrait
	var tex := Art.real("fx/ult_portrait.png")
	var portrait: Control
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(vs.y * 0.95, vs.y * 0.95)
		portrait = tr
	else:
		var tr2 := TextureRect.new()
		tr2.texture = Art.real("chars/hero/cast.png")
		tr2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr2.size = Vector2(vs.y * 1.3, vs.y * 1.3)
		portrait = tr2
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.position = Vector2(-portrait.size.x, vs.y - portrait.size.y * 0.92)
	root.add_child(portrait)
	var tp := portrait.create_tween()
	tp.tween_property(portrait, "position:x", vs.x * 0.02, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tp.tween_property(portrait, "position:x", vs.x * 0.06, cutin - 0.38)
	tp.tween_property(portrait, "position:x", -portrait.size.x, 0.18).set_ease(Tween.EASE_IN)
	tp.tween_callback(root.queue_free)
	var tv := create_tween()
	tv.tween_interval(0.12)
	tv.tween_callback(func(): sfx.play("ult_voice", 2.0, 0.0))

class UltBanner extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts := PackedVector2Array([Vector2(60, 0), Vector2(w, 0), Vector2(w - 60, h), Vector2(0, h)])
		var cols := PackedColorArray([Color(0.6, 0.08, 0.02, 0.0), Color(0.75, 0.18, 0.03, 0.95), Color(0.45, 0.05, 0.02, 0.95), Color(0.3, 0.02, 0.0, 0.0)])
		draw_polygon(pts, cols)
		draw_line(Vector2(60, 0), Vector2(w, 0), Color(1.0, 0.8, 0.4, 0.9), 3.0)
		draw_line(Vector2(0, h), Vector2(w - 60, h), Color(1.0, 0.6, 0.2, 0.8), 3.0)
