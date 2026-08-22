class_name ScoreDisplay3D
extends Node3D
## 手机立牌：竖立面板，屏幕显示总分 + 电量格命数。
## 电量格：4 格，按剩余命数整组变色（4绿/3黄/2橙/1红/0灭），点亮前 lives 格。
## 面向 +Z（朝玩家/相机）。支持 set_dim 高亮降暗。

var points := 0
var lives := 0
var _grayed := false  # 盲选模式：数字置暗灰，不按分数变色

var _number: Label3D
var _flash_tw: Tween = null
var _flicker_tw: Tween = null
var _cells: Array[StandardMaterial3D] = []
var _all_mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	_build()


func _build() -> void:
	# 面板（竖立，面朝 +Z）
	var panel := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.7, 0.8, 0.03)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.03, 0.92)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.04, 0.04, 0.06)
	panel.mesh = b
	panel.material_override = mat
	panel.position = Vector3(0, 0.4, 0)
	add_child(panel)
	_all_mats.append(mat)

	# 数字（面朝 +Z）
	_number = Label3D.new()
	_number.text = "0"
	_number.font = load("res://scripts/STENCIL.TTF")
	_number.font_size = 128
	_number.pixel_size = 0.0016
	_number.modulate = Color(0.95, 0.95, 0.95)
	_number.position = Vector3(0, 0.55, 0.017)
	add_child(_number)

	# 电量格 4 个（面朝 +Z，排成一排）
	for i in 4:
		var cell := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.13, 0.2, 0.02)
		var cm := StandardMaterial3D.new()
		cm.emission_enabled = true
		cm.emission = Color(0.12, 0.12, 0.12)
		cm.albedo_color = Color(0.12, 0.12, 0.12)
		cell.mesh = cb
		cell.material_override = cm
		cell.position = Vector3((i - 1.5) * 0.16, 0.22, 0.018)
		add_child(cell)
		_cells.append(cm)
		_all_mats.append(cm)


## 设置保留牌点数和并更新颜色
func set_points(p: int) -> void:
	points = p
	if _number == null:
		return
	_number.text = str(p)
	if _grayed:
		_stop_flash()
		_number.modulate = Color(0.5, 0.5, 0.5)
		return
	if p > 21:
		_number.modulate = Color(1.0, 0.25, 0.25)
		_start_flash()
	elif p >= 18:
		_stop_flash()
		_number.modulate = Color(1.0, 0.82, 0.2)
	else:
		_stop_flash()
		_number.modulate = Color(0.95, 0.95, 0.95)


## 盲选模式：置灰/恢复数字颜色（不按分数变色）
func set_grayed(g: bool) -> void:
	if _grayed == g:
		return
	_grayed = g
	set_points(points)


## 设置剩余命数 -> 电量格
func set_lives(l: int) -> void:
	lives = l
	var tier := _tier_color(l)
	for i in _cells.size():
		var on := i < l
		var c := tier if on else Color(0.12, 0.12, 0.12)
		_cells[i].emission = c
		_cells[i].albedo_color = c
	# 剩 1 颗：间歇闪烁（像要坏掉），其余时候恢复稳定
	if l == 1:
		_start_flicker()
	else:
		_stop_flicker()


func _tier_color(l: int) -> Color:
	match l:
		4:
			return Color(0.3, 1.0, 0.3)
		3:
			return Color(1.0, 0.85, 0.2)
		2:
			return Color(1.0, 0.55, 0.1)
		1:
			return Color(1.0, 0.25, 0.2)
		_:
			return Color(0.1, 0.1, 0.1)


## 高亮时降暗（教程用）：降低所有材质自发光
func set_dim(d: bool) -> void:
	if _all_mats.is_empty():
		return
	for m in _all_mats:
		m.emission_energy_multiplier = 0.15 if d else 1.0


func _start_flash() -> void:
	_stop_flash()
	_flash_tw = create_tween().set_loops()
	_flash_tw.tween_property(_number, "modulate:r", 0.45, 0.18)
	_flash_tw.tween_property(_number, "modulate:r", 1.0, 0.18)


func _stop_flash() -> void:
	if _flash_tw != null:
		_flash_tw.kill()
		_flash_tw = null


## 剩 1 颗电：点亮的电池格间歇闪烁（快速闪两下 → 停一拍 → 再闪），营造"要坏掉"的感觉
func _start_flicker() -> void:
	_stop_flicker()
	if lives != 1 or _cells.is_empty():
		return
	var on := Color(1.0, 0.25, 0.2)   # 剩 1 颗的红色
	var off := Color(0.28, 0.07, 0.06)
	_flicker_tw = create_tween().set_loops()
	for i in 2:
		_flicker_tw.tween_property(_cells[0], "emission", off, 0.1)
		_flicker_tw.tween_property(_cells[0], "emission", on, 0.1)
	_flicker_tw.tween_interval(0.8)  # 停一拍，形成间歇而非一直闪


func _stop_flicker() -> void:
	if _flicker_tw != null:
		_flicker_tw.kill()
		_flicker_tw = null


## 输牌/倒下时隐藏记牌器数字（复位后恢复显示）
func set_number_visible(v: bool) -> void:
	if _number == null:
		return
	_number.visible = v

