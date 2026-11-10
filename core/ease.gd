class_name Ease
extends RefCounted
## Easing curves shared by core (displacement curves) and the rig player (ANIMATION.md §4).

const CODES := {"": 0, "linear": 0, "quadIn": 1, "quadOut": 2, "quadInOut": 3, "cubicIn": 4, "cubicOut": 5,
	"expoOut": 6, "backOut": 7, "sineInOut": 8, "step": 9}

static func code(name: String) -> int:
	return int(CODES.get(name, 0))

## Same curves as apply(), addressed by the integer code baked into a track (avoids String matching per frame).
static func apply_code(c: int, t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	match c:
		1:
			return t * t
		2:
			return 1.0 - (1.0 - t) * (1.0 - t)
		3:
			return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) * 0.5
		4:
			return t * t * t
		5:
			return 1.0 - pow(1.0 - t, 3.0)
		6:
			return 1.0 if t >= 1.0 else 1.0 - pow(2.0, -10.0 * t)
		7:
			var c1 := 1.70158
			var c3 := c1 + 1.0
			return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)
		8:
			return -(cos(PI * t) - 1.0) * 0.5
		9:
			return 1.0 if t >= 1.0 else 0.0
	return t

static func apply(name: String, t: float) -> float:
	return apply_code(code(name), t)

## Distance covered between two normalized times along a curve (for per-frame displacement).
static func delta(name: String, t0: float, t1: float) -> float:
	return apply(name, t1) - apply(name, t0)
