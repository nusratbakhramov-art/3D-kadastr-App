#ifndef PCSCAN_TEX_H
#define PCSCAN_TEX_H
#ifdef __cplusplus
extern "C" {
#endif
/* MVE scene (dir with .jpg + .cam) + binary PLY mesh -> textured OBJ+MTL+PNG at out_prefix. 0 = ok. */
int pcscan_texture(const char* scene_dir, const char* mesh_ply, const char* out_prefix, const char* tmp_dir);
#ifdef __cplusplus
}
#endif
#endif
