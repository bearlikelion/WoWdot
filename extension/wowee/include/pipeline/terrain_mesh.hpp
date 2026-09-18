#pragma once

#include "pipeline/adt_loader.hpp"
#include <vector>
#include <cstdint>

namespace wowee {
namespace pipeline {

/**
 * Vertex format for terrain rendering
 */
struct TerrainVertex {
    float position[3];     // X, Y, Z
    float normal[3];       // Normal vector
    float texCoord[2];     // Base texture coordinates
    float layerUV[2];      // Layer texture coordinates
    uint8_t chunkIndex;    // Which chunk this vertex belongs to

    TerrainVertex() : chunkIndex(0) {
        position[0] = position[1] = position[2] = 0.0f;
        normal[0] = normal[1] = normal[2] = 0.0f;
        texCoord[0] = texCoord[1] = 0.0f;
        layerUV[0] = layerUV[1] = 0.0f;
    }
};

/**
 * Triangle index (3 vertices)
 */
using TerrainIndex = uint32_t;

/**
 * Renderable terrain mesh for a single map chunk
 */
struct ChunkMesh {
    std::vector<TerrainVertex> vertices;
    std::vector<TerrainIndex> indices;

    // Chunk position in world space
    float worldX;
    float worldY;
    float worldZ;

    // Chunk grid coordinates
    int chunkX;
    int chunkY;

    // Texture layer info
    struct LayerInfo {
        uint32_t textureId;
        uint32_t flags;
        std::vector<uint8_t> alphaData;  // 64x64 alpha map
    };
    std::vector<LayerInfo> layers;

    bool isValid() const { return !vertices.empty() && !indices.empty(); }
    size_t getVertexCount() const { return vertices.size(); }
    size_t getTriangleCount() const { return indices.size() / 3; }
};

/**
 * Complete terrain tile mesh (16x16 chunks)
 */
struct TerrainMesh {
    std::array<ChunkMesh, 256> chunks;  // 16x16 grid
    std::vector<std::string> textures;   // Texture filenames

    int validChunkCount = 0;

    const ChunkMesh& getChunk(int x, int y) const { return chunks[y * 16 + x]; }
    ChunkMesh& getChunk(int x, int y) { return chunks[y * 16 + x]; }
};

/**
 * Terrain mesh generator
 *
 * Converts ADT heightmap data into renderable triangle meshes
 */
class TerrainMeshGenerator {
public:
    /**
     * Generate terrain mesh from ADT data
     * @param terrain Loaded ADT terrain data
     * @return Generated mesh (check validChunkCount)
     */
    static TerrainMesh generate(const ADTTerrain& terrain);

private:
    /**
     * Generate mesh for a single map chunk
     */
    static ChunkMesh generateChunkMesh(const MapChunk& chunk, int chunkX, int chunkY, int tileX, int tileY);

    /**
     * Generate vertices from heightmap
     * WoW heightmap layout: 9x9 outer + 8x8 inner vertices (145 total)
     */
    static std::vector<TerrainVertex> generateVertices(const MapChunk& chunk, int chunkX, int chunkY, int tileX, int tileY);

    /**
     * Generate triangle indices
     * Creates triangles that connect the heightmap vertices
     * Skips quads that are marked as holes in the chunk
     */
    static std::vector<TerrainIndex> generateIndices(const MapChunk& chunk);

    /**
     * Calculate texture coordinates for vertex
     */
    static void calculateTexCoords(TerrainVertex& vertex, int x, int y);

    /**
     * Convert WoW's compressed normals to float
     */
    static void decompressNormal(const int8_t* compressedNormal, float* normal);

    /**
     * Get height at grid position from WoW's 9x9+8x8 layout
     */
    static float getHeightAt(const HeightMap& heightMap, int x, int y);

    /**
     * Convert grid coordinates to vertex index
     */
    static int getVertexIndex(int x, int y);

    // Terrain constants
    // WoW terrain: 64x64 tiles, each tile = 533.33 yards, each chunk = 33.33 yards
    static constexpr float TILE_SIZE = 533.33333f;         // One ADT tile = 533.33 yards
    static constexpr float CHUNK_SIZE = TILE_SIZE / 16.0f; // One chunk = 33.33 yards (16 chunks per tile)
    static constexpr float GRID_STEP = CHUNK_SIZE / 8.0f;  // 8 quads per chunk = 4.17 yards per vertex
};

} // namespace pipeline
} // namespace wowee
