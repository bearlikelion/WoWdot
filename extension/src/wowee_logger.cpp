#include "core/logger.hpp"

#include <godot_cpp/variant/utility_functions.hpp>

// Replaces mWoWee's file logger so vendored code reports through Godot's output instead of writing logs/wowee.log.
namespace wowee::core {

Logger &Logger::getInstance() {
	static Logger instance;
	return instance;
}

void Logger::log(LogLevel level, const std::string &message) {
	const godot::String text = godot::String::utf8(message.c_str());
	if (level >= kLogLevelError) {
		godot::UtilityFunctions::push_error(text);
	} else if (level == LogLevel::WARNING) {
		godot::UtilityFunctions::push_warning(text);
	} else {
		godot::UtilityFunctions::print_verbose(text);
	}
}

void Logger::setLogLevel(LogLevel level) {
	minLevel_.store(static_cast<int>(level));
}

bool Logger::shouldLog(LogLevel level) const {
	return static_cast<int>(level) >= minLevel_.load();
}

} // namespace wowee::core
