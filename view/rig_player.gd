class_name RigPlayer
extends Node2D
## ANIMATION.md §4.1. Angles in JSON are degrees; Godot transforms use radians.
## No automatic _process: caller supplies gameplay time so hitstop freezes everything.
## Every clip is precompiled once into flat per-property tracks (times/values/ease codes + mode),
## so the per-frame path is allocation-free array indexing instead of dictionary/property scans.
signal event_fired(event: Dictionary)
var rig: Dictionary
var animations: Dictionary
var bones: Dictionary = {}
var children_of: Dictionary = {}
var bone_order: Array = []
var bone_parent: Dictionary = {}
var slots: Dictionary = {}
var setup_pose: Dictionary = {}
var pose: Dictionary = {}
var world: Dictionary = {}
var textures: Dictionary = {}
var atlas: Texture2D = null
var atlas_regions: Dictionary = {}
var spring_state: Dictionary = {}
var spring_chains: Array = []          # [{k, d, g, bones: [[id, length, axis], ...]}] precomputed
var clip_tracks: Dictionary = {}      # clip -> Array of tracks
var reset_pairs: Array = []           # tracks/props reset to setup each frame
var blend_pairs: Array = []           # [key, prop, setup] blended during a crossfade
var touched: Array = []               # tracks of the previous clip
var slot_static_order: Array = []
var z_animated := false
var clip := ""
var clock := 0.0
var duration := 1.0
var source_knots: Array = []
var target_knots: Array = []
var blend_from: Dictionary = {}
var blend_time := 0.0
var blend_duration := 0.08
var base_path := ""
var unit := 1.0
var debug_blocks := false
## Per-frame instrumentation (bench only): time spent inside advance()/draw and drawn part count.
static var sim_us := 0
static var draw_us := 0
static var parts_drawn := 0
static var eval_us := 0
static var world_us := 0
static var spring_us := 0

func configure(definition: Dictionary, clips: Dictionary, directory := "", blocks := false) -> void:
	rig = definition
	animations = clips
	base_path = directory
	debug_blocks = blocks
	atlas = null
	atlas_regions.clear()
	if directory != "" and not blocks:
		var aj := directory.path_join("atlas.json")
		var ap := directory.path_join("atlas.png")
		if FileAccess.file_exists(aj) and ResourceLoader.exists(ap):
			atlas_regions = JSON.parse_string(FileAccess.get_file_as_string(aj))
			atlas = load(ap)
	unit = float(rig.get("unitsPerPixel", 1.0))
	scale = Vector2.ONE * float(rig.get("displayScale", 0.6))
	bones.clear()
	children_of.clear()
	bone_parent.clear()
	bone_order.clear()
	slots.clear()
	setup_pose.clear()
	spring_state.clear()
	clip_tracks.clear()
	blend_from.clear()
	blend_pairs.clear()
	reset_pairs.clear()
	touched.clear()
	z_animated = false
	for b in rig.bones:
		bones[b.name] = b
		var par: Variant = b.get("parent")
		bone_parent[b.name] = String(par) if par != null else ""
		if par != null:
			if not children_of.has(par):
				children_of[par] = []
			children_of[par].append(b.name)
		setup_pose[b.name] = {"x": float(b.get("x", 0)), "y": float(b.get("y", 0)), "rot": float(b.get("rot", 0)), "sx": float(b.get("sx", 1)), "sy": float(b.get("sy", 1)), "alpha": float(b.get("alpha", 1)), "z": float(b.get("z", 0))}
	for s in rig.slots:
		slots[s.name] = s
		setup_pose["slot:" + s.name] = {"image": s.get("image", ""), "alpha": float(s.get("alpha", 1)), "z": float(s.get("z", 0))}
	var visited := {}
	for id in bones:
		_order_bone(String(id), visited)
	_compile_springs()
	_compile_clips()
	slot_static_order = slots.keys()
	slot_static_order.sort_custom(func(a, b): return float(setup_pose["slot:" + a].z) + float(setup_pose[slots[a].bone].z) < float(setup_pose["slot:" + b].z) + float(setup_pose[slots[b].bone].z))
	pose = setup_pose.duplicate(true)
	_build_world()
	queue_redraw()

func _order_bone(id: String, visited: Dictionary) -> void:
	if visited.has(id):
		return
	visited[id] = true
	var par: String = bone_parent.get(id, "")
	if par != "" and bones.has(par):
		_order_bone(par, visited)
	bone_order.append(id)

## Precompute each spring bone's rest length and direction once (ANIMATION.md §4.1: length = distance to next bone).
func _compile_springs() -> void:
	spring_chains.clear()
	for chain in rig.get("springs", []):
		var names: Array = chain.bones
		var meta: Array = []
		var previous_length := 20.0
		for i in names.size():
			var id: String = names[i]
			var length := previous_length
			var axis := 0.0
			if i + 1 < names.size():
				var next: Dictionary = setup_pose[names[i + 1]]
				var offset := Vector2(next.x, next.y) * unit
				length = offset.length()
				axis = offset.angle()
			else:
				length = float(bones[id].get("length", previous_length / unit)) * unit
			previous_length = length
			meta.append([id, length, axis])
		spring_chains.append({"k": float(chain.get("stiffness", 120)), "d": float(chain.get("damping", 12)), "g": float(chain.get("gravity", 0)), "bones": meta})

## Flat track layout: [key, prop, mode, setup, times, values, eases, images]
## mode 0 = relative add (rot/x/y), 1 = relative multiply (sx/sy), 2 = absolute float,
## 3 = discrete float (z), 4 = discrete image string.
func _compile_clips() -> void:
	var relative: bool = String(rig.get("keyMode", "relative")) != "absolute"
	for name in animations:
		var a: Dictionary = animations[name]
		var tracks: Array = []
		for group in ["bones", "slots"]:
			var tg: Dictionary = a.get(group, {})
			for id in tg:
				var key: String = ("slot:" if group == "slots" else "") + String(id)
				if not setup_pose.has(key):
					continue
				var by_prop := {}
				for k in tg[id]:
					for p in k:
						if p == "t" or p == "ease":
							continue
						if String(p) == "z":
							z_animated = true
						if not by_prop.has(p):
							by_prop[p] = []
						by_prop[p].append(k)
				for prop in by_prop:
					var list: Array = by_prop[prop]
					var times := PackedFloat32Array()
					var values := PackedFloat32Array()
					var eases := PackedByteArray()
					var images: Array = []
					var is_img: bool = String(prop) == "image"
					for k in list:
						times.append(float(k.t))
						if is_img:
							images.append(String(k[prop]))
						else:
							values.append(float(k[prop]))
						eases.append(Ease.code(String(k.get("ease", "linear"))))
					var mode := 2
					if is_img:
						mode = 4
					elif String(prop) == "z":
						mode = 3
					elif relative and (prop == "rot" or prop == "x" or prop == "y"):
						mode = 0
					elif relative and (prop == "sx" or prop == "sy"):
						mode = 1
					tracks.append([key, String(prop), mode, setup_pose[key][prop], times, values, eases, images])
		clip_tracks[name] = tracks

## target duration + optional hitAt. windup follows the original pre-hit ratio.
func play(name: String, actual_duration := -1.0, hit_at := -1.0, fade := 0.08, restart := false) -> void:
	if not animations.has(name) or (clip == name and not restart):
		return
	blend_from = pose.duplicate(true)
	blend_time = 0.0
	blend_duration = clampf(fade, 0.06, 0.12)
	clip = name
	clock = 0.0
	var a: Dictionary = animations[clip]
	var src_duration := float(a.duration)
	var phases: Dictionary = a.get("phases", {})
	var recovery := float(phases.get("recovery", src_duration))
	var actual := actual_duration if actual_duration > 0.0 else recovery
	source_knots = [0.0]
	target_knots = [0.0]
	var active := float(phases.get("active", 0))
	if hit_at > 0.0 and active > 0.0 and active < recovery and hit_at < actual:
		source_knots.append(active)
		target_knots.append(hit_at)
	source_knots.append(recovery)
	target_knots.append(actual)
	if src_duration > recovery:
		source_knots.append(src_duration)
		target_knots.append(actual + (src_duration - recovery) * actual / recovery)
	duration = float(target_knots.back())
	# Blend only properties that actually moved in the outgoing pose (plus whatever the new clip animates).
	blend_pairs.clear()
	for key in blend_from:
		if not setup_pose.has(key):
			continue
		var from: Dictionary = blend_from[key]
		var own: Dictionary = setup_pose[key]
		for prop in from:
			if prop == "image" or prop == "z":
				continue
			if float(from[prop]) != float(own[prop]):
				blend_pairs.append([key, prop, own[prop]])
	# Reset targets: new clip's tracks, the outgoing clip's tracks, and blended properties.
	var seen := {}
	reset_pairs.clear()
	for tr in clip_tracks[name]:
		var k: String = tr[0] + "|" + tr[1]
		if not seen.has(k):
			seen[k] = true
			reset_pairs.append(tr)
	for tr in touched:
		var k2: String = tr[0] + "|" + tr[1]
		if not seen.has(k2):
			seen[k2] = true
			reset_pairs.append(tr)
	for pr in blend_pairs:
		var k3: String = pr[0] + "|" + pr[1]
		if not seen.has(k3):
			seen[k3] = true
			reset_pairs.append([pr[0], pr[1], 2, pr[2]])
	_evaluate(0.0)
	_emit_between(-0.000001, 0.0)

func source_time(t: float) -> float:
	for i in range(1, target_knots.size()):
		if t <= float(target_knots[i]):
			return lerpf(source_knots[i - 1], source_knots[i], clampf((t - float(target_knots[i - 1])) / maxf(0.000001, float(target_knots[i]) - float(target_knots[i - 1])), 0, 1))
	return float(source_knots.back())

func advance(dt: float) -> void:
	if clip.is_empty() or dt <= 0.0:
		return
	var t_start := Time.get_ticks_usec()
	blend_time += dt
	var remain := dt
	var looping := bool(animations[clip].get("loop", false))
	while remain > 0.000001:
		var step := minf(remain, maxf(0.0, duration - clock))
		var before := source_time(clock)
		clock += step
		_emit_between(before, source_time(clock))
		remain -= step
		if clock >= duration:
			if not looping:
				break
			clock = 0.0
			_emit_between(-0.000001, 0.0)
	_evaluate(source_time(clock))
	var steps := clampi(int(ceil(dt * 60.0)), 1, 2)
	var t_spring := Time.get_ticks_usec()
	for i in steps:
		_springs(minf(dt, 0.05) / steps)
	spring_us += Time.get_ticks_usec() - t_spring
	queue_redraw()
	sim_us += Time.get_ticks_usec() - t_start

func _emit_between(a: float, b: float) -> void:
	for ev in animations[clip].get("events", []):
		if float(ev.t) > a and float(ev.t) <= b:
			event_fired.emit(ev.duplicate(true))

func _evaluate(t: float) -> void:
	var t_eval := Time.get_ticks_usec()
	for tr in reset_pairs:
		pose[tr[0]][tr[1]] = tr[3]
	for tr in clip_tracks[clip]:
		_write_track(tr, t)
	if blend_time < blend_duration and not blend_pairs.is_empty():
		var mix := clampf(blend_time / blend_duration, 0, 1)
		for pr in blend_pairs:
			pose[pr[0]][pr[1]] = lerpf(float(blend_from[pr[0]][pr[1]]), float(pose[pr[0]][pr[1]]), mix)
	touched = clip_tracks[clip]
	_build_world()
	eval_us += Time.get_ticks_usec() - t_eval

func _write_track(tr: Array, t: float) -> void:
	var times: PackedFloat32Array = tr[4]
	var mode: int = tr[2]
	var key: String = tr[0]
	var prop: String = tr[1]
	var n := times.size()
	var i := 0
	while i < n and float(times[i]) <= t:
		i += 1
	if mode == 4:
		pose[key][prop] = tr[7][i - 1] if i > 0 else tr[3]
		return
	var vals: PackedFloat32Array = tr[5]
	var prev: float
	if i > 0:
		prev = vals[i - 1]
	elif mode == 2 or mode == 3:
		prev = float(tr[3])
	else:
		prev = 1.0 if mode == 1 else 0.0
	var value: float
	if mode == 3 or i >= n:
		value = prev
	else:
		var prev_t := float(times[i - 1]) if i > 0 else 0.0
		var u := clampf((t - prev_t) / maxf(0.000001, float(times[i]) - prev_t), 0.0, 1.0)
		value = lerpf(prev, vals[i], Ease.apply_code(int(tr[6][i]), u))
	if mode == 0:
		value = float(tr[3]) + value
	elif mode == 1:
		value = float(tr[3]) * value
	pose[key][prop] = value

func _build_world() -> void:
	var t_w := Time.get_ticks_usec()
	world.clear()
	for id in bone_order:
		var p: Dictionary = pose[id]
		var local := Transform2D(deg_to_rad(float(p.rot)), Vector2(p.sx, p.sy), 0.0, Vector2(p.x, p.y) * unit)
		var par: String = bone_parent[id]
		world[id] = world[par] * local if par != "" else local
	world_us += Time.get_ticks_usec() - t_w

func _world_bone(id: String) -> Transform2D:
	if world.has(id):
		return world[id]
	var p: Dictionary = pose[id]
	var local := Transform2D(deg_to_rad(float(p.rot)), Vector2(p.sx, p.sy), 0.0, Vector2(p.x, p.y) * unit)
	var parent: Variant = bones[id].get("parent")
	world[id] = _world_bone(parent) * local if parent != null and bones.has(parent) else local
	return world[id]

func _springs(dt: float) -> void:
	for chain in spring_chains:
		var k: float = chain.k
		var dmp: float = chain.d
		var gravity := Vector2(0, float(chain.g))
		for m in chain.bones:
			var id: String = m[0]
			if not world.has(id):
				continue
			var tr: Transform2D = world[id]
			var target := tr * (Vector2.from_angle(float(m[2])) * float(m[1]))
			if not spring_state.has(id):
				spring_state[id] = {"tip": target, "v": Vector2.ZERO}
			var s: Dictionary = spring_state[id]
			s.v += ((target - s.tip) * k - s.v * dmp + gravity) * dt
			s.tip += s.v * dt
			var delta: Vector2 = s.tip - tr.origin
			if delta.length_squared() > 0.0001:
				s.tip = tr.origin + delta.normalized() * target.distance_to(tr.origin)
				var angle := delta.angle() - (target - tr.origin).angle()
				world[id] = Transform2D(angle, tr.origin) * Transform2D(0, -tr.origin) * tr
				_rebuild_children(id)

func _rebuild_children(parent: String) -> void:
	for id in children_of.get(parent, []):
		world.erase(id)
		_world_bone(String(id))
		_rebuild_children(String(id))

func socket_at(name: String, target_time: float) -> Vector2:
	var s: Dictionary = rig.get("sockets", {}).get(name, {})
	if s.is_empty():
		return Vector2.ZERO
	var saved_blend := blend_time
	blend_time = clampf(target_time, 0.0, duration)
	_evaluate(source_time(blend_time))
	var p: Vector2 = world[s.bone] * (Vector2(s.get("x", 0), s.get("y", 0)) * unit) if world.has(s.bone) else Vector2.ZERO
	blend_time = saved_blend
	_evaluate(source_time(clock))
	return p

func socket(name: String) -> Vector2:
	var s: Dictionary = rig.get("sockets", {}).get(name, {})
	if s.is_empty() or not world.has(s.bone):
		return Vector2.ZERO
	return world[s.bone] * (Vector2(s.get("x", 0), s.get("y", 0)) * unit)

func _texture(path: String) -> Texture2D:
	if not textures.has(path):
		var file := base_path.path_join(path)
		textures[path] = load(file) if ResourceLoader.exists(file) else null
	return textures[path]

func _draw() -> void:
	var t_draw := Time.get_ticks_usec()
	var ordered: Array = slot_static_order
	if z_animated:
		ordered = slots.keys()
		ordered.sort_custom(func(a, b): return float(pose["slot:" + a].z) + float(pose[slots[a].bone].z) < float(pose["slot:" + b].z) + float(pose[slots[b].bone].z))
	parts_drawn += ordered.size()
	for id in ordered:
		var slot_def: Dictionary = slots[id]
		var sp: Dictionary = pose["slot:" + id]
		var bp: Dictionary = pose[slot_def.bone]
		draw_set_transform_matrix(world[slot_def.bone])
		var color := Color(1, 1, 1, float(sp.alpha) * float(bp.alpha))
		var img := String(sp.image)
		var pivot: Array = slot_def.get("pivot", [0.5, 0.5])
		var region: Array = atlas_regions.get(img, [])
		if atlas != null and region.size() == 4:
			# One texture per character: every part batches into a single draw call.
			var sz := Vector2(float(region[2]), float(region[3]))
			draw_texture_rect_region(atlas, Rect2(-Vector2(pivot[0], pivot[1]) * sz * unit, sz * unit), Rect2(float(region[0]), float(region[1]), sz.x, sz.y), color)
		else:
			var tex := _texture(img) if not debug_blocks else null
			var size_px := tex.get_size() if tex else Vector2(36, 16)
			var rect := Rect2(-Vector2(pivot[0], pivot[1]) * size_px * unit, size_px * unit)
			if tex:
				draw_texture_rect(tex, rect, false, color)
			elif debug_blocks:
				color = Color.from_hsv(float(ordered.find(id)) / maxf(1, ordered.size()), 0.6, 1, color.a)
				draw_rect(rect, color)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_us += Time.get_ticks_usec() - t_draw
