require "test_helper"

class ArAppUserRepositoryTest < ActiveSupport::TestCase
  setup { @repo = Persistence::ArAppUserRepository.new }

  test "find raises NotFound for unknown and malformed ids" do
    assert_raises(Ports::NotFound) { @repo.find(SecureRandom.uuid) }
    assert_raises(Ports::NotFound) { @repo.find("oops") }
  end

  test "list searches email and display name" do
    create_core_user!(email: "somchai@example.com", display_name: "สมชาย ใจดี")
    create_core_user!(email: "other@example.com", display_name: "คนอื่น")
    assert_equal 1, @repo.list(search: "somchai").size
    assert_equal 1, @repo.list(search: "สมชาย").size
    assert_equal 2, @repo.list.size
  end

  test "update_role and update_quota stamp updated_by" do
    user = create_core_user!(email: "stamp@example.com", role: "user", quota: 0)
    @repo.update_role(user.id, role: "admin", updated_by: "carbonmice-admin:sa@pea.co.th")
    @repo.update_quota(user.id, quota: 7, updated_by: "carbonmice-admin:sa@pea.co.th")
    user.reload
    assert_equal "admin", user.role
    assert_equal 7, user.event_quota
    assert_equal "carbonmice-admin:sa@pea.co.th", user.updated_by
  end
end
