extends Node

var global_movespeed_multiplier: float = 1.0
var global_bulletspeed_multiplier: float = 1.0
var global_sway: float = 0.0
var global_drop_multiplier: float = 1.0
var global_cooldown_multiplier: float = 1.0
var global_reaction_delay: float = 0.4
var global_sustain_dist_multiplier: float = 1.0
var global_aggression: float = 0.5
var global_prediction_factor: float = 0.0
var player_invul_time: float = 0.2

@export var adaptive_difficulty: bool = false
@export var base_difficulty: float = 1.5
@export var min_difficulty: float = 0.0
@export var max_difficulty: float = 3.0

@export var adjustment_multiplier: float = 1.0
@export var difficulty_smoothing: float = 0.5
@export var max_upward_adjustment: float = 0.2
@export var min_change: float = 0.1
@export var death_penalty: float = 0.5

var difficulty_score: float = 1.5
var target_diff: float = 1.5
var current_bias: float = 1.0

var _recent_hits: float = 0.0
var _recent_misses: float = 0.0
var _recent_damage_count: float = 0.0
var _recent_kills_without_damage: float = 0.0

const ACCURACY_WINDOW_RESET: float = 5.0
var _accuracy_window_timer: float = 0.0

var _time_since_death: float = 0.0
var _last_damage_time: float = 0.0
var _consecutive_deaths: int = 0

var powerup_mult: float = 1.0
var bomb_active: bool = false

var player: Node = null
var count_time: bool = false

var lowest_diff: float
var highest_diff: float

signal updated_difficulty

func _ready() -> void:
	lowest_diff = max_difficulty
	highest_diff = min_difficulty
	difficulty_score = base_difficulty
	target_diff = base_difficulty

func _process(delta: float) -> void:
	if player == null:
		return
		
	if count_time:
		_time_since_death += delta
		
	if !adaptive_difficulty: 
		difficulty_score = base_difficulty
		_apply_difficulty_score()
		return
		
	var weight = 0.27 * delta if target_diff > difficulty_score else 1.2 * delta
	difficulty_score = lerp(difficulty_score, target_diff, weight * difficulty_smoothing)
	_apply_difficulty_score()
	
	_accuracy_window_timer += delta
	if _accuracy_window_timer >= ACCURACY_WINDOW_RESET:
		_recent_hits *= 0.8
		_recent_misses *= 0.8
		_recent_damage_count *= 0.8
		_accuracy_window_timer = 0.0

func recalculate_difficulty() -> void:
	if !adaptive_difficulty:
		target_diff = base_difficulty
		return
		
	var adjustment: float = 0.0
	
	var recent_total = _recent_hits + _recent_misses
	if recent_total >= 10:
		var recent_acc = float(_recent_hits) / float(recent_total)
		var acc_adjust = remap(clampf(recent_acc, 0.2, 0.9), 0.2, 0.9, -0.8, 0.8)
		
		if bomb_active: 
			if acc_adjust > 0:
				adjustment += acc_adjust
				
		if recent_total >= 50:
			_recent_hits *= 0.8
			_recent_misses *= 0.8

	var weighted_dmg = _recent_damage_count * current_bias
	var efficiency = float(_recent_kills_without_damage) / (weighted_dmg + 1.0)
	
	if efficiency > 5.0:
		adjustment += 0.7
	elif efficiency > 2.0:
		adjustment += 0.5
	elif efficiency < 0.5:
		adjustment -= 0.4
		
	var death_adj = (_consecutive_deaths * death_penalty)
	if death_adj > 1.0:
		death_adj = 1.0
	adjustment -= death_adj
	
	var time_factor = clampf(_time_since_death / 300.0, 0.0, 0.2)
	adjustment += time_factor
	
	adjustment *= adjustment_multiplier
	
	if adjustment > 0:
		adjustment *= powerup_mult
		
	if abs(adjustment) >= min_change:
		var newdiff = clampf(base_difficulty + adjustment, min_difficulty, max_difficulty)
		if newdiff - target_diff > max_upward_adjustment:
			newdiff = target_diff + max_upward_adjustment
		target_diff = newdiff

func _apply_difficulty_score() -> void:
	var d = difficulty_score / max_difficulty
	
	global_movespeed_multiplier    = lerpf(0.4, 1.2, d)
	global_bulletspeed_multiplier   = lerpf(0.45, 1.8, d)
	global_sway                    = lerpf(15.0, 0.0, d)
	global_drop_multiplier         = lerpf(2.0, 0.25, d)
	global_cooldown_multiplier     = lerpf(2.25, 0.8, d)
	global_reaction_delay          = lerpf(1.0, 0.1, d)
	global_sustain_dist_multiplier = lerpf(0.75, 1.3, d)
	global_aggression              = lerpf(0.1, 0.9, d)
	global_prediction_factor       = lerpf(0.0, 1.0, d)
	player_invul_time              = lerpf(0.6, 0.15, d)
	
	if difficulty_score < lowest_diff:
		lowest_diff = difficulty_score
	if difficulty_score > highest_diff:
		highest_diff = difficulty_score
		
	updated_difficulty.emit()

func _on_kill() -> void:
	if adaptive_difficulty:
		var time_since_dmg = _time_since_death - _last_damage_time
		if time_since_dmg > 5.0:
			_recent_kills_without_damage += 1
		recalculate_difficulty()

func on_player_hit(damage_amt: float) -> void:
	_last_damage_time = _time_since_death
	var penalty = 2 * current_bias
	_recent_kills_without_damage = max(0, _recent_kills_without_damage - penalty)
	_recent_damage_count += 1
	if adaptive_difficulty:
		recalculate_difficulty()

func on_player_death() -> void:
	_consecutive_deaths += 1
	_time_since_death = 0.0
	_recent_kills_without_damage = 0
	if adaptive_difficulty:
		recalculate_difficulty()

func on_level_cleared() -> void:
	_consecutive_deaths = 0

func on_player_bullet_hit() -> void:
	_recent_hits += 1

func on_player_bullet_miss() -> void:
	_recent_misses += 1