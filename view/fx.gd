class_name Fx
extends Node
## Effect compositions. Each skill has its own distinct look (DESIGN §5).
## Layers: ground (under actors), top (over actors, additive, semi-transparent), nums (damage numbers).

const C_FIRE := Color(1.0, 0.42, 0.16)
const C_FIRE2 := Color(1.0, 0.75, 0.35)
const C_SKY := Color(0.56, 0.85, 1.0)
const C_WARN := Color(1.0, 0.2, 0.15)

var bv                      # BattleView (shake / flash)
var ground: Node2D
var top: Node2D
var nums: Node2D
var p_add: Particles        # sparks, embers (top, additive)
var p_ground: Particles     # lingering embers on ground (additive)
var p_debris: Particles     # rocks (normal blend)
var p_smoke: Particles      # smoke / dust (normal blend)
var add_mat: CanvasItemMaterial
var telegraphs: Dictionary = {}   # enemy id -> Node2D
var num_count := 0

func setup(battle, g: Node2D, t: Node2D, n: Node2D) -> void:
	bv = battle
	ground = g
	top = t
	nums = n
	add_mat = CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p_ground = Particles.new(Art.fx("fx/ember.png"), true)
	ground.add_child(p_ground)
	p_smoke = Particles.new(Art.fx("fx/smoke.png"), false)
	top.add_child(p_smoke)
	p_debris = Particles.new(Art.fx("fx/rock_debris.png"), false)
	top.add_child(p_debris)
	p_add = Particles.new(Art.fx("fx/spark.png"), true)
	top.add_child(p_add)

# ------------------------------------------------------------------ primitives
func spr(layer: Node2D, path: String, pos: Vector2, col: Color, scl: Vector2, additive := true) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Art.fx(path)
	s.position = pos
	s.modulate = col
	s.scale = scl
	if additive:
		s.material = add_mat
	layer.add_child(s)
	return s

## Scale so the texture spans `w` x `h` world px.
func fit(s: Sprite2D, w: float, h: float) -> Vector2:
	var sz := s.texture.get_size()
	return Vector2(w / sz.x, h / sz.y)

func fade_out(n: CanvasItem, dur: float, delay := 0.0) -> Tween:
	var tw := n.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(n, "modulate:a", 0.0, dur)
	tw.tween_callback(n.queue_free)
	return tw

## Ground ellipse ring expanding from r0 to r1 (ground radius; ellipse is 2:1).
func ring(pos: Vector2, r0: float, r1: float, col: Color, dur: float, layer: Node2D = null, path := "fx/shock_ring.png") -> void:
	var s := spr(layer if layer else ground, path, pos, col, Vector2.ONE)
	s.scale = fit(s, r0 * 2.0, r0)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "scale", fit(s, r1 * 2.0, r1), dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(s.queue_free)

func glow(pos: Vector2, size: float, col: Color, dur: float, layer: Node2D = null) -> Sprite2D:
	var s := spr(layer if layer else top, "fx/glow.png", pos, col, Vector2.ONE)
	s.scale = fit(s, size, size)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "scale", s.scale * 1.4, dur)
	tw.tween_property(s, "modulate:a", 0.0, dur)
	tw.chain().tween_callback(s.queue_free)
	return s

# ------------------------------------------------------------------ hits
func hit(ev: Dictionary, body_h: float) -> void:
	var pos := Vector2(ev.x, ev.y - ev.z - body_h * 0.5)
	var src: String = ev.src
	var col := Color(1.0, 0.95, 0.75)
	match src:
		"crescent", "spear", "flame", "ult", "slam":
			col = C_FIRE2
		"skyfall":
			col = C_SKY
	var hs := spr(top, "fx/hit_spark.png", pos, Color(col, 0.95), Vector2.ONE)
	var sz := 110.0 if ev.heavy else 80.0
	hs.scale = fit(hs, sz * 0.4, sz * 0.4)
	hs.rotation = randf() * TAU
	var tw := hs.create_tween().set_parallel(true)
	tw.tween_property(hs, "scale", fit(hs, sz, sz), 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(hs, "modulate:a", 0.0, 0.16).set_delay(0.04)
	tw.chain().tween_callback(hs.queue_free)
	var d := Vector2(float(ev.dir), -0.2)
	p_add.burst(pos, 7 if ev.heavy else 4, col, Vector2(220, 520), Vector2(0.12, 0.3), Vector2(6, 12), 600.0, 4.0, d, 0.8)
	if ev.crit:
		var st := spr(top, "fx/flash_star.png", pos, Color(1, 0.9, 0.4, 0.9), Vector2.ONE)
		st.scale = fit(st, 40, 40)
		var tw2 := st.create_tween().set_parallel(true)
		tw2.tween_property(st, "scale", fit(st, 150, 150), 0.14)
		tw2.tween_property(st, "modulate:a", 0.0, 0.2)
		tw2.chain().tween_callback(st.queue_free)
	number(pos + Vector2(randf_range(-14, 14), -16), int(ev.dmg), ev.crit, src)

func number(pos: Vector2, v: int, crit: bool, src: String) -> void:
	if num_count > 40:
		return
	num_count += 1
	var l := Label.new()
	l.text = str(v) + ("!" if crit else "")
	var ls := LabelSettings.new()
	ls.font_size = 40 if crit else 26
	ls.font_color = Color(1.0, 0.3, 0.25) if src == "player" else Color(0.4, 1.0, 0.5) if src == "heal" else Color(1.0, 0.85, 0.2) if crit else (Color(1.0, 0.62, 0.3) if src in ["crescent", "spear", "ult", "flame"] else (Color(0.7, 0.9, 1.0) if src == "skyfall" else Color(1, 1, 1)))
	ls.outline_size = 8 if crit else 6
	ls.outline_color = Color(0.25, 0.05, 0.0) if crit else Color(0.1, 0.05, 0.08)
	l.label_settings = ls
	l.size = Vector2(120, 50)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.pivot_offset = Vector2(60, 25)
	l.position = pos - Vector2(60, 25)
	l.scale = Vector2(0.4, 0.4)
	nums.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2(1.25, 1.25) if crit else Vector2(1.0, 1.0), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE if crit else Vector2(0.9, 0.9), 0.08)
	tw.parallel().tween_property(l, "position:y", l.position.y - 50.0, 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		num_count -= 1
		l.queue_free())

func word(pos: Vector2, text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font_size = 26
	ls.font_color = col
	ls.outline_size = 6
	ls.outline_color = Color(0.05, 0.05, 0.12)
	l.label_settings = ls
	l.size = Vector2(160, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = pos - Vector2(80, 20)
	nums.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 40.0, 0.5).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.2)
	tw.tween_callback(l.queue_free)

# ------------------------------------------------------------------ basic attacks
func swing(ev: Dictionary, step: int) -> void:
	var f := float(ev.facing)
	var pos := Vector2(ev.x + f * 50.0, ev.y - 60.0)
	if step == 2:
		var b := spr(top, "fx/thrust_beam.png", Vector2(ev.x + f * 20.0, ev.y - 58.0), Color(1.0, 0.85, 0.55, 0.9), Vector2.ONE)
		b.centered = false
		b.offset = Vector2(0, -b.texture.get_height() * 0.5)
		b.scale = fit(b, 60, 26) * Vector2(f, 1)
		var tw := b.create_tween().set_parallel(true)
		tw.tween_property(b, "scale", fit(b, 170, 22) * Vector2(f, 1), 0.08)
		tw.tween_property(b, "modulate:a", 0.0, 0.18).set_delay(0.06)
		tw.chain().tween_callback(b.queue_free)
		return
	var s := spr(top, "fx/slash_trail.png", pos, Color(1.0, 0.8, 0.5, 0.85), Vector2.ONE)
	s.scale = fit(s, 150, 90) * Vector2(f, -1.0 if step == 1 else 1.0)
	s.rotation = (0.2 if step == 0 else -0.2) * f
	var tw2 := s.create_tween().set_parallel(true)
	tw2.tween_property(s, "rotation", s.rotation + (0.5 if step == 0 else -0.5) * f, 0.12)
	tw2.tween_property(s, "modulate:a", 0.0, 0.16).set_delay(0.04)
	tw2.chain().tween_callback(s.queue_free)

func charge_ready(pos: Vector2) -> void:
	var st := spr(top, "fx/flash_star.png", pos + Vector2(0, -60), Color(1.0, 0.85, 0.4), Vector2.ONE)
	st.scale = fit(st, 20, 20)
	var tw := st.create_tween()
	tw.tween_property(st, "scale", fit(st, 90, 90), 0.1)
	tw.tween_property(st, "modulate:a", 0.0, 0.2)
	tw.tween_callback(st.queue_free)
	ring(pos, 20, 70, C_FIRE2, 0.25)

func charging(pos: Vector2, facing: int) -> void:
	var tip := pos + Vector2(facing * 70.0, -60.0)
	var a := randf() * TAU
	p_add.emit_one(tip + Vector2(cos(a), sin(a)) * 50.0, -Vector2(cos(a), sin(a)) * 200.0, 0.25, 8.0, 2.0, C_FIRE2, 0.0, 0.0)

func thrust(ev: Dictionary) -> void:
	var f := float(ev.facing)
	var dist := float(ev.distance)
	var b := spr(top, "fx/thrust_beam.png", Vector2(ev.x, ev.y - 58.0), Color(1.0, 0.7, 0.35, 0.95), Vector2.ONE)
	b.centered = false
	b.offset = Vector2(0, -b.texture.get_height() * 0.5)
	b.scale = fit(b, 40, 40) * Vector2(f, 1)
	var core := spr(top, "fx/thrust_beam.png", Vector2(ev.x, ev.y - 58.0), Color(1, 1, 0.9, 1), Vector2.ONE)
	core.centered = false
	core.offset = b.offset
	core.scale = fit(core, 40, 14) * Vector2(f, 1)
	for s in [b, core]:
		var h := 44.0 if s == b else 14.0
		var tw: Tween = s.create_tween().set_parallel(true)
		tw.tween_property(s, "scale", fit(s, dist + 120.0, h) * Vector2(f, 1), float(ev.dur)).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(s, "modulate:a", 0.0, 0.25)
		tw.chain().tween_callback(s.queue_free)
	p_add.burst(Vector2(ev.x, ev.y - 58), 14, C_FIRE2, Vector2(200, 500), Vector2(0.2, 0.45), Vector2(6, 12), 0.0, 3.0, Vector2(f, 0), 0.25)
	ring(Vector2(ev.x, ev.y), 20, 90, C_FIRE, 0.3)

func dodge_ghost(av: ActorView) -> void:
	var g := av.make_ghost(Color(0.5, 0.85, 1.0, 0.5))
	ground.get_parent().get_node("Actors").add_child(g)
	g.z_index = -1
	fade_out(g, 0.3)

func slam_land(ev: Dictionary) -> void:
	var pos := Vector2(ev.x, ev.y)
	var r := float(ev.r)
	ring(pos, 20, r * 1.15, C_FIRE2, 0.35)
	ring(pos, 10, r * 0.7, Color(1, 1, 1, 0.8), 0.2)
	glow(pos + Vector2(0, -10), r * 1.4, Color(1.0, 0.5, 0.2, 0.6), 0.3, ground)
	p_smoke.burst(pos, 10, Color(0.55, 0.45, 0.4, 0.5), Vector2(80, 240), Vector2(0.4, 0.7), Vector2(30, 60), 0.0, 4.0)
	p_debris.burst(pos, 10, Color(0.45, 0.36, 0.3), Vector2(150, 350), Vector2(0.4, 0.7), Vector2(8, 16), 1400.0, 1.0, Vector2(0, -1), 1.2)
	bv.shake(4.0)

# ------------------------------------------------------------------ skill 1: 炎月斩 (orbiting fire crescents)
func crescent(ev: Dictionary, follow: Node2D) -> void:
	var r := float(ev.r)
	var spins := int(ev.spins)
	var dur := float(ev.spin_dur) * spins
	var root := Node2D.new()
	root.set_script(preload("res://view/follow.gd"))
	root.set("target", follow)
	top.add_child(root)
	# ground fire ring
	var ringn := spr(ground, "fx/fire_ring.png", Vector2.ZERO, Color(1.0, 0.45, 0.12, 0.85), Vector2.ONE)
	ringn.set_script(preload("res://view/follow.gd"))
	ringn.set("target", follow)
	ringn.scale = fit(ringn, r * 0.4, r * 0.2)
	var tw0 := ringn.create_tween()
	tw0.tween_property(ringn, "scale", fit(ringn, r * 2.1, r * 1.05), 0.12).set_ease(Tween.EASE_OUT)
	tw0.tween_interval(maxf(0.0, dur - 0.12))
	tw0.tween_property(ringn, "modulate:a", 0.0, 0.2)
	tw0.tween_callback(ringn.queue_free)
	# orbit plane squashed to ground perspective, lifted to waist height
	var plane := Node2D.new()
	plane.position = Vector2(0, -40)
	plane.scale = Vector2(1.0, 0.5)
	root.add_child(plane)
	var spinner := Node2D.new()
	plane.add_child(spinner)
	for k in 2:
		for gst in 4:
			var s := Sprite2D.new()
			s.texture = Art.fx("fx/crescent_arc.png")
			s.material = add_mat
			var sz := s.texture.get_size()
			s.scale = Vector2(r * 2.0 / sz.x, r * 2.0 / sz.y)
			s.rotation = PI * k - 0.32 * gst
			var a: float = [0.85, 0.42, 0.22, 0.1][gst]
			s.modulate = (C_FIRE if gst > 0 else C_FIRE2.lerp(C_FIRE, 0.3)) * Color(1, 1, 1, a)
			spinner.add_child(s)
	var tw := spinner.create_tween()
	tw.tween_property(spinner, "rotation", TAU * spins, dur)
	var tw2 := root.create_tween()
	tw2.tween_interval(dur)
	tw2.tween_property(root, "modulate:a", 0.0, 0.15)
	tw2.tween_callback(root.queue_free)
	# embers thrown from the arc tips
	var emit_t := root.create_tween().set_loops(int(dur / 0.03))
	emit_t.tween_callback(func():
		if not is_instance_valid(follow):
			return
		for k in 2:
			var a: float = spinner.rotation + PI * k
			var p := follow.position + Vector2(cos(a) * r, -40.0 + sin(a) * r * 0.5)
			var tang := Vector2(-sin(a), cos(a) * 0.5) * 260.0
			p_add.emit_one(p, tang + Vector2(0, -60), randf_range(0.25, 0.5), randf_range(7, 13), 2.0, C_FIRE2 if randf() < 0.5 else C_FIRE, -120.0, 2.0, true))
	emit_t.tween_interval(0.03)
	bv.sfx.play("skill1_crescent")

func crescent_tick(ev: Dictionary) -> void:
	ring(Vector2(ev.x, ev.y), 40, 170, Color(1.0, 0.55, 0.2, 0.7), 0.25)
	bv.shake(2.0)

# ------------------------------------------------------------------ skill 2: 天穹落光 (warning -> sky pillar)
func skyfall_cast(ev: Dictionary) -> void:
	var pos := Vector2(ev.x, ev.y)
	var r := float(ev.r)
	var d := float(ev.delay)
	var w := spr(ground, "fx/warn_circle.png", pos, Color(C_SKY, 0.0), Vector2.ONE)
	w.scale = fit(w, r * 2.6, r * 1.3)
	var tw := w.create_tween().set_parallel(true)
	tw.tween_property(w, "scale", fit(w, r * 2.0, r), d).set_ease(Tween.EASE_OUT)
	tw.tween_property(w, "modulate:a", 0.9, d * 0.5)
	tw.chain().tween_property(w, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(w.queue_free)
	# runes spinning inward
	for i in 6:
		var a := TAU * i / 6.0
		p_ground.emit_one(pos + Vector2(cos(a) * r, sin(a) * r * 0.5), Vector2(-cos(a) * r, -sin(a) * r * 0.5) / d, d, 10.0, 4.0, C_SKY, 0.0, 0.0)
	# charge glow at caster hand
	glow(Vector2(ev.px, ev.y - 90), 60, Color(C_SKY, 0.8), d)
	bv.sfx.play("skill2_charge")

func skyfall_strike(ev: Dictionary) -> void:
	var pos := Vector2(ev.x, ev.y)
	var r := float(ev.r)
	var top_y: float = bv.cam_top() - 40.0
	var h: float = pos.y - top_y
	for layer in 2:
		var s := spr(top, "fx/light_pillar.png", pos, Color(C_SKY, 0.85) if layer == 0 else Color(1, 1, 1, 0.95), Vector2.ONE)
		s.centered = false
		s.offset = Vector2(-s.texture.get_width() * 0.5, -s.texture.get_height())
		var wpx := r * (1.5 if layer == 0 else 0.55)
		var full := fit(s, wpx, h)
		s.scale = Vector2(full.x * 0.5, 0.0)
		s.position = Vector2(pos.x, top_y)
		s.offset = Vector2(-s.texture.get_width() * 0.5, 0)
		var tw := s.create_tween()
		tw.tween_property(s, "scale", Vector2(full.x * 0.5, full.y), 0.06)
		tw.tween_property(s, "scale", Vector2(full.x * 1.15, full.y), 0.08)
		tw.tween_property(s, "scale", Vector2(0.0, full.y), 0.3).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(s, "modulate:a", 0.0, 0.3)
		tw.tween_callback(s.queue_free)
	ring(pos, 20, r * 1.3, Color(0.8, 0.95, 1.0), 0.4)
	ring(pos, 10, r * 0.8, C_SKY, 0.3)
	glow(pos, r * 2.2, Color(0.5, 0.8, 1.0, 0.5), 0.35, ground)
	p_debris.burst(pos, 16, Color(0.5, 0.45, 0.42), Vector2(200, 500), Vector2(0.5, 0.9), Vector2(8, 18), 1500.0, 0.8, Vector2(0, -1), 1.3)
	p_add.burst(pos + Vector2(0, -20), 16, C_SKY, Vector2(150, 450), Vector2(0.3, 0.6), Vector2(6, 12), -200.0, 3.0, Vector2(0, -1), 1.0)
	p_smoke.burst(pos, 6, Color(0.7, 0.75, 0.8, 0.35), Vector2(60, 200), Vector2(0.4, 0.7), Vector2(40, 70), 0.0, 4.0)
	bv.screen_flash(Color(0.75, 0.9, 1.0, 0.35), 0.12)
	bv.shake(4.0)
	bv.sfx.play("skill2_strike")

# ------------------------------------------------------------------ skill 3: 流星枪 (comet spear + ground embers)
func spear_node(h_data: Dictionary) -> Node2D:
	var n := Node2D.new()
	var f := signf(float(h_data.dx))
	n.rotation = atan2(float(h_data.dy), float(h_data.dx))
	var trail := Sprite2D.new()
	trail.texture = Art.fx("fx/comet_trail.png")
	trail.material = add_mat
	trail.centered = false
	trail.offset = Vector2(-trail.texture.get_width(), -trail.texture.get_height() * 0.5)
	trail.scale = Vector2(260.0 / trail.texture.get_width(), 40.0 / trail.texture.get_height())
	trail.modulate = Color(1.0, 0.45, 0.12, 0.9)
	n.add_child(trail)
	var trail2 := trail.duplicate()
	trail2.scale = Vector2(180.0 / trail.texture.get_width(), 14.0 / trail.texture.get_height())
	trail2.modulate = Color(1.0, 0.9, 0.6, 1.0)
	n.add_child(trail2)
	var head := Sprite2D.new()
	head.texture = Art.fx("fx/comet_head.png")
	head.material = add_mat
	head.scale = Vector2(90.0 / head.texture.get_width(), 48.0 / head.texture.get_height())
	head.modulate = Color(1.0, 0.85, 0.5)
	n.add_child(head)
	var _unused := f
	return n

func spear_tick(n: Node2D) -> void:
	p_add.emit_one(n.position + Vector2(randf_range(-10, 10), randf_range(-8, 8)), Vector2(-cos(n.rotation), -sin(n.rotation)) * 160.0 + Vector2(0, -40),
		randf_range(0.2, 0.4), randf_range(8, 14), 2.0, C_FIRE if randf() < 0.6 else C_FIRE2, -100.0, 2.0, true)

func ember(ev: Dictionary) -> void:
	var pos := Vector2(ev.x + randf_range(-10, 10), ev.y + randf_range(-6, 6))
	var life := float(ev.life)
	p_ground.emit_one(pos, Vector2(0, -6), life, 16.0, 6.0, C_FIRE, 0.0, 0.0, true)
	p_ground.emit_one(pos + Vector2(randf_range(-12, 12), 0), Vector2(0, -24), life * 0.7, 9.0, 3.0, C_FIRE2, 0.0, 0.0, true)

func spear_end(pos: Vector2) -> void:
	glow(pos, 90, Color(1.0, 0.6, 0.2, 0.8), 0.25)
	p_add.burst(pos, 10, C_FIRE2, Vector2(100, 300), Vector2(0.2, 0.4), Vector2(6, 12), 300.0, 3.0)

# ------------------------------------------------------------------ ultimate meteors
func meteor(target: Vector2, delay: float) -> void:
	var start := target + Vector2(-260, -620)
	var m := spr(top, "fx/meteor.png", start, Color(1.0, 0.75, 0.4), Vector2.ONE)
	m.scale = fit(m, 150, 150)
	m.rotation = (target - start).angle() - PI * 0.25
	m.visible = false
	var tw := m.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func(): m.visible = true)
	tw.tween_property(m, "position", target + Vector2(0, -20), 0.16).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		m.queue_free()
		_meteor_boom(target))

func _meteor_boom(pos: Vector2) -> void:
	glow(pos + Vector2(0, -30), 220, Color(1.0, 0.55, 0.2, 0.75), 0.35)
	ring(pos, 20, 150, C_FIRE2, 0.35)
	p_add.burst(pos + Vector2(0, -20), 8, C_FIRE2, Vector2(200, 500), Vector2(0.3, 0.55), Vector2(8, 16), 500.0, 2.0, Vector2(0, -1), 1.2)
	p_debris.burst(pos, 4, Color(0.4, 0.3, 0.26), Vector2(200, 400), Vector2(0.4, 0.7), Vector2(8, 14), 1400.0, 1.0, Vector2(0, -1), 1.0)
	bv.sfx.play("ult_impact", -2.0, 0.1, 0.06)
	bv.shake(3.0)

# ------------------------------------------------------------------ enemy telegraphs / hazards
func telegraph(ev: Dictionary) -> void:
	clear_telegraph(int(ev.id))
	var kind: String = ev.kind
	var dur := float(ev.dur)
	var pos := Vector2(ev.x, ev.y)
	var n: Node2D = null
	match kind:
		"bar":
			n = Node2D.new()
			n.position = pos
			ground.add_child(n)
			var len := float(ev.len)
			var w := float(ev.width)
			var d := float(ev.dir)
			for i in 2:
				var s := Sprite2D.new()
				s.texture = Art.fx("fx/warn_bar.png")
				s.centered = false
				s.offset = Vector2(0, -s.texture.get_height() * 0.5)
				s.modulate = Color(C_WARN, 0.55 if i == 0 else 0.6)
				s.scale = Vector2(len / s.texture.get_width() * d, w / s.texture.get_height())
				n.add_child(s)
				if i == 1:
					s.scale.x = 0.0
					var tw := s.create_tween()
					tw.tween_property(s, "scale:x", len / s.texture.get_width() * d, dur)
		"fan":
			n = Node2D.new()
			n.position = pos
			ground.add_child(n)
			var rng_len := float(ev.range)
			var f := float(ev.facing)
			for i in 2:
				var s := Sprite2D.new()
				s.texture = Art.fx("fx/warn_fan.png")
				s.centered = false
				s.offset = Vector2(0, -s.texture.get_height() * 0.5)
				s.modulate = Color(C_WARN, 0.5)
				var full := Vector2(rng_len / s.texture.get_width() * f, rng_len / s.texture.get_height())
				s.scale = full
				n.add_child(s)
				if i == 1:
					s.scale = full * 0.05
					var tw := s.create_tween()
					tw.tween_property(s, "scale", full, dur)
		"circle":
			var r := float(ev.r)
			var s := spr(ground, "fx/warn_circle.png", pos, Color(C_WARN, 0.85), Vector2.ONE, false)
			s.scale = fit(s, r * 2.0, r)
			var inner := Sprite2D.new()
			inner.texture = s.texture
			inner.modulate = Color(1, 0.3, 0.2, 0.6)
			inner.scale = Vector2(0.05, 0.05)
			s.add_child(inner)
			var tw := inner.create_tween()
			tw.tween_property(inner, "scale", Vector2.ONE, dur)
			n = s
		"summon":
			var s := spr(ground, "fx/warn_circle.png", pos, Color(0.7, 0.3, 1.0, 0.8), Vector2.ONE)
			s.scale = fit(s, 260, 130)
			var tw := s.create_tween().set_loops(4)
			tw.tween_property(s, "modulate:a", 0.3, dur / 8.0)
			tw.tween_property(s, "modulate:a", 0.8, dur / 8.0)
			n = s
		"claw", "lantern":
			var av: ActorView = bv.actor_views.get(int(ev.id))
			if av:
				av.show_alert(dur)
			return
	if n:
		telegraphs[int(ev.id)] = n
		var tw2 := n.create_tween()
		tw2.tween_interval(dur + 0.6)
		tw2.tween_callback(func(): clear_telegraph(int(ev.id), n))

func clear_telegraph(id: int, only: Node2D = null) -> void:
	if not telegraphs.has(id):
		return
	var n: Node2D = telegraphs[id]
	if only != null and n != only:
		return
	telegraphs.erase(id)
	if is_instance_valid(n):
		fade_out(n, 0.12)

func fireball_node(h_data: Dictionary) -> Node2D:
	var n := Node2D.new()
	var tx := float(h_data.tx)
	var ty := float(h_data.ty)
	var r := float(h_data.r)
	var w := spr(ground, "fx/warn_circle.png", Vector2(tx, ty), Color(1.0, 0.35, 0.15, 0.0), Vector2.ONE, false)
	w.scale = fit(w, r * 2.0, r)
	var tw := w.create_tween()
	tw.tween_property(w, "modulate:a", 0.85, 0.2)
	tw.tween_interval(0.85)
	tw.tween_callback(w.queue_free)
	var ball := Sprite2D.new()
	ball.texture = Art.fx("fx/fireball.png")
	ball.material = add_mat
	ball.modulate = Color(1.0, 0.55, 0.2)
	ball.scale = Vector2(46.0 / ball.texture.get_width(), 46.0 / ball.texture.get_height())
	n.add_child(ball)
	return n

func fireball_land(ev: Dictionary) -> void:
	var pos := Vector2(ev.x, ev.y)
	ring(pos, 10, float(ev.r) * 1.1, C_FIRE, 0.3)
	glow(pos + Vector2(0, -16), 120, Color(1.0, 0.45, 0.15, 0.7), 0.3)
	p_add.burst(pos, 8, C_FIRE2, Vector2(120, 320), Vector2(0.2, 0.45), Vector2(6, 12), 500.0, 2.0, Vector2(0, -1), 1.2)
	bv.sfx.play("fireball_land", -3.0)
	bv.shake(1.5)

func flame_node() -> Node2D:
	var n := Node2D.new()
	var s := Sprite2D.new()
	s.texture = Art.fx("fx/glow.png")
	s.material = add_mat
	s.modulate = Color(1.0, 0.4, 0.1, 0.7)
	s.scale = Vector2(70.0 / s.texture.get_width(), 34.0 / s.texture.get_height())
	n.add_child(s)
	return n

func flame_tick(n: Node2D) -> void:
	p_add.emit_one(n.position + Vector2(randf_range(-20, 20), randf_range(-6, 6)), Vector2(0, -90), randf_range(0.3, 0.5), randf_range(10, 16), 2.0, C_FIRE, -60.0, 1.0, true)

# ------------------------------------------------------------------ misc
func enemy_dead(pos: Vector2, big: bool) -> void:
	p_add.burst(pos + Vector2(0, -30), 14 if big else 8, C_FIRE, Vector2(60, 220), Vector2(0.4, 0.9), Vector2(6, 12), -180.0, 2.0, Vector2(0, -1), 1.2, true)
	p_smoke.burst(pos + Vector2(0, -20), 5 if big else 3, Color(0.25, 0.2, 0.22, 0.5), Vector2(30, 90), Vector2(0.5, 0.9), Vector2(30, 60), -40.0, 2.0)

func dust(pos: Vector2, n := 4) -> void:
	p_smoke.burst(pos, n, Color(0.5, 0.42, 0.36, 0.4), Vector2(40, 140), Vector2(0.3, 0.6), Vector2(20, 40), -20.0, 4.0)

func boss_land(ev: Dictionary) -> void:
	var pos := Vector2(ev.x, ev.y)
	ring(pos, 20, float(ev.r) * 1.2, Color(1.0, 0.4, 0.2), 0.4)
	p_debris.burst(pos, 14, Color(0.35, 0.32, 0.3), Vector2(200, 450), Vector2(0.4, 0.8), Vector2(10, 18), 1500.0, 1.0, Vector2(0, -1), 1.2)
	dust(pos, 8)
	bv.shake(4.0)
	bv.sfx.play("boss_slam")

func boss_sweep(ev: Dictionary) -> void:
	var f := float(ev.facing)
	var s := spr(top, "fx/slash_trail.png", Vector2(ev.x + f * 90.0, ev.y - 100.0), Color(1.0, 0.35, 0.2, 0.85), Vector2.ONE)
	s.scale = fit(s, float(ev.range) * 1.6, 200) * Vector2(f, 1)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "rotation", 0.6 * f, 0.18)
	tw.tween_property(s, "modulate:a", 0.0, 0.25).set_delay(0.06)
	tw.chain().tween_callback(s.queue_free)
	bv.shake(3.0)
	bv.sfx.play("boss_slam", -4.0)

func enrage(pos: Vector2) -> void:
	ring(pos, 40, 260, Color(1.0, 0.2, 0.15), 0.6)
	glow(pos + Vector2(0, -110), 340, Color(1.0, 0.2, 0.1, 0.6), 0.6)
	p_add.burst(pos + Vector2(0, -100), 30, Color(1.0, 0.3, 0.15), Vector2(150, 400), Vector2(0.4, 0.8), Vector2(8, 16), -100.0, 2.0)
	bv.shake(4.0)
