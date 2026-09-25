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
	table->name = name;
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

// A localized string's locale columns follow its enUS one; a client fills only its own.
String WowDBC::get_text(int row, const Variant &col) const {
	const int base = column(col);
	const std::string text = dbc.getString(row, base + locale);
	if (!text.empty()) {
		return String::utf8(text.c_str());
	}
	if (!translations.empty()) {
		const auto found = translations.find(text_key(row, col).utf8().get_data());
		if (found != translations.end()) {
			return String::utf8(found->second.c_str());
		}
	}
	return String::utf8(dbc.getString(row, base).c_str());
}

// Table, layout column name (or index) and record ID, such as Spell.Name.133.
String WowDBC::text_key(int row, const Variant &col) const {
	const int index = column(col);
	String field = String::num_int64(index);
	const Array names = columns.keys();
	for (int i = 0; i < names.size(); i++) {
		if (static_cast<int>(columns[names[i]]) == index) {
			field = names[i];
			break;
		}
	}
	return name + String(".") + field + String(".") + String::num_int64(dbc.getUInt32(row, 0));
}

void WowDBC::set_translations(const Dictionary &p_translations) {
	translations.clear();
	const Array keys = p_translations.keys();
	for (int i = 0; i < keys.size(); i++) {
		translations[String(keys[i]).utf8().get_data()] = String(p_translations[keys[i]]).utf8().get_data();
	}
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
	ClassDB::bind_method(D_METHOD("get_text", "row", "col"), &WowDBC::get_text);
	ClassDB::bind_method(D_METHOD("column", "col"), &WowDBC::column);
	ClassDB::bind_method(D_METHOD("text_key", "row", "col"), &WowDBC::text_key);
	ClassDB::bind_static_method("WowDBC", D_METHOD("set_translations", "translations"), &WowDBC::set_translations);
	ClassDB::bind_static_method("WowDBC", D_METHOD("set_locale", "locale"), &WowDBC::set_locale);
	ClassDB::bind_static_method("WowDBC", D_METHOD("get_locale"), &WowDBC::get_locale);
}

} // namespace godot
