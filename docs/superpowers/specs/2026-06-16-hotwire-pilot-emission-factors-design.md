# Hotwire pilot — emission factors (the pattern for the rollout)

> Feature 3 of 3 in the current batch (post-`v0.0.1`). First real use of the already-installed
> Hotwire stack (turbo-rails + stimulus-rails + importmap). Establishes the reusable pattern on
> ONE resource (`emission_factors`); the other ~9 resources roll out later by copying this pattern.
> No domain / Go / schema / migration change — web layer (controllers, views, JS) only.

## Goal

Make the `emission_factors` admin screen dynamic across four dimensions, using shared
infrastructure that transfers to every other resource:
1. **Search/filter without a full-page reload** (Turbo Frame + debounced auto-submit).
2. **New/Edit in a modal** (Turbo Frame) — no page change.
3. **Live list + flash updates** via Turbo Streams (create/update/delete patch the table in place).
4. **Stimulus sprinkles** — modal, toast (auto-dismiss), debounced filter, and a styled custom
   confirm dialog replacing the native `confirm()`.

## Current state (baseline)

Hotwire gems installed but unused (only scaffold `hello_controller.js`). All CRUD uses full-page
`redirect_to` + a static `shared/_flash` partial. `emission_factors`:
- `index`: header + amber warning banner + GET filter form (`search` text + `category_id` select)
  + table + prev/next pagination. List ordered by **`identifier`** (immutable), `PAGE_SIZE = 25`.
- `new`/`edit`: separate full pages; `create`/`update` re-render with `:unprocessable_entity` +
  `flash.now[:alert]` on error; `destroy` uses `data-turbo-confirm`.
- Model `Core::EmissionFactor` → `dom_id` = `emission_factor_<id>`.
- `identifier` is immutable on update; `update_params` excludes it.

## Design

### Shared infrastructure (built once, reused by the rollout)

**Stimulus controllers** (`app/javascript/controllers/`):
- `modal_controller.js` — shows an overlay dialog around its Turbo Frame content; closes on ESC,
  backdrop click, an explicit close button, and on `turbo:submit-end` when the submit succeeded
  (`event.detail.success`). Connect/disconnect manage body scroll lock.
- `toast_controller.js` — auto-dismiss after ~4s (and on click); fade-out; respects nothing else.
- `filter_controller.js` — `requestSubmit()`s its form on `input` (debounced ~300ms, for the
  search box) and on `change` (immediate, for selects). The visible "กรอง" button stays as a
  no-JS fallback.
- Remove the scaffold `hello_controller.js`.

**Custom confirm** — in `app/javascript/application.js` (or a small `confirm.js` it imports),
register `Turbo.setConfirmMethod(...)` to render a styled confirm dialog returning a
`Promise<boolean>`. Because it overrides Turbo's global confirm, every existing
`data-turbo-confirm="…"` button (delete buttons across the whole app) gets the new dialog with
no per-button change.

**Layout** (`app/views/layouts/application.html.erb`):
- Add a persistent, empty `<turbo-frame id="modal">` wrapped by a `modal` Stimulus host, plus a
  `<div id="toast_container">` (the Turbo Stream target for toasts), inside `<main>` and also in
  the unauthenticated branch where appropriate (toasts at least).
- The existing `shared/_flash` keeps working for full-page loads; ALSO render full-page flash as a
  toast (so notice/alert on a normal navigation appears in the same toast UI). Keep `_flash`
  available for the no-JS fallback.

**Shared partials** (`app/views/shared/`):
- `_modal.html.erb` — modal chrome (overlay + centered card + title slot + close button) wrapping
  `yield`/content; used by `new`/`edit`.
- `_toast.html.erb` — one toast (kind: notice/alert → green/red), `data-controller="toast"`.

### emission_factors — dimension by dimension

**1. Filter (Turbo Frame).**
- Wrap the table + pagination block in `<turbo-frame id="ef_list" data-turbo-action="advance">`.
- The filter `form_with method: :get` targets `#ef_list` (`data: { turbo_frame: "ef_list" }`) and
  carries `data-controller="filter"`. Pagination links live inside the frame (so they replace it)
  and also advance history.
- `data-turbo-action="advance"` keeps the browser URL in sync so a filtered/paged view is
  refresh- and share-able.
- **No controller change** for filtering: a frame request re-renders `index`; Turbo extracts
  `#ef_list`. Extract the table+pagination into a partial (`_list.html.erb`) so create can also
  re-render it if ever needed, but the frame mechanism needs only the template restructure.

**2. New/Edit modal (Turbo Frame).**
- Extract the form fields into `app/views/emission_factors/_form.html.erb` (shared by new/edit;
  handles the create-vs-edit differences: `identifier` editable on new, disabled on edit).
- `new.html.erb` / `edit.html.erb` wrap `_form` in `<turbo-frame id="modal">` + the shared
  `_modal` chrome, including an inline error region that shows `flash.now[:alert]` /
  validation error.
- index "เพิ่มค่า EF" link and each row's "แก้ไข" link get `data: { turbo_frame: "modal" }`.
- On validation failure, `create`/`update` still `render :new/:edit, status: :unprocessable_entity`
  — because that response is the `#modal` frame, Turbo replaces the modal content and the modal
  stays open showing the error. (Progressive enhancement: opened directly without a frame, the
  page still renders the form.)

**3. Turbo Streams for writes.**
- Row partial `app/views/emission_factors/_emission_factor.html.erb` (`id: dom_id(factor)`), and
  the table body becomes `<tbody id="ef_rows">`.
- Controllers respond per format (progressive enhancement — keeps existing tests green):
  - `create` → `format.turbo_stream`: `prepend` the new row to `#ef_rows` + close the modal +
    append a success toast. `format.html { redirect_to … }` (fallback).
  - `update` → `format.turbo_stream`: `replace` `dom_id(factor)` with the row partial (position is
    stable because the list is ordered by the **immutable** `identifier`) + close modal + toast.
    `format.html { redirect_to … }`.
  - `destroy` → `format.turbo_stream`: `remove dom_id(factor)` + toast. `format.html { redirect_to … }`.
- Closing the modal = a stream that replaces `#modal` with an empty frame (and/or the
  `modal_controller` closing on `turbo:submit-end` success).
- **Documented trade-off (create under an active filter/sort):** the new row is prepended to the
  top even though the list is `identifier`-sorted and a filter may exclude it; it settles into the
  correct position / visibility on the next list load. Accepted for the pilot (admin-volume, low
  risk). Not changing pagination logic.

**4. Sprinkles** — as in Shared infrastructure: modal, toast, filter, custom confirm. The existing
delete button keeps its `data-turbo-confirm` text and now shows the styled dialog.

## Testing

- **System tests** (`test/system/…`, Capybara + headless Chrome) are the real proof:
  1. typing in the search box live-filters `#ef_list` without a full reload (assert a row
     appears/disappears; URL updates).
  2. "เพิ่มค่า EF" opens the modal; submitting a valid factor closes it, the new row appears, a
     success toast shows.
  3. "แก้ไข" opens the modal; saving replaces the row in place; toast shows.
  4. deleting via the custom confirm removes the row; toast shows.
  5. submitting an invalid new factor keeps the modal open and shows the error.
- **Controller tests** (`test/controllers/emission_factors_controller_test.rb`): add
  `as: :turbo_stream` cases asserting `create`/`update`/`destroy` return
  `content_type` turbo-stream with the expected stream actions; KEEP the existing HTML-format
  tests (they hit `format.html` and must still redirect — proves progressive enhancement / no-JS).
- Full gate at the end: `bin/rails test`, `bin/rails test:system`, `bin/rubocop`,
  `bundle exec brakeman -q`.

## Out of scope

- The other ~9 resources (separate rollout once this pattern is approved in practice).
- Any change to `app/domain/**`, the Go backend, the DB schema, or migrations.
- Smart insertion of a created row at its correct sorted position / page (prepend is accepted).
- Inline-row editing (modal chosen instead).
- npm/build tooling changes (stay on importmap + tailwindcss-rails).

## Verification (manual smoke, docker compose up)

Login → ค่า EF: type to filter (no page flash, URL updates) → add (modal, row appears, toast) →
edit (modal, row updates) → delete (styled confirm, row removed, toast) → invalid add (modal stays,
error shown) → disable JS / curl shows the HTML fallback still redirects.
