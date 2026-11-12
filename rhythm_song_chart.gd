## One Inspector-editable difficulty in a song. Note data stays in the authoring JSON.
class_name RhythmSongChart
extends Resource

const DEFAULT_BASE_SCORE: int = 1000000

@export var difficulty: String = "Normal"
@export_file("*.json") var chart_path: String = ""
## Full-accuracy score for this difficulty; independent of the difficulty's display name.
@export_range(1, 1000000000, 1) var base_score: int = DEFAULT_BASE_SCORE
