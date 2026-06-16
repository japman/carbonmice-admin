# Hotwire Rollout (remaining 8 resources) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Roll the approved emission-factors Hotwire pattern out to the remaining admin resources — live-filter frames, modal new/edit, and Turbo-Stream writes — so the whole admin UI updates in place without full-page reloads, while keeping HTML redirect fallbacks (progressive enhancement) and leaving the domain/Go/schema untouched.

**Architecture:** Web layer only. Reuse the shared infrastructure already on `main` (Stimulus `modal`/`toast`/`filter` controllers, the global custom confirm, the layout's `<turbo-frame id="modal">` + `#toast_container`, and `shared/_modal` / `shared/_toast`). Per resource: extract a row partial + (where a list is filterable) a `_list` Turbo Frame, turn new/edit into modal frames sharing one `_form`, and make create/update/destroy `respond_to` with Turbo Streams + an HTML redirect fallback. No `app/domain/**`, Go, DB schema, or migration changes. Auth controllers (`sessions`, `passwords`) stay untouched.

**Tech Stack:** Rails 8.1, Ruby 4.0.0 (run everything via `mise exec ruby@4.0.0 --`), Hotwire (turbo-rails, stimulus-rails) over importmap, Tailwind, Capybara + Selenium headless Chrome for system tests.

---

## The reference pattern (already on `main`, study it first)

The **emission_factors** pilot is the canonical template. Before each task, read these committed files and mirror them:

- Row partial: `app/views/emission_factors/_emission_factor.html.erb` — `<tr id="<%= dom_id(record) %>">`, `can?(...)`-gated edit link with `data: { turbo_frame: "modal" }` + delete `button_to` with `data: { turbo_confirm: ... }`.
- List frame: `app/views/emission_factors/_list.html.erb` — `turbo_frame_tag "ef_list", data: { turbo_action: "advance" }` wrapping the table (tbody `id="ef_rows"`) + pagination, body rendered via **`render partial: "emission_factor", collection: @factors`**.
- Shared form: `app/views/emission_factors/_form.html.erb` — renders `flash.now[:alert]` inline, `form_with url:/method:/scope:`, `new_record` branching.
- Index: `app/views/emission_factors/index.html.erb` — "add" link `data: { turbo_frame: "modal" }`, filter `form_with method: :get, data: { controller: "filter", turbo_frame: "<list>" }`, search `data: { action: "input->filter#submit" }`, select `data: { action: "change->filter#submitNow" }`, `render "list"`.
- Modal wrappers: `app/views/emission_factors/new.html.erb` / `edit.html.erb` — `render "shared/modal", title: ... do render "form", ... end`.
- Streams: `app/views/emission_factors/{create,update,destroy}.turbo_stream.erb` — `prepend`/`replace`/`remove` + `turbo_stream.update "modal", ""` + `turbo_stream.append "toast_container"` rendering `shared/toast`.
- Controller: `app/controllers/emission_factors_controller.rb` — success branch sets `@record = result.value` then `respond_to do |format| format.turbo_stream { flash.now[:notice] = "…" }; format.html { redirect_to …, notice: "…" } end`; error branch keeps `render :new/:edit, status: :unprocessable_entity` + `flash.now[:alert]`.
- Tests: `test/controllers/emission_factors_controller_test.rb` (turbo_stream cases asserting `text/vnd.turbo-stream.html` + stream actions + toast text, plus HTML-fallback redirect cases) and `test/system/emission_factors_test.rb` (`driven_by :selenium, using: :headless_chrome, screen_size: [1400, 900]`, `login_admin` helper).

## Standing rules (apply in EVERY task)

1. **Namespaced models need an explicit collection render.** For any `Core::*` model, `render @collection` resolves to `core/<plural>/_<singular>` and misses our partial. Always use `render partial: "<singular>", collection: @collection`. (`AdminUser` is NOT namespaced, but use the explicit form anyway for consistency.)
2. **`dom_id`** in row partials: `<tr id="<%= dom_id(record) %>">`. In controller tests target rows with `ActionView::RecordIdentifier.dom_id(record)` — never hardcode the prefix.
3. **Error branch must 422-render, not redirect.** For the modal to show inline errors, every create/update error branch must `render :new`/`:edit, status: :unprocessable_entity` with `flash.now[:alert] = result.error` and an object for the form to repopulate. Resources that currently `redirect_to` on error (categories, app_users, events, pricing_tiers, admin_users) MUST be changed; resources that already 422-render (carbon_offset_sources, carbon_credits) keep their error branch.
4. **Success branch uses `respond_to`** with `format.turbo_stream { flash.now[:notice] = "…" }` + `format.html { redirect_to …, notice: "…" }`. Set the record for the stream template: prefer `@record = result.value`; **if a use case's `Result.success` does not carry the AR record** (verify with `get_code_snippet`), reload via `@record = repo.find(params[:id])` after success.
5. **Progressive enhancement:** keep every existing HTML-format controller test green — the `format.html` redirect must behave exactly as before. Add turbo_stream cases; do not delete HTML cases.
6. **Tests per task (TDD — write them first, watch them fail, then implement):**
   - Controller: a turbo_stream case per mutation asserting `assert_equal "text/vnd.turbo-stream.html", response.media_type`, the expected `turbo-stream action="…" target="…"`, and `assert_match "<toast text>", response.body`; PLUS keep/extend HTML-fallback redirect cases.
   - System (selenium): the live filter (where applicable), modal open + create/edit reflected in the list + toast, delete via the styled confirm (click "ยืนยัน", not `accept_confirm`), and a server-rejected submit that keeps the modal open showing `.text-danger` (use a real server rejection — e.g. duplicate/blank that the domain rejects — not one HTML5 blocks client-side; scope the "still open" proof to the error text, since the layout keeps a second empty `turbo-frame#modal` load target).
7. **Commands:** prefix everything with `mise exec ruby@4.0.0 --`. **Commit after each task**; messages end with the trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. The implementer runs the narrow target tests per task; the full gate runs per batch.
8. **Re-index** the codebase graph (`index_repository`, mode `fast`, project `…-carbonmice-admin`) before starting and after each batch.

## Batching (per repo speed policy)

- **Batch 1 (Task 1, 2):** carbon_offset_sources, carbon_credits — closest to the pilot (already 422-render).
- **Batch 2 (Task 3, 4, 5):** categories, app_users, admin_users — edit-centric, need error-branch→422 changes.
- **Batch 3 (Task 6, 7, 8):** events, pricing_tiers, audit_logs — bespoke.

Reviews per batch in parallel: spec reviewer (model: haiku) + code-quality reviewer (model: sonnet). Full gate (`bin/rails test` + `test:system` + `rubocop` + `brakeman -q`) at the end of each batch and in final verification.

---

# Batch 1

## Task 1: carbon_offset_sources — modal new/edit + Turbo-Stream writes (no live filter)

Full CRUD over a **small, unfiltered** list (`repo.list` = all kept, ordered by `name`). No pagination/search → **no live filter**; the frame exists only so create can prepend. Model `Core::CarbonOffsetSource`. The controller **already** 422-renders on error (keep it).

**Files:**
- Create: `app/views/carbon_offset_sources/_carbon_offset_source.html.erb`, `_list.html.erb`, `_form.html.erb`, `{create,update,destroy}.turbo_stream.erb`
- Modify: `app/controllers/carbon_offset_sources_controller.rb`, `index.html.erb`, `new.html.erb`, `edit.html.erb`
- Test: `test/controllers/carbon_offset_sources_controller_test.rb`, `test/system/carbon_offset_sources_test.rb`

**Substitutions (vs the pilot):**

| Pilot token | This resource |
|---|---|
| model | `Core::CarbonOffsetSource` |
| frame id / tbody id | `cos_list` / `cos_rows` |
| row partial / local | `_carbon_offset_source` / `carbon_offset_source` |
| collection ivar | `@sources` |
| paths | `carbon_offset_sources_path`, `new_carbon_offset_source_path`, `edit_carbon_offset_source_path(id)`, `carbon_offset_source_path(id)` |
| create toast | `"สร้างแหล่งออฟเซ็ตแล้ว"` |
| update toast | `"บันทึกแล้ว"` |
| destroy toast | `"ลบแหล่งออฟเซ็ตแล้ว (soft delete)"` |
| add-link label | `"เพิ่มแหล่ง"` |

**Row partial** (`_carbon_offset_source.html.erb`, local `carbon_offset_source`): `<tr id="<%= dom_id(carbon_offset_source) %>" class="border-b border-gray-100">` with cells: `carbon_offset_source.name_th.presence || "—"`; `<%= carbon_offset_source.name %> 🔒` (font-mono text-xs); actions cell gated by `can?(:manage_master_data)` — edit `link_to "แก้ชื่อไทย", edit_carbon_offset_source_path(carbon_offset_source.id), data: { turbo_frame: "modal" }, class: "text-primary"` + `button_to "ลบ", carbon_offset_source_path(carbon_offset_source.id), method: :delete, form: { data: { turbo_confirm: "ลบแหล่ง #{carbon_offset_source.name}? (soft delete)" }, class: "inline" }, class: "ml-3 cursor-pointer text-danger"`.

**List partial** (`_list.html.erb`): `turbo_frame_tag "cos_list" do` wrapping the existing table; thead unchanged (ชื่อ (ไทย) | ชื่อ (ระบบหลัก) | ⌀); `<tbody id="cos_rows"><%= render partial: "carbon_offset_source", collection: @sources %></tbody>`. No pagination.

**`index.html.erb`:** keep the header + warning banner; change the "เพิ่มแหล่ง" link to add `data: { turbo_frame: "modal" }`; replace the inline `<table>…</table>` with `<%= render "list" %>`.

**`_form.html.erb`** (locals `url`, `method`, `source`, `new_record`): inline `flash.now[:alert]` block (copy from the pilot). `form_with url: url, method: method, scope: :carbon_offset_source`. Field `name`: when `new_record`, `f.text_field :name, value: source&.name, required: true, maxlength: 255`; else `f.text_field :name, value: source.name, disabled: true` (font-mono, gray) with a 🔒 label note "(ระบบหลักใช้ชื่อนี้ — แก้ไขไม่ได้)". Field `name_th`: `f.text_field :name_th, value: source&.name_th, maxlength: 255` (always editable). Submit `new_record ? "เพิ่มแหล่ง" : "บันทึก"`.

**`new.html.erb`:**
```erb
<%= render "shared/modal", title: "เพิ่มแหล่งออฟเซ็ต" do %>
  <%= render "form", url: carbon_offset_sources_path, method: :post, source: @source, new_record: true %>
<% end %>
```
(`new` action sets nothing today — add `@source = nil` is unnecessary since `source&.` is nil-safe; the create error branch already builds `@source` via `Data.define(:name, :name_th)`.)

**`edit.html.erb`:**
```erb
<%= render "shared/modal", title: "แก้ชื่อไทย: #{@source.name}" do %>
  <%= render "form", url: carbon_offset_source_path(@source.id), method: :patch, source: @source, new_record: false %>
<% end %>
```

**Controller** — only the **success** branches change (error branches already 422-render). `create`: on success `@source = result.value` then `respond_to` (turbo_stream sets `flash.now[:notice] = "สร้างแหล่งออฟเซ็ตแล้ว"`; html `redirect_to carbon_offset_sources_path, notice: "สร้างแหล่งออฟเซ็ตแล้ว"`). `update`: `@source = result.value` + respond_to (toast `"บันทึกแล้ว"`). `destroy` success: `@source = result.value` + respond_to (toast `"ลบแหล่งออฟเซ็ตแล้ว (soft delete)"`); keep the error redirect. **Verify** with `get_code_snippet` that `CreateCarbonOffsetSource`/`RenameCarbonOffsetSource`/`DeleteCarbonOffsetSource` return the AR record in `Result.success`; if not, reload `@source = repo.find(params[:id])` (create: use the returned record).

**Streams:** `create.turbo_stream.erb` → `turbo_stream.prepend "cos_rows"` (render row) + `turbo_stream.update "modal", ""` + `turbo_stream.append "toast_container"` (render `shared/toast`, kind: :notice, message: `flash.now[:notice]`). `update` → `turbo_stream.replace dom_id(@source)` + update modal + toast. `destroy` → `turbo_stream.remove dom_id(@source)` + toast.

**Tests:** controller — `create`/`update`/`destroy` as `:turbo_stream` assert media_type + `prepend target="cos_rows"` / `replace target="<dom_id>"` / `remove target="<dom_id>"` + toast text; keep HTML redirect cases (incl. the existing duplicate-name 422 case). System (`test/system/carbon_offset_sources_test.rb`, selenium): create via modal shows the row + toast; edit Thai name updates the row + toast; delete via styled confirm removes the row + toast; **server-rejected create** (duplicate `name`) keeps the modal open showing `.text-danger`.

- [ ] Step 1: write the failing controller turbo_stream tests; run → fail.
- [ ] Step 2: write the failing system tests; run → fail.
- [ ] Step 3: create row + list partials; update `index.html.erb`.
- [ ] Step 4: create `_form` + modal `new`/`edit`.
- [ ] Step 5: add `respond_to` to the controller success branches; create the three stream templates.
- [ ] Step 6: run controller + system tests → pass; run the existing file's HTML tests → pass.
- [ ] Step 7: commit `feat(hotwire): carbon offset sources modal + Turbo Streams`.

## Task 2: carbon_credits — live filter (user select) + modal new/edit + Turbo-Stream writes

Full CRUD, **paginated + filter by user (select)**, `order(created_at: :desc)`. Model `Core::CarbonCredit`. Controller **already** 422-renders on error. Because the list is newest-first, **prepend lands the new row in its correct position** (note this in the create stream — no accepted-trade-off caveat needed).

**Files:**
- Create: `app/views/carbon_credits/_carbon_credit.html.erb`, `_list.html.erb`, `_form.html.erb`, `{create,update,destroy}.turbo_stream.erb`
- Modify: `app/controllers/carbon_credits_controller.rb`, `index.html.erb`, `new.html.erb`, `edit.html.erb`
- Test: `test/controllers/carbon_credits_controller_test.rb`, `test/system/carbon_credits_test.rb`

**Substitutions:** frame/tbody `cc_list`/`cc_rows`; row partial/local `_carbon_credit`/`carbon_credit`; ivar `@credits`; paths `carbon_credits_path` etc.; toasts create `"เพิ่ม carbon credit แล้ว"`, update `"บันทึกแล้ว"`, destroy `"ลบ carbon credit แล้ว (soft delete)"`; add-link `"เพิ่ม carbon credit"`.

**Row partial** (local `carbon_credit`): `<tr id="<%= dom_id(carbon_credit) %>" …>` with the 7 existing cells (user email, amount, source `name_th||name` or "—", created date, updated date or "—", `updated_by` or "—", actions). Actions gated `can?(:manage_master_data)`: edit `link_to "แก้ไข", edit_carbon_credit_path(carbon_credit.id), data: { turbo_frame: "modal" }` + delete `button_to "ลบ", carbon_credit_path(carbon_credit.id), method: :delete, form: { data: { turbo_confirm: "ลบ carbon credit #{carbon_credit.carbon_credit}? (soft delete)" }, class: "inline" }, class: "ml-3 cursor-pointer text-danger"`.

**List partial:** `turbo_frame_tag "cc_list", data: { turbo_action: "advance" } do` wrapping the table (thead unchanged) with `<tbody id="cc_rows"><%= render partial: "carbon_credit", collection: @credits %></tbody>` + the existing pagination block (keep `user_id:` + `page:` in the links).

**`index.html.erb`:** "เพิ่ม carbon credit" link gets `data: { turbo_frame: "modal" }`. Change the filter `form_with` to `data: { controller: "filter", turbo_frame: "cc_list" }`; the user select gets `data: { action: "change->filter#submitNow" }`; keep the "กรอง" submit as the no-JS fallback. Replace the inline table+pagination with `<%= render "list" %>`.

**`_form.html.erb`** (locals `url`, `method`, `credit`, `new_record`; uses `@users`/`@sources`): inline `flash.now[:alert]`. `form_with … scope: :carbon_credit`. When `new_record`: `user_id` select (required) `[["เลือกผู้ใช้", ""]] + @users.map { |u| [u.email, u.id] }`, selected `credit&.user_id`. When edit: show the user **read-only** (`<div>… @credit.user&.email …</div>`, no input — `user_id` is immutable). Always: `carbon_credit` `f.number_field :carbon_credit, value: credit&.carbon_credit, required: true, min: 1, step: 1`; `carbon_offset_source_id` select (optional) `[["— ไม่ระบุ —", ""]] + @sources.map { |s| [(s.name_th.presence || s.name), s.id] }`, selected `credit&.carbon_offset_source_id`. Submit `new_record ? "เพิ่ม" : "บันทึก"`.

**`new.html.erb` / `edit.html.erb`:** modal wrappers — new title `"เพิ่ม carbon credit"`, edit title `"แก้ไข carbon credit"`. (`new` loads `@users`+`@sources`; `edit` loads `@sources`; the edit form shows the user read-only so `@users` isn't needed there.)

**Controller:** success branches only. `create`: `@credit = result.value` + respond_to (toast `"เพิ่ม carbon credit แล้ว"`). `update`: `@credit = result.value` + respond_to (toast `"บันทึกแล้ว"`). `destroy`: `@credit = result.value` + respond_to (toast `"ลบ carbon credit แล้ว (soft delete)"`). Verify the use cases return the record (else reload). Error branches unchanged (they already 422-render with `@users`/`@sources` reloaded).

**Streams:** create `prepend "cc_rows"` + update modal + toast; update `replace dom_id(@credit)` + update modal + toast; destroy `remove dom_id(@credit)` + toast.

**Tests:** controller turbo_stream (prepend/replace/remove + toast) + HTML redirects. System (selenium): seed two users + credits; filtering by a user via the select re-renders `#cc_list` without reload and advances the URL (`user_id=`); create via modal prepends the row + toast; edit updates the row + toast; delete via styled confirm; server-rejected create (e.g. blank amount / amount `0` which the domain rejects) keeps the modal open with `.text-danger`.

- [ ] Steps mirror Task 1 (tests first → partials/index → form/modals → controller+streams → green → commit `feat(hotwire): carbon credits live filter + modal + Turbo Streams`).

**End of Batch 1:** full gate (`bin/rails test`, `test:system`, `rubocop`, `brakeman -q`) → all clean; re-index graph (fast).

---

# Batch 2

## Task 3: categories — modal edit (rename) + Turbo-Stream replace (no filter; units table untouched)

Edit-only rename of `name_thai`. The index has **two tables**: หมวดคาร์บอน (editable) and หน่วย (read-only). **Only the categories table** gets a row partial + modal edit + update stream; the units table stays exactly as-is. Tiny list → no filter, no list frame needed (a `turbo_stream.replace` targets the row by `dom_id` globally). Model `Core::CarbonCategory`.

**Files:**
- Create: `app/views/categories/_category.html.erb`, `_form.html.erb`, `update.turbo_stream.erb`
- Modify: `app/controllers/categories_controller.rb`, `index.html.erb`, `edit.html.erb`
- Test: `test/controllers/categories_controller_test.rb`, `test/system/categories_test.rb`

**Row partial** (`_category.html.erb`, local `category`): `<tr id="<%= dom_id(category) %>" class="border-b border-gray-100">` with cells `category.name_thai` (font-medium); `<%= category.name_eng %> 🔒` (font-mono text-xs); actions cell gated `can?(:manage_master_data)`: `link_to "แก้ชื่อไทย", edit_category_path(category.id), data: { turbo_frame: "modal" }, class: "text-primary"` (no delete).

**`index.html.erb`:** in the หมวดคาร์บอน table, replace the inline `@categories.each` body with `<tbody><%= render partial: "category", collection: @categories %></tbody>`. Leave the หน่วย table unchanged.

**`edit.html.erb`:**
```erb
<%= render "shared/modal", title: "แก้ชื่อหมวด: #{@category.name_eng}" do %>
  <%= render "form", category: @category %>
<% end %>
```

**`_form.html.erb`** (local `category`): inline `flash.now[:alert]`; `form_with url: category_path(category.id), method: :patch, scope: :category`; `f.text_field :name_thai, value: category.name_thai, required: true, maxlength: 255`; submit "บันทึก".

**Controller `update`** — change BOTH branches:
```ruby
  def update
    result = MasterData::RenameCategory.call(actor: current_admin, id: params[:id],
                                             name_thai: params.require(:category).permit(:name_thai)[:name_thai],
                                             repo: repo, audit: audit)
    if result.success?
      @category = repo.find(params[:id]) # reload for the row render (RenameCategory may not carry the record)
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = "บันทึกชื่อหมวดแล้ว" }
        format.html { redirect_to categories_path, notice: "บันทึกชื่อหมวดแล้ว" }
      end
    else
      @category = repo.find(params[:id])
      @category.assign_attributes(name_thai: params.require(:category).permit(:name_thai)[:name_thai])
      flash.now[:alert] = result.error
      render :edit, status: :unprocessable_entity
    end
  rescue Ports::NotFound
    redirect_to categories_path, alert: "ไม่พบหมวดหมู่"
  end
```
(If `get_code_snippet` shows `RenameCategory` returns the record, use `@category = result.value` instead of the reload.)

**`update.turbo_stream.erb`:** `turbo_stream.replace dom_id(@category)` (render `_category`) + `turbo_stream.update "modal", ""` + toast `"บันทึกชื่อหมวดแล้ว"`.

**Tests:** controller — `patch` as `:turbo_stream` asserts media_type + `replace target="<dom_id>"` + toast; an HTML `patch` still redirects to `categories_path`; an invalid (blank `name_thai`) `:turbo_stream`/HTML keeps/renders 422 (note: the domain must reject blank — verify; if blank is allowed, use a different rejection or assert the validation the use case enforces). System: edit a category via the modal updates its row in place + toast; blank name keeps the modal open with `.text-danger`.

- [ ] tests-first → partial/index → form/modal → controller both branches + stream → green → commit `feat(hotwire): categories modal rename + Turbo Stream`.

## Task 4: app_users — live filter (search) + modal edit + Turbo-Stream replace (special multi-use-case update)

Edit-only, **paginated + search text** → live filter. The `update` runs up to **two independent use cases** (`AppUsers::ChangeRole`, `AppUsers::AdjustQuota`) and collects errors. Model `Core::User`.

**Files:**
- Create: `app/views/app_users/_app_user.html.erb`, `_list.html.erb`, `_form.html.erb`, `update.turbo_stream.erb`
- Modify: `app/controllers/app_users_controller.rb`, `index.html.erb`, `edit.html.erb`
- Test: `test/controllers/app_users_controller_test.rb`, `test/system/app_users_test.rb`

**Row partial** (local `app_user`): `<tr id="<%= dom_id(app_user) %>" …>` cells `app_user.display_name`, `app_user.email`, `app_user.role`, `app_user.event_quota`, `app_user.is_package_user ? "ใช่" : "—"`, actions gated `can?(:manage_app_users)`: `link_to "แก้ไข", edit_app_user_path(app_user.id), data: { turbo_frame: "modal" }`.

**List partial:** `turbo_frame_tag "au_list", data: { turbo_action: "advance" } do` wrapping the table (thead unchanged) `<tbody id="au_rows"><%= render partial: "app_user", collection: @app_users %></tbody>` + the existing pagination (keep `search:`+`page:`).

**`index.html.erb`:** change the filter `form_with` to `data: { controller: "filter", turbo_frame: "au_list" }`; the search field gets `data: { action: "input->filter#submit" }`; keep the "ค้นหา" submit as fallback; replace the inline table+pagination with `<%= render "list" %>`.

**`edit.html.erb`:**
```erb
<%= render "shared/modal", title: "แก้ไขผู้ใช้งาน: #{@app_user.email}" do %>
  <%= render "form", app_user: @app_user %>
<% end %>
```

**`_form.html.erb`** (local `app_user`): inline `flash.now[:alert]`; `form_with url: app_user_path(app_user.id), method: :patch, scope: :app_user`; role select `(AppUsers::ChangeRole::ROLES | [app_user.role]).map { |r| [r, r] }`, selected `app_user.role`; `f.number_field :event_quota, value: app_user.event_quota, min: 0`; submit "บันทึก".

**Controller `update`** — keep the two-use-case logic; change the tail:
```ruby
    if errors.empty?
      @app_user = repo.find(params[:id]) # reload to render the updated row + form
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = "บันทึกการแก้ไขแล้ว" }
        format.html { redirect_to app_users_path, notice: "บันทึกการแก้ไขแล้ว" }
      end
    else
      @app_user = repo.find(params[:id])
      flash.now[:alert] = errors.join(" / ")
      render :edit, status: :unprocessable_entity
    end
```
(Leave the `rescue Ports::NotFound` redirect.)

**`update.turbo_stream.erb`:** `replace dom_id(@app_user)` + update modal + toast `"บันทึกการแก้ไขแล้ว"`.

**Tests:** controller — `patch` as `:turbo_stream` with a real role/quota change asserts media_type + `replace target="<dom_id>"` + toast; HTML `patch` still redirects; an error case (e.g. invalid role or negative quota the use case rejects) renders 422 with the error. System: live filter by search re-renders `#au_list` + URL `search=`; editing role/quota via the modal updates the row + toast; an invalid submit keeps the modal open with `.text-danger`.

- [ ] tests-first → partials/index → form/modal → controller tail + stream → green → commit `feat(hotwire): app users live filter + modal edit + Turbo Stream`.

## Task 5: admin_users — live filter (search, new backend) + modal new/edit + create/update Streams (no destroy)

Create + edit, **no destroy**. Currently **no search/pagination** — add a small `search:` to the repo so the chosen live filter has a backend. Manages `AdminUser` (the admin's own table — NOT the `sessions`/`passwords` auth controllers; those stay untouched). Both branches currently redirect on error → change to 422-render.

**Files:**
- Create: `app/views/admin_users/_admin_user.html.erb`, `_list.html.erb`, `_form.html.erb`, `{create,update}.turbo_stream.erb`
- Modify: `app/controllers/admin_users_controller.rb`, `app/adapters/persistence/ar_admin_user_repository.rb`, `index.html.erb`, `new.html.erb`, `edit.html.erb`
- Test: `test/controllers/admin_users_controller_test.rb`, `test/system/admin_users_test.rb`

**Repo:** add `def list(search: nil)` that returns the `all_ordered` scope filtered by name/email when `search` is present (case-insensitive `ILIKE "%…%"` on `name` and `email_address`, sanitized via `ActiveRecord::Base.sanitize_sql_like`). Keep `all_ordered` for any other caller. Verify the current implementation with `get_code_snippet` and mirror its style.

**Controller `index`:** `@admin_users = repo.list(search: params[:search].presence)`.

**Row partial** (local `admin_user`): `<tr id="<%= dom_id(admin_user) %>" …>` cells `admin_user.name`, `admin_user.email_address`, `role_label(admin_user.role)`, the active/inactive badge (copy the existing markup), actions: `link_to "แก้ไข", edit_admin_user_path(admin_user), data: { turbo_frame: "modal" }` (the whole controller is gated `manage_admin_users`).

**List partial:** `turbo_frame_tag "adm_list", data: { turbo_action: "advance" } do` wrapping the table `<tbody id="adm_rows"><%= render partial: "admin_user", collection: @admin_users %></tbody>` (no pagination — small list).

**`index.html.erb`:** "เพิ่มผู้ดูแล" link gets `data: { turbo_frame: "modal" }`; add a filter form above the table: `form_with url: admin_users_path, method: :get, data: { controller: "filter", turbo_frame: "adm_list" }` with a `search` text field `data: { action: "input->filter#submit" }` + a "ค้นหา" submit fallback; replace the inline table with `<%= render "list" %>`.

**`_form.html.erb`** (locals `admin_user`, `new_record`): inline `flash.now[:alert]`; `form_with url: (new_record ? admin_users_path : admin_user_path(admin_user.id)), method: (new_record ? :post : :patch), scope: :admin_user`. Always: `name` text (required). When `new_record`: `email_address` email (required) + `password` password (required, minlength 12) + role select `[["Viewer","viewer"],["Admin","admin"],["Superadmin","superadmin"]]`. When edit: show email read-only (`<div>… admin_user.email_address …</div>`), role select selected `admin_user.role`, and an `active` checkbox `f.check_box :active` (matches `update_params` = name, role, active). Submit `new_record ? "สร้างบัญชี" : "บันทึก"`.

**`new.html.erb` / `edit.html.erb`:** modal wrappers — new title `"เพิ่มผู้ดูแล"` (`render "form", admin_user: @admin_user, new_record: true`); edit title `"แก้ไขผู้ดูแล: #{@admin_user.name}"` (`new_record: false`). `new` action: set `@admin_user = AdminUser.new` so the form has an object.

**Controller `create`:**
```ruby
    if result.success?
      @admin_user = result.value
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = "สร้างบัญชีผู้ดูแลแล้ว" }
        format.html { redirect_to admin_users_path, notice: "สร้างบัญชีผู้ดูแลแล้ว" }
      end
    else
      @admin_user = AdminUser.new(create_params.except(:password)) # repopulate (password intentionally cleared)
      flash.now[:alert] = result.error
      render :new, status: :unprocessable_entity
    end
```
**Controller `update`:**
```ruby
    if result.success?
      @admin_user = repo.find(params[:id])
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = "บันทึกการแก้ไขแล้ว" }
        format.html { redirect_to admin_users_path, notice: "บันทึกการแก้ไขแล้ว" }
      end
    else
      @admin_user = repo.find(params[:id])
      @admin_user.assign_attributes(update_params.to_h)
      flash.now[:alert] = result.error
      render :edit, status: :unprocessable_entity
    end
```
(Verify `CreateAdmin` returns the record; if not, reload by the created email. `AdminUser.new(...)` for the create-error form is fine — it's only for re-rendering, not saved.)

**Streams:** `create.turbo_stream.erb` → `prepend "adm_rows"` + update modal + toast `"สร้างบัญชีผู้ดูแลแล้ว"`. `update.turbo_stream.erb` → `replace dom_id(@admin_user)` + update modal + toast `"บันทึกการแก้ไขแล้ว"`.

**Tests:** controller — `create`/`update` as `:turbo_stream` assert media_type + `prepend target="adm_rows"` / `replace target="<dom_id>"` + toast; HTML `create`/`update` still redirect; a create error (e.g. duplicate email / short password the use case rejects) renders `:new` 422; an update error renders `:edit` 422; add a `list(search:)` repo test. System: live filter by name/email; create an admin via the modal prepends the row + toast; edit (role/active) updates the row + toast; server-rejected create keeps the modal open with `.text-danger`.

- [ ] tests-first → repo `list(search:)` → partials/index → form/modals → controller both actions + streams → green → commit `feat(hotwire): admin users search + modal new/edit + Turbo Streams`.

**End of Batch 2:** full gate → clean; re-index graph (fast).

---

# Batch 3 (bespoke)

## Task 6: events — live filter (search + status) + modal edit from the show page (status flow untouched)

Events have a **list → show → edit** flow. The index rows link to the **show** page (no row-level edit/delete). The **status change** (danger zone, shipped in feature 1) stays exactly as-is (full-page redirect). Two Hotwire changes: (a) **live filter** on the index; (b) **edit-in-a-modal** opened from the show page, whose save updates the show page's detail block via a Turbo Stream. Model `Core::Event`.

**Files:**
- Create: `app/views/events/_list.html.erb`, `app/views/events/_details.html.erb`, `app/views/events/update.turbo_stream.erb`
- Modify: `app/controllers/events_controller.rb`, `index.html.erb`, `show.html.erb`, `edit.html.erb`
- Test: `test/controllers/events_controller_test.rb`, `test/system/events_test.rb` (extend if present; the feature-1 system test already seeds statuses)

**(a) Live filter (index):** wrap the table + pagination in `turbo_frame_tag "ev_list", data: { turbo_action: "advance" } do … end` (extract into `_list.html.erb`; rows can stay inline — there are no per-row stream updates, so **no row partial is required**). Change the filter `form_with` to `data: { controller: "filter", turbo_frame: "ev_list" }`; search field `data: { action: "input->filter#submit" }`; status select `data: { action: "change->filter#submitNow" }`; keep "กรอง" fallback. `index.html.erb` ends with `<%= render "list" %>`. **No controller change** for filtering (frame re-renders `index`).

**(b) Edit modal from show:**
- `show.html.erb`: wrap the event's descriptive block (the part edited by `update_params` — ชื่อไทย/อังกฤษ/สถานที่/จังหวัด) in `<div id="event_details"><%= render "details", event: @event %></div>` and add an "แก้ไขรายละเอียด" `link_to edit_event_path(@event.id), data: { turbo_frame: "modal" }`. The status danger-zone box is **left untouched**.
- `_details.html.erb`: the read-only detail markup moved out of `show.html.erb` (local `event`).
- `edit.html.erb`: wrap the existing form in the modal — `render "shared/modal", title: "แก้ไขอีเว้นท์: #{@event.name_thai.presence || @event.name_eng}" do … end`, and add an inline `flash.now[:alert]` block at the top of the form. (Keep the existing fields/`form_with`.)
- Controller `update`:
```ruby
    if result.success?
      @event = repo.find(params[:id])
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = "บันทึกการแก้ไขแล้ว" }
        format.html { redirect_to event_path(params[:id]), notice: "บันทึกการแก้ไขแล้ว" }
      end
    else
      @event = repo.find(params[:id])
      @event.assign_attributes(update_params.to_h)
      flash.now[:alert] = result.error
      render :edit, status: :unprocessable_entity
    end
```
  (Keep the `rescue Ports::NotFound` redirect. Note: `edit` action uses `load_event` → `@event` is set for the modal.)
- `update.turbo_stream.erb`: `turbo_stream.replace "event_details" do render "details", event: @event end` + `turbo_stream.update "modal", ""` + toast `"บันทึกการแก้ไขแล้ว"`.

**Status:** do **not** modify the `status` action or the danger-zone partial. (If the status form's `data-turbo-confirm` exists it now uses the styled confirm automatically — no change needed.)

**Tests:** controller — `update` as `:turbo_stream` asserts media_type + `replace target="event_details"` + toast; HTML `update` still redirects to `event_path`; an update error renders `:edit` 422; the existing feature-2 audit-IP test on `status` stays green. System: typing in search + choosing a status live-filters `#ev_list` + URL advances; on a show page, "แก้ไขรายละเอียด" opens the modal, saving updates `#event_details` in place + toast + modal closes; an invalid edit keeps the modal open with `.text-danger`. (Seed `event_statuses` as the feature-1 test does.)

- [ ] tests-first → index `_list`+filter wiring → show `_details`+edit link → edit modal → controller update + stream → green → commit `feat(hotwire): events live filter + modal detail edit`.

## Task 7: pricing_tiers — modal edits for event & offset tiers + per-row Turbo-Stream replace (custom routes)

Two edit forms over **custom non-REST routes** (`edit_event`/`update_event`, `edit_offset`/`update_offset`). Edit-only (no create/delete). The index lists event tiers in one table and offset tiers grouped by source. Each tier row gets a `dom_id` so its save replaces just that row. Models: the event-tier and offset-tier records returned by `event_repo`/`offset_repo` (confirm class names via `get_code_snippet`, e.g. `Core::EventPricingTier` / `Core::OffsetPricingTier`).

**Files:**
- Create: `app/views/pricing_tiers/_event_tier.html.erb`, `_offset_tier.html.erb`, `edit_event.html.erb`, `edit_offset.html.erb` (if these templates don't already exist as full pages, otherwise modify), `update_event.turbo_stream.erb`, `update_offset.turbo_stream.erb`, and a shared `_event_tier_form.html.erb` / `_offset_tier_form.html.erb`
- Modify: `app/controllers/pricing_tiers_controller.rb`, `index.html.erb`
- Test: `test/controllers/pricing_tiers_controller_test.rb`, `test/system/pricing_tiers_test.rb`

**Index:** give each event-tier row `<tr id="<%= dom_id(tier) %>">` via `render partial: "event_tier", collection: @event_tiers` (verify the index ivar; current controller exposes `@event_tiers` and `@offset_tiers_by_source`), and each offset-tier row `<tr id="<%= dom_id(tier) %>">` via `render partial: "offset_tier", collection: tiers` inside each source group. Each row's "แก้ไข" link points at `edit_event_pricing_tier_path(tier.id)` / `edit_offset_pricing_tier_path(tier.id)` with `data: { turbo_frame: "modal" }`.

**Edit views** (`edit_event.html.erb` / `edit_offset.html.erb`): wrap the tier form in `render "shared/modal", title: "แก้ไขระดับราคา" do render "event_tier_form"/"offset_tier_form", tier: @tier end`. Each `_*_form` has an inline `flash.now[:alert]` and the existing tier fields (`min_participants`/`max_participants`/`price_per_person` for event; `min_emission`/`max_emission`/`price_per_emission` for offset), `form_with url: event_pricing_tier_path(tier.id)/offset_pricing_tier_path(tier.id), method: :patch, scope: :tier`.

**Controller** `update_event` / `update_offset` — change both branches:
```ruby
  def update_event
    result = ActiveRecord::Base.transaction do
      MasterData::UpdateEventPricingTier.call(actor: current_admin, id: params[:id],
                                              attrs: tier_params(:min_participants, :max_participants, :price_per_person),
                                              repo: event_repo, audit: audit)
    end
    if result.success?
      @tier = event_repo.find(params[:id])
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = "บันทึกระดับราคาแล้ว" }
        format.html { redirect_to pricing_tiers_path, notice: "บันทึกระดับราคาแล้ว" }
      end
    else
      @tier = event_repo.find(params[:id])
      flash.now[:alert] = result.error
      render :edit_event, status: :unprocessable_entity
    end
  end
```
(Same shape for `update_offset` with `offset_repo`, `:min_emission/:max_emission/:price_per_emission`, and `render :edit_offset`. Verify the use cases return the record; else the reload above stands.)

**Streams:** `update_event.turbo_stream.erb` → `replace dom_id(@tier)` (render `_event_tier`) + update modal + toast. `update_offset.turbo_stream.erb` → `replace dom_id(@tier)` (render `_offset_tier`) + update modal + toast.

**Tests:** controller — `update_event`/`update_offset` as `:turbo_stream` assert media_type + `replace target="<dom_id>"` + toast; HTML still redirects to `pricing_tiers_path`; an invalid bound (e.g. min > max the use case rejects) renders the matching `:edit_*` 422. System: open an event tier edit modal, save, its row updates in place + toast; same for an offset tier; an invalid submit keeps the modal open with `.text-danger`.

- [ ] tests-first → index row partials → edit modals + forms → controller both updates + streams → green → commit `feat(hotwire): pricing tiers modal edits + Turbo Stream row replace`.

## Task 8: audit_logs — live filter only (no modal/streams, no controller change)

Read-only log with `action_prefix` select + `from`/`to` date filters. Add **only** the live-filter Turbo Frame — no row partial, no modal, no streams, **no controller change** (a frame request re-renders `index`; Turbo extracts the frame, exactly like the pilot's filter dimension).

**Files:**
- Create: `app/views/audit_logs/_list.html.erb`
- Modify: `app/views/audit_logs/index.html.erb`
- Test: `test/system/audit_logs_test.rb`

**`_list.html.erb`:** `turbo_frame_tag "al_list", data: { turbo_action: "advance" } do` wrapping the truncation notice (`@truncated`) + the table (thead + `@entries.each` rows, unchanged markup). 

**`index.html.erb`:** change the filter `form_with` to `data: { controller: "filter", turbo_frame: "al_list" }`; `action_prefix` select `data: { action: "change->filter#submitNow" }`; the `from`/`to` date fields `data: { action: "change->filter#submitNow" }`; keep the "กรอง" submit fallback; replace the truncation-notice+table with `<%= render "list" %>`.

**Tests:** system (selenium): seed a few audit rows across prefixes (reuse the audit factories the feature-2 tests used); choosing a `action_prefix` re-renders `#al_list` without a full reload (asserts a matching row appears, a non-matching one disappears) and the URL advances (`action_prefix=`). No controller test (no controller change).

- [ ] tests-first → `_list` partial → index filter wiring → green → commit `feat(hotwire): audit logs live filter`.

**End of Batch 3:** full gate → clean; re-index graph (fast).

---

## Final verification (after all batches)

- [ ] `mise exec ruby@4.0.0 -- bin/rails test` → 0 failures
- [ ] `mise exec ruby@4.0.0 -- bin/rails test:system` → 0 failures
- [ ] `mise exec ruby@4.0.0 -- bin/rubocop` → 0 offenses
- [ ] `mise exec ruby@4.0.0 -- bundle exec brakeman -q` → 0 warnings
- [ ] Re-index the graph (`index_repository`, mode `fast`) on carbonmice-admin.
- [ ] Manual smoke (docker compose up): for each resource — filter live (where applicable, URL advances, no flash), add/edit in a modal (row appears/updates, toast, modal closes), delete via the styled confirm (where applicable), invalid submit keeps the modal open with the error; confirm a curl/no-JS request still redirects.

## Out of scope

- Any change to `app/domain/**`, the Go backend, the DB schema, or migrations.
- The `sessions`/`passwords` auth controllers.
- The events `status` flow and danger-zone (unchanged) and the categories **units** table (read-only).
- Smart insertion of a created row at its sorted position under an active filter (prepend accepted; carbon_credits is newest-first so prepend is already correct).
- New columns, new search/pagination beyond the minimal `admin_users` name/email search.
