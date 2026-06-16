# Event status — Danger zone + dropdown from `event_statuses`

> Feature 1 of 3 in the current batch. Locally verifiable (view + controller only).
> No domain change, no Go change, no migration. Ships before the `v0.0.1` tag.

## Goal

On the event detail page (`/events/:id`), the "เปลี่ยนสถานะ" (change-status) box should:

1. **Look like a danger zone** — visually distinct so an admin understands this is a
   direct, out-of-band data edit (no email, no quota, audited).
2. **Source its status options from the database** (`public.event_statuses`) shown as Thai
   labels, instead of the current hardcoded raw status codes.

## Context

- The box lives in `app/views/events/show.html.erb`, gated by `can?(:manage_events)`.
- Today the dropdown renders `@status_targets.map { |s| [s, s] }` — the *valid transition
  targets* computed from `Events::ChangeStatus::TRANSITIONS` for the current status, shown
  as raw codes (e.g. `draft`) with no Thai label.
- `Core::EventStatus` (`public.event_statuses`, Go-owned) already exists with columns
  `name_eng` (the value stored in `events.event_status`), `name_thai` (Thai label) and
  `running_order`. It has an `ordered` scope (`kept.order(:running_order)`). The **index**
  action already loads `Core::EventStatus.ordered` for its filter dropdown — same pattern.
- `Events::ChangeStatus` validates every transition server-side against `TRANSITIONS`
  (mirrors Go's `ValidateStatus`). Invalid moves return
  `Result.failure("เปลี่ยนสถานะจาก X ไป Y ไม่ได้")` and redirect back with an alert.

## Decisions

1. **Dropdown shows the full catalog** — all `Core::EventStatus.ordered` rows
   (`value = name_eng`, `label = name_thai`), default-selected to the event's current
   status. The admin may pick any status; the existing `TRANSITIONS` guard remains the
   safety net and rejects invalid moves with the existing alert. (Chosen over
   "valid-transitions-only" so the catalog drives the UI and labels come from one place;
   accepted trade-off: picking an invalid target yields an error instead of being hidden.)
2. **Guard unchanged** — `Events::ChangeStatus::TRANSITIONS` and the whole domain layer are
   untouched. This stays a pure presentation change.
3. **Danger-zone styling — "strong" variant (approved mockup B):** light-red background
   (`bg-red-50`) + thick red border (`border-2 border-danger`). Heading
   "เปลี่ยนสถานะ" in `text-danger` with a warning-triangle SVG icon and a red
   **"Danger zone"** pill. The existing warning paragraph (no email / no quota / all changes
   audited) is kept. The submit button becomes **danger-red** (`bg-danger`, hover
   `bg-danger-dark`) to separate it from the page's blue primary CTA
   (`destructive-emphasis`). Danger is signalled by colour **and** icon **and** text label,
   never colour alone.
4. **Form always rendered** — since the catalog is non-empty, the `@status_targets.any?`
   conditional and its "ไม่มีสถานะปลายทาง…" empty branch are removed.

## Changes

### `app/controllers/events_controller.rb`
- `show`: add `@statuses = Core::EventStatus.ordered`. Remove the `@status_targets`
  computation (no longer used by the view).

### `app/views/events/show.html.erb`
- Restyle the change-status `<div>` to the danger-zone "strong" look (border-2 border-danger
  bg-red-50, red heading + triangle icon + "Danger zone" pill, danger submit button).
- Replace the `<select>` options with
  `@statuses.map { |s| [s.name_thai, s.name_eng] }`, `selected: @event.event_status`.
- Drop the `@status_targets.any?` conditional / empty-state branch.
- Tailwind classes `border-danger`, `bg-danger`, `bg-red-50` compile from the existing
  `--color-danger` theme token (`bg-red-50` already in the build).

### `app/assets/tailwind/application.css`
- Add one theme token `--color-danger-dark: #B42318;` next to the existing
  `--color-primary-dark`, so the danger submit button gets a proper `hover:bg-danger-dark`
  shade (mirrors how the blue primary button uses `primary-dark`). One line, no other change.

### `test/support/core_factories.rb`
- Add `create_core_event_status!(name_eng:, name_thai:, running_order:)` — raw uncached
  INSERT into `public.event_statuses` (stamps `created_by`), mirroring the other
  `create_core_*` helpers. Needed because `event_statuses` is Go-owned and the test DB seeds
  no rows.

### `test/controllers/events_controller_test.rb`
- New test: on the show page, seed a couple of `event_statuses` rows, `get event_path`, and
  assert the dropdown renders the Thai labels (`assert_select "form[action=?] option"` for
  `status_event_path`) and that the container carries the `border-danger` danger-zone class.
- New test: selecting an **invalid** transition target from the full catalog still gets
  rejected by the guard (redirect back with the existing alert, status unchanged) — proves
  the catalog dropdown did not weaken the server-side guard.
- The existing "viewer sees no status form" test must keep passing (form still gated by
  `can?(:manage_events)`).

## Out of scope

- Changing `TRANSITIONS` / the allowed-transition rules.
- Hiding or disabling invalid targets in the dropdown (guard handles them).
- Any change to `events.event_status` semantics, the Go backend, or the DB schema.
- A confirm dialog on submit (can be added later if wanted; not required for v0.0.1).

## Verification

1. `bin/rails test test/controllers/events_controller_test.rb` → green (run via
   `mise exec ruby@4.0.0 --`).
2. Full gate at batch end: `bin/rails test`, `bin/rails test:system`, `bin/rubocop`,
   `bundle exec brakeman -q`.
3. Manual smoke (docker compose up, login superadmin): open an event → the change-status box
   shows the red danger-zone styling, the dropdown lists Thai status labels, picking a valid
   transition changes status (audited), picking an invalid one shows the rejection alert.
