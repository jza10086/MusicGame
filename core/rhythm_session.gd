extends RefCounted
## Deterministic, audio-independent chart and judgment model.
const EPSILON := 0.00000001
const PERFECT_WINDOW := 0.070
const GOOD_WINDOW := 0.150
const DURATION := 48.0
var notes: Array[Dictionary] = []
var time := -2.0
var running := false
var paused := false
var finished := false
var combo := 0
var max_combo := 0
var perfect := 0
var good := 0
var misses := 0
var score := 0
var held := [false, false]
var events: Array[Dictionary] = []

func start(difficulty: int = 0) -> void:
	notes.clear()
	var step := 0.50 if difficulty == 0 else 0.375
	var count := 84 if difficulty == 0 else 112
	for i in range(count):
		var beat := 2.0 + i * step
		var lane := (i + int(i / 8)) % 2
		notes.append({"time":beat,"lane":lane,"hit":false,"missed":false})
		if i % 8 == 7 or (difficulty == 1 and i % 12 == 4):
			notes.append({"time":beat,"lane":1-lane,"hit":false,"missed":false})
	notes.sort_custom(func(a:Dictionary,b:Dictionary)->bool: return float(a.time)<float(b.time))
	time = -2.0
	running = true
	paused = false
	finished = false
	combo = 0
	max_combo = 0
	perfect = 0
	good = 0
	misses = 0
	score = 0
	held = [false,false]
	events.clear()

func advance(delta: float) -> void:
	if not running or paused or finished: return
	time += maxf(delta,0.0)
	for note in notes:
		if not note.hit and not note.missed and time > float(note.time)+GOOD_WINDOW+EPSILON:
			note.missed = true
			misses += 1
			combo = 0
			events.append({"lane":int(note.lane),"quality":"MISS"})
	if time >= DURATION:
		finished = true
		running = false

func press(lane:int) -> String:
	if lane < 0 or lane > 1 or not running or paused or finished or held[lane]: return ""
	held[lane] = true
	var candidate:Dictionary = {}
	var distance := GOOD_WINDOW + 0.001
	for note in notes:
		if int(note.lane) != lane or note.hit or note.missed: continue
		var d := absf(float(note.time)-time)
		if d <= GOOD_WINDOW+EPSILON and d < distance:
			candidate = note
			distance = d
	if candidate.is_empty(): return ""
	candidate.hit = true
	combo += 1
	max_combo = maxi(max_combo,combo)
	var quality := "PERFECT" if distance <= PERFECT_WINDOW+EPSILON else "GOOD"
	if quality == "PERFECT": perfect += 1
	else: good += 1
	score = roundi((perfect + good * 0.65) / notes.size() * 1000000.0)
	events.append({"lane":lane,"quality":quality})
	return quality

func release(lane:int) -> void:
	if lane >= 0 and lane <= 1: held[lane] = false

func set_paused(value:bool) -> void:
	if not running: return
	paused = value
	held = [false,false]

func cancel() -> void:
	running = false
	paused = false
	held = [false,false]
	events.clear()

func accuracy() -> float:
	var judged := perfect+good+misses
	return 100.0 if judged==0 else (perfect+good*0.65)/judged*100.0

func grade() -> String:
	if misses==0 and good==0: return "SS"
	if accuracy()>=95: return "S"
	if accuracy()>=85: return "A"
	if accuracy()>=70: return "B"
	return "C"
