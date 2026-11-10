class_name CoreEntities
extends RefCounted
## Plain data holders for core simulation. No engine nodes.

class Player:
	var x := 300.0
	var y := 580.0
	var z := 0.0
	var vz := 0.0
	var facing := 1
	var hp := 300.0
	var max_hp := 300.0
	var mp := 100.0
	var max_mp := 100.0
	var rage := 0.0
	var state := "idle"      # idle run attack charge thrust dodge jump slam cast hurt dead ult
	var state_t := 0.0       # time in current state
	var state_dur := 0.0
	var moving := false
	# attack
	var combo_step := 0      # 0..2 current/last step
	var chain_t := 0.0       # time left to chain into next step after attack end
	var buffered := false    # attack pressed during attack (fires at feel.attackCancelAt)
	var buf := {}            # input buffer: action -> seconds left (feel.inputBuffer)
	var hit_done := false
	var holding := false
	var hold_t := 0.0
	var charged := false     # hold reached charge time
	var thrust_from := 0.0
	var thrust_hit := {}     # enemy id -> true
	# dodge
	var dodge_cd := 0.0
	var dodge_dx := 1.0
	var dodge_dy := 0.0
	var dodge_from := Vector2.ZERO
	var dodge_crit_ready := false
	var flame_drop := 0.0
	# misc
	var iframe := 0.0
	var stun := 0.0
	var kb_x := 0.0
	var kb_y := 0.0
	var flash := 0.0
	var air_attacked := false
	var cast_skill := ""
	var cast_data := {}
	var cds := {"crescent": 0.0, "skyfall": 0.0, "meteorSpear": 0.0}

class Enemy:
	var id := 0
	var type := "imp"
	var kind := "melee"
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var vz := 0.0
	var hp := 1.0
	var max_hp := 1.0
	var facing := -1
	var state := "spawn"      # spawn move orbit windup attack recover hurt dead charge_windup charging air
	var state_t := 0.0
	var state_dur := 0.0
	var stun := 0.0
	var kb_x := 0.0
	var kb_y := 0.0
	var flash := 0.0
	var cooldown := 0.0
	var token := false
	var orbit_a := 0.0
	var tx := 0.0             # locked target
	var ty := 0.0
	var dir_x := 0.0
	var dir_y := 0.0
	var travelled := 0.0
	var hit_player := false
	var move := ""            # boss move
	var enraged := false
	var dead_t := 0.0
	var radius := 22.0
	var cfg: Dictionary = {}
	var hit_by := {}          # source key -> true (for multi-tick skills)
	var airborne := false
	var think_t := 0.0
	var side := 1

	func alive() -> bool:
		return state != "dead"

class Hazard:
	## Timed effect owned by core: skyfall strike, fireball, spear, ember, flame, meteor.
	var id := 0
	var kind := ""
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var tx := 0.0
	var ty := 0.0
	var sx := 0.0
	var sy := 0.0
	var vx := 0.0
	var vy := 0.0
	var t := 0.0
	var life := 1.0
	var radius := 60.0
	var damage := 0.0
	var tick_t := 0.0
	var travelled := 0.0
	var hit := {}
	var done := false
	var data := {}
