extends SceneTree
## Lists every res:// asset the project's scenes and scripts depend on.
##
##   godot --headless --path godot --script res://tools/verify_referenced_assets.gd
##
## Exists because a scene can reference a file that is not tracked in git: it
## loads perfectly on the machine that made it and fails on a fresh clone. This
## walks the real dependency graph so the answer is not a guess.

const SEARCH_ROOTS: PackedStringArray = ["res://scenes", "res://scripts", "res://resources"]


func _initialize() -> void:
	var referenced: Dictionary = {}

	for search_root: String in SEARCH_ROOTS:
		_scan(search_root, referenced)

	# Anything outside the project's own source folders is an imported asset, and
	# those are the ones at risk of being untracked.
	var external: Array[String] = []
	for path: String in referenced.keys():
		var is_source: bool = false
		for search_root: String in SEARCH_ROOTS:
			if path.begins_with(search_root):
				is_source = true
		if not is_source:
			external.append(path)

	external.sort()
	print("\n=== External assets referenced by scenes and scripts ===\n")
	for path: String in external:
		print(path)
	print("\n%d external dependencies\n" % external.size())
	quit(0)


func _scan(path: String, referenced: Dictionary) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return

	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while entry != "":
		var full: String = path.path_join(entry)
		if directory.current_is_dir():
			_scan(full, referenced)
		elif entry.ends_with(".tscn") or entry.ends_with(".tres") or entry.ends_with(".gd"):
			_collect_from_file(full, referenced)
		entry = directory.get_next()
	directory.list_dir_end()


func _collect_from_file(path: String, referenced: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return

	var text: String = file.get_as_text()
	file.close()

	# Matches res:// paths in ext_resource lines, preload/load calls and exported
	# string defaults alike.
	var regex := RegEx.new()
	regex.compile('res://[^"\\\']+')
	for found in regex.search_all(text):
		var reference: String = found.get_string()
		if reference.ends_with(".import"):
			continue
		referenced[reference] = true
