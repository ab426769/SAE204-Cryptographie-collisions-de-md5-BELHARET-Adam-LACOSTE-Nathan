#pragma once
// Ce fichier annonce les fonctions qu'on va écrire dans md5.cpp

#ifndef MD5_H 
#define MD5_H   

#include <string>   // Pour utiliser std::string les chaines de caractères
#include <cstdint>  // Pour uint8_t, uint32_t les entiers qui ont une taille fixe

// Calcule le hash MD5 d'une chaîne de caractères
std::string md5(const std::string& message);

// Calcule le hash MD5 d'un tableau d'octets bruts
std::string md5_raw(const uint8_t* data, size_t length);

#endif