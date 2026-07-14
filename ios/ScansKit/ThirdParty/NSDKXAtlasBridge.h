#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// xatlas natijasi: yangi vertexlar (chart chegaralarida dublikatlangan),
/// ularning atlas UV koordinatalari (texel birligida) va asl vertexga xref.
@interface NSDKXAtlasResult : NSObject
@property (nonatomic) uint32_t width;
@property (nonatomic) uint32_t height;
@property (nonatomic) uint32_t vertexCount;
@property (nonatomic) uint32_t indexCount;
/// float2 * vertexCount — atlas texel koordinatalari
@property (nonatomic, strong) NSData *uvs;
/// uint32 * vertexCount — asl (kirish) vertex indeksi
@property (nonatomic, strong) NSData *xrefs;
/// uint32 * indexCount — yangi indeks buferi
@property (nonatomic, strong) NSData *indices;
@end

/// xatlas (MIT, github.com/jpcy/xatlas) uchun Swift'ga qulay ko'prik.
@interface NSDKXAtlasBridge : NSObject

/// Yagona atlasga UV unwrap. atlasCount > 1 chiqsa texelsPerUnit kamaytirilib
/// qayta uriniladi. Muvaffaqiyatsizlikda nil.
+ (nullable NSDKXAtlasResult *)generateWithPositions:(const float *)positions
                                     vertexCount:(uint32_t)vertexCount
                                         indices:(const uint32_t *)indices
                                      indexCount:(uint32_t)indexCount
                                      resolution:(uint32_t)resolution;

@end

NS_ASSUME_NONNULL_END
