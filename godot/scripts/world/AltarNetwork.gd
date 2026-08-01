class_name AltarNetwork
extends Node
## Counts the Funeral Altars and fires the demo's central gate.
##
## Individual altars know nothing about each other; this watches them all and
## announces progress. Keeping the count here rather than in each altar means the
## level can hold any number of them and the quest system only has to listen to
## one signal.

signal all_cleansed

var _altars: Array[FuneralAltar] = []
var _cleansed_count: int = 0


func _ready() -> void:
	# Deferred so every altar in the level has finished _ready and joined its
	# group before the roll call.
	call_deferred("_collect_altars")


func get_total() -> int:
	return _altars.size()


func get_cleansed_count() -> int:
	return _cleansed_count


func is_complete() -> bool:
	return _altars.size() > 0 and _cleansed_count >= _altars.size()


func _collect_altars() -> void:
	for node in get_tree().get_nodes_in_group("funeral_altars"):
		var altar := node as FuneralAltar
		if altar == null:
			continue
		_altars.append(altar)
		if altar.is_cleansed():
			_cleansed_count += 1
		else:
			altar.cleansed.connect(_on_altar_cleansed)

	print("[AltarNetwork] Tracking %d altars (%d already cleansed)." % [_altars.size(), _cleansed_count])

	# A save restored with every altar already done still needs the gate opened.
	if is_complete():
		_announce_complete()


func _on_altar_cleansed(altar: FuneralAltar) -> void:
	_cleansed_count += 1
	EventBus.altar_cleansed.emit(altar.altar_id, _cleansed_count, _altars.size())

	if is_complete():
		_announce_complete()


func _announce_complete() -> void:
	EventBus.all_altars_cleansed.emit()
	all_cleansed.emit()
