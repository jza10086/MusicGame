extends SceneTree
const Session = preload("res://core/rhythm_session.gd")
var checks := 0
var failures := 0

func check(condition:bool, label:String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func _init() -> void:
	for difficulty in range(2):
		var s = Session.new()
		s.start(difficulty)
		var original = s.notes.duplicate(true)
		s.start(difficulty)
		check(original == s.notes, "deterministic chart %d" % difficulty)
		check(s.notes.size() == (94 if difficulty == 0 else 135), "chart count %d" % difficulty)
		var previous := -1.0
		var seen := {}
		for note in s.notes:
			check(note.time >= previous and note.time < s.DURATION-s.GOOD_WINDOW, "sorted note within duration")
			var identity = "%s:%s" % [note.time,note.lane]
			check(not seen.has(identity), "no duplicate chart note")
			seen[identity] = true
			previous = note.time
			s.advance(float(note.time)-s.time)
			check(s.press(note.lane) == "PERFECT", "autoplay exact note")
			s.release(note.lane)
		s.advance(s.DURATION-s.time)
		check(s.finished and not s.running, "autoplay completes")
		check(s.score==1000000 and s.perfect==s.notes.size() and s.misses==0 and s.good==0, "million perfect score")
		check(s.max_combo==s.notes.size() and s.accuracy()==100.0 and s.grade()=="SS", "perfect metrics")
		s.start(difficulty)
		s.advance(100)
		check(s.finished and s.misses==s.notes.size() and s.score==0 and s.accuracy()==0 and s.grade()=="C", "miss all completes")
		var missed = s.misses
		s.advance(1)
		check(s.misses==missed, "miss is counted once")
	for note_time in [2.0, 11.5, 40.0]:
		for offset in [-0.151,-0.150,-0.071,-0.070,0.0,0.070,0.071,0.150,0.151]:
			var s = Session.new()
			s.start()
			s.notes.clear()
			s.notes.append({"time":note_time,"lane":0,"hit":false,"missed":false})
			s.time = note_time+offset
			var expected := ""
			if absf(offset)<=0.150: expected = "PERFECT" if absf(offset)<=0.070 else "GOOD"
			check(s.press(0)==expected, "boundary t=%s offset=%s expected=%s" % [note_time,offset,expected])
	for note_time in [2.0, 11.5, 40.0]:
		var boundary = Session.new()
		boundary.start()
		boundary.notes.clear()
		boundary.notes.append({"time":note_time,"lane":0,"hit":false,"missed":false})
		boundary.time = note_time
		boundary.advance(0.150)
		check(boundary.misses==0 and boundary.press(0)=="GOOD", "advance to late boundary remains hittable")
		boundary.start()
		boundary.notes.clear()
		boundary.notes.append({"time":note_time,"lane":0,"hit":false,"missed":false})
		boundary.time = note_time
		boundary.advance(0.15001)
		check(boundary.misses==1 and boundary.press(0)=="", "advance beyond late boundary misses")
	var s = Session.new()
	s.start()
	s.time = 2.0
	check(s.press(-1)=="" and s.press(2)=="", "invalid lanes ignored")
	check(s.press(0)=="PERFECT", "first hit")
	var score = s.score
	for i in range(8): check(s.press(0)=="" and s.score==score, "held repeat ignored")
	s.advance(1.0)
	check(s.press(0)=="" and s.score==score, "holding cannot hit next note")
	s.release(0)
	check(s.press(0)=="PERFECT", "release enables next note")
	s.start()
	s.time = 5.5
	check(s.press(0)=="PERFECT" and s.press(1)=="PERFECT" and s.combo==2, "simultaneous chord")
	s.set_paused(true)
	var paused_time = s.time
	s.advance(10)
	check(s.time==paused_time and s.press(0)=="" and s.held==[false,false], "pause freezes and clears holds")
	s.set_paused(false)
	s.advance(0.1)
	check(is_equal_approx(s.time,paused_time+0.1), "resume advances")
	s.start(1)
	check(s.time==-2 and s.combo==0 and s.score==0 and s.misses==0 and s.events.is_empty() and s.held==[false,false] and not s.paused, "restart resets all state")
	s.advance(-1)
	check(s.time==-2, "negative delta ignored")
	s.cancel()
	s.advance(5)
	check(not s.running and not s.paused and s.time==-2 and s.press(0)=="" and s.events.is_empty(), "cancel is inert")
	print("CORE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
