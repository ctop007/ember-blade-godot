class_name Hud
extends Control
## Top-left status (avatar, HP, MP, combo), top-center wave/tip + boss bar, top-right "乃秀游戏 Demo", banners, boss title card.
## Coordinates follow _shared/UI_LAYOUT.md in CSS pixels scaled via HudScale.factor().

var game: CoreGame
var insets := Vector4(22, 18, 22, 18)
var font: Font
var hp_lag := 1.0
var combo := 0
var combo_dmg := 0.0
var combo_pop := 0.0
var combo_alpha := 0.0
var banners: Array = []         # [text, color, t, dur]
var card_t := -1.0
var card_dur := 2.0
var card_name := ""
var boss_lag := 1.0
var t := 0.0
var rage_glow := 0.0
var avatar_tex: Texture2D
var vignette := 0.0
var last_hp := -1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	font = get_theme_default_font()
	avatar_tex = Art.real("ui/avatar.png")
	if avatar_tex == null:
		# Fallback until ui/avatar.png is delivered: full head-and-shoulders crop centered on face.
		var idle := Art.real("chars/hero/idle.png")
		if idle != null:
			var at := AtlasTexture.new()
			at.atlas = idle
			var k := idle.get_width() / 512.0
			at.region = Rect2(Vector2(118, 92) * k, Vector2(276, 276) * k)
			avatar_tex = at

func on_combo(n: int, dmg: float) -> void:
	combo = n
	combo_dmg = dmg
	combo_pop = 1.0
	combo_alpha = 1.0

func rage_full() -> void:
	rage_glow = 1.0

func skill_fail(_skill: String, _why: String) -> void:
	pass

func banner(text: String, col: Color, dur := 1.6) -> void:
	banners.append([text, col, 0.0, dur])

func boss_card(name: String, dur: float) -> void:
	card_name = name
	card_dur = dur
	card_t = 0.0

func on_core_event(ev: Dictionary) -> void:
	match ev.type:
		"wave_start":
			if not ev.boss:
				banner(String(ev.title), Color(1.0, 0.85, 0.5), 1.4)
		"wave_clear":
			banner("波次清除！", Color(1.0, 0.75, 0.3), 1.2)
		"combo_end":
			pass

func _process(dt: float) -> void:
	t += dt
	if game == null:
		return
	var p = game.player
	var r: float = p.hp / p.max_hp
	if last_hp >= 0.0 and p.hp < last_hp:
		vignette = 1.0
	last_hp = p.hp
	hp_lag = r if r > hp_lag else lerpf(hp_lag, r, minf(1.0, dt * 3.0))
	combo_pop = maxf(0.0, combo_pop - dt * 5.0)
	if game.combo == 0:
		combo_alpha = maxf(0.0, combo_alpha - dt * 3.0)
	rage_glow = maxf(0.0, rage_glow - dt * 0.8)
	vignette = maxf(0.0, vignette - dt * 2.5)
	for b in banners:
		b[2] += dt
	banners = banners.filter(func(b): return b[2] < b[3])
	if card_t >= 0.0:
		card_t += dt
		if card_t > card_dur:
			card_t = -1.0
	queue_redraw()

func _text(pos: Vector2, s: String, size: int, col: Color, align := 0, outline := 5, ocol := Color(0.06, 0.02, 0.03)) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x - (w * 0.5 if align == 1 else (w if align == 2 else 0.0))
	draw_string_outline(font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, ocol)
	draw_string(font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _bar(r: Rect2, k: float, lag: float, c1: Color, c2: Color) -> void:
	var frame := Art.real("ui/bar_frame.png")
	var fill := Art.real("ui/bar_fill.png")
	var rad := r.size.y * 0.45
	UiDraw.grad_rrect(self, r, rad, Color(0.08, 0.04, 0.05, 0.9), Color(0.15, 0.08, 0.08, 0.9))
	if lag > k:
		UiDraw.grad_rrect(self, Rect2(r.position, Vector2(r.size.x * lag, r.size.y)), rad, Color(1, 0.9, 0.8), Color(0.9, 0.7, 0.6))
	if k > 0.01:
		var fw := maxf(6.0, r.size.x * k)
		if fill != null:
			draw_texture_rect(fill, Rect2(r.position, Vector2(fw, r.size.y)), false, c1)
		else:
			UiDraw.grad_rrect(self, Rect2(r.position, Vector2(fw, r.size.y)), rad, c1, c2)
	if frame != null:
		draw_texture_rect(frame, r.grow(2.0), false)
	else:
		draw_rect(r.grow(1.0), Color(0.85, 0.65, 0.4, 0.85), false, 2.0)

func _draw() -> void:
	if game == null:
		return
	var vs := get_viewport_rect().size
	var k := HudScale.factor()
	var L := maxf(12.0 * k, insets.x)
	var R := vs.x - maxf(12.0 * k, insets.z)
	var T := maxf(10.0 * k, insets.y)
	var p = game.player
	# --- vignette when hurt / low hp
	var low: float = clampf(1.0 - p.hp / p.max_hp / 0.3, 0.0, 1.0)
	var va := maxf(vignette * 0.5, low * (0.25 + 0.1 * sin(t * 5.0)))
	if va > 0.01:
		for i in 6:
			var w := 18.0 + i * 16.0
			var c := Color(0.8, 0.0, 0.0, va * (0.22 - i * 0.03))
			draw_rect(Rect2(0, 0, vs.x, w), c)
			draw_rect(Rect2(0, vs.y - w, vs.x, w), c)
			draw_rect(Rect2(0, 0, w, vs.y), c)
			draw_rect(Rect2(vs.x - w, 0, w, vs.y), c)
	# --- UI_LAYOUT.md §4: avatar 44x44 at (L+22, T+22), HP 125x12 at (L+52, center T+14), MP 110x10 at (L+52, center T+30)
	var ac := Vector2(L + 22.0 * k, T + 22.0 * k)
	var ar := 22.0 * k
	var real_av := Art.real("ui/avatar.png")
	if real_av != null:
		draw_texture_rect(real_av, Rect2(ac - Vector2(ar, ar), Vector2(ar, ar) * 2.0), false)
	elif avatar_tex != null:
		draw_circle(ac, ar + 2.0, Color(0.1, 0.04, 0.03, 0.9))
		draw_circle(ac, ar, Color(0.95, 0.7, 0.35))
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in 32:
			var a := TAU * i / 32.0
			pts.append(ac + Vector2(cos(a), sin(a)) * (ar - 2.0))
			uvs.append(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
		draw_colored_polygon(pts, Color.WHITE, uvs, avatar_tex)
	var hp_rect := Rect2(L + 52.0 * k, T + 8.0 * k, 125.0 * k, 12.0 * k)
	_bar(hp_rect, p.hp / p.max_hp, hp_lag, Color(1.0, 0.38, 0.32), Color(0.75, 0.1, 0.12))
	var hp_fs := int(round(10.0 * k))
	_text(hp_rect.get_center() + Vector2(0, hp_fs * 0.35), "%d/%d" % [int(ceil(p.hp)), int(p.max_hp)], hp_fs, Color.WHITE, 1, 4)
	var mp_rect := Rect2(L + 52.0 * k, T + 25.0 * k, 110.0 * k, 10.0 * k)
	_bar(mp_rect, p.mp / p.max_mp, p.mp / p.max_mp, Color(0.42, 0.72, 1.0), Color(0.15, 0.35, 0.85))
	var mp_fs := int(round(9.0 * k))
	_text(mp_rect.get_center() + Vector2(0, mp_fs * 0.35), "%d/%d" % [int(p.mp), int(p.max_mp)], mp_fs, Color.WHITE, 1, 3)
	# --- combo at (L+10, T+68)
	if combo_alpha > 0.01 and combo > 0:
		var big := combo >= int(game.cfg.ui.comboBigAt)
		var s := 1.0 + combo_pop * (0.35 if big else 0.2)
		var cpos := Vector2(L + 10.0 * k, T + 68.0 * k)
		draw_set_transform(cpos, -0.05, Vector2(s, s))
		var col := Color(1.0, 0.85, 0.3, combo_alpha) if big else Color(1.0, 0.95, 0.85, combo_alpha)
		var cfs := int(round((22.0 if big else 18.0) * k))
		_text(Vector2(0, 0), "%d 连击" % combo, cfs, col, 0, 6, Color(0.35, 0.08, 0.0, combo_alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_text(Vector2(L + 10.0 * k, T + 84.0 * k), "伤害 %d" % int(combo_dmg), int(round(9.5 * k)), Color(1.0, 0.9, 0.8, combo_alpha * 0.9), 0, 3)
	# --- UI_LAYOUT.md §5: top center objective (W/2, T+12) fs 13, wave (W/2, T+28) fs 10, boss bar (W/2, T+46) 260x10
	var w_i: int = game.wave_index
	var waves: Array = game.cfg.waves
	var title := String(waves[clampi(w_i, 0, waves.size() - 1)].title)
	var cx := vs.x * 0.5
	var boss = null
	for e in game.enemies:
		if e.type == "boss" and e.state != "dead":
			boss = e
	var obj_fs := int(round(13.0 * k))
	var wave_fs := int(round(10.0 * k))
	var obj_text := game.tip if game.tip != "" else title
	if boss != null and game.phase != "boss_intro":
		obj_text = String(game.cfg.enemies.boss.name) + (" · 狂暴" if boss.enraged else "")
	_text(Vector2(cx, T + 12.0 * k + obj_fs * 0.35), obj_text, obj_fs, Color(1.0, 0.95, 0.82), 1, 5)
	_text(Vector2(cx, T + 28.0 * k + wave_fs * 0.35), title + ("" if game.phase != "wave" else " · 剩余 %d" % _remaining()), wave_fs, Color(1.0, 0.86, 0.65), 1, 4)
	if boss != null and game.phase != "boss_intro":
		var bk: float = boss.hp / boss.max_hp
		boss_lag = bk if bk > boss_lag else lerpf(boss_lag, bk, minf(1.0, get_process_delta_time() * 2.5))
		var bw := 260.0 * k
		var bh := 10.0 * k
		var br := Rect2(cx - bw * 0.5, T + 46.0 * k - bh * 0.5, bw, bh)
		_bar(br, bk, boss_lag, Color(1.0, 0.35, 0.25) if boss.enraged else Color(0.95, 0.55, 0.3), Color(0.6, 0.1, 0.08))
	# --- UI_LAYOUT.md §5: fixed label "乃秀游戏 Demo" right-aligned at (R-46, T+22), font size 12
	var brand_fs := int(round(12.0 * k))
	_text(Vector2(R - 46.0 * k, T + 22.0 * k + brand_fs * 0.35), "乃秀游戏 Demo", brand_fs, Color(1.0, 0.94, 0.82), 2, 5, Color(0.08, 0.03, 0.03))
	# advance arrow
	if game.phase == "advance" and game.tip.begins_with("向右"):
		var ax := vs.x - insets.z - 150.0 + sin(t * 6.0) * 10.0
		var ay := vs.y * 0.42
		for i in 3:
			var x := ax + i * 26.0
			var a := 0.4 + 0.6 * (0.5 + 0.5 * sin(t * 6.0 - i))
			draw_colored_polygon(PackedVector2Array([Vector2(x, ay - 22), Vector2(x + 22, ay), Vector2(x, ay + 22), Vector2(x + 8, ay)]), Color(1.0, 0.75, 0.3, a))
	# banners
	var by := vs.y * 0.33
	for b in banners:
		var bt: float = b[2]
		var dur: float = b[3]
		var a := clampf(bt / 0.15, 0.0, 1.0) * clampf((dur - bt) / 0.3, 0.0, 1.0)
		var s := 1.0 + maxf(0.0, 0.15 - bt) * 3.0
		draw_set_transform(Vector2(cx, by), 0.0, Vector2(s, s))
		var bc: Color = b[1]
		draw_rect(Rect2(-260, -42, 520, 58), Color(0.0, 0.0, 0.0, 0.35 * a))
		_text(Vector2(0, 0), b[0], 46, Color(bc, a), 1, 10, Color(0.25, 0.05, 0.0, a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		by += 70.0
	# boss title card
	if card_t >= 0.0:
		var slide := clampf(card_t / 0.25, 0.0, 1.0)
		var a2 := clampf((card_dur - card_t) / 0.3, 0.0, 1.0)
		var h := 150.0
		var y := vs.y * 0.5 - h * 0.5
		var x0 := lerpf(vs.x, 0.0, ease(slide, 0.3))
		draw_rect(Rect2(0, 0, vs.x, vs.y), Color(0, 0, 0, 0.35 * a2))
		var tex := Art.real("ui/boss_title.png")
		if tex != null:
			draw_texture_rect(tex, Rect2(x0, y - 20, vs.x, h + 40), false, Color(1, 1, 1, a2))
		else:
			draw_polygon(PackedVector2Array([Vector2(x0, y), Vector2(x0 + vs.x, y), Vector2(x0 + vs.x, y + h), Vector2(x0, y + h)]),
				PackedColorArray([Color(0.35, 0.03, 0.02, 0.0), Color(0.55, 0.06, 0.03, 0.95 * a2), Color(0.3, 0.02, 0.01, 0.95 * a2), Color(0.2, 0.0, 0.0, 0.0)]))
			draw_line(Vector2(x0, y), Vector2(x0 + vs.x, y), Color(1.0, 0.5, 0.25, a2), 3.0)
			draw_line(Vector2(x0, y + h), Vector2(x0 + vs.x, y + h), Color(1.0, 0.5, 0.25, a2), 3.0)
		_text(Vector2(cx + (1.0 - slide) * 300.0, y + 48), "BOSS", 26, Color(1.0, 0.6, 0.35, a2), 1, 5)
		var shake_k := maxf(0.0, 0.4 - card_t) * 20.0
		_text(Vector2(cx + randf_range(-shake_k, shake_k), y + 116), card_name, 76, Color(1.0, 0.9, 0.75, a2), 1, 14, Color(0.3, 0.02, 0.0, a2))

func _remaining() -> int:
	return game.spawn_queue.size() + game.alive_enemies().size()
