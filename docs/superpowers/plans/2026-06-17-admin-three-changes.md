# Admin Three Changes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make carbon-credit offset source required + merge-on-add, remove the province field from event editing, and add first-time package-flagging plus a total-credit column to app user management — all in the admin Rails app.

**Architecture:** Hexagonal Rails (view → controller params → domain use case → repo port/adapter). Validation stays authoritative in domain use cases. The carbon-credit merge is enforced at the domain layer (no DB unique constraint). The credit total is a single grouped aggregate query in the controller (no N+1).

**Tech Stack:** Ruby on Rails, Hotwire/Turbo, Minitest (domain unit tests with hand-rolled fake repos + Selenium headless system tests), PostgreSQL (`Core::*` read/write models, soft-delete via `kept`).

**Spec:** `docs/superpowers/specs/2026-06-17-admin-three-changes-design.md`

**Test commands:**
- Single domain test: `bin/rails test test/domain/master_data/carbon_credit_test.rb`
- Single system test: `bin/rails test:system TEST=test/system/carbon_credits_test.rb`
- Full gate (run at end): `bin/rails test && bin/rails test:system && bundle exec rubocop && bundle exec brakeman -q`

---

## Change 1 — Carbon Credit: offset source required + merge on add (sum)

### Task 1: Domain — require offset source and merge into existing record

**Files:**
- Modify: `app/domain/master_data/create_carbon_credit.rb`
- Modify: `app/adapters/persistence/ar_carbon_credit_repository.rb`
- Modify: `app/domain/ports/carbon_credit_repository.rb` (doc comment)
- Test: `test/domain/master_data/carbon_credit_test.rb`

- [ ] **Step 1: Update the fake repo and existing create tests, then add new failing tests**

In `test/domain/master_data/carbon_credit_test.rb`, add a `find_kept_by` method to `FakeCreditRepo` (place it after `create`):

```ruby
  def find_kept_by(user_id:, source_id:)
    @rows.values.find { |r| !r.deleted && r.user_id == user_id && r.carbon_offset_source_id == source_id }
  end
```

Change `valid_attrs` so a source is always present (source is now required):

```ruby
  def valid_attrs
    { user_id: "user-uuid-1", carbon_credit: "100", carbon_offset_source_id: "src-1" }
  end
```

Update `test_create_success_audits_carbon_credit_created` — it currently asserts the stored source is `nil`. Replace that assertion so it expects the source from `valid_attrs`:

```ruby
  def test_create_success_audits_carbon_credit_created
    result = MasterData::CreateCarbonCredit.call(actor: @admin,
               attrs: valid_attrs.merge(carbon_credit: "50"), repo: @repo, audit: @audit)
    assert result.success?
    assert_equal 50, result.value.carbon_credit
    assert_equal "src-1", result.value.carbon_offset_source_id
    assert_equal "carbonmice-admin:ad@pea.co.th", result.value.created_by
    assert_equal "master_data.carbon_credit_created", @audit_entries.last[:action]
    assert_equal({ "user_id" => "user-uuid-1", "carbon_credit" => 50 }, @audit_entries.last[:changes])
  end
```

Add these new tests at the end of the `# Create` section (before the `# Update` divider):

```ruby
  def test_create_requires_source
    result = MasterData::CreateCarbonCredit.call(actor: @admin,
               attrs: valid_attrs.merge(carbon_offset_source_id: ""), repo: @repo, audit: @audit)
    assert result.failure?
    assert_match "กรุณาเลือกแหล่งออฟเซ็ต", result.error
    assert_empty @audit_entries
  end

  def test_create_merges_into_existing_user_and_source_by_summing
    first = MasterData::CreateCarbonCredit.call(actor: @admin,
              attrs: valid_attrs.merge(carbon_credit: "100"), repo: @repo, audit: @audit)
    assert first.success?

    second = MasterData::CreateCarbonCredit.call(actor: @admin,
               attrs: valid_attrs.merge(carbon_credit: "30"), repo: @repo, audit: @audit)
    assert second.success?

    # Same row, summed amount — not a new row.
    assert_equal first.value.id, second.value.id
    assert_equal 130, second.value.carbon_credit
    assert_equal 1, @repo.rows.size
    assert_equal "master_data.carbon_credit_updated", @audit_entries.last[:action]
    assert_equal({ "carbon_credit" => { "from" => 100, "to" => 130 } }, @audit_entries.last[:changes])
  end

  def test_create_does_not_merge_when_source_differs
    MasterData::CreateCarbonCredit.call(actor: @admin,
      attrs: valid_attrs.merge(carbon_credit: "100", carbon_offset_source_id: "src-1"),
      repo: @repo, audit: @audit)
    MasterData::CreateCarbonCredit.call(actor: @admin,
      attrs: valid_attrs.merge(carbon_credit: "40", carbon_offset_source_id: "src-2"),
      repo: @repo, audit: @audit)
    assert_equal 2, @repo.rows.size
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/domain/master_data/carbon_credit_test.rb`
Expected: FAIL — `test_create_requires_source`, the two merge tests, and the updated success test fail (source still optional, no merge, `find_kept_by` unused).

- [ ] **Step 3: Add the `find_kept_by` finder to the repo**

In `app/adapters/persistence/ar_carbon_credit_repository.rb`, add after `find`:

```ruby
    def find_kept_by(user_id:, source_id:)
      Core::CarbonCredit.kept.find_by(user_id: user_id, carbon_offset_source_id: source_id)
    rescue ActiveRecord::StatementInvalid
      nil
    end
```

In `app/domain/ports/carbon_credit_repository.rb`, add the finder to the doc comment under `find(id)`:

```ruby
  # find_kept_by(user_id:, source_id:) → record | nil
```

- [ ] **Step 4: Implement required source + merge in the use case**

In `app/domain/master_data/create_carbon_credit.rb`, replace the body from the `source_id` line through `Result.success(record)` with:

```ruby
      source_id = attrs[:carbon_offset_source_id].to_s.strip
      return Result.failure("กรุณาเลือกแหล่งออฟเซ็ต") if source_id.empty?

      existing = repo.find_kept_by(user_id: user_id, source_id: source_id)
      if existing
        new_amount = existing.carbon_credit + amount
        record = repo.update(existing.id, { carbon_credit: new_amount }, updated_by: AuditIdentity.for(actor))
        audit.record(action: "master_data.carbon_credit_updated", actor: actor, target: record,
                     changes: { "carbon_credit" => { "from" => existing.carbon_credit, "to" => new_amount } })
      else
        record = repo.create(
          { user_id: user_id, carbon_credit: amount, carbon_offset_source_id: source_id },
          created_by: AuditIdentity.for(actor)
        )
        audit.record(action: "master_data.carbon_credit_created", actor: actor, target: record,
                     changes: { "user_id" => user_id, "carbon_credit" => amount })
      end
      Result.success(record)
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/domain/master_data/carbon_credit_test.rb`
Expected: PASS (all create/update/merge tests green).

- [ ] **Step 6: Commit**

```bash
git add app/domain/master_data/create_carbon_credit.rb app/adapters/persistence/ar_carbon_credit_repository.rb app/domain/ports/carbon_credit_repository.rb test/domain/master_data/carbon_credit_test.rb
git commit -m "feat: require offset source and merge carbon credits by (user, source)"
```

---

### Task 2: View + system tests — required offset source in the form

**Files:**
- Modify: `app/views/carbon_credits/_form.html.erb`
- Test: `test/system/carbon_credits_test.rb`

- [ ] **Step 1: Update existing system tests and add a merge system test**

In `test/system/carbon_credits_test.rb`:

(a) The "creating a credit" test must now select a source. Replace that test with:

```ruby
  test "creating a credit shows the new row and a toast, and closes the modal" do
    user = create_core_user!(email: "newcredit@example.com")
    create_core_offset_source!(name: "Solar")
    login_admin
    visit carbon_credits_path
    click_link "เพิ่ม carbon credit"
    assert_selector "turbo-frame#modal h2", text: "เพิ่ม carbon credit"
    within "turbo-frame#modal" do
      select "newcredit@example.com", from: "carbon_credit[user_id]"
      fill_in "carbon_credit[carbon_credit]", with: "150"
      select "Solar", from: "carbon_credit[carbon_offset_source_id]"
      click_on "เพิ่ม"
    end
    assert_selector "#toast_container", text: "เพิ่ม carbon credit แล้ว"
    assert_selector "#cc_rows", text: "newcredit@example.com"
    assert_no_selector "turbo-frame#modal div"
  end
```

(b) The "server-rejected create" test must select a source so the amount-0 server-side rejection is actually reached (an empty required select would otherwise block submission in the browser). Replace it with:

```ruby
  test "server-rejected create keeps modal open with error" do
    user = create_core_user!(email: "rejectcredit@example.com")
    create_core_offset_source!(name: "Solar")
    login_admin
    visit carbon_credits_path
    click_link "เพิ่ม carbon credit"
    assert_selector "turbo-frame#modal h2", text: "เพิ่ม carbon credit"
    within "turbo-frame#modal" do
      select "rejectcredit@example.com", from: "carbon_credit[user_id]"
      select "Solar", from: "carbon_credit[carbon_offset_source_id]"
      # amount 0 is rejected server-side (domain validates > 0). The number field has
      # no min: constraint (see _form.html.erb), so this reaches the server and
      # exercises the render :new, 422 turbo-frame re-render path.
      fill_in "carbon_credit[carbon_credit]", with: "0"
      click_on "เพิ่ม"
    end
    assert_selector "turbo-frame#modal .text-danger"
  end
```

(c) Add a new merge system test at the end of the class:

```ruby
  test "adding a credit for an existing user+source merges by summing into the same row" do
    user = create_core_user!(email: "merge@example.com")
    source = create_core_offset_source!(name: "Solar")
    existing = create_core_carbon_credit!(user_id: user.id, amount: 100, source_id: source.id)
    login_admin
    visit carbon_credits_path
    click_link "เพิ่ม carbon credit"
    within "turbo-frame#modal" do
      select "merge@example.com", from: "carbon_credit[user_id]"
      fill_in "carbon_credit[carbon_credit]", with: "30"
      select "Solar", from: "carbon_credit[carbon_offset_source_id]"
      click_on "เพิ่ม"
    end
    assert_selector "#toast_container", text: "เพิ่ม carbon credit แล้ว"
    # Same row updated to the summed total; no second row added.
    assert_selector "##{dom_id(existing)}", text: "130"
    assert_equal 1, all("#cc_rows tr").size
  end
```

- [ ] **Step 2: Run the system test to verify the new/updated cases fail**

Run: `bin/rails test:system TEST=test/system/carbon_credits_test.rb`
Expected: FAIL — the form has no required source select yet (`select ... from: "carbon_credit[carbon_offset_source_id]"` finds the optional field; merge/required behavior not wired in the view label, and the create test cannot find a "Solar" option only if no source exists — it does exist, but the field is still labelled "ไม่บังคับ"). The merge assertion (`text: "130"`) fails because the view/label still allows the old optional path. Confirm red before editing the view.

- [ ] **Step 3: Make the offset source select required in the form**

In `app/views/carbon_credits/_form.html.erb`, replace the offset-source `<div>` block with:

```erb
  <div>
    <%= f.label :carbon_offset_source_id, "แหล่งออฟเซ็ต", class: "mb-1 block font-medium text-ink" %>
    <%= f.select :carbon_offset_source_id,
          [["เลือกแหล่งออฟเซ็ต", ""]] + @sources.map { |s| [(s.name_th.presence || s.name), s.id] },
          { selected: credit&.carbon_offset_source_id },
          required: true, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
```

- [ ] **Step 4: Run the system test to verify it passes**

Run: `bin/rails test:system TEST=test/system/carbon_credits_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/carbon_credits/_form.html.erb test/system/carbon_credits_test.rb
git commit -m "feat: make carbon credit offset source a required field"
```

---

## Change 2 — Edit Event: remove the province field (no longer editable)

### Task 3: Remove province from the event edit path

**Files:**
- Modify: `app/domain/events/update_details.rb`
- Modify: `app/controllers/events_controller.rb`
- Modify: `app/views/events/edit.html.erb`
- Test: `test/domain/events/update_details_test.rb`

- [ ] **Step 1: Add a failing test asserting province is no longer editable**

In `test/domain/events/update_details_test.rb`, add after `test_rejects_fields_outside_the_whitelist`:

```ruby
  def test_rejects_province_as_no_longer_editable
    result = Events::UpdateDetails.call(actor: @superadmin, id: "e1",
                                        attrs: { province: "เชียงใหม่" }, repo: @repo, audit: @audit)
    assert result.failure?
    assert_equal "กรุงเทพมหานคร", @repo.find("e1").province
    assert_empty @audit_entries
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/domain/events/update_details_test.rb`
Expected: FAIL — `:province` is still in `EDITABLE`, so the update succeeds instead of being rejected.

- [ ] **Step 3: Remove `:province` from the editable whitelist**

In `app/domain/events/update_details.rb`, change the `EDITABLE` constant:

```ruby
    EDITABLE = [ :name_thai, :name_eng, :area_name ].freeze
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/domain/events/update_details_test.rb`
Expected: PASS.

- [ ] **Step 5: Remove `:province` from permitted params and the edit form**

In `app/controllers/events_controller.rb`, change `update_params`:

```ruby
    def update_params = params.require(:event).permit(:name_thai, :name_eng, :area_name)
```

In `app/views/events/edit.html.erb`, delete the entire province `<div>` block:

```erb
    <div>
      <%= f.label :province, "จังหวัด", class: "mb-1 block font-medium text-ink" %>
      <%= f.text_field :province, value: @event.province, maxlength: 255, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
    </div>
```

- [ ] **Step 6: Run event tests to verify nothing else broke**

Run: `bin/rails test test/domain/events/update_details_test.rb test/controllers/events_controller_test.rb && bin/rails test:system TEST=test/system/events_test.rb`
Expected: PASS (the edit system test edits name/area, not province).

- [ ] **Step 7: Commit**

```bash
git add app/domain/events/update_details.rb app/controllers/events_controller.rb app/views/events/edit.html.erb test/domain/events/update_details_test.rb
git commit -m "feat: remove province from event edit (no longer editable)"
```

---

## Change 3 — App User quota: first-time package flag + total credit column

### Task 4: Domain — flip is_package_user on the first quota adjustment

**Files:**
- Modify: `app/domain/app_users/adjust_quota.rb`
- Modify: `app/adapters/persistence/ar_app_user_repository.rb`
- Modify: `app/domain/ports/app_user_repository.rb` (doc comment)
- Test: `test/domain/app_users/manage_app_users_test.rb`

- [ ] **Step 1: Extend the fake repo + add failing tests**

In `test/domain/app_users/manage_app_users_test.rb`:

Add `is_package_user` to the `FakeAppUser` struct definition:

```ruby
FakeAppUser = Struct.new(:id, :email, :display_name, :role, :event_quota, :is_package_user, :updated_by,
                         keyword_init: true)
```

Update `update_quota` in `FakeAppUserRepo` to honor the new `mark_package:` keyword:

```ruby
  def update_quota(id, quota:, updated_by:, mark_package: false)
    row = find(id)
    row.event_quota = quota
    row.is_package_user = true if mark_package
    row.updated_by = updated_by
    row
  end
```

In `setup`, give the seeded user an explicit `is_package_user: false`:

```ruby
    @repo = FakeAppUserRepo.new(
      "u1" => FakeAppUser.new(id: "u1", email: "u@x.com", role: "user", event_quota: 2, is_package_user: false)
    )
```

Add these tests after `test_adjust_quota_audits_diff`:

```ruby
  def test_first_quota_adjustment_flags_package_user_and_audits_it
    result = AppUsers::AdjustQuota.call(actor: @actor, id: "u1", quota: "5",
                                        repo: @repo, audit: @audit)
    assert result.success?
    assert_equal true, @repo.find("u1").is_package_user
    assert_equal({ "event_quota" => { "from" => 2, "to" => 5 },
                   "is_package_user" => { "from" => false, "to" => true } },
                 @audit_entries.last[:changes])
  end

  def test_subsequent_quota_adjustment_does_not_reflag_or_reaudit_package
    @repo.find("u1").is_package_user = true
    result = AppUsers::AdjustQuota.call(actor: @actor, id: "u1", quota: "7",
                                        repo: @repo, audit: @audit)
    assert result.success?
    assert_equal true, @repo.find("u1").is_package_user
    assert_equal({ "event_quota" => { "from" => 2, "to" => 7 } }, @audit_entries.last[:changes])
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/domain/app_users/manage_app_users_test.rb`
Expected: FAIL — `AdjustQuota` never sets `is_package_user`, so the flag stays false and the audit lacks the `is_package_user` diff.

- [ ] **Step 3: Implement the flag in the use case**

In `app/domain/app_users/adjust_quota.rb`, replace the block from `before = repo.find(id)` through `Result.success(record)` with:

```ruby
      before = repo.find(id)
      from = before.event_quota
      first_package = !before.is_package_user
      record = repo.update_quota(id, quota: quota, mark_package: first_package, updated_by: AuditIdentity.for(actor))
      changes = { "event_quota" => { "from" => from, "to" => quota } }
      changes["is_package_user"] = { "from" => false, "to" => true } if first_package
      audit.record(action: "app_users.quota_adjusted", actor: actor, target: record, changes: changes)
      Result.success(record)
```

- [ ] **Step 4: Implement `mark_package:` in the repo**

In `app/adapters/persistence/ar_app_user_repository.rb`, replace `update_quota` with:

```ruby
    def update_quota(id, quota:, updated_by:, mark_package: false)
      record = find(id)
      attrs = { event_quota: quota, updated_by: updated_by }
      attrs[:is_package_user] = true if mark_package
      record.update!(**attrs)
      record
    end
```

In `app/domain/ports/app_user_repository.rb`, update the doc line for `update_quota`:

```ruby
  #   update_quota(id, quota:, updated_by:, mark_package: false) -> record
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/domain/app_users/manage_app_users_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/domain/app_users/adjust_quota.rb app/adapters/persistence/ar_app_user_repository.rb app/domain/ports/app_user_repository.rb test/domain/app_users/manage_app_users_test.rb
git commit -m "feat: flag is_package_user on first quota adjustment"
```

---

### Task 5: View — total carbon credit column in the app users list

**Files:**
- Modify: `app/controllers/app_users_controller.rb`
- Modify: `app/views/app_users/_list.html.erb`
- Modify: `app/views/app_users/_app_user.html.erb`
- Test: `test/system/app_users_test.rb`

- [ ] **Step 1: Add a failing system test for the credit total column**

In `test/system/app_users_test.rb`, add at the end of the class:

```ruby
  test "lists the total carbon credit summed across offset sources" do
    user = create_core_user!(email: "credit_total@example.com", display_name: "เครดิตรวม")
    s1 = create_core_offset_source!(name: "Solar")
    s2 = create_core_offset_source!(name: "Wind")
    create_core_carbon_credit!(user_id: user.id, amount: 100, source_id: s1.id)
    create_core_carbon_credit!(user_id: user.id, amount: 50, source_id: s2.id)
    login_admin
    visit app_users_path
    within "##{dom_id(user)}" do
      assert_text "150"
    end
  end

  test "shows a dash when a user has no carbon credits" do
    user = create_core_user!(email: "no_credit@example.com", display_name: "ไม่มีเครดิต")
    login_admin
    visit app_users_path
    within "##{dom_id(user)}" do
      assert_text "—"
    end
  end
```

- [ ] **Step 2: Run the system test to verify it fails**

Run: `bin/rails test:system TEST=test/system/app_users_test.rb`
Expected: FAIL — there is no credit total cell yet, so "150"/"—" is not present in the row.

- [ ] **Step 3: Build the grouped credit-total aggregate in the controller**

The `_app_user` partial is re-rendered both by `index` and by `update.turbo_stream.erb` (after an edit). So `@credit_totals` must be set on **both** paths, via a shared helper, to avoid a `NoMethodError` on `nil` in the turbo-stream re-render.

In `app/controllers/app_users_controller.rb`:

In `index`, after the `@page = page` line add:

```ruby
      @credit_totals = credit_totals_for(@app_users.map(&:id))
```

In `update`, inside the `if errors.empty?` branch, immediately after `@app_user = repo.find(params[:id])` (the line before `respond_to`), add:

```ruby
        @credit_totals = credit_totals_for([ @app_user.id ])
```

Add this private helper (e.g. right after the `update_params` definition):

```ruby
    def credit_totals_for(ids)
      Core::CarbonCredit.kept.where(user_id: ids).group(:user_id).sum(:carbon_credit)
    end
```

(`group(:user_id).sum` returns a Hash with no entry for users that have no kept credits, so they fall through to "—".)

- [ ] **Step 4: Add the column header and cell**

In `app/views/app_users/_list.html.erb`, add a header `<th>` after the `โควต้าอีเว้นท์` header:

```erb
        <th class="px-4 py-3">เครดิตรวม</th>
```

In `app/views/app_users/_app_user.html.erb`, add a `<td>` after the `event_quota` cell. Use the safe-navigation `dig` so any future render without `@credit_totals` degrades to "—" instead of raising:

```erb
  <td class="px-4 py-3"><%= @credit_totals&.dig(app_user.id) || "—" %></td>
```

- [ ] **Step 5: Run the system test to verify it passes**

Run: `bin/rails test:system TEST=test/system/app_users_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/app_users_controller.rb app/views/app_users/_list.html.erb app/views/app_users/_app_user.html.erb test/system/app_users_test.rb
git commit -m "feat: show total carbon credit column in app users list"
```

---

## Final Verification Gate

- [ ] **Run the full suite + linters**

Run: `bin/rails test && bin/rails test:system && bundle exec rubocop && bundle exec brakeman -q`
Expected: all green, no rubocop offenses, no brakeman warnings.

- [ ] **Re-index the graph** (per project CLAUDE.md, mode `fast`) for `carbonmice-admin` so graph-first discovery reflects the new code.
