#ifndef TEXIOS_BRIDGE_H
#define TEXIOS_BRIDGE_H
#ifdef __cplusplus
extern "C" {
#endif
// mvs-texturing (Let There Be Color!) on-device entry.
// scene: papka kf_*.jpg + kf_*.cam ; mesh: mesh.ply ; outPrefix: .../texout
// keepUnseen: 1 (teshiksiz), outlier: 1 (gauss_damping). 0 = muvaffaqiyat.
int ios_texture(const char* scene, const char* mesh,
                const char* outPrefix, int keepUnseen, int outlier);
#ifdef __cplusplus
}
#endif
#endif
