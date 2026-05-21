#include <iostream>
#include <vector>
#include <cstring>
#include <sstream>
#include <iomanip>

using namespace std;

// Constantes MD5
static const uint32_t T[64] = {
    0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,
    0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,
    0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,
    0x6b901122,0xfd987193,0xa679438e,0x49b40821,
    0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,
    0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,
    0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,
    0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,
    0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,
    0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,
    0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,
    0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
    0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,
    0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,
    0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,
    0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391
};

static const uint32_t S[64] = {
    7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,
    5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,
    4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,
    6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21
};

// Rotation gauche
uint32_t rotl(uint32_t x, uint32_t n) {
    return (x << n) | (x >> (32 - n));
}

string md5(const string& input) {

    // Padding
    vector<uint8_t> msg(input.begin(), input.end());
    uint64_t bitLen = msg.size() * 8;

    msg.push_back(0x80);
    while (msg.size() % 64 != 56)
        msg.push_back(0);

    for (int i = 0; i < 8; i++)
        msg.push_back((bitLen >> (8 * i)) & 0xFF);

    //  Initialisation 
    uint32_t A = 0x67452301;
    uint32_t B = 0xefcdab89;
    uint32_t C = 0x98badcfe;
    uint32_t D = 0x10325476;

    //  Traitement 
    for (size_t i = 0; i < msg.size(); i += 64) {

        uint32_t M[16];
        memcpy(M, &msg[i], 64);

        uint32_t a = A, b = B, c = C, d = D;

        for (int j = 0; j < 64; j++) {

            uint32_t f, g;

            if (j < 16) { f = (b & c) | (~b & d); g = j; }
            else if (j < 32) { f = (d & b) | (~d & c); g = (5 * j + 1) % 16; }
            else if (j < 48) { f = b ^ c ^ d;          g = (3 * j + 5) % 16; }
            else { f = c ^ (b | ~d);       g = (7 * j) % 16; }

            uint32_t temp = d;
            d = c;
            c = b;
            b = b + rotl(a + f + T[j] + M[g], S[j]);
            a = temp;
        }

        A += a;
        B += b;
        C += c;
        D += d;
    }

    // Résultat
    uint32_t res[4] = { A, B, C, D };

    ostringstream oss;
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++)
            oss << hex << setw(2) << setfill('0')
            << ((res[i] >> (8 * j)) & 0xFF);

    return oss.str();
}