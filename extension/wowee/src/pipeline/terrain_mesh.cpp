#include "pipeline/terrain_mesh.hpp"
#include "pipeline/terrain_alpha.hpp"
#include "core/coordinates.hpp"
#include "core/logger.hpp"
#include <cmath>

namespace wowee {
namespace pipeline {

TerrainMesh TerrainMeshGenerator::generate(const ADTTerrain& terrain) {
    TerrainMesh mesh;

    if (!terrain.isLoaded()) {
        LOG_WARNING("Attempting to generate mesh from unloaded terrain");
        return mesh;
    }


    // Copy texture list
    mesh.textures = terrain.textures;

    // Generate mesh for each chunk
    int validCount = 0;
    bool loggedFirstChunk = false;
    for (int y = 0; y < 16; y++) {
        for (int x = 0; x < 16; x++) {
            const MapChunk& chunk = terrain.getChunk(x, y);

            if (chunk.hasHeightMap()) {
                mesh.getChunk(x, y) = generateChunkMesh(chunk, x, y, terrain.coord.x, terrain.coord.y);
                validCount++;

                // Debug: log first chunk world position
                if (!loggedFirstChunk) {
                    loggedFirstChunk = true;
                    LOG_DEBUG("First terrain chunk world pos: (", chunk.position[0], ", ",
                              chunk.position[1], ", ", chunk.position[2], ")");
                }
            }
        }
    }

    mesh.validChunkCount = validCount;


    return mesh;
}

ChunkMesh TerrainMeshGenerator::generateChunkMesh(const MapChunk& chunk, int chunkX, int chunkY, int tileX, int tileY) {
    ChunkMesh mesh;

    mesh.chunkX = chunkX;
    mesh.chunkY = chunkY;

    // Compute render-space XY from tile/chunk indices (MCNK position fields are unreliable).
    // tileX increases southward (renderY axis), tileY increases eastward (renderX axis).
    // NW corner of tile: renderX = (32-tileY)*TILE_SIZE, renderY = (32-tileX)*TILE_SIZE
    // Each chunk step goes east (–renderX) or south (–renderY).
    const float tileNW_renderX = (32.0f - static_cast<float>(tileY)) * core::coords::TILE_SIZE;
    const float tileNW_renderY = (32.0f - static_cast<float>(tileX)) * core::coords::TILE_SIZE;
    mesh.worldX = tileNW_renderX - static_cast<float>(chunkY) * CHUNK_SIZE;  // iy controls renderX (east-west)
    mesh.worldY = tileNW_renderY - static_cast<float>(chunkX) * CHUNK_SIZE;  // ix controls renderY (north-south)
    mesh.worldZ = chunk.position[2];  // height base (wowZ) from MCNK offset 112

    // Debug: log chunk positions for first tile
    static int posLogCount = 0;
    if (posLogCount < 5) {
        posLogCount++;
        LOG_INFO("Terrain chunk: tile(", tileX, ",", tileY, ") ix=", chunkX, " iy=", chunkY,
                 " worldXY=(", mesh.worldX, ",", mesh.worldY, ",", mesh.worldZ, ")",
                 " mcnk=(", chunk.position[0], ",", chunk.position[1], ",", chunk.position[2], ")");
    }

    // Generate vertices from heightmap (pass chunk grid indices and tile coords)
    mesh.vertices = generateVertices(chunk, chunkX, chunkY, tileX, tileY);

    // Generate triangle indices (checks for holes)
    mesh.indices = generateIndices(chunk);

    // Debug: verify mesh integrity (one-time)
    static bool debugLogged = false;
    if (!debugLogged && chunkX == 0 && chunkY == 0) {
        debugLogged = true;
        LOG_INFO("Terrain mesh debug: ", mesh.vertices.size(), " vertices, ",
                 mesh.indices.size(), " indices (", mesh.indices.size() / 3, " triangles)");

        // Verify all indices are in bounds
        int maxIndex = 0;
        int minIndex = 9999;
        for (auto idx : mesh.indices) {
            if (static_cast<int>(idx) > maxIndex) maxIndex = idx;
            if (static_cast<int>(idx) < minIndex) minIndex = idx;
        }
        LOG_INFO("Index range: [", minIndex, ", ", maxIndex, "] (expected [0, 144])");

        if (maxIndex >= static_cast<int>(mesh.vertices.size())) {
            LOG_ERROR("INDEX OUT OF BOUNDS! Max index ", maxIndex, " >= vertex count ", mesh.vertices.size());
        }

        // Check for invalid vertex positions
        int invalidCount = 0;
        for (size_t i = 0; i < mesh.vertices.size(); i++) {
            const auto& v = mesh.vertices[i];
            if (!std::isfinite(v.position[0]) || !std::isfinite(v.position[1]) || !std::isfinite(v.position[2])) {
                invalidCount++;
            }
        }
        if (invalidCount > 0) {
            LOG_ERROR("Found ", invalidCount, " vertices with invalid positions!");
        }
    }

    // Copy texture layers
    for (size_t layerIdx = 0; layerIdx < chunk.layers.size(); layerIdx++) {
        const auto& layer = chunk.layers[layerIdx];
        ChunkMesh::LayerInfo layerInfo;
        layerInfo.textureId = layer.textureId;
        layerInfo.flags = layer.flags;
        layerInfo.effectId = layer.effectId;

        if (!decodeLayerAlpha(chunk, layerIdx, layerInfo.alphaData)) {
            layerInfo.alphaData.clear();
        }

        mesh.layers.push_back(layerInfo);
    }
    mesh.shadowMap = chunk.shadowMap;

    return mesh;
}

std::vector<TerrainVertex> TerrainMeshGenerator::generateVertices(const MapChunk& chunk, int chunkX, int chunkY, int tileX, int tileY) {
    std::vector<TerrainVertex> vertices;
    vertices.reserve(145);  // 145 vertices total

    const HeightMap& heightMap = chunk.heightMap;

    // WoW terrain uses 145 heights stored in a 9x17 row-major grid layout
    const float unitSize = CHUNK_SIZE / 8.0f;  // 33.333/8 units per vertex step

    // Compute render-space base from tile/chunk indices (same formula as generateChunkMesh).
    const float tileNW_renderX = (32.0f - static_cast<float>(tileY)) * core::coords::TILE_SIZE;
    const float tileNW_renderY = (32.0f - static_cast<float>(tileX)) * core::coords::TILE_SIZE;
    float chunkBaseX = tileNW_renderX - static_cast<float>(chunkY) * CHUNK_SIZE;  // iy controls renderX (east-west)
    float chunkBaseY = tileNW_renderY - static_cast<float>(chunkX) * CHUNK_SIZE;  // ix controls renderY (north-south)
    float chunkBaseZ = chunk.position[2];  // height base (wowZ) from MCNK offset 112

    for (int index = 0; index < 145; index++) {
        int y = index / 17;  // Row (0-8)
        int x = index % 17;  // Column (0-16)

        // Columns 9-16 are offset by 0.5 units (wowee exact logic)
        float offsetX = static_cast<float>(x);
        float offsetY = static_cast<float>(y);

        if (x > 8) {
            offsetY += 0.5f;
            offsetX -= 8.5f;
        }

        TerrainVertex vertex;

        // Position in render space:
        //   MCVT rows (offsetY) go west→east = renderX decreasing
        //   MCVT columns (offsetX) go north→south = renderY decreasing
        // NaN heights are clamped — WHM load scrubs but mid-edit terrain
        // can briefly carry NaN before stitchEdges runs, and a single NaN
        // vertex would propagate into normal computations and crash culling.
        float h = heightMap.heights[index];
        if (!std::isfinite(h)) h = 0.0f;
        vertex.position[0] = chunkBaseX - (offsetY * unitSize);  // renderX (row = west→east)
        vertex.position[1] = chunkBaseY - (offsetX * unitSize);  // renderY (col = north→south)
        vertex.position[2] = chunkBaseZ + h;                      // renderZ

        // Normal
        if (index * 3 + 2 < static_cast<int>(chunk.normals.size())) {
            decompressNormal(&chunk.normals[index * 3], vertex.normal);
        } else {
            // Default up normal
            vertex.normal[0] = 0.0f;
            vertex.normal[1] = 0.0f;
            vertex.normal[2] = 1.0f;
        }

        // Texture coordinates: world-aligned so patterns don't reset per chunk.
        // Tile each texture 4× per chunk (one repeat every ~8 yards) so the
        // texture's own pattern noise breaks up the chunk grid rather than
        // syncing with it. At 1 repeat/chunk the per-chunk alpha differences
        // read as obvious 33-yard squares; at 4× the pattern is small enough
        // that the eye no longer locks onto the chunk boundary.
        constexpr float texScale = 4.0f / CHUNK_SIZE;
        vertex.texCoord[0] = -vertex.position[1] * texScale;
        vertex.texCoord[1] = -vertex.position[0] * texScale;

        // Layer UV for alpha map sampling (0-1 range per chunk).
        // Sample at texel centers of the 64x64 alpha map to avoid edge seams.
        constexpr float alphaTexels = 64.0f;
        constexpr float alphaStep = (alphaTexels - 1.0f) / 8.0f; // 63 texels across 8 quads
        vertex.layerUV[0] = (offsetX * alphaStep + 0.5f) / alphaTexels;
        vertex.layerUV[1] = (offsetY * alphaStep + 0.5f) / alphaTexels;

        vertices.push_back(vertex);
    }

    return vertices;
}

std::vector<TerrainIndex> TerrainMeshGenerator::generateIndices(const MapChunk& chunk) {
    std::vector<TerrainIndex> indices;
    indices.reserve(768);  // 8x8 quads * 4 triangles * 3 indices = 768

    // Generate indices based on 9x17 grid layout (matching wowee.js)
    // Each quad uses a center vertex with 4 surrounding vertices
    // Index offsets from center: -9, -8, +9, +8

    int holesSkipped = 0;
    for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
            // Skip quads that are marked as holes (cave entrances, etc.)
            if (chunk.isHole(y, x)) {
                holesSkipped++;
                continue;
            }

            // Center vertex index in the 9x17 grid
            int center = 9 + y * 17 + x;

            // Four triangles per quad
            // Using CCW winding when viewed from +Z (top-down)
            int tl = center - 9;  // top-left outer
            int tr = center - 8;  // top-right outer
            int bl = center + 8;  // bottom-left outer
            int br = center + 9;  // bottom-right outer

            // Triangle 1: top (center, tl, tr)
            indices.push_back(center);
            indices.push_back(tl);
            indices.push_back(tr);

            // Triangle 2: right (center, tr, br)
            indices.push_back(center);
            indices.push_back(tr);
            indices.push_back(br);

            // Triangle 3: bottom (center, br, bl)
            indices.push_back(center);
            indices.push_back(br);
            indices.push_back(bl);

            // Triangle 4: left (center, bl, tl)
            indices.push_back(center);
            indices.push_back(bl);
            indices.push_back(tl);
        }
    }

    // Debug: log if any holes were skipped (one-time per session)
    static bool holesLogged = false;
    if (!holesLogged && holesSkipped > 0) {
        holesLogged = true;
        LOG_INFO("Terrain holes: skipped ", holesSkipped, " quads due to hole mask (holes=0x",
                 std::hex, chunk.holes, std::dec, ")");
    }

    return indices;
}

void TerrainMeshGenerator::calculateTexCoords(TerrainVertex& vertex, int x, int y) {
    // Base texture coordinates (0-1 range across chunk)
    vertex.texCoord[0] = x / 16.0f;
    vertex.texCoord[1] = y / 16.0f;

    // Layer UVs (same as base for now)
    vertex.layerUV[0] = vertex.texCoord[0];
    vertex.layerUV[1] = vertex.texCoord[1];
}

void TerrainMeshGenerator::decompressNormal(const int8_t* compressedNormal, float* normal) {
    // WoW stores normals as signed bytes (-127 to 127)
    // Convert to float and normalize

    float x = compressedNormal[0] / 127.0f;
    float y = compressedNormal[1] / 127.0f;
    float z = compressedNormal[2] / 127.0f;

    // Normalize
    float length = std::sqrt(x * x + y * y + z * z);
    if (length > 0.0001f) {
        normal[0] = x / length;
        normal[1] = y / length;
        normal[2] = z / length;
    } else {
        // Default up normal if degenerate
        normal[0] = 0.0f;
        normal[1] = 0.0f;
        normal[2] = 1.0f;
    }
}

int TerrainMeshGenerator::getVertexIndex(int x, int y) {
    // Convert virtual grid position (0-16) to actual vertex index (0-144)
    // Outer vertices (even positions): 0-80 (9x9 grid)
    // Inner vertices (odd positions): 81-144 (8x8 grid)

    bool isOuter = (y % 2 == 0) && (x % 2 == 0);
    bool isInner = (y % 2 == 1) && (x % 2 == 1);

    if (isOuter) {
        int gridX = x / 2;
        int gridY = y / 2;
        return gridY * 9 + gridX;  // 0-80
    } else if (isInner) {
        int gridX = (x - 1) / 2;
        int gridY = (y - 1) / 2;
        return 81 + gridY * 8 + gridX;  // 81-144
    }

    return -1;  // Invalid position
}

} // namespace pipeline
} // namespace wowee
