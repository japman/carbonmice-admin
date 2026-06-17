# Audit-log pagination + credit column relabel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the app-users list credit-column header to "คาร์บอนเครดิตรวม", and replace the audit-log's 200-row limit + truncation warning with offset-based prev/next pagination at 25 rows per page.

**Architecture:** Hexagonal Rails (view → controller → domain use case → query port/adapter). Change 1 is a one-line view edit. Change 2 is a vertical slice through all four layers, mirroring the existing pagination pattern already shipped for the app-users and events lists (`limit(PAGE_SIZE + 1).offset(...)` in the adapter; `@has_next`/`@page` in the controller; prev/next links in the partial).

**Tech Stack:** Ruby 4.0.0 + Rails (run everything via `/opt/homebrew/bin/mise exec --`), Hotwire/Turbo frames, Minitest (controller integration + Selenium system tests).

**Toolchain note (read once):** The shell defaults to system Ruby 2.6, which fails. EVERY ruby/rails/rubocop/brakeman command in this plan MUST be prefixed with `/opt/homebrew/bin/mise exec --`. Git commands use the `rtk` prefix per the repo CLAUDE.md.

**Spec:** `docs/superpowers/specs/2026-06-17-audit-pagination-and-credit-label-design.md`

---

## File Structure

| File | Change | Responsibility |
|------|--------|----------------|
| `app/views/app_users/_list.html.erb` | Modify (line 9) | Header label rename |
| `test/system/app_users_test.rb` | Modify | Assert the new header text |
| `app/adapters/persistence/ar_audit_log_query.rb` | Modify | `PAGE_SIZE`, `page:` param, `limit+1`/`offset` |
| `app/domain/ports/audit_log_query.rb` | Modify | Port doc contract gains `page:` |
| `app/domain/audit/list_entries.rb` | Modify | Thread `page:` through to the query |
| `app/controllers/audit_logs_controller.rb` | Modify | Clamp page, compute `@has_next`/`@page`, drop `@truncated` |
| `app/views/audit_logs/_list.html.erb` | Modify | Drop warning block, add prev/next nav |
| `test/controllers/audit_logs_controller_test.rb` | Modify | Replace truncation test with pagination tests |
| `test/system/audit_logs_test.rb` | Modify | Add a next-page system test |

---

## Task 1: Rename the app-users credit column header

**Files:**
- Modify: `app/views/app_users/_list.html.erb:9`
- Test: `test/system/app_users_test.rb:53-63` (extend the existing credit-total test)

**Context:** The app-users list has a column header that currently reads "เครดิตรวม" (line 9). The data cell below it (`_app_user.html.erb`) shows the summed carbon-credit total. The existing system tests assert that value by column position (`td:nth-child(5)`), never by header text, so renaming the header does not touch them. Note: the old header text "เครดิตรวม" is a *substring* of the new "คาร์บอนเครดิตรวม", so the new-text assertion correctly fails before the rename and passes after.

- [ ] **Step 1: Add the failing header assertion**

In `test/system/app_users_test.rb`, inside the existing test `"lists the total carbon credit summed across offset sources"`, add a header assertion right after `visit app_users_path`. The full test becomes:

```ruby
  test "lists the total carbon credit summed across offset sources" do
    user = create_core_user!(email: "credits_au@example.com", display_name: "เครดิตรวม")
    s1 = create_core_offset_source!(name: "Solar")
    s2 = create_core_offset_source!(name: "Wind")
    create_core_carbon_credit!(user_id: user.id, amount: 100, source_id: s1.id)
    create_core_carbon_credit!(user_id: user.id, amount: 50, source_id: s2.id)
    login_admin
    visit app_users_path
    # The column header reads the full carbon-credit label.
    assert_selector "th", text: "คาร์บอนเครดิตรวม"
    # 5th column is the summed credit total (after name, email, role, quota).
    assert_selector "##{dom_id(user)} td:nth-child(5)", text: "150"
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `/opt/homebrew/bin/mise exec -- bin/rails test test/system/app_users_test.rb -n "/lists the total carbon credit/"`
Expected: FAIL — Capybara cannot find a `th` containing "คาร์บอนเครดิตรวม" (header still reads "เครดิตรวม").

- [ ] **Step 3: Rename the header**

In `app/views/app_users/_list.html.erb`, change line 9 from:

```erb
        <th class="px-4 py-3">เครดิตรวม</th>
```

to:

```erb
        <th class="px-4 py-3">คาร์บอนเครดิตรวม</th>
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `/opt/homebrew/bin/mise exec -- bin/rails test test/system/app_users_test.rb -n "/lists the total carbon credit/"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
rtk git add app/views/app_users/_list.html.erb test/system/app_users_test.rb
rtk git commit -m "feat: rename app-users credit column to คาร์บอนเครดิตรวม"
```

---

## Task 2: Audit-log offset pagination (25 per page)

**Files:**
- Modify: `app/adapters/persistence/ar_audit_log_query.rb`
- Modify: `app/domain/ports/audit_log_query.rb`
- Modify: `app/domain/audit/list_entries.rb`
- Modify: `app/controllers/audit_logs_controller.rb`
- Modify: `app/views/audit_logs/_list.html.erb`
- Test: `test/controllers/audit_logs_controller_test.rb`
- Test: `test/system/audit_logs_test.rb`

**Context:** This is one cohesive vertical slice — the query signature, use case, controller, and view must change together or intermediate states break (e.g. changing the adapter signature without the use case raises `ArgumentError`). So it is implemented and committed as a single task, driven by controller integration tests (the observable behavior) plus one system test. It mirrors the already-shipped app-users pagination exactly.

Reference — the existing app-users controller (`app/controllers/app_users_controller.rb`) and its view (`app/views/app_users/_list.html.erb`) show the canonical pattern this task copies: `page = params[:page].to_i.clamp(1, 10_000)`, fetch `PAGE_SIZE + 1` rows, `@has_next = rows.size > PAGE_SIZE`, slice to `PAGE_SIZE`, prev/next `link_to` carrying the filter params.

Current behavior being removed: the controller sets `@truncated = @entries.size >= DEFAULT_LIMIT` and the view renders a "...อาจถูกตัดทอน" warning when 200 rows are returned. The existing controller test `"shows truncation notice when the limit is hit"` (lines 57-67) references `Persistence::ArAuditLogQuery::DEFAULT_LIMIT` and asserts that warning — it tests behavior that no longer exists and **must be replaced** with the pagination tests below (leaving it raises `NameError: uninitialized constant ... DEFAULT_LIMIT` once the constant is gone).

- [ ] **Step 1: Write the failing pagination controller tests**

In `test/controllers/audit_logs_controller_test.rb`, **delete** the existing test `"shows truncation notice when the limit is hit"` (lines 57-67 in the current file) and add the following three tests plus a private seed helper. Put the helper after the `login` method and the new tests alongside the others:

```ruby
  # Inserts `count` audit entries with strictly descending timestamps (index 0 is
  # newest) so newest-first ordering and page slicing are deterministic. insert_all
  # bypasses the readonly model guard — acceptable in test fixtures.
  def seed_entries(count, action: "seed.event")
    rows = Array.new(count) do |i|
      { action: action, actor_id: @superadmin.id, actor_email: @superadmin.email_address,
        change_set: {}, created_at: (i + 1).minutes.ago }
    end
    AuditLog.insert_all(rows)
  end

  test "page 1 shows 25 rows and a next-page link when more exist" do
    login(@superadmin)            # adds one entry (auth.login_succeeded), newest
    seed_entries(25)              # 26 total => page 1 is full, a 2nd page exists
    get audit_logs_path
    assert_response :success
    assert_select "tbody tr", count: 25
    assert_select "a", text: /ถัดไป/ do |links|
      assert_includes links.first["href"], "page=2"
    end
  end

  test "page 2 shows the remaining rows and no next-page link" do
    login(@superadmin)            # 1 entry
    seed_entries(25)              # 26 total => page 2 holds the single oldest row
    get audit_logs_path, params: { page: 2 }
    assert_response :success
    assert_select "tbody tr", count: 1
    assert_select "a", text: /ถัดไป/, count: 0
  end

  test "pagination preserves the action_prefix filter in page links" do
    login(@superadmin)            # auth.login_succeeded is filtered out
    seed_entries(26, action: "admin_users.created")  # 26 matching => 2 pages
    get audit_logs_path, params: { action_prefix: "admin_users." }
    assert_select "tbody tr", count: 25
    assert_select "a", text: /ถัดไป/ do |links|
      href = links.first["href"]
      assert_includes href, "action_prefix=admin_users"
      assert_includes href, "page=2"
    end
  end
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `/opt/homebrew/bin/mise exec -- bin/rails test test/controllers/audit_logs_controller_test.rb`
Expected: the three new tests FAIL — with the current 200-row limit and no `<tbody>`-level slicing, page 1 renders all 26 rows (`assert_select "tbody tr", count: 25` fails) and no "ถัดไป" link exists. (The other pre-existing tests still pass.)

- [ ] **Step 3: Add pagination to the query adapter**

Replace the entire contents of `app/adapters/persistence/ar_audit_log_query.rb` with:

```ruby
module Persistence
  class ArAuditLogQuery
    PAGE_SIZE = 25

    def entries(actor_id: nil, action_prefix: nil, from: nil, to: nil, page: 1)
      safe_page = page.to_i.clamp(1, 10_000)
      scope = AuditLog.order(created_at: :desc)
                      .limit(PAGE_SIZE + 1)
                      .offset((safe_page - 1) * PAGE_SIZE)
      scope = scope.where(actor_id: actor_id) if actor_id.present?
      scope = scope.where("action LIKE ?", "#{AuditLog.sanitize_sql_like(action_prefix)}%") if action_prefix.present?
      if (from_date = safe_date(from))
        scope = scope.where(created_at: from_date.beginning_of_day..)
      end
      if (to_date = safe_date(to))
        scope = scope.where(created_at: ..to_date.end_of_day)
      end
      scope
    end

    private

      # Malformed ?from=/=?to= URL params are ignored rather than 500ing.
      def safe_date(value)
        value.presence&.to_date
      rescue Date::Error
        nil
      end
  end
end
```

- [ ] **Step 4: Update the port contract doc**

In `app/domain/ports/audit_log_query.rb`, update the contract comment so the signature shows `page:` instead of `limit:`:

```ruby
module Ports
  # Contract:
  #   entries(actor_id: nil, action_prefix: nil, from: nil, to: nil, page: 1) -> [entry]
  #   Returns up to PAGE_SIZE + 1 rows (the extra row signals "a next page exists").
  # Entries respond to: created_at, actor_email, action, target_type, target_id, change_set, ip_address.
  # Newest first.
  module AuditLogQuery
  end
end
```

- [ ] **Step 5: Thread `page:` through the use case**

Replace the contents of `app/domain/audit/list_entries.rb` with:

```ruby
module Audit
  class ListEntries
    def self.call(actor:, query:, filters: {}, page: 1)
      return Result.failure("คุณไม่มีสิทธิ์ดูบันทึกการใช้งาน") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :view_audit_log)

      Result.success(query.entries(**filters, page: page))
    end
  end
end
```

- [ ] **Step 6: Update the controller**

Replace the `index` action in `app/controllers/audit_logs_controller.rb` (keep the `before_action` and the private `filters` method unchanged):

```ruby
  def index
    page = params[:page].to_i.clamp(1, 10_000)
    result = Audit::ListEntries.call(actor: current_admin, query: Persistence::ArAuditLogQuery.new,
                                     filters: filters, page: page)
    raise ApplicationController::NotAuthorized if result.failure?
    rows = result.value.to_a
    @has_next = rows.size > Persistence::ArAuditLogQuery::PAGE_SIZE
    @entries = rows.first(Persistence::ArAuditLogQuery::PAGE_SIZE)
    @page = page
  end
```

- [ ] **Step 7: Update the list partial — drop the warning, add prev/next**

Replace the entire contents of `app/views/audit_logs/_list.html.erb` with (the warning block at the top is removed; the prev/next nav at the bottom mirrors `app/views/app_users/_list.html.erb`, carrying the audit filter params):

```erb
<%= turbo_frame_tag "al_list", data: { turbo_action: "advance" } do %>
  <table class="mt-6 w-full rounded-xl bg-white shadow-sm text-sm">
    <thead>
      <tr class="border-b border-gray-200 text-left text-body/60">
        <th class="px-4 py-3">เวลา</th>
        <th class="px-4 py-3">ผู้กระทำ</th>
        <th class="px-4 py-3">การกระทำ</th>
        <th class="px-4 py-3">เป้าหมาย</th>
        <th class="px-4 py-3">รายละเอียด</th>
        <th class="px-4 py-3">IP</th>
      </tr>
    </thead>
    <tbody>
      <% @entries.each do |e| %>
        <tr class="border-b border-gray-100 align-top">
          <td class="whitespace-nowrap px-4 py-3"><%= e.created_at.in_time_zone.strftime("%d/%m/%Y %H:%M:%S") %></td>
          <td class="px-4 py-3"><%= e.actor_email %></td>
          <td class="px-4 py-3 font-medium text-ink"><%= e.action %></td>
          <td class="px-4 py-3"><%= [e.target_type, e.target_id].compact.join("#") %></td>
          <td class="px-4 py-3 font-mono text-xs"><%= e.change_set.presence&.to_json %></td>
          <td class="px-4 py-3"><%= e.ip_address %></td>
        </tr>
      <% end %>
    </tbody>
  </table>

  <div class="mt-4 flex items-center gap-3">
    <% if @page > 1 %>
      <%= link_to "← ก่อนหน้า", audit_logs_path(action_prefix: params[:action_prefix], from: params[:from], to: params[:to], page: @page - 1), class: "text-primary" %>
    <% end %>
    <span class="text-sm text-body/60">หน้า <%= @page %></span>
    <% if @has_next %>
      <%= link_to "ถัดไป →", audit_logs_path(action_prefix: params[:action_prefix], from: params[:from], to: params[:to], page: @page + 1), class: "text-primary" %>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 8: Run the controller tests to verify they pass**

Run: `/opt/homebrew/bin/mise exec -- bin/rails test test/controllers/audit_logs_controller_test.rb`
Expected: PASS — all tests green (the three new pagination tests plus the unchanged filter/auth/date tests).

- [ ] **Step 9: Add the next-page system test**

In `test/system/audit_logs_test.rb`, add this test after the existing one (it reuses the `login_superadmin` helper):

```ruby
  test "clicking ถัดไป re-renders al_list and advances the URL with page" do
    login_superadmin
    # login already wrote auth.login_succeeded. Add 25 more so a 2nd page exists.
    rows = Array.new(25) do |i|
      { action: "admin_users.created", actor_id: @superadmin.id,
        actor_email: @superadmin.email_address, change_set: {}, created_at: (i + 1).minutes.ago }
    end
    AuditLog.insert_all(rows)

    visit audit_logs_path
    assert_selector "#al_list a", text: "ถัดไป →"

    within "#al_list" do
      click_link "ถัดไป →"
    end

    # The frame re-renders showing the previous-page link, and the URL advances.
    assert_selector "#al_list a", text: "← ก่อนหน้า"
    assert_current_path(/page=2/)
  end
```

- [ ] **Step 10: Run the audit system tests to verify they pass**

Run: `/opt/homebrew/bin/mise exec -- bin/rails test test/system/audit_logs_test.rb`
Expected: PASS — both the existing filter test and the new next-page test.

- [ ] **Step 11: Commit**

```bash
rtk git add app/adapters/persistence/ar_audit_log_query.rb app/domain/ports/audit_log_query.rb app/domain/audit/list_entries.rb app/controllers/audit_logs_controller.rb app/views/audit_logs/_list.html.erb test/controllers/audit_logs_controller_test.rb test/system/audit_logs_test.rb
rtk git commit -m "feat: paginate the audit log (25/page) replacing the 200-row cap"
```

---

## Final verification gate

Run after both tasks are complete. Do not skip.

- [ ] **Full unit/integration suite**

Run: `/opt/homebrew/bin/mise exec -- bin/rails test`
Expected: PASS, 0 failures / 0 errors.

- [ ] **System tests**

Run: `/opt/homebrew/bin/mise exec -- bin/rails test:system`
Expected: PASS, 0 failures / 0 errors.

- [ ] **Rubocop**

Run: `/opt/homebrew/bin/mise exec -- bundle exec rubocop app/adapters/persistence/ar_audit_log_query.rb app/domain/audit/list_entries.rb app/controllers/audit_logs_controller.rb`
Expected: no offenses.

- [ ] **Brakeman**

Run: `/opt/homebrew/bin/mise exec -- bundle exec brakeman -q`
Expected: 0 security warnings.

- [ ] **Re-index the codebase graph**

Re-run `index_repository` (mode `fast`) on the `carbonmice-admin` project so graph-first discovery sees the new code.

---

## Self-Review (filled in by plan author)

**1. Spec coverage:**
- Change 1 (relabel `เครดิตรวม` → `คาร์บอนเครดิตรวม`) → Task 1. ✓
- Change 2 query layer (`PAGE_SIZE`, `page:`, `limit+1`/`offset`, drop `DEFAULT_LIMIT`) → Task 2 Step 3. ✓
- Port doc → Step 4. ✓ Use case threading `page:` → Step 5. ✓
- Controller (clamp, `@has_next`, `@page`, drop `@truncated`) → Step 6. ✓
- View (drop warning, prev/next preserving filters) → Step 7. ✓
- Replace truncation test → Step 1. ✓ Pagination controller tests → Step 1. ✓ System test → Step 9. ✓
- Out-of-scope items (no count UI, no infinite scroll, nav once below table) respected. ✓

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows full code. ✓

**3. Type consistency:** `PAGE_SIZE` (not `DEFAULT_LIMIT`) used consistently across adapter, controller, and prose. `page:` keyword consistent across adapter → use case → controller. `@has_next`/`@page`/`@entries` consistent between controller and view. ✓
