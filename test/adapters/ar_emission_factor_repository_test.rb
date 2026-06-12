require "test_helper"

class ArEmissionFactorRepositoryTest < ActiveSupport::TestCase
  setup { @repo = Persistence::ArEmissionFactorRepository.new }

  test "create persists with stamp and duplicate identifier maps to ValidationFailed" do
    category_id = create_core_emission_factor!(identifier: "ef_seed").carbon_category_id
    record = @repo.create(
      { identifier: "ef_brand_new", name: "ใหม่", source: "TGO", value_per_unit: 1.25,
        unit_title: "kgCO2e/kg", carbon_category_id: category_id },
      created_by: "carbonmice-admin:sa@pea.co.th"
    )
    assert_equal "carbonmice-admin:sa@pea.co.th", record.reload.created_by

    err = assert_raises(Ports::ValidationFailed) do
      @repo.create(
        { identifier: "ef_brand_new", name: "ซ้ำ", source: "TGO", value_per_unit: 1.0,
          unit_title: "kgCO2e/kg", carbon_category_id: category_id },
        created_by: "carbonmice-admin:sa@pea.co.th"
      )
    end
    assert_match "identifier", err.message
  end

  test "list searches identifier and name, filters by category" do
    f1 = create_core_emission_factor!(identifier: "ef_car_test", name: "รถยนต์ทดสอบ")
    create_core_emission_factor!(identifier: "ef_food_test", name: "อาหารทดสอบ")
    assert_equal 1, @repo.list(search: "ef_car").size
    assert_equal 1, @repo.list(search: "อาหาร").size
    assert_equal 1, @repo.list(category_id: f1.carbon_category_id).size
  end

  test "update and soft_delete stamp updated_by; deleted factors vanish" do
    f = create_core_emission_factor!(identifier: "ef_gone")
    @repo.update(f.id, { value_per_unit: 9.99 }, updated_by: "carbonmice-admin:sa@pea.co.th")
    assert_equal 9.99, f.reload.value_per_unit.to_f

    @repo.soft_delete(f.id, updated_by: "carbonmice-admin:sa@pea.co.th")
    assert f.reload.deleted_at.present?
    assert_raises(Ports::NotFound) { @repo.find(f.id) }
    assert_equal 0, @repo.list(search: "ef_gone").size
  end

  test "value beyond numeric(12,6) maps to ValidationFailed" do
    f = create_core_emission_factor!(identifier: "ef_range")
    assert_raises(Ports::ValidationFailed) do
      @repo.update(f.id, { value_per_unit: 10_000_000_000 }, updated_by: "carbonmice-admin:sa@pea.co.th")
    end
  end
end
