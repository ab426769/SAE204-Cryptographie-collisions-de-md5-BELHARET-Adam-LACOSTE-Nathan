#include <cuda_runtime.h>
#include <stdio.h>
#include <math.h>
#include <unordered_map>

#define BITS 52
#define N (1<<20)

__constant__ unsigned int d_k[64];

__constant__ unsigned int d_r[64] = {
    7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
    5, 9,14,20, 5, 9,14,20, 5, 9,14,20, 5, 9,14,20,
    4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
    6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21
};

__device__ unsigned int leftrotate(unsigned int x, unsigned int n) {
    return (x << n) | (x >> (32 - n));
}

__device__ void md5(unsigned long long val, unsigned int* out) {
    unsigned char buf[64] = { 0 };

    // Message = 8 octets little-endian
    for (int i = 0; i < 8; i++)
        buf[i] = (val >> (i * 8)) & 0xFF;

    // Padding : bit "1" puis taille en bits sur 64 bits
    buf[8] = 0x80;
    unsigned long long bits = 64;
    for (int i = 0; i < 8; i++)
        buf[56 + i] = (bits >> (i * 8)) & 0xFF;

    // Decoupage en 16 mots de 32 bits
    unsigned int w[16];
    for (int i = 0; i < 16; i++) {
        w[i] = buf[i * 4]
            | (buf[i * 4 + 1] << 8)
            | (buf[i * 4 + 2] << 16)
            | (buf[i * 4 + 3] << 24);
    }

    // Initialisation
    unsigned int a = 0x67452301;
    unsigned int b = 0xEFCDAB89;
    unsigned int c = 0x98BADCFE;
    unsigned int d = 0x10325476;

    // Boucle principale
    for (int i = 0; i < 64; i++) {
        unsigned int f, g;
        if (i < 16) {
            f = (b & c) | (~b & d);
            g = i;
        }
        else if (i < 32) {
            f = (d & b) | (~d & c);
            g = (5 * i + 1) % 16;
        }
        else if (i < 48) {
            f = b ^ c ^ d;
            g = (3 * i + 5) % 16;
        }
        else {
            f = c ^ (b | ~d);
            g = (7 * i) % 16;
        }
        unsigned int temp = d;
        d = c;
        c = b;
        b = b + leftrotate(a + f + d_k[i] + w[g], d_r[i]);
        a = temp;
    }

    out[0] = 0x67452301 + a;
    out[1] = 0xEFCDAB89 + b;
}
// calcule un hash MD5 tronqué pour chaque thread
__global__ void kernel(unsigned long long start, unsigned long long* hashes) {
    int id = blockIdx.x * blockDim.x + threadIdx.x; //id unique thrad

    unsigned int digest[2]; //calcul md5 partiel pour start + id
    md5(start + id, digest);

    unsigned long long h = ((unsigned long long)digest[1] << 32) | digest[0];
    if (BITS < 64) // Tronque hash à BITS bits si nécessaire
        h = h & ((1ULL << BITS) - 1);

    hashes[id] = h; // Stock résultat dans tableau GPU
}

int main() {
    printf("Collision MD5 sur %d bits\n", BITS);

    // Calcul de la table k[i] = floor(|sin(i+1)| * 2^32)
    unsigned int h_k[64];
    for (int i = 0; i < 64; i++)
        h_k[i] = (unsigned int)floor(fabs(sin((double)(i + 1))) * 4294967296.0);
    cudaMemcpyToSymbol(d_k, h_k, sizeof(h_k));

    // Allocations
    unsigned long long* d_h; //declare pointeur GPU
    unsigned long long* h_h = (unsigned long long*)malloc(N * sizeof(unsigned long long)); //alloc tableau N entiers 64 en memoire CPU RAM pour recuperer hash GPU
    cudaMalloc(&d_h, N * sizeof(unsigned long long)); //alloc meme blabla mais mémoire GPU VRAM

    std::unordered_map<unsigned long long, unsigned long long> table; // Dictionnaire pour stocker hash message et détecter les collisions
    unsigned long long start = 0; // Début de la plage de valeurs testées

    while (1) {
        kernel << <N / 256, 256 >> > (start, d_h); 
        cudaMemcpy(h_h, d_h, N * sizeof(unsigned long long), cudaMemcpyDeviceToHost);

        for (int i = 0; i < N; i++) {
            unsigned long long h = h_h[i];
            unsigned long long v = start + i;

            if (table.count(h)) {
                printf("\nCOLLISION TROUVEE !\n");
                printf("hash = %llx\n", h);
                printf("msg1 = %llu\n", table[h]);
                printf("msg2 = %llu\n", v);
                return 0;
            }
            table[h] = v;
        }

        start += N;
        printf(".");
        fflush(stdout);
    }
}