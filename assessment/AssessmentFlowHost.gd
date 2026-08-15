extends Node
## 场景流程控制器 (Autoload)
## 管理场景切换、过渡动画

const SCENE_PATHS := {
	"registration": "res://ui/assessment/RegistrationScreen.tscn",
	"provider_setup": "res://ui/assessment/ProviderSetupScreen.tscn",
	"politeness_house": "res://ui/rpg/PolitenessHouseRpg.tscn",
	"sunshine_market": "res://ui/rpg/SunshineMarketRpg.tscn",
	"results": "res://ui/assessment/ResultsScreen.tscn",
}

var _current_scene: Node = null
var _transition_layer: CanvasLayer = null
var _is_transitioning: bool = false

signal scene_changed(scene_name: String)

func _ready() -> void:
	# 创建过渡层
	_transition_layer = CanvasLayer.new()
	_transition_layer.layer = 100
	add_child(_transition_layer)
	# 记录初始场景（主场景），确保首次切换时能正确释放
	_current_scene = get_tree().current_scene

## 切换到指定场景
func change_scene(scene_name: String) -> void:
	if _is_transitioning:
		return
	if not SCENE_PATHS.has(scene_name):
		push_error("[AssessmentFlowHost] 未知场景: %s" % scene_name)
		return
	
	_is_transitioning = true
	
	# 创建单一遮罩，用于淡出和淡入
	var fade_rect := ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_transition_layer.add_child(fade_rect)
	
	# 淡出：透明 → 黑色
	var tween_out := create_tween()
	tween_out.tween_property(fade_rect, "color:a", 1.0, 0.3)
	await tween_out.finished
	
	# 释放当前场景
	if _current_scene and is_instance_valid(_current_scene):
		_current_scene.queue_free()
	
	# 加载新场景
	var scene_path: String = SCENE_PATHS[scene_name]
	var packed_scene := load(scene_path)
	if packed_scene == null:
		push_error("[AssessmentFlowHost] 无法加载场景: %s" % scene_path)
		fade_rect.queue_free()
		_is_transitioning = false
		return
	
	_current_scene = packed_scene.instantiate()
	get_tree().root.add_child(_current_scene)
	get_tree().current_scene = _current_scene
	
	# 淡入：黑色 → 透明，然后移除遮罩
	var tween_in := create_tween()
	tween_in.tween_property(fade_rect, "color:a", 0.0, 0.3)
	tween_in.tween_callback(fade_rect.queue_free)
	await tween_in.finished
	
	_is_transitioning = false
	scene_changed.emit(scene_name)
	print("[AssessmentFlowHost] 切换到场景: %s" % scene_name)

## 从注册页直接进入板块一
func go_to_politeness_house() -> void:
	await change_scene("politeness_house")

## 从板块一进入板块二
func go_to_sunshine_market() -> void:
	await change_scene("sunshine_market")

## 从板块二进入结果页
func go_to_results() -> void:
	await change_scene("results")

## 返回注册页（重新开始）
func go_to_registration() -> void:
	await change_scene("registration")

## 前往API设置页
func go_to_provider_setup() -> void:
	await change_scene("provider_setup")

## 退出游戏
func quit_game() -> void:
	get_tree().quit()
