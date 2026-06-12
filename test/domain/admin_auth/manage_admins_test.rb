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

  def test_update_by_non_superadmin_is_denied
    row = @repo.create(email_address: "y@pea.co.th", name: "วาย", password: "password-for-tests", role: "viewer")
    result = AdminAuth::UpdateAdmin.call(actor: @admin, repo: @repo, audit: @audit,
                                         id: row.id, attrs: { role: "admin" })
    assert result.failure?
    assert_empty @audit.entries
  end

  def test_update_of_unknown_id_fails_gracefully
    result = AdminAuth::UpdateAdmin.call(actor: @superadmin, repo: @repo, audit: @audit,
                                         id: 12345, attrs: { role: "admin" })
    assert result.failure?
    assert_equal "ไม่พบบัญชีผู้ดูแล", result.error
  end

  def test_active_diff_is_recorded_with_booleans
    row = @repo.create(email_address: "z@pea.co.th", name: "แซด", password: "password-for-tests", role: "admin")
    result = AdminAuth::UpdateAdmin.call(actor: @superadmin, repo: @repo, audit: @audit,
                                         id: row.id, attrs: { active: false })
    assert result.success?
    assert_equal({ "active" => { "from" => true, "to" => false } }, @audit.entries.last[:changes])
  end
end
