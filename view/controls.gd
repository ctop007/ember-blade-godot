class_name Controls
extends Control
## Multi-touch virtual controls (floating joystick + right-hand button fan) and desktop keys.
## Each finger is bound to one control on touch-down, so zones never steal from each other.

const SKILLS := ["crescent", "skyfall", "meteorSpear"]
const ICONS := ["crescent", "skyfall", "meteor"]

var game: CoreGame
var enabled := true
var insets := Vector4(16, 12, 16, 10)    # left, top, right, bottom (logical px)
var buttons: Dictionary = {}            # id -> {c: Vector2, r: float, kind}
var touch_owner: Dictionary = {}        # finger index -> "joy" | button id
var held: Dictionary = {}               # button id -> true
var edges: Dictionary = {}
var joy_center := Vector2.ZERO
var joy_knob := Vector2.ZERO
var joy_active := false
var joy_rest := Vector2.ZERO
var joy_r := 90.0
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
	joy_r = float(game.cfg.ui.joystickRadius) if game else 90.0
	var a := Vector2(vs.x - insets.z - 120.0, vs.y - insets.w - 108.0)
	buttons = {
		"attack": {"c": a, "r": 70.0},
		"dodge": {"c": a + Vector2(-162, 26), "r": 44.0},
		"jump": {"c": a + Vector2(24, -160), "r": 44.0},
		"skill1": {"c": a + Vector2(-252, -38), "r": 44.0},
		"skill2": {"c": a + Vector2(-206, -164), "r": 44.0},
		"skill3": {"c": a + Vector2(-92, -246), "r": 44.0},
		"ult": {"c": a + Vector2(58, -276), "r": 52.0},
		"pause": {"c": Vector2(vs.x - insets.z - 40.0, insets.y + 38.0), "r": 28.0},
	}
	joy_rest = Vector2(insets.x + 150.0, vs.y - insets.w - 140.0)
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

## Logical-space rects of every control (for Playwright tapping via the bridge).
func layout_info() -> Dictionary:
	var out := {}
	for id in buttons.keys():
		out[id] = [buttons[id].c.x, buttons[id].c.y, buttons[id].r]
	out["joy"] = [joy_rest.x, joy_rest.y, joy_r]
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
		var hit_r: float = b.r * (1.25 if id != "pause" else 1.6)
		if d <= hit_r and d - b.r < bd:
			bd = d - b.r
			best = id
	if best != "":
		touch_owner[idx] = best
		held[best] = true
		edges[best + "_pressed"] = true
		get_viewport().set_input_as_handled()
		return
	if pos.x < vs.x * 0.5 and pos.y > vs.y * 0.28 and not joy_active:
		touch_owner[idx] = "joy"
		joy_active = true
		var m := joy_r + 12.0
		joy_center = Vector2(clampf(pos.x, insets.x + m, vs.x * 0.5), clampf(pos.y, vs.y * 0.3, vs.y - insets.w - m))
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
	# joystick
	var ja := 0.9 if joy_active else 0.45
	draw_circle(joy_center, joy_r + 6.0, Color(0, 0, 0, 0.25 * ja))
	draw_arc(joy_center, joy_r, 0, TAU, 48, Color(1.0, 0.75, 0.45, 0.55 * ja), 3.0, true)
	draw_circle(joy_center, joy_r - 2.0, Color(0.15, 0.08, 0.06, 0.35 * ja))
	for i in 4:
		var a := i * PI * 0.5
		var tip := joy_center + Vector2(cos(a), sin(a)) * (joy_r - 14.0)
		draw_colored_polygon(PackedVector2Array([tip + Vector2(cos(a), sin(a)) * 8.0, tip + Vector2(cos(a + 1.6), sin(a + 1.6)) * 7.0, tip + Vector2(cos(a - 1.6), sin(a - 1.6)) * 7.0]), Color(1, 0.8, 0.5, 0.5 * ja))
	UiDraw.orb(self, joy_knob, 34.0, Color(0.9, 0.45, 0.2), Color(1.0, 0.8, 0.5), false, ja)
	# buttons
	for id in buttons.keys():
		var b: Dictionary = buttons[id]
		var pressed := held.has(id)
		match id:
			"attack":
				UiDraw.orb(self, b.c, b.r, Color(0.75, 0.22, 0.1), Color(1.0, 0.72, 0.35), pressed)
				_tex_or_icon("ui/btn_attack.png", "attack", b.c, b.r)
				if p.holding and p.hold_t > 0.05:
					var k := clampf(p.hold_t / float(game.cfg.attack.chargeTime), 0.0, 1.0)
					var col := Color(1.0, 0.9, 0.4) if k >= 1.0 else Color(1.0, 0.6, 0.2)
					draw_arc(b.c, b.r + 8.0, -PI * 0.5, -PI * 0.5 + TAU * k, 40, col, 6.0, true)
			"jump", "dodge":
				UiDraw.orb(self, b.c, b.r, Color(0.3, 0.32, 0.45), Color(0.75, 0.8, 0.95), pressed)
				_tex_or_icon("ui/btn_%s.png" % id, id, b.c, b.r)
				if id == "dodge" and p.dodge_cd > 0.0:
					_cd_pie(b.c, b.r, p.dodge_cd / float(game.cfg.dodge.cooldown))
			"skill1", "skill2", "skill3":
				var i := int(id.substr(5)) - 1
				var sk: String = SKILLS[i]
				var sc: Dictionary = game.cfg.skills[sk]
				var cd: float = p.cds[sk]
				var no_mp: bool = p.mp < float(sc.mp)
				var base: Color = [Color(0.7, 0.25, 0.1), Color(0.2, 0.4, 0.7), Color(0.75, 0.45, 0.1)][i]
				UiDraw.orb(self, b.c, b.r, base, Color(1.0, 0.85, 0.55), pressed, 0.55 if no_mp else 1.0)
				_tex_or_icon("ui/icon_skill%d.png" % (i + 1), ICONS[i], b.c, b.r * 0.82, 0.45 if no_mp else 1.0)
				if cd > 0.0:
					_cd_pie(b.c, b.r, cd / (float(sc.cooldown) * game.cd_mul()))
					_text(b.c + Vector2(0, 9), "%.1f" % cd if cd < 10.0 else str(int(cd)), 24, Color.WHITE)
				# MP cost tag
				var tag := Rect2(b.c + Vector2(-20, b.r - 10), Vector2(40, 20))
				UiDraw.grad_rrect(self, tag, 8, Color(0.15, 0.3, 0.6, 0.95) if not no_mp else Color(0.35, 0.2, 0.2, 0.95), Color(0.08, 0.15, 0.35, 0.95))
				_text(tag.get_center() + Vector2(0, 7), str(int(sc.mp)), 17, Color(0.75, 0.9, 1.0) if not no_mp else Color(1.0, 0.5, 0.45))
				if fail_flash.has(id):
					draw_arc(b.c, b.r + 4.0, 0, TAU, 40, Color(1, 0.2, 0.2, fail_flash[id] / 0.35), 5.0, true)
			"ult":
				var k := clampf(p.rage / float(game.cfg.player.maxRage), 0.0, 1.0)
				var full := k >= 1.0
				if full:
					var pulse := 0.5 + 0.5 * sin(t * 6.0)
					for g in 4:
						draw_circle(b.c, b.r + 8.0 + g * 6.0 + pulse * 6.0, Color(1.0, 0.6, 0.2, 0.09))
				UiDraw.orb(self, b.c, b.r, Color(0.55, 0.15, 0.35) if not full else Color(0.85, 0.35, 0.1), Color(1.0, 0.85, 0.5), pressed, 1.0 if full else 0.75)
				_tex_or_icon("ui/icon_ult.png", "ult", b.c, b.r * 0.85, 1.0 if full else 0.5)
				draw_arc(b.c, b.r + 5.0, -PI * 0.5, -PI * 0.5 + TAU * k, 48, Color(1.0, 0.8, 0.3) if full else Color(1.0, 0.5, 0.2), 6.0, true)
				if not full:
					_text(b.c + Vector2(0, b.r + 26.0), "%d%%" % int(k * 100.0), 20, Color(1.0, 0.85, 0.6))
				if fail_flash.has(id):
					draw_arc(b.c, b.r + 4.0, 0, TAU, 40, Color(1, 0.2, 0.2, fail_flash[id] / 0.35), 5.0, true)
			"pause":
				UiDraw.orb(self, b.c, b.r, Color(0.25, 0.22, 0.3), Color(0.8, 0.75, 0.7), pressed)
				_tex_or_icon("ui/btn_pause.png", "pause", b.c, b.r * 0.7)

func _tex_or_icon(path: String, icon: String, c: Vector2, r: float, alpha := 1.0) -> void:
	var tex := Art.real(path)
	if tex != null:
		draw_texture_rect(tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, alpha))
	else:
		UiDraw.icon(self, icon, c, r * 0.55, Color(1.0, 0.95, 0.85, alpha))

func _cd_pie(c: Vector2, r: float, k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	if k <= 0.0:
		return
	var pts := PackedVector2Array([c])
	var n := 32
	for i in n + 1:
		var a := -PI * 0.5 + TAU * k * float(i) / float(n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, Color(0.02, 0.02, 0.05, 0.62))

func _text(pos: Vector2, s: String, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string_outline(font, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0.05, 0.02, 0.02))
	draw_string(font, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
