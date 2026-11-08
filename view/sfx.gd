class_name Sfx
extends Node
## Sound playback. Uses res://assets/audio/<path>.ogg when imported, else a synthesized placeholder.

const RATE := 22050
var streams: Dictionary = {}
var players: Array = []
var next_player := 0
var last_play: Dictionary = {}
var bgm: AudioStreamPlayer
var muted := false
var _rng := CoreRng.new(7)

# layer: [wave, f0, f1, start, dur, vol, attack, lowpass(0..1, 1=none), curve]
const RECIPES := {
	"swing1": [["noise", 0, 0, 0.0, 0.16, 0.5, 0.03, 0.35, 2.0], ["sine", 900, 300, 0.0, 0.1, 0.12, 0.01, 1.0, 2.0]],
	"swing2": [["noise", 0, 0, 0.0, 0.17, 0.5, 0.03, 0.42, 2.0], ["sine", 1100, 380, 0.0, 0.1, 0.12, 0.01, 1.0, 2.0]],
	"swing3": [["noise", 0, 0, 0.0, 0.22, 0.6, 0.02, 0.3, 1.5], ["sine", 180, 60, 0.0, 0.18, 0.5, 0.005, 1.0, 2.0]],
	"charge_thrust": [["noise", 0, 0, 0.0, 0.3, 0.6, 0.01, 0.5, 1.2], ["saw", 220, 880, 0.0, 0.18, 0.18, 0.005, 0.4, 1.5], ["sine", 90, 40, 0.0, 0.25, 0.6, 0.005, 1.0, 2.0]],
	"hit": [["noise", 0, 0, 0.0, 0.07, 0.7, 0.001, 0.6, 3.0], ["sine", 160, 70, 0.0, 0.12, 0.8, 0.001, 1.0, 2.5]],
	"hit_crit": [["noise", 0, 0, 0.0, 0.09, 0.8, 0.001, 0.7, 3.0], ["sine", 180, 60, 0.0, 0.16, 0.9, 0.001, 1.0, 2.5], ["sine", 1800, 1500, 0.0, 0.18, 0.25, 0.001, 1.0, 1.5]],
	"dodge": [["noise", 0, 0, 0.0, 0.22, 0.35, 0.06, 0.25, 1.5]],
	"jump": [["sine", 220, 520, 0.0, 0.12, 0.3, 0.005, 1.0, 1.5], ["noise", 0, 0, 0.0, 0.1, 0.2, 0.01, 0.3, 2.0]],
	"land_slam": [["sine", 80, 35, 0.0, 0.45, 1.0, 0.002, 1.0, 1.8], ["noise", 0, 0, 0.0, 0.35, 0.7, 0.002, 0.25, 2.0]],
	"player_hurt": [["square", 330, 140, 0.0, 0.16, 0.3, 0.002, 0.5, 1.5], ["noise", 0, 0, 0.0, 0.08, 0.5, 0.001, 0.5, 3.0]],
	"enemy_hurt": [["noise", 0, 0, 0.0, 0.06, 0.5, 0.001, 0.35, 3.0], ["square", 260, 200, 0.0, 0.05, 0.12, 0.001, 0.5, 2.0]],
	"enemy_die": [["square", 420, 70, 0.0, 0.3, 0.25, 0.002, 0.4, 1.3], ["noise", 0, 0, 0.0, 0.3, 0.45, 0.002, 0.2, 1.5]],
	"skill1_crescent": [["noise", 0, 0, 0.0, 0.75, 0.7, 0.05, 0.12, 0.8], ["noise", 0, 0, 0.05, 0.25, 0.5, 0.01, 0.6, 2.0], ["saw", 110, 70, 0.0, 0.7, 0.18, 0.05, 0.15, 1.0], ["noise", 0, 0, 0.4, 0.22, 0.45, 0.01, 0.6, 2.0]],
	"skill2_charge": [["sine", 140, 440, 0.0, 0.42, 0.4, 0.05, 1.0, 0.3], ["sine", 280, 880, 0.0, 0.42, 0.18, 0.05, 1.0, 0.3], ["noise", 0, 0, 0.0, 0.42, 0.12, 0.2, 0.08, 0.3]],
	"skill2_strike": [["noise", 0, 0, 0.0, 0.12, 1.0, 0.0005, 0.95, 2.5], ["noise", 0, 0, 0.02, 1.0, 0.8, 0.01, 0.06, 1.2], ["sine", 60, 30, 0.0, 0.8, 0.9, 0.002, 1.0, 1.5], ["sine", 2400, 1200, 0.0, 0.15, 0.2, 0.0005, 1.0, 2.0]],
	"skill3_throw": [["noise", 0, 0, 0.0, 0.25, 0.6, 0.01, 0.55, 1.5], ["noise", 0, 0, 0.1, 0.45, 0.35, 0.05, 0.15, 1.0], ["saw", 600, 200, 0.0, 0.2, 0.12, 0.005, 0.3, 1.5]],
	"ult_impact": [["sine", 70, 28, 0.0, 0.55, 1.0, 0.002, 1.0, 1.6], ["noise", 0, 0, 0.0, 0.5, 0.8, 0.002, 0.3, 1.6]],
	"ult_start": [["noise", 0, 0, 0.0, 0.8, 0.5, 0.6, 0.1, 0.4], ["saw", 55, 110, 0.0, 0.9, 0.3, 0.3, 0.12, 0.5], ["sine", 1760, 1760, 0.6, 0.3, 0.15, 0.01, 1.0, 1.5]],
	"fireball_land": [["sine", 120, 45, 0.0, 0.3, 0.7, 0.002, 1.0, 1.8], ["noise", 0, 0, 0.0, 0.3, 0.6, 0.002, 0.35, 1.5]],
	"brute_charge": [["saw", 70, 50, 0.0, 0.55, 0.4, 0.05, 0.12, 1.0], ["noise", 0, 0, 0.0, 0.55, 0.4, 0.05, 0.1, 1.0]],
	"boss_appear": [["saw", 55, 55, 0.0, 1.6, 0.35, 0.3, 0.1, 0.8], ["saw", 82, 82, 0.1, 1.5, 0.3, 0.3, 0.1, 0.8], ["noise", 0, 0, 0.0, 1.0, 0.5, 0.002, 0.08, 1.2], ["sine", 40, 30, 0.0, 1.4, 0.8, 0.01, 1.0, 1.0]],
	"boss_slam": [["sine", 60, 25, 0.0, 0.6, 1.0, 0.002, 1.0, 1.5], ["noise", 0, 0, 0.0, 0.5, 0.8, 0.002, 0.22, 1.5]],
	"ui_click": [["sine", 1500, 1100, 0.0, 0.05, 0.35, 0.001, 1.0, 2.0]],
	"card_flip": [["noise", 0, 0, 0.0, 0.1, 0.4, 0.01, 0.5, 2.0], ["sine", 700, 1000, 0.0, 0.06, 0.12, 0.002, 1.0, 2.0]],
	"card_rare": [["sine", 880, 880, 0.0, 0.25, 0.3, 0.002, 1.0, 1.5], ["sine", 1109, 1109, 0.08, 0.25, 0.3, 0.002, 1.0, 1.5], ["sine", 1319, 1319, 0.16, 0.35, 0.3, 0.002, 1.0, 1.5], ["sine", 1760, 1760, 0.24, 0.5, 0.25, 0.002, 1.0, 1.2]],
	"victory": [["square", 523, 523, 0.0, 0.2, 0.2, 0.005, 0.4, 1.0], ["square", 659, 659, 0.18, 0.2, 0.2, 0.005, 0.4, 1.0], ["square", 784, 784, 0.36, 0.2, 0.2, 0.005, 0.4, 1.0], ["square", 1047, 1047, 0.54, 0.7, 0.22, 0.005, 0.4, 1.0], ["sine", 262, 262, 0.54, 0.7, 0.4, 0.005, 1.0, 1.0]],
	"defeat": [["saw", 392, 392, 0.0, 0.35, 0.2, 0.01, 0.2, 1.0], ["saw", 311, 311, 0.3, 0.35, 0.2, 0.01, 0.2, 1.0], ["saw", 262, 196, 0.6, 0.9, 0.22, 0.01, 0.2, 1.0]],
}

func _ready() -> void:
	for i in 14:
		var pl := AudioStreamPlayer.new()
		add_child(pl)
		players.append(pl)
	bgm = AudioStreamPlayer.new()
	bgm.volume_db = -9.0
	add_child(bgm)

func sound_names() -> Array:
	return RECIPES.keys()

## Load or synthesize one stream (call during loading screen).
func prepare(name: String) -> void:
	if streams.has(name):
		return
	var real_path := "res://assets/audio/sfx/%s.ogg" % name
	if ResourceLoader.exists(real_path):
		streams[name] = load(real_path)
	else:
		streams[name] = _synth(RECIPES[name])

func prepare_bgm() -> void:
	var real_path := "res://assets/audio/bgm/battle_loop.ogg"
	if ResourceLoader.exists(real_path):
		var s: AudioStream = load(real_path)
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		streams["bgm"] = s
	else:
		streams["bgm"] = _synth_bgm()

func play(name: String, vol_db := 0.0, pitch_var := 0.06, min_gap := 0.03, pitch := 1.0) -> void:
	if muted:
		return
	if not streams.has(name):
		if RECIPES.has(name):
			prepare(name)
		else:
			return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(last_play.get(name, -1.0)) < min_gap:
		return
	last_play[name] = now
	var pl: AudioStreamPlayer = players[next_player]
	next_player = (next_player + 1) % players.size()
	pl.stream = streams[name]
	pl.volume_db = vol_db
	pl.pitch_scale = pitch + randf_range(-pitch_var, pitch_var)
	pl.play()

func play_bgm() -> void:
	if not streams.has("bgm"):
		prepare_bgm()
	if bgm.playing:
		return
	bgm.stream = streams["bgm"]
	bgm.play()

func stop_bgm() -> void:
	bgm.stop()

# ------------------------------------------------------------------ synthesis
func _synth(layers: Array) -> AudioStreamWAV:
	var total := 0.0
	for L in layers:
		total = maxf(total, float(L[3]) + float(L[4]))
	var n := int(total * RATE) + 64
	var buf := PackedFloat32Array()
	buf.resize(n)
	for L in layers:
		_layer(buf, L)
	return _to_wav(buf, false)

func _layer(buf: PackedFloat32Array, L: Array) -> void:
	var wave: String = L[0]
	var f0 := float(L[1])
	var f1 := float(L[2])
	var start := int(float(L[3]) * RATE)
	var dur := float(L[4])
	var vol := float(L[5])
	var att := maxf(0.0005, float(L[6]))
	var lp := float(L[7])
	var curve := float(L[8])
	var ns := int(dur * RATE)
	var phase := 0.0
	var y := 0.0
	for i in ns:
		var t := float(i) / RATE
		var k := t / dur
		var env := minf(1.0, t / att) * pow(maxf(0.0, 1.0 - k), curve)
		var s := 0.0
		var f := f0 + (f1 - f0) * k
		phase += f / RATE
		match wave:
			"noise":
				s = _rng.randf() * 2.0 - 1.0
			"sine":
				s = sin(phase * TAU)
			"square":
				s = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
			"saw":
				s = fmod(phase, 1.0) * 2.0 - 1.0
		y += (s - y) * lp
		var idx := start + i
		if idx < buf.size():
			buf[idx] += y * env * vol

func _to_wav(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var peak := 0.001
	for v in buf:
		peak = maxf(peak, absf(v))
	var g := 0.85 / peak if peak > 0.85 else 1.0
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w

func _synth_bgm() -> AudioStreamWAV:
	# 8 bars of 4/4 at 128 bpm, D minor ostinato with kick/snare/hat.
	var bpm := 128.0
	var beat := 60.0 / bpm
	var bars := 4
	var n := int(beat * 4.0 * bars * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var bass := [36.71, 36.71, 43.65, 41.20]  # D1 D1 F1 E1 (Hz*?) -> multiplied below
	for b in bars * 4:
		var t0 := float(b) * beat
		_layer(buf, ["sine", 110, 40, t0, 0.22, 0.9, 0.002, 1.0, 2.0])                   # kick
		if b % 2 == 1:
			_layer(buf, ["noise", 0, 0, t0, 0.16, 0.35, 0.001, 0.55, 2.5])               # snare
		for h in 2:
			_layer(buf, ["noise", 0, 0, t0 + h * beat * 0.5, 0.04, 0.12, 0.001, 0.9, 3.0])  # hat
		var root: float = bass[(b / 4) % 4] * 2.0
		for e in 2:
			_layer(buf, ["saw", root, root, t0 + e * beat * 0.5, beat * 0.45, 0.22, 0.005, 0.18, 1.2])
	# pad
	var chords := [[146.8, 174.6, 220.0], [146.8, 174.6, 220.0], [174.6, 220.0, 261.6], [164.8, 207.7, 246.9]]
	for c in bars:
		for f in chords[c]:
			_layer(buf, ["saw", f, f, c * beat * 4.0, beat * 4.0, 0.05, 0.4, 0.06, 0.6])
	return _to_wav(buf, true)
