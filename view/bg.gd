class_name Bg
extends Node2D
## Parallax "Ember Forest" background. Uses bg/*.png when imported, else code-drawn layers.
## Layers are Parallax2D following the active Camera2D.

const TILE := 2560.0

static func build(parent: Node2D, world_len: float) -> Array:
	## returns [back_root, fore_root]
	var back := Node2D.new()
	back.name = "BgBack"
	parent.add_child(back)
	var fore := Node2D.new()
	fore.name = "BgFore"
	_layer(back, "bg/far.png", "far", world_len)
	_layer(back, "bg/mid.png", "mid", world_len)
	_layer(back, "bg/ground.png", "ground", world_len)
	_layer(fore, "bg/foreground.png", "fore", world_len)
	return [back, fore]

static func _layer(root: Node2D, path: String, which: String, _world_len: float) -> void:
	var e := Art.entry(path)
	var px := Parallax2D.new()
	px.scroll_scale = Vector2(float(e.get("parallax", {"far": 0.15, "mid": 0.45, "ground": 1.0, "fore": 1.25}[which])), 1.0)
	px.repeat_size = Vector2(TILE, 0)
	px.repeat_times = 3
	root.add_child(px)
	var tex := Art.real(path)
	if tex != null:
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.position = Vector2(0, float(e.get("y", 0.0)))
		var sz := Art.size_of(path, tex.get_size())
		s.scale = Vector2(sz.x / tex.get_width(), sz.y / tex.get_height())
		if which == "fore":
			s.modulate.a = 0.9
		px.add_child(s)
	else:
		var d := BgDraw.new()
		d.which = which
		px.add_child(d)

class BgDraw extends Node2D:
	var which := "far"

	func _draw() -> void:
		var r := CoreRng.new({"far": 11, "mid": 23, "ground": 37, "fore": 51}[which])
		match which:
			"far": _far(r)
			"mid": _mid(r)
			"ground": _ground(r)
			"fore": _fore(r)

	func _vgrad(rect: Rect2, a: Color, b: Color) -> void:
		draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
			PackedColorArray([a, a, b, b]))

	func _far(r: CoreRng) -> void:
		_vgrad(Rect2(0, 0, TILE, 420), Color(0.05, 0.05, 0.14), Color(0.22, 0.1, 0.16))
		for i in 90:
			var p := Vector2(r.range_f(0, TILE), r.range_f(0, 300))
			draw_circle(p, r.range_f(0.8, 2.0), Color(1, 0.95, 0.85, r.range_f(0.3, 0.9)))
		var m := Vector2(1700, 110)
		for k in 5:
			draw_circle(m, 60.0 + k * 22.0, Color(1.0, 0.75, 0.5, 0.05))
		draw_circle(m, 52, Color(1.0, 0.9, 0.75))
		draw_circle(m + Vector2(14, -8), 46, Color(0.98, 0.84, 0.66))
		for layer in 2:
			var pts := PackedVector2Array()
			pts.append(Vector2(0, 420))
			var x := 0.0
			var base := 300.0 + layer * 50.0
			while x <= TILE:
				pts.append(Vector2(x, base - absf(sin(x * 0.004 + layer * 2.0)) * (90.0 - layer * 30.0) - r.range_f(0, 20)))
				x += 80.0
			pts.append(Vector2(TILE, 420))
			draw_colored_polygon(pts, [Color(0.12, 0.08, 0.16), Color(0.09, 0.06, 0.1)][layer])

	func _mid(r: CoreRng) -> void:
		_vgrad(Rect2(0, 330, TILE, 120), Color(0.08, 0.05, 0.08, 0.0), Color(0.08, 0.05, 0.07, 1.0))
		var x := 40.0
		while x < TILE:
			var w := r.range_f(40, 80)
			var top := r.range_f(-40, 60)
			var col := Color(0.11, 0.07, 0.08).lerp(Color(0.16, 0.09, 0.08), r.randf())
			draw_colored_polygon(PackedVector2Array([Vector2(x - w * 0.4, top), Vector2(x + w * 0.4, top), Vector2(x + w * 0.6, 450), Vector2(x - w * 0.6, 450)]), col)
			# branch
			draw_line(Vector2(x, top + 120), Vector2(x + r.range_f(-120, 120), top + 40), col, 10.0)
			# canopy blob
			for k in 3:
				draw_circle(Vector2(x + r.range_f(-90, 90), top + r.range_f(-20, 40)), r.range_f(60, 110), Color(0.09, 0.06, 0.09))
			# glowing mushrooms / lanterns
			if r.chance(0.6):
				var mp := Vector2(x + r.range_f(-50, 50), 440)
				for k in 4:
					draw_circle(mp, 24.0 - k * 5.0, Color(1.0, 0.55, 0.2, 0.08 + k * 0.05))
				draw_circle(mp, 6, Color(1.0, 0.75, 0.4))
			x += r.range_f(170, 300)

	func _ground(r: CoreRng) -> void:
		_vgrad(Rect2(0, 440, TILE, 280), Color(0.24, 0.16, 0.13), Color(0.13, 0.08, 0.08))
		_vgrad(Rect2(0, 440, TILE, 24), Color(0.08, 0.05, 0.06), Color(0.24, 0.16, 0.13, 0.0))
		# warm light pools
		for i in 10:
			var c := Vector2(r.range_f(0, TILE), r.range_f(520, 650))
			draw_set_transform(c, 0.0, Vector2(1.0, 0.35))
			for k in 4:
				draw_circle(Vector2.ZERO, 220.0 - k * 45.0, Color(1.0, 0.55, 0.25, 0.03))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i in 160:
			var p := Vector2(r.range_f(0, TILE), r.range_f(470, 715))
			draw_set_transform(p, 0.0, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, r.range_f(3, 10), Color(0.32, 0.22, 0.17, r.range_f(0.4, 0.9)))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i in 70:
			var p := Vector2(r.range_f(0, TILE), r.range_f(460, 700))
			for k in 3:
				draw_line(p, p + Vector2(r.range_f(-8, 8), -r.range_f(8, 20)), Color(0.3, 0.32, 0.16, 0.8), 2.0)
		for i in 30:
			var p := Vector2(r.range_f(0, TILE), r.range_f(480, 700))
			draw_circle(p, 2.0, Color(1.0, 0.6, 0.25, 0.8))

	func _fore(r: CoreRng) -> void:
		var x := 0.0
		while x < TILE:
			if r.chance(0.35):
				var w := r.range_f(80, 160)
				for k in 9:
					var bx := x + r.range_f(0, w)
					var hgt := r.range_f(40, 110)
					draw_colored_polygon(PackedVector2Array([Vector2(bx - 8, 730), Vector2(bx + r.range_f(-20, 20), 730 - hgt), Vector2(bx + 8, 730)]), Color(0.04, 0.03, 0.04))
			x += r.range_f(180, 360)
