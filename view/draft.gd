class_name DraftModal
extends Control
## 三选一: mask fades in, card backs fly in one by one, flip in order (rare/epic pause + sfx).
## A full-screen blocker swallows all clicks until the last card settles. One tap = pick.

signal picked(id: String)

const RARITY := {
	"common": {"name": "普通", "base": Color(0.24, 0.3, 0.4), "rim": Color(0.62, 0.72, 0.85), "glow": Color(0.6, 0.75, 1.0, 0.0)},
	"rare": {"name": "稀有", "base": Color(0.32, 0.16, 0.46), "rim": Color(0.8, 0.55, 1.0), "glow": Color(0.75, 0.45, 1.0, 0.35)},
	"epic": {"name": "史诗", "base": Color(0.5, 0.24, 0.06), "rim": Color(1.0, 0.8, 0.35), "glow": Color(1.0, 0.65, 0.2, 0.55)},
}
const ICON_BY_EFFECT := {"crescentSpins": "crescent", "spearSplit": "meteor", "dodgeFlame": "dodge", "skyfallRadiusMul": "skyfall",
	"attackMul": "atk", "critChance": "crit", "maxHp": "hp", "mpRegenMul": "mp", "killHeal": "heal", "dodgeCrit": "dodge",
	"rageMul": "rage", "cooldownMul": "cdr"}

var cfg: Dictionary
var sfx: Sfx
var cards: Array = []
var blocker: Control
var dimr: ColorRect
var title: Label
var done := false
var ready_to_pick := false

func open(options: Array, game_cfg: Dictionary, s: Sfx) -> void:
	cfg = game_cfg
	sfx = s
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vs := get_viewport_rect().size
	dimr = ColorRect.new()
	dimr.color = Color(0.03, 0.01, 0.04, 0.0)
	dimr.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimr.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimr)
	title = Label.new()
	title.text = "选择一项强化"
	var ls := LabelSettings.new()
	ls.font_size = 40
	ls.font_color = Color(1.0, 0.88, 0.6)
	ls.outline_size = 10
	ls.outline_color = Color(0.3, 0.06, 0.0)
	title.label_settings = ls
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(vs.x, 60)
	title.position = Vector2(0, vs.y * 0.5 - 250)
	title.modulate.a = 0.0
	add_child(title)
	var d: Dictionary = cfg.draft
	var cw := 232.0
	var ch := 330.0
	var gap := minf(44.0, (vs.x - cw * 3.0) / 4.0)
	var total := cw * 3.0 + gap * 2.0
	var x0 := (vs.x - total) * 0.5
	var y := vs.y * 0.5 - ch * 0.5 + 30.0
	for i in options.size():
		var c := DraftCard.new()
		c.data = _card(String(options[i]))
		c.rar = RARITY.get(String(c.data.get("rarity", "common")), RARITY.common)
		c.size = Vector2(cw, ch)
		c.pivot_offset = c.size * 0.5
		c.target = Vector2(x0 + i * (cw + gap), y)
		c.position = Vector2(c.target.x, vs.y + 40.0)
		c.rotation = 0.25
		c.modulate.a = 0.0
		c.chosen.connect(_on_choose)
		add_child(c)
		cards.append(c)
	blocker = Control.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	# timeline
	var tw := create_tween()
	tw.tween_property(dimr, "color:a", 0.72, float(d.maskFade))
	tw.parallel().tween_property(title, "modulate:a", 1.0, float(d.maskFade))
	for i in cards.size():
		var c: DraftCard = cards[i]
		tw.tween_callback(func(): sfx.play("card_flip", -6.0, 0.1))
		tw.tween_property(c, "position", c.target, float(d.cardFlyIn)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(c, "rotation", 0.0, float(d.cardFlyIn))
		tw.parallel().tween_property(c, "modulate:a", 1.0, float(d.cardFlyIn) * 0.5)
		tw.tween_interval(maxf(0.0, float(d.cardStagger) - float(d.cardFlyIn) * 0.5))
	for i in cards.size():
		var c: DraftCard = cards[i]
		var special: bool = String(c.data.get("rarity", "common")) != "common"
		if special:
			tw.tween_interval(float(d.rarePause))
		tw.tween_property(c, "scale:x", 0.0, float(d.cardFlip) * 0.5).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			c.face_up = true
			c.build_front()
			sfx.play("card_rare" if special else "card_flip", -2.0 if special else -4.0, 0.0))
		tw.tween_property(c, "scale:x", 1.0, float(d.cardFlip) * 0.5).set_ease(Tween.EASE_OUT)
		if special:
			tw.tween_property(c, "scale", Vector2(1.08, 1.08), 0.08)
			tw.tween_property(c, "scale", Vector2.ONE, 0.1)
	tw.tween_callback(func():
		ready_to_pick = true
		blocker.queue_free()
		blocker = null)

func _card(id: String) -> Dictionary:
	for c in cfg.cards:
		if String(c.id) == id:
			return c
	return {}

func _on_choose(card: DraftCard) -> void:
	if done or not ready_to_pick:
		return
	done = true
	sfx.play("ui_click", 0.0, 0.0)
	var tw := create_tween().set_parallel(true)
	for c in cards:
		if c == card:
			tw.tween_property(c, "scale", Vector2(1.12, 1.12), 0.12).set_trans(Tween.TRANS_BACK)
		else:
			tw.tween_property(c, "modulate:a", 0.0, 0.18)
	tw.chain().tween_interval(0.12)
	tw.chain().tween_property(self, "modulate:a", 0.0, 0.18)
	tw.chain().tween_callback(func():
		picked.emit(String(card.data.id))
		queue_free())

## Bridge/test helper: centers of cards in logical px.
func card_centers() -> Array:
	var out: Array = []
	for c in cards:
		out.append([c.target.x + c.size.x * 0.5, c.target.y + c.size.y * 0.5])
	return out

# ------------------------------------------------------------------ card
class DraftCard extends Control:
	signal chosen(card)
	var data: Dictionary
	var rar: Dictionary
	var target := Vector2.ZERO
	var face_up := false
	var t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _process(dt: float) -> void:
		t += dt
		if face_up and String(data.get("rarity", "")) == "epic":
			queue_redraw()

	func _gui_input(ev: InputEvent) -> void:
		if not face_up:
			return
		var tap := false
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			tap = true
		elif ev is InputEventScreenTouch and ev.pressed:
			tap = true
		if tap:
			accept_event()
			chosen.emit(self)

	func build_front() -> void:
		var w := size.x
		var name_l := _label(String(data.name), 32, Color(1.0, 0.95, 0.85), Color(0.15, 0.05, 0.02), 9)
		name_l.position = Vector2(0, 168)
		name_l.size = Vector2(w, 44)
		var desc := _label(String(data.desc), 21, Color(1.0, 0.92, 0.8), Color(0.08, 0.03, 0.03), 5)
		desc.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		desc.position = Vector2(18, 218)
		desc.size = Vector2(w - 36, 90)
		desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		var rl := _label(String(rar.name), 18, rar.rim.lightened(0.3), Color(0.05, 0.02, 0.05), 5)
		rl.position = Vector2(0, 12)
		rl.size = Vector2(w, 28)
		queue_redraw()

	func _label(s: String, fs: int, col: Color, oc: Color, os: int) -> Label:
		var l := Label.new()
		l.text = s
		var ls := LabelSettings.new()
		ls.font_size = fs
		ls.font_color = col
		ls.outline_size = os
		ls.outline_color = oc
		l.label_settings = ls
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		return l

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if not face_up:
			var back := Art.real("ui/card_back.png")
			if back != null:
				draw_texture_rect(back, r, false)
				return
			UiDraw.game_panel(self, r, 18, Color(0.25, 0.1, 0.1), Color(0.8, 0.55, 0.3))
			var c := size * 0.5
			for i in 3:
				draw_arc(c, 40.0 + i * 22.0, 0, TAU, 40, Color(1.0, 0.7, 0.35, 0.35 - i * 0.08), 3.0, true)
			UiDraw.icon(self, "ult", c, 36, Color(1.0, 0.8, 0.45, 0.9))
			return
		var rk := String(data.get("rarity", "common"))
		var gl: Color = rar.glow
		if gl.a > 0.0:
			var pulse := 0.6 + 0.4 * sin(t * 4.0)
			for i in 4:
				UiDraw.grad_rrect(self, r.grow(6.0 + i * 5.0), 22 + i * 4, Color(gl, gl.a * 0.25 * pulse), Color(gl, gl.a * 0.25 * pulse))
		var tex := Art.real("ui/card_%s.png" % rk)
		if tex != null:
			draw_texture_rect(tex, r, false)
		else:
			UiDraw.game_panel(self, r, 18, rar.base, rar.rim)
			UiDraw.grad_rrect(self, Rect2(14, 160, size.x - 28, 3), 1, Color(rar.rim, 0.8), Color(rar.rim, 0.8))
		# gem emblem with icon
		var ic := Vector2(size.x * 0.5, 100)
		if rk == "epic":
			for i in 8:
				var a := t * 0.6 + TAU * i / 8.0
				draw_line(ic, ic + Vector2(cos(a), sin(a)) * 72.0, Color(1.0, 0.8, 0.4, 0.18), 6.0)
		draw_circle(ic, 50, Color(0.05, 0.02, 0.03, 0.6))
		draw_circle(ic, 46, rar.rim.darkened(0.2))
		draw_circle(ic, 41, rar.base.darkened(0.35))
		var eff: Dictionary = data.get("effect", {})
		var icon := "atk"
		for k in eff.keys():
			if ICON_BY_EFFECT.has(k):
				icon = ICON_BY_EFFECT[k]
				break
		UiDraw.icon(self, icon, ic, 30, Color(1, 0.95, 0.85))
