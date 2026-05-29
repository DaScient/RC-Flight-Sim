## agentic_scenery_generator.gd
## Phase 5.1.2 - turns an LLM scenery description into a runnable Godot scene:
## a flat Terrain3D-style ground plane, a runway strip, and whitelisted props
## (trees, hangars, windsocks...). The result can be saved as a .tscn and loaded
## like any hand-made scenery.
##
## Spec validation lives in AgenticUtils.parse_scenery_spec (unit-tested); this
## class only builds nodes from an already-validated spec and saves them.
class_name AgenticSceneryGenerator
extends RefCounted

const SCENERY_DIR := "user://scenery/generated/"

## Build the user prompt sent to the LLM for [param description].
static func build_prompt(description: String) -> String:
	return "Design this RC flying field: %s" % description.strip_edges()

## Process the LLM's JSON reply into a validated, complete scenery spec.
func process_response(content: String) -> Dictionary:
	var block: Variant = AgenticUtils.extract_json_block(content)
	var data: Dictionary = block if block is Dictionary else {}
	return AgenticUtils.parse_scenery_spec(data)

## Build a scene graph (Node3D) from a validated spec. Uses only primitive
## meshes so it works in GL Compatibility with no external assets.
func build_scene(spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "GeneratedAirfield"

	var size: float = float(spec.get("size_m", 500.0))
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(size, size)
	ground.mesh = ground_mesh
	root.add_child(ground)

	var runway := MeshInstance3D.new()
	runway.name = "Runway"
	var runway_mesh := BoxMesh.new()
	runway_mesh.size = Vector3(10.0, 0.05, float(spec.get("runway_length_m", 300.0)))
	runway.mesh = runway_mesh
	runway.position = Vector3(0.0, 0.03, 0.0)
	root.add_child(runway)

	var props: Array = spec.get("objects", [])
	for entry in props:
		if not (entry is Dictionary):
			continue
		var prop := _build_prop(entry)
		if prop != null:
			root.add_child(prop)
	return root

func _build_prop(entry: Dictionary) -> MeshInstance3D:
	var ptype := String(entry.get("type", ""))
	var node := MeshInstance3D.new()
	node.name = ptype.capitalize()
	var height := 4.0
	match ptype:
		"tree":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.2
			cyl.bottom_radius = 0.4
			cyl.height = 5.0
			node.mesh = cyl
			height = 5.0
		"hangar":
			var box := BoxMesh.new()
			box.size = Vector3(12.0, 6.0, 10.0)
			node.mesh = box
			height = 6.0
		"windsock":
			var pole := CylinderMesh.new()
			pole.top_radius = 0.05
			pole.bottom_radius = 0.05
			pole.height = 6.0
			node.mesh = pole
			height = 6.0
		"pylon":
			var p := CylinderMesh.new()
			p.top_radius = 0.1
			p.bottom_radius = 0.1
			p.height = 3.0
			node.mesh = p
			height = 3.0
		"tent":
			var t := PrismMesh.new()
			t.size = Vector3(4.0, 2.5, 4.0)
			node.mesh = t
			height = 2.5
		"rock":
			node.mesh = SphereMesh.new()
			height = 1.0
		_:
			return null
	node.position = Vector3(float(entry.get("x", 0.0)), height * 0.5, float(entry.get("z", 0.0)))
	return node

## Build and save a scenery scene to user://scenery/generated/<slug>.tscn.
## Returns the saved path, or "" on failure.
func save_scene(spec: Dictionary) -> String:
	if not DirAccess.dir_exists_absolute(SCENERY_DIR):
		if DirAccess.make_dir_recursive_absolute(SCENERY_DIR) != OK:
			return ""
	var scene_root := build_scene(spec)
	# Ownership must be set so children are serialised into the PackedScene.
	for child in scene_root.get_children():
		child.owner = scene_root
	var packed := PackedScene.new()
	if packed.pack(scene_root) != OK:
		scene_root.free()
		return ""
	var slug := AgenticUtils.slugify(String(spec.get("name", "airfield")))
	var path := SCENERY_DIR + slug + ".tscn"
	var err := ResourceSaver.save(packed, path)
	scene_root.free()
	return path if err == OK else ""
