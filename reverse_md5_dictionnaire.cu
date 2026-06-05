#include <cuda_runtime.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <fstream>
#include <string>
#include <vector>

//Hash MD5 a casser
const char* TARGET = "ae43792485331fa311a50a7972118adc";

//Chemin vers le dictionnaire
const char* DICT_PATH = "C:/Users/etudiants/Desktop/rockyou.txt";

#define MAX_LEN 32          // longueur max mdp
#define BATCH (1 << 18)     // 262144 mots testes par lot

// Tables constantes MD5
__constant__ unsigned int d_k[64];
__constant__ unsigned int d_r[64] = {
    7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
    5, 9,14,20, 5, 9,14,20, 5, 9,14,20, 5, 9,14,20,
    4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
    6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21
};

// Rotation a gauche sur 32 bits
__device__ unsigned int rol(unsigned int x, unsigned int n) {
    return (x << n) | (x >> (32 - n));
}

// MD5 prend un message et renvoie son hash 128 bits
__device__ void md5(const unsigned char* msg, int len, unsigned int* out) {
    // Padding 
    unsigned char buf[64] = { 0 };
    for (int i = 0; i < len; i++) buf[i] = msg[i];
    buf[len] = 0x80;
    unsigned long long bits = (unsigned long long)len * 8;
    for (int i = 0; i < 8; i++) buf[56 + i] = (bits >> (i * 8)) & 0xFF;

    // Decoupage en 16 mots de 32 bits
    unsigned int w[16];
    for (int i = 0; i < 16; i++)
        w[i] = buf[i * 4] | (buf[i * 4 + 1] << 8) | (buf[i * 4 + 2] << 16) | (buf[i * 4 + 3] << 24);

    // Valeurs initiales MD5
    unsigned int a = 0x67452301, b = 0xEFCDAB89, c = 0x98BADCFE, d = 0x10325476;

    // 64 tours de melange
    for (int i = 0; i < 64; i++) {
        unsigned int f, g;
        if (i < 16) { f = (b & c) | (~b & d);  g = i; }
        else if (i < 32) { f = (d & b) | (~d & c);  g = (5 * i + 1) % 16; }
        else if (i < 48) { f = b ^ c ^ d;           g = (3 * i + 5) % 16; }
        else { f = c ^ (b | ~d);        g = (7 * i) % 16; }

        unsigned int temp = d;
        d = c;
        c = b;
        b = b + rol(a + f + d_k[i] + w[g], d_r[i]);
        a = temp;
    }

    // Hash final
    out[0] = 0x67452301 + a;
    out[1] = 0xEFCDAB89 + b;
    out[2] = 0x98BADCFE + c;
    out[3] = 0x10325476 + d;
}

// Kernel chaque thread  = 1 MDP
__global__ void kernel(unsigned char* pwds, int* lens, int count,
    unsigned int t0, unsigned int t1,
    unsigned int t2, unsigned int t3, int* found)
{
    int id = blockIdx.x * blockDim.x + threadIdx.x;
    if (id >= count) return;

    // Calcul du hash du MDP du thread
    unsigned int h[4];
    md5(pwds + id * MAX_LEN, lens[id], h);

    // Comparaison avec la cible
    if (h[0] == t0 && h[1] == t1 && h[2] == t2 && h[3] == t3)
        *found = id;
}

// Convertit le hash hexadecimal en 4 entiers
void hex_to_target(const char* hex, unsigned int out[4]) {
    for (int i = 0; i < 16; i++) {
        unsigned int byte;
        sscanf(hex + i * 2, "%2x", &byte);
        out[i / 4] |= byte << ((i % 4) * 8);
    }
}

int main() {
    printf("Hash cible   : %s\n", TARGET);
    printf("Dictionnaire : %s\n\n", DICT_PATH);

    //Preparer le hash cible
    unsigned int target[4] = { 0 };
    hex_to_target(TARGET, target);

    //Calculer la table k[] et l'envoyer au GPU
    unsigned int h_k[64];
    for (int i = 0; i < 64; i++)
        h_k[i] = (unsigned int)floor(fabs(sin(i + 1.0)) * 4294967296.0);
    cudaMemcpyToSymbol(d_k, h_k, sizeof(h_k));

    //Allouer la memoire GPU et CPU
    unsigned char* d_pwds;
    int* d_lens;
    int* d_found;
    cudaMalloc(&d_pwds, BATCH * MAX_LEN);
    cudaMalloc(&d_lens, BATCH * sizeof(int));
    cudaMalloc(&d_found, sizeof(int));

    unsigned char* h_pwds = (unsigned char*)calloc(BATCH, MAX_LEN);
    int* h_lens = (int*)malloc(BATCH * sizeof(int));
    std::vector<std::string> words(BATCH);

    //Ouvrir le dictionnaire
    std::ifstream file(DICT_PATH);

    std::string line;
    unsigned long long total = 0;

    //Boucle lire et tester par lots
    while (std::getline(file, line)) {
        int count = 0;

        // Remplir un lot avec BATCH mots du dictionnaire
        do {
            while (!line.empty() && (line.back() == '\r' || line.back() == '\n'))
                line.pop_back();
            if (!line.empty() && line.size() < MAX_LEN) {
                words[count] = line;
                memcpy(h_pwds + count * MAX_LEN, line.data(), line.size());
                h_lens[count] = (int)line.size();
                count++;
            }
        } while (count < BATCH && std::getline(file, line));

        //Copier le lot vers le GPU
        cudaMemcpy(d_pwds, h_pwds, BATCH * MAX_LEN, cudaMemcpyHostToDevice);
        cudaMemcpy(d_lens, h_lens, BATCH * sizeof(int), cudaMemcpyHostToDevice);
        int init = -1;
        cudaMemcpy(d_found, &init, sizeof(int), cudaMemcpyHostToDevice);

        //Lancer le kernel
        kernel << <(count + 255) / 256, 256 >> > (d_pwds, d_lens, count,
            target[0], target[1], target[2], target[3], d_found);

        //Recuperer le resultat
        int found;
        cudaMemcpy(&found, d_found, sizeof(int), cudaMemcpyDeviceToHost);
        total += count;

        //Si thread a trouvé afficher et terminer
        if (found >= 0) {
            printf("\nTROUVE : %s\n", words[found].c_str());
            printf("Tentatives : %llu\n", total);
            return 0;
        }

        printf("Testes : %llu\r", total);
        fflush(stdout);
    }

    printf("\nMot de passe non trouve.\n");
    return 0;
}