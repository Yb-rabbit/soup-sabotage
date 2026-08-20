class_name Button3D
extends Node3D
## 通用 3D 按钮：底板 + 文字 + 副标题，Area3D 交互（悬停高亮、点击）。
## 含 enabled 状态（置灰不可点）与供屏幕同步提示的 title/subtitle。

signal pressed

var enabled := true
var title := ""
var subtitle := ""

var _mat: StandardMaterial3D
var _base_color := Color(0.85, 0.85, 0.85)
var _label: Label3D
var _hovering := false
var _hover_tw: Tween = null
var _hover_base_y := 0.0


func setup(p_title: String, p_sub: String, color: Color = Color(0.85, 0.85, 0.85)) -> void:
	title = p_title
	subtitle = p_sub
	_base_color = color
	if _mat != null:
		_mat.albedo_color = color
		_mat.emission = color
		set_enabled(true)


func _ready() -> void:
	_build()


func _build() -> void:
	# 底板
	var plate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.85, 0.06, 0.34)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = _base_color
	_mat.emission_enabled = true
	_mat.emission = _base_color
	plate.mesh = box
	plate.material_override = _mat
	add_child(plate)

	# 主文字（面朝 +Y）
	_label = Label3D.new()
	_label.text = title
	_label.font_size = 52
	_label.pixel_size = 0.0022
	_label.modulate = Color(0.06, 0.06, 0.08)
	_label.rotation_degrees.x = -90.0
	_label.position = Vector3(0, 0.045, 0)
	add_child(_label)

	# 副标题（更小，提示用途，面朝 +Y）
	var sub := Label3D.new()
	sub.text = subtitle
	sub.font_size = 32
	sub.pixel_size = 0.0016
	sub.modulate = Color(0.9, 0.9, 0.9)
	sub.rotation_degrees.x = -90.0
	sub.position = Vector3(0, 0.028, 0)
	add_child(sub)

	# 交互
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.9, 0.1, 0.36)
	shape.shape = bs
	area.add_child(shape)
	area.input_event.connect(_on_input_event)
	area.mouse_entered.connect(func() -> void: set_hover(true))
	area.mouse_exited.connect(func() -> void: set_hover(false))
	add_child(area)


func set_enabled(e: bool) -> void:
	enabled = e
	if _mat == null:
		return
	if e:
		_mat.emission_enabled = true
		_mat.albedo_color = _base_color
		_mat.emission = _base_color
		_label.modulate = Color(0.06, 0.06, 0.08)
	else:
		_mat.emission_enabled = false
		_mat.albedo_color = Color(0.24, 0.24, 0.26)
		_label.modulate = Color(0.5, 0.5, 0.5)


## 高亮时降暗（教程用）
func set_dim(d: bool) -> void:
	if _mat != null:
		_mat.emission_energy_multiplier = 0.15 if d else 1.0


func set_hover(h: bool) -> void:
	if h == _hovering:
		return
	_hovering = h
	if _hover_tw != null:
		_hover_tw.kill()
	if h:
		_hover_base_y = position.y  # 记录固定基准，避免位置累积漂移
	var target_y := _hover_base_y + (0.05 if h else 0.0)
	_hover_tw = create_tween()
	_hover_tw.set_parallel(true)
	_hover_tw.tween_property(self, "position:y", target_y, 0.15)
	_hover_tw.tween_property(_mat, "emission_energy_multiplier", 2.0 if h else 1.0, 0.15)


func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int) -> void:
	if enabled and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
