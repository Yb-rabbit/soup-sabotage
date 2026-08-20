class_name Bell3D
extends Node3D
## 共用铃铛：若干白色方块错落堆叠成"铃铛"造型，Area3D 点击触发开牌。
## 含 enabled 状态（置灰不可点）与屏幕同步提示信息。

signal pressed

var enabled := true
var title := "铃铛"
var subtitle := "开牌 · 结束回合"

var _mats: Array[StandardMaterial3D] = []
var _base := Color(0.92, 0.92, 0.95)
var _hovering := false
var _hover_tw: Tween = null
var _hover_base_y := 0.0
var _audio: AudioStreamPlayer


func _ready() -> void:
	_build()
	_setup_sound()


func _setup_sound() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.stream = _make_bell_tone()
	add_child(_audio)


## 程序合成一声"叮"（正弦叠加 + 快速衰减包络）
func _make_bell_tone() -> AudioStreamWAV:
	var rate := 44100
	var dur := 0.35
	var frames := int(rate * dur)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / rate
		var env := exp(-7.0 * t)
		var s := sin(TAU * 880.0 * t) * 0.6 + sin(TAU * 1320.0 * t) * 0.3
		var v := int(clamp(s * env * 0.5, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


func play_sound() -> void:
	if _audio != null:
		_audio.pitch_scale = randf_range(0.95, 1.05)
		_audio.play()


func _build() -> void:
	# 大块（钟身）+ 小块（铃锤）叠放，简单轮廓
	var big := MeshInstance3D.new()
	var b1 := BoxMesh.new()
	b1.size = Vector3(0.5, 0.4, 0.5)
	var big_mat := _make_white()
	big.mesh = b1
	big.material_override = big_mat
	big.position = Vector3(0, 0.2, 0)
	add_child(big)
	_mats.append(big_mat)

	var small := MeshInstance3D.new()
	var b2 := BoxMesh.new()
	b2.size = Vector3(0.22, 0.18, 0.22)
	var sm_mat := _make_white()
	small.mesh = b2
	small.material_override = sm_mat
	small.position = Vector3(0, 0.5, 0)
	add_child(small)
	_mats.append(sm_mat)

	# 交互
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 0.62, 0.6)
	shape.shape = bs
	shape.position = Vector3(0, 0.28, 0)
	area.add_child(shape)
	area.input_event.connect(_on_input_event)
	area.mouse_entered.connect(func() -> void: set_hover(true))
	area.mouse_exited.connect(func() -> void: set_hover(false))
	add_child(area)


func _make_white() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = _base
	m.emission_enabled = true
	m.emission = _base
	return m


func set_enabled(e: bool) -> void:
	enabled = e
	if _mats.is_empty():
		return
	for m in _mats:
		if e:
			m.emission_enabled = true
			m.albedo_color = _base
			m.emission = _base
		else:
			m.emission_enabled = false
			m.albedo_color = Color(0.22, 0.22, 0.24)


## 高亮时降暗（教程用）
func set_dim(d: bool) -> void:
	for m in _mats:
		m.emission_energy_multiplier = 0.15 if d else 1.0


func set_hover(h: bool) -> void:
	if h == _hovering:
		return
	_hovering = h
	if _hover_tw != null:
		_hover_tw.kill()
	if h:
		_hover_base_y = position.y  # 记录固定基准，避免位置累积漂移
	var target_y := _hover_base_y + (0.04 if h else 0.0)
	_hover_tw = create_tween()
	_hover_tw.set_parallel(true)
	_hover_tw.tween_property(self, "position:y", target_y, 0.15)
	for m in _mats:
		_hover_tw.tween_property(m, "emission_energy_multiplier", 2.0 if h else 1.0, 0.15)


func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int) -> void:
	if enabled and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		play_sound()
