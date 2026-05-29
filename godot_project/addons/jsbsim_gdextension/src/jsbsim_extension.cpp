/**
 * jsbsim_extension.cpp
 *
 * Godot 4 GDExtension that wraps JSBSim for RC-Flight-Sim.
 * Exposes a JSBSimFDM Node with load_aircraft(), set_property(),
 * get_property(), and update() methods that delegate to JSBSim::FGFDMExec.
 *
 * Build instructions (see CMakeLists.txt and build_instructions.md):
 *   cmake -B build -DCMAKE_BUILD_TYPE=Release
 *   cmake --build build --config Release
 */

#include "jsbsim_extension.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

// JSBSim headers (available after cloning JSBSim as submodule)
#ifdef HAS_JSBSIM
#include <FGFDMExec.h>
#include <initialization/FGInitialCondition.h>
#include <models/propulsion/FGEngine.h>
#include <models/propulsion/FGThruster.h>
#endif

using namespace godot;

// ---------------------------------------------------------------------------
// GDExtension entry points
// ---------------------------------------------------------------------------
extern "C" {

GDExtensionBool GDE_EXPORT jsbsim_init(
    GDExtensionInterfaceGetProcAddress p_get_proc_address,
    const GDExtensionClassLibraryPtr   p_library,
    GDExtensionInitialization*         r_initialization)
{
    godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer(initialize_jsbsim_module);
    init_obj.register_terminator(uninitialize_jsbsim_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}

} // extern "C"

void initialize_jsbsim_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
    ClassDB::register_class<JSBSimFDM>();
}

void uninitialize_jsbsim_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
}

// ---------------------------------------------------------------------------
// JSBSimFDM implementation
// ---------------------------------------------------------------------------
JSBSimFDM::JSBSimFDM() {
#ifdef HAS_JSBSIM
    _fdm_exec = std::make_unique<JSBSim::FGFDMExec>();
    _fdm_exec->SetDebugLevel(0);
    // Default JSBSim data path – override via set_root_path()
    _fdm_exec->SetRootDir(SGPath("./"));
#endif
    _is_loaded = false;
    _dt        = 1.0 / 60.0;
}

JSBSimFDM::~JSBSimFDM() {
#ifdef HAS_JSBSIM
    _fdm_exec.reset();
#endif
}

void JSBSimFDM::_bind_methods() {
    ClassDB::bind_method(D_METHOD("load_aircraft", "xml_path"),   &JSBSimFDM::load_aircraft);
    ClassDB::bind_method(D_METHOD("set_property",  "name", "value"), &JSBSimFDM::set_property);
    ClassDB::bind_method(D_METHOD("get_property",  "name"),       &JSBSimFDM::get_property);
    ClassDB::bind_method(D_METHOD("get_property_tree"),           &JSBSimFDM::get_property_tree);
    ClassDB::bind_method(D_METHOD("update",        "delta"),      &JSBSimFDM::update);
    ClassDB::bind_method(D_METHOD("reset"),                       &JSBSimFDM::reset);
    ClassDB::bind_method(D_METHOD("set_root_path", "path"),       &JSBSimFDM::set_root_path);
    ClassDB::bind_method(D_METHOD("is_loaded"),                   &JSBSimFDM::is_loaded);
}

bool JSBSimFDM::load_aircraft(const String& p_xml_path) {
#ifdef HAS_JSBSIM
    if (!_fdm_exec) return false;

    std::string xml_path = p_xml_path.utf8().get_data();
    // JSBSim expects the aircraft directory and model name separately
    // Assume p_xml_path is full path like "res://assets/aircraft/trainer/trainer.xml"
    // which has already been mapped to an absolute filesystem path.

    _fdm_exec->LoadModel(SGPath(xml_path), false);
    _fdm_exec->RunIC();
    _is_loaded = true;
    UtilityFunctions::print("[JSBSimFDM] Loaded aircraft: " + p_xml_path);
    return true;
#else
    UtilityFunctions::print("[JSBSimFDM] JSBSim not compiled in – stub mode.");
    _is_loaded = false;
    return false;
#endif
}

void JSBSimFDM::set_property(const String& p_name, double p_value) {
#ifdef HAS_JSBSIM
    if (!_fdm_exec || !_is_loaded) return;
    _fdm_exec->SetPropertyValue(p_name.utf8().get_data(), p_value);
#endif
}

double JSBSimFDM::get_property(const String& p_name) {
#ifdef HAS_JSBSIM
    if (!_fdm_exec || !_is_loaded) return 0.0;
    return _fdm_exec->GetPropertyValue(p_name.utf8().get_data());
#else
    return 0.0;
#endif
}

Dictionary JSBSimFDM::get_property_tree() {
    Dictionary out;
#ifdef HAS_JSBSIM
    if (!_fdm_exec || !_is_loaded) return out;

    // Curated set of high-value properties for the telemetry/HUD overlay.
    // NOTE: JSBSim exposes a full FGPropertyManager tree; enumerating every
    // node is possible via FGPropertyNode recursion. We expose a stable,
    // documented subset here for performance and a clear UI contract.
    // TODO: add optional full-tree recursion behind a flag for research use.
    static const char* kPaths[] = {
        "velocities/vt-fps",
        "velocities/mach",
        "position/h-sl-ft",
        "position/h-agl-ft",
        "aero/alpha-deg",
        "aero/beta-deg",
        "aero/qbar-psf",
        "forces/fbx-aero-lbs",
        "forces/fbz-aero-lbs",
        "moments/m-aero-lbsft",
        "aero/cl-squared",
        "propulsion/engine/thrust-lbs",
        "propulsion/engine/rpm",
        "fcs/throttle-cmd-norm",
        "fcs/aileron-cmd-norm",
        "fcs/elevator-cmd-norm",
        "fcs/rudder-cmd-norm",
        "attitude/roll-rad",
        "attitude/pitch-rad",
        "attitude/psi-rad",
    };
    for (const char* path : kPaths) {
        out[String(path)] = _fdm_exec->GetPropertyValue(path);
    }
#endif
    return out;
}

void JSBSimFDM::update(double p_delta) {
#ifdef HAS_JSBSIM
    if (!_fdm_exec || !_is_loaded) return;
    // JSBSim runs at a fixed internal rate; run multiple frames to match godot delta
    int steps = static_cast<int>(p_delta / _dt + 0.5);
    steps = std::max(1, std::min(steps, 10));
    for (int i = 0; i < steps; ++i) {
        _fdm_exec->Run();
    }
#endif
}

void JSBSimFDM::reset() {
#ifdef HAS_JSBSIM
    if (!_fdm_exec) return;
    _fdm_exec->RunIC();
#endif
}

void JSBSimFDM::set_root_path(const String& p_path) {
#ifdef HAS_JSBSIM
    if (!_fdm_exec) return;
    _fdm_exec->SetRootDir(SGPath(p_path.utf8().get_data()));
#endif
}

bool JSBSimFDM::is_loaded() const {
    return _is_loaded;
}
