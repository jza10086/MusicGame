## Standard original-protocol round. Each participant judges against their own audio clock.
extends "music_game.gd"

const REPORT_INTERVAL: float = 0.4
const FINISH_GRACE_SECONDS: float = 20.0
var api: PartyAPI
var request_id: String
var local_player: String
var players: Array[Dictionary]
var reports: Dictionary = {}
var rows: Dictionary[String, HBoxContainer] = {}
var running: bool = false
var publish_in: float = 0.0
var song_length: float
var combo_limit: int
var deadline_ms: int
@onready var board: VBoxContainer = $HUD/Leaderboard/Panel/Rows

func party_setup(value: PartyAPI, config: Dictionary) -> void:
	api = value
	request_id = config.request_id
	players = api.get_players()
	for player: Dictionary in players:
		var id: String = player.player_id
		if player.is_local:
			local_player = id
		reports[id] = {"accuracy": 10000, "combo": 0, "status": "playing"}
	api.net.message_received.connect(_receive)
	api.players_changed.connect(_players_changed)

func _ready() -> void:
	super()
	if api == null:
		push_error("请从小游戏轮换启动霓虹回响")
		return
	if not backend.last_error.is_empty():
		_fail(backend.last_error)
		return
	var chart: Dictionary = Backend.Chart.read_chart(Backend.DEFAULT_CHART)
	if not chart.ok:
		_fail(chart.error)
		return
	song_length = chart.duration
	combo_limit = chart.notes.size()
	for i: int in range(chart.notes.size()):
		if chart.ends[i] > chart.notes[i]:
			combo_limit += 1 + chart.subs[i].size()
	$HUD/PauseButton.hide()
	playback_failed.connect(_fail)
	_build_round_board()
	var error: Error = api.mark_ready()
	if error != OK:
		_fail(error_string(error))

func _build_round_board() -> void:
	var templates: Array[HBoxContainer] = [board.get_node("Self"), board.get_node("Waiting1"), board.get_node("Waiting2"), board.get_node("Waiting3")]
	while templates.size() < players.size():
		var copy: HBoxContainer = templates[1].duplicate() as HBoxContainer
		board.add_child(copy)
		templates.append(copy)
	for i: int in range(templates.size()):
		var row: HBoxContainer = templates[i]
		row.visible = i < players.size()
		if not row.visible:
			continue
		var player: Dictionary = players[i]
		rows[player.player_id] = row
		row.get_node("Player").text = player.name
		row.modulate = ACCENT if player.is_local else Color.WHITE
		if player.is_local:
			_leaderboard_accuracy = row.get_node("Accuracy")
	board.get_node("Heading/Placeholder").text = "观战" if local_player.is_empty() else "实时"
	_render_board()

func party_start() -> void:
	running = true
	deadline_ms = Time.get_ticks_msec() + ceili((song_length + preparation_seconds + FINISH_GRACE_SECONDS) * 1000.0)
	if local_player.is_empty():
		for child: Control in $HUD.get_children():
			child.visible = child == _leaderboard
		$HUD.show()
	else:
		start_game()
	_players_changed()

func party_stop(_reason: StringName) -> void:
	running = false
	if is_node_ready() and backend != null:
		stop_playback()
	set_process(false)
	set_process_input(false)

func _input(event: InputEvent) -> void:
	if not running or local_player.is_empty() or (event is InputEventKey and event.physical_keycode == KEY_ESCAPE):
		return
	super(event)

## Losing focus releases held lanes while the shared round continues.
func pause_game() -> void:
	if mode == "playing":
		for lane: int in range(backend.key_count):
			backend._key_sources[lane].clear()
			backend.press_lane(lane, false, false)

func finish_game() -> void:
	mode = "stopped"
	$HUD/Judgment.text = "演奏完成"
	timing_error.text = "等待本轮结算"
	_report(true)

func _process(delta: float) -> void:
	if not running:
		return
	super(delta)
	if not running:
		return
	publish_in -= delta
	if publish_in > 0.0:
		return
	publish_in = REPORT_INTERVAL
	if mode == "playing" and not local_player.is_empty():
		_report(false)
	if api.is_host() and running:
		if Time.get_ticks_msec() >= deadline_ms:
			for data: Dictionary in reports.values():
				if data.status == "playing":
					data.status = "withdrawn"
		_publish()

func _report(done: bool) -> void:
	var data: Dictionary = {"accuracy": roundi(backend.scoring.accuracy() * 10000.0), "combo": backend._best_combo, "status": "completed" if done else "playing"}
	if api.is_host():
		reports[local_player] = data
	else:
		var error: Error = api.net.send_to_host(&"performance", data)
		if error != OK:
			_fail(error_string(error))

func _valid_report(data: Variant) -> bool:
	return data is Dictionary and data.get("accuracy") is int and data.accuracy >= 0 and data.accuracy <= 10000 and data.get("combo") is int and data.combo >= 0 and data.combo <= combo_limit

func _receive(sender: Dictionary, topic: StringName, payload: Variant) -> void:
	if not running:
		return
	if topic == &"performance" and api.is_host():
		if not _valid_report(payload) or payload.get("status") not in ["playing", "completed"]:
			return
		for id: String in sender.player_ids:
			if reports.has(id) and reports[id].status == "playing":
				reports[id] = payload
				return
	elif topic == &"standings" and not api.is_host() and sender.peer_id == 1:
		if not payload is Dictionary or payload.size() != reports.size():
			return
		for id: String in reports:
			var data: Variant = payload.get(id)
			if not _valid_report(data) or data.get("status") not in ["playing", "completed", "withdrawn"]:
				return
		reports = payload
		_render_board()

func _players_changed() -> void:
	if running and api.is_host():
		for player: Dictionary in api.get_players():
			if not player.connected and reports[player.player_id].status == "playing":
				reports[player.player_id].status = "withdrawn"

func _ahead(a: String, b: String) -> bool:
	if (reports[a].status == "withdrawn") != (reports[b].status == "withdrawn"):
		return reports[b].status == "withdrawn"
	return reports[a].accuracy > reports[b].accuracy

func _rank(id: String) -> int:
	if reports[id].status == "withdrawn":
		return 0
	var rank_value: int = 1
	for other: String in reports:
		if _ahead(other, id):
			rank_value += 1
	return rank_value

func _render_board() -> void:
	var ids: Array = reports.keys()
	ids.sort_custom(_ahead)
	for i: int in range(ids.size()):
		var id: String = ids[i]
		var row: HBoxContainer = rows[id]
		board.move_child(row, 2 + i)
		var rank_value: int = _rank(id)
		row.get_node("Rank").text = str(rank_value) if rank_value > 0 else "—"
		row.get_node("Accuracy").text = "%.2f%%" % (float(reports[id].accuracy) / 100.0) if rank_value > 0 else "已退出"

func _publish() -> void:
	_render_board()
	var error: Error = api.net.broadcast(&"standings", reports)
	if error != OK:
		_fail(error_string(error))
		return
	var rankings: Array[Dictionary] = []
	for id: String in reports:
		var data: Dictionary = reports[id]
		if data.status == "playing":
			return
		rankings.append({"player_id": id, "rank": _rank(id), "status": data.status, "metrics": {"accuracy": float(data.accuracy) / 100.0, "combo": data.combo}})
	running = false
	error = api.finish({"request_id": request_id, "reason": "completed", "rankings": rankings, "columns": [{"key": "accuracy", "title": "准确率 (%)", "format": "decimal"}, {"key": "combo", "title": "最长连击", "format": "integer"}]})
	if error != OK:
		_fail(error_string(error))

func _fail(message: String) -> void:
	running = false
	api.fail("rhythm_round_failed", message)
