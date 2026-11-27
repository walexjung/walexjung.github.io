extends SceneTree
## Repackage the publicly deployed, already-approved MN-B44 full-test PCK
## into an honest 1-1/1-2-only preview. No private repo credentials required.
## Usage: godot --headless --script this.gd -- <full-test.pck> <filtered-ch1.json> <filtered-en.json> <output.pck>

const BG_ALLOW = ["BG-1-1-01", "BG-1-1-02", "BG-1-2-01", "BG-1-2-02", "BG-1-2-03"]
const CHR_ALLOW = ["CHR-01", "CHR-03", "CHR-04", "CHR-08", "CHR-09", "CHR-10", "CHR-11", "CHR-12", "CHR-13", "CHR-40"]
const ITEM_ALLOW = ["INV-01", "INV-02", "INV-03", "INV-04"]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		push_error("expected full.pck, filtered-ch1.json, filtered-en.json, output.pck")
		quit(1)
		return
	var in_pack: String = args[0]
	var demo_data: String = args[1]
	var demo_en: String = args[2]
	var output: String = args[3]
	var a = JSON.parse_string(FileAccess.get_file_as_string(demo_data))
	var e = JSON.parse_string(FileAccess.get_file_as_string(demo_en))
	if not (a is Dictionary) or not (e is Dictionary):
		push_error("invalid public demo JSON")
		quit(2)
		return
	if (a["acts"] as Dictionary).size() != 2 or not a["acts"].has("1-1") or not a["acts"].has("1-2"):
		push_error("public demo must contain exactly acts 1-1, 1-2")
		quit(3)
		return
	if (a["rooms"] as Dictionary).size() != 5 or (a["nodes"] as Dictionary).size() != 78:
		push_error("public demo room/dialogue count mismatch")
		quit(4)
		return
	for forbidden in ["1-3", "2-1", "3-1", "4-1", "5-1", "敵1", "☾1", "終"]:
		if a["acts"].has(forbidden):
			push_error("later act unexpectedly included: " + forbidden)
			quit(5)
			return
	if not ProjectSettings.load_resource_pack(in_pack, true):
		push_error("could not mount source full-test pack")
		quit(6)
		return

	var all_files: Array = []
	for dir_path in ["res://assets", "res://data", "res://scripts", "res://scenes", "res://shaders", "res://fonts", "res://.godot"]:
		_walk(dir_path, all_files)
	for base_name in ["res://project.binary", "res://project.godot", "res://icon.svg", "res://icon.svg.import"]:
		if FileAccess.file_exists(base_name):
			all_files.append(base_name)

	var selected: Dictionary = {}
	var imports: Dictionary = {}
	for f in all_files:
		var path: String = str(f)
		if not _want(path):
			continue
		if path == "res://data/ch1.json" or path == "res://data/i18n/en.json":
			continue
		selected[path] = path
		if path.ends_with(".import"):
			# Each import descriptor points to one or more actual binary
			# resource files in .godot/imported; include ONLY those links.
			var body: String = FileAccess.get_file_as_string(path)
			for line in body.split("\n"):
				var idx := line.find("res://.godot/imported/")
				while idx >= 0:
					var tail: String = line.substr(idx)
					var stop: int = tail.find('"')
					if stop < 0:
						break
					var imported := tail.substr(0, stop)
					if not FileAccess.file_exists(imported):
						push_error("Missing imported resource: " + imported + " for " + path)
						quit(7)
						return
					imports[imported] = imported
					var next := line.find("res://.godot/imported/", idx + stop + 1)
					idx = next

	for f in imports:
		selected[f] = f
	# Ensure all vital runtime and scene resources are retained.
	for required in ["res://project.binary", "res://scripts/main.gdc", "res://scripts/game_state.gdc",
			"res://assets/video/opening.ogv", "res://assets/video/opening_en.ogv", "res://data/audio.json"]:
		if not selected.has(required):
			push_error("required packaged runtime resource absent: " + required)
			quit(8)
			return

	var packer := PCKPacker.new()
	var code := packer.pck_start(output)
	if code != OK:
		push_error("PCK start failed: " + str(code))
		quit(9)
		return
	var total := 0
	for file_path in selected:
		code = packer.add_file(str(file_path), str(selected[file_path]))
		if code != OK:
			push_error("PCK add failed: " + str(file_path) + " status " + str(code))
			quit(10)
			return
		total += 1
	for dest in ["res://data/ch1.json", "res://data/i18n/en.json"]:
		var source_file: String = demo_data if dest.ends_with("ch1.json") else demo_en
		code = packer.add_file(dest, source_file)
		if code != OK:
			push_error("PCK demo override failed: " + dest + " status " + str(code))
			quit(11)
			return
	code = packer.flush()
	if code != OK:
		push_error("PCK flush failed: " + str(code))
		quit(12)
		return
	var handle := FileAccess.open(output, FileAccess.READ)
	if handle == null:
		push_error("repacked file missing")
		quit(13)
		return
	var size := handle.get_length()
	handle.close()
	print("DEMO_REPACK_OK files=", total + 2,
			" imported=", imports.size(),
			" acts=2 rooms=5 nodes=78 translations=", e.size(),
			" pck_bytes=", size)
	if total + 2 < 300 or size > 66000000 or size < 45000000:
		push_error("suspiciously sized demo pack")
		quit(14)
		return
	quit(0)

func _want(path: String) -> bool:
	if path.begins_with("res://assets/backgrounds/"):
		var x := path.trim_prefix("res://assets/backgrounds/").get_slice("/", 0)
		return x in BG_ALLOW
	if path.begins_with("res://assets/characters/"):
		var x := path.trim_prefix("res://assets/characters/")
		var char_id := x.substr(0, 6)
		return char_id in CHR_ALLOW and not (char_id == "CHR-01" and "_armor" in x)
	if path.begins_with("res://assets/objects/"):
		return path.begins_with("res://assets/objects/OBJ-1-1-") or path.begins_with("res://assets/objects/OBJ-1-2-")
	if path.begins_with("res://assets/icons/"):
		var x := path.trim_prefix("res://assets/icons/").substr(0, 6)
		return x in ITEM_ALLOW
	if path.begins_with("res://assets/cuts/"):
		return false
	if path.begins_with("res://assets/"):
		return path.begins_with("res://assets/audio/") or \
				path.begins_with("res://assets/video/") or \
				path.begins_with("res://assets/ui/")
	if path.begins_with("res://data/"):
		return path in ["res://data/audio.json", "res://data/ch1.json", "res://data/i18n/en.json"]
	if path.begins_with("res://.godot/imported/"):
		return false  # Selected by reference from the kept *.import descriptors.
	if path.begins_with("res://.godot/"):
		return true
	if path.begins_with("res://scripts/") or path.begins_with("res://scenes/"):
		return true
	if path.begins_with("res://shaders/") or path.begins_with("res://fonts/"):
		return true
	return path in ["res://project.binary", "res://project.godot", "res://icon.svg", "res://icon.svg.import"]

func _walk(dir_path: String, files: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry == "":
			break
		if entry == "." or entry == "..":
			continue
		var path := dir_path.path_join(entry)
		if dir.current_is_dir():
			_walk(path, files)
		else:
			files.append(path)
	dir.list_dir_end()
