# nsdk (ScansApp) → kadastr integratsiya rejasi

**Maqsad:** `/Users/ofoqovabdulboriy/StudioProjects/nsdk` (native iOS "ScansApp",
Niantic Spatial SDK asosidagi on-device 3D skaner) ni kadastr Flutter ilovasi
ichiga to'liq olib o'tish. Profildagi skan-picker'da **"#1"** bosilganda nsdk
ochiladi.

## Qarorlar (2026-07-14)

1. **Min iOS = 15 saqlanadi.** NSDK iOS 17 talab qiladi → skan faqat iOS 17+ da
   yoqiladi, NSDK/ScansKit **weak-link** qilinadi. iOS 15/16 qurilmada app
   normal ochiladi, "#1" esa "qo'llab-quvvatlanmaydi" beradi. (kadastr allaqachon
   skan funksiyalarini `if #available(iOS 17)` bilan gate qiladi — shu uslub.)
2. **"#1" → to'liq nsdk** (bosh menyu: "3D Mesh skan" + "Xona xaritasi (VPS)").
3. **Ikkala pipeline saqlanadi:** "#1" = nsdk; "#2" = kadastr'ning mavjud native
   skani (`room_plan_scanner` / `saved_scans`). Eski kod buzilmaydi.

## Nima o'zgaradi (holat)

| | nsdk (ScansApp) | kadastr (mobile) |
|---|---|---|
| Min iOS | 17.0 | **15.0 (saqlanadi)** |
| Build | XcodeGen + SPM | Flutter + CocoaPods |
| Signing | com.hamrayev.scansapp / KHGXWF53U9 | uz.kadastr.kadastr |
| Skan kodi | ScansApp/ (45 swift + C/C++ + metal) | ios/Runner/ + RoomScan/ (mavjud) |

## Arxitektura: `ScansKit` alohida modul

nsdk kodi **alohida embedded framework** (`ScansKit`) sifatida o'raladi. Sabab:
Swift'da namespace yo'q, kadastr'da esa allaqachon `MeshHoleFiller`,
marching-cubes jadvallari, `.metal` shaderlar bor — to'g'ridan `ios/Runner/` ga
qo'shsak nom to'qnashadi va link buziladi. Modul chegarasi buni, NSDK/C++
bog'liqliklarini va Metal bundle'ini izolatsiya qiladi.

```
Flutter: profil "#1" onTap
  → MethodChannel("kadastr/nsdk_scanner").invokeMethod("open")
  → AppDelegate handler
       if #available(iOS 17) && ScansKit mavjud:
          present  ScansKit.makeMainMenu()   // nsdk MainMenu (Mesh + VPS)
       else:
          FlutterError("UNSUPPORTED", "iOS 17+ va LiDAR kerak")
```

`ScansKit` public API (minimal):
```swift
public enum ScansKit {
  public static func makeMainMenu() -> UIViewController   // nsdk MainMenuVC
  public static var isAvailable: Bool { get }             // iOS17 + NSDK yuklandimi
}
```

## 3 ta to'siq va yechimi

### 1. iOS 17 vs 15 — weak-link
- `ScansKit.framework` **"Embed Without Signing" + Optional (weak)** qilib
  linklanadi; "#1" handler avval `if #available(iOS 17, *)` va
  `ScansKit.isAvailable` ni tekshiradi. iOS 15/16'da weak framework yuklanmaydi →
  app crash bo'lmaydi.
- **Phase 0 natijasi:** NSDK `Package.swift` = **`.iOS(.v15)`** — NSDK'ning o'zi
  iOS 15'ni qo'llaydi (binar 15'da yuklanadi). Demak weak-link faqat **ScansKit**
  (bizning wrapper — nsdk kodi iOS 17 API'lariga yozilgani uchun target=17) ustida
  bo'ladi, uchinchi-tomon binari ustida emas. Bu biz nazorat qiladigan standart
  pattern → risk PAST. Yakuniy tasdiq: Phase 5 device test.

### 2. Nom to'qnashuvi — modul chegarasi + ObjC rename
**Phase 0 grep natijasi:**
- **Swift tiplar (modul HAL QILADI):** `Cam ExportError Keyframe MeshHoleFiller
  Plane Result` ikkala repo'da bor — ScansKit alohida Swift modul bo'lgani uchun
  avtomatik hal bo'ladi. (`AppDelegate` ham kesishadi, lekin nsdk'niki tashlanadi.)
- **ObjC klasslar (modul HAL QILMAYDI — rename SHART):** `XAtlasBridge` va
  `XAtlasResult` kadastr `ios/Runner/Cpp/` da HAM bor. ObjC klass nomlari butun app
  runtime'ida yagona → ikkitasi bo'lsa "implemented in both" + noaniq yuklash.
  **Yechim:** nsdk nusxasidagi bridge klasslarini prefikslash —
  `XAtlasBridge`→`NSDKXAtlasBridge`, `XAtlasResult`→`NSDKXAtlasResult`
  (`.h/.mm` + Swift chaqiruvlar). `MeshOptBridge` kadastr'da yo'q — tegilmaydi.
- **Metal:** `ScansKit` o'z `default.metallib`'ini quradi. Renderer'lar
  (`SplatRenderer`, `MetalTextureBaker`, `TextureView`) `makeDefaultLibrary()`
  o'rniga `Bundle(for:)` / `makeDefaultLibrary(bundle:)` ishlatishi kerak.

### 3. C/C++ + SPM + Metal build sozlamalari
- texios (`libtexios.a` + libjpeg/png/tiff/tbb), xatlas, meshoptimizer →
  `ScansKit` target'iga; `LIBRARY_SEARCH_PATHS`, `OTHER_LDFLAGS`
  (`-ltexios -ljpeg -lpng -ltiff -ltbb -lz -lc++`), `CLANG_CXX_LANGUAGE_STANDARD=c++17`.
- **Bridging-header → module-map:** framework'da bridging-header ishlamaydi.
  ObjC++ ko'priklar (`XAtlasBridge`, `MeshOptBridge`) va C `TexIOSBridge.h`
  `ScansKit` umbrella-header / module-map orqali Swift'ga ochiladi.
- NSDK SPM paketi (`nsdk-library-xcframework` 4.1.0) Runner emas, **ScansKit**
  target'iga ulanadi.

## Bosqichli reja

**Phase 0 — Tayyorgarlik** ✅ (2026-07-14, bajarildi)
- [x] NSDK min-deployment: `Package.swift` = **`.iOS(.v15)`** → min-15 app'ga
      ulanishga to'siq yo'q (binar `CArdk.xcframework` paket ichida local).
- [x] Nom to'qnashuvlari: Swift'lar module bilan hal; ObjC `XAtlasBridge`/
      `XAtlasResult` rename SHART ("### 2" ga qarang).

**Phase 1a — Kod ko'chirish** ✅ (2026-07-14, bajarildi — `ios/ScansKit/`)
- [x] `ScansApp/` (AR, MeshScan, RoomScan, Splat, ThirdParty) → `ios/ScansKit/`
      (AppDelegate/SceneDelegate tashlandi; texios/src tashlandi). 45 swift, 3 metal,
      2 .mm, 5 .a (device-arm64), xatlas+meshopt C++ manba.
- [x] ObjC rename: `XAtlasBridge`→`NSDKXAtlasBridge`, `XAtlasResult`→`NSDKXAtlasResult`.
- [x] Metal: 4× `makeDefaultLibrary()` → `scansKitDefaultLibrary()` (framework bundle).
- [x] texios `ios_texture` `#if !targetEnvironment(simulator)` bilan gate (lib device-only).
- [x] Public entry `ScansKit.swift` (`makeMainMenu()` + `isAvailable`), umbrella
      `ScansKit.h` (NSDKXAtlasBridge/MeshOptBridge/TexIOSBridge public), `NSDKConfig` (token="").

**Phase 1b — ScansKit target (pbxproj surgery — KEYINGI, invaziv)**
- [ ] Runner loyihasiga `ScansKit` framework target (xcodeproj ruby gem;
      `add_roomscan.rb` uslubida `add_scanskit.rb`).
- [ ] Sources: ScansKit/*.swift + *.mm + xatlas.cpp + meshoptimizer/*.cpp; `.metal`
      → Compile Sources; `.a` → Link Binary; 3 bridge .h = Public; umbrella = ScansKit.h.
- [ ] Build settings: `IPHONEOS_DEPLOYMENT_TARGET=17`, `DEFINES_MODULE=YES`,
      `CLANG_CXX_LANGUAGE_STANDARD=c++17`, `LIBRARY_SEARCH_PATHS` (texios/lib),
      `OTHER_LDFLAGS[sdk=iphoneos*]` = `-ltexios -ljpeg -lpng -ltiff -ltbb -lz -lc++`
      (faqat DEVICE SDK — simulator link buzilmasin), signing = kadastr team.
- [ ] NSDK SPM paketini **ScansKit** target'iga ulash (gem bilan yoki Xcode GUI).
      ⚠ gem'da SPM biroz ishonchsiz — kerak bo'lsa GUI fallback (File > Add Packages).
- [ ] ScansKit'ni Runner'ga **Embed + Optional (weak)** qilib ulash.

**Phase 1c — Flutter ↔ native ko'prik**
- [ ] `AppDelegate`: `kadastr/nsdk_scanner` kanali + `if #available(iOS 17)` +
      `ScansKit.makeMainMenu()` present.
- [ ] `profile_screen.dart` `_ScanPickerSheet` "#1" onTap → invokeMethod("open").

**Phase 3 — Signing / Info.plist**
- [ ] ScansKit'ni kadastr team/bundle ostiga; `NSDKView`/AR ruxsatlari.
- [ ] Info.plist: kamera ✅ bor, location ✅ bor (VPS uchun). Qo'shimcha kerak emas.

**Phase 4 — Ko'prik (Flutter ↔ native)**
- [ ] `AppDelegate`'da `kadastr/nsdk_scanner` kanali + iOS-17/isAvailable gate.
- [ ] Flutter: `lib/features/profile/profile_screen.dart` `_ScanPickerSheet`'da
      "#1" onTap → `MethodChannel("kadastr/nsdk_scanner").invokeMethod("open")`.
      "#2" hozircha bo'sh (mavjud pipeline'ga keyin ulanadi).

**Phase 5 — Test** ✅ (2026-07-14, bajarildi)
- [x] Simulator: app + ScansKit LINK/embed (`flutter build ios`) — muvaffaqiyatli.
- [x] LiDAR qurilma (iPhone 13 Pro Max, iOS 26.3.1): signed build + o'rnatish +
      launch (dyld crash yo'q) → "#1" → nsdk menyu → Mesh skan → **texios HQ
      tekstura pipeline'i device-arm64'da ishladi** (atlas generatsiyasi). Hech
      qanday `Library not loaded` yo'q.
- [ ] iOS 15/16 qurilma: app ochiladi, "#1" → "UNSUPPORTED" (mavjud emas, tekshirilmagan).

**Phase 1b tuzatish — NSDK embed (2026-07-14)**
- `add_scanskit.rb` NSDK SPM mahsulotini **ScansKit** target'iga uladi (ScansKit
  uni qattiq `LC_LOAD_DYLIB @rpath/NSDK.framework/NSDK` bilan link qiladi). Ammo
  framework o'z SPM bog'liqligini embed qilmaydi → NSDK.framework app bundle'ga
  tushmadi → dlopen'da `Library not loaded` crash bo'lardi.
- **Yechim:** `add_nsdk_embed.rb` — Runner'ga "Embed NSDK" copy-files fazasi
  (faqat embed, Runner NSDK'ni LINK qilmaydi; faza `Thin Binary`'dan oldin —
  ScansKit embed'i urgan build cycle'dan qochish uchun). Tasdiqlandi:
  `Runner.app/Frameworks/NSDK.framework` (arm64) bor.

## Ochiq savollar / risklar
- ~~NSDK binary min-iOS~~ ✅ hal (Phase 0): Package.swift `.iOS(.v15)`.
- ScansKit + NSDK/CArdk.xcframework → app bundle o'lchamiga ta'siri (katta).
- texios static lib'lar **simulator (arm64-sim) slice**iga bor-yo'qligi — Phase 1'da
  tekshiriladi; bo'lmasa sim build uchun stub yoki device-only build kerak.
- Keyinroq: nsdk natijasini (model fayli) kadastr backend'iga bog'lash — hozir
  doirada emas ("#1" faqat ochadi).
