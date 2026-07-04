extends Control

func _ready() -> void:
	print("[Boot] Booting up Riff Wilde and the Sold-Out Saga...")
	await get_tree().create_timer(1.5).timeout
	print("[Boot] Boot sequence complete. Transitioning to Tavern Hub...")
	
	SceneLoader.load_scene("res://scenes/levels/TavernHub.tscn")
