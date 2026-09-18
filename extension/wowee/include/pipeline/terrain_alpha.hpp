// Decoding of MCAL terrain layer alpha maps into 64x64 bytes.
#pragma once

#include "pipeline/adt_loader.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace wowee {
namespace pipeline {

inline constexpr size_t ALPHA_MAP_DIM = 64;
inline constexpr size_t ALPHA_MAP_SIZE = ALPHA_MAP_DIM * ALPHA_MAP_DIM;
inline constexpr size_t ALPHA_MAP_PACKED = ALPHA_MAP_SIZE / 2;
inline constexpr uint32_t MCNK_DO_NOT_FIX_ALPHA_MAP = 0x8000;

// Without FLAG_DO_NOT_FIX_ALPHA_MAP a 4-bit map is really 63x63, with the last row and column copied from the previous one.
inline void fixAlphaMapEdges(std::vector<uint8_t>& alpha) {
    const size_t last = ALPHA_MAP_DIM - 1;
    for (size_t i = 0; i < ALPHA_MAP_DIM; i++) {
        alpha[i * ALPHA_MAP_DIM + last] = alpha[i * ALPHA_MAP_DIM + last - 1];
        alpha[last * ALPHA_MAP_DIM + i] = alpha[(last - 1) * ALPHA_MAP_DIM + i];
    }
}

// Fills outAlpha with 4096 bytes; returns false when the layer has no usable alpha map.
[[nodiscard]] inline bool decodeLayerAlpha(const MapChunk& chunk, size_t layerIdx, std::vector<uint8_t>& outAlpha) {
    if (layerIdx >= chunk.layers.size()) return false;
    const TextureLayer& layer = chunk.layers[layerIdx];
    const std::vector<uint8_t>& src = chunk.alphaMap;
    if (!layer.useAlpha() || layer.offsetMCAL >= src.size()) return false;

    const size_t offset = layer.offsetMCAL;
    size_t layerSize = src.size() - offset;
    for (size_t j = layerIdx + 1; j < chunk.layers.size(); j++) {
        if (chunk.layers[j].useAlpha()) {
            if (chunk.layers[j].offsetMCAL > offset) layerSize = std::min<size_t>(layerSize, chunk.layers[j].offsetMCAL - offset);
            break;
        }
    }

    outAlpha.assign(ALPHA_MAP_SIZE, 0);

    if (layer.compressedAlpha()) {
        size_t readPos = offset;
        size_t writePos = 0;
        while (writePos < ALPHA_MAP_SIZE && readPos < src.size()) {
            const uint8_t cmd = src[readPos++];
            const size_t count = static_cast<size_t>(cmd & 0x7F) + 1;
            if (cmd & 0x80) {
                if (readPos >= src.size()) break;
                const uint8_t val = src[readPos++];
                for (size_t i = 0; i < count && writePos < ALPHA_MAP_SIZE; i++) outAlpha[writePos++] = val;
            } else {
                for (size_t i = 0; i < count && writePos < ALPHA_MAP_SIZE && readPos < src.size(); i++) outAlpha[writePos++] = src[readPos++];
            }
        }
        return true;
    }

    if (layerSize >= ALPHA_MAP_SIZE) {
        std::copy_n(src.begin() + static_cast<std::ptrdiff_t>(offset), ALPHA_MAP_SIZE, outAlpha.begin());
        return true;
    }

    if (layerSize >= ALPHA_MAP_PACKED) {
        for (size_t i = 0; i < ALPHA_MAP_PACKED; i++) {
            const uint8_t v = src[offset + i];
            outAlpha[i * 2] = static_cast<uint8_t>((v & 0x0F) * 17);
            outAlpha[i * 2 + 1] = static_cast<uint8_t>((v >> 4) * 17);
        }
        if (!(chunk.flags & MCNK_DO_NOT_FIX_ALPHA_MAP)) fixAlphaMapEdges(outAlpha);
        return true;
    }

    return false;
}

} // namespace pipeline
} // namespace wowee
