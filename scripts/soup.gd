extends Area2D

signal reached_king

## 上菜时的飞行速度（像素/秒）
@export var speed: float = 320.0

var is_moving := false
var _start_pos := Vector2.ZERO
var _king_pos := Vector2.ZERO

@onready var king: Area2D = get_node("../King")


func _ready() -> void:
	_start_pos = position
	_king_pos = king.position


func start_moving() -> void:
	is_moving = true


func _process(delta: float) -> void:
	if not is_moving:
		return
	var dir := (_king_pos - _start_pos).normalized()
	position += dir * speed * delta
	if position.distance_to(_king_pos) < maxf(speed * delta, 4.0):
		position = _king_pos
		is_moving = false
		reached_king.emit()


func reset_to_start() -> void:
	position = _start_pos
	is_moving = false
