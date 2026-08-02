extends Node
## Layered music. The demo's second voice: what the player has achieved should be
## audible before it is visible.
##
## The four combat stems are one arrangement bounced into parts (see
## docs/AUDIO_SPEC.md). They are started together and never stopped or restarted
## individually — that is what keeps them sample-locked. Layers are revealed by
## fading volume, and reveals are quantised to the next bar so an instrument never
## enters off-beat.
##
## Works two ways, because music arrives two ways.
##
## Given the four authored stems it layers them: started together, never stopped
## or restarted individually, revealed by volume on bar boundaries. Given a single
## finished arrangement instead — which is how most music is actually written —
## it plays that and expresses the Encore through *intensity*: a low-pass that
## opens and a level that lifts as the meter climbs, so a low Encore sounds
## distant and muffled and a full one is bright and present.
##
## The second mode is not a degraded version of the first. It is what the delivered
## tracks needed, and it keeps the promise that what the player has achieved is
## audible before it is visible.
##
## Purely a consumer: it listens on EventBus and never calls into gameplay.

const MUSIC_DIRECTORY: String = "res://assets/audio/music"

## Must match the stems' authored tempo and length exactly, or bar quantisation
## drifts out of sync with the music.
const BEATS_PER_MINUTE: float = 120.0
const BEATS_PER_BAR: int = 4

const SILENT_DB: float = -80.0

const FADE_IN_SECONDS: float = 1.5
const FADE_OUT_SECONDS: float = 1.2
const CROSSFADE_SECONDS: float = 1.2
const AMBIENT_RETURN_SECONDS: float = 2.5

## Combat is held briefly after the last enemy dies, so a straggler re-engaging
## does not cause the music to lurch back and forth.
const COMBAT_HOLD_SECONDS: float = 4.0

## Stem file names, in layer order. Index matches the Encore tier that reveals it.
const COMBAT_LAYERS: PackedStringArray = [
	"combat_l1_guitar",
	"combat_l2_percussion",
	"combat_l3_trumpet",
	"combat_l4_lead",
]

const BOSS_LAYERS: PackedStringArray = [
	"boss_choirmaster_l1",
	"boss_choirmaster_l2",
]

## Used when no layered stems are present. A complete arrangement, played whole.
const COMBAT_FULL: String = "combat_full"
const BOSS_FULL: String = "boss_choirmaster_full"

## Cutoff and level per Encore tier, for single-track mode.
##
## The filter is doing most of the work: volume alone reads as "quieter", which is
## the wrong idea entirely. A closed filter reads as the music being somewhere
## else, and opening it as the fight arriving.
const INTENSITY_CUTOFF_HZ: PackedFloat32Array = [900.0, 2400.0, 6500.0, 20000.0]
const INTENSITY_DB: PackedFloat32Array = [-7.0, -4.5, -2.0, 0.0]

var _ambient_player: AudioStreamPlayer = null
var _tavern_player: AudioStreamPlayer = null
var _combat_players: Array[AudioStreamPlayer] = []
var _boss_players: Array[AudioStreamPlayer] = []

var _in_combat: bool = false
var _boss_active: bool = false
var _combat_hold_timer: float = 0.0
var _encore_tier: int = 0
var _live_enemies: int = 0

var _missing_reported: Dictionary = {}

## True when the section is served by one finished track rather than by stems.
var _combat_is_single: bool = false
var _boss_is_single: bool = false
var _intensity_filters: Dictionary = {}
var _intensity_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_players()

	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.encore_tier_changed.connect(_on_encore_tier_changed)
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.game_state_changed.connect(_on_game_state_changed)
	EventBus.scene_transition_started.connect(_on_scene_transition)
	EventBus.boss_interlude_started.connect(_on_boss_interlude_started)
	EventBus.boss_interlude_finished.connect(_on_boss_interlude_finished)
	EventBus.boss_defeated.connect(_on_boss_defeated)

	print("[MusicDirector] Ready. Bar length %.3fs." % get_bar_seconds())


func _process(delta: float) -> void:
	if _combat_hold_timer <= 0.0:
		return

	_combat_hold_timer -= delta
	if _combat_hold_timer <= 0.0 and _live_enemies <= 0:
		_leave_combat()


func get_bar_seconds() -> float:
	return float(BEATS_PER_BAR) * 60.0 / BEATS_PER_MINUTE


# ── Public control ───────────────────────────────────────────────

## Starts the exploration bed. Called when a level begins.
func play_exploration() -> void:
	_boss_active = false
	_stop_group(_boss_players)
	_fade_to(_tavern_player, SILENT_DB, FADE_OUT_SECONDS)

	# Stems are started here and left running silently, because starting them later
	# is what breaks their phase lock. A single arrangement has nothing to stay
	# locked to, and starting it now would mean combat joins it wherever it happens
	# to have got to — so it waits and begins at its own opening.
	if not _combat_is_single:
		_start_group(_combat_players)
	_apply_combat_layers(false)
	_fade_to(_ambient_player, 0.0, CROSSFADE_SECONDS)


func play_tavern() -> void:
	_in_combat = false
	_boss_active = false
	_stop_group(_combat_players)
	_stop_group(_boss_players)
	_fade_to(_ambient_player, SILENT_DB, FADE_OUT_SECONDS)
	_start_player(_tavern_player)
	_fade_to(_tavern_player, 0.0, CROSSFADE_SECONDS)


## Switches to the boss arrangement. Its layers are driven by phase rather than by
## Encore, since the Choirmaster's fight has its own escalation.
func play_boss(phase: int = 0) -> void:
	_boss_active = true
	_fade_to(_ambient_player, SILENT_DB, FADE_OUT_SECONDS)
	_fade_group(_combat_players, SILENT_DB, FADE_OUT_SECONDS)

	_start_group(_boss_players)

	if _boss_is_single:
		# One arrangement: the phase opens it up rather than adding to it, so the
		# conducted interludes still lift the music.
		_fade_to(_boss_players[0], 0.0, CROSSFADE_SECONDS)
		_apply_intensity(AudioManager.BUS_MUSIC_BOSS, phase + 1)
		return

	for index in range(_boss_players.size()):
		_fade_to(_boss_players[index], 0.0 if index <= phase else SILENT_DB, CROSSFADE_SECONDS)


func stop_all(fade_seconds: float = FADE_OUT_SECONDS) -> void:
	_fade_to(_ambient_player, SILENT_DB, fade_seconds)
	_fade_to(_tavern_player, SILENT_DB, fade_seconds)
	_fade_group(_combat_players, SILENT_DB, fade_seconds)
	_fade_group(_boss_players, SILENT_DB, fade_seconds)


# ── Event handlers ───────────────────────────────────────────────

func _on_enemy_spawned(_enemy: Node3D) -> void:
	_live_enemies += 1


func _on_enemy_died(_enemy: Node3D) -> void:
	_live_enemies = maxi(0, _live_enemies - 1)
	if _live_enemies <= 0 and _in_combat:
		_combat_hold_timer = COMBAT_HOLD_SECONDS


func _on_combat_started() -> void:
	if _in_combat:
		return

	_in_combat = true
	_combat_hold_timer = 0.0
	_fade_to(_ambient_player, SILENT_DB, CROSSFADE_SECONDS)
	# Ensure the stems are running before revealing any of them — combat can begin
	# without play_exploration() having been called, e.g. straight into an ambush.
	_start_group(_combat_players)
	_apply_combat_layers(true)


func _on_combat_ended() -> void:
	_combat_hold_timer = COMBAT_HOLD_SECONDS


func _on_encore_tier_changed(tier: int) -> void:
	_encore_tier = tier
	if _in_combat and not _boss_active:
		_reveal_layers_on_next_bar()


## The conducted interludes are the fight's escalation, so they are the music's
## too. Each one opens the arrangement further and it stays there — the fight only
## ever gets worse.
func _on_boss_interlude_started(number: int, _total: int) -> void:
	play_boss(number)


func _on_boss_interlude_finished(completed: int, _total: int) -> void:
	play_boss(completed)


func _on_boss_defeated(_boss_id: StringName) -> void:
	_boss_active = false
	_fade_group(_boss_players, SILENT_DB, AMBIENT_RETURN_SECONDS)
	_fade_to(_ambient_player, 0.0, AMBIENT_RETURN_SECONDS)


func _on_game_state_changed(_previous: int, current: int) -> void:
	if current == GameManager.GameState.INN_HUB:
		play_tavern()


func _on_scene_transition(_path: String) -> void:
	stop_all(0.35)


func _leave_combat() -> void:
	_in_combat = false
	_apply_combat_layers(false)
	if not _boss_active:
		_fade_to(_ambient_player, 0.0, AMBIENT_RETURN_SECONDS)


# ── Layering ─────────────────────────────────────────────────────

## Waits for the next bar boundary before revealing layers, so an instrument
## never enters mid-phrase. Uses layer one's playback position as the clock,
## since every stem shares its timeline.
func _reveal_layers_on_next_bar() -> void:
	# Quantisation only makes sense against stems authored at BEATS_PER_MINUTE.
	# A finished track has its own tempo, and holding a change for "the next bar"
	# of a bar length it does not share would land the change at a random point
	# and delay it for no reason.
	if _combat_is_single:
		_apply_combat_layers(true)
		return

	var clock: AudioStreamPlayer = _combat_players[0] if not _combat_players.is_empty() else null
	if clock == null or not clock.playing:
		_apply_combat_layers(true)
		return

	var bar: float = get_bar_seconds()
	var into_bar: float = fmod(clock.get_playback_position(), bar)
	var wait: float = bar - into_bar

	# Already effectively on the boundary — do not stall a whole bar for a few ms.
	if wait < 0.05:
		_apply_combat_layers(true)
		return

	await get_tree().create_timer(wait, true, false, true).timeout

	# Combat may have ended during the wait.
	if _in_combat and not _boss_active:
		_apply_combat_layers(true)


## Layer N is audible when the Encore tier has reached N. Layers are faded, never
## started or stopped, so they stay locked to each other.
##
## With a single arrangement there is nothing to reveal, so the Encore is applied
## to the sound of the track instead.
func _apply_combat_layers(audible: bool) -> void:
	if _combat_is_single:
		var track: AudioStreamPlayer = _combat_players[0] if not _combat_players.is_empty() else null
		if track != null:
			_fade_to(track, 0.0 if audible else SILENT_DB, FADE_IN_SECONDS if audible else FADE_OUT_SECONDS, false)
		_apply_intensity(AudioManager.BUS_MUSIC_COMBAT, _encore_tier if audible else 0)
		return

	for index in range(_combat_players.size()):
		var wanted: bool = audible and index <= _encore_tier
		_fade_to(
			_combat_players[index],
			0.0 if wanted else SILENT_DB,
			FADE_IN_SECONDS if wanted else FADE_OUT_SECONDS,
			false
		)


## Applies an Encore tier to a whole arrangement, as filter and level.
##
## The filter carries the idea. Turning the volume down reads as "quieter", which
## says nothing about how the fight is going; closing a low-pass reads as the music
## being in another room, and opening it as the fight arriving in this one.
func _apply_intensity(bus: StringName, tier: int) -> void:
	var filter: AudioEffectLowPassFilter = _intensity_filter(bus)
	if filter == null:
		return

	var step: int = clampi(tier, 0, INTENSITY_CUTOFF_HZ.size() - 1)

	if _intensity_tween != null and _intensity_tween.is_valid():
		_intensity_tween.kill()
	_intensity_tween = create_tween()
	_intensity_tween.set_parallel(true)
	# Eased, not snapped: a filter jumping open on the frame a tier is crossed is
	# audible as a click rather than as a swell.
	_intensity_tween.tween_property(filter, "cutoff_hz", INTENSITY_CUTOFF_HZ[step], CROSSFADE_SECONDS)

	var index: int = AudioServer.get_bus_index(bus)
	if index >= 0:
		_intensity_tween.tween_method(
			func(db: float) -> void: AudioServer.set_bus_volume_db(index, db),
			AudioServer.get_bus_volume_db(index),
			INTENSITY_DB[step],
			CROSSFADE_SECONDS
		)


## The low-pass on a music bus, added on first use.
##
## Added at runtime rather than saved into the shared bus layout: this filter
## belongs to the director that drives it, and a project-wide layout carrying an
## effect that only one mode uses is the kind of thing that gets "tidied away".
func _intensity_filter(bus: StringName) -> AudioEffectLowPassFilter:
	if _intensity_filters.has(bus):
		return _intensity_filters[bus]

	var index: int = AudioServer.get_bus_index(bus)
	if index < 0:
		push_warning("[MusicDirector] No audio bus named %s." % bus)
		return null

	var filter := AudioEffectLowPassFilter.new()
	filter.cutoff_hz = INTENSITY_CUTOFF_HZ[0]
	AudioServer.add_bus_effect(index, filter)
	_intensity_filters[bus] = filter
	return filter


# ── Playback plumbing ────────────────────────────────────────────

func _build_players() -> void:
	_ambient_player = _make_player("Ambient", "explore_graveyard_ambient", AudioManager.BUS_MUSIC_AMBIENT)
	_tavern_player = _make_player("Tavern", "tavern_ambient", AudioManager.BUS_MUSIC_AMBIENT)

	_combat_is_single = not _any_stem_exists(COMBAT_LAYERS)
	if _combat_is_single:
		_combat_players.append(_make_player("CombatFull", COMBAT_FULL, AudioManager.BUS_MUSIC_COMBAT))
	else:
		for stem: String in COMBAT_LAYERS:
			_combat_players.append(_make_player(stem, stem, AudioManager.BUS_MUSIC_COMBAT))

	_boss_is_single = not _any_stem_exists(BOSS_LAYERS)
	if _boss_is_single:
		_boss_players.append(_make_player("BossFull", BOSS_FULL, AudioManager.BUS_MUSIC_BOSS))
	else:
		for stem: String in BOSS_LAYERS:
			_boss_players.append(_make_player(stem, stem, AudioManager.BUS_MUSIC_BOSS))

	print("[MusicDirector] Combat: %s. Boss: %s." % [
		"one arrangement, Encore drives intensity" if _combat_is_single else "%d layered stems" % _combat_players.size(),
		"one arrangement" if _boss_is_single else "%d layered stems" % _boss_players.size(),
	])


## Whether any of a section's layered stems were delivered. All or nothing: a
## partial set cannot be layered meaningfully, and quietly playing two of four
## would sound like an arrangement with holes in it.
func _any_stem_exists(stems: PackedStringArray) -> bool:
	for stem: String in stems:
		if _find_stem_path(stem) != "":
			return true
	return false


## Players are created whether or not the audio exists yet, so the whole system is
## wired and testable before the stems are delivered. A player with no stream is
## simply silent.
func _make_player(node_name: String, stem: String, bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = bus
	player.volume_db = SILENT_DB
	player.stream = _load_stem(stem)
	add_child(player)
	return player


## Where a track lives, or an empty string. Both formats are accepted: .ogg is
## smaller and preferred, but music arrives as .wav often enough that refusing it
## would mean asking for a re-export before anything could be heard.
func _find_stem_path(stem: String) -> String:
	for extension: String in ["ogg", "wav"]:
		var path: String = "%s/%s.%s" % [MUSIC_DIRECTORY, stem, extension]
		if ResourceLoader.exists(path):
			return path
	return ""


func _load_stem(stem: String) -> AudioStream:
	var path: String = _find_stem_path(stem)
	if path == "":
		if not _missing_reported.has(stem):
			_missing_reported[stem] = true
			print("[MusicDirector] Track not yet available: %s/%s" % [MUSIC_DIRECTORY, stem])
		return null

	var stream := ResourceLoader.load(path) as AudioStream
	# Looping is a property of the file; enforced here so a track exported without
	# a loop flag does not fall silent after one pass and leave a twelve-minute
	# level in silence.
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		var sample := stream as AudioStreamWAV
		if sample.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			sample.loop_mode = AudioStreamWAV.LOOP_FORWARD
			sample.loop_end = 0
	return stream


func _start_group(players: Array[AudioStreamPlayer]) -> void:
	# Started in one pass so every stem shares a start time. Staggering them, or
	# starting one later when its layer unlocks, is what breaks phase lock.
	for player in players:
		_start_player(player)


func _start_player(player: AudioStreamPlayer) -> void:
	if player == null or player.stream == null or player.playing:
		return
	player.volume_db = SILENT_DB
	player.play()


func _stop_group(players: Array[AudioStreamPlayer]) -> void:
	for player in players:
		if player != null:
			player.stop()


func _fade_group(players: Array[AudioStreamPlayer], target_db: float, seconds: float, stop_at_silence: bool = true) -> void:
	for player in players:
		_fade_to(player, target_db, seconds, stop_at_silence)


## stop_at_silence must be FALSE for the layered stems. Stopping a silent combat
## layer and restarting it when its tier unlocks would put it out of phase with
## the others, which is the one thing this system exists to prevent. Silent layers
## keep playing; only the volume moves.
func _fade_to(player: AudioStreamPlayer, target_db: float, seconds: float, stop_at_silence: bool = true) -> void:
	if player == null:
		return

	if player.has_meta("fade_tween"):
		var running := player.get_meta("fade_tween") as Tween
		if running != null and running.is_valid():
			running.kill()

	if player.stream == null:
		player.volume_db = target_db
		return

	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(player, "volume_db", target_db, seconds)
	if stop_at_silence and target_db <= SILENT_DB:
		tween.tween_callback(player.stop)
	player.set_meta("fade_tween", tween)
