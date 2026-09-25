#pragma once

#include "wow_archive.h"

#include "pipeline/dbc_loader.hpp"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <string>
#include <unordered_map>

namespace godot {

// A DBC table; columns are an index or a field name from the profile's dbc_layouts.json.
class WowDBC : public RefCounted {
	GDCLASS(WowDBC, RefCounted)

	wowee::pipeline::DBCFile dbc;
	Dictionary columns;
	String name;

	static inline int locale = 0;
	static inline std::unordered_map<std::string, std::string> translations;

protected:
	static void _bind_methods();

public:
	static Ref<WowDBC> open(const Ref<WowArchive> &archive, const String &name);

	int row_count() const { return dbc.getRecordCount(); }
	int field_count() const { return dbc.getFieldCount(); }
	int find(int64_t id) const { return dbc.findRecordById(static_cast<uint32_t>(id)); }
	int column(const Variant &col) const;
	int64_t get_uint(int row, const Variant &col) const;
	int64_t get_int(int row, const Variant &col) const;
	double get_float(int row, const Variant &col) const;
	String get_string(int row, const Variant &col) const;
	String get_text(int row, const Variant &col) const;
	String text_key(int row, const Variant &col) const;

	static void set_locale(int p_locale) { locale = p_locale; }
	static int get_locale() { return locale; }
	static void set_translations(const Dictionary &p_translations);

	const wowee::pipeline::DBCFile &file() const { return dbc; }
};

} // namespace godot
