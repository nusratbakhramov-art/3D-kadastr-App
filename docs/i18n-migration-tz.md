# TZ — Mobile i18n migration (hardcoded strings → backend-driven `tr()`)

**Repo:** `kadastr/mobile` (Flutter). Related: `kadastr/backend` (FastAPI), `kadastr/admin` (React/Refine).
**Owner task:** #14 — "Translate ~146 audited hardcoded strings via `tr()`".
**Audience:** the engineer/AI picking this up. Assumes repo access. Read this top-to-bottom before touching code.

---

## 1. Objective

Two things, together:

1. **Plumbing** — wrap every remaining hardcoded user-facing string in `tr(locale, key, uz:, ru:, en:)` so it becomes admin-overridable from the backend at runtime (no app release needed).
2. **Translation** — most of the audited strings are **Uzbek-only** today (the user sees Uzbek even in Russian/English mode). So each migration must supply **real `ru` and `en` translations**, not just move the Uzbek text into a `uz:` slot.

This is 80% translation quality, 20% plumbing. Do not treat it as a mechanical wrap.

---

## 2. Current state — READ THIS FIRST

The `tr()` foundation is **already built** but lives on **three unmerged feature branches**. None are on prod (`master`/`main`). Nothing below needs to be re-invented.

| Repo | Branch / commit | What it adds |
|------|-----------------|--------------|
| mobile | `feat/i18n` (`dc05e66`) | `lib/core/i18n/app_translations.dart` (`tr()` + model), `lib/core/i18n/app_translations_store.dart` (cache-first version-checked store), `main.dart` wiring (root rebuild on bundle update), **home banner + cards migrated as the proof slice**, and **`I18N_AUDIT.md`** (the full string audit — the worklist). Branch is 1 ahead / 13 behind `master`. |
| backend | commit `bca87b8` | `app/api/v1/i18n.py` (`GET /i18n/version`, `GET /i18n/bundle`, admin CRUD `/admin/i18n`), `app/models/app_translation.py`, migration `alembic/versions/i18n_01_app_translations.py`. |
| admin | commit `a3c7eaa` | "Tarjimalar" page — table editor for the keys (module `i18n`). |

**Prod today has NONE of this.** `master` mobile still uses three legacy patterns side-by-side:
- `lib/core/i18n.dart` → `L` class (`L.cancel(l)` etc.) — small shared set.
- Per-file `_pick(...)` / `_s(...)` / `switch (l.languageCode)` helpers — the bulk of correctly-trilingual strings.
- Raw hardcoded literals — **the target of this TZ.**

Going forward, **`tr()` is the one convention.** You are not required to migrate the already-trilingual `_pick`/`L`/`switch` strings (they work in 3 languages, just aren't admin-overridable) — that is an optional stretch, see §8. The mandatory scope is the hardcoded single-language strings in `I18N_AUDIT.md`.

---

## 3. Prerequisite: land the foundation

The mobile app is **offline-safe** (every `tr()` call keeps inline defaults, so it works with no backend), which means order is flexible, but ship the backend first so overrides actually resolve:

1. **Backend** — merge `bca87b8` to `master`, run migration `i18n_01`, deploy.
   - ⚠️ **Alembic has had multiple heads historically.** Before `alembic upgrade`, run `alembic heads`; if there are multiple, apply `i18n_01` by name / merge heads — don't blind-`upgrade head`.
   - ⚠️ **Do NOT commit/deploy the demo-phone files** `app/api/v1/auth.py` and `app/services/otp_service.py` if they carry local test changes. Verify the diff before pushing.
   - Smoke test: `GET /api/v1/i18n/version` → `{"version": <int>}`, `GET /api/v1/i18n/bundle` → `{"version":…,"locales":{"uz":{},"ru":{},"en":{}}}`.
2. **Admin** — merge `a3c7eaa` to `main`, confirm the "Tarjimalar" page loads and the `i18n` module is granted to the admin role.
3. **Mobile** — rebase `feat/i18n` onto `master` (it's 13 behind; resolve against the recently-landed Arizalar/detail changes), confirm `flutter analyze` is clean, then do the §5 migration work **on that branch**.

---

## 4. The contract (how `tr()` resolves)

```dart
// lib/core/i18n/app_translations.dart
String tr(
  Locale l,
  String key, {          // stable dotted key, e.g. 'scan.provider.title'
  required String uz,     // inline defaults — ALWAYS provided, offline-safe
  required String ru,
  required String en,
});
```

Resolution order: **backend override for `key`+language → else inline default for that language.** The store (`AppTranslationsStore.loadCachedThenRefresh()`) reads the cached bundle instantly at startup, then background-checks `GET /i18n/version` and only downloads `GET /i18n/bundle` when the server version grew. `main.dart` wraps the app in a `ValueListenableBuilder<AppTranslations>` so a new bundle rebuilds the tree.

**Backend bundle shape** (what the app consumes):
```json
{ "version": 1719000000,
  "locales": {
    "uz": { "scan.provider.title": "3D pipeline tanlang" },
    "ru": { "scan.provider.title": "Выберите 3D-конвейер" },
    "en": { "scan.provider.title": "Choose 3D pipeline" } } }
```
Version = `max(updated_at)` epoch across the `app_translations` table; empty/NULL language value → app falls back to the inline default for that language.

---

## 5. The work — file-by-file

**Source of truth for the worklist:** `I18N_AUDIT.md` on `feat/i18n` (~146–154 strings across ~26 files). Line numbers there are approximate — grep the literal, don't trust the number. Work the list in this priority order:

### 🔴 P0 — SCAN / 3D feature (~114 strings, all LIVE)
The worst offender; whole screens are Uzbek-only.
- `ai_scan_screen.dart` — provider & quality bottom sheets + toasts (~30)
- `scan_metadata_screen.dart` — summary row labels (~23)
- `saved_scan_detail_screen.dart` (~24), `saved_scans_screen.dart` (~14), `my_scans_screen.dart` (~12)
- `splat_viewer_screen.dart` (4), `scan_lidar_screen.dart` (1), `scan_draft.dart` `ScanObjectType` labels (4)
- `scan_camera_card.dart` + `scan_tips_card.dart` (6, **LATENT** — default params overridden by callers; low priority)

### 🟠 P1 — SMETA editor (~17, LIVE)
- `smeta_editor_screen.dart` — entire screen hardcoded (~15)
- `code_search_sheet.dart` (2)

### 🟡 P2 — Market 3D / Calculator / Misc (~19, LIVE)
- Market: `listing_detail_screen.dart`, `listing_3d_viewer_screen.dart`, `listing_3d_viewer.dart`, `listing_formats_card.dart`, `listing_payment_card.dart` (7)
- Wizard: `arxitektura_tz_wizard_screen.dart`, `dizayn_tz_wizard_screen.dart`, `dynamic_form_screen.dart` (5)
- Misc: `home_screen.dart` tooltips, `settings_screen.dart` change-phone sheet, `no_internet_sheet.dart`, `application_detail_screen.dart` (PDF placeholder card + "3D skan #" titles), `service_placeholder_screen.dart`, `chat/api_chat_service.dart` network fallbacks

### LATENT (lowest priority)
`ai_valuation_draft.dart` / `ai_usage_type` labels, the two `scan_*_card.dart` default params — these aren't rendered today. Wrap them for correctness but they can trail.

---

## 6. Migration pattern (worked example)

**Before** (`ai_scan_screen.dart`, Uzbek-only, user sees Uzbek in RU/EN):
```dart
Text('3D pipeline tanlang', style: …),
…
Text("Bekor qilish"),
```

**After:**
```dart
final l = Localizations.localeOf(context);
…
Text(tr(l, 'scan.provider.title',
        uz: '3D pipeline tanlang',
        ru: 'Выберите 3D-конвейер',
        en: 'Choose 3D pipeline'), style: …),
…
Text(tr(l, 'common.cancel', uz: 'Bekor qilish', ru: 'Отмена', en: 'Cancel')),
```

Rules:
- **Keep the Uzbek text as the `uz:` inline default** — never delete it; it's the offline fallback.
- **Add genuine `ru` + `en`** (see §7). This is the actual deliverable.
- Get the `Locale` from `Localizations.localeOf(context)`. In non-widget contexts (services, toasts fired outside build), thread the locale in or read `localeNotifier.value`.
- Reuse **one key** for repeated strings ("Bekor qilish", "O'chirish", "Xatolik", date words "Bugun,"/"Kecha,"). Put shared ones under a `common.*` namespace so the admin edits them once.

### Key naming convention
`namespace.section.item`, lowercase dotted, stable. Namespaces: `common.*`, `scan.*`, `smeta.*`, `market.*`, `wizard.*`, `home.*`, `settings.*`, `applications.*`. Keys are **permanent contracts** — once an admin overrides a key, renaming it silently drops the override. Name carefully the first time.

---

## 7. Translation quality (the important part)

- **Real translations, not machine sludge.** Russian is the primary second language for this audience; get it fluent and idiomatic.
- **Preserve the domain glossary** — do not "translate" proper product/legal terms:
  - `Kadastr`, `STIR` (tax ID; RU often `ИНН`), `smeta`/`смета` (cost estimate), `LiDAR`, `3DGS`/gaussian splat, `Object Capture`, `Polycam`, `Kiri Engine`, `СНиР`/`SNiR` catalog codes.
  - Object types: `Turar joy` = жилое / residential, `Noturar joy` = нежилое / non-residential, `Ombor` = склад / warehouse, `Sanoat obyektlari` = промышленные объекты / industrial.
  - `Eskiz loyiha` = эскизный проект / concept design, `Ishchi loyiha` = рабочий проект / working design, `Rekonstruksiya` vs `Yangi qurilish` = реконструкция / новое строительство.
- **Interpolations must survive.** `"Skan xatosi: $e"`, `"Skan saqlandi (#$id)"`, `"$n foto"`, `"Natijalar ($count)"` — keep the placeholder in all three languages and keep it building via string interpolation *outside* `tr()` where the dynamic part varies, e.g.:
  ```dart
  '${tr(l, 'scan.error.prefix', uz: 'Skan xatosi', ru: 'Ошибка скана', en: 'Scan error')}: $e'
  ```
  Do **not** bake user data into a translation key.
- **Match tone** to the surrounding already-translated screens (`payment_receipt_sheet.dart`, `settings_screen.dart` are good references for register).

---

## 8. Out of scope / optional

- **Migrating already-trilingual `_pick`/`L`/`switch` strings to `tr()`** — they work in 3 languages already; converting them only adds admin-overridability. Optional stretch, not required for #14. If you do it, batch it as a separate commit series and don't mix with the hardcoded work.
- **Seeding keys into the backend `app_translations` table** — not required (inline defaults render fine, and admins can add a row when they want to override). If the product wants every key pre-listed in the "Tarjimalar" admin page, that's a follow-up seeding task, call it out but don't block on it.
- Backend/admin foundation code — already written (§2); only merge/deploy, don't rewrite.

---

## 9. Definition of done

- [ ] Foundation branches merged/deployed in order backend → admin → mobile (§3).
- [ ] Every LIVE string in `I18N_AUDIT.md` wrapped in `tr()` with a stable key + genuine uz/ru/en.
- [ ] **No user-visible Uzbek leaks when the app runs in RU or EN** — spot-check P0 scan flow, smeta editor, market 3D, and the misc sheets in all three languages.
- [ ] Shared strings collapsed onto `common.*` keys (no duplicate keys for the same text).
- [ ] All interpolations/placeholders preserved and correct in every language.
- [ ] `flutter analyze` clean; app builds; `AppTranslationsStore` still loads (test with backend up: edit a key in admin, confirm it overrides live on next app open).
- [ ] LATENT items wrapped or explicitly deferred with a note.
- [ ] Work committed on the mobile i18n branch in reviewable, per-feature commits (e.g. one per P0 file group), **not** one giant commit.

---

## 10. Gotchas checklist

- **Alembic multiple heads** — apply `i18n_01` by name; don't blind-`upgrade head`.
- **Don't ship demo-phone files** (`auth.py`, `otp_service.py`) — verify backend diff before push.
- **Authed HTTP** — the translation store uses a plain `http.Client` (public endpoints, correct). Anything else that's authenticated must use `AuthHttpClient`, not raw `http.Client`, or token refresh never fires.
- **Keys are permanent** — renaming a key orphans any admin override. Decide the key once.
- **Locale in non-widget code** — services/toasts fired outside `build()` need the locale threaded in or read from `localeNotifier.value`.
- **`feat/i18n` is 13 behind master** — rebase and re-run analyze before starting; the Arizalar list + `application_detail_screen.dart` changed recently and both appear in the audit.
- **Ask before commit/push** — do not push to prod without explicit sign-off.
