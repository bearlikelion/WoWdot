#pragma once

#include <vector>
#include <cstdint>
#include <string>
#include <openssl/bn.h>

namespace wowee {
namespace auth {

// Wrapper around OpenSSL BIGNUM for big integer arithmetic
class BigNum {
public:
    BigNum();
    explicit BigNum(uint32_t value);
    explicit BigNum(const std::vector<uint8_t>& bytes, bool littleEndian = true);
    ~BigNum();

    // Copy/move operations
    BigNum(const BigNum& other);
    BigNum& operator=(const BigNum& other);
    BigNum(BigNum&& other) noexcept;
    BigNum& operator=(BigNum&& other) noexcept;

    // Factory methods
    static BigNum fromRandom(int bytes);
    static BigNum fromHex(const std::string& hex);
    static BigNum fromDecimal(const std::string& dec);

    // Arithmetic operations
    BigNum add(const BigNum& other) const;
    BigNum subtract(const BigNum& other) const;
    BigNum multiply(const BigNum& other) const;
    BigNum mod(const BigNum& modulus) const;
    BigNum modPow(const BigNum& exponent, const BigNum& modulus) const;

    // Comparison
    bool equals(const BigNum& other) const;
    bool isZero() const;

    // Conversion
    std::vector<uint8_t> toArray(bool littleEndian = true, int minSize = 0) const;
    std::string toHex() const;
    std::string toDecimal() const;

    // Direct access (for advanced operations)
    BIGNUM* getBN() { return bn; }
    const BIGNUM* getBN() const { return bn; }

private:
    BIGNUM* bn;
};

} // namespace auth
} // namespace wowee
