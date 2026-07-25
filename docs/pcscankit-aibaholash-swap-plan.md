# #2 (PCScanKit) skanerni AI Baholash skaneri o'rniga qo'yish — reja + prompt list

**Savolga javob: HA, joylay olamiz.** Flutter va backend'ni deyarli tegmasdan.

Strategiya: AI Baholash ikki MethodChannel orqali ishlaydi (`kadastr/room_plan_scanner` +
`kadastr/saved_scans`). Ular ortidagi **native handler**'ni `RoomScanBridge` dan yangi
`PCScanBridge` ga **provider-flag** bilan almashtiramiz. Flutter ekranlari va Dart wrapper'lari
shakl-neytral (`startTexturedScan`/`process(id)`/`listScanFiles(id)`/`previewModel(path)`),
shuning uchun ular tegilmaydi. Backend o'zgarishsiz — u yana `scan_files={glb,usdz}` +
`scan_usdz_key=<glb>` oladi.

## Backend'ga nima ketadi (o'zgarmaydi)
`POST /ai-valuations/upload` (multipart, `category=scan_bundle`) → S3 kalitlar → `POST
/ai-valuations/draft` `{scan_usdz_key:<glb>, scan_files:{glb,usdz}}`. Happy-path faqat
**glb + usdz** yuboradi (`ai_scan_process_screen.dart:119-122` filtri). Depth va statistika
yuborilmaydi (statistika mahalliy-only). **Talab: glb + usdz ikkovi ham chiqadi.**

## Global konstruksiyalar (HAR bir promptda amal qilinadi)
1. **dlopen chegarasi:** Runner PCScanKit'ni import qilmaydi (Runner iOS-15, kit iOS-17). Chegarani
   `perform(NSSelectorFromString)` bilan EMAS — Runner'da e'lon qilingan **umumiy `@objc protocol`**
   orqali kesib o'tamiz (`entry as? PCScanFacade`). Faqat protokol escaping block, `Bool`, massiv
   qaytara oladi.
2. **Re-sync xavfsizligi:** kit o'zgarishlari FAQAT yangi fayllarda — `PCScanEntry+Kadastr.swift`,
   `PCScanGLBExport.swift` — + `AppState.swift` ga ~5 qatorlik hook. (Kit PCScan `6.1.x-vc` ni
   kuzatadi; re-sync ustiga yozmasin.)
3. **Provider-flag + fallback:** `AppDelegate.scanProvider` (`.roomScan` default | `.pcScan`).
   PCScan mavjud bo'lmasa (iOS<17 / LiDAR yo'q / kit yuklanmadi) → avtomatik `RoomScan`'ga tushadi.
4. **ID:** PCScan id = `1_000_000 + ScanRecord.index`. `saved_scans` chaqiruvlari id-prefiks bo'yicha
   yo'naltiriladi (≥1_000_000 → PCScanBridge). Ikkala store ham `Documents/Scans` da, lekin RoomScan
   faqat `scanNNN` papkalarni o'qiydi → to'qnashuv yo'q.
5. **Chiqish:** `atlas.glb` (ko'p-material + `COLOR_0`, UV flip) VA `atlas.usdz` (TexturedOBJLoader →
   SCNScene.write, tekstura saqlanadi). MDLAsset(OBJ) ishlatilmasin — teksturani yo'qotadi.
6. **Flutter/backend:** happy-path uchun o'zgartirilmaydi.

## Kontrakt (almashtiruvchi bajarishi shart)
- `room_plan_scanner`/`isSupported` → `Bool`.
- `room_plan_scanner`/`startTexturedScan` → `{savedScanId:int, mode:"saved_raw", walls, doors:0,
  windows:0, objects, floorAreaSqm:double|null, fileSize:0}` yoki cancel'da `nil`.
- `saved_scans`/`process(id)` → `{scanId, version:1, filePath:<GLB path>, fileSize, mode:"offline_processed"}`.
- `saved_scans`/`listScanFiles(id)` → `[{path, rel, type, sizeBytes}]`, kamida `glb`(+`usdz`).
- `room_plan_scanner`/`previewModel(path)` → 3D viewer.
- Ikkilamchi (standalone scans ekrani): `list/get/outputPath/delete/deleteOutput/rename/viewLidarMesh`.

## PCScan chiqishi (manba)
`Documents/Scans/<yyyyMMdd-HHmmss>/`: `textures/room.obj` + `room.mtl` + `room*.png` (ko'p atlas
sahifa + `unseen_vc`/`fillmat` vertex-rangli guruhlar), `textures/mesh.ply`, `images/frame_%04d.jpg`,
`frames.json`, `model.usdz` (faqat OC-fallback). `ScanRecord.index:Int` (metadata.json'da saqlanadi),
`ScanRecord.floorArea:Float`. `ReconstructionViewModel().run(paths:room:) async -> URL?` — headless
ishlaydi. `TexturedOBJLoader` room.obj+mtl+atlas ni SceneKit'ga to'g'ri bog'laydi (v'=1-v qiladi,
ko'p-material + vertex-rang'ni biladi).

---

# Bosqichma-bosqich prompt list (P0–P8)

Har bir promptни alohida sessiyaga bering; oldingisi bajarilгач keyingisiga o'ting. Har biri
"Global konstruksiyalar" ga bo'ysunadi.

## P0 — Scaffolding + provider switch + @objc boundary (dark ship)
> Kadastr mobile (`ios/`). AI Baholash skanerini keyinchalik PCScanKit bilan almashtirish uchun
> zamin tayyorla, lekin hali xatti-harakatni O'ZGARTIRMA (flag o'chiq, hamma narsa RoomScan'da
> qoladi). Qil: (1) `ios/Runner/` da umumiy `@objc protocol PCScanFacade` e'lon qil — metodlar:
> `presentCapture(from:onFinished:)`, `processScan(_:completion:)`, `listScanFiles(_:) -> [[String:Any]]`,
> `presentViewer(from:path:)`, `availableScanIds() -> [NSNumber]`, `deleteScan(_:) -> Bool`,
> `outputPath(_:) -> String?` (hammasi ObjC-bridgeable). (2) `AppDelegate` ga `enum ScanProvider
> {.roomScan,.pcScan}` va `scanProvider` (default `.roomScan`, `UserDefaults`/build-flag'dan) qo'sh.
> (3) `ios/Runner/PCScanBridge.swift` — `RoomScanBridge` egizagi, bo'sh stub'lar bilan (`handleRoomPlan`,
> `handleSavedScans`), facade'ni `loadPCScanEntry()` uslubida dlopen qilib `as? PCScanFacade` cast qiladi.
> (4) `ios/PCScanKit/PCScanEntry+Kadastr.swift` — mavjud `@objc(PCScanEntry)` ni `PCScanFacade` ga
> muvofiqlashtiradigan BO'SH stub'lar (hozircha `fatalError`/nil). (5) AppDelegate routing: kanallarни
> `scanProvider` bo'yicha tanla, LEKIN default `.roomScan` — ya'ni hech narsa o'zgarmaydi.
> **Chegara:** kit o'zgarishi faqat yangi faylda. **Qabul:** `flutter build ios --no-codesign` yashil;
> PCScanKit sim+device build yashil; flag `.roomScan` da app avvalgidek ishlaydi.

## P1 — presentCapture + AppState hook + guard'langan completion
> `PCScanEntry+Kadastr.swift` da `presentCapture(from:onFinished:)` ni yoz: PCScan'ni **capture-only**
> rejimida present qil (onboarding SAQLANADI — permission/LiDAR gate uchun; faqat capture tugashiни
> ushlaymiz). `ios/PCScanKit/App/AppState.swift:scanningFinished` ga ~5 qatorlik hook qo'sh: agar
> `captureOnlyCompletion` o'rnatilgan bo'lsa, `library.save` dan keyin `.viewer` ga O'TMASDAN o'sha
> closure'ni chaqir va modalни yop. Natija map RoomScan'nikiga aynan mos:
> `{savedScanId: 1_000_000 + record.index, mode:"saved_raw", walls: record.wallCount, doors:0,
> windows:0, objects: record.objectCount, floorAreaSqm: Double(record.floorArea), fileSize:0}`.
> **MUHIM:** bitta `returned` guard bilan BARCHA chiqish yo'llarini qamra — capture tugadi,
> `ScanningView` ichki "orqaga" tugmasi (`ScanningView.swift:37-45`), onboarding chiqishi, container
> xmark (`PCScanKit.swift:76-78`) — bekor bo'lsa aynan bir marta `onFinished(nil)`. `PCScanBridge`
> `startTexturedScan` + `isSupported` ni ulа (isSupported = iOS17 ∧ kit yuklanadi ∧ LiDAR; aks holda
> RoomScan'ga fallback). **Qabul:** flag `.pcScan` da AI Baholash "Skanlash" → PCScan ochiladi,
> tugatgach intro ekrani `savedScanId` bilan process ekraniga o'tadi; bekor qilinsa osilib qolmaydi.

## P2 — processScan (headless texturing → room.obj)
> `PCScanEntry+Kadastr.swift` da `processScan(_:completion:)`: id (≥1_000_000) → `ScanPaths` orqali
> papka → `room.json`→`CapturedRoom` yukla (`ScanLibrary.loadArtifacts` uslubida) →
> `await ReconstructionViewModel().run(paths:room:)` (headless; UI shart emas) → `textures/room.obj`
> (yoki OC-fallback'da `model.usdz`) hosil bo'ladi → `library.updateAfterReprocess` →
> `completion({scanId:id, version:1, filePath:<hozircha room.obj yoki model.usdz>, fileSize, mode:"offline_processed"}, nil)`
> yoki `NSError`. `PCScanBridge.handleSavedScans` da `process` ni id-prefiks bo'yicha ulа. Hozircha
> GLB/USDZ eksport YO'Q — keyingi qadamlar. **Qabul:** device'da `process(id)` room.obj yaratadi,
> Flutter process ekrani xatosiz o'tadi (filePath hali OBJ bo'lsa ham).

## P3 — OBJ→GLB writer (ko'p-material + COLOR_0 + UV flip)  ⚠️ eng katta ish
> `ios/PCScanKit/PCScanGLBExport.swift` — mustaqil, native-lib'siz OBJ→glTF2 (`.glb`) yozuvchi.
> texrecon OBJ **ko'p-materialli, ko'p atlas-sahifali**, plyus `unseen_vc`/`fillmat` guruhlari
> **vertex-rangli, teksturasiz** (qarang `TexturedOBJLoader.swift:47-64,99-160`). Shuning uchun:
> har `usemtl` guruhi → alohida glTF primitivi; teksturali guruh → `pbrMetallicRoughness` +
> `baseColorTexture` (mos atlas PNG, BIN chunk'ga embed); vertex-rangli guruh → `COLOR_0`, tekstura'siz.
> **UV flip: `v' = 1 - v`** (OBJ pastki-chap, glTF yuqori-chap — `TexturedOBJLoader.swift:67` tasdiqlaydi).
> Material'lar `doubleSided:false` (dollhouse cull; Flutter `_glbForceSingleSided` ham bor). Winding'ni
> device modelida tekshir; teskari bo'lsa flip. `atlas.glb` ni scan papkasiga yoz. `processScan` shu
> yozuvchini chaqirib `filePath` ni GLB ga o'zgartirsin. Past-xotira holatida (texrecon o'tmasa,
> vertex-rangli mesh) ham ishlasin. **Qabul:** unit-test'lar (v/vt/vn/f parse, N material, COLOR_0);
> device'da chiqqan `atlas.glb` `model_viewer_plus` da to'g'ri teksturali/rangli ko'rinadi.

## P4 — Textured USDZ eksport (TexturedOBJLoader → SCNScene.write)
> `PCScanEntry+Kadastr.swift` (yoki yangi `PCScanUSDZExport.swift`) da `room.obj`+mtl+atlas ni
> kit'ning mavjud `TexturedOBJLoader` orqali `SCNScene` ga yukla (u UV↔tekstura bog'lashni to'g'ri
> qiladi — `RoomSceneController.swift:100-108`), so'ng `scene.write(to: atlas.usdz)`. **MDLAsset(url:
> room.obj) ISHLATMA** — u teksturani oq qilib yuboradi (`TexturedOBJLoader.swift:6-8`). `processScan`
> GLB'dan keyin USDZ'ni ham yozsin. **Qabul:** `atlas.usdz` QuickLook/SceneKit'da teksturali;
> `atlas.glb` va `atlas.usdz` ikkovi ham scan papkasida.

## P5 — listScanFiles + wiring + previewModel
> `PCScanEntry+Kadastr.swift` `listScanFiles(_:)`: `[{path, rel, type, sizeBytes}]` qaytar —
> `atlas.glb`→`glb`, `atlas.usdz`→`usdz` (kamida shu 2 tasi; ixtiyoriy: mesh_ply/png/frame). Shakl
> `RoomScanBridge.listScanFiles` ga aynan mos (`saved_scan_service.dart` `ScanFile.fromMap` uni o'qiydi).
> `PCScanBridge` da `listScanFiles`/`outputPath` ni id-prefiks bo'yicha ulа. `previewModel(path)`:
> PCScan viewer `atlas.geo/png` ga ega EMAS — shuning uchun scan-root + `textures/room.obj` ni
> `TexturedOBJLoader` bilan SceneKit'da ko'rsat (path'ни provider/sniff bo'yicha yo'naltir, GLB'ni
> SceneKit'ga yuklashga urinma — u render qilolmaydi). **Qabul:** happy-path E2E: scan→process→
> `listScanFiles`(glb,usdz)→`uploadBundle`→`createDraft` → sim'da `scan_files={glb,usdz}`; "3D ko'rish"
> ishlaydi.

## P6 — Device E2E + hardening (cancel / low-memory / resume)
> Real iOS-17 LiDAR qurilmada to'liq oqimni tekshir: scan → process → upload → createDraft →
> resume (`GET /ai-valuations/{id}/scan` GLB yuklab ko'rsatadi). Chekka holatlar: (a) capture bekor
> qilishning har xil yo'llari osilmaydi/ikki marta chaqirmaydi; (b) past-xotira → `MemoryBudget` gate
> `FusionEngine`/vertex-rangli mesh'ga tushsa GLB yozuvchi uni ham eplaydi; agar hech nima bo'lmasa
> Flutter `_uploadUsdz` fallback'i (`scan_model`) ishlaydi; (c) app restart'dan keyin id barqaror
> (`ScanRecord.index` metadata.json'da). **Qabul:** uch stsenariy ham yashil, backend arizasida
> `scan_usdz_key`+`scan_files` to'g'ri.

## P7 — Ikkilamchi saved_scans metodlari (standalone "Skanlarim")
> `PCScanBridge` da `list/get/outputPath/delete/deleteOutput/rename/viewLidarMesh` ni facade orqali
> ulа (id-prefiks routing). `scanMap` shakli `RoomScanBridge.scanMap` ga mos; `areaSqm` ni endi
> haqiqiy `floorArea` bilan to'ldir. **Qabul:** standalone scans ekrani PCScan skanlar bilan degrade
> bo'lmaydi.

## P8 — Default'ni PCScan'ga o'tkazish (RoomScan <17 fallback bo'lib qoladi)
> `scanProvider` default'ini `.pcScan` ga o'zgartir (RoomScan avtomatik <17/LiDAR-yo'q fallback).
> Soak/test. Xohishga ko'ra dev-only `kadastr/pcscan_scanner` kanalini olib tashla. Instant rollback:
> flag'ni `.roomScan` ga qaytarish. **Qabul:** yangi qurilmalarda PCScan, eski qurilmalarda RoomScan;
> AI Baholash hech qachon skanersiz qolmaydi.

---

## Xavflar (rangi bo'yicha)
1. **OBJ→GLB writer** (P3) — eng katta, CI/sim'da to'liq sinab bo'lmaydi (texrecon device-only). Device
   test byudjeti kerak. Ko'p-material + COLOR_0 + winding + UV.
2. **dlopen chegarasi** (P0/P1) — `@objc protocol` cast SHART (`perform` block/Bool/massiv o'tkazolmaydi).
3. **Cancel guard** (P1) — barcha chiqish yo'llari bitta guard'dan.
4. **Re-sync friction** — kit edit'lari 2 yangi fayl + ~5 qator AppState; sync eslatmalari yoniga hujjatla.

## Effort (taxminiy)
P0 ~0.5k · P1 ~1-2k · P2 ~1k · **P3 ~3-5k (asosiy)** · P4 ~1k · P5 ~1k · P6 ~1-2k · P7 ~1-2k · P8 ~0.5k.
(k = kun; device test P3/P6 da og'ir.)
