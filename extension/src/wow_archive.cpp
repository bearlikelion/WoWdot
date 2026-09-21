#include "wow_archive.h"

#include "wow_profile.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <StormLib.h>

#include <algorithm>
#include <cctype>
#include <cstring>
#include <filesystem>
#include <set>
#include <unordered_map>

namespace godot {

namespace {

std::string to_lower(std::string s) {
	std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return std::tolower(c); });
	return s;
}

std::vector<std::string> classic_sequence() {
	std::vector<std::string> names = {
		"base.mpq", "backup.mpq", "dbc.mpq", "fonts.mpq", "interface.mpq", "misc.mpq",
		"model.mpq", "sound.mpq", "speech.mpq", "terrain.mpq", "texture.mpq", "wmo.mpq",
		"patch.mpq",
	};
	for (char c = '2'; c <= '9'; c++) {
		names.push_back(std::string("patch-") + c + ".mpq");
	}
	for (char c = 'a'; c <= 'z'; c++) {
		names.push_back(std::string("patch-") + c + ".mpq");
	}
	return names;
}

// The 3.3.5a chain; the locale folder's archives carry the DBCs and every string.
std::vector<std::string> wotlk_sequence(const std::string &locale) {
	const std::string suffix = "-" + locale + ".mpq";
	std::vector<std::string> names = {
		"common.mpq", "common-2.mpq", "expansion.mpq", "lichking.mpq",
		"locale" + suffix, "speech" + suffix, "expansion-locale" + suffix,
		"lichking-locale" + suffix, "expansion-speech" + suffix, "lichking-speech" + suffix,
		"patch.mpq",
	};
	for (char c = '2'; c <= '9'; c++) {
		names.push_back(std::string("patch-") + c + ".mpq");
	}
	names.push_back("patch-" + locale + ".mpq");
	for (char c = '2'; c <= '9'; c++) {
		names.push_back("patch-" + locale + "-" + c + ".mpq");
	}
	return names;
}

std::string locale_from(const std::unordered_map<std::string, std::filesystem::path> &on_disk) {
	for (const auto &entry : on_disk) {
		if (entry.first.rfind("locale-", 0) == 0 && entry.first.size() == 15) {
			return entry.first.substr(7, 4);
		}
	}
	return "enus";
}

} // namespace

WowArchive::~WowArchive() {
	close();
}

void WowArchive::close() {
	std::lock_guard<std::mutex> lock(mutex);
	for (void *archive : archives) {
		SFileCloseArchive(archive);
	}
	archives.clear();
	listfiles_loaded = false;
	archive_names.clear();
}

Error WowArchive::open(const String &data_dir) {
	close();
	namespace fs = std::filesystem;
	const fs::path dir(data_dir.utf8().get_data());
	std::error_code ec;
	std::unordered_map<std::string, fs::path> on_disk;
	for (const fs::directory_entry &entry : fs::directory_iterator(dir, ec)) {
		if (entry.is_regular_file()) {
			on_disk[to_lower(entry.path().filename().string())] = entry.path();
			continue;
		}
		// A locale folder holds archives of its own, and a root archive of the same name wins.
		std::error_code sub_ec;
		for (const fs::directory_entry &sub : fs::directory_iterator(entry.path(), sub_ec)) {
			const std::string name = to_lower(sub.path().filename().string());
			if (sub.is_regular_file() && name.size() > 4 && name.compare(name.size() - 4, 4, ".mpq") == 0) {
				on_disk.emplace(name, sub.path());
			}
		}
	}
	if (ec) {
		UtilityFunctions::push_error("WowArchive: cannot list ", data_dir);
		return ERR_FILE_NOT_FOUND;
	}

	const std::vector<std::string> sequence = std::strcmp(wow_profile().id, "wotlk") == 0
			? wotlk_sequence(locale_from(on_disk))
			: classic_sequence();

	std::lock_guard<std::mutex> lock(mutex);
	for (const std::string &name : sequence) {
		auto it = on_disk.find(name);
		if (it == on_disk.end()) {
			continue;
		}
		HANDLE archive = nullptr;
		if (!SFileOpenArchive(it->second.string().c_str(), 0, MPQ_OPEN_READ_ONLY | MPQ_OPEN_NO_LISTFILE | MPQ_OPEN_NO_ATTRIBUTES, &archive)) {
			UtilityFunctions::push_error("WowArchive: failed to open ", String(it->second.string().c_str()));
			continue;
		}
		archives.insert(archives.begin(), archive);
		archive_names.insert(0, String(it->second.filename().string().c_str()));
	}
	return archives.empty() ? ERR_FILE_NOT_FOUND : OK;
}

std::string WowArchive::normalize(const String &path) {
	std::string s = path.utf8().get_data();
	std::replace(s.begin(), s.end(), '/', '\\');
	return s;
}

bool WowArchive::open_file(const std::string &path, void **r_file) const {
	std::vector<std::string> candidates = { path };
	const std::string lower = to_lower(path);
	const size_t dot = lower.rfind('.');
	const std::string ext = dot == std::string::npos ? "" : lower.substr(dot);
	// ADTs and DBCs name models .mdx or .mdl while the archives store .m2, and the reverse also occurs.
	if (ext == ".mdx" || ext == ".mdl") {
		candidates.push_back(path.substr(0, dot) + ".m2");
	} else if (ext == ".m2") {
		candidates.push_back(path.substr(0, dot) + ".mdx");
	}
	for (const std::string &candidate : candidates) {
		for (void *archive : archives) {
			if (SFileOpenFileEx(archive, candidate.c_str(), SFILE_OPEN_FROM_MPQ, r_file)) {
				return true;
			}
		}
	}
	return false;
}

bool WowArchive::read_bytes(const std::string &path, std::vector<uint8_t> &r_data) const {
	std::lock_guard<std::mutex> lock(mutex);
	HANDLE file = nullptr;
	if (!open_file(path, &file)) {
		return false;
	}
	const DWORD size = SFileGetFileSize(file, nullptr);
	r_data.resize(size);
	DWORD read = 0;
	if (size > 0) {
		SFileReadFile(file, r_data.data(), size, &read, nullptr);
	}
	SFileCloseFile(file);
	return read == size;
}

bool WowArchive::has(const String &path) const {
	std::lock_guard<std::mutex> lock(mutex);
	HANDLE file = nullptr;
	if (!open_file(normalize(path), &file)) {
		return false;
	}
	SFileCloseFile(file);
	return true;
}

PackedByteArray WowArchive::read(const String &path) const {
	std::vector<uint8_t> data;
	PackedByteArray out;
	if (!read_bytes(normalize(path), data)) {
		return out;
	}
	out.resize(data.size());
	std::copy(data.begin(), data.end(), out.ptrw());
	return out;
}

PackedStringArray WowArchive::find(const String &mask) const {
	std::lock_guard<std::mutex> lock(mutex);
	const std::string pattern = normalize(mask);
	std::set<std::string> seen;
	std::vector<std::string> names;
	for (void *archive : archives) {
		if (!listfiles_loaded) {
			SFileAddListFile(archive, nullptr);
		}
		SFILE_FIND_DATA data;
		HANDLE search = SFileFindFirstFile(archive, pattern.c_str(), &data, nullptr);
		if (!search) {
			continue;
		}
		do {
			if (seen.insert(to_lower(data.cFileName)).second) {
				names.push_back(data.cFileName);
			}
		} while (SFileFindNextFile(search, &data));
		SFileFindClose(search);
	}
	listfiles_loaded = true;
	std::sort(names.begin(), names.end(), [](const std::string &a, const std::string &b) { return to_lower(a) < to_lower(b); });
	PackedStringArray out;
	for (const std::string &name : names) {
		out.push_back(String(name.c_str()));
	}
	return out;
}

void WowArchive::_bind_methods() {
	ClassDB::bind_method(D_METHOD("open", "data_dir"), &WowArchive::open);
	ClassDB::bind_method(D_METHOD("has", "path"), &WowArchive::has);
	ClassDB::bind_method(D_METHOD("read", "path"), &WowArchive::read);
	ClassDB::bind_method(D_METHOD("find", "mask"), &WowArchive::find);
	ClassDB::bind_method(D_METHOD("get_archive_names"), &WowArchive::get_archive_names);
}

} // namespace godot
