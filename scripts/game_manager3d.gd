extends Node
## 皇家厨房：决斗餐桌 —— 3D 版（多局制 + 保留/跳过 + 3D 交互 + 视觉小说）。
## 规则：牌池 1~10 各 1 张(10张)；达标区间 18~21；双方各 4 命(灯泡)；开局各明牌 1 张；
##       加料抽牌后选"保留"(计入总分)或"跳过"(牌背占槽不计分)；铃铛开牌(仅玩家)；
##       AI 只看自身总分逼近 21；爆牌先小对话再结算；AI 思考随机 ≤6s。

const BUST_LIMIT := 21
const KING_MIN := 18
const MAX_CARDS := 5
const START_LIVES := 4
const AI_THINK_MAX := 6.0

const AI_TAUNTS: Array[String] = [
	"再加一把，让这锅更滚烫……",
	"呵，你这道菜还不够火候。",
	"国王更偏爱我的配方。",
	"加料！加料！满上满上！",
	"你以为你赢定了？天真。",
]

enum Side { PLAYER, AI }
enum State { TUTORIAL, PLAYER_TURN, AI_TURN, GAME_OVER }
enum Phase { IDLE, DECIDE }  # 玩家回合内：IDLE=选抽牌/开牌，DECIDE=决定保留/跳过

# ---- 3D 场景节点 ----
var _camera: Camera3D
var _light: DirectionalLight3D
var _player_slots: Array[CardSlot3D] = []
var _ai_slots: Array[CardSlot3D] = []
var _player_phone: ScoreDisplay3D
var _ai_phone: ScoreDisplay3D
var _draw_btn: Button3D
var _keep_btn: Button3D
var _skip_btn: Button3D
var _bell: Bell3D
# 桌边小剧场（方块角色）
var _king_char: Node3D
var _ai_char: Node3D
var _player_char: Node3D

# ---- 2D UI（悬浮层）----
var _root: Control
var _vn_panel: PanelContainer
var _vn_text: Label
var _vn_portrait: Label
var _vn_button: Button
var _tut_next: Button  # 教程"了解"
var _deck_label: Label

# ---- 教程状态 ----
var _tut_step := 0
var _tut_demo_tw: Tween = null
var _highlight_ring: Node3D = null
var _dim_nodes: Array = []  # 教程降暗的所有可交互节点

# ---- 游戏状态 ----
var card_pool: Array[int] = []
var player_points := 0
var ai_points := 0
var player_lives := START_LIVES
var ai_lives := START_LIVES
var state := State.PLAYER_TURN
var phase := Phase.IDLE
var _pending_value := 0
var _pending_slot: CardSlot3D = null
var _ai_timer: Timer
var _busy := false  # 发牌动画输入锁


func _ready() -> void:
	_build_3d()
	_build_ui()
	_ai_timer = Timer.new()
	_ai_timer.one_shot = true
	_ai_timer.timeout.connect(_on_ai_turn_timeout)
	add_child(_ai_timer)
	_start_tutorial()


# ============================================================
#  3D 场景构建
# ============================================================
func _build_3d() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.04, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.36, 0.45)
	env.ambient_light_energy = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	_light = DirectionalLight3D.new()
	_light.rotation_degrees = Vector3(-50, 25, 0)
	_light.light_energy = 1.3
	_light.shadow_enabled = true
	_light.directional_shadow_max_distance = 40.0
	add_child(_light)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.position = Vector3(0.5, 2.9, 4.8)
	_camera.fov = 62.0
	add_child(_camera)
	_camera.look_at(Vector3(0, 0.0, -0.2))

	# 桌面
	var table := MeshInstance3D.new()
	var tbox := BoxMesh.new()
	tbox.size = Vector3(4.6, 0.15, 3.6)
	table.mesh = tbox
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.11, 0.065, 0.05)
	table.material_override = tmat
	table.position = Vector3(0, -0.075, 0)
	add_child(table)

	# 卡槽（AI 红/Z=-1.1，玩家绿/Z=+1.1）
	for i in MAX_CARDS:
		var x := (i - 2) * 0.7
		var ai_slot := CardSlot3D.new()
		ai_slot.glow_color = Color(0.9, 0.3, 0.3)
		ai_slot.position = Vector3(x, 0, -1.1)
		add_child(ai_slot)
		_ai_slots.append(ai_slot)

		var p_slot := CardSlot3D.new()
		p_slot.glow_color = Color(0.3, 0.9, 0.3)
		p_slot.position = Vector3(x, 0, 1.1)
		add_child(p_slot)
		_player_slots.append(p_slot)

	# 总分"手机"立牌（竖立，面朝玩家；屏幕上总分 + 电量格命数）
	_ai_phone = ScoreDisplay3D.new()
	_ai_phone.position = Vector3(-2.0, 0, -1.5)
	add_child(_ai_phone)
	_player_phone = ScoreDisplay3D.new()
	_player_phone.position = Vector3(2.0, 0, 1.5)
	add_child(_player_phone)

	# 桌边小剧场：方块角色（国王金 / 红队红 / 玩家绿）
	_king_char = _make_char(Color(0.95, 0.78, 0.2), "国王", Vector3(0, 0, -1.7))
	_ai_char = _make_char(Color(0.85, 0.25, 0.25), "红队", Vector3(-2.3, 0, -0.4))
	_player_char = _make_char(Color(0.3, 0.8, 0.35), "你", Vector3(2.3, 0, -0.4))

	# ---- 3D 交互控件 ----
	_draw_btn = Button3D.new()
	_draw_btn.setup("加料", "抽 1 张牌", Color(0.4, 0.8, 0.4))
	_draw_btn.position = Vector3(-1.05, 0.15, 2.3)
	_draw_btn.pressed.connect(_on_draw)
	add_child(_draw_btn)

	_keep_btn = Button3D.new()
	_keep_btn.setup("保留", "计入总分", Color(0.4, 0.8, 0.4))
	_keep_btn.position = Vector3(-0.55, 0.15, 2.3)
	_keep_btn.pressed.connect(_on_keep)
	_keep_btn.visible = false
	add_child(_keep_btn)

	_skip_btn = Button3D.new()
	_skip_btn.setup("跳过", "弃牌·占槽", Color(0.8, 0.5, 0.3))
	_skip_btn.position = Vector3(0.55, 0.15, 2.3)
	_skip_btn.pressed.connect(_on_skip)
	_skip_btn.visible = false
	add_child(_skip_btn)

	_bell = Bell3D.new()
	_bell.position = Vector3(1.05, 0.15, 2.3)
	_bell.pressed.connect(_on_bell)
	add_child(_bell)

	# 教程高亮光环（默认隐藏）
	_highlight_ring = _make_ring()
	add_child(_highlight_ring)
	_highlight_ring.visible = false

	# 收集所有可降暗的交互节点（教程高亮用）
	for s in _player_slots:
		_dim_nodes.append(s)
	for s in _ai_slots:
		_dim_nodes.append(s)
	_dim_nodes.append(_player_phone)
	_dim_nodes.append(_ai_phone)
	_dim_nodes.append(_draw_btn)
	_dim_nodes.append(_keep_btn)
	_dim_nodes.append(_skip_btn)
	_dim_nodes.append(_bell)


## 构建一个方块角色（身体 + 头部 + 名牌）
func _make_char(color: Color, name_text: String, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos

	var body := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.7, 0.9, 0.5)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = color
	bm.emission_enabled = true
	bm.emission = color
	body.mesh = b
	body.material_override = bm
	body.position.y = 0.45
	root.add_child(body)

	var head := MeshInstance3D.new()
	var h := BoxMesh.new()
	h.size = Vector3(0.42, 0.42, 0.42)
	var hm := StandardMaterial3D.new()
	hm.albedo_color = color.lightened(0.25)
	hm.emission_enabled = true
	hm.emission = color.lightened(0.25)
	head.mesh = h
	head.material_override = hm
	head.position.y = 1.11
	root.add_child(head)

	var label := Label3D.new()
	label.text = name_text
	label.font_size = 44
	label.pixel_size = 0.0022
	label.modulate = Color(1, 1, 1)
	label.position = Vector3(0, 1.5, 0)
	root.add_child(label)

	# 记录演出所需的材质与基准高度
	root.set_meta("char_mats", [bm, hm])
	root.set_meta("char_base_y", pos.y)
	return root


## 角色演出：说话时发光增强 + 轻微抬起（其余角色变暗回落）
func _set_char_talk(char: Node3D, on: bool) -> void:
	if char == null:
		return
	var mats: Array = char.get_meta("char_mats", [])
	for m in mats:
		m.emission_energy_multiplier = 3.0 if on else 1.0
	var base: float = char.get_meta("char_base_y", 0.0)
	var tw := char.create_tween()
	tw.tween_property(char, "position:y", base + (0.12 if on else 0.0), 0.2)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 依据 VN 说话者，点亮对应角色演出
func _update_char_talk(speaker: String) -> void:
	_set_char_talk(_king_char, speaker == "国王")
	_set_char_talk(_ai_char, speaker == "红队")
	_set_char_talk(_player_char, speaker == "你")


func _char_for(speaker: String) -> Node3D:
	match speaker:
		"国王":
			return _king_char
		"红队":
			return _ai_char
		"你":
			return _player_char
	return null


## 在说话角色上方弹出 3D 对话气泡：飘起 + 淡出 + 消失
func _spawn_speech(speaker: String, text: String) -> void:
	var char := _char_for(speaker)
	if char == null:
		return
	var lab := Label3D.new()
	lab.text = text
	lab.font_size = 30
	lab.pixel_size = 0.0018
	lab.modulate = Color(1, 1, 1)
	lab.outline_size = 8
	lab.outline_modulate = Color(0, 0, 0, 0.85)
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position = Vector3(0, 1.9, 0)
	char.add_child(lab)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lab, "position:y", 2.6, 2.4)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lab, "modulate:a", 0.0, 0.8).set_delay(1.6)
	tw.chain().tween_callback(lab.queue_free)


## 构建教程高亮光环（平放圆环，自发光）
func _make_ring() -> Node3D:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.62
	torus.outer_radius = 0.72
	torus.rings = 32
	torus.ring_segments = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.2)
	mat.emission_energy_multiplier = 2.0
	mesh.mesh = torus
	mesh.material_override = mat
	root.add_child(mesh)
	return root

# ============================================================
#  2D 悬浮层 UI
# ============================================================
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)

	# 标题
	var title := Label.new()
	title.text = "皇家厨房 · 决斗餐桌"
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 6
	title.offset_bottom = 34
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.78, 0.4))
	_root.add_child(title)

	# 牌池计数（右上）
	_deck_label = Label.new()
	_deck_label.text = "牌池 10 / 10"
	_deck_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_deck_label.offset_left = -190
	_deck_label.offset_top = 44
	_deck_label.offset_right = -24
	_deck_label.offset_bottom = 68
	_deck_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_deck_label.add_theme_font_size_override("font_size", 16)
	_deck_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.5))
	_root.add_child(_deck_label)

	# ---- VN 面板（顶部中央）----
	_vn_panel = PanelContainer.new()
	_vn_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_vn_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_vn_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_vn_panel.offset_left = -300
	_vn_panel.offset_top = 44
	_vn_panel.offset_right = 300
	_vn_panel.offset_bottom = 196
	var vn_style := StyleBoxFlat.new()
	vn_style.bg_color = Color(0.04, 0.04, 0.06, 0.92)
	vn_style.border_color = Color(0.8, 0.6, 0.25)
	vn_style.set_border_width_all(2)
	vn_style.set_corner_radius_all(10)
	vn_style.content_margin_left = 16
	vn_style.content_margin_right = 16
	vn_style.content_margin_top = 10
	vn_style.content_margin_bottom = 10
	_vn_panel.add_theme_stylebox_override("panel", vn_style)
	_vn_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_vn_panel)

	var vn_vbox := VBoxContainer.new()
	vn_vbox.add_theme_constant_override("separation", 6)
	_vn_panel.add_child(vn_vbox)

	var portrait_row := HBoxContainer.new()
	portrait_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vn_vbox.add_child(portrait_row)
	_vn_portrait = Label.new()
	_vn_portrait.text = "国王"
	_vn_portrait.add_theme_font_size_override("font_size", 22)
	_vn_portrait.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	portrait_row.add_child(_vn_portrait)

	_vn_text = Label.new()
	_vn_text.custom_minimum_size = Vector2(540, 0)
	_vn_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vn_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vn_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_vn_text.add_theme_font_size_override("font_size", 18)
	_vn_text.add_theme_color_override("font_color", Color(1.0, 0.95, 0.82))
	vn_vbox.add_child(_vn_text)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vn_vbox.add_child(btn_row)

	_tut_next = Button.new()
	_tut_next.text = "了解"
	_tut_next.custom_minimum_size = Vector2(150, 42)
	_tut_next.add_theme_font_size_override("font_size", 18)
	_tut_next.pressed.connect(_tut_advance)
	_tut_next.visible = false
	btn_row.add_child(_tut_next)

	_vn_button = Button.new()
	_vn_button.text = "下一局"
	_vn_button.custom_minimum_size = Vector2(170, 42)
	_vn_button.add_theme_font_size_override("font_size", 18)
	_vn_button.pressed.connect(_on_vn_button_pressed)
	_vn_button.visible = false
	btn_row.add_child(_vn_button)


# ============================================================
#  对局流程
# ============================================================
# ============================================================
#  教程（分步引导，首次启动）
# ============================================================
const TUT_STEPS := 6

func _start_tutorial() -> void:
	state = State.TUTORIAL
	_tut_step = 0
	_tut_show_step()


## "了解"按钮：进入下一步
func _tut_advance() -> void:
	if state != State.TUTORIAL:
		return
	_tut_kill_demo()
	_tut_step += 1
	if _tut_step >= TUT_STEPS:
		_start_match()
	else:
		_tut_show_step()


func _tut_show_step() -> void:
	_tut_next.visible = true
	_tut_next.text = "开始游戏" if _tut_step == TUT_STEPS - 1 else "了解"
	match _tut_step:
		0:
			_tut_highlight(_bell)
			_vn_button.text = "跳过教程，直接开始"
			_vn_button.visible = true
			show_vn("国王", "这是开牌用的铃铛。敲响它，双方亮牌比大小、决出胜负。觉得都会了，可直接跳过教程开始游戏。")
		1:
			_tut_highlight(_player_phone)
			_vn_button.visible = false
			_tut_run_demo(1)
			show_vn("国王", "手机显示你的总分。目标是 18~21 分且大于对方：18 分以上亮金色，超过 21 会爆红。")
		2:
			_tut_highlight(_player_phone)
			_vn_button.visible = false
			_tut_run_demo(2)
			show_vn("国王", "超过 21 就爆牌，不足 18 也赢不了。失败会扣掉手机上的电量格。")
		3:
			_tut_highlight(_player_phone)
			_vn_button.visible = false
			_tut_run_demo(3)
			show_vn("国王", "每输一局扣一格电量；4 格全灭就输掉整场。只有点「重来」才会重新点亮电量格。")
		4:
			_tut_highlight(_draw_btn)
			_vn_button.visible = false
			show_vn("你", "加料按钮：抽一张牌，再决定「保留」（计入总分）或「跳过」（弃牌，占用一格）。")
		5:
			_tut_clear_highlight()
			_vn_button.visible = false
			show_vn("国王", "规则都明白了吗？点「开始游戏」，开启你的皇家晚宴。")
		_:
			pass


## 高亮目标：光环 + 其余降暗
func _tut_highlight(target: Node3D) -> void:
	if _highlight_ring == null or target == null:
		return
	_highlight_ring.position = target.global_position + Vector3(0, 0.8, 0)
	_highlight_ring.visible = true
	_tut_dim_all(target)


func _tut_clear_highlight() -> void:
	if _highlight_ring != null:
		_highlight_ring.visible = false
	_tut_dim_all(null)


func _tut_dim_all(except_node: Node3D) -> void:
	for n in _dim_nodes:
		if n == null:
			continue
		var dim: bool = except_node != null and n != except_node
		n.set_dim(dim)


## 演示动画（一次性清晰序列：怎么赢 / 失败扣血 / 重新亮电；不循环，避免"自主回血"感）
func _tut_run_demo(step: int) -> void:
	_tut_kill_demo()
	var tw := create_tween()
	match step:
		1:
			tw.tween_callback(func() -> void: _player_phone.set_points(19))
			tw.tween_interval(0.8)
			tw.tween_callback(func() -> void: _player_phone.set_points(21))
			tw.tween_interval(0.8)
			tw.tween_callback(func() -> void: _player_phone.set_points(15))
		2:
			tw.tween_callback(func() -> void: _player_phone.set_points(22))
			tw.tween_callback(func() -> void: _player_phone.set_lives(3))
		3:
			tw.tween_callback(func() -> void: _player_phone.set_lives(3))
			tw.tween_interval(0.5)
			tw.tween_callback(func() -> void: _player_phone.set_lives(2))
			tw.tween_interval(0.5)
			tw.tween_callback(func() -> void: _player_phone.set_lives(1))
			tw.tween_interval(0.5)
			tw.tween_callback(func() -> void: _player_phone.set_lives(0))
			tw.tween_interval(0.7)
			tw.tween_callback(func() -> void: _player_phone.set_lives(4))
	_tut_demo_tw = tw


func _tut_kill_demo() -> void:
	if _tut_demo_tw != null:
		_tut_demo_tw.kill()
		_tut_demo_tw = null


## 整场开始/重来：重置双方生命，再开第一局
func _start_match() -> void:
	_tut_kill_demo()
	_tut_clear_highlight()
	player_lives = START_LIVES
	ai_lives = START_LIVES
	_update_lives()
	_start_round()


## 开始一局（保留整场生命与灯泡）
func _start_round() -> void:
	_ai_timer.stop()
	_busy = false
	card_pool = []
	for v in range(1, 11):
		card_pool.append(v)
	player_points = 0
	ai_points = 0
	state = State.PLAYER_TURN
	phase = Phase.IDLE
	for s in _player_slots:
		s.reset()
	for s in _ai_slots:
		s.reset()
	_vn_button.visible = false
	_tut_next.visible = false
	_deck_label.text = "牌池 %d / 10" % card_pool.size()
	_player_phone.set_points(0)
	_ai_phone.set_points(0)
	_update_lives()
	_update_buttons()
	_deal_opening()


## 开局：双方各发 1 张明牌
func _deal_opening() -> void:
	var pv := _draw_from_pool()
	var ps := _next_empty(_player_slots)
	player_points = pv
	_busy = true
	await _spawn_deal(ps, pv)
	if ps.card3d != null:
		ps.card3d.reveal()
	_busy = false
	_update_scores()

	var av := _draw_from_pool()
	var asl := _next_empty(_ai_slots)
	ai_points = av
	_busy = true
	await _spawn_deal(asl, av)
	if asl.card3d != null:
		asl.card3d.reveal()
	_busy = false
	_update_scores()
	show_vn("国王", "开局明牌：你 %d，红队 %d。目标 18~21。轮到你了：加料 或 铃铛开牌。" % [pv, av])
	_start_player_turn()


func _draw_from_pool() -> int:
	var idx := randi_range(0, card_pool.size() - 1)
	var v := card_pool[idx]
	card_pool.remove_at(idx)
	_deck_label.text = "牌池 %d / 10" % card_pool.size()
	return v


## 创建 3D 卡牌，从发牌源交给动画器飞入目标槽（落地牌背朝上）
func _spawn_deal(slot: CardSlot3D, value: int) -> void:
	var card := Card3D.new()
	card.setup(value)
	add_child(card)
	card.position = _deal_source()
	card.rotation_degrees.x = 180.0
	CardAnimator3D.play_deal(card, slot, value)
	await CardAnimator3D.deal_finished


## 玩家：加料（抽 1 张，看到后决定保留/跳过）
func _on_draw() -> void:
	if state != State.PLAYER_TURN or phase != Phase.IDLE or _busy:
		return
	if _slots_full(_player_slots):
		show_vn("提示", "你的槽位已满，只能开牌。")
		return
	if card_pool.is_empty():
		show_vn("提示", "牌池已空，只能开牌。")
		return
	var v := _draw_from_pool()
	var slot := _next_empty(_player_slots)
	_pending_value = v
	_pending_slot = slot
	_busy = true
	_update_buttons()
	await _spawn_deal(slot, v)
	# 翻开给自己看（决定保留/跳过）
	if slot.card3d != null:
		slot.card3d.reveal()
	_busy = false
	phase = Phase.DECIDE
	_update_buttons()
	show_vn("你", "你抽到 %d。保留（计入总分）还是跳过（弃牌·占用一格）？" % v)


## 玩家：保留（计入总分）
func _on_keep() -> void:
	if state != State.PLAYER_TURN or phase != Phase.DECIDE or _busy:
		return
	player_points += _pending_value
	_update_scores()
	if player_points > BUST_LIMIT:
		show_vn("你", "你保留 %d，总分 %d —— 手抖了一下，香料撒多了！" % [_pending_value, player_points])
		await get_tree().create_timer(0.9).timeout
		_resolve()
		return
	_start_ai_turn()


## 玩家：跳过（弃牌，牌背占槽不计分）
func _on_skip() -> void:
	if state != State.PLAYER_TURN or phase != Phase.DECIDE or _busy:
		return
	_pending_slot.set_skipped(true)
	if _pending_slot.card3d != null:
		_pending_slot.card3d.set_orientation(false, true)
	show_vn("你", "你弃置了一张牌（%d 不计入，占用 1 格）。" % _pending_value)
	await get_tree().create_timer(0.6).timeout
	_start_ai_turn()


## 玩家：铃铛开牌
func _on_bell() -> void:
	if state != State.PLAYER_TURN or phase != Phase.IDLE or _busy:
		return
	_resolve()


func _start_ai_turn() -> void:
	state = State.AI_TURN
	phase = Phase.IDLE
	_update_buttons()
	_ai_timer.start(randf_range(0.5, AI_THINK_MAX))
	show_vn("红队", "红队思考中……（加料 / 开牌）")


func _on_ai_turn_timeout() -> void:
	if state != State.AI_TURN:
		return
	var decision := AIController.decide_draw(ai_points, card_pool.size(), _slots_full(_ai_slots))
	if decision == "stand":
		show_vn("红队", "红队：%s（开牌）" % _rand_taunt())
		await get_tree().create_timer(0.4).timeout
		_resolve()
		return
	if _slots_full(_ai_slots) or card_pool.is_empty():
		await get_tree().create_timer(0.3).timeout
		_resolve()
		return
	var v := _draw_from_pool()
	var slot := _next_empty(_ai_slots)
	_busy = true
	await _spawn_deal(slot, v)
	_busy = false
	# AI 看自己的牌，决定保留/跳过
	var keep := AIController.decide_keep(ai_points, v)
	if keep:
		ai_points += v
		if slot.card3d != null:
			slot.card3d.reveal()
		_update_scores()
		if ai_points > BUST_LIMIT:
			show_vn("红队", "红队抽到 +%d，总分 %d —— 它端不稳汤锅，爆了！" % [v, ai_points])
			await get_tree().create_timer(0.8).timeout
			_resolve()
			return
		_start_player_turn()
	else:
		slot.set_skipped(true)
		if slot.card3d != null:
			slot.card3d.set_orientation(false, true)
		show_vn("红队", "红队弃置了一张牌（+%d 不计入）。" % v)
		await get_tree().create_timer(0.6).timeout
		_start_player_turn()


func _start_player_turn() -> void:
	state = State.PLAYER_TURN
	phase = Phase.IDLE
	_update_buttons()
	show_vn("你", "轮到你了。总分 %d：加料（抽牌）或 铃铛（开牌）。" % player_points)


func _rand_taunt() -> String:
	return AI_TAUNTS[randi_range(0, AI_TAUNTS.size() - 1)]


func _update_scores() -> void:
	_player_phone.set_points(player_points)
	_ai_phone.set_points(ai_points)


## 依据 state 与 phase 设置 3D 交互控件的可见/可点
func _update_buttons() -> void:
	var player_turn := state == State.PLAYER_TURN
	var deciding := player_turn and phase == Phase.DECIDE
	var can_act := player_turn and not deciding and not _busy

	_draw_btn.visible = can_act
	_draw_btn.set_enabled(can_act and not _slots_full(_player_slots) and not card_pool.is_empty())

	_keep_btn.visible = deciding
	_keep_btn.set_enabled(deciding and not _busy)
	_skip_btn.visible = deciding
	_skip_btn.set_enabled(deciding and not _busy)

	_bell.visible = can_act
	_bell.set_enabled(can_act)


# ============================================================
#  结算
# ============================================================
func _resolve() -> void:
	state = State.GAME_OVER
	phase = Phase.IDLE
	_ai_timer.stop()
	_update_buttons()
	_vn_button.visible = true

	# 结算：保留(明牌)保持翻开；跳过的保持牌背 + ✕，不强制翻开（体现"弃牌"）
	var p_ok := player_points >= KING_MIN and player_points <= BUST_LIMIT
	var a_ok := ai_points >= KING_MIN and ai_points <= BUST_LIMIT
	var result := ""
	if not p_ok and not a_ok:
		result = "draw"
	elif p_ok and not a_ok:
		result = "player"
	elif not p_ok and a_ok:
		result = "ai"
	elif player_points > ai_points:
		result = "player"
	elif ai_points > player_points:
		result = "ai"
	else:
		result = "draw"

	var msg := ""
	var portrait := "国王"
	if result == "player":
		msg = "你以 %d 点（18~21）博得国王欢心！红队（%d 点）被扔进汤锅。你赢了本局！" % [player_points, ai_points]
		portrait = "你"
	elif result == "ai":
		msg = "红队以 %d 点胜出。你的 %d 点没能赢得青睐……你输了本局。" % [ai_points, player_points]
		portrait = "红队"
	else:
		msg = "双方均未达标（或平局），国王拂袖而去，重上一道菜。（你 %d / 红队 %d）" % [player_points, ai_points]
		portrait = "国王"

	# 电量格：本局失败方扣 1 格（平局双方都不扣）
	var match_over := false
	if result == "player":
		ai_lives = maxi(0, ai_lives - 1)
		msg += "\n红队电量 -1（剩余 %d）。" % ai_lives
		if ai_lives <= 0:
			match_over = true
			msg += "\n红队电量尽失，你赢下整场盛宴！"
	elif result == "ai":
		player_lives = maxi(0, player_lives - 1)
		msg += "\n你电量 -1（剩余 %d）。" % player_lives
		if player_lives <= 0:
			match_over = true
			msg += "\n你的电量尽失，红队赢下整场盛宴！"
	_update_lives()

	_vn_button.text = "重来" if match_over else "下一局"
	show_vn(portrait, msg)


## VN 面板按钮：教程中=跳过教程；整场结束=重来；否则下一局
func _on_vn_button_pressed() -> void:
	if state == State.TUTORIAL:
		_start_match()
		return
	if player_lives <= 0 or ai_lives <= 0:
		_start_match()
	else:
		_start_round()


func _update_lives() -> void:
	if _player_phone != null:
		_player_phone.set_lives(player_lives)
	if _ai_phone != null:
		_ai_phone.set_lives(ai_lives)


func show_vn(portrait: String, text: String) -> void:
	_vn_portrait.text = portrait
	_vn_text.text = text
	_vn_panel.visible = true
	_update_char_talk(portrait)
	_spawn_speech(portrait, text)


# ============================================================
#  槽位辅助
# ============================================================
func _slots_full(slots: Array[CardSlot3D]) -> bool:
	for s in slots:
		if s.is_empty():
			return false
	return true


func _next_empty(slots: Array[CardSlot3D]) -> CardSlot3D:
	for s in slots:
		if s.is_empty():
			return s
	return slots[0]


func _deal_source() -> Vector3:
	return Vector3(0, 4.0, 0.4)
