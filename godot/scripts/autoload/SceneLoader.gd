extends Node
## Scene transitions with a fade curtain and threaded loading.
##
## Every scene change in the demo goes through here so transitions are consistent
## and never show a frozen frame. The curtain lives on its own CanvasLayer above
## everything, and processes while paused so a transition can be started from a
## paused state (pause menu -> quit to hub).

const FADE_OUT_SECONDS: float = 0.45
const FADE_IN_SECONDS: float = 0.55
const CURTAIN_LAYER: int = 128

## Spawn point name for the next scene to read via consume_spawn_point(). Lets a
## level place the player at the correct entrance without the caller holding a
## reference to anything inside the target scene.
var _pending_spawn_point: StringName = &""
var _is_transitioning: bool = false

var _curtain_layer: CanvasLayer
var _curtain: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_curtain()
	print("[SceneLoader] Ready.")


## Changes scene with a fade out/in. Safe to call from anywhere; concurrent calls
## are ignored rather than queued, so a double-click on "start mission" cannot
## trigger two loads.
func load_scene(path: String, spawn_point: StringName = &"") -> void:
	if _is_transitioning:
		print("[SceneLoader] Ignored request for '%s': transition already running." % path)
		return

	if not ResourceLoader.exists(path):
		push_error("[SceneLoader] Scene does not exist: %s" % path)
		return

	_is_transitioning = true
	_pending_spawn_point = spawn_point
	EventBus.scene_transition_started.emit(path)

	await _fade(1.0, FADE_OUT_SECONDS)

	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null:
		push_error("[SceneLoader] Failed to load: %s" % path)
		await _fade(0.0, FADE_IN_SECONDS)
		_is_transitioning = false
		return

	# Mouse capture is a per-scene concern; releasing it here stops a captured
	# cursor leaking into menus if the previous scene was mid-gameplay.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var error: Error = get_tree().change_scene_to_packed(packed)
	if error != OK:
		push_error("[SceneLoader] Scene change failed: %s (error %d)" % [path, error])
		await _fade(0.0, FADE_IN_SECONDS)
		_is_transitioning = false
		return

	# Let the new scene finish _ready() before revealing it.
	await get_tree().process_frame
	await _fade(0.0, FADE_IN_SECONDS)

	_is_transitioning = false
	EventBus.scene_transition_finished.emit(path)


func is_transitioning() -> bool:
	return _is_transitioning


## Returns the spawn point requested by the caller that loaded this scene, and
## clears it so it cannot be read twice.
func consume_spawn_point() -> StringName:
	var spawn_point: StringName = _pending_spawn_point
	_pending_spawn_point = &""
	return spawn_point


# ── Internals ────────────────────────────────────────────────────

func _build_curtain() -> void:
	_curtain_layer = CanvasLayer.new()
	_curtain_layer.name = "TransitionCurtain"
	_curtain_layer.layer = CURTAIN_LAYER
	add_child(_curtain_layer)

	_curtain = ColorRect.new()
	_curtain.name = "Fade"
	_curtain.color = Color(0.02, 0.02, 0.04, 0.0)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curtain.visible = false
	_curtain_layer.add_child(_curtain)


func _fade(target_alpha: float, duration: float) -> void:
	_curtain.visible = true

	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_curtain, "color:a", target_alpha, duration)
	await tween.finished

	# Hiding a fully transparent curtain keeps it out of the compositing path.
	_curtain.visible = target_alpha > 0.0


## Loading is synchronous by design. The fade curtain is fully opaque before the
## load begins, so a threaded load buys no visible smoothness here — and
## ResourceLoader's threaded path leaves an instance alive at shutdown, which
## would permanently mask genuine leak warnings during development.
##
## Revisit in Phase 5 if the cemetery's load time grows enough to justify a
## progress-bar loading screen, which is the only thing threaded loading enables.
