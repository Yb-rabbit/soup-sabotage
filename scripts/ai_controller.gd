class_name AIController
extends RefCounted
## AI 决策：**只看自身总分**（不考虑玩家分），目标逼近 21 施压。
## 两个决策：
##   decide_draw  -> 是否加料（返回 "draw"/"stand"）
##   decide_keep  -> 抽到牌后是否保留（保留=计入总分逼近21；跳过=耗槽保命）

const BUST_LIMIT := 21
const KING_MIN := 18


## 是否加料
static func decide_draw(ai_points: int, pool_size: int, slot_full: bool) -> String:
	if slot_full or pool_size <= 0:
		return "stand"
	# 未达标：必须加料
	if ai_points < KING_MIN:
		return "draw"
	# 已达 21：完美，求稳
	if ai_points >= BUST_LIMIT:
		return "stand"
	# 爆牌概率过高：求稳
	if _bust_probability(ai_points, pool_size) > 0.6:
		return "stand"
	# 追求 21：分数越低越倾向加料（抽到会爆的牌可"跳过"兜底）
	var chance := 0.0
	if ai_points <= 18:
		chance = 0.85
	elif ai_points == 19:
		chance = 0.55
	elif ai_points == 20:
		chance = 0.25
	return "draw" if randf() < chance else "stand"


## 抽到 drawn_value 后是否保留（false = 跳过，占用槽位但不计分）
## mark_value=本局 AI 标记牌；mark_refined=料种是否为新鲜日（新鲜日料倾向保留自回血，怀旧节料倾向跳过避免自扣血）
static func decide_keep(ai_points: int, drawn_value: int, mark_value: int = 0, mark_refined: bool = false) -> bool:
	# 保留会爆牌 => 跳过
	if ai_points + drawn_value > BUST_LIMIT:
		return false
	# 抽到标记牌：精制料倾向保留（自回血），过期料倾向跳过（避免自扣血）
	if mark_value != 0 and drawn_value == mark_value:
		return mark_refined
	# 不爆则保留（更接近 21）
	return true


## 选标记牌：新鲜日挑一张自己大概率能保留的低风险牌（自回血）；
## 怀旧节挑一张对方凑分时更可能保留的低数值牌（坑进对方手）。
## ingredient: 0=怀旧节(EXPIRED)，1=新鲜日(REFINED)
static func decide_mark(ingredient: int, pool: Array, ai_points: int) -> int:
	if pool.is_empty():
		return 0
	var low := [1, 2, 3, 4, 5]
	if ingredient == 1:  # 新鲜日：低分值自己更容易保留受益
		for v in low:
			if pool.has(v):
				return v
		return pool[0]
	# 怀旧节：低分值对方更可能保留凑分
	for v in low:
		if pool.has(v):
			return v
	return pool[0]


## 当前分数下，从剩余池抽一张导致爆牌(>21)的概率（近似，未知具体构成）
static func _bust_probability(points: int, pool_size: int) -> float:
	if pool_size <= 0:
		return 0.0
	var threshold := BUST_LIMIT - points
	if threshold < 1:
		return 1.0
	var dangerous := maxi(0, 10 - threshold)
	return float(dangerous) / float(pool_size)

