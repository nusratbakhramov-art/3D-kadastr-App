#import <Foundation/Foundation.h>

//! ScansKit framework versiyasi.
FOUNDATION_EXPORT double ScansKitVersionNumber;
FOUNDATION_EXPORT const unsigned char ScansKitVersionString[];

// ObjC++ / C ko'priklarni framework moduliga ochamiz — ScansKit ichidagi Swift
// (xatlas UV unwrap, meshoptimizer, texios) shular orqali ishlaydi. Uchalasi
// ham Public header sifatida belgilanadi.
#import <ScansKit/NSDKXAtlasBridge.h>
#import <ScansKit/MeshOptBridge.h>
#import <ScansKit/TexIOSBridge.h>
