## Runtime waveform analysis uses a private decoder, never the audible playback instance.
## Bounded batches keep editing responsive; peak levels are shared by timeline and overview.
extends Node
signal updated
var levels: Array = []
var stream: AudioStream
var decoder: AudioStreamPlayback
var duration: float = 0.0
var progress: float = 0.0
var complete: bool = false
var _base: PackedVector2Array = PackedVector2Array()
var _rate: float = 48000.0
var _frames: int = 0
const BLOCK: int = 256

func begin(audio: AudioStream) -> void:
	stream = audio
	decoder = audio.instantiate_playback()
	duration = audio.get_length()
	_rate = AudioServer.get_mix_rate()
	_frames = 0
	progress = 0.0
	complete = false
	_base.clear()
	levels.clear()
	decoder.start()
	set_process(true)

func _process(_delta: float) -> void:
	if decoder==null or complete:
		return
	var deadline: int = Time.get_ticks_usec()+2000
	while Time.get_ticks_usec()<deadline:
		var pcm: PackedVector2Array = decoder.mix_audio(1.0,BLOCK)
		if pcm.is_empty():
			_finish()
			break
		var low: float = 0.0
		var high: float = 0.0
		for frame: Vector2 in pcm:
			low = minf(low,minf(frame.x,frame.y))
			high = maxf(high,maxf(frame.x,frame.y))
		_base.append(Vector2(low,high))
		_frames += pcm.size()
		progress = minf(1.0,float(_frames)/_rate/duration)
		if float(_frames)/_rate>=duration:
			_finish()
			break
	if not complete:
		levels = [_base]
	updated.emit()

func _finish() -> void:
	complete = true
	progress = 1.0
	levels = [_base]
	var current: PackedVector2Array = _base
	while current.size()>1:
		var next: PackedVector2Array = PackedVector2Array()
		for i: int in range(0,current.size(),2):
			var value: Vector2 = current[i]
			if i+1<current.size():
				value = Vector2(minf(value.x,current[i+1].x),maxf(value.y,current[i+1].y))
			next.append(value)
		levels.append(next)
		current = next
	decoder.stop()
	decoder = null
	set_process(false)

func draw_wave(target: Control, rect: Rect2, from: float, until: float, color: Color) -> void:
	if levels.is_empty() or until<=from or rect.size.x<=0.0:
		return
	var per_pixel: float = (until-from)*_rate/BLOCK/rect.size.x
	var level: int = clampi(int(floor(log(maxf(1.0,per_pixel))/log(2.0))),0,levels.size()-1)
	var peaks: PackedVector2Array = levels[level]
	var seconds_per_peak: float = BLOCK*pow(2.0,level)/_rate
	var lines: PackedVector2Array = PackedVector2Array()
	for x: int in range(int(rect.size.x)):
		var time: float = from+(until-from)*float(x)/rect.size.x
		if time<0.0:
			continue
		var index: int = int(time/seconds_per_peak)
		if index>=peaks.size():
			break
		var peak: Vector2 = peaks[index]
		lines.append(rect.position+Vector2(x,rect.size.y*(0.5-peak.y*0.46)))
		lines.append(rect.position+Vector2(x,rect.size.y*(0.5-peak.x*0.46)))
	if not lines.is_empty():
		target.draw_multiline(lines,color,1.0)
