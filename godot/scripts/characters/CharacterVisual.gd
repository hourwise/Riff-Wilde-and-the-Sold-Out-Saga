class_name CharacterVisual
extends Node3D
## The seam between gameplay and how a character looks.
##
## Gameplay calls play_locomotion/play_attack/play_hit/play_death and never touches
## a mesh, skeleton or animation name. Swapping a placeholder for a final rigged
## model is then a scene edit plus the animation names below — no gameplay script
## changes.
##
## Works in two modes:
##   - Animated: an AnimationPlayer is found and the mapped clips are played.
##   - Procedural: no AnimationPlayer, so motion is faked with squash, tilt and
##     scale on the mesh. Riff currently runs in this mode because no owned asset
##     provides attack, dodge, hit or death animations for a humanoid rig.
##
## Both modes honour the same API, so combat code is identical either way.

## Optional. Leave empty to search this subtree for an AnimationPlayer.
@export var animation_player_path: NodePath

## Yaw correction for the model, in degrees. Godot's forward is -Z, but packs are
## authored facing either way and it varies between vendors — assume nothing and
## check each model.
##
## This is a named property rather than a rotation baked into the model's
## transform because a transform matrix hides the intent: the correction reads as
## an accident and gets "tidied away", which is exactly how this went wrong twice.
@export_range(-180.0, 180.0, 90.0) var model_yaw_degrees: float = 0.0

## Scenes whose animations are merged onto this character at load.
##
## Some packs ship the mesh and its animations as separate files that share one
## rig — better for consistency, since every character draws from the same motion
## set, but it has to be assembled here. Clips are copied in and their track paths
## rewritten to point at this character's skeleton.
@export var animation_libraries: Array[PackedScene] = []

@export_group("Animation names")
@export var idle_animation: StringName = &"Idle"
@export var run_animation: StringName = &"Running"
@export var attack_animations: Array[StringName] = []
@export var hit_animation: StringName = &""
@export var death_animation: StringName = &""
@export var dodge_animation: StringName = &""

@export_group("Tuning")
## Normalised speed above which locomotion switches from idle to run.
@export var run_threshold: float = 0.12
@export var blend_seconds: float = 0.14
## Playback rate of the run clip at FULL speed. Below full speed the rate scales
## down in proportion, so stride rate tracks ground speed.
##
## Tuned per character against its clip: a clip authored as a sprint played over a
## shambling walk reads as running on the spot, however correct the movement is.
@export var run_speed_scale: float = 1.35
## Floor for the scaled playback rate, so a barely-moving character still animates
## rather than freezing mid-stride.
@export var min_run_speed_scale: float = 0.25

@export_group("Procedural fallback")
@export var procedural_mesh_path: NodePath
@export var attack_squash: Vector3 = Vector3(1.15, 0.88, 1.15)
@export var hit_squash: Vector3 = Vector3(1.22, 0.8, 1.22)
@export var dodge_tilt_degrees: float = 22.0

var _animation_player: AnimationPlayer = null
var _mesh: Node3D = null
var _mesh_rest_scale: Vector3 = Vector3.ONE
var _procedural_tween: Tween = null
var _locked: bool = false
## Clip currently playing as a one-shot (attack, hit, dodge). Locomotion must not
## override it, or the clip is replaced on the very next frame and never seen.
var _one_shot_clip: StringName = &""


func _ready() -> void:
	_apply_model_yaw()
	_animation_player = _resolve_animation_player()
	_merge_animation_libraries()
	_mesh = _resolve_procedural_mesh()
	if _mesh != null:
		_mesh_rest_scale = _mesh.scale

	if _animation_player != null:
		_animation_player.animation_finished.connect(_on_animation_finished)


## Copies clips from the configured library scenes onto the character.
##
## No track remapping is needed for packs whose libraries and characters share a
## rig layout: the tracks address nodes relative to the model root, so an
## AnimationPlayer parented there resolves them as-is. Verified with
## tools/inspect_kaykit_rig.gd before relying on it.
func _merge_animation_libraries() -> void:
	if animation_libraries.is_empty():
		return

	var model: Node3D = _resolve_model_root()
	if model == null:
		push_warning("[CharacterVisual] No model to merge animations onto.")
		return

	# Characters in these packs ship with no AnimationPlayer at all, since the
	# motion lives in the shared libraries.
	if _animation_player == null:
		_animation_player = AnimationPlayer.new()
		_animation_player.name = "AnimationPlayer"
		model.add_child(_animation_player)

	# Reuse the default library when the model already ships one. Adding a second
	# library under the same name fails silently and leaves every merged clip
	# missing, which looks identical to having configured the wrong names.
	# Asked before fetching: get_animation_library on a name that is not there
	# returns null but also logs an engine error, and every enemy spawn printed one.
	var is_new_library: bool = not _animation_player.has_animation_library("")
	var merged: AnimationLibrary = (
		AnimationLibrary.new() if is_new_library else _animation_player.get_animation_library("")
	)

	var clashes: int = 0

	for scene: PackedScene in animation_libraries:
		if scene == null:
			continue

		var source: Node = scene.instantiate()
		var source_player: AnimationPlayer = _find_animation_player(source)
		if source_player != null:
			for clip: String in source_player.get_animation_list():
				if merged.has_animation(clip):
					# T-Pose and the like appear in several libraries.
					clashes += 1
					continue
				merged.add_animation(clip, source_player.get_animation(clip).duplicate())
		source.free()

	if is_new_library:
		_animation_player.add_animation_library("", merged)
	_apply_loop_modes()


## Locomotion clips are authored as single cycles; without looping they play once
## and the character freezes mid-stride.
func _apply_loop_modes() -> void:
	for clip: StringName in [idle_animation, run_animation]:
		if not _has_clip(clip):
			continue
		var animation: Animation = _animation_player.get_animation(String(clip))
		if animation != null:
			animation.loop_mode = Animation.LOOP_LINEAR


## The instantiated model beneath this node.
func _resolve_model_root() -> Node3D:
	for child in get_children():
		var model := child as Node3D
		if model != null:
			return model
	return null


## Turns the model itself, leaving this node's own rotation free for the facing
## code that drives it every frame.
func _apply_model_yaw() -> void:
	if is_zero_approx(model_yaw_degrees):
		return

	for child in get_children():
		var model := child as Node3D
		if model != null:
			model.rotate_y(deg_to_rad(model_yaw_degrees))


func has_animations() -> bool:
	return _animation_player != null


## True when the model animates its own attacks. Callers use this to stand down
## any procedural stand-in, so a swing is not driven twice.
func has_attack_animations() -> bool:
	for clip: StringName in attack_animations:
		if _has_clip(clip):
			return true
	return false


## Configured clip names that the model does not actually contain.
##
## A misspelled or renamed clip fails silently — playback is simply skipped and
## the character stands still — so this exists to make that visible to tests and
## to anyone swapping in a new model.
func get_missing_clips() -> Array[StringName]:
	var missing: Array[StringName] = []
	if _animation_player == null:
		return missing

	var configured: Array[StringName] = [idle_animation, run_animation, hit_animation, death_animation, dodge_animation]
	configured.append_array(attack_animations)

	for clip: StringName in configured:
		if clip != &"" and not _animation_player.has_animation(String(clip)):
			missing.append(clip)

	return missing


## speed_ratio is current speed divided by maximum speed, 0..1.
func play_locomotion(speed_ratio: float) -> void:
	# Death and one-shot reactions own the visual until they finish. Without this
	# guard, locomotion runs every frame and replaces an attack or hit clip
	# immediately after it starts, so the swing is never actually seen.
	if _locked or _one_shot_clip != &"":
		return

	if _animation_player == null:
		return

	var moving: bool = speed_ratio > run_threshold
	var clip: StringName = run_animation if moving else idle_animation
	if not _has_clip(clip):
		return

	if _animation_player.current_animation != String(clip):
		_animation_player.play(String(clip), blend_seconds)

	# Proportional, not interpolated from 1.0. Lerping toward run_speed_scale meant
	# that for any character whose clip needs slowing down, moving slower made the
	# animation play FASTER — the opposite of what stride matching requires.
	if moving:
		_animation_player.speed_scale = maxf(
			min_run_speed_scale, clampf(speed_ratio, 0.0, 1.0) * run_speed_scale
		)
	else:
		_animation_player.speed_scale = 1.0


## step_index selects the matching clip from attack_animations, wrapping if the
## chain is longer than the available animations.
func play_attack(step_index: int) -> void:
	if _animation_player != null and not attack_animations.is_empty():
		var clip: StringName = attack_animations[step_index % attack_animations.size()]
		if _play_one_shot(clip):
			return

	_procedural_pulse(attack_squash, 0.06, 0.16)


func play_hit() -> void:
	if _play_one_shot(hit_animation):
		return
	_procedural_pulse(hit_squash, 0.05, 0.13)


func play_dodge(duration: float) -> void:
	if _play_one_shot(dodge_animation):
		return
	_procedural_tilt(duration)


## Locks the visual so locomotion cannot override the death pose.
func play_death() -> void:
	_locked = true

	if _play_one_shot(death_animation):
		return

	if _mesh == null:
		return
	_kill_procedural_tween()
	_procedural_tween = create_tween()
	_procedural_tween.set_parallel(true)
	_procedural_tween.tween_property(_mesh, "rotation:x", deg_to_rad(90.0), 0.35)
	_procedural_tween.tween_property(_mesh, "scale", _mesh_rest_scale * Vector3(1.1, 0.9, 1.1), 0.35)


## Returns a character to its neutral state, e.g. on respawn.
func reset() -> void:
	_locked = false
	_one_shot_clip = &""
	_kill_procedural_tween()

	if _mesh != null:
		_mesh.scale = _mesh_rest_scale
		_mesh.rotation.x = 0.0
		_mesh.rotation.z = 0.0

	if _animation_player != null and _has_clip(idle_animation):
		_animation_player.play(String(idle_animation), blend_seconds)


# ── Internals ────────────────────────────────────────────────────

## Plays a clip that owns the character until it finishes. A newer one-shot
## replaces an older one, so a combo chain flows rather than blocking itself.
func _play_one_shot(clip: StringName) -> bool:
	if _animation_player == null or clip == &"" or not _has_clip(clip):
		return false

	_one_shot_clip = clip
	_animation_player.speed_scale = 1.0
	_animation_player.play(String(clip), blend_seconds)
	return true


func _on_animation_finished(finished: StringName) -> void:
	if finished == _one_shot_clip:
		_one_shot_clip = &""


func _has_clip(clip: StringName) -> bool:
	return clip != &"" and _animation_player != null and _animation_player.has_animation(String(clip))


func _procedural_pulse(squash: Vector3, out_seconds: float, back_seconds: float) -> void:
	if _mesh == null or _locked:
		return

	_kill_procedural_tween()
	_mesh.scale = _mesh_rest_scale
	_procedural_tween = create_tween()
	_procedural_tween.tween_property(_mesh, "scale", _mesh_rest_scale * squash, out_seconds)
	_procedural_tween.tween_property(_mesh, "scale", _mesh_rest_scale, back_seconds)


func _procedural_tilt(duration: float) -> void:
	if _mesh == null or _locked:
		return

	_kill_procedural_tween()
	_procedural_tween = create_tween()
	_procedural_tween.tween_property(_mesh, "rotation:z", deg_to_rad(dodge_tilt_degrees), duration * 0.35)
	_procedural_tween.tween_property(_mesh, "rotation:z", 0.0, duration * 0.65)


func _kill_procedural_tween() -> void:
	if _procedural_tween != null and _procedural_tween.is_valid():
		_procedural_tween.kill()
	_procedural_tween = null


func _resolve_animation_player() -> AnimationPlayer:
	if not animation_player_path.is_empty():
		return get_node_or_null(animation_player_path) as AnimationPlayer
	return _find_animation_player(self)


func _find_animation_player(node: Node) -> AnimationPlayer:
	for child in node.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null


## The node driven by the procedural fallback. Defaults to this node's parent mesh
## so an existing placeholder capsule works with no configuration.
func _resolve_procedural_mesh() -> Node3D:
	if not procedural_mesh_path.is_empty():
		return get_node_or_null(procedural_mesh_path) as Node3D
	return get_parent() as Node3D
