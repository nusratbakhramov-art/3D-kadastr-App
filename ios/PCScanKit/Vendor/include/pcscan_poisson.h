#ifndef PCSCAN_POISSON_H
#define PCSCAN_POISSON_H
#ifdef __cplusplus
extern "C" {
#endif
// Poisson Surface Reconstruction: nuqta-bulut PLY (points+normals) -> mesh PLY.
// depth: rekonstruksiya chuqurligi (8-9). 0 = muvaffaqiyat, aks holda xato.
int pcscan_poisson(const char* in_ply, const char* out_ply, int depth);
#ifdef __cplusplus
}
#endif
#endif
