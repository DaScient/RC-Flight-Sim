## sim_console.gd
## Lightweight developer console for runtime simulation tweaking (Part 3A).
##
## Commands (whitespace-separated):
##   sim.set_property <path> <value>   Write a JSBSim/FDM property.
##   sim.get_property <path>           Read and print a property value.
##   sim.tree                          Dump the property-tree snapshot.
##   help                              List commands.
##
## The console logic lives in execute(), which returns a String result so it
## can be unit-tested headlessly and driven by any UI. Attach this to a
## CanvasLayer and wire a LineEdit + RichTextLabel to display output, or call
## execute() directly from another script.
extends CanvasLayer

signal output_logged(text: String)

## Optional UI nodes; the console works without them via execute().
@export var input_field: LineEdit = null
@export var output_label: RichTextLabel = null

## The aircraft whose FDM the console operates on. Set by the scene/controller.
var aircraft: Node = null

func _ready() -> void:
	if input_field != null:
		input_field.text_submitted.connect(_on_text_submitted)

func _on_text_submitted(line: String) -> void:
	var result := execute(line)
	_log(result)
	if input_field != null:
		input_field.clear()

## Execute a single console command line and return a human-readable result.
func execute(line: String) -> String:
	var trimmed := line.strip_edges()
	if trimmed == "":
		return ""
	var parts := trimmed.split(" ", false)
	var cmd: String = parts[0]
	match cmd:
		"help":
			return "Commands: sim.set_property <path> <value> | sim.get_property <path> | sim.tree | help"
		"sim.set_property":
			if parts.size() < 3:
				return "Usage: sim.set_property <path> <value>"
			return _cmd_set_property(parts[1], parts[2])
		"sim.get_property":
			if parts.size() < 2:
				return "Usage: sim.get_property <path>"
			return _cmd_get_property(parts[1])
		"sim.tree":
			return _cmd_tree()
		_:
			return "Unknown command: %s (try 'help')" % cmd

# ---------------------------------------------------------------------------
# Command implementations
# ---------------------------------------------------------------------------
func _cmd_set_property(path: String, value_str: String) -> String:
	var fdm := _fdm()
	if fdm == null:
		return "No FDM available."
	if not value_str.is_valid_float():
		return "Value '%s' is not a number." % value_str
	var value := value_str.to_float()
	var ok: bool = fdm.set_property(path, value)
	return ("Set %s = %s" % [path, value]) if ok else ("Property not writable: %s" % path)

func _cmd_get_property(path: String) -> String:
	var fdm := _fdm()
	if fdm == null:
		return "No FDM available."
	var tree: Dictionary = fdm.get_property_tree()
	if tree.has(path):
		return "%s = %s" % [path, tree[path]]
	return "Property not found in snapshot: %s" % path

func _cmd_tree() -> String:
	var fdm := _fdm()
	if fdm == null:
		return "No FDM available."
	var tree: Dictionary = fdm.get_property_tree()
	var lines: PackedStringArray = []
	for key in tree.keys():
		lines.append("%s = %s" % [key, tree[key]])
	return "\n".join(lines)

func _fdm() -> Object:
	if aircraft == null:
		return null
	return aircraft.get("fdm")

func _log(text: String) -> void:
	if text == "":
		return
	if output_label != null:
		output_label.append_text(text + "\n")
	output_logged.emit(text)
