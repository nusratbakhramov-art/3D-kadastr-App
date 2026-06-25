# Backend-driven architecture/design calculator orders — plan

**Date:** 2026-06-25
**Status:** scoped, not started. Source of the asks: `kadastr-mobile/TODO.md` (2026-06-25).
**Repos involved:** `kadastr-mobile` (Flutter), `kadastr-backend` (FastAPI), `kadastr-admin` (Refine/React).

---

## TL;DR — this is a half-finished migration, not greenfield

A backend-driven **dynamic-forms** system already exists (built 2026-06-16) and is *partially* wired.
The work is to **finish the cut-over**, not to build the mechanism.

| Layer | Static (old) path | Dynamic (backend-driven) path | State |
|-------|-------------------|-------------------------------|-------|
| Backend catalog | — | `form_definitions` table + `GET /forms/{key}` + admin CRUD, **seeded `arxitektura_tz` / `dizayn_tz`** | ✅ exists |
| Backend persistence | `architecture_orders` / `design_orders` (codes in enum cols + `details` JSON) | same tables — dynamic forms write the *same* JSON via `maps_to` | ✅ codes, re-translatable |
| Mobile **render** (view order) | flat-rows fallback | `SchemaAnswersView` re-translates codes→labels from schema | ✅ migrated, live |
| Mobile **submit** (create order) | `ArxitekturaTzWizardScreen` / `DizaynTzWizardScreen` (hardcoded) | `DynamicFormScreen` (consumes schema) | ❌ **built but zero call sites** |
| Admin render | `TzOrderView` shows raw codes | (would consult schema) | ❌ shows raw codes |

---

## Current-state map (verified, with file refs)

### Mobile (`kadastr-mobile`)
- **Static submit wizards (LIVE):** `lib/features/services/screens/calculator/arxitektura_tz_wizard_screen.dart` (~2628 lines, 9 steps), `dizayn_tz_wizard_screen.dart`. Entry points: `arxitektura_form_screen.dart:68`, `dizayn_form_screen.dart:72`, `kadastr_submit_flow_screen.dart:71,84`, `ai_scan_screen.dart:218`.
- **Answer storage = stable codes (good).** Drafts serialize option `value` codes, enums via `.apiValue`: `models/architecture_order_draft.dart:201-249`, `models/design_order_draft.dart:182-213`. Submit: `POST /services/architecture/orders` (`api_architecture_order_service.dart:92`), `POST /services/design/orders` (`api_design_order_service.dart:86`).
  - **String leaks (frozen language):** `land_use_purpose` stores the localized chip label (`arxitektura_tz_wizard_screen.dart:874`, `architecture_order_draft.dart:212`); standard room `name` frozen to Uzbek `labelUz` (`architecture_order_draft.dart:234`).
- **Option sources:** only style/facade/material/floor/color read from a backend catalog via `calculatorPricingNotifier` (`GET /calculator/pricing`, `calculator_pricing_store.dart:54`) **with a hardcoded Dart mirror** (`calculator_pricing.dart:248-314`). Constructive (Step 6), engineering (Step 7), territory (Step 8) options are **inline Dart `const` literals** (`arxitektura_tz_wizard_screen.dart:1261-1451`). Object/construction types are Dart **enums** (`architecture_order_draft.dart:15-36`).
- **Dynamic-form system:** `models/dynamic_form_schema.dart` (`FormSchema`/`FormFieldDef`, each field has `key`, `label{lang}`, `type`, `options[{value,label{lang}}]`, **`mapsTo`** dotted path), `models/dynamic_form_payload.dart` (`buildPayload` walks `mapsTo` → same JSON the wizard posts; `setByPath`), `api_forms_service.dart:32` (`GET /forms/{key}`, cached), `screens/calculator/dynamic_form_screen.dart` (**no call sites — dead**), `widgets/schema_answers_view.dart` (**live** render: `getByPath(payload, mapsTo)` then code→label via `_optionLabel`).
- **Render already migrated:** `application_detail_screen.dart:648` uses `SchemaAnswersView`; form keys wired at `applications_screen.dart:313,342`.

### Backend (`kadastr-backend`)
- **Order endpoints (no service layer — handlers build ORM inline):** `app/api/v1/architecture_order.py:17` (create `:28`), `app/api/v1/design_order.py:17` (create `:28`), legacy `app/api/v1/calculator_order.py:22`.
- **Models:** `app/models/architecture_order.py:56` (`architecture_orders`), `app/models/design_order.py:57` (`design_orders`). Promoted enum/filter columns + a `details` **JSONB** blob keyed by codes (`architecture_order.py:105`). Enums: `ArchitectureObjectType` (`:28`), `ConstructionType` (`:42`).
  - **Write path does NOT validate `details` option codes** — only the 3 enum columns are checked; `details.*` lands as free JSON (`schemas/architecture_order.py:24-27`). Catalog constrains UI, not writes.
- **Dynamic forms catalog (EXISTS, 2026-06-16):** `app/models/form_schema.py:49` (`form_definitions`, JSONB `schema`, `version`), public `app/api/v1/forms.py:16` (`GET /forms`, `GET /forms/{key}`), admin CRUD `app/api/v1/admin.py:1638-1704` (PUT bumps `version`) + sqladmin `app/admin.py:373`. Seeded by `scripts/seed_forms.py` (keys `arxitektura_tz` `:624`, `dizayn_tz` `:632`; fields carry `maps_to` e.g. `:158,222`).
- **Pricing is a SEPARATE store:** `app/models/calculator_price.py:24` (`calculator_prices`, keys like `arxitektura.yakka_small`), `GET /calculator/pricing` (`app/api/v1/calculator.py:22`). Option `value` ↔ price `key` linked **by convention only**; tier boundaries hardcoded (`calculator_price.py:7-9`).
- **Admin read API:** list `GET /admin/calculator-orders` UNION-merges calc+design+arch, ids namespaced `design-<N>`/`arch-<N>` (`admin.py:1339,1441`), **summary fields only** (`_row` `:1446`). Detail `GET /admin/calculator-orders/{id}` dispatches to `_arch_detail`/`_design_detail` and **returns all fields incl. raw `details`** (`admin.py:1535,1488,1572`). **No server-side code→label translation.** PATCH only sets `status`/`admin_note` (`:1612`); `quoted_price_uzs` is read-but-not-writable.
- **Legacy `calculator_orders`:** `category_title` + `details.lines[{label,value}]` are **frozen translated strings** (`app/models/calculator_order.py:49-56`) — not re-translatable.

### Admin (`kadastr-admin`)
- **No dedicated arch/design page.** Both ride the shared `calculator-orders` resource; detected by `record.source === "design" | "arch"` (`src/pages/calculator-orders/show.tsx:287`) → `TzOrderView` (`:171-266`).
- **List** (`list.tsx:64-105`): `id, account_name, account_phone, category_title, total_uzs, status, created_at` — **no type/object/address column**; arch/design/calc indistinguishable.
- **TzOrderView**: client card (`customer_name,phone,email,tin`), an **object card driven by a hardcoded `OBJECT_FIELDS[source]` allow-list (~13 fields/type)** (`show.tsx:31-64,230-238`), then `record.details` via a **generic walker** `renderDetails` (`show.tsx:122-169`) that handles maps + variable arrays-of-objects (auto-columned tables) + scalars.
- **i18n:** field keys via `tz.labels.*`/`tz.sections.*` with `humanize()` fallback (`show.tsx:80-83`; `i18n/locales/ru.json:258-346`). **Option VALUES are not translated** — `fmtValue` prints enum codes verbatim (`show.tsx:85-91`). → arch/design details show as e.g. `style: high_tech`.

---

## Per-TODO status

1. **"admin shows every field / data stored but not visible"** — premise partly false: orders *are* returned and `details` *is* walked. Real gaps: (a) option **values render as raw codes**, (b) object card is a fixed ~13-field allow-list, (c) list can't distinguish order types. → **Slice A.**
2. **"options from backend, not static mobile"** — the actual ask, **narrowed 2026-06-25 to options-only**: keep the wizard flow & fields, just de-hardcode its **option lists** so they're backend-served + admin-editable. Backend options catalog already exists (`form_definitions`, admin-editable); style/facade/material already read from a catalog, the rest are inline Dart literals. → **Slice B (options-only; NOT a full `DynamicFormScreen` migration).**
3. **"stop freezing submit-time language"** — already mostly done for arch/design (codes + render-time translation). Remaining: 2 string-leak fields; admin doesn't translate; legacy `calculator_orders` is genuinely frozen. → **Slice C** (+ legacy decision).
4. **"admin pages + surface per-service submit failures"** — arch/design have views (no dedicated page/filters). The **swallowed-failures** half is **uninvestigated** (look at `kadastr_submit_flow_screen` multi-service submit). → **Slice A** (pages) + **Slice C** (error audit).

---

## Sliced plan

### Slice A — Admin readability, done in the BACKEND (TODO #1; lowest risk)
**✅ Implemented 2026-06-25** — `kadastr-backend`: new `app/services/form_label_resolver.py` + `app/api/v1/admin.py` (import; `_row` now returns `source`; `GET /admin/calculator-orders/{id}?lang=` translates arch/design choice codes→labels via the active form schema). Deep-copies before mutating so it never writes labels back over stored codes. Logic verified against the real seeded schema (23 choice fields × uz/ru/en; free-text + unknown codes preserved). **Activation:** needs the `form_definitions` rows seeded — `docker exec kadastr-api python -m scripts.seed_forms`; until then it no-ops (shows codes, no regression). React admin unchanged. Default `lang=ru` (flip to uz if admins are uz-primary; React can pass its locale via a 1-line dataProvider tweak later). Not committed.

**Decided 2026-06-25:** translate option codes→labels **server-side in `kadastr-backend`**, NOT in the `kadastr-admin` React app. The admin detail endpoints resolve stored codes against the active `form_definitions` schema and return human-readable labels, so the existing React `TzOrderView`/`renderDetails` shows readable values with **no frontend change**.
1. Port the mobile `schema_answers_view.dart` resolver to Python: given an order payload (enum columns + `details` JSON) + the form schema for `arxitektura_tz`/`dizayn_tz`, walk each field, read its value by `maps_to` path, and map choice `value`→label `{uz,ru,en}`.
2. Wire it into `_arch_detail`/`_design_detail` (`app/api/v1/admin.py:1535,1488`): translate choice values **in place** in the response (top-level enum cols like `object_type` + nested `details.*`), for a requested `lang` (query param, default ru). Leave bools/numbers/free-text untouched (React already formats bools).
3. Expose the order **type/source** explicitly in the list `_row` (`admin.py:1446`) so a type column/filter is a trivial later add (the id prefix `arch-`/`design-` already encodes it).
- **Out of scope here (deferred per "kadastr-backend, not kadastr-admin"):** the React type column itself + `OBJECT_FIELDS` widening — thin frontend follow-ups.
- **Verify:** `GET /admin/calculator-orders/{arch-id}?lang=ru` returns labels, not codes.

### Slice B — Make wizard OPTIONS backend-driven (TODO #2; the actual ask)
**Scope clarified 2026-06-25:** keep the static wizard's flow and fields unchanged — only the **option lists** become backend-served + admin-editable. Do **NOT** adopt `DynamicFormScreen` / a full schema-driven form. Full migration + feature-parity work is explicitly out of scope.
1. Inventory the hardcoded option groups still inline in the wizards: object/construction types (Dart enums, `architecture_order_draft.dart:15-36`), constructive scheme/foundation/walls/ceiling/roof_type (Step 6, `arxitektura_tz_wizard_screen.dart:1261-1334`), engineering water/sewage/heating/ventilation/AC + feature toggles (Step 7, `:1335-1411`), territory (Step 8), `land_use_purpose` chips (`:838-874`). (Style/facade/material/floor/color already read from a backend catalog via `_catalog()`.)
2. Pick the backend options source — **recommended: `form_definitions`** (`GET /forms/{key}`), already seeded for `arxitektura_tz`/`dizayn_tz` and already admin-editable via `/admin/forms` + the React `forms` page (`scripts/seed_forms.py`, `app/api/v1/forms.py`). Verify the seed covers every group above; fill any missing option groups. *(Alt: extend the `calculator_prices` catalog used by `_catalog()` today — but it has no React admin editor and is a price table, not an options catalog.)*
3. Mobile: add a small helper so the static wizard reads each picker's options (`value` + `{uz,ru,en}` labels) from the backend by field key, replacing the inline `const [...]` lists + `switch` label maps. **No flow/field/UX changes.**
4. Bonus (free): once `land_use_purpose` reads dynamic options, it stores the option **code** instead of the localized label → its language-freeze (a TODO #3 leak) is fixed as a side effect.

**Out of scope:** rebuilding fields/flow, `DynamicFormScreen`, the room-`name` freeze fix, retiring the wizard, legacy `calculator_orders`.

**◑ In progress 2026-06-25 — `kadastr-mobile` (arxitektura wizard, plain-string pickers):** the 10 hardcoded plain-string option groups now read from the `arxitektura_tz` schema — constructive (scheme/foundation/walls/ceiling/roof_type) + engineering (water_source/sewage/heating/ventilation/air_conditioning). Done via a new fallback-safe `_schemaChipPicker(mapsTo, fallbackOptions, fallbackLabelOf, …)` in `arxitektura_tz_wizard_screen.dart`: it pulls `{value,label}` from the schema by `maps_to`, and if the schema isn't loaded/seeded falls back to the *exact* current hardcoded list + label switch (UX byte-identical offline). Schema loaded once in `initState` via `FormsApiService().getForm('arxitektura_tz')`. `dart analyze` clean. **Backend needs no changes** — the seed already covers every group with matching codes (verified). Activation = same `seed_forms` step as Slice A. Not committed.
**Remaining for Slice B:** enum-backed `object_type`/`construction_type` + `land_use_purpose` (higher-risk: enum↔code + the freeze-fix); and the whole **dizayn** wizard (partition_material, air_conditioning = plain-string; object_type, design_type = enum). Needs `flutter analyze` (full) + on-device test before commit.

### Slice C — Quick fixes + error audit (TODO #3/#4 tail; small, scattered)
1. Code-ify `land_use_purpose` (codes already exist in the chip tuples — stop storing the label): `arxitektura_tz_wizard_screen.dart:838-874`, `architecture_order_draft.dart:212`. Add label maps in mobile render + admin.
2. Code-ify standard room `name` (`architecture_order_draft.dart:234`).
3. Audit the multi-service submit flow for swallowed per-service failures (`kadastr_submit_flow_screen.dart`) — surface partial failures to the user instead of silently succeeding.

### Slice D — Backend enforcement (TODO #2 crux; architectural, deferrable)
1. Validate posted `details.*` option codes against the active `FormDefinition.schema` on write.
2. Formally link option `value` ↔ price-book `key` (today synced by convention); consider unifying `form_definitions` option metadata with `calculator_prices`.
3. Add a quote-write path (`quoted_price_uzs` is currently read-only via PATCH).

---

## Decisions (resolved 2026-06-25)
- **Scope of #2 = options-only.** Keep the wizard flow & fields; only make option lists backend-served + admin-editable. Full `DynamicFormScreen` migration is **out of scope**.
- **Legacy `calculator_orders`: leave as-is** (out of scope — a separate language-storage change, not an options change).
- **Admin readability done server-side in `kadastr-backend`, not `kadastr-admin`** (confirmed 2026-06-25): the admin detail endpoints translate codes→labels from the `form_definitions` schema; the React admin renders the result unchanged. Type/source exposed in the list response so a column/filter is a trivial later frontend add (deferred).
- **Admin pages (#4): keep the shared `calculator-orders` resource** — no dedicated pages.
- **Options source: `form_definitions`** (reuses existing `/admin/forms` CRUD).

## Recommended order
A (admin: codes→labels + type column; low risk) → B (options-only: de-hardcode the wizard's option lists from the backend catalog). C/D and legacy-calc deferred unless asked.

## Key file index
- Mobile static wizards: `lib/features/services/screens/calculator/arxitektura_tz_wizard_screen.dart`, `dizayn_tz_wizard_screen.dart`
- Mobile drafts→payload: `models/architecture_order_draft.dart:201-249`, `models/design_order_draft.dart:182-213`
- Mobile dynamic forms: `models/dynamic_form_schema.dart`, `models/dynamic_form_payload.dart`, `api_forms_service.dart`, `screens/calculator/dynamic_form_screen.dart`, `widgets/schema_answers_view.dart`
- Backend orders: `app/api/v1/architecture_order.py`, `app/api/v1/design_order.py`, `app/models/architecture_order.py`, `app/models/design_order.py`
- Backend forms catalog: `app/models/form_schema.py`, `app/api/v1/forms.py`, `app/admin.py:373`, `scripts/seed_forms.py`
- Backend admin API: `app/api/v1/admin.py:1339` (list), `:1488/:1535` (detail), `:1612` (patch)
- Admin UI: `src/pages/calculator-orders/show.tsx`, `src/pages/calculator-orders/list.tsx`, `src/i18n/locales/ru.json`
