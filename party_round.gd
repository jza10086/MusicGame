## Standard original-protocol round. Each participant judges against their own audio clock.
extends "res://games/minigame/gp_rhythm_game/music_game.gd"

## Content-owned gameplay rules, independent of package compatibility.
static func party_definition() -> Dictionary:
	return {"player_counts": [1, 2, 3, 4, 5, 6, 7, 8], "tags": ["original", "rhythm"]}


const REPORT_INTERVAL: float = 0.4
const FINISH_GRACE_SECONDS: float = 20.0
const Pages = preload("res://games/protocols/godot_party_default_protocol/round_pages.gd")
const RandomPool = preload("res://games/protocols/godot_party_default_protocol/random/least_played_pool.gd")
const SONG_TOPIC: StringName = &"rhythm/song"
const SONG_REQUEST_TOPIC: StringName = &"rhythm/song_request"
## The inherited Song is the first pool entry. Save every extra song as a package-local resource.
@export var additional_songs: Array[RhythmSong] = []
var _songs: Dictionary[String, RhythmSong] = {}
var _song_pool: RandomPool
var _selected_song: String = ""
var _started: bool = false
var _stopped: bool = false
@export var pages: Pages
var api: PartyAPI
var request: Dictionary
var request_id: String
var local_player: String
var players: Array[Dictionary]
var reports: Dictionary = {}
var rows: Dictionary[String, HBoxContainer] = {}
var running: bool = false
var publish_in: float = 0.0
var song_length: float
var _combo_limits: Dictionary[String, int] = {}
var _base_scores: Dictionary[String, int] = {}
var deadline_ms: int
var _negative_lead: float = 0.0
var _last_report: Dictionary = {}
var _published_reports: Dictionary = {}
var _final_reported: bool = false
@onready var board: VBoxContainer = $HUD/Leaderboard/Panel/Rows

func party_setup(value: PartyAPI, config: Dictionary) -> void:
	api = value
	$Audio/AudioBackend.party_config = api.config
	request = config.duplicate(true)
	request_id = config.request_id
	players = api.get_players()
	for player: Dictionary in players:
		var id: String = player.player_id
		if player.is_local:
			local_player = id
		reports[id] = {"accuracy": 10000, "combo": 0, "status": "playing"}
	api.players_changed.connect(_players_changed)

func _ready() -> void:
	super()
	if api == null:
		push_error("请从小游戏轮换启动霓虹节拍")
		return
	if not backend.last_error.is_empty():
		_fail(backend.last_error)
		return
	if not _prepare_song_pool():
		return
	api.net.message_received.connect(_receive)
	if api.is_host():
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = api.get_seed()
		_select_song(_song_pool.choose(rng))
		if not _stopped:
			_broadcast_song()
	else:
		var error: Error = api.net.send_to_host(SONG_REQUEST_TOPIC, _song_envelope())
		if error != OK:
			_fail("无法请求本轮曲目：" + error_string(error))

## Initialize device-local counts before selection. No history is written until play begins.
func _prepare_song_pool() -> bool:
	var entries: Array[RhythmSong] = [song]
	entries.append_array(additional_songs)
	var root_path: String = Backend.Paths.root_directory() + "/"
	var ids: Array[String] = []
	for entry: RhythmSong in entries:
		if entry == null or not entry.resource_path.begins_with(root_path) or entry.resource_path.get_extension() not in ["tres", "res"]:
			_fail("曲目池必须绑定已保存到音游包目录内的曲目 Resource")
			return false
		var id: String = entry.resource_path.trim_prefix(root_path)
		if _songs.has(id):
			_fail("曲目池重复：" + id)
			return false
		_songs[id] = entry
		ids.append(id)
	_song_pool = RandomPool.new(ids)
	var path: String = api.input.storage_directory().path_join("minigame/%s/config/song_pool_stats.json" % api.package_id)
	var error: Error = _song_pool.open_file(path)
	if error != OK:
		_fail("无法读取曲目游玩统计：%s · %s" % [path, error_string(error)])
		return false
	return true

func _song_envelope() -> Dictionary:
	return {"session": api.session_id, "scope": api.scope_id}

func _broadcast_song() -> void:
	var payload: Dictionary = _song_envelope()
	payload.song = _selected_song
	var error: Error = api.net.broadcast(SONG_TOPIC, payload)
	if error != OK:
		_fail("无法同步本轮曲目：" + error_string(error))

## One authoritative selection per activation; duplicate delivery cannot rebuild the ready page.
func _select_song(id: String) -> void:
	if not _songs.has(id):
		_fail("本机曲目池中不存在房主选择的曲目：" + id)
		return
	if not _selected_song.is_empty():
		if _selected_song != id:
			_fail("房主在同一轮中更换了已选曲目")
		return
	_selected_song = id
	song = _songs[id]
	_prepare_song()

func _prepare_song() -> void:
	var chart: Dictionary = read_selected_chart()
	if not chart.ok:
		_fail(chart.error)
		return
	song_length = chart.duration
	var options: Array[String] = []
	for entry: RhythmSongChart in song.charts:
		var variant_chart: Dictionary = song.read_chart(entry.difficulty)
		if not variant_chart.ok:
			_fail(variant_chart.error)
			return
		_negative_lead = maxf(_negative_lead, maxf(0.0, -float(variant_chart.notes[0])))
		var editor_data: Dictionary = variant_chart.data.get("editor", {})
		_negative_lead = maxf(_negative_lead, maxf(0.0, -float(editor_data.get("offset_ms", 0.0)) / 1000.0))
		var limit: int = variant_chart.notes.size()
		for i: int in range(variant_chart.notes.size()):
			if variant_chart.ends[i] > variant_chart.notes[i]:
				limit += 1 + variant_chart.subs[i].size()
		_combo_limits[entry.difficulty] = limit
		_base_scores[entry.difficulty] = entry.base_score
		options.append(entry.difficulty)
	$HUD/PauseButton.hide()
	$HUD/StandingsToggle.text = api.i18n.text(&"round.rankings")
	$HUD/MenuHint.text = api.i18n.text(&"round.menu_hint")
	playback_failed.connect(_fail)
	add_to_group(&"party_minimal_hud")
	leaderboard_expanded = local_player.is_empty()
	$HUD/StandingsToggle.pressed.connect(func() -> void: leaderboard_expanded = not leaderboard_expanded)
	_build_round_board()
	assert(pages != null, "Assign ProtocolPages in the game scene")
	var error: Error = pages.prepare(self, api, request, _start_gameplay, {
		"choice_label": "难度", "choice_options": options, "choice_default": difficulty,
		"introduction": "%s\n每位玩家选择自己的难度，准备后锁定。按基准分数 × 准确率排名。" % chart.data.title})
	if error != OK:
		_fail(error_string(error))

func _build_round_board() -> void:
	var templates: Array[HBoxContainer] = [board.get_node("Self"), board.get_node("Waiting1"), board.get_node("Waiting2"), board.get_node("Waiting3")]
	while templates.size() < players.size():
		var copy: HBoxContainer = preload("ui/player_row.tscn").instantiate()
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
	board.get_node("Heading/Placeholder").text = api.i18n.text(&"round.spectating") if local_player.is_empty() else api.i18n.text(&"round.live")
	_render_board()

func party_start() -> void:
	pages.transport_started()

func _start_gameplay() -> void:
	if _stopped or _started:
		return
	var error: Error = _song_pool.accept_history([_selected_song])
	if error != OK:
		_fail("无法保存曲目游玩统计：" + error_string(error))
		return
	_started = true
	if api.is_host():
		var audio_zero: int = api.net.host_time_msec() + ceili((preparation_seconds + _negative_lead) * 1000.0)
		var send_error: Error = api.net.broadcast(&"rhythm/start", {"audio_zero_msec": audio_zero,
			"deadline_msec": audio_zero + ceili((song_length + FINISH_GRACE_SECONDS) * 1000.0)})
		if send_error != OK:
			_fail(error_string(send_error))

func _begin_scheduled_play(payload: Dictionary) -> void:
	if running or not _started or not payload.get("audio_zero_msec") is int or not payload.get("deadline_msec") is int:
		return
	deadline_ms = payload.deadline_msec
	running = true
	if local_player.is_empty():
		for child: Control in $HUD.get_children():
			child.visible = child == _leaderboard or child.name == &"MenuHint"
		$HUD.show()
	else:
		difficulty = pages.briefing.get_choice(local_player)
		skip_intro = false
		start_game()
		if not running:
			return
		backend.schedule_audio_zero(float(payload.audio_zero_msec - api.net.host_time_msec()) / 1000.0)
	_players_changed()

func party_stop(_reason: StringName) -> void:
	_stopped = true
	running = false
	if is_node_ready() and backend != null:
		shutdown_playback()
	if pages != null:
		pages.stop()
	if api.net.message_received.is_connected(_receive):
		api.net.message_received.disconnect(_receive)
	if api.players_changed.is_connected(_players_changed):
		api.players_changed.disconnect(_players_changed)

func _input(event: InputEvent) -> void:
	if not running or api.input.input_blocked or local_player.is_empty() or (event is InputEventKey and event.physical_keycode == KEY_ESCAPE):
		return
	super(event)

func _gui_input(event: InputEvent) -> void:
	if not running or api.input.input_blocked or local_player.is_empty():
		return
	super(event)

## Losing focus releases held lanes while the shared round continues.
func pause_game() -> void:
	if mode == "playing":
		backend.release_inputs()

func finish_game() -> void:
	mode = "stopped"
	$HUD/Judgment.text = api.i18n.text(&"round.complete")
	timing_error.text = api.i18n.text(&"round.waiting")
	_report(true)

func _process(delta: float) -> void:
	if not running:
		return
	if api.input.input_blocked:
		pause_game()
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
		if api.net.host_time_msec() >= deadline_ms:
			for data: Dictionary in reports.values():
				if data.status == "playing":
					data.status = "withdrawn"
		_publish()

func _report(done: bool) -> void:
	var data: Dictionary = backend.performance()
	data.status = "completed" if done else "playing"
	if _final_reported or data == _last_report:
		return
	_last_report = data.duplicate()
	_final_reported = done
	if api.is_host():
		reports[local_player] = data
	else:
		var error: Error = api.net.send_to_host(&"performance", data)
		if error != OK:
			_fail(error_string(error))

func _valid_report(data: Variant, player_id: String) -> bool:
	var limit: int = _combo_limits[pages.briefing.get_choice(player_id)]
	return data is Dictionary and data.get("accuracy") is int and data.accuracy >= 0 and data.accuracy <= 10000 and data.get("combo") is int and data.combo >= 0 and data.combo <= limit

func _receive(sender: Dictionary, topic: StringName, payload: Variant) -> void:
	if _stopped:
		return
	if topic == &"rhythm/start" and sender.peer_id == 1:
		if payload is Dictionary:
			_begin_scheduled_play(payload)
		return
	if topic == SONG_REQUEST_TOPIC or topic == SONG_TOPIC:
		if not payload is Dictionary or payload.get("session") != api.session_id or payload.get("scope") != api.scope_id:
			return
		if topic == SONG_REQUEST_TOPIC and api.is_host():
			_broadcast_song()
		elif topic == SONG_TOPIC and not api.is_host() and sender.peer_id == 1:
			if not payload.get("song") is String:
				_fail("房主发送了无效的曲目选择")
				return
			_select_song(payload.song)
		return
	if not running:
		return
	if topic == &"performance" and api.is_host():
		if not payload is Dictionary or payload.get("status") not in ["playing", "completed"]:
			return
		for id: String in sender.player_ids:
			if reports.has(id) and reports[id].status == "playing" and _valid_report(payload, id):
				reports[id] = payload
				return
	elif topic == &"standings" and not api.is_host() and sender.peer_id == 1:
		if not payload is Dictionary or payload.size() > reports.size():
			return
		for id: String in payload:
			if not reports.has(id):
				return
			var data: Variant = payload[id]
			if not _valid_report(data, id) or data.get("status") not in ["playing", "completed", "withdrawn"]:
				return
		reports.merge(payload, true)
		_render_board()

func _players_changed() -> void:
	if running and api.is_host():
		for player: Dictionary in api.get_players():
			if not player.connected and reports[player.player_id].status == "playing":
				reports[player.player_id].status = "withdrawn"

## Difficulty choices are locked by the briefing; never trust a client-supplied score.
func _player_score(id: String) -> int:
	var selected_difficulty: String = pages.briefing.get_choice(id) if _started else difficulty
	return Backend.Scoring.score_for_accuracy(_base_scores[selected_difficulty], float(reports[id].accuracy) / 10000.0)

func _ahead(a: String, b: String) -> bool:
	if (reports[a].status == "withdrawn") != (reports[b].status == "withdrawn"):
		return reports[b].status == "withdrawn"
	return _player_score(a) > _player_score(b)

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
		if row.get_index() != 2 + i:
			board.move_child(row, 2 + i)
		var rank_value: int = _rank(id)
		row.get_node("Rank").text = str(rank_value) if rank_value > 0 else "—"
		row.get_node("Accuracy").text = api.i18n.text(&"hud.accuracy", {"accuracy": "%.2f" % (float(reports[id].accuracy) / 100.0)}) if rank_value > 0 else api.i18n.text(&"round.withdrawn")

func _publish() -> void:
	_render_board()
	var changes: Dictionary = {}
	for id: String in reports:
		if not _published_reports.has(id) or _published_reports[id] != reports[id]:
			changes[id] = reports[id]
	var error: Error = OK
	if not changes.is_empty():
		error = api.net.broadcast(&"standings", changes)
		if error != OK:
			_fail(error_string(error))
			return
		_published_reports.merge(changes.duplicate(true), true)
	var rankings: Array[Dictionary] = []
	for id: String in reports:
		var data: Dictionary = reports[id]
		if data.status == "playing":
			return
		rankings.append({"player_id": id, "rank": _rank(id), "status": data.status, "metrics": {"score": _player_score(id), "accuracy": float(data.accuracy) / 100.0, "combo": data.combo}})
	running = false
	error = pages.present({"request_id": request_id, "reason": "completed", "rankings": rankings, "columns": [{"key": "score", "title": api.i18n.text(&"round.score"), "format": "integer"}, {"key": "accuracy", "title": api.i18n.text(&"round.accuracy"), "format": "decimal"}, {"key": "combo", "title": api.i18n.text(&"round.combo"), "format": "integer"}]})
	if error != OK:
		_fail(error_string(error))

func _fail(message: String) -> void:
	party_stop(&"failed")
	api.fail("rhythm_round_failed", message)
