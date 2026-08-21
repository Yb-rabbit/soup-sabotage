extends Node3D
## Savage Odds: Ultimate Punishment —— 主菜单。
## 黑暗工业风 + 压抑赌徒心理：蒸汽大锅背景 + 血红破碎标题 + 生锈警报启动按钮。
## 项目无音频/字体素材，全部音效程序化合成；入场/退出均有戏剧性演出。

const GAME_SCENE := "res://main.tscn"

@onready var _cam: Camera3D = $Camera3D
@onready var _glow: OmniLight3D = $Background/GlowLight
@onready var _steam: GPUParticles3D = $Background/Steam
@onready var _title: Label = $CanvasLayer/MenuRoot/TitleLabel
@onready var _subtitle: Label = $CanvasLayer/MenuRoot/SubtitleLabel
@onready var _soup: Label = $CanvasLayer/MenuRoot/SoupGhost
@onready var _start: Button = $CanvasLayer/MenuRoot/StartButton
@onready var _black: ColorRect = $CanvasLayer/MenuRoot/BlackScreen
@onready var _flash: ColorRect = $CanvasLayer/MenuRoot/RedFlash
@onready var _shutter_l: ColorRect = $CanvasLayer/MenuRoot/ShutterLeft
@onready var _shutter_r: ColorRect = $CanvasLayer/MenuRoot/ShutterRight

var _title_base_x := 0.0
var _title_base_y := 0.0
var _idle_pulse := 0.0
var _started := false

var _sfx_steam: AudioStream
var _sfx_metal: AudioStream
var _sfx_click: AudioStream
var _sfx_hover: AudioStream
var _sfx_boil: AudioStream
var _audio_player: AudioStreamPlayer   # 一次性音效
var _boil_player: AudioStreamPlayer    # 沸腾循环（切场景前）


func _ready() -> void:
	_build_audio()
	_start.mouse_entered.connect(_on_start_mouse_entered)
	_start.mouse_exited.connect(_on_start_mouse_exited)
	_start.pressed.connect(_on_start_button_pressed)
	_title_base_x = _title.position.x
	_title_base_y = _title.position.y
	# 初始隐藏：全黑、标题/副标题/彩蛋透明、快门关闭、闪红透明
	_black.color = Color.BLACK
	_title.modulate.a = 0.0
	_subtitle.modulate.a = 0.0
	_soup.modulate.a = 0.0
	_flash.modulate.a = 0.0
	_shutter_l.modulate.a = 0.0
	_shutter_r.modulate.a = 0.0
	_start.disabled = true
	_play_intro()


# ============ 入场演出 ============
func _play_intro() -> void:
	await get_tree().create_timer(0.4).timeout
	# 蒸汽泄压声 + 背景蒸汽显现 + 黑幕淡出
	_play(_sfx_steam)
	_steam.emitting = true
	var tw := create_tween()
	tw.tween_property(_black, "color:a", 0.0, 1.2)
	await tw.finished
	# 标题随金属撞击砸入 + 镜头震动
	_play(_sfx_metal)
	_title.modulate.a = 1.0
	_title.position.y = get_viewport().get_visible_rect().size.y * 2.0
	var t2 := create_tween()
	t2.tween_property(_title, "position:y", _title_base_y, 0.35)\
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await t2.finished
	_shake_camera()
	# 副标题 + 蒸汽 S.O.U.P. 彩蛋淡入
	var t3 := create_tween()
	t3.set_parallel(true)
	t3.tween_property(_subtitle, "modulate:a", 1.0, 0.6)
	t3.tween_property(_soup, "modulate:a", 0.4, 1.5)
	_start.disabled = false
	_idle_pulse = TAU


func _process(delta: float) -> void:
	if _started:
		return
	# 标题轻微颤抖（模拟痛苦嘶吼），使用基准点避免漂移出画面
	_title.position.x = _title_base_x + randf_range(-1.2, 1.2)
	_title.rotation_degrees = randf_range(-0.4, 0.4)
	# 按钮呼吸脉冲（Idle 状态弱红光脉动）
	_idle_pulse = wrapf(_idle_pulse + delta * 2.2, 0.0, TAU)
	var pulse: float = 0.5 + 0.5 * sin(_idle_pulse)
	if _start.is_hovered():
		_start.modulate = Color(1, 1, 1, 1)
	else:
		_start.modulate = Color(1, 1.0 - 0.35 * pulse, 1.0 - 0.35 * pulse, 1.0)
	# 锅底火光闪烁
	_glow.light_energy = 1.3 + 0.6 * sin(_idle_pulse * 3.0) + randf_range(-0.15, 0.15)


# ============ 按钮交互 ============
func _on_start_mouse_entered() -> void:
	if _started:
		return
	_play(_sfx_hover)            # 电流滋滋
	_start.scale = Vector2(1.05, 1.05)


func _on_start_mouse_exited() -> void:
	_start.scale = Vector2.ONE


func _on_start_button_pressed() -> void:
	if _started:
		return
	_started = true
	_start.disabled = true
	_play(_sfx_click)
	# 按钮下沉 + 屏幕猛闪红
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_start, "scale", Vector2(0.9, 0.9), 0.1)
	tw.tween_property(_flash, "color:a", 1.0, 0.08)
	await tw.finished
	tw = create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.25)
	await tw.finished
	_close_shutter()


# 快门闭合（黑幕两侧向中间合拢）+ 沸腾声 + 切场景
func _close_shutter() -> void:
	_shutter_l.modulate.a = 1.0
	_shutter_r.modulate.a = 1.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_shutter_l, "anchor_right", 0.5, 0.55)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_shutter_r, "anchor_left", 0.5, 0.55)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	_play_loop(_sfx_boil)         # 音效切换为游戏内沸腾声
	await get_tree().create_timer(0.35).timeout
	get_tree().change_scene_to_file(GAME_SCENE)


# ============ 镜头震动 ============
func _shake_camera() -> void:
	var base := _cam.position
	for i in 8:
		_cam.position = base + Vector3(randf_range(-0.12, 0.12), randf_range(-0.12, 0.12), 0)
		await get_tree().create_timer(0.03).timeout
	_cam.position = base


# ============ 程序化音效 ============
func _build_audio() -> void:
	_sfx_steam = _make_noise(1.6, 0.5, 0.15, true)      # 蒸汽泄压（低频噪声）
	_sfx_metal = _make_impulse(0.4, 0.85, 85.0)         # 金属撞击
	_sfx_click = _make_impulse(0.09, 0.6, 160.0)        # 按钮咔哒
	_sfx_hover = _make_noise(0.18, 0.35, 0.5, false)    # 电流滋滋
	_sfx_boil = _make_noise(2.0, 0.45, 0.22, false, true)  # 沸腾循环
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)
	_boil_player = AudioStreamPlayer.new()
	add_child(_boil_player)


func _play(stream: AudioStream) -> void:
	_audio_player.stream = stream
	_audio_player.play()


func _play_loop(stream: AudioStream) -> void:
	_boil_player.stream = stream
	_boil_player.play()


# 低通白噪声：cutoff∈(0,1) 越小越闷；fade_out 尾部淡出；loop 开启循环
func _make_noise(duration: float, vol: float, cutoff: float, fade_out: bool, loop := false) -> AudioStreamWAV:
	var rate := 22050
	var n := int(duration * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var s_in := randf_range(-1.0, 1.0)
		lp += cutoff * (s_in - lp)
		var env := 1.0 - float(i) / n if fade_out else 1.0
		var v := lp * vol * env
		var s := int(clampf(v * 32767.0, -32768.0, 32767.0))
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	wav.data = data
	return wav


# 指数衰减低频音（撞击/咔哒）
func _make_impulse(duration: float, vol: float, freq: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(duration * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 14.0)
		var v := sin(TAU * freq * t) * vol * env
		var s := int(clampf(v * 32767.0, -32768.0, 32767.0))
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav

	_sfx_steam = _make_noise(1.6, 0.5, 0.15, true)      # 蒸汽泄压（低频噪声）
	_sfx_metal = _make_impulse(0.4, 0.85, 85.0)         # 金属撞击
	_sfx_click = _make_impulse(0.09, 0.6, 160.0)        # 按钮咔哒
	_sfx_hover = _make_noise(0.18, 0.35, 0.5, false)    # 电流滋滋
	_sfx_boil = _make_noise(2.0, 0.45, 0.22, false, true)  # 沸腾循环
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)
	_boil_player = AudioStreamPlayer.new()
	add_child(_boil_player)
