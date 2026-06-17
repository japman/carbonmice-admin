# Admin: audit-log pagination + carbon-credit column relabel

Date: 2026-06-17
Scope: `carbonmice-admin` only (Rails). No changes to `carbonmice-main-fe` or
`carbonmice-main-go-be`.

Architecture is hexagonal: view → controller (params) → domain use case → query
port/adapter. Each change is applied at the correct layer.

---

## Change 1 — Relabel the app-users credit column

The app-users list header currently reads "เครดิตรวม". Rename it to
"คาร์บอนเครดิตรวม". Label-only change.

- `app/views/app_users/_list.html.erb`: change the `<th>เครดิตรวม</th>` header
  to `<th>คาร์บอนเครดิตรวม</th>`.

The data cell (`_app_user.html.erb`, `td:nth-child(5)`) is unchanged. The
existing system tests assert the credit total by column position
(`td:nth-child(5)`), not by header text, so they remain green.

---

## Change 2 — Audit log pagination (offset prev/next, 25 per page)

Today `ArAuditLogQuery#entries` runs `order(created_at: :desc).limit(200)`. The
controller sets `@truncated = @entries.size >= DEFAULT_LIMIT` and the view shows
a "แสดงเพียง 200 รายการล่าสุด … อาจถูกตัดทอน" warning. Replace this with
offset-based pagination matching the established pattern already used by the
events and app-users lists (`limit(PAGE_SIZE + 1).offset(...)`, `@has_next`,
`@page`, prev/next links).

Page size: **25** per page (`PAGE_SIZE = 25`), consistent with the other lists.

### Layer-by-layer

**1. `app/adapters/persistence/ar_audit_log_query.rb`**
- Replace `DEFAULT_LIMIT = 200` with `PAGE_SIZE = 25`.
- `entries` gains a `page:` keyword (default `1`). It clamps `page` to `>= 1`,
  then replaces `.limit(DEFAULT_LIMIT)` with
  `.limit(PAGE_SIZE + 1).offset((page - 1) * PAGE_SIZE)`. The `+ 1` lookahead row
  lets the controller detect whether a next page exists. All existing filter
  clauses (actor_id, action_prefix, from, to, `safe_date`) are unchanged.

**2. `app/domain/ports/audit_log_query.rb`**
- Update the documentation-only port contract so the `entries` signature
  includes `page:`.

**3. `app/domain/audit/list_entries.rb`**
- Add a `page: 1` parameter to `call`. Keep the auth check. Forward the page to
  the query: `query.entries(**filters, page: page)`. Page is passed separately
  from `filters` (it is navigation state, not a filter).

**4. `app/controllers/audit_logs_controller.rb`**
- `page = params[:page].to_i.clamp(1, 10_000)` (matches the events controller).
- Call `Audit::ListEntries.call(actor:, query:, filters:, page:)`.
- `rows = result.value.to_a`
- `@has_next = rows.size > Persistence::ArAuditLogQuery::PAGE_SIZE`
- `@entries = rows.first(Persistence::ArAuditLogQuery::PAGE_SIZE)`
- `@page = page`
- Remove the `@truncated` assignment.

**5. `app/views/audit_logs/_list.html.erb`**
- Remove the `@truncated` warning block (and its reference to `DEFAULT_LIMIT`).
- After the table, inside the existing `al_list` turbo-frame, add a prev/next nav
  identical in shape to the app-users / events lists: a "← ก่อนหน้า" link when
  `@page > 1`, a "หน้า <%= @page %>" label, and a "ถัดไป →" link when
  `@has_next`. Every page link carries the current filters so navigation
  preserves them:
  `audit_logs_path(action_prefix: params[:action_prefix], from: params[:from], to: params[:to], page: @page - 1)`
  (and `+ 1` for next).

### Data flow

index → `Audit::ListEntries` (auth check) → `query.entries(filters, page)`
returns up to `PAGE_SIZE + 1` (26) rows → controller computes `@has_next` and
slices to 25 → view renders the table plus prev/next. The nav lives inside the
existing `al_list` turbo-frame (`turbo_action: "advance"`), so paging
re-renders only the frame and advances the URL — same behavior as the filter
form today.

### Error handling

- Garbage `page` param → `.to_i` yields `0` → clamped to `1`.
- A page past the end → empty table with a working "← ก่อนหน้า" link. This
  matches how events / app-users behave today and needs no special handling.
- Authorization failure → existing `raise ApplicationController::NotAuthorized`.

---

## Testing

Follow the existing test patterns for the events / app-users paginated lists.

**Change 1 (relabel):**
- `test/system/app_users_test.rb`: add a short assertion to an existing test (or
  a tiny new one) that the list header reads "คาร์บอนเครดิตรวม". The existing
  data-cell tests assert by column position (`td:nth-child(5)`), not header text,
  so they stay green and already cover the values.

**Change 2 (pagination):**
- `test/controllers/audit_logs_controller_test.rb`:
  - **Replace** the existing `"shows truncation notice when the limit is hit"`
    test — `DEFAULT_LIMIT` and the truncation notice no longer exist.
  - Page 1 returns the first 25 newest entries; with ≥ 26 entries a "ถัดไป"
    next-page link is rendered.
  - Page 2 returns the next batch (entries not shown on page 1).
  - Filters (e.g. `action_prefix`) are preserved across page navigation (the
    next/prev links include the active filter params).
  - Seed rows with `AuditLog.insert_all(...)` and explicit `created_at`, as the
    existing tests do (the model is readonly at the instance level).
- `test/system/audit_logs_test.rb`:
  - Clicking "ถัดไป →" re-renders `#al_list` without a full reload and advances
    the URL to include `page=`.
  - A selected `action_prefix` filter remains applied after paging to the next
    page.

---

## Out of scope

- `carbonmice-main-fe` and `carbonmice-main-go-be`.
- No total-count / numbered-page UI: prev/next only, matching the existing
  convention (avoids a `COUNT(*)` on a growing audit table).
- No "load more" / infinite scroll.
- Pagination controls appear once, below the table (not duplicated above it).
- No new filter inputs; the existing action_prefix / from / to filters are
  unchanged apart from being carried through page links.
