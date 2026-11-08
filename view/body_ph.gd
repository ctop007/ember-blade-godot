class_name BodyPH
extends Node2D
## Code-drawn placeholder characters (facing right, feet at origin). Replaced by PNGs once ready.

const OL := Color(0.07, 0.04, 0.06)
var kind := "hero"
var pose := "idle"

func _draw() -> void:
	match kind:
		"hero": _hero()
		"imp": _imp()
		"lantern": _lantern()
		"brute": _brute()
		"boss": _boss()

func _ell(c: Vector2, r: Vector2, col: Color, ol := 3.0) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, r.y / r.x))
	draw_circle(Vector2.ZERO, r.x + ol, OL)
	draw_circle(Vector2.ZERO, r.x, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _poly(pts: PackedVector2Array, col: Color, ol := 3.0) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, OL, ol * 2.0, true)
	draw_colored_polygon(pts, col)

func _limb(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	draw_line(a, b, OL, w + 5.0, true)
	draw_line(a, b, col, w, true)

# ------------------------------------------------------------------ hero (Deng, spear girl)
func _hero() -> void:
	var skin := Color(1.0, 0.86, 0.76)
	var cloth := Color(0.86, 0.32, 0.2)
	var cloth2 := Color(0.98, 0.72, 0.32)
	var hair := Color(0.2, 0.16, 0.28)
	var spear_a := -0.15
	var hand := Vector2(14, -58)
	var crouch := 0.0
	match pose:
		"run": spear_a = 0.2; hand = Vector2(10, -56)
		"attack1": spear_a = -0.9; hand = Vector2(24, -66)
		"attack2": spear_a = 0.75; hand = Vector2(26, -52)
		"attack3", "thrust": spear_a = 0.0; hand = Vector2(34, -58)
		"charge": spear_a = 0.05; hand = Vector2(-6, -56); crouch = 6.0
		"jump": spear_a = -0.6; hand = Vector2(10, -64)
		"slam": spear_a = 1.35; hand = Vector2(18, -50)
		"cast": spear_a = -1.4; hand = Vector2(10, -78)
		"hurt": spear_a = -0.5; hand = Vector2(-4, -54)
		"dodge": spear_a = 0.3; crouch = 18.0
		"dead": spear_a = 0.0
	draw_set_transform(Vector2(0, crouch), 0.0, Vector2(1, 1.0 - crouch / 140.0))
	# back hair
	_poly(PackedVector2Array([Vector2(-26, -112), Vector2(-40, -70), Vector2(-30, -60), Vector2(-14, -92)]), hair)
	# legs
	var stride := 10.0 if pose == "run" else 6.0
	_limb(Vector2(-6, -34), Vector2(-stride, -2), 9.0, Color(0.25, 0.2, 0.3))
	_limb(Vector2(6, -34), Vector2(stride + 2, -2), 9.0, Color(0.25, 0.2, 0.3))
	_ell(Vector2(-stride, -3), Vector2(8, 4), Color(0.35, 0.18, 0.12), 2.0)
	_ell(Vector2(stride + 3, -3), Vector2(8, 4), Color(0.35, 0.18, 0.12), 2.0)
	# skirt/body
	_poly(PackedVector2Array([Vector2(-14, -74), Vector2(14, -74), Vector2(24, -30), Vector2(-24, -30)]), cloth)
	draw_colored_polygon(PackedVector2Array([Vector2(-20, -38), Vector2(20, -38), Vector2(23, -31), Vector2(-23, -31)]), cloth2)
	draw_rect(Rect2(-14, -58, 28, 5), cloth2)
	# scarf (flame-colored)
	_poly(PackedVector2Array([Vector2(-12, -76), Vector2(12, -76), Vector2(-6, -68), Vector2(-34, -60), Vector2(-28, -70)]), Color(1.0, 0.5, 0.15))
	# spear (behind arm)
	var dir := Vector2(cos(spear_a), sin(spear_a))
	var a := hand - dir * 46.0
	var b := hand + dir * 62.0
	draw_line(a, b, OL, 8.0, true)
	draw_line(a, b, Color(0.55, 0.32, 0.18), 4.0, true)
	var perp := Vector2(-dir.y, dir.x)
	_poly(PackedVector2Array([b + dir * 26.0, b + perp * 6.0, b - dir * 4.0, b - perp * 6.0]), Color(0.92, 0.95, 1.0), 2.0)
	draw_colored_polygon(UiDraw.flame_points(b - dir * 6.0 + perp * 3.0, 9.0), Color(1.0, 0.55, 0.15, 0.9))
	# arm
	_limb(Vector2(4, -68), hand, 7.0, skin)
	# head (big, chibi)
	_ell(Vector2(2, -98), Vector2(24, 24), skin)
	# hair front + bangs
	_poly(PackedVector2Array([Vector2(-24, -100), Vector2(-20, -122), Vector2(4, -128), Vector2(26, -114), Vector2(26, -98), Vector2(14, -108), Vector2(2, -100), Vector2(-8, -110)]), hair)
	# hair ornament (ember star)
	draw_colored_polygon(UiDraw.star_points(Vector2(-14, -118), 7.0, 3.0, 4), Color(1.0, 0.75, 0.3))
	# eye
	if pose == "hurt" or pose == "dead":
		draw_line(Vector2(10, -98), Vector2(18, -94), OL, 3.0)
	else:
		_ell(Vector2(14, -96), Vector2(4, 6), Color(0.95, 0.5, 0.15), 1.5)
		draw_circle(Vector2(15, -98), 1.6, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ------------------------------------------------------------------ imp
func _imp() -> void:
	var c := Color(0.5, 0.17, 0.14)
	var ember := Color(1.0, 0.5, 0.15)
	var arm_a := Vector2(26, -36)
	if pose == "windup":
		arm_a = Vector2(-6, -66)
	elif pose == "attack":
		arm_a = Vector2(40, -26)
	var step := 6.0 if pose == "run" else 3.0
	_limb(Vector2(-6, -18), Vector2(-step - 4, -1), 7.0, c.darkened(0.3))
	_limb(Vector2(6, -18), Vector2(step + 4, -1), 7.0, c.darkened(0.3))
	_ell(Vector2(0, -34), Vector2(22, 24), c)
	draw_line(Vector2(-8, -40), Vector2(2, -28), ember, 2.0)
	draw_line(Vector2(6, -44), Vector2(12, -32), ember, 2.0)
	_ell(Vector2(4, -62), Vector2(18, 15), c.lightened(0.08))
	_poly(PackedVector2Array([Vector2(-8, -72), Vector2(-16, -92), Vector2(-2, -76)]), Color(0.25, 0.1, 0.1), 2.0)
	_poly(PackedVector2Array([Vector2(10, -74), Vector2(16, -94), Vector2(18, -72)]), Color(0.25, 0.1, 0.1), 2.0)
	_ell(Vector2(12, -64), Vector2(4, 4), Color(1.0, 0.9, 0.3), 1.5)
	_ell(Vector2(2, -64), Vector2(3, 3), Color(1.0, 0.9, 0.3), 1.5)
	draw_line(Vector2(4, -54), Vector2(16, -55), OL, 2.0)
	_limb(Vector2(10, -40), arm_a, 6.0, c.lightened(0.1))
	for i in 3:
		var d := (arm_a - Vector2(10, -40)).normalized()
		var p := Vector2(-d.y, d.x)
		draw_line(arm_a, arm_a + d * 10.0 + p * (i - 1) * 5.0, Color(0.95, 0.9, 0.8), 2.5, true)
	draw_colored_polygon(UiDraw.flame_points(Vector2(-2, -94), 10.0), Color(1, 0.55, 0.15, 0.8))

# ------------------------------------------------------------------ lantern
func _lantern() -> void:
	var paper := Color(0.95, 0.55, 0.22)
	var glow := 0.9 if pose == "windup" else 0.55
	draw_circle(Vector2(0, -54), 46.0, Color(1.0, 0.6, 0.2, 0.12 + 0.12 * glow))
	draw_line(Vector2(0, -102), Vector2(0, -116), OL, 3.0)
	draw_rect(Rect2(-16, -104, 32, 10), Color(0.3, 0.17, 0.1))
	_ell(Vector2(0, -56), Vector2(30, 40), paper)
	for i in 3:
		var x := -14.0 + 14.0 * i
		draw_arc(Vector2(x * 0.2, -56), 36.0, -PI * 0.5 - 0.6 + 0.6 * i * 0.0, -PI * 0.5 + 0.6, 2, Color(0, 0, 0, 0))
		draw_line(Vector2(x, -92), Vector2(x * 1.25, -56), Color(0.7, 0.3, 0.1), 2.0)
		draw_line(Vector2(x * 1.25, -56), Vector2(x, -20), Color(0.7, 0.3, 0.1), 2.0)
	draw_circle(Vector2(4, -56), 18.0, Color(1.0, 0.92, 0.5, glow))
	_poly(PackedVector2Array([Vector2(-6, -66), Vector2(4, -62), Vector2(-6, -58)]), OL, 1.0)
	_poly(PackedVector2Array([Vector2(10, -66), Vector2(20, -62), Vector2(10, -58)]), OL, 1.0)
	var mouth := 8.0 if pose == "windup" or pose == "throw" else 3.0
	draw_rect(Rect2(0, -48, 16, mouth), OL)
	draw_rect(Rect2(-16, -18, 32, 8), Color(0.3, 0.17, 0.1))
	for i in 3:
		draw_line(Vector2(-8 + 8 * i, -10), Vector2(-8 + 8 * i, 0), Color(0.9, 0.4, 0.15), 2.0)

# ------------------------------------------------------------------ brute
func _brute() -> void:
	var bark := Color(0.4, 0.27, 0.17)
	var moss := Color(0.35, 0.5, 0.22)
	var lowc := 10.0 if pose == "windup" or pose == "charge" else 0.0
	draw_set_transform(Vector2(lowc, lowc * 0.5), 0.15 if pose == "charge" else 0.0, Vector2.ONE)
	_limb(Vector2(-16, -30), Vector2(-20, -2), 16.0, bark.darkened(0.3))
	_limb(Vector2(16, -30), Vector2(22, -2), 16.0, bark.darkened(0.3))
	_poly(PackedVector2Array([Vector2(-40, -110), Vector2(36, -116), Vector2(46, -60), Vector2(30, -26), Vector2(-34, -26), Vector2(-46, -64)]), bark)
	for i in 4:
		draw_line(Vector2(-30 + i * 18, -104), Vector2(-26 + i * 16, -34), bark.darkened(0.35), 3.0)
	_ell(Vector2(-30, -110), Vector2(18, 10), moss, 2.0)
	_ell(Vector2(28, -114), Vector2(16, 9), moss, 2.0)
	_ell(Vector2(20, -92), Vector2(5, 4), Color(0.6, 1.0, 0.4), 1.5)
	_ell(Vector2(34, -92), Vector2(4, 3), Color(0.6, 1.0, 0.4), 1.5)
	var fist := Vector2(52, -54) if pose == "charge" else Vector2(44, -44)
	_limb(Vector2(30, -86), fist, 14.0, bark.lightened(0.1))
	_ell(fist, Vector2(13, 12), bark.darkened(0.1))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ------------------------------------------------------------------ boss (ash knight)
func _boss() -> void:
	var armor := Color(0.42, 0.42, 0.46)
	var armor2 := Color(0.25, 0.24, 0.28)
	var ember := Color(1.0, 0.4, 0.15)
	var sword_a := 0.9
	var hand := Vector2(40, -110)
	match pose:
		"sweep_windup": sword_a = -2.3; hand = Vector2(-20, -140)
		"sweep": sword_a = 0.25; hand = Vector2(70, -100)
		"leap": sword_a = -1.6; hand = Vector2(20, -170)
		"slam": sword_a = 1.4; hand = Vector2(60, -70)
		"summon": sword_a = -1.57; hand = Vector2(36, -150)
		"walk": sword_a = 0.7
	# cape
	_poly(PackedVector2Array([Vector2(-30, -170), Vector2(-74, -20), Vector2(-20, -30), Vector2(10, -160)]), Color(0.3, 0.08, 0.08))
	_limb(Vector2(-18, -60), Vector2(-24, -4), 20.0, armor2)
	_limb(Vector2(18, -60), Vector2(26, -4), 20.0, armor2)
	_poly(PackedVector2Array([Vector2(-44, -170), Vector2(44, -170), Vector2(38, -60), Vector2(-38, -60)]), armor)
	draw_line(Vector2(0, -164), Vector2(0, -70), armor2, 4.0)
	for i in 3:
		draw_line(Vector2(-30, -140 + 26 * i), Vector2(-14, -128 + 26 * i), ember, 2.0)
	_ell(Vector2(-44, -166), Vector2(22, 16), armor2)
	_ell(Vector2(44, -166), Vector2(22, 16), armor2)
	# helmet
	_poly(PackedVector2Array([Vector2(-26, -176), Vector2(28, -176), Vector2(30, -214), Vector2(0, -228), Vector2(-28, -214)]), armor)
	_poly(PackedVector2Array([Vector2(-20, -220), Vector2(-40, -246), Vector2(-14, -226)]), armor2, 2.0)
	_poly(PackedVector2Array([Vector2(20, -220), Vector2(40, -246), Vector2(14, -226)]), armor2, 2.0)
	draw_rect(Rect2(-6, -204, 32, 7), Color(1.0, 0.35, 0.15))
	draw_rect(Rect2(-6, -202, 32, 3), Color(1.0, 0.9, 0.5))
	# greatsword
	var dir := Vector2(cos(sword_a), sin(sword_a))
	var perp := Vector2(-dir.y, dir.x)
	var base := hand + dir * 14.0
	var tip := hand + dir * 150.0
	_poly(PackedVector2Array([base + perp * 11.0, tip + perp * 4.0, tip + dir * 18.0, tip - perp * 4.0, base - perp * 11.0]), Color(0.3, 0.3, 0.34))
	draw_line(base + dir * 10.0, tip, ember, 3.0, true)
	draw_line(hand - perp * 22.0, hand + perp * 22.0, OL, 10.0)
	draw_line(hand - perp * 20.0, hand + perp * 20.0, Color(0.6, 0.45, 0.2), 6.0)
	_limb(Vector2(30, -150), hand, 16.0, armor2)
