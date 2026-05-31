# ABC-UZ integration: Kalkulyator estimate + AI Baholash cost approach

**Status:** built & tested locally, **not yet deployed**. Session handoff doc so
another chat can continue. Spans two repos (`backend/` + `mobile/`).

Date: 2026-05-30/31.

---

## TL;DR — what was built

Two things, both wiring the ABC-UZ (АВС-4) construction-cost engine into the app:

1. **Kalkulyator → "Ta'mirlash va qurilish"**: a real construction *estimate*
   (smeta). User picks a building profile → backend builds a bill of works →
   ABC prices it (over the reverse bridge) → itemized result. If ABC is
   unreachable, a deterministic per-m² approximation is returned instead.

2. **AI Baholash → cost approach (silent)**: the same estimate service is used
   to compute a *replacement cost* for the property, fed to GPT as a **second
   valuation anchor** (cost approach) alongside the comparables (market
   approach). It is **invisible to the user** by explicit product decision —
   no UI step, no result block. It only moves the final number + GPT reasoning.

### Why ABC belongs in BOTH
ABC answers *"what does it cost to build/repair?"* (forward, bottom-up). That is
the **cost approach** — one of the 3 classic valuation methods (market / income
/ cost). So:
- Kalkulyator = the estimate itself (the headline product).
- AI Baholash = uses it as a cross-check anchor; market value usually sits near
  or below replacement cost for old builds, can exceed it where land/location
  demand is high. GPT reconciles.

---

## ⚠️ The one big caveat — placeholder codes

ABC can only compute real numbers from real **СНиР/ЕРЕР position codes**. The
templates currently use **placeholder codes (`ПЛ-…`)**, so:
- ABC rejects them → every path currently falls back to the **deterministic
  per-m² approximation**.
- The deterministic numbers are tuned to match the app's existing tariffs
  (construction ≈ 2.4M/m², premium renovation ≈ 5M/m²) and are sane, but they
  are **placeholders**, not official figures.

**To switch on the real ABC engine:** a сметчик replaces the placeholder codes
+ per-m² norms in `smeta_template_service.py` (one set of tables), and
`ABC4_ESTIMATE_LABEL` is set to a connected bridge. No other code change — the
`engine` field flips from `"approx"` to `"abc4"` automatically.

---

## Backend changes (`backend/`)

### New files
- `app/schemas/construction_estimate.py`
  - `ConstructionProfile` (request): `work_kind` (construction|renovation),
    `building_type`, `wall_material`, `finish_level`, `floors`, `area_sqm`,
    optional `district`/`address`/`cadastre_number`.
  - `ConstructionEstimateResult` (response): `total_uzs`, `currency`, `engine`
    (`abc4`|`approx`), `lines[]` (itemized sections), `note`, `area_sqm`,
    `profile_summary`.
  - Enums: `BuildingType`, `WallMaterial`, `FinishLevel`, `WorkKind` — **must
    mirror the mobile enums** in `abc4_estimate_client.dart`.
- `app/services/smeta_template_service.py` — the heart. Table-driven:
  - `_CONSTRUCTION_SECTIONS` / `_RENOVATION_SECTIONS` — section catalogue with
    placeholder codes + `base_uzs_m2` per-m² norms.
  - `_MATERIAL_FACTOR`, `_FINISH_FACTOR`, `_TYPE_FACTOR` + height/shared-
    foundation factors.
  - `build_payload(profile) -> EstimatePayload` — profile → ABC bill of works.
  - `deterministic_estimate(profile) -> ConstructionEstimateResult` — itemized
    per-m² fallback.
- `app/services/construction_estimate_service.py`
  - `run_estimate(profile)` — routing: **bridge → direct adapter → deterministic
    fallback**. Any ABC failure (offline / placeholder codes / timeout /
    unparseable) silently degrades to the approximation. Always returns a result.
  - `_parse_job_result` parses the ABC driver response **defensively** — only a
    positive numeric total promotes to `engine="abc4"`. The exact driver result
    shape is unknown; widen `_TOTAL_KEYS` once the сметчик confirms it.

### Modified files
- `app/config.py` — added `ABC4_ESTIMATE_LABEL` (falls back to
  `ABC4_AIVAL_LABEL`) and `ABC4_ESTIMATE_WAIT` (default 90s).
- `app/api/v1/abc4.py` — `POST /abc4/estimate` (public, no auth). Always 200.
- `app/services/ai_valuation_pipeline.py`
  - Phase 1 now runs a **third** parallel task `_cost_approach(bundle)` next to
    listings + POIs.
  - `_cost_approach` infers a `ConstructionProfile` from cadastre facts
    (type from hint; **brick/standard/1-floor defaults**) and calls
    `run_estimate` → replacement cost.
  - `_infer_building_type(hint)` maps davreestr type hint → `BuildingType`.
  - Stores `result_payload["cost_approach"]` (cost, engine, summary, lines) and
    passes `cost_approach_value` to the LLM.
- `app/services/llm_valuation_service.py`
  - `estimate_value(... cost_approach_value=None)`. Prompt now reconciles
    **market (primary) + cost (secondary)**.
  - Grounding gate now also accepts a cost anchor → AI Baholash can price a
    property with **zero comparables** (previously returned None).
  - Sanity clamp baseline falls back to the cost anchor when there are no
    comparables.

### No DB migration
The estimate is stateless; the cost approach is stored inside the existing
`ai_valuation_job.result_payload` JSON. No Alembic change in this session.
(The `kadastr_lookup` migration `f8b9c0d1e2a3` is from the *previous* session.)

---

## Mobile changes (`mobile/`)

### New files
- `lib/features/services/data/abc4_estimate_client.dart` — enums (mirror
  backend), `ConstructionProfile`, `ConstructionEstimateResult`/`EstimateLine`,
  `Abc4EstimateService.estimate()` → `POST /abc4/estimate` (130s timeout, public).
- `lib/features/services/screens/calculator/abc4_estimate_screen.dart` — the
  form (work kind, building type, wall material, finish level, floors stepper,
  area) → calls the endpoint → reuses `OnlineCalculatorResultScreen` to show the
  itemized breakdown. **This breakdown IS shown** (a smeta calculator is
  expected to show one) — unlike the AI cost approach which is hidden.

### Modified files
- `lib/features/services/screens/online_calculator_screen.dart` — the
  "Ta'mirlash va qurilish" (`CalculatorCategory.tamirlash`) tile now opens
  `Abc4EstimateScreen` instead of the old tariff `TamirlashFormScreen`.
  - `tamirlash_form_screen.dart` + `computeTamirlash` are now **orphaned but
    left in place** (reversible).
- `pubspec.yaml` — version bump `1.0.0+5` (from the prior .ipa build; predates
  this work).

### AI Baholash mobile
**No change.** The cost approach is silent; the result screen is untouched.

---

## Config / deploy notes

- Env knobs (server `.env`, gitignored): `ABC4_ESTIMATE_LABEL`,
  `ABC4_ESTIMATE_WAIT`, plus existing `ABC4_AIVAL_LABEL`, `ABC4_BRIDGE_TOKENS`,
  `OPENAI_API_KEY`, `OPENAI_MODEL=gpt-4o-mini`.
- **Deploy steps when shipping:**
  1. Deploy backend (no migration needed).
  2. **Recreate the `ai-valuation-worker` container** (`docker compose up -d`,
     NOT `restart`) so it picks up the new pipeline code.
  3. Mobile: ship via normal build (changes are client-side, backward compatible).

### ⚠️ Worker ≠ web process (known limitation)
The reverse-bridge WS registry is **in-memory in the FastAPI web process**. The
`ai-valuation-worker` is a **separate process**, so its `run_estimate` never
sees a connected bridge → in the worker the cost approach is **always the
deterministic replacement cost** (still a valid cost-approach figure).
**Follow-up:** to use real ABC from the worker, have it call the web process's
HTTP bridge endpoint (`POST /abc4/bridge/{label}/jobs`) instead of the
in-process `registry`.

---

## What was tested

✅ Backend imports clean (`app.main`).
✅ `deterministic_estimate` across profiles — numbers match existing tariffs.
✅ `POST /abc4/estimate` via TestClient → 200, itemized `approx` fallback.
✅ `_cost_approach()` with a real bundle → 192M for 80 m² apartment; building-
   type inference correct.
✅ **Real GPT** (gpt-4o-mini, local key) reconciliation, both branches:
   - with comparables + cost anchor → leaned on comparables, ignored the low
     rebuild cost (correct);
   - zero comparables + cost anchor → priced via cost approach, said so.
✅ `flutter analyze` clean on new/changed files + whole project.
✅ Mobile run-time — confirmed by the user (they ran the app).

⚠️ NOT verified (environmental): full DB-backed `process_job` through the
   worker; the **live ABC bridge** path (needs a сметчик actually connected).

---

## Open product decisions (for the next session)

1. **Surface cost approach in AI result?** — Decision so far: **NO**, keep it
   silent (user: "user doesn't care how it's calculated"). `result_payload`
   still carries `cost_approach` for DB/admin inspection.
2. **Collect construction fields in the AI flow?** — Currently inferred
   (brick/standard/1-floor). Asking 2-3 questions would improve accuracy but
   adds friction. Not done.
3. **Kalkulyator breakdown visibility** — currently shows itemized lines +
   method label. User may want total-only; not changed yet.
4. **сметчик real codes** — the gating item for real ABC numbers everywhere.

---

## Branches (this session's work)
- backend: `feat/abc4-cost-approach` (off `feat/kadastr-lookup-cache`)
- mobile: `feat/abc4-cost-approach` (off `fix/home-ai-baholash-route`)

Both prior branches were already merged to master in the previous session.
