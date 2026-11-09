## A playable song binds one music stream to its difficulty/chart list.
class_name RhythmSong
extends Resource

const Chart = preload("rhythm_chart.gd")

@export var music: AudioStream
@export var charts: Array[RhythmSongChart] = []

## Validate the Inspector configuration, then load the requested chart against this song's music.
## Resource difficulty is authoritative for playback; the source JSON is never changed.
func read_chart(difficulty: String) -> Dictionary:
	if music == null:
		return {"ok": false, "error": "曲目未绑定音乐"}
	if charts.is_empty():
		return {"ok": false, "error": "曲目没有难度谱面"}
	var selected: RhythmSongChart
	var names: Array[String] = []
	for entry: RhythmSongChart in charts:
		if entry == null or entry.difficulty.strip_edges().is_empty() or entry.chart_path.is_empty():
			return {"ok": false, "error": "曲目存在未填写的难度或谱面"}
		if names.has(entry.difficulty):
			return {"ok": false, "error": "曲目难度重复：" + entry.difficulty}
		names.append(entry.difficulty)
		if entry.difficulty == difficulty:
			selected = entry
	if selected == null:
		return {"ok": false, "error": "曲目不包含难度：" + difficulty}
	var chart: Dictionary = Chart.read_chart(selected.chart_path, music)
	if chart.ok:
		chart.data.difficulty = selected.difficulty
		if not resource_name.is_empty():
			chart.data.title = resource_name
	return chart
