class_name ResultBoard3D
extends Node3D
## 常驻统计结算装置（SOUP 记账台）：记录整场 S/O/U/P 累计。
## 平时实时显示；整场结束时做"老虎机"滚动演算 + 记账留言判词 + "再开一局"按钮。
## 响应掀桌（shake_flip）。数据与演出解耦，无尽模式可直接复用。
##
## S(Standard)=达标局数 O(Overshoot)=爆牌数 U(Underdo)=欠火数 P(Poison)=下料数
## 颜色：S=金 O=白 U=暗灰 P=毒绿
## 平时待机暗屏（只看到模型）+ 随机闪屏故障；整场结束才点亮演算。

signal replay_pressed
signal quit_pressed

const SOUP_COLORS: Array[Color] = [
	Color(1.0, 0.82, 0.2),
	Color(0.95, 0.95, 0.95),
	Color(0.5, 0.5, 0.52),
	Color(0.35, 0.9, 0.4),
]

var _digits: Array[Label3D] = []      # 4 列数字
var _letters: Array[Label3D] = []     # 4 列字母铭牌
var _columns: Array[Node3D] = []      # 4 列（含字母+数字）
var _verdict: Label3D = null          # 记账留言（判词）
var _replay_btn: Button3D = null      # 再开一局
var _quit_btn: Button3D = null        # 退出（回主菜单）
var _audio: AudioStreamPlayer
var _lamp_mat: StandardMaterial3D = null  # 顶部红色指示灯材质
var _hint: Label3D = null                 # 计分规则悬停提示（红灯上方）
var _hover_area: Area3D = null            # 装置悬停检测区
var _ambient_timer: Timer = null      # 待机随机故障定时器
var _cur := [0, 0, 0, 0]              # 当前统计值（S/O/U/P）
var _lit := false                     # 是否已点亮（结算演算）
const GLYPHS := "0123456789#@$%&*=!"


func _ready() -> void:
	_build()
	_start_ambient_glitch()


func _build() -> void:
	# 底座（黑铁盒，呼应手机立牌/空罐）
	var base := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(1.4, 0.34, 0.62)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.08, 0.08, 0.1)
	bm.emission_enabled = true
	bm.emission = Color(0.05, 0.05, 0.08)
	bm.metallic = 0.8
	bm.roughness = 0.5
	base.mesh = b
	base.material_override = bm
	base.position = Vector3(0, 0.17, 0)
	add_child(base)

	# 背板（账本立屏）
	var back := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(1.4, 0.95, 0.05)
	var bkm := StandardMaterial3D.new()
	bkm.albedo_color = Color(0.03, 0.03, 0.05)
	bkm.emission_enabled = true
	bkm.emission = Color(0.02, 0.02, 0.04)
	back.mesh = bb
	back.material_override = bkm
	back.position = Vector3(0, 0.78, -0.05)
	add_child(back)

	# 顶部红色指示灯（待机"要坏"时随闪，点亮时亮）
	var lamp := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.16, 0.1, 0.1)
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.9, 0.1, 0.05)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(0.35, 0.08, 0.04)
	lamp.mesh = lb
	lamp.material_override = _lamp_mat
	lamp.position = Vector3(0, 1.26, -0.02)
	add_child(lamp)

	# 底座两侧支撑块（机器脚）
	for side in [-1.0, 1.0]:
		var foot := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(0.16, 0.16, 0.5)
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.05, 0.05, 0.07)
		fm.metallic = 0.8
		fm.roughness = 0.6
		foot.mesh = fb
		foot.material_override = fm
		foot.position = Vector3(side * 0.68, 0.06, -0.06)
		add_child(foot)

	# 4 列 S/O/U/P（常驻实时显示）
	var letters := ["S", "O", "U", "P"]
	for i in 4:
		var col := Node3D.new()
		col.position = Vector3((i - 1.5) * 0.3, 0.8, 0.06)
		var lt := Label3D.new()
		lt.text = letters[i]
		lt.font_size = 50
		lt.pixel_size = 0.0018
		lt.modulate = SOUP_COLORS[i]
		lt.outline_size = 6
		lt.outline_modulate = Color(0, 0, 0, 0.8)
		lt.position = Vector3(0, 0.24, 0)
		col.add_child(lt)
		_letters.append(lt)
		var dig := Label3D.new()
		dig.text = "0"
		dig.font_size = 72
		dig.pixel_size = 0.002
		dig.modulate = Color(0.2, 0.2, 0.22)   # 待机暗屏
		dig.outline_size = 5
		dig.outline_modulate = Color(0, 0, 0, 0.8)
		dig.position = Vector3(0, 0.0, 0.02)
		col.add_child(dig)
		add_child(col)
		_columns.append(col)
		_digits.append(dig)

	# 记账留言板（判词，默认隐藏）
	_verdict = Label3D.new()
	_verdict.font_size = 30
	_verdict.pixel_size = 0.002
	_verdict.modulate = Color(1, 0.25, 0.2)
	_verdict.outline_size = 6
	_verdict.outline_modulate = Color(0, 0, 0, 0.85)
	_verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_verdict.position = Vector3(0, 0.45, 0.08)
	_verdict.visible = false
	add_child(_verdict)

	# 再开一局按钮（面朝 +Y，放装置前方地面）
	_replay_btn = Button3D.new()
	_replay_btn.setup("再开一局", "回到模式选择", Color(0.4, 0.8, 0.4))
	_replay_btn.position = Vector3(0.5, 0.2, 0.85)
	_replay_btn.visible = false
	_replay_btn.pressed.connect(func() -> void: replay_pressed.emit())
	add_child(_replay_btn)

	_quit_btn = Button3D.new()
	_quit_btn.setup("退出", "回到主菜单", Color(0.62, 0.32, 0.32))
	_quit_btn.position = Vector3(-0.5, 0.2, 0.85)
	_quit_btn.visible = false
	_quit_btn.pressed.connect(func() -> void: quit_pressed.emit())
	add_child(_quit_btn)

	# 程序化音效
	_audio = AudioStreamPlayer.new()
	add_child(_audio)

	# 计分规则悬停提示（红灯正上方，结算时鼠标靠近显示小字）
	_hint = Label3D.new()
	_hint.font_size = 30
	_hint.pixel_size = 0.0018
	_hint.modulate = Color(0.95, 0.85, 0.6)
	_hint.outline_size = 6
	_hint.outline_modulate = Color(0, 0, 0, 0.85)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.text = "S 火候正好：总分 18~21 的达标局数\nO 过火：爆牌局数（>21）\nU 欠火：总分不足 18 的局数\nP 下毒：特殊日下料次数"
	_hint.position = Vector3(0, 1.62, 0.05)
	_hint.visible = false
	add_child(_hint)

	# 悬停检测区（覆盖装置本体；仅结算点亮后鼠标靠近才显示提示）
	_hover_area = Area3D.new()
	var hs := BoxShape3D.new()
	hs.size = Vector3(1.5, 1.4, 0.4)
	var hcol := CollisionShape3D.new()
	hcol.shape = hs
	hcol.position = Vector3(0, 0.7, 0)
	_hover_area.add_child(hcol)
	_hover_area.mouse_entered.connect(func() -> void:
		if _lit:
			_hint.visible = true)
	_hover_area.mouse_exited.connect(func() -> void: _hint.visible = false)
	add_child(_hover_area)

	# 默认待机暗屏（只看到模型，不显示统计）
	_render_standby()


## 更新累计值（后台计算）。未点亮前只记数值不显示（结算才点亮）。
func refresh(score: int, orders: int, unused: int, poison: int) -> void:
	_cur = [score, orders, unused, poison]
	if _lit:
		for i in 4:
			_digits[i].text = str(_cur[i])


## 整场结束：逐列"老虎机"滚动演算到最终值，每列落定回调 on_land
func spin_reveal(score: int, orders: int, unused: int, poison: int, on_land: Callable = Callable()) -> void:
	_cur = [score, orders, unused, poison]
	# 点亮前：先来一段强故障（像旧监视器开机信号不稳）
	_do_glitch(0.5, 1.0)
	_lit = true
	var targets := [score, orders, unused, poison]
	for i in 4:
		_columns[i].visible = true
		_letters[i].modulate = SOUP_COLORS[i]
		_digits[i].modulate = _digit_color(i)
		_play_tick()
		await _spin_one(_digits[i], targets[i])
		if on_land.is_valid():
			on_land.call(i)
	_render_lit()


## 单列滚动：先高频乱跳，再定格到目标
func _spin_one(dig: Label3D, target: int) -> void:
	var tw := create_tween()
	var hi := maxi(9, target * 2)
	for s in 10:
		var rv := randi_range(0, hi)
		tw.tween_callback(func() -> void: dig.text = str(rv))
		tw.tween_interval(0.05)
	tw.tween_callback(func() -> void: dig.text = str(target))
	tw.tween_interval(0.12)
	await tw.finished


## 记账留言判词（含综合评级）
func show_verdict(win: bool, judge: String = "") -> void:
	var head := "国王裁决：%s" % ("胜出" if win else "落败")
	var final_text := (head + "\n" + judge) if judge != "" else head
	_verdict.modulate = Color(1.0, 0.85, 0.3) if win else Color(1.0, 0.28, 0.2)
	_verdict.visible = true
	var tw := create_tween()
	# 裁决"变形"：先乱码闪现，再落定 + 水平抖动
	for i in 5:
		tw.tween_callback(func() -> void:
			_verdict.text = GLYPHS[randi_range(0, GLYPHS.length() - 1)].repeat(randi_range(6, 12)))
		tw.tween_interval(0.05)
	tw.tween_callback(func() -> void: _verdict.text = final_text)
	tw.tween_property(_verdict, "position:y", 0.6, 0.4)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_verdict, "position:x", 0.07, 0.07)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_verdict, "position:x", -0.07, 0.07)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_verdict, "position:x", 0.0, 0.07)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(_verdict, "modulate:a", 1.0, 0.2)


func hide_verdict() -> void:
	_verdict.visible = false


## 结算结束：装置回到待机暗屏（下局不再点亮），并隐藏悬停提示
func reset_standby() -> void:
	_lit = false
	_hint.visible = false
	_render_standby()


func show_replay_button() -> void:
	_replay_btn.visible = true
	_replay_btn.set_enabled(true)
	_quit_btn.visible = true
	_quit_btn.set_enabled(true)


func hide_replay_button() -> void:
	_replay_btn.visible = false
	_quit_btn.visible = false


## 掀桌响应：装置被震得发颤（记录留档，空罐则被卷走）
func shake_flip() -> void:
	var tw := create_tween()
	tw.tween_property(self, "rotation_degrees:z", 8.0, 0.12)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "rotation_degrees:z", -6.0, 0.12)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "rotation_degrees:z", 0.0, 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for dig in _digits:
		var fw := create_tween().set_loops(3)
		fw.tween_property(dig, "modulate:a", 0.3, 0.08)
		fw.tween_property(dig, "modulate:a", 1.0, 0.08)
		fw.chain().tween_callback(func() -> void: dig.modulate.a = 1.0)


## 程序化一声"咔哒"（拨号音，凑近音效）
func _play_tick() -> void:
	if _audio.stream == null:
		_audio.stream = _make_tick()
	_audio.pitch_scale = randf_range(0.95, 1.05)
	_audio.play()


func _make_tick() -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * 0.12)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 45.0)
		var v := sin(TAU * 1320.0 * t) * 0.5 * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


## 待机随机故障：低频不定时触发弱 glitch（营造"要坏掉的旧机器"感）
func _start_ambient_glitch() -> void:
	_ambient_timer = Timer.new()
	_ambient_timer.one_shot = true
	_ambient_timer.timeout.connect(func() -> void:
		if not _lit:
			_do_ambient_flicker()
		_ambient_timer.wait_time = randf_range(1.5, 5.0)
		_ambient_timer.start())
	add_child(_ambient_timer)
	_ambient_timer.wait_time = randf_range(1.5, 5.0)
	_ambient_timer.start()


## 故障：数字屏闪乱码 + 变色 + 轻微位移，结束按状态还原
func _do_glitch(dur: float, strength: float) -> void:
	var tw := create_tween()
	var frames := maxi(1, int(dur / 0.05))
	var base_x := position.x
	for i in frames:
		tw.tween_callback(func() -> void:
			for d in _digits:
				d.text = _rand_glyph()
				d.modulate = _glitch_color()
			position.x = base_x + randf_range(-0.05, 0.05) * strength)
		tw.tween_interval(0.05)
	tw.tween_callback(func() -> void:
		position.x = base_x
		_render_cur())


## 待机"供电不稳"：数字屏暗/微亮间歇闪烁（仿只剩一电池的手机），不闪乱码
func _do_ambient_flicker() -> void:
	var on := Color(0.42, 0.42, 0.46)
	var off := Color(0.12, 0.12, 0.13)
	var base_x := position.x
	var tw := create_tween()
	# 快闪两下 -> 停一拍 -> 再闪两下（配轻抖）
	for seg in 2:
		for i in 2:
			tw.tween_callback(func() -> void:
				for d in _digits:
					d.modulate = on
				if _lamp_mat != null:
					_lamp_mat.emission = Color(1.0, 0.25, 0.1)
				position.x = base_x + randf_range(-0.03, 0.03))
			tw.tween_interval(0.06)
			tw.tween_callback(func() -> void:
				for d in _digits:
					d.modulate = off
				if _lamp_mat != null:
					_lamp_mat.emission = Color(0.25, 0.06, 0.03))
			tw.tween_interval(0.06)
		tw.tween_interval(0.7)
	tw.tween_callback(func() -> void:
		position.x = base_x
		_render_cur())


## 渲染当前状态：点亮/待机
func _render_cur() -> void:
	if _lit:
		_render_lit()
	else:
		_render_standby()


func _render_lit() -> void:
	for i in 4:
		_letters[i].modulate = SOUP_COLORS[i]
		_digits[i].text = str(_cur[i])
		_digits[i].modulate = _digit_color(i)
	if _lamp_mat != null:
		_lamp_mat.emission = Color(1.0, 0.3, 0.12)


func _render_standby() -> void:
	for i in 4:
		_letters[i].modulate = SOUP_COLORS[i].darkened(0.72)
		_digits[i].text = "0"
		_digits[i].modulate = Color(0.2, 0.2, 0.22)
	if _lamp_mat != null:
		_lamp_mat.emission = Color(0.3, 0.07, 0.03)


func _digit_color(i: int) -> Color:
	return Color(0.95, 0.95, 0.95) if i != 2 else Color(0.6, 0.6, 0.62)


func _rand_glyph() -> String:
	return GLYPHS[randi_range(0, GLYPHS.length() - 1)]


func _glitch_color() -> Color:
	match randi_range(0, 3):
		0:
			return Color(0.3, 0.9, 0.9)
		1:
			return Color(0.9, 0.3, 0.9)
		2:
			return Color(0.9, 0.9, 0.2)
		_:
			return Color(0.9, 0.4, 0.2)
