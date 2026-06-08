# AI Baholash — wizard & result (mobile)

AI Baholash is the in-app property valuation flow. The user enters a cadastre
number, confirms location, uploads photos/docs, and gets a 3-approach appraisal
back. **The price is computed server-side** by a deterministic engine (the
Yusupov / ГККИНП xls methodology); AI only fills bounded judgment parameters.
Backend internals are documented in the backend repo (`docs/ai-baholash.md`).

This doc covers the mobile side.

---

## Flow

```
Cadastre lookup  →  Purpose  →  Location (map)  →  Intake (this is the big one)  →  Status/Result
```

The whole flow is gated behind login (`ensureLoggedIn`). The bundle
(`AiBaholashBundle`) is built up across steps and serialised on submit
(`POST /api/v1/ai-valuations`), then the status screen polls
`GET /ai-valuations/{id}` every ~4 s until `completed` / `failed`.

---

## Intake step — required inputs

`lib/features/services/screens/ai_intake_screen.dart`

Required before **Hisoblash** is enabled (amber hint lists what's missing):
- **Obyekt rasmlari** (≥1 photo) — drives the AI condition score
- **Kadastr hujjatlari** (≥1 doc) — drives AI fact extraction (area/year/type)
- **Xonalar** (≥1 room) — dynamic chips + per-type count
- **Qavat** — Obyekt qavati + Jami qavatlar (both required; affect pricing)

Optional: **Pasport / ID**.

Uploads (`api_ai_upload_service.dart`) go to `POST /ai-valuations/upload` per
category; the returned keys are stored on the bundle. Each uploaded file shows a
**thumbnail preview** (image) or a **file-type chip** (PDF/XLSX/…) with a × to
remove. Accepts jpg/jpeg/png/webp/heic + pdf/doc/docx/xls/xlsx (validated by
extension on both sides — Flutter sends `application/octet-stream`).

---

## Result screen

`lib/features/services/screens/ai_status_screen.dart`

- **Price card** — estimated value, range, confidence bar
- **AI summary** — plain-Uzbek narrative (LLM; explanation only, not the number)
- **Baholash yondashuvlari** — the 3 approaches with value + weight
  (Qiyoslash / Daromad / Xarajat)
- **Solishtirilgan e'lonlar** — top 5 comparables (tappable → listing URL), then
  a "Yana N ta" footer. Each comparable carries its grid adjustment % in the
  payload.
- **Yaqin atrofdagi obyektlar** — POI categories with counts, **tap to expand**
  into the actual named places + distance ("12-son maktab · 0.4 km"). Caption:
  "1–2 km radiusda topilgan infratuzilma".

---

## What AI does (and doesn't)

The price is a deterministic formula (ГККИНП cost + income + market comparison,
weighted). **AI never emits a price** — it only supplies bounded parameters the
formula needs, all clamped server-side:
- photo condition → wear %
- kadastr/passport docs → facts read off the page
- per-comparable adjustments (floor/size/rooms/condition)
- a per-location rent rate

If any AI step fails, the server falls back to deterministic defaults. The floor
inputs feed a per-comparable market adjustment.

---

## Key files (mobile)

```
lib/features/services/models/ai_baholash_bundle.dart        # the wizard bundle + toJson
lib/features/services/screens/ai_cadastre_screen.dart       # cadastre lookup (masked input)
lib/features/services/screens/ai_purpose_screen.dart        # baholash maqsadi
lib/features/services/screens/ai_intake_screen.dart         # photos/docs/passport/rooms/floor + gating
lib/features/services/screens/ai_status_screen.dart         # submit + poll + result render
lib/features/services/api_ai_upload_service.dart            # multipart uploads
lib/features/services/api_ai_valuation_job_service.dart     # create / poll / list
lib/features/auth/widgets/login_required_sheet.dart         # ensureLoggedIn gate
```

---

## This session's changes (2026-06)

- Upload **thumbnail previews** with per-file remove.
- **Qavat** (floor / total floors) inputs; **required-field gating** on
  Hisoblash (photos + kadastr + rooms + floors); dropped "(ixtiyoriy)".
- Result: comparables capped at **5 + "Yana N ta"**; POI **"1–2 km radiusda"**
  caption; **expandable** POI list (named places + distance).
- Bundle sends `floor` / `total_floors`.

## Known open items

- **POIs sometimes don't render** — the section only shows when the backend
  returns POIs; the worker's Overpass call can come back empty (public-instance
  throttling). Backend-side fix tracked in the backend repo.
