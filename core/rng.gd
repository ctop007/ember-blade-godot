class_name CoreRng
extends RefCounted
## Seeded mulberry32 RNG. Pure logic, no engine randomness.

var state: int = 0

func _init(seed_value: int = 1) -> void:
	state = seed_value & 0xFFFFFFFF

func next_u32() -> int:
	state = (state + 0x6D2B79F5) & 0xFFFFFFFF
	var t: int = state
	t = _imul(t ^ (t >> 15), t | 1)
	t ^= (t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF
	t &= 0xFFFFFFFF
	return (t ^ (t >> 14)) & 0xFFFFFFFF

static func _imul(a: int, b: int) -> int:
	return (a * b) & 0xFFFFFFFF

func randf() -> float:
	return float(next_u32()) / 4294967296.0

func range_f(a: float, b: float) -> float:
	return a + (b - a) * randf()

func range_i(a: int, b: int) -> int:
	## inclusive a..b
	return a + int(randf() * float(b - a + 1))

func chance(p: float) -> bool:
	return randf() < p

func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[int(randf() * arr.size()) % arr.size()]

func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = int(randf() * float(i + 1))
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func weighted(keys: Array, weights: Array) -> Variant:
	var total := 0.0
	for w in weights:
		total += float(w)
	var r := randf() * total
	for i in keys.size():
		r -= float(weights[i])
		if r <= 0.0:
			return keys[i]
	return keys[keys.size() - 1]
