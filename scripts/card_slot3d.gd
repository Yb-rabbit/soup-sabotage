class_name CardSlot3D
extends Node3D
## 3D 黑槽：桌面上的一块半透明暗板。占用时 emission 发光（绿=玩家/红=AI）。
## 支持"跳过/弃牌"状态：置灰 + ✕ 标记，表示占用该槽但不计分。

var card3d: Card3D = null
var occupied := false
var skipped := false
var glow_color := Color(0.3, 0.9, 0.3)

var _plate_mat: StandardMaterial3D
var _skip_label: Label3D


func _ready() -> void:
	_build()


func _build() -> void:
	var plate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.72, 0.015, 0.95)
	_plate_mat = StandardMaterial3D.new()
	_plate_mat.albedo_color = Color(0.04, 0.04, 0.05, 0.8)
	_plate_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plate_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plate.mesh = box
	plate.material_override = _plate_mat
	position.y = 0.008
	add_child(plate)

	# "跳过/弃牌"标记（默认隐藏）
	_skip_label = Label3D.new()
	_skip_label.text = "✕ 弃"
	_skip_label.font_size = 40
	_skip_label.pixel_size = 0.0016
	_skip_label.modulate = Color(1.0, 0.35, 0.35)
	_skip_label.rotation_degrees.x = -90.0
	_skip_label.position = Vector3(0, 0.14, 0)
	_skip_label.visible = false
	add_child(_skip_label)


func is_empty() -> bool:
	return not occupied


func set_occupied(c: Card3D) -> void:
	card3d = c
	occupied = true
	skipped = false
	_highlight(glow_color)


## 标记该槽为"跳过/弃牌"（占槽但不计分）
func set_skipped(s: bool) -> void:
	skipped = s
	if _plate_mat == null:
		return
	if s:
		_plate_mat.emission_enabled = false
		_plate_mat.albedo_color = Color(0.28, 0.24, 0.24, 0.6)
		_skip_label.visible = true
	else:
		_skip_label.visible = false
		_highlight(glow_color)


func reset() -> void:
	if card3d != null:
		card3d.queue_free()
		card3d = null
	occupied = false
	skipped = false
	_skip_label.visible = false
	_plate_mat.emission_enabled = false
	_plate_mat.albedo_color = Color(0.04, 0.04, 0.05, 0.8)


func _highlight(c: Color) -> void:
	_plate_mat.emission_enabled = true
	_plate_mat.emission = c
	_plate_mat.albedo_color = Color(c.r, c.g, c.b, 0.45)


## 高亮时降暗（教程用）
func set_dim(d: bool) -> void:
	_plate_mat.emission_energy_multiplier = 0.15 if d else 1.0

