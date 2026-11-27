extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		push_error("missing .pck path")
		quit(1)
		return
	var source_pack: String = args[0]
	var ok: bool = ProjectSettings.load_resource_pack(source_pack, true)
	print("PCK_LOADED=", ok)
	if not ok:
		quit(1)
		return
	var hits: Array = []
	_walk("res://", hits)
	print("PCK_FILES=", hits.size())
	print("PCK_FIRST_FILES=", hits.slice(0, 30))
	print("PCK_DATA_FILE_EXISTS=", FileAccess.file_exists("res://data/ch1.json"))
	print("PCK_AUDIO_FILE_EXISTS=", FileAccess.file_exists("res://data/audio.json"))
	if FileAccess.file_exists("res://data/ch1.json"):
		var source: String = FileAccess.get_file_as_string("res://data/ch1.json")
		print("PCK_DATA_LEN=", source.length())
		var data = JSON.parse_string(source)
		if data is Dictionary:
			print("PCK_GAME_ACTS=", (data.get("acts", {}) as Dictionary).size())
	var packer := PCKPacker.new()
	var destination: String = source_pack.get_base_dir().path_join("probe.pck")
	var state := packer.pck_start(destination)
	print("PACKER_START=", state)
	if state == OK:
		var r := packer.add_file("res://data/ch1.json", "res://data/ch1.json")
		print("PACKER_ADD=", r)
		print("PACKER_FLUSH=", packer.flush())
		print("PACKER_PROBE_BYTES=", FileAccess.get_file_as_bytes(destination).size())
	quit()

func _walk(path: String, files: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry == "":
			break
		if entry == "." or entry == "..":
			continue
		var p := path.path_join(entry)
		if dir.current_is_dir():
			_walk(p, files)
		else:
			files.append(p)
	dir.list_dir_end()
