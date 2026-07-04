extends Node

func _ready() -> void:
	print("[AudioManager] Initializing...")

func play_sfx(sfx_name: String) -> void:
	print("[AudioManager] Playing SFX: ", sfx_name)

func play_music(music_name: String) -> void:
	print("[AudioManager] Playing Music: ", music_name)
