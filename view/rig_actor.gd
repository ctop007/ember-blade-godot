class_name RigActor
extends ActorView
## Opt-in skeletal adapter for hero and enemies. ActorView's single-image renderer stays intact for comparison.
var player: RigPlayer
var trail: SpearTrail
var config: Dictionary
var sound: Sfx
var previous_state := ""
var previous_time := 0.0
var tip_active := false

const ENEMY_CLIPS := {
	"imp": {"spawn": "idle", "move": "run", "orbit": "run", "windup": "windup", "attack": "claw", "recover": "idle", "hurt": "hurt", "dead": "dead"},
	"lantern": {"spawn": "float", "move": "float", "windup": "windup", "recover": "throw", "hurt": "hurt", "dead": "dead"},
	"brute": {"spawn": "idle", "move": "walk", "orbit": "walk", "windup": "charge_windup", "charging": "charge", "recover": "stagger", "hurt": "hurt", "dead": "dead"},
	"boss": {"spawn": "idle", "idle": "idle", "move": "walk", "walk": "walk", "sweep_windup": "sweep_windup", "sweep": "sweep",
		"leap_windup": "leap", "leap": "leap", "leap_land": "land", "summon_windup": "summon", "hurt": "hurt", "dead": "dead"},
}

func enable_rig(cfg: Dictionary, audio: Sfx, trail_parent: Node2D, fixture := false) -> bool:
	config = cfg
	sound = audio
	var definition: Dictionary
	var clips: Dictionary
	var directory := "res://rigs/" + kind
	if fixture:
		definition = RigFixture.definition()
		clips = RigFixture.clips()
	else:
		if not FileAccess.file_exists(directory + "/rig.json") or not FileAccess.file_exists(directory + "/anims.json"):
			return false
		definition = JSON.parse_string(FileAccess.get_file_as_string(directory + "/rig.json"))
		clips = JSON.parse_string(FileAccess.get_file_as_string(directory + "/anims.json"))
	player = RigPlayer.new()
	lift.add_child(player)
	player.configure(definition, clips, directory, fixture)
	player.event_fired.connect(_event)
	if kind == "hero":
		trail = SpearTrail.new()
		trail_parent.add_child(trail)
	return true

func sync(ent, dt: float, frozen: bool) -> void:
	super.sync(ent, dt, frozen)
	if player == null:
		return
	body.visible = false
	player.scale.x = absf(player.scale.x) * ent.facing
	player.modulate = body.modulate
	var name: String = ent.state
	var actual := -1.0
	var hit := -1.0
	if kind == "hero":
		match ent.state:
			"attack":
				name = "attack%d" % (ent.combo_step + 1)
				actual = float(config.attack.steps[ent.combo_step].duration)
				hit = float(config.attack.steps[ent.combo_step].hitAt)
			"jump":
				name = "jump_up" if ent.vz >= 0 else "jump_fall"
			"thrust_end": name = "thrust"
			"slam_end": name = "land"
			"cast":
				name = {"crescent": "cast_crescent", "skyfall": "cast_skyfall", "meteorSpear": "cast_meteor"}.get(ent.cast_skill, "idle")
		if ent.state in ["thrust", "dodge", "hurt", "slam_end", "cast", "ult"]:
			actual = ent.state_dur
	else:
		name = String(ENEMY_CLIPS.get(kind, {}).get(ent.state, ent.state))
		if not player.animations.has(name):
			name = "float" if player.animations.has("float") else "idle"
		if ent.state in ["windup", "attack", "charging", "recover", "hurt", "sweep_windup", "sweep", "leap_windup", "leap_land", "summon_windup"]:
			actual = ent.state_dur
	var key: String = name + ":" + ent.state
	var restart: bool = key != previous_state or float(ent.state_t) < previous_time
	if restart:
		if trail:
			trail.emitting = false
		var fade := float(config.feel.fadeDefault)
		if ent.state in ["hurt", "dodge", "attack"]:
			fade = float(config.feel.fadeFast)
		elif ent.state in ["idle", "run", "move", "walk"]:
			fade = float(config.feel.fadeSlow)
		player.play(name, actual, hit, fade, true)
	previous_state = key
	previous_time = ent.state_t
	if not frozen and dt > 0.0:
		var sub := clampi(int(ceil(dt / 0.01)), 1, 6) if (trail and ent.state in ["attack", "thrust", "cast", "ult"]) else 1
		var h := dt / float(sub)
		var tip := Vector2.ZERO
		for i in sub:
			player.advance(h)
			if trail:
				tip = player.to_global(player.socket("spearTip"))
				if trail.emitting:
					trail.push_substep(tip, 0.0)
		if trail:
			# One ribbon rebuild per frame; substeps only add arc samples.
			trail.tick(dt, tip)

func _event(ev: Dictionary) -> void:
	match String(ev.name):
		"trail_on":
			if trail:
				trail.samples.clear()
				trail.emitting = true
		"trail_off":
			if trail:
				trail.emitting = false
		"sfx":
			var name := String(ev.get("arg", ""))
			if sound.sound_names().has(name):
				sound.play(name)
		"hit":
			tip_active = true

func _exit_tree() -> void:
	if is_instance_valid(trail):
		trail.queue_free()
