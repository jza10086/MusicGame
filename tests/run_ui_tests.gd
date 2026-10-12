extends SceneTree
var checks := 0
var failures := 0
var ui:Control

func check(condition:bool,label:String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ",label)

func key(code:int, down:bool=true, echo:bool=false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	event.echo = echo
	ui._input(event)

func touch(index:int,position:Vector2,down:bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = down
	ui._input(event)

func fresh_note(lane:int=0) -> void:
	ui.start_game()
	ui.session.notes.clear()
	ui.session.notes.append({"time":2.0,"lane":lane,"hit":false,"missed":false})
	ui.session.time = 2.0

func _init() -> void:
	call_deferred("run")

func run() -> void:
	ui = load("res://ui/main.tscn").instantiate()
	root.add_child(ui)
	ui.set_process(false)
	await process_frame
	check(ui.mode=="menu" and ui.get_node("Menu").visible and not ui.get_node("HUD").visible,"initial menu")
	for style in range(3):
		ui.get_node("Menu/Style"+str(style)).pressed.emit()
		await process_frame
		check(ui.selected==style and is_instance_valid(ui.skin),"load skin %d" % style)
		check(ui.get_node("Backdrop").get_child_count()==1,"old skin removed")
		check(ui.skin.state.mode=="menu","skin receives menu state")
		ui.get_node("Menu/Hard").pressed.emit()
		ui.get_node("Menu/Begin").pressed.emit()
		check(ui.difficulty==1 and ui.mode=="playing" and ui.session.notes.size()==135,"menu buttons start hard chart")
		ui._process(2.2)
		await process_frame
		check(ui.skin.state.mode=="playing" and ui.get_node("HUD").visible,"skin gameplay state")
		for path in ["Header", "Footer", "HUD/TrackEyebrow", "HUD/TrackSub", "HUD/Best", "HUD/Accuracy"]:
			check(not ui.get_node(path).is_visible_in_tree(), "no stage presentation or instructions: " + path)
		check(ui.get_node("HUD/TrackTitle").text == ui.TITLES[style], "unprefixed song title")
		var old_time:float = ui.session.time
		key(KEY_D)
		key(KEY_ESCAPE)
		ui._process(2.0)
		check(ui.mode=="paused" and ui.session.time==old_time and ui.session.held==[false,false],"pause freezes and clears held")
		check(ui.get_node("Modal/Pause").visible and ui.get_node("Modal").visible,"pause modal")
		check(not ui.get_node("Header").visible and not ui.get_node("Footer").visible, "pause clean of branding and instructions")
		key(KEY_ESCAPE)
		check(ui.mode=="playing" and ui.resume_countdown==2.0 and ui.session.paused,"resume countdown")
		key(KEY_K)
		ui._process(1.0)
		check(ui.session.time==old_time and ui.session.held==[false,false],"countdown ignores input and freezes")
		ui._process(1.0)
		check(not ui.session.paused and ui.resume_countdown==0.0,"countdown releases pause")
		ui._process(0.5)
		check(is_equal_approx(ui.session.time,old_time+0.5),"resumed chart progresses")
		ui.pause_game()
		ui.get_node("Modal/Pause/Restart").pressed.emit()
		check(ui.mode=="playing" and ui.session.time==-2.0 and ui.session.score==0 and ui.key_sources==[{},{}],"pause restart resets")
		ui._process(100.0)
		await process_frame
		check(ui.mode=="results" and ui.session.finished and ui.get_node("Modal/Results").visible,"automatic results")
		check(not ui.get_node("Header").visible and not ui.get_node("Footer").visible, "results clean of branding and instructions")
		check(ui.get_node("Modal/Results/Grade").text=="C" and ui.get_node("Modal/Results/FinalScore").text=="0000000","results metrics")
		ui.get_node("Modal/Results/Again").pressed.emit()
		check(ui.mode=="playing" and ui.session.time==-2,"results replay")
		ui.finish_game()
		ui.get_node("Modal/Results/Home").pressed.emit()
		check(ui.mode=="menu" and not ui.session.running,"results home cancels")
		ui.start_game()
		ui.pause_game()
		ui.get_node("Modal/Pause/Back").pressed.emit()
		check(ui.mode=="menu" and ui.touch_lanes.is_empty(),"pause home")
	for code in [KEY_D,KEY_F,KEY_LEFT,KEY_K,KEY_J,KEY_RIGHT]:
		var lane := 0 if code in [KEY_D,KEY_F,KEY_LEFT] else 1
		fresh_note(lane)
		key(code)
		check(ui.session.perfect==1 and ui.session.held[lane],"alias hits: %d" % code)
		key(code,true,true)
		check(ui.session.perfect==1,"echo ignored")
		key(code,false)
		check(not ui.session.held[lane],"alias release")
	fresh_note()
	key(KEY_D)
	key(KEY_F)
	key(KEY_D,false)
	check(ui.session.held[0] and ui.key_sources[0].size()==1 and ui.session.perfect==1,"alias source overlap")
	key(KEY_F,false)
	check(not ui.session.held[0],"last alias release clears hold")
	fresh_note()
	touch(0,Vector2(800,850),true)
	touch(1,Vector2(850,850),true)
	touch(0,Vector2(800,850),false)
	check(ui.session.held[0] and ui.session.perfect==1,"multi-touch source overlap")
	touch(1,Vector2(850,850),false)
	check(not ui.session.held[0],"last touch release")
	key(KEY_D)
	touch(2,Vector2(1100,850),true)
	ui.show_menu()
	ui.start_game()
	check(ui.session.held==[false,false] and ui.key_sources==[{},{}] and ui.touch_lanes.is_empty(),"home restart clears old input")
	key(KEY_D,false)
	touch(2,Vector2(1100,850),false)
	check(ui.session.held==[false,false],"stale releases harmless")
	ui._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(ui.mode=="paused","focus loss pauses")
	for style in range(3):
		ui.show_menu()
		ui.select_style(style)
		if ui.reduced_motion: ui.toggle_motion()
		ui.get_node("Menu/Motion").pressed.emit()
		ui.effects.append({"lane":0,"quality":"PERFECT","age":0.0})
		ui._process(0.1)
		await process_frame
		check(ui.reduced_motion and ui.skin.state.time==0 and ui.skin.state.effects.is_empty(),"reduced motion skin %d" % style)
		ui.toggle_motion()
		ui._process(0.1)
		check(ui.skin.state.time>0,"full motion restored")
	fresh_note()
	touch(8,Vector2(800,200),true)
	check(ui.session.perfect==0 and ui.session.held==[false,false],"touch HUD does not hit lane")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = ui.skin.playfield_transform() * Vector2(830,870)
	mouse.pressed = true
	ui._input(mouse)
	check(ui.session.perfect==1 and ui.session.held[0],"mouse target hits lane")
	mouse.pressed = false
	ui._input(mouse)
	check(not ui.session.held[0],"mouse release clears lane")
	ui.show_menu()
	ui.get_node("Menu/Easy").pressed.emit()
	ui.get_node("Menu/Begin").pressed.emit()
	check(ui.difficulty==0 and ui.session.notes.size()==94,"easy menu selection")
	for note in ui.session.notes:
		ui._process(float(note.time)-ui.session.time)
		var code:int = KEY_D if note.lane==0 else KEY_K
		key(code)
		key(code,false)
	ui._process(ui.session.DURATION-ui.session.time)
	check(ui.mode=="results" and ui.get_node("Modal/Results/Grade").text=="SS" and ui.get_node("Modal/Results/FinalScore").text=="1000000", "full UI autoplay perfect results")
	for resolution in [Vector2i(1280,720),Vector2i(640,360),Vector2i(1280,800),Vector2i(1600,720),Vector2i(720,1280)]:
		root.size = resolution
		await process_frame
		await process_frame
		check(root.size==resolution,"window size %s" % resolution)
		var viewport_size := root.get_visible_rect().size
		check(ui.size.is_equal_approx(viewport_size),"canvas fills expanded viewport at %s" % resolution)
		check(absf(viewport_size.x / viewport_size.y - float(resolution.x) / resolution.y) < 0.001, "no letterboxing at %s" % resolution)
		for style in range(3):
			ui.select_style(style)
			ui.start_game()
			ui._process(3.5)
			await process_frame
			check(ui.skin.size.is_equal_approx(viewport_size),"skin fills stage %d at %s" % [style,resolution])
			var transform: Transform2D = ui.skin.playfield_transform()
			check(is_equal_approx(transform.x.length(), transform.y.length()), "uniform track scale")
			if style == 1:
				var top: Vector2 = transform * Vector2(960, ui.skin.TRACK_TOP)
				check(top.y >= ui.get_node("HUD/Judgment").get_global_rect().end.y + 8.0, "pixel header clears judgment text")
				check(ui.skin.NOTE_ENTRY_Y - 22.0 > ui.skin.TRACK_TOP, "pixel entering notes stay below header")
			var background: Transform2D = ui.skin.environment_transform()
			var coverage: Rect2 = background * Rect2(0,0,1920,1080)
			check(coverage.grow(0.1).encloses(Rect2(Vector2.ZERO,viewport_size)), "background covers viewport")
			for lane in range(2):
				fresh_note(lane)
				var target: Vector2 = transform * Vector2(830 + lane * 260, 870)
				touch(lane,target,true)
				check(ui.session.perfect == 1 and ui.session.held[lane], "responsive touch lane %d" % lane)
				touch(lane,target,false)
			check(ui.skin.lane_at_position(Vector2(20,20)) == -1, "HUD excluded from hit testing")
			var rect:Rect2 = ui.get_node("HUD/PauseButton").get_global_rect()
			check(Rect2(Vector2.ZERO,viewport_size).encloses(rect),"pause inside viewport")
	ui.queue_free()
	await process_frame
	print("UI: %d checks, %d failures (headless canvas; not GPU screenshot validation)" % [checks,failures])
	quit(1 if failures else 0)
