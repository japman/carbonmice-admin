require_relative "../../domain_helper"

FakeTier = Struct.new(:id, :min_participants, :max_participants, :price_per_person,
                      :min_emission, :max_emission, :price_per_emission,
                      :carbon_offset_source_id, :updated_by, keyword_init: true)

class FakeTierRepo
  attr_reader :rows
  def initialize(rows) = @rows = rows
  def find(id) = @rows.fetch(id) { raise Ports::NotFound }
  def list(source_id: nil)
    rows = @rows.values
    rows = rows.select { |r| r.carbon_offset_source_id == source_id } if source_id
    rows
  end
  def update(id, attrs, updated_by:)
    row = find(id)
    attrs.each { |k, v| row[k] = v }
    row.updated_by = updated_by
    row
  end
end

class PricingTiersDomainTest < Minitest::Test
  def setup
    @audit_entries = []
    entries = @audit_entries
    @audit = Object.new
    @audit.define_singleton_method(:record) { |**entry| entries << entry }
    @admin = Struct.new(:id, :role, :email_address).new(1, "admin", "ad@pea.co.th")
  end

  def event_repo
    FakeTierRepo.new(
      "t1" => FakeTier.new(id: "t1", min_participants: 1, max_participants: 1000, price_per_person: 5.0),
      "t2" => FakeTier.new(id: "t2", min_participants: 1001, max_participants: 2000, price_per_person: 4.0)
    )
  end

  def test_event_tier_price_update_audits
    repo = event_repo
    result = MasterData::UpdateEventPricingTier.call(actor: @admin, id: "t1",
                                                     attrs: { price_per_person: "6.5" },
                                                     repo: repo, audit: @audit)
    assert result.success?
    assert_equal 6.5, repo.find("t1").price_per_person
    assert_equal "master_data.event_tier_updated", @audit_entries.last[:action]
  end

  def test_event_tier_overlap_is_rejected
    repo = event_repo
    result = MasterData::UpdateEventPricingTier.call(actor: @admin, id: "t1",
                                                     attrs: { max_participants: "1500" },
                                                     repo: repo, audit: @audit)
    assert result.failure?
    assert_equal 1000, repo.find("t1").max_participants
  end

  def test_event_tier_bounds_validated
    repo = event_repo
    assert MasterData::UpdateEventPricingTier.call(actor: @admin, id: "t1",
      attrs: { min_participants: "-5" }, repo: repo, audit: @audit).failure?
    assert MasterData::UpdateEventPricingTier.call(actor: @admin, id: "t1",
      attrs: { min_participants: "500", max_participants: "100" }, repo: repo, audit: @audit).failure?
    assert MasterData::UpdateEventPricingTier.call(actor: @admin, id: "t1",
      attrs: { price_per_person: "free" }, repo: repo, audit: @audit).failure?
  end

  def test_offset_tier_overlap_scoped_to_source
    repo = FakeTierRepo.new(
      "o1" => FakeTier.new(id: "o1", min_emission: 0, max_emission: 100,
                           price_per_emission: 100.0, carbon_offset_source_id: "s1"),
      "o2" => FakeTier.new(id: "o2", min_emission: 0, max_emission: 100,
                           price_per_emission: 90.0, carbon_offset_source_id: "s2")
    )
    # overlapping range exists in s2 but NOT in s1 → extending o1 within s1 only checks s1
    result = MasterData::UpdateOffsetPricingTier.call(actor: @admin, id: "o1",
                                                      attrs: { max_emission: "150" },
                                                      repo: repo, audit: @audit)
    assert result.success?
    assert_equal 150, repo.find("o1").max_emission
    assert_equal "master_data.offset_tier_updated", @audit_entries.last[:action]
  end

  def test_viewer_denied
    viewer = Struct.new(:id, :role, :email_address).new(2, "viewer", "v@pea.co.th")
    assert MasterData::UpdateEventPricingTier.call(actor: viewer, id: "t1",
      attrs: { price_per_person: "1" }, repo: event_repo, audit: @audit).failure?
    assert_empty @audit_entries
  end
end
