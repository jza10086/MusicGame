extends RefCounted
## Copyable least-played pool. One instance owns one match's accepted draw history.
## The entry owns authority/transport; only open_file() opts into local persistence.
const MAX_COUNT: int = 9007199254740991
var _ids: Array[String] = []
var _counts: Dictionary[String, int] = {}
var _history: Array[String] = []
var _path: String = ""

func _init(content_ids: Array[String]) -> void:
	assert(not content_ids.is_empty(), "A random pool needs at least one content ID.")
	for id: String in content_ids:
		assert(not id.is_empty() and not _counts.has(id), "Content IDs must be unique and nonempty.")
		_ids.append(id)
		_counts[id] = 0

func counts() -> Dictionary[String, int]:
	return _counts.duplicate()

## Include the complete sequence in snapshots. Counts stay private to each device.
func history() -> Array[String]:
	return _history.duplicate()

## Host only: choose without recording; append to history and accept before publishing.
func choose(rng: RandomNumberGenerator) -> String:
	var minimum: int = _counts[_ids[0]]
	var candidates: Array[String] = []
	for id: String in _ids:
		minimum = mini(minimum, _counts[id])
	for id: String in _ids:
		if _counts[id] == minimum:
			candidates.append(id)
	return candidates[rng.randi_range(0, candidates.size() - 1)]

## Call once before play with an absolute file path from the injected storage root.
## Missing files start at zero; corrupt data fails instead of resetting history.
func open_file(path: String) -> Error:
	assert(_path.is_empty() and _history.is_empty(), "Open storage before accepting any draws.")
	assert(path.is_absolute_path(), "The entry must resolve the portable storage root.")
	if not FileAccess.file_exists(path):
		_path = path
		return OK
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var source: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		return read_error
	var json: JSON = JSON.new()
	var error: Error = json.parse(source)
	if error != OK:
		return error
	var data: Variant = json.data
	if not data is Dictionary or data.get("version") != 1 or not data.get("plays") is Dictionary:
		return ERR_INVALID_DATA
	if data.plays.size() != _ids.size():
		return ERR_INVALID_DATA
	var loaded: Dictionary[String, int] = {}
	for id: String in _ids:
		var value: Variant = data.plays.get(id)
		if (not value is int and not value is float) or not is_finite(float(value)):
			return ERR_INVALID_DATA
		if value < 0 or value > MAX_COUNT or float(value) != floorf(float(value)):
			return ERR_INVALID_DATA
		loaded[id] = int(value)
	_counts = loaded
	_path = path
	return OK

## Validate host history, ignore duplicate/older matching snapshots and record only
## the unseen suffix. Conflicting prefixes fail. A failed save never advances memory.
## Create a fresh instance for each match; deduplication is scoped to that match.
func accept_history(sequence: Array) -> Error:
	for index: int in sequence.size():
		var id: Variant = sequence[index]
		if not id is String or not _counts.has(id):
			return ERR_INVALID_DATA
		if index < _history.size() and id != _history[index]:
			return ERR_INVALID_DATA
	if sequence.size() <= _history.size():
		return OK
	var next: Dictionary[String, int] = _counts.duplicate()
	for index: int in range(_history.size(), sequence.size()):
		var id: String = sequence[index]
		if next[id] == MAX_COUNT:
			return ERR_INVALID_DATA
		next[id] += 1
	if not _path.is_empty():
		var error: Error = _save(next)
		if error != OK:
			return error
	_counts = next
	_history.assign(sequence)
	return OK

func _save(next: Dictionary[String, int]) -> Error:
	var error: Error = DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	if error != OK:
		return error
	var pending: String = _path + ".pending"
	var file: FileAccess = FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": 1, "plays": next}, "\t") + "\n")
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(pending, _path)

