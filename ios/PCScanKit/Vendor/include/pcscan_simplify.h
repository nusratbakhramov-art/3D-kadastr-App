#ifndef PCSCAN_SIMPLIFY_H
#define PCSCAN_SIMPLIFY_H
#ifdef __cplusplus
extern "C" {
#endif
// Mesh decimation. outIndices oldindan indexCount o'lchamда ajratilgan bo'lishi kerak.
// Yangi indeks sonini qaytaradi.
int pcscan_simplify(const float* positions, int vertCount,
                    const unsigned int* indices, int indexCount,
                    unsigned int* outIndices, float targetRatio);
#ifdef __cplusplus
}
#endif
#endif
