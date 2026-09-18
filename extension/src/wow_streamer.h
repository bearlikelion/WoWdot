#pragma once

#include "wow_loader.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <mutex>
#include <unordered_map>
#include <vector>

namespace godot {

// Builds map tiles on worker threads and hands them back through poll(), so no script runs off the main thread.
class WowStreamer : public RefCounted {
	GDCLASS(WowStreamer, RefCounted)

	Ref<WowLoader> loader;
	bool threaded = true;
	bool load_placements = true;

	std::mutex mutex;
	uint64_t generation = 0;
	std::unordered_map<int64_t, int> refs;
	std::vector<Dictionary> results;
	std::vector<int64_t> tasks;

	void work(const String &map_name, const Vector2i &tile, uint64_t p_generation);
	bool claim(int64_t unique_id, uint64_t p_generation);
	static void free_result(const Dictionary &result);

protected:
	static void _bind_methods();

public:
	~WowStreamer() override;

	void set_loader(const Ref<WowLoader> &p_loader) { loader = p_loader; }
	Ref<WowLoader> get_loader() const { return loader; }
	void set_threaded(bool p_threaded) { threaded = p_threaded; }
	bool is_threaded() const { return threaded; }
	void set_load_placements(bool p_load) { load_placements = p_load; }
	bool get_load_placements() const { return load_placements; }

	void request(const String &map_name, const Vector2i &tile);
	Array poll();
	PackedInt64Array release(const PackedInt64Array &unique_ids);
	void reset();
	int pending() const { return tasks.size(); }
};

} // namespace godot
