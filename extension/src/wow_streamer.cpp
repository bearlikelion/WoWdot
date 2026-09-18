#include "wow_streamer.h"

#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace godot {

WowStreamer::~WowStreamer() {
	for (int64_t task : tasks) {
		WorkerThreadPool::get_singleton()->wait_for_task_completion(task);
	}
	for (const Dictionary &result : results) {
		free_result(result);
	}
}

void WowStreamer::request(const String &map_name, const Vector2i &tile) {
	ERR_FAIL_COND(loader.is_null());
	uint64_t current = 0;
	{
		std::lock_guard<std::mutex> lock(mutex);
		current = generation;
	}
	if (!threaded) {
		work(map_name, tile, current);
		return;
	}
	const Callable task = callable_mp(this, &WowStreamer::work).bind(map_name, tile, current);
	tasks.push_back(WorkerThreadPool::get_singleton()->add_task(task, false, "WowStreamer tile"));
}

void WowStreamer::work(const String &map_name, const Vector2i &tile, uint64_t p_generation) {
	Node3D *node = loader->load_adt(map_name, tile.x, tile.y);
	PackedInt64Array tile_refs;
	Dictionary built;
	if (node && load_placements) {
		const Array placements = node->get_meta("placements", Array());
		Array doodads;
		for (int i = 0; i < placements.size(); i++) {
			const Dictionary placement = placements[i];
			const int64_t unique_id = placement["unique_id"];
			tile_refs.push_back(unique_id);
			if (!claim(unique_id, p_generation)) {
				continue;
			}
			if (String(placement["kind"]) != "wmo") {
				doodads.push_back(placement);
				continue;
			}
			Node3D *wmo = loader->load_wmo(placement["path"], placement["doodad_set"]);
			if (wmo) {
				wmo->set_transform(placement["transform"]);
				built[unique_id] = wmo;
			}
		}
		// ponytail: border doodads live on the tile that claimed them and hide when it unloads.
		node->add_child(loader->build_static_models(doodads));
	}
	Dictionary result;
	result["tile"] = tile;
	result["node"] = node;
	result["refs"] = tile_refs;
	result["built"] = built;
	result["generation"] = p_generation;
	std::lock_guard<std::mutex> lock(mutex);
	results.push_back(result);
}

Array WowStreamer::poll() {
	for (size_t i = 0; i < tasks.size();) {
		if (WorkerThreadPool::get_singleton()->is_task_completed(tasks[i])) {
			WorkerThreadPool::get_singleton()->wait_for_task_completion(tasks[i]);
			tasks.erase(tasks.begin() + i);
		} else {
			i++;
		}
	}
	std::vector<Dictionary> done;
	uint64_t current = 0;
	{
		std::lock_guard<std::mutex> lock(mutex);
		done.swap(results);
		current = generation;
	}
	Array out;
	for (const Dictionary &result : done) {
		if (uint64_t(int64_t(result["generation"])) == current) {
			out.push_back(result);
		} else {
			free_result(result);
		}
	}
	return out;
}

bool WowStreamer::claim(int64_t unique_id, uint64_t p_generation) {
	std::lock_guard<std::mutex> lock(mutex);
	if (p_generation != generation) {
		return false;
	}
	return refs[unique_id]++ == 0;
}

PackedInt64Array WowStreamer::release(const PackedInt64Array &unique_ids) {
	PackedInt64Array unreferenced;
	std::lock_guard<std::mutex> lock(mutex);
	for (int64_t unique_id : unique_ids) {
		auto it = refs.find(unique_id);
		if (it != refs.end() && --it->second <= 0) {
			refs.erase(it);
			unreferenced.push_back(unique_id);
		}
	}
	return unreferenced;
}

void WowStreamer::reset() {
	std::lock_guard<std::mutex> lock(mutex);
	generation++;
	refs.clear();
}

void WowStreamer::free_result(const Dictionary &result) {
	if (Object *node = result["node"]) {
		memdelete(node);
	}
	const Array built = Dictionary(result["built"]).values();
	for (int i = 0; i < built.size(); i++) {
		if (Object *wmo = built[i]) {
			memdelete(wmo);
		}
	}
}

void WowStreamer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_loader", "loader"), &WowStreamer::set_loader);
	ClassDB::bind_method(D_METHOD("get_loader"), &WowStreamer::get_loader);
	ClassDB::bind_method(D_METHOD("set_threaded", "threaded"), &WowStreamer::set_threaded);
	ClassDB::bind_method(D_METHOD("is_threaded"), &WowStreamer::is_threaded);
	ClassDB::bind_method(D_METHOD("set_load_placements", "load_placements"), &WowStreamer::set_load_placements);
	ClassDB::bind_method(D_METHOD("get_load_placements"), &WowStreamer::get_load_placements);
	ClassDB::bind_method(D_METHOD("request", "map_name", "tile"), &WowStreamer::request);
	ClassDB::bind_method(D_METHOD("poll"), &WowStreamer::poll);
	ClassDB::bind_method(D_METHOD("release", "unique_ids"), &WowStreamer::release);
	ClassDB::bind_method(D_METHOD("reset"), &WowStreamer::reset);
	ClassDB::bind_method(D_METHOD("pending"), &WowStreamer::pending);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "loader", PROPERTY_HINT_RESOURCE_TYPE, "WowLoader"), "set_loader", "get_loader");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "threaded"), "set_threaded", "is_threaded");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "load_placements"), "set_load_placements", "get_load_placements");
}

} // namespace godot
