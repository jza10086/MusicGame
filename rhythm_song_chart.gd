## One Inspector-editable difficulty in a song. Note data stays in the authoring JSON.
class_name RhythmSongChart
extends Resource

@export var difficulty: String = "Normal"
@export_file("*.json") var chart_path: String = ""
