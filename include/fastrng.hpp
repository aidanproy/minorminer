#pragma once
#include <algorithm>

class fastrng {
  private:
    uint64_t S0;
    uint64_t S1;

    static inline uint64_t splitmix64(uint64_t &x) {
        uint64_t z = (x += UINT64_C(0x9E3779B97F4A7C15));
        z = (z ^ (z >> 30)) * UINT64_C(0xBF58476D1CE4E5B9);
        z = (z ^ (z >> 27)) * UINT64_C(0x94D049BB133111EB);
        return z ^ (z >> 31);
    }

    static inline uint32_t splitmix32(uint32_t &x) {
        uint32_t z = (x += 0x6D2B79F5UL);
        z = (z ^ (z >> 15)) * (z | 1UL);
        z ^= z + (z ^ (z >> 7)) * (z | 61UL);
        return z ^ (z >> 14);
    }

  public:
    typedef uint64_t result_type;

    fastrng() {}

    inline void seed(uint32_t x) {
        uint32_t a = splitmix32(x);
        uint64_t b = static_cast<uint64_t>(splitmix32(x));
        b <<= 32;
        b += a;
        seed(b);
    }

    inline void seed(uint64_t x) {
        S0 = splitmix64(x);
        S1 = splitmix64(x);
        discard(1024);
    }

    uint64_t operator()() {
        uint64_t x = S0;
        uint64_t const y = S1;
        S0 = y;
        x ^= x << 23;                        // a
        S1 = x ^ y ^ (x >> 17) ^ (y >> 26);  // b, c
        return S1 + y;
    }

    void discard(int n) {
        while (n-- > 0) {
            uint64_t x = S0;
            uint64_t const y = S1;
            S0 = y;
            x ^= x << 23;                        // a
            S1 = x ^ y ^ (x >> 17) ^ (y >> 26);  // b, c
        }
    }

    static uint64_t min() { return std::numeric_limits<uint64_t>::min(); }
    static uint64_t max() { return std::numeric_limits<uint64_t>::max(); }
};
