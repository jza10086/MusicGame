## Resolve package-local data from an existing root script, independent of folder name.
## Static preloads/scenes remain relative; use this only for runtime file discovery/loading.
extends RefCounted
const ROOT_SCRIPT: Script = preload("rhythm_timing.gd")

static func root_directory() -> String:
	return ROOT_SCRIPT.resource_path.get_base_dir()

static func resolve(relative_path: String) -> String:
	return relative_path if relative_path.is_absolute_path() else root_directory().path_join(relative_path).simplify_path()
