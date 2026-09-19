#include "auth/crypto.hpp"
#include <tomcrypt.h>

namespace wowee {
namespace auth {

namespace {

constexpr size_t SHA1_LENGTH = 20;
constexpr size_t MD5_LENGTH = 16;
constexpr size_t SHA1_BLOCK_SIZE = 64;

} // namespace

std::vector<uint8_t> Crypto::sha1(const std::vector<uint8_t>& data) {
    std::vector<uint8_t> hash(SHA1_LENGTH);
    hash_state state;
    sha1_init(&state);
    // libtomcrypt aborts on a null input pointer, which an empty vector may hand it.
    if (!data.empty()) {
        sha1_process(&state, data.data(), data.size());
    }
    sha1_done(&state, hash.data());
    return hash;
}

std::vector<uint8_t> Crypto::sha1(const std::string& data) {
    std::vector<uint8_t> bytes(data.begin(), data.end());
    return sha1(bytes);
}

std::vector<uint8_t> Crypto::md5(const std::vector<uint8_t>& data) {
    std::vector<uint8_t> hash(MD5_LENGTH);
    hash_state state;
    md5_init(&state);
    if (!data.empty()) {
        md5_process(&state, data.data(), data.size());
    }
    md5_done(&state, hash.data());
    return hash;
}

std::vector<uint8_t> Crypto::md5(const std::string& data) {
    std::vector<uint8_t> bytes(data.begin(), data.end());
    return md5(bytes);
}

std::vector<uint8_t> Crypto::hmacSHA1(const std::vector<uint8_t>& key,
                                        const std::vector<uint8_t>& data) {
    std::vector<uint8_t> block = key.size() > SHA1_BLOCK_SIZE ? sha1(key) : key;
    block.resize(SHA1_BLOCK_SIZE, 0);

    std::vector<uint8_t> inner(block);
    std::vector<uint8_t> outer(block);
    for (size_t i = 0; i < SHA1_BLOCK_SIZE; ++i) {
        inner[i] ^= 0x36;
        outer[i] ^= 0x5c;
    }

    inner.insert(inner.end(), data.begin(), data.end());
    std::vector<uint8_t> innerHash = sha1(inner);
    outer.insert(outer.end(), innerHash.begin(), innerHash.end());
    return sha1(outer);
}

} // namespace auth
} // namespace wowee
