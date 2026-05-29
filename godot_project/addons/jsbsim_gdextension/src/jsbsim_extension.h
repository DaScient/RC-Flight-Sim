/**
 * jsbsim_extension.h
 *
 * Header for the JSBSimFDM GDExtension node.
 */

#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/binder_common.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#ifdef HAS_JSBSIM
#include <FGFDMExec.h>
#include <memory>
#endif

using namespace godot;

// ---------------------------------------------------------------------------
// Forward declarations for module init/deinit
// ---------------------------------------------------------------------------
void initialize_jsbsim_module(ModuleInitializationLevel p_level);
void uninitialize_jsbsim_module(ModuleInitializationLevel p_level);

// ---------------------------------------------------------------------------
// JSBSimFDM: Godot Node wrapping JSBSim::FGFDMExec
// ---------------------------------------------------------------------------
class JSBSimFDM : public Node {
    GDCLASS(JSBSimFDM, Node)

public:
    JSBSimFDM();
    ~JSBSimFDM();

    /// Load a JSBSim aircraft model from an XML file path.
    bool   load_aircraft(const String& p_xml_path);

    /// Set a named JSBSim property (e.g. "fcs/throttle-cmd-norm").
    void   set_property(const String& p_name, double p_value);

    /// Get a named JSBSim property value.
    double get_property(const String& p_name);

    /// Return a curated snapshot of the JSBSim property tree as a Dictionary
    /// mapping property path (String) -> value (double). Used to drive the
    /// in-game telemetry/HUD overlay without hard-coding individual getters.
    Dictionary get_property_tree();

    /// Advance simulation by p_delta seconds.
    void   update(double p_delta);

    /// Reset the simulation to initial conditions.
    void   reset();

    /// Set the JSBSim data root directory (aircraft/, engines/, etc.)
    void   set_root_path(const String& p_path);

    /// Returns true if an aircraft is currently loaded.
    bool   is_loaded() const;

protected:
    static void _bind_methods();

private:
#ifdef HAS_JSBSIM
    std::unique_ptr<JSBSim::FGFDMExec> _fdm_exec;
#endif
    bool   _is_loaded = false;
    double _dt        = 1.0 / 60.0;   ///< JSBSim fixed time step (seconds)
};
