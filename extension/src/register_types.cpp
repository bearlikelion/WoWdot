#include "wow_archive.h"
#include "wow_coords.h"
#include "wow_dbc.h"
#include "wow_loader.h"
#include "wow_session.h"
#include "wow_streamer.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void WowCoords::_bind_methods() {
	ClassDB::bind_static_method("WowCoords", D_METHOD("to_godot", "wow"), &WowCoords::to_godot);
	ClassDB::bind_static_method("WowCoords", D_METHOD("from_godot", "godot"), &WowCoords::from_godot);
}

static void initialize_wowgd_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(WowArchive);
	GDREGISTER_CLASS(WowDBC);
	GDREGISTER_CLASS(WowLoader);
	GDREGISTER_CLASS(WowStreamer);
	GDREGISTER_CLASS(WowSession);
	GDREGISTER_ABSTRACT_CLASS(WowCoords);
}

static void uninitialize_wowgd_module(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT wowgd_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_wowgd_module);
	init_obj.register_terminator(uninitialize_wowgd_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
