# Admin: three changes (carbon credit, edit event, app user quota)

Date: 2026-06-17
Scope: `carbonmice-admin` only (Rails). No changes to `carbonmice-main-fe` or
`carbonmice-main-go-be`.

Architecture is hexagonal: view → controller (params) → domain use case → repo
(port/adapter). Each change is applied at the correct layer, with the domain
remaining authoritative for validation.

---

## Change 1 — Carbon Credit: offset source required, non-negative, merge on add

### 1A. Offset source becomes a required field

Currently `carbon_offset_source_id` is optional: the form labels it
"แหล่งออฟเซ็ต (ไม่บังคับ)" with a "— ไม่ระบุ —" empty option, and
`MasterData::CreateCarbonCredit` stores `nil` when blank.

- `app/views/carbon_credits/_form.html.erb`: relabel to "แหล่งออฟเซ็ต",
  replace the "— ไม่ระบุ —" option with an empty placeholder
  ("เลือกแหล่งออฟเซ็ต", value ""), add `required: true` to the select.
- `app/domain/master_data/create_carbon_credit.rb`: after parsing `source_id`,
  reject blank with `Result.failure("กรุณาเลือกแหล่งออฟเซ็ต")`. Domain stays
  authoritative (so the no-JS / system-test path is exercised).

### 1B. Non-negative amount

Already enforced server-side in `CreateCarbonCredit`:
`amount.nil? || amount <= 0 → "จำนวน carbon credit ต้องเป็นจำนวนเต็มมากกว่า 0"`.
The form intentionally omits HTML5 `min` (documented in `_form.html.erb`) so the
server-side rejection remains observable. **No change** — requirement already met.

### 1C. Merge on add (sum)

When the admin clicks "เพิ่ม" and a kept carbon_credit already exists for the
same `(user_id, carbon_offset_source_id)`, add the new amount to the existing
record instead of inserting a new row. There is **no** DB unique constraint on
`(user_id, carbon_offset_source_id)`, so the merge is done at the application
(domain) layer.

In `MasterData::CreateCarbonCredit.call`, after validations pass:

1. Look up the existing kept record via a new repo finder
   `find_kept_by(user_id:, source_id:)`.
2. **If found:** `new_amount = existing.carbon_credit + amount`; update the
   existing record's `carbon_credit`. Audit as `master_data.carbon_credit_updated`
   with `changes: { "carbon_credit" => { "from" => old, "to" => new_amount } }`.
3. **If not found:** create a new record as today. Audit as
   `master_data.carbon_credit_created`.

`source_id` is always present now (1A), so the merge key is always fully
populated.

Repo: add `ArCarbonCreditRepository#find_kept_by(user_id:, source_id:)` returning
the kept record or `nil`. Reuse the existing update path for the amount bump.

---

## Change 2 — Edit Event: remove "จังหวัด" (province) — not editable

Province is removed from the **edit path** only. It remains a column in the DB
and is still displayed on the event show page; it simply can no longer be edited
from the edit modal.

- `app/views/events/edit.html.erb`: remove the `<div>` containing the `:province`
  field.
- `app/domain/events/update_details.rb`: remove `:province` from `EDITABLE`
  → `[:name_thai, :name_eng, :area_name]`.
- `app/controllers/events_controller.rb`: remove `:province` from
  `update_params` permit list.

---

## Change 3 — App User quota: first-time isPackage flag + credit total column

### 3A. Set `is_package_user` true on the first quota adjustment

`users.is_package_user boolean DEFAULT false`. `AppUsers::AdjustQuota.call`
currently never touches it.

- `app/domain/app_users/adjust_quota.rb`: after `before = repo.find(id)`, if
  `before.is_package_user` is `false`, set it to `true` as part of the same
  update (first time only). Subsequent quota adjustments leave the flag alone.
- `app/adapters/persistence/ar_app_user_repository.rb#update_quota`: accept the
  decision from the domain (e.g. a `mark_package:` keyword) and set
  `is_package_user: true` alongside `event_quota` when instructed.
- Audit: when the flag flips, include
  `"is_package_user" => { "from" => false, "to" => true }` in the recorded
  changes (alongside the existing `event_quota` diff).

### 3B. New "เครดิตรวม" column in the app users list

Show the sum of the user's carbon credits across all offset sources.

- `app/controllers/app_users_controller.rb#index`: after loading `@app_users`,
  build a single grouped aggregate to avoid N+1:
  `@credit_totals = Core::CarbonCredit.kept.where(user_id: @app_users.map(&:id))
   .group(:user_id).sum(:carbon_credit)` (Hash of user_id → total).
- `app/views/app_users/_list.html.erb`: add `<th>เครดิตรวม</th>`.
- `app/views/app_users/_app_user.html.erb`: add a `<td>` showing
  `@credit_totals[app_user.id]` (display `0`/absent as "—").

---

## Testing

Follow TDD. Each change has existing domain unit tests and system tests to
extend:

- Change 1: merge sums into existing kept record; new source-required validation
  rejects blank; created vs updated audit action; amount `<= 0` still rejected.
- Change 2: `:province` rejected as a now-unknown editable key (or simply no
  longer permitted/rendered); name/area edits still work.
- Change 3A: first adjustment flips `is_package_user` and audits it; second
  adjustment does not re-flip / does not re-audit the flag.
- Change 3B: list shows the per-user summed total across multiple offset sources;
  users with no credits show "—".

## Out of scope

- `carbonmice-main-fe` and `carbonmice-main-go-be` — all three changes are in
  the admin Rails app.
- Province stays in the DB and on the event show page; only editing is removed.
- No HTML5 `min` constraint added to the amount field (server-side stays
  authoritative).
- No DB migration — `(user_id, carbon_offset_source_id)` merge is enforced in the
  domain, not via a new unique constraint.
