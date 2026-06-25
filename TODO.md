# TODO

## 2026-06-25

- Calculator orders: confirm admin shows every field the user submitted; current gap is that architecture/design wizard data is stored in backend but not visible in admin.
- Calculator options for architecture/design must come from backend-managed data, not static mobile screen definitions.
- Order content is currently frozen in the submit-time language because labels/values are stored as translated strings. Replace this with backend-driven keys/codes and translate at render time per viewer language.
- Add admin pages for architecture/design orders and verify the creation flow surfaces any per-service submission failures instead of swallowing them.
