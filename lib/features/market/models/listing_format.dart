enum ListingFormat {
  glb,
  usdz,
  obj,
  fbx,
  gltf,
  blend;

  String get label => switch (this) {
    ListingFormat.glb => 'GLB',
    ListingFormat.usdz => 'USDZ',
    ListingFormat.obj => 'OBJ',
    ListingFormat.fbx => 'FBX',
    ListingFormat.gltf => 'glTF',
    ListingFormat.blend => 'BLEND',
  };
}
