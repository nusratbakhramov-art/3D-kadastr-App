// XAtlasBridge — Objective-C interface to xatlas (C++ UV atlas generator).
// Swift'dan chaqirish uchun mo'ljallangan, plain ObjC API (C++ ko'rinmaydi).
//
// Foydalanish: ARKit mesh (vertices + indices) → atlas UV map + atlas o'lchami.
// Output natija mesh, asl mesh'dan ko'p bo'lishi mumkin (chartlar bo'yicha
// bo'linadi). Output triangle'lar asl indices'iga olib bormaydi — yangi index
// buffer beradi.

#ifndef XATLAS_BRIDGE_H
#define XATLAS_BRIDGE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XAtlasResult : NSObject
@property (nonatomic, readonly) NSUInteger atlasWidth;
@property (nonatomic, readonly) NSUInteger atlasHeight;
@property (nonatomic, readonly) NSUInteger vertexCount;
@property (nonatomic, readonly) NSUInteger indexCount;
/// Output vertex world positions. Length = vertexCount * 3 floats (x, y, z).
@property (nonatomic, readonly) NSData *positions;
/// Output normals. Length = vertexCount * 3 floats.
@property (nonatomic, readonly) NSData *normals;
/// Output UV coordinates [0..1]. Length = vertexCount * 2 floats (u, v).
@property (nonatomic, readonly) NSData *uvs;
/// Output triangle indices. Length = indexCount uint32_t.
@property (nonatomic, readonly) NSData *indices;
/// For each output vertex, the index of the original mesh vertex it came from.
/// Length = vertexCount uint32_t. Useful for color/normal lookup.
@property (nonatomic, readonly) NSData *originalIndices;
@end

@interface XAtlasBridge : NSObject

/// xatlas orqali ARKit mesh'ni UV unwrap qilish. Input world-space positions
/// va normals, hamda triangle index buffer. atlasResolution — atlas'ning
/// maksimal o'lchami (default 2048). Real o'lcham bunga teng yoki kichikroq.
+ (nullable XAtlasResult *)unwrapMeshWithPositions:(NSData *)positions
                                            normals:(NSData *)normals
                                            indices:(NSData *)indices
                                       vertexCount:(NSUInteger)vertexCount
                                    triangleCount:(NSUInteger)triangleCount
                                  atlasResolution:(uint32_t)atlasResolution
                                            error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif /* XATLAS_BRIDGE_H */
