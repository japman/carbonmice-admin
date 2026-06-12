require "test_helper"

class ArEventRepositoryTest < ActiveSupport::TestCase
  setup { @repo = Persistence::ArEventRepository.new }

  test "find raises NotFound for unknown and malformed ids" do
    assert_raises(Ports::NotFound) { @repo.find(SecureRandom.uuid) }
    assert_raises(Ports::NotFound) { @repo.find("not-a-uuid") }
  end

  test "find excludes soft-deleted events" do
    event = create_core_event!
    ActiveRecord::Base.connection.execute(
      "UPDATE public.events SET deleted_at = now() WHERE id = '#{event.id}'"
    )
    assert_raises(Ports::NotFound) { @repo.find(event.id) }
  end

  test "list searches both names and filters by status" do
    create_core_event!(name_thai: "งานหนังสือ", name_eng: "Book Fair", status: "collecting")
    create_core_event!(name_thai: "งานวิ่ง", name_eng: "Run", status: "draft")

    assert_equal 1, @repo.list(search: "หนังสือ").size
    assert_equal 1, @repo.list(search: "book").size          # ILIKE, case-insensitive
    assert_equal 1, @repo.list(status: "draft").size
    assert_equal 0, @repo.list(search: "100%งาน").size       # LIKE wildcards escaped
  end

  test "list paginates with a has-next sentinel row" do
    (Persistence::ArEventRepository::PAGE_SIZE + 1).times { |i| create_core_event!(name_eng: "E#{i}") }
    page1 = @repo.list(page: 1)
    assert_equal Persistence::ArEventRepository::PAGE_SIZE + 1, page1.size
    page2 = @repo.list(page: 2)
    assert_equal 1, page2.size
  end

  test "update_status stamps updated_by" do
    event = create_core_event!(status: "collecting")
    @repo.update_status(event.id, to: "in_progress", updated_by: "carbonmice-admin:sa@pea.co.th")
    event.reload
    assert_equal "in_progress", event.event_status
    assert_equal "carbonmice-admin:sa@pea.co.th", event.updated_by
  end

  test "update_details writes only given attrs" do
    event = create_core_event!(name_thai: "เดิม", province: "เชียงใหม่")
    @repo.update_details(event.id, { name_thai: "ใหม่" }, updated_by: "carbonmice-admin:sa@pea.co.th")
    event.reload
    assert_equal "ใหม่", event.name_thai
    assert_equal "เชียงใหม่", event.province
  end
end
