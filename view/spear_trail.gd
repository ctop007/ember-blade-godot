class_name SpearTrail
extends Node2D
## World-space ribbon mesh sampled from spearTip. Explicit clock stops aging during hitstop.
var samples: Array = []
var emitting := false
var life := 0.14
var width := 32.0
var mesh := ArrayMesh.new()
var core_mesh := ArrayMesh.new()
var white_tex: ImageTexture

func _ready() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	white_tex = ImageTexture.create_from_image(img)

func push_substep(tip: Vector2, age: float) -> void:
	if samples.is_empty() or tip.distance_squared_to(samples.back().p) > 0.5:
		samples.append({"p": tip, "age": age})

func tick(dt: float, tip: Vector2) -> void:
	if dt <= 0:
		return
	for s in samples:
		s.age += dt
	samples = samples.filter(func(s): return float(s.age) < life)
	if emitting and (samples.is_empty() or tip.distance_squared_to(samples.back().p) > 0.5):
		samples.append({"p": tip, "age": 0.0})
	while samples.size() > 48:
		samples.pop_front()
	_build(mesh, width, Color(1.0, 0.45, 0.1, 0.85))
	_build(core_mesh, width * 0.42, Color(1.0, 0.94, 0.58, 0.95))
	queue_redraw()

func _build(target: ArrayMesh, w: float, base_col: Color) -> void:
	target.clear_surfaces()
	if samples.size() < 2:
		return
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for i in samples.size():
		var p: Vector2 = samples[i].p
		var before: Vector2 = samples[maxi(0, i - 1)].p
		var after: Vector2 = samples[mini(samples.size() - 1, i + 1)].p
		var normal := (after - before).normalized().orthogonal()
		var fade := clampf(1.0 - float(samples[i].age) / life, 0.0, 1.0)
		var u := clampf(float(i) / float(samples.size() - 1), 0.0, 1.0)
		var head := sin(u * PI * 0.85)
		var hw := maxf(2.0, w * fade * (0.3 + 0.7 * head) * 0.5)
		for side in [-1.0, 1.0]:
			var v := to_local(p + normal * side * hw)
			vertices.append(Vector3(v.x, v.y, 0.0))
			uvs.append(Vector2(u, 0.0 if side < 0.0 else 1.0))
			colors.append(Color(base_col.r, base_col.g, base_col.b, base_col.a * fade))
		if i > 0:
			var j := i * 2
			indices.append_array(PackedInt32Array([j - 2, j - 1, j, j, j - 1, j + 1, j, j - 1, j - 2, j + 1, j - 1, j]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func _draw() -> void:
	if mesh.get_surface_count() > 0:
		draw_mesh(mesh, white_tex)
	if core_mesh.get_surface_count() > 0:
		draw_mesh(core_mesh, white_tex)
