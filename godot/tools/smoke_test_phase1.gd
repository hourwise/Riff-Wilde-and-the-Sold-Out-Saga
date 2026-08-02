extends SceneTree
## Automated verification for Phase 1 (foundation).
##
##   godot --headless --path godot --script res://tools/smoke_test_phase1.gd
##
## Exits non-zero on failure so this can gate a build later. Covers the wiring that
## is easy to break silently: input bindings that never match, missing audio buses,
## and pause suspension that does not actually stop the tree.

const EXPECTED_ACTIONS: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right",
	"camera_left", "camera_right", "camera_up", "camera_down",
	"strike", "sing", "dodge", "lock_on", "summon_companion",
	"interact", "pause", "map_toggle", "restart",
]

const EXPECTED_BUSES: PackedStringArray = [
	"Master", "Music", "MusicAmbient", "MusicCombat", "MusicBoss",
	"SFX", "SFXPlayer", "SFXWorld", "SFXUI",
]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	# Autoloads are constructed before the first idle frame; wait for them.
	await process_frame
	await process_frame

	print("\n=== Phase 1 smoke test ===\n")
	_test_input_map()
	_test_audio_buses()
	_test_sound_resolution()
	_test_autoloads()
	await _test_pause_suspension()
	_test_settings_round_trip()

	print("\n=== %d/%d checks passed ===" % [_checks - _failures, _checks])
	if _failures > 0:
		print("FAILED\n")
		quit(1)
		return
	print("PASSED\n")
	quit(0)


# ── Tests ────────────────────────────────────────────────────────

func _test_input_map() -> void:
	for action: String in EXPECTED_ACTIONS:
		if not _check(InputMap.has_action(action), "action '%s' exists" % action):
			continue

		var events: Array[InputEvent] = InputMap.action_get_events(action)
		_check(events.size() > 0, "action '%s' has bindings" % action)

		# A binding whose device is not -1 is silently skipped by InputMap, which
		# looks identical to a working binding until you press the key.
		var all_any_device: bool = true
		for event in events:
			if event.device != -1:
				all_any_device = false
		_check(all_any_device, "action '%s' binds to any device" % action)


## Sounds arrive one file at a time, in whatever format they were produced in, and
## a sound that cannot be found is silent rather than loud — the exact failure the
## player is least likely to report and the developer least likely to notice.
func _test_sound_resolution() -> void:
	var audio: Node = root.get_node_or_null("AudioManager")
	if not _check(audio != null, "AudioManager available"):
		return

	# The lute impact is declared as wanting three variations but only the first
	# has been delivered, and it is a .wav rather than the .ogg the spec asks for.
	# Both fallbacks have to hold or the most-heard sound in the game is missing.
	var path: String = String(audio.call("_resolve_path", &"riff_strike_impact"))
	_check(
		ResourceLoader.exists(path),
		"the lute impact resolves to a file that exists (%s)" % path.get_file()
	)

	# Asked repeatedly, because the variation is chosen at random: picking the two
	# undelivered ones must still fall back rather than returning a dead path.
	var misses: int = 0
	for i in range(40):
		if not ResourceLoader.exists(String(audio.call("_resolve_path", &"riff_strike_impact"))):
			misses += 1
	_check(misses == 0, "it resolves on every roll of the variation dice (%d misses in 40)" % misses)

	# A sound with no variations and no file must still report a sensible path
	# rather than crash or resolve to something unrelated.
	var absent: String = String(audio.call("_resolve_path", &"definitely_not_a_real_sound"))
	_check(
		not ResourceLoader.exists(absent) and absent.contains("definitely_not_a_real_sound"),
		"a missing sound reports its own name"
	)

	# Repeated sounds are pitched, one-shots are not.
	var pitched: bool = false
	for i in range(40):
		if not is_equal_approx(float(audio.call("_pitch_for", &"riff_strike_impact")), 1.0):
			pitched = true
			break
	_check(pitched, "repeated hits are pitch-varied so they do not machine-gun")
	_check(
		is_equal_approx(float(audio.call("_pitch_for", &"ui_back")), 1.0),
		"one-shot and UI sounds are left at their authored pitch"
	)


func _test_audio_buses() -> void:
	for bus: String in EXPECTED_BUSES:
		_check(AudioServer.get_bus_index(bus) >= 0, "audio bus '%s' exists" % bus)

	var music_index: int = AudioServer.get_bus_index("MusicCombat")
	if music_index >= 0:
		_check(
			AudioServer.get_bus_send(music_index) == "Music",
			"MusicCombat routes into Music"
		)


func _test_autoloads() -> void:
	for name: String in ["EventBus", "SaveService", "GameManager", "AudioManager", "SceneLoader", "UIRoot"]:
		_check(root.has_node(name), "autoload '%s' present" % name)

	var ui_root: Node = root.get_node_or_null("UIRoot")
	if ui_root != null:
		_check(ui_root.get("pause_menu") != null, "UIRoot instanced the pause menu")

	# EventBus must be stateless — a stray variable here means logic crept in.
	# get_script_property_list() also reports the script's category entry, so filter
	# down to genuine declared variables.
	var event_bus: Node = root.get_node_or_null("EventBus")
	if event_bus != null:
		var declared_variables: Array = []
		for property: Dictionary in event_bus.get_script().get_script_property_list():
			if int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				declared_variables.append(property.get("name", ""))
		_check(
			declared_variables.is_empty(),
			"EventBus declares no state (found: %s)" % str(declared_variables)
		)


func _test_pause_suspension() -> void:
	var game_manager: Node = root.get_node_or_null("GameManager")
	var ui_root: Node = root.get_node_or_null("UIRoot")
	if game_manager == null or ui_root == null:
		_check(false, "pause suspension testable")
		return

	var pause_menu: Node = ui_root.get("pause_menu")
	if pause_menu == null:
		_check(false, "pause menu available")
		return

	pause_menu.call("open")
	await process_frame
	_check(paused, "opening the pause menu suspends the tree")
	_check(bool(pause_menu.call("is_open")), "pause menu reports open")

	# A second suspend reason must keep the game suspended after the menu closes,
	# so a cinematic cannot be resumed out from under itself.
	game_manager.call("suspend", 1)  # SuspendReason.CINEMATIC
	pause_menu.call("close")
	await process_frame
	_check(paused, "tree stays suspended while a cinematic holds it")

	game_manager.call("release_suspend", 1)
	await process_frame
	_check(not paused, "releasing the last reason resumes the tree")


func _test_settings_round_trip() -> void:
	var save_service: Node = root.get_node_or_null("SaveService")
	if save_service == null:
		_check(false, "SaveService available")
		return

	var original: float = float(save_service.call("get_setting", "audio/music_volume"))

	save_service.call("set_setting", "audio/music_volume", 0.35)
	_check(save_service.call("save_settings"), "settings write to disk")
	save_service.call("load_settings")
	_check(
		is_equal_approx(float(save_service.call("get_setting", "audio/music_volume")), 0.35),
		"settings survive a reload"
	)

	save_service.call("set_setting", "audio/music_volume", original)
	save_service.call("save_settings")


# ── Helpers ──────────────────────────────────────────────────────

func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if condition:
		print("  ok    %s" % description)
		return true

	_failures += 1
	print("  FAIL  %s" % description)
	return false
