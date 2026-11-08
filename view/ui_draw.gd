class_name UiDraw
extends RefCounted
## Shared code-drawn "game-feel" UI pieces: beveled panels, orb buttons, vector icons.

static func rrect_points(r: Rect2, rad: float, seg: int = 5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var cs: Array = [
		[Vector2(r.end.x - rad, r.position.y + rad), -PI * 0.5],
		[Vector2(r.end.x - rad, r.end.y - rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5],
		[Vector2(r.position.x + rad, r.position.y + rad), PI],
	]
	for cc in cs:
		var c: Vector2 = cc[0]
		var a0: float = cc[1]
		for i in seg + 1:
			var a: float = a0 + PI * 0.5 * float(i) / float(seg)
			pts.append(c + Vector2(cos(a), sin(a)) * rad)
	return pts

static func grad_rrect(ci: CanvasItem, r: Rect2, rad: float, top: Color, bot: Color) -> void:
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return
	var pts := rrect_points(r, rad)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top.lerp(bot, clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)))
	ci.draw_polygon(pts, cols)

static func rrect_outline(ci: CanvasItem, r: Rect2, rad: float, col: Color, width: float) -> void:
	var pts := rrect_points(r, rad)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, width, true)

static func game_panel(ci: CanvasItem, r: Rect2, rad: float, base: Color, border: Color, shadow := true) -> void:
	if shadow:
		grad_rrect(ci, Rect2(r.position + Vector2(0, 5), r.size), rad, Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.45))
	grad_rrect(ci, r, rad, border.lightened(0.35), border.darkened(0.35))
	var inner := r.grow(-3.0)
	grad_rrect(ci, inner, maxf(2.0, rad - 3.0), base.lightened(0.12), base.darkened(0.3))
	var hl := Rect2(inner.position + Vector2(rad * 0.5, 2), Vector2(inner.size.x - rad, maxf(2.0, inner.size.y * 0.32)))
	grad_rrect(ci, hl, rad * 0.6, Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.0))

static func orb(ci: CanvasItem, c: Vector2, rad: float, base: Color, rim: Color, pressed := false, alpha := 1.0) -> void:
	var k := 0.92 if pressed else 1.0
	rad *= k
	ci.draw_circle(c + Vector2(0, 4), rad + 3.0, Color(0, 0, 0, 0.4 * alpha))
	ci.draw_circle(c, rad + 3.0, Color(rim.darkened(0.55), alpha))
	ci.draw_circle(c, rad, Color(rim, alpha))
	var steps := 6
	for i in steps:
		var t := float(i) / float(steps - 1)
		var col := base.darkened(0.45).lerp(base.lightened(0.1), t)
		col.a = alpha
		ci.draw_circle(c + Vector2(0, -rad * 0.08 * t), rad * (0.86 - 0.5 * t * t * 0.6), col)
	ci.draw_set_transform(c + Vector2(0, -rad * 0.5), 0.0, Vector2(1.0, 0.45))
	ci.draw_circle(Vector2.ZERO, rad * 0.55, Color(1, 1, 1, 0.12 * alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_arc(c, rad - 1.0, PI * 1.1, PI * 1.9, 18, Color(1, 1, 1, 0.35 * alpha), 2.0, true)

static func star_points(c: Vector2, r_out: float, r_in: float, n: int, rot := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n * 2:
		var r := r_out if i % 2 == 0 else r_in
		var a := rot + PI * float(i) / float(n) - PI * 0.5
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts

static func flame_points(c: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 24:
		var t := TAU * float(i) / 24.0
		var x := sin(t) * 0.55
		var y := -cos(t) * 0.75
		if y < 0.0:
			x *= (1.0 + y * 0.95)
			y *= 1.25
		pts.append(c + Vector2(x, y) * s)
	return pts

static func heart_points(c: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 30:
		var t := TAU * float(i) / 30.0
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		pts.append(c + Vector2(x, y) * s / 17.0)
	return pts

## Vector icons. kind: attack jump dodge crescent skyfall meteor ult pause atk crit hp mp heal rage cdr
static func icon(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	var dark := Color(0.08, 0.04, 0.03, col.a * 0.85)
	match kind:
		"attack":
			var a := c + Vector2(-0.6, 0.6) * s
			var b := c + Vector2(0.55, -0.55) * s
			ci.draw_line(a, b, dark, s * 0.24, true)
			ci.draw_line(a, b, col, s * 0.13, true)
			var tip := PackedVector2Array([b + Vector2(0.28, -0.28) * s, b + Vector2(-0.05, -0.2) * s, b + Vector2(0.2, 0.05) * s])
			ci.draw_colored_polygon(tip, Color(1.0, 0.85, 0.5, col.a))
			ci.draw_colored_polygon(flame_points(b + Vector2(-0.22, 0.22) * s, s * 0.32), Color(1.0, 0.45, 0.15, col.a * 0.9))
		"jump":
			for i in 2:
				var y := c.y + (0.15 - 0.4 * i) * s
				var pts := PackedVector2Array([Vector2(c.x - 0.5 * s, y + 0.3 * s), Vector2(c.x, y - 0.2 * s), Vector2(c.x + 0.5 * s, y + 0.3 * s)])
				ci.draw_polyline(pts, dark, s * 0.26, true)
				ci.draw_polyline(pts, col, s * 0.15, true)
		"dodge":
			for i in 3:
				var r := s * (0.25 + 0.2 * i)
				ci.draw_arc(c + Vector2(0.1 * s * i, 0), r, PI * (0.15 + 0.1 * i), PI * (1.3 + 0.1 * i), 16, col, s * 0.11, true)
			ci.draw_circle(c + Vector2(0.55, 0.1) * s, s * 0.12, col)
		"crescent":
			ci.draw_arc(c, s * 0.62, -PI * 0.8, PI * 0.8, 24, Color(1.0, 0.35, 0.1, col.a), s * 0.3, true)
			ci.draw_arc(c + Vector2(0.06 * s, 0), s * 0.6, -PI * 0.6, PI * 0.6, 24, Color(1.0, 0.82, 0.45, col.a), s * 0.12, true)
			ci.draw_colored_polygon(flame_points(c + Vector2(0.62, -0.1) * s, s * 0.35), Color(1.0, 0.55, 0.15, col.a))
		"skyfall":
			ci.draw_set_transform(c + Vector2(0, 0.6 * s), 0.0, Vector2(1, 0.38))
			ci.draw_arc(Vector2.ZERO, s * 0.7, 0, TAU, 28, Color(0.6, 0.9, 1.0, col.a), s * 0.18, true)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			ci.draw_rect(Rect2(c + Vector2(-0.26, -0.95) * s, Vector2(0.52, 1.5) * s), Color(0.55, 0.85, 1.0, col.a * 0.6))
			ci.draw_rect(Rect2(c + Vector2(-0.11, -0.95) * s, Vector2(0.22, 1.5) * s), Color(1, 1, 1, col.a))
		"meteor":
			var tail := PackedVector2Array([c + Vector2(0.25, -0.35) * s, c + Vector2(-0.9, 0.55) * s, c + Vector2(0.35, -0.05) * s])
			ci.draw_colored_polygon(tail, Color(1.0, 0.45, 0.1, col.a * 0.85))
			ci.draw_line(c + Vector2(-0.75, 0.75) * s, c + Vector2(0.4, -0.4) * s, Color(1.0, 0.9, 0.6, col.a), s * 0.1, true)
			ci.draw_circle(c + Vector2(0.4, -0.35) * s, s * 0.3, Color(1.0, 0.7, 0.25, col.a))
			ci.draw_circle(c + Vector2(0.42, -0.38) * s, s * 0.16, Color(1, 1, 0.9, col.a))
		"ult":
			ci.draw_colored_polygon(star_points(c, s * 0.95, s * 0.38, 8, 0.2), Color(1.0, 0.55, 0.15, col.a))
			ci.draw_colored_polygon(star_points(c, s * 0.6, s * 0.25, 4), Color(1.0, 0.92, 0.6, col.a))
			ci.draw_circle(c, s * 0.18, Color(1, 1, 1, col.a))
		"pause":
			ci.draw_rect(Rect2(c + Vector2(-0.4, -0.45) * s, Vector2(0.28, 0.9) * s), col)
			ci.draw_rect(Rect2(c + Vector2(0.12, -0.45) * s, Vector2(0.28, 0.9) * s), col)
		"atk":
			ci.draw_line(c + Vector2(-0.6, 0.6) * s, c + Vector2(0.6, -0.6) * s, col, s * 0.18, true)
			ci.draw_line(c + Vector2(-0.55, 0.15) * s, c + Vector2(-0.15, 0.55) * s, col, s * 0.18, true)
			ci.draw_colored_polygon(flame_points(c + Vector2(0.2, -0.1) * s, s * 0.5), Color(1.0, 0.5, 0.15, col.a * 0.7))
		"crit":
			ci.draw_colored_polygon(star_points(c, s * 0.9, s * 0.3, 4), col)
			ci.draw_circle(c, s * 0.2, Color(1, 1, 1, col.a))
		"hp", "heal":
			ci.draw_colored_polygon(heart_points(c, s * 0.85), Color(1.0, 0.3, 0.35, col.a))
			if kind == "heal":
				ci.draw_rect(Rect2(c + Vector2(-0.1, -0.35) * s, Vector2(0.2, 0.6) * s), Color(1, 1, 1, col.a))
				ci.draw_rect(Rect2(c + Vector2(-0.3, -0.15) * s, Vector2(0.6, 0.2) * s), Color(1, 1, 1, col.a))
		"mp":
			ci.draw_colored_polygon(flame_points(c, s * 0.95), Color(0.35, 0.7, 1.0, col.a))
			ci.draw_circle(c + Vector2(-0.12, 0.15) * s, s * 0.14, Color(1, 1, 1, col.a * 0.8))
		"rage":
			ci.draw_colored_polygon(flame_points(c, s * 1.0), Color(1.0, 0.35, 0.1, col.a))
			ci.draw_colored_polygon(flame_points(c + Vector2(0, 0.2) * s, s * 0.55), Color(1.0, 0.85, 0.4, col.a))
		"cdr":
			ci.draw_arc(c, s * 0.7, 0, TAU, 28, col, s * 0.14, true)
			ci.draw_line(c, c + Vector2(0, -0.45) * s, col, s * 0.12, true)
			ci.draw_line(c, c + Vector2(0.35, 0.1) * s, col, s * 0.12, true)
		_:
			ci.draw_circle(c, s * 0.5, col)
