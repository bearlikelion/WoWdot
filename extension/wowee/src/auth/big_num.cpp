#include "auth/big_num.hpp"
#include <algorithm>
#include <cstring>
#include <random>

namespace wowee {
namespace auth {

namespace {

std::string toRadix(mp_int* value, int radix) {
    int size = 0;
    mp_radix_size(value, radix, &size);
    std::string result(size, '\0');
    mp_toradix(value, result.data(), radix);
    result.resize(std::strlen(result.c_str()));
    return result;
}

} // namespace

BigNum::BigNum() {
    mp_init(&bn);
}

BigNum::BigNum(uint32_t value) {
    mp_init(&bn);
    mp_set_int(&bn, value);
}

BigNum::BigNum(const std::vector<uint8_t>& bytes, bool littleEndian) {
    mp_init(&bn);
    if (littleEndian) {
        std::vector<uint8_t> reversed(bytes.rbegin(), bytes.rend());
        mp_read_unsigned_bin(&bn, reversed.data(), static_cast<int>(reversed.size()));
    } else {
        mp_read_unsigned_bin(&bn, bytes.data(), static_cast<int>(bytes.size()));
    }
}

BigNum::~BigNum() {
    mp_clear(&bn);
}

BigNum::BigNum(const BigNum& other) {
    mp_init_copy(&bn, &other.bn);
}

BigNum& BigNum::operator=(const BigNum& other) {
    if (this != &other) {
        mp_copy(&other.bn, &bn);
    }
    return *this;
}

BigNum::BigNum(BigNum&& other) noexcept {
    mp_init(&bn);
    mp_exch(&bn, &other.bn);
}

BigNum& BigNum::operator=(BigNum&& other) noexcept {
    mp_exch(&bn, &other.bn);
    return *this;
}

BigNum BigNum::fromRandom(int bytes) {
    std::random_device device;
    std::vector<uint8_t> randomBytes(bytes);
    for (uint8_t& byte : randomBytes) {
        byte = static_cast<uint8_t>(device());
    }
    return BigNum(randomBytes, true);
}

BigNum BigNum::fromHex(const std::string& hex) {
    BigNum result;
    mp_read_radix(&result.bn, hex.c_str(), 16);
    return result;
}

BigNum BigNum::fromDecimal(const std::string& dec) {
    BigNum result;
    mp_read_radix(&result.bn, dec.c_str(), 10);
    return result;
}

BigNum BigNum::add(const BigNum& other) const {
    BigNum result;
    mp_add(&bn, &other.bn, &result.bn);
    return result;
}

BigNum BigNum::subtract(const BigNum& other) const {
    BigNum result;
    mp_sub(&bn, &other.bn, &result.bn);
    return result;
}

BigNum BigNum::multiply(const BigNum& other) const {
    BigNum result;
    mp_mul(&bn, &other.bn, &result.bn);
    return result;
}

BigNum BigNum::mod(const BigNum& modulus) const {
    BigNum result;
    // mp_div keeps the dividend's sign like BN_mod; mp_mod would not.
    mp_div(&bn, &modulus.bn, nullptr, &result.bn);
    return result;
}

BigNum BigNum::modPow(const BigNum& exponent, const BigNum& modulus) const {
    BigNum result;
    mp_exptmod(&bn, &exponent.bn, &modulus.bn, &result.bn);
    return result;
}

bool BigNum::equals(const BigNum& other) const {
    return mp_cmp(&bn, &other.bn) == MP_EQ;
}

bool BigNum::isZero() const {
    return mp_iszero(&bn) == MP_YES;
}

std::vector<uint8_t> BigNum::toArray(bool littleEndian, int minSize) const {
    int numBytes = mp_unsigned_bin_size(&bn);
    int size = std::max(numBytes, minSize);

    std::vector<uint8_t> bytes(size, 0);
    mp_to_unsigned_bin(&bn, bytes.data() + (size - numBytes));

    if (littleEndian) {
        std::reverse(bytes.begin(), bytes.end());
    }

    return bytes;
}

std::string BigNum::toHex() const {
    return toRadix(&bn, 16);
}

std::string BigNum::toDecimal() const {
    return toRadix(&bn, 10);
}

} // namespace auth
} // namespace wowee
