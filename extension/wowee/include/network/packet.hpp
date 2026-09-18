#pragma once

#include <vector>
#include <cstdint>
#include <string>

namespace wowee {
namespace network {

class Packet {
public:
    Packet() = default;
    explicit Packet(uint16_t opcode);
    Packet(uint16_t opcode, const std::vector<uint8_t>& data);
    Packet(uint16_t opcode, std::vector<uint8_t>&& data);

    void writeUInt8(uint8_t value);
    void writeUInt16(uint16_t value);
    void writeUInt32(uint32_t value);
    void writeUInt64(uint64_t value);
    void writeFloat(float value);
    void writeString(const std::string& value);
    void writeBytes(const uint8_t* data, size_t length);

    uint8_t readUInt8();
    uint16_t readUInt16();
    uint32_t readUInt32();
    uint64_t readUInt64();
    float readFloat();
    uint64_t readPackedGuid();
    void writePackedGuid(uint64_t guid);
    std::string readString();

    uint16_t getOpcode() const { return opcode; }
    const std::vector<uint8_t>& getData() const { return data; }
    size_t getReadPos() const { return readPos; }
    size_t getSize() const { return data.size(); }
    // Clamp to 0 instead of wrapping to ~(size_t)0 when readPos overshoots
    // (can happen via setReadPos with an unchecked offset).
    size_t getRemainingSize() const { return (readPos <= data.size()) ? (data.size() - readPos) : 0; }
    bool hasRemaining(size_t need) const { return readPos <= data.size() && need <= (data.size() - readPos); }
    bool hasFullPackedGuid() const {
        if (readPos >= data.size()) return false;
        uint8_t mask = data[readPos];
        size_t guidBytes = 1;
        for (int bit = 0; bit < 8; ++bit)
            if (mask & (1u << bit)) ++guidBytes;
        return getRemainingSize() >= guidBytes;
    }
    void setReadPos(size_t pos) { readPos = pos; }
    bool hasData() const { return readPos < data.size(); }
    void skipAll() { readPos = data.size(); }

private:
    uint16_t opcode = 0;
    std::vector<uint8_t> data;
    size_t readPos = 0;
};

} // namespace network
} // namespace wowee
