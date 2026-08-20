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
var _hover_base_y := 0.0

var _face_label: Label3D
var _crest_label: Label3D
var _body_mat: StandardMaterial3D
var _face_mat: StandardMaterial3D
var _area: Area3D


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
func set_orientation(face: bool, instant: bool = false) -> void:
	var target_deg := 0.0 if face else 180.0
	face_up = face
	if instant:
		rotation_degrees.x = target_deg
		return
	var base_y := position.y
	var tw := create_tween()
	tw.tween_property(self, "position:y", base_y + 0.4, 0.14)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation_degrees:x", target_deg, 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "position:y", base_y, 0.14)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## 结算时翻开（露出数字）
func reveal(instant: bool = false) -> void:
	set_orientation(true, instant)


func set_hover(h: bool) -> void:
	if h == hovering:
		return
	hovering = h
	if _hover_tw != null:
		_hover_tw.kill()
	if h:
		_hover_base_y = position.y  # 进入悬停：记录固定基准，避免位置累积漂移
	var target_y := _hover_base_y + (0.06 if h else 0.0)
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
		_spin_inspect()


## 发牌落地后调用：重置悬停基准到落地位置，避免悬停动画与发牌冲突
func settle_on_slot() -> void:
	hovering = false
	if _hover_tw != null:
		_hover_tw.kill()
	_hover_base_y = position.y


## 点击：做一次 360° 自旋检视（不暴露数字，仅表现力）
func _spin_inspect() -> void:
	var tw := create_tween()
	tw.tween_property(self, "rotation_degrees:x", rotation_degrees.x + 360.0, 0.6)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
