#import "MeshOptBridge.h"
#import "meshoptimizer/meshoptimizer.h"
#include <vector>

@implementation MeshOptBridge

+ (nullable NSData *)simplifyIndices:(const uint32_t *)indices
                          indexCount:(NSUInteger)indexCount
                           positions:(const float *)positions
                         vertexCount:(NSUInteger)vertexCount
                     targetTriangles:(NSUInteger)targetTriangles
                        targetError:(float)targetError {
    if (indexCount < 3 || vertexCount == 0) return nil;

    size_t targetIndexCount = targetTriangles * 3;
    if (targetIndexCount >= indexCount) {
        // Allaqachon target'dan kichik — o'zini qaytaramiz
        return [NSData dataWithBytes:indices length:indexCount * sizeof(uint32_t)];
    }

    std::vector<unsigned int> result(indexCount);
    float resultError = 0.0f;
    size_t newCount = meshopt_simplify(
        result.data(), indices, indexCount,
        positions, vertexCount, sizeof(float) * 3,
        targetIndexCount, targetError,
        meshopt_SimplifyLockBorder,  // chekka qirralarni saqlaydi (teshik ochilmasin)
        &resultError);

    if (newCount < 3) return nil;
    return [NSData dataWithBytes:result.data() length:newCount * sizeof(uint32_t)];
}

@end
