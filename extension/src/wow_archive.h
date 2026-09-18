#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace godot {

// Read-only view over a 1.12.1 client's MPQ chain, later archives overriding earlier ones.
class WowArchive : public RefCounted {
	GDCLASS(WowArchive, RefCounted)

	std::vector<void *> archives; // Highest priority first.
	PackedStringArray archive_names;
	mutable std::mutex mutex;

	void close();
	bool open_file(const std::string &path, void **r_file) const;

protected:
	static void _bind_methods();

public:
	~WowArchive() override;

	Error open(const String &data_dir);
	bool has(const String &path) const;
	PackedByteArray read(const String &path) const;
	PackedStringArray find(const String &mask) const;
	PackedStringArray get_archive_names() const { return archive_names; }

	bool read_bytes(const std::string &path, std::vector<uint8_t> &r_data) const;
	static std::string normalize(const String &path);
};

} // namespace godot
