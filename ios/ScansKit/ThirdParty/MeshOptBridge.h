#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// meshoptimizer (MIT, github.com/zeux/meshoptimizer) uchun Swift ko'prigi.
/// Mesh'ni indekslaydi, decimate (soddalashtiradi) qiladi — Scaniverse'ning
/// "Simplification" bosqichiga mos.
@interface MeshOptBridge : NSObject

/// Uchburchak sonini `targetTriangles`gacha kamaytiradi. Natija: yangi indeks
/// buferi (uint32). Pozitsiyalar o'zgarmaydi (indekslar qayta ishlatiladi).
/// Muvaffaqiyatsizlikda nil.
+ (nullable NSData *)simplifyIndices:(const uint32_t *)indices
                          indexCount:(NSUInteger)indexCount
                           positions:(const float *)positions
                         vertexCount:(NSUInteger)vertexCount
                     targetTriangles:(NSUInteger)targetTriangles
                        targetError:(float)targetError;

@end

NS_ASSUME_NONNULL_END
