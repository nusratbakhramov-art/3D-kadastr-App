#import <Foundation/Foundation.h>

//! PCScanKit framework versiyasi.
FOUNDATION_EXPORT double PCScanKitVersionNumber;
FOUNDATION_EXPORT const unsigned char PCScanKitVersionString[];

// texrecon/poisson/meshopt C ko'priklarini framework moduliga ochamiz —
// PCScanKit ichidagi Swift shular orqali native rekonstruksiyani chaqiradi.
// (Framework'da Swift bridging-header ishlamaydi → umbrella + module-map kerak;
// bu 3 header Public sifatida belgilanadi, header'lar Vendor/include da.)
#import <PCScanKit/pcscan_tex.h>
#import <PCScanKit/pcscan_poisson.h>
#import <PCScanKit/pcscan_simplify.h>
