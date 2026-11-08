extends SceneTree
## Headless core simulation: godot --headless --path . -s tools/sim.gd [-- seeds=5 god=0]
## Bot: walks to nearest enemy, attacks, uses skills/ult, dodges telegraphs, picks first card.

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var f := FileAccess.open("res://config/game.json", FileAccess.READ)
	var cfg: Dictionary = JSON.parse_string(f.get_as_text())
	var seeds := int(args.get("seeds", "5"))
	var wins := 0
	for s in seeds:
		var r := run(cfg, 1000 + s, args.get("god", "0") == "1")
		print("seed=%d result=%s time=%.1fs wave=%d hp=%.0f kills=%d maxCombo=%d dmg=%.0f picks=%s" % [
			1000 + s, r.result, r.time, r.wave, r.hp, r.kills, r.maxCombo, r.dmg, r.picks])
		if r.result == "win":
			wins += 1
	print("SIM_DONE wins=%d/%d" % [wins, seeds])
	quit()

func run(cfg: Dictionary, seed_value: int, god: bool) -> Dictionary:
	var g := CoreGame.new(cfg, seed_value)
	g.god = god
	var dt := 1.0 / 60.0
	var t := 0.0
	var bot := Bot.new()
	var ev_count := {}
	while t < 600.0 and g.result == "":
		for ev in g.events:
			ev_count[ev.type] = int(ev_count.get(ev.type, 0)) + 1
		if g.phase == "draft":
			g.choose_card(g.draft_options[0])
		var inp := bot.think(g)
		g.events.clear()
		g.step(dt, inp)
		t += dt
	var picks: Array = g.picked.keys()
	return {"result": g.result if g.result != "" else "timeout", "time": t, "wave": g.wave_index + 1, "hp": g.player.hp,
		"kills": g.kills, "maxCombo": g.max_combo, "dmg": g.total_damage, "picks": picks, "ev": ev_count}
