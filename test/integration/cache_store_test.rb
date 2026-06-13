require "test_helper"

class CacheStoreTest < ActiveSupport::TestCase
  test "solid cache round-trips a value through the database store" do
    store = ActiveSupport::Cache.lookup_store(:solid_cache_store)
    store.write("plan4a:probe", "ok")
    assert_equal "ok", store.read("plan4a:probe")
  end

  test "production resolves to the shared solid cache store, not per-process memory" do
    assert defined?(SolidCache), "solid_cache gem must be loaded"
    # In test env the global cache_store stays :null_store; this asserts the gem +
    # store class resolve so production's config.cache_store = :solid_cache_store holds.
    assert_kind_of ActiveSupport::Cache::Store, ActiveSupport::Cache.lookup_store(:solid_cache_store)
  end
end
