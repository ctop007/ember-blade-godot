class_name Screens
extends RefCounted
## Code-built screens: loading, home, QR modal, pause, result. All return a Control.

const VERSION_DATE := "2026-11-08"

static func label(text: String, fs: int, col: Color, outline := 6, oc := Color(0.08, 0.03, 0.03)) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font_size = fs
	ls.font_color = col
	ls.outline_size = outline
	ls.outline_color = oc
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func centered(l: Label, w: float) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(w, l.label_settings.font_size * 1.5)
	return l

static func full(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	return c

# ------------------------------------------------------------------ button
class GameButton extends Control:
	signal pressed
	var text := ""
	var style := "primary"    # primary / secondary / small
	var down := false
	var fs := 30
	var sfx: Sfx

	func _init(t: String, st := "primary", sz := Vector2(260, 76)) -> void:
		text = t
		style = st
		size = sz
		custom_minimum_size = sz
		pivot_offset = sz * 0.5
		fs = 30 if st == "primary" else (24 if st == "secondary" else 20)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				down = true
				queue_redraw()
			elif down:
				down = false
				queue_redraw()
				if Rect2(Vector2.ZERO, size).has_point(ev.position):
					if sfx:
						sfx.play("ui_click", 0.0, 0.0)
					pressed.emit()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if down:
			r = r.grow(-3.0)
		var tex := Art.real("ui/btn_primary.png") if style == "primary" else null
		if tex != null:
			draw_texture_rect(tex, r, false)
		elif style == "primary":
			UiDraw.game_panel(self, r, size.y * 0.42, Color(0.85, 0.35, 0.12), Color(1.0, 0.82, 0.45))
		else:
			UiDraw.game_panel(self, r, size.y * 0.4, Color(0.25, 0.18, 0.28), Color(0.8, 0.65, 0.5))
		var font := get_theme_default_font()
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := Vector2((size.x - w) * 0.5, size.y * 0.5 + fs * 0.36)
		draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0.3, 0.07, 0.0) if style == "primary" else Color(0.08, 0.04, 0.08))
		draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.96, 0.85))

# ------------------------------------------------------------------ backgrounds
class Backdrop extends Control:
	var t := 0.0
	var embers: Array = []
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in 40:
			embers.append([randf(), randf(), randf_range(0.02, 0.08), randf_range(2, 5)])
	func _process(dt: float) -> void:
		t += dt
		queue_redraw()
	func _draw() -> void:
		var vs := get_viewport_rect().size
		var tex := Art.real("ui/home_bg.png")
		if tex != null:
			var s := maxf(vs.x / tex.get_width(), vs.y / tex.get_height())
			var ts := tex.get_size() * s
			draw_texture_rect(tex, Rect2((vs - ts) * 0.5, ts), false)
		else:
			draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)]),
				PackedColorArray([Color(0.06, 0.04, 0.12), Color(0.1, 0.05, 0.12), Color(0.3, 0.1, 0.06), Color(0.2, 0.07, 0.06)]))
			for k in 6:
				draw_circle(Vector2(vs.x * 0.78, vs.y * 0.24), 70.0 + k * 30.0, Color(1.0, 0.7, 0.45, 0.04))
			draw_circle(Vector2(vs.x * 0.78, vs.y * 0.24), 64, Color(1.0, 0.88, 0.7))
			var pts := PackedVector2Array([Vector2(0, vs.y)])
			for i in 21:
				var x := vs.x * i / 20.0
				pts.append(Vector2(x, vs.y * 0.72 - absf(sin(i * 1.7)) * 90.0))
			pts.append(vs)
			draw_colored_polygon(pts, Color(0.07, 0.04, 0.06))
		for e in embers:
			var x: float = fmod(e[0] + sin(t * 0.5 + e[1] * 10.0) * 0.02, 1.0) * vs.x
			var y: float = fmod(e[1] - t * e[2] + 10.0, 1.0) * vs.y
			draw_circle(Vector2(x, y), e[3] * 2.0, Color(1.0, 0.5, 0.2, 0.15))
			draw_circle(Vector2(x, y), e[3] * 0.7, Color(1.0, 0.8, 0.4, 0.8))

# ------------------------------------------------------------------ loading
class Loading extends Control:
	var progress := 0.0
	var tip := "正在点燃余烬……"
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_anchors_preset(Control.PRESET_FULL_RECT)
	func _process(_dt: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var vs := get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.03, 0.06))
		var font := get_theme_default_font()
		var title := "烬刃"
		var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 110).x
		var p := Vector2((vs.x - w) * 0.5, vs.y * 0.45)
		draw_string_outline(font, p, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 110, 18, Color(0.35, 0.05, 0.0))
		draw_string(font, p, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 110, Color(1.0, 0.75, 0.35))
		var bw := minf(560.0, vs.x * 0.6)
		var r := Rect2((vs.x - bw) * 0.5, vs.y * 0.62, bw, 18)
		UiDraw.grad_rrect(self, r.grow(3), 10, Color(0.8, 0.55, 0.3), Color(0.4, 0.2, 0.1))
		UiDraw.grad_rrect(self, r, 9, Color(0.1, 0.05, 0.05), Color(0.15, 0.08, 0.08))
		if progress > 0.01:
			UiDraw.grad_rrect(self, Rect2(r.position, Vector2(maxf(18.0, r.size.x * progress), r.size.y)), 9, Color(1.0, 0.75, 0.3), Color(0.9, 0.35, 0.1))
		var s := "%s  %d%%" % [tip, int(progress * 100.0)]
		var w2 := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(font, Vector2((vs.x - w2) * 0.5, r.end.y + 40), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.85, 0.7, 0.85))

# ------------------------------------------------------------------ home
static func home(sfx: Sfx, insets: Vector4, on_start: Callable, on_qr: Callable) -> Control:
	var root := full(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(full(Backdrop.new()))
	var vs := root.get_viewport_rect().size if root.is_inside_tree() else Vector2(1280, 720)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	holder.resized.connect(func(): _layout_home(holder, insets))
	# hero art
	var hero_tex := Art.real("chars/hero/idle.png")
	if hero_tex != null:
		var tr := TextureRect.new()
		tr.name = "Hero"
		tr.texture = hero_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(560, 560)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
	var logo_tex := Art.real("ui/logo.png")
	if logo_tex != null:
		var lt := TextureRect.new()
		lt.name = "Logo"
		lt.texture = logo_tex
		lt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lt.size = Vector2(520, 195)
		lt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(lt)
	else:
		var t := label("烬刃", 130, Color(1.0, 0.75, 0.32), 22, Color(0.35, 0.04, 0.0))
		t.name = "Logo"
		t.label_settings.shadow_size = 10
		t.label_settings.shadow_color = Color(1.0, 0.35, 0.1, 0.45)
		holder.add_child(centered(t, 520))
	var sub := centered(label("余烬森林 · 双引擎试玩 Demo（Godot）", 22, Color(1.0, 0.88, 0.7), 5), 520)
	sub.name = "Sub"
	holder.add_child(sub)
	var start := GameButton.new("开始战斗", "primary", Vector2(280, 84))
	start.name = "Start"
	start.sfx = sfx
	start.pressed.connect(on_start)
	holder.add_child(start)
	var qr := GameButton.new("加入交流群", "secondary", Vector2(220, 60))
	qr.name = "Qr"
	qr.sfx = sfx
	qr.pressed.connect(on_qr)
	holder.add_child(qr)
	var note := label("本游戏由 AI 开发，当前为试玩版，欢迎加群提意见", 18, Color(1.0, 0.9, 0.8, 0.85), 4)
	note.name = "Note"
	holder.add_child(note)
	var ver := label("v0.1.0 试玩版 · 更新于 %s" % VERSION_DATE, 16, Color(0.9, 0.8, 0.7, 0.7), 4)
	ver.name = "Ver"
	holder.add_child(ver)
	var _v := vs
	return root

static func _layout_home(h: Control, insets: Vector4) -> void:
	var vs := h.size
	var cx := vs.x * 0.62
	var hero := h.get_node_or_null("Hero")
	if hero:
		hero.position = Vector2(vs.x * 0.28 - 280.0, vs.y - 560.0 + 40.0)
	var logo: Control = h.get_node("Logo")
	logo.position = Vector2(cx - logo.size.x * 0.5, vs.y * 0.1)
	var sub: Control = h.get_node("Sub")
	sub.position = Vector2(cx - 260, vs.y * 0.1 + 200)
	var st: Control = h.get_node("Start")
	st.position = Vector2(cx - st.size.x * 0.5, vs.y * 0.56)
	var qr: Control = h.get_node("Qr")
	qr.position = Vector2(cx - qr.size.x * 0.5, vs.y * 0.56 + 104)
	var note: Label = h.get_node("Note")
	note.position = Vector2(insets.x + 12, vs.y - insets.w - 34)
	var ver: Label = h.get_node("Ver")
	ver.position = Vector2(vs.x - insets.z - 12 - 300, vs.y - insets.w - 32)
	ver.size = Vector2(300, 24)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

# ------------------------------------------------------------------ modal frame
class Panel9 extends Control:
	var base := Color(0.22, 0.12, 0.14, 0.97)
	var rim := Color(0.85, 0.6, 0.35)
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _draw() -> void:
		var tex := Art.real("ui/panel.png")
		if tex != null:
			draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
		else:
			UiDraw.game_panel(self, Rect2(Vector2.ZERO, size), 22, base, rim)

static func modal_root() -> Control:
	var root := full(Control.new())
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dimr := full(ColorRect.new())
	dimr.color = Color(0.02, 0.01, 0.03, 0.72)
	dimr.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dimr)
	return root

static func qr_modal(sfx: Sfx) -> Control:
	var root := modal_root()
	var p := Panel9.new()
	p.size = Vector2(700, 470)
	root.add_child(p)
	var title := centered(label("加入交流群", 34, Color(1.0, 0.88, 0.6), 8), 700)
	title.position = Vector2(0, 20)
	p.add_child(title)
	var note := label("本游戏由 AI 制作。欢迎加群交流 AI 做游戏，或直接联系作者提出修改意见。微信长按二维码即可识别。", 17, Color(1, 0.92, 0.85), 4)
	note.text = UiDraw.wrap_text(note.text, note.get_theme_default_font(), 17, 616)
	note.position = Vector2(40, 72)
	note.size = Vector2(620, 50)
	p.add_child(note)
	var items := [["res://images/qr-group.png", "AI 游戏兴趣交流群", "群码 7 天有效，过期加作者微信"], ["res://images/qr-author.png", "作者微信", "提建议、报 bug、交流学习"]]
	for i in 2:
		var x := 90.0 + i * 300.0
		var bgc := ColorRect.new()
		bgc.color = Color.WHITE
		bgc.position = Vector2(x - 4, 128)
		bgc.size = Vector2(228, 224)
		bgc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(bgc)
		var tr := TextureRect.new()
		tr.texture = load(items[i][0])
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = Vector2(x, 132)
		tr.size = Vector2(220, 216)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(tr)
		var cap := centered(label(items[i][1], 19, Color(1, 0.9, 0.75), 4), 260)
		cap.position = Vector2(x - 20, 354)
		p.add_child(cap)
		var cap2 := centered(label(items[i][2], 14, Color(0.95, 0.85, 0.75, 0.8), 3), 260)
		cap2.position = Vector2(x - 20, 380)
		p.add_child(cap2)
	var ok := GameButton.new("知道了", "primary", Vector2(200, 58))
	ok.sfx = sfx
	ok.position = Vector2(250, 404)
	ok.pressed.connect(root.queue_free)
	p.add_child(ok)
	root.resized.connect(func(): p.position = (root.size - p.size) * 0.5)
	return root

static func pause_menu(sfx: Sfx, on_resume: Callable, on_restart: Callable, on_home: Callable, on_mute: Callable, muted: bool) -> Control:
	var root := modal_root()
	var p := Panel9.new()
	p.size = Vector2(380, 420)
	root.add_child(p)
	var title := centered(label("暂停", 40, Color(1.0, 0.88, 0.6), 9), 380)
	title.position = Vector2(0, 22)
	p.add_child(title)
	var defs := [["继续战斗", "primary", on_resume], ["重新开始", "secondary", on_restart], ["音效：" + ("关" if muted else "开"), "secondary", on_mute], ["返回首页", "secondary", on_home]]
	for i in defs.size():
		var b := GameButton.new(defs[i][0], defs[i][1], Vector2(260, 64 if i == 0 else 56))
		b.name = "B%d" % i
		b.sfx = sfx
		b.position = Vector2(60, 96 + i * 76)
		b.pressed.connect(defs[i][2])
		p.add_child(b)
	root.resized.connect(func(): p.position = (root.size - p.size) * 0.5)
	return root

static func result(sfx: Sfx, win: bool, stats: Dictionary, on_again: Callable, on_home: Callable) -> Control:
	var root := modal_root()
	var p := Panel9.new()
	p.size = Vector2(560, 440)
	if not win:
		p.base = Color(0.15, 0.1, 0.14, 0.97)
		p.rim = Color(0.6, 0.55, 0.6)
	root.add_child(p)
	var t := centered(label("胜 利" if win else "败 北", 72, Color(1.0, 0.82, 0.35) if win else Color(0.8, 0.75, 0.8), 14, Color(0.4, 0.08, 0.0) if win else Color(0.1, 0.05, 0.1)), 560)
	t.position = Vector2(0, 16)
	t.pivot_offset = Vector2(280, 50)
	p.add_child(t)
	var sub := centered(label("灰烬骑士已被击败，余烬森林重归宁静" if win else "余烬未灭，再来一局吧", 20, Color(1, 0.92, 0.85), 4), 560)
	sub.position = Vector2(0, 118)
	p.add_child(sub)
	var rows := [["用时", "%d 秒" % int(stats.time)], ["击败敌人", str(stats.kills)], ["最高连击", str(stats.maxCombo)], ["总伤害", str(int(stats.damage))]]
	for i in rows.size():
		var y := 166 + i * 42
		var a := label(rows[i][0], 22, Color(1.0, 0.85, 0.65), 4)
		a.position = Vector2(110, y)
		p.add_child(a)
		var b := label(rows[i][1], 24, Color.WHITE, 5)
		b.position = Vector2(300, y - 2)
		p.add_child(b)
	var again := GameButton.new("再来一局", "primary", Vector2(220, 70))
	again.name = "Again"
	again.sfx = sfx
	again.position = Vector2(50, 344)
	again.pressed.connect(on_again)
	p.add_child(again)
	var home := GameButton.new("返回首页", "secondary", Vector2(200, 62))
	home.sfx = sfx
	home.position = Vector2(310, 348)
	home.pressed.connect(on_home)
	p.add_child(home)
	p.scale = Vector2(0.6, 0.6)
	p.pivot_offset = p.size * 0.5
	p.modulate.a = 0.0
	var tw := p.create_tween().set_parallel(true)
	tw.tween_property(p, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	root.resized.connect(func(): p.position = (root.size - p.size) * 0.5)
	return root
