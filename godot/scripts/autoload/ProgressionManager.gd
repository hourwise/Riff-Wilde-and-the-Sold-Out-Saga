extends Node

var current_xp: int = 0
var current_level: int = 1
var unlocked_skills: Array[String] = []
var mission_active: bool = false
var current_mission_stats: Dictionary = {}
var last_mission_summary: Dictionary = {}

func _ready() -> void:
	print("[ProgressionManager] Initializing...")
	_load_progression()

func add_xp(amount: int) -> void:
	current_xp += amount
	_recalculate_level()
	print("[ProgressionManager] XP added: %d. Total XP: %d" % [amount, current_xp])
	_save_progression()

func unlock_skill(skill_id: String) -> bool:
	if not unlocked_skills.has(skill_id):
		unlocked_skills.append(skill_id)
		print("[ProgressionManager] Unlocked skill: ", skill_id)
		_save_progression()
		return true
	return false

func start_mission(mission_id: String) -> void:
	mission_active = true
	current_mission_stats = {
		"mission_id": mission_id,
		"started_msec": Time.get_ticks_msec(),
		"damage_dealt": 0.0,
		"armor_damage": 0.0,
		"damage_taken": 0.0,
		"enemies_defeated": 0,
		"combos_completed": 0,
		"scouting_completed": false
	}
	print("[ProgressionManager] Mission started: %s" % mission_id)

func record_damage_dealt(amount: float) -> void:
	if mission_active:
		current_mission_stats["damage_dealt"] = float(current_mission_stats.get("damage_dealt", 0.0)) + maxf(amount, 0.0)

func record_armor_damage(amount: float) -> void:
	if mission_active:
		current_mission_stats["armor_damage"] = float(current_mission_stats.get("armor_damage", 0.0)) + maxf(amount, 0.0)

func record_damage_taken(amount: float) -> void:
	if mission_active:
		current_mission_stats["damage_taken"] = float(current_mission_stats.get("damage_taken", 0.0)) + maxf(amount, 0.0)

func record_enemy_defeated() -> void:
	if mission_active:
		current_mission_stats["enemies_defeated"] = int(current_mission_stats.get("enemies_defeated", 0)) + 1

func record_combo_completed() -> void:
	if mission_active:
		current_mission_stats["combos_completed"] = int(current_mission_stats.get("combos_completed", 0)) + 1

func record_scouting_completed() -> void:
	if mission_active:
		current_mission_stats["scouting_completed"] = true

func complete_mission() -> Dictionary:
	if not mission_active:
		return last_mission_summary

	var elapsed_seconds: float = float(Time.get_ticks_msec() - int(current_mission_stats.get("started_msec", Time.get_ticks_msec()))) / 1000.0
	var enemies_defeated: int = int(current_mission_stats.get("enemies_defeated", 0))
	var combos_completed: int = int(current_mission_stats.get("combos_completed", 0))
	var damage_dealt: float = float(current_mission_stats.get("damage_dealt", 0.0))
	var armor_damage: float = float(current_mission_stats.get("armor_damage", 0.0))
	var scouting_bonus: int = 25 if bool(current_mission_stats.get("scouting_completed", false)) else 0
	var time_bonus: int = maxi(0, 90 - int(elapsed_seconds))
	var xp_awarded: int = 50 + enemies_defeated * 25 + combos_completed * 15 + int((damage_dealt + armor_damage) * 0.15) + scouting_bonus + time_bonus

	last_mission_summary = current_mission_stats.duplicate()
	last_mission_summary["elapsed_seconds"] = elapsed_seconds
	last_mission_summary["xp_awarded"] = xp_awarded
	last_mission_summary["total_xp_after_award"] = current_xp + xp_awarded

	add_xp(xp_awarded)
	mission_active = false
	print("[ProgressionManager] Mission complete. XP awarded: %d" % xp_awarded)
	return last_mission_summary

func consume_last_mission_summary() -> Dictionary:
	var summary := last_mission_summary.duplicate()
	last_mission_summary.clear()
	return summary

func get_progression_save_data() -> Dictionary:
	return {
		"current_xp": current_xp,
		"current_level": current_level,
		"unlocked_skills": unlocked_skills.duplicate()
	}

func apply_progression_save_data(data: Dictionary) -> void:
	current_xp = max(0, int(data.get("current_xp", 0)))
	current_level = max(1, int(data.get("current_level", 1)))
	unlocked_skills.clear()

	var saved_skills: Variant = data.get("unlocked_skills", [])
	if saved_skills is Array:
		for skill in saved_skills:
			unlocked_skills.append(String(skill))

	_recalculate_level()
	print("[ProgressionManager] Loaded progression. XP: %d, Level: %d, Skills: %d" % [current_xp, current_level, unlocked_skills.size()])

func _load_progression() -> void:
	var save_service := get_node_or_null("/root/SaveService")
	if not save_service or not save_service.has_method("load_progression"):
		return

	var data: Dictionary = save_service.call("load_progression")
	if data.is_empty():
		return

	apply_progression_save_data(data)

func _save_progression() -> void:
	var save_service := get_node_or_null("/root/SaveService")
	if save_service and save_service.has_method("save_progression"):
		save_service.call("save_progression", get_progression_save_data())

func _recalculate_level() -> void:
	current_level = max(1, int(floor(float(current_xp) / 500.0)) + 1)
