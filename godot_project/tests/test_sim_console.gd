## test_sim_console.gd
## Unit tests for the sim console command parser (Part 3A). Exercises the
## branches that don't require a live FDM (help, usage, unknown commands).
class_name TestSimConsole
extends RefCounted

const SimConsole = preload("res://scripts/debug/sim_console.gd")

func _make() -> Object:
	var c: Object = SimConsole.new()
	c.aircraft = null
	return c

func test_help_lists_commands(t) -> void:
	var c := _make()
	var out: String = c.execute("help")
	t.assert_true(out.contains("sim.set_property"), "help lists set_property")
	c.free()

func test_empty_line_is_noop(t) -> void:
	var c := _make()
	t.assert_true(c.execute("   ") == "", "blank line returns empty")
	c.free()

func test_unknown_command(t) -> void:
	var c := _make()
	t.assert_true(c.execute("frobnicate").contains("Unknown command"), "unknown reported")
	c.free()

func test_set_property_usage(t) -> void:
	var c := _make()
	t.assert_true(c.execute("sim.set_property").contains("Usage"), "usage on missing args")
	c.free()

func test_set_property_without_fdm(t) -> void:
	var c := _make()
	t.assert_true(c.execute("sim.set_property fcs/throttle-cmd-norm 0.5").contains("No FDM"), "no fdm handled")
	c.free()
