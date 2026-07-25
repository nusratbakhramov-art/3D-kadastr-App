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

// os_proc_available_memory() — qurilma-adaptiv xotira byudjeti (MemoryBudget.swift).
// App tarafidagi bridging-header'ning kit-ekvivalenti: framework Swift'i bu system
// funksiyani umbrella orqali ko'radi (bridging-header framework'da ishlamaydi).
#import <os/proc.h>
