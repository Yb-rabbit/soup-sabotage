class_name Card3D
extends Node3D
## 3D 卡牌：BoxMesh 卡身（暗红牌背）+ 羊皮纸牌面 + 数字/皇冠 Label3D。
## 用真实 X 轴旋转实现翻面（牌面朝 +Y <-> 牌背朝 +Y）。
## 交互：Area3D 悬停高亮 + 点击检视。

signal hovered
signal unhovered
signal clicked

const CARD_W := 0.6
const CARD_H := 0.85

var value := 0
var face_up := false
var hovering := false
var _hover_tw: Tween = null
var _rest_y := 0.0  # 落槽基准高度（权威基准，翻面/悬停/点击都以它回位，避免位置漂移）

var _face_label: Label3D
var _crest_label: Label3D
var _body_mat: StandardMaterial3D
var _face_mat: StandardMaterial3D
var _area: Area3D
var _flip_tw: Tween = null


func setup(v: int) -> void:
	value = v
	if _face_label != null:
		_face_label.text = str(v)


func _ready() -> void:
	_build()


func _build() -> void:
	# 卡身：薄长方体，暗红牌背色
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CARD_W, 0.02, CARD_H)
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.25, 0.05, 0.05)
	_body_mat.emission_enabled = true
	_body_mat.emission = Color(0.35, 0.06, 0.06)
	body.mesh = box
	body.material_override = _body_mat
	add_child(body)

	# 牌面：羊皮纸平面，面朝 +Y
	var face := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(CARD_W * 0.92, CARD_H * 0.92)
	quad.orientation = QuadMesh.FACE_Y
	_face_mat = StandardMaterial3D.new()
	_face_mat.albedo_color = Color(0.95, 0.91, 0.82)
	_face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face.mesh = quad
	face.material_override = _face_mat
	face.position = Vector3(0, 0.012, 0)
	add_child(face)

	# 正面数字（朝向 +Y）
	_face_label = Label3D.new()
	_face_label.text = str(value)
	_face_label.font_size = 128
	_face_label.pixel_size = 0.0014
	_face_label.modulate = Color(0.2, 0.12, 0.05)
	_face_label.rotation_degrees.x = -90.0
	_face_label.position = Vector3(0, 0.02, 0)
	_face_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(_face_label)

	# 背面皇冠（朝向 -Y，翻到牌背时可见）
	_crest_label = Label3D.new()
	_crest_label.text = "♛"
	_crest_label.font_size = 72
	_crest_label.pixel_size = 0.0018
	_crest_label.modulate = Color(0.92, 0.72, 0.45)
	_crest_label.rotation_degrees.x = 90.0
	_crest_label.position = Vector3(0, -0.013, 0)
	_crest_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(_crest_label)

	# 交互：Area3D + 碰撞盒
	_area = Area3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(CARD_W, 0.02, CARD_H)
	shape.shape = bs
	_area.add_child(shape)
	_area.input_event.connect(_on_area_input_event)
	_area.mouse_entered.connect(_on_mouse_entered)
	_area.mouse_exited.connect(_on_mouse_exited)
	add_child(_area)


## 设置朝向：face=true 牌面朝上（rotation.x=0）；face=false 牌背朝上（rotation.x=180）
## 非瞬时翻转时先抬升再旋转再落下，避免旋转过程扫进桌面（"沉入"）
## 翻转前打断悬停/旧的翻转 tween，并以落槽基准 _rest_y 回位，避免翻面后位置滞留错位
func set_orientation(face: bool, instant: bool = false) -> void:
	var target_deg := 0.0 if face else 180.0
	face_up = face
	if _flip_tw != null:
		_flip_tw.kill()
		_flip_tw = null
	if _hover_tw != null:
		_hover_tw.kill()
		_hover_tw = null
	hovering = false
	var base_y := _rest_y if _rest_y != 0.0 else position.y
	_rest_y = base_y
	if instant:
		rotation_degrees.x = target_deg
		position.y = base_y
		_reset_glow()
		return
	_flip_tw = create_tween()
	_flip_tw.tween_property(self, "position:y", base_y + 0.4, 0.14)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flip_tw.tween_property(self, "rotation_degrees:x", target_deg, 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_flip_tw.tween_property(self, "position:y", base_y, 0.14)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_flip_tw.finished.connect(func() -> void:
		_flip_tw = null
		_reset_glow())


## 结算时翻开（露出数字）
func reveal(instant: bool = false) -> void:
	set_orientation(true, instant)


func set_hover(h: bool) -> void:
	if h == hovering:
		return
	hovering = h
	if _hover_tw != null:
		_hover_tw.kill()
		_hover_tw = null
	var target_y := _rest_y + (0.06 if h else 0.0)
	_hover_tw = create_tween()
	_hover_tw.set_parallel(true)
	_hover_tw.tween_property(self, "position:y", target_y, 0.15)
	_hover_tw.tween_property(_body_mat, "emission:r", 0.9 if h else 0.35, 0.15)
	_hover_tw.tween_property(_body_mat, "emission:g", 0.5 if h else 0.06, 0.15)
	_hover_tw.tween_property(_body_mat, "emission:b", 0.5 if h else 0.06, 0.15)


func _on_mouse_entered() -> void:
	hovered.emit()
	set_hover(true)


func _on_mouse_exited() -> void:
	unhovered.emit()
	set_hover(false)


func _on_area_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
		if face_up:
			_spin_inspect()
		else:
			_reject_scale()


## 发牌落地后调用：记录落槽基准高度，避免悬停动画与发牌冲突
func settle_on_slot() -> void:
	hovering = false
	if _hover_tw != null:
		_hover_tw.kill()
		_hover_tw = null
	_rest_y = position.y
	_reset_glow()


## 点击：先结束悬停回到落槽高度，再做 360° 自旋检视（不暴露数字，仅表现力）
func _spin_inspect() -> void:
	if _hover_tw != null:
		_hover_tw.kill()
		_hover_tw = null
	hovering = false
	_reset_glow()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position:y", _rest_y, 0.18)
	tw.tween_property(self, "rotation_degrees:x", rotation_degrees.x + 360.0, 0.6)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_callback(_after_spin)


## 自旋结束：把旋转归一化到牌面朝向，并复位发光
func _after_spin() -> void:
	rotation_degrees.x = 0.0 if face_up else 180.0
	_reset_glow()


## 未翻开的牌被点击：做一次"放缩"拒绝动作，不翻开、不暴露数值
func _reject_scale() -> void:
	if _flip_tw != null:
		_flip_tw.kill()
		_flip_tw = null
	if _hover_tw != null:
		_hover_tw.kill()
		_hover_tw = null
	hovering = false
	_reset_glow()
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.72, 0.72, 0.72), 0.12)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "position:y", _rest_y, 0.12)
	tw.tween_property(self, "scale", Vector3.ONE, 0.32)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 复位卡身发光到默认（暗红牌背）
func _reset_glow() -> void:
	if _body_mat == null:
		return
	_body_mat.emission = Color(0.35, 0.06, 0.06)
