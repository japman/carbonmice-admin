# Hotwire Pilot (Emission Factors) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the emission-factors admin screen dynamic (live filter, modal new/edit, Turbo-Stream list/flash updates, Stimulus sprinkles) using shared infrastructure that the other resources will later reuse.

**Architecture:** Web layer only. Add three Stimulus controllers (modal/toast/filter) + a global custom-confirm, a persistent modal Turbo Frame and a toast container in the layout, and shared `_modal`/`_toast` partials. Restructure the emission_factors index into a Turbo Frame + row partials, turn new/edit into modal frames sharing one `_form`, and make create/update/destroy respond with Turbo Streams while keeping an HTML redirect fallback (progressive enhancement, so existing tests stay green). No domain/Go/schema/migration change.

**Tech Stack:** Rails 8.1, Ruby 4.0.0 (run everything via `mise exec ruby@4.0.0 --`), Hotwire (turbo-rails, stimulus-rails) over importmap, Tailwind (tailwindcss-rails), Capybara + Selenium headless Chrome for system tests.

**Conventions for every task:**
- All commands prefixed with `mise exec ruby@4.0.0 --`.
- Commit after each task; messages end with the trailer:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- Tailwind classes compile via the running `tailwindcss:watch` (dev) / `assets:precompile` (prod); system tests render real CSS through `assets:precompile`/watch, so new classes work.
- DO NOT touch `app/domain/**`, the Go backend, the DB schema, or migrations.

**Suggested batching for execution (per repo speed policy):** Task 1 alone (infra), then Task 2, then Tasks 3+4 together (modal + streams are interdependent). Run the full gate (`bin/rails test` + `test:system` + `rubocop` + `brakeman`) at the end.

---

## File Structure

**Create:**
- `app/javascript/controllers/modal_controller.js` — overlay open/close behavior for the modal frame.
- `app/javascript/controllers/toast_controller.js` — auto-dismiss a toast.
- `app/javascript/controllers/filter_controller.js` — debounced auto-submit of a GET filter form.
- `app/views/shared/_modal.html.erb` — modal chrome (frame + overlay + card + title + close), yields the body.
- `app/views/shared/_toast.html.erb` — one toast element.
- `app/views/emission_factors/_form.html.erb` — shared new/edit fields.
- `app/views/emission_factors/_list.html.erb` — table + pagination (the Turbo Frame body).
- `app/views/emission_factors/_emission_factor.html.erb` — one table row (`id: dom_id`).
- `app/views/emission_factors/create.turbo_stream.erb`
- `app/views/emission_factors/update.turbo_stream.erb`
- `app/views/emission_factors/destroy.turbo_stream.erb`

**Modify:**
- `app/javascript/application.js` — register the global custom confirm.
- `app/views/layouts/application.html.erb` — add modal frame + toast container; render full-page flash as toasts.
- `app/views/emission_factors/index.html.erb` — wrap list in the frame, wire the filter form, point "เพิ่ม" at the modal.
- `app/views/emission_factors/new.html.erb` / `edit.html.erb` — wrap `_form` in the modal.
- `app/controllers/emission_factors_controller.rb` — `respond_to` for create/update/destroy (turbo_stream + html fallback).
- `test/controllers/emission_factors_controller_test.rb` — add turbo_stream cases, keep html cases.
- `test/system/admin_flows_test.rb` (or a new `test/system/emission_factors_test.rb`) — Hotwire behavior.

**Delete:**
- `app/javascript/controllers/hello_controller.js` — scaffold, unused.

---

## Task 1: Shared Hotwire infrastructure

**Files:**
- Create: `app/javascript/controllers/{modal,toast,filter}_controller.js`, `app/views/shared/_modal.html.erb`, `app/views/shared/_toast.html.erb`
- Modify: `app/javascript/application.js`, `app/views/layouts/application.html.erb`
- Delete: `app/javascript/controllers/hello_controller.js`
- Test: `test/system/hotwire_infra_test.rb` (smoke)

- [ ] **Step 1: Write the failing smoke test**

`test/system/hotwire_infra_test.rb`:
```ruby
require "application_system_test_case"

class HotwireInfraTest < ApplicationSystemTestCase
  test "authenticated layout includes the modal frame and toast container" do
    AdminUser.create!(email_address: "sa@pea.co.th", password: "password-for-tests",
                      name: "ซุป", role: :superadmin)
    visit new_session_path
    fill_in "email_address", with: "sa@pea.co.th"
    fill_in "password", with: "password-for-tests"
    click_on "เข้าสู่ระบบ"
    assert_text "ภาพรวมระบบ"
    assert_selector "turbo-frame#modal", visible: :all
    assert_selector "#toast_container", visible: :all
  end

  test "a full-page flash notice renders as an auto-dismissing toast" do
    AdminUser.create!(email_address: "sa@pea.co.th", password: "password-for-tests",
                      name: "ซุป", role: :superadmin)
    visit new_session_path
    fill_in "email_address", with: "sa@pea.co.th"
    fill_in "password", with: "password-for-tests"
    click_on "เข้าสู่ระบบ"
    # login redirect sets a flash notice rendered as a toast inside the container
    assert_selector "#toast_container [data-controller='toast']"
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mise exec ruby@4.0.0 -- bin/rails test:system test/system/hotwire_infra_test.rb`
Expected: FAIL (no `turbo-frame#modal` / `#toast_container`).

- [ ] **Step 3: Create the Stimulus controllers**

`app/javascript/controllers/modal_controller.js`:
```js
import { Controller } from "@hotwired/stimulus"

// Connected on the overlay element rendered inside <turbo-frame id="modal">.
// Closing empties the frame, which removes this element and triggers disconnect().
export default class extends Controller {
  connect() {
    document.body.classList.add("overflow-hidden")
    this.onKeydown = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.body.classList.remove("overflow-hidden")
    document.removeEventListener("keydown", this.onKeydown)
  }

  backdrop(event) {
    if (event.target === this.element) this.close()
  }

  close() {
    const frame = document.getElementById("modal")
    if (frame) frame.innerHTML = ""
  }
}
```

`app/javascript/controllers/toast_controller.js`:
```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: { type: Number, default: 4000 } }

  connect() {
    this.timer = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  dismiss() {
    this.element.remove()
  }
}
```

`app/javascript/controllers/filter_controller.js`:
```js
import { Controller } from "@hotwired/stimulus"

// Debounced auto-submit of a GET filter form. The visible submit button still
// works without JS.
export default class extends Controller {
  static values = { delay: { type: Number, default: 300 } }

  submit() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  submitNow() {
    clearTimeout(this.timer)
    this.element.requestSubmit()
  }
}
```

- [ ] **Step 4: Register the global custom confirm**

`app/javascript/application.js` — replace contents with:
```js
// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import { Turbo } from "@hotwired/turbo-rails"

// Replace the native confirm() used by data-turbo-confirm with a styled dialog.
Turbo.setConfirmMethod((message) => {
  return new Promise((resolve) => {
    const overlay = document.createElement("div")
    overlay.className = "fixed inset-0 z-50 flex items-center justify-center bg-black/40"
    overlay.innerHTML = `
      <div class="w-full max-w-sm rounded-xl bg-white p-6 shadow-lg">
        <p class="text-ink">${message}</p>
        <div class="mt-5 flex justify-end gap-3">
          <button data-confirm-cancel class="rounded-lg px-4 py-2 font-semibold text-body hover:bg-surface cursor-pointer">ยกเลิก</button>
          <button data-confirm-ok class="rounded-lg bg-danger px-4 py-2 font-semibold text-white hover:bg-danger-dark cursor-pointer">ยืนยัน</button>
        </div>
      </div>`
    const cleanup = (result) => { overlay.remove(); document.removeEventListener("keydown", onKey); resolve(result) }
    const onKey = (e) => { if (e.key === "Escape") cleanup(false) }
    overlay.addEventListener("click", (e) => { if (e.target === overlay) cleanup(false) })
    overlay.querySelector("[data-confirm-cancel]").addEventListener("click", () => cleanup(false))
    overlay.querySelector("[data-confirm-ok]").addEventListener("click", () => cleanup(true))
    document.addEventListener("keydown", onKey)
    document.body.appendChild(overlay)
    overlay.querySelector("[data-confirm-ok]").focus()
  })
})
```

- [ ] **Step 5: Create the shared partials**

`app/views/shared/_modal.html.erb` (chrome; callers pass `title:` and a block):
```erb
<%= turbo_frame_tag "modal" do %>
  <div data-controller="modal" data-action="click->modal#backdrop"
       class="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4">
    <div class="w-full max-w-md rounded-xl bg-white p-6 shadow-lg">
      <div class="flex items-center justify-between">
        <h2 class="text-xl font-bold text-ink"><%= title %></h2>
        <button type="button" data-action="modal#close"
                class="cursor-pointer text-2xl leading-none text-body/60 hover:text-ink">&times;</button>
      </div>
      <div class="mt-4"><%= yield %></div>
    </div>
  </div>
<% end %>
```

`app/views/shared/_toast.html.erb` (locals: `kind` = :notice/:alert, `message`):
```erb
<div data-controller="toast" data-action="click->toast#dismiss"
     class="cursor-pointer rounded-lg px-4 py-3 shadow-lg <%= kind == :alert ? "bg-red-50 text-danger" : "bg-green-50 text-green-800" %>">
  <%= message %>
</div>
```

- [ ] **Step 6: Update the layout**

`app/views/layouts/application.html.erb` — in the authenticated branch, replace
`<%= render "shared/flash" %>` inside `<main>` with the modal frame + toast container, and render
full-page flash as toasts. Final `<body>`:
```erb
  <body class="bg-surface text-body font-sans min-h-screen">
    <% if authenticated? %>
      <div class="flex min-h-screen">
        <%= render "shared/sidebar" %>
        <main class="flex-1 p-8">
          <%= yield %>
        </main>
      </div>
    <% else %>
      <%= render "shared/flash" %>
      <%= yield %>
    <% end %>

    <%= turbo_frame_tag "modal" %>
    <div id="toast_container" class="fixed top-4 right-4 z-50 flex w-80 flex-col gap-2">
      <%= render "shared/toast", kind: :notice, message: notice if notice %>
      <%= render "shared/toast", kind: :alert, message: alert if alert %>
    </div>
  </body>
```
(The empty `turbo_frame_tag "modal"` here is the load target; `_modal` renders a frame with the
SAME id whose content replaces it. Keep `shared/_flash` for the unauthenticated branch.)

- [ ] **Step 7: Delete the scaffold controller**

Run: `git rm app/javascript/controllers/hello_controller.js`

- [ ] **Step 8: Run the smoke test to verify it passes**

Run: `mise exec ruby@4.0.0 -- bin/rails test:system test/system/hotwire_infra_test.rb`
Expected: PASS (both tests).

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat(hotwire): shared modal/toast/filter Stimulus + custom confirm + layout

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Emission factors — Turbo Frame list + live filter

**Files:**
- Create: `app/views/emission_factors/_list.html.erb`, `app/views/emission_factors/_emission_factor.html.erb`
- Modify: `app/views/emission_factors/index.html.erb`
- Test: `test/system/emission_factors_test.rb`

- [ ] **Step 1: Write the failing system test**

`test/system/emission_factors_test.rb`:
```ruby
require "application_system_test_case"

class EmissionFactorsTest < ApplicationSystemTestCase
  def login_admin
    AdminUser.create!(email_address: "ad@pea.co.th", password: "password-for-tests",
                      name: "แอด", role: :admin)
    visit new_session_path
    fill_in "email_address", with: "ad@pea.co.th"
    fill_in "password", with: "password-for-tests"
    click_on "เข้าสู่ระบบ"
    assert_text "ภาพรวมระบบ"
  end

  test "typing in search live-filters the list without a full page reload" do
    create_core_emission_factor!(identifier: "ef_alpha", value: 1.0)
    create_core_emission_factor!(identifier: "ef_beta", value: 2.0)
    login_admin
    visit emission_factors_path
    assert_selector "#ef_list", text: "ef_alpha"
    assert_selector "#ef_list", text: "ef_beta"

    fill_in "search", with: "alpha"
    within "#ef_list" do
      assert_text "ef_alpha"
      assert_no_text "ef_beta"
    end
    assert_current_path(/search=alpha/)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mise exec ruby@4.0.0 -- bin/rails test:system test/system/emission_factors_test.rb`
Expected: FAIL (no `#ef_list`; search needs a button click).

- [ ] **Step 3: Create the row partial**

`app/views/emission_factors/_emission_factor.html.erb` (local: `emission_factor`):
```erb
<tr id="<%= dom_id(emission_factor) %>" class="border-b border-gray-100">
  <td class="px-4 py-3 font-mono text-xs"><%= emission_factor.identifier %></td>
  <td class="px-4 py-3 font-medium text-ink"><%= emission_factor.name %></td>
  <td class="px-4 py-3"><%= emission_factor.value_per_unit %></td>
  <td class="px-4 py-3"><%= emission_factor.unit_title %></td>
  <td class="px-4 py-3"><%= emission_factor.carbon_category&.name_thai %></td>
  <td class="px-4 py-3 text-right whitespace-nowrap">
    <% if can?(:manage_master_data) %>
      <%= link_to "แก้ไข", edit_emission_factor_path(emission_factor.id),
            data: { turbo_frame: "modal" }, class: "text-primary" %>
      <%= button_to "ลบ", emission_factor_path(emission_factor.id), method: :delete,
            form: { data: { turbo_confirm: "ลบค่า #{emission_factor.identifier}? (soft delete)" }, class: "inline" },
            class: "ml-3 cursor-pointer text-danger" %>
    <% end %>
  </td>
</tr>
```

- [ ] **Step 4: Create the list partial (table + pagination)**

`app/views/emission_factors/_list.html.erb`:
```erb
<%= turbo_frame_tag "ef_list", data: { turbo_action: "advance" } do %>
  <table class="mt-6 w-full rounded-xl bg-white shadow-sm text-sm">
    <thead>
      <tr class="border-b border-gray-200 text-left text-body/60">
        <th class="px-4 py-3">identifier</th>
        <th class="px-4 py-3">ชื่อ</th>
        <th class="px-4 py-3">ค่า</th>
        <th class="px-4 py-3">หน่วย</th>
        <th class="px-4 py-3">หมวด</th>
        <th class="px-4 py-3"></th>
      </tr>
    </thead>
    <tbody id="ef_rows">
      <%= render partial: "emission_factor", collection: @factors %>
    </tbody>
  </table>

  <div class="mt-4 flex items-center gap-3">
    <% if @page > 1 %>
      <%= link_to "← ก่อนหน้า", emission_factors_path(search: params[:search], category_id: params[:category_id], page: @page - 1), class: "text-primary" %>
    <% end %>
    <span class="text-sm text-body/60">หน้า <%= @page %></span>
    <% if @has_next %>
      <%= link_to "ถัดไป →", emission_factors_path(search: params[:search], category_id: params[:category_id], page: @page + 1), class: "text-primary" %>
    <% end %>
  </div>
<% end %>
```
(The explicit `render partial: "emission_factor", collection: @factors` is used deliberately: the
model is namespaced `Core::EmissionFactor`, so `render @factors` would resolve to
`core/emission_factors/_emission_factor` and miss our partial. The collection form sets a local
named `emission_factor` per row — matching the partial above.)

- [ ] **Step 5: Rewrite index to use the frame + wire the filter form**

`app/views/emission_factors/index.html.erb`:
```erb
<div class="flex items-center justify-between">
  <h1 class="text-2xl font-bold text-ink">ค่าการปล่อยคาร์บอน (EF)</h1>
  <% if can?(:manage_master_data) %>
    <%= link_to "เพิ่มค่า EF", new_emission_factor_path, data: { turbo_frame: "modal" },
          class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark" %>
  <% end %>
</div>

<p class="mt-3 max-w-3xl rounded-lg bg-amber-50 px-4 py-3 text-sm text-amber-800">
  การแก้ไขมีผลกับการคำนวณทั่วไปทันที ยกเว้นหมวดของแจก/อุปกรณ์อีเว้นท์
  (event items / giveaways) ซึ่งระบบหลักแคชไว้ตอนเริ่มทำงาน — ต้อง restart ระบบหลักจึงจะมีผล
</p>

<%= form_with url: emission_factors_path, method: :get,
      data: { controller: "filter", turbo_frame: "ef_list" },
      class: "mt-4 flex flex-wrap items-end gap-3" do |f| %>
  <div>
    <%= f.label :search, "ค้นหา", class: "mb-1 block text-sm font-medium text-ink" %>
    <%= f.text_field :search, value: params[:search], placeholder: "identifier หรือชื่อ",
          data: { action: "input->filter#submit" },
          class: "w-72 rounded-lg border border-gray-300 px-3 py-2" %>
  </div>
  <div>
    <%= f.label :category_id, "หมวด", class: "mb-1 block text-sm font-medium text-ink" %>
    <%= f.select :category_id,
          [["ทั้งหมด", ""]] + @categories.map { |c| ["#{c.name_thai} (#{c.name_eng})", c.id] },
          { selected: params[:category_id] },
          data: { action: "change->filter#submitNow" },
          class: "rounded-lg border border-gray-300 px-3 py-2" %>
  </div>
  <%= f.submit "กรอง", class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
<% end %>

<%= render "list" %>
```

- [ ] **Step 6: Run the system test to verify it passes**

Run: `mise exec ruby@4.0.0 -- bin/rails test:system test/system/emission_factors_test.rb`
Expected: PASS. If `render @factors` raised a missing-partial error, switch Step 4 to the explicit
`render partial: "emission_factor", collection: @factors` form and re-run.

- [ ] **Step 7: Confirm existing controller tests still pass**

Run: `mise exec ruby@4.0.0 -- bin/rails test test/controllers/emission_factors_controller_test.rb`
Expected: PASS (index still renders the same data; no controller change yet).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(hotwire): emission factors list in a Turbo Frame with live filter

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Emission factors — modal new/edit sharing one form

**Files:**
- Create: `app/views/emission_factors/_form.html.erb`
- Modify: `app/views/emission_factors/new.html.erb`, `app/views/emission_factors/edit.html.erb`
- Test: `test/system/emission_factors_test.rb` (add cases)

- [ ] **Step 1: Add failing system tests for the modal**

Append to `test/system/emission_factors_test.rb`:
```ruby
  test "add opens a modal and an invalid submit keeps it open with an error" do
    login_admin
    visit emission_factors_path
    click_on "เพิ่มค่า EF"
    assert_selector "turbo-frame#modal h2", text: "เพิ่มค่า EF"
    # submit with a blank identifier -> server re-renders the modal with an error
    fill_in "emission_factor[name]", with: "x"
    click_on "สร้าง"
    assert_selector "turbo-frame#modal", text: "เพิ่มค่า EF" # still open
  end

  test "edit opens a modal prefilled with the factor" do
    create_core_emission_factor!(identifier: "ef_editme", value: 3.0)
    login_admin
    visit emission_factors_path
    within "#ef_list" do
      click_on "แก้ไข"
    end
    assert_selector "turbo-frame#modal", text: "ef_editme"
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mise exec ruby@4.0.0 -- bin/rails test:system test/system/emission_factors_test.rb -n "/modal|edit opens/"`
Expected: FAIL (links don't open a modal; new/edit are full pages).

- [ ] **Step 3: Create the shared form partial**

`app/views/emission_factors/_form.html.erb` (locals: `url`, `method`, `factor`, `new_record`):
```erb
<% if flash.now[:alert].present? %>
  <div class="mb-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-danger"><%= flash.now[:alert] %></div>
<% end %>

<%= form_with url: url, method: method, scope: :emission_factor, class: "space-y-5" do |f| %>
  <div>
    <%= f.label :identifier, new_record ? "identifier (a-z, 0-9, _, . — แก้ไขภายหลังไม่ได้)" : "identifier (ระบบหลักใช้ค้นหา — แก้ไขไม่ได้)",
          class: "mb-1 block font-medium text-ink" %>
    <% if new_record %>
      <%= f.text_field :identifier, value: factor&.identifier, required: true, maxlength: 255, pattern: "[a-z0-9_.]+",
            class: "w-full rounded-lg border border-gray-300 px-4 py-2.5 font-mono" %>
    <% else %>
      <%= f.text_field :identifier, value: factor.identifier, disabled: true,
            class: "w-full rounded-lg border border-gray-200 bg-gray-50 px-4 py-2.5 font-mono text-body/60" %>
    <% end %>
  </div>
  <div>
    <%= f.label :name, "ชื่อ", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :name, value: factor&.name, required: new_record, maxlength: 255,
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :description, "คำอธิบาย", class: "mb-1 block font-medium text-ink" %>
    <%= text_area_tag "emission_factor[description]", factor&.description, rows: 2,
          id: "emission_factor_description", class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :source, "แหล่งอ้างอิง", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :source, value: factor&.source, required: new_record,
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :value_per_unit, "ค่า (ต่อหน่วย)", class: "mb-1 block font-medium text-ink" %>
    <%= f.number_field :value_per_unit,
          value: (factor.respond_to?(:value_per_unit_before_type_cast) ? factor.value_per_unit_before_type_cast : nil) || factor&.value_per_unit,
          required: new_record, step: "any", min: 0,
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :unit_title, "หน่วย (เช่น kgCO2e/kg)", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :unit_title, value: factor&.unit_title, required: new_record, maxlength: 255,
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <% if new_record %>
    <div>
      <%= f.label :carbon_category_id, "หมวด", class: "mb-1 block font-medium text-ink" %>
      <%= f.select :carbon_category_id,
            @categories.map { |c| ["#{c.name_thai} (#{c.name_eng})", c.id] },
            { selected: factor&.carbon_category_id }, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
    </div>
  <% end %>
  <%= f.submit new_record ? "สร้าง" : "บันทึก",
        class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
<% end %>
```
(Note: `update_params` does not permit `carbon_category_id`/`identifier`, so the edit form omits the
category select and disables identifier — matching the controller's existing strong params.)

- [ ] **Step 4: Wrap new/edit in the modal**

`app/views/emission_factors/new.html.erb`:
```erb
<%= render "shared/modal", title: "เพิ่มค่า EF" do %>
  <%= render "form", url: emission_factors_path, method: :post, factor: @factor, new_record: true %>
<% end %>
```

`app/views/emission_factors/edit.html.erb`:
```erb
<%= render "shared/modal", title: "แก้ไขค่า EF: #{@factor.identifier}" do %>
  <%= render "form", url: emission_factor_path(@factor.id), method: :patch, factor: @factor, new_record: false %>
<% end %>
```

- [ ] **Step 5: Run the modal system tests to verify they pass**

Run: `mise exec ruby@4.0.0 -- bin/rails test:system test/system/emission_factors_test.rb -n "/modal|edit opens/"`
Expected: PASS. (The invalid-submit test relies on the create action already re-rendering `:new`
with 422 — which it does today — so the modal frame replaces itself and stays open.)

- [ ] **Step 6: Run the controller test file (no controller change yet)**

Run: `mise exec ruby@4.0.0 -- bin/rails test test/controllers/emission_factors_controller_test.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(hotwire): emission factors new/edit in a modal sharing one form

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Emission factors — Turbo Stream writes (with HTML fallback) + tests

**Files:**
- Create: `app/views/emission_factors/{create,update,destroy}.turbo_stream.erb`
- Modify: `app/controllers/emission_factors_controller.rb`
- Test: `test/controllers/emission_factors_controller_test.rb`, `test/system/emission_factors_test.rb`

- [ ] **Step 1: Write failing controller tests for the turbo_stream responses**

Append to `test/controllers/emission_factors_controller_test.rb` (inside the class; reuse its
existing `setup`/`login` helpers — superadmin or admin logged in, a category available):
```ruby
  test "create via turbo_stream prepends a row, closes the modal, and toasts" do
    login(@superadmin)
    category = create_core_category!
    assert_difference -> { Core::EmissionFactor.kept.count } => 1 do
      post emission_factors_path, as: :turbo_stream, params: { emission_factor: {
        identifier: "ef_stream", name: "n", source: "s", value_per_unit: "1.0",
        unit_title: "kg", description: "", carbon_category_id: category.id } }
    end
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{turbo-stream action="prepend" target="ef_rows"}, response.body
    assert_match %r{turbo-stream action="update" target="modal"}, response.body
    assert_match %r{turbo-stream action="append" target="toast_container"}, response.body
  end

  test "create via HTML still redirects (no-JS fallback)" do
    login(@superadmin)
    category = create_core_category!
    post emission_factors_path, params: { emission_factor: {
      identifier: "ef_html", name: "n", source: "s", value_per_unit: "1.0",
      unit_title: "kg", description: "", carbon_category_id: category.id } }
    assert_redirected_to emission_factors_path
  end

  test "update via turbo_stream replaces the row and toasts" do
    login(@superadmin)
    factor = create_core_emission_factor!(identifier: "ef_upd", value: 1.0)
    patch emission_factor_path(factor.id), as: :turbo_stream,
      params: { emission_factor: { name: "ใหม่", value_per_unit: "9.0", unit_title: "kg", source: "s" } }
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(factor)}"}, response.body
  end

  test "destroy via turbo_stream removes the row and toasts" do
    login(@superadmin)
    factor = create_core_emission_factor!(identifier: "ef_del", value: 1.0)
    delete emission_factor_path(factor.id), as: :turbo_stream
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{turbo-stream action="remove" target="#{ActionView::RecordIdentifier.dom_id(factor)}"}, response.body
  end
```
(If the existing test file's `setup` uses a different logged-in admin variable, adapt the `login`
calls to match. Ensure `create_core_category!` is available — it is, in `core_factories.rb`.)

- [ ] **Step 2: Run to verify they fail**

Run: `mise exec ruby@4.0.0 -- bin/rails test test/controllers/emission_factors_controller_test.rb -n "/turbo_stream|fallback/"`
Expected: FAIL (controller currently always redirects; no turbo_stream templates).

- [ ] **Step 3: Add `respond_to` to create/update/destroy**

In `app/controllers/emission_factors_controller.rb`, change the success branches to respond per
format (keep the error branches and `rescue` exactly as-is):

`create` success branch:
```ruby
    if result.success?
      @factor = result.value
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = "สร้างค่า EF แล้ว" }
        format.html { redirect_to emission_factors_path, notice: "สร้างค่า EF แล้ว" }
      end
    else
```
`update` success branch:
```ruby
    if result.success?
      @factor = result.value
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = "บันทึกการแก้ไขแล้ว" }
        format.html { redirect_to emission_factors_path, notice: "บันทึกการแก้ไขแล้ว" }
      end
    else
```
`destroy`:
```ruby
  def destroy
    result = MasterData::DeleteEmissionFactor.call(actor: current_admin, id: params[:id],
                                                   repo: repo, audit: audit)
    if result.success?
      @factor = result.value
      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = "ลบค่า EF แล้ว (soft delete)" }
        format.html { redirect_to emission_factors_path, notice: "ลบค่า EF แล้ว (soft delete)" }
      end
    else
      redirect_to emission_factors_path, alert: result.error
    end
  end
```
(Confirmed: `Result` exposes `.value`, and `CreateEmissionFactor` / `UpdateEmissionFactor` /
`DeleteEmissionFactor` all `Result.success(record)`, so `result.value` is the AR record.)

- [ ] **Step 4: Create the turbo_stream templates**

`app/views/emission_factors/create.turbo_stream.erb`:
```erb
<%= turbo_stream.prepend "ef_rows" do %>
  <%= render "emission_factor", emission_factor: @factor %>
<% end %>
<%= turbo_stream.update "modal", "" %>
<%= turbo_stream.append "toast_container" do %>
  <%= render "shared/toast", kind: :notice, message: flash.now[:notice] %>
<% end %>
```

`app/views/emission_factors/update.turbo_stream.erb`:
```erb
<%= turbo_stream.replace dom_id(@factor) do %>
  <%= render "emission_factor", emission_factor: @factor %>
<% end %>
<%= turbo_stream.update "modal", "" %>
<%= turbo_stream.append "toast_container" do %>
  <%= render "shared/toast", kind: :notice, message: flash.now[:notice] %>
<% end %>
```

`app/views/emission_factors/destroy.turbo_stream.erb`:
```erb
<%= turbo_stream.remove dom_id(@factor) %>
<%= turbo_stream.append "toast_container" do %>
  <%= render "shared/toast", kind: :notice, message: flash.now[:notice] %>
<% end %>
```

- [ ] **Step 5: Run the controller tests to verify they pass**

Run: `mise exec ruby@4.0.0 -- bin/rails test test/controllers/emission_factors_controller_test.rb`
Expected: PASS (new turbo_stream tests + the original HTML tests).

- [ ] **Step 6: Add end-to-end system tests for the write flows**

Append to `test/system/emission_factors_test.rb`:
```ruby
  test "creating a factor shows the new row and a toast, and closes the modal" do
    create_core_category!(name_thai: "หมวดทดสอบ", name_eng: "test_cat")
    login_admin
    visit emission_factors_path
    click_on "เพิ่มค่า EF"
    fill_in "emission_factor[identifier]", with: "ef_created"
    fill_in "emission_factor[name]", with: "ชื่อใหม่"
    fill_in "emission_factor[source]", with: "src"
    fill_in "emission_factor[value_per_unit]", with: "2.5"
    fill_in "emission_factor[unit_title]", with: "kgCO2e/kg"
    click_on "สร้าง"
    assert_selector "#toast_container", text: "สร้างค่า EF แล้ว"
    assert_selector "#ef_rows", text: "ef_created"
    assert_no_selector "turbo-frame#modal div" # modal emptied/closed
  end

  test "deleting a factor removes its row after the styled confirm" do
    create_core_emission_factor!(identifier: "ef_kill", value: 1.0)
    login_admin
    visit emission_factors_path
    within "#ef_list" do
      accept_confirm { click_on "ลบ" }
    end
    assert_no_selector "#ef_rows", text: "ef_kill"
    assert_selector "#toast_container", text: "ลบค่า EF แล้ว"
  end
```
(`accept_confirm` works with the custom `Turbo.setConfirmMethod` only if it resolves a native
dialog. Because the custom confirm is NOT a native `window.confirm`, replace `accept_confirm { ... }`
with clicking the styled dialog's confirm button:
```ruby
    within "#ef_list" do
      click_on "ลบ"
    end
    click_on "ยืนยัน"
```
Use this styled-dialog form in the test.)

- [ ] **Step 7: Run the system tests to verify they pass**

Run: `mise exec ruby@4.0.0 -- bin/rails test:system test/system/emission_factors_test.rb`
Expected: PASS (all emission-factors system tests).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(hotwire): emission factors create/update/destroy via Turbo Streams

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification (run after all tasks)

- [ ] `mise exec ruby@4.0.0 -- bin/rails test` → 0 failures
- [ ] `mise exec ruby@4.0.0 -- bin/rails test:system` → 0 failures
- [ ] `mise exec ruby@4.0.0 -- bin/rubocop` → 0 offenses
- [ ] `mise exec ruby@4.0.0 -- bundle exec brakeman -q` → 0 warnings
- [ ] Re-index the graph (`index_repository`, mode `fast`) on carbonmice-admin.
- [ ] Manual smoke (docker compose up) per the spec's Verification section.

## Notes for the rollout (NOT part of this plan)

Once this pilot is approved in practice, the other resources reuse: the three Stimulus controllers,
the custom confirm, the layout modal frame + toast container, and the `_modal`/`_toast` partials.
Per resource the mechanical work is: list→frame + row partial, new/edit→modal + shared `_form`,
and `respond_to` + three `*.turbo_stream.erb` templates. Edit-only resources (categories, app_users,
admin_users) skip create/destroy; `events` keeps its status flow.
