class_name ActorView
extends Node2D
## One character on screen. Node origin = foot position on ground (y-sorted).
## Uses chars/<kind>/<pose>.png when imported, else code-drawn placeholder (BodyPH).

const HEIGHT := {"hero": 140.0, "imp": 86.0, "lantern": 104.0, "brute": 140.0, "boss": 220.0}
const SHADOW_W := {"hero": 70.0, "imp": 56.0, "lantern": 50.0, "brute": 92.0, "boss": 140.0}
const POSE_MAP := {
	"hero": {"idle": "idle", "run": "run", "charge": "charge", "thrust": "thrust", "thrust_end": "thrust",
		"dodge": "dodge", "jump": "jump", "slam": "slam", "slam_end": "slam", "cast": "cast", "hurt": "hurt",
		"dead": "dead", "ult": "cast"},
	"imp": {"spawn": "idle", "move": "run", "orbit": "run", "windup": "windup", "attack": "attack", "recover": "idle", "hurt": "hurt", "dead": "dead"},
	"lantern": {"spawn": "idle", "move": "move", "windup": "windup", "recover": "throw", "hurt": "hurt", "dead": "dead"},
	"brute": {"spawn": "idle", "move": "walk", "orbit": "walk", "windup": "windup", "charging": "charge", "recover": "idle", "hurt": "hurt", "dead": "dead"},
	"boss": {"spawn": "idle", "idle": "idle", "move": "walk", "walk": "walk", "sweep_windup": "sweep_windup", "sweep": "sweep",
		"leap_windup": "leap", "leap": "leap", "leap_land": "slam", "summon_windup": "summon", "hurt": "hurt", "dead": "dead"},
}

var kind := "hero"
var ent_id := 0
var shadow: Sprite2D
var lift: Node2D
var scaler: Node2D
var rot: Node2D
var body: Node2D
var sprite: Sprite2D
var ph: BodyPH
var hpbar: HpBar
var alert: Node2D
var pose := ""
var facing := 1
var squash := Vector2.ONE
var sq_v := Vector2.ZERO
var flash := 0.0
var t := 0.0
var h := 150.0
var tint := Color.WHITE
var alert_t := 0.0
var enraged := false
var dead_t := 0.0
var lean := 0.0
var spin := 0.0

func setup(k: String, id: int) -> void:
	kind = k
	ent_id = id
	h = HEIGHT.get(k, 100.0)
	shadow = Sprite2D.new()
	shadow.texture = Art.fx("chars/shadow.png") if Art.real("chars/%s/shadow.png" % k) == null else Art.real("chars/%s/shadow.png" % k)
	var sw: float = SHADOW_W.get(k, 60.0)
	shadow.scale = Vector2(sw / shadow.texture.get_width(), sw * 0.28 / shadow.texture.get_height())
	shadow.modulate = Color(0, 0, 0, 0.75)
	add_child(shadow)
	lift = Node2D.new()
	add_child(lift)
	scaler = Node2D.new()
	lift.add_child(scaler)
	rot = Node2D.new()
	rot.position = Vector2(0, -h * 0.45)
	scaler.add_child(rot)
	body = Node2D.new()
	body.position = Vector2(0, h * 0.45)
	rot.add_child(body)
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.visible = false
	body.add_child(sprite)
	ph = BodyPH.new()
	ph.kind = k
	body.add_child(ph)
	if k != "hero" and k != "boss":
		hpbar = HpBar.new()
		hpbar.position = Vector2(0, -h - 12.0)
		lift.add_child(hpbar)
	alert = Node2D.new()
	alert.position = Vector2(0, -h - 30.0)
	alert.visible = false
	alert.draw.connect(_draw_alert)
	lift.add_child(alert)
	set_pose("idle")

func set_pose(p: String) -> void:
	if p == pose:
		return
	pose = p
	var tex := Art.real("chars/%s/%s.png" % [kind, p])
	if tex != null:
		sprite.texture = tex
		sprite.visible = true
		ph.visible = false
		var path := "chars/%s/%s.png" % [kind, p]
		var sz := Art.size_of(path, tex.get_size())
		var anc := Art.anchor_of(path, Vector2(0.5, 0.92))
		var ds := Art.display_scale(path, 0.6)
		# scale real texture so its manifest size maps to displayScale
		var k := ds * sz.x / tex.get_size().x
		sprite.offset = Vector2(-tex.get_size().x * anc.x, -tex.get_size().y * anc.y)
		sprite.scale = Vector2(k, k)
	else:
		sprite.visible = false
		ph.visible = true
		ph.pose = p
		ph.queue_redraw()

func kick(sx: float, sy: float) -> void:
	## squash/stretch impulse (sx,sy are velocity added to scale)
	sq_v += Vector2(sx, sy)

func show_alert(dur: float) -> void:
	alert_t = dur
	alert.visible = true
	alert.queue_redraw()

func _draw_alert() -> void:
	var pulse := 1.0 + 0.25 * sin(t * 30.0)
	alert.draw_set_transform(Vector2.ZERO, 0.0, Vector2(pulse, pulse))
	alert.draw_colored_polygon(PackedVector2Array([Vector2(-7, -26), Vector2(7, -26), Vector2(3, -2), Vector2(-3, -2)]), Color(0.1, 0, 0))
	alert.draw_colored_polygon(PackedVector2Array([Vector2(-5, -24), Vector2(5, -24), Vector2(2, -4), Vector2(-2, -4)]), Color(1, 0.25, 0.15))
	alert.draw_circle(Vector2(0, 5), 5.0, Color(0.1, 0, 0))
	alert.draw_circle(Vector2(0, 5), 3.5, Color(1, 0.25, 0.15))

## Called every frame with the core entity (player or enemy).
func sync(ent, dt: float, frozen: bool) -> void:
	t += dt
	position = Vector2(ent.x, ent.y)
	lift.position.y = -ent.z
	var sh := clampf(1.0 - ent.z / 400.0, 0.4, 1.0)
	shadow.modulate.a = 0.7 * sh
	shadow.self_modulate = Color(1, 1, 1, 1)
	shadow.scale = Vector2(SHADOW_W.get(kind, 60.0) / shadow.texture.get_width(), SHADOW_W.get(kind, 60.0) * 0.28 / shadow.texture.get_height()) * sh
	var st: String = ent.state
	if kind == "hero" and st == "attack":
		set_pose("attack%d" % (ent.combo_step + 1))
	else:
		set_pose(POSE_MAP[kind].get(st, "idle"))
	facing = ent.facing
	# spring squash
	if not frozen:
		var k := 380.0
		var damp := 20.0
		sq_v += (Vector2.ONE - squash) * k * dt - sq_v * damp * dt
		squash += sq_v * dt
	# procedural motion
	var bob := 0.0
	var target_lean := 0.0
	match st:
		"idle", "spawn":
			bob = sin(t * 3.2 + ent_id) * 0.025
		"run", "move", "orbit", "walk":
			bob = absf(sin(t * 11.0 + ent_id)) * 0.06
			target_lean = 0.12
		"windup", "sweep_windup", "summon_windup", "charge":
			target_lean = -0.12
		"charging", "thrust", "attack":
			target_lean = 0.2
		"hurt":
			target_lean = -0.3
		"leap_windup":
			target_lean = 0.1
			bob = -0.12
	if kind == "lantern":
		lift.position.y -= 26.0 + sin(t * 2.4 + ent_id) * 6.0
		target_lean *= 0.5
	lean = lerpf(lean, target_lean, minf(1.0, dt * 14.0))
	var real := sprite.visible
	if st == "dodge" and not real:
		spin += dt * TAU * 3.3
		rot.rotation = spin
	elif st == "dead" and real:
		dead_t += dt
		rot.rotation = 0.0
	elif st == "dead":
		dead_t += dt
		rot.rotation = lerpf(rot.rotation, -PI * 0.5 if kind != "lantern" else 0.6, minf(1.0, dt * 10.0))
	else:
		spin = 0.0
		rot.rotation = lean
	var sc := squash * Vector2(1.0 - bob * 0.5, 1.0 + bob)
	scaler.scale = Vector2(sc.x * facing, sc.y)
	# flash / tint
	var f: float = ent.flash
	var col := tint
	if kind == "boss" and ent.enraged:
		col = Color(1.0, 0.55, 0.5)
	if st in ["windup", "sweep_windup", "summon_windup"] or (kind == "brute" and st == "windup"):
		var pulse := 0.5 + 0.5 * sin(t * 28.0)
		col = col.lerp(Color(1.6, 0.4, 0.3), 0.35 + 0.35 * pulse)
	if f > 0.0:
		col = Color(7, 7, 7, 1)
	if kind == "hero" and ent.iframe > 0.0 and st != "dodge" and st != "ult" and st != "thrust" and ent.flash <= 0.0:
		col.a = 0.55 + 0.45 * float(int(t * 20.0) % 2)
	body.modulate = col
	if st == "spawn":
		var k2 := clampf(ent.state_t / maxf(0.01, ent.state_dur), 0.0, 1.0)
		body.modulate.a = k2
		scaler.scale.y *= 0.4 + 0.6 * k2
	if st == "dead":
		modulate.a = clampf(1.0 - (dead_t - 0.35) / 0.6, 0.0, 1.0)
	if hpbar:
		hpbar.ratio = ent.hp / ent.max_hp
		hpbar.visible = ent.hp < ent.max_hp and st != "dead"
		hpbar.queue_redraw()
	if alert_t > 0.0:
		alert_t -= dt
		alert.queue_redraw()
		if alert_t <= 0.0:
			alert.visible = false

## A semi-transparent snapshot of the current body (dodge afterimages).
func make_ghost(col: Color) -> Node2D:
	var g := Node2D.new()
	g.global_position = body.global_position
	g.scale = scaler.scale
	g.rotation = rot.rotation * signf(scaler.scale.x)
	if sprite.visible:
		var s := Sprite2D.new()
		s.texture = sprite.texture
		s.centered = false
		s.offset = sprite.offset
		s.scale = sprite.scale
		g.add_child(s)
	else:
		var p := BodyPH.new()
		p.kind = kind
		p.pose = pose
		g.add_child(p)
	g.modulate = col
	return g

# ------------------------------------------------------------------ inner
class HpBar extends Node2D:
	var ratio := 1.0
	func _draw() -> void:
		var w := 44.0
		draw_rect(Rect2(-w * 0.5 - 1, -1, w + 2, 7), Color(0.05, 0.02, 0.02, 0.85))
		draw_rect(Rect2(-w * 0.5, 0, w * clampf(ratio, 0.0, 1.0), 5), Color(0.95, 0.25, 0.2))
		draw_rect(Rect2(-w * 0.5, 0, w * clampf(ratio, 0.0, 1.0), 2), Color(1, 0.6, 0.5))
