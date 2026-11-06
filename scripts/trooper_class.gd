## Data-driven trooper classes + class weapons (v1.1).
extends RefCounted
class_name TrooperClass

const IDS := ["assault", "heavy", "sniper", "officer"]
const NAMES := ["Assault", "Heavy", "Sniper", "Officer"]
const DESCS := [
	"Balanced frontliner. DC-15A rifle + DP-23 scatter.",
	"Armored gunner. Z-6 rotary + explosive repeater.",
	"Recon sharpshooter. Valken longblaster + scout sidearm.",
	"Tactical commander. Burst carbine + S-5 pistol. Aura + Battle Command (X).",
]

## Per-class base stats. Weapons: array of weapon defs (slot 0 primary, slot 1 secondary).
static func def(cls: int) -> Dictionary:
	match clampi(cls, 0, 3):
		1:  # Heavy
			return {
				"id": 1, "name": "Heavy", "hp": 145.0, "speed": 0.86,
				"weapons": [
					{"name": "Z-6 ROTARY", "kind": "z6", "mag": 60, "dmg": 14.0, "interval": 0.13,
						"bolt": 3, "auto": true, "spin_up": true, "min_interval": 0.055, "fire_slow": 0.72},
					{"name": "DC-15LE EXP", "kind": "explosive", "mag": 12, "dmg": 34.0, "interval": 0.36,
						"bolt": 3, "splash": 18.0, "splash_r": 2.2, "reload": 1.6},
				],
			}
		2:  # Sniper
			return {
				"id": 2, "name": "Sniper", "hp": 85.0, "speed": 1.10,
				"weapons": [
					{"name": "VALKEN-38X", "kind": "sniper", "mag": 6, "dmg": 95.0, "interval": 0.85,
						"bolt": 2, "scope": 2.8, "head_mult": 1.5, "reload": 2.0, "ads_spread": 0.0},
					{"name": "DC-17s", "kind": "pistol", "mag": 15, "dmg": 22.0, "interval": 0.16,
						"bolt": 0, "reload": 0.9},
				],
			}
		3:  # Officer
			return {
				"id": 3, "name": "Officer", "hp": 105.0, "speed": 1.04,
				"aura_r": 12.0, "aura_dmg": 1.15, "aura_regen": 3.0,
				"cmd_cd": 18.0, "cmd_shield": 25.0, "cmd_speed": 1.2, "cmd_dur": 6.0,
				"weapons": [
					{"name": "BLURRG-1120", "kind": "burst", "mag": 24, "dmg": 16.0, "interval": 0.42,
						"bolt": 0, "burst": 4, "burst_gap": 0.045},
					{"name": "S-5 HEAVY", "kind": "handcannon", "mag": 8, "dmg": 52.0, "interval": 0.42,
						"bolt": 3, "reload": 1.5},
				],
			}
		_:  # Assault
			return {
				"id": 0, "name": "Assault", "hp": 100.0, "speed": 1.00,
				"weapons": [
					{"name": "DC-15A RIFLE", "kind": "rifle", "mag": 28, "dmg": 26.0, "interval": 0.13,
						"bolt": 0, "auto": true},
					{"name": "DP-23 SCATTER", "kind": "scatter", "mag": 8, "dmg": 11.0, "interval": 0.85,
						"bolt": 2, "pellets": 8, "range": 30.0, "reload": 1.8},
				],
			}


static func clamp_id(cls: int) -> int:
	return clampi(cls, 0, 3)


static func weapon(cls: int, slot: int) -> Dictionary:
	var d := def(cls)
	var w: Array = d["weapons"]
	return w[clampi(slot, 0, w.size() - 1)]
