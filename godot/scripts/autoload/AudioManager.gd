extends Node
## Sound effect playback and audio bus control.
##
## Music is NOT handled here — that belongs to MusicDirector, which owns the
## layered stem system. This script is a dumb service: it plays what it is asked
## to play and never listens to gameplay events.
##
## Audio files do not exist yet (see docs/AUDIO_SPEC.md). Every lookup failure is
## warned about exactly once and then ignored, so the game runs silently and
## without error spam until the real assets land.

const SFX_DIRECTORY: String = "res://assets/audio/sfx"

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_MUSIC_AMBIENT: StringName = &"MusicAmbient"
const BUS_MUSIC_COMBAT: StringName = &"MusicCombat"
const BUS_MUSIC_BOSS: StringName = &"MusicBoss"
const BUS_SFX: StringName = &"SFX"
const BUS_SFX_PLAYER: StringName = &"SFXPlayer"
const BUS_SFX_WORLD: StringName = &"SFXWorld"
const BUS_SFX_UI: StringName = &"SFXUI"

const POOL_SIZE_2D: int = 16
const POOL_SIZE_3D: int = 24

## Sounds with numbered variations, chosen at random per playback to avoid the
## machine-gun effect on repeated hits. Value is the number of files, named
## "<id>_01.ogg" .. "<id>_NN.ogg". Anything not listed resolves to "<id>.ogg".
const VARIATIONS: Dictionary = {
	&"riff_strike_swing": 3,
	&"riff_strike_impact": 3,
	&"riff_hurt": 2,
	&"footstep_stone": 4,
	&"footstep_grass": 4,
	&"tonedeaf_groan": 2,
}

var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _stream_cache: Dictionary = {}
var _missing_reported: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_pools()
	apply_saved_volumes()
	print("[AudioManager] Ready. %d 2D voices, %d 3D voices." % [POOL_SIZE_2D, POOL_SIZE_3D])


## Applies the persisted volume settings. SaveService is ordered before this
## autoload in project.godot so the values are available here.
func apply_saved_volumes() -> void:
	set_bus_volume_linear(BUS_MASTER, float(SaveService.get_setting("audio/master_volume")))
	set_bus_volume_linear(BUS_MUSIC, float(SaveService.get_setting("audio/music_volume")))
	set_bus_volume_linear(BUS_SFX, float(SaveService.get_setting("audio/sfx_volume")))


# ── Playback ─────────────────────────────────────────────────────

## Plays a non-positional sound (UI, player-centric feedback).
func play_sfx(sfx_id: StringName, bus: StringName = BUS_SFX_PLAYER, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _resolve_stream(sfx_id)
	if stream == null:
		return

	var player: AudioStreamPlayer = _acquire_2d()
	if player == null:
		return

	player.stream = stream
	player.bus = bus
	player.volume_db = volume_db
	player.play()


## Plays a sound positioned in the world. Falls back to non-positional playback if
## the 3D pool is exhausted rather than dropping the sound entirely.
func play_sfx_3d(sfx_id: StringName, position: Vector3, bus: StringName = BUS_SFX_WORLD, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _resolve_stream(sfx_id)
	if stream == null:
		return

	var player: AudioStreamPlayer3D = _acquire_3d()
	if player == null:
		play_sfx(sfx_id, bus, volume_db)
		return

	player.stream = stream
	player.bus = bus
	player.volume_db = volume_db
	player.global_position = position
	player.play()


func play_ui(sfx_id: StringName, volume_db: float = 0.0) -> void:
	play_sfx(sfx_id, BUS_SFX_UI, volume_db)


func stop_all() -> void:
	for player in _players_2d:
		player.stop()
	for player_3d in _players_3d:
		player_3d.stop()


# ── Bus volume ───────────────────────────────────────────────────

## Volume as a 0..1 slider value. Uses a perceptual curve rather than a raw dB
## mapping so the middle of a settings slider sounds like "half as loud".
func set_bus_volume_linear(bus: StringName, value: float) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0:
		push_warning("[AudioManager] Unknown audio bus: %s" % bus)
		return

	var clamped: float = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_mute(index, is_zero_approx(clamped))
	AudioServer.set_bus_volume_db(index, linear_to_db(clamped))


func get_bus_volume_linear(bus: StringName) -> float:
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0:
		return 0.0
	if AudioServer.is_bus_mute(index):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(index)), 0.0, 1.0)


# ── Internals ────────────────────────────────────────────────────

func _build_pools() -> void:
	for i in range(POOL_SIZE_2D):
		var player := AudioStreamPlayer.new()
		player.name = "Sfx2D_%02d" % i
		player.bus = BUS_SFX_PLAYER
		add_child(player)
		_players_2d.append(player)

	for i in range(POOL_SIZE_3D):
		var player_3d := AudioStreamPlayer3D.new()
		player_3d.name = "Sfx3D_%02d" % i
		player_3d.bus = BUS_SFX_WORLD
		player_3d.max_distance = 40.0
		player_3d.unit_size = 4.0
		add_child(player_3d)
		_players_3d.append(player_3d)


func _acquire_2d() -> AudioStreamPlayer:
	for player in _players_2d:
		if not player.playing:
			return player
	return null


func _acquire_3d() -> AudioStreamPlayer3D:
	for player in _players_3d:
		if not player.playing:
			return player
	return null


func _resolve_stream(sfx_id: StringName) -> AudioStream:
	var path: String = _resolve_path(sfx_id)

	if _stream_cache.has(path):
		return _stream_cache[path] as AudioStream

	if not ResourceLoader.exists(path):
		_report_missing(sfx_id, path)
		return null

	var stream := ResourceLoader.load(path) as AudioStream
	if stream == null:
		_report_missing(sfx_id, path)
		return null

	_stream_cache[path] = stream
	return stream


func _resolve_path(sfx_id: StringName) -> String:
	if VARIATIONS.has(sfx_id):
		var count: int = int(VARIATIONS[sfx_id])
		var pick: int = randi_range(1, maxi(1, count))
		return "%s/%s_%02d.ogg" % [SFX_DIRECTORY, sfx_id, pick]
	return "%s/%s.ogg" % [SFX_DIRECTORY, sfx_id]


## Warns once per sound id. Repeated misses are expected while audio is still being
## produced, and would otherwise flood the output every frame of combat.
func _report_missing(sfx_id: StringName, path: String) -> void:
	if _missing_reported.has(sfx_id):
		return

	_missing_reported[sfx_id] = true
	print("[AudioManager] Sound not yet available: %s (expected %s)" % [sfx_id, path])
