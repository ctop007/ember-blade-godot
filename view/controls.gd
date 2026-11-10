class_name Controls
extends Control
## Multi-touch virtual controls matching _shared/UI_LAYOUT.md.
## Each finger is bound to one control on touch-down; a second finger on an already-held button is ignored.

const SKILLS := ["crescent", "skyfall", "meteorSpear"]
const ICONS := ["crescent", "skyfall", "meteor"]

var game: CoreGame
var enabled := true
var insets := Vector4(22, 18, 22, 18)    # left, top, right, bottom (logical px)
var buttons: Dictionary = {}             # id -> {c: Vector2, r: float, hit_r: float}
var touch_owner: Dictionary = {}         # finger index -> "joy" | button id
var held: Dictionary = {}                # button id -> true
var edges: Dictionary = {}
var joy_center := Vector2.ZERO
var joy_knob := Vector2.ZERO
var joy_active := false
var joy_rest := Vector2.ZERO
var joy_r := 81.0
var joy_vis_r := 85.0
var keys_edge: Dictionary = {}
var fail_flash: Dictionary = {}
var t := 0.0
var font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	font = get_theme_default_font()
	get_viewport().size_changed.connect(layout)
	layout()

func layout() -> void:
	var vs := get_viewport_rect().size
	var k := HudScale.factor()
	var L := maxf(12.0 * k, insets.x)
	var R := vs.x - maxf(12.0 * k, insets.z)
	var T := maxf(10.0 * k, insets.y)
	var B := vs.y - maxf(10.0 * k, insets.w)
	joy_r = 44.0 * k
	joy_vis_r = 46.0 * k
	buttons = {
		"attack": {"c": Vector2(R - 40.0 * k, B - 40.0 * k), "r": 34.0 * k, "hit_r": 36.0 * k},
		"dodge": {"c": Vector2(R - 122.0 * k, B - 27.0 * k), "r": 21.0 * k, "hit_r": 23.0 * k},
		"jump": {"c": Vector2(R - 28.0 * k, B - 119.0 * k), "r": 21.0 * k, "hit_r": 23.0 * k},
		"skill1": {"c": Vector2(R - 110.0 * k, B - 85.0 * k), "r": 22.0 * k, "hit_r": 23.0 * k},
		"skill2": {"c": Vector2(R - 88.0 * k, B - 142.0 * k), "r": 22.0 * k, "hit_r": 23.0 * k},
		"skill3": {"c": Vector2(R - 30.0 * k, B - 179.0 * k), "r": 22.0 * k, "hit_r": 23.0 * k},
		"ult": {"c": Vector2(R - 176.0 * k, B - 95.0 * k), "r": 25.0 * k, "hit_r": 26.0 * k},
		"pause": {"c": Vector2(R - 22.0 * k, T + 22.0 * k), "r": 16.0 * k, "hit_r": 22.0 * k},
	}
	joy_rest = Vector2(L + 58.0 * k, B - 58.0 * k)
	if not joy_active:
		joy_center = joy_rest
		joy_knob = joy_rest

func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		touch_owner.clear()
		held.clear()
		edges.clear()
		joy_active = false
		joy_center = joy_rest
		joy_knob = joy_rest

## Logical-space centers and hit radii of every control (for Playwright tapping via the bridge).
func layout_info() -> Dictionary:
	var out := {}
	for id in buttons.keys():
		out[id] = [buttons[id].c.x, buttons[id].c.y, buttons[id].hit_r, buttons[id].r]
	out["joy"] = [joy_rest.x, joy_rest.y, joy_r, joy_vis_r]
	return out

# ------------------------------------------------------------------ input
func _input(ev: InputEvent) -> void:
	if ev is InputEventKey:
		_key(ev)
		return
	if not enabled:
		return
	if ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_touch_down(st.index, st.position)
		else:
			_touch_up(st.index)
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		if touch_owner.get(sd.index, "") == "joy":
			_joy_move(sd.position)

func _touch_down(idx: int, pos: Vector2) -> void:
	var vs := get_viewport_rect().size
	var best := ""
	var bd := INF
	for id in buttons.keys():
		var b: Dictionary = buttons[id]
		var d := pos.distance_to(b.c)
		if d <= float(b.hit_r) and d < bd:
			bd = d
			best = id
	if best != "":
		# UI_LAYOUT.md §2: ignore a second finger pressing an already-held button.
		if held.has(best):
			get_viewport().set_input_as_handled()
			return
		touch_owner[idx] = best
		held[best] = true
		edges[best + "_pressed"] = true
		get_viewport().set_input_as_handled()
		return
	if pos.x < vs.x * 0.5 and pos.y > vs.y * 0.22 and not joy_active:
		touch_owner[idx] = "joy"
		joy_active = true
		var m := joy_vis_r + 8.0
		joy_center = Vector2(clampf(pos.x, insets.x + m, vs.x * 0.5), clampf(pos.y, vs.y * 0.25, vs.y - insets.w - m))
		joy_knob = pos
		_joy_move(pos)
		get_viewport().set_input_as_handled()

func _touch_up(idx: int) -> void:
	if not touch_owner.has(idx):
		return
	var who: String = touch_owner[idx]
	touch_owner.erase(idx)
	if who == "joy":
		joy_active = false
		joy_center = joy_rest
		joy_knob = joy_rest
	else:
		held.erase(who)
		edges[who + "_released"] = true

func _joy_move(pos: Vector2) -> void:
	var d := pos - joy_center
	if d.length() > joy_r:
		d = d.normalized() * joy_r
	joy_knob = joy_center + d

func _key(k: InputEventKey) -> void:
	if k.echo:
		return
	var map := {KEY_J: "attack", KEY_K: "jump", KEY_L: "dodge", KEY_U: "skill1", KEY_I: "skill2", KEY_O: "skill3", KEY_P: "ult", KEY_ESCAPE: "pause"}
	var id: String = map.get(k.physical_keycode, "")
	if id == "":
		return
	if k.pressed:
		keys_edge[id + "_pressed"] = true
	else:
		keys_edge[id + "_released"] = true

func poll_pause() -> bool:
	var hit: bool = edges.has("pause_pressed") or keys_edge.has("pause_pressed")
	edges.erase("pause_pressed")
	keys_edge.erase("pause_pressed")
	edges.erase("pause_released")
	keys_edge.erase("pause_released")
	return hit

## Consumes edges; returns core input dict.
func poll() -> Dictionary:
	var mx := 0.0
	var my := 0.0
	if joy_active:
		var d := (joy_knob - joy_center) / joy_r
		if d.length() > float(game.cfg.ui.joystickDeadzone):
			mx = d.x
			my = d.y
	if Input.is_physical_key_pressed(KEY_A): mx -= 1.0
	if Input.is_physical_key_pressed(KEY_D): mx += 1.0
	if Input.is_physical_key_pressed(KEY_W): my -= 1.0
	if Input.is_physical_key_pressed(KEY_S): my += 1.0
	var v := Vector2(mx, my)
	if v.length() > 1.0:
		v = v.normalized()
	var out := {"mx": v.x, "my": v.y,
		"attack_held": held.has("attack") or Input.is_physical_key_pressed(KEY_J)}
	for src in [edges, keys_edge]:
		for k in src.keys():
			out[k] = true
	edges.clear()
	keys_edge.clear()
	return out

func flash_fail(id: String) -> void:
	fail_flash[id] = 0.35

# ------------------------------------------------------------------ draw
func _process(dt: float) -> void:
	t += dt
	for k in fail_flash.keys():
		fail_flash[k] = float(fail_flash[k]) - dt
		if fail_flash[k] <= 0.0:
			fail_flash.erase(k)
	queue_redraw()

func _draw() -> void:
	if game == null:
		return
	var p = game.player
	var k := HudScale.factor()
	# joystick
	var ja := 0.9 if joy_active else 0.5
	var jbase := Art.real("ui/joystick_base.png")
	if jbase != null:
		draw_texture_rect(jbase, Rect2(joy_center - Vector2.ONE * joy_vis_r, Vector2.ONE * joy_vis_r * 2.0), false, Color(1, 1, 1, ja))
	else:
		draw_circle(joy_center, joy_vis_r + 3.0, Color(0, 0, 0, 0.25 * ja))
		draw_arc(joy_center, joy_vis_r, 0, TAU, 48, Color(1.0, 0.75, 0.45, 0.55 * ja), 2.5, true)
		draw_circle(joy_center, joy_vis_r - 2.0, Color(0.15, 0.08, 0.06, 0.35 * ja))
	var jknob := Art.real("ui/joystick_knob.png")
	var kr := 18.0 * k
	if jknob != null:
		draw_texture_rect(jknob, Rect2(joy_knob - Vector2.ONE * kr, Vector2.ONE * kr * 2.0), false, Color(1, 1, 1, ja))
	else:
		UiDraw.orb(self, joy_knob, kr, Color(0.9, 0.45, 0.2), Color(1.0, 0.8, 0.5), false, ja)
	# buttons
	for id in buttons.keys():
		var b: Dictionary = buttons[id]
		var pressed := held.has(id)
		var r: float = b.r * (0.93 if pressed else 1.0)
		match id:
			"attack", "jump", "dodge", "pause":
				var single := Art.real("ui/btn_%s.png" % id)
				if single != null:
					draw_texture_rect(single, Rect2(b.c - Vector2(r, r), Vector2(r, r) * 2.0), false)
				else:
					var base := Color(0.75, 0.22, 0.1) if id == "attack" else (Color(0.25, 0.22, 0.3) if id == "pause" else Color(0.3, 0.32, 0.45))
					var rim := Color(1.0, 0.72, 0.35) if id == "attack" else Color(0.8, 0.78, 0.85)
					UiDraw.orb(self, b.c, r, base, rim, pressed)
					UiDraw.icon(self, id, b.c, r * 0.52, Color(1.0, 0.95, 0.85))
				if id == "attack" and p.holding and p.hold_t > 0.05:
					var ck := clampf(p.hold_t / float(game.cfg.attack.chargeTime), 0.0, 1.0)
					draw_arc(b.c, r + 4.0, -PI * 0.5, -PI * 0.5 + TAU * ck, 40, Color(1.0, 0.9, 0.4) if ck >= 1.0 else Color(1.0, 0.6, 0.2), 4.0, true)
				if id == "dodge" and p.dodge_cd > 0.0:
					_cd_pie(b.c, r, p.dodge_cd / float(game.cfg.dodge.cooldown))
			"skill1", "skill2", "skill3":
				var i := int(id.substr(5)) - 1
				var sk: String = SKILLS[i]
				var sc: Dictionary = game.cfg.skills[sk]
				var cd: float = p.cds[sk]
				var no_mp: bool = p.mp < float(sc.mp)
				var alpha := 0.5 if no_mp else 1.0
				var frame := Art.real("ui/btn_frame.png")
				var icon := Art.real("ui/icon_skill%d.png" % (i + 1))
				if icon != null:
					var ir := r * 0.78
					draw_texture_rect(icon, Rect2(b.c - Vector2(ir, ir), Vector2(ir, ir) * 2.0), false, Color(1, 1, 1, alpha))
				else:
					UiDraw.icon(self, ICONS[i], b.c, r * 0.5, Color(1.0, 0.95, 0.85, alpha))
				if frame != null:
					draw_texture_rect(frame, Rect2(b.c - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, alpha))
				elif icon == null:
					var base2: Color = [Color(0.7, 0.25, 0.1), Color(0.2, 0.4, 0.7), Color(0.75, 0.45, 0.1)][i]
					UiDraw.orb(self, b.c, r, base2, Color(1.0, 0.85, 0.55), pressed, alpha)
				if cd > 0.0:
					_cd_pie(b.c, r, cd / (float(sc.cooldown) * game.cd_mul()))
					_text(b.c + Vector2(0, 6), "%.1f" % cd if cd < 10.0 else str(int(cd)), int(round(10.0 * k)), Color.WHITE)
				var tag := Rect2(b.c + Vector2(-13.0 * k, r - 6.0 * k), Vector2(26.0 * k, 12.0 * k))
				UiDraw.grad_rrect(self, tag, 5, Color(0.15, 0.3, 0.6, 0.95) if not no_mp else Color(0.35, 0.2, 0.2, 0.95), Color(0.08, 0.15, 0.35, 0.95))
				_text(tag.get_center() + Vector2(0, 4.0 * k), str(int(sc.mp)), int(round(8.5 * k)), Color(0.75, 0.9, 1.0) if not no_mp else Color(1.0, 0.5, 0.45))
				if fail_flash.has(id):
					draw_arc(b.c, r + 3.0, 0, TAU, 36, Color(1, 0.2, 0.2, fail_flash[id] / 0.35), 3.5, true)
			"ult":
				var rk := clampf(p.rage / float(game.cfg.player.maxRage), 0.0, 1.0)
				var full := rk >= 1.0
				if full:
					var pulse := 0.5 + 0.5 * sin(t * 6.0)
					for g in 3:
						draw_circle(b.c, r + (5.0 + g * 4.0 + pulse * 4.0) * k * 0.5, Color(1.0, 0.6, 0.2, 0.1))
				var uframe := Art.real("ui/btn_ult_frame.png")
				var uicon := Art.real("ui/icon_ult.png")
				var ua := 1.0 if full else 0.72
				if uicon != null:
					var ur := r * 0.78
					draw_texture_rect(uicon, Rect2(b.c - Vector2(ur, ur), Vector2(ur, ur) * 2.0), false, Color(1, 1, 1, 1.0 if full else 0.55))
				else:
					UiDraw.icon(self, "ult", b.c, r * 0.5, Color(1.0, 0.95, 0.85, 1.0 if full else 0.55))
				if uframe != null:
					draw_texture_rect(uframe, Rect2(b.c - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, ua))
				elif uicon == null:
					UiDraw.orb(self, b.c, r, Color(0.55, 0.15, 0.35) if not full else Color(0.85, 0.35, 0.1), Color(1.0, 0.85, 0.5), pressed, ua)
				draw_arc(b.c, r + 3.0, -PI * 0.5, -PI * 0.5 + TAU * rk, 44, Color(1.0, 0.8, 0.3) if full else Color(1.0, 0.5, 0.2), 4.0, true)
				if not full:
					_text(b.c + Vector2(0, r + 11.0 * k), "%d%%" % int(rk * 100.0), int(round(9.0 * k)), Color(1.0, 0.85, 0.6))
				if fail_flash.has(id):
					draw_arc(b.c, r + 3.0, 0, TAU, 36, Color(1, 0.2, 0.2, fail_flash[id] / 0.35), 3.5, true)

func _cd_pie(c: Vector2, r: float, k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	if k <= 0.005:
		return
	var pts := PackedVector2Array([c])
	var n := maxi(4, int(ceil(32.0 * k)))
	for i in n + 1:
		var a := -PI * 0.5 + TAU * k * float(i) / float(n)
		var q := c + Vector2(cos(a), sin(a)) * r
		if pts[pts.size() - 1].distance_squared_to(q) > 0.25:
			pts.append(q)
	if pts.size() >= 3:
		draw_colored_polygon(pts, Color(0.02, 0.02, 0.05, 0.62))

func _text(pos: Vector2, s: String, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string_outline(font, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0.05, 0.02, 0.02))
	draw_string(font, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
