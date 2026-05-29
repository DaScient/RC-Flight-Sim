## scene_manager.gd
## Autoload singleton for scene transitions with optional loading screen support.
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal scene_loading_started(scene_path: String)
signal scene_loading_finished(scene_path: String)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const LOADING_SCREEN_PATH := "res://scenes/ui/loading_screen.tscn"

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _current_scene_path: String = ""
var _loading_screen: Node = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	# Store initial scene path
	var root := get_tree().root
	var current := root.get_child(root.get_child_count() - 1)
	_current_scene_path = current.scene_file_path

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Transition to a new scene. Optionally show a loading screen for heavy scenes.
func go_to_scene(scene_path: String, use_loading_screen: bool = false) -> void:
	scene_loading_started.emit(scene_path)
	if use_loading_screen:
		await _show_loading_screen()
		await _load_scene_async(scene_path)
	else:
		_load_scene_immediate(scene_path)

## Reload the current scene
func reload_scene() -> void:
	go_to_scene(_current_scene_path)

## Return to main menu
func go_to_main_menu() -> void:
	go_to_scene("res://scenes/ui/main_menu.tscn")

## Go to a flight scene with a given aircraft and scenery
func start_flight(aircraft: String, scenery: String) -> void:
	SettingsManager.set_setting("aircraft", aircraft)
	SettingsManager.set_setting("scenery", scenery)
	go_to_scene("res://scenes/main.tscn", true)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------
func _load_scene_immediate(scene_path: String) -> void:
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("[SceneManager] Failed to load scene: %s (err %d)" % [scene_path, err])
		return
	_current_scene_path = scene_path
	scene_loading_finished.emit(scene_path)

func _show_loading_screen() -> void:
	# Show loading overlay if available
	if ResourceLoader.exists(LOADING_SCREEN_PATH):
		var screen_scene := load(LOADING_SCREEN_PATH) as PackedScene
		if screen_scene:
			_loading_screen = screen_scene.instantiate()
			get_tree().root.add_child(_loading_screen)
	await get_tree().process_frame

func _load_scene_async(scene_path: String) -> void:
	ResourceLoader.load_threaded_request(scene_path)
	while true:
		var status := ResourceLoader.load_threaded_get_status(scene_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			push_error("[SceneManager] Async load failed: %s" % scene_path)
			_hide_loading_screen()
			return
		await get_tree().process_frame

	var packed_scene := ResourceLoader.load_threaded_get(scene_path) as PackedScene
	_hide_loading_screen()

	if packed_scene:
		get_tree().change_scene_to_packed(packed_scene)
		_current_scene_path = scene_path
		scene_loading_finished.emit(scene_path)

func _hide_loading_screen() -> void:
	if _loading_screen and is_instance_valid(_loading_screen):
		_loading_screen.queue_free()
		_loading_screen = null
