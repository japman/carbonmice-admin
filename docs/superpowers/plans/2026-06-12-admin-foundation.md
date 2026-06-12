# Carbonmice Admin — Plan 1/2: Foundation, Auth & Audit Log

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A running Rails 8.1.3 admin app with login (3 roles), an insert-only audit log covering auth events and admin-account changes, and the carbonmice corporate identity — connected to the shared Postgres via its own `admin` schema.

**Architecture:** Hexagonal: pure-PORO domain (`app/domain/`) with ports; ActiveRecord adapters (`app/adapters/persistence/`); controllers/views as the web adapter. Rails-owned tables live in the Postgres `admin` schema; the Go backend's `public` schema is never migrated or touched. Plan 2 (events / app users / master data / dashboard) follows after this plan is executed and reuses these patterns.

**Tech Stack:** Ruby 4.0.0, Rails 8.1.3, PostgreSQL (shared instance), Tailwind v4 (tailwindcss-rails), Hotwire, Minitest, bcrypt, dotenv-rails.

**Spec:** `docs/superpowers/specs/2026-06-12-admin-panel-design.md`

**Hard rules for every task:**
- NEVER modify anything under `/Users/japman/Documents/Backup/Project/PEA/carbonmice/carbonmice-main-go-be` (read-only reference).
- All work happens in `/Users/japman/Documents/Backup/Project/PEA/carbonmice/carbonmice-admin` (repo already exists; `docs/` is committed).
- Rails migrations may only create/alter tables in the `admin` schema.

---

### Task 1: Scaffold the Rails app

**Files:**
- Create: `.ruby-version`, full Rails app skeleton (via `rails new`), `Gemfile` additions

- [ ] **Step 1: Pin Ruby and install Rails**

```bash
cd /Users/japman/Documents/Backup/Project/PEA/carbonmice/carbonmice-admin
echo "4.0.0" > .ruby-version
ruby -v        # expect: ruby 4.0.0 (via mise; if not, run: mise use ruby@4.0.0)
gem install rails -v 8.1.3
```

- [ ] **Step 2: Generate the app in place** (keeps existing `.git/` and `docs/`)

```bash
rails _8.1.3_ new . --database=postgresql --css=tailwind \
  --skip-kamal --skip-solid --skip-jbuilder --skip-docker \
  --skip-action-mailbox --skip-action-text --skip-active-storage
```

Expected: generator completes, app module is `CarbonmiceAdmin`, `bundle install` succeeds.

- [ ] **Step 3: Add gems**

In `Gemfile`, uncomment/add:

```ruby
gem "bcrypt", "~> 3.1"

group :development, :test do
  gem "dotenv-rails"
end
```

Then:

```bash
bundle install
```

- [ ] **Step 4: Ignore .env**

Append to `.gitignore`:

```
.env
```

- [ ] **Step 5: Verify and commit**

```bash
bin/rails about    # expect: Rails version 8.1.3, Ruby version 4.0.0
git add -A && git commit -m "chore: scaffold Rails 8.1.3 app (postgres, tailwind, minitest)"
```

---

### Task 2: Database config — shared Postgres, `admin` schema only

**Files:**
- Modify: `config/database.yml`
- Create: `.env`, `.env.example`, `lib/tasks/admin_schema.rake`, `config/initializers/database_tasks.rb`
- Modify: `bin/setup`

- [ ] **Step 1: Write `config/database.yml`** (replace generated content entirely)

```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  host: <%= ENV.fetch("DB_HOST", "localhost") %>
  port: <%= ENV.fetch("DB_PORT", "5432") %>
  username: <%= ENV.fetch("DB_USER", "postgres") %>
  password: <%= ENV["DB_PASSWORD"] %>
  schema_search_path: "admin,public"

development:
  <<: *default
  database: <%= ENV.fetch("DB_NAME", "carbonmice") %>

# Own throwaway DB — full control, no shared data. Go-owned table structure
# is loaded as a fixture in Plan 2 (db/core_structure.sql).
test:
  <<: *default
  database: carbonmice_admin_test

production:
  <<: *default
  database: <%= ENV.fetch("DB_NAME") %>
```

- [ ] **Step 2: Create `.env.example`** (commit) **and `.env`** (not committed)

`.env.example`:

```
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=carbonmice
SEED_SUPERADMIN_EMAIL=
SEED_SUPERADMIN_NAME=
SEED_SUPERADMIN_PASSWORD=
```

Copy to `.env` and fill DB values to match the running dev Postgres. Read the values from `carbonmice-main-go-be/.env` (look at `GOOSE_DBSTRING` / `DB_*` / compose `postgres` service) — READ that file only, never edit it. The dev Postgres comes from the Go repo's docker-compose (`docker compose up -d postgres` there — running it does not modify their repo).

- [ ] **Step 3: Guarantee the `admin` schema exists before any migrate**

Create `lib/tasks/admin_schema.rake`:

```ruby
namespace :db do
  desc "Create the admin schema used by this app (idempotent)"
  task ensure_admin_schema: :environment do
    ActiveRecord::Base.connection.execute("CREATE SCHEMA IF NOT EXISTS admin")
  end
end

Rake::Task["db:migrate"].enhance(["db:ensure_admin_schema"])
```

- [ ] **Step 4: Dump ONLY the admin schema** (so `structure.sql` never contains Go's tables)

Create `config/initializers/database_tasks.rb`:

```ruby
# Keep the SQL structure dump limited to the schema this app owns.
# The shared `public` schema belongs to the Go backend and must never
# appear in this repo's structure.sql.
ActiveRecord::Tasks::DatabaseTasks.structure_dump_flags = ["--schema=admin"]
```

In `config/application.rb`, inside `class Application < Rails::Application`, add:

```ruby
config.active_record.schema_format = :sql
```

- [ ] **Step 5: Point `bin/setup` at the safe path**

In `bin/setup`, replace the `bin/rails db:prepare` line with:

```ruby
system! "bin/rails db:ensure_admin_schema db:migrate"
```

- [ ] **Step 6: Verify against the running dev DB**

```bash
bin/rails db:ensure_admin_schema db:migrate
psql "postgres://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME" -c "\dt admin.*"
```

Expected: `admin.schema_migrations` and `admin.ar_internal_metadata` exist; nothing new in `public`.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: shared-postgres config with admin schema isolation"
```

---

### Task 3: `AccessPolicy` — pure domain, TDD

**Files:**
- Create: `test/domain_helper.rb`
- Test: `test/domain/admin_auth/access_policy_test.rb`
- Create: `app/domain/admin_auth/access_policy.rb`

- [ ] **Step 1: Create `test/domain_helper.rb`**

```ruby
require "minitest/autorun"

# Standalone runs (`ruby -Itest ...`) require the domain directly — proving it
# is Rails-free. Under `bin/rails test`, Zeitwerk autoloads the same constants.
unless defined?(Rails)
  Dir[File.expand_path("../app/domain/**/*.rb", __dir__)].sort.each { |f| require f }
end
```

- [ ] **Step 2: Write the failing test** — `test/domain/admin_auth/access_policy_test.rb`

```ruby
require_relative "../../domain_helper"

class AccessPolicyTest < Minitest::Test
  def test_viewer_can_view_operations_but_not_manage_or_audit
    assert AdminAuth::AccessPolicy.allows?(role: "viewer", action: :view_operations)
    refute AdminAuth::AccessPolicy.allows?(role: "viewer", action: :manage_events)
    refute AdminAuth::AccessPolicy.allows?(role: "viewer", action: :view_audit_log)
  end

  def test_admin_manages_operations_but_not_admin_accounts_or_audit
    assert AdminAuth::AccessPolicy.allows?(role: "admin", action: :manage_events)
    assert AdminAuth::AccessPolicy.allows?(role: "admin", action: :manage_app_users)
    assert AdminAuth::AccessPolicy.allows?(role: "admin", action: :manage_master_data)
    refute AdminAuth::AccessPolicy.allows?(role: "admin", action: :manage_admin_users)
    refute AdminAuth::AccessPolicy.allows?(role: "admin", action: :view_audit_log)
  end

  def test_superadmin_can_do_everything
    AdminAuth::AccessPolicy::ACTIONS.each do |action|
      assert AdminAuth::AccessPolicy.allows?(role: "superadmin", action: action),
             "superadmin should be allowed #{action}"
    end
  end

  def test_unknown_role_or_action_is_denied
    refute AdminAuth::AccessPolicy.allows?(role: "hacker", action: :view_operations)
    refute AdminAuth::AccessPolicy.allows?(role: "admin", action: :launch_rockets)
    refute AdminAuth::AccessPolicy.allows?(role: nil, action: :view_operations)
  end
end
```

- [ ] **Step 3: Run to verify failure**

```bash
ruby -Itest test/domain/admin_auth/access_policy_test.rb
```

Expected: FAIL — `uninitialized constant AdminAuth`.

- [ ] **Step 4: Implement** — `app/domain/admin_auth/access_policy.rb`

```ruby
module AdminAuth
  # Single authority for role-based permissions across the app.
  # Visibility changes (e.g. letting other roles see the audit log later)
  # are made HERE and nowhere else.
  class AccessPolicy
    PERMISSIONS = {
      "viewer"     => %i[view_operations],
      "admin"      => %i[view_operations manage_events manage_app_users manage_master_data],
      "superadmin" => %i[view_operations manage_events manage_app_users manage_master_data
                         manage_admin_users view_audit_log]
    }.freeze

    ACTIONS = PERMISSIONS.values.flatten.uniq.freeze

    def self.allows?(role:, action:)
      PERMISSIONS.fetch(role.to_s, []).include?(action&.to_sym)
    end
  end
end
```

- [ ] **Step 5: Run to verify pass**

```bash
ruby -Itest test/domain/admin_auth/access_policy_test.rb
```

Expected: PASS, 4 runs, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: AccessPolicy domain rules for viewer/admin/superadmin"
```

---

### Task 4: `AdminUser` + `Session` models — TDD

**Files:**
- Create: migration `db/migrate/*_create_admin_auth_tables.rb`
- Create: `app/models/admin_user.rb`, `app/models/session.rb`
- Test: `test/models/admin_user_test.rb`

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration CreateAdminAuthTables
```

Replace the generated file's content:

```ruby
class CreateAdminAuthTables < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_users do |t|
      t.string  :email_address, null: false, index: { unique: true }
      t.string  :password_digest, null: false
      t.string  :name, null: false
      t.integer :role, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :sessions do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end
  end
end
```

- [ ] **Step 2: Write the failing test** — `test/models/admin_user_test.rb`

```ruby
require "test_helper"

class AdminUserTest < ActiveSupport::TestCase
  test "normalizes email address" do
    u = AdminUser.create!(email_address: "  Admin@PEA.co.th ",
                          password: "password-for-tests", name: "แอดมิน", role: :admin)
    assert_equal "admin@pea.co.th", u.email_address
  end

  test "rejects duplicate email case-insensitively" do
    AdminUser.create!(email_address: "a@pea.co.th", password: "password-for-tests", name: "หนึ่ง")
    dup = AdminUser.new(email_address: "A@pea.co.th", password: "password-for-tests", name: "สอง")
    refute dup.valid?
  end

  test "defaults to viewer role and active" do
    u = AdminUser.create!(email_address: "v@pea.co.th", password: "password-for-tests", name: "วิว")
    assert u.viewer?
    assert u.active?
  end

  test "rejects passwords shorter than 12 chars" do
    u = AdminUser.new(email_address: "s@pea.co.th", password: "short", name: "สั้น")
    refute u.valid?
  end
end
```

- [ ] **Step 3: Run to verify failure**

```bash
bin/rails db:migrate && bin/rails test test/models/admin_user_test.rb
```

Expected: FAIL — `uninitialized constant AdminUser`.

- [ ] **Step 4: Implement the models**

`app/models/admin_user.rb`:

```ruby
class AdminUser < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  enum :role, { viewer: 0, admin: 1, superadmin: 2 }, default: :viewer

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
                            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :password, length: { minimum: 12 }, allow_nil: true
end
```

`app/models/session.rb`:

```ruby
class Session < ApplicationRecord
  belongs_to :admin_user
end
```

- [ ] **Step 5: Run to verify pass**

```bash
bin/rails test test/models/admin_user_test.rb
```

Expected: PASS, 4 runs, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: AdminUser and Session models with roles"
```

---

### Task 5: Authentication + login page with carbonmice CI

**Files:**
- Create: `app/models/current.rb`, `app/controllers/concerns/authentication.rb`, `app/controllers/sessions_controller.rb`, `app/views/sessions/new.html.erb`, `app/views/shared/_flash.html.erb`
- Modify: `app/controllers/application_controller.rb`, `config/routes.rb`, `app/assets/tailwind/application.css`, `app/views/layouts/application.html.erb`
- Copy: `docs/assets/ci/logo-carbonmice.png` → `app/assets/images/logo-carbonmice.png`
- Test: `test/controllers/sessions_controller_test.rb`

- [ ] **Step 1: Write the failing test** — `test/controllers/sessions_controller_test.rb`

```ruby
require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = AdminUser.create!(email_address: "admin@pea.co.th",
                               password: "password-for-tests", name: "แอดมิน", role: :admin)
  end

  test "login with valid credentials reaches home" do
    post session_path, params: { email_address: "admin@pea.co.th", password: "password-for-tests" }
    assert_redirected_to root_url
    follow_redirect!
    assert_response :success
  end

  test "login with wrong password is rejected" do
    post session_path, params: { email_address: "admin@pea.co.th", password: "wrong-password" }
    assert_redirected_to new_session_path
  end

  test "deactivated admin cannot login" do
    @admin.update!(active: false)
    post session_path, params: { email_address: "admin@pea.co.th", password: "password-for-tests" }
    assert_redirected_to new_session_path
  end

  test "unauthenticated request is redirected to login" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "logout terminates the session" do
    post session_path, params: { email_address: "admin@pea.co.th", password: "password-for-tests" }
    delete session_path
    assert_redirected_to new_session_path
    get root_path
    assert_redirected_to new_session_path
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bin/rails test test/controllers/sessions_controller_test.rb
```

Expected: FAIL — undefined `session_path` / `root_path` routes.

- [ ] **Step 3: Implement auth plumbing** (hand-written Rails 8 pattern — the generator hardcodes a `User` model, we need `AdminUser`)

`app/models/current.rb`:

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :admin_user, to: :session, allow_nil: true
end
```

`app/controllers/concerns/authentication.rb`:

```ruby
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?, :current_admin
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated? = resume_session.present?

    def current_admin = Current.admin_user

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      return nil unless (id = cookies.signed[:session_id])
      session = Session.includes(:admin_user).find_by(id: id)
      return nil unless session&.admin_user&.active?
      session
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(admin_user)
      admin_user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |new_session|
        Current.session = new_session
        cookies.signed.permanent[:session_id] = { value: new_session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session&.destroy
      cookies.delete(:session_id)
      Current.session = nil
    end
end
```

`app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  include Authentication
  allow_browser versions: :modern

  helper_method :can?

  private
    def can?(action)
      current_admin.present? && AdminAuth::AccessPolicy.allows?(role: current_admin.role, action: action)
    end

    def authorize!(action)
      redirect_to root_path, alert: "คุณไม่มีสิทธิ์เข้าถึงส่วนนี้" unless can?(action)
    end
end
```

`app/controllers/sessions_controller.rb` (audit wiring comes in Task 8):

```ruby
class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_session_url, alert: "พยายามเข้าสู่ระบบบ่อยเกินไป กรุณาลองใหม่ภายหลัง" }

  def new
  end

  def create
    admin = AdminUser.authenticate_by(email_address: params[:email_address], password: params[:password])
    if admin&.active?
      start_new_session_for(admin)
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "อีเมลหรือรหัสผ่านไม่ถูกต้อง"
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, notice: "ออกจากระบบแล้ว"
  end
end
```

`config/routes.rb`:

```ruby
Rails.application.routes.draw do
  root "home#show"
  resource :session, only: %i[new create destroy]
end
```

Minimal home (full version in Task 6) — `app/controllers/home_controller.rb`:

```ruby
class HomeController < ApplicationController
  def show
  end
end
```

`app/views/home/show.html.erb`:

```erb
<h1 class="text-2xl font-bold text-ink">หน้าหลัก</h1>
```

- [ ] **Step 4: CI theme tokens** — replace `app/assets/tailwind/application.css`:

```css
@import "tailwindcss";

@theme {
  /* Tokens verified against carbonmice-main-fe source — see spec §10 */
  --font-sans: "IBM Plex Sans Thai", ui-sans-serif, system-ui, sans-serif;
  --color-primary: #0065D0;
  --color-primary-dark: #0052A8;
  --color-danger: #D92D20;
  --color-ink: #101828;
  --color-body: #333741;
  --color-surface: #F9FAFB;
}
```

- [ ] **Step 5: Layout, flash, logo**

```bash
cp docs/assets/ci/logo-carbonmice.png app/assets/images/logo-carbonmice.png
```

`app/views/layouts/application.html.erb` (replace generated):

```erb
<!DOCTYPE html>
<html lang="th">
  <head>
    <title>Carbon MICE Admin</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Thai:wght@400;500;600;700&display=swap" rel="stylesheet">
    <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>
  <body class="bg-surface text-body font-sans min-h-screen">
    <%= render "shared/flash" %>
    <%= yield %>
  </body>
</html>
```

`app/views/shared/_flash.html.erb`:

```erb
<% if notice %>
  <div class="mx-auto mt-4 max-w-3xl rounded-lg bg-green-50 px-4 py-3 text-green-800"><%= notice %></div>
<% end %>
<% if alert %>
  <div class="mx-auto mt-4 max-w-3xl rounded-lg bg-red-50 px-4 py-3 text-danger"><%= alert %></div>
<% end %>
```

`app/views/sessions/new.html.erb` (layout mirrors `docs/assets/ci/login-reference.png`):

```erb
<div class="min-h-screen grid lg:grid-cols-2">
  <div class="flex flex-col items-center justify-center bg-white px-8 py-16">
    <%= image_tag "logo-carbonmice.png", alt: "carbon MICE", class: "w-56 mb-10" %>
    <h1 class="text-3xl font-bold text-ink">ยินดีต้อนรับ</h1>
    <p class="mt-2 mb-8 text-body/70">เข้าสู่ระบบผู้ดูแลด้วยอีเมลของคุณ</p>

    <%= form_with url: session_path, class: "w-full max-w-sm space-y-5" do |f| %>
      <div>
        <%= f.label :email_address, "อีเมล", class: "mb-1 block font-medium text-ink" %>
        <%= f.email_field :email_address, required: true, autofocus: true,
              class: "w-full rounded-lg border border-gray-300 px-4 py-2.5 focus:outline-none focus:ring-2 focus:ring-primary" %>
      </div>
      <div>
        <%= f.label :password, "รหัสผ่าน", class: "mb-1 block font-medium text-ink" %>
        <%= f.password_field :password, required: true,
              class: "w-full rounded-lg border border-gray-300 px-4 py-2.5 focus:outline-none focus:ring-2 focus:ring-primary" %>
      </div>
      <%= f.submit "เข้าสู่ระบบ",
            class: "w-full cursor-pointer rounded-lg bg-primary py-3 font-semibold text-white hover:bg-primary-dark" %>
    <% end %>
  </div>
  <div class="hidden lg:block bg-[#7FA8D9]"></div>
</div>
```

- [ ] **Step 6: Run to verify pass**

```bash
bin/rails test test/controllers/sessions_controller_test.rb
```

Expected: PASS, 5 runs, 0 failures.

- [ ] **Step 7: Eyeball the login page**

```bash
bin/dev
```

Open http://localhost:3000 — expect redirect to login, IBM Plex Sans Thai, blue #0065D0 button, carbon MICE logo. Stop the server.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat: session auth with rate-limited login styled to carbonmice CI"
```

---

### Task 6: Authenticated shell — sidebar nav gated by role

**Files:**
- Create: `app/views/shared/_sidebar.html.erb`
- Modify: `app/views/layouts/application.html.erb`, `app/views/home/show.html.erb`
- Test: `test/controllers/home_controller_test.rb`

- [ ] **Step 1: Write the failing test** — `test/controllers/home_controller_test.rb`

```ruby
require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  def login_as(role)
    admin = AdminUser.create!(email_address: "#{role}@pea.co.th",
                              password: "password-for-tests", name: role.to_s, role: role)
    post session_path, params: { email_address: admin.email_address, password: "password-for-tests" }
    admin
  end

  test "superadmin sees admin-management and audit links" do
    login_as(:superadmin)
    get root_path
    assert_select "nav a[href=?]", "/admin_users"
    assert_select "nav a[href=?]", "/audit_logs"
  end

  test "admin sees neither admin-management nor audit links" do
    login_as(:admin)
    get root_path
    assert_select "nav a[href=?]", "/admin_users", count: 0
    assert_select "nav a[href=?]", "/audit_logs", count: 0
  end

  test "viewer sees only the home link" do
    login_as(:viewer)
    get root_path
    assert_select "nav a[href=?]", "/", count: 1
    assert_select "nav a[href=?]", "/admin_users", count: 0
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bin/rails test test/controllers/home_controller_test.rb
```

Expected: FAIL — no `<nav>` rendered yet.

- [ ] **Step 3: Implement sidebar + layout**

`app/views/shared/_sidebar.html.erb` (the `/admin_users` and `/audit_logs` pages are built in Tasks 9–10; links are policy-gated so nothing 404s for roles that can't see them):

```erb
<aside class="flex w-64 flex-col border-r border-gray-200 bg-white">
  <div class="flex items-center gap-2 px-6 py-5">
    <%= image_tag "logo-carbonmice.png", alt: "carbon MICE", class: "w-36" %>
  </div>
  <nav class="flex-1 space-y-1 px-3">
    <%= link_to "หน้าหลัก", root_path, class: "block rounded-lg px-3 py-2 font-medium hover:bg-surface" %>
    <% if can?(:manage_admin_users) %>
      <%= link_to "บัญชีผู้ดูแล", "/admin_users", class: "block rounded-lg px-3 py-2 font-medium hover:bg-surface" %>
    <% end %>
    <% if can?(:view_audit_log) %>
      <%= link_to "บันทึกการใช้งาน", "/audit_logs", class: "block rounded-lg px-3 py-2 font-medium hover:bg-surface" %>
    <% end %>
  </nav>
  <div class="border-t border-gray-200 px-6 py-4">
    <p class="text-sm font-medium text-ink"><%= current_admin.name %></p>
    <p class="text-xs text-body/60"><%= current_admin.role %></p>
    <%= button_to "ออกจากระบบ", session_path, method: :delete,
          class: "mt-2 cursor-pointer text-sm text-danger" %>
  </div>
</aside>
```

In `app/views/layouts/application.html.erb`, replace the `<body>` content:

```erb
<body class="bg-surface text-body font-sans min-h-screen">
  <% if authenticated? %>
    <div class="flex min-h-screen">
      <%= render "shared/sidebar" %>
      <main class="flex-1 p-8">
        <%= render "shared/flash" %>
        <%= yield %>
      </main>
    </div>
  <% else %>
    <%= render "shared/flash" %>
    <%= yield %>
  <% end %>
</body>
```

`app/views/home/show.html.erb`:

```erb
<h1 class="text-2xl font-bold text-ink">หน้าหลัก</h1>
<p class="mt-2 text-body/70">ระบบหลังบ้าน Carbon MICE — แดชบอร์ดจะเพิ่มใน Phase ถัดไป</p>
```

- [ ] **Step 4: Run to verify pass**

```bash
bin/rails test test/controllers/home_controller_test.rb
```

Expected: PASS, 3 runs, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: authenticated shell with role-gated sidebar"
```

---

### Task 7: Audit log — model, port, adapter (TDD)

**Files:**
- Create: migration `db/migrate/*_create_audit_logs.rb`, `app/models/audit_log.rb`, `app/domain/ports.rb`, `app/domain/ports/audit_recorder.rb`, `app/adapters/persistence/ar_audit_recorder.rb`
- Test: `test/models/audit_log_test.rb`, `test/adapters/ar_audit_recorder_test.rb`

- [ ] **Step 1: Migration**

```bash
bin/rails generate migration CreateAuditLogs
```

Replace content:

```ruby
class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.references :actor, foreign_key: { to_table: :admin_users }, null: true
      t.string   :actor_email
      t.string   :action, null: false
      t.string   :target_type
      t.string   :target_id          # string: Go-owned tables use UUID keys
      t.jsonb    :change_set, null: false, default: {}
      t.string   :ip_address
      t.string   :user_agent
      t.datetime :created_at, null: false   # insert-only: no updated_at
    end
    add_index :audit_logs, :action
    add_index :audit_logs, :created_at
  end
end
```

- [ ] **Step 2: Write the failing tests**

`test/models/audit_log_test.rb`:

```ruby
require "test_helper"

class AuditLogTest < ActiveSupport::TestCase
  test "entries are insert-only" do
    log = AuditLog.create!(action: "auth.login_succeeded", actor_email: "a@pea.co.th")
    assert_raises(ActiveRecord::ReadOnlyRecord) { log.update!(action: "tampered") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { log.destroy! }
  end

  test "requires an action" do
    refute AuditLog.new.valid?
  end
end
```

`test/adapters/ar_audit_recorder_test.rb`:

```ruby
require "test_helper"

class ArAuditRecorderTest < ActiveSupport::TestCase
  setup do
    @actor = AdminUser.create!(email_address: "sa@pea.co.th",
                               password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  test "records a data-change entry with actor and target" do
    target = AdminUser.create!(email_address: "t@pea.co.th",
                               password: "password-for-tests", name: "เป้า")
    Persistence::ArAuditRecorder.new.record(
      action: "admin_users.updated", actor: @actor, target: target,
      changes: { "role" => { "from" => "viewer", "to" => "admin" } },
      ip: "10.0.0.1", user_agent: "test"
    )
    log = AuditLog.order(:id).last
    assert_equal "admin_users.updated", log.action
    assert_equal @actor.id, log.actor_id
    assert_equal "sa@pea.co.th", log.actor_email
    assert_equal "AdminUser", log.target_type
    assert_equal target.id.to_s, log.target_id
    assert_equal({ "role" => { "from" => "viewer", "to" => "admin" } }, log.change_set)
  end

  test "records an actorless entry (failed login)" do
    Persistence::ArAuditRecorder.new.record(
      action: "auth.login_failed", actor_email: "ghost@pea.co.th", ip: "10.0.0.2", user_agent: "test"
    )
    log = AuditLog.order(:id).last
    assert_nil log.actor_id
    assert_equal "ghost@pea.co.th", log.actor_email
  end
end
```

- [ ] **Step 3: Run to verify failure**

```bash
bin/rails db:migrate && bin/rails test test/models/audit_log_test.rb test/adapters/ar_audit_recorder_test.rb
```

Expected: FAIL — `uninitialized constant AuditLog`.

- [ ] **Step 4: Implement**

`app/models/audit_log.rb`:

```ruby
class AuditLog < ApplicationRecord
  belongs_to :actor, class_name: "AdminUser", optional: true

  validates :action, presence: true

  # Insert-only: the application has no path to rewrite history.
  def readonly? = persisted?
end
```

`app/domain/ports.rb`:

```ruby
# Ports are duck-typed interfaces between the domain and adapters.
# Each port module documents its contract; adapters implement it.
module Ports
  class Error < StandardError; end
  class NotFound < Error; end
  class ValidationFailed < Error; end
end
```

`app/domain/ports/audit_recorder.rb`:

```ruby
module Ports
  # Contract:
  #   record(action:, actor: nil, actor_email: nil, target: nil, changes: {}, ip: nil, user_agent: nil)
  # - action: namespaced string, e.g. "auth.login_succeeded", "admin_users.created"
  # - actor: the acting admin (nil for failed logins); actor_email falls back to actor's email
  # - target: any record responding to #id (stored as string) — Go-owned rows use UUIDs
  # Raises on persistence failure: an unrecorded action must not silently succeed.
  module AuditRecorder
  end
end
```

`app/adapters/persistence/ar_audit_recorder.rb`:

```ruby
module Persistence
  class ArAuditRecorder
    def record(action:, actor: nil, actor_email: nil, target: nil, changes: {}, ip: nil, user_agent: nil)
      AuditLog.create!(
        actor: actor,
        actor_email: actor_email || actor&.email_address,
        action: action,
        target_type: target&.class&.name,
        target_id: target&.id&.to_s,
        change_set: changes,
        ip_address: ip,
        user_agent: user_agent
      )
    end
  end
end
```

- [ ] **Step 5: Run to verify pass**

```bash
bin/rails test test/models/audit_log_test.rb test/adapters/ar_audit_recorder_test.rb
```

Expected: PASS, 4 runs, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: insert-only audit log with recorder port and AR adapter"
```

---

### Task 8: Record auth events

**Files:**
- Modify: `app/controllers/sessions_controller.rb`
- Test: append to `test/controllers/sessions_controller_test.rb`

- [ ] **Step 1: Write the failing tests** — append inside `SessionsControllerTest`:

```ruby
  test "successful login writes an audit entry" do
    assert_difference -> { AuditLog.where(action: "auth.login_succeeded").count } do
      post session_path, params: { email_address: "admin@pea.co.th", password: "password-for-tests" }
    end
    assert_equal @admin.id, AuditLog.order(:id).last.actor_id
  end

  test "failed login writes an audit entry with the attempted email" do
    assert_difference -> { AuditLog.where(action: "auth.login_failed").count } do
      post session_path, params: { email_address: "Nobody@pea.co.th", password: "wrong-password" }
    end
    assert_equal "nobody@pea.co.th", AuditLog.order(:id).last.actor_email
  end

  test "logout writes an audit entry" do
    post session_path, params: { email_address: "admin@pea.co.th", password: "password-for-tests" }
    assert_difference -> { AuditLog.where(action: "auth.logout").count } do
      delete session_path
    end
  end
```

- [ ] **Step 2: Run to verify failure**

```bash
bin/rails test test/controllers/sessions_controller_test.rb
```

Expected: 3 new tests FAIL (0 audit rows written).

- [ ] **Step 3: Wire the recorder** — update `SessionsController#create`/`#destroy` and add the private helper:

```ruby
  def create
    admin = AdminUser.authenticate_by(email_address: params[:email_address], password: params[:password])
    if admin&.active?
      start_new_session_for(admin)
      audit_recorder.record(action: "auth.login_succeeded", actor: admin,
                            ip: request.remote_ip, user_agent: request.user_agent)
      redirect_to after_authentication_url
    else
      audit_recorder.record(action: "auth.login_failed",
                            actor_email: params[:email_address].to_s.strip.downcase,
                            ip: request.remote_ip, user_agent: request.user_agent)
      redirect_to new_session_path, alert: "อีเมลหรือรหัสผ่านไม่ถูกต้อง"
    end
  end

  def destroy
    audit_recorder.record(action: "auth.logout", actor: current_admin,
                          ip: request.remote_ip, user_agent: request.user_agent)
    terminate_session
    redirect_to new_session_path, notice: "ออกจากระบบแล้ว"
  end

  private
    def audit_recorder = Persistence::ArAuditRecorder.new
```

- [ ] **Step 4: Run to verify pass**

```bash
bin/rails test test/controllers/sessions_controller_test.rb
```

Expected: PASS, 8 runs, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: audit auth events (login success/failure, logout)"
```

---

### Task 9: Admin account management (superadmin only)

**Files:**
- Create: `app/domain/result.rb`, `app/domain/ports/admin_user_repository.rb`, `app/adapters/persistence/ar_admin_user_repository.rb`, `app/domain/admin_auth/create_admin.rb`, `app/domain/admin_auth/update_admin.rb`, `app/controllers/admin_users_controller.rb`, `app/views/admin_users/index.html.erb`, `app/views/admin_users/new.html.erb`, `app/views/admin_users/edit.html.erb`
- Modify: `config/routes.rb`
- Test: `test/domain/admin_auth/manage_admins_test.rb`, `test/controllers/admin_users_controller_test.rb`

- [ ] **Step 1: Write the failing domain test** — `test/domain/admin_auth/manage_admins_test.rb`

Uses hand-rolled fakes — this is the pattern all Plan-2 use-case tests follow:

```ruby
require_relative "../../domain_helper"

FakeRow = Struct.new(:id, :email_address, :name, :role, :active, keyword_init: true)
FakeActor = Struct.new(:id, :role, :email_address, keyword_init: true)

class FakeAdminRepo
  attr_reader :rows
  def initialize = @rows = {}
  def create(email_address:, name:, password:, role:)
    raise Ports::ValidationFailed, "อีเมลซ้ำ" if @rows.values.any? { |r| r.email_address == email_address }
    row = FakeRow.new(id: @rows.size + 1, email_address:, name:, role: role.to_s, active: true)
    @rows[row.id] = row
  end
  def find(id) = @rows.fetch(id) { raise Ports::NotFound }
  def update(id, **attrs)
    row = find(id)
    attrs.each { |k, v| row[k] = v }
    row
  end
end

class FakeAudit
  attr_reader :entries
  def initialize = @entries = []
  def record(**entry) = @entries << entry
end

class ManageAdminsTest < Minitest::Test
  def setup
    @repo = FakeAdminRepo.new
    @audit = FakeAudit.new
    @superadmin = FakeActor.new(id: 99, role: "superadmin", email_address: "sa@pea.co.th")
    @admin = FakeActor.new(id: 98, role: "admin", email_address: "ad@pea.co.th")
  end

  def test_superadmin_creates_admin_and_audits
    result = AdminAuth::CreateAdmin.call(
      actor: @superadmin, repo: @repo, audit: @audit,
      attrs: { email_address: "new@pea.co.th", name: "ใหม่", password: "password-for-tests", role: "admin" }
    )
    assert result.success?
    assert_equal "admin_users.created", @audit.entries.last[:action]
  end

  def test_non_superadmin_is_denied
    result = AdminAuth::CreateAdmin.call(
      actor: @admin, repo: @repo, audit: @audit,
      attrs: { email_address: "new@pea.co.th", name: "ใหม่", password: "password-for-tests", role: "admin" }
    )
    assert result.failure?
    assert_empty @audit.entries
  end

  def test_duplicate_email_returns_failure
    @repo.create(email_address: "dup@pea.co.th", name: "เดิม", password: "password-for-tests", role: "admin")
    result = AdminAuth::CreateAdmin.call(
      actor: @superadmin, repo: @repo, audit: @audit,
      attrs: { email_address: "dup@pea.co.th", name: "ซ้ำ", password: "password-for-tests", role: "admin" }
    )
    assert result.failure?
    assert_equal "อีเมลซ้ำ", result.error
  end

  def test_update_audits_the_diff
    row = @repo.create(email_address: "x@pea.co.th", name: "เอ็กซ์", password: "password-for-tests", role: "viewer")
    result = AdminAuth::UpdateAdmin.call(actor: @superadmin, repo: @repo, audit: @audit,
                                         id: row.id, attrs: { role: "admin" })
    assert result.success?
    assert_equal({ "role" => { "from" => "viewer", "to" => "admin" } }, @audit.entries.last[:changes])
  end

  def test_cannot_deactivate_yourself
    row = @repo.create(email_address: "sa@pea.co.th", name: "ตัวเอง", password: "password-for-tests", role: "superadmin")
    me = FakeActor.new(id: row.id, role: "superadmin", email_address: "sa@pea.co.th")
    result = AdminAuth::UpdateAdmin.call(actor: me, repo: @repo, audit: @audit,
                                         id: row.id, attrs: { active: false })
    assert result.failure?
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
ruby -Itest test/domain/admin_auth/manage_admins_test.rb
```

Expected: FAIL — `uninitialized constant AdminAuth::CreateAdmin`.

- [ ] **Step 3: Implement domain pieces**

`app/domain/result.rb`:

```ruby
# Shared return value for use cases: expected failures are values, not exceptions.
class Result
  attr_reader :value, :error

  def self.success(value = nil) = new(success: true, value: value)
  def self.failure(error) = new(success: false, error: error)

  def initialize(success:, value: nil, error: nil)
    @success, @value, @error = success, value, error
  end

  def success? = @success
  def failure? = !@success
end
```

`app/domain/ports/admin_user_repository.rb`:

```ruby
module Ports
  # Contract:
  #   create(email_address:, name:, password:, role:) -> record (responds to id/email_address/name/role/active)
  #   find(id) -> record | raises Ports::NotFound
  #   update(id, **attrs) -> record | raises Ports::NotFound, Ports::ValidationFailed
  #   all_ordered -> [record] newest first
  module AdminUserRepository
  end
end
```

`app/domain/admin_auth/create_admin.rb`:

```ruby
module AdminAuth
  class CreateAdmin
    def self.call(actor:, attrs:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการบัญชีผู้ดูแล") unless AccessPolicy.allows?(role: actor.role, action: :manage_admin_users)

      record = repo.create(**attrs)
      audit.record(action: "admin_users.created", actor: actor, target: record,
                   changes: { "email_address" => record.email_address, "role" => record.role })
      Result.success(record)
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
```

`app/domain/admin_auth/update_admin.rb`:

```ruby
module AdminAuth
  class UpdateAdmin
    def self.call(actor:, id:, attrs:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการบัญชีผู้ดูแล") unless AccessPolicy.allows?(role: actor.role, action: :manage_admin_users)
      return Result.failure("ไม่สามารถปิดหรือลดสิทธิ์บัญชีของตัวเองได้") if actor.id.to_s == id.to_s

      before = repo.find(id)
      snapshot = attrs.keys.to_h { |k| [k.to_s, before.public_send(k)] }
      record = repo.update(id, **attrs)
      diff = attrs.keys.to_h { |k| [k.to_s, { "from" => snapshot[k.to_s], "to" => record.public_send(k) }] }
      audit.record(action: "admin_users.updated", actor: actor, target: record, changes: diff)
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบบัญชีผู้ดูแล")
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
```

- [ ] **Step 4: Run domain tests to verify pass**

```bash
ruby -Itest test/domain/admin_auth/manage_admins_test.rb
```

Expected: PASS, 5 runs, 0 failures.

- [ ] **Step 5: Write the failing controller test** — `test/controllers/admin_users_controller_test.rb`

```ruby
require "test_helper"

class AdminUsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user, password: "password-for-tests")
    post session_path, params: { email_address: user.email_address, password: password }
  end

  test "superadmin lists, creates and updates admins with audit entries" do
    login(@superadmin)
    get admin_users_path
    assert_response :success

    assert_difference -> { AdminUser.count } => 1,
                      -> { AuditLog.where(action: "admin_users.created").count } => 1 do
      post admin_users_path, params: { admin_user: {
        email_address: "new@pea.co.th", name: "ใหม่", password: "password-for-tests", role: "admin" } }
    end
    assert_redirected_to admin_users_path

    target = AdminUser.find_by!(email_address: "new@pea.co.th")
    assert_difference -> { AuditLog.where(action: "admin_users.updated").count } => 1 do
      patch admin_user_path(target), params: { admin_user: { role: "viewer", active: false } }
    end
    assert target.reload.viewer?
    refute target.reload.active?
  end

  test "admin role is denied" do
    admin = AdminUser.create!(email_address: "ad@pea.co.th",
                              password: "password-for-tests", name: "แอด", role: :admin)
    login(admin)
    get admin_users_path
    assert_redirected_to root_path
  end

  test "superadmin cannot deactivate own account" do
    login(@superadmin)
    patch admin_user_path(@superadmin), params: { admin_user: { active: false } }
    assert @superadmin.reload.active?
  end
end
```

- [ ] **Step 6: Run to verify failure**

```bash
bin/rails test test/controllers/admin_users_controller_test.rb
```

Expected: FAIL — undefined `admin_users_path`.

- [ ] **Step 7: Implement adapter, controller, routes, views**

`app/adapters/persistence/ar_admin_user_repository.rb`:

```ruby
module Persistence
  class ArAdminUserRepository
    def create(email_address:, name:, password:, role:)
      AdminUser.create!(email_address:, name:, password:, role:)
    rescue ActiveRecord::RecordInvalid => e
      raise Ports::ValidationFailed, e.record.errors.full_messages.to_sentence
    end

    def find(id)
      AdminUser.find(id)
    rescue ActiveRecord::RecordNotFound
      raise Ports::NotFound
    end

    def update(id, **attrs)
      record = find(id)
      record.update!(**attrs)
      record
    rescue ActiveRecord::RecordInvalid => e
      raise Ports::ValidationFailed, e.record.errors.full_messages.to_sentence
    end

    def all_ordered = AdminUser.order(created_at: :desc)
  end
end
```

`config/routes.rb` — add:

```ruby
  resources :admin_users, only: %i[index new create edit update]
```

`app/controllers/admin_users_controller.rb`:

```ruby
class AdminUsersController < ApplicationController
  before_action -> { authorize!(:manage_admin_users) }

  def index
    @admin_users = repo.all_ordered
  end

  def new
  end

  def create
    result = AdminAuth::CreateAdmin.call(actor: current_admin, repo: repo, audit: audit,
                                         attrs: create_params.to_h.symbolize_keys)
    if result.success?
      redirect_to admin_users_path, notice: "สร้างบัญชีผู้ดูแลแล้ว"
    else
      redirect_to new_admin_user_path, alert: result.error
    end
  end

  def edit
    @admin_user = repo.find(params[:id])
  end

  def update
    result = AdminAuth::UpdateAdmin.call(actor: current_admin, repo: repo, audit: audit,
                                         id: params[:id], attrs: update_params.to_h.symbolize_keys)
    if result.success?
      redirect_to admin_users_path, notice: "บันทึกการแก้ไขแล้ว"
    else
      redirect_to admin_users_path, alert: result.error
    end
  end

  private
    def create_params = params.require(:admin_user).permit(:email_address, :name, :password, :role)
    def update_params = params.require(:admin_user).permit(:name, :role, :active)
    def repo = Persistence::ArAdminUserRepository.new
    def audit = Persistence::ArAuditRecorder.new
end
```

`app/views/admin_users/index.html.erb`:

```erb
<div class="flex items-center justify-between">
  <h1 class="text-2xl font-bold text-ink">บัญชีผู้ดูแล</h1>
  <%= link_to "เพิ่มผู้ดูแล", new_admin_user_path,
        class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark" %>
</div>

<table class="mt-6 w-full rounded-xl bg-white shadow-sm">
  <thead>
    <tr class="border-b border-gray-200 text-left text-sm text-body/60">
      <th class="px-4 py-3">ชื่อ</th>
      <th class="px-4 py-3">อีเมล</th>
      <th class="px-4 py-3">สิทธิ์</th>
      <th class="px-4 py-3">สถานะ</th>
      <th class="px-4 py-3"></th>
    </tr>
  </thead>
  <tbody>
    <% @admin_users.each do |admin| %>
      <tr class="border-b border-gray-100">
        <td class="px-4 py-3 font-medium text-ink"><%= admin.name %></td>
        <td class="px-4 py-3"><%= admin.email_address %></td>
        <td class="px-4 py-3"><%= admin.role %></td>
        <td class="px-4 py-3">
          <% if admin.active? %>
            <span class="rounded-full bg-green-50 px-3 py-1 text-sm text-green-700">ใช้งาน</span>
          <% else %>
            <span class="rounded-full bg-gray-100 px-3 py-1 text-sm text-body/60">ปิดใช้งาน</span>
          <% end %>
        </td>
        <td class="px-4 py-3 text-right"><%= link_to "แก้ไข", edit_admin_user_path(admin), class: "text-primary" %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

`app/views/admin_users/new.html.erb`:

```erb
<h1 class="text-2xl font-bold text-ink">เพิ่มผู้ดูแล</h1>

<%= form_with url: admin_users_path, scope: :admin_user, class: "mt-6 max-w-md space-y-5" do |f| %>
  <div>
    <%= f.label :name, "ชื่อ", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :name, required: true, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :email_address, "อีเมล", class: "mb-1 block font-medium text-ink" %>
    <%= f.email_field :email_address, required: true, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :password, "รหัสผ่าน (อย่างน้อย 12 ตัวอักษร)", class: "mb-1 block font-medium text-ink" %>
    <%= f.password_field :password, required: true, minlength: 12, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :role, "สิทธิ์", class: "mb-1 block font-medium text-ink" %>
    <%= f.select :role, [["Viewer", "viewer"], ["Admin", "admin"], ["Superadmin", "superadmin"]],
          {}, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <%= f.submit "สร้างบัญชี", class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
<% end %>
```

`app/views/admin_users/edit.html.erb`:

```erb
<h1 class="text-2xl font-bold text-ink">แก้ไขผู้ดูแล: <%= @admin_user.email_address %></h1>

<%= form_with url: admin_user_path(@admin_user), method: :patch, scope: :admin_user, class: "mt-6 max-w-md space-y-5" do |f| %>
  <div>
    <%= f.label :name, "ชื่อ", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :name, value: @admin_user.name, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :role, "สิทธิ์", class: "mb-1 block font-medium text-ink" %>
    <%= f.select :role, [["Viewer", "viewer"], ["Admin", "admin"], ["Superadmin", "superadmin"]],
          { selected: @admin_user.role }, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div class="flex items-center gap-2">
    <%= f.check_box :active, checked: @admin_user.active?, class: "h-4 w-4" %>
    <%= f.label :active, "เปิดใช้งานบัญชี", class: "font-medium text-ink" %>
  </div>
  <%= f.submit "บันทึก", class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
<% end %>
```

- [ ] **Step 8: Run all tests to verify pass**

```bash
bin/rails test && ruby -Itest test/domain/admin_auth/manage_admins_test.rb
```

Expected: PASS everywhere, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add -A && git commit -m "feat: superadmin manages admin accounts via audited use cases"
```

---

### Task 10: Audit log viewer (superadmin only)

**Files:**
- Create: `app/domain/ports/audit_log_query.rb`, `app/domain/audit/list_entries.rb`, `app/adapters/persistence/ar_audit_log_query.rb`, `app/controllers/audit_logs_controller.rb`, `app/views/audit_logs/index.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/audit_logs_controller_test.rb`

- [ ] **Step 1: Write the failing test** — `test/controllers/audit_logs_controller_test.rb`

```ruby
require "test_helper"

class AuditLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user)
    post session_path, params: { email_address: user.email_address, password: "password-for-tests" }
  end

  test "superadmin sees entries newest first" do
    login(@superadmin)   # writes auth.login_succeeded
    get audit_logs_path
    assert_response :success
    assert_select "td", text: "auth.login_succeeded"
  end

  test "filters by action prefix" do
    login(@superadmin)
    AuditLog.create!(action: "admin_users.created", actor: @superadmin, actor_email: @superadmin.email_address)
    get audit_logs_path, params: { action_prefix: "admin_users." }
    assert_select "td", text: "admin_users.created"
    assert_select "td", text: "auth.login_succeeded", count: 0
  end

  test "admin and viewer are denied" do
    %i[admin viewer].each do |role|
      user = AdminUser.create!(email_address: "#{role}@pea.co.th",
                               password: "password-for-tests", name: role.to_s, role: role)
      login(user)
      get audit_logs_path
      assert_redirected_to root_path
      delete session_path
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bin/rails test test/controllers/audit_logs_controller_test.rb
```

Expected: FAIL — undefined `audit_logs_path`.

- [ ] **Step 3: Implement**

`app/domain/ports/audit_log_query.rb`:

```ruby
module Ports
  # Contract:
  #   entries(actor_id: nil, action_prefix: nil, from: nil, to: nil, limit: 200) -> [entry]
  # Entries respond to: created_at, actor_email, action, target_type, target_id, change_set, ip_address.
  # Newest first.
  module AuditLogQuery
  end
end
```

`app/domain/audit/list_entries.rb`:

```ruby
module Audit
  class ListEntries
    def self.call(actor:, query:, filters: {})
      return Result.failure("คุณไม่มีสิทธิ์ดูบันทึกการใช้งาน") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :view_audit_log)

      Result.success(query.entries(**filters))
    end
  end
end
```

`app/adapters/persistence/ar_audit_log_query.rb`:

```ruby
module Persistence
  class ArAuditLogQuery
    def entries(actor_id: nil, action_prefix: nil, from: nil, to: nil, limit: 200)
      scope = AuditLog.order(created_at: :desc).limit(limit)
      scope = scope.where(actor_id: actor_id) if actor_id.present?
      scope = scope.where("action LIKE ?", "#{AuditLog.sanitize_sql_like(action_prefix)}%") if action_prefix.present?
      scope = scope.where(created_at: from..) if from.present?
      scope = scope.where(created_at: ..to) if to.present?
      scope
    end
  end
end
```

`config/routes.rb` — add:

```ruby
  resources :audit_logs, only: :index
```

`app/controllers/audit_logs_controller.rb`:

```ruby
class AuditLogsController < ApplicationController
  before_action -> { authorize!(:view_audit_log) }

  def index
    result = Audit::ListEntries.call(actor: current_admin, query: Persistence::ArAuditLogQuery.new,
                                     filters: filters)
    @entries = result.value
  end

  private
    def filters
      {
        actor_id: params[:actor_id].presence,
        action_prefix: params[:action_prefix].presence,
        from: params[:from].presence,
        to: params[:to].presence
      }.compact
    end
end
```

`app/views/audit_logs/index.html.erb`:

```erb
<h1 class="text-2xl font-bold text-ink">บันทึกการใช้งาน</h1>

<%= form_with url: audit_logs_path, method: :get, class: "mt-4 flex flex-wrap items-end gap-3" do |f| %>
  <div>
    <%= f.label :action_prefix, "ประเภท", class: "mb-1 block text-sm font-medium text-ink" %>
    <%= f.select :action_prefix,
          [["ทั้งหมด", ""], ["การเข้าสู่ระบบ", "auth."], ["บัญชีผู้ดูแล", "admin_users."]],
          { selected: params[:action_prefix] }, class: "rounded-lg border border-gray-300 px-3 py-2" %>
  </div>
  <div>
    <%= f.label :from, "ตั้งแต่", class: "mb-1 block text-sm font-medium text-ink" %>
    <%= f.date_field :from, value: params[:from], class: "rounded-lg border border-gray-300 px-3 py-2" %>
  </div>
  <div>
    <%= f.label :to, "ถึง", class: "mb-1 block text-sm font-medium text-ink" %>
    <%= f.date_field :to, value: params[:to], class: "rounded-lg border border-gray-300 px-3 py-2" %>
  </div>
  <%= f.submit "กรอง", class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
<% end %>

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
        <td class="whitespace-nowrap px-4 py-3"><%= e.created_at.in_time_zone("Asia/Bangkok").strftime("%d/%m/%Y %H:%M:%S") %></td>
        <td class="px-4 py-3"><%= e.actor_email %></td>
        <td class="px-4 py-3 font-medium text-ink"><%= e.action %></td>
        <td class="px-4 py-3"><%= [e.target_type, e.target_id].compact.join("#") %></td>
        <td class="px-4 py-3 font-mono text-xs"><%= e.change_set.presence&.to_json %></td>
        <td class="px-4 py-3"><%= e.ip_address %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

- [ ] **Step 4: Run to verify pass**

```bash
bin/rails test test/controllers/audit_logs_controller_test.rb
```

Expected: PASS, 3 runs, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: superadmin audit log viewer with filters"
```

---

### Task 11: Seeds, README, full green run

**Files:**
- Modify: `db/seeds.rb`, `README.md`

- [ ] **Step 1: Seeds** — replace `db/seeds.rb`:

```ruby
# First superadmin — credentials from ENV only, never hardcoded.
if ENV["SEED_SUPERADMIN_EMAIL"].present?
  AdminUser.find_or_create_by!(email_address: ENV["SEED_SUPERADMIN_EMAIL"]) do |u|
    u.name = ENV.fetch("SEED_SUPERADMIN_NAME", "Super Admin")
    u.password = ENV.fetch("SEED_SUPERADMIN_PASSWORD")
    u.role = :superadmin
  end
  puts "Superadmin ensured: #{ENV["SEED_SUPERADMIN_EMAIL"]}"
else
  puts "Skipped superadmin seed (SEED_SUPERADMIN_EMAIL not set)"
end
```

- [ ] **Step 2: README** — replace `README.md`:

```markdown
# Carbonmice Admin

Admin panel for the carbonmice platform. Rails 8.1.3 / Ruby 4.0.0, hexagonal
architecture (`app/domain` = pure PORO + ports, `app/adapters` = ActiveRecord
implementations, controllers/views = web adapter).

## Database rules (important)

- Shares the carbonmice Postgres. This app owns ONLY the `admin` schema.
- NEVER write a migration that touches the `public` schema — it belongs to the
  Go backend (`carbonmice-main-go-be`, goose migrations).
- `structure.sql` is dumped with `--schema=admin` on purpose.
- Production should use a dedicated DB role: full rights on `admin`,
  table-level grants on `public`.

## Setup

1. Start the dev Postgres: `docker compose up -d postgres` in `../carbonmice-main-go-be`.
2. `cp .env.example .env` and fill values (DB creds from the Go repo's `.env`).
3. `bin/setup`
4. Seed the first superadmin: set `SEED_SUPERADMIN_*` in `.env`, then `bin/rails db:seed`.
5. `bin/dev` → http://localhost:3000

## Tests

- Everything: `bin/rails test` (uses its own `carbonmice_admin_test` DB)
- Domain only (no Rails): `ruby -Itest test/domain/**/*_test.rb`

## Notes

- Login rate limiting uses `Rails.cache` — configure a shared cache store
  (e.g. Redis) in production for it to work across processes.
- Audit log is insert-only; visibility is controlled solely by
  `AdminAuth::AccessPolicy` (currently superadmin).
- Spec: `docs/superpowers/specs/2026-06-12-admin-panel-design.md`.
  Phase 2 plan (events / app users / master data / dashboard + `db/core_structure.sql`)
  is written after this plan executes.
```

- [ ] **Step 3: Full verification**

```bash
bin/rails test
ruby -Itest test/domain/admin_auth/access_policy_test.rb
ruby -Itest test/domain/admin_auth/manage_admins_test.rb
```

Expected: all PASS, 0 failures, 0 errors.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: seeds, README and full test pass for admin foundation"
```

---

## Roadmap after this plan

**Plan 2/2 (written once this plan is executed and reviewed):** `Core::` read models over Go-owned tables, `db/core_structure.sql` test fixture dumped from the dev DB, events module (list/search + status state machine), app users module (quota/role), master data CRUD (emission factors, categories, units, pricing tiers), dashboard summary, Capybara system tests for the critical flows, and deployment (Rails Dockerfile + GitLab CI following the team pipeline) — all following the port/adapter/use-case/test patterns established here, all writes audited via `Ports::AuditRecorder`.
