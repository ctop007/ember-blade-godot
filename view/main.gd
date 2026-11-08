extends Node
## Root: loading -> home -> battle -> result. Owns CoreGame, BattleView, HUD, Controls, AI bridge.

var cfg: Dictionary
var sfx: Sfx
var world: Node2D
var ui: CanvasLayer
var screen := "loading"
var screen_node: Control
var game: CoreGame
var battle: BattleView
var hud: Hud
var controls: Controls
var draft: DraftModal
var pause_node: Control
var paused := false
var time_scale := 1.0
var insets := Vector4(16, 12, 16, 10)
var debug := false
var is_web := false
var bridge_t := 0.0
var load_step := 0
var loading: Screens.Loading
var fps_samples: Array = []
var result_shown := false
var last_vis := "visible"
var autoplay: Bot = null
var autoplay_frames := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = $World
	ui = $UI
	var f := FileAccess.open("res://config/game.json", FileAccess.READ)
	cfg = JSON.parse_string(f.get_as_text())
	Particles.cap = int(cfg.combat.maxParticles)
	sfx = Sfx.new()
	add_child(sfx)
	is_web = OS.has_feature("web")
	if is_web:
		debug = str(JavaScriptBridge.eval("location.search")).contains("debug")
		_install_bridge()
		_read_insets()
	get_viewport().size_changed.connect(_read_insets)
	loading = Screens.Loading.new()
	ui.add_child(loading)
	screen_node = loading

# ------------------------------------------------------------------ loading (progressive)
func _load_tick() -> void:
	var gen_n := Art.gen_count()
	var snd: Array = sfx.sound_names()
	var real_imgs: Array = []
	for path in Art.manifest().keys():
		if path.ends_with(".png") and Art.has_real(path):
			real_imgs.append(path)
	var total := gen_n + snd.size() + 1 + real_imgs.size()
	var budget := Time.get_ticks_msec() + 30
	while Time.get_ticks_msec() < budget and load_step < total:
		var i := load_step
		if i < gen_n:
			Art.gen_step(i)
		elif i < gen_n + snd.size():
			sfx.prepare(snd[i - gen_n])
		elif i == gen_n + snd.size():
			sfx.prepare_bgm()
		else:
			Art.real(real_imgs[i - gen_n - snd.size() - 1])
		load_step += 1
	loading.progress = float(load_step) / float(total)
	loading.tip = ["正在点燃余烬……", "磨砺长枪……", "唤醒森林……"][int(loading.progress * 2.99)]
	if load_step >= total:
		show_home()
		if OS.get_cmdline_user_args().has("--autoplay"):
			autoplay = Bot.new()
			time_scale = 3.0
			start_battle()
			game.god = true

# ------------------------------------------------------------------ screens
func _set_screen(n: Control, name: String) -> void:
	if screen_node and is_instance_valid(screen_node):
		screen_node.queue_free()
	screen_node = n
	screen = name
	if n:
		ui.add_child(n)

func show_home() -> void:
	_end_battle()
	_set_screen(Screens.home(sfx, insets, start_battle, _show_qr), "home")

func _show_qr() -> void:
	ui.add_child(Screens.qr_modal(sfx))

func start_battle() -> void:
	_end_battle()
	_set_screen(null, "battle")
	game = CoreGame.new(cfg, int(cfg.seed) + int(Time.get_unix_time_from_system()) % 100000)
	battle = BattleView.new()
	world.add_child(battle)
	battle.setup(game, sfx)
	hud = Hud.new()
	hud.game = game
	hud.insets = insets
	ui.add_child(hud)
	battle.hud = hud
	controls = Controls.new()
	controls.game = game
	controls.insets = insets
	ui.add_child(controls)
	paused = false
	result_shown = false
	sfx.play_bgm()

func _end_battle() -> void:
	for n in [battle, hud, controls, draft, pause_node]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	battle = null
	hud = null
	controls = null
	draft = null
	pause_node = null
	if game:
		game.dispose()
	game = null
	paused = false
	Particles.total = 0
	sfx.stop_bgm()

func set_paused(on: bool) -> void:
	if screen != "battle" or game == null or (on and game.result != ""):
		return
	if on == paused:
		return
	paused = on
	battle.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	hud.process_mode = battle.process_mode
	if on:
		controls.set_enabled(false)
		pause_node = Screens.pause_menu(sfx, func(): set_paused(false), start_battle, show_home, _toggle_mute, sfx.muted)
		ui.add_child(pause_node)
	else:
		if pause_node and is_instance_valid(pause_node):
			pause_node.queue_free()
		pause_node = null
		controls.set_enabled(draft == null)

func _toggle_mute() -> void:
	sfx.muted = not sfx.muted
	if sfx.muted:
		sfx.stop_bgm()
	else:
		sfx.play_bgm()
	set_paused(false)
	set_paused(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		set_paused(true)

# ------------------------------------------------------------------ frame
func _process(dt: float) -> void:
	if screen == "loading":
		_load_tick()
	fps_samples.append(Engine.get_frames_per_second())
	if fps_samples.size() > 30:
		fps_samples.pop_front()
	if is_web:
		_bridge_poll(dt)
	if screen != "battle" or game == null:
		return
	if controls.poll_pause():
		set_paused(not paused)
	if paused:
		return
	var inp: Dictionary = controls.poll()
	if autoplay:
		autoplay_frames += 1
		inp = autoplay.think(game)
		if draft and draft.ready_to_pick and not draft.done:
			draft._on_choose(draft.cards[0])
		if autoplay_frames % 300 == 0:
			print("AUTOPLAY f=%d wave=%d phase=%s hp=%d enemies=%d particles=%d fps=%d" % [autoplay_frames, game.wave_index + 1, game.phase, game.player.hp, game.alive_enemies().size(), Particles.total, Engine.get_frames_per_second()])
	var sdt := minf(dt, 0.1) * time_scale
	var steps := maxi(1, int(ceil(sdt / (1.0 / 60.0))))
	var h := sdt / steps
	for i in steps:
		game.step(h, inp if i == 0 else {"mx": inp.mx, "my": inp.my, "attack_held": inp.attack_held})
	battle.sync(sdt)
	for ev in battle.fx_skill_fail:
		controls.flash_fail(ev)
	battle.fx_skill_fail.clear()
	if game.phase == "draft" and draft == null:
		_open_draft()
	if game.result != "" and game.phase_t > 1.6 and not result_shown:
		_show_result()
		if autoplay:
			print("AUTOPLAY_DONE result=%s time=%.1f kills=%d" % [game.result, game.time, game.kills])
			get_tree().quit()

func _open_draft() -> void:
	controls.set_enabled(false)
	draft = DraftModal.new()
	ui.add_child(draft)
	draft.open(game.draft_options, cfg, sfx)
	draft.picked.connect(func(id: String):
		game.choose_card(id)
		draft = null
		if controls:
			controls.set_enabled(not paused))

func _show_result() -> void:
	result_shown = true
	controls.set_enabled(false)
	var win := game.result == "win"
	sfx.stop_bgm()
	sfx.play("victory" if win else "defeat")
	var stats := {"time": game.time, "kills": game.kills, "maxCombo": game.max_combo, "damage": game.total_damage}
	pause_node = Screens.result(sfx, win, stats, start_battle, show_home)
	ui.add_child(pause_node)
	screen = "result"

# ------------------------------------------------------------------ safe area
func _read_insets() -> void:
	var l := 16.0
	var t := 12.0
	var r := 16.0
	var b := 10.0
	if is_web:
		var js := "(function(){var d=document.getElementById('__sa');if(!d){d=document.createElement('div');d.id='__sa';d.style.cssText='position:fixed;left:0;top:0;width:0;height:0;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left);visibility:hidden;pointer-events:none';document.body.appendChild(d);}var s=getComputedStyle(d);return JSON.stringify([parseFloat(s.paddingLeft)||0,parseFloat(s.paddingTop)||0,parseFloat(s.paddingRight)||0,parseFloat(s.paddingBottom)||0,window.innerHeight]);})()"
		var v: Variant = JSON.parse_string(str(JavaScriptBridge.eval(js)))
		if v is Array and v.size() == 5 and float(v[4]) > 0.0:
			var k := get_viewport().get_visible_rect().size.y / float(v[4])
			l = maxf(l, float(v[0]) * k)
			t = maxf(t, float(v[1]) * k)
			r = maxf(r, float(v[2]) * k)
			b = maxf(b, float(v[3]) * k)
	insets = Vector4(l, t, r, b)
	if controls:
		controls.insets = insets
		controls.layout()
	if hud:
		hud.insets = insets

# ------------------------------------------------------------------ AI bridge (?debug only)
func _install_bridge() -> void:
	var js := """
(function(){
  window.__jr = window.__jr || {q: [], state: null, vis: document.visibilityState};
  document.addEventListener('visibilitychange', function(){ window.__jr.vis = document.visibilityState; });
  if (!/debug/.test(location.search)) return;
  var q = function(cmd){ return function(){ window.__jr.q.push([cmd].concat([].slice.call(arguments))); return true; }; };
  window.__AI_BRIDGE__ = {
    state: function(){ return window.__jr.state ? window.__jr.state.game : null; },
    full: function(){ return window.__jr.state; },
    cast: q('cast'), spawn: q('spawn'), setWave: q('setWave'), draft: q('draft'),
    timeScale: q('timeScale'), god: q('god'), pick: q('pick'), start: q('start'), pause: q('pause'),
    toCss: function(x, y){ var c = document.querySelector('canvas'); var r = c.getBoundingClientRect(); var s = window.__jr.state;
      var lw = s ? s.view[0] : 1280, lh = s ? s.view[1] : 720; return [r.left + x * r.width / lw, r.top + y * r.height / lh]; }
  };
})();
"""
	JavaScriptBridge.eval(js)

func _bridge_poll(dt: float) -> void:
	var raw := str(JavaScriptBridge.eval("(function(){var j=window.__jr;if(!j)return '[[],\"visible\"]';var q=j.q;j.q=[];return JSON.stringify([q,j.vis]);})()"))
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Array and parsed.size() == 2:
		var vis := String(parsed[1])
		if vis != last_vis:
			last_vis = vis
			if vis == "hidden":
				set_paused(true)
		if debug:
			for cmd in parsed[0]:
				_bridge_cmd(cmd)
	if not debug:
		return
	bridge_t -= dt
	if bridge_t > 0.0:
		return
	bridge_t = 0.1
	var st := {"screen": screen, "paused": paused, "view": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"insets": [insets.x, insets.y, insets.z, insets.w], "fps": _fps(), "particles": Particles.total}
	if game:
		var g := game.debug_state()
		g["fps"] = _fps()
		st["game"] = g
	if controls:
		st["layout"] = controls.layout_info()
	if draft and is_instance_valid(draft):
		st["cards"] = draft.card_centers()
		st["cardsReady"] = draft.ready_to_pick
	if screen_node and is_instance_valid(screen_node) and screen == "home":
		var h := screen_node.get_child(1)
		var sb: Control = h.get_node("Start")
		st["startBtn"] = [sb.position.x + sb.size.x * 0.5, sb.position.y + sb.size.y * 0.5]
	if pause_node and is_instance_valid(pause_node) and screen == "result":
		var again: Control = pause_node.get_child(1).get_node("Again")
		st["againBtn"] = [again.global_position.x + again.size.x * 0.5, again.global_position.y + again.size.y * 0.5]
	JavaScriptBridge.eval("window.__jr.state = " + JSON.stringify(st) + ";")

func _fps() -> float:
	var s := 0.0
	for v in fps_samples:
		s += v
	return s / maxf(1.0, fps_samples.size())

func _bridge_cmd(cmd: Array) -> void:
	var name := String(cmd[0])
	match name:
		"start":
			start_battle()
		"pause":
			set_paused(bool(cmd[1]) if cmd.size() > 1 else not paused)
		"timeScale":
			time_scale = clampf(float(cmd[1]), 0.05, 10.0)
			Engine.time_scale = time_scale
	if game == null:
		return
	match name:
		"cast":
			var s := String(cmd[1])
			var map := {"skill1": "crescent", "skill2": "skyfall", "skill3": "meteorSpear", "crescent": "crescent", "skyfall": "skyfall", "meteorSpear": "meteorSpear"}
			if s in ["ult", "ultimate"]:
				game.pctl.try_ult(true)
			elif map.has(s):
				game.player.state = "idle"
				game.pctl.try_skill(map[s], true)
		"spawn":
			game.debug_spawn(String(cmd[1]), int(cmd[2]) if cmd.size() > 2 else 1)
		"setWave":
			game.debug_set_wave(int(cmd[1]))
		"draft":
			if game.phase != "draft":
				game.open_draft(game.phase == "wave")
		"god":
			game.god = bool(cmd[1]) if cmd.size() > 1 else true
		"pick":
			if game.phase == "draft" and draft:
				var i := int(cmd[1])
				if i < draft.cards.size():
					draft._on_choose(draft.cards[i])
