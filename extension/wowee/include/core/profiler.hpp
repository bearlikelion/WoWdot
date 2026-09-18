// Thin wrapper around Tracy profiler.
// When TRACY_ENABLE is not defined, all macros expand to nothing (zero overhead).
#pragma once

#ifdef TRACY_ENABLE
#include <tracy/Tracy.hpp>
#define WOWEE_THREAD_NAME(name) tracy::SetThreadName(name)
#else
// No-op replacements when Tracy is disabled.
#define ZoneScoped
#define ZoneScopedN(x)
#define ZoneScopedC(x)
#define ZoneScopedNC(x, y)
#define ZoneTransientN(varname, name, active)
#define ZoneText(txt, size)
#define ZoneName(txt, size)
#define FrameMark
#define FrameMarkNamed(x)
#define FrameMarkStart(x)
#define FrameMarkEnd(x)
#define TracyPlot(x, y)
#define TracyPlotConfig(name, type, step, fill, color)
#define TracyMessage(txt, size)
#define TracyMessageL(x)
#define WOWEE_THREAD_NAME(name)
#endif
