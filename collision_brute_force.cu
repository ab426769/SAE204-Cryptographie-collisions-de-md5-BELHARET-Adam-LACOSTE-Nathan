#include <cuda_runtime.h>
#include <stdio.h>
#include <math.h>
#include <chrono>

#define BITS 64
#define N (1 << 24)
#define TABLE_BITS 28
#define TABLE_SIZE (1ULL << TABLE_BITS)
#define TABLE_MASK (TABLE_SIZE - 1)
#define BATCH_KERNELS 8

__constant__ unsigned int d_k[64];
__constant__ unsigned int d_r[64] = {
    7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
    5, 9,14,20, 5, 9,14,20, 5, 9,14,20, 5, 9,14,20,
    4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
    6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21
};

__device__ unsigned int rol(unsigned int x, unsigned int n) {
    return (x << n) | (x >> (32 - n));
}

__device__ unsigned long long md5(unsigned long long val) {
    unsigned int w[16] = { 0 };
    w[0] = (unsigned int)val;
    w[1] = (unsigned int)(val >> 32);
    w[2] = 0x80;
    w[14] = 64;

    unsigned int a = 0x67452301, b = 0xEFCDAB89, c = 0x98BADCFE, d = 0x10325476;

    for (int i = 0; i < 64; i++) {
        unsigned int f, g;
        if (i < 16) { f = (b & c) | (~b & d); g = i; }
        else if (i < 32) { f = (d & b) | (~d & c); g = (5 * i + 1) & 15; }
        else if (i < 48) { f = b ^ c ^ d;          g = (3 * i + 5) & 15; }
        else { f = c ^ (b | ~d);       g = (7 * i) & 15; }

        unsigned int temp = d;
        d = c;
        c = b;
        b = b + rol(a + f + d_k[i] + w[g], d_r[i]);
        a = temp;
    }

    unsigned long long h = ((unsigned long long)(0xEFCDAB89 + b) << 32) | (0x67452301 + a);

#if BITS >= 64
    return h;
#else
    return h & ((1ULL << BITS) - 1);
#endif
}

__global__ void kernel(unsigned long long start,
    unsigned long long* table_h, unsigned long long* table_v,
    unsigned long long* r_hash, unsigned long long* r_v1, unsigned long long* r_v2,
    int* found)
{
    if (*found) return;

    unsigned long long v = start + blockIdx.x * blockDim.x + threadIdx.x;
    unsigned long long h = md5(v);
    unsigned long long slot = (h * 2654435761ULL) & TABLE_MASK;

    for (int i = 0; i < 8; i++) {
        unsigned long long old = atomicCAS(&table_h[slot], 0ULL, h);

        if (old == 0) {
            table_v[slot] = v;
            return;
        }
        if (old == h) {
            if (atomicCAS(found, 0, 1) == 0) {
                *r_hash = h;
                *r_v1 = table_v[slot];
                *r_v2 = v;
            }
            return;
        }
        slot = (slot + 1) & TABLE_MASK;
    }
}

int main() {
    printf("Collision MD5 sur %d bits\n\n", BITS);

    // Table k[] de MD5
    unsigned int h_k[64];
    for (int i = 0; i < 64; i++)
        h_k[i] = (unsigned int)(fabs(sin(i + 1.0)) * 4294967296.0);
    cudaMemcpyToSymbol(d_k, h_k, sizeof(h_k));

    // Allocations GPU
    unsigned long long* table_h, * table_v, * d_rh, * d_rv1, * d_rv2;
    int* d_found, * h_found;

    cudaMalloc(&table_h, TABLE_SIZE * sizeof(unsigned long long));
    cudaMalloc(&table_v, TABLE_SIZE * sizeof(unsigned long long));
    cudaMalloc(&d_rh, sizeof(unsigned long long));
    cudaMalloc(&d_rv1, sizeof(unsigned long long));
    cudaMalloc(&d_rv2, sizeof(unsigned long long));
    cudaMalloc(&d_found, sizeof(int));
    cudaMallocHost(&h_found, sizeof(int));

    cudaMemset(table_h, 0, TABLE_SIZE * sizeof(unsigned long long));
    cudaMemset(d_found, 0, sizeof(int));
    *h_found = 0;

    cudaStream_t stream;
    cudaStreamCreate(&stream);

    unsigned long long start = 1;
    auto t_start = std::chrono::high_resolution_clock::now();

    // Boucle principale
    while (!*h_found) {
        for (int i = 0; i < BATCH_KERNELS; i++) {
            kernel << <N / 256, 256, 0, stream >> > (start, table_h, table_v,
                d_rh, d_rv1, d_rv2, d_found);
            start += N;
        }
        cudaMemcpyAsync(h_found, d_found, sizeof(int), cudaMemcpyDeviceToHost, stream);
        cudaStreamSynchronize(stream);
    }

    double total_sec = std::chrono::duration<double>(
        std::chrono::high_resolution_clock::now() - t_start).count();

    // Recuperation des resultats
    unsigned long long h, v1, v2;
    cudaMemcpy(&h, d_rh, sizeof(unsigned long long), cudaMemcpyDeviceToHost);
    cudaMemcpy(&v1, d_rv1, sizeof(unsigned long long), cudaMemcpyDeviceToHost);
    cudaMemcpy(&v2, d_rv2, sizeof(unsigned long long), cudaMemcpyDeviceToHost);

    printf("COLLISION TROUVEE !\n");
    printf("hash = %llx\n", h);
    printf("msg1 = %llu\n", v1);
    printf("msg2 = %llu\n", v2);
    printf("Temps = %.2f s\n", total_sec);

    return 0;
}