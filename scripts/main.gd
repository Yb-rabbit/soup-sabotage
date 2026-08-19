extends Node2D

## 皇家厨房：香料博弈 —— MVP（交替回合版）
## 每局共享卡池 = 1~10 各一张（共 10 张，总和恒为 55），开局双方各公开抽一张起始牌。
## 玩家回合自由决策；加料后进入 AI 回合，AI 思考倒计时结束抽一张，再回到玩家回合。
## 谁先把分数做到 15~21 并上菜即赢本局；爆(>21)或太淡(<15 上菜)即输本局。
## 三局两胜；每局相互独立，重新发一套香料。

const BUST_LIMIT := 21
const KING_MIN := 15
const AI_THINK_TIME := 2.5
const ROUND_NAMES := ["前菜", "主菜", "甜点"]
const ROUNDS_TO_WIN := 2
const CARD_MAX := 10

enum Turn { PLAYER, AI, OVER }

@onready var soup: Area2D = $GameLayer/Soup
@onready var story_label: Label = $UILayer/VBox/Header/HeaderV/StoryLabel
@onready var points_label: Label = $UILayer/VBox/PlayerPanel/PlayerVBox/PointsLabel
@onready var draw_button: Button = $UILayer/VBox/Controls/DrawCardButton
@onready var serve_button: Button = $UILayer/VBox/Controls/ServeButton
@onready var round_label: Label = $UILayer/VBox/Header/HeaderV/RoundLabel
@onready var ai_score_label: Label = $UILayer/VBox/AIPanel/AIVBox/AIScoreLabel
@onready var ai_last_label: Label = $UILayer/VBox/AIPanel/AIVBox/AILastCardLabel
@onready var ai_timer_bar: ProgressBar = $UILayer/VBox/AIPanel/AIVBox/AITimerBar
@onready var deck_count_label: Label = $UILayer/VBox/DeckPanel/DeckVBox/DeckCountLabel
@onready var player_start_label: Label = $UILayer/VBox/PlayerPanel/PlayerVBox/PlayerStartLabel
@onready var ai_start_label: Label = $UILayer/VBox/AIPanel/AIVBox/AIStartLabel

var card_pool: Array[int] = []
var player_points := 0
var ai_points := 0
var player_wins := 0
var ai_wins := 0
var round_index := 0
var turn := Turn.PLAYER
var game_over := false
var ai_timer: Timer


func _ready() -> void:
	ai_timer = Timer.new()
	ai_timer.wait_time = AI_THINK_TIME
	ai_timer.timeout.connect(_on_ai_timer_timeout)
	add_child(ai_timer)
	draw_button.pressed.connect(_on_draw_card_button_pressed)
	serve_button.pressed.connect(_on_serve_button_pressed)
	soup.reached_king.connect(_on_reached_king)
	ai_timer_bar.max_value = 100.0
	_start_round()


## 从共享卡池随机取一张并移除（当局抽牌次数上限随之减少）
func _draw_from_pool() -> int:
	var idx := randi_range(0, card_pool.size() - 1)
	var v := card_pool[idx]
	card_pool.remove_at(idx)
	return v


func _start_round() -> void:
	ai_timer.stop()
	card_pool = []
	for v in range(1, CARD_MAX + 1):
		card_pool.append(v)
	player_points = 0
	ai_points = 0
	turn = Turn.PLAYER
	soup.reset_to_start()
	# 开局：双方各从卡池随机抽一张起始牌（公开）
	var p_card := _draw_from_pool()
	var a_card := _draw_from_pool()
	player_points = p_card
	ai_points = a_card
	round_label.text = "第 %d/%d 局 · %s     你 %d - %d 红队" % [round_index + 1, ROUND_NAMES.size(), ROUND_NAMES[round_index], player_wins, ai_wins]
	player_start_label.text = "开局起始牌：%d" % p_card
	ai_start_label.text = "开局起始牌：%d" % a_card
	ai_last_label.text = ""
	draw_button.disabled = false
	serve_button.text = "上菜（结算）"
	serve_button.disabled = false
	story_label.text = "第 %d 道——%s！你手气 %d，红队 %d。轮到你先出手：加料还是上菜？" % [round_index + 1, ROUND_NAMES[round_index], p_card, a_card]
	_update_labels()
	_set_timer_bar(0.0)


func _on_draw_card_button_pressed() -> void:
	if game_over or turn != Turn.PLAYER or card_pool.is_empty():
		return
	var v := _draw_from_pool()
	player_points += v
	story_label.text = "你抽到 +%d，当前 %d 点。" % [v, player_points]
	_update_labels()
	if player_points > BUST_LIMIT:
		_end_round(false, "你爆了（%d > 21）！厨师被炸飞，本局红队获胜。" % player_points)
		return
	if card_pool.is_empty():
		_resolve_empty_pool()
		return
	_start_ai_turn()


func _start_ai_turn() -> void:
	turn = Turn.AI
	draw_button.disabled = true
	serve_button.disabled = true
	story_label.text = story_label.text + "\n红队正在思考（倒计时 %.1f 秒）……" % AI_THINK_TIME
	ai_timer.start()
	_set_timer_bar(100.0)


func _on_ai_timer_timeout() -> void:
	if game_over or turn != Turn.AI:
		return
	var v := _draw_from_pool()
	ai_points += v
	ai_last_label.text = "红队抽到 %d" % v
	story_label.text = "红队抽到 +%d，当前 %d 点。轮到你出手了。" % [v, ai_points]
	_update_labels()
	if ai_points > BUST_LIMIT:
		_end_round(true, "红队爆了（%d > 21）！本局你获胜。" % ai_points)
		return
	if ai_points >= KING_MIN:
		_end_round(false, "红队抽到 %d 点并立刻上菜（达标）！本局你输。" % ai_points)
		return
	if card_pool.is_empty():
		_resolve_empty_pool()
		return
	turn = Turn.PLAYER
	ai_timer.stop()
	draw_button.disabled = false
	serve_button.disabled = false
	_set_timer_bar(0.0)


func _on_serve_button_pressed() -> void:
	if game_over:
		_restart_full()
		return
	if turn == Turn.OVER:
		_go_next_round()
		return
	if turn != Turn.PLAYER or soup.is_moving:
		return
	if player_points < KING_MIN:
		_end_round(false, "太淡了（%d < 15）！国王拒绝食用，本局你输。" % player_points)
	elif player_points <= BUST_LIMIT:
		turn = Turn.OVER
		draw_button.disabled = true
		serve_button.disabled = true
		soup.start_moving()
		_set_timer_bar(0.0)


func _on_reached_king() -> void:
	if player_points >= KING_MIN and player_points <= BUST_LIMIT:
		_end_round(true, "完美上菜！点数 %d，本局你获胜！" % player_points)
	else:
		_end_round(false, "上菜无效，点数 %d 不达标，本局你输。" % player_points)


func _resolve_empty_pool() -> void:
	turn = Turn.OVER
	_set_timer_bar(0.0)
	var p_ok := player_points >= KING_MIN and player_points <= BUST_LIMIT
	var a_ok := ai_points >= KING_MIN and ai_points <= BUST_LIMIT
	if p_ok and not a_ok:
		_end_round(true, "香料耗尽。你达标（%d）而红队未达标，本局你胜！" % player_points)
	elif a_ok and not p_ok:
		_end_round(false, "香料耗尽。红队达标（%d）而你没达标，本局你输。" % ai_points)
	else:
		story_label.text = "香料耗尽且无人胜出，国王不耐烦，重新上这道菜！"
		_start_round()


func _end_round(player_won: bool, message: String) -> void:
	turn = Turn.OVER
	ai_timer.stop()
	_set_timer_bar(0.0)
	draw_button.disabled = true
	serve_button.disabled = true
	story_label.text = message
	if player_won:
		player_wins += 1
	else:
		ai_wins += 1
	round_label.text = "第 %d/%d 局 · %s     你 %d - %d 红队" % [round_index + 1, ROUND_NAMES.size(), ROUND_NAMES[round_index], player_wins, ai_wins]
	if player_wins >= ROUNDS_TO_WIN or ai_wins >= ROUNDS_TO_WIN:
		_end_match()
	else:
		serve_button.disabled = false
		serve_button.text = "下一道菜"


func _go_next_round() -> void:
	round_index += 1
	_start_round()


func _end_match() -> void:
	game_over = true
	_set_timer_bar(0.0)
	draw_button.disabled = true
	serve_button.disabled = false
	serve_button.text = "重新开宴"
	if player_wins >= ROUNDS_TO_WIN:
		story_label.text = "🎉 你赢得整场盛宴！国王赐你黄金勺，红队被扔进锅里做成明天的汤。"
	else:
		story_label.text = "💀 红队赢得整场盛宴。你被扔进锅里，成了明天的一道菜……"


func _restart_full() -> void:
	player_wins = 0
	ai_wins = 0
	round_index = 0
	game_over = false
	_start_round()


func _set_timer_bar(ratio: float) -> void:
	ai_timer_bar.value = clampf(ratio, 0.0, 100.0)


func _update_labels() -> void:
	points_label.text = "你：%d 点" % player_points
	ai_score_label.text = "红队：%d 点" % ai_points
	deck_count_label.text = "香料剩余：%d / %d" % [card_pool.size(), CARD_MAX]
	points_label.add_theme_color_override("font_color", _zone_color(player_points))
	ai_score_label.add_theme_color_override("font_color", _zone_color(ai_points))


func _zone_color(points: int) -> Color:
	if points > BUST_LIMIT:
		return Color(1, 0.2, 0.2)
	elif points >= KING_MIN:
		return Color(0.2, 1, 0.3)
	else:
		return Color(0.6, 0.7, 1)


## 每帧把 AI 思考倒计时条按剩余时间递减
func _process(_delta: float) -> void:
	if turn == Turn.AI and not ai_timer.is_stopped():
		_set_timer_bar(100.0 * ai_timer.time_left / ai_timer.wait_time)
