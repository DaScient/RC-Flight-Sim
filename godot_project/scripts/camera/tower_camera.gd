## tower_camera.gd
## Blends between predefined tower positions based on aircraft distance/bearing.
class_name TowerCamera
extends Camera3D

## Tower positions (world coordinates) – set in editor via exported array
@export var tower_positions: Array[Vector3] = []
@export var blend_speed: float = 2.0
@export var track_speed: float = 5.0

var target: Node3D = null

var _active_tower_idx: int  = 0

func _ready() -> void:
	set_as_top_level(true)
	if tower_positions.is_empty():
		# Default: single tower at origin offset
		tower_positions.append(Vector3(0.0, 5.0, 30.0))

func _process(delta: float) -> void:
	if target == null:
		return

	var aircraft_pos := target.global_position
	_select_best_tower(aircraft_pos)

	var desired_pos: Vector3 = tower_positions[_active_tower_idx]
	global_position = global_position.lerp(desired_pos, clampf(blend_speed * delta, 0.0, 1.0))

	var current_basis := global_transform.basis
	var desired_transform := global_transform.looking_at(aircraft_pos, Vector3.UP)
	global_transform.basis = current_basis.slerp(desired_transform.basis, clampf(track_speed * delta, 0.0, 1.0))

func _select_best_tower(aircraft_pos: Vector3) -> void:
	if tower_positions.size() <= 1:
		_active_tower_idx = 0
		return
	# Pick the tower with the best view angle (roughly closest + facing)
	var best_idx := 0
	var best_score := -INF
	for i in tower_positions.size():
		var dist := tower_positions[i].distance_to(aircraft_pos)
		var score := -dist  # simple: prefer closest
		if score > best_score:
			best_score = score
			best_idx = i
	_active_tower_idx = best_idx
