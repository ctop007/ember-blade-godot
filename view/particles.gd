class_name Particles
extends Node2D
## Lightweight batched particle layer (one draw pass). Shared global cap across all layers.

static var total := 0
static var cap := 260

var tex: Texture2D
var parts: Array = []   # each: [x,y,vx,vy,life,max,size0,size1,col,grav,drag,rot,vrot,flicker]
var additive := true
var tex_sz := Vector2.ONE

func _init(t: Texture2D, add := true) -> void:
	tex = t
	tex_sz = t.get_size()
	additive = add
	if add:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m

func emit_one(pos: Vector2, vel: Vector2, life: float, size0: float, size1: float, col: Color,
		grav := 0.0, drag := 0.0, flicker := false) -> void:
	if total >= cap:
		return
	total += 1
	parts.append([pos.x, pos.y, vel.x, vel.y, life, life, size0, size1, col, grav, drag, randf() * TAU, randf_range(-6.0, 6.0), flicker])

func burst(pos: Vector2, n: int, col: Color, speed: Vector2, life: Vector2, size: Vector2,
		grav := 0.0, drag := 3.0, dir := Vector2.ZERO, spread := PI, flicker := false) -> void:
	for i in n:
		var a: float
		if dir == Vector2.ZERO:
			a = randf() * TAU
		else:
			a = dir.angle() + randf_range(-spread, spread)
		var sp := randf_range(speed.x, speed.y)
		var v := Vector2(cos(a), sin(a) * 0.6) * sp
		emit_one(pos, v, randf_range(life.x, life.y), randf_range(size.x, size.y), 0.0, col, grav, drag, flicker)

func _process(dt: float) -> void:
	if parts.is_empty():
		return
	var keep: Array = []
	for p in parts:
		p[4] -= dt
		if p[4] <= 0.0:
			total -= 1
			continue
		var drag: float = p[10]
		if drag > 0.0:
			var k := exp(-drag * dt)
			p[2] *= k
			p[3] *= k
		p[3] += p[9] * dt
		p[0] += p[2] * dt
		p[1] += p[3] * dt
		p[11] += p[12] * dt
		keep.append(p)
	parts = keep
	queue_redraw()

func _draw() -> void:
	for p in parts:
		var k: float = p[4] / p[5]
		var s: float = lerpf(p[7], p[6], k)
		var col: Color = p[8]
		var a := col.a * minf(1.0, k * 2.5)
		if p[13]:
			a *= 0.6 + 0.4 * sin(p[4] * 40.0 + p[11])
		var c := Color(col.r, col.g, col.b, a)
		draw_set_transform(Vector2(p[0], p[1]), p[11], Vector2.ONE)
		draw_texture_rect(tex, Rect2(-s * 0.5, -s * 0.5, s, s), false, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func clear_all() -> void:
	total -= parts.size()
	parts.clear()
	queue_redraw()
