extends Node
## 皇家厨房：决斗餐桌 —— 3D 版（多局制 + 保留/跳过 + 3D 交互 + 视觉小说）。
## 规则：牌池 1~13 各 1 张(13张)；达标区间 18~21；双方各 4 命(灯泡)；开局各明牌 1 张；
##       加料抽牌后选"保留"(计入总分)或"跳过"(牌背占槽不计分)；铃铛开牌(仅玩家)；
##       AI 只看自身总分逼近 21；爆牌先小对话再结算；AI 思考随机 ≤6s。

const BUST_LIMIT := 21
const KING_MIN := 18
const MAX_CARDS := 5
const START_LIVES := 4
const AI_THINK_MAX := 6.0
const USE_SETTLE_CAM := false  # 结算闪切镜头暂不启用（true 时走运镜序列）
const SPECIAL_DAY_CHANCE := 0.4  # 出现特殊日（怀旧节/新鲜日）的概率；其余为普通日
const DRAW_PENALTY_AT := 3  # 连续平局达此阈值触发“国王掀桌子”（双方各扣 1 命）

const AI_TAUNTS: Array[String] = [
	"再加一把，让这锅更滚烫……",
	"呵，你这道菜还不够火候。",
	"国王更偏爱我的配方。",
	"加料！加料！满上满上！",
	"你以为你赢定了？天真。",
]

enum Side { PLAYER, AI }
enum Ingredient { EXPIRED, REFINED, NONE }  # 怀旧节（被计入者扣命） / 新鲜日（被计入者回命） / NONE=普通日（无特殊料）
enum State { TUTORIAL, PLAYER_TURN, AI_TURN, GAME_OVER }
enum Phase { IDLE, DECIDE, MARK }  # 玩家回合内：IDLE=选抽牌/开牌，DECIDE=决定保留/跳过，MARK=选标记料

# ---- 3D 场景节点 ----
var _camera: Camera3D
var _light: DirectionalLight3D
var _table: MeshInstance3D
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
var _day_chip: PanelContainer
var _day_chip_label: Label
var _day_chip_style: StyleBoxFlat
var _block_label: Label
var _menu: Control                 # 进入过渡黑屏遮罩（原内置“开始”菜单已废除，消除二重验证）

# ---- 教程状态 ----
var _tut_step := 0
var _tut_demo_tw: Tween = null
var _highlight_ring: Node3D = null
var _ring_tw: Tween = null  # 高亮光环上下浮动动效
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
var _consecutive_draws := 0  # 连续平局计数（达阈值触发掀桌子）

# ---- 过期料/精制料 ----
var round_ingredient := Ingredient.EXPIRED  # 本局料种（每局重置）
var player_mark_value := 0  # 玩家标记的牌值（0=未标）
var ai_mark_value := 0      # AI 标记的牌值（0=未标）
var _pick_bar: HBoxContainer
var _pick_buttons: Array[Button] = []
var _partic_bar: HBoxContainer
var _partic_buttons: Array[Button] = []
var _mode_bar: HBoxContainer
var _mode_buttons: Array[Button] = []
var _blind_mode := false     # 盲选模式开关
var _blind_unlocked := false # 通关（整场胜利一次）后解锁盲选

# ---- 镜头演出 ----
var _cam_tw: Tween = null
var _cam_seq_token := 0
var _banner_label: Label3D = null
var _banner_tw: Tween = null
var _cam_home_pos := Vector3(0.5, 2.9, 4.8)
var _cam_home_look := Vector3(0, 0.0, -0.2)


func _ready() -> void:
	_build_3d()
	_build_ui()
	_ai_timer = Timer.new()
	_ai_timer.one_shot = true
	_ai_timer.timeout.connect(_on_ai_turn_timeout)
	add_child(_ai_timer)
	# 进入后黑屏过渡 → 直接显示模式选择（现行/盲选），不再有内置“开始”菜单（二重验证）
	_play_intro_to_mode()


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
	_table = MeshInstance3D.new()
	var tbox := BoxMesh.new()
	tbox.size = Vector3(4.6, 0.15, 3.6)
	_table.mesh = tbox
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.11, 0.065, 0.05)
	_table.material_override = tmat
	_table.position = Vector3(0, -0.075, 0)
	add_child(_table)

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

	# 桌边小剧场：方块角色已移除（反馈无法看到）；角色变量保持 null，相关演出函数均有 null 保护
	# _king_char = _make_char(Color(0.95, 0.78, 0.2), "国王", Vector3(0, 0, -1.6))
	# _ai_char = _make_char(Color(0.85, 0.25, 0.25), "红队", Vector3(-1.9, 0, -0.5))
	# _player_char = _make_char(Color(0.3, 0.8, 0.35), "你", Vector3(1.9, 0, -0.5))

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
	b.size = Vector3(0.95, 1.15, 0.65)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = color
	bm.emission_enabled = true
	bm.emission = color
	body.mesh = b
	body.material_override = bm
	body.position.y = 0.58
	root.add_child(body)

	var head := MeshInstance3D.new()
	var h := BoxMesh.new()
	h.size = Vector3(0.55, 0.55, 0.55)
	var hm := StandardMaterial3D.new()
	hm.albedo_color = color.lightened(0.25)
	hm.emission_enabled = true
	hm.emission = color.lightened(0.25)
	head.mesh = h
	head.material_override = hm
	head.position.y = 1.45
	root.add_child(head)

	var label := Label3D.new()
	label.text = name_text
	label.font_size = 52
	label.pixel_size = 0.0022
	label.modulate = Color(1, 1, 1)
	label.position = Vector3(0, 1.95, 0)
	root.add_child(label)

	# 记录演出所需的材质与基准高度
	root.set_meta("char_mats", [bm, hm])
	root.set_meta("char_base_y", pos.y)
	return root


## 角色演出：说话时发光增强 + 轻微抬起（其余角色变暗回落）
func _set_char_talk(char: Node3D, on: bool) -> void:
	if char == null:
		return
	_char_kill_tw(char)
	var mats: Array = char.get_meta("char_mats", [])
	for m in mats:
		m.emission_energy_multiplier = 3.0 if on else 1.0
	var base: float = char.get_meta("char_base_y", 0.0)
	var tw := char.create_tween()
	tw.tween_property(char, "position:y", base + (0.12 if on else 0.0), 0.2)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	char.set_meta("char_tw", tw)


func _char_kill_tw(char: Node3D) -> void:
	if not char.has_meta("char_tw"):
		return
	var tw: Tween = char.get_meta("char_tw")
	if tw != null:
		tw.kill()
		char.set_meta("char_tw", null)


## 角色反应演出：talk=发光抬升；hurt=压扁+红闪+下蹲；happy=蹦跳+金光
func _char_react(char: Node3D, type: String) -> void:
	if char == null:
		return
	_char_kill_tw(char)
	var mats: Array = char.get_meta("char_mats", [])
	var base: float = char.get_meta("char_base_y", 0.0)
	var tw := char.create_tween()
	match type:
		"hurt":
			tw.tween_property(char, "scale", Vector3(1.2, 0.68, 1.2), 0.18)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(char, "position:y", base - 0.16, 0.18)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			for m in mats:
				tw.parallel().tween_property(m, "emission_energy_multiplier", 4.0, 0.15)
			tw.tween_property(char, "scale", Vector3.ONE, 0.3)\
				.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(char, "position:y", base, 0.3)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			for m in mats:
				tw.parallel().tween_property(m, "emission_energy_multiplier", 1.0, 0.3)
		"happy":
			tw.tween_property(char, "position:y", base + 0.32, 0.24)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			for m in mats:
				tw.parallel().tween_property(m, "emission_energy_multiplier", 3.5, 0.15)
			tw.tween_property(char, "position:y", base, 0.24)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			for m in mats:
				tw.parallel().tween_property(m, "emission_energy_multiplier", 1.0, 0.2)
		"shock":
			tw.tween_property(char, "position:y", base - 0.1, 0.12)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(char, "scale", Vector3(1.15, 0.85, 1.15), 0.12)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			for m in mats:
				tw.parallel().tween_property(m, "emission_energy_multiplier", 4.5, 0.1)
			tw.tween_property(char, "position:y", base, 0.25)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(char, "scale", Vector3.ONE, 0.25)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			for m in mats:
				tw.parallel().tween_property(m, "emission_energy_multiplier", 1.0, 0.25)
		_:
			for m in mats:
				tw.parallel().tween_property(m, "emission_energy_multiplier", 3.0, 0.2)
			tw.tween_property(char, "position:y", base + 0.12, 0.2)
	char.set_meta("char_tw", tw)


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
	lab.position = Vector3(0, 1.5, 0)
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

	# 标题（隐藏：不显示顶部黄色标题）
	var title := Label.new()
	title.text = "皇家厨房 · 决斗餐桌"
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 6
	title.offset_bottom = 34
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.78, 0.4))
	title.visible = false
	_root.add_child(title)

	# 牌池计数（右上）
	_deck_label = Label.new()
	_deck_label.text = "牌池 13 / 13"
	_deck_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_deck_label.offset_left = -190
	_deck_label.offset_top = 44
	_deck_label.offset_right = -24
	_deck_label.offset_bottom = 68
	_deck_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_deck_label.add_theme_font_size_override("font_size", 16)
	_deck_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.5))
	_root.add_child(_deck_label)

	# 今日料种指示（顶部左侧，闹钟样式，默认隐藏；宽度自适应文本）
	_day_chip = PanelContainer.new()
	_day_chip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_day_chip.grow_horizontal = Control.GROW_DIRECTION_END
	_day_chip.grow_vertical = Control.GROW_DIRECTION_END
	_day_chip.offset_left = 24
	_day_chip.offset_top = 44
	_day_chip_style = StyleBoxFlat.new()
	_day_chip_style.bg_color = Color(0.04, 0.04, 0.06, 0.9)
	_day_chip_style.set_border_width_all(2)
	_day_chip_style.set_corner_radius_all(8)
	_day_chip_style.content_margin_left = 10
	_day_chip_style.content_margin_right = 10
	_day_chip_style.content_margin_top = 6
	_day_chip_style.content_margin_bottom = 6
	_day_chip.add_theme_stylebox_override("panel", _day_chip_style)
	_day_chip.visible = false
	_root.add_child(_day_chip)

	_day_chip_label = Label.new()
	_day_chip_label.add_theme_font_size_override("font_size", 15)
	_day_chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_day_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_day_chip.add_child(_day_chip_label)

	# ---- VN 面板（顶部中央）----
	_vn_panel = PanelContainer.new()
	_vn_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_vn_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_vn_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_vn_panel.offset_left = -300
	_vn_panel.offset_top = 40
	_vn_panel.offset_right = 300
	_vn_panel.offset_bottom = 268
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
	vn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
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
	_tut_next.custom_minimum_size = Vector2(160, 46)
	_tut_next.add_theme_font_size_override("font_size", 18)
	_tut_next.pressed.connect(_tut_advance)
	_tut_next.visible = false
	btn_row.add_child(_tut_next)

	_vn_button = Button.new()
	_vn_button.text = "下一局"
	_vn_button.custom_minimum_size = Vector2(210, 46)
	_vn_button.add_theme_font_size_override("font_size", 18)
	_vn_button.pressed.connect(_on_vn_button_pressed)
	_vn_button.visible = false
	btn_row.add_child(_vn_button)

	# ---- 料种选择条（开局选标记牌，默认隐藏）----
	_pick_bar = HBoxContainer.new()
	_pick_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_pick_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pick_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_pick_bar.offset_left = -360
	_pick_bar.offset_top = -100
	_pick_bar.offset_right = 360
	_pick_bar.offset_bottom = -24
	_pick_bar.add_theme_constant_override("separation", 8)
	_pick_bar.visible = false
	_root.add_child(_pick_bar)
	for v in range(1, 14):
		var b := Button.new()
		b.text = str(v)
		b.custom_minimum_size = Vector2(46, 46)
		b.add_theme_font_size_override("font_size", 18)
		b.set_meta("mark_val", v)
		b.pressed.connect(_on_mark_pick.bind(v))
		_pick_bar.add_child(b)
		_pick_buttons.append(b)

	# ---- 参与/不参与（和平交易）选择条（特殊日，默认隐藏）----
	_partic_bar = HBoxContainer.new()
	_partic_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_partic_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_partic_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_partic_bar.offset_left = -320
	_partic_bar.offset_top = -100
	_partic_bar.offset_right = 320
	_partic_bar.offset_bottom = -24
	_partic_bar.add_theme_constant_override("separation", 16)
	_partic_bar.visible = false
	_root.add_child(_partic_bar)
	var b_in := Button.new()
	b_in.text = "参与料效"
	b_in.custom_minimum_size = Vector2(200, 50)
	b_in.add_theme_font_size_override("font_size", 18)
	b_in.pressed.connect(_on_participate.bind(true))
	_partic_bar.add_child(b_in)
	_partic_buttons.append(b_in)
	var b_out := Button.new()
	b_out.text = "不参与（和平交易）"
	b_out.custom_minimum_size = Vector2(220, 50)
	b_out.add_theme_font_size_override("font_size", 18)
	b_out.pressed.connect(_on_participate.bind(false))
	_partic_bar.add_child(b_out)
	_partic_buttons.append(b_out)

	# ---- 模式选择条（现行/盲选，通关后解锁，默认隐藏）----
	_mode_bar = HBoxContainer.new()
	_mode_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_mode_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_mode_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_mode_bar.offset_left = -300
	_mode_bar.offset_top = -100
	_mode_bar.offset_right = 300
	_mode_bar.offset_bottom = -24
	_mode_bar.add_theme_constant_override("separation", 16)
	_mode_bar.visible = false
	_root.add_child(_mode_bar)
	var b_cur := Button.new()
	b_cur.text = "现行模式"
	b_cur.custom_minimum_size = Vector2(200, 50)
	b_cur.add_theme_font_size_override("font_size", 18)
	b_cur.pressed.connect(_on_mode_select.bind(false))
	_mode_bar.add_child(b_cur)
	_mode_buttons.append(b_cur)
	var b_blind := Button.new()
	b_blind.text = "盲选模式"
	b_blind.custom_minimum_size = Vector2(200, 50)
	b_blind.add_theme_font_size_override("font_size", 18)
	b_blind.pressed.connect(_on_mode_select.bind(true))
	_mode_bar.add_child(b_blind)
	_mode_buttons.append(b_blind)

	# “挡”无效提示（点击对方牌时）
	_block_label = Label.new()
	_block_label.text = "喂！那是对方的牌"
	_block_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_block_label.add_theme_font_size_override("font_size", 40)
	_block_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	_block_label.visible = false
	_root.add_child(_block_label)

	# ---- 进入过渡：黑屏遮罩（代替原内置“开始”菜单，消除二重验证）----
	_menu = ColorRect.new()
	_menu.color = Color(0, 0, 0, 1)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_menu)


## 进入过渡：黑屏短暂停留 → 淡出 → 直接显示模式选择（现行/盲选）
func _play_intro_to_mode() -> void:
	if _tut_next != null:
		_tut_next.visible = false
	if _vn_button != null:
		_vn_button.visible = false
	if _vn_panel != null:
		_vn_panel.visible = false
	await get_tree().create_timer(0.4).timeout
	if _menu != null:
		var tw := create_tween()
		tw.tween_property(_menu, "color:a", 0.0, 0.9)
		await tw.finished
	_start_tutorial()


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
	if _day_chip != null:
		_day_chip.visible = false
	_tut_show_step()


## "了解"按钮：进入下一步
func _tut_advance() -> void:
	if state != State.TUTORIAL:
		return
	_tut_kill_demo()
	_tut_step += 1
	if _tut_step >= TUT_STEPS:
		_show_mode_select_flow()
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
			show_vn("侍从", "欢迎来到皇家厨房！桌上这个铃铛是「开牌」：轮到你时敲响它，双方立刻亮牌比大小、决胜负。先点「了解」继续看看怎么算分。")
		1:
			_tut_highlight(_player_phone)
			_vn_button.visible = false
			_tut_run_demo(1)
			show_vn("侍从", "计分器显示你的总分，目标是 18~21 分且比对方大。你看：达到 18 会亮起金色，逼近 21 是最佳状态。")
		2:
			_tut_highlight(_player_phone)
			_vn_button.visible = false
			_tut_run_demo(2)
			show_vn("侍从", "但要小心！总分超过 21 会爆牌直接判负，不足 18 同样不算赢。所以拿牌、加多少料，都得盘算好。")
		3:
			_tut_highlight(_player_phone)
			_vn_button.visible = false
			_tut_run_demo(3)
			show_vn("侍从", "每输一局，手机上的电量会扣一格。一共 4 格，全灭就输掉整场——只有点「重来」才能重新点亮。")
		4:
			_tut_highlight(_draw_btn)
			_vn_button.visible = false
			show_vn("你", "轮到我就按「加料」抽一张牌，再看情况选「保留」（计入总分）或「跳过」（弃牌、占一格）。控制好点数别爆啦。")
		5:
			_tut_clear_highlight()
			_vn_button.visible = false
			show_vn("侍从", "规则都懂了吧？点「开始游戏」，选个模式，开启你的皇家晚宴。")
		_:
			pass


## 高亮目标：光环 + 其余降暗
func _tut_highlight(target: Node3D) -> void:
	if _highlight_ring == null or target == null:
		return
	_highlight_ring.position = target.global_position + Vector3(0, 0.8, 0)
	_highlight_ring.visible = true
	_tut_dim_all(target)
	# 上下浮动动效
	if _ring_tw != null:
		_ring_tw.kill()
	var base_y := _highlight_ring.position.y
	var rtw := create_tween()
	rtw.set_loops()
	rtw.tween_property(_highlight_ring, "position:y", base_y + 0.15, 0.6)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	rtw.tween_property(_highlight_ring, "position:y", base_y - 0.15, 0.6)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_ring_tw = rtw


func _tut_clear_highlight() -> void:
	if _ring_tw != null:
		_ring_tw.kill()
		_ring_tw = null
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
	_consecutive_draws = 0
	_update_lives()
	_start_round()


## 开始一局（保留整场生命与灯泡）
func _start_round() -> void:
	_ai_timer.stop()
	_busy = false
	round_ingredient = Ingredient.NONE
	if randf() < SPECIAL_DAY_CHANCE:
		round_ingredient = Ingredient.EXPIRED if randf() < 0.5 else Ingredient.REFINED
	player_mark_value = 0
	ai_mark_value = 0
	_hide_pick_bar()
	_hide_participate_bar()
	_hide_mode_bar()
	if round_ingredient == Ingredient.NONE:
		if _day_chip != null:
			_day_chip.visible = false
	else:
		_update_day_chip()
	card_pool = []
	for v in range(1, 14):
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
	_deck_label.text = "牌池 %d / 13" % card_pool.size()
	_player_phone.set_points(0)
	_ai_phone.set_points(0)
	_update_lives()
	_update_buttons()
	_cam_player_push()  # 每局开始强制复位到玩家机位，避免结算后镜头滞留
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
	show_vn("国王", "开局明牌：你 %d，红队 %d。目标 18~21。" % [pv, av])
	if round_ingredient == Ingredient.NONE:
		_start_player_turn()
	else:
		_start_marking()


func _draw_from_pool() -> int:
	var idx := randi_range(0, card_pool.size() - 1)
	var v := card_pool[idx]
	card_pool.remove_at(idx)
	_deck_label.text = "牌池 %d / 13" % card_pool.size()
	return v


## 创建 3D 卡牌，从发牌源交给动画器飞入目标槽（落地牌背朝上）
func _spawn_deal(slot: CardSlot3D, value: int) -> void:
	var card := Card3D.new()
	card.setup(value)
	card.own = not _ai_slots.has(slot)  # 我方牌
	card.invalid_clicked.connect(_on_card_invalid)
	add_child(card)
	card.position = _deal_source()
	card.rotation_degrees.x = 180.0
	CardAnimator3D.play_deal(card, slot, value)
	await CardAnimator3D.deal_finished


## 开局选标记牌：国王钦定本局料种后，双方各自暗选一张牌
func _start_marking() -> void:
	state = State.PLAYER_TURN
	phase = Phase.MARK
	# AI 暗中决定：参与（暗选一张牌）或不参与（和平交易）
	ai_mark_value = AIController.decide_mark(int(round_ingredient), card_pool, ai_points)
	_show_participate_bar()
	_update_buttons()
	var nm := _ing_name(round_ingredient)
	show_vn("国王", "今日是【%s】——%s。特许你「暗选」一张牌，还是「放弃」？算入总点数才生效：%s）" % [nm, _ing_note(), _ing_effect()])


func _on_mark_pick(v: int) -> void:
	if state != State.PLAYER_TURN or phase != Phase.MARK:
		return
	player_mark_value = v
	phase = Phase.IDLE
	_hide_participate_bar()
	_hide_pick_bar()
	_update_buttons()
	_start_player_turn()


func _show_pick_bar() -> void:
	if _pick_bar == null:
		return
	_pick_bar.visible = true
	for b in _pick_buttons:
		var val: int = b.get_meta("mark_val")
		b.disabled = not card_pool.has(val)


func _hide_pick_bar() -> void:
	if _pick_bar != null:
		_pick_bar.visible = false


## 特殊日：玩家选择“参与”（暗选一张牌）或“不参与（和平交易）”
func _on_participate(join: bool) -> void:
	if state != State.PLAYER_TURN or phase != Phase.MARK:
		return
	if join:
		_hide_participate_bar()
		_show_pick_bar()
		show_vn("密语", "选一张牌作为%s（牌仍留在牌池，若最终被算入总点数才生效：%s）。" % [_ing_name(round_ingredient), _ing_effect()])
	else:
		player_mark_value = 0
		phase = Phase.IDLE
		_hide_participate_bar()
		_hide_pick_bar()
		_update_buttons()
		_start_player_turn()


func _show_participate_bar() -> void:
	if _partic_bar == null:
		return
	_partic_bar.visible = true


func _hide_participate_bar() -> void:
	if _partic_bar != null:
		_partic_bar.visible = false


## 显示模式选择前：西红柿方块抛物砸屏闪屏开场
func _show_mode_select_flow() -> void:
	await _play_tomato_splash()
	_show_mode_bar()


## 西红柿方块：从远处抛物逼近 → 砸中屏幕（闪红+震屏）→ 下降退场
func _play_tomato_splash() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.12, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.2, 0.12)
	mat.emission_energy_multiplier = 1.4
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.9, 0.9)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = Vector3(0, 6.5, 13)
	mesh.scale = Vector3(0.12, 0.12, 0.12)
	add_child(mesh)
	var flash := ColorRect.new()
	flash.color = Color(1, 0, 0, 0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(flash)
	# 抛物逼近（远处 → 砸到面前，同时放大）
	var tw := create_tween()
	tw.tween_property(mesh, "position", Vector3(0, 3.0, 2.6), 0.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(mesh, "scale", Vector3(2.4, 2.4, 2.4), 0.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	# 砸中：闪红 + 震屏
	var ftw := create_tween()
	ftw.tween_property(flash, "color:a", 0.9, 0.06)
	ftw.tween_property(flash, "color:a", 0.0, 0.3)
	_camera_shake_burst(0.4)
	# 下降退场
	var dtw := create_tween()
	dtw.tween_property(mesh, "position:y", -2.2, 0.35)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	dtw.parallel().tween_property(mesh, "position:z", 1.2, 0.35)
	dtw.parallel().tween_property(mesh, "scale", Vector3(0.3, 0.3, 0.3), 0.35)
	await dtw.finished
	mesh.queue_free()
	await get_tree().create_timer(0.15).timeout
	flash.queue_free()


## 短促相机震动
func _camera_shake_burst(amp: float) -> void:
	if _camera == null:
		return
	var base := _camera.position
	var tw := create_tween()
	for i in 6:
		tw.tween_callback(func() -> void:
			_camera.position = base + Vector3(randf_range(-amp, amp), randf_range(-amp, amp), 0))
		tw.tween_interval(0.03)
	tw.tween_callback(func() -> void: _camera.position = base)


## 通关后解锁：新局开头显示“现行/盲选”选择
func _show_mode_bar() -> void:
	if _mode_bar == null:
		_start_match()
		return
	_mode_bar.visible = true
	_vn_button.visible = false


func _hide_mode_bar() -> void:
	if _mode_bar != null:
		_mode_bar.visible = false


func _on_mode_select(blind: bool) -> void:
	_blind_mode = blind
	_hide_mode_bar()
	_start_match()


## 盲选下更新我方牌的“可查看”状态（仅玩家回合）
func _update_peek() -> void:
	for s in _player_slots:
		if s.card3d != null:
			s.card3d.peekable = _blind_mode and state == State.PLAYER_TURN


## 点击对方牌：显示“挡”提示
func _on_card_invalid() -> void:
	if state != State.PLAYER_TURN:
		return
	_show_block()


func _show_block() -> void:
	if _block_label == null:
		return
	_block_label.modulate.a = 1.0
	_block_label.visible = true
	var tw := _block_label.create_tween()
	tw.tween_property(_block_label, "modulate:a", 0.0, 0.5).set_delay(0.4)
	tw.tween_callback(func() -> void: _block_label.visible = false)


func _ing_name(ing: Ingredient) -> String:
	return "怀旧节" if ing == Ingredient.EXPIRED else "新鲜日"


func _ing_effect() -> String:
	return "被计入者多扣一点血" if round_ingredient == Ingredient.EXPIRED else "被计入者回一点血"


func _ing_note() -> String:
	return "陈年过气、混入会倒扣" if round_ingredient == Ingredient.EXPIRED else "现采新鲜、掺入能回血"


## 常驻指示：显示今日料种（闹钟样式，红=怀旧节 / 绿=新鲜日）
func _update_day_chip() -> void:
	if _day_chip_label == null:
		return
	var nm := _ing_name(round_ingredient)
	var color := Color(0.95, 0.3, 0.3) if round_ingredient == Ingredient.EXPIRED else Color(0.3, 0.9, 0.4)
	var note := "有牌料稍含异味" if round_ingredient == Ingredient.EXPIRED else "有牌料鲜美异常"
	_day_chip_label.text = "今日：%s｜%s" % [nm, note]
	_day_chip_label.add_theme_color_override("font_color", color)
	_day_chip_style.border_color = color
	_day_chip.reset_size()  # 按文本实际长度自适应宽高
	_day_chip.visible = true


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
	# 盲选：卡牌贴近摄像机直接看牌面（不弹数字），看完再决定
	if _blind_mode:
		await _blind_draw_view(slot.card3d)
	else:
		if slot.card3d != null:
			slot.card3d.reveal()
	_busy = false
	phase = Phase.DECIDE
	_update_buttons()
	if _blind_mode:
		show_vn("你", "请看这张牌。保留还是跳过？")
	else:
		show_vn("你", "你抽到 %d。保留（计入总分）还是跳过（弃牌·占用一格）？" % v)


## 玩家：保留（计入总分）
func _on_keep() -> void:
	if state != State.PLAYER_TURN or phase != Phase.DECIDE or _busy:
		return
	player_points += _pending_value
	# 盲选：保留的牌平放盖下（暗牌回槽位）
	if _blind_mode and _pending_slot != null and _pending_slot.card3d != null:
		_card_place_down(_pending_slot.card3d)
	_update_scores()
	if player_points > BUST_LIMIT:
		_speak_scene("你", "你保留 %d，总分 %d —— 你超过 21 了！别急着认输，看红队会不会也爆。" % [_pending_value, player_points])
		await get_tree().create_timer(0.8).timeout
	_start_ai_turn()


## 玩家：跳过（弃牌，牌背占槽不计分）
func _on_skip() -> void:
	if state != State.PLAYER_TURN or phase != Phase.DECIDE or _busy:
		return
	_pending_slot.set_skipped(true)
	if _pending_slot.card3d != null:
		_set_discarded(_pending_slot.card3d)
	_speak_scene("你", "你弃置了一张牌（%d 不计入，占用 1 格）。" % _pending_value)
	await get_tree().create_timer(0.6).timeout
	_start_ai_turn()


## 玩家：铃铛开牌
func _on_bell() -> void:
	if state != State.PLAYER_TURN or phase != Phase.IDLE or _busy:
		return
	_bell.ring()
	_resolve()


func _start_ai_turn() -> void:
	state = State.AI_TURN
	phase = Phase.IDLE
	_update_buttons()
	_ai_timer.start(randf_range(0.5, AI_THINK_MAX))
	_cam_push_in()
	_speak_scene("红队", "红队思考中……")


func _on_ai_turn_timeout() -> void:
	if state != State.AI_TURN:
		return
	var decision := AIController.decide_draw(ai_points, card_pool.size(), _slots_full(_ai_slots))
	if decision == "stand":
		_speak_scene("红队", "%s（开牌）" % _rand_taunt())
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
	var keep := AIController.decide_keep(ai_points, v, ai_mark_value, round_ingredient == Ingredient.REFINED)
	if keep:
		ai_points += v
		if not _blind_mode and slot.card3d != null:
			slot.card3d.reveal()
		_update_scores()
		if ai_points > BUST_LIMIT:
			_speak_scene("红队", "红队抽到 +%d，总分 %d —— 它超过 21 了！看你能不能抓住机会。" % [v, ai_points])
			await get_tree().create_timer(0.8).timeout
		_start_player_turn()
	else:
		slot.set_skipped(true)
		if slot.card3d != null:
			_set_discarded(slot.card3d)
		_speak_scene("红队", "红队弃置了一张牌（+%d 不计入）。" % v)
		await get_tree().create_timer(0.6).timeout
		_start_player_turn()


func _start_player_turn() -> void:
	state = State.PLAYER_TURN
	phase = Phase.IDLE
	_update_buttons()
	_cam_player_push()
	show_vn("你", "轮到你了。总分 %d：加料（抽牌）或 铃铛（开牌）。" % player_points)


func _rand_taunt() -> String:
	return AI_TAUNTS[randi_range(0, AI_TAUNTS.size() - 1)]


func _update_scores() -> void:
	if _blind_mode:
		# 盲选：玩家手机=实时总分（暗灰）；AI手机=仅首牌得分（暗灰）
		var ai_first := 0
		for s in _ai_slots:
			if s.occupied and s.card3d != null:
				ai_first = s.card3d.value
				break
		_player_phone.set_points(player_points)
		_ai_phone.set_points(ai_first)
		_player_phone.set_grayed(true)
		_ai_phone.set_grayed(true)
	else:
		_player_phone.set_points(player_points)
		_ai_phone.set_points(ai_points)
		_player_phone.set_grayed(false)
		_ai_phone.set_grayed(false)


## 依据 state 与 phase 设置 3D 交互控件的可见/可点
func _update_buttons() -> void:
	_update_peek()
	var player_turn := state == State.PLAYER_TURN
	var deciding := player_turn and phase == Phase.DECIDE
	var marking := player_turn and phase == Phase.MARK
	var can_act := player_turn and not deciding and not marking and not _busy

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
	var p_bust := player_points > BUST_LIMIT
	var a_bust := ai_points > BUST_LIMIT
	var p_ok := player_points >= KING_MIN and not p_bust
	var a_ok := ai_points >= KING_MIN and not a_bust
	var result := ""
	if p_bust and a_bust:
		# 双爆：更接近 21（总分更低）者胜；同分平局
		if player_points < ai_points:
			result = "player"
		elif ai_points < player_points:
			result = "ai"
		else:
			result = "draw"
	elif p_bust and not a_bust:
		result = "ai"      # 我爆、对方未爆 => 我输
	elif a_bust and not p_bust:
		result = "player"  # 对方爆、我未爆 => 我赢
	elif not p_ok and not a_ok:
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
		if p_bust and a_bust:
			msg = "双方都爆牌了！你（%d 点）比红队（%d 点）更接近 21，算你赢！" % [player_points, ai_points]
		elif a_bust:
			msg = "红队爆牌了（%d 点，超过 21）！你以 %d 点获胜，你过关！" % [ai_points, player_points]
		else:
			msg = "你以 %d 点（18~21）博得国王欢心！对方（%d 点）被扔进汤锅。赢！" % [player_points, ai_points]
		portrait = "你"
	elif result == "ai":
		if p_bust and a_bust:
			msg = "双方都爆了！红队（%d 点）比你（%d 点）更接近 21，输！" % [ai_points, player_points]
		elif p_bust:
			msg = "你爆牌了（%d 点，超过 21）！红队以 %d 点胜出，输！" % [player_points, ai_points]
		else:
			msg = "红队以 %d 点胜出。你的 %d 点没能赢得青睐……输！" % [ai_points, player_points]
		portrait = "红队"
	else:
		if p_bust and a_bust:
			msg = "双方爆牌且同分（%d 点），国王摇头说，这锅坏菜了。" % player_points
		else:
			msg = "双方均未达标（或平局），国王表示菜就多练。（你 %d / 红队 %d）" % [player_points, ai_points]
		portrait = "国王"

	# ---- 过期料/精制料：被计入哪一方的手就影响哪一方 ----
	var p_counted := _counted_values(_player_slots)
	var a_counted := _counted_values(_ai_slots)
	var hit_desc: Array[String] = []
	var processed: Dictionary = {}
	for mv in [player_mark_value, ai_mark_value]:
		if mv == 0 or processed.has(mv):
			continue
		processed[mv] = true
		if p_counted.has(mv):
			_apply_ingredient_life(Side.PLAYER)
			hit_desc.append(_ing_hit_desc(Side.PLAYER, mv))
			_add_pin_marker(_find_card(_player_slots, mv))
		if a_counted.has(mv):
			_apply_ingredient_life(Side.AI)
			hit_desc.append(_ing_hit_desc(Side.AI, mv))
			_add_pin_marker(_find_card(_ai_slots, mv))
	if not hit_desc.is_empty():
		msg += "\n（" + "；".join(hit_desc) + "）"

	# 特殊日：揭示双方参与/不参与
	if round_ingredient != Ingredient.NONE:
		var rp := "你：参与（料 %d）" % player_mark_value if player_mark_value != 0 else "你：不参与（和平交易）"
		var ra := "红队：参与（料 %d）" % ai_mark_value if ai_mark_value != 0 else "红队：不参与（和平交易）"
		msg += "\n%s　%s" % [rp, ra]

	# 电量格：本局失败方扣 1 格（平局双方都不扣）
	var match_over := false
	if result == "player":
		ai_lives = maxi(0, ai_lives - 1)
		msg += "\n红队电量 -1（剩余 %d）。" % ai_lives
	elif result == "ai":
		player_lives = maxi(0, player_lives - 1)
		msg += "\n你电量 -1（剩余 %d）。" % player_lives
	if player_lives <= 0:
		match_over = true
		msg += "\n你的电量尽失，红队赢下整场盛宴！"
	if ai_lives <= 0:
		match_over = true
		msg += "\n红队电量尽失，你赢下整场盛宴！"
		_blind_unlocked = true  # 首次整场胜利解锁盲选模式

	# 连续平局：非平局清零，平局递增；达阈值国王掀桌子（双方各扣 1 命）
	var flip_table := false
	if result == "draw":
		_consecutive_draws += 1
	else:
		_consecutive_draws = 0
	if result == "draw" and _consecutive_draws >= DRAW_PENALTY_AT:
		flip_table = true
		_consecutive_draws = 0
		player_lives = maxi(0, player_lives - 1)
		ai_lives = maxi(0, ai_lives - 1)
		msg += "\n连续平局让国王震怒——他掀了桌子！。"
		if player_lives <= 0:
			match_over = true
			msg += "\n你的电量尽失，红队赢下整场盛宴！"
		if ai_lives <= 0:
			match_over = true
			msg += "\n红队电量尽失，你赢下整场盛宴！"
	_update_lives()

	# 盲选：开牌时才翻开双方保留牌、显示完整总分
	if _blind_mode:
		await _reveal_all_kept()
		_player_phone.set_points(player_points)
		_ai_phone.set_points(ai_points)
		_player_phone.set_grayed(false)
		_ai_phone.set_grayed(false)

	_vn_button.text = "重来" if match_over else "下一局"
	show_vn(portrait, msg)

	# 结算演出（闪切镜头暂不启用）：默认镜头下播角色反应；如需运镜改 USE_SETTLE_CAM=true
	var loser_side: int = Side.PLAYER if result == "ai" else (Side.AI if result == "player" else Side.PLAYER)
	var winner_side: int = Side.PLAYER if result == "player" else (Side.AI if result == "ai" else Side.PLAYER)
	if USE_SETTLE_CAM:
		var shots: Array = []
		shots.append(_phone_shot(loser_side))
		shots.append(_char_shot(loser_side, "hurt"))
		if result != "draw":
			shots.append(_char_shot(winner_side, "happy"))
		_vn_button.disabled = true
		await _play_cam_seq(shots)
		_vn_button.disabled = false
	else:
		var loser_busted := (loser_side == Side.PLAYER and p_bust) or (loser_side == Side.AI and a_bust)
		_char_react(_char_for_side(loser_side), "shock" if loser_busted else "hurt")
		if result != "draw":
			_char_react(_char_for_side(winner_side), "happy")

	# 掀桌子演出（达阈值时）
	if flip_table:
		_vn_button.disabled = true
		await _play_table_flip()
		_vn_button.disabled = false


## VN 面板按钮：教程中=跳过教程；整场结束=重来；否则下一局
func _on_vn_button_pressed() -> void:
	if state == State.TUTORIAL:
		_show_mode_select_flow()
		return
	if player_lives <= 0 or ai_lives <= 0:
		_show_mode_select_flow()
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


## 场景回应：只播 3D 醒目文字（挡样式弹出淡出），隐藏 2D 悬浮层
func _speak_scene(speaker: String, text: String) -> void:
	_update_char_talk(speaker)
	_show_scene_banner(text)
	if _vn_panel != null:
		_vn_panel.visible = false


## 在场景桌面中央上空显示一大段文字横幅（挡样式：弹出 + 淡出）
func _show_scene_banner(text: String) -> void:
	# 先清掉上一条横幅，避免重叠遮挡
	if _banner_label != null:
		if _banner_tw != null:
			_banner_tw.kill()
			_banner_tw = null
		_banner_label.queue_free()
		_banner_label = null
	var lab := Label3D.new()
	lab.text = text
	lab.font_size = 46
	lab.pixel_size = 0.0022
	lab.modulate = Color(1, 0.92, 0.55)
	lab.outline_size = 10
	lab.outline_modulate = Color(0, 0, 0, 0.9)
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position = Vector3(0.5, 1.6, 1.4)
	add_child(lab)
	_banner_label = lab
	_banner_tw = create_tween()
	_banner_tw.set_parallel(true)
	_banner_tw.tween_property(lab, "position:y", 2.0, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tw.tween_property(lab, "modulate:a", 0.0, 0.5).set_delay(1.6)
	_banner_tw.chain().tween_callback(func() -> void:
		_banner_tw = null
		if _banner_label == lab:
			_banner_label = null)


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


## 收集某方"被计入总点数"的牌值（保留=计入；跳过/弃牌不计入）
func _counted_values(slots: Array[CardSlot3D]) -> Array[int]:
	var vals: Array[int] = []
	for s in slots:
		if s.occupied and not s.skipped and s.card3d != null:
			vals.append(s.card3d.value)
	return vals


## 对一方应用本轮料种的命数修正（过期-1 / 精制+1，封顶 START_LIVES）
func _apply_ingredient_life(side: int) -> void:
	if side == Side.PLAYER:
		if round_ingredient == Ingredient.EXPIRED:
			player_lives = maxi(0, player_lives - 1)
		else:
			player_lives = mini(START_LIVES, player_lives + 1)
	else:
		if round_ingredient == Ingredient.EXPIRED:
			ai_lives = maxi(0, ai_lives - 1)
		else:
			ai_lives = mini(START_LIVES, ai_lives + 1)


func _ing_hit_desc(side: int, mv: int) -> String:
	var who := "你" if side == Side.PLAYER else "红队"
	var act := "在怀旧节被陈年料缠上，电量 -1" if round_ingredient == Ingredient.EXPIRED else "在新鲜日尝到鲜料，电量 +1"
	return "%s %s（牌 %d）" % [who, act, mv]


# ============================================================
#  镜头演出
# ============================================================
func _camera_move_to(target_pos: Vector3, look_at: Vector3, dur: float) -> void:
	if _camera == null:
		return
	_kill_cam_tw()
	var start := _camera.position
	_cam_tw = create_tween()
	_cam_tw.tween_method(_camera_track.bind(target_pos, look_at), start, target_pos, dur)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _camera_track(p: Vector3, target_pos: Vector3, look_at: Vector3) -> void:
	_camera.position = p
	_camera.look_at(look_at, Vector3.UP)


func _kill_cam_tw() -> void:
	if _cam_tw != null:
		_cam_tw.kill()
		_cam_tw = null


## 某侧手机特写镜头
func _phone_shot(side: int) -> Dictionary:
	if side == Side.PLAYER:
		return {"pos": Vector3(2.0, 1.5, 2.7), "look": Vector3(2.0, 0.6, 1.5), "dur": 0.7, "hold": 0.55, "react": ""}
	return {"pos": Vector3(-2.0, 1.5, -0.2), "look": Vector3(-2.0, 0.6, -1.5), "dur": 0.7, "hold": 0.55, "react": ""}


## 某侧角色镜头，带反应动画
func _char_shot(side: int, react: String) -> Dictionary:
	if side == Side.PLAYER:
		return {"pos": Vector3(1.9, 1.4, 1.5), "look": Vector3(1.9, 1.2, -0.5), "dur": 0.7, "hold": 0.9, "react": react, "char": _player_char}
	return {"pos": Vector3(-1.9, 1.4, 1.5), "look": Vector3(-1.9, 1.2, -0.5), "dur": 0.7, "hold": 0.9, "react": react, "char": _ai_char}


func _char_for_side(side: int) -> Node3D:
	return _player_char if side == Side.PLAYER else _ai_char


## 结算镜头序列：依次运镜，播完回主位
func _play_cam_seq(shots: Array) -> void:
	if _camera == null:
		return
	var token := _cam_seq_token + 1
	_cam_seq_token = token
	_kill_cam_tw()
	for shot in shots:
		if token != _cam_seq_token:
			return
		_camera_move_to(shot["pos"], shot["look"], shot["dur"])
		var react: String = shot.get("react", "")
		var ch: Node3D = shot.get("char", null)
		if react != "" and ch != null:
			_char_react(ch, react)
		await get_tree().create_timer(shot["hold"]).timeout
	if token != _cam_seq_token:
		return
	_camera_move_to(_cam_home_pos, _cam_home_look, 0.8)
	await get_tree().create_timer(0.8).timeout


## 对手抽牌/思考时：镜头轻微推进（局部推近，不做闪切）
func _cam_push_in() -> void:
	if _camera == null:
		return
	_camera_move_to(Vector3(0.5, 2.5, 3.1), Vector3(0, 0.5, -0.6), 0.9)


## 玩家回合：镜头比主位再稍微推近一点点
func _cam_player_push() -> void:
	if _camera == null:
		return
	_camera_move_to(Vector3(0.5, 2.8, 4.3), Vector3(0, 0.3, -0.4), 0.9)


## 回到主位
func _cam_push_out() -> void:
	if _camera == null:
		return
	_camera_move_to(_cam_home_pos, _cam_home_look, 0.9)


## 国王掀桌子演出：怒起→卡牌抛起+桌面倾斜→镜头震动→散落归位
func _play_table_flip() -> void:
	if _table == null:
		return
	_busy = true
	_char_react(_king_char, "happy")
	await get_tree().create_timer(0.45).timeout
	# 收集桌上的卡牌
	var cards: Array[Card3D] = []
	for s in _player_slots:
		if s.card3d != null:
			cards.append(s.card3d)
	for s in _ai_slots:
		if s.card3d != null:
			cards.append(s.card3d)
	# 卡牌抛起 + 横甩
	for c in cards:
		var dir := 1 if c.position.x >= 0.0 else -1
		var tw := c.create_tween().set_parallel(true)
		tw.tween_property(c, "position:y", 1.3, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "position:x", c.position.x + dir * 0.3, 0.5)
		tw.tween_property(c, "rotation_degrees:z", 32.0 * dir, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	# 桌面倾斜
	var ttw := _table.create_tween()
	ttw.tween_property(_table, "rotation_degrees:z", 20.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 镜头震动
	_kill_cam_tw()
	var shake := create_tween()
	shake.set_loops(6)
	shake.tween_property(_camera, "position:x", _cam_home_pos.x + 0.09, 0.04)
	shake.tween_property(_camera, "position:x", _cam_home_pos.x - 0.09, 0.04)
	await get_tree().create_timer(0.7).timeout
	# 卡牌散落落下（乱糟糟，下一局 reset 会清理）
	for c in cards:
		var tw2 := c.create_tween()
		tw2.tween_property(c, "position:y", 0.05, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# 桌面归位 + 相机归位
	var ttw2 := _table.create_tween()
	ttw2.tween_property(_table, "rotation_degrees:z", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_camera_move_to(_cam_home_pos, _cam_home_look, 0.4)
	await get_tree().create_timer(0.7).timeout
	_busy = false


## 弃牌：弹性“弹开”翻开 + 绕 Y 轴倾斜30°，作为“不要这张牌”的场景标记（双方对称）
func _set_discarded(card: Card3D) -> void:
	if card == null:
		return
	card.face_up = true
	var base_y := card._rest_y if card._rest_y != 0.0 else card.position.y
	var tw := card.create_tween()
	tw.tween_property(card, "position:y", base_y + 0.5, 0.16)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "rotation_degrees:x", 0.0, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(card, "rotation_degrees:y", 30.0, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "position:y", base_y, 0.16)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## 盲选：抽牌后把牌“稍微抬高、垂直桌面/卡槽”给玩家看（牌面朝向玩家，不公开平放）
func _blind_draw_view(card: Card3D) -> void:
	if card == null:
		return
	var base_y := card.position.y
	var tw := card.create_tween().set_parallel(true)
	tw.tween_property(card, "position:y", base_y + 0.35, 0.2)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "rotation_degrees:x", 90.0, 0.25)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await get_tree().create_timer(0.25).timeout


## 盲选：保留——把立起的牌平放盖下（暗牌回槽位）
func _card_place_down(card: Card3D) -> void:
	if card == null:
		return
	card.face_up = false
	var target_y := card._rest_y if card._rest_y != 0.0 else card.position.y
	var tw := card.create_tween().set_parallel(true)
	tw.tween_property(card, "position:y", target_y, 0.2)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(card, "rotation_degrees:x", 180.0, 0.25)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


## 盲选：保留牌绕前缘枢轴“翻面向玩家/摄像机一侧盖下”，牌面转离 AI 侧
func _blind_conceal_keep(card: Card3D) -> void:
	if card == null:
		return
	card.face_up = false
	var base_pos := card.position
	var main_node: Node = card.get_parent()
	# 在牌前缘（+z，靠玩家/摄像机侧）建枢轴
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.position = base_pos + Vector3(0, 0.02, 0.42)
	# 挂到枢轴下，牌心放在枢轴后侧
	card.reparent(pivot, true)
	card.position = Vector3(0, 0.02, -0.42)
	card.rotation_degrees.x = 0.0
	var tw := pivot.create_tween()
	tw.tween_property(pivot, "rotation_degrees:x", 180.0, 0.4)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await get_tree().create_timer(0.45).timeout
	# 挂回主节点，归位盖下
	card.reparent(main_node, true)
	card.rotation_degrees.x = 180.0
	pivot.queue_free()
	var tw2 := card.create_tween()
	tw2.tween_property(card, "position", base_pos, 0.25)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


## 在指定侧的槽位里找持有某数值的已翻开卡牌
func _find_card(slots: Array[CardSlot3D], mv: int) -> Card3D:
	for s in slots:
		if s.occupied and not s.skipped and s.card3d != null and s.card3d.value == mv:
			return s.card3d
	return null


## 盲选：开牌时逐个翻开双方被保留（计入）的牌，再显示总分
func _reveal_all_kept() -> void:
	for s in _player_slots:
		if s.occupied and not s.skipped and s.card3d != null:
			s.card3d.reveal()
			await get_tree().create_timer(0.35).timeout
	for s in _ai_slots:
		if s.occupied and not s.skipped and s.card3d != null:
			s.card3d.reveal()
			await get_tree().create_timer(0.35).timeout


## 给特殊料卡牌加一个“图钉”式红/绿扁平方块（约牌面 1/5）压住边角
func _add_pin_marker(card: Card3D) -> void:
	if card == null:
		return
	var color := Color(0.9, 0.25, 0.25) if round_ingredient == Ingredient.EXPIRED else Color(0.25, 0.9, 0.35)
	var pin := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.12, 0.02, 0.16)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	pin.mesh = pm
	pin.material_override = mat
	pin.position = Vector3(0.24, 0.04, 0.36)
	card.add_child(pin)
