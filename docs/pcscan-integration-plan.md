# PCScan (RoomPlan+ObjectCapture skaner) → kadastr "#2" integratsiya rejasi

**Maqsad:** `/Users/ofoqovabdulboriy/StudioProjects/PCScan` (native iOS LiDAR xona
skaneri — RoomPlan struktura + Object Capture tekstura + texrecon/poisson
rekonstruksiya) ni kadastr Flutter ilovasi ichiga olib o'tish. Profildagi
skan-picker'da **"#2"** bosilganda PCScan ochiladi. **"#1" = nsdk (ScansKit)**
allaqachon ulangan — bu uni takrorlaydi, buzmaydi.

## Bu ScansKit (nsdk) integratsiyasining egizagi

Xuddi shu isbotlangan pattern: alohida embedded framework (`PCScanKit`), iOS 17
target, min-15 Runner uni **import qilmaydi** — ish vaqtida `Bundle.load()` +
`@objc PCScanEntry` (dlopen). Qarang: [nsdk-integration-plan.md](nsdk-integration-plan.md).

| | PCScan | ScansKit (nsdk) — ulangan |
|---|---|---|
| Turi | SwiftUI `@main` App, `AppState` phase mashinasi | UIKit |
| Kod | 49 swift, 0 metal, 0 ObjC++ | 45 swift + metal + ObjC++ |
| Min iOS | 17.0 (RoomPlan/ObjectCapture) | 17.0 |
| Team / bundle | KHGXWF53U9 / com.pcscan.app | KHGXWF53U9 |
| Native lib | **29M** statik, device-arm64: poisson(24M) tex mve jpeg png tbb tbbmalloc meshopt pcscan | 16M texios/xatlas |
| Ko'prik | 3 C header (`pcscan_tex/poisson/simplify.h`), sof `extern "C"` | ObjC++ bridge'lar |

## Nega ScansKit'dan SODDAROQ

1. **ObjC klass to'qnashuvi YO'Q.** ScansKit'da `XAtlasBridge`/`XAtlasResult`
   ObjC klasslarini prefikslash kerak edi. PCScan header'lari sof C (`extern "C"`)
   — ObjC klass yo'q → runtime nom to'qnashuvi yo'q, rename kerak emas.
2. **NSDK-embed muammosi TAKRORLANMAYDI.** ScansKit NSDK dinamik SPM framework'iga
   bog'liq edi (u embed qilinmay qolib crash bergan). PCScan'da **hamma lib
   statik** → dinamik bog'liqlik yo'q → embed miss bo'lmaydi. Faqat PCScanKit.framework
   embed qilinadi.
3. **Statik lib overlap xavfsiz.** `jpeg/png/tbb/meshopt` ikkala framework'da ham
   bor, lekin har biri alohida dylib ichiga statik linklanadi (two-level namespace)
   → symbol'lar izolatsiyalanadi, clash yo'q.
4. **Swift nom to'qnashuvi** (FusionService, RoomGeometry, MeshPrep, StorageService,
   PermissionsService, Theme, ScanRecord, DeviceCapability...) — alohida Swift modul
   `PCScanKit` avtomatik namespace qiladi (ScansKit'dagidek).

## Arxitektura

```
Flutter: profil "#2" onTap
  → MethodChannel("kadastr/pcscan_scanner").invokeMethod("open")
  → AppDelegate.loadPCScanEntry()  (Bundle.load PCScanKit.framework, dlopen)
       if #available(iOS 17):  present PCScanEntry().present(from:)
       else:                   FlutterError("UNSUPPORTED")
```

`PCScanKit` public API:
```swift
public enum PCScanKit {
  public static func makeRoot() -> UIViewController   // RootView+AppState → UIHostingController
  public static var isAvailable: Bool { get }         // iOS 17
}
@objc(PCScanEntry) public final class PCScanEntry: NSObject {
  @objc public func present(from presenter: UIViewController)
}
```

## Bosqichli reja

**Phase 1a — Kod ko'chirish** ✅ (2026-07-14, bajarildi — `ios/PCScanKit/`)
- [x] `PCScan/{App,Core,Features,UI}` + `Info.plist` → `ios/PCScanKit/` (48 swift).
- [x] `Vendor/{lib,include}` (29M statik, arm64 device-only) → `ios/PCScanKit/Vendor/`.
- [x] `@main PCScanApp.swift` **tashlandi**; bridging-header ko'chirilmadi (umbrella
      o'rnini bosadi).
- [x] `PCScanKit.swift` public entry: `makeRoot()` (`RootView`+`AppState` →
      `UIHostingController`, `PCScanContainerViewController` fullScreen + suzuvchi
      "Yopish" tugmasi) + `@objc(PCScanEntry)`.
- [x] `PCScanKit.h` umbrella: 3 C header (`pcscan_tex/poisson/simplify.h`) Public.
- [x] Toza: `Bundle.main` yo'q, `UIApplication.shared`/`SceneDelegate`/`exit()` yo'q,
      barcha import'lar system framework — framework'ga mos. Swift C-bridge chaqiruvlari
      (`pcscan_texture/poisson/simplify`) umbrella orqali hal bo'ladi.

**Phase 1b — PCScanKit target (pbxproj surgery)** ✅ (2026-07-14, bajarildi)
- [x] `add_pcscankit.rb`: framework target (iOS 17, DEFINES_MODULE, c++17). 49 source,
      4 public header (umbrella + 3 C), 9 statik lib ref.
- [x] `HEADER_SEARCH_PATHS`, `LIBRARY_SEARCH_PATHS[sdk=iphoneos*]`,
      `OTHER_LDFLAGS[sdk=iphoneos*]` (device-only statik link) sozlandi.
- [x] Runner'ga weak-link + **mavjud "Embed Frameworks" fazasiga** embed (yangi
      faza EMAS → ScansKit urgan build cycle takrorlanmadi).
- [x] **Simulyator gate:** `pcscan_poisson`/`pcscan_simplify` chaqiruvlari
      `#if targetEnvironment(simulator)` bilan o'raldi (TexReconService'dagi
      `pcscan_texture` uslubida) — aks holda simulyator undefined-symbol bilan
      link'ni buzardi.
- [x] **Tasdiqlandi:** simulyator build ✓ (3 framework embed, cycle yo'q), device
      build ✓ (PCScanKit.framework arm64, `PCScanEntry` @objc symbol, 115 texrecon/
      poisson symbol statik linklangan, faqat o'z @rpath — NSDK-uslub yo'qolgan
      dinamik dep YO'Q).

**Phase 1c — Flutter ↔ native ko'prik** ✅ (2026-07-14, bajarildi)
- [x] `AppDelegate`: `kadastr/pcscan_scanner` kanali (`isAvailable`/`open`) +
      `loadPCScanEntry()` (dlopen, `loadScansKitEntry()` egizagi) + iOS-17 gate.
      `PCScanEntry.present(from:)` → selector `presentFrom:`.
- [x] `profile_screen.dart` `_ScanPickerSheet`: `_pcscanScanner` kanali +
      `_openPcscan()`; "#2" onTap ulandi (eski TODO olib tashlandi).
- [x] Tasdiqlandi: `flutter analyze` toza, device build ✓.

**Phase 3 — Info.plist** ✅ (2026-07-14)
- [x] Runner Info.plist'da NSCameraUsageDescription + location + photo library bor.
      Object Capture qo'shimcha ruxsat talab qilmaydi → qo'shimcha kerak emas.

**Phase 5 — Test** ✅ (2026-07-14, bajarildi)
- [x] Simulator: app + PCScanKit embed, statik lib'lar `[sdk=iphoneos*]` gate,
      cycle yo'q — ✓ Built.
- [x] LiDAR qurilma (iPhone 13 Pro Max, iOS 26.3.1): signed build + install +
      launch (dyld crash yo'q) → **"#2" → PCScan onboarding ochildi, "Yopish"
      qaytardi** (foydalanuvchi tasdiqladi). `Library not loaded` yo'q — dlopen
      zanjiri sog'lom (hammasi statik, yo'qolgan dinamik dep yo'q).

## Ochiq savollar / risklar
- **Bundle o'lchami:** PCScan +29M (poisson yolg'iz 24M). ScansKit +16M bilan
  birga ~45M sof skan lib'lari. Kerak bo'lsa poisson strip/thin ko'riladi.
- **SwiftUI dismiss UX:** PCScan o'zini butun oyna deb hisoblaydi. Phase 1a'da
  nav + "Yopish" bilan o'raladi; yakuniy UX Phase 1c'da sozlanadi.
- **Simulyator:** RoomPlan/ObjectCapture simulyatorда ishlamaydi + statik lib'lar
  device-only → simulyator faqat LINK/launch sanity, skan device'da.
- Keyinroq: PCScan natijasini (USDZ/OBJ) kadastr backend'iga bog'lash — doirada emas.
