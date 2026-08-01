extends CanvasLayer
## Pause menu and settings. Hosted by the UIRoot autoload, so it is available in
## every scene without each level having to instance it.
##
## Suspension is requested through GameManager rather than setting
## get_tree().paused directly — a cinematic or dialogue can also be holding the
## game suspended, and closing this menu must not resume play underneath them.

@onready var _dim: ColorRect = $Dim
@onready var _root_menu: CenterContainer = $RootMenu
@onready var _settings_menu: CenterContainer = $SettingsMenu

@onready var _resume_button: Button = $RootMenu/Panel/Margin/Content/ResumeButton
@onready var _settings_button: Button = $RootMenu/Panel/Margin/Content/SettingsButton
@onready var _quit_to_inn_button: Button = $RootMenu/Panel/Margin/Content/QuitToInnButton
@onready var _quit_game_button: Button = $RootMenu/Panel/Margin/Content/QuitGameButton

@onready var _master_slider: HSlider = $SettingsMenu/Panel/Margin/Content/Options/MasterSlider
@onready var _music_slider: HSlider = $SettingsMenu/Panel/Margin/Content/Options/MusicSlider
@onready var _sfx_slider: HSlider = $SettingsMenu/Panel/Margin/Content/Options/SfxSlider
@onready var _mouse_slider: HSlider = $SettingsMenu/Panel/Margin/Content/Options/MouseSlider
@onready var _gamepad_slider: HSlider = $SettingsMenu/Panel/Margin/Content/Options/GamepadSlider
@onready var _invert_y_check: CheckButton = $SettingsMenu/Panel/Margin/Content/Options/InvertYCheck
@onready var _reset_button: Button = $SettingsMenu/Panel/Margin/Content/Buttons/ResetButton
@onready var _back_button: Button = $SettingsMenu/Panel/Margin/Content/Buttons/BackButton

var _is_open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_resume_button.pressed.connect(close)
	_settings_button.pressed.connect(_show_settings)
	_quit_to_inn_button.pressed.connect(_on_quit_to_inn)
	_quit_game_button.pressed.connect(_on_quit_game)
	_back_button.pressed.connect(_show_root)
	_reset_button.pressed.connect(_on_reset_settings)

	_master_slider.value_changed.connect(_on_master_changed)
	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_mouse_slider.value_changed.connect(_on_mouse_sensitivity_changed)
	_gamepad_slider.value_changed.connect(_on_gamepad_sensitivity_changed)
	_invert_y_check.toggled.connect(_on_invert_y_toggled)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return

	# Never steal the pause key mid-transition, or while a cinematic or dialogue is
	# what is holding the game suspended.
	if SceneLoader.is_transitioning():
		return
	if not _is_open and GameManager.is_suspended():
		return

	get_viewport().set_input_as_handled()
	if _is_open:
		close()
	else:
		open()


func open() -> void:
	if _is_open:
		return

	_is_open = true
	_load_settings_into_controls()
	_show_root()
	visible = true
	GameManager.suspend(GameManager.SuspendReason.PAUSE_MENU)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resume_button.grab_focus()
	AudioManager.play_ui(&"ui_confirm")


func close() -> void:
	if not _is_open:
		return

	_is_open = false
	visible = false
	SaveService.save_settings()
	GameManager.release_suspend(GameManager.SuspendReason.PAUSE_MENU)
	_restore_mouse_mode()
	AudioManager.play_ui(&"ui_back")


func is_open() -> bool:
	return _is_open


# ── Panels ───────────────────────────────────────────────────────

func _show_root() -> void:
	_root_menu.visible = true
	_settings_menu.visible = false
	_dim.visible = true
	_resume_button.grab_focus()


func _show_settings() -> void:
	_root_menu.visible = false
	_settings_menu.visible = true
	_master_slider.grab_focus()
	AudioManager.play_ui(&"ui_confirm")


# ── Settings ─────────────────────────────────────────────────────

## Populates controls without firing value_changed, so opening the menu does not
## immediately re-write the settings it just read.
func _load_settings_into_controls() -> void:
	_master_slider.set_value_no_signal(float(SaveService.get_setting("audio/master_volume")))
	_music_slider.set_value_no_signal(float(SaveService.get_setting("audio/music_volume")))
	_sfx_slider.set_value_no_signal(float(SaveService.get_setting("audio/sfx_volume")))
	_mouse_slider.set_value_no_signal(float(SaveService.get_setting("camera/mouse_sensitivity")))
	_gamepad_slider.set_value_no_signal(float(SaveService.get_setting("camera/gamepad_sensitivity")))
	_invert_y_check.set_pressed_no_signal(bool(SaveService.get_setting("camera/invert_y")))


func _on_master_changed(value: float) -> void:
	SaveService.set_setting("audio/master_volume", value)
	AudioManager.set_bus_volume_linear(AudioManager.BUS_MASTER, value)


func _on_music_changed(value: float) -> void:
	SaveService.set_setting("audio/music_volume", value)
	AudioManager.set_bus_volume_linear(AudioManager.BUS_MUSIC, value)


func _on_sfx_changed(value: float) -> void:
	SaveService.set_setting("audio/sfx_volume", value)
	AudioManager.set_bus_volume_linear(AudioManager.BUS_SFX, value)
	AudioManager.play_ui(&"ui_hover")


func _on_mouse_sensitivity_changed(value: float) -> void:
	SaveService.set_setting("camera/mouse_sensitivity", value)


func _on_gamepad_sensitivity_changed(value: float) -> void:
	SaveService.set_setting("camera/gamepad_sensitivity", value)


func _on_invert_y_toggled(pressed: bool) -> void:
	SaveService.set_setting("camera/invert_y", pressed)


func _on_reset_settings() -> void:
	SaveService.reset_settings()
	_load_settings_into_controls()
	AudioManager.apply_saved_volumes()
	AudioManager.play_ui(&"ui_confirm")


# ── Quitting ─────────────────────────────────────────────────────

func _on_quit_to_inn() -> void:
	_is_open = false
	visible = false
	SaveService.save_settings()
	GameManager.release_suspend(GameManager.SuspendReason.PAUSE_MENU)
	SceneLoader.load_scene("res://scenes/levels/TavernHub.tscn")


func _on_quit_game() -> void:
	SaveService.save_settings()
	get_tree().quit()


## Gameplay scenes capture the cursor; menus and the boot screen do not.
func _restore_mouse_mode() -> void:
	var in_gameplay: bool = (
		GameManager.is_state(GameManager.GameState.INN_HUB)
		or GameManager.is_state(GameManager.GameState.MISSION)
	)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if in_gameplay else Input.MOUSE_MODE_VISIBLE
