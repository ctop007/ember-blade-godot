class_name Art
extends RefCounted
## Texture access by manifest path ("fx/glow.png"). Real asset if imported under res://assets/,
## otherwise a procedurally generated white placeholder (fx) or null (chars/ui -> code-drawn).

static var _cache: Dictionary = {}
static var _gen_queue: Array = [
	"fx/glow.png", "fx/spark.png", "fx/ember.png", "fx/hit_spark.png", "fx/flash_star.png",
	"fx/crescent_arc.png", "fx/fire_ring.png", "fx/warn_circle.png", "fx/shock_ring.png",
	"fx/light_pillar.png", "fx/comet_head.png", "fx/comet_trail.png", "fx/thrust_beam.png",
	"fx/slash_trail.png", "fx/warn_bar.png", "fx/warn_fan.png", "fx/rock_debris.png",
	"fx/smoke.png", "fx/fireball.png", "fx/meteor.png", "chars/shadow.png",
]

static var _manifest: Dictionary = {}

## Manifest entries keyed by path (copied from _shared/assets/manifest.json by tools/sync_assets.sh).
static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var f := FileAccess.open("res://assets/manifest.json", FileAccess.READ)
		if f != null:
			var m: Variant = JSON.parse_string(f.get_as_text())
			if m is Dictionary:
				for it in m.get("assets", []):
					_manifest[String(it.path)] = it
		if _manifest.is_empty():
			_manifest["_none"] = {}
	return _manifest

static func entry(path: String) -> Dictionary:
	return manifest().get(path, {})

static func size_of(path: String, fallback: Vector2) -> Vector2:
	var s: Array = entry(path).get("size", [])
	return Vector2(float(s[0]), float(s[1])) if s.size() == 2 else fallback

static func anchor_of(path: String, fallback: Vector2) -> Vector2:
	var a: Array = entry(path).get("anchor", [])
	return Vector2(float(a[0]), float(a[1])) if a.size() == 2 else fallback

static func display_scale(path: String, fallback: float) -> float:
	return float(entry(path).get("displayScale", fallback))

static func has_real(path: String) -> bool:
	return ResourceLoader.exists("res://assets/" + path)

static func real(path: String) -> Texture2D:
	var key := "R:" + path
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = null
	if has_real(path):
		t = load("res://assets/" + path)
	_cache[key] = t
	return t

## Always returns a texture (real or placeholder) for fx / shadow paths.
static func fx(path: String) -> Texture2D:
	var t := real(path)
	if t != null:
		return t
	var key := "G:" + path
	if not _cache.has(key):
		_cache[key] = _generate(path)
	return _cache[key]

static func gen_count() -> int:
	return _gen_queue.size()

## Generate one placeholder per call (for loading-screen progress). Returns false when finished.
static func gen_step(i: int) -> bool:
	if i >= _gen_queue.size():
		return false
	fx(_gen_queue[i])
	return true

# ------------------------------------------------------------------ generators
static func _img(w: int, h: int, f: Callable) -> ImageTexture:
	var data := PackedByteArray()
	data.resize(w * h * 4)
	var idx := 0
	for y in h:
		var v := (float(y) + 0.5) / float(h)
		for x in w:
			var u := (float(x) + 0.5) / float(w)
			var a: float = clampf(f.call(u, v), 0.0, 1.0)
			data[idx] = 255
			data[idx + 1] = 255
			data[idx + 2] = 255
			data[idx + 3] = int(a * 255.0)
			idx += 4
	var im := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	return ImageTexture.create_from_image(im)

static func _ring(u: float, v: float, inner: float, outer: float, soft: float) -> float:
	var dx := (u - 0.5) * 2.0
	var dy := (v - 0.5) * 2.0
	var d := sqrt(dx * dx + dy * dy)
	return smoothstep(inner - soft, inner, d) * (1.0 - smoothstep(outer, outer + soft, d))

static func _generate(path: String) -> Texture2D:
	match path:
		"fx/glow.png":
			return _img(64, 64, func(u: float, v: float) -> float:
				var d := Vector2(u - 0.5, v - 0.5).length() * 2.0
				return pow(maxf(0.0, 1.0 - d), 2.2))
		"fx/spark.png", "fx/smoke.png":
			return _img(32, 32, func(u: float, v: float) -> float:
				var d := Vector2(u - 0.5, v - 0.5).length() * 2.0
				return pow(maxf(0.0, 1.0 - d), 1.4))
		"fx/ember.png":
			return _img(32, 32, func(u: float, v: float) -> float:
				var d := Vector2(u - 0.5, v - 0.5).length() * 2.0
				return maxf(1.0 - smoothstep(0.15, 0.35, d), pow(maxf(0.0, 1.0 - d), 3.0) * 0.6))
		"fx/hit_spark.png":
			return _img(128, 128, func(u: float, v: float) -> float:
				var p := Vector2(u - 0.5, v - 0.5) * 2.0
				var d := p.length()
				var a := atan2(p.y, p.x)
				var rays := pow(absf(cos(a * 4.0)), 18.0) * (1.0 - d) * 1.4
				var core := pow(maxf(0.0, 1.0 - d * 2.2), 1.5)
				return maxf(rays, core))
		"fx/flash_star.png":
			return _img(128, 128, func(u: float, v: float) -> float:
				var p := Vector2(u - 0.5, v - 0.5) * 2.0
				var sx := maxf(0.0, 1.0 - absf(p.x)) * maxf(0.0, 1.0 - absf(p.y) * 14.0)
				var sy := maxf(0.0, 1.0 - absf(p.y)) * maxf(0.0, 1.0 - absf(p.x) * 14.0)
				var core := pow(maxf(0.0, 1.0 - p.length() * 2.5), 2.0)
				return maxf(maxf(sx, sy), core))
		"fx/crescent_arc.png":
			# crescent band around center, thick in the middle (pointing right), tapered ends
			return _img(256, 256, func(u: float, v: float) -> float:
				var p := Vector2(u - 0.5, v - 0.5) * 2.0
				var d := p.length()
				var a := absf(atan2(p.y, p.x))           # 0 at right
				if a > 2.4:
					return 0.0
				var th := 0.26 * cos(a / 2.4 * PI * 0.5)  # thickness
				var outer := 0.92
				var inner := outer - th
				var band := smoothstep(inner - 0.03, inner + 0.04, d) * (1.0 - smoothstep(outer - 0.02, outer + 0.02, d))
				var edge := 1.0 - smoothstep(0.0, 0.08, absf(d - outer + 0.03))
				return band * (0.55 + 0.45 * edge) * (1.0 - smoothstep(1.9, 2.4, a)))
		"fx/fire_ring.png", "fx/shock_ring.png":
			return _img(256, 128, func(u: float, v: float) -> float: return _ring(u, v, 0.78, 0.92, 0.07))
		"fx/warn_circle.png":
			return _img(256, 128, func(u: float, v: float) -> float:
				var dx := (u - 0.5) * 2.0
				var dy := (v - 0.5) * 2.0
				var d := sqrt(dx * dx + dy * dy)
				var edge := _ring(u, v, 0.86, 0.96, 0.04)
				return maxf(edge, (1.0 - smoothstep(0.9, 0.96, d)) * 0.28))
		"fx/light_pillar.png":
			return _img(64, 512, func(u: float, v: float) -> float:
				var x := absf(u - 0.5) * 2.0
				var core := pow(maxf(0.0, 1.0 - x), 2.5)
				var hot := (1.0 - smoothstep(0.0, 0.18, x))
				var fade_top := smoothstep(0.0, 0.25, v)
				return maxf(core * 0.8, hot) * fade_top)
		"fx/comet_head.png":
			return _img(128, 64, func(u: float, v: float) -> float:
				var p := Vector2((u - 0.72) * 2.0, (v - 0.5) * 2.0)
				if p.x < 0.0:
					p.x *= 0.35
				var d := p.length()
				return pow(maxf(0.0, 1.0 - d), 1.3) * 1.4)
		"fx/comet_trail.png", "fx/thrust_beam.png":
			return _img(256, 64, func(u: float, v: float) -> float:
				var w := 0.15 + 0.85 * u
				var y := absf(v - 0.5) * 2.0 / w
				return pow(maxf(0.0, 1.0 - y), 1.6) * pow(u, 1.3))
		"fx/slash_trail.png":
			return _img(256, 128, func(u: float, v: float) -> float:
				var p := Vector2((u - 0.3) * 1.6, (v - 1.0) * 1.6)
				var d := p.length()
				var ang := atan2(-p.y, p.x)
				var band := smoothstep(0.95, 1.08, d) * (1.0 - smoothstep(1.32, 1.4, d))
				var along := smoothstep(0.2, 1.4, ang) * (1.0 - smoothstep(2.3, 2.8, ang))
				return band * along)
		"fx/warn_bar.png":
			return _img(256, 32, func(u: float, v: float) -> float:
				var y := absf(v - 0.5) * 2.0
				var edge := smoothstep(0.75, 0.9, y) * (1.0 - smoothstep(0.92, 1.0, y))
				return maxf(edge, 0.3) * (1.0 - smoothstep(0.92, 1.0, u)))
		"fx/warn_fan.png":
			return _img(256, 256, func(u: float, v: float) -> float:
				var p := Vector2(u, (v - 0.5) * 2.0)
				var d := p.length()
				var a := absf(atan2(p.y, p.x))
				var inside := (1.0 - smoothstep(0.93, 1.0, d)) * (1.0 - smoothstep(PI / 3.0 - 0.03, PI / 3.0, a))
				var edge := smoothstep(0.86, 0.95, d)
				return inside * maxf(0.3, edge))
		"fx/rock_debris.png":
			return _img(32, 32, func(u: float, v: float) -> float:
				var p := Vector2(u - 0.5, v - 0.5) * 2.0
				var a := atan2(p.y, p.x)
				var r := 0.7 + 0.2 * cos(a * 3.0 + 1.0)
				return 1.0 - smoothstep(r - 0.08, r, p.length()))
		"fx/fireball.png":
			return _img(64, 64, func(u: float, v: float) -> float:
				var d := Vector2(u - 0.5, v - 0.5).length() * 2.0
				return maxf(1.0 - smoothstep(0.3, 0.5, d), pow(maxf(0.0, 1.0 - d), 1.5)))
		"fx/meteor.png":
			return _img(128, 128, func(u: float, v: float) -> float:
				# head at lower-right, tail to upper-left (flying 45deg down-right)
				var p := Vector2(u - 0.72, v - 0.72)
				var axis := Vector2(0.7071, 0.7071)
				var along := p.dot(axis)
				var perp := absf(p.dot(Vector2(-0.7071, 0.7071)))
				var head := pow(maxf(0.0, 1.0 - Vector2(along, perp).length() * 6.0), 1.2)
				var tail := 0.0
				if along < 0.0:
					var w := 0.09 * (1.0 + along * 0.9)
					tail = maxf(0.0, 1.0 - perp / maxf(0.01, w)) * maxf(0.0, 1.0 + along * 1.3)
				return maxf(head * 1.3, tail * 0.8))
		"chars/shadow.png":
			return _img(128, 32, func(u: float, v: float) -> float:
				var d := Vector2((u - 0.5) * 2.0, (v - 0.5) * 2.0).length()
				return (1.0 - smoothstep(0.55, 1.0, d)) * 0.55)
	return _img(8, 8, func(_u: float, _v: float) -> float: return 1.0)
