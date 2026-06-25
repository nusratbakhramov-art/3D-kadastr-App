# TODO

## 2026-06-25

- Calculator orders: confirm admin shows every field the user submitted; current gap is that architecture/design wizard data is stored in backend but not visible in admin.
- Calculator options for architecture/design must come from backend-managed data, not static mobile screen definitions.
- Order content is currently frozen in the submit-time language because labels/values are stored as translated strings. Replace this with backend-driven keys/codes and translate at render time per viewer language.
- Add admin pages for architecture/design orders and verify the creation flow surfaces any per-service submission failures instead of swallowing them.

### Investigation status (2026-06-25)

Scoped across mobile/backend/admin → full plan in `docs/backend-driven-calculator-orders-plan.md`.
Key finding: a backend-driven dynamic-forms system already exists (built 2026-06-16) and is half-wired — this is a migration to finish, not a build from scratch.

- **#1 admin visibility** — ✅ Slice A done in `kadastr-backend`: admin detail now translates option codes→labels from the `form_definitions` schema (`?lang=`, default ru); `source` exposed for a future type column. Needs `python -m scripts.seed_forms` run to activate; React admin unchanged. (Object-card allow-list widening = deferred frontend.)
- **#2 backend options** — scope **narrowed to options-only** (2026-06-25): keep the wizard flow/fields, just de-hardcode its option lists from an admin-editable backend catalog (`form_definitions`, already seeded). NOT a full `DynamicFormScreen` migration. `land_use_purpose` language-freeze fixes itself as a side effect. → Slice B. ✅ Done 2026-06-25: arx + dizayn wizards — plain-string pickers (constructive/engineering + partition/AC) schema-driven via `_schemaChipPicker`; enum pickers (object/construction/design type) get labels from schema via `_schemaEnumLabel`; `land_use_purpose` now stores a code (freeze fixed) and backend seed made it a `single_choice`. All `dart analyze` clean; resolver test green (arx 15 choice fields). First batch (arx plain-string) pushed as 6427f5b; the rest uncommitted. ⚠ Deploy mobile + a prod `seed_forms` re-seed together for land_use_purpose.
- **#3 language freeze** — already mostly fixed for arch/design (codes + render-time translate); legacy `calculator_orders` left frozen (out of scope). → covered by A (admin translate) + B bonus.
- **#4 admin pages** — keep the shared `calculator-orders` page; add a type column/filter (no dedicated pages). Swallowed-per-service-failure audit deferred. → Slice A.

Recommended order: A (admin codes→labels + type column) → B (options-only). C/D + legacy-calc deferred unless asked.
