extends Node3D

const MISSION_SCENE_PATH := "res://scenes/levels/ChurchGraveyard.tscn"

var prompt_label: Label = null
var mission_panel: PanelContainer = null
var results_panel: PanelContainer = null
var mission_panel_open: bool = false
var results_panel_open: bool = false

@onready var quest_board: Node = $QuestBoard

func _ready() -> void:
	GameManager.change_state(GameManager.GameState.INN_HUB)

	_create_ui()
	_show_last_mission_results()
	if quest_board.has_signal("player_entered"):
		quest_board.player_entered.connect(_show_interact_prompt)
	if quest_board.has_signal("player_exited"):
		quest_board.player_exited.connect(_hide_interact_prompt)
	if quest_board.has_signal("mission_requested"):
		quest_board.mission_requested.connect(_open_mission_panel)
	print("[TavernHub] Ready.")

func _unhandled_input(event: InputEvent) -> void:
	# Panels consume the pause action so it does not also reach the pause menu.
	if results_panel_open and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close_results_panel()
		return

	if not mission_panel_open:
		return

	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close_mission_panel()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.physical_keycode == KEY_ENTER or key_event.physical_keycode == KEY_KP_ENTER:
			_launch_mission()

func _create_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "TavernUI"
	add_child(canvas)

	prompt_label = Label.new()
	prompt_label.name = "QuestPromptLabel"
	prompt_label.text = "Press E to inspect the Quest Board"
	prompt_label.visible = false
	prompt_label.position = Vector2(32.0, 620.0)
	prompt_label.add_theme_font_size_override("font_size", 28)
	canvas.add_child(prompt_label)

	mission_panel = PanelContainer.new()
	mission_panel.name = "MissionPanel"
	mission_panel.visible = false
	mission_panel.position = Vector2(320.0, 180.0)
	mission_panel.size = Vector2(640.0, 260.0)
	canvas.add_child(mission_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	mission_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var title := Label.new()
	title.text = "Quest Board"
	title.add_theme_font_size_override("font_size", 34)
	content.add_child(title)

	var mission_text := Label.new()
	mission_text.text = "Available Mission: The Church Graveyard\n\nSomething has corrupted the old cemetery. Four Funeral Altars still burn wrong. Cleanse them all, and whatever is conducting this will come out to meet you."
	mission_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_text.add_theme_font_size_override("font_size", 22)
	content.add_child(mission_text)

	var instructions := Label.new()
	instructions.text = "Press Enter to launch mission. Press Esc to close."
	instructions.add_theme_font_size_override("font_size", 20)
	content.add_child(instructions)

	results_panel = PanelContainer.new()
	results_panel.name = "MissionResultsPanel"
	results_panel.visible = false
	results_panel.position = Vector2(330.0, 460.0)
	results_panel.size = Vector2(620.0, 220.0)
	canvas.add_child(results_panel)

func _show_interact_prompt() -> void:
	if prompt_label:
		prompt_label.visible = true

func _hide_interact_prompt() -> void:
	if prompt_label:
		prompt_label.visible = false
	_close_mission_panel()

func _open_mission_panel() -> void:
	mission_panel_open = true
	if mission_panel:
		mission_panel.visible = true
	if prompt_label:
		prompt_label.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close_mission_panel() -> void:
	mission_panel_open = false
	if mission_panel:
		mission_panel.visible = false
	if quest_board and quest_board.get("player_in_range") == true and prompt_label:
		prompt_label.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _launch_mission() -> void:
	GameManager.change_state(GameManager.GameState.MISSION)
	var progression_manager := get_node_or_null("/root/ProgressionManager")
	if progression_manager and progression_manager.has_method("start_mission"):
		progression_manager.call("start_mission", "church_graveyard")
	SceneLoader.load_scene(MISSION_SCENE_PATH, &"from_inn")

func _show_last_mission_results() -> void:
	var progression_manager := get_node_or_null("/root/ProgressionManager")
	if not progression_manager or not progression_manager.has_method("consume_last_mission_summary"):
		return

	var summary: Dictionary = progression_manager.call("consume_last_mission_summary")
	if summary.is_empty():
		return

	if not results_panel:
		return

	for child in results_panel.get_children():
		child.queue_free()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	results_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	var title := Label.new()
	title.text = "Encore Results"
	title.add_theme_font_size_override("font_size", 30)
	content.add_child(title)

	var elapsed: float = float(summary.get("elapsed_seconds", 0.0))
	var body := Label.new()
	body.text = "Mission: %s\nTime: %.1fs | Enemies: %d | Combos: %d\nDamage Dealt: %.1f | Armor Damage: %.1f | Damage Taken: %.1f\nXP Awarded: %d | Total XP: %d\n\nPress Esc to close." % [
		String(summary.get("mission_id", "mission")),
		elapsed,
		int(summary.get("enemies_defeated", 0)),
		int(summary.get("combos_completed", 0)),
		float(summary.get("damage_dealt", 0.0)),
		float(summary.get("armor_damage", 0.0)),
		float(summary.get("damage_taken", 0.0)),
		int(summary.get("xp_awarded", 0)),
		int(summary.get("total_xp_after_award", 0))
	]
	body.add_theme_font_size_override("font_size", 20)
	content.add_child(body)

	results_panel.visible = true
	results_panel_open = true

func _close_results_panel() -> void:
	results_panel_open = false
	if results_panel:
		results_panel.visible = false
