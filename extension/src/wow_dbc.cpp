#include "wow_dbc.h"

#include "wow_profile.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {

Ref<WowDBC> WowDBC::open(const Ref<WowArchive> &archive, const String &name) {
	ERR_FAIL_COND_V(archive.is_null(), Ref<WowDBC>());
	std::vector<uint8_t> data;
	if (!archive->read_bytes(WowArchive::normalize("DBFilesClient/" + name + ".dbc"), data)) {
		UtilityFunctions::push_error("WowDBC: ", name, ".dbc not found");
		return Ref<WowDBC>();
	}
	Ref<WowDBC> table;
	table.instantiate();
	if (!table->dbc.load(data)) {
		UtilityFunctions::push_error("WowDBC: ", name, ".dbc failed to parse");
		return Ref<WowDBC>();
	}
	const Dictionary layouts = JSON::parse_string(FileAccess::get_file_as_string(wow_data_path("dbc_layouts.json")));
	table->columns = layouts.get(name, Dictionary());
	return table;
}

int WowDBC::column(const Variant &col) const {
	if (col.get_type() == Variant::INT) {
		return col;
	}
	const Variant index = columns.get(col, -1);
	ERR_FAIL_COND_V_MSG(static_cast<int>(index) < 0, 0, "WowDBC: unknown column " + String(col));
	return index;
}

int64_t WowDBC::get_uint(int row, const Variant &col) const {
	return dbc.getUInt32(row, column(col));
}

int64_t WowDBC::get_int(int row, const Variant &col) const {
	return dbc.getInt32(row, column(col));
}

double WowDBC::get_float(int row, const Variant &col) const {
	return dbc.getFloat(row, column(col));
}

String WowDBC::get_string(int row, const Variant &col) const {
	return String::utf8(dbc.getString(row, column(col)).c_str());
}

void WowDBC::_bind_methods() {
	ClassDB::bind_static_method("WowDBC", D_METHOD("open", "archive", "name"), &WowDBC::open);
	ClassDB::bind_method(D_METHOD("row_count"), &WowDBC::row_count);
	ClassDB::bind_method(D_METHOD("field_count"), &WowDBC::field_count);
	ClassDB::bind_method(D_METHOD("find", "id"), &WowDBC::find);
	ClassDB::bind_method(D_METHOD("get_uint", "row", "col"), &WowDBC::get_uint);
	ClassDB::bind_method(D_METHOD("get_int", "row", "col"), &WowDBC::get_int);
	ClassDB::bind_method(D_METHOD("get_float", "row", "col"), &WowDBC::get_float);
	ClassDB::bind_method(D_METHOD("get_string", "row", "col"), &WowDBC::get_string);
}

} // namespace godot
