extends Node
## CardAnimator3D —— 全局单例（Autoload）。
## 统一处理 3D 发牌动画：三轴位移(parallel) + 高度抛物线 + 720° 自旋翻面。
## 落地时牌背朝上；结算翻开由 Card3D.reveal() 完成。

signal deal_finished(slot: CardSlot3D)

var _busy := false


func play_deal(card: Card3D, target: CardSlot3D, value: int, yaw_final := 0.0) -> void:
	if _busy or card == null or target == null:
		return
	_busy = true

	var to := target.position + Vector3(0, 0.02, 0)
	card.rotation_degrees.x = 180.0  # 初始牌背朝上
	card.rotation_degrees.y = yaw_final  # 对坐：玩家牌朝玩家(+z)，对面牌朝对面(-z)

	var tw := create_tween()
	tw.set_parallel(true)
	# 1. 平面位移 (x/z)
	tw.tween_property(card, "position:x", to.x, 0.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(card, "position:z", to.z, 0.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	# 2. 高度抛物线：先升到 3，后落回目标高度（delay 错峰）
	tw.tween_property(card, "position:y", 3.0, 0.25)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "position:y", to.y, 0.25)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(0.25)
	# 3. 自旋：绕 Y 轴转 720°+朝向偏移（整圈保持水平转圈，落地牌背朝上且朝向目标）
	tw.tween_property(card, "rotation_degrees:y", 720.0 + yaw_final, 0.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	tw.finished.connect(_finish_deal.bind(card, target, value))


func _finish_deal(card: Card3D, target: CardSlot3D, value: int) -> void:
	card.rotation_degrees.x = 180.0  # 确保落地牌背朝上
	target.set_occupied(card)
	card.settle_on_slot()
	_busy = false
	deal_finished.emit(target)


## 在槽上方浮现 "+N" 并淡出
func _spawn_float(target: CardSlot3D, value: int) -> void:
	var lab := Label3D.new()
	lab.text = "+%d" % value
	lab.font_size = 60
	lab.pixel_size = 0.0016
	lab.modulate = Color(1.0, 0.85, 0.3)
	lab.rotation_degrees.x = -90.0
	lab.position = Vector3(0, 0.12, 0)
	lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	target.add_child(lab)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lab, "position:y", 0.45, 0.7)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lab, "modulate:a", 0.0, 0.7)
	tw.finished.connect(lab.queue_free)
